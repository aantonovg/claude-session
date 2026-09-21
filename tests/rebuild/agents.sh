#!/bin/bash
# Static oracle of the tool-set agents.
# Globs: plugins/session/agents/tools-*.md, plus every agentType string in
# plugins/session/workflows/{role,chain,make,probe}.js (a workflow that does not exist yet is
# skipped, so this test lives from P1 on).
# Proves: every tool-set agent carries a tool list, a return shape, a BLOCKED rule and a working
# directory rule; none of them pins a model or a reasoning level (A9: the call site passes both
# from the class table); every tool is a built-in of the allowed set; every agentType a workflow of
# this root launches carries this root's prefix, and every agent name those launches can reach —
# the name at the call site, or, when the site names only the prefix, every agent of the role
# catalog the site resolves through — has a file of this root. Temp dirs only, no network,
# under 10 s.
set -u

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
# TOOLPLUGIN=<root> runs the same checks against another plugin's root (P7: the tool plugin
# template and the stub fixture are plugins of their own). In that mode the agent roster and the
# workflow list come from that root, and an MCP tool name (mcp__<server>__<tool>) counts as a tool
# of the set: a tool plugin exists to carry exactly those.
FOREIGN=${TOOLPLUGIN:-}
P=${FOREIGN:-$REPO/plugins/session}
A=$P/agents

N=0; FAILS=0
pass() { N=$((N + 1)); }
fail() { echo "FAIL $1"; FAILS=$((FAILS + 1)); }
check() { local label=$1; shift; if "$@"; then pass; else fail "$label"; fi; }

