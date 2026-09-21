# session:codex: reference

Read once at the start of `session:codex`; tables and conventions (modes: `SKILL.md`).
The stage tables below apply when a process skill of the base set is on; in a
base-only session the mapping is the one in `SKILL.md` (executor-kind fork job → executor
axis, heavy agent on request → heavy axis) and the exchange directory is
`$TMPDIR/codex-<YYYY-MM-DD>-<basename of cwd>/codex/`, one per session, never shared.

## Codex model ids

The shim (`skills/codex/proxy-prompt.md` in this plugin) maps targets: `luna` → `gpt-5.6-luna`, `terra` → `gpt-5.6-terra`,
`sol` → `gpt-5.6-sol`, `luna-reserve` → `gpt-reserve` (luna billed against the separate GPT
reserve quota, for a 0% main quota). `astra` → `gpt-6-astra` (efforts medium and high, low accepted; label code `atr`).

## Effort

Executors are fixed at `high`: `luna-high` replaces sonnet-low, `terra-high` replaces opus-low
(terra mode only). Heavy effort follows the stage's tool-call budget:

| stage budget | heavy (`sol` mode: sol only; `astra` mode: astra only) | Claude analogue |
|---|---|---|
| at most 5 tool calls, pure reasoning over given files (critic) | `sol-medium`, `astra-medium` | opus-medium |
| hardest document review (decision contract), a gate that must not fail silently, 3 tool calls | `sol-high`, `astra-high` | fable-medium / high |

Heavy runs per depth follow the key-document cycle of the process skill (generate → review →
evidence → fix, once): `lite` 0 heavy runs, `std` 1 (the review), `full` ≤ 3 for the
decision contract (generate, review, fix) and only the review for the ledger; sol / astra
fill exactly those slots, never more.

Code review rule: the heavy axis (sol, astra, and any medium or high effort) exists
only for generating important documents and critiquing them, within 5 tool calls at
medium and 3 at high. It never reviews volumes of work: no code review, no repository
read. Code is verified by the
harness and never reviewed; a package without a scenario is authored by opus-low, or
terra-high in terra executor mode, and not reviewed.
Executor jobs that go to codex in `luna` / `terra` mode (`luna-high`; in terra mode the
implementation packages and harness build go to `terra-high`, the rest stays luna):
repo-only research sweeps (no MCP), harness build and health checks, implementation
packages (one codex run per package, `CODEX CWD` = repo root, in-place edits), test runs
and mechanical checks. Stay forks: framing, decision, plans, report. The codex prompt file and the ledger
rows are written by the main session; a luna research wave writes its evidence bundle
and ledger lines itself (envelope rule in `SKILL.md`, zero forks around a codex call). The package prompt file names the files, the acceptance
criteria and the harness commands to run (tests, checks from the verification plan) and
ends with: run the harness, commit on pass with the given message, return the 5-field
status with the harness result lines. The codex run does the edit, the harness run and
the commit itself; the main session reads only the shim's `LAST LINE`; `done` with a
passing harness closes the package: no fork reads the diff, no fork re-runs the tests, no
review. `partial` or a failing harness → one more codex run with the failure packet (the
failing lines, the hypothesis), never an opus fork; after the second failure the package
goes to the loop guard of the process skill (failure packet into the ledger, a low fork diagnoses
from the failure lines only). A harness build is closed the same way: it must fail on the
negative control and codex reports it.

## Admissibility (the stage stays on Claude when any holds)

- MCP needed: Jira, GitLab, Confluence reads or writes.
- Repository edits under Claude permissions, or writes of the task file group's own
  artifacts (`intent.md`, `specification.md`, `task.md` at depth `lite`, `ledger.jsonl`,
  `evidence/`, `reviews/`). Codex writes only
  into the exchange area `<task dir>/codex/` and, in dual review, `reviews/<stage>-codex.md`
  (the main session sets `CODEX OUTPUT FILE` to that path). A codex
  package that edits code is allowed only when the user said so for this task: codex edits
  in its own workspace-write sandbox, outside Claude's permission system.
- A skill is needed: codex sees no SKILL.md; the prompt file names the SKILL.md path to
  read, or the stage stays on Claude.
- Codex 5-hour quota at 0%: executor slots → `luna-reserve-high`; heavy slots → the
  Claude agent of the `none` axis. The fallback is a ledger `label` suffix `(fallback)`,
  not a mode change.

## Launch convention

