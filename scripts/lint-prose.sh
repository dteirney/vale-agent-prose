#!/usr/bin/env bash
#
# PostToolUse hook: lint the prose the agent wrote and hand back only what
# lands on lines this edit added.
#
# PostToolUse can't block, because the write already happened, so
# additionalContext is the whole mechanism. Moving this to PreToolUse to deny
# would be worse: a false deny teaches the agent to route around the hook, and
# a prose alert needs judgement.
#
# Every guard below exits 0, because a hook that can't read its input must
# never interrupt the turn. That costs nothing under `set -e`: a command to
# the left of `||` sits in a condition context.
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

# shellcheck source=lib/prose.sh
source "${SCRIPT_DIR}/../lib/prose.sh"

# Print the file where session $1 saves the alerts it hands back for file $2.
saved_file() {
  local dir key
  # shellcheck disable=SC2310  # the hook exits 0 on any failure
  dir="$(prose::session_dir "$1")" || return 1
  key="$(git hash-object --stdin <<<"$2")" || return 1
  printf '%s\n' "${dir}/${key}.json"
}

# Print a recheck line for each alert saved in $1, then remove it. Vale's JSON
# report on the file comes on stdin, and an empty one rechecks nothing.
recheck() {
  [[ -f "$1" ]] || return 0
  local report
  report="$(cat)" || return 1

  # Each alert matches one occurrence of its rule on its flagged words, so
  # two alerts on the same words need two occurrences to persist.
  local defs rechecks=''
  # shellcheck disable=SC2310  # the hook exits 0 on any failure
  if [[ -n "${report}" ]] && defs="$(prose::vale_jq)"; then
    rechecks="$(jq -c --slurpfile saved "$1" "${defs}"'
      reduce (alerts | [.Check, .Match] | tojson) as $k ({}; .[$k] += 1)
      | reduce $saved[0][] as $alert ({left: ., out: []};
        ([$alert.rule, $alert.match] | tojson) as $k
        | if (.left[$k] // 0) > 0
          then .left[$k] -= 1 | .out += [{recheck: "persisted"} + $alert]
          else .out += [{recheck: "absent"} + $alert]
          end)
      | .out[]' <<<"${report}")" || rechecks=''
  fi
  # Removed before the lines print, so a failure can't recheck it twice.
  rm -f "$1" || return 1
  if [[ -n "${rechecks}" ]]; then
    printf '%s\n' "${rechecks}"
  fi
}

# Save to $1 the alerts in Vale's JSON report, on stdin, whose lines are among
# those handed back. $2 is the file, $3 the alerts handed back, $4 the root and
# $5 the configuration.
save_alerts() {
  local report
  report="$(cat)" || return 1
  [[ -n "${report}" && -n "$3" ]] || return 0

  local name="${2##*/}" type=''
  if [[ "${name}" == *.* ]]; then
    type="${name##*.}"
  fi
  local version defs
  version="$(jq -r .version "${SCRIPT_DIR}/../.claude-plugin/plugin.json")" \
    || return 1
  # shellcheck disable=SC2310  # the hook exits 0 on any failure
  defs="$(prose::vale_jq)" || return 1

  local alerts
  alerts="$(jq -c --arg handed_back "$3" --rawfile text "$2" --arg file "$2" \
    --arg type "${type}" --arg root "$4" --arg config "$5" \
    --arg version "${version}" "${defs}"'
      ($text | rtrimstr("\n") | split("\n")) as $src
      | ($handed_back | split("\n") | INDEX(.)) as $lines
      | [alerts | select($lines[line])
        | {rule: .Check, message: .Message, match: .Match, file: $file,
          type: (if $type == "" then null else $type end), line: .Line,
          lines: [range([.Line - 1, 1] | max; [.Line + 1, ($src | length)] | min + 1)
            | {line: ., text: $src[. - 1]}],
          root: (if $root == "" then null else $root end),
          config: $config, version: $version}]
    ' <<<"${report}")" || return 1

  [[ "${alerts}" != '[]' ]] || return 0
  mkdir -p "${1%/*}" || return 1
  # shellcheck disable=SC2310  # the hook exits 0 on any failure
  prose::claim_session_dir "${1%/*}" || return 1
  printf '%s\n' "${alerts}" >"$1"
}

main() {
  command -v jq >/dev/null 2>&1 || exit 0
  command -v vale >/dev/null 2>&1 || exit 0

  local input
  input="$(cat)" || exit 0

  local file
  file="$(printf '%s' "${input}" | jq -r '.tool_input.file_path // empty' \
    2>/dev/null)" || exit 0
  [[ -n "${file}" && -f "${file}" ]] || exit 0

  local session
  session="$(printf '%s' "${input}" | jq -r '.session_id // empty' \
    2>/dev/null)" || session=''

  # Resolve symlinks before anything compares this path to a repository root.
  # `git rev-parse --show-toplevel` returns a resolved path, and on macOS
  # \$TMPDIR sits under /var where the real directory is /private/var. An
  # unresolved path then fails to strip its own root, Vale prints absolute
  # paths, and the filter finds none of them in the repository.
  local dir
  dir="$(cd "$(dirname "${file}")" && pwd -P)" || exit 0
  file="${dir}/$(basename "${file}")"

  case "${file}" in
    */.git/* | */node_modules/* | */dist/* | */.moon/cache/*) exit 0 ;;
  esac

  # cspell has no user-level config, so without -c the word list there reaches
  # only files under the config directory itself. -c adds it without
  # displacing a repository's own cspell.json: the search for that one still
  # runs, and only --no-config-search would stop it.
  local cspell_config="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}/cspell.json"
  [[ -f "${cspell_config}" ]] || cspell_config=''

  local default_config=''
  if [[ -n "${CLAUDE_PLUGIN_DATA:-}" ]]; then
    default_config="${CLAUDE_PLUGIN_DATA}/vale/.vale.ini"
  fi

  local root=''
  root="$(git -C "${dir}" rev-parse --show-toplevel 2>/dev/null)" || root=''

  # A file the repository ignores is scratch, and it has no diff to scope
  # against, so the branch below would report every line it has.
  if [[ -n "${root}" ]] \
    && git -C "${root}" check-ignore -q -- "${file}" 2>/dev/null; then
    exit 0
  fi

  local tracked=0
  if [[ -n "${root}" ]] \
    && git -C "${root}" ls-files --error-unmatch -- "${file}" \
      >/dev/null 2>&1; then
    tracked=1
    cd "${root}" || exit 0
  fi

  # shellcheck disable=SC2310  # the hook exits 0 on any failure
  prose::use_default_config "${default_config}" || exit 0
  local config=own
  if [[ -n "${default_config}" &&
    "${VALE_CONFIG_PATH:-}" == "${default_config}" ]]; then
    config=default
  fi

  # Vale matches a config section's glob against the path it receives, so a
  # relative path misses sections like the one that allows first person. It
  # gets the absolute path, and the tracked branch strips the root from its
  # report. Only Vale's JSON output has the words an alert flags.
  local report=''
  # shellcheck disable=SC2310  # a predicate
  if prose::vale_reads "${file}"; then
    local code=0
    report="$(vale --no-global --output=JSON "${file}" 2>/dev/null)" \
      || code=$?
    # Vale exits 1 for an error-level alert and 2 when it can't run.
    if [[ "${code}" -gt 1 ]]; then
      report=''
    fi
  fi

  local alerts
  if [[ "${tracked}" -eq 1 ]]; then
    # A legacy file's existing comments aren't this edit's to answer for, but
    # the whole comment or paragraph the edit touched is. The filter reads the
    # file by its path relative to the repository root.
    report="$(jq -c --arg root "${root}/" 'with_entries(.key |= ltrimstr($root))' \
      <<<"${report}" 2>/dev/null)" || report=''
    # No revision makes the diff the working tree's against the index.
    # shellcheck disable=SC2310,SC2119  # both swallow a linter's exit on an alert
    alerts="$({
      prose::vale_lines <<<"${report}"
      prose::cspell "${cspell_config}" "${file#"${root}"/}"
    } | prose::filter_touched 2>/dev/null)" || alerts=''
  else
    # Untracked, or outside a repository: every line is one the agent wrote,
    # so there is nothing to filter against.
    # shellcheck disable=SC2310  # it swallows a linter's exit on an alert
    alerts="$(
      prose::vale_lines <<<"${report}"
      prose::cspell "${cspell_config}" "file://${file}"
    )" || alerts=''
  fi

  local handed_back=''
  if [[ -n "${alerts}" ]]; then
    # shellcheck disable=SC2310  # the hook exits 0 on any failure
    handed_back="$(prose::hook_alerts "${alerts}")" || exit 0
  fi

  # The model never receives a hook's stderr when it exits 0, but the
  # transcript keeps it. A recheck printed before a failure still counts.
  local saved
  # shellcheck disable=SC2310  # a failure here must leave the hook silent
  if saved="$(saved_file "${session}" "${file}" 2>/dev/null)"; then
    local rechecks
    rechecks="$(recheck "${saved}" <<<"${report}" 2>/dev/null)" || true
    if [[ -n "${rechecks}" ]]; then
      printf '%s\n' "${rechecks}" >&2 || true
    fi
    save_alerts "${saved}" "${file}" "${handed_back}" "${root}" "${config}" \
      <<<"${report}" 2>/dev/null || true
  fi

  [[ -n "${handed_back}" ]] || exit 0

  prose::hook_context "${handed_back}" lint-prose/context \
    "$(basename "${BASH_SOURCE[0]}" .sh)"
  exit 0
}

main "$@"
