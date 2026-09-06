---
name: pipeline
description: Session mode 10, forks plus a staged pipeline (research, critic, decision, verification, implementation, closure check) for one bugfix, feature, migration, investigation or ops task; invoke at session start.
disable-model-invocation: true
---

# Mode: pipeline

The forks mode (`session:forks`) with a fixed order of stages and gates on top. All
fork rules come from that skill and are not repeated here: when to fork, the prompt
template, the 3-minute limit per call, no background job left running, review and fix in
different forks. Model and effort of the main session are set at start and forks
inherit them; the only stages on another model are the clean-context ones below (the critic, plus a cold researcher when the cold researcher rule in `core.md` sends breadth research there).

## Start (do this now)

0. Read `core.md` next to this file (cost principle, task directory, cost ledger, cost
   rules, harness gate, cold researcher rule, Sources/Oracles blocks, effort rule, heavy
   document cycle, ping and limit restart). Its rules are part of this mode.
1. First tool call: `CronCreate` with `cron: "*/30 * * * *"`, `prompt: "ping"`,
   `recurring: true`. Reply to every `ping` with one word. If a `ping` cron already
   exists in this session, reuse it. Limit restart: `core.md`, "Ping and limit restart".
2. Read `~/.claude/session-map.md` (fallback: `session-map.example.md` in the plugin,
   fable-opus only). Pick the pairing row the user named, else the default pairing of
   the account.
3. Reply with one line: "Pipeline mode on, ping cron <id>; forks + cold critic."
4. When the task arrives: propose its class (1-5, criteria in the README) and the path
   (class 1-2 fast, 3-4 standard, 5 or weak oracle or the word "full" from the user →
   full). Say both in one line and start; do not wait for approval unless the user asks.
   If the skill was invoked with an argument `fast`, `standard` or `full`
   (`/session:pipeline fast`), that path is fixed for the task regardless of class.
5. Create the task directory and register it, one command:
   `D=~/.claude/projects/<encoded-cwd>/pipeline/<date>-<slug>; mkdir -p $D/evidence $D/reviews; P=$(dirname $(dirname $D)); echo $D > $P/pipeline/current; echo ${CLAUDE_SESSION_ID:-$(ls -t $P/*.jsonl | head -1 | xargs basename | sed 's/\.jsonl$//')} > $D/session`
   (`<encoded-cwd>` = the cwd with every character outside `A-Za-z0-9-` replaced by `-`).

## Stages and gates

Every stage: forks for anything with 3+ tool calls and for every write into the task
directory (except the codex prompt file and ledger rows in codex mode). The main session dictates: it puts the decisions, gate verdicts and paths into
the fork prompt as short bullets, the fork writes the section and returns the status. The
main session itself writes only the one-line class/path proposal, the ledger lines and
the final chat report. Every fork returns a structured status, 5 fields, short:
`Status: done|partial|blocked`, `Evidence:`, `Assumptions:`, `Unresolved:`, `Next:`.
A fork never writes `done` without evidence for the acceptance criteria of its job.

**1. Research → Gate R.** A framing fork writes `Framing` and the first `Ledger` from
the main session's bullets (what is known, unknowns with a class: decision-changing,
verification-changing, implementation-local, nice-to-know). Then research waves: one
fork per group of unknowns (parallel, one message), each writes its evidence bundle
(≤ 80 lines, raw payloads in `evidence/raw/`) and returns facts with pointers; the last
fork of a wave updates the ledger itself, no merge fork. At most 2 waves.
Fork or cold researcher: `core.md`, "Cold researcher rule". `Sources` block: `core.md`,
"Sources and Oracles blocks". Gate R passes only when the block is present, and
when no decision-changing or
verification-changing unknown is open, contradictions are closed or accepted as risk,
and verification capabilities are listed (or "unverifiable" is written explicitly). The
main session's Gate R status line in chat quotes the `wanted, unavailable` lines
verbatim (or "none").
Two waves without new evidence → stop research, go to the critic (standard, full). Fast
path: no waves at all, the framing fork's own reads are the research and it asks the
user through `session:ask` when a decision-changing unknown stays open.

**2. Critic (standard, full) → clean context.** One lean workflow agent
(`agentType: "session:stage-critic"`, tools Read and Write only, model and effort = the
reviewer-debugger cell of the class row, budget 5 tool calls at medium, 3 at high, label
`<mod>-<eff>-critic`), input = the ledger snapshot and the framing only, no repository
access asked for. Cold agents carry only
CLAUDE.md, its imports and memory; the main session picks 0-3 skills for the stage from
the skill-routing map and puts `Read these first: <SKILL.md paths>` into the prompt (resolve
the paths first: `~/.claude/skills/`, plugin caches). It writes `reviews/critic.md`: missed
decision-changing unknowns, claims without evidence, circular reasoning, hidden
assumptions, weak verification capabilities, each with severity, and may raise the task
class (never lower it). Main triages: high-severity claims go to an evidence-audit fork
(confirm or refute against files), confirmed gaps go back into one more research wave;
the ledger is fixed by a low fork, the critic does not run again (heavy document cycle
below). Fast path skips this stage.

