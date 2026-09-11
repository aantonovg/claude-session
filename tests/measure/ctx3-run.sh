#!/bin/bash
# round 2 min-context driver: config only (plugins off, tools denied, user files aside)
T=/Users/aleksandr.antonov/.claude/jobs/b6440034/tmp
P=$HOME/projects/empty-context-test
PROJ=$HOME/.claude/projects/-Users-aleksandr-antonov-projects-empty-context-test
R=$T/ctx3-result.log
US=$HOME/.claude/settings.json
export TERM=xterm-256color
log(){ echo "[$(date +%H:%M:%S)] $*" >> $R; }
usage(){ python3 - "$1" <<'PY'
import json,sys
for line in open(sys.argv[1]):
    try: o=json.loads(line)
    except: continue
    if o.get('type')=='assistant':
        u=o['message'].get('usage',{})
        i=u.get('input_tokens',0); c=u.get('cache_creation_input_tokens',0); r=u.get('cache_read_input_tokens',0)
        print(f"total={i+c+r} input={i} cache_create={c} cache_read={r}"); break
PY
}
cats(){ sed 's/\x1b\[[0-9;]*m//g' "$1" | grep -E 'System prompt|System tools|MCP tools|Custom agents|Memory files|Skills:|Messages:|Free space' | sed 's/^[^A-Za-z]*//' | tr -s ' ' | tr '\n' ';'; }
variant(){ # name
  N=$1; POLL=${2:-18}
  rm -f $PROJ/*.jsonl
  tmux new-session -d -x 220 -y 80 -s ctx3-$N -c $P "env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT claude --model sonnet"
  sleep 10
  tmux send-keys -t ctx3-$N Down; sleep 1; tmux send-keys -t ctx3-$N Enter; sleep 4
  tmux capture-pane -p -t ctx3-$N > $T/ctx3-$N-start.txt 2>&1
  tmux send-keys -t ctx3-$N "hi"; sleep 1; tmux send-keys -t ctx3-$N Enter; sleep 1; tmux send-keys -t ctx3-$N Enter
  U=""
  for i in $(seq 1 $POLL); do
    sleep 5
    f=$(ls -t $PROJ/*.jsonl 2>/dev/null | head -1)
    [ -n "$f" ] && grep -q '"type":"assistant"' "$f" && { U=$(usage "$f"); break; }
  done
  tmux send-keys -t ctx3-$N "/context"; sleep 1; tmux send-keys -t ctx3-$N Enter; sleep 6
  tmux capture-pane -p -S -300 -t ctx3-$N > $T/ctx3-$N.txt 2>&1
  tmux send-keys -t ctx3-$N "/context all"; sleep 1; tmux send-keys -t ctx3-$N Enter; sleep 6
  tmux capture-pane -p -S -300 -t ctx3-$N > $T/ctx3all-$N.txt 2>&1
  tmux kill-session -t ctx3-$N 2>/dev/null; sleep 2
  log "variant $N | ${U:-NO ASSISTANT MESSAGE} | cats: $(cats $T/ctx3-$N.txt) | files: $T/ctx3-$N.txt $T/ctx3all-$N.txt"
}
DENY_TOOLS='"Bash","Edit","Write","MultiEdit","NotebookEdit","Glob","Grep","WebFetch","WebSearch","Agent","Skill","Task","TodoWrite","TaskCreate","TaskUpdate","TaskList","TaskGet","TaskOutput","TaskStop","Artifact","Workflow","Monitor","CronCreate","CronDelete","CronList","ScheduleWakeup","SendMessage","ListAgents","EnterPlanMode","ExitPlanMode","EnterWorktree","ExitWorktree","KillShell","BashOutput","LSP","ToolSearch","AskUserQuestion","SendFeedback","ReportFindings","PushNotification","RemoteTrigger","DesignSync","SendUserFile","mcp__*"'
write_settings(){ # deny list ("" = none)
  mkdir -p $P/.claude
  DENY="$1"
  cat > $P/.claude/settings.json <<JS
{
  "model": "sonnet",
  "disableAllHooks": true,
  "includeCoAuthoredBy": false,
  "enabledPlugins": {},
  "env": { "DISABLE_AUTOUPDATER": "1", "DISABLE_TELEMETRY": "1", "CLAUDE_CODE_DISABLE_TERMINAL_TITLE": "1" },
  "permissions": { "deny": [ $DENY ] }
}
JS
}
plugins_off(){ python3 - <<'PY'
import json,os
h=os.path.expanduser('~/.claude')
s=json.load(open(h+'/settings.json'))
ip=json.load(open(h+'/plugins/installed_plugins.json'))
names=list(ip.get('plugins',ip).keys())
s['enabledPlugins']={n:False for n in names}
json.dump(s,open(h+'/settings.json','w'),indent=2)
print('plugins off:',len(names))
PY
}
B=$T/user-backup3; mkdir -p $B
cp $US $B/settings.json.bak; cp $US $T/user-settings.bak
MOVED=""
restore(){
  for n in $MOVED; do
    [ -e ~/.claude/$n ] && mv ~/.claude/$n $B/created-$n-$(date +%s)
    mv $B/$n ~/.claude/$n && log "restored $n" || log "RESTORE FAILED $n"
  done
  MOVED=""
  cp $B/settings.json.bak $US
  if diff -q $US $T/user-settings.bak >/dev/null; then log "user settings restored: identical"; else log "USER SETTINGS DIFF AFTER RESTORE"; fi
  log "verify: $(ls ~/.claude/CLAUDE.md ~/.claude/skills ~/.claude/agents ~/.claude/memory-user 2>&1 | head -4 | tr '\n' ' ')"
}
trap restore EXIT ERR
: > $R
log "$(plugins_off)"

FULL="\"Read\",$DENY_TOOLS,\"EndConversation\""
deny_minus(){ echo "$FULL" | sed "s/\"$1\",//; s/,\"$1\"//"; }
write_settings_hooks(){ mkdir -p $P/.claude; cat > $P/.claude/settings.json <<JS
{ "model": "sonnet", "includeCoAuthoredBy": false, "enabledPlugins": {}, "env": { "DISABLE_AUTOUPDATER": "1", "DISABLE_TELEMETRY": "1", "CLAUDE_CODE_DISABLE_TERMINAL_TITLE": "1" }, "permissions": { "deny": [ $FULL ] } }
JS
}
if [ "$1" = probe ]; then write_settings "$(deny_minus Bash)"; variant only-Bash 10; restore; trap - EXIT ERR; cat $R; exit 0; fi
write_settings "$FULL"; variant v8-none
for t in Bash Read Edit Write NotebookEdit Glob Grep WebFetch WebSearch Agent Skill ToolSearch AskUserQuestion Artifact Workflow Monitor TaskCreate TaskUpdate TaskList TaskGet TaskOutput TaskStop CronCreate CronDelete CronList ScheduleWakeup SendMessage ListAgents EnterPlanMode ExitPlanMode EnterWorktree ExitWorktree SendFeedback ReportFindings PushNotification RemoteTrigger DesignSync SendUserFile EndConversation; do write_settings "$(deny_minus $t)"; variant only-$t 10; done
cp $B/settings.json.bak $US; write_settings "$FULL"; variant plugins-on-hooks-off 10; write_settings_hooks; variant hooks-on 10
restore; trap - EXIT ERR
touch $T/ctx3-done