One `agent()` per codex stage inside a `Workflow`:
`agentType: 'session:tools-read-bash', model: 'haiku', effort: 'medium'` (the cheap wrapper cell
is passed here at the call site, the one place of this plugin that pins a model instead of taking a
slot of the class: the shim only wraps an external CLI), label `hai-me-<tier>-<stage>`
with tiers `luna`, `luna-reserve`, `terra`, `sol`, `astra`. The prompt is the path of the shim page
`$CODEX_BIN/../skills/codex/proxy-prompt.md` ("read it first and follow it") and the header block,
nothing else:

```
Read $CODEX_BIN/../skills/codex/proxy-prompt.md first and follow it.
CODEX TARGET: <luna|luna-reserve|terra>-high | <sol>-<medium|high> | <astra>-<medium|high>
CODEX CWD: <repo root>
CODEX PROMPT FILE: <task dir>/codex/<stage>-<n>.md
CODEX OUTPUT FILE: <task dir>/codex/<stage>-<n>.out.md
```

The main session writes the prompt file with one Write, ≤ 30 lines of bullets: the style
line, role, inputs by absolute path (codex reads the repo, not `~/.claude`), acceptance
criteria, the required last lines (the 5-field status; reviews end with
`DONE severity=<none|low|medium|high>`). The shim never reads it. The artifact the model writes stays at `CODEX OUTPUT FILE`; the
final message lands in `<CODEX OUTPUT FILE>.final.md`, which the shim reads for `LAST LINE`.
The output file is read by its next consumer by path, never by the main session and never
by a relay fork; the shim's `LAST LINE` is the gate signal. Per workflow: `meta.name` `c<class>-<pairing>-<slug>` as usual. Script shape:

```
export const meta = { name: 'c3-fable-opus-critic-codex', description: 'sol critic', phases: [{ title: 'Critic' }] }
return await agent(args.header, { agentType: 'session:tools-read-bash', model: 'haiku', effort: 'medium', label: 'hai-me-sol-critic', phase: 'Critic' })
```
with `args: { header: "Read <plugin root>/skills/codex/proxy-prompt.md first and follow it.\nCODEX TARGET: sol-medium\nCODEX CWD: <repo>\nCODEX PROMPT FILE: <…>\nCODEX OUTPUT FILE: <…>" }`.

## Ledger row and cost

`{"ts","stage","step","role","kind":"codex-agent","model":"<sol|terra|luna|luna-reserve|astra>",
"effort","mode","class","codex":"<session:codex mode>","agent_id":"<workflow agent id>","label"}`.
`codex` is optional (default `claude`). `tools/pipeline-cost.py` matches the row to records
of `~/.codex/proxy-usage.jsonl` (`{"ts","model","effort","input","cached_input","output",
"reasoning_output"}`, one per run) whose model and effort equal the row's tier and effort
and whose `ts` falls between the row's `ts` and its stop mark (or the next row of the same
task, or +4 h); residual risk: two parallel codex stages on the same model and effort can
still swap records, so give them distinct labels and check the turn counts. Prices with the codex rows of the claude-cost table
(sol 4 / 0.4 / 20, terra 2 / 0.2 / 12, luna 0.2 / 0.02 / 1.2 USD per M input / cached /
output; reserve = luna; astra $10 / $1 / $50 per M input / cached / output, unofficial). The haiku shim's own transcript (agent id of the row) is priced and added to the same row (`shim_usd` shows its share).

## Dual review (`+sol`, `+astra`)

Applies to document reviews only (critic, decision review, upscale review); code is never
dual-reviewed. The pair: the Claude upscale agent of the main session's model (opus or
fable) and the codex agent of the mode's set at the same effort, in one `Workflow`
(`parallel`); generation stays single on the Claude agent. Both reviewers get the same inputs and write separate files (`reviews/<stage>.md` and
`reviews/<stage>-codex.md`). A merge fork writes `reviews/<stage>-triage.md`: findings in
both, in one only, contradictions, with a verdict per contradiction taken from the files.
The gate fails when either review has a high finding the triage did not refute with
evidence. Review rounds stay at 2.

## Codex context mirror

Codex reads `AGENTS.md`, not `CLAUDE.md`, skills or Claude memory. For the b2connect
project `~/projects/b2connect/tools/codex-context-sync.sh` generates `AGENTS.md` (identical in
the repo and the workspace, git-excluded there) from the Claude sources: CLAUDE.md with its
imports, the workspace rules, a skills catalog with paths to read, the memory directory and
index. Profile `codex -p b2connect` carries the bw MCP servers (`--with-mcp`). The shim runs
the sync before every codex run under the workspace; git hooks rerun it after merges. Independently of that mirror,
`bin/codex-exec-logged.sh` composes codex's stdin at every run from the Claude sources: the
`--role` agent body, user and project `CLAUDE.md`, the memory index and `codex-style.md`.
