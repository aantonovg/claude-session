#!/usr/bin/env python3
"""Per-run cost breakdown for demo-game runs: model-effort rows with cw:out:cr split,
haiku codex-proxy shims, codex ledger rows attributed by shim time windows, agent counts
and label checks. Usage: batch-cost.py <run-name>... [--json out.json]
Effort comes from the `effort` field of each assistant record (main and every agent)."""
import glob, json, os, re, sys
from datetime import datetime, timedelta
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "tools"))
from pipeline_cost_prices import PRICES, CODEX_PRICES, CODEX_USAGE, price_for  # noqa: E402
RUNS = os.path.expanduser("~/projects/demo-game-runs")
MCODE = {"fable": "fab", "opus": "ops", "sonnet": "son", "haiku": "hai"}

def ts(s): return datetime.strptime(s[:19], "%Y-%m-%dT%H:%M:%S")
def project_dir(run):
    p = os.path.join(RUNS, run)
    return os.path.expanduser("~/.claude/projects/" + re.sub(r"[^A-Za-z0-9-]", "-", p))

def scan(path):
    """One JSONL: usage rows (dedup by message.id), effort, timestamps, tool calls."""
    seen, rows, calls, effort, first, last = set(), [], [], None, None, None
    for line in open(path, encoding="utf-8", errors="replace"):
        try: d = json.loads(line)
        except Exception: continue
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
    return rows, effort, first, last, calls

def price(model, inp, out, cr, w5, w1):
    p, key = price_for(model)
    return key or model, (inp * p[0], out * p[1], cr * p[2], w5 * p[3] + w1 * p[4])

def run_report(run, codex_rows):
    root = project_dir(run)
    mains = [f for f in glob.glob(os.path.join(root, "*.jsonl"))]
    per, agents, shims, notes = {}, {"fork": 0, "cold": 0, "codex": 0}, [], []
    main_model = main_eff = None; main_turns = 0; first = last = None
    def add(model, eff, kind, rows):
        _, key = price_for(model); key = key or model
        r = per.setdefault((key, eff or "?", kind), dict(inp=0, out=0, cr=0, cw=0, usd_in=0, usd_out=0, usd_cr=0, usd_cw=0, turns=0, agents=0, kind=kind))
        for _, i, o, c, w5, w1 in rows:
            _, (ui, uo, uc, uw) = price(model, i, o, c, w5, w1)
            r["inp"] += i; r["out"] += o; r["cr"] += c; r["cw"] += w5 + w1
            r["usd_in"] += ui; r["usd_out"] += uo; r["usd_cr"] += uc; r["usd_cw"] += uw; r["turns"] += 1
        r["agents"] += 1
        return r
    for f in mains:
        rows, eff, fi, la, calls = scan(f)
        if not rows: continue
        main_model, main_eff, main_turns = rows[0][0], eff, main_turns + len(rows)
        first = min(filter(None, [first, fi])); last = max(filter(None, [last, la]))
        add(main_model, eff, "main", rows)
        code = f"{MCODE.get(next((k for k in MCODE if k in main_model), ''), '?')}-{(eff or '?')[:2]}-"
        for t, name, inp in calls:
            if name == "Agent":
                if inp.get("subagent_type") != "fork": notes.append(f"Agent non-fork: {inp.get('subagent_type')} {inp.get('name', '')}")
                elif not (inp.get("name") or "").startswith(code): notes.append(f"fork mislabel: {inp.get('name')} (expected {code}*)")
            if name == "Workflow" and inp.get("script"):
                s = inp["script"]; n = len(re.findall(r"\bagent\(", s))
                if n and (len(re.findall(r"\bmodel\s*:", s)) < n or len(re.findall(r"\beffort\s*:", s)) < n):
                    notes.append(f"Workflow agent() without explicit model+effort: {re.search(r'name:\s*[\'\"]([^\'\"]+)', s).group(1) if re.search(r'name:\s*[\'\"]([^\'\"]+)', s) else '?'}")
    for f in glob.glob(os.path.join(root, "**", "agent-*.jsonl"), recursive=True):
        rows, eff, fi, la, calls = scan(f)
        if not rows: continue
        codex_calls = [(t, i["command"]) for t, n, i in calls if n == "Bash" and "codex-exec-logged" in str(i.get("command", ""))]
        is_fork = "/workflows/" not in f
        kind = "fork" if is_fork else ("codex" if codex_calls else "cold")
        agents[kind] += 1
        eff = eff or ("medium" if kind == "codex" else None)  # shim launched at effort medium, field absent on haiku records
        r = add(rows[0][0], eff, kind, rows)
        if kind == "codex":
            tot = [sum(x[k] for x in rows) for k in (1, 2, 3, 4, 5)]
            _, usd = price(rows[0][0], *tot)
            shims.append(dict(agent=os.path.basename(f)[6:-6], model=rows[0][0], turns=len(rows), inp=tot[0], out=tot[1], cr=tot[2], cw=tot[3] + tot[4], usd=sum(usd),
                              codex_cmds=len(codex_calls), targets=[re.search(r"-m (\S+)", c).group(1) for _, c in codex_calls if re.search(r"-m (\S+)", c)],
                              t0=min(t for t, _ in codex_calls), t1=la))
        if kind == "cold" and "sonnet" in rows[0][0]:
            r.setdefault("start_tokens", []).append(rows[0][3] + rows[0][4] + rows[0][5] + rows[0][1])
    # codex ledger rows attributed to this run's shims: model matches a shim target, ts inside [t0-5s, t1+5min]
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
    return dict(run=run, main=f"{main_model}-{main_eff}", turns_main=main_turns, wall_min=round((ts(last) - ts(first)).total_seconds() / 60, 1) if first else None,
                rows={f"{m}-{e}/{k}": r for (m, e, k), r in per.items()}, shims=shims, codex=codex, agents=agents, notes=notes,
                usd_claude=round(claude_usd, 2), usd_codex=round(sum(k["usd"] for k in codex.values()), 2), usd_shim=round(sum(s["usd"] for s in shims), 2))

