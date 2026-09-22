# session plugin: main, fork, helpers

Rules of the main Claude Code session as user-invocable skills. Start a session, pick the model
and effort, run `/session:base [no-sonnet] [no-opus] [no-fable] [c1..c5]` first (and again after
`/compact`), then optionally `/session:codex <mode>` on top. Source of the base is `base/BASE.md`;
`bin/build.sh` regenerates `skills/base/SKILL.md`, the class table inside the base and the shared
block of the two workflows from `lib/classes.json` and `lib/block.src.js`.

| skill | what it does |
|---|---|
| `session:base` | every session: main keeps the intent and the state, a fork does the work, a fresh helper brings one result for a named reason; classes and slots, waits, language, style |
| `session:codex` | on top of the base: helper jobs of named kinds go to the codex CLI (luna, terra as executors; sol, astra for a narrow analysis) |
| `session:ask` | ask without blocking: options document, Plannotator in the background, continue on reversible defaults (model-invocable) |
| `session:start-ping`, `session:stop-ping`, `session:resume-ping` | the keep-warm ping monitor of a session |
| `session:reset-counter` | clears the statusline mode counters after a rewind (user only) |

## The 0.18 set

0.18.0 rebuilds the routing around the fork-first architecture of
`reviews/claude_fork_first_architecture_full_dialogue.md`: main holds the intent, the constraints,
the decisions and the paths of results; every job of 2+ tool calls goes to a conversation fork on
the main session's own cell; a fresh helper, launched by main before the fork, runs only for one concrete result (an index,
facts, a run, a counterexample, a narrow check, a replicated change) that improves the fork's
decision or replaces its costlier work, and returns three lines (status, report path, summary)
with the details in a file. A fork launches nothing after its first tool call and never waits: a
wait longer than the 5-minute cache window rewrites its whole section. There is no task process, no stage list, no review loop and no verification ladder:
enough is the normal end, "no remarks" is a normal outcome of a check, "no helper" is a normal
decision. Two named workflows carry every helper launch: `session:helper` (one helper, one
contract, one result directory) and `session:batch` (one helper over many items, one status row per
item). Nine helper agents carry the contracts; the class table stays the only source of a model and
an effort. `tests/plugin/all.sh` runs the static oracles of the set; `tests/workflows/usage-test.sh`
checks the contract collector; `tests/plugin/release-gate.sh` runs once, right after the release
commit.

## Helpers

One agent file per helper under `agents/`: the method and the contract in the body (what it
takes, what it returns, what it never does), the tools in the frontmatter, no model and no effort
key. The launch prompt adds the object, the question, the inputs by absolute path and the result
directory, never the history. There is no bare helper. Two groups: a cost helper replaces a part of
the fork's work the fork can trust without redoing it (slot: the cheapest one trusted for the job);
a quality helper brings new evidence for the fork's decision (slot: the difficulty of the analysis).

| helper | gain | brings | tools | default slot |
|---|---|---|---|---|
| `finder` | cost | an index of files, symbols, ranges for one question, with the limits of the search | Read, Bash | sonnet |
| `extractor` | cost | facts with source fragments for named questions from named local material | Read, Write, Bash | sonnet |
| `web-extractor` | cost | the same from public sources, URL and version per fact | WebFetch, WebSearch, Write | sonnet |
| `runner` | cost | a given experiment, test run, build or command set; commands, environment, logs | Read, Bash, Write | sonnet |
| `applier` | cost | an accepted transformation replicated by sample; exceptions listed; the check run | Read, Edit, Write, Bash | sonnet |
| `consumer` | quality | a document followed as a new consumer; the first blocker, the ambiguous step | Read, Bash, Write | sonnet |
| `checker` | quality | defect candidates against one named property, with place and evidence | Read, Write | opus |
| `breaker` | quality | a counterexample, a failing input, a minimal reproduction for one property | Read, Bash, Write | opus |
| `guide` | | an answer on Claude Code, the SDK or the API (the built-in guide agent) | built-in | fixed seat `guide` |
| `codex` | either | a contract forwarded to the codex CLI, the answer as a file; alone or paired with a Claude helper | Read, Bash | fixed seat `codex` |