Effort rule and heavy document cycle: `core.md`.

**3. Decision → Gate D.** A fork writes the `Decision contract` from the main
session's choice: problem, chosen approach, alternatives and why rejected,
invariants, accepted assumptions, residual unknowns, failure modes, rollback,
invalidation triggers. Review by path: fast has no separate contract (10 lines inside
the framing fork, no review); standard: a low fork checks it against the ledger; full:
the heavy document review, one cold `session:stage-reviewer` (reviewer-debugger cell,
budget 3 tool calls at high, 5 at medium, label `<mod>-<eff>-decision-review`, input =
the contract and the ledger by path). In the full path the contract may be generated by
a heavy author run and, after the evidence step, fixed by one heavy run (the heavy
document cycle above: generate → review → evidence → fix, no second round). Gate D
passes when the check or review has no high finding left after the fix. Alternatives
drafted independently (A/B) only in the full path and only when the user asks for it.

**4. Verification plan and harness → Gate V.** A fork writes `Verification plan`
from the decision contract and the main session's bullets: invariant → oracle map, tools and their health check, scenarios, negative scenarios,
unverifiable areas, pass/fail criteria. `Oracles` block: `core.md`, "Sources and Oracles
blocks". Harness first: a fork implements the missing
tests, scenarios or checks and runs the health checks; in the full path, where the
oracle is strong (code, tests) a negative control must fail as expected before
implementation starts (standard skips the negative control; fast has no plan: existing
tests plus one new test per changed behaviour, written inside the work-item fork);
where it is weak (ops, visual) the plan says what stays unverified and the user accepts
that through `session:ask` or in chat. Gate V passes only when the `Oracles` block is present, the harness runs, the
negative control is calibrated (full) and the weak-oracle acceptance is recorded; the
main session's Gate V status line in chat quotes the `wanted, unconfirmed` lines
verbatim (or "none").

**5. Implementation → Gate I.** A fork writes `Implementation plan`: work packages with
files, acceptance criteria, order, parallelizable packages, rollback points (fast: 1-3
work items, no plan section). One fork per package (parallel only in the full path and
only for disjoint files; sequential otherwise), then verification: test runs and formal
checks are forks (mechanical); no review of the code (stage 6 rule); fix is a separate
fork.
Fix cycles per package by path: fast 1, standard 2, full 3. A check longer than ~2.5 minutes (test suites, CI,
deploys, tmux-driven checks) is not started in a fork: the fork returns first, the main
session starts it with `run_in_background` or launches a `waiter` agent (forks skill,
"Long waits and polling") and hands the result path to the next fork. Gate I passes when every package
is done with evidence and no plan deviation is unrecorded.
Loop guard: the same failing check fixed twice, a diff that grows without better
verification, or revert/reapply → stop that fork, write a failure packet (check, last
diff summary, hypothesis tried) into the ledger, and send a review fork to diagnose; a
changed assumption sends the task back to the `Decision contract`.

**6. Closure check → Gate F.** There is no "final review" of the work. Code is verified
by the harness; the closure check is mechanical: a low fork reads the verification plan,
the harness results and the implementation plan with package status, and writes
`reviews/closure.md`: every invariant has a passed scenario, every package has
evidence, every deviation is recorded, the unverifiable areas are listed with their
acceptance; last line `DONE severity=<…>`. A gap → a fix fork, then the check once more
(rounds by path: fast none, the main session reads the harness result line; standard 1;
full 2). Gate F passes at severity low or none.

There is no code review in this mode. Author rule for a package with no formal
verifier in the harness: its author is opus-low (terra-high in terra executor mode) and
nobody reviews it; a second reader of the same class is waste. A cheap executor
(sonnet-low, luna-high) writes only packages that have a verifier in the harness. Tests
and harness code are written at low and never reviewed. Reviews of documents (critic,
decision contract) are the only reviews, and the only ones that may use medium or high
effort, within their tool-call budget.

**7. Closure → Gate C.** Fast path: 5 lines in chat by the main session, nothing else.
Otherwise a fork writes the `Report` (Russian, plain: what was solved and
why, what was found, what was changed, how it was verified, what stays unverified,
rollback, next steps) and marks `task.md` final; the main session gives the same in
chat from the fork's summary and updates the task status where the task lives (Jira,
MR, issue) when the user allows. Commit and push only on the user's word. Remove
`pipeline/current`.

## Paths: what each one skips

