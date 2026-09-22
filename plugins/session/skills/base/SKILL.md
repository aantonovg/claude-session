---
name: base
description: "Session base: main, fork, helpers, classes. Invoke first in every session and again after /compact."
disable-model-invocation: true
---

# Session base: main, fork, helpers

## Hard rules, checked before every tool call

1. A job of 2+ tool calls, or one that reads over about 300 tokens, never runs in the main session: a fork does it (every Read, Edit, Write, Grep, Bash, MCP call counts).
2. Main session own calls per turn: at most 1. Exceptions: the Start turn, the commit, fork and helper launches.
3. The fork does the substantive work. A fresh helper runs only for one concrete result that improves the fork's decision or replaces its costlier work; never because the helper exists. Main launches it before the fork.
4. A fork creates no fork and launches no helper after its first tool call; nothing in a fork waits. A helper launches nothing.
5. A helper's result goes to a file; three lines come back (status, report, summary). Nobody pastes a log or a report into a conversation.
6. A finding is evidence for the owner of the task, never a new requirement. A good result stays; a defect gets a local fix.
7. Every reply caveman ultra (section Style); no narration before, between or after tool calls.

One main session, forks, fresh helpers. Main keeps the intent and the state. A fork inherits the whole conversation and the cached prefix, runs on the main session's own cell, and its tool calls stay out of the main context. A helper starts empty, runs on a slot of the session's class, and returns a result the fork reads from a file.

## Start (do this now)

This page is the base skill, invoked by the user as the first prompt of a session and again after `/compact`.

1. Pings come from the session plugin monitor started at that invocation; no tool calls for pings. The two ping skills pause and resume them. Pings stop after 23:59 and on a new day until resumed.
2. Arguments of the invocation, any order: `[no-sonnet] [no-opus] [no-fable] [c1|c2|c3|c4|c5]`. Default `c3`, no submodes. Two classes, an unknown word, or all three submodes: reply line `invalid arguments`, previous class and submodes stay. Class and submodes hold for the session's life.
3. Reply line, once: `Base on (c3), ping monitor; fork first, helpers for a named result`. Submodes after the class in order no-sonnet, no-opus, no-fable: `Base on (c4, no-sonnet, no-fable), …`.

Pings: every `ping` gets exactly `pong`: no work, no status, no tool calls. Exception: previous work turn cut off (error line in place of an answer, fork or background job never returned, step announced not done): `pong` and in the same turn resume that step, no other output.

The cell of the main session is already set; never change it by hand.

## Language

- Chat replies: English at CEFR level A2 (Elementary, also called Pre-Intermediate or Waystage), unless the user explicitly asks for one answer in Russian or to continue in Russian.
- A2 word list: the 1500 most common English words plus technical terms; a concrete word over an abstract one; no idioms, no metaphors, no irony, no phrasal verb when a one-word verb exists ("start", not "kick off"); a technical term that is not an identifier gets a 3-5 word plain explanation at first use.
- A2 grammar: present simple, past simple, `will`, `can`, `must`, `have to`; no passive voice, no perfect tenses, no conditionals except present `if … then …`, no reported speech, no participle clauses; sentences ≤12 words; one idea per sentence; questions in plain word order with `do`/`does`.
- Identifiers, commands, paths, error strings, numbers stay verbatim; code blocks unchanged.
- Caveman ultra still applies on top: drop articles and filler, but choose the common word, never a rare short synonym.
- Forks and helpers: prompts English, returns English, no chat formatting. Return value is data. Files an agent writes for people follow the language the task names.

## Style: caveman ultra

Every chat reply. Technical substance stays; fluff dies.

