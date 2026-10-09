# vale-agent-prose

An AI slop linter for the prose a coding agent writes: markdown, the comments in a source file, and a commit message. It flags the tells of large language model (LLM) writing, such as abstract-noun triads, filler adverbs and clichés.

It ships two things. A Claude Code plugin that lints every file the agent writes and hands the alerts back to it. A [Vale](https://vale.sh) package that the plugin runs. It combines [vale-ai-tells](https://github.com/krishnasunkam/vale-ai-tells), [vale-llm-slop](https://github.com/Syntaf/vale-llm-slop), [Std](https://github.com/vale-cli/Std), Google, [Harper](https://github.com/vale-cli/Harper), [proselint](https://github.com/vale-cli/proselint) and write-good, and switches off the rules that only add noise.

## What it catches

A paragraph an agent might write:

```text
This refactor isn't just cleanup, it's a game-changer. The new cache unlocks speed, clarity, or trust across the pipeline. The retry layer keeps no state, so there's no race.
```

What the package reports on it:

```text
 1:15   suggestion  'not just X, but Y' escalation: say Y.                                                                   AiTells.NegParallel
 1:15   warning     Negative parallelism ('isn't just cleanup, it's') is a machine cadence. State the claim once.            Slop.NegativeParallelism
 1:21   suggestion  Filler adverb 'just': let the verb carry it.                                                             AiTells.Adverb
 1:42   suggestion  Cliche 'game-changer': cut it or say the literal thing.                                                  AiTells.Cliche
 1:42   warning     LLM tell: 'game-changer'.                                                                                Slop.Vocabulary
 1:70   suggestion  'unlocks': where the subject can't act, use is, has, with or from.                                       AgentProse.InanimateVerb
 1:78   suggestion  Abstract-noun triad 'speed, clarity, or trust': name one concrete thing instead of three abstractions.   AgentProse.AbstractTriad
 1:146  suggestion  Negated deduction 'no state, so there's no race': say what the thing does, then the action it licenses.  AgentProse.NegDeduction
```

An alert says a line matched a pattern, not that the line is wrong. The plugin's `settle-prose-alert` skill is how the agent decides which.

### What AgentProse adds

Rules the published packages miss:

| Rule | Catches |
| --- | --- |
| `InanimateVerb` | A subject that can't act taking an active verb |
| `NegDeduction` | A negation in two `no` phrases joined by `so` |
| `SourcePath` | A source file named in a comment, which a rename breaks |
| `FleschReadingEase` | A reading-ease score, gated so short text doesn't report |

It also replaces four upstream rules with copies. `AbstractTriad` copies `AiTells.AbstractTriad`, and widens it to catch three abstract nouns joined by `or`. The others copy `Std.Punctuation.OxfordComma`, `Harper.DiscourseMarkers` and `proselint.But`. Vale matches `^` and `$` at every line, so each original fires where a hard wrap starts or ends a line. Each copy anchors to the whole sentence or paragraph instead.

## Quick start with Claude Code

The plugin needs:

- `vale` 3.23.0 or later, and `jq`, on the PATH
- `cspell` on the PATH for spelling, which is optional
- git 2.54.0 or later for the commit message check

Install it:

```
/plugin marketplace add dteirney/vale-agent-prose
/plugin install vale-agent-prose@vale-agent-prose
```

Then run the setup skill once, and again in each repository with its own Vale configuration:

```
/vale-agent-prose:setup
```

It runs `tools/setup install`, which does three things:

- adds a `commit-msg` hook to your global git configuration
- syncs the default Vale configuration into the plugin's data directory
- syncs the styles that the current repository's own Vale configuration lists

To run the plugin from a checkout instead, add the checkout's path as the marketplace: `/plugin marketplace add /path/to/vale-agent-prose`. Claude Code then loads the plugin from that directory, and an edit there takes effect at the next session or `/reload-plugins`.

## Quick start with Vale alone

Add the package to your `.vale.ini` and sync:

```ini
StylesPath = styles
Packages = https://github.com/dteirney/vale-agent-prose/releases/latest/download/AgentProse.zip
```

```sh
vale sync
```

`latest` takes each release as it ships. To stay on one, name its tag instead: `releases/download/v0.1.0/AgentProse.zip`.

It needs Vale 3.23.0 or later. An older Vale reports some alerts on the wrong line.

## Commit messages

### With the plugin

The setup skill's `commit-msg` hook has git check a commit message before the commit lands. From then on, every `git commit` in every repository runs the check, whether the agent commits or you do. An alert stops the commit and prints why. The repository's own `commit-msg` hook still runs. Git 2.54.0 is the first release that runs a hook named in git's configuration.

After an uninstall, the hook lets every commit through. Ask the setup skill to remove the check to take the entry out of your git configuration.

### With Vale alone

Give Vale the message under the name `COMMIT_EDITMSG` and it lints the subject and the body. Git's comment lines, the diff under a verbose commit's scissors line, a type prefix, a ticket key, and the trailers stay out. A `commit-msg` hook gets the message file as `$1`:

```sh
#!/bin/sh
exec vale --path=COMMIT_EDITMSG < "$1"
```

Put it in the directory `git config core.hooksPath` names, or run the same line from husky, lefthook or pre-commit. In CI, lint the message of the commit a job runs on:

```sh
git log -1 --format=%B | vale --path=COMMIT_EDITMSG
```

Vale exits 0 when every alert is a warning or a suggestion, so the hook prints the alerts and the commit goes ahead.

The section names its own View, `CommitMessage`. Add the [Commits](https://github.com/jdkato/commits) package beside this one and its View replaces this one, even from your own `.vale.ini`. That View lints the trailers and the type prefix.

## How the plugin works

A `PostToolUse` hook on `Write` and `Edit` lints the file the agent wrote and returns the alerts as context. In a file git tracks, it reports every alert in each paragraph or comment the edit touched. A sentence the edit made too long reports even where it starts on an older line. An old comment the edit didn't touch stays out.

Missing `vale` or `jq`, the hook exits 0 and says nothing: a hook that can't read its input must never interrupt the turn.

A repository's own Vale configuration decides the rules. A repository with none gets the package, from the default configuration in the plugin's data directory. Both hooks use it. After a plugin update, a `SessionStart` hook syncs it again, which needs the network and takes a few seconds.

Another `SessionStart` hook warns you once per session when the prose hook would miss alerts. The causes are a missing tool, styles nobody has synced, and a Vale older than 3.23.0. It also warns when commit messages go unchecked. Each warning that setup can fix names the setup skill. Without the warning, a hook that never ran looks the same as a clean file.

To run the same check at any time, without changing anything:

```
/vale-agent-prose:doctor
```

cspell finds a repository's own configuration as usual. The hook also adds `~/.claude/cspell.json` when that file exists, or the same file under `$CLAUDE_CONFIG_DIR`. A word list you keep there applies in every repository.

### Reviewing the alerts that persist

The hook keeps the alerts it hands back, and rechecks them at the file's next edit. Each recheck goes to its stderr as one JSON line. The model never receives that line, but the session transcript keeps it. `tools/review-alerts` reads those lines from every transcript under `~/.claude/projects`, or the same folder under `$CLAUDE_CONFIG_DIR`, subagents included. It counts only the current plugin version's. It ranks the rules by how often their alerts persist, once a rule has five rechecks. Under each rule it lists the repositories its persisted alerts came from, with the Vale configuration each one used. Then it prints the persisted alerts with their lines. `--limit` caps the rules it prints and `--alert-limit` the alerts under each, and `--help` gives the defaults.

The review skill runs that command when you ask:

```
/vale-agent-prose:review-alerts
```

It judges each persisted alert from its line, as a false positive or a rule that was right. It sorts each false positive by the repositories in its rule's list. For one the package would raise anywhere, it drafts an issue for this repository. For one only your repository's prose raises, it shows the Vale configuration lines that switch the rule off there. It files nothing and edits nothing.

## Configuration

`StylesPath` and `Vocab` stay yours. The package sets neither, because a `StylesPath` is a path in your repository and a vocabulary is your own list of words.

### Set a Vocab if acronyms flag

Vale adds a vocabulary entry to every style's `exceptions` list, not only to spelling. Adding `GDAL` to `styles/config/vocabularies/Base/accept.txt` silences `Std.Abbreviations.Acronyms` on it, which is the one job this file still has. Spelling belongs to cspell, which knows the technical words a hand-written list would carry.

An entry is safe as a lowercase word only because `Vale.Terms` is off here. `HEAD`, `PUT` and `PATCH` each carry that collision.

### Comments in a source file

Vale reads the comments in most source files through its own tree-sitter grammars. Where it has none, the package ships a View. `Shell` reads anything commenting with `#`, including the commands with no extension in `bin/`, `tools/` and `githooks/`. `JavaScript` reads anything commenting with `//`, such as `.mjs` and `.json5`. A third View, `DataComments`, reads only the comments in YAML and TOML, where Vale would otherwise lint the string values too.

## The commands

| Command | Does |
| --- | --- |
| `tools/lint-prose <path>...` | Lint the paths you name. It walks a directory |
| `tools/lint-branch-prose` | Lint what this branch added |
| `tools/lint-commit-prose <file>` | Lint a commit message, minus its format |
| `tools/setup install <dir>` | Everything the setup skill does |
| `tools/doctor [<dir>]` | Check the setup, and change nothing |
| `tools/commit-hook install <dir>` | Add the global `commit-msg` hook alone |
| `tools/review-alerts` | Rank the rules whose alerts persist |

Each exits 0 when clean, 1 on a finding, and 2 on a usage error. Run any of them with `--help`. `tools/review-alerts` exits 1 when the transcripts hold no rechecks, and names the folder it searched.

`tools/lint-commit-prose` adds cspell to the Vale run in the commit message section, and exits 1 on an alert of any level.

## Reporting to a pull request

`vale --output=rdjsonl.tmpl` renders alerts as rdjsonl, with the severity and the rule's doc link that an errorformat parse drops. `vale sync` installs the template, and the name needs its extension:

```sh
vale --output=rdjsonl.tmpl . | reviewdog -f=rdjsonl -reporter=github-pr-review
```

The commands above don't use it, because reviewdog's local reporter prints rdjsonl back unchanged.

## Files the plugin keeps

The prose hook keeps the alerts it hands back in the plugin's data directory, with one folder per session. A `SessionEnd` hook deletes the folder when the session ends. A crash skips that hook, so a `SessionStart` hook deletes any folder whose Claude Code process has exited.

The commit message hook runs a copy of the check that the plugin keeps in its data directory, so an update doesn't move it. An uninstall removes the copy, which is why the hook then lets every commit through.

## Related

[vale-cli/agent-tools](https://github.com/vale-cli/agent-tools) is Vale's own Claude Code plugin.

## Contributing

Read [CONTRIBUTING.md](.github/CONTRIBUTING.md) to set up a checkout. [AGENTS.md](AGENTS.md) covers how a command here behaves, how the shell is written, and what belongs in a comment. `tools/check` is the gate, and this repository's own `githooks/commit-msg` runs `tools/lint-commit-prose`.

## License

MIT. [LICENSE](LICENSE) also has the notice for the View derived from [Commits](https://github.com/jdkato/commits). It has the notices for the rules derived from [vale-ai-tells](https://github.com/krishnasunkam/vale-ai-tells), [Std](https://github.com/vale-cli/Std), [proselint](https://github.com/vale-cli/proselint), and the [Vale Harper style](https://github.com/vale-cli/Harper).
