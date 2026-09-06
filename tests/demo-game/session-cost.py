#!/usr/bin/env python3
"""Session total for one Claude Code project dir: walks every JSONL under it, dedups by
message.id, sums tokens per model, prices them with the pipeline-cost.py table.
Usage: session-cost.py <project dir> [--since ISO] [--until ISO]
Prints per-model rows, a total, misses (cache_creation 5m > 20K after a read drop), the
main-session turn count and wall time (first to last main turn, ping turns excluded)."""
import glob, json, os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "tools"))
from pipeline_cost_prices import PRICES, price_for  # noqa: E402

def usage_rows(path):
    seen = set()
    for line in open(path, encoding="utf-8", errors="replace"):
        try:
            d = json.loads(line)
        except Exception:
            continue
        if d.get("type") != "assistant":
            continue
        m = d.get("message") or {}
        u = m.get("usage")
        if not u:
            continue
        mid = m.get("id")
        if mid and mid in seen:
            continue
        seen.add(mid)
        cc = u.get("cache_creation") or {}
        yield d.get("timestamp"), m.get("model"), {
            "input": u.get("input_tokens", 0) or 0, "output": u.get("output_tokens", 0) or 0,
            "read": u.get("cache_read_input_tokens", 0) or 0,
            "w5": cc.get("ephemeral_5m_input_tokens", 0) or 0,
            "w1": cc.get("ephemeral_1h_input_tokens", 0) or 0}

def main():
    root = sys.argv[1]
    files = sorted(glob.glob(os.path.join(root, "**", "*.jsonl"), recursive=True))
    per = {}
    total = dict(input=0, output=0, read=0, w5=0, w1=0, usd=0.0, turns=0, miss=0)
    main_files = [f for f in files if os.path.dirname(f) == root.rstrip("/")]
    main_turns = 0
    first = last = None
    for f in files:
        prev = None
        for ts, model, u in usage_rows(f):
            p, key = price_for(model or "")
            row = per.setdefault(key or model or "?", dict(input=0, output=0, read=0, w5=0, w1=0, usd=0.0, turns=0, miss=0))
            usd = u["input"]*p[0] + u["output"]*p[1] + u["read"]*p[2] + u["w5"]*p[3] + u["w1"]*p[4]
            for k in ("input", "output", "read", "w5", "w1"):
                row[k] += u[k]; total[k] += u[k]
            row["usd"] += usd; total["usd"] += usd
            row["turns"] += 1; total["turns"] += 1
            if prev is not None and u["read"] < prev - 20000 and u["w5"] > 20000:
                row["miss"] += 1; total["miss"] += 1
            prev = u["read"]
            if f in main_files:
                main_turns += 1
                if ts:
                    first = first or ts
                    last = ts
    k = lambda n: f"{n/1000:.0f}K"
    for m, r in sorted(per.items(), key=lambda x: -x[1]["usd"]):
        print(f"{m:28} turns {r['turns']:4} in {k(r['input']):>6} out {k(r['output']):>6} read {k(r['read']):>7} w5 {k(r['w5']):>6} w1 {k(r['w1']):>6} miss {r['miss']:2} ${r['usd']:.2f}")
    print(f"TOTAL turns {total['turns']} read {k(total['read'])} w5 {k(total['w5'])} w1 {k(total['w1'])} out {k(total['output'])} miss {total['miss']} ${total['usd']:.2f}")
    print(f"MAIN turns {main_turns} first {first} last {last} files {len(files)}")

main()
