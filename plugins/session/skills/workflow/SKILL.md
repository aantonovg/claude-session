---
name: workflow
description: Session mode 1, the original flow. The main session does no work itself, every job runs as a Workflow script of cold agents (one class and one pairing per workflow, model and effort explicit on every agent, author → review → fix loops). No forks, no plain subagents, no teammates. Invoke at session start; the baseline the other modes are measured against.
disable-model-invocation: true
---

# Mode: workflow

The flow as it ran in August 2026 (user-prefs 6.5-6.7): one warm main session that
plans, launches `Workflow` scripts, verifies their results and talks to the user. Every
piece of substantive work is a workflow agent. This mode is the cost and quality baseline
for `session:forks` and `session:pipeline`.

## Start (do this now)

1. First tool call: `CronCreate` with `cron: "*/30 * * * *"`, `prompt: "ping"`,
   `recurring: true`. Reply to every `ping` with one word. If a `ping` cron already
   exists in this session, reuse it.
2. Read `~/.claude/session-map.md` (fallback: `session-map.example.md` in the plugin,
   fable-opus only). Pick the pairing row the user named, else the default pairing of
   the account.
3. Reply with one line: "Workflow mode on, ping cron <id>; workflows only."

## The main session does no work itself

Inline tool use is limited to orchestration: a `git status` or hash check, reading one
result file, TaskList and memory bookkeeping, the plan file, questions to the user.
Editing files, running commands, builds or tests, calling external systems, reading
many files: a workflow job, even when it looks like a two-minute task. Quick recon is a
minimal workflow with one collector agent on the class-1 fact-researcher combo; broader
recon adds direction-scoped collectors plus one synthesis agent on the class-1 plan
author/fixer combo. Questions about Claude Code or the API go to `claude-code-guide`
launched as a workflow agent with `agentType`, never to the `claude-api` skill.

## One class and one pairing per workflow

Assess the task once on the 5-class scale (1 very simple … 5 very complex; criteria in
the README) and pick the pairing once. Stamp both into `meta.name` as
`c<class>-<pairing>-<slug>` (`c3-fable-opus-fix-retry-logic`); a running workflow must
always show what it was sized for. Every role takes its combo from that single row of
the pairing's map: the role picks the column, the class picks the row. Never mix rows,
never pick a combo ad hoc for one agent, never mix pairings inside a workflow. Switch
the pairing only on the user's word or a real availability limit, and say so.

Six roles, one column each: reviewer-debugger (strongest slot), plan author/fixer,
code/test fixer, code/test author, fact researcher, test/script executor (cheapest).

## Every `agent()` call

- `model` and `effort` set explicitly in opts, never inherited; `agentType` launches
  (`claude-code-guide`) too. Full ids come from the session map (`claude-opus-5[1m]`).
- Label starts with the `<mod>-<eff>-` prefix: `fab-hi-review-plan`, `ops-lo-fast-tests`
  (`fab`, `ops`, `son`, `hai`; `lo`, `me`, `hi`, `xh`, `mx`). The UI shows the model
  but not the effort; the prefix is the only place the effort is visible.
- The prompt ends with two lines chosen by the main session from the skill-routing map
  (`~/.claude/memory-user/skill-routing.md`, 0-3 skills by role and step): "Load these
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

## Stages and quality loops

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

## Questions to the user

Through `session:ask` (or in chat when the user is present): grouped, reversible default
chosen, work continuing on it.

## Forbidden in this mode

- No forks (`subagent_type: "fork"`), no plain subagents via the `Agent` tool, no
  teammates, no pool. Only `Workflow` with `agent()` stages (`agentType` allowed for
  `claude-code-guide` and the plugin's stage agents).
- No substantive inline work by the main session (edits, test runs, multi-file reads).
- Heavy agent on request (forks skill, "Heavy agent on request"): on the user's explicit
  word a single-agent workflow does a point review or generation with the named model and
  effort (sol / astra via `codex-proxy`), budget 5 tool calls at medium, 3 at high or
  xhigh; never on the session's own initiative.
- No `agent()` without explicit model and effort, no label without the `<mod>-<eff>-` prefix, no prompt
  without the two skill lines, no `meta.name` without class and pairing.
- No fourth review cycle: stop and report.
- No `/model`, `/effort`, plugin changes or `/compact` in the middle of a task.
- Do not switch mode on your own; if the task outgrows workflows, say so to the user.

## Reference

Class criteria, the selection map and the stage table: `plugins/session/README.md`,
sections "Mode 1 — Workflow" and "Roles, selection map and stages". Cache facts and
prices: same file.