The catalog is a set of tools, not a team: a helper is launched for a result the fork names, and
the fork decides what to do with it. The reasons and limits of each helper kind are in sections 6
and 8 of the architecture document.

## Result files and the handback

A launch passes `out`, one absolute directory per launch:
`~/.claude/projects/<encoded-cwd>/helpers/<YYYY-MM-DD>-<slug>/<helper>/`. The helper writes
`result.md` there (what was asked and over which inputs, what was observed or changed, the
evidence with paths and line ranges, the exceptions, what stayed unchecked) and its logs beside
it, and returns exactly three lines:

```
status: completed | partial | blocked | failed
report: <absolute path of result.md>
summary: <one line>
```

`completed` means the contract was carried out, not that the object is fine. The workflow parses
the lines (`handback()` of `lib/block.js`); a missing or unknown status comes back as `failed`.
The next fork reads the file at the depth its decision needs; a result belongs to a state (commit
and diff, document version, fetch date, environment) and an old one is a hint, never a confirmation.

## Named workflows

Scripts under `workflows/`, launched by name with `args`; the `/* usage: */` block is the contract,
delivered to the session as SessionStart context (section "Workflow contract hooks"); the body is
never read by the caller. Shared block in every script: the class table, `submodes()`, `cellFor()`,
`helperOpts()`, `handback()`, `batchRows()`; `args.class` (default c3) and `args.submodes` pick the
row, the helper's own slot or `args.slot` picks the cell, and every `agent()` call passes `model`,
`effort` and a `<mod>-<eff>-<helper>` label explicitly.

| workflow | args | returns |
|---|---|---|
| `helper` | `helper, ask, in (array), out, slot, codex, cwd, class, submodes (array)` | `{helper, cell, slot, label, out, status, report, summary}`, plus `codex: {target, status, report, summary}` when `codex` was given |
| `batch` | `helper, ask (with {item}), items (array), in (array), out, slot, class, submodes (array)` | `{helper, out, counts, rows: [{item, status, report, summary}]}` |

## Classes, slots and submodes

The class comes from `/session:base` (default c3) and holds for the session. Three slots per row:
main-model slot, opus slot, sonnet slot. Each helper has a default slot in `lib/classes.json`; the
`slot` argument moves one launch with a one-line reason. Two fixed seats stand outside the rows:
`guide` and `codex`. Forks run on the main session's model and effort.

| class | main-model slot | opus slot | sonnet slot |
|---|---|---|---|
| c1 lowest | opus-low | opus-low | sonnet-low |
| c2 below default | fable-low | opus-low | sonnet-medium |
| c3 default | fable-low | opus-medium | sonnet-high |
| c4 above default | fable-medium | opus-high | sonnet-high |
| c5 highest | fable-high | opus-high | opus-high |

Submodes rewrite the row (cells main / opus / sonnet; all three at once is an error): the full
35-cell table is rendered into the base from `lib/classes.json` by `bin/build.sh`.

## Workflow contract hooks

Each named workflow contract reaches the session as its own SessionStart `additionalContext`
entry: `Workflow <launch name> (launch by name; contract below; never read the script body): <usage>`.
`bin/workflow-usage.sh --hook --file <wf.js> --prefix <plugin>` prints one hook JSON for one script;
`--hook --dir @user` covers `~/.claude/workflows`, `--hook --dir @project` covers
`${CLAUDE_PROJECT_DIR:-$PWD}/.claude/workflows` (a project stem overrides the user stem). Session's
plugin.json declares one `--file` hook per `workflows/*.js` (`session:` prefix) plus the two dir hooks.

Another plugin exposing its own workflows: copy the collector into its `bin/` and add one group per
script to its inline plugin.json `hooks.SessionStart` (never hooks/hooks.json):

```json
"hooks": {
  "SessionStart": [
    { "hooks": [ { "type": "command", "timeout": 5,
      "command": "sh ${CLAUDE_PLUGIN_ROOT}/bin/workflow-usage.sh --hook --file ${CLAUDE_PLUGIN_ROOT}/workflows/<name>.js --prefix <plugin>" } ] }
  ]
}
```

