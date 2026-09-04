---
name: team-forks
description: Session mode 5, team plus forks. Named tmux teammates on their own models and efforts (light: one per model+effort combo, full: one per role), and both the main session and every teammate hand any job with 3+ tool calls or 3K+ input tokens to a fork subagent. Also restores a team parked by session:team-compact. No plain subagents, no Workflow. Invoke at the start of a session for the biggest tasks.
disable-model-invocation: true
---

# Mode: team-forks

One main session plus named teammates, each a separate `claude` process in a tmux pane
(`teammateMode: "tmux"`), each with its own model and effort, each kept warm and reused
for the whole task. The main session drives the stages, hands out work by role and
merges results. On top of mode team, every context (main and teammates) keeps itself
small by running heavy work in forks: a fork inherits its parent's cached prefix, so
it costs almost nothing to start and its tool calls never land in the parent context.

Argument (optional): `$ARGUMENTS` = a team-compact directory to restore from. Empty =
show the menu below.

## Start (do this now, in order)

### 0. Keep-warm cron, first tool call

Before anything else: `CronCreate` with `cron: "*/30 * * * *"`, `prompt: "ping"`,
`recurring: true` (a `ToolSearch` to load the tool may come first; nothing else may).
Reply to every `ping` with one word. This happens in both branches below (new team and
restore); do not ask the user for the task before step 1 is done.

### 1. Restore or new team

Second tool call, always, even if the user already described a task:

```
ls -dt ~/.claude/projects/<encoded-cwd>/team-compact/*/ 2>/dev/null | head -10 || true
```

`<encoded-cwd>` is the current working directory with every `/` replaced by `-`
(`/Users/me/proj` → `-Users-me-proj`). Keep directories modified in the last 7 days
(`team.md` exists inside). If `$ARGUMENTS` names a directory, use it and skip the menu.

If any are found, ask with `AskUserQuestion` (one question, options = one per compact,
label = the recap line from its `team.md` plus the date, and a last option "New team").
If none, go straight to a new team.

