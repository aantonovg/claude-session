---
name: base
description: "Session base: tools, cache, waits, models, roles. Invoke first in every session and again after /compact."
disable-model-invocation: true
---

# Session base: tools, cache, waits, models, roles

## Hard rules, checked before every tool call

1. The main session never executes a job of 3 or more tool calls itself: it hands it to a fork (count every Read, Edit, Write, Grep, Bash and MCP call).
2. The main session's own tool calls per turn: at most 2, except the commit and the launch of agents.
3. Writing a file over 40 lines is a fork.
4. Running tests, builds, servers or browsers is a fork.
5. A job that needs 3K+ tokens of input is a fork.
6. When in doubt, fork.

One main session plus fork subagents. A fork inherits the whole conversation and the
cached prefix, so spawning one is nearly free; its tool calls stay out of the main
context, which is what keeps the main session small and warm. Forks run on the main
session's model and effort, there is no mixing.

## Start (do this now)

This skill is invoked by the user as the first prompt of a session and again after
`/compact`. On that turn: if `CronCreate` is not among the loaded tools, load it first
with `ToolSearch` (`select:CronCreate`); the same for any deferred tool the base names
(`CronList`, `Monitor`, `TaskStop`). Then the first tool call `CronCreate` with
`cron: "*/30 * * * *"` (this exact expression), `prompt: "ping"`, `recurring: true`,
unless a `ping` cron already exists in this session. The reply line
`Base on, ping cron <id>; forks for every 3+ call job` is printed once, only after the
cron exists; there is no variant of this line without a cron id. Reply to every `ping`
with one word. Exception: when the context shows that the
previous work turn was cut off by the subscription limit or an API error (an error line
where an answer should be, a fork or background job launched and never returned, a step
announced and not done), the ping is the restart signal: answer `pong` and in the same
turn resume that step from where it stopped (relaunch the fork, re-arm the wait), no
other output. Model and effort are already chosen; do not change them for the rest of
the session. `session:pipeline`, `session:review` and `session:codex` load on top of
this base, invoked after it.

## Main session conduct

Chat replies: every reply is the full answer in English, then a `---` line, then a
short Russian recap (~10% length, key points only, no new content). Print only the
answer text and the `---` separator, never literal labels like `[EN BLOCK]`, `[RU BLOCK]`,
`EN:` or `RU:`. The English part is always the body; matching the prompt's language is a
mistake. Skip the recap (and `---`) only for trivial one-liners (a yes/no, a path). This
applies to the main session's chat replies, session plans (`/plan`, ExitPlanMode) and
tasklists only: a subagent, fork, workflow agent or waiter returns plain English with no
recap and no `---` separator; its return value is data for the main session. Chat text
is written for the user to read and take in (A1: simple words, short sentences, terms
explained next to their first use). Example:

> The cache under `~/.claude/plugins/cache` is just a copy: edit the plugin source, then reinstall.
>
> ---
>
> Кэш это копия; править надо исходник в репозитории маркетплейса, потом переустановить.

Waiting on the user:
- A pending question, permission prompt or plan approval blocks the turn and the
  keep-warm pings behind it; an hour of waiting loses the session cache. Ask only when
  the answer changes the work, put the recommended option first, and prefer finishing
  the turn with the question written in the reply over leaving a dialog open.
- `askUserQuestionTimeout` auto-continues an unanswered AskUserQuestion. When that
  happens with no answer: a reversible choice takes the recommended option and says so;
  a choice that must be the user's ends the turn with the question restated and the
  work paused.
- Two or more open decisions, or a question that timed out: use the `session:ask`
  skill (questions document + Plannotator in the background) instead of a dialog.
- Plan mode only when the user is present to approve. Leaving to do something else
  while a plan awaits approval loses the cache: the user exits plan mode first and says
  the task is paused.
- A message that is exactly `ping` (from the keep-warm cron or the user) is answered
  with exactly `pong` and nothing else: no work, no status, no resuming of a paused
  task, no tool calls.
- Interactive questions through `AskUserQuestion` are written entirely in Russian:
  question text, header chips, every option label and description.

