# vale-agent-prose

Prose linting for the text an agent writes: markdown, the comments in a source
file, and a commit message.

It ships two things. A Claude Code plugin that lints every file the agent
writes and hands the alerts back to it. A [Vale](https://vale.sh) package
that the plugin runs. It combines the published style packages and switches off
the rules that only add noise.

## The Claude Code plugin

```
/plugin marketplace add dteirney/vale-agent-prose
/plugin install vale-agent-prose@vale-agent-prose
```

To run it from a checkout instead, add the checkout's path as the marketplace:
`/plugin marketplace add /path/to/vale-agent-prose`. Claude Code then loads the
plugin from that directory, and an edit there takes effect at the next session
or `/reload-plugins`.

A `PostToolUse` hook on `Write` and `Edit` lints the file the agent wrote and
returns the alerts as context. In a file git tracks, it reports every alert
in each paragraph or comment the edit touched. A sentence the edit made too long
reports even where it starts on an older line. An old comment the edit didn't
touch stays out.

The hook needs `vale` and `jq` on the PATH. It uses `cspell` when it's there.
Missing one, it exits 0 and says nothing: a hook that can't read its input must
never interrupt the turn.

The hook keeps the alerts it hands back in the plugin's data directory, with
one folder per session. At the file's next edit it rechecks them. A
`SessionEnd` hook deletes the folder when the session ends. A crash skips that
hook, so a `SessionStart` hook deletes any folder whose Claude Code process has
exited.

Run the setup skill once after you install the plugin, and again in each
repository with its own Vale configuration:

```
/vale-agent-prose:setup
```

It runs `tools/setup install`, which does three things:

- adds a `commit-msg` hook to your global git config
- syncs the default Vale configuration into the plugin's data directory
- syncs the styles that the current repository's own Vale configuration lists

A commit message gets checked by git itself, before the commit lands. From then on, every `git commit` in every repository runs the check, whether
the agent commits or you do. An alert stops the commit and prints why. The
repository's own `commit-msg` hook still runs. This needs git 2.54.0 or later,
the first release that runs a hook named in git's configuration.

The hook runs a copy of the check that the plugin keeps in its data directory,
so an update doesn't move it. After an uninstall the copy is gone, and the hook
lets every commit through. Ask the setup skill to remove the check to take the
entry out of your git config.

A repository's own Vale configuration decides the rules. A repository with none
gets the package below, from the default configuration in the plugin's data
directory. Both hooks use it. After a plugin update, a `SessionStart` hook syncs
it again, which needs the network and takes a few seconds.

Another `SessionStart` hook warns you once per session when the prose hook
would miss alerts. The causes are a missing tool, styles nobody has synced,
and a Vale older than 3.23.0. It also warns when commit messages go unchecked.
Each warning that setup can fix names the setup skill. Without the warning, a
hook that never ran looks the same as a clean file.

To run the same check at any time, without changing anything:

```
/vale-agent-prose:doctor
```

cspell finds a repository's own configuration as usual. The hook also adds
`~/.claude/cspell.json` when that file exists, or the same file under
`$CLAUDE_CONFIG_DIR`. A word list you keep there applies in every repository.

`skills/settle-prose-alert` is the companion skill. An alert says a line
matched a pattern, not that the line is wrong, and the skill is how to tell
which.

## The Vale package

Add it to your `.vale.ini` and sync:

```ini
StylesPath = styles
Packages = https://github.com/dteirney/vale-agent-prose/releases/latest/download/AgentProse.zip
```

```sh
vale sync
```

`latest` takes each release as it ships. To stay on one, name its tag instead:
`releases/download/v0.1.0/AgentProse.zip`.

It needs Vale 3.23.0 or later. An older Vale reports some alerts on the wrong
line.

`StylesPath` and `Vocab` stay yours. The package sets neither, because a
`StylesPath` is a path in your repository and a vocabulary is your own list of
words.

### Set a Vocab if acronyms flag

A vocabulary entry reaches every style's `exceptions` list, not only spelling.
Adding `GDAL` to `styles/config/vocabularies/Base/accept.txt` silences
`Google.Acronyms` and `Std.Abbreviations.Acronyms` on it, which is the one job
this file still has. Spelling belongs to cspell, which knows the technical
words a hand-written list would carry.

An entry is safe as a lowercase word only because `Vale.Terms` is off here.
`HEAD`, `PUT` and `PATCH` each carry that collision.

### What AgentProse adds

Rules the published packages miss:

| Rule | Catches |
| --- | --- |
| `AbstractTriad` | Three abstract nouns in a row, joined by `and` or `or` |
| `InanimateVerb` | A subject that can't act taking an active verb |
| `NegDeduction` | A negation in two `no` phrases joined by `so` |
| `SourcePath` | A source file named in a comment, which a rename breaks |
| `FleschReadingEase` | A reading-ease score, gated so short text doesn't report |

### Comments in a source file

Vale reads comments through a tree-sitter grammar and has none for shell. The
package ships two TextFSM views instead, which need no grammar: `Shell` for
anything commenting with `#`, and `JavaScript` for anything commenting with
`//`. Between them the config covers the common source extensions, plus the
commands with no extension in `bin/`, `tools/` and `githooks/`.

### A commit message

Give Vale the message under the name `COMMIT_EDITMSG` and it lints the subject
and the body. Git's comment lines, the diff under a verbose commit's scissors
line, a type prefix, a ticket key, and the trailers stay out. A `commit-msg`
hook gets the message file as `$1`:

```sh
#!/bin/sh
exec vale --path=COMMIT_EDITMSG < "$1"
```

Put it in the directory `git config core.hooksPath` names, or run the same
line from husky, lefthook or pre-commit. In CI, lint the message of the commit
a job runs on:

```sh
git log -1 --format=%B | vale --path=COMMIT_EDITMSG
```

Vale exits 0 when every alert is a warning or a suggestion, so the hook
prints the alerts and the commit goes ahead.

The section names its own View, `CommitMessage`. Add the
[Commits](https://github.com/jdkato/commits) package beside this one and its
View replaces this one, even from your own `.vale.ini`. That View lints the
trailers and the type prefix.

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
| `tools/check` | The repository's own gate |

Each exits 0 when clean, 1 on a finding, and 2 on a usage error. Run any of
them with `--help`. `tools/review-alerts` exits 1 when the transcripts hold no
rechecks, and names the folder it searched.

`tools/lint-commit-prose` adds cspell to the Vale run above, and exits 1 on an
alert of any level. This repository's own `githooks/commit-msg` runs it.

## Reporting to a pull request

`vale --output=rdjsonl.tmpl` renders alerts as rdjsonl, with the severity and
the rule's doc link that an errorformat parse drops. `vale sync` installs the
template, and the name needs its extension:

```sh
vale --output=rdjsonl.tmpl . | reviewdog -f=rdjsonl -reporter=github-pr-review
```

The commands above don't use it, because reviewdog's local reporter prints
rdjsonl back unchanged.

## Related

[vale-cli/agent-tools](https://github.com/vale-cli/agent-tools) is Vale's own
Claude Code plugin.

## Contributing

Read [AGENTS.md](AGENTS.md). It covers the gate, how a command here behaves,
how the shell is written, and what belongs in a comment.

## License

MIT. [LICENSE](LICENSE) also has the notices for the rule derived from
[vale-ai-tells](https://github.com/krishnasunkam/vale-ai-tells) and the View
derived from [Commits](https://github.com/jdkato/commits).
