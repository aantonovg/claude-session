#!/bin/bash
# Static oracle of P3: the review chain of idea 3.6 is a chain of decisions a test can execute.
# Globs: plugins/session/lib/block.js (node), plugins/session/lib/aspects/*.md,
#        plugins/session/lib/roles/critic.md, plugins/session/workflows/chain.js (grep only),
#        plugins/session/.claude-plugin/plugin.json, tests/measure/rebuild-scenarios-0.16.txt.
# Proves: two critics hinting at the same place give one evidence run, the group keeping both
# aspect tags and the higher severity; the hint cap of 5 per critic (A27); an unknown aspect name
# stops the workflow; no hint without evidence reaches the fixer and `undetermined` never does
# (A28); a failure that reproduces on the base version is not a finding; a harness failure lands in
# its own list; an answer with no readable control run settles nothing; a group that ran and came
# back with no answer goes to the user; the judge's accepted rows are the fixer's whole mandate;
# the ceiling of A30 cuts each fan-out stage; the long form is taken for `full` and for any group of
# high severity, the short form otherwise (idea decision 5); the status sends the open rows to the
# user and states the one round; an undetermined answer is closed by no control run; the whole
# return of a run — the open rows, the harness failures, the on-base rows naming the base version,
# the evidence files, the status — is built by chainResult() and survives a late block. Every
# decision is executed over lib/block.js, never grepped out of the workflow file, and each rule is
# re-run over a mutant that must turn that same named rule red.
# Temp dirs only, no network, no session, under 20 s.
set -u

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
P=$REPO/plugins/session
LIB=$P/lib
WF=$P/workflows/chain.js
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

