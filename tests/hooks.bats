#!/usr/bin/env bats
#
# The plugin's hooks, run the way Claude Code runs them: JSON on stdin for the
# prose hook, nothing for the doctor.

setup_file() {
  REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  export REPO
  CONSUMER="$(mktemp -d)"
  export CONSUMER
  printf 'StylesPath = styles\nPackages = %s/package\n' "${REPO}" \
    >"${CONSUMER}/.vale.ini"
  vale --config="${CONSUMER}/.vale.ini" sync >/dev/null
  VALE_CONFIG_PATH="${CONSUMER}/.vale.ini"
  export VALE_CONFIG_PATH
  # Keeps a developer's own cspell word list out of the result.
  CLAUDE_CONFIG_DIR="$(mktemp -d)"
  export CLAUDE_CONFIG_DIR
  # A global git config that has the commit hook, so the doctor's verdict
  # doesn't depend on the developer's own.
  GIT_CONFIG_GLOBAL="${CONSUMER}/gitconfig"
  export GIT_CONFIG_GLOBAL
  git config set --file "${GIT_CONFIG_GLOBAL}" hook.vale-agent-prose.command true
}

teardown_file() {
  rm -rf "${CONSUMER}" "${CLAUDE_CONFIG_DIR}"
}

setup() {
  WORK="$(mktemp -d)"
  unset CLAUDE_PLUGIN_DATA
}

# A data directory whose default config reads the styles in $1.
default_config() {
  CLAUDE_PLUGIN_DATA="${WORK}/data"
  export CLAUDE_PLUGIN_DATA
  mkdir -p "${CLAUDE_PLUGIN_DATA}/vale"
  printf 'StylesPath = %s\n' "$1" >"${CLAUDE_PLUGIN_DATA}/vale/.vale.ini"
}

teardown() {
  rm -rf "${WORK}"
}

readonly TRIAD='The gate needs clarity, discipline, and rigor before anyone trusts it.'
readonly NEG='A readability score names no span, so it licenses no rewrite here.'

lint_hook() {
  "${REPO}/scripts/lint-prose.sh"
}

doctor() {
  "${REPO}/scripts/doctor.sh"
}

lint_file() {
  printf '{"tool_input":{"file_path":"%s"}}' "$1" | lint_hook
}

@test "a file outside a repository reports every finding" {
  printf '%s\n' "${TRIAD}" >"${WORK}/notes.md"
  run lint_file "${WORK}/notes.md"
  [ "${status}" -eq 0 ]
  [[ "$(jq -r .hookSpecificOutput.additionalContext <<<"${output}")" \
    == *'AgentProse.AbstractTriad'* ]]
}

@test "a tracked file leaves out a paragraph the edit didn't touch" {
  git -C "${WORK}" init -q
  printf '%s\n' "${TRIAD}" >"${WORK}/notes.md"
  git -C "${WORK}" add notes.md
  printf '\n%s\n' "${NEG}" >>"${WORK}/notes.md"
  run lint_file "${WORK}/notes.md"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'AgentProse.NegDeduction'* ]]
  [[ "${output}" != *'AgentProse.AbstractTriad'* ]]
}

readonly FIRST='The loader reads the file and checks the header'
readonly SHORT='before it parses the rest.'
readonly LONG='before it parses the rest of the body and every section after it in order, and then it validates them all.'

# The finding sits on the sentence's first line, which the edit never touched.
@test "an edit that lengthens a comment's sentence reports from the line it starts on" {
  git -C "${WORK}" init -q
  printf '# %s\n# %s\nx = 1\n' "${FIRST}" "${SHORT}" >"${WORK}/a.py"
  git -C "${WORK}" add a.py
  printf '# %s\n# %s\nx = 1\n' "${FIRST}" "${LONG}" >"${WORK}/a.py"
  run lint_file "${WORK}/a.py"
  [[ "${output}" == *'a.py:1:3:Std.Readability.SentenceLength'* ]]
}

