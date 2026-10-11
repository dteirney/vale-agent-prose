---
paths:
  - "messages/lint-prose/context.txt"
  - "messages/lint-commit-prose/blocked.txt"
  - "skills/defect-test.md"
---

# The defect test

The prose hook's message, the commit hook's message, and the defect test each tell an agent whether to fix an alert. fix-prose and review-alerts point to the defect test. Each text asks whether the line has the defect the alert names. A change to how one judges an alert means checking the rest, because nothing else links them.
