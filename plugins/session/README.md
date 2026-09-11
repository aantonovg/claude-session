# session plugin: modes of the main session

One user-invocable skill per mode. Start a session, pick the model and effort, then run
`/session:<mode>`; the skill states the rules of the mode, starts the keep-warm monitor and
says what the session may and may not spawn. This README is the reference behind the
skills: read it before changing any of them.

| skill | mode | spawns |
|---|---|---|
| `session:base [sonnet]` (`skills/base/SKILL.md` from `base/BASE.md`; invoked first in every session and after `/compact`; no base hooks, 0.8.0; `sonnet` argument = sonnet-only session, 0.9.0) | every session: main + fork subagents, launch forms, cache and wait rules, models, efforts, roles, intelligence up/downscale (the August workflow rules folded in, 2026-09-06) | forks + `Workflow` for cold agents: downscale (sonnet-low / opus-low, luna / terra), upscale (opus/fable medium/high, sol / astra), waiter (0.7.2) |
| `session:pipeline` | on top of the base: a staged pipeline with gates (research, critic, decision, verification, implementation, closure check); shared rules in `skills/pipeline/core.md` | forks + lean cold critic (and cold researcher) |
| `session:review` | on top of the base: verification-first review of someone else's MR (reads `skills/pipeline/core.md`) | forks + cold researcher |
| `session:codex` | on top of the base (pipeline or review may also be on): codex heavy axis (sol, astra) and executor axis (luna, terra) | `session:codex-proxy` one-agent workflows (agent, wrapper and style ship with the plugin) |
| `session:ask` | ask without blocking: questions doc in Russian, Plannotator in the background, continue on reversible defaults (the model may invoke this one) | - |

