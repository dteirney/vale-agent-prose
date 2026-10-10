#!/usr/bin/env bats
#
# The plugin's hooks, run the way Claude Code runs them: JSON on stdin for the
# prose hook, nothing for the doctor.

bats_require_minimum_version 1.5.0

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
  # A test that takes write access away gives it back here, should it fail.
  chmod -R u+w "${WORK}"
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

# An edit of file $2 in session $1, with a data directory to keep alerts in.
edit_in() {
  CLAUDE_PLUGIN_DATA="${CLAUDE_PLUGIN_DATA:-${WORK}/data}" lint_hook \
    <<<"$(printf '{"session_id":"%s","tool_input":{"file_path":"%s"}}' "$1" "$2")"
}

# An edit like edit_in's, from a Claude Code process that has since exited.
edit_then_exit() {
  (
    edit_in "$1" "$2" &
    wait
  )
}

# Hook event $1 for session $2, sent to the hook that deletes session folders.
session_event() {
  CLAUDE_PLUGIN_DATA="${CLAUDE_PLUGIN_DATA:-${WORK}/data}" \
    "${REPO}/scripts/prune-sessions.sh" \
    <<<"$(printf '{"hook_event_name":"%s","session_id":"%s"}' "$1" "$2")"
}

# The rechecks of rule $1 in the last run's stderr, one per line.
rechecks() {
  jq -r --arg rule "$1" 'select(.rule == $rule) | .recheck' <<<"${stderr}"
}

readonly TRIAD_REWORDED='Our gate needs clarity, discipline, and rigor before a reviewer trusts it.'
readonly TRIAD_FIXED='The gate needs one passing test before anyone trusts it.'

@test "a file outside a repository reports every alert" {
  printf '%s\n' "${TRIAD}" >"${WORK}/notes.md"
  run lint_file "${WORK}/notes.md"
  [ "${status}" -eq 0 ]
  [[ "$(jq -r .hookSpecificOutput.additionalContext <<<"${output}")" \
    == *'AgentProse.AbstractTriad'* ]]
}

