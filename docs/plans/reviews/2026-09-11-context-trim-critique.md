# Critique: 2026-09-11-context-trim

Hypotheses only, no verification done. Each: severity, plan section, check for a follow-up agent.

## High

1. **Artifact agents are dead on arrival under the deny.** (2c, 2e, 1) The plan itself states a
   user-level deny removes the tool from every subagent, yet 2c acceptance demands "each agent
   launched once through Workflow ... returns its format". artifact-publisher and
   artifact-designer cannot satisfy that while Artifact/DesignSync sit in `permissions.deny`.
   Check: launch artifact-publisher with the deny active, capture the exact failure (does it
   return `BLOCKED:` or hard-fail the workflow), and rewrite the 2c acceptance to exclude the two
   artifact agents or to require a lift-then-restore run.

2. **`name-only` fallback may re-add tokens to the main listing.** (2c step 1, Risks) The plan
   asserts `name-only` keeps skills "still hidden from the main listing"; that is an assumption,
   not a measurement. If `name-only` publishes name+description to the model, six skills times
   four to six entries eat part of the -15K.
   Check: set one skill (`code-review`) to `name-only`, start a sonnet session in
   `~/projects/empty-context-test`, diff `/context` skill lines against the `off` baseline.

3. **Start-context target rests on an unmeasured 52K.** (1) 56.9K is measured; 52K is "expected"
   after today's user-level changes, and the whole table subtracts from it. If today's changes
   landed 54-55K, the 35-39K band in section 3 fails and the plan looks broken for the wrong
   reason.
   Check: measure the current start context before any edit; re-derive the table from the
   measured number; state a rollback rule if the post-change measurement exceeds 39K.

## Medium

4. **+0.5K for six descriptions is likely low.** (1, 2c, Risks) desc-inventory says each new
   description costs 60-100 tok "as the harness counts" — six is 360-600, top of range already
   over 0.5K, and the listing also carries each agent's name, model and tool list, which the
   inventory notes is unchanged for existing agents but is *new* for six new ones.
   Check: count the six drafted descriptions with the chars/4 rule, multiply by 1.4, add the
   tool-list lines; compare to 0.5K and correct the table.

5. **Mixed token units in the arithmetic.** (1 vs desc-inventory line 35) The trim saving is
   about 0.44K by chars/4 and about 0.65K as the harness counts; the plan writes -0.6K next to a
   +0.5K that is stated in harness units. Small, but the same table also mixes a measured -14.8K
   with an estimated -0.6K/+0.5K.
   Check: restate every row of the section 1 table in harness tokens with the source (measured or
   chars/4 x1.4) named per row.

6. **Order 2f before 2e, and no explicit marketplace refresh.** (2f "Order of work", Risks) The
   version bump and commit happen before the deny lands, so the README log line and the commit
   message claim "about 37K" before any post-change measurement exists. Separately, the plan says
   the directory marketplace "still copies to the cache" but never names the command sequence
   (`claude plugin marketplace update` vs reinstall) that guarantees the cache picks up 0.10.0.
   Check: after the bump, run the install as written and confirm the cached
   `plugins/session/.claude-plugin/plugin.json` reads 0.10.0 and the new agents appear in a fresh
   session listing; move the numbers in the commit message to after step 3 verification.

7. **Agent bodies are promised, not specified.** (2c) "same skeleton", "the output-style block the
   other agents carry", "returns a diff summary", "the two reviewers return findings with
   file:line" — no exact return format, no word cap for five of six agents (only web-researcher
   gets 3-5K), no artifact-agent return contract beyond "the URL".
   Check: require each agent body to carry a verbatim last-line return spec and a word cap before
   the review gate; list which existing agent is the skeleton source.

8. **Tool-set acceptance contradicts the Grep/Glob note.** (2c acceptance vs desc-inventory note)
   Acceptance wants "exactly the listed tools (plus Grep/Glob that ride with Read)" while
   security-reviewer lists Grep without Glob and simplifier lists neither. The check as written
   cannot fail or pass cleanly.
   Check: define the expected tool set per agent explicitly, including the ride-along set, then
   compare to the agent JSONL.

9. **Risk to running sessions from the settings.json edit.** (2e) Editing `permissions.deny` while
   the user has live sessions: unclear whether a running session re-reads the file and loses
   Artifact mid-task, and whether the toggle needs a restart. The plan says "remove the entries,
   start a session" but never says the deny takes effect only on a new session.
   Check: with a session open, add the deny and probe the tool in that same session; document the
   observed behaviour in the README toggle text.

## Low

10. **README drift is covered by a "consistency read" only.** (2a, 2e, 2f) Three hand edits land
    in `plugins/session/README.md`: agent table rows, the toggle doc, the 0.10.0 log line. No
    acceptance names the file.
    Check: add an explicit acceptance that the README names all six new agents, the toggle
    procedure and the 0.10.0 line, and that no README text quotes a trimmed description.

11. **Acceptance threshold is loose.** (2a) The table targets 40-90 tok per description but
    acceptance only asserts "under 150 tokens", which every current description except
    codex-proxy already passes. The check would pass without the trim.
    Check: assert the per-file targets from the 2a table, not a single 150 cap.

12. **Inventory suggestions dropped without a note.** (2a, desc-inventory (b)) Removing pool-proxy
    while pool mode is unstable and deleting the duplicate `spec-critic` (50 tok) are proposed in
    the inventory and silently absent from the plan; also unclear whether `agents-heavy` as a
    separate plugin was considered and rejected.
    Check: record the decision and the reason for keeping both agents in the listing.

13. **Backup path depends on `$CLAUDE_JOB_DIR`.** (2e) The settings backup goes to a job-scoped
    temp dir that disappears with the job, so the rollback for a user-level config change is not
    durable.
    Check: copy the backup to a persistent location outside the job dir and name that path in the
    plan.

verdict: ready with fixes | high items: 3
