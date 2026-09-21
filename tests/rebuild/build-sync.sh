#!/bin/bash
# Static oracle of P1: the one source of the class table.
# Globs: plugins/session/lib/**, plugins/session/bin/build.sh, tests/rebuild/fixtures/marker-*.
# Proves: bin/build.sh stamps the shared block, the class table and the role texts into files that
# carry the markers, leaves a file without markers byte-identical, and --check fails on any drift;
# lib/block.js is a fresh render of lib/block.src.js; all 35 class cells resolve in node exactly as
# in lib/classes.json; the pure functions of the block behave; tests/rebuild/verdicts.sh reads a
# verdict file the way the plan states. Temp dirs only, no network, no session, under 20 s.
set -u

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
P=$REPO/plugins/session
LIB=$P/lib
FX=$REPO/tests/rebuild/fixtures
BUILD=$P/bin/build.sh

T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT

N=0; FAILS=0
pass() { N=$((N + 1)); }
fail() { echo "FAIL $1"; FAILS=$((FAILS + 1)); }
check() { local label=$1; shift; if "$@"; then pass; else fail "$label"; fi; }

# ---- b1: the repo is built ----
check "b1 lib/classes.json is valid JSON" python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$LIB/classes.json"
check "b1 lib/build-manifest.json is valid JSON" python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$LIB/build-manifest.json"
check "b1 lib/block.src.js carries the class-table marker" grep -q '^// ---- class table' "$LIB/block.src.js"
check "b1 bin/build.sh --check clean on the repo" bash "$BUILD" --check
check "b1 lib/block.js loads in node" node -e 'require(process.argv[1])' "$LIB/block.js"
check "b1 lib/block.js calls no harness global" bash -c '! grep -vE "^\s*//" "$1" | grep -qE "(^|[^a-zA-Z.])(agent|log|phase|parallel|pipeline)\s*\("' _ "$LIB/block.js"

# ---- b2: the stamp over the fixtures ----
mkdir -p "$T/plugin" "$T/fx"
cp -R "$LIB" "$P/bin" "$T/plugin/"
mkdir -p "$T/plugin/lib/roles"
printf 'Demo role.\n\nOne paragraph with a `backtick`, a "quote" and a ${dollar} form.\n' > "$T/plugin/lib/roles/demo-role.md"
cat > "$T/plugin/lib/build-manifest.json" <<'JSON'
{ "targets": [
  { "path": "../fx/marker-script.js", "block": true, "roles": ["demo-role"] },
  { "path": "../fx/marker-doc.md", "table": true },
  { "path": "../fx/no-marker.js" },
  { "path": "../fx/nosuch.js" }
] }
JSON
cp "$FX/marker-script.js" "$FX/marker-doc.md" "$FX/no-marker.js" "$T/fx/"
sha() { shasum "$1" | cut -d' ' -f1; }
NM_BEFORE=$(sha "$T/fx/no-marker.js")
bash "$T/plugin/bin/build.sh" "$T/fx/marker-script.js" "$T/fx/marker-doc.md" "$T/fx/no-marker.js" > "$T/build.out" 2>&1; BRC=$?
check "b2 build over fixtures exits 0 ($(tail -1 "$T/build.out"))" test "$BRC" = 0
check "b2 no-marker.js byte-identical" test "$NM_BEFORE" = "$(sha "$T/fx/no-marker.js")"

cat > "$T/region.py" <<'PY'
import sys
begin, end, path = sys.argv[1], sys.argv[2], sys.argv[3]
lines = open(path, encoding='utf-8').read().split('\n')
b = e = None
for i, l in enumerate(lines):
    s = l.strip()
    if b is None and s.startswith(begin): b = i
    elif b is not None and s.startswith(end): e = i; break
