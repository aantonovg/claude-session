#!/bin/bash
# Static oracle of the text of the new set: the class table is the only source of a model.
#
#   tests/rebuild/text.sh [--with-base]
#
# Globs (a glob that matches nothing is tolerated, which is what lets this test exist from P1):
#   plugins/session/lib/roles/*.md, lib/aspects/*.md, lib/verification.md,
#   plugins/session/agents/tools-*.md, skills/process/**,
#   the kept skills skills/ask/**, skills/reset-counter/**, skills/*-ping/**,
#   with --with-base also base/BASE.md and skills/base/SKILL.md (from P6 on: the old base text
#   names models until P6 rewrites it).
# Rule: no text of the new set names a model, a cell short code, a reasoning level or a tier. The
# only allowed forms of a model word are the slot names ("opus slot", "sonnet slot") and the
# submode names ("no-sonnet", "no-opus", "no-fable"); a generated region between build markers is
# skipped, because the class table itself is rendered there by bin/build.sh. What counts as naming
# a cell is cellTokens() of lib/block.js, executed here over every file of the globs and re-run
# over a mutant of that function which must turn the same check red.
# Also: lib/verification.md carries the pieces P1 owes (oracle classes, a route per ladder level,
# the fork-author exception, the ops control-call form).
# From P6 on, under --with-base: the base text is one of those globs, it carries the class table
# only as a generated region, it names no carrier but the session:ask skill, the cut sections of
# P6 are gone, and it points at lib/verification.md instead of repeating it. P6 also reads the two
# composite workflows for that pointer (workflows/chain.js, workflows/make.js), a fixed extension
# of the glob list of the plan's scope rule. The no-roster rule is checked twice: against the agent
# forms (agentType, subagent_type, tools-*) and against the role catalog names of lib/classes.json
# in roster shapes only - a list or table entry that starts with a role name, or a role name beside
# a slot word - so a role word used as a plain English word stays clean. The two workflow files are
# read here because no other static test owns that citation.
set -u

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
P=$REPO/plugins/session
WITH_BASE=0
for a in "$@"; do
  case $a in
    --with-base) WITH_BASE=1 ;;
    *) echo "text.sh: unknown option $a" >&2; exit 2 ;;
  esac
done

N=0; FAILS=0
pass() { N=$((N + 1)); }
fail() { echo "FAIL $1"; FAILS=$((FAILS + 1)); }
check() { local label=$1; shift; if "$@"; then pass; else fail "$label"; fi; }

