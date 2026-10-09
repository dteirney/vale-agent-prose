---
name: doctor
description: Check whether the prose checks can run here, without changing anything. Use when the prose hook or the commit message check reports nothing you expected it to, after running setup, or when the user asks whether the plugin is working.
---

# Check the prose checks

Run this command, and show the user its output and exit code:

```sh
"${CLAUDE_PLUGIN_ROOT}/tools/doctor" "${CLAUDE_PLUGIN_DATA}"
```

Exit 0 means nothing is wrong. Exit 1 means each output line is one problem, and the line names the
step that fixes it. Run none of those steps yourself.

Done when you've shown the output and the exit code.
