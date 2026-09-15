#!/bin/sh
# Plugin monitor: prints "ping" every interval so the session gets a turn and
# the prompt cache stays warm. Stops when a stop file for this session appears.
# $1: plugin data dir; "$1/ping-interval" may hold the interval in seconds.
here=$(cd "$(dirname "$0")" && pwd)
interval=3420
if [ -n "$1" ] && [ -f "$1/ping-interval" ]; then
  v=$(tr -dc '0-9' < "$1/ping-interval")
  [ -n "$v" ] && [ "$v" -gt 0 ] && interval=$v
fi
stops=$(sh "$here/session-pid.sh")
while true; do
  elapsed=0
  while [ "$elapsed" -lt "$interval" ]; do
    for f in $stops; do
      if [ -f "$f" ]; then rm -f $stops; exit 0; fi
    done
    step=$((interval - elapsed))
    [ "$step" -gt 60 ] && step=60
    sleep "$step"
    elapsed=$((elapsed + step))
  done
  echo ping
done
