---
name: setup
description: Set up the prose checks, or remove the commit-message check.
disable-model-invocation: true
---

# Set up the prose checks

Run this command, and show the user its output and exit code:

```sh
"${CLAUDE_PLUGIN_ROOT}/tools/setup" install "${CLAUDE_PLUGIN_DATA}"
```

When the user asked to remove the commit-message check, run this one instead:

```sh
"${CLAUDE_PLUGIN_ROOT}/tools/setup" remove
```

Done when you've shown the output. On a non-zero exit, show the error lines as the command printed
them.
