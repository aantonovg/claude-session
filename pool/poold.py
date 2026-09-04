#!/usr/bin/env python3
"""poold: a small daemon that manages a pool of warm Claude Code worker sessions.

A worker is an ordinary interactive `claude` session running in a tmux window.
The daemon starts workers, types tasks into their panes, and reports when the
result file appears. The requesting session never talks to a worker directly;
it only uses `poolctl` (a thin HTTP client for this daemon).

Layout on disk (one directory per pool):

    ~/.claude/pool/<pool-key>/pool.json     manifest: workers, tasks, config
    ~/.claude/pool/<pool-key>/tasks/        copies of submitted task files
    ~/.claude/pool/<pool-key>/results/      result files written by workers
    ~/.claude/pool/<pool-key>/park/         handoff files of parked workers
    ~/.claude/pool/<pool-key>/last-turn/    marks written by the worker hook

Pool keys:

    shared/<sha1(cwd)[:12]>     one pool per project directory (default)
    dedicated/<session-id>      one pool per owner session (explicit request)

Only the Python standard library is used. Run with `poold.py run [--port N]`.
"""

import argparse
import calendar
import hashlib
import glob
import json
import os
import re
import shlex
import subprocess
import sys
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

HOME = os.path.expanduser("~")
POOL_ROOT = os.path.join(HOME, ".claude", "pool")
PROJECTS_ROOT = os.path.join(HOME, ".claude", "projects")
DEFAULT_PORT = 19540

# Model aliases used in combo names (`opus-low`, `sonnet-medium`, ...).
# Overridden by ~/.claude/pool/models.json when present.
DEFAULT_MODELS = {
    "opus": "claude-opus-5[1m]",
    "sonnet": "claude-sonnet-5[1m]",
    "fable": "claude-fable-5-1[1m]",
    "haiku": "claude-haiku-4-5-20251001",
}
EFFORTS = ("low", "medium", "high", "xhigh", "max")

# Policy knobs (plan step 2). The policy thread reads them every tick.
CONFIG = {
    "max_workers": 15,          # ensure refuses (HTTP 409) above this many live workers
    "warm_after_min": 45,       # keep-warm ping after this much idle time ...
    "warm_until_min": 50,       # ... and before this much; later the worker is not pinged
    "cold_after_min": 60,       # idle longer than this = cold (cache gone)
    "cold_wake_max_tokens": 100_000,  # cold worker below this context is woken, else parked
    "day_end_compact_hour": 23,  # warm /compact (or /clear) at this local hour
    "owner_gone_park_min": 10,  # dedicated pool parked after the owner session is gone
    "ready_timeout_s": 120,     # how long to wait for the prompt after spawn
    "poll_s": 2,                # result polling interval
    "policy_tick_s": 60,        # policy thread period
    "trust_keys": ["Down", "Enter"],  # keys that accept the trust-folder dialog
    # Warm /compact for an idle worker whose context passed the family ceiling.
    # Cache reads are priced per token on every turn (opus $0.5/MTok, fable $0.25),
    # so a 150-200K opus context costs more per turn than a fresh 60K one.
    "compact_above_tokens": {"opus": 120_000, "fable": 200_000, "sonnet": 300_000, "haiku": 300_000},
    "compact_min_interval_min": 30,  # at most one ceiling compact per worker per this many minutes
}

# Prices per MTok (USD): input, output, cache read, 5m write, 1h write.
PRICES = {
    "claude-fable": (10.0, 50.0, 0.25, 12.5, 20.0),
    "claude-opus": (5.0, 25.0, 0.5, 6.25, 10.0),
    "claude-sonnet": (2.0, 10.0, 0.2, 2.5, 4.0),
    "claude-haiku": (1.0, 5.0, 0.1, 1.25, 2.0),
}

# The Stop hook that records a worker's last turn ships with the `session` plugin
# (plugins/session/hooks/pool-last-turn.sh) and is registered by the plugin itself;
# the daemon only checks that an installed copy exists.
LAST_TURN_HOOK_GLOB = os.path.join(HOME, ".claude", "plugins", "cache", "claude-session", "session", "*",
                                   "hooks", "pool-last-turn.sh")

BRIEFING = (
    "You are worker `{name}` of pool `{key}`, combo `{combo}`, roles `{roles}`. "
    "Work in forks mode: heavy work goes to fork subagents, any single wait stays "
    "under 3 minutes. A task arrives as one line `POOL TASK <id> <task file>`: read "
    "the file, do the task, write the result to `{results}/<id>.md` with the last "
    "line being the status `DONE` or `BLOCKED: <reason>`, then reply with exactly one "
    "line `DONE <id>`. "
    "Result file = status line, paths of the files you produced, at most 5 lines of "
    "summary; deliverables go into project files, never copied into the result. In "
    "the pane write nothing but tool calls and the final `DONE <id>` line. "
    "On `ping` answer exactly `pong`. Never run /model, /effort, "
    "/compact or create crons: the pool daemon does the keep-warm. Reply now with "
    "one line `READY {name}`."
)

PARK_INSTRUCTION = (
    "POOL PARK: write your handoff file to `{path}`: what you worked on today, the "
    "state of every task (id, result file, status), open questions, and the files "
    "you touched. Plain Markdown, no secrets. Reply with one line `PARKED {name}` "
    "when the file is written."
)

RESUME_NOTE = " Before anything else read your handoff file `{path}` and continue from it."

# Forks mode: the briefing sentence alone is ignored (benchmark 2026-09-04: four
# workers, zero forks), so the daemon loads the `session:forks` skill in the pane
# with the `pool` argument: the skill then creates no ping cron (the daemon keeps
# the worker warm).
FORKS_SKILL_COMMAND = "/session:forks pool"
FORKS_SETUP = (
    "Forks rules reminder: 3+ tool calls or 3K+ input always go to a fork; reviews and "
    "fixes are separate forks; you only write the result file and reply `DONE <id>`; "
    "no crons. "
    "Result file = status line, paths of the files you produced, at most 5 lines of "
    "summary; deliverables go into project files, never copied into the result. In "
    "the pane write nothing but tool calls and the final `DONE <id>` line. "
    "Reply READY."
)
FORKS_REMINDER = (
    " Forks rule still applies: 3+ tool calls or 3K+ input go to a fork subagent, "
    "reviews and fixes are separate forks, no crons."
)

# Re-sent after every /compact: the summary keeps the gist but loses the exact
# protocol lines (probe 3: the worker answered `t2 done.` instead of `DONE t2`).
PROTOCOL_REMINDER = (
    "POOL PROTOCOL reminder for worker `{name}`: a task arrives as `POOL TASK <id> "
    "<task file>`; write the result to `{results}/<id>.md` with the last line `DONE` "
    "or `BLOCKED: <reason>`, then reply with exactly one line `DONE <id>`. "
    "Result file = status line, paths of the files you produced, at most 5 lines of "
    "summary; deliverables go into project files, never copied into the result. In "
    "the pane write nothing but tool calls and the final `DONE <id>` line. "
    "On `ping` answer exactly `pong`. Reply now with one line `READY {name}`."
)


# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------

def now():
    return time.time()


def iso(ts):
    return time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(ts)) if ts else None


def encode_project_dir(cwd):
    """Claude Code stores transcripts under ~/.claude/projects/<encoded cwd>/.

    The encoding replaces every character that is not a letter or a digit
    with `-` (verified against existing directories: `/`, `.` and `_` all
    become `-`).
    """
    return re.sub(r"[^A-Za-z0-9]", "-", cwd)


def jsonl_path(cwd, session_id):
    return os.path.join(PROJECTS_ROOT, encode_project_dir(cwd), session_id + ".jsonl")


def price_for(model):
    for prefix, row in PRICES.items():
        if model and model.startswith(prefix):
            return row
    return PRICES["claude-opus"]


def jsonl_stats(path, day=None):
    """Context size and cost of a worker session from its transcript.

    Returns {"ctx": tokens of the last assistant turn (cache read + input +
    writes), "cost_today": USD for turns stamped with `day` (local date,
    default today), "turns": assistant turns, "misses": turns whose cache read
    dropped by more than 20K while writing more than 20K, "model": last model,
    "last_ts": mtime}. Entries are deduplicated by message id.
    """
    day = day or time.strftime("%Y-%m-%d")
    out = {"ctx": 0, "cost_today": 0.0, "turns": 0, "misses": 0, "model": None, "last_ts": None,
           "cost": {"read": 0.0, "w1h": 0.0, "w5m": 0.0, "input": 0.0, "output": 0.0, "total": 0.0}}
    if not path or not os.path.exists(path):
        return out
    out["last_ts"] = os.path.getmtime(path)
    seen = set()
    prev_read = None
    try:
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
                u = msg.get("usage") or {}
                cc = u.get("cache_creation") or {}
                inp = u.get("input_tokens", 0) or 0
                outp = u.get("output_tokens", 0) or 0
                read = u.get("cache_read_input_tokens", 0) or 0
                w5 = cc.get("ephemeral_5m_input_tokens", 0) or 0
                w1 = cc.get("ephemeral_1h_input_tokens", 0) or 0
                model = msg.get("model") or out["model"]
                out["model"] = model
                out["turns"] += 1
                out["ctx"] = read + inp + w5 + w1
                if prev_read is not None and read < prev_read - 20_000 and (w5 + w1) > 20_000:
                    out["misses"] += 1
                prev_read = read
                ts = d.get("timestamp") or ""
                if ts:
                    # Transcript timestamps are UTC ISO strings; the day policy is local.
                    utc = calendar.timegm(time.strptime(ts[:19], "%Y-%m-%dT%H:%M:%S"))
                    local_day = time.strftime("%Y-%m-%d", time.localtime(utc))
                else:
                    local_day = day
                if local_day == day:
                    p_in, p_out, p_rd, p_5, p_1 = price_for(model)
                    c = out["cost"]
                    c["read"] += read * p_rd / 1e6
                    c["w1h"] += w1 * p_1 / 1e6
                    c["w5m"] += w5 * p_5 / 1e6
                    c["input"] += inp * p_in / 1e6
                    c["output"] += outp * p_out / 1e6
                    c["total"] = c["read"] + c["w1h"] + c["w5m"] + c["input"] + c["output"]
                    out["cost_today"] = c["total"]
    except OSError:
        pass
    return out


_FORK_CACHE = {}


def fork_stats(jsonl_path):
    """Stats of the worker's fork subagents: transcripts under
    <project dir>/<session id>/subagents/**/*.jsonl. Per-file results are cached
    by mtime so the admin polling stays cheap. Returns {"forks", "fork_turns",
    "cost_forks", "misses_forks"} (cost for today only, same price table)."""
    out = {"forks": 0, "fork_turns": 0, "cost_forks": 0.0, "misses_forks": 0,
           "cost": {"read": 0.0, "w1h": 0.0, "w5m": 0.0, "input": 0.0, "output": 0.0, "total": 0.0}}
    if not jsonl_path:
        return out
    base = jsonl_path[:-6] if jsonl_path.endswith(".jsonl") else jsonl_path
    sub = os.path.join(base, "subagents")
    if not os.path.isdir(sub):
        return out
    day = time.strftime("%Y-%m-%d")
    for f in glob.glob(os.path.join(sub, "**", "*.jsonl"), recursive=True):
        try:
            mtime = os.path.getmtime(f)
        except OSError:
            continue
        key = (f, day)
        hit = _FORK_CACHE.get(key)
        if not hit or hit[0] != mtime:
            st = jsonl_stats(f, day)
            hit = (mtime, st)
            _FORK_CACHE[key] = hit
        st = hit[1]
        if not st["turns"]:
            continue
        out["forks"] += 1
        out["fork_turns"] += st["turns"]
        out["cost_forks"] += st["cost_today"]
        out["misses_forks"] += st["misses"]
        for k2, v in st["cost"].items():
            out["cost"][k2] += v
    return out


def load_models():
    path = os.path.join(POOL_ROOT, "models.json")
    models = dict(DEFAULT_MODELS)
    if os.path.exists(path):
        try:
            with open(path) as fh:
                models.update(json.load(fh))
        except (OSError, ValueError):
            pass
    return models


def parse_need(spec):
    """Parse `opus-low,sonnet-low,reviewer=opus-medium` into a list of dicts.

    Each entry: {"name": <worker name>, "role": <role or None>, "model": alias,
    "effort": level}. `name` is the combo for plain entries and the role for
    `role=combo` entries.
    """
    out = []
    for item in [s.strip() for s in spec.split(",") if s.strip()]:
        role = None
        combo = item
        if "=" in item:
            role, combo = [s.strip() for s in item.split("=", 1)]
        if "-" not in combo:
            raise ValueError(f"bad combo {combo!r}: expected <model>-<effort>")
        model, effort = combo.rsplit("-", 1)
        if effort not in EFFORTS:
            raise ValueError(f"bad effort {effort!r} in {combo!r}")
        out.append({"name": role or combo, "role": role, "model": model, "effort": effort})
    return out


def sh(args, check=True, timeout=30):
    return subprocess.run(args, capture_output=True, text=True, check=check, timeout=timeout)


def tmux(*args, check=True):
    return sh(["tmux", *args], check=check)


