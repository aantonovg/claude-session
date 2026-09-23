# Fork-first review: session plugin 0.18.0 against the spec

Date: 2026-09-23. Scope: repo `claude-session` at `8c035cb` (clean tree), the installed plugin on the Mac and on the VM (`ssh claude-vm`), user-level skills and agents on both machines, the project workflows in `.claude/workflows/`. Measured against `reviews/claude_fork_first_architecture_full_dialogue.md` (spec sections 1, 4-6, 9-15, 17; its own decisions written "spec D05") and `docs/plans/2026-09-22-fork-first-decisions.md` (plugin decisions written "plan D1"-"plan D16"), plus the user's rule of 2026-09-23: every subagent launch except a fork goes through a workflow, because `Agent` cannot set effort.

Three review passes produced the raw findings: A (base, ask, codex and ping skills, hooks, `lib/classes.json`), B (nine helper agents, `session:helper`, `session:batch`, the project workflows, `lib/block.src.js`, four user agents), C (installs on the Mac and the VM, user skills). Duplicates are merged below; each item keeps its source ids. The six high items were checked again against the files before this document was written.

Not done: no test run (`tests/plugin/all.sh`, `bin/build.sh --check`), no live routing run, no read of harness `permissions.deny`.

## 1. Does the base launch helpers before forks, and is "every launch except a fork through a workflow" in place?

In the text, yes. Hard rule 3 (`plugins/session/skills/base/SKILL.md:13`) says main launches a helper before the fork, and "Launching a helper" (`SKILL.md:112`, `:162`) allows exactly two forms: a fork through `Agent`, a helper through the `Workflow` `session:helper` or `session:batch`. Plain subagents through `Agent` are in the Forbidden list.

In practice, the helper route almost never fires:

- The `session:helper` and `session:batch` argument contracts did not reach main at session start (R-2). Main sees the class and slot rules but not the arguments `helper`, `ask`, `in`, `out`, `codex`, `cwd`.
- Scenario B needs the operation to be "clear from the request", and the base gives no trigger examples, positive or negative (R-3). Scenario A, `session:batch` and `HELPER WANTED:` never ran live (plan D12).
- In this review session main launched four forks and no helper, the expected outcome under the current text.
- Nothing technical enforces the workflow-only rule (R-1): the nine `session:*` helper types and four user agents stay in the `Agent` registry, and a direct launch runs on the session's model and effort with no sign.
- Nobody has checked that `agent()` inside the workflow really applies the `effort` it gets (R-7). That effort control is the whole reason for the workflow wrapper.

## 2. Do agents, skills and workflows carry a real method?

Mostly yes. Ratings:

| object | rating | note |
|---|---|---|
| finder | good | named tools (grep, find, git grep, `git log -S`), ranking, doubtful section, coverage |
| extractor | good | source per claim, contradictions apart, coverage; no sampling rule for very large material |
| web-extractor | good | fetch cap 8, URL plus fragment plus version plus date per fact |
| runner | good | `commands.txt` with exit codes, logs, environment, stop at the first step it cannot run, never repairs |
| applier | good | exact sample, exceptions listed, one final check; no patch or changed-file list (R-20) |
| consumer | good | step record, first blocker; says nothing about isolation from the repo |
| checker | thin | scope rules clear, but no reading procedure (enumerate instances, then test each) and no search tool |
| breaker | good | hypotheses, attempts log, minimal repro run twice, budget |
| codex | good | full header contract, exact command, poll, failure codes |
| guide (built-in) | empty for this protocol | knows nothing of `result.md` or the three return lines (R-24) |
| `session:helper` | good | cell from the table, parsed triple, unknown status is `failed`; gaps R-11, R-16 |
| `session:batch` | good | one row per item, null return is a `failed` row, unique item dirs |
| `memory-gc` | good method, broken protocol | R-4, R-13, R-27 |
| `skill-author` | good method, old protocol | R-13 |
| `test-session` | good split drive/judge, wait defect, old protocol | R-5, R-13 |
| user agents session-driver, skill-author, skill-reviewer, transcript-analyst | good | pin model and effort in frontmatter (R-14) |
| base skill | method, but too much of it for main | R-10 |

## 3. Deviations from the spec and the decisions

34 items: 6 high, 11 medium, 15 low, 2 info.

### High

