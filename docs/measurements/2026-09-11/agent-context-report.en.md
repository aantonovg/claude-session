# Start context of every custom agent (sonnet, empty project, plugin 0.10.1)

Measured 2026-09-11: each agent launched once through `Workflow` from a sonnet test session in `~/projects/empty-context-test` (Artifact and DesignSync denied there, so the two artifact agents ran without them). Numbers: API usage of the agent's first request (exact) and character counts of the prompt parts from the agent's JSONL (`prompt_snapshot` and attachments), converted at 4 chars per token. The tool-schema column is the remainder: usage minus everything else, so it also holds the tool-block wrapper (about 1.5K that every agent with at least one tool pays).

## Per agent

| agent | description, tokens | start usage, tokens | agent body (system prompt) | harness blocks | CLAUDE.md echo | other attachments | tool schemas (remainder) | tools |
|---|---|---|---|---|---|---|---|---|
| session:codex-proxy | 101 | 14775 | 3.9K (15.5K chars) | 0.3K | 1.5K | 0.3K | 8.7K | Bash, Read, Write |
| session:code-reviewer | 38 | 11341 | 0.5K | 0.3K | 1.5K | 0.3K | 8.7K, includes the preloaded `code-review` skill, about 2.2K | Read, Grep, Glob, Bash |
| session:stage-author | 44 | 10066 | 0.4K | 0.3K | 1.5K | 0.3K | 7.5K | Bash, Read, Edit, Write, Grep, Glob |
| session:stage-researcher | 41 | 9898 | 0.4K | 0.3K | 1.5K | 0.4K (deferred names) | 7.3K | Bash, Read, Grep, Glob, ToolSearch, WebFetch |
| session:simplifier | 38 | 9865 | 0.5K | 0.3K | 1.5K | 0.3K | 7.2K | Read, Edit, Bash |
| session:artifact-designer | 44 | 9713 | 0.5K | 0.3K | 1.5K | 0.3K | 7.0K (Artifact, DesignSync absent: denied in the test project; +14.8K and +3.7K when allowed) | Artifact, DesignSync, Read, Write, Bash |
| session:artifact-publisher | 45 | 9657 | 0.5K | 0.3K | 1.5K | 0.3K | 7.0K (Artifact absent, +14.8K when allowed) | Artifact, Read, Write, Bash |
| session:waiter | 50 | 9442 | 0.6K | 0.3K | 1.5K | 0.3K | 6.6K | Bash, Read |
| session:security-reviewer | 29 | 9301 | 0.5K | 0.3K | 1.5K | 0.3K | 6.6K | Read, Grep, Bash |
| session:stage-executor | 40 | 9099 | 0.4K | 0.3K | 1.5K | 0.3K | 6.5K | Bash, Read, Grep, Glob |
| session:web-researcher | 48 | 6797 | 0.4K | 0.3K | 1.5K | 0.3K | 4.2K | WebFetch, WebSearch, Read, Write |
| session:stage-critic | 61 | 5533 | 0.5K | 0.3K | 1.5K | 0.3K | 2.8K | Read, Write |
| session:stage-reviewer | 66 | 5510 | 0.5K | 0.3K | 1.5K | 0.3K | 2.8K | Read, Write |
| user-prefs:Explore (other plugin) | 128 | 10375 | 0.3K | 0.3K | 1.5K | 0.3K | 7.9K | Bash, Glob, Grep, Read, WebFetch, WebSearch |
| general-purpose (built-in) | built-in | 13297 | 0.4K | 0.3K | 1.5K | 1.6K (deferred names 0.55K, skill listing 0.66K, env) | 9.5K | all, Skill included |
| Explore (built-in) | built-in | 10653 | 0.6K | 0.3K | none | 1.6K (deferred names, skill listing, env) | 8.2K | read-only set, Skill included |

## Per-tool cost inside an agent, derived from the pairs above

| part | tokens |
|---|---|
| tool block wrapper, paid once when the agent has any tool | about 1.5K |
| Bash | about 4.2K |
| Read | 0.9K |
| Edit | 0.6K |
| Write | 0.35K |
| ToolSearch | 0.5K |
| WebFetch + WebSearch | about 1.4K together (one of them arrives deferred) |
| Grep, Glob | 0: in auto mode ("bash first") the harness does not load them for agents either |
| preloaded `skills:` entry | the skill body, 2.2K for `code-review`; a skill switched off by `skillOverrides` is not preloaded (simplifier, security-reviewer, both artifact agents show no extra cost) |

## What every agent pays regardless

- Harness agent blocks: launcher note, "Notes" block, token budget line: about 0.3K.
- CLAUDE.md echo: the user's `~/.claude/CLAUDE.md` plus its `skill-routing.md` import, 6.1K chars, about 1.5K. Every custom agent gets it; only the built-in Explore did not.
- Environment, model, session context, date, remote-session hints: about 0.3K.
- So the floor for a custom agent with no tools is about 2.1K plus its body; with Read and Write it is 5.5K; with Bash it is 9K or more.

## What varies

- Tools: Bash alone is 4.2K, so "needs a shell" is the single biggest decision per agent.
- Body: 0.3K to 0.6K for all agents except codex-proxy at 3.9K.
- Skill listing (0.66K) appears only when the agent has the `Skill` tool; none of the plugin agents do.
- Preloaded skills: only skills that are not switched off get injected.
