# AgentProse

A Vale package and a Claude Code plugin that lint the prose an agent writes. The plugin also reviews which rules' alerts the agent leaves standing.

## Language

### What ships

**Package**: the Vale package this repository ships, with its own AgentProse rules and a configuration that switches on rules from other styles. _Avoid_: ruleset, style guide

**Plugin**: the Claude Code plugin that lints what an agent writes against the package, through its hooks, skills, and commands. _Avoid_: extension

**Prose hook**: the plugin's hook that lints each file the agent writes and hands the alerts back to the agent. _Avoid_: lint hook, edit hook

**Repository configuration**: a repository's own Vale configuration, which decides the rules for that repository. This repository's own lints only this repository and doesn't ship. _Avoid_: local configuration, project configuration

**Default configuration**: the Vale configuration the plugin uses where a repository has no repository configuration. It lists the package and nothing else. _Avoid_: fallback configuration, global configuration

**Data directory**: the folder Claude Code keeps for the plugin across updates, with the default configuration and the alerts the prose hook has handed back. _Avoid_: cache, state folder

**Unsynced package**: a package a configuration lists that Vale hasn't installed, so Vale loads the configuration and reports nothing. _Avoid_: missing styles, missing package

### Alerts

**Alert**: one Vale rule's report on a line. _Avoid_: warning, issue

**Metric rule**: a rule that scores a whole file and flags no words, such as reading ease. Its alert names the score. _Avoid_: readability check

**Unknown word**: a word cspell's dictionaries don't hold, which the lint reports beside the alerts. It isn't an alert. _Avoid_: misspelling, spelling alert, cspell alert

### Reviewing alerts

**Recheck**: Vale's second look at one alert the prose hook handed back, at the next edit of its file. It finds the alert persisted or absent. An alert has at most one. _Avoid_: outcome, result, status, state

**Persisted alert**: an alert Vale raises again at its recheck, with the same rule, message, and flagged words. An alert from a metric rule flags no words, so the same rule is enough, whatever its score. It says nothing about whether the agent chose to keep the alert. _Avoid_: surviving alert, dismissed alert, kept alert

**Absent alert**: an alert Vale no longer raises at its recheck, whatever that edit was for. _Avoid_: cleared alert, fixed alert, dropped alert

**Persistence rate**: a rule's persisted alerts as a share of its persisted and absent alerts together. _Avoid_: survival rate, dismissal rate

**False positive**: a verdict the review gives a persisted alert: the rule was wrong for that line. A persisted alert where the rule was right isn't one. _Avoid_: bad alert, noise

**Package-wide false positive**: a false positive another repository's prose would raise too, fixed once in the package. _Avoid_: package defect, upstream bug

**Repository-only false positive**: a false positive that only one repository's prose produces, fixed in its repository configuration. _Avoid_: repository defect, repository exception, local override
