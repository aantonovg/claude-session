#!/bin/bash
# No live reference to a retired name anywhere under plugins/session, the two READMEs, the
# project workflows and the tool-plugin doc: the four old workflows, the tool-set agents, the
# process skill and its pages, the verification page, the task layout, the ledger hook, the roles
# and aspects, the old codex pages. The version log of the plugin README is history and is skipped.
set -u
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
NAMES='workflows/(role|chain|make|probe)\.js|session:(role|chain|make|probe)\b|tools-(read-write-bash|read-write|read-bash|edit|web)\b|skills/process|session:process|process/core\.md|intent-form\.md|lib/verification\.md|verification page|task-layout|ledger-stop|lib/roles|lib/aspects|codex-modes\.md|proxy-prompt\.md|tests/rebuild'
scan() {  # $1 file
  case $1 in
    */plugins/session/README.md) awk '/^## Version log/{exit} {print}' "$1" ;;
    *) cat "$1" ;;
  esac | grep -nE "$NAMES" | head -3
}
files=$(find "$P" "$REPO/docs/tool-plugin" "$REPO/.claude/workflows" -type f \( -name '*.md' -o -name '*.js' -o -name '*.sh' -o -name '*.json' \) | grep -v '/lib/block.js$' | sort)
files="$files $REPO/README.md"
for f in $files; do
  h=$(scan "$f")
  check "${f#$REPO/} names no retired asset${h:+ ($h)}" test -z "$h"
done
for d in skills/process lib/roles lib/aspects; do check "$d is gone" test ! -e "$P/$d"; done
for f in lib/verification.md lib/task-layout.md hooks/ledger-stop.sh skills/codex/codex-modes.md skills/codex/proxy-prompt.md workflows/role.js workflows/chain.js workflows/make.js workflows/probe.js; do
  check "$f is gone" test ! -e "$P/$f"
done
check "tests/rebuild is gone" test ! -e "$REPO/tests/rebuild"
done_with stale
