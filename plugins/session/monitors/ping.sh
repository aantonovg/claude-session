#!/bin/sh
# Plugin monitor: prints "ping" every interval so the session gets a turn and
# the prompt cache stays warm. Exits only when orphaned (parent pid 1: its
# claude process died); otherwise never exits (an exit would not re-arm):
# while a pause file for this session exists, or the day is not the
# active date, it keeps sleeping without printing and the timer stays at 0.
# Active date: latest of the start date and every valid session date file
# (written by resume-ping.sh). Only the same date pings, so nothing after 23:59
# and nothing on a later day until /session:resume-ping.
# With 57 min cadence the second-to-last ping of a day lands at 23:02 or earlier.
# $1: plugin data dir; "$1/ping-interval" may hold the interval in seconds.
# Env: PING_INTERVAL (seconds, wins when valid), PING_STEP (seconds, default 60),
# PING_DRY_RUN=1 (test hook: print resolved interval and step, exit).
here=$(cd "$(dirname "$0")" && pwd)
posint() { case "$1" in ''|*[!0-9]*) return 1 ;; esac; [ "$1" -gt 0 ]; }
interval=3420
if posint "${PING_INTERVAL:-}"; then
  interval=$PING_INTERVAL
elif [ -n "$1" ] && [ -f "$1/ping-interval" ]; then
  v=$(tr -dc '0-9' < "$1/ping-interval")
  posint "$v" && interval=$v
fi
step_max=${PING_STEP:-60}
posint "$step_max" || step_max=60
if [ "${PING_DRY_RUN:-}" = 1 ]; then echo "interval=$interval step=$step_max"; exit 0; fi
today() { date +%Y-%m-%d; }
start_date=$(today)
pauses=$(sh "$here/session-pid.sh")
dates=""
[ -n "$pauses" ] && dates=$(printf '%s\n' $pauses | sed 's/session-ping-pause-/session-ping-date-/')
paused() { for f in $pauses; do [ -f "$f" ] && return 0; done; return 1; }
active_date() {
  best=$start_date
  for p in $dates; do
    [ -f "$p" ] || continue
    f=$(head -n1 "$p" 2>/dev/null)
    printf '%s\n' "$f" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || continue
    expr "$f" \> "$best" >/dev/null && best=$f
  done
  printf '%s\n' "$best"
}
silent() { paused || [ "$(today)" != "$(active_date)" ]; }
while true; do
  elapsed=0
  while [ "$elapsed" -lt "$interval" ]; do
    if silent; then elapsed=0; fi
    step=$((interval - elapsed))
    [ "$step" -gt "$step_max" ] && step=$step_max
    sleep "$step"
    [ "$(ps -o ppid= -p $$ 2>/dev/null | tr -d ' ')" = 1 ] && exit 0
    elapsed=$((elapsed + step))
  done
  if silent; then continue; fi
  echo ping
done
