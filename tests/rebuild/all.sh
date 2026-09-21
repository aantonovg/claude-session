#!/bin/bash
# Runs every static test of tests/rebuild/ that exists at this moment, in order, and stops at none:
# it reports each result and fails when any failed. stale.sh and verdicts.sh are left out, they
# take arguments and are called by the part that owns them. switch-user.sh runs in its --selftest
# mode: that mode patches fixtures in a temporary directory of its own and touches no user-level
# file, so "a patch reaches its file only when all of it applied" is executed by every run here.
# From P6 on text.sh always runs with --with-base: the base text is rewritten, so it is part of the
# no-model rule like every other text of the new set. The flag is still accepted and changes
# nothing, so an older command line keeps working.
#   tests/rebuild/all.sh [--with-base]
set -u

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WITH_BASE=--with-base
for a in "$@"; do
  case $a in
    --with-base) WITH_BASE=--with-base ;;
    *) echo "all.sh: unknown option $a" >&2; exit 2 ;;
  esac
done

ORDER="build-sync agents text contracts roles chain stages hooks resume carrier-free toolplugin waits switch-user"
ran=0; failed=

for t in $ORDER; do
  f=$HERE/$t.sh
  [ -f "$f" ] || continue
  ran=$((ran + 1))
  if [ "$t" = text ] && [ -n "$WITH_BASE" ]; then
    bash "$f" "$WITH_BASE"; rc=$?
  elif [ "$t" = switch-user ]; then
    bash "$f" --selftest; rc=$?
  else
    bash "$f"; rc=$?
  fi
  [ "$rc" -eq 0 ] || failed="$failed $t"
done

if [ "$ran" -eq 0 ]; then echo "all: FAIL no test found in $HERE"; exit 1; fi
if [ -n "$failed" ]; then echo "all: FAIL$failed ($ran tests run)"; exit 1; fi
echo "all: PASS $ran tests"
