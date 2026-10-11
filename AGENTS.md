# AgentProse

A Vale package and a Claude Code plugin that lint the prose an agent writes.

## The gate

`tools/check` is the gate, and CI runs the same command. Judge it by its exit code: `0` passed, anything else failed. Never pipe it into `tail` or `grep`, because a pipeline reports the filter's status and the failure disappears.

## How the markdown here is written

Write each paragraph and each list item on one line, with no hard wrap. Prettier's `proseWrap: "never"` enforces it, and `tools/check --fix` joins any wrapped lines. Vale matches `^` and `$` at every line, and a rule's literal space never matches a line break. A wrap inside a sentence then makes rules fire on the wrong words or miss the right ones. To review a change to a long line, run `git diff --word-diff`.

## What belongs in a comment

Only what the code can't say: a cost nobody would expect, or an approach that looks right and fails. Never what the code does, and never a count, which goes stale on the next edit. What you learned while doing the work belongs in the commit message.

## Agent skills

### Issue tracker

Issues live as markdown files under `.scratch/<feature>/` in this repository, which git ignores. See `docs/agents/issue-tracker.md`.

### Triage labels

The five default triage labels, each named for its role. See `docs/agents/triage-labels.md`.

### Domain docs

One `CONTEXT.md` and one `docs/adr/` at the repository root. See `docs/agents/domain.md`.
