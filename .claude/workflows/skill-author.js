export const meta = {
  name: 'skill-author',
  description: 'Write one skill',
  whenToUse: 'A new or rewritten user or project skill with named sources: memory files, notes, scripts, existing skills.',
  phases: [{ title: 'Author' }, { title: 'Trim list' }],
}
/* usage:
Writes one SKILL.md from sources with review and fix cycles, then a memory-trim list.
name (string, directory name, required)
purpose (string, one line, required)
sources (array of absolute paths, required)
cap (number, tokens, default 4000)
out (string, absolute dir, default ~/.claude/skills)
reviews (string, absolute dir, default ~/.claude/reviews/skill-<name>)
absorbs (array of absolute memory file paths, default [])
class (string c1-c5, default c3)
submodes (array of strings: no-sonnet no-opus no-fable, default [])
Out: status (completed partial blocked failed), report path (last review), summary; <out>/<name>/SKILL.md; stage result.md files and memory-trim.md in reviews.
Use: new or rewritten skill with named sources.
*/

// ---- shared block (generated from lib/block.js by bin/build.sh; never edit here) ----
// Shared script block. Source of truth: lib/block.src.js plus lib/classes.json; edit those only.
// bin/build.sh renders them into lib/block.js and stamps lib/block.js between the shared-block
// markers of every target named by lib/build-manifest.json. lib/block.js and every stamped copy
// are generated: a hand edit inside them is lost at the next build and fails `bin/build.sh --check`.
// Scripts cannot import, so every workflow carries a byte-identical copy of this block.
// Pure functions only: no file access, no harness global (`args`, `agent`, `log`), no side effect.

// ---- class table ----
const CLASSES = {
  "defaultClass": "c3",
  "slots": [
    "main",
    "opus",
    "sonnet"
  ],
  "models": {
    "fab": "fable",
    "ops": "opus",
    "son": "sonnet",
    "hai": "haiku"
  },
  "efforts": {
    "lo": "low",
    "me": "medium",
    "hi": "high"
  },
  "submodeOrder": [
    "no-sonnet",
    "no-opus",
    "no-fable"
  ],
  "submodeKeys": [
    "none",
    "no-sonnet",
    "no-opus",
    "no-fable",
    "no-sonnet no-opus",
    "no-sonnet no-fable",
    "no-opus no-fable"
  ],
  "table": {
    "c1": {
      "none": "ops-lo/ops-lo/son-lo",
      "no-sonnet": "ops-lo/ops-lo/ops-lo",
      "no-opus": "son-me/son-me/son-lo",
      "no-fable": "ops-lo/ops-lo/son-lo",
      "no-sonnet no-opus": "fab-lo/fab-lo/fab-lo",
      "no-sonnet no-fable": "ops-lo/ops-lo/ops-lo",
      "no-opus no-fable": "son-me/son-me/son-lo"
    },
    "c2": {
      "none": "fab-lo/ops-lo/son-me",
      "no-sonnet": "fab-lo/ops-lo/ops-lo",
      "no-opus": "fab-lo/son-me/son-me",
      "no-fable": "ops-me/ops-lo/son-me",
      "no-sonnet no-opus": "fab-lo/fab-lo/fab-lo",
      "no-sonnet no-fable": "ops-me/ops-lo/ops-lo",
      "no-opus no-fable": "son-me/son-me/son-me"
    },
    "c3": {
      "none": "fab-lo/ops-me/son-hi",
      "no-sonnet": "fab-lo/ops-me/ops-me",
      "no-opus": "fab-lo/son-hi/son-hi",
      "no-fable": "ops-me/ops-me/son-hi",
      "no-sonnet no-opus": "fab-lo/fab-lo/fab-lo",
      "no-sonnet no-fable": "ops-me/ops-me/ops-me",
      "no-opus no-fable": "son-hi/son-hi/son-hi"
    },
    "c4": {
      "none": "fab-me/ops-hi/son-hi",
      "no-sonnet": "fab-me/ops-hi/ops-me",
      "no-opus": "fab-me/fab-me/son-hi",
      "no-fable": "ops-hi/ops-hi/son-hi",
      "no-sonnet no-opus": "fab-me/fab-me/fab-lo",
      "no-sonnet no-fable": "ops-hi/ops-hi/ops-me",
      "no-opus no-fable": "son-hi/son-hi/son-hi"
    },
    "c5": {
      "none": "fab-hi/ops-hi/ops-hi",
      "no-sonnet": "fab-hi/ops-hi/ops-hi",
      "no-opus": "fab-hi/fab-me/fab-me",
      "no-fable": "ops-hi/ops-hi/ops-hi",
      "no-sonnet no-opus": "fab-hi/fab-me/fab-me",
      "no-sonnet no-fable": "ops-hi/ops-hi/ops-hi",
      "no-opus no-fable": "son-hi/son-hi/son-hi"
    }
  },
  "fixedCells": {
    "guide": {
      "none": "son-me",
      "no-sonnet": "ops-lo",
      "no-sonnet no-opus": "fab-lo"
    },
    "codex": {
      "none": "hai-me"
    }
  },
  "helpers": {
    "finder": {
      "agent": "session:finder",
      "slot": "sonnet",
      "gain": "cost"
    },
    "extractor": {
      "agent": "session:extractor",
      "slot": "sonnet",
      "gain": "cost"
    },
    "web-extractor": {
      "agent": "session:web-extractor",
      "slot": "sonnet",
      "gain": "cost"
    },
    "runner": {
      "agent": "session:runner",
      "slot": "sonnet",
      "gain": "cost"
    },
    "applier": {
      "agent": "session:applier",
      "slot": "sonnet",
      "gain": "cost"
    },
    "consumer": {
      "agent": "session:consumer",
      "slot": "sonnet",
      "gain": "quality"
    },
    "checker": {
      "agent": "session:checker",
      "slot": "opus",
      "gain": "quality"
    },
    "breaker": {
      "agent": "session:breaker",
      "slot": "opus",
      "gain": "quality"
    },
    "guide": {
      "agent": "claude-code-guide",
      "seat": "guide"
    },
    "codex": {
      "agent": "session:codex",
      "seat": "codex"
    }
  },
  "statuses": [
    "completed",
    "partial",
    "blocked",
    "failed"
  ]
}
// ---- end class table ----

