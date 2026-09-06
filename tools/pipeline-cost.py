#!/usr/bin/env python3
"""Cost of one pipeline-mode task, cut by stage, role, kind and model+effort.

Usage:
  pipeline-cost.py <task dir> [--session <id>] [--projects <dir>] [--json]
  pipeline-cost.py --all-runs <pipeline root> [--projects <dir>] [--json]
  pipeline-cost.py --selftest

The pipeline skill writes <task dir>/ledger.jsonl: one line per spawn or main-session
stage (ts, stage, step, role, kind main|fork|workflow-agent, model, effort, mode
fast|standard|full, agent_id, label) plus {ts, agent_id, event:"stop"} lines appended
by the SubagentStop hook. This script joins those rows with the transcripts:
  main session   <projects>/<encoded-cwd>/<session>.jsonl (session id from <task dir>/session)
  agents         <projects>/<encoded-cwd>/<session>/subagents/**/agent-<id>.jsonl
Assistant entries are deduplicated by message id (a turn is re-logged when the context is
rewritten). Cost per row = tokens × the claude-cost price table (per token, USD). A cache
miss is a turn whose cache read drops by more than 20K against the previous turn while
its 5m write exceeds 20K (same rule as cache-loss.py). Main-session usage is assigned to
the latest ledger row of kind "main" whose ts is not later than the entry; turns before
the first main row or with an unparsable timestamp, and agent transcripts not named in
the ledger, are reported as "unattributed" under the session total. Without a session
file the newest main transcript by mtime is used, with a warning.
Rows of kind "codex-agent" (session:codex) are priced from ~/.codex/proxy-usage.jsonl
(one record per codex run: ts, model, effort, input, cached_input, output, reasoning_output):
a record belongs to the row when its ts lies in [row ts - 2 min, stop mark], else up to the
next codex row of the same tier and effort (retries land in the same row), else +4 h. A row
whose ts is older than the previous row's by more than 1 h is mis-stamped and takes the
previous row's ts. Codex prices: the codex rows of claude-cost; astra has none and shows "?".
Rows of kind "workflow-agent" and "codex-agent" may have agent_id null: the main session
cannot know a workflow agent's id before the launch. Such rows are resolved by label: the
saved workflow script (<session>/workflows/scripts/*-<run id>.js) that contains the label
names the run, whose journal lists the agent ids in launch order; failing that, the agent
whose first prompt contains the label.
"""
import glob
import io
import json
import os
import re
import subprocess
import sys
import tempfile
from collections import defaultdict
from datetime import datetime, timezone

# Copied from claude-cost (swiftbar-plugins/main.go, pricingTable), USD per token:
# input, output, cache read, cache write 5m, cache write 1h. Longest-prefix match.
PRICES = {
    "claude-fable-5-1": (10e-6, 50e-6, 2.5e-7, 12.5e-6, 20e-6),
    "claude-fable-5": (10e-6, 50e-6, 1e-6, 12.5e-6, 20e-6),
    "claude-opus-5": (5e-6, 25e-6, 5e-7, 6.25e-6, 10e-6),
    "claude-opus-4-8": (5e-6, 25e-6, 5e-7, 6.25e-6, 10e-6),
    "claude-opus-4-7": (5e-6, 25e-6, 5e-7, 6.25e-6, 10e-6),
    "claude-sonnet-5": (2e-6, 10e-6, 2e-7, 2.5e-6, 4e-6),
    "claude-sonnet-4-5": (3e-6, 15e-6, 3e-7, 3.75e-6, 6e-6),
    "claude-haiku-4-5": (1e-6, 5e-6, 1e-7, 1.25e-6, 2e-6),
}
DEFAULT_PRICE_KEY = "claude-opus-4-8"
# Copied from claude-cost codexPricingTable, USD per token: input, cached input, output.
CODEX_PRICES = {
    "gpt-5.6-sol": (4e-6, 4e-7, 20e-6),
    "gpt-5.6-terra": (2e-6, 2e-7, 12e-6),
    "gpt-5.6-luna": (2e-7, 2e-8, 1.2e-6),
    "gpt-reserve": (2e-7, 2e-8, 1.2e-6),  # luna billed against the reserve quota
}
CODEX_TIERS = {"sol": "gpt-5.6-sol", "terra": "gpt-5.6-terra", "luna": "gpt-5.6-luna",
               "luna-reserve": "gpt-reserve", "astra": "gpt-6-astra"}  # astra: no price yet
CODEX_USAGE = os.path.expanduser("~/.codex/proxy-usage.jsonl")
CODEX_WINDOW_S = 4 * 3600
CODEX_LEAD_S = 120          # a usage record may be stamped up to 2 min before its ledger row
CODEX_TAIL_S = 600          # a last codex row's window ends 10 min after the task's last row
MISSTAMP_S = 3600           # a row ts older than the previous row's by more than this is wrong
MISS_DROP = 20_000
MISS_WRITE = 20_000
FIELDS = ("input", "output", "read", "w5", "w1")


def price_for(model):
    best = ""
    for k in PRICES:
        if model and model.startswith(k) and len(k) > len(best):
            best = k
    return PRICES[best or DEFAULT_PRICE_KEY], best or None


