# session plugin: modes of the main session

One user-invocable skill per mode. Start a session, pick the model and effort, run
`/session:base [no-sonnet] [no-opus] [no-fable] [c1..c5]` first (and again after `/compact`),
then optionally one mode skill on top. Source of the base is `base/BASE.md`; `base/split.sh`
regenerates `skills/base/SKILL.md`.

| skill | mode | spawns |
|---|---|---|
| `session:base` | every session: main + forks, delegation rules, classes and slots, waits, style | forks + `Workflow` for cold agents |
| `session:pipeline` | on top of the base: staged pipeline with gates (research, critic, decision, verification, implementation, closure); shared rules in `skills/pipeline/core.md` | forks + lean cold agents |
| `session:review` | on top of the base: verification-first review of someone else's MR | forks + cold researcher |
| `session:codex` | on top of the base: codex heavy axis (sol, astra) and executor axis (luna, terra) | `session:codex-proxy` one-agent workflows |
| `session:ask` | ask without blocking: options document, Plannotator in the background, continue on reversible defaults (model-invocable) | - |
| `session:reset-counter` | clears the statusline mode counters after a rewind (user only) | - |

## Agents

Lean cold agents, launched only through one-agent or multi-agent `Workflow` with `agentType: session:<name>`,
explicit model and effort, inputs by path. Frontmatter holds the c3 default.

| agent | model / effort | tools | returns |
|---|---|---|---|
| `artifact-publisher` | opus / medium | Artifact, Read, Write | `URL: <url>`, at most 40 words |
| `artifact-designer` | opus / medium | Artifact, DesignSync, Read, Write | `URL: <url>`, at most 40 words |
| `web-researcher` | sonnet / medium | WebFetch, WebSearch, Write | `FILE: <path>` plus a digest of at most 600 words with sources |
| `code-reviewer` | sonnet / high | Read, Bash | findings `file:line severity text`, at most 300 words, or `CLEAN` |
| `simplifier` | sonnet / medium | Read, Edit, Bash | one line per file plus the check result, at most 150 words |
| `security-reviewer` | sonnet / high | Read, Bash | findings `file:line severity text`, at most 300 words, or `CLEAN` |
| `stage-author` | opus / medium | Bash, Read, Edit, Write | plan or code author and fixer; diff summary |
| `stage-reviewer` | fable / low | Read, Write | document critique to a review file, 5 tool calls at medium, 3 at high |
| `stage-critic` | fable / low | Read, Write | clean-context critic of a framing and ledger |
| `stage-researcher` | sonnet / high | Bash, Read, Write | facts to a notes file |
| `stage-executor` | sonnet / high | Bash, Read | runs named commands, PASS/FAIL with decisive lines |
| `waiter` | sonnet / low | Bash, Read | long waits with judgment |
| `codex-proxy` | haiku / medium | Bash | runs one codex job by header block, returns a file path |

Only `code-reviewer` keeps a `skills:` preload (`code-review`); other skills reach an agent as a
resolved SKILL.md path in the prompt. Artifact and DesignSync are denied per project in
`.claude/settings.local.json`; remove the two entries and start a new session to publish.

## Classes, slots and submodes

The class comes from `/session:base` (default c3) and holds for the session; every workflow
takes one row. Main-model slot: document critique and generation (stage-reviewer, stage-critic).
Opus slot: authors and fixers (stage-author, simplifier, artifact agents). Sonnet slot: researchers,
executors, bulk code and security review, web research. Large input moves a role one slot down,
never up. Fixed: waiter sonnet-low; codex-proxy and claude-code-guide haiku-medium. Forks run on the
main session's model and effort.

| class | main-model slot (small input; document critique and generation) | opus slot (medium input; plan and code authors, fixers) | sonnet slot (large input; researchers, executors, bulk reviews) |
|---|---|---|---|
| c1 lowest | opus-low | opus-low | sonnet-low |
| c2 below default | fable-low | opus-low | sonnet-medium |
| c3 default | fable-low | opus-medium | sonnet-high |
| c4 above default | fable-medium | opus-high | sonnet-high |
| c5 highest | fable-high | opus-high | opus-high |

Submodes rewrite the row (cells main / opus / sonnet; all three at once is an error):

