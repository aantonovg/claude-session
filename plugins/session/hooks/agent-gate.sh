#!/bin/bash
# PreToolUse gate on Agent (and its old name Task). The base allows exactly one launch form through
# Agent: a fork, with subagent_type "fork" and a name "fork-<mod>-<eff>-<job>". Every other subagent
# type (a session:* helper, a user agent, general-purpose, Explore, Plan, the built-in guide) runs
# through the Workflow session:helper or session:batch, the only path that sets a helper's model
# and effort from the class table; an Agent call cannot set effort, so a direct launch would run on
# the session's own cell with no sign. The deny reason is what the model reads.
#
# SESSION_AGENT_GATE=off turns the gate off: an emergency switch, for instance if the agent() calls
# inside a workflow ever reach this hook (not seen so far; a workflow launches its agents itself,
# not through an Agent tool call of the model).

[ "${SESSION_AGENT_GATE:-on}" = off ] && exit 0
INPUT=$(cat)

deny() {  # $1 reason
  if command -v jq >/dev/null 2>&1; then
    jq -nc --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
    exit 0
  fi
  printf '%s\n' "$1" >&2
  exit 2
}

HOW='launch a helper through the Workflow session:helper by name (session:batch for many items); only a fork goes through Agent'

if command -v jq >/dev/null 2>&1; then
  tool=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
  type=$(printf '%s' "$INPUT" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null)
  name=$(printf '%s' "$INPUT" | jq -r '.tool_input.name // empty' 2>/dev/null)
else
  # No jq: a crude read of the flat fields; anything unreadable counts as "not a fork".
  field() { printf '%s' "$INPUT" | tr -d '\n' | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -n1; }
  tool=$(field tool_name); type=$(field subagent_type); name=$(field name)
fi

case "$tool" in Agent|Task) ;; *) exit 0 ;; esac

if [ "$type" != fork ]; then
  deny "session plugin: Agent with subagent_type \"${type:-general-purpose}\" is blocked; $HOW."
fi
case "$name" in
  fork-[a-z0-9]*-[a-z0-9]*-?*) exit 0 ;;
esac
deny "session plugin: a fork needs name \"fork-<mod>-<eff>-<job>\" with the main session's own cell (got \"$name\"); description starts the same way."
