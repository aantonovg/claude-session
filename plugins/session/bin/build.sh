#!/bin/bash
# Build step of the session plugin: one source, many copies.
#
#   bin/build.sh              renders lib/block.js, stamps every target of lib/build-manifest.json
#   bin/build.sh --check      writes nothing, exits non-zero on any drift, names the file
#   bin/build.sh [--check] <file> ...   same over the named files only (fixtures, one workflow)
#
# What it renders:
#   lib/block.js   = lib/block.src.js with the table of lib/classes.json at the class-table marker
#   a target file  = its generated regions replaced, by marker pair:
#     "// ---- shared block" ... "// ---- end shared block"   the text of lib/block.js
#     "<!-- class table"     ... "<!-- end class table"       the class table as a markdown table
#   a "fromBase" target = the frontmatter of its manifest entry plus the whole body of the file it
#     names, after that file was stamped in this same run (skills/base/SKILL.md from base/BASE.md).
#     It carries no markers of its own and is never hand-edited.
# A manifest key ("block", "table") whose marker pair is missing from the target is an error, never
# a silent skip. A "fromBase" target that stands on disk while its source is gone is an error. A
# hand edit inside a generated region is lost at the next build; --check catches it before a commit.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
PLUGIN=$(cd "$HERE/.." && pwd)
exec python3 - "$PLUGIN" "$@" <<'PY'
import json, os, sys

plugin = sys.argv[1]
argv = sys.argv[2:]
check = '--check' in argv
bad = [a for a in argv if a.startswith('--') and a != '--check']
if bad:
    print('build.sh: unknown option %s' % bad[0]); sys.exit(2)
files = [a for a in argv if not a.startswith('--')]

lib = os.path.join(plugin, 'lib')
src_path = os.path.join(lib, 'block.src.js')
gen_path = os.path.join(lib, 'block.js')
classes = json.load(open(os.path.join(lib, 'classes.json'), encoding='utf-8'))
mpath = os.path.join(lib, 'build-manifest.json')
manifest = json.load(open(mpath, encoding='utf-8'))['targets']

drift = []
wrote = []


def region(text, begin, end, path):
    lines = text.split('\n')
    b = e = None
    for i, l in enumerate(lines):
        s = l.strip()
        if b is None and s.startswith(begin):
            b = i
        elif b is not None and s.startswith(end):
            e = i
            break
    if b is None:
        return None
    if e is None:
        print('build.sh: %s has %s without %s' % (path, begin, end)); sys.exit(2)
    return lines[:b + 1], lines[e:]


def put(text, begin, end, body, path):
    r = region(text, begin, end, path)
    if r is None:
        return text, False
    before, after = r
    return '\n'.join(before + body + after), True


def render_table():
    keys = classes['submodeKeys']
    out = ['| class | ' + ' | '.join(keys) + ' |', '|' + '---|' * (len(keys) + 1)]
    for cls in sorted(classes['table']):
        row = classes['table'][cls]
        out.append('| %s | %s |' % (cls, ' | '.join(' / '.join(row[k].split('/')) for k in keys)))
    fixed = classes.get('fixedCells') or {}
    if fixed:
        seats = []
        for seat in sorted(fixed):
            cells = fixed[seat]
            bits = ['%s %s' % (seat, cells[k]) if k == 'none' else 'under %s %s' % (k, cells[k])
                    for k in keys if k in cells]
            seats.append(', '.join(bits))
        out += ['', 'Fixed seats, which no class and no slot argument move: ' + '; '.join(seats)
                + '. The longest matching submode row wins.']
    return out


def render_block():
    src = open(src_path, encoding='utf-8').read()
    body = ['const CLASSES = ' + json.dumps(classes, indent=2, ensure_ascii=False)]
    text, found = put(src, '// ---- class table', '// ---- end class table', body, src_path)
    if not found:
        print('build.sh: %s has no class-table marker' % src_path); sys.exit(2)
    return text


def emit(path, text):
    old = open(path, encoding='utf-8').read() if os.path.exists(path) else None
    if old == text:
        return
    if check:
        drift.append(path)
        return
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, 'w', encoding='utf-8').write(text)
    wrote.append(path)


def norm(p):
    return os.path.normpath(os.path.realpath(os.path.abspath(p)))


block = render_block()
emit(gen_path, block)
block_body = block.rstrip('\n').split('\n')

by_path = {norm(os.path.join(plugin, t['path'])): t for t in manifest}
if files:
    unknown = [f for f in files if norm(f) not in by_path]
    if unknown:
        print('build.sh: %s is no target of %s' % (unknown[0], mpath)); sys.exit(2)
    targets = [(os.path.abspath(f), by_path[norm(f)]) for f in files]
    named = set(norm(f) for f in files)
    # a fromBase target travels with its source in both directions, so --check over either side
    # of a stale pair can never print clean
    for t in manifest:
        fb = t.get('fromBase')
        if not fb:
            continue
        tp = norm(os.path.join(plugin, t['path']))
        sp = norm(os.path.join(plugin, fb))
        if sp in named and tp not in named:
            targets.append((os.path.join(plugin, t['path']), t)); named.add(tp)
        elif tp in named and sp not in named and sp in by_path:
            targets.append((os.path.join(plugin, fb), by_path[sp])); named.add(sp)
else:
    targets = [(os.path.join(plugin, t['path']), t) for t in manifest]

rendered = {}
for path, spec in targets:
    if spec.get('fromBase'):
        continue
    if not os.path.exists(path):
        print('build.sh: no such file %s' % path); sys.exit(2)
    text = open(path, encoding='utf-8').read()
    out = text
    out, found = put(out, '// ---- shared block', '// ---- end shared block', block_body, path)
    if spec.get('block') and not found:
        print('build.sh: %s declares block, but carries no shared-block marker' % path); sys.exit(2)
    out, found = put(out, '<!-- class table', '<!-- end class table', render_table(), path)
    if spec.get('table') and not found:
        print('build.sh: %s declares table, but carries no class-table marker' % path); sys.exit(2)
    rendered[norm(path)] = out
    emit(path, out)

for path, spec in targets:
    fb = spec.get('fromBase')
    if not fb:
        continue
    src = os.path.join(plugin, fb)
    if not os.path.exists(src):
        print('build.sh: %s names the missing source %s' % (path, src)); sys.exit(2)
    body = rendered.get(norm(src))
    if body is None:
        body = open(src, encoding='utf-8').read()
    front = spec.get('frontmatter')
    if not front:
        print('build.sh: %s declares fromBase without a frontmatter list' % path); sys.exit(2)
    emit(path, '---\n' + '\n'.join(front) + '\n---\n\n' + body.strip('\n') + '\n')

if check:
    if drift:
        for p in drift:
            print('build.sh --check: out of date: %s' % p)
        sys.exit(1)
    print('build.sh --check: clean')
    sys.exit(0)
print('build.sh: wrote %d file(s)%s' % (len(wrote), (': ' + ' '.join(wrote)) if wrote else ''))
PY
