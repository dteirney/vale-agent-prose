# AgentProse

A Vale package and a Claude Code plugin that lint the prose an agent writes. This glossary covers how a review judges an alert after the agent has seen it.

## Language

**Alert**: one rule's report on a line the agent wrote, as Vale raises it and the prose hook hands it back. _Avoid_: finding, warning, issue

**Recheck**: the Vale run at the next edit of an alert's file, which finds the alert persisted or absent. An alert has at most one. _Avoid_: outcome, result, status, state

**Persisted alert**: an alert Vale raises again at the next edit of its file: the same rule, message, and flagged words. A metric alert flags no words, so the same rule is enough, whatever its score. It says nothing about whether the agent chose to keep it. _Avoid_: surviving alert, dismissed alert, kept alert

**Absent alert**: an alert Vale no longer raises at the next edit of its file, whatever that edit was for. _Avoid_: cleared alert, fixed alert, dropped alert

**Unchecked alert**: an alert with no recheck: the agent doesn't edit its file again in the same session. _Avoid_: open alert, pending alert

**Persistence rate**: a rule's persisted alerts as a share of its persisted and absent alerts together. _Avoid_: survival rate, dismissal rate

**False positive**: a verdict the review gives a persisted alert: the rule was wrong for that line. A persisted alert where the rule was right isn't one. _Avoid_: bad alert, noise

**Package-wide false positive**: a false positive the shipped package would raise in any repository, fixed once in the package. _Avoid_: package defect, upstream bug

**Repository-only false positive**: a false positive that only one repository's prose produces, fixed in that repository's own Vale configuration. _Avoid_: repository defect, repository exception, local override
