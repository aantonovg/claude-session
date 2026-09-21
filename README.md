# claude-session

A Claude Code plugin marketplace with one plugin, `session`: modes of the main session as
user-invocable skills.

```
claude plugin marketplace add aantonovg/claude-session
claude plugin install session@claude-session
```

The session base (launch forms, classes and slots, cache and wait rules, verification
first) is injected into every session by the plugin's `SessionStart` hook; nothing to
invoke. Then, when the session has a task: `/session:process <type> <depth>` — one page of
stages, gates, task files and user points for a code change, an MR review, an
investigation, a document or an infrastructure change, at depth `lite`, `std` or `full`.
Add `/session:codex [mode]` to run a stage on codex models (luna, terra as executors; sol,
astra as heavy reviewers). The model may call `session:ask` on its own to ask you without
blocking.

The work itself runs in named workflows the session launches by name: `session:role` (one
role, one agent), `session:chain` (the evidence review chain), `session:make` (spec,
scenarios, tests, code, executor, fixer) and `session:probe` (parallel research, critique,
synthesis). Each arrives as one SessionStart contract line, so a launch never reads a
script body.

Reference (modes, cache facts, compact prices, measurements): `plugins/session/README.md`.
