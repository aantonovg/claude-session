# Pipeline core

Read by `session:pipeline` and `session:review` before their own text; the base rules
of the forks skill apply underneath.

## Cost principle (why the pipeline exists)

The three dearest operations of any task, in order, and what this mode does with each:

1. **Reading a large code base.** Never done as a stage. No agent reviews the code
   base or the diff, ever; a package is proven by its formal verifier (tests,
   scenarios, checks) that the harness runs. A package with no verifier is written by
   opus-low (terra-high in terra executor mode) and nobody reviews it. Every other
   stage of the pipeline exists to make this reading unnecessary.
2. **Initial research.** Done cheaply or not at all: breadth by cold sonnet-low
   researchers with named inputs, judgment by short forks (≤ 8 turns), never by a
   medium or high agent, never a repository sweep by the main model.
3. **Implementation.** Done by low executors: forks at the main model's low effort, or
   sonnet-low / luna-high slots when the codex axis is on. Never medium or high.

Medium and high effort exist for exactly two things: generating a key document
(decision contract, verification plan on request) and critiquing a key document (the
critic, the decision review), each within 5 tool calls at medium and 3 at high. When the
main session is about to launch anything else at medium or high, or anything that reads
volumes of code, it is off the pipeline: stop and pick the cheap form.

## Ping and limit restart

Limit restart: when the context shows the previous
   stage was cut off by the subscription limit or an API error (error line instead of an
   answer, a fork or cold agent launched and never returned, a gate announced and not
   reached), the ping is the restart signal: `pong`, then in the same turn resume that
   stage from the last ledger row (relaunch the fork or agent, re-arm the wait). A stage
   stopped by the Harness gate resumes the same way once its health check passes.

## Task directory

One directory per task: `~/.claude/projects/<encoded-cwd>/pipeline/<date>-<slug>/`.

- fast and standard: one file `task.md` with the sections `Framing`, `Ledger`
  (evidence with file:line pointers, unknowns with a class, contradictions,
  assumptions, verification capabilities), `Decision contract`, `Verification plan`,
  `Implementation plan`, `Report`; keep it under ~300 lines (fast: ≤ 120, no `Report`
  section). Research forks write
  `evidence/EB-<n>.md`; review stages write `reviews/<stage>.md`.
- full: the same sections as separate files (`ledger.md`, `decision.md`,
  `verification.md`, `implementation.md`, `report.md`) plus `evidence/` and `reviews/`.
- Forks write and update `task.md` (or the split files) and own only the files their
  prompt names. The directory is the state of the task: a new session continues from it
  (untested, see README).
- Draft files are read by forks only. While a file is a draft, the main session never
  reads `task.md`, the split files, `evidence/`, `reviews/` or `ledger.jsonl`: it works
  from the fork return lines (facts, gate verdict, at most the word limit the prompt set)
  and passes file paths, not contents, to the next fork. A fork marks a file final by
  writing `Status: final` in its first lines; the main session may then read that file
  once, and only when holding its content helps the remaining stages. Every read of a
  big file by the main session is context it keeps until the session ends.
- TaskList mirrors the gates: one task per gate below, marked as they pass.

## Cost ledger

Every spawn and every main-session stage is one line in `<task dir>/ledger.jsonl`, so
the cost can later be cut by stage, step, role, kind and model:
`{"ts","stage","step","role","kind":"main|fork|workflow-agent","model","effort",
"mode":"fast|standard|full","class","agent_id","label"}` (`label` = the launch
description or workflow label, starting with the `<mod>-<eff>-` prefix as the forks skill prescribes). The main session appends the
line BEFORE the launch (merge, fix and audit forks included) and fills `agent_id` from
the `Agent` result right after; a fork row without `agent_id` is a bug the main session
fixes in the same turn. Rows of kind `workflow-agent` and `codex-agent` leave `agent_id`
null and carry the exact workflow `label`: the cost script resolves them through the
saved workflow script and its journal. `agent_id` is null for the main session's own
stages too, appended when the stage starts. The task
directory path in `pipeline/current` and the session id in `<task dir>/session` come
from the Start step. The plugin's `SubagentStop` hook (`hooks/pipeline-subagent-stop.sh`)
appends `{"ts","agent_id","event":"stop"}` per finished agent whose id the ledger already
names (other agents and repeats are ignored); workflow agents get no stop row, their
window ends at the next row of the same kind. The table:
`tools/pipeline-cost.py <task dir>` (tokens, cache read / write 5m / 1h, misses, $ per
row; totals by stage, role, kind, model+effort); `--all-runs <pipeline root>` compares
runs and calibrates the fast / standard / full paths. Remove `pipeline/current` at closure.

## Cost rules (from test 1)

Test 1 (B2CT-22116, opus-low, full, through Gate D): $17.9, 63% of it prefix re-reads over
197 turns, one miss. The forks skill's turn cap and read-once rule apply; on top of them:

- Terse main session: one status line per gate in chat, short ledger lines and fork
  prompts, no restating of fork results; its 29K of chat became prefix for ~120 turns.
- MCP payloads: ask for the fields needed (Jira JQL field list, GitLab discussion or job
  filters); write the raw payload once to `evidence/raw/<name>.json`, later forks read
  that file. No resource is fetched twice within a task.
- Sizes: evidence bundle ≤ 80 lines (pointers, not quotes), `ledger.md` ≤ 120; more goes
  into a raw file plus a short bundle. No merge fork: the last wave fork updates the ledger.

## Harness gate

Research and verification tools are a hard requirement, not a nice-to-have.

