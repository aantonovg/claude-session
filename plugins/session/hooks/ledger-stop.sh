#!/bin/bash
# SubagentStop hook: one stop row per agent in the ledger of the current task.
#
# The process skill writes the path of the active task directory into
# ~/.claude/projects/<encoded-cwd>/tasks/current (lib/task-layout.md). When that
# file is missing - any ordinary session - the hook exits at once and writes
# nothing at all. Otherwise it appends one row
#   {ts, agent_id, event:"stop", class, depth, slot, label}
# to <task dir>/ledger.jsonl, copying class, depth, slot and label from that
# agent's own launch row, and records the main session id in <task dir>/session
# on first use, so a cost reading finds the transcripts without help from the model.
#
# Input: the hook JSON on stdin (session_id, cwd, agent_id). Output: none.
#
# Only agents the ledger already names get a stop row: any other subagent that
# stops while tasks/current points at this task (forks of other work, workflow
# agents launched without a row) is ignored, and a second stop for the same id is
# ignored too - the row is the evidence of one launch, never a counter.

INPUT=$(cat)
command -v jq >/dev/null 2>&1 || exit 0

field() { printf '%s' "$INPUT" | jq -r --arg k "$1" '.[$k] // empty' 2>/dev/null; }
CWD=$(field cwd); [ -n "$CWD" ] || CWD=$PWD
ENC=$(printf '%s' "$CWD" | sed 's#[^A-Za-z0-9-]#-#g')
CUR="$HOME/.claude/projects/$ENC/tasks/current"
[ -f "$CUR" ] || exit 0
DIR=$(head -1 "$CUR"); [ -n "$DIR" ] && [ -d "$DIR" ] || exit 0
AID=$(field agent_id); [ -n "$AID" ] || AID=$(field agentId)
[ -n "$AID" ] || exit 0
LEDGER="$DIR/ledger.jsonl"
[ -f "$LEDGER" ] || exit 0

# The launch row of this agent, and its own stop row if one already stands. A line
# that is no JSON object is skipped, never fatal: the ledger is appended to by
# several writers and one broken line may not silence every later stop.
ROW=$(jq -c -R --arg a "$AID" '
  fromjson? | select(type == "object") | select(.agent_id == $a) | select(has("event") | not)
' "$LEDGER" 2>/dev/null | tail -1)
[ -n "$ROW" ] || exit 0
DONE=$(jq -c -R --arg a "$AID" '
  fromjson? | select(type == "object") | select(.agent_id == $a and .event == "stop")
' "$LEDGER" 2>/dev/null | head -1)
[ -n "$DONE" ] && exit 0

SID=$(field session_id)
[ -n "$SID" ] && [ ! -f "$DIR/session" ] && printf '%s\n' "$SID" > "$DIR/session"
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
# class, depth, slot and label are copied from the launch row and never invented:
# a launch row that carried none of them gets a stop row with none of them.
OUT=$(printf '%s' "$ROW" | jq -c --arg a "$AID" --arg ts "$TS" '
  {ts: $ts, agent_id: $a, event: "stop"}
  + ({class, depth, slot, label} | with_entries(select(.value != null)))
' 2>/dev/null)
[ -n "$OUT" ] || exit 0
printf '%s\n' "$OUT" >> "$LEDGER"
exit 0
