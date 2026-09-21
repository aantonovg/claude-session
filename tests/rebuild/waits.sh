#!/bin/bash
# Static oracle of part 9 for the two tmux launch scripts: tests/corp/launch.sh and
# tests/demo-game/launch.sh.
#
#   tests/rebuild/waits.sh
#
# Both scripts prove that a mode skill loaded by typing a slash command with `tmux send-keys` and
# then polling the pane for a line of the reply. Two ways such a wait proves nothing, and P9 met
# both: a pattern the typed command itself matches returns before the skill answered (the pane holds
# the command it just typed), and a pattern no reply of the skill ever prints times out and kills
# the run. Both are read here by echoedWaits() of the shared block, executed, never grepped: the
# rule sits with the rest of the block and the mutant below proves it ran.
#
# Globs: tests/corp/launch.sh, tests/demo-game/launch.sh, plugins/session/lib/block.js.
# Temp dirs only, no tmux, no network, no session, under 10 s.
set -u

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
BLOCK=$REPO/plugins/session/lib/block.js
CORP=$REPO/tests/corp/launch.sh
DEMO=$REPO/tests/demo-game/launch.sh
# the values these scripts are launched with: the mode line of the P9 chain and the codex line
VARS='{"mode":"process code full","extra":"codex +astra"}'

N=0; FAILS=0
pass() { N=$((N + 1)); }
fail() { echo "FAIL $1"; FAILS=$((FAILS + 1)); }
check() { local label=$1; shift; if "$@"; then pass; else fail "$label"; fi; }

for f in "$BLOCK" "$CORP" "$DEMO"; do
  [ -f "$f" ] || { echo "waits: FAIL missing $f" >&2; exit 1; }
done

T=$(mktemp -d) || exit 1
trap 'rm -rf "$T"' EXIT

cat > "$T/scan.js" <<'JS'
// scan.js <block> <script> <vars json>: prints every wait the typed line before it already
// satisfies, and exits non-zero when there is one
const fs = require('fs')
const b = require(process.argv[2])
const path = process.argv[3]
const hits = b.echoedWaits(fs.readFileSync(path, 'utf8'), JSON.parse(process.argv[4]))
hits.forEach(h => console.log(`${path}:${h.line} ${h.why}: /${h.re}/ over "${h.typed}"`))
process.exit(hits.length ? 1 : 0)
JS

# ---- w1: no wait of either script is satisfied by the line the script typed ----
check "w1 tests/corp/launch.sh waits for a line it did not type itself" \
  node "$T/scan.js" "$BLOCK" "$CORP" "$VARS"
check "w1 tests/demo-game/launch.sh waits for a line it did not type itself" \
  node "$T/scan.js" "$BLOCK" "$DEMO" "$VARS"

# ---- w2: the waits can see the reply they are waiting for ----
# A pattern that matches nothing the skill prints is the other half of the defect and no scan of the
# script text can see it. It is read by feeding the reply line into the place of the typed command:
# the same wait must then report a hit, which is exactly "this pattern matches this reply".
# The two replies are the shapes the process skill and the codex skill fix: "the type, the depth and
# the class, nothing else" and `Codex: <mode> (heavy <…>, exec <…>); fallbacks <…>.`
CODEXREPLY='Codex: sol (heavy gpt-5-codex, exec gpt-5-codex); fallbacks none.'
for reply in 'code, full, c3' 'code full c3'; do
  sed -e "s|/session:process code full|$reply|" -e "s|/session:codex +astra|$CODEXREPLY|" "$CORP" > "$T/corp-reply.sh"
  check "w2 the corp waits see the reply \"$reply\"" \
    bash -c 'out=$(node "$1" "$2" "$3" "$4"); [ "$(printf %s "$out" | grep -c ":")" = 2 ]' \
    _ "$T/scan.js" "$BLOCK" "$T/corp-reply.sh" "$VARS"
  check "w2 the demo-game waits see the reply \"$reply\"" \
    bash -c 'out=$(node "$1" "$2" "$3" "$4"); [ "$(printf %s "$out" | grep -c ":")" = 2 ]' \
    _ "$T/scan.js" "$BLOCK" "$DEMO" "{\"mode\":\"$reply\",\"extra\":\"$CODEXREPLY\"}"
done