Loading order (2026-09-06, 0.8.0): the user invokes `/session:base` as the first prompt
of every session and again after `/compact`; then `/session:pipeline` (implementing
something) or `/session:review` (someone else's MR); then, optionally,
`/session:codex <mode>`. `session:workflow` and `session:forks` were folded into the base the same day.

## Base as a skill (0.8.0)

0.10.0 agents for heavy work (the main session keeps the lean tool set, one-agent `Workflow`
launches with `agentType: session:<name>`, inputs by path):

| agent | model / effort | tools | returns |
|---|---|---|---|
| `artifact-publisher` | opus / medium | Artifact, Read, Write | `URL: <url>`, at most 40 words |
| `artifact-designer` | opus / medium | Artifact, DesignSync, Read, Write | `URL: <url>`, at most 40 words |
| `web-researcher` | sonnet / medium | WebFetch, WebSearch, Write | `FILE: <path>` plus a digest of at most 600 words with sources |
| `code-reviewer` | sonnet / high | Read, Bash | findings `file:line severity text`, at most 300 words, or `CLEAN` |
| `simplifier` | sonnet / medium | Read, Edit, Bash | one line per file plus the check result, at most 150 words |
| `security-reviewer` | sonnet / high | Read, Bash | findings `file:line severity text`, at most 300 words, or `CLEAN` |

Only `code-reviewer` keeps a `skills:` preload (`code-review`, the one skill still on); the
other agents carry their rules inline because their skills are `off` in the user
`skillOverrides` and a preload of an off skill is silently skipped. Any other skill reaches an
agent as a resolved SKILL.md path in the launch prompt (rule in the base, fork prompt template).

Artifact toggle: Artifact and DesignSync are denied per project (`permissions.deny` in
`.claude/settings.local.json` of every directory under `~/projects`, git-ignored). To publish
from a project: remove the two entries from that project's local file, start a new session,
launch `artifact-publisher` or `artifact-designer`, put the entries back. Measured 2026-09-11:
a deny edit is picked up by a running session at its next request and rewrites the whole
prompt cache of that session (cache_read 0, about 16K smaller), so edit the file before
starting the session you need it in, not while warm sessions run in that folder.

0.11.0: delegation threshold 2 tool calls (was 3), a fork prompt under 100 tokens and a workflow agent prompt of 300-1000 tokens, workflow preferred over fork, slot by input volume (small main-model / medium opus / large sonnet), five classes as three slots (c3 default fable-low + opus-medium + sonnet-high), submodes `no-sonnet` / `no-opus` / `no-fable` with a fixed 35-cell table, `/session:base [submodes] [c1..c5]` in any order (`session:base sonnet` is now `no-fable no-opus`), agent frontmatter carries the c3 defaults, the pairing maps and `~/.claude/session-map.md` are no longer read; keep-warm monitor every 57 minutes (`sleep 3420`) instead of 59, which missed the one-hour cache window too often.
0.10.3: base reads the caveman plugin's ruleset by path at start (ultra level); plugin disabled, no hook injection (the SessionStart hook injected 5220 bytes as hidden context, which the model followed poorly). If the file is missing the reply line says `no style file` and the session continues without one.

0.10.2: agent tool sets cut to the role minimum (codex-proxy Bash only; artifact agents without Bash, text inputs only; web-researcher without Read; stage agents without Grep, Glob, ToolSearch, WebFetch), dead `skills:` preloads removed (the skills are off by `skillOverrides`, their rules stay inlined; re-adding a skill means re-adding the line), codex-proxy body trimmed from 15.8K to 6.7K chars with the permission-set rationale moved below, stage agents read skill files by path (no `Skill` tool in any plugin agent).

0.10.1: dropped unstable pool tooling and dead skills: `session:pool-workflow-unstable`, `session:pool-unstable`, `session:pool-stop-unstable`, the `pool-proxy` agent, the `pool/` daemon and CLI, and the user agent `spec-critic`.

0.10.0: agent descriptions trimmed to 50-100 tokens (details moved into the agent bodies), six new lean agents for heavy work (artifact-publisher, artifact-designer, web-researcher, code-reviewer, simplifier, security-reviewer), `session:reset-counter` hidden from the model, per-project Artifact and DesignSync deny toggle documented.

0.9.1: the keep-warm ping is a `Monitor` instead of a cron: one `ping` event every 59
minutes, just under the 1-hour prompt-cache TTL, so a long session pays half the ping
turns of the old 30-minute cron. The base loads `Monitor` as its deferred tool, the reply
line names a task id, and a `ping` is answered with `pong` whether it arrives as a
monitor event or as a user message. Teammate sessions keep their own crons.

0.9.0: `/session:base sonnet` runs the session without opus: every opus slot (opus-low downscale, opus-medium / opus-high upscale, map rows) goes to sonnet-high, cheap slots stay sonnet-low, pairing `sonnet`. The main session may run any model (sonnet high included); forks copy its model and effort; early fact gathering goes to forks, bulk jobs to lean agents.
0.8.4: response style (caveman ultra) stated in the base for every chat reply of the main session; the caveman plugin stays optional.
0.8.3: main-session conduct (chat reply format, waiting on the user, claude-code-guide routing, tmux test sessions) and the bundled-skills routing map (`base/skill-routing.md`) moved into the base from the global CLAUDE.md.
0.8.2: the base gains "Decision points" (when a downscale or upscale agent fires; minimum per code task: plan critique, closure review, test-suite job); the codex wrapper runs detached (`--detach <done-file>`), the shim polls the done-file, no second codex run for a job in flight.

0.8.1: the start block loads deferred tools (`CronCreate` and the others the base names) with `ToolSearch` before the first call; the codex exchange directory outside a task dir is per session (`$TMPDIR/codex-<date>-<cwd basename>/codex/`).

Cold agents get the output-style rules (plain English, caveman ultra) in their agent definition, section "Output style"; no SubagentStart hook.

codex-proxy ships with the plugin (0.8.0): `agents/codex-proxy.md`, the logging wrapper
`bin/codex-exec-logged.sh` and the style file `bin/codex-style.md` that the wrapper
prepends to every codex prompt on stdin. Launch with `agentType: 'session:codex-proxy'`;
the agent resolves the wrapper from the newest installed plugin version (fallback: the
source checkout, then a legacy `~/.claude/bin`). A user-level `~/.claude/agents/codex-proxy.md`
is no longer needed.

The base is the skill `/session:base` (`skills/base/SKILL.md`, generated from
`base/BASE.md` by `base/split.sh`). Invoke it as the first prompt of every session and
again after `/compact`; then `/session:pipeline`, `/session:review` or
`/session:codex <mode>` as needed. The plugin ships no base hooks: nothing is injected
at session start or per prompt; the base reaches the main session and its forks only
through the invocation.

Measured 2026-09-06 (batch c, 6 base-family runs on opus-low, base delivered only by
`SessionStart` hooks as a user-turn attachment): 4 of 6 runs skipped the start block (no
cron, no reply line, no `Workflow`); the pipeline runs, whose rules came from a typed
`/session:pipeline`, followed them. Two runs with a 1.4K kernel appended to the system
prompt (`--append-system-prompt-file`) followed the start block 2 of 2; that route has no
settings key and is not distributed by the plugin, so 0.8.0 uses the skill instead. Cache:
two `ping` sessions 30 s apart reused only the system prompt (26.6K read, 29K written);
hook text in the first turn is rewritten per session while the Remote Control attachment
carries a per-session URL. `tests/demo-game/launch.sh` sends `/session:base` first in
every mode.

Default for day-to-day work (decided 2026-09-04 after the tests): the base alone (forks). One
context, no relay chatter, zero misses measured. `session:pipeline` adds the staged
process on top of it (2026-09-05).

Removed 2026-09-05 (single, team light/full, team-forks, team-compact, workflow with lean
stage agents): the modes fell behind and are not used; their skills and README sections
live in git history before this change. Their measurements are kept below in
"Measurements (kept from removed modes)". Peers, delegate and workflow-over-a-crew were
never built; the pool (mode 9) was removed in 0.10.1.

Everything below follows from one fact: the prompt cache is the main cost lever on this
account, and Fable 5.1 makes the gap between a cache read and a cache write very wide.
Choose the mode by task size and by how many tool calls the work needs, then keep every
long-lived context warm.


## codex-proxy permission set

Moved out of `agents/codex-proxy.md` in 0.10.2. Every launch runs `codex exec` with the same
three settings: `-s workspace-write` (the sandbox: writes only inside the workspace, no
network), `-c approval_policy="on-request"` (codex asks before going beyond the sandbox) and
`-c approvals_reviewer="auto_review"` (those requests go to codex's built-in risk-based
reviewer, non-interactively; legacy alias `guardian_subagent`). The reviewer never weakens the
sandbox: beyond-sandbox capability comes only from per-command escalation, which the shim's
preamble tells codex to request when a command is denied (out-of-workspace write, network) or
silently broken (GUI and system-service commands such as `screencapture`, `xcrun simctl`,
`osascript`, `open`, which fail with "no display" or "service unavailable" inside the
sandbox). Verified on this machine under the preamble: out-of-workspace writes, HTTPS
requests, real screenshots and simulator listing all succeed via escalation. Forbidden for
every launch, whatever the task prompt asks: `-s danger-full-access`,
`--dangerously-bypass-approvals-and-sandbox`, `--dangerously-bypass-hook-trust` and any other
bypass. `codex exec` is non-interactive and has no `-a` flag; approval behaviour comes only
from the `-c` keys above. The wrapper (`bin/codex-exec-logged.sh`) adds `--json`, writes the
`-o` answer file, returns codex's exit code and appends one usage line to
`~/.codex/proxy-usage.jsonl`; on failure it prints to stderr only an events-file path and the
sequence of event types, never task content. In detached mode (`--detach <done-file>`) it
starts codex with nohup, prints the PID, and on exit writes the answer file, the ledger row
and the done-file (content = exit code) with stderr in `<done-file>.log`.

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
2. A keep-warm `ping` in every long-lived session: the main session runs a `Monitor`
   every 57 minutes, created by the base as its first tool call, just under the 1-hour
   cache TTL; teammates keep their own 30-minute crons, created from the spawn message.
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
talks to the user. Every job is a cold workflow agent: one class per workflow, stamped
with the submodes into `meta.name` (`c<class>[-<submodes>]-<slug>`), every `agent()` with
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
- Setup: a `ping` monitor every 57 minutes in the main session; forks need nothing.
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
  upscale agent, codex-proxy), one agent per single stage and ONE workflow
  (`parallel` / `pipeline`) for N independent cold agents, never N launches; no plain
  subagents. Measured 2026-09-06, same waiter agent both ways: agent cost identical
  ($0.136 per five sonnet agents, each reads 6.7K of its system prompt from cache and
  writes 8.5K); each separate completion notification is a full prefix re-read in the
  main session (≈ $0.13 on a 285K fable prefix); notifications landing together are
  batched by Claude Code.

