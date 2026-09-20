#!/bin/bash
# Builds the scratch project a behavior run starts in.
#
#   tests/rebuild/scenario-env.sh [--hide-old] <variant> <dir>
#
# Variants: base (P1). stub-on, stub-off-deny and the --hide-old flag arrive with P7; this script
# refuses them until then instead of building half an environment.
#
# The mechanism is the one the U7 answer line froze (plan/control-calls.md):
#   real HOME, a scratch project directory whose .claude/settings.json sets
#   "session@claude-session" to false, and `claude --plugin-dir <worktree>/plugins/session`.
# The flag loads the worktree plugin (its contract lines and its agents appear exactly once) and
# the project-level disable hides the installed plugin in that project only.
#
# Credential rule (section 6): nothing is read, listed or copied from ~/.claude, ~/.claude.json, a
# keychain or any login state. This script writes three files and nothing else. The user-level
# skills of the real ~/.claude/skills stay visible to the session; that loss of isolation is
# accepted and named under "what no oracle covers".
#
# Writes into <dir>: .claude/settings.json, claude-args (the argument list for `claude`), variant.
set -u

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
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

case $DIR in
  /*) ;;
  *) echo "scenario-env: <dir> must be an absolute path" >&2; exit 2 ;;
esac

if [ "$HIDE_OLD" = 1 ]; then
  echo "scenario-env: --hide-old is built in P7, not here" >&2
  exit 2
fi
if [ "$VARIANT" != base ]; then
  echo "scenario-env: variant $VARIANT is built in P7; P1 builds base only" >&2
  exit 2
fi

if [ -e "$DIR" ] && [ -n "$(ls -A "$DIR" 2>/dev/null)" ]; then
  echo "scenario-env: $DIR is not empty; a run never reuses a project directory" >&2
  exit 2
fi

mkdir -p "$DIR/.claude" || exit 1
cat > "$DIR/.claude/settings.json" <<'JSON'
{
  "enabledPlugins": {
    "session@claude-session": false
  }
}
JSON
printf -- '--plugin-dir %s/plugins/session\n' "$REPO" > "$DIR/claude-args"
printf '%s\n' "$VARIANT" > "$DIR/variant"

echo "scenario-env: $VARIANT built in $DIR (args: $(cat "$DIR/claude-args"))"
