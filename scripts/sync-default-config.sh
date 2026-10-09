#!/usr/bin/env bash
#
# Keep a Vale config in the plugin's data directory, for a repository that has
# none of its own. $1 is the data directory.
#
#   scripts/sync-default-config.sh ~/.claude/plugins/data/<id>
#
# The sync downloads every package the config names, which takes seconds. It
# runs only when the package here differs from the copy it last synced.
# Exit 0 when the copy is current, 1 when the sync fails, 2 on a usage error.
set -euo pipefail
IFS=$'\n\t'

readonly PROG="${0##*/}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

# shellcheck source=lib/prose.sh
source "${SCRIPT_DIR}/../lib/prose.sh"

die() {
  printf '%s: %s\n' "${PROG}" "$1" >&2
  exit 1
}

main() {
  if [[ $# -ne 1 || -z "$1" ]]; then
    printf 'usage: %s <data-dir>\n' "${PROG}" >&2
    exit 2
  fi
  command -v vale >/dev/null 2>&1 || die 'vale is required'

  local src="${SCRIPT_DIR}/../package"
  local dir="$1/vale"

  if diff -rq "${src}" "${dir}/package" >/dev/null 2>&1; then
    return 0
  fi

  rm -rf "${dir}/package" || die "cannot remove the old copy in '${dir}'"
  mkdir -p "${dir}" || die "cannot create '${dir}'"
  cp -R "${src}" "${dir}/package" || die "cannot copy the package into '${dir}'"

  # Vale resolves a relative package path against the working directory, not
  # against the config file.
  printf 'StylesPath = styles\nPackages = %s\n' "${dir}/package" \
    >"${dir}/.vale.ini" || die "cannot write '${dir}/.vale.ini'"

  if ! vale --no-global --config="${dir}/.vale.ini" sync >/dev/null 2>&1; then
    # Without the copy, the next run's diff fails and the sync runs again.
    rm -rf "${dir}/package" || true
    local msg
    msg="$(prose::message sync/failed "${dir}/.vale.ini")"
    die "${msg}"
  fi
}

main "$@"
