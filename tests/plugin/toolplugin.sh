#!/bin/bash
# The tool-plugin template stands on its own: its agent carries a tools line and no model or effort
# key, its workflow has one usage block that the template's own contract printer turns into one
# JSON line with {ROOT} resolved, its plugin.json hooks that printer, and nothing in the template
# names an asset of the session plugin.
set -u
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
T=$REPO/docs/tool-plugin/template
check "template plugin.json valid JSON" python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$T/.claude-plugin/plugin.json"
check "template .mcp.json valid JSON" python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$T/.mcp.json"
for a in "$T"/agents/*.md; do
  fm=$(frontmatter "$a")
  check "$(basename "$a") tools line" grep -Eq '^tools: .+' <<<"$fm"
  check "$(basename "$a") no model or effort key" bash -c '! grep -Eq "^(model|effort):" <<<"$1"' _ "$fm"
done
for w in "$T"/workflows/*.js; do
  check "$(basename "$w") one usage block" test "$(grep -c '^/\* usage:' "$w")" -eq 1
  out=$(sh "$T/bin/contract.sh" "$w" 2>/dev/null)
  check "$(basename "$w") contract.sh prints one JSON line" bash -c 'printf "%s" "$1" | python3 -c "import json,sys; t=sys.stdin.read(); assert t.count(chr(10))<=1; d=json.loads(t); assert d[\"hookSpecificOutput\"][\"hookEventName\"]==\"SessionStart\""' _ "$out"
  check "$(basename "$w") contract.sh resolves {ROOT}" bash -c '! grep -q "{ROOT}" <<<"$1"' _ "$out"
done
check "template names no session plugin asset" bash -c '! grep -rEq "session:|plugins/session|CLAUDE_PLUGIN_ROOT}/../" "$1"' _ "$T"
done_with toolplugin