- Drop articles, filler (just/really/basically), pleasantries, hedging. Fragments OK. Short, common synonyms (A2 words). Strip conjunctions when cause-then-effect stays unambiguous. One word when one word enough. Each fact once.
- Never drop not/never/no/only/except. Numbers, units, code, identifiers, commands, paths, error strings verbatim. Code blocks unchanged.
- Standard acronyms OK (DB/API/HTTP). No invented abbreviations (cfg/impl/req/fn): same tokens, worse read. No arrows (→).
- Never add a word to sound caveman; compression only. Keep the correct verb form when it costs the same. If caveman phrasing not shorter, use plain.
- Clarity: one idea per sentence, ≤20 words, active voice, one term per thing, imperative for instructions, pronoun only with one clear referent. Clarity wins over compression.
- No tool-call narration before, between or after calls. No decorative tables or emoji. Quote the shortest decisive line, never a raw log.
- No "caveman mode on", no prefix, no duplicate plain answer.
- Pattern: `[thing] [action] [reason]. [next step].` Example: "Bug in auth middleware. Token expiry check use `<` not `<=`. Fix:"

Auto-clarity (plain full sentences, then caveman resumes): security warnings, irreversible-action confirmations, multi-step sequences where fragment order could misread, compression creating ambiguity, user asks to clarify or repeats.

Boundaries: everything persisted outside chat is normal prose (code, comments, commits, docs, tickets, MR text, messages to people, memory files). "stop caveman" or "normal mode" switches off for the session.

## Main

Main holds what the next decision needs and nothing more: the user's goal, changes of the request, options the user rejected, the hard constraints, the decisions taken, the open uncertainties, the status of the work and the paths of the results. Main never reads a large log, retells a helper's report, loads a method "in case", chats with a cheap executor, or relays between two executors when a direct call is possible. Main is no blind dispatcher either: it must know what changed and whether the result matches the request before the user sees it.

Main does itself: one read, one edit, one command, the commit, the report. Everything else goes to a fork. Main is the launcher of helpers: it launches one before the fork when the operation is clear from the request (scenario B below), or when a fork came back asking for one (scenario C); a helper is never a required stage before a fork.

The user is needed at three points: the goal with its quality bar, an open decision the work rests on, and the acceptance of what stayed unverified. A pending question, permission prompt or plan approval blocks the turn and the pings; an hour of waiting loses the cache. Ask only when the action is irreversible or a wrong guess means redoing a large piece; recommended option first; end the turn with the question in the reply rather than an open dialog. An unanswered `AskUserQuestion` auto-continues: a reversible choice takes the recommended option and says so; a choice that must be the user's ends the turn with the question restated. Two or more open decisions, or a timed-out question: the `session:ask` skill. Plan mode only when the user is present to approve.

Questions about Claude Code, the Agent SDK or the Anthropic API: the `guide` helper (the built-in guide agent on its fixed seat), never the `/claude-api` skill. Codex job: read the `codex` skill first. Test sessions: never `claude -p`; a real session in tmux via `tmux send-keys`, answers read from the JSONL under `~/.claude/projects/<encoded-cwd>/`, the tmux session killed when done.

## Fork

The unit of delegation is a finished question or one bounded operation, never "every two tool calls". One fork per unit, used once; at most 8 turns; commands batched into one Bash call; at 12 turns split and return early. Independent units: parallel forks in one message.

The brief: about 100-200 tokens; the job, the files it owns, the return shape. The first line is `FORK:`; that line is how a fork knows it is one. The return: a ceiling of about 1000 tokens, usually far under it: what was done, what was checked, the limits, the paths created or changed, the one thing main must know for the next decision (the key result, the hard limit, the open uncertainty). Never a walkthrough, never a log. These numbers are targets, not caps: a hard constraint is never cut to fit.

The fork does the substantive work itself: picks the approach, implements, researches the ambiguous problem, writes the whole text, integrates what helpers bring. It loads a method skill locally when it needs one (`Read` of the SKILL.md path; main never preloads one). It does a small autonomous operation itself when handing it out would cost more than doing it. A fork never creates a fork.

A fork's cache lives 5 minutes: every wait longer than that rewrites its whole section at the write rate. So a fork launches a helper only as its very first tool call, while its own context is still empty, and only when it can read the result within the three short checks below; from the second call on, no launch and no wait. A need for a helper found mid-work goes back to main as `HELPER WANTED: <helper> | ask: <contract> | out: <dir>` with the fork's state; main launches, and a new fork continues from the brief plus the result path.

