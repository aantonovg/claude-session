#!/bin/bash
# Verifier for plugins/session/bin/workflow-usage.sh: the usage blocks of the project workflows,
# plain mode, hook mode (--hook --file/--dir/--prefix), escaping, the user and project override
# rules, the real collector's timing. Temp dirs and fixtures only, no network, runs under 20 s.
# The plugin workflows themselves are owned by tests/plugin/contracts.sh.
set -u

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
P=$REPO/plugins/session
COLLECTOR=$P/bin/workflow-usage.sh
BASE=$P/base/BASE.md
SKILL=$P/skills/base/SKILL.md

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

# Baseline: arg names of each usage block of the project workflows.
args_of() {
  case $1 in
    memory-gc) echo "trim class submodes" ;;
    skill-author) echo "name purpose sources cap out reviews absorbs class submodes" ;;
    test-session) echo "scenarios runner out ids parser budget class submodes" ;;
  esac
}
# Step 1 baseline: shasum (first 12 chars) of the whenToUse line.
when_of() {
  case $1 in
    memory-gc) echo 1f7e0a0699b4 ;; skill-author) echo df4695e1aca5 ;;
    test-session) echo 9c7fa53f7327 ;;
  esac
}
# Step 1 baseline: `node --check` exit code of every unmodified script
# (all 1: top-level `return` is illegal outside the workflow runtime).
NODE_BASE=1

SCRIPTS=()
for n in memory-gc skill-author test-session; do SCRIPTS+=("$REPO/.claude/workflows/$n.js"); done

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
  (cd "$2" && env -u CLAUDE_PROJECT_DIR HOME=$1 sh "$T/plugin/bin/workflow-usage.sh" > "$T/out" 2> "$T/err"; echo $? > "$T/rc")
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
real=$(cd "$REPO" && env -u CLAUDE_PROJECT_DIR sh "$COLLECTOR" 2>/dev/null); rc=$?
t1=$(now_ms)
ms=$((t1 - t0))
echo "usage-test: real collector ${ms} ms"
check "c6 d real exit 0" test "$rc" -eq 0
check "c6 d real under 3 s (${ms} ms)" test "$ms" -lt 3000
got=$(printf '%s\n' "$real" | sed -E 's/^- ([^ ]+) — .*/\1/' | grep -v '^$' | tr '\n' ' ')
check "c5 d real names and order (got $got)" test "$got" = "$(printf '%s ' "${exp[@]}")"

# ---------- wf-hook-dev2 plan: labels k<criterion> ----------
WHY='(launch by name; contract below; never read the script body)'
entry() { printf 'Workflow %s %s: %s' "$1" "$WHY" "$2"; }  # $1 launch name, $2 usage text
cat > "$T/j.py" <<'PY'
import json, sys
mode, path = sys.argv[1], sys.argv[2]
raw = open(path, 'rb').read()
try:
    txt = raw.decode('utf-8')
    d = json.loads(txt)
except Exception as e:
    print('invalid: %s' % e, file=sys.stderr); sys.exit(1)
h = d.get('hookSpecificOutput', {}) if isinstance(d, dict) else {}
c = h.get('additionalContext')
if mode == 'valid': sys.exit(0)
if mode == 'oneline': sys.exit(0 if txt.strip('\n') and '\n' not in txt.rstrip('\n') else 1)
if mode == 'event': print(h.get('hookEventName', '')); sys.exit(0)
if not isinstance(c, str): sys.exit(1)
if mode == 'ctx': sys.stdout.buffer.write(c.encode('utf-8')); sys.exit(0)
if mode == 'eq': sys.exit(0 if c == open(sys.argv[3], encoding='utf-8').read() else 1)
PY
jvalid() { python3 "$T/j.py" valid "$1" 2>/dev/null; }
jone() { python3 "$T/j.py" oneline "$1" 2>/dev/null; }
jeq() { python3 "$T/j.py" eq "$1" "$2" 2>/dev/null; }  # $1 hook output, $2 file with expected context
wfx() { printf 'export const meta = {}\n}\n/* usage:\n%s\n*/\n' "$2" > "$1"; }
# $1 plugin root (bin/ copy of collector), $2 HOME, $3 cwd, rest collector args -> $T/ko, $T/ke, $T/kr
runk() {
  local root=$1 home=$2 cwd=$3; shift 3
  (cd "$cwd" && env -u CLAUDE_PROJECT_DIR HOME="$home" sh "$root/bin/workflow-usage.sh" "$@" > "$T/ko" 2> "$T/ke"; echo $? > "$T/kr")
}
K=$T/k2
mkdir -p "$K/pl/bin" "$K/pl/workflows" "$K/home/.claude/workflows" "$K/proj/.claude/workflows" "$K/x" "$K/other/.claude/workflows" "$K/empty" "$K/txt"
cp "$COLLECTOR" "$K/pl/bin/workflow-usage.sh"

