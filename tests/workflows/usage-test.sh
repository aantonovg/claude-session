#!/bin/bash
# Verifier for plugins/session/bin/workflow-usage.sh, workflow usage blocks,
# hook mode (--hook --file/--dir/--prefix), plugin.json SessionStart hooks, translate-ru in plugin
# base and README. Temp dirs and fixtures only, no network, runs under 20 s.
# Labels: c1..c6 from the 0.15.16 plan, k<n> = wf-hook-dev2 acceptance criterion n.
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
SCRIPTS+=("$P/workflows/translate-ru.js")

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
check "k4 plain real lists session:translate-ru" grep -q '^- session:translate-ru — ' <<<"$real_plain"

# k5, k6: plugin.json
PJ=$P/.claude-plugin/plugin.json
check "k5 plugin.json valid JSON" python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$PJ"
# P5 of the 0.16 rebuild moved all five hook events to the two new scripts, so this check reads the
# wiring itself instead of comparing it with HEAD: four events plus the first SessionStart entry,
# every command path on disk, and the contract entries only counted (contracts.sh owns their shape).
check "k5 hook wiring: five events at the two new scripts, every command path on disk" python3 -c '
import json, os, re, sys
pj = sys.argv[1]
plugin = os.path.dirname(os.path.dirname(pj))
hooks = json.load(open(pj, encoding="utf-8"))["hooks"]

def only(groups, want, what):
    cmds = [h.get("command", "") for g in groups for h in g["hooks"]]
    assert len(cmds) == 1, "%s: expected one hook, got %d" % (what, len(cmds))
    assert cmds[0].endswith(want), "%s: %s" % (what, cmds[0])

only(hooks["SubagentStop"], "/hooks/ledger-stop.sh", "SubagentStop")
only(hooks["UserPromptSubmit"], "/hooks/modes.sh", "UserPromptSubmit")
only(hooks["PreCompact"], "/hooks/modes.sh", "PreCompact")
only([g for g in hooks["PostToolUse"] if g.get("matcher") == "Skill"], "/hooks/modes.sh", "PostToolUse(Skill)")
only([hooks["SessionStart"][0]], "/hooks/modes.sh", "the first SessionStart entry")

missing = []
for event, groups in hooks.items():
    for g in groups:
        for h in g["hooks"]:
            for m in re.finditer(r"\$\{CLAUDE_PLUGIN_ROOT\}(/[A-Za-z0-9._/-]+)", h.get("command", "")):
                p = plugin + m.group(1)
                if not os.path.exists(p): missing.append("%s: %s" % (event, p))
assert not missing, "hook command path missing on disk: %s" % "; ".join(missing)

# the contract entries are only counted here: one per workflow file plus @user and @project
entries = [h.get("command", "") for g in hooks["SessionStart"] for h in g["hooks"] if "workflow-usage.sh" in h.get("command", "")]
wf = [f for f in os.listdir(os.path.join(plugin, "workflows")) if f.endswith(".js")]
assert len(entries) == len(wf) + 2, "contract entries %d, workflow files %d" % (len(entries), len(wf))
' "$PJ"
cat > "$T/k6.py" <<'PY'
import json, os, sys, glob
pj, wfdir = sys.argv[1], sys.argv[2]
groups = json.load(open(pj))["hooks"]["SessionStart"]
cmds = [h.get("command", "") for g in groups for h in g["hooks"]]
cmds = [c for c in cmds if "workflow-usage.sh" in c]
pre = "sh ${CLAUDE_PLUGIN_ROOT}/bin/workflow-usage.sh "
stems = sorted(os.path.basename(f)[:-3] for f in glob.glob(os.path.join(wfdir, "*.js")))
ok = bool(stems)
for s in stems:
    want = pre + "--hook --file ${CLAUDE_PLUGIN_ROOT}/workflows/%s.js --prefix session" % s
    n = cmds.count(want)
    if n != 1: print("file command count %s = %d" % (s, n)); ok = False
for d in ("@user", "@project"):
    n = cmds.count(pre + "--hook --dir " + d)
    if n != 1: print("dir command count %s = %d" % (d, n)); ok = False
for c in cmds:
    if "--file" in c:
        name = c.split("/workflows/")[-1].split(".js")[0]
        if name not in stems: print("command for missing file", name); ok = False
