#!/bin/bash
# The result protocol end to end without a model: launchTail builds the prompt tail (the protocol
# spelled out for a non-plugin agent such as guide, the skill line last), handbackAt fails a return
# whose report is not <out>/result.md, isBlocked reads only a line start, batchRows checks each item
# directory; helper.js and batch.js run over a mock agent(); every agent body refuses a result
# directory that already holds result.md, writes result.md last, and polls within 120000.
set -u
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
node - "$P/lib/block.js" "$P/workflows/helper.js" "$P/workflows/batch.js" <<'JS'
const fs = require('fs')
const b = require(process.argv[2])
let n = 0, fails = 0
const ok = (label, cond) => { if (cond) n++; else { fails++; console.log('FAIL ' + label) } }
const throws = f => { try { f(); return false } catch (e) { return true } }

const own = b.launchTail('finder', '/o', [])
ok('launchTail plugin agent: no protocol line', !own.some(l => /^Result protocol:/.test(l)))
ok('launchTail no skills: last line', own[own.length - 1] === 'No skills needed for this step.')
ok('launchTail names the report path', own.some(l => l.includes('report (/o/result.md)')))
const g = b.launchTail('guide', '/o', ['/s/a/SKILL.md', '/s/b/SKILL.md'])
ok('launchTail guide: protocol spelled out', g.some(l => /^Result protocol: .*\/o\/result\.md already exists.*not fresh/.test(l)))
ok('launchTail skills: last line names every path', /^Read these skill files .*\/s\/a\/SKILL\.md \/s\/b\/SKILL\.md/.test(g[g.length - 1]))
ok('launchTail refuses a relative skill path', throws(() => b.launchTail('finder', '/o', ['a/SKILL.md'])))
ok('launchTail refuses an unknown helper', throws(() => b.launchTail('oracle', '/o', [])))

const good = 'status: completed\nreport: /o/result.md\nsummary: 3 hits'
ok('handbackAt matching report', b.handbackAt(good, '/o').status === 'completed')
const stale = b.handbackAt('status: completed\nreport: /old/result.md\nsummary: s', '/o')
ok('handbackAt foreign report is failed', stale.status === 'failed' && /\/old\/result\.md is not \/o\/result\.md/.test(stale.summary))
ok('handbackAt missing report is failed', /missing/.test(b.handbackAt('status: partial\nsummary: s', '/o').summary))
ok('handbackAt keeps blocked with its own report', b.handbackAt('status: blocked\nreport: /o/result.md\nsummary: result directory not fresh', '/o').status === 'blocked')
ok('handbackAt malformed stays failed', /malformed/.test(b.handbackAt('done', '/o').summary))
ok('handbackAt out with trailing slash', b.handbackAt(good, '/o/').status === 'completed')
ok('handbackAt report with double slash', b.handbackAt('status: completed\nreport: /o//result.md\nsummary: s', '/o/').status === 'completed')
ok('handbackAt trailing slash keeps a foreign report failed', b.handbackAt('status: completed\nreport: /old/result.md\nsummary: s', '/o/').status === 'failed')
ok('normPath collapses and trims', b.normPath('/a//b/') === '/a/b' && b.normPath('/') === '/' && b.normPath('/a') === '/a')

ok('isBlocked line start', b.isBlocked('BLOCKED: Bash denied') === true)
ok('isBlocked quoted mid-line is no block', b.isBlocked('status: completed\nreport: /r\nsummary: item 3 said BLOCKED: x') === false)
ok('isBlocked status line', b.isBlocked('status: blocked\nreport: /r\nsummary: s') === true)

const rows = b.batchRows(['a', 'b'], ['status: completed\nreport: /o/1-a/result.md\nsummary: ok', 'status: completed\nreport: /o/1-a/result.md\nsummary: ok'], ['/o/1-a', '/o/2-b'])
ok('batchRows with dirs: own report passes', rows[0].status === 'completed')
ok('batchRows with dirs: a neighbour report fails', rows[1].status === 'failed')