if b is None or e is None: sys.exit(3)
sys.stdout.write('\n'.join(lines[b + 1:e]))
PY
python3 "$T/region.py" '// ---- shared block' '// ---- end shared block' "$T/fx/marker-script.js" > "$T/stamped-block.js"
printf '%s' "$(cat "$LIB/block.js")" > "$T/block-body.js"
check "b2 stamped shared block equals lib/block.js" cmp -s "$T/stamped-block.js" "$T/block-body.js"
check "b2 tail below the regions survived" grep -q 'this line stays below every generated region' "$T/fx/marker-script.js"
check "b2 roles region holds ROLE_TEXT" bash -c 'python3 "$1" "// ---- roles" "// ---- end roles" "$2" | grep -q "^const ROLE_TEXT = {"' _ "$T/region.py" "$T/fx/marker-script.js"
check "b2 stamped role text equals its source byte for byte" python3 -c '
import json, re, sys
body = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"^const ROLE_TEXT = \{\n(.*?)\n\}$", body, re.S | re.M)
src = open(sys.argv[2], encoding="utf-8").read()
line = m.group(1).strip().rstrip(",")
key, val = line.split(": ", 1)
sys.exit(0 if json.loads(key) == "demo-role" and json.loads(val) == src else 1)
' <(python3 "$T/region.py" '// ---- roles' '// ---- end roles' "$T/fx/marker-script.js") "$T/plugin/lib/roles/demo-role.md"
# a file matched by base name only is no target: it must be refused loudly, never built with an
# empty spec (an empty spec enforces no roles/aspects key, so --check would print clean over a
# stale region of a file this build step does not own)
mkdir -p "$T/elsewhere"; cp "$FX/marker-script.js" "$T/elsewhere/marker-script.js"
EW_BEFORE=$(sha "$T/elsewhere/marker-script.js")
check "b2 same base name outside the manifest is refused" bash -c '! bash "$1" "$2" > "$3" 2>&1' _ "$T/plugin/bin/build.sh" "$T/elsewhere/marker-script.js" "$T/elsewhere.out"
check "b2 the message says the file is no manifest target" grep -q 'no target of' "$T/elsewhere.out"
check "b2 a refused file is left byte-identical" test "$EW_BEFORE" = "$(sha "$T/elsewhere/marker-script.js")"
check "b2 --check of a non-target file never reads clean" bash -c '! bash "$1" --check "$2" > /dev/null 2>&1' _ "$T/plugin/bin/build.sh" "$T/elsewhere/marker-script.js"

check "b2 marker-doc.md text above the region survived" grep -q 'Text above the region stays untouched' "$T/fx/marker-doc.md"
check "b2 marker-doc.md text below the region survived" grep -q 'Text below the region stays untouched' "$T/fx/marker-doc.md"
check "b2 marker-doc.md table equals lib/classes.json" python3 -c '
import json, re, sys
rows = [l for l in open(sys.argv[1], encoding="utf-8").read().split("\n") if re.match(r"^\| c[0-9] ", l)]
cls = json.load(open(sys.argv[2], encoding="utf-8"))
keys = cls["submodeKeys"]
want = ["| %s | %s |" % (c, " | ".join(" / ".join(cls["table"][c][k].split("/")) for k in keys)) for c in sorted(cls["table"])]
sys.exit(0 if rows == want else 1)
' "$T/fx/marker-doc.md" "$LIB/classes.json"