| class | none | no-sonnet | no-opus | no-fable | no-sonnet no-opus | no-sonnet no-fable | no-opus no-fable |
|---|---|---|---|---|---|---|---|
| c1 | ops-lo / ops-lo / son-lo | ops-lo / ops-lo / ops-lo | son-me / son-me / son-lo | ops-lo / ops-lo / son-lo | fab-lo / fab-lo / fab-lo | ops-lo / ops-lo / ops-lo | son-me / son-me / son-lo |
| c2 | fab-lo / ops-lo / son-me | fab-lo / ops-lo / ops-lo | fab-lo / son-me / son-me | ops-me / ops-lo / son-me | fab-lo / fab-lo / fab-lo | ops-me / ops-lo / ops-lo | son-me / son-me / son-me |
| c3 | fab-lo / ops-me / son-hi | fab-lo / ops-me / ops-me | fab-lo / son-hi / son-hi | ops-me / ops-me / son-hi | fab-lo / fab-me / fab-me | ops-me / ops-me / ops-me | son-me / son-hi / son-hi |
| c4 | fab-me / ops-hi / son-hi | fab-me / ops-hi / ops-me | fab-me / fab-me / son-hi | ops-hi / ops-hi / son-hi | fab-me / fab-me / fab-me | ops-hi / ops-hi / ops-me | son-hi / son-hi / son-hi |
| c5 | fab-hi / ops-hi / ops-hi | fab-hi / ops-hi / ops-hi | fab-hi / fab-me / fab-me | ops-hi / ops-hi / ops-hi | fab-hi / fab-me / fab-me | ops-hi / ops-hi / ops-hi | son-hi / son-hi / son-hi |

## Named workflows (0.14.0)

Scripts under `workflows/`, launched by name (`session:dev`, `session:review-fix`, `session:build`,
`session:research`) with `args`; the meta description is the contract, the body is never read by
the caller. Shared block in every script: the 35-cell class table, `args.class` (default c3) and
`args.submodes` pick the row, `opts(slot, job)` turns a slot into explicit `model`, `effort` and a
`<mod>-<eff>-<job>` label. `args.cwd` is required; outputs go to `args.out` (default `<cwd>/reviews`).
A `null` or `BLOCKED:` stage result ends the run with a report; reviewers end with `VERDICT: clean`
or `VERDICT: findings`, which drives the 1-3 review-fix cycles.
Skill injection is prompt-time: `skillLine()` in each script adds `~/.claude/skills/<name>/SKILL.md`
paths to a stage prompt only when the args touch that domain (`transcripts-jsonl` for researchers on
transcripts, `tmux-sessions` for tmux test commands, `workflow-reliability` for workflow tasks,
`shell-gotchas` for `.sh` inputs); otherwise the prompt says "No skills needed for this step". No
agent preloads a skill in frontmatter.

| workflow | stages | args | agents |
|---|---|---|---|
| `dev` | plan, plan critique+fix (1-3), red tests + review (1-2), implement + code review + tests + fix (1-3), closure + review | `cwd, task, paths (array), test, class, submodes (array), out` | stage-author (opus slot), stage-reviewer (main), code-reviewer and stage-executor (sonnet) |
| `review-fix` | code review, evidence check, fix, tests; 1-3 cycles (1 when `fix: false`) | `cwd, target (diff file / a..b / worktree), test, fix, class, submodes (array), out` | code-reviewer (findings returned inline), stage-researcher (sonnet), stage-author (opus) |
| `build` | implement a plan, code review + tests + fix (1-3) | `cwd, plan, test, class, submodes (array), out` | stage-author (opus), code-reviewer and stage-executor (sonnet) |
| `research` | parallel researchers by direction, critique, synthesis | `cwd, question, directions (array), paths (array), class, submodes (array), out` | stage-researcher (sonnet), stage-critic (main), stage-author (opus) |


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


## Compact prices

- Warm compact (cache alive): the compact call reads the whole context at the cache-read
  rate and pays for the summary output, a near-fixed $0.1-0.2 on sonnet whatever the size
  (188K: ≈ $0.09; 80K: ≈ $0.17). The next turn after it reads ~43K and writes ~25K.
- Cold compact: the whole history at the input rate. 460K: $1.30 sonnet, $5.87 fable.
- Cold big session on fable: `/model sonnet` (free, cache dead anyway), `/compact`,
  `/model` back (small reset), restore the settings.json default afterwards.
- The compact call leaves no usage entry in the JSONL; its cost is the status-line delta

## Description limits

Skill description: 100 tokens. Agent description: 100 tokens. Workflow `meta.description`: 200 tokens, every arg named with its type (string, absolute path, array of strings, boolean) and default.

## Workflow args and outputs

Details trimmed from `meta.description`; classes and submodes are described in "Classes, slots and submodes".

### dev

Defaults: `class` c3, `submodes` `[]`, `paths` `[]`, `test` the command decided in the plan, `out` `<cwd>/reviews`.
Outputs: `plan.md`, review files and the closure review under `out`; working-tree changes, no commit.
Stop conditions: plan critique-fix, red-test review and implementation review each run 1-3 rounds; a BLOCKED stage stops the run with a report.

### build