def pool_key_for(kind, cwd=None, owner=None):
    if kind == "dedicated":
        if not owner:
            raise ValueError("dedicated pool needs --owner <session-id>")
        return f"dedicated/{owner}"
    if not cwd:
        raise ValueError("shared pool needs --cwd")
    return "shared/" + hashlib.sha1(os.path.realpath(cwd).encode()).hexdigest()[:12]


def tmux_session_name(key):
    return "pool-" + key.replace("/", "-")


# --------------------------------------------------------------------------
# pool state
# --------------------------------------------------------------------------


def plog(msg):
    """Policy/action log line on stderr, same timestamp style as the HTTP access lines."""
    sys.stderr.write("%s - policy: %s\n" % (time.strftime("%d/%b/%Y %H:%M:%S"), msg))


class Pool:
    """One pool: a manifest on disk, a tmux session, workers and tasks."""

    def __init__(self, key, cwd=None, owner=None):
        self.key = key
        self.dir = os.path.join(POOL_ROOT, key)
        self.manifest_path = os.path.join(self.dir, "pool.json")
        self.lock = threading.RLock()
        self.data = {
            "key": key,
            "kind": key.split("/", 1)[0],
            "cwd": os.path.realpath(cwd) if cwd else None,
            "owner": owner,
            "created": now(),
            "config": dict(CONFIG),
            "workers": {},   # name -> worker dict
            "tasks": {},     # id -> task dict
            "seq": 0,
        }
        self._load()
        for sub in ("tasks", "results", "park", "last-turn"):
            os.makedirs(os.path.join(self.dir, sub), exist_ok=True)

    # ---- manifest ----
    def _load(self):
        if os.path.exists(self.manifest_path):
            with open(self.manifest_path) as fh:
                saved = json.load(fh)
            saved.setdefault("config", dict(CONFIG))
            self.data.update(saved)

    def save(self):
        with self.lock:
            os.makedirs(self.dir, exist_ok=True)
            tmp = self.manifest_path + ".tmp"
            with open(tmp, "w") as fh:
                json.dump(self.data, fh, indent=2)
            os.replace(tmp, self.manifest_path)

    @property
    def cwd(self):
        return self.data["cwd"]

    @property
    def workers(self):
        return self.data["workers"]

    @property
    def tasks(self):
        return self.data["tasks"]

    @property
    def tmux_session(self):
        return tmux_session_name(self.key)

    def sub(self, name):
        return os.path.join(self.dir, name)

    # ---- tmux ----
    def tmux_session_alive(self):
        return tmux("has-session", "-t", self.tmux_session, check=False).returncode == 0

    def open_window(self, name, command):
        """Open the worker window and return its pane id (`%N`).

        The first worker creates the tmux session; a fresh detached session
        gets an explicit size (probe 1: works on the Mac without an attached
        client). Later workers are new windows. The pane id is stored in the
        worker record so later commands do not depend on the window name
        (`automatic-rename` may change it).
        """
        if self.tmux_session_alive():
            r = tmux("new-window", "-P", "-F", "#{pane_id}", "-t", self.tmux_session, "-n", name,
                     "-c", self.cwd or HOME, command)
        else:
            r = tmux("new-session", "-d", "-P", "-F", "#{pane_id}", "-s", self.tmux_session,
                     "-x", "200", "-y", "50", "-c", self.cwd or HOME, "-n", name, command)
        return r.stdout.strip() or None

    def window_alive(self, name):
        r = tmux("list-windows", "-t", self.tmux_session, "-F", "#{window_name}", check=False)
        return r.returncode == 0 and name in r.stdout.split()

    def target(self, name):
        """tmux target of the worker: its pane id, or the window name for old records."""
        w = self.workers.get(name) or {}
        return w.get("pane") or f"{self.tmux_session}:{name}"

    def send(self, name, text, enter=True, second_enter=True):
        """Type `text` into the worker pane as one prompt.

        Multi-line pastes are not submitted reliably, so the text is one line.
        A second Enter after a short pause submits prompts that Claude Code
        leaves in the input box (seen with non-ASCII text).
        """
        try:
            tmux("send-keys", "-t", self.target(name), "-l", text)
        except subprocess.CalledProcessError:
            worker = self.workers.get(name)
            if worker and worker["state"] not in ("parked",):
                worker["state"] = "dead"
                worker["current"] = None
                plog(f"dead worker {self.key}/{name}: pane gone")
                self.save()
            raise RuntimeError(f"worker {name!r} pane is gone (state=dead); run `poolctl ensure` to respawn it")
        if enter:
            tmux("send-keys", "-t", self.target(name), "Enter")
            if second_enter:
                time.sleep(1)
                tmux("send-keys", "-t", self.target(name), "Enter")

    def capture(self, name, lines=40):
        r = tmux("capture-pane", "-p", "-t", self.target(name), "-S", f"-{lines}", check=False)
        return r.stdout if r.returncode == 0 else ""

    def wait_text(self, name, pattern, timeout=180):
        """Poll the pane until `pattern` (regex) shows up; True on match."""
        deadline = now() + timeout
        while now() < deadline:
            if re.search(pattern, self.capture(name, lines=60)):
                return True
            time.sleep(2)
        return False

    def forks_enabled(self):
        return bool(self.data.get("forks", True))

    def setup_forks(self, name):
        """Load the forks skill (pool variant, no cron) in the worker pane.

        Returns True when the worker confirmed with READY. A failure is not
        fatal: the worker still works, just inline (logged for the admin page).
        """
        self.send(name, FORKS_SKILL_COMMAND, second_enter=False)
        # Any reply counts: wait for the input prompt to come back, not for a phrase
        # (sonnet-low answered without the "Forks mode on" line in the first run).
        time.sleep(5)
        if not self.wait_ready(name, timeout=180):
            return False
        self.send(name, FORKS_SETUP)
        return self.wait_text(name, r"\bREADY\b", timeout=180)

    def wait_ready(self, name, timeout=None):
        """Poll the pane until the Claude Code input prompt is visible.

        A project directory Claude Code has not seen before shows the
        trust-folder dialog first; it is accepted with `trust_keys` (probe 1:
        Down + Enter). Pre-trusting through `~/.claude.json` is avoided because
        Claude Code rewrites that file itself.
        """
        timeout = timeout or self.data["config"]["ready_timeout_s"]
        deadline = now() + timeout
        trusted = False
        while now() < deadline:
            text = self.capture(name)
            if not trusted and re.search(r"trust", text, re.I) and "Enter" in text:
                for key in self.data["config"]["trust_keys"]:
                    tmux("send-keys", "-t", self.target(name), key)
                    time.sleep(0.5)
                trusted = True
                time.sleep(2)
                continue
            # The input box line starts with `>` or `❯` (possibly after a border
            # char; the prompt glyph depends on the theme), and the footer shows
            # "? for shortcuts" (probe 1, scenario 1).
            if re.search(r"^[│┃ ]*[>❯]\s", text, re.M) or "? for shortcuts" in text:
                return True
            time.sleep(1)
        return False

    # ---- last turn / idle ----
    def last_turn_dir(self):
        return self.sub("last-turn")

    def last_turn_ts(self, worker):
        """Time of the worker's last turn: hook mark, else transcript mtime, else daemon record."""
        mark = os.path.join(self.last_turn_dir(), worker["session_id"])
        candidates = [worker.get("last_turn") or 0]
        for path in (mark, worker.get("jsonl")):
            if path and os.path.exists(path):
                candidates.append(os.path.getmtime(path))
        return max(candidates)

    def idle_min(self, worker):
        return (now() - self.last_turn_ts(worker)) / 60.0

    def note_turn(self, worker):
        worker["last_turn"] = now()
        worker.pop("pinged_for", None)

    # ---- workers ----
    def unique_name(self, base):
        if base not in self.workers:
            return base
        i = 2
        while f"{base}-{i}" in self.workers:
            i += 1
        return f"{base}-{i}"

    def spawn(self, name, model_alias, effort, role=None, resume_note=""):
        models = load_models()
        if model_alias not in models:
            raise ValueError(f"unknown model alias {model_alias!r}; known: {sorted(models)}")
        full_id = models[model_alias]
        session_id = str(uuid.uuid4())
        # The model id must be quoted inside zsh: `[1m]` is a glob ("no matches found").
        cmd = f"claude --model {shlex.quote(full_id)} --effort {effort} --session-id {session_id}"
        # Per-pool extra claude flags (e.g. --add-dir/--settings/--mcp-config/--plugin-dir
        # for a corporate harness), stored in the manifest and applied to every spawn.
        extra = (self.data.get("extra_args") or "").strip()
        if extra:
            cmd += " " + extra
        # `zsh -lic` = interactive login shell, so ~/.zshrc exports (MCP tokens) load.
        # POOL_LAST_TURN_DIR reaches the Stop hook through the environment.
        # No `sleep N` in this string: the fork guard hook scans Bash commands for it.
        command = (f"env POOL_LAST_TURN_DIR={shlex.quote(self.last_turn_dir())} "
                   f"zsh -lic {shlex.quote(cmd)}")
        pane = self.open_window(name, command)
        worker = {
            "name": name,
            "role": role,
            "model": model_alias,
            "model_id": full_id,
            "effort": effort,
            "combo": f"{model_alias}-{effort}",
            "session_id": session_id,
            "pane": pane,
            "jsonl": jsonl_path(self.cwd or HOME, session_id),
            "state": "starting",
            "spawned": now(),
            "last_turn": None,
            "queue": [],
            "current": None,
        }
        self.workers[name] = worker
        self.save()
        if not self.wait_ready(name):
            # Roll back: no half-started worker stays in the manifest or in tmux.
            tmux("kill-window", "-t", self.target(name), check=False)
            del self.workers[name]
            self.save()
            raise RuntimeError(
                f"worker {name}: prompt not ready after {self.data['config']['ready_timeout_s']}s; window closed")
        briefing = BRIEFING.format(
            name=name, key=self.key, combo=worker["combo"], roles=role or "any",
            results=self.sub("results"),
        ) + resume_note
        self.send(name, briefing)
        self.wait_text(name, rf"READY {re.escape(name)}", timeout=180)
        if self.forks_enabled():
            worker["forks"] = self.setup_forks(name)
        worker["state"] = "warm"
        self.note_turn(worker)
        self.save()
        return worker

    def live_workers(self):
        return [w for w in self.workers.values() if w["state"] not in ("parked", "error", "dead")]

    def ensure(self, need, registry=None):
        """Make sure a worker exists for every entry of `need`; return them all.

        Policies applied here: the account-wide worker limit (LimitError →
        HTTP 409), waking or replacing cold workers, and a `suggest` hint when a
        worker's queue is longer than one.
        """
        result = []
        with self.lock:
            for entry in need:
                existing = self.workers.get(entry["name"])
                if existing and existing["state"] not in ("error", "dead") and self.window_alive(entry["name"]):
                    if existing["state"] == "cold":
                        plog(f"ensure {self.key}/{entry['name']}: cold worker, wake or replace")
                        existing = self.wake_or_replace(existing)
                    result.append(existing)
                    continue
                if existing and existing["state"] == "parked":
                    plog(f"ensure {self.key}/{entry['name']}: resume parked worker")
                    result.extend(self._resume_worker(entry["name"]) or [])
                    continue
                if existing:
                    # Window gone: forget the stale record and respawn under the same name.
                    plog(f"ensure {self.key}/{entry['name']}: window gone (state={existing['state']}), respawn")
                    del self.workers[entry["name"]]
                self.check_limit(registry)
                name = self.unique_name(entry["name"])
                result.append(self.spawn(name, entry["model"], entry["effort"], entry["role"]))
        out = []
        for w in result:
            pub = self.public_worker(w)
            if len(w.get("queue", [])) > 1:
                pub["suggest"] = self.unique_name(w["name"])
            out.append(pub)
        return out

    def check_limit(self, registry):
        limit = self.data["config"]["max_workers"]
        total = sum(len(p.live_workers()) for p in (registry.pools.values() if registry else [self]))
        if total >= limit:
            raise LimitError(f"worker limit reached ({total}/{limit}); park something first")

    def wake_or_replace(self, worker):
        """A cold worker is pinged back when its context is small, else parked and replaced."""
        stats = jsonl_stats(worker.get("jsonl"))
        if stats["ctx"] < self.data["config"]["cold_wake_max_tokens"]:
            self.send(worker["name"], "ping", second_enter=False)
            worker["state"] = "warm"
            self.note_turn(worker)
            self.save()
            return worker
        name = worker["name"]
        self.park([name])
        return (self._resume_worker(name) or [worker])[0]

    def public_worker(self, w):
        pub = {k: v for k, v in w.items()}
        stats = jsonl_stats(w.get("jsonl"))
        pub["ctx"] = stats["ctx"]
        pub["cost_today"] = round(stats["cost_today"], 4)
        pub["misses"] = stats["misses"]
        pub["turns"] = stats["turns"]
        fk = fork_stats(w.get("jsonl"))
        pub["forks"] = fk["forks"]
        pub["fork_turns"] = fk["fork_turns"]
        pub["cost_forks"] = round(fk["cost_forks"], 4)
        pub["misses_forks"] = fk["misses_forks"]
        pub["cost_total"] = round(stats["cost_today"] + fk["cost_forks"], 4)
        pub["cost"] = {k2: round(stats["cost"][k2] + fk["cost"][k2], 4) for k2 in stats["cost"]}
        pub["idle_min"] = round(self.idle_min(w), 1) if w["state"] not in ("parked", "error", "dead") else None
        pub["queue_len"] = len(w.get("queue", []))
        pub["ctx_ceiling"] = self.ceiling_for(w)
        pub["ceiling_compact_at"] = w.get("ceiling_compact_at")
        return pub

    # ---- tasks ----
    def submit(self, worker_name, task_file):
        with self.lock:
            worker = self.workers.get(worker_name)
            if not worker:
                raise ValueError(f"no worker {worker_name!r} in pool {self.key}")
            with open(task_file, "rb") as fh:
                content = fh.read()
            self.data["seq"] += 1
            digest = hashlib.sha1(content).hexdigest()[:8]
            # Prefix with the pool's short key: ids must be unique across pools because
            # /wait resolves a task by id (seq restarts per pool, hashes repeat per file).
            task_id = f"{self.key.split('/')[-1][:6]}-t{self.data['seq']}-{digest}"
            dest = os.path.join(self.sub("tasks"), f"{task_id}.md")
            with open(dest, "wb") as fh:
                fh.write(content)
            task = {
                "id": task_id,
                "worker": worker_name,
                "file": dest,
                "source": os.path.realpath(task_file),
                "result": os.path.join(self.sub("results"), f"{task_id}.md"),
                "state": "queued",
                "submitted": now(),
                "started": None,
                "finished": None,
                "last_line": None,
            }
            self.tasks[task_id] = task
            worker["queue"].append(task_id)
            self.save()
            self._dispatch(worker_name)
            return task

    def _dispatch(self, worker_name):
        """Type the next queued task into the pane if the worker is free."""
        worker = self.workers[worker_name]
        if worker["current"] or not worker["queue"]:
            return
        task_id = worker["queue"].pop(0)
        task = self.tasks[task_id]
        self.send(worker_name, f"POOL TASK {task_id} {task['file']}")
        task["state"] = "running"
        task["started"] = now()
        worker["current"] = task_id
        worker["state"] = "busy"
        self.note_turn(worker)
        self.save()

    def _check_task(self, task):
        """Return True when the result file is complete (last line DONE/BLOCKED)."""
        if task["state"] in ("done", "blocked"):
            return True
        path = task["result"]
        if not os.path.exists(path):
            return False
        try:
            with open(path) as fh:
                lines = [ln.strip() for ln in fh if ln.strip()]
        except OSError:
            return False
        if not lines:
            return False
        last = lines[-1]
        if last.startswith("DONE"):
            task["state"] = "done"
        elif last.startswith("BLOCKED"):
            task["state"] = "blocked"
        else:
            return False
        task["last_line"] = last
        task["finished"] = now()
        with self.lock:
            worker = self.workers.get(task["worker"])
            if worker and worker["current"] == task["id"]:
                worker["current"] = None
                worker["state"] = "warm"
                self.note_turn(worker)
                self.save()
                self._dispatch(task["worker"])
            else:
                self.save()
        return True

    def wait(self, task_id, timeout):
        task = self.tasks.get(task_id)
        if not task:
            raise ValueError(f"no task {task_id!r} in pool {self.key}")
        deadline = now() + timeout
        poll = self.data["config"]["poll_s"]
        while True:
            if self._check_task(task):
                return task
            if now() >= deadline:
                return task
            time.sleep(poll)

    def poll_all(self):
        for task in list(self.tasks.values()):
            if task["state"] == "running":
                self._check_task(task)

    # ---- park / resume / compact ----
    def park(self, names=None, timeout=300):
        """Ask each worker to write its handoff file, then close its window."""
        parked = []
        with self.lock:
            targets = names or list(self.workers)
            for name in targets:
                worker = self.workers.get(name)
                if not worker:
                    continue
                path = os.path.join(self.sub("park"), f"{name}.md")
                if self.window_alive(name):
                    self.send(name, PARK_INSTRUCTION.format(path=path, name=name))
                    deadline = now() + timeout
                    while now() < deadline and not os.path.exists(path):
                        time.sleep(2)
                    tmux("kill-window", "-t", self.target(name), check=False)
                worker["state"] = "parked"
                worker["park_file"] = path if os.path.exists(path) else None
                worker["current"] = None
                parked.append(self.public_worker(worker))
            self.save()
        return parked

    def _resume_worker(self, name):
        old = self.workers.get(name)
        if not old or old["state"] != "parked":
            return []
        note = RESUME_NOTE.format(path=old.get("park_file")) if old.get("park_file") else ""
        del self.workers[name]
        w = self.spawn(name, old["model"], old["effort"], old.get("role"), resume_note=note)
        w["queue"] = old.get("queue", [])
        self.save()
        self._dispatch(name)
        return [w]

    def resume(self, names=None):
        """Re-spawn parked workers with the same combo; they read their handoff file."""
        resumed = []
        with self.lock:
            targets = names or [n for n, w in self.workers.items() if w["state"] == "parked"]
            for name in targets:
                resumed.extend(self.public_worker(w) for w in self._resume_worker(name))
        return resumed

    def compact(self, names=None, command="/compact", mark_cold=False):
        """Type `/compact` (or `/clear`) into every idle worker, then re-send the protocol.

        Warm compact is cheap (≈ $0.1-0.5). After it the summary keeps the gist
        but not the exact protocol lines, so PROTOCOL_REMINDER follows. With
        `mark_cold` the worker is left cold on purpose (day end: no more pings).
        """
        done = []
        with self.lock:
            for name in names or list(self.workers):
                w = self.workers.get(name)
                if w and w["state"] in ("warm", "cold") and self.window_alive(name):
                    self.send(name, command, second_enter=False)
                    done.append(name)
            for name in done:
                # Compact takes a while; wait for the prompt, then remind the protocol.
                self.wait_ready(name, timeout=240)
                time.sleep(2)
                reminder = PROTOCOL_REMINDER.format(name=name, results=self.sub("results"))
                if self.forks_enabled():
                    reminder += FORKS_REMINDER
                self.send(name, reminder)
                w = self.workers[name]
                w["state"] = "cold" if mark_cold else "warm"
                self.note_turn(w)
            self.save()
        return done

    # ---- policies (called by the policy thread every tick) ----
    def tick(self, registry):
        cfg = self.data["config"]
        with self.lock:
            self.poll_all()
            self._keep_warm(cfg)
            self._ceiling_compact(cfg)
            self._day_end(cfg)
            self._owner_check(cfg)

    def ceiling_for(self, w):
        """Context ceiling (tokens) for a worker by model family, from CONFIG."""
        table = CONFIG["compact_above_tokens"]
        model = (w.get("model") or "").lower()
        for fam, limit in table.items():
            if fam in model:
                return limit
        return table["opus"]

    def _ceiling_compact(self, cfg):
        """Warm /compact for an idle warm worker whose context passed its ceiling.

        Runs at most once per `compact_min_interval_min` per worker. The compact
        path re-sends the protocol reminder, so the worker keeps the exact lines.
        """
        interval = CONFIG["compact_min_interval_min"] * 60
        for w in list(self.workers.values()):
            if w["state"] != "warm" or w.get("queue"):
                continue
            ctx = jsonl_stats(w.get("jsonl"))["ctx"]
            limit = self.ceiling_for(w)
            if ctx <= limit:
                continue
            if now() - (w.get("ceiling_compact_at") or 0) < interval:
                continue
            plog(f"ceiling compact {self.key}/{w['name']}: ctx {ctx} > {limit}")
            w["ceiling_compact_at"] = now()
            self.compact([w["name"]])

    def _keep_warm(self, cfg):
        """Ping idle warm workers 45-50 min after their last turn; older ones go cold."""
        for w in list(self.workers.values()):
            if w["state"] not in ("warm", "busy"):
                continue
            if not self.window_alive(w["name"]):
                w["state"] = "error"
                plog(f"dead worker {self.key}/{w['name']}: window gone, state=error")
                continue
            if w["state"] != "warm":
                # A busy worker is mid-task: its turns keep the cache warm and it
                # must never be marked cold or pinged while working.
                continue
            idle = self.idle_min(w)
            if idle >= cfg["cold_after_min"]:
                w["state"] = "cold"
                plog(f"cold {self.key}/{w['name']}: idle {idle:.0f} min")
                w.pop("pinged_for", None)
                continue
            last = self.last_turn_ts(w)
            if cfg["warm_after_min"] <= idle < cfg["warm_until_min"] and w.get("pinged_for") != last:
                plog(f"keep-warm ping {self.key}/{w['name']}: idle {idle:.0f} min")
                self.send(w["name"], "ping", second_enter=False)
                w["pinged_for"] = last
                w["pinged_at"] = now()
        self.save()

    def _day_end(self, cfg):
        """Once per local day at `day_end_compact_hour`: compact (or clear) idle workers."""
        today = time.strftime("%Y-%m-%d")
        if time.localtime().tm_hour < cfg["day_end_compact_hour"] or self.data.get("day_end_done") == today:
            return
        idle = [n for n, w in self.workers.items() if w["state"] == "warm"]
        self.data["day_end_done"] = today
        if idle:
            cmd = "/clear" if self.data.get("reset_at_day_end") else "/compact"
            plog(f"day-end {cmd} {self.key}: workers {', '.join(idle)}")
            self.compact(idle, command=cmd, mark_cold=True)
        self.save()

    def owner_alive(self):
        owner = self.data.get("owner")
        if not owner:
            return True
        r = sh(["pgrep", "-f", "--", f"--session-id {owner}"], check=False)
        if r.returncode == 0 and r.stdout.strip():
            return True
        # Sessions started without the flag: the id shows up in the process environment.
        r = sh(["ps", "-axeww", "-o", "command"], check=False)
        return owner in r.stdout

    def _owner_check(self, cfg):
        """A dedicated pool is parked `owner_gone_park_min` after its owner session is gone."""
        if self.data["kind"] != "dedicated" or not self.live_workers():
            return
        if self.owner_alive():
            self.data.pop("owner_gone_since", None)
            return
        since = self.data.setdefault("owner_gone_since", now())
        if (now() - since) / 60.0 >= cfg["owner_gone_park_min"]:
            plog(f"owner gone {self.key}: parking pool")
            self.park()
            self.data.pop("owner_gone_since", None)
        self.save()

    def status(self):
        self.poll_all()
        return {
            "key": self.key,
            "kind": self.data["kind"],
            "cwd": self.cwd,
            "owner": self.data["owner"],
            "owner_alive": self.owner_alive() if self.data["kind"] == "dedicated" else None,
            "reset_at_day_end": bool(self.data.get("reset_at_day_end")),
            "forks": self.forks_enabled(),
            "extra_args": self.data.get("extra_args") or "",
            "tmux": self.tmux_session,
            "workers": [self.public_worker(w) for w in self.workers.values()],
            "tasks": list(self.tasks.values()),
        }


