# Regroup check (branch regroup-0.7, base injected by SessionStart hook), 2026-09-06

Same method as `final-table.md`: `$ dedup` = every JSONL under the run's project dir (luna run: its own session id only) deduplicated and priced with `tools/pipeline_cost_prices.py`; codex $ from `~/.codex/proxy-usage.jsonl` luna rows after 12:10 UTC (0.2 / 0.02 / 1.2 USD per M input / cached / output). Wall = first to last main assistant message. `b-std-opus` was still running and is not in this pass.

## Table 1: runs of the regrouped plugin vs references

| run | mode | model | wall min | turns main/all | $ dedup | $ codex | misses | tests | commits | JS lines | base injected | subagent transcripts with base text |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| b-fable | base only (no skill) | fable-low | 19 | 12/24 | 2.44 | – | 1 | 21 | 5 | 562 | yes ("Base on, ping cron d8e89661") | 0 of 1 |
| b-opus | base only (no skill) | opus-low | 7 | 41/26 msgs | 2.23 | – | 0 | 27 | 4 | 712 | yes | 0 of 0 (no subagents at all) |
| research-luna | pipeline full + codex luna, B2CT-22116 through Gate D | opus-low; luna repo research; fable-medium critic and decision review | 43 | 77/169 | 12.94 | 0.18 (3 luna runs, 4.2M input, 3.9M cached) | 0 | – | – | – | no (session started before the base hook existed; loaded `session:pipeline` 0.6.0 text) | 0 of 20 |
| f-fable (reference) | forks | fable-low | 9 | 24/73 | 4.79 | – | 1 | 32 | 6 | 638 | n/a | – |
| f-opus (reference) | forks | opus-low | 47 (20 working) | 21/73 | 4.16 | – | 1 | 53 | 5 | 911 | n/a | – |
| research-22116 (reference) | pipeline full, cold sonnet researchers | opus-low | 24 | 42/125 | 8.11 | – | 1 | – | – | – | n/a | – |

Turn counts: `turns main/all` = main assistant messages / unique priced requests across all transcripts (session-cost). b-opus: 41 assistant messages, 26 priced requests, one transcript.

## Table 2: luna run, cost by kind and where the work went

| kind | rows | turns | read tokens | $ |
|---|---|---|---|---|
| fork (opus-low) | 9 | 83 | 10.5M | 7.06 |
| workflow-agent (2 sonnet-low researchers, fable-medium critic, fable-medium decision review) | 4 | 10 | 0.13M | 0.86 |
| codex-agent (luna-high, 2 ledger rows, 3 usage records) | 2 | 22 (haiku shim) | 4.1M (luna side) | 0.29 incl. shim (0.18 luna) |
| main session, outside ledger rows | – | 56 | – | 4.92 |
| session total | 15 rows | 171 | 21.0M | 13.13 (session-cost dedup: 12.94) |

Where the work went: luna = repo research wave 1 (2.4M input, 21K out) and the code-side evidence audit (1.6M input); cold sonnet-low = the two MCP research slots (Jira, GitLab), both returned `BLOCKED: no MCP` after 4 turns, $0.10; forks = harness gate (6 turns), framing + ledger + codex prompt file, the two MCP fallback researchers (Jira, GitLab), ledger close (6), wave-2 targeted GitLab (14), MCP evidence audit (7), ledger fix (6), decision evidence + fix (16).

## Findings

- Cost vs references. Base-only runs are cheaper than the forks-mode references on the same task: b-fable 2.44 vs f-fable 4.79 (half the turns, 21 tests vs 32, 562 vs 638 lines), b-opus 2.23 vs f-opus 4.16 (27 tests vs 53). The luna research run is dearer than the cold-researcher reference: 12.94 vs 8.11 (+60%); luna itself cost 0.18, the nine opus forks around it 7.06 and the main session 4.92.
- Rule deviations. b-opus made no fork at all: 19 Bash calls inline, plus a Chrome MCP call, against the base's "3+ tool calls → fork" rule; its output is fine but the base was read and not followed. b-fable made one fork and three inline Bash calls (borderline). Luna run: two forks over 12 turns (wave-2 GitLab 14, decision evidence + fix 16); no heavy agent read code (critic and decision review at fable-medium, 3 calls each, documents only).
- Codex envelope. The luna run still had relay forks: one fork wrote the codex prompt file and the ledger, and the wave-1 outcome was folded into the ledger by an opus "ledger close" fork (6 turns, $0.52). The fork-free envelope landed on the branch after this session started, so this run measures the old envelope; the envelope cost here is about $1.0-1.5 of the $7.06 fork total.
- Cold researchers and MCP. Both sonnet-low researchers returned `BLOCKED: no MCP` (MCP tools not visible to workflow agents under bw even with exact tool names), and the fetch went to two opus forks per the fallback rule; cost of the failed cold attempts $0.10. The harness gate itself passed: "GitLab API ok (root 403 = nginx, not VPN), Atlassian MCP ok, GitLab MCP ok, codex -p b2connect mcp list lists atlassian/gitlab/grafana/kubernetes"; the Sources block's `wanted, unavailable` list was reported (workflow-agent MCP visibility).
- Gate D: pass after one review + evidence + fix round (the fable-medium decision review returned high first, the fix fork closed it). Contract: rebase !1307 on develop and fix in place, no A/B/C split. No Jira or GitLab writes. Base injection: present in both b-* main sessions, absent from every subagent transcript (0 of 21), as intended.

## Table 3: round 2 (branch text with hard fork rules, fork-free codex envelope), 2026-09-06 16:20-17:16

Same method. Wall = first to last main assistant message, ping turns included (real work ended earlier for the base-only runs). `forks >12` = ledger fork rows over 12 turns; `forks around codex` = prompt-writing or output-relay forks next to codex rows.

