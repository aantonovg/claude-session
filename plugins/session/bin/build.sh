#!/bin/bash
# Build step of the session plugin: one source, many copies.
#
#   bin/build.sh              renders lib/block.js, stamps every target of lib/build-manifest.json
#   bin/build.sh --check      writes nothing, exits non-zero on any drift, names the file
#   bin/build.sh [--check] <file> ...   same over the named files only (fixtures, one workflow)
#
# What it renders:
#   lib/block.js   = lib/block.src.js with the table of lib/classes.json at the class-table marker
#                    and the two tables of lib/task-layout.md at the task-layout marker
#   a target file  = its generated regions replaced, by marker pair:
#     "// ---- shared block" ... "// ---- end shared block"   the text of lib/block.js
#     "<!-- class table"     ... "<!-- end class table"       the class table as a markdown table
#     "// ---- roles"        ... "// ---- end roles"          that target's roles from lib/roles/
#     "// ---- aspects"      ... "// ---- end aspects"        that target's aspect paragraphs
#   a "fromBase" target = the frontmatter of its manifest entry plus the whole body of the file it
#     names, after that file was stamped in this same run (skills/base/SKILL.md from base/BASE.md).
#     It carries no markers of its own and is never hand-edited.
# A file with none of these markers is skipped and stays byte-identical. A manifest target that
# does not exist yet is skipped, with one exception: a "fromBase" target is generated whole out of
# its source, so its absence is drift, not a skip, and the skip of a later part is keyed on its
# source instead; a "fromBase" target that stands on disk while its source is gone is an error, so
# a deleted source can never leave a stale copy that --check calls clean. A file named on the
# command line must exist and must be a target of
# lib/build-manifest.json; a named file that is the source of a "fromBase" target drags that target
# into the same run, and a named "fromBase" target drags its source in the same way, so --check over
# a file this build step does not own, and --check over either side of a stale pair, can never print
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
    fixed = classes.get('fixedCells') or {}
    if fixed:
        # the fixed seats live inside the generated region too: a main session that reads the base
        # text sees the cell without opening lib/classes.json
        seats = []
        for seat in sorted(fixed):
            cells = fixed[seat]
            bits = ['%s %s' % (seat, cells[k]) if k == 'none' else 'under %s %s' % (k, cells[k])
                    for k in keys if k in cells]
            seats.append(', '.join(bits))
        out += ['', 'Fixed seats, which no class and no size move: ' + '; '.join(seats)
                + '. The longest matching submode row wins.']
    return out


def rows(text, begin, end, path):
    """The rows of one markdown table between a marker pair, header and separator dropped."""
    r = region(text, begin, end, path)
    if r is None:
        print('build.sh: %s has no %s marker' % (path, begin)); sys.exit(2)
    before, after = r
    body = text.split('\n')[len(before):len(text.split('\n')) - len(after)]
    out = []
    for l in body:
        s = l.strip()
        if not s.startswith('|'):
            continue
        cells = [c.strip() for c in s.strip('|').split('|')]
        if not cells or set(''.join(cells)) <= set('-: '):
            continue
        out.append(cells)
    if len(out) < 2:
        print('build.sh: %s carries no rows under %s' % (path, begin)); sys.exit(2)
    return out[1:]  # the first row is the header


