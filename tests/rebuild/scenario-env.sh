#!/bin/bash
# Builds the scratch project a behavior run starts in.
#
#   tests/rebuild/scenario-env.sh [--hide-old] <variant> <dir>
#
# Variants:
#   base            the worktree plugin alone
#   stub-on         plus the stub tool plugin of tests/rebuild/fixtures/tool-stub (a second
#                   --plugin-dir; U7 froze that two of them are accepted in one command)
#   stub-off-deny   the stub is not loaded and one built-in tool is denied in the project
#                   (U10: the project disable is complete; U11: a bare tool name in
#                   permissions.deny removes the tool from the session and from its agents)
#   gate, gate-stub-on, gate-stub-off-deny
#                   the same three with --hide-old built in: the names the behavior gate runs
#                   under, so the variant of a verdict line says which set was measured
# --hide-old: the plugin argument points at a copy of the worktree plugin, with the contract entries
#   of the five old workflows taken out of the copy's plugin.json and the old workflow files and
#   process skills left out of the copy itself, so the gate measures the new set only: a workflows/
#   directory is auto-loaded, so a file left in the copy would stay launchable and listed however
#   the contract entries read. The files themselves are deleted in P9 in the worktree; this flag
#   only hides them from one session.
#   The copy is made in the sibling directory <dir>-plugin, never inside <dir>: a copy inside the
#   project would put the workflow scripts under the directory the measured session works in, where
#   its own Glob, Grep and Read reach the script bodies the gate rules forbid it to read.
#
# The mechanism is the one the U7 answer line froze (plan/control-calls.md):
#   real HOME, a scratch project directory whose .claude/settings.json sets
#   "session@claude-session" to false, and `claude --plugin-dir <worktree>/plugins/session`.
# The flag loads the worktree plugin (its contract lines and its agents appear exactly once) and
# the project-level disable hides the installed plugin in that project only.
#
# Credential rule (section 6): nothing is read, listed or copied from ~/.claude, ~/.claude.json, a
# keychain or any login state. This script writes inside <dir> and, with --hide-old, inside
# <dir>-plugin, and nowhere else. The user-level skills of the real ~/.claude/skills stay visible to
# the session; that loss of isolation is accepted and named under "what no oracle covers".
#
# Writes into <dir>: .claude/settings.json, claude-args (the argument list for `claude`), variant.
# With --hide-old it also writes the plugin copy <dir>-plugin, outside the project.
set -u

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
PLUG=$REPO/plugins/session
STUB=$REPO/tests/rebuild/fixtures/tool-stub
OLD_WF="build dev research review-fix translate-ru"
OLD_SKILLS="pipeline review"
# The denied tool of the stub-off-deny variant: a tool the carriers normally use, whose loss still
# leaves reading and writing files possible. A bare `Read` in permissions.deny stood here first and
# made the scenario unpassable by construction: the harness reads that rule as a rule over paths, so
# every Write came back "File is covered by a Read deny rule" and the wanted file could never be
# written by anyone.
DENY_TOOL=Bash

HIDE_OLD=0
ARGS=()
for a in "$@"; do
  case $a in
    --hide-old) HIDE_OLD=1 ;;
    -*) echo "scenario-env: unknown option $a" >&2; exit 2 ;;
    *) ARGS+=("$a") ;;
  esac
done

if [ "${#ARGS[@]}" -ne 2 ]; then
  echo "scenario-env: usage: scenario-env.sh [--hide-old] <variant> <dir>" >&2
  exit 2
fi
VARIANT=${ARGS[0]}
DIR=${ARGS[1]}

# the gate names carry the flag: one variant name per line of a verdict file, no second argument
# that a runner could forget
case $VARIANT in
  gate) BUILD=base; HIDE_OLD=1 ;;
  gate-stub-on) BUILD=stub-on; HIDE_OLD=1 ;;
  gate-stub-off-deny) BUILD=stub-off-deny; HIDE_OLD=1 ;;
  base | stub-on | stub-off-deny) BUILD=$VARIANT ;;
  *) echo "scenario-env: unknown variant $VARIANT (base stub-on stub-off-deny gate gate-stub-on gate-stub-off-deny)" >&2; exit 2 ;;
esac

