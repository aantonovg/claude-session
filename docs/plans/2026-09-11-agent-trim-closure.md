# Agent trim: closure note (2026-09-11)

Commit `e94396d`, session plugin 0.10.2 installed fresh from the local marketplace.

## Measured (sonnet, first request of each agent, empty project with Artifact denied)

| agent | before | after |
|---|---|---|
| codex-proxy | 14775 | 10376 |
| artifact-designer | 9713 | 5572 |
| artifact-publisher | 9657 | 5530 |
| web-researcher | 6797 | 5928 |
| stage-researcher | 9898 | 9504 |
| stage-author | 10066 | 10029 |
| waiter | 9442 | 9387 |
| stage-reviewer | 5510 | 5474 |
| stage-executor, stage-critic, code-reviewer, simplifier, security-reviewer | unchanged within 10 tokens | |

Fixed per agent regardless of tools: harness blocks about 0.3K, CLAUDE.md plus skill-routing echo about 1.5K, environment attachments about 0.3K, tool wrapper about 1.5K when any tool is present. Bash costs 4.2K wherever kept. Grep and Glob cost 0 under auto mode. `skills:` preload of a skill switched off by skillOverrides is skipped silently and costs 0.

## Delivered

- Tool lists cut to the role minimum (see the 0.10.2 README rows); artifact agents lost Bash and return `BLOCKED: Bash` for binary assets.
- codex-proxy body 15779 to 6709 chars, every contract line kept; permission-set rationale moved to the README.
- Dead `skills:` lines removed; only code-reviewer keeps `skills: code-review`.
- Fork and workflow prompt templates read SKILL.md files by resolved path (newest installed version) instead of the Skill tool; BLOCKED on a missing file.
- Plan critique (3 high, fixed), code review (2 high, fixed), measurements log under docs/plans/reviews.
- user-prefs plugin: Explore override removed (6.12.6, commits in claude-settings).

## Verification

- `tests/session-modes-hook.sh`: 72/72 pass (run after the 0.10.2 commit).
- Launch smoke, run 2 (sonnet, Workflow, prompt "Reply with the single word OK"): codex-proxy replied `OK`, web-researcher replied `OK`, artifact-publisher replied `OK` (newest agent JSONL per agent under the measurement dir, mtimes 23:30-23:31).
- Code review re-run after the fixes: see docs/plans/reviews/2026-09-11-agent-trim-code-review-2.md.

## Open

- Second measurement run reused the first run's output dir; corrected numbers were taken from the newest JSONL per agent, no third run.
- The skill-by-path rule is untested end to end from a real fork launch.
- Artifact agents still untested end to end (Artifact denied in every project).
- Next lever for every agent: a shorter `~/.claude/CLAUDE.md` and skill-routing.md, echoed into each agent at about 1.5K.
- Not pushed.
