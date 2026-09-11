# Agent trim: minimum tools, skills, bodies (plan, 2026-09-11)

Source data: `$CLAUDE_JOB_DIR/tmp/agent-context-report.en.md` (measured start usage per agent, sonnet, plugin 0.10.1).

Cost model inside an agent (measured): tool-block wrapper 1.5K once; Bash 4.2K; Read 0.9K; Edit 0.6K; Write 0.35K; ToolSearch 0.5K; WebFetch+WebSearch 1.4K; Grep and Glob 0 (not loaded in auto mode); a preloaded skill costs its body, and a skill switched off by `skillOverrides` is silently not preloaded. Fixed per agent: harness blocks 0.3K, CLAUDE.md echo 1.5K, environment 0.3K.

Rule for every cut: an agent must still be able to finish its role's job in the common case. When it cannot, it returns `BLOCKED: <needed tool>` and the main session relaunches it with a wider set. Never remove the tool the role is named after (Bash for an executor, Write for an author, Artifact for a publisher).

## Per agent

| agent | role (base) | tools now | tools proposed | removed, why | can it get stuck? | skills | body | expected start |
|---|---|---|---|---|---|---|---|---|
| codex-proxy | shim: runs `codex exec` through the wrapper, returns the output path and its last line | Bash, Read, Write | Bash | Read: the last line comes from `tail -1` in Bash; Write: the prompt file is written by the main session, the output file by codex | No: every step is a shell command | none | 15.5K chars to at most 4K: keep the header contract, the wrapper invocation, the escalation preamble rule, the return format; move the long permission-set explanation and examples to `README.md` | 14.8K to about 10K (body 15.8K to 6.7K chars, contracts kept verbatim) |
| stage-researcher | fact researcher: reads code, git history, docs; writes a notes file | Bash, Read, Grep, Glob, ToolSearch, WebFetch | Bash, Read, Write | ToolSearch and WebFetch: web research now belongs to web-researcher; Grep, Glob: free but listed for nothing | Notes file needs Write (today it uses Bash heredocs; Write is cleaner and 0.35K) | none | trim the "Details moved" paragraph if it repeats the harness notes | 9.9K to about 9.5K |
| stage-author | code/test author | Bash, Read, Edit, Write, Grep, Glob | Bash, Read, Edit, Write | Grep, Glob: free, cosmetic | No | none | no change | 10.1K, unchanged |
| stage-executor | test/script executor | Bash, Read, Grep, Glob | Bash, Read | Grep, Glob: cosmetic | No | none | no change | 9.1K, unchanged |
| stage-reviewer | document reviewer, 3-5 tool calls | Read, Write | Read, Write | nothing | No | none | no change | 5.5K, unchanged |
| stage-critic | clean-context critic | Read, Write | Read, Write | nothing | No | none | no change | 5.5K, unchanged |
| waiter | long waits with judgment, tmux and JSONL polling | Bash, Read | Bash, Read | nothing | No | none | 2.5K chars to about 1.5K: drop the duplicated dialog rules that the launch prompt always carries | 9.4K to about 9.2K |
| web-researcher | web search and fetch, notes by path | WebFetch, WebSearch, Read, Write | WebFetch, WebSearch, Write | Read: inputs arrive in the prompt; notes are written, not read | If asked to compare with a local file it returns BLOCKED; acceptable | none | no change | 6.8K to about 5.9K |
| code-reviewer | diff review on sonnet | Read, Grep, Glob, Bash | Read, Bash | Grep, Glob: cosmetic | No: `git diff` and file reads cover the job | keep `code-review` preloaded (2.2K, the review procedure; the skill is on) | no change | 11.3K, unchanged |
| simplifier | cleanup pass that applies fixes | Read, Edit, Bash | Read, Edit, Bash | nothing: Bash is needed for `git diff` and the test run after the fix | No | `simplify` is off in skillOverrides, so the preload does nothing; keep the inlined rules, drop the `skills:` line to stop pretending | no change | 9.9K, unchanged |
| security-reviewer | security pass, findings only | Read, Grep, Bash | Read, Bash | Grep: cosmetic | No | `security-review` off; same as simplifier: drop the `skills:` line, keep inlined rules | no change | 9.3K, unchanged |
| artifact-publisher | publish an HTML page from files | Artifact, Read, Write, Bash | Artifact, Read, Write | Bash: the page is composed with Read and Write; no shell step in the role | Converting sources with a CLI tool would block; the main session then prepares the HTML first | `artifact-design`, `artifact-capabilities` are off, preload does nothing; drop the `skills:` line, keep inlined rules | no change | 9.7K to about 5.5K (plus 14.8K Artifact where allowed) |
| artifact-designer | same with the design canvas | Artifact, DesignSync, Read, Write, Bash | Artifact, DesignSync, Read, Write | Bash: same reasoning | same | `design`, `dataviz`, `artifact-*` are off; drop the `skills:` line | no change | 9.7K to about 5.5K (plus Artifact and DesignSync where allowed) |
| user-prefs:Explore | belongs to the user-prefs plugin, not this one | Bash, Glob, Grep, Read, WebFetch, WebSearch | out of scope; note for that plugin: WebFetch and WebSearch cost 1.4K in a repository explorer | | | | | 10.4K, unchanged here |