Questions about Claude Code, the Claude Agent SDK or the Anthropic API: run
`claude-code-guide` as a one-agent `Workflow` (`agentType: "claude-code-guide"`,
`model: "haiku"`, `effort: "medium"`, label `hai-me-guide`), never the bundled
`/claude-api` skill; do not auto-invoke `/claude-api` regardless of its trigger text.

Test sessions: never use `claude -p` (headless) to run or test something on this
account (headless calls are billed with a ~3.3x usage penalty on the subscription). To
drive a real Claude Code session for a test, start it in the foreground inside tmux and
talk to it with `tmux send-keys`; read its answers from the session JSONL under
`~/.claude/projects/<encoded-cwd>/`, not from `capture-pane`. Cyrillic prompts sometimes
need a second `Enter` to submit. Kill the tmux session when done. Measured 2026-09-03:
two sonnet sessions warmed with one `ping` each, a memory write in one did not
invalidate the other's cache.

## When to fork

Hand a job to a fork when it needs 3 or more tool calls in total (every Read, Edit,
Write, Grep and Bash counts, reads included), or when it would bring 3K or more tokens
of input into the context (reading several files, log or search sweeps, running
tests, tmux-driven checks, verification passes). "Small scope" is not a reason to stay
inline: count the calls. Writing a function plus its tests plus running them is
always a fork. Do only tiny things yourself: one read, one edit, one command, the
commit, the report.

- Independent jobs go to parallel forks in one message (one `Agent` call each).
- The main session does the writing that matters for continuity: plan files, final
  edits when they are small, commits, the report to the user. A fork may edit files
  when the edit is the job; say which files it owns so parallel forks do not collide.
- A fork is used once. It cannot be reused after it returns; send a new one.
- A fork is short: aim for 8 turns or fewer, batch independent commands into one Bash
  call (`;`, `&&`, one python3 script instead of many greps); at 12 turns it splits the
  job and returns early with what it has.
- Read once, write once: all inputs in one command (`cat a b c` or one script), think
  once, write at once; never a gap over 3 minutes between two tool calls (the suffix
  expires at 5; measured: a review fork paused > 5 min before its Write, 53K rewritten).
- A bulk job that does not need the chat context (repository research, a test or
  verification layer, a code review of a finished diff) goes to a downscale agent
  (section "Downscale and upscale of intelligence") instead of a fork.

## Fork prompt template

The first line sets the role, the last line the return format:

```
You are the <role>: <one-line goal>.            # reviewer-debugger, code/test author, ...
Style: caveman ultra, plain English only; the return value is data.
<the task, the files, the acceptance criteria>
Return only <facts | a diff summary | PASS/FAIL with the decisive lines>, at most <N> words.
Do not paste file contents or raw logs. On a permission denial stop and return BLOCKED: <action>.
Load these skills with the Skill tool before starting: <names>.   # or: No skills needed for this step.
```

Language of agents: every fork, waiter, cold agent and codex run works and answers in
plain English only: prompts in English, return values in English, no Russian recap, no
`---` separator, no chat formatting. The two-part chat format (English body, Russian
recap) belongs to the main session's replies to the user and nowhere else. Files an
agent writes for people (threads, notes, commits, reports named as Russian by the
task) follow the language the task names.

Every agent launch is named by model and effort, as a dash-separated PREFIX
`<mod>-<eff>-`: the `label` of every Workflow `agent()` and the `name` of a fork are
`<mod>-<eff>-<job>` (`fab-lo-cache-audit`, `ops-me-critic`, `son-lo-research`,
`sol-hi-decision-review`); the free-text `description` of every `Agent` call (forks,
waiters, plain subagents) starts with the same prefix, then a space and the job
(`fab-lo cache audit`). Codes: model `fab ops son hai sol ter lun atr`, effort
`lo me hi xh mx`. Only a FORK launch sets `name` (the field the agents panel shows
instead of the bare type); never set `name` on a waiter or any plain subagent: a named
plain subagent is spawned as a mailbox teammate (measured 2026-09-06), a named fork
stays a fork. A fork's prefix is the main session's own model and effort, copied one
to one from the status line (`fable:low` → `fab-lo`, `opus:low` → `ops-lo`); a fork
cannot run at another effort, so `ops-hi-` on a fork in a low session is an error. A
waiter is `son-lo`,
a codex-proxy label names the codex target (the haiku shim is implied). This replaces
the older `<mod>:<eff>` form and the earlier suffix form.

