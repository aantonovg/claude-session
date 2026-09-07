#!/bin/bash
# Records which session:* skills are loaded in a session, for the statusline.
# Hooked into UserPromptSubmit, PostToolUse (Skill), PreCompact, SessionStart.
#
# User-typed slash commands are NOT Skill tool calls: the harness puts them into
# the prompt, so UserPromptSubmit is the only place their name and argument are
# visible. Two payload shapes exist. Interactive sessions send the prompt
# verbatim ("/session:codex +astra"). Background-job sessions send the command
# already expanded, starting with a tag block:
#   <command-message>session:codex</command-message>
#   <command-name>/session:codex</command-name>
#   <command-args>+astra</command-args>
# (the args tag may be absent, and the whole skill body may follow). Both shapes
# are handled. Model-invoked skills do produce a Skill tool call, hence the
# PostToolUse branch.
#
# State: ~/.claude/session-modes/<session_id>.json, one key per skill, last wins.
# Marker: ~/.claude/session-modes/<session_id>.seeded means the one-time seed for
# this session is done, or deliberately suppressed. A prompt with no marker reads
# the head of the transcript once and replays the session commands it finds, so a
# session whose opening commands were missed still shows its modes. Every event
# that wipes the state also writes the marker, so the seed cannot resurrect what
# was just cleared - except SessionStart(startup), where the id is fresh and a
# later seed must stay possible. A resume changes nothing: it replays the
# transcript, so the recorded modes are still true.

INPUT=$(cat)
command -v jq >/dev/null 2>&1 || exit 0

EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)

STATE_DIR="$HOME/.claude/session-modes"
[ -z "$SESSION_ID" ] && exit 0
# The id goes straight into a path, so anything but [A-Za-z0-9._-] is refused:
# a "/" or ".." would write outside the state dir and the prune would follow it.
case "$SESSION_ID" in
  *[!A-Za-z0-9._-]*) exit 0 ;;
esac
STATE="$STATE_DIR/${SESSION_ID}.json"
MARKER="$STATE_DIR/${SESSION_ID}.seeded"

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

mark() { mkdir -p "$STATE_DIR" 2>/dev/null && : >"$MARKER" 2>/dev/null; return 0; }
wipe() { rm -f "$STATE" 2>/dev/null; return 0; }

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