**R-1. The workflow-only rule has no technical guard.** Source A-7, B-1, B-2.
- Where: `plugins/session/skills/base/SKILL.md:112`, `:162` (text only); `plugins/session/.claude-plugin/plugin.json` has hooks for `UserPromptSubmit`, `PostToolUse` (Skill), `PreCompact`, `SessionStart` and no `PreToolUse`; `plugins/session/agents/*.md:1-5` carry no model or effort.
- Spec: 12.6 "Текст в агентном промпте не является достаточной технической границей"; 14.6; plan D1; the user's rule of 2026-09-23.
- Deviation: `Agent(subagent_type: "session:checker")` or a direct launch of a user agent is not blocked. It runs on the session's own model and effort with no sign. That is the exact failure plan D1 exists to prevent.
- Fix: a `PreToolUse` hook with matcher `Agent` that denies every `subagent_type` except `fork`, with the message "helpers launch through Workflow session:helper". First test whether the hook also sees `agent()` calls inside a workflow; if it does, let those through. Add a test in `tests/plugin`.

**R-2. The helper and batch contract lines did not reach main.** Source A-1.
- Where: `plugins/session/.claude-plugin/plugin.json:62`, `:71` (SessionStart hooks `workflow-usage.sh --file workflows/helper.js` and `batch.js`); base `SKILL.md:112` ("The contract line at session start states the arguments").
- Spec: 13.3 "Наличие skills/router/SKILL.md на диске не следует считать достаточным доказательством..."; 15.1 row "Загрузка маршрутизатора".
- Deviation: in this session (Mac, cache 0.18.0) the SessionStart context holds only the three project workflows (`memory-gc`, `skill-author`, `test-session`). The same hook command run by hand prints both plugin contracts with rc 0. So main does not know the helper arguments. This can explain why the user has never seen a helper launch.
- Fix: find why the plugin SessionStart outputs drop (four hook entries, background job, dedupe, size). Merge the four `workflow-usage.sh` calls into one hook command, or put the helper and batch argument lists into the base "Launching a helper" section. Add a smoke test that greps the session JSONL for a `session:helper` launch.

**R-3. The helper route is almost unreachable.** Source A-2.
- Where: base `SKILL.md:13` (hard rule 3), `:63`, `:77`, `:83` ("the helper is the exception with a reason"), `:114`.
- Spec: 11.1 "Это предпочтительный путь, когда необходимость помощника стала понятна во время решения"; 11.3; 15.3 positive routing examples; spec D26 "Проверять также решения не запускать помощника".
- Deviation: the spec's preferred path (a fork calls a helper mid-work) is the exception here (plan D8, a user decision; kept). What remains: scenario B depends on main seeing the need "clear from the request" with no trigger list, and scenario C costs a whole new fork. So the base defaults to "no helper" in nearly every case. No routing eval exists; `tests/plugin` are static checks.
- Fix: add to "Main" 4-6 concrete scenario B triggers from spec 8 and 15.3 (facts from a known file set; a document run as a new consumer; a given test run; a sample change over many files; a counterexample for one property; a large index before a code change) and 3 negative ones. Add positive and negative routing scenarios to `test-session`, so the helper launch rate is measured.

**R-4. `memory-gc` reads a blocked applier as success.** Source B-3, C-3.
- Where: `.claude/workflows/memory-gc.js:54` (prompt: "last line DONE or BLOCKED: <reason>"), `:57-58`, `:67-68` (`agentType: 'session:applier'`, `blocked()` tests only `/BLOCKED:/`); `plugins/session/agents/applier.md:15` ("Return exactly three lines and nothing else").
- Spec: 10.1, spec D21 "не выдавать незавершённую работу за подтверждённый успех"; plan D13 names the conflict and leaves it open.
- Deviation: two opposite return contracts in one call. If the applier follows its own body and returns `status: blocked`, the Check stage runs as if the trim happened. No `out` directory is passed.
- Fix: read the return with the plugin `handback()` (`blocked` or `failed` stops the stage) and pass an `out` directory; or use an agent whose body returns DONE/BLOCKED.

**R-5. `test-session` orders a wait the driver cannot do.** Source B-4.
- Where: `.claude/workflows/test-session.js:61` ("wait for ${OUT}/done in one Bash call with a ${BUDGET}-minute timeout", default 120 minutes); `~/.claude/agents/session-driver.md:14-15` (every synchronous Bash call `timeout` ≤ 120000; self-ping loop).
- Spec: base "Waits"; spec 13.4.
- Deviation: 120 minutes is over the Bash tool maximum, and the driver's own body says the opposite. The agent gets two wait rules.
- Fix: "wait by the self-ping loop of your definition until ${OUT}/done or ${BUDGET} minutes".

