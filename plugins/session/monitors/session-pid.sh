#!/bin/sh
# Prints the pause-file paths for the current Claude Code session, one per line.
# Both the plugin monitor and the Bash tool shell are children of the same
# claude process, so the ancestor walk yields the same pid in both.
# When CLAUDE_SESSION_ID is exported, a second path keyed by it is printed too.
dir="${TMPDIR:-/tmp}"; dir="${dir%/}"
pid=$$
claude_pid=""
while [ "$pid" -gt 1 ] 2>/dev/null; do
  pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
  [ -n "$pid" ] || break
  comm=$(ps -o comm= -p "$pid" 2>/dev/null)
  case "$comm" in
    *claude*) claude_pid=$pid; break ;;
  esac
done
[ -n "$claude_pid" ] && echo "$dir/session-ping-pause-$claude_pid"
[ -n "$CLAUDE_SESSION_ID" ] && echo "$dir/session-ping-pause-$CLAUDE_SESSION_ID"
exit 0
