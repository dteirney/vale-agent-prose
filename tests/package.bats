#!/usr/bin/env bats
#
# The package is the published artifact, and it only breaks at a consumer's
# `vale sync`. Every test installs it into a throwaway consumer the way a
# stranger would, and asserts on what a stranger would then see.
#
# setup_file runs the sync once, because each sync fetches every package over
# the network.

setup_file() {
  # Every test writes its probe to the same few file names.
  export BATS_NO_PARALLELIZE_WITHIN_FILE=true
  REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  export REPO
  CONSUMER="$(mktemp -d)"
  export CONSUMER
  printf 'StylesPath = styles\nPackages = %s/package\n' "${REPO}" \
    >"${CONSUMER}/.vale.ini"
  vale --config="${CONSUMER}/.vale.ini" sync >/dev/null
}

teardown_file() {
  rm -rf "${CONSUMER}"
}

# Lint one string and print the alerts. --no-global keeps a developer's own
# machine config out of the result.
lint() {
  printf '%s\n' "$1" >"${CONSUMER}/probe.md"
  vale --no-global --config="${CONSUMER}/.vale.ini" --output=line \
    "${CONSUMER}/probe.md" 2>&1 || true
}

@test "every message the plugin prints passes its own lint" {
  # Without this probe the test would pass on a config that skips text files.
  printf '%s\n' 'Vale simply reports nothing.' >"${CONSUMER}/probe.txt"
  run vale --no-global --config="${CONSUMER}/.vale.ini" --output=line \
    "${CONSUMER}/probe.txt"
  [[ "${output}" == *'AiTells.Adverb'* ]]

  local files=()
  mapfile -t files < <(find "${REPO}/messages" -type f -name '*.txt')
  [[ "${#files[@]}" -gt 0 ]]
  run vale --no-global --config="${CONSUMER}/.vale.ini" --output=line \
    "${files[@]}"
  printf '%s\n' "${output}"
  [[ "${status}" -eq 0 && -z "${output}" ]]
}

@test "sync installs every style the config names" {
  for style in AgentProse AiTells Google Harper proselint Slop Std; do
    [ -d "${CONSUMER}/styles/${style}" ]
  done
}

@test "a triad joined by or is caught" {
  run lint 'The gate needs clarity, discipline, or rigor before anyone trusts it.'
  [[ "${output}" == *'AgentProse.AbstractTriad'* ]]
}

@test "a triad joined by and is caught" {
  run lint 'The gate needs clarity, discipline, and rigor before anyone trusts it.'
  [[ "${output}" == *'AgentProse.AbstractTriad'* ]]
}

@test "the upstream triad rule is off, so one span reports once" {
  run lint 'The gate needs clarity, discipline, and rigor before anyone trusts it.'
  [[ "${output}" != *'AiTells.AbstractTriad'* ]]
}

@test "an inanimate subject taking an active verb is caught" {
  run lint 'Metadata carried by each column decides the sort order.'
  [[ "${output}" == *'AgentProse.InanimateVerb'* ]]
}

# The rule exists because Slop.Anthropomorphism targets intent verbs and finds
# no inanimate subject taking an active one. If this starts failing, upstream
# has widened and the local rule may be redundant.
@test "no upstream rule catches that same line" {
  run lint 'Metadata carried by each column decides the sort order.'
  [[ "${output}" != *'Anthropomorphism'* ]]
}

# The verb that got a sentence of this shape into a file in this repository.
@test "a verb outside the carry and hold pair is caught" {
  run lint 'Without this the gate runs only in CI and a message reaches nobody.'
  [[ "${output}" == *'AgentProse.InanimateVerb'* ]]
}

@test "every ungated verb in the second group is caught" {
  local verb
  for verb in reaches enables unlocks governs dictates; do
    run lint "The release job ${verb} every file in the repository."
    [[ "${output}" == *'AgentProse.InanimateVerb'* ]] || return 1
  done
}

# These verbs are also common plural nouns, so the rule asks for a determiner after
# the verb. Both halves matter: without the gate the noun reports, and without
# the pattern the verb does not.
@test "a noun-shaped verb taking an object is caught" {
  local verb
  for verb in drives powers surfaces demands; do
    run lint "The release job ${verb} the build for every package."
    [[ "${output}" == *'AgentProse.InanimateVerb'* ]] || return 1
  done
}

@test "the same words as plural nouns stay quiet" {
  run lint 'Two disk drives failed, and the surfaces showed no wear at all.'
  [[ "${output}" != *'AgentProse.InanimateVerb'* ]]
}

