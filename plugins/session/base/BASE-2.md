# Session base, part 2 of 3

## Downscale and upscale of intelligence

What to launch when:

| need | launch | model, effort |
|---|---|---|
| context-aware work, the chat matters, strongest judgment of the set; cheap start, costlier execution | fork | main session model and effort |
| downscale: bulk tool-heavy work (repository research, tests and the verification layer, code review), many tool calls per agent expected | `Workflow`, lean agent | `sonnet-low`; `opus-low` when the main session is fable or a review needs a fresh context; under `session:codex` `luna-high` replaces sonnet-low, `terra-high` replaces opus-low |
| upscale: critique of one fact set or generation of a key document (section above) | `Workflow`, `session:stage-reviewer` / `session:stage-author` | `opus-medium`, `fable-medium` (5 tool calls); `opus-high`, `fable-high` (3 tool calls); sol / astra under `session:codex` |
| long wait with judgment | waiter, one-agent `Workflow` | sonnet-low |

Every downscale and upscale agent starts through `Workflow`: independent agents are
batched into ONE workflow (`parallel`); a relay between steps (research → critique →
check) is wired as `pipeline()` stages of the same workflow; every `agent()` carries
explicit model and effort and the `<mod>-<eff>-` label.

The rules below came verbatim from the August workflow mode (`session:workflow`, folded
into this base 2026-09-06) and apply to every `Workflow` launched from any session.

### One class and one pairing per workflow

Assess the task once on the 5-class scale (1 very simple … 5 very complex; criteria in
the README) and pick the pairing once. Stamp both into `meta.name` as
`c<class>-<pairing>-<slug>` (`c3-fable-opus-fix-retry-logic`); a running workflow must
always show what it was sized for. Every role takes its combo from that single row of
the pairing's map: the role picks the column, the class picks the row. Never mix rows,
never pick a combo ad hoc for one agent, never mix pairings inside a workflow. Switch
the pairing only on the user's word or a real availability limit, and say so.

Six roles, one column each: reviewer-debugger (strongest slot), plan author/fixer,
code/test fixer, code/test author, fact researcher, test/script executor (cheapest).

### Every `agent()` call

- `model` and `effort` set explicitly in opts, never inherited; `agentType` launches
  (`claude-code-guide`) too. Full ids come from the session map (`claude-opus-5[1m]`).
- Label starts with the `<mod>-<eff>-` prefix: `fab-hi-review-plan`, `ops-lo-fast-tests`
  (`fab`, `ops`, `son`, `hai`; `lo`, `me`, `hi`, `xh`, `mx`). The UI shows the model
  but not the effort; the prefix is the only place the effort is visible.
- The prompt ends with two lines chosen by the main session from the skill-routing map
  (`~/.claude/memory-user/skill-routing.md`, 0-3 skills by role and step): "Load these
  skills with the Skill tool before starting, in this order: <names>. Follow each loaded
  skill's instructions in place of your default approach." or "No skills needed for this
  step."; then "If you hit work outside this list that a clearly matching skill in your
  available-skills list covers, load it first, but never load claude-api." Workflow
  agents never open the skill list on their own (measured 2026-08-27).
- Author, fixer and executor prompts carry: "On a permission denial stop at once and
  return BLOCKED: <denied action>."
- Return format named in the last line: facts, a diff summary, or PASS/FAIL with the
  decisive lines, with a word limit; no file contents, no raw logs.

Check a saved script before every launch: explicit model+effort, `<mod>-<eff>-` label prefixes, the
two skill lines, class and pairing in `meta.name`; fix first, then launch. After editing
a saved script launch it by `scriptPath`, not `name` (name resolution can serve a stale
copy). Load `workflow-authoring` in the main session before writing a script.

### Stages and quality loops (workflow-only work)

Every stage that authors an artifact (plan, code, tests, scenarios, design document) is
paired with an independent review by the reviewer-debugger, a separate agent. Wire it as
author → reviewer-debugger (→ fast tests by the test/script executor when the artifact
is code) → fixer, 1-3 cycles: exit as soon as the verdict is clean and tests are green;
after the third cycle stop and report what is unresolved. A full task chains:

1. **Plan**: plan author/fixer writes, reviewer-debugger reviews, plan author/fixer
   applies; 1-3 cycles. Worth it for large tasks even when well understood.
2. **Red tests** (when acceptance criteria exist): code/test author writes tests first;
   the review checks the test code and that every acceptance criterion maps to a test;
   code/test fixer applies; 1-3 cycles.
3. **Implementation**: code/test author writes, reviewer-debugger reviews, test/script
   executor runs the fast tests, code/test fixer applies; 1-3 cycles.
4. **Technical stages** (preparation, merge, commit, conflict resolution): test/script
   executor, no review loop.

Parallelize when it pays: before launching, decide whether a stage splits into 3-5
agents of the same role over independent files, directions or work items. Overlapping
code areas get `isolation: 'worktree'`; disjoint files share the tree. Parallel agents
still take the same map row. Prefer `pipeline()` over barriers.

Blocks: the script checks every stage result (`null` or a `BLOCKED` prefix counts as
blocked) and ends the workflow at once with a report; review and fix never run against
unchanged files. Relaunch only after the cause is addressed. Resume with
`resumeFromRunId` after a pause or a script edit; read `journal.jsonl` in the transcript
dir before diagnosing an empty result.

Land stages (commit, push, MR update) are self-contained: repo path, branch, expected
changed files, a one-to-two-line summary of the change interpolated from earlier stage
results. The agent runs `git status` and `git diff --stat` first and returns
`BLOCKED: unexpected working tree` on a mismatch. Push only when the task grants it.
