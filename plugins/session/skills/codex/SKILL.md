---
name: codex
description: Extra skill loaded on top of the session base; routes heavy roles and/or executor jobs to the codex stack (luna, terra, sol, astra) through the codex-proxy shim. Pipeline or review may also be on; then their stages are mapped as well.
disable-model-invocation: true
---

# Codex axis

Loaded on top of the session base; `session:pipeline` or `session:review` may also be on.
Those skills know nothing about codex. Only the agent running a job changes; jobs, gates,
files and ledger stay as defined by the base or by the pipeline / review skill.

A job is a fork job in the base, a stage in pipeline / review. The heavy axis replaces or
pairs the base's "heavy agent on request" and, when pipeline / review is on, their critic
and decision-review stages. The executor axis routes executor-kind fork jobs (repository
research, harness, package edits, mechanical checks) to `luna-high` / `terra-high` in any
session, and the pipeline / review executor stages when those are on.

## Modes

Two axes, multiplied:

| heavy axis (critic, decision review, heavy agent on request: document critique only, never code review) | executor axis (repo research, harness, packages, mechanical checks) |
|---|---|
| `none` — Claude agents / forks as in the base or pipeline | `none` — forks on the main model |
| `sol` — replace with `sol-medium` / `sol-high` (5 / 3 tool calls) | `luna` — executor fork jobs → `luna-high` |
| `astra` — replace with `sol-medium`, `sol-high`, `astra-medium` or `astra-high` | `terra` — as luna, plus opus-low-class executor jobs → `terra-high` |
| `+sol` — keep the Claude agent, pair a sol agent (dual review) | |
| `+astra` — pair one of the four heavy codex combos | |

Names: single axis `luna`, `terra`, `sol`, `astra`, `+sol`, `+astra`; combos `<heavy>-<exec>`:
`sol-luna`, `sol-terra`, `astra-luna`, `astra-terra`, `+sol-luna`, `+sol-terra`,
`+astra-luna`, `+astra-terra`. Invocation: `/session:codex <mode>`, at any point of the
session; after `/session:pipeline` or `/session:review` when those are used.

## Start (do this now)

0. The base is present in every session; no check. If pipeline or review is on, the stage
   mapping of `codex-modes.md` applies; otherwise the base mapping applies: executor-kind
   fork job → executor axis, heavy agent on request → heavy axis.
1. Parse the argument. `<mode>` present → split at the `-` before `luna`/`terra`:
   `sol-luna` = heavy `sol`, exec `luna`; `sol` = heavy `sol`, exec `none`; `luna` = heavy
   `none`, exec `luna`. With an argument there is NO question to the user. Only without an
   argument ask two questions with `AskUserQuestion`, entirely in Russian, recommended
   option first:

   Q1, header «Тяжёлые агенты», question «Кем делать критику и ревью решения (только документы)?»
   - «Claude (по умолчанию)» — тяжёлые работы на агентах Claude из session-map.
   - «Пара Claude + codex» — к каждому тяжёлому агенту Claude в пару codex-агент, слияние отдельным форком (`+sol` / `+astra`).
   - «Заменить на codex» — тяжёлые агенты заменить на codex (`sol` / `astra`).

   Q1b (only when Q1 chose codex), header «Какая codex-модель», question «Какой набор тяжёлых codex-моделей?»
   - «sol» — sol-medium / sol-high.
   - «astra» — одна из sol-medium, sol-high, astra-medium, astra-high.

   Q2, header «Исполнители», question «Кем делать дешёвые исполнительские работы (исследование по репозиторию, тесты, проверки)?»
   - «Форки Claude (по умолчанию)» — как в базе.
   - «luna» — исполнительские форки заменить на luna-high, где допустимо.
   - «terra» — как luna, плюс тяжёлые исполнительские работы на terra-high.

2. One Bash call: `codex --version; ls ~/.claude/bin/codex-exec-logged.sh ~/.codex/proxy-usage.jsonl`.
   Missing wrapper → BLOCKED, say so. A `CODEX CLI ERROR` mentioning the quota during the
   task → executors fall back to `luna-reserve-high`, heavy slots to the Claude agent;
   record `(fallback)` in the ledger label when a ledger exists. Harness gate (pipeline
   skill, when on): the same call runs `codex -p <profile> mcp list` for every MCP server
   the task needs; a server missing or failing there is a harness outage: the job does not
   start, the user gets one chat line per server with the exact failure, and every
   following `ping` re-runs the check and resumes from the last ledger row when the
   servers are back (`still unavailable: <list>` otherwise); "continue without <tool>"
   from the user overrides.
3. Astra modes need `astra` in `~/.claude/agents/codex-proxy.md` (one grep); missing →
   run on the sol set and say "astra pending".
4. Reply with one line: "Codex: <mode> (heavy <…>, exec <…>); fallbacks <…>."
   When a ledger exists, every `ledger.jsonl` row of the task carries `"codex": "<mode>"`.
5. Exchange directory: `<task dir>/codex/` when pipeline / review has a task directory
   (`mkdir -p` right after it exists); otherwise `$TMPDIR/codex-<YYYY-MM-DD>/codex/`,
   created at the first codex job. Prompt and output files live there.

