# claude-session

A Claude Code plugin marketplace with one plugin, `session`: rules of the main session as
user-invocable skills.

```
claude plugin marketplace add aantonovg/claude-session
claude plugin install session@claude-session
```

The session base is the skill you invoke as the first prompt of a session, and again after
`/compact`: `/session:base [no-sonnet] [no-opus] [no-fable] [c1..c5]`. It is fork-first: the main
session keeps the user's intent, the constraints, the decisions and the paths of results; every job
of 2+ tool calls runs in a conversation fork on the main session's own model; a fresh helper (an
index, facts, a run, a counterexample, a narrow check, a replicated change) runs only for one
concrete result that improves the fork's decision or replaces its costlier work, writes the details
to a file and returns three lines. Add `/session:codex [mode]` to send helper jobs of named kinds
to the codex CLI. The model may call `session:ask` on its own to ask you without blocking.

Helper launches go through two named workflows, `session:helper` (one helper, one contract, one
result directory) and `session:batch` (one helper over many items, one status row per item), each
arriving as one SessionStart contract line, so a launch never reads a script body.

## The 0.18 set

0.18.0 rebuilds the routing from the fork-first architecture document
(`reviews/claude_fork_first_architecture_full_dialogue.md`); the class `c1`-`c5` plus its submodes
stays the only source of a model and an effort, and the keep-warm ping monitors stay as they were.
`tests/plugin/all.sh` runs the static oracles of the set, `tests/workflows/usage-test.sh` checks the
contract collector, `tests/plugin/release-gate.sh` runs once, right after the release commit.
0.18.1 adds the agent gate (only a fork goes through `Agent`; every helper goes through `session:helper`
or `session:batch`) and the fixes of `docs/plans/2026-09-23-fork-first-review.md`.
Details: `plugins/session/README.md`.
