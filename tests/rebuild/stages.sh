#!/bin/bash
# Static oracle of P4: the composite flows are verification-first by construction.
# Globs: plugins/session/lib/block.js (node), plugins/session/workflows/{make,probe}.js (grep only),
#        plugins/session/lib/build-manifest.json, plugins/session/.claude-plugin/plugin.json,
#        tests/measure/rebuild-scenarios-0.16.txt.
# Proves: `stageRange` returns every stage alone, every contiguous range and the whole flow by
# default, and rejects an unknown name and a backwards range, so every old `dev` gate is a launch of
# one stage that can run alone; `makePlan` reads its depth ceiling from lib/classes.json, folds the
# upper levels at `lite`, sends the key document to the evidence chain one class step up and runs
# the negative control at `full` only; a test suite that passes on the base version is a gap, never
# an acceptance; the fix cycle is a ceiling that ends the stage and writes the gap instead of
# retrying; an executor return that says neither PASS nor FAIL settles nothing; every exit of a
# composite flow is built by one result builder, so a blocked or failing stage never returns the
# shape of a finished run; no flow with an oracle output carries a review stage over that output,
# every such flow has an executor stage, and every stage that names an output file is checked for
# existence and non-emptiness. Every decision is executed over lib/block.js, never grepped out of a
# workflow file, and each rule is re-run over a mutant that must turn that same named rule red.
# Temp dirs only, no network, no session, under 20 s.
set -u

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
P=$REPO/plugins/session
LIB=$P/lib
WF=$P/workflows
PJ=$P/.claude-plugin/plugin.json
BUILD=$P/bin/build.sh
SCEN=$REPO/tests/measure/rebuild-scenarios-0.16.txt
CAP=110

T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT

N=0; FAILS=0
pass() { N=$((N + 1)); }
fail() { echo "FAIL $1"; FAILS=$((FAILS + 1)); }
check() { local label=$1; shift; if "$@"; then pass; else fail "$label"; fi; }

# code_of <file>: the hand-written code of a workflow, with every generated region cut out.
code_of() {
  python3 - "$1" <<'PY'
import sys
lines = open(sys.argv[1], encoding='utf-8').read().split('\n')
skip, out = False, []
for l in lines:
    s = l.strip()
    if skip:
        if s.startswith(('// ---- end shared block', '// ---- end roles', '// ---- end aspects')):
            skip = False
        continue
    if s.startswith(('// ---- shared block', '// ---- roles', '// ---- aspects')):
        skip = True
        continue
    out.append(l)
print('\n'.join(out))
PY
}

