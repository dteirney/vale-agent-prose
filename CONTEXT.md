# AgentProse

A Vale package and a Claude Code plugin that lint the prose an agent writes. This glossary covers
how a review judges a finding after the agent has seen it.

## Language

**Finding**:
One alert Vale raises on a line the agent wrote, as the prose hook hands it back.
_Avoid_: Alert, warning, issue

**Dismissed finding**:
A finding Vale still reports, the same rule on the same line text, at the agent's next edit of the
same file.
_Avoid_: Ignored finding, rejected finding

**Fixed finding**:
A finding Vale no longer reports at the agent's next edit of the same file.
_Avoid_: Resolved finding, addressed finding

**Open finding**:
A finding with no later edit of its file in the same session, so it's neither dismissed nor fixed.
_Avoid_: Pending finding, unknown finding

**False positive**:
A verdict on a dismissed finding: the rule was wrong for that line, judged from the agent's stated
reason. A dismissed finding where the rule was right isn't one.
_Avoid_: Bad finding, noise

**Package defect**:
A false positive the shipped package causes everywhere, fixed once in the package.
_Avoid_: Upstream bug

**Repository defect**:
A false positive only one repository's prose causes, fixed in that repository's own Vale
configuration.
_Avoid_: Local override