# ---- b3: --check catches every drift ----
check "b3 --check clean right after a build" bash "$T/plugin/bin/build.sh" --check "$T/fx/marker-script.js" "$T/fx/marker-doc.md" "$T/fx/no-marker.js"
python3 - "$T/fx/marker-script.js" <<'PY'
import sys
p = sys.argv[1]
t = open(p, encoding='utf-8').read().replace('const CLASSES = {', 'const CLASSES = { hand_edited: 1,', 1)
open(p, 'w', encoding='utf-8').write(t)
PY
check "b3 --check fails on a hand edit inside a stamped region" bash -c '! bash "$1" --check "$2" > "$3" 2>&1' _ "$T/plugin/bin/build.sh" "$T/fx/marker-script.js" "$T/check.out"
check "b3 --check names the drifted file" grep -q 'marker-script.js' "$T/check.out"
printf '\n// hand edit\n' >> "$T/plugin/lib/block.js"
check "b3 --check fails on a hand edit of lib/block.js" bash -c '! bash "$1" --check > "$2" 2>&1' _ "$T/plugin/bin/build.sh" "$T/check2.out"
check "b3 --check names lib/block.js" grep -q 'block.js' "$T/check2.out"
check "b3 build restores lib/block.js from its source" bash -c 'bash "$1" > /dev/null && bash "$1" --check > /dev/null' _ "$T/plugin/bin/build.sh"
check "b3 a file without markers is skipped, not rewritten" test "$NM_BEFORE" = "$(sha "$T/fx/no-marker.js")"
# a named file that does not exist must never read as clean
check "b3 --check of a missing named file fails" bash -c '! bash "$1" --check "$2" > "$3" 2>&1' _ "$T/plugin/bin/build.sh" "$T/fx/nosuch.js" "$T/check3.out"
check "b3 --check names the missing file" grep -q 'nosuch.js' "$T/check3.out"
# a manifest key whose marker was deleted is an error, not a silent skip
python3 - "$T/fx/marker-script.js" <<'PY'
import sys
p = sys.argv[1]
keep = [l for l in open(p, encoding='utf-8').read().split('\n') if 'shared block' not in l]
open(p, 'w', encoding='utf-8').write('\n'.join(keep))
PY
check "b3 a target declaring block with no marker fails" bash -c '! bash "$1" > "$2" 2>&1' _ "$T/plugin/bin/build.sh" "$T/check4.out"
check "b3 the message names the missing marker" grep -q 'carries no shared-block marker' "$T/check4.out"

# ---- b3b: a fromBase target whose source is gone is said out loud, never skipped ----
# A full run (no file named) used to skip such a target, so a deleted base/BASE.md left the
# generated skills/base/SKILL.md on disk and --check still printed clean over the stale copy.
mkdir -p "$T/plugin2" "$T/fx2"
cp -R "$LIB" "$P/bin" "$T/plugin2/"
cat > "$T/plugin2/lib/build-manifest.json" <<'JSON'
{ "targets": [
  { "path": "../fx2/src.md" },
  { "path": "../fx2/gen.md", "fromBase": "../fx2/src.md", "frontmatter": ["name: demo"] }
] }
JSON
B2=$T/plugin2/bin/build.sh
printf 'the body of the source\n' > "$T/fx2/src.md"
check "b3b a full run generates the fromBase target" bash -c 'bash "$1" > /dev/null 2>&1 && [ -f "$2" ]' _ "$B2" "$T/fx2/gen.md"
check "b3b --check clean right after that run" bash "$B2" --check
rm -f "$T/fx2/src.md"
check "b3b a full run with the source gone fails" bash -c '! bash "$1" > "$2" 2>&1' _ "$B2" "$T/b3b.out"
check "b3b the message names the missing source" grep -q 'missing source' "$T/b3b.out"
check "b3b --check with the source gone never reads clean" bash -c '! bash "$1" --check > "$2" 2>&1' _ "$B2" "$T/b3b-check.out"
check "b3b the stale target is left on disk, not silently rebuilt" test -f "$T/fx2/gen.md"
rm -f "$T/fx2/gen.md"
check "b3b source and target both absent is still the skip of a later part" bash "$B2" --check

# ---- b4: all 35 cells resolve identically in node and in lib/classes.json ----
cat > "$T/cells.js" <<'JS'
const b = require(process.argv[2])
const out = []
for (const cls of Object.keys(b.CLASSES.table))
  for (const key of b.CLASSES.submodeKeys) {
    const c = b.cellFor(cls, key === 'none' ? [] : key.split(' '))
    out.push(`${cls}|${key}|${c.main}/${c.opus}/${c.sonnet}`)
  }
console.log(out.join('\n'))
JS
node "$T/cells.js" "$LIB/block.js" > "$T/cells-node.txt"
python3 -c '
import json, sys
cls = json.load(open(sys.argv[1], encoding="utf-8"))
print("\n".join("%s|%s|%s" % (c, k, cls["table"][c][k]) for c in cls["table"] for k in cls["submodeKeys"]))
' "$LIB/classes.json" > "$T/cells-json.txt"
check "b4 35 cells in node" test "$(wc -l < "$T/cells-node.txt" | tr -d ' ')" = 35
check "b4 node cells equal lib/classes.json cells" cmp -s "$T/cells-node.txt" "$T/cells-json.txt"

