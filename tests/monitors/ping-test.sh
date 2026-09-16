#!/bin/bash
# Verifier for plugins/session/monitors/ping.sh daily cutoff, resume-ping.sh
# date files and env hooks. Temp TMPDIR, fake `date` in PATH, runs under 60 s.
set -uo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
M=$REPO/plugins/session/monitors
T=$(mktemp -d) || exit 1
mkdir -p "$T/tmp" "$T/bin" "$T/data"
export TMPDIR=$T/tmp CLAUDE_SESSION_ID=pingtest PING_INTERVAL=2 PING_STEP=1
export FAKE_DATE=$T/fake-date

PID1=""; PID2=""
killtree() {  # $1 pid
  [ -n "$1" ] || return 0
  pkill -P "$1" 2>/dev/null || true
  kill "$1" 2>/dev/null || true
  pkill -P "$1" 2>/dev/null || true
}
cleanup() { killtree "$PID1"; killtree "$PID2"; rm -rf "$T"; }
trap cleanup EXIT

# Fake date: ignores args, prints the day held in $FAKE_DATE.
printf '#!/bin/sh\ncat "$FAKE_DATE"\n' > "$T/bin/date"
chmod +x "$T/bin/date"
PATH=$T/bin:$PATH
export PATH
if [ "$(command -v date)" != "$T/bin/date" ]; then echo "FAIL shim"; exit 1; fi
clock() { printf '%s\n' "$1" > "$FAKE_DATE"; }

N=0; FAILS=0
pass() { echo "PASS $1"; N=$((N + 1)); }
fail() { echo "FAIL $1"; FAILS=$((FAILS + 1)); }
deadline() { [ "$SECONDS" -lt 55 ] || { fail "watchdog: over 55 s"; return 1; }; }

pings() { grep -c '^ping$' "${1:-$T/out.log}" 2>/dev/null || true; }
wait_ping() {  # $1 count before, $2 max seconds, [$3 log] -> 0 when count grew
  local end=$((SECONDS + $2))
  while [ "$SECONDS" -lt "$end" ]; do
    deadline || return 1
    [ "$(pings "${3:-}")" -gt "$1" ] && return 0
    sleep 0.5
  done
  [ "$(pings "${3:-}")" -gt "$1" ]
}
no_ping() {  # $1 count before, $2 seconds, [$3 log] -> 0 when count unchanged
  sleep "$2"; deadline || return 1
  [ "$(pings "${3:-}")" -eq "$1" ]
}
alive() { kill -0 "$1" 2>/dev/null; }

DATEF=$TMPDIR/session-ping-date-pingtest

# Static checks (AC 3, 4, 5)
grep -q 3420 "$M/ping.sh" || fail "static: default interval 3420 missing in ping.sh"
grep -q 'PING_STEP:-60' "$M/ping.sh" || fail "static: PING_STEP:-60 missing in ping.sh"
grep -q 'PING_INTERVAL' "$M/ping.sh" || fail "static: PING_INTERVAL hook missing in ping.sh"
grep -q '23:02' "$M/ping.sh" || fail "static: 23:02 cadence comment missing in ping.sh"
grep -q 'date +%Y-%m-%d' "$M/ping.sh" || fail "static: ping.sh does not read date +%Y-%m-%d"
grep -q 'date +%Y-%m-%d' "$M/resume-ping.sh" || fail "static: resume-ping.sh does not read date +%Y-%m-%d"
if grep -n -E '/(usr/)?bin/date' "$M/ping.sh" "$M/resume-ping.sh" >/dev/null; then
  fail "static: absolute date path in ping.sh or resume-ping.sh"
fi
if [ -n "$(git -C "$REPO" diff -- plugins/session/monitors/stop-ping.sh)" ]; then
  fail "static: stop-ping.sh changed"
fi

