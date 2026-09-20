#!/bin/bash
# Static oracle of P7: the tool plugin pattern (A8) and the environment every behavior run starts in.
# Globs: docs/tool-plugin/**, tests/rebuild/fixtures/tool-stub/**, tests/rebuild/scenario-env.sh.
# Proves:
#   - the template and the stub are plugins of their own: they pass the contracts.sh and agents.sh
#     checks against their own root (TOOLPLUGIN=<root>), and neither names a path, an agent, a
#     workflow, a skill or a hook of the base plugin (A8: nothing outside a plugin names a carrier
#     a project can deny or disable);
#   - the stub's SessionStart hook command, run directly in a shell with CLAUDE_PLUGIN_ROOT set,
#     prints exactly one contract line — no session needed;
#   - the stub carries a capability the base set lacks: a metrics store holding a number that
#     exists nowhere else in the tree and nowhere in the scenario text, so scenario 2 can only be
#     answered through the stub;
#   - scenario-env.sh builds every variant (base, stub-on, stub-off-deny) with and without
#     --hide-old into an empty directory, and every --hide-old build holds no old contract entry
#     and no old process skill.
# Temp dirs only, no network, no session, no HOME write, under 60 s.
set -u

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
HERE=$REPO/tests/rebuild
DOC=$REPO/docs/tool-plugin
TPL=$DOC/template
STUB=$HERE/fixtures/tool-stub
ENVSH=$HERE/scenario-env.sh
OLD_WF="build dev research review-fix translate-ru"
OLD_SKILLS="pipeline review"

T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT

N=0; FAILS=0
pass() { N=$((N + 1)); }
fail() { echo "FAIL $1"; FAILS=$((FAILS + 1)); }
check() { local label=$1; shift; if "$@"; then pass; else fail "$label"; fi; }

json() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2], ""))' "$1" "$2"; }

# ---- t1: both roots carry the whole plugin shape ----
for root in "$TPL" "$STUB"; do
  b=$(basename "$root")
  check "t1 $b .claude-plugin/plugin.json exists" test -f "$root/.claude-plugin/plugin.json"
  check "t1 $b plugin.json is JSON with name, version, description and a SessionStart hook" python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
for k in ("name", "version", "description"):
    assert isinstance(d.get(k), str) and d[k].strip(), k
groups = d["hooks"]["SessionStart"]
assert sum(len(g["hooks"]) for g in groups) >= 1
' "$root/.claude-plugin/plugin.json"
  # U2: a permissions block in a plugin.json does nothing, so neither carrier carries one
  check "t1 $b plugin.json carries no permissions key (U2: it has no effect)" python3 -c '
import json, sys
sys.exit(1 if "permissions" in json.load(open(sys.argv[1])) else 0)' "$root/.claude-plugin/plugin.json"
  check "t1 $b has at least one workflow" bash -c 'ls "$1"/workflows/*.js >/dev/null 2>&1' _ "$root"
  check "t1 $b has at least one tool-set agent" bash -c 'ls "$1"/agents/tools-*.md >/dev/null 2>&1' _ "$root"
  check "t1 $b carries its own contract script" test -f "$root/bin/contract.sh"
done
check "t1 the template carries an .mcp.json (the server it is built around)" test -f "$TPL/.mcp.json"
check "t1 the stub carries no .mcp.json (no real server)" test ! -f "$STUB/.mcp.json"

# ---- t2: the README says what a tool plugin carries, where it lives, how it is switched ----
R=$DOC/README.md
check "t2 docs/tool-plugin/README.md exists" test -f "$R"
if [ -f "$R" ]; then
  for s in ".mcp.json" "agents/" "workflows/" ".claude-plugin/plugin.json" "SessionStart" \
           "enabledPlugins" "user level" "Artifact" "DesignSync" "permissions" "deny"; do
    check "t2 README names $s" grep -qF -- "$s" "$R"
  done
  check "t2 README names the artifact pair as the first candidate to move out" grep -qiE 'candidate' "$R"
  check "t2 README points at the template tree" grep -qF "docs/tool-plugin/template" "$R"
fi

# ---- t3: each root passes the contract and agent oracles with its own root ----
for root in "$TPL" "$STUB"; do
  b=$(basename "$root")
  for t in contracts agents; do
    TOOLPLUGIN=$root bash "$HERE/$t.sh" > "$T/$b-$t.out" 2>&1; rc=$?
    check "t3 $b passes $t.sh with its own root ($(tail -1 "$T/$b-$t.out"))" test "$rc" -eq 0
  done
done

