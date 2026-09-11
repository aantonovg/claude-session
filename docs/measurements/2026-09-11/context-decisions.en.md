# Start context of a main session: what stays, what went, what moves to agents

Baseline measured: 56.9K tokens (sonnet, empty project). Floor reachable by config alone: 10.8K.
After today's changes the expected start is about 52K. Numbers are tokens in the first request.

## 1. Kept: needed in every main session

| item | tokens | where it is set | status / note |
|---|---|---|---|
| Bash | 4.3K | built-in tool | Kept. Shell, git, tests, tmux. Every fork and commit goes through it. |
| Read | 0.9K | built-in tool | Kept. The only way to see images and PDF pages. |
| Edit | 0.6K | built-in tool | Kept. Safe multi-line replacements. |
| Write | 0.35K | built-in tool | Kept. Plan files, reports, driver scripts, memory. |
| Agent | 3.2K | built-in tool | Kept. Forks are the backbone of the session plugin. Also brings the 1.5K agent listing. |
| Workflow | 1.7K | built-in tool | Kept. Every cold agent (waiter, critic, codex proxy) starts through it. |
| Skill | 0.7K + listing | built-in tool | Kept. The session plugin lives on skills. Brings the skill listing (about 2K) with it. |
| ToolSearch | 0.5K | built-in tool | Kept. Loads deferred tools on demand; the deferral itself keeps tools at 32.6K instead of 57K. |
| AskUserQuestion | 1.2K | built-in tool | Kept. Quick choice dialogs; cheaper than a Plannotator round for small questions. |
| SendMessage | deferred | built-in tool | Kept. Messages to forks and other sessions. |
| Monitor | deferred | built-in tool | Kept. Keeps the session warm; replaced the cron tools. |
| ListAgents | 0.4K | built-in tool | Kept. Used now and then with SendMessage. |
| EnterPlanMode, ExitPlanMode | deferred | built-in tools | Kept. Loaded only when plan mode is used. |
| EnterWorktree, ExitWorktree | deferred | built-in tools | Kept. Loaded only on request. |
| session plugin agents (9) | 1.4K | plugin session | Kept. Pipeline roles, waiter, codex proxy. |
| session:ask | 0.14K | plugin session | Kept. Non-blocking questions through Plannotator. |
| workflow-authoring | 0.08K | built-in skill | Kept. Needed when the model writes a workflow script. |
| code-review | 0.27K | built-in skill | Kept for now. Later: a sonnet-only agent, never in a fable main session. |
| ~/.claude/CLAUDE.md | 1.1K | user file | Kept. Global rules. |
| skill-routing.md | 0.76K | user file, imported by CLAUDE.md | Kept. Decision pending: static skills per agent instead of a routing map. |
| user-prefs:Explore | 0.13K | plugin user-prefs | Kept. Cheap override of the built-in Explore. |
| spec-critic | 0.08K | ~/.claude/agents | Kept. |
| Chrome MCP (22 tools) | 0 at start | built-in extension | Kept. Costs nothing until used; the user prefers to disable it when not in use. |
| plannotator | 0.12K | ~/.claude/skills (installer copy) | Kept. CLI reference for reviews and annotations. |

## 2. Removed today (user level; backup in $CLAUDE_JOB_DIR/tmp/user-config-backup)

| item | tokens | where it is set | status / note |
|---|---|---|---|
| SendFeedback | 1.8K | ~/.claude/settings.json, permissions.deny | Denied. Bug report drafts about Claude Code; never useful for project work. |
| ReportFindings | 0.6K | permissions.deny | Denied. Only /code-review used it. |
| CronCreate, CronDelete, CronList | 3.0K when loaded | permissions.deny | Denied. Monitor covers the same need and is visible in the UI. |
| ScheduleWakeup | 1.6K | permissions.deny | Denied. Invisible scheduler; Bash sleep or Monitor do the job. |
| NotebookEdit | 1.0K when loaded | permissions.deny | Denied. Jupyter is not used. |
| EndConversation | 0.2K | permissions.deny | Denied. Only for abuse cases. |
| dataviz, design, claude-api, artifact-design, artifact-diagramming, artifact-capabilities, loop, fewer-permission-prompts, update-config, keybindings-help, init, run, simplify, security-review | about 2K of listing | ~/.claude/settings.json, skillOverrides: off | Hidden from the skill listing. Per-skill deny does not do this; skillOverrides does. |
| work-conventions.md, claude-harness.md, b2connect-platform.md | 0 | ~/.claude/CLAUDE.md imports | Three empty files and their @ imports deleted; a stale .bak removed too. |
| explore.md, waiter.md | 0.23K | ~/.claude/agents | Moved out. Duplicates of user-prefs:Explore and session:waiter. |
| open-file | 0.03K | ~/.claude/skills | Moved out. Not used. |
| session:reset-counter | 0.07K | plugin source, skills/reset-counter/SKILL.md | Hidden from the model with disable-model-invocation: true. Not bumped, not committed yet. |

Expected saving on sonnet: about 5K.

## 3. Wanted in a dedicated agent (not done yet)

| item | tokens | where it is set | status / note |
|---|---|---|---|
| Artifact | 14.8K | built-in tool | Wanted in an artifact agent on a lower model (fable to opus). Two variants: plain, and design (with DesignSync and the design skill). Each main session would lose about 15K. |
| DesignSync + design skill | 3.7K + 0.34K | built-in tool, built-in skill | Goes with the design variant of the artifact agent. |
| WebFetch, WebSearch | 2.1K when loaded | built-in tools | Wanted in a search agent on sonnet-medium; the main session gets a 3-5K digest instead of raw pages. |
| code-review, simplify, security-review | 0.36K of listing | built-in skills | Wanted as sonnet agents; the input is heavy, the main session should not pay for it. |
| Constraint | | permissions | A user-level deny removes the tool from agents too (measured today). So the main session can hide these only by a per-project deny, or by the `--tools` launch whitelist if subagents keep the full set. Test pending. |

## 4. Rejected or still open

| item | tokens | where it is set | status / note |
|---|---|---|---|
| DISABLE_TELEMETRY=1 | -8.5K | settings env | Rejected. It also drops Monitor, PushNotification, SendUserFile and Remote Control. |
| Skill(name) in permissions.deny | 0 | settings | No effect on the listing; only blocks the call. |
| enabledPlugins: {} at project level | 0 | project settings | No effect; only user-level per-plugin false works. |
| Settings shipped by a plugin | | plugin | Not possible; plugins ship skills, agents, hooks, MCP, LSP only. |
| CLAUDE_CODE_SETTINGS profiles | | shell env | Possible, but the user sees no value in it. |
| PushNotification, RemoteTrigger, /schedule | 0 at start | deferred tools | Open. Experiments wanted later (push to phone when done, cloud routines). |
| Plugin agent descriptions | 1.4K | plugin agents | Open. Trim each description to 50-150 tokens (codex-proxy alone is 519). |
| Static skills per agent | 0.76K | agent frontmatter skills vs skill-routing.md | Open. Decide between a fixed skill set per agent and the routing map. |
