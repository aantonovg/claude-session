# claude-session

A Claude Code plugin marketplace with one plugin, `session`: modes of the main session as
user-invocable skills.

```
claude plugin marketplace add aantonovg/claude-session
claude plugin install session@claude-session
```

Then, at the start of a session: `/session:forks` (default) or `/session:pipeline` (forks plus a
staged pipeline for one task: ledger, decision, verification, implementation, final review,
report); add `/session:pipeline-codex [mode]` after it to run pipeline stages on codex
models (luna, terra as executors; sol, astra as reviewers, alone or paired with Claude).
Unstable experiment: the worker pool (`/session:pool-workflow-unstable`,
`/session:pool-unstable`, `/session:pool-stop-unstable`). The model may call
`session:ask` on its own to ask you without blocking.

The skills `forks` and `pipeline` read the per-account selection map from
`~/.claude/session-map.md`; copy `plugins/session/session-map.example.md` there and
edit the model ids and the table for your account.

Reference (modes, cache facts, compact prices, measurements): `plugins/session/README.md`.
