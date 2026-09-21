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
# Two rules of core.md that a gate run found broken are guarded here by their decisive words, both
# executed over lib/block.js: how a critique is read (a hint settles nothing, a claim is dropped only
# where a fact refutes it — g8, hintVerdictHits()) and what the harness gate does when the project
# denies a capability (re-send the need, never do the stage in the main session, never ask for the
# capability back — g9, phraseGap()).
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
# the roles of the new set are carriers too: a hyphenated role name counts bare, a one-word role
# name counts beside a carrier noun
printf 'The spec-author writes the specification.\n' > "$T/rolehyph.md"
printf 'The stage goes to the executor carrier.\n' > "$T/rolenoun.md"
for c in launch agent flow tool toolplain rolehyph rolenoun; do
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
  # a mutant that no longer loads proves nothing: every check below runs the mutant through a node
  # script whose exit code is read inverted, so a mutant that throws on require would be counted as
  # a caught mutant while the rule it was written for was never executed at all
  check "g1 the mutant $1 still loads" \
    bash -c 'node -e "require(process.argv[1])" "$1" 2> "$2/mut.err" || { tail -2 "$2/mut.err"; exit 1; }' \
    _ "$T/$1.js" "$T"
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
mut norolehyph "s/ROLE_HYPHEN = '-'/ROLE_HYPHEN = 'zzznotinanyname'/"
check "g1 the mutant that drops the bare hyphenated role name is caught" \
  bash -c 'node "$1" "$2" process "$3" > /dev/null' _ "$T/scan.js" "$T/norolehyph.js" "$T/rolehyph.md"
mut norolenoun "s/'role', 'roles', 'carrier', 'carriers'/'zzrole', 'zzroles', 'zzcarrier', 'zzcarriers'/"
check "g1 the mutant that drops the role-beside-a-noun shape is caught" \
  bash -c 'node "$1" "$2" process "$3" > /dev/null' _ "$T/scan.js" "$T/norolenoun.js" "$T/rolenoun.md"
# the roster is the two generated tables, never a list of this test: an empty roster is no rule
check "g1 the role roster comes from the generated tables, not from a list of this file" \
  bash -c 'n=$(node -e "process.stdout.write(String(require(process.argv[1]).roleCarrierNames().length))" "$1"); [ "$n" -ge 15 ]' \
  _ "$BLOCK"

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
entries = json.loads(subprocess.run(
    ['node', '-e', 'process.stdout.write(JSON.stringify(Object.values(require(process.argv[1]).LAYOUT.files)))', block],
    capture_output=True, text=True, check=True).stdout)
paths = [e['path'] for e in entries]
# every document and every directory of lib/task-layout.md is written by some stage of the master
# table: a place the layout declares and the mkdir of core.md creates, with no stage that writes
# it, is a gap the per-row check above cannot see (a row naming one other layout path already
# satisfies it). The `dir` rows count as well as the `file` rows — `evidence` is filled by a stage
# exactly as `report.md` is — and only the machine-written `state` rows are left out
docs = [e['path'] for e in entries if e.get('kind') in ('file', 'dir')]
HEAD = ['stage', 'task file', 'gate', 'lite', 'std', 'full']
def cells(line):
    return [c.strip() for c in line.strip().strip('|').split('|')]
