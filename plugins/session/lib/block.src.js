// Shared script block. Source of truth: lib/block.src.js plus lib/classes.json; edit those only.
// bin/build.sh renders them into lib/block.js and stamps lib/block.js between the shared-block
// markers of every target named by lib/build-manifest.json. lib/block.js and every stamped copy
// are generated: a hand edit inside them is lost at the next build and fails `bin/build.sh --check`.
// Scripts cannot import, so every workflow carries a byte-identical copy of this block.
// Pure functions only: no file access, no harness global (`args`, `agent`, `log`), no side effect.

// ---- class table ----
const CLASSES = {} // generated from lib/classes.json by bin/build.sh
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

// optsFor(class, submodes, slot, job) -> { model, effort, label } for one agent() call.
function optsFor(cls, subs, slot, job, extra) {
  const cell = cellFor(cls, subs)
  if (!Object.prototype.hasOwnProperty.call(cell, slot)) throw new Error(`unknown slot ${slot}`)
  const short = cell[slot]
  const m = short.split('-')[0]
  const e = short.split('-')[1]
  // `extra` spreads first: a call site adds keys (agentType, tools) but never overrides the model,
  // the effort or the label, which only the class table decides.
  return { ...(extra || {}), model: MODEL_NAME[m], effort: EFFORT_NAME[e], label: `${short}-${job}` }
}

// classUp(class): the one class step of 3.5 rule 2 and rule 3; the top class steps to itself.
function classUp(cls) {
  const next = CLASSES.classStep[cls]
  if (!next) throw new Error(`unknown class ${cls}`)
  return next
}

// slotForSize(slot, size): a large input moves a role one slot down, never up, never past the
// cheapest slot (A32; the launcher states the volume, a script cannot measure its inputs).
function slotForSize(slot, size) {
  if (!CLASSES.slots.includes(slot)) throw new Error(`unknown slot ${slot}`)
  const s = size || CLASSES.defaultSize
  if (!CLASSES.sizes.includes(s)) throw new Error(`unknown size ${s}`)
  return s === 'large' ? CLASSES.slotDown[slot] : slot
}

// bindClass(class, submodes): the class of one run; every stage asks it for its agent options.
function bindClass(cls, subs) {
  const s = submodes(subs)
  const cell = cellFor(cls, s.subs)
  return {
    class: cls,
    submodes: s.subs,
    cell,
    name: stem => [cls, ...s.subs, stem].join('-'),
    opts: (slot, job, extra) => optsFor(cls, s.subs, slot, job, extra),
    up: () => bindClass(classUp(cls), s.subs),
  }
}

// roleOf / roleAgent / roleSlot / roleClass: the per-role slot map of lib/classes.json.
function roleOf(name) {
  const r = CLASSES.roles[name]
  if (!r) throw new Error(`unknown role ${name}`)
  return r
}
function roleNames() { return Object.keys(CLASSES.roles) }
function roleAgent(name) { return roleOf(name).agent }
function roleSlot(name, size, split) {
  const r = roleOf(name)
  return slotForSize(split && r.splitSlot ? r.splitSlot : r.slot, size)
}
// roleClass(role, class): an output no oracle can check gets a stronger author, one class step up.
function roleClass(name, cls) { return roleOf(name).uplift ? classUp(cls) : cls }

// ceiling(depth) -> { agents, cycles } (A30); ceilingHit is true when `used` units reach the
// ceiling, so the next unit may not start: the stage ends and writes the gap.
function ceiling(depth) {
  const c = CLASSES.ceilings[depth]
  if (!c) throw new Error(`unknown depth ${depth}`)
  return c
}
function ceilingHit(depth, kind, used) {
  const c = ceiling(depth)
  if (!Object.prototype.hasOwnProperty.call(c, kind)) throw new Error(`unknown ceiling ${kind}`)
  const n = Number(used)
  // a NaN would compare false and let the ceiling pass unnoticed: a bad counter is an error.
  if (!Number.isFinite(n)) throw new Error(`ceilingHit needs a number of ${kind}, got ${used}`)
  return n >= c[kind]
}

// isBlocked / lastLine: the return shape every tool-set agent keeps. Every agent file puts the
// blocked word on the LAST line, so only that line counts: a return quoting the word mid-text
// (a finding, a file path, an error string) is a normal return, not a blocked stage.
function lastLine(ret) { return String(ret == null ? '' : ret).trim().split('\n').pop() }
function isBlocked(ret) { return ret == null || /^BLOCKED:/.test(lastLine(ret).trim()) }

// blockedLine(why): the blocked value of a stage, carrying the block word exactly once. Reasons
// come from two sources: an agent return that already opens with the word, and a reason this block
// wrote itself; prefixing both would print the word twice.
function blockedLine(why) {
  const w = String(why == null ? '' : why).trim() || 'no reason'
  return /^BLOCKED:/.test(w) ? w : `BLOCKED: ${w}`
}

// mustExist(ret, out): the output check of every stage that names an output file. A workflow
// script has no file access, so the agent's own return is the evidence: it names the path it
// wrote. Returns { ok, out, reason }; a false ok stops the flow instead of feeding the next stage.
function mustExist(ret, out) {
  if (!out) throw new Error('mustExist needs the output path')
  const s = String(ret == null ? '' : ret)
  // the agent's own last line is the reason, unprefixed here: blockedLine puts the word on once
  if (isBlocked(ret)) return { ok: false, out, reason: lastLine(s) || 'no return' }
  if (s.indexOf(out) === -1) return { ok: false, out, reason: `return does not name ${out}` }
  return { ok: true, out }
}

