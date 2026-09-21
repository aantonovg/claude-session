#!/bin/bash
# Static oracle of P5: the state on disk between stages, and the hook wiring that follows it.
# Globs: plugins/session/hooks/*.sh, plugins/session/.claude-plugin/plugin.json,
#        plugins/session/lib/task-layout.md (the literals the hooks share with the layout).
# Proves: hooks/modes.sh records the mode of every session skill of the new set and only of that
# set, in both slash-command payload shapes, seeds once from the transcript head, wipes at the
# events that end a context, and injects at SessionStart one context line naming the absolute path
# of lib/verification.md (P6 review: the base may not resolve that path itself); hooks/ledger-stop.sh appends one stop row per agent against the task
# directory named by tasks/current, carrying the class, depth, slot and label of that agent's own
# launch row, and writes nothing at all in an ordinary session; the state file keeps its JSON shape
# (one flat object, one key per skill); every `command` path of plugin.json exists on disk and the
# five hook events point at the two new scripts.
# A throwaway HOME for the hook scripts alone: no session starts here, no credential, keychain or
# account file is read or copied. Temp dirs only, no network, under 20 s.
set -u

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
P=$REPO/plugins/session
HOOKS=$P/hooks
MODES=$HOOKS/modes.sh
LEDGER_HOOK=$HOOKS/ledger-stop.sh
PJ=$P/.claude-plugin/plugin.json
LAYOUT=$P/lib/task-layout.md

N=0; FAILS=0
pass() { N=$((N + 1)); }
fail() { echo "FAIL $1"; FAILS=$((FAILS + 1)); }
check() { local label=$1; shift; if "$@"; then pass; else fail "$label"; fi; }

command -v jq >/dev/null 2>&1 || { echo "hooks: FAIL jq is required by this suite"; exit 1; }

