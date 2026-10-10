#!/usr/bin/env bats
#
# tools/lint-prose and tools/lint-branch-prose. The branch command's lint needs
# a commit to diff against, so only its argument handling is here.

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

@test "lint-branch-prose with an operand is a usage error" {
  run lint_branch README.md
  [ "${status}" -eq 64 ]
}
