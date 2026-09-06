# Session base: tools, cache, waits, models, roles

## Hard rules, checked before every tool call

1. The main session never executes a job of 3 or more tool calls itself: it hands it to a fork (count every Read, Edit, Write, Grep, Bash and MCP call).
2. The main session's own tool calls per turn: at most 2, except the commit and the launch of agents.
3. Writing a file over 40 lines is a fork.
4. Running tests, builds, servers or browsers is a fork.
5. A job that needs 3K+ tokens of input is a fork.
6. When in doubt, fork.

One main session plus fork subagents. A fork inherits the whole conversation and the
cached prefix, so spawning one is nearly free; its tool calls stay out of the main
context, which is what keeps the main session small and warm. Forks run on the main
session's model and effort, there is no mixing.

## Start (every session, injected by the plugin's SessionStart hook)

On the first turn of a session (and after `/compact`): first tool call `CronCreate` with
`cron: "*/30 * * * *"` (this exact expression), `prompt: "ping"`, `recurring: true`,
unless a `ping` cron already exists in this session; reply line `Base on, ping cron <id>; forks for every 3+ call job`
once. Reply to every `ping` with one word. Exception: when the context shows that the
previous work turn was cut off by the subscription limit or an API error (an error line
where an answer should be, a fork or background job launched and never returned, a step
announced and not done), the ping is the restart signal: answer `pong` and in the same
turn resume that step from where it stopped (relaunch the fork, re-arm the wait), no
other output. Model and effort are already chosen; do not change them for the rest of
the session. `session:pipeline`, `session:review` and `session:codex` load on top of
this base; nothing here is a skill to invoke.

## When to fork

Hand a job to a fork when it needs 3 or more tool calls in total (every Read, Edit,
Write, Grep and Bash counts, reads included), or when it would bring 3K or more tokens
of input into the context (reading several files, log or search sweeps, running
tests, tmux-driven checks, verification passes). "Small scope" is not a reason to stay
inline: count the calls. Writing a function plus its tests plus running them is
always a fork. Do only tiny things yourself: one read, one edit, one command, the
commit, the report.

- Independent jobs go to parallel forks in one message (one `Agent` call each).
- The main session does the writing that matters for continuity: plan files, final
  edits when they are small, commits, the report to the user. A fork may edit files
  when the edit is the job; say which files it owns so parallel forks do not collide.
- A fork is used once. It cannot be reused after it returns; send a new one.
- A fork is short: aim for 8 turns or fewer, batch independent commands into one Bash
  call (`;`, `&&`, one python3 script instead of many greps); at 12 turns it splits the
  job and returns early with what it has.
- Read once, write once: all inputs in one command (`cat a b c` or one script), think
  once, write at once; never a gap over 3 minutes between two tool calls (the suffix
  expires at 5; measured: a review fork paused > 5 min before its Write, 53K rewritten).

## Fork prompt template

The first line sets the role, the last line the return format:

```
You are the <role>: <one-line goal>.            # reviewer-debugger, code/test author, ...
<the task, the files, the acceptance criteria>
Return only <facts | a diff summary | PASS/FAIL with the decisive lines>, at most <N> words.
Do not paste file contents or raw logs. On a permission denial stop and return BLOCKED: <action>.
Load these skills with the Skill tool before starting: <names>.   # or: No skills needed for this step.
```

Language of agents: every fork, waiter, cold agent and codex run works and answers in
plain English only: prompts in English, return values in English, no Russian recap, no
`---` separator, no chat formatting. The two-part chat format (English body, Russian
recap) belongs to the main session's replies to the user and nowhere else. Files an
agent writes for people (threads, notes, commits, reports named as Russian by the
task) follow the language the task names.

Every agent launch is named by model and effort, as a dash-separated PREFIX
`<mod>-<eff>-`: the `label` of every Workflow `agent()` and the `name` of a fork are
`<mod>-<eff>-<job>` (`fab-lo-cache-audit`, `ops-me-critic`, `son-lo-research`,
`sol-hi-decision-review`); the free-text `description` of every `Agent` call (forks,
waiters, plain subagents) starts with the same prefix, then a space and the job
(`fab-lo cache audit`). Codes: model `fab ops son hai sol ter lun atr`, effort
`lo me hi xh mx`. Only a FORK launch sets `name` (the field the agents panel shows
instead of the bare type); never set `name` on a waiter or any plain subagent: a named
plain subagent is spawned as a mailbox teammate (measured 2026-09-06), a named fork
stays a fork. A fork carries the main session's model and effort, a waiter is `son-lo`,
a codex-proxy label names the codex target (the haiku shim is implied). This replaces
the older `<mod>:<eff>` form and the earlier suffix form.

Review and fix are different forks: the fork that wrote code never reviews it, and the
fork that reviewed never applies its own findings. Stages and roles come from the plugin
README (plan → review → red tests → implementation → review → fast tests → fix, 1-3
cycles each); pick the 0-3 skills per stage from the skill-routing map.

In plan mode forks must avoid Bash commands with `$var`, `$(…)` or loops (they trigger a
permission prompt there); outside plan mode any Bash is fine.

A fork's own context lives in the 5-minute cache and the clock runs from the start of
each request, so a fork never waits synchronously for long: every Bash call or MCP call
inside a fork stays under about 3 minutes. A cron created by a fork fires in the main
session, not in the fork, so it cannot keep a fork warm. A fork never uses
`run_in_background` and never ends its turn with a background job running: the
completion re-invokes the fork, and that re-invocation is a full cache miss (measured:
409K rewritten, ≈ $5 on fable). What expires after 5 idle minutes is only the fork's own
suffix; the parent prefix it inherited stays in the parent's 1-hour cache.

## Heavy agent on request

Only on the user's explicit word ("high-ревью", "через sol", "сгенерируй через astra"),
never on the session's own initiative, one cold lean agent does a point review or a
point generation of one artifact: `session:stage-reviewer` for review,
`session:stage-author` for generation, `codex-proxy` for sol / astra / terra (model and
effort as the user named them, else the reviewer-debugger or author cell of the class
row). Launched as a single-agent `Workflow` (`label: "ops-hi-review"`, `"sol-hi-generate"`), inputs passed by path, output written to a file, the main session receives
the path and the last line. Budget stated in the prompt: at most 5 tool calls at medium,
3 at high or xhigh, all inputs read in one call, one write; when the budget runs out the
agent returns `partial` with what it has. In pipeline mode the launch gets a ledger row
like any cold stage.
