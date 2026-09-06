#!/usr/bin/env bash
# Score one finished run. Usage: score.sh <run-dir>
# Prints one key=value line per metric plus a guess of the session JSONL path.
set -uo pipefail

run_dir=${1:?usage: score.sh <run-dir>}
run_dir=$(cd "$run_dir" && pwd -P)
cd "$run_dir"

tests_pass=0 tests_fail=0
if compgen -G "tests/*.test.js" > /dev/null; then
  out=$(node --test tests/*.test.js 2>&1 | sed $'s/\x1b\\[[0-9;]*m//g' || true)
  tests_pass=$(printf '%s\n' "$out" | grep -E '^(#|ℹ) pass' | sed -E 's/^[^0-9]*([0-9]+).*/\1/' | tail -1)
  tests_fail=$(printf '%s\n' "$out" | grep -E '^(#|ℹ) fail' | sed -E 's/^[^0-9]*([0-9]+).*/\1/' | tail -1)
  tests_pass=${tests_pass:-0} tests_fail=${tests_fail:-0}
fi

commits=$(git rev-list --count HEAD 2>/dev/null || echo 0)
src_files=$(find src -name '*.js' 2>/dev/null | wc -l | tr -d ' ')
js_lines=$(find src tests -name '*.js' 2>/dev/null -exec cat {} + | wc -l | tr -d ' ')
[[ -f index.html ]] && has_index=1 || has_index=0
[[ -f README.md ]] && has_readme=1 || has_readme=0

check_ok=1
while IFS= read -r f; do
  node --check "$f" 2>/dev/null || check_ok=0
done < <(find src -name '*.js' 2>/dev/null)
[[ $src_files -eq 0 ]] && check_ok=0

encoded=$(printf '%s' "$run_dir" | sed 's/[^A-Za-z0-9-]/-/g')
jsonl=$(ls -t ~/.claude/projects/"$encoded"/*.jsonl 2>/dev/null | head -1)

echo "run=$run_dir"
echo "tests_pass=$tests_pass tests_fail=$tests_fail commits=$commits src_files=$src_files js_lines=$js_lines index_html=$has_index readme=$has_readme node_check_ok=$check_ok"
echo "jsonl=${jsonl:-not-found}"