shopt -s nullglob
FILES=("$P"/lib/roles/*.md "$P"/lib/aspects/*.md "$P"/lib/verification.md "$P"/agents/tools-*.md)
# bash 3.2 (the /bin/bash of macOS) has no globstar, and `shopt -s globstar` there only prints
# "invalid shell option name" while `**` silently degrades to `*`, so the skill trees are walked
# with find instead: an absent skill directory contributes nothing, which keeps the globs tolerant.
for d in process ask reset-counter start-ping stop-ping resume-ping; do
  [ -d "$P/skills/$d" ] || continue
  while IFS= read -r f; do FILES+=("$f"); done < <(find "$P/skills/$d" -type f -name '*.md' | sort)
done
if [ "$WITH_BASE" = 1 ]; then
  FILES+=("$P/base/BASE.md" "$P/skills/base/SKILL.md")
fi

# bash 3.2 expands "${FILES[@]}" of an empty array as an unbound variable under set -u, so the
# guard stops the script instead of falling through into the scan with no files.
if [ "${#FILES[@]}" -eq 0 ]; then
  fail "t1 at least one text file in the globs"
  echo "text: FAIL $FAILS failures, $N checks passed"
  exit 1
fi
pass

# What counts as naming a cell is not a regex of this file: it is cellTokens() of the shared block,
# executed over lib/block.js, so the model names, the short codes and the effort words all come
# from lib/classes.json and the rule is tested by mutation below instead of read.
T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT
cat > "$T/scan.js" <<'JS'
const fs = require('fs')
const b = require(process.argv[2])
const BEGIN = ['// ---- shared block', '// ---- class table', '// ---- roles', '// ---- aspects', '<!-- class table']
const END = ['// ---- end shared block', '// ---- end class table', '// ---- end roles', '// ---- end aspects', '<!-- end class table']
const hits = []
for (const path of process.argv.slice(3)) {
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
    for (const t of b.cellTokens(line)) hits.push(`${path}:${i + 1} names a cell: ${t}`)
  })
}
hits.slice(0, 20).forEach(h => console.log(h))
process.exit(hits.length ? 1 : 0)
JS
if node "$T/scan.js" "$P/lib/block.js" "${FILES[@]}"; then pass
else fail "t1 no model, cell short code, reasoning level or tier in the new text"; fi

# t1 is executed, not read: a line naming a cell short code must be seen, and a mutant of the
# shared block that looks at model names only must stop seeing it.
printf 'a label `fab-me` in prose\n' > "$T/cell.md"
check "t1 the scan sees a cell short code" bash -c '! node "$1" "$2" "$3" > /dev/null' _ "$T/scan.js" "$P/lib/block.js" "$T/cell.md"
perl -pe "s/parts\.join\('\|'\)/parts[0]/" "$P/lib/block.js" > "$T/mutant.js"
check "t1 the mutant of cellTokens is really a mutation" bash -c '! cmp -s "$1" "$2"' _ "$P/lib/block.js" "$T/mutant.js"
check "t1 the mutant that drops the short code is caught" bash -c 'node "$1" "$2" "$3" > /dev/null' _ "$T/scan.js" "$T/mutant.js" "$T/cell.md"

# the same, executed, for a reasoning level named without the words "effort" and "tier": the two
# forms a prose line really takes ("run at high reasoning", "reasoning level high"), and a mutant
# of cellTokens that keeps the two bare words only must stop seeing both.
printf 'run at high reasoning, the reasoning level high\n' > "$T/level.md"
check "t1 the scan sees a reasoning level named without the word effort" \
  bash -c '! node "$1" "$2" "$3" > /dev/null' _ "$T/scan.js" "$P/lib/block.js" "$T/level.md"
perl -pe "s/const LEVEL_NOUNS = \[.*\]/const LEVEL_NOUNS = ['effort', 'tier']/" "$P/lib/block.js" > "$T/levels.js"
check "t1 the mutant of LEVEL_NOUNS is really a mutation" bash -c '! cmp -s "$1" "$2"' _ "$P/lib/block.js" "$T/levels.js"
check "t1 the mutant that drops the level nouns is caught" bash -c 'node "$1" "$2" "$3" > /dev/null' _ "$T/scan.js" "$T/levels.js" "$T/level.md"
# and the sentence that names the command, with no level word beside it, is no cell token
printf 'the reasoning-level command `/model`\n' > "$T/cmd.md"
check "t1 naming the reasoning-level command is no cell token" node "$T/scan.js" "$P/lib/block.js" "$T/cmd.md"

# t2: lib/verification.md, the page every process skill and composite workflow cites.
V=$P/lib/verification.md
if [ -f "$V" ]; then
  check "t2 verification.md names the oracle class existing" grep -q 'existing oracle' "$V"
  check "t2 verification.md names the oracle class missing" grep -q 'missing oracle' "$V"
  check "t2 verification.md names the oracle class no possible" grep -q 'no possible oracle' "$V"
  for l in a b c d e; do
    check "t2 verification.md has a route for ladder level $l" grep -Eq "^\| $l \|" "$V"
  done
  check "t2 verification.md carries the fork-author exception" grep -qi 'fork' "$V"
  check "t2 verification.md carries the ops control-call form" grep -qi 'control call' "$V"
  check "t2 verification.md states the artifact chain" grep -qi 'artifact chain' "$V"
  check "t2 verification.md states how an unverified area is accepted" grep -qi 'accepted by the user' "$V"
  check "t2 verification.md rejects ids in test names" grep -qi 'no test name carries one' "$V"
else
  fail "t2 lib/verification.md missing"
fi

# t3: the base text (P6). Under --with-base only: the old base names models and an agent roster
# until P6 rewrites it, so this group starts to run in the part that owns the rewrite.
if [ "$WITH_BASE" = 1 ]; then
  B=$P/base/BASE.md
  S=$P/skills/base/SKILL.md
  if [ -f "$B" ] && [ -f "$S" ]; then
    check "t3 BASE.md opens the class-table region" grep -q '<!-- class table' "$B"
    check "t3 BASE.md closes the class-table region" grep -q '<!-- end class table' "$B"
    check "t3 the class table is generated, bin/build.sh --check clean" bash "$P/bin/build.sh" --check
    check "t3 skills/base/SKILL.md is BASE.md under a frontmatter" python3 -c '
import sys
base = open(sys.argv[1], encoding="utf-8").read().strip("\n") + "\n"
skill = open(sys.argv[2], encoding="utf-8").read()
if not skill.startswith("---\n"): sys.exit(1)
body = skill.split("\n---\n", 1)[1].lstrip("\n") if "\n---\n" in skill else ""
sys.exit(0 if body == base else 1)
' "$B" "$S"
    check "t3 session:ask is the only session: name in the base" python3 -c '
import re, sys
bad = []
for p in sys.argv[1:]:
    for n, line in enumerate(open(p, encoding="utf-8").read().split("\n"), 1):
        for m in re.finditer(r"session:[a-z][a-z0-9-]*", line):
            if m.group(0) != "session:ask": bad.append("%s:%d %s" % (p, n, m.group(0)))
for b in bad[:10]: print(b)
sys.exit(1 if bad else 0)
' "$B" "$S"
    check "t3 no agent roster prose in the base" bash -c '! grep -Eq "agentType|subagent_type: *.(session:|tools-)|\btools-(read|write|edit|web)[a-z-]*" "$1"' _ "$B"
    # the same rule over the role catalog of lib/classes.json, which the grep above never sees: a
    # roster of bare role names is still a roster. Only roster SHAPES count - a list or numbered
    # entry that starts with a role name, a table row whose first cell is one, and a role name
    # standing beside a slot word - so "a critic may raise the class" stays plain English. Executed
    # over the base and over three mutants that must turn it red.
    cat > "$T/roster.py" <<'PY'
import json, re, sys
roles = sorted(json.load(open(sys.argv[1], encoding='utf-8'))['roles'], key=len, reverse=True)
alt = '|'.join(re.escape(r) for r in roles)
name = r'[`*_]*(?:session:)?(%s)[`*_]*' % alt
shapes = [
    ('list entry', re.compile(r'^\s*(?:[-*+]|\d+\.)\s+%s\s*(?:[-–—:(,]|$)' % name)),
    ('table row', re.compile(r'^\s*\|\s*%s\s*\|' % name)),
    ('name beside a slot', re.compile(
        r'\b(%s)\b[^.|]{0,40}\b(?:main|opus|sonnet)(?:-model)?\s+slot'
        r'|\b(?:main|opus|sonnet)(?:-model)?\s+slot[^.|]{0,40}\b(%s)\b' % (alt, alt))),
]
hits = []
for p in sys.argv[2:]:
    for n, line in enumerate(open(p, encoding='utf-8').read().split('\n'), 1):
        for what, rx in shapes:
            m = rx.search(line)
            if m:
                hits.append('%s:%d roster %s: %s' % (p, n, what, next(g for g in m.groups() if g)))
for h in hits[:10]:
    print(h)
sys.exit(1 if hits else 0)
PY
    check "t3 no roster of role catalog names in the base" \
      python3 "$T/roster.py" "$P/lib/classes.json" "$B" "$S"
    ROLE1=$(python3 -c '
import json, sys
print(sorted(json.load(open(sys.argv[1], encoding="utf-8"))["roles"])[0])' "$P/lib/classes.json")
    { cat "$B"; printf -- '- `%s` — the author of the plan, opus slot\n' "$ROLE1"; } > "$T/roster-list.md"
    { cat "$B"; printf '| %s | opus slot |\n' "$ROLE1"; } > "$T/roster-table.md"
    { cat "$B"; printf 'The %s runs on the opus slot of the class.\n' "$ROLE1"; } > "$T/roster-slot.md"
    for m in list table slot; do
      check "t3 the roster check catches a $m of role names" \
        bash -c '! python3 "$1" "$2" "$3" > /dev/null' _ "$T/roster.py" "$P/lib/classes.json" "$T/roster-$m.md"
    done
    # a role word used as a plain English word in a sentence about process stays clean
    printf 'A critic may raise the class for the stages that follow, never lower it.\nThe fixer of a finding reads what the executor left.\n' > "$T/roster-prose.md"
    check "t3 a role word in plain prose is no roster" \
      python3 "$T/roster.py" "$P/lib/classes.json" "$T/roster-prose.md"
    check "t3 the base takes the verification page path from the session-start line" \
      grep -Fq 'session-start context line' "$B"
    check "t3 the base resolves no path of its own for the verification page" bash -c \
      '! grep -F "verification.md" "$1" | grep -Eq "ls -d|sort -V|tail -1"' _ "$B"
    check "t3 the section Stages and quality loops is gone" bash -c '! grep -q "^## Stages and quality loops" "$1"' _ "$B"
    check "t3 no mandatory review of a diff over 100 lines" bash -c '! grep -qi "over 100 lines" "$1"' _ "$B"
    check "t3 no mandatory closure review" bash -c '! grep -qi "closure review" "$1"' _ "$B"
    check "t3 no author pairs with a reviewer by default" bash -c '! grep -qi "pairs with an independent review" "$1"' _ "$B"
    check "t3 the base cites lib/verification.md" grep -Fq 'lib/verification.md' "$B"
    check "t3 the base states review only where no oracle is possible" grep -Fq 'gets no review' "$B"
    check "t3 the base states launch by name" grep -Fq 'Launch by name; an ad hoc script is the exception' "$B"
    check "t3 the base carries the fork-author exception" grep -Fq 'clean-context checker' "$B"
    check "t3 the base carries the critic class raise" grep -Fq 'raise the class for the stages that follow' "$B"
    check "t3 the base feeds the size argument" grep -Fq 'the `size` argument' "$B"
    for v in small medium large; do
      check "t3 the volume table has the row $v" grep -Eq "^\| $v \|" "$B"
    done
    check "t3 one line sends a codex job to the codex skill" grep -Eq '^Codex job: ' "$B"
  else
    fail "t3 base/BASE.md or skills/base/SKILL.md missing"
  fi
fi

# t4: the composite workflows cite the verification page instead of repeating it (P6). Comment
# lines are cut before the grep, the way k8 of usage-test.sh cuts them: a citation that stands only
# in a note to a reader of the script reaches no agent of the flow. A missing workflow is a failure
# here, never a skip, or the criterion would pass over a file nobody wrote.
for w in chain make; do
  f=$P/workflows/$w.js
  if [ -f "$f" ]; then
    check "t4 workflows/$w.js cites lib/verification.md in a prompt" \
      bash -c 'grep -v "^[[:space:]]*//" "$1" | grep -Fq "lib/verification.md"' _ "$f"
  else
    fail "t4 workflows/$w.js missing"
  fi
done

if [ "$FAILS" -eq 0 ]; then echo "text: PASS $N"; exit 0; fi
echo "text: FAIL $FAILS failures, $N checks passed"
exit 1
