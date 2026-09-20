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
# Rule: no text of the new set names a model, a reasoning level or a tier. The only allowed forms
# of a model word are the slot names ("opus slot", "sonnet slot") and the submode names
# ("no-sonnet", "no-opus", "no-fable"); a generated region between build markers is skipped,
# because the class table itself is rendered there by bin/build.sh.
# Also: lib/verification.md carries the pieces P1 owes (oracle classes, a route per ladder level,
# the fork-author exception, the ops control-call form).
# From P6 on, under --with-base: the base text is one of those globs, it carries the class table
# only as a generated region, it names no carrier but the session:ask skill, the cut sections of
# P6 are gone, and it points at lib/verification.md instead of repeating it. P6 also reads the two
# composite workflows for that pointer (workflows/chain.js, workflows/make.js), a fixed extension
# of the glob list of the plan's scope rule, because no other static test owns that citation.
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

cat > /tmp/.text-scan.$$ <<'PY'
import re, sys

BEGIN = ('// ---- shared block', '// ---- class table', '// ---- roles', '// ---- aspects', '<!-- class table')
END = ('// ---- end shared block', '// ---- end class table', '// ---- end roles', '// ---- end aspects', '<!-- end class table')
MODEL = re.compile(r'(?i)(no-)?\b(opus|sonnet|fable|haiku)\b([- ]slot)?')
WORDS = re.compile(r'(?i)\b(effort|tier)\b')
KEY = re.compile(r'(?im)^(model|effort):')

hits = []
for path in sys.argv[1:]:
    try:
        lines = open(path, encoding='utf-8').read().split('\n')
    except OSError:
        continue
    skip = False
    for n, line in enumerate(lines, 1):
        s = line.strip()
        if skip:
            if s.startswith(END): skip = False
            continue
        if s.startswith(BEGIN):
            skip = True
            continue
        for m in MODEL.finditer(line):
            if m.group(1) or m.group(3): continue
            hits.append('%s:%d names a model: %s' % (path, n, m.group(0)))
        for m in WORDS.finditer(line):
            hits.append('%s:%d names a reasoning level or a tier: %s' % (path, n, m.group(0)))
        if KEY.match(line):
            hits.append('%s:%d pins it in frontmatter: %s' % (path, n, s))
for h in hits[:20]:
    print(h)
sys.exit(1 if hits else 0)
PY
if python3 /tmp/.text-scan.$$ "${FILES[@]}"; then pass; else fail "t1 no model, reasoning level or tier in the new text"; fi
rm -f /tmp/.text-scan.$$

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

# t4: the composite workflows cite the verification page instead of repeating it (P6).
for w in chain make; do
  f=$P/workflows/$w.js
  [ -f "$f" ] || continue
  check "t4 workflows/$w.js cites lib/verification.md" grep -Fq 'lib/verification.md' "$f"
done

if [ "$FAILS" -eq 0 ]; then echo "text: PASS $N"; exit 0; fi
echo "text: FAIL $FAILS failures, $N checks passed"
exit 1
