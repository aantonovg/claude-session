#!/bin/bash
# The usage block of each workflow: exactly one, right after the meta close, closed by */, 50-150
# tokens, names every A.<arg> the script reads, its first line under 12 words; meta keys and a 1-4
# word description; plugin.json carries one SessionStart hook per workflow plus @user and @project;
# the collector prints one valid JSON line per script; the helper list of helper.js usage equals the
# helpers of classes.json.
set -u
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
PJ=$P/.claude-plugin/plugin.json
COL=$P/bin/workflow-usage.sh
for f in "$P"/workflows/*.js; do
  s=$(basename "$f" .js)
  meta=$(awk '/meta = \{/{m=1} m{print} m&&/^\}/{exit}' "$f")
  end=$(awk '/meta = \{/{m=1} m&&/^\}/{print NR; exit}' "$f")
  desc=$(printf '%s\n' "$meta" | grep -E "^  description:" | sed -E "s/^  description: *['\"](.*)['\"],? *$/\1/")
  w=$(printf '%s' "$desc" | wc -w | tr -d ' ')
  check "$s description 1-4 words (got $w)" test "$w" -ge 1 -a "$w" -le 4
  keys=$(printf '%s\n' "$meta" | grep -oE '^  [A-Za-z]+:' | tr -d ' :' | sort | tr '\n' ' ')
  check "$s meta keys (got $keys)" test "$keys" = "description name phases whenToUse "
  check "$s meta name equals the file stem" grep -Eq "^  name: '$s'," <<<"$meta"
  cnt=$(grep -c '^/\* usage:' "$f")
  check "$s exactly one usage block (got $cnt)" test "$cnt" -eq 1
  start=$(grep -n '^/\* usage:' "$f" | head -1 | cut -d: -f1)
  check "$s usage block right after meta close" test "${start:-0}" = "$((end + 1))"
  block=$(awk 'f==0&&/^\/\* usage:/{f=1} f{print} f&&/\*\//{exit}' "$f")
  check "$s usage block closed" bash -c 'printf "%s\n" "$1" | tail -1 | grep -q "\*/"' _ "$block"
  t=$(printf '%s' "$block" | sed -e 's#^/\* usage:##' -e 's#\*/##' | tokens)
  check "$s usage 50-150 tokens (got $t)" test "$t" -ge 50 -a "$t" -le 150
  first=$(printf '%s\n' "$block" | sed -n 2p)
  fw=$(printf '%s' "$first" | wc -w | tr -d ' ')
  check "$s usage first line under 12 words (got $fw)" test "$fw" -le 12
  for a in $(grep -oE '\bA\.[a-z]+' "$f" | sort -u | sed 's/^A\.//'); do
    check "$s usage names arg $a" grep -qE "(^|[ (,])$a([ ,)]|$)" <<<"$block"
  done
  check "$s usage has Out: and Use: lines" bash -c 'grep -q "^Out: " <<<"$1" && grep -q "^Use: " <<<"$1"' _ "$block"
  check "$s carries the shared block markers" bash -c 'grep -q "^// ---- shared block" "$1" && grep -q "^// ---- end shared block" "$1"' _ "$f"
  check "$s launches by agentType from helperOpts" grep -q 'agentType: O.agentType' "$f"
  check "$s passes model and effort explicitly" grep -q 'model: O.model, effort: O.effort, label: O.label' "$f"
  check "$s validates an absolute out" grep -q "startsWith('/')" "$f"
  cmd="sh \${CLAUDE_PLUGIN_ROOT}/bin/workflow-usage.sh --hook --file \${CLAUDE_PLUGIN_ROOT}/workflows/$s.js --prefix session"
  check "$s SessionStart hook in plugin.json" python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); cs=[h["command"] for e in d["hooks"]["SessionStart"] for h in e["hooks"]]; sys.exit(0 if cs.count(sys.argv[2])==1 else 1)' "$PJ" "$cmd"
  out=$(cd "$REPO" && env -u CLAUDE_PROJECT_DIR sh "$COL" --hook --file "$f" --prefix session)
  check "$s collector prints one JSON line" bash -c 'printf "%s" "$1" | python3 -c "import json,sys; t=sys.stdin.read(); assert t.count(chr(10))<=1; d=json.loads(t); assert d[\"hookSpecificOutput\"][\"hookEventName\"]==\"SessionStart\"; assert \"Workflow session:$2 (launch by name; contract below; never read the script body): \" in d[\"hookSpecificOutput\"][\"additionalContext\"]"' _ "$out" "$s"
done
check "plugin.json @user and @project hooks once each" python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); cs=[h["command"] for e in d["hooks"]["SessionStart"] for h in e["hooks"]]; sys.exit(0 if sum(c.endswith("--dir @user") for c in cs)==1 and sum(c.endswith("--dir @project") for c in cs)==1 else 1)' "$PJ"
check "plugin.json names no retired workflow hook" bash -c '! grep -Eq "workflows/(role|chain|make|probe)\.js" "$1"' _ "$PJ"
check "plugin.json has no SubagentStop hook" bash -c '! grep -q SubagentStop "$1"' _ "$PJ"
check "plugin.json version equals marketplace version" python3 -c 'import json,sys; v=json.load(open(sys.argv[1]))["version"]; m=[p["version"] for p in json.load(open(sys.argv[2]))["plugins"] if p["name"]=="session"]; sys.exit(0 if m==[v] else 1)' "$PJ" "$REPO/.claude-plugin/marketplace.json"
want=$(node -e 'const c=require(process.argv[1]); console.log(Object.keys(c.helpers).join(" "))' "$P/lib/classes.json")
got=$(awk '/^helper \(required\): /{sub(/^helper \(required\): /, ""); print; exit}' "$P/workflows/helper.js")
check "helper.js usage lists the helpers of classes.json in order (got: $got)" test "$got" = "$want"
check "batch.js usage requires {item}" grep -q '{item}' "$P/workflows/batch.js"
if command -v claude >/dev/null 2>&1; then
  check "claude plugin validate plugins/session" bash -c 'claude plugin validate "$1" >/dev/null 2>&1' _ "$P"
fi
done_with contracts