@test "a deduction between two negations is caught" {
  run lint 'A readability score names no span, so it licenses no rewrite here.'
  [[ "${output}" == *'AgentProse.NegDeduction'* ]]
}

# The rule exists because both upstream forms need a different shape:
# AiTells.EpigramContrast wants a literal ", not " after a copula, and
# Slop.NegativeParallelism wants "not just X, it's Y".
@test "neither upstream negation rule reaches that same line" {
  run lint 'A readability score names no span, so it licenses no rewrite here.'
  [[ "${output}" != *'EpigramContrast'* ]]
  [[ "${output}" != *'NegativeParallelism'* ]]
}

# Slop.Tricolon excludes plain three-item lists in its own comment, so the
# local triad rule is an addition rather than a duplicate.
@test "the upstream tricolon rule leaves a noun triad alone" {
  run lint 'The gate needs clarity, discipline, and rigor before anyone trusts it.'
  [[ "${output}" != *'Tricolon'* ]]
}

# Lint a file of the given name holding the given lines, and print the alerts.
lint_source() {
  local name="$1"
  shift
  printf '%s\n' "$@" >"${CONSUMER}/${name}"
  vale --no-global --config="${CONSUMER}/.vale.ini" --output=line \
    "${CONSUMER}/${name}" 2>&1 || true
}

readonly LONG_FIRST='This sentence keeps going and going with clause after clause after clause so'
readonly LONG_SECOND='that it sails far past the twenty-five word threshold the rule enforces here.'

# One file per route a comment takes into Vale: a grammar for each line and
# block syntax, and each View. Wrapping the sentence proves the whole comment
# arrives as one piece of prose.
long_sentence_caught() {
  run lint_source "$@"
  [[ "${output}" == *'Std.Readability.SentenceLength:Long sentence: 27 words.'* ]] \
    || { printf 'no alert through %s:\n%s\n' "$1" "${output}"; return 1; }
}

@test "a long sentence wrapped across comment lines is caught on every route" {
  mkdir -p "${CONSUMER}/tools"
  long_sentence_caught probe.py "# ${LONG_FIRST}" "# ${LONG_SECOND}" 'x = 1'
  long_sentence_caught probe.go "// ${LONG_FIRST}" "// ${LONG_SECOND}" 'var x = 1'
  long_sentence_caught probe.c "/* ${LONG_FIRST}" "   ${LONG_SECOND} */" 'int x;'
  long_sentence_caught probe.lua "-- ${LONG_FIRST}" "-- ${LONG_SECOND}" 'x = 1'
  long_sentence_caught probe.sh "# ${LONG_FIRST}" "# ${LONG_SECOND}" 'true'
  long_sentence_caught tools/probe "# ${LONG_FIRST}" "# ${LONG_SECOND}" 'true'
  long_sentence_caught probe.mjs "// ${LONG_FIRST}" "// ${LONG_SECOND}" 'export const x = 1;'
}

# The line-comment marker a probe for this extension writes, or nothing for an
# extension the table doesn't know, which fails the test below.
comment_marker() {
  case "$1" in
    sh | bash | zsh | cfg | conf | example | fish | hcl | ini | nix | properties | tf | tfvars) printf '#' ;;
    toml | yaml | yml | py | py3 | pyw | cpy | rpy | r | rb | pl | pm | pod | ex | exs | jl) printf '#' ;;
    gemspec | ps1 | psd1 | psm1) printf '#' ;;
    c | h | cc | cp | cpp | cxx | 'c++' | hpp | 'h++' | cs | csx | go | java | bsh | js | jsx) printf '//' ;;
    kt | kts | less | php | proto | qml | rs | sass | sbt | scala | scss | swift | ts | tsx) printf '//' ;;
    mjs | cjs | gradle | json5 | query | rules) printf '//' ;;
    lua | hs) printf -- '--' ;;
    clj | cljc | cljd | cljs) printf ';' ;;
    *) ;;
  esac
}

# Count the alerts of rule $2 on line $3 of the alerts in $1.
count_at() {
  grep -c "^[^:]*:$3:[0-9]*:$2" <<<"$1" || true
}

