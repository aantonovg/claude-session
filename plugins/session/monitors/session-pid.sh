#!/bin/sh
# Prints the pause-file path for the current Claude Code session.
# Both the plugin monitor and the Bash tool shell are children of the same
# claude process, so the ancestor walk yields the same pid in both.
# The claude pid is the only key: it is stable across /clear and /compact.
# SESSION_PID_TEST overrides that key; test use only (tests/monitors/ping-test.sh),
# so the test runs with or without a claude ancestor.
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
[ -n "${SESSION_PID_TEST:-}" ] && claude_pid=$SESSION_PID_TEST
[ -n "$claude_pid" ] && echo "$dir/session-ping-pause-$claude_pid"
exit 0