1. Before stage 1, and again before stage 4 for the verifiers, the main session runs one
   health check in one fork: every MCP server the task needs (by name, one cheap read call
   each), VPN or proxy reachability for the hosts the task needs, the docker daemon when
   the project uses it, the CLI binaries and skills the task names, and, when the codex
   axis is on, `codex -p <profile> mcp list` for the same servers.
2. Any wanted tool unavailable → the stage does not start or continue: the `wanted,
   unavailable` lines go into the `Sources` (or `Oracles`) block, the user gets one chat
   line per tool with the exact failure, and the turn ends.
3. On every following `ping`: `pong`, then in the same turn the same health check runs
   silently; when every wanted tool is back, the stage resumes from the last ledger row
   without asking; when not, one line `still unavailable: <list>` follows `pong`.
4. The fork fallback for `BLOCKED: no MCP` from a cold researcher applies only when the
   same MCP call succeeds in the main session's health check (the tool exists, cold
   agents cannot see it); a tool that fails in the health check is a harness outage under
   point 2, never a fallback.
5. The user may override with "continue without <tool>": the stage runs and the
   unavailable list stays in the block and in the report.

## Cold researcher rule (stage 1)

Fork or cold researcher: a fork re-reads the whole main prefix on every turn (150K
prefix × 8 turns = 1.2M read tokens), a cold `session:stage-researcher` (Workflow agent,
researcher cell of the class row, usually sonnet-low, label `<mod>-<eff>-research`)
costs a fixed ~15-20K start (lean agent: no Skill tool, few tool schemas; measured 13K
bare) and nothing per turn, but knows nothing of the chat and reasons at sonnet level.
The choice is price for quality, made per research job, not by prefix size:
- Breadth research → cold researcher: inventories, grep sweeps, reading docs or
  history, collecting file:line pointers, raw MCP payload fetches into `evidence/raw/`,
  anything whose inputs can be fully named in the prompt. Typical for the first wave of
  a big task, when the mass of unknowns is still nice-to-know or implementation-local.
- Judgment research → fork: why a bug happens, weighing contradictions, unknowns that
  are decision-changing, a small but hard task, anything that needs the chat so far.
  Typical for the closing wave, after breadth is done. Keep such forks short (≤ 8 turns,
  little output): their cost is the prefix re-read plus output, not the start.
- Model economics tilt the border: on a fable main session cache reads are cheap and
  output and 5m writes dear, so forks are affordable on a big prefix but must stay
  terse; on an opus main session cache reads are the dear part, so a big prefix pushes
  breadth work to the cold researcher sooner. In doubt: first wave cold, second wave
  forks.
The cold researcher writes the same `evidence/EB-<n>.md` and gets the same ledger row
(`kind: workflow-agent`); a wave of cold researchers is one `Workflow` with `parallel`,
never several launches; the main session appends its stop line. Fetching raw MCP
payloads into `evidence/raw/` is a cold-researcher job: the prompt names the exact MCP
tool names (`Tools: mcp__gitlab__get_merge_request, mcp__jira__get_issue, …`), the agent
loads them with ToolSearch. When the first cold researcher returns `BLOCKED: no MCP`
(the session's MCP servers are not visible to workflow agents), that fetch goes to one
short fork instead, its ledger row label gets the `(fallback)` suffix, and no second
cold researcher is launched for the same fetch.

## Sources and Oracles blocks

`Sources` block, the first lines of the `Ledger` section (`ledger.md` in full), two
lists: `used:` every source class that produced evidence (repo paths, git history, MCP
tools by name, docs, CI logs, skills loaded); `wanted, unavailable:` every source that
would have answered an unknown but could not be used, one line each, the source and the
harness reason in ≤ 8 words (`GitLab MCP: not visible to cold agents`, `registry: 403
from this host`, `VPN: down`, `skill x: missing`). The framing fork writes the first
version, every research fork appends.

`Oracles` block, the first lines of the plan:
`planned:` each verifier type with its health-check result (tests, scenarios, static
checks, docker, CI job, MCP read, CLI, skill); `wanted, unconfirmed:` each verifier that
would strengthen an invariant but whose presence could not be confirmed (docker, MCP,
CLI binary, skill, access, VPN), one line each with the reason in ≤ 8 words.

## Effort rule

Effort rule for every agent in this mode: medium or high effort exists only for the
generation of an important document and for its critique, within a stated budget of 5
tool calls at medium and 3 at high (the critic, a decision contract review, a heavy
agent the user asks for). Nothing at medium or high reads volumes of work: no code
review, no repository sweep, no test run. Code is verified by scenarios and never
reviewed; a package without a scenario is authored by opus-low (terra-high in terra
executor mode) instead. Everything else is low.

## Heavy document cycle

Heavy document cycle, fixed for every key document (the ledger snapshot at Gate R, the
decision contract; the verification plan only on the user's request): generate → review
→ evidence → fix, and it stops there. Generate = one run. Review = one run (the critic
or the decision reviewer, document only, its tool-call budget). Evidence = low forks or
cold sonnet-low researchers confirm or refute each high finding against files (the
evidence-audit step). Fix = one run that applies the confirmed findings. No second
review, no second fix; a further cycle only on the user's explicit word. Heavy = the
reviewer-debugger or author cell at medium or high, or sol / astra when the codex axis
is on, each within its budget (5 tool calls at medium, 3 at high). Per path: fast = 0
heavy runs (documents by low forks, no review); standard = 1 heavy run (the review),
generation and fix by low forks; full = up to 3 heavy runs (generate, review, fix) for
the decision contract, and for the ledger only the review.

