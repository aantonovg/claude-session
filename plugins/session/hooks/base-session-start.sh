#!/bin/sh
# SessionStart hook: injects the session base (base/BASE.md: tools, cache, waits, models,
# roles, launch forms) into every session at startup, resume, compact and clear, so the
# base is never a skill to invoke. Output: one hookSpecificOutput JSON with additionalContext.
DIR=$(cd "$(dirname "$0")/.." && pwd)
BASE="$DIR/base/BASE.md"
[ -f "$BASE" ] || exit 0
python3 - "$BASE" <<'PY'
import json, sys
text = open(sys.argv[1], encoding='utf-8').read()
print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": text}}))
PY
exit 0