def parse_ts(s):
    if not s:
        return None
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).astimezone(timezone.utc)
    except ValueError:
        return None


def iter_assistant(lines):
    """Yield (ts, model, usage dict) per unique assistant message from JSONL lines."""
    seen = set()
    for line in lines:
        try:
            d = json.loads(line)
        except ValueError:
            continue
        if d.get("type") != "assistant":
            continue
        msg = d.get("message") or {}
        mid = msg.get("id")
        if mid and mid in seen:
            continue
        if mid:
            seen.add(mid)
        u = msg.get("usage") or {}
        cc = u.get("cache_creation") or {}
        yield parse_ts(d.get("timestamp")), msg.get("model"), {
            "input": u.get("input_tokens", 0) or 0,
            "output": u.get("output_tokens", 0) or 0,
            "read": u.get("cache_read_input_tokens", 0) or 0,
            "w5": cc.get("ephemeral_5m_input_tokens", 0) or 0,
            "w1": cc.get("ephemeral_1h_input_tokens", 0) or 0,
        }


def zero():
    return {"input": 0, "output": 0, "read": 0, "w5": 0, "w1": 0, "miss": 0, "turns": 0, "usd": 0.0}


def add_turns(acc, turns, model_hint=None):
    """Accumulate a sequence of (ts, model, usage) into acc; returns the model seen."""
    prev_read = None
    model = model_hint
    for _ts, m, u in turns:
        model = m or model
        p, _ = price_for(model)
        for f in FIELDS:
            acc[f] += u[f]
        acc["turns"] += 1
        acc["usd"] += (u["input"] * p[0] + u["output"] * p[1] + u["read"] * p[2]
                       + u["w5"] * p[3] + u["w1"] * p[4])
        if prev_read is not None and u["read"] < prev_read - MISS_DROP and u["w5"] > MISS_WRITE:
            acc["miss"] += 1
        prev_read = u["read"]
    return model


def codex_price(model):
    best = ""
    for k in CODEX_PRICES:
        if model and model.startswith(k) and len(k) > len(best):
            best = k
    return CODEX_PRICES[best] if best else None


def load_codex_usage(path=CODEX_USAGE):
    """Records of the codex-proxy usage ledger as (ts, model, effort, input, cached, output)."""
    recs = []
    if not os.path.isfile(path):
        return None
    with open(path) as fh:
        for line in fh:
            try:
                d = json.loads(line)
            except ValueError:
                continue
            ts = parse_ts(d.get("ts"))
            if ts is None:
                continue
            recs.append((ts, d.get("model") or "", d.get("effort") or "",
                         int(d.get("input") or 0), int(d.get("cached_input") or 0),
                         int(d.get("output") or 0) + int(d.get("reasoning_output") or 0)))
    recs.sort()
    return recs


def add_codex(acc, recs, model_hint):
    """Accumulate codex usage records into acc (input, read=cached, output, usd; turns = runs).
    Returns False when the model has no price (usd stays 0 and the row shows ?)."""
    priced = True
    for _ts, m, _e, inp, cached, out in recs:
        p = codex_price(m or CODEX_TIERS.get(model_hint or "", ""))
        acc["input"] += inp - cached
        acc["read"] += cached
        acc["output"] += out
        acc["turns"] += 1
        if p is None:
            priced = False
        else:
            acc["usd"] += (inp - cached) * p[0] + cached * p[1] + out * p[2]
    return priced


def codex_windows(rows, stops):
    """{id(row): (start, end)} for codex-agent rows: start = row ts - CODEX_LEAD_S, end = stop
    mark, else the next codex row with the same tier and effort, else the task's last row or
    stop mark + CODEX_TAIL_S, else ts + CODEX_WINDOW_S (a task with nothing after the row)."""
    out = {}
    stamped = [(parse_ts(r.get("ts")), r) for r in rows]
    task_end = max([t for t, _ in stamped if t is not None] + [t for t in map(parse_ts, stops.values()) if t],
                   default=None)
    for i, (ts, r) in enumerate(stamped):
        if r.get("kind") != "codex-agent" or ts is None:
            continue
        end = parse_ts(stops.get(r.get("agent_id")))
        if end is None:
            nxt = [t for t, x in stamped[i + 1:] if t is not None and t > ts
                   and x.get("kind") == "codex-agent" and x.get("model") == r.get("model")
                   and x.get("effort") == r.get("effort")]
            end = nxt[0] if nxt else None
        if end is None and task_end is not None and task_end > ts:
            end = datetime.fromtimestamp(task_end.timestamp() + CODEX_TAIL_S, timezone.utc)
        if end is None:
            end = datetime.fromtimestamp(ts.timestamp() + CODEX_WINDOW_S, timezone.utc)
        out[id(r)] = (datetime.fromtimestamp(ts.timestamp() - CODEX_LEAD_S, timezone.utc), end)
    return out


