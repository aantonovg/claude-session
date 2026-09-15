#!/usr/bin/env bash
# Verifier for plugins/session/bin/codex-exec-logged.sh (context composition,
# --role, --prompt-file, dry run, detach, codex probe, ledger label).
# Runs with a temp HOME, temp cwd, temp TMPDIR and a fake `codex` on a
# restricted PATH (<fake dir>:/usr/bin:/bin), so the real codex and the real
# ledger are never touched. Plan criteria: AC1-AC8, AC19, AC20, part of AC21.
#
# Deviation from "byte-equal" (AC20): the trailing newline(s) at EOF are
# stripped on both sides (agent body and role section) before comparing.
set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
BIN="$REPO/plugins/session/bin"
WRAP="$BIN/codex-exec-logged.sh"
AGENTS="$REPO/plugins/session/agents"
[ -f "$WRAP" ] || { echo "wrapper not found: $WRAP"; exit 1; }

REAL_HOME=$HOME
REAL_LEDGER="$REAL_HOME/.codex/proxy-usage.jsonl"
ledger_count() { if [ -f "$REAL_LEDGER" ]; then wc -l <"$REAL_LEDGER" | tr -d ' '; else echo 0; fi; }
REAL_LEDGER_BEFORE=$(ledger_count)

JQ=$(command -v jq || true)
PY=/usr/bin/python3
[ -x "$PY" ] || { echo "python3 not found at $PY"; exit 1; }

