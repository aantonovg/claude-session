# Code review: base classes, slots, 2-call threshold (2026-09-12, 0.11.0)

Scope: uncommitted diff on `main`. Plan `docs/plans/2026-09-12-base-classes.md`,
critique `docs/plans/reviews/2026-09-12-base-classes-critique.md` (5 high).

Verdict: **PASS**. All five high items are resolved in the text. Four medium/low
items remain; none blocks the release.

## High items from the critique

### H1 — 1-call rule vs the Start turn: resolved
`base/BASE.md:6-7` now reads: rule 1 "never executes a job of 2 or more tool calls
itself: it hands it to a fork or a workflow"; rule 2 "at most 1, except the Start turn
(ToolSearch, Monitor, the style-file path resolve and its Read), the commit, and the
launch of forks and workflows". The Start section (`BASE.md:24-54`) needs exactly those
four calls and no more. `BASE.md:114`, `BASE.md:522` carry the same 2+ threshold; no
"3 or more" / "3+ call" string is left (grep empty).

### H2 — submode composition onto a banned model: resolved
The explicit 35-cell table is at `base/BASE.md:283-289` and, byte-identical, at
`README.md:549-555` (verified by diff of the `| cN |` rows). Six cells recomputed from
the single maps at `BASE.md:276-279`:

- c3 / no-sonnet: son-hi to ops-me, so `fab-lo / ops-me / ops-me` — matches `BASE.md:287`.
- c4 / no-opus: ops-hi to fab-me twice, sonnet untouched, `fab-me / fab-me / son-hi` — matches `BASE.md:288`.
- c2 / no-fable: fab-lo to ops-me, `ops-me / ops-lo / son-me` — matches `BASE.md:286`.
- c5 / no-opus: ops-hi to fab-me in both opus and sonnet slots, `fab-hi / fab-me / fab-me` — matches `BASE.md:289`.
- c4 / no-sonnet no-fable: fab-me to ops-hi, son-hi to ops-me, `ops-hi / ops-hi / ops-me` — matches `BASE.md:288`.
- c1 / no-opus no-fable: ops-lo to son-me twice, son-lo kept, `son-me / son-me / son-lo` — matches `BASE.md:285`.

All 35 cells scanned for the banned model: the `no-sonnet` columns contain no `son`,
the `no-opus` columns no `ops`, the `no-fable` columns no `fab`. Clean. All three
submodes together is an argument error (`BASE.md:280`, `BASE.md:34-36`), enforced by the
hook (`hooks/session-modes.sh:76`).

### H3 — input volume not decidable: resolved
`base/BASE.md:127-132` gives numbers: "small = up to 3 files or under 3K tokens of
input"; "medium = 4-10 files or 3-15K tokens"; "large = more than 10 files, over 15K
tokens, or a size unknown in advance"; "Unknown counts as large." Hard rule 5
(`BASE.md:10`) was rewritten to the same rule, so the old 3K fork rule no longer
competes with it. Haiku restricted to proxies on `BASE.md:132`, `BASE.md:273`.

### H4 — optional opts: resolved
Opts are always explicit. `BASE.md:291-293`, `BASE.md:308-309`, `BASE.md:375-377`,
`BASE.md:395`, `BASE.md:527` all say explicit model and effort; the frontmatter is
called "a fallback for direct launches only". No line anywhere says the opts may be
omitted (grep for "omit", "carry neither" empty).

### H5 — old combo vocabulary in "Upscale agents": resolved
`BASE.md:227-229`: "runs on the main-model slot one class above the session's class (c1
gives the c2 value, c4 gives the c5 value, c5 stays c5), submodes applied after; budget
5 tool calls when the effective effort is medium or lower, 3 at high or above." No
`Mode: sonnet` section, no `pairing`, no `session-map.md` anywhere in the plugin
(grep across `README.md`, `base/BASE.md`, `skills/pipeline/SKILL.md`,
`skills/review/SKILL.md` — only the 0.9.0 history line at `README.md:63` mentions the
old pairing, which is intended as a changelog entry). The strings `opus-medium`,
`fable-medium`, `fable-high` survive only inside the class table
(`BASE.md:262-264`), the submode map prose (`BASE.md:276-279`) and one illustrative
"a fable-high main" (`BASE.md:254`).

## Internal contradictions (checked, mostly clean)

Hard rules / When to delegate / Decision points / Every `agent()` call / Forbidden all
agree on the 2-call threshold, on "prefer a workflow", on explicit model and effort, and
on the class plus submodes in `meta.name`. The waiter is `sonnet-low` consistently
(`BASE.md:203`, `BASE.md:273`, `BASE.md:304`, `BASE.md:467`, `agents/waiter.md`
frontmatter) — critique M3 closed.

