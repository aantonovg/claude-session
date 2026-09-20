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
# What counts as naming a carrier is no pattern list of this file: it is carrierTokens() of the
# shared block, executed over every file of the two roots and re-run over a mutant of that function
# which must turn the same scan red. A workflow name of the base plugin is an ordinary English word
# ("make", "role"), which a literal grep either misses or reports everywhere; the function reads the
# carrier shapes instead — a path, a launch name, the word `workflow` beside the name.
# The whole documentation tree, not only the template inside it: the README explains the pattern
# without naming a carrier of the base plugin either, or the first plugin copied from it inherits
# the dependency the pattern forbids.
BLOCKJS=$REPO/plugins/session/lib/block.js
cat > "$T/carrier.js" <<'JS'
const fs = require('fs')
const b = require(process.argv[2])
const hits = []
for (const path of process.argv.slice(3)) {
  let lines
  try { lines = fs.readFileSync(path, 'utf8').split('\n') } catch (e) {
    hits.push(`${path}:0 unreadable: ${e.message}`)
    continue
  }
  lines.forEach((line, i) => {
    for (const t of b.carrierTokens(line)) hits.push(`${path}:${i + 1} names a carrier: ${t}`)
  })
}
hits.slice(0, 20).forEach(h => console.log(h))
process.exit(hits.length ? 1 : 0)
JS
check "t4 lib/block.js exists: the carrier rule is executed, never grepped" test -f "$BLOCKJS"
shopt -s nullglob
FILES4=()
while IFS= read -r f; do FILES4+=("$f"); done < <(find "$DOC" "$STUB" -type f | sort)
if [ "${#FILES4[@]}" -eq 0 ]; then
  fail "t4 at least one file under the two roots"
else
  pass
  check "t4 no file of the template, the README or the stub names a path, an agent, a workflow or a launch name of the base plugin" \
    node "$T/carrier.js" "$BLOCKJS" "${FILES4[@]}"
fi
# executed, not read: the two carrier shapes must be seen, a sentence using the same words as plain
# English must stay clean, and a mutant that forgets the workflow names must stop seeing the first.
printf 'The common role workflow of the base plugin never carries a tool-server role\n' > "$T/carrier-wf.md"
printf 'launch session:make over it\n' > "$T/carrier-name.md"
printf 'copy the tree and make your own workflows, one file per job\n' > "$T/carrier-prose.md"
check "t4 the scan sees a workflow of the base plugin named in prose" \
  bash -c '! node "$1" "$2" "$3" > /dev/null' _ "$T/carrier.js" "$BLOCKJS" "$T/carrier-wf.md"
check "t4 the scan sees a launch name of the base plugin" \
  bash -c '! node "$1" "$2" "$3" > /dev/null' _ "$T/carrier.js" "$BLOCKJS" "$T/carrier-name.md"
check "t4 the same words as plain English name no carrier" node "$T/carrier.js" "$BLOCKJS" "$T/carrier-prose.md"
perl -pe "s/const CARRIER_WORKFLOWS = \[[^\]]*\]/const CARRIER_WORKFLOWS = ['zzz']/" "$BLOCKJS" > "$T/mutant-carrier.js"
check "t4 the mutant of carrierTokens is really a mutation" bash -c '! cmp -s "$1" "$2"' _ "$BLOCKJS" "$T/mutant-carrier.js"
check "t4 the mutant that drops the workflow names is caught" \
  bash -c 'node "$1" "$2" "$3" > /dev/null' _ "$T/carrier.js" "$T/mutant-carrier.js" "$T/carrier-wf.md"

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
  # the whole worktree, the store itself apart: "exists nowhere else" is a claim about the tree a
  # behavior run reads, so a duplicate of the number in docs/, in another test or in .claude/ would
  # break it exactly the way one in the base plugin does
  while read -r k v; do
    [ -n "$k" ] || continue
    hits=$(grep -rlF --exclude-dir=.git -- "$v" "$REPO" 2>/dev/null | grep -vF "$STORE" | tr '\n' ' ')
    check "t6 the value of $k exists nowhere else in the worktree (hits: $hits)" test -z "$hits"
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
        # a workflows/ directory is auto-loaded: a file left in the copy stays launchable and listed
        # however the contract entries read, so the gate would not measure the new set alone
        check "t7 [$tag] the copy holds no old workflow file $w.js" test ! -e "$copy/workflows/$w.js"
      done
      for w in role chain make probe; do
        check "t7 [$tag] the copy keeps the contract entry of $w" grep -qF "workflows/$w.js" "$copy/.claude-plugin/plugin.json"
        check "t7 [$tag] the copy keeps the workflow file $w.js" test -f "$copy/workflows/$w.js"
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
  check "t7 [$gv] no old workflow file in the copy" test ! -e "$D/plugin/workflows/dev.js"
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

