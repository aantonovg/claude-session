# Critique: 2026-09-12-base-classes.md (hypotheses only, not verified)

Plan: /Users/aleksandr.antonov/projects/claude-session/docs/plans/2026-09-12-base-classes.md

## High

1. high
Submode chain (1e, line 52) reintroduces banned models for two-submode combos: c3 `no-sonnet no-opus` sonnet slot goes sonnet-high -> opus-medium -> sonnet-high; c3 `no-opus no-fable` main slot goes fable-low -> opus-medium (opus banned).
Maps at lines 56-58 are applied left to right on current value; H2 (line 136) claims "no cell lands on a banned model" but single maps as written cannot give that.

2. high
Plan carries two sources of truth: sections 1-3 vs section 5 disagree on opts passing (1f line 64 "only when differs from c3" vs H4 line 138 "every agent() passes"), frontmatter (lines 92-103 vs line 140), reply line (line 70 vs line 142), `base sonnet` (line 84 invalid vs line 139 alias).
Section 5 is appended, sections 1-3 not rewritten; implementer following the body gets 0.10.3-era rules.

3. high
"2 or more tool calls" (line 13) vs kept bullet "one read, one edit, one command, the commit, the report" (line 17): read then edit is 2 calls; unclear if "job" counts across turns or per turn.
Line 14 "at most 1 own call per turn" makes any read+edit fix a fork or two turns; cost and rule collision unstated.

4. high
Rule 5 kept as "3K+ tokens of input is a fork" (line 20) but H3 (line 137) sends 3-15K to opus slot workflow and 1c prefers workflow over fork.
Two thresholds point at different launch kinds for same input; H1 says rule 5 "became the input-volume rule" but line 20 says it stays.

5. high
Slot chosen by role (line 44) and by input volume (line 30) with no tie-break: reviewer on 40 files, author on bulk input.
Both lists are normative; nothing says which wins.

## Medium

6. medium
1c "main-model slot, as a fork" (line 30) vs 1d "fork always runs on the main session's model, not on a slot" (line 46): fable-high main with c1 makes forks bypass class entirely.
Term "main-model slot" conflates session model and class main slot.

7. medium
1d "upscale critique or generation -> main slot" (line 44) is per-stage; H5 (line 139) says upscaling is whole workflow at another class, never per stage.
Role list and H5 written at different times.

8. medium
Mid-flight breakage: sessions on 0.10.3 with `base sonnet` or pairing names get hook rejection, `~/.claude/session-map.md` no longer read by pipeline/review skills, running workflows keep `c1-<pairing>-` meta.name.
No migration or compatibility note; line 84 and line 139 disagree on `sonnet` arg fate.

9. medium
Class read only from base reply line (line 127); reply line printed only after monitor exists (line 70), "no variant without a task id".
Monitor denied or missing means no reply line, class silently falls to c3 even after `/base c5`.

10. medium
Test asserts on "first tool_use after the task prompt" (line 107); deferred tools may make ToolSearch the first call; T1 line 111 uses "or" between no opts and explicit opts, not falsifiable.
Section 5 fixes T1 but table left unchanged; ToolSearch case unaddressed.

11. medium
Edits keyed to 0.10.3 line numbers (lines 9-18, 78) drift once early sections change; section 5 cites lines 236, 315, 333, 465 matching neither list.
Line-based instructions applied in sequence on a shifting file.

12. medium
Hard rule 7 body (line 14) has no Start-turn exception; Start needs ToolSearch, Monitor, style-file read.
Exception only in H1 (line 135); body as written forbids Start.

13. medium
Diff review under 100 lines has no slot (line 44); "bulk" for code/test author undefined until H3 (line 137), and H3 uses files/tokens, not diff lines.
Two different size scales for review vs authoring.

## Low

14. low
Label prefix abbreviations `fab-hi-`, `ops-me-`, `son-lo-` (lines 111-116) never defined in rules section.
Only appear in test table.

15. low
Waiter fixed to `c1-wait-<job>` (line 72) while H5 says class is one setting per workflow; waiter under `no-sonnet` at c1 gets opus-low but name says c1 only.
Submodes absent from waiter name.

16. low
c1 or `no-opus` puts judgment roles (reviewer, critic) on sonnet; c5 sonnet slot is opus-high for bulk logs.
Slot semantics ("judgment", "bulk") stop matching model at edges of table.

17. low
Test setup relies on unverified `effort: medium` project setting ("check claude --help", line 107) and probabilistic model choice (line 128).
Rerun rule "twice" is ad hoc; seven sessions may not separate rule defects from noise.

18. low
`~/.claude/session-map.md` stays on disk after removal from readers (line 48, 81).
Stale file may be picked up by other skills or memory.
