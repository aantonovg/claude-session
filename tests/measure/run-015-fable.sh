#!/bin/bash
# 0.15 matrix runner for fable-medium; writes to OUT and touches OUT/done
export MODEL=fable EFFORT=medium REPEAT=1 OUT=/Users/aleksandr.antonov/.claude/jobs/b6440034/tmp/bt15-fable-medium
exec "$(dirname "$0")/basecls-run.sh" S1 S4 S6