sys.exit(0 if ok else 1)
PY
check "k6 SessionStart commands match plugin workflows plus @user and @project" python3 "$T/k6.py" "$PJ" "$P/workflows"
mkdir -p "$T/k6wf"; cp "$P"/workflows/*.js "$T/k6wf/" 2>/dev/null; wfx "$T/k6wf/zz-extra.js" 'Extra.'
check "k6 negative: extra fixture .js without hook fails the check" bash -c '! python3 "$1" "$2" "$3" > /dev/null 2>&1' _ "$T/k6.py" "$PJ" "$T/k6wf"
python3 -c '
import json, sys
for g in json.load(open(sys.argv[1]))["hooks"]["SessionStart"]:
    for h in g["hooks"]:
        if "workflow-usage.sh" in h.get("command", ""): print(h["command"])
' "$PJ" > "$T/k6cmds" 2>/dev/null
check "k6 real plugin.json has workflow-usage commands" test -s "$T/k6cmds"
KH=$(mktemp -d "$T/khome.XXXX"); i=0
while IFS= read -r c; do
  i=$((i + 1))
  c=${c//\$\{CLAUDE_PLUGIN_ROOT\}/$P}
  (cd "$REPO" && env -u CLAUDE_PROJECT_DIR HOME="$KH" sh -c "$c" > "$T/k6o$i" 2>/dev/null); rc=$?
  check "k6 command $i exit 0" test "$rc" -eq 0
  if [ -s "$T/k6o$i" ]; then check "k6 command $i output json.loads" jvalid "$T/k6o$i"; fi
done < "$T/k6cmds"
if command -v claude > /dev/null 2>&1; then
  check "k6 claude plugin validate plugins/session" bash -c 'claude plugin validate "$1" > /dev/null 2>&1' _ "$P"
else
  echo "usage-test: note: claude not on PATH, plugin validate skipped"
fi

# k7: usage word range and arg sets (description words and whenToUse checked in c1)
for f in "${SCRIPTS[@]}"; do
  s=$(basename "$f" .js)
  block=$(awk 'f==0&&/^\/\* usage:/{f=1} f{print} f&&/\*\//{exit}' "$f" 2>/dev/null)
  w=$(printf '%s\n' "$block" | sed -e 's#^/\* usage:##' -e 's#\*/##' | wc -w | tr -d ' ')
  check "k7 $s usage words 36-107 (got $w)" test "$w" -ge 36 -a "$w" -le 107
  got=$(grep -oE 'A\.[a-z]+' "$f" 2>/dev/null | sed 's/^A\.//' | sort -u | tr '\n' ' ')
  want=$(args_of "$s" | tr ' ' '\n' | sort -u | tr '\n' ' ')
  check "k7 $s A.<arg> set equals args_of (got $got)" test "$got" = "$want"
done

# k8: the role workflow and the tool-set agents it may launch (rewritten in P2 of the 0.16
# rebuild: the old check read translate-ru.js, whose two agents leave with it in P9)
RL=$P/workflows/role.js
check "k8 role.js in plugin" test -f "$RL"
# comment lines are stripped first: an agent named only in a comment reaches no launch, so it must
# not keep this check green
at=$(grep -vE '^[[:space:]]*(//|\*|/\*)' "$RL" 2>/dev/null | grep -oE "session:tools-[a-z-]+" | sort -u | tr '\n' ' ')
check "k8 role.js agentTypes are the five tool-set agents (got $at)" test "$at" = "session:tools-edit session:tools-read-bash session:tools-read-write session:tools-read-write-bash session:tools-web "
check "k8 role.js passes its agent as agentType" grep -qE "agentType: *AGENT" "$RL"
for a in tools-edit tools-read-bash tools-read-write tools-read-write-bash tools-web; do
  fm=$(awk 'NR==1&&/^---$/{f=1; next} f&&/^---$/{exit} f{print}' "$P/agents/$a.md" 2>/dev/null)
  check "k8 agents/$a.md frontmatter name" grep -Fxq "name: $a" <<<"$fm"
  check "k8 agents/$a.md frontmatter description" grep -Eq '^description: .+' <<<"$fm"
  check "k8 agents/$a.md frontmatter tools" grep -Eq '^tools: .+' <<<"$fm"
done

# k9 (the repo-wide scan for translate-ru, translator and size-estimator) is gone: `translator` is
# a live role name of lib/roles/ from P2 on, so the scan would be red by construction. P9 puts
# tests/rebuild/stale.sh here instead, which matches qualified forms only.

# k10: base
for f in "$BASE" "$SKILL"; do
  b=$(basename "$f")
  check "k10 $b no workflow-usage.sh text" bash -c '! grep -Fq "workflow-usage.sh" "$1"' _ "$f"
  check "k10 $b no Named workflows heading" bash -c '! grep -q "^## Named workflows" "$1"' _ "$f"
  check "k10 $b keeps meta.description label sentence" grep -Fq 'Its `meta.description` is a 1-4 word label' "$f"
