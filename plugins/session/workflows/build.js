export const meta = {
  name: 'build',
  description: 'Implement an existing plan: code author works through the plan, code review, test run, fixer; 1-3 cycles until the review is clean and tests pass. Input args { cwd, plan (absolute path), class, submodes, test, out }. Output: code changed in the working tree (no commit), code-review-N.md and tests-N.md under out (default <cwd>/reviews). Stops with a report on any BLOCKED stage.',
  whenToUse: 'A reviewed plan file exists and only the implementation is missing. Use dev when there is no plan yet, review when the code already exists.',
  phases: [{ title: 'Implement' }],
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

const PLAN = A.plan
if (!PLAN) throw new Error('args.plan (absolute path to the plan file) is required')
const TEST = A.test || '(the command named in the plan under "Test command")'
log(`build: ${CLS} ${SUBS.join(' ') || 'no submodes'} slots ${ROW.join(' / ')}; plan ${PLAN}`)

phase('Implement')
const impl = await agent(`Code author. Implement the plan ${PLAN} in ${CWD}, step by step, until "${TEST}" passes. Read the plan and the files it lists first. Touch only the files the plan lists plus what a step strictly needs; note any extra file in your return. Existing tests stay as they are unless one contradicts the plan (say so). Do not commit.
Return: DONE plus "files: <list>, run: <the passing summary line>", or BLOCKED: <reason>. ${STYLE}`, opts('opus', 'implement', { agentType: 'session:stage-author', phase: 'Implement' }))
if (blocked(impl)) return { stage: 'implement', blocked: last(impl) }

const loop = await cycle(3,
  async i => {
    const rev = await agent(`Code reviewer. In ${CWD} review the uncommitted change: "git diff" plus new files from "git status --short"; read ${PLAN} for intent. Findings with file:line by severity: logic errors, error handling, races, boundaries, unchecked inputs, broken contracts with unchanged code, duplicated helpers, dead code, steps of the plan not done. Skip style. Never edit. Write ${OUT}/code-review-${i}.md (create ${OUT} if missing).
Last line of your return: "VERDICT: clean" or "VERDICT: findings <n high> <m medium>". ${STYLE}`, opts('sonnet', `code-review-${i}`, { agentType: 'session:code-reviewer', phase: 'Implement' }))
    if (blocked(rev)) return rev
    const tests = await agent(`Test executor. In ${CWD} run "${TEST}". Write ${OUT}/tests-${i}.md: one PASS/FAIL line plus the last 20 lines of output on failure. Never edit code.
Last line of your return: "VERDICT: clean" when the run passed, else "VERDICT: findings 1 high" plus the failing summary line. ${STYLE}`, opts('sonnet', `tests-${i}`, { agentType: 'session:stage-executor', phase: 'Implement' }))
    if (blocked(tests)) return tests
    return clean(rev) && clean(tests) ? 'VERDICT: clean' : `${last(rev)} | ${last(tests)}`
  },
  (i, r) => agent(`Code fixer. In ${CWD} apply ${OUT}/code-review-${i}.md (high and medium findings) and fix the failures in ${OUT}/tests-${i}.md. Run "${TEST}" until it passes. Do not commit.
Return: DONE plus the count applied and the passing summary line, or BLOCKED: <reason>. ${STYLE}`, opts('opus', `code-fix-${i}`, { agentType: 'session:stage-author', phase: 'Implement' })))

if (loop.blocked) return { stage: 'implement-review', blocked: loop.blocked }
return {
  class: CLS, submodes: SUBS, slots: SLOT, out: OUT, plan: PLAN,
  result: loop.clean ? `clean after round ${loop.round}` : `not clean after ${loop.round} rounds: ${loop.last}`,
  next: 'Read the newest code-review-N.md and tests-N.md; commit from the main session.',
}
