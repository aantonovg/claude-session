---
name: forks
description: Session mode 2, main session plus fork subagents. The main session keeps its warm context and hands every job with 3+ tool calls or 3K+ tokens of input to a fork (subagent_type fork) that inherits the cached prefix; no plain subagents, no teammates, no Workflow. Invoke at the start of a session for one task with parallel angles on one model.
disable-model-invocation: true
---

# Mode: forks

One main session plus fork subagents. A fork inherits the whole conversation and the
cached prefix, so spawning one is nearly free; its tool calls stay out of the main
context, which is what keeps the main session small and warm. Forks run on the main
session's model and effort, there is no mixing.

## Start (do this now)

1. First tool call, before any reply and even when no task has been given yet:
   `CronCreate` with `cron: "*/30 * * * *"` (this exact expression), `prompt: "ping"`,
   `recurring: true`. Reply to every `ping` with one word.
2. Model and effort are already chosen; do not change them for the rest of the session.
3. Reply with one line: "Forks mode on, ping cron <id>; forks only." The cron id must
   be in that line.

If the skill is invoked with the argument `pool` (`/session:forks pool`), skip step 1
entirely: never create a cron, the pool daemon keeps the session warm; the reply line is then
"Forks mode on (pool); forks only."

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

## Fork prompt template

The first line sets the role, the last line the return format:

```
You are the <role>: <one-line goal>.            # reviewer-debugger, code/test author, ...
<the task, the files, the acceptance criteria>
Return only <facts | a diff summary | PASS/FAIL with the decisive lines>, at most <N> words.
Do not paste file contents or raw logs. On a permission denial stop and return BLOCKED: <action>.
Load these skills with the Skill tool before starting: <names>.   # or: No skills needed for this step.
```

Review and fix are different forks: the fork that wrote code never reviews it, and the
fork that reviewed never applies its own findings. Stages and roles come from the plugin
README (plan → review → red tests → implementation → review → fast tests → fix, 1-3
cycles each); pick the 0-3 skills per stage from the skill-routing map.

In plan mode forks must avoid Bash commands with `$var`, `$(…)` or loops (they trigger a
permission prompt there); outside plan mode any Bash is fine.

A fork's own context lives in the 5-minute cache and the clock runs from the start of
each request, so a fork never waits synchronously for long: every Bash call, MCP call
or poll loop inside a fork stays under about 3 minutes; longer work runs with
`run_in_background` and is polled in short calls, or the wait moves to the main
session. A cron created by a fork fires in the main session, not in the fork, so it
cannot keep a fork warm. A fork must never end its turn with a `run_in_background`
job still running: the completion re-invokes the fork, but that re-invocation is a
full cache miss (measured: 409K rewritten, ≈ $5 on fable). Background jobs inside a
fork are polled with short foreground calls until they finish, then the fork returns. What expires is only the fork's own suffix; the parent prefix
it inherited stays in the parent's 1-hour cache.

## Forbidden in this mode

- No plain subagents (`general-purpose`, `Explore`, custom agent types), no named
  teammates, no `Workflow`. Only `subagent_type: "fork"`.
- No `/model`, `/effort`, plugin changes or `/compact` in the middle of a task.
- Do not switch mode on your own; if the task outgrows forks, say so to the user.

## Reference

Cache facts, prices and the role/stage tables: `plugins/session/README.md` in the
claude-settings repo.
