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
#     "// ---- roles"        ... "// ---- end roles"          that target's roles from lib/roles/
#     "// ---- aspects"      ... "// ---- end aspects"        that target's aspect paragraphs
# A file with none of these markers is skipped and stays byte-identical. A manifest target that
# does not exist yet is skipped; a file named on the command line must exist and must be a target
# of lib/build-manifest.json, so --check over a file this build step does not own can never print
# clean over a stale region. A manifest key
# ("block", "table", "roles", "aspects") whose marker pair is missing from the target is an error,
# never a silent skip. A hand edit inside a generated region is lost at the next build; --check
# catches it before a commit.
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
manifest = json.load(open(mpath, encoding='utf-8'))['targets'] if os.path.exists(mpath) else []

drift = []
wrote = []


def region(text, begin, end, path):
    """Return (before, after) around the lines between the marker pair, or None when absent."""
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
    return out


def render_block():
    src = open(src_path, encoding='utf-8').read()
    body = ['const CLASSES = ' + json.dumps(classes, indent=2, ensure_ascii=False)]
    text, found = put(src, '// ---- class table', '// ---- end class table', body, src_path)
    if not found:
        print('build.sh: %s has no class-table marker' % src_path); sys.exit(2)
    return text


def texts(kind, names):
    """JS object literal with one entry per named text file of lib/<kind>/ ("*" = all of them)."""
    d = os.path.join(lib, kind)
    if not os.path.isdir(d):
        return None
    if names == ['*']:
        names = sorted(f[:-3] for f in os.listdir(d) if f.endswith('.md'))
    body = ['const %s_TEXT = {' % kind[:-1].upper()]
    for n in names:
        p = os.path.join(d, n + '.md')
        if not os.path.exists(p):
            print('build.sh: %s names %s, missing %s' % (mpath, n, p)); sys.exit(2)
        body.append('  %s: %s,' % (json.dumps(n), json.dumps(open(p, encoding='utf-8').read())))
    body.append('}')
    return body


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


# 1. lib/block.js, the one generated copy of the hand-written source.
block = render_block()
emit(gen_path, block)
block_body = block.rstrip('\n').split('\n')

# 2. the targets: the named files, or every target of the manifest. A named file is matched to its
# manifest entry by full path, never by base name: a file called role.js outside the plugin must
# not inherit the role stamp of the plugin's own role.js.
def norm(p):
    return os.path.normpath(os.path.realpath(os.path.abspath(p)))


by_path = {}
for t in manifest:
    by_path[norm(os.path.join(plugin, t['path']))] = t
if files:
    # a named file must be a target of the manifest: an unknown file would get an empty spec, so
    # no roles/aspects key would be enforced and --check would print clean over a stale region
    unknown = [f for f in files if norm(f) not in by_path]
    if unknown:
        print('build.sh: %s is no target of %s' % (unknown[0], mpath)); sys.exit(2)
    targets = [(os.path.abspath(f), by_path[norm(f)]) for f in files]
else:
    targets = [(os.path.join(plugin, t['path']), t) for t in manifest]

for path, spec in targets:
    if not os.path.exists(path):
        # a manifest target of a later part is skipped; a file named on the command line is not,
        # so --check over a mistyped path can never exit 0 without checking anything
        if files:
            print('build.sh: no such file %s' % path); sys.exit(2)
        continue
    text = open(path, encoding='utf-8').read()
    out = text
    out, found = put(out, '// ---- shared block', '// ---- end shared block', block_body, path)
    if spec.get('block') and not found:
        print('build.sh: %s declares block, but carries no shared-block marker' % path); sys.exit(2)
    out, found = put(out, '<!-- class table', '<!-- end class table', render_table(), path)
    if spec.get('table') and not found:
        print('build.sh: %s declares table, but carries no class-table marker' % path); sys.exit(2)
    for kind, names in (('roles', spec.get('roles')), ('aspects', spec.get('aspects'))):
        if not names:
            continue
        body = texts(kind, list(names))
        if body is None:
            print('build.sh: %s declares %s, but %s is missing'
                  % (path, kind, os.path.join(lib, kind))); sys.exit(2)
        out, found = put(out, '// ---- %s' % kind, '// ---- end %s' % kind, body, path)
        if not found:
            print('build.sh: %s declares %s, but carries no %s marker' % (path, kind, kind))
            sys.exit(2)
    emit(path, out)

if check:
    if drift:
        for p in drift:
            print('build.sh --check: out of date: %s' % p)
        sys.exit(1)
    print('build.sh --check: clean')
    sys.exit(0)
print('build.sh: wrote %d file(s)%s' % (len(wrote), (': ' + ' '.join(wrote)) if wrote else ''))
PY
