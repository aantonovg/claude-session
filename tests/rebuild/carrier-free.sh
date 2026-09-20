#!/bin/bash
# Static guard of P8: the process skill is carrier-free, and every stage row names its task file
# and its gate.
#
#   tests/rebuild/carrier-free.sh
#
# Globs (the plan's scope rule): plugins/session/skills/process/**, and the non-generated part of
# plugins/session/base/BASE.md.
#
# The rule (idea 3.3 and decision 19): a process skill fixes the stages, the task files each stage
# writes and reads, the gates and the points where the user is needed. It names no workflow, no
# agent and no tool, so the main model matches every stage to the usage contracts the session holds
# at that moment, and a newly enabled plugin widens what the process can do with no skill edit.
# What counts as naming a carrier is not a regex of this file: it is carrierFreeTokens() of the
# shared block, executed here over lib/block.js, so the carrier roster comes from one place and the
# rule is tested by mutation below instead of read. Only qualified forms match (`session:<name>`,
# an agent file name such as `tools-edit`, a workflow in a carrier shape, a tool name of the fixed
# list): the bare words `chain`, `make`, `role` and `probe` are ordinary prose ("the evidence
# chain") and never match.
#
# Deviation from the plan's P8 oracle row, stated once: the row asks for "no tool name from the
# fixed list" in `skills/process/**` AND in the non-generated part of `BASE.md`. The tool half is
# applied to the process skill only. The base text is the page that states the main session's own
# tool calls — its hard rule 1 counts "every Read, Edit, Write, Grep, Bash, MCP call" — and that
# text landed in P6 as a decided point; the carrier half (no `session:` name but `session:ask`, no
# agent name, no workflow name) is applied to the base in full.
#
# The behavior gate of this part is no part of this script: scenarios 1, 4, 6 and 10 in the `gate`
# variant, 2 in `gate-stub-on` and 3 in `gate-stub-off-deny` are read by the part's Test through
# tests/rebuild/verdicts.sh. This script only guards the text against a regression.
# Temp dirs only, no network, under 10 s.
set -u

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
P=$REPO/plugins/session
S=$P/skills/process
B=$P/base/BASE.md
BLOCK=$P/lib/block.js
CLASSES=$P/lib/classes.json
SCEN=$REPO/tests/measure/rebuild-scenarios-0.16.txt
PROCS="code mr look doc ops"

N=0; FAILS=0
pass() { N=$((N + 1)); }
fail() { echo "FAIL $1"; FAILS=$((FAILS + 1)); }
check() { local label=$1; shift; if "$@"; then pass; else fail "$label"; fi; }

T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT

# ---- g0: the files of this part ----
check "g0 lib/block.js exists: the carrier rule is executed, never grepped" test -f "$BLOCK"
check "g0 skills/process/SKILL.md exists" test -f "$S/SKILL.md"
check "g0 skills/process/core.md exists" test -f "$S/core.md"
for p in $PROCS; do
  check "g0 skills/process/$p.md exists" test -f "$S/$p.md"
done
if [ ! -f "$BLOCK" ] || [ ! -f "$S/SKILL.md" ]; then
  echo "carrier-free: FAIL $FAILS failures, $N checks passed"
  exit 1
fi

shopt -s nullglob
FILES=()
while IFS= read -r f; do FILES+=("$f"); done < <(find "$S" -type f -name '*.md' | sort)
if [ "${#FILES[@]}" -eq 0 ]; then
  fail "g0 at least one file under skills/process"
  echo "carrier-free: FAIL $FAILS failures, $N checks passed"
  exit 1
fi
pass

# ---- g1: no carrier in the process skill ----
# The scan takes its mode from the argument: `process` guards the whole rule, `base` drops the tool
# half and allows session:ask (the deviation above). A generated region is skipped: the class table
# of the base is rendered there by bin/build.sh.
cat > "$T/scan.js" <<'JS'
const fs = require('fs')
const b = require(process.argv[2])
const mode = process.argv[3]
const opts = mode === 'base' ? { tools: false, allow: ['session:ask'] } : {}
const BEGIN = ['// ---- shared block', '// ---- class table', '<!-- class table', '<!-- layout table',
  '<!-- role output table']
const END = ['// ---- end shared block', '// ---- end class table', '<!-- end class table',
  '<!-- end layout table', '<!-- end role output table']
