#!/usr/bin/env bash
#
# SessionEnd and SessionStart hook: delete the folders where the prose hook
# keeps each session's alerts, so they don't pile up.
#
# A crash skips SessionEnd, so SessionStart deletes what a dead process left.
# SessionEnd gets a budget of 1.5 seconds, shared with every other SessionEnd
# hook. Every failure exits 0, because a session must never wait on this.
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

# shellcheck source=lib/prose.sh
source "${SCRIPT_DIR}/../lib/prose.sh"

prune_unclaimed() {
  local root dir
  # shellcheck disable=SC2310  # the hook exits 0 on any failure
  root="$(prose::sessions_dir)" || return 0
  for dir in "${root}"/*/; do
    dir="${dir%/}"
    # shellcheck disable=SC2310  # a predicate
    if [[ -d "${dir}" ]] && ! prose::session_dir_claimed "${dir}"; then
      rm -rf "${dir}" 2>/dev/null || true
    fi
  done
}

main() {
  command -v jq >/dev/null 2>&1 || exit 0

  local input event session dir=''
  input="$(cat)" || exit 0
  event="$(jq -r '.hook_event_name // empty' <<<"${input}" 2>/dev/null)" \
    || exit 0
  session="$(jq -r '.session_id // empty' <<<"${input}" 2>/dev/null)" \
    || session=''
  # shellcheck disable=SC2310  # the hook exits 0 on any failure
  dir="$(prose::session_dir "${session}")" || dir=''

  case "${event}" in
    SessionEnd)
      if [[ -n "${dir}" ]]; then
        rm -rf "${dir}" 2>/dev/null || true
      fi
      ;;
    SessionStart)
      # A resumed session's folder still names the process that wrote it.
      if [[ -n "${dir}" && -d "${dir}" ]]; then
        # shellcheck disable=SC2310  # the hook exits 0 on any failure
        prose::claim_session_dir "${dir}" 2>/dev/null || true
      fi
      prune_unclaimed
      ;;
  esac
  exit 0
}

main "$@"
