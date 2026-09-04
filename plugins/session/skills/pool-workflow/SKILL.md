---
name: pool-workflow
description: Session mode 9, workflows over a pool of warm worker sessions. The main session keeps its context small (forks for recon), each Workflow stage is a pool-proxy agent on haiku that hands a task file to a warm worker started by poold and returns a result file. No teammates, no plain subagents. Invoke at the start of a session for multi-stage work with review/fix cycles and mixed models.
disable-model-invocation: true
---

# Mode: pool-workflow

The workflow script stays the visible pipeline (stages, review loops, resume); the
tokens are spent in warm worker sessions that the `poold` daemon runs in tmux. Each
`agent()` of the script is a `pool-proxy` (haiku, Bash only) that submits a task file
to a worker and waits for the result file. The main session writes task files, runs the
script and reads result files; heavy reads of its own go to forks.

## Start (do this now)

1. First tool call: `CronCreate` with `cron: "*/30 * * * *"`, `prompt: "ping"`,
   `recurring: true` (a `ToolSearch` to load the tool may come first). Reply to every
   `ping` with one word.
2. `poolctl status` (`~/projects/claude-session/pool/poolctl`, or on PATH). If the
   daemon is not reachable, say so and stop; the user starts it.
3. Reply with one line: "Pool-workflow mode on, ping cron <id>; pool <key>, workers:
   <names or none>."

## Per task

1. **Recon** in forks (`subagent_type: "fork"`), as in `session:forks`: read the ticket,
   the code, MCP sources; return facts. Decide the task class (1-5) and sub-mode:
   light = one worker per unique combo of the selection-map row, full = one worker
   per role. Say the class and the reason in one line; ask only if it changes the work.
2. **Workers**: read the class row of `~/.claude/session-map.md` (fallback: the table
   in the plugin README), then

   ```
   poolctl ensure --need <opus-low,sonnet-low | reviewer=opus-medium,author=opus-low,...> --json
   ```

   Keep the returned pool key and worker names. Shared pool by default; `--pool
   dedicated --owner <session id>` only when the user asked for one.
3. **Task files**: one file per stage under
   `~/.claude/projects/<encoded-cwd>/pool-tasks/<YYYY-MM-DD-HHMM>-<stage>-<hash>.md`
   (`<encoded-cwd>` = cwd with `/` replaced by `-`; `<hash>` = first 8 hex chars of
   the file's sha1, appended after writing). Outside the repo so nothing lands in the
   working tree by accident, next to the other per-project state (`team-compact/`,
   `questions/`). The daemon copies each file into its own `tasks/` dir on submit. The
   hash is part of the name because a workflow `resume` returns the cached `agent()`
   result for an unchanged prompt: a changed task must have a changed path.

   Task file layout, same as a teammate stage message: role line first, the task,
   files, acceptance criteria, then the skill line ("Load these skills with the Skill
   tool before starting: …" from the skill-routing map, or "No skills needed"), then
   the return contract: write the result to the path the worker was briefed with,
   last line `DONE` or `BLOCKED: <action>`, at most N words, no file contents.

   Result convention (benchmark 2026-09-04: worker output was 3x the plain run):
   the deliverable goes into a project file (PLAN.md, REVIEW-N.md, code, tests), and
   the result file holds only the status line, the paths of the files produced and at
   most 5 lines of summary. Never ask the worker to "copy it into the result file",
   and never ask for the content back in the pane: the main session reads the
   project file itself.
4. **Script**: load `workflow-authoring`, then

   ```js
   export const meta = { name: 'c<class>-<pairing>-<slug>', description: '...', phases: [...] }
   const POOL = '<pool key>'
   const proxy = (worker, file, label, phase) => agent(
     `POOL: ${POOL}\nPOOL WORKER: ${worker}\nPOOL TASK FILE: ${file}`,
     { agentType: 'pool-proxy', model: 'haiku', effort: 'medium', label, phase })
   const last = r => (r || '').split('\n').find(l => l.startsWith('LAST LINE:')) || ''
   const done = r => last(r).includes('DONE')
   const file = r => ((r || '').match(/POOL RESULT FILE: (.*)/) || [])[1]
   ```

   Two rules that keep the cost floor low (the cost of a workflow is mostly the tool
   output the agents consume and reread, not the model prices):

   - **Convergence gate.** After a review stage, read REVIEW-N.md. If it has no medium
     or high findings, skip the fix and check stages of that cycle and end the cycles;
     go to the final check. Do not run three cycles by habit.
   - **Tool-output caps** in the task files. Before each stage tag the tree
     (`git tag stage-<n>`); a reviewer reviews `git diff stage-<n-1>..HEAD`, not whole
     files, and opens a full file only when the diff does not explain itself. A checker
     returns only PASS/FAIL lines and the last 20 lines of failing output. Authors and
     fixers run tests with the quietest reporter available.

   Header lines in that exact order and spelling: every proxy of the run shares the
   same system prompt and header, so the second and later proxies read the first
   one's prefix from cache. Stages: plan → review → fix (1-3 cycles), red tests →
   review → fix, implementation → review → fast tests → fix; the review worker is a
   different worker from the author (same rule as forks). Parallel stages go to
   different workers in one `parallel()`; two stages on one worker queue in the
   daemon. Gate every stage on `done(r)`; a `BLOCKED` last line or a `BLOCKED:` proxy
   answer ends the workflow with `return { blocked: last(r), file: file(r) }`. Log the
   result file path per stage. Each proxy takes a `POOL MAX WAIT` line when a stage
   may run longer than 100 minutes.
5. **Read results** from the files the script returns (one Read each, or a fork when
   there are many); the workflow journal already shows the stage flow. Resume a
   stopped run with `Workflow({scriptPath, resumeFromRunId})` after editing the task
   files that changed.
6. **End**: leave the workers to the daemon (it keeps them warm and compacts them at
   day end); `session:pool-stop` parks them when the user says so.

## Forbidden in this mode

- No named teammates, no `general-purpose` / `Explore` / other custom agents in the
  script; only `pool-proxy` in `agent()` and `subagent_type: "fork"` for recon.
- The session never types into worker panes, never pins `/model` or `/effort` there,
  never compacts a worker.
- No `/model`, `/effort`, plugin changes or `/compact` of this session mid-task.

## Reference

Mode 9 in `plugins/session/README.md`: protocol, daemon policies, costs, probes.
