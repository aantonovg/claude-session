#!/bin/sh
# One SessionStart contract line for one workflow of this plugin.
#
#   sh bin/contract.sh <workflow.js> <prefix>
#
# Prints one line of SessionStart hook JSON whose additionalContext is
#   "Workflow <prefix>:<stem> (launch by name; contract below; never read the script body): <usage>"
# where <usage> is the `/* usage: ... */` block of the workflow file collapsed to one line. Every
# `{ROOT}` inside it becomes the absolute root of this plugin (CLAUDE_PLUGIN_ROOT, or the parent of
# this script), so a launcher reads the plugin's own paths out of the contract and never has to
# know where the plugin was installed.
# stdout only, exit 0 and print nothing when there is no usable block: a hook never fails a session.
# This plugin carries its own copy of this script; it depends on no other plugin.
set -u

F=${1:-}
PREFIX=${2:-}
[ -n "$F" ] && [ -f "$F" ] || exit 0
ROOT=${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)}
S=$(basename "$F" .js)
NAME=$S
[ -n "$PREFIX" ] && NAME="$PREFIX:$S"

LC_ALL=C awk -v root="$ROOT" -v name="$NAME" '
  BEGIN {
    # the JSON escape map: a character-by-character walk, never a gsub replacement, so a backslash
    # in the text can not be re-read as an escape of the replacement string
    for (i = 1; i < 32; i++) m[sprintf("%c", i)] = sprintf("\\u%04x", i)
    m["\t"] = "\\t"; m["\\"] = "\\\\"; m["\""] = "\\\""
  }
  !f && /\/\* usage:/ { f = 1; sub(/.*\/\* usage:/, "") }
  f {
    if (index($0, "*/")) { sub(/\*\/.*/, ""); t = t " " $0; done = 1; exit }
    t = t " " $0
  }
  END {
    if (!f || !done) exit 0
    gsub(/[ \t\r]+/, " ", t); sub(/^ /, "", t); sub(/ $/, "", t)
    gsub(/\{ROOT\}/, root, t)
    if (t == "") exit 0
    line = "Workflow " name " (launch by name; contract below; never read the script body): " t
    o = ""; L = length(line)
    for (i = 1; i <= L; i++) { c = substr(line, i, 1); o = o ((c in m) ? m[c] : c) }
    printf "{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"%s\"}}\n", o
  }' "$F" 2>/dev/null

exit 0