T=$(mktemp -d "${TMPDIR:-/tmp}/wrapper-test.XXXXXX")
T=$(cd "$T" && pwd)
trap 'rm -rf "$T"' EXIT
HOME="$T/home"; mkdir -p "$HOME/.claude"; export HOME
case "$HOME" in "$REAL_HOME"|"$REAL_HOME"/*) echo "FAIL sandbox: HOME inside real home"; exit 1 ;; esac
export TMPDIR="$T/tmp"; mkdir -p "$TMPDIR"
FAKE="$T/fake"; mkdir -p "$FAKE"
MARK="$T/mark"; mkdir -p "$MARK"; export FAKE_MARK="$MARK"
WORK="$T/work"; mkdir -p "$WORK"

# Fake codex: records $0, argv, stdin, and whether any TMPDIR file holds the
# composed context while codex runs; emits one v2 usage event.
cat >"$FAKE/codex" <<'FAKEEOF'
#!/bin/bash
printf '%s\n' "$0" >"$FAKE_MARK/argv0"
printf '%s\n' "$@" >"$FAKE_MARK/args"
cat >"$FAKE_MARK/stdin"
if grep -rlF '[USER CLAUDE.md]' "$TMPDIR" >/dev/null 2>&1; then echo leak >"$FAKE_MARK/tmpscan"; else echo clean >"$FAKE_MARK/tmpscan"; fi
echo '{"type":"turn.completed","usage":{"input_tokens":10,"cached_input_tokens":0,"output_tokens":5,"reasoning_output_tokens":0}}'
exit 0
FAKEEOF
chmod +x "$FAKE/codex"
if [ -n "$JQ" ]; then ln -s "$JQ" "$FAKE/jq"; fi
export PATH="$FAKE:/usr/bin:/bin"

PASS=0; TOTAL=0; FAILED=""
ok()   { TOTAL=$((TOTAL + 1)); PASS=$((PASS + 1)); echo "PASS $1"; }
bad()  { TOTAL=$((TOTAL + 1)); FAILED="$FAILED|$1"; echo "FAIL $1: $2"; }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$3] got [$2]"; fi; }

# Guard: fake codex must win before any wrapper call.
if [ "$(command -v codex || true)" != "$FAKE/codex" ]; then
  echo "FAIL guard: command -v codex = [$(command -v codex || true)], not fake"; exit 1
fi
ok "guard: command -v codex is fake"

clear_mark() { rm -f "$MARK"/argv0 "$MARK"/args "$MARK"/stdin "$MARK"/tmpscan; }
DRY_MARKER_LEAK=0
# dry <cwd> <stdin-text> <wrapper args...>: dry run, sets OUT and RC.
dry() {
  local cwd="$1" in="$2"; shift 2
  clear_mark; RC=0
  OUT=$(cd "$cwd" && printf '%s' "$in" | CODEX_EXEC_DRY_RUN=1 "$WRAP" "$@" 2>"$T/err") || RC=$?
  [ -e "$MARK/argv0" ] && DRY_MARKER_LEAK=1
  return 0
}
# real <cwd> <stdin-text> <wrapper args...>: fake-codex run, sets OUT, ERR and RC.
real() {
  local cwd="$1" in="$2"; shift 2
  clear_mark; RC=0
  OUT=$(cd "$cwd" && printf '%s' "$in" | "$WRAP" "$@" 2>"$T/err") || RC=$?
  ERR=$(cat "$T/err")
}
# One header pattern shared by section() and headers(). ROLE accepts any name
# (not the wrapper's role-name rule), so a role header is always parsed and a
# wrong name fails the header checks loudly instead of vanishing.
HDR_RE='^\[(ROLE: [^]]+|USER CLAUDE\.md|PROJECT CLAUDE\.md|MEMORY INDEX|RESPONSE STYLE|TASK)\]$'
# section <name> reads OUT; prints the section body (between its header line
# and the next known header line), trailing newlines stripped.
section() {
  SEC_NAME="$1" HDR_RE="$HDR_RE" "$PY" -c '
import os, re, sys
name = os.environ["SEC_NAME"]
lines = sys.stdin.read().split("\n")
hdr = re.compile(os.environ["HDR_RE"])
out, on = [], False
for l in lines:
    if on and l.startswith("CODEX ARGV: "): break  # dry-run argv line ends the last section
    m = hdr.match(l)
    if m:
        if on: break
        on = (m.group(1) == name or (name == "ROLE" and m.group(1).startswith("ROLE: ")))
        continue
    if on: out.append(l)
if not on and not out: sys.exit(1)
sys.stdout.write("\n".join(out).rstrip("\n"))
' <<<"$OUT"
}
has_section() { section "$1" >/dev/null 2>&1; }
headers() { grep -E "$HDR_RE" <<<"$OUT" | tr '\n' ',' || true; }
agent_body() {
  "$PY" -c '
import sys
t = open(sys.argv[1]).read()
if t.startswith("---\n"):
    end = t.index("\n---\n", 3)
    t = t[end + 5:]
    if t.startswith("\n"): t = t[1:]
sys.stdout.write(t.rstrip("\n"))
' "$1"
}
slug() { printf '%s' "$1" | tr '/.' '--'; }

# Fixtures: user CLAUDE.md, project CLAUDE.md, memory index for WORK.
echo "user-claude-marker" >"$HOME/.claude/CLAUDE.md"
echo "project-claude-marker" >"$WORK/CLAUDE.md"
WORK_SLUG=$(slug "$(cd "$WORK" && pwd)")
mkdir -p "$HOME/.claude/projects/$WORK_SLUG/memory"
echo "memory-marker-work" >"$HOME/.claude/projects/$WORK_SLUG/memory/MEMORY.md"

# AC21 (part): syntax.
if bash -n "$WRAP" && bash -n "${BASH_SOURCE[0]}"; then ok "AC21 bash -n wrapper and test"; else bad "AC21 bash -n" "syntax error"; fi

# AC5: static greps: inherited PATH only, ledger under $HOME.
if grep -nE 'PATH=|env -i|bash -l|zsh -l|/opt/homebrew|/usr/local/bin' "$WRAP" >/dev/null; then bad "AC5 no PATH reset or login shell" "grep hit"; else ok "AC5 no PATH reset or login shell"; fi
# Match-based filter: -o emits each hit alone, so a .codex/ path elsewhere on
# the same line cannot hide an absolute codex binary path.
if grep -oE '/[A-Za-z0-9._/-]*/codex([^-a-zA-Z.]|$)' "$WRAP" | grep -vE '/\.codex(/|$)' >/dev/null; then bad "AC5 no absolute codex path" "grep hit"; else ok "AC5 no absolute codex path"; fi
if grep -q '"\$HOME/.codex/proxy-usage.jsonl"' "$WRAP"; then ok "AC5 ledger under \$HOME"; else bad "AC5 ledger under \$HOME" "not found"; fi

# AC1: role section byte-equal to agent body (trailing EOF newline stripped).
dry "$WORK" "task-text" --role stage-author -
check "AC1 dry run --role exit 0" "$RC" 0
check "AC1 role header present" "$(grep -c '^\[ROLE: stage-author\]$' <<<"$OUT" || true)" 1
check "AC1/AC20 role section equals agent body" "$(section ROLE 2>/dev/null || true)" "$(agent_body "$AGENTS/stage-author.md")"

