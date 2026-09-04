---
name: pool
description: Show or start the session pool for this project by hand (mode 9). Runs `poolctl status` and, with an argument, `poolctl ensure --need <combos>`; shared pool by default, dedicated only when the user asks. Invoke to see the warm workers before a workflow or to bring up a pool without a workflow.
disable-model-invocation: true
---

# Pool: show or start workers

The pool is run by the `poold` daemon (`pool/poold.py` in the claude-session repo,
HTTP on `127.0.0.1:19540`), never by this session. This skill is a thin wrapper over
`poolctl` (`~/projects/claude-session/pool/poolctl`, or `poolctl` on PATH).

Argument (optional): `$ARGUMENTS` = the `--need` list, e.g. `opus-low,sonnet-low` or
`reviewer=opus-medium,author=opus-low`, optionally followed by `dedicated`.

## Steps (do now)

1. `poolctl status` for the current cwd. If the daemon is not reachable, say so and
   stop: starting the daemon is the user's job (`poold run`, or the LaunchAgent /
   systemd unit from `pool/units/`).
2. With an argument: `poolctl ensure --need <list>` (`--pool dedicated --owner <this
   session id>` only when the argument says `dedicated`; the shared pool is the
   default because its workers already know the day's tasks and cost nothing extra).
3. Print the table the daemon returned: worker, combo, state (`warm` / `cold` / `busy`),
   context size, pool key. One line per worker, nothing else.

## Rules

- Names come from the selection map row (`~/.claude/session-map.md`): a combo
  (`opus-low`) or `role=combo`. A name that exists is reused; the daemon adds `-2`
  only when the user asks for a second one.
- The session never types into worker panes, never pins `/model` or `/effort`, never
  compacts a worker: the daemon owns the workers. To hand work to them use
  `session:pool-workflow`; to park them use `session:pool-stop`.
