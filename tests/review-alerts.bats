#!/usr/bin/env bats
#
# tools/review-alerts, reading transcripts built from the prose hook's own
# recheck lines and the transcript record Claude Code keeps them in.

setup_file() {
  REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  export REPO
  FIXTURES="${BATS_TEST_DIRNAME}/fixtures/review-alerts"
  export FIXTURES
  VERSION="$(jq -r .version "${REPO}/.claude-plugin/plugin.json")"
  export VERSION
}

setup() {
  CLAUDE_CONFIG_DIR="$(mktemp -d)"
  export CLAUDE_CONFIG_DIR
}

teardown() {
  rm -rf "${CLAUDE_CONFIG_DIR}"
}

review() {
  "${REPO}/tools/review-alerts" "$@"
}

# Print $3 recheck lines for rule $1, each the fixture's $2 line, from plugin
# version $4 or the installed one.
rechecks_of() {
  local line i
  line="$(jq -c --arg rule "$1" --arg recheck "$2" --arg version "${4:-${VERSION}}" \
    'select(.recheck == $recheck) | .rule = $rule | .version = $version' \
    "${FIXTURES}/rechecks.jsonl")"
  for ((i = 0; i < $3; i++)); do
    printf '%s\n' "${line}"
  done
}

# Move each recheck line on stdin to repository $1, under configuration $2.
in_repository() {
  jq -c --arg root "$1" --arg config "$2" \
    '.root = $root | .config = $config | .file = $root + "/notes.md"'
}

# Append a prose hook record to transcript $1 in the projects folder, with
# stdin as the hook's stderr.
record_in() {
  local file="${CLAUDE_CONFIG_DIR}/projects/$1"
  mkdir -p "${file%/*}"
  jq -c --rawfile stderr /dev/stdin '.attachment.stderr = $stderr' \
    "${FIXTURES}/hook-success.json" >>"${file}"
}

# The rules the last run reported, in order, joined with commas.
ranked() {
  grep -oE '^[A-Za-z]+\.[A-Za-z]+' <<<"${output}" | paste -sd , -
}

@test "no records exits 0 and names the folder it searched" {
  mkdir "${CLAUDE_CONFIG_DIR}/projects"
  run review
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"${CLAUDE_CONFIG_DIR}/projects hold no rechecks"* ]]
}

@test "rules rank by persistence rate, and a rule needs five rechecks" {
  {
    rechecks_of Low.Rule persisted 1
    rechecks_of Low.Rule absent 4
    rechecks_of High.Rule persisted 4
    rechecks_of High.Rule absent 1
    rechecks_of Few.Rule persisted 4
  } | record_in -home-dev-notes/s1.jsonl
  run review
  [ "${status}" -eq 0 ]
  [ "$(ranked)" = High.Rule,Low.Rule ]
  [[ "$(grep '^High.Rule' <<<"${output}")" == *'80%'* ]]
  [[ "$(grep '^Low.Rule' <<<"${output}")" == *'20%'* ]]
}

@test "a rule shows its persisted alerts with their lines, and not its absent ones" {
  {
    rechecks_of Some.Rule persisted 2
    rechecks_of Some.Rule absent 3
  } | record_in -home-dev-notes/s1.jsonl
  run review
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'/home/dev/notes/notes.md'*'    1 | Intro.'*'  > 2 | The gate needs clarity, discipline, and rigor before anyone trusts it.'* ]]
  [[ "${output}" != *'names no span'* ]]
}

# The repository lines the last run printed.
repositories() {
  grep -E ': [0-9]+ persisted, (own|default)( and (own|default))? configurations?$' \
    <<<"${output}"
}

@test "a rule lists each repository its persisted alerts came from, with its configuration" {
  {
    rechecks_of Some.Rule persisted 3
    rechecks_of Some.Rule persisted 1 | in_repository /home/dev/site default
    rechecks_of Some.Rule absent 2 | in_repository /home/dev/other default
  } | record_in -home-dev-notes/s1.jsonl
  run review
  [ "${status}" -eq 0 ]
  [ "$(repositories)" = "$(printf '%s\n' \
    '  /home/dev/notes: 3 persisted, own configuration' \
    '  /home/dev/site: 1 persisted, default configuration')" ]
  [[ "${output}" != *'/home/dev/other'* ]]
}

