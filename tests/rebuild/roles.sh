#!/bin/bash
# Static oracle of P2: the role catalog cannot drift, and the uniform argument shape of A26 holds.
# Globs: plugins/session/workflows/{role,chain,make,probe}.js, plugins/session/lib/roles/*.md,
#        plugins/session/lib/classes.json (through lib/block.js in node),
#        plugins/session/.claude-plugin/plugin.json.
# Proves: the catalog of lib/block.js equals the file names of lib/roles/ and the names the
# session:role contract lists; every role a script launches is in that script's stamped subset
# (A23) and the stamp is in sync; no role prompt reads a key outside A26; no no-uplift author sits
# on the main-model slot (A25); `size: large` moves a role one slot down and never past the
# cheapest slot (A32); an unknown role takes the error path; no role text lets a hint, a critique or
# a critic withdraw a claim by itself (idea 3.6: a claim is dropped only where a fact refutes it);
# and, executed over lib/block.js, that a stage whose out file is missing or empty returns a block,
# never done — with mutants that must turn the suite red.
# Temp dirs only, no network, no session, under 20 s.
set -u

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
P=$REPO/plugins/session
LIB=$P/lib
R=$LIB/roles
WF=$P/workflows
BUILD=$P/bin/build.sh

T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT

N=0; FAILS=0
pass() { N=$((N + 1)); }
fail() { echo "FAIL $1"; FAILS=$((FAILS + 1)); }
check() { local label=$1; shift; if "$@"; then pass; else fail "$label"; fi; }

# ---- r1: the catalog is one list in three places ----
if [ ! -d "$R" ]; then
  fail "r1 lib/roles/ exists"
  echo "roles: FAIL $FAILS failures, $N checks passed"
  exit 1