const MODEL_NAME = CLASSES.models
const EFFORT_NAME = CLASSES.efforts

// submodes(list) -> { subs, key }: submodes in the table's order, the row key of the class table.
function submodes(list) {
  const given = list || []
  const bad = given.filter(s => !CLASSES.submodeOrder.includes(s))
  if (bad.length) throw new Error(`unknown submode ${bad.join(' ')}`)
  const subs = CLASSES.submodeOrder.filter(s => given.includes(s))
  if (subs.length === 3) throw new Error('all three submodes banned: nothing left to run on')
  return { subs, key: subs.join(' ') || 'none' }
}

// cellFor(class, submodes) -> { main, opus, sonnet }, each the short cell of the class table.
function cellFor(cls, subs) {
  const row = CLASSES.table[cls]
  if (!row) throw new Error(`unknown class ${cls}`)
  const parts = row[submodes(subs).key].split('/')
  return { main: parts[0], opus: parts[1], sonnet: parts[2] }
}

// seatCell(seat, submodes): the short cell of a fixed seat; the longest matching submode row wins,
// `none` when no submode row of the seat matches.
function seatCell(seat, subs) {
  const rows = CLASSES.fixedCells[seat]
  if (!rows) throw new Error(`unknown seat ${seat}`)
  const have = submodes(subs).subs
  const fits = Object.keys(rows).filter(k => k !== 'none' && k.split(' ').every(s => have.includes(s)))
  const best = fits.sort((a, b) => b.length - a.length)[0]
  return rows[best || 'none']
}

// cellOpts(short, job, extra) -> { model, effort, label, ...extra } for one agent() call. `extra`
// spreads first: a call site adds keys (agentType, phase) but never overrides the model, the effort
// or the label, which only the class table decides.
function cellOpts(short, job, extra) {
  const m = short.split('-')[0]
  const e = short.split('-')[1]
  if (!MODEL_NAME[m] || !EFFORT_NAME[e]) throw new Error(`unknown cell ${short}`)
  return { ...(extra || {}), model: MODEL_NAME[m], effort: EFFORT_NAME[e], label: `${short}-${job}` }
}

// helperOpts(class, submodes, helper, slot, job) -> { agentType, model, effort, label, slot, cell }.
// A helper with a fixed seat ignores `slot`. A helper with a default slot takes `slot` when given
// (the launcher's one-line reason stands in the ask), else its own.
function helperOpts(cls, subs, helper, slot, job) {
  const h = CLASSES.helpers[helper]
  if (!h) throw new Error(`unknown helper ${helper}`)
  let short, used
  if (h.seat) {
    short = seatCell(h.seat, subs); used = h.seat
  } else {
    used = slot || h.slot
    if (!CLASSES.slots.includes(used)) throw new Error(`unknown slot ${used}`)
    short = cellFor(cls, subs)[used]
  }
  return { ...cellOpts(short, job, { agentType: h.agent }), slot: used, cell: short }
}

