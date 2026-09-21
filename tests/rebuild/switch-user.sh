#!/bin/bash
# The user-level half of part 9, as a script instead of a hand edit.
#
#   tests/rebuild/switch-user.sh <claude-dir>
#
# <claude-dir> is the copy that tests/rebuild/user-copy.sh built while the branch is being built,
# and the real ~/.claude at the switch of section 6 — the same layout either way. Nothing under the
# real ~/.claude is touched while the branch is built; this script is the only writer at the switch.
#
# Every patch is found by pattern, never by line number: the numbers in the plan came from the
# research and are hints. For every patch either the old pattern or the new text must be present; a
# file where neither is found fails the run. So the first run can not pass by matching nothing, and
# the second run changes nothing (idempotent: a patch whose new text already stands is counted as
# done, and a file holding both is a failure, because a half-applied patch is neither state).
#
# The patches, with their reason. stale-ok: every old pattern below is a name this script removes
# from the user level, so the lines that carry one are the deletion, never a live reference; the
# same marker stands over each patch call for the same reason.
#   skills/tmux-sessions       the waiting carrier is a role of session:role now
#   skills/russian-plannotator the translation workflow is a role of session:role now
#   skills/harness-cost        the two rows are measured costs of agents that no longer exist; they
#                              go, and a new number goes in only after a fresh measurement (idea 8.14)
#   skills/transcripts-jsonl   "every stage agentType prefixed session:" is false for a tool plugin
#                              agent and becomes "prefixed by a plugin name"
#   statusline.sh              the mode file keeps its path, its keys change: the consumer read
#                              .pipeline and .review, and hooks/modes.sh writes .process (U9)
#   projects/<enc>/memory      the index entry and the two memory files that instruct a translation
# Credential rule: no keychain entry, login state or ~/.claude.json is read, listed or copied.

set -u

MAIN=${CLAUDE_MAIN_CHECKOUT:-/Users/aleksandr.antonov/projects/claude-session}
ENC=$(printf '%s' "$MAIN" | tr '/.' '--')
MEM=projects/$ENC/memory

DIR=${1:-}
if [ -z "$DIR" ]; then
  echo "switch-user: no argument; want <claude-dir> (the copy, or ~/.claude at the switch)" >&2
  exit 2
fi
if [ ! -d "$DIR" ]; then
  echo "switch-user: FAIL no such directory: $DIR" >&2
  exit 1
fi

N=0; DONE=0; FAILS=0
ok() { N=$((N + 1)); }
applied() { N=$((N + 1)); DONE=$((DONE + 1)); }
fail() { echo "FAIL $1"; FAILS=$((FAILS + 1)); }

patch() {  # $1 relative path, $2 label, $3 old literal, $4 new literal, $5 perl expression
  local rel=$1 label=$2 old=$3 new=$4 expr=$5
  local f=$DIR/$rel
  if [ ! -f "$f" ]; then fail "$label: no file $rel under $DIR"; return; fi
  if grep -qF -- "$new" "$f"; then
    if grep -qF -- "$old" "$f"; then
      fail "$label: both the old pattern and the new text stand in $rel"
    else
      ok
    fi
    return
  fi
  if ! grep -qF -- "$old" "$f"; then
    fail "$label: neither the old pattern nor the new text is in $rel"
    return
  fi
  if ! perl -0777 -i -pe "$expr" "$f"; then fail "$label: perl failed on $rel"; return; fi
  if ! grep -qF -- "$new" "$f"; then fail "$label: the new text is missing from $rel after the patch"; return; fi
  if grep -qF -- "$old" "$f"; then fail "$label: the old pattern still stands in $rel after the patch"; return; fi
  applied
}

# ---- 1. the waiting carrier ---- stale-ok: the old name is what this patch removes
patch skills/tmux-sessions/SKILL.md 'tmux-sessions waiter' \
  'session:waiter' \
  '`session:role` with `role: waiter`' \
  's{launches `session:waiter` as a one-agent `Workflow`, sonnet, effort low, label `son-lo-wait-<job>`}{launches the named workflow `session:role` with `role: waiter`, class and submodes from the session base, label `<mod>-<eff>-wait-<job>`}'