REAL_HOME=$HOME
HOME=$(mktemp -d) || exit 1
export HOME
case "$HOME" in
  "$REAL_HOME"|"$REAL_HOME"/*) echo "hooks: FAIL sandbox HOME inside the real home"; exit 1 ;;
esac
trap 'rm -rf "$HOME"' EXIT
pass  # sandbox HOME is outside the real home

for f in "$MODES" "$LEDGER_HOOK" "$LAYOUT" "$PJ"; do
  check "h0 $(basename "$f") exists" test -f "$f"
done
if [ ! -f "$MODES" ] || [ ! -f "$LEDGER_HOOK" ] || [ ! -f "$LAYOUT" ]; then
  echo "hooks: FAIL $FAILS failures, $N checks passed"
  exit 1
fi

# ---- h1: hooks/modes.sh, the mode state of the loaded session skills ----
SID=test-session
STATE_DIR=$HOME/.claude/session-modes
STATE=$STATE_DIR/$SID.json
MARKER=$STATE_DIR/$SID.seeded

run() { printf '%s' "$1" | bash "$MODES" >/dev/null 2>&1; }
state() {  # $1 label, $2 expected state ("" = no file)
  local got; got=$(cat "$STATE" 2>/dev/null)
  check "h1 $1: expected [$2] got [$got]" test "$got" = "$2"
}
marker() {  # $1 label, $2 yes|no
  local got=no; [ -f "$MARKER" ] && got=yes
  check "h1 $1: marker expected $2 got $got" test "$got" = "$2"
}
reset() { rm -rf "$STATE_DIR"; }
payload() { jq -nc --arg s "$SID" --arg p "$1" '{hook_event_name:"UserPromptSubmit",session_id:$s,prompt:$p}'; }
skillcall() { jq -nc --arg s "$SID" --arg k "$1" --arg a "$2" '{hook_event_name:"PostToolUse",session_id:$s,tool_name:"Skill",tool_input:{skill:$k,args:$a}}'; }
event() { jq -nc --arg s "$SID" --arg e "$1" --arg src "$2" '{hook_event_name:$e,session_id:$s} + (if $src == "" then {} else {source:$src} end)'; }

# the state file keeps its JSON shape: one flat object, one key per skill, string values
reset; run "$(payload '/session:base')"; state "raw base" '{"base":"base"}'
check "h1 the state file is one flat object of strings" bash -c 'jq -e "type == \"object\" and (to_entries | all(.value | type == \"string\"))" "$1" >/dev/null' _ "$STATE"
reset; run "$(payload '/session:base c4')"; state "base c4" '{"base":"base-c4"}'
reset; run "$(payload '/session:base no-sonnet c4')"; state "base no-sonnet c4" '{"base":"base-c4-no-sonnet"}'
reset; run "$(payload '/session:base c5 no-fable no-sonnet')"; state "base canonical order" '{"base":"base-c5-no-sonnet-no-fable"}'
reset; run "$(payload '/session:base c9')"; state "base c9 invalid" ''
reset; run "$(payload '/session:base no-sonnet no-opus no-fable')"; state "all three submodes invalid" ''
reset; run "$(payload '/session:base c2 c3')"; state "two classes invalid" ''
reset; run "$(payload '/base no-opus')"; state "bare /base no-opus" '{"base":"base-no-opus"}'
reset; run "$(payload '/session:codex +sol')"; state "raw codex +sol" '{"codex":"codex+sol"}'
reset; run "$(payload '/session:codex nonsense')"; state "invalid codex writes nothing" ''

# the process skill of the new set: the task type and the depth are its arguments (A12), in any
# order, rendered in one canonical order
reset; run "$(payload '/session:process')"; state "process bare" '{"process":"process"}'
reset; run "$(payload '/session:process code full')"; state "process code full" '{"process":"process-code-full"}'
reset; run "$(payload '/session:process full code')"; state "process full code (canonical order)" '{"process":"process-code-full"}'
reset; run "$(payload '/session:process lite')"; state "process depth alone" '{"process":"process-lite"}'
reset; run "$(payload '/session:process mr')"; state "process type alone" '{"process":"process-mr"}'
for t in code mr look doc ops; do
  reset; run "$(payload "/session:process $t std")"; state "process type $t" "{\"process\":\"process-$t-std\"}"
done
reset; run "$(payload '/session:process code mr')"; state "two types invalid" ''
reset; run "$(payload '/session:process std full')"; state "two depths invalid" ''
reset; run "$(payload '/session:process fast')"; state "old depth word invalid" ''
reset; run "$(payload '/session:process nonsense')"; state "unknown process argument invalid" ''

# no key of the old set survives: the old process skills are not modes of this hook any more
for old in pipeline review; do
  reset; run "$(payload "/session:$old full")"; state "old skill $old records nothing" ''
  reset; run "$(payload '/session:base')"; run "$(payload "/$old full")"
  state "bare old skill $old changes nothing" '{"base":"base"}'
done
check "h1 modes.sh names no old process skill" bash -c '! grep -Eq "(^|[^a-z-])(pipeline|review)([^a-z-]|$)" "$1"' _ "$MODES"
# the state directory of the U9 answer: the statusline outside this plugin reads
# ~/.claude/session-modes/<session_id>.json, and the full plan names no other directory, so the
# names inside the file are the only thing this rebuild changes about that file
check "h1 modes.sh writes the state directory the statusline reads" grep -Fq '$HOME/.claude/session-modes' "$MODES"
check "h1 modes.sh writes no second state directory" bash -c '! grep -Fq "session-state" "$1"' _ "$MODES"
# the old depths were fast|standard|full; `full` is a depth of the new set too, so only the two
# retired words may not stand in the hook. The alternation this check used to hold was escaped,
# so it matched the literal string `fast|standard|full` and passed over any word at all.
check "h1 modes.sh names no old depth word" bash -c '! grep -Eq "(^|[^a-z-])(fast|standard)([^a-z-]|$)" "$1"' _ "$MODES"

# both payload shapes, as measured on real sessions
EXP='<command-message>session:process</command-message>
<command-name>/session:process</command-name>
<command-args>code full</command-args>'
reset; run "$(payload "$EXP")"; state "expanded process code full" '{"process":"process-code-full"}'
BODY=$(head -c 20000 /dev/zero | tr '\0' 'x')
reset; run "$(payload "$EXP
$BODY")"; state "expanded + 20KB body" '{"process":"process-code-full"}'
BARE='<command-message>process</command-message>
<command-name>/process</command-name>
<command-args>doc lite</command-args>'
reset; run "$(payload "$BARE")"; state "bare form in an expanded block" '{"process":"process-doc-lite"}'

# an unrelated command is never taken for a mode and never deletes
for c in /model /plan /compact /processing /basement; do
  reset; run "$(payload "$c")"; state "unrelated $c records nothing" ''
  reset; run "$(payload '/session:base')"; run "$(payload "$c")"
  state "unrelated $c deletes nothing" '{"base":"base"}'
done

# the skill tool call, the counter reset and the lifecycle events
reset; run "$(skillcall session:process 'ops std')"; state "PostToolUse process ops std" '{"process":"process-ops-std"}'
run "$(skillcall session:reset-counter '')"; state "PostToolUse reset-counter deletes" ''
reset; run "$(payload '/session:base')"; run "$(payload '/session:reset-counter')"; state "reset-counter deletes" ''
marker "reset-counter writes the marker" yes
reset; run "$(payload '/session:base')"; run "$(event PreCompact '')"; state "PreCompact wipes" ''
marker "PreCompact marks" yes
reset; run "$(payload '/session:base')"; run "$(event SessionStart compact)"; state "SessionStart compact wipes" ''
reset; run "$(payload '/session:base')"; run "$(event SessionStart resume)"; state "SessionStart resume keeps" '{"base":"base"}'
reset; run "$(payload '/session:base')"; run "$(event PreCompact '')"; run "$(event SessionStart startup)"
state "SessionStart startup wipes" ''
marker "SessionStart startup removes the marker" no
reset; run "$(event SessionStart wat)"; marker "SessionStart unknown source marks" yes

# the one context line of SessionStart: the absolute path of lib/verification.md, so the base rule
# "read the verification page before planning a task" is one Read of a known path instead of a
# resolve pipeline plus a Read in the main session.
emit() { printf '%s' "$1" | bash "$MODES" 2>/dev/null; }
reset; VOUT=$(emit "$(event SessionStart startup)")
check "h1 SessionStart prints one SessionStart hook JSON" bash -c \
  'printf "%s" "$1" | jq -e ".hookSpecificOutput.hookEventName == \"SessionStart\"" >/dev/null' _ "$VOUT"
check "h1 the injected line names the plugin's own verification page" bash -c \
  'p=$(printf "%s" "$1" | jq -r ".hookSpecificOutput.additionalContext" | grep -oE "/[^ ]*/lib/verification\.md"); [ "$p" = "$2" ] && [ -f "$p" ]' _ "$VOUT" "$P/lib/verification.md"
