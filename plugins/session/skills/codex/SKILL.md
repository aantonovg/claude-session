---
name: codex
description: Loaded on top of the session base: sends helper jobs of named kinds to the codex CLI (luna, terra as executors; sol, astra for a narrow analysis, alone or paired with the Claude helper) through the codex helper of this plugin.
disable-model-invocation: true
---

# Codex axis

Loaded on top of the session base. Only the executor of a helper job changes; the launcher (main,
before the fork), the result directories and the three handback lines stay as the base states them.
A codex job is a `session:helper` launch: alone with `helper: codex`, or paired with a Claude
helper through the `codex` argument of the same launch.

## Modes

Two axes, multiplied. Executor axis: the jobs of the cost helpers (`runner`, `applier`, `finder`,
`extractor`) go to codex instead of the Claude helper. Heavy axis: the jobs of the quality helpers
(`checker`, `breaker`) go to codex, or run on both.

| heavy axis | executor axis |
|---|---|
| `none`: Claude helpers as in the base | `none`: the same |
| `sol`: replace `checker` and `breaker` with `helper: codex` on `sol-medium`, `sol-high` for the hardest one | `luna`: cost-helper jobs as `helper: codex` on `luna-high` |
| `astra`: the same on `astra-medium`, `astra-high`; sol not used | `terra`: as luna, plus the heavy executor jobs on `terra-high` |
| `+sol`: pair: the Claude `checker` or `breaker` launch carries `codex: sol-medium` (or `sol-high`) | |
| `+astra`: the same pair with astra | |

Single axis: `luna`, `terra`, `sol`, `astra`, `+sol`, `+astra`. Combos `<heavy>-<exec>`:
`sol-luna`, `sol-terra`, `astra-luna`, `astra-terra`, `+sol-luna`, `+sol-terra`, `+astra-luna`,
`+astra-terra`. Invocation `/session:codex <mode>`, at any point of the session.

## Start (do this now)

1. Parse the argument: `sol-luna` = heavy `sol`, exec `luna`; `sol` = heavy `sol`, exec `none`;
   `luna` = heavy `none`, exec `luna`; `+sol` = pair, exec `none`. With an argument, ask the user
   nothing. Without one, ask two questions with `AskUserQuestion`, recommended option first: who
   does the narrow checks (Claude helpers; Claude paired with sol or astra; sol or astra alone) and
   who does the executor jobs (Claude helpers; luna; terra).
2. One Bash call; a missing wrapper is BLOCKED, say so:
   ```
   codex --version; for d in $(ls -d ~/.claude/plugins/cache/claude-session/session/*/bin 2>/dev/null | sort -rV) ~/projects/claude-session/plugins/session/bin ~/.claude/bin; do [ -x "$d/codex-exec-logged.sh" ] && CODEX_BIN=$d && break; done; ls "$CODEX_BIN/codex-exec-logged.sh" "$CODEX_BIN/codex-style.md"
   ```
3. Reply one line: `Codex: <mode> (heavy <…>, exec <…>); fallbacks <…>.`
4. Exchange directory, one per job: the result directory of the launch (`out` of
   `session:helper`; `out/codex` in a pair). Prompt and output files live there.

## How a codex job runs

### Alone (`sol`, `astra`, `luna`, `terra`)

Main launches `session:helper` with `helper: codex` and `ask` opening with this header block:

```
CODEX TARGET: <tier>-<effort of the mode>
CODEX CWD: <repository root>
CODEX OUTPUT FILE: <out>/output.md
CODEX LABEL: <mod>-<eff>-<tier>-<job>
RESULT DIR: <out>
CODEX ASK:
```

After `CODEX ASK:` comes the contract the Claude helper of that kind would get: the goal, the
object by absolute path, the constraints, the result file at `<out>/output.md`, the required last
line.

- The codex helper writes that text to `<out>/prompt.md` verbatim and runs; a prompt file written
  beforehand can be named with `CODEX PROMPT FILE:` instead.
- Codex reads the repository and the paths named, never `~/.claude`; a SKILL.md it needs is named
  by path inside the ask.
- The codex helper runs on its fixed seat under the class table; the launcher names no cell for it.
- Main consumes the three handback lines; the summary is the last line of the codex answer. The
  fork reads the output file by path, never retold.

### Paired (`+sol`, `+astra`)

Main launches the Claude `checker` or `breaker` as usual and adds `codex: sol-medium` (or
`sol-high`, `astra-medium`, `astra-high`) and `cwd` to the same launch. The workflow runs both on
the same contract in parallel: two result directories, two sets of handback lines. The fork reads
both result files and takes what evidence stands; it never merges the two into a longer list.

### Executor jobs

Executor jobs run inside codex's workspace-write sandbox, in the repository root (`CODEX CWD`). A
job that edits the repository does the edit, runs the check named in the ask and returns the
status. The fork reads the diff at the risk level of the change; the reported check counts as run,
not as proof that the change is right. A `partial` or a failing check: main launches one more
codex run with the failing lines and the hypothesis, then the gap goes to the fork. Choosing an
executor mode is the user's permission for codex edits in that task.

## Rules

- A job stays on a Claude helper when it needs MCP (Jira, GitLab, Confluence), a tool codex lacks,
  or a skill codex cannot read by path.
- Heavy jobs (sol, astra) analyze one property with evidence, within 5 tool calls at medium and 3
  at high; they never review a tested object and never read the repository at large.
- No mode change in the middle of a task. A `CODEX CLI ERROR` naming the quota is a fallback, not
  a mode change: executors fall back to `luna-reserve-high`, heavy jobs to the Claude helper, and
  the launch label gets the suffix `-fallback`.
- No effort or model outside the sets above; no `danger-full-access`, no bypass flag (the helper
  refuses them anyway).
- Cost: `tools/pipeline-cost.py` joins the codex rows of `~/.codex/proxy-usage.jsonl` by model,
  effort and time window; give parallel codex jobs distinct labels.
