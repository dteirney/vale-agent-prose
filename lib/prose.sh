#!/usr/bin/env bash
#
# Shared by the prose hook and the prose commands. A caller sources this, so
# it sets no shell options and defines no top-level state.

# Whether Vale can reach this file's comments without reading its code.
#
# Vale compiles in the extension list at docs.vale.sh/formats/code. An
# extension outside it reads as whole-file prose, and the Harper package ships
# a [*] section, so a binary reaching Vale reports against its bytes. A format
# association doesn't add an extension, because it targets a markup format.
prose::vale_reads() {
  local file="$1"
  local name="${file##*/}"
  local ext
  ext="$(printf '%s' "${name##*.}" | tr '[:upper:]' '[:lower:]')"

  # A file with no extension is a command or a git hook. Only its shebang
  # identifies it, and the Vale config gives those directories the Shell view
  # so the comments come out without the code.
  if [[ "${name}" != *.* ]]; then
    local first=''
    read -r first <"${file}" 2>/dev/null || return 1
    case "${first}" in
      '#!'*sh*) return 0 ;;
      *) return 1 ;;
    esac
  fi

  case "${ext}" in
    # Prose and markup Vale parses itself. adoc, rst and xml stay out: each
    # shells out to a binary the machine may lack and aborts the whole run,
    # losing every other file's alerts with it.
    md | html | txt) return 0 ;;
    # Comment syntax picks the View, not language family. These comment with #.
    sh | bash | zsh) return 0 ;;
    cfg | conf | example | fish | hcl | ini | nix) return 0 ;;
    properties | tf | tfvars | toml | yaml | yml) return 0 ;;
    # And these comment with //.
    mjs | cjs | gradle | json5 | kt | kts | query | rules) return 0 ;;
    c | h | cc | cp | cpp | cxx | 'c++' | hpp | 'h++') return 0 ;;
    cs | csx | clj | cljc | cljd | cljs | css | ex | exs) return 0 ;;
    go | gemspec | hs | java | bsh | js | jsx | jl | less | lua) return 0 ;;
    pl | pm | pod | php | proto | ps1 | psd1 | psm1) return 0 ;;
    py | py3 | pyw | cpy | rpy | qml | r | rb | rs) return 0 ;;
    sass | sbt | scala | scss | swift | ts | tsx) return 0 ;;
    # A Vue single-file component has three languages in one file, so no View
    # picks its comments out. cspell parses it and has a dictionary for it.
    vue) return 1 ;;
    # Everything else still reaches cspell, which parses any text file and
    # skips a binary on its own. Vale must not see it.
    *) return 1 ;;
  esac
}

