#!/usr/bin/env bats
#
# tools/lint-prose and tools/lint-branch-prose. The branch command's lint needs
# a commit to diff against, so a test that lints with it commits a base first.

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
}

teardown_file() {
  rm -rf "${CONSUMER}"
}

setup() {
  WORK="$(mktemp -d)"
}

teardown() {
  rm -rf "${WORK}"
}

readonly TRIAD='The gate needs clarity, discipline, and rigor before anyone trusts it.'

lint_prose() {
  "${REPO}/tools/lint-prose" "$@"
}

lint_branch() {
  "${REPO}/tools/lint-branch-prose" "$@"
}

commit_all() {
  git -C "${WORK}" add -A
  git -C "${WORK}" -c user.name=t -c user.email=t@t commit -qm "$1"
}

# A plugin data directory whose default config reads the synced styles, and no
# Vale config for the commands to find on their own.
data_dir() {
  mkdir -p "${WORK}/data/vale"
  printf 'StylesPath = %s/styles\n' "${CONSUMER}" >"${WORK}/data/vale/.vale.ini"
  unset VALE_CONFIG_PATH
}

@test "lint-prose walks a directory and exits 1 on an alert" {
  mkdir "${WORK}/docs"
  printf '%s\n' "${TRIAD}" >"${WORK}/docs/a.md"
  run lint_prose "${WORK}/docs"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *'a.md:1:'*'AgentProse.AbstractTriad'* ]]
}

@test "lint-prose exits 0 and says nothing on a clean file" {
  printf 'Run the gate.\n' >"${WORK}/a.md"
  run lint_prose "${WORK}/a.md"
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "lint-prose keeps a Vue file away from Vale" {
  printf '<template><p>%s</p></template>\n' "${TRIAD}" >"${WORK}/a.vue"
  run lint_prose "${WORK}/a.vue"
  [[ "${output}" != *'AgentProse'* ]]
}

@test "lint-prose past its limit prints a count per rule" {
  printf '%s\n\n%s\n' "${TRIAD}" "${TRIAD}" >"${WORK}/a.md"
  run lint_prose --limit 1 "${WORK}/a.md"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *'Alerts by rule:'* ]]
}

@test "lint-prose reads a zero-padded limit in decimal" {
  printf '%s\n\n%s\n' "${TRIAD}" "${TRIAD}" >"${WORK}/a.md"
  run lint_prose --limit 08 "${WORK}/a.md"
  [ "${status}" -eq 1 ]
  [[ "${output}" != *'value too great'* ]]
  [[ "${output}" != *'Alerts by rule:'* ]]
}

@test "lint-prose --by-file prints a count per file, highest first, and nothing else" {
  mkdir "${WORK}/docs"
  printf '%s\n' "${TRIAD}" >"${WORK}/docs/one.md"
  printf '%s\n\n%s\n' "${TRIAD}" "${TRIAD}" >"${WORK}/docs/two.md"
  printf 'Run the gate.\n' >"${WORK}/docs/clean.md"
  cd "${WORK}"
  run --separate-stderr lint_prose --by-file docs
  [ "${status}" -eq 1 ]
  [ "${#lines[@]}" -eq 2 ]
  [[ "${lines[0]}" =~ ^\ *2\ docs/two\.md$ ]]
  [[ "${lines[1]}" =~ ^\ *1\ docs/one\.md$ ]]
}

# cspell:ignore gaet
@test "lint-prose --by-file counts Vale alerts only" {
  printf '%s\n\nRun the gaet.\n' "${TRIAD}" >"${WORK}/mixed.md"
  printf 'Run the gaet.\n' >"${WORK}/spelling.md"
  cd "${WORK}"
  run lint_prose spelling.md
  [[ "${output}" == *'[cspell]'* ]]
  run --separate-stderr lint_prose --by-file mixed.md spelling.md
  [ "${status}" -eq 1 ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "${lines[0]}" =~ ^\ *1\ mixed\.md$ ]]
}

