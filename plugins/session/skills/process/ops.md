# Process: an infrastructure change

A change of a running system, local or remote: a config, a deployment, a cluster object, a
pipeline, a certificate, a DNS record. The result sits on ladder level b. Its oracle is the state
after the change, and the accepted form of "tests" here is a file of control calls. Read `core.md`
and `SKILL.md` first.

## Stages and gates

| stage | task file | gate | lite | std | full |
|---|---|---|---|---|---|
| `research` — facts, unknowns, contradictions, assumptions, verification capabilities | `ledger.md`, `evidence` | no decision-changing unknown open, contradictions closed or accepted as risk, verification capabilities listed or unverifiable written | one research bundle, no gate | yes | yes |
| `intent` — what must be true after the change, and what must not change | `intent.md` | the user confirms the wanted state, the blast radius and the criteria | written by the main session, no gate | user gate | user gate |
| `subtasks` — the change cut into steps that can be applied and rolled back alone | `subtasks.md` | every part of the goal has a step, each with its rollback | folded into `intent.md` | yes | yes |
| `specification` — the wanted state, the invariants that must hold during the change, the constraints (window, access, quota) | `specification.md` | traceability to the steps, every invariant measurable as a number or a line of output | folded into `intent.md` | yes | yes |
| `scenarios` — what a correct state looks like, and what a broken one looks like | `scenarios.md` | every invariant has a scenario; the failure cases are among them | one-liners | yes | yes, with negatives |
| `verification-plan` — the oracle of every invariant, and the rollback trigger | `verification-plan.md` | every invariant has a row: `existing`, `missing` or `no possible` oracle | folded into `intent.md` | yes | yes |
| `implementation-plan` — the plan of the work | `implementation-plan.md` | the steps and their order are named and checked against the verification plan; starts only after the verification-plan gate passed | folded into `intent.md` | yes | yes |
| `checks` — the control-call file: one line per call, each with its expected result | `tests.md` | every invariant has a call with an expected result written down before the change | – | yes | yes, plus a call that must fail while the change is absent |
| `result` — the change applied, with the control calls run before it and after it | `changes`, `runs` | the two runs are recorded and every call matches its expected result; a mismatch triggers the rollback | yes | yes | yes |
| `review` — the parts no call can reach | `reviews` | evidence chain over the approved aspects; what stays undetermined goes to the user | 1 merged critic | 2-3 aspects | 3-5 aspects |
| `coverage` — invariants without a call, calls without an invariant | `coverage.md` | both lists written out, empty ones said so | – | yes | yes |
| `closure` — what changed, the two runs, what stays unverified | `report.md` | gaps, hit ceilings and unverified areas named, rollback still available or said to be gone | short in chat | yes | yes |

## The control-call file

The `checks` stage of this process writes one file, and it is the oracle of the whole change:

- One line per call: the command to run and the expected result beside it — a request and the
  answer it must give, a metric and the band it must stay in, a log line that must appear or must
  never appear, a count that must not drop.
- It is written **before the change**, never after: a call whose expected result was not written
  down beforehand proves nothing, because the state is then read to fit what happened.
- It is run **before the change** to record the state the work starts from, and run again after
  the change. The pair of runs is the verdict, and both raw outputs stay in `runs`.
- A call that needs a credential names the variable it reads, never the value; no value of a
  secret is printed, written into a file of the task or passed on.
- An invariant whose control calls cannot be written is a weak-oracle area: it is named in the
  verification plan with the reason, given the strongest substitute available, listed in the
  report as unverified and accepted by the user.

## What this process insists on

- Nothing is applied before the "before" run exists and the rollback of that step is written.
- One step at a time on a live system; the control calls run between the steps, not only at the
  end.
- A change that cannot be rolled back is a decision for the user, taken before the work starts and
  recorded with the intent.
- A mismatch after the change is a stop: roll back the step, write the failure packet into the
  ledger, and go back to the specification, not to a second attempt at the same command.
- What was done by hand outside the control-call file does not exist for the report: every manual
  step is written into the file first.