check "h1 the injected line carries the wording the base quotes" bash -c \
  'printf "%s" "$1" | jq -r ".hookSpecificOutput.additionalContext" | grep -Fq "Verification page (read before planning a task): "' _ "$VOUT"
check "h1 a resume SessionStart injects the line too" bash -c \
  'printf "%s" "$1" | jq -e ".hookSpecificOutput.additionalContext" >/dev/null' _ "$(emit "$(event SessionStart resume)")"
check "h1 a prompt event prints nothing" test -z "$(emit "$(payload '/session:base')")"
check "h1 a PreCompact prints nothing" test -z "$(emit "$(event PreCompact '')")"
# a copy of the hook without the page beside it stays silent: a path that reads clean but points at
# nothing would cost the session the very Read the line saves
COPY=$HOME/fakeplugin/hooks; mkdir -p "$COPY"; cp "$MODES" "$COPY/modes.sh"
check "h1 no page beside the hook, no line" test -z "$(printf '%s' "$(event SessionStart startup)" | bash "$COPY/modes.sh" 2>/dev/null)"
reset

# the seed: one pass over the head of the transcript, merge with what real events recorded
TR=$HOME/transcript.jsonl
uline() { jq -nc --arg c "$1" '{type:"user",message:{content:$c}}'; }
cmd() {
  if [ -z "$2" ]; then printf '<command-message>session:%s</command-message>\n<command-name>/session:%s</command-name>' "$1" "$1"
  else printf '<command-message>session:%s</command-message>\n<command-name>/session:%s</command-name>\n<command-args>%s</command-args>' "$1" "$1" "$2"; fi
}
tpayload() { jq -nc --arg s "$SID" --arg p "$2" --arg t "$1" '{hook_event_name:"UserPromptSubmit",session_id:$s,prompt:$p,transcript_path:$t}'; }