# Write the probe for extension $1, or fail for an extension the marker table
# doesn't know.
write_probe() {
  local ext="$1" marker
  if [[ "${ext}" == css ]]; then
    printf '%s\n' '/* Here we simply do not stop. */' 'a { content: "we simply do not"; }' \
      "/* ${LONG_FIRST}" "   ${LONG_SECOND} */" >"${CONSUMER}/probe.${ext}"
    return 0
  fi
  marker="$(comment_marker "${ext}")"
  [[ -n "${marker}" ]] || return 1
  {
    # PHP reads nothing before its opening tag.
    if [[ "${ext}" == php ]]; then
      printf '<?php\n'
    fi
    printf '%s\n' "${marker} Here we simply do not stop." 'x = "we simply do not"' \
      "${marker} ${LONG_FIRST}" "${marker} ${LONG_SECOND}"
  } >"${CONSUMER}/probe.${ext}"
}

# Each extension the package lints as source gets one probe: a comment the
# rules must report once, a string literal they must leave alone, and a
# sentence wrapped over two comment lines that must arrive as one sentence.
# The list comes from the package's own sections, so an extension added there
# can't skip this.
@test "every source extension reports a comment once, a string never, and a wrapped sentence whole" {
  local exts
  exts="$(sed -n 's/^\[\*\.{\{0,1\}\([^]}]*\)}\{0,1\}\]$/\1/p' "${REPO}/package/.vale.ini" | tr ',' '\n')"
  [[ -n "${exts}" ]]

  local ext header all out failures=''
  local -a files=()
  while IFS= read -r ext; do
    case "${ext}" in md | txt | html) continue ;; esac
    if write_probe "${ext}"; then
      files+=("${CONSUMER}/probe.${ext}")
    else
      failures+=" ${ext}(no marker)"
    fi
  done <<<"${exts}"
  [[ "${#files[@]}" -gt 0 ]]

  # One run, because each Vale start reloads every package. A run that Vale
  # aborts fails every extension at once.
  all="$(vale --no-global --config="${CONSUMER}/.vale.ini" --output=line \
    "${files[@]}" 2>&1)" || true

  local file
  for file in "${files[@]}"; do
    ext="${file##*.}"
    header=0
    if [[ "${ext}" == php ]]; then
      header=1
    fi
    out="$(grep -F "/probe.${ext}:" <<<"${all}")" || out=''

    [[ "$(count_at "${out}" AiTells.Adverb $((header + 1)))" -eq 1 ]] || failures+=" ${ext}(comment)"
    [[ "$(count_at "${out}" AiTells.Adverb $((header + 2)))" -eq 0 ]] || failures+=" ${ext}(string)"
    # Vale reads Clojure and PowerShell comments by pattern, and mapping them
    # to md fails the run, so their comment lines stay apart.
    case "${ext}" in clj | cljc | cljd | cljs | ps1 | psd1 | psm1) continue ;; esac
    [[ "$(count_at "${out}" Std.Readability.SentenceLength $((header + 3)))" -eq 1 ]] \
      || failures+=" ${ext}(wrapped)"
  done

  [[ -z "${failures}" ]] || { printf 'failed:%s\n' "${failures}"; return 1; }
}

# A pattern-read language mapped to md fails the whole run with E100, which
# would take every other file's alerts with it.
@test "a powershell file still lints its comments" {
  run lint_source probe.ps1 '# Here we simply do not stop.' '$x = 1'
  [[ "${output}" != *'E100'* ]]
  [[ "${output}" == *'AiTells.Adverb'* ]]
}

@test "a shellcheck directive reports nothing, and the reason after it still lints" {
  run lint_source probe.sh '#!/usr/bin/env bash' \
    '# shellcheck source=lib/prose.sh' \
    '# shellcheck disable=SC2310  # a failure here simply ends the hook'
  [[ "${output}" != *'SourcePath'* ]]
  [[ "${output}" == *'AiTells.Adverb'* ]]
}

# Every extension the source-file section names needs an md mapping, or its
# comments lose the sentence rules without anything failing.
@test "every grammar-read extension maps to md" {
  local section
  section="$(sed -n 's/^\[\*\.{\(c,h,cc[^}]*\)}\]$/\1/p' "${REPO}/package/.vale.ini")"
  [[ -n "${section}" ]]
  local ext missing=''
  IFS=',' read -r -a exts <<<"${section}"
  for ext in "${exts[@]}"; do
    case "${ext}" in clj | cljc | cljd | cljs | ps1 | psd1 | psm1) continue ;; esac
    grep -qxF "${ext} = md" "${REPO}/package/.vale.ini" || missing+=" ${ext}"
  done
  [[ -z "${missing}" ]] || { printf 'no md mapping:%s\n' "${missing}"; return 1; }
}