@test "lint-prose --by-file exits 1 when every alert is cspell's, and prints nothing" {
  printf 'Run the gaet.\n' >"${WORK}/a.md"
  cd "${WORK}"
  run --separate-stderr lint_prose --by-file a.md
  [ "${status}" -eq 1 ]
  [ -z "${output}" ]
}

@test "lint-prose --by-file with a missing path exits with no input" {
  run lint_prose --by-file "${WORK}/nothing-here"
  [ "${status}" -eq 66 ]
}

@test "lint-prose --by-file lists every file past the limit" {
  printf '%s\n' "${TRIAD}" >"${WORK}/a.md"
  printf '%s\n' "${TRIAD}" >"${WORK}/b.md"
  run --separate-stderr lint_prose --limit 1 --by-file "${WORK}/a.md" "${WORK}/b.md"
  [ "${status}" -eq 1 ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "lint-prose --by-file exits 0 and says nothing on a clean file" {
  printf 'Run the gate.\n' >"${WORK}/a.md"
  run lint_prose --by-file "${WORK}/a.md"
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "lint-prose --help describes --by-file" {
  run lint_prose --help
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'--by-file'* ]]
}

@test "lint-prose --data-dir lints a directory with no Vale config through the default one" {
  data_dir
  mkdir "${WORK}/docs"
  printf '%s\n' "${TRIAD}" >"${WORK}/docs/a.md"
  cd "${WORK}/docs"
  run --separate-stderr lint_prose --data-dir "${WORK}/data" --by-file a.md
  [ "${status}" -eq 1 ]
  [[ "${lines[0]}" =~ ^\ *1\ a\.md$ ]]
}

@test "lint-prose --data-dir leaves a directory's own Vale config in force" {
  data_dir
  mkdir "${WORK}/docs"
  printf 'StylesPath = %s/styles\n[*]\nAgentProse.AbstractTriad = NO\n' \
    "${CONSUMER}" >"${WORK}/docs/.vale.ini"
  printf '%s\n' "${TRIAD}" >"${WORK}/docs/a.md"
  cd "${WORK}/docs"
  run lint_prose --data-dir "${WORK}/data" a.md
  [[ "${output}" != *'AgentProse.AbstractTriad'* ]]
}

@test "lint-prose --data-dir with no directory after it is a usage error" {
  run lint_prose --data-dir
  [ "${status}" -eq 64 ]
}

@test "lint-prose --data-dir with a missing directory exits with no input" {
  printf 'Run the gate.\n' >"${WORK}/a.md"
  run --separate-stderr lint_prose --data-dir "${WORK}/nothing-here" "${WORK}/a.md"
  [ "${status}" -eq 66 ]
  [[ "${stderr}" == *"no such directory '${WORK}/nothing-here'"* ]]
}

@test "lint-prose --help describes --data-dir" {
  run lint_prose --help
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'--data-dir <dir>'* ]]
}

@test "lint-prose with no Vale config to find is a configuration error" {
  unset VALE_CONFIG_PATH
  printf '%s\n' "${TRIAD}" >"${WORK}/a.md"
  cd "${WORK}"
  run --separate-stderr lint_prose a.md
  [ "${status}" -eq 78 ]
  [ -z "${output}" ]
  [[ "${stderr}" == *'--data-dir'* ]]
}

@test "lint-prose --data-dir with no default config in it is a configuration error" {
  unset VALE_CONFIG_PATH
  mkdir "${WORK}/data"
  printf '%s\n' "${TRIAD}" >"${WORK}/a.md"
  cd "${WORK}"
  run --separate-stderr lint_prose --data-dir "${WORK}/data" a.md
  [ "${status}" -eq 78 ]
  [[ "${stderr}" == *'/vale-agent-prose:setup'* ]]
}

