#!/usr/bin/env python3
"""Per-run cost breakdown for the corporate bw runs (b2connect-workspace project dir).
Same logic as tests/demo-game/batch-cost.py, keyed by main session id instead of run dir.
Usage: corp-cost.py <run-name>=<session-id-prefix>... [--json out.json] [--md out.md]
Rows: model-effort x kind (main, fork, cold Workflow agent by agentType, haiku codex shim),
tokens cw(5m/1h):out:cr and $ split, codex ledger rows attributed by shim time windows."""
import glob, json, os, re, sys
from datetime import datetime, timedelta
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "tools"))
from pipeline_cost_prices import PRICES, CODEX_PRICES, CODEX_USAGE, price_for  # noqa: E402
PROJ = os.path.expanduser("~/.claude/projects/-Users-Shared-projects-b2connect-workspace")
MCODE = {"fable": "fab", "opus": "ops", "sonnet": "son", "haiku": "hai"}

def ts(s): return datetime.strptime(s[:19], "%Y-%m-%dT%H:%M:%S")

def scan(path):
    seen, rows, calls, effort, agent_type, first, last = set(), [], [], None, None, None, None
    for line in open(path, encoding="utf-8", errors="replace"):
        try: d = json.loads(line)
        except Exception: continue
        agent_type = agent_type or d.get("attributionAgent") or d.get("agentType")
        if d.get("type") != "assistant": continue
        m = d.get("message") or {}
        effort = effort or d.get("effort")
        t = d.get("timestamp")
        if t: first = first or t; last = t
        for c in m.get("content") or []:
            if isinstance(c, dict) and c.get("type") == "tool_use": calls.append((t, c["name"], c["input"]))
        u, mid = m.get("usage"), m.get("id")
        if not u or (mid and mid in seen): continue
        seen.add(mid); cc = u.get("cache_creation") or {}
        rows.append((m.get("model") or "?", u.get("input_tokens", 0) or 0, u.get("output_tokens", 0) or 0,
                     u.get("cache_read_input_tokens", 0) or 0,
                     cc.get("ephemeral_5m_input_tokens", 0) or 0, cc.get("ephemeral_1h_input_tokens", 0) or 0))
    return rows, effort, first, last, calls, agent_type

def price(model, inp, out, cr, w5, w1):
    p, key = price_for(model)
    return key or model, (inp * p[0], out * p[1], cr * p[2], w5 * p[3] + w1 * p[4])

def run_report(run, sid, codex_rows):
    main = glob.glob(os.path.join(PROJ, sid + "*.jsonl"))[0]
    root = main[:-6]
    per, agents, shims, notes, wf_labels = {}, {"fork": 0, "cold": 0, "codex": 0}, [], [], []
    def add(model, eff, kind, rows):
        _, key = price_for(model); key = key or model
        r = per.setdefault((key, eff or "?", kind), dict(inp=0, out=0, cr=0, cw5=0, cw1=0, usd_in=0, usd_out=0, usd_cr=0, usd_cw=0, turns=0, agents=0, kind=kind))
        for _, i, o, c, w5, w1 in rows:
            _, (ui, uo, uc, uw) = price(model, i, o, c, w5, w1)
            r["inp"] += i; r["out"] += o; r["cr"] += c; r["cw5"] += w5; r["cw1"] += w1
            r["usd_in"] += ui; r["usd_out"] += uo; r["usd_cr"] += uc; r["usd_cw"] += uw; r["turns"] += 1
        r["agents"] += 1
        return r
    rows, eff, first, last, calls, _ = scan(main)
    main_model, main_eff = rows[0][0], eff
    add(main_model, eff, "main", rows)
    code = f"{MCODE.get(next((k for k in MCODE if k in main_model), ''), '?')}-{(eff or '?')[:2]}-"
    pings = sum(1 for _ in open(main) if '"ping"' in _ and '"type":"user"' in _.replace(" ", ""))
    for t, name, inp in calls:
        if name == "Agent":
            if inp.get("subagent_type") != "fork": notes.append(f"Agent non-fork: {inp.get('subagent_type')} {inp.get('name', '')}")
            elif not (inp.get("name") or "").startswith(code): notes.append(f"fork mislabel: {inp.get('name')} (expected {code}*)")
        if name == "Workflow" and inp.get("script"):
            s = inp["script"]; n = len(re.findall(r"\bagent\(", s))
            wf_labels += re.findall(r"label:\s*['\"]([^'\"]+)", s)
            if n and (len(re.findall(r"\bmodel\s*:", s)) < n or len(re.findall(r"\beffort\s*:", s)) < n):
                nm = re.search(r"name:\s*['\"]([^'\"]+)", s)
                notes.append(f"Workflow agent() without explicit model+effort: {nm.group(1) if nm else '?'}")
    for f in glob.glob(os.path.join(root, "**", "agent-*.jsonl"), recursive=True):
        rows, eff, fi, la, calls, atype = scan(f)
        if not rows: continue
        last = max(last, la or last)
        codex_calls = [(t, i["command"]) for t, n, i in calls if n == "Bash" and "codex-exec-logged" in str(i.get("command", ""))]
        is_fork = "/workflows/" not in f
        kind = "fork" if is_fork else ("codex" if codex_calls else f"cold:{atype or '?'}")
        agents["fork" if is_fork else ("codex" if codex_calls else "cold")] += 1
        eff = eff or ("medium" if kind == "codex" else None)
        add(rows[0][0], eff, kind, rows)
        if kind == "codex":
            tot = [sum(x[k] for x in rows) for k in (1, 2, 3, 4, 5)]
            _, usd = price(rows[0][0], *tot)
            shims.append(dict(agent=os.path.basename(f)[6:-6], model=rows[0][0], turns=len(rows), inp=tot[0], out=tot[1], cr=tot[2], cw=tot[3] + tot[4], usd=sum(usd),
                              codex_cmds=len(codex_calls), targets=[re.search(r"-m (\S+)", c).group(1) for _, c in codex_calls if re.search(r"-m (\S+)", c)],
                              t0=min(t for t, _ in codex_calls), t1=la))
    codex = {}
    for row in codex_rows:
        for sh in shims:
            if row["model"] in sh["targets"] and ts(sh["t0"]) - timedelta(seconds=5) <= ts(row["ts"]) <= ts(sh["t1"]) + timedelta(minutes=5) and not row.get("run"):
                row["run"] = run
                p = CODEX_PRICES.get(row["model"], CODEX_PRICES["gpt-5.6-sol"])
                k = codex.setdefault(f"{row['model']}-{row['effort']}", dict(calls=0, inp=0, cached=0, out=0, usd=0.0))
                k["calls"] += 1; k["inp"] += row["input"] - row["cached_input"]; k["cached"] += row["cached_input"]; k["out"] += row["output"]
                k["usd"] += (row["input"] - row["cached_input"]) * p[0] + row["cached_input"] * p[1] + row["output"] * p[2]
    claude_usd = sum(r["usd_in"] + r["usd_out"] + r["usd_cr"] + r["usd_cw"] for r in per.values())
    return dict(run=run, sid=sid, main=f"{main_model}-{main_eff}", turns_main=per[(price_for(main_model)[1] or main_model, main_eff or "?", "main")]["turns"], pings=pings,
                wall_min=round((ts(last) - ts(first)).total_seconds() / 60, 1), rows={f"{m}-{e}/{k}": r for (m, e, k), r in per.items()},
                shims=shims, codex=codex, agents=agents, wf_labels=wf_labels, notes=notes,
                usd_claude=round(claude_usd, 2), usd_codex=round(sum(k["usd"] for k in codex.values()), 2), usd_shim=round(sum(s["usd"] for s in shims), 2))