class NotFound(ValueError):
    """Unknown pool, worker or task: answered with HTTP 404, never a fallback."""


class LimitError(RuntimeError):
    """Raised by ensure when the account-wide worker limit is reached (HTTP 409)."""


# --------------------------------------------------------------------------
# registry
# --------------------------------------------------------------------------

class Registry:
    def __init__(self):
        self.pools = {}
        self.lock = threading.Lock()
        self._load_all()

    def _load_all(self):
        for kind in ("shared", "dedicated"):
            base = os.path.join(POOL_ROOT, kind)
            if not os.path.isdir(base):
                continue
            for name in os.listdir(base):
                if os.path.exists(os.path.join(base, name, "pool.json")):
                    key = f"{kind}/{name}"
                    self.pools[key] = Pool(key)

    def get(self, kind=None, cwd=None, owner=None, key=None, create=False):
        with self.lock:
            if key is None:
                key = pool_key_for(kind or "shared", cwd=cwd, owner=owner)
            pool = self.pools.get(key)
            if pool is None:
                if not create:
                    raise NotFound(f"no pool {key!r}")
                pool = Pool(key, cwd=cwd, owner=owner)
                pool.save()
                self.pools[key] = pool
            elif cwd and not pool.cwd:
                pool.data["cwd"] = os.path.realpath(cwd)
                pool.save()
            return pool

    def find_task(self, task_id, key=None):
        """Pool holding `task_id`; `key` (when given) scopes the lookup to one pool."""
        if key:
            pool = self.pools.get(key)
            if pool is None:
                raise NotFound(f"no pool {key!r}")
            if task_id not in pool.tasks:
                raise NotFound(f"no task {task_id!r} in pool {key!r}")
            return pool
        hits = [pool for pool in self.pools.values() if task_id in pool.tasks]
        if len(hits) == 1:
            return hits[0]
        if not hits:
            raise NotFound(f"no task {task_id!r}")
        raise ValueError(f"task id {task_id!r} exists in several pools; pass --key")

    def status(self, key=None):
        pools = [self.pools[key]] if key else list(self.pools.values())
        return {"config": CONFIG, "live_workers": sum(len(p.live_workers()) for p in self.pools.values()),
                "pools": [p.status() for p in pools]}

    def policy_loop(self):
        """Background thread: keep-warm, day end, owner liveness for every pool."""
        while True:
            time.sleep(CONFIG["policy_tick_s"])
            for pool in list(self.pools.values()):
                try:
                    pool.tick(self)
                except Exception as exc:  # one bad pool must not stop the loop
                    sys.stderr.write(f"policy tick {pool.key}: {exc!r}\n")


