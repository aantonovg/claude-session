# session plugin: modes of the main session

One user-invocable skill per mode. Start a session, pick the model and effort, then run
`/session:<mode>`; the skill states the rules of the mode, starts the keep-warm cron and
says what the session may and may not spawn. This README is the reference behind the
skills: read it before changing any of them.

| skill | mode | spawns |
|---|---|---|
| base (`base/BASE.md`, injected by the `SessionStart` hook, no skill to invoke) | every session: main + fork subagents, launch forms, cache and wait rules, models, efforts, roles, intelligence up/downscale (the August workflow rules folded in, 2026-09-06) | forks + one-agent `Workflow` for cold agents (waiter, heavy agent on request) |
| `session:pipeline` | on top of the base: a staged pipeline with gates (research, critic, decision, verification, implementation, closure check); shared rules in `skills/pipeline/core.md` | forks + lean cold critic (and cold researcher) |
| `session:review` | on top of the base: verification-first review of someone else's MR (reads `skills/pipeline/core.md`) | forks + cold researcher |
| `session:codex` | on top of the base (pipeline or review may also be on): codex heavy axis (sol, astra) and executor axis (luna, terra) | codex-proxy one-agent workflows |
| `session:pool-workflow-unstable` | workflows over a pool of warm worker sessions run by the `poold` daemon; each stage a haiku `pool-proxy` (experimental, daemon currently stopped) | pool-proxy agents + forks |
| `session:pool-unstable` / `session:pool-stop-unstable` | show or start the pool by hand / park it | - |
| `session:ask` | ask without blocking: questions doc in Russian, Plannotator in the background, continue on reversible defaults (the model may invoke this one) | - |

