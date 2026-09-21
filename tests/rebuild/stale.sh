#!/bin/bash
# Static oracle of part 9: no live reference to a name of the 0.15 set survives, inside the repo or
# in the user-level assets, and no live text of the plugin still routes by the design part 9 deleted
# (group s4, oldDesignHits() of the shared block: prose that names "the pipeline", a gate letter of
# the old flow or "the review's own artifacts" carries no qualified name and passes group s1).
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
# Neither what counts as a retired name nor what counts as a declaration is a pattern list of this
# file: both are staleFileHits() of the shared block, executed here over lib/block.js, so the rule
# lives in one place with the rosters and is tested by the mutants below instead of read. Only
# qualified forms count (`session:<old name>`, an `agentType`/`subagent_type` value, the two retired
# slash commands, a path of a deleted file, the five `stage-<x>` stems, the two mode keys of the old
# state file the U9 answer line reports). The bare words `research`, `review`, `build`, `waiter`,
# `translator` and `web-researcher` are live names of the new set and never match alone.
#
# Four kinds of line are a declaration that a name is retired, never a reference to it, and each one
# is scoped to the file kind that owns it: a tree-wide escape would drop a live launch that merely
# stands beside a date or beside the word FAIL (the scopes are in the shared block, with the rule):
#   - a roster of the shared block: a line inside a `const NAME = [` array literal, read only inside
#     lib/block.src.js, lib/block.js and the stamped shared-block region of a workflow. The carrier
#     roster and OLD_CARRIERS list the retired names on purpose, which is what makes
#     tests/rebuild/carrier-free.sh catch a process text that names one;
#   - a line that calls such a launch a FAIL, in the files that state gate PASS rules only (the
#     scenario set of tests/measure, the tests of tests/rebuild): such a sentence has to name every
#     retired carrier, and it is the opposite of a live reference;
#   - a line that dates its statement (`2026-09-16`), in the memory files of the user level only: a
#     record of what happened that day, not an instruction to do it again. This keeps the dated
#     memory entries readable without a rewrite of the user's history;
#   - the lines under a `## Version log` heading of a markdown file, up to the next heading of that
#     file: a version log records what a released version shipped, which is the same kind of
#     statement as a dated one, and the rebuild rewrites no released version.
# A line may also carry the marker `stale-ok:` with a reason; the marker covers its own line and the
# lines after it up to the next blank line, it is counted and printed by the line of the marker
# itself, and it is allowed under tests/rebuild/ only, so no file of the product tree can opt out.
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
  const r = b.staleFileHits(path, text)
  r.hits.forEach(h => hits.push(`${path}:${h.line} names the retired ${h.name}`))
  r.marks.forEach(m => marks.push(`${path}:${m}`))
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
# tree full of old names. Every fixture stands at the path of the file kind it speaks for, because
# the declaration kinds are scoped by path: the very same line is a record in a memory file and a
# live reference in the product tree, and that difference is checked in both directions below.
mk() { # mk <name> <line>: a one-line fixture in the product tree, where no escape is in scope
  mkat "$1" "plugins/session/skills/f-$1.md" "$2"
}
mkat() { # mkat <name> <relative path under $T> <line>
  mkdir -p "$T/$(dirname "$2")"
  printf '%s\n' "$3" > "$T/$2"
  printf '%s\n' "$T/$2" > "$T/l-$1"
}
SCEN=tests/measure/rebuild-scenarios-0.16.txt # the gate scenarios: the FAIL escape is in scope
MEMO=projects/enc/memory/note.md              # a memory file of the user level: a date is a record
TESTF=tests/rebuild/f-marked.sh               # a test of this directory: the marker is in scope
# stale-ok: every fixture line of this group quotes a retired form on purpose, to prove the scan
# sees it; the group ends at the blank line below
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

# the declaration kinds, executed, each one in three directions: clean inside its scope, a hit in
# the product tree (the scope is what keeps a live launch beside a date or beside the word FAIL
# visible), and a hit without the declaration at all
# stale-ok: the fixture lines of this group quote retired names to prove the scoped escapes
FAILLINE='A launch of session:build, session:dev, session:research, session:review-fix, session:translate-ru or any session:stage- agent is a FAIL.'
DATELINE='On 2026-09-16 a session:dev run blocked on git and the resume replayed the cached result.'
MARKLINE='mut noold "s/session:review-fix/x/"  # stale-ok: the retired roster, quoted to prove the rule'
mkat decl-fail "$SCEN" "$FAILLINE"
mkat fail-prod "plugins/session/skills/f-fail.md" "$FAILLINE"
mkat decl-date "$MEMO" "$DATELINE"
mkat date-prod "plugins/session/skills/f-date.md" "$DATELINE"
mkat decl-mark "$TESTF" "$MARKLINE"
mkat mark-prod "plugins/session/skills/f-mark.md" "$MARKLINE"
mk no-decl 'A session:dev run blocked on git and the resume replayed the cached result.'
for c in decl-fail decl-date decl-mark; do
  check "s2 the $c line is a declaration inside its scope" node "$T/scan.js" "$BLOCK" "$T/l-$c"
