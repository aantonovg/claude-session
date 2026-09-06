# Demo game benchmark: final table (2026-09-06)

One prompt (`tests/demo-game/prompt.md`, Asteroid Dodge), one plugin source dir, one fresh
repository per run. `$ total` = every JSONL under the run's project dir deduplicated by
message id and priced with `tools/pipeline_cost_prices.py` (`session-cost.py`); haiku codex
shims are inside it. `$ codex` = `~/.codex/proxy-usage.jsonl` rows in the run's window priced
with the codex table (astra unofficial, see `corrected-6.md`). `$ per test` and `$ per 100 JS
lines` use `$ total + $ codex`. Wall = first to last main turn. Cold = workflow agents and
codex agents. Skill version: `v1 rules` = the pipeline text of the morning (heavy final
review allowed); `corrected` = after the effort rule (medium/high only for documents, final
review = document check on opus-low); `final` = the executor rule of 14:05 (codex packages
run the harness and commit themselves, no diff-reading forks). The `workflow` and `forks`
modes never loaded the pipeline text, so their rows are unaffected by those edits.

## Table 1: valid runs

| run | mode | main model | wall min | turns main/all | $ total | $ codex | $/test | $/100 JS lines | misses | tests | commits | src files | JS lines | cold agents | skill version |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| wf-fable | workflow | fable-low (opus agents) | 13 | 14/68 | 4.17 | – | 0.09 | 0.49 | 0 | 46 | 4 | 12 | 858 | all stages (39 opus turns) | unaffected |
| f-fable | forks | fable-low | 9 | 24/73 | 4.79 | – | 0.15 | 0.75 | 1 | 32 | 6 | 8 | 638 | 0 | unaffected |
| f-opus | forks | opus-low | 47 | 21/73 | 4.16 | – | 0.08 | 0.46 | 1 | 53 | 5 | 10 | 911 | 0 | unaffected |
| p-fast-opus-v2 | pipeline fast | opus-low | 20 | 22/62 | 3.55 | – | 0.14 | 0.50 | 1 | 26 | 3 | 10 | 713 | 0 | corrected |
| p-std-opus-v3 | pipeline standard | opus-low | 47 | 54/114 | 8.16 | – | 0.15 | 0.72 | 0 | 56 | 5 | 12 | 1128 | 1 (opus-medium critic) | corrected |
| p-full-opus-v2 | pipeline full | opus-low | 33 | 53/178 | 10.91 | – | 0.15 | 0.67 | 0 | 74 | 7 | 11 | 1617 | 4 (fable-medium critic, 3 opus-low reviews) | corrected |
| p-full-fable-v2 | pipeline full | fable-low | 40 | 67/147 | 11.01 | – | 0.25 | 1.33 | 0 | 44 | 4 | 10 | 829 | 2 (fable-low critic, opus-low review) | corrected |
| p-astra-opus | pipeline full + codex astra | opus-low, astra heavy | 36 | 66/221 | 14.37 | 0.35 | 0.30 | 1.24 | 1 | 49 | 5 | 10 | 1184 | 4 (astra critic + decision review, 2 opus-low reviews) | corrected |
| p-sol-terra-opus-v2 | pipeline full + codex sol-terra | opus-low, sol heavy, terra executor | 52 | 78/200 | 11.86 | 1.97 (sol 0.39, terra 1.59) | 0.60 | 1.03 | 0 | 23 | 7 | 12 | 1345 | 10 (sol critic, sol decision review, 8 terra packages) | final |

Every run: index.html, README, `node --check` clean on all src files, all tests green.
f-opus wall time includes a 30-minute idle gap inside the run (statusline showed it done at
11:40 after a 10:53 start); its working time was under 20 min.

## Table 2: invalid runs (kept for reference)

| run | mode | $ total (+codex) | reason |
|---|---|---|---|
| p-full-opus (v1) | pipeline full, opus-low | 13.02 | superseded by p-full-opus-v2 (fable-medium final reviews read the diff) |
| p-full-fable (v1) | pipeline full, fable-low | 11.66 | superseded by p-full-fable-v2 (final reviews read the diff at low) |
| p-std-opus (v1) | pipeline standard, opus-low | 15.16 | superseded by p-std-opus-v3 (standard path was not actually lighter) |
| p-fast-opus (v1) | pipeline fast, opus-low | 5.28 | superseded by p-fast-opus-v2 (fast path formalized) |
| p-sol-opus | pipeline full + codex sol | 26.33 + 3.83 | sol-high reviewed code (300-470K input per review) |
| p-sol-luna-opus | pipeline full + codex sol-luna | ≈ 35 (killed mid-fix) | sol-high final code review, luna packages at 0.8-2.1M input each |
| p-sol-terra-opus (v1) | pipeline full + codex sol-terra | 28.08 + 1.78 | opus forks read the diff, ran tests and committed after every terra package (338 opus turns) |

## Table 3: corporate sessions (from `corporate-4.md`)

| session | task | mode | wall min | turns main/all | $ dedup | misses | forks | cold | drafts | harness failures |
|---|---|---|---|---|---|---|---|---|---|---|
| review-mr | unified-errors!23, first pass | pipeline full + review-full | 56 | 73/176 | 13.97 | 2 | 10 | 2 | 3 (deleted) | registry 403, docker down, linter version skew, cold agent no MCP |
| review-mr2 | fixforge!1319 | pipeline full + review-full | 42 | 58/121 | 9.98 | 2 | 8 | 2 | 2 | cold agent no GitLab MCP, registry blocked locally |
| research-22116 | B2CT-22116 resume, through Gate D | pipeline full | 24 | 42/125 | 8.11 | 1 | 5 | 7 | – | curl 403 misread as VPN down (one wasted wave) |
| review-mr3 | unified-errors!23 from scratch, corrected skill, Docker on | pipeline full + review-full | 36 | 53/158 | 11.01 | 1 | 8 | 2 | 2 | cold agent no GitLab MCP, stale registry login, SSH clone hangs |

## sol-terra v1 vs v2

- Turns: 392 → 200 (main 121 → 78); opus turns 338 → 148; forks 21 rows → 8 rows (framing, prompt files, plan, decision fix, closure, report). No fork read a diff or ran tests in v2.
- $: 28.08 → 11.86 on the Claude side (−58%); with codex 29.86 → 13.83 (−54%). Codex $ rose 1.78 → 1.97 (terra now runs the harness and commits inside each package: 8 terra calls, 2.7M input, 1.59).
- Wall: 71 → 52 min; the terra packages themselves took 21 min (11:12-11:33), the rest is Claude-side pipeline stages.
- Output: 43 tests / 1470 lines → 23 tests / 1345 lines, 10 → 7 commits: the v2 harness is smaller (terra wrote fewer tests when nobody asked for more), so $/test is the worst of the valid runs (0.60) while $/100 lines (1.03) sits between full-opus (0.67) and full-fable (1.33).
- Executor-axis verdict: with the final rule the terra executor stops being ruinous (13.83 vs 10.91 for plain full opus) but still does not save money: the sol document reviews cost 0.39, the terra packages 1.59, and the Claude side around them 11.86 (main 78 turns plus 8 forks over a 140K prefix) is more than a plain full run's 10.91. The executor axis buys wall time and codex quota use, not dollars; the heavy axis alone (astra 0.35, sol 0.39) is cheap but its Claude side (14.37, 11.86) was never cheaper than plain full either.