## Skill tool and skills preload

- No plugin agent has the `Skill` tool; none should get it. The base injects skills by prompt ("Load these skills with the Skill tool") only for cold stage agents launched with an explicit skill list; those launches must add `Skill` to the agent's tools for that run (Workflow `tools` opt) or the agent cannot load anything. Today the skill-routing map names project skills for the executor and researcher roles (macup steps, grepai, release, backup-db). Rule: an agent file never lists `Skill`; a launch that names skills passes `Skill` explicitly. Document this in BASE.md (one sentence).
- `skills:` preload is kept only where the skill is on and always needed: code-reviewer (`code-review`). All other `skills:` lines are removed as dead (their skills are off by `skillOverrides`); the agents keep the inlined rules they already have.

## Body trims

- codex-proxy: the only large body. Target at most 4K chars. Keep: the header contract (CODEX TARGET, CWD, PROMPT FILE, OUTPUT FILE), the target-to-model map, the wrapper command, the escalation preamble rule, pass-by-reference rule, the return format. Move to README: the long permission-set rationale and examples.
- waiter: remove the paragraph that repeats the launch template's dialog rules; keep the mandate and the return format.
- All: delete any sentence repeating the harness "Notes" block (cwd reset, background children) since the harness sends it anyway.

## Expected effect

Per launch: codex-proxy -5.3K, artifact agents -4.2K each (their common case), web-researcher -0.9K, stage-researcher -0.4K, waiter -0.2K. The stage agents, reviewers and code-reviewer stay as they are; their tool sets are already minimal for the role.

## Verification

1. Rerun `$CLAUDE_JOB_DIR/tmp/agentctx-run.sh` after the reinstall; compare `agentctx-result.log` with the numbers above; accept when each changed agent is within 0.5K of its expected start and no agent grew.
2. Smoke: codex-proxy with a trivial prompt file returns the output path and last line using Bash only; artifact-publisher returns `BLOCKED: Artifact` in a project with the deny, not an error; web-researcher returns a fetched fact with the three tools.
3. `tests/session-modes-hook.sh` still 72/72.

## Risks

- An agent stuck without a tool: mitigated by the BLOCKED rule in every body and a relaunch with a wider set from the main session; the cost of one failed launch is under 10K.
- codex-proxy body trim drops a rule the wrapper relies on: keep the wrapper script as the source of truth and reference it by path in the body.
- Skill injection by prompt into an agent without `Skill`: the launch fails silently; the BASE.md sentence closes this.

## Version

Bump to 0.10.2; README log line: "0.10.2: agent tool sets cut to the role minimum, dead skills: lines removed, codex-proxy and waiter bodies trimmed, Skill tool passed per launch". No push.

## Applied (0.10.2)

- Skill tool: added to no agent. Stage agents read skill files by path (Read); BASE.md prompt
  template changed to "Read these skill files with the Read tool: <absolute SKILL.md paths>".
- codex-proxy: Bash only; body 15.8K to 6.7K chars (the 4K target could not hold the header,
  model map, preamble, invocation and error contracts verbatim); permission-set rationale moved
  to README "codex-proxy permission set".
- artifact agents: Bash dropped; bodies return `BLOCKED: Bash` for binary assets or CLI
  conversion (critique high 3 accepted as an explicit BLOCKED path, not silent failure).
- web-researcher: Read dropped, file written once, `BLOCKED: Read` for local-file tasks.
- Grep, Glob, ToolSearch, WebFetch removed from stage agents; dead `skills:` lines removed
  from simplifier, security-reviewer, artifact-publisher, artifact-designer.
