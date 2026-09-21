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
# Input: the hook JSON on stdin (session_id, cwd, agent_id, and for the run of a workflow
# agent agent_transcript_path or transcript_path). Output: none. The stop row is the machine
# record that a launch finished; the resume rule of the process reads it instead of any marker
# an agent writes into its own file.
#
# Only agents the ledger already names get a stop row: any other subagent that
# stops while tasks/current points at this task (forks of other work, workflow
# agents launched without a row) is ignored, and a second stop for the same id is
# ignored too - the row is the evidence of one launch, never a counter. One more row, once per
# task: the intent stop row {ts, stage:"intent", event:"stop", depth}, at the end of this file.

INPUT=$(cat)
# The row shape above is built with jq and cannot be built without it. A machine with no jq loses
# every stop row, so the loss is said out loud on stderr instead of passing for a session that
# launched no agent; the exit stays 0, because a hook that fails stops the agent's own stop event.
if ! command -v jq >/dev/null 2>&1; then
  printf 'session ledger-stop: jq is missing, no stop row written\n' >&2
  exit 0
fi

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
launch_row() {
  jq -c -R --arg a "$1" '
    fromjson? | select(type == "object") | select(.agent_id == $a) | select(has("event") | not)
  ' "$LEDGER" 2>/dev/null | tail -1
}
ROW=$(launch_row "$AID")
# An agent of a workflow launch stops under its own id, while the launch row holds the id of the
# run (`wf_...`), the only id the launch result gives. The run is the directory the agent's
# transcript sits in, `.../subagents/workflows/<run>/agent-<id>.jsonl`: read from the payload's
# agent_transcript_path, else looked up beside the session transcript. The stop row then names the
# run, once: the first agent of the run that stops writes it.
if [ -z "$ROW" ]; then
  RUN=
  ATP=$(field agent_transcript_path)
  case $ATP in */subagents/workflows/*/agent-*) RUN=$(basename "$(dirname "$ATP")") ;; esac
  if [ -z "$RUN" ]; then
    SID0=$(field session_id); TP=$(field transcript_path)
    if [ -n "$TP" ]; then BASE=${TP%.jsonl}
    elif [ -n "$SID0" ]; then BASE=$HOME/.claude/projects/$ENC/$SID0
    else exit 0; fi
    for f in "$BASE"/subagents/workflows/*/agent-"$AID".jsonl; do
      [ -f "$f" ] && { RUN=$(basename "$(dirname "$f")"); break; }
    done
  fi
  [ -n "$RUN" ] || exit 0
  ROW=$(launch_row "$RUN")
  [ -n "$ROW" ] || exit 0
  AID=$RUN
fi
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

# The intent stop row: no launch writes the intent, so its row is written here, once, at the first
# stop row of the task. The decision is intentStopDue() of lib/block.js (nothing is launched at std
# or full before the user confirmed the intent); this glue only reads the files. No node, no row.
BLOCKJS=$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)/lib/block.js
if command -v node >/dev/null 2>&1 && [ -f "$BLOCKJS" ]; then
  node -e '
    const b = require(process.argv[1]), fs = require("fs"), d = process.argv[2]
    const led = fs.readFileSync(d + "/ledger.jsonl", "utf8")
    if (b.intentStopDue(led, fs.readdirSync(d))) process.stdout.write(JSON.stringify(b.intentStopRow(led, process.argv[3])) + "\n")
  ' "$BLOCKJS" "$DIR" "$TS" >> "$LEDGER" 2>/dev/null
fi
exit 0
