---
name: workflow
description: Session mode 7, plain workflows with lean stage agents. Every Workflow stage is a fresh agent of type stage-author, stage-reviewer, stage-executor or stage-researcher (reduced tool set, measured start 12K instead of 35K), with model and effort from the session map; review cycles stop at the convergence gate. Forks only for main-session recon; no teammates, no pool. Invoke at the start of a session for multi-stage work with review cycles and mixed models.
disable-model-invocation: true
---

# Mode: workflow

The main session plans and launches `Workflow` scripts; every stage is a fresh lean agent.
A lean agent carries about 12K tokens at start instead of 35K, because it gets only the
tools its role needs. A stage is cheaper than a warm pool worker when it takes more than
about 12 turns (the pool trades one 40K write for larger reads on every turn), so this is
the default mode for real work.

## Start (do this now)

1. First tool call, before any reply: `CronCreate` with `cron: "*/30 * * * *"`, `prompt:
   "ping"`, `recurring: true`. Reply to every `ping` with one word.
2. Read `~/.claude/session-map.md`, take the row of the task class in the default pairing
   (or the pairing the user named); this gives model and effort per role.
3. Reply with one line: "Workflow mode on, ping cron <id>; lean stage agents." The cron id
   must be in that line.

## Agents per role

| role in the map | agentType |
|---|---|
| plan author/fixer, code/test author, code/test fixer | `stage-author` |
| reviewer-debugger | `stage-reviewer` |
| test/script executor | `stage-executor` |
| fact researcher | `stage-researcher` |

Every `agent()` call passes `agentType`, `model` and `effort` explicitly:

```
agent(prompt, { agentType: 'stage-reviewer', model: 'opus', effort: 'medium', label, phase })
```

## Stages

Plan → plan review → plan fix → implement → (review → fix → check) × 1-3 cycles. Recon
before the script runs is done by forks of the main session (MCP reads always in forks).
`meta.name` is `c<class>-<pairing>-<slug>`.

- **Convergence gate.** A review stage ends with `DONE severity=<none|low|medium|high>`.
  When the severity is below medium, skip the fix and check stages of that cycle and end the
  cycles. `BLOCKED` on any stage stops the script.
- **Tool-output caps.** Before each cycle the script's author stage tags the tree
  (`git tag stage-<n>`); reviewers get `git diff stage-<n-1>..HEAD`, not whole files;
  checkers return PASS/FAIL lines plus the last 20 lines of a failure; test runners in quiet
  mode.
- **Prompt shape.** Role line first, then the task, acceptance and the exact commands, then
  the return format; deliverables go into project files, the return is at most 5 lines with
  `DONE` or `BLOCKED: <reason>` last.
- **Resume.** Rerun with `scriptPath` + `resumeFromRunId`; finished stages replay from the
  journal.

## Forbidden in this mode

- No teammates, no plain subagents (`general-purpose`, `Explore`), no pool workers.
- No `/model`, `/effort`, plugin changes or `/compact` in the middle of a task.
- Do not switch mode on your own; if the task outgrows workflows, say so to the user.

## Reference

Cache facts, prices, the role tables and the benchmark: `plugins/session/README.md`.
