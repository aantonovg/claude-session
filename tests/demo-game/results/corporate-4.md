# Corporate test sessions, 2026-09-06 (bw, opus-low main, fable-opus pairing)

$ = deduplicated by message id over main + subagent + workflow transcripts, price table
`tools/pipeline_cost_prices.py`. `pipeline-cost.py` session totals in brackets (its w5/w1 split
differs slightly). Wall = first to last main turn. Cold = workflow agents.

## Table 1

| session | task | mode | wall min | turns main/all | $ dedup | misses | forks | cold | drafts | harness failures |
|---|---|---|---|---|---|---|---|---|---|---|
| review-mr (4365d0b8) | unified-errors!23, first pass | pipeline full + review-full | 56 | 73/176 | 13.97 (14.86) | 2 | 10 | 2 | 3 (2 findings + summary; reworked, then deleted) | 16 lines: registry 403, docker down, linter version skew, cold agent no MCP |
| review-mr2 (a3736157) | fixforge!1319 | pipeline full + review-full | 42 | 58/121 | 9.98 (10.68) | 2 | 8 | 2 | 2 (1 finding + summary) | 6 lines: cold agent no GitLab MCP, registry blocked locally |
| research-22116 (08596e75) | B2CT-22116 resume, through Gate D | pipeline full | 24 | 42/125 | 8.11 | 1 | 5 | 7 | – (nothing written to Jira/GitLab) | curl 403 misread as VPN down (one wasted wave) |
| review-mr3 (81eb5d36) | unified-errors!23 from scratch, corrected skill, Docker on | pipeline full + review-full | 36 | 53/158 | 11.01 (11.63) | 1 | 8 | 2 | 2 (1 finding + summary) | 6 lines: cold agent no GitLab MCP, stale registry login, SSH clone hangs |

## Table 2: $ by kind

| session | main | forks | workflow agents |
|---|---|---|---|
| review-mr | 5.87 | 7.60 | 0.51 |
| review-mr2 | 4.94 | 4.59 | 0.45 |
| research-22116 | 3.45 | 3.42 | 1.25 |
| review-mr3 | 4.13 | 6.48 | 0.40 |

## Table 3: cold-stage rows (from ledgers and transcripts)

| session | stage | model:effort | calls | input tokens | state |
|---|---|---|---|---|---|
| review-mr | 1-research cold-research | sonnet:low | ? | ? | BLOCKED: no GitLab MCP → fetch+framing fork (11 calls, 1.24M) |
| review-mr | 2 contract-critique | fable:high | 3 | 41K | done, document only |
| review-mr2 | 1-research cold-research | sonnet:low | 3 | 43K | done (no MCP, file inputs only) |
| review-mr2 | 2 contract-critique | fable:high | 3 | 38K | done, document only |
| research-22116 | 1 wave1 EB-1/2/3 + retries EB-2/3 | sonnet:low ×5 | – | – | 2 returned "VPN down" on a curl 403, retried, both delivered |
| research-22116 | 2 critic | fable:medium | – | – | done, document only |
| research-22116 | 3 decision-review | fable:medium | – | – | FAIL (1 high) → fix fork → re-verdict by a fork (cold ceiling hit) |
| review-mr3 | 1-research fetch | sonnet:low | 4 | 72K | done, then fetch+framing fork (12 calls, 1.21M) |
| review-mr3 | 2 contract-review | fable:high | 3 | 39K | done, document only |

Transcripts for research-22116 cold rows were not resolved by the script (agent ids missing on
5 of 7 rows; label resolution needs the fixed script re-run).

## Observations

- Research split in research-22116: breadth (MR fixforge!1307 state, helm 874/855, frontend MRs) went to 5 cold sonnet-low researchers (2 retries), judgment (framing, wave-2 thread verdicts, evidence audit F1-F4, contract, contract-fix) to forks; the cold share of $ is 15%, the highest of the four runs.
- unified-errors!23: first pass 56 min / $13.97 with 3 drafts of ~900 words; from-scratch third pass 36 min / $11.01 with 2 drafts under the caps. Different finding sets: pass 1 raised the false checkbox and the copied commit body; pass 3 raised only the false checkbox (CLAUDE.md:40) and missed the commit body.
- Wasted cold researchers: every review run started with a sonnet-low researcher that had no GitLab MCP and produced nothing usable (review-mr BLOCKED outright); the MCP fetch then ran again in an opus-low fork at 1.2M read tokens. Cost of the pattern ≈ $0.9-1.0 per run.
- Nothing above opus-low read code: the fable:high critiques took 38-41K input each (documents), 3 calls; the fable:medium critic and decision review in research-22116 likewise. The only source reads were opus-low forks (no-oracle read in fixforge, 6 calls, allowed by the loaded text).
- Forks dominate cost again (46-58% of $ in the review runs), each opus-low fork reading 0.5-1.3M tokens of prefix; the main session's own turns are 35-50%.
- Versus 2026-09-05 B2CT-22116 (through Gate D): $17.84 opus-low on the VM, $11.84 fable-low on the Mac; today's research-22116 on opus-low with the cold-researcher rule: $8.11 in 24 min, Gate D passed on the second attempt. Ordering: rules ($17.84 → $8.11 on the same model and task) beat the model switch.