# stamped_roles <file>: the role names stamped between the roles markers.
stamped_roles() {
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

# ---- s1: every decision of the two flows, executed over lib/block.js ----
cat > "$T/stages.js" <<'JS'
const b = require(process.argv[2])
const out = []
const ck = (cond, what) => out.push(`${cond ? 'ok' : 'bad'} ${what}`)
const eq = (got, want, what) => ck(JSON.stringify(got) === JSON.stringify(want),
  `${what}: got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`)

// ---- the stage range: every old `dev` gate is one stage that can run alone (idea 7) ----
const ALL = b.MAKE_STAGES
eq(ALL, ['spec', 'scenarios', 'tests', 'code', 'executor', 'coverage', 'fixer'],
  'the stage list of make, in the order of the artifact chain')
for (const s of ALL) {
  const r = b.stageRange(s, s)
  eq(r.ok && r.stages, [s], `stageRange ${s}..${s} runs that stage alone`)
}
let ranges = 0
for (let i = 0; i < ALL.length; i++) {
  for (let j = i; j < ALL.length; j++) {
    const r = b.stageRange(ALL[i], ALL[j])
    if (r.ok && r.stages.join(' ') === ALL.slice(i, j + 1).join(' ')) { ranges += 1; continue }
    ck(false, `stageRange ${ALL[i]}..${ALL[j]}: got ${JSON.stringify(r.stages)}`)
  }
}
ck(ranges === (ALL.length * (ALL.length + 1)) / 2, `every contiguous range resolves (got ${ranges})`)
eq(b.stageRange(null, null).stages, ALL, 'no from and no until is the whole flow')
eq(b.stageRange('', '').stages, ALL, 'two empty strings are the whole flow')
eq(b.stageRange('code', null).stages, ALL.slice(3), 'a from alone runs to the last stage')
eq(b.stageRange(null, 'tests').stages, ALL.slice(0, 3), 'an until alone starts at the first stage')
const unknown = b.stageRange('spec', 'nosuch')
ck(unknown.ok === false, 'an unknown until is rejected')
ck(/nosuch/.test(String(unknown.why)), `the rejection names the unknown stage (${unknown.why})`)
ck(/^BLOCKED: /.test(String(unknown.why)), 'the rejection carries the blocked word once')
eq(unknown.stages, [], 'a rejected range runs no stage at all')
ck(b.stageRange('nosuch', 'code').ok === false, 'an unknown from is rejected')
const inv = b.stageRange('fixer', 'spec')
ck(inv.ok === false, 'a backwards range is rejected')
ck(/spec/.test(String(inv.why)) && /fixer/.test(String(inv.why)), 'the rejection names both ends')
ck(b.stageOn(b.stageRange('code', 'executor'), 'code') === true, 'a stage of the range is on')
ck(b.stageOn(b.stageRange('code', 'executor'), 'spec') === false, 'a stage before the range is off')
ck(b.stageOn(b.stageRange('code', 'executor'), 'fixer') === false, 'a stage after the range is off')
ck(b.stageOn(unknown, 'spec') === false, 'a rejected range switches no stage on')

// ---- the depth plan: the ceilings of A30 and the two verification-first branches ----
const R = b.stageRange(null, null)
const lite = b.makePlan('lite', R)
ck(lite.stages.indexOf('spec') === -1, 'lite folds the specification into the short form (A5)')
ck(lite.stages.indexOf('coverage') === -1, 'lite writes no coverage report')
ck(lite.stages.indexOf('tests') !== -1, 'lite still writes the tests')
ck(lite.keyCheck === false, 'lite sends no key document to the evidence chain')
ck(lite.control === false, 'lite runs no negative control')
ck(lite.cycles === b.ceiling('lite').cycles, 'the cycle ceiling comes from the depth table')
const std = b.makePlan('std', R)
eq(std.stages, ALL, 'std runs every stage of the range')
ck(std.keyCheck === true, 'std checks the key document one class step up (3.5 rule 3)')
ck(std.control === false, 'the negative control is a rule of full, not of std')
ck(std.cycles === b.ceiling('std').cycles, 'std takes its cycles from the depth table')
const full = b.makePlan('full', R)
ck(full.control === true, 'full runs the negative control (3.5 rule 1, ladder level c)')
ck(full.keyCheck === true, 'full checks the key document too')
ck(full.cycles === b.ceiling('full').cycles, 'full takes its cycles from the depth table')
ck(b.makePlan('full', b.stageRange('code', 'coverage')).control === false,
  'no tests stage in the range, no negative control to run')
ck(b.makePlan('std', b.stageRange('scenarios', 'code')).keyCheck === false,
  'no spec stage in the range, no key document to check')
try { b.makePlan('deep', R); ck(false, 'makePlan over an unknown depth throws') } catch (e) {
  ck(/deep/.test(String(e.message)), `makePlan names the unknown depth (${e.message})`)
}
try { b.makePlan('std', b.stageRange('nosuch', 'code')); ck(false, 'makePlan over a rejected range throws') } catch (e) {
  ck(/range/.test(String(e.message)), `makePlan refuses a rejected range (${e.message})`)
}

// ---- the negative control: a suite that passes on the base version proves nothing ----
eq(b.negativeControl('full', 'FAIL'),
  { required: true, ran: true, ok: true, verdict: 'FAIL', gap: null },
  'the tests fail on the base version: the control passed')
const onBase = b.negativeControl('full', 'PASS')
ck(onBase.ok === false, 'the tests pass on the base version: not an acceptance')
ck(/base version/.test(String(onBase.gap)), `that is a gap of the run (${onBase.gap})`)
const noRead = b.negativeControl('full', 'unreadable')
ck(noRead.ok === false, 'a control run nobody could read settles nothing')
ck(String(noRead.gap || '').length > 0, 'and it is a gap too')
const noRun = b.negativeControl('full', null)
ck(noRun.ok === false && noRun.ran === false, 'a control run that never happened is no acceptance')
ck(b.negativeControl('std', null).required === false, 'std requires no control run')
ck(b.negativeControl('std', null).ok === true, 'and is not blocked by its absence')
ck(b.negativeControl('lite', null).gap === null, 'lite writes no control gap')
try { b.negativeControl('deep', 'FAIL'); ck(false, 'negativeControl over an unknown depth throws') } catch (e) {
  ck(/deep/.test(String(e.message)), `negativeControl names the unknown depth (${e.message})`)
}

// ---- the fix cycle: a ceiling that ends the stage, never a silent retry ----
eq(b.cycleState('lite', 0), { room: 1, used: 0, hit: false, gap: null }, 'lite allows one fix cycle')
const hit = b.cycleState('lite', 1)
ck(hit.hit === true, 'the second cycle at lite never starts')
ck(/ceiling/.test(String(hit.gap)), `the ceiling writes the gap (${hit.gap})`)
ck(b.cycleState('std', 1).hit === false, 'std allows a second cycle')
ck(b.cycleState('std', 2).hit === true, 'std stops at its ceiling')
ck(b.cycleState('full', 2).gap === null, 'a cycle below the ceiling writes no gap')
ck(b.cycleState('full', 3).hit === true, 'full stops at its ceiling')
try { b.cycleState('std', 'many'); ck(false, 'a cycle count that is no number throws') } catch (e) {
  ck(/cycle/.test(String(e.message)), `cycleState names what it wanted (${e.message})`)
}

// ---- the oracle verdict of an executor return ----
ck(b.runVerdict('/tmp/run/out.txt 40 bytes\nPASS exit 0, 4 tests\nDONE') === 'PASS', 'a PASS line is a pass')
ck(b.runVerdict('/tmp/run/out.txt 40 bytes\nFAIL exit 1: 2 failures\nDONE') === 'FAIL', 'a FAIL line is a failure')
ck(b.runVerdict('- **PASS** | exit 0') === 'PASS', 'a decorated verdict line still binds')
ck(b.runVerdict('FAIL exit 1\nPASS after my fix') === 'FAIL', 'the first readable verdict decides')
ck(b.runVerdict('the run says nothing about its exit\nDONE') === 'unreadable', 'prose is no verdict')
ck(b.runVerdict('passed the check, I think') === 'unreadable', 'prose about passing is no verdict')
ck(b.runVerdict(null) === 'unreadable', 'no return, no verdict')
ck(b.runVerdict('') === 'unreadable', 'an empty return, no verdict')

// ---- one result builder per flow: a blocked stage never returns the shape of a finished run ----
const S = {
  out: '/tmp/run/report.md', from: 'spec', until: 'fixer', stages: ALL,
  done: ALL, files: ['/tmp/run/make-spec.md'],
}
const stopped = b.makeResult({ ...S, done: ['spec'], stage: 'code', blocked: 'the tool was denied' })
ck(stopped.ok === false, 'a blocked stage is never a finished run')
ck(/^BLOCKED: /.test(String(stopped.blocked)), 'the blocked line opens with the word')
ck((String(stopped.blocked).match(/BLOCKED:/g) || []).length === 1, 'and carries it exactly once')
ck(stopped.stage === 'code', 'the result names the stage that stopped')
ck(/code/.test(String(stopped.status)), `the status names it too (${stopped.status})`)
ck(b.makeResult({ ...S, stage: 'code', blocked: 'BLOCKED: the tool was denied' }).blocked
  === 'BLOCKED: the tool was denied', 'a reason that already carries the word is not prefixed twice')
ck(b.makeResult({ ...S, run: 'FAIL' }).ok === false, 'a failing oracle is no finished run')
ck(b.makeResult({ ...S, run: 'unreadable' }).ok === false, 'an unreadable oracle result is no pass')
ck(b.makeResult(S).ok === false, 'a run with no oracle result at all is no pass')
const done = b.makeResult({ ...S, run: 'PASS' })
ck(done.ok === true, 'the range ran to its end and the oracle passed')
ck(done.blocked === undefined, 'a finished run carries no blocked line')
ck(done.range === 'spec..fixer', `the result names the range it ran (${done.range})`)
const ctlBad = b.makeResult({ ...S, run: 'PASS', control: b.negativeControl('full', 'PASS') })
ck(ctlBad.ok === false, 'a suite that passes on the base version is no finished run either')
ck((ctlBad.gap || []).filter(g => /base version/.test(g)).length === 1, 'and that gap stands in the result')
ck(b.makeResult({ ...S, run: 'PASS', control: b.negativeControl('full', 'FAIL') }).ok === true,
  'a control run that failed on the base version leaves the run ok')
const capped = b.makeResult({ ...S, run: 'FAIL', cycles: 1, gap: ['the fix cycle ceiling of 1 ended the stage'] })
ck(capped.ok === false && capped.gap.length === 1, 'a hit ceiling stands in the result as a gap')
ck(capped.cycles === 1, 'the result counts the cycles that ran')
const foldedRun = b.makeResult({ ...S, run: 'PASS', folded: ['spec', 'coverage'] })
ck(foldedRun.ok === true, 'a level the depth folded is no gap of the run')
ck(foldedRun.folded.length === 2, 'and the result names what was folded')
ck(/folded/.test(String(foldedRun.status)), 'the status says it too')
ck(b.makeResult({}).ok === false, 'an empty state is no finished run')
ck(typeof b.makeResult({}).status === 'string', 'every make result carries a status sentence')

const PB = {
  out: '/tmp/run/synthesis.md', directions: ['one', 'two'],
  bundles: ['/tmp/run/probe-1.md', '/tmp/run/probe-2.md'],
  critique: '/tmp/run/probe-critique.md', synthesis: '/tmp/run/synthesis.md',
}
ck(b.probeResult(PB).ok === true, 'two bundles, a critique and a synthesis is a finished probe')
ck(b.probeResult(PB).blocked === undefined, 'a finished probe carries no blocked line')
const pStopped = b.probeResult({ ...PB, stage: 'synthesis', blocked: 'the tool was denied' })
ck(pStopped.ok === false, 'a blocked probe stage is never a finished run')
ck(/^BLOCKED: /.test(String(pStopped.blocked)), 'its blocked line opens with the word')
ck(pStopped.stage === 'synthesis', 'and names the stage that stopped')
ck(b.probeResult({ ...PB, synthesis: null }).ok === false, 'no synthesis file, no finished probe')
ck(b.probeResult({ ...PB, critique: null }).ok === false, 'no critique, no finished probe')
ck(b.probeResult({ ...PB, bundles: [] }).ok === false, 'no bundle, no finished probe')
ck(b.probeResult({}).ok === false, 'an empty state is no finished probe')
ck(b.probeResult({ ...PB, gap: ['direction three never started: the ceiling was full'] }).gap.length === 1,
  'a direction the ceiling left out stands in the result as a gap')
ck(typeof b.probeResult(PB).status === 'string', 'every probe result carries a status sentence')
console.log(out.join('\n'))
JS

run_suite() { # run_suite <block.js> <out>
  node "$T/stages.js" "$1" > "$2" 2>&1
}
run_suite "$LIB/block.js" "$T/s1.out"
if [ ! -s "$T/s1.out" ]; then
  fail "s1 the decision suite produced no line (node failed)"
else
  while IFS= read -r line; do
    case $line in
      "ok "*) pass ;;
      "bad "*) fail "s1 ${line#bad }" ;;
      *) fail "s1 unexpected output: $line" ;;
    esac
  done < "$T/s1.out"