Loading order (2026-09-06, 0.7.0-pre): the base arrives by hook at every session start
(startup, resume, compact, clear), nothing to invoke; then `/session:pipeline`
(implementing something) or `/session:review` (someone else's MR); then, optionally,
`/session:codex <mode>`. `session:workflow` and `session:forks` were folded into the base the same day.

Default for day-to-day work (decided 2026-09-04 after the tests): the base alone (forks). One
context, no relay chatter, zero misses measured. `session:pipeline` adds the staged
process on top of it (2026-09-05).

Removed 2026-09-05 (single, team light/full, team-forks, team-compact, workflow with lean
stage agents): the modes fell behind and are not used; their skills and README sections
live in git history before this change. Their measurements are kept below in
"Measurements (kept from removed modes)". Peers, delegate and workflow-over-a-crew were
never built; the pool (mode 9) stays as an unstable experiment.

Everything below follows from one fact: the prompt cache is the main cost lever on this
account, and Fable 5.1 makes the gap between a cache read and a cache write very wide.
Choose the mode by task size and by how many tool calls the work needs, then keep every
long-lived context warm.

## Facts the modes rest on

Measured on this Mac (2026-09-03, Claude Code 2.1.259) unless marked "docs".

| Fact | Value |
|---|---|
| Main session cache TTL | 1 hour (drops to 5 minutes only in usage overage) |
| Subagent / workflow agent TTL | 5 minutes by default; `subagentPromptCacheTtl: "1h"` in settings or `CLAUDE_CODE_SUBAGENT_PROMPT_CACHE_TTL=1h` gives 1 hour (docs) |
| Cache write price | 5m bucket = 1.25x input, 1h bucket = 2x input; read = 0.1x input (docs) |
| A cache hit | restarts the TTL for free |
| Session start in a large project (big CLAUDE.md, MCP servers, plugins) | ~85K tokens written; the static head (~35K) is shared between sessions in the same cwd |
| Workflow agent first turn | 35-50K written (opus), agents of one fan-out with equal model/effort/tools share the first agent's prefix (17K read seen) |
| Keep-warm ping cost | one cache read of the whole context (85K ≈ 2 cents) |
| Resets the whole cache | `/effort`, `/model` (Claude Code warns first), a plugin set change in `/plugin`, `/compact`, `/clear`, the date rollover at midnight, edits to a loaded settings file |
| Partial rewrite | `/reload-plugins` (~9K, the tool block) |
| Does not reset | opening and closing `/plugin`, `/skills`, `/memory`, `/mcp`, `/config`; a memory write by this or a neighbour session (the change arrives as an appended system-reminder); plan mode toggle; file edits |
| Teammate pane discovery | the teammate's pane lives in the tmux server Claude Code chose for the team, often a private `claude-swarm-<pid>` socket invisible to `tmux list-panes -a`; read `TMUX` and `TMUX_PANE` from the teammate process environment and address the pane with `tmux -S <socket>`; an empty pane list never means in-process (check `backendType` in `~/.claude/teams/<team>/config.json`) |
| Teammate effort | a tmux teammate inherits the lead's `--effort`; an agent file's `effort:` does not reach it (the `model:` pin does); `/effort <level>` typed into its pane works (confirm dialog needs a second Enter) and so does `/model <full id>`; both are saved as the account default in `~/.claude/settings.json`, so a team compact (removed mode) restored the recorded defaults |
| Fork subagent | inherits the parent's model AND effort, cannot override either; measured (10 forks, 2026-09-04): first turn reads the parent's full prefix (120K-350K read, 0.1-5K written, into the parent's 1h bucket), every later turn writes into the 5m bucket; a fork that waits over 5 minutes in one call rewrites its own suffix on the next turn (the parent prefix stays cached); a cron created by a fork fires in the main session, never in the fork; a parent `/effort` change propagates to running forks (docs) |
| Plain subagent | fresh context, measured 60K written on the first turn (general-purpose); model (and, per docs, effort) via agent frontmatter; workflow `agent()` opts always honoured; with `subagentPromptCacheTtl: "1h"` the whole 60K lands in the 1h bucket (measured), without it in the 5m bucket |
| Teammate | with `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` a *named* plain Agent spawn is an in-process teammate (`taskKind: in_process_teammate`, transcript under `<session>/subagents/agent-a<name>-*.jsonl`): fresh context, measured 69K written on the first turn in the **5m** bucket, stays alive and answers SendMessage; it has the Agent tool and can spawn its own forks (measured). `name` + `subagent_type: fork` does NOT make a teammate: it is a one-shot fork that exits after its task. With `teammateMode: "tmux"` the teammate is a separate `claude` process in a tmux pane with its own session file, and its writes land in the **1h** bucket (measured: 54K + 13K on start) regardless of `subagentPromptCacheTtl` |
| Teammate pings wake the lead | every teammate turn ends with an idle notification that is delivered to the lead as a turn: a teammate's `pong` to its own cron costs the lead one cache read of its whole context (measured: ~518K read, ≈ $0.14 on a fable lead; ≈ $0.02 on a fresh 85K lead). With 30-minute pings ≈ $0.28/h per teammate on a fat lead. A lead-driven `ping all teammates` is worse (1 + N lead turns per cycle) and no setting suppresses the notifications, so teammates keep their own crons and the lead drops its own cron once the team is up (the notifications keep it warm): floor = 2N turns per cycle; the levers are a small lead context (forks, short replies), light over full, and parking the team in files for long idle periods |
| Peer sessions | a SendMessage to another local session (ref from ListAgents) wakes an idle interactive session: it received the message as a `cross-session-message` turn and answered with its cache intact (84K read, 330 written) |
| Fork re-invocation | a fork that ends its turn with a background Bash running is re-invoked when the job exits (measured 52 s later), but the re-invoked turn reads only the static head and rewrites the whole context into 5m (409K, ≈ $5 on fable): never leave a background job behind in a fork; short foreground polls are the only cheap wait |
| TTL clock | measured from request start, not response end (docs); a turn whose generation plus tool wait exceeds the TTL loses its cache before the next request; no keep-alive in Claude Code |
| Cron jitter | recurring jobs fire up to 10% late (max 15 min), so a keep-warm loop must be ≤ 50 minutes for a 1h TTL; 30 minutes is the safe default |

## Rules that apply to every mode

1. Pick model and effort before the first message. Never change them mid-session.
2. A `ping` cron every 30 minutes in every long-lived session (main session, each
   teammate); every mode skill creates it as its first tool call, teammates create their
   own from the spawn message.
3. No `/clear` and no `/compact` mid-task until the task is finished or the context is
   clearly degraded (well above 500K). A warm compact is cheap (rule 7), but every compact
   loses detail and the next turn pays a fresh ~65K start.
4. `/recap` is safe. Menus are safe. `/reload-plugins` costs ~9K. Plugin changes, model,
   effort, settings edits and midnight cost a full rewrite: do them right before a real
   prompt, never in a session that only pings.
5. Headless `claude -p` is never used for tests on this account (3.3x usage penalty);
   drive a foreground session in tmux instead (see the global rule).
6. Never continue yesterday's big session from where it stopped. A session with 250K+
   tokens whose cache has expired costs a full 2x rewrite of the whole history on the
   first message, the largest useless spend there is, and then keeps paying the big
   context on every tool call. Either `/compact` and restart the keep-warm loop (keeps a
   summary, costs the summary plus a ~85K start) or `/clear` (cheapest start, summary
   lost). Both give far more capacity before degradation. Resuming a cold 250K+ context
   is acceptable only in rare cases where the exact history matters more than the cost.
7. Compact while warm. The compact call reads the whole context at the cache-read rate
   and only pays for the summary output, so on a warm session it costs a near-fixed
   $0.1-0.2 whatever the size (measured: 188K sonnet ≈ $0.09, 80K sonnet ≈ $0.17; the
   summary output dominates). On a cold session the same compact reads everything at the
   full input rate: 460K cost $1.30 on sonnet and $5.87 on fable. Two habits follow:
   - End of the working day: `/compact` every big session that is still warm, on its
     own model. Next morning it resumes from a ~65K summary instead of a cold 460K
     history, and the summary is written by the model that did the work.
   - A big session that is already cold (yesterday's fable 250K+): switch to
     `sonnet` first (the cache is dead anyway, the switch is free), `/compact` there,
     switch back to the working model (a small-context reset, cents), then continue.
     `/model` saves the choice into settings.json, so restore the default afterwards.

## Mode 1 — Workflow (baseline, folded into forks 2026-09-06)

The original flow (August 2026, user-prefs 6.5-6.7) kept as the baseline; its skill text
lives in the base (`base/BASE.md`), section "Downscale and upscale of intelligence" (`session:workflow`
no longer exists as a skill, the rules apply to every `Workflow` launched from any session). The main
session does no work itself: it plans, launches `Workflow` scripts, verifies results and
talks to the user. Every job is a cold workflow agent: one class and one pairing per
workflow stamped into `meta.name` (`c<class>-<pairing>-<slug>`), every `agent()` with
explicit model and effort and a `<mod>-<eff>-` label prefix, 0-3 skills named by the main session at
the end of each prompt, author → reviewer-debugger (→ fast tests) → fixer loops of 1-3
cycles, `BLOCKED` stops the script, land stages self-contained. No forks, no plain
subagents, no teammates.

Cost shape: every stage pays a cold start (35-50K, see "Teammate start size") and the
main session's prefix is small; the benchmark in Mode 9 ("plain") is this mode. Used to
compare `forks` and `pipeline` on the same prompt.

## Mode 2 — Forks (the base; `session:forks` folded into `base/BASE.md` 2026-09-06)

One main session plus fork subagents (`subagent_type: "fork"`). Forks inherit the whole
conversation and the cached prefix, so spawning them is nearly free; their tool calls stay
out of the main context, which is what makes the main session live longer.

- Fits: several independent chunks of one task that need the shared context (parallel
  reviews from different angles, parallel edits in disjoint files, verification passes).
- Limits: same model and effort as the main session, no mixing; a fork's context is not
  clean, so it reviews with the main session's bias; forks are short-lived, each new fork
  re-adds only the task text, but a fork cannot be reused after it returns.
- Measured: a fork's own turns are cached in the 5m bucket; fine while it works, lost after 5 idle minutes.
- Measured 2026-09-04: in normal auto mode a fork runs Bash with `$var`, `$(…)` and loops
  without any permission prompt; only in plan mode such a command prompts the user
  ("Contains simple_expansion"). Keep forks off Bash expansions during plan mode only.
- Setup: cron `ping` every 30 minutes in the main session; forks need nothing.
- Long waits (2026-09-05): every fork turn re-reads the whole parent prefix at cache-read
  price, so a polling fork on a 500K prefix costs about 0.5M read tokens per poll (18
  polls ≈ 9M); a call over 5 minutes rewrites the fork suffix; a fork re-invoked by a
  finished background job is a full miss (409K measured); the API cache lookback is 20
  blocks, so many-block forks are an unmeasured risk. Rule: forks are short (≤ 10 turns),
  never poll or wait, never use `run_in_background`. Waits go to the `waiter` agent
  (`agents/waiter.md`: fresh context, sonnet pin, tools Bash + Read), launched by the main
  session as a one-agent `Workflow` with the condition, the polling command shape, dialog rules,
  a time budget and a word limit; it returns facts only. The main session may also run
  async work itself and be woken by the completion.
- Launch forms, all modes: exactly two. `Agent` only with `subagent_type: "fork"`;
  `Workflow` for every cold agent (waiter, critic, decision reviewer, cold researcher,
  heavy agent on request, codex-proxy), one agent per single stage and ONE workflow
  (`parallel` / `pipeline`) for N independent cold agents, never N launches; no plain
  subagents. Measured 2026-09-06, same waiter agent both ways: agent cost identical
  ($0.136 per five sonnet agents, each reads 6.7K of its system prompt from cache and
  writes 8.5K); each separate completion notification is a full prefix re-read in the
  main session (≈ $0.13 on a 285K fable prefix); notifications landing together are
  batched by Claude Code.

## Mode 9 — Pool (`session:pool-workflow-unstable`, `session:pool-unstable`, `session:pool-stop-unstable`)

Workflow over warm peers without a team: a separate daemon (`poold`) runs a pool of plain `claude`
sessions in tmux windows, one per model+effort combo or per role, and keeps them warm.
A workflow script drives the stages; each `agent()` is a `pool-proxy` (haiku, Bash
only) that hands a task file to a worker through `poolctl` and returns the result file.
No lead, no teammates, no notifications: the worker writes a file, the proxy waits for
it, the main session reads it.

Idea in one line: the workflow keeps its visible pipeline, review loops and resume; the
tool-call volume runs in warm 1-hour contexts instead of cold 35-50K agent starts.

### Pieces

| piece | where | what |
|---|---|---|
| `poold` | `pool/poold.py`, HTTP `127.0.0.1:19540` | registry, tmux spawn, task queue, policies, admin page |
| `poolctl` | `pool/poolctl` | CLI over the HTTP API: `ensure`, `submit`, `wait`, `status`, `park`, `resume`, `compact` |
| `pool-proxy` | `plugins/session/agents/pool-proxy.md` | haiku agent: `submit` + `wait` rounds, returns `POOL RESULT FILE` + `LAST LINE` |
| skills | `pool-workflow` (mode), `pool` (show/ensure), `pool-stop` (park) | thin wrappers, all through `poolctl` |
| state | `~/.claude/pool/<key>/` | `pool.json`, `tasks/`, `results/`, `park/`, `last-turn/` |

Pools: `shared/<sha1(cwd)[:12]>`, one per project, the default; `dedicated/<session id>`
for one owner session on the user's word (parked 10 minutes after the owner exits).
Worker names are combos (`opus-low`) or roles (`reviewer=opus-medium`), unique per pool
(`opus-low-2`).

### Protocol

1. Spawn: `tmux new-window -t pool-<key> -n <name> -c <cwd> "zsh -lic 'claude --model
   \"<full id>\" --effort <lvl> --session-id <uuid>'"`. Interactive login shell so the
   `~/.zshrc` exports (MCP tokens) load; `[1m]` quoted or zsh globbing fails. Model and
   effort by flags only: `settings.json` is not touched (probe 5).
2. Briefing, typed once: worker name, pool key, combo, roles, forks mode, the task line
   format, the result dir, `ping` → `pong`, no `/model` `/effort` `/compact` or crons.
   The daemon re-sends the protocol line after every `/compact` (probe 3: after a compact
   the worker answered `t2 done.` instead of `DONE t2`).
3. Task: `poolctl submit` copies the file to `tasks/` and types `POOL TASK <id> <path>`;
   the worker writes `results/<id>.md`, last line `DONE` or `BLOCKED: …`, and replies
   `DONE <id>`. `poolctl wait <id> --timeout 150` long-polls for the file.
4. Proxy: header only (`POOL:`, `POOL WORKER:`, `POOL TASK FILE:`, optional `POOL MAX
   WAIT:`), identical across a run so proxies share the cached prefix; `submit` then
   `wait` rounds under the 170 s Bash guard; answer = two lines or `BLOCKED:`.
5. Task file names carry a content hash: a workflow `resume` replays `agent()` calls
   with an unchanged prompt from the journal.

### Daemon policies (not the model's job)

- Keep-warm: `ping` typed 45-50 minutes after the worker's last turn (mark from the
  worker's Stop hook from the plugin in `last-turn/`, fallback JSONL mtime); one cache read per hour.
  A worker that missed the window is `cold`: not pinged; on the next `ensure` it is
  woken if its context is under 100K, otherwise parked and replaced.
- Day end: `/compact` typed to every warm worker an hour before midnight, pings stop
  until the next `ensure` (flag `--reset-at-day-end` clears instead).
- Busy: one task at a time per worker, others queue; `ensure` offers `<name>-2` when
  the queue is longer than one.
- Limit: 15 workers per account by default.
- Context ceiling: an idle warm worker whose context passed the family ceiling
  (opus 120K, fable 200K, sonnet and haiku 300K, `compact_above_tokens`) gets a warm
  `/compact` plus the protocol reminder, at most once per 30 minutes. Cache reads are
  paid on every turn (opus $0.5/MTok), so a 150-200K opus fixer costs more per turn
  than a fresh 60K one.
- Forks mode: after the briefing the daemon types `/session:forks pool` into the
  pane (the `pool` argument skips the ping cron) and re-sends the forks rules after
  every compact. The briefing sentence alone was ignored (benchmark: four workers,
  zero forks). `poolctl ensure --no-forks` disables it.

### Cost model

- Worker turns are cache reads in the 1h bucket (probe 2 below); a stage costs its new
  tokens plus one read of the worker context, not a 35-50K start.
- Proxy: haiku start ≈ $0.07 on the first proxy, less for the next ones (shared prefix);
  the wait rounds are tiny turns.
- Keep-warm: one read of the worker context per hour, ≈ $0.05-0.10 per worker; ten
  workers ≈ $5-10 per day. Compact at day end ≈ $0.1-0.5 per worker while warm.

### Install

Daemon: `python3 pool/poold.py run` (foreground) or the units in `pool/units/`
(`com.claude-session.poold.plist` for the Mac LaunchAgent, `poold.service` for the VM
systemd user unit; step 5 of the plan, not written yet). CLI: symlink `pool/poolctl`
into `~/.local/bin`. Plugin 0.5.0 ships the agent, the three skills and the Stop hook
`hooks/pool-last-turn.sh` (registered by the plugin; it exits at once in sessions
without `POOL_LAST_TURN_DIR`, so no `settings.json` change is needed). On the VM the
admin page is reached with `ssh -L 19541:localhost:19540 claude-vm`.

### Measured 2026-09-04 (probes, sonnet-low worker in a detached tmux on the Mac)

| probe | result |
|---|---|
| 1 `--session-id` worker in tmux, `send-keys` task | PASS: task line is a normal turn, `results/t1.md` and `t2.md` with `DONE`, JSONL under `~/.claude/projects/<encoded cwd>/<uuid>.jsonl` |
| 2 cache after a `send-keys` task | PASS: briefing wrote 58K into the 1h bucket; task turns read 58-59K and wrote 0.1-0.3K each; after `/compact` the next turn read the 42.7K static prefix and wrote the 12K summary |
| 3 `/compact` typed into the pane, `ping` | PASS: no dialog (`Compacted`), `ping` → `pong`; protocol detail degraded after compact (re-brief needed) |
| 5 `--model claude-sonnet-5[1m] --effort low` flags | PASS: pane shows `Sonnet 5 with low effort`, status `sonnet:low`; `settings.json` unchanged |

### Benchmark 2026-09-04 (c3 "Orbit Dodge" browser game, 13 stages, fable-opus row)

Same spec and stages through the pool (haiku proxies + four warm workers fable-low,
opus-medium, opus-low, sonnet-low) and as a plain workflow (one cold agent per stage).

Four runs of the same 13 stages (the second and fourth are reruns with one change):

| metric | plain (5m TTL) | plain (1h TTL) | pool | pool + forks |
|---|---|---|---|---|
| $ for the task | 5.00 | 6.42 | 4.20 (+1.98 one-time worker startup) | 6.54 (+1.81 startup) |
| uncached tokens (input + cache writes) | 453K | 389K | 269K | 366K |
| cache writes by workers | — | — | 88K, all in the 1h bucket | 58K 1h + 306K 5m (forks) |
| output tokens | 9.6K | — | 31K | 25K |
| cache misses | 0 | 0 | 0 | 0 |
| wall time | 10.0 min | 10.8 min | 10.1 min | 15.6 min |
| tests passing at the end | 41 | 23 | 17 | 37 |
| review depth, cycles 1/2/3 (lines) | 55 / 54 / 52 | 55 / 48 / 43 | 31 / 12 / 1 | 51 / 54 / 53 |

What the four runs say:

- The ~20K static prefix (system prompt, CLAUDE.md, tools) is already shared between
  agents of one model and effort under the 5m TTL: the second and later agents read it
  and write ~10K of their own. The 1h TTL reused nothing more and paid 1.6x per write,
  so `subagentPromptCacheTtl` stays at 5m (closed, see below).
- The 5m writes are the agents' own tool output (files read, test output, diffs).
  They do not depend on the TTL. The cost floor of a workflow is therefore about
  "tool-output tokens consumed × write price + the per-turn rereads of the growing
  context"; the only way down is less tool output per stage and fewer turns.
- The pool pays off only when there is a big shared project context that every cold
  agent would otherwise re-read (a corporate repo with 100K+ of orientation). On a
  greenfield task the shared prefix is just the briefing and the pool is a wash.
- Forks inside the workers restore the review quality (37 tests, deep reviews in all
  three cycles) but cost more on small contexts: every fork rereads the worker's
  50-60K prefix on each of its turns and writes its own suffix at the 5m price.

Two workflow rules that follow from the cost floor (in `session:pool-workflow-unstable`, and
valid for plain workflows too): a convergence gate (a review with no medium or high
findings ends the cycles; the fix and check stages of that cycle are skipped) and
tool-output caps in task files (checkers return PASS/FAIL lines and the tail of failing
output; the pipeline has no code review stage at all).

Three lessons, now built in:

1. Opus is the most expensive family per cache read ($0.5/MTok): its fixer read
   150-200K on every one of 32 turns. Hence the per-family context ceiling above.
2. The workers used no forks at all, so their sessions grew and every write landed in
   the 1h bucket (twice the 5m price). Hence `/session:forks pool` at spawn.
3. Proxies plus result files doubled the output: workers answered in the pane and
   copied deliverables into the result file. Hence the result convention (status,
   paths, at most 5 lines; deliverables in project files; nothing in the pane but
   tool calls and `DONE <id>`). tmux capture is not a substitute: pane text is broken
   and unstable, and `claude -p` carries the usage penalty.

The warm reviewer went shallow after cycle 1 (same context reviewing the same code
three times); the quality loss came from there, not from the models. `claude --resume
<id> --fork-session` does not share the parent's cache (probe: first turn read only
the 26.6K static prefix and rewrote 51.6K in the 1h bucket, then stable), so forked
sessions are no answer; in-session forks (Agent tool) are.

Gotchas: a new cwd shows the trust-folder dialog (Down + Enter accepts), so the daemon
handles it or the dir is trusted first; the subagent Bash guard also matches a long
literal wait written inside a tmux command string. Probes 4 (haiku proxy start size,
role discipline, shared prefix) and 6 (last-turn hook) run with steps 2-3 of the plan.

## Mode 10 — Pipeline (`session:pipeline`)

The session base plus a staged pipeline for one task. Source: the design note
`claude-code-agent-pipeline-spec-ru.md` (claude-settings, 2026-09-05) after a
clean-context critique (27 hypotheses) and an evidence audit against the measurements in
this README (`docs/review/pipeline-spec-*.md` in claude-settings). What was kept from the
note and what was cut:

- Kept: research ledger as the one state file of a task (evidence with pointers,
  unknowns with a class, assumptions, verification capabilities), written and read by
  forks only: the main session dictates bullets in the fork prompt and works from the
  fork return lines, it reads a task file at most once after it is marked final;
  decision contract as a
  separate section before any plan; verification harness before implementation, with a
  negative control where the oracle is strong and an explicit "unverifiable" list where
  it is weak; a 5-field structured status from every fork; fast / standard / full path
  tied to the task class with a hard per-path table in the skill (what each path skips,
  ceilings on forks, turns and cold agents: fast ≤ 6 / 50 / 0, standard ≤ 14 / 120 / 1,
  full ≤ 24 / 220 / 3); loop guards per path (research waves 0 / 1 / 2, fix cycles per
  package 1 / 2 / 3, closure-check rounds 0 / 1 / 2).
- Cut: "fresh subagent by default" (a cold agent starts at 35-50K, lean 13-19K; the
  13-stage benchmarks above cost $3.2-6.5 against ~$1.15 for direct work on a real
  class-1 ticket), only the critic (and breadth research) stays cold; the hard-coded model
  table (the session map already has one per account; enterprise has no haiku, opus
  low/medium and fable low only; a fork cannot change model or effort); 5 review roles
  cut to 2 (evidence audit is a fork: it refutes against files, anchoring does not hurt
  there); a "pending-human without blocking" state (a dialog blocks the turn and the
  pings behind it; `session:ask` already covers it); skill metadata, artifact hash
  graph, cost manifest (nothing in Claude Code reads them; claude-cost reads the JSONL).

Class criteria (the same 1-5 classes as the selection map): 1 = one file, known fix,
existing test covers it; 2 = a few files, clear spec, tests exist or are obvious; 3 =
several modules or an unclear cause, needs research, tests to write; 4 = cross-cutting
change, migration or design choice between alternatives, weak or partial oracle; 5 =
multi-day, entangled legacy, incident, or a decision that is hard to reverse. The main
session proposes the class; the critic may raise it. Trade-off, deliberate: a class 1-2
task is self-assigned and has no external check (the audit wanted the critic to assign
the class, which costs a cold agent before any research); the calibration signal is the
share of tasks whose class the critic later raises, visible in `--all-runs`.

The cold stages run as a `Workflow` with one `agent()` each: the critic on
`session:stage-critic` (Read and Write only; model and effort from the reviewer-debugger
cell of the class row, at most 5 tool calls at medium, 3 at high, label
`<mod>-<eff>-critic`), the full path's decision review on `session:stage-reviewer` (same cell
and budget, label `<mod>-<eff>-decision-review`; standard has a low fork check instead,
fast none), and breadth research on `session:stage-researcher` when the stage 1 rule
sends it there. There is no final review of the work: Gate F is a mechanical closure
check by a low fork (verification plan against harness results and package status,
`reviews/closure.md`). Medium or high effort exists only for generating important
documents and critiquing them (critic, decision contract review; `session:stage-reviewer`
is the document reviewer). Code is verified by the harness and never reviewed: a
package without a formal verifier is authored by opus-low (`terra-high` in terra
executor mode) and nobody reads it back; a cheap executor writes only packages that
have a verifier; tests are never reviewed. Everything else is the main session or a
fork on the main session's model.

Cold-stage agents: a cold agent gets only CLAUDE.md with its imports and memory as domain
context; no Skill tool, no MCP, minimal tools. Skills are chosen by the main session (0-3
per stage from the skill-routing map) and injected as `Read these first: <SKILL.md paths>`
in the stage prompt. Sizes measured: default workflow agent 35-50K at start, lean 13K;
built-in tool schemas 24-26K of that; the Skill tool's listing 9K; CLAUDE.md plus imports
12K reach every agent and cannot be cut. The benchmarks tied review quality to the
reviewer's model, not to its tool set. Untested: whether auto-memory (`MEMORY.md`) reaches
a custom agent at all.

Verification split (user's note on the spec): mechanical checks (tests, linters, formal
tools) are a plain fork; there is no semantic code review on a weak oracle: the package
is authored by opus-low (terra-high in terra executor mode) instead and left unreviewed. The cheap executor row of the map is not used in
this mode; if a task needs a cheaper executor family, start the session on that model.

Cost ledger: `<task dir>/ledger.jsonl` holds one row per spawn or main-session stage
(ts, stage, step, role, kind main / fork / workflow-agent, model, effort, mode, class,
agent id, label), written by the main session, plus stop marks written by the plugin's
`SubagentStop` hook (`hooks/pipeline-subagent-stop.sh`, active only while
`~/.claude/projects/<encoded-cwd>/pipeline/current` points at a task dir). The session
id in `<task dir>/session` is written by the skill at start (the hook writes it as a
fallback; the script falls back to the newest transcript by mtime with a warning).
`tools/pipeline-cost.py <task dir>` joins the rows with the main and agent transcripts
(dedup by message id, the price table copied from claude-cost, the cache-miss rule of
`cache-loss.py`) and prints the per-row table plus cuts by stage, role, kind and
model+effort, then a session total (every main turn plus every found agent transcript)
with the unattributed part (main turns outside all stage rows: pings, setup, closure);
`--all-runs <pipeline root>` gives one line per run (mode, class, attributed $, session
$, wall time, spawns, misses): the calibration data for the fast / standard / full
paths. Main-session turns are assigned to the latest `main` row by timestamp, so a stage
row must be appended when the stage starts. `--selftest` runs on synthetic records.

Cost rules (from test 1, 2026-09-05, B2CT-22116, opus-low main, full path through Gate D;
analysis in claude-settings `docs/review/pipeline-test1-cost-analysis.md`): $17.9 total,
one cache miss ($0.34), 63% of the money was prefix re-reads over 197 turns. The rules
below keep the gates and artifacts and would have saved about $7.9 (44%):
1. Fork turns ≤ 8, batched commands; split at 12 (8 of 12 forks ran 10-25 turns): ≈ $4.0.
2. Terse main session: its 29K of chat became prefix for ~120 later turns: ≈ $1.5.
3. Review forks read inputs in one command and never pause > 3 min before the write (the
   only miss was a > 5 min pause, 53K rewritten): ≈ $1.0.
4. MCP payloads capped by fields and persisted once in `evidence/raw/` (45K of GitLab
   discussions fetched twice, 33K pipeline jobs, 28K JQL): ≈ $0.6.
5. No merge-ledger fork (the last wave fork updates the ledger); evidence bundles ≤ 80
   lines (two were 170), `ledger.md` ≤ 120: ≈ $0.8.
6. Ledger completeness: every spawn gets its row before launch and `agent_id` right after
   (test 1 lost the merge fork's row and one review row's id).

Codex axis (`session:codex`, loaded on top of the base at any point, since 0.7.1 without a
pipeline or review prerequisite; base-only sessions map executor-kind fork jobs to the
executor axis and the heavy agent on request to the heavy axis, exchange directory
`$TMPDIR/codex-<date>/codex/`; the pipeline skill itself never mentions codex): two multiplied axes, heavy `none | sol
| astra | +sol | +astra` (critic, decision review only, document critique: replace the Claude agent or pair a codex one with it, merge fork, a high
finding in either fails the gate) × executor `none | luna | terra` (research sweeps, harness,
packages, mechanical checks: sonnet-low slots → luna-high, with terra also opus-low executor
slots → terra-high; executors have one effort). Heavy effort follows the stage's tool-call
budget: ≤5 calls pure reasoning → sol-medium / astra-medium, the hardest document gate, ≤3
calls → sol-high / astra-high; heavy models never review code (2026-09-06: sol-high
final code reviews read 300-470K tokens each; those runs count as failed). A stage stays on Claude when it needs MCP, repository edits under Claude
permissions, the pipeline's own artifacts or a skill; codex writes only into `<task
dir>/codex/` and `reviews/<stage>-codex.md`. Every codex stage is one `codex-proxy`
`agent()` with workflow opts `model: 'haiku', effort: 'medium'` (the opts win over the agent
file; the deployed `~/.claude/agents/codex-proxy.md` still pins opus/low and should be
re-pinned to haiku-medium with the next user-prefs update), header block only, prompt and
answer as files; ledger rows carry `kind: codex-agent` and `codex: <mode>` and are priced
from `~/.codex/proxy-usage.jsonl` by model + effort, then time window. Astra is mapped
(`gpt-6-astra`, medium/high, label `atr`; $10 / $1 / $50 per M, unofficial). Tables and conventions:
`skills/codex/codex-modes.md`.

Review axis (`session:review`, loaded after the pipeline skill; the pipeline skill
never mentions it): reviewing someone else's MR or PR without reading the diff; one finding = one draft note = one resolvable thread, MR-level threads for findings without a line; only findings are published, passed checks and unverifiable claims stay silent (lite, std) or get a diff-scoped opus-low read (full). The
stages 1-7 are replaced by research (a short fork fetches intent, claims, CI, changed
files, threads once through MCP; a cold sonnet-low researcher covers repository questions), verification audit (a fork writes the review contract:
claim → existing / missing / no possible oracle), verification delta (missing oracles
only), harness delta and run (MR branch in a worktree under `$TMPDIR`, low forks add and
run the missing checks), threads from run results (`reviews/threads.md`, critical and
important findings only, confirmed against the base branch; harness failures on our side
go to `reviews/harness.md`, never to the MR), closure check, publish: file-line threads
of at most 3 lines or one MR note of at most 6, at most 30 published lines per MR and
nothing about how the review was done, all as draft notes, submitted or "request
changes" on the user's word, approve when nothing critical or important remains. Re-review path (`re`): resolve threads fixed with evidence
or answered, rerun the existing harness delta and CI, approve. Paths `lite | std | full |
re` by diff size and blast radius, with ceilings (3 / 10 / 18 / 2 forks); the only code
reading is a diff-scoped opus-low read of files with no possible oracle (std, full); the
only heavy agent is the full path's contract critique (3 calls). Main session: opus-low.
Untested.

Untested (to measure on the first real tasks, Mac via `bw`, fable-low main): A/B cost against a
plain forks session on 3 class 2-3 tickets ($ by `tools/pipeline-cost.py`, misses by
`tools/cache-loss.py`, defects caught before the closure check); size of `task.md`
after two research waves against the 200K enterprise context; whether the decision
contract check by a low fork (standard path) catches at least 80% of what the full
path's heavy decision review would; continuing a task from its directory in a new session (tokens
at start, research repeated); whether the main session reclassifies a disputed unknown
under pressure (Gate R gaming); whether `SubagentStop` fires for Workflow `agent()`
calls (until known, the skill appends the stop line of the cold stages by hand).

## Measurements (kept from removed modes)

Facts measured 2026-09-04 while the team, delegate and workflow modes existed; the modes
are gone, the numbers still hold.

- Teammates: in-process (`teammateMode: "in-process"`) start with a fresh 69K context in
  the 5m bucket; tmux teammates are separate sessions on the 1h bucket (54K + 13K on
  start). Claude Code opens a private tmux server (`tmux -L claude-swarm-<pid>`); only a
  detached test session on macOS fails with `respawn pane failed: fork failed: Device not
  configured` (attach a pty client first); Linux needs no client. The `Agent` tool takes
  only model aliases (`opus`, `sonnet`, `fable`), no effort; `/model` and `/effort` typed
  into the pane work and are saved as the account default. A teammate has the Agent tool
  and can spawn a fork; plain subagents cannot nest. Every teammate reply lands in the
  main context: a full team of six on a small task cost ≈ $10 (main $3.9 of it, 6.9M
  cache-read tokens from 8 exchanges).
- Plain subagent (delegate): 35-60K written per fresh start; `subagentPromptCacheTtl:
  "1h"` moves the 60K into the 1h bucket (measured), otherwise 5m.
- Lean workflow stage agents (`stage-author/reviewer/executor/researcher`, still shipped
  in `agents/`): 12K written on the first turn against 35K for the default workflow agent
  (23.6K of it the built-in tool schemas). `session:pipeline` uses `stage-critic` and
  `stage-researcher` for its cold stages, `stage-reviewer` for a document review.
- Workflow agent → teammate handoff (sonnet): a workflow agent CAN `SendMessage` to a
  teammate; the reply is routed to the main session, not to the agent; the working
  handoff is a result file the proxy waits for with a bash until-loop. No `agent()`
  option targets a teammate; workflows cannot spawn forks of the main session.
- Proxy stage cost in a large monorepo (5m bucket): proxy 1 first-turn write 60 247,
  proxy 2 three minutes later 35 552 (24 819 read from proxy 1's head); later writes
  ~9-10K each; cache reads ~537K / ~358K. At sonnet prices ≈ $0.29 / $0.18 per stage;
  opus ≈ $0.22-0.31 start, haiku ≈ $0.07.

## Closed: 1-hour cache for forks and subagents

`subagentPromptCacheTtl` stays at the default 5 minutes (decided 2026-09-04 after the
benchmark rerun above: the 1h TTL made the same workflow 28% more expensive and reused
nothing that 5m did not already reuse). A fork that waits or generates for more than
5 minutes in one call still loses its cache, and a long fork (more than 20 content
blocks after the fork point) then also misses the parent prefix (measured: three fable
forks rewrote 229K, 377K and 251K, ≈ $10.7 together). The mitigation is the fork rules
(short waits, background for long commands, the Bash guard hook), not the TTL.
`tools/cache-loss.py <hours>` stays as the audit tool; revisit only if the miss losses
it reports grow well past the extra 1h cost over a representative week.

## Waiting on the user

A pending AskUserQuestion, permission prompt or plan approval blocks the turn; cron
pings do not fire at all while it waits (measured 2026-09-04, sonnet, `*/2` cron: three
windows passed with no API call during a pending question and during a pending plan
approval; one queued ping was delivered the moment the dialog closed). A user away for over an hour therefore
loses the 1h cache of that session. `askUserQuestionTimeout` (`"60s" | "5m" | "10m" |
"never"`, default never, `~/.claude/settings.json`) auto-continues an unanswered
AskUserQuestion with whatever was selected; it does not cover permission prompts or
plan approval. Rule for the model (global instructions): ask only when the answer
changes the work; put the recommended option first; when the question auto-continues
without an answer, take the recommended option for a reversible choice, and for a
decision that must be the user's end the turn with the question written out instead of
leaving a dialog open, so the pings keep the cache alive. Avoid plan mode in a session
that may sit unattended. `session:ask` is the non-blocking form: a questions document
opened in Plannotator with `run_in_background`; the session continues and is woken by
the submitted feedback (a background completion re-invokes the main session as a
normal cached turn, unlike a fork).

## Verified 2026-09-04 on the VM (opus-low main, sonnet[1m] teammate, real ticket)

Restore from a compact, `/model claude-sonnet-5[1m]` pin through tmux (allow rules for
`tmux send-keys/capture-pane/list-panes`), five stages by SendMessage, seven forks
inside the teammate, `pong`, a team compact (removed mode) with a time-stamped dir: main 52 turns and
the teammate 32 turns wrote only into the 1h bucket, every fork read the teammate's
prefix and wrote 1-4K, zero cache misses anywhere. Cost ≈ $7. A subagent Bash guard
hook (user-prefs `fork-bash-guard.sh`) now caps fork Bash timeouts at 170 s; Claude Code
itself already blocks literal long `sleep` calls.

## Teammate start size and MCP tool schemas

Measured 2026-09-04 on the VM (34 org MCP connectors): a sonnet teammate went from 86K
after its first turn to 212K on the second, before any work. The +94K is the tool
block: the connectors finish connecting after the teammate's first turn and their full
tool schemas are appended without deferral, because the teammate's tool-search "auto"
decision was taken while the tool count was still small. The main session, started
with tool search already active, keeps names only (~30K). Fix: `export
ENABLE_TOOL_SEARCH=true` in the shell environment of every `claude` process (VM and
Mac `~/.zshenv`); the teammate then shows a `deferred_tools_delta` attachment and stays
near 90K. On a 200K model the unfixed jump caused auto-compact thrashing and "prompt
too long" in the teammate's forks.

## Compact prices

- Warm compact (cache alive): the compact call reads the whole context at the cache-read
  rate and pays for the summary output, a near-fixed $0.1-0.2 on sonnet whatever the size
  (188K: ≈ $0.09; 80K: ≈ $0.17). The next turn after it reads ~43K and writes ~25K.
- Cold compact: the whole history at the input rate. 460K: $1.30 sonnet, $5.87 fable.
- Cold big session on fable: `/model sonnet` (free, cache dead anyway), `/compact`,
  `/model` back (small reset), restore the settings.json default afterwards.
- The compact call leaves no usage entry in the JSONL; its cost is the status-line delta
  minus the next turn.
- Opus 200-300K, native compact + resume versus handoff file + fresh session: measured
  2026-09-04, see the table below.

Measured 2026-09-04, opus-low, two identical sessions filled to ~372K (warm, 1h cache):

| step | (a) warm `/compact` + `--resume` | (b) handoff file + `/clear` |
|---|---|---|
| park | `/compact` $0.47 | write `main.md` (139 lines, ~1.9K tokens) $0.52 |
| first turn after | $0.31 (read 31.5K, write 28.8K) | `/clear` + read the file $0.36 |
| next turn | `--resume` in a new process, `ping` $0.08 | `ping` $0.03-0.10 |
| park + morning | **$0.86** | **$0.88-0.95** |
| context after | 60-65K | 56-59K |

A tie within noise: both read the history at the cache-read rate and pay for a short
summary. The plugin uses the file for the main session too (one mechanism for main and
teammates, human-readable, restorable from any fresh session); a native warm `/compact`
is equally good when the user wants to keep the same session id.

## Roles, selection map and stages (used by `workflow`, `forks` and `pipeline`)

Six roles: **reviewer-debugger** (independent review of plans and code, root-causing
failures; the strongest slot), **plan author/fixer** (writes the plan, applies review
findings to it), **code/test fixer** (applies review findings to code and tests),
**code/test author** (writes code and tests), **fact researcher** (collects facts, no
analysis), **test/script executor** (builds, tests, scripts, deploys; mistakes are loud).

The live map is per account: `~/.claude/session-map.md` (deployed by the user-prefs
plugin of claude-settings from `hooks/session-map-<tier>.md`; the plugin ships
`session-map.example.md` with the same layout). The skills read that file; the table
below is the subscription default and the fallback when the file is missing.

Selection map, pairing fable-opus (row = task class 1-5, column = role):

| Class | Reviewer-debugger | Plan author/fixer | Code/test fixer | Code/test author | Fact researcher | Test/script executor |
|---|---|---|---|---|---|---|
| 1 very simple | opus-low | opus-low | opus-low | opus-low | opus-low | opus-low |
| 2 simple | opus-medium | opus-low | opus-low | opus-low | opus-low | opus-low |
| 3 medium | fable-low | opus-medium | opus-medium | opus-low | opus-low | opus-low |
| 4 complex | fable-medium | fable-low | opus-medium | opus-medium | opus-low | opus-low |
| 5 very complex | fable-high | fable-medium | opus-high | opus-medium | opus-low | opus-low |

Full model ids (always the 1M variant on the subscription):

| short | id |
|---|---|
| fable | `claude-fable-5-1[1m]` |
| opus | `claude-opus-5[1m]` |
| sonnet | `claude-sonnet-5[1m]` |

Stages of a task, each authored artifact paired with an independent review, 1-3 cycles,
exit as soon as the review is clean:

1. Plan: plan author → reviewer-debugger → plan author applies findings.
2. Red tests (when acceptance criteria exist): code/test author → reviewer-debugger
   (test code and criterion coverage) → code/test fixer.
3. Implementation: code/test author → reviewer-debugger → test/script executor (fast
   tests) → code/test fixer.
4. Technical stages (preparation, commit, conflict resolution): test/script executor,
   no review.

Stop on block: any worker that hits a permission denial stops at once and returns
`BLOCKED: <denied action>`; the main session never runs a review or fix cycle against
unchanged files. Land steps (commit, push, MR update) get self-contained prompts: repo
path, branch, expected changed files, a one-line summary of the change; the worker checks
`git status` and `git diff --stat` first and returns `BLOCKED: unexpected working tree`
on a mismatch. Push only when the task explicitly grants it.

Skills for a worker: the main session names 0-3 skills per stage from the skill-routing
map (`~/.claude/memory-user/skill-routing.md`) and puts them at the end of the prompt
("Load these skills with the Skill tool before starting: …" or "No skills needed for this
step."). Never `claude-api`, never a superpowers orchestration skill.

## Verified 2026-09-04 (sonnet sessions in tmux)

1. Fork: first turn reads the parent prefix, own turns go to the 5m bucket.
2. Teammate: fresh 69K context, 5m bucket by default; `name` + `fork` is a one-shot fork.
3. Teammate → fork nesting works.
4. SendMessage wakes an idle peer session; it answers with its cache intact.
5. `subagentPromptCacheTtl: "1h"`: plain subagent writes 60K into the 1h bucket.

6. `teammateMode: "tmux"`: the teammate is a separate session, 1h bucket, own session
   file under the project dir; the parent gets its reply as a teammate-message turn.
7. Workflow agent → teammate handoff works via SendMessage + a result file; direct
   replies go to the main session, not to the workflow agent.
8. Warm `/compact` on sonnet-low (188K context): ≈ $0.09 for the compact, ≈ $0.16 for the
   first turn after it (42.7K read + 24.7K written). The compact call itself leaves no
   usage entry in the session JSONL; its cost is the total delta minus the next turn.

Recommended team setting: `teammateMode: "tmux"` + default 5m subagent TTL.
