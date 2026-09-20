# Process: a code change

A bugfix, a feature, a migration or a refactor of code this session owns. The result sits on
ladder level a, so it has an oracle almost always: the checks are written before the code and the
run of those checks is the verdict. Read `core.md` and `SKILL.md` first.

## Stages and gates

| stage | task file | gate | lite | std | full |
|---|---|---|---|---|---|
| `intent` — the problem, the wanted behaviour, the quality criteria | `intent.md` | the user confirms the text and the criteria | written by the main session, no gate | user gate | user gate |
| `subtasks` — the change cut into parts that can land alone | `subtasks.md` | every part of the goal has a subtask, no subtask outside the goal | folded into `intent.md` | yes | yes |
| `specification` — behaviour, invariants, compatibility constraints | `specification.md` | traceability to the subtasks, every non-functional requirement measurable | folded into `intent.md` | yes | yes |
| `scenarios` — what a working change must do, negatives included | `scenarios.md` | every requirement and invariant has a scenario | one-liners | yes | yes, with negatives |
| `verification-plan` — the oracle of every invariant | `verification-plan.md` | every invariant has an oracle row: `existing`, `missing` or `no possible` | folded into `intent.md` | yes | yes |
| `checks` — the tests, written before the code | `tests.md` | every scenario has a test, no test stands without a scenario, no id in a name | – | yes | yes, plus the negative control on the version before the change |
| `result` — the code, then the run of the checks | `changes`, `runs` | the checks run and report PASS; no review of code the checks cover | yes | yes | yes |
| `review` — only the parts no check can judge | `reviews` | evidence chain over the approved aspects; what stays undetermined goes to the user | 1 merged critic | 2-3 aspects | 3-5 aspects |
| `coverage` — scenarios without tests, tests without scenarios | `coverage.md` | both lists written out, empty ones said so | – | yes | yes |
| `closure` — what changed, how it was proven, what stays open | `report.md` | gaps, hit ceilings and unverified areas named | short in chat | yes | yes |

## What this process insists on

- The checks come before the code, and at `full` they must fail on the version before the change
  before they are accepted: a test that passes without the change proves nothing.
- Code with a passing check gets no review. A part with no possible check (a shape only a reader
  can judge) is written one class step up instead, and only that part goes to the review stage.
- One subtask, one result launch, one check run. Parts that touch disjoint files run in parallel;
  anything else runs in order.
- A failing check is fixed within the depth's cycle ceiling. At the ceiling the stage ends, the
  gap goes into the task files and into the report, and the loop guard of `core.md` applies.
- A long check run never sits inside a short-lived carrier: it is started detached and its result
  path is handed to the next stage.
- Commit and push only on the user's word, and never as part of a stage.