# ---- t4: A8, neither root names anything of the base plugin ----
cat > "$T/forbidden.txt" <<'PAT'
plugins/session
workflow-usage.sh
lib/block.js
lib/classes.json
build-manifest.json
hooks/modes.sh
ledger-stop.sh
skills/process
skills/pipeline
skills/review
tools-read-write
tools-read-bash
tools-edit
tools-web
session-modes
PAT
# the whole documentation tree, not only the template inside it: the README explains the pattern
# without naming a carrier of the base plugin either, or the first plugin copied from it inherits
# the dependency the pattern forbids.
for root in "$DOC" "$STUB"; do
  b=$(basename "$root")
  hits=$(grep -rlF -f "$T/forbidden.txt" "$root" 2>/dev/null | tr '\n' ' ')
  check "t4 $b names no path, agent, workflow, skill or hook of the base plugin (hits: $hits)" test -z "$hits"
  # the launch name of a carrier, qualified form only: "the session:" of ordinary prose is no name
  qual=$(grep -rlE 'session:[a-z]' "$root" 2>/dev/null | tr '\n' ' ')
  check "t4 $b names no workflow or agent of the base plugin by its launch name (hits: $qual)" test -z "$qual"
done

# ---- t5: the stub's SessionStart hook command prints one contract line, no session needed ----
STUB_PJ=$STUB/.claude-plugin/plugin.json
CMD=$(python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
cmds = [h["command"] for g in d["hooks"]["SessionStart"] for h in g["hooks"]]
print(cmds[0] if len(cmds) == 1 else "")
' "$STUB_PJ" 2>/dev/null)
check "t5 the stub has exactly one SessionStart hook command" test -n "$CMD"
if [ -n "$CMD" ]; then
  (cd "$T" && env -u CLAUDE_PROJECT_DIR HOME="$T" CLAUDE_PLUGIN_ROOT="$STUB" sh -c "$CMD" > "$T/stub.out" 2> "$T/stub.err"); rc=$?
  check "t5 stub hook command exit 0" test "$rc" -eq 0
  check "t5 stub hook command writes no stderr" test ! -s "$T/stub.err"
  check "t5 stub hook command prints exactly one contract line" python3 -c '
import json, sys
raw = open(sys.argv[1], encoding="utf-8").read()
assert raw.strip("\n") and "\n" not in raw.rstrip("\n"), "not one line"
c = json.loads(raw)["hookSpecificOutput"]["additionalContext"]
assert c.startswith("Workflow %s:" % sys.argv[2]), c[:60]
assert "\n" not in c, "contract line holds a newline"
' "$T/stub.out" "$(json "$STUB_PJ" name)"
  # the store lives inside the plugin, so the line the session reads names its absolute path
  check "t5 the contract line names the stub's store by absolute path" grep -qF "$STUB/data/metrics.txt" "$T/stub.out"
fi

# ---- t6: the capability the base set lacks ----
STORE=$STUB/data/metrics.txt
check "t6 the stub carries a metrics store" test -s "$STORE"
if [ -s "$STORE" ]; then
  KEY=$(awk 'NR==1{print $1}' "$STORE")
  check "t6 the stub's agent reads the store through a shell" bash -c 'grep -Eq "^tools: .*Bash" "$1"' _ "$(ls "$STUB"/agents/tools-*.md | head -1)"
  while read -r k v; do
    [ -n "$k" ] || continue
    n=$(grep -rlF -- "$v" "$REPO/plugins/session" "$REPO/tests/measure" 2>/dev/null | wc -l | tr -d ' ')
    check "t6 the value of $k exists nowhere in the base plugin or the scenario text (files: $n)" test "$n" -eq 0
  done < "$STORE"
  check "t6 the store holds a key the scenario can ask for" test -n "$KEY"
fi

# ---- t7: scenario-env.sh builds every variant, with and without --hide-old ----
PLUG=$REPO/plugins/session
i=0
for variant in base stub-on stub-off-deny; do
  for flag in "" --hide-old; do
    i=$((i + 1))
    D=$T/env-$i
    mkdir -p "$D"
    if [ -n "$flag" ]; then bash "$ENVSH" "$flag" "$variant" "$D" > "$T/env-$i.out" 2>&1
    else bash "$ENVSH" "$variant" "$D" > "$T/env-$i.out" 2>&1; fi
    rc=$?
    tag="$variant${flag:+ $flag}"
    check "t7 [$tag] scenario-env exit 0 ($(tail -1 "$T/env-$i.out"))" test "$rc" -eq 0
    check "t7 [$tag] writes .claude/settings.json" test -s "$D/.claude/settings.json"
    check "t7 [$tag] writes claude-args" test -s "$D/claude-args"
    check "t7 [$tag] writes variant" grep -qxF "$variant" "$D/variant"
    check "t7 [$tag] the project disables the installed plugin" python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
sys.exit(0 if d["enabledPlugins"]["session@claude-session"] is False else 1)' "$D/.claude/settings.json"
    args=$(cat "$D/claude-args" 2>/dev/null)
    dirs=$(printf '%s\n' "$args" | tr ' ' '\n' | grep -c -- '--plugin-dir')
    case $variant in
      stub-on) check "t7 [$tag] two --plugin-dir arguments (got $dirs)" test "$dirs" -eq 2
               check "t7 [$tag] the second one is the stub" grep -qF "$STUB" "$D/claude-args" ;;
      *) check "t7 [$tag] one --plugin-dir argument (got $dirs)" test "$dirs" -eq 1
         check "t7 [$tag] the stub is not loaded" bash -c '! grep -qF "$1" "$2"' _ "$STUB" "$D/claude-args" ;;
    esac
    case $variant in
      stub-off-deny) check "t7 [$tag] one built-in tool denied in the project (U11)" python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