// helperNames(): the helpers of the table, in its order.
function helperNames() {
  return Object.keys(CLASSES.helpers)
}

// handback(text) -> { status, report, summary, lines }: the three handback lines of a helper's
// return, wherever they stand in the text (last occurrence wins). A missing or unknown status is
// `failed` with the summary `malformed handback`, never a success: an unfinished job may not
// pass for a confirmed one. `report` is null when no line names one.
function handback(text) {
  const s = String(text == null ? '' : text)
  const pick = key => {
    const re = new RegExp(`^\\s*${key}:\\s*(.*?)\\s*$`, 'gm')
    let m, last = null
    while ((m = re.exec(s))) last = m[1]
    return last
  }
  const status = pick('status')
  const report = pick('report')
  const summary = pick('summary')
  const ok = status && CLASSES.statuses.includes(status)
  return {
    status: ok ? status : 'failed',
    report: report || null,
    summary: ok ? (summary || '') : `malformed handback: ${status ? `unknown status ${status}` : 'no status line'}`,
    lines: s.trim().split('\n').slice(-3).join('\n'),
  }
}

// normPath(p) -> p with repeated slashes collapsed and a trailing slash dropped: a model often
// passes `out` with a trailing slash, and a path compared as text must not fail on that.
function normPath(p) {
  if (p == null) return p
  const s = String(p).trim().replace(/\/{2,}/g, '/')
  return s.length > 1 ? s.replace(/\/$/, '') : s
}

// handbackAt(text, dir) -> handback(text), and `failed` when a non-failed return names a report
// other than <dir>/result.md: a script cannot read the disk, so the path is the one check it has
// that the report belongs to this launch and not to an earlier run.
function handbackAt(text, dir) {
  const h = handback(text)
  const want = `${normPath(dir)}/result.md`
  if (h.status !== 'failed' && normPath(h.report) !== want) {
    return { ...h, status: 'failed', summary: `report ${h.report || 'missing'} is not ${want}` }
  }
  return h
}

// isBlocked(text): a return that is null, or has a line that starts with BLOCKED:, or hands back
// `blocked`. A summary that quotes a blocked item further in its line blocks nothing.
function isBlocked(text) {
  if (text == null) return true
  return /^\s*BLOCKED:/m.test(String(text)) || handback(text).status === 'blocked'
}

// launchTail(helper, dir, skills) -> the prompt lines after the contract and the inputs, the skill
// line last. A helper whose agent is no plugin agent (the built-in guide) knows no result protocol,
// so the lines spell it out; a plugin agent carries it in its own body.
function launchTail(helper, dir, skills) {
  const h = CLASSES.helpers[helper]
  if (!h) throw new Error(`unknown helper ${helper}`)
  const list = skills || []
  if (list.some(p => !String(p).startsWith('/'))) throw new Error('skills holds a relative path')
  const lines = [`Result directory: ${dir} (mkdir -p it; write result.md there; logs and attempts beside it).`]
  if (!h.agent.startsWith('session:')) {
    lines.push(`Result protocol: if ${dir}/result.md already exists, stop and return status blocked with summary "result directory not fresh". Otherwise write ${dir}/result.md last, with Bash (a heredoc to a temp file beside it, then mv): first line "status: <completed | partial | blocked | failed>", then the answer, a source (doc URL or file path) per fact, and what stayed unchecked. completed means the contract was carried out, not that the answer is certain.`)
  }
  lines.push(`Return exactly the three handback lines: status, report (${dir}/result.md), summary. No other text.`)
  lines.push(list.length
    ? `Read these skill files with the Read tool before starting: ${list.join(' ')} (a missing file: status blocked, its path in the summary).`
    : 'No skills needed for this step.')
  return lines
}

// batchRows(items, returns, dirs) -> [{ item, status, report, summary }]: one row per item, in the
// item order; a null return (the agent died or was skipped) is a `failed` row, never a dropped one.
// With `dirs` (the result directory of each item) a row is checked by handbackAt.
function batchRows(items, returns, dirs) {
  return (items || []).map((item, i) => {
    const r = returns ? returns[i] : null
    if (r == null) return { item, status: 'failed', report: null, summary: 'no return' }
    const h = dirs ? handbackAt(r, dirs[i]) : handback(r)
    return { item, status: h.status, report: h.report, summary: h.summary }
  })
}

// batchCounts(rows) -> { completed, partial, blocked, failed, total }.
function batchCounts(rows) {
  const c = { total: (rows || []).length }
  for (const st of CLASSES.statuses) c[st] = 0
  for (const r of rows || []) if (c[r.status] != null) c[r.status]++
  return c
}

