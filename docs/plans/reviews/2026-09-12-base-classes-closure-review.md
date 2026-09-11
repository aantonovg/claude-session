# Closure review: base classes (2026-09-12)

Inputs: `docs/plans/2026-09-12-base-classes-closure.md`, `docs/plans/2026-09-12-base-classes.md`,
`docs/plans/reviews/2026-09-12-base-classes-critique.md`,
`docs/plans/reviews/2026-09-12-base-classes-code-review.md`.

## Medium

### M-a. Critique mediums and lows neither claimed fixed nor listed open
Closure line 3 names only three fixed mediums (stage-reviewer/stage-critic effort, example
labels, README wording) — the three MEDIUMs of the code review. Critique M2 (duplicate slot
values at c1/c5, asks for a c5 bulk scenario T8), M4 (bulk-authoring scenario asserting
`model: 'sonnet', effort: 'high'`), M5 (pass column as N-of-N exact string matches, model-choice
rows 2-of-2), L1 (bare `base` renders `base`), L3 (T9 prompt-size and haiku assertions) appear
nowhere in the closure. Fix: add a line per item to `closure.md` section "Open" with the decision
(fixed / accepted as is / deferred), or state once that critique mediums/lows below the code
review's three were accepted as is.

### M-b. Test scenarios do not match plan section 3
Plan T1-T7 (lines 111-117) has T7 = exact reply line `Base on (c5, no-sonnet, no-fable), ping
monitor <id>; forks ... 2+ call job`. Closure line 19 runs T0-T7 with T7 = "c5 no-sonnet no-fable
→ ops-hi in every slot" and a new T0 (all three submodes rejected). The reply-line assertion has
no observed value anywhere. Fix: in `closure.md` line 19 record the observed reply line for the
c5 no-sonnet no-fable session, or say the plan T7 assertion was folded into T0 and dropped.

### M-c. Code review LOW (table derivation) unresolved
`code-review.md:93-99` asks for one sentence naming the fallback effort rule for the two-submode
cells of the 35-cell table. Closure claims no fix and lists no open item. Fix: add it to
`closure.md` "Open" or state the sentence was added to `BASE.md`.

## Low

### L-a. Static checks of plan section 3 have no observed value in the closure
Plan line 119 requires three static checks (grep for `3 or more|3+ call|Mode: sonnet|pairing`,
hook suite, `split.sh` diff empty). Closure "Verification" records only 81/81 hook tests; the
grep and the `split.sh` diff are observed in the code review (`code-review.md:17`, `:121-124`)
but not carried over. Fix: one line in `closure.md` "Verification" citing both as PASS.

## Verified clean

- Five critique highs H1-H5: all addressed per `code-review.md:11-59`, verdict PASS; closure line 3
  matches.
- H5 later correction present: `closure.md:10` "one class per whole workflow, no per-stage step",
  matching plan line 139 (critique in the class's own main slot, budgets 5 at medium / 3 at high).
- Delivered rules (closure lines 7-14) each trace to a plan section: 1a, 1b, 1c, 1d, 1e, 1f, 1g,
  keep-warm 3420 s, style-file read by installed path.
- Driver parser FAIL and "not pushed" correctly listed as open; the cost finding is flagged as a
  later decision, not a promise.

verdict: closed with notes
