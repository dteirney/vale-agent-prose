#!/usr/bin/env bats
#
# The shared helpers the hook and the prose commands source.

setup() {
  REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  # shellcheck source=lib/prose.sh
  source "${REPO}/lib/prose.sh"
  WORK="$(mktemp -d)"
}

teardown() {
  rm -rf "${WORK}"
}

@test "a shell command with no extension reaches Vale" {
  mkdir -p "${WORK}/tools"
  printf '#!/usr/bin/env bash\n' >"${WORK}/tools/cmd"
  prose::vale_reads "${WORK}/tools/cmd"
}

@test "a dot in a directory name doesn't count as an extension" {
  mkdir -p "${WORK}/a.b/tools"
  printf '#!/usr/bin/env bash\n' >"${WORK}/a.b/tools/cmd"
  prose::vale_reads "${WORK}/a.b/tools/cmd"
}

@test "a file with no extension and no shell shebang stays out" {
  printf 'plain text\n' >"${WORK}/notes"
  run prose::vale_reads "${WORK}/notes"
  [ "${status}" -eq 1 ]
}

# The extension gate and the package config each list the extensions Vale may
# read, and a file reaching one list but not the other is linted as whole-file
# prose or not at all.
config_extensions() {
  sed -nE 's/^\[\*\.\{?([^]}]*)\}?\]$/\1/p' "${REPO}/package/.vale.ini" \
    | tr ',' '\n' | sort -u
}

gate_extensions() {
  sed -n '/case "${ext}" in/,/esac/p' "${REPO}/lib/prose.sh" \
    | sed -nE "s/^ *([a-z0-9'+ |]+)\) return 0 ;;\$/\1/p" \
    | tr -d "' " | tr '|' '\n' | sort -u
}

@test "the gate passes every extension the package config lints" {
  local ext
  while read -r ext; do
    printf 'x\n' >"${WORK}/probe.${ext}"
    prose::vale_reads "${WORK}/probe.${ext}" || {
      printf 'not in the gate: %s\n' "${ext}"
      return 1
    }
  done < <(config_extensions)
}

@test "the package config lints every extension the gate passes" {
  # An extraction that broke would compare two empty lists and pass.
  [ -n "$(gate_extensions)" ]
  [ -n "$(config_extensions)" ]
  local missing
  missing="$(comm -23 <(gate_extensions) <(config_extensions))"
  [ -z "${missing}" ] || {
    printf 'not in the package config: %s\n' "${missing}"
    return 1
  }
}

@test "the hook past its cap says when the rest appear" {
  local alerts
  alerts="$(seq 1 41 | sed 's/.*/a.md:&:1:Std.Rule:message/')"
  run prose::hook_alerts "${alerts}"
  [ "$(grep -c 'Std.Rule' <<<"${output}")" -eq 40 ]
  [[ "${output}" == *'1 more alerts'*'next edit to this file lists its alerts again'* ]]
}

@test "an alert prints in the GNU error format, with its rule last" {
  run prose::gnu_alerts <<<$'a.md:2:5:Std.Rule:Long sentence: 27 words.\t\t'
  [ "${output}" = 'a.md:2:5: long sentence: 27 words [Std.Rule]' ]
}

@test "an alert's link prints after its rule" {
  run prose::gnu_alerts <<<$'a.md:2:5:Google.Parens:Use parentheses judiciously.\thttps://example.com/parens\t'
  [ "${output}" = 'a.md:2:5: use parentheses judiciously [Google.Parens] (https://example.com/parens)' ]
}

@test "an alert names its flagged words where its message doesn't" {
  run prose::gnu_alerts <<<$'a.md:2:5:Google.Parens:Use parentheses judiciously.\t\t(a shell script)'
  [ "${output}" = "a.md:2:5: use parentheses judiciously: '(a shell script)' [Google.Parens]" ]
}

@test "an alert whose message quotes its words doesn't name them twice" {
  run prose::gnu_alerts <<<$'a.md:1:1:AgentProse.ThereIs:\'There\'s\' opens the sentence.\t\tThere\'s'
  [ "${output}" = "a.md:1:1: 'There's' opens the sentence [AgentProse.ThereIs]" ]
}

@test "a rule's replacements print on a note line under the alert" {
  run prose::gnu_alerts <<<$'a.md:3:10:Harper.X:Prose usually spells this out.\t\tconfig\tconfiguration\tconfigurations'
  [ "${output}" = "a.md:3:10: prose usually spells this out: 'config' [Harper.X]
a.md:3:10: note: replace 'config' with 'configuration' or 'configurations'" ]
}

@test "an unknown word prints with the word cspell flagged" {
  run prose::gnu_alerts <<<$'a.md:7:16:cspell:Unknown word\t\tgate'
  [ "${output}" = "a.md:7:16: unknown word: 'gate' [cspell]" ]
}

@test "a message opening with an acronym keeps its capitals" {
  run prose::gnu_alerts <<<$'a.md:1:1:Slop.Vocabulary:LLM tell: \'delve\'.\t\tdelve'
  [ "${output}" = "a.md:1:1: LLM tell: 'delve' [Slop.Vocabulary]" ]
}

@test "a line that isn't an alert prints as it came" {
  run prose::gnu_alerts <<<'2 alerts you left still stand.'
  [ "${output}" = '2 alerts you left still stand.' ]
}

@test "the report past its limit prints a count per rule" {
  local alerts
  alerts="$(printf 'a.md:%d:1:Std.Rule:message\n' 1 2 3)"
  run prose::report 2 "${alerts}"
  [[ "${output}" == *'[1 more alerts, not shown.'* ]]
  [[ "${output}" == *'3 Std.Rule'* ]]
}
