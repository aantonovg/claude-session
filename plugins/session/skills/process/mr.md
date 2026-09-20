# Process: the review of someone else's change

A merge request or a pull request written by somebody else. The question is not "is this code
pretty" but "did the author understand the task, and is the work verified". Findings come from
runs, never from reading. Read `core.md` and `SKILL.md` first.

## Stages and gates

| stage | task file | gate | lite | std | full |
|---|---|---|---|---|---|
| `intent` — what the ticket asked, what the change claims | `intent.md` | the user confirms the review depth and the criteria | written by the main session, no gate | user gate | user gate |
| `subtasks` — the claims, one per changed behaviour | `subtasks.md` | every claim of the description and the commits has a row, none invented | folded into `intent.md` | yes | yes |
| `specification` — the review contract: claim, oracle class, what proves it | `specification.md` | every claim carries `existing`, `missing` or `no possible` | folded into `intent.md` | yes | yes |
| `scenarios` — what a claim must show to count as proven | `scenarios.md` | every claim with a missing oracle has a scenario | one-liners | yes | yes, with negatives |
| `verification-plan` — the delta: only the checks the author did not run | `verification-plan.md` | no check re-plans what the author already proved | folded into `intent.md` | yes | yes |
| `checks` — the missing checks, built on a copy of the branch | `tests.md` | every planned check exists and runs; nothing is pushed to the author's branch | – | yes | yes, plus the negative control on the base branch |
| `result` — the runs and the findings they produced | `changes`, `runs` | every finding reproduces on the author's side; a failure that also shows on the base branch is dropped | yes | yes | yes |
| `review` — a claim no check can settle | `reviews` | evidence chain over the approved aspects; what stays undetermined goes to the user | 1 merged critic | 2-3 aspects | 3-5 aspects |
| `coverage` — claims without a check, checks without a claim | `coverage.md` | both lists written out, empty ones said so | – | yes | yes |
| `closure` — the threads, the summary, the verdict | `report.md` | every finding is one thread; nothing about our own process is published | short in chat | yes | yes |

## What this process insists on

- Two kinds of failure stay apart: a finding about the change, and a failure of our own side (an
  access, a missing source, a sandbox). Only the first reaches the findings; the second lives in
  `reviews/` and in the chat report.
- Before a finding is written, the same check runs on the version before the change. A failure
  that reproduces there is no finding.
- One finding is one thread: what is wrong in one line, the shortest evidence in one line, the fix
  in one line. Findings are never grouped, and a check that passed is silent.
- Nothing about how the review was done is published: no stage names, no depth, no ceilings, no
  class, no carrier names, no list of what was verified.
- The branch is read in a copy outside the user's working tree. No commit, no push, no submitted
  draft and no "request changes" before the user's word.
- Total published text stays small: one line per finding in the summary and one verdict line.
- A revisit after the author's replies is the same process at `lite`, scoped to the open threads:
  a thread whose failing check now passes is resolved, a thread still open gets one reply.
