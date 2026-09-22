#!/bin/bash
# Unit tests of the pure functions of lib/block.js: every class row and submode key, every helper
# and both fixed seats, the handback parser on good, partial, blocked and malformed text, the batch
# rows and counts, the cell-token scanner.
set -u
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
node - "$P/lib/block.js" <<'JS'
const b = require(process.argv[2])
let n = 0, fails = 0
const ok = (label, cond) => { if (cond) n++; else { fails++; console.log('FAIL ' + label) } }
const C = b.CLASSES
for (const cls of Object.keys(C.table)) for (const key of C.submodeKeys) {
  const subs = key === 'none' ? [] : key.split(' ')
  const cell = b.cellFor(cls, subs)
  const want = C.table[cls][key].split('/')
  ok(`cellFor ${cls} ${key}`, cell.main === want[0] && cell.opus === want[1] && cell.sonnet === want[2])
}
ok('submodes reorders', b.submodes(['no-fable', 'no-sonnet']).key === 'no-sonnet no-fable')
ok('submodes refuses all three', (() => { try { b.submodes(['no-sonnet', 'no-opus', 'no-fable']); return false } catch (e) { return true } })())
ok('submodes refuses unknown', (() => { try { b.submodes(['no-haiku']); return false } catch (e) { return true } })())
ok('cellFor refuses unknown class', (() => { try { b.cellFor('c9', []); return false } catch (e) { return true } })())
for (const h of b.helperNames()) {
  const o = b.helperOpts('c3', [], h, null, h)
  ok(`helperOpts ${h} agentType`, o.agentType === C.helpers[h].agent)
  ok(`helperOpts ${h} label prefix`, o.label === `${o.cell}-${h}`)
  ok(`helperOpts ${h} model and effort named`, Object.values(C.models).includes(o.model) && Object.values(C.efforts).includes(o.effort))
  if (C.helpers[h].seat) {
    ok(`helperOpts ${h} ignores slot`, b.helperOpts('c5', [], h, 'main', h).cell === o.cell)
  } else {
    ok(`helperOpts ${h} default slot`, o.slot === C.helpers[h].slot && o.cell === b.cellFor('c3', [])[o.slot])
    ok(`helperOpts ${h} slot override`, b.helperOpts('c3', [], h, 'main', h).cell === b.cellFor('c3', []).main)
  }
}
ok('helperOpts refuses unknown helper', (() => { try { b.helperOpts('c3', [], 'oracle', null, 'x'); return false } catch (e) { return true } })())
ok('helperOpts refuses unknown slot', (() => { try { b.helperOpts('c3', [], 'finder', 'cheap', 'x'); return false } catch (e) { return true } })())
ok('guide seat none', b.seatCell('guide', []) === C.fixedCells.guide.none)
ok('guide seat no-sonnet', b.seatCell('guide', ['no-sonnet']) === C.fixedCells.guide['no-sonnet'])
ok('guide seat no-sonnet no-opus (longest wins)', b.seatCell('guide', ['no-opus', 'no-sonnet']) === C.fixedCells.guide['no-sonnet no-opus'])
ok('guide seat no-sonnet no-fable falls to no-sonnet', b.seatCell('guide', ['no-sonnet', 'no-fable']) === C.fixedCells.guide['no-sonnet'])
ok('guide seat no-opus alone falls to none', b.seatCell('guide', ['no-opus']) === C.fixedCells.guide.none)
ok('codex seat fixed under every submode', b.seatCell('codex', ['no-sonnet', 'no-opus']) === C.fixedCells.codex.none)
const h1 = b.handback('noise\nstatus: completed\nreport: /x/result.md\nsummary: 3 hits')
ok('handback good', h1.status === 'completed' && h1.report === '/x/result.md' && h1.summary === '3 hits')
ok('handback partial', b.handback('status: partial\nreport: /r\nsummary: step 4 failed').status === 'partial')
ok('handback blocked', b.handback('status: blocked\nreport: /r\nsummary: Write denied').status === 'blocked')
ok('handback last occurrence wins', b.handback('status: partial\nstatus: completed\nreport: /r\nsummary: s').status === 'completed')
const bad = b.handback('all done, looks great')
ok('handback malformed is failed', bad.status === 'failed' && /malformed/.test(bad.summary) && bad.report === null)
ok('handback unknown status is failed', /unknown status done/.test(b.handback('status: done\nreport: /r\nsummary: s').summary))
ok('handback null', b.handback(null).status === 'failed')
ok('isBlocked null', b.isBlocked(null) === true)
ok('isBlocked BLOCKED text', b.isBlocked('BLOCKED: Bash') === true)
ok('isBlocked completed', b.isBlocked('status: completed\nreport: /r\nsummary: s') === false)
const rows = b.batchRows(['a', 'b', 'c'], ['status: completed\nreport: /a\nsummary: ok', null, 'garbage'])
ok('batchRows keeps every item in order', rows.map(r => r.item).join() === 'a,b,c')
ok('batchRows null is failed', rows[1].status === 'failed' && rows[1].summary === 'no return')
ok('batchRows garbage is failed', rows[2].status === 'failed')
const c = b.batchCounts(rows)
ok('batchCounts', c.total === 3 && c.completed === 1 && c.failed === 2 && c.partial === 0 && c.blocked === 0)
ok('cellTokens model name', b.cellTokens('runs on fable').length === 1)
ok('cellTokens short code', b.cellTokens('label ops-me-x').length === 1)
ok('cellTokens frontmatter pin', b.cellTokens('model: sonnet').length >= 1)
ok('cellTokens slot and submode are clean', b.cellTokens('the opus slot, the sonnet-slot, no-sonnet').length === 0)
ok('cellTokens plain prose clean', b.cellTokens('a fork does the work; a helper brings a result').length === 0)
console.log(fails ? `block: FAIL ${fails} failures, ${n} checks passed` : `block: PASS ${n}`)
process.exit(fails ? 1 : 0)
JS