def fix_misstamps(rows):
    """Rows in file order: a ts older than the previous row's by more than MISSTAMP_S is
    replaced by the previous row's ts (the original stays in ts_raw). Returns the rows sorted."""
    prev = None
    for r in rows:
        ts = parse_ts(r.get("ts"))
        if ts is not None and prev is not None and (prev - ts).total_seconds() > MISSTAMP_S:
            r["ts_raw"] = r["ts"]
            r["ts"] = prev.strftime("%Y-%m-%dT%H:%M:%SZ")
            ts = prev
        if ts is not None:
            prev = ts
    floor = datetime.min.replace(tzinfo=timezone.utc)
    rows.sort(key=lambda r: parse_ts(r.get("ts")) or floor)
    return rows


def load_ledger(task_dir):
    rows, stops = [], {}
    path = os.path.join(task_dir, "ledger.jsonl")
    if not os.path.isfile(path):
        return rows, stops
    with open(path) as fh:
        for line in fh:
            try:
                d = json.loads(line)
            except ValueError:
                continue
            if d.get("event") == "stop":
                stops[d.get("agent_id")] = d.get("ts")
            elif "stage" in d or "kind" in d:
                rows.append(d)
    return fix_misstamps(rows), stops


def label_index(projects, session_id):
    """{label: [agent ids in launch order]} from the saved workflow scripts of the session
    (<root>/<session>/workflows/scripts/*-<run id>.js) joined with each run's journal."""
    out = defaultdict(list)
    if not session_id:
        return out
    for sp in glob.glob(os.path.join(projects, "*", session_id, "workflows", "scripts", "*.js")):
        base = os.path.basename(sp)[:-len(".js")]
        i = base.rfind("wf_")
        if i < 0:
            continue
        run_id = base[i:]
        try:
            text = open(sp).read()
        except OSError:
            continue
        labels = [m for m in re.findall(r"label:\s*['\"`]([^'\"`]+)['\"`]", text) if "${" not in m]
        ids = []
        for j in glob.glob(os.path.join(projects, "*", session_id, "subagents", "workflows", run_id, "journal.jsonl"))[:1]:
            for line in open(j):
                try:
                    d = json.loads(line)
                except ValueError:
                    continue
                if d.get("type") == "started" and d.get("agentId") and d["agentId"] not in ids:
                    ids.append(d["agentId"])
        if labels and ids and len(labels) == len(ids):
            for lab, aid in zip(labels, ids):
                out[lab].append(aid)
        elif len(labels) == 1 and ids:
            out[labels[0]].extend(ids)
    return out


def first_prompt(path, limit=4000):
    """The text of the first user message of an agent transcript (for label matching)."""
    try:
        with open(path) as fh:
            for line in fh:
                try:
                    d = json.loads(line)
                except ValueError:
                    continue
                if d.get("type") != "user":
                    continue
                c = (d.get("message") or {}).get("content")
                if isinstance(c, list):
                    c = " ".join(x.get("text", "") for x in c if isinstance(x, dict))
                return (c or "")[:limit]
    except OSError:
        pass
    return ""


def resolve_label(row, labels, prompts, taken):
    """Agent id for a row without agent_id: by label via the workflow scripts, else the agent
    whose first prompt contains the label. Ids already taken by another row are skipped."""
    lab = row.get("label") or ""
    if not lab:
        return None
    for aid in labels.get(lab, []):
        if aid not in taken:
            return aid
    for aid, text in prompts.items():
        if aid not in taken and lab in text:
            return aid
    return None


def find_transcripts(projects, session_id, task_dir):
    """Return (main jsonl path or None, {agent_id: path})."""
    main, agents = None, {}
    pat_root = os.path.join(projects, "*")
    if session_id:
        for m in glob.glob(os.path.join(pat_root, session_id + ".jsonl")):
            main = m
        for a in glob.glob(os.path.join(pat_root, session_id, "subagents", "**", "agent-*.jsonl"),
                           recursive=True):
            agents[os.path.basename(a)[len("agent-"):-len(".jsonl")]] = a
    return main, agents


