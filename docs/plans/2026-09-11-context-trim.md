# Context trim: lean main session, heavy work in agents

Plan for the session plugin (0.9.1 to 0.10.0) and the user config. Date 2026-09-11, revised
after the critique in `reviews/2026-09-11-context-trim-critique.md`.
Inputs: `$CLAUDE_JOB_DIR/tmp/baseline-breakdown.md`, `desc-inventory.md`,
`context-decisions.en.md`, the M1/M2 measurements below (`$CLAUDE_JOB_DIR/tmp/m-M1.jsonl`,
`m-M2.jsonl`, `m-M1.txt`, `m-M2.txt`).

## 1. Goal and numbers

All numbers below are harness tokens (what `/context` and the JSONL usage report). Rows marked
"estimate" are chars/4 x 1.4, the calibration measured today (session:ask: 97 by chars/4, 140
by `/context`).

Measured sonnet start in `~/projects/empty-context-test` (first request, prompt `hi`):

| state | total | System tools | agents | memory | skills | messages |
|---|---|---|---|---|---|---|
| original baseline (morning) | 56.9K | 32.6K | 1.8K | 1.9K | 3.3K | 7.1K |
| M1: today's user-level changes plus per-project deny of Artifact and DesignSync | 33.0K | 13.7K | 1.6K | 1.8K | 0.9K | 4.8K |
| M2: M1 plus `code-review` set to `name-only` | 32.8K | 13.9K | 1.6K | 1.8K | 0.65K | 5.3K |

M1 is the baseline for this plan. M2 shows what `name-only` does: the skill keeps its name in
the listing and loses its description (skills line 915 to 650, so a `name-only` entry costs
about 10-20 tokens instead of about 270 for `code-review`).

Target after this plan, derived from M1:

| change | tokens | source |
|---|---|---|
| description trims (2a) | -0.6K | estimate: 1030 to 590 by chars/4, x1.4 |
| six new agents in the listing (2c) | +0.5K to +0.6K | estimate: six descriptions 40-70 each plus name, model and tool-list lines about 25 each |
| skills preloaded into agents via `name-only` (2c) | +0.1K at most | measured M2: 10-20 per skill, six skills |
| expected start | 33.0K, accept 32.5K-34.0K | |

Rollback rule: if the verification start (section 3, step 1) exceeds 34.0K (M1 + 1K), revert
the six agent files and re-measure; the trims and the base note stay.

The permission model only narrows: a user-level or project-level deny removes a tool from every
subagent too (measured), and the `--tools` launch whitelist cuts subagents as well (measured).
Decision taken today: no user-level deny of Artifact and DesignSync. Every directory under
`~/projects` (25 today) has `.claude/settings.local.json` with `permissions.deny: ["Artifact",
"DesignSync"]`; git ignores that file in every repo. The two artifact agents work in a project
only after the user removes those two entries from that project's local file and starts a new
session (a deny is read at start; whether a running session picks up the change is being
measured separately and goes into the README toggle text).

Telemetry: the plan sets `DISABLE_TELEMETRY` nowhere. A project may set
`"env": {"DISABLE_TELEMETRY": "1"}` in its local settings for another -8.5K, at the price of
Monitor, PushNotification, SendUserFile and Remote Control (measured: Monitor is not offered at
all, `ToolSearch select:Monitor` returns no match); the keep-warm in such a project has to be a
background Bash sleep.

## 2. Changes

### 2a. Trim agent and skill descriptions (session plugin)

Files: `plugins/session/agents/*.md`, `plugins/session/skills/ask/SKILL.md`. New texts are the
proposals in `desc-inventory.md`, section "(a) Proposed descriptions"; copy them verbatim.
Mechanics that leave a description move into the agent body, nothing is lost.

| file | now (chars/4) | target (chars/4) | max accepted |
|---|---|---|---|
| agents/codex-proxy.md | 344 | 90 | 100 |
| agents/pool-proxy.md | 132 | 60 | 70 |
| agents/stage-reviewer.md | 108 | 60 | 70 |
| agents/stage-critic.md | 72 | 50 | 60 |
| agents/waiter.md | 67 | 50 | 60 |
| agents/stage-author.md | 62 | 45 | 55 |
| agents/stage-researcher.md | 60 | 45 | 55 |
| agents/stage-executor.md | 54 | 40 | 50 |
| skills/ask/SKILL.md | 97 | 70 | 80 |

Kept in the listing on purpose: `pool-proxy` (pool mode is unstable but launched by its skill
and needs the agent), `spec-critic` (user file, 50 tokens, the user's own critic for design
documents; stage-critic serves the pipeline, not the same input). Recorded so the inventory's
"delete" suggestions are not silently dropped. A separate `agents-heavy` plugin was considered
and rejected: one more marketplace entry to keep in sync for about 0.5K of listing.

