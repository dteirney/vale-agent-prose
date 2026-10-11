# The defect test

An alert says a line matched a pattern. It doesn't say the line is wrong. This test asks whether the line has the defect the alert names.

Read the line, and the one before it. The rule matched a span, and the claim is often wider than the span. Where the line has the defect, the rule was right about it. A fix removes the defect, and the line still says the same thing. A synonym the rule doesn't list keeps the defect, so swapping one in isn't a fix. Where the line doesn't have the defect, the rule was wrong about it, as when a pattern matches a code name.

An alert on filler words has a quick form of the test. Delete the flagged words in your head and read the line back. Where it still says the same thing, the words were padding, and the line has the defect. Where the meaning moved, the words were doing work, and it doesn't. A rule flags "usually" in "a hedge is usually the point" as a filler adverb. Without it the line claims more than the writer meant, so the word does work. The same rule flags "just" in "just check the output", which says nothing, so it's padding.

An alert from a metric rule scores the whole file and names no defect in a line, so the test can't judge it.
