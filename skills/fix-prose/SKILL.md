---
name: fix-prose
description: Fix the prose in the files and directories you name, with one subagent per file.
disable-model-invocation: true
---

# Fix the prose in the named paths

You hand out files and report. Each subagent fixes one file. Your context window has file paths, alert counts, and the lines the subagents left. The alert lines, the edits, and the file contents stay in the subagents' context windows.

## 1. List the files

Where the user named no paths, ask which paths to fix. Run the lint over the paths the user named:

```sh
"${CLAUDE_PLUGIN_ROOT}/tools/lint-prose" --data-dir "${CLAUDE_PLUGIN_DATA}" --by-file <paths>
```

Each stdout line is `<count> <path>`, highest count first. Read only that list, and show the user anything on stderr. Then branch on the exit code:

- **0:** the paths have no alerts. Tell the user and stop. A stderr warning that the configuration names no styles means few rules ran, if any. Say the result isn't evidence the prose is clean.
- **1 with no lines:** the lint found only unknown words, which this skill leaves alone. Tell the user and stop.
- **1 with lines:** go to step 2.
- **Anything else:** show the user the stderr and the exit code, and stop.

## 2. Hand out the files in waves of 8

Take the list from the top, 8 files at a time. For each file in a wave, start a general-purpose subagent with the brief below, its `<path>` filled in. Start the wave's subagents in one message, and wait for every report before you start the next wave. Between waves, tell the user in one line how many files have a report and how many are left.

Each file goes to one subagent, once. Keep each report as it came, and leave the file unopened.

## 3. Rerun and report

After the last wave, rerun the command from step 1 with the same paths. The rerun only reports: it starts no subagent.

Report to the user:

- the rerun's list, with each file's count
- each line a subagent left, grouped by file, with its rule and its reason as the subagent wrote them
- each file whose subagent sent no report

Leave the rewrites uncommitted, for the user to review.

**Done when:** every file in the step 1 list had one subagent, the rerun ran, and the user has the report. You've committed nothing.

## The subagent brief

Fill in `<path>`, and write the lint command with the plugin's paths spelled out.

```text
Fix the prose in one file: <path>.

Lint it:

    "${CLAUDE_PLUGIN_ROOT}/tools/lint-prose" --data-dir "${CLAUDE_PLUGIN_DATA}" --limit 0 <path>

Each alert is one line, `file:line:column: message [rule]`. Some name the flagged words before the rule, and some end with a link. A `note:` line under an alert offers a replacement. An alert says a line matched a pattern. It doesn't say the line is wrong.

For each alert:

1. Read the line, and the one before it. The rule matched a span, and the claim is usually wider than the span.
2. Ask whether the line has the defect the alert names, with the defect test in "${CLAUDE_PLUGIN_ROOT}/skills/defect-test.md". Where it has, fix the line. Where it hasn't, leave the line.
3. Where you fix the line, compare the old and the new line and say what each asserts. Revert where the new one asserts something the old one didn't, or drops a condition the old one had.
4. Where you leave the line, quote the words that carry your reason, or name the file or command you checked. A restatement of the rule's message isn't a reason.

A line ending `[cspell]` is an unknown word, not an alert. Leave it as it stands. Spelling is out of scope, and a rewrite to get past it renames something.

After each edit, the prose hook lints the paragraph you changed and hands back any alert still in it. That feedback is your second lint: act on it, and run the lint command once only.

When every alert has a fix or a reason, read the whole file back as one text, as though someone else wrote it. A file can clear every alert and still read badly. Fix what you find.

Report only the alerts you left, one per line:

    <path>:<line>:<column>: <reason> [<rule>]

Where you left none, report `none left`. Send nothing else: no list of fixes and no diff.
```
