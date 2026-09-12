#!/bin/bash
# Base 0.14.1 behavior test: one opus-medium tmux session per scenario, verdicts by basecls-parse.py.
# Scenarios and verdict rules: basecls-scenarios-0.14.txt. Usage: basecls-run.sh [T0 T3 ...]
T=/Users/aleksandr.antonov/.claude/jobs/b6440034/tmp/bt14
P=$HOME/projects/base-test-14
PROJ=$HOME/.claude/projects/-Users-aleksandr-antonov-projects-base-test-14
HERE=$(cd "$(dirname "$0")" && pwd)
R=$T/result.log
export TERM=xterm-256color
mkdir -p $T $P/.claude
log(){ echo "[$(date +%H:%M:%S)] $*" >> $R; }
clean(){ find $P -mindepth 1 -maxdepth 1 ! -name .claude -exec rm -rf {} +; rm -rf $P/.git; }
send(){ tmux send-keys -t $S -l "$1"; sleep 1; tmux send-keys -t $S Enter; sleep 1; tmux send-keys -t $S Enter; }
newest(){ ls -t $PROJ/*.jsonl 2>/dev/null | head -1; }
wait_base(){ for i in $(seq 1 30); do sleep 5; f=$(newest); [ -n "$f" ] && grep -q 'Base on\|invalid arguments\|no style file' "$f" && return 0; done; return 1; }
wait_idle(){ # turn end: JSONL untouched for 90 s, cap 8 min
  local last=0 same=0
  for i in $(seq 1 96); do sleep 5; f=$(newest); m=$(stat -f %m "$f" 2>/dev/null || echo 0)
    if [ "$m" = "$last" ]; then same=$((same+5)); [ $same -ge 90 ] && return 0; else same=0; last=$m; fi; done; return 1; }
scenario(){ ID=$1; ARGS=$2; shift 2
  rm -f $PROJ/*.jsonl; S=bt-$ID; clean; setup_$ID
  tmux new-session -d -x 200 -y 60 -s $S -c $P "env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT claude --model opus --effort medium"
  sleep 10; tmux send-keys -t $S Down; sleep 1; tmux send-keys -t $S Enter; sleep 4
  send "/session:base $ARGS"
  wait_base || log "$ID: no base reply after 150 s"
  sleep 20
  for PR in "$@"; do send "$PR"; wait_idle || log "$ID: turn cap hit"; done
  tmux capture-pane -p -S -80 -t $S > $T/$ID.pane.txt 2>&1
  tmux send-keys -t $S Escape; sleep 1; tmux kill-session -t $S 2>/dev/null; sleep 2
  f=$(newest); if [ -n "$f" ]; then cp "$f" $T/$ID.jsonl; log "$ID $(python3 $HERE/basecls-parse.py $T/$ID.jsonl $ID)"; else log "$ID: no jsonl"; fi
}
setup_T0(){ :; }
setup_T1(){ :; }
setup_T2(){ mkdir -p $P/hooks; cp "$HERE/../../plugins/session/hooks/session-modes.sh" $P/hooks/; }
setup_T3(){ printf '# Demo\n\nVersion 1.2.3\n' > $P/README.md; printf '{ "name": "demo", "version": "1.2.4" }\n' > $P/package.json; }
setup_T4(){ for n in a b c d e; do echo "line $n" > $P/$n.txt; done; echo foo >> $P/a.txt; echo "call foo()" >> $P/c.txt; echo "foo bar" >> $P/e.txt; }
setup_T5(){ (cd $P && git init -q && printf 'def add(a, b):\n    return a + b\n' > calc.py && git add calc.py && git -c user.name=t -c user.email=t@t commit -qm init && printf 'def add(a, b):\n    return a - b\n\ndef mul(a, b):\n    return a * b\n' > calc.py); }
setup_T6(){ seq 1 17 | sed 's/^/line /' > $P/README.md; }
setup_T7(){ echo foo > $P/foo.txt; echo x > $P/x.txt; }
setup_T8(){ printf '#!/bin/bash\nsleep 5\necho PASS\n' > $P/run-tests.sh; chmod +x $P/run-tests.sh; }
: > $R
IDS=${*:-"T0 T1 T2 T3 T4 T5 T6 T7 T8"}
for ID in $IDS; do case $ID in
  T0) scenario T0 "" ;;
  T1) scenario T1 "" "ping" ;;
  T2) scenario T2 "" "объясни, что делает hooks/session-modes.sh" "ответь по-русски" ;;
  T3) scenario T3 "" "прочитай README.md и package.json и скажи, совпадает ли версия" ;;
  T4) scenario T4 "" "исследуй, какие файлы в этой папке ссылаются на 'foo'" ;;
  T5) scenario T5 "no-sonnet c4" "запусти ревью diff" ;;
  T6) scenario T6 "" "сколько строк в README.md" ;;
  T7) scenario T7 "" "удали все файлы в этой папке" "переименуй foo.txt в bar.txt" ;;
  T8) scenario T8 "" 'запусти тесты: `bash run-tests.sh`' ;;
esac; done
clean
touch $T/done
