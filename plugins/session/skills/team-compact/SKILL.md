---
name: team-compact
description: Park a running team (modes team or team-forks) for the night or between days. Every teammate folds its context into a file, the main session writes its own state file and a team.md manifest, then stops the teammates and the ping cron. session:team or session:team-forks restores the team from these files. Invoke only on the user's word.
disable-model-invocation: true
---

# Team compact

tmux teammates die when the main session exits or the tmux server restarts, so a team
that spans days is parked in files, not in native compacts. Everything written here is
output only; nothing re-reads a big history.

## Steps (do all of them now)

1. **Directory.** `<dir>` = `~/.claude/projects/<encoded-cwd>/team-compact/<stamp>-<slug>/`
   where `<encoded-cwd>` is the current working directory with `/` replaced by `-`,
   `<stamp>` is now as `YYYY-MM-DD-HHMM` (`date +%Y-%m-%d-%H%M`), `<slug>` is 2-4
   lowercase words joined by `-` that say what the team was working on
   (`retry-logic-mr`). Always a new directory; never reuse an earlier one. `mkdir -p <dir>`.

2. **Teammates fold.** Send every live teammate the same message (`SendMessage`, one per
   teammate, all in one turn):

   ```
   Fold your context into <dir>/<name>.md, at most 300 lines, sections: Goal, Current
   state, Decisions taken, Open items, Files and commands I rely on. Write it with the
   Write tool, then reply exactly: DONE <path>. Do nothing else.
   ```

   Wait for every `DONE`. A teammate that does not answer within a few minutes gets one
   reminder; if it still does not answer, note it as "no file" in `team.md`.

3. **Main state.** Write `<dir>/main.md` with the same five sections about this session:
   the task, where it stands, decisions, open items, files and commands. Under 300
   lines. This file is what a fresh session reads tomorrow instead of this history.

4. **Manifest.** Write `<dir>/team.md`:

   ```
   # <one-line recap of the work>
   mode: team | team-forks
   sub-mode: light | full
   class: <1-5>
   main: model <id>, effort <level>, file main.md
   teammates:
   - name: <name>; roles: <roles>; model: <full id>; effort: <level>; file: <name>.md
   ...
   ```

5. **Stop.** Delete the `ping` cron of this session (`CronList`, then `CronDelete`).
   Ask each teammate to shut down (send `{"type": "shutdown_request"}`) and confirm they
   are gone with `ListAgents`.

6. **Report.** One line to the user: the directory, the number of files, and the way
   back: tomorrow start a fresh session in the same directory and run
   `/session:team` (or `/session:team-forks`); the compact appears in the menu, or pass
   the directory as the argument.

## Not part of this skill

- No native `/compact` and no `/clear` are run here; the user decides what to do with
  this session after the files are written (see "Compact prices" in the plugin README
  for when a warm `/compact` is worth it).
- The teammate files are not read by the main session; it only records their paths.
