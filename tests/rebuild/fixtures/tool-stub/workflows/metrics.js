export const meta = {
  name: 'metrics',
  description: 'Metrics store lookup',
  whenToUse: 'One value of the metrics store this plugin carries. No other source holds these numbers: one key in, one number out.',
  phases: [{ title: 'Metrics' }],
}
/* usage:
One key of the metrics store this plugin carries, one number back.
key (required): a key of the store, one line per key
store (required): the store file, {ROOT}/data/metrics.txt
ask (the job in prose, default: report the value)
out (absolute output file, optional)
class (c1-c5, default c3)
submodes (array: no-sonnet no-opus no-fable, default [])
Out: returns {key, store, value, class, label}, or blocked; writes out when given.
Use: a number only this store holds. Not: a flow, not a number of another source.
*/

// This plugin stands alone: it carries its own class table, its own contract script and its own
// agent, and it names nothing outside its own root. The table below is the one-slot column of the
// class table this plugin launches on; a class and its submodes are the only source of the model
// and the reasoning level of a call, exactly as in any other plugin of this pattern.
const CELL = {
  c1: { 'none': 'son-lo', 'no-sonnet': 'ops-lo', 'no-opus': 'son-lo', 'no-fable': 'son-lo', 'no-sonnet no-opus': 'fab-lo', 'no-sonnet no-fable': 'ops-lo', 'no-opus no-fable': 'son-lo' },
  c2: { 'none': 'son-me', 'no-sonnet': 'ops-lo', 'no-opus': 'son-me', 'no-fable': 'son-me', 'no-sonnet no-opus': 'fab-lo', 'no-sonnet no-fable': 'ops-lo', 'no-opus no-fable': 'son-me' },
  c3: { 'none': 'son-hi', 'no-sonnet': 'ops-me', 'no-opus': 'son-hi', 'no-fable': 'son-hi', 'no-sonnet no-opus': 'fab-lo', 'no-sonnet no-fable': 'ops-me', 'no-opus no-fable': 'son-hi' },
  c4: { 'none': 'son-hi', 'no-sonnet': 'ops-me', 'no-opus': 'son-hi', 'no-fable': 'son-hi', 'no-sonnet no-opus': 'fab-lo', 'no-sonnet no-fable': 'ops-me', 'no-opus no-fable': 'son-hi' },
  c5: { 'none': 'ops-hi', 'no-sonnet': 'ops-hi', 'no-opus': 'fab-me', 'no-fable': 'ops-hi', 'no-sonnet no-opus': 'fab-me', 'no-sonnet no-fable': 'ops-hi', 'no-opus no-fable': 'son-hi' },
}
const MODEL = { fab: 'fable', ops: 'opus', son: 'sonnet' }
const LEVEL = { lo: 'low', me: 'medium', hi: 'high' }
const SUBORDER = ['no-sonnet', 'no-opus', 'no-fable']
const AGENT = 'toolstub:tools-metrics'

// the submode key of a row: the names in the order of the table, `none` when there is none
function subKey(subs) {
  const s = (subs || []).slice().sort((a, b) => SUBORDER.indexOf(a) - SUBORDER.indexOf(b))
  return s.length ? s.join(' ') : 'none'
}

// the last line of a return: a block check reads that line and nothing above it
function lastLine(r) { return String(r == null ? '' : r).trim().split('\n').pop().trim() }

// The one exit of this script. A blocked run never carries a value: the two shapes share no key
// but the ones that describe the call, so a caller can never read a failure as a number.
function result(o) {
  const head = { workflow: 'metrics', key: o.key || null, store: o.store || null }
  if (o.blocked) return { ...head, blocked: o.blocked, ...(o.extra || {}) }
  return { ...head, value: o.value, class: o.class, label: o.label, agent: AGENT, out: o.out || null }
}

let A = args || {}
if (typeof A === 'string') A = JSON.parse(A)
const KEY = A.key
const STORE = A.store
const CLS = A.class || 'c3'
const SUBS = Array.isArray(A.submodes) ? A.submodes : []
const OUT = A.out || null
const ASK = A.ask || 'report the value of that key'

log(`${[CLS, ...(Array.isArray(A.submodes) ? A.submodes : [])].join('-')}-metrics | key=${KEY || '(none)'} store=${STORE || '(none)'} out=${OUT || '(none)'}`)

if (!KEY) return result({ blocked: 'args.key is required: one key of the metrics store' })
if (!STORE) return result({ key: KEY, blocked: 'args.store is required: the store path the contract line names' })
if (typeof STORE !== 'string' || STORE[0] !== '/') return result({ key: KEY, blocked: `args.store must be an absolute path, got ${STORE}` })
if (!CELL[CLS]) return result({ key: KEY, store: STORE, blocked: `unknown class ${CLS}`, extra: { classes: Object.keys(CELL) } })
if (A.submodes !== undefined && !Array.isArray(A.submodes)) return result({ key: KEY, store: STORE, blocked: 'args.submodes must be a JSON array', extra: { submodes: SUBORDER } })
const BAD = SUBS.filter(s => !SUBORDER.includes(s))
if (BAD.length) return result({ key: KEY, store: STORE, blocked: `unknown submode ${BAD.join(' ')}`, extra: { submodes: SUBORDER } })
const ROW = CELL[CLS][subKey(SUBS)]
if (!ROW) return result({ key: KEY, store: STORE, blocked: `no cell for ${CLS} with ${subKey(SUBS)}` })

const SHORT = ROW.split('-')
const O = { agentType: AGENT, phase: 'Metrics', model: MODEL[SHORT[0]], effort: LEVEL[SHORT[1]], label: `${ROW}-metrics` }
log(`metrics | key=${KEY} class=${CLS} label=${O.label} agent=${AGENT}`)

const PROMPT = `Report one value of the metrics store of this plugin.

Store (plain text, one \`<key> <value>\` per line): ${STORE}
Key: ${KEY}
Job: ${ASK}

Look the key up with your shell: \`grep -E "^${KEY} " ${STORE}\`. That store is the only place this
number lives, so a number from memory or from any other file is a wrong answer; when the key is
missing from the store, say so instead of inventing a value.${OUT ? ` Write the answer into ${OUT}.` : ''}
Work only inside the directory the store path names${OUT ? ' and the directory the output path names' : ''}.
Return the value on the last line, alone, in the form \`${KEY} <value>\`. On a permission denial stop at once and return BLOCKED: <the denied action>.`

phase('Metrics')
const r = await agent(PROMPT, O)
const LINE = lastLine(r)
// the word counts on the last line alone: this script's own prompt asks the agent to write it
// there, so a return quoting it anywhere above (a finding, a path, the rule itself) is no block
if (!LINE || /^BLOCKED:/.test(LINE)) {
  return result({ key: KEY, store: STORE, blocked: LINE || 'the metrics agent returned nothing' })
}
if (!LINE.startsWith(`${KEY} `)) {
  return result({ key: KEY, store: STORE, blocked: `the return does not end in the value line of ${KEY}: ${LINE}` })
}
return result({ key: KEY, store: STORE, out: OUT, value: LINE.slice(KEY.length + 1).trim(), class: CLS, label: O.label })
