#!/bin/zsh
# Watch the demo tmux sessions and touch a done-file when all of them are idle.
# Idle = the pane shows no running work ("esc to interrupt") and no agent rows ("◯ ")
# for IDLE_MIN consecutive minutes. Runs detached; the main session waits on the file.
# Usage: watch-done.sh <done-file> <session>... ; log goes to stdout.
set -u
done_file=$1; shift
IDLE_MIN=${IDLE_MIN:-8}
typeset -A idle
for s in "$@"; do idle[$s]=0; done
while true; do
  all=1
  for s in "$@"; do
    pane=$(tmux capture-pane -p -t "demo-$s" 2>/dev/null) || { echo "$(date +%T) $s: no tmux session"; idle[$s]=$IDLE_MIN; continue; }
    if print -r -- "$pane" | grep -qE 'esc to interrupt|^ *◯ '; then
      idle[$s]=0
    else
      idle[$s]=$(( ${idle[$s]} + 1 ))
    fi
    (( ${idle[$s]} >= IDLE_MIN )) || all=0
  done
  echo "$(date +%T) idle minutes: $(for s in "$@"; do print -n "$s=${idle[$s]} "; done)"
  if (( all )); then touch "$done_file"; echo "$(date +%T) all idle, done"; exit 0; fi
  sleep 60
done
