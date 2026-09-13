#!/bin/bash
export MODEL=opus EFFORT=medium REPEAT=1 OUT=/Users/aleksandr.antonov/.claude/jobs/b6440034/tmp/bt15b-opus-medium
exec "$(dirname "$0")/basecls-run.sh" S1