// outVerdict(ret, out): the whole verdict of a stage that names an output file — mustExist plus
// the size the agent reports. A script has no file access, so that number is the only evidence the
// file is not empty: a missing or zero count is an empty output, and an empty output is blocked,
// never done. The count counts only on a line naming the output path, and only on the FIRST such
// line, the demanded one: a later line naming the path with a byte count (a quoted run log, a
// check output, another file) must not decide the stage.
function outVerdict(ret, out) {
  const m = mustExist(ret, out)
  if (!m.ok) return { ok: false, out, bytes: 0, reason: m.reason, blocked: blockedLine(m.reason) }
  const RE = /(\d[\d,]*) *bytes\b/
  const line = String(ret).split('\n').filter(l => l.indexOf(out) !== -1 && RE.test(l))[0] || ''
  const n = Number(((line.match(RE) || [])[1] || '').replace(/,/g, ''))
  if (!(n > 0)) {
    const why = `return reports no non-empty ${out}: no positive byte count on a line naming it`
    return { ok: false, out, bytes: 0, reason: why, blocked: blockedLine(why) }
  }
  return { ok: true, out, bytes: n }
}

// ---- the review chain of idea 3.6 ----
// Every decision of the chain lives here as a pure function over the returns of its stages, so a
// test executes it instead of grepping workflows/chain.js. A workflow script has no file access:
// the hint lists and the evidence answers reach the script only as lines of an agent return, which
// is why the two parsers below are part of the chain and not of the prompt.

const HINT_CAP = 5 // A27: at most 5 hints per critic, so N critics give at most 5 x N hints
const SEVERITY_ORDER = ['low', 'medium', 'high']
const EVIDENCE_VERDICTS = ['confirmed', 'refuted', 'undetermined', 'harness']