case $DIR in
  /*) ;;
  *) echo "scenario-env: <dir> must be an absolute path" >&2; exit 2 ;;
esac

if [ -e "$DIR" ] && [ -n "$(ls -A "$DIR" 2>/dev/null)" ]; then
  echo "scenario-env: $DIR is not empty; a run never reuses a project directory" >&2
  exit 2
fi

if [ "$BUILD" = stub-on ] && [ ! -f "$STUB/.claude-plugin/plugin.json" ]; then
  echo "scenario-env: no stub tool plugin at $STUB" >&2
  exit 1
fi

mkdir -p "$DIR/.claude" || exit 1

# ---- the plugin the session loads: the worktree plugin, or a copy without the old set ----
LOADED=$PLUG
if [ "$HIDE_OLD" = 1 ]; then
  # outside <dir>: the measured session works in <dir>, and a plugin copy inside it would put every
  # workflow script within reach of its own Glob, Grep and Read
  LOADED=$DIR-plugin
  if [ -e "$LOADED" ] && [ -n "$(ls -A "$LOADED" 2>/dev/null)" ]; then
    echo "scenario-env: $LOADED is not empty; a run never reuses a plugin copy" >&2
    exit 2
  fi
  mkdir -p "$LOADED" || exit 1
  # copied entry by entry, skills and workflows apart: the old process skills and the old workflow
  # files are left out of the copy instead of being copied and then removed, so this script deletes
  # nothing anywhere. A plugin auto-loads every file of its workflows/ directory, so taking the old
  # contract entries out of plugin.json alone would leave the old set launchable and listed, and the
  # gate would not measure the new set.
  [ -e "$PLUG/.claude-plugin" ] && { cp -R "$PLUG/.claude-plugin" "$LOADED/" || exit 1; }
  for e in "$PLUG"/*; do
    [ -e "$e" ] || continue
    b=$(basename "$e")
    [ "$b" = skills ] && continue
    [ "$b" = workflows ] && continue
    cp -R "$e" "$LOADED/" || exit 1
  done
  if [ -d "$PLUG/workflows" ]; then
    mkdir -p "$LOADED/workflows" || exit 1
    for w in "$PLUG"/workflows/*; do
      [ -e "$w" ] || continue
      b=$(basename "$w")
      skip=0
      for o in $OLD_WF; do [ "$b" = "$o.js" ] && skip=1; done
      [ "$skip" = 1 ] && continue
      cp -R "$w" "$LOADED/workflows/$b" || exit 1
    done
  fi
  if [ -d "$PLUG/skills" ]; then
    mkdir -p "$LOADED/skills" || exit 1
    for s in "$PLUG"/skills/*; do
      [ -e "$s" ] || continue
      b=$(basename "$s")
      skip=0
      for o in $OLD_SKILLS; do [ "$b" = "$o" ] && skip=1; done
      [ "$skip" = 1 ] && continue
      cp -R "$s" "$LOADED/skills/$b" || exit 1
    done
  fi
  python3 - "$LOADED/.claude-plugin/plugin.json" $OLD_WF <<'PY' || exit 1
import json, sys
path, old = sys.argv[1], set(sys.argv[2:])
d = json.load(open(path, encoding='utf-8'))
def keep(h):
    c = h.get('command', '')
    return not any(('workflows/%s.js' % o) in c for o in old)
groups = []
for g in d.get('hooks', {}).get('SessionStart', []):
    hooks = [h for h in g.get('hooks', []) if keep(h)]
    if hooks:
        g = dict(g)
        g['hooks'] = hooks
        groups.append(g)
d['hooks']['SessionStart'] = groups
with open(path, 'w', encoding='utf-8') as fh:
    json.dump(d, fh, indent=2)
    fh.write('\n')
PY
fi

# ---- the project settings: the installed plugin off, and for one variant a denied tool ----
python3 - "$DIR/.claude/settings.json" "$BUILD" "$DENY_TOOL" <<'PY' || exit 1
import json, sys
path, build, tool = sys.argv[1], sys.argv[2], sys.argv[3]
s = {"enabledPlugins": {"session@claude-session": False}}
if build == 'stub-off-deny':
    s["permissions"] = {"deny": [tool]}
with open(path, 'w', encoding='utf-8') as fh:
    json.dump(s, fh, indent=2)
    fh.write('\n')
PY

# ---- the argument list for `claude` ----
ARGLINE="--plugin-dir $LOADED"
[ "$BUILD" = stub-on ] && ARGLINE="$ARGLINE --plugin-dir $STUB"
printf '%s\n' "$ARGLINE" > "$DIR/claude-args"
printf '%s\n' "$VARIANT" > "$DIR/variant"

echo "scenario-env: $VARIANT built in $DIR (args: $ARGLINE)"
