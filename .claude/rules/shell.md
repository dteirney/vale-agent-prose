---
paths:
  - "tools/**"
  - "lib/**"
  - "scripts/**"
  - "githooks/**"
---

# How the shell here is written

The configuration decides it, and the gate enforces it: `.shellcheckrc` for shellcheck, `.editorconfig` for shfmt. Read those two files rather than any description of them.

One naming rule breaks the style guide on purpose. A command takes hyphens, `lint-branch-prose` and not `lint_branch_prose`, because that's what a person typing it expects.