Outside the plugin, same rule, separate commits: `user-prefs` Explore (81 to 35, repo
`~/projects/claude-settings`), `~/.claude/skills/plannotator/SKILL.md` (85 to 50, installer
copy, may be overwritten by the next plannotator install).

Acceptance: a `python3` count asserts each file's description is at or under its "max accepted"
column (chars/4); each trimmed description still names the trigger, the launch form (Workflow,
agentType, model and effort where pinned) and the tool limits; the moved sentences are found in
the agent body by grep.

### 2b. Hide user-only skills from the model

`disable-model-invocation: true` is already set on base, pipeline, review, codex,
pool-workflow-unstable, pool-unstable, pool-stop-unstable and reset-counter (set today,
uncommitted). `ask` stays model-invocable by design.

Acceptance: `grep -L disable-model-invocation plugins/session/skills/*/SKILL.md` prints only
`plugins/session/skills/ask/SKILL.md`.

### 2c. New agents in `plugins/session/agents/`

Frontmatter from `desc-inventory.md`, section "New agents"; description under 70 tokens
(chars/4), model and effort explicit, tools the exact minimum. Skeleton source for the body:
`agents/stage-researcher.md` (role line, inputs by path, output by path, return spec, BLOCKED
rule, output style).

| agent | model / effort | tools | expected set in the agent JSONL | skills | label prefix | return, last line |
|---|---|---|---|---|---|---|
| artifact-publisher | opus / medium | Artifact, Read, Write, Bash | the four plus Grep, Glob | artifact-design, artifact-capabilities | `ops-me-artifact-<job>` | `URL: <url>` plus at most 40 words |
| artifact-designer | opus / medium | Artifact, DesignSync, Read, Write, Bash | the five plus Grep, Glob | design, artifact-design, artifact-diagramming, artifact-capabilities, dataviz | `ops-me-artifact-<job>` | `URL: <url>` plus at most 40 words |
| web-researcher | sonnet / medium | WebFetch, WebSearch, Read, Write | the four plus Grep, Glob | none | `son-me-web-<job>` | `FILE: <path>` then a digest of at most 600 words with sources |
| code-reviewer | sonnet / high | Read, Grep, Glob, Bash | the four | code-review | `son-hi-review-<job>` | findings `file:line severity text`, at most 300 words, or `CLEAN` |
| simplifier | sonnet / medium | Read, Edit, Bash | the three plus Grep, Glob | simplify | `son-me-simplify-<job>` | diff summary per file, at most 150 words |
| security-reviewer | sonnet / high | Read, Grep, Bash | the three plus Glob | security-review | `son-hi-security-<job>` | findings `file:line severity text`, at most 300 words, or `CLEAN` |

Grep and Glob ride along with Read in subagents (measured today: a whitelist of Read gave Read,
Grep, Glob). The "expected set" column is what the acceptance compares against.

Skills preload, first step of 2c: every skill above except `code-review` is `off` in the user
`skillOverrides`. One check before writing the agents: an agent with `skills: simplify` launched
from a test session; read its JSONL for the skill body. If absent, set those skills to
`name-only` in `~/.claude/settings.json` (M2: about 10-20 tokens each in the main listing,
description dropped) and re-check; if still absent, copy the needed instructions into the agent
body and drop the `skills:` line.

Every body ends with the same three lines: the return spec from the table, "at most N words, no
file contents, no raw logs", and "On a permission denial stop at once and return BLOCKED:
<action>". No polling, no Bash call over 120 s. Reviewers get the diff by path or run `git diff`
themselves; simplifier edits only the files the caller names.

Acceptance: after the reinstall (2f) a fresh session lists the six agents (`/agents` or the
agent listing in the first-turn attachments); `web-researcher`, `code-reviewer`, `simplifier`
and `security-reviewer` each launched once through `Workflow` from a sonnet test session in
`~/projects/empty-context-test` return the last line of the table, and the agent JSONL shows the
expected tool set and the preloaded skill body. The two artifact agents get a dry check only
(frontmatter parses, present in the listing): Artifact is denied in every project by the local
file, so they cannot be smoke-tested without lifting the deny.

### 2d. Base skill note

File: `plugins/session/base/BASE.md` (source; `base/split.sh` regenerates
`skills/base/SKILL.md`; never edit SKILL.md by hand). One paragraph in the section "Downscale
and upscale of intelligence", after the table:

> Heavy tools live in agents, not in the main session: web pages through `web-researcher`
> (`son-me-web-<job>`), a diff review through `code-reviewer` (`son-hi-review-<job>`), cleanup
> passes through `simplifier` (`son-me-simplify-<job>`), a security pass through
> `security-reviewer` (`son-hi-security-<job>`), a published page through `artifact-publisher`
> or `artifact-designer` (`ops-me-artifact-<job>`). All are one-agent `Workflow` launches with
> `agentType: session:<name>`, explicit model and effort, inputs by path. The main session never
> calls WebFetch, WebSearch or Artifact itself. Artifact and DesignSync are denied per project in
> `.claude/settings.local.json`; an artifact job needs those two entries removed in that project
> and a new session.

