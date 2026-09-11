# Context trim: closure note (2026-09-11)

Commit `bf532af`, session plugin 0.10.0 installed fresh from the local marketplace.

## Measured

| state | sonnet start, first request |
|---|---|
| baseline, empty project | 56.9K |
| after user-level deny (8 tools) and skillOverrides (14 skills) | about 52K (derived, not measured alone) |
| plus per-project deny of Artifact and DesignSync (M1, before this change) | 33.0K |
| after this change (14 agents, trimmed descriptions) | 32.9K, accept band 32.5-34.0K |

Custom agents: 9 agents 1.6K before, 14 agents 1.4K after.
Hook tests: `tests/session-modes-hook.sh` 72/72 PASS.
Smoke via Workflow: `session:web-researcher` reported `WebFetch, WebSearch, Read, Write`; `session:code-reviewer` reported `Read, Bash`.

## Delivered

- Nine descriptions trimmed to 40-101 tokens; dropped facts moved into the agent bodies.
- Six new agents: artifact-publisher, artifact-designer, web-researcher, code-reviewer, simplifier, security-reviewer; minimum tool sets; `skills:` preload kept but unverified, rules inlined in the bodies.
- `session:reset-counter` hidden from the model.
- Base paragraph naming the new agents; README table, 0.10.0 log line, artifact deny toggle with the hot-reload measurement.
- User config (outside the repo): 25 project dirs got `.claude/settings.local.json` denying Artifact and DesignSync; user-level deny of 8 tools and 14 skills off; duplicate user agents and open-file moved out; empty CLAUDE.md imports removed.

## Open

- Closure review (opus-medium): closed with notes. The codex-proxy description/frontmatter contradiction it cites was fixed before the commit (description no longer names a model). Smoke test covered web-researcher and code-reviewer only; simplifier and security-reviewer not exercised.
- User config backup copied to `~/.claude/backups/2026-09-11-context-trim/` (settings.json, CLAUDE.md, explore.md, waiter.md, open-file).

- `skills:` preload for a skill switched off by skillOverrides: not verified (three attempts, sonnet never spawned the agent).
- Two artifact agents untested end to end (Artifact denied in every project; lift the local deny in one folder to use them).
- Code review low items accepted: stage-critic 61/60, codex-proxy 101/100 tokens.
- Not pushed.
