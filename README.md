# claude-session

A Claude Code plugin marketplace with one plugin, `session`: rules of the main session as
user-invocable skills.

```
claude plugin marketplace add aantonovg/claude-session
claude plugin install session@claude-session
```

The session base (launch forms, classes and slots, cache and wait rules, verification
first) is the skill you invoke as the first prompt of a session, and again after `/compact`:
`/session:base [no-sonnet] [no-opus] [no-fable] [c1..c5]`. Then, when the session has a task: `/session:process <type> <depth>` — one page of
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

## The 0.16 set

0.16.0 rebuilds the plugin from zero: the class `c1`-`c5` plus its submodes is the only source of a
model and an effort. `tests/rebuild/all.sh` runs the static oracles of the rebuild, and
`tests/workflows/usage-test.sh` checks the contract collector, the SessionStart wiring, the base
sentences and the READMEs on every commit; `tests/rebuild/release-gate.sh` runs once, right after
the release commit, and checks what holds only there (both version files at 0.16.0, the version log
line, the commit subject, a clean tree). Details: the section
"The 0.16 set" of `plugins/session/README.md`.

Reference (classes, cache facts, compact prices, measurements): `plugins/session/README.md`.