@test "a repository that used two configurations lists once, with both" {
  {
    rechecks_of Some.Rule persisted 3
    rechecks_of Some.Rule persisted 1 | in_repository /home/dev/notes default
    rechecks_of Some.Rule absent 1
  } | record_in -home-dev-notes/s1.jsonl
  run review
  [ "${status}" -eq 0 ]
  [ "$(repositories)" = '  /home/dev/notes: 4 persisted, own and default configurations' ]
}

@test "a rule confined to one repository lists only that one" {
  {
    rechecks_of Some.Rule persisted 4
    rechecks_of Some.Rule absent 1
  } | record_in -home-dev-notes/s1.jsonl
  run review
  [ "${status}" -eq 0 ]
  [ "$(repositories)" = '  /home/dev/notes: 4 persisted, own configuration' ]
}

@test "an alert from a file outside any repository lists as outside any repository" {
  rechecks_of Some.Rule persisted 5 \
    | jq -c '.root = null | .config = "default"' \
    | record_in -home-dev/s1.jsonl
  run review
  [ "${status}" -eq 0 ]
  [ "$(repositories)" = '  outside any repository: 5 persisted, default configuration' ]
}

@test "a rule with no persisted alert lists no repositories" {
  rechecks_of Some.Rule absent 5 | record_in -home-dev-notes/s1.jsonl
  run review
  [ "${status}" -eq 0 ]
  [ "$(ranked)" = Some.Rule ]
  [[ "${output}" != *"$(<"${REPO}/messages/review-alerts/repositories.txt")"* ]]
}

# Print $3 persisted recheck lines for rule $1, each from file $2.
persisted_in() {
  rechecks_of "$1" persisted "$3" | jq -c --arg file "$2" '.file = $file'
}

# One rule's persisted alerts, each from its own file.
seven_alerts() {
  local i
  for i in 1 2 3 4 5 6 7; do
    persisted_in Some.Rule "/home/dev/notes/note-${i}.md" 1
  done | record_in -home-dev-notes/s1.jsonl
}

# The alert files the last run printed, joined with commas.
shown_alerts() {
  grep -oE '^  /home/dev/notes/note-[0-9]+\.md' <<<"${output}" \
    | sed 's/^  //' | paste -sd , -
}

@test "a rule prints five persisted alerts and says how to see the rest" {
  seven_alerts
  run review
  [ "${status}" -eq 0 ]
  [ "$(shown_alerts | tr ',' '\n' | wc -l | tr -d ' ')" -eq 5 ]
  [[ "${output}" == *"left out 2 of this rule's persisted alerts"*'--alert-limit'* ]]
}

@test "--alert-limit keeps the alerts that persisted most, each counted once" {
  {
    persisted_in Some.Rule /home/dev/notes/note-9.md 3
    persisted_in Some.Rule /home/dev/notes/note-1.md 1
    persisted_in Some.Rule /home/dev/notes/note-2.md 1
  } | record_in -home-dev-notes/s1.jsonl
  run review --alert-limit 2
  [ "${status}" -eq 0 ]
  [ "$(shown_alerts)" = /home/dev/notes/note-9.md,/home/dev/notes/note-1.md ]
  [[ "${output}" == *"left out 1 of this rule's persisted alerts"*'--alert-limit'* ]]
}

@test "an alert left out counts each time it persisted" {
  {
    persisted_in Some.Rule /home/dev/notes/note-9.md 3
    persisted_in Some.Rule /home/dev/notes/note-1.md 2
  } | record_in -home-dev-notes/s1.jsonl
  run review --alert-limit 1
  [ "${status}" -eq 0 ]
  [ "$(shown_alerts)" = /home/dev/notes/note-9.md ]
  [[ "${output}" == *"left out 2 of this rule's persisted alerts"* ]]
}

