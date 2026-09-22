# Task file group

The state of a task lives on disk, not in a context window: between stages, across an
interruption, across `/compact` and across sessions. One layout holds for every process and every
depth (idea 8.8).

Directory of one task:

```
~/.claude/projects/<encoded-cwd>/tasks/<date>-<slug>/
```

`<encoded-cwd>` is the working directory with every character outside `[A-Za-z0-9-]` replaced by
`-`, the form the harness already uses for its own project directories. `<date>` is `YYYY-MM-DD`,
`<slug>` a short name of the task in lower case.

The pointer to the task a session is working on:

```
~/.claude/projects/<encoded-cwd>/tasks/current
```

One line: the absolute path of the task directory. The pointer is
written by the process skill when the task directory is created and
removed by the process skill when the task is closed; no hook and no workflow writes it.
`hooks/ledger-stop.sh` and `hooks/modes.sh` read it and nothing else: with no pointer an ordinary
session writes no ledger row at all and gets no resume line after a clear, a compact or a resume.

A file of the layout is written by one stage and read by later ones. Nobody rewrites a file of a
level above their own: a stage that disagrees with the level above says so in its own file, and
the disagreement goes to the gate of that level.

## The files

Paths are relative to the task directory. `kind` is `file` (one document), `dir` (one file per
run of a stage, named by the stem the stage passes) or `state` (machine-written). The last column
is what the depth `lite` does with the row: `task.md` means the row becomes a section of the one
collapsed file, `-` means the depth does not have that level at all, and any other value means
the row stays as it is.

<!-- layout table (read by bin/build.sh; every row becomes an entry of LAYOUT in lib/block.js) -->

| key | path | kind | written by | read by | at lite |
|---|---|---|---|---|---|
| facts | ledger.md | file | the research stage (the synthesis carrier, when the process names `ledger.md` as its `out`) | the intent, decisions, verification-plan and implementation-plan stages | task.md |
| intent | intent.md | file | the intent and quality criteria stage, confirmed by the user at `std` and `full` | every later stage: authors as constraints, the review chain as its aspect source, triage as its severity scale | task.md |
| subtasks | subtasks.md | file | the subtasks stage, from the confirmed intent | the specification stage, the scenario stage, closure | task.md |
| decisions | decisions.md | file | the intent and specification stages: the decision contract and what each decision rests on | every author, triage, closure | task.md |
| specification | specification.md | file | the requirements stage (`spec-author`), checked against the subtasks | the scenario stage, the key-document review, the code author | task.md |
| scenarios | scenarios.md | file | the scenario stage (`scenario-author`), checked against the specification | the test stage, the coverage check, the executor | task.md |
| verification-plan | verification-plan.md | file | the verification-plan stage: one oracle row per invariant (`existing`, `missing`, `no possible`) | the test stage, the executor, closure | task.md |
| implementation-plan | implementation-plan.md | file | the planning stage (`plan-author`) | the code author, the fixer, closure | task.md |
| tests | tests.md | file | the test stage (`test-author`): the test files it wrote, one path per line | the coverage check, the executor, closure | - |
| coverage | coverage.md | file | the coverage stage (`coverage-checker`): scenarios without tests, tests without scenarios | closure, the user | - |
| report | report.md | file | the synthesis stage (`synthesizer`): the answer its inputs add up to. The closure stage writes no file: this harness lets no subagent write a report, so its report travels back as the text of its return | the user, the next task | task.md |
| ledger | ledger.jsonl | state | one row per launch by the stage that launches (class, depth, slot, label, and `agent_id` filled in from the launch result, the field the stop hook finds the row by; a row whose `agent_id` stayed null gets a stop row that names its `stage` and `step`), one stop row per agent by the SubagentStop hook, which also writes the one intent stop row (`stage` `intent`, no `agent_id`) at the first stop row of the task | closure, the cost reading, the loop guard | ledger.jsonl |
| evidence | evidence | dir | the research and evidence stages (`researcher`, `web-researcher`, `evidence-researcher`, `evidence`), one bundle per run | triage, the synthesis stage, closure | evidence |
| reviews | reviews | dir | the review chain: hint lists per critic, the accepted list of triage, the result of a key-document check | the fixer, closure, the user | reviews |
| changes | changes | dir | the code author and the fixer: the paths they changed, one file per run | the executor, closure | changes |
| runs | runs | dir | the executor: the raw output of every check run, including the control run on the base version | the fixer, the coverage check, closure | runs |

<!-- end layout table -->

At `lite` the document rows above collapse into one file, `task.md`, with one section per row;
the rows marked `-` are not written at all, and the state rows and the directories keep their
place. Nothing else changes: the same stage writes the same content, in a section instead of a
file.

## The default output of a role

A role launched with the task directory as its `out` writes the file of this table; a role
launched with a file path writes that path. A role with no row here always needs a path: its
output is not a file of the task group.

`closure-author` has no row and writes no file at all: it reads `out` as the directory the run
filled and returns its report as text, because a subagent of this harness cannot hand a report
file to anybody. The stage that launches it checks the return, never a path.

<!-- role output table (read by bin/build.sh; every row becomes an entry of LAYOUT.roleOut) -->

| role | key | stem |
|---|---|---|
| plan-author | implementation-plan | |
| spec-author | specification | |
| scenario-author | scenarios | |
| test-author | tests | |
| code-author | changes | code |
| fixer | changes | fix |
| coverage-checker | coverage | |
| critic | reviews | hints |
| evidence-triage | reviews | accepted |
| evidence-researcher | evidence | answers |
| evidence | evidence | answers |
| researcher | evidence | bundle |
| web-researcher | evidence | web |
| synthesizer | report | |
| executor | runs | run |
| waiter | runs | wait |

<!-- end role output table -->

## Resume

A session that lost its context resumes from these files alone: it reads the pointer, then the
intent, the ledger and the last file of the artifact chain that exists, and continues at the
first level that is not done by the completeness rule of the process core (a stop row of the
launch that wrote the file). No stage re-researches what a file of the group already holds, and
no stage trusts a memory of a conversation over a file of this group.