# k1: --hook --file
wfx "$K/x/a.js" 'Alpha   summary.
  Args: x (string, required).'
wfx "$K/x/b.js" 'Bee text.'
printf 'not js\n' > "$K/x/notes.txt"
runk "$K/pl" "$K/home" "$K/proj" --hook --file "$K/x/a.js" --prefix session
check "k1 --file exit 0" test "$(cat "$T/kr")" = 0
check "k1 --file exactly one line" jone "$T/ko"
check "k1 --file json.loads" jvalid "$T/ko"
check "k1 --file hookEventName SessionStart" test "$(python3 "$T/j.py" event "$T/ko" 2>/dev/null)" = SessionStart
entry session:a 'Alpha summary. Args: x (string, required).' > "$T/exp"
check "k1 --file additionalContext entry with session: prefix" jeq "$T/ko" "$T/exp"
runk "$K/pl" "$K/home" "$K/proj" --hook --file "$K/x/a.js"
entry a 'Alpha summary. Args: x (string, required).' > "$T/exp"
check "k1 --file without --prefix bare stem" jeq "$T/ko" "$T/exp"

# k2: --hook --dir
runk "$K/pl" "$K/home" "$K/proj" --hook --dir "$K/x"
check "k2 --dir exit 0" test "$(cat "$T/kr")" = 0
check "k2 --dir exactly one line" jone "$T/ko"
check "k2 --dir hookEventName SessionStart" test "$(python3 "$T/j.py" event "$T/ko" 2>/dev/null)" = SessionStart
{ entry a 'Alpha summary. Args: x (string, required).'; printf '\n'; entry b 'Bee text.'; } > "$T/exp"
check "k2 --dir entries newline-joined in glob order, .js only" jeq "$T/ko" "$T/exp"
wfx "$K/home/.claude/workflows/c.js" 'Cee user.'
wfx "$K/home/.claude/workflows/d.js" 'Dee user.'
wfx "$K/proj/.claude/workflows/d.js" 'Dee project.'
wfx "$K/other/.claude/workflows/o.js" 'Other cwd.'
runk "$K/pl" "$K/home" "$K/proj" --hook --dir @user
entry c 'Cee user.' > "$T/exp"
check "k2 @user skips stem present in project dir" jeq "$T/ko" "$T/exp"
runk "$K/pl" "$K/home" "$K/proj" --hook --dir @project
entry d 'Dee project.' > "$T/exp"
check "k2 @project from PWD holds overriding stem" jeq "$T/ko" "$T/exp"
(cd "$K/other" && HOME="$K/home" CLAUDE_PROJECT_DIR="$K/proj" sh "$K/pl/bin/workflow-usage.sh" --hook --dir @project > "$T/ko" 2>/dev/null)
check "k2 @project uses CLAUDE_PROJECT_DIR over PWD" jeq "$T/ko" "$T/exp"
(cd "$K/other" && HOME="$K/home" CLAUDE_PROJECT_DIR="$K/proj" sh "$K/pl/bin/workflow-usage.sh" --hook --dir @user > "$T/ko" 2>/dev/null)
entry c 'Cee user.' > "$T/exp"
check "k2 @user override uses CLAUDE_PROJECT_DIR over PWD" jeq "$T/ko" "$T/exp"
(cd "$K/other" && env -u CLAUDE_PROJECT_DIR HOME="$K/home" sh "$K/pl/bin/workflow-usage.sh" --hook --dir @user > "$T/ko" 2>/dev/null)
{ entry c 'Cee user.'; printf '\n'; entry d 'Dee user.'; } > "$T/exp"
check "k2 @user keeps stem absent from project dir" jeq "$T/ko" "$T/exp"
(cd "$K/other" && HOME="$K/home" CLAUDE_PROJECT_DIR="$K/home" sh "$K/pl/bin/workflow-usage.sh" --hook --dir @project > "$T/ko" 2>&1; echo $? > "$T/kr")
check "k2 @project equal to @user real path prints nothing" test ! -s "$T/ko" -a "$(cat "$T/kr")" = 0
mkdir -p "$K/pp/.claude/bin" "$K/pp/.claude/workflows"
cp "$COLLECTOR" "$K/pp/.claude/bin/workflow-usage.sh"
wfx "$K/pp/.claude/workflows/p.js" 'Plugin one.'
(cd "$K/other" && HOME="$K/home" CLAUDE_PROJECT_DIR="$K/pp" sh "$K/pp/.claude/bin/workflow-usage.sh" --hook --dir @project > "$T/ko" 2>&1; echo $? > "$T/kr")
check "k2 @project equal to plugin workflows real path prints nothing" test ! -s "$T/ko" -a "$(cat "$T/kr")" = 0
(cd "$K/other" && HOME="$K/home" CLAUDE_PROJECT_DIR="$K/proj" sh "$K/pp/.claude/bin/workflow-usage.sh" --hook --dir @project > "$T/ko" 2>/dev/null)
entry d 'Dee project.' > "$T/exp"
check "k2 @project control case with same plugin copy prints entry" jeq "$T/ko" "$T/exp"