@test "the hook claims no enforcement, because it can't block" {
  printf '%s\n' "${TRIAD}" >"${WORK}/notes.md"
  run lint_file "${WORK}/notes.md"
  [[ "$(jq -r .hookSpecificOutput.additionalContext <<<"${output}")" \
    == *'AgentProse.AbstractTriad'* ]]
  [[ "${output}" != *'Enforced'* ]]
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

# The alert sits on the sentence's first line, which the edit never touched.
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

@test "the doctor names a Vale too old to place alerts" {
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
  [ "${status}" -eq 64 ]
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

@test "an alert left standing reports persisted at the next edit" {
  printf '%s\n' "${TRIAD}" >"${WORK}/notes.md"
  edit_in s1 "${WORK}/notes.md" >/dev/null
  printf '\n%s\n' "${NEG}" >>"${WORK}/notes.md"
  run --separate-stderr edit_in s1 "${WORK}/notes.md"
  [ "${status}" -eq 0 ]
  [ "$(rechecks AgentProse.AbstractTriad)" = persisted ]
  [ "$(jq -r 'select(.rule == "AgentProse.AbstractTriad") | .config' <<<"${stderr}")" = own ]
}

@test "a rewrite of the flagged words reports absent" {
  printf '%s\n' "${TRIAD}" >"${WORK}/notes.md"
  edit_in s1 "${WORK}/notes.md" >/dev/null
  printf '%s\n' "${TRIAD_FIXED}" >"${WORK}/notes.md"
  run --separate-stderr edit_in s1 "${WORK}/notes.md"
  [ "${status}" -eq 0 ]
  [ "$(rechecks AgentProse.AbstractTriad)" = absent ]
}

@test "a rewrite elsewhere on the line reports persisted" {
  printf '%s\n' "${TRIAD}" >"${WORK}/notes.md"
  edit_in s1 "${WORK}/notes.md" >/dev/null
  printf '%s\n' "${TRIAD_REWORDED}" >"${WORK}/notes.md"
  run --separate-stderr edit_in s1 "${WORK}/notes.md"
  [ "$(rechecks AgentProse.AbstractTriad)" = persisted ]
}

@test "two alerts on the same flagged words recheck one occurrence each" {
  printf '%s\n\n%s\n' "${TRIAD}" "${TRIAD_REWORDED}" >"${WORK}/notes.md"
  edit_in s1 "${WORK}/notes.md" >/dev/null
  printf '%s\n\n%s\n' "${TRIAD_FIXED}" "${TRIAD_REWORDED}" >"${WORK}/notes.md"
  run --separate-stderr edit_in s1 "${WORK}/notes.md"
  [ "$(rechecks AgentProse.AbstractTriad | sort | paste -sd , -)" = absent,persisted ]
}

readonly LONG_A='This sentence keeps going and going with clause after clause after clause so that it sails far past the twenty-five word threshold the rule enforces here.'
readonly LONG_B='This sentence keeps going and going with clause after clause after clause so that it sails far past the twenty-five word threshold the rule enforces here every single time.'

# Vale names only a long sentence's first word, so the message tells them apart.
@test "a fixed long sentence reports absent beside another that starts the same" {
  printf '%s\n\n%s\n' "${LONG_A}" "${LONG_B}" >"${WORK}/notes.md"
  edit_in s1 "${WORK}/notes.md" >/dev/null
  printf 'Short.\n\n%s\n' "${LONG_B}" >"${WORK}/notes.md"
  run --separate-stderr edit_in s1 "${WORK}/notes.md"
  [ "$(jq -r 'select(.rule == "Std.Readability.SentenceLength" and .line == 1) | .recheck' <<<"${stderr}")" = absent ]
  [ "$(jq -r 'select(.rule == "Std.Readability.SentenceLength" and .line == 3) | .recheck' <<<"${stderr}")" = persisted ]
}

readonly DENSE='The configuration determines which particular validation procedures execute automatically during every subsequent repository operation. Administrators occasionally misunderstand the relationship between individual validation procedures and the corresponding documentation requirements. Consequently, organizational documentation frequently contradicts the operational behavior that administrators observe in production environments. Additional complications originate whenever independent contributors introduce contradictory modifications simultaneously across multiple repositories. Eventually, accumulated inconsistencies necessitate comprehensive reconciliation activities involving considerable organizational coordination and substantial investigative documentation. Therefore, preventive verification remains considerably preferable to retrospective reconciliation whenever organizational resources permit. Experienced administrators recommend establishing automated verification procedures immediately after initial repository configuration. Unfortunately, organizational priorities frequently postpone verification infrastructure indefinitely until significant operational disruptions demonstrate its importance.'

# A metric alert's message carries its score, so a score that moves without
# clearing the rule still leaves the alert standing.
@test "a metric alert whose score moves reports persisted" {
  printf '%s\n' "${DENSE}" >"${WORK}/notes.md"
  edit_in s1 "${WORK}/notes.md" >/dev/null
  printf '%s Verification matters.\n' "${DENSE}" >"${WORK}/notes.md"
  run --separate-stderr edit_in s1 "${WORK}/notes.md"
  [ "$(rechecks AgentProse.FleschReadingEase)" = persisted ]
}

# The hook hands back only what the edit touched, and the recheck reads the
# whole file.
@test "an alert on a line the next edit didn't touch reports persisted" {
  git -C "${WORK}" init -q
  printf '%s\n' "${TRIAD}" >"${WORK}/notes.md"
  edit_in s1 "${WORK}/notes.md" >/dev/null
  git -C "${WORK}" add notes.md
  printf '\n%s\n' "${NEG}" >>"${WORK}/notes.md"
  run --separate-stderr edit_in s1 "${WORK}/notes.md"
  [[ "${output}" != *'AgentProse.AbstractTriad'* ]]
  [ "$(rechecks AgentProse.AbstractTriad)" = persisted ]
}

@test "an alert handed back from a tracked file gets a recheck" {
  git -C "${WORK}" init -q
  printf 'Intro.\n' >"${WORK}/notes.md"
  git -C "${WORK}" add notes.md
  printf '\n%s\n' "${TRIAD}" >>"${WORK}/notes.md"
  edit_in s1 "${WORK}/notes.md" >/dev/null
  printf 'Intro.\n\n%s\n' "${TRIAD_FIXED}" >"${WORK}/notes.md"
  run --separate-stderr edit_in s1 "${WORK}/notes.md"
  [ "$(rechecks AgentProse.AbstractTriad)" = absent ]
}

@test "an alert handed back again gets its own recheck" {
  printf '%s\n' "${TRIAD}" >"${WORK}/notes.md"
  edit_in s1 "${WORK}/notes.md" >/dev/null
  printf '%s\n' "${TRIAD_REWORDED}" >"${WORK}/notes.md"
  edit_in s1 "${WORK}/notes.md" >/dev/null 2>&1
  printf '%s\n' "${TRIAD_FIXED}" >"${WORK}/notes.md"
  run --separate-stderr edit_in s1 "${WORK}/notes.md"
  [ "$(rechecks AgentProse.AbstractTriad)" = absent ]
}

@test "an alert with no later edit writes nothing" {
  printf '%s\n' "${TRIAD}" >"${WORK}/notes.md"
  run --separate-stderr edit_in s1 "${WORK}/notes.md"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'AgentProse.AbstractTriad'* ]]
  [ -z "${stderr}" ]
}

