#!/bin/bash
# Static oracle of part 9: no live reference to a name of the 0.15 set survives, inside the repo or
# in the user-level assets.
#
#   tests/rebuild/stale.sh <dir>
#
# <dir> is the copy of the user-level assets that tests/rebuild/user-copy.sh builds and
# tests/rebuild/switch-user.sh patches (at the switch of section 6: the real ~/.claude). The
# argument is required and the run fails when the directory is missing or holds no file, so this
# test can never pass by scanning nothing.
#
# Scope (the plan's scope rule): the whole tracked tree, `git ls-files`, plus every file under
# <dir>. It is the only tree-wide test.
#
# What counts as a retired name is not a pattern list of this file: it is staleNameHits() of the
# shared block, executed here over lib/block.js, so the retired names live in one place with the
# rest of the rosters and the rule is tested by mutation below instead of read. Only qualified forms
# count (`session:<old name>`, an `agentType`/`subagent_type` value, `/session:pipeline`,
# `/session:review`, a path of a deleted file, the five `stage-<x>` stems, the two mode keys of the
# old state file the U9 answer line reports). The bare words `research`, `review`, `build`,
# `waiter`, `translator` and `web-researcher` are live names of the new set and never match alone.
#
# Three kinds of line are a declaration that a name is retired, never a reference to it:
#   - a roster of the shared block: a line inside a `const NAME = [` array literal, read only inside
#     lib/block.src.js, lib/block.js and the stamped shared-block region of a workflow. The carrier
#     roster and OLD_CARRIERS list the retired names on purpose, which is what makes
#     tests/rebuild/carrier-free.sh catch a process text that names one;
#   - a line that calls such a launch a FAIL: the PASS rules of the gate scenarios have to name
#     every retired carrier, and that sentence is the opposite of a live reference;
#   - a line that dates its statement (`2026-09-16`): a record of what happened that day, not an
#     instruction to do it again. This is what keeps the dated memory entries of the user level and
#     the measurement records readable without a rewrite of the user's history;
#   - every line under a `## Version log` heading: a version log records what a released version
#     shipped, which is the same kind of statement as a dated one, and the rebuild rewrites no
#     released version.
# A line may also carry the marker `stale-ok:` with a reason; such a line is counted and printed,
# and the marker is allowed under tests/rebuild/ only, so no file of the product tree can opt out.
#
# Excluded paths, each a dated record of a past run or a past plan rather than a live reference, and
# each asserted to match at least one tracked file, so an exclusion that outlived its files is a
# failure of this test and not a silent hole. Deviation from the plan's P9 list, stated once: the
# plan names three of them (docs/measurements, tests/corp/results, tests/demo-game/results); the
# others are the same kind of file and were found by running this test (the dated plans of docs/, the
# dated copy of the old README, the design document of this rebuild, which names the set it
# replaces, the night plan of tests/corp and the 0.14 scenario set).
# Temp dirs only, no network, under 20 s.
set -u

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
BLOCK=$REPO/plugins/session/lib/block.js

EXCLUDE='docs/measurements/
docs/plans/
docs/history-README-2026-09-12.md
docs/roadmap-2026-09-12.md
reviews/
tests/corp/results/
tests/corp/NIGHT-PLAN-2026-09-07.md
tests/demo-game/results/
tests/measure/basecls-scenarios-0.14.txt'

DIR=${1:-}
N=0; FAILS=0
pass() { N=$((N + 1)); }
fail() { echo "FAIL $1"; FAILS=$((FAILS + 1)); }
check() { local label=$1; shift; if "$@"; then pass; else fail "$label"; fi; }

if [ -z "$DIR" ]; then
  echo "stale: no argument; want <dir> (the patched copy of the user-level assets)" >&2
  exit 2
fi
if [ ! -d "$DIR" ]; then
  echo "stale: FAIL no such directory: $DIR" >&2
  exit 1
fi
DIRFILES=$(find "$DIR" -type f 2>/dev/null | wc -l | tr -d ' ')
if [ "$DIRFILES" -eq 0 ]; then
  echo "stale: FAIL $DIR holds no file: nothing was scanned" >&2
  exit 1
fi
if [ ! -f "$BLOCK" ]; then
  echo "stale: FAIL $BLOCK missing: the retired-name rule is executed, never grepped" >&2
  exit 1
fi

T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT

