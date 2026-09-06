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
inherit them; the only stages on another model are the clean-context ones below (the critic, plus a cold researcher when the stage 1 rule sends breadth research there).

## Cost principle (why the pipeline exists)

The three dearest operations of any task, in order, and what this mode does with each:

1. **Reading a large code base.** Never done as a stage. No agent reviews the code
   base or the diff, ever; a package is proven by its formal verifier (tests,
   scenarios, checks) that the harness runs. A package with no verifier is written by
   opus-low (terra-high in terra executor mode) and nobody reviews it. Every other
   stage of the pipeline exists to make this reading unnecessary.
2. **Initial research.** Done cheaply or not at all: breadth by cold sonnet-low
   researchers with named inputs, judgment by short forks (≤ 8 turns), never by a
   medium or high agent, never a repository sweep by the main model.
3. **Implementation.** Done by low executors: forks at the main model's low effort, or
   sonnet-low / luna-high slots when the codex axis is on. Never medium or high.

Medium and high effort exist for exactly two things: generating a key document
(decision contract, verification plan on request) and critiquing a key document (the
critic, the decision review), each within 5 tool calls at medium and 3 at high. When the
main session is about to launch anything else at medium or high, or anything that reads
volumes of code, it is off the pipeline: stop and pick the cheap form.

## Start (do this now)

1. First tool call: `CronCreate` with `cron: "*/30 * * * *"`, `prompt: "ping"`,
   `recurring: true`. Reply to every `ping` with one word. If a `ping` cron already
   exists in this session, reuse it. Limit restart: when the context shows the previous
   stage was cut off by the subscription limit or an API error (error line instead of an
   answer, a fork or cold agent launched and never returned, a gate announced and not
   reached), the ping is the restart signal: `pong`, then in the same turn resume that
   stage from the last ledger row (relaunch the fork or agent, re-arm the wait). A stage
   stopped by the Harness gate resumes the same way once its health check passes.
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

## Task directory

One directory per task: `~/.claude/projects/<encoded-cwd>/pipeline/<date>-<slug>/`.

- fast and standard: one file `task.md` with the sections `Framing`, `Ledger`
  (evidence with file:line pointers, unknowns with a class, contradictions,
  assumptions, verification capabilities), `Decision contract`, `Verification plan`,
  `Implementation plan`, `Report`; keep it under ~300 lines (fast: ≤ 120, no `Report`
  section). Research forks write
  `evidence/EB-<n>.md`; review stages write `reviews/<stage>.md`.
- full: the same sections as separate files (`ledger.md`, `decision.md`,
  `verification.md`, `implementation.md`, `report.md`) plus `evidence/` and `reviews/`.
- Forks write and update `task.md` (or the split files) and own only the files their
  prompt names. The directory is the state of the task: a new session continues from it
  (untested, see README).
- Draft files are read by forks only. While a file is a draft, the main session never
  reads `task.md`, the split files, `evidence/`, `reviews/` or `ledger.jsonl`: it works
  from the fork return lines (facts, gate verdict, at most the word limit the prompt set)
  and passes file paths, not contents, to the next fork. A fork marks a file final by
  writing `Status: final` in its first lines; the main session may then read that file
  once, and only when holding its content helps the remaining stages. Every read of a
  big file by the main session is context it keeps until the session ends.
- TaskList mirrors the gates: one task per gate below, marked as they pass.

## Cost ledger