# Glob is in the list because an input path of a launch may name a directory: a reading role
# that cannot list one blocks on the input it was given instead of answering.
ALLOWED="Bash Edit Glob Read Write WebFetch WebSearch"
if [ -n "$FOREIGN" ]; then
  WANT=
  WORKFLOWS=$(for f in "$P"/workflows/*.js; do [ -f "$f" ] && basename "$f" .js; done)
  # the launch prefix of this root is its plugin name: an agentType of any other prefix names an
  # agent of another plugin, which no agent file of this root can answer for
  PREFIX=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["name"])' "$P/.claude-plugin/plugin.json" 2>/dev/null)
else
  WANT="tools-read-write tools-read-bash tools-read-write-bash tools-edit tools-web"
  WORKFLOWS="role chain make probe"
  PREFIX=session
fi

for w in $WANT; do
  check "a1 agents/$w.md exists" test -f "$A/$w.md"
done

shopt -s nullglob
FILES=("$A"/tools-*.md)
# bash 3.2 expands "${FILES[@]}" of an empty array as an unbound variable under set -u, so the
# guard stops the script instead of falling into the loop with no files.
if [ "${#FILES[@]}" -eq 0 ]; then
  fail "a1 at least one tools-*.md"
  echo "agents: FAIL $FAILS failures, $N checks passed"
  exit 1
fi
pass

for f in "${FILES[@]}"; do
  b=$(basename "$f" .md)
  fm=$(awk 'NR==1&&/^---$/{f=1; next} f&&/^---$/{exit} f{print}' "$f")
  body=$(awk 'NR==1&&/^---$/{f=1; next} f&&/^---$/{f=0; next} !f{print}' "$f")
  check "a2 $b frontmatter name equals the file name" grep -Fxq "name: $b" <<<"$fm"
  check "a2 $b frontmatter description" grep -Eq '^description: .+' <<<"$fm"
  check "a2 $b frontmatter tools" grep -Eq '^tools: .+' <<<"$fm"
  check "a2 $b no model key (A9: the call site passes it)" bash -c '! grep -Eq "^model:" <<<"$1"' _ "$fm"
  check "a2 $b no effort key (A9: the call site passes it)" bash -c '! grep -Eq "^effort:" <<<"$1"' _ "$fm"
  tools=$(grep -E '^tools: ' <<<"$fm" | sed 's/^tools: //' | tr -d ' ' | tr ',' ' ')
  extra=
  for t in $tools; do
    case " $ALLOWED " in *" $t "*) continue ;; esac
    # a tool plugin carries its server's tools, which are no built-ins by construction
    if [ -n "$FOREIGN" ] && printf '%s' "$t" | grep -Eq '^mcp__[A-Za-z0-9_-]+__[A-Za-z0-9_-]+$'; then continue; fi
    extra="$extra $t"
  done
  check "a2 $b tools are built-ins of the allowed set (extra:$extra)" test -z "$extra"
  check "a2 $b names its tool list in the body" bash -c 'for t in $2; do grep -q "$t" <<<"$1" || exit 1; done' _ "$body" "$tools"
  check "a2 $b states a return shape" grep -q '^Return:' <<<"$body"
  check "a2 $b states the BLOCKED rule" grep -q 'BLOCKED: <the denied action>' <<<"$body"
  check "a2 $b states the working directory rule" grep -Eq 'only inside the directory|only inside the directory the output path names' <<<"$body"
done

# a3: every agentType a workflow of this root launches resolves to an agent file of the same root.
# The prefix is read, never stripped: `${t##*:}` would let `other:tools-edit` in a workflow of this
# root, or a base-plugin name in a tool plugin, resolve to a file of the root that is being checked
# and pass as its own agent. A qualified name must carry this root's prefix; a bare name is the
# same root by definition.
# The sites come from block.js agentTypesOf(), executed, never from a grep for `agentType: '...'`:
# both tool-plugin workflows and all four workflows of this plugin write the launch name through a
# const or the shorthand `{ agentType, phase }`, so a grep for a quoted name inspects zero names and
# a foreign prefix passes unseen. A site whose name is decided at run time still carries its prefix.
BLOCKJS=$REPO/plugins/session/lib/block.js
check "a3 the launch prefix of this root is known" test -n "$PREFIX"
check "a3 lib/block.js exists: the agentType rule is executed, never grepped" test -f "$BLOCKJS"
for w in $WORKFLOWS; do
  f=$P/workflows/$w.js
  [ -f "$f" ] || continue
  sites=$(node -e '
const fs = require("fs")
const b = require(process.argv[1])
for (const s of b.agentTypesOf(fs.readFileSync(process.argv[2], "utf8"))) {
  console.log([s.expr, s.prefix == null ? "-" : s.prefix, s.name == null ? "-" : s.name].join("|"))
}' "$BLOCKJS" "$f" 2>/dev/null | sort -u)
  check "a3 $w.js launches at least one agentType a reader can resolve" test -n "$sites"
  while IFS='|' read -r expr prefix name; do
    [ -n "$expr" ] || continue
    # the prefix is required, never assumed: a plugin agent is addressable only as <plugin>:<name>,
    # so a bare name is no launch of this root, and an unresolved site (neither prefix nor name)
    # fails here instead of passing as this root by definition
    check "a3 $w.js agentType $expr carries the prefix of this root ($prefix vs $PREFIX)" test "$prefix" = "$PREFIX"
    [ "$name" != - ] || continue
    check "a3 $w.js agentType $expr carries no second prefix ($name)" bash -c 'case "$1" in *:*) exit 1 ;; esac' _ "$name"
    check "a3 $w.js agentType $expr has an agent file ($name.md)" test -f "$A/$name.md"
  done <<EOF
$sites
EOF
done

# a4: the names behind those launches. Every workflow of this plugin writes its agentType as
# `session:${roleAgent(role)}`, so the site names the prefix and nothing else, and a3 can check no
# file for it. The names a caller can reach are the agents of the role catalog of lib/classes.json,
# read through the generated block: every one of them must have a file of this root. Executed, with
# a mutation — a catalog row naming an agent with no file must turn this red.
roleagents() { node -e 'const b = require(process.argv[1]); console.log(b.roleNames().map(b.roleAgent).join("\n"))' "$1" 2>/dev/null; }
missing_agents() { # <block.js> <agents dir>: the reachable agent names with no file
  local n miss=
  for n in $(roleagents "$1"); do [ -f "$2/$n.md" ] || miss="$miss $n"; done
  printf '%s' "$miss"
}
if [ -z "$FOREIGN" ]; then
  check "a4 the role catalog names the agents a launch can reach" test -n "$(roleagents "$BLOCKJS")"
  check "a4 every agent of the role catalog has a file (missing:$(missing_agents "$BLOCKJS" "$A"))" \
    test -z "$(missing_agents "$BLOCKJS" "$A")"
  T=$(mktemp -d) || exit 1
  trap 'rm -rf "$T"' EXIT
  python3 - "$BLOCKJS" "$T/mutant-block.js" <<'PY'
import re, sys
s = open(sys.argv[1], encoding='utf-8').read()
open(sys.argv[2], 'w', encoding='utf-8').write(re.sub(r'"agent": "tools-[a-z-]+"', '"agent": "tools-no-such"', s, count=1))
PY
  check "a4 the mutant catalog row is really a mutation" bash -c '! cmp -s "$1" "$2"' _ "$BLOCKJS" "$T/mutant-block.js"
  check "a4 a catalog row naming an agent with no file is caught" test -n "$(missing_agents "$T/mutant-block.js" "$A")"
fi

if [ "$FAILS" -eq 0 ]; then echo "agents: PASS $N"; exit 0; fi
echo "agents: FAIL $FAILS failures, $N checks passed"
exit 1