@test "lint-prose with a Vale config that can't load is a configuration error" {
  unset VALE_CONFIG_PATH
  printf 'StylesPath = no-such-styles\n[*]\nBasedOnStyles = Vale\n' >"${WORK}/.vale.ini"
  printf '%s\n' "${TRIAD}" >"${WORK}/a.md"
  cd "${WORK}"
  run --separate-stderr lint_prose a.md
  [ "${status}" -eq 78 ]
  [[ "${stderr}" == *'no-such-styles'* ]]
}

@test "lint-prose with an unsynced package warns that its config names no styles" {
  unset VALE_CONFIG_PATH
  printf 'StylesPath = styles\nPackages = %s/package\n' "${REPO}" >"${WORK}/.vale.ini"
  mkdir "${WORK}/styles"
  printf '%s\n' "${TRIAD}" >"${WORK}/a.md"
  cd "${WORK}"
  run --separate-stderr lint_prose a.md
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
  [[ "${stderr}" == *'names no styles'*'/vale-agent-prose:setup'* ]]
}

@test "lint-prose with synced styles warns nothing" {
  printf '%s\n' "${TRIAD}" >"${WORK}/a.md"
  run --separate-stderr lint_prose "${WORK}/a.md"
  [ "${status}" -eq 1 ]
  [ -z "${stderr}" ]
}

@test "lint-prose with no operand is a usage error" {
  run lint_prose
  [ "${status}" -eq 64 ]
}

@test "lint-prose with a missing path exits with no input" {
  run lint_prose "${WORK}/nothing-here"
  [ "${status}" -eq 66 ]
}

@test "lint-prose with a non-numeric limit is a usage error" {
  run lint_prose --limit many "${WORK}"
  [ "${status}" -eq 64 ]
}

@test "lint-branch-prose outside a repository is a usage error" {
  cd "${WORK}"
  run lint_branch
  [ "${status}" -eq 64 ]
  [[ "${output}" == *'not inside a git repository'* ]]
}

@test "lint-branch-prose with an unknown base is a usage error" {
  git -C "${WORK}" init -q
  cd "${WORK}"
  run lint_branch --base no-such-ref
  [ "${status}" -eq 64 ]
}

@test "lint-branch-prose reads a zero-padded limit in decimal" {
  git -C "${WORK}" init -q
  printf 'Run the gate.\n' >"${WORK}/a.md"
  git -C "${WORK}" add a.md
  git -C "${WORK}" -c user.name=t -c user.email=t@t commit -qm base
  printf '\n%s\n\n%s\n' "${TRIAD}" "${TRIAD}" >>"${WORK}/a.md"
  cd "${WORK}"
  run lint_branch --base HEAD --limit 08
  [ "${status}" -eq 1 ]
  [[ "${output}" != *'value too great'* ]]
  [[ "${output}" != *'Alerts by rule:'* ]]
}

@test "lint-branch-prose with a path reports only that file's added lines" {
  git -C "${WORK}" init -q
  printf '%s\n' "${TRIAD}" >"${WORK}/a.md"
  printf 'Run the gate.\n' >"${WORK}/b.md"
  commit_all base
  printf '\n%s\n' "${TRIAD}" >>"${WORK}/a.md"
  printf '\n%s\n' "${TRIAD}" >>"${WORK}/b.md"
  cd "${WORK}"
  run --separate-stderr lint_branch --base HEAD a.md
  [ "${status}" -eq 1 ]
  [[ "${output}" == *'a.md:3:'*'AgentProse.AbstractTriad'* ]]
  [[ "${output}" != *'a.md:1:'* ]]
  [[ "${output}" != *'b.md'* ]]
}

