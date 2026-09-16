#!/bin/sh
# Regenerates skills/base/SKILL.md from base/BASE.md (frontmatter + body).
# BASE.md is the single source of truth; run after every edit of it.
set -e
DIR=$(cd "$(dirname "$0")" && pwd)
python3 - "$DIR" <<'PY'
import sys, os
d = sys.argv[1]
body = open(os.path.join(d, 'BASE.md'), encoding='utf-8').read().strip('\n') + '\n'
front = ('---\n'
         'name: base\n'
         'description: "Session base: tools, cache, waits, models, roles. Invoke first in every session and again after /compact."\n'
         'disable-model-invocation: true\n'
         '---\n\n')
out = os.path.join(d, '..', 'skills', 'base', 'SKILL.md')
os.makedirs(os.path.dirname(out), exist_ok=True)
open(out, 'w', encoding='utf-8').write(front + body)
print(f'skills/base/SKILL.md {len(front + body)} chars')
PY