def compute(rows, stops, main_lines, agent_lines, codex_recs=None, labels=None, prompts=None):
    """rows: ledger rows; main_lines: iterable of JSONL lines or None; agent_lines: {id: iterable}.
    labels: {label: [agent ids]} and prompts: {agent id: first prompt text} resolve rows whose
    agent_id is null (workflow and codex agents). Returns (per-row results, warnings, totals).
    totals: "session" = every main turn plus every agent transcript found for the session;
    "unattributed" = main turns outside all stage windows (before the first main row, or with
    an unparsable timestamp) plus agent transcripts not named in the ledger."""
    results, warnings = [], []
    totals = {"session": zero(), "unattributed": zero(), "main_turns": 0}
    labels, prompts = labels or {}, prompts or {}
    taken = {r.get("agent_id") for r in rows if r.get("agent_id")}
    for r in rows:
        if not r.get("agent_id") and r.get("kind") in ("workflow-agent", "codex-agent"):
            aid = resolve_label(r, labels, prompts, taken)
            if aid:
                r["agent_id"] = aid
                r["agent_id_from"] = "label"
                taken.add(aid)
    main_rows = [r for r in rows if r.get("kind") == "main"]
    main_acc = {id(r): zero() for r in main_rows}
    if main_lines is not None:
        turns_by_row, loose = defaultdict(list), []
        stamps = [(parse_ts(r.get("ts")), r) for r in main_rows]
        all_turns = list(iter_assistant(main_lines))
        for ts, m, u in all_turns:
            target = None
            if ts is not None:
                for rts, r in stamps:
                    if rts is not None and rts <= ts:
                        target = r
            (turns_by_row[id(target)] if target is not None else loose).append((ts, m, u))
        for r in main_rows:
            add_turns(main_acc[id(r)], turns_by_row.get(id(r), []), r.get("model"))
        add_turns(totals["unattributed"], loose)
        add_turns(totals["session"], all_turns)
        totals["main_turns"] = len(all_turns)
    elif main_rows:
        warnings.append("main session transcript not found; main rows show ? tokens")
    used = set()
    windows = codex_windows(rows, stops)
    codex_used = set()
    for r in rows:
        res = dict(r)
        res.setdefault("label", "")
        if r.get("kind") == "codex-agent":
            acc = zero()
            if codex_recs is None:
                warnings.append(f"codex row {r.get('stage')}/{r.get('step')}: {CODEX_USAGE} not found")
                res["known"] = False
            else:
                start, end = windows.get(id(r), (None, None))
                tier = CODEX_TIERS.get(r.get("model") or "", "")
                eff = r.get("effort") or ""
                cand = [x for x in codex_recs if start is not None and start <= x[0] <= end
                        and id(x) not in codex_used]
                mine = [x for x in cand if (not tier or x[1] == tier) and (not eff or x[2] == eff)]
                if not mine and not (tier or eff):
                    mine = cand
                for x in mine:
                    codex_used.add(id(x))
                priced = add_codex(acc, mine, r.get("model"))
                if not mine:
                    warnings.append(f"codex row {r.get('stage')}/{r.get('step')}: no usage record in its window")
                res["known"] = bool(mine) and priced
                if mine and not priced:
                    warnings.append(f"codex row {r.get('stage')}/{r.get('step')}: model without price (astra?)")
                for f in list(FIELDS) + ["miss", "turns"]:
                    totals["session"][f] += acc[f]
                totals["session"]["usd"] += acc["usd"]
            # The codex-proxy shim (haiku workflow agent) has its own transcript: add it to
            # the row so the stage cost includes the proxy, and keep it visible in shim_usd.
            shim = zero()
            aid = r.get("agent_id")
            if aid and aid in agent_lines:
                used.add(aid)
                add_turns(shim, iter_assistant(agent_lines[aid]), "claude-haiku-4-5")
                for f in list(FIELDS) + ["miss", "turns"]:
                    totals["session"][f] += shim[f]
                    acc[f] += shim[f]
                totals["session"]["usd"] += shim["usd"]
                acc["usd"] += shim["usd"]
            res.update(acc)
            res["shim_usd"] = shim["usd"]
            res["stop"] = stops.get(r.get("agent_id"))
            results.append(res)
            continue
        if r.get("kind") == "main":
            res.update(main_acc[id(r)])
            res["known"] = main_lines is not None
        else:
            aid = r.get("agent_id")
            acc = zero()
            if aid and aid in agent_lines:
                used.add(aid)
                model = add_turns(acc, iter_assistant(agent_lines[aid]), r.get("model"))
                res["model"] = res.get("model") or model
                res["known"] = True
                for f in list(FIELDS) + ["miss", "turns"]:
                    totals["session"][f] += acc[f]
                totals["session"]["usd"] += acc["usd"]
            else:
                warnings.append(f"agent {aid or '(none)'} ({r.get('stage')}/{r.get('step')}): transcript not found")
                res["known"] = False
            res.update(acc)
            res["stop"] = stops.get(aid)
        results.append(res)
    for aid, lines in agent_lines.items():
        if aid in used:
            continue
        acc = zero()
        add_turns(acc, iter_assistant(lines))
        for f in list(FIELDS) + ["miss", "turns"]:
            totals["session"][f] += acc[f]
            totals["unattributed"][f] += acc[f]
        totals["session"]["usd"] += acc["usd"]
        totals["unattributed"]["usd"] += acc["usd"]
    return results, warnings, totals


def group(results, key):
    g = defaultdict(zero)
    for r in results:
        k = key(r)
        for f in list(FIELDS) + ["miss", "turns"]:
            g[k][f] += r[f]
        g[k]["usd"] += r["usd"]
        g[k]["n"] = g[k].get("n", 0) + 1
    return g


def fmt_k(n):
    return f"{n/1000:.0f}K" if n else "0"


def print_table(title, g):
    print(f"\n{title}")
    print(f"{'key':34} {'n':>3} {'turns':>5} {'in':>7} {'out':>7} {'read':>8} {'w5':>7} {'w1':>7} {'miss':>4} {'$':>8}")
    for k, v in sorted(g.items(), key=lambda kv: -kv[1]["usd"]):
        print(f"{str(k)[:34]:34} {v.get('n', 0):3} {v['turns']:5} {fmt_k(v['input']):>7} {fmt_k(v['output']):>7} "
              f"{fmt_k(v['read']):>8} {fmt_k(v['w5']):>7} {fmt_k(v['w1']):>7} {v['miss']:4} {v['usd']:8.2f}")