REGISTRY = None


# --------------------------------------------------------------------------
# HTTP API
# --------------------------------------------------------------------------

# ---- admin page (GET /): one self-contained HTML file, polls /status every 10 s ----
ADMIN_HTML = """<!doctype html>
<html><head><meta charset="utf-8"><title>poold</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<style>
:root{--bg:#fafaf8;--fg:#1c1c1a;--mut:#6b6b66;--line:#ddd;--card:#fff;--warm:#2a7d3f;--busy:#b26a00;--cold:#3a6ea5;--bad:#b3261e}
@media(prefers-color-scheme:dark){:root{--bg:#161615;--fg:#e8e6e1;--mut:#9a9994;--line:#333;--card:#1f1f1e;--warm:#6fcf8a;--busy:#f0b354;--cold:#8ab8ea;--bad:#f28b82}}
body{margin:0;padding:20px;background:var(--bg);color:var(--fg);font:14px/1.45 -apple-system,system-ui,sans-serif}
h1{font-size:18px;margin:0 0 4px}h2{font-size:15px;margin:22px 0 6px}
.mut{color:var(--mut)}.card{background:var(--card);border:1px solid var(--line);border-radius:8px;padding:12px 14px;margin:12px 0}
table{border-collapse:collapse;width:100%;font-variant-numeric:tabular-nums}
th,td{text-align:left;padding:4px 8px;border-bottom:1px solid var(--line);white-space:nowrap}
th{font-weight:600;color:var(--mut)}td.n,th.n{text-align:right}
.wrap{overflow-x:auto}.st-warm{color:var(--warm)}.st-busy{color:var(--busy)}.st-cold{color:var(--cold)}
.st-error,.st-blocked{color:var(--bad)}.st-parked,.st-queued{color:var(--mut)}.st-done{color:var(--warm)}.st-running{color:var(--busy)}
tfoot td{font-weight:600;border-top:2px solid var(--line)}
</style></head><body>
<h1>poold</h1><div class="mut" id="hdr">loading…</div>
<div id="pools"></div>
<div class="card"><h2 style="margin-top:0">Totals per model (today)</h2><div class="wrap" id="models"></div></div>
<script>
const esc=s=>String(s==null?"":s).replace(/[&<>]/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;"}[c]));
const k=n=>n==null?"":(n/1000).toFixed(n>=100000?0:1)+"K";
const usd=n=>n==null?"":"$"+Number(n).toFixed(2);
const age=m=>m==null?"":(m<60?Math.round(m)+"m":(m/60).toFixed(1)+"h");
const dur=(a,b)=>{if(!a)return"";const e=(b||Date.now()/1000)-a;return e<90?Math.round(e)+"s":Math.round(e/60)+"m";};
const st=s=>'<span class="st-'+esc(s)+'">'+esc(s)+'</span>';
function stage(t){const f=(t.source||t.file||"").split("/").pop().replace(/\\.md$/,"");const p=f.split("-");return p.length>=3?p.slice(1,-1).join("-"):"";}
function workers(ws){let h='<div class="wrap"><table><thead><tr><th>worker</th><th>model</th><th>effort</th><th>role</th><th class="n">ctx</th><th>state</th><th class="n">last turn</th><th class="n">$ read</th><th class="n">$ w1h</th><th class="n">$ w5m</th><th class="n">$ in</th><th class="n">$ out</th><th class="n">$ total</th><th class="n">forks</th><th class="n">misses</th><th class="n">turns</th><th class="n">queue</th><th>current</th></tr></thead><tbody>';
 const T={read:0,w1h:0,w5m:0,input:0,output:0,total:0};let forks=0,ctx=0;
 for(const w of ws){const c=w.cost||{};for(const q in T)T[q]+=c[q]||0;forks+=w.forks||0;ctx+=w.ctx||0;
  h+='<tr><td>'+esc(w.name)+'</td><td>'+esc(w.model_id||w.model)+'</td><td>'+esc(w.effort)+'</td><td>'+esc(w.role||"")+'</td><td class="n">'+k(w.ctx)+'</td><td>'+st(w.state)+'</td><td class="n">'+age(w.idle_min)+'</td><td class="n">'+usd((w.cost||{}).read)+'</td><td class="n">'+usd((w.cost||{}).w1h)+'</td><td class="n">'+usd((w.cost||{}).w5m)+'</td><td class="n">'+usd((w.cost||{}).input)+'</td><td class="n">'+usd((w.cost||{}).output)+'</td><td class="n"><b>'+usd((w.cost||{}).total)+'</b></td><td class="n">'+esc(w.forks||0)+'</td><td class="n">'+esc(w.misses)+(w.misses_forks?'+'+esc(w.misses_forks):'')+'</td><td class="n">'+esc(w.turns)+'</td><td class="n">'+esc(w.queue_len)+'</td><td>'+esc(w.current||"")+'</td></tr>';}
 h+='</tbody><tfoot><tr><td>'+ws.length+' workers</td><td></td><td></td><td></td><td class="n">'+k(ctx)+'</td><td></td><td></td><td class="n">'+usd(T.read)+'</td><td class="n">'+usd(T.w1h)+'</td><td class="n">'+usd(T.w5m)+'</td><td class="n">'+usd(T.input)+'</td><td class="n">'+usd(T.output)+'</td><td class="n"><b>'+usd(T.total)+'</b></td><td class="n">'+forks+'</td><td colspan="4"></td></tr></tfoot></table></div>';return h;}
function tasks(ts){if(!ts.length)return'<div class="mut">no tasks</div>';
 ts=[...ts].sort((a,b)=>(b.submitted||0)-(a.submitted||0));
 let h='<div class="wrap"><table><thead><tr><th>task</th><th>worker</th><th>stage</th><th>status</th><th class="n">duration</th><th>last line</th></tr></thead><tbody>';
 for(const t of ts)h+='<tr><td>'+esc(t.id)+'</td><td>'+esc(t.worker)+'</td><td>'+esc(stage(t))+'</td><td>'+st(t.state)+'</td><td class="n">'+dur(t.started||t.submitted,t.finished)+'</td><td class="mut">'+esc((t.last_line||"").slice(0,80))+'</td></tr>';
 return h+'</tbody></table></div>';}
function render(d){
 document.getElementById("hdr").textContent="live workers "+d.live_workers+" / "+(d.config||{}).max_workers+" · "+new Date().toLocaleTimeString();
 let ph="";const per={};
 for(const p of d.pools||[]){
  for(const w of p.workers){const m=w.model_id||w.model||"?";per[m]=per[m]||{n:0,c:{read:0,w1h:0,w5m:0,input:0,output:0,total:0},turns:0,miss:0};per[m].n++;const cc=w.cost||{};for(const q in per[m].c)per[m].c[q]+=cc[q]||0;per[m].turns+=(w.turns||0)+(w.fork_turns||0);per[m].miss+=(w.misses||0)+(w.misses_forks||0);}
  const own=p.kind==="dedicated"?' · owner '+esc(p.owner)+(p.owner_alive===false?' <span class="st-error">gone</span>':' alive'):'';
  ph+='<div class="card"><h2 style="margin-top:0">'+esc(p.key)+'</h2><div class="mut">'+esc(p.cwd||"")+' · tmux '+esc(p.tmux)+own+(p.reset_at_day_end?' · reset at day end':'')+'</div>'+workers(p.workers)+'<h2>tasks</h2>'+tasks(p.tasks)+'</div>';}
 document.getElementById("pools").innerHTML=ph||'<div class="card mut">no pools</div>';
 let mh='<table><thead><tr><th>model</th><th class="n">workers</th><th class="n">turns</th><th class="n">misses</th><th class="n">$ read</th><th class="n">$ w1h</th><th class="n">$ w5m</th><th class="n">$ in</th><th class="n">$ out</th><th class="n">$ total</th></tr></thead><tbody>';const TT={read:0,w1h:0,w5m:0,input:0,output:0,total:0};
 for(const m of Object.keys(per).sort()){const v=per[m];for(const q in TT)TT[q]+=v.c[q];mh+='<tr><td>'+esc(m)+'</td><td class="n">'+v.n+'</td><td class="n">'+v.turns+'</td><td class="n">'+v.miss+'</td><td class="n">'+usd(v.c.read)+'</td><td class="n">'+usd(v.c.w1h)+'</td><td class="n">'+usd(v.c.w5m)+'</td><td class="n">'+usd(v.c.input)+'</td><td class="n">'+usd(v.c.output)+'</td><td class="n"><b>'+usd(v.c.total)+'</b></td></tr>';}
 document.getElementById("models").innerHTML=mh+'</tbody><tfoot><tr><td>total</td><td colspan="3"></td><td class="n">'+usd(TT.read)+'</td><td class="n">'+usd(TT.w1h)+'</td><td class="n">'+usd(TT.w5m)+'</td><td class="n">'+usd(TT.input)+'</td><td class="n">'+usd(TT.output)+'</td><td class="n"><b>'+usd(TT.total)+'</b></td></tr></tfoot></table>';}
async function tick(){try{const r=await fetch("/status");render(await r.json());}catch(e){document.getElementById("hdr").textContent="poold unreachable: "+e;}}
tick();setInterval(tick,10000);
</script></body></html>
"""


