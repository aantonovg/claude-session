#!/bin/bash
# bin/build.sh --check is clean; the shared block is byte-identical in both workflows and equals
# lib/block.js; the generated base skill is the base under its frontmatter; a hand edit inside a
# generated region turns --check red (mutant run in a copy).
set -u
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
check "build.sh --check clean" bash "$P/bin/build.sh" --check
blk() { awk '/^\/\/ ---- shared block/{f=1; next} /^\/\/ ---- end shared block/{f=0} f' "$1"; }
for w in helper batch; do
  check "$w.js carries the shared block" test -n "$(blk "$P/workflows/$w.js")"
  check "$w.js shared block equals lib/block.js" bash -c 'diff <(awk "/^\/\/ ---- shared block/{f=1; next} /^\/\/ ---- end shared block/{f=0} f" "$1") "$2" >/dev/null' _ "$P/workflows/$w.js" "$P/lib/block.js"
done
check "block.js carries the table of classes.json" bash -c 'node -e "const b=require(process.argv[1]); const c=require(process.argv[2]); process.exit(JSON.stringify(b.CLASSES)===JSON.stringify(c)?0:1)" "$1" "$2"' _ "$P/lib/block.js" "$P/lib/classes.json"
check "skills/base/SKILL.md is BASE.md under its frontmatter" bash -c 'diff <(awk "NR>6" "$1") "$2" >/dev/null' _ "$P/skills/base/SKILL.md" "$P/base/BASE.md"
check "generated skill frontmatter disables model invocation" grep -Fxq 'disable-model-invocation: true' "$P/skills/base/SKILL.md"
T=$(mktemp -d) || exit 1; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/plugins/session" && cp -R "$P/bin" "$P/lib" "$P/workflows" "$P/base" "$P/skills" "$T/plugins/session/"
# The manifest names project workflows as ../../.claude/workflows/*.js, so the copy keeps the repo layout.
mkdir -p "$T/.claude/workflows" && cp "$P"/../../.claude/workflows/*.js "$T/.claude/workflows/"
echo '// hand edit' >> "$T/plugins/session/lib/block.js"
check "--check fails on a hand edit of lib/block.js" bash -c '! bash "$1" --check >/dev/null 2>&1' _ "$T/plugins/session/bin/build.sh"
bash "$T/plugins/session/bin/build.sh" >/dev/null
sed -i '' 's/^| c3 |.*/| c3 | x |/' "$T/plugins/session/base/BASE.md"
check "--check fails on a hand edit inside the class table" bash -c '! bash "$1" --check >/dev/null 2>&1' _ "$T/plugins/session/bin/build.sh"
bash "$T/plugins/session/bin/build.sh" >/dev/null
check "--check clean after a rebuild" bash "$T/plugins/session/bin/build.sh" --check
done_with build-sync
