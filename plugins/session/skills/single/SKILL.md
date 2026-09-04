---
name: single
description: Session mode 1, one session and nothing else. The main session does all the work itself, spawns no agents of any kind, and keeps its cache warm with a 30-minute ping cron. Invoke at the start of a session for chat, analysis, small and medium edits.
disable-model-invocation: true
---

# Mode: single

One session, no agents. Every turn is a cache read plus the new tokens, the cheapest
mode per unit of work. Fits conversation, analysis, small and medium edits, anything
under a few hundred tool calls.

## Start (do this now)

1. First tool call, before any reply and even when no task has been given yet:
   `CronCreate` with `cron: "*/30 * * * *"` (this exact expression), `prompt: "ping"`,
   `recurring: true`. Reply to every `ping` with one word.
2. Model and effort are already chosen; do not change them for the rest of the session.
3. Reply with one line: "Single mode on, ping cron <id>; no agents, no workflow." The
   cron id must be in that line.

## Rules of this mode

- Do all the work yourself: reading, editing, running commands, reviewing.
- Do not spawn anything: no `Agent` tool (no forks, no plain subagents, no named
  teammates), no `Workflow`, no `Skill` that launches agents. If a task looks too big for
  one context, say so and let the user switch mode; do not switch on your own.
- Big inputs in chunks: read long files by ranges, run searches with tight filters,
  never dump a whole transcript or log into the context.
- Review is a separate pass, always, without waiting for the user. After the code is
  written and the tests pass, write the line "Implementation done, reviewing next." and
  continue in the same turn: re-read every changed file from disk, list findings (or
  "no findings"), fix them, run the tests again. Only then report completion. Stop
  after three review cycles and report what is open.
- Follow the stages of a task from the plugin README (plan → review → tests →
  implementation → review → fix), all performed by this session.
- No `/model`, `/effort`, plugin changes or `/compact` in the middle of a task. When the
  task is done or the context is clearly degraded, the user decides on a compact.

## Prompt reminders

- The plugin README (`plugins/session/README.md` in the claude-settings repo) holds the
  cache facts and prices behind these rules; read it only when the rules need changing.
