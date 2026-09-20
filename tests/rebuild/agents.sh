#!/bin/bash
# Static oracle of the tool-set agents.
# Globs: plugins/session/agents/tools-*.md, plus every agentType string in
# plugins/session/workflows/{role,chain,make,probe}.js (a workflow that does not exist yet is
# skipped, so this test lives from P1 on).
# Proves: every tool-set agent carries a tool list, a return shape, a BLOCKED rule and a working
# directory rule; none of them pins a model or a reasoning level (A9: the call site passes both
# from the class table); every tool is a built-in of the allowed set; no workflow launches an
# agentType without a file. Temp dirs only, no network, under 10 s.
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

ALLOWED="Bash Edit Read Write WebFetch WebSearch"
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
check "a3 the launch prefix of this root is known" test -n "$PREFIX"
for w in $WORKFLOWS; do
  f=$P/workflows/$w.js
  [ -f "$f" ] || continue
  types=$(grep -oE "agentType: *['\"][^'\"]+['\"]" "$f" | sed -E "s/agentType: *['\"]//; s/['\"]$//" | sort -u)
  for t in $types; do
    case $t in
      "$PREFIX":*) name=${t#"$PREFIX":} ;;
      *:*) name= ;;
      *) name=$t ;;
    esac
    check "a3 $w.js agentType $t is a name of this root (prefix $PREFIX)" test -n "$name"
    [ -n "$name" ] || continue
    check "a3 $w.js agentType $t carries no second prefix" bash -c 'case "$1" in *:*) exit 1 ;; esac' _ "$name"
    check "a3 $w.js agentType $t has an agent file" test -f "$A/$name.md"
  done
done

if [ "$FAILS" -eq 0 ]; then echo "agents: PASS $N"; exit 0; fi
echo "agents: FAIL $FAILS failures, $N checks passed"
exit 1