Defaults: `class` c3, `submodes` `[]`, `test` the plan's "Test command", `out` `<cwd>/reviews`.
Outputs: working-tree changes (no commit), `code-review-N.md` and `tests-N.md` under `out`.
Stop conditions: 1-3 author/review/test cycles until clean and green; a BLOCKED stage stops the run with a report.

### research

Defaults: `directions` `[question]`, `paths` `[]`, `class` c3, `submodes` `[]`, `out` `<cwd>/reviews`.
Outputs: `notes-N.md` per direction, `critique.md`, `research.md` under `out`. Read-only, no file in the repo is changed.
Stop conditions: every direction BLOCKED stops the run with a report.

### review-fix

Defaults: `target` `worktree`, `class` c3, `submodes` `[]`, `test` none, `out` `<cwd>/reviews`, `fix` true.
Outputs: `evidence-N.md` and `tests-N.md` under `out`; fixes in the working tree when `fix` is true.
Stop conditions: 1-3 review/evidence/fix cycles until clean; a BLOCKED stage stops the run with a report.

## Session mode counters

`hooks/session-modes.sh` writes `~/.claude/session-modes/<session_id>.json`: a JSON object keyed by
skill name holding the string to render (`{"base":"base-c3","codex":"codex+astra"}`). Written on a
user-typed `/session:<mode> <args>` (UserPromptSubmit) or a model-invoked one (PostToolUse on Skill);
cleared on PreCompact and SessionStart (resume keeps it); files older than seven days pruned. A
statusline reads it by `session_id`; `/session:reset-counter` clears it after a rewind. State, not an API.

## Version log