### MEDIUM — two agent labels still name the wrong slot
`base/BASE.md:311-313`: web research is labelled `son-me-web-<job>` and cleanup
`son-me-simplify-<job>`. Both disagree with this change: `web-researcher` sits in the
sonnet slot (son-hi at c3) and its frontmatter is now `sonnet` / `high`
(`agents/web-researcher.md`); `simplifier` was moved to the opus slot
(`BASE.md:268`) with frontmatter `opus` / `medium`, so its label prefix should be
`ops-me-`. A session copying these examples emits a prefix that does not match the opts
it passes.

### MEDIUM — "the c3 default" does not describe two frontmatter values
`BASE.md:292` and `README.md:557` say the frontmatter holds "the c3 default". The c3
main-model slot is `fable-low` (`BASE.md:262`), but `agents/stage-reviewer.md` and
`agents/stage-critic.md` carry `fable` / `medium` — the value chosen in plan section 5,
not the c3 cell. Runtime is unaffected (opts are always explicit), but a direct launch
of either agent runs one effort step above the documented default. Either restate the
sentence ("the frontmatter default, c3 except stage-reviewer and stage-critic at medium")
or set both to `low`.

### MEDIUM — critique M1 not addressed
`README.md:519` still calls the reviewer-debugger "the strongest slot". Under the new
table it takes the main-model slot, which is `fab-lo` at c3 while the sonnet slot runs
`son-hi`. `skills/pipeline/SKILL.md` and `skills/review/SKILL.md` pick roles by that
ranking, so the phrase should go or be qualified per class.

### LOW — the table's stated derivation does not cover two submodes
`BASE.md:275-280` says the 35 cells were "built from the single maps", yet the
two-submode cells are not a composition of them: composing `no-sonnet` then `no-opus` on
c1 yields `son-me`, while the table (correctly) gives `fab-lo`. The real rule is the one
in the same sentence — "two submodes leave one model" — plus an effort choice that is
consistent across the table but written down nowhere. Add one sentence naming the
fallback effort rule so a future edit can reproduce the cells.

### LOW — critique L1 left open by choice
`hooks/session-modes.sh:79` renders a bare `base` as `base`, so a default c3 session is
indistinguishable from a class-less one in the statusline. `tests/session-modes-hook.sh`
covers the bare form, so the behaviour is at least pinned.

## Start section, README and the hook (check 3)

Consistent. `BASE.md:27` holds the 3420-second keep-warm loop with
`description: "keep-warm ping every 57m"` and the rationale at `BASE.md:29-32`;
`README.md:167` and `README.md:229` both say 57 minutes; the two remaining "59 minutes"
mentions (`BASE.md:30`) are the recorded reason for the change, not a stale value. The
argument grammar at `BASE.md:32-36`
(`[no-sonnet] [no-opus] [no-fable] [c1|c2|c3|c4|c5]`, any order, default c3, errors on a
second class, an unknown word or all three submodes) matches `base_mode()` in
`hooks/session-modes.sh:64-81` exactly, including the canonical render order
`base[-cN][-no-sonnet][-no-opus][-no-fable]`. The reply line at `BASE.md:38-41` is
`Base on (c3), ping monitor <task id>; forks or workflows for every 2+ call job` — the
section 5 wording, not the older section 1g wording; submodes are appended after the
class in the same canonical order, closing critique L2.

## Generated skill, frontmatter, tests (checks 4-6)

- `skills/base/SKILL.md` is regenerated: re-running `base/split.sh` produces no diff, and
  the body below the four frontmatter lines is identical to `base/BASE.md`.
- Agent frontmatter matches the role table of `BASE.md:266-273` and `README.md:541-547`:
  `stage-author` opus/medium, `stage-researcher` and `stage-executor` sonnet/high,
  `waiter` sonnet/low, `simplifier` opus/medium, `codex-proxy` haiku/medium,
  `code-reviewer` / `security-reviewer` / `web-researcher` sonnet/high, artifact agents
  opus/medium. Only `stage-reviewer` / `stage-critic` deviate as described above.
- `tests/session-modes-hook.sh:55-64` adds 9 cases for the new tokens (`base c4`,
  `base no-sonnet c4`, canonical reordering, bare `/base no-opus`, `c9`, the retired
  `sonnet`, all three submodes, two classes, and the expanded-args form). Suite result:
  81/81 pass.
- Versions bumped to 0.11.0 in `plugins/session/.claude-plugin/plugin.json:3` and
  `.claude-plugin/marketplace.json:16`.