def table(path):
    # every six-column stage header of the file is one table: a second one is reported, never
    # silently dropped, or the rows of the first table would go unchecked
    tables, rows, on = [], None, False
    for line in open(path, encoding='utf-8').read().split('\n'):
        if not line.strip().startswith('|'):
            on = False
            continue
        c = cells(line)
        if not on:
            low = [x.lower().strip('`*_ ') for x in c]
            if low[:1] == ['stage'] and len(low) == 6:
                rows, on = [], True
                tables.append((low, rows))
            continue
        if set(''.join(c)) <= set('-: '):
            continue
        rows.append(c)
    if len(tables) > 1:
        bad.append('%s: %d stage tables with the six columns, want one' % (path, len(tables)))
    return tables[0] if tables else (None, [])
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
    written = '\n'.join(r[1] for r in table(skill)[1])
    for p in docs:
        if p not in written:
            bad.append('%s: no stage writes %s, a document of lib/task-layout.md' % (skill, p))
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
  # a document of lib/task-layout.md that no stage row names is a gap the per-row check cannot see
  sed 's/, `decisions.md`//' "$S/SKILL.md" > "$T/t1/nodec.md"
  check "g3 a layout document no stage writes is caught" \
    bash -c '! python3 "$1" "$2" "$3" > /dev/null' _ "$T/table.py" "$BLOCK" "$T/t1/nodec.md"
  # two stage tables in one file: the rows of the first one may never be dropped in silence
  cat "$S/SKILL.md" "$S/SKILL.md" > "$T/t1/twice.md"
  check "g3 a second stage table in one file is caught" \
    bash -c '! python3 "$1" "$2" "$3" > /dev/null' _ "$T/table.py" "$BLOCK" "$T/t1/twice.md"
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
  # hooks/ledger-stop.sh selects the launch row by `.agent_id`: a schema without that field gets no
  # stop row at all, and the hook exits 0 in silence
  check "g4 the ledger row schema of core.md carries every field the stop hook selects by" \
    bash -c 'row=$(grep -m1 "^{\"ts\"" "$1") || true
      [ -n "$row" ] || { echo "core.md carries no ledger row schema"; exit 1; }
      for f in $(grep -o "select(\.[a-z_]* ==" "$2" | sed "s/select(\.//;s/ ==//" | sort -u); do
        case $row in *"\"$f\""*) ;; *) echo "the ledger schema names no $f"; exit 1 ;; esac
      done' \
    _ "$C" "$P/hooks/ledger-stop.sh"
  check "g4 core.md says agent_id is filled in after the launch returns" \
    grep -qi 'agent_id.*after the launch\|filled in from the launch result' "$C"
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
# The rule is asked for by its decisive words, through phraseGap() of the shared block: a check for
# one common word ("after") is satisfied by any prose and proves nothing.
cat > "$T/gap.js" <<'JS'
const fs = require('fs')
const b = require(process.argv[2])
const mode = process.argv[3] // 'old' = the retired carrier names, 'phrases' = the list that follows
const text = fs.readFileSync(process.argv[4], 'utf8')
const gap = mode === 'old' ? b.oldCarrierGap(text) : b.phraseGap(text, process.argv.slice(5))
gap.forEach(g => console.log('missing: ' + g))
process.exit(gap.length ? 1 : 0)
JS
O=$S/ops.md
if [ -f "$O" ]; then
  check "g6 ops.md names the control-call file" grep -qi 'control call' "$O"
  check "g6 ops.md states the expected result per command" grep -qi 'expected result' "$O"
  check "g6 ops.md runs the calls before the change and again after it, and calls the pair of runs the verdict" \
    node "$T/gap.js" "$BLOCK" phrases "$O" \
    'written before the change' 'run before the change' 'run again after the change' \
    'The pair of runs is the verdict'
  # executed, not read: a text without the phrase must come back with a gap, and a mutant that
  # never finds a phrase missing must stop seeing it
  printf 'The calls run whenever it suits, and somebody looks after.\n' > "$T/ops-thin.md"
  check "g6 a text that only says 'after' is seen as a gap" \
    bash -c '! node "$1" "$2" phrases "$3" "The pair of runs is the verdict" > /dev/null' \
    _ "$T/gap.js" "$BLOCK" "$T/ops-thin.md"
  mut nogap 's/\) === -1\)/) === -2)/'
  check "g6 the mutant that never finds a phrase missing is caught" \
    bash -c 'node "$1" "$2" phrases "$3" "The pair of runs is the verdict" > /dev/null' \
    _ "$T/gap.js" "$T/nogap.js" "$T/ops-thin.md"
else
  fail "g6 skills/process/ops.md exists"
fi

