---
name: codex
description: Extra skill invoked right after session:pipeline or session:review; routes heavy roles and/or executors to the codex stack (luna, terra, sol, astra) through the codex-proxy shim. Loaded on top of forks plus pipeline or review, never alone.
disable-model-invocation: true
---

# Pipeline: codex axis

Loaded on top of `session:pipeline` or `session:review`, never alone; those skills know
nothing about codex. Only the agent running a stage changes; stages, gates, files, ledger stay as defined.

## Modes

Two axes, multiplied:

| heavy axis (critic, decision review: document critique only, never code review) | executor axis (repo research, harness, packages, mechanical checks) |
|---|---|
| `none` — Claude agents / forks as in the pipeline | `none` — forks on the main model |
| `sol` — replace with `sol-medium` / `sol-high` (5 / 3 tool calls) | `luna` — executor fork jobs → `luna-high` |
| `astra` — replace with `sol-medium`, `sol-high`, `astra-medium` or `astra-high` | `terra` — as luna, plus opus-low-class executor jobs → `terra-high` |
| `+sol` — keep the Claude agent, pair a sol agent (dual review) | |
| `+astra` — pair one of the four heavy codex combos | |

Names: single axis `luna`, `terra`, `sol`, `astra`, `+sol`, `+astra`; combos `<heavy>-<exec>`:
`sol-luna`, `sol-terra`, `astra-luna`, `astra-terra`, `+sol-luna`, `+sol-terra`,
`+astra-luna`, `+astra-terra`. Invocation: `/session:codex <mode>`, right after
`/session:pipeline` or `/session:review`.

## Start (do this now)

0. Pipeline or review mode must already be on in this session (`/session:pipeline` or
   `/session:review` was invoked). If neither is, reply "session:codex needs
   session:pipeline or session:review first" and stop.
1. Parse the argument. `<mode>` present → split at the `-` before `luna`/`terra`:
   `sol-luna` = heavy `sol`, exec `luna`; `sol` = heavy `sol`, exec `none`; `luna` = heavy
   `none`, exec `luna`. With an argument there is NO question to the user. Only without an
   argument ask two questions with `AskUserQuestion`, entirely in Russian, recommended
   option first:

   Q1, header «Тяжёлые агенты», question «Кем делать критику и ревью решения (только документы)?»
   - «Claude (по умолчанию)» — тяжёлые этапы на агентах Claude из session-map.
   - «Пара Claude + codex» — к каждому тяжёлому агенту Claude в пару codex-агент, слияние отдельным форком (`+sol` / `+astra`).
   - «Заменить на codex» — тяжёлые агенты заменить на codex (`sol` / `astra`).

   Q1b (only when Q1 chose codex), header «Какая codex-модель», question «Какой набор тяжёлых codex-моделей?»
   - «sol» — sol-medium / sol-high.
   - «astra» — одна из sol-medium, sol-high, astra-medium, astra-high.

   Q2, header «Исполнители», question «Кем делать дешёвые исполнительские этапы (исследование по репозиторию, тесты, проверки)?»
   - «Форки Claude (по умолчанию)» — как в обычном pipeline.
   - «luna» — исполнительские форки заменить на luna-high, где допустимо.
   - «terra» — как luna, плюс тяжёлые исполнительские работы на terra-high.

2. One Bash call: `codex --version; ls ~/.claude/bin/codex-exec-logged.sh ~/.codex/proxy-usage.jsonl`.
   Missing wrapper → BLOCKED, say so. A `CODEX CLI ERROR` mentioning the quota during the
   task → executors fall back to `luna-reserve-high`, heavy slots to the Claude agent;
   record `(fallback)` in the ledger label. Harness gate (pipeline skill): the same call
   runs `codex -p <profile> mcp list` for every MCP server the task needs; a server missing
   or failing there is a harness outage: the stage does not start, the user gets one chat
   line per server with the exact failure, and every following `ping` re-runs the check
   and resumes from the last ledger row when the servers are back (`still unavailable:
   <list>` otherwise); "continue without <tool>" from the user overrides.
3. Astra modes need `astra` in `~/.claude/agents/codex-proxy.md` (one grep); missing →
   run on the sol set and say "astra pending".
4. Reply with one line: "Pipeline codex: <mode> (heavy <…>, exec <…>); fallbacks <…>."
   Every `ledger.jsonl` row of the task carries `"codex": "<mode>"`.
5. `mkdir -p <task dir>/codex` right after the pipeline's task directory exists.

## How a codex stage runs

Codex stage envelope, zero forks. Three steps, always the same (per-stage table and
conventions in `codex-modes.md`, read it once at start):

1. The MAIN session writes the prompt file `<task dir>/codex/<stage>-<n>.md` itself with
   one Write: ≤ 30 lines of bullets: the first line
   `Style: caveman ultra (see AGENTS.md Response style); artifacts in normal prose.`, then
   role, inputs by absolute path (never pasted, the main session reads no input), the
   acceptance criteria, the harness commands, the required last lines. For a research
   wave the prompt names the output path `<task dir>/evidence/EB-<n>.md` and ends with
   "append your ledger lines to `<task dir>/ledger.md`".