# Reads the head of the transcript once and rebuilds the state from the session
# commands recorded in it. Transcript text is untrusted, so only user entries
# whose content is a string that STARTS WITH a command tag count - the same tags
# quoted inside assistant text or a tool result must never seed anything. Every
# value goes through --arg, never through eval or a jq filter string.
seed() {
  local tp
  tp=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
  # No usable transcript: do nothing and leave the marker unwritten, so a later
  # prompt can retry. The retry costs one stat, not a re-parse.
  [ -n "$tp" ] || return 0
  [ -f "$tp" ] && [ -r "$tp" ] || return 0

  # The trailing 'X' turns the possibly-partial last line of the 256 KB slice
  # into its own line, which sed then drops; a slice that ended on a newline
  # keeps every whole record.
  local slice
  slice=$( { head -c 262144 "$tp" 2>/dev/null; printf 'X'; } | sed '$d' )
  # Cheap fixed-string pre-check: no command tag at all means nothing to parse.
  # It only SKIPS - it must not mark: the commands may simply not have reached
  # the first 256 KB yet, and a marker here would freeze the miss for the whole
  # session. Only a pass that really parsed may write the marker.
  printf '%s\n' "$slice" | grep -q '<command-name>/session:' || return 0

  # Only a string-shaped .message.content is read. Every observed transcript uses
  # that shape; an array-shaped content is ignored on purpose (verified, not a bug).

  local out rc
  out=$(printf '%s\n' "$slice" | jq -R -r '
      fromjson?
      | select(type == "object")
      | select(.type == "user")
      | select(.isSidechain != true and .isMeta != true)
      | .message.content
      | select(type == "string")
      | select(startswith("<command-message>") or startswith("<command-name>"))
      | (capture("(?:^|\n)<command-name>/session:(?<s>[^<\n]*)</command-name>(?:\n<command-args>(?<a>[^<\n]*)</command-args>)?(?:\n|$)")?)
      | select(. != null)
      | [.s, (.a // "")] | @tsv' 2>/dev/null )
  rc=$?
  # A failed parse (broken jq, no oniguruma) must leave no marker, so a later
  # prompt can retry.
  [ "$rc" -eq 0 ] || return 0

  local acc='{}' s a m
  while IFS=$'\t' read -r s a; do
    [ -n "$s" ] || continue
    a=$(printf '%s' "$a" | awk '{$1=$1; print}')
    if [ "$s" = "reset-counter" ]; then acc='{}'; continue; fi
    m=$(mode_valid "$s" "$a")
    [ -n "$m" ] || continue
    acc=$(printf '%s' "$acc" | jq -c --arg k "$s" --arg v "$m" '. + {($k): $v}' 2>/dev/null)
    [ -n "$acc" ] || acc='{}'
  done < <( printf '%s\n' "$out" )

  mkdir -p "$STATE_DIR" 2>/dev/null || return 0
  # Merge, never overwrite: a state file written by real hook events is the more
  # authoritative source, so on a key collision the EXISTING value wins over the
  # seeded one. An empty or unparseable state file counts as {}.
  if [ "$acc" != "{}" ]; then
    local cur merged
    cur=$(cat "$STATE" 2>/dev/null)
    printf '%s' "$cur" | jq -e 'type == "object"' >/dev/null 2>&1 || cur='{}'
    merged=$(printf '%s\n%s\n' "$acc" "$cur" | jq -c -s '.[0] + .[1]' 2>/dev/null)
    [ -n "$merged" ] || merged=$acc
    printf '%s\n' "$merged" >"$STATE.tmp" 2>/dev/null && mv -f "$STATE.tmp" "$STATE" 2>/dev/null
    rm -f "$STATE.tmp" 2>/dev/null
  fi
  # A completed pass always marks, even when it found nothing.
  : >"$MARKER" 2>/dev/null
  return 0
}

case "$EVENT" in
  UserPromptSubmit)
    # A slash command sits only at the very start, in either shape, so only the
    # first 4000 bytes are ever inspected - the skill body can be tens of KB.
    head=$(echo "$INPUT" | jq -r '.prompt // empty' 2>/dev/null | head -c 4000)
    first=$(printf '%s' "$head" | head -n1)
    skill=""; args=""
    case "$first" in
      /session:*)                       # verbatim shape
        rest=${first#/session:}
        skill=${rest%% *}
        if [ "$skill" = "$rest" ]; then args=""; else args=${rest#* }; fi ;;
      *)                                # expanded shape: read the tag block
        skill=$(printf '%s\n' "$head" \
          | sed -n 's|^<command-name>/session:\([^<]*\)</command-name>$|\1|p' | head -n1)
        args=$(printf '%s\n' "$head" \
          | sed -n 's|^<command-args>\(.*\)</command-args>$|\1|p' | head -n1) ;;
    esac
    # trim surrounding whitespace from the argument
    args=$(printf '%s' "$args" | awk '{$1=$1; print}')
    if [ "$skill" = "reset-counter" ]; then wipe; mark; exit 0; fi
    [ -f "$MARKER" ] || seed
    [ -n "$skill" ] && record "$skill" "$args" ;;
  PostToolUse)
    tool=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
    [ "$tool" = "Skill" ] || exit 0
    skill=$(echo "$INPUT" | jq -r '.tool_input.skill // empty' 2>/dev/null)
    args=$(echo "$INPUT" | jq -r '.tool_input.args // empty' 2>/dev/null)
    case "$skill" in
      session:reset-counter) wipe; mark ;;
      session:*) record "${skill#session:}" "$args" ;;
    esac ;;
  PreCompact)
    wipe; mark ;;
  SessionStart)
    src=$(echo "$INPUT" | jq -r '.source // empty' 2>/dev/null)
    case "$src" in
      resume) ;;                        # transcript replayed, modes still true
      startup) wipe; rm -f "$MARKER" 2>/dev/null ;;  # fresh id, seed stays possible
      *) wipe; mark ;;                  # compact, clear, unknown, missing
    esac
    # State and marker expire together, so an old marker never blocks a rebuild.
    find "$STATE_DIR" -type f -mtime +7 -delete 2>/dev/null ;;
esac
exit 0
