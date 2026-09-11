# Base classes: closure note (2026-09-12)

Session plugin 0.11.0. Plan `2026-09-12-base-classes.md`, critique (5 high, all fixed), code review PASS (`reviews/2026-09-12-base-classes-code-review.md`), medium items fixed afterwards (stage-reviewer and stage-critic at effort low, example labels, README wording).

## Rules delivered

- Any job of 2 or more tool calls goes to a fork or a workflow; the main session makes at most 1 own call per turn except the Start turn, the commit and launches.
- Fork prompt under 100 tokens; workflow agent prompt 300-1000 tokens, inputs by path.
- Workflow first; fork only for general-purpose jobs or small input living in the conversation. Slot by input volume: small (up to 3 files or under 3K tokens) main-model slot, medium (4-10 files or 3-15K) opus slot, large or unknown sonnet slot. Haiku only for proxies.
- Classes c1-c5 as three slots, one class per whole workflow, no per-stage step; submodes no-sonnet, no-opus, no-fable as one explicit 35-cell table; all three together rejected.
- Every agent() with explicit model and effort; agent frontmatter holds the c3 defaults.
- `/session:base [no-sonnet] [no-opus] [no-fable] [c1..c5]`, `/base` alias, reply line with class and submodes, meta.name `c<class>[-<submodes>]-<slug>`.
- Keep-warm Monitor at 57 minutes (`sleep 3420`).
- Base reads the caveman ruleset by installed path at start (0.10.3), no fallback section.

## Verification

- Hook tests 81/81 (`tests/session-modes-hook.sh`), new cases for class and submode tokens.
- Scenarios T0-T7 on an opus-medium main in `~/projects/empty-context-test`, verdicts from raw JSONLs (`$CLAUDE_JOB_DIR/tmp/basecls-T*.jsonl`): all PASS. T0 rejected all three submodes; T1 c3 research → stage-researcher sonnet-high; T2 no-sonnet → opus-medium; T3 c5 critique → stage-reviewer fable-high; T4 c1 → sonnet-low; T5 tiny job → one Bash call, no workflow; T6 c4 no-fable author → opus-high; T7 c5 no-sonnet no-fable → ops-hi in every slot.
- Two c3 workflows run from this session for cost: Breakout $1.041 (6 agents), FPS $1.601 (8 agents); the fable main-model slot took 38-40% of each run for the plan and critique stages.

## Open

- The driver's own parser reported FAIL for every scenario (it scanned for tool calls only after the reply text); verdicts were taken from the transcripts by hand. Fix the parser before reusing `basecls-run.sh`.
- Cost finding for a later decision: at c3 the plan and critique on fable are the expensive stages; moving them to the opus slot would cut about a third of a workflow's cost.
- Not pushed.
