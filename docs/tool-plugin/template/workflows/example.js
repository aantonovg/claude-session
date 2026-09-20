export const meta = {
  name: 'example',
  description: 'Example server lookup',
  whenToUse: 'One job against the example server: find an object, read it, write the answer. Copy this file per job the server is needed for.',
  phases: [{ title: 'Lookup' }],
}
/* usage:
One job against the example server, one agent, one file.
ask (the job in prose, required)
object (required): what to look up on the server
out (absolute output file, required)
class (c1-c5, default c3)
submodes (array: no-sonnet no-opus no-fable, default [])
Out: returns {object, out, class, label}, or blocked.
Use: a job only this server can answer. Not: a flow, not a job the base set already covers.
*/

// A tool plugin stands alone: it carries its own class table, its own contract script and its own
// agents, and it names nothing of another plugin. The table is the one-slot column the calls of
// this plugin run on; a class plus its submodes is the only source of the model and the reasoning
// level, so no agent file and no prose of this plugin names either.
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
const AGENT = 'example-tools:tools-example'

function subKey(subs) {
  const s = (subs || []).slice().sort((a, b) => SUBORDER.indexOf(a) - SUBORDER.indexOf(b))
  return s.length ? s.join(' ') : 'none'
}

// the last line of a return: a block check reads that line and nothing above it
function lastLine(r) { return String(r == null ? '' : r).trim().split('\n').pop().trim() }

// The one exit of this script: a blocked run never returns the success shape, so no caller can
// read a failure as an answer.
function result(o) {
  const head = { workflow: 'example', object: o.object || null, out: o.out || null }
  return o.blocked ? { ...head, blocked: o.blocked, ...(o.extra || {}) }
    : { ...head, class: o.class, label: o.label, agent: AGENT, result: o.result }
}

let A = args || {}
if (typeof A === 'string') A = JSON.parse(A)
const OBJ = A.object
const ASK = A.ask
const OUT = A.out
const CLS = A.class || 'c3'
const SUBS = Array.isArray(A.submodes) ? A.submodes : []

log(`${[CLS, ...SUBS].join('-')}-example | object=${OBJ || '(none)'} out=${OUT || '(none)'}`)

if (!OBJ) return result({ blocked: 'args.object is required' })
if (!ASK) return result({ object: OBJ, blocked: 'args.ask (the job in prose) is required' })
if (!OUT || typeof OUT !== 'string' || OUT[0] !== '/') return result({ object: OBJ, blocked: 'args.out must be one absolute output path' })
if (!CELL[CLS]) return result({ object: OBJ, out: OUT, blocked: `unknown class ${CLS}`, extra: { classes: Object.keys(CELL) } })
const BAD = SUBS.filter(s => !SUBORDER.includes(s))
if (BAD.length) return result({ object: OBJ, out: OUT, blocked: `unknown submode ${BAD.join(' ')}`, extra: { submodes: SUBORDER } })
const ROW = CELL[CLS][subKey(SUBS)]
if (!ROW) return result({ object: OBJ, out: OUT, blocked: `no cell for ${CLS} with ${subKey(SUBS)}` })

const SHORT = ROW.split('-')
const O = { agentType: AGENT, phase: 'Lookup', model: MODEL[SHORT[0]], effort: LEVEL[SHORT[1]], label: `${ROW}-example` }

phase('Lookup')
const r = await agent(`Answer one question against the example server.

Object: ${OBJ}
Job: ${ASK}

Find the object with mcp__example__list, read what the job needs with mcp__example__query, and
answer from what the server returned, never from memory. Write ${OUT} yourself. Work only inside
the directory that path names. Start your return with one line \`${OUT} <n> bytes\`, then the
answer. On a permission denial stop at once and return BLOCKED: <the denied action>.`, O)

const LINE = lastLine(r)
// the word counts on the last line alone: the prompt above asks the agent to write it there, so a
// return that quotes it higher up (a finding, a path, the rule itself) is a finished lookup
if (!LINE || /^BLOCKED:/.test(LINE)) return result({ object: OBJ, out: OUT, blocked: LINE || 'the agent returned nothing' })
// the size stands on the FIRST line, the one the prompt asks for: a count quoted further down (a
// log the agent pasted, another file) is no evidence that this file was written. The path is
// compared as text and never built into a pattern — an `out` holding `(`, `[` or `\` would make a
// pattern that throws a SyntaxError out of this script instead of returning the blocked shape.
const FIRST = String(r == null ? '' : r).trim().split('\n')[0] || ''
const SIZE = FIRST.match(/(\d[\d,]*) *bytes\b/)
if (FIRST.indexOf(OUT) === -1 || !SIZE || !(Number(SIZE[1].replace(/,/g, '')) > 0)) {
  return result({ object: OBJ, out: OUT, blocked: `the first line of the return is no size line for ${OUT}` })
}
return result({ object: OBJ, out: OUT, class: CLS, label: O.label, result: LINE })
