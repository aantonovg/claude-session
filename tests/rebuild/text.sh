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

if [ "$FAILS" -eq 0 ]; then echo "text: PASS $N"; exit 0; fi
echo "text: FAIL $FAILS failures, $N checks passed"
exit 1