// keyedFields(text, tag, width): the lines of an agent return that carry one keyed answer, split
// into their fields. A real return decorates its answers the way an agent writes everything else:
// a list marker, a blockquote or a heading before the tag, backticks or bold around the tag, a
// lowercase tag, a colon or a dash where the first `|` belongs, prose lines before and after, and
// a long answer wrapped onto a second line. None of that changes the answer, so it is stripped.
// Nothing else is guessed: a line without the tag is prose and binds nothing, and a field that is
// absent stays absent — which every caller below reads as "settled by nobody".
// `width` is how many fields a whole answer has; only a row still short of that many takes the
// next prose line as its continuation, so a finished answer is never extended by the text after
// it. A wrap inside the last field of a whole row is therefore cut at the wrap: the role texts
// ask for one line per answer, and swallowing the prose after a complete row would be worse.
const LEAD = /^[ \t]*(?:[-*+>][ \t]+|#{1,6}[ \t]+|\d+[.)][ \t]+)*/
const TAG_DECOR = '[`*_]*'
const WORD_DECOR = /^[`*_"']+|[`*_"'.,;]+$/g
// word(s): a short field — an id, a verdict, a severity, the control-run flag — with its
// decoration removed. The prose fields keep theirs: only the keys the flow reads are normalised.
const word = s => String(s == null ? '' : s).trim().replace(WORD_DECOR, '').trim()
function keyedFields(text, tag, width) {
  const head = new RegExp(`^${TAG_DECOR}${tag}${TAG_DECOR}[ \\t]*[|:\\u2013\\u2014-][ \\t]*`, 'i')
  const n = Number(width || 0)
  const rows = []
  for (const line of String(text == null ? '' : text).split('\n')) {
    const s = String(line).replace(LEAD, '').trim()
    if (!s) continue
    if (head.test(s)) { rows.push(s.replace(head, '').split('|').map(x => x.trim())); continue }
    const last = rows[rows.length - 1]
    if (!last || last.length >= n) continue
    const add = s.split('|').map(x => x.trim())
    last[last.length - 1] = `${last[last.length - 1]} ${add[0]}`.trim()
    for (const x of add.slice(1)) last.push(x)
  }
  return rows
}

// placeOf(place): "file:12-30", "file:12" or "doc.md#Section"; anything else is the whole file.
function placeOf(place) {
  const s = String(place == null ? '' : place).trim()
  const hash = s.indexOf('#')
  if (hash !== -1) {
    return { file: s.slice(0, hash).trim(), section: s.slice(hash + 1).trim(), from: null, to: null }
  }
  const m = s.match(/^(.*?):(\d+)(?:\s*-\s*(\d+))?$/)
  if (m) return { file: m[1].trim(), section: null, from: Number(m[2]), to: Number(m[3] || m[2]) }
  return { file: s, section: null, from: null, to: null }
}

// placeText(p): the place of a group, written back in the form the critics use.
function placeText(p) {
  if (p.section) return `${p.file}#${p.section}`
  if (p.from == null) return p.file
  return `${p.file}:${p.from}-${p.to}`
}

// parseHints(text, aspect): the hint lines of one critic return. Format, one line per hint:
//   HINT | <aspect> | <place> | <severity> | <suspected error> | <evidence that would settle it>
// Everything else in the return is prose and is ignored; a hint with no place could not be
// grouped and could not be settled, so it is no hint. The decoration a real critic writes around
// such a line is read through keyedFields().
function parseHints(text, aspect) {
  const hints = []
  for (const f of keyedFields(text, 'HINT', 5)) {
    const place = word(f[1] || '')
    if (!place) continue
    const sev = word(f[2] || '').toLowerCase()
    hints.push({
      aspect: word(f[0] || '') || aspect || '',
      place,
      ...placeOf(place),
      // an unreadable severity counts as medium: it must not silently become the highest one and
      // pull the whole run into the long form
      severity: SEVERITY_ORDER.includes(sev) ? sev : 'medium',
      what: f[3] || '',
      evidence: f.slice(4).join(' | '),
    })
  }
  return hints
}

// capHints(hints, cap): the cap of A27, applied per critic. The critic writes the strongest first,
// so the cap keeps the head of its list.
function capHints(hintList, cap) {
  const n = Number(cap == null ? HINT_CAP : cap)
  if (!Number.isFinite(n) || n < 1) throw new Error(`capHints needs a positive cap, got ${cap}`)
  const hints = hintList || []
  return hints.slice(0, n)
}

// hintsOverlap(a, b): same place. Two line ranges overlap when they intersect; a hint on a whole
// file covers every hint in that file; a document section meets only the same section.
function hintsOverlap(a, b) {
  if (a.file !== b.file) return false
  if (a.section || b.section) return a.section === b.section
  if (a.from == null || b.from == null) return true
  return a.from <= b.to && b.from <= a.to
}

function higher(x, y) {
  return SEVERITY_ORDER.indexOf(x) >= SEVERITY_ORDER.indexOf(y) ? x : y
}

function joinInto(g, h) {
  g.from = g.from == null || h.from == null ? null : Math.min(g.from, h.from)
  g.to = g.from == null || h.to == null ? null : Math.max(g.to, h.to)
  g.severity = higher(g.severity, h.severity)
  for (const a of h.aspects || [h.aspect]) if (a && !g.aspects.includes(a)) g.aspects.push(a)
  g.hints = g.hints.concat(h.hints || [h])
  g.place = placeText(g)
  return g
}

// groupHints(hints): the merge and dedupe of 3.6, in the script and with no extra agent. Hints on
// the same or overlapping place form one group that keeps all its aspect tags and the highest
// severity of its members, so two critics pointing at the same lines cost one evidence run, not
// two. Same-meaning hints on different places stay separate.
function groupHints(hints) {
  const groups = []
  for (const h of hints || []) {
    const hit = groups.filter(g => hintsOverlap(g, h))
    if (!hit.length) {
      groups.push({
        file: h.file, section: h.section, from: h.from, to: h.to, place: h.place,
        severity: h.severity, aspects: h.aspect ? [h.aspect] : [], hints: [h],
      })
      continue
    }
    const g = joinInto(hit[0], h)
    // a later hint can bridge two groups that did not meet before: they become one
    for (const other of hit.slice(1)) {
      joinInto(g, other)
      groups.splice(groups.indexOf(other), 1)
    }
  }
  // every hint carries an id of its own inside its group (`g1.h2`). A group is one evidence run,
  // but the answers are per hint: a group holding a confirmed hint and a refuted one must not
  // carry the refuted one to the fixer under the group's verdict (A28).
  return groups.map((g, i) => {
    const id = `g${i + 1}`
    return {
      ...g, aspects: g.aspects.slice().sort(), id,
      hints: (g.hints || []).map((h, j) => ({ ...h, id: `${id}.h${j + 1}` })),
    }
  })
}

// maxSeverity(groups): the severity of the whole critique, the second input of the form choice.
function maxSeverity(groups) {
  let top = null
  for (const g of groups || []) top = top == null ? g.severity : higher(top, g.severity)
  return top
}

// chainForm(depth, maxSeverity): idea decision 5. The long form (one evidence researcher per
// group, then a separate triage) for `full` and for any hint group of high severity; the short
// form (one agent that collects and decides in one pass) otherwise.
function chainForm(depth, sev) {
  if (!CLASSES.ceilings[depth]) throw new Error(`unknown depth ${depth}`)
  return depth === 'full' || sev === 'high' ? 'long' : 'short'
}

// pickAspects(names, catalog): the `aspects` argument against the static catalog. It selects
// paragraphs and carries no prompt text; an unknown name is returned to the launcher, and the
// workflow stops instead of running a critic with no aspect paragraph.
function pickAspects(names, catalog) {
  const known = Array.isArray(catalog) ? catalog.slice() : Object.keys(catalog || {})
  const given = (names || []).slice()
  return { names: given, unknown: given.filter(n => !known.includes(n)), known }
}

// criticSplit(depth, names): one merged critic at `lite` and whenever a single aspect is asked
// for; one critic per aspect above that (3.6, A5). The split also decides the slot: a split
// critic sits one slot down, through roleSlot(name, size, split).
function criticSplit(depth, names) {
  if (!CLASSES.ceilings[depth]) throw new Error(`unknown depth ${depth}`)
  const list = (names || []).slice()
  if (depth === 'lite' || list.length < 2) return [list]
  return list.map(n => [n])
}

// parseEvidence(text): the answer lines of an evidence stage. Format, one line per hint group:
//   EVIDENCE | <group id> | confirmed|refuted|undetermined|harness | base:yes|base:no | <pointer>
// An unreadable verdict counts as undetermined: it then goes to the user and never to the fixer.
function parseEvidence(text) {
  const answers = []
  for (const f of keyedFields(text, 'EVIDENCE', 4)) {
    // the id of an answer is a hint id (`g1.h2`); the group it belongs to is its head
    const id = word(f[0] || '')
    if (!id) continue
    const group = id.split('.')[0]
    const v = word(f[1] || '').toLowerCase()
    let verdict = EVIDENCE_VERDICTS.includes(v) ? v : 'undetermined'
    const base = word(f[2] || '')
    // a missing or unreadable control-run field settles nothing: reading it as `base:no` would
    // turn an answer nobody controlled into a finding of this change. It goes to the user, the
    // same way an unreadable verdict does. A harness failure needs no control run.
    if (verdict !== 'harness' && !/^base:\s*(yes|no)$/i.test(base)) verdict = 'undetermined'
    answers.push({
      id,
      group,
      verdict,
      kind: verdict === 'harness' ? 'harness' : 'object',
      onBase: /^base:\s*yes$/i.test(base),
      pointer: f.slice(3).join(' | '),
    })
  }
  return answers
}

// splitFailures(answers): the two rules of 3.6 that keep a finding honest. A failure of our own
// harness (tool, access, sandbox) is no finding about the object and is kept in its own list; a
// failure that also reproduces on the base version is no finding of this change either.
// Only a settled answer can be closed by the control run: an `undetermined` row with `base:yes`
// was settled by nobody, so it stays among the findings, reaches the undetermined list and the
// user (A28), and is never closed as "no finding of this change".
// dedupeAnswers(answers): one answer per hint. A stage that wrote two lines for one hint would
// otherwise put that hint in two lists at once — confirmed to the fixer and undetermined to
// the user. The stronger evidence wins: a settled verdict beats an unsettled one and beats a
// failure of our own harness; two settled verdicts that contradict each other (confirmed and
// refuted) settle nothing, so the hint goes to the user as undetermined.
const ANSWER_RANK = ['harness', 'undetermined', 'refuted', 'confirmed']
function dedupeAnswers(answers) {
  const out = []
  for (const a of answers || []) {
    const cur = out.filter(x => x.id === a.id)[0]
    if (!cur) { out.push({ ...a }); continue }
    const settled = v => v === 'confirmed' || v === 'refuted'
    const i = out.indexOf(cur)
    if (settled(cur.verdict) && settled(a.verdict) && cur.verdict !== a.verdict) {
      out[i] = { ...cur, verdict: 'undetermined', kind: 'object', pointer: `${cur.pointer} ;; ${a.pointer}` }
    } else if (ANSWER_RANK.indexOf(a.verdict) > ANSWER_RANK.indexOf(cur.verdict)) {
      out[i] = { ...a }
    }
  }
  return out
}

function splitFailures(answers) {
  const all = dedupeAnswers(answers)
  const harness = all.filter(a => a.kind === 'harness')
  const rest = all.filter(a => a.kind !== 'harness')
  const closed = a => a.onBase && a.verdict !== 'undetermined'
  const onBase = rest.filter(a => closed(a))
  const findings = rest.filter(a => !closed(a))
  return { findings, harness, onBase }
}

// hintRows(groups, answers): every hint of every group that ran, bound to the answer that settled
// it. The binding lives here and nowhere else, so the fixer's mandate, the review file and the
// return read the same rows and can no longer tell two different stories (A28).
// An answer names a hint id (`g1.h2`). A group of one hint is that hint, so an answer naming the
// group settles it; a group of several hints is not — one verdict over several hints would carry
// the refuted and the unsettled hints to the fixer under the confirmed one. A hint no answer
// names is unanswered: nothing settled it, so it is undetermined, never confirmed.
function hintRows(groups, answers) {
  const all = dedupeAnswers(answers)
  const kindOf = a => a.kind === 'harness'
    ? 'harness'
    : (a.onBase && a.verdict !== 'undetermined' ? 'onBase' : 'finding')
  const rows = []
  for (const g of groups || []) {
    const hints = (g.hints || []).length ? g.hints : [{ id: g.id, place: g.place, what: '' }]
    for (const h of hints) {
      const byHint = all.filter(x => x.id === h.id)[0]
      const byGroup = hints.length === 1 ? all.filter(x => x.id === g.id)[0] : null
      const a = byHint || byGroup || null
      rows.push({
        id: h.id, group: g.id, place: h.place || g.place, what: h.what || '',
        answered: !!a, verdict: a ? a.verdict : 'undetermined',
        kind: a ? kindOf(a) : 'finding', pointer: a ? a.pointer : '',
      })
    }
  }
  return rows
}

// chainRows(groups, answers): the one table of a chain run. The result file the judge writes and
// the return the caller reads are both this table — the open rows above all (A28), so a run can
// no longer return `undetermined: []` while its review file holds unsettled rows.
function chainRows(groups, answers) {
  const rows = hintRows(groups, answers)
  const findings = rows.filter(r => r.kind === 'finding')
  const undetermined = findings.filter(r => r.answered && r.verdict === 'undetermined')
  const unanswered = findings.filter(r => !r.answered)
  return {
    rows,
    findings,
    confirmed: findings.filter(r => r.verdict === 'confirmed'),
    rejected: findings.filter(r => r.verdict === 'refuted'),
    undetermined,
    unanswered,
    open: undetermined.concat(unanswered),
    harness: rows.filter(r => r.kind === 'harness'),
    onBase: rows.filter(r => r.kind === 'onBase'),
  }
}

// openRowsText(rows): the unsettled section of the review file, rendered from the rows the return
// carries. The judge copies this block instead of composing a list of its own.
function openRowsText(rows) {
  const open = (rows && rows.open) || []
  if (!open.length) return '(none)'
  return open.map(r => `| ${r.id} | ${r.place} | ${r.answered ? r.pointer || 'the facts settle nothing' : 'the evidence run came back with no readable answer for this hint'} |`).join('\n')
}

// fixerInput(groups, answers): what may reach the one who changes the object. A hint without
// evidence changes nothing, so a group goes on with its confirmed hints only; refuted,
// undetermined, harness, base-version and unanswered hints all stay out (A28).
function fixerInput(groups, answers) {
  const ok = chainRows(groups, answers).confirmed.map(r => r.id)
  const out = []
  for (const g of groups || []) {
    const hints = (g.hints || []).filter(h => ok.includes(h.id))
    if (hints.length) { out.push({ ...g, hints }); continue }
    // a group that carries no hint list of its own is addressed by its group id
    if (!(g.hints || []).length && ok.includes(g.id)) out.push(g)
  }
  return out
}

// confirmedOf(groups, answers): the hints a fact confirmed. The `confirmed` count of the result
// and of the status is this one, never the count that reached the fixer: a run whose triage or fix
// stage blocked still confirmed what it confirmed, and a judge that rejected a confirmed hint does
// not unmake the fact (A28). What the fixer got is its own number.
function confirmedOf(groups, answers) {
  return chainRows(groups, answers).confirmed
}

// undeterminedOf(groups, answers): the list that goes into the result file and into the status,
// for the main session to put to the user (A28: a script has no place for the user).
function undeterminedOf(groups, answers) {
  return chainRows(groups, answers).undetermined
}

// unansweredOf(groups, answers): a hint that ran and came back with no readable answer line.
// Nothing settled it, so it is neither confirmed nor rejected: it goes to the user with the
// undetermined ones (A28). Counting it out of existence would drop a whole hint.
function unansweredOf(groups, answers) {
  return chainRows(groups, answers).unanswered
}

// parseAccepted(text): the accepted rows of the judge's return. Format, one line per row:
//   ACCEPTED | <hint id> | <the change in one sentence>
// The whole decision stands in the judge's result file; these lines are the part a script without
// file access can read, and they are the only mandate the fixer gets.
function parseAccepted(text) {
  const rows = []
  for (const f of keyedFields(text, 'ACCEPTED', 2)) {
    const id = word(f[0] || '')
    if (!id) continue
    rows.push({ id, group: id.split('.')[0], change: f.slice(1).join(' | ') })
  }
  return rows
}

// judgedInput(groups, answers, rows): the fixer's mandate in the long form. The judge decides
// which hints become changes, so a hint it rejected or left unsettled never reaches the fixer;
// it cannot widen the mandate either, so a row no fact confirmed stays out (A28). No accepted
// row, no fix stage.
function judgedInput(groups, answers, rows) {
  const ids = (rows || []).map(r => r.id)
  const out = []
  for (const g of fixerInput(groups, answers)) {
    const hints = (g.hints || []).filter(h => ids.includes(h.id))
    if (hints.length) { out.push({ ...g, hints }); continue }
    if (!(g.hints || []).length && ids.includes(g.id)) out.push(g)
  }
  return out
}

// chainSeats(depth, wanted): the ceiling of A30 is a ceiling per stage — at most `agents` units
// in one stage. What does not fit never starts: the stage ends and the rest becomes the gap of
// the result, never a second round. `seats` is what starts, `gap` what never does: a caller needs
// no third number, so none is returned.
function chainSeats(depth, wanted) {
  const room = ceiling(depth).agents
  const n = Number(wanted)
  if (!Number.isFinite(n) || n < 0) throw new Error(`chainSeats needs a unit count, got ${wanted}`)
  const seats = Math.min(n, room)
  return { room, seats, gap: n - seats }
}

// aspectsOrStop(names, catalog): the gate of the `aspects` argument. An unknown name selects no
// paragraph, so the critic would run with no question at all: the run stops and the catalog goes
// back to the launcher (3.6). An empty list is no review either.
function aspectsOrStop(names, catalog) {
  const p = pickAspects(names, catalog)
  if (!p.names.length) {
    return { ok: false, known: p.known, why: blockedLine('args.aspects must name at least one catalog aspect') }
  }
  if (p.unknown.length) {
    return { ok: false, known: p.known, why: blockedLine(`unknown aspect ${p.unknown.join(' ')}`) }
  }
  return { ok: true, known: p.known, names: p.names, why: null }
}

// chainPlan(depth, names, catalog): the whole plan of the critic stage as one decision — the gate
// of the `aspects` argument, the split into critic sets (A5) and the ceiling of A30 over them.
// `ok:false` stops the run before any agent starts and hands `why` and the catalog back to the
// launcher; `sets` are the critics that start, `gap` the ones the ceiling left out (never a second
// round), and `split` is the slot flag: a split critic sits one slot down.
function chainPlan(depth, names, catalog) {
  const gate = aspectsOrStop(names, catalog)
  if (!gate.ok) return { ok: false, known: gate.known, why: gate.why, sets: [], gap: [], room: 0, split: false }
  const all = criticSplit(depth, gate.names)
  const seats = chainSeats(depth, all.length)
  return {
    ok: true, known: gate.known, why: null,
    sets: all.slice(0, seats.seats), gap: all.slice(seats.seats),
    room: seats.room, split: all.length > 1,
  }
}

// chainEvidenceRuns(depth, form, groups): the groups the evidence stage really starts, the highest
// severity first, and the groups the ceiling of A30 left as the gap. The short form is one agent
// for every group, so it cuts nothing; the long form is one agent per group and takes the seats.
function chainEvidenceRuns(depth, form, groups) {
  const ordered = (groups || []).slice()
    .sort((a, b) => SEVERITY_ORDER.indexOf(b.severity) - SEVERITY_ORDER.indexOf(a.severity))
  if (form !== 'long') return { room: ceiling(depth).agents, ran: ordered, gap: [] }
  const seats = chainSeats(depth, ordered.length)
  return { room: seats.room, ran: ordered.slice(0, seats.seats), gap: ordered.slice(seats.seats) }
}

// chainStatus(s): the status sentence of one chain run, the one place that states the A28
// contract — the open rows go to the user, and the chain ran one round.
function chainStatus(s) {
  const o = s || {}
  const open = Number(o.undetermined || 0) + Number(o.unanswered || 0)
  const where = o.out || 'the result file'
  const openText = open
    ? `The ${open} open row(s) stand in ${where} and in this return: put them to the user, one decision each, before anything else is changed.`
    : 'Nothing is open for the user.'
  const gap = Number(o.gap || 0)
  const gapText = gap
    ? ` ${gap} unit(s) never started: the ceiling of ${Number(o.room || 0)} agents per stage ended the stage.`
    : ''
  // two numbers, never one: `confirmed` counts the facts, `to the fixer` counts the groups the
  // fix stage really got. A blocked triage reports the facts it has and 0 to the fixer.
  return `${o.form} form, ${Number(o.groups || 0)} hint group(s), ${Number(o.confirmed || 0)} confirmed, ${Number(o.fixing || 0)} to the fixer, ${open} open. ${openText}${gapText} One round only: a second critique needs the user's word.`
}

// chainResult(s): the whole return of one chain run, built in one place, so a stage that blocks
// late returns what the run already knows instead of a bare blocked line: the undetermined rows,
// the groups nobody answered, the harness failures in their own list, the failures that reproduce
// on the base version (named), the evidence files written, the gap and the status sentence (A28).
// `groups` is every group of the run, `ran` the groups a stage really started.
function chainResult(s) {
  const o = s || {}
  const groups = o.groups || []
  const answers = o.answers || []
  // one table for the whole run: the return and the review file are rendered from these same rows
  const T = chainRows(o.ran || groups, answers)
  // the facts are counted from the answers themselves, so no caller can claim a confirmation the
  // evidence never gave, and a stage that blocked late still reports what was confirmed
  const conf = T.confirmed
  const und = T.undetermined
  const open = T.unanswered
  const base = o.base || 'the base version'
  const res = {
    out: o.out == null ? null : o.out,
    form: o.form,
    aspects: o.aspects || [],
    critics: Number(o.critics || 0),
    groups: groups.length,
    confirmed: conf.length,
    fixing: Number(o.fixing || 0),
    fixed: o.fixed || 'no accepted row: nothing was changed',
    undetermined: und.map(r => `${r.id}: ${r.place} — ${r.pointer}`),
    unanswered: open.map(r => `${r.id} at ${r.place}: the stage ran and came back with no readable answer`),
    harness: T.harness.map(r => `${r.id}: ${r.pointer}`),
    onBase: T.onBase.map(r => `${r.id}: reproduces on ${base}, no finding of this change`),
    evidence: o.evidence || [],
    gap: o.gap || [],
    blockedStages: o.blockedStages || [],
    status: chainStatus({
      form: o.form, groups: groups.length, confirmed: conf.length, fixing: Number(o.fixing || 0),
      undetermined: und.length, unanswered: open.length, out: o.out,
      gap: Number(o.gapCount || 0), room: Number(o.room || 0),
    }),
  }
  if (o.stage) res.stage = o.stage
  if (o.blocked) res.blocked = blockedLine(o.blocked)
  return res
}

// ---- the composite flows of idea 8.7 (make) and 8.2 (probe) ----
// The same rule as the chain above: every decision of the two flows lives here as a pure function
// over arguments and stage returns, so a test executes it instead of grepping a workflow file.

// MAKE_STAGES: the stages of make.js, in the order of the artifact chain of 3.5.2 — the
// specification, the scenarios, the tests, the code, the run of the oracle, the coverage check and
// the fix. Each of them is a gate of the old `dev`, and each can run alone (idea 7).
const MAKE_STAGES = ['spec', 'scenarios', 'tests', 'code', 'executor', 'coverage', 'fixer']

// stageRange(from, until): the `from` and `until` arguments as a contiguous range of MAKE_STAGES.
// A missing end is the end of the list, so a launch with neither argument runs the whole flow and a
// launch with both runs one stage alone. An unknown name and a backwards range return ok:false with
// the reason and the list: the launcher fixes the call, and no run silently does more than it was
// asked for.
function stageRange(from, until) {
  const all = MAKE_STAGES.slice()
  const f = from == null || from === '' ? all[0] : String(from)
  const u = until == null || until === '' ? all[all.length - 1] : String(until)
  const i = all.indexOf(f)
  const j = all.indexOf(u)
  const bad = [...(i === -1 ? [f] : []), ...(j === -1 ? [u] : [])]
  if (bad.length) {
    return { ok: false, stages: [], from: f, until: u, why: blockedLine(`unknown stage ${bad.join(' ')}; the stages are ${all.join(' ')}`) }
  }
  if (i > j) {
    return { ok: false, stages: [], from: f, until: u, why: blockedLine(`the range ${f}..${u} runs backwards; the order is ${all.join(' ')}`) }
  }
  return { ok: true, stages: all.slice(i, j + 1), from: f, until: u, why: null }
}

// stageOn(range, name): does this stage run in this range? A rejected range switches nothing on.
function stageOn(range, name) {
  return !!range && range.ok === true && (range.stages || []).indexOf(name) !== -1
}

// makePlan(depth, range): what the depth does to the range. At `lite` the upper levels of the
// artifact chain collapse into the scenario file and no coverage report is written (A5); the key
// document goes to the evidence chain one class step up above `lite` (3.5 rule 3); the negative
// control of ladder level c runs at `full` only (3.5 rule 1). The cycle ceiling comes from the
// depth table of lib/classes.json (A30), never from a number in a script.
const DEPTH_FOLD = { lite: ['spec', 'coverage'], std: [], full: [] }
function makePlan(depth, range) {
  if (!CLASSES.ceilings[depth]) throw new Error(`unknown depth ${depth}`)
  if (!range || range.ok !== true) throw new Error('makePlan needs a stage range that resolved')
  const fold = DEPTH_FOLD[depth] || []
  const stages = range.stages.filter(s => !fold.includes(s))
  return {
    stages,
    folded: range.stages.filter(s => fold.includes(s)),
    keyCheck: depth !== 'lite' && stages.includes('spec'),
    control: depth === 'full' && stages.includes('tests'),
    cycles: ceiling(depth).cycles,
  }
}

// runVerdict(ret): the verdict of an executor return. The executor answers PASS or FAIL with the
// exit status; the first line that opens with one of the two words decides, through the same
// decoration stripping the chain answers get. A return that says neither settles nothing:
// `unreadable`, which no caller may read as a pass.
function runVerdict(ret) {
  for (const raw of String(ret == null ? '' : ret).split('\n')) {
    const s = String(raw).replace(LEAD, '').trim()
    if (!s) continue
    const v = word(s.split(/[\s|:,]+/)[0] || '').toUpperCase()
    const verdict = v === 'PASS' || v === 'FAIL' ? v : 'unreadable'
    if (verdict !== 'unreadable') return verdict
  }
  return 'unreadable'
}

// negativeControl(depth, verdict): the negative control of 3.5 rule 1 and ladder level c. At `full`
// the new tests are run against the unchanged base version and must FAIL there; a suite that passes
// without the change proves nothing about it. Below `full` no control run is asked for. A suite
// that passed on the base version, and a control run nobody could read, are both gaps of the run —
// never an acceptance, and never a silent one.
function negativeControl(depth, verdict) {
  if (!CLASSES.ceilings[depth]) throw new Error(`unknown depth ${depth}`)
  const required = depth === 'full'
  if (!required) return { required: false, ran: false, ok: true, verdict: null, gap: null }
  const v = verdict == null || verdict === '' ? 'unreadable' : String(verdict)
  const ran = v === 'PASS' || v === 'FAIL'
  const okBase = v === 'FAIL'
  if (okBase) return { required: true, ran: true, ok: true, verdict: v, gap: null }
  const gap = ran
    ? 'the test suite passes on the base version: it proves nothing about this change (negative control, ladder level c)'
    : 'the control run on the base version came back with no readable PASS or FAIL: the suite stays unproven'
  return { required: true, ran, ok: false, verdict: v, gap }
}

// cycleState(depth, used): the fix cycles of A30 as a ceiling of the fix stage. When it is hit the
// stage ends and `gap` is what the result carries; nothing is retried in silence.
function cycleState(depth, used) {
  const room = ceiling(depth).cycles
  const n = Number(used)
  if (!Number.isFinite(n) || n < 0) throw new Error(`cycleState needs a cycle count, got ${used}`)
  const hit = ceilingHit(depth, 'cycles', n)
  const gap = hit
    ? `the fix cycle ceiling of ${room} at depth ${depth} ended the stage: what the check still fails is a gap, not another round`
    : null
  return { room, used: n, hit, gap }
}

// stageSeats(depth, wanted): the ceiling of A30 over the units of one parallel stage, for any flow.
// It is the rule chainSeats() carries for the review chain, under a name the other flows can read.
function stageSeats(depth, wanted) {
  return chainSeats(depth, wanted)
}

// makeStatus(s) / makeResult(s): the one return of a make run. Every exit of the flow is built here
// — a blocked stage, a failing oracle and a finished run alike — so a run that stopped can never
// carry the shape of one that finished: `ok` is true only when the oracle said PASS, no stage
// blocked, and the negative control (when the depth asked for one) really failed on the base
// version.
function makeStatus(s) {
  const o = s || {}
  const gap = o.gap || []
  const where = o.out || 'the report file'
  const stopped = o.blocked ? ` The run stopped at the ${o.stage || 'unnamed'} stage: ${o.blocked}` : ''
  const runText = o.run === 'PASS'
    ? 'the oracle passed'
    : o.run === 'FAIL'
      ? 'the oracle still fails'
      : o.run === null || o.run === undefined
        ? 'no oracle run happened'
        : `the oracle run came back unreadable (${o.run})`
  const ctl = o.control && o.control.required
    ? o.control.ok
      ? ' The tests failed on the base version, as a negative control must.'
      : ' The negative control did not hold.'
    : ''
  const gapText = gap.length
    ? ` ${gap.length} gap(s) stand in this return and in ${where}: they are unfinished work, not a silent retry.`
    : ''
  const folded = o.folded || []
  const foldText = folded.length
    ? ` The depth folded ${folded.join(', ')} into the short form: those levels were not written as files of their own.`
    : ''
  return `${Number(o.done || 0)} of ${Number(o.planned || 0)} stage(s) ran (${o.range || ''}), ${runText}.${ctl}${foldText}${gapText}${stopped}`
}
function makeResult(s) {
  const o = s || {}
  const stages = o.stages || []
  const done = o.done || []
  const nc = o.control || null
  const gap = (o.gap || []).slice()
  if (nc && nc.gap) gap.push(nc.gap)
  const blocked = o.blocked ? blockedLine(o.blocked) : null
  const run = o.run == null ? null : String(o.run)
  const ok = !blocked && run === 'PASS' && (!nc || nc.ok)
  const first = stages[0] || ''
  const last = stages.length ? stages[stages.length - 1] : ''
  const res = {
    out: o.out == null ? null : o.out,
    ok,
    range: `${o.from || first}..${o.until || last}`,
    stages,
    done,
    files: o.files || [],
    run,
    control: nc ? { required: nc.required, ran: nc.ran, verdict: nc.verdict, ok: nc.ok } : null,
    cycles: Number(o.cycles || 0),
    check: o.check == null ? null : o.check,
    folded: o.folded || [],
    gap,
    status: makeStatus({
      run, gap, out: o.out, control: nc, stage: o.stage, blocked, folded: o.folded || [],
      done: done.length, planned: stages.length, range: `${o.from || first}..${o.until || last}`,
    }),
  }
  if (o.stage) res.stage = o.stage
  if (blocked) res.blocked = blocked
  return res
}

// probeStatus(s) / probeResult(s): the one return of a probe run, on the same rule. A finished run
// has a bundle per direction that ran, a critique over them and the synthesis file; a run that lost
// its synthesis, its critique or every direction is not finished, whatever else it wrote.
function probeStatus(s) {
  const o = s || {}
  const gap = o.gap || []
  const stopped = o.blocked ? ` The run stopped at the ${o.stage || 'unnamed'} stage: ${o.blocked}` : ''
  const gapText = gap.length
    ? ` ${gap.length} direction(s) never started: the ceiling of a stage ended it, and that is a gap of this answer.`
    : ''
  const where = o.out ? ` The answer stands in ${o.out}; every claim in it carries the pointer it rests on.` : ''
  return `${Number(o.bundles || 0)} of ${Number(o.directions || 0)} direction(s) came back, ${o.critique ? 'critiqued' : 'with no critique'}, ${o.synthesis ? 'synthesised' : 'with no synthesis'}.${where}${gapText}${stopped}`
}
function probeResult(s) {
  const o = s || {}
  const bundles = o.bundles || []
  const directions = o.directions || []
  const gap = (o.gap || []).slice()
  const blocked = o.blocked ? blockedLine(o.blocked) : null
  const ok = !blocked && !!o.out && bundles.length > 0 && !!o.critique && !!o.synthesis
  const res = {
    out: o.out == null ? null : o.out,
    ok,
    directions,
    bundles,
    critique: o.critique == null ? null : o.critique,
    synthesis: o.synthesis == null ? null : o.synthesis,
    gap,
    blockedStages: o.blockedStages || [],
    status: probeStatus({
      bundles: bundles.length, directions: directions.length, critique: o.critique,
      synthesis: o.synthesis, out: o.out, gap, stage: o.stage, blocked,
    }),
  }
  if (o.stage) res.stage = o.stage
  if (blocked) res.blocked = blocked
  return res
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    CLASSES, MODEL_NAME, EFFORT_NAME, submodes, cellFor, optsFor, classUp, slotForSize, bindClass,
    roleOf, roleNames, roleAgent, roleSlot, roleClass, ceiling, ceilingHit, isBlocked, lastLine,
    blockedLine, mustExist, outVerdict,
    HINT_CAP, SEVERITY_ORDER, keyedFields, placeOf, placeText, parseHints, capHints, hintsOverlap, groupHints,
    maxSeverity, chainForm, pickAspects, criticSplit, parseEvidence, dedupeAnswers, splitFailures,
    hintRows, chainRows, openRowsText,
    fixerInput, confirmedOf, undeterminedOf, unansweredOf, parseAccepted, judgedInput, chainSeats,
    aspectsOrStop, chainPlan, chainEvidenceRuns, chainStatus, chainResult,
    MAKE_STAGES, stageRange, stageOn, makePlan, runVerdict, negativeControl, cycleState,
    stageSeats, makeStatus, makeResult, probeStatus, probeResult,
  }
}
