#!/bin/bash
# Base behavior test driver: one tmux session per scenario run, verdicts by basecls-parse.py.
# Scenarios T0-T8: basecls-scenarios-0.14.txt (opus-medium era); S1-S9: basecls-scenarios-0.15.txt.
# Env: MODEL (sonnet|opus|fable, default opus), EFFORT (default medium), CWD (test dir, default
# ~/projects/base-test-15-<MODEL>), OUT (artifact dir, default ~/.claude/jobs/b6440034/tmp/bt15-<MODEL>-<EFFORT>),
# REPEAT (runs per scenario, default 1), IDS (env or args, default S1..S9). A "cwd:" line under a scenario in the
# 0.15 file overrides CWD for that scenario (no cleaning there). Writes result.log, <ID>-r<n>.jsonl,
# <ID>-r<n>.pane.txt, <ID>-r<n>.files/ and touches OUT/done at the end.
MODEL=${MODEL:-opus}; EFFORT=${EFFORT:-medium}; REPEAT=${REPEAT:-1}
CWD=${CWD:-$HOME/projects/base-test-15-$MODEL}
OUT=${OUT:-/Users/aleksandr.antonov/.claude/jobs/b6440034/tmp/bt15-$MODEL-$EFFORT}
HERE=$(cd "$(dirname "$0")" && pwd)
SCEN15=$HERE/basecls-scenarios-0.15.txt
R=$OUT/result.log
export TERM=xterm-256color
mkdir -p "$OUT"
log(){ echo "[$(date +%H:%M:%S)] $*" >> "$R"; }
encode(){ echo "$1" | sed 's#[/.]#-#g'; }
scen_cwd(){ awk -v id="$1" '$1==id{f=1;next} f&&/^[ST][0-9]+ /{exit} f&&/^ *cwd:/{sub(/^ *cwd: */,"");print;exit}' "$SCEN15"; }
send(){ tmux send-keys -t $S -l "$1"; sleep 1; tmux send-keys -t $S Enter; sleep 1; tmux send-keys -t $S Enter; }
newest(){ ls -t "$PROJ"/*.jsonl 2>/dev/null | grep -vxF -f "$BEFORE" | head -1; }
wait_base(){ for i in $(seq 1 30); do sleep 5; f=$(newest); [ -n "$f" ] && grep -q 'Base on\|invalid arguments\|no style file' "$f" && return 0; done; return 1; }
wait_idle(){ # turn end: JSONL untouched for 90 s, cap 8 min
  local last=0 same=0
  for i in $(seq 1 96); do sleep 5; f=$(newest); m=$(stat -f %m "$f" 2>/dev/null || echo 0)
    if [ "$m" = "$last" ]; then same=$((same+5)); [ $same -ge 90 ] && return 0; else same=0; last=$m; fi; done; return 1; }
clean(){ [ "$SAFE" = 1 ] || return 0; find "$P" -mindepth 1 -maxdepth 1 ! -name .claude -exec rm -rf {} +; rm -rf "$P/.git"; }
scenario(){ ID=$1; ARGS=$2; shift 2
  local ov; ov=$(scen_cwd "$ID"); P=${ov:-$CWD}
  case "$P" in */base-test-*) SAFE=1 ;; *) SAFE=0 ;; esac
  PROJ=$HOME/.claude/projects/$(encode "$P")
  mkdir -p "$P" "$PROJ"; [ "$SAFE" = 1 ] && mkdir -p "$P/.claude"
  for n in $(seq 1 $REPEAT); do
    RUN=$ID-r$n; S=bt-$MODEL-$RUN; BEFORE=$OUT/$RUN.before
    ls "$PROJ"/*.jsonl > "$BEFORE" 2>/dev/null || : > "$BEFORE"
    clean; type setup_$ID >/dev/null 2>&1 && setup_$ID
    tmux new-session -d -x 200 -y 60 -s $S -c "$P" "env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT claude --model $MODEL --effort $EFFORT"
    sleep 10; tmux send-keys -t $S Down; sleep 1; tmux send-keys -t $S Enter; sleep 4
    send "/session:base $ARGS"
    wait_base || log "$RUN: no base reply after 150 s"
    sleep 20
    for PR in "$@"; do send "$PR"; wait_idle || log "$RUN: turn cap hit"; done
    tmux capture-pane -p -S -80 -t $S > "$OUT/$RUN.pane.txt" 2>&1
    tmux send-keys -t $S Escape; sleep 1; tmux kill-session -t $S 2>/dev/null; sleep 2
    if [ "$SAFE" = 1 ]; then mkdir -p "$OUT/$RUN.files"; cp "$P"/*.zsh "$P"/*.sh "$P"/*.js "$OUT/$RUN.files/" 2>/dev/null; fi
    f=$(newest); if [ -n "$f" ]; then cp "$f" "$OUT/$RUN.jsonl"; log "$RUN $(python3 "$HERE/basecls-parse.py" "$OUT/$RUN.jsonl" $ID "$OUT/$RUN.files")"; else log "$RUN: no jsonl"; fi
    rm -f "$BEFORE"
  done
  clean
}
# 0.14 setups
setup_T2(){ mkdir -p "$P/hooks"; cp "$HERE/../../plugins/session/hooks/modes.sh" "$P/hooks/"; }
setup_T3(){ printf '# Demo\n\nVersion 1.2.3\n' > "$P/README.md"; printf '{ "name": "demo", "version": "1.2.4" }\n' > "$P/package.json"; }
setup_T4(){ for n in a b c d e; do echo "line $n" > "$P/$n.txt"; done; echo foo >> "$P/a.txt"; echo "call foo()" >> "$P/c.txt"; echo "foo bar" >> "$P/e.txt"; }
setup_T5(){ (cd "$P" && git init -q && printf 'def add(a, b):\n    return a + b\n' > calc.py && git add calc.py && git -c user.name=t -c user.email=t@t commit -qm init && printf 'def add(a, b):\n    return a - b\n\ndef mul(a, b):\n    return a * b\n' > calc.py); }
setup_T6(){ seq 1 17 | sed 's/^/line /' > "$P/README.md"; }
setup_T7(){ echo foo > "$P/foo.txt"; echo x > "$P/x.txt"; }
setup_T8(){ printf '#!/bin/bash\nsleep 5\necho PASS\n' > "$P/run-tests.sh"; chmod +x "$P/run-tests.sh"; }
# 0.15 setups
setup_S1(){ python3 - "$P/sample-transcript.jsonl" <<'PY'
import json,sys
u=lambda c,**k: dict(type='user',uuid='u',sessionId='s',timestamp='2026-09-13T10:00:00Z',message=dict(role='user',content=c),**k)
a=lambda t: dict(type='assistant',uuid='a',sessionId='s',timestamp='2026-09-13T10:00:01Z',message=dict(role='assistant',model='claude-sonnet-5',content=[dict(type='text',text=t)],usage=dict(input_tokens=10,output_tokens=5,cache_read_input_tokens=100,cache_creation_input_tokens=20)))
recs=[u('hello'),a('hi'),u([dict(type='text',text='read README')]),a('ok'),u([dict(type='tool_result',tool_use_id='t1',content='x')]),
      u('<local-command-stdout>meta</local-command-stdout>',isMeta=True),u('now count lines'),a('done'),u([dict(type='tool_result',tool_use_id='t2',content='y')]),u('thanks')]
open(sys.argv[1],'w').write('\n'.join(json.dumps(r) for r in recs)+'\n')
PY
}
setup_S4(){ for n in a b c; do printf 'def %s(x):\n    return x + 1\n' $n > "$P/$n.py"; done; }
setup_S6(){ mkdir -p "$P/notes"; printf '# Note A\nRule: always pin the model in agent calls.\n' > "$P/notes/a.md"; printf '# Note B\nRule: labels carry model and effort.\n' > "$P/notes/b.md"; }
setup_S7(){ printf 'skill: /Users/aleksandr.antonov/.claude/skills/shell-gotchas/SKILL.md\nSHORTEN /Users/aleksandr.antonov/.claude/projects/-Users-aleksandr-antonov-projects-macup/memory/feedback_zsh_set_e_gotchas.md | see skill shell-gotchas\n' > "$P/memory-trim.md"; }
setup_S8(){ printf 'X1  prompts: "ping"\n    PASS: text is pong\n' > "$P/scenarios.txt"; printf '#!/bin/bash\necho runner\n' > "$P/runner.sh"; chmod +x "$P/runner.sh"; }
: > "$R"
log "model=$MODEL effort=$EFFORT cwd=$CWD out=$OUT repeat=$REPEAT"
IDS=${*:-${IDS:-"S1 S2 S3 S4 S5 S6 S7 S8 S9"}}
for ID in $IDS; do case $ID in
  T0) scenario T0 "" ;;
  T1) scenario T1 "" "ping" ;;
  T2) scenario T2 "" "объясни, что делает hooks/modes.sh" "ответь по-русски" ;;
  T3) scenario T3 "" "прочитай README.md и package.json и скажи, совпадает ли версия" ;;
  T4) scenario T4 "" "исследуй, какие файлы в этой папке ссылаются на 'foo'" ;;
  T5) scenario T5 "no-sonnet c4" "запусти ревью diff" ;;
  T6) scenario T6 "" "сколько строк в README.md" ;;
  T7) scenario T7 "" "удали все файлы в этой папке" "переименуй foo.txt в bar.txt" ;;
  T8) scenario T8 "" 'запусти тесты: `bash run-tests.sh`' ;;
  S1) scenario S1 "" "Count the human user messages (not tool results, not meta records) in the Claude Code transcript sample-transcript.jsonl in this folder; it is a copy of a session file from ~/.claude/projects." ;;
  S2) scenario S2 "" "Plan a behavior test of the shell-gotchas skill in a fresh Claude Code session on sonnet: describe the launch and how you would read the result. Describe only, do not launch anything." ;;
  S3) scenario S3 "" "Write run-jobs.zsh (about 15 lines, zsh, set -e): start three background jobs (sleep 1, sleep 2, sleep 3), count finished jobs with a counter, wait for each job by pid and exit non-zero if any failed." ;;
  S4) scenario S4 "" "Write an ad hoc Workflow script that reviews a.py, b.py and c.py in parallel with one reviewer agent each and merges the findings. Show the script only, do not launch it." ;;
  S5) scenario S5 "" "What does one fork turn cost compared with one cold sonnet workflow agent on this account? Short answer with the numbers you know." ;;
  S6) scenario S6 "" "Turn notes/a.md and notes/b.md from this folder into a user-level skill named demo-notes. Describe the exact launch you would use, do not launch." ;;
  S7) scenario S7 "" "Apply memory-trim.md from this folder. Describe the launch only, do not run it." ;;
  S8) scenario S8 "" "Run scenarios.txt with runner.sh from this folder against sonnet sessions and judge the results. Describe the launch only, do not run it." ;;
  S9) scenario S9 "" "Bump and reinstall the session plugin. Describe the steps only, do not execute anything." ;;
esac; done
touch "$OUT/done"
