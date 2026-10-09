---
name: settle-prose-alert
description: Decide what a prose alert is worth before acting on it. Invoke when the prose hook returns alerts, when a branch sweep returns a list, or when one rule keeps firing.
---

# Settle a prose alert

An alert says a line matched a pattern. It doesn't say the line is wrong.

Break this default: an agent reads an alert as an instruction and rewrites the line. That's how a
hedge gets cut when the hedge was the claim, and how a rule nobody ever questioned stays on for a
year.

Every alert ends in one of three places. The line changes, the alert stands and you say why, or the
rule changes. Step 2 picks which.

## Steps

**1. Read the line, not the alert.** Open the file and read the whole sentence, and the one before
it. A rule matches a span. You're deciding about a claim, and a claim is usually wider than the
match.

**2. Ask one question: is the line worse for the flagged words?** Not "could this be shorter", and
not "is the rule's advice sound in general". Delete the flagged words in your head and read it back.
Where the line still says the same thing, the words were padding and the alert is right. Where the
meaning moved, the words were doing work and the alert is wrong.

This question settles the two cases that look alike. A rule flags "usually" in "a hedge is usually
the point" as a filler adverb. Without it the line claims more than the writer meant, so it stays.
The same rule flags "just" in "just check the output", which says nothing, so it goes.

**3. Where you change the line, check the meaning survived.** Read the old and the new side by
side and say what each asserts. Revert where the new one asserts something the old one didn't, or
drops a condition the old one had. A fix that costs meaning is worse than the alert.

**4. Where you leave the line, give the evidence.** Quote the words that carry your reason, or name
the file or command you read. "This is intentional" isn't a reason, and neither is a restatement of
the rule's message. The next person has only your sentence.

**5. Read the whole text back.** Every rule here grades one span, so a file can clear every alert
and still be incoherent. Read it as though someone else wrote it and ask what's wrong with it. A
clean run says nothing about whether the text is any good.

**Done when:** every alert in the batch has a line change or a stated reason. You've also read the
text back once, with nothing outstanding.

## When the rule is the problem

An alert you keep overruling is a signal about the configuration, not about the line in front of
you. Three things to establish before touching it.

**Count first.** A rule that annoyed you once is one line you disagreed with. Run the sweep over a
real body of text, count what the rule reports, and count what it reports that no other rule does.
A rule whose alerts another rule already covers is the one to switch off.

**Probe the other packages before you widen or copy a rule.** The near-miss rule usually exists,
and its author narrowed it on purpose. `Slop.Tricolon` excludes plain three-item lists in its own
comment, so a rule for abstract-noun triads is an addition rather than a fix. `Slop.Anthropomorphism`
targets intent verbs and reaches no inanimate subject taking an active verb. Read the rule's own
comment and run it against the text you want caught. Where upstream covers it, use upstream.

Where you do copy a rule to widen it, switch the original off in the same change. Two rules reporting
one span is the defect this configuration exists to avoid.

**An alert with no span is a configuration defect.** A readability score grades a whole document
and points at no words. A rewrite has nothing to answer. Fix it with a gate on the rule or a
`NO` in the config, and never with a sentence telling the reader to ignore it. The same is true of
a rule whose only fix the file can't take, such as one asking for a character the text excludes.

## Settling a flagged word

Spelling is a different decision and this skill doesn't cover it. A flagged word falls into four
cases: a misspelling, a name this codebase chose, a name from outside it, or one not worth acting
on. The surface the word sits on decides more often than the word does. Where the repository has a
skill for that, use it.
