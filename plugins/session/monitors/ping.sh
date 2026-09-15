#!/bin/sh
# Plugin monitor: prints "ping" every interval so the session gets a turn and
# the prompt cache stays warm. Never exits on its own: while a pause file for
# this session exists it keeps sleeping without printing; when the file goes,
# pinging resumes on the next full interval.
# $1: plugin data dir; "$1/ping-interval" may hold the interval in seconds.
here=$(cd "$(dirname "$0")" && pwd)
interval=3420
if [ -n "$1" ] && [ -f "$1/ping-interval" ]; then
  v=$(tr -dc '0-9' < "$1/ping-interval")
  [ -n "$v" ] && [ "$v" -gt 0 ] && interval=$v
fi
pauses=$(sh "$here/session-pid.sh")
paused() { for f in $pauses; do [ -f "$f" ] && return 0; done; return 1; }
while true; do
  elapsed=0
  while [ "$elapsed" -lt "$interval" ]; do
    if paused; then elapsed=0; fi
    step=$((interval - elapsed))
    [ "$step" -gt 60 ] && step=60
    sleep "$step"
    elapsed=$((elapsed + step))
  done
  if paused; then continue; fi
  echo ping
done