# AC1: header order.
check "AC1 header order" "$(headers)" "[ROLE: stage-author],[USER CLAUDE.md],[PROJECT CLAUDE.md],[MEMORY INDEX],[RESPONSE STYLE],[TASK],"
check "AC2 USER CLAUDE.md content" "$(section 'USER CLAUDE.md' 2>/dev/null || true)" "user-claude-marker"
check "AC2 PROJECT CLAUDE.md content" "$(section 'PROJECT CLAUDE.md' 2>/dev/null || true)" "project-claude-marker"
check "AC2 MEMORY INDEX content" "$(section 'MEMORY INDEX' 2>/dev/null || true)" "memory-marker-work"
check "AC2 RESPONSE STYLE from codex-style.md" "$(section 'RESPONSE STYLE' 2>/dev/null | head -n 1 || true)" "$(head -n 1 "$BIN/codex-style.md")"
check "AC1 TASK content" "$(section TASK 2>/dev/null || true)" "task-text"

# AC4: preamble at end of codex-style.md reaches RESPONSE STYLE; no proxy-only header.
STYLE_SEC=$(section 'RESPONSE STYLE' 2>/dev/null || true)
if grep -qF '[SANDBOX & ESCALATION NOTICE]' <<<"$STYLE_SEC" && grep -qF 'never ask for blanket unsandboxed mode.' <<<"$STYLE_SEC"; then ok "AC4 preamble in RESPONSE STYLE"; else bad "AC4 preamble in RESPONSE STYLE" "missing"; fi
if grep -qE 'CODEX (ROLE|LABEL|PROFILE|WALL|SANDBOX|OUTPUT FILE):' <<<"$STYLE_SEC"; then bad "AC4 preamble names no proxy-only header" "hit"; else ok "AC4 preamble names no proxy-only header"; fi

# AC2: CODEX_STYLE_FILE override.
echo "override-style-marker" >"$T/style.md"
clear_mark; RC=0
OUT=$(cd "$WORK" && printf 't' | CODEX_STYLE_FILE="$T/style.md" CODEX_EXEC_DRY_RUN=1 "$WRAP" -) || RC=$?
check "AC2 CODEX_STYLE_FILE override" "$(section 'RESPONSE STYLE' 2>/dev/null || true)" "override-style-marker"

# AC2: missing or empty optional files omit section and header.
EMPTY="$T/empty-proj"; mkdir -p "$EMPTY"; : >"$EMPTY/CLAUDE.md"
mv "$HOME/.claude/CLAUDE.md" "$T/user-claude.bak"
dry "$EMPTY" "t" --role stage-author -
check "AC2 missing/empty files: headers" "$(headers)" "[ROLE: stage-author],[RESPONSE STYLE],[TASK],"
if has_section 'USER CLAUDE.md' || has_section 'PROJECT CLAUDE.md' || has_section 'MEMORY INDEX'; then bad "AC2 absent sections when missing" "section present"; else ok "AC2 absent sections when missing"; fi
mv "$T/user-claude.bak" "$HOME/.claude/CLAUDE.md"
check "AC2 missing style file omits RESPONSE STYLE" "$(cd "$WORK" && printf 't' | CODEX_STYLE_FILE="$T/nope.md" CODEX_EXEC_DRY_RUN=1 "$WRAP" - 2>/dev/null | grep -c '^\[RESPONSE STYLE\]$' || true)" 0

# AC3: without --role the other sections still compose, no ROLE.
dry "$WORK" "t" -
check "AC3 no --role header order" "$(headers)" "[USER CLAUDE.md],[PROJECT CLAUDE.md],[MEMORY INDEX],[RESPONSE STYLE],[TASK],"

# AC2: memory slug for relative -C.
REL="$WORK/sub/rel.proj"; mkdir -p "$REL"
mkdir -p "$HOME/.claude/projects/$(slug "$(cd "$REL" && pwd)")/memory"
echo "memory-marker-rel" >"$HOME/.claude/projects/$(slug "$(cd "$REL" && pwd)")/memory/MEMORY.md"
echo "project-rel" >"$REL/CLAUDE.md"
dry "$WORK" "t" --role stage-author -C sub/rel.proj -
check "AC2 relative -C memory slug" "$(section 'MEMORY INDEX' 2>/dev/null || true)" "memory-marker-rel"
check "AC2 relative -C project CLAUDE.md" "$(section 'PROJECT CLAUDE.md' 2>/dev/null || true)" "project-rel"
dry "$WORK" "t" --role stage-author --cd sub/rel.proj -
check "AC2 --cd memory slug" "$(section 'MEMORY INDEX' 2>/dev/null || true)" "memory-marker-rel"
dry "$WORK" "t" --role stage-author --cd=sub/rel.proj -
check "AC2 --cd= memory slug" "$(section 'MEMORY INDEX' 2>/dev/null || true)" "memory-marker-rel"

