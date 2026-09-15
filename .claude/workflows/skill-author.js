export const meta = {
  name: 'skill-author',
  description: 'Writes one SKILL.md from source files: author, reviewer, fix cycles (1-3); round 2+ re-checks the previous findings and is clean when no high remains (medium accepted); then a memory-trim list. Args: name (string, required; directory name), purpose (string, required; one line), sources (array of absolute paths, required), cap (number, tokens, default 4000), out (string, absolute dir holding <name>/SKILL.md, default ~/.claude/skills), reviews (string, absolute dir, default ~/.claude/reviews/skill-<name>), absorbs (array of absolute memory file paths, default []), class (string c1-c5, default c3), submodes (array of strings from no-sonnet no-opus no-fable, default []). Output: <out>/<name>/SKILL.md, memory-trim.md under reviews, review text in the result. BLOCKED stage stops with a report.',
  whenToUse: 'A new or rewritten user or project skill with named sources: memory files, notes, scripts, existing skills.',
  phases: [{ title: 'Author' }, { title: 'Trim list' }],
}

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
// report(r): full reviewer return, capped; stages pass it inline, no stage reads a subagent-written report file
const report = (r, cap = 12000) => { const s = String(r || '').trim(); return s.length > cap ? `${s.slice(0, cap)}\n[truncated at ${cap} chars]` : s }

const SK = A.name
if (!SK) throw new Error('args.name (skill directory name) is required')
if (!A.purpose) throw new Error('args.purpose (one line) is required')
if (!A.sources || !A.sources.length) throw new Error('args.sources (array of absolute paths) is required')
const CAP = A.cap || 4000
const OUT = A.out || `${HOME}/.claude/skills`
const REV = A.reviews || `${HOME}/.claude/reviews/skill-${SK}`
const FILE = `${OUT}/${SK}/SKILL.md`
const SRC = A.sources.join('\n')
const ABS = A.absorbs || []
const NAME = [CLS, ...SUBS, 'skill-author'].join('-')
log(`${NAME} | name=${SK} sources=${A.sources.length} cap=${CAP} out=${OUT} absorbs=${ABS.length} slots=${ROW.join('/')}`)

const authorPrompt = `Skill author. Write ${FILE} (create the directory if missing). Purpose: ${A.purpose}
Frontmatter: name: ${SK}; description of 10-30 tokens (7-21 words) naming the purpose and the trigger words. Body: strategy only, cap ${CAP} tokens (at most ${Math.floor(CAP / 1.4)} words), every rule once, no reasons, no history, no examples over three lines.
Sources (absolute paths, read all in one pass):
${SRC}
Return: DONE plus the body word count, or BLOCKED: <reason>. ${STYLE}`

phase('Author')
const draft = await agent(authorPrompt, opts('opus', 'author', { agentType: 'skill-author', phase: 'Author' }))
if (blocked(draft)) return { stage: 'author', blocked: last(draft) }

const SEV = 'Severity: high = invented or wrong statement, or a rule the purpose requires that is missing; medium = duplicate, contradiction, rule that cannot be applied as written; low = wording.'
let lastReview = ''
let lastReviewRaw = ''
const reviewPrompt = i => i === 1
  ? `Skill reviewer, round 1. Draft: ${FILE}. Cap: ${CAP} tokens. Purpose: ${A.purpose}
Sources (absolute paths):
${SRC}
${SEV} Never write files. Return the findings numbered under High / Medium / Low, each with draft line, source line and fix.
Last line of your return: "VERDICT: clean" or "VERDICT: findings <n high> <m medium>". ${STYLE}`
  : `Skill reviewer, round ${i}. Draft: ${FILE}. Previous review is below. Sources (absolute paths):
${SRC}
Re-check only the previous findings: mark each applied, not applied or regressed (the fix broke something). Then scan the edited passages for regressions only: a new contradiction, an invented statement, cap overflow (${CAP} tokens). Raise no other new finding unless it is high. ${SEV} Never write files; return the re-check and the findings.
Previous review:
${lastReview}
Verdict: clean when no high remains; unresolved medium and low are listed as accepted, not counted. Last line of your return: "VERDICT: clean (<m> medium accepted)" or "VERDICT: findings <n high> <m medium>". ${STYLE}`
const loop = await cycle(3,
  i => agent(reviewPrompt(i), opts('main', `review-${i}`, { agentType: 'skill-reviewer', phase: 'Author' })).then(r => { lastReviewRaw = r; lastReview = report(r); return r }),
  (i, r) => agent(`Skill author, fix round ${i}. Apply every open finding (not applied, regressed, new) in the review below to ${FILE} in place; keep the cap of ${CAP} tokens (at most ${Math.floor(CAP / 1.4)} body words) and the 10-30 token description. Sources for reference:
${SRC}
Review ${i}:
${report(r)}
Return: DONE plus the count of findings applied and the body word count, or BLOCKED: <reason>. ${STYLE}`, opts('opus', `fix-${i}`, { agentType: 'skill-author', phase: 'Author' })))
if (loop.blocked) return { stage: 'review', blocked: loop.blocked, file: FILE }
const accepted = loop.clean ? (last(lastReviewRaw).match(/(\d+)\s+medium accepted/) || [])[1] : null

let trim = null, trimText = null
if (ABS.length) {
  phase('Trim list')
  const t = await agent(`Memory trim list. Skill: ${FILE}. Absorbed memory candidates (absolute paths, read all in one pass):
${ABS.join('\n')}
For each file decide: DELETE (every fact now lives in the skill), SHORTEN (some facts absorbed; list the lines to keep, at most 3), KEEP (nothing absorbed or the file carries a why that a skill must not carry). Write ${REV}/memory-trim.md: one line per file "<verdict> <path> | <kept lines or reason>", then a line "skill: ${FILE}". Never edit the memory files.
Return: the trim lines, then DONE plus counts per verdict, or BLOCKED: <reason>. ${STYLE}`, opts('opus', 'trim-list', { agentType: 'skill-author', phase: 'Trim list' }))
  trim = blocked(t) ? `BLOCKED ${last(t)}` : `${REV}/memory-trim.md`
  trimText = blocked(t) ? null : report(t)
}

return {
  class: CLS, submodes: SUBS, slots: SLOT, file: FILE, reviews: REV,
  result: loop.clean ? `clean after round ${loop.round}${accepted ? ` with ${accepted} medium accepted` : ''}` : `not clean after ${loop.round} rounds: ${loop.last}`,
  trim, trimText, lastReview, next: trim ? 'Check SKILL.md; then memory-gc with the trim file.' : 'Check SKILL.md.',
}
