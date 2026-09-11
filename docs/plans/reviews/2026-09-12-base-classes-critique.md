# Critique: base classes, slots, 2-call threshold (2026-09-12)

Inputs: `docs/plans/2026-09-12-base-classes.md`, `plugins/session/base/BASE.md` (0.10.3).
Hypotheses only, not verified. Severity order.

## High

### H1. The Start turn breaks the new "at most 1 own tool call per turn"
Plan 1a (line 14) sets rule 2 to "at most 1, except the commit and the launch of forks
and workflows". BASE "Start" (lines 22-47) requires on that same turn: `ToolSearch`
(when Monitor is not loaded), `Monitor`, `python3` path resolve plus `Read` of the
caveman ruleset — 3-4 own calls, and BASE itself calls the Read "the second tool call of
that turn". Any session that obeys rule 2 literally will drop the style file or the
monitor.
Check: after the edit, `grep -n "second tool call\|at most 1" plugins/session/base/BASE.md`
and read the Start paragraph; the rule needs an explicit exception list
("except the Start turn, the commit and the launch of forks and workflows"), or rule 2
stays at 2 calls while rule 1 moves to 2+ for *jobs*.
Related: a review turn (Read inputs + Write review) is 2 calls, so the rule as written
also forbids the main session writing its own report after one read.

### H2. Submode composition can loop back onto the banned model
Plan 1e: rewrites applied left to right, `no-sonnet` → `no-opus` → `no-fable`.
`c3 no-sonnet no-opus`: sonnet-high → opus-medium (no-sonnet), then no-opus maps
opus-medium → sonnet-high — the sonnet slot ends on the model both submodes ban.
`no-opus no-fable` has the mirror problem: opus-high → fable-medium → opus-high.
Check: enumerate all 7 submode subsets over all 5 classes (a 35-row table) and assert no
resulting value uses a banned model; either forbid conflicting combinations at the
argument parser, or define the rewrites as one pass over the *class row* values with a
fixpoint pass that drops banned models.

### H3. "Input volume" small/medium/large is not decidable
Plan 1c gives only prose ("a few files", "sweeps, logs, many files"). Two sessions will
map the same job to different slots, and the tests in section 3 assume a deterministic
choice (T1 researcher → sonnet slot). It also contradicts hard rule 5 (3K+ tokens of
input is a fork): "a few files" can already exceed 3K.
Fix: numeric thresholds in the rule, e.g. small = up to 3 files or < 3K tokens of input;
medium = 4-10 files or 3-15K tokens; large = more than 10 files, or over 15K tokens, or
any output of unknown size (logs, test runs, sweeps). State the tie-break: when volume is
unknown, treat as large.
Check: `grep -n "input volume" BASE.md` shows a numeric threshold; re-run T1/T4 twice
each and require the same slot both runs.

### H4. Optional opts (1f) contradict the Forbidden rule and the launch checklist
Plan 1f: "with c3 and no submodes the opts carry neither". BASE line 315 ("`model` and
`effort` set explicitly in opts, never inherited"), line 236 ("every `agent()` carries
explicit model and effort"), line 333 (pre-launch check) and Forbidden line 465 ("No
`agent()` without explicit model and effort") all say the opposite, and the plan's file
table only rewrites line 466, not 465. T1 then accepts *either* form, so it cannot fail.
Fix: pick one rule. Recommended: keep opts always explicit (frontmatter is a fallback for
direct launches only) — it keeps the label prefix, the JSONL assertions and the checklist
consistent. Otherwise rewrite 236, 315, 333, 465 in the same change.
Check: the static grep list must include `explicit model and effort`.

### H5. The "Upscale agents" section keeps the old combo vocabulary
Plan section 2 lists lines 228-231, 248-260, 266-267, 279-280 but not lines 200-220. That
section still says "Combos: `opus-medium`, `fable-medium` … `opus-high`, `fable-high`" and
routes critique to `session:stage-reviewer` — after 1d the reviewer sits in the *main*
slot, which is `opus-low` at c1 and `fable-low` at c3, i.e. not an upscale combo at all.
A c1 or c3 session reading both passages gets two different answers for the same launch.
Check: add lines 200-220 to the file table; `grep -n "opus-medium\|fable-medium\|fable-high"
BASE.md` must return only the class table after the edit.

## Medium

### M1. The reviewer-debugger is no longer the strongest slot
BASE line 310 calls reviewer-debugger "(strongest slot)". Under 1d it takes the main slot:
c3 = fable-low, while the opus slot is opus-medium and the sonnet slot sonnet-high. Plan
never states that the demotion is intended, and `skills/pipeline`/`skills/review` pick
roles by that ranking. Also the plan's role list names 8 roles (adds upscale
critique/generation and waiter) while the six-role vocabulary is what the other skills
use.
Check: keep the canonical six-role names in BASE and add one sentence saying which slot is
strongest per class; grep `skills/pipeline/SKILL.md` and `skills/review/SKILL.md` for
"strongest".

