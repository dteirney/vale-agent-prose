#!/usr/bin/env bash
#
# SessionStart hook: say once why the prose hook would stay silent.
#
# The prose hook must never interrupt the turn. It exits 0 with nothing to say
# when a tool is missing or Vale can't load a configuration. Without this
# check, a silent hook reads the same as a clean file.
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

# shellcheck source=lib/prose.sh
source "${SCRIPT_DIR}/../lib/prose.sh"

# Print $1 as a JSON string, for the one reply built without jq. A message
# file is one line, so a backslash and a quote are all it can hold to escape.
json_string() {
  local s="${1//\\/\\\\}"
  printf '"%s"' "${s//\"/\\\"}"
}

main() {
  if ! command -v jq >/dev/null 2>&1; then
    local user agent
    # shellcheck disable=SC2310  # a missing message ends the hook with exit 0
    user="$(prose::message doctor-hook/jq-missing-user)" || exit 0
    # shellcheck disable=SC2310  # a missing message ends the hook with exit 0
    agent="$(prose::message doctor-hook/jq-missing-agent)" || exit 0
    user="$(json_string "${user}")"
    agent="$(json_string "${agent}")"
    printf '{"systemMessage":%s,"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' \
      "${user}" "${agent}"
    exit 0
  fi

  local problems
  problems="$("${SCRIPT_DIR}/../tools/doctor" "${CLAUDE_PLUGIN_DATA:-}" 2>/dev/null)" \
    || true
  [[ -n "${problems}" ]] || exit 0

  local caveat
  # shellcheck disable=SC2310  # a missing caveat still leaves the problems
  caveat="$(prose::message doctor-hook/caveat)" || caveat=''

  jq -n --arg msg "vale-agent-prose: ${problems//$'\n'/ }" \
    --arg caveat "${caveat}" '{
    systemMessage: $msg,
    hookSpecificOutput: {
      hookEventName: "SessionStart",
      additionalContext: ($msg + " " + $caveat)
    }
  }'
}

main "$@"