Every spawn and every main-session stage is one line in `<task dir>/ledger.jsonl`, so
the cost can later be cut by stage, step, role, kind and model:
`{"ts","stage","step","role","kind":"main|fork|workflow-agent","model","effort",
"mode":"fast|standard|full","class","agent_id","label"}` (`label` = the launch
description or workflow label, starting with the `<mod>-<eff>-` prefix as the forks skill prescribes). The main session appends the
line BEFORE the launch (merge, fix and audit forks included) and fills `agent_id` from
the `Agent` result right after; a fork row without `agent_id` is a bug the main session
fixes in the same turn. Rows of kind `workflow-agent` and `codex-agent` leave `agent_id`
null and carry the exact workflow `label`: the cost script resolves them through the
saved workflow script and its journal. `agent_id` is null for the main session's own
stages too, appended when the stage starts. The task
directory path in `pipeline/current` and the session id in `<task dir>/session` come
from the Start step. The plugin's `SubagentStop` hook (`hooks/pipeline-subagent-stop.sh`)
appends `{"ts","agent_id","event":"stop"}` per finished agent whose id the ledger already
names (other agents and repeats are ignored); workflow agents get no stop row, their
window ends at the next row of the same kind. The table:
`tools/pipeline-cost.py <task dir>` (tokens, cache read / write 5m / 1h, misses, $ per
row; totals by stage, role, kind, model+effort); `--all-runs <pipeline root>` compares
runs and calibrates the fast / standard / full paths. Remove `pipeline/current` at closure.

## Cost rules (from test 1)

Test 1 (B2CT-22116, opus-low, full, through Gate D): $17.9, 63% of it prefix re-reads over
197 turns, one miss. The forks skill's turn cap and read-once rule apply; on top of them:

- Terse main session: one status line per gate in chat, short ledger lines and fork
  prompts, no restating of fork results; its 29K of chat became prefix for ~120 turns.
- MCP payloads: ask for the fields needed (Jira JQL field list, GitLab discussion or job
  filters); write the raw payload once to `evidence/raw/<name>.json`, later forks read
  that file. No resource is fetched twice within a task.
- Sizes: evidence bundle ≤ 80 lines (pointers, not quotes), `ledger.md` ≤ 120; more goes
  into a raw file plus a short bundle. No merge fork: the last wave fork updates the ledger.

## Harness gate

Research and verification tools are a hard requirement, not a nice-to-have.

1. Before stage 1, and again before stage 4 for the verifiers, the main session runs one
   health check in one fork: every MCP server the task needs (by name, one cheap read call
   each), VPN or proxy reachability for the hosts the task needs, the docker daemon when
   the project uses it, the CLI binaries and skills the task names, and, when the codex
   axis is on, `codex -p <profile> mcp list` for the same servers.
2. Any wanted tool unavailable → the stage does not start or continue: the `wanted,
   unavailable` lines go into the `Sources` (or `Oracles`) block, the user gets one chat
   line per tool with the exact failure, and the turn ends.
3. On every following `ping`: `pong`, then in the same turn the same health check runs
   silently; when every wanted tool is back, the stage resumes from the last ledger row
   without asking; when not, one line `still unavailable: <list>` follows `pong`.
4. The fork fallback for `BLOCKED: no MCP` from a cold researcher applies only when the
   same MCP call succeeds in the main session's health check (the tool exists, cold
   agents cannot see it); a tool that fails in the health check is a harness outage under
   point 2, never a fallback.
5. The user may override with "continue without <tool>": the stage runs and the
   unavailable list stays in the block and in the report.

## Stages and gates

Every stage: forks for anything with 3+ tool calls and for every write into the task
directory. The main session dictates: it puts the decisions, gate verdicts and paths into
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
Fork or cold researcher: a fork re-reads the whole main prefix on every turn (150K
prefix × 8 turns = 1.2M read tokens), a cold `session:stage-researcher` (Workflow agent,
researcher cell of the class row, usually sonnet-low, label `<mod>-<eff>-research`)
costs a fixed ~15-20K start (lean agent: no Skill tool, few tool schemas; measured 13K
bare) and nothing per turn, but knows nothing of the chat and reasons at sonnet level.
The choice is price for quality, made per research job, not by prefix size:
- Breadth research → cold researcher: inventories, grep sweeps, reading docs or
  history, collecting file:line pointers, raw MCP payload fetches into `evidence/raw/`,
  anything whose inputs can be fully named in the prompt. Typical for the first wave of
  a big task, when the mass of unknowns is still nice-to-know or implementation-local.