User and project workflow dirs are already covered by session's `@user` and `@project` hooks; add no
second `@project` hook. Contracts load at session start: after a mid-session install run
`/reload-plugins` or restart the session. A tool plugin (an MCP server with its own helper agents
and workflows) follows `docs/tool-plugin/`.

## codex shim permission set

Stated here since 0.10.2; the shim itself is the `codex` helper (`agents/codex.md`). Every launch runs `codex exec` with the same
three settings: `-s workspace-write` (the sandbox: writes only inside the workspace, no
network), `-c approval_policy="on-request"` (codex asks before going beyond the sandbox) and
`-c approvals_reviewer="auto_review"` (those requests go to codex's built-in risk-based
reviewer, non-interactively; legacy alias `guardian_subagent`). The reviewer never weakens the
sandbox: beyond-sandbox capability comes only from per-command escalation, which the
preamble at the end of `bin/codex-style.md` tells codex to request when a command is denied (out-of-workspace write, network) or
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
and the done-file (content = exit code) with stderr in `<done-file>.log`. With a trailing `-` or
`--prompt-file <path>` the wrapper composes codex's stdin in memory, never on disk: the
body of the named file in `agents/` for `--role <name>`, user and project `CLAUDE.md`, the memory index, `bin/codex-style.md`
(style plus the escalation preamble), then the task; `CODEX_LABEL` lands in the ledger row's `label`.

## Compact prices

- Warm compact (cache alive): the compact call reads the whole context at the cache-read
  rate and pays for the summary output, a near-fixed $0.1-0.2 on sonnet whatever the size
  (188K: ≈ $0.09; 80K: ≈ $0.17). The next turn after it reads ~43K and writes ~25K.
- Cold compact: the whole history at the input rate. 460K: $1.30 sonnet, $5.87 fable.
- Cold big session on fable: `/model sonnet` (free, cache dead anyway), `/compact`,
  `/model` back (small reset), restore the settings.json default afterwards.
- The compact call leaves no usage entry in the JSONL; its cost is the status-line delta

## Description limits

Skill description: 100 tokens. Agent description: 100 tokens. Workflow usage block: 50-150 tokens, every arg named with its type and default.

## Session mode counters

`hooks/modes.sh` writes `~/.claude/session-modes/<session_id>.json`: a JSON object keyed by
skill name holding the string to render (`{"base":"base-c3","codex":"codex-sol-luna"}`).
Written on a user-typed `/session:<mode> <args>` (UserPromptSubmit) or a model-invoked one
(PostToolUse on Skill); cleared on PreCompact and SessionStart (resume keeps it); files older than
seven days pruned. A statusline reads it by `session_id`; `/session:reset-counter` clears it after a
rewind. State, not an API.

## Version log

