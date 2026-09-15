---
name: resume-ping
description: Resume the keep-warm ping monitor of the current session after /session:stop-ping. Use when the user asks to resume pings.
disable-model-invocation: true
---

# Resume the keep-warm ping

Run exactly one Bash call:

```
sh "$(ls -d ~/.claude/plugins/cache/claude-session/session/*/monitors/resume-ping.sh | sort -V | tail -1)"
```

Then reply one line: `ping resumed`. No other output. Next ping after one full interval (57 min).
