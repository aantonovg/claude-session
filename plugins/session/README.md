# session plugin: modes of the main session

One user-invocable skill per mode. Start a session, pick the model and effort, then run
`/session:<mode>`; the skill states the rules of the mode, starts the keep-warm cron and
says what the session may and may not spawn. This README is the reference behind the
skills: read it before changing any of them.

| skill | mode | spawns |
|---|---|---|
| `session:single` | one session | nothing |
| `session:forks` | main + fork subagents | forks only |
| `session:team` | main + tmux teammates (light: one per model+effort; full: one per role) | teammates only |
| `session:team-forks` | team where main and teammates use forks for volume | teammates + forks |
| `session:team-compact` | fold a running team into files; `team` / `team-forks` restore from them | - |
| `session:workflow` | plain workflows with lean stage agents (`stage-author/reviewer/executor/researcher`, 12K start instead of 35K), convergence gate | lean workflow agents + forks for recon |
| `session:pool-workflow` | workflows over a pool of warm worker sessions run by the `poold` daemon; each stage a haiku `pool-proxy` | pool-proxy agents + forks |
| `session:pool` / `session:pool-stop` | show or start the pool by hand / park it | - |
| `session:ask` | ask without blocking: questions doc in Russian, Plannotator in the background, continue on reversible defaults (the model may invoke this one) | - |

Default for day-to-day work (decided 2026-09-04 after the tests): `session:forks`. One
context, no relay chatter, zero misses measured; team modes cost N notification turns
per keep-warm cycle and hide the stage flow in messages. Next targets: peers (mode 4)
and then a workflow over peers (mode 8 with peer sessions instead of teammates: the
workflow script is the visible pipeline, each `agent()` a cheap proxy that hands its
stage to a warm peer by role/model and returns a result file; the pieces were measured
today: SendMessage + file handoff, peers wake with their cache, proxy stage ≈ $0.07-0.15).

Mode 9 (`session:pool-workflow`) is the workflow-over-peers target above, built on a
separate daemon (`pool/poold.py`) instead of teammates; see "Mode 9 — Pool".

