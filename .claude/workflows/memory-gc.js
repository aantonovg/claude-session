export const meta = {
  name: 'memory-gc',
  description: 'Apply memory trim list',
  whenToUse: 'A skill-author run produced memory-trim.md and the skill passed review.',
  phases: [{ title: 'Trim' }, { title: 'Check' }],
}
/* usage:
Applies a memory-trim list after a skill absorbed memory files; reviewer checks nothing unabsorbed was lost.
trim (string, absolute memory-trim.md path, required)
class (string c1-c5, default c3)
submodes (array of strings: no-sonnet no-opus no-fable, default [])
Out: memory files edited or deleted, MEMORY.md index fixed, review text in result.
Use: skill-author produced memory-trim.md and skill passed review. Not: same workflow as skill-author.
*/

// ---- shared block (copied verbatim into every script; scripts cannot import) ----
const T = {
  c1: { none: 'ops-lo/ops-lo/son-lo', 'no-sonnet': 'ops-lo/ops-lo/ops-lo', 'no-opus': 'son-me/son-me/son-lo', 'no-fable': 'ops-lo/ops-lo/son-lo', 'no-sonnet no-opus': 'fab-lo/fab-lo/fab-lo', 'no-sonnet no-fable': 'ops-lo/ops-lo/ops-lo', 'no-opus no-fable': 'son-me/son-me/son-lo' },
  c2: { none: 'fab-lo/ops-lo/son-me', 'no-sonnet': 'fab-lo/ops-lo/ops-lo', 'no-opus': 'fab-lo/son-me/son-me', 'no-fable': 'ops-me/ops-lo/son-me', 'no-sonnet no-opus': 'fab-lo/fab-lo/fab-lo', 'no-sonnet no-fable': 'ops-me/ops-lo/ops-lo', 'no-opus no-fable': 'son-me/son-me/son-me' },
  c3: { none: 'fab-lo/ops-me/son-hi', 'no-sonnet': 'fab-lo/ops-me/ops-me', 'no-opus': 'fab-lo/son-hi/son-hi', 'no-fable': 'ops-me/ops-me/son-hi', 'no-sonnet no-opus': 'fab-lo/fab-lo/fab-lo', 'no-sonnet no-fable': 'ops-me/ops-me/ops-me', 'no-opus no-fable': 'son-me/son-hi/son-hi' },
  c4: { none: 'fab-me/ops-hi/son-hi', 'no-sonnet': 'fab-me/ops-hi/ops-me', 'no-opus': 'fab-me/fab-me/son-hi', 'no-fable': 'ops-hi/ops-hi/son-hi', 'no-sonnet no-opus': 'fab-me/fab-me/fab-lo', 'no-sonnet no-fable': 'ops-hi/ops-hi/ops-me', 'no-opus no-fable': 'son-hi/son-hi/son-hi' },
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
const blocked = r => r == null || /BLOCKED:/.test(String(r))
const clean = r => /VERDICT:\s*clean/i.test(String(r))
const last = r => String(r || '').trim().split('\n').pop()
const STYLE = 'Plain English, caveman ultra; the return value is data. No skills needed for this step. On a permission denial stop at once and return BLOCKED: <denied action>.'
// ---- end shared block ----
// report(r): full reviewer return, capped; stages pass it inline, no stage reads a subagent-written report file
const report = (r, cap = 12000) => { const s = String(r || '').trim(); return s.length > cap ? `${s.slice(0, cap)}\n[truncated at ${cap} chars]` : s }

const TRIM = A.trim
if (!TRIM) throw new Error('args.trim (absolute path to memory-trim.md) is required')
const NAME = [CLS, ...SUBS, 'memory-gc'].join('-')
log(`${NAME} | trim=${TRIM} slots=${ROW.join('/')}`)

const trimPrompt = (i, review) => `Memory gardener${i > 1 ? `, fix round ${i}` : ''}. Trim list: ${TRIM}. Read the list and the skill it names in one pass.${review ? `\nReview to apply:\n${review}` : ''}
For each line: DELETE moves the file with mv into /Users/aleksandr.antonov/.claude/backups/2026-09-13-memory-trim/ (mkdir -p first; never rm); SHORTEN rewrites the file to its frontmatter plus the kept lines plus one line "Absorbed by skill <name>: <skill path>"; KEEP changes nothing. In the MEMORY.md index next to each touched file (same directory) delete the line of a deleted file and rewrite the line of a shortened file to name the skill. Touch nothing else.
Return: counts deleted, shortened, kept, index lines changed; last line DONE or BLOCKED: <reason>. ${STYLE}`

phase('Trim')
const t = await agent(trimPrompt(1), opts('opus', 'trim', { agentType: 'session:applier', phase: 'Trim' }))
if (blocked(t)) return { stage: 'trim', blocked: last(t) }

phase('Check')
const check = await agent(`Memory reviewer. Trim list: ${TRIM}. Read the list, the skill it names, every SHORTEN file and every MEMORY.md index touched, in one pass. Findings: a deleted or shortened fact that is absent from the skill (high); an index line still naming a deleted file, or missing for a shortened one (medium); a KEEP file that was changed (medium). Never write files. Return the findings with concrete fixes, or "no findings".
Last line of your return: "VERDICT: clean" or "VERDICT: findings <n high> <m medium>". ${STYLE}`, opts('main', 'gc-review', { agentType: 'skill-reviewer', phase: 'Check' }))
if (blocked(check)) return { stage: 'check', blocked: last(check) }

let fixed = null
if (!clean(check)) {
  const f = await agent(trimPrompt(2, report(check)), opts('opus', 'gc-fix', { agentType: 'session:applier', phase: 'Check' }))
  fixed = blocked(f) ? `BLOCKED ${last(f)}` : last(f)
}

return {
  class: CLS, submodes: SUBS, slots: SLOT, trim: TRIM, review: report(check),
  result: clean(check) ? 'clean' : `findings: ${last(check)}; fix: ${fixed}`,
  next: 'Read the review field; restore from git or backups if a fact was lost.',
}
