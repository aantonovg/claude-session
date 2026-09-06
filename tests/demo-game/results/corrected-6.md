# Demo game benchmark: 6 corrected runs (2026-09-06, after the effort rule)

Same prompt and kit as `partial-7.md`. These runs started after the pipeline skill got the
effort rule (medium/high only for documents; final review = document check on opus-low; no
heavy code review). `$ total` = every JSONL under the run's project dir, deduplicated by
message id, priced with `tools/pipeline_cost_prices.py` (`session-cost.py`); the haiku codex
shims are inside it. `$ codex` = `~/.codex/proxy-usage.jsonl` rows in the run's window, priced
with the codex table (astra priced unofficially, see footnote). Wall = first to last main turn.

## Table 1: runs

| run | mode | model | wall min | turns main / all | $ total | $ codex | misses | tests | commits | src files | JS lines |
|---|---|---|---|---|---|---|---|---|---|---|---|
| p-full-opus-v2 | pipeline full | opus-low (+fable critic) | 33 | 53 / 178 | 10.91 | – | 0 | 74/0 | 7 | 11 | 1617 |
| p-full-fable-v2 | pipeline full | fable-low (+opus final review) | 40 | 67 / 147 | 11.01 | – | 0 | 44/0 | 4 | 10 | 829 |
| p-std-opus-v3 | pipeline standard | opus-low | 47 | 54 / 114 | 8.16 | – | 0 | 56/0 | 5 | 12 | 1128 |
| p-fast-opus-v2 | pipeline fast | opus-low | 20 | 22 / 62 | 3.55 | – | 1 | 26/0 | 3 | 10 | 713 |
| p-astra-opus | pipeline full + codex astra | opus-low, astra heavy | 36 | 66 / 221 | 14.37 | 0.35 (2 calls, 41K in / 2.3K out)[^astra] | 1 | 49/0 | 5 | 10 | 1184 |
| p-sol-terra-opus | pipeline full + codex sol-terra | opus-low, sol heavy, terra executor | 71 | 121 / 392 | 28.08 | 1.78 (sol 0.36, terra 1.42) | 1 | 43/0 | 10 | 12 | 1470 |

Every run: index.html, README, `node --check` clean, all tests green.

## Table 2: $ by kind (pipeline ledger; cold rows without a transcript are in the session total)

| run | fork | workflow-agent (cold) | codex shim (haiku) | main / unattributed | session total |
|---|---|---|---|---|---|
| p-full-opus-v2 | 6.32 (9 rows, 110 turns) | 0.21 (fable critic, 3 turns; opus final reviews inside unattributed) | – | 4.59 (68 turns) | 10.91 |
| p-full-fable-v2 | 5.29 (13, 73) | 0.17 (opus final review) + fable critic in session | – | 1.12 main row + 4.61 unattributed | 11.01 |
| p-std-opus-v3 | 3.34 (11, 52) | critic opus-medium (54K in, in main model total) | – | 4.35 (54 turns) + 0.47 | 8.16 |
| p-fast-opus-v2 | 2.25 (4, 40) | – | – | 1.29 (22 turns) | 3.55 |
| p-astra-opus | 9.32 (11, 130) | 0.53 (2 final reviews, opus-low) | 0.04 (2 shims) | 4.48 (66 turns) | 14.37 |
| p-sol-terra-opus | ≈ 20 (fork rows, 338 opus turns incl. main) | 0.50 (2 final reviews, opus-low) | 0.18 (12 shims) | main inside the opus total | 28.08 + 1.78 codex |

## Table 3: cold-stage audit (workflow agents; codex targets from the ledger)

