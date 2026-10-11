---
name: review-alerts
description: Judge the prose hook's persisted alerts, and draft a fix for each false positive.
disable-model-invocation: true
---

# Review the persisted alerts

A persisted alert says Vale raised it again at the next edit of its file. It doesn't say whether the rule was wrong for the line. This review decides that for each persisted alert, and drafts the fix for each false positive. The user acts on every draft. The review files no issue and edits no repository.

## 1. Run the review command

```sh
"${CLAUDE_PLUGIN_ROOT}/tools/review-alerts"
```

Show the user its output and its exit code. Then branch:

- **Not 0:** the command failed, perhaps after printing some rules. Show the error lines as printed, and stop. Judge none of the rules it printed.
- **0 with ranked rules:** go to step 2.
- **0, and the output says the transcripts hold no rechecks:** report that, with the folder the output names, and stop. Tell the user an empty search isn't evidence the rules are fine.
- **0 with no ranked rule:** the output says how many rechecks it found and the floor a rule needs. Stop there.

## 2. Judge each printed alert

Give every persisted alert in the report one verdict: **false positive** or **rule right**. Judge it with the [defect test](../defect-test.md). A line with the defect means the rule was right, and a line without it means a false positive. A metric rule flags no words, so [When the rule is the problem](when-the-rule-is-the-problem.md) covers its alerts. Where that file says to run the lint, run `"${CLAUDE_PLUGIN_ROOT}/tools/lint-prose" --data-dir "${CLAUDE_PLUGIN_DATA}"`.

Judge from the line the report prints, and the lines around it. The `>` marks the alert's line. The file may have changed since the edit, and the printed line is what Vale saw.

Give each verdict one sentence of reason, quoting the words that carry it. A restatement of the rule's message isn't a reason.

The report caps the rules it prints and the alerts under each rule, and says how many of each it left out. Judge the printed ones, and tell the user how many rules and alerts the verdicts don't cover.

## 3. Sort each false positive

A false positive is **package-wide** when another repository's prose would raise it too. It's **repository-only** when one repository's own prose produces it, such as its domain words or its house register. The evidence is the repositories the review lists under the rule. Take these in order, and stop at the first that applies:

- The rule's style appears in no `BasedOnStyles` line of `${CLAUDE_PLUGIN_ROOT}/package/.vale.ini`. The rule comes only from a repository's own configuration, so it's repository-only.
- The false positive's file is outside any repository. No repository configuration applies to it, so the package is the only place to fix it: package-wide.
- Two or more listed repositories each have a printed false positive from the rule: package-wide. An `outside any repository` row never counts as one of them.
- Only one listed repository has a printed false positive from the rule: repository-only, unless your reason from step 2 applies to any prose. Where it does, call it package-wide and say only one repository had a false positive.

Count only the repositories with a printed alert. Name any other listed repository to the user, because nobody judged its alerts.

## 4. Draft the fix

**Package-wide:** read [When the rule is the problem](when-the-rule-is-the-problem.md) first. Then draft one issue per rule for this plugin's repository, the `repository` field in `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`. Stop at the draft: the user reads it and files it.

```markdown
Title: <rule> flags <what the false positives have in common>

<rule> raised these alerts on lines where the flagged words do work:

> <example line>

<the alert's message>. <the reason from step 2>

<persisted> of <rechecks> rechecked alerts persisted, from <the listed repositories>.

Proposed change to `package/.vale.ini`:

    [<section>]
    # <why the rule is off, in one or two lines>
    <rule> = NO
```

Every switch in `package/.vale.ini` has a comment saying why, so the draft has one too. Pick the narrowest section that covers the false positives, and `[*]` when they come from more than one file type.

**Repository-only:** show the exact lines for each repository, grouped by repository. Stop at the lines: the user makes the edit.

The review lists the configuration each repository used. A repository that lists two changed its configuration during the period. Draft for the one it has now. Run `vale --no-global ls-config` from its root. Take own configuration when the command succeeds, and default configuration when it reports `no config file found`.

- **own configuration:** run `vale --no-global ls-config` from the repository root. Its `RootINI` field is the file to edit. Show these lines to add to it:

  ```ini
  [*]
  <rule> = NO
  ```

  A rule setting under `[*]` applies to every file, and the package's sections can't turn it back on.

- **default configuration:** the repository has no Vale configuration of its own, so the lines are a new `.vale.ini` at its root. It replaces the default for that repository, so it names the package. Pin the release that matches the installed plugin: `<repository>` and `<version>` are those fields in `plugin.json`.

  ```ini
  StylesPath = styles
  Packages = <repository>/releases/download/v<version>/AgentProse.zip

  [*]
  <rule> = NO
  ```

  Tell the user to run the setup skill in that repository after adding it, which syncs the styles it names.

**Done when:** every printed persisted alert has a verdict and a reason. Every false positive has a sort. Every package-wide rule has a drafted issue, and every repository-only false positive has its lines. You've filed no issue and edited no file.