const hits = []
for (const path of process.argv.slice(4)) {
  let lines
  // a file of the glob list nobody could read is never a clean file: it is reported like a hit,
  // or this scan would print nothing over a text it never looked at
  try { lines = fs.readFileSync(path, 'utf8').split('\n') } catch (e) {
    hits.push(`${path}:0 unreadable: ${e.message}`)
    continue
  }
  let skip = false
  lines.forEach((line, i) => {
    const s = line.trim()
    if (skip) { if (END.some(e => s.startsWith(e))) skip = false; return }
    if (BEGIN.some(x => s.startsWith(x))) { skip = true; return }
    for (const t of b.carrierFreeTokens(line, opts)) hits.push(`${path}:${i + 1} names a carrier: ${t}`)
  })
}
hits.slice(0, 20).forEach(h => console.log(h))
process.exit(hits.length ? 1 : 0)
JS
if node "$T/scan.js" "$BLOCK" process "${FILES[@]}"; then pass
else fail "g1 no workflow, agent, launch name or tool named in skills/process/**"; fi

# g1 is executed, not read: every half of the rule must be seen on a line that carries it, and a
# mutant of the shared block that drops that half must stop seeing it.
printf 'Launch session:role for the research stage.\n' > "$T/launch.md"
printf 'The tools-edit agent writes the code.\n' > "$T/agent.md"
printf 'The chain workflow reads the object.\n' > "$T/flow.md"
printf 'The stage asks through AskUserQuestion.\n' > "$T/tool.md"
printf 'The stage runs it with `Bash`.\n' > "$T/toolplain.md"
for c in launch agent flow tool toolplain; do
  check "g1 the scan sees a carrier of kind $c" \
    bash -c '! node "$1" "$2" process "$3" > /dev/null' _ "$T/scan.js" "$BLOCK" "$T/$c.md"
done
# prose that uses the same words as plain English is no carrier: this is what lets the skill say
# "the evidence chain", "make the check run", "read the intent" at all
printf 'The evidence chain makes the review; read the intent, then write the gate verdict.\nOne stage per role of the process, with its own task file.\n' > "$T/prose.md"
check "g1 plain prose with the same words is no carrier" \
  node "$T/scan.js" "$BLOCK" process "$T/prose.md"
mut() { # mut <name> <perl expression>: a mutant of the shared block that drops one half of the rule
  perl -pe "$2" "$BLOCK" > "$T/$1.js"
  check "g1 the mutant $1 is really a mutation" bash -c '! cmp -s "$1" "$2"' _ "$BLOCK" "$T/$1.js"
}
mut nolaunch "s/\\\\\\\\b\\\$\{rxEsc\(CARRIER_PREFIX\)\}:\[a-z\]\[a-z0-9-\]\*/(?!x)x/"
check "g1 the mutant that drops the launch-name shape is caught" \
  bash -c 'node "$1" "$2" process "$3" > /dev/null' _ "$T/scan.js" "$T/nolaunch.js" "$T/launch.md"
mut notool "s/'AskUserQuestion'/'ZzNeverAToolName'/"
check "g1 the mutant that drops a tool name is caught" \
  bash -c 'node "$1" "$2" process "$3" > /dev/null' _ "$T/scan.js" "$T/notool.js" "$T/tool.md"
mut notoolshape 's/\x60\(\?:/ZZ(?:/'
check "g1 the mutant that drops the tool shape is caught" \
  bash -c 'node "$1" "$2" process "$3" > /dev/null' _ "$T/scan.js" "$T/notoolshape.js" "$T/toolplain.md"
mut noagent "s/'tools-edit'/'zz-never-an-agent'/"
check "g1 the mutant that drops an agent of the roster is caught" \
  bash -c 'node "$1" "$2" process "$3" > /dev/null' _ "$T/scan.js" "$T/noagent.js" "$T/agent.md"

# ---- g2: the base text, carrier half ----
if [ -f "$B" ]; then
  check "g2 the base names no carrier but session:ask" node "$T/scan.js" "$BLOCK" base "$B"
  # the whitelist is one name, not a switch: another launch name in the base is still a hit
  { cat "$B"; printf 'Send the research stage to session:probe.\n'; } > "$T/base-extra.md"
  check "g2 a second launch name in the base is caught" \
    bash -c '! node "$1" "$2" base "$3" > /dev/null' _ "$T/scan.js" "$BLOCK" "$T/base-extra.md"
  check "g2 the class table of the base is a generated region" grep -q '<!-- class table' "$B"