Deferred, not in the plugin yet: peers (mode 4, started by hand), delegate (mode 6, plain
subagents with role agents), workflow (mode 7) and workflow over a team (mode 8), codex.

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
| Teammate effort | a tmux teammate inherits the lead's `--effort`; an agent file's `effort:` does not reach it (the `model:` pin does); `/effort <level>` typed into its pane works (confirm dialog needs a second Enter) and so does `/model <full id>`; both are saved as the account default in `~/.claude/settings.json`, so team-compact restores the recorded defaults |
| Fork subagent | inherits the parent's model AND effort, cannot override either; measured (10 forks, 2026-09-04): first turn reads the parent's full prefix (120K-350K read, 0.1-5K written, into the parent's 1h bucket), every later turn writes into the 5m bucket; a fork that waits over 5 minutes in one call rewrites its own suffix on the next turn (the parent prefix stays cached); a cron created by a fork fires in the main session, never in the fork; a parent `/effort` change propagates to running forks (docs) |
| Plain subagent | fresh context, measured 60K written on the first turn (general-purpose); model (and, per docs, effort) via agent frontmatter; workflow `agent()` opts always honoured; with `subagentPromptCacheTtl: "1h"` the whole 60K lands in the 1h bucket (measured), without it in the 5m bucket |
| Teammate | with `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` a *named* plain Agent spawn is an in-process teammate (`taskKind: in_process_teammate`, transcript under `<session>/subagents/agent-a<name>-*.jsonl`): fresh context, measured 69K written on the first turn in the **5m** bucket, stays alive and answers SendMessage; it has the Agent tool and can spawn its own forks (measured). `name` + `subagent_type: fork` does NOT make a teammate: it is a one-shot fork that exits after its task. With `teammateMode: "tmux"` the teammate is a separate `claude` process in a tmux pane with its own session file, and its writes land in the **1h** bucket (measured: 54K + 13K on start) regardless of `subagentPromptCacheTtl` |
| Teammate pings wake the lead | every teammate turn ends with an idle notification that is delivered to the lead as a turn: a teammate's `pong` to its own cron costs the lead one cache read of its whole context (measured: ~518K read, ≈ $0.14 on a fable lead; ≈ $0.02 on a fresh 85K lead). With 30-minute pings ≈ $0.28/h per teammate on a fat lead. A lead-driven `ping all teammates` is worse (1 + N lead turns per cycle) and no setting suppresses the notifications, so teammates keep their own crons and the lead drops its own cron once the team is up (the notifications keep it warm): floor = 2N turns per cycle; the levers are a small lead context (forks, short replies), light over full, and `team-compact` for long idle periods |
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

## Mode 1 — Single (`session:single`)

One session, no agents. The cheapest mode per unit of work: every turn is a cache read
plus the new tokens.

- Fits: conversation, analysis, small and medium edits, anything under a few hundred tool
  calls.
- Limit: tool results pile up in the one context; around 1000 tool calls the session needs
  a compact, which resets the cache.
- Setup: cron `ping` every 30 minutes (the skill creates it).

## Mode 2 — Forks (`session:forks`)

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

## Mode 3 — Team (`session:team`)

One main session plus 3-5 named teammates with fixed roles (reviewer, author, fixer,
researcher, executor), each with its own model and effort, each reused across rounds
without clearing. The main session hands out subtasks and merges results; the teammates
keep their warmed context, so the second and later rounds are cheap.

- Fits: large tasks with repeated review/fix cycles, multi-model work (fable reviewer,
  opus fixer, sonnet executor), anything that would need thousands of tool calls in total.
- Limits: 3-5 session starts up front (≈ 85K written each); every teammate must be kept
  warm; coordination goes through messages and the shared task list, so the main session
  spends tokens on orchestration.
- Measured: in-process teammates (`teammateMode: "in-process"`) start with a fresh 69K
  context in the 5m bucket; tmux teammates (`teammateMode: "tmux"`) are separate sessions
  on the 1h bucket. So a team runs with `teammateMode: "tmux"`: teammates keep the 1h
  cache like the main session, while `subagentPromptCacheTtl` can stay at 5m for the
  cheap-write forks and plain subagents. Keep-warm ping per teammate is still needed.
  A named fork is not a teammate: it runs once and exits.
- Setup: spawn the roles first, then a ping cron in each (the spawn message asks for
  it), then start dispatching.
- Tool limits (2026-09-04): the `Agent` tool takes only model aliases (`opus`, `sonnet`,
  `fable`), no effort; the skill pins the 1M id and the effort by typing `/model` and
  `/effort` into the teammate's tmux pane. Teammate panes have no status line. tmux
  teammates do not need the session to run inside tmux: Claude Code opens a private
  server (`tmux -L claude-swarm-<pid>`; `tmux ls` on the default server shows nothing).
  Only a *detached test session on macOS* fails with `respawn pane failed: fork failed:
  Device not configured` (attach a pty client first); Linux needs no client. Every teammate reply lands in the main context: a full team of six on a
  small task cost ≈ $10 (main $3.9 of it, 6.9M cache-read tokens from 8 exchanges),
  so replies are kept to "DONE + 5 lines".

### Light and full, by role or by domain

- A new team starts with recon in forks style (the class is only known after looking
  at the task); the team is spawned once the class and sub-mode are agreed.
- **Light**: one teammate per unique model+effort combo of the selection-map row for the
  task class, minus the main session's own combo (the main session does those roles
  itself). Class 3 with a fable-low main: main = reviewer, teammates `opus-medium`
  (plan author, fixer) and `opus-low` (author, researcher, executor). Fewest sessions.
- **Full**: one teammate per role the task needs, equal combos not merged; the main
  session only drives the stages. More starts, more total context before a compact.

