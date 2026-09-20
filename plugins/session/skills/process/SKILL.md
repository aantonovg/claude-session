---
name: process
description: The task process: stages, gates, task files and user points for a task of any type the list under "Start" names; invoke at session start with a task type and a depth.
disable-model-invocation: true
---

# Task process

The session base applies underneath; this page adds the order of the work. It fixes the stages,
the file each stage writes, the gate each stage passes and the three points where the user is
needed. It fixes no carrier: which carrier does a stage is read from the usage contracts the
session was given at its start and again after a compact. A newly enabled plugin widens what a
stage can do, with no edit of this page.

## Start (do this now)

0. Read `core.md` next to this file first: task directory, ledger, cost rules, harness gate,
   `Sources` and `Oracles` blocks, the ladder, the artifact chain, how a review is read as an
   evidence chain, the status shape, the loop guard. Its rules are part of this process.
1. Arguments, any order, each at most once: a task type and a depth `lite`, `std` or `full`. The
   depth picks the column of every table. The task types are this one list, each with the process
   file it picks, read next to this one; nothing else in this skill enumerates them:

   | task type | process file | the work |
   |---|---|---|
   | `code` | `code.md` | a code change |
   | `mr` | `mr.md` | an MR review |
   | `look` | `look.md` | an investigation |
   | `doc` | `doc.md` | a document |
   | `ops` | `ops.md` | an infrastructure change |
2. Class and depth are two axes, neither derived from the other. The class comes from the base
   reply line, `c3` when the user named none; `full` at `c2` and `lite` at `c5` are both valid.
   The depth is the argument; with no argument the default is `full`, and only the user lowers it.
3. Reply with one line: the type, the depth and the class, nothing else.
4. At `std` and `full` no stage starts before the user confirmed the intent text and the quality
   criteria, and nothing at all is launched before that word: the intent text, the criteria and the
   open decisions are your own writing in chat, never a job you send away, because this level
   answers to the user alone. Between the task and the confirmation the turn holds no launch and no
   task file of a later stage. At `lite` the work starts at once, on your own reading of the
   request.
5. Create the task directory and write the pointer, one command (`core.md`, "Task directory").

## Stages and gates

Every process file instantiates this table for its task type. A stage writes its file, passes its
gate, and only then does the next stage start. The main session writes the one-line status of each
gate, the ledger rows and the final report in chat; the files are written by the carriers it
launches.

The task file of a row is the file of that level; which files a depth collapses into one file, and
which it drops, stands in `core.md`, "Task directory", and nowhere else.

| stage | task file | gate | lite | std | full |
|---|---|---|---|---|---|
| `intent` — the problem, the quality criteria, the open decisions | `intent.md`, `decisions.md` | the user confirms the text and the criteria; every open decision names what it rests on | written by the main session, no gate | written by the main session, user gate | written by the main session, user gate |
| `subtasks` — the goal cut into parts | `subtasks.md` | every part of the goal has a subtask, no subtask outside the goal | folded into the intent level | yes | yes |
| `specification` — requirements, invariants, constraints | `specification.md` | traceability to the subtasks, every non-functional requirement measurable | folded into the intent level | yes | yes |
| `scenarios` — the scenarios as text, ladder level d | `scenarios.md` | every requirement and invariant has a scenario, negatives included | one-liners | yes | yes, with negatives |
| `verification-plan` — the oracle of every invariant, and the plan of the work | `verification-plan.md`, `implementation-plan.md` | every invariant has an oracle row: `existing`, `missing` or `no possible`; the plan names the steps and their order | folded into the intent level | yes | yes |
| `checks` — tests or control calls, ladder level c | `tests.md` | coverage read from the two lists; no scenario id in a test name | – | yes | yes, plus the negative control |
| `result` — the code, the document, the state, ladder levels a and b | `changes`, `runs` | the oracle is run and the run reports PASS | yes | yes | yes |
| `review` — only where no oracle is possible, ladder level e | `reviews`, `evidence` | evidence chain over the approved aspects, its facts written into `evidence`; what stays undetermined goes to the user | 1 merged critic | 2-3 aspects | 3-5 aspects |
| `coverage` — scenarios without tests, tests without scenarios | `coverage.md` | both lists are written out, empty ones said so | – | yes | yes |
| `closure` — what was done, what stays open | `report.md` | gaps, hit ceilings and unverified areas named | short | yes | yes |