def report(results, warnings, totals=None, as_json=False):
    if as_json:
        print(json.dumps({"rows": results, "warnings": warnings, "totals": totals}, indent=1, default=str))
        return
    print(f"{'stage':14} {'step':18} {'role':16} {'kind':14} {'model:effort':22} {'turns':>5} {'read':>8} {'w5':>7} {'miss':>4} {'$':>8}")
    for r in results:
        me = f"{(r.get('model') or '?').replace('claude-', '')}:{r.get('effort') or '?'}"
        tok = (r["turns"], fmt_k(r["read"]), fmt_k(r["w5"]), r["miss"], f"{r['usd']:.2f}") if r["known"] else ("?", "?", "?", "?", "?")
        print(f"{str(r.get('stage'))[:14]:14} {str(r.get('step'))[:18]:18} {str(r.get('role'))[:16]:16} "
              f"{str(r.get('kind'))[:14]:14} {me[:22]:22} {tok[0]:>5} {tok[1]:>8} {tok[2]:>7} {tok[3]:>4} {tok[4]:>8}")
    print_table("by stage", group(results, lambda r: r.get("stage")))
    print_table("by role", group(results, lambda r: r.get("role")))
    print_table("by kind", group(results, lambda r: r.get("kind")))
    print_table("by model+effort", group(results, lambda r: f"{r.get('model')}:{r.get('effort')}"))
    if any(r.get("codex") for r in results):
        print_table("by codex mode", group(results, lambda r: r.get("codex") or "claude"))
    tot = group(results, lambda r: "total")["total"]
    unknown = sum(1 for r in results if not r["known"])
    print(f"\nattributed: {tot['n']} rows, {tot['turns']} turns, ${tot['usd']:.2f}, misses {tot['miss']}"
          + (f", {unknown} rows without transcript" if unknown else ""))
    if totals and totals.get("main_turns"):
        s, u = totals["session"], totals["unattributed"]
        print(f"session total: {s['turns']} turns, read {fmt_k(s['read'])}, w5 {fmt_k(s['w5'])}, "
              f"w1 {fmt_k(s['w1'])}, misses {s['miss']}, ${s['usd']:.2f}")
        print(f"unattributed (main turns outside stages, agents not in ledger): {u['turns']} turns, ${u['usd']:.2f}")
    for w in warnings:
        print(f"warning: {w}", file=sys.stderr)


def newest_session(projects, rows):
    """Fallback: the main transcript with the newest mtime whose span covers the ledger."""
    stamps = [parse_ts(r.get("ts")) for r in rows if parse_ts(r.get("ts"))]
    cands = []
    for p in glob.glob(os.path.join(projects, "*", "*.jsonl")):
        mt = datetime.fromtimestamp(os.path.getmtime(p), timezone.utc)
        if not stamps or mt >= min(stamps):
            cands.append((mt, p))
    if not cands:
        return None
    return os.path.basename(max(cands)[1])[:-len(".jsonl")]


def run_dir(task_dir, projects, session_id=None):
    rows, stops = load_ledger(task_dir)
    warn0 = []
    if not session_id:
        sp = os.path.join(task_dir, "session")
        if os.path.isfile(sp):
            session_id = open(sp).read().strip()
    if not session_id:
        session_id = newest_session(projects, rows)
        warn0.append(f"no session file in {task_dir}; using newest transcript by mtime: {session_id}")
    main, agents = find_transcripts(projects, session_id, task_dir)
    main_lines = open(main) if main else None
    agent_lines = {k: open(v) for k, v in agents.items()}
    need_labels = any(not r.get("agent_id") and r.get("kind") in ("workflow-agent", "codex-agent") for r in rows)
    labels = label_index(projects, session_id) if need_labels else {}
    prompts = {k: first_prompt(v) for k, v in agents.items()} if need_labels else {}
    try:
        codex_recs = load_codex_usage() if any(r.get("kind") == "codex-agent" for r in rows) else None
        results, warnings, totals = compute(rows, stops, main_lines, agent_lines, codex_recs, labels, prompts)
        return results, warn0 + warnings, totals
    finally:
        if main_lines:
            main_lines.close()
        for fh in agent_lines.values():
            fh.close()


def all_runs(root, projects, as_json=False):
    out = []
    for d in sorted(glob.glob(os.path.join(root, "*"))):
        if not os.path.isfile(os.path.join(d, "ledger.jsonl")):
            continue
        results, _w, totals = run_dir(d, projects)
        rows, stops = load_ledger(d)
        stamps = [parse_ts(t) for t in [r.get("ts") for r in rows] + list(stops.values())]
        stamps = [t for t in stamps if t]
        wall = (max(stamps) - min(stamps)).total_seconds() / 60 if len(stamps) > 1 else 0
        mode = next((r.get("mode") for r in rows if r.get("mode")), "?")
        cls = next((r.get("class") for r in rows if r.get("class")), "?")
        cp = os.path.join(d, "class")
        if cls == "?" and os.path.isfile(cp):
            cls = open(cp).read().strip()
        out.append({"run": os.path.basename(d), "mode": mode, "class": cls,
                    "usd": round(sum(r["usd"] for r in results), 2),
                    "session_usd": round(totals["session"]["usd"], 2) if totals.get("main_turns") else None,
                    "wall_min": round(wall, 1),
                    "spawns": sum(1 for r in rows if r.get("kind") != "main"),
                    "misses": sum(r["miss"] for r in results),
                    "unknown": sum(1 for r in results if not r["known"])})
    if as_json:
        print(json.dumps(out, indent=1))
        return
    print(f"{'run':40} {'mode':9} {'class':>5} {'$':>8} {'session $':>9} {'wall min':>8} {'spawns':>6} {'miss':>4} {'?':>3}")
    for r in out:
        su = f"{r['session_usd']:9.2f}" if r["session_usd"] is not None else f"{'?':>9}"
        print(f"{r['run'][:40]:40} {r['mode']:9} {str(r['class']):>5} {r['usd']:8.2f} {su} {r['wall_min']:8.1f} "
              f"{r['spawns']:6} {r['misses']:4} {r['unknown']:3}")


