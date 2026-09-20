#!/bin/bash
# Static oracle of P2: every new workflow is launchable by name from its contract alone.
# Globs: plugins/session/workflows/{role,chain,make,probe}.js,
#        plugins/session/.claude-plugin/plugin.json.
# Proves: each new workflow carries exactly one usage block, under 110 words (A6), right after its
# meta block; each has exactly one SessionStart entry in plugin.json; the collector really prints
# one contract line for it; every SessionStart --file entry points at a file that exists; no
# contract names a model or a reasoning level (the class table is the only source).
# A workflow of a later part is skipped, so this test lives from P2 on; it fails when none of the
# four exists, so it can never pass over an empty set. Temp dirs only, no network, under 10 s.
set -u

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
P=$REPO/plugins/session
PJ=$P/.claude-plugin/plugin.json
COLLECTOR=$P/bin/workflow-usage.sh
NEW="role chain make probe"
CAP=110

T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT

N=0; FAILS=0
pass() { N=$((N + 1)); }
fail() { echo "FAIL $1"; FAILS=$((FAILS + 1)); }
check() { local label=$1; shift; if "$@"; then pass; else fail "$label"; fi; }

found=0
for w in $NEW; do
  f=$P/workflows/$w.js
  [ -f "$f" ] || continue
  found=$((found + 1))

  # ---- the meta block: the launch name and the 1-4 word label ----
  meta=$(awk '/meta = \{/{m=1} m{print} m&&/^\}/{exit}' "$f")
  end=$(awk '/meta = \{/{m=1} m&&/^\}/{print NR; exit}' "$f")
  keys=$(printf '%s\n' "$meta" | grep -oE '^  [A-Za-z]+:' | tr -d ' :' | sort | tr '\n' ' ')
  check "n1 $w meta keys (got $keys)" test "$keys" = "description name phases whenToUse "
  check "n1 $w meta name equals the file stem" grep -Eq "^  name: '$w'," <<<"$meta"
  desc=$(printf '%s\n' "$meta" | grep -E "^  description:" | sed -E "s/^  description: *['\"](.*)['\"],? *$/\1/")
  dw=$(printf '%s' "$desc" | wc -w | tr -d ' ')
  check "n1 $w description 1-4 words (got $dw)" test "$dw" -ge 1 -a "$dw" -le 4

  # ---- the usage block: one per script, right after meta, closed, non-empty, under the cap ----
  cnt=$(grep -c '^/\* usage:' "$f")
  check "n2 $w exactly one /* usage: line (got $cnt)" test "$cnt" -eq 1
  start=$(grep -n '^/\* usage:' "$f" | head -1 | cut -d: -f1)
  check "n2 $w usage block right after meta close" test "${start:-0}" = "$((end + 1))"
  block=$(awk 'f==0&&/^\/\* usage:/{f=1} f{print} f&&/\*\//{exit}' "$f")
  closed=$(printf '%s\n' "$block" | tail -1 | grep -c '\*/')
  check "n2 $w usage block closed by */" test "$closed" -eq 1
  inner=$(printf '%s\n' "$block" | sed -e 's#^/\* usage:##' -e 's#\*/##')
  check "n2 $w usage block non-empty" test -n "$(printf '%s' "$inner" | tr -d ' \n\t')"
  words=$(printf '%s\n' "$inner" | wc -w | tr -d ' ')
  check "n2 $w usage under $CAP words (got $words)" test "$words" -lt "$CAP"

  # ---- the contract names no model and no reasoning level (A9: the class table is the source) ----
  check "n3 $w contract names no model" bash -c '! grep -Eqi "(^|[^-a-z])(opus|sonnet|fable|haiku)([^-a-z]|$)" <<<"$1"' _ "$inner"
  check "n3 $w contract names no reasoning level or tier" bash -c '! grep -Eqi "\b(effort|tier)\b" <<<"$1"' _ "$inner"

  # ---- plugin.json: exactly one SessionStart entry, and the collector prints one line for it ----
  want="sh \${CLAUDE_PLUGIN_ROOT}/bin/workflow-usage.sh --hook --file \${CLAUDE_PLUGIN_ROOT}/workflows/$w.js --prefix session"
  hits=$(python3 -c '
import json, sys
groups = json.load(open(sys.argv[1]))["hooks"]["SessionStart"]
print(sum(1 for g in groups for h in g["hooks"] if h.get("command", "") == sys.argv[2]))
' "$PJ" "$want")
  check "n4 $w exactly one SessionStart entry in plugin.json (got $hits)" test "$hits" = 1
  (cd "$REPO" && env -u CLAUDE_PROJECT_DIR HOME="$T" sh "$COLLECTOR" --hook --file "$f" --prefix session > "$T/$w.out" 2> "$T/$w.err"); rc=$?
  check "n4 $w collector exit 0" test "$rc" -eq 0
  check "n4 $w collector no stderr" test ! -s "$T/$w.err"
  check "n4 $w collector prints exactly one contract line naming session:$w" python3 -c '
import json, sys
raw = open(sys.argv[1], encoding="utf-8").read()
assert raw.strip("\n") and "\n" not in raw.rstrip("\n"), "not one line"
c = json.loads(raw)["hookSpecificOutput"]["additionalContext"]
assert c.startswith("Workflow session:%s " % sys.argv[2]), c[:60]
assert "\n" not in c, "contract line holds a newline"
' "$T/$w.out" "$w"
done

check "n0 at least one new workflow exists (got $found)" test "$found" -ge 1

# ---- every SessionStart --file entry of plugin.json points at a file that exists ----
check "n5 every SessionStart --file entry names an existing file" python3 -c '
import json, os, sys
pj, plugin = sys.argv[1], sys.argv[2]
bad = []
for g in json.load(open(pj))["hooks"]["SessionStart"]:
    for h in g["hooks"]:
        c = h.get("command", "")
        if "workflow-usage.sh" not in c or "--file" not in c:
            continue
        path = c.split("--file", 1)[1].split()[0].replace("${CLAUDE_PLUGIN_ROOT}", plugin)
        if not os.path.exists(path):
            bad.append(path)
if bad:
    print("missing:", " ".join(bad))
sys.exit(1 if bad else 0)
' "$PJ" "$P"

if [ "$FAILS" -eq 0 ]; then echo "contracts: PASS $N"; exit 0; fi
echo "contracts: FAIL $FAILS failures, $N checks passed"
exit 1