| run | mode | model | wall min | turns main/all | $ dedup | $ codex | misses | tests | commits | JS lines | forks | forks >12 | forks around codex | base injected |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| b-fable-v2 | base only | fable-low | ≤51 (8 main turns) | 8/22 | 1.94 | – | 1 | 19 | 4 | 565 | 1 | 0 | – | yes |
| b-opus-v2 | base only | opus-low | ≤51 (8 main turns) | 8/31 | 1.98 | – | 1 | 56 | 5 | 1041 | 1 | 0 | – | yes |
| b-std-opus | base + pipeline standard | opus-low | 73 | 48/169 | 12.35 | – | 1 | 67 | 8 | 1289 | 12 | 3 (21, 16, 13) | – | yes (pre-hard-rules text) |
| b-pipe-codex-opus | base + pipeline full + codex sol-luna | opus-low; sol critic/decision review; luna packages | 43 | 66/218 | 11.31 (session-cost) / 18.22 (pipeline-cost, codex rows joined) | sol 0.37, luna ≈0.17 | 1 | 33 | 12 | 1172 | 8 | 3 (13, 14, 15) | 0 | yes |
| research-luna2 | base + pipeline full + codex luna, B2CT-22116 to Gate D | opus-low; luna repo audit; fable critic/decision review | ~40 | 47/158 | 12.61 | luna ≈0.13 | 0 | – | – | – | 8 | 2 (17, 27) | 0 | yes |
| f-fable (ref) | forks | fable-low | 9 | 24/73 | 4.79 | – | 1 | 32 | 6 | 638 | | | | |
| f-opus (ref) | forks | opus-low | 47 | 21/73 | 4.16 | – | 1 | 53 | 5 | 911 | | | | |
| p-std-opus-v3 (ref) | pipeline standard | opus-low | 47 | 54/114 | 8.16 | – | 0 | 56 | 5 | 1128 | | | | |
| p-astra-opus (ref) | pipeline full + codex astra | opus-low | 36 | 66/221 | 14.72 | 0.35 | 1 | 49 | 5 | 1184 | | | | |
| research-22116 (ref) | pipeline full, cold researchers | opus-low | 24 | 42/125 | 8.11 | – | 1 | – | – | – | | | | |
| research-luna (ref, old envelope) | pipeline full + codex luna | opus-low | 43 | 77/169 | 12.94 | 0.18 | 0 | – | – | – | 9 | 2 | 2 | |

Note on b-pipe-codex-opus: `pipeline-cost.py` joins the sol rows to the wrong usage records (338K input, 164K output → $5.35 for one sol-high review); the codex ledger shows sol-medium 84K/1K and sol-high 91K/3.6K, i.e. $0.37 total. The 18.22 figure is therefore inflated; the session-cost 11.31 plus codex 0.54 is the number to use.

## Findings, round 2

- Base-only v2 vs references: b-fable-v2 1.94 (f-fable 4.79) with 19 tests vs 32; b-opus-v2 1.98 (f-opus 4.16) with 56 tests vs 53 and 1041 lines vs 911. Both made exactly one fork this time (round 1: b-opus made none) and stayed under 8 main turns, so the hard fork rules changed behaviour; opus now matches the forks reference on output at half the price, fable still writes the smallest suite.
- Luna2 envelope: zero forks around codex (round 1: two, prompt writer plus ledger close). Luna itself ≈$0.13 for a 2.5M-input repository audit; forks $7.45 (8 forks, 90 turns), cold agents $0.81, main $4.05; total 12.61 vs 8.11 (cold-researcher run) and 12.94 (old envelope). The envelope saving (~$1) was eaten by two long forks: evidence-audit 17 turns and decision evidence+fix 27 turns ($2.30 alone).
- b-pipe-codex: sol critic + sol-high decision review $0.37, seven luna packages ≈$0.17 (one package, 6+7, fell back to an opus fork of 13 turns, $1.08); zero forks around codex; 66 main turns outside ledger rows ($5.26): the main session wrote every prompt file and ledger row itself as the envelope prescribes, and that inline work is now the biggest single cost. Total 11.31 + 0.54 codex vs p-astra-opus 14.72.
- b-std-opus vs p-std-opus-v3: 12.35 vs 8.16 with 67 tests vs 56. Dearer because: `0-start setup+health` ran 33 main turns inline ($2.34, the harness gate done by the main session instead of a fork), 169 total turns against the standard ceiling of 120, three forks over 12 turns (WP1-3 21, WP6 16, WP5 13), and both a closure-check fork (11) and a report fork (11) where the table allows one round. Fork count 12 stays under the 14 ceiling.
- Rule violations: no heavy agent read code in any run (critics 3 calls on documents, sol reviews on documents only); no relay forks around codex in the three codex runs; inline 3+ call work by the main session in b-std-opus (33-turn setup) and b-pipe-codex-opus (66 unattributed main turns, prompt files and ledger); forks over 12 turns in all three pipeline runs (2-3 each).
- research-luna2: harness gate passed (VPN, Atlassian MCP, GitLab MCP, `codex mcp list`, repo list); Sources `wanted, unavailable`: `timeout` binary absent (use `gtimeout`), cold workflow researchers cannot see MCP (reads went to forks by rule), external CI templates not in repo, real-environment CompID inventory unread, !551/!717 pipeline job state not fetched. Gate D passed: critic raised the class to 5; decision = a stacked A → A+B → A+B+C MR chain instead of three separate MRs, order C3 → C1 → C2/C4 → demux switch, hard precondition `FIXFORGE_FIX_VENUE` under `fix-auth:` in every environment plus a DB snapshot before the first deploy. No Jira or GitLab writes.
