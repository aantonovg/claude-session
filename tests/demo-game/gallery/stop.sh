#!/bin/zsh
# Stop the gallery servers by port.
cd "$(dirname "$0")"
while read -r run port; do
  [ -z "$run" ] && continue
  pids=$(lsof -nP -iTCP:$port -sTCP:LISTEN -t 2>/dev/null)
  [ -n "$pids" ] && kill $pids && echo "$run $port stopped"
done < ports.txt
