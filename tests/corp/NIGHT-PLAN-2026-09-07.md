# Night plan 2026-09-07: three corporate pipeline tests

Agreed with the user on 2026-09-06 23:40. Alarm: one-shot cron `a11cb8d3` fires at 00:05 local with the prompt "LAUNCH CORP TESTS".

## What to launch (at 00:05)

Three tmux main sessions on the Mac, corporate harness `bw` (personal subscription, never the VM), model `claude-fable-5-1[1m]`, effort low, session plugin 0.8.4 (installed cache; caveman plugin disabled). Per session, in order: `/session:base` (wait `Base on`), `/session:pipeline full` (wait pipeline line), `/session:codex +astra` (wait `Codex`), then the task prompt file.

| run | task |
|---|---|
| corp-22401 | B2CT-22401 |
| corp-22402 | B2CT-22402 |
| corp-22116 | B2CT-22116 |

Launcher: `tests/corp/launch.sh <run-name> <jira-key> [model] [effort]` (written by the pre-check fork; prompt files `tests/corp/prompt-<key>.md`). Watcher: done-file after 8 idle minutes in every pane, then the main session waits on the file with a background `until` loop.

Prompt content: take the task from its current Jira state to a Draft MR ready for colleagues' review; real repos, real GitLab, no sandbox; decisions for the user go through `session:ask` (Plannotator, asynchronous), continue on the recommended default meanwhile, act on annotations when they arrive; finish with the MR link and a 5-line summary.

## Pre-check (fork `fab-lo-corp-precheck`, running at 23:45)

Facts to use: how `bw` starts (cwd, flags, model/effort), whether the session plugin is visible, Jira and GitLab MCP answer for the three keys, `session:ask` present, smoke session on sonnet through the three skills. If the pre-check reports a blocker, fix it before 00:05 or tell the user; do not launch on a broken harness.

## After the runs

1. Kill the tmux sessions after reading; `tmux ls` empty.
2. Cost pass with `tests/demo-game/batch-cost.py` adapted to the corporate run transcripts (`~/.claude/projects/<encoded cwd>/`) and pipeline ledgers: per test, per model-effort row, launches by type (forks, cold agents by agent type, codex calls, haiku shims), tokens and $ split cw : out : cr, codex ledger rows from `~/.codex/proxy-usage.jsonl`, shim cost separately.
3. Quality: MR links (Draft state), pipeline ledger completeness, rule checks (base line, prefixes, Workflow use, upscale points fired, dual review happened), escalations through session:ask and what was asked.
4. Russian report `~/projects/claude-settings/docs/review/corp-pipeline-astra-2026-09-07-ru.md`, opened in Plannotator (background), committed with the results on the user's word.

## Standing rules

Ping cron `eab05b95` (30 min): reply `pong`. Never `claude -p`. Kill idle tmux sessions after tests. Skill text: strategy only. Never print secrets. Commits without Co-Authored-By. Chat: English body, `---`, Russian recap, caveman ultra.
