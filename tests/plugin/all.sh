#!/bin/bash
# Runs every static test of tests/plugin/ in order and stops at none; reports each result and
# fails when any failed. release-gate.sh runs in its --selftest mode only: the gate itself holds
# only at the release commit and is run once, by hand, right after it.
#   tests/plugin/all.sh
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ORDER="build-sync block agents contracts text hooks stale toolplugin release-gate"
ran=0; failed=
for t in $ORDER; do
  f=$HERE/$t.sh
  [ -f "$f" ] || continue
  ran=$((ran + 1))
  if [ "$t" = release-gate ]; then bash "$f" --selftest; rc=$?; else bash "$f"; rc=$?; fi
  [ "$rc" -eq 0 ] || failed="$failed $t"
done
if [ "$ran" -eq 0 ]; then echo "all: FAIL no test found in $HERE"; exit 1; fi
if [ -n "$failed" ]; then echo "all: FAIL$failed ($ran tests run)"; exit 1; fi
echo "all: PASS $ran tests"