2. The main session appends the ledger row (`kind: "codex-agent"`, `model: "<tier>"`,
   `effort`, `codex: "<mode>"`) with one Bash, then runs ONE `Workflow` with one `agent()`:
   `agentType: 'codex-proxy', model: 'haiku', effort: 'medium'`, label `<sol|atr|lun|lur|ter>-<eff>-<stage>`,
   prompt = the header block only (`CODEX TARGET`, `CODEX CWD` = repo root,
   `CODEX PROMPT FILE`, `CODEX OUTPUT FILE: <task dir>/codex/<stage>-<n>.out.md`).
   It fills `agent_id` from the workflow journal and appends the stop line after.
3. The output file is never read by the main session and never read by a fork for relay:
   the next consumer reads it by path (the next codex stage, a cold sonnet-low researcher,
   or the fork of a later stage that needs it for its own work). Luna research writes
   `evidence/EB-<n>.md` directly and appends its own ledger lines; no copy step, no merge
   fork. Heavy stages write `reviews/<stage>-codex.md` (dual review) or their output file,
   which the next stage's consumer reads by path. The main session consumes only the shim's
   `LAST LINE` (the 5-field status, the gate signal). `partial` or a failing status → a
   second codex run with a failure packet (≤ 10 lines) written by the main session, still
   no fork. Forks appear around codex only when a later pipeline stage needs them for its
   own work. 2026-09-06: two opus forks per codex call (prompt writer, output reader) cost
   more than the luna call itself on a 150K prefix; this envelope removes them.

Executor jobs (luna, terra) run inside codex's workspace-write sandbox, `CODEX CWD` = repo
root. The package prompt file names the files, the acceptance criteria and the harness
commands to run (tests and checks from the verification plan) and ends with: run the
harness, commit on pass with the given message, return the 5-field status with the
harness result lines. The codex run does the edit, the harness run and the commit itself.
No fork reads the diff, no fork re-runs the tests, no review. `partial` or a failing
harness → one more codex run with the failure packet (the failing lines, the hypothesis),
never an opus fork; after the second failure the package goes to the pipeline's loop
guard (failure packet into the ledger, a low fork diagnoses from the failure lines only).
A harness build in luna / terra mode is closed the same way: the harness must fail on the
negative control and codex reports it in the status. Choosing an executor mode is the
user's permission for codex edits in that task. 2026-09-06 sol-terra run: diff-reading
opus forks around 6 terra packages cost $28 for $1.42 of terra; this rule removes them.

## Rules

- Heavy effort by stage budget: critic (reasoning over given files) → `sol-medium` /
  `astra-medium`; decision review (full path only; standard has a low fork check, fast
  none) → `sol-high` / `astra-high`. Heavy models and any
  medium/high effort generate or critique documents only, within 5 tool calls at medium
  and 3 at high; they never review code or read the repository. There is no final
  review and no code review at all: Gate F is a mechanical closure check by a low fork.
  A package without a formal verifier is authored by opus-low (`terra-high` in terra
  mode) and not reviewed; luna-high writes only packages that have a verifier.
  Executors fixed at `luna-high` (`terra-high` for the heavy executor jobs in terra mode).
- A stage stays on Claude when it needs MCP (Jira, GitLab, Confluence), writes the
  pipeline's own artifacts (`task.md`, split files, `ledger*`, `evidence/`,
  `reviews/<stage>.md`) or needs a skill (codex sees no SKILL.md; the prompt file names the SKILL.md path to
  read, or the stage stays on Claude). Codex writes only into the
  repository (executor jobs, including their commits), `<task dir>/codex/` and, in dual
  review, `reviews/<stage>-codex.md`.
- Codex stages are Workflow calls like the pipeline's cold stages (critic, cold researcher, waiter); the
  pipeline's ban on other Workflow stages is lifted exactly for them, one agent per stage.
- Dual review (`+sol`, `+astra`): two review files, a merge fork writes the triage, a high
  finding in either that the triage did not refute fails the gate. Rounds stay at 2.
- Cost: `tools/pipeline-cost.py` joins codex rows with `~/.codex/proxy-usage.jsonl` by
  model + effort, then time window; give parallel codex stages distinct labels.

## Forbidden

- No codex agent for a stage that needs MCP, the pipeline's own artifacts or a skill; no
  inline task text in the shim prompt (file only); no reading of a codex output file by the
  main session or by a relay fork; no fork to write a prompt file; no codex Workflow
  without its ledger row.
- No effort or model outside the sets above; no `danger-full-access` or bypass flags (the
  shim refuses them anyway).
- No mode change in the middle of a task; a fallback is recorded, not a mode change.
