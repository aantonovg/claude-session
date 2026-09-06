---
name: review
description: Skill for reviewing someone else's MR or PR; replaces the pipeline stages with a verification-first review (research, verification audit, verification delta, harness delta, threads, publish) and a re-review path for an MR revisited after the author's replies or fixes. Reads skills/pipeline/core.md first; does not need session:pipeline.
disable-model-invocation: true
---

# Pipeline: review of someone else's work

Loaded on top of the session base (injected at start). Task directory, ledger, cost principle, harness gate,
cold researcher rule and the Sources/Oracles blocks come from `../pipeline/core.md` (read
first); fork rules from the session base; the stages below mirror the pipeline's stages
1-7, gates keep their letters. The review checks whether the author understood
the task and whether the work is verified; findings come from runs, not from reading.

## Start (do this now)

0. Read `../pipeline/core.md` first. Then the pipeline Start steps, done here:
   1. The base already created the `ping` cron and answers pings; nothing to start here.
      Limit restart: `core.md`, "Ping and limit restart".
   2. Read `~/.claude/session-map.md` (fallback: `session-map.example.md` in the plugin,
      fable-opus only). Pick the pairing row the user named, else the default pairing of
      the account.
   5. Create the task directory and register it, one command:
      `D=~/.claude/projects/<encoded-cwd>/pipeline/<date>-<slug>; mkdir -p $D/evidence $D/reviews; P=$(dirname $(dirname $D)); echo $D > $P/pipeline/current; echo ${CLAUDE_SESSION_ID:-$(ls -t $P/*.jsonl | head -1 | xargs basename | sed 's/\.jsonl$//')} > $D/session`
      (`<encoded-cwd>` = the cwd with every character outside `A-Za-z0-9-` replaced by `-`).
1. Argument `lite`, `std`, `full` or `re` fixes the path. `re` is also the path when the
   MR already has threads by this user. Without an argument the path comes from the
   class; only when the class is unclear ask one question with `AskUserQuestion`,
   entirely in Russian, recommended option first (header «Глубина ревью»: «lite» —
   только факты и аудит верификации автора; «std» — плюс недостающие проверки, которые
   можно прогнать существующими средствами; «full» — плюс сценарии для утверждений без
   тестов, с негативным контролем).
2. Class by diff size and blast radius, not by ticket type: lines changed, files touched,
   shared modules or public interfaces touched, migrations, config or infra changes.
   Class 1-2 → lite, 3-4 → std, 5 or a migration or an infra change → full.
3. Reply with one line: "Pipeline review: <path>, class <n>; verification-first." Main
   session for review work: opus-low. Every `ledger.jsonl` row carries `"review": "<path>"`.

## Stages (replace pipeline stages 1-7)

Harness gate (`core.md`, same rule): before stage 1 one fork health-checks every
MCP server, host, docker daemon, CLI binary and skill the review needs (codex axis on:
`codex -p <profile> mcp list` too); any wanted tool unavailable → the `wanted,
unavailable` lines go into the `Sources` block, one chat line per tool with the exact
failure, and the turn ends; every following `ping` re-runs the check silently and resumes
from the last ledger row when the tools are back, else adds `still unavailable: <list>`;
"continue without <tool>" from the user overrides. MCP reads are fork jobs, never cold
researchers (measured 2026-09-06: workflow agents do not see the session's MCP servers
under the corporate harness; a fork does).

**1. Research → Gate R** (every path). One short fork (≤ 6 turns) fetches once through
MCP, straight into `evidence/raw/`, no relay: the ticket intent, the MR description and
the author's claims, CI status and job results, the changed-file list with line counts,
the existing threads; it writes `evidence/EB-1.md` (≤ 80 lines, pointers). A cold
`session:stage-researcher` (sonnet-low, label `son-lo-research`, a one-agent `Workflow`,
session base "Launch forms") takes only repository, git history and docs questions. Judgment (what the task really asked, where the claims and the intent
disagree) is one short fork (≤ 6 turns) that writes `Framing` and the `Ledger`, whose
first lines are the `Sources` block: `used:` every source class that produced evidence
(MCP tools by name, repo paths, CI logs, docs, skills loaded); `wanted, unavailable:`
each source that would have answered a question but could not be used, one line, the
source and the harness reason in ≤ 8 words. Gate R passes only when the block is present
and the intent, the claims and the changed surface are written with pointers; the
Gate R status line in chat quotes the `wanted, unavailable` lines verbatim (or "none").
The block stays unpublished (`reviews/harness.md` and chat only).