### M2. Duplicate slot values make c1 and c5 untestable and possibly wrong
c1: main = opus slot = opus-low. c5: opus slot = sonnet slot = opus-high. The plan calls
neither intentional. Two consequences: bulk sweeps at c5 run opus-high (cost and the
3-call upscale budget were never meant for tool-heavy work), and the `<mod>-<eff>-` label
no longer identifies the slot, so no JSONL assertion can tell which slot fired.
Check: state the intent in the table caption; add a c5 bulk-research scenario (T8) and
decide whether it must be `ops-hi-` or stay sonnet-high.

### M3. The waiter contradicts itself after remapping
1d puts the waiter on the sonnet slot (sonnet-high at c3), the frontmatter table says
sonnet/high, but BASE line 231, line 394 ("pinned to sonnet") and the launch template at
line 405 (`effort: 'low'`) say sonnet-low, and the label section (line 178) says "A waiter
is `son-lo`". Plan section 2 does not list 231/394/405/178.
Check: `grep -n "son-lo\|sonnet-low" BASE.md` after the edit returns nothing unexplained.

### M4. One frontmatter default cannot serve `stage-author`'s two roles
The table gives `stage-author` opus/medium, but 1d routes code/test author to the sonnet
slot for bulk input and the opus slot otherwise. With 1f's "omit opts at c3", a bulk
authoring job at c3 silently runs opus-medium instead of sonnet-high.
Check: T6 is the small-input case only; add a bulk-authoring scenario and assert
`model: 'sonnet', effort: 'high'`.

### M5. Test pass criteria are not all checkable from the JSONL
T1 "all four" over an assertion with an `or` branch (H4) always passes. T5 accepts three
different first tool calls, so it cannot distinguish "obeyed the 2-call rule" from "forked
unnecessarily"; state which is the expected answer and treat the others as soft pass. T7
asserts an exact reply line but gives no rule for the `<id>` placeholder match. T3 relies
on the model choosing `stage-reviewer` for a "hypotheses only" prompt — probabilistic; the
plan's own risk note (line 128) says run twice, but the pass column says "all".
Check: rewrite the pass column as "N of N exact string matches on named JSONL fields",
and mark the model-choice rows as 2-of-2 runs.

## Low

### L1. Statusline hides the default class
Hook change renders bare `base` as `base`, so a c3 session is indistinguishable from a
session with no class in the statusline and in `tests/session-modes-hook.sh`. Consider
rendering `base-c3`. Check: add that case to the hook test either way.

### L2. Canonical order is stated twice and must match
1g prints submodes "in the order given above" (no-sonnet, no-opus, no-fable) while the
hook renders "class first, then submodes in canonical order". Same order, but two
wordings; one drift and T7 fails for a cosmetic reason.
Check: one named ordering constant referenced by both bullets.

### L3. No test covers the newly written prompt-size and haiku rules
1b (fork prompt under 100 tokens, workflow prompt 300-1000) and the "haiku only inside
proxy agents" line have no assertion anywhere in section 3; they are checkable from the
JSONL prompt field (token count, `model: 'haiku'` only for `codex-proxy` /
`claude-code-guide`).
Check: add T9 counting prompt words of the T1/T5 launches.

### L4. Requests that survived
Fork prompt < 100 tokens, workflow prompt 300-1000, haiku only for proxies, main model
independent of the class — all present (1b, 1c, 1d). Nothing from the user's list is
missing; only their verification is (L3).

verdict: not ready
high items: 5
