#!/bin/bash
# Agent start-context driver: one sonnet main session launches each agent once through Workflow,
# the subagent JSONL is copied to $T/agentctx/<name>/ and its first request is itemized.
T=/Users/aleksandr.antonov/.claude/jobs/b6440034/tmp
P=$HOME/projects/empty-context-test
PROJ=$HOME/.claude/projects/-Users-aleksandr-antonov-projects-empty-context-test
R=$T/agentctx-result.log
OUT=$T/agentctx
S=agentctx
export TERM=xterm-256color
log(){ echo "[$(date +%H:%M:%S)] $*" >> $R; }
cp $P/.claude/settings.json $T/agentctx-project-settings.bak
restore(){ cp $T/agentctx-project-settings.bak $P/.claude/settings.json; tmux kill-session -t $S 2>/dev/null; log "project settings restored"; }
trap restore EXIT ERR
mkdir -p $OUT; : > $R
printf '%s\n' '{ "model": "sonnet" }' > $P/.claude/settings.json
rm -rf $PROJ

AGENTS="session:stage-executor session:stage-author session:stage-researcher session:stage-reviewer session:stage-critic session:waiter session:codex-proxy session:web-researcher session:code-reviewer session:simplifier session:security-reviewer session:artifact-publisher session:artifact-designer user-prefs:Explore general-purpose Explore"
[ "$1" = probe ] && AGENTS="session:stage-executor"

# parse one subagent jsonl: system prompt blocks, attachments, usage
parse(){ python3 - "$1" <<'PY'
import json,sys
p=sys.argv[1]; parts=[]; usage=None; tools_hint=''
for line in open(p):
    try:o=json.loads(line)
    except: continue
    t=o.get('type')
    if t=='attachment':
        a=o['attachment']; at=a.get('type')
        if at=='prompt_snapshot':
            sp=a.get('systemPrompt') or []
            if isinstance(sp,str): sp=[sp]
            for i,b in enumerate(sp):
                s=b if isinstance(b,str) else json.dumps(b)
                head=s[:60].replace('\n',' ')
                parts.append(('system_block%d'%i,len(s),head))
        else:
            parts.append(('att_'+str(at),len(json.dumps(a)),''))
    elif t=='user' and usage is None:
        c=o['message'].get('content'); s=c if isinstance(c,str) else json.dumps(c)
        parts.append(('user_prompt',len(s),s[:60].replace('\n',' ')))
    elif t=='assistant' and usage is None:
        u=o['message'].get('usage',{}); usage=(u.get('input_tokens',0),u.get('cache_creation_input_tokens',0),u.get('cache_read_input_tokens',0))
        break
tot=sum(x[1] for x in parts)
print(f"usage_total={sum(usage) if usage else 'NA'} input={usage[0] if usage else ''} create={usage[1] if usage else ''} read={usage[2] if usage else ''} snapshot_chars={tot}")
for n,l,h in parts: print(f"  {n} chars={l} tok4={l//4} head={h!r}")
PY
}

tmux new-session -d -x 220 -y 80 -s $S -c $P "env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT claude --model sonnet"
sleep 10; tmux send-keys -t $S Down; sleep 1; tmux send-keys -t $S Enter; sleep 5
SESSDIR=""
for a in $AGENTS; do
  name=${a//:/-}
  before=$(find $PROJ -type d -name 'wf_*' 2>/dev/null | sort)
  prompt="Use the Workflow tool with a one-agent script: agentType \"$a\", model \"sonnet\", effort \"low\", label \"son-lo-ctx-$name\", prompt \"Reply with the single word OK and nothing else.\" Reply only with the agent's return value."
  tmux send-keys -t $S "$prompt"; sleep 1; tmux send-keys -t $S Enter; sleep 1; tmux send-keys -t $S Enter
  found=""
  for i in $(seq 1 22); do sleep 5
    after=$(find $PROJ -type d -name 'wf_*' 2>/dev/null | sort)
    new=$(comm -13 <(echo "$before") <(echo "$after") | head -1)
    if [ -n "$new" ]; then f=$(ls $new/agent-*.jsonl 2>/dev/null | head -1); [ -n "$f" ] && grep -q '"type":"assistant"' "$f" && { found=$new; break; }; fi
  done
  sleep 3
  if [ -n "$found" ]; then
    mkdir -p $OUT/$name; cp -R $found/. $OUT/$name/
    f=$(ls $OUT/$name/agent-*.jsonl | head -1)
    log "agent $a | $(parse "$f" | head -1)"; parse "$f" | tail -n +2 >> $R
  else
    log "agent $a | NO SUBAGENT JSONL within 110 s"
  fi
done
tmux send-keys -t $S "/context"; sleep 1; tmux send-keys -t $S Enter; sleep 6
tmux capture-pane -p -S -300 -t $S > $T/agentctx-main-context.txt 2>&1
mf=$(ls -t $PROJ/*.jsonl 2>/dev/null | head -1); [ -n "$mf" ] && cp "$mf" $T/agentctx-main.jsonl
restore; trap - EXIT ERR
[ "$1" = probe ] || touch $T/agentctx-done