def selftest():
    def entry(mid, ts, model, inp, out, read, w5, w1=0):
        return json.dumps({"type": "assistant", "timestamp": ts, "message": {
            "id": mid, "model": model, "usage": {"input_tokens": inp, "output_tokens": out,
            "cache_read_input_tokens": read,
            "cache_creation": {"ephemeral_5m_input_tokens": w5, "ephemeral_1h_input_tokens": w1}}}})
    rows = [
        {"ts": "2026-09-05T10:00:00Z", "stage": "research", "step": "framing", "role": "lead", "kind": "main",
         "model": "claude-fable-5-1", "effort": "high", "mode": "standard", "agent_id": None, "label": "main"},
        {"ts": "2026-09-05T10:05:00Z", "stage": "research", "step": "wave-1", "role": "researcher", "kind": "fork",
         "model": "claude-fable-5-1", "effort": "high", "mode": "standard", "agent_id": "a1", "label": "fab-hi-wave-1"},
        {"ts": "2026-09-05T10:20:00Z", "stage": "critic", "step": "critic", "role": "reviewer-debugger",
         "kind": "workflow-agent", "model": "claude-opus-5", "effort": "low", "mode": "standard", "agent_id": "a2",
         "label": "ops-lo-critic"},
        {"ts": "2026-09-05T10:30:00Z", "stage": "decision", "step": "contract", "role": "lead", "kind": "main",
         "model": "claude-fable-5-1", "effort": "high", "mode": "standard", "agent_id": None, "label": "main"},
        {"ts": "2026-09-05T10:40:00Z", "stage": "impl", "step": "pkg-1", "role": "author", "kind": "fork",
         "model": "claude-fable-5-1", "effort": "high", "mode": "standard", "agent_id": "missing", "label": "x"},
        {"ts": "2026-09-05T10:50:00Z", "stage": "final-review", "step": "codex", "role": "reviewer-debugger",
         "kind": "codex-agent", "model": "sol", "effort": "high", "mode": "standard", "codex": "+sol-luna",
         "agent_id": "a7", "label": "sol-hi-final-review"},
        {"ts": "2026-09-05T10:51:00Z", "stage": "final-review", "step": "codex-check", "role": "executor",
         "kind": "codex-agent", "model": "luna", "effort": "high", "mode": "standard", "codex": "+sol-luna",
         "agent_id": "a8", "label": "lun-hi-final-check"},   # overlapping window, other model
    ]
    stops = {"a1": "2026-09-05T10:09:00Z", "a7": "2026-09-05T10:58:00Z", "a8": "2026-09-05T10:57:00Z"}
    codex_recs = [
        (parse_ts("2026-09-05T10:45:00Z"), "gpt-5.6-luna", "high", 1000, 500, 10),   # before both windows
        (parse_ts("2026-09-05T10:52:00Z"), "gpt-5.6-sol", "high", 100_000, 60_000, 2_000),
        (parse_ts("2026-09-05T10:53:00Z"), "gpt-5.6-luna", "high", 20_000, 10_000, 500),  # inside sol window too
        (parse_ts("2026-09-05T10:55:00Z"), "gpt-5.6-sol", "high", 50_000, 40_000, 1_000),
        (parse_ts("2026-09-05T11:10:00Z"), "gpt-5.6-sol", "high", 9, 0, 9),           # after the stop mark
    ]
    main_lines = [
        entry("m0", "2026-09-05T09:50:00Z", "claude-fable-5-1", 10, 100, 50_000, 40_000),  # before first stage
        entry("m1", "2026-09-05T10:01:00Z", "claude-fable-5-1", 10, 500, 100_000, 5_000),
        entry("m1", "2026-09-05T10:01:00Z", "claude-fable-5-1", 10, 500, 100_000, 5_000),  # re-logged duplicate
        entry("m2", "2026-09-05T10:31:00Z", "claude-fable-5-1", 10, 800, 120_000, 2_000),
        entry("m3", "not-a-timestamp", "claude-fable-5-1", 10, 100, 120_000, 0),  # unparsable ts
    ]
    agents = {
        "a1": [entry("f1", "2026-09-05T10:06:00Z", "claude-fable-5-1", 5, 300, 100_000, 30_000),
               entry("f2", "2026-09-05T10:08:00Z", "claude-fable-5-1", 5, 300, 20_000, 60_000)],  # miss
        "a2": [entry("c1", "2026-09-05T10:21:00Z", "claude-opus-5", 4, 1000, 0, 13_000)],
        "a9": [entry("x1", "2026-09-05T10:50:00Z", "claude-fable-5-1", 4, 100, 0, 1_000)],  # not in ledger
    }
    res, warns, totals = compute(rows, stops, main_lines, agents, codex_recs)
    assert res[0]["turns"] == 1 and res[0]["output"] == 500, res[0]          # dedup + assignment
    exp_codex = (40_000 * 4e-6 + 60_000 * 4e-7 + 2_000 * 20e-6) + (10_000 * 4e-6 + 40_000 * 4e-7 + 1_000 * 20e-6)
    assert res[5]["turns"] == 2 and res[5]["known"] and abs(res[5]["usd"] - exp_codex) < 1e-9, res[5]
    exp_luna = 10_000 * 2e-7 + 10_000 * 2e-8 + 500 * 1.2e-6
    assert res[6]["turns"] == 1 and res[6]["known"] and abs(res[6]["usd"] - exp_luna) < 1e-9, res[6]  # model filter
    assert codex_price("gpt-6-astra") is None and codex_price("gpt-reserve") == CODEX_PRICES["gpt-reserve"]
    res_nofile, warns_nofile, _t = compute(rows, stops, main_lines, agents, None)
    assert res_nofile[5]["known"] is False and res_nofile[6]["known"] is False and any("proxy-usage" in w for w in warns_nofile), warns_nofile
    assert res[3]["turns"] == 1 and res[3]["read"] == 120_000, res[3]
    assert res[1]["miss"] == 1 and res[1]["stop"] == "2026-09-05T10:09:00Z", res[1]
    exp_a2 = 4 * 5e-6 + 1000 * 25e-6 + 13_000 * 6.25e-6
    assert abs(res[2]["usd"] - exp_a2) < 1e-9, (res[2]["usd"], exp_a2)
    assert res[4]["known"] is False and any("missing" in w for w in warns), warns
    assert totals["main_turns"] == 4, totals
    assert totals["unattributed"]["turns"] == 3, totals["unattributed"]  # m0, m3, a9
    attributed = sum(r["usd"] for r in res)
    assert abs(totals["session"]["usd"] - attributed - totals["unattributed"]["usd"]) < 1e-9, totals
    assert price_for("claude-fable-5-1[1m]")[1] == "claude-fable-5-1"
    assert price_for("claude-unknown")[1] is None
    buf, old = io.StringIO(), sys.stdout
    sys.stdout = buf
    try:
        report(res, [], totals)
    finally:
        sys.stdout = old
    text = buf.getvalue()
    assert "by stage" in text and "attributed: 7 rows" in text and "by codex mode" in text, text
    assert "session total: 11 turns" in text, text
    # Label resolution: workflow and codex rows without agent_id take the transcript by label
    # (scripts+journal index first, then the first prompt), never an id another row holds.
    rows_l = [dict(r) for r in rows]
    rows_l[2]["agent_id"] = None          # ops-lo-critic → a2 via the label index
    rows_l[5]["agent_id"] = None          # sol-hi-final-review → a7 via the prompt text
    agents_l = dict(agents)
    agents_l["a7"] = [entry("s1", "2026-09-05T10:52:00Z", "claude-haiku-4-5", 4, 50, 0, 2_000)]
    res_l, _w, _t = compute(rows_l, stops, main_lines, agents_l, codex_recs,
                            labels={"ops-lo-critic": ["a2"]},
                            prompts={"a7": "CODEX TARGET: sol-high  label sol-hi-final-review", "a9": "other"})
    assert res_l[2]["agent_id"] == "a2" and res_l[2]["agent_id_from"] == "label" and res_l[2]["turns"] == 1, res_l[2]
    assert res_l[5]["agent_id"] == "a7" and res_l[5]["shim_usd"] > 0, res_l[5]
    # Codex window: a record 90 s before the row joins; a retry after the next non-codex row
    # but before the next codex row of the same tier+effort joins the same row; a row
    # mis-stamped hours earlier is moved to the previous row's ts before windows are cut.
    rows_c = [
        {"ts": "2026-09-05T12:00:00Z", "stage": "critic", "step": "prompt", "role": "researcher", "kind": "fork",
         "model": "claude-opus-5", "effort": "low", "mode": "full", "agent_id": "b1", "label": "ops-lo-prompt"},
        {"ts": "2026-09-05T08:01:00Z", "stage": "critic", "step": "codex", "role": "reviewer-debugger",
         "kind": "codex-agent", "model": "sol", "effort": "medium", "mode": "full", "codex": "sol",
         "agent_id": None, "label": "sol-me-critic"},                                   # mis-stamped (08:01)
        {"ts": "2026-09-05T12:03:00Z", "stage": "critic", "step": "triage", "role": "reviewer-debugger", "kind": "fork",
         "model": "claude-opus-5", "effort": "low", "mode": "full", "agent_id": "b2", "label": "ops-lo-triage"},
        {"ts": "2026-09-05T12:10:00Z", "stage": "decision", "step": "codex", "role": "reviewer-debugger",
         "kind": "codex-agent", "model": "sol", "effort": "high", "mode": "full", "codex": "sol",
         "agent_id": None, "label": "sol-hi-decision"},
        {"ts": "2026-09-05T12:30:00Z", "stage": "closure", "step": "codex", "role": "reviewer-debugger",
         "kind": "codex-agent", "model": "sol", "effort": "medium", "mode": "full", "codex": "sol",
         "agent_id": None, "label": "sol-me-closure"},
        {"ts": "2026-09-05T12:35:00Z", "stage": "closure", "step": "report", "role": "author", "kind": "fork",
         "model": "claude-opus-5", "effort": "low", "mode": "full", "agent_id": "b3", "label": "ops-lo-report"},
    ]
    rows_c = fix_misstamps(rows_c)
    assert rows_c[1]["ts"] == "2026-09-05T12:00:00Z" and rows_c[1]["ts_raw"] == "2026-09-05T08:01:00Z", rows_c[1]
    recs_c = [
        (parse_ts("2026-09-05T11:58:40Z"), "gpt-5.6-sol", "medium", 1000, 0, 100),   # 80 s before the row: joins
        (parse_ts("2026-09-05T12:05:00Z"), "gpt-5.6-sol", "medium", 2000, 0, 100),   # retry after the triage fork: joins
        (parse_ts("2026-09-05T12:11:00Z"), "gpt-5.6-sol", "high", 3000, 0, 100),
        (parse_ts("2026-09-05T12:31:00Z"), "gpt-5.6-sol", "medium", 4000, 0, 100),   # next same-tier row
        (parse_ts("2026-09-05T13:30:00Z"), "gpt-5.6-sol", "high", 9999, 0, 9),       # another run, 55 min after the task end
    ]
    res_c, _w, _t = compute(rows_c, {}, None, {}, recs_c)
    assert res_c[1]["turns"] == 2 and res_c[1]["input"] == 3000, res_c[1]
    assert res_c[3]["turns"] == 1 and res_c[3]["input"] == 3000, res_c[3]          # tail cap keeps 13:30 out
    assert res_c[4]["turns"] == 1 and res_c[4]["input"] == 4000, res_c[4]
    hook_note = selftest_hook()
    print(f"selftest OK: 7 rows (2 codex, 3 runs), attributed ${attributed:.2f}, session ${totals['session']['usd']:.2f}, "
          f"unattributed {totals['unattributed']['turns']} turns, 1 miss, 1 unknown agent; "
          f"label resolution 2 rows; codex window 2+1+1 records, 1 mis-stamp; hook {hook_note}")


