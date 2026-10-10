# AgentProse

A Vale package and a Claude Code plugin that lint the prose an agent writes.

## Setup

```sh
mise trust && mise install
git config core.hooksPath githooks
```

`mise.toml` pins every tool the gate runs, and CI installs from the same file. mise ignores a repository's `mise.toml` until you trust it.

Git never installs a hook from a checkout, so neither hook runs until you set `core.hooksPath`.

## The gate

`tools/check` is the gate, and CI runs the same command. Judge it by its exit code: `0` passed, anything else failed. Never pipe it into `tail` or `grep`, because a pipeline reports the filter's status and the failure disappears.

`tools/check --fix` applies shfmt's and Prettier's formatting first, then reports.

The commands live in `tools/` and not `bin/`, a name Claude Code reserves. A plugin's `bin/` goes on the Bash tool's PATH, and claude.ai and Cowork refuse to install a plugin that has one.

## How the markdown here is written

Write each paragraph and each list item on one line, with no hard wrap. Prettier's `proseWrap: "never"` enforces it, and `tools/check --fix` joins any wrapped lines. Vale matches `^` and `$` at every line, and a rule's literal space never matches a line break. A wrap inside a sentence then makes rules fire on the wrong words or miss the right ones. To review a change to a long line, run `git diff --word-diff`.

## Commits and releases

A commit message follows Conventional Commits, and commitlint checks it in the `commit-msg` hook and in CI. The type matters beyond style: release-please reads it on `main` to pick the next version and write the changelog. A `feat` bumps the minor version and a `fix` the patch.

release-please keeps a release pull request open. Merging it tags the release, and the release workflow attaches `AgentProse.zip` to it.

## How a command here behaves

[clig.dev](https://clig.dev) decides it. Nothing checks this, so it's on you. What it means for every file in `tools/`:

- `--help` prints a usage line, the options, and what the exit codes mean.
- Exit `0` on success. A command that checks something exits `1` when the check found something, as ShellCheck does. A command that reports, such as `review-alerts`, exits `0` whatever is in the report. A failure exits with its `sysexits(3)` code, from `lib/sysexits.sh`: `64` for wrong arguments, and the rest by the man page's definitions.
- A finding goes to stdout. A diagnostic goes to stderr.
- A long report has a limit, and says how to ask for the rest.
- A sentence a person or an agent reads goes in `messages/`, one file per message, and prints through `prose::message`. The gate lints every file there with the package. `--help` text and argument errors stay inline, because they're structured output and not prose.

## How the shell here is written

The configuration decides it, and the gate enforces it: `.shellcheckrc` for shellcheck, `.editorconfig` for shfmt. Read those two files rather than any description of them.

One naming rule breaks the style guide on purpose. A command takes hyphens, `lint-branch-prose` and not `lint_branch_prose`, because that's what a person typing it expects.

## How the spelling gate decides

Teach cspell what a file is before you teach it a word. A shell script with no extension has no language, so cspell flags every builtin in it as a misspelling. One `languageId` override retires a dozen word entries, and keeps retiring them as the scripts grow. Reach for the word list only for a name no dictionary could hold.

## What belongs in a comment

Only what the code can't say: a cost nobody would expect, or an approach that looks right and fails. Never what the code does, and never a count, which goes stale on the next edit. What you learned while doing the work belongs in the commit message.

## Agent skills

### Issue tracker

Issues live as markdown files under `.scratch/<feature>/` in this repository, which git ignores. See `docs/agents/issue-tracker.md`.

### Triage labels

The five default triage labels, each named for its role. See `docs/agents/triage-labels.md`.

### Domain docs

One `CONTEXT.md` and one `docs/adr/` at the repository root. See `docs/agents/domain.md`.