reset; { uline "$(cmd base '')"; uline "$(cmd process 'code full')"; } >"$TR"
run "$(tpayload "$TR" hello)"; state "seed builds the state" '{"base":"base","process":"process-code-full"}'
marker "seed writes the marker" yes
reset; { uline "$(cmd base '')"; uline "$(cmd reset-counter '')"; uline "$(cmd process 'look lite')"; } >"$TR"
run "$(tpayload "$TR" hello)"; state "seed honours a mid-transcript reset-counter" '{"process":"process-look-lite"}'
reset; { uline "$(cmd base '')"; } >"$TR"
run "$(tpayload "$TR" hello)"; rm -f "$STATE"; run "$(tpayload "$TR" again)"; state "seed runs once" ''
reset; jq -nc --arg c "quoted $(cmd base '')" '{type:"user",message:{content:$c}}' >"$TR"
run "$(tpayload "$TR" hello)"; state "a quoted command tag seeds nothing" ''
reset; jq -nc --arg c "$(cmd base '')" '{type:"user",isSidechain:true,message:{content:$c}}' >"$TR"
run "$(tpayload "$TR" hello)"; state "a sidechain entry seeds nothing" ''
GOOD=$HOME/good.jsonl; uline "$(cmd base '')" >"$GOOD"
reset; run "$(tpayload "$HOME/nope.jsonl" hello)"; marker "a missing transcript leaves no marker" no
run "$(tpayload "$GOOD" again)"; state "a missing transcript still reseeds later" '{"base":"base"}'
reset; run "$(skillcall session:process 'code std')"; { uline "$(cmd base '')"; } >"$TR"
run "$(tpayload "$TR" hello)"; state "seed merges with the recorded state" '{"base":"base","process":"process-code-std"}'
reset; run "$(skillcall session:process 'code std')"; { uline "$(cmd process 'doc lite')"; } >"$TR"
run "$(tpayload "$TR" hello)"; state "a recorded key is not clobbered by the seed" '{"process":"process-code-std"}'

# a session id is a path segment: anything else is refused outright
reset; printf '%s' "$(jq -nc '{hook_event_name:"UserPromptSubmit",session_id:"../evil",prompt:"/session:base"}')" | bash "$MODES" >/dev/null 2>&1
check "h1 a session id with a path separator writes nothing" bash -c '[ ! -e "$1/.claude/evil.json" ] && [ ! -d "$1/.claude/session-modes" ]' _ "$HOME"
reset

# ---- h2: hooks/ledger-stop.sh, one stop row per agent against tasks/current ----
# This suite proves the reader of the pointer and nothing about its writer: no file of P5 writes or
# removes tasks/current. The writer is the process skill of P8 (plan section P8, `core.md`: the
# task dir and the ledger), and the executed cases below are the two states the hook must survive —
# a pointer that stands and no pointer at all.
POINTER_REL=$(grep -oE '[A-Za-z0-9./<>_-]*tasks/current' "$LAYOUT" | head -1)
check "h2 lib/task-layout.md names the tasks/current pointer" test -n "$POINTER_REL"
check "h2 lib/task-layout.md names the stage that writes it" grep -Fq 'written by the process skill' "$LAYOUT"
check "h2 lib/task-layout.md names the stage that removes it" grep -Fq 'removed by the process skill' "$LAYOUT"
check "h2 ledger-stop.sh reads that pointer" grep -Fq 'tasks/current' "$LEDGER_HOOK"
LEDGER_NAME=$(grep -oE 'ledger\.jsonl' "$LAYOUT" | head -1)
check "h2 lib/task-layout.md names the ledger file" test "$LEDGER_NAME" = ledger.jsonl
check "h2 ledger-stop.sh appends to that file" grep -Fq 'ledger.jsonl' "$LEDGER_HOOK"
check "h2 ledger-stop.sh names no old pointer path" bash -c '! grep -Fq "pipeline/current" "$1"' _ "$LEDGER_HOOK"  # stale-ok: the retired pointer path, quoted to assert its absence

