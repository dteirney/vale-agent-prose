#!/usr/bin/env bash
#
# PostToolUse hook: lint the prose the agent wrote and hand back only what
# lands on lines this edit added.
#
# PostToolUse can't block, because the write already happened, so
# additionalContext is the whole mechanism. Moving this to PreToolUse to deny
# would be worse: a false deny teaches the agent to route around the hook, and
# a prose finding needs judgement.
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

main() {
  command -v jq >/dev/null 2>&1 || exit 0
  command -v vale >/dev/null 2>&1 || exit 0

  local input
  input="$(cat)" || exit 0

  local file
  file="$(printf '%s' "${input}" | jq -r '.tool_input.file_path // empty' \
    2>/dev/null)" || exit 0
  [[ -n "${file}" && -f "${file}" ]] || exit 0

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

  local findings
  if [[ -n "${root}" ]] \
    && git -C "${root}" ls-files --error-unmatch -- "${file}" \
      >/dev/null 2>&1; then
    # A legacy file's existing comments aren't this edit's to answer for, but
    # the whole comment or paragraph the edit touched is. The filter reads the
    # file by its path relative to the repository root.
    #
    # Vale matches a config section's glob against the path it receives, so a
    # relative path misses sections like the one that allows first person. It
    # gets the absolute path, and sed strips the root from what it prints.
    local rel="${file#"${root}"/}"
    # No revision makes the diff the working tree's against the index.
    # shellcheck disable=SC2310,SC2119  # both swallow a linter's non-zero finding
    findings="$(cd "${root}" \
      && prose::use_default_config "${default_config}" \
      && prose::lint_file "${file}" "${rel}" "${cspell_config}" \
      | sed "s|^${root}/||" \
        | prose::filter_touched 2>/dev/null)" || findings=''
  else
    # Untracked, or outside a repository: every line is one the agent wrote,
    # so there is nothing to filter against.
    # shellcheck disable=SC2310  # it swallows a linter's non-zero finding
    findings="$(prose::use_default_config "${default_config}" \
      && prose::lint_file "${file}" "file://${file}" "${cspell_config}")" \
      || findings=''
  fi

  [[ -n "${findings}" ]] || exit 0

  prose::hook_context "${findings}" lint-prose/context \
    "$(basename "${BASH_SOURCE[0]}" .sh)"
  exit 0
}

main "$@"
