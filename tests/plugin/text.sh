#!/bin/bash
# The class table is the only source of a model: no text of the plugin names a model, a cell code,
# a reasoning level or a tier outside the generated class-table region and lib/classes.json
# (cellTokens of lib/block.js, executed over the base, the agents, the skills and the workflow
# usage blocks; a mutant of the function that returns nothing must turn the same check red). Out
# of scope: the codex skill and the codex helper (they name codex tiers and their reasoning levels by necessity), the
# READMEs (reference tables and history) and the `slot (main opus sonnet ...)` usage line, whose
# words are slot names. Also: no live text of the plugin or the READMEs names a retired design
# word (the version log of the plugin README is history and is cut off).
set -u
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
FILES=$(find "$P/base" "$P/agents" "$P/skills" -name '*.md' | grep -v '/skills/codex/\|/agents/codex.md' | sort)
usage_blocks() { for f in "$P"/workflows/*.js; do awk 'f==0&&/^\/\* usage:/{f=1} f{print} f&&/\*\//{exit}' "$f" | grep -v '^slot ('; done; }
scan() {  # $1 block.js; stdin: lines; prints hits
  node -e '
const b = require(process.argv[1]); let t = ""; process.stdin.on("data", d => t += d).on("end", () => {
  let inTable = false, hits = []
  for (const [i, l] of t.split("\n").entries()) {
    if (/^<!-- class table/.test(l.trim())) inTable = true
    if (/^<!-- end class table/.test(l.trim())) { inTable = false; continue }
    if (inTable) continue
    const toks = b.cellTokens(l); if (toks.length) hits.push(`${i + 1}: ${toks.join(",")} :: ${l.trim().slice(0, 80)}`)
  }
  process.stdout.write(hits.join("\n")); process.exit(0) })' "$1"
}
for f in $FILES; do
  hits=$(scan "$P/lib/block.js" < "$f")
  check "$(basename "$(dirname "$f")")/$(basename "$f") names no cell${hits:+ ($hits)}" test -z "$hits"
done
hits=$(usage_blocks | scan "$P/lib/block.js")
check "workflow usage blocks name no cell${hits:+ ($hits)}" test -z "$hits"
T=$(mktemp -d) || exit 1; trap 'rm -rf "$T"' EXIT
sed 's/^function cellTokens(line) {/function cellTokens(line) { return [];/' "$P/lib/block.js" > "$T/mutant.js"
printf 'runs on fable at high effort\n' > "$T/probe.md"
m=$(scan "$T/mutant.js" < "$T/probe.md"); r=$(scan "$P/lib/block.js" < "$T/probe.md")
check "mutant scanner passes the probe, the real scanner fails it" test -z "$m" -a -n "$r"
OLD='cold agent|verification page|verification\.md|task-layout|ledger-stop|lib/roles|lib/aspects|session:role|session:chain|session:make|session:probe|tools-read-write|tools-read-bash|tools-edit|tools-web|process skill|/session:process|evidence chain|coverage-checker|closure-author'
live() { case $1 in */plugins/session/README.md) awk '/^## Version log/{exit} {print}' "$1" ;; *) cat "$1" ;; esac; }
for f in $FILES $(find "$P/skills/codex" "$P/agents/codex.md" -name "*.md") "$P/README.md" "$REPO/README.md"; do
  h=$(live "$f" | grep -nE "$OLD" | head -3)
  check "$(basename "$(dirname "$f")")/$(basename "$f") names no retired design word${h:+ ($h)}" test -z "$h"
done
done_with text
