# Alert lines follow the GNU error format

Every alert the plugin prints, in the hook, the lint commands and the commit check, takes the form `file:line:column: message: 'words' [rule] (link)`. That's the compiler form in the [GNU Coding Standards' Formatting Error Messages](https://www.gnu.org/prep/standards/html_node/Errors.html). The message starts lowercase and drops its closing period, as that section asks, because the sentence starts at the beginning of the line.

The other parts come from Vale's JSON report:

- **`'words'`** is the alert's `Match`, added where the message doesn't already quote it. An agent edits by matching text, so the flagged words locate the line where a column number doesn't.
- **`[rule]`** goes last in brackets, the way ShellCheck's `gcc` format puts its code. The standard has no place for it.
- **`(link)`** is the rule's `Link`, where it has one.
- **A `note:` line** follows an alert whose rule offers a replacement, as `file:line:column: note: replace 'config' with 'configuration'`. It comes from the alert's `Action`. Clang and GCC mark a secondary line on the same location with `note:`.

The hook prints each path in absolute form, because the agent's Edit tool takes one. It leaves out an alert the agent saw at its last edit of the file and left. A count of those takes their place.

Inside, the plugin keeps Vale's line format, `file:line:column:rule:message`, with the link, the flagged words and the replacements after it, a tab before each. The touched-line filter, the matching of saved alerts, and the count per rule each parse that line. A tab keeps each alert on one line. Only a printed line changes.

## Considered options

- **Vale's line format, unchanged.** It joins the rule and the message with a colon, so a colon inside a message reads as one more field.
- **The standard's form for a program that isn't a compiler,** `program:file:line:column: message`. A linter reports positions in a source file, which is the job the compiler form serves. The hook already names the plugin above its alerts, so the name on every line repeats it.
- **The quoted source line, with a caret under the span,** as clang and the Rust compiler print it. An agent finds text by matching it, not by counting columns, and it wrote the line it's reading moments before. The flagged words do the same job in fewer characters.
- **Labelled fields,** such as `file line 41, rule: message`. No standard defines them, and the agent read Vale's colons without trouble. The rule's boundary was the problem, and the brackets fix that.

## Consequences

- A capital followed by a lowercase letter becomes lowercase, so a message that opens with a proper noun loses its capital. `AgentProse.FleschReadingEase` opens with `Reading ease` for that reason. A capital followed by a capital starts an acronym and keeps its case.
- A long sentence's alert flags its first word, so its line reads `long sentence: 27 words: 'Print'`, which locates where the sentence starts.
- The standard counts a tab as a stop every 8 columns. Vale and cspell report their own column, and nobody has checked either against that rule.
- The output of `tools/lint-prose` no longer matches `vale --output=line` on the same file.