**2. Verification audit → Gate D.** Replaces critic and decision. A low fork reads what
the author verified (tests in the MR, CI jobs, described manual checks) against the
intent and writes the `Review contract` into `task.md`: one row per claim → `existing
oracle` (test or job that proves it, with its result) / `missing oracle` (provable, not
proven) / `no possible oracle`; plus the list of files with no possible oracle. Full
path only: one cold `session:stage-reviewer` critiques the contract (reviewer-debugger
cell, budget 3 calls at high, 5 at medium, label `<mod>-<eff>-contract-review`). Gate D
passes when every claim has a row.

**3. Verification delta → Gate V.** Replaces the verification plan. A low fork plans
the missing oracles only: check → tool → command → pass/fail criterion; never re-plans
what the author already proved. Its first lines are the `Oracles` block: `planned:` each
verifier type with its health-check result (tests, scenarios, static checks, docker, CI
job, MCP read, CLI, skill); `wanted, unconfirmed:` each verifier that would strengthen a
claim but whose presence could not be confirmed (docker, MCP, CLI binary, skill, access,
VPN), one line with the reason in ≤ 8 words. Gate V passes only when the block is
present; the Gate V status line in chat quotes the `wanted, unconfirmed` lines verbatim
(or "none"); the block stays unpublished. Lite path: no delta stage, the contract's
`missing oracle` rows become threads directly and the `Oracles` block (2 lines) goes
into the contract.

**4. Harness delta and run → Gate I.** Replaces implementation. A low fork checks out
the MR branch in a git worktree under `$TMPDIR` (never the user's working tree),
implements the missing tests, scenarios or checks as low forks (one per oracle), runs
them, and records results in the ledger. Full path: negative controls calibrated, two
runs. Nothing is pushed to the author's branch.

**5. Findings → threads.** Two kinds of failure, kept apart. An MR finding: a check
that fails because of the MR (wrong code, a false statement in the description or a
commit, a test the MR claims and lacks, a scenario that fails on the MR branch and
passes on the base branch). A harness failure: our side (MCP, VPN, docker, a missing
binary, access denied, a missing skill, a tool version mismatch, the sandbox). Harness
failures go to `reviews/harness.md` and the chat report only. Before a finding is
written, a low fork runs the same check on the base branch (or reads the same statement
in the description); a failure that also occurs on the base branch is not a finding. A
finding is written only when its evidence reproduces on the author's side (their CI,
their tests, their reading of the description).
A fork writes `reviews/threads.md` from confirmed MR findings only, severity `critical`
or `important` (`minor` findings are not written and never posted). One finding is one
entry, never grouped with another; each entry carries its file and line when it has
one. One thread is at most 3 lines: line 1 names the finding (≤ 20 words), line 2 the
evidence as the minimal way the problem shows, a command or a file:line (≤ 20 words),
never a description of the checking procedure, line 3 the fix (≤ 20 words); no
headings, no bullets, no preamble. Successful checks are silent everywhere in the MR.
A claim that cannot be verified with the available oracles: review-full → a diff-scoped
read on opus-low (terra-high in terra executor mode) of the files behind that claim,
input = the diff of those files and nothing else, the only code reading in a review,
producing threads the same way; review-lite and review-std → skipped silently, no
mention in threads or notes, recorded only in `reviews/harness.md` and the chat report.

**6. Closure check → Gate F.** A low fork checks: every claim has a row, every missing
oracle a run or a thread, every unverifiable claim its read (full) or its
`reviews/harness.md` line (lite, std); last line `DONE severity=<…>`.

