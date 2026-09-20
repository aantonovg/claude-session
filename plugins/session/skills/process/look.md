# Process: an investigation

A question about a system: why does this happen, where does this number come from, what would
break if we changed that. The result is an answer with pointers, and its oracle is the fact it
rests on. Read `core.md` and `SKILL.md` first.

## Stages and gates

| stage | task file | gate | lite | std | full |
|---|---|---|---|---|---|
| `intent` — the question, and what a good answer must settle | `intent.md` | the user confirms the question and the criteria of a good answer | written by the main session, no gate | user gate | user gate |
| `subtasks` — the question cut into directions that can run in parallel | `subtasks.md` | every part of the question has a direction, none outside it | folded into `intent.md` | yes | yes |
| `specification` — the unknowns, each with its class: decision-changing, verification-changing, local, nice-to-know | `specification.md` | every unknown carries a class; contradictions are named | folded into `intent.md` | yes | yes |
| `scenarios` — what evidence would settle each unknown | `scenarios.md` | every decision-changing unknown has one | one-liners | yes | yes, with the refuting evidence named too |
| `verification-plan` — where that evidence can come from | `verification-plan.md` | every unknown has a source row, `existing`, `missing` or `no possible` | folded into `intent.md` | yes | yes |
| `checks` — the reads, the queries and the runs that produce facts | `tests.md` | every planned source was reached or reported unavailable | – | yes | yes, plus one run that would refute the leading answer |
| `result` — the evidence bundles the answer will rest on | `evidence` | every fact carries a pointer; an unsettled unknown is written as one, never as an answer | yes | yes | yes |
| `review` — the answer itself, which no run can judge | `reviews` | evidence chain over the approved aspects; what stays undetermined goes to the user | 1 merged critic | 2-3 aspects | 3-5 aspects |
| `coverage` — unknowns without evidence, evidence without an unknown | `coverage.md` | both lists written out, empty ones said so | – | yes | yes |
| `closure` — the answer the bundles add up to, its confidence and what stays open | `report.md` | every claim of the answer carries a pointer, a claim with none is marked open; open unknowns, hit ceilings and unverified areas named | short in chat | yes | yes |

## What this process insists on

- Breadth first and cheap: directions run in parallel, each with its input paths named, each
  writing one bundle of pointers. Judgment comes after the breadth, once, and reads the bundles.
- Two rounds of research at most. A round that produced no new fact ends the stage.
- A fact is a pointer: a file and a line, a command and its output, a page and its date. A
  sentence with no pointer is an assumption and is written as one.
- A contradiction between two sources is closed by a third fact or accepted as a risk in the
  report; it is never resolved by choosing the more pleasant source.
- The answer is one short document. What was read but did not matter stays out of it, in the
  evidence files.
- An investigation ends at the answer. A change that follows it is a new task with its own intent.