| run | stage | model | effort | tool calls | input tokens | read diff / src |
|---|---|---|---|---|---|---|
| p-full-opus-v2 | critic | fable | medium | 3 | 65K | no / no |
| p-full-opus-v2 | final review r1 (document check) | opus | low | 9 | 191K | no / no |
| p-full-opus-v2 | code review of unverifiable browser layer | opus | low | 6 | 85K | no / yes |
| p-full-opus-v2 | final review r2 | opus | low | 9 | 212K | no / yes |
| p-full-fable-v2 | critic | fable | low | 4 | 56K | no / no |
| p-full-fable-v2 | final review | opus | low | 7 | 151K | no / no |
| p-std-opus-v3 | critic | opus | medium | 3 | 54K | no / no |
| p-fast-opus-v2 | (no cold stages) | | | | | |
| p-astra-opus | critic | astra (via haiku shim) | low | shim 6 | 19K codex in | no / no |
| p-astra-opus | decision review | astra (shim) | medium | shim 6 | 22K codex in | no / no |
| p-astra-opus | final review r1 | opus | low | 9 | 311K | no / yes |
| p-astra-opus | final review r2 | opus | low | 8 | 235K | no / no |
| p-sol-terra-opus | critic | sol (shim) | medium | shim 6 | 21K codex in | no / no |
| p-sol-terra-opus | decision review | sol (shim) | high | shim 5 | 25K codex in | no / no |
| p-sol-terra-opus | harness + 6 packages | terra (shim) | high | 8 shims | 118K-568K codex in each | codex edits in place |
| p-sol-terra-opus | final review r1 (document check) | opus | low | 16 | 507K | no / no |
| p-sol-terra-opus | code review of browser-only code | terra (shim) | high | shim | 43K codex in | yes (allowed) |
| p-sol-terra-opus | final review r2 | opus | low | 7 | 181K | no / no |

Verdict: no agent above opus-low read code or the diff. The two medium agents (fable critic,
opus critic) stayed on documents with 3 calls. Source reads happened only in opus-low final
reviews and the terra-high diff-scoped review, both permitted by the text those sessions
loaded (the final rule since then: no code review at all).

## Observations

1. Full pipeline got cheaper after the rule: p-full-opus 13.02 → 10.91 (−16%), p-full-fable
   11.66 → 11.01 (−6%), with zero misses and more tests on opus (55 → 74). The v1 heavy
   final reviews ($2.7 per run) are gone; what remains is fork prefix re-reads (10-14M read
   tokens per run, 58% of p-full-opus-v2).
2. `standard` now costs less than `full` (8.16 vs 10.91) but took longer (47 min) and its
   main session did 54 turns and $4.35 itself: the main session, not the forks, is the
   biggest single line in the standard run. v1 standard was 15.16.
3. `fast` dropped 5.28 → 3.55 (22 main turns, 4 forks, 26 tests); still 26% dearer than
   the workflow-only run (4.17) and cheaper than plain forks on fable (4.79) or opus (f-opus,
   statusline 6.44).
4. Cheap modes stay cheapest: wf-fable 4.17 / 46 tests, f-fable 4.79 / 32 tests, fast 3.55 /
   26 tests. The full pipeline buys 44-74 tests and 2× the code for 2.5-3× the money.
5. Astra works (2 calls, low and medium, 19-22K input each, real review files with
   severity); its run cost 14.37 on the Claude side, dearer than plain full because it ran
   130 fork turns (14M read tokens) and one miss. Codex $ for astra ≈ 0.35 (unofficial price).
6. sol-terra is the dearest valid run: 28.08 + 1.78 codex, 71 min, 392 turns. Terra wrote
   the harness and 6 packages (9 calls, 2.4M codex input, only $1.42) but every package
   then needed an opus fork to read the diff and commit, so the Claude side did 338 turns
   and 40.7M read tokens. Cheap executor, expensive supervision.
7. Ledger still misses agent ids for most cold rows (p-full-opus-v2 4 rows, p-full-fable-v2
   2, p-std-opus-v3 2, all codex rows); their cost lands in the session total only.
8. Per-line comparison: p-full-opus-v2 delivered 1617 JS lines and 74 tests for 10.91
   (≈ $6.7 per 1000 lines); wf-fable 858 lines / 46 tests for 4.17 ($4.9 per 1000);
   f-fable 638 lines / 32 tests for 4.79 ($7.5 per 1000). Quality of play is not measured
   here (browser check pending).

[^astra]: gpt-6-astra priced at $10 / $1 cached / $50 per 1M tokens (input / cached input / output), unofficial: https://www.cloudzero.com/blog/gpt-6-pricing/ (also OpenRouter and press, 2026-09-06); the official OpenAI pricing page returned 403 to the fetch. Billable input = input − cached.