# ---- b5: the pure functions of the block ----
cat > "$T/pure.js" <<'JS'
const b = require(process.argv[2])
const bad = []
const eq = (got, want, what) => { const g = JSON.stringify(got), w = JSON.stringify(want); if (g !== w) bad.push(`${what}: got ${g}, want ${w}`) }
const throws = (fn, what) => { try { fn(); bad.push(`${what}: no throw`) } catch (e) {} }

// full model and effort names at the call site, label carries the resolved cell
eq(b.optsFor('c3', [], 'main', 'critic'), { model: 'fable', effort: 'low', label: 'fab-lo-critic' }, 'optsFor c3 main')
eq(b.optsFor('c4', ['no-sonnet'], 'sonnet', 'run', { agentType: 'x' }), { agentType: 'x', model: 'opus', effort: 'medium', label: 'ops-me-run' }, 'optsFor c4 no-sonnet sonnet')
// extra never overrides the class table
eq(b.optsFor('c3', [], 'main', 'critic', { model: 'opus', effort: 'high' }), { model: 'fable', effort: 'low', label: 'fab-lo-critic' }, 'optsFor extra cannot override')
eq(b.bindClass('c2', ['no-fable']).name('chain'), 'c2-no-fable-chain', 'bindClass name')
eq(b.bindClass('c2', []).up().class, 'c3', 'bindClass up')

// classUp: one step, the top class steps to itself
eq(['c1', 'c2', 'c3', 'c4', 'c5'].map(b.classUp), ['c2', 'c3', 'c4', 'c5', 'c5'], 'classUp')

// slotForSize: one slot down at large, never up, never past the cheapest slot
for (const size of ['small', 'medium']) eq(['main', 'opus', 'sonnet'].map(s => b.slotForSize(s, size)), ['main', 'opus', 'sonnet'], `slotForSize ${size}`)
eq(['main', 'opus', 'sonnet'].map(s => b.slotForSize(s, 'large')), ['opus', 'sonnet', 'sonnet'], 'slotForSize large')
eq(b.slotForSize('main', null), 'main', 'slotForSize default size')

// roles: 18 catalog rows, each with an existing tool-set agent, the split critic slot, the uplift
eq(b.roleNames().length, 18, 'role count')
eq(b.roleAgent('code-author'), 'tools-edit', 'roleAgent code-author')
eq(b.roleSlot('code-author'), 'sonnet', 'roleSlot code-author')
eq(b.roleSlot('translator', 'large'), 'sonnet', 'roleSlot translator large')
eq(b.roleSlot('critic'), 'main', 'roleSlot critic merged')
eq(b.roleSlot('critic', null, true), 'opus', 'roleSlot critic split by aspect')
eq(b.roleClass('plan-author', 'c3'), 'c4', 'roleClass uplift')
eq(b.roleClass('code-author', 'c3'), 'c3', 'roleClass no uplift')

// ceilings of A30
eq(b.ceiling('lite'), { agents: 2, cycles: 1 }, 'ceiling lite')
eq([b.ceilingHit('std', 'agents', 4), b.ceilingHit('std', 'agents', 5)], [false, true], 'ceilingHit agents')
eq([b.ceilingHit('full', 'cycles', 2), b.ceilingHit('full', 'cycles', 3)], [false, true], 'ceilingHit cycles')

// mustExist: the output check of a stage that names an output file
eq(b.mustExist('wrote it\nFILE: /tmp/out.md\nDONE', '/tmp/out.md').ok, true, 'mustExist ok')
eq(b.mustExist('BLOCKED: Read', '/tmp/out.md').ok, false, 'mustExist blocked')
eq(b.mustExist('DONE', '/tmp/out.md').ok, false, 'mustExist path not named')
eq(b.mustExist(null, '/tmp/out.md').ok, false, 'mustExist null return')
// the blocked word counts on the last line only
eq(b.isBlocked('one finding says BLOCKED: nothing\nwrote /tmp/out.md\nDONE'), false, 'isBlocked mid-text')
eq(b.mustExist('a line quoting BLOCKED: x\n/tmp/out.md written\nDONE', '/tmp/out.md').ok, true, 'mustExist word mid-text')
eq(b.isBlocked('wrote nothing\nBLOCKED: Read denied'), true, 'isBlocked last line')