@test "an edit that lengthens a paragraph's sentence reports from the line it starts on" {
  git -C "${WORK}" init -q
  printf '%s\n%s\n' "${FIRST}" "${SHORT}" >"${WORK}/notes.md"
  git -C "${WORK}" add notes.md
  printf '%s\n%s\n' "${FIRST}" "${LONG}" >"${WORK}/notes.md"
  run lint_file "${WORK}/notes.md"
  [[ "${output}" == *'notes.md:1:1:Std.Readability.SentenceLength'* ]]
}

# A code edit beside a comment isn't an edit to the comment.
@test "a code edit leaves the comment above it out" {
  git -C "${WORK}" init -q
  printf '# %s %s\nx = 1\n' "${FIRST}" "${LONG}" >"${WORK}/a.py"
  git -C "${WORK}" add a.py
  printf '# %s %s\nx = 2\n' "${FIRST}" "${LONG}" >"${WORK}/a.py"
  run lint_file "${WORK}/a.py"
  [[ "${output}" != *'SentenceLength'* ]]
}

# Joining two lines can make a sentence that wasn't there.
@test "a deletion inside a comment reports the comment" {
  git -C "${WORK}" init -q
  printf '# %s\n# %s.\n# %s\nx = 1\n' "${FIRST}" 'Then it stops' "${LONG}" >"${WORK}/a.py"
  git -C "${WORK}" add a.py
  printf '# %s\n# %s\nx = 1\n' "${FIRST}" "${LONG}" >"${WORK}/a.py"
  run lint_file "${WORK}/a.py"
  [[ "${output}" == *'a.py:1:3:Std.Readability.SentenceLength'* ]]
}