Review and fix are different forks: the fork that wrote code never reviews it, and the
fork that reviewed never applies its own findings. Stages and roles come from the plugin
README (plan → review → red tests → implementation → review → fast tests → fix, 1-3
cycles each); pick the 0-3 skills per stage from the skill-routing map.

In plan mode forks must avoid Bash commands with `$var`, `$(…)` or loops (they trigger a
permission prompt there); outside plan mode any Bash is fine.

A fork's own context lives in the 5-minute cache and the clock runs from the start of
each request, so a fork never waits synchronously for long: every Bash call or MCP call
inside a fork stays under about 3 minutes. A cron created by a fork fires in the main
session, not in the fork, so it cannot keep a fork warm. A fork never uses
`run_in_background` and never ends its turn with a background job running: the
completion re-invokes the fork, and that re-invocation is a full cache miss (measured:
409K rewritten, ≈ $5 on fable). What expires after 5 idle minutes is only the fork's own
suffix; the parent prefix it inherited stays in the parent's 1-hour cache.

## Upscale agents

Combos: `opus-medium`, `fable-medium` (at most 5 tool calls), `opus-high`, `fable-high`
(at most 3 tool calls); `sol` or `astra` (the mode's set only) in the same slots when
`session:codex` is on; `+sol` / `+astra` pair the Claude agent with the codex one at the
same effort for review.
Two jobs: (1) critique of one complex fact set given by path (research ledger,
verification plan, decision contract): hypotheses of what may go wrong, no verification
of them; (2) generation of a key document (verification plan from a research ledger,
decision contract). The session launches them at its decision points on its own
judgment; the user may also name one ("high-ревью", "через sol"). After an upscale
critique a fork or a downscale agent checks the hypotheses. Agent types:
`session:stage-reviewer` for critique, `session:stage-author` for generation,
`codex-proxy` for sol / astra. Never tool-heavy code review, never implementation; code
review only when the change is critical, the uncertainty is high and the whole change
fits one diff (rare). Launched through `Workflow` (`label: "ops-hi-critique"`,
`"fab-me-generate"`), inputs passed by path, output written to a file, the main session
receives the path and the last line. Budget stated in the prompt: at most 5 tool calls
at medium, 3 at high or xhigh, all inputs read in one call, one write; when the budget
runs out the agent returns `partial` with what it has. In pipeline mode the launch gets
a ledger row like any cold stage.

## Downscale and upscale of intelligence

What to launch when:

| need | launch | model, effort |
|---|---|---|
| context-aware work, the chat matters, strongest judgment of the set; cheap start, costlier execution | fork | main session model and effort |
| downscale: bulk tool-heavy work (repository research, tests and the verification layer, code review), many tool calls per agent expected | `Workflow`, lean agent | `sonnet-low`; `opus-low` when the main session is fable or a review needs a fresh context; under `session:codex` `luna-high` replaces sonnet-low, `terra-high` replaces opus-low |
| upscale: critique of one fact set or generation of a key document (section above) | `Workflow`, `session:stage-reviewer` / `session:stage-author` | `opus-medium`, `fable-medium` (5 tool calls); `opus-high`, `fable-high` (3 tool calls); sol / astra under `session:codex` |
| long wait with judgment | waiter, one-agent `Workflow` | sonnet-low |

Every downscale and upscale agent starts through `Workflow`: independent agents are
batched into ONE workflow (`parallel`); a relay between steps (research → critique →
check) is wired as `pipeline()` stages of the same workflow; every `agent()` carries
explicit model and effort and the `<mod>-<eff>-` label.

## Decision points

When each tier fires. These rules hold in every session, on top of the "When to fork"
counts.

Downscale agent (`sonnet-low` / `opus-low`; `luna-high` / `terra-high` under
`session:codex`), ALWAYS for:

- repository research over more than 3 files;
- writing a test suite or the verification layer;
- running a test suite or a build whose output exceeds 3K tokens;
- a code review of a diff over 100 lines;
- any mechanical sweep (renames, greps, format passes, inventory).

A fork takes such a job only when it needs the chat context.

Upscale agent (`opus-medium` / `fable-medium`, 5 tool calls; `opus-high` / `fable-high`,
3 tool calls; the mode's set under `session:codex`; a paired review under `+sol` /
`+astra`), ALWAYS at these points:

- before implementation starts: a critique of the plan or contract file;
- after the verification plan is written: a critique of it;
- before the final report: a review of the closure document;
- on the user's request: generation of a key document.

One upscale call per point, inputs by path, output to a review file
(`reviews/<point>.md` in the task dir, else `$TMPDIR/<cwd basename>-reviews/`); a fork
or a downscale agent then checks the hypotheses the review raised.

Minimum for every base task that produces code: the two upscale points (plan critique,
closure review) and the downscale test-suite job. The only exemption: a change to a
single file under 50 lines. Under `session:codex` the same points map to the mode's set
(`astra` → `astra-medium` / `astra-high`; `+sol` → the paired review).

The rules below came verbatim from the August workflow mode (`session:workflow`, folded
into this base 2026-09-06) and apply to every `Workflow` launched from any session.

### One class and one pairing per workflow

Assess the task once on the 5-class scale (1 very simple … 5 very complex; criteria in
the README) and pick the pairing once. Stamp both into `meta.name` as
`c<class>-<pairing>-<slug>` (`c3-fable-opus-fix-retry-logic`); a running workflow must
always show what it was sized for. Every role takes its combo from that single row of
the pairing's map: the role picks the column, the class picks the row. Never mix rows,
never pick a combo ad hoc for one agent, never mix pairings inside a workflow. Switch
the pairing only on the user's word or a real availability limit, and say so.

Six roles, one column each: reviewer-debugger (strongest slot), plan author/fixer,
code/test fixer, code/test author, fact researcher, test/script executor (cheapest).

### Every `agent()` call

- `model` and `effort` set explicitly in opts, never inherited; `agentType` launches
  (`claude-code-guide`) too. Full ids come from the session map (`claude-opus-5[1m]`).
- Label starts with the `<mod>-<eff>-` prefix: `fab-hi-review-plan`, `ops-lo-fast-tests`
  (`fab`, `ops`, `son`, `hai`; `lo`, `me`, `hi`, `xh`, `mx`). The UI shows the model
  but not the effort; the prefix is the only place the effort is visible.
- The prompt ends with two lines chosen by the main session from the skill-routing map
  (`skill-routing.md` next to this skill for the bundled CLI skills, plus the per-machine
  map `~/.claude/memory-user/skill-routing.md` when present; 0-3 skills by role and step): "Load these
  skills with the Skill tool before starting, in this order: <names>. Follow each loaded
  skill's instructions in place of your default approach." or "No skills needed for this
  step."; then "If you hit work outside this list that a clearly matching skill in your
  available-skills list covers, load it first, but never load claude-api." Workflow
  agents never open the skill list on their own (measured 2026-08-27).
- Author, fixer and executor prompts carry: "On a permission denial stop at once and
  return BLOCKED: <denied action>."
- Return format named in the last line: facts, a diff summary, or PASS/FAIL with the
  decisive lines, with a word limit; no file contents, no raw logs.

Check a saved script before every launch: explicit model+effort, `<mod>-<eff>-` label prefixes, the
two skill lines, class and pairing in `meta.name`; fix first, then launch. After editing
a saved script launch it by `scriptPath`, not `name` (name resolution can serve a stale
copy). Load `workflow-authoring` in the main session before writing a script.

### Stages and quality loops (workflow-only work)

Every stage that authors an artifact (plan, code, tests, scenarios, design document) is
paired with an independent review by the reviewer-debugger, a separate agent. Wire it as
author → reviewer-debugger (→ fast tests by the test/script executor when the artifact
is code) → fixer, 1-3 cycles: exit as soon as the verdict is clean and tests are green;
after the third cycle stop and report what is unresolved. A full task chains:

1. **Plan**: plan author/fixer writes, reviewer-debugger reviews, plan author/fixer
   applies; 1-3 cycles. Worth it for large tasks even when well understood.
2. **Red tests** (when acceptance criteria exist): code/test author writes tests first;
   the review checks the test code and that every acceptance criterion maps to a test;
   code/test fixer applies; 1-3 cycles.
3. **Implementation**: code/test author writes, reviewer-debugger reviews, test/script
   executor runs the fast tests, code/test fixer applies; 1-3 cycles.
4. **Technical stages** (preparation, merge, commit, conflict resolution): test/script
   executor, no review loop.

Parallelize when it pays: before launching, decide whether a stage splits into 3-5
agents of the same role over independent files, directions or work items. Overlapping
code areas get `isolation: 'worktree'`; disjoint files share the tree. Parallel agents
still take the same map row. Prefer `pipeline()` over barriers.

Blocks: the script checks every stage result (`null` or a `BLOCKED` prefix counts as
blocked) and ends the workflow at once with a report; review and fix never run against
unchanged files. Relaunch only after the cause is addressed. Resume with
`resumeFromRunId` after a pause or a script edit; read `journal.jsonl` in the transcript
dir before diagnosing an empty result.

Land stages (commit, push, MR update) are self-contained: repo path, branch, expected
changed files, a one-to-two-line summary of the change interpolated from earlier stage
results. The agent runs `git status` and `git diff --stat` first and returns
`BLOCKED: unexpected working tree` on a mismatch. Push only when the task grants it.

## Long waits and polling

Every fork turn re-reads the whole parent prefix at cache-read price (pipeline test 1:
63% of $17.9 was prefix re-reads over 197 turns), so a 500K prefix polled 18 times is 9M
read tokens for nothing; and the API cache lookback is 20 blocks, so a fork with many
tool blocks is a risk we have not measured. Therefore a fork never polls or waits: no
poll loops, no waiting on tmux, CI, deploys or remote state. Escalation ladder, fixed:
a fork may make at most 3 short checks (each one Bash call of ≤ 120 s, `sleep` inside
allowed); if the condition still does not hold after the third check, it stops and
returns the `WAIT:` line below, and the main session takes over the wait. The main
session's prompts must not ask a fork for anything longer ("wait until X", "repeat once
if not up"): the fork starts the job, checks up to 3 times, returns.

Default for a long wait — detached process plus a main-session wake. The fork starts
the long job detached, so Claude Code does not track it and its end cannot re-invoke the
fork: `nohup <job> > <log> 2>&1 &` (no `setsid`: it does not exist on macOS; on Linux
`nohup setsid …` is fine), or a shell loop that exits when the condition holds, with a
done-file at the end (`touch <dir>/done`), and returns at once with the paths. The main session waits on the file itself: a `Monitor`, or one `run_in_background`
Bash `until [ -f <done> ]; do sleep 60; done`. The wake turn is an ordinary cached turn.

A `waiter` only when the wait needs judgment mid-way (answering permission prompts in a
tmux pane, branching on what appears, extracting facts from a changing transcript): a
fresh small-context agent pinned to sonnet with tools Bash and Read only
(`agents/waiter.md` in this plugin). The MAIN session launches it as a one-agent
`Workflow`, never a fork does: a fork that finds such a wait ahead ends its turn with one line
`WAIT: <condition> | poll: <command shape> | dialogs: <rules> | budget: <N min>` and the
main session launches the waiter from it (or arms a Monitor when no judgment is needed).
Launch template:

```
Workflow(script: `export const meta = { name: 'c1-<pairing>-wait-<job>', description: 'waiter: <job>', phases: [{ title: 'Wait' }] }
phase('Wait')
return await agent("Wait until <condition>. Poll with <command shape> every ~120 s, each call under 150 s, total budget <N> minutes. Dialog rules: <what may be approved, what not>. Return <facts wanted>, at most <N> words. Never print secrets.",
  { agentType: 'session:waiter', model: 'sonnet', effort: 'low', label: 'son-lo-wait-<job>', phase: 'Wait' })`)
```
(`agentType: 'waiter'` for a local copy in `~/.claude/agents/`.)

## Launch forms

Exactly two. (1) `Agent` with `subagent_type: "fork"` for forks; nothing else goes
through `Agent`. (2) `Workflow` for every cold agent: a single cold agent (waiter,
critic, decision reviewer, cold researcher, downscale or upscale agent, codex-proxy) is a
one-agent workflow with explicit `agentType`, `model`, `effort` and the
`<mod>-<eff>-<job>` label; N independent cold agents go into ONE workflow (`parallel`
or `pipeline`), never N launches. No plain subagents. Measured 2026-09-06 with the same
waiter agent both ways: agent cost identical ($0.136 per five agents); each separate
completion notification costs the main session a full prefix re-read (≈ $0.13 on a 285K
fable prefix); notifications that land together are batched.

A waiter's mandate is narrow and the prompt states it as such: it babysits our own test
sessions, answers their questions, confirms routine work inside the test's own
directory, and refuses and reports anything outside it (other paths, deletions, pushes,
settings or plugin changes). It never acts as a general approver for another session.

The main session may start async work itself with `run_in_background` and be woken by
the completion: its turns are paid for anyway and the ping cron keeps its prefix warm.
Inside a fork the same call is forbidden: the completion would wake the fork.

## Launching a codex model

Codex models (luna, terra, sol, astra) run through the `codex-proxy` agent of this
plugin (agent, wrapper and style file ship in it; no `~/.claude/agents` copy needed) as a
one-agent `Workflow`: `agentType: 'session:codex-proxy', model: 'haiku', effort: 'medium'`, label
`<lun|ter|sol|atr>-<eff>-<job>`. The prompt is the header block only: `CODEX TARGET`,
`CODEX CWD`, `CODEX PROMPT FILE`, `CODEX OUTPUT FILE`. The MAIN session writes the prompt
file itself with one Write, at most 30 lines of bullets: the style line (caveman ultra,
plain English only), the role, the inputs by absolute path (never pasted), the
acceptance criteria, the commands to run, the required last lines (the 5-field status).
The main session consumes only the shim's `LAST LINE`; the output file is read by its
next consumer by path, never relayed by a fork. A failure → one more codex run with a
failure packet of at most 10 lines written by the main session, never a fork. No forks
around a codex call at all: no prompt-writing fork, no output-reading fork.

Roles: `luna-high` = cheap executor and repository researcher (repository and files
only, no MCP); `terra-high` = stronger executor; `sol-<me|hi>` and `astra-<me|hi>` =
heavy generation or critique of one document within the 5 (medium) / 3 (high)
tool-call budget, never code review. Codex quota at 0%: executors → `luna-reserve-high`,
heavy jobs → the Claude agent of the same role. Context: codex reads `AGENTS.md`, not
`CLAUDE.md`; where the project has a sync script, `AGENTS.md` is generated from the
Claude sources before the run.

## Forbidden in every session

- No plain subagents at all (`general-purpose`, `Explore`, custom agent types through
  `Agent`), no named teammates. `Agent` only with `subagent_type: "fork"`; `Workflow`
  for every cold agent (downscale, upscale, waiter, codex-proxy), one class and one
  pairing per workflow.
- No inline job of 3+ tool calls in the main session (measured 2026-09-06: an inline
  session wrote 19 Bash calls and produced the smallest test suite).
- No polling loops, waits or `run_in_background` in a fork; a fork starts long jobs
  detached with a done-file, the main session waits (Monitor or its own background
  Bash), a waiter only when the wait needs judgment.
- No `agent()` without explicit model and effort, no label without the `<mod>-<eff>-` prefix, no prompt
  without the two skill lines, no `meta.name` without class and pairing.
- No fourth review cycle: stop and report.
- No `/model`, `/effort`, plugin changes or `/compact` in the middle of a task.
- Do not switch mode on your own; if the task outgrows the base, say so to the user.

## Reference

Cache facts, prices, class criteria, the selection map and the role/stage tables:
`plugins/session/README.md` (sections "Mode 1 — Workflow" and "Roles, selection map and
stages").