def render_layout():
    """The two tables of lib/task-layout.md as the LAYOUT object of the shared block."""
    path = os.path.join(lib, 'task-layout.md')
    if not os.path.exists(path):
        print('build.sh: %s is missing' % path); sys.exit(2)
    text = open(path, encoding='utf-8').read()
    files = {}
    for cells in rows(text, '<!-- layout table', '<!-- end layout table', path):
        if len(cells) < 6:
            print('build.sh: %s: layout row with %d cells' % (path, len(cells))); sys.exit(2)
        key, rel, kind, lite = cells[0], cells[1], cells[2], cells[5]
        if kind not in ('file', 'dir', 'state'):
            print('build.sh: %s: unknown kind %s of %s' % (path, kind, key)); sys.exit(2)
        files[key] = {'path': rel, 'kind': kind, 'lite': lite}
    role_out = {}
    for cells in rows(text, '<!-- role output table', '<!-- end role output table', path):
        if len(cells) < 2:
            print('build.sh: %s: role row with %d cells' % (path, len(cells))); sys.exit(2)
        role, key = cells[0], cells[1]
        stem = cells[2] if len(cells) > 2 else ''
        if key not in files:
            print('build.sh: %s: role %s names the unknown key %s' % (path, role, key)); sys.exit(2)
        if files[key]['kind'] == 'dir' and not stem:
            print('build.sh: %s: role %s writes into the directory %s without a stem' % (path, role, key)); sys.exit(2)
        if files[key]['kind'] != 'dir' and stem:
            print('build.sh: %s: role %s names a stem for the file %s' % (path, role, key)); sys.exit(2)
        role_out[role] = {'key': key, 'stem': stem}
    return {'files': files, 'roleOut': role_out}


def render_block():
    src = open(src_path, encoding='utf-8').read()
    body = ['const CLASSES = ' + json.dumps(classes, indent=2, ensure_ascii=False)]
    text, found = put(src, '// ---- class table', '// ---- end class table', body, src_path)
    if not found:
        print('build.sh: %s has no class-table marker' % src_path); sys.exit(2)
    lay = ['const LAYOUT = ' + json.dumps(render_layout(), indent=2, ensure_ascii=False)]
    text, found = put(text, '// ---- task layout', '// ---- end task layout', lay, src_path)
    if not found:
        print('build.sh: %s has no task-layout marker' % src_path); sys.exit(2)
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
    # a fromBase target is carried along with the source it names, even when the command line
    # names only that source: `build.sh [--check] base/BASE.md` that left skills/base/SKILL.md
    # untouched would write a new base and print clean over a stale generated skill
    named = set(norm(f) for f in files)
    for t in manifest:
        fb = t.get('fromBase')
        tp = os.path.join(plugin, t['path'])
        if fb and norm(os.path.join(plugin, fb)) in named and norm(tp) not in named:
            targets.append((tp, t))
    # the other direction: naming the fromBase target alone drags its source in, so the source is
    # stamped in this same run instead of being read off disk — a hand edit inside the generated
    # region of the source would otherwise be published into the generated skill
    for t in manifest:
        fb = t.get('fromBase')
        if not fb or norm(os.path.join(plugin, t['path'])) not in named:
            continue
        sp = norm(os.path.join(plugin, fb))
        if sp in named or sp not in by_path:
            continue
        targets.append((os.path.join(plugin, fb), by_path[sp]))
        named.add(sp)
else:
    targets = [(os.path.join(plugin, t['path']), t) for t in manifest]

rendered = {}
for path, spec in targets:
    if spec.get('fromBase'):
        continue  # second pass: it reads a target stamped in this same run
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
    rendered[norm(path)] = out
    emit(path, out)

# 3. the fromBase targets: a generated skill file that is one source file under a frontmatter.
for path, spec in targets:
    fb = spec.get('fromBase')
    if not fb:
        continue
    src = os.path.join(plugin, fb)
    if not os.path.exists(src):
        # the skip rule of a later part, keyed on the source: a fromBase target is generated whole,
        # so its own absence is drift and never a skip, but a source nobody has written yet is the
        # target of a later part. A file named on the command line is never skipped, and a target
        # that already stands on disk is never skipped either: a deleted source with the generated
        # file left behind is a stale copy nobody can rebuild, so it is said out loud instead of
        # letting --check print clean over it.
        if files or os.path.exists(path):
            print('build.sh: %s names the missing source %s' % (path, src)); sys.exit(2)
        continue
    body = rendered.get(norm(src))
    if body is None:  # the source is not a target of this run: read what is on disk
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