Inside full, two ways to cut the crew:

- **By role** (reviewer, author, fixer, researcher, executor): the default. Each teammate
  keeps the process knowledge of its role; models and efforts follow the selection map
  (reviewer-grade model for reviewer and plan roles, cheaper executor family for the
  rest). Good when the task moves through stages.
- **By domain or stack** (e.g. `api`, `billing`, `helm-chart`, `frontend`; or Go
  backend, Angular, k8s/ArgoCD, Jira/GitLab process): each teammate warms up the code,
  docs and conventions of one area once and answers every question about it for the rest
  of the day. Good when the task cuts across several services or when the same area is
  hit many times; a domain teammate that also reviews its own area saves the reviewer
  from re-reading the code.
- **Mixed**: a small role core (one reviewer, one fixer) plus domain specialists as
  authors/researchers. The main session routes by area first, then by role.
  Domain teammates fit the file handoff (see Team compact) especially well: their context
  file is a reusable area briefing, not a task state.

## Mode 4 — Peer sessions

Next mode to build (decided 2026-09-04). Why: in team modes every teammate turn ends
with an idle notification that costs the lead a full context read, so an opus lead
with N teammates pays N × (lead read) per keep-warm cycle on top of the teammates'
own reads. Peers have no lead in the protocol: each is a full session with its own
cron, messages go through `SendMessage` to a local session (measured: the peer wakes
with its cache intact), and nothing is relayed. Design to do: the coordinating
session spawns peers itself (`tmux new-session -d "claude --model <id> --effort <x>"`
plus a typed briefing, so model and effort are set at start and no account default
changes), names them by role/combination, keeps a manifest like `team.md`, hands out
stages by message, parks them with the same file protocol; check whether
cross-session messages need approval in auto mode, and how a peer reports back
without a lead notification (reply message, or a result file).


