export const meta = {
  name: 'dev',
  description: 'Full development run on one task: plan, plan critique and fix (1-3), red tests with review (1-3), implementation with code review, test run and fix (1-3), closure review. Input args { cwd, task, class, submodes, paths, test, out }. Output: plan, reviews and closure under out (default <cwd>/reviews), code changed in the working tree, no commit. Stops with a report on any BLOCKED stage.',
  whenToUse: 'A code change of class c2-c5 with acceptance criteria: new feature, non-trivial fix, refactor with tests. Not for research only (use research) or an existing plan (use build).',
  phases: [{ title: 'Plan' }, { title: 'Red tests' }, { title: 'Implement' }, { title: 'Closure' }],
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

const TASK = A.task
if (!TASK) throw new Error('args.task is required')
const PATHS = (A.paths || []).join('\n')
const TEST = A.test || '(the command named in plan.md under "Test command")'
log(`dev: ${CLS} ${SUBS.join(' ') || 'no submodes'} slots ${ROW.join(' / ')}`)

phase('Plan')
const plan = await agent(`Plan author. Write an implementation plan for the task below into ${OUT}/plan.md (create ${OUT} if missing).
Repository: ${CWD}. Read the files listed under Inputs first, then only what the plan needs.
Task: ${TASK}
Inputs (absolute paths):
${PATHS || '(none named: locate the relevant files yourself, at most 10 reads)'}
Plan sections, in order: Goal (2 lines); Acceptance criteria (numbered, each testable); Files to change (path, what changes); Test command (one shell line, or "${A.test || 'to be decided'}"); Steps (numbered, each one commit-sized); Risks (what may break, how to check). At most 120 lines.
Return: DONE plus the criteria count, or BLOCKED: <reason>. ${STYLE}`, opts('opus', 'plan', { agentType: 'session:stage-author', phase: 'Plan' }))
if (blocked(plan)) return { stage: 'plan', blocked: last(plan) }

const planLoop = await cycle(3,
  i => agent(`Plan reviewer. Read ${OUT}/plan.md and the files it lists (budget: read all inputs in one pass, one write). Write ${OUT}/plan-review-${i}.md: findings ordered by severity (high / medium / low), each with the plan line, why it matters, the concrete fix. Look for: acceptance criteria that no test can check, missing files, steps out of order, risks without a check, scope beyond the task. No praise, no summary.
Task for reference: ${TASK}
Last line of your return: "VERDICT: clean" when there is no high or medium finding, else "VERDICT: findings <n high> <m medium>". ${STYLE}`, opts('main', `plan-review-${i}`, { agentType: 'session:stage-reviewer', phase: 'Plan' })),
  (i, r) => agent(`Plan fixer. Apply ${OUT}/plan-review-${i}.md to ${OUT}/plan.md: every high and medium finding, low ones when cheap. Keep the section order. Do not change the task scope. Read both files in one pass, write once.
Return: DONE plus the count of findings applied, or BLOCKED: <reason>. ${STYLE}`, opts('opus', `plan-fix-${i}`, { agentType: 'session:stage-author', phase: 'Plan' })))
if (planLoop.blocked) return { stage: 'plan-review', blocked: planLoop.blocked }
if (!planLoop.clean) log(`plan: not clean after ${planLoop.round} rounds, continuing on the last version (${planLoop.last})`)

phase('Red tests')
const red = await agent(`Test author. Read ${OUT}/plan.md. Write failing tests in ${CWD} that map one to one onto its acceptance criteria, in the project's existing test framework and layout (look at one existing test file first). Do not implement the feature. Run "${TEST}" once and confirm the new tests fail for the right reason (missing behaviour, not a syntax error).
Return: DONE plus "<n> tests, <m> criteria covered, run: <the failing summary line>", or BLOCKED: <reason>. ${STYLE}`, opts('opus', 'red-tests', { agentType: 'session:stage-author', phase: 'Red tests' }))
if (blocked(red)) return { stage: 'red-tests', blocked: last(red) }

const redLoop = await cycle(2,
  i => agent(`Test reviewer. In ${CWD} run "git diff" plus "git status --short" to see the new tests; read ${OUT}/plan.md for the acceptance criteria. Check: every criterion has a test, every test checks behaviour (not implementation details), no test passes before the feature exists, fixtures are minimal. Never edit files. Write ${OUT}/tests-review-${i}.md with findings by severity and file:line.
Last line of your return: "VERDICT: clean" or "VERDICT: findings <n high> <m medium>". ${STYLE}`, opts('sonnet', `tests-review-${i}`, { agentType: 'session:code-reviewer', phase: 'Red tests' })),
  (i, r) => agent(`Test fixer. Apply ${OUT}/tests-review-${i}.md to the test files in ${CWD}: high and medium findings. Run "${TEST}" once; the new tests must still fail for the right reason.
Return: DONE plus the count applied and the failing summary line, or BLOCKED: <reason>. ${STYLE}`, opts('opus', `tests-fix-${i}`, { agentType: 'session:stage-author', phase: 'Red tests' })))
if (redLoop.blocked) return { stage: 'red-tests-review', blocked: redLoop.blocked }

phase('Implement')
const impl = await agent(`Code author. Implement ${OUT}/plan.md in ${CWD}, step by step, until "${TEST}" passes. Touch only the files the plan lists plus what a step strictly needs; note any extra file in your return. Do not edit the tests except to fix a test that contradicts the plan (say so). Do not commit.
Return: DONE plus "files: <list>, run: <the passing summary line>", or BLOCKED: <reason>. ${STYLE}`, opts('opus', 'implement', { agentType: 'session:stage-author', phase: 'Implement' }))
if (blocked(impl)) return { stage: 'implement', blocked: last(impl) }

let tests = null
const implLoop = await cycle(3,
  async i => {
    const rev = await agent(`Code reviewer. In ${CWD} review the uncommitted change: "git diff" plus new files from "git status --short"; read ${OUT}/plan.md for intent. Findings with file:line by severity: logic errors, error handling, races, boundaries, unchecked inputs, broken contracts with unchanged code, duplicated helpers, dead code. Skip style. Never edit. Write ${OUT}/code-review-${i}.md.
Last line: "VERDICT: clean" or "VERDICT: findings <n high> <m medium>". ${STYLE}`, opts('sonnet', `code-review-${i}`, { agentType: 'session:code-reviewer', phase: 'Implement' }))
    if (blocked(rev)) return rev
    tests = await agent(`Test executor. In ${CWD} run "${TEST}". Write ${OUT}/tests-${i}.md: one PASS/FAIL line for the run plus the last 20 lines of output on failure. Never edit code.
Last line of your return: "VERDICT: clean" when the run passed, else "VERDICT: findings 1 high" plus the failing summary line. ${STYLE}`, opts('sonnet', `tests-${i}`, { agentType: 'session:stage-executor', phase: 'Implement' }))
    if (blocked(tests)) return tests
    return clean(rev) && clean(tests) ? 'VERDICT: clean' : `${last(rev)} | ${last(tests)}`
  },
  (i, r) => agent(`Code fixer. In ${CWD} apply ${OUT}/code-review-${i}.md (high and medium findings) and fix the failures in ${OUT}/tests-${i}.md. Run "${TEST}" until it passes. Do not commit.
Return: DONE plus the count applied and the passing summary line, or BLOCKED: <reason>. ${STYLE}`, opts('opus', `code-fix-${i}`, { agentType: 'session:stage-author', phase: 'Implement' })))
if (implLoop.blocked) return { stage: 'implement-review', blocked: implLoop.blocked }

phase('Closure')
const closure = await agent(`Closure author. In ${CWD} write ${OUT}/closure.md: what changed (from "git diff --stat"), each acceptance criterion of ${OUT}/plan.md with the test that proves it and the run result from the newest ${OUT}/tests-*.md, open review findings (from the newest ${OUT}/code-review-*.md), risks left. At most 60 lines. No commit.
Return: DONE, or BLOCKED: <reason>. ${STYLE}`, opts('opus', 'closure', { agentType: 'session:stage-author', phase: 'Closure' }))
if (blocked(closure)) return { stage: 'closure', blocked: last(closure) }
const closureReview = await agent(`Closure reviewer. Read ${OUT}/closure.md, ${OUT}/plan.md and the newest ${OUT}/tests-*.md and ${OUT}/code-review-*.md in one pass (budget 3 reads, 1 write). Write ${OUT}/closure-review.md: claims in the closure that the evidence does not support, criteria without a proving test, findings left open. Ordered by severity.
Last line: "VERDICT: clean" or "VERDICT: findings <n high> <m medium>". ${STYLE}`, opts('main', 'closure-review', { agentType: 'session:stage-reviewer', phase: 'Closure' }))

return {
  class: CLS, submodes: SUBS, slots: SLOT, out: OUT,
  plan: planLoop, redTests: redLoop, implementation: implLoop,
  closure: last(closureReview),
  next: 'Read closure.md and closure-review.md; commit from the main session.',
}
