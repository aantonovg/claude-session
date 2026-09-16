#!/bin/sh
# Removes the pause files for the current session and writes today's date into
# its date files; ping.sh resumes on the next full interval.
here=$(cd "$(dirname "$0")" && pwd)
pauses=$(sh "$here/session-pid.sh")
[ -n "$pauses" ] || { echo "no claude ancestor found"; exit 1; }
d=$(date +%Y-%m-%d)
for f in $pauses; do
  rm -f "$f"
  printf '%s\n' "$d" > "$(printf '%s\n' "$f" | sed 's/session-ping-pause-/session-ping-date-/')"
  echo "$f"
done
