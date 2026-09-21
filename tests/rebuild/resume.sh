#!/bin/bash
# Static oracle of two P9 gate repairs that make a behavior structural instead of a reading of text.
#   tests/rebuild/resume.sh
# r1 resumeState(), resumeLine(), intentStopDue(), intentStopRow() of lib/block.js, executed, and a
#    mutant of each decision the test must catch.
# r2 hooks/modes.sh prints the resume line on SessionStart clear, compact and resume with a live
#    tasks/current pointer, and never on startup or without a pointer; hooks/ledger-stop.sh writes the
#    intent stop row once, at the first stop row of the task.
# r3 the intent form: skills/process/intent-form.md exists, carries the Task, Depth, Acceptance
#    criteria and aspects lines, its default aspect table equals defaultAspects() of lib/block.js,
#    intentAspects() reads the approved line back (with a mutant), and SKILL.md cites the form and
#    the resume line.
# r4 the real clear of gate run base/20260921-084315 replayed from fixtures/resume-clear through both
#    hooks: a launch row left with agent_id null still gets its stop row and the resume line names
#    the stage done; a block.js that binds no such row fails the replay.
# A throwaway HOME for the hook scripts: no session starts, no credential, keychain or account file
# is read or copied. Temp dirs only, no network, under 10 s.
set -u

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
P=$REPO/plugins/session
BLOCK=$P/lib/block.js
FORM=$P/skills/process/intent-form.md
SKILL=$P/skills/process/SKILL.md

N=0; FAILS=0
pass() { N=$((N + 1)); }
fail() { echo "FAIL $1"; FAILS=$((FAILS + 1)); }
check() { local label=$1; shift; if "$@"; then pass; else fail "$label"; fi; }

command -v jq >/dev/null 2>&1 || { echo "resume: FAIL jq is required"; exit 1; }
command -v node >/dev/null 2>&1 || { echo "resume: FAIL node is required"; exit 1; }
T=$(mktemp -d) || exit 1
REAL_HOME=$HOME
trap 'rm -rf "$T"' EXIT

# ---- r1: the pure functions, executed over one block.js; the same checks run over mutants ----
cat > "$T/r1.js" <<'JS'
const b = require(process.argv[2])
const J = rows => rows.map(r => JSON.stringify(r)).join('\n')
const launch = (stage, id, depth) => ({ ts: 't', stage, agent_id: id, depth: depth || 'std', label: 'x' })
const stop = (id, depth) => ({ ts: 't', agent_id: id, event: 'stop', depth: depth || 'std' })
const bad = []
const eq = (name, got, want) => { if (JSON.stringify(got) !== JSON.stringify(want)) bad.push(`${name}: got ${JSON.stringify(got)}`) }
// the resume gate run: subtasks stopped, specification launched and not stopped
const run = [launch('subtasks', 'wf_1'), stop('wf_1'), launch('specification', 'wf_2')]
eq('due after the first stop', b.intentStopDue(J(run), ['intent.md', 'ledger.jsonl']), true)
eq('not due without an intent file', b.intentStopDue(J(run), ['ledger.jsonl']), false)
eq('not due before any stop', b.intentStopDue(J([launch('subtasks', 'wf_1')]), ['intent.md']), false)
const row = b.intentStopRow(J(run), 'T')
eq('intent stop row', row, { ts: 'T', stage: 'intent', event: 'stop', depth: 'std' })
const led = J(run.concat([row]))
eq('never due twice', b.intentStopDue(led, ['intent.md']), false)
const s = b.resumeState(led, ['intent.md'])
eq('state', [s.depth, s.done, s.last, s.next, s.intent], ['std', ['intent', 'subtasks'], 'subtasks', 'specification', true])
eq('no intent stop row: not confirmed', b.resumeState(J(run), ['intent.md']).intent, false)
eq('a launch row without its stop row is not done', b.resumeState(J([launch('subtasks', 'wf_1')]), []).done, [])
eq('a broken line is skipped', b.resumeState(led + '\n{broken', ['intent.md']).next, 'specification')
// lite skips the folded and dashed stages: result follows scenarios
const lite = J([launch('scenarios', 'a', 'lite'), stop('a', 'lite')])
eq('lite next', b.resumeState(lite, ['task.md']).next, 'result')
const line = b.resumeLine('/x/tasks/d', led, ['intent.md'], 'Review aspects: simplicity')
for (const want of ['Open task: /x/tasks/d', 'Next stage: specification', 'The intent is confirmed', 'intent, subtasks', 'Approved review aspects: simplicity'])
  if (line.indexOf(want) === -1) bad.push(`line lacks [${want}]: ${line}`)