3-5 independent sessions started by hand (tmux or `claude agents`), no main session, work
passed between them with SendMessage / ListAgents ("other local Claude sessions on this
machine").

- Fits: long-running roles that outlive any single task.
- Measured: a SendMessage from one session to another local session wakes the idle peer
  and it answers with its cache intact. So peers can relay work between themselves; what
  is missing is only a scheduler, which the sending session provides by its own prompts.
- Setup: each session starts its own `/loop 30m ping`.

## Mode 5 — Team + forks (`session:team-forks`)

Mode 3 where each teammate does its heavy lifting through its own fork subagents. The
teammate keeps a small, warm context; the forks absorb the tool-call volume at the
teammate's model and effort and read the teammate's cached prefix when they start.

- Fits: the biggest tasks: a multi-model role pool that almost never rewrites its cache.
- Limits: two levels of delegation to instruct (main → teammate → fork); more moving parts
  to keep warm. Works as intended only with `teammateMode: "tmux"` (1h teammates); the
  forks then write at the cheap 5m rate and read the teammate's prefix.
- Measured: a teammate has the Agent tool and spawned a fork on request (the fork ran
  `date` and the teammate relayed the result). Plain subagents cannot nest.
- Setup: as Mode 3, plus a standing instruction in each teammate's prompt: "run every
  multi-step piece of work in a fork; keep your own context for coordination".

## Mode 6 — Delegate

One lean main session plus fresh plain subagents per job, with model and effort chosen per
subagent (custom agent types or workflow-style opts). The main session stays small and
warm; each subagent pays its own start (35-50K written, 5m bucket) and is thrown away.

- Fits: many unrelated small jobs, jobs that need a clean context, jobs on a cheaper
  model than the main session.
- Limits: start overhead per subagent; results come back as text only; with the default
  5m TTL a subagent that waits (network, long build) loses its cache.
- Setup: `/loop 30m ping` in the main session; `subagentPromptCacheTtl: "1h"` moves the
  subagent writes into the 1h bucket (measured: 60K in 1h with the key, 5m without).

## Mode 7 — Workflow

Dynamic workflows (`Workflow` tool): deterministic pipelines of fresh agents with explicit
model and effort per `agent()`, progress UI, resume from a run id. Every agent is a clean
context, so a 10-15 agent cycle pays 10-15 starts.

- Fits: formal multi-stage processes (plan → review → fix → verify → land), audits and
  sweeps, anything that must be reproducible and observable.
- Cache levers: agents of one fan-out with equal model/effort/tools share the first agent's
  prefix; `subagentPromptCacheTtl: "1h"` for agents that wait; resume replays finished
  agents from the journal instead of re-running them. There is no reuse of an agent across
  stages: the price of the mode is the start overhead, the gain is structure.
- Setup: `/loop 30m ping` in the main session; class and pairing in `meta.name` as usual.
- Lean stage agents (`session:workflow`, 2026-09-04): the plugin ships `stage-author`,
  `stage-reviewer`, `stage-executor`, `stage-researcher` with reduced tool sets and no
  model pin. Measured first turn: 12K written for a lean agent against 35K for the default
  workflow agent (23.6K of it the built-in tool schemas). The skill adds the convergence
  gate (review severity below medium ends the cycles) and the tool-output caps.

## Mode 8 — Workflow over a crew (proxy agents)

Mode 5 driven by a workflow script: the crew (tmux teammates, 1h cache, forks for volume)
does the work, the workflow only sequences it. Each `agent()` is a cheap proxy that hands
its stage to a teammate and returns the result, so the script keeps its pipeline shape,
review loops and resume while the tokens are spent in warm contexts.

Measured 2026-09-04 (sonnet):

- A workflow agent CAN `SendMessage` to a teammate and the teammate executes the task.
- The teammate's reply is routed to the **main session** (as a teammate-message), not to
  the workflow agent; a subagent cannot idle-wait, so a "wait for the reply" prompt ends
  with a stub result.
- Working handoff: the proxy tells the teammate to write its result to a file
  (`$TMPDIR` or the job tmp dir), then waits for that file with a bash until-loop
  (`for i in $(seq 1 36); do [ -s FILE ] && break; sleep 5; done`) and returns the file
  content. Verified end to end (`sw_vers` output came back as `FILE-RESULT:`).
- First read outside the cwd triggers a one-time "allow reads outside the working
  directories" dialog in the main session; answer it once (or keep the handoff files
  under the cwd).

Cost, measured on two sonnet proxies in a large monorepo project (JSONL usage, 5m bucket):

