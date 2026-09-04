---
name: pool-stop
description: Park the session pool of this project (mode 9): every worker writes its handoff file, the daemon closes its tmux window; optional warm /compact first. Invoke on the user's word at the end of a task or day.
disable-model-invocation: true
---

# Pool stop: park the workers

Argument (optional): `$ARGUMENTS` = `compact` to run a warm `/compact` on every worker
before parking, or a comma-separated worker list to park only those.

## Steps (do now)

1. `poolctl status` for the current cwd; stop if there are no live workers.
2. If the argument says `compact`: `poolctl compact` (the daemon types `/compact`
   into each warm worker; ≈ $0.1-0.5 per worker while warm). Wait for it to return.
3. `poolctl park [--workers a,b]`. The daemon asks each worker for its handoff file
   (`~/.claude/pool/<key>/park/<name>.md`), waits for it and closes the window.
4. Report one line: pool key, workers parked, where the handoff files are, and that
   `poolctl resume` (or the next `poolctl ensure`) brings them back reading those files.

## Rules

- Only `poolctl`; never `tmux kill-window` or `tmux send-keys` from this session.
- A worker that does not write its handoff file within the daemon's timeout is
  reported as "no file", not retried here.