# AC2: cwd under symlinked dir with a dot in its name (logical path slug).
mkdir -p "$T/real.target/proj"; ln -s "$T/real.target" "$T/link.dir"
LINKCWD="$T/link.dir/proj"
LSLUG=$(slug "$(cd "$LINKCWD" && pwd)")
mkdir -p "$HOME/.claude/projects/$LSLUG/memory"; echo "memory-marker-link" >"$HOME/.claude/projects/$LSLUG/memory/MEMORY.md"
dry "$LINKCWD" "t" --role stage-author -
check "AC2 symlinked dotted cwd memory slug" "$(section 'MEMORY INDEX' 2>/dev/null || true)" "memory-marker-link"

# AC1: wrapper invoked through a symlink yields role section.
mkdir -p "$T/symbin"; ln -s "$WRAP" "$T/symbin/codex-exec-logged.sh"
clear_mark; RC=0
OUT=$(cd "$WORK" && printf 't' | CODEX_EXEC_DRY_RUN=1 "$T/symbin/codex-exec-logged.sh" --role stage-author - 2>/dev/null) || RC=$?
check "AC1 symlink invocation role section" "$(section ROLE 2>/dev/null || true)" "$(agent_body "$AGENTS/stage-author.md")"

# AC1: copy without sibling agents dir exits 2.
mkdir -p "$T/copy/bin"; cp "$WRAP" "$BIN/codex-style.md" "$T/copy/bin/"
clear_mark; RC=0
OUT=$(cd "$WORK" && printf 't' | "$T/copy/bin/codex-exec-logged.sh" --role stage-author - 2>"$T/err") || RC=$?
check "AC1 copy without agents dir exit 2" "$RC" 2
check "AC1 agents dir not found message" "$(grep -c "codex-exec-logged: agents dir not found: " "$T/err" || true)" 1
check "AC1 copy without agents dir: codex not started" "$([ -e "$MARK/argv0" ] && echo started || echo absent)" absent

# AC20: every agents/stage-*.md yields non-empty role section.
for f in "$AGENTS"/stage-*.md; do
  n=$(basename "$f" .md)
  dry "$WORK" "t" --role "$n" -
  s=$(section ROLE 2>/dev/null || true)
  if [ "$RC" = 0 ] && [ -n "$s" ] && [ "$s" = "$(agent_body "$f")" ]; then ok "AC20 role $n non-empty"; else bad "AC20 role $n non-empty" "rc=$RC len=${#s}"; fi
done

# AC1: unknown role and bad name exit 2, codex not started.
real "$WORK" "t" --role no-such-role -
check "AC1 unknown role exit 2" "$RC" 2
check "AC1 unknown role message" "$(grep -c 'codex-exec-logged: unknown role no-such-role' <<<"$ERR" || true)" 1
check "AC1 unknown role: codex not started" "$([ -e "$MARK/argv0" ] && echo started || echo absent)" absent
real "$WORK" "t" --role ../stage-author -
check "AC1 bad role name exit 2" "$RC" 2
check "AC1 bad role name: codex not started" "$([ -e "$MARK/argv0" ] && echo started || echo absent)" absent

# AC3: --role without - or --prompt-file exits 2.
real "$WORK" "t" --role stage-author -m gpt-5
check "AC3 --role without stdin form exit 2" "$RC" 2
check "AC3 --role without stdin form message" "$(grep -c 'codex-exec-logged: --role needs - or --prompt-file' <<<"$ERR" || true)" 1
check "AC3 --role without stdin form: codex not started" "$([ -e "$MARK/argv0" ] && echo started || echo absent)" absent

# AC3: missing prompt file exits 3.
real "$WORK" "" --role stage-author --prompt-file "$T/missing-prompt.txt"
check "AC3 missing prompt file exit 3" "$RC" 3
check "AC3 missing prompt file message" "$(grep -c "codex-exec-logged: prompt file not found: $T/missing-prompt.txt" <<<"$ERR" || true)" 1
check "AC3 missing prompt file: codex not started" "$([ -e "$MARK/argv0" ] && echo started || echo absent)" absent

