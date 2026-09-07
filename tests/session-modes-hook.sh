#!/bin/bash
# Verifier for plugins/session/hooks/session-modes.sh
# Runs the hook against both slash-command payload shapes and the lifecycle
# events, in a throwaway HOME so the real ~/.claude is never touched.

HOOK=$(cd "$(dirname "$0")/.." && pwd)/plugins/session/hooks/session-modes.sh
[ -x "$HOOK" ] || [ -f "$HOOK" ] || { echo "hook not found: $HOOK"; exit 1; }

REAL_HOME=$HOME
HOME=$(mktemp -d) || exit 1
export HOME
case "$HOME" in
  "$REAL_HOME"|"$REAL_HOME"/*) echo "FAIL sandbox: HOME inside real home"; exit 1 ;;
esac
echo "PASS sandbox HOME=$HOME"

SID=test-session
STATE="$HOME/.claude/session-modes/$SID.json"
PASS=1; TOTAL=1

run() {  # $1 = json payload on stdin
  printf '%s' "$1" | bash "$HOOK" >/dev/null 2>&1
}
check() {  # $1 name, $2 expected state ("" = file must not exist)
  TOTAL=$((TOTAL + 1))
  got=$(cat "$STATE" 2>/dev/null)
  if [ "$got" = "$2" ]; then
    echo "PASS $1"; PASS=$((PASS + 1))
  else
    echo "FAIL $1: expected [$2] got [$got]"
  fi
}
reset() { rm -rf "$HOME/.claude/session-modes"; }

# jq -n builds the payload so quoting and huge bodies stay safe.
payload() { jq -nc --arg s "$SID" --arg p "$2" "{hook_event_name:\"UserPromptSubmit\",session_id:\$s,prompt:\$p}"; }

reset; run "$(payload x '/session:base')";  check "raw base" '{"base":"base"}'
reset; run "$(payload x '/session:codex +sol')"; check "raw codex +sol" '{"codex":"codex+sol"}'

EXP_BASE='<command-message>session:base</command-message>
<command-name>/session:base</command-name>'
reset; run "$(payload x "$EXP_BASE")"; check "expanded base" '{"base":"base"}'

EXP_CODEX='<command-message>session:codex</command-message>
<command-name>/session:codex</command-name>
<command-args>+sol</command-args>'
reset; run "$(payload x "$EXP_CODEX")"; check "expanded codex +sol" '{"codex":"codex+sol"}'

BODY=$(head -c 20000 /dev/zero | tr '\0' 'x')
reset; run "$(payload x "$EXP_CODEX
$BODY")"; check "expanded + 20KB body" '{"codex":"codex+sol"}'

reset; run "$(payload x '/session:codex nonsense')"; check "invalid mode writes nothing" ''

reset; run "$(payload x '/session:base')"; run "$(payload x '/session:reset-counter')"
check "raw reset-counter deletes" ''
reset; run "$(payload x '/session:base')"
run "$(payload x '<command-message>session:reset-counter</command-message>
<command-name>/session:reset-counter</command-name>')"
check "expanded reset-counter deletes" ''

reset
run "$(jq -nc --arg s "$SID" '{hook_event_name:"PostToolUse",session_id:$s,tool_name:"Skill",tool_input:{skill:"session:pipeline",args:"full"}}')"
check "PostToolUse pipeline full" '{"pipeline":"pipeline-full"}'
run "$(jq -nc --arg s "$SID" '{hook_event_name:"PostToolUse",session_id:$s,tool_name:"Skill",tool_input:{skill:"session:reset-counter"}}')"
check "PostToolUse reset-counter deletes" ''

reset; run "$(payload x '/session:base')"
run "$(jq -nc --arg s "$SID" '{hook_event_name:"SessionStart",session_id:$s,source:"compact"}')"
check "SessionStart compact wipes" ''
reset; run "$(payload x '/session:base')"
run "$(jq -nc --arg s "$SID" '{hook_event_name:"SessionStart",session_id:$s,source:"resume"}')"
check "SessionStart resume keeps" '{"base":"base"}'
reset; run "$(payload x '/session:base')"
run "$(jq -nc --arg s "$SID" '{hook_event_name:"PreCompact",session_id:$s}')"
check "PreCompact wipes" ''

# --- seed pass, marker, prune -------------------------------------------------

MARKER="$HOME/.claude/session-modes/$SID.seeded"
TR="$HOME/transcript.jsonl"

check_marker() {  # $1 name, $2 "yes"|"no"
  TOTAL=$((TOTAL + 1))
  if [ -f "$MARKER" ]; then got=yes; else got=no; fi
  if [ "$got" = "$2" ]; then echo "PASS $1"; PASS=$((PASS + 1))
  else echo "FAIL $1: marker expected $2 got $got"; fi
}
# payload carrying a transcript path
tpayload() { jq -nc --arg s "$SID" --arg p "$2" --arg t "$1" \
  '{hook_event_name:"UserPromptSubmit",session_id:$s,prompt:$p,transcript_path:$t}'; }
# one user entry whose content is the given string
uline() { jq -nc --arg c "$1" '{type:"user",message:{content:$c}}'; }
cmd() {  # $1 skill, $2 args ("" = no args tag)
  if [ -z "$2" ]; then
    printf '<command-message>session:%s</command-message>\n<command-name>/session:%s</command-name>' "$1" "$1"
  else
    printf '<command-message>session:%s</command-message>\n<command-name>/session:%s</command-name>\n<command-args>%s</command-args>' "$1" "$1" "$2"
  fi
}

reset; { uline "$(cmd base '')"; uline "$(cmd codex '+astra')"; } >"$TR"
run "$(tpayload "$TR" 'hello')"
check "seed builds state" '{"base":"base","codex":"codex+astra"}'
check_marker "seed writes marker" yes

reset; { uline "$(cmd base '')"; uline "$(cmd reset-counter '')"; uline "$(cmd review 'std')"; } >"$TR"
run "$(tpayload "$TR" 'hello')"
check "seed honours mid-transcript reset-counter" '{"review":"review-std"}'

reset; { uline "$(cmd base '')"; } >"$TR"
run "$(tpayload "$TR" 'hello')"; rm -f "$STATE"
run "$(tpayload "$TR" 'hello again')"
check "seed runs once" ''

reset; { uline "$(cmd base '')"; } >"$TR"
run "$(payload x '/session:reset-counter')"
check_marker "reset-counter writes marker" yes
run "$(tpayload "$TR" 'hello')"
check "reset-counter blocks resurrection" ''

reset; run "$(jq -nc --arg s "$SID" '{hook_event_name:"PreCompact",session_id:$s}')"
check_marker "PreCompact marks" yes
reset; run "$(jq -nc --arg s "$SID" '{hook_event_name:"SessionStart",session_id:$s,source:"compact"}')"
check_marker "SessionStart compact marks" yes
reset; run "$(jq -nc --arg s "$SID" '{hook_event_name:"SessionStart",session_id:$s,source:"wat"}')"
check_marker "SessionStart unknown source marks" yes
reset; run "$(jq -nc --arg s "$SID" '{hook_event_name:"SessionStart",session_id:$s}')"
check_marker "SessionStart missing source marks" yes

reset; run "$(payload x '/session:base')"; run "$(jq -nc --arg s "$SID" '{hook_event_name:"PreCompact",session_id:$s}')"
run "$(jq -nc --arg s "$SID" '{hook_event_name:"SessionStart",session_id:$s,source:"startup"}')"
check "SessionStart startup wipes state" ''
check_marker "SessionStart startup removes marker" no

reset; run "$(payload x '/session:base')"
run "$(jq -nc --arg s "$SID" '{hook_event_name:"PreCompact",session_id:$s}')"
run "$(jq -nc --arg s "$SID" '{hook_event_name:"SessionStart",session_id:$s,source:"resume"}')"
check_marker "SessionStart resume keeps marker" yes
reset; run "$(payload x '/session:base')"
run "$(jq -nc --arg s "$SID" '{hook_event_name:"SessionStart",session_id:$s,source:"resume"}')"
check "SessionStart resume keeps state" '{"base":"base"}'

reset
jq -nc --arg c "look at this: $(cmd base '')" '{type:"assistant",message:{content:$c}}' >"$TR"
jq -nc --arg c "quoted $(cmd base '')" '{type:"user",message:{content:$c}}' >>"$TR"
run "$(tpayload "$TR" 'hello')"
check "quoted command tag seeds nothing" ''

reset
jq -nc --arg c "$(cmd base '')" '{type:"user",message:{content:[{type:"text",text:$c}]}}' >"$TR"
run "$(tpayload "$TR" 'hello')"
check "array content ignored" ''

# Big payloads go to jq through a FILE (--rawfile), never through argv: a few
# hundred KB in a command line blows ARG_MAX on Linux.
# A command inside the slice must seed, one pushed past the cut must not, so the
# case cannot pass by the hook never running.
reset
PADF="$HOME/pad.txt"
head -c 300000 /dev/zero | tr '\0' 'y' >"$PADF"
uline "$(cmd codex '+sol')" >"$TR"
jq -nc --rawfile c "$PADF" '{type:"user",message:{content:$c}}' >>"$TR"
uline "$(cmd base '')" >>"$TR"
run "$(tpayload "$TR" 'hello')"
check "command past the 256KB cap not seeded" '{"codex":"codex+sol"}'

# A pass that could not read the transcript must not block a later seed: the
# real consequence, not just the absent marker.
GOOD_TR="$HOME/good.jsonl"; uline "$(cmd base '')" >"$GOOD_TR"
reset; run "$(tpayload "$HOME/nope.jsonl" 'hello')"
check_marker "missing transcript leaves no marker" no
run "$(tpayload "$GOOD_TR" 'hello again')"
check "missing transcript still reseeds later" '{"base":"base"}'

reset; run "$(jq -nc --arg s "$SID" '{hook_event_name:"UserPromptSubmit",session_id:$s,prompt:"hi"}')"
check_marker "absent transcript_path leaves no marker" no
run "$(tpayload "$GOOD_TR" 'hello again')"
check "absent transcript_path still reseeds later" '{"base":"base"}'

reset; mkdir -p "$HOME/dirpath"; run "$(tpayload "$HOME/dirpath" 'hello')"
check_marker "directory transcript_path leaves no marker" no
run "$(tpayload "$GOOD_TR" 'hello again')"
check "directory transcript_path still reseeds later" '{"base":"base"}'

# A record cut in half by the 256 KB slice must be dropped, not half-parsed.
reset
# a good record first, so the case fails if the hook never ran
uline "$(cmd codex '+sol')" >"$TR"
head -c 262000 /dev/zero | tr '\0' 'z' >"$PADF"
jq -nc --rawfile c "$PADF" '{type:"user",message:{content:$c}}' >>"$TR"
# shrink the pad record until the line before the straddler ends just short of
# the 256 KB cut, so the next record starts inside the slice and is chopped
L=$(wc -c <"$TR" | tr -d ' ')
head -c $((262000 - (L - 262100))) /dev/zero | tr '\0' 'z' >"$PADF"
uline "$(cmd codex '+sol')" >"$TR"
jq -nc --rawfile c "$PADF" '{type:"user",message:{content:$c}}' >>"$TR"
jq -nc --arg c "$(cmd base '')" '{type:"user",message:{content:$c}}' | tr -d '\n' >>"$TR"
printf '\n' >>"$TR"
run "$(tpayload "$TR" 'hello')"
check "record straddling the 256KB cut is dropped" '{"codex":"codex+sol"}'

# A seed still works after SessionStart(startup) cleared the marker.
reset; { uline "$(cmd base '')"; } >"$TR"
run "$(tpayload "$TR" 'hello')"
run "$(jq -nc --arg s "$SID" '{hook_event_name:"SessionStart",session_id:$s,source:"startup"}')"
check_marker "startup clears marker before reseed" no
run "$(tpayload "$TR" 'hello again')"
check "seed works again after startup" '{"base":"base"}'

# PostToolUse alone never seeds.
reset; { uline "$(cmd base '')"; } >"$TR"
run "$(jq -nc --arg s "$SID" --arg t "$TR" '{hook_event_name:"PostToolUse",session_id:$s,transcript_path:$t,tool_name:"Skill",tool_input:{skill:"session:review",args:"lite"}}')"
check "PostToolUse never seeds" '{"review":"review-lite"}'
check_marker "PostToolUse writes no seed marker" no

# A genuine command block whose body quotes a tag later must not seed the quoted one.
reset
jq -nc --arg c "$(cmd base '')
blah blah <command-name>/session:codex</command-name> <command-args>+astra</command-args>" \
  '{type:"user",message:{content:$c}}' >"$TR"
run "$(tpayload "$TR" 'hello')"
check "tag quoted mid-body does not seed" '{"base":"base"}'

# Sidechain and meta entries never seed.
reset
jq -nc --arg c "$(cmd base '')" '{type:"user",isSidechain:true,message:{content:$c}}' >"$TR"
jq -nc --arg c "$(cmd codex '+sol')" '{type:"user",isMeta:true,message:{content:$c}}' >>"$TR"
run "$(tpayload "$TR" 'hello')"
check "sidechain and meta entries do not seed" ''

# A seed pass that cannot parse leaves no marker, and a later prompt retries.
reset
FAKEBIN="$HOME/fakebin"; mkdir -p "$FAKEBIN"
printf '#!/bin/bash\nif [ "$1" = "-R" ]; then exit 5; fi\nexec %s "$@"\n' "$(command -v jq)" >"$FAKEBIN/jq"
chmod +x "$FAKEBIN/jq"
{ uline "$(cmd base '')"; } >"$TR"
printf '%s' "$(tpayload "$TR" 'hello')" | PATH="$FAKEBIN:$PATH" bash "$HOOK" >/dev/null 2>&1
check_marker "failed seed parse leaves no marker" no
run "$(tpayload "$TR" 'hello again')"
check "failed seed parse retries later" '{"base":"base"}'

# No command tag anywhere: mark and skip the parse.
reset
jq -nc '{type:"user",message:{content:"just a plain prompt"}}' >"$TR"
run "$(tpayload "$TR" 'hello')"
check_marker "transcript without tags marks" yes

reset; run "$(payload x '/session:base')"; run "$(jq -nc --arg s "$SID" '{hook_event_name:"PreCompact",session_id:$s}')"
run "$(payload x '/session:base')"
touch -t 200101010101 "$STATE" "$MARKER"
run "$(jq -nc --arg s "$SID" '{hook_event_name:"SessionStart",session_id:$s,source:"resume"}')"
check "prune removes old state" ''
check_marker "prune removes old marker" no

# A session id with a path separator is refused outright.
reset
run "$(jq -nc '{hook_event_name:"UserPromptSubmit",session_id:"../evil",prompt:"/session:base"}')"
TOTAL=$((TOTAL + 1))
if [ ! -e "$HOME/.claude/evil.json" ] && [ ! -d "$HOME/.claude/session-modes" ]; then
  echo "PASS bad session id writes nothing"; PASS=$((PASS + 1))
else
  echo "FAIL bad session id writes nothing"
fi

rm -rf "$HOME"
if [ "$PASS" -eq "$TOTAL" ]; then
  echo "session-modes hook: $PASS/$TOTAL pass"; exit 0
fi
echo "session-modes hook: $PASS/$TOTAL pass, $((TOTAL - PASS)) failed"; exit 1
