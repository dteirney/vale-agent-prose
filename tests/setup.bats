#!/usr/bin/env bats
#
# tools/setup and the default-config sync it runs, against a throwaway global
# git config and throwaway directories.

setup_file() {
  REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  export REPO
}

setup() {
  WORK="$(mktemp -d)"
  DATA="${WORK}/data"
  GIT_CONFIG_GLOBAL="${WORK}/gitconfig"
  export GIT_CONFIG_GLOBAL
  unset VALE_CONFIG_PATH
  mkdir "${WORK}/project"
}

teardown() {
  rm -rf "${WORK}"
}

setup_cmd() {
  "${REPO}/tools/setup" "$@"
}

sync_default() {
  "${REPO}/scripts/sync-default-config.sh" "$@"
}

# A package copy that matches, so the default-config sync skips the download.
current_copy() {
  mkdir -p "${DATA}/vale"
  cp -R "${REPO}/package" "${DATA}/vale/package"
}

# A vale that fails every sync and passes everything else through.
failing_sync() {
  mkdir "${WORK}/bin"
  printf '#!/usr/bin/env bash\n[[ "$*" == *sync* ]] && exit 2\nexec %s "$@"\n' \
    "$(command -v vale)" >"${WORK}/bin/vale"
  chmod +x "${WORK}/bin/vale"
}

# This one downloads the packages the package names.
@test "install adds the commit hook and syncs this directory's styles" {
  current_copy
  printf 'StylesPath = styles\nPackages = %s/package\n' "${REPO}" \
    >"${WORK}/project/.vale.ini"
  cd "${WORK}/project"
  run setup_cmd install "${DATA}"
  [ "${status}" -eq 0 ]
  [ -d "${WORK}/project/styles/AgentProse" ]
  run git config get --global hook.vale-agent-prose.command
  [ "${status}" -eq 0 ]
}

@test "install in a directory with no Vale configuration says the default applies" {
  current_copy
  cd "${WORK}/project"
  run setup_cmd install "${DATA}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'the default one applies'* ]]
}

@test "install with a broken Vale configuration fails and says why" {
  current_copy
  printf '[unclosed\n' >"${WORK}/project/.vale.ini"
  cd "${WORK}/project"
  run setup_cmd install "${DATA}"
  [ "${status}" -eq 70 ]
  [[ "${output}" == *'unclosed section'* ]]
}

@test "a failed step still runs the rest, and install fails" {
  failing_sync
  cd "${WORK}/project"
  PATH="${WORK}/bin:${PATH}" run setup_cmd install "${DATA}"
  [ "${status}" -eq 70 ]
  run git config get --global hook.vale-agent-prose.command
  [ "${status}" -eq 0 ]
}

@test "remove takes the commit hook out" {
  current_copy
  cd "${WORK}/project"
  setup_cmd install "${DATA}"
  run setup_cmd remove
  [ "${status}" -eq 0 ]
  run git config get --global hook.vale-agent-prose.command
  [ "${status}" -ne 0 ]
}

@test "no subcommand is a usage error" {
  run setup_cmd
  [ "${status}" -eq 64 ]
}

@test "install with no directory is a usage error" {
  run setup_cmd install
  [ "${status}" -eq 64 ]
}

@test "--help exits 0" {
  run setup_cmd --help
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'usage:'* ]]
}

@test "a failed default sync leaves no package copy, so the next run retries" {
  failing_sync
  PATH="${WORK}/bin:${PATH}" run sync_default "${DATA}"
  [ "${status}" -eq 1 ]
  [ ! -e "${DATA}/vale/package" ]
}

# This one downloads the packages the package names.
@test "the default sync installs a config that lints, and skips an unchanged package" {
  run sync_default "${DATA}"
  [ "${status}" -eq 0 ]

  printf 'The gate needs clarity, discipline, and rigor.\n' >"${WORK}/project/notes.md"
  cd "${WORK}/project"
  VALE_CONFIG_PATH="${DATA}/vale/.vale.ini" run vale --no-global --output=line notes.md
  [[ "${output}" == *'AgentProse.AbstractTriad'* ]]

  printf 'unchanged\n' >"${DATA}/vale/.vale.ini"
  run sync_default "${DATA}"
  [ "${status}" -eq 0 ]
  [ "$(cat "${DATA}/vale/.vale.ini")" = 'unchanged' ]
}

@test "the default sync with no directory is a usage error" {
  run sync_default
  [ "${status}" -eq 2 ]
}