0.18.0: fork-first rebuild: main keeps the intent, a fork does every 2+ call job, a fresh helper launched by main before the fork runs only for one named result and hands back three lines (status, report, summary) with the details in `result.md`; a fork launches nothing after its first tool call and never waits; workflows `session:helper` (with a `codex` pair argument) and `session:batch` replace `role`, `chain`, `make` and `probe`; nine helper agents (`finder`, `extractor`, `web-extractor`, `runner`, `applier`, `consumer`, `checker`, `breaker`, `codex`) replace the five tool-set agents; the process skill, the verification page, the task layout, the roles, the aspects and the ledger hook are gone; `lib/classes.json` keeps the class table and adds the helper map and the `codex` seat; the codex skill is one page over the `codex` helper; tests `tests/plugin/all.sh`.
0.15.1: chat replies in A2 English (word list, grammar, verbatim identifiers) in the base Language section; caveman uses common synonyms.
0.15.2: self-ping rule for long commands in every Bash-capable agent (detach, then `sleep 180` per turn; no background job at turn end).
0.15.3: every synchronous Bash call in an agent sets `timeout` ≤ 120000; commands that may run over 2 minutes run detached only.
0.15.4: the self-ping is a 30-second step loop (`for i in $(seq 6); do test -f <done> && break; sleep 30; done`), so a finished job is noticed within 30 s; background jobs write their own done-file.
0.15.5: poll step 5 seconds (`for i in $(seq 36); do test -f <done> && break; sleep 5; done`); a finished job is noticed within 5 s.
0.15.6: base "Skill first, then delegate" bullet (transcripts-jsonl, shell-gotchas, workflow-reliability, harness-cost, tmux-sessions); tests/measure: S1-S9 scenarios for the 0.15 assets, driver env matrix (MODEL EFFORT CWD OUT REPEAT IDS), parser S3 scans script files only.
0.15.7: shorter workflow descriptions; README documents workflow args; plugin-dev workflows (test-session, skill-author, memory-gc) tracked in .claude/workflows/.
0.17.1: `hooks/ledger-stop.sh` and `hooks/modes.sh` retry the `tasks/current` pointer from the repository root (`git -C "$CWD" rev-parse --show-toplevel`) when the hook cwd itself names none, so a process skill turn whose cwd sits inside the repository still finds it.
0.17.0: `research` stage before `intent` (task file `ledger.md`); at `std` and `full` nothing but research launches before the user confirms the intent; plan stage splits into `verification-plan` and `implementation-plan`; uplift moves a no-oracle author one slot up in its class row, never one class up; researcher and synthesizer role texts carry `Sources` lines (`used:`, `wanted, unavailable:`).
0.16.3: base clause on the `Monitor` 30 min cap and its expiry notice (start the `Monitor` again or switch to the `run_in_background` until-loop); empty `reviews/` directories removed.
0.16.2: ping state keyed on the claude pid only (dead CLAUDE_SESSION_ID path removed, test-only SESSION_PID_TEST); process skill: a returned out path counts only after a check on disk; switch-user.sh skips a memory note the user removed or rewrote; ping-test runs without a claude ancestor.
0.16.1: fixed guide seat (son-me, ops-lo under no-sonnet, fab-lo under no-sonnet no-opus) rendered under the class table; detached-job recipe always writes the exit code and the done-file; class table fix for c3 under no-opus no-fable.
0.16.0: rebuild from zero: class and submodes the only source of a cell (`lib/classes.json`, rendered by `bin/build.sh`); four named workflows `session:role`, `session:chain`, `session:make`, `session:probe`; five tool-set agents; one process skill with task files under `tasks/current`; verification page `lib/verification.md`; hooks `modes.sh` and `ledger-stop.sh`; the 0.15 agents, workflows and skills are gone; tests `tests/rebuild/all.sh` and `tests/workflows/usage-test.sh`.
0.15.18: fork names and `Agent` descriptions use `fork-<mod>-<eff>-<job>`; effort comes from the status line or the user's word, never guessed; workflow labels stay `<mod>-<eff>-<job>`.
0.15.17: workflow contracts via per-workflow SessionStart hooks (50-150 tokens); session:translate-ru, session:translator, session:size-estimator moved into the plugin; start-ping monitor for sessions without base; ping.sh exits when orphaned.
0.15.16: named workflows: 1-4 word descriptions, launch contract injected into base via workflow-usage.sh; ad hoc description rule. Each named workflow keeps its args in a `/* usage: */` block; base `## Named workflows` runs `bin/workflow-usage.sh` at skill load; test tests/workflows/usage-test.sh.
0.15.15: plugin monitor is the only keep-warm; daily 23:59 cutoff; resume-ping re-enables a new day. Base drops the background Bash ping jobs and re-arm rule; ping.sh gets PING_INTERVAL, PING_STEP and PING_DRY_RUN test hooks; test tests/monitors/ping-test.sh.
0.15.14: codex jobs get role body, CLAUDE.md, project memory and style from `codex-exec-logged.sh --role` (optional `CODEX ROLE:` header), dry-run test tests/codex/wrapper-test.sh; codex-proxy fixed haiku medium, label `<mod>-<eff>-<tier>-<job>`; workflow stages pass reviewer, executor and note returns inline instead of report files; build and review-fix drop the unused `out` arg, memory-gc drops `reviews`.
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