fi
pass
shopt -s nullglob
FILES=("$R"/*.md)
if [ "${#FILES[@]}" -eq 0 ]; then
  fail "r1 at least one role text in lib/roles/"
  echo "roles: FAIL $FAILS failures, $N checks passed"
  exit 1
fi
pass
CATALOG=$(for f in "${FILES[@]}"; do basename "$f" .md; done | sort | tr '\n' ' ')
NODE_ROLES=$(node -e 'console.log(require(process.argv[1]).roleNames().sort().join(" "))' "$LIB/block.js" 2>"$T/node.err")
check "r1 lib/block.js loads its catalog ($(tail -1 "$T/node.err" 2>/dev/null))" test -n "$NODE_ROLES"
check "r1 lib/roles/ equals the catalog of lib/block.js (files: $CATALOG)" test "$CATALOG" = "$NODE_ROLES "
nfiles=${#FILES[@]}
check "r1 18 role texts (got $nfiles)" test "$nfiles" -eq 18

# ---- r2: the stamped subset of every new workflow ----
keys_of() { # keys_of <file>: the role names stamped between the roles markers
  python3 - "$1" <<'PY'
import json, re, sys
lines = open(sys.argv[1], encoding='utf-8').read().split('\n')
b = e = None
for i, l in enumerate(lines):
    s = l.strip()
    if b is None and s.startswith('// ---- roles'): b = i
    elif b is not None and s.startswith('// ---- end roles'): e = i; break
if b is None or e is None:
    sys.exit(3)
names = []
for l in lines[b + 1:e]:
    m = re.match(r'\s*("(?:[^"\\]|\\.)*")\s*:', l)
    if m: names.append(json.loads(m.group(1)))
print(' '.join(sorted(names)))
PY
}
found=0
for w in role chain make probe; do
  f=$WF/$w.js
  [ -f "$f" ] || continue
  found=$((found + 1))
  check "r2 $w.js carries the shared-block marker" grep -q '^// ---- shared block' "$f"
  check "r2 $w.js carries the roles marker" grep -q '^// ---- roles' "$f"
  check "r2 $w.js stamp is in sync with its sources" bash "$BUILD" --check "$f"
  ks=$(keys_of "$f" 2>/dev/null)
  manifest=$(python3 -c '
import json, sys
t = [x for x in json.load(open(sys.argv[1]))["targets"] if x["path"] == "workflows/%s.js" % sys.argv[2]]
print(" ".join(sorted(t[0].get("roles", []))) if t else "")
' "$LIB/build-manifest.json" "$w")
  check "r2 $w.js stamped roles equal its manifest subset (stamped: $ks)" test "$ks" = "$manifest"
  # every role name the script code names is in its own stamped subset (A23)
  used=$(python3 - "$f" "$NODE_ROLES" <<'PY'
import re, sys
lines = open(sys.argv[1], encoding='utf-8').read().split('\n')
catalog = set(sys.argv[2].split())
skip, code = False, []
for l in lines:
    s = l.strip()
    if skip:
        if s.startswith(('// ---- end shared block', '// ---- end roles', '// ---- end aspects')): skip = False
        continue
    if s.startswith(('// ---- shared block', '// ---- roles', '// ---- aspects')):
        skip = True
        continue
    code.append(l)
text = '\n'.join(code)
# a key of the task layout inside side('<key>', ...) is a file of the task group, never a role
# launch: the two name spaces overlap (`evidence`), so the key is cut before the scan
text = re.sub(r"side\(\s*'[a-z-]+'", 'side(', text)
hits = set()
for m in re.finditer(r"""['"]([a-z][a-z-]*)['"]""", text):
    if m.group(1) in catalog: hits.add(m.group(1))
print(' '.join(sorted(hits)))
PY
)
  missing=
  for u in $used; do case " $ks " in *" $u "*) ;; *) missing="$missing $u" ;; esac; done
  check "r2 $w.js launches no role outside its stamped subset (missing:$missing)" test -z "$missing"
done
check "r2 at least one new workflow exists (got $found)" test "$found" -ge 1

# ---- r3: the contract of session:role lists every role and the whole argument shape (A26) ----
ROLEJS=$WF/role.js
if [ -f "$ROLEJS" ]; then
  usage=$(awk 'f==0&&/^\/\* usage:/{f=1} f{print} f&&/\*\//{exit}' "$ROLEJS")
  # a hyphen is a word character here: -w would let `evidence` pass on `evidence-researcher` and
  # `researcher` on `web-researcher`, so the shorter name could be missing and the check stay green
  for r in $NODE_ROLES; do
    check "r3 the contract names role $r" grep -qE "(^|[^a-z-])$r([^a-z-]|$)" <<<"$usage"
  done
  # an argument is named by its own line, `<name> (...`: prose ("the job or question in prose")
  # must never stand in for the `in` argument line
  for a in role in ask out class submodes size; do
    check "r3 the contract names argument $a on its own line" grep -qE "^$a \(" <<<"$usage"
  done
else
  fail "r3 workflows/role.js exists"
fi

# ---- r4: no role prompt reads a key outside A26 ----
# A role text is a template: the only fields it may ask for are `in`, `ask` and `out`, the uniform
# shape. Any other {placeholder} would be a per-role argument, which the contract cannot state.
for f in "${FILES[@]}"; do
  b=$(basename "$f" .md)
  # the scan is case-aware, like the one in role.js: {OUT} or {Ask} is a placeholder nobody fills
  check "r4 $b reads no key outside in/ask/out" python3 -c '
import re, sys
bad = sorted(set(m.group(1) for m in re.finditer(r"\{([A-Za-z][A-Za-z0-9_-]*)\}", open(sys.argv[1], encoding="utf-8").read()))
             - {"in", "ask", "out"})
if bad: print("extra keys:", " ".join(bad))
sys.exit(1 if bad else 0)
' "$f"
  for k in in ask out; do
    check "r4 $b names {$k}" grep -Fq "{$k}" "$f"
  done
  check "r4 $b is not empty" test -s "$f"
  # a role text states the job; the carrier is the script's business, so it names no workflow and
  # no agent file (a role prompt that named one would break when the catalog moves)
  check "r4 $b names no workflow and no tool-set agent" bash -c '! grep -Eq "session:[a-z-]+|tools-(read|edit|web)[a-z-]*" "$1"' _ "$f"
done

# a role text that orders a file into {out} must sit on an agent whose tool list can create one:
# Write, or Bash for a shell redirect. An agent with neither could only return BLOCKED.
for f in "${FILES[@]}"; do
  b=$(basename "$f" .md)
  grep -Fq "{out}" "$f" || continue
  ag=$(node -e 'console.log(require(process.argv[1]).roleAgent(process.argv[2]))' "$LIB/block.js" "$b" 2>/dev/null)
  tl=$(awk 'NR==1&&/^---$/{f=1;next} f&&/^---$/{exit} f' "$P/agents/$ag.md" 2>/dev/null | grep -E '^tools: ')
  check "r4 $b: agent $ag can create a file (tools: $tl)" grep -Eq "Write|Bash" <<<"$tl"
done

# ---- r5: the slot map, in node over lib/block.js ----
# every assertion prints its own `ok <label>` / `bad <label>` line, so the PASS count names how
# many assertions ran instead of hiding the whole suite behind one check
cat > "$T/slots.js" <<'JS'
const b = require(process.argv[2])
const out = []
const ck = (cond, what) => out.push(`${cond ? 'ok' : 'bad'} ${what}`)
const eq = (got, want, what) => ck(JSON.stringify(got) === JSON.stringify(want),
  `${what}: got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`)

// A25: an author with no uplift never sits on the main-model slot; the two of the catalog sit on
// the cheapest slot the three-slot table has.
const onMain = b.roleNames().filter(r => /-author$/.test(r) && !b.CLASSES.roles[r].uplift && b.roleSlot(r) === 'main')
ck(onMain.length === 0, `A25 no author without uplift on the main-model slot (got ${onMain.join(' ') || 'none'})`)
eq(b.roleSlot('code-author'), 'sonnet', 'A25 code-author')
eq(b.roleSlot('test-author'), 'sonnet', 'A25 test-author')

// A32: large moves a role one slot down, never up, never past the cheapest slot.
eq(b.roleSlot('translator'), 'opus', 'A22 translator default slot')
eq(b.roleSlot('translator', 'large'), 'sonnet', 'A32 translator large')
eq(b.roleSlot('code-author', 'large'), 'sonnet', 'A32 a sonnet role stays')
eq(b.roleSlot('translator', 'small'), 'opus', 'A32 small changes nothing')
const order = ['main', 'opus', 'sonnet']
const movedUp = b.roleNames().filter(r => order.indexOf(b.roleSlot(r, 'large')) < order.indexOf(b.roleSlot(r)))
ck(movedUp.length === 0, `A32 no role moves up at large (got ${movedUp.join(' ') || 'none'})`)

// every role resolves to one of the five tool-set agents
const AGENTS = ['tools-edit', 'tools-read-bash', 'tools-read-write', 'tools-read-write-bash', 'tools-web']
const offList = b.roleNames().filter(r => !AGENTS.includes(b.roleAgent(r)))
ck(offList.length === 0, `every role names a tool-set agent (got ${offList.join(' ') || 'none'})`)

// the error path of an unknown role
try { b.roleOf('nosuch'); ck(false, 'unknown role throws') } catch (e) {
  ck(/nosuch/.test(String(e.message)), `unknown role: the message names it (${e.message})`)
}
console.log(out.join('\n'))
JS
node "$T/slots.js" "$LIB/block.js" > "$T/slots.out" 2>&1
if [ ! -s "$T/slots.out" ]; then
  fail "r5 the slot map suite produced no line (node failed)"
else
  while IFS= read -r line; do
    case $line in
      "ok "*) pass ;;
      "bad "*) fail "r5 ${line#bad }" ;;
      *) fail "r5 unexpected output: $line" ;;
    esac
  done < "$T/slots.out"
fi

# ---- r6: what role.js does with a launch ----
if [ -f "$ROLEJS" ]; then
  code=$(python3 - "$ROLEJS" <<'PY'
import sys
lines = open(sys.argv[1], encoding='utf-8').read().split('\n')
skip, out = False, []
for l in lines:
    s = l.strip()
    if skip:
        if s.startswith(('// ---- end shared block', '// ---- end roles')): skip = False
        continue
    if s.startswith(('// ---- shared block', '// ---- roles')):
        skip = True
        continue
    out.append(l)
print('\n'.join(out))
PY
)
  check "r6 role.js resolves the role through the catalog of lib/block.js" grep -q 'roleNames()' <<<"$code"
  check "r6 role.js carries no role name of its own" python3 -c '
import re, sys
hits = sorted(set(m.group(1) for m in re.finditer(r"""[\x27\"]([a-z][a-z-]*)[\x27\"]""", sys.argv[1])) & set(sys.argv[2].split()))
if hits: print("literal role names in the code:", " ".join(hits))
sys.exit(1 if hits else 0)
' "$code" "$NODE_ROLES"
  check "r6 role.js takes the agent from the role map" grep -q 'roleAgent(' <<<"$code"
  check "r6 role.js takes the slot from the role map" grep -q 'roleSlot(' <<<"$code"
  check "r6 role.js takes the uplift from the role map" grep -q 'roleClass(' <<<"$code"
  check "r6 role.js answers an unknown role with the catalog" bash -c 'grep -q "unknown role" <<<"$1" && grep -q "roleNames()" <<<"$1"' _ "$code"
  # the verdict itself lives in outVerdict() of the shared block and is executed by r7 below; here
  # only the wiring is read: role.js asks for the size line and returns what outVerdict decided
  check "r6 role.js checks the output through outVerdict" grep -q 'outVerdict(' <<<"$code"
  check "r6 role.js returns blocked, never done, when the output check fails" grep -qE 'blocked: *V\.blocked' <<<"$code"
  # missing OR empty: the return's byte count is the only evidence a script without file access has
  check "r6 role.js asks the agent for the size of the output" grep -Fq '<n> bytes' <<<"$code"
  check "r6 role.js logs the launch before the first argument check" python3 -c '
import sys
code = sys.argv[1]
sys.exit(0 if 0 < code.index("log(") < code.index("return fail(") else 1)
' "$code"
  check "r6 role.js requires an absolute output path" grep -Fq 'absolute path' <<<"$code"
  check "r6 role.js takes a list argument that is no array to the error path" grep -q 'Array.isArray' <<<"$code"
  check "r6 role.js reads a return through the block, not by its own regex" bash -c '! grep -qE "/BLOCKED:?/|BLOCKED:.{0,3}\.test" <<<"$1"' _ "$code"
  check "r6 role.js pins no model at the call site" bash -c '! grep -qE "^\s*(model|effort):" <<<"$1"' _ "$code"
  check "r6 role.js names no model word" bash -c '! grep -Eqi "(^|[^-a-z])(opus|sonnet|fable|haiku)([^-a-z]|$)" <<<"$1"' _ "$code"
  check "r6 role.js requires an output path" grep -q 'args.out' <<<"$code"
  # the five tool-set agents, as literals, so a launch can never name an agent with no file
  agents=$(grep -oE "session:tools-[a-z-]+" "$ROLEJS" | sort -u | tr '\n' ' ')
  check "r6 role.js names the five tool-set agents (got $agents)" test "$agents" = "session:tools-edit session:tools-read-bash session:tools-read-write session:tools-read-write-bash session:tools-web "
  for a in $agents; do
    check "r6 agent file of ${a#session:} exists" test -f "$P/agents/${a#session:}.md"
  done
  want=$(node -e '
const b = require(process.argv[1])
console.log([...new Set(b.roleNames().map(r => "session:" + b.roleAgent(r)))].sort().join(" ") + " ")
' "$LIB/block.js" 2>/dev/null)
  check "r6 those agents equal the agents of the role map (want $want)" test "$agents" = "$want"
fi

# ---- r7: the output verdict, executed over lib/block.js (never read out of a workflow file) ----
# A stage whose out file is missing or empty must return a block, never done. The decision is
# outVerdict() of the shared block, so this suite runs it, and then runs it again over mutated
# copies: a mutation that lets an empty output through must turn at least one line red.
cat > "$T/outv.js" <<'JS'
const b = require(process.argv[2])
const out = []
const ck = (cond, what) => out.push(`${cond ? 'ok' : 'bad'} ${what}`)
const P = '/tmp/run/out.md'
const v = ret => b.outVerdict(ret, P)
ck(v(`${P} 120 bytes\nDONE`).ok === true, 'a size line naming the output passes')
ck(v(`${P} 120 bytes\nDONE`).bytes === 120, 'the byte count of that line is the size')
ck(v(`${P} 1,024 bytes\nDONE`).bytes === 1024, 'a grouped count is read')
ck(v(`${P} 0 bytes\nDONE`).ok === false, 'an empty output is blocked, never done')
ck(v(`wrote ${P}\nDONE`).ok === false, 'a return with no byte count is blocked')
ck(v('DONE').ok === false, 'a return that never names the output is blocked')
ck(v(null).ok === false, 'a null return is blocked')
ck(v(`/tmp/run/other.md 500 bytes\n${P}\nDONE`).ok === false, 'a size on another file is not the size')
ck(v(`${P} 12 bytes\nBLOCKED: denied`).ok === false, 'a blocked last line beats a size line')
ck(v(`${P} 12 bytes\nBLOCKED: denied`).blocked === 'BLOCKED: denied', 'the block word stands exactly once')
ck(/^BLOCKED: /.test(String(v(`${P} 0 bytes`).blocked)), 'an empty output carries a blocked line')
ck(v(`${P} 42 bytes\nthe check said: wrote ${P} 999999 bytes\nDONE`).bytes === 42,
   'the demanded first line decides, not a later line of a quoted run log')
console.log(out.join('\n'))
JS
node "$T/outv.js" "$LIB/block.js" > "$T/outv.out" 2>&1
if [ ! -s "$T/outv.out" ]; then
  fail "r7 the output-verdict suite produced no line (node failed)"
  sed 's/^/  /' "$T/outv.out" 2>/dev/null
else
  while IFS= read -r line; do
    case $line in
      "ok "*) pass ;;
      "bad "*) fail "r7 ${line#bad }" ;;
      *) fail "r7 unexpected output: $line" ;;
    esac
  done < "$T/outv.out"
fi
# the mutants: each breaks one rule of outVerdict, and the suite above must go red on each
i=0
while IFS='|' read -r what expr; do
  [ -n "$what" ] || continue
  i=$((i + 1))
  perl -pe "$expr" "$LIB/block.js" > "$T/mutant$i.js"
  check "r7 mutant $i is really a mutation" bash -c '! cmp -s "$1" "$2"' _ "$LIB/block.js" "$T/mutant$i.js"
  node "$T/outv.js" "$T/mutant$i.js" > "$T/mutant$i.out" 2>&1
  check "r7 the suite catches the mutant: $what" grep -q '^bad ' "$T/mutant$i.out"
done <<'MUT'
an empty output passes|s/if \(!\(n > 0\)\)/if (false)/
the last matching line decides instead of the first|s/RE\.test\(l\)\)\[0\]/RE.test(l)).pop()/
MUT

# ---- r8 (P5): the `out` default of every role is a path of lib/task-layout.md ----
# A role launched with a task directory instead of a file name writes the file the task layout
# gives that role, so the process skill reads what the role wrote without a second agreement
# (idea 8.8). Executed over lib/block.js; the two scripts are only grepped.
LAYOUT=$LIB/task-layout.md
check "r8 lib/task-layout.md exists" test -f "$LAYOUT"
cat > "$T/roleout.js" <<'JS'
const b = require(process.argv[2])
const out = []
const ck = (cond, what) => out.push(`${cond ? 'ok' : 'bad'} ${what}`)
const doc = require('fs').readFileSync(process.argv[3], 'utf8')
let covered = 0
for (const r of b.roleNames()) {
  const d = b.roleOut(r)
  if (!d) continue
  covered++
  ck(b.taskKeys().includes(d.key), `${r} defaults into the layout key ${d.key}`)
  const p = b.roleOutPath('/t/task', r, 'r1')
  ck(typeof p === 'string' && p.startsWith('/t/task/'), `${r} builds a path under the task directory (got ${p})`)
  ck(doc.includes(p.slice('/t/task/'.length).split('/')[0]), `the layout document names the file of ${r}`)
  // a `dir` row is one file per run: its path carries the run key, so a second launch of the same
  // role into the same task directory writes a second file instead of over the first one
  if (b.taskEntry(d.key).kind === 'dir') {
    ck(p !== b.roleOutPath('/t/task', r, 'r2'), `${r} writes one file per run, not one file (got ${p})`)
    let missing = false
    try { b.roleOutPath('/t/task', r) } catch (e) { missing = /run key/.test(String(e.message)) }
    ck(missing, `${r} without a run key is an error, never a silent overwrite`)
  } else {
    ck(p === b.roleOutPath('/t/task', r, 'r2'), `${r} writes one document of the task, run key or not`)
  }
}
ck(covered >= 10, `most roles carry a default output (got ${covered})`)
// the authors of the artifact chain write the file of their own level
const want = { 'spec-author': 'specification.md', 'scenario-author': 'scenarios.md', 'coverage-checker': 'coverage.md', 'plan-author': 'implementation-plan.md' }
for (const [role, file] of Object.entries(want)) {
  ck(b.roleOutPath('/t/task', role) === `/t/task/${file}`, `${role} writes ${file} (got ${b.roleOutPath('/t/task', role)})`)
}
// the roles of the run directories, named: the run key stands in the file name itself
const perRun = { 'code-author': 'changes/code-r1.md', fixer: 'changes/fix-r1.md', critic: 'reviews/hints-r1.md', executor: 'runs/run-r1.md' }
for (const [role, file] of Object.entries(perRun)) {
  ck(b.roleOutPath('/t/task', role, 'r1') === `/t/task/${file}`, `${role} writes ${file} (got ${b.roleOutPath('/t/task', role, 'r1')})`)
}
// a role with no row keeps `out` required: the script may not invent a file for it
ck(b.roleOut('translator') === null, 'a role with no layout row has no default')
ck(b.roleOutPath('/t/task', 'translator', 'r1') === null, 'and builds no path')
console.log(out.join('\n'))
JS
node "$T/roleout.js" "$LIB/block.js" "$LAYOUT" > "$T/roleout.out" 2>&1
if [ ! -s "$T/roleout.out" ]; then
  fail "r8 the role-output suite produced no line (node failed)"
  sed 's/^/  /' "$T/roleout.out" 2>/dev/null
else
  while IFS= read -r line; do
    case $line in
      "ok "*) pass ;;
      "bad "*) fail "r8 ${line#bad }" ;;
      *) fail "r8 unexpected output: $line" ;;
    esac
  done < "$T/roleout.out"
fi
if [ -f "$ROLEJS" ]; then
  check "r8 role.js resolves a task directory through roleOutPath()" grep -q 'roleOutPath(' <<<"$code"
  # a layout directory is one level below the task directory and a shell redirect makes no
  # directory: the tail carries the mkdir, built by writeHint() of the shared block
  check "r8 role.js tells a shell-only role to make its directory" grep -Fq 'writeHint(' <<<"$code"
  # the one role whose output is its return writes no file, so no path is demanded of it: the
  # whole decision is textResult() of the shared block, executed by r9 below
  check "r8 role.js checks the closure role on its return, not on a file" grep -Fq 'textResult(' <<<"$code"
  check "r8 role.js reads a text-mode out through taskDirOf()" grep -Fq 'taskDirOf(' <<<"$code"
  # the one rule all four scripts read `out` by: a task directory handed over without a trailing
  # slash is still the task directory, never a file whose output lands one level up in tasks/
  check "r8 role.js decides the form of out through outForm()" grep -Fq 'outForm(OUT)' <<<"$code"
  check "r8 role.js hands the run key of the launch to roleOutPath()" grep -Fq 'roleOutPath(form.dir, ROLE, RUNKEY)' <<<"$code"
  check "r8 the contract of role names the task-directory form of out" \
    grep -qiE "^out \(.*(task|layout)" <<<"$(awk 'f==0&&/^\/\* usage:/{f=1} f{print} f&&/\*\//{exit}' "$ROLEJS")"
fi
CHAINJS=$WF/chain.js
if [ -f "$CHAINJS" ]; then
  ccode=$(python3 - "$CHAINJS" <<'PY'
import sys
lines = open(sys.argv[1], encoding='utf-8').read().split('\n')
skip, out = False, []
for l in lines:
    s = l.strip()
    if skip:
        if s.startswith(('// ---- end shared block', '// ---- end roles', '// ---- end aspects')): skip = False
        continue
    if s.startswith(('// ---- shared block', '// ---- roles', '// ---- aspects')):
        skip = True
        continue
    out.append(l)
print('\n'.join(out))
PY
)
  check "r8 chain.js builds its stage paths through taskPath()" grep -q 'taskPath(' <<<"$ccode"
  bad=
  for k in $(grep -oE "side\('[a-z-]+'" <<<"$ccode" | sed "s/side('//; s/'//" | sort -u); do
    node -e 'require(process.argv[1]).taskEntry(process.argv[2])' "$LIB/block.js" "$k" 2>/dev/null || bad="$bad $k"
  done
  check "r8 chain.js names no key outside the layout (extra:$bad)" test -z "$bad"
  check "r8 chain.js spells no stage path by hand" bash -c '! grep -qE "\\$\{DIR\}/[a-z]" <<<"$1"' _ "$ccode"
  check "r8 chain.js takes its task directory from outForm" grep -Fq 'outForm(OUT)' <<<"$ccode"
  check "r8 chain.js builds the files of a run directory with the run key" grep -Fq 'runStem(stem, RUNKEY)' <<<"$ccode"
  check "r8 chain.js demands that run key" grep -Fq 'if (!RUNKEY) return fail(' <<<"$ccode"
  check "r8 chain.js tells a shell-only stage to make its directory" grep -Fq 'writeHint(' <<<"$ccode"
fi

# ---- r9 (P5): the text-mode stage and the task directory, executed, not grepped ----
# The role whose whole output is its return (closure-author) is decided by textResult() of the
# shared block, and the task directory of an `out` argument by taskDirOf(): both run here over
# lib/block.js, and the mutants below prove the suite really decides them.
cat > "$T/textres.js" <<'JS'
const b = require(process.argv[2])
const out = []
const ck = (cond, what) => out.push(`${cond ? 'ok' : 'bad'} ${what}`)
const head = { role: 'closure-author', class: 'c3', slot: 'sonnet', label: 'son-hi-closure-author' }
const AG = 'session:tools-read-write'
const good = b.textResult('the run closed every subtask\nDONE', head, AG)
ck(good.out === null, 'a finished text stage returns no path: no file was written')
ck(good.report === 'the run closed every subtask', 'the report is the return without its shape line')
ck(good.blocked === undefined, 'a finished text stage carries no blocked line')
ck(good.role === 'closure-author' && good.slot === 'sonnet' && good.label === head.label, 'the head fields stand')
ck(good.agent === AG, 'the agent type stands on a finished stage')
ck(good.result === 'DONE', 'the last line of the return is the result line')
const denied = b.textResult('BLOCKED: denied', head, AG)
ck(denied.out === null, 'a blocked text stage returns no path either')
ck(/^BLOCKED: /.test(String(denied.blocked)), 'a blocked return is a blocked stage')
ck(denied.report === undefined, 'and carries no report')
ck(/^BLOCKED: /.test(String(b.textResult('DONE', head, AG).blocked)), 'a return of nothing but its shape line is blocked')
ck(/^BLOCKED: /.test(String(b.textResult('', head, AG).blocked)), 'an empty return is blocked')
// taskDirOf: a task directory is a directory whatever its slug reads like
ck(b.taskDirOf('/p/tasks/2026-09-20-v0.16') === '/p/tasks/2026-09-20-v0.16', 'a dotted slug keeps its own directory')
ck(b.taskDirOf('/p/tasks/t/') === '/p/tasks/t', 'a trailing slash is stripped')
ck(b.taskPath(b.taskDirOf('/p/tasks/2026-09-20-v0.16'), 'report') === '/p/tasks/2026-09-20-v0.16/report.md', 'and its stage files stay inside it')
let threw = false
try { b.taskDirOf('/p/tasks/t/report.md') } catch (e) { threw = true }
ck(threw, 'a document path is no task directory')
threw = false
try { b.taskDirOf('rel/dir') } catch (e) { threw = true }
ck(threw, 'a relative path is refused')
// outForm: the one rule all four scripts read `out` by. A trailing slash decides nothing, because
// a launcher is free to drop it: the last segment decides, and only a document suffix makes a file
ck(b.outForm('/p/tasks/t/').file === null, 'a task directory with a trailing slash is a directory')
ck(b.outForm('/p/tasks/t').file === null, 'a task directory without one is the same directory')
ck(b.outForm('/p/tasks/t').dir === '/p/tasks/t', 'and the directory is itself, not its parent')
ck(b.outForm('/p/tasks/2026-09-20-v0.16').dir === '/p/tasks/2026-09-20-v0.16', 'a dotted slug is a directory too')
const ff = b.outForm('/p/tasks/t/reviews/accepted.md')
ck(ff.file === '/p/tasks/t/reviews/accepted.md', 'a document is the file it names')
ck(ff.dir === '/p/tasks/t/reviews', 'and its directory is the one it sits in')
threw = false
try { b.outForm('rel/out.md') } catch (e) { threw = true }
ck(threw, 'a relative out is refused')
threw = false
try { b.outForm('/out.md') } catch (e) { threw = true }
ck(threw, 'a file at the root sits in no task directory')
// runStem: a `dir` row of the layout is one file per run, and the key comes from the launcher
ck(b.runStem('fix', 'r2') === 'fix-r2', 'the run key stands in the file name')
ck(b.runStem('fix', 'r2') !== b.runStem('fix', 'r3'), 'two runs write two files')
threw = false
try { b.runStem('fix', '') } catch (e) { threw = true }
ck(threw, 'a missing run key is an error, never a silent overwrite')
threw = false
try { b.roleOutPath('/t/task', 'code-author') } catch (e) { threw = true }
ck(threw, 'and a role of a run directory launched without one writes nothing')
console.log(out.join('\n'))
JS
node "$T/textres.js" "$LIB/block.js" > "$T/textres.out" 2>&1
if [ ! -s "$T/textres.out" ]; then
  fail "r9 the text-mode suite produced no line (node failed)"
  sed 's/^/  /' "$T/textres.out" 2>/dev/null
else
  while IFS= read -r line; do
    case $line in
      "ok "*) pass ;;
      "bad "*) fail "r9 ${line#bad }" ;;
      *) fail "r9 unexpected output: $line" ;;
    esac
  done < "$T/textres.out"
fi
i=0
while IFS='|' read -r what expr; do
  [ -n "$what" ] || continue
  i=$((i + 1))
  perl -pe "$expr" "$LIB/block.js" > "$T/tmutant$i.js"
  check "r9 mutant $i is really a mutation" bash -c '! cmp -s "$1" "$2"' _ "$LIB/block.js" "$T/tmutant$i.js"
  node "$T/textres.js" "$T/tmutant$i.js" > "$T/tmutant$i.out" 2>&1
  check "r9 the suite catches the mutant: $what" grep -q '^bad ' "$T/tmutant$i.out"
done <<'MUT'
a text stage hands back a path to a file nobody wrote|s/out: null \}/out: 'x' }/
a gap of the closing report passes as a finished stage|s/if \(!c\.ok\) return \{ \.\.\.h/if (false) return { ...h/
a task directory with a document suffix is taken as one|s/\.\(md\|jsonl/.(mdx|jsonl/
a task directory is read as a file and its stage files land one level up|s/\{ dir: taskDirOf\(p\), file: null \}/{ dir: p.slice(0, cut), file: p }/
a file of one run overwrites the file of the run before it|s/if \(!k\) throw new Error/if (false) throw new Error/
MUT

# ---- r10: a critique reaches a role as hints, never as verdicts (idea 3.6) ----
# A role text that lets a hint, a critique or a critic withdraw or drop a claim by itself makes the
# doubt a verdict, and the role then loses a fact its sources proved with no fact against it. The
# rule is executed through hintVerdictHits() of lib/block.js over every role text, and the role that
# writes an answer on a critique has to state what a hint may do, or the shape comes back the next
# time the sentence is rewritten.
cat > "$T/hintrole.js" <<'JS'
const fs = require('fs')
const b = require(process.argv[2])
let bad = 0
for (const p of process.argv.slice(3)) {
  const t = fs.readFileSync(p, 'utf8')
  for (const h of b.hintVerdictHits(t)) { console.log(`${p}: a hint as a verdict: ${h}`); bad++ }
}
process.exit(bad ? 1 : 0)
JS
check "r10 no role text lets a hint act as a verdict" \
  node "$T/hintrole.js" "$LIB/block.js" "${FILES[@]}"
if [ -f "$R/synthesizer.md" ]; then
  cat > "$T/phr.js" <<'JS'
const fs = require('fs')
const b = require(process.argv[2])
const gap = b.phraseGap(fs.readFileSync(process.argv[3], 'utf8'), process.argv.slice(4))
gap.forEach(g => console.log('missing: ' + g))
process.exit(gap.length ? 1 : 0)
JS
  check "r10 the role that writes an answer on a critique states what a hint may do" \
    node "$T/phr.js" "$LIB/block.js" "$R/synthesizer.md" \
    'hints, not verdicts' 'only when a fact' 'refutes it' 'not checked'
fi
# executed, not read: the sentence that cost a true fact must be seen, and a mutant of the rule must
# stop seeing it
printf 'Where the critique withdraws a fact, drop it from the answer.\n' > "$T/verdict.md"
check "r10 a text that lets the critique withdraw a fact is seen" \
  bash -c '! node "$1" "$2" "$3" > /dev/null' _ "$T/hintrole.js" "$LIB/block.js" "$T/verdict.md"
perl -pe "s/'critique', 'critiques'/'zzcritique', 'zzcritiques'/" "$LIB/block.js" > "$T/hmutant.js"
check "r10 the mutant is really a mutation" bash -c '! cmp -s "$1" "$2"' _ "$LIB/block.js" "$T/hmutant.js"
check "r10 the mutant still loads" node -e 'require(process.argv[1])' "$T/hmutant.js"
check "r10 the mutant that drops the critique as a subject is caught" \
  bash -c 'node "$1" "$2" "$3" > /dev/null' _ "$T/hintrole.js" "$T/hmutant.js" "$T/verdict.md"

if [ "$FAILS" -eq 0 ]; then echo "roles: PASS $N"; exit 0; fi
echo "roles: FAIL $FAILS failures, $N checks passed"
exit 1
