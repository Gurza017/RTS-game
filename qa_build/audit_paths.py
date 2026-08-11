import os, re, io, sys

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')

root = os.getcwd()
SEP = chr(92)

real = {}
realdirs = {}
for dirpath, dirnames, filenames in os.walk(root):
    if '.godot' in dirpath or '.git' in dirpath:
        continue
    d = os.path.relpath(dirpath, root).replace(SEP, '/')
    if d != '.':
        realdirs[d.lower()] = d
    for f in filenames:
        p = os.path.relpath(os.path.join(dirpath, f), root).replace(SEP, '/')
        real[p.lower()] = p

# res:// внутри строкового литерала — берём всё до закрывающей кавычки
lit = re.compile(r'"(res://[^"]*)"' + "|'(res://[^']*)'")

bad, missing = [], []
for dirpath, dirnames, filenames in os.walk(root):
    if '.godot' in dirpath or '.git' in dirpath:
        continue
    for f in filenames:
        if not f.endswith(('.gd', '.tscn', '.godot', '.cfg')):
            continue
        fp = os.path.join(dirpath, f)
        try:
            txt = open(fp, encoding='utf-8').read()
        except Exception:
            continue
        for m in lit.finditer(txt):
            rel = (m.group(1) or m.group(2))[6:]
            if '%s' in rel or '%d' in rel or not rel:
                continue
            rel = rel.rstrip('/')
            key = rel.lower()
            src = os.path.relpath(fp, root).replace(SEP, '/')
            if key in real:
                if real[key] != rel:
                    bad.append((src, rel, real[key]))
            elif key in realdirs:
                if realdirs[key] != rel:
                    bad.append((src, rel, realdirs[key]))
            else:
                missing.append((src, rel))

print("=== NON-MATCHING CASE (breaks on case-sensitive FS) ===")
for f, w, r in sorted(set(bad)):
    print("  " + f)
    print("     code: " + w)
    print("     disk: " + r)
if not bad:
    print("  none")

print("")
print("=== PATH IN CODE, NOTHING ON DISK ===")
seen = set()
for f, w in sorted(set(missing)):
    if w in seen:
        continue
    seen.add(w)
    print("  " + w + "   <- " + f)
if not missing:
    print("  none")