@test "a file the repository ignores reports nothing" {
  git -C "${WORK}" init -q
  printf 'scratch.md\n' >"${WORK}/.gitignore"
  printf '%s\n' "${TRIAD}" >"${WORK}/scratch.md"
  run lint_file "${WORK}/scratch.md"
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "input with no file path exits 0 and says nothing" {
  run lint_hook <<<'{}'
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "the doctor says nothing where Vale has styles to load" {
  cd "${CONSUMER}"
  run doctor
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "the doctor names an unsynced package and leaves it unsynced" {
  printf 'StylesPath = styles\nPackages = %s/package\n' "${REPO}" \
    >"${WORK}/.vale.ini"
  mkdir "${WORK}/styles"
  cd "${WORK}"
  unset VALE_CONFIG_PATH
  run doctor
  [ "${status}" -eq 0 ]
  [[ "$(jq -r .systemMessage <<<"${output}")" == *"haven't synced"*'/vale-agent-prose:setup'* ]]
  [ ! -e "${WORK}/styles/AgentProse" ]
}

@test "the doctor names a Vale too old to place findings" {
  mkdir "${WORK}/bin"
  printf '#!/usr/bin/env bash\n[[ "$1" == --version ]] && exec echo "vale version 3.22.0"\nexec %s "$@"\n' \
    "$(command -v vale)" >"${WORK}/bin/vale"
  chmod +x "${WORK}/bin/vale"
  cd "${CONSUMER}"
  PATH="${WORK}/bin:${PATH}" run doctor
  [ "${status}" -eq 0 ]
  [[ "$(jq -r .systemMessage <<<"${output}")" == *'Vale 3.22.0 is older than 3.23.0'* ]]
}

@test "the doctor without jq still prints valid JSON naming jq" {
  mkdir "${WORK}/bin"
  local tool
  for tool in bash cat dirname sort vale; do
    ln -s "$(command -v "${tool}")" "${WORK}/bin/${tool}"
  done
  cd "${CONSUMER}"
  PATH="${WORK}/bin" run doctor
  [ "${status}" -eq 0 ]
  [[ "$(jq -r .systemMessage <<<"${output}")" == *"jq isn't on the PATH"* ]]
}

@test "the doctor names a missing commit hook" {
  cd "${CONSUMER}"
  GIT_CONFIG_GLOBAL="${WORK}/gitconfig" run doctor
  [ "${status}" -eq 0 ]
  [[ "$(jq -r .systemMessage <<<"${output}")" == *'/vale-agent-prose:setup'* ]]
}

@test "the doctor names a git too old to run a hook from config" {
  mkdir "${WORK}/bin"
  printf '#!/usr/bin/env bash\n[[ "$1" == --version ]] && exec echo "git version 2.53.0"\nexec %s "$@"\n' \
    "$(command -v git)" >"${WORK}/bin/git"
  chmod +x "${WORK}/bin/git"
  cd "${CONSUMER}"
  PATH="${WORK}/bin:${PATH}" run doctor
  [ "${status}" -eq 0 ]
  [[ "$(jq -r .systemMessage <<<"${output}")" == *'git 2.53.0 is older than 2.54.0'* ]]
}

@test "the doctor names a missing config" {
  cd "${WORK}"
  unset VALE_CONFIG_PATH
  run doctor
  [ "${status}" -eq 0 ]
  [[ "$(jq -r .systemMessage <<<"${output}")" == *"can't load a configuration"* ]]
}

@test "a directory with no Vale config lints through the default config" {
  default_config "${CONSUMER}/styles"
  printf '%s\n' "${TRIAD}" >"${WORK}/notes.md"
  cd "${WORK}"
  unset VALE_CONFIG_PATH
  run lint_file "${WORK}/notes.md"
  [ "${status}" -eq 0 ]
  [[ "$(jq -r .hookSpecificOutput.additionalContext <<<"${output}")" \
    == *'AgentProse.AbstractTriad'* ]]
}

@test "the doctor says nothing where the default config has styles" {
  default_config "${CONSUMER}/styles"
  cd "${WORK}"
  unset VALE_CONFIG_PATH
  run doctor
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

# A fresh clone's config fails to load until a sync creates its styles
# directory, and the default config must not stand in for it.
@test "the doctor names a fresh clone's config rather than using the default" {
  default_config "${CONSUMER}/styles"
  printf 'StylesPath = styles\nPackages = %s/package\n' "${REPO}" \
    >"${WORK}/.vale.ini"
  cd "${WORK}"
  unset VALE_CONFIG_PATH
  run doctor
  [ "${status}" -eq 0 ]
  [[ "$(jq -r .systemMessage <<<"${output}")" == *"can't load a configuration"*'/vale-agent-prose:setup'* ]]
}

@test "tools/doctor prints each problem as a line and exits 1" {
  cd "${CONSUMER}"
  GIT_CONFIG_GLOBAL="${WORK}/gitconfig" run "${REPO}/tools/doctor"
  [ "${status}" -eq 1 ]
  [[ "${output}" == 'Nothing checks your commit messages'*'/vale-agent-prose:setup.' ]]
}

@test "tools/doctor exits 0 and says nothing where nothing is wrong" {
  cd "${CONSUMER}"
  run "${REPO}/tools/doctor"
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "tools/doctor changes nothing in the data directory" {
  cd "${WORK}"
  unset VALE_CONFIG_PATH
  run "${REPO}/tools/doctor" "${WORK}/data"
  [ ! -e "${WORK}/data" ]
}

@test "tools/doctor with two operands is a usage error" {
  run "${REPO}/tools/doctor" a b
  [ "${status}" -eq 2 ]
}

@test "the doctor names a default config that hasn't synced" {
  mkdir "${WORK}/empty"
  default_config "${WORK}/empty"
  cd "${WORK}"
  unset VALE_CONFIG_PATH
  run doctor
  [ "${status}" -eq 0 ]
  [[ "$(jq -r .systemMessage <<<"${output}")" == *'has no styles yet'* ]]
}