@test "lint-branch-prose with a path the branch didn't change exits 0 and says nothing" {
  git -C "${WORK}" init -q
  printf '%s\n' "${TRIAD}" >"${WORK}/a.md"
  printf 'Run the gate.\n' >"${WORK}/b.md"
  commit_all base
  printf '\n%s\n' "${TRIAD}" >>"${WORK}/b.md"
  printf '%s\n' "${TRIAD}" >"${WORK}/untracked.md"
  cd "${WORK}"
  run lint_branch --base HEAD a.md untracked.md
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "lint-branch-prose with a missing path exits with no input" {
  git -C "${WORK}" init -q
  cd "${WORK}"
  run lint_branch nothing-here
  [ "${status}" -eq 66 ]
}

@test "lint-branch-prose with a path outside the repository is a usage error" {
  mkdir "${WORK}/repo"
  git -C "${WORK}/repo" init -q
  git -C "${WORK}/repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m base
  printf 'Run the gate.\n' >"${WORK}/outside.md"
  cd "${WORK}/repo"
  run --separate-stderr lint_branch --base HEAD ../outside.md
  [ "${status}" -eq 64 ]
  [[ "${stderr}" == *"'../outside.md' is outside the repository"* ]]
}

@test "lint-branch-prose reads a path from the directory it runs in" {
  git -C "${WORK}" init -q
  mkdir "${WORK}/docs"
  printf 'Run the gate.\n' >"${WORK}/docs/a.md"
  commit_all base
  printf '\n%s\n' "${TRIAD}" >>"${WORK}/docs/a.md"
  cd "${WORK}/docs"
  run --separate-stderr lint_branch --base HEAD a.md
  [ "${status}" -eq 1 ]
  grep -q '^a\.md:3:.*AgentProse\.AbstractTriad' <<<"${output}"
}

@test "lint-branch-prose prints each path from the directory it runs in" {
  git -C "${WORK}" init -q
  mkdir "${WORK}/docs"
  printf 'Run the gate.\n' >"${WORK}/docs/a.md"
  printf 'Run the gate.\n' >"${WORK}/b.md"
  commit_all base
  printf '\n%s\n' "${TRIAD}" >>"${WORK}/docs/a.md"
  printf '\n%s\n' "${TRIAD}" >>"${WORK}/b.md"
  cd "${WORK}/docs"
  run --separate-stderr lint_branch --base HEAD
  [ "${status}" -eq 1 ]
  grep -q '^a\.md:3:' <<<"${output}"
  grep -q '^\.\./b\.md:3:' <<<"${output}"
}

@test "lint-branch-prose with a directory lints every file under it" {
  git -C "${WORK}" init -q
  mkdir "${WORK}/docs"
  printf 'Run the gate.\n' >"${WORK}/docs/a.md"
  printf 'Run the gate.\n' >"${WORK}/b.md"
  commit_all base
  printf '\n%s\n' "${TRIAD}" >>"${WORK}/docs/a.md"
  printf '\n%s\n' "${TRIAD}" >>"${WORK}/b.md"
  cd "${WORK}"
  run --separate-stderr lint_branch --base HEAD docs
  [ "${status}" -eq 1 ]
  [[ "${output}" == *'docs/a.md:3:'* ]]
  [[ "${output}" != *'b.md'* ]]
}

@test "lint-branch-prose with a path keeps --base and --limit" {
  git -C "${WORK}" init -q
  printf 'Run the gate.\n' >"${WORK}/a.md"
  printf 'Run the gate.\n' >"${WORK}/b.md"
  commit_all base
  printf '\n%s\n\n%s\n' "${TRIAD}" "${TRIAD}" >>"${WORK}/a.md"
  printf '\n%s\n' "${TRIAD}" >>"${WORK}/b.md"
  commit_all added
  cd "${WORK}"
  run --separate-stderr lint_branch --base HEAD~1 --limit 1 a.md
  [ "${status}" -eq 1 ]
  [[ "${output}" == *'[1 more alerts'* ]]
  [[ "${output}" == *'Alerts by rule:'* ]]
}

@test "lint-branch-prose with no path lints every file the branch changed" {
  git -C "${WORK}" init -q
  printf 'Run the gate.\n' >"${WORK}/a.md"
  printf 'Run the gate.\n' >"${WORK}/b.md"
  commit_all base
  printf '\n%s\n' "${TRIAD}" >>"${WORK}/a.md"
  printf '\n%s\n' "${TRIAD}" >>"${WORK}/b.md"
  cd "${WORK}"
  run --separate-stderr lint_branch --base HEAD
  [ "${status}" -eq 1 ]
  [[ "${output}" == *'a.md:3:'* ]]
  [[ "${output}" == *'b.md:3:'* ]]
}

@test "lint-branch-prose --by-file counts only the alerts on added lines, highest first" {
  git -C "${WORK}" init -q
  printf 'Run the gate.\n' >"${WORK}/a.md"
  printf '%s\n' "${TRIAD}" >"${WORK}/b.md"
  printf 'Run the gate.\n' >"${WORK}/clean.md"
  commit_all base
  printf '\n%s\n' "${TRIAD}" >>"${WORK}/a.md"
  printf '\n%s\n\n%s\n' "${TRIAD}" "${TRIAD}" >>"${WORK}/b.md"
  printf '\nRun it again.\n' >>"${WORK}/clean.md"
  cd "${WORK}"
  run --separate-stderr lint_branch --base HEAD --by-file
  [ "${status}" -eq 1 ]
  [ "${#lines[@]}" -eq 2 ]
  [[ "${lines[0]}" =~ ^\ *2\ b\.md$ ]]
  [[ "${lines[1]}" =~ ^\ *1\ a\.md$ ]]
}

@test "lint-branch-prose --by-file counts Vale alerts only" {
  git -C "${WORK}" init -q
  printf 'Run the gate.\n' >"${WORK}/a.md"
  commit_all base
  printf '\n%s\n\nRun the gaet.\n' "${TRIAD}" >>"${WORK}/a.md"
  cd "${WORK}"
  run --separate-stderr lint_branch --base HEAD --by-file
  [ "${status}" -eq 1 ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "${lines[0]}" =~ ^\ *1\ a\.md$ ]]
}

