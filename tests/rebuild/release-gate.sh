#!/bin/bash
# One-time gate of the 0.16.0 release (part P10 of the rebuild). Run once, right after the release
# commit, never as part of a standing suite: every check here holds only at the release commit
# (HEAD subject, the bump itself), so a later commit fails it by design. The checks that hold on
# every commit stay in tests/workflows/usage-test.sh.
#   tests/rebuild/release-gate.sh [repo]   gate the repo (default: this checkout)
#   tests/rebuild/release-gate.sh --selftest   fixture test: a clean release fixture passes, a
#                                              dirty tree and a wrong subject each fail
# Fails on a dirty tree and on any missing item; never skips a check.
set -u

REL=0.16.0

gate() {  # $1 repo root; prints one FAIL line per missing item and a summary, returns 0/1
  local repo=$1 n=0 fails=0
  local pj=$repo/plugins/session/.claude-plugin/plugin.json
  local mj=$repo/.claude-plugin/marketplace.json
  local rd=$repo/plugins/session/README.md
  ck() { local l=$1; shift; if "$@"; then n=$((n + 1)); else echo "FAIL $l"; fails=$((fails + 1)); fi; }

  ck "is a git work tree" git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1
  local st
  st=$(git -C "$repo" status --porcelain 2>/dev/null) || st="git status failed"
  ck "tree clean (git status --porcelain empty)" test -z "$st"
  ck "HEAD subject is 'session $REL: <summary>'" bash -c 'git -C "$1" log -1 --format=%s 2>/dev/null | grep -Eq "^session ${2//./\\.}: ."' _ "$repo" "$REL"
  ck "plugin.json version $REL" python3 -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1]))["version"]==sys.argv[2] else 1)' "$pj" "$REL"
  ck "marketplace.json session version $REL" python3 -c 'import json,sys; m=[p["version"] for p in json.load(open(sys.argv[1]))["plugins"] if p["name"]=="session"]; sys.exit(0 if m==[sys.argv[2]] else 1)' "$mj" "$REL"
  local rsec
  rsec=$(awk '/^## The 0\.16 set/{f=1; print; next} f&&/^## /{exit} f{print}' "$rd" 2>/dev/null)
  ck "README section The 0.16 set" test -n "$rsec"
  ck "README 0.16 section names the four workflows" bash -c 'for w in role chain make probe; do grep -q "session:$w" <<<"$1" || exit 1; done' _ "$rsec"
  ck "README 0.16 section usage-test.sh sentence" grep -Fq 'tests/workflows/usage-test.sh' <<<"$rsec"
  ck "README 0.16 section static suite sentence" grep -Fq 'tests/rebuild/all.sh' <<<"$rsec"
  # the previous release is the highest other version of the log (the log is not sorted: the 0.15.x
  # part runs 0.15.1-0.15.7, then down from the last 0.15 release to 0.15.8), and the new line
  # stands right above it
  local log prev above
  log=$(awk '/^## Version log/{f=1; next} f&&/^## /{exit} f&&/^[0-9]+\.[0-9]+\.[0-9]+: /{print}' "$rd" 2>/dev/null)
  prev=$(printf '%s\n' "$log" | python3 -c 'import sys
v=[l.split(":")[0] for l in sys.stdin if l.strip()]
o=[x for x in v if x!=sys.argv[1]]
print(max(o, key=lambda x: tuple(int(p) for p in x.split("."))) if o else "")' "$REL")
  above=$(printf '%s\n' "$log" | awk -v p="$prev: " 'index($0, p)==1{print last; exit} {last=$0}')
  ck "README version log: $REL is the line right above the previous release ${prev:-(none found)}" bash -c 'test -n "$2" && grep -q "^$1: " <<<"$3"' _ "$REL" "$prev" "$above"
  ck "README version log holds $REL once" test "$(grep -c "^$REL: " "$rd" 2>/dev/null)" = 1

  if [ "$fails" -eq 0 ]; then echo "release-gate: PASS $n"; return 0; fi
  echo "release-gate: FAIL $fails failures, $n checks passed"; return 1
}

if [ "${1:-}" = --selftest ]; then
  T=$(mktemp -d) || exit 1
  trap 'rm -rf "$T"' EXIT
  mk() {  # $1 dir: a minimal release fixture, committed with the release subject
    local d=$1
    mkdir -p "$d/plugins/session/.claude-plugin" "$d/.claude-plugin"
    printf '{\n  "name": "session",\n  "version": "%s"\n}\n' "$REL" > "$d/plugins/session/.claude-plugin/plugin.json"
    printf '{\n  "plugins": [{"name": "session", "version": "%s"}]\n}\n' "$REL" > "$d/.claude-plugin/marketplace.json"
    cat > "$d/plugins/session/README.md" <<EOF
# session
## The 0.16 set
Workflows session:role, session:chain, session:make, session:probe.
Tests: tests/rebuild/all.sh and tests/workflows/usage-test.sh.
## Version log
$REL: rebuild.
0.15.9: previous.
0.15.8: older.
EOF
    git -C "$d" init -q && git -C "$d" add -A &&
      git -C "$d" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm "session $REL: fixture" || return 1
  }
  sf=0
  mk "$T/ok" || { echo "release-gate selftest: FAIL fixture setup"; exit 1; }
  if gate "$T/ok" >/dev/null; then :; else echo "FAIL selftest: clean release fixture must pass"; gate "$T/ok"; sf=$((sf + 1)); fi
  # mutation 1: a dirty tree must fail
  mk "$T/dirty" && echo x >> "$T/dirty/plugins/session/README.md"
  if gate "$T/dirty" >/dev/null; then echo "FAIL selftest: dirty tree passed"; sf=$((sf + 1)); fi
  # mutation 2: an untracked file is dirt too
  mk "$T/untracked" && echo x > "$T/untracked/stray.txt"
  if gate "$T/untracked" >/dev/null; then echo "FAIL selftest: untracked file passed"; sf=$((sf + 1)); fi
  # mutation 3: a wrong HEAD subject must fail
  mk "$T/subj" && echo y > "$T/subj/y" && git -C "$T/subj" add y &&
    git -C "$T/subj" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm "later change"
  if gate "$T/subj" >/dev/null; then echo "FAIL selftest: wrong subject passed"; sf=$((sf + 1)); fi
  if [ "$sf" -eq 0 ]; then echo "release-gate selftest: PASS 4"; exit 0; fi
  echo "release-gate selftest: FAIL $sf"; exit 1
fi

REPO=${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}
gate "$REPO"