# ---- w3: executed, not read ----
# a fixture whose wait the typed line satisfies is a hit, the same fixture with a pattern of the
# reply is clean, and the resolved form of a command built from a variable is what counts
{ printf '%s\n' 'tmux send-keys -t "$s" "/session:process code full" Enter'
  printf '%s\n' "wait_for 'process' 90 || exit 1"
} > "$T/f-echo.sh"
check "w3 a wait the typed line satisfies is a hit" \
  bash -c '! node "$1" "$2" "$3" "$4" > /dev/null' _ "$T/scan.js" "$BLOCK" "$T/f-echo.sh" "$VARS"
{ printf '%s\n' 'tmux send-keys -t "$s" "/session:process code full" Enter'
  printf '%s\n' "wait_for 'c[0-9]' 90 || exit 1"
} > "$T/f-clean.sh"
check "w3 a wait for a line the typed command does not carry is clean" \
  node "$T/scan.js" "$BLOCK" "$T/f-clean.sh" "$VARS"
{ printf '%s\n' 'tmux send-keys -t "$s" "/session:$mode" Enter'
  printf '%s\n' "wait_for 'full' 90 || exit 1"
} > "$T/f-var.sh"
check "w3 a command assembled from a variable is read resolved" \
  bash -c '! node "$1" "$2" "$3" "$4" > /dev/null' _ "$T/scan.js" "$BLOCK" "$T/f-var.sh" "$VARS"
printf '%s\n' "wait_for 'anything' 90 || exit 1" > "$T/f-first.sh"
check "w3 a wait before the first typed line is no hit" \
  node "$T/scan.js" "$BLOCK" "$T/f-first.sh" "$VARS"

# ---- w4: the mutants ----
mut() { # mut <name> <perl expression>
  perl -pe "$2" "$BLOCK" > "$T/$1.js"
  check "w4 the mutant $1 is really a mutation" bash -c '! cmp -s "$1" "$2"' _ "$BLOCK" "$T/$1.js"
  check "w4 the mutant $1 still loads" \
    bash -c 'node -e "require(process.argv[1])" "$1" 2> "$2/mut.err" || { tail -2 "$2/mut.err"; exit 1; }' \
    _ "$T/$1.js" "$T"
}
mut novars "s|Object\.prototype\.hasOwnProperty\.call\(v, name\) \? String\(v\[name\]\) : m0|m0|"
check "w4 the mutant that leaves a variable unresolved is caught" \
  bash -c 'node "$1" "$2" "$3" "$4" > /dev/null' _ "$T/scan.js" "$T/novars.js" "$T/f-var.sh" "$VARS"
mut notyped "s|if \(sent\) \{ typed\.push.*return \}|if (sent) { return }|"
check "w4 the mutant that forgets the typed line is caught" \
  bash -c 'node "$1" "$2" "$3" "$4" > /dev/null' _ "$T/scan.js" "$T/notyped.js" "$T/f-echo.sh" "$VARS"
# the pane window: the poller greps the last 20 non-blank lines, so a wait an EARLIER typed line
# satisfies is a hit too — a rule read against the line typed last would call this fixture clean
{ printf '%s\n' 'tmux send-keys -t "$s" "/session:process code full" Enter'
  printf '%s\n' "wait_for 'c[0-9]' 90 || exit 1"
  printf '%s\n' 'tmux send-keys -t "$s" "ready" Enter'
  printf '%s\n' "wait_for 'process' 90 || exit 1"
} > "$T/f-window.sh"
check "w4 a wait an earlier typed line of the window satisfies is a hit" \
  bash -c '! node "$1" "$2" "$3" "$4" > /dev/null' _ "$T/scan.js" "$BLOCK" "$T/f-window.sh" "$VARS"
mut lasttyped "s|const echoed = typed\.filter\(t => re\.test\(t\)\)|const echoed = [typed[typed.length - 1]].filter(t => re.test(t))|"
check "w4 the mutant that reads the line typed last only is caught" \
  bash -c 'node "$1" "$2" "$3" "$4" > /dev/null' _ "$T/scan.js" "$T/lasttyped.js" "$T/f-window.sh" "$VARS"

if [ "$FAILS" -eq 0 ]; then echo "waits: PASS $N checks"; exit 0; fi
echo "waits: FAIL $FAILS failures, $N checks passed"
exit 1