## How a codex job runs

Envelope as in the session base, section "Launching a codex model": the MAIN session
writes the prompt file `<exchange dir>/<job>-<n>.md` (≤ 30 lines of bullets, first line
`Style: caveman ultra (see AGENTS.md Response style); plain English only, no Russian recap; artifacts in normal prose.`),
appends the ledger row when a ledger exists (`kind: "codex-agent"`, `model: "<tier>"`,
`effort`, `codex: "<mode>"`) with one Bash, runs ONE `Workflow` with one `agent()`
(`agentType: 'codex-proxy', model: 'haiku', effort: 'medium'`, label
`<sol|atr|lun|lur|ter>-<eff>-<job>`, prompt = the header block, `CODEX CWD` = repo root,
`CODEX OUTPUT FILE: <exchange dir>/<job>-<n>.out.md`), fills `agent_id` from the
workflow journal and appends the stop line when a ledger exists; consumes only the shim's
`LAST LINE`; no fork writes a prompt or relays an output. Per-stage slots and conventions
for pipeline / review: `codex-modes.md`, read once at start. Inputs of each prompt file in
the base: the role, the inputs by absolute path, the acceptance criteria, the commands to
run, the required last lines. In pipeline: the codex sentences of stages 1, 4 and 5
(research: ledger snapshot, framing, `evidence/`, output `evidence/EB-<n>.md` plus the
ledger append line; harness: verification plan and contract invariants; package: its
implementation-plan section, contract invariants, harness commands, commit message).
Luna research writes `evidence/EB-<n>.md` directly and appends its own ledger lines; heavy
jobs write `reviews/<stage>-codex.md` (dual review) or their output file, read by the
next consumer by path. 2026-09-06: two opus forks per codex call (prompt writer, output
reader) cost more than the luna call itself on a 150K prefix; this envelope removes them.

Executor jobs (luna, terra) run inside codex's workspace-write sandbox, `CODEX CWD` = repo
root. The package prompt file ends with: run the harness, commit on pass with the given
message, return the 5-field status with the harness result lines. The codex run does the
edit, the harness run and the commit itself. No fork reads the diff, no fork re-runs the
tests, no review. `partial` or a failing harness → one more codex run with the failure
packet (the failing lines, the hypothesis), never an opus fork; after the second failure
the job goes to the loop guard (in pipeline: failure packet into the ledger; in the base:
the failure packet in chat), a low fork diagnoses from the failure lines only. A harness
build in luna / terra mode is closed the same way: the harness must fail on the negative
control and codex reports it in the status. Choosing an executor mode is the user's
permission for codex edits in that task. 2026-09-06 sol-terra run: diff-reading opus
forks around 6 terra packages cost $28 for $1.42 of terra; this rule removes them.

## Rules

- Heavy effort by job budget: critic (reasoning over given files) → `sol-medium` /
  `astra-medium`; decision review (pipeline full path only; standard has a low fork
  check, fast none) and the hardest document review on request → `sol-high` /
  `astra-high`. Heavy models and any medium/high effort generate or critique documents
  only, within 5 tool calls at medium and 3 at high; they never review code or read the
  repository. There is no final review and no code review at all: in pipeline Gate F is a
  mechanical closure check by a low fork. A package without a formal verifier is authored
  by opus-low (`terra-high` in terra mode) and not reviewed; luna-high writes only
  packages that have a verifier. Executors fixed at `luna-high` (`terra-high` for the
  heavy executor jobs in terra mode).
- A job stays on Claude when it needs MCP (Jira, GitLab, Confluence), writes the
  pipeline's or review's own artifacts (`task.md`, split files, `ledger*`, `evidence/`,
  `reviews/<stage>.md`) or needs a skill (codex sees no SKILL.md; the prompt file names
  the SKILL.md path to read, or the job stays on Claude). Codex writes only into the
  repository (executor jobs, including their commits), the exchange directory and, in
  dual review, `reviews/<stage>-codex.md`.
- Codex jobs are Workflow calls like the base's cold agents and the pipeline's cold stages
  (critic, cold researcher, waiter); the pipeline's ban on other Workflow stages is lifted
  exactly for them, one agent per job.
- Dual review (`+sol`, `+astra`): two review files, a merge fork writes the triage, a high
  finding in either that the triage did not refute fails the gate. Rounds stay at 2.
- Cost: `tools/pipeline-cost.py` joins codex rows with `~/.codex/proxy-usage.jsonl` by
  model + effort, then time window; give parallel codex jobs distinct labels.

## Forbidden

- No codex agent for a job that needs MCP, the pipeline's or review's own artifacts or a
  skill; no inline task text in the shim prompt (file only); no reading of a codex output
  file by the main session or by a relay fork; no fork to write a prompt file; no codex
  Workflow without its ledger row when a ledger exists.
- No effort or model outside the sets above; no `danger-full-access` or bypass flags (the
  shim refuses them anyway).
- No mode change in the middle of a task; a fallback is recorded, not a mode change.
