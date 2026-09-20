#!/bin/sh
# Retired in P6 of the 0.16 rebuild: bin/build.sh generates skills/base/SKILL.md from base/BASE.md,
# with the frontmatter of lib/build-manifest.json. The file itself is deleted in P9; until then it
# writes nothing, because a run of the old generator would revert the frontmatter of the generated
# skill and turn `bin/build.sh --check` red.
echo "base/split.sh is retired: run bin/build.sh (or bin/build.sh --check) instead" >&2
exit 2