// a launch row the session left without an id (gate run base/20260921-084315)
const nul = { ts: 't', stage: 'subtasks', step: 1, depth: 'std', label: 'x', agent_id: null }
const head = '{"message":{"content":"out: /h/tasks/d/subtasks.md"}}'
const u = b.unnamedStopRow(J([nul]), 'wf_9', 'T', head, '/h/tasks/d/')
eq('unnamed stop row', u, { ts: 'T', agent_id: 'wf_9', event: 'stop', stage: 'subtasks', step: 1, depth: 'std', label: 'x' })
eq('unnamed: another task dir binds nothing', b.unnamedStopRow(J([nul]), 'wf_9', 'T', head, '/h/tasks/e'), null)
eq('unnamed: a bound row binds nothing twice', b.unnamedStopRow(J([nul, u]), 'wf_8', 'T', head, '/h/tasks/d'), null)
eq('unnamed: a stop of this id stands', b.unnamedStopRow(J([nul, { ts: 't', stage: 'x', agent_id: 'wf_9' }]), 'wf_9', 'T', head, '/h/tasks/d'), null)
eq('unnamed: the bound stage is done', b.resumeState(J([nul, u]), ['intent.md']).done, ['subtasks'])
eq('unnamed: due after the bound stop', b.intentStopDue(J([nul, u]), ['intent.md']), true)
// the intent form
eq('default aspects std', b.defaultAspects('std'), ['reliability', 'simplicity'])
eq('default aspects full', b.defaultAspects('full'), ['reliability', 'simplicity', 'testability'])
eq('aspects line read back', b.intentAspects('Task: x\n**Review aspects:** simplicity, `testability` (approved by the user)\n'), ['simplicity', 'testability'])
eq('no aspects line', b.intentAspects('Task: x'), null)
if (bad.length) { console.log(bad.join('\n')); process.exit(1) }
JS
check "r1 the pure functions of the resume line and the intent form hold" node "$T/r1.js" "$BLOCK"

mutant() { # <label> <python regex> <replacement>: a mutant block.js the r1 checks must reject
  python3 - "$BLOCK" "$T/m.js" "$2" "$3" <<'PY'
import re, sys
s = open(sys.argv[1]).read()
m, n = re.subn(sys.argv[3], sys.argv[4], s, count=1)
open(sys.argv[2], 'w').write(m)
sys.exit(0 if n == 1 else 1)
PY
  check "r1 mutant $1 applied" test $? -eq 0
  check "r1 mutant $1 is caught" bash -c '! node "$1" "$2" >/dev/null 2>&1' _ "$T/r1.js" "$T/m.js"
}
mutant "next stage off by one" 'i > lastIdx' 'i >= lastIdx'
mutant "intent row written twice" "if \(rows\.some\(r => r\.event === 'stop' && r\.stage === 'intent'\)\) return false" ''
mutant "launch row counted without its stop row" 'stopped\.has\(r\.agent_id\) && PROCESS_STAGES' 'PROCESS_STAGES'
mutant "unnamed stop bound without the task dir" "if \(!id \|\| !dir \|\| String\(agentHead \|\| ''\)\.indexOf\(dir \+ '/'\) === -1\) return null" ''
mutant "aspects note kept" "replace\(/\\\\\(\[\^\)\]\*\\\\\)/g, ' '\)" "replace(/x^/g, ' ')"