# k3: escaping (quote, backslash, tab, \001)
printf 'export const meta = {}\n}\n/* usage:\nsay "hi" back\\slash tab\there ctl\001end\n*/\n' > "$K/x/esc.js"
runk "$K/pl" "$K/home" "$K/proj" --hook --file "$K/x/esc.js"
check "k3 escape json.loads" jvalid "$T/ko"
check "k3 escape exactly one line" jone "$T/ko"
entry esc "$(printf 'say "hi" back\\slash tab\there ctl\001end')" > "$T/exp"
check "k3 escape additionalContext keeps quote, backslash, tab, U+0001" jeq "$T/ko" "$T/exp"
check "k3 escape raw output holds \\u0001" grep -Fq '\u0001' "$T/ko"
check "k3 escape raw output holds \\t" grep -Fq 'tab\there' "$T/ko"
check "k3 escape raw output has no raw control bytes" python3 -c '
import sys
b = open(sys.argv[1], "rb").read().rstrip(b"\n")
sys.exit(0 if b and not any(x < 32 for x in b) else 1)
' "$T/ko"

# k4: silent failures, plain mode
k4() {  # $1 label, rest collector args
  local label=$1; shift
  runk "$K/pl" "$K/home" "$K/proj" "$@"
  check "k4 $label exit 0" test "$(cat "$T/kr")" = 0
  check "k4 $label no stdout" test ! -s "$T/ko"
  check "k4 $label no stderr" test ! -s "$T/ke"
}
printf 'x\n' > "$K/txt/a.txt"
k4 "missing file" --hook --file "$K/x/nope.js" --prefix session
k4 "missing dir" --hook --dir "$K/nope"
k4 "empty dir" --hook --dir "$K/empty"
k4 "dir without .js" --hook --dir "$K/txt"
k4 "--file without value" --hook --file
k4 "--dir without value" --hook --dir
real_plain=$(cd "$REPO" && env -u CLAUDE_PROJECT_DIR sh "$COLLECTOR" 2>/dev/null)
check "k4 plain real lists session:helper" grep -q '^- session:helper — ' <<<"$real_plain"


if [ "$FAILS" -eq 0 ]; then echo "usage-test: PASS $N"; exit 0; fi
echo "usage-test: FAIL $FAILS failures, $N checks passed"; exit 1
