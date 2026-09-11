# Baseline start context, sonnet, empty project: 56.9K first-request tokens

Sources: JSONL usage of the first request (`hi`), `/context` and `/context all` captures, per-tool isolation runs (ctx3), settings-key isolation runs (ctx4). Token numbers are `/context` estimates unless marked "usage".

Category totals of the baseline request (run hooks-off-only, byte-identical prefix to variant 1: cache_read 46119):

| category | tokens |
|---|---|
| System prompt | 10.2K |
| System tools | 32.6K |
| Custom agents | 1.8K |
| Memory files | 1.9K |
| Skills | 3.3K |
| Messages (first turn) | 7.1K |
| sum | 56.9K (usage 56901) |

## System prompt: 10.2K
| artifact | source | tokens | purpose |
|---|---|---|---|
| Claude Code system prompt | built-in | ~10200 | harness rules, environment block, memory dir instructions, git status, date; fixed by config (`--bare` reference 2.1K) |

## System tools: 32.6K (per tool, measured alone with every other tool denied; each number carries the shared tools header, about 0.4K)
| artifact | source | tokens | purpose |
|---|---|---|---|
| Artifact | built-in | 11300 | publish and update hosted HTML pages, comments, database, assets, pins |
| Workflow | built-in | 8600 | run a multi-agent orchestration script in the background |
| Bash | built-in | 4400 | run shell commands, background jobs, git rules |
| DesignSync | built-in | 3700 | sync a design canvas artifact (design skill runtime) |
| SendMessage | built-in | 2800 | message another agent, teammate or session |
| ScheduleWakeup | built-in | 2100 | self-paced wakeups for /loop dynamic mode |
| AskUserQuestion | built-in | 2000 | structured multiple-choice question to the user |
| CronCreate | built-in | 2000 | schedule a prompt at a cron time inside the session |
| EnterPlanMode | built-in | 2000 | switch the session into plan mode |
| Grep | built-in | 1800 | regex search over files |
| EnterWorktree | built-in | 1800 | create and enter an isolated git worktree |
| RemoteTrigger | built-in | 1700 | trigger a remote cloud session or routine |
| Read | built-in | 1300 | read files, images, PDFs, notebooks |
| ExitWorktree | built-in | 1300 | leave the worktree, keep or remove it |
| ExitPlanMode | built-in | 1200 | present the plan for approval and leave plan mode |
| ReportFindings | built-in | 1200 | typed code-review findings list for the host UI |
| WebFetch | built-in | 1100 | fetch a URL and extract content |
| WebSearch | built-in | 1000 | web search |
| NotebookEdit | built-in | 994 | edit a Jupyter notebook cell |
| Edit | built-in | 941 | exact string replacement in a file |
| ToolSearch | built-in | 897 | load deferred tool schemas on demand |
| ListAgents | built-in | 767 | list addressable agents and sessions |
| Write | built-in | 722 | write or overwrite a file |
| Glob | built-in | 717 | file name pattern search |
| CronDelete | built-in | 542 | cancel a session cron job |
| CronList | built-in | 482 | list session cron jobs |
| Skill | built-in | in Skills section | invoke a skill; its schema shows only with the Skills list (3K) plus 1.4K of skill reminders in Messages |
| Agent, Monitor, TaskCreate, TaskUpdate, TaskList, TaskGet, TaskOutput, TaskStop, SendFeedback, PushNotification, SendUserFile, EndConversation | built-in | 0 alone | request byte-identical to the no-tools run: these are sent as deferred names only when allowed alone (Agent likely loads with a schema in the baseline, not measured separately) |
| sum of the measured schemas | | 56.5K | more than the 32.6K of the baseline: in the baseline a part of the list is deferred (names only, loaded through ToolSearch) and the 0.4K header is counted once; which tools are deferred is decided by the harness, not by config |

Settings-key isolation (ctx4, plugins on, user settings untouched):

| project settings.json | usage total | System tools | note |
|---|---|---|---|
| `{"model":"sonnet"}` | 55728 | 31.5K | fresh prefix (cache_read 0) |
| `{"disableAllHooks":true}` | 56901 | 32.6K | identical prefix to baseline: hooks cost 0 at start |
| `{"model":"sonnet","enabledPlugins":{}}` | 56904 | 32.6K | identical to baseline: project-level `enabledPlugins:{}` disables nothing |
| `{"model":"sonnet","env":{DISABLE_AUTOUPDATER,DISABLE_TELEMETRY,CLAUDE_CODE_DISABLE_TERMINAL_TITLE}}` | 48426 | 24.8K | the whole 8.5K delta of variant 2 |
| `{"model":"sonnet","env":{"DISABLE_TELEMETRY":"1"}}` | 48429 | 24.8K | the delta is this one variable |
| `{"model":"sonnet","env":{"DISABLE_AUTOUPDATER":"1"}}` | 56895 | 32.6K | no effect |

## Hooks / settings delta: 8.5K, attributed to `DISABLE_TELEMETRY=1`
| artifact | source | tokens | purpose |
|---|---|---|---|
| System tools removed by `DISABLE_TELEMETRY=1` | built-in, feature-gated | 7.8K in System tools, 8.5K in usage | with telemetry off the harness drops about 7.8K of tool schema; closest single match by size is Workflow (8.6K measured alone), not confirmed which tool; the rest of the delta is Messages 7.1K to 6.8K |
| hooks (user-prefs, session, plannotator plugins) | plugins | 0 | SessionStart hooks print 0 bytes; `disableAllHooks` changes nothing at the first request |

