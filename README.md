# claude-session

A Claude Code plugin marketplace with one plugin, `session`: modes of the main session as
user-invocable skills.

```
claude plugin marketplace add aantonovg/claude-session
claude plugin install session@claude-session
```

Then, at the start of a session: `/session:single`, `/session:forks`, `/session:team`,
`/session:team-forks`; to park a team: `/session:team-compact`.

The skills `team` and `team-forks` read the per-account selection map from
`~/.claude/session-map.md`; copy `plugins/session/session-map.example.md` there and
edit the model ids and the table for your account.

Reference (modes, cache facts, compact prices, scores): `plugins/session/README.md`.