# --no-global keeps the machine-level Vale config out. Vale merges that file
# into this one, so without the flag one person's own styles and switches
# decide what everyone else's run reports.
prose::vale() {
  [[ $# -gt 0 ]] || return 0
  printf '%s\0' "$@" \
    | xargs -0 vale --no-global --output=JSON 2>/dev/null \
    | prose::vale_lines || true
}

# Print the version the plugin's manifest declares. The prose hook writes it into
# each recheck and review-alerts counts only that version's, so both read it here.
prose::plugin_version() {
  jq -r .version "$(dirname "${BASH_SOURCE[0]}")/../.claude-plugin/plugin.json"
}

# Print the message in messages/$1.txt, with the rest of the arguments filling
# its %s placeholders in order.
prose::message() {
  local file template
  file="$(dirname "${BASH_SOURCE[0]}")/../messages/$1.txt"
  template="$(<"${file}")" || return 1
  shift
  # shellcheck disable=SC2059  # the template is the format
  printf "${template}\n" "$@"
}

# Point Vale at the config in $1 when it finds none from the working directory.
# $1 can be empty or missing, and then Vale keeps its own search.
#
# A config Vale finds but can't load stays in force. A fresh clone's config
# fails until its styles are synced, and the default would hide that.
prose::use_default_config() {
  [[ -n "$1" && -f "$1" ]] || return 0
  local err
  if err="$(vale --no-global ls-config 2>&1 >/dev/null)"; then
    return 0
  fi
  if [[ "${err}" == *'no config file found'* ]]; then
    export VALE_CONFIG_PATH="$1"
  fi
}

# Whether Vale loads a configuration from the working directory. Where it
# can't, say why on stderr. A run without one reports nothing on every file,
# which reads as clean.
prose::config_loads() {
  local err
  err="$(vale --no-global ls-config 2>&1 >/dev/null)" && return 0
  if [[ "${err}" == *'no config file found'* ]]; then
    prose::message lint-prose/no-config >&2
  else
    prose::message lint-prose/config-failed "${err}" >&2
  fi
  return 1
}

# $1 is a cspell configuration file to add, or empty. The rest are paths, which cspell
# reads as globs against the working directory, so an absolute path outside
# it matches nothing and cspell reports "Files checked: 0" rather than an
# error.
prose::cspell() {
  local config="$1"
  shift
  [[ $# -gt 0 ]] || return 0
  command -v cspell >/dev/null 2>&1 || return 0
  # shellcheck disable=SC2016  # cspell's own template placeholders
  printf '%s\n' "$@" \
    | cspell lint --no-progress --no-summary --no-exit-code \
      ${config:+-c "${config}"} \
      --issue-template $'$filename:$row:$col:cspell:$message\t\t$text' \
      --file-list stdin 2>/dev/null || true
}

# Print jq definitions for Vale's JSON report. `alerts` yields each alert with
# its Path. `line` prints one in Vale's line format. A tab follows it, then the
# rule's link, the flagged words, and each replacement, each after a tab. An
# error report has no array of alerts, so `alerts` yields nothing for it.
prose::vale_jq() {
  # shellcheck disable=SC2016  # jq's own variables
  printf '%s' 'def alerts: to_entries[] | select(.value | type == "array")
    | .key as $path | .value[] | . + {Path: $path};
  def flat: sub("[\t\n]"; " "; "g");
  def line: ["\(.Path):\(.Line):\(.Span[0]):\(.Check):\(.Message | flat)",
      (.Link // ""), (.Match // "" | flat)]
    + (if .Action.Name == "replace" then (.Action.Params // [] | map(flat)) else [] end)
    | join("\t");'
}

# Print Vale's JSON report, read from stdin, in Vale's line format.
prose::vale_lines() {
  local defs
  defs="$(prose::vale_jq)" || return 1
  jq -r "${defs} alerts | line"
}

# Print the alert lines on stdin in the GNU Coding Standards' error format,
# `file:line:column: message: 'words' [rule] (link)`, and any other line as it
# came. A rule that offers a replacement adds a `note:` line with it. The
# standard asks for no capital at the start of the message and no closing period.
prose::gnu_alerts() {
  # A capital followed by another capital starts an acronym, which keeps its case.
  jq -Rr '
    (split("\t") as $f
      | ($f[0] | capture("^(?<loc>.+?:[0-9]+:[0-9]+):(?<rule>[^:[:space:]]+):(?<msg>.*)$")) as $a
      | ($a.msg | sub("\\.$"; "")
        | if test("^[A-Z][a-z]") then (.[0:1] | ascii_downcase) + .[1:] else . end) as $msg
      | ($f[1] // "") as $link
      | ($f[2] // "") as $words
      | ($f[3:] | map(select(. != ""))) as $fixes
      | "\($a.loc): \($msg)"
        + (if $words == "" or ($msg | contains($words)) then "" else ": '\''\($words)'\''" end)
        + " [\($a.rule)]"
        + (if $link == "" then "" else " (\($link))" end),
        (if $fixes == [] then empty
          else "\($a.loc): note: replace '\''\($words)'\'' with "
            + ($fixes | map("'\''\(.)'\''") | join(" or "))
          end))
    // .'
}

# Run the linters over many files, one process each. Each Vale start reloads
# every package, which dominates a run over a branch's worth of files.
prose::lint_files() {
  local -a vale_files=()
  local f
  for f in "$@"; do
    if prose::vale_reads "${f}"; then
      vale_files+=("${f}")
    fi
  done
  prose::vale "${vale_files[@]}"
  prose::cspell '' "$@"
}

# Print the prose in a commit message file, and nothing else. Vale's View does
# this for Vale, and cspell has no View, so this is what cspell gets.
# shellcheck disable=SC2312  # every caller sets pipefail
prose::commit_text() {
  # stripspace drops comment lines but not what follows the scissors line, and
  # `git commit -v` puts the staged diff there.
  local message
  message="$(sed -E '/^[^ ]+ -+ >8 -+$/,$d' "$1" \
    | git stripspace --strip-comments)" || return 1

  # Git decides what counts as a trailer, so ask it rather than matching a
  # line pattern. Git normalizes its output, joining folds and collapsing
  # spacing, so it can't be cut from the message by matching text. Git only
  # finds trailers in the last paragraph, so that paragraph is what goes.
  local trailers
  trailers="$(git interpret-trailers --only-trailers --parse <<<"${message}")" \
    || return 1
  if [[ -n "${trailers}" ]]; then
    message="${message%$'\n\n'*}"
  fi

  # A project key takes digits after its first letter, so the leading class
  # can't be letters alone.
  sed -E '1s/^[a-z]+(\([^)]+\))?!?: //; 1s/^\[[A-Za-z][A-Za-z0-9]*-[0-9]+\] //' \
    <<<"${message}"
}

# Lint a commit message file. $1 is the file, and $2 a cspell configuration
# file to add, or empty. Run it from the repository, so Vale finds its
# .vale.ini, or call prose::use_default_config there first.
#
# Vale gets the file whole under the name the package's commit section
# matches, so a Vale column is the file's column. A cspell column counts from
# the start of the stripped subject.
prose::lint_commit() {
  vale --no-global --output=JSON --path=COMMIT_EDITMSG <"$1" 2>/dev/null \
    | prose::vale_lines || true
  command -v cspell >/dev/null 2>&1 || return 0
  local text
  text="$(prose::commit_text "$1")" || return 1
  # shellcheck disable=SC2016  # cspell's own template placeholders
  cspell lint --no-progress --no-summary --no-exit-code \
    ${2:+-c "$2"} \
    --issue-template '$filename:$row:$col:cspell:$message ($text)' \
    stdin://COMMIT_EDITMSG <<<"${text}" 2>/dev/null || true
}

# Print the new-side line numbers a diff's hunks touch, from `git diff -U0`.
# A hunk that only deletes touches the lines either side of the gap, because
# joining them can make a sentence that wasn't there.
prose::touched_lines() {
  awk '/^@@ / {
    split($3, range, ",")
    start = substr(range[1], 2) + 0
    count = (2 in range) ? range[2] + 0 : 1
    if (count == 0) {
      if (start > 0) print start
      print start + 1
    }
    for (i = start; i < start + count; i++) print i
  }'
}

# Widen touched lines to the prose block each sits in, and print each as
# path:line. $1 is the file, $2 is 1 when every non-blank line is prose, and $3
# the touched lines. In a source file a block is a run of comment lines, so a
# code edit beside a comment leaves it out.
prose::block_lines() {
  # ENVIRON, because the BSD awk on macOS rejects a newline in an -v value.
  PROSE_TOUCHED="$3" awk -v all="$2" '
    {
      if (all) prose[NR] = ($0 ~ /[^[:space:]]/)
      else prose[NR] = ($0 ~ /^[[:space:]]*(#|\/\/|\/\*|\*|--|;|<!--)/)
      last = NR
    }
    END {
      count = split(ENVIRON["PROSE_TOUCHED"], lines, "\n")
      for (k = 1; k <= count; k++) {
        i = lines[k] + 0
        if (i < 1 || i > last) continue
        print FILENAME ":" i
        if (!prose[i]) continue
        for (j = i - 1; j >= 1 && prose[j]; j--) print FILENAME ":" j
        for (j = i + 1; j <= last && prose[j]; j++) print FILENAME ":" j
      }
    }' "$1"
}

# Keep the alerts that sit in a prose block the diff touched. The arguments
# go to `git diff`, and the alerts' paths are relative to the working
# directory. An alert sits on the line its sentence starts, so an edit further
# down the same sentence would never reach it by line alone.
#
# --no-ext-diff and --no-color, because diff.external and color.diff=always in a
# user's git config each change what the hunk headers look like.
prose::filter_touched() {
  local alerts
  alerts="$(cat)"
  [[ -n "${alerts}" ]] || return 0

  local paths
  paths="$(awk -F: '!seen[$1]++ { print $1 }' <<<"${alerts}")"

  local keep='' path hunks touched all
  while IFS= read -r path; do
    if [[ -z "${path}" || ! -f "${path}" ]]; then
      continue
    fi
    hunks="$(git diff --no-color --no-ext-diff -U0 "$@" -- "${path}")" || return 1
    touched="$(prose::touched_lines <<<"${hunks}")"
    if [[ -z "${touched}" ]]; then
      continue
    fi
    all=0
    case "${path##*.}" in md | txt | html) all=1 ;; esac
    keep+="$(prose::block_lines "${path}" "${all}" "${touched}")"$'\n'
  done <<<"${paths}"

  [[ -n "${keep//$'\n'/}" ]] || return 0
  # ENVIRON, because awk -v reads a backslash in a path as an escape.
  PROSE_KEEP="${keep}" awk -F: '
    BEGIN {
      count = split(ENVIRON["PROSE_KEEP"], lines, "\n")
      for (k = 1; k <= count; k++) wanted[lines[k]] = 1
    }
    ($1 ":" $2) in wanted
  ' <<<"${alerts}"
}

# Print the alerts in $1 that a hook hands back, with a count of the rest.
# shellcheck disable=SC2312  # every caller sets pipefail
prose::hook_alerts() {
  # Past forty nobody reads the list, and the ones at the top are the ones to
  # act on.
  local max=40
  local total
  total="$(printf '%s\n' "$1" | wc -l | tr -d ' ')"
  if [[ "${total}" -le "${max}" ]]; then
    printf '%s\n' "$1"
    return 0
  fi
  printf '%s\n' "$1" | head -n "${max}"
  prose::message lint-prose/more-alerts "$((total - max))"
}

# Print the parent folder of every session's folder.
prose::sessions_dir() {
  [[ -n "${CLAUDE_PLUGIN_DATA:-}" ]] || return 1
  printf '%s\n' "${CLAUDE_PLUGIN_DATA}/sessions"
}

# Print the folder where the prose hook keeps session $1's alerts.
prose::session_dir() {
  # The session id becomes a folder name.
  [[ "$1" =~ ^[A-Za-z0-9_-]+$ ]] || return 1
  local root
  root="$(prose::sessions_dir)" || return 1
  printf '%s/%s\n' "${root}" "$1"
}

# Record the caller's parent as the process that owns session folder $1. A hook
# with args runs with no shell between it and Claude Code, so the parent is the
# session's process. Through a shell, the parent exits at once.
prose::claim_session_dir() {
  printf '%s\n' "${PPID}" >"$1/pid"
}

# Whether the process that last claimed session folder $1 still runs. A reused
# process id keeps a folder until that process exits too.
prose::session_dir_claimed() {
  local pid=''
  { read -r pid <"$1/pid"; } 2>/dev/null || return 1
  [[ "${pid}" =~ ^[0-9]+$ ]] && kill -0 "${pid}" 2>/dev/null
}

# Print a PostToolUse hook's JSON that hands the alerts back as context. $1
# is the alerts from prose::hook_alerts, and $2 the message that goes above them.
prose::hook_context() {
  local msg='' alerts
  msg="$(prose::message "$2")" || msg=''
  alerts="$(prose::gnu_alerts <<<"$1")" || return 1

  jq -n --arg context "${msg}

${alerts}" \
    '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$context}}'
}

# Print the alerts, at most $1 of them where $1 isn't 0. Past the limit,
# print a count per rule instead of the rest.
# shellcheck disable=SC2312  # every caller sets pipefail
prose::report() {
  # Bash arithmetic reads a leading zero as octal, and 08 isn't octal.
  local limit="$((10#$1))"
  local alerts="$2"

  local total
  total="$(printf '%s\n' "${alerts}" | wc -l | tr -d ' ')"

  if [[ "${limit}" -eq 0 || "${total}" -le "${limit}" ]]; then
    prose::gnu_alerts <<<"${alerts}"
    return 0
  fi

  printf '%s\n' "${alerts}" | head -n "${limit}" | prose::gnu_alerts
  printf '\n[%d more alerts, not shown. Pass --limit 0 for all.]\n\n' \
    "$((total - limit))"

  # The tally is what the list past the limit can't say: one rule with
  # hundreds of hits is a question about that rule, not about hundreds of
  # lines. Field 4 of the line format is the rule name.
  printf 'Alerts by rule:\n'
  printf '%s\n' "${alerts}" | cut -d: -f4 | sort | uniq -c | sort -rn
}

# Print each file in the alert lines on stdin with its count of Vale alerts,
# highest first. A file whose only alerts are cspell's prints nothing.
# shellcheck disable=SC2312  # every caller sets pipefail
prose::report_by_file() {
  awk -F: '$4 != "cspell" { print $1 }' | sort | uniq -c | sort -k1,1nr -k2
}
