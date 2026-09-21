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
# Scenarios: $VERDICTS_SCENARIOS, default tests/measure/rebuild-scenarios-0.16.txt; the kind line of
# the key's block (judgment or machine) picks the rule. A key with no kind fails.
#
# Per pair: every run directory of that variant that holds the key is one recorded run, oldest
# first, and inside it the last line for the key is that run's verdict. A verdict of another key
# never stands in for the asked one. A run counts only when it covers the code of HEAD:
#   - the commit carries `+dirty`: the run sat on an uncommitted tree, so no commit describes what
#     ran and the run is refused (scenario-run.sh writes the marker);
#   - the commit is HEAD, or an ancestor of HEAD with plugins/session and tests unchanged since;
#     any other commit is refused and the line says why.
# The decision is gateDecision() of lib/block.js: judgment needs 2 PASS out of at most 3 counted
# runs (2 FAIL fail, fewer runs are unsettled), machine takes the newest counted run. One line per
# pair names the kind, the PASS and FAIL counts and the decision; only PASS exits 0.
set -u

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ROOT=${VERDICTS_ROOT:-$HOME/.claude/jobs/rebuild-0.16/results}
SCEN=${VERDICTS_SCENARIOS:-$REPO/tests/measure/rebuild-scenarios-0.16.txt}
BLOCK=${VERDICTS_BLOCK:-$REPO/plugins/session/lib/block.js}
HEADSHA=$(git -C "$REPO" rev-parse HEAD 2>/dev/null)

if [ "$#" -eq 0 ]; then
  echo "verdicts: no argument; want <variant>:<key> ..." >&2
  exit 2
fi
command -v node >/dev/null 2>&1 || { echo "verdicts: node is required" >&2; exit 2; }

current() { # <variant:key> <commit> <run dir> <verdict>: 0 when the run covers the code of HEAD
  case $2 in
    *+dirty)
      echo "verdicts: $1 run $3 ran on an uncommitted tree at ${2%+dirty}: no commit describes the code that ran" >&2
      return 1 ;;
  esac
  if [ "$2" = "$HEADSHA" ]; then
    if [ "$4" = PASS ]; then echo "verdicts: $1 run $3 PASS at HEAD"; else echo "verdicts: $1 run $3 FAIL at HEAD"; fi
    return 0
  fi
  if ! git -C "$REPO" merge-base --is-ancestor "$2" HEAD 2>/dev/null; then
    echo "verdicts: $1 run $3 ran at $2, not HEAD and not an ancestor of HEAD" >&2; return 1
  fi
  if ! git -C "$REPO" diff --quiet "$2" HEAD -- plugins/session tests 2>/dev/null; then
    echo "verdicts: $1 run $3 ran at $2, an ancestor of HEAD, and plugins/session or tests changed since: the verdict covers superseded code" >&2
    return 1
  fi
  echo "verdicts: $1 run $3 $4 at $2, an ancestor of HEAD with plugins/session and tests unchanged since"
  return 0
}

fails=0
for pair in "$@"; do
  variant=${pair%%:*}; key=${pair#*:}
  if [ "$variant" = "$pair" ] || [ -z "$variant" ] || [ -z "$key" ]; then
    echo "verdicts: bad argument $pair; want <variant>:<key>" >&2; fails=$((fails + 1)); continue
  fi
  kind=$(node -e 'const b = require(process.argv[1]), fs = require("fs")
    let t = ""; try { t = fs.readFileSync(process.argv[2], "utf8") } catch (e) {}
    process.stdout.write(b.scenarioKind(t, process.argv[3]) || "")' "$BLOCK" "$SCEN" "$key")
  runs=
  for d in $(ls -1 "$ROOT/$variant" 2>/dev/null | sort); do
    f=$ROOT/$variant/$d/verdicts.txt
    [ -f "$f" ] || continue
    # field equality, not a regex: a key holding . or * must never match another key's line
    l=$(awk -v v="$variant" -v k="$key" '$1 == v && $2 == k' "$f" | tail -1)
    [ -n "$l" ] || continue
    verdict=$(echo "$l" | awk '{print $3}'); commit=$(echo "$l" | awk '{print $5}')
    case $verdict in PASS|FAIL) ;; *) verdict=FAIL ;; esac
    cur=false
    if [ -z "$commit" ]; then echo "verdicts: $pair run $d names no commit" >&2
    elif current "$pair" "$commit" "$d" "$verdict"; then cur=true; fi
    runs="$runs$verdict $cur
"
  done
  [ -n "$runs" ] || echo "verdicts: no verdict for $pair under $ROOT/$variant" >&2
  [ -n "$kind" ] || echo "verdicts: $pair has no kind line in $SCEN" >&2
  line=$(printf '%s' "$runs" | node -e 'const b = require(process.argv[1])
    const runs = require("fs").readFileSync(0, "utf8").split("\n").filter(Boolean)
      .map(l => { const [verdict, c] = l.split(" "); return { verdict, current: c === "true" } })
    const d = b.gateDecision(process.argv[2] || null, runs)
    process.stdout.write(`kind ${d.kind || "none"} PASS ${d.pass} FAIL ${d.fail} decision ${d.decision}`)' "$BLOCK" "$kind")
  echo "verdicts: $pair $line"
  case $line in *"decision PASS") ;; *) fails=$((fails + 1)) ;; esac
done

[ "$fails" -eq 0 ] || exit 1
