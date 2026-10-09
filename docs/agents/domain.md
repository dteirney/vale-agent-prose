# Domain docs

How the engineering skills read this repository's domain documentation before they explore the code.

## Read these first

- **`CONTEXT.md`** at the repository root.
- **`docs/adr/`**: the decision records that touch the area you're about to work in.

If a file is missing, carry on and don't mention it. Don't suggest creating these files ahead of time. The `/domain-modeling` skill creates them when a term or a decision gets settled.

## Layout

This repository has one context:

```text
/
├── CONTEXT.md
└── docs/adr/
    └── 0001-<decision>.md
```

## Use the glossary's terms

When your output names a domain concept, use the term `CONTEXT.md` defines for it. That covers an issue title, a refactor proposal, a hypothesis, and a test name. Leave out the words the glossary lists under _Avoid_.

A concept missing from the glossary means one of two things. You're inventing language the project doesn't use, so reconsider. Or the glossary has a real gap, so note it for `/domain-modeling`.

## Flag a conflict with a decision record

If your output contradicts a decision record, say so rather than overriding it without a word:

> _Contradicts decision record 0007 on event-sourced orders. Worth reopening, because the order volume it assumed has doubled._