# ---- the scanner: one node process over a file list ----
cat > "$T/scan.js" <<'JS'
const fs = require('fs')
const b = require(process.argv[2])
const files = fs.readFileSync(process.argv[3], 'utf8').split('\n').filter(x => x.length)
const BEGIN = '// ---- shared block'
const END = '// ---- end shared block'
const ROSTER = /^const [A-Z][A-Z0-9_]* = \[/
const DATED = /\b\d{4}-\d{2}-\d{2}\b/
const hits = []
const marks = []
for (const path of files) {
  let text
  try { text = fs.readFileSync(path, 'utf8') } catch (e) {
    // a file of the scope nobody could read is never a clean file: it is reported like a hit
    hits.push(`${path}:0 unreadable: ${e.message}`)
    continue
  }
  if (text.indexOf('\u0000') !== -1) continue // binary
  const isBlock = /lib\/block(\.src)?\.js$/.test(path)
  let inBlock = isBlock
  let inRoster = false
  let inLog = false
  text.split('\n').forEach((line, i) => {
    const s = line.trim()
    if (/^#+\s+Version log\b/i.test(s)) inLog = true
    if (inLog) return
    if (!isBlock) {
      if (s.startsWith(END)) { inBlock = false; return }
      if (s.startsWith(BEGIN)) { inBlock = true; return }
    }
    if (inBlock) {
      if (inRoster) { if (s.indexOf(']') !== -1) inRoster = false; return }
      if (ROSTER.test(s)) { inRoster = s.indexOf(']') === -1; return }
    }
    const found = b.staleNameHits(line)
    if (!found.length) return
    if (/\bFAIL\b/.test(line)) return // the line calls such a launch a FAIL
    if (DATED.test(line)) return // a record of that day, not an instruction
    if (line.indexOf('stale-ok') !== -1) { marks.push(`${path}:${i + 1}`); return }
    found.forEach(t => hits.push(`${path}:${i + 1} names the retired ${t}`))
  })
}
hits.slice(0, 25).forEach(h => console.log(h))
if (hits.length > 25) console.log(`... ${hits.length - 25} more`)
if (process.env.STALE_MARKS === '1') marks.forEach(m => console.log('marked ' + m))
process.exit(hits.length ? 1 : 0)
JS

# ---- the file list: the tracked tree minus the excluded records, plus <dir> ----
git -C "$REPO" ls-files > "$T/tracked" || { echo "stale: FAIL git ls-files failed in $REPO" >&2; exit 1; }
check "s0 the tracked tree is not empty" test -s "$T/tracked"
printf '%s\n' "$EXCLUDE" > "$T/exclude"
# an exclusion that matches no tracked file has outlived its files: it is a failure, never a hole
while IFS= read -r ex; do
  [ -n "$ex" ] || continue
  check "s0 the exclusion $ex still matches a tracked file" \
    grep -q -F -- "$ex" "$T/tracked"
done < "$T/exclude"
grep -v -F -f "$T/exclude" "$T/tracked" | sed "s|^|$REPO/|" > "$T/files"
find "$DIR" -type f >> "$T/files"
COUNT=$(wc -l < "$T/files" | tr -d ' ')
check "s0 the scan list holds the tree and the copy (got $COUNT files, $DIRFILES of them under the copy)" \
  test "$COUNT" -gt "$DIRFILES"

# ---- s1: no live reference to a retired name, in the tree or in the copy ----
if node "$T/scan.js" "$BLOCK" "$T/files"; then pass
else fail "s1 no live reference to a retired name of the 0.15 set"; fi

# ---- s2: executed, not read ----
# Every form of the rule is seen on a line that carries it, and a mutant of the shared block that
# drops that form stops seeing it. Without this group a broken pattern would print "PASS" over a
# tree full of old names.
mk() { printf '%s\n' "$2" > "$T/f-$1.txt"; printf '%s\n' "$T/f-$1.txt" > "$T/l-$1"; }
mk launch 'Send the research stage to session:research at class c3.'
mk agenttype "const o = { agentType: 'session:stage-author', phase: 'Plan' }"
mk slash 'Then run /session:pipeline full and wait for the line.'
mk path 'The shared rules live in skills/pipeline/core.md next to it.'
mk file 'It reads workflows/translate-ru.js of the plugin.'
mk role 'codex-exec-logged.sh --role stage-reviewer - composes the role body.'
mk statekey "jq -r '[.base, .codex, .pipeline, .review] | join(\":\")' state.json"
for c in launch agenttype slash path file role statekey; do
  check "s2 the scan sees a retired name of kind $c" \
    bash -c '! node "$1" "$2" "$3" > /dev/null' _ "$T/scan.js" "$BLOCK" "$T/l-$c"
done
# the live names of the new set are no hits, or this test would forbid the plugin its own names
mk live 'The research carrier, the waiter role and the translator role are launched by name: session:role, session:chain, session:make, session:probe, and the review of a document reads the evidence chain. The build step is bin/build.sh.'
check "s2 the live names of the new set are clean" node "$T/scan.js" "$BLOCK" "$T/l-live"
# the three declaration kinds, executed: each must come back clean, and the same line without its
# declaration must come back as a hit
mk decl-fail 'A launch of session:build, session:dev, session:research, session:review-fix, session:translate-ru or any session:stage- agent is a FAIL.'
check "s2 a line that calls such a launch a FAIL is a declaration" node "$T/scan.js" "$BLOCK" "$T/l-decl-fail"
mk decl-date 'On 2026-09-16 a session:dev run blocked on git and the resume replayed the cached result.'
check "s2 a line that dates its statement is a record" node "$T/scan.js" "$BLOCK" "$T/l-decl-date"
mk decl-mark 'mut noold "s/session:review-fix/x/"  # stale-ok: the retired roster, quoted to prove the rule'
check "s2 a line with the marker is opted out" node "$T/scan.js" "$BLOCK" "$T/l-decl-mark"
mk no-decl 'A session:dev run blocked on git and the resume replayed the cached result.'
check "s2 the same line without a date, a FAIL or the marker is a hit" \
  bash -c '! node "$1" "$2" "$3" > /dev/null' _ "$T/scan.js" "$BLOCK" "$T/l-no-decl"
# the roster rule holds inside the shared block only: the same roster line in an ordinary file is a
# hit, or any file could hide a reference behind a capitalised array name
mkdir -p "$T/lib" "$T/plain"
printf "const CARRIER_AGENTS = ['stage-author', 'code-reviewer']\n" > "$T/lib/block.js"
printf '%s\n' "$T/lib/block.js" > "$T/l-roster"
check "s2 a roster line of the shared block is a declaration" node "$T/scan.js" "$BLOCK" "$T/l-roster"
printf "const CARRIER_AGENTS = ['stage-author', 'code-reviewer']\n" > "$T/plain/other.js"
printf '%s\n' "$T/plain/other.js" > "$T/l-roster-plain"
check "s2 the same roster line outside the shared block is a hit" \
  bash -c '! node "$1" "$2" "$3" > /dev/null' _ "$T/scan.js" "$BLOCK" "$T/l-roster-plain"
# a file the scan cannot read is reported, never counted clean
printf '%s\n' "$T/nope-missing.txt" > "$T/l-missing"
check "s2 an unreadable file of the scope is reported" \
  bash -c '! node "$1" "$2" "$3" > /dev/null' _ "$T/scan.js" "$BLOCK" "$T/l-missing"

mut() { # mut <name> <perl expression>: a mutant of the shared block that drops one form of the rule
  perl -pe "$2" "$BLOCK" > "$T/$1.js"
  check "s2 the mutant $1 is really a mutation" bash -c '! cmp -s "$1" "$2"' _ "$BLOCK" "$T/$1.js"
  # a mutant that no longer loads proves nothing: the exit code below is read inverted, so a mutant
  # that throws on require would count as a caught mutant while the rule was never executed
  check "s2 the mutant $1 still loads" \
    bash -c 'node -e "require(process.argv[1])" "$1" 2> "$2/mut.err" || { tail -2 "$2/mut.err"; exit 1; }' \
    _ "$T/$1.js" "$T"
}
mut noagent "s/'stage-reviewer'/'zz-stage-reviewer'/g"
check "s2 the mutant that renames a retired agent is caught" \
  bash -c 'node "$1" "$2" "$3" > /dev/null' _ "$T/scan.js" "$T/noagent.js" "$T/l-role"
mut noflow "s/const STALE_WORKFLOWS = \[.*\]/const STALE_WORKFLOWS = ['zznoflow']/"
check "s2 the mutant that empties the retired workflow list is caught" \
  bash -c 'node "$1" "$2" "$3" > /dev/null' _ "$T/scan.js" "$T/noflow.js" "$T/l-launch"
mut nopath "s|'skills/pipeline/', 'skills/review/'|'zz/skills/pipeline/', 'zz/skills/review/'|"
check "s2 the mutant that renames a retired path is caught" \
  bash -c 'node "$1" "$2" "$3" > /dev/null' _ "$T/scan.js" "$T/nopath.js" "$T/l-path"
mut nokey "s/const STALE_STATE_KEYS = \[.*\]/const STALE_STATE_KEYS = ['zznokey']/"
check "s2 the mutant that drops the mode keys of the old state file is caught" \
  bash -c 'node "$1" "$2" "$3" > /dev/null' _ "$T/scan.js" "$T/nokey.js" "$T/l-statekey"

# ---- s3: the marker is allowed under tests/rebuild/ only ----
marked=$(STALE_MARKS=1 node "$T/scan.js" "$BLOCK" "$T/files" 2>/dev/null | sed -n 's/^marked //p')
echo "stale: $(printf '%s\n' "$marked" | grep -c '[^[:space:]]') line(s) opted out with a written reason"
bad=$(printf '%s\n' "$marked" | grep -v '^$' | grep -v "^$REPO/tests/rebuild/" | tr '\n' ' ')
check "s3 the stale-ok marker stands under tests/rebuild/ only (outside: $bad)" test -z "$bad"
if [ -n "$(printf '%s\n' "$marked" | grep -v '^$')" ]; then
  check "s3 every marked line carries a reason after the marker" \
    bash -c 'for m in $1; do f=${m%:*}; n=${m##*:}; l=$(sed -n "${n}p" "$f");
      case $l in *stale-ok:*[a-z]*) ;; *) echo "no reason: $m"; exit 1 ;; esac; done' \
    _ "$(printf '%s ' $marked)"
fi

if [ "$FAILS" -eq 0 ]; then echo "stale: PASS $N checks, $COUNT files ($DIRFILES under $DIR)"; exit 0; fi
echo "stale: FAIL $FAILS failures, $N checks passed"
exit 1
