#!/usr/bin/env python3
"""Subagent cache-miss losses over a period, and what the 1h subagent TTL would have cost.

Usage: cache-loss.py [HOURS] [--root DIR]

Scans every subagent transcript (forks, plain subagents, teammates, workflow agents)
under ~/.claude/projects/*/<session>/subagents/ modified in the last HOURS (default 24),
dedups assistant entries by message id, and flags a cache miss as a turn whose cache
read drops by more than 20K tokens against the previous turn while its 5m write exceeds
20K. Prices per MTok (USD): 5m write / 1h write, by model family.
"""
import glob
import json
import os
import sys
import time

PRICES = {  # 5m write, 1h write, per MTok
    "claude-fable": (12.5, 20.0),
    "claude-opus": (6.25, 10.0),
    "claude-sonnet": (2.5, 4.0),
    "claude-haiku": (1.25, 2.0),
}
MISS_DROP = 20_000
MISS_WRITE = 20_000


def price(model):
    for k, v in PRICES.items():
        if model and model.startswith(k):
            return v
    return PRICES["claude-opus"]


def scan(path):
    seen = set()
    turns = []
    model = None
    with open(path) as fh:
        for line in fh:
            try:
                d = json.loads(line)
            except ValueError:
                continue
            if d.get("type") != "assistant":
                continue
            msg = d.get("message") or {}
            mid = msg.get("id")
            if mid in seen:
                continue
            seen.add(mid)
            model = msg.get("model") or model
            u = msg.get("usage") or {}
            cc = u.get("cache_creation") or {}
            turns.append((
                u.get("cache_read_input_tokens", 0) or 0,
                cc.get("ephemeral_5m_input_tokens", 0) or 0,
                cc.get("ephemeral_1h_input_tokens", 0) or 0,
            ))
    return model, turns


def main():
    hours = 24.0
    root = os.path.expanduser("~/.claude/projects")
    args = sys.argv[1:]
    if "--root" in args:
        i = args.index("--root")
        root = args[i + 1]
        del args[i:i + 2]
    if args:
        hours = float(args[0])
    since = time.time() - hours * 3600
    files = [f for f in glob.glob(os.path.join(root, "*", "*", "subagents", "**", "*.jsonl"), recursive=True)
             if os.path.getmtime(f) >= since]
    total_files = 0
    miss_cost = 0.0
    miss_tokens = 0
    misses = 0
    extra_1h = 0.0
    all_w5 = 0
    rows = []
    for f in sorted(files, key=os.path.getmtime):
        model, turns = scan(f)
        if not turns:
            continue
        total_files += 1
        p5, p1 = price(model)
        w5_sum = sum(t[1] for t in turns)
        all_w5 += w5_sum
        extra_1h += w5_sum / 1e6 * (p1 - p5)
        prev_read = None
        f_miss = 0
        f_miss_tokens = 0
        for read, w5, _w1 in turns:
            if prev_read is not None and read < prev_read - MISS_DROP and w5 > MISS_WRITE:
                f_miss += 1
                f_miss_tokens += w5
            prev_read = read
        if f_miss:
            misses += f_miss
            miss_tokens += f_miss_tokens
            miss_cost += f_miss_tokens / 1e6 * p5
            rows.append((os.path.basename(f)[:40], model or "?", len(turns), f_miss, f_miss_tokens))
    print(f"period: last {hours:g} h, subagent transcripts with turns: {total_files}")
    print(f"cache misses: {misses} in {len(rows)} transcripts, {miss_tokens/1000:.0f}K tokens rewritten, "
          f"loss ≈ ${miss_cost:.2f} (at 5m write prices)")
    print(f"all subagent 5m writes: {all_w5/1000:.0f}K tokens; the 1h TTL would have added ≈ ${extra_1h:.2f} "
          f"and avoided the misses above")
    if rows:
        print(f"\n{'transcript':42} {'model':18} {'turns':>5} {'miss':>4} {'tokens':>8}")
        for r in rows:
            print(f"{r[0]:42} {r[1]:18} {r[2]:5} {r[3]:4} {r[4]/1000:7.0f}K")


if __name__ == "__main__":
    main()