@test "--alert-limit 0 prints every alert" {
  seven_alerts
  run review --alert-limit 0
  [ "${status}" -eq 0 ]
  [ "$(shown_alerts | tr ',' '\n' | wc -l | tr -d ' ')" -eq 7 ]
  [[ "${output}" != *'--alert-limit'* ]]
}

# Twelve rules that each rank.
twelve_rules() {
  local i
  for i in A B C D E F G H I J K L; do
    rechecks_of "Rule.${i}" persisted 5
  done | record_in -home-dev-notes/s1.jsonl
}

@test "it shows ten rules and says how to see the rest" {
  twelve_rules
  run review
  [ "${status}" -eq 0 ]
  [ "$(ranked)" = Rule.A,Rule.B,Rule.C,Rule.D,Rule.E,Rule.F,Rule.G,Rule.H,Rule.I,Rule.J ]
  [[ "${output}" == *'--limit'* ]]
}

@test "--limit sets how many rules it shows, and 0 shows them all" {
  twelve_rules
  run review --limit 11
  [ "${status}" -eq 0 ]
  [ "$(ranked | tr ',' '\n' | wc -l | tr -d ' ')" -eq 11 ]
  run review --limit 0
  [ "$(ranked | tr ',' '\n' | wc -l | tr -d ' ')" -eq 12 ]
  [[ "${output}" != *'--limit'* ]]
}

@test "a zero-padded limit counts in decimal" {
  twelve_rules
  run review --limit 08
  [ "${status}" -eq 0 ]
  [ "$(ranked | tr ',' '\n' | wc -l | tr -d ' ')" -eq 8 ]
  [[ "${output}" != *'value too great'* ]]
}

@test "a record in a subagent's transcript counts" {
  rechecks_of Some.Rule persisted 3 | record_in -home-dev-notes/s1.jsonl
  rechecks_of Some.Rule persisted 2 \
    | record_in -home-dev-notes/s1/subagents/agent-a1.jsonl
  run review
  [ "${status}" -eq 0 ]
  [ "$(ranked)" = Some.Rule ]
}

@test "a record from an older plugin version doesn't count" {
  rechecks_of Some.Rule persisted 5 0.0.1 | record_in -home-dev-notes/s1.jsonl
  run review
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"${CLAUDE_CONFIG_DIR}/projects hold no rechecks"* ]]
}

@test "the same lines from another hook don't count" {
  rechecks_of Some.Rule persisted 5 | record_in -home-dev-notes/s1.jsonl
  jq -c '.attachment.command = "/usr/local/bin/other-hook.sh"' \
    "${CLAUDE_CONFIG_DIR}/projects/-home-dev-notes/s1.jsonl" \
    >"${CLAUDE_CONFIG_DIR}/projects/-home-dev-notes/s2.jsonl"
  rm "${CLAUDE_CONFIG_DIR}/projects/-home-dev-notes/s1.jsonl"
  run review
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'hold no rechecks'* ]]
}

@test "records with no rule that ranks exit 0 and say so" {
  rechecks_of Some.Rule persisted 4 | record_in -home-dev-notes/s1.jsonl
  run review
  [ "${status}" -eq 0 ]
  [ -z "$(ranked)" ]
  [[ "${output}" == *'4 rechecks'* ]]
}

@test "--help prints the usage and exits 0" {
  run review --help
  [ "${status}" -eq 0 ]
  [[ "${output}" == 'usage: review-alerts'* ]]
}

@test "an operand is a usage error" {
  run review somewhere
  [ "${status}" -eq 64 ]
}

@test "an unknown option is a usage error" {
  run review --all
  [ "${status}" -eq 64 ]
}

@test "a non-numeric limit is a usage error" {
  run review --limit many
  [ "${status}" -eq 64 ]
}

@test "a non-numeric alert limit is a usage error" {
  run review --alert-limit many
  [ "${status}" -eq 64 ]
}

@test "an alert limit with no count is a usage error" {
  run review --alert-limit
  [ "${status}" -eq 64 ]
}

@test "--help names the alert limit and its default" {
  run review --help
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'--alert-limit <n>'*'default 5'* ]]
}
