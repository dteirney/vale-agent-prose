# The commands

The commands live in `tools/` and not `bin/`, a name Claude Code reserves. A plugin's `bin/` goes on the Bash tool's PATH, and claude.ai and Cowork refuse to install a plugin that has one. The [plugin layout](https://code.claude.com/docs/en/plugins-reference#standard-layout) says so.

## How a command here behaves

[clig.dev](https://clig.dev) decides it. Nothing checks this, so it's on you. For every command here, it means this:

- `--help` prints a usage line, the options, and what the exit codes mean.
- Exit `0` on success. A command that checks something exits `1` when the check found something, as ShellCheck does. A command that reports, such as `review-alerts`, exits `0` whatever is in the report. A failure exits with its `sysexits(3)` code, from `lib/sysexits.sh`: `64` for wrong arguments, and the rest by the man page's definitions.
- A finding goes to stdout. A diagnostic goes to stderr.
- An alert prints in the compiler form of the [GNU Coding Standards' error format](https://www.gnu.org/prep/standards/html_node/Errors.html), through `prose::gnu_alerts`. `docs/adr/0002-alert-lines-follow-the-gnu-error-format.md` says why, and what it costs.
- A long report has a limit, and says how to ask for the rest.
- A sentence a person or an agent reads goes in `messages/`, one file per message, and prints through `prose::message`. The gate lints every file there with the package. `--help` text and argument errors stay inline, because they're structured output and not prose.
