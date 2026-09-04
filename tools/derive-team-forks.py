#!/usr/bin/env python3
"""Regenerate skills/team-forks/SKILL.md from skills/team/SKILL.md."""
import pathlib, sys
root = pathlib.Path(__file__).resolve().parent.parent / 'plugins' / 'session' / 'skills'
s = (root / 'team' / 'SKILL.md').read_text()
reps = [
 ("name: team\n", "name: team-forks\n"),
 ("description: Session mode 3, main session plus named tmux teammates on their own models and efforts. Light sub-mode spawns one teammate per model+effort combo of the selection-map row, full sub-mode one per role. Also restores a team parked by session:team-compact (menu of recent compacts, or a directory argument). No forks, no plain subagents, no Workflow. Invoke at the start of a session for big tasks with review/fix cycles and mixed models.",
  "description: Session mode 5, team plus forks. Named tmux teammates on their own models and efforts (light: one per model+effort combo, full: one per role), and both the main session and every teammate hand any job with 3+ tool calls or 3K+ input tokens to a fork subagent. Also restores a team parked by session:team-compact. No plain subagents, no Workflow. Invoke at the start of a session for the biggest tasks."),
 ("# Mode: team\n", "# Mode: team-forks\n"),
 ("merges results.\n\nArgument (optional)", "merges results. On top of mode team, every context (main and teammates) keeps itself\nsmall by running heavy work in forks: a fork inherits its parent's cached prefix, so\nit costs almost nothing to start and its tool calls never land in the parent context.\n\nArgument (optional)"),
 ("Rules: keep your context for coordination and for your roles; do not spawn agents\n(no forks, no subagents, no Workflow); never run /model, /effort or /compact yourself;\non a permission denial stop and return BLOCKED: <action>.",
  "Rules: keep your own context for coordination; run every job with 3+ tool calls or\n3K+ tokens of input (file sweeps, tests, searches, verification) in a fork\n(Agent tool, subagent_type \"fork\"; parallel forks in one message; the fork's prompt\nstarts with its role and ends with a return format of at most N words, no dumps;\nevery wait inside a fork stays under 3 minutes per call). Never spawn plain subagents\nor Workflow; never run /model, /effort or /compact yourself; on a permission denial\nstop and return BLOCKED: <action>."),
 ("- Extra teammates mid-task only after agreeing with the user.",
  "- Extra teammates mid-task only after agreeing with the user.\n- The main session forks too: any job of its own with 3+ tool calls or 3K+ input goes\n  to a fork with a role line first and a return format last; small things it does\n  itself. Review and fix are always different forks.\n- Outside plan mode a fork may use any Bash; in plan mode forks avoid `$var`, `$(…)`\n  and loops (they prompt the user there)."),
 ("- No plain subagents and no `Workflow`, for the main session and for the teammates.\n  Forks are allowed only in the recon of step 2, before the team exists; once the team\n  is up, no forks either (that is mode team-forks).",
  "- No plain subagents (`general-purpose`, `Explore`, custom agent types) and no\n  `Workflow`, for the main session and for the teammates. Forks only."),
]
for a, b in reps:
    if a not in s:
        sys.exit(f"anchor not found: {a[:60]!r}")
    s = s.replace(a, b, 1)
(root / 'team-forks' / 'SKILL.md').write_text(s)
print("team-forks regenerated")