else
  fail "g2 plugins/session/base/BASE.md exists"
fi

# ---- g3: every stage row names its task file and its gate ----
# The master table of SKILL.md fixes the stage keys; every process file instantiates the same keys
# with its own gate wording. A task file cell names a path of lib/task-layout.md (read through
# LAYOUT of the shared block), never a name this test invents.
cat > "$T/table.py" <<'PY'
import json, re, subprocess, sys
block, skill = sys.argv[1], sys.argv[2]
paths = json.loads(subprocess.run(
    ['node', '-e', 'process.stdout.write(JSON.stringify(Object.values(require(process.argv[1]).LAYOUT.files).map(e => e.path)))', block],
    capture_output=True, text=True, check=True).stdout)
HEAD = ['stage', 'task file', 'gate', 'lite', 'std', 'full']
def cells(line):
    return [c.strip() for c in line.strip().strip('|').split('|')]
def table(path):
    rows, head, on = [], None, False
    for line in open(path, encoding='utf-8').read().split('\n'):
        if not line.strip().startswith('|'):
            on = False
            continue
        c = cells(line)
        if head is None or not on:
            low = [x.lower().strip('`*_ ') for x in c]
            if low[:1] == ['stage'] and len(low) == 6:
                head, on = low, True
                rows = []
                continue
            on = False
            continue
        if set(''.join(c)) <= set('-: '):
            continue
        rows.append(c)
    return head, rows
def key(cell):
    m = re.search(r'`([a-z][a-z0-9-]*)`', cell)
    return m.group(1) if m else None
bad = []
def read(path, want=None):
    head, rows = table(path)
    if head is None:
        bad.append('%s: no stage table with the six columns %s' % (path, '/'.join(HEAD)))
        return None
    for i, h in enumerate(HEAD):
        if not head[i].startswith(h):
            bad.append('%s: column %d is %r, want %r' % (path, i + 1, head[i], h))
    keys = []
    for r in rows:
        k = key(r[0])
        if k is None:
            bad.append('%s: row %r names no stage key in backticks' % (path, r[0][:40]))
            continue
        keys.append(k)
        if not any(p in r[1] for p in paths):
            bad.append('%s: stage %s names no task file of the layout (%r)' % (path, k, r[1][:40]))
        if len(r[2].split()) < 3:
            bad.append('%s: stage %s names no gate condition (%r)' % (path, k, r[2][:40]))
        for i, d in enumerate(('lite', 'std', 'full')):
            if not r[3 + i].strip(' -'):
                bad.append('%s: stage %s says nothing at depth %s' % (path, k, d))
    if len(keys) != len(set(keys)):
        bad.append('%s: a stage key is written twice' % path)
    if want is not None and set(keys) != set(want):
        bad.append('%s: stage keys %s, want %s' % (path, sorted(set(keys)), sorted(set(want))))
    return keys
master = read(skill)
if master is not None:
    if len(master) < 8:
        bad.append('%s: the master table has %d stages, want the full ladder' % (skill, len(master)))
    for path in sys.argv[3:]:
        read(path, master)
for b in bad[:12]:
    print(b)
sys.exit(1 if bad else 0)
PY
PFILES=()
for p in $PROCS; do [ -f "$S/$p.md" ] && PFILES+=("$S/$p.md"); done
if [ "${#PFILES[@]}" -gt 0 ]; then
  check "g3 every stage row names its task file, its gate and every depth" \
    python3 "$T/table.py" "$BLOCK" "$S/SKILL.md" "${PFILES[@]}"
  # executed, not read: a row with an empty gate cell and a process file that drops a stage must
  # both turn this check red
  mkdir -p "$T/t1"
  python3 - "$S/SKILL.md" "$T/t1/SKILL.md" <<'PY'
import re, sys
out, done = [], False
for line in open(sys.argv[1], encoding='utf-8').read().split('\n'):
    c = [x.strip() for x in line.strip().strip('|').split('|')]
    if not done and line.strip().startswith('|') and len(c) == 6 and re.search(r'`[a-z]', c[0]):
        c[2] = ''
        line = '| ' + ' | '.join(c) + ' |'
        done = True
    out.append(line)