class Handler(BaseHTTPRequestHandler):
    server_version = "poold/0.1"

    def log_message(self, fmt, *args):
        sys.stderr.write("%s - %s\n" % (self.log_date_time_string(), fmt % args))

    def _json(self, code, obj):
        body = json.dumps(obj, indent=2).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _body(self):
        n = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(n) if n else b"{}"
        return json.loads(raw or b"{}")

    def do_GET(self):
        url = urlparse(self.path)
        q = {k: v[0] for k, v in parse_qs(url.query).items()}
        try:
            if url.path == "/status":
                self._json(200, REGISTRY.status(q.get("key")))
            elif url.path == "/":
                body = ADMIN_HTML.encode()
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            else:
                self._json(404, {"error": "unknown path"})
        except Exception as exc:  # report to the client, keep the daemon alive
            self._json(500, {"error": str(exc)})

    def do_POST(self):
        url = urlparse(self.path)
        try:
            req = self._body()
            handler = {
                "/ensure": self.op_ensure,
                "/submit": self.op_submit,
                "/wait": self.op_wait,
                "/park": self.op_park,
                "/resume": self.op_resume,
                "/compact": self.op_compact,
            }.get(url.path)
            if handler is None:
                self._json(404, {"error": "unknown path"})
                return
            self._json(200, handler(req))
        except LimitError as exc:
            self._json(409, {"error": str(exc), "status": REGISTRY.status()})
        except NotFound as exc:
            self._json(404, {"error": str(exc)})
        except (ValueError, RuntimeError, subprocess.CalledProcessError, OSError) as exc:
            self._json(400, {"error": str(exc)})
        except Exception as exc:
            self._json(500, {"error": repr(exc)})

    def _pool(self, req, create=False):
        return REGISTRY.get(kind=req.get("pool", "shared"), cwd=req.get("cwd"),
                            owner=req.get("owner"), key=req.get("key"), create=create)

    def op_ensure(self, req):
        need = parse_need(req.get("need", ""))
        if not need:
            raise ValueError("ensure needs --need")
        pool = self._pool(req, create=True)
        if "reset_at_day_end" in req:
            pool.data["reset_at_day_end"] = bool(req["reset_at_day_end"])
            pool.save()
        if "forks" in req:
            pool.data["forks"] = bool(req["forks"])
            pool.save()
        if "extra_args" in req:
            pool.data["extra_args"] = str(req["extra_args"] or "")
            pool.save()
        return {"key": pool.key, "tmux": pool.tmux_session, "workers": pool.ensure(need, REGISTRY)}

    def op_submit(self, req):
        pool = self._pool(req)
        task = pool.submit(req["worker"], req["file"])
        return {"key": pool.key, "task": task}

    def op_wait(self, req):
        pool = REGISTRY.find_task(req["task"], key=req.get("key"))
        task = pool.wait(req["task"], float(req.get("timeout", 150)))
        return {"key": pool.key, "task": task,
                "state": "PENDING" if task["state"] in ("queued", "running") else task["state"].upper()}

    def op_park(self, req):
        pool = self._pool(req)
        return {"key": pool.key, "parked": pool.park(req.get("workers"))}

    def op_resume(self, req):
        pool = self._pool(req)
        return {"key": pool.key, "resumed": pool.resume(req.get("workers"))}

    def op_compact(self, req):
        pool = self._pool(req)
        return {"key": pool.key, "compacted": pool.compact(req.get("workers"))}


def run(port):
    global REGISTRY
    os.makedirs(POOL_ROOT, exist_ok=True)
    REGISTRY = Registry()
    threading.Thread(target=REGISTRY.policy_loop, name="policies", daemon=True).start()
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    sys.stderr.write(f"poold listening on http://127.0.0.1:{port} pools={len(REGISTRY.pools)}\n")
    if not glob.glob(LAST_TURN_HOOK_GLOB):
        sys.stderr.write("warning: session plugin hook pool-last-turn.sh not installed; using transcript mtime\n")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("run", help="run the daemon in the foreground")
    r.add_argument("--port", type=int, default=DEFAULT_PORT)
    a = ap.parse_args()
    if a.cmd == "run":
        run(a.port)


if __name__ == "__main__":
    main()
