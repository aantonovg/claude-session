# Session base, part 3 of 3

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

Codex models (luna, terra, sol, astra) run through the `codex-proxy` agent as a
one-agent `Workflow`: `agentType: 'codex-proxy', model: 'haiku', effort: 'medium'`, label
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