// cellTokens(line): the tokens of one line of prose that name a cell of the class table: a model
// name, the short code of a cell (`fab-me`), a reasoning-level word, or a frontmatter pin. The
// class table is the only source of what a launch runs on, so no text of this plugin names one of
// them, and tests/plugin/text.sh executes this function over every text file of the plugin instead
// of carrying a regex of its own. Two forms are no cell token: a slot name ("opus slot",
// "sonnet-slot") names a column of the table, a submode name ("no-sonnet") names one of its rows.
const LEVEL_WORDS = ['effort', 'tier']
const LEVEL_NOUNS = ['effort', 'tier', 'reasoning', 'thinking']
function cellTokens(line) {
  const s = String(line == null ? '' : line)
  const names = Object.values(MODEL_NAME).join('|')
  const mods = Object.keys(MODEL_NAME).join('|')
  const effs = Object.keys(EFFORT_NAME).join('|')
  const levels = Object.values(EFFORT_NAME).join('|')
  const nouns = LEVEL_NOUNS.join('|')
  const parts = [
    `(no-)?\\b(?:${names})\\b([- ]slot)?`,
    `\\b(?:${mods})-(?:${effs})\\b`,
    `\\b(?:${LEVEL_WORDS.join('|')})\\b`,
    `\\b(?:${levels})[- ]+(?:level[- ]+)?(?:${nouns})\\b`,
    `\\b(?:${nouns})(?:[- ]+level)?[- :]+(?:${levels})\\b`,
    `^\\s*(?:model|effort):\\s*\\S`,
  ]
  const re = new RegExp(parts.join('|'), 'gi')
  const out = []
  let m
  while ((m = re.exec(s))) {
    const t = m[0]
    if (/^no-/.test(t) || /[- ]slot$/.test(t)) continue
    out.push(t)
  }
  return out
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    CLASSES, MODEL_NAME, EFFORT_NAME, submodes, cellFor, seatCell, cellOpts, helperOpts, helperNames,
    handback, handbackAt, normPath, isBlocked, launchTail, batchRows, batchCounts, cellTokens,
  }
}
// ---- end shared block ----

const HOME = '/Users/aleksandr.antonov'
const A = args || {}
const CLS = A.class || CLASSES.defaultClass
const SUBS = submodes(A.submodes).subs
const CELL = cellFor(CLS, SUBS)
const SK = A.name
if (!SK) throw new Error('args.name (skill directory name) is required')
if (!A.purpose) throw new Error('args.purpose (one line) is required')
if (!A.sources || !A.sources.length) throw new Error('args.sources (array of absolute paths) is required')
const CAP = A.cap || 4000
const WORDS = Math.floor(CAP / 1.4)
const OUT = normPath(A.out || `${HOME}/.claude/skills`)
const REV = normPath(A.reviews || `${HOME}/.claude/reviews/skill-${SK}`)
const FILE = `${OUT}/${SK}/SKILL.md`
const SRC = A.sources.join('\n')
const ABS = A.absorbs || []
const NAME = [CLS, ...SUBS, 'skill-author'].join('-')
log(`${NAME} | name=${SK} sources=${A.sources.length} cap=${CAP} out=${OUT} reviews=${REV} absorbs=${ABS.length} cells=${CELL.main}/${CELL.opus}/${CELL.sonnet}`)

const STYLE = 'Plain English, caveman ultra; the return value is data. No skills needed for this step.'
// handoff(dir): the result protocol of every stage; stages pass each other result.md paths, never text
const handoff = dir => `Result directory: ${dir} (create it if missing; write result.md there and overwrite an older one; its first line is status: <the handback status>). Return exactly the three handback lines: status, report, summary. No other text. Permission denial or a missing input: status: blocked, the reason in the summary.`
// a reviewer's summary is "clean", "clean (<m> medium accepted)" or "findings <n> high <m> medium"
const isClean = h => h.status === 'completed' && /^\s*(VERDICT:\s*)?clean\b/i.test(h.summary)
const done = (stage, h, extra) => ({ class: CLS, submodes: SUBS, stage, status: h.status, report: h.report, summary: `${stage}: ${h.summary}`, file: FILE, reviews: REV, ...(extra || {}) })