**R-6. `russian-plannotator` calls workflows that no longer exist.** Source C-1, C-2.
- Where: Mac `~/.claude/skills/russian-plannotator/SKILL.md:11` (named workflow `session:role`, `role: "translator"`); VM copy of the same file, line 10 (`session:translate-ru`). The two copies differ.
- Spec: plan D1; the 0.18.0 deletions (role workflows removed).
- Deviation: step 3 fails, or the model improvises a direct launch or an inline translation. This review's Russian copy was written by a fork for that reason.
- Fix: decide who translates. None of the nine helpers has a translation method. Either the fork translates (simplest), or a translate helper is added. Then sync the one file to the VM.

### Medium

**R-7. Effort control is not verified.** Source A-9.
- Where: base `SKILL.md:112`, `:144`; `plugins/session/workflows/helper.js:371` passes `effort` to `agent()`.
- Spec: 15.1 row "Выбор модели: Запущена фактическая ожидаемая модель и effort"; 14.3; plan D1, D12 (the smoke run reports labels only).
- Deviation: no test reads the helper transcript for the model and effort in use. If `agent()` ignores `effort`, the reason for the workflow-only rule fails with no sign.
- Fix: one smoke run per slot; read the subagent JSONL (model field; thinking budget or effort marker); record the result in the decisions file.

**R-8. The base contradicts itself on waits in a fork.** Source A-3.
- Where: base `SKILL.md:14` (hard rule 4 "nothing in a fork waits"), `:166` (Forbidden: "Polling, waits or run_in_background in a fork") against `:77`, `:79`, `:114` (scenario A: up to three 120-second polls).
- Spec: 11.1; plan D8, D16.
- Fix: hard rule 4 and the Forbidden line add "except the three file checks of a first-call launch".

**R-9. A fork may not run tests, yet its test is "the verdict".** Source A-4.
- Where: base `SKILL.md:79` ("Tests, builds ... never in a fork") against `:81` ("a test or a check it can run is the verdict").
- Spec: 1.1 ("Fable-fork: проверка в нужном объёме"); 4.2; plan D8 (targets long or noisy runs).
- Deviation: every code change needs an extra round trip (fork, main, runner, new fork), which spec 11.3 prices as costly.
- Fix: allow a short, quiet test or build under about 3 minutes in the fork; keep long, noisy, server and browser runs for `runner` or the detached recipe.

**R-10. The base is a large method, not a short policy.** Source A-5.
- Where: base `SKILL.md`, 23 252 bytes (about 5.5-6K tokens) in main every session; recipes at `:118` (helper prompt assembly, `ls | sort -V`), `:136-140` (nohup recipe, runner wait mandate), `:67` (tmux test method), class table `:146-158`.
- Spec: 14.2 "Базовая политика — не большая методология ... Не включать полные инструкции экспериментов"; 14.7; 17.2 (example policy about 350 tokens); spec D11.
- Fix: keep in the base the routing rules, the launch forms and the handback; move the detached-job recipe, the judgment-wait mandate and the prompt assembly into the runner agent, the `helper.js` prompt, or a side file a fork reads on need.

**R-11. The helper prompt paragraph is stale.** Source A-6, B-10.
- Where: base `SKILL.md:118` (prompt "ends with `Read these skill files...`", a missing file is `BLOCKED`); `plugins/session/workflows/helper.js:349-355`, `batch.js:354-360`.
- Spec: 14.5; plan D1 (the workflow builds the launch).
- Deviation: the workflow builds the prompt from `ask` and `in` and appends its own lines after `ask`, so the skill line is never last, and nothing adds "No skills needed" when the caller forgets it. The base never says the skill line goes inside `ask`. Uppercase `BLOCKED` is the retired 0.16 word; the status set is lowercase `blocked`.
- Fix: an optional `skills` argument (absolute paths) that the workflow renders as the last prompt line, default "No skills needed for this step."; drop the resolution recipe and `BLOCKED` from the base.

**R-12. The codex skill trusts a green check.** Source A-8.
- Where: `plugins/session/skills/codex/SKILL.md:66-70` ("nobody re-reads the diff, nobody re-runs the check"; "one more codex run" with no launcher).
- Spec: 12.4 "Зелёный тест не доказывает правильность самого ожидаемого результата"; base `SKILL.md:130`.
- Fix: "the fork reads the diff at the risk level of the change; the reported check counts as run, not as proof of sense"; "main launches the second codex run".