# AC3/AC20: --prompt-file form composes, TASK equals file content.
printf 'prompt-file-task' >"$T/prompt.txt"
dry "$WORK" "" --role stage-author --prompt-file "$T/prompt.txt"
check "AC3 --prompt-file dry exit 0" "$RC" 0
check "AC3 --prompt-file TASK" "$(section TASK 2>/dev/null || true)" "prompt-file-task"
check "AC3 --prompt-file header order" "$(headers)" "[ROLE: stage-author],[USER CLAUDE.md],[PROJECT CLAUDE.md],[MEMORY INDEX],[RESPONSE STYLE],[TASK],"

# AC6: dry run prints argv line, exit 0, works with --detach, no detach.
rm -f "$HOME/.codex/proxy-usage.jsonl"
dry "$WORK" "t" --detach "$T/dry.done" --role stage-author -m gpt-5 -c 'model_reasoning_effort="medium"' -o "$T/o.md" -
check "AC6 dry --detach exit 0" "$RC" 0
check "AC6 dry --detach TASK count" "$(grep -c '^\[TASK\]$' <<<"$OUT" || true)" 1
ARGV_LINE=$(grep '^CODEX ARGV: ' <<<"$OUT" || true)
EXP_ARGV="CODEX ARGV: exec --json $(printf '%q ' -m gpt-5 -c 'model_reasoning_effort="medium"' -o "$T/o.md" -)"
check "AC6 argv line" "$ARGV_LINE" "${EXP_ARGV% }"
check "AC6 argv line is last line" "$(tail -n 1 <<<"$OUT")" "${EXP_ARGV% }"
check "AC6 dry never detaches" "$([ -e "$T/dry.done" ] || [ -e "$T/dry.done.log" ] && echo detached || echo no)" no
check "AC7 dry argv has no --role/--prompt-file/--detach" "$(grep -cE -- '--role|--prompt-file|--detach' <<<"$ARGV_LINE" || true)" 0
check "AC6 dry run writes no ledger" "$([ -e "$HOME/.codex/proxy-usage.jsonl" ] && echo written || echo none)" none
check "AC6/AC20 marker absent after every dry run" "$DRY_MARKER_LEAK" 0

# AC5: codex probe: codex absent from PATH exits 127, not in dry run.
if (PATH="/usr/bin:/bin"; command -v codex >/dev/null 2>&1); then
  bad "AC5 codex probe" "codex present in /usr/bin:/bin, cannot test safely"
else
  RC=0; (cd "$WORK" && printf 't' | PATH="/usr/bin:/bin" "$WRAP" - >/dev/null 2>"$T/err") || RC=$?
  check "AC5 codex absent exit 127" "$RC" 127
  check "AC5 codex not found message" "$(grep -c '^codex-exec-logged: codex not found$' "$T/err" || true)" 1
  RC=0; OUT=$(cd "$WORK" && printf 't' | PATH="/usr/bin:/bin" CODEX_EXEC_DRY_RUN=1 "$WRAP" - 2>/dev/null) || RC=$?
  check "AC5 no probe in dry run" "$RC" 0
fi

