#!/bin/bash
# Verifier for plugins/session/bin/workflow-usage.sh, workflow usage blocks,
# BASE.md "Named workflows" section and split.sh allowed-tools line.
# Temp dirs and fixtures only, no network, runs under 20 s.
# Check labels carry the plan criterion number: c1..c9.
set -u

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
P=$REPO/plugins/session
COLLECTOR=$P/bin/workflow-usage.sh
BASE=$P/base/BASE.md
SKILL=$P/skills/base/SKILL.md
INJECT='!`sh ${CLAUDE_PLUGIN_ROOT}/bin/workflow-usage.sh`'
ALLOW='allowed-tools: Bash(sh ${CLAUDE_PLUGIN_ROOT}/bin/workflow-usage.sh)'

T=$(mktemp -d) || exit 1
cleanup() { chmod 755 "$T/h/proj/.claude/workflows" 2>/dev/null; rm -rf "$T"; }
trap cleanup EXIT

N=0; FAILS=0
pass() { N=$((N + 1)); }
fail() { echo "FAIL $1"; FAILS=$((FAILS + 1)); }
check() {  # $1 label, rest: command
  local label=$1; shift
  if "$@"; then pass; else fail "$label"; fi
}
now_ms() { perl -MTime::HiRes=time -e 'printf "%d\n", time * 1000'; }

# Step 1 baseline: arg names of each old `Args:` list.
args_of() {
  case $1 in
    build) echo "cwd plan class submodes test" ;;
    dev) echo "cwd task class submodes paths test out" ;;
    research) echo "cwd question directions paths class submodes out" ;;
    review-fix) echo "cwd target class submodes test fix" ;;
    memory-gc) echo "trim class submodes" ;;
    skill-author) echo "name purpose sources cap out reviews absorbs class submodes" ;;
    test-session) echo "scenarios runner out ids parser budget class submodes" ;;
    translate-ru) echo "file out class submodes" ;;
  esac
}
# Step 1 baseline: shasum (first 12 chars) of the whenToUse line.
when_of() {
  case $1 in
    build) echo bf8556d8f89f ;; dev) echo f986277b56a2 ;; research) echo aa621fd9bdd1 ;;
    review-fix) echo bb6ec7d84d07 ;; memory-gc) echo 1f7e0a0699b4 ;; skill-author) echo df4695e1aca5 ;;
    test-session) echo 9c7fa53f7327 ;; translate-ru) echo 951e6f4e2e07 ;;
  esac
}
# Step 1 baseline: `node --check` exit code of every unmodified script
# (all 1: top-level `return` is illegal outside the workflow runtime).
NODE_BASE=1

SCRIPTS=()
for n in build dev research review-fix; do SCRIPTS+=("$P/workflows/$n.js"); done
for n in memory-gc skill-author test-session; do SCRIPTS+=("$REPO/.claude/workflows/$n.js"); done
[ -f "$HOME/.claude/workflows/translate-ru.js" ] && SCRIPTS+=("$HOME/.claude/workflows/translate-ru.js")

# ---------- c1, c2, c3: real scripts ----------
for f in "${SCRIPTS[@]}"; do
  s=$(basename "$f" .js)
  meta=$(awk '/meta = \{/{m=1} m{print} m&&/^\}/{exit}' "$f")
  end=$(awk '/meta = \{/{m=1} m&&/^\}/{print NR; exit}' "$f")
  desc=$(printf '%s\n' "$meta" | grep -E "^  description:" | sed -E "s/^  description: *['\"](.*)['\"],? *$/\1/")
  words=$(printf '%s' "$desc" | wc -w | tr -d ' ')
  check "c1 $s description 1-4 words (got $words)" test "$words" -ge 1 -a "$words" -le 4
  keys=$(printf '%s\n' "$meta" | grep -oE '^  [A-Za-z]+:' | tr -d ' :' | sort | tr '\n' ' ')
  check "c1 $s meta keys (got $keys)" test "$keys" = "description name phases whenToUse "
  wh=$(printf '%s\n' "$meta" | grep -E '^  whenToUse:' | shasum | cut -c1-12)
  check "c1 $s whenToUse unchanged" test "$wh" = "$(when_of "$s")"

  cnt=$(grep -c '^/\* usage:' "$f")
  check "c2 $s exactly one /* usage: line (got $cnt)" test "$cnt" -eq 1
  start=$(grep -n '^/\* usage:' "$f" | head -1 | cut -d: -f1)
  check "c2 $s usage block right after meta close" test "${start:-0}" = "$((end + 1))"
  block=$(awk 'f==0&&/^\/\* usage:/{f=1} f{print} f&&/\*\//{exit}' "$f")
  closed=$(printf '%s\n' "$block" | tail -1 | grep -c '\*/')
  check "c2 $s usage block closed by */" test "$closed" -eq 1
  inner=$(printf '%s\n' "$block" | sed -e 's#^/\* usage:##' -e 's#\*/##' | tr -d ' \n\t')
  check "c2 $s usage block non-empty" test -n "$inner"
  for a in $(args_of "$s"); do
    check "c2 $s usage names arg $a" grep -qw -- "$a" <<<"$block"
  done
  node --check "$f" >/dev/null 2>&1; rc=$?
  check "c3 $s node --check exit $rc equals baseline $NODE_BASE" test "$rc" -eq "$NODE_BASE"
