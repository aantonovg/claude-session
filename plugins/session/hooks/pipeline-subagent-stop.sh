#!/bin/sh
# SubagentStop hook for the pipeline mode: appends a stop mark to the cost ledger.
#
# The pipeline skill writes the path of the active task directory into
# ~/.claude/projects/<encoded-cwd>/pipeline/current. When that file is missing
# (any ordinary session) the hook exits at once. Otherwise it appends one line
# {ts, agent_id, event:"stop"} to <task dir>/ledger.jsonl and records the main
# session id in <task dir>/session on first use, so tools/pipeline-cost.py can
# find the transcripts without help from the model.
#
# Input: the hook JSON on stdin (session_id, cwd, agent_id). Output: none. No jq:
# field() takes the first "key": "value" match anywhere in the JSON, so a value with an
# escaped quote is cut short; fine for paths and ids.
#
# Only agents the ledger already names get a stop row: any other subagent that stops
# while pipeline/current points at this task (forks of other work, workflow agents
# launched without a row) is ignored, and a second stop for the same id is ignored too.

INPUT=$(cat)
field() { printf '%s' "$INPUT" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1; }
CWD=$(field cwd); [ -n "$CWD" ] || CWD=$PWD
ENC=$(printf '%s' "$CWD" | sed 's#[^A-Za-z0-9-]#-#g')
CUR="$HOME/.claude/projects/$ENC/pipeline/current"
[ -f "$CUR" ] || exit 0
DIR=$(head -1 "$CUR"); [ -d "$DIR" ] || exit 0
AID=$(field agent_id); [ -n "$AID" ] || AID=$(field agentId)
[ -n "$AID" ] || exit 0
LEDGER="$DIR/ledger.jsonl"
[ -f "$LEDGER" ] || exit 0
grep -v '"event"' "$LEDGER" | grep -qF "\"$AID\"" || exit 0
grep '"event"' "$LEDGER" | grep -qF "\"$AID\"" && exit 0
SID=$(field session_id)
[ -n "$SID" ] && [ ! -f "$DIR/session" ] && printf '%s\n' "$SID" > "$DIR/session"
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
printf '{"ts":"%s","agent_id":"%s","event":"stop"}\n' "$TS" "$AID" >> "$LEDGER"
exit 0
