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

@test "no records exits 1 and names the folder it searched" {
  mkdir "${CLAUDE_CONFIG_DIR}/projects"
  run review
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"${CLAUDE_CONFIG_DIR}/projects"* ]]
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
  [[ "${output}" == *'/home/dev/notes/notes.md'*'2 | The gate needs clarity, discipline, and rigor before anyone trusts it.'* ]]
  [[ "${output}" != *'names no span'* ]]
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
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"${CLAUDE_CONFIG_DIR}/projects"* ]]
}

@test "the same lines from another hook don't count" {
  rechecks_of Some.Rule persisted 5 | record_in -home-dev-notes/s1.jsonl
  jq -c '.attachment.command = "/usr/local/bin/other-hook.sh"' \
    "${CLAUDE_CONFIG_DIR}/projects/-home-dev-notes/s1.jsonl" \
    >"${CLAUDE_CONFIG_DIR}/projects/-home-dev-notes/s2.jsonl"
  rm "${CLAUDE_CONFIG_DIR}/projects/-home-dev-notes/s1.jsonl"
  run review
  [ "${status}" -eq 1 ]
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
  [ "${status}" -eq 2 ]
}

@test "an unknown option is a usage error" {
  run review --all
  [ "${status}" -eq 2 ]
}

@test "a non-numeric limit is a usage error" {
  run review --limit many
  [ "${status}" -eq 2 ]
}
