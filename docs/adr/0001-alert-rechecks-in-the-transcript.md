# Alert rechecks live in the session transcript

The prose hook writes each alert's recheck, persisted or absent, to its stderr as a JSON line. The review reads those lines back from the session transcripts. The plugin keeps no log of its own, only each session's last alerts per file, which it deletes at session end.

The hooks guide says Claude Code writes stderr from a hook that exits 0 to the debug log only. It also says the model never receives it. The transcript file still records it, in the `stderr` field of a `hook_success` attachment, and this design depends on that. The model never receives the recheck lines, so they add nothing to the turn.

## Considered options

- **A log in the plugin's data directory.** The plugin would own the format, but it's a second record of what the transcript already has.
- **Parsing the hook's own stdout from the transcript.** The hook filters alerts to the lines an edit touched, so a persisted alert on an untouched line never reappears there.

## Consequences

The sessions guide calls the transcript format internal, and says it can change on any release. A release that stops recording stderr, or renames the field, leaves the review with no records and no error. The review script has to say so when it finds no records under the current version.