**Restore**: read `<dir>/main.md` (it is this session's own previous state), then
`<dir>/team.md`. Take mode, sub-mode, class and the teammate list (name, roles, model,
effort, file) from it, spawn every teammate exactly as listed (step 3) with the start
message "Read `<dir>/<name>.md` fully. Create a keep-warm cron now: CronCreate cron
"*/30 * * * *", prompt "ping", recurring. Then reply READY and wait for tasks" followed
by the same rules block as a fresh spawn (context small, named skills only, short
replies, deliverables under the project, the fork-prompt skeleton in team-forks). After
the READY replies do the pin step (step 3b) for every teammate, then go to step 4. Do
not ask about class or sub-mode again.

### 2. Recon first, then class and sub-mode (new team only)

The class decides how many teammates and which models, and the class is only known
after looking at the task. So a new team starts in forks style: the main session
explores the task through forks (`Agent`, `subagent_type: "fork"`; any job with 3+
tool calls or 3K+ input goes to a fork, and every Jira, Confluence, GitLab or other
MCP read is a fork regardless of count, because those results are large; the fork
prompt starts with "You are the fact researcher: …" and ends with a return format of at
most N words, no dumps). Read the ticket, the code, the tests, the runbooks this way
until the size of the work is clear. Then ask with `AskUserQuestion`, always, with the
proposed class and a one-line reason in the question text, three options: "No team,
answer directly" (when the recon already answered a small task), "Light team",
"Full team". The user's pick decides; never declare the outcome without asking.

If a team was chosen, read the selection map: `~/.claude/session-map.md` (per-account file: one class × role
table per pairing, the default pairing, the default main model, the full model ids
with their allowed efforts). Use the default pairing unless the user named another
one at invocation (`pairing opus-opus`). If the file is missing, use the fallback
table at the end of this skill and tell the user the file is missing. Propose the task
class 1-5 with a one-line reason based on the recon (the user may have named one at
invocation; confirm it against what the recon showed). Take the row of the chosen
pairing's table for that class. The two
sub-modes (the menu above already offered both; a missing task description is asked as
free text, never as a one-option menu):

- **light**: one teammate per unique model+effort combo of the row, minus the main
  session's own combo. The main session performs the roles of its own combo itself.
  Example class 3 with a fable-low main: main = reviewer-debugger; teammates
  `opus-medium` (plan author/fixer, code/test fixer) and `opus-low` (code/test author,
  fact researcher, test/script executor).
- **full**: one teammate per role the task needs, equal combos not merged, named by
  role; a small task needs three or four (reviewer, author, fixer, executor), a big one
  all six; may also be cut by domain (`api`, `helm-chart`, …) when the task spans
  several areas. The main session only orchestrates.

Show the resulting table (name, roles, model, effort) before spawning.

### 3. Spawn

One `Agent` call per teammate, all in one message:

- `name`: the combo (`opus-low`) or the role/domain (`reviewer`, `api`);
- `model`: the `Agent` tool accepts only the aliases `opus`, `sonnet`, `fable`; pass
  the alias here and put the full id in the prompt. Right after the READY reply, pin
  the variant in the pane: `tmux send-keys -t <pane_id> "/model <full id>" Enter`
  (ids from `session-map.md`) and read the confirmation line with
  `tmux capture-pane -t <pane_id> -p`. Do this before the first task: the reset is
  cheap on an empty context;
- `subagent_type`: omit (a named spawn is a teammate; `fork` would make a one-shot fork);
- `prompt`: the spawn message (template below).

### 3b. Pin model and effort in every pane (new team and restore)

Effort is not an `Agent` parameter either. A teammate starts with the main session's
own effort, so only a teammate whose effort differs needs `tmux send-keys -t <pane_id>
"/effort <level>" Enter`, sent together with the `/model` line above. Panes: the
teammates sit in the main session's tmux window; `tmux list-panes -F '#{pane_id}
#{pane_index}'` lists them (the main session is `$TMUX_PANE`; titles are identical,
never search by title; teammate panes show no status line, so read the command's
confirmation text instead).

Spawn message template:

```
You are teammate <name> of a team run by the main session. Your roles: <roles>.
Model <model>, effort <effort>. Project: <cwd>. Task: <one-line goal>.
Rules: keep your own context for coordination; run every job with 3+ tool calls or
3K+ tokens of input (file sweeps, tests, searches, verification) in a fork
(Agent tool, subagent_type "fork"; parallel forks in one message; the fork's prompt
starts with its role and ends with a return format of at most N words, no dumps;
every wait inside a fork stays under 3 minutes per call). Never spawn plain subagents
or Workflow; never run /model, /effort or /compact yourself; on a permission denial
stop and return BLOCKED: <action>.
Create a keep-warm cron now: CronCreate cron "*/30 * * * *", prompt "ping", recurring.
Reply READY and wait for tasks. Keep every later reply to DONE plus at most 5 lines.
Load only the skills a stage names; keep your own context small, big reads go to forks.
Deliverables (plans, reports) go under the project or the path the main session names,
never into a scratchpad that dies with the session.
```

In mode team-forks the spawn message also carries this fork-prompt skeleton, which the
teammate copies for every fork it spawns:

```
Every fork you spawn gets a prompt shaped exactly like this:
  You are the <role>: <one-line goal>.
  <task, files, acceptance criteria>
  Return only <facts | diff summary | PASS/FAIL>, at most <N> words, no dumps.
  Every wait under 3 minutes per call; long jobs run_in_background and are polled.
  On a permission denial stop and return BLOCKED: <action>.
```

### 4. Go