0.15.1: chat replies in A2 English (word list, grammar, verbatim identifiers) in the base Language section; caveman uses common synonyms.
0.15.2: self-ping rule for long commands in every Bash-capable agent (detach, then `sleep 180` per turn; no background job at turn end).
0.15.3: every synchronous Bash call in an agent sets `timeout` ≤ 120000; commands that may run over 2 minutes run detached only.
0.15.4: the self-ping is a 30-second step loop (`for i in $(seq 6); do test -f <done> && break; sleep 30; done`), so a finished job is noticed within 30 s; background jobs write their own done-file.
0.15.5: poll step 5 seconds (`for i in $(seq 36); do test -f <done> && break; sleep 5; done`); a finished job is noticed within 5 s.
0.15.6: base "Skill first, then delegate" bullet (transcripts-jsonl, shell-gotchas, workflow-reliability, harness-cost, tmux-sessions); tests/measure: S1-S9 scenarios for the 0.15 assets, driver env matrix (MODEL EFFORT CWD OUT REPEAT IDS), parser S3 scans script files only.
0.15.7: shorter workflow descriptions; README documents workflow args; plugin-dev workflows (test-session, skill-author, memory-gc) tracked in .claude/workflows/.
0.15.13: workflow slot tables match the base table (c3 no-sonnet no-opus fab-lo/fab-lo/fab-lo, c4 fab-me/fab-me/fab-lo) in the four plugin workflows and the three project workflows.
0.15.12: base keep-warm pings are four scheduled background Bash jobs (57 min apart, re-armed from the last live job, no target after 23:59, the one before it at 23:03 or earlier); monitors.json `when` is `on-skill-invoke:session:base`.
0.15.11: `/session:stop-ping` pauses the ping (pause file per session, monitor keeps running), `/session:resume-ping` resumes; status line shows `base+ping` or `base+ping(paused)`.
0.15.10: keep-warm ping as plugin monitor `keep-warm-ping` (starts on /session:base, 57 min, stop file per session) with `/session:stop-ping`; base no longer launches ping jobs.
0.15.9: substitution rule sentence dropped from base, the table alone carries the cells.
0.15.8: submode substitution shifts effort one step per model tier (c3 and c4 no-sonnet no-opus cells fixed); keep-warm via four background Bash sleeps, Monitor cap 30 min.
0.15.0: prompt-time skill injection (`skillLine`) in the four workflows; `code-reviewer` no longer names the bundled `code-review` skill (frontmatter cannot preload bundled skills); base lists the five user skills.
0.14.6: agent descriptions under 100 tokens, workflow descriptions type every arg (limit 200 tokens).
0.14.5: every skill and workflow description under 100 tokens; whenToUse under 25 words.
0.14.4: every named workflow logs `c<class>[-<submodes>]-<name>` plus its launch args as its first line; base scopes the `meta.name` class rule to ad hoc scripts.
0.14.3: workflow descriptions name the array args (`directions`, `paths`, `submodes`); a string `paths` crashed `research` on `.join`.
0.14.2: base hard rule 7 (caveman, no narration), research requests to `session:research` by name, fork prefix rule in one sentence; workflow `review` renamed `review-fix` (name clash with the skill), its reviewer returns findings inline instead of a file; test parser fixed.
0.14.1: README cut to the contract sections (old text in `docs/history-README-2026-09-12.md`), `base/skill-routing.md` and `session-map.example.md` deleted, plugin and ask descriptions shortened, stale base pointers in the pipeline, review and codex skills inlined.
0.10.0 agents for heavy work (the main session keeps the lean tool set, one-agent `Workflow`
0.14.0: named workflows `dev`, `review`, `build`, `research` under `workflows/` (section "Named workflows"); agents and skills trimmed (5c73790); base prefers named workflows and lean agent types (1b0afad).
0.13.0: base trimmed to the rules used in most sessions: fork threshold 20 lines, tests never in a fork, one class/submode table, no codex, pipeline, skill-map or fork-template text, no history notes; caveman block unchanged.
0.12.1: chat replies English only, no Russian recap and no `---` two-part structure anywhere; a Russian recap of the last message is a separate reply on the user's request; the AskUserQuestion-in-Russian rule dropped.
0.12.0: the caveman ultra rules live inline in the base ("Style" section) instead of a runtime path resolve and Read of the caveman plugin file; a "Language" section (English body + Russian recap, full Russian only on the user's explicit request, English-only traffic with forks and agents); the base text cut by about a third with no rule, number, table cell, template or command changed.
0.11.0: delegation threshold 2 tool calls (was 3), a fork prompt under 100 tokens and a workflow agent prompt of 300-1000 tokens, workflow preferred over fork, slot by input volume (small main-model / medium opus / large sonnet), five classes as three slots (c3 default fable-low + opus-medium + sonnet-high), submodes `no-sonnet` / `no-opus` / `no-fable` with a fixed 35-cell table, `/session:base [submodes] [c1..c5]` in any order (`session:base sonnet` is now `no-fable no-opus`), agent frontmatter carries the c3 defaults, the pairing maps and `~/.claude/session-map.md` are no longer read; keep-warm monitor every 57 minutes (`sleep 3420`) instead of 59, which missed the one-hour cache window too often.
0.10.3: base reads the caveman plugin's ruleset by path at start (ultra level); plugin disabled, no hook injection (the SessionStart hook injected 5220 bytes as hidden context, which the model followed poorly). If the file is missing the reply line says `no style file` and the session continues without one.
0.10.2: agent tool sets cut to the role minimum (codex-proxy Bash only; artifact agents without Bash, text inputs only; web-researcher without Read; stage agents without Grep, Glob, ToolSearch, WebFetch), dead `skills:` preloads removed (the skills are off by `skillOverrides`, their rules stay inlined; re-adding a skill means re-adding the line), codex-proxy body trimmed from 15.8K to 6.7K chars with the permission-set rationale moved below, stage agents read skill files by path (no `Skill` tool in any plugin agent).
0.10.1: dropped unstable pool tooling and dead skills: `session:pool-workflow-unstable`, `session:pool-unstable`, `session:pool-stop-unstable`, the `pool-proxy` agent, the `pool/` daemon and CLI, and the user agent `spec-critic`.
0.10.0: agent descriptions trimmed to 50-100 tokens (details moved into the agent bodies), six new lean agents for heavy work (artifact-publisher, artifact-designer, web-researcher, code-reviewer, simplifier, security-reviewer), `session:reset-counter` hidden from the model, per-project Artifact and DesignSync deny toggle documented.
0.9.1: the keep-warm ping is a `Monitor` instead of a cron: one `ping` event every 59
0.9.0: `/session:base sonnet` runs the session without opus: every opus slot (opus-low downscale, opus-medium / opus-high upscale, map rows) goes to sonnet-high, cheap slots stay sonnet-low, pairing `sonnet`. The main session may run any model (sonnet high included); forks copy its model and effort; early fact gathering goes to forks, bulk jobs to lean agents.
0.8.4: response style (caveman ultra) stated in the base for every chat reply of the main session; the caveman plugin stays optional.
0.8.3: main-session conduct (chat reply format, waiting on the user, claude-code-guide routing, tmux test sessions) and the bundled-skills routing map (`base/skill-routing.md`) moved into the base from the global CLAUDE.md.
0.8.2: the base gains "Decision points" (when a downscale or upscale agent fires; minimum per code task: plan critique, closure review, test-suite job); the codex wrapper runs detached (`--detach <done-file>`), the shim polls the done-file, no second codex run for a job in flight.
0.8.1: the start block loads deferred tools (`CronCreate` and the others the base names) with `ToolSearch` before the first call; the codex exchange directory outside a task dir is per session (`$TMPDIR/codex-<date>-<cwd basename>/codex/`).

History, measurements and the retired modes: `docs/history-README-2026-09-12.md` at the repo root.