// helper.js and batch.js over a mock agent(): capture the prompt, answer with a scripted return
const AF = Object.getPrototypeOf(async function () {}).constructor
const load = p => new AF('args', 'agent', 'parallel', 'phase', 'log', fs.readFileSync(p, 'utf8').replace(/^export const meta/m, 'const meta'))
const run = async (p, args, answer) => {
  const seen = []
  const agent = async (prompt, opts) => { seen.push({ prompt, opts }); return answer(prompt, opts, seen.length - 1) }
  const parallel = async fs => Promise.all(fs.map(f => f()))
  const out = await load(p)(args, agent, parallel, () => {}, () => {})
  return { out, seen }
}
;(async () => {
  const H = process.argv[3], B = process.argv[4]
  let r = await run(H, { helper: 'guide', ask: 'q', out: '/o', skills: ['/s/x/SKILL.md'], class: 'c4', submodes: ['no-sonnet'] },
    () => 'status: completed\nreport: /o/result.md\nsummary: answered')
  const lines = r.seen[0].prompt.split('\n')
  ok('helper.js guide prompt carries the protocol', lines.some(l => /^Result protocol:/.test(l)))
  ok('helper.js prompt ends with the skill line', /^Read these skill files .*\/s\/x\/SKILL\.md/.test(lines[lines.length - 1]))
  ok('helper.js completed passes', r.out.status === 'completed' && r.out.report === '/o/result.md')
  r = await run(H, { helper: 'finder', ask: 'q', out: '/o' }, () => 'status: completed\nreport: /tmp/old/result.md\nsummary: s')
  ok('helper.js foreign report is failed', r.out.status === 'failed')
  ok('helper.js no skills: last prompt line', r.seen[0].prompt.split('\n').pop() === 'No skills needed for this step.')
  r = await run(H, { helper: 'checker', ask: 'q', out: '/o', codex: 'sol-medium' },
    (p, o, i) => i === 0 ? 'status: completed\nreport: /o/result.md\nsummary: s' : 'status: completed\nreport: /o/codex/result.md\nsummary: c')
  ok('helper.js codex pair checks its own dir', r.out.status === 'completed' && r.out.codex.status === 'completed')
  r = await run(B, { helper: 'finder', ask: 'find {item}', items: ['x', 'y'], out: '/o' },
    (p, o, i) => `status: completed\nreport: /o/${i + 1}-${i ? 'y' : 'x'}/result.md\nsummary: s`)
  ok('batch.js rows pass with own dirs', r.out.counts.completed === 2)
  r = await run(B, { helper: 'finder', ask: 'find {item}', items: ['x', 'y'], out: '/o' }, () => 'status: completed\nreport: /o/1-x/result.md\nsummary: s')
  ok('batch.js a shared report fails the other row', r.out.counts.completed === 1 && r.out.counts.failed === 1)
  console.log(fails ? `handback-js: FAIL ${fails} failures, ${n} checks passed` : `handback-js: PASS ${n}`)
  process.exit(fails ? 1 : 0)
})()
JS
check "handback unit and mock-run checks" test $? -eq 0
for f in "$P"/agents/*.md; do
  h=$(basename "$f" .md); b=$(body "$f")
  check "$h refuses a used result directory" grep -Fq 'summary: result directory not fresh' <<<"$b"
  check "$h writes result.md last" grep -Fq 'as the last file of the run' <<<"$b"
  check "$h no poll timeout over 120000" bash -c '! grep -Eo "timeout\`? *[0-9]+" <<<"$1" | grep -Eq "[0-9]{7,}|[2-9][0-9]{5}|1[3-9][0-9]{4}|12[1-9][0-9]{3}"' _ "$b"
done
check "checker has a search tool" grep -Eq '^tools: .*\bBash\b' "$P/agents/checker.md"
check "checker reads by enumerate then judge" bash -c 'grep -Fq "Enumerate:" "$1" && grep -Fq "Judge each instance" "$1"' _ "$P/agents/checker.md"
check "checker Bash is read-only" grep -Fq 'Bash is for reading and search only' "$P/agents/checker.md"
check "consumer isolation rule" grep -Fq 'Isolation: read only the document' "$P/agents/consumer.md"
check "finder can write result.md" grep -Eq '^tools: .*\bWrite\b' "$P/agents/finder.md"
done_with handback
