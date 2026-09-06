#!/bin/sh
# Regenerates base/BASE-<n>.md from base/BASE.md, splitting at `<!-- part -->` lines.
# Each part, wrapped in the hook's JSON envelope, must stay under 9,000 characters:
# Claude Code persists a hook additionalContext over 10,000 characters to a file and
# the model sees only a pointer. Run after every edit of BASE.md.
set -e
DIR=$(cd "$(dirname "$0")" && pwd)
python3 - "$DIR" <<'PY'
import json, sys, os, glob
d = sys.argv[1]
text = open(os.path.join(d, 'BASE.md'), encoding='utf-8').read()
parts = [p.strip('\n') + '\n' for p in text.split('<!-- part -->\n')]
n = len(parts)
for old in glob.glob(os.path.join(d, 'BASE-*.md')):
    os.remove(old)
for i, p in enumerate(parts, 1):
    if i > 1:
        p = f'# Session base, part {i} of {n}\n\n' + p
    size = len(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": p}}))
    if size > 9000:
        sys.exit(f'BASE-{i}.md envelope is {size} chars, cap 9000: move a <!-- part --> marker')
    open(os.path.join(d, f'BASE-{i}.md'), 'w', encoding='utf-8').write(p)
    print(f'BASE-{i}.md {len(p)} chars, envelope {size}')
PY