# ---- r2: the hooks, over a throwaway HOME ----
HOME=$T/home; export HOME
mkdir -p "$HOME"
case "$HOME" in "$REAL_HOME"|"$REAL_HOME"/*) echo "resume: FAIL sandbox HOME inside the real home"; exit 1 ;; esac
CWD=$T/proj; mkdir -p "$CWD"
ENC=$(printf '%s' "$CWD" | sed 's#[^A-Za-z0-9-]#-#g')
D=$HOME/.claude/projects/$ENC/tasks/2026-01-01-demo
mkdir -p "$D/reviews" "$D/evidence"
printf 'Task: demo\nReview aspects: simplicity\n' > "$D/intent.md"
printf '%s\n' '{"ts":"t","stage":"subtasks","step":1,"role":"r","kind":"workflow","class":"c3","submodes":[],"depth":"std","slot":"main","label":"l","agent_id":"wf_1"}' > "$D/ledger.jsonl"
printf '%s\n' '{"ts":"t","stage":"specification","step":1,"role":"r","kind":"workflow","class":"c3","submodes":[],"depth":"std","slot":"main","label":"l","agent_id":"wf_2"}' >> "$D/ledger.jsonl"
stophook() { jq -nc --arg c "$CWD" --arg a "$1" '{cwd:$c, agent_id:$a, session_id:"s1"}' | bash "$P/hooks/ledger-stop.sh"; }
ctx() { jq -nc --arg c "$CWD" --arg s "$1" '{hook_event_name:"SessionStart", session_id:"s1", source:$s, cwd:$c}' \
  | bash "$P/hooks/modes.sh" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null; }
check "r2 no pointer: no resume line after a clear" bash -c '! printf "%s" "$1" | grep -q "Open task:"' _ "$(ctx clear)"
echo "$D" > "$(dirname "$D")/current"
stophook wf_1
check "r2 the stop row and one intent stop row" test "$(jq -rc 'select(.event=="stop") | .stage // .agent_id' "$D/ledger.jsonl" | tr '\n' ' ')" = "wf_1 intent "
stophook wf_2
check "r2 the intent stop row is written once" test "$(grep -c '"stage":"intent"' "$D/ledger.jsonl")" -eq 1
# back to the gate run's state: wf_2 not stopped
grep -v '"agent_id":"wf_2","event":"stop"' "$D/ledger.jsonl" > "$T/l" && cp "$T/l" "$D/ledger.jsonl"
for src in clear compact resume; do
  out=$(ctx $src)
  check "r2 $src: resume line names the task, the next stage and the confirmed intent" bash -c \
    'printf "%s" "$1" | grep -q "Open task: $2 (depth std)" && printf "%s" "$1" | grep -q "Next stage: specification" && printf "%s" "$1" | grep -q "The intent is confirmed" && printf "%s" "$1" | grep -q "Approved review aspects: simplicity"' _ "$out" "$D"
  check "r2 $src: the verification line stays" bash -c 'printf "%s" "$1" | grep -q "lib/verification.md"' _ "$out"
done
check "r2 startup: no resume line" bash -c '! printf "%s" "$1" | grep -q "Open task:"' _ "$(ctx startup)"
echo "$T/nowhere" > "$(dirname "$D")/current"
check "r2 a dead pointer: no resume line" bash -c '! printf "%s" "$1" | grep -q "Open task:"' _ "$(ctx clear)"
HOME=$REAL_HOME; export HOME

# ---- r4: the real clear of gate run base/20260921-084315 (commit e97f51c), replayed ----
# fixtures/resume-clear holds that run's task directory as it stood at the clear (the launch row the
# session wrote before the launch, with agent_id null, and nothing after it), its tasks/current
# pointer, the first record of the one agent's transcript, and the two hook inputs rebuilt from the
# transcript (SubagentStop of agent ab4d7e3b85c01fe32 of run wf_71063446-f6e, SessionStart clear).
# Paths are relocated through @TASKDIR@, @PROJDIR@ and @CWD@. The run saw "No stage has a stop row
# yet. Next stage: intent." although subtasks.md had been written by a finished launch.
FX=$REPO/tests/rebuild/fixtures/resume-clear
replay() { # <plugin root> <home>: prints the resume line after the stop and the clear
  local root=$1 h=$2 cwd enc pd td
  cwd=$h/proj/project-resume; mkdir -p "$cwd"
  enc=$(printf '%s' "$cwd" | sed 's#[^A-Za-z0-9-]#-#g'); pd=$h/.claude/projects/$enc
  td=$pd/tasks/2026-09-21-slug-max-length
  mkdir -p "$td" "$pd/9f23b1b2-f17c-4d7d-b8f9-73985bfc4508/subagents/workflows/wf_71063446-f6e"
  cp -R "$FX/task/." "$td/"
  rel() { sed -e "s|@TASKDIR@|$td|g" -e "s|@PROJDIR@|$pd|g" -e "s|@CWD@|$cwd|g" "$1"; }
  rel "$FX/current" > "$pd/tasks/current"
  rel "$FX/agent-ab4d7e3b85c01fe32.jsonl" > "$pd/9f23b1b2-f17c-4d7d-b8f9-73985bfc4508/subagents/workflows/wf_71063446-f6e/agent-ab4d7e3b85c01fe32.jsonl"
  rel "$FX/subagent-stop.json" | HOME=$h bash "$root/hooks/ledger-stop.sh"
  rel "$FX/session-start-clear.json" | HOME=$h bash "$root/hooks/modes.sh" 2>/dev/null \
    | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null | grep '^Open task:'
  printf 'STOPROWS %s\n' "$(jq -rc 'select(.event=="stop") | .stage // "-"' "$td/ledger.jsonl" 2>/dev/null | tr '\n' ' ')"
}
r4ok() { # <replay output>: the finished launch has its stop row and the line names subtasks done
  printf '%s' "$1" | grep -q 'STOPROWS subtasks intent ' \
    && printf '%s' "$1" | grep -q 'Stages with a stop row, done: intent, subtasks; last: subtasks\.' \
    && printf '%s' "$1" | grep -q 'Next stage: specification\.' \
    && printf '%s' "$1" | grep -q 'The intent is confirmed'
}
export -f r4ok
out=$(replay "$P" "$T/h4")
check "r4 the real clear: stop row for the null-id launch, resume line names subtasks done [$(printf '%s' "$out" | tr '\n' ' ' | cut -c1-400)]" r4ok "$out"
# the same replay over a plugin copy whose block.js binds no launch row without an id: must fail
mkdir -p "$T/pm/lib"; cp -R "$P/hooks" "$T/pm/hooks"
python3 - "$BLOCK" "$T/pm/lib/block.js" <<'PY'
import re, sys
s = open(sys.argv[1]).read()
m, n = re.subn(r"const open = rows\.filter\(", "const open = [].filter(", s, count=1)
open(sys.argv[2], 'w').write(m); sys.exit(0 if n == 1 else 1)
PY
check "r4 mutant no binding applied" test $? -eq 0
check "r4 mutant no binding is caught by the replay" bash -c '! r4ok "$1"' _ "$(replay "$T/pm" "$T/h4m")"

# ---- r3: the intent form and the two statements of the skill ----
check "r3 skills/process/intent-form.md exists" test -f "$FORM"
for l in 'Task:' 'Depth:' 'Acceptance criteria:' "$(node -e 'process.stdout.write(require(process.argv[1]).ASPECTS_HEAD)' "$BLOCK"):"; do
  check "r3 the form carries the line [$l]" grep -q "^$l" "$FORM"
done
for d in std full; do
  want=$(node -e 'process.stdout.write(require(process.argv[1]).defaultAspects(process.argv[2]).join(", "))' "$BLOCK" $d)
  check "r3 the form's $d row equals defaultAspects($d)" grep -qF "| \`$d\` | $want |" "$FORM"
done
check "r3 the form's aspects line reads back through intentAspects()" node -e '
  const b = require(process.argv[1]); const t = require("fs").readFileSync(process.argv[2], "utf8")
  const a = b.intentAspects(t); if (!Array.isArray(a)) process.exit(1)' "$BLOCK" "$FORM"
check "r3 SKILL.md cites the form for the confirmation" bash -c 'tr "\n" " " < "$1" | grep -q "form of .intent-form\.md."' _ "$SKILL"
check "r3 SKILL.md states the resume line near its start" bash -c 'head -30 "$1" | grep -q "Open task:"' _ "$SKILL"

if [ "$FAILS" -gt 0 ]; then echo "resume: FAIL $FAILS failures, $N checks passed"; exit 1; fi
echo "resume: PASS $N checks"
