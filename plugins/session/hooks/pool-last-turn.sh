#!/bin/bash
# Stop hook for pool workers: records the time of the worker's last turn.
#
# poold decides when to keep-warm a worker from this mark (45-50 minutes after
# the last turn, before the 1-hour prompt cache expires). The daemon starts every
# worker with POOL_LAST_TURN_DIR in its environment; a session without that
# variable (any ordinary session) exits at once, so the hook is safe for every
# session. It is registered by the `session` plugin itself (plugin.json, Stop
# hooks); nothing is added to ~/.claude/settings.json by hand.
#
# Input: the hook JSON on stdin (uses `session_id`). Output: none.

[ -n "$POOL_LAST_TURN_DIR" ] || exit 0
INPUT=$(cat)
SID=$(printf '%s' "$INPUT" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ -n "$SID" ] || exit 0
mkdir -p "$POOL_LAST_TURN_DIR" 2>/dev/null
touch "$POOL_LAST_TURN_DIR/$SID" 2>/dev/null
exit 0