@test "a second session's edit rechecks nothing from the first" {
  printf '%s\n' "${TRIAD}" >"${WORK}/notes.md"
  edit_in s1 "${WORK}/notes.md" >/dev/null
  run --separate-stderr edit_in s2 "${WORK}/notes.md"
  [ "${status}" -eq 0 ]
  [ -z "${stderr}" ]
}

@test "a recheck's line has the alert, its file, its lines and where it ran" {
  git -C "${WORK}" init -q
  default_config "${CONSUMER}/styles"
  cd "${WORK}"
  unset VALE_CONFIG_PATH
  printf 'Intro.\n%s\nOutro.\n' "${TRIAD}" >"${WORK}/notes.md"
  edit_in s1 "${WORK}/notes.md" >/dev/null
  run --separate-stderr edit_in s1 "${WORK}/notes.md"
  local line
  line="$(jq -c 'select(.rule == "AgentProse.AbstractTriad")' <<<"${stderr}")"
  [ "$(jq -r .match <<<"${line}")" = 'clarity, discipline, and rigor' ]
  [[ "$(jq -r .message <<<"${line}")" == 'Abstract-noun triad'* ]]
  [ "$(jq -r .file <<<"${line}")" = "$(pwd -P)/notes.md" ]
  [ "$(jq -r .type <<<"${line}")" = md ]
  [ "$(jq -r .line <<<"${line}")" = 2 ]
  [ "$(jq -c '[.lines[].line]' <<<"${line}")" = '[1,2,3]' ]
  [ "$(jq -r '.lines[1].text' <<<"${line}")" = "${TRIAD}" ]
  [ "$(jq -r .root <<<"${line}")" = "$(pwd -P)" ]
  [ "$(jq -r .config <<<"${line}")" = default ]
  [ "$(jq -r .version <<<"${line}")" = "$(jq -r .version "${REPO}/.claude-plugin/plugin.json")" ]
}

@test "a data directory the hook can't write to leaves it silent" {
  : >"${WORK}/data"
  printf '%s\n' "${TRIAD}" >"${WORK}/notes.md"
  edit_in s1 "${WORK}/notes.md" >/dev/null
  run --separate-stderr edit_in s1 "${WORK}/notes.md"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'AgentProse.AbstractTriad'* ]]
  [ -z "${stderr}" ]
}

@test "a session id that names another folder keeps nothing" {
  printf '%s\n' "${TRIAD}" >"${WORK}/notes.md"
  edit_in ../s1 "${WORK}/notes.md" >/dev/null
  run --separate-stderr edit_in ../s1 "${WORK}/notes.md"
  [ "${status}" -eq 0 ]
  [ -z "${stderr}" ]
  [ ! -e "${WORK}/data" ]
}

