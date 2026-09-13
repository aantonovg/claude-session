# Measurement drivers (2026-09-11)

Interactive tmux sessions that measure the start context of a main session or of every custom agent, and check which agent a main session launches under the base. Never `claude -p` (billed at about 3.3x on the subscription).

- `rem-run.sh`: one sonnet session in a project dir, sends `hi`, keeps the JSONL; the pattern every other driver copies.
- `ctx3-run.sh`: one session per built-in tool with every other tool denied, to price each tool schema.
- `agentctx-run.sh`: launches every custom agent once through Workflow and copies each subagent JSONL for a per-agent breakdown.
- `basecls-run.sh` + `basecls-parse.py`: one fresh tmux session per scenario run, verdicts over every assistant record of the turn. Env: `MODEL` (sonnet|opus|fable), `EFFORT`, `CWD` (default `~/projects/base-test-15-<MODEL>`), `OUT` (default `~/.claude/jobs/b6440034/tmp/bt15-<MODEL>-<EFFORT>`), `REPEAT`, `IDS`. Scenarios T0-T8 (`basecls-scenarios-0.14.txt`, base rules, Russian prompts) and S1-S9 (`basecls-scenarios-0.15.txt`, one per new user asset: transcripts-jsonl, tmux-sessions, shell-gotchas, workflow-reliability, harness-cost, skill-author, memory-gc, test-session, plugin-release). A `cwd:` line in the scenario file overrides the test dir (S9 runs in this repo; no cleaning outside `base-test-*`). Artifacts: `result.log`, `<ID>-r<n>.jsonl`, `.pane.txt`, `.files/`, `done`.

0.15 matrix (2026-09-13), run detached with `nohup`, one driver per model, sequential inside:

| model | effort | ids | repeat | sessions |
|---|---|---|---|---|
| sonnet | medium | S1-S9 | 3 | 27 |
| opus | medium | S1-S9 | 1 | 9 |
| fable | medium | S1 S4 S6 | 1 | 3 |

```
MODEL=sonnet EFFORT=medium REPEAT=3 nohup tests/measure/basecls-run.sh S1 S2 S3 S4 S5 S6 S7 S8 S9 >/dev/null 2>&1 &
MODEL=opus   EFFORT=medium REPEAT=1 nohup tests/measure/basecls-run.sh S1 S2 S3 S4 S5 S6 S7 S8 S9 >/dev/null 2>&1 &
MODEL=fable  EFFORT=medium REPEAT=1 nohup tests/measure/basecls-run.sh S1 S4 S6 >/dev/null 2>&1 &
```
Wait on `<OUT>/done`; read verdicts from `<OUT>/result.log`. The three drivers may run at the same time: separate test dirs and tmux session names (`bt-<ID>-r<n>` collide only within one model, so stagger by ids or run the models one after another when in doubt).

tmux caveats: use the default tmux server (a private `-S` socket dies under `nohup`); set `TERM=xterm-256color`; start claude with `env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT`; the trust dialog defaults to "No, exit", send `Down` then `Enter`; Cyrillic prompts sometimes need a second `Enter`; reports live in `docs/measurements/2026-09-11/`.