# ---- g7: the scenario texts of the gate, and the five the cleanup part runs ----
# The verdicts themselves are read by a part's Test through tests/rebuild/verdicts.sh; here only
# the texts are guarded, so a key can never go missing from the scenario file. The six keys of the
# P8 gate and the five keys P9 runs in the `base` variant after the cleanup (resume,
# aspect-approval, coverage, ceiling, lite-skips) carry the same shape, so one guard reads them all:
# a missing field, a PASS text that reads lines from before the launch finished, a finish line that
# disagrees with the prompt list or with the PASS text, and a text that does not call a launch of a
# retired carrier a FAIL are caught for every one of them.
GATE_KEYS="carrier-pick labels intent-gate compact-contracts plugin-widens deny-completes"
P9_KEYS="resume aspect-approval coverage ceiling lite-skips"
if [ -f "$SCEN" ]; then
  for k in $GATE_KEYS $P9_KEYS; do
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
  # the finish line of a scenario, read against the rest of the scenario: `finish: <i> <n>` holds the
  # index of the prompt the runner delays and the number of workflow finish notices it waits for.
  # Both numbers have a second source in the same text — the prompt list and the PASS rule, which
  # names the notice its own reading starts after — and a number that disagrees with its source makes
  # the runner send the reading prompt at the wrong moment, which is the one thing this field exists
  # to prevent.
  cat > "$T/finish.py" <<'PY'
import re, sys
text = open(sys.argv[1], encoding='utf-8').read()
head = text.split('\n')[0]
bad = []
m = re.search(r'^\s*finish:\s*(\S+)\s+(\S+)\s*$', text, re.M)
if m is None:
    print('no `finish: <prompt index> <notice count>` line')
    sys.exit(1)
i, n = m.group(1), m.group(2)
if not (i.isdigit() and n.isdigit()):
    bad.append('finish: %s %s is no pair of numbers' % (i, n))
    i = n = '0'
i, n = int(i), int(n)
prompts = head.count('"') // 2
if prompts == 0:
    bad.append('the head line carries no quoted prompt')
elif not 1 <= i <= prompts:
    bad.append('finish names prompt %d of %d prompts' % (i, prompts))
ORD = ['no', 'first', 'second', 'third', 'fourth', 'fifth', 'sixth', 'seventh', 'eighth', 'ninth',
       'tenth', 'eleventh', 'twelfth', 'thirteenth', 'fourteenth', 'fifteenth', 'sixteenth',
       'seventeenth', 'eighteenth', 'nineteenth', 'twentieth']
p = re.search(r'^\s*PASS:(.*)$', text, re.M | re.S)
pt = re.sub(r'\s+', ' ', p.group(1)) if p else ''
said = set()
for w in re.findall(r'(?:the|every) (?:([a-z]+) )?workflow finish notice', pt):
    # no ordinal at all means the one and only notice of that run
    said.add(1 if w == '' else (ORD.index(w) if w in ORD else -1))
if not said:
    bad.append('the PASS text names no workflow finish notice the reading starts after')
elif said != {n}:
    named = ', '.join('an ordinal nobody counts' if x < 0 else ORD[x] for x in sorted(said))
    bad.append('finish waits for %d notice(s), the PASS text reads after: %s' % (n, named))
for b in bad:
    print(b)
