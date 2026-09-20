# Tool plugin pattern

One plugin per MCP server or tool group. A tool plugin adds carriers; it never changes, replaces or
depends on the plugin this repo builds. The contract line a workflow prints at session start is the
only link between the two: the main model reads the contracts it has and picks a carrier from them.

## What a tool plugin carries

| file | what it holds |
|---|---|
| `.mcp.json` | the server: command, args, env. One server per plugin, or one tool group |
| `agents/tools-<server>*.md` | one agent per tool group, its `tools:` line naming that server's tools (`mcp__<server>__<tool>`) plus the built-ins the job needs. No model and no reasoning level in the file: the call site passes both from the class the launch names |
| `workflows/*.js` | the jobs that need those tools, one file per job, each with a `/* usage: */` block that fits the contract cap. The common role workflow of the base plugin never carries a tool-server role |
| `.claude-plugin/plugin.json` | name, version, description, and one `SessionStart` hook entry per workflow, each printing that workflow's contract line |
| `bin/contract.sh` | the plugin's own contract printer: it reads the `/* usage: */` block of one workflow file, replaces every `{ROOT}` with the absolute plugin root, and prints one line of SessionStart JSON. Each plugin carries its own copy, so no plugin depends on another one's script |
| `skills/` (optional) | a skill that explains the tool itself, when the tool needs explaining |

`{ROOT}` is how a plugin hands its own absolute paths to the session: the hook knows
`CLAUDE_PLUGIN_ROOT`, the workflow script does not, so a path that lives inside the plugin
(a data file, a schema, a store) is written as `{ROOT}/...` in the usage block and reaches the
launcher already resolved.

## Where it lives and how it is switched

- The plugin directory lives outside this repo, next to the other plugins of the user's
  marketplace (today: `/Users/aleksandr.antonov/projects/claude-settings/plugins`). Real cases
  there are `gitlab`, `grafana`, `kubernetes` and `atlassian` (directory `jira`): each is an
  `.mcp.json` plus a `plugin.json` with no agents, no workflows and no hooks yet. `playwright`
  exists only as an `.mcp.json` in a project and has no plugin at all.
- **Enabled at user level**: `~/.claude/settings.json`, `"enabledPlugins": {"<plugin>@<marketplace>": true}`.
- **Disabled per project**: the same key set to `false` in `<project>/.claude/settings.json`. A
  project `false` beats a user `true`: no hook of that plugin runs, no contract line is injected and
  none of its agents is listed. That is how a project takes a tool away.
- **A tool taken away inside a project**: a bare tool name in the project's `permissions` `deny`
  list removes that tool from the session's tool list, and an agent whose file lists the tool does
  not get it either — the agent runs and reports the tool missing. The stage then picks another
  carrier from the contracts that are present, and the harness gate names the gap in one line.
- **A plugin can not deny anything.** A `permissions` block inside a `plugin.json` has no effect
  (measured, not assumed): the plugin loads and the listed tool still works. Plugins only add;
  removal is the project's job, through the two keys above. Neither the template nor the stub
  carries a `permissions` key for that reason.

## Self-containment

Nothing inside a tool plugin names a path, an agent, a workflow, a skill or a hook of another
plugin, and nothing outside it names one of its carriers. A plugin that is disabled or a tool that
is denied then costs a capability, never a broken flow. `tests/rebuild/toolplugin.sh` proves it for
the template and for the stub fixture: both pass the contract and agent oracles against their own
root, and neither names anything of the base plugin.

## The template

`docs/tool-plugin/template` is a working skeleton around an imaginary `example` server: copy the
tree, rename `example` to the server, replace `.mcp.json`, keep one agent per tool group and one
workflow per job, and keep `bin/contract.sh` as it is. `tests/rebuild/fixtures/tool-stub` is the
same pattern with no server at all: its agent reads a metrics file through a shell, which is what
lets the behavior runs prove that an enabled plugin widens what a stage can do.

## First candidates to move out

The artifact pair is the first candidate: the two agents deleted with the old set did their work
through the `Artifact` and `DesignSync` tools, which come from an MCP server, so under the
self-containment rule they belong in a tool plugin of their own, not in the base plugin. Version
0.16.0 accepts the loss and leaves the decision open; the usage numbers of those two agents decide
only whether that plugin is a must or stays a candidate. A browser plugin around `playwright` is
the second candidate, for the same reason.