fi

# ---- s2: the mutants — each breaks one named rule, and the suite above must go red on each ----
i=0
while IFS='|' read -r what expr; do
  [ -n "$what" ] || continue
  i=$((i + 1))
  perl -pe "$expr" "$LIB/block.js" > "$T/mutant$i.js"
  check "s2 mutant $i is really a mutation: $what" bash -c '! cmp -s "$1" "$2"' _ "$LIB/block.js" "$T/mutant$i.js"
  run_suite "$T/mutant$i.js" "$T/mutant$i.out"
  check "s2 the suite catches the mutant: $what" grep -q '^bad ' "$T/mutant$i.out"
done <<'MUT'
a backwards stage range runs anyway|s/if \(i > j\)/if (false)/
the negative control is never required|s/const required = depth === 'full'/const required = false/
a suite that passes on the base version is accepted|s/const okBase = v === 'FAIL'/const okBase = true/
the fix cycle ceiling is never hit|s/const hit = ceilingHit\(depth, 'cycles', n\)/const hit = false/
a blocked stage returns the shape of a finished run|s/const ok = !blocked/const ok = true || !blocked/
the control gap no longer stops the run|s/&& \(!nc \|\| nc\.ok\)//
an unreadable run counts as a pass|s/const verdict = v === 'PASS' \|\| v === 'FAIL' \? v : 'unreadable'/const verdict = 'PASS'/
MUT

