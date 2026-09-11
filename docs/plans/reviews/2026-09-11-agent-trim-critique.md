# Critique: agent trim plan (2026-09-11)

Reviewed: `docs/plans/2026-09-11-agent-trim.md` against `$CLAUDE_JOB_DIR/tmp/agent-context-report.en.md`.
Format: hypothesis — severity — plan section — check to run.

## High

1. **The per-launch `Skill` tool has no verified mechanism.** — high — line 30 ("those launches must add `Skill` to the agent's tools for that run (Workflow `tools` opt)"). The plan assumes a `Workflow` option can widen an agent's tool set at launch; nothing in the report or the plan shows it exists or that it also brings the skill listing the `Skill` tool needs. Report line 51 says the listing appears only with the `Skill` tool, so the cost is not zero either. Check: launch one stage agent through `Workflow` with the `tools` opt naming `Skill` plus a real skill name, and confirm from the agent's JSONL that the `Skill` schema and the skill listing are present and the skill loads. If the opt does not exist, the fix is the opposite one: keep `Skill` in the two stage agents that receive skill lists (researcher, executor) and pay about 0.5K plus 0.66K there.

2. **codex-proxy body cut 15.5K to 4K chars drops a rule the base relies on.** — high — lines 13, 35, 52. The keep-list names the header contract, the wrapper, the escalation preamble, the return format — it does not name `BLOCKED: <needed tool>`, the no-polling rule, or the return cap. The BLOCKED rule is the whole mitigation of risk 1 (line 51), and after the Read and Write removal codex-proxy is the agent most likely to need it. Check: diff the old and new body against the base's contract list; assert the new body still contains `BLOCKED`, the ban on polling the output file, and the return-size cap. Add these three to the keep-list on line 35.

3. **Artifact agents without Bash cannot copy or convert inputs.** — high — lines 24-25 ("Bash: the page is composed with Read and Write; no shell step in the role"). Read plus Write round-trips text only; an image, a PDF or any binary source named in the prompt cannot be copied into the artifact, and there is no `cp`. The plan's own escape ("the main session then prepares the HTML first") means the main session pays the work the agent was launched for. Check: run artifact-publisher on a task whose input list has one PNG and one Markdown file; confirm it returns `BLOCKED: Bash` rather than silently publishing a page with a broken image. If it does not return BLOCKED, keep Bash for artifact-publisher and cut it only for artifact-designer.

## Medium

4. **codex-proxy loses Write, so the output header has no writer.** — medium — line 13 ("Write: the prompt file is written by the main session, the output file by codex"). If the agent is the one that stamps the header (CODEX TARGET, CWD, PROMPT FILE, OUTPUT FILE) into the output file, it must do it through a Bash heredoc, which the plan never states, and heredoc quoting of a prompt path with spaces is a real failure mode. Check: confirm who writes the header — the wrapper script or the agent. If the agent, add the heredoc form to the body verbatim; if the wrapper, say so on line 35 so the trim does not delete the only mention.

5. **Removing Grep and Glob buys nothing and costs capability.** — medium — lines 14-16, 21, 23 ("Grep, Glob: cosmetic"). The report (line 37) measures 0 only "in auto mode"; in a session or project not in auto mode the harness may load them, so the saving is 0 in the measured case and unknown otherwise, while the loss (a researcher with no structured search) is certain. Check: measure one agent with and one without Grep and Glob in a non-auto-mode project; keep them wherever the delta is under 0.2K.

6. **The measurement is a remainder, and the acceptance band is tighter than its error.** — medium — report line 3 ("the remainder: usage minus everything else"), plan line 45 ("within 0.5K of its expected start"). Every per-tool figure in the cost model (plan line 5) inherits the error of the 4-chars-per-token conversion of the body, the harness blocks and the CLAUDE.md echo; summing four or five of them per agent plausibly exceeds 0.5K. Check: rerun `agentctx-run.sh` twice on an unchanged plugin and take the spread as the noise floor; set the acceptance band to max(0.5K, 2x spread). Also record the CLAUDE.md echo size on the measuring machine — it is user-specific (1.5K here) and will differ elsewhere.

7. **Reinstall is not a step.** — medium — line 45 ("after the reinstall") and line 57 (version bump). The plan mentions a reinstall in passing but never lists the command, and agent definitions are read from the installed plugin, not the repo, so a rerun without it silently re-measures 0.10.1 and "confirms" the old numbers. Check: make the reinstall an explicit numbered step before verification step 1, and assert the plugin version reported in the agent's context is 0.10.2 before trusting the log.

8. **waiter body trim assumes the launch prompt always carries the dialog rules.** — medium — lines 19, 36. "Always" is not verified; a waiter launched outside the standard template would lose the no-polling and BLOCKED rules, which is exactly the agent where polling costs the most. Check: grep the base launch template for the dialog rules, and keep in the waiter body any rule the template does not contain.

9. **README drift.** — medium — lines 13, 35, 57. Content moves out of codex-proxy into `README.md`, but no section is named, and the README likely still documents the old per-agent tool sets and the `skills:` lines being deleted. Check: grep README for each agent name, `ToolSearch`, `WebFetch`, `skills:`, and the removed permission-set examples; update the agent table and add the moved rationale in the same commit as the bump.

## Low

10. **web-researcher without Read.** — low — line 20. Accepted BLOCKED case, but the agent also cannot re-read a notes file it just wrote to append a second batch. Check: run a two-round research task and confirm the agent appends via Write without truncating.

11. **stage-researcher gains Write while the body still says heredoc.** — low — line 14. Check: the body's notes-file instruction names Write, not a Bash heredoc, after the change.

12. **Dropping `skills:` lines is behaviour-neutral only while the overrides stay off.** — low — lines 22-25, 31. If a user turns `simplify` or `security-review` back on, the preload silently never returns. Check: add one README sentence saying the rules are inlined on purpose and re-adding the skill means re-adding the line.

verdict: ready with fixes
high items: 3