- Judgment research → fork: why a bug happens, weighing contradictions, unknowns that
  are decision-changing, a small but hard task, anything that needs the chat so far.
  Typical for the closing wave, after breadth is done. Keep such forks short (≤ 8 turns,
  little output): their cost is the prefix re-read plus output, not the start.
- Model economics tilt the border: on a fable main session cache reads are cheap and
  output and 5m writes dear, so forks are affordable on a big prefix but must stay
  terse; on an opus main session cache reads are the dear part, so a big prefix pushes
  breadth work to the cold researcher sooner. In doubt: first wave cold, second wave
  forks.
The cold researcher writes the same `evidence/EB-<n>.md` and gets the same ledger row
(`kind: workflow-agent`); a wave of cold researchers is one `Workflow` with `parallel`,
never several launches; the main session appends its stop line. Fetching raw MCP
payloads into `evidence/raw/` is a cold-researcher job: the prompt names the exact MCP
tool names (`Tools: mcp__gitlab__get_merge_request, mcp__jira__get_issue, …`), the agent
loads them with ToolSearch. When the first cold researcher returns `BLOCKED: no MCP`
(the session's MCP servers are not visible to workflow agents), that fetch goes to one
short fork instead, its ledger row label gets the `(fallback)` suffix, and no second
cold researcher is launched for the same fetch.
`Sources` block, the first lines of the `Ledger` section (`ledger.md` in full), two
lists: `used:` every source class that produced evidence (repo paths, git history, MCP
tools by name, docs, CI logs, skills loaded); `wanted, unavailable:` every source that
would have answered an unknown but could not be used, one line each, the source and the
harness reason in ≤ 8 words (`GitLab MCP: not visible to cold agents`, `registry: 403
from this host`, `VPN: down`, `skill x: missing`). The framing fork writes the first
version, every research fork appends. Gate R passes only when the block is present, and
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

Effort rule for every agent in this mode: medium or high effort exists only for the
generation of an important document and for its critique, within a stated budget of 5
tool calls at medium and 3 at high (the critic, a decision contract review, a heavy
agent the user asks for). Nothing at medium or high reads volumes of work: no code
review, no repository sweep, no test run. Code is verified by scenarios and never
reviewed; a package without a scenario is authored by opus-low (terra-high in terra
executor mode) instead. Everything else is low.

Heavy document cycle, fixed for every key document (the ledger snapshot at Gate R, the
decision contract; the verification plan only on the user's request): generate → review
→ evidence → fix, and it stops there. Generate = one run. Review = one run (the critic
or the decision reviewer, document only, its tool-call budget). Evidence = low forks or
cold sonnet-low researchers confirm or refute each high finding against files (the
evidence-audit step). Fix = one run that applies the confirmed findings. No second
review, no second fix; a further cycle only on the user's explicit word. Heavy = the
reviewer-debugger or author cell at medium or high, or sol / astra when the codex axis
is on, each within its budget (5 tool calls at medium, 3 at high). Per path: fast = 0
heavy runs (documents by low forks, no review); standard = 1 heavy run (the review),
generation and fix by low forks; full = up to 3 heavy runs (generate, review, fix) for
the decision contract, and for the ledger only the review.

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
unverifiable areas, pass/fail criteria. `Oracles` block, the first lines of the plan:
`planned:` each verifier type with its health-check result (tests, scenarios, static
checks, docker, CI job, MCP read, CLI, skill); `wanted, unconfirmed:` each verifier that
would strengthen an invariant but whose presence could not be confirmed (docker, MCP,
CLI binary, skill, access, VPN), one line each with the reason in ≤ 8 words. Harness first: a fork implements the missing
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

Class criteria, the role map, what is measured and what is still untested for this
mode: `plugins/session/README.md`, section "Mode 10 — Pipeline".
