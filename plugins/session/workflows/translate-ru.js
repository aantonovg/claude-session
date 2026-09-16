export const meta = {
  name: 'translate-ru',
  description: 'Translate file to Russian',
  whenToUse: 'A finished English document (plan, proposal, report) must be shown to the user in Russian, for Plannotator or reading.',
  phases: [{ title: 'Estimate' }, { title: 'Translate' }],
}
/* usage:
Translates one English file to Russian; size estimate picks the translator slot.
file (string, absolute path, required)
out (string, absolute path, default <file> with _ru before extension)
class (string c1-c5, default c3)
submodes (array of strings: no-sonnet no-opus no-fable, default [])
Out: the _ru file; returns {file, out, tokens, slot}.
Use: finished English document for Plannotator or reading.
*/

// ---- shared block (copied verbatim into every script; scripts cannot import) ----
const T = {
  c1: { none: 'ops-lo/ops-lo/son-lo', 'no-sonnet': 'ops-lo/ops-lo/ops-lo', 'no-opus': 'son-me/son-me/son-lo', 'no-fable': 'ops-lo/ops-lo/son-lo', 'no-sonnet no-opus': 'fab-lo/fab-lo/fab-lo', 'no-sonnet no-fable': 'ops-lo/ops-lo/ops-lo', 'no-opus no-fable': 'son-me/son-me/son-lo' },
  c2: { none: 'fab-lo/ops-lo/son-me', 'no-sonnet': 'fab-lo/ops-lo/ops-lo', 'no-opus': 'fab-lo/son-me/son-me', 'no-fable': 'ops-me/ops-lo/son-me', 'no-sonnet no-opus': 'fab-lo/fab-lo/fab-lo', 'no-sonnet no-fable': 'ops-me/ops-lo/ops-lo', 'no-opus no-fable': 'son-me/son-me/son-me' },
  c3: { none: 'fab-lo/ops-me/son-hi', 'no-sonnet': 'fab-lo/ops-me/ops-me', 'no-opus': 'fab-lo/son-hi/son-hi', 'no-fable': 'ops-me/ops-me/son-hi', 'no-sonnet no-opus': 'fab-lo/fab-me/fab-me', 'no-sonnet no-fable': 'ops-me/ops-me/ops-me', 'no-opus no-fable': 'son-me/son-hi/son-hi' },
  c4: { none: 'fab-me/ops-hi/son-hi', 'no-sonnet': 'fab-me/ops-hi/ops-me', 'no-opus': 'fab-me/fab-me/son-hi', 'no-fable': 'ops-hi/ops-hi/son-hi', 'no-sonnet no-opus': 'fab-me/fab-me/fab-me', 'no-sonnet no-fable': 'ops-hi/ops-hi/ops-me', 'no-opus no-fable': 'son-hi/son-hi/son-hi' },
  c5: { none: 'fab-hi/ops-hi/ops-hi', 'no-sonnet': 'fab-hi/ops-hi/ops-hi', 'no-opus': 'fab-hi/fab-me/fab-me', 'no-fable': 'ops-hi/ops-hi/ops-hi', 'no-sonnet no-opus': 'fab-hi/fab-me/fab-me', 'no-sonnet no-fable': 'ops-hi/ops-hi/ops-hi', 'no-opus no-fable': 'son-hi/son-hi/son-hi' },
}
const MODEL = { fab: 'fable', ops: 'opus', son: 'sonnet' }
const EFF = { lo: 'low', me: 'medium', hi: 'high' }
const A = args || {}
const CLS = A.class || 'c3'
const ORDER = ['no-sonnet', 'no-opus', 'no-fable']
const SUBS = ORDER.filter(s => (A.submodes || []).includes(s))
if (!T[CLS]) throw new Error(`unknown class ${CLS}`)
if (SUBS.length === 3) throw new Error('all three submodes banned: nothing left to run on')
const ROW = T[CLS][SUBS.join(' ') || 'none'].split('/')
const SLOT = { main: ROW[0], opus: ROW[1], sonnet: ROW[2] }
// opts(slot, job) -> { model, effort, label } for one agent() call
const opts = (slot, job, extra) => {
  const [m, e] = SLOT[slot].split('-')
  return { model: MODEL[m], effort: EFF[e], label: `${SLOT[slot]}-${job}`, ...extra }
}
const HOME = '/Users/aleksandr.antonov'
const blocked = r => r == null || /BLOCKED:/.test(String(r))
const clean = r => /VERDICT:\s*clean/i.test(String(r))
const last = r => String(r || '').trim().split('\n').pop()
const STYLE = 'Plain English, caveman ultra; the return value is data. No skills needed for this step. On a permission denial stop at once and return BLOCKED: <denied action>.'
// cycle: review -> fix, up to max rounds; stops on clean, blocked or max
async function cycle(max, review, fix) {
  for (let i = 1; i <= max; i++) {
    const r = await review(i)
    if (blocked(r)) return { blocked: last(r), round: i }
    if (clean(r)) return { clean: true, round: i }
    if (i === max) return { clean: false, round: i, last: last(r) }
    const f = await fix(i, r)
    if (blocked(f)) return { blocked: last(f), round: i }
  }
}
// ---- end shared block ----

const FILE = A.file
if (!FILE) throw new Error('args.file (absolute path) is required')
const OUT = A.out || FILE.replace(/(\.[^./]+)?$/, (ext) => `_ru${ext}`)
const NAME = [CLS, ...SUBS, 'translate-ru'].join('-')

phase('Estimate')
const SIZE_SCHEMA = { type: 'object', properties: { words: { type: 'number' }, bytes: { type: 'number' }, tokens: { type: 'number' } }, required: ['words', 'bytes', 'tokens'] }
const size = await agent(`Measure the file ${FILE}: one Bash call \`wc -w ${FILE}; wc -c ${FILE}\` (timeout 120000); tokens = round(words * 1.4). Return the numbers. ${STYLE}`,
  { agentType: 'session:size-estimator', model: 'haiku', effort: 'medium', label: 'hai-me-size', phase: 'Estimate', schema: SIZE_SCHEMA })
if (!size || typeof size.tokens !== 'number') return { stage: 'estimate', blocked: 'size-estimator returned no numbers', file: FILE }
const TOK = size.tokens
const slot = TOK < 1000 ? 'main' : TOK <= 2000 ? 'opus' : 'sonnet'
log(`${NAME} | file=${FILE} tokens=${TOK} slot=${slot}=${SLOT[slot]} out=${OUT}`)

phase('Translate')
const r = await agent(`Translate ${FILE} into Russian and write ${OUT}. Faithful and complete, same markdown structure and tables; identifiers, paths, commands, code blocks, numbers, model and tool names verbatim; natural technical Russian; no shortening, no additions. Read once, Write once. Return only the output path. ${STYLE}`,
  opts(slot, 'translate', { agentType: 'session:translator', phase: 'Translate' }))
if (blocked(r)) return { stage: 'translate', blocked: last(r), file: FILE, tokens: TOK, slot: SLOT[slot] }
return { file: FILE, out: OUT, tokens: TOK, slot: SLOT[slot] }
