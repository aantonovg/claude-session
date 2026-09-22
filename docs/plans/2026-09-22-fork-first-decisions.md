# Fork-first rebuild: contested decisions

Every decision below was taken without the user during the 2026-09-22 rebuild (session plugin
0.18.0). Each states the options, the default taken and how to reverse it. Nothing here is
irreversible: no commit, no push, no reinstall was made; the working tree holds every change.

## D1. Helpers launch through `Workflow`, not through `Agent`

The `Agent` tool has a `model` parameter but no `effort` parameter, so a helper launched by
`Agent` could take the model of its class cell but never the effort. Default: two launch forms
stay, a fork through `Agent` and a helper through the named workflow `session:helper` (or
`session:batch`); the workflow passes model, effort and the label from the class table. The
launcher is main (annotation of 2026-09-23: a fork launches nothing after its first tool call, see
D8). Reverse: allow `Agent` with `subagent_type: "session:<helper>"` in the base's "Launching a
helper" section and accept that such a launch runs on the session's effort.


## D2. The helper catalog: nine helpers with a method each, no bare helper

Section 14.1 of the document asks for one or two helpers at first; section 8 lists thirteen
operation kinds. Default: nine agent files (`finder`, `extractor`, `web-extractor`, `runner`,
`applier`, `consumer`, `checker`, `breaker`, `codex`) plus the built-in `guide` seat; each file
carries its method, the base lists them in one table, and the routing rules make every launch earn
its place. The bare helper `hand` of the first draft was dropped on the user's annotation: a helper
without a method needs the history passed in, which is the fork's job. Reverse: delete the agent
files that see no use and their rows in `lib/classes.json`; `tests/plugin/agents.sh` follows the map.


## D3. Two groups of helpers and the slot of each

On the user's annotation the helpers split by gain (`gain` in `lib/classes.json`, a column in the
base table). Cost helpers replace a part of the fork's work that the fork can take without redoing
it: `finder`, `extractor`, `web-extractor`, `runner`, `applier`; their slot is the cheapest one the
fork can trust for the job, default sonnet. Quality helpers bring new evidence for the fork's
decision: `consumer` (default sonnet: a blocker in a document is cheap to re-check), `checker` and
`breaker` (default opus: the analysis is the hard part and a missed finding is not cheap to
check). The `slot` argument moves one launch with a reason. Reverse: edit `helpers.<name>.slot` and
`gain` in `lib/classes.json`.


## D4. Result directory root

Options: `.agent-results/` inside the project (the document's example; pollutes every repository
and needs a gitignore), or the harness's own project directory. Default:
`~/.claude/projects/<encoded-cwd>/helpers/<YYYY-MM-DD>-<slug>/<helper>/`, the same encoding the
old task files used. Open point of section 16.8: a worktree encodes to a different directory, so
results of a worktree are not found from the main checkout without the path in the state.
Reverse: one sentence in the base ("Result directory").

## D5. The result file is named `result.md`

