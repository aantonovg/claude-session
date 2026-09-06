# claude-session

A Claude Code plugin marketplace with one plugin, `session`: modes of the main session as
user-invocable skills.

```
claude plugin marketplace add aantonovg/claude-session
claude plugin install session@claude-session
```

The session base (forks, launch forms, cache and wait rules, models, efforts, roles) is
injected into every session by the plugin's `SessionStart` hook; nothing to invoke. Then,
when the session has a task: `/session:pipeline` (a staged pipeline for one task: ledger,
decision, verification, implementation, closure check, report) or `/session:review` (a
verification-first review of someone else's MR); add `/session:codex [mode]` after either
to run stages on codex models (luna, terra as executors; sol, astra as heavy reviewers).
Unstable experiment: the worker pool (`/session:pool-workflow-unstable`,
`/session:pool-unstable`, `/session:pool-stop-unstable`). The model may call
`session:ask` on its own to ask you without blocking.

The base and the skills `pipeline` and `review` read the per-account selection map from
`~/.claude/session-map.md`; copy `plugins/session/session-map.example.md` there and
edit the model ids and the table for your account.

Reference (modes, cache facts, compact prices, measurements): `plugins/session/README.md`.