CWD=/tmp/ledger-proj
ENC=$(printf '%s' "$CWD" | sed 's#[^A-Za-z0-9-]#-#g')
PDIR=$HOME/.claude/projects/$ENC
TASK=$HOME/task-2026-09-20-thing
stop_payload() { jq -nc --arg c "$CWD" --arg a "$1" --arg s "${2:-main-session}" \
  '{hook_event_name:"SubagentStop",session_id:$s,cwd:$c,agent_id:$a}'; }
launch_row() {  # $1 agent id, $2 class, $3 depth, $4 slot, $5 label
  jq -nc --arg a "$1" --arg c "$2" --arg d "$3" --arg s "$4" --arg l "$5" \
    '{ts:"2026-09-20T10:00:00Z",agent_id:$a,role:"code-author",class:$c,depth:$d,slot:$s,label:$l}'
}
ledger_reset() {
  rm -rf "$PDIR" "$TASK"
  mkdir -p "$PDIR/tasks" "$TASK"
  printf '%s\n' "$TASK" >"$PDIR/tasks/current"
  launch_row a1 c3 full sonnet son-hi-code-author >"$TASK/ledger.jsonl"
}
stops() { grep -c '"event":"stop"' "$TASK/ledger.jsonl" 2>/dev/null || true; }
field() { jq -r --arg a "$1" --arg k "$2" 'select(.event == "stop" and .agent_id == $a) | .[$k] // "(absent)"' "$TASK/ledger.jsonl" 2>/dev/null | head -1; }

