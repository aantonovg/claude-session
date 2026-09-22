#!/bin/bash
# hooks/modes.sh: records base and codex in both payload shapes, refuses the retired process skill
# and unrelated commands, wipes on PreCompact, reset-counter and a fresh SessionStart, keeps the
# state over a resume, seeds once from the transcript head, prunes old files, prints no context;
# every hook command of plugin.json exists on disk; no ledger hook. Throwaway HOME, no network.
set -u
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
MODES=$P/hooks/modes.sh
PJ=$P/.claude-plugin/plugin.json
command -v jq >/dev/null 2>&1 || { echo "hooks: FAIL jq is required by this suite"; exit 1; }
REAL_HOME=$HOME
HOME=$(mktemp -d) || exit 1
export HOME
case "$HOME" in "$REAL_HOME"|"$REAL_HOME"/*) echo "hooks: FAIL sandbox HOME inside the real home"; exit 1 ;; esac
trap 'rm -rf "$HOME"' EXIT
SID=test-session
STATE_DIR=$HOME/.claude/session-modes
STATE=$STATE_DIR/$SID.json
MARKER=$STATE_DIR/$SID.seeded
run() { printf '%s' "$1" | bash "$MODES" 2>/dev/null; }
state() { local got; got=$(cat "$STATE" 2>/dev/null); check "$1: expected [$2] got [$got]" test "$got" = "$2"; }
marker() { local got=no; [ -f "$MARKER" ] && got=yes; check "$1: marker expected $2 got $got" test "$got" = "$2"; }
reset() { rm -rf "$STATE_DIR"; }
payload() { jq -nc --arg s "$SID" --arg p "$1" '{hook_event_name:"UserPromptSubmit",session_id:$s,prompt:$p}'; }
skillcall() { jq -nc --arg s "$SID" --arg k "$1" --arg a "$2" '{hook_event_name:"PostToolUse",session_id:$s,tool_name:"Skill",tool_input:{skill:$k,args:$a}}'; }
event() { jq -nc --arg s "$SID" --arg e "$1" --arg src "$2" '{hook_event_name:$e,session_id:$s} + (if $src == "" then {} else {source:$src} end)'; }

reset; run "$(payload '/session:base')" >/dev/null; state "raw base" '{"base":"base"}'
check "state file is one flat object of strings" bash -c 'jq -e "type == \"object\" and (to_entries | all(.value | type == \"string\"))" "$1" >/dev/null' _ "$STATE"
reset; run "$(payload '/session:base c4')" >/dev/null; state "base c4" '{"base":"base-c4"}'
reset; run "$(payload '/session:base c5 no-fable no-sonnet')" >/dev/null; state "base canonical order" '{"base":"base-c5-no-sonnet-no-fable"}'
reset; run "$(payload '/session:base c9')" >/dev/null; state "base c9 invalid" ''
reset; run "$(payload '/session:base no-sonnet no-opus no-fable')" >/dev/null; state "all three submodes invalid" ''
reset; run "$(payload '/base no-opus')" >/dev/null; state "bare /base no-opus" '{"base":"base-no-opus"}'
reset; run "$(payload '/session:codex sol')" >/dev/null; state "codex sol" '{"codex":"codex-sol"}'
reset; run "$(payload '/session:codex astra-terra')" >/dev/null; state "codex astra-terra" '{"codex":"codex-astra-terra"}'
reset; run "$(payload '/session:codex +sol')" >/dev/null; state "codex pair +sol" '{"codex":"codex+sol"}'
reset; run "$(payload '/session:codex +astra-luna')" >/dev/null; state "codex pair +astra-luna" '{"codex":"codex+astra-luna"}'
reset; run "$(payload '/session:codex nonsense')" >/dev/null; state "invalid codex records nothing" ''
reset; run "$(payload '/session:process code full')" >/dev/null; state "retired process skill records nothing" ''
reset; run "$(payload '/session:base')" >/dev/null; run "$(payload '/process code full')" >/dev/null; state "bare process changes nothing" '{"base":"base"}'
check "modes.sh names no process mode" bash -c '! grep -Eq "(^|[^a-z-])process([^a-z-]|$)" "$1"' _ "$MODES"
check "modes.sh writes the state directory the statusline reads" grep -Fq '$HOME/.claude/session-modes' "$MODES"
EXP='<command-message>session:base</command-message>
<command-name>/session:base</command-name>
<command-args>c4 no-opus</command-args>'
reset; run "$(payload "$EXP")" >/dev/null; state "expanded base c4 no-opus" '{"base":"base-c4-no-opus"}'
BODY=$(head -c 20000 /dev/zero | tr '\0' 'x')
reset; run "$(payload "$EXP
$BODY")" >/dev/null; state "expanded + 20KB body" '{"base":"base-c4-no-opus"}'
for c in /model /plan /compact /basement; do
  reset; run "$(payload "$c")" >/dev/null; state "unrelated $c records nothing" ''
  reset; run "$(payload '/session:base')" >/dev/null; run "$(payload "$c")" >/dev/null; state "unrelated $c deletes nothing" '{"base":"base"}'
done
reset; run "$(skillcall session:codex 'luna')" >/dev/null; state "PostToolUse codex luna" '{"codex":"codex-luna"}'
run "$(skillcall session:reset-counter '')" >/dev/null; state "PostToolUse reset-counter deletes" ''
reset; run "$(payload '/session:base')" >/dev/null; run "$(payload '/session:reset-counter')" >/dev/null; state "reset-counter deletes" ''
marker "reset-counter writes the marker" yes
reset; run "$(payload '/session:base')" >/dev/null; run "$(event PreCompact '')" >/dev/null; state "PreCompact wipes" ''
marker "PreCompact marks" yes
reset; run "$(payload '/session:base')" >/dev/null; run "$(event SessionStart startup)" >/dev/null; state "SessionStart startup wipes" ''
marker "SessionStart startup leaves no marker" no
reset; run "$(payload '/session:base')" >/dev/null; run "$(event SessionStart resume)" >/dev/null; state "SessionStart resume keeps" '{"base":"base"}'
reset; run "$(payload '/session:base')" >/dev/null; run "$(event SessionStart compact)" >/dev/null; state "SessionStart compact wipes" ''
out=$(reset; run "$(event SessionStart startup)")
check "SessionStart prints no context (got [$out])" test -z "$out"
# seed from the transcript head, once
TP=$HOME/t.jsonl
printf '%s\n' "$(jq -nc '{type:"user",message:{content:"<command-message>session:base</command-message>\n<command-name>/session:base</command-name>\n<command-args>c2</command-args>"}}')" > "$TP"
seedp() { jq -nc --arg s "$SID" --arg p "$1" --arg t "$TP" '{hook_event_name:"UserPromptSubmit",session_id:$s,prompt:$p,transcript_path:$t}'; }
reset; run "$(seedp 'hello')" >/dev/null; state "seed from transcript" '{"base":"base-c2"}'; marker "seed marks" yes
reset; mkdir -p "$STATE_DIR"; touch -t 200001010000 "$STATE_DIR/old.json"; run "$(event SessionStart startup)" >/dev/null
check "SessionStart prunes files older than 7 days" test ! -f "$STATE_DIR/old.json"
# the wiring
check "plugin.json valid JSON" python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$PJ"
python3 - "$PJ" "$P" <<'PY' && pass || fail "every hook command path exists and only modes.sh and workflow-usage.sh are hooked"
import json, os, re, sys
d = json.load(open(sys.argv[1])); root = sys.argv[2]
cmds = [h['command'] for ev in d['hooks'].values() for e in ev for h in e['hooks']]
ok = True
for c in cmds:
    m = re.search(r'\$\{CLAUDE_PLUGIN_ROOT\}/([^ ]+)', c)
    if not m or not os.path.exists(os.path.join(root, m.group(1))): ok = False
    if not ('hooks/modes.sh' in c or 'bin/workflow-usage.sh' in c): ok = False
for ev in ('UserPromptSubmit', 'PostToolUse', 'PreCompact', 'SessionStart'):
    if not any('hooks/modes.sh' in h['command'] for e in d['hooks'].get(ev, []) for h in e['hooks']): ok = False
sys.exit(0 if ok else 1)
PY
check "no ledger hook on disk" test ! -f "$P/hooks/ledger-stop.sh"
done_with hooks