@test "lint-branch-prose --by-file exits 0 and says nothing on a clean branch" {
  git -C "${WORK}" init -q
  printf 'Run the gate.\n' >"${WORK}/a.md"
  commit_all base
  printf '\nRun it again.\n' >>"${WORK}/a.md"
  cd "${WORK}"
  run lint_branch --base HEAD --by-file
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "lint-branch-prose --by-file exits 1 when every alert is cspell's, and prints nothing" {
  git -C "${WORK}" init -q
  printf 'Run the gate.\n' >"${WORK}/a.md"
  commit_all base
  printf '\nRun the gaet.\n' >>"${WORK}/a.md"
  cd "${WORK}"
  run lint_branch --base HEAD a.md
  [[ "${output}" == *'[cspell]'* ]]
  run --separate-stderr lint_branch --base HEAD --by-file a.md
  [ "${status}" -eq 1 ]
  [ -z "${output}" ]
}

@test "lint-branch-prose --by-file takes --base and a path from the directory it runs in" {
  git -C "${WORK}" init -q
  mkdir "${WORK}/docs"
  printf 'Run the gate.\n' >"${WORK}/docs/a.md"
  printf 'Run the gate.\n' >"${WORK}/b.md"
  commit_all base
  printf '\n%s\n' "${TRIAD}" >>"${WORK}/docs/a.md"
  printf '\n%s\n' "${TRIAD}" >>"${WORK}/b.md"
  commit_all added
  cd "${WORK}/docs"
  run --separate-stderr lint_branch --base HEAD~1 --by-file a.md
  [ "${status}" -eq 1 ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "${lines[0]}" =~ ^\ *1\ a\.md$ ]]
}

