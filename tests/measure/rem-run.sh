#!/bin/bash
# system-reminder attribution driver: JSONLs kept as $T/rem-<v>.jsonl
T=/Users/aleksandr.antonov/.claude/jobs/b6440034/tmp
P=$HOME/projects/empty-context-test
PROJ=$HOME/.claude/projects/-Users-aleksandr-antonov-projects-empty-context-test
R=$T/rem-result.log
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
rems(){ python3 - "$1" <<'PY'
import json,sys,re
n=0
for line in open(sys.argv[1]):
    try: o=json.loads(line)
    except: continue
    if o.get('type')=='user':
        c=o['message'].get('content')
        if isinstance(c,str): c=[{'type':'text','text':c}]
        for b in c:
            if b.get('type')!='text': continue
            for m in re.finditer(r'<system-reminder>(.*?)</system-reminder>',b['text'],re.S):
                t=m.group(1).strip(); n+=1
                print(f"rem{n} chars={len(t)} head={t[:70]!r}")
        break
PY
}
cats(){ sed 's/\x1b\[[0-9;]*m//g' "$1" | grep -E 'System prompt|System tools|Custom agents|Memory files|Skills:|Messages:' | sed 's/^[^A-Za-z]*//' | tr -s ' ' | tr '\n' ';'; }
variant(){ N=$1; POLL=${2:-18}
  rm -f $PROJ/*.jsonl
  tmux new-session -d -x 220 -y 80 -s rem-$N -c $P "env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT claude --model sonnet"
  sleep 10; tmux send-keys -t rem-$N Down; sleep 1; tmux send-keys -t rem-$N Enter; sleep 4
  tmux send-keys -t rem-$N "hi"; sleep 1; tmux send-keys -t rem-$N Enter; sleep 1; tmux send-keys -t rem-$N Enter
  U=""; f=""
  for i in $(seq 1 $POLL); do sleep 5; f=$(ls -t $PROJ/*.jsonl 2>/dev/null | head -1); [ -n "$f" ] && grep -q '"type":"assistant"' "$f" && { U=$(usage "$f"); break; }; done
  tmux send-keys -t rem-$N "/context"; sleep 1; tmux send-keys -t rem-$N Enter; sleep 6
  tmux capture-pane -p -S -300 -t rem-$N > $T/rem-$N.txt 2>&1
  tmux kill-session -t rem-$N 2>/dev/null; sleep 2
  [ -n "$f" ] && cp "$f" $T/rem-$N.jsonl
  log "variant $N | ${U:-NO ASSISTANT MESSAGE} | cats: $(cats $T/rem-$N.txt)"
  [ -n "$f" ] && rems $T/rem-$N.jsonl | sed "s/^/  $N /" >> $R
}
DENY='"Read","Bash","Edit","Write","MultiEdit","NotebookEdit","Glob","Grep","WebFetch","WebSearch","Agent","Skill","Task","TodoWrite","TaskCreate","TaskUpdate","TaskList","TaskGet","TaskOutput","TaskStop","Artifact","Workflow","Monitor","CronCreate","CronDelete","CronList","ScheduleWakeup","SendMessage","ListAgents","EnterPlanMode","ExitPlanMode","EnterWorktree","ExitWorktree","KillShell","BashOutput","LSP","ToolSearch","AskUserQuestion","SendFeedback","ReportFindings","PushNotification","RemoteTrigger","DesignSync","SendUserFile","mcp__*","EndConversation"'
deny_minus(){ echo "$DENY" | sed "s/\"$1\",//; s/,\"$1\"//"; }
settings(){ mkdir -p $P/.claude; printf '%s\n' "$1" > $P/.claude/settings.json; }
settings_deny(){ settings "{ \"model\": \"sonnet\", \"disableAllHooks\": true, \"permissions\": { \"deny\": [ $1 ] } }"; }
plugins_off(){ python3 - <<'PY'
import json,os
h=os.path.expanduser('~/.claude'); s=json.load(open(h+'/settings.json'))
ip=json.load(open(h+'/plugins/installed_plugins.json')); names=list(ip.get('plugins',ip).keys())
s['enabledPlugins']={n:False for n in names}; json.dump(s,open(h+'/settings.json','w'),indent=2); print('plugins off:',len(names))
PY
}
cp $US $T/rem-user-settings.bak
restore(){ cp $T/rem-user-settings.bak $US; diff -q $US $T/rem-user-settings.bak >/dev/null && log "user settings restored: identical" || log "USER SETTINGS DIFF"; settings_deny "$DENY"; }
trap restore EXIT ERR
: > $R
if [ "$1" = probe ]; then settings '{ "model": "sonnet" }'; variant baseline 12; trap - EXIT ERR; settings_deny "$DENY"; cat $R; exit 0; fi
settings '{ "model": "sonnet" }'; variant baseline
settings '{ "model": "sonnet", "disableAllHooks": true }'; variant hooks-off
log "$(plugins_off)"
settings_deny "$DENY"; variant v8-none
for t in TaskCreate Skill Agent; do settings_deny "$(deny_minus $t)"; variant only-$t; done
restore; trap - EXIT ERR
touch $T/rem-done
