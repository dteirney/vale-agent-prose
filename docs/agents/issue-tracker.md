# Issue tracker: local markdown

Issues and specs for this repository live as markdown files in `.scratch/`, which git ignores.

## Conventions

- Each feature has its own directory, `.scratch/<feature-slug>/`.
- The spec is `.scratch/<feature-slug>/spec.md`.
- Each implementation issue is its own file, `.scratch/<feature-slug>/issues/<NN>-<slug>.md`,
  numbered from `01`. Never combine the tickets into one file.
- A `Status:` line near the top of each issue file records its triage state. The role strings
  are in `triage-labels.md`.
- Comments and conversation history go at the end of the file, under a `## Comments` heading.

## When a skill says "publish to the issue tracker"

Create a new file under `.scratch/<feature-slug>/`, and create the directory if it's missing.

## When a skill says "fetch the relevant ticket"

Read the file at the path the skill names. The user normally passes the path or the issue number.

## Map operations

`/wayfinder` uses these. The map is one file, with one child file per ticket.

- **Map:** `.scratch/<effort>/map.md`, with the Notes, Decisions-so-far and Fog sections.
- **Child ticket:** `.scratch/<effort>/issues/NN-<slug>.md`, numbered from `01`, with the
  question in the body. A `Type:` line records the ticket type: `research`, `prototype`,
  `grilling` or `task`. A `Status:` line records `claimed` or `resolved`.
- **Blocking:** a `Blocked by: NN, NN` line near the top. A ticket has no blocker left once every
  file it lists is `resolved`.
- **Frontier:** the files in `.scratch/<effort>/issues/` that are open, unblocked, and unclaimed.
  The lowest number goes first.
- **Claim:** set `Status: claimed` and save the file before any other work.
- **Resolve:** write the answer under an `## Answer` heading and set `Status: resolved`. Then add
  a context pointer, a one-line summary and a link, to the Decisions-so-far section of `map.md`.