## MCP tools: 0
| artifact | source | tokens | purpose |
|---|---|---|---|
| claude-in-chrome, 22 tools | built-in extension | 0 at start (deferred, ~10.1K when loaded) | browser automation in Chrome |

## Custom agents: 12 / 1812
| artifact | source | tokens | purpose |
|---|---|---|---|
| session:codex-proxy | plugin session | 519 | shim running a task on codex models, file references in and out |
| session:pool-proxy | plugin session | 203 | shim handing a workflow stage to a warm pool worker |
| session:stage-reviewer | plugin session | 147 | document reviewer for the decision contract, Read and Write only |
| user-prefs:Explore | plugin user-prefs | 128 | override of the built-in Explore pinned to sonnet |
| Explore | ~/.claude/agents | 122 | same override, user copy (duplicate of the plugin one) |
| session:waiter | plugin session | 114 | small agent for long waits and polling |
| waiter | ~/.claude/agents | 112 | same waiter, user copy (duplicate) |
| session:stage-critic | plugin session | 107 | clean-context critic for the pipeline mode |
| session:stage-author | plugin session | 101 | author and fixer stage agent |
| session:stage-researcher | plugin session | 96 | fact researcher stage agent |
| session:stage-executor | plugin session | 87 | test and script executor stage agent |
| spec-critic | ~/.claude/agents | 76 | critic for a design document, Read and Write |

## Memory files: 2 / 1.9K
| artifact | source | tokens | purpose |
|---|---|---|---|
| ~/.claude/CLAUDE.md | user | ~1100 | global rules: reasoning language, language levels, session rules, imports |
| ~/.claude/memory-user/skill-routing.md | user, imported by CLAUDE.md | 759 | which skill to inject into which agent role |
| work-conventions.md, claude-harness.md, b2connect-platform.md | imported by CLAUDE.md | 0 | not listed by /context: missing or empty on this machine |

## Skills: 22 / 3.3K
| artifact | source | tokens | purpose |
|---|---|---|---|
| dataviz | built-in | ~480 | chart and dashboard design guidance |
| claude-api | built-in | ~360 | Claude API and SDK reference |
| design | built-in | ~340 | design canvas artifacts |
| code-review | built-in | ~270 | review the diff for bugs |
| update-config | built-in | ~240 | settings.json and hooks configuration |
| artifact-capabilities | built-in | ~220 | runtime capabilities of published artifacts |
| claude-in-chrome | built-in | ~180 | browser automation entry skill |
| session:ask | plugin session | ~140 | ask the user without blocking (Plannotator) |
| schedule | built-in | ~130 | scheduled cloud agents |
| plannotator | ~/.claude/skills | ~120 | Plannotator CLI reference |
| run | built-in | ~120 | launch the project's app |
| loop | built-in | ~120 | recurring prompt on an interval |
| workflow-authoring | built-in | ~80 | Workflow script reference |
| keybindings-help | built-in | ~80 | customize keyboard shortcuts |
| artifact-diagramming | built-in | ~70 | diagrams in artifacts |
| artifact-design | built-in | ~70 | artifact design guidance |
| session:reset-counter | plugin session | ~70 | clear statusline mode counters |
| fewer-permission-prompts | built-in | ~60 | build a permission allowlist |
| simplify | built-in | ~60 | cleanup pass on changed code |
| open-file | ~/.claude/skills | ~30 | open a file or URL |
| security-review | built-in | ~30 | security review of pending changes |
| init | built-in | ~20 | create CLAUDE.md |
| plannotator-review, -last, -annotate; user-prefs:explainer; session:base, pipeline, review, codex, pool-* | user / plugins | 0 | not listed by /context: user-invocable only |

## Messages, first turn: 7.1K
| artifact | source | tokens | purpose |
|---|---|---|---|
| system reminders around `hi` | harness | ~6.2K | CLAUDE.md echo, tool and skill reminders, task-tool nudge; falls to 0.9K when tools are denied |
| the prompt `hi` and the assistant reply | | <0.1K | |
| model auto-invoking `/session:base` (variant 1 only) | CLAUDE.md rule | +0.2K in variant 1 (7.3K) | the JSONL total is taken before it |

## Reconciliation
10.2 (prompt) + 32.6 (tools) + 0 (MCP) + 1.8 (agents) + 1.9 (memory) + 3.3 (skills) + 7.1 (messages) = 56.9K; usage 56901. Unexplained: the per-tool split of the 32.6K (which tools are deferred in the baseline) and the identity of the 7.8K tool block gated by telemetry.

Hooks installed (all from plugins, none in ~/.claude/settings.json):
- user-prefs: PreToolUse Bash (bash-bg-tracker.sh, fork-bash-guard.sh), PostToolUse BashOutput|KillShell, SessionStart/SessionEnd/SubagentStart/SubagentStop (fork-tracker.sh), Stop (lang-format-check.sh, notify.sh), Notification (notify.sh)
- session: SessionStart/UserPromptSubmit/PreCompact/PostToolUse Skill (session-modes.sh), SubagentStop (pipeline-subagent-stop.sh)
- plannotator: PreToolUse EnterPlanMode, PermissionRequest ExitPlanMode
