# Measurement drivers (2026-09-11)

Interactive tmux sessions that measure the start context of a main session or of every custom agent, and check which agent a main session launches under the base. Never `claude -p` (billed at about 3.3x on the subscription).

- `rem-run.sh`: one sonnet session in a project dir, sends `hi`, keeps the JSONL; the pattern every other driver copies.
- `ctx3-run.sh`: one session per built-in tool with every other tool denied, to price each tool schema.
- `agentctx-run.sh`: launches every custom agent once through Workflow and copies each subagent JSONL for a per-agent breakdown.
- `basecls-run.sh` + `basecls-parse.py`: scenarios T0-T7 on an opus-medium main, asserting the Workflow model, effort and label per class and submode. Known bug: the parser scans for tool calls only after the "Base on" text; read the raw JSONL when in doubt.

tmux caveats: use the default tmux server (a private `-S` socket dies under `nohup`); set `TERM=xterm-256color`; start claude with `env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT`; the trust dialog defaults to "No, exit", send `Down` then `Enter`; Cyrillic prompts sometimes need a second `Enter`; reports live in `docs/measurements/2026-09-11/`.
