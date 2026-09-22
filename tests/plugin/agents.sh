#!/bin/bash
# One agent file per plugin helper of lib/classes.json and no other; frontmatter name, description
# under 100 tokens, tools line; no model and no effort key; the body names result.md, the three
# handback lines and the blocked rule; a Bash agent carries the long-command recipe; a helper
# without Bash says which tool it lacks.
set -u
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
helpers=$(node -e 'const c=require(process.argv[1]); for (const [k,v] of Object.entries(c.helpers)) if (v.agent.startsWith("session:")) console.log(k)' "$P/lib/classes.json")
for h in $helpers; do
  f=$P/agents/$h.md
  check "agents/$h.md exists" test -f "$f"
  [ -f "$f" ] || continue
  fm=$(frontmatter "$f")
  check "$h frontmatter name" grep -Fxq "name: $h" <<<"$fm"
  d=$(grep -E '^description: ' <<<"$fm" | sed 's/^description: //')
  check "$h description present" test -n "$d"
  t=$(printf '%s' "$d" | tokens)
  check "$h description under 100 tokens (got $t)" test "$t" -le 100
  check "$h frontmatter tools" grep -Eq '^tools: .+' <<<"$fm"
  check "$h no model key" bash -c '! grep -Eq "^model:" <<<"$1"' _ "$fm"
  check "$h no effort key" bash -c '! grep -Eq "^effort:" <<<"$1"' _ "$fm"
  b=$(body "$f")
  check "$h body names result.md" grep -Fq 'result.md' <<<"$b"
  check "$h body: first line of result.md is the status" grep -Fq 'its first line `status: <the same status as the handback>`' <<<"$b"
  for l in 'status: completed | partial | blocked | failed' 'report: <absolute path' 'summary: <one line'; do
    check "$h body carries handback line '$l'" grep -Fq "$l" <<<"$b"
  done
  check "$h body: blocked rule" grep -Fq 'status: blocked' <<<"$b"
  check "$h body: completed means the contract, not the object" grep -Fq 'not that the object is fine' <<<"$b"
  if grep -Eq '^tools: .*\bBash\b' <<<"$fm"; then
    check "$h Bash agent carries the detached recipe" grep -Fq 'touch <dir>/done' <<<"$b"
    check "$h Bash agent never ends with a background job" grep -Fq 'Never end a turn with a background job running' <<<"$b"
  fi
done
for f in "$P"/agents/*.md; do
  n=$(basename "$f" .md)
  check "agents/$n.md is a helper of classes.json" grep -qx "$n" <<<"$helpers"
done
check "no tool-set agent left" bash -c '! ls "$1"/agents/tools-*.md >/dev/null 2>&1' _ "$P"
done_with agents