# ---- 2. the translation workflow ---- stale-ok: the old name is what this patch removes
patch skills/russian-plannotator/SKILL.md 'russian-plannotator translate' \
  'session:translate-ru' \
  'named workflow `session:role`' \
  's{named workflow `session:translate-ru`, args `\{ file: <absolute path> \}`}{named workflow `session:role`, args `{ role: "translator", in: [<absolute path>], ask: "translate this file into Russian", out: <the same directory>/<name>_ru.<ext> }`}'

# ---- 3. the measured rows of two agents that no longer exist ---- stale-ok: the rows name them
patch skills/harness-cost/SKILL.md 'harness-cost rows' \
  'session:stage-executor' \
  'only after a fresh measurement' \
  's{^\| `session:stage-executor` \| 10,446 \|\n\| `session:stage-reviewer` \| 7,966 \|\n}{}m;
   s{^(\| blank instructions \| 3,177 \|)$}{$1\n\nThe two measured rows of the 0.15 agents are gone with those agents: a number per agent type goes back in only after a fresh measurement.}m'

# ---- 4. the agentType predicate that is false for a tool plugin ----
patch skills/transcripts-jsonl/SKILL.md 'transcripts-jsonl predicate' \
  'every stage `agentType` prefixed `session:`' \
  'every stage `agentType` prefixed by a plugin name' \
  's{every stage `agentType` prefixed `session:`}{every stage `agentType` prefixed by a plugin name}'

# ---- 5. the statusline consumer: the keys of the mode file, and the writer it names ----
# stale-ok: the old keys and the old writer path are what these two patches remove
patch statusline.sh 'statusline mode keys' \
  '[.base, .codex, .pipeline, .review]' \
  '[.base, .codex, .process]' \
  's{\[\.base, \.codex, \.pipeline, \.review\]}{[.base, .codex, .process]}'
patch statusline.sh 'statusline writer name' \
  'hooks/session-modes.sh' \
  "hooks/modes.sh" \
  's{hooks/session-modes\.sh}{hooks/modes.sh}g'

# ---- 6. the memory: the index entry and the two files that instruct a translation ----
# stale-ok: the old workflow name is what this patch removes
patch "$MEM/MEMORY.md" 'memory index entry' \
  'session:translate-ru' \
  'session:role with role translator' \
  's{\[Translation: session:translate-ru workflow for files, fork for conversation\]}{[Translation: session:role with role translator for files, fork for conversation]};
   s{named workflow session:translate-ru \(size-picked slot\) when the source is on disk}{named workflow session:role with role translator (slot picked by the size argument) when the source is on disk}'

# stale-ok: the old workflow name is what this patch removes
patch "$MEM/feedback-translation-cold-agent.md" 'memory translation entry' \
  'session:translate-ru' \
  '`session:role` with `role: translator`' \
  's{the session:translate-ru named workflow}{the session:role workflow with role translator}g;
   s{`plugins/session/workflows/translate-ru\.js` in the session plugin, args `\{file, out\?, class\?, submodes\?\}`}{args `{role, in, ask, out, class?, submodes?, size?}`}g;
   s{a haiku `size-estimator` measures the file, then a `translator` agent runs on the slot picked by size \(under 1000 tokens: main-model slot; 1000-2000: opus slot; over 2000: sonnet slot\)}{the translator role runs on the opus slot of the class, one slot down at `size: large`}g;
   s{`session:translate-ru`}{`session:role` with `role: translator`}g'

# stale-ok: the old path of the shared block is what this patch removes
patch skills/workflow-reliability/SKILL.md 'workflow-reliability shared block' \
  'plugins/session/workflows/research.js' \
  'plugins/session/lib/block.src.js' \
  's{canonical copy: `/Users/aleksandr\.antonov/projects/claude-session/plugins/session/workflows/research\.js` lines 8-49\.}{one source, stamped into every script by `bin/build.sh`: `/Users/aleksandr.antonov/projects/claude-session/plugins/session/lib/block.src.js`.}'

# stale-ok: the old workflow name is what this patch removes
patch "$MEM/feedback-translate-ru-verify-output.md" 'memory verify-output description' \
  'description: session:translate-ru' \
  'description: a translation launch' \
  's{description: session:translate-ru returns out without checking the file exists}{description: a translation launch can return out without the file existing}'

if [ "$FAILS" -eq 0 ]; then
  echo "switch-user: PASS $N patch(es) in place, $DONE applied in this run ($DIR)"
  exit 0
fi
echo "switch-user: FAIL $FAILS failure(s), $N patch(es) in place ($DIR)"
exit 1
