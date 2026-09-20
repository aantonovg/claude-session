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
CAP=110
# TOOLPLUGIN=<root> runs the same checks against another plugin's root (P7: the tool plugin
# template and the stub fixture are plugins of their own and pass this oracle with their own root).
# In that mode the workflow list, the launch prefix and the hook command all come from that root,
# and no path of this repo's plugin is read.
FOREIGN=${TOOLPLUGIN:-}
if [ -n "$FOREIGN" ]; then
  P=$FOREIGN
  PJ=$P/.claude-plugin/plugin.json
  [ -f "$PJ" ] || { echo "contracts: FAIL no plugin.json under $P"; exit 1; }
  PREFIX=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["name"])' "$PJ")
  NEW=$(for f in "$P"/workflows/*.js; do [ -f "$f" ] && basename "$f" .js; done)
else
  P=$REPO/plugins/session
  PJ=$P/.claude-plugin/plugin.json
  PREFIX=session
  NEW="role chain make probe"
fi

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

  # ---- plugin.json: exactly one SessionStart entry, and that very command prints one line ----
  # The command read out of plugin.json is the one that runs: the entry a session uses and the
  # line this test judges are the same thing, in this plugin and in a tool plugin alike.
  cmd=$(python3 -c '
import json, sys
groups = json.load(open(sys.argv[1]))["hooks"]["SessionStart"]
c = [h.get("command", "") for g in groups for h in g["hooks"] if ("workflows/%s.js" % sys.argv[2]) in h.get("command", "")]
print(c[0] if len(c) == 1 else "")
' "$PJ" "$w")
  check "n4 $w exactly one SessionStart entry naming workflows/$w.js" test -n "$cmd"
  if [ -z "$FOREIGN" ]; then
    want="sh \${CLAUDE_PLUGIN_ROOT}/bin/workflow-usage.sh --hook --file \${CLAUDE_PLUGIN_ROOT}/workflows/$w.js --prefix session"
    check "n4 $w SessionStart entry has the collector form" test "$cmd" = "$want"
  fi
  [ -n "$cmd" ] || continue
  (cd "$T" && env -u CLAUDE_PROJECT_DIR HOME="$T" CLAUDE_PLUGIN_ROOT="$P" sh -c "$cmd" > "$T/$w.out" 2> "$T/$w.err"); rc=$?
  check "n4 $w hook command exit 0" test "$rc" -eq 0
  check "n4 $w hook command no stderr" test ! -s "$T/$w.err"
  check "n4 $w hook command prints exactly one contract line naming $PREFIX:$w" python3 -c '
import json, sys
raw = open(sys.argv[1], encoding="utf-8").read()
assert raw.strip("\n") and "\n" not in raw.rstrip("\n"), "not one line"
c = json.loads(raw)["hookSpecificOutput"]["additionalContext"]
assert c.startswith("Workflow %s:%s " % (sys.argv[3], sys.argv[2])), c[:60]
assert "\n" not in c, "contract line holds a newline"
' "$T/$w.out" "$w" "$PREFIX"
done

check "n0 at least one new workflow exists (got $found)" test "$found" -ge 1

# ---- every path a SessionStart entry names inside the plugin exists on disk ----
# Every token of a command that starts at ${CLAUDE_PLUGIN_ROOT} is a file of this plugin: the
# script that runs, the workflow file it reads. A missing one is a hook that prints nothing at
# session start, in this plugin and in a tool plugin alike.
check "n5 every SessionStart entry names existing files of the plugin" python3 -c '
import json, os, sys
pj, plugin = sys.argv[1], sys.argv[2]
bad = []
for g in json.load(open(pj))["hooks"]["SessionStart"]:
    for h in g["hooks"]:
        for tok in h.get("command", "").split():
            if not tok.startswith("${CLAUDE_PLUGIN_ROOT}"):
                continue
            path = tok.replace("${CLAUDE_PLUGIN_ROOT}", plugin)
            if not os.path.exists(path):
                bad.append(path)
if bad:
    print("missing:", " ".join(bad))
sys.exit(1 if bad else 0)
' "$PJ" "$P"

if [ "$FAILS" -eq 0 ]; then echo "contracts: PASS $N"; exit 0; fi
echo "contracts: FAIL $FAILS failures, $N checks passed"
exit 1
