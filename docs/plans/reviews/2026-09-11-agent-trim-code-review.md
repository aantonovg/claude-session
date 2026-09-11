# Code review: agent trim 0.10.2 (2026-09-11)

Scope: uncommitted diff against `docs/plans/2026-09-11-agent-trim.md` and its critique.

## High

1. **README still teaches the removed mechanism.** — `plugins/session/README.md:564` —
   "(\"Load these skills with the Skill tool before starting: …\" or \"No skills needed for this
   step.\")" contradicts `plugins/session/base/BASE.md:170` and `:338`, which now say "Read these
   skill files with the Read tool". The main session reads both; one of them is wrong. Fix: same
   wording in both, in this commit.

2. **The skill path has no resolution rule and the cache path carries the version.** —
   `plugins/session/base/BASE.md:170`, `:338` — the template says only `<absolute SKILL.md paths>`.
   Plugin skills live under `~/.claude/plugins/cache/claude-session/session/<version>/skills/<name>/SKILL.md`;
   `README.md:58` already states the cache is a copy rewritten on reinstall, so any path the main
   session memorises breaks at the next bump, silently (the agent's Read fails, it continues
   without the skill). `agents/codex-proxy.md` solves the same problem with
   `ls -d ~/.claude/plugins/cache/claude-session/session/*/bin | sort -V | tail -1`; the skill
   template has no equivalent. Safer wording for both files:
   "Read these skill files with the Read tool before starting, in this order: <absolute SKILL.md
   paths>. Resolve a plugin skill to the newest installed version
   (`ls -d ~/.claude/plugins/cache/<marketplace>/<plugin>/*/skills/<name>/SKILL.md | sort -V | tail -1`)
   and pass the resolved path, never a remembered one; a user skill is
   `~/.claude/skills/<name>/SKILL.md`. Ignore the YAML frontmatter at the top of the file and
   resolve any relative path inside it against the file's own directory. If a named file is
   missing, return `BLOCKED: <path>` instead of working without it. Follow each file's
   instructions in place of your default approach."

## Medium

3. **Read does not reproduce Skill-tool behaviour.** — `BASE.md:170` — the Skill tool strips
   frontmatter, resolves the skill's bundled files and accepts arguments; Read returns the raw
   file, so the agent also ingests `name:`, `description:`, `disable-model-invocation: true` and
   sees relative resource paths it cannot resolve. Not fatal for prose skills, fatal for a skill
   that ships scripts. Covered by the wording in item 2; state it once in BASE.md rather than in
   every launch prompt.

4. **README skills paragraph is stale.** — `plugins/session/README.md:35-38` — "Each agent names
   its skills in `skills:` (code-review, simplify, security-review, the artifact and design
   skills)" is false after the diff: only `agents/code-reviewer.md:7` keeps `skills: code-review`.
   The critique's item 12 sentence (re-adding a skill means re-adding the line) exists only in the
   0.10.2 log line at `README.md:48`, not here.

## Low

5. **Body target missed, documented.** — `agents/codex-proxy.md` is 6709 bytes against the plan's
   "at most 4K chars"; the plan's "Applied" section records the deviation with its reason. No
   action.

## Checks that pass

- Tool sets vs role: researcher `Bash, Read, Write` (git via Bash), executor `Bash, Read`,
  codex-proxy `Bash` only, artifact agents without Bash — each body states its BLOCKED path.
- codex-proxy writes no file with Write: the preamble goes through a Bash heredoc
  ("write it with a Bash heredoc to `$TMPDIR/codex-preamble-<name>.txt`"), the answer file is the
  wrapper's `-o`, the last line comes from `tail -n 1`; "Check the file exists with a shell test,
  never read it" and "Never read the output file" replace Read.
- codex-proxy keeps the header contract, model map, escalation preamble verbatim, the wrapper
  invocation, the two-line output block, `CODEX CLI ERROR (exit <code>)`,
  `BLOCKED: <the denied action>`, "No `run_in_background`, no `&` of your own".
- `skills/base/SKILL.md` body is byte-identical to `base/BASE.md` (`diff` of SKILL.md from line 6
  against BASE.md is empty).
- README agent table rows match every `tools:` line; version 0.10.2 in both
  `.claude-plugin/marketplace.json` and `plugins/session/.claude-plugin/plugin.json`.
- No `BLOCKED`, no-polling or return-cap rule lost: every agent body still carries all three
  (waiter keeps them at `agents/waiter.md:21,28`; the only deletion there is the "Details moved"
  line).

verdict: FAIL (2 high)
