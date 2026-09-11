# Inventory of the main session: tools, agents, skills

State on 2026-09-11 evening: session plugin 0.10.0; user-level `permissions.deny` covers SendFeedback, ReportFindings, CronCreate, CronDelete, CronList, ScheduleWakeup, NotebookEdit, EndConversation; user-level `skillOverrides` switches 14 built-in skills off; every folder under `~/projects` denies Artifact and DesignSync in `.claude/settings.local.json`. A sonnet main session in such a folder starts at 32.9K tokens (was 56.9K).

How the numbers were made. "Tokens at start" for loaded tools come from the `prompt_snapshot` record of a real session (schema characters divided by 5.15, the calibrated ratio). "Tokens on demand" for deferred tools come from sessions where only that tool was allowed (they include a shared header of about 0.4K, so they read a little high). Agent and skill sizes are file characters divided by 4; the harness counts descriptions about 1.4 times higher. Usefulness is scored 1-10 for this user's work: session plugin with forks and workflows, tmux test sessions, GitLab merge requests, iOS app, Go and Python services, macOS setup scripts.

## Table 1. Tools

Status values: loaded (schema in context at start), deferred (name only at start, full schema loaded by ToolSearch when needed), denied-user (removed everywhere by user settings), denied-project (removed by the project's local settings).

| tool | status | tokens at start | tokens on demand | what it is for | usefulness |
|---|---|---|---|---|---|
| Bash | loaded | 4.3K | same | Runs shell commands: git, go test, pytest, xcodebuild, tmux, brew, curl, background jobs with a wake-up when they finish. Touches the shell, files and the network. In auto mode the harness even prefers it over Read and Edit. Every fork, test session and commit goes through it. | 10, nothing works without it |
| Read | loaded | 0.9K | same | Reads files with line numbers, and it is the only way to see an image, a screenshot or a PDF page. Touches files only. | 10, cannot be dropped |
| Edit | loaded | 0.6K | same | Exact string replacement in a file, safe for multi-line changes. Touches files. Used less in auto mode, still the safe path for code edits. | 9 |
| Write | loaded | 0.35K | same | Creates or overwrites a file: plan files, reports, driver scripts, memory notes. Also lets a subagent leave a large result on disk instead of returning it. Touches files. | 9 |
| Agent | loaded | 3.2K | same | Spawns a fork (a copy that inherits the conversation) or a cold subagent. The base rule sends every job of three or more tool calls through it. Also pulls in the agent listing reminder (about 1.5K). Touches other Claude processes. | 10, backbone of the session plugin |
| Workflow | loaded | 1.7K | same | Runs a JavaScript orchestration script that starts cold agents with explicit model and effort, in the background. The base sends every cold agent through it. Touches other Claude processes, files (script and journal) and the codex CLI through the proxy agent. | 9 |
| Skill | loaded | 0.7K | same | Invokes a skill (packaged instructions such as session:ask). The tool is small, but allowing it also brings the skill listing (about 0.9K now, 3.3K before the overrides). Touches files (SKILL.md on disk). | 8, the plugin lives on skills |
| ToolSearch | loaded | 0.5K | same | Loads the schema of a deferred tool on demand. Without it Monitor, SendMessage, WebFetch and the Chrome tools cannot be reached; deferring is what keeps the tool block small. | 8 |
| AskUserQuestion | loaded | 1.2K | same | Shows a multiple-choice question in the terminal (the Russian dialogs the base requires). Touches the harness UI. Cheap for quick questions; heavier decisions go to Plannotator. | 6 |
| ListAgents | loaded | 0.4K | same | Lists agents and sessions the model can message, needed before a cross-session SendMessage. Touches the harness only. | 4, used now and then |
| Monitor | deferred | 0 | not measured alone, loads via ToolSearch | Streams events from a long-running script, one notification per line; the keep-warm ping of the base runs on it. Touches the shell. Disappears when telemetry is off. | 9 in the main session, never in subagents |
| SendMessage | deferred | 0 | 2.8K | Sends a message to a fork, a subagent or another local session; also how a relay session could ping background sessions. Touches other Claude processes. | 7 in the main session, rare in subagents |
| EnterPlanMode, ExitPlanMode | deferred | 0 | 2.0K + 1.2K | Switches into plan mode and presents the plan for approval (Plannotator hooks on exit). Touches the harness UI. | 5, rarely used now |
| EnterWorktree, ExitWorktree | deferred | 0 | 1.8K + 1.3K | Creates and leaves an isolated git worktree. Touches the shell and the repository. | 4, useful but out of habit |
| WebFetch, WebSearch | deferred | 0 | 1.1K + 1.0K | Fetches a page or searches the web. Touches the network. Raw results flood the context; a search agent that returns a 3-5K digest is the better home. | 5 in the main session, 8 inside web-researcher |
| RemoteTrigger | deferred | 0 | 1.7K | Creates or runs claude.ai Routines, the engine behind /schedule. Touches the network and needs Remote Control. | 4, untested, worth an experiment |
| TaskOutput, TaskStop | deferred | 0 | not measured | Reads the output of a background job or agent and stops it. Touches the harness task list. The other Task tools (TaskCreate, TaskUpdate, TaskList, TaskGet) are a checklist the terminal draws with dots and were 0 at start when allowed alone. | 5, main session only |
| PushNotification | deferred | 0 | not measured | Sends a desktop and phone push through Remote Control, meant for "call me when done". Gone when telemetry is off. | 6, untested, promising |
| SendUserFile | deferred | 0 | not measured | Puts a file in front of the user in the claude.ai or mobile view of the session. | 3 |
| Grep, Glob | absent in auto mode | 0 | 1.8K + 0.7K | File search by regex and by name pattern. Under auto mode the harness drops them from the main session and expects grep and find through Bash; subagents still get them together with Read. | 5 |
| Chrome MCP, 22 tools | deferred | 0 | about 10K when loaded | Browser automation in Chrome: tabs, clicks, forms, screenshots, console. Touches the browser and the network. Costs nothing until asked. | 3, disable the extension when unused |
| Artifact | denied-project | 0 (14.8K when loaded) | same | Publishes an HTML file as a hosted page on claude.ai, updates it, reads comments, keeps a small shared database and asset store. The schema is huge because it describes about twenty sub-actions; about 5K of it depends on feature flags. Touches the network and the harness UI. | 3, a few times a year; lift the local deny in one folder when needed |
| DesignSync | denied-project | 0 (3.7K measured alone) | same | Syncs a design canvas artifact for the design skill. Touches the network. | 1 |
| SendFeedback | denied-user | 0 (1.8K when loaded) | same | Drafts a bug report or idea about Claude Code into a local queue for the user to approve. Never affects project work. | 1 |
| ScheduleWakeup | denied-user | 0 (1.6K when loaded) | same | Lets the model pace its own /loop iterations by scheduling the next wake-up; invisible in the UI. A background Bash sleep or a Monitor does the same visibly. | 2 |
| ReportFindings | denied-user | 0 (0.6K when loaded) | same | Returns code-review findings as a typed list for the terminal; only /code-review uses it. | 2 |
| CronCreate, CronDelete, CronList | denied-user | 0 (2.0K + 0.5K + 0.5K) | same | Schedules a prompt at a cron time inside the session. Expensive to use (list, then add or delete) and the harness shows no state; Monitor replaced it in the base. | 2 |
| NotebookEdit | denied-user | 0 (1.0K) | same | Edits a cell of a Jupyter notebook. Not used. | 1 |
| EndConversation | denied-user | 0 | same | Ends the session as a last resort against abuse. | 1 |

Paid at start for tools: about 13.7K (Bash, Read, Edit, Write, Agent, Workflow, Skill, ToolSearch, AskUserQuestion, ListAgents plus the shared header and the deferred name list).

## Table 2. Agents

"Description tokens" is what the main session pays in the agent listing (chars/4, then x1.4 as the harness counts). "Body tokens" is what the agent itself pays when it starts; where `skills:` names skills, their bodies would add to it, but every preloaded skill here is a built-in one switched off by skillOverrides, so the preload is unverified and each body carries its rules inline instead.

| agent | source | description tokens | body tokens | tools | what it does | usefulness |
|---|---|---|---|---|---|---|
| codex-proxy | session plugin | 101 / 141 | 3800 | Bash, Read, Write | Thin shim that runs one task on a codex model (luna, terra, sol, astra, luna-reserve) through the local codex CLI. Takes a header block with the prompt file path, returns the output file path and its last line; nothing large passes through its context. Model and effort come from the workflow call. | 8 under session:codex |
| pool-proxy | session plugin | 64 / 90 | 843 | Bash | Hands one workflow stage to a warm pool worker (poold) and returns the result file path. Belongs to the unstable pool experiment. | 2, experiment not in use |
| stage-reviewer | session plugin | 66 / 92 | 433 | Read, Write | Document reviewer for a decision contract or another key document: checks claims against the evidence they point to, writes one review file. Runs at medium or high effort within a 5 or 3 tool-call budget. Used today for the plan critique and the closure review. | 8 |
| stage-critic | session plugin | 61 / 85 | 425 | Read, Write | Clean-context critic for pipeline mode: reads the framing and the ledger snapshot, writes reviews/critic.md with severities, may raise the task class. | 6 |
| stage-author | session plugin | 44 / 62 | 298 | Bash, Read, Edit, Write, Grep, Glob | Lean author and fixer stage agent for plans, code and tests; the workflow passes model and effort. Used today for the opus-high translation. | 8 |
| stage-researcher | session plugin | 41 / 57 | 328 | Bash, Read, Grep, Glob, ToolSearch, WebFetch | Lean fact researcher: reads code, git history and docs named in the prompt, writes a notes file. Used today for the opus-low code review. | 8 |
| stage-executor | session plugin | 40 / 56 | 281 | Bash, Read, Grep, Glob | Runs the commands the task names and reports PASS/FAIL with the decisive lines. | 7 |
| waiter | session plugin | 50 / 70 | 540 | Bash, Read | Small fresh-context agent for long waits and polling: tmux sessions, JSONL transcripts, CI, deploys. Pinned to sonnet. | 7 |
| artifact-publisher | session plugin, new | 45 / 63 | 417 | Artifact, Read, Write, Bash | Publishes or updates a claude.ai Artifact from a local HTML file and returns the URL, on opus. Works only in a folder where the local Artifact deny is lifted. | 4, a few times a year |
| artifact-designer | session plugin, new | 44 / 63 | 455 | Artifact, DesignSync, Read, Write, Bash | Designs and publishes a polished Artifact (canvas, diagrams, charts) from a brief, on opus. Same deny constraint. | 3, only when looks matter |
| web-researcher | session plugin, new | 48 / 68 | 335 | WebFetch, WebSearch, Read, Write | Searches and fetches for one named question, writes a sourced summary to a file and returns a 3-5K digest, on sonnet medium. Keeps raw web results out of the main session. Smoke-tested today. | 8 |
| code-reviewer | session plugin, new | 38 / 54 | 400 | Read, Grep, Glob, Bash | Reviews a diff, branch or PR for correctness bugs and cleanups, returns findings with file:line, on sonnet high. Smoke-tested today. | 7 |
| simplifier | session plugin, new | 38 / 53 | 425 | Read, Edit, Bash | Applies reuse and simplification cleanups to the changed files named by the caller, returns a diff summary, on sonnet. Not yet exercised. | 5 |
| security-reviewer | session plugin, new | 29 / 41 | 423 | Read, Grep, Bash | Security review of the pending changes, findings with severity and file:line, read-only, on sonnet high. Not yet exercised. | 5 |
| Explore | user-prefs plugin | 81 / 113 | 193 | Bash, Glob, Grep, Read, WebFetch, WebSearch | Override of the built-in Explore pinned to sonnet so an accidental spawn stays cheap. Description still untrimmed (lives in another plugin). | 5, insurance |
| spec-critic | ~/.claude/agents | 50 / 70 | 193 | Read, Write | Clean-context critic for a design document: reads one file, writes one review file. Overlaps with stage-critic and stage-reviewer. | 3, candidate to delete |

Paid at start for agents: about 1.4K in the listing (16 descriptions plus names and tool lists).

## Table 3. Skills

"Model-invocable" says whether the model can call the skill on its own: yes; no by `disable-model-invocation` (the user types /name); off by `skillOverrides` (hidden from the model entirely); name-only (name kept, description dropped, about 10-20 tokens). Built-in skills are not on disk, so their body size is unknown; their description tokens are the /context figures.

| skill | source | description tokens | model-invocable | body tokens | what it is for | usefulness |
|---|---|---|---|---|---|---|
| session:base | session plugin | 26 | no (user) | 7894 | The session rules: forks, workflows, waits, models, the keep-warm ping, the reply format. Loaded first in every session. | 10 |
| session:pipeline | session plugin | 54 | no (user) | 3979 | Pipeline mode on top of the base: ledger, stages, critics. | 7 |
| session:review | session plugin | 84 | no (user) | 3320 | Review mode on top of the base. | 6 |
| session:codex | session plugin | 66 | no (user) | 2875 | Codex mode: luna, terra, sol, astra through the proxy. | 7 |
| session:ask | session plugin | 73 | yes | 676 | Ask the user without blocking: writes a short Russian options document, opens it in Plannotator in the background, continues on defaults. The only session skill the model may call on its own. | 8 |
| session:reset-counter | session plugin | 46 | no (user, set today) | 184 | Clears the statusline mode counters after a rewind. | 3 |
| session:pool-unstable, pool-stop-unstable, pool-workflow-unstable | session plugin | 86, 64, 109 | no (user) | 380, 250, 1551 | The warm-pool experiment. Hidden, cost 0 at start. | 2 |
| plannotator | ~/.claude/skills (installed by the Plannotator installer) | 85 | yes | 3325 | Reference for the Plannotator CLI: review, annotate, last, archive, guides. Loaded today to open the reports. | 7 |
| plannotator-review, -last, -annotate | ~/.claude/skills | 34, 31, 31 | no (user) | 74, 248, 334 | Thin launchers for the three common Plannotator actions. | 6 |
| workflow-authoring | built-in | 80 | yes | unknown | Reference for writing a Workflow script: API, gotchas, resume, patterns. Loaded before every new script. | 8 |
| code-review | built-in | 270 | yes | unknown | Reviews the diff for bugs; the base says sonnet only, never the main session. The code-reviewer agent wraps it. | 5 |
| claude-in-chrome | built-in | 180 | yes | unknown | Entry skill for browser automation. | 3 |
| schedule | built-in | 130 | yes | unknown | Scheduled cloud agents (Routines) through RemoteTrigger. | 4, untested |
| session:ask is above; remaining built-ins: dataviz, design, artifact-design, artifact-diagramming, artifact-capabilities, claude-api, loop, fewer-permission-prompts, update-config, keybindings-help, init, run, simplify, security-review | built-in | 480, 340, 70, 70, 220, 360, 120, 60, 240, 80, 20, 120, 60, 30 | off by skillOverrides | unknown | Charts, design canvases, artifact guidance, the Claude API database, /loop, permission allowlists, settings.json help, keybindings, CLAUDE.md init, app launcher, cleanup pass, security review. Switched off today; simplify and security-review live on inside their agents. | 1-3 each |

Paid at start for skills: about 0.9K (the listing of session:ask, plannotator, workflow-authoring, code-review, claude-in-chrome, schedule and the names of the rest).

## Sums at start (sonnet, 32.9K measured)

| block | tokens |
|---|---|
| system prompt | 10.2K |
| tools | 13.7K |
| agents listing | 1.4K |
| memory files (CLAUDE.md, skill-routing.md) | 1.8K |
| skills listing | 0.9K |
| first-turn reminders | about 5K |