# AC8/AC19: ledger label from CODEX_LABEL (non-dry, fake codex).
rm -f "$HOME/.codex/proxy-usage.jsonl"
clear_mark; RC=0
(cd "$WORK" && printf 'label-task' | CODEX_LABEL=hai-me-sol-test "$WRAP" --role stage-author -m gpt-5 - >/dev/null 2>"$T/err") || RC=$?
check "AC19 label run exit 0" "$RC" 0
check "AC20 marker present in non-dry label case" "$([ -e "$MARK/argv0" ] && echo present || echo absent)" present
LBL=$("$PY" -c 'import json,sys; rows=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]; print(rows[-1].get("label","<missing>"))' "$HOME/.codex/proxy-usage.jsonl" 2>/dev/null || echo "<no ledger>")
check "AC8/AC19 ledger label equals CODEX_LABEL" "$LBL" "hai-me-sol-test"
KEYS=$("$PY" -c 'import json,sys; rows=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]; print(",".join(sorted(rows[-1])))' "$HOME/.codex/proxy-usage.jsonl" 2>/dev/null || echo "<no ledger>")
check "AC8 ledger other fields unchanged" "$KEYS" "cached_input,effort,input,label,model,output,reasoning_output,ts"
check "AC7 non-dry: --role not in codex argv" "$(grep -cE -- '^(--role|--prompt-file|--detach)$' "$MARK/args" 2>/dev/null || true)" 0
check "AC1 non-dry: codex stdin has role section" "$(grep -c '^\[ROLE: stage-author\]$' "$MARK/stdin" 2>/dev/null || true)" 1
clear_mark; RC=0
(cd "$WORK" && printf 'x' | env -u CODEX_LABEL "$WRAP" - >/dev/null 2>"$T/err") || RC=$?
LBL=$("$PY" -c 'import json,sys; rows=[json.loads(l) for l in open(sys.argv[1]) if l.strip()]; print("[" + rows[-1].get("label","<missing>") + "]")' "$HOME/.codex/proxy-usage.jsonl" 2>/dev/null || echo "<no ledger>")
check "AC8 label empty string when unset" "$LBL" "[]"

# AC7/AC2/AC20: detached fake-codex run, --prompt-file form.
detach_run() {  # $1 name, rest: wrapper args; stdin from $DIN
  local name="$1"; shift
  local done="$T/$name.done"
  clear_mark; rm -f "$done"
  ls -A "$TMPDIR" >"$T/tmp-before.txt"
  local leak_before=clean
  RC=0
  (cd "$WORK" && "$WRAP" --detach "$done" "$@" <"$DIN" >/dev/null 2>"$T/err") || RC=$?
  if grep -rlF '[USER CLAUDE.md]' "$TMPDIR" >/dev/null 2>&1; then leak_before=leak; fi
  for i in $(seq 60); do [ -f "$done" ] && break; sleep 0.5; done
  if grep -rlF '[USER CLAUDE.md]' "$TMPDIR" >/dev/null 2>&1; then leak_before=leak; fi
  check "AC7 $name detach launch exit 0" "$RC" 0
  check "AC7 $name done-file written" "$([ -f "$done" ] && echo yes || echo no)" yes
  check "AC20 $name detached child \$0 is fake codex" "$(cat "$MARK/argv0" 2>/dev/null || true)" "$FAKE/codex"
  check "AC7/AC20 $name exactly one [TASK]" "$(grep -c '^\[TASK\]$' "$MARK/stdin" 2>/dev/null || true)" 1
  check "AC7 $name child composed role section" "$(grep -c '^\[ROLE: stage-author\]$' "$MARK/stdin" 2>/dev/null || true)" 1
  check "AC7 $name child composed USER CLAUDE.md" "$(grep -c '^\[USER CLAUDE.md\]$' "$MARK/stdin" 2>/dev/null || true)" 1
  check "AC7 $name TASK is caller prompt" "$(OUT=$(cat "$MARK/stdin" 2>/dev/null || true); section TASK 2>/dev/null || true)" "detach-task"
  check "AC2/AC20 $name no TMPDIR file holds composed context (launch, done)" "$leak_before" clean
  check "AC2/AC20 $name no TMPDIR file holds composed context (during codex)" "$(cat "$MARK/tmpscan" 2>/dev/null || echo unscanned)" clean
  check "AC7 $name --role/--prompt-file/--detach not in codex argv" "$(if [ -f "$MARK/args" ]; then grep -cE -- '^(--role|--prompt-file|--detach)$' "$MARK/args" || true; else echo missing; fi)" 0
  check "AC7/AC20 $name no wrapper temp stdin file remains" "$(ls -A "$TMPDIR" | grep -c '^codex-stdin\.' || true)" 0
}
printf 'detach-task' >"$T/detach-prompt.txt"
DIN=/dev/null
detach_run pf --role stage-author --prompt-file "$T/detach-prompt.txt" -m gpt-5 -o "$T/pf.final.md"
DIN="$T/detach-prompt.txt"
detach_run stdin --role stage-author -m gpt-5 -o "$T/stdin.final.md" -

# AC20: real ledger untouched.
check "AC20 real ledger line count unchanged" "$(ledger_count)" "$REAL_LEDGER_BEFORE"

if [ -z "$FAILED" ]; then
  echo "wrapper-test: PASS $PASS"; exit 0
fi
echo "wrapper-test: FAIL $((TOTAL - PASS))/$TOTAL"; exit 1
