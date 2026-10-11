# When the rule is the problem

A rule with many false positives is a question about the configuration. Establish these before you draft a change to the rule.

**Count first.** One false positive is one line you disagreed with. Run `"${CLAUDE_PLUGIN_ROOT}/tools/lint-prose" --data-dir "${CLAUDE_PLUGIN_DATA}"` over a real body of text, and count what the rule reports. Then count what it reports that no other rule does. Where another rule already reports the same words, draft switching this one off.

**Check the other packages before you draft a wider rule.** A published package usually has a similar rule, and its author narrowed it on purpose. `Slop.Tricolon` excludes plain three-item lists in its own comment, so a rule for abstract-noun triads is an addition rather than a fix. `Slop.Anthropomorphism` targets intent verbs and has no pattern for an inanimate subject taking an active verb. Read the rule's own comment, and run it against the text you want caught. Where a published rule catches that text, draft a change that uses it.

A draft that copies a rule to widen it also switches the original off. Two rules reporting one span is the defect this configuration exists to avoid.

**An alert with no span is a configuration defect.** A readability score grades a whole document and points at no words. A rewrite has nothing to answer. The draft gates the rule or sets it to `NO` in the configuration. It never adds a sentence telling the reader to ignore the alert. The same is true of a rule whose only fix the file can't take, such as one asking for a character the text excludes.
