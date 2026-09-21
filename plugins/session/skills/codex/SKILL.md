---
name: codex
description: Loaded on top of the session base: routes heavy roles or executor jobs to the codex stack (luna, terra, sol, astra) through the proxy shim of this skill.
disable-model-invocation: true
---

# Codex axis

Loaded on top of the session base. Only the agent running a job changes; jobs and files
stay as defined by the base.

A job is a fork job in the base. The heavy axis replaces or pairs the base's "upscale
agent". The executor axis routes executor-kind fork jobs (repository research, harness,
package edits, mechanical checks) to `luna-high` / `terra-high`.

## Modes

Two axes, multiplied:

| heavy axis (critic, decision review, upscale agent: document critique only, never code review) | executor axis (repo research, harness, packages, mechanical checks) |
|---|---|
| `none` — Claude agents / forks as in the base or pipeline | `none` — forks on the main model |
| `sol` — replace with `sol-medium` / `sol-high` (5 / 3 tool calls) | `luna` — executor fork jobs → `luna-high` |
| `astra` — replace with `astra-medium` / `astra-high` (5 / 3 tool calls); sol not used | `terra` — as luna, plus opus-low-class executor jobs → `terra-high` |
| `+sol` — dual review: keep the Claude upscale agent, pair `sol` at the same effort | |
| `+astra` — dual review: keep the Claude upscale agent, pair `astra` at the same effort | |

Names: single axis `luna`, `terra`, `sol`, `astra`, `+sol`, `+astra`; combos `<heavy>-<exec>`:
`sol-luna`, `sol-terra`, `astra-luna`, `astra-terra`, `+sol-luna`, `+sol-terra`,
`+astra-luna`, `+astra-terra`. Invocation: `/session:codex <mode>`, at any point of the
session; after the process skill of the base set when one is loaded.

## Start (do this now)

0. The base is present in every session; no check. The base mapping applies: executor-kind
   fork job → executor axis, upscale agent → heavy axis. The review points (plan critique,
   verification-plan critique, closure review, test-suite job) fire in every mode; only the
   agent behind each point changes.
1. Parse the argument. `<mode>` present → split at the `-` before `luna`/`terra`:
   `sol-luna` = heavy `sol`, exec `luna`; `sol` = heavy `sol`, exec `none`; `luna` = heavy
   `none`, exec `luna`. With an argument there is NO question to the user. Only without an
   argument ask two questions with `AskUserQuestion`, in A2 English, recommended option
   first:

   Q1, header "Heavy agents", question "Who does critique and decision review (documents only)?"
   - "Claude (default)" — heavy jobs on Claude agents by class slot.
   - "Claude + codex pair" — each heavy Claude agent gets a codex agent as a pair, a separate fork merges (`+sol` / `+astra`).
   - "Replace with codex" — heavy agents replaced by codex (`sol` / `astra`).

   Q1b (only when Q1 chose codex), header "Codex model", question "Which heavy codex model set?"
   - "sol" — sol-medium / sol-high.
   - "astra" — astra-medium / astra-high (no sol).

   Q2, header "Executors", question "Who does cheap executor jobs (repository research, tests, checks)?"
   - "Claude forks (default)" — as in the base.
   - "luna" — executor forks go to luna-high where allowed.
   - "terra" — as luna, plus heavy executor jobs on terra-high.

2. One Bash call: `codex --version; for d in $(ls -d ~/.claude/plugins/cache/claude-session/session/*/bin 2>/dev/null | sort -rV) ~/projects/claude-session/plugins/session/bin ~/.claude/bin; do [ -x "$d/codex-exec-logged.sh" ] && CODEX_BIN=$d && break; done; ls "$CODEX_BIN/codex-exec-logged.sh" "$CODEX_BIN/codex-style.md"`.
   The wrapper and the style file ship with this plugin (`bin/`). Missing wrapper → BLOCKED, say so. A `CODEX CLI ERROR` mentioning the quota during the
   task → executors fall back to `luna-reserve-high`, heavy slots to the Claude agent;
   the job label gets the suffix `-fallback`.
3. Astra modes need `astra` in the plugin's `skills/codex/proxy-prompt.md` (one grep on `$CODEX_BIN/../skills/codex/proxy-prompt.md`); missing →
   run on the sol set and say "astra pending".
