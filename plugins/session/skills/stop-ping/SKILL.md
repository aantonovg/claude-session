---
name: stop-ping
description: Pause the keep-warm ping monitor of the current session (started by /session:base). Use when the user asks to stop or pause pings.
disable-model-invocation: true
---

# Pause the keep-warm ping

Run exactly one Bash call:

```
sh "$(ls -d ~/.claude/plugins/cache/claude-session/session/*/monitors/stop-ping.sh | sort -V | tail -1)"
```

Then reply one line: `ping paused`. No other output. `/session:resume-ping` resumes.