ledger_reset
printf '%s' "$(stop_payload a1)" | bash "$LEDGER_HOOK" >/dev/null 2>&1
check "h2 the stop row is appended (rows: $(stops))" test "$(stops)" = 1
check "h2 every ledger line stays one JSON object" bash -c 'jq -e . "$1" >/dev/null' _ "$TASK/ledger.jsonl"
for kv in class:c3 depth:full slot:sonnet label:son-hi-code-author; do
  k=${kv%%:*}; v=${kv#*:}
  check "h2 the stop row carries $k=$v (got $(field a1 "$k"))" test "$(field a1 "$k")" = "$v"
done
check "h2 the stop row carries a timestamp" bash -c '[ -n "$(jq -r "select(.event == \"stop\") | .ts // empty" "$1" | head -1)" ]' _ "$TASK/ledger.jsonl"
check "h2 the main session id is recorded once" test "$(cat "$TASK/session" 2>/dev/null)" = main-session
printf '%s' "$(stop_payload a1 other-session)" | bash "$LEDGER_HOOK" >/dev/null 2>&1
check "h2 a second stop of the same agent adds no row (rows: $(stops))" test "$(stops)" = 1
check "h2 the recorded session id is not overwritten" test "$(cat "$TASK/session" 2>/dev/null)" = main-session

ledger_reset
printf '%s' "$(stop_payload unknown-agent)" | bash "$LEDGER_HOOK" >/dev/null 2>&1
check "h2 an agent the ledger does not name gets no row (rows: $(stops))" test "$(stops)" = 0

ledger_reset
{ launch_row a2 c4 std opus ops-hi-fixer; } >>"$TASK/ledger.jsonl"
printf '%s' "$(stop_payload a2)" | bash "$LEDGER_HOOK" >/dev/null 2>&1
check "h2 the row of the stopping agent decides, not the first row (got $(field a2 label))" test "$(field a2 label)" = ops-hi-fixer
check "h2 only the stopping agent gets a row (rows: $(stops))" test "$(stops)" = 1

ledger_reset
printf 'not json at all\n' >>"$TASK/ledger.jsonl"
printf '%s' "$(stop_payload a1)" | bash "$LEDGER_HOOK" >/dev/null 2>&1
check "h2 a broken ledger line does not stop the stop row (rows: $(stops))" test "$(stops)" = 1

ledger_reset
jq -nc '{ts:"2026-09-20T10:00:00Z",agent_id:"a3",role:"waiter"}' >>"$TASK/ledger.jsonl"
printf '%s' "$(stop_payload a3)" | bash "$LEDGER_HOOK" >/dev/null 2>&1
check "h2 a launch row without the four fields still gets a stop row" test "$(stops)" = 1
check "h2 that stop row invents no class (got $(field a3 class))" test "$(field a3 class)" = '(absent)'

ledger_reset; rm -f "$PDIR/tasks/current"
printf '%s' "$(stop_payload a1)" | bash "$LEDGER_HOOK" >/dev/null 2>&1
check "h2 no pointer, no row: an ordinary session is untouched (rows: $(stops))" test "$(stops)" = 0

ledger_reset; printf '%s\n' "$HOME/no-such-task" >"$PDIR/tasks/current"
printf '%s' "$(stop_payload a1)" | bash "$LEDGER_HOOK" >/dev/null 2>&1
check "h2 a pointer at a missing directory writes nothing (rows: $(stops))" test "$(stops)" = 0

ledger_reset; rm -f "$TASK/ledger.jsonl"
printf '%s' "$(stop_payload a1)" | bash "$LEDGER_HOOK" >/dev/null 2>&1
check "h2 a task directory without a ledger writes nothing" bash -c '[ ! -f "$1/ledger.jsonl" ]' _ "$TASK"

ledger_reset
printf '%s' "$(jq -nc --arg c "$CWD" '{hook_event_name:"SubagentStop",session_id:"s",cwd:$c}')" | bash "$LEDGER_HOOK" >/dev/null 2>&1
check "h2 a payload without an agent id writes nothing (rows: $(stops))" test "$(stops)" = 0

# A workflow launch: the launch row holds the run id the launch result gives (`wf_...`), and each
# agent of the run stops under its own id. Live run 20260921-065113 (base:resume) had launch rows of
# that form and no stop row at all, so a finished stage read as unfinished and was redone. The run
# is found from the agent's transcript path, from the payload or beside the session transcript.
wf_setup() { # wf_setup <run> <agent...>: a session transcript dir holding the run's agent files
  local run=$1; shift
  mkdir -p "$PDIR/sess1/subagents/workflows/$run"
  : > "$PDIR/sess1.jsonl"
  for a in "$@"; do : > "$PDIR/sess1/subagents/workflows/$run/agent-$a.jsonl"; done
}
wf_payload() { # wf_payload <agent> <with agent_transcript_path: yes|no> <run>
  if [ "$2" = yes ]; then
    jq -nc --arg c "$CWD" --arg a "$1" --arg p "$PDIR/sess1/subagents/workflows/$3/agent-$1.jsonl" \
      '{hook_event_name:"SubagentStop",session_id:"sess1",cwd:$c,agent_id:$a,agent_transcript_path:$p}'
  else
    jq -nc --arg c "$CWD" --arg a "$1" --arg t "$PDIR/sess1.jsonl" \
      '{hook_event_name:"SubagentStop",session_id:"sess1",cwd:$c,agent_id:$a,transcript_path:$t}'
  fi
}
for how in yes no; do
  ledger_reset; wf_setup wf_run1-abc a5f00 a6f00
  launch_row wf_run1-abc c4 std main fab-me-plan-author >>"$TASK/ledger.jsonl"
  printf '%s' "$(wf_payload a5f00 "$how" wf_run1-abc)" | bash "$LEDGER_HOOK" >/dev/null 2>&1
  check "h2 a workflow agent stopping writes the stop row of its run (path in payload: $how; rows: $(stops))" test "$(stops)" = 1
  check "h2 that stop row names the run and copies its label (got $(field wf_run1-abc label))" test "$(field wf_run1-abc label)" = fab-me-plan-author
  printf '%s' "$(wf_payload a6f00 "$how" wf_run1-abc)" | bash "$LEDGER_HOOK" >/dev/null 2>&1
  check "h2 a second agent of the same run adds no row (path in payload: $how; rows: $(stops))" test "$(stops)" = 1
done
ledger_reset; wf_setup wf_other-123 a7f00
printf '%s' "$(wf_payload a7f00 no wf_other-123)" | bash "$LEDGER_HOOK" >/dev/null 2>&1
check "h2 an agent of a run the ledger does not name gets no row (rows: $(stops))" test "$(stops)" = 0
# the mutant is the hook of before: it looks the stopping agent up by its own id and nothing else
MUT_HOOK=$HOME/ledger-stop-mutant.sh
perl -pe 's/^if \[ -z "\$ROW" \]; then$/if false; then/' "$LEDGER_HOOK" > "$MUT_HOOK"
check "h2 the run-lookup mutant is really a mutation" bash -c '! cmp -s "$1" "$2"' _ "$LEDGER_HOOK" "$MUT_HOOK"
ledger_reset; wf_setup wf_run1-abc a5f00
launch_row wf_run1-abc c4 std main fab-me-plan-author >>"$TASK/ledger.jsonl"
printf '%s' "$(wf_payload a5f00 no wf_run1-abc)" | bash "$MUT_HOOK" >/dev/null 2>&1
check "h2 a hook that finds no run for a workflow agent is caught (mutant rows: $(stops))" test "$(stops)" = 0

ledger_reset
printf '%s' "$(stop_payload a1)" | bash "$LEDGER_HOOK" >/dev/null 2>&1; rc=$?
check "h2 the hook exits 0" test "$rc" -eq 0

# The row shape needs jq: on a machine without it every stop row is lost, so the loss is said on
# stderr instead of reading as a session that launched no agent, and the exit stays 0.
ledger_reset
NOJQ=$HOME/nojq; mkdir -p "$NOJQ"
for t in cat sed head tail date printf; do p=$(command -v "$t") && [ -x "$p" ] && ln -sf "$p" "$NOJQ/$t"; done
# bash itself is looked up in that stripped PATH, so it is called by its own absolute path
printf '%s' "$(stop_payload a1)" | env PATH="$NOJQ" "${BASH:-/bin/bash}" "$LEDGER_HOOK" >/dev/null 2>"$HOME/nojq.err"; rc=$?
check "h2 with no jq the hook still exits 0" test "$rc" -eq 0
check "h2 with no jq the lost row is said on stderr" grep -Fq 'jq is missing' "$HOME/nojq.err"
check "h2 with no jq no row is invented (rows: $(stops))" test "$(stops)" = 0

# ---- h3: the wiring of plugin.json ----
check "h3 plugin.json is valid JSON" python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$PJ"
wiring() { python3 - "$PJ" "$1" "$2" "$3" <<'PY'
import json, sys
pj, event, want, matcher = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
groups = json.load(open(pj, encoding='utf-8'))['hooks'].get(event, [])
if matcher:
    groups = [g for g in groups if g.get('matcher') == matcher]
else:
    groups = [groups[0]] if groups else []
cmds = [h.get('command', '') for g in groups for h in g['hooks']]
sys.exit(0 if len(cmds) == 1 and cmds[0].endswith(want) else 1)
PY
}
check "h3 SubagentStop points at hooks/ledger-stop.sh" wiring SubagentStop '/hooks/ledger-stop.sh' ''
check "h3 UserPromptSubmit points at hooks/modes.sh" wiring UserPromptSubmit '/hooks/modes.sh' ''
check "h3 PreCompact points at hooks/modes.sh" wiring PreCompact '/hooks/modes.sh' ''
check "h3 PostToolUse(Skill) points at hooks/modes.sh" wiring PostToolUse '/hooks/modes.sh' Skill
check "h3 the first SessionStart entry points at hooks/modes.sh" wiring SessionStart '/hooks/modes.sh' ''
check "h3 no event points at an old hook script" bash -c '! grep -Eq "session-modes\.sh|pipeline-subagent-stop\.sh" "$1"' _ "$PJ"
check "h3 every command path of plugin.json exists on disk" python3 - "$PJ" "$P" <<'PY'
import json, os, re, sys
pj, plugin = sys.argv[1], sys.argv[2]
missing = []
for event, groups in json.load(open(pj, encoding='utf-8'))['hooks'].items():
    for g in groups:
        for h in g['hooks']:
            cmd = h.get('command', '')
            for m in re.finditer(r'\$\{CLAUDE_PLUGIN_ROOT\}(/[A-Za-z0-9._/-]+)', cmd):
                p = plugin + m.group(1)
                if not os.path.exists(p):
                    missing.append('%s: %s' % (event, p))
if missing:
    print('\n'.join(missing))
sys.exit(1 if missing else 0)
PY
check "h3 both new hook scripts are executable" bash -c '[ -x "$1" ] && [ -x "$2" ]' _ "$MODES" "$LEDGER_HOOK"

if [ "$FAILS" -eq 0 ]; then echo "hooks: PASS $N"; exit 0; fi
echo "hooks: FAIL $FAILS failures, $N checks passed"
exit 1