Acceptance: `bash plugins/session/base/split.sh` runs clean, the paragraph appears in
`skills/base/SKILL.md`, the tests under `tests/` that parse the base still pass.

### 2e. Per-project deny of Artifact and DesignSync (done today)

Already applied: 25 directories under `~/projects`, each `.claude/settings.local.json` has
`permissions.deny` with `Artifact` and `DesignSync` (19 files created, 6 appended). No user-level
entry. Nothing left to edit here.

README addition next to the agent table, the toggle: "To publish an artifact from a project,
remove `Artifact` and `DesignSync` from that project's `.claude/settings.local.json`, start a
new session, launch `artifact-publisher` or `artifact-designer`, put the entries back. The deny
is read at session start" (amend with the hot-reload measurement once it is in).

Acceptance: `python3` over `~/projects/*/.claude/settings.local.json` finds both entries in
every file; M1 above already shows System tools 13.7K with no Artifact schema.

### 2f. Version bump, reinstall, commit

Order: 2c preload check, then 2a, 2c, 2d in one batch (disjoint files), review by a separate
agent, then the verification of section 3, then the bump and the commit with the measured
numbers, then the reinstall check.

`plugins/session/.claude-plugin/plugin.json`: version 0.10.0. README log line under the base
section, same style as the 0.9.1 line:

> 0.10.0: lean main session. Agent and skill descriptions trimmed (targets in the plan);
> reset-counter hidden from the model; six heavy-work agents (artifact-publisher,
> artifact-designer, web-researcher, code-reviewer, simplifier, security-reviewer) launched as
> one-agent workflows; the base names them. Artifact and DesignSync are denied per project.

Reinstall sequence (directory marketplace copies to the cache, measured today):
`claude plugin marketplace update claude-session` then
`claude plugin install session@claude-session --scope user`; then
`grep version ~/.claude/plugins/cache/claude-session/session/0.10.0/.claude-plugin/plugin.json`
reads 0.10.0 and a fresh session shows the six agents.

Commit message draft (no push; numbers filled from section 3 before committing):

```
session 0.10.0: lean main session, heavy tools moved into agents

Descriptions of the plugin agents and of session:ask trimmed; reset-counter
hidden from the model. Six new agents for work the main session should not
carry: artifact-publisher, artifact-designer, web-researcher, code-reviewer,
simplifier, security-reviewer. The base skill names them and routes web,
review, cleanup and artifact work through them.

Measured start context of a sonnet main session in an empty project: 56.9K
this morning, 33.0K before this change (user-level denies, skills off,
per-project deny of Artifact and DesignSync), <measured> after.
```

Durable backups: copy `$CLAUDE_JOB_DIR/tmp/user-config-backup/` and the M1/M2 files to
`~/projects/claude-session/docs/plans/artifacts/2026-09-11-context-trim/` before the job ends.

## 3. Verification

1. Start size: one sonnet tmux session in `~/projects/empty-context-test`, project settings
   `{"model":"sonnet"}`, prompt `hi`, first request usage from the JSONL; accept 32.5K-34.0K;
   `/context` capture at 220x80 for the category lines; rollback rule from section 1.
2. Agent smoke: from a sonnet test session, one `Workflow` each with `web-researcher` (question
   with a known answer), `code-reviewer` (small diff in a scratch git repo), `simplifier` (one
   named file with an obvious duplicate), `security-reviewer` (same scratch repo). Check the
   last line against the 2c table, and in each agent JSONL the expected tool set and the
   preloaded skill body.
3. Reinstall: the sequence in 2f, `claude plugin list` shows `session 0.10.0`;
   `bash plugins/session/base/split.sh` idempotent.
4. Sizes: the `python3` check of 2a per file, plus the six new descriptions at or under 70.
5. README: names all six agents, the toggle text, the 0.10.0 line; no README text quotes a
   trimmed description verbatim.

Test sessions are interactive tmux sessions on sonnet, never `claude -p`.

## 4. Risks

- Skills preload against `skillOverrides: off` may fail; fallback `name-only` (measured cheap)
  or inlined text (costs tokens inside the agent only).
- README drift: three hand edits (agent table, toggle, log line); covered by verification 5.
- Agent listing grows by six entries (about +0.5K to +0.6K); net effect on the listing about
  zero after the trims; the rollback rule guards the total.
- The artifact toggle is manual per project; if it is needed often, revisit.
- `~/.claude/skills/plannotator/SKILL.md` is an installer copy; a plannotator update may restore
  the long description.
- Trimmed descriptions and new agents reach a session only after the bump and the reinstall
  sequence in 2f.
- The user has live sessions during the edits; plugin files are read at session start, so
  running sessions are unaffected; the user-level `skillOverrides` edit for `name-only`, if
  needed, is the only change a running session might see (unmeasured).