open(sys.argv[2], 'w', encoding='utf-8').write('\n'.join(out))
PY
  check "g3 a stage row with no gate condition is caught" \
    bash -c '! python3 "$1" "$2" "$3" > /dev/null' _ "$T/table.py" "$BLOCK" "$T/t1/SKILL.md"
  grep -v '^| `closure`' "${PFILES[0]}" > "$T/t1/short.md"
  check "g3 a process file that drops a stage of the master table is caught" \
    bash -c '! python3 "$1" "$2" "$3" "$4" > /dev/null' _ "$T/table.py" "$BLOCK" "$S/SKILL.md" "$T/t1/short.md"
else
  fail "g3 at least one process file"
fi

# ---- g4: what core.md owes (the shared rules every process file reads first) ----
C=$S/core.md
if [ -f "$C" ]; then
  check "g4 core.md names the task directory under the projects tree" \
    grep -Fq 'tasks/<date>-<slug>' "$C"
  check "g4 core.md names the pointer to the current task" grep -Fq 'tasks/current' "$C"
  check "g4 core.md names the ledger file" grep -Fq 'ledger.jsonl' "$C"
  check "g4 core.md carries the cost rules" grep -qi 'cost rules' "$C"
  check "g4 core.md carries the harness gate" grep -qi 'harness gate' "$C"
  check "g4 core.md carries the Sources block" grep -Fq 'Sources' "$C"
  check "g4 core.md carries the Oracles block" grep -Fq 'Oracles' "$C"
  check "g4 core.md names the unavailable line of both blocks" grep -Fq 'wanted, unavailable' "$C"
  for l in a b c d e; do
    check "g4 core.md carries ladder level $l" grep -Eq "^\| $l \|" "$C"
  done
  check "g4 core.md states the artifact chain" grep -qi 'artifact chain' "$C"
  check "g4 core.md states how a review is read as an evidence chain" grep -qi 'evidence chain' "$C"
  check "g4 core.md states the critic class raise" grep -qi 'raise the class' "$C"
  check "g4 core.md forbids lowering the class" grep -qi 'never lower' "$C"
  for f in Status Evidence Assumptions Unresolved Next; do
    check "g4 core.md carries the status field $f" grep -Eq "^\`?$f" "$C"
  done
  check "g4 core.md carries the loop guard" grep -qi 'loop guard' "$C"
  check "g4 core.md states that done needs evidence" grep -qi 'done.*evidence\|evidence.*done' "$C"
  check "g4 core.md states the resume from the task files" grep -qi 'resume' "$C"
else
  fail "g4 skills/process/core.md exists"
fi

# ---- g5: SKILL.md — the two axes, the depth lists and the ceilings of lib/classes.json ----
K=$S/SKILL.md
if [ -f "$K" ]; then
  fm=$(awk 'NR==1&&/^---$/{f=1; next} f&&/^---$/{exit} f{print}' "$K")
  body=$(awk 'NR==1&&/^---$/{f=1; next} f&&/^---$/{f=0; next} !f{print}' "$K")
  check "g5 SKILL.md frontmatter name is process" grep -Fxq 'name: process' <<<"$fm"
  check "g5 SKILL.md frontmatter description" grep -Eq '^description: .+' <<<"$fm"
  check "g5 SKILL.md is not model-invoked" grep -Fxq 'disable-model-invocation: true' <<<"$fm"
  # the two axes are the arguments hooks/modes.sh already parses: the task type and the depth
  for t in $PROCS; do
    check "g5 SKILL.md names the task type $t" grep -qE "\`$t\`" <<<"$body"
  done
  for d in lite std full; do
    check "g5 SKILL.md names the depth $d" grep -qE "\`$d\`" <<<"$body"
  done
  check "g5 SKILL.md states the class default" grep -Fq 'c3' <<<"$body"
  check "g5 SKILL.md states the depth default" grep -qi 'default' <<<"$body"
  check "g5 SKILL.md states that a dash step is not done at all" \
    grep -qi 'not done at all' <<<"$body"
  check "g5 SKILL.md states the intent gate at std and full" \
    grep -qi 'no stage starts before' <<<"$body"
  check "g5 SKILL.md states that lite starts at once" grep -qi 'at once' <<<"$body"
  # the ceilings are quoted from lib/classes.json, not invented here: a changed number in that file
  # must turn this red
  for d in lite std full; do
    a=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["ceilings"][sys.argv[2]]["agents"])' "$CLASSES" "$d")
    c=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["ceilings"][sys.argv[2]]["cycles"])' "$CLASSES" "$d")
    check "g5 SKILL.md carries the agent ceiling of $d ($a)" \
      grep -qE "(^|[^0-9])$a([^0-9]|$)" <<<"$(grep -i "$d" <<<"$body")"
    check "g5 SKILL.md carries the fix-cycle ceiling of $d ($c)" \
      grep -qE "(^|[^0-9])$c([^0-9]|$)" <<<"$(grep -i "$d" <<<"$body")"
  done
  check "g5 SKILL.md sends a hit ceiling into the task files and the report" \
    grep -qi 'ceiling' <<<"$body"
  check "g5 SKILL.md tells the main model to pick carriers from the contracts" \
    grep -qi 'contract' <<<"$body"
