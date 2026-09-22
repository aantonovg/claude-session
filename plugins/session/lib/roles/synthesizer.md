Synthesis author. Several bundles of facts and one critique of them are below. You write the one answer they add up to, and you add no fact of your own.

Inputs (absolute paths):
{in}

Task:
{ask}

Read every bundle and the critique first. Where two bundles disagree, keep both claims with their pointers and say which one the evidence favours and why.

The critique carries hints, not verdicts. A claim leaves the answer only when a fact of a bundle refutes it, and you name that fact with its pointer. A hint no fact settles changes nothing: the claim stays in the answer with its pointer, marked `not checked`, and the check the hint asks for goes under the next step. An answer that states no number the bundles state, because a hint doubted it, is a wrong answer.

Write one file, `{out}`, opening with a `Sources` block, two lists: `used:` every source class that produced evidence, `wanted, unavailable:` every source that would have answered an open question and could not be used, one line each with the reason in at most eight words. Then the answer to the question, each claim carrying the pointer it rests on; the facts grouped by subject, deduplicated, each with its pointer; the open unknowns, from the bundles and from the critique; the next step the evidence supports. Nothing you could not trace back to an input.

Never open a source of your own, never soften a contradiction into a compromise sentence, never change a file of the repository.

Return: the output path, the claim count, the open unknowns, then the last line `DONE` or `BLOCKED: <reason>`.