`report.md` of the closure row is written by the synthesis carrier that stage launches, the one
that puts what its inputs add up to into that file; the closing carrier itself writes no file and
returns its report as text, because this harness lets no delegated job hand a report file back
(`lib/task-layout.md`, "The default output of a role"). The main session puts that text into chat.

The gate of a stage is read against the level above it, never against the conversation: the
scenarios answer to the specification, the checks answer to the scenarios, the result answers to
the checks (`core.md`, "The artifact chain"). A stage that disagrees with the level above writes
the disagreement into its own file and sends it back to that level's gate.

## Depth is a hard list

The depth is fixed at the start and is a list, not a mood.
A step a depth column marks `–` is not done at all, even when it looks useful.
The ceilings below are what makes a lighter depth cheaper; the main session counts them in the
ledger.

| depth | agents per stage | fix cycles per result | task files | user gates |
|---|---|---|---|---|
| `lite` | 2 | 1 | the file group, collapsed as `core.md` says | none: the work starts at once |
| `std` | 5 | 2 | the file group | intent with criteria, open decisions, closure |
| `full` | 10 | 3 | the file group | the same three, plus the aspect list of the review |

A hit ceiling ends the stage with what it has: the gap is written into the task files and named in
the report. Never a silent retry, never one more cycle without the user's word.

## Picking the carrier of a stage

Each stage states a need, never a name. Match the need to the usage contracts the session holds
right now; they arrive at session start and again after a compact.

| the need of a stage | what to look for in the contracts |
|---|---|
| collect facts from files, history, docs or an external source | a research carrier, one per direction, run in parallel |
| write a document of the artifact chain | an authoring carrier, launched one class step up when its output has no oracle |
| write code or tests | an authoring carrier with edit rights, on the cheapest slot the class allows |
| run a check, a suite or a control-call file | a carrier that runs commands and reports PASS or FAIL with the raw output path |
| judge an object no oracle can judge | the evidence review chain: hints, evidence, triage, fix |
| wait for something outside this session | a waiting carrier, started by the main session |

Rules that hold whatever the contracts offer: one launch does one job; the launch prompt carries
the task, the input paths and the output path and stays under 100 words all together — the return
shape, the output style and the working rules are the carrier's own text and are never repeated in
the launch, and neither is a stage row of this page; the class
and its submodes are passed on every launch; the label of every launch goes into the ledger before
the launch starts. When no contract fits a need, say so in one line and pick the closest one; when
a tool the stage needs is missing, the harness gate of `core.md` decides.

## The three points where the user is needed

1. The intent with its quality criteria, before any stage (`std` and `full`).
2. An open decision the work rests on, with the reversible default already taken.
3. The acceptance of what stayed unverified, at closure.

Put a question as one grouped ask with the recommended option first, and keep working on that
option when it is reversible. Two or more open decisions at once, or a question that timed out,
go to the carrier of user decisions named in the base text.

## Forbidden in this process

- A step the depth column marks `–`, an extra cycle past the ceiling, a second review round on the
  same object without the user's word.
- A review of output an oracle can judge, and a second reader where a stronger author is the rule.
- A stage that starts before the gate of the level above it passed; a file of a level above
  rewritten by a stage below it.
- `done` in a status without the evidence for the acceptance criteria of that stage.
- The main session doing a stage itself: it writes the gate lines, the ledger rows and the report,
  and nothing else. The one exception is the intent level, which answers to the user alone: its
  text, its criteria and its open decisions are the main session's own writing, before any launch.
- Reading a draft task file into the main session while it is still a draft; the gate line of the
  launch that wrote it is what the main session works from.
- A hint that reached no evidence changing anything, and an unverified area called verified
  because a reading went well.
