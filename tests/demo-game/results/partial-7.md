# Demo game benchmark, partial results: 7 finished runs (2026-09-06)

Same prompt (`tests/demo-game/prompt.md`, Asteroid Dodge), same plugin source dir, one run
directory each. `$ total` = every JSONL under the run's project dir, deduplicated by
message id, priced with the pipeline-cost.py table (`tests/demo-game/session-cost.py`).
`$ statusline` = the number shown in the pane, known to overcount (re-logged turns).
Wall = first main turn to the last non-ping main turn. Codex spend is priced from
`~/.codex/proxy-usage.jsonl` and added to `$ total` for the codex run.

## Table 1: runs

| run | mode | model | wall min | turns main / all | $ total | $ statusline | misses | tests | commits | src files | JS lines |
|---|---|---|---|---|---|---|---|---|---|---|---|
| p-full-opus | pipeline full | opus-low (+fable cold) | 30 | 57 / 190 | 13.02 | 18.51 | 1 | 55/0 | 6 | 11 | 1095 |
| p-full-fable | pipeline full | fable-low | 24 | 79 / 183 | 11.66 | 15.81 | 1 | 42/0 | 5 | 9 | 701 |
| wf-fable | workflow | fable-low main, opus agents | 13 | 14 / 68 | 4.17 | 5.72 | 0 | 46/0 | 4 | 12 | 858 |
| p-fast-opus | pipeline fast | opus-low | 10 | 37 / 83 | 5.28 | 7.12 | 0 | 30/0 | 4 | 9 | 837 |
| p-std-opus | pipeline standard | opus-low (+fable cold) | 28 | 72 / 230 | 15.16 | 19.56 | 0 | 88/0 | 8 | 12 | 1502 |
| p-sol-opus | pipeline full + codex sol | opus-low, sol heavy | 68 | 104 / 383 | 26.33 + 3.83 codex = 30.16 | 35.61 | 1 | 82/0 | 11 | 12 | 1829 |
| f-fable | forks | fable-low | 9 | 24 / 73 | 4.79 | n/a | 1 | 32/0 | 6 | 8 | 638 |

Every run: index.html, README, `node --check` clean on all src files, all tests green.

## Table 2: $ by kind (from the pipeline ledger; workflow-agent rows without a transcript
show 0 and land in the session total instead)

| run | fork | workflow-agent (cold) | codex-agent | main / unattributed | session total |
|---|---|---|---|---|---|
| p-full-opus | 7.52 (11 rows, 116 turns) | 0.00 in ledger; ~1.40 as fable rows in the session | – | 5.50 (74 turns) | 13.02 |
| p-full-fable | 6.03 (14, 91) | 1.05 (3, 13) | – | 4.58 (79) | 11.66 |
| p-fast-opus | 0.93 (5, 20) | – | – | 4.35 (63) | 5.28 |
| p-std-opus | 6.36 (13, 97) | 0.00 in ledger; ~1.18 fable rows | – | 5.34 (main row) + 3.47 | 15.16 |
| p-sol-opus | 19.13 (21, 249) | – | 2.09 joined (5 of 8 codex rows); raw window sum 3.83 | 7.20 (134) | 28.42 (+ codex) |
| wf-fable | – | opus agents 1.33 (39 turns), main fable 2.84 (29 turns) | – | – | 4.17 |
| f-fable | forks 73 turns total | – | – | – | 4.79 |

Per-stage, p-full-opus: implementation 4.78, final review 0.92, decision 0.77, closure 0.73,
research 0.32. p-full-fable: implementation 3.58, final review 1.25, verification 0.69,
decision 0.57, research 0.40, closure 0.37, critic 0.21.

## Observations

1. Cheapest by far: workflow-only (wf-fable, $4.17, 13 min) and plain forks (f-fable,
   $4.79, 9 min); both produced a complete game with 46 and 32 green tests. The full
   pipeline costs 2.5-3× as much for the same prompt.
2. Model effect inside the pipeline is small: p-full-fable $11.66 versus p-full-opus
   $13.02; fable was faster (24 versus 30 min) and wrote less code (701 versus 1095 lines).
3. `pipeline standard` was NOT cheaper than `pipeline full` on opus ($15.16 versus $13.02,
   230 turns versus 190); its main session alone ran 72 turns and 38K output tokens. The
   path argument does not shorten the work; only `fast` does ($5.28, 10 min).
4. Cost is read tokens: 15-41M cache-read tokens per pipeline run, 95% of it forks
   re-reading the main prefix. The p-sol-opus run had 249 fork turns and 30.6M read
   tokens, $19 of its $26; codex itself cost under $4.
5. Codex sol as heavy reviewer: 8 launches (3 retries at the critic), inputs up to 470K
   per call because the shim passed the whole repo context; the ledger caught 5 of 8
   rows ($2.09 joined versus $3.83 raw), so the join needs the retry rows too.
6. Misses: one per full run (p-full-opus, p-full-fable, p-sol-opus, f-fable), none in
   fast, standard and workflow. Each is one fork whose suffix expired.
7. Ledger gaps: cold-stage transcripts not found for p-full-opus (3 rows), p-fast-opus
   (3), p-std-opus (7): the `agent_id` was left empty ("(none)") so the script cannot
   attribute them; the cost still appears in the session total.
8. Quality proxy (tests, commits, lines) grows with spend: p-std-opus 88 tests and
   p-sol-opus 82 tests versus 30-46 for the cheap runs. Whether that is better play needs
   the browser check (not done here).

## Invalidated

p-sol-opus and p-sol-luna-opus ran heavy code reviews: sol-high read the whole repository
for the semantic and final reviews (300-470K input tokens per call, 5 sol-high calls in
p-sol-opus alone). That contradicts the effort rule (medium/high only for generating and
critiquing documents within 3-5 tool calls; code is verified by the harness, code review
only for unverifiable packages on opus-low or terra-high). Both runs count as failed;
their cost and quality numbers are not comparable with the other runs.
