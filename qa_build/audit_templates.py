import os, io, sys
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
root = os.getcwd()
SEP = chr(92)

real = set()
for dirpath, dirnames, filenames in os.walk(root):
    if '.godot' in dirpath or '.git' in dirpath:
        continue
    d = os.path.relpath(dirpath, root).replace(SEP, '/')
    if d != '.':
        real.add(d)
    for f in filenames:
        real.add(os.path.relpath(os.path.join(dirpath, f), root).replace(SEP, '/'))
lower = {r.lower(): r for r in real}

RACES = ['humans']
COLORS = ['Black', 'Blue', 'Purple', 'Red', 'Yellow']
UNIT_SUB = ['Lancer', 'Archer', 'Pawn', 'Warrior', 'Monk']
BUILDINGS = ['Castle', 'Barracks', 'Archery', 'Monastery', 'House1', 'House2', 'House3', 'Tower']
PROCESS = ['Castle_Construction', 'Castle_Destroyed', 'House_Construction', 'House_Destroyed']

cases = []
for r in RACES:
    for c in COLORS:
        for s in UNIT_SUB:
            cases.append(("_UNITS_ROOT", "assets/factions/%s/units/%s Units/%s" % (r, c, s)))
        for b in BUILDINGS:
            cases.append(("_BUILDINGS_ROOT", "assets/factions/%s/buildings/%s Buildings/%s.png" % (r, c, b)))
    for p in PROCESS:
        cases.append(("_PROCESS_ROOT", "assets/factions/%s/icons/buildings/process_building_destroeyrs/%s.png" % (r, p)))
    for f in ['units/archer', 'units/soldier_pack', 'units/spearman', 'units/worker', 'units/monk']:
        cases.append(("fallback", "assets/factions/%s/%s" % (r, f)))
    cases.append(("warrior_idle", "assets/factions/%s/units/soldier_pack/Warrior_Idle.png" % r))

missing, wrongcase = [], []
for tag, p in cases:
    if p in real:
        continue
    if p.lower() in lower:
        wrongcase.append((tag, p, lower[p.lower()]))
    else:
        missing.append((tag, p))

print("=== ШАБЛОННЫЙ ПУТЬ С НЕВЕРНЫМ РЕГИСТРОМ ===")
for t, p, r in wrongcase:
    print("  [%s] %s" % (t, p))
    print("        на диске: %s" % r)
if not wrongcase:
    print("  нет")
print("")
print("=== ШАБЛОННЫЙ ПУТЬ, КОТОРОГО НЕТ (проверь, что он под guard'ом) ===")
for t, p in missing:
    print("  [%s] %s" % (t, p))
if not missing:
    print("  нет")
