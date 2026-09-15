#!/bin/sh
# Creates the stop files for the current session; ping.sh exits within 60 s.
here=$(cd "$(dirname "$0")" && pwd)
stops=$(sh "$here/session-pid.sh")
[ -n "$stops" ] || { echo "no claude ancestor found"; exit 1; }
for f in $stops; do : > "$f"; echo "$f"; done
