#!/bin/sh
# Watches the process skills of the plugin the measured session loaded, for the `plugin-widens`
# scenario: a newly enabled tool plugin must widen what the session can do with no edit to a
# process skill of the base plugin.
#
#   sh skills-check.sh --before   writes skills-before.txt (the baseline, run by the scenario setup)
#   sh skills-check.sh            writes skills-after.txt and prints SKILLS-UNCHANGED or SKILLS-CHANGED
#
# The skills hashed are the ones of the plugin the session really loaded, never a `plugin/` path
# inside the project: with --hide-old the copy lives in the sibling directory <project>-plugin, so
# the root is read from the first --plugin-dir argument of the project's claude-args (PLUGIN_ROOT
# overrides it). An empty or unreadable skill set is evidence of nothing: this script then prints
# SKILLS-CHECK-BROKEN and exits 1, so the criterion can never pass by hashing no file at all.
set -u

MODE=${1:-}
ROOT=${PLUGIN_ROOT:-}
if [ -z "$ROOT" ]; then
  if [ ! -f claude-args ]; then
    echo "SKILLS-CHECK-BROKEN no claude-args in $PWD"
    exit 1
  fi
  ROOT=$(awk '{print $2}' claude-args)
fi
if [ -z "$ROOT" ] || [ ! -d "$ROOT/skills" ]; then
  echo "SKILLS-CHECK-BROKEN no skills directory under ${ROOT:-(no plugin root)}"
  exit 1
fi

OUT=skills-after.txt
[ "$MODE" = --before ] && OUT=skills-before.txt
find "$ROOT/skills" -type f -print0 | sort -z | xargs -0 shasum > "$OUT" 2>/dev/null
if [ ! -s "$OUT" ]; then
  echo "SKILLS-CHECK-BROKEN empty hash set under $ROOT/skills"
  exit 1
fi

if [ "$MODE" = --before ]; then
  echo "SKILLS-BASELINE $(wc -l < "$OUT" | tr -d ' ') files under $ROOT/skills"
  exit 0
fi
if [ ! -s skills-before.txt ]; then
  echo "SKILLS-CHECK-BROKEN no baseline skills-before.txt in $PWD"
  exit 1
fi
if diff -q skills-before.txt "$OUT" >/dev/null 2>&1; then echo SKILLS-UNCHANGED; else echo SKILLS-CHANGED; fi