def selftest_hook():
    """The SubagentStop hook appends a stop row only for an agent id already in the ledger,
    and never twice. Returns a short note; skipped when the hook file is not beside the script."""
    hook = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "plugins", "session",
                        "hooks", "pipeline-subagent-stop.sh")
    if not os.path.isfile(hook):
        return "skipped (hook not found)"
    with tempfile.TemporaryDirectory() as home:
        cwd = os.path.join(home, "proj")
        enc = "".join(c if c.isalnum() or c == "-" else "-" for c in cwd)
        task = os.path.join(home, "task")
        os.makedirs(os.path.join(home, ".claude", "projects", enc, "pipeline"))
        os.makedirs(task)
        with open(os.path.join(home, ".claude", "projects", enc, "pipeline", "current"), "w") as fh:
            fh.write(task + "\n")
        with open(os.path.join(task, "ledger.jsonl"), "w") as fh:
            fh.write('{"ts":"2026-09-05T10:00:00Z","stage":"x","kind":"fork","agent_id":"aknown1","label":"l"}\n')
        env = dict(os.environ, HOME=home)
        for aid in ("aknown1", "aunknown", "aknown1"):
            subprocess.run(["sh", hook], input=json.dumps({"session_id": "s1", "cwd": cwd, "agent_id": aid}),
                           text=True, env=env, check=True)
        lines = open(os.path.join(task, "ledger.jsonl")).read().splitlines()
        stops_ = [json.loads(l) for l in lines if '"event"' in l]
        assert len(stops_) == 1 and stops_[0]["agent_id"] == "aknown1", lines
        assert open(os.path.join(task, "session")).read().strip() == "s1"
    return "1 stop row for 3 events (known, unknown, repeat)"


def main(argv):
    if "--selftest" in argv:
        selftest()
        return
    projects = os.path.expanduser("~/.claude/projects")
    as_json = "--json" in argv
    args = [a for a in argv if a != "--json"]
    if "--projects" in args:
        i = args.index("--projects")
        projects = args[i + 1]
        del args[i:i + 2]
    session_id = None
    if "--session" in args:
        i = args.index("--session")
        session_id = args[i + 1]
        del args[i:i + 2]
    if "--all-runs" in args:
        all_runs(args[args.index("--all-runs") + 1], projects, as_json)
        return
    if not args:
        print(__doc__)
        sys.exit(2)
    results, warnings, totals = run_dir(args[0], projects, session_id)
    if not results:
        print(f"no ledger rows in {args[0]}", file=sys.stderr)
        sys.exit(1)
    report(results, warnings, totals, as_json)


if __name__ == "__main__":
    main(sys.argv[1:])
