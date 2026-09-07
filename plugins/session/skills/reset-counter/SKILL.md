---
name: reset-counter
description: "Clear the statusline mode counters for this session. Use after a rewind dropped a session skill out of context, or whenever the statusline segment names modes that are no longer loaded."
---

# Reset the mode counters

The statusline segment after `project:branch` lists the `session:*` skills recorded
for this session. The record is written when a skill is invoked and cleared on
compaction and session start, but a rewind removes a skill from context without any
event, so the segment can outlive the skill it names.

Invoking this skill clears that record: the hook wipes
`~/.claude/session-modes/<session_id>.json` and the segment disappears at the next
statusline refresh.

On this turn: reply with one line naming the modes that are still actually loaded in
this session (for example `base, codex +astra`), or `none` when the context holds no
session skill. Re-invoke the ones that are still wanted. Change nothing else.
