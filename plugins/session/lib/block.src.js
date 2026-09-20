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
// grouped and could not be settled, so it is no hint.
function parseHints(text, aspect) {
  const hints = []
  for (const line of String(text == null ? '' : text).split('\n')) {
    const parts = line.split('|')
    if (parts[0].trim() !== 'HINT') continue
    const f = parts.slice(1).map(s => s.trim())
    const place = f[1] || ''
    if (!place) continue
    const sev = (f[2] || '').toLowerCase()
    hints.push({
      aspect: f[0] || aspect || '',
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
  return groups.map((g, i) => ({ ...g, aspects: g.aspects.slice().sort(), id: `g${i + 1}` }))
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
  for (const line of String(text == null ? '' : text).split('\n')) {
    const parts = line.split('|')
    if (parts[0].trim() !== 'EVIDENCE') continue
    const f = parts.slice(1).map(s => s.trim())
    const group = f[0] || ''
    if (!group) continue
    const v = (f[1] || '').toLowerCase()
    let verdict = EVIDENCE_VERDICTS.includes(v) ? v : 'undetermined'
    const base = (f[2] || '').trim()
    // a missing or unreadable control-run field settles nothing: reading it as `base:no` would
    // turn an answer nobody controlled into a finding of this change. It goes to the user, the
    // same way an unreadable verdict does. A harness failure needs no control run.
    if (verdict !== 'harness' && !/^base:\s*(yes|no)$/i.test(base)) verdict = 'undetermined'
    answers.push({
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
// dedupeAnswers(answers): one answer per hint group. A stage that wrote two lines for one group
// would otherwise put that group in two lists at once — confirmed to the fixer and undetermined to
// the user. The stronger evidence wins: a settled verdict beats an unsettled one and beats a
// failure of our own harness; two settled verdicts that contradict each other (confirmed and
// refuted) settle nothing, so the group goes to the user as undetermined.
const ANSWER_RANK = ['harness', 'undetermined', 'refuted', 'confirmed']
function dedupeAnswers(answers) {
  const out = []
  for (const a of answers || []) {
    const cur = out.filter(x => x.group === a.group)[0]
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

// fixerInput(groups, answers): what may reach the one who changes the object. A hint without
// evidence changes nothing, so only a group a fact confirmed goes on; refuted, undetermined,
// harness, base-version and unanswered groups all stay out (A28).
function fixerInput(groups, answers) {
  const confirmed = confirmedOf(answers).map(a => a.group)
  return (groups || []).filter(g => confirmed.includes(g.id))
}

// confirmedOf(answers): the groups a fact confirmed. The `confirmed` count of the result and of
// the status is this one, never the count that reached the fixer: a run whose triage or fix stage
// blocked still confirmed what it confirmed, and a judge that rejected a confirmed group does not
// unmake the fact (A28). What the fixer got is its own number.
function confirmedOf(answers) {
  return splitFailures(answers).findings.filter(a => a.verdict === 'confirmed')
}

// undeterminedOf(answers): the list that goes into the result file and into the status, for the
// main session to put to the user (A28: a script has no place for the user).
function undeterminedOf(answers) {
  return splitFailures(answers).findings.filter(a => a.verdict === 'undetermined')
}

// unansweredOf(groups, answers): a group that ran and came back with no readable answer line.
// Nothing settled it, so it is neither confirmed nor rejected: it goes to the user with the
// undetermined ones (A28). Counting it out of existence would drop a whole hint group.
function unansweredOf(groups, answers) {
  const seen = (answers || []).map(a => a.group)
  return (groups || []).filter(g => !seen.includes(g.id))
}

// parseAccepted(text): the accepted rows of the judge's return. Format, one line per row:
//   ACCEPTED | <group id> | <the change in one sentence>
// The whole decision stands in the judge's result file; these lines are the part a script without
// file access can read, and they are the only mandate the fixer gets.
function parseAccepted(text) {
  const rows = []
  for (const line of String(text == null ? '' : text).split('\n')) {
    const parts = line.split('|')
    if (parts[0].trim() !== 'ACCEPTED') continue
    const f = parts.slice(1).map(s => s.trim())
    if (!f[0]) continue
    rows.push({ group: f[0], change: f.slice(1).join(' | ') })
  }
  return rows
}

// judgedInput(groups, answers, rows): the fixer's mandate in the long form. The judge decides
// which groups become changes, so a group it rejected or left unsettled never reaches the fixer;
// it cannot widen the mandate either, so a row no fact confirmed stays out (A28). No accepted
// row, no fix stage.
function judgedInput(groups, answers, rows) {
  const ids = (rows || []).map(r => r.group)
  return fixerInput(groups, answers).filter(g => ids.includes(g.id))
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
  const split = splitFailures(answers)
  // the facts are counted from the answers themselves, so no caller can claim a confirmation the
  // evidence never gave, and a stage that blocked late still reports what was confirmed
  const conf = confirmedOf(answers)
  const und = undeterminedOf(answers)
  const open = unansweredOf(o.ran || groups, answers)
  const base = o.base || 'the base version'
  const placeById = id => (groups.filter(g => g.id === id)[0] || {}).place || id
  const res = {
    out: o.out == null ? null : o.out,
    form: o.form,
    aspects: o.aspects || [],
    critics: Number(o.critics || 0),
    groups: groups.length,
    confirmed: conf.length,
    fixing: Number(o.fixing || 0),
    fixed: o.fixed || 'no accepted row: nothing was changed',
    undetermined: und.map(a => `${a.group}: ${placeById(a.group)} — ${a.pointer}`),
    unanswered: open.map(g => `${g.id} at ${g.place}: the stage ran and came back with no readable answer`),
    harness: split.harness.map(a => `${a.group}: ${a.pointer}`),
    onBase: split.onBase.map(a => `${a.group}: reproduces on ${base}, no finding of this change`),
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

if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    CLASSES, MODEL_NAME, EFFORT_NAME, submodes, cellFor, optsFor, classUp, slotForSize, bindClass,
    roleOf, roleNames, roleAgent, roleSlot, roleClass, ceiling, ceilingHit, isBlocked, lastLine,
    blockedLine, mustExist, outVerdict,
    HINT_CAP, SEVERITY_ORDER, placeOf, placeText, parseHints, capHints, hintsOverlap, groupHints,
    maxSeverity, chainForm, pickAspects, criticSplit, parseEvidence, dedupeAnswers, splitFailures,
    fixerInput, confirmedOf, undeterminedOf, unansweredOf, parseAccepted, judgedInput, chainSeats,
    aspectsOrStop, chainPlan, chainEvidenceRuns, chainStatus, chainResult,
  }
}