# ---- a1: the static aspect catalog ----
A=$LIB/aspects
shopt -s nullglob
AFILES=("$A"/*.md)
if [ "${#AFILES[@]}" -eq 0 ]; then
  fail "a1 at least one aspect paragraph in lib/aspects/"
else
  pass
  na=${#AFILES[@]}
  check "a1 at least 6 aspects in the catalog (got $na)" test "$na" -ge 6
  for f in "${AFILES[@]}"; do
    b=$(basename "$f" .md)
    check "a1 $b is not empty" test -s "$f"
    w=$(wc -w < "$f" | tr -d ' ')
    check "a1 $b is a short paragraph, under 200 words (got $w)" test "$w" -lt 200
    check "a1 $b says what is out of scope" grep -qi 'out of scope' "$f"
    # an aspect text is appended to the critic prompt: it takes no argument of its own
    check "a1 $b carries no {placeholder}" bash -c '! grep -Eq "\{[A-Za-z][A-Za-z0-9_-]*\}" "$1"' _ "$f"
    # a quality aspect names no carrier: the script picks the agent and the slot
    check "a1 $b names no workflow and no tool-set agent" bash -c '! grep -Eq "session:[a-z-]+|tools-(read|edit|web)[a-z-]*" "$1"' _ "$f"
  done
  # the names the catalog must carry, the aspects idea 3.6 lists first
  for n in simplicity reliability security extensibility performance; do
    check "a1 the catalog carries the aspect $n" test -f "$A/$n.md"
  done
fi

# ---- a2: the critic role text carries the budget of idea 3.6 ----
C=$LIB/roles/critic.md
if [ -f "$C" ]; then
  check "a2 critic.md states the tool-call budget" grep -q 'Tool-call budget: at most' "$C"
  check "a2 critic.md caps the hints at 5" grep -q 'At most 5 hints' "$C"
  check "a2 critic.md gives hints, never verdicts" grep -qi 'hints, never verdicts' "$C"
else
  fail "a2 lib/roles/critic.md exists"
fi

# ---- a3: the chain decisions, executed over lib/block.js ----
cat > "$T/chain.js" <<'JS'
const b = require(process.argv[2])
const out = []
const ck = (cond, what) => out.push(`${cond ? 'ok' : 'bad'} ${what}`)
const eq = (got, want, what) => ck(JSON.stringify(got) === JSON.stringify(want),
  `${what}: got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`)

// --- the hint format and the cap of A27 ---
const critique = aspect => [
  'Some prose the critic wrote first.',
  `HINT | ${aspect} | src/add.js:10-20 | high | wrong operator | run the test`,
  `HINT | ${aspect} | src/add.js:60-70 | low | dead branch | read the file`,
  `HINT | ${aspect} | src/other.js:1-5 | medium | unchecked input | run it`,
  `HINT | ${aspect} | doc.md#Rules | medium | rule contradicts itself | read the section`,
  `HINT | ${aspect} | src/add.js:200-210 | low | needless helper | read it`,
  `HINT | ${aspect} | src/add.js:300 | high | over the cap | read it`,
  'DONE',
].join('\n')
const raw = b.parseHints(critique('simplicity'), 'simplicity')
eq(raw.length, 6, 'parseHints reads every hint line and no prose line')
eq(raw[0].severity, 'high', 'parseHints reads the severity')
eq(raw[0].aspect, 'simplicity', 'parseHints reads the aspect tag')
ck(b.HINT_CAP === 5, `A27 the hint cap is 5 (got ${b.HINT_CAP})`)
eq(b.capHints(raw).length, 5, 'A27 one critic gives at most 5 hints')
eq(b.capHints(raw)[4].place, 'src/add.js:200-210', 'A27 the cap keeps the first hints, the strongest')
eq(b.parseHints('no hint line here\nDONE', 'security'), [], 'a return with no hint line gives no hint')
eq(b.parseHints('HINT | security | | high | no place | none', 'security'), [],
   'a hint with no place is no hint')
const bare = b.parseHints('HINT |  | src/add.js:1-2 | low | x | y', 'simplicity+security')
eq(bare.map(h => h.aspect), ['simplicity+security'],
   'a hint line with an empty aspect field takes the aspect of the critic that wrote it')
eq(b.groupHints(bare)[0].aspects, ['simplicity+security'],
   'that group carries an aspect tag, never an empty one')

// --- grouping by place: two critics, one place, one evidence run ---
const h1 = b.capHints(b.parseHints([
  'HINT | simplicity | src/add.js:10-20 | medium | needless branch | read it',
  'HINT | simplicity | src/far.js:1-5 | low | dead code | read it',
].join('\n'), 'simplicity'))
const h2 = b.capHints(b.parseHints([
  'HINT | security | src/add.js:15-25 | high | unchecked input | run it',
].join('\n'), 'security'))
const g = b.groupHints([...h1, ...h2])
eq(g.length, 2, 'two critics on one place give one group, the far hint its own')
const same = g.filter(x => x.hints.length === 2)[0]
ck(!!same, 'the overlapping hints form one group')
if (same) {
  eq(same.aspects, ['security', 'simplicity'], 'the group keeps both aspect tags')
  eq(same.severity, 'high', 'the group takes the highest severity of its hints')
  eq(same.from, 10, 'the group covers the union of the places: from')
  eq(same.to, 25, 'the group covers the union of the places: to')
}
const apart = b.groupHints(b.parseHints([
  'HINT | cost | src/a.js:10-20 | low | one | read it',
  'HINT | cost | src/a.js:40-50 | low | two | read it',
].join('\n'), 'cost'))
eq(apart.length, 2, 'same-meaning hints on different places stay separate')
const files = b.groupHints(b.parseHints([
  'HINT | cost | src/a.js:10-20 | low | one | read it',
  'HINT | cost | src/b.js:10-20 | low | two | read it',
].join('\n'), 'cost'))
eq(files.length, 2, 'the same line range in two files is two groups')
const sect = b.groupHints(b.parseHints([
  'HINT | simplicity | doc.md#Rules | low | one | read it',
  'HINT | security | doc.md#Rules | high | two | read it',
  'HINT | cost | doc.md#Other | low | three | read it',
].join('\n'), 'x'))
eq(sect.length, 2, 'a document section is a place: the same section groups, another does not')
eq(b.maxSeverity(g), 'high', 'maxSeverity over the groups')
eq(b.maxSeverity([]), null, 'no group, no severity')

// --- the form of the chain: idea decision 5 ---
eq(b.chainForm('full', 'low'), 'long', 'full takes the long form at any severity')
eq(b.chainForm('full', null), 'long', 'full takes the long form with no hint at all')
eq(b.chainForm('std', 'high'), 'long', 'a high-severity group takes the long form at std')
eq(b.chainForm('lite', 'high'), 'long', 'a high-severity group takes the long form at lite too')
eq(b.chainForm('std', 'medium'), 'short', 'std with no high severity is the short form')
eq(b.chainForm('lite', 'low'), 'short', 'lite with no high severity is the short form')
try { b.chainForm('deep', 'low'); ck(false, 'an unknown depth throws') } catch (e) {
  ck(/deep/.test(String(e.message)), `an unknown depth names itself (${e.message})`)
}

// --- the aspect catalog: an unknown name stops the workflow ---
const cat = { simplicity: 'x', security: 'y', cost: 'z' }
eq(b.pickAspects(['security'], cat).unknown, [], 'a known aspect passes')
eq(b.pickAspects(['security', 'taste'], cat).unknown, ['taste'], 'an unknown aspect is named back')
eq(b.pickAspects([], cat).unknown, [], 'an empty list names no unknown')

// --- critic split: one merged critic at lite, one per aspect above it (A3, 3.6) ---
eq(b.criticSplit('lite', ['simplicity', 'security']), [['simplicity', 'security']],
   'lite runs one merged critic over the whole set')
eq(b.criticSplit('full', ['simplicity', 'security']), [['simplicity'], ['security']],
   'full splits into one critic per aspect')
eq(b.criticSplit('std', ['security']), [['security']], 'one aspect is one critic, merged or not')

// --- evidence: the two kinds of failure, the control run, and what reaches the fixer ---
const ev = [
  'EVIDENCE | g1 | confirmed | base:no | src/add.js:12 returns a - b',
  'EVIDENCE | g2 | refuted | base:no | the input is checked at src/other.js:3',
  'EVIDENCE | g3 | undetermined | base:no | needs a run nobody can start here',
  'EVIDENCE | g4 | confirmed | base:yes | the same failure shows on the base version',
  'EVIDENCE | g5 | harness | base:no | the sandbox denied the command',
  'prose the researcher added',
].join('\n')
const ans = b.parseEvidence(ev)
eq(ans.length, 5, 'parseEvidence reads every evidence line and no prose line')
const sp = b.splitFailures(ans)
eq(sp.harness.map(a => a.group), ['g5'], 'a harness failure lands in its own list')
eq(sp.onBase.map(a => a.group), ['g4'], 'a failure that reproduces on the base is not a finding')
eq(sp.findings.map(a => a.group), ['g1', 'g2', 'g3'], 'the findings are what is left')
const groups = ['g1', 'g2', 'g3', 'g4', 'g5', 'g6'].map(id => ({ id, place: `src/${id}.js:1-2` }))
eq(b.undeterminedOf(groups, ans).map(r => r.id), ['g3'], 'the undetermined list is its own list')
const toFix = b.fixerInput(groups, ans).map(x => x.id)
eq(toFix, ['g1'], 'only a confirmed hint reaches the fixer')
ck(!toFix.includes('g3'), 'A28 an undetermined hint never reaches the fixer')
ck(!toFix.includes('g4'), 'a base-version failure never reaches the fixer')
ck(!toFix.includes('g5'), 'a harness failure never reaches the fixer')
ck(!toFix.includes('g6'), 'a hint with no evidence at all never reaches the fixer')
eq(b.fixerInput(groups, []), [], 'no evidence, no fix')

// --- the control run closes a settled answer only: an unsettled one stays open ---
const undBase = b.parseEvidence('EVIDENCE | g9 | undetermined | base:yes | the same run fails on both')
const spBase = b.splitFailures(undBase)
eq(spBase.onBase.map(a => a.group), [],
   'an undetermined answer on the base version is closed by nobody')
eq(b.undeterminedOf([{ id: 'g9', place: 'src/x.js:1' }], undBase).map(r => r.id), ['g9'],
   'an undetermined answer on the base version stays open and goes to the user')
eq(b.fixerInput([{ id: 'g9', place: 'src/x.js:1' }], undBase), [],
   'it still reaches no fixer')

// --- the control-run field: an unreadable one settles nothing ---
const noBase = b.parseEvidence('EVIDENCE | g7 | confirmed |  | src/x.js:1 returns a - b')
eq(noBase.map(a => a.verdict), ['undetermined'],
   'an answer with no readable control run is unsettled, never a finding of this change')
eq(b.parseEvidence('EVIDENCE | g8 | harness |  | the sandbox denied it')[0].kind, 'harness',
   'a harness failure needs no control run')
eq(b.fixerInput([{ id: 'g7', place: 'src/x.js:1' }], noBase), [],
   'an answer with no readable control run never reaches the fixer')

// --- a group that ran and came back with no answer goes to the user, it does not vanish ---
eq(b.unansweredOf(groups, ans).map(g => g.id), ['g6'],
   'A28 a group with no readable answer line is its own list')
eq(b.unansweredOf(groups, []).map(g => g.id), ['g1', 'g2', 'g3', 'g4', 'g5', 'g6'],
   'no answer at all: every group that ran is unanswered')
eq(b.unansweredOf([], ans), [], 'no group, nothing unanswered')

// --- the long form: the judge decides what reaches the fixer, and cannot widen it ---
const rows = b.parseAccepted([
  'The judge wrote prose first.',
  'ACCEPTED | g1 | swap the operator back to a + b',
  'ACCEPTED | g2 | widen the check',
  'DONE',
].join('\n'))
eq(rows.map(r => r.group), ['g1', 'g2'], 'parseAccepted reads every accepted row and no prose line')
eq(rows[0].change, 'swap the operator back to a + b', 'an accepted row carries its change')
eq(b.parseAccepted('ACCEPTED |  | no group id').length, 0, 'an accepted row with no group is no row')
eq(b.judgedInput(groups, ans, rows).map(x => x.id), ['g1'],
   'the judge cannot widen the mandate past what a fact confirmed')
eq(b.judgedInput(groups, ans, []), [], 'the judge accepted nothing: no fix stage')
eq(b.judgedInput(groups, ans, b.parseAccepted('ACCEPTED | g3 | change it anyway')), [],
   'a group the judge accepted but no fact confirmed stays out')
eq(b.judgedInput(groups, ans, b.parseAccepted('ACCEPTED | g2 | change it anyway')), [],
   'a group the facts refuted stays out however the judge voted')

// --- A30: the ceiling counts the agents of one stage, and what does not fit never starts ---
eq(b.chainSeats('lite', 3), { room: 2, seats: 2, gap: 1 },
   'lite seats two agents in a stage and leaves the third as the gap')
eq(b.chainSeats('std', 5), { room: 5, seats: 5, gap: 0 },
   'std seats five and the ceiling is then reached')
eq(b.chainSeats('full', 3), { room: 10, seats: 3, gap: 0 },
   'under the ceiling nothing is cut')
eq(b.chainSeats('lite', 0).seats, 0, 'no unit asked for, no seat taken')
try { b.chainSeats('lite', 'many'); ck(false, 'a seat count that is no number throws') } catch (e) {
  ck(/many/.test(String(e.message)), `a bad seat count names itself (${e.message})`)
}
try { b.chainSeats('deep', 1); ck(false, 'chainSeats over an unknown depth throws') } catch (e) {
  ck(/deep/.test(String(e.message)), `chainSeats names the unknown depth (${e.message})`)
}

// --- the aspect gate: an unknown name stops the workflow ---
eq(b.aspectsOrStop(['security'], cat).ok, true, 'a known aspect passes the gate')
const stop = b.aspectsOrStop(['security', 'taste'], cat)
eq(stop.ok, false, 'an unknown aspect stops the workflow')
ck(/^BLOCKED: unknown aspect taste$/.test(String(stop.why)), `the stop names the bad name (${stop.why})`)
eq(stop.known, ['simplicity', 'security', 'cost'], 'the stop hands the catalog back to the launcher')
eq(b.aspectsOrStop([], cat).ok, false, 'an empty aspect list is no review')

// --- the status sentence: A28 and the one round (the contract the main session reads) ---
const st = b.chainStatus({ form: 'long', groups: 3, confirmed: 1, undetermined: 1, unanswered: 1,
                           out: '/tmp/r/out.md', gap: 2, room: 5 })
ck(/2 open/.test(st), `the status counts the undetermined and the unanswered together (${st})`)
ck(st.includes('/tmp/r/out.md'), 'the status names the result file the open rows stand in')
ck(/put them to the user/.test(st), 'A28 the status sends the open rows to the user')
ck(/One round only: a second critique needs the user's word\./.test(st),
   'the status states that the chain ran one round')
ck(/ceiling of 5 agents per stage/.test(st), 'the status states the ceiling that ended a stage')
const clean = b.chainStatus({ form: 'short', groups: 2, confirmed: 0, undetermined: 0, unanswered: 0, out: '/tmp/r/out.md' })
ck(/Nothing is open for the user\./.test(clean), `nothing open, nothing to decide (${clean})`)
ck(!/ceiling/.test(clean), 'no gap, no ceiling sentence')
ck(/One round only/.test(clean), 'the one round stands in every status')

// --- the return of one run: built in one place, the same rows after a late block (A28) ---
const state = { out: '/tmp/r/out.md', form: 'long', aspects: ['security'], critics: 2,
                base: 'v1.2', groups, ran: groups, answers: ans, confirmed: 1,
                evidence: ['/tmp/r/e1.md'], gap: ['g7: no seat'], gapCount: 1, room: 5,
                blockedStages: ['critic cost: BLOCKED: denied'] }
const res = b.chainResult(state)
eq(res.undetermined.map(s => s.split(':')[0]), ['g3'], 'the result carries the undetermined rows')
eq(res.unanswered.map(s => s.split(' ')[0]), ['g6'], 'the result carries the groups nobody answered')
eq(res.harness.map(s => s.split(':')[0]), ['g5'], 'the result keeps the harness failures apart')
ck(res.onBase.length === 1 && /reproduces on v1\.2,/.test(res.onBase[0]),
   `the result names the base version of an on-base row (${res.onBase[0]})`)
eq(res.evidence, ['/tmp/r/e1.md'], 'the result names the evidence files that were written')
eq(res.groups, 6, 'the result counts every group of the run')
ck(/2 open/.test(res.status), `the result carries the status sentence (${res.status})`)
const blk = b.chainResult({ ...state, stage: 'triage', blocked: 'the judge stopped' })
ck(/^BLOCKED: the judge stopped$/.test(String(blk.blocked)), `a blocked stage names its reason (${blk.blocked})`)
eq(blk.stage, 'triage', 'a blocked stage names the stage that blocked')
eq(blk.undetermined, res.undetermined, 'a blocked stage still returns the open rows')
eq(blk.unanswered, res.unanswered, 'a blocked stage still returns the groups nobody answered')
eq(blk.harness, res.harness, 'a blocked stage still returns the harness failures')
eq(blk.evidence, res.evidence, 'a blocked stage still returns the evidence files')
eq(blk.status, res.status, 'a blocked stage still returns the status sentence')
ck(!('blocked' in res), 'a run that reached the end carries no blocked line')

// --- two answer lines for one group: the stronger evidence wins, and one list holds the group ---
const dup = b.parseEvidence([
  'EVIDENCE | g1 | undetermined | base:no | nobody could run it',
  'EVIDENCE | g1 | confirmed | base:no | src/add.js:12 returns a - b',
  'EVIDENCE | g2 | harness | base:no | the sandbox denied the command',
  'EVIDENCE | g2 | refuted | base:no | the check passes at src/other.js:3',
  'EVIDENCE | g3 | confirmed | base:no | the run fails',
  'EVIDENCE | g3 | refuted | base:no | the run passes',
].join('\n'))
eq(b.dedupeAnswers(dup).length, 3, 'two answer lines for one group give one answer')
eq(b.dedupeAnswers(dup).map(a => a.verdict), ['confirmed', 'refuted', 'undetermined'],
   'the stronger evidence wins, and two settled answers that contradict each other settle nothing')
eq(b.fixerInput(groups, dup).map(x => x.id), ['g1'], 'a group answered twice reaches the fixer once')
eq(b.undeterminedOf(groups, dup).map(r => r.id), ['g3'],
   'a group confirmed once and undetermined once no longer stands in both lists')

// --- the confirmed count is the facts; what reached the fixer is its own number ---
eq(b.confirmedOf(groups, ans).map(r => r.id), ['g1'], 'confirmedOf counts the facts of the run')
eq(b.confirmedOf(groups, []).length, 0, 'no answer, no confirmation')
const blkT = b.chainResult({ ...state, stage: 'triage', blocked: 'the judge stopped', fixing: 0 })
eq(blkT.confirmed, 1, 'a blocked triage still reports the fact the evidence confirmed')
eq(blkT.fixing, 0, 'a blocked triage reports nothing reaching the fixer')
ck(/1 confirmed, 0 to the fixer/.test(blkT.status),
   `the status of a blocked triage separates the facts from the fix stage (${blkT.status})`)
eq(b.chainResult({ ...state, confirmed: 99, fixing: 1 }).confirmed, 1,
   'the confirmed count comes from the answers, not from the caller')
ck(/1 confirmed, 1 to the fixer/.test(b.chainResult({ ...state, fixing: 1 }).status),
   'the status of a finished run names both numbers')

// --- the plan of the critic stage: the gate, the split and the ceiling in one decision ---
const plan = b.chainPlan('full', ['simplicity', 'security'], cat)
eq(plan.ok, true, 'a known aspect list plans a run')
eq(plan.sets, [['simplicity'], ['security']], 'the plan splits full into one critic per aspect')
eq(plan.split, true, 'two critic sets are a split critic, which sits one slot down')
eq(b.chainPlan('lite', ['simplicity', 'security'], cat).split, false,
   'the merged critic of lite is no split')
const stopped = b.chainPlan('full', ['simplicity', 'taste'], cat)
eq(stopped.ok, false, 'an unknown aspect name stops the run before any critic starts')
eq(stopped.sets, [], 'a stopped plan seats no critic')
ck(/^BLOCKED: unknown aspect taste$/.test(String(stopped.why)),
   `the stopped plan names the bad name (${stopped.why})`)
eq(stopped.known, ['simplicity', 'security', 'cost'], 'the stopped plan hands the catalog back')
eq(b.chainPlan('full', [], cat).ok, false, 'an empty aspect list plans no review')
const many = ['a1', 'a2', 'a3', 'a4', 'a5', 'a6']
const capped = b.chainPlan('std', many, many)
eq(capped.sets.length, 5, 'the plan seats five critics, the ceiling of the stage')
eq(capped.gap, [['a6']], 'the critic that does not fit is the gap, never a second round')
eq(capped.room, 5, 'the plan names the ceiling it applied')

// --- the evidence stage: the strongest groups first, under the same ceiling ---
const evg = [{ id: 'g1', severity: 'low' }, { id: 'g2', severity: 'high' }, { id: 'g3', severity: 'medium' }]
const longRuns = b.chainEvidenceRuns('lite', 'long', evg)
eq(longRuns.ran.map(x => x.id), ['g2', 'g3'],
   'the long form starts the strongest groups first, under the ceiling')
eq(longRuns.gap.map(x => x.id), ['g1'], 'the group that does not fit becomes the gap')
const shortRuns = b.chainEvidenceRuns('lite', 'short', evg)
eq(shortRuns.gap, [], 'the short form is one agent: it cuts no group')
eq(shortRuns.ran.map(x => x.id), ['g2', 'g3', 'g1'], 'the short form takes every group')
eq(b.chainEvidenceRuns('full', 'long', []).ran, [], 'no group, no evidence run')

// --- the answers are per hint: one group, one evidence run, one verdict per hint of it ---
const mixed = b.groupHints(b.parseHints([
  'HINT | reliability | src/x.js:1-7 | high | the cut leaves a trailing dash | run the check',
  'HINT | simplicity | src/x.js:6 | high | the wrapper is needless, drop it | grep its callers',
  'HINT | simplicity | src/x.js:3 | medium | the default is written twice | compare both',
].join('\n'), 'x'))
eq(mixed.length, 1, 'hints on one place are one group, one evidence run')
eq(mixed[0].hints.map(h => h.id), ['g1.h1', 'g1.h2', 'g1.h3'],
   'every hint of a group carries its own id')
const mixedAns = b.parseEvidence([
  'EVIDENCE | g1.h1 | confirmed | base:no | the check fails at src/x.js:4',
  'EVIDENCE | g1.h2 | refuted | base:yes | the wrapper already stands in the base version',
  'EVIDENCE | g1.h3 | undetermined | base:no | no rule says which spelling is meant',
].join('\n'))
eq(b.fixerInput(mixed, mixedAns).map(g => g.hints.map(h => h.id)), [['g1.h1']],
   'only the confirmed hint of the group reaches the fixer, the refuted and the unsettled stay out')
eq(b.chainRows(mixed, mixedAns).onBase.map(r => r.id), ['g1.h2'],
   'a hint whose shape already stands on the base version is no finding of this change')
eq(b.chainRows(mixed, mixedAns).undetermined.map(r => r.id), ['g1.h3'],
   'the unsettled hint of a confirmed group is its own row')
eq(b.judgedInput(mixed, mixedAns, b.parseAccepted('ACCEPTED | g1.h2 | drop the wrapper')), [],
   'the judge cannot accept a hint no fact confirmed, however its group was answered')
eq(b.judgedInput(mixed, mixedAns, b.parseAccepted('ACCEPTED | g1.h1 | trim the dash'))
   .map(g => g.hints.map(h => h.id)), [['g1.h1']],
   'the judge accepts a confirmed hint by that hint id')
const wholeGroup = b.parseEvidence('EVIDENCE | g1 | confirmed | base:no | one verdict for the whole group')
eq(b.fixerInput(mixed, wholeGroup), [],
   'one verdict over a group of several hints settles no hint of it and reaches no fixer')
eq(b.chainRows(mixed, wholeGroup).unanswered.map(r => r.id), ['g1.h1', 'g1.h2', 'g1.h3'],
   'those hints are unanswered and go to the user')
const single = b.groupHints(b.parseHints('HINT | cost | src/one.js:1-2 | low | one hint | read it', 'cost'))
eq(b.fixerInput(single, b.parseEvidence('EVIDENCE | g1 | confirmed | base:no | src/one.js:2')).map(g => g.id),
   ['g1'], 'a group of one hint is that hint: an answer naming the group settles it')
eq(b.fixerInput(mixed, b.parseEvidence('EVIDENCE | g1.h2 | confirmed |  | no control run')), [],
   'a hint whose answer has no readable control run reaches no fixer either')

// --- the return and the review file come from one table ---
// one hint confirmed, one unsettled, one nobody answered: both kinds of open row in one run
const partial = b.parseEvidence([
  'EVIDENCE | g1.h1 | confirmed | base:no | the check fails at src/x.js:4',
  'EVIDENCE | g1.h2 | undetermined | base:no | nothing here settles it',
].join('\n'))
const tbl = b.chainRows(mixed, partial)
eq(tbl.open.map(r => r.id), ['g1.h2', 'g1.h3'],
   'the open rows are the unsettled hints and the hints nobody answered')
const one = b.chainResult({ out: '/tmp/r/out.md', form: 'long', groups: mixed, ran: mixed,
                            answers: partial, base: 'v1.2' })
eq(one.undetermined.map(s => s.split(':')[0]).concat(one.unanswered.map(s => s.split(' ')[0])),
   tbl.open.map(r => r.id), 'the return carries exactly the open rows of the table')
const openText = b.openRowsText(tbl)
eq(openText.split('\n').length, tbl.open.length,
   'the unsettled section holds one row per open row of the table')
ck(tbl.open.every(r => openText.includes(r.id)),
   'every open row of the return stands in the unsettled section of the file')
eq(b.openRowsText(b.chainRows(mixed, b.parseEvidence(
   ['EVIDENCE | g1.h1 | confirmed | base:no | a fact',
    'EVIDENCE | g1.h2 | refuted | base:no | a fact',
    'EVIDENCE | g1.h3 | refuted | base:no | a fact'].join('\n')))), '(none)',
   'nothing open, no unsettled row for the file')
console.log(out.join('\n'))
JS

run_suite() { # run_suite <label> <block file> <expect ok|red> [the rule that must go red]
  local label=$1 file=$2 expect=$3 rule=${4:-}
  node "$T/chain.js" "$file" > "$T/suite.out" 2>&1
  if [ ! -s "$T/suite.out" ]; then
    fail "$label produced no line (node failed)"
    sed 's/^/  /' "$T/suite.out" 2>/dev/null
    return 1
  fi
  if [ "$expect" = red ]; then
    # the named rule must be the one that goes red: a mutant caught by an unrelated check proves
    # nothing about the rule it breaks
    check "$label" grep -qE "^bad .*$rule" "$T/suite.out"
    return 0
  fi
  while IFS= read -r line; do
    case $line in
      "ok "*) pass ;;
      "bad "*) fail "a3 ${line#bad }" ;;
      *) fail "a3 unexpected output: $line" ;;
    esac
  done < "$T/suite.out"
}

if [ -f "$LIB/block.js" ]; then
  run_suite "a3 the chain suite over lib/block.js" "$LIB/block.js" ok
else
  fail "a3 lib/block.js exists"
fi

# ---- a4: the mutants. Each breaks one rule of the chain; the suite must go red on that rule ----
# Fields: <what the mutant breaks> | <the assertion text that must go red> | <the perl expression>.
# The expression stands last because it carries pipe characters of its own.
i=0
while IFS='|' read -r what pat expr; do
  [ -n "$what" ] || continue
  i=$((i + 1))
  perl -pe "$expr" "$LIB/block.js" > "$T/mutant$i.js" 2>/dev/null
  check "a4 mutant $i is really a mutation ($what)" bash -c '! cmp -s "$1" "$2"' _ "$LIB/block.js" "$T/mutant$i.js"
  run_suite "a4 the suite catches the mutant: $what" "$T/mutant$i.js" red "$pat"
done <<'MUT'
two critics on one place cost two evidence runs|two critics on one place give one group|s/^function hintsOverlap\(a, b\) \{/function hintsOverlap(a, b) { return false;/
the hint cap lets every hint through|one critic gives at most 5 hints|s/return hints\.slice\(0, n\)/return hints.slice(0)/
an undetermined hint reaches the fixer|an undetermined hint never reaches the fixer|s/findings\.filter\(r => r\.verdict === 'confirmed'\)/findings.filter(r => r.verdict !== 'refuted')/
a base-version failure stays a finding|reproduces on the base is not a finding|s/const onBase = rest\.filter\(a => closed\(a\)\)/const onBase = []/
an undetermined answer is closed by the control run|on the base version is closed by nobody|s/a\.onBase && a\.verdict !== 'undetermined'/a.onBase/
the short form is taken everywhere|full takes the long form at any severity|s/depth === 'full' \|\| sev === 'high'/false/
a harness failure becomes a finding|a harness failure lands in its own list|s/a\.kind === 'harness'/false/
an unreadable control run passes as base:no|no readable control run is unsettled|s/if \(verdict !== 'harness' && /if (false && /
a group with no answer vanishes|a group with no readable answer line is its own list|s/answered: !!a,/answered: true,/
the judge's accepted rows stop filtering the fixer's mandate|the judge accepted nothing|s/ids\.includes\(g\.id\)/true/
the ceiling never cuts a stage|lite seats two agents in a stage|s/const seats = Math\.min\(n, room\)/const seats = n/
an unknown aspect name runs anyway|an unknown aspect stops the workflow|s/if \(p\.unknown\.length\) \{/if (false) {/
a hint with an empty aspect field loses its tag|takes the aspect of the critic that wrote it|s/f\[0\] \|\| aspect \|\| ''/f[0] || ''/
the status keeps the open rows to itself|the status sends the open rows to the user|s/put them to the user/keep them here/
the status promises another round|the status states that the chain ran one round|s/One round only/Another round/
the result drops the undetermined rows|the result carries the undetermined rows|s/undetermined: und\.map/undetermined: [].map/
the result mixes the harness failures in|the result keeps the harness failures apart|s/harness: T\.harness\.map/harness: [].map/
the result does not name the base version|names the base version of an on-base row|s/o\.base \|\| 'the base version'/'the base version'/
a blocked stage drops every row it knows|a blocked stage still returns the open rows|s/if \(o\.blocked\) res\.blocked = blockedLine\(o\.blocked\)/if (o.blocked) return { blocked: blockedLine(o.blocked) }/
two answers for one group stay two|two answer lines for one group give one answer|s/const cur = out\.filter\(x => x\.id === a\.id\)\[0\]/const cur = null/
one verdict settles every hint of its group|one verdict over a group of several hints settles no hint|s/hints\.length === 1 \? all\.filter\(x => x\.id === g\.id\)\[0\] : null/all.filter(x => x.id === g.id)[0]/
the fixer gets every hint of a group one fact confirmed|only the confirmed hint of the group reaches the fixer|s/const hints = \(g\.hints \|\| \[\]\)\.filter\(h => ok\.includes\(h\.id\)\)/const hints = (g.hints || [])/
the hints of a group share the group id|every hint of a group carries its own id|s/id: `\$\{id\}\.h\$\{j \+ 1\}`/id/
the unsettled section of the file drops the open rows|the unsettled section holds one row per open row|s/const open = \(rows && rows\.open\) \|\| \[\]/const open = []/
the return invents its open rows instead of the table|the return carries exactly the open rows of the table|s/const open = T\.unanswered/const open = []/
two contradicting answers settle the group anyway|two settled answers that contradict each other settle nothing|s/cur\.verdict !== a\.verdict/false/
an unknown aspect name plans a run anyway|an unknown aspect name stops the run before any critic starts|s/if \(!gate\.ok\) return \{ ok: false/if (false) return { ok: false/
the ceiling never cuts the critic stage|the plan seats five critics, the ceiling of the stage|s/sets: all\.slice\(0, seats\.seats\)/sets: all.slice(0)/
the ceiling never cuts the evidence stage|the long form starts the strongest groups first|s/ran: ordered\.slice\(0, seats\.seats\)/ran: ordered.slice(0)/
the confirmed count is whatever the caller claims|the confirmed count comes from the answers|s/confirmed: conf\.length,/confirmed: Number(o.confirmed),/
MUT

# ---- a5: the wiring of workflows/chain.js, by grep over its own code ----
if [ -f "$WF" ]; then
  code=$(python3 - "$WF" <<'PY'
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
)
  check "a5 chain.js carries the shared-block marker" grep -q '^// ---- shared block' "$WF"
  check "a5 chain.js carries the roles marker" grep -q '^// ---- roles' "$WF"
  check "a5 chain.js carries the aspects marker" grep -q '^// ---- aspects' "$WF"
  check "a5 chain.js stamp is in sync with its sources" bash "$BUILD" --check "$WF"
  # every decision comes from the shared block, so a test can execute it
  for fn in chainPlan chainEvidenceRuns parseHints capHints groupHints maxSeverity chainForm parseEvidence splitFailures fixerInput parseAccepted judgedInput chainRows openRowsText chainStatus chainResult; do
    check "a5 chain.js decides through $fn() of the shared block" grep -q "$fn(" <<<"$code"
  done
  # the gate, the critic split and the two ceilings of A30 are executed in a3 over lib/block.js:
  # here only the wiring, that this script asks those functions and that the gate's `no` returns
  check "a5 chain.js stops on an unknown aspect name" grep -Fq 'if (!PLAN.ok) return fail(PLAN.why' <<<"$code"
  check "a5 chain.js plans the critic stage through chainPlan" grep -Fq 'chainPlan(DEPTH, ASPECTS, ASPECT_TEXT)' <<<"$code"
  check "a5 chain.js seats the critics by that plan" grep -Fq 'const PLANRUN = PLAN.sets' <<<"$code"
  check "a5 chain.js seats the evidence runs under the ceiling" grep -Fq 'chainEvidenceRuns(DEPTH, FORM, GROUPS)' <<<"$code"
  # the long form takes its mandate from the judge, never from the raw evidence verdicts
  check "a5 chain.js fixes by the judge's accepted rows in the long form" grep -Fq 'judgedInput(RUNGROUPS, answers, parseAccepted(judged.ret))' <<<"$code"
  check "a5 chain.js takes the critic slot split from the role map" grep -q 'roleSlot(' <<<"$code"
  check "a5 chain.js checks every output through outVerdict" grep -q 'outVerdict(' <<<"$code"
  check "a5 chain.js reads a return through the block, not by its own regex" bash -c '! grep -qE "/BLOCKED:?/|BLOCKED:.{0,3}\.test" <<<"$1"' _ "$code"
  check "a5 chain.js pins no model at the call site" bash -c '! grep -qE "^\s*(model|effort):" <<<"$1"' _ "$code"
  check "a5 chain.js names no model word" bash -c '! grep -Eqi "(^|[^-a-z])(opus|sonnet|fable|haiku)([^-a-z]|$)" <<<"$1"' _ "$code"
  check "a5 chain.js logs the launch before the first argument check" python3 -c '
import sys
code = sys.argv[1]
sys.exit(0 if 0 < code.index("log(") < code.index("return fail(") else 1)
' "$code"
  check "a5 chain.js requires an absolute output path" grep -Fq 'absolute path' <<<"$code"
  check "a5 chain.js takes a list argument that is no array to the error path" grep -q 'Array.isArray' <<<"$code"
  # the control run on the base version is called before a finding is emitted, and the version the
  # on-base rows name is the one the launcher gave (the row text itself is executed in a3)
  check "a5 chain.js hands the base version to the result builder" grep -Fq 'base: BASE' <<<"$code"
  check "a5 chain.js drops the base-version failures before it judges" python3 -c '
import sys
code = sys.argv[1]
sys.exit(0 if code.index("splitFailures(") < code.index("fixerInput(") else 1)
' "$code"
  check "a5 chain.js asks the evidence stage for the control run" grep -qi 'base version' <<<"$code"
  # one round: the critic stage is launched once, and no loop reruns a stage
  ncrit=$(grep -c "chainPlan(" <<<"$code")
  check "a5 chain.js plans the critic stage once (got $ncrit)" test "$ncrit" -eq 1
  check "a5 chain.js runs one round, no review loop" bash -c '! grep -qE "while \(|cycle\(" <<<"$1"' _ "$code"
  # A28: the rows of the return — the undetermined, the unanswered, the harness failures, the
  # on-base rows and the status sentence — are built by chainResult(), executed over lib/block.js
  # in a3. Here only the wiring: that this script returns through it and hands it the run's state,
  # a blocked triage included, and that the groups nobody answered stand in the triage prompt.
  check "a5 chain.js builds its return through chainResult" grep -Fq 'chainResult({' <<<"$code"
  check "a5 chain.js hands the groups and the answers to the result builder" grep -Fq 'groups: GROUPS, ran: RUNGROUPS, answers' <<<"$code"
  check "a5 chain.js returns through the result builder after a blocked triage" grep -Fq "return result({ stage: 'triage'" <<<"$code"
  check "a5 chain.js returns through the result builder after a blocked short evidence stage" grep -Fq "return result({ stage: 'evidence'" <<<"$code"
  # a blocked fixer is a failed run: it names its stage and its blocked line, never a bare success
  check "a5 chain.js returns through the result builder after a blocked fix stage" grep -Fq "stage: 'fix', blocked: fixed.blocked" <<<"$code"
  check "a5 chain.js puts every late block into the blocked stages" grep -Fq 'LATE.push(`fix:' <<<"$code"
  # the count of the fix stage is its own field: no return calls it the confirmed facts
  check "a5 chain.js never reports the fixer's count as the confirmed facts" bash -c '! grep -Fq "confirmed: TOFIX.length" <<<"$1"' _ "$code"
  check "a5 chain.js hands the fixer's count to the result builder" grep -Fq 'fixing: TOFIX.length' <<<"$code"
  # the rows of the return and the rows of the result file are the same rows, rendered once
  check "a5 chain.js builds the one table of the run through chainRows" grep -Fq 'chainRows(RUNGROUPS, answers)' <<<"$code"
  check "a5 chain.js takes its open rows from that table" grep -Fq 'const NOANSWER = ROWS.unanswered' <<<"$code"
  check "a5 the triage prompt carries the open rows rendered by the block" grep -Fq 'openRowsText(ROWS)' <<<"$code"
  check "a5 the triage prompt has the judge copy them, not compose its own" grep -Fq 'exactly these and no others' <<<"$code"
  check "a5 the triage prompt accepts a hint only on a confirmed row" grep -Fq 'Accept a hint only when its own row says' <<<"$code"
  # the fixer's mandate is named hint by hint, never re-read wider out of the result file
  check "a5 chain.js names the fixer's mandate hint by hint" grep -Fq 'const FIXTEXT = TOFIX.map' <<<"$code"
  check "a5 the fix prompt holds the fixer to that list" grep -Fq 'is not yours to change' <<<"$code"
  # the evidence stage answers per hint, and the control run covers a shape as well as a failure
  check "a5 the evidence shape asks for one line per hint" grep -Fq 'EVIDENCE | <hint id' <<<"$code"
  check "a5 the evidence shape refuses a group-wide verdict" grep -Fq 'one verdict written over a whole group settles no hint' <<<"$code"
  check "a5 the evidence shape demands a fact before a confirmation" grep -Fq 'plausible is not confirmed' <<<"$code"
  check "a5 the control run covers a shape, not only a failure" grep -Fq 'A hint that claims a shape' <<<"$code"
  check "a5 chain.js writes no status sentence of its own" bash -c '! grep -qE "^ *status: \`" <<<"$1"' _ "$code"
  check "a5 chain.js names no skill" bash -c '! grep -qE "session:(ask|base|process|codex)" <<<"$1"' _ "$code"
  check "a5 chain.js cites the verification page" grep -q 'lib/verification.md' <<<"$code"

  # the contract: one usage block, under the cap, naming no model
  usage=$(awk 'f==0&&/^\/\* usage:/{f=1} f{print} f&&/\*\//{exit}' "$WF")
  inner=$(printf '%s\n' "$usage" | sed -e 's#^/\* usage:##' -e 's#\*/##')
  words=$(printf '%s\n' "$inner" | wc -w | tr -d ' ')
  check "a5 the contract of chain is under $CAP words (got $words)" test "$words" -lt "$CAP"
  check "a5 the contract names the aspects argument" grep -qE '^aspects \(' <<<"$inner"
  check "a5 the contract names the depth argument" grep -qE '^depth \(' <<<"$inner"
  check "a5 the contract sends the undetermined list to the user" grep -qi 'to the user' <<<"$inner"
  check "a5 the contract names no model" bash -c '! grep -Eqi "(^|[^-a-z])(opus|sonnet|fable|haiku)([^-a-z]|$)" <<<"$1"' _ "$inner"

  # plugin.json: exactly one SessionStart entry for this workflow
  want="sh \${CLAUDE_PLUGIN_ROOT}/bin/workflow-usage.sh --hook --file \${CLAUDE_PLUGIN_ROOT}/workflows/chain.js --prefix session"
  hits=$(python3 -c '
import json, sys
groups = json.load(open(sys.argv[1]))["hooks"]["SessionStart"]
print(sum(1 for g in groups for h in g["hooks"] if h.get("command", "") == sys.argv[2]))
' "$PJ" "$want")
  check "a5 exactly one SessionStart entry for chain.js (got $hits)" test "$hits" = 1
else
  fail "a5 plugins/session/workflows/chain.js exists"
fi

# ---- a6: the behavior scenario of this part is written, whoever runs it ----
if [ -f "$SCEN" ]; then
  block=$(awk '/^chain-seeded[[:space:]]/{f=1} f&&/^[A-Za-z][A-Za-z0-9_-]*[[:space:]].*prompts:/&&!/^chain-seeded/{exit} f{print}' "$SCEN")
  check "a6 the scenario chain-seeded exists" test -n "$block"
  check "a6 chain-seeded names its prompts" grep -q 'prompts:' <<<"$block"
  for fld in base setup PASS; do
    check "a6 chain-seeded carries the field $fld" grep -qE "^[[:space:]]+$fld:" <<<"$block"
  done
  check "a6 chain-seeded seeds a real defect and a bait" grep -qi 'bait' <<<"$block"
  check "a6 chain-seeded demands the false hint be refuted" grep -qi 'refut' <<<"$block"
  check "a6 chain-seeded launches session:chain" grep -q 'session:chain' <<<"$block"
  # the prompt that reads the result waits for the workflow to finish, it never races the launch
  check "a6 chain-seeded gates its reading prompt on the workflow finish notice" grep -qE '^[[:space:]]+finish: 3 1$' <<<"$block"
  check "a6 chain-seeded judges only the lines after that notice" grep -qi 'only the lines after the workflow finish notice' <<<"$block"
else
  fail "a6 tests/measure/rebuild-scenarios-0.16.txt exists"
fi

# ---- a7: the runner can wait for a workflow finish notice, and a verdict names the code it ran on ----
RUNNER=$REPO/tests/rebuild/scenario-run.sh
VERD=$REPO/tests/rebuild/verdicts.sh
note() { # note <task-id> <summary> <status>: one task-notification line of a session transcript
  python3 -c '
import json, sys
tid, summary, status = sys.argv[1], sys.argv[2], sys.argv[3]
text = "<task-notification>\n<task-id>%s</task-id>\n<status>%s</status>\n<summary>%s</summary>\n</task-notification>" % (tid, status, summary)
print(json.dumps({"type": "user", "message": {"role": "user", "content": text}}))
' "$1" "$2" "$3"
}
{
  note wf1 'Dynamic workflow "Evidence review chain" completed' completed
  note wf1 'Dynamic workflow "Evidence review chain" completed' completed  # the same notice, queued and delivered
  note ab2 'Agent "fab-me check-review: run check.sh" finished' completed
  note bg3 'Monitor "keep-warm ping every 57m" stopped' killed
} > "$T/finished.jsonl"
{
  note ab2 'Agent "fab-me check-review: run check.sh" finished' completed
  note wf9 'Dynamic workflow "Evidence review chain" started' running
} > "$T/running.jsonl"
check "a7 the runner sees the workflow finish notice" bash -c 'bash "$1" --finished "$2" >/dev/null' _ "$RUNNER" "$T/finished.jsonl"
check "a7 one notice written twice counts once" bash -c '[ "$(bash "$1" --finished "$2")" = 1 ]' _ "$RUNNER" "$T/finished.jsonl"
check "a7 two notices are not there yet" bash -c '! bash "$1" --finished "$2" 2 >/dev/null' _ "$RUNNER" "$T/finished.jsonl"
check "a7 an agent notice is no workflow finish notice" bash -c '! bash "$1" --finished "$2" >/dev/null' _ "$RUNNER" "$T/running.jsonl"
check "a7 a workflow still running has not finished" bash -c '[ "$(bash "$1" --finished "$2" 2>/dev/null; true)" = 0 ]' _ "$RUNNER" "$T/running.jsonl"
check "a7 no transcript, nothing finished" bash -c '! bash "$1" --finished "$2/none.jsonl" >/dev/null 2>&1' _ "$RUNNER" "$T"
check "a7 the runner gates a prompt on that notice" grep -Fq 'wait_finished "$GWANT"' "$RUNNER"
check "a7 the runner marks a run on an uncommitted tree" grep -Fq 'COMMIT=$COMMIT+dirty' "$RUNNER"
# a verdict of a run on an uncommitted tree describes no commit: it never stands in for HEAD
mkdir -p "$T/verdicts/base/20260101-000000"
printf 'base fix-me PASS 20260101-000000 %s+dirty\n' "$(git -C "$REPO" rev-parse HEAD)" > "$T/verdicts/base/20260101-000000/verdicts.txt"
VERDICTS_ROOT=$T/verdicts bash "$VERD" base:fix-me > "$T/v.out" 2> "$T/v.err"
check "a7 a verdict of an uncommitted tree fails" bash -c 'grep -q "uncommitted tree" "$1"' _ "$T/v.err"
printf 'base gone PASS 20260101-000000 %s\n' 0000000000000000000000000000000000000000 > "$T/verdicts/base/20260101-000000/verdicts.txt"
VERDICTS_ROOT=$T/verdicts bash "$VERD" base:gone > "$T/v2.out" 2> "$T/v2.err"
check "a7 a verdict of a commit outside this history fails" bash -c 'grep -q "not HEAD and not an ancestor" "$1"' _ "$T/v2.err"
check "a7 verdicts.sh tells a verdict of HEAD from one of an older commit" grep -Fq 'PASS at HEAD' "$VERD"

if [ "$FAILS" -eq 0 ]; then echo "chain: PASS $N"; exit 0; fi
echo "chain: FAIL $FAILS failures, $N checks passed"
exit 1