| | proxy 1 (cold) | proxy 2 (3 min later) |
|---|---|---|
| first-turn cache write | 60 247 | 35 552 (24 819 read from proxy 1's head) |
| later writes, total | ~9 900 | ~8 900 |
| cache reads, total | ~537 000 | ~358 000 |

At sonnet $2/MTok input (5m write 1.25x = $2.50/MTok, read $0.20/MTok): start write
$0.15 / $0.09, whole stage ≈ $0.29 / $0.18. Ten proxy stages ≈ $2-3. On the 1h bucket the
start would be $0.24, so keep subagents on 5m in this mode. Same start on opus
($5/MTok) ≈ $0.22-0.31, on haiku ($1/MTok) ≈ $0.07. Use the cheapest proxy that can
follow the protocol and keep the number of stages small; the heavy tool-call volume runs
on the teammate and its forks.
Not in the script API yet: no `agent()` option to target a teammate directly, and
workflows cannot spawn forks of the main session or of a teammate (no feature request
found in anthropics/claude-code as of 2026-09-04).

## Mode 9 — Pool (`session:pool-workflow`, `session:pool`, `session:pool-stop`)

Mode 8 without a team: a separate daemon (`poold`) runs a pool of plain `claude`
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

Two workflow rules that follow from the cost floor (in `session:pool-workflow`, and
valid for plain workflows too): a convergence gate (a review with no medium or high
findings ends the cycles; the fix and check stages of that cycle are skipped) and
tool-output caps in task files (reviewers get `git diff` since the previous stage,
not whole files; checkers return PASS/FAIL lines and the tail of failing output).

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

## Team compact (`session:team-compact`) and restore

Teammates are tied to the main session: when it exits, is killed, or the tmux server
dies, the team is gone. A team that spans days therefore parks itself in files.

1. Directory: `~/.claude/projects/<encoded-cwd>/team-compact/<stamp>-<slug>/`, next to
   the project's transcripts and memory, outside any repo. `<stamp>` = `YYYY-MM-DD-HHMM`,
   `<slug>` = 2-4 words about the work (`2026-09-05-1830-retry-logic-mr`); always a new
   directory.
2. The main session sends every teammate: "fold your context into `<dir>/<name>.md`:
   goal, current state, decisions, open items, files and commands you rely on, under
   300 lines; reply `DONE <path>`", and waits for every DONE.
3. It writes `<dir>/main.md` (its own state, same template) and `<dir>/team.md` (one-line
   recap, mode, sub-mode, class, and per teammate: name, roles, model, effort, file).
4. It stops the teammates, deletes the `ping` cron and tells the user the directory.

Restore is part of the start of `session:team` and `session:team-forks`: the skill lists
this project's compacts of the last 7 days (date + recap) in an AskUserQuestion menu with
a "new team" item; on restore it reads `main.md`, then `team.md`, spawns the same
teammates with the same full model ids and efforts, tells each to read its file first,
and restarts the pings. An explicit `<dir>` argument skips the menu.

Cost: the evening is output only (files); the morning is one clean start per session plus
one file read each. No cold read of a big history ever happens.

Main session, native `/compact` versus the file: see "Compact prices" below; the skill
uses the cheaper one.

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
inside the teammate, `pong`, team-compact with a time-stamped dir: main 52 turns and
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

## Roles, selection map and stages (used by `team`, `team-forks`, `forks`)

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

Full model ids for spawning teammates (always the 1M variant):

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

## Scores for a big task (~3000 tool calls, review/fix cycles, mixed roles)

1-10, higher is better on every column (cost 10 = cheapest).

| Mode | Cost | Quality | Context capacity | Control / observability | Setup effort | Total |
|---|---|---|---|---|---|---|
| 1 Single | 4 | 5 | 2 | 6 | 10 | 27 |
| 2 Forks | 8 | 6 | 6 | 5 | 9 | 34 |
| 3 Team (tmux teammates) | 6 | 8 | 7 | 6 | 5 | 32 |
| 4 Peer sessions | 7 | 7 | 7 | 3 | 3 | 27 |
| 5 Team + forks | 8 | 9 | 9 | 5 | 4 | 35 |
| 6 Delegate | 5 | 6 | 8 | 6 | 7 | 32 |
| 7 Workflow | 3 | 8 | 9 | 10 | 6 | 36 |
| 8 Workflow over a crew (proxy agents) | 6 | 9 | 9 | 9 | 3 | 36 |

Reading: cost + quality is best in mode 5 (17/20); mode 7 wins on audit trail and
reproducibility; mode 2 is the cheap default for medium tasks; mode 1 does not fit big
tasks because forced compacts each cost a full rewrite. Cost reasoning: solo pays several
compacts; forks pay no start and write at the 5m rate; crew pays 3-5 starts of 55-70K
then runs on reads; delegate pays ~60K per fresh subagent; workflow pays 35-50K per agent
times 10-15 agents per cycle.

## Choosing

| Task | Mode |
|---|---|
| chat, small edit, single-file fix | 1 Single |
| one task, parallel angles, same model is fine | 2 Forks |
| big task, review/fix cycles, mixed models | 3 Team, or 5 Team + forks |
| many small unrelated jobs, cheap model | 6 Delegate |
| formal, auditable multi-stage process | 7 Workflow |
| big task that also needs the audit trail | 8 Workflow over a crew |
| standing roles outliving tasks | 4 Peer sessions |

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
