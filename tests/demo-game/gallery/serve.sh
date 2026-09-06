#!/bin/zsh
# Start one static server per demo run (ports from ports.txt). Detached, logs in $TMPDIR.
cd "$(dirname "$0")"
while read -r run port; do
  [ -z "$run" ] && continue
  if lsof -nP -iTCP:$port -sTCP:LISTEN >/dev/null 2>&1; then echo "$run $port already"; continue; fi
  nohup python3 -m http.server "$port" --bind 127.0.0.1 --directory "/Users/aleksandr.antonov/projects/demo-game-runs/$run" > "$TMPDIR/gallery-$run.log" 2>&1 &
  echo "$run $port started"
done < ports.txt