Step 3b is done for every teammate (one `tmux send-keys` with `/model <full id>` per
pane, plus `/effort` where it differs) before the team is announced; a team announced
without the pin lines in the transcript is a mistake. If the `tmux send-keys` call is
denied (permission or classifier), stop: report the denial and the exact command to
the user and do not dispatch stages, because an unpinned teammate may run on a 200K
context and thrash on the first big read. The user can add an allow rule
(`Bash(tmux send-keys *)`) or type the `/model` line into the pane. Every teammate creates its own cron (it is in the spawn message; check the READY
reply mentions it). Every teammate `pong` reaches the main session as a notification
turn, so once the team is up the main session's own cron is redundant: delete it
(`CronDelete` the id from step 0); the teammates' notifications keep the main context
warm. If a teammate cannot create crons, keep the main cron and let its ping turn send
`SendMessage("ping")` to that teammate. Cost floor: one main-context read plus one
teammate read per teammate per 30 minutes; keep the main context small, prefer light,
and park an idle team with `session:team-compact` instead of keeping it warm for hours. Tell the user the team is up (names,
models, efforts) and start the first stage.

## Working in this mode

- Stages from the README: plan → review → fix; red tests → review → fix;
  implementation → review → fast tests → fix; 1-3 cycles each, exit on a clean review.
  Technical stages (prep, commit, conflicts) go to the executor role without review.
- Each stage is one `SendMessage(to: <name>, …)` to the teammate that owns the role.
  `Agent` with an existing name spawns a second instance (`<name>-2`), so it is only
  for replacing a teammate that died or thrashed, never for sending work. In light, name the role in the message ("acting as code/test author:
  …"). Review and fix are never done by the same teammate in full; in light they are by
  design different combos.
- Every teammate reply lands in the main context, so ask for short replies: "reply
  DONE plus at most 5 lines" (full details go to files or the task list). Results
  always travel in the reply body or in a named file; an idle notice carries nothing
  and needs no reply.
- Messages are self-contained: goal, files, acceptance criteria, the 0-3 skills to load
  (from the skill-routing map), the return format. Land messages carry repo, branch,
  expected changed files and a one-line summary.
- A `BLOCKED: …` reply stops the stage; report to the user, never re-run a review
  against unchanged files.
- Extra teammates mid-task only after agreeing with the user.
- The main session forks too: any job of its own with 3+ tool calls or 3K+ input goes
  to a fork with a role line first and a return format last; small things it does
  itself. Review and fix are always different forks.
- Outside plan mode a fork may use any Bash; in plan mode forks avoid `$var`, `$(…)`
  and loops (they prompt the user there).

## Forbidden in this mode

- No plain subagents (`general-purpose`, `Explore`, custom agent types) and no
  `Workflow`, for the main session and for the teammates. Forks only.
- No `/model`, `/effort` (after the initial setting), plugin changes or `/compact`
  mid-task. Parking the team for the night is `session:team-compact`, on the user's
  word.

## Fallback selection map (only when `~/.claude/session-map.md` is missing)

Pairing fable-opus, subscription account:

| Class | Reviewer-debugger | Plan author/fixer | Code/test fixer | Code/test author | Fact researcher | Test/script executor |
|---|---|---|---|---|---|---|
| 1 very simple | opus-low | opus-low | opus-low | opus-low | opus-low | opus-low |
| 2 simple | opus-medium | opus-low | opus-low | opus-low | opus-low | opus-low |
| 3 medium | fable-low | opus-medium | opus-medium | opus-low | opus-low | opus-low |
| 4 complex | fable-medium | fable-low | opus-medium | opus-medium | opus-low | opus-low |
| 5 very complex | fable-high | fable-medium | opus-high | opus-medium | opus-low | opus-low |

Roles: reviewer-debugger (independent review of plans and code, root-causing failures),
plan author/fixer, code/test fixer, code/test author, fact researcher, test/script
executor.

Fallback model ids:

| short | id |
|---|---|
| fable | `claude-fable-5-1[1m]` |
| opus | `claude-opus-5[1m]` |
| sonnet | `claude-sonnet-5[1m]` |

## Reference

`plugins/session/README.md` in the claude-settings repo: cache facts, prices, the
team-compact protocol, scores.