def main():
    out = sys.argv[sys.argv.index("--json") + 1] if "--json" in sys.argv else None
    args = [a for a in sys.argv[1:] if not a.startswith("--") and a != out]
    codex_rows = [json.loads(l) for l in open(CODEX_USAGE)] if os.path.exists(CODEX_USAGE) else []
    reps = [run_report(r, codex_rows) for r in args]
    K = lambda n: f"{n/1000:.0f}K"
    for R in reps:
        print(f"\n## {R['run']}  main {R['main']}  turns {R['turns_main']}  wall {R['wall_min']} min  Claude ${R['usd_claude']}  codex ${R['usd_codex']}  haiku shim ${R['usd_shim']}  agents fork/cold/codex {R['agents']['fork']}/{R['agents']['cold']}/{R['agents']['codex']}")
        print("| model-effort | kind | agents | turns | cw | out | cr | in | $cw | $out | $cr | $in | $ |\n|---|---|---|---|---|---|---|---|---|---|---|---|---|")
        for k, r in sorted(R["rows"].items(), key=lambda x: -(x[1]["usd_in"] + x[1]["usd_out"] + x[1]["usd_cr"] + x[1]["usd_cw"])):
            print(f"| {k} | {r['kind']} | {r['agents']} | {r['turns']} | {K(r['cw'])} | {K(r['out'])} | {K(r['cr'])} | {K(r['inp'])} | {r['usd_cw']:.2f} | {r['usd_out']:.2f} | {r['usd_cr']:.2f} | {r['usd_in']:.2f} | {r['usd_cw']+r['usd_out']+r['usd_cr']+r['usd_in']:.2f} |")
        for s in R["shims"]:
            print(f"haiku codex-proxy {s['agent']}: targets {','.join(s['targets'])} codex cmds {s['codex_cmds']} turns {s['turns']} cw {K(s['cw'])} out {K(s['out'])} cr {K(s['cr'])} ${s['usd']:.3f}")
        for k, c in R["codex"].items():
            print(f"codex {k}: calls {c['calls']} in {K(c['inp'])} cached {K(c['cached'])} out {K(c['out'])} ${c['usd']:.2f}")
        for n in R["notes"]: print("note:", n)
    if out:
        json.dump(dict(runs=reps, codex_unattributed=[r for r in codex_rows if not r.get("run")][-20:]), open(out, "w"), indent=1, default=str)
main()