# ---- s3: the wiring of workflows/make.js ----
MAKE=$WF/make.js
if [ -f "$MAKE" ]; then
  code=$(code_of "$MAKE")
  check "s3 make.js carries the shared-block marker" grep -q '^// ---- shared block' "$MAKE"
  check "s3 make.js carries the roles marker" grep -q '^// ---- roles' "$MAKE"
  check "s3 make.js stamp is in sync with its sources" bash "$BUILD" --check "$MAKE"

  # every decision comes from the shared block, so a test executes it instead of reading this file
  for fn in stageRange stageOn makePlan negativeControl cycleState runVerdict makeResult outVerdict; do
    check "s3 make.js decides through $fn() of the shared block" grep -q "$fn(" <<<"$code"
  done
  check "s3 make.js takes the slot from the role map" grep -q 'roleSlot(' <<<"$code"
  check "s3 make.js takes the uplift of a no-oracle author from the role map" grep -q 'roleClass(' <<<"$code"
  check "s3 make.js takes the agent from the role map" grep -q 'roleAgent(' <<<"$code"
  check "s3 make.js stops on a rejected stage range" grep -Fq 'return fail(RANGE.why' <<<"$code"

  # one launch site, and it checks its output file: existence and non-emptiness in one verdict
  nag=$(grep -c 'await agent(' <<<"$code")
  check "s3 make.js launches agents from one stage helper only (got $nag)" test "$nag" -eq 1
  check "s3 that helper checks the output of every stage" python3 -c '