The path is fixed at Start (argument or class) and is a hard list, not a mood. Each
step below is done exactly as the row says; a step marked `–` is not done at all, even
when it looks useful. Budgets are ceilings the main session tracks in the ledger; when a
ceiling is hit the stage ends with what it has and the gap goes into the report.

| step | fast (class 1-2) | standard (class 3-4) | full (class 5, weak oracle, on request) |
|---|---|---|---|
| task files | `task.md` only, ≤ 120 lines | `task.md` ≤ 300 lines | split files |
| framing + ledger | one fork, ≤ 6 turns, framing and research together | framing fork | framing fork |
| `Sources` block (ledger) | 2 lines | full lists | full lists |
| research waves | – (the framing fork's own reads are the research) | 1 wave, ≤ 2 forks or cold researchers | ≤ 2 waves, ≤ 3 per wave |
| critic (cold, heavy) | – | 1, budget 5 calls at medium / 3 at high | 1, same budget, then evidence-audit fork |
| decision contract | 10 lines inside the framing fork | fork | fork; A/B draft only on request |
| decision review (heavy document review) | – | – (a low fork checks it against the ledger) | 1 cold `stage-reviewer`, budget 3 calls at high / 5 at medium |
| heavy document cycle | – | review only, 1 heavy run | generate → review → evidence → fix, ≤ 3 heavy runs |
| verification plan | – (existing tests + one new test per changed behaviour) | fork, no negative control | fork, negative control calibrated |
| `Oracles` block (plan) | 2 lines, inside the work-item fork's note | full lists | full lists |
| harness build | inside the work-item fork | 1 fork | 1 fork per oracle |
| implementation | 1-3 work items, one fork each, sequential | packages, one fork each | packages, parallel when disjoint |
| fix cycles per package | 1 | 2 | 3 |
| no-verifier packages: opus-low author, no review | – | – | – |
| closure check | – (main reads the harness result line) | 1 round | 2 rounds |
| report | 5 lines in chat, no report section | `Report` section | `report.md` |
| ceilings | ≤ 6 forks, ≤ 50 turns, 0 cold agents | ≤ 14 forks, ≤ 120 turns, 1 cold agent | ≤ 24 forks, ≤ 220 turns, ≤ 3 cold agents |

Measured 2026-09-06 (demo game, before this table): fast $5.3, standard $15.2, full
$11.7-13.0; standard was not cheaper than full because nothing was actually skipped.
The ceilings above are what makes a lighter path cheaper.

## Questions to the user

Only through `session:ask` (or in chat when the user is present): grouped, with the
reversible default already chosen and the work continuing on it. No separate
"pending-human" state: the open question lives in the questions file and the TaskList.
A choice that must be the user's ends the turn with the question restated.

## Forbidden in this mode

- Everything the forks skill forbids, with one exception: the clean-context stages
  (critic, the full path's decision review, and research jobs that meet the
  cold-researcher rule in stage 1) run as a `Workflow` with lean `agent()` calls: one
  agent per single stage, one workflow (`parallel`) for a wave of cold researchers;
  no other workflow stages, no plain subagents, no teammates (forks skill, "Launch
  forms").
- No hard-coded model or effort in prompts: the critic and the full path's decision
  review take the reviewer-debugger cell of the session map, the cold researcher its
  researcher cell, the author of a no-verifier package is opus-low (terra-high in terra
  executor mode); everything else is the main session's model. No code review by anyone.
- No reading of draft task files by the main session (`task.md`, split files, `evidence/`,
  `reviews/`, `ledger.jsonl`); a file marked `Status: final` may be read once.
- No extra artifacts in fast and standard paths (one `task.md`), no skill metadata,
  no hash graph, no cost manifest beyond `ledger.jsonl`; $ is computed after the fact by
  `tools/pipeline-cost.py` from the transcripts.
- No third research wave, no third fix cycle per package, no third closure check: stop
  and ask.
- No second review or fix run on a document without the user's word: a key document
  gets generate → review → evidence → fix once, within the path's heavy-run count.
- No step the path row marks `–`, no fork, turn or cold-agent count over the path's
  ceiling: the ledger row count is the check, and a hit ceiling ends the stage.
- No polling or waiting inside a fork: long waits go to the `waiter` agent launched by
  the main session.
- No fork over 12 turns, no gap over 3 minutes between a fork's read and its write, no
  second fetch of the same MCP resource, no evidence bundle over 80 lines, no spawn
  without its ledger row and `agent_id`.
- No `/model`, `/effort`, plugin changes or `/compact` in the middle of a task.

## Reference

Shared rules and files: `core.md` next to this file. Class criteria, the role map, what is
measured and what is still untested for this mode: `plugins/session/README.md`, section
"Mode 10 — Pipeline".