# Docs: BASE.md and generated SKILL.md keep monitor wording, drop ping jobs.
B_MD=$REPO/plugins/session/base/BASE.md
S_MD=$REPO/plugins/session/skills/base/SKILL.md
for doc in "$B_MD" "$S_MD"; do
  name=${doc#"$REPO"/}
  grep -qF 'ping monitor; forks or workflows for every 2+ call job' "$doc" || fail "docs: reply line missing in $name"
  grep -qF 'Pings: every `ping` gets exactly `pong`: no work, no status, no tool calls.' "$doc" || fail "docs: pong rule missing in $name"
  grep -qF 'Exception: previous work turn cut off (error line in place of an answer, fork or background job never returned, step announced not done): `pong` and in the same turn resume that step, no other output.' "$doc" || fail "docs: cut-off exception missing in $name"
  if grep -qiE 'run_in_background.*(ping|keep-warm)|(ping|keep-warm).*run_in_background' "$doc"; then fail "docs: run_in_background ping text in $name"; fi
  if grep -qiF 're-arm' "$doc"; then fail "docs: re-arm text in $name"; fi
done

# I: runtime defaults via PING_DRY_RUN: unset PING_INTERVAL gives 3420, invalid PING_STEP gives 60.
mkdir -p "$T/empty"
got=$(env -u PING_INTERVAL PING_STEP=abc PING_DRY_RUN=1 sh "$M/ping.sh" "$T/empty" 2>&1)
if [ "$got" = "interval=3420 step=60" ]; then pass "I defaults interval 3420 and step fallback 60"
else fail "I defaults interval 3420 and step fallback 60 (got [$got])"; fi

# Setup: clock 2026-09-16, stale older date file (reused pid case).
clock 2026-09-16
printf '2026-09-15\n' > "$DATEF"
sh "$M/ping.sh" "$T/data" > "$T/out.log" 2>&1 &
PID1=$!

# A: ping before cutoff despite stale older date file.
A=0
if wait_ping 0 5; then pass "A ping on active date with stale date file"; A=1
else fail "A ping on active date with stale date file"; fi

# B: next-day clock (past 23:59 of active date): silent, still running.
B=0
clock 2026-09-17; sleep 1; c=$(pings)
if [ "$A" = 1 ] && no_ping "$c" 4 && alive "$PID1"; then pass "B no ping after 23:59"; B=1
else fail "B no ping after 23:59 (needs A, silence, pid alive)"; fi

# C: later date: silent.
clock 2026-09-18; sleep 1; c=$(pings)
if [ "$B" = 1 ] && no_ping "$c" 4 && alive "$PID1"; then pass "C no ping on later date"
else fail "C no ping on later date (needs B, silence, pid alive)"; fi

# D: resume writes today and ping returns.
D=0
c=$(pings)
sh "$M/resume-ping.sh" > "$T/resume.log" 2>&1
got=$(head -n1 "$DATEF" 2>/dev/null)
if [ "$got" = 2026-09-18 ] && wait_ping "$c" 5; then pass "D resume writes today and ping returns"; D=1
else fail "D resume writes today and ping returns (date file [$got])"; fi

# E: pause file silences.
E=0
sh "$M/stop-ping.sh" > "$T/stop.log" 2>&1
sleep 1; c=$(pings)
if [ "$D" = 1 ] && no_ping "$c" 4; then pass "E pause file silences"; E=1
else fail "E pause file silences (needs D)"; fi

# F: pause removal restores ping.
c=$(pings)
rm -f "$TMPDIR"/session-ping-pause-*
if [ "$E" = 1 ] && wait_ping "$c" 5; then pass "F pause removal restores ping"
else fail "F pause removal restores ping (needs E)"; fi

# G: invalid PING_INTERVAL falls back to file value 2.
killtree "$PID1"; PID1=""
printf '2\n' > "$T/data/ping-interval"
PING_INTERVAL=abc sh "$M/ping.sh" "$T/data" > "$T/out2.log" 2>&1 &
PID2=$!
if wait_ping 0 5 "$T/out2.log"; then pass "G invalid PING_INTERVAL falls back to file"
else fail "G invalid PING_INTERVAL falls back to file"; fi

# H: timer restarts from zero on resume (interval 4 s, paused 4 s before resume).
killtree "$PID2"; PID2=""
sh "$M/stop-ping.sh" > "$T/stop2.log" 2>&1
PING_INTERVAL=4 sh "$M/ping.sh" "$T/data" > "$T/out3.log" 2>&1 &
PID2=$!
sleep 4
c=$(pings "$T/out3.log")
sh "$M/resume-ping.sh" > "$T/resume2.log" 2>&1
if [ "$c" -eq 0 ] && no_ping 0 3 "$T/out3.log" && wait_ping 0 3 "$T/out3.log"; then
  pass "H timer restarts from zero on resume"
else fail "H timer restarts from zero on resume (no ping in 3 s, ping by 6 s)"; fi

if [ "$FAILS" -eq 0 ] && [ "$N" -eq 9 ]; then
  echo "ping-test: PASS $N"; exit 0
fi
echo "ping-test: FAIL $FAILS failures, $N/9 cases passed"
exit 1