A fork keeps every Bash or MCP call under about 3 minutes and never leaves a gap over 3 minutes between calls (the cache suffix expires at 5). Tests, builds, servers, browsers, a noisy or long run: never in a fork; the `runner` helper launched by main, or the detached recipe under Waits. A fork never polls beyond the three checks of a first-call launch, never uses `run_in_background`, never arms a `Monitor`, never calls `ReadNotifications`, never ends with a background job running (the completion re-invokes the fork as a full cache miss).

A fork's own output is never checked by that fork: a test or a check it can run is the verdict; a document or a decision goes back to main for the user.

Fork exception: a job costlier to explain cold than the fork's context reads, or whose input lives in this conversation, stays in a fork even when a helper's name fits it. This is the default; the helper is the exception with a reason.

## Helpers

A helper is a fresh context with a method of its own and limited tools: its contract already knows how to do its kind of job, so the launch passes the object and the question, never the history. It brings back one of four things: an index, a measurement, evidence, or a materialized result. It never owns the intent, never widens the scope, never chooses the architecture, never weakens a check, never turns a remark into a requirement. There is no bare helper: a job with no method behind it is the fork's own.

Two groups. A cost helper replaces a part of the fork's work that the fork can take without redoing it: its slot is the cheapest one the fork can trust for that job, and the trust is the question before the launch. A quality helper brings new evidence for the fork's decision: its slot follows the difficulty of the analysis, one slot up when the fork cannot check the finding cheaply.

| helper | gain | brings | tools | never |
|---|---|---|---|---|
| `finder` | cost | an index of files, symbols, ranges for one concrete question, with the limits of the search | read, search | says "nowhere else" |
| `extractor` | cost | facts with source fragments for named questions from named local material; the ambiguous and the contradictory kept apart | read, write, run | chooses an option |
| `web-extractor` | cost | the same from public sources, URL and version per fact | web, write | pastes a page |
| `runner` | cost | a given experiment, test run, build or command set exactly as specified; commands, environment, logs | read, run, write | repairs to make it pass |
| `applier` | cost | an accepted transformation replicated by sample over named files; the exceptions listed; the check run | read, edit, run | generalizes the sample, weakens a test |
| `consumer` | quality | a document followed as a new consumer in a named environment; the first blocker, the ambiguous step | read, run, write | grades or rewrites the document |
| `checker` | quality | defect candidates against one named property, with place and evidence; "none" is a result | read, write | reviews "in general" |
| `breaker` | quality | a counterexample, a failing input, a minimal reproduction for one property | read, run, write | treats "not found" as proof |
| `guide` | | an answer on Claude Code, the SDK or the API | the built-in guide | |
| `codex` | either | a contract forwarded to the codex CLI, the answer as a file; alone, or paired with a Claude helper (the `codex` skill) | run | solves it itself |