import re, sys
code = sys.argv[1]
m = re.search(r"(?ms)^async function stage\(.*?^\}", code)
if not m: print("no stage helper"); sys.exit(1)
body = m.group(0)
missing = [n for n in ("await agent(", "outVerdict(") if n not in body]
if missing: print("the stage helper misses:", " ".join(missing))
sys.exit(1 if missing else 0)
' "$code"

  # every exit of the flow goes through one result builder (or the argument gate before any stage)
  check "s3 every exit of make.js is fail() or the result builder" python3 -c '
import re, sys
code = sys.argv[1]
i = code.find("// ---- the flow")
if i == -1: print("no flow marker in the script"); sys.exit(1)
bad = [l.strip() for l in code[i:].split("\n")
       if re.match(r"^\s*return\b", l) and not re.match(r"^return (fail\(|result\()", l.strip())]
if bad: print("an exit outside the result builder:", " ;; ".join(bad[:3]))
sys.exit(1 if bad else 0)
' "$code"
  check "s3 make.js builds that result through makeResult" grep -Fq 'makeResult({' <<<"$code"
  check "s3 a blocked stage of make.js returns through the result builder" grep -Eq 'return result\(\{ stage:' <<<"$code"

  # verification-first: an oracle decides the output, so no review stage stands over it
  check "s3 make.js launches no critic and no evidence role over its own output" bash -c '! grep -Eq "\x27(critic|evidence|evidence-researcher|evidence-triage)\x27" <<<"$1"' _ "$code"
  check "s3 make.js carries no reviewer stage" bash -c '! grep -Eqi "reviewer|phase\(.Review" <<<"$1"' _ "$code"
  ks=$(stamped_roles "$MAKE" 2>/dev/null)
  for r in critic evidence evidence-researcher evidence-triage; do
    case " $ks " in
      *" $r "*) fail "s3 make.js stamps the chain role $r (stamped: $ks)" ;;
      *) pass ;;
    esac
  done
  check "s3 make.js stamps the executor role (stamped: $ks)" bash -c 'case " $1 " in *" executor "*) exit 0 ;; *) exit 1 ;; esac' _ "$ks"
  check "s3 make.js runs an executor stage over the oracle" grep -Fq "'executor'" <<<"$code"
  check "s3 make.js runs the coverage check of ladder level c" grep -Fq "'coverage-checker'" <<<"$code"
  check "s3 make.js requires the check command that decides" grep -Fq 'args.test' <<<"$code"

  # the negative control of 3.5 rule 1: the tests run on the base version and must fail there
  check "s3 make.js runs the tests against the base version" grep -q 'BASE' <<<"$code"
  check "s3 make.js decides that control run through negativeControl" grep -Fq 'negativeControl(DEPTH' <<<"$code"
  check "s3 make.js hands the control verdict to the result builder" grep -Fq 'control' <<<"$code"

  # the key document goes to the evidence chain one class step up (3.5 rule 3), never to a reviewer
  check "s3 make.js routes the key document to the evidence chain" grep -Fq "workflow('session:chain'" <<<"$code"
  check "s3 that chain run sits one class step above this run" grep -Fq 'RUN.up()' <<<"$code"
  check "s3 make.js names the chain fallback of the U8 answer in its contract" grep -q 'needs chain' "$MAKE"

  # the ceiling of A30 ends the stage and writes the gap, never a silent retry
  check "s3 make.js reads its cycle ceiling through cycleState" grep -Fq 'cycleState(DEPTH' <<<"$code"
  check "s3 the hit ceiling writes the gap" grep -Eq 'gap\.push\(CY\.gap\)|gap\.push\(.*\.gap\)' <<<"$code"

  # the class table is the only source of model and effort
  check "s3 make.js pins no model at the call site" bash -c '! grep -qE "^\s*(model|effort):" <<<"$1"' _ "$code"
  check "s3 make.js names no model word" bash -c '! grep -Eqi "(^|[^-a-z])(opus|sonnet|fable|haiku)([^-a-z]|$)" <<<"$1"' _ "$code"
  check "s3 make.js reads a return through the block, not by its own regex" bash -c '! grep -qE "/BLOCKED:?/|BLOCKED:.{0,3}\.test" <<<"$1"' _ "$code"
  check "s3 make.js logs the launch before the first argument check" python3 -c '