// the error paths
throws(() => b.cellFor('c9', []), 'unknown class')
throws(() => b.cellFor('c3', ['no-sonnet', 'no-opus', 'no-fable']), 'all three submodes')
throws(() => b.cellFor('c3', ['no-such']), 'unknown submode')
throws(() => b.optsFor('c3', [], 'nosuch', 'job'), 'unknown slot')
throws(() => b.slotForSize('main', 'huge'), 'unknown size')
throws(() => b.roleOf('nosuch'), 'unknown role')
throws(() => b.ceiling('deep'), 'unknown depth')
throws(() => b.ceilingHit('std', 'agents', 'many'), 'ceilingHit of a non-number')
throws(() => b.mustExist('DONE', ''), 'mustExist without a path')

if (bad.length) { console.log(bad.join('\n')); process.exit(1) }
JS
if node "$T/pure.js" "$LIB/block.js" > "$T/pure.out" 2>&1; then pass; else fail "b5 pure functions of lib/block.js"; sed 's/^/  /' "$T/pure.out"; fi
check "b5 every role agent has an agent file" python3 -c '
import json, os, sys
cls = json.load(open(sys.argv[1], encoding="utf-8"))
missing = [r["agent"] for r in cls["roles"].values() if not os.path.exists(os.path.join(sys.argv[2], r["agent"] + ".md"))]
if missing: print("missing agent files:", " ".join(sorted(set(missing))))
sys.exit(1 if missing else 0)
' "$LIB/classes.json" "$P/agents"

# ---- b6: tests/rebuild/verdicts.sh reads verdicts the way the plan states ----
V=$REPO/tests/rebuild/verdicts.sh
HEADSHA=$(git -C "$REPO" rev-parse HEAD)
# every key asked below has a kind, so a refusal comes from the verdicts, never from a missing kind
for k in good stale other-not-asked nosuch abc a.c loose; do
  printf '%s  prompts: "x"\n    kind: machine, because fixture\n' "$k"
done > "$T/scen.txt"
printf '%s  prompts: "x"\n    kind: judgment, because fixture\n' jkey j2 j3 j4 >> "$T/scen.txt"
printf '%s  prompts: "x"\n    kind: machine, because fixture\n' mold >> "$T/scen.txt"
export VERDICTS_SCENARIOS=$T/scen.txt
VR=$T/verdicts; mkdir -p "$VR/base/20260101-000000" "$VR/base/20260102-000000" "$VR/base/20260103-000000"
printf 'base stale PASS 20260101-000000 %s\nbase good PASS 20260101-000000 %s\n' "$HEADSHA" "$HEADSHA" > "$VR/base/20260101-000000/verdicts.txt"
printf 'base stale FAIL 20260102-000000 %s\n' "$HEADSHA" > "$VR/base/20260102-000000/verdicts.txt"
printf 'base other PASS 20260103-000000 %s\n' "$HEADSHA" > "$VR/base/20260103-000000/verdicts.txt"
check "b6 a PASS in the newest run holding the key passes" bash -c 'VERDICTS_ROOT="$1" bash "$2" base:good' _ "$VR" "$V"
check "b6 a stale PASS under a newer FAIL fails" bash -c '! VERDICTS_ROOT="$1" bash "$2" base:stale' _ "$VR" "$V"
check "b6 a missing key fails" bash -c '! VERDICTS_ROOT="$1" bash "$2" base:nosuch' _ "$VR" "$V"
check "b6 a PASS of another key does not count" bash -c '! VERDICTS_ROOT="$1" bash "$2" base:other-not-asked' _ "$VR" "$V"
check "b6 a PASS of an unknown variant fails" bash -c '! VERDICTS_ROOT="$1" bash "$2" gate:good' _ "$VR" "$V"
printf 'base a.c PASS 20260103-000000 %s\n' "$HEADSHA" >> "$VR/base/20260103-000000/verdicts.txt"
check "b6 a key is matched literally, not as a regex" bash -c '! VERDICTS_ROOT="$1" bash "$2" base:abc' _ "$VR" "$V"
printf 'base loose PASS 20260103-000000 0000000000000000000000000000000000000000\n' >> "$VR/base/20260103-000000/verdicts.txt"
check "b6 a PASS whose commit is not an ancestor of HEAD fails" bash -c '! VERDICTS_ROOT="$1" bash "$2" base:loose' _ "$VR" "$V"
check "b6 no argument fails" bash -c '! VERDICTS_ROOT="$1" bash "$2"' _ "$VR" "$V"