4. Reply with one line: "Codex: <mode> (heavy <…>, exec <…>); fallbacks <…>."
5. Exchange directory: `<task dir>/codex/` when pipeline / review has a task directory
   (`mkdir -p` right after it exists); otherwise
   `$TMPDIR/codex-<YYYY-MM-DD>-<basename of cwd>/codex/`, created at the first codex job.
   Prompt and output files live there. Two sessions never share an exchange directory; a
   session never renames or deletes files it did not create there.

## How a codex job runs

Envelope: the MAIN session
writes the prompt file `<exchange dir>/<job>-<n>.md` (≤ 30 lines of bullets, first line
`Style: caveman ultra, plain English only; artifacts in normal prose.`), runs ONE `Workflow`
with one `agent()` (`agentType: 'session:tools-read-bash'`, the fixed cheap wrapper cell passed
at this call site: `model: 'haiku', effort: 'medium'` — the pin is the cheapest wrapper around an
external CLI, never a slot of the class; label `<mod>-<eff>-<tier>-<job>`, so `hai-me-<tier>-<job>`,
for example `hai-me-luna-research`; tiers `sol`, `terra`, `luna`, `luna-reserve`, `astra`) and
consumes only the shim's `LAST LINE`; no fork writes a prompt or relays an output.
The agent prompt is the absolute path of the shim page
(`$CODEX_BIN/../skills/codex/proxy-prompt.md`, "read it first and follow it") plus the header
block: `CODEX TARGET`, `CODEX PROMPT FILE`, `CODEX CWD` = repo
root, `CODEX OUTPUT FILE: <exchange dir>/<job>-<n>.out.md`, optional
`CODEX ROLE: <stem of a file in the plugin's agents/ directory>` (the wrapper puts that file's
body, the CLAUDE.md files and the memory index into codex's stdin; a role text of `lib/roles/` is
named inside the prompt file instead)
and `CODEX LABEL: <the same label>` (lands in `~/.codex/proxy-usage.jsonl`). The header block
ends with the line `No skills needed for this step.` (or the Read-skill-files line). Inputs of
each prompt file: the role, the inputs by absolute path, the acceptance criteria, the commands
to run, the required last lines. Heavy jobs write their output file, read by the next consumer
by path; the artifact stays at `CODEX OUTPUT FILE`, the final message lands in
`<CODEX OUTPUT FILE>.final.md`, which the shim reads for `LAST LINE`.

Executor jobs (luna, terra) run inside codex's workspace-write sandbox, `CODEX CWD` = repo
root. The package prompt file ends with: run the harness, commit on pass with the given
message, return the 5-field status with the harness result lines. The codex run does the
edit, the harness run and the commit itself. No fork reads the diff, no fork re-runs the
tests, no review. `partial` or a failing harness → one more codex run with the failure
packet (the failing lines, the hypothesis), never an opus fork; after the second failure
the job goes to the loop guard (the failure packet in chat), a low fork diagnoses from the failure lines only. A harness
build in luna / terra mode is closed the same way: the harness must fail on the negative
control and codex reports it in the status. Choosing an executor mode is the user's
permission for codex edits in that task.

## Rules

- Heavy effort by job budget, within the mode's set only (`sol` mode: sol; `astra` mode:
  astra): critic (reasoning over given files) → `<set>-medium`; decision review
  (pipeline full path only; standard has a low fork check, fast none) and the hardest
  document review or generation on request → `<set>-high`. Heavy models and any medium/high effort generate or critique documents
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
- Dual review (`+sol`, `+astra`): at every review point (plan critique, verification-plan critique, closure review) the Claude upscale agent of
  the main session's model (opus-medium / opus-high in an opus session, fable-medium /
  fable-high in a fable session) and the codex agent of the same effort (sol-me with
  opus-me, sol-hi with opus-hi; same for astra) run in ONE `Workflow` (`parallel`), two
  review files, a merge fork writes the triage, a high finding in either that the triage
  did not refute fails the gate. Rounds stay at 2. Upscale GENERATION stays single, on
  the Claude agent.
- Cost: `tools/pipeline-cost.py` joins codex rows with `~/.codex/proxy-usage.jsonl` by
  model + effort, then time window; give parallel codex jobs distinct labels.

## Forbidden

- No codex agent for a job that needs MCP, the pipeline's or review's own artifacts or a
  skill; no inline task text in the shim prompt (file only); no reading of a codex output
  file by the main session or by a relay fork; no fork to write a prompt file.
- No effort or model outside the sets above; no `danger-full-access` or bypass flags (the
  shim refuses them anyway).
- No mode change in the middle of a task; a fallback is recorded, not a mode change.
