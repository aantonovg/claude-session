import json,sys,re
path,sid,task=sys.argv[1],sys.argv[2],sys.argv[3]
recs=[]
for line in open(path):
    try: recs.append(json.loads(line))
    except: pass
def texts(o):
    c=o.get('message',{}).get('content')
    if isinstance(c,str): return [c]
    return [b.get('text','') for b in (c or []) if b.get('type')=='text']
def tools(o):
    c=o.get('message',{}).get('content')
    if not isinstance(c,list): return []
    return [b for b in c if b.get('type')=='tool_use']
base_reply=None; bi=None
for i,o in enumerate(recs):
    if o.get('type')=='assistant' and bi is None:
        for t in texts(o):
            if 'Base on' in t or 'invalid arguments' in t:
                base_reply=t.strip().replace('\n',' ')[:200]; bi=i; break
out={'id':sid,'base_reply':base_reply,'tool':None}
if bi is not None and task:
    for o in recs[bi+1:]:
        if o.get('type')!='assistant': continue
        tl=tools(o)
        if not tl: continue
        b=tl[0]; out['tool']=b['name']; inp=b.get('input',{})
        if b['name']=='Workflow':
            s=inp.get('script','') or ''
            m=re.search(r"name:\s*'([^']*)'",s); out['meta_name']=m.group(1) if m else None
            out['agents']=[]
            for am in re.finditer(r"agent\((.*?)\{([^}]*)\}\s*\)",s,re.S):
                o2=am.group(2)
                g=lambda k:(re.search(k+r":\s*'([^']*)'",o2) or [None,None])[1]
                out['agents'].append({'agentType':g('agentType'),'model':g('model'),'effort':g('effort'),'label':g('label')})
        elif b['name']=='Agent':
            out['subagent_type']=inp.get('subagent_type'); out['description']=inp.get('description')
        else:
            out['input_head']=json.dumps(inp)[:120]
        break
def ok_wf(agt,model,effort,labpre,metapre):
    if out.get('tool')!='Workflow': return False
    if out.get('meta_name') is None or not out['meta_name'].startswith(metapre): return False
    ags=out.get('agents') or []
    return any((a['agentType']==agt) and a['model']==model and a['effort']==effort and (a['label'] or '').startswith(labpre) for a in ags)
res=None
if sid=='T0': res='invalid arguments' in (base_reply or '')
elif sid=='T1': res=ok_wf('session:stage-researcher','sonnet','high','son-hi-','c3-')
elif sid=='T2': res=ok_wf('session:stage-researcher','opus','medium','ops-me-','c3-no-sonnet')
elif sid=='T3': res=ok_wf('session:stage-reviewer','fable','high','fab-hi-','c5')
elif sid=='T4': res=ok_wf('session:stage-researcher','sonnet','low','son-lo-','c1')
elif sid=='T5': res=out.get('tool') in ('Bash','Read') or (out.get('tool')=='Agent' and out.get('subagent_type')=='fork')
elif sid=='T6': res=ok_wf('session:stage-author','opus','high','ops-hi-','c4-no-fable')
elif sid=='T7': res=bool(base_reply) and base_reply.startswith('Base on (c5, no-sonnet, no-fable), ping monitor') and 'forks or workflows for every 2+ call job' in base_reply
out['result']='PASS' if res else 'FAIL'
print(json.dumps(out,ensure_ascii=False))