sys.exit(1 if bad else 0)
PY
  # the four scenarios of the gate that this part writes, plus the five of the cleanup part: each
  # says a launch of an old carrier name is a FAIL, which is what both measure — the gate because
  # the process must pick a carrier of the new set, the cleanup because the old set is gone by then
  for k in carrier-pick labels intent-gate compact-contracts $P9_KEYS; do
    block=$(awk -v k="$k" '$0 ~ "^"k"[[:space:]]"{f=1} f&&/^[A-Za-z][A-Za-z0-9_-]*[[:space:]].*prompts:/&&$1!=k{exit} f{print}' "$SCEN")
    [ -n "$block" ] || continue
    printf '%s\n' "$block" > "$T/scen-$k.txt"
    # the shape of the finish line settles nothing on its own: the prompt index has to be one of the
    # prompts this scenario really sends, and the notice count has to be the one the PASS text names,
    # or the runner waits for a number of launches the judge never reads
    check "g7 $k gates the reading prompt on its own prompt count and on the notice count of its PASS text" \
      python3 "$T/finish.py" "$T/scen-$k.txt"
    # the PASS rule has to name every retired launch name inside a sentence that calls such a
    # launch a FAIL: oldCarrierGap() of the shared block reads the FAIL sentences and reports what
    # the text forgot, so the word "old" standing anywhere settles nothing
    check "g7 $k makes a launch of any old carrier name a FAIL" \
      node "$T/gap.js" "$BLOCK" old "$T/scen-$k.txt"
  done
  # executed, not read: a text that names an old carrier outside any FAIL sentence is a gap, and a
  # mutant of the retired list stops seeing the name it no longer carries
  printf 'The old carriers session:build, session:dev, session:research, session:review-fix, session:translate-ru and session:stage- are gone; a second Workflow call is a FAIL.\n' \
    > "$T/scen-loose.txt"
  check "g7 a text naming the old carriers outside a FAIL sentence is a gap" \
    bash -c '! node "$1" "$2" old "$3" > /dev/null' _ "$T/gap.js" "$BLOCK" "$T/scen-loose.txt"
  mut noold "s/'session:review-fix'/'session:zz-review-fix'/"  # stale-ok: a retired carrier of the OLD_CARRIERS roster, renamed to prove the rule
  check "g7 the mutant that renames a retired carrier is caught" \
    bash -c '! node "$1" "$2" old "$3" > /dev/null' _ "$T/gap.js" "$T/noold.js" "$T/scen-carrier-pick.txt"
  # the names have to stand in one sentence that calls such a launch a FAIL: a text that spreads them
  # over two FAIL sentences, one of them about something else entirely, is a gap, because the joined
  # sentences would carry every name while neither sentence says what the rule asks
  printf 'k  prompts: "one"\n    PASS: A launch of session:build, session:dev or session:research is a FAIL. A missing answer.md, a second Workflow call, session:review-fix, session:translate-ru or session:stage- standing in the out file, is a FAIL.\n' \
    > "$T/scen-split.txt"
  check "g7 the old names spread over two FAIL sentences are a gap" \
    bash -c '! node "$1" "$2" old "$3" > /dev/null' _ "$T/gap.js" "$BLOCK" "$T/scen-split.txt"
  # the finish numbers, executed: a prompt index outside the prompt list and a notice count the PASS
  # text contradicts must both turn the check above red
  sed 's/^\( *\)finish: [0-9]* \([0-9]*\)$/\1finish: 99 \2/' "$T/scen-compact-contracts.txt" > "$T/scen-badindex.txt"
  check "g7 a finish line naming a prompt the scenario never sends is caught" \
    bash -c '! python3 "$1" "$2" > /dev/null' _ "$T/finish.py" "$T/scen-badindex.txt"
  sed 's/^\( *\)finish: \([0-9]*\) [0-9]*$/\1finish: \2 4/' "$T/scen-compact-contracts.txt" > "$T/scen-badcount.txt"
  check "g7 a finish count the PASS text contradicts is caught" \
    bash -c '! python3 "$1" "$2" > /dev/null' _ "$T/finish.py" "$T/scen-badcount.txt"
  printf 'k  prompts: "one" "two"\n    finish: 2 1\n    PASS: only the lines after the work decide this run.\n' > "$T/scen-nonotice.txt"
  check "g7 a PASS text that names no finish notice at all is caught" \
    bash -c '! python3 "$1" "$2" > /dev/null' _ "$T/finish.py" "$T/scen-nonotice.txt"
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