@test "an edit Vale can't lint rechecks nothing, and nor does the edit after" {
  printf '%s\n' "${TRIAD}" >"${WORK}/notes.md"
  edit_in s1 "${WORK}/notes.md" >/dev/null
  printf 'StylesPath = missing\n' >"${WORK}/broken.ini"
  VALE_CONFIG_PATH="${WORK}/broken.ini" edit_in s1 "${WORK}/notes.md" >/dev/null
  run --separate-stderr edit_in s1 "${WORK}/notes.md"
  [[ "${output}" == *'AgentProse.AbstractTriad'* ]]
  [ -z "${stderr}" ]
}

@test "the SessionEnd hook deletes the ending session's alerts" {
  printf '%s\n' "${TRIAD}" >"${WORK}/notes.md"
  edit_in s1 "${WORK}/notes.md" >/dev/null
  run --separate-stderr session_event SessionEnd s1
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ -z "${stderr}" ]
  run --separate-stderr edit_in s1 "${WORK}/notes.md"
  [ -z "${stderr}" ]
}

@test "the SessionEnd hook leaves another session's alerts" {
  printf '%s\n' "${TRIAD}" >"${WORK}/notes.md"
  edit_in s1 "${WORK}/notes.md" >/dev/null
  edit_in s2 "${WORK}/notes.md" >/dev/null
  session_event SessionEnd s2
  run --separate-stderr edit_in s1 "${WORK}/notes.md"
  [ "$(rechecks AgentProse.AbstractTriad)" = persisted ]
}

@test "a session id that names another folder deletes nothing" {
  printf '%s\n' "${TRIAD}" >"${WORK}/notes.md"
  edit_in s1 "${WORK}/notes.md" >/dev/null
  run --separate-stderr session_event SessionEnd ..
  [ "${status}" -eq 0 ]
  [ -z "${stderr}" ]
  run --separate-stderr edit_in s1 "${WORK}/notes.md"
  [ "$(rechecks AgentProse.AbstractTriad)" = persisted ]
}

@test "the SessionStart hook deletes the alerts of a session whose process exited" {
  printf '%s\n' "${TRIAD}" >"${WORK}/notes.md"
  edit_then_exit s1 "${WORK}/notes.md" >/dev/null
  run --separate-stderr session_event SessionStart s2
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ -z "${stderr}" ]
  run --separate-stderr edit_in s1 "${WORK}/notes.md"
  [ -z "${stderr}" ]
}

@test "the SessionStart hook leaves the alerts of a live session" {
  printf '%s\n' "${TRIAD}" >"${WORK}/notes.md"
  edit_in s1 "${WORK}/notes.md" >/dev/null
  session_event SessionStart s2
  run --separate-stderr edit_in s1 "${WORK}/notes.md"
  [ "$(rechecks AgentProse.AbstractTriad)" = persisted ]
}

# A crashed session that the user resumes is live again.
@test "a resumed session's alerts outlast the next session's start" {
  printf '%s\n' "${TRIAD}" >"${WORK}/notes.md"
  edit_then_exit s1 "${WORK}/notes.md" >/dev/null
  session_event SessionStart s1
  session_event SessionStart s2
  run --separate-stderr edit_in s1 "${WORK}/notes.md"
  [ "$(rechecks AgentProse.AbstractTriad)" = persisted ]
}

@test "both hooks exit 0 and say nothing when there's no session folder" {
  run --separate-stderr session_event SessionEnd s1
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ -z "${stderr}" ]
  run --separate-stderr session_event SessionStart s1
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ -z "${stderr}" ]
}

@test "both hooks exit 0 and say nothing when a folder can't be deleted" {
  printf '%s\n' "${TRIAD}" >"${WORK}/notes.md"
  edit_then_exit s1 "${WORK}/notes.md" >/dev/null
  chmod -R a-w "${WORK}/data"
  run --separate-stderr session_event SessionEnd s1
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ -z "${stderr}" ]
  run --separate-stderr session_event SessionStart s2
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [ -z "${stderr}" ]
}
