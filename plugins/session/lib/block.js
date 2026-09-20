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
  "slotDown": {
    "main": "opus",
    "opus": "sonnet",
    "sonnet": "sonnet"
  },
  "sizes": [
    "small",
    "medium",
    "large"
  ],
  "defaultSize": "medium",
  "models": {
    "fab": "fable",
    "ops": "opus",
    "son": "sonnet"
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
      "no-opus no-fable": "son-me/son-hi/son-hi"
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
  "classStep": {
    "c1": "c2",
    "c2": "c3",
    "c3": "c4",
    "c4": "c5",
    "c5": "c5"
  },
  "roles": {
    "plan-author": {
      "agent": "tools-read-write",
      "slot": "main",
      "uplift": true
    },
    "spec-author": {
      "agent": "tools-read-write",
      "slot": "main",
      "uplift": true
    },
    "scenario-author": {
      "agent": "tools-read-write",
      "slot": "main",
      "uplift": true
    },
    "code-author": {
      "agent": "tools-edit",
      "slot": "sonnet",
      "uplift": false
    },
    "test-author": {
      "agent": "tools-edit",
      "slot": "sonnet",
      "uplift": false
    },
    "coverage-checker": {
      "agent": "tools-read-write",
      "slot": "sonnet",
      "uplift": false
    },
    "closure-author": {
      "agent": "tools-read-write",
      "slot": "sonnet",
      "uplift": false,
      "returns": "text"
    },
    "critic": {
      "agent": "tools-read-write",
      "slot": "main",
      "splitSlot": "opus",
      "uplift": false
    },
    "evidence-researcher": {
      "agent": "tools-read-bash",
      "slot": "sonnet",
      "uplift": false
    },
    "evidence": {
      "agent": "tools-read-bash",
      "slot": "sonnet",
      "uplift": false
    },
    "evidence-triage": {
      "agent": "tools-read-write",
      "slot": "main",
      "uplift": false
    },
    "fixer": {
      "agent": "tools-edit",
      "slot": "opus",
      "uplift": false
    },
    "researcher": {
      "agent": "tools-read-write-bash",
      "slot": "sonnet",
      "uplift": false
    },
    "web-researcher": {
      "agent": "tools-web",
      "slot": "sonnet",
      "uplift": false
    },
    "synthesizer": {
      "agent": "tools-read-write",
      "slot": "main",
      "uplift": true
    },
    "executor": {
      "agent": "tools-read-bash",
      "slot": "sonnet",
      "uplift": false
    },
    "waiter": {
      "agent": "tools-read-bash",
      "slot": "sonnet",
      "uplift": false
    },
    "translator": {
      "agent": "tools-read-write",
      "slot": "opus",
      "uplift": false
    }
  },
  "ceilings": {
    "lite": {
      "agents": 2,
      "cycles": 1
    },
    "std": {
      "agents": 5,
      "cycles": 2
    },
    "full": {
      "agents": 10,
      "cycles": 3
    }
  }
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

// cellTokens(line): the tokens of one line of prose that name a cell of the class table — a model
// name, the short code of a cell (`fab-me`), a reasoning-level word, or a frontmatter pin. The
// class table is the only source of what a launch runs on, so no text of this plugin names one of
// them, and tests/rebuild/text.sh executes this function over every text file of the new set
// instead of carrying a regex of its own. Two forms are no cell token: a slot name ("opus slot",
// "sonnet-slot") names a column of the table, a submode name ("no-sonnet") names one of its rows.
const OFF_TABLE_MODELS = ['haiku'] // a model the class table never picks, still banned in prose
const LEVEL_WORDS = ['effort', 'tier'] // a level noun that names the table's own vocabulary alone
// A level can be named without either of those two words ("run at high reasoning", "reasoning level
// high"), so the nouns below count too — but only with a level word of lib/classes.json beside
// them, or the sentence that names `/model` as the reasoning-level command could no longer be
// written. The level words are the values of the table, never a list of this file.
const LEVEL_NOUNS = ['effort', 'tier', 'reasoning', 'thinking']
function cellTokens(line) {
  const s = String(line == null ? '' : line)
  const names = Object.values(MODEL_NAME).concat(OFF_TABLE_MODELS).join('|')
  const mods = Object.keys(MODEL_NAME).join('|')
  const effs = Object.keys(EFFORT_NAME).join('|')
  const levels = Object.values(EFFORT_NAME).join('|')
  const nouns = LEVEL_NOUNS.join('|')
  const parts = [
    `(no-)?\\b(?:${names})\\b([- ]slot)?`, // a model name, with its submode and slot forms
    `\\b(?:${mods})-(?:${effs})\\b`, // the short code of a cell, the way a label carries it
    `\\b(?:${LEVEL_WORDS.join('|')})\\b`, // a reasoning level or a tier
    `\\b(?:${levels})[- ]+(?:level[- ]+)?(?:${nouns})\\b`, // "high reasoning", "low effort"
    `\\b(?:${nouns})(?:[- ]+level)?[- :]+(?:${levels})\\b`, // "reasoning level high", "effort: low"
  ]
  const re = new RegExp(parts.join('|'), 'gi')
  const hits = []
  let m
  while ((m = re.exec(s)) !== null) {
    if (m[1] || m[2]) continue // "no-sonnet" is a row, "opus slot" is a column: neither is a cell
    hits.push(m[0])
  }
  if (/^(?:model|effort):/i.test(s)) hits.push(s.trim()) // a frontmatter pin of a whole file
  return hits
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
// roleReturnsText(role): true for a role whose whole output is its return. This harness lets no
// subagent hand a report file to anybody, so such a role writes nothing, reads its `out` as the
// directory the run filled, and is checked on closureReport() of its return, never on a path. The
// fact lives in lib/classes.json because a workflow script may carry no role name of its own.
function roleReturnsText(name) { return roleOf(name).returns === 'text' }

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

// namesOut(text, out): does this text name the output file? The stage asks for the absolute path,
// and an agent that worked in that directory writes the file the way it typed it at the shell —
// `out/make-tests.md` for `/p/out/make-tests.md`. That is the same file, so it counts. A tail of
// the path counts only when it starts at a directory boundary of the path and stands in the text as
// a whole path of its own: `/other/dir/make-tests.md`, `my-make-tests.md` and `make-tests.md.bak`
// never pass for it — a neighbour whose name carries this one is another file, and a size line
// about it is no evidence that this one was written.
const PATH_CHAR = /[A-Za-z0-9_.\\/-]/
function namesOut(text, out) {
  if (!out) throw new Error('namesOut needs the output path')
  const s = String(text == null ? '' : text)
  const abs = String(out)
  const forms = [abs]
  for (let i = 0; i < abs.length - 1; i++) if (abs[i] === '/') forms.push(abs.slice(i + 1))
  for (const form of forms) {
    for (let at = s.indexOf(form); at !== -1; at = s.indexOf(form, at + 1)) {
      const after = at + form.length
      const opens = at === 0 || !PATH_CHAR.test(s[at - 1])
      // a full stop that ends the sentence is not a longer name: `.md.` closes the path, `.md.bak`
      // is another file, so a dot counts as a boundary only when no path character follows it
      const stop = s[after] === '.' && (after + 1 >= s.length || !PATH_CHAR.test(s[after + 1]))
      const closes = after >= s.length || !PATH_CHAR.test(s[after]) || stop
      if (opens && closes) return true
    }
  }
  return false
}

// mustExist(ret, out): the output check of every stage that names an output file. A workflow
// script has no file access, so the agent's own return is the evidence: it names the path it
// wrote. Returns { ok, out, reason }; a false ok stops the flow instead of feeding the next stage.
function mustExist(ret, out) {
  if (!out) throw new Error('mustExist needs the output path')
  const s = String(ret == null ? '' : ret)
  // the agent's own last line is the reason, unprefixed here: blockedLine puts the word on once
  if (isBlocked(ret)) return { ok: false, out, reason: lastLine(s) || 'no return' }
  if (!namesOut(s, out)) return { ok: false, out, reason: `return does not name ${out}` }
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
  const line = String(ret).split('\n').filter(l => namesOut(l, out) && RE.test(l))[0] || ''
  const n = Number(((line.match(RE) || [])[1] || '').replace(/,/g, ''))
  if (!(n > 0)) {
    const why = `return reports no non-empty ${out}: no positive byte count on a line naming it`
    return { ok: false, out, bytes: 0, reason: why, blocked: blockedLine(why) }
  }
  return { ok: true, out, bytes: n }
}

// outDir(out): the directory the files of a run go to, from the `out` argument. The argument names
// that directory; a caller that names a file inside it names the directory that file sits in, and
// nothing of this flow writes that file — the closing report of a run comes back in the return,
// because the harness lets no subagent write a report file. A last segment carrying a dot is read
// as a file name, any other segment as the directory itself.
function outDir(out) {
  const s = String(out == null ? '' : out).trim().replace(/\/+$/, '')
  if (!s || s[0] !== '/') throw new Error(`outDir needs an absolute path, got ${out}`)
  const cut = s.lastIndexOf('/')
  if (s.slice(cut + 1).indexOf('.') === -1) return s
  return cut < 1 ? '/' : s.slice(0, cut)
}

// taskDirOf(out): the task directory an argument that names a directory stands for. Nothing is
// read out of the last segment: a task directory is a directory whatever its slug looks like, so
// `2026-09-20-v0.16` stays itself where outDir()'s dot rule would drop it and put every file of
// the task one level up, in `tasks/`. A last segment carrying a document suffix is a file, never
// a task directory: it stops the launch instead of becoming a directory of that name.
const TASK_FILE_SUFFIX = /\.(md|jsonl?|txt|js|sh|ya?ml)$/i
function taskDirOf(out) {
  const s = String(out == null ? '' : out).trim().replace(/\/+$/, '')
  if (!s || s[0] !== '/' || s.length < 2) throw new Error(`taskDirOf needs an absolute task directory, got ${out}`)
  if (TASK_FILE_SUFFIX.test(s.slice(s.lastIndexOf('/') + 1))) {
    throw new Error(`taskDirOf needs a task directory, got the file ${out}`)
  }
  return s
}

// outForm(out) -> { dir, file }: the one rule every workflow reads its `out` argument by. The
// contract of all four scripts says the same thing — an absolute task directory, or one file
// inside a task directory — so the form may never hang on a trailing slash a launcher is free to
// drop: a task directory handed over without one would fall to the file branch, and the hints, the
// bundles and the change lists of that run would land in `tasks/` beside the task instead of in
// it. The rule is the rule of taskDirOf(): a last segment carrying a document suffix is a file,
// anything else is the task directory itself, whatever its slug reads like.
function outForm(out) {
  const p = String(out == null ? '' : out).trim().replace(/\/+$/, '')
  if (!p || p[0] !== '/' || p.length < 2) throw new Error(`out must be an absolute task directory or a file inside one, got ${out}`)
  const cut = p.lastIndexOf('/')
  if (!TASK_FILE_SUFFIX.test(p.slice(cut + 1))) return { dir: taskDirOf(p), file: null }
  if (cut < 1) throw new Error(`out must name a file inside a task directory, got ${out}`)
  return { dir: taskDirOf(p.slice(0, cut)), file: p }
}

// ---- the task file group of idea 8.8 ----
// One layout for every process and every depth, source lib/task-layout.md: bin/build.sh renders
// its two tables here, so the file a stage writes and the file the process skill reads are one
// name. Every path a workflow hands to a stage is built by taskPath(), never spelled in a script.

// ---- task layout ----
const LAYOUT = {
  "files": {
    "intent": {
      "path": "intent.md",
      "kind": "file",
      "lite": "task.md"
    },
    "subtasks": {
      "path": "subtasks.md",
      "kind": "file",
      "lite": "task.md"
    },
    "decisions": {
      "path": "decisions.md",
      "kind": "file",
      "lite": "task.md"
    },
    "specification": {
      "path": "specification.md",
      "kind": "file",
      "lite": "task.md"
    },
    "scenarios": {
      "path": "scenarios.md",
      "kind": "file",
      "lite": "task.md"
    },
    "verification-plan": {
      "path": "verification-plan.md",
      "kind": "file",
      "lite": "task.md"
    },
    "implementation-plan": {
      "path": "implementation-plan.md",
      "kind": "file",
      "lite": "task.md"
    },
    "tests": {
      "path": "tests.md",
      "kind": "file",
      "lite": "-"
    },
    "coverage": {
      "path": "coverage.md",
      "kind": "file",
      "lite": "-"
    },
    "report": {
      "path": "report.md",
      "kind": "file",
      "lite": "task.md"
    },
    "ledger": {
      "path": "ledger.jsonl",
      "kind": "state",
      "lite": "ledger.jsonl"
    },
    "evidence": {
      "path": "evidence",
      "kind": "dir",
      "lite": "evidence"
    },
    "reviews": {
      "path": "reviews",
      "kind": "dir",
      "lite": "reviews"
    },
    "changes": {
      "path": "changes",
      "kind": "dir",
      "lite": "changes"
    },
    "runs": {
      "path": "runs",
      "kind": "dir",
      "lite": "runs"
    }
  },
  "roleOut": {
    "plan-author": {
      "key": "implementation-plan",
      "stem": ""
    },
    "spec-author": {
      "key": "specification",
      "stem": ""
    },
    "scenario-author": {
      "key": "scenarios",
      "stem": ""
    },
    "test-author": {
      "key": "tests",
      "stem": ""
    },
    "code-author": {
      "key": "changes",
      "stem": "code"
    },
    "fixer": {
      "key": "changes",
      "stem": "fix"
    },
    "coverage-checker": {
      "key": "coverage",
      "stem": ""
    },
    "critic": {
      "key": "reviews",
      "stem": "hints"
    },
    "evidence-triage": {
      "key": "reviews",
      "stem": "accepted"
    },
    "evidence-researcher": {
      "key": "evidence",
      "stem": "answers"
    },
    "evidence": {
      "key": "evidence",
      "stem": "answers"
    },
    "researcher": {
      "key": "evidence",
      "stem": "bundle"
    },
    "web-researcher": {
      "key": "evidence",
      "stem": "web"
    },
    "synthesizer": {
      "key": "report",
      "stem": ""
    },
    "executor": {
      "key": "runs",
      "stem": "run"
    },
    "waiter": {
      "key": "runs",
      "stem": "wait"
    }
  }
}
// ---- end task layout ----

// taskEntry(key) -> { path, kind, lite }: the row of the layout, or an error. An unknown key is a
// defect of the caller, not a file to invent: a stage writing outside the layout is a stage
// nobody reads.
function taskEntry(key) {
  const e = LAYOUT.files[key]
  if (!e) throw new Error(`unknown task file ${key}`)
  return e
}
function taskKeys() { return Object.keys(LAYOUT.files) }

// taskPath(dir, key, stem): the absolute path of one file of the group under the task directory.
// A `dir` row needs a stem (one file per run of that stage), a `file` row takes none. The stem is
// sanitised, never trusted: it comes from a label, a group id or a cycle counter, so anything but
// [A-Za-z0-9._-] becomes a dash and no stem can leave the task directory.
function taskPath(dir, key, stem) {
  const d = String(dir == null ? '' : dir).trim().replace(/\/+$/, '')
  if (!d || d[0] !== '/') throw new Error(`taskPath needs an absolute task directory, got ${dir}`)
  const e = taskEntry(key)
  if (e.kind !== 'dir') {
    if (stem != null && String(stem) !== '') throw new Error(`task file ${key} takes no stem, got ${stem}`)
    return `${d}/${e.path}`
  }
  const s = String(stem == null ? '' : stem).replace(/[^A-Za-z0-9._-]+/g, '-').replace(/^[-.]+/, '').replace(/[-.]+$/, '')
  if (!s) throw new Error(`task directory ${key} needs a stem`)
  return `${d}/${e.path}/${s}.md`
}

// runStem(stem, run): the stem of one file of a `dir` row. A `dir` row of lib/task-layout.md is
// one file per run of its stage, and a script has no clock, no random and no file access: the key
// that tells two runs apart comes from the launcher (`args.run`). Without it the second launch of
// the same role into the same task directory would write over the file of the first one and hand
// its launcher a success-shaped result, so a missing key is an error here, never a silent overwrite.
function runStem(stem, run) {
  const k = String(run == null ? '' : run).trim()
  if (!k) throw new Error(`a file of one run needs a run key (args.run): ${stem || '(no stem)'} would write over the file of the run before it`)
  return stem ? `${stem}-${k}` : k
}

// writeHint(out, hasShell): the sentence a stage needs before it can write `out`. A `dir` row of
// the layout puts its file one level below the task directory, and the roles on a shell-only tool
// set create their output with a redirect: `> <dir>/runs/run.md` dies with "No such file or
// directory" when `<dir>/runs` is absent, and no stage, script or role text of this flow runs
// mkdir. A role with a Write tool needs no hint (the tool makes the parent directory itself); a
// shell-only role gets the mkdir for the directory its file sits in, the task directory included,
// because a launcher that only hands over a path may never have created it.
function writeHint(out, hasShell) {
  const s = String(out == null ? '' : out).trim().replace(/\/+$/, '')
  if (!s || s[0] !== '/') throw new Error(`writeHint needs an absolute output path, got ${out}`)
  if (!hasShell) return ''
  const cut = s.lastIndexOf('/')
  const parent = cut < 1 ? '/' : s.slice(0, cut)
  if (parent === '/') return ''
  return ` Make its directory first, \`mkdir -p ${parent}\`: a redirect into a directory that does not exist writes nothing.`
}

// liteTarget(key): what the depth `lite` does with that row — the collapsed file it becomes, its
// own path when it stays, or null when the depth does not have that level at all (A5).
function liteTarget(key) {
  const v = taskEntry(key).lite
  return !v || v === '-' ? null : v
}

// roleOut(role) -> { key, stem } or null: the file of the layout a role writes when it is launched
// with the task directory instead of a path. A role with no row always needs a path of its own.
function roleOut(role) {
  const r = LAYOUT.roleOut[role]
  return r ? { key: r.key, stem: r.stem || '' } : null
}
// roleOutPath(dir, role, run): that file under the task directory. A `dir` row is one file per
// run, so it takes the run key of the launch and throws without one (runStem); a `file` row is one
// document of the task and takes no key.
function roleOutPath(dir, role, run) {
  const r = roleOut(role)
  if (!r) return null
  return taskPath(dir, r.key, taskEntry(r.key).kind === 'dir' ? runStem(r.stem, run) : r.stem)
}

// closureReport(ret): the closing report of a run, read out of the return of its closure stage.
// A subagent of this harness returns its findings as text and writes no report file, so the return
// itself is the report and this is the only check over it: a return that came back empty, blocked,
// or carrying nothing but its shape line is a gap of the run, never a report.
function closureReport(ret) {
  const s = String(ret == null ? '' : ret).trim()
  if (!s) return { ok: false, report: null, gap: 'the closing report came back empty: this run states nothing about itself' }
  if (isBlocked(ret)) return { ok: false, report: null, gap: `the closing report was not returned: ${lastLine(s)}` }
  const lines = s.split('\n')
  // the last line of every tool-set return is the shape line, no part of the report itself
  while (lines.length && /^DONE[.!]?$/i.test(lines[lines.length - 1].trim())) lines.pop()
  const text = lines.join('\n').trim()
  if (!text) return { ok: false, report: null, gap: 'the closing report carried nothing but its last line' }
  return { ok: true, report: text, gap: null }
}

// textResult(ret, head, agent): the whole return of a stage whose output is its return and not a
// file — the closure role. `out` is null in both shapes, because no file was written and a
// launcher that reads a path here would look for a file nobody creates; a return closureReport()
// calls a gap becomes a blocked result, never a finished one, and the agent type stands only on a
// result that carries a report. The decision lives here, not in workflows/role.js, so a test can
// execute it instead of grepping the script.
function textResult(ret, head, agent) {
  const h = { ...(head || {}), out: null }
  const c = closureReport(ret)
  if (!c.ok) return { ...h, blocked: blockedLine(c.gap) }
  return { ...h, agent, report: c.report, result: lastLine(ret) }
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

// controlTree(ret): what the negative control left in the working tree. That run needs the base
// version of the source, and the only honest place for it is a scratch copy: a checkout over the
// live tree would take uncommitted work this flow never wrote, and no later stage could put it
// back. The executor states what it left behind on a `TREE | untouched` line; a return that states
// nothing verified nothing, so it is a gap of the run, exactly like a control nobody could read.
function controlTree(ret) {
  const v = word((keyedFields(ret, 'TREE', 1)[0] || [])[0] || '').toLowerCase()
  if (v === 'untouched') return { stated: true, untouched: true, gap: null }
  if (v === 'changed') {
    return { stated: true, untouched: false, gap: 'the negative control left the working tree changed: the base version of the source, or a file it moved, may still stand in it — check the tree before anything else is built on it' }
  }
  return { stated: false, untouched: false, gap: 'the negative control never said what it left in the working tree (no `TREE | untouched` line): nothing verified that the tree it ran over is the tree the next stage gets' }
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

// fixerState(range, run): does the fix stage enter, and must it learn the oracle state first? The
// fix stage is a gate of its own (idea 7), so a launch `from=fixer until=fixer` carries no executor
// before it and `run` is null: the stage runs the check itself once before it fixes anything,
// instead of doing nothing and returning the shape of a finished run. A run the oracle already
// passed is nothing to fix, and a range without the fix stage enters nothing.
function fixerState(range, run) {
  if (!stageOn(range, 'fixer')) return { enter: false, probe: false, why: 'the fix stage is outside this range' }
  const v = run == null || run === '' ? null : String(run)
  if (v === null) {
    return { enter: true, probe: true, why: 'no executor stage ran in this range: the fix stage runs the check once before it fixes' }
  }
  if (v === 'PASS') return { enter: false, probe: false, why: 'the oracle passed: nothing to fix' }
  return { enter: true, probe: false, why: `the oracle said ${v}` }
}

// keyCheckState(c, file): the return of the evidence chain over the key document, as the two things
// a make run carries on — what the check is, and what it left open. A chain that never finished is
// the `needs chain` fallback of U8. A chain that did finish and came back with undetermined rows,
// unanswered rows or gaps of its own has found the key document defective: those rows are gaps of
// this run too, so a specification nobody could settle never passes to the next level in silence.
function keyCheckState(c, file) {
  const gap = []
  const where = file || 'the key document'
  if (!c || c.blocked) {
    const why = c && c.blocked ? lastLine(c.blocked) : 'the chain returned nothing'
    gap.push(`needs chain: the key-document check of ${where} did not finish (${why}); the main session launches session:chain over it one class step up`)
    return { ok: false, ran: !!c, check: `needs chain: ${why}`, gap }
  }
  for (const r of c.gap || []) gap.push(`key document ${where}: ${r}`)
  for (const r of c.undetermined || []) gap.push(`key document ${where}: ${r} — the chain could not settle it, and it stands open over every level built on this document`)
  for (const r of c.unanswered || []) gap.push(`key document ${where}: ${r}`)
  return { ok: gap.length === 0, ran: true, check: c.out || where, gap }
}

// stageStop(s, name): what a stage result does to the run. A stage whose output check came back
// bad — a blocked agent, a file nobody wrote, an empty one — ends the run at that stage, and the
// control run is no exception: a control that never spoke says nothing about the base version, so
// nothing may be built on what it left behind. The return is the extra the result builder takes,
// so every stage of a flow stops through the one builder and names itself while doing it.
function stageStop(s, name) {
  if (!name) throw new Error('stageStop needs the stage name')
  if (s && s.ok === true) return { stop: false, stage: name, blocked: null }
  const why = (s && s.blocked) || 'the stage came back with nothing'
  return { stop: true, stage: name, blocked: blockedLine(why) }
}

// fixerDone(capped): the stages the fix loop adds to the ran list. A loop the cycle ceiling cut
// left the check failing, so the fix stage never did its job: it is a gap of the run, never a
// stage that ran. A loop that ended by itself ended on a passing check.
function fixerDone(capped) {
  return capped === true ? [] : ['fixer']
}

// makeStatus(s) / makeResult(s): the one return of a make run. Every exit of the flow is built here
// — a blocked stage, a failing oracle and a finished run alike — so a run that stopped can never
// carry the shape of one that finished: `ok` is true only when the oracle said PASS, no stage
// blocked, the closing report came back in `report`, and the negative control (when the depth asked
// for one) really failed on the base version, and the check of the key document (when the depth
// asked for one) left no row open. A
// range that carries no oracle stage at all (`spec..tests` and its kind) is judged on what it
// promised instead: every stage of the range ran, and the status says in words that no check ran
// here, so a partial range is never read as a failing one. A range the depth folds to nothing
// (`from=spec until=spec` at `lite`) promised nothing and did nothing: that is a finished no-op with
// the folded levels named, never a failure nobody can explain.
function makeStatus(s) {
  const o = s || {}
  const gap = o.gap || []
  const stopped = o.blocked ? ` The run stopped at the ${o.stage || 'unnamed'} stage: ${o.blocked}` : ''
  const runText = o.noop
    ? 'the depth folded every stage of this range, so nothing ran and nothing is open'
    : o.run === 'PASS'
      ? 'the oracle passed'
      : o.run === 'FAIL'
        ? 'the oracle still fails'
        : o.run === null || o.run === undefined
          ? o.oracle === false
            ? 'no stage of this range runs the check, so this range settles no behavior'
            : 'no oracle run happened'
          : `the oracle run came back unreadable (${o.run})`
  const keyText = o.key === false
    ? ' The key document did not come back clean from its check: what it left open stands in the gaps.'
    : ''
  const ctl = o.control && o.control.required
    ? o.control.ok
      ? ' The tests failed on the base version, as a negative control must.'
      : ' The negative control did not hold.'
    : ''
  const treeText = o.tree && o.tree.untouched !== true
    ? ' The control-run stage left the working tree unverified: what stands in it now is nobody\'s statement.'
    : ''
  const gapText = gap.length
    ? ` ${gap.length} gap(s) stand in this return and in the closing report it carries: they are unfinished work, not a silent retry.`
    : ''
  const folded = o.folded || []
  const foldText = folded.length
    ? ` The depth folded ${folded.join(', ')} into the short form: those levels were not written as files of their own.`
    : ''
  return `${Number(o.done || 0)} of ${Number(o.planned || 0)} stage(s) ran (${o.range || ''}), ${runText}.${ctl}${treeText}${keyText}${foldText}${gapText}${stopped}`
}
function makeResult(s) {
  const o = s || {}
  const stages = o.stages || []
  const done = o.done || []
  const nc = o.control || null
  // what the control run left in the working tree: a tree it changed, and a tree it never spoke
  // about, are both unverified ground under every later stage, so they take the run down and name
  // the stage that left them — the gap alone would stand in a return whose `ok` says finished
  const tr = o.tree || null
  const gap = (o.gap || []).slice()
  if (nc && nc.gap) gap.push(nc.gap)
  if (tr && tr.gap) gap.push(`the control-run stage: ${tr.gap}`)
  // the closing report travels in this return, never in a file: the harness lets no subagent write
  // a report file. A run that came back without one says nothing about itself, so that is a gap of
  // it and it takes `ok` down like any unverified ground
  const report = String(o.report == null ? '' : o.report).trim()
  const reportOk = report !== ''
  if (!reportOk) gap.push(o.reportGap || 'the closing report came back empty: this run states nothing about itself')
  const blocked = o.blocked ? blockedLine(o.blocked) : null
  const run = o.run == null ? null : String(o.run)
  // the oracle stages of this range: with one of them in the range the check decides the result,
  // without one the promise of the range is that every stage of it ran
  const oracle = stages.indexOf('executor') !== -1 || stages.indexOf('fixer') !== -1
  const ranAll = stages.length > 0 && stages.every(s => done.indexOf(s) !== -1)
  // a range the depth folded to nothing: no stage was planned and none was promised, so the run is
  // a finished no-op — `ok:false` with no blocked line and no gap would read as a failure nobody wrote
  const noop = stages.length === 0 && (o.folded || []).length > 0
  // what the chain found in the key document decides this run too: a specification it could not
  // settle never turns into a finished run because the oracle below it passed
  const key = o.key == null ? true : o.key !== false
  const treeOk = !tr || tr.untouched === true
  const ok = !blocked && key && (!nc || nc.ok) && treeOk && reportOk && (noop || (oracle ? run === 'PASS' : ranAll))
  const first = stages[0] || ''
  const last = stages.length ? stages[stages.length - 1] : ''
  const res = {
    out: o.out == null ? null : o.out,
    ok,
    range: `${o.from || first}..${o.until || last}`,
    stages,
    done,
    report: reportOk ? report : null,
    files: o.files || [],
    run,
    oracle,
    control: nc ? { required: nc.required, ran: nc.ran, verdict: nc.verdict, ok: nc.ok } : null,
    tree: tr ? { stated: tr.stated === true, untouched: tr.untouched === true } : null,
    cycles: Number(o.cycles || 0),
    check: o.check == null ? null : o.check,
    keyCheck: key,
    folded: o.folded || [],
    gap,
    status: makeStatus({
      run, gap, oracle, out: o.out, control: nc, tree: tr, stage: o.stage, blocked, folded: o.folded || [],
      key, noop, done: done.length, planned: stages.length, range: `${o.from || first}..${o.until || last}`,
    }),
  }
  if (o.stage) res.stage = o.stage
  if (blocked) res.blocked = blocked
  return res
}

// probeStatus(s) / probeResult(s): the one return of a probe run, on the same rule. A finished run
// has a bundle per direction that ran, a critique over them and the synthesis file; a run that lost
// its synthesis, its critique or every direction is not finished, whatever else it wrote. A
// direction that came back blocked is a hole in the material the answer rests on: it stands in
// `gap` like a direction the ceiling cut, and it takes `ok` down with it — a partly failed research
// stage never returns the shape of a whole one. A direction the ceiling of A30 never seated is the
// same hole from the other side: the ceiling ends the stage and writes the gap (A30), so the run
// that asked five directions and ran two is unfinished work, and the status says both numbers.
function probeStatus(s) {
  const o = s || {}
  const gap = o.gap || []
  const asked = Number(o.directions || 0)
  const seated = Number(o.seated == null ? asked : o.seated)
  const stopped = o.blocked ? ` The run stopped at the ${o.stage || 'unnamed'} stage: ${o.blocked}` : ''
  const seatText = seated < asked
    ? ` The ceiling of ${Number(o.room || 0)} agents per stage seated ${seated} of the ${asked} direction(s) asked; the rest never started.`
    : ''
  const gapText = gap.length
    ? ` ${gap.length} direction(s) are missing from this answer — the ceiling of the stage cut them or they came back blocked — and that is a gap of it, never a second round.`
    : ''
  const where = o.out ? ` The answer stands in ${o.out}; every claim in it carries the pointer it rests on.` : ''
  return `${Number(o.bundles || 0)} of ${asked} direction(s) asked came back, ${o.critique ? 'critiqued' : 'with no critique'}, ${o.synthesis ? 'synthesised' : 'with no synthesis'}.${where}${seatText}${gapText}${stopped}`
}
function probeResult(s) {
  const o = s || {}
  const bundles = o.bundles || []
  const directions = o.directions || []
  // the directions the ceiling never seated: their gap lines are written here, with the room that
  // cut them, so no caller can hand the ceiling to the result without the run losing its `ok`
  const cut = o.cut || []
  const seated = directions.length - cut.length
  const gap = (o.gap || []).slice()
  for (let i = 0; i < cut.length; i++) {
    gap.push(`direction ${seated + i + 1} (${cut[i]}) never started: the ceiling of ${Number(o.room || 0)} agents per stage ended the research stage`)
  }
  const lost = o.blockedStages || []
  // a direction the flow started and lost is a gap of the answer, on the same line as one the
  // ceiling never seated: the synthesis was written over less material than the question asked for
  for (const s of lost) gap.push(`${s} — that direction brought nothing, so the answer rests on less material than the question asked for`)
  const blocked = o.blocked ? blockedLine(o.blocked) : null
  const ok = !blocked && !!o.out && bundles.length > 0 && !!o.critique && !!o.synthesis
    && lost.length === 0 && cut.length === 0
  const res = {
    out: o.out == null ? null : o.out,
    ok,
    directions,
    asked: directions.length,
    seated,
    cut,
    bundles,
    critique: o.critique == null ? null : o.critique,
    synthesis: o.synthesis == null ? null : o.synthesis,
    gap,
    blockedStages: o.blockedStages || [],
    status: probeStatus({
      bundles: bundles.length, directions: directions.length, seated, room: o.room,
      critique: o.critique, synthesis: o.synthesis, out: o.out, gap, stage: o.stage, blocked,
    }),
  }
  if (o.stage) res.stage = o.stage
  if (blocked) res.blocked = blocked
  return res
}

if (typeof module !== 'undefined' && module.exports) {
  module.exports = {
    CLASSES, MODEL_NAME, EFFORT_NAME, submodes, cellFor, optsFor, classUp, slotForSize, cellTokens,
    bindClass,
    roleOf, roleNames, roleAgent, roleSlot, roleClass, roleReturnsText, ceiling, ceilingHit, isBlocked, lastLine,
    blockedLine, namesOut, mustExist, outVerdict, outDir, closureReport, textResult,
    LAYOUT, taskDirOf, outForm, taskEntry, taskKeys, taskPath, runStem, writeHint, liteTarget, roleOut, roleOutPath,
    HINT_CAP, SEVERITY_ORDER, keyedFields, placeOf, placeText, parseHints, capHints, hintsOverlap, groupHints,
    maxSeverity, chainForm, pickAspects, criticSplit, parseEvidence, dedupeAnswers, splitFailures,
    hintRows, chainRows, openRowsText,
    fixerInput, confirmedOf, undeterminedOf, unansweredOf, parseAccepted, judgedInput, chainSeats,
    aspectsOrStop, chainPlan, chainEvidenceRuns, chainStatus, chainResult,
    MAKE_STAGES, stageRange, stageOn, makePlan, runVerdict, negativeControl, cycleState,
    fixerState, fixerDone, keyCheckState, controlTree, stageStop, makeStatus, makeResult,
    probeStatus, probeResult,
  }
}