**R-13. The project workflows keep the old result protocol.** Source B-5, B-6.
- Where: `.claude/workflows/memory-gc.js`, `skill-author.js`, `test-session.js` (stage prompts "Never write files", DONE/BLOCKED lines, up to 12000 characters of review in the result); `~/.claude/agents/skill-reviewer.md:3,9,21` and `transcript-analyst.md:3,10,19` say "write the report file".
- Spec: 10.1 "короткий handback, подробный артефакт"; spec D20, D21; base hard rule 5.
- Deviation: no `result.md`, no status/report/summary; each call carries two opposite output contracts (agent body writes a file, workflow prompt forbids it).
- Fix: give each workflow an `out` directory; stages write their file; the workflow returns status, report path and a one-line summary.

**R-14. User agents pin model and effort.** Source B-7.
- Where: `~/.claude/agents/{session-driver,skill-author,skill-reviewer,transcript-analyst}.md:3-5`.
- Spec: base `SKILL.md:138` "no skill, agent or helper text names a cell"; plan D10.
- Deviation: a direct `Agent` launch (R-1) runs on the pin, not on the class; the pins also differ from the table (skill-reviewer is pinned fable-low, while c4 main slot is fab-me).
- Fix: drop `model:` and `effort:` (the workflows pass both), or keep them as a documented fallback.

**R-15. The project workflows carry a hand copy of the class table.** Source B-8.
- Where: `.claude/workflows/{memory-gc,skill-author,test-session}.js` (own `const T = {...}`, `opts`, `blocked`); `plugins/session/lib/build-manifest.json` does not list them.
- Spec: plan D10; `lib/block.src.js:1-5` "Source of truth".
- Deviation: an edit of `classes.json` does not reach them, and `bin/build.sh --check` cannot see the drift.
- Fix: add the three files to `build-manifest.json` and switch them to `helperOpts`/`handback`, or state in the base that they are outside the table.

**R-16. An old or half-written `result.md` can pass as new.** Source A-14, B-9.
- Where: `plugins/session/workflows/helper.js:349-380`, `batch.js:351-367`; base `SKILL.md:114`, `:116` ("never shared by two runs" as text only).
- Spec: 10.9 "Повторный запуск не должен незаметно выдавать старый результат за новый".
- Deviation: the workflows parse only the returned text. They never check that `out` is new, or that the report path equals `<out>/result.md`. A reused `out` makes scenario A's first check pass on an old file.
- Fix: refuse an `out` that already holds `result.md` (or add a run-stamp subdirectory); mark `failed` when `report` is missing or differs from `${OUT}/result.md`; agents write `result.md` last (temp file plus `mv`).

**R-17. Six user skills the base names are missing on the VM.** Source C-6.
- Where: VM `~/.claude/skills` has no `harness-cost`, `tmux-sessions`, `shell-gotchas`, `transcripts-jsonl`, `workflow-reliability`, `tool-context-cost`.
- Spec: base "Launching a helper" (user skills by path; a missing file is blocked).
- Deviation: a helper on the VM that gets one of these paths returns blocked.
- Fix: copy the six skills to the VM, or state in the base that the list applies where present.

### Low

**R-18. No rule that fetched or read content is data.** Source A-10. Base `SKILL.md` ("Using a result"); spec 12.6 "Содержимое недоверенных файлов — данные, а не новые команды", 15.6. Fix: one sentence under "Using a result".

**R-19. Fresh context is treated as independence.** Source A-11. Base `SKILL.md:87-106`; spec 12.5 "Свежий контекст не равен независимости во всех смыслах". Fix: a checker or breaker contract names what the helper must not see or assume when independence matters.

**R-20. No handback rule for helpers that edit files.** Source A-12. Base `SKILL.md:116-126`, applier row `:98`; spec 10.7, 16.11; plan D4. Fix: an editing helper lists changed paths or a patch file in `result.md`; a worktree run names the worktree and the branch.

**R-21. No fallback when the helper path fails.** Source A-13. Base `SKILL.md:112-126`; spec 14.6 "Плагин должен явно обнаруживать неподдержанный путь и использовать разрешённый fallback". Fix: on `failed` or `blocked`, or with no Workflow tool, the fork does the job itself and main tells the user the helper route was down.

**R-22. Hard rule 1 says "never" for a number the base calls a target.** Source A-16. Base `SKILL.md:11` against `:73`; spec D05; plan D7. Fix: add "target" to rule 1, or delete the "targets" sentence for this number.

