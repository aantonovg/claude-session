#!/bin/bash
# Builds the copy of the user-level assets that part 9 patches, in the real layout.
#
#   tests/rebuild/user-copy.sh <dir>
#
# Source: $CLAUDE_USER_DIR, default $HOME/.claude, read-only input of this branch — nothing is ever
# written there (work mode, section 6). The copy holds exactly what tests/rebuild/switch-user.sh
# patches, at the relative paths it meets at the switch:
#   <dir>/skills/                          the user-level skills
#   <dir>/projects/<encoded main checkout>/memory/    the memory of this project
#   <dir>/statusline.sh                    the statusline consumer named by statusLine.command (U9)
# A missing source fails the run: a copy of nothing would let switch-user.sh and stale.sh pass while
# they scanned an empty directory.
#
# The copy is a copy of files, never a HOME: no session starts in it, and no keychain entry, login
# state or ~/.claude.json is read, listed or copied (credential rule, section 6).
set -u

SRC=${CLAUDE_USER_DIR:-$HOME/.claude}
# The memory of this project sits under the encoded path of the MAIN checkout, not of this worktree:
# it is the memory the switch meets. The encoding is the one Claude Code uses, `/` and `.` to `-`.
MAIN=${CLAUDE_MAIN_CHECKOUT:-/Users/aleksandr.antonov/projects/claude-session}
ENC=$(printf '%s' "$MAIN" | tr '/.' '--')
STATUSLINE=statusline.sh

DIR=${1:-}
if [ -z "$DIR" ]; then
  echo "user-copy: no argument; want <dir> (where the copy is built)" >&2
  exit 2
fi
case $DIR in
  "$SRC"|"$SRC"/*) echo "user-copy: FAIL <dir> lies inside $SRC: the copy is never written there" >&2; exit 1 ;;
esac

fail() { echo "user-copy: FAIL $1" >&2; exit 1; }

[ -d "$SRC" ] || fail "no source directory $SRC"
[ -d "$SRC/skills" ] || fail "no source $SRC/skills"
[ -d "$SRC/projects/$ENC/memory" ] || fail "no source $SRC/projects/$ENC/memory"
[ -f "$SRC/$STATUSLINE" ] || fail "no source $SRC/$STATUSLINE (the U9 answer line names it)"

mkdir -p "$DIR/projects/$ENC" || fail "cannot create $DIR"
rm -rf "$DIR/skills" "$DIR/projects/$ENC/memory"
cp -R "$SRC/skills" "$DIR/skills" || fail "cannot copy $SRC/skills"
cp -R "$SRC/projects/$ENC/memory" "$DIR/projects/$ENC/memory" || fail "cannot copy the memory"
cp "$SRC/$STATUSLINE" "$DIR/$STATUSLINE" || fail "cannot copy $SRC/$STATUSLINE"

SK=$(find "$DIR/skills" -type f -name '*.md' | wc -l | tr -d ' ')
ME=$(find "$DIR/projects/$ENC/memory" -type f | wc -l | tr -d ' ')
[ "$SK" -gt 0 ] || fail "the copy holds no skill file"
[ "$ME" -gt 0 ] || fail "the copy holds no memory file"
echo "user-copy: $DIR ($SK skill file(s), $ME memory file(s), $STATUSLINE)"
