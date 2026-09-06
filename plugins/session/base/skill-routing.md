# Skill routing map
Which skill goes into which workflow agent. The main session picks 0-3 per `agent()` prompt: role picks the column, step picks the entry. Format: `skill — role(s) — when to inject`.
This file covers the bundled CLI skills, identical on every machine. Per-machine skills (plugins, user-level and project skills) are listed in `~/.claude/memory-user/skill-routing.md` when that file exists.

## Shared: bundled CLI skills

### Inject into stages
- `dataviz` — any author — any chart, plot, graph, dashboard or stat tile, in any medium.
- `artifact-design` — any author — any published artifact page, Markdown included.
- `artifact-diagramming` — any author — an artifact page that needs a diagram.
- `artifact-capabilities` — any author — an artifact that stores state, reads live data or asks Claude a question.
- `update-config` — executor — editing Claude settings, permissions, env vars or hooks.
- `claude-in-chrome` — any agent — browser automation; before any `mcp__claude-in-chrome__*` call.
- `run` — executor — launching the project app to confirm a change.
- `code-review` — reviewer-debugger — reviewing a diff, branch or PR. Never inject it at the `ultra` level: there it spawns its own agents.
- `security-review` — reviewer-debugger — auth, secrets, input or network-facing changes.
- `simplify` — code/test fixer — reuse and simplification pass, quality only.

### Main session only, never inject into a stage
`workflow-authoring`, `loop`, `schedule`, `keybindings-help`, `fewer-permission-prompts`.
They drive the session itself (or spawn their own agents) and conflict with Workflow pipelines.

### Never anywhere
`claude-api` — Claude Code and Anthropic API questions go to the `claude-code-guide` agent instead.