import sys
code = sys.argv[1]
sys.exit(0 if 0 < code.index("log(") < code.index("return fail(") else 1)
' "$code"
  check "s3 make.js requires an absolute output path" grep -Fq 'absolute path' <<<"$code"
  check "s3 make.js takes a list argument that is no array to the error path" grep -q 'Array.isArray' <<<"$code"
  check "s3 make.js names no skill" bash -c '! grep -qE "session:(ask|base|process|codex)" <<<"$1"' _ "$code"
  check "s3 make.js cites the verification page" grep -q 'lib/verification.md' <<<"$code"

  # the contract: one usage block, under the cap, naming the arguments a launcher needs
  usage=$(awk 'f==0&&/^\/\* usage:/{f=1} f{print} f&&/\*\//{exit}' "$MAKE")
  inner=$(printf '%s\n' "$usage" | sed -e 's#^/\* usage:##' -e 's#\*/##')
  words=$(printf '%s\n' "$inner" | wc -w | tr -d ' ')
  check "s3 the contract of make is under $CAP words (got $words)" test "$words" -lt "$CAP"
  for a in ask out test depth size; do
    check "s3 the contract of make names the argument $a on its own line" grep -qE "^$a \(" <<<"$inner"
  done
  check "s3 the contract of make names the stage range from and until" grep -qE "^from" <<<"$inner"
  check "s3 the contract of make names the stage names of that range" grep -q 'spec' <<<"$inner"
  check "s3 the contract of make names no model" bash -c '! grep -Eqi "(^|[^-a-z])(opus|sonnet|fable|haiku)([^-a-z]|$)" <<<"$1"' _ "$inner"

  want="sh \${CLAUDE_PLUGIN_ROOT}/bin/workflow-usage.sh --hook --file \${CLAUDE_PLUGIN_ROOT}/workflows/make.js --prefix session"
  hits=$(python3 -c '
import json, sys
groups = json.load(open(sys.argv[1]))["hooks"]["SessionStart"]
print(sum(1 for g in groups for h in g["hooks"] if h.get("command", "") == sys.argv[2]))
' "$PJ" "$want")
  check "s3 exactly one SessionStart entry for make.js (got $hits)" test "$hits" = 1
else
  fail "s3 plugins/session/workflows/make.js exists"
fi

# ---- s4: the wiring of workflows/probe.js ----
PROBE=$WF/probe.js
if [ -f "$PROBE" ]; then
  code=$(code_of "$PROBE")
  check "s4 probe.js carries the shared-block marker" grep -q '^// ---- shared block' "$PROBE"
  check "s4 probe.js carries the roles marker" grep -q '^// ---- roles' "$PROBE"
  check "s4 probe.js stamp is in sync with its sources" bash "$BUILD" --check "$PROBE"
  for fn in probeResult outVerdict roleSlot roleClass roleAgent; do
    check "s4 probe.js decides through $fn() of the shared block" grep -q "$fn(" <<<"$code"
  done
  nag=$(grep -c 'await agent(' <<<"$code")
  check "s4 probe.js launches agents from one stage helper only (got $nag)" test "$nag" -eq 1
  check "s4 that helper checks the output of every stage" python3 -c '
import re, sys
code = sys.argv[1]
m = re.search(r"(?ms)^async function stage\(.*?^\}", code)
if not m: print("no stage helper"); sys.exit(1)
body = m.group(0)
missing = [n for n in ("await agent(", "outVerdict(") if n not in body]
if missing: print("the stage helper misses:", " ".join(missing))
sys.exit(1 if missing else 0)
' "$code"
  check "s4 every exit of probe.js is fail() or the result builder" python3 -c '
import re, sys
code = sys.argv[1]
i = code.find("// ---- the flow")
if i == -1: print("no flow marker in the script"); sys.exit(1)
bad = [l.strip() for l in code[i:].split("\n")
       if re.match(r"^\s*return\b", l) and not re.match(r"^return (fail\(|result\()", l.strip())]
if bad: print("an exit outside the result builder:", " ;; ".join(bad[:3]))
sys.exit(1 if bad else 0)
' "$code"
  check "s4 probe.js builds that result through probeResult" grep -Fq 'probeResult({' <<<"$code"
  check "s4 probe.js runs its directions in parallel" grep -q 'parallel(' <<<"$code"
  check "s4 probe.js seats the directions under the ceiling of A30" grep -Eq 'stageSeats\(|chainSeats\(' <<<"$code"
  check "s4 probe.js writes the directions the ceiling left out as a gap" grep -q 'gap' <<<"$code"
  # the critique of probe stands over research bundles, an output no oracle can decide
  check "s4 probe.js critiques the bundles" grep -Fq "'critic'" <<<"$code"
  check "s4 probe.js synthesises them" grep -Fq "'synthesizer'" <<<"$code"
  check "s4 probe.js names no check command: its output has no oracle" bash -c '! grep -Fq "args.test" <<<"$1"' _ "$code"
  check "s4 probe.js pins no model at the call site" bash -c '! grep -qE "^\s*(model|effort):" <<<"$1"' _ "$code"
  check "s4 probe.js names no model word" bash -c '! grep -Eqi "(^|[^-a-z])(opus|sonnet|fable|haiku)([^-a-z]|$)" <<<"$1"' _ "$code"
  check "s4 probe.js reads a return through the block, not by its own regex" bash -c '! grep -qE "/BLOCKED:?/|BLOCKED:.{0,3}\.test" <<<"$1"' _ "$code"
  check "s4 probe.js logs the launch before the first argument check" python3 -c '
import sys
code = sys.argv[1]
sys.exit(0 if 0 < code.index("log(") < code.index("return fail(") else 1)
' "$code"
  check "s4 probe.js requires an absolute output path" grep -Fq 'absolute path' <<<"$code"
  check "s4 probe.js takes a list argument that is no array to the error path" grep -q 'Array.isArray' <<<"$code"
  check "s4 probe.js names no skill" bash -c '! grep -qE "session:(ask|base|process|codex)" <<<"$1"' _ "$code"

  usage=$(awk 'f==0&&/^\/\* usage:/{f=1} f{print} f&&/\*\//{exit}' "$PROBE")
  inner=$(printf '%s\n' "$usage" | sed -e 's#^/\* usage:##' -e 's#\*/##')
  words=$(printf '%s\n' "$inner" | wc -w | tr -d ' ')
  check "s4 the contract of probe is under $CAP words (got $words)" test "$words" -lt "$CAP"
  for a in ask directions out size; do
    check "s4 the contract of probe names the argument $a on its own line" grep -qE "^$a \(" <<<"$inner"
  done
  check "s4 the contract of probe names no model" bash -c '! grep -Eqi "(^|[^-a-z])(opus|sonnet|fable|haiku)([^-a-z]|$)" <<<"$1"' _ "$inner"

  want="sh \${CLAUDE_PLUGIN_ROOT}/bin/workflow-usage.sh --hook --file \${CLAUDE_PLUGIN_ROOT}/workflows/probe.js --prefix session"
  hits=$(python3 -c '
import json, sys
groups = json.load(open(sys.argv[1]))["hooks"]["SessionStart"]
print(sum(1 for g in groups for h in g["hooks"] if h.get("command", "") == sys.argv[2]))
' "$PJ" "$want")
  check "s4 exactly one SessionStart entry for probe.js (got $hits)" test "$hits" = 1
else
  fail "s4 plugins/session/workflows/probe.js exists"
fi

# ---- s5: the behavior scenarios of this part are written, whoever runs them ----
if [ -f "$SCEN" ]; then
  block_of() {
    awk -v k="$1" '$0 ~ "^"k"[[:space:]]" {f=1} f&&/^[A-Za-z][A-Za-z0-9_-]*[[:space:]].*prompts:/&&$1!=k{exit} f{print}' "$SCEN"
  }
  mk=$(block_of make-smoke)
  check "s5 the scenario make-smoke exists" test -n "$mk"
  check "s5 make-smoke names its prompts" grep -q 'prompts:' <<<"$mk"
  for fld in base setup finish PASS; do
    check "s5 make-smoke carries the field $fld" grep -qE "^[[:space:]]+$fld:" <<<"$mk"
  done
  check "s5 make-smoke launches session:make" grep -q 'session:make' <<<"$mk"
  check "s5 make-smoke gates its reading prompt on the workflow finish notice" grep -qE '^[[:space:]]+finish: [0-9]+ [0-9]+$' <<<"$mk"
  check "s5 make-smoke judges only the lines after that notice" grep -qi 'only the lines after the workflow finish notice' <<<"$mk"
  check "s5 make-smoke demands scenarios and tests" bash -c 'grep -qi "scenario" <<<"$1" && grep -qi "test" <<<"$1"' _ "$mk"
  check "s5 make-smoke demands a PASS from the executor" grep -qi 'executor' <<<"$mk"
  check "s5 make-smoke fails on a review stage over the tested code" grep -qi 'no review stage' <<<"$mk"

  pr=$(block_of probe-smoke)
  check "s5 the scenario probe-smoke exists" test -n "$pr"
  check "s5 probe-smoke names its prompts" grep -q 'prompts:' <<<"$pr"
  for fld in base setup finish PASS; do
    check "s5 probe-smoke carries the field $fld" grep -qE "^[[:space:]]+$fld:" <<<"$pr"
  done
  check "s5 probe-smoke launches session:probe" grep -q 'session:probe' <<<"$pr"
  check "s5 probe-smoke gates its reading prompt on the workflow finish notice" grep -qE '^[[:space:]]+finish: [0-9]+ [0-9]+$' <<<"$pr"
  check "s5 probe-smoke judges only the lines after that notice" grep -qi 'only the lines after the workflow finish notice' <<<"$pr"
  check "s5 probe-smoke demands two bundles, one critique and one synthesis" bash -c 'grep -qi "two bundle" <<<"$1" && grep -qi "critique" <<<"$1" && grep -qi "synthesis" <<<"$1"' _ "$pr"
else
  fail "s5 tests/measure/rebuild-scenarios-0.16.txt exists"
fi

# ---- s6: the build manifest carries both new scripts with their stamped subsets ----
check "s6 the manifest names make.js and probe.js" python3 -c '
import json, sys
t = {x["path"]: x for x in json.load(open(sys.argv[1]))["targets"]}
bad = []
for p in ("workflows/make.js", "workflows/probe.js"):
    if p not in t: bad.append("missing " + p); continue
    if not t[p].get("block"): bad.append(p + " declares no shared block")
    if not t[p].get("roles"): bad.append(p + " stamps no role")
if bad: print("; ".join(bad))
sys.exit(1 if bad else 0)
' "$LIB/build-manifest.json"

if [ "$FAILS" -eq 0 ]; then echo "stages: PASS $N"; exit 0; fi
echo "stages: FAIL $FAILS failures, $N checks passed"
exit 1
