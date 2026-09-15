export const meta = {
  name: 'test-session',
  description: 'Runs a scenarios file against real Claude Code sessions in tmux and judges the transcripts: session-driver starts the driver detached and waits on its done-file, transcript-analyst writes verdicts.md, the run returns the failing scenario ids. Args: scenarios (string, absolute path, required), runner (string, absolute path to the driver script, required), out (string, absolute artifact dir the driver writes result.log, *.jsonl and done into, required), ids (array of strings, default all scenarios), parser (string, absolute path to a verdict script, default none), budget (number, minutes, default 120), class (string c1-c5, default c3), submodes (array of strings from no-sonnet no-opus no-fable, default []). Output: <out>/verdicts.md. BLOCKED stage stops with a report.',
  whenToUse: 'Behavior test of a skill, agent or base rule in fresh sessions on a chosen model; replaces the manual driver plus parser loop.',
  phases: [{ title: 'Drive' }, { title: 'Judge' }],
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
const blocked = r => r == null || /BLOCKED:/.test(String(r))
const last = r => String(r || '').trim().split('\n').pop()
const STYLE = 'Plain English, caveman ultra; the return value is data. No skills needed for this step. On a permission denial stop at once and return BLOCKED: <denied action>.'
// ---- end shared block ----

const SCN = A.scenarios
const RUN = A.runner
const OUT = A.out
if (!SCN || !RUN || !OUT) throw new Error('args.scenarios, args.runner and args.out (absolute paths) are required')
const IDS = A.ids || []
const PARSER = A.parser || null
const BUDGET = A.budget || 120
const NAME = [CLS, ...SUBS, 'test-session'].join('-')
log(`${NAME} | scenarios=${SCN} runner=${RUN} out=${OUT} ids=${IDS.length || 'all'} parser=${PARSER || 'none'} budget=${BUDGET}m slots=${ROW.join('/')}`)

phase('Drive')
const drive = await agent(`Session driver. Scenarios file: ${SCN}. Driver script: ${RUN}. Scenario ids: ${IDS.length ? IDS.join(' ') : 'all (no arguments)'}. Artifact directory: ${OUT} (the driver writes result.log, <id>.jsonl, <id>.pane.txt and done there).
Remove a stale ${OUT}/done first. Start the driver detached with nohup, log to ${OUT}/driver.log, wait for ${OUT}/done in one Bash call with a ${BUDGET}-minute timeout, then list the artifacts. Kill every tmux session the driver created before returning.
Return: artifact directory, result.log path, jsonl count, last driver.log line; last line DONE or BLOCKED: <reason>. ${STYLE}`, opts('sonnet', 'drive', { agentType: 'session-driver', phase: 'Drive' }))
if (blocked(drive)) return { stage: 'drive', blocked: last(drive), out: OUT }

phase('Judge')
const judge = await agent(`Transcript analyst. Judge the session run in ${OUT}: scenario definitions and PASS rules in ${SCN}; transcripts ${OUT}/<id>.jsonl; the driver's own verdict lines in ${OUT}/result.log${PARSER ? `; verdict script ${PARSER} (usage: python3 ${PARSER} <jsonl> <id>)` : ''}.
For every scenario decide PASS, FAIL or UNKNOWN over the whole turn (all assistant records after the prompt), quoting the decisive line. Write ${OUT}/verdicts.md: one line per scenario, then a "FAIL:" line listing the failing ids or "FAIL: none".
Return: the per-scenario lines, then DONE or BLOCKED: <reason>, then exactly one final line "FAIL: <ids separated by commas, or none>". ${STYLE}`, opts('sonnet', 'judge', { agentType: 'transcript-analyst', phase: 'Judge' }))
if (blocked(judge)) return { stage: 'judge', blocked: last(judge), out: OUT }

const failLines = String(judge).split('\n').filter(l => /^\s*FAIL\b/.test(l))
const lastFail = failLines.length ? failLines[failLines.length - 1] : ''
const failing = /^\s*FAIL:\s*none/i.test(lastFail) ? [] : [...new Set(lastFail.match(/\bS\d+\b/g) || [])]
return {
  class: CLS, submodes: SUBS, slots: SLOT, out: OUT, verdicts: `${OUT}/verdicts.md`,
  failing, next: failing.length ? `Read verdicts.md; fix the rule behind ${failing.join(', ')}; rerun with ids.` : 'All scenarios pass.',
}