done
check "k10 $(basename "$SKILL") no allowed-tools" bash -c '! grep -Fq "allowed-tools" "$1"' _ "$SKILL"
# P6 of the 0.16 rebuild rewrote the base, so the contract sentence is the new one: the injected
# contract is the only thing a launch by name needs.
check "k10 BASE.md SessionStart contract sentence" grep -Fq 'A named workflow arrives as one SessionStart contract line; launch it by `name` and never read the script body.' "$BASE"

# k11: bin/build.sh regenerates SKILL.md from BASE.md (P6 replaced base/split.sh as the generator;
# the copy holds lib/, bin/, base/ and skills/base/, so the build runs against a tree of its own)
mkdir -p "$T/g/plugin/skills/base"
cp -R "$P/base" "$T/g/plugin/base"
cp -R "$P/lib" "$T/g/plugin/lib"
cp -R "$P/bin" "$T/g/plugin/bin"
cp "$SKILL" "$T/g/plugin/skills/base/SKILL.md"
printf '\nhand edit\n' >> "$T/g/plugin/skills/base/SKILL.md"
check "k11 build.sh --check fails on a hand edit of the generated skill" bash -c '! bash "$1" --check > "$2" 2>&1' _ "$T/g/plugin/bin/build.sh" "$T/g/check.out"
check "k11 --check names skills/base/SKILL.md" grep -q 'skills/base/SKILL.md' "$T/g/check.out"
bash "$T/g/plugin/bin/build.sh" > /dev/null 2>&1
check "k11 build.sh regenerates identical SKILL.md" cmp -s "$T/g/plugin/skills/base/SKILL.md" "$SKILL"
check "k11 build.sh --check clean on the real plugin" bash "$P/bin/build.sh" --check

# k12: README
RD=$P/README.md
sec=$(awk '/^## Workflow contract hooks/{f=1; print; next} f&&/^## /{exit} f{print}' "$RD")
check "k12 README section Workflow contract hooks" test -n "$sec"
check "k12 README section plugin.json SessionStart snippet" bash -c 'grep -q "plugin.json" <<<"$1" && grep -q "SessionStart" <<<"$1" && grep -q "\"hooks\"" <<<"$1"' _ "$sec"
check "k12 README section collector copy into bin/" grep -q 'bin/' <<<"$sec"
check "k12 README section --hook --file and --prefix" bash -c 'grep -q -- "--hook --file" <<<"$1" && grep -q -- "--prefix" <<<"$1"' _ "$sec"
check "k12 README section user and project dirs covered by session (@project)" grep -q '@project' <<<"$sec"
check "k12 README section /reload-plugins or restart" bash -c 'grep -q "/reload-plugins" <<<"$1" && grep -qi "restart" <<<"$1"' _ "$sec"
pre=$(awk '/^## Version log/{exit} {print}' "$RD")
check "k12 README no base injection text outside version log" bash -c '! grep -Eiq "injected into base|at skill load|base .?## Named workflows|meta description is the contract" <<<"$1"' _ "$pre"

# k13: changed paths, no version bump (suite pass itself is the rest of k13)
bad=$(git -C "$REPO" status --porcelain -uall | cut -c4- | grep -vxE '\.claude-plugin/marketplace.json|plugins/session/lib/.*|plugins/session/hooks/(modes|ledger-stop)\.sh|plugins/session/bin/build\.sh|plugins/session/agents/tools-[a-z-]+\.md|tests/rebuild/.*|docs/tool-plugin/.*|plugins/session/bin/workflow-usage.sh|plugins/session/\.claude-plugin/plugin.json|plugins/session/workflows/(build|chain|dev|make|probe|research|review-fix|role|translate-ru)\.js|tests/measure/rebuild-scenarios-0\.16\.txt|\.claude/workflows/(memory-gc|skill-author|test-session)\.js|\.claude/skills/plugin-release/SKILL\.md|plugins/session/agents/(translator|size-estimator)\.md|plugins/session/base/BASE.md|plugins/session/base/split.sh|plugins/session/skills/base/SKILL.md|plugins/session/README.md|plugins/session/monitors/.*|plugins/session/skills/start-ping/.*|tests/monitors/.*|tests/workflows/usage-test.sh' | tr '\n' ' ')
check "k13 changed paths within allowed list (extra: $bad)" test -z "$bad"
check "k13 plugin and marketplace versions match" python3 -c 'import json,sys; v=json.load(open(sys.argv[1]))["version"]; m=[p["version"] for p in json.load(open(sys.argv[2]))["plugins"] if p["name"]=="session"]; sys.exit(0 if m==[v] else 1)' "$P/.claude-plugin/plugin.json" "$P/../../.claude-plugin/marketplace.json"

if [ "$FAILS" -eq 0 ]; then
  echo "usage-test: PASS $N"; exit 0
fi
echo "usage-test: FAIL $FAILS failures, $N checks passed"
exit 1
