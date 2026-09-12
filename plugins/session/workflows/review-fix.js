export const meta = {
  name: 'review-fix',
  description: 'Review and fix loop on an existing change: code critique, evidence check of every finding by a second agent, fixes of the confirmed ones, test run; 1-3 cycles until clean. Input args { cwd, target (diff file, "a..b" range or "worktree"), class, submodes, test, out, fix (default true) }. Output: evidence-N.md and tests-N.md under out (default <cwd>/reviews); fixes in the working tree when fix is true. Stops with a report on any BLOCKED stage.',
  whenToUse: 'A finished diff, branch or MR needs a verified review, with or without fixes. Not for authoring code from a plan (use build).',
  phases: [{ title: 'Review' }],
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

const TARGET = A.target || 'worktree'
const FIX = A.fix !== false
const TEST = A.test || null
const targetLine = TARGET === 'worktree' ? 'the uncommitted change: "git diff" plus new files from "git status --short"' : /\.\./.test(TARGET) ? `the range: "git diff ${TARGET}"` : `the diff file ${TARGET}`
log(`review-fix: ${CLS} ${SUBS.join(' ') || 'no submodes'} slots ${ROW.join(' / ')}; target ${TARGET}; fix ${FIX}`)

phase('Review')
const loop = await cycle(FIX ? 3 : 1,
  async i => {
    const rev = await agent(`Code reviewer. In ${CWD} review ${targetLine}. Findings with file:line by severity (high / medium / low): logic errors, wrong or missing error handling, races, boundaries, unchecked inputs, broken contracts with unchanged code, duplicated helpers, dead code, needless complexity. Skip style. Read surrounding code only where a finding needs it. Never edit, never write files. Return the findings as one numbered list, one line each: "<n>. <severity> <file>:<line> <what is wrong>".
Last line of your return: "VERDICT: clean" when no high or medium finding, else "VERDICT: findings <n high> <m medium>". ${STYLE}`, opts('sonnet', `review-${i}`, { agentType: 'session:code-reviewer', phase: 'Review' }))
    if (blocked(rev) || clean(rev)) return rev
    const ev = await agent(`Evidence checker. Findings from the code reviewer:\n${String(rev).trim()}\nFor every numbered finding open the named file at the named line in ${CWD} and decide: CONFIRMED (the code does what the finding says), REFUTED (it does not; say why in one line), UNCLEAR (needs a run to tell). Do not fix anything. Write ${OUT}/evidence-${i}.md (create ${OUT} if missing): the same numbering, the finding text, the verdict, the decisive line quoted.
Last line of your return: "VERDICT: clean" when no high or medium finding is CONFIRMED or UNCLEAR, else "VERDICT: findings <n confirmed> <m unclear>". ${STYLE}`, opts('sonnet', `evidence-${i}`, { agentType: 'session:stage-researcher', phase: 'Review' }))
    return ev
  },
  (i, r) => agent(`Code fixer. In ${CWD} apply every finding marked CONFIRMED or UNCLEAR with severity high or medium in ${OUT}/evidence-${i}.md. Smallest correct change each. ${TEST ? `Then run "${TEST}"; write ${OUT}/tests-${i}.md with PASS/FAIL and the last 20 lines on failure.` : 'No test command given: do not run tests.'} Do not commit.
Return: DONE plus the count applied${TEST ? ' and the test summary line' : ''}, or BLOCKED: <reason>. ${STYLE}`, opts('opus', `fix-${i}`, { agentType: 'session:stage-author', phase: 'Review' })))

if (loop.blocked) return { stage: 'review', blocked: loop.blocked }
return {
  class: CLS, submodes: SUBS, slots: SLOT, out: OUT, target: TARGET, fixed: FIX,
  result: loop.clean ? `clean after round ${loop.round}` : `not clean after ${loop.round} rounds: ${loop.last}`,
  next: FIX ? 'Read the newest evidence-N.md; commit from the main session.' : 'Read evidence-1.md.',
}
