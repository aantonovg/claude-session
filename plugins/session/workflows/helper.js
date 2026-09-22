export const meta = {
  name: 'helper',
  description: 'One fresh helper',
  whenToUse: 'A fork or the main session needs one concrete result from a fresh context: an index, facts, a run, a counterexample, a narrow check, a replicated change. The contract is short; the result goes to a file; three lines come back.',
  phases: [{ title: 'Helper' }],
}
/* usage:
One fresh helper, one contract, one result directory.
helper (required): finder extractor web-extractor runner applier consumer checker breaker guide codex
ask (the contract: goal, object, constraints, expected result; required)
in (absolute paths array, default [])
out (absolute result directory, required)
slot (main opus sonnet; default the helper's own; reason in ask)
codex (codex target like sol-medium: the codex helper runs the same contract in parallel; default none)
cwd (directory of the codex run, default none)
class (c1-c5, default c3)
submodes (array: no-sonnet no-opus no-fable, default [])
Out: status (completed partial blocked failed), report path, summary; with codex a second triple.
Use: one result before the fork decides. Not: authoring, intent, a review of tested code.
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

// isBlocked(text): a return that is null, or carries BLOCKED: anywhere, or hands back `blocked`.
function isBlocked(text) {
  if (text == null) return true
  return /BLOCKED:/.test(String(text)) || handback(text).status === 'blocked'
}

// batchRows(items, returns) -> [{ item, status, report, summary }]: one row per item, in the item
// order; a null return (the agent died or was skipped) is a `failed` row, never a dropped one.
function batchRows(items, returns) {
  return (items || []).map((item, i) => {
    const r = returns ? returns[i] : null
    if (r == null) return { item, status: 'failed', report: null, summary: 'no return' }
    const h = handback(r)
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
    handback, isBlocked, batchRows, batchCounts, cellTokens,
  }
}
// ---- end shared block ----

const A = args || {}
const CLS = A.class || CLASSES.defaultClass
const SUBS = submodes(A.submodes).subs
const HELPER = A.helper
const ASK = A.ask
const OUT = A.out
const IN = Array.isArray(A.in) ? A.in : (A.in ? [A.in] : [])
if (!HELPER) throw new Error('args.helper is required')
if (!ASK) throw new Error('args.ask is required')
if (!OUT || !String(OUT).startsWith('/')) throw new Error('args.out (absolute result directory) is required')
if (IN.some(p => !String(p).startsWith('/'))) throw new Error('args.in holds a relative path')

const O = helperOpts(CLS, SUBS, HELPER, A.slot, HELPER)
log(`c${CLS.slice(1)}${SUBS.length ? '-' + SUBS.join('-') : ''}-helper | helper=${HELPER} cell=${O.cell} slot=${O.slot} out=${OUT}`)

const prompt = [
  `Contract:`,
  ASK,
  IN.length ? `Inputs (absolute paths): ${IN.join(' ')}` : 'Inputs: none beyond the contract.',
  `Result directory: ${OUT} (mkdir -p it; write result.md there; logs and attempts beside it).`,
  `Return exactly the three handback lines: status, report, summary. No other text.`,
].join('\n')

const codexPrompt = (target, cwd, dir) => [
  `CODEX TARGET: ${target}`,
  cwd ? `CODEX CWD: ${cwd}` : null,
  `CODEX OUTPUT FILE: ${dir}/output.md`,
  `CODEX LABEL: ${O.label}-codex`,
  `RESULT DIR: ${dir}`,
  `CODEX ASK:`,
  `Style: caveman ultra, plain English only; artifacts in normal prose.`,
  `Contract: ${ASK}`,
  IN.length ? `Inputs (absolute paths): ${IN.join(' ')}` : 'Inputs: none beyond the contract.',
  `Write the result to ${dir}/output.md: what was asked, what was observed, the evidence with paths and lines, the exceptions, what stayed unchecked. Last line of the file: status: completed | partial | failed.`,
].filter(Boolean).join('\n')

phase('Helper')
const runs = [() => agent(prompt, { agentType: O.agentType, model: O.model, effort: O.effort, label: O.label, phase: 'Helper' })]
if (A.codex && HELPER !== 'codex') {
  const C = helperOpts(CLS, SUBS, 'codex', null, `${HELPER}-codex`)
  runs.push(() => agent(codexPrompt(A.codex, A.cwd, `${OUT}/codex`), { agentType: C.agentType, model: C.model, effort: C.effort, label: C.label, phase: 'Helper' }))
}
const returns = await parallel(runs)
const h = handback(returns[0])
const out = { helper: HELPER, cell: O.cell, slot: O.slot, label: O.label, out: OUT, status: h.status, report: h.report, summary: h.summary }
if (runs.length > 1) { const c = handback(returns[1]); out.codex = { target: A.codex, status: c.status, report: c.report, summary: c.summary } }
return out
