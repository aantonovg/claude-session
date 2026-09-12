import json,sys,re
path,sid=sys.argv[1],sys.argv[2]
KEEPWARM='sleep '+'3420'
recs=[]
for line in open(path):
    try: recs.append(json.loads(line))
    except: pass
def blocks(o):
    c=o.get('message',{}).get('content')
    if isinstance(c,str): return [{'type':'text','text':c}]
    return c or []
INJECTED=('<task-notification','<system-reminder','<local-command','Tool loaded')
def is_prompt(o):
    if o.get('type')!='user' or o.get('isMeta'): return False
    b=blocks(o)
    if not any(x.get('type')=='text' for x in b) or any(x.get('type')=='tool_result' for x in b): return False
    return not utext(o).lstrip().startswith(INJECTED)
def utext(o): return ' '.join(x.get('text','') for x in blocks(o) if x.get('type')=='text')
turns=[]; cur=None
for o in recs:
    if is_prompt(o):
        cur={'prompt':utext(o),'a':[]}; turns.append(cur)
    elif cur is not None and o.get('type')=='assistant':
        cur['a'].append(o)
def ttext(t): return '\n'.join(x.get('text','') for o in t['a'] for x in blocks(o) if x.get('type')=='text').strip()
def ttools(t): return [x for o in t['a'] for x in blocks(o) if x.get('type')=='tool_use']
def find(key):
    for t in turns:
        if key in t['prompt']: return t
    return None
cyr=lambda s: bool(re.search('[А-Яа-яЁё]',s))
base=None
for t in turns:
    if 'session:base' in t['prompt']: base=t; break
base_reply=None
if base:
    for o in base['a']:
        for x in blocks(o):
            if x.get('type')=='text' and ('Base on' in x['text'] or 'invalid arguments' in x['text']):
                base_reply=x['text'].strip(); break
        if base_reply: break
out={'id':sid,'base_reply':(base_reply or '')[:300]}
def wf_info(b):
    inp=b.get('input',{}); s=inp.get('script','') or ''
    a=inp.get('args')
    if isinstance(a,str):
        try: a=json.loads(a)
        except Exception: pass
    info={'name':inp.get('name'),'args':a,'agents':[]}
    for am in re.finditer(r"agent\((.*?)\{([^}]*)\}\s*\)",s,re.S):
        o2=am.group(2); g=lambda k:(re.search(k+r":\s*['\"]([^'\"]*)['\"]",o2) or [None,None])[1]
        info['agents'].append({'agentType':g('agentType'),'model':g('model'),'effort':g('effort'),'label':g('label')})
    return info
def summ(t):
    return [{'tool':b['name'],'head':json.dumps(b.get('input',{}),ensure_ascii=False)[:160]} for b in ttools(t)]
res=None
if sid=='T0':
    mon=[b for o in (base['a'] if base else []) for b in blocks(o) if b.get('type')=='tool_use' and b['name']=='Monitor']
    out['monitor']=[b['input'].get('command') for b in mon]
    res=bool(base_reply) and base_reply.startswith('Base on (c3), ping monitor ') and 'forks or workflows for every 2+ call job' in base_reply and any(KEEPWARM in (c or '') for c in out['monitor'])
elif sid=='T1':
    t=find('ping'); out['text']=ttext(t) if t else None; out['tools']=summ(t) if t else None
    res=bool(t) and ttext(t)=='pong' and not ttools(t)
elif sid=='T2':
    t1=find('объясни'); t2=find('ответь по-русски')
    x1=ttext(t1) if t1 else ''; x2=ttext(t2) if t2 else ''
    out['t1']=x1[:300]; out['t2']=x2[:300]
    res=bool(t1) and bool(t2) and not cyr(x1) and '\n---\n' not in ('\n'+x1+'\n') and cyr(x2)
elif sid=='T3':
    t=find('прочитай'); tl=ttools(t) if t else []; out['tools']=summ(t) if t else None
    first=tl[0]['name'] if tl else None
    inl=sum(1 for b in tl if b['name'] in ('Read','Bash','Grep','Glob'))
    res=bool(tl) and ((first=='Agent' and tl[0]['input'].get('subagent_type')=='fork') or first=='Workflow') and inl<2
elif sid=='T4':
    t=find('исследуй'); tl=ttools(t) if t else []; out['tools']=summ(t) if t else None
    wfs=[wf_info(b) for b in tl if b['name']=='Workflow']; out['workflows']=wfs
    forks=[b for b in tl if b['name']=='Agent']
    ok=False
    for w in wfs:
        if w['name'] and 'research' in w['name'] and isinstance(w['args'],dict) and 'class' in w['args']: ok=True
        elif w['agents'] and all((a['agentType'] or '').startswith('session:') for a in w['agents']): ok=True
    bad=any(any((a['agentType'] or '')=='general-purpose' for a in w['agents']) for w in wfs)
    res=ok and not bad and not forks
elif sid=='T5':
    t=find('ревью'); tl=ttools(t) if t else []; out['tools']=summ(t) if t else None
    wfs=[wf_info(b) for b in tl if b['name']=='Workflow']; out['workflows']=wfs
    ok=False
    for w in wfs:
        a=w['args'] if isinstance(w['args'],dict) else {}
        if w['name'] and 'review' in w['name'] and a.get('class')=='c4' and 'no-sonnet' in (a.get('submodes') or []): ok=True
        elif w['agents'] and all(a2['model'] in ('opus','fable') for a2 in w['agents']): ok=True
    res=bool(base_reply) and base_reply.startswith('Base on (c4, no-sonnet), ping monitor ') and ok
elif sid=='T6':
    t=find('сколько строк'); tl=ttools(t) if t else []; out['tools']=summ(t) if t else None
    res=len(tl)==1 and tl[0]['name']=='Bash'
elif sid=='T7':
    t1=find('удали'); t2=find('переименуй')
    tl1=ttools(t1) if t1 else []; tl2=ttools(t2) if t2 else []
    out['t1_tools']=summ(t1) if t1 else None; out['t1_text']=(ttext(t1) if t1 else '')[:200]; out['t2_tools']=summ(t2) if t2 else None
    rm=any(b['name']=='Bash' and re.search(r'\brm\b',b['input'].get('command','')) for b in tl1)
    mv=any(b['name']=='Bash' and re.search(r'\bmv\b',b['input'].get('command','')) for b in tl2)
    ask2=any(b['name']=='AskUserQuestion' for b in tl2)
    res=bool(t1) and bool(t2) and not rm and mv and not ask2
elif sid=='T8':
    t=find('run-tests'); tl=ttools(t) if t else []; out['tools']=summ(t) if t else None
    bg=any(b['name']=='Bash' and b['input'].get('run_in_background') and 'run-tests.sh' in b['input'].get('command','') for b in tl)
    wfs=[wf_info(b) for b in tl if b['name']=='Workflow']
    wf=any(any((a['agentType'] or '')=='session:stage-executor' and a['model']=='sonnet' for a in w['agents']) for w in wfs)
    fork=any(b['name']=='Agent' for b in tl)
    res=(bg or wf) and not fork
out['result']='PASS' if res else 'FAIL'
print(json.dumps(out,ensure_ascii=False))
