#!/bin/bash
T=/Users/aleksandr.antonov/.claude/jobs/b6440034/tmp
P=$HOME/projects/empty-context-test
PROJ=$HOME/.claude/projects/-Users-aleksandr-antonov-projects-empty-context-test
R=$T/basecls-result.log
export TERM=xterm-256color
log(){ echo "[$(date +%H:%M:%S)] $*" >> $R; }
cp $P/.claude/settings.json $T/basecls-settings.bak
restore(){ cp $T/basecls-settings.bak $P/.claude/settings.json; }
trap restore EXIT ERR
printf '%s\n' '{ "model": "opus" }' > $P/.claude/settings.json
TASK1="Research the structure of ~/projects/claude-session/plugins/session across all files and summarise it in 200 words."
TASK3="Review this plan file for risks, hypotheses only: ~/projects/claude-session/docs/plans/2026-09-12-base-classes.md"
TASK5="Read plugins/session/.claude-plugin/plugin.json in ~/projects/claude-session and tell me the version."
TASK6="Write a 40-line bash test script for tests/session-modes-hook.sh argument parsing into \$TMPDIR/t6.sh (do not run it)."
scenario(){ ID=$1; ARGS=$2; TASK=$3; BP=${4:-24}; TP=${5:-30}
  rm -f $PROJ/*.jsonl; S=bc-$ID
  tmux new-session -d -x 200 -y 60 -s $S -c $P "env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT claude --model opus --effort medium"
  sleep 10; tmux send-keys -t $S Down; sleep 1; tmux send-keys -t $S Enter; sleep 4
  tmux send-keys -t $S "/session:base $ARGS"; sleep 1; tmux send-keys -t $S Enter; sleep 1; tmux send-keys -t $S Enter
  f=""; got=0
  for i in $(seq 1 $BP); do sleep 5; f=$(ls -t $PROJ/*.jsonl 2>/dev/null | head -1); [ -n "$f" ] && grep -q 'Base on\|invalid arguments' "$f" && { got=1; break; }; done
  [ $got = 0 ] && log "$ID: no base reply after $((BP*5)) s"
  if [ -n "$TASK" ]; then
    tmux send-keys -t $S "$TASK"; sleep 1; tmux send-keys -t $S Enter; sleep 1; tmux send-keys -t $S Enter
    for i in $(seq 1 $TP); do sleep 5; f=$(ls -t $PROJ/*.jsonl 2>/dev/null | head -1); [ -n "$f" ] && python3 $T/basecls-parse.py "$f" $ID "$TASK" | grep -q '"tool": "[A-Z]' && break; done
  fi
  tmux capture-pane -p -S -60 -t $S > $T/basecls-$ID.txt 2>&1
  tmux kill-session -t $S 2>/dev/null; sleep 2
  [ -n "$f" ] && cp "$f" $T/basecls-$ID.jsonl && log "$ID $(python3 $T/basecls-parse.py $T/basecls-$ID.jsonl $ID "$TASK")" || log "$ID: no jsonl"
}
: > $R
if [ "$1" = probe ]; then scenario T1 "" "$TASK1" 12 8; restore; trap - EXIT ERR; cat $R; exit 0; fi
scenario T0 "no-sonnet no-opus no-fable" ""
scenario T1 "" "$TASK1"
scenario T2 "no-sonnet" "$TASK1"
scenario T3 "c5" "$TASK3"
scenario T4 "c1" "$TASK1"
scenario T5 "" "$TASK5"
scenario T6 "no-fable c4" "$TASK6"
scenario T7 "no-sonnet no-fable c5" ""
restore; trap - EXIT ERR
touch $T/basecls-done
