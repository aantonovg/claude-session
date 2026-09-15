#!/bin/sh
# Removes the pause files for the current session; ping.sh resumes on the next full interval.
here=$(cd "$(dirname "$0")" && pwd)
pauses=$(sh "$here/session-pid.sh")
[ -n "$pauses" ] || { echo "no claude ancestor found"; exit 1; }
for f in $pauses; do rm -f "$f"; echo "$f"; done