done

# ---------- c4, c5: fixture tree (case a) ----------
mk_fixture() {
  mkdir -p "$T/plugin/bin" "$T/plugin/workflows" "$T/h/home/.claude/workflows" "$T/h/proj/.claude/workflows"
  cp "$COLLECTOR" "$T/plugin/bin/workflow-usage.sh" 2>/dev/null
  printf 'export const meta = {\n  name: %s,\n}\n/* usage:\nAlpha   summary.\n  Args: x (string, required).\n*/\n' "'a'" > "$T/plugin/workflows/a.js"
  printf 'export const meta = {\n  name: %s,\n}\n' "'b'" > "$T/plugin/workflows/b.js"
  printf 'export const meta = {}\n}\n/* usage:\nCee user text.\n*/\n' > "$T/h/home/.claude/workflows/c.js"
  printf 'export const meta = {}\n}\n/* usage:\nDee user text.\n*/\n' > "$T/h/home/.claude/workflows/d.js"
  printf 'export const meta = {}\n}\n/* usage:\nDee project text.\n*/\n' > "$T/h/proj/.claude/workflows/d.js"
}
run_fix() {  # $1 HOME, $2 cwd -> $T/out, $T/err, $T/rc
  (cd "$2" && HOME=$1 sh "$T/plugin/bin/workflow-usage.sh" > "$T/out" 2> "$T/err"; echo $? > "$T/rc")
}
mk_fixture
run_fix "$T/h/home" "$T/h/proj"
check "c4 a exit 0" test "$(cat "$T/rc")" = 0
check "c4 a plugin line with collapsed usage" grep -Fxq -- '- session:a — Alpha summary. Args: x (string, required).' "$T/out"
check "c6 a no usage block line" grep -Fxq -- '- session:b — (no usage block)' "$T/out"
check "c4 a user line bare stem" grep -Fxq -- '- c — Cee user text.' "$T/out"
dn=$(grep -c '^- d — ' "$T/out")
check "c5 a exactly one d line (got $dn)" test "$dn" -eq 1
check "c5 a d holds project text" grep -Fxq -- '- d — Dee project text.' "$T/out"
order=$(sed -E 's/^- ([^ ]+) — .*/\1/' "$T/out" | tr '\n' ' ')
check "c5 a order session:a session:b c d (got $order)" test "$order" = "session:a session:b c d "
lines=$(wc -l < "$T/out" | tr -d ' ')
check "c4 a one line per workflow (got $lines)" test "$lines" -eq 4

# ---------- c6: case b, no .claude dirs ----------
mkdir -p "$T/b/home" "$T/b/proj"
run_fix "$T/b/home" "$T/b/proj"
check "c6 b exit 0" test "$(cat "$T/rc")" = 0
order=$(sed -E 's/^- ([^ ]+) — .*/\1/' "$T/out" | tr '\n' ' ')
check "c6 b only plugin lines (got $order)" test "$order" = "session:a session:b "

