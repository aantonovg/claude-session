# Process core

Read by every process file of this skill before its own text; the session base applies underneath.
Nothing here names a carrier: it names what a stage needs, which file holds the state, and what a
gate asks. The carriers come from the usage contracts of the session.

## Task directory

One directory per task:

```
~/.claude/projects/<encoded-cwd>/tasks/<date>-<slug>/
```

`<encoded-cwd>` is the working directory with every character outside `A-Za-z0-9-` replaced by
`-`, `<date>` is `YYYY-MM-DD`, `<slug>` a short lower-case name of the task. The pointer
`~/.claude/projects/<encoded-cwd>/tasks/current` holds one line, the absolute path of that
directory. Written at the start, removed at closure, by the main session and by nobody else:

```
D=~/.claude/projects/<encoded-cwd>/tasks/<date>-<slug>; mkdir -p $D/evidence $D/reviews $D/changes $D/runs; echo $D > $(dirname $D)/current
```

The files, one level of the chain each: `intent.md`, `subtasks.md`, `decisions.md`,
`specification.md`, `scenarios.md`, `verification-plan.md`, `implementation-plan.md`, `tests.md`,
`coverage.md`, `report.md`, the state file `ledger.jsonl`, and the directories `evidence`,
`reviews`, `changes`, `runs`. At depth `lite` the documents collapse into one `task.md` with one
section per level; `tests.md` and `coverage.md` are not written at all, and the directories keep
their place.

A file is written by one stage and read by the later ones. Nobody rewrites a file of a level above
their own: a stage that disagrees says so in its own file, and the disagreement goes to the gate
of that level.

## Resume

A session that lost its context resumes from these files alone: read the pointer, then the intent,
the ledger and the last file of the chain that exists, and continue at the first level whose file
is not whole. A level counts as done only when its file is complete: the launch that wrote it has a
stop row in `ledger.jsonl`, or the file carries the closing marker of its level (the status block,
the last section the level asks for). A file that exists but is not whole — a stage killed
mid-write by a compact, an interruption or a denied capability — is redone from that level, not
read as a result. No stage researches again what a whole file already holds, and no stage trusts a
memory of the conversation over a file of this group. The same rule carries a task across
`/compact`, across an interruption and into a new session.

## Ledger

Every launch is one line in `<task dir>/ledger.jsonl`, appended **before** the launch starts:

```
{"ts","stage","step","role","kind","class","submodes","depth","slot","label","agent_id"}
```

The same field set stands in the `ledger` row of `lib/task-layout.md`, "The files", and in the hook
that appends the stop row, `hooks/ledger-stop.sh`: a field added or renamed is changed in all three.

`label` is the launch label, whose prefix carries the resolved cell of the class table, so the
ledger proves after the fact which cell each stage ran on. `agent_id` is the one field that cannot
be known before the launch: it is filled in from the launch result in the same turn the launch
returns, and a row left without one is a defect fixed in that turn, because that hook finds the
launch row by that id and writes nothing when it finds none. A launch whose result carries no id
keeps the field null; rows with no stop row end at the next row of the same kind. The ledger is
also the count the ceilings are read against, and the loop guard reads it to see the same check
fixed twice.

## Cost rules

The three dearest things in any task are reading a large code base, research, and rework. The
process exists to make the first unnecessary and the last rare.

- No stage reads a code base or a diff to "understand" it. An object with an oracle is proven by
  running the oracle; an object without one gets a stronger author, not a second reader.
- Research is cheap and named: inputs by absolute path, output one bundle file of pointers, never
  a sweep of the repository by the main session.
- The main session writes the gate lines, the ledger rows and the final report. Every job of two
  or more calls is delegated, and the result travels as a path plus a short status, never as
  pasted content.
- A payload fetched from outside is written once into `evidence/raw/` and read from there by the
  later stages; no source is fetched twice inside one task.
- Sizes: one evidence bundle stays a short list of pointers; anything longer goes into a raw file
  beside it.

## Harness gate

The sources and the checks a task needs are a hard requirement, not a nice-to-have.

1. Before the first stage, and again before the checks stage, one health check runs: every
   external source the task needs, every command and every check it will run, each by one cheap
   call.
2. Any wanted one unavailable: the stage does not start or continue. The `wanted, unavailable`
   lines go into the `Sources` block (or `Oracles` for a check), the user gets one chat line per
   missing one with the exact failure, and the turn ends.
3. On every following ping the same health check runs silently: back again means the stage resumes
   from the last ledger row without asking; still missing means one line `still unavailable:
   <list>` after the pong.
4. A project may take a capability away from this session on purpose. That is a decision of the
   project, not a fault: the gate names the missing capability in one chat line, the work goes on
   without it, and the session never asks the user to give it back. The capability stays in the
   block and in the report. Three cases, all of them a re-send and none of them an end:
   - Before the launch: read each contract of the session and send the need to one whose work
     needs nothing this project denies.
   - A launch that comes back blocked on a denied capability ends that launch, never the stage: the
     same need goes out once more, with the denied capability named in the launch text, so what
     comes next reaches the same fact another way.
   - A denied way of writing the wanted file is the same case: the need goes out again, asking for
     that file to be written another way.
   The main session never does the stage itself instead: a fact it looked up in its own turn is no
   result of this task, and one chat line that reports the missing capability is a report, never a
   request. A stage reports blocked only when every contract of the session needs what this project
   denies; the task never ends with the wanted file unwritten while one untried way to write it is
   left.