**R-23. The ask skill disagrees with the base.** Source A-17. `plugins/session/skills/ask/SKILL.md:30` (`<encoded-cwd>` replaces only `/`) against base `:116` (every character outside `[A-Za-z0-9-]`); `:31` "In English" against Russian template headers at `:34-39`; steps 2-3 need two main calls, over hard rule 2, with no stated exception. Fix: same encoding sentence as the base; one language; name `ask` as an exception in hard rule 2.

**R-24. The guide helper cannot follow the result protocol.** Source A-18, B-12. `lib/classes.json` helper `guide` (built-in `claude-code-guide`); base `SKILL.md:101`; `helper.js:371`; spec 14.3. It has no Write tool and no knowledge of `result.md`; never smoke-tested (plan D12). Fix: one smoke launch; if it fails, make guide a fork-side job or wrap it in a plugin agent.

**R-25. Two timeout limits for the same call in agent bodies.** Source B-11. `plugins/session/agents/{applier,breaker,codex,consumer,extractor,finder,runner}.md:27` (`codex.md:39,59`), `session-driver.md:14-15`, `transcript-analyst.md:29`: "at most 120000" and then the poll "(timeout 200000)". Fix: "at most 120000, except the done-file poll at 200000", or shrink the poll to `seq 22`.

**R-26. finder has no Write tool; checker has no search.** Source B-13. `plugins/session/agents/finder.md:4`, `checker.md:4`; spec 8.1. finder writes `result.md` only through Bash redirects; checker coverage depends on the caller naming every file. Fix: add Write to finder; checker asks for a finder index when the object is large.

**R-27. `memory-gc` backup path is fixed.** Source B-14. `.claude/workflows/memory-gc.js:25` writes every run into `~/.claude/backups/2026-09-13-memory-trim/`; spec 10.4. Fix: date or slug from the trim path.

**R-28. The helper catalog is wider than the spec's start and the evidence.** Source A-15, B-16. Base `SKILL.md:85-101`; `lib/classes.json`; spec 14.1 "одного-двух действительно полезных помощников", 15.7; spec D15; plan D2 (user decision, kept). Six helpers (extractor, web-extractor, runner, applier, consumer, breaker) and `session:batch` never ran live; no negative routing eval (spec D26). Fix: mark them untested in the decisions file and give each one smoke run.

**R-29. `workflow-reliability` keeps role words and allows `general-purpose`.** Source C-4, C-5. Mac `~/.claude/skills/workflow-reliability/SKILL.md:54-55` ("every role's combo"; "Main session only orchestrates", stricter than the base) and `:34` ("`general-purpose` workflow agents are a last resort"); plan D1. Fix: slots instead of roles, the base main rule, "general-purpose never".

**R-30. The project workflows cannot run on the VM.** Source C-7. VM `~/.claude/agents` is empty and the VM repo is at `5394062`; `skill-author` and `test-session` need four user agents that exist only on the Mac. Fix: state Mac-only, or copy the agents and pull the repo.

**R-31. VM b2connect skills keep role vocabulary.** Source C-8. VM `~/.claude/skills/session-behavior-rules/SKILL.md:23`, `skill-routing/SKILL.md:3,20-25` ("review panel with model and effort pinned per role", direct subagent launch). Fix: helper and slot words; route reviews to `session:helper` with `checker`, or name the domain workflow.

**R-32. `isBlocked` matches any `BLOCKED:` substring.** Source B (method note). `plugins/session/lib/block.src.js`: a summary that quotes a blocked item marks the whole return blocked. Fix: match the status line only.

### Info

**R-33.** VM has no `~/.claude/statusline.sh`, so the plan D11 edit exists on the Mac only. Source C-9. No conflict.

**R-34.** The Mac and VM copies of `plannotator` and `plannotator-review` skills differ. Source C-10. Vendor skills, no fork-first rules inside.

## Checked and found conforming

Installed plugin: Mac and VM both `session@claude-session` 0.18.0, user scope, sha `8c035cb`, enabled; Mac cache equals the repo (`diff -rq` clean), VM cache files hash-equal to the repo (only `.in_use/*` and `.DS_Store` extra). Old cache dirs (43 on the Mac, 12 on the VM) are inactive. Base: two launch forms and the `Agent` ban; main, fork and helper duties (spec 4.1-4.3); five questions before a launch (spec 6.2); short contract (6.3); stop rule (1.4); reuse by state (10.6, 11.4); handback triple and status set (10.1); results outside the plugin (10.4); class table equals `classes.json`; `hooks/modes.sh` has no stale references. `lib/classes.json` matches plan D3 and D10. Mac `tmux-sessions` names `session:helper` with `runner` (plan D11).
