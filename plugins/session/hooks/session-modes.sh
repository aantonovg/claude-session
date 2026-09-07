#!/bin/bash
# Records which session:* skills are loaded in a session, for the statusline.
# Hooked into UserPromptSubmit, PostToolUse (Skill), PreCompact, SessionStart.
#
# User-typed slash commands are NOT Skill tool calls: the harness expands them
# into the prompt, so UserPromptSubmit is the only place their name and argument
# are visible (verbatim, e.g. "/session:codex +astra"). Model-invoked skills do
# produce a Skill tool call, hence the PostToolUse branch. PreCompact and
# SessionStart clear the state: after a compaction the skills are gone from
# context, so the statusline must stop claiming them.
#
# State: ~/.claude/session-modes/<session_id>.json, one key per skill, last wins.

INPUT=$(cat)
command -v jq >/dev/null 2>&1 || exit 0

EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)

STATE_DIR="$HOME/.claude/session-modes"
[ -z "$SESSION_ID" ] && exit 0
STATE="$STATE_DIR/${SESSION_ID}.json"

# "codex" "+astra" -> codex+astra ; "pipeline" "full" -> pipeline-full ; "base" "" -> base
mode_fmt() {
  if [ -z "$2" ]; then printf '%s' "$1"; return; fi
  case "$2" in +*) printf '%s%s' "$1" "$2" ;; *) printf '%s-%s' "$1" "$2" ;; esac
}

# Validates <skill> <args>; prints the rendered mode, or nothing when invalid.
mode_valid() {
  case "$1" in
    base) printf 'base' ;;
    codex)
      case "$2" in
        "") printf 'codex' ;;
        luna|terra|sol|astra|+sol|+astra|\
sol-luna|sol-terra|astra-luna|astra-terra|\
+sol-luna|+sol-terra|+astra-luna|+astra-terra) mode_fmt codex "$2" ;;
      esac ;;
    pipeline)
      case "$2" in
        "") printf 'pipeline' ;;
        fast|standard|full) mode_fmt pipeline "$2" ;;
      esac ;;
    review)
      case "$2" in
        "") printf 'review' ;;
        lite|std|full|re) mode_fmt review "$2" ;;
      esac ;;
  esac
}

record() {  # $1 skill, $2 args
  local mode; mode=$(mode_valid "$1" "$2")
  [ -z "$mode" ] && return 0
  mkdir -p "$STATE_DIR" 2>/dev/null || return 0
  local cur; cur=$(cat "$STATE" 2>/dev/null); [ -z "$cur" ] && cur='{}'
  printf '%s' "$cur" \
    | jq -c --arg k "$1" --arg v "$mode" '. + {($k): $v}' >"$STATE.tmp" 2>/dev/null \
    && mv -f "$STATE.tmp" "$STATE" 2>/dev/null
  rm -f "$STATE.tmp" 2>/dev/null
  return 0
}

case "$EVENT" in
  UserPromptSubmit)
    # Prefix test only: a slash command can sit only at the very start, so a
    # long prompt is never scanned.
    prompt=$(echo "$INPUT" | jq -r '.prompt // empty' 2>/dev/null | head -n1)
    case "$prompt" in
      /session:reset-counter*) rm -f "$STATE" 2>/dev/null ;;
      /session:*)
        rest=${prompt#/session:}
        skill=${rest%% *}
        if [ "$skill" = "$rest" ]; then args=""; else args=${rest#* }; fi
        # trim surrounding whitespace from the argument
        args=$(printf '%s' "$args" | awk '{$1=$1; print}')
        record "$skill" "$args" ;;
    esac ;;
  PostToolUse)
    tool=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
    [ "$tool" = "Skill" ] || exit 0
    skill=$(echo "$INPUT" | jq -r '.tool_input.skill // empty' 2>/dev/null)
    args=$(echo "$INPUT" | jq -r '.tool_input.args // empty' 2>/dev/null)
    case "$skill" in
      session:*) record "${skill#session:}" "$args" ;;
    esac ;;
  PreCompact)
    rm -f "$STATE" 2>/dev/null ;;
  SessionStart)
    rm -f "$STATE" 2>/dev/null
    find "$STATE_DIR" -type f -name '*.json' -mtime +7 -delete 2>/dev/null ;;
esac
exit 0