5. "Continue without <name>" from the user overrides the gate, and the unavailable list stays in
   the report.

## Sources and Oracles blocks

`Sources`, the first lines of the evidence the research stages produce, two lists:

- `used:` every source class that produced evidence (repository paths, history, docs, external
  sources by name, logs).
- `wanted, unavailable:` every source that would have answered an open question and could not be
  used, one line each, the source and the harness reason in at most eight words.

`Oracles`, the first lines of `verification-plan.md`, two lists:

- `planned:` every check type with its health-check result.
- `wanted, unconfirmed:` every check that would strengthen an invariant and whose presence could
  not be confirmed, one line each with the reason in at most eight words.

A gate passes only when its block is present, and the gate line in chat quotes the
`wanted, unavailable` or `wanted, unconfirmed` lines verbatim, or the word `none`.

## The ladder

Every object of a task sits on one level. The level decides the route; the question is never
"should this be reviewed", it is "which level is this". The verification page named by the
session-start context line holds the long form; this table is the short one.

| level | object | oracle | route |
|---|---|---|---|
| a | code | tests, benchmarks; almost always possible | run them; no review of the code; a missing suite is written first, at level c |
| b | an infrastructure change | the resulting state: requests, metrics, logs | control calls written before the change, run before it and after it; the pair of runs is the verdict |
| c | tests, control calls, harness code | the scenario list written beforehand | coverage only, read from the two lists; no quality review; at `full` a negative control |
| d | the scenarios as text | the specification | traceability: every requirement, invariant and constraint has a scenario, negatives included |
| e | the intent | only the user | hints on ambiguity, a contradiction, a hidden second goal; the user confirms the text |

The lower the level, the weaker the oracle, the more the user is needed.

## The artifact chain

The same ladder read from the top is the order of the work, for code and for prose alike:

intent → subtasks → requirements, invariants, constraints → scenarios as text → tests or control
calls → the result.

**Each level is the oracle of the level below it.** A level is checked against the level above,
never against the conversation and never against the memory of an author. An error high in the
chain is the most costly one: every level below verifies against it faithfully, so the money and
the user's attention go to the top and the bottom runs cheap. The form of a scenario is free and
carries no id; no test name carries one either, so coverage is read from the two lists.

At `lite` the top levels collapse into one short text, but their order and the rule "checked
against the level above" stay.

## How a review is read as an evidence chain

A review where no oracle is possible is not an opinion round. It is four steps, and the object
changes only on facts:

1. **Hints.** One or more critics read the object in a clean context, each through one approved
   quality aspect, and write hints: place, suspected error, severity, and the evidence that would
   settle it. Hints, not verdicts, with a cap per critic.
2. **Evidence.** Hints on the same or overlapping places form one group; each group is settled by
   facts — a run, a read, a control run on the version before the change — and comes back
   `confirmed`, `refuted` or `undetermined`.
3. **Triage.** One judge reads the hints with their evidence and writes the accepted list with the
   change each accepted row asks for. It runs no queries of its own.
4. **Fix.** The accepted list, and nothing else, changes the object; then the oracle runs where
   one exists.

Rules: a hint without evidence changes nothing — the claim it points at stays as it was, marked as
not checked, and the check the hint asks for is written down as the next step; a claim is dropped
only where a fact refutes it, and that fact is named with its pointer; an `undetermined` hint goes
to the user and never to the fix step; a failure that also shows on the version before the change is no finding; a
failure of our own side (a missing source, an access, a sandbox) is kept in its own list and never
becomes a finding; one round, and a second round only on the user's word.

Where step 2 is skipped — a short route whose critique reaches the author of the result directly —
the rule is the same and matters more: the critique is a list of doubts nobody settled, so the
result keeps every fact its sources carry, each marked checked or not checked. A result that states
nothing its sources stated, because a hint doubted it, is wrong and goes back once.

The aspect list is proposed by the main session from the quality criteria agreed with the intent,
cut to the count the depth allows, and approved by the user. No aspect critic runs without that
approval. A criterion with no aspect of its own is recorded in the task files and named in the
report as not covered by a critic, never dropped in silence.

A critic may raise the class of the stages that follow, never lower it, and says so in one line.
A checker of a key document runs one class step above its author; that step is the only per-stage
class change and does not move the class of the session.

## Status shape

Every launch returns a short structured status, five fields, and the main session copies its first
line into the ledger row:

`Status: done | partial | blocked`
`Evidence: what proves it, as paths or command output lines`
`Assumptions: what was taken as given`
`Unresolved: what is still open`
`Next: the one step that follows`

`done` without the evidence for the acceptance criteria of that stage is a defect of the stage,
not a result: it goes back once with the missing evidence named.

## Loop guard

Stop and write a failure packet into the ledger (the check, the last change summary, the
hypothesis already tried) when any of these shows:

- the same failing check fixed twice;
- a change that grows while the verification stays the same;
- a revert followed by the same change again;
- a cycle count at the depth ceiling.

A changed assumption sends the task back to the decision it rests on, not to another fix attempt.
