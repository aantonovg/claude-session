#!/bin/bash
# One-time gate of a release. Run once, right after the release commit, never as part of a standing
# suite: every check here holds only at the release commit (HEAD subject, the bump itself).
#   tests/plugin/release-gate.sh [repo]    gate the repo (default: this checkout)
#   tests/plugin/release-gate.sh --selftest   fixture test: a clean release fixture passes, a dirty
#                                             tree and a wrong subject each fail
set -u
REL=0.18.1
gate() {
  local repo=$1 n=0 fails=0
  local pj=$repo/plugins/session/.claude-plugin/plugin.json mj=$repo/.claude-plugin/marketplace.json rd=$repo/plugins/session/README.md
  ck() { local l=$1; shift; if "$@"; then n=$((n + 1)); else echo "FAIL $l"; fails=$((fails + 1)); fi; }
  ck "is a git work tree" git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1
  local st; st=$(git -C "$repo" status --porcelain 2>/dev/null) || st="git status failed"
  ck "tree clean" test -z "$st"
  ck "HEAD subject is 'session $REL: <summary>'" bash -c 'git -C "$1" log -1 --format=%s 2>/dev/null | grep -Eq "^session ${2//./\\.}: ."' _ "$repo" "$REL"
  ck "plugin.json version $REL" python3 -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1]))["version"]==sys.argv[2] else 1)' "$pj" "$REL"
  ck "marketplace.json session version $REL" python3 -c 'import json,sys; m=[p["version"] for p in json.load(open(sys.argv[1]))["plugins"] if p["name"]=="session"]; sys.exit(0 if m==[sys.argv[2]] else 1)' "$mj" "$REL"
  local rsec; rsec=$(awk '/^## The 0\.18 set/{f=1; print; next} f&&/^## /{exit} f{print}' "$rd" 2>/dev/null)
  ck "README section The 0.18 set" test -n "$rsec"
  ck "README 0.18 section names the two workflows" bash -c 'grep -q "session:helper" <<<"$1" && grep -q "session:batch" <<<"$1"' _ "$rsec"
  ck "README 0.18 section names tests/plugin/all.sh" grep -Fq 'tests/plugin/all.sh' <<<"$rsec"
  ck "README version log holds $REL once" test "$(grep -c "^$REL: " "$rd" 2>/dev/null)" = 1
  ck "README version log: $REL is the first line" bash -c 'awk "/^## Version log/{f=1; next} f&&/^[0-9]+\\.[0-9]+\\.[0-9]+: /{print; exit}" "$1" | grep -q "^$2: "' _ "$rd" "$REL"
  if [ "$fails" -eq 0 ]; then echo "release-gate: PASS $n"; return 0; fi
  echo "release-gate: FAIL $fails failures, $n checks passed"; return 1
}
if [ "${1:-}" = --selftest ]; then
  T=$(mktemp -d) || exit 1; trap 'rm -rf "$T"' EXIT
  mk() {
    local d=$1
    mkdir -p "$d/plugins/session/.claude-plugin" "$d/.claude-plugin"
    printf '{\n  "name": "session",\n  "version": "%s"\n}\n' "$REL" > "$d/plugins/session/.claude-plugin/plugin.json"
    printf '{\n  "plugins": [{"name": "session", "version": "%s"}]\n}\n' "$REL" > "$d/.claude-plugin/marketplace.json"
    printf '# session\n## The 0.18 set\nWorkflows session:helper and session:batch. Tests: tests/plugin/all.sh.\n## Version log\n%s: rebuild.\n0.17.1: previous.\n' "$REL" > "$d/plugins/session/README.md"
    git -C "$d" init -q && git -C "$d" add -A && git -C "$d" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm "session $REL: fixture" || return 1
  }
  sf=0
  mk "$T/ok" || { echo "release-gate selftest: FAIL fixture setup"; exit 1; }
  gate "$T/ok" >/dev/null || { echo "FAIL selftest: clean release fixture must pass"; gate "$T/ok"; sf=$((sf + 1)); }
  mk "$T/dirty" && echo x >> "$T/dirty/plugins/session/README.md"
  gate "$T/dirty" >/dev/null && { echo "FAIL selftest: dirty tree passed"; sf=$((sf + 1)); }
  mk "$T/subj" && echo y > "$T/subj/y" && git -C "$T/subj" add y && git -C "$T/subj" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -qm "later change"
  gate "$T/subj" >/dev/null && { echo "FAIL selftest: wrong subject passed"; sf=$((sf + 1)); }
  [ "$sf" -eq 0 ] && { echo "release-gate selftest: PASS 3"; exit 0; }
  echo "release-gate selftest: FAIL $sf"; exit 1
fi
gate "${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