deny = d.get("permissions", {}).get("deny", [])
sys.exit(0 if len(deny) == 1 and deny[0] == "Read" else 1)' "$D/.claude/settings.json" ;;
      *) check "t7 [$tag] no tool denied" python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
sys.exit(1 if d.get("permissions", {}).get("deny") else 0)' "$D/.claude/settings.json" ;;
    esac
    if [ -n "$flag" ]; then
      copy=$D/plugin
      check "t7 [$tag] the plugin argument points into the run directory" bash -c 'grep -qF -- "--plugin-dir $1" "$2"' _ "$copy" "$D/claude-args"
      check "t7 [$tag] the copy exists" test -f "$copy/.claude-plugin/plugin.json"
      for w in $OLD_WF; do
        check "t7 [$tag] no contract entry for the old $w" bash -c '! grep -qF "workflows/$1.js" "$2"' _ "$w" "$copy/.claude-plugin/plugin.json"
      done
      for w in role chain make probe; do
        check "t7 [$tag] the copy keeps the contract entry of $w" grep -qF "workflows/$w.js" "$copy/.claude-plugin/plugin.json"
      done
      for s in $OLD_SKILLS; do
        check "t7 [$tag] the copy holds no old process skill $s" test ! -e "$copy/skills/$s"
      done
      check "t7 [$tag] the copy keeps the kept skills" test -d "$copy/skills/ask"
      check "t7 [$tag] the copy keeps lib and workflows" bash -c 'test -f "$1/lib/block.js" && test -d "$1/workflows"' _ "$copy"
    else
      check "t7 [$tag] the plugin argument names the worktree plugin" bash -c 'grep -qF -- "--plugin-dir $1" "$2"' _ "$PLUG" "$D/claude-args"
      check "t7 [$tag] no copy is made" test ! -e "$D/plugin"
    fi
  done
done

# the gate names of the plan are the same three variants with the flag built in
for gv in gate gate-stub-on gate-stub-off-deny; do
  i=$((i + 1)); D=$T/env-$i; mkdir -p "$D"
  bash "$ENVSH" "$gv" "$D" > "$T/env-$i.out" 2>&1; rc=$?
  check "t7 [$gv] scenario-env exit 0 ($(tail -1 "$T/env-$i.out"))" test "$rc" -eq 0
  check "t7 [$gv] records its own variant name" grep -qxF "$gv" "$D/variant"
  check "t7 [$gv] hides the old set" test -f "$D/plugin/.claude-plugin/plugin.json"
  check "t7 [$gv] no old contract entry" bash -c '! grep -qF "workflows/dev.js" "$1"' _ "$D/plugin/.claude-plugin/plugin.json"
done

# ---- t8: refusals ----
i=$((i + 1)); D=$T/env-$i; mkdir -p "$D"
bash "$ENVSH" no-such-variant "$D" > "$T/refuse1.out" 2>&1
check "t8 an unknown variant is refused" test "$?" -ne 0
i=$((i + 1)); D=$T/env-$i; mkdir -p "$D"; : > "$D/keep"
bash "$ENVSH" base "$D" > "$T/refuse2.out" 2>&1
check "t8 a non-empty directory is refused" test "$?" -ne 0
bash "$ENVSH" base relative/dir > "$T/refuse3.out" 2>&1
check "t8 a relative directory is refused" test "$?" -ne 0

# ---- t9: every workflow script of both roots parses ----
# A workflow script runs as the body of an async function of the harness (top-level `await` and
# `return` are its shape), so the parse check wraps it in one. A script that does not parse is a
# launch that never happens, and a fixture that does not parse burns a whole behavior run.
for root in "$TPL" "$STUB"; do
  b=$(basename "$root")
  for f in "$root"/workflows/*.js; do
    [ -f "$f" ] || continue
    s=$(basename "$f" .js)
    python3 -c '
import sys
src = open(sys.argv[1], encoding="utf-8").read().replace("export const meta", "const meta", 1)
open(sys.argv[2], "w", encoding="utf-8").write("async function __wf(args, agent, log, phase, parallel, workflow, budget) {\n" + src + "\n}\n")
' "$f" "$T/$b-$s.wrapped.js"
    node --check "$T/$b-$s.wrapped.js" 2> "$T/$b-$s.parse.err"
    check "t9 $b workflows/$s.js parses ($(head -2 "$T/$b-$s.parse.err" | tr '\n' ' '))" test ! -s "$T/$b-$s.parse.err"
  done
done

if [ "$FAILS" -eq 0 ]; then echo "toolplugin: PASS $N"; exit 0; fi
echo "toolplugin: FAIL $FAILS failures, $N checks passed"
exit 1
