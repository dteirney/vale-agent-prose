#!/usr/bin/env bats
#
# tools/commit-hook, against a throwaway global git config and a throwaway
# repository, with real commits.

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
  DATA="${WORK}/data"
  GIT_CONFIG_GLOBAL="${WORK}/gitconfig"
  export GIT_CONFIG_GLOBAL
  git config set --global user.name 'Test'
  git config set --global user.email 'test@example.com'
  git init -q "${WORK}/repo"
}

teardown() {
  rm -rf "${WORK}"
}

readonly TRIAD='feat: add clarity, discipline, and rigor'
readonly CLEAN='fix: strip the ticket key from a subject line'

commit_hook() {
  "${REPO}/tools/commit-hook" "$@"
}

commit() {
  git -C "${WORK}/repo" commit --allow-empty -q -m "$1"
}

@test "a finding in the message stops the commit" {
  commit_hook install "${DATA}"
  run commit "${TRIAD}"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *'COMMIT_EDITMSG:1:'*'AgentProse.AbstractTriad'* ]]
  run git -C "${WORK}/repo" rev-parse -q --verify HEAD
  [ "${status}" -ne 0 ]
}

@test "a repository with no Vale config checks against the default one" {
  commit_hook install "${DATA}"
  mkdir -p "${DATA}/vale"
  printf 'StylesPath = %s/styles\n' "${CONSUMER}" >"${DATA}/vale/.vale.ini"
  unset VALE_CONFIG_PATH
  run commit "${TRIAD}"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *'COMMIT_EDITMSG:1:'*'AgentProse.AbstractTriad'* ]]
}

# A copy of this repository's own commit-msg hook and commitlint config.
repo_hook() {
  mkdir "${WORK}/repo/githooks"
  cp "${REPO}/githooks/commit-msg" "${WORK}/repo/githooks/commit-msg"
  cp "${REPO}/.commitlintrc.json" "${WORK}/repo/.commitlintrc.json"
  git -C "${WORK}/repo" config core.hooksPath githooks
}

@test "this repository's own commit-msg hook defers to the global one" {
  commit_hook install "${DATA}"
  repo_hook
  run commit "${TRIAD}"
  [ "${status}" -eq 1 ]
  [ "$(grep -c 'AgentProse.AbstractTriad' <<<"${output}")" -eq 1 ]
}

@test "this repository's own commit-msg hook stops a message with no type" {
  commit_hook install "${DATA}"
  repo_hook
  run commit 'strip the ticket key from a subject line'
  [ "${status}" -eq 1 ]
  [[ "${output}" == *'type-empty'* ]]
}

@test "a clean message commits" {
  commit_hook install "${DATA}"
  run commit "${CLEAN}"
  [ "${status}" -eq 0 ]
}

@test "the repository's own commit-msg hook still runs" {
  commit_hook install "${DATA}"
  printf '#!/bin/sh\necho repository hook ran\n' >"${WORK}/repo/.git/hooks/commit-msg"
  chmod +x "${WORK}/repo/.git/hooks/commit-msg"
  run commit "${CLEAN}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'repository hook ran'* ]]
}

# Claude Code deletes the plugin's data directory on uninstall, and the global
# config still names it.
@test "a commit goes through once the copied check is gone" {
  commit_hook install "${DATA}"
  rm -rf "${DATA}"
  run commit "${TRIAD}"
  [ "${status}" -eq 0 ]
}

@test "refresh replaces a stale copy and touches no git config" {
  commit_hook install "${DATA}"
  printf 'stale\n' >"${DATA}/lib/prose.sh"
  git config remove-section --global hook.vale-agent-prose
  run commit_hook refresh "${DATA}"
  [ "${status}" -eq 0 ]
  cmp "${REPO}/lib/prose.sh" "${DATA}/lib/prose.sh"
  run git config get --global hook.vale-agent-prose.command
  [ "${status}" -ne 0 ]
}

@test "installing twice leaves one event" {
  commit_hook install "${DATA}"
  commit_hook install "${DATA}"
  run git config get --global --all hook.vale-agent-prose.event
  [ "${output}" = 'commit-msg' ]
}

@test "remove takes the hook out, and a finding commits again" {
  commit_hook install "${DATA}"
  run commit_hook remove
  [ "${status}" -eq 0 ]
  run commit "${TRIAD}"
  [ "${status}" -eq 0 ]
}

@test "remove with no hook installed exits 0" {
  run commit_hook remove
  [ "${status}" -eq 0 ]
}

@test "a git too old to run a hook from config fails the install" {
  mkdir "${WORK}/bin"
  printf '#!/usr/bin/env bash\n[[ "$1" == --version ]] && exec echo "git version 2.53.0"\nexec %s "$@"\n' \
    "$(command -v git)" >"${WORK}/bin/git"
  chmod +x "${WORK}/bin/git"
  PATH="${WORK}/bin:${PATH}" run commit_hook install "${DATA}"
  [ "${status}" -eq 1 ]
  run git config get --global hook.vale-agent-prose.command
  [ "${status}" -ne 0 ]
}

@test "no subcommand is a usage error" {
  run commit_hook
  [ "${status}" -eq 2 ]
}

@test "install with no directory is a usage error" {
  run commit_hook install
  [ "${status}" -eq 2 ]
}

@test "an unknown subcommand is a usage error" {
  run commit_hook enable
  [ "${status}" -eq 2 ]
}

@test "--help exits 0" {
  run commit_hook --help
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'usage:'* ]]
}
