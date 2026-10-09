# AgentProse

A Vale package and a Claude Code plugin that lint the prose an agent writes. This glossary covers
how a review judges an alert after the agent has seen it.

## Language

**Alert**:
One rule's report on a line the agent wrote, as Vale raises it and the prose hook hands it back.
_Avoid_: Finding, warning, issue

**Recheck**:
The Vale run at the next edit of an alert's file, which finds the alert persisted or absent. An
alert has at most one.
_Avoid_: Outcome, result, status, state

**Persisted alert**:
An alert Vale raises again at the next edit of its file: the same rule, message, and flagged words.
It says nothing about whether the agent chose to keep it.
_Avoid_: Surviving alert, dismissed alert, kept alert

**Absent alert**:
An alert Vale no longer raises at the next edit of its file, whatever that edit was for.
_Avoid_: Cleared alert, fixed alert, dropped alert

**Unchecked alert**:
An alert with no recheck: the agent doesn't edit its file again in the same session.
_Avoid_: Open alert, pending alert

**Persistence rate**:
A rule's persisted alerts as a share of its persisted and absent alerts together.
_Avoid_: Survival rate, dismissal rate

**False positive**:
A verdict the review gives a persisted alert: the rule was wrong for that line. A persisted alert
where the rule was right isn't one.
_Avoid_: Bad alert, noise

**Package-wide false positive**:
A false positive the shipped package would raise in any repository, fixed once in the package.
_Avoid_: Package defect, upstream bug

**Repository-only false positive**:
A false positive that only one repository's prose produces, fixed in that repository's own Vale
configuration.
_Avoid_: Repository defect, repository exception, local override