phase('Author')
const draft = handbackAt(await agent(`Skill author. Write ${FILE} (create the directory if missing). Purpose: ${A.purpose}
Frontmatter: name: ${SK}; description of 10-30 tokens (7-21 words) naming the purpose and the trigger words. Body: strategy only, cap ${CAP} tokens (at most ${WORDS} words), every rule once, no reasons, no history, no examples over three lines.
Sources (absolute paths, read all in one pass):
${SRC}
result.md: the skill path, the body word count, the description token estimate. Summary: the body word count.
${handoff(`${REV}/author`)} ${STYLE}`, cellOpts(CELL.opus, 'author', { agentType: 'skill-author', phase: 'Author' })), `${REV}/author`)
if (draft.status !== 'completed') return done('author', draft)

const SEV = 'Severity: high = invented or wrong statement, or a rule the purpose requires that is missing; medium = duplicate, contradiction, rule that cannot be applied as written; low = wording.'
const reviewPrompt = (i, prev) => `${i === 1
  ? `Skill reviewer, round 1. Draft: ${FILE}. Cap: ${CAP} tokens. Purpose: ${A.purpose}
Sources (absolute paths):
${SRC}
${SEV} Never edit the draft or the sources.
result.md: the findings numbered under High / Medium / Low, each with draft line, source line and fix. Summary: exactly "clean" (no high and no medium) or "findings <n> high <m> medium".`
  : `Skill reviewer, round ${i}. Draft: ${FILE}. Previous review: ${prev}. Sources (absolute paths):
${SRC}
Re-check only the previous findings: mark each applied, not applied or regressed (the fix broke something). Then scan the edited passages for regressions only: a new contradiction, an invented statement, cap overflow (${CAP} tokens). Raise no other new finding unless it is high. ${SEV} Never edit the draft or the sources.
result.md: the re-check and the open findings. Summary: exactly "clean (<m> medium accepted)" when no high remains (unresolved medium and low are accepted, not counted) or "findings <n> high <m> medium".`}
${handoff(`${REV}/review-${i}`)} ${STYLE}`
const fixPrompt = (i, review) => `Skill author, fix round ${i}. Apply every open finding (not applied, regressed, new) of the review ${review} to ${FILE} in place; keep the cap of ${CAP} tokens (at most ${WORDS} body words) and the 10-30 token description. Sources for reference:
${SRC}
result.md: the findings applied, the findings not applied with the reason, the body word count. Summary: applied count and body word count.
${handoff(`${REV}/fix-${i}`)} ${STYLE}`

// review, fix, review: up to three reviews; stops on clean, on a stage that did not complete, or after round 3
let review = null
for (let i = 1; i <= 3; i++) {
  review = handbackAt(await agent(reviewPrompt(i, review && review.report), cellOpts(CELL.main, `review-${i}`, { agentType: 'skill-reviewer', phase: 'Author' })), `${REV}/review-${i}`)
  if (review.status !== 'completed') return done(`review-${i}`, review)
  if (isClean(review)) { review.round = i; break }
  if (i === 3) { review.round = i; break }
  const fix = handbackAt(await agent(fixPrompt(i, review.report), cellOpts(CELL.opus, `fix-${i}`, { agentType: 'skill-author', phase: 'Author' })), `${REV}/fix-${i}`)
  if (fix.status !== 'completed') return done(`fix-${i}`, fix, { review: review.report })
}
const clean = isClean(review)

let trim = null
if (ABS.length) {
  phase('Trim list')
  const t = handbackAt(await agent(`Memory trim list. Skill: ${FILE}. Absorbed memory candidates (absolute paths, read all in one pass):
${ABS.join('\n')}
For each file decide: DELETE (every fact now lives in the skill), SHORTEN (some facts absorbed; list the lines to keep, at most 3), KEEP (nothing absorbed or the file carries a why that a skill must not carry). Write ${REV}/memory-trim.md: one line per file "<verdict> <path> | <kept lines or reason>", then a line "skill: ${FILE}". Never edit the memory files.
result.md: the path of memory-trim.md and the counts per verdict. Summary: the counts per verdict.
${handoff(`${REV}/trim-list`)} ${STYLE}`, cellOpts(CELL.opus, 'trim-list', { agentType: 'skill-author', phase: 'Trim list' })), `${REV}/trim-list`)
  trim = { status: t.status, report: t.report, list: t.status === 'completed' ? `${REV}/memory-trim.md` : null, summary: t.summary }
}

const trimOk = !trim || trim.status === 'completed'
return {
  class: CLS, submodes: SUBS, status: clean && trimOk ? 'completed' : 'partial', report: review.report,
  summary: `${clean ? 'clean' : 'not clean'} after review ${review.round}: ${review.summary}${trim ? `; trim list: ${trim.status} ${trim.summary}` : ''}`,
  file: FILE, reviews: REV, trim,
  next: trim && trim.list ? `Check ${FILE}; then memory-gc with trim ${trim.list}.` : `Check ${FILE}.`,
}