The harness once refused a subagent Write of `report.md` under a directory `out` ("Subagents
should return f..."; memory `reference-harness-subagent-limits`) while `facts.md` wrote fine.
`result.md` is the document's name and was not seen refused, but was not tested here either.
Reverse: rename in the ten agent files, the two workflows, the base and `tests/plugin/agents.sh`
(one grep).

## D6. The verification page and the task layout are gone

`lib/verification.md` (oracle ladder, artifact chain, uplift rules) and `lib/task-layout.md` (task
directory, ledger, resume) were the spine of the retired process. The one rule that fits fork-first
(a test beats a review; a green check proves its form, not the sense) stands in the base under
"Using a result". No stage, no ledger row, no resume line, no `tasks/current` pointer. Reverse:
restore both pages from `git show HEAD:plugins/session/lib/verification.md` and re-add a hook; the
document argues against it (section 2.3, 12.8).

## D7. Fork limits are targets

Fork brief about 100-200 tokens; return ceiling about 1000 tokens; "2+ tool calls or over about 300
tokens read" moves a job out of main. The document marks all four numbers as unverified hypotheses
(D05, D06, section 16.2-16.3). The base says "targets, not caps: a hard constraint is never cut to
fit". Reverse: numbers in "Hard rules" and "Fork".

## D8. Nothing runs long inside a fork, and a fork launches nothing after its first call

The user's annotation restored the old rule and extended it: a fork's cache section lives 5
minutes, and every wait longer than that rewrites the whole section at the write rate, so tests,
builds, servers, browsers and any long or noisy run stay out of a fork (the `runner` helper, or
the detached recipe), every fork call stays under about 3 minutes, and a fork never launches a
helper or a workflow after its first tool call and never waits on one. The one allowance the user
offered: a launch as the very first tool call of a fork, while its context is still empty, with at
most three 120-second file checks; beyond that the fork returns `HELPER RUNNING:` and main takes
over. The default path is main launching the helper before the fork (scenario B) or after a fork
returned `HELPER WANTED:` (scenario C). Reverse: the "Fork" and "Launching a helper" sections.


## D9. The codex skill survives, with the pair modes restored

The user's annotation: replacing a helper with codex, or pairing it, was a good feature to keep.
Default: `skills/codex/SKILL.md` names the modes: heavy axis `sol` and `astra` replace `checker`
and `breaker` with `helper: codex`; `+sol` and `+astra` pair them (the `codex` argument of
`session:helper` runs the codex helper on the same contract in parallel, second result directory
`out/codex`, two triples back, the fork reads both); executor axis `luna` and `terra` send the
cost-helper jobs to codex. The shim text lives in `agents/codex.md`, which accepts the contract
either as a prompt file or as a `CODEX ASK:` block it writes to `<out>/prompt.md` verbatim. The
launcher is main, before the fork. The wrapper `bin/codex-exec-logged.sh` is unchanged. Reverse:
delete `skills/codex`, `agents/codex.md`, the `codex` rows of `classes.json`, the `codex` branch of
`workflows/helper.js`, and `tests/codex`.


## D10. The class table gained a `haiku` model entry

The codex seat needs a cell; the old design pinned `haiku medium` at the call site as the one
exception to the table. Default: `hai: haiku` in `models` and the fixed seat `codex: hai-me`, so
the table stays the only source of a cell. Reverse: remove both and pin at the call site in
`workflows/helper.js`.

## D11. User-level files: two edits applied on the user's approval

The 0.16 switch had patched user skills and `~/.claude/statusline.sh` to the old names. Applied on
2026-09-23 after the user marked the suggestion "looks good": in
`~/.claude/skills/tmux-sessions/SKILL.md` the judgment-wait sentence now launches `session:helper`
with `helper: runner`; in `~/.claude/statusline.sh` the modes segment reads `.base` and `.codex`
only. `~/.claude/skills/harness-cost` and `transcripts-jsonl` were not touched. Reverse: the two
one-line edits.


## D12. Two live smoke runs on a sonnet main session

Run 1 (2026-09-23, before the annotations) let a fork launch `session:helper` itself: the nesting
worked, `session:finder` wrote `result.md` and returned the three lines, but the fork could not
drain notifications, armed a `Monitor`, ended its turn, and main had to resume it. That path is now
the exception (D8).

Run 2 (2026-09-23, after the annotations), throwaway project `~/projects/ff-smoke-2` with two
Python files, `--plugin-dir` on the working copy, `/session:base c3`, then three prompts:

- a fix task naming a helper index first: main launched `session:helper` with `finder`, waited on
  the workflow notification, then started `fork-son-hi-fixdb` with the result path in its brief;
  the fork made Read, Bash and Edit calls only, no launch, and returned the change plus the note
  that the check fails the same way on the unmodified code;
- `/session:codex +sol-luna`, then a codex-alone launch (`helper: codex`, `luna-high`, a
  `CODEX ASK:` block): the codex helper wrote `prompt.md`, ran, and returned three lines with the
  answer as the summary (70 s); side effect: the codex model also wrote an `output.txt` into the
  repository, because the ask said "the output file" without a path; the ask must name the path;
- a paired launch (`helper: checker`, `codex: sol-medium`): both triples came back, the Claude
  checker on `ops-me`, the codex helper on `hai-me`, two result directories (`checker-pair/` and
  `checker-pair/codex/`), both `none found`.

Statusline read `base-c3:codex+sol-luna+ping`. Cost of run 2: about $0.63 on the sonnet session
plus the helpers and the codex quota. Not tested: scenario A (a launch as the fork's first call),
`session:batch`, `HELPER WANTED:` from a fork.


## D13. The project workflow `memory-gc.js` now uses `session:applier`

Its trim and fix stages used `session:tools-edit`, which is gone. `applier` has the same tools
(Read, Edit, Write, Bash). Its contract text expects the three handback lines, while `memory-gc.js`
reads `DONE` or `BLOCKED:` from the return; the two scripts of `.claude/workflows/` that use
built-in and user agent types (`skill-author.js`, `test-session.js`) are untouched. Reverse: point
the two `agentType` values at another agent, or make memory-gc read `handback()`.

## D14. `docs/tool-plugin/` was reworded, not rebuilt

"carrier" and "stage" became "helper" and "launcher"; the template agent's return line mentions
the three handback lines. The pattern (one MCP server per plugin, agents by tool group, one usage
block per workflow, a contract printer) stands. Reverse: `git checkout docs/tool-plugin`.

## D15. The two review documents stay untracked

`reviews/claude_fork_first_architecture_full_dialogue.md` and
`reviews/fable_fork_vs_complex_workflow.md` are referenced by both READMEs and were not added to
git: the user placed them. `git add reviews/` before the release commit, or move them under
`docs/` and fix the two README references.

## D16. A helper's completion: main waits on the notification, a fork on the file

Main is the launcher and gets the workflow completion as a task notification (seen in run 2). The
one exception, a launch as a fork's first call, waits on `<out>/result.md` with three 120-second
Bash checks, because a fork cannot drain notifications and a `Monitor` inside a fork expires in 5
minutes; `result.md` starts with its status line so the file alone tells partial from completed.
Reverse: the last sentences of "Launching a helper".