# Vale compiles every token in multiline mode, so `^` and `$` match at each line
# a hard wrap makes. These rules anchor to the whole scope with \A and \z, and
# their upstream originals, anchored with ^ and $, are off.
@test "a wrap after a two-item phrase reports no missing serial comma" {
  run lint $'It judges each alert, as a false positive or a rule\nthat was right.'
  [[ "${output}" != *'OxfordComma'* ]]
}

@test "a list missing its serial comma is caught once" {
  run lint 'The installer copies binaries, styles and vocabularies.'
  [[ "${output}" == *'AgentProse.OxfordComma'* ]]
  [[ "${output}" != *'Std.Punctuation.OxfordComma'* ]]
}

@test "a discourse marker a wrap puts first on a line reports nothing" {
  run lint $'The hook keeps them per file, and nothing\nhowever small is lost.'
  [[ "${output}" != *'DiscourseMarkers'* ]]
}

@test "a sentence opening with a discourse marker is caught once" {
  run lint 'However the hook keeps them per file.'
  [[ "${output}" == *'AgentProse.DiscourseMarkers'* ]]
  [[ "${output}" != *'Harper.DiscourseMarkers'* ]]
}

@test "a but a wrap puts first on a comment line reports nothing" {
  run lint_source probe.sh '#!/usr/bin/env bash' \
    '# The sweep runs at every start and deletes the folder of each dead session.' \
    '# But it skips a live one.' 'true'
  [[ "${output}" != *'.But:'* ]]
}

@test "a paragraph opening with but is caught once" {
  run lint 'But the sweep skips a live session.'
  [[ "${output}" == *'AgentProse.But'* ]]
  [[ "${output}" != *'proselint.But'* ]]
}

# A literal space in a token can't match the line break a hard wrap leaves, so
# these rules span their gaps with one that crosses a single line break.
@test "an inanimate verb wrapped before its object is caught" {
  run lint $'The release job drives\nthe build for every package.'
  [[ "${output}" == *'AgentProse.InanimateVerb'* ]]
}

@test "a blank line between the verb and its object reports nothing" {
  run lint $'The release job drives\n\nthe build for every package.'
  [[ "${output}" != *'AgentProse.InanimateVerb'* ]]
}

@test "two examples after such as report no missing serial comma" {
  run lint 'It is repository-only when its prose produces it, such as its domain words or its house register.'
  [[ "${output}" != *'OxfordComma'* ]]
}

@test "a list after such as still misses its serial comma" {
  run lint 'The cache holds small files, such as configs, locks and logs.'
  [[ "${output}" == *'AgentProse.OxfordComma'* ]]
}

@test "a list wrapped before its last item still misses its serial comma" {
  run lint $'The installer copies binaries, styles and\nvocabularies.'
  [[ "${output}" == *'AgentProse.OxfordComma'* ]]
}

@test "a discourse marker wrapped inside its phrase is caught" {
  run lint $'On the other\nhand we could delay the deployment.'
  [[ "${output}" == *'AgentProse.DiscourseMarkers'* ]]
}

@test "a discourse marker wrapped before its clause is caught" {
  run lint $'For example\nI recommend updating the configuration.'
  [[ "${output}" == *'AgentProse.DiscourseMarkers'* ]]
}

@test "reading ease stays quiet under a hundred words" {
  run lint 'Considerable administrative reorganization necessitated subsequent documentation modifications.'
  [[ "${output}" != *'FleschReadingEase'* ]]
}

# One sentence over the word gate, so only the sentence gate can stop it. The
# score itself is far below the threshold, which is what makes it a test.
@test "reading ease stays quiet under five sentences" {
  local clause='considerable administrative reorganization necessitating subsequent documentation modifications'
  local long='The organization reported'
  local i
  for ((i = 0; i < 15; i++)); do
    long+=" ${clause},"
  done
  run lint "${long} and nothing else."
  [[ "${output}" != *'FleschReadingEase'* ]]
}

@test "reading ease reports over a hundred words" {
  local sentence='Considerable administrative reorganization necessitated subsequent documentation modifications throughout the organization.'
  local long=''
  local i
  for ((i = 0; i < 15; i++)); do
    long+="${sentence} "
  done
  run lint "${long}"
  [[ "${output}" == *'AgentProse.FleschReadingEase'* ]]
}

@test "the simplified technical english style stays out" {
  run lint "It isn't a problem, because the gate doesn't read it."
  [[ "${output}" != *'STE.'* ]]
}