# ---- t10: the block check of each workflow reads the last line and nothing above it ----
# Executed, not grepped: each script runs over a fake harness whose agent return quotes the blocked
# word mid-text — the prompt of the script asks for that word on the last line, so its own rule text
# echoed back would turn a finished lookup into a blocked one under a whole-return check. The same
# run against a mutant with the whole-return form must go the other way.
cat > "$T/run-wf.js" <<'JS'
const fs = require('fs')
const src = fs.readFileSync(process.argv[2], 'utf8').replace('export const meta', 'const meta')
const args = JSON.parse(process.argv[3])
const ret = fs.readFileSync(process.argv[4], 'utf8')
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor
const wf = new AsyncFunction('args', 'agent', 'log', 'phase', 'parallel', 'workflow', 'budget', src)
wf(args, async () => ret, () => {}, () => {}, async () => [], () => {}, () => {}).then(
  r => console.log(JSON.stringify(r)),
  e => { console.log(JSON.stringify({ error: String(e && e.message || e) })); process.exitCode = 1 },
)
JS
printf 'Looked the key up. The rule says to return BLOCKED: <the denied action> on a denial; nothing was denied.\n%s %s\n' \
  "$(awk 'NR==1{print $1}' "$STORE")" "$(awk 'NR==1{print $2}' "$STORE")" > "$T/ret-stub-ok.txt"
printf 'Ran the lookup.\nBLOCKED: Bash\n' > "$T/ret-stub-blocked.txt"
printf '/tmp/example-out.md 42 bytes\nThe rule says to return BLOCKED: <the denied action> on a denial.\nthe answer\n' > "$T/ret-tpl-ok.txt"
printf '/tmp/example-out.md 42 bytes\nBLOCKED: Write\n' > "$T/ret-tpl-blocked.txt"
STUB_ARGS=$(python3 -c '
import json, sys
print(json.dumps({"key": sys.argv[1], "store": sys.argv[2]}))' "$(awk 'NR==1{print $1}' "$STORE")" "$STORE")
TPL_ARGS='{"object":"an object","ask":"read it","out":"/tmp/example-out.md"}'
blocked_key() { python3 -c '
import json, sys
d = json.loads(open(sys.argv[1], encoding="utf-8").read() or "{}")
sys.exit(0 if d.get("blocked") else 1)' "$1"; }
i=0
for pair in "$STUB/workflows/metrics.js|$STUB_ARGS" "$TPL/workflows/example.js|$TPL_ARGS"; do
  i=$((i + 1))
  f=${pair%%|*}; a=${pair#*|}
  b=$(basename "$f")
  tag=$([ "$i" = 1 ] && echo stub || echo tpl)
  node "$T/run-wf.js" "$f" "$a" "$T/ret-$tag-ok.txt" > "$T/$tag-ok.json" 2> "$T/$tag-ok.err"
  check "t10 $b runs over the fake harness ($(head -1 "$T/$tag-ok.err"))" test -s "$T/$tag-ok.json"
  if blocked_key "$T/$tag-ok.json"; then fail "t10 $b blocks on the word quoted mid-text ($(cat "$T/$tag-ok.json"))"; else pass; fi
  node "$T/run-wf.js" "$f" "$a" "$T/ret-$tag-blocked.txt" > "$T/$tag-bad.json" 2>/dev/null
  if blocked_key "$T/$tag-bad.json"; then pass; else fail "t10 $b blocks on the word on the last line ($(cat "$T/$tag-bad.json"))"; fi
  perl -pe 's{/\^BLOCKED:/\.test\(LINE\)}{/BLOCKED:/.test(String(r))}' "$f" > "$T/$tag-mutant.js"
  check "t10 $b mutant with the whole-return check is really a mutation" bash -c '! cmp -s "$1" "$2"' _ "$f" "$T/$tag-mutant.js"
  node "$T/run-wf.js" "$T/$tag-mutant.js" "$a" "$T/ret-$tag-ok.txt" > "$T/$tag-mut.json" 2>/dev/null
  if blocked_key "$T/$tag-mut.json"; then pass; else fail "t10 $b the whole-return mutant is caught"; fi
done

if [ "$FAILS" -eq 0 ]; then echo "toolplugin: PASS $N"; exit 0; fi
echo "toolplugin: FAIL $FAILS failures, $N checks passed"
exit 1