def render(reps):
    K = lambda n: f"{n/1000:.0f}K"; L = []
    for R in reps:
        L.append(f"\n## {R['run']}  main {R['main']}  main turns {R['turns_main']} (pings {R['pings']})  wall {R['wall_min']} min  Claude ${R['usd_claude']}  codex ${R['usd_codex']}  haiku shim ${R['usd_shim']}  agents fork/cold/codex {R['agents']['fork']}/{R['agents']['cold']}/{R['agents']['codex']}\n")
        L.append("| model-effort | kind | agents | turns | cw 5m | cw 1h | out | cr | $cw | $out | $cr | $in | $ |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|")
        for k, r in sorted(R["rows"].items(), key=lambda x: -(x[1]["usd_in"] + x[1]["usd_out"] + x[1]["usd_cr"] + x[1]["usd_cw"])):
            L.append(f"| {k.split('/')[0]} | {r['kind']} | {r['agents']} | {r['turns']} | {K(r['cw5'])} | {K(r['cw1'])} | {K(r['out'])} | {K(r['cr'])} | {r['usd_cw']:.2f} | {r['usd_out']:.2f} | {r['usd_cr']:.2f} | {r['usd_in']:.2f} | {r['usd_cw']+r['usd_out']+r['usd_cr']+r['usd_in']:.2f} |")
        for s in R["shims"]:
            L.append(f"- haiku codex-proxy {s['agent']}: targets {','.join(s['targets'])}, codex cmds {s['codex_cmds']}, turns {s['turns']}, cw {K(s['cw'])} out {K(s['out'])} cr {K(s['cr'])}, ${s['usd']:.3f}")
        for k, c in R["codex"].items():
            L.append(f"- codex {k}: calls {c['calls']}, in {K(c['inp'])} cached {K(c['cached'])} out {K(c['out'])}, ${c['usd']:.2f}")
        L.append("- Workflow labels: " + ", ".join(R["wf_labels"]))
        for n in R["notes"]: L.append("- note: " + n)
    tot = lambda k: round(sum(R[k] for R in reps), 2)
    L.append(f"\n## Total  Claude ${tot('usd_claude')}  codex ${tot('usd_codex')}  haiku shim ${tot('usd_shim')} (shim included in Claude)  all ${round(tot('usd_claude')+tot('usd_codex'), 2)}")
    return "\n".join(L)

def main():
    a = sys.argv[1:]
    out = a[a.index("--json") + 1] if "--json" in a else None
    md = a[a.index("--md") + 1] if "--md" in a else None
    runs = [x.split("=") for x in a if "=" in x]
    codex_rows = [json.loads(l) for l in open(CODEX_USAGE)] if os.path.exists(CODEX_USAGE) else []
    reps = [run_report(r, s, codex_rows) for r, s in runs]
    text = render(reps); print(text)
    if md: open(md, "w").write("# Corporate runs cost 2026-09-07\n" + text + "\n")
    if out: json.dump(dict(runs=reps, codex_unattributed=[r for r in codex_rows if not r.get("run") and r["ts"] >= "2026-09-06T21"]), open(out, "w"), indent=1, default=str)
main()
