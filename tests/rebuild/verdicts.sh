#!/bin/bash
# The only reader of behavior verdicts in a part's Test.
#
#   tests/rebuild/verdicts.sh <variant>:<key> [<variant>:<key> ...]
#
# Root: $VERDICTS_ROOT, default $HOME/.claude/jobs/rebuild-0.16/results, the same default
# tests/rebuild/scenario-run.sh writes to and outside the repo. Under it one directory per
# variant, one run directory per run (named <run-ts>, so the names sort chronologically), each with
# a verdicts.txt of lines:
#
#   <variant> <key> <PASS|FAIL> <run-ts> <commit>
#
# Per pair: the newest run directory of that variant that holds the key wins, and inside it the
# last line for the key. A missing key fails, a FAIL line fails, a verdict of another key never
# stands in for the asked one, and a rerun after a fix wins because it is newer.
#
# A PASS counts only when it covers the code of HEAD, which is three questions, not one:
#   - the commit carries `+dirty`: the run sat on an uncommitted tree, so no commit describes what
#     ran and the verdict is refused (scenario-run.sh writes the marker);
#   - the commit is an ancestor of HEAD: it passes only while plugins/session and tests are
#     unchanged between that commit and HEAD, and the line says which of the two it is.
set -u

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ROOT=${VERDICTS_ROOT:-$HOME/.claude/jobs/rebuild-0.16/results}
HEADSHA=$(git -C "$REPO" rev-parse HEAD 2>/dev/null)

if [ "$#" -eq 0 ]; then
  echo "verdicts: no argument; want <variant>:<key> ..." >&2
  exit 2
fi

fails=0
for pair in "$@"; do
  variant=${pair%%:*}; key=${pair#*:}
  if [ "$variant" = "$pair" ] || [ -z "$variant" ] || [ -z "$key" ]; then
    echo "verdicts: bad argument $pair; want <variant>:<key>" >&2; fails=$((fails + 1)); continue
  fi
  line=
  dir=
  for d in $(ls -1 "$ROOT/$variant" 2>/dev/null | sort -r); do
    f=$ROOT/$variant/$d/verdicts.txt
    [ -f "$f" ] || continue
    # field equality, not a regex: a key holding . or * must never match another key's line
    l=$(awk -v v="$variant" -v k="$key" '$1 == v && $2 == k' "$f" | tail -1)
    if [ -n "$l" ]; then line=$l; dir=$ROOT/$variant/$d; break; fi
  done
  if [ -z "$line" ]; then
    echo "verdicts: no verdict for $variant:$key under $ROOT/$variant" >&2; fails=$((fails + 1)); continue
  fi
  verdict=$(echo "$line" | awk '{print $3}')
  commit=$(echo "$line" | awk '{print $5}')
  if [ "$verdict" != PASS ]; then
    echo "verdicts: $variant:$key is $verdict in $dir" >&2; fails=$((fails + 1)); continue
  fi
  if [ -z "$commit" ]; then
    echo "verdicts: $variant:$key names no commit in $dir" >&2; fails=$((fails + 1)); continue
  fi
  case $commit in
    *+dirty)
      echo "verdicts: $variant:$key ran on an uncommitted tree at ${commit%+dirty}: no commit describes the code that ran" >&2
      fails=$((fails + 1)); continue ;;
  esac
  if ! git -C "$REPO" merge-base --is-ancestor "$commit" HEAD 2>/dev/null; then
    echo "verdicts: $variant:$key ran at $commit, not HEAD and not an ancestor of HEAD" >&2; fails=$((fails + 1)); continue
  fi
  if [ "$commit" = "$HEADSHA" ]; then
    echo "verdicts: $variant:$key PASS at HEAD ($dir)"
    continue
  fi
  if ! git -C "$REPO" diff --quiet "$commit" HEAD -- plugins/session tests 2>/dev/null; then
    echo "verdicts: $variant:$key ran at $commit, an ancestor of HEAD, and plugins/session or tests changed since: the verdict covers superseded code" >&2
    fails=$((fails + 1)); continue
  fi
  echo "verdicts: $variant:$key PASS at $commit, an ancestor of HEAD with plugins/session and tests unchanged since ($dir)"
done

[ "$fails" -eq 0 ] || exit 1
