#!/bin/bash
export MODEL=sonnet EFFORT=medium REPEAT=1 OUT=/Users/aleksandr.antonov/.claude/jobs/b6440034/tmp/bt15b-sonnet-medium
exec "$(dirname "$0")/basecls-run.sh" S1 S3 S9
