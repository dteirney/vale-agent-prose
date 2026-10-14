#!/usr/bin/env bats
#
# tools/lint-commit-prose drops the parts of a message that are format rather
# than prose. Each test here pairs a defect the command must report with one
# it must not, so a stripper that removed the whole message would fail too.

setup_file() {
  # Every test writes its message to the same file.
  export BATS_NO_PARALLELIZE_WITHIN_FILE=true
  REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  export REPO
  CONSUMER="$(mktemp -d)"
  export CONSUMER
  printf 'StylesPath = styles\nPackages = %s/package\n' "${REPO}" \
    >"${CONSUMER}/.vale.ini"
  vale --config="${CONSUMER}/.vale.ini" sync >/dev/null
  VALE_CONFIG_PATH="${CONSUMER}/.vale.ini"
  export VALE_CONFIG_PATH
  MSG="${CONSUMER}/COMMIT_EDITMSG"
  export MSG
}

teardown_file() {
  rm -rf "${CONSUMER}"
}

# The body defect every stripping test uses as its control. A test that loses
# this one has removed too much, not too little.
readonly BODY='A readability score names no span, so it licenses no rewrite here.'

lint_commit() {
  "${REPO}/tools/lint-commit-prose" "$@"
}

# Google.Parens reports the scope's parentheses when the prefix survives.
@test "the type prefix comes off the subject, and the column is the file's" {
  printf 'feat(gate)!: [K2S-1] add clarity, discipline, and rigor\n' >"${MSG}"
  run lint_commit "${MSG}"
  [[ "${output}" == *':1:26: '*'[AgentProse.AbstractTriad]'* ]]
  [[ "${output}" != *'Google.Parens'* ]]
}

# cspell reports the key's letters when the key survives. A project key
# holding a digit once did. cspell reports nothing for `QW2ZX`, so the digit
# here comes last.
# cspell:ignore qwzx
@test "a ticket key comes off the subject" {
  printf 'fix: [qwzx-42] add clarity, discipline, and rigor\n' >"${MSG}"
  run lint_commit "${MSG}"
  [[ "${output}" == *'AgentProse.AbstractTriad'* ]]
  [[ "${output}" != *'qwzx'* ]]
}

@test "a ticket key with a digit in the project comes off the subject" {
  printf 'fix: [QWZX2-42] add clarity, discipline, and rigor\n' >"${MSG}"
  run lint_commit "${MSG}"
  [[ "${output}" == *'AgentProse.AbstractTriad'* ]]
  [[ "${output}" != *'QWZX'* ]]
}

# Google.Exclamation reports the prefix when it survives. A rebase pairs a
# fixup commit with its target by the exact subject, so rewording isn't a fix.
@test "a fixup prefix comes off the subject, and the column is the file's" {
  printf 'fixup! feat: add clarity, discipline, and rigor\n' >"${MSG}"
  run lint_commit "${MSG}"
  [[ "${output}" == *':1:18: '*'[AgentProse.AbstractTriad]'* ]]
  [[ "${output}" != *'Google.Exclamation'* ]]
}

@test "stacked fixup and squash prefixes all come off the subject" {
  printf 'fixup! squash! feat: add clarity, discipline, and rigor\n' >"${MSG}"
  run lint_commit "${MSG}"
  [[ "${output}" == *'AgentProse.AbstractTriad'* ]]
  [[ "${output}" != *'Google.Exclamation'* ]]
}

# An amend commit's message replaces the original's, so its body still lints.
@test "an amend prefix comes off the subject, and the body still reports" {
  printf '%s\n\n%s\n' 'amend! fix: tidy the gate' "${BODY}" >"${MSG}"
  run lint_commit "${MSG}"
  [[ "${output}" == *'AgentProse.NegDeduction'* ]]
  [[ "${output}" != *'Google.Exclamation'* ]]
}

@test "a dotted name in backticks reports nothing in the subject, and a bare one does" {
  printf 'fix: call `config.Load` and config.Load first\n' >"${MSG}"
  run lint_commit "${MSG}"
  [ "$(grep -c 'Std.Punctuation.Spacing' <<<"${output}")" -eq 1 ]
}

@test "a sentence rule reaches the subject" {
  printf 'ci: add the gate, git hooks and release workflow\n' >"${MSG}"
  run lint_commit "${MSG}"
  [[ "${output}" == *'AgentProse.OxfordComma'* ]]
}

# The package's own route, the one a commit-msg hook without this command takes.
@test "vale alone leaves the trailers out under the commit message's name" {
  printf '%s\n\n%s\n\nRefs: this does not work\n' \
    'fix: tidy the gate' "${BODY}" >"${MSG}"
  run vale --output=line --path=COMMIT_EDITMSG <"${MSG}"
  [[ "${output}" == *'COMMIT_EDITMSG:3:'*'AgentProse.NegDeduction'* ]]
  [[ "${output}" != *'Contractions'* ]]
}

@test "git's comment block reports nothing, and the body still does" {
  printf '%s\n\n%s\n\n# This does not work for me.\n' \
    'fix: tidy the gate' "${BODY}" >"${MSG}"
  run lint_commit "${MSG}"
  [[ "${output}" == *'AgentProse.NegDeduction'* ]]
  [[ "${output}" != *'Contractions'* ]]
}

@test "a trailer reports nothing, and the body still does" {
  printf '%s\n\n%s\n\nRefs: this does not work\n' \
    'fix: tidy the gate' "${BODY}" >"${MSG}"
  run lint_commit "${MSG}"
  [[ "${output}" == *'AgentProse.NegDeduction'* ]]
  [[ "${output}" != *'Contractions'* ]]
}

@test "a folded trailer reports nothing, and the body still does" {
  printf '%s\n\n%s\n\nRefs:   this does not\n  work at all\n' \
    'fix: tidy the gate' "${BODY}" >"${MSG}"
  run lint_commit "${MSG}"
  [[ "${output}" == *'AgentProse.NegDeduction'* ]]
  [[ "${output}" != *'Contractions'* ]]
}

@test "the diff under a verbose commit's scissors line reports nothing" {
  printf '%s\n\n%s\n\n%s\n%s\n%s\n' 'fix: tidy the gate' "${BODY}" \
    '# ------------------------ >8 ------------------------' \
    'diff --git a/x.md b/x.md' \
    '+This does not work for me.' >"${MSG}"
  run lint_commit "${MSG}"
  [[ "${output}" == *'AgentProse.NegDeduction'* ]]
  [[ "${output}" != *'Contractions'* ]]
}

@test "a clean message exits 0 and says nothing" {
  printf 'fix: strip the ticket key from a subject line\n' >"${MSG}"
  run lint_commit "${MSG}"
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "a blocked message names the plugin and what to do after the alerts" {
  printf 'feat: add clarity, discipline, and rigor\n' >"${MSG}"
  run lint_commit "${MSG}"
  [[ "${output}" == *'AgentProse.AbstractTriad'*'vale-agent-prose blocked this commit'* ]]
}

@test "a message with an alert exits 1" {
  printf 'feat: add clarity, discipline, and rigor\n' >"${MSG}"
  run lint_commit "${MSG}"
  [ "${status}" -eq 1 ]
}

@test "no operand is a usage error" {
  run lint_commit
  [ "${status}" -eq 64 ]
}

@test "a missing file exits with no input" {
  run lint_commit "${CONSUMER}/nothing-here"
  [ "${status}" -eq 66 ]
}
