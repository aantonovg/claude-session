#!/bin/bash
# 0.15 matrix runner for sonnet-medium; writes to OUT and touches OUT/done
export MODEL=sonnet EFFORT=medium REPEAT=3 OUT=/Users/aleksandr.antonov/.claude/jobs/b6440034/tmp/bt15-sonnet-medium
exec "$(dirname "$0")/basecls-run.sh" S1 S2 S3 S4 S5 S6 S7 S8 S9