@test "lint-branch-prose --by-file lists every file past the limit" {
  git -C "${WORK}" init -q
  printf 'Run the gate.\n' >"${WORK}/a.md"
  printf 'Run the gate.\n' >"${WORK}/b.md"
  commit_all base
  printf '\n%s\n' "${TRIAD}" >>"${WORK}/a.md"
  printf '\n%s\n' "${TRIAD}" >>"${WORK}/b.md"
  cd "${WORK}"
  run --separate-stderr lint_branch --base HEAD --limit 1 --by-file
  [ "${status}" -eq 1 ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "lint-branch-prose --data-dir lints a repository with no Vale config through the default one" {
  data_dir
  mkdir "${WORK}/repo"
  git -C "${WORK}/repo" init -q
  printf 'Run the gate.\n' >"${WORK}/repo/a.md"
  git -C "${WORK}/repo" add a.md
  git -C "${WORK}/repo" -c user.name=t -c user.email=t@t commit -qm base
  printf '\n%s\n' "${TRIAD}" >>"${WORK}/repo/a.md"
  cd "${WORK}/repo"
  run --separate-stderr lint_branch --base HEAD --data-dir "${WORK}/data"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *'a.md:3:'*'AgentProse.AbstractTriad'* ]]
}

@test "lint-branch-prose --data-dir reads a relative directory from where it runs" {
  data_dir
  mkdir -p "${WORK}/repo/docs"
  git -C "${WORK}/repo" init -q
  printf 'Run the gate.\n' >"${WORK}/repo/docs/a.md"
  git -C "${WORK}/repo" add docs/a.md
  git -C "${WORK}/repo" -c user.name=t -c user.email=t@t commit -qm base
  printf '\n%s\n' "${TRIAD}" >>"${WORK}/repo/docs/a.md"
  cd "${WORK}/repo/docs"
  run --separate-stderr lint_branch --base HEAD --data-dir ../../data --by-file
  [ "${status}" -eq 1 ]
  [[ "${lines[0]}" =~ ^\ *1\ a\.md$ ]]
}

@test "lint-branch-prose --data-dir with a missing directory exits with no input" {
  git -C "${WORK}" init -q
  cd "${WORK}"
  run lint_branch --data-dir "${WORK}/nothing-here"
  [ "${status}" -eq 66 ]
}

@test "lint-branch-prose with no Vale config to find is a configuration error" {
  unset VALE_CONFIG_PATH
  git -C "${WORK}" init -q
  printf 'Run the gate.\n' >"${WORK}/a.md"
  commit_all base
  printf '\n%s\n' "${TRIAD}" >>"${WORK}/a.md"
  cd "${WORK}"
  run --separate-stderr lint_branch --base HEAD
  [ "${status}" -eq 78 ]
  [ -z "${output}" ]
  [[ "${stderr}" == *'--data-dir'* ]]
}

@test "lint-branch-prose with an unsynced package warns that its config names no styles" {
  unset VALE_CONFIG_PATH
  git -C "${WORK}" init -q
  printf 'StylesPath = styles\nPackages = %s/package\n' "${REPO}" >"${WORK}/.vale.ini"
  printf 'Run the gate.\n' >"${WORK}/a.md"
  commit_all base
  mkdir "${WORK}/styles"
  printf '\n%s\n' "${TRIAD}" >>"${WORK}/a.md"
  cd "${WORK}"
  run --separate-stderr lint_branch --base HEAD
  [ "${status}" -eq 0 ]
  [[ "${stderr}" == *'names no styles'* ]]
}

@test "lint-branch-prose --help describes --data-dir" {
  run lint_branch --help
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'--data-dir <dir>'* ]]
}

@test "lint-branch-prose --help describes --by-file" {
  run lint_branch --help
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'--by-file'* ]]
}

@test "lint-branch-prose --help shows the paths in its usage line" {
  run lint_branch --help
  [ "${status}" -eq 0 ]
  [[ "${lines[0]}" == *'[<path>...]'* ]]
}