**7. Publish → Gate C.** One finding = one draft note = one resolvable thread. A
finding with a file and line is a draft note with that `position`
(`mcp__gitlab__create_draft_note`); a finding without a line (description, commit
message, CI config claim) is a draft note without `position`, one per finding, which
publishes as an MR-level discussion thread; never a plain non-resolvable note, never
two findings in one note. Each note is the 3 lines from `threads.md` verbatim. The
summary note is the only note that is not a thread, at most 4 lines: one line per
finding (≤ 15 words, pointing to its thread) and one verdict line; no list of what was
verified or not verified, no oracles, no claims table. With no findings the summary
note is omitted and the MR is approved. Total published text per MR ≤ 1/3 of the
diff's line count and never more than 30 lines. Nothing about how the review was done
is published: no path, class, ceilings, forks, agents, harness, "proven by runs", model
names, skill names, ledger, worktree, checks that passed, checks that could not run;
that text lives only in `reviews/closure.md`, `reviews/harness.md` and the chat
report. Every message is posted through the tool as a draft note, in plain
professional English; the harness delta is offered as a patch attached to the note.
The draft set is submitted, and "request changes" is used, only on the user's explicit
word or by the user in the UI. When no `critical` or `important` finding remains (only
`minor` ones, or none), the session approves the MR. The chat report is in Russian: what the author claimed, what
was proven, what the review added, what was found, what stays unverified and the
harness failures. Remove `pipeline/current`.

## Re-review (`/session:review re`)

An MR revisited after the author's replies or fixes: the `re-review` column below. Per
thread, one at a time: fixed with evidence (the earlier failing check now passes, rerun
once) or answered with an argument → resolve it; still open → one reply. Fix commits
are verified only by rerunning the existing harness delta and CI. Approve when nothing
stays open.

## Paths: what each one skips

| step | review-lite (class 1-2) | review-std (class 3-4) | review-full (class 5, migration, infra) | re-review |
|---|---|---|---|---|
| research | cold researcher only, 1 judgment fork | cold researcher, 1 judgment fork | cold researcher, ≤ 2 judgment forks | threads + new commits, 1 cold researcher or 1 fork |
| verification audit | fork | fork | fork + cold contract critique (3 calls at high) | – (per-thread check) |
| `Sources` / `Oracles` blocks | 2 lines each, in ledger and contract | full lists | full lists | 2 lines each |
| verification delta | – (missing oracles → threads) | fork, only oracles existing tooling can run | fork, plus scenarios for claims without tests | – |
| harness delta + run | – | 1 fork per oracle, one run | 1 fork per oracle, negative controls, two runs | rerun existing delta + CI once |
| CI and diff stat | read from evidence | read from evidence | read from evidence | read from evidence |
| unverifiable claims | – (silent skip, harness.md only) | – (silent skip, harness.md only) | diff-scoped opus-low read | – |
| threads | findings from failing or missing oracles | plus findings from runs | plus findings from scenarios and reads | resolve or one reply per thread |
| closure check | – (main reads the contract status) | 1 round | 1 round | – |
| publish | draft notes; submit on the user's word; approve when clean | same | same | resolve threads, approve when nothing open |
| ceilings | ≤ 3 forks, ≤ 40 turns, 1 cold agent | ≤ 10 forks, ≤ 100 turns, 1 cold agent | ≤ 18 forks, ≤ 180 turns, 2 cold agents | ≤ 2 forks, ≤ 25 turns, 0-1 cold agent |

## Forbidden

- Everything `core.md` and the session base forbid, plus the pipeline's Forbidden list
  (`../pipeline/SKILL.md`). No medium or high agent in a review except the full
  path's contract critique; no reading of the diff except the full path's read of the
  files behind an unverifiable claim, on opus-low only; no reading of the code base to
  "understand" the MR.
- No checkout into the user's working tree, no push, no commit to the author's branch,
  no draft submitted and no "request changes" before the user's word.
- No step the path row marks `–`, no count over the path's ceiling.
- Fork prompts for `threads.md` and the note carry the caps (words per line, lines per
  thread, lines per note, the 30-line total), the two-kinds rule, "one note per
  finding", "findings only: no verified / not verified lists, no procedure"; the main
  session rejects a `threads.md` or a note over the cap, with grouped findings or with
  verification text and sends it back once.
Reference: `skills/pipeline/core.md` (shared rules, files), `skills/pipeline/SKILL.md`
(stages, Forbidden), `plugins/session/README.md` (classes, measurements).
