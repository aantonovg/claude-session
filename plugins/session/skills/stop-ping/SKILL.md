---
name: stop-ping
description: Stop the keep-warm ping monitor of the current session (started by /session:base). Use when the user asks to stop pings.
disable-model-invocation: true
---

# Stop the keep-warm ping

Run exactly one Bash call:

```
sh "$(ls -d ~/.claude/plugins/cache/claude-session/session/*/monitors/stop-ping.sh | sort -V | tail -1)"
```

Then reply one line: `ping monitor stop requested, exits within 60 s`. No other output.
