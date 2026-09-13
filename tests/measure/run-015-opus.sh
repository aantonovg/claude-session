#!/bin/bash
# 0.15 matrix runner for opus-medium; writes to OUT and touches OUT/done
export MODEL=opus EFFORT=medium REPEAT=1 OUT=/Users/aleksandr.antonov/.claude/jobs/b6440034/tmp/bt15-opus-medium
exec "$(dirname "$0")/basecls-run.sh" S1 S2 S3 S4 S5 S6 S7 S8 S9