# ---- b8: the kind of a key picks the rule; gateDecision() of lib/block.js decides ----
# judgment: 2 PASS out of at most 3 runs on the current code, 2 FAIL fail, fewer runs unsettled.
# machine: the newest run on the current code; a PASS of an older commit with other code never counts.
OLD=
for c in $(git -C "$REPO" rev-list --max-count=50 HEAD); do
  git -C "$REPO" diff --quiet "$c" HEAD -- plugins/session tests || { OLD=$c; break; }
done
JR=$T/jv; for i in 1 2 3 4 5; do mkdir -p "$JR/base/2026010$i-000000"; done
vl() { printf 'base %s %s 2026010%s-000000 %s\n' "$1" "$2" "$3" "$4" >> "$JR/base/2026010$3-000000/verdicts.txt"; }
vl jkey PASS 1 "$HEADSHA"                                   # one PASS only
vl j2 PASS 1 "$HEADSHA"; vl j2 FAIL 2 "$HEADSHA"; vl j2 PASS 3 "$HEADSHA"; vl j2 FAIL 4 "$HEADSHA"
vl j3 FAIL 1 "$HEADSHA"; vl j3 PASS 2 "$HEADSHA"; vl j3 FAIL 3 "$HEADSHA"
vl j4 PASS 1 "$OLD"; vl j4 PASS 2 "$HEADSHA"               # the older PASS never counts
vl mold PASS 1 "$OLD"
vl good PASS 5 "$HEADSHA"
kline() { env VERDICTS_ROOT=$JR ${3:+VERDICTS_BLOCK=$3} bash "$V" "base:$1" 2>/dev/null | grep "^verdicts: base:$1 kind" | sed "s/^verdicts: base:$1 //"; }
check "b8 an older commit with other code exists in this history" test -n "$OLD"
check "b8 judgment with one PASS is unsettled [$(kline jkey)]" test "$(kline jkey)" = "kind judgment PASS 1 FAIL 0 decision unsettled"
check "b8 judgment with one PASS exits non-zero" bash -c '! VERDICTS_ROOT="$1" bash "$2" base:jkey >/dev/null 2>&1' _ "$JR" "$V"
check "b8 judgment settles at the second PASS of three runs [$(kline j2)]" test "$(kline j2)" = "kind judgment PASS 2 FAIL 2 decision PASS"
check "b8 judgment settled at 2 PASS exits 0" bash -c 'VERDICTS_ROOT="$1" bash "$2" base:j2 >/dev/null 2>&1' _ "$JR" "$V"
check "b8 judgment settles at the second FAIL [$(kline j3)]" test "$(kline j3)" = "kind judgment PASS 1 FAIL 2 decision FAIL"
check "b8 judgment counts no run of superseded code [$(kline j4)]" test "$(kline j4)" = "kind judgment PASS 1 FAIL 0 decision unsettled"
check "b8 machine passes on one PASS at HEAD [$(kline good)]" test "$(kline good)" = "kind machine PASS 1 FAIL 0 decision PASS"
check "b8 machine with only a PASS of an older commit is unsettled [$(kline mold)]" test "$(kline mold)" = "kind machine PASS 0 FAIL 0 decision unsettled"
check "b8 machine with only a PASS of an older commit exits non-zero" bash -c '! VERDICTS_ROOT="$1" bash "$2" base:mold >/dev/null 2>&1' _ "$JR" "$V"
# the two mutants of gateDecision(): judgment passing on 1 PASS, machine passing on an older commit
bmut() { # <out> <python regex> <replacement>
  python3 - "$REPO/plugins/session/lib/block.js" "$1" "$2" "$3" <<'PY'
import re, sys
s = open(sys.argv[1]).read(); m, n = re.subn(sys.argv[3], sys.argv[4], s, count=1)
open(sys.argv[2], 'w').write(m); sys.exit(0 if n == 1 else 1)
PY
}
bmut "$T/mj.js" 'if \(p === 2\) \{' 'if (p === 1) {'; check "b8 mutant judgment on 1 PASS applied" test $? -eq 0
check "b8 mutant judgment on 1 PASS is caught" test "$(kline jkey "" "$T/mj.js")" != "kind judgment PASS 1 FAIL 0 decision unsettled"
bmut "$T/mm.js" '\.filter\(r => r && r\.current\)' '.filter(r => r)'; check "b8 mutant machine on an older commit applied" test $? -eq 0
check "b8 mutant machine on an older commit is caught" test "$(kline mold "" "$T/mm.js")" != "kind machine PASS 0 FAIL 0 decision unsettled"
check "b8 scenarioKind reads the kind of every scenario of the real file" node -e '
  const b = require(process.argv[1]), t = require("fs").readFileSync(process.argv[2], "utf8")
  const keys = t.split("\n").filter(l => /^[A-Za-z][A-Za-z0-9_-]*\s.*prompts:/.test(l)).map(l => l.split(/\s/)[0])
  const bad = keys.filter(k => !b.scenarioKind(t, k)); if (!keys.length || bad.length) { console.log(bad.join(" ")); process.exit(1) }
  for (const k of ["coverage", "aspect-approval"]) if (b.scenarioKind(t, k) !== "judgment") process.exit(1)' \
  "$REPO/plugins/session/lib/block.js" "$REPO/tests/measure/rebuild-scenarios-0.16.txt"