# ---------- c6: case h, empty user dir, unreadable project dir ----------
rm -f "$T/h/home/.claude/workflows/"*.js
chmod 000 "$T/h/proj/.claude/workflows"
run_fix "$T/h/home" "$T/h/proj"
check "c6 h exit 0" test "$(cat "$T/rc")" = 0
check "c6 h no stderr" test ! -s "$T/err"
order=$(sed -E 's/^- ([^ ]+) — .*/\1/' "$T/out" | tr '\n' ' ')
check "c6 h plugin lines still printed (got $order)" test "$order" = "session:a session:b "
chmod 755 "$T/h/proj/.claude/workflows"

# ---------- c6: case c, plugin workflows dir removed ----------
rm -rf "$T/plugin/workflows"
run_fix "$T/b/home" "$T/b/proj"
check "c6 c exit 0 without plugin dir" test "$(cat "$T/rc")" = 0
check "c6 c prints nothing" test ! -s "$T/out"

# ---------- c4, c5, c6: case d, real dirs ----------
exp=()
for f in "$P"/workflows/*.js; do [ -f "$f" ] && exp+=("session:$(basename "$f" .js)"); done
for f in "$HOME"/.claude/workflows/*.js; do
  [ -f "$f" ] || continue
  s=$(basename "$f" .js); [ -f "$REPO/.claude/workflows/$s.js" ] || exp+=("$s")
done
for f in "$REPO"/.claude/workflows/*.js; do [ -f "$f" ] && exp+=("$(basename "$f" .js)"); done
t0=$(now_ms)
real=$(cd "$REPO" && sh "$COLLECTOR" 2>/dev/null); rc=$?
t1=$(now_ms)
ms=$((t1 - t0))
echo "usage-test: real collector ${ms} ms"
check "c6 d real exit 0" test "$rc" -eq 0
check "c6 d real under 3 s (${ms} ms)" test "$ms" -lt 3000
got=$(printf '%s\n' "$real" | sed -E 's/^- ([^ ]+) — .*/\1/' | grep -v '^$' | tr '\n' ' ')
check "c5 d real names and order (got $got)" test "$got" = "$(printf '%s ' "${exp[@]}")"

# ---------- c7, c8: BASE.md ----------
check "c7 BASE.md injection line" grep -Fxq -- "$INJECT" "$BASE"
check "c7 BASE.md lead line" grep -Fxq -- 'Launch names and args (contract):' "$BASE"
check "c8 BASE.md old contract text gone" bash -c '! grep -Fq "its meta description is the contract" "$1"' _ "$BASE"
check "c8 BASE.md new contract text" grep -Fq -- 'the usage list under Named workflows is the contract, never read the script body' "$BASE"
between=$(awk '/^## Named workflows$/{f=1; next} f&&/^## Classes, slots and submodes$/{ok=1; exit} f&&/^## /{exit} END{print ok+0}' "$BASE")
check "c7 Named workflows section right before Classes section" test "$between" = 1
lead=$(awk '/^## Named workflows$/{f=1; next} f&&/^## /{exit} f&&NF{print}' "$BASE" | tr '\n' '|')
check "c7 section holds lead line then injection line" test "$lead" = "Launch names and args (contract):|$INJECT|"

# ---------- c9: SKILL.md and split.sh (case f, g) ----------
check "c9 SKILL.md injection line" grep -Fxq -- "$INJECT" "$SKILL"
fm=$(awk 'NR==1&&/^---$/{f=1; next} f&&/^---$/{exit} f{print}' "$SKILL")
check "c9 SKILL.md frontmatter allowed-tools" grep -Fxq -- "$ALLOW" <<<"$fm"
allow_cmd=$(printf '%s\n' "$fm" | grep '^allowed-tools:' | sed -E 's/^allowed-tools: Bash\((.*)\)$/\1/')
inj_cmd=$(printf '%s' "$INJECT" | sed -E 's/^!`(.*)`$/\1/')
check "c9 allowed-tools command equals injected command" test -n "$allow_cmd" -a "$allow_cmd" = "$inj_cmd"
mkdir -p "$T/g/plugin/skills/base"
cp -R "$P/base" "$T/g/plugin/base"
sh "$T/g/plugin/base/split.sh" > /dev/null 2>&1
check "c9 split.sh regenerates identical SKILL.md" cmp -s "$T/g/plugin/skills/base/SKILL.md" "$SKILL"

if [ "$FAILS" -eq 0 ]; then
  echo "usage-test: PASS $N"; exit 0
fi
echo "usage-test: FAIL $FAILS failures, $N checks passed"
exit 1
