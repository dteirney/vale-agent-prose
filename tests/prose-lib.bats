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

@test "the report past its limit prints a count per rule" {
  local alerts
  alerts="$(printf 'a.md:%d:1:Std.Rule:message\n' 1 2 3)"
  run prose::report 2 "${alerts}"
  [[ "${output}" == *'[1 more alerts, not shown.'* ]]
  [[ "${output}" == *'3 Std.Rule'* ]]
}