done
for c in fail-prod date-prod mark-prod no-decl; do
  check "s2 the $c line is a hit outside that scope" \
    bash -c '! node "$1" "$2" "$3" > /dev/null' _ "$T/scan.js" "$BLOCK" "$T/l-$c"
done

# the marker covers the lines after it up to the next blank line, and no further: a patch table or a
# fixture group is written over several lines, and the line after the blank is a hit again
# stale-ok: the fixture written below is a marked patch table and one line past its blank line
mkdir -p "$T/tests/rebuild"
{ printf '%s\n' '# stale-ok: the patch table below removes these names'
  printf '%s\n' "patch skills/tmux-sessions/SKILL.md 'session:waiter' \\"
  printf '%s\n' "  's{session:waiter}{session:role}'"
  printf '\n'
  printf '%s\n' 'tmux send-keys -t "$s" "/session:pipeline full" Enter'
} > "$T/tests/rebuild/f-block.sh"
printf '%s\n' "$T/tests/rebuild/f-block.sh" > "$T/l-markblock"
check "s2 a marked block ends at the blank line: exactly the line after it is a hit" \
  bash -c 'out=$(node "$1" "$2" "$3"); [ "$(printf %s "$out" | grep -c "names the retired")" = 1 ] &&
    printf %s "$out" | grep -q ":5 names the retired"' _ "$T/scan.js" "$BLOCK" "$T/l-markblock"

# the version log ends at the next heading of its file, or one log heading would silence the rest of
# the file, to the end of it when the section is the last one; and it is a declaration in a README or
# a CHANGELOG only, the two file kinds that write a released version down. The very same section in
# an ordinary document of the product tree is no escape: both hits stand there.
# stale-ok: the two fixtures written below are a version log and a section after it
mkdir -p "$T/plugins/session" "$T/plugins/session/skills"
LOGDOC() { { printf '%s\n' '## Version log' '- 0.15.4 the pipeline skill: /session:pipeline full' '' '## Modes'
  printf '%s\n' 'The mode file is written by hooks/session-modes.sh at every start.'; } > "$1"; }
LOGDOC "$T/plugins/session/README.md"
printf '%s\n' "$T/plugins/session/README.md" > "$T/l-log"
check "s2 a version log of a README is a declaration and the heading after it ends the log" \
  bash -c 'out=$(node "$1" "$2" "$3"); [ "$(printf %s "$out" | grep -c "names the retired")" = 1 ] &&
    printf %s "$out" | grep -q ":5 names the retired"' _ "$T/scan.js" "$BLOCK" "$T/l-log"
LOGDOC "$T/plugins/session/skills/f-log.md"
printf '%s\n' "$T/plugins/session/skills/f-log.md" > "$T/l-log-prod"
check "s2 the same version log in an ordinary document of the tree is no escape" \
  bash -c 'out=$(node "$1" "$2" "$3"); [ "$(printf %s "$out" | grep -c "names the retired")" = 2 ]' \
  _ "$T/scan.js" "$BLOCK" "$T/l-log-prod"

# the roster rule holds inside the shared block only: the same roster line in an ordinary file is a
# hit, or any file could hide a reference behind a capitalised array name
# stale-ok: the two roster fixtures below quote retired agent names, once in each kind of file
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
# stale-ok: every mutant below names the retired form it removes from the rule
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

# the scope of every escape is mutated too: a mutant that lets an escape run over the whole tree
# stops seeing the product-tree fixtures above, which is what a line-wide escape would do in the
# repo
mut failwide "s|const STALE_FAIL_SCOPE = \[.*\]|const STALE_FAIL_SCOPE = [/./]|"
check "s2 the mutant that widens the FAIL escape to every file is caught" \
  bash -c 'node "$1" "$2" "$3" > /dev/null' _ "$T/scan.js" "$T/failwide.js" "$T/l-fail-prod"
mut datewide "s|const STALE_DATED_SCOPE = \[.*\]|const STALE_DATED_SCOPE = [/./]|"
check "s2 the mutant that widens the date escape to every file is caught" \
  bash -c 'node "$1" "$2" "$3" > /dev/null' _ "$T/scan.js" "$T/datewide.js" "$T/l-date-prod"
mut markwide "s|const STALE_MARK_SCOPE = \[.*\]|const STALE_MARK_SCOPE = [/./]|"
check "s2 the mutant that lets any file carry the marker is caught" \
  bash -c 'node "$1" "$2" "$3" > /dev/null' _ "$T/scan.js" "$T/markwide.js" "$T/l-mark-prod"