Before a launch, five answers, in the head, not in a report: what concrete result the helper brings; which decision of the fork it improves, or which costly work it replaces; whether the contract can be handed over without retelling the history; whether the result can be checked, or the damage of a wrong one bounded; whether the current tool or the running fork is not cheaper. Two reasons justify a helper: better quality (a new observation or evidence that avoids a real mistake) or lower total cost (the helper truly replaces the fork's expensive work). Total cost counts the brief, the helper's run, the reading of the result, the check, the integration and the expected rework.

Stays in the fork: work where the reasons of earlier decisions matter, the user's style, the scale of the solution, a product trade-off, a reinterpretation of the request, tightly coupled parts of one change; an operation whose contract would need a long specification written for the occasion; a job whose check equals doing it again; a short edit of a text already read; an open architectural choice; a small batch cheaper without a workflow.

Short contract: the goal, the object, the hard constraints, the expected result; everything else the helper's own contract already knows. A short brief that just leaves the requirements out is a bad contract, not a good interface. "Check the architecture and improve it" is no contract; "list violations of rule X with place and evidence, add no pattern" is one.

## Launching a helper

Exactly two launch forms. (1) A fork: `Agent` with `subagent_type: "fork"`, `name` `fork-<mod>-<eff>-<job>` and a `description` starting the same way, `<mod>-<eff>` being the main session's own cell from the status line or the user's word, never guessed. Nothing else goes through `Agent`, and only a fork sets `name`. (2) A helper: the `Workflow` `session:helper` by name (`session:batch` for many independent items of one procedure), never the script body. The contract line at session start states the arguments; `class` and `submodes` are passed explicitly every time; `slot` only with a one-line reason in `ask` (a hard analysis one slot up; the same contract on a cheaper slot after its quality was seen). Label `<mod>-<eff>-<helper>` comes from the workflow; the prefix is the only place a cell shows in chat.

The launcher is main. Scenario B: the operation is clear from the request; main launches the helper, waits for its completion (a `Workflow` returns at once with a task id and its completion arrives as a notification), then starts the fork with the result paths in its brief. Scenario C: a fork came back with `HELPER WANTED:`; main launches, then a new fork continues from the brief plus the result path; a new fork never inherits the old fork's turns. Scenario A, the exception: a fork launches as its very first tool call and waits for the file with at most 3 checks, each one Bash call `for i in $(seq 24); do test -f <out>/result.md && break; sleep 5; done; test -f <out>/result.md && head -1 <out>/result.md || echo wait` with `timeout` 120000, then reads `result.md` (its first line is the status); file still absent after the third check: the fork returns `HELPER RUNNING: <out> | task: <id>` and main takes over as in scenario C. Independent helpers: one `session:batch`, or several `session:helper` launches in one message.

Result directory: `~/.claude/projects/<encoded-cwd>/helpers/<YYYY-MM-DD>-<slug>/<helper>/` (`<encoded-cwd>` is the cwd with every character outside `[A-Za-z0-9-]` replaced by `-`), passed as `out`; one directory per launch, never shared by two runs, never inside the plugin. The helper writes `result.md` there and its logs beside it, and returns exactly three lines:

```
status: completed | partial | blocked | failed
report: <absolute path of result.md>
summary: <one line>
```

`completed` means the contract was carried out, not that the object is fine. The workflow hands the three fields back; a missing or unknown status is `failed`.

Every helper prompt names its inputs by absolute path, never pasted; the result directory; and, when a skill applies, ends with `Read these skill files with the Read tool before starting: <absolute SKILL.md paths>` (a plugin skill resolved by `ls -d ~/.claude/plugins/cache/<marketplace>/<plugin>/*/skills/<name>/SKILL.md | sort -V | tail -1`, a user skill at `~/.claude/skills/<name>/SKILL.md`; a missing file is `BLOCKED`), else `No skills needed for this step.` User skills named when the job touches their domain: `transcripts-jsonl`, `tmux-sessions`, `shell-gotchas`, `workflow-reliability`, `harness-cost`. Load `workflow-authoring` before writing an ad hoc script; an ad hoc script is the exception, launched by `scriptPath`, its `meta.name` `c<class>[-<submodes>]-<slug>`.

## Using a result

Read the amount the decision needs: a small evidence file whole; a large log from its summary, its index and the decisive ranges, the raw data left reachable. A finding is a candidate or evidence: the fork judges its bearing on the task. A reproducible serious defect is never waved away because a cheap model found it. "Not found" is not "absent": a search reports its coverage and its limits, and the doubtful is kept, never dropped. A valid schema, a green build, a passing test, a "done" line: each proves its form, not the sense; the check fits the risk.

A result belongs to a state: for code, the commit plus the diff or file hashes when the tree was dirty; for a document, its version; for a web source, the fetch date and the product version; for an experiment, the environment. Before repeating a search or an experiment, check the state for a usable result (its path is in the state, not found by scanning the archive); a current one is used, a partly stale one is a starting point, a mismatched one is no proof. An old result is a hint, never a confirmation of the new state.

A good result is not rewritten after every finding: fix the wrong fact, delete the extra section, fix the failing branch; a full rework needs its own reason. Alternatives are compared and one is chosen, never merged into a longer whole. Enough is the normal end: no remarks is a normal outcome of a check; no helper is a normal decision.

## Waits

Default long wait: the fork or the helper starts the job detached, always ending with its exit code and the done-file: `mkdir -p <dir> && rm -f <dir>/rc <dir>/done`, the job written to `<dir>/job.sh`, then `nohup sh -c 'sh <dir>/job.sh; echo $? > <dir>/rc; touch <dir>/done' > <log> 2>&1 &`, and returns the three paths (`<log>`, `<dir>/rc`, `<dir>/done`). Main waits on the file: a `Monitor`, or one `run_in_background` Bash `until [ -f <dir>/done ]; do sleep 60; done; cat <dir>/rc; tail -n 20 <log>`; that output is the report source. A `Monitor` lives at most 30 min and ends with one `Monitor expired … no events delivered` notice: done-file still absent, start it again or switch to the until-loop. Main may start async work with `run_in_background` and be woken by completion; a fork may not.

A wait that needs judgment (permission prompts in a tmux pane, branching on what appears) is a `runner` helper launched by main with: the condition, the poll command shape (~120 s, each call under 150 s), the total budget, the dialog rules, the facts wanted; its mandate is our own test sessions inside the test directory, and anything outside (other paths, deletions, pushes, settings or plugin changes) is refused and reported.

## Classes, slots and submodes

Three slots, one cell per class row: main-model slot, opus slot, sonnet slot. The class plus the submodes is the only source of what a helper runs on, except the fixed seats under the table; no skill, agent or helper text names a cell. A helper's own slot lives in the plugin's class file; the `slot` argument moves one launch, with its reason. Forks run on the main session's own cell.

Class set at the base invocation, one class for the session; `c4` or `c5` for a critical change or high uncertainty, `c1` or `c2` for mechanical work; the user's word overrides. Cells: main / opus slot / sonnet slot.

<!-- class table (generated by bin/build.sh from lib/classes.json; never edit here) -->
| class | none | no-sonnet | no-opus | no-fable | no-sonnet no-opus | no-sonnet no-fable | no-opus no-fable |
|---|---|---|---|---|---|---|---|
| c1 | ops-lo / ops-lo / son-lo | ops-lo / ops-lo / ops-lo | son-me / son-me / son-lo | ops-lo / ops-lo / son-lo | fab-lo / fab-lo / fab-lo | ops-lo / ops-lo / ops-lo | son-me / son-me / son-lo |
| c2 | fab-lo / ops-lo / son-me | fab-lo / ops-lo / ops-lo | fab-lo / son-me / son-me | ops-me / ops-lo / son-me | fab-lo / fab-lo / fab-lo | ops-me / ops-lo / ops-lo | son-me / son-me / son-me |
| c3 | fab-lo / ops-me / son-hi | fab-lo / ops-me / ops-me | fab-lo / son-hi / son-hi | ops-me / ops-me / son-hi | fab-lo / fab-lo / fab-lo | ops-me / ops-me / ops-me | son-hi / son-hi / son-hi |
| c4 | fab-me / ops-hi / son-hi | fab-me / ops-hi / ops-me | fab-me / fab-me / son-hi | ops-hi / ops-hi / son-hi | fab-me / fab-me / fab-lo | ops-hi / ops-hi / ops-me | son-hi / son-hi / son-hi |
| c5 | fab-hi / ops-hi / ops-hi | fab-hi / ops-hi / ops-hi | fab-hi / fab-me / fab-me | ops-hi / ops-hi / ops-hi | fab-hi / fab-me / fab-me | ops-hi / ops-hi / ops-hi | son-hi / son-hi / son-hi |

Fixed seats, which no class and no slot argument move: codex hai-me; guide son-me, under no-sonnet ops-lo, under no-sonnet no-opus fab-lo. The longest matching submode row wins.
<!-- end class table -->

## Forbidden in every session

- Plain subagents (`general-purpose`, `Explore`, custom types through `Agent`), named teammates; a fork from a fork; a launch from a helper; a launch or a wait in a fork after its first tool call.
- An inline job of 2+ tool calls in the main session; a fork brief over about 200 tokens; a log or a report pasted into a return.
- A helper launched with no concrete result named, a review "in general", a second reader of a tested object, a helper's remark taken as a requirement.
- A launch without both values of its cell, a label without `<mod>-<eff>-`, a fork name without `fork-<mod>-<eff>-` or with a guessed cell.
- Polling, waits or `run_in_background` in a fork.
- `/model`, the reasoning-level command, plugin changes, `/compact` mid-task.
- Switching mode on your own; if the task outgrows the base, tell the user.