# ---- b7: scenario-run.sh --verdict names the commit the run started at ----
# No session and no tmux here: only the --verdict path over a run directory laid out by hand.
SR=$REPO/tests/rebuild/scenario-run.sh
RUN=$T/runs/base/20260104-000000
mkdir -p "$RUN"
RANSHA=1111111111111111111111111111111111111111
printf '%s\n' "$RANSHA" > "$RUN/commit"
check "b7 --verdict over a run directory exits 0" bash -c 'VARIANT=base OUT="$1" bash "$2" --verdict good PASS > /dev/null' _ "$RUN" "$SR"
check "b7 the line names the commit recorded by the run" bash -c 'awk -v s="$2" "\$1 == \"base\" && \$2 == \"good\" && \$5 == s" "$1/verdicts.txt" | grep -q .' _ "$RUN" "$RANSHA"
check "b7 the line does not name HEAD at judging time" bash -c '! grep -q "$2" "$1/verdicts.txt"' _ "$RUN" "$HEADSHA"
check "b7 the run-ts field is the run directory name" bash -c 'awk "\$4 == \"20260104-000000\"" "$1/verdicts.txt" | grep -q .' _ "$RUN"
NOC=$T/runs/base/20260105-000000; mkdir -p "$NOC"
check "b7 --verdict over a run directory with no commit file fails" bash -c '! VARIANT=base OUT="$1" bash "$2" --verdict good PASS > "$3" 2>&1' _ "$NOC" "$SR" "$T/verdict-noc.out"
check "b7 the message names the missing commit file" grep -q 'commit' "$T/verdict-noc.out"
check "b7 --verdict without a run directory fails" bash -c '! VARIANT=base OUT="$1/runs/base/20260106-000000" bash "$2" --verdict good PASS > /dev/null 2>&1' _ "$T" "$SR"
check "b7 verdicts.sh accepts nothing from a run whose commit is unrelated" bash -c '! VERDICTS_ROOT="$1/runs" bash "$2" base:good' _ "$T" "$V"

if [ "$FAILS" -eq 0 ]; then echo "build-sync: PASS $N"; exit 0; fi
echo "build-sync: FAIL $FAILS failures, $N checks passed"
exit 1