mut logsticky "s|inLog = STALE_LOG_HEAD\.test\(s\)|inLog = inLog \|\| STALE_LOG_HEAD.test(s)|"
check "s2 the mutant whose version log never ends is caught" \
  bash -c 'node "$1" "$2" "$3" > /dev/null' _ "$T/scan.js" "$T/logsticky.js" "$T/l-log"
mut logwide "s|const STALE_LOG_SCOPE = \[.*\]|const STALE_LOG_SCOPE = [/./]|"
check "s2 the mutant that lets any document open a version log is caught" \
  bash -c 'out=$(node "$1" "$2" "$3"); [ "$(printf %s "$out" | grep -c "names the retired")" = 1 ]' \
  _ "$T/scan.js" "$T/logwide.js" "$T/l-log-prod"

# ---- s4: no live text of the plugin still routes by the deleted design ----
# staleNameHits() counts qualified names only. Prose that tells its reader what "the pipeline" does,
# which gate letter ends it or which artifacts "the review's own" are carries no qualified name, so
# it passed the scan above while instructing the session to use a skill this part deleted — which is
# what skills/codex carried after P9. oldDesignHits() of the shared block is that rule, executed here
# over the same file list, with the fixtures and the mutant below.
cat > "$T/design.js" <<'JS'
const fs = require('fs')
const b = require(process.argv[2])
const files = fs.readFileSync(process.argv[3], 'utf8').split('\n').filter(x => x.length)
const hits = []
for (const path of files) {
  let text
  try { text = fs.readFileSync(path, 'utf8') } catch (e) {
    hits.push(`${path}:0 unreadable: ${e.message}`)
    continue
  }
  if (text.indexOf('\u0000') !== -1) continue // binary
  b.oldDesignHits(path, text).forEach(h => hits.push(`${path}:${h.line} routes by the deleted design: ${h.phrase}`))
}
hits.slice(0, 25).forEach(h => console.log(h))
if (hits.length > 25) console.log(`... ${hits.length - 25} more`)
process.exit(hits.length ? 1 : 0)
JS
if node "$T/design.js" "$BLOCK" "$T/files"; then pass
else fail "s4 no live text of the plugin routes by the deleted design"; fi

# executed, not read: the prose of the plugin is a hit, the same line outside the plugin's prose is
# none (a review of the rebuild and a dated plan quote the old design on purpose), and the live uses
# of the word `pipeline` stay clean
mkdir -p "$T/plugins/session/skills/codex" "$T/docs"
DESIGNLINE='A job stays on Claude when it writes the pipeline'"'"'s own artifacts, and in pipeline Gate F closes it.'
printf '%s\n' "$DESIGNLINE" > "$T/plugins/session/skills/codex/f-design.md"
printf '%s\n' "$T/plugins/session/skills/codex/f-design.md" > "$T/l-design"
check "s4 a sentence of the plugin prose that routes by the deleted design is a hit" \
  bash -c '! node "$1" "$2" "$3" > /dev/null' _ "$T/design.js" "$BLOCK" "$T/l-design"
printf '%s\n' "$DESIGNLINE" > "$T/docs/f-design.md"
printf '%s\n' "$T/docs/f-design.md" > "$T/l-design-out"
check "s4 the same sentence outside the plugin prose is no hit" \
  node "$T/design.js" "$BLOCK" "$T/l-design-out"
{ printf '%s\n' 'A relay runs as `pipeline()` stages of the same workflow.'
  printf '%s\n' 'The object of the task can be a deployment pipeline, a certificate or a DNS record.'
  printf '%s\n' '`tools/pipeline-cost.py` joins the rows of a run by label.'
} > "$T/plugins/session/skills/f-live.md"
printf '%s\n' "$T/plugins/session/skills/f-live.md" > "$T/l-design-live"
check "s4 the live uses of the word pipeline are clean" \
  node "$T/design.js" "$BLOCK" "$T/l-design-live"
printf '%s\n' 'The closure of a task is Gate F of the flow.' > "$T/plugins/session/skills/f-gate.md"
printf '%s\n' "$T/plugins/session/skills/f-gate.md" > "$T/l-design-gate"
check "s4 a gate letter of the old flow is a hit of its own" \
  bash -c '! node "$1" "$2" "$3" > /dev/null' _ "$T/design.js" "$BLOCK" "$T/l-design-gate"
mut nogate 's|/\\bGate \[A-F\]\\b/|/zzGateF/|'
check "s4 the mutant that drops the gate letters is caught" \
  bash -c 'node "$1" "$2" "$3" > /dev/null' _ "$T/design.js" "$T/nogate.js" "$T/l-design-gate"
mut nodesignscope 's|const OLD_DESIGN_SCOPE = \[.*\]|const OLD_DESIGN_SCOPE = [/zznothing/]|'
check "s4 the mutant that scans no plugin prose at all is caught" \
  bash -c 'node "$1" "$2" "$3" > /dev/null' _ "$T/design.js" "$T/nodesignscope.js" "$T/l-design"

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