## Mode 9 — Pool (removed in 0.10.1)

The warm-worker pool (`poold` daemon, `poolctl`, the `pool-proxy` agent and the three `pool-*-unstable` skills) was an unstable experiment and is gone since 0.10.1. Its design, measurements and gotchas live in git history up to commit `f0ee0b4`.

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
`session:stage-critic` (Read and Write only; model and effort from the main-model slot
of the class row, at most 5 tool calls at medium, 3 at high, label
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
executor axis and the upscale agent to the heavy axis, exchange directory
`$TMPDIR/codex-<date>/codex/`; the pipeline skill itself never mentions codex): two multiplied axes, heavy `none | sol
| astra | +sol | +astra` (critic, decision review only, document critique: `sol` / `astra` replace the Claude agent with that set only; `+sol` / `+astra` pair the Claude agent with the codex one at the same effort for review, merge fork, a high
finding in either fails the gate) × executor `none | luna | terra` (research sweeps, harness,
packages, mechanical checks: sonnet-low slots → luna-high, with terra also opus-low executor
slots → terra-high; executors have one effort). Heavy effort follows the stage's tool-call
budget: ≤5 calls pure reasoning → sol-medium / astra-medium, the hardest document gate, ≤3
calls → sol-high / astra-high; heavy models never review code (2026-09-06: sol-high
final code reviews read 300-470K tokens each; those runs count as failed). A stage stays on Claude when it needs MCP, repository edits under Claude
permissions, the pipeline's own artifacts or a skill; codex writes only into `<task
dir>/codex/` and `reviews/<stage>-codex.md`. Every codex stage is one `session:codex-proxy`
`agent()` with workflow opts `model: 'haiku', effort: 'medium'` (the opts win over the agent
file's own pin), header block only, prompt and
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

## Roles, classes and stages (used by `workflow`, `forks` and `pipeline`)

Six roles: **reviewer-debugger** (independent review of plans and code, root-causing
failures; the sonnet slot for a diff, the main-model slot for a document), **plan author/fixer** (writes the plan, applies review
findings to it), **code/test fixer** (applies review findings to code and tests),
**code/test author** (writes code and tests), **fact researcher** (collects facts, no
analysis), **test/script executor** (builds, tests, scripts, deploys; mistakes are loud).

Three slots, one row per class; the class comes from `/session:base [no-sonnet] [no-opus]
[no-fable] [c1..c5]` (default c3, any order, `/base` alias) and holds for the session. The
main session's own model and effort are independent of the class; a fork always runs on
the main session's model and effort. `~/.claude/session-map.md` and the pairing maps are
no longer read (0.11.0).

| class | main-model slot (small input; document critique and generation) | opus slot (medium input; plan and code authors, fixers) | sonnet slot (large input; researchers, executors, bulk reviews) |
|---|---|---|---|
| c1 lowest | opus-low | opus-low | sonnet-low |
| c2 below default | fable-low | opus-low | sonnet-medium |
| c3 default | fable-low | opus-medium | sonnet-high |
| c4 above default | fable-medium | opus-high | sonnet-high |
| c5 highest | fable-high | opus-high | opus-high |

Roles onto slots: reviewer-debugger of a document (stage-reviewer, stage-critic, c3 default fable-low) → main-model
slot; plan author/fixer, code/test author and fixer (stage-author, simplifier, artifact
agents) → opus slot; fact researcher, test/script executor, bulk code and security review,
web research (stage-researcher, stage-executor, code-reviewer, security-reviewer,
web-researcher) → sonnet slot. Large input moves a role one slot down, never up. Fixed:
waiter sonnet-low; codex-proxy and claude-code-guide haiku-medium. An upscale agent
(critique or generation of one document) is the main-model slot of the workflow's own
class; upscaling or downscaling is always the whole workflow at another class, chosen by
the user or by the main session with a one-line reason, never per stage.

Submodes rewrite the row; cells are main / opus / sonnet slot (`fab ops son`, `lo me hi`);
all three submodes at once is an argument error:

| class | none | no-sonnet | no-opus | no-fable | no-sonnet no-opus | no-sonnet no-fable | no-opus no-fable |
|---|---|---|---|---|---|---|---|
| c1 | ops-lo / ops-lo / son-lo | ops-lo / ops-lo / ops-lo | son-me / son-me / son-lo | ops-lo / ops-lo / son-lo | fab-lo / fab-lo / fab-lo | ops-lo / ops-lo / ops-lo | son-me / son-me / son-lo |
| c2 | fab-lo / ops-lo / son-me | fab-lo / ops-lo / ops-lo | fab-lo / son-me / son-me | ops-me / ops-lo / son-me | fab-lo / fab-lo / fab-lo | ops-me / ops-lo / ops-lo | son-me / son-me / son-me |
| c3 | fab-lo / ops-me / son-hi | fab-lo / ops-me / ops-me | fab-lo / son-hi / son-hi | ops-me / ops-me / son-hi | fab-lo / fab-me / fab-me | ops-me / ops-me / ops-me | son-me / son-hi / son-hi |
| c4 | fab-me / ops-hi / son-hi | fab-me / ops-hi / ops-me | fab-me / fab-me / son-hi | ops-hi / ops-hi / son-hi | fab-me / fab-me / fab-me | ops-hi / ops-hi / ops-me | son-hi / son-hi / son-hi |
| c5 | fab-hi / ops-hi / ops-hi | fab-hi / ops-hi / ops-hi | fab-hi / fab-me / fab-me | ops-hi / ops-hi / ops-hi | fab-hi / fab-me / fab-me | ops-hi / ops-hi / ops-hi | son-hi / son-hi / son-hi |

Agent frontmatter carries the c3 default (model, effort) as a fallback for direct
launches; every `agent()` still passes the effective values explicitly.

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
map (`base/skill-routing.md` in the plugin plus `~/.claude/memory-user/skill-routing.md` when present) and puts them at the end of the prompt
("Read these skill files with the Read tool before starting, in this order: <resolved SKILL.md
paths>." or "No skills needed for this step."). A plugin skill is resolved to the newest
installed version at launch (`ls -d ~/.claude/plugins/cache/<marketplace>/<plugin>/*/skills/<name>/SKILL.md | sort -V | tail -1`),
never a remembered path; a user skill is `~/.claude/skills/<name>/SKILL.md`; the agent skips the
YAML frontmatter and returns `BLOCKED: <path>` when the file is missing. Never `claude-api`,
never a superpowers orchestration skill.

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

## Session mode counters (`~/.claude/session-modes/<session_id>.json`)

The plugin records which of its modes are loaded in a session, so a statusline can show
them. The file is a small JSON object keyed by skill name, holding the string to render:
`{"base":"base","codex":"codex+astra","pipeline":"pipeline-full","review":"review-std"}`.
A key appears once its skill has been invoked; the last invocation wins.

`hooks/session-modes.sh` is the only writer, wired to four hooks of this plugin:
`UserPromptSubmit` records a user-typed `/session:<mode> <arg>` (prefix match on the first
line, invalid arguments ignored), `PostToolUse` on `Skill` records a model-invoked one,
and `PreCompact` and `SessionStart` clear the file, because after a compact the modes are
no longer loaded (a `resume` is the exception and keeps it). `SessionStart` also prunes
every file in the directory older than seven days.

The first prompt of a session with no `<session_id>.seeded` marker reads the first 256 KB
of the transcript once and replays the session commands found in user entries, so modes
typed before the hook ran still show. Every clear writes that marker, so nothing comes
back; `SessionStart(startup)` also removes it, because a fresh id may still need a seed.
The writer never prints and always exits 0.

Any consumer may read the file; it is state, not an API. The statusline in `user-prefs`
reads it by the `session_id` on its stdin and joins the values with `:`, showing nothing
when the file is missing. A rewind is invisible to the hooks, so `/session:reset-counter`
clears the file and the panel is rebuilt by hand.
