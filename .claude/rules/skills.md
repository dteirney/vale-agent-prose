---
paths:
  - "skills/**"
---

# The skills

A command a skill runs can't read the plugin's paths from its environment. The Bash tool runs it without `CLAUDE_PLUGIN_ROOT` or `CLAUDE_PLUGIN_DATA` set. Write `${CLAUDE_PLUGIN_ROOT}` or `${CLAUDE_PLUGIN_DATA}` in the skill's text instead, and Claude Code fills in the path when it loads the skill. A command that needs the data directory takes it as an argument, as `tools/lint-prose --data-dir` does. The plugins reference says [where each variable resolves](https://code.claude.com/docs/en/plugins-reference#where-each-variable-resolves).