else
  fail "g5 skills/process/SKILL.md exists"
fi

# ---- g6: ops.md carries the control-call file of decision 17 ----
O=$S/ops.md
if [ -f "$O" ]; then
  check "g6 ops.md names the control-call file" grep -qi 'control call' "$O"
  check "g6 ops.md states the expected result per command" grep -qi 'expected result' "$O"
  check "g6 ops.md runs the calls before and after the change" \
    grep -qi 'before the change' "$O"
  check "g6 ops.md names the pair of runs as the verdict" grep -qi 'after' "$O"
else
  fail "g6 skills/process/ops.md exists"
fi

# ---- g7: the six scenario texts this part's gate runs ----
# The verdicts themselves are read by the part's Test through tests/rebuild/verdicts.sh; here only
# the texts are guarded, so a key can never go missing from the scenario file.
if [ -f "$SCEN" ]; then
  for k in carrier-pick labels intent-gate compact-contracts plugin-widens deny-completes; do
    block=$(awk -v k="$k" '$0 ~ "^"k"[[:space:]]"{f=1} f&&/^[A-Za-z][A-Za-z0-9_-]*[[:space:]].*prompts:/&&$1!=k{exit} f{print}' "$SCEN")
    check "g7 the scenario $k exists" test -n "$block"
    [ -n "$block" ] || continue
    check "g7 $k names its prompts" grep -q 'prompts:' <<<"$block"
    for fld in base PASS; do
      check "g7 $k carries the field $fld" grep -qE "^[[:space:]]+$fld:" <<<"$block"
    done
    check "g7 $k judges only the lines after the finish notice" \
      grep -qi 'only the lines after' <<<"$block"
  done
  # the four scenarios of the gate that this part writes: each says a launch of an old carrier name
  # is a FAIL, which is what the gate measures
  for k in carrier-pick labels intent-gate compact-contracts; do
    block=$(awk -v k="$k" '$0 ~ "^"k"[[:space:]]"{f=1} f&&/^[A-Za-z][A-Za-z0-9_-]*[[:space:]].*prompts:/&&$1!=k{exit} f{print}' "$SCEN")
    [ -n "$block" ] || continue
    check "g7 $k gates the reading prompt on the workflow finish notice" \
      grep -qE "^[[:space:]]+finish: [0-9]+ [0-9]+$" <<<"$block"
    check "g7 $k makes a launch of an old carrier name a FAIL" \
      grep -qi 'old' <<<"$block"
  done
  # the prompts of a carrier-free run never name the carrier themselves, or the scenario would
  # prove nothing about the skill: the main session picks it from its contracts
  block=$(awk '$0 ~ "^carrier-pick[[:space:]]"{f=1} f&&/^[A-Za-z][A-Za-z0-9_-]*[[:space:]].*prompts:/&&$1!="carrier-pick"{exit} f{print}' "$SCEN")
  if [ -n "$block" ]; then
    prompts=$(printf '%s\n' "$block" | awk '/prompts:/{sub(/^.*prompts:/, ""); print}')
    check "g7 the carrier-pick prompt names no workflow of the new set" \
      bash -c '! grep -Eq "session:(role|chain|make|probe)" <<<"$1"' _ "$prompts"
  fi
else
  fail "g7 tests/measure/rebuild-scenarios-0.16.txt exists"
fi

if [ "$FAILS" -eq 0 ]; then echo "carrier-free: PASS $N"; exit 0; fi
echo "carrier-free: FAIL $FAILS failures, $N checks passed"
exit 1
