#!/bin/bash
# Runs every static test of tests/rebuild/ that exists at this moment, in order, and stops at none:
# it reports each result and fails when any failed. stale.sh and verdicts.sh are left out, they
# take arguments and are called by the part that owns them.
#   tests/rebuild/all.sh [--with-base]     the flag is passed to text.sh only
set -u

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WITH_BASE=
for a in "$@"; do
  case $a in
    --with-base) WITH_BASE=--with-base ;;
    *) echo "all.sh: unknown option $a" >&2; exit 2 ;;
  esac
done

ORDER="build-sync agents text contracts roles chain stages hooks carrier-free toolplugin"
ran=0; failed=

for t in $ORDER; do
  f=$HERE/$t.sh
  [ -f "$f" ] || continue
  ran=$((ran + 1))
  if [ "$t" = text ] && [ -n "$WITH_BASE" ]; then
    bash "$f" "$WITH_BASE"; rc=$?
  else
    bash "$f"; rc=$?
  fi
  [ "$rc" -eq 0 ] || failed="$failed $t"
done

if [ "$ran" -eq 0 ]; then echo "all: FAIL no test found in $HERE"; exit 1; fi
if [ -n "$failed" ]; then echo "all: FAIL$failed ($ran tests run)"; exit 1; fi
echo "all: PASS $ran tests"