# ---- g8: how a critique is read (idea 3.6) ----
# A critic gives hints, never verdicts. The rule that follows from it is the one a text is easiest to
# lose: a claim is dropped only where a fact refutes it, and a hint no fact settles leaves the claim
# standing, marked as not checked. A text that says the other thing costs a true fact of the object,
# so it is asked for by its decisive words through phraseGap(), and the shape that reverses it is
# found by hintVerdictHits() — both executed over lib/block.js, with mutants below.
cat > "$T/hint.js" <<'JS'
const fs = require('fs')
const b = require(process.argv[2])
let bad = 0
for (const path of process.argv.slice(3)) {
  let text
  try { text = fs.readFileSync(path, 'utf8') } catch (e) {
    console.log(`${path}: unreadable: ${e.message}`); bad++; continue
  }
  for (const h of b.hintVerdictHits(text)) { console.log(`${path}: a hint as a verdict: ${h}`); bad++ }
}
process.exit(bad ? 1 : 0)
JS
if [ -f "$C" ]; then
  check "g8 core.md states that a hint with no fact leaves the claim standing" \
    node "$T/gap.js" "$BLOCK" phrases "$C" \
    'a hint without evidence changes nothing' 'marked as not checked' \
    'a claim is dropped only where a fact refutes it'
  check "g8 core.md lets no hint act as a verdict" node "$T/hint.js" "$BLOCK" "$C"
  # executed, not read: the sentence the gate run produced must be seen, and a mutant that forgets
  # the shape must stop seeing it
  printf 'Where the critique withdraws a fact, drop it from the answer.\n' > "$T/verdict.md"
  check "g8 a text that lets the critique withdraw a fact is seen" \
    bash -c '! node "$1" "$2" "$3" > /dev/null' _ "$T/hint.js" "$BLOCK" "$T/verdict.md"
  printf 'The claim stays, withdrawn per the critique only when a fact says so.\n' > "$T/verdict2.md"
  check "g8 the same verdict written the other way round is seen" \
    bash -c '! node "$1" "$2" "$3" > /dev/null' _ "$T/hint.js" "$BLOCK" "$T/verdict2.md"
  # the hint as the object of the sentence is no verdict, or the critic text could not say it
  printf 'A hint nobody could settle is not a hint, drop it. Reject the hint that no fact confirms.\n' \
    > "$T/hintobject.md"
  check "g8 a hint that is dropped itself is no verdict" node "$T/hint.js" "$BLOCK" "$T/hintobject.md"
  mut noverdict "s/'withdraws', 'withdrew'/'zzwithdraws', 'zzwithdrew'/"
  check "g8 the mutant that drops the verdict verb is caught" \
    bash -c 'node "$1" "$2" "$3" > /dev/null' _ "$T/hint.js" "$T/noverdict.js" "$T/verdict.md"

  # ---- g9: what the harness gate does when the project denies a capability ----
  # A behavior run showed the failure this rule exists to stop: the denied capability ended the
  # stage, the main session looked the fact up in its own turn and asked the user to switch the
  # deny rule off. So the rule is asked for by the words that can be followed — pick a contract that
  # needs none of what is denied, send the need again with the limit named, never do the stage
  # itself, never ask for the capability back — through phraseGap(), never by one common word.
  check "g9 core.md sends the need to a contract that does not need the denied capability" \
    node "$T/gap.js" "$BLOCK" phrases "$C" \
    'send the need to one whose work needs nothing this project denies' \
    'the same need goes out once more' \
    'with the denied capability named in the launch text' \
    'the need goes out again'
  check "g9 core.md forbids doing the stage in the main session instead" \
    node "$T/gap.js" "$BLOCK" phrases "$C" \
    'The main session never does the stage itself instead' \
    'is no result of this task'
  check "g9 core.md makes the chat line a report and never a request for the capability" \
    node "$T/gap.js" "$BLOCK" phrases "$C" \
    'the session never asks the user to give it back' \
    'is a report, never a request'
  check "g9 core.md blocks a stage only when every contract needs what is denied" \
    node "$T/gap.js" "$BLOCK" phrases "$C" \
    'only when every contract of the session needs what this project denies' \
    'never ends with the wanted file unwritten'
  # executed, not read: a text that says only that the capability is missing carries none of it
  printf 'A denied capability is named in one chat line and the task goes on somehow.\n' > "$T/deny-thin.md"
  check "g9 a text that only names the missing capability is a gap" \
    bash -c '! node "$1" "$2" phrases "$3" "The main session never does the stage itself instead" > /dev/null' \
    _ "$T/gap.js" "$BLOCK" "$T/deny-thin.md"
fi

if [ "$FAILS" -eq 0 ]; then echo "carrier-free: PASS $N"; exit 0; fi
echo "carrier-free: FAIL $FAILS failures, $N checks passed"
exit 1
