export const meta = {
  name: 'research',
  description: 'Fact research on one question: one stage-researcher per direction in parallel, each writes a notes file; one critique of all notes; one synthesis. Input args { cwd, question, directions (array of strings, 2-6), paths, class, submodes, out }. Output: notes-N.md, critique.md and research.md under out (default <cwd>/reviews). Read-only on the repository. Stops with a report when every direction is BLOCKED.',
  whenToUse: 'The task needs facts from the repository, git history or docs before a plan can be written, and the question splits into directions. Web questions belong to web-researcher, not here.',
  phases: [{ title: 'Research' }, { title: 'Synthesis' }],
}

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
const CWD = A.cwd
if (!CWD) throw new Error('args.cwd (absolute repo path) is required')
const OUT = A.out || `${CWD}/reviews`
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

const Q = A.question
if (!Q) throw new Error('args.question is required')
const DIRS = A.directions && A.directions.length ? A.directions : [Q]
const PATHS = (A.paths || []).join('\n')
log(`research: ${CLS} ${SUBS.join(' ') || 'no submodes'} slots ${ROW.join(' / ')}; ${DIRS.length} directions`)

phase('Research')
const notes = await parallel(DIRS.map((d, n) => () => agent(`Fact researcher, direction ${n + 1} of ${DIRS.length}: ${d}
Question: ${Q}
Repository: ${CWD}. Start from the inputs below, then git log and grep as needed; read only what the direction needs. No web.
Inputs (absolute paths):
${PATHS || '(none named)'}
Write ${OUT}/notes-${n + 1}.md (create ${OUT} if missing): Direction; Facts (each with file:line or commit hash as evidence); Unknowns (what you could not establish and why); at most 80 lines. Never edit repository files.
Return: DONE plus the fact count, or BLOCKED: <reason>. ${STYLE}`, opts('sonnet', `notes-${n + 1}`, { agentType: 'session:stage-researcher', phase: 'Research' }))))
const done = notes.map((r, n) => ({ n: n + 1, r })).filter(x => !blocked(x.r))
notes.forEach((r, n) => { if (blocked(r)) log(`direction ${n + 1} blocked: ${last(r)}`) })
if (!done.length) return { stage: 'research', blocked: 'every direction blocked', directions: DIRS }

phase('Synthesis')
const files = done.map(x => `${OUT}/notes-${x.n}.md`).join(', ')
const critique = await agent(`Critic. Read ${files} in one pass (at most ${done.length + 1} tool calls: the reads and one write). Write ${OUT}/critique.md: facts without evidence, contradictions between notes, unknowns that change the answer to the question, directions that missed the point. Ordered by severity. No praise, no summary.
Question: ${Q}
Last line of your return: "VERDICT: clean" or "VERDICT: findings <n high> <m medium>". ${STYLE}`, opts('main', 'critique', { agentType: 'session:stage-critic', phase: 'Synthesis' }))
if (blocked(critique)) return { stage: 'critique', blocked: last(critique), notes: files }

const synth = await agent(`Synthesis author. Read ${files} and ${OUT}/critique.md in one pass. Write ${OUT}/research.md: Answer (to the question, 5-10 lines, each claim with its evidence pointer); Facts by direction (deduplicated, with evidence); Open unknowns (from the notes and the critique); Recommended next step. At most 120 lines. Do not add facts of your own; do not edit repository files.
Question: ${Q}
Return: DONE, or BLOCKED: <reason>. ${STYLE}`, opts('opus', 'synthesis', { agentType: 'session:stage-author', phase: 'Synthesis' }))
if (blocked(synth)) return { stage: 'synthesis', blocked: last(synth), notes: files }

return {
  class: CLS, submodes: SUBS, slots: SLOT, out: OUT,
  directions: DIRS.length, completed: done.length, critique: last(critique),
  file: `${OUT}/research.md`, next: 'Read research.md; plan from it (dev or build).',
}
