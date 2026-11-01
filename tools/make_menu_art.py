# -*- coding: utf-8 -*-
"""Фоновая иллюстрация главного меню и экрана загрузки (ТЗ 29.10.2026).

Композиция (ТЗ 29.10.2026, вечер — пересборка по скриншоту владельца):
зелёное поле под закатным небом, симметрично относительно рамы меню. Слева —
МАЛЫЙ замок (Blue Buildings/Castle.png ×1.8) и линия из четырёх башен
(Tower.png ×1.8-2.25) вниз-влево, СТЕНЫ НЕТ (в игре стен нет — только
башни); лучники ровно на верхних настилах, передний зубчатый край башни
поверх них. Вдоль линии башен — две плотные линии отрядов копейщиков
(Lancer, по четыре блока 10×5), лицом к орде; знамёна — картинки игры
(tools/menu_banners, выгружает qa_menu_ui/BannerDump: вымпелы рангов,
легенда, штандарт элиты). Справа — орда гоблинов с троллями и знамёнами орды,
косой фронт зеркален линии копейщиков; на нижнем фланге — клин
свиносадников орды (разворот «конницы нет вовсе» 29.10). Над полем — 130
стрел с башен и замка по всей полосе наступления. Заголовок и рама с
кнопками — узлы сцены (MainMenu.gd); середина кадра под рамой свободна.

ТЗ 30.10.2026, вечер (скриншот 19:45): три башни поменьше (по 10 лучников на
настиле), замок меньше и гуще гарнизон; отряды — фаланги (копья вверх, два
правых ряда — копья вперёд), передняя линия правее; знамёна людей — синие
вымпелы шкалы 30.10 (лычки белые/красные/золотые), знамёна орды ниже,
рваного штандарта легенды (его принимали за знамя Свинобосса) нет; орда
надвигается через середину поля, перед копейщиками — побоище: тела, стрелы
в земле, вытоптанная трава.

Случайность — своё зерно: повторный запуск даёт ту же картинку байт в байт.
Прежняя версия (закатный сумрак, кабаньи наездники) — в истории git.

Запуск из корня проекта:  python -X utf8 tools/make_menu_art.py
Итог: assets/ui/menu_background_castle.png (3840x2160).
"""
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter, ImageOps

W, H = 3840, 2160
SS = 2                      # суперсэмплинг векторных слоёв (стрелы, знамёна)
HORIZON = int(H * 0.56)
SEED = 1066
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HUM = os.path.join(ROOT, "assets", "factions", "humans")
GOB = os.path.join(ROOT, "assets", "factions", "Goblin")
ORC = os.path.join(ROOT, "assets", "factions", "orc", "Troll")
ENV = os.path.join(ROOT, "assets", "environment", "resources")
OUT = os.path.join(ROOT, "assets", "ui", "menu_background_castle.png")

rng = random.Random(SEED)


def lerp(a, b, t):
    return a + (b - a) * t


def lerp_col(c0, c1, t):
    return tuple(int(round(lerp(c0[i], c1[i], t))) for i in range(len(c0)))


def frames(path, fw, fh):
    sheet = Image.open(path).convert("RGBA")
    return [sheet.crop((i * fw, 0, (i + 1) * fw, fh)) for i in range(sheet.width // fw)]


def scaled(img, k, nearest=True):
    w = max(1, int(round(img.width * k)))
    h = max(1, int(round(img.height * k)))
    return img.resize((w, h), Image.NEAREST if nearest else Image.LANCZOS)


def grade(img, mul, add=(0, 0, 0), haze=None, haze_t=0.0):
    """Подкраска: множитель по каналам, прибавка, дымка к цвету дали."""
    r, g, b, a = img.split()
    chans = []
    for ch, m, ad, hz in zip((r, g, b), mul, add, haze or (0, 0, 0)):
        lut = []
        for v in range(256):
            x = v * m + ad
            if haze is not None:
                x = lerp(x, hz, haze_t)
            lut.append(int(max(0, min(255, x))))
        chans.append(ch.point(lut))
    return Image.merge("RGBA", (*chans, a))


def _foot_of(fr):
    """Низ непрозрачного (ноги) и середина фигуры по кадру"""
    bb = fr.getbbox() or (0, 0, fr.width, fr.height)
    return bb[3], (bb[0] + bb[2]) * 0.5


def no_swoosh(seq, max_w):
    """Кадры удара БЕЗ дуги взмаха: у кадра с дугой рамка непрозрачного
    заметно шире фигуры. На арте дуги сливались в кашу — берём узкие кадры"""
    out = []
    for f in seq:
        bb = f.getbbox()
        if bb is not None and bb[2] - bb[0] <= max_w:
            out.append(f)
    return out or seq


def draw_sorted(img, sprites):
    for y, spr, ox, oy in sorted(sprites, key=lambda e: e[0]):
        img.alpha_composite(spr, (ox, oy))


def glow(img, cx, cy, r, col, alpha):
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=col + (alpha,))
    layer = layer.filter(ImageFilter.GaussianBlur(r * 0.45))
    img.alpha_composite(layer)


# ── НЕБО, СОЛНЦЕ, ГОРЫ ──────────────────────────────────────────────────────
def sky():
    img = Image.new("RGBA", (W, H))
    stops = [(0.00, (24, 20, 46)), (0.28, (74, 36, 66)), (0.55, (170, 72, 54)),
             (0.80, (240, 140, 66)), (1.00, (252, 206, 118))]
    px = ImageDraw.Draw(img)
    for y in range(HORIZON):
        t = y / HORIZON
        for i in range(len(stops) - 1):
            if stops[i][0] <= t <= stops[i + 1][0]:
                k = (t - stops[i][0]) / (stops[i + 1][0] - stops[i][0])
                px.line([(0, y), (W, y)], fill=lerp_col(stops[i][1], stops[i + 1][1], k) + (255,))
                break
    px.rectangle([0, HORIZON, W, H], fill=(70, 120, 50, 255))
    return img


def sun(img):
    cx, cy = int(W * 0.72), int(HORIZON - H * 0.20)
    r = int(H * 0.065)
    glow(img, cx, cy, int(r * 5.0), (255, 150, 70), 90)
    glow(img, cx, cy, int(r * 2.2), (255, 190, 110), 140)
    d = ImageDraw.Draw(img)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(255, 222, 150, 255))
    d.ellipse([cx - r * 0.8, cy - r * 0.8, cx + r * 0.8, cy + r * 0.8], fill=(255, 238, 185, 255))


def clouds(img):
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for i in range(11):
        y = H * rng.uniform(0.06, 0.38)
        x0 = W * rng.uniform(-0.15, 0.95)
        ln = W * rng.uniform(0.16, 0.36)
        th = H * rng.uniform(0.010, 0.024)
        col = (80, 40, 70, 140) if y < H * 0.26 else (235, 130, 85, 95)
        pts = []
        n = 24
        for k in range(n + 1):
            u = k / n
            pts.append((x0 + ln * u, y - th * math.sin(u * math.pi) * (1 + 0.3 * math.sin(u * 9 + i))))
        for k in range(n, -1, -1):
            u = k / n
            pts.append((x0 + ln * u, y + th * 0.5 * math.sin(u * math.pi)))
        d.polygon(pts, fill=col)
    img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(6)))


def ridge(img, base_y, amp, col, steps):
    d = ImageDraw.Draw(img)
    pts = [(0, HORIZON + 8)]
    for i in range(steps + 1):
        x = W * i / steps
        pts.append((x, base_y - amp * (0.3 + 0.7 * abs(math.sin(i * 1.7 + rng.random() * 2)))))
        if i < steps:
            pts.append((x + W / steps * 0.5, base_y - amp * rng.uniform(0.0, 0.35)))
    pts.append((W, HORIZON + 8))
    d.polygon(pts, fill=col + (255,))


def mist(img, y, th, col, alpha):
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for k in range(int(th * 2)):
        t = 1.0 - abs(k - th) / th
        d.line([(0, y - th + k), (W, y - th + k)], fill=col + (int(alpha * t * t),))
    img.alpha_composite(layer)


# ── ЗЕЛЁНОЕ ПОЛЕ ────────────────────────────────────────────────────────────
def field(img):
    """Луг: волнистая кромка холмов у горизонта, градиент от выжженного
    закатом жёлто-зелёного вдали к сочной зелени внизу, пятна травы."""
    d = ImageDraw.Draw(img)
    top = HORIZON - int(H * 0.02)
    pts = [(0, H)]
    n = 18
    for i in range(n + 1):
        x = W * i / n
        pts.append((x, top + H * 0.012 + math.sin(i * 1.3 + rng.random() * 0.8) * H * 0.010))
    pts.append((W, H))
    d.polygon(pts, fill=(178, 186, 98, 255))
    g0 = top + int(H * 0.025)
    for y in range(g0, H):
        t = (y - g0) / (H - g0)
        if t < 0.55:
            c = lerp_col((172, 182, 96), (100, 150, 62), t / 0.55)
        else:
            c = lerp_col((100, 150, 62), (66, 114, 46), (t - 0.55) / 0.45)
        d.line([(0, y), (W, y)], fill=c + (255,))
    # пятна травы — темнее и светлее, крупнее к переднему плану
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    for i in range(260):
        y = rng.uniform(g0, H)
        t = (y - g0) / (H - g0)
        x = rng.uniform(-100, W + 100)
        rx = lerp(40, 260, t) * rng.uniform(0.6, 1.4)
        ry = rx * rng.uniform(0.18, 0.32)
        dark = rng.random() < 0.55
        col = (48, 96, 36, 70) if dark else (150, 196, 84, 55)
        ld.ellipse([x - rx, y - ry, x + rx, y + ry], fill=col)
    img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(14)))
    # стебли на переднем плане
    sd = ImageDraw.Draw(img)
    for i in range(900):
        y = rng.uniform(H * 0.72, H + 10)
        x = rng.uniform(0, W)
        ln = rng.uniform(8, 22)
        sd.line([(x, y), (x + rng.uniform(-4, 4), y - ln)], fill=(52, 104, 40, 170), width=2)
    # закатная дымка над дальним полем
    mist(img, HORIZON + H * 0.02, H * 0.045, (248, 190, 120), 80)


def hill(img, cx, cy, rx, ry):
    """Светлый холм под крепостью"""
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(layer).ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=(150, 190, 92, 150))
    img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(40)))


# ── ЛЕС У ГОРИЗОНТА ─────────────────────────────────────────────────────────
TREES = [frames(os.path.join(ENV, "Tree1.png"), 192, 256),
         frames(os.path.join(ENV, "Tree2.png"), 192, 256),
         frames(os.path.join(ENV, "Tree3.png"), 192, 192),
         frames(os.path.join(ENV, "Tree4.png"), 192, 192)]


def forest(img, x0, x1, n):
    sprites = []
    band = H * 0.05
    for i in range(n):
        x = rng.uniform(x0, x1)
        y = HORIZON + rng.uniform(-0.004, 1.0) * band
        t = (y - HORIZON) / band
        kind = rng.randrange(4)
        fr = TREES[kind][rng.randrange(len(TREES[kind]))]
        k = lerp(1.0, 1.7, t) * rng.uniform(0.9, 1.1)
        spr = grade(scaled(fr, k), (1.0, 0.94, 0.86), haze=(236, 160, 100), haze_t=lerp(0.42, 0.18, t))
        foot, mid = _foot_of(fr)
        sprites.append((y, spr, int(x - mid * k), int(y - foot * k)))
    draw_sorted(img, sprites)


# ── КРЕПОСТЬ: МАЛЫЙ ЗАМОК И ЛИНИЯ БАШЕН, ЛУЧНИКИ НА НАСТИЛАХ ───────────────
# Стен в игре нет — только башни (ТЗ 29.10.2026, вечер): замок и башни
# уменьшены в 1.75 раза против прежней заставки и соразмерны отрядам
CASTLE = Image.open(os.path.join(HUM, "buildings", "Blue Buildings", "Castle.png")).convert("RGBA")
TOWER = Image.open(os.path.join(HUM, "buildings", "Blue Buildings", "Tower.png")).convert("RGBA")
ARCHER = frames(os.path.join(HUM, "units", "Blue Units", "Archer", "Archer_Shoot.png"), 192, 192)
ARCHER_FOOT, ARCHER_CX = 136, 96
CASTLE_FOOT, CASTLE_CX = 249, 160
TOWER_FOOT, TOWER_CX = 230, 64
TOWER_RIM = (116, 142)      # передний зубчатый край башни по y спрайта — поверх лучников
# места лучников на настиле: три ряда, 10 человек (ТЗ 30.10.2026)
TOWER_DECK = [(44, 86), (58, 84), (72, 84), (86, 86),
              (38, 95), (52, 94), (66, 93), (80, 94), (94, 95),
              (64, 103)]
BLD_MUL = (0.98, 0.92, 0.88)
BLD_ADD = (12, 4, -4)
CASTLE_K = 1.55
# Линия башен: подножие (доли кадра) и масштаб — от замка вниз-влево; три
# башни, мельче прежних четырёх (ТЗ 30.10.2026)
TOWERS = [(0.178, 0.628, 1.50), (0.136, 0.718, 1.65), (0.092, 0.808, 1.80)]


def _archer(fr, k):
    return grade(scaled(fr, k), (0.96, 0.90, 0.88), add=(8, 0, -4))


def fortress(img):
    """Малый замок на холме и линия башен с лучниками на верхних настилах.
    Возвращает точки выстрела (верх каждой башни и настил замка)."""
    shots = []
    kc = CASTLE_K
    cas = grade(scaled(CASTLE, kc), BLD_MUL, add=BLD_ADD)
    cx, cy = W * 0.080, H * 0.590
    hill(img, cx + W * 0.06, cy + H * 0.02, W * 0.20, H * 0.08)
    sh = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sh)
    sd.ellipse([cx - cas.width * 0.45, cy - 50, cx + cas.width * 0.45, cy + 24], fill=(10, 30, 10, 150))
    for fx, fy, kt in TOWERS:
        x, y = W * fx, H * fy
        sd.ellipse([x - 70 * kt, y - 14 * kt, x + 90 * kt, y + 16 * kt], fill=(10, 30, 10, 140))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(22)))
    left, top = int(cx - CASTLE_CX * kc), int(cy - CASTLE_FOOT * kc)
    img.alpha_composite(cas, (left, top))
    # лучники на настиле замка (координаты — пиксели спрайта), ровными рядами
    ak = 0.56
    for row, (y, xs) in enumerate([(92, range(50, 300, 28)), (106, range(62, 292, 30)),
                                   (122, range(74, 280, 32))]):
        for j, x in enumerate(xs):
            if 146 < x < 174 and row == 0:
                continue
            fr = ARCHER[(j * 2 + row) % len(ARCHER)]
            img.alpha_composite(_archer(fr, ak), (int(left + x * kc - ARCHER_CX * ak),
                                                  int(top + y * kc - ARCHER_FOOT * ak)))
            shots.append((left + x * kc, top + (y - 40) * kc))
    rim = cas.crop((0, int(128 * kc), cas.width, int(150 * kc)))
    img.alpha_composite(rim, (left, top + int(128 * kc)))
    # башни: сзади вперёд; на каждой — лучники в бойницах, передний край поверх
    for fx, fy, kt in TOWERS:
        x, y = W * fx, H * fy
        tw = grade(scaled(TOWER, kt), BLD_MUL, add=BLD_ADD)
        tl, tt = int(x - TOWER_CX * kt), int(y - TOWER_FOOT * kt)
        img.alpha_composite(tw, (tl, tt))
        ak = kt * 0.30
        for j, (dx, dy) in enumerate(TOWER_DECK):
            fr = ARCHER[(j * 3 + int(fy * 10)) % len(ARCHER)]
            img.alpha_composite(_archer(fr, ak), (int(tl + dx * kt - ARCHER_CX * ak),
                                                  int(tt + dy * kt - ARCHER_FOOT * ak)))
            shots.append((tl + dx * kt, tt + (dy - 30) * kt))
        r0, r1 = TOWER_RIM
        img.alpha_composite(tw.crop((0, int(r0 * kt), tw.width, int(r1 * kt))), (tl, tt + int(r0 * kt)))
    return shots


# ── ЗНАМЁНА ОТРЯДОВ — КАРТИНКИ ИЗ ИГРЫ ───────────────────────────────────────
# tools/menu_banners/*.png выгружает qa_menu_ui/BannerDump (BannerArt игры:
# вымпелы рангов 1-6, легенда, штандарт элиты, знамёна орды) — флажки на
# заставке те же, что над отрядами в партии. Перевыгрузка после правки
# BannerArt: <godot> --headless --path . res://qa_menu_ui/BannerDump.tscn
BANNER_DIR = os.path.join(ROOT, "tools", "menu_banners")


def _banner(name):
    im = Image.open(os.path.join(BANNER_DIR, name + ".png")).convert("RGBA")
    a = im.split()[3].load()
    y0 = int(im.height * 0.75)
    runs = [sum(1 for y in range(y0, im.height) if a[x, y] > 0) for x in range(im.width)]
    best = max(runs)
    xs = [x for x in range(im.width) if runs[x] >= best * 0.9]
    bot = max(y for y in range(im.height) if any(a[x, y] > 0 for x in xs))
    return im, (min(xs) + max(xs) + 1) * 0.5, bot + 1


BANNERS = {n: _banner(n) for n in
           ["human_%d" % i for i in range(1, 10)] + ["human_legend", "human_elite"]
           + ["goblin_%d" % i for i in range(1, 7)] + ["goblin_legend"]}


def banner(sprites, name, x, foot_y, k, haze_t, sort_y=None):
    """Знамя из игры: низ древка — в (x, foot_y); масштаб k — пиксель холста"""
    im, pcx, bot = BANNERS[name]
    spr = grade(scaled(im, k), (1.0, 0.97, 0.95), haze=(236, 160, 100), haze_t=haze_t)
    sprites.append((foot_y if sort_y is None else sort_y, spr, int(x - pcx * k), int(foot_y - bot * k)))


# ── ОТРЯДЫ КОПЕЙЩИКОВ: ПЛОТНЫЕ БЛОКИ ЛИНИЕЙ ВДОЛЬ БАШЕН ──────────────────────
LANCER = frames(os.path.join(HUM, "units", "Blue Units", "Lancer", "Lancer_Idle.png"), 320, 320)
LANCER_FOOT = 198          # низ ног в кадре (bbox 48..198)
LANCER_CX = 150            # ось фигуры в кадре
LANCER_TIP = 48            # остриё копья
LANCER_POSES = {
    "right": (frames(os.path.join(HUM, "units", "Blue Units", "Lancer", "Lancer_Right_Defence.png"), 320, 320),
              frames(os.path.join(HUM, "units", "Blue Units", "Lancer", "Lancer_Right_Attack.png"), 320, 320)),
    "downright": (frames(os.path.join(HUM, "units", "Blue Units", "Lancer", "Lancer_DownRight_Defence.png"), 320, 320),
                  frames(os.path.join(HUM, "units", "Blue Units", "Lancer", "Lancer_DownRight_Attack.png"), 320, 320)),
}


def block(sprites, cx, foot_y, cols, rows, k, mul, haze, haze_t, flag, pose="idle"):
    """Плотный прямоугольный отряд: ряды сзади вперёд со сдвигом по глубине,
    одно знамя из игры за центром. pose: "idle" — копья вверх у всех;
    "right"/"downright" — ФАЛАНГА (ТЗ 30.10.2026): копья вверх у всех, кроме
    двух правых колонок — у тех копья к врагу (Defence)"""
    sx = 44 * k
    sy = 24 * k
    lean = 14 * k
    width = (cols - 1) * sx
    for r in range(rows - 1, -1, -1):
        ry = foot_y - r * sy
        rx = cx - width / 2 + r * lean
        t_row = haze_t + (r / max(1, rows - 1)) * 0.05
        for c in range(cols):
            if pose == "idle":
                fr = LANCER[(c * 5 + r * 3) % len(LANCER)]
            elif c < cols - 2:
                fr = LANCER[(c * 5 + r * 3) % len(LANCER)]
            else:
                defence, _attack = LANCER_POSES[pose]
                fr = defence[(c * 2 + r) % len(defence)]
            spr = grade(scaled(fr, k, nearest=k >= 0.99), mul, haze=haze, haze_t=min(1.0, t_row))
            x = rx + c * sx + rng.uniform(-2, 2) * k
            y = ry + rng.uniform(-2, 2) * k
            sprites.append((y, spr, int(x - LANCER_CX * k), int(y - LANCER_FOOT * k)))
    # знамя: древко над серединой отряда, выше копий
    mid = rows // 2
    banner(sprites, flag, cx + mid * lean, foot_y - mid * sy, 1.45 * k, haze_t)


# ── ОРДА: ГОБЛИНЫ, ТРОЛЛИ, СВИНОСАДНИКИ ─────────────────────────────────────
GOB_RUN = frames(os.path.join(GOB, "Spear Goblin_Run.png"), 256, 256)
GOB_ATK = no_swoosh(frames(os.path.join(GOB, "Spear Goblin_Attack Fast.png"), 256, 256), 125)
GOB_ATK2 = no_swoosh(frames(os.path.join(GOB, "Spear Goblin_Attack Strong.png"), 256, 256), 126)
PIG_RUN = frames(os.path.join(GOB, "Pig Rider_Run.png"), 256, 256)
TROLL_WALK = frames(os.path.join(ORC, "Troll_Walk.png"), 384, 384)
TROLL_ATK = no_swoosh(frames(os.path.join(ORC, "Troll_Attack.png"), 384, 384), 200)
GOB_MUL = (0.98, 0.94, 0.90)


def goblin_wave(sprites, x0, y0, x1, y1, n, k0, k1, front, haze_t=0.0, keep=None):
    """Толпа гоблинов в прямоугольнике, лицом ВЛЕВО (зеркально); масштаб
    растёт с y от k0 до k1. front(x, y) -> True: у фронта — кадр удара;
    keep(x, y) -> False: точка вне толпы (косой фронт, место конницы)"""
    placed = 0
    tries = 0
    while placed < n and tries < n * 6:
        tries += 1
        x = rng.uniform(x0, x1)
        y = rng.uniform(y0, y1)
        if keep is not None and not keep(x, y):
            continue
        placed += 1
        t = (y - y0) / max(1.0, y1 - y0)
        hit = front(x, y)
        seq = (GOB_ATK if rng.random() < 0.6 else GOB_ATK2) if hit else GOB_RUN
        fr = ImageOps.mirror(seq[rng.randrange(len(seq))])
        kk = lerp(k0, k1, t) * rng.uniform(0.94, 1.06)
        spr = grade(scaled(fr, kk, nearest=kk >= 0.99), GOB_MUL, add=(8, 0, -6),
                    haze=(236, 160, 100), haze_t=haze_t * (1 - t))
        foot, mid = _foot_of(fr)
        sprites.append((y, spr, int(x - mid * kk), int(y - foot * kk)))


def pig_riders(sprites, x0, y0, rows, cols, k0, k1, step_x, step_y, haze_t=0.0):
    """Клин свиносадников орды, бегом влево (фланговый удар): голова клина —
    (x0, y0), ряды уходят назад-вправо"""
    for r in range(rows):
        for c in range(cols):
            if c > r + 1:
                continue
            x = x0 + r * step_x * 0.9 + c * step_x * 0.55 + rng.uniform(-10, 10)
            y = y0 + (c - r * 0.5) * step_y + rng.uniform(-6, 6)
            t = (y - (y0 - rows * step_y)) / max(1.0, 2.0 * rows * step_y)
            kk = lerp(k0, k1, max(0.0, min(1.0, t)))
            fr = ImageOps.mirror(PIG_RUN[(r * 3 + c) % len(PIG_RUN)])
            spr = grade(scaled(fr, kk, nearest=kk >= 0.99), GOB_MUL, add=(8, 0, -6),
                        haze=(236, 160, 100), haze_t=haze_t)
            foot, mid = _foot_of(fr)
            sprites.append((y, spr, int(x - mid * kk), int(y - foot * kk)))


def troll(sprites, x, y, k, attack=False, haze_t=0.0):
    seq = TROLL_ATK if attack else TROLL_WALK
    fr = ImageOps.mirror(seq[rng.randrange(len(seq))])
    spr = grade(scaled(fr, k, nearest=k >= 0.99), GOB_MUL, add=(6, 0, -6), haze=(236, 160, 100), haze_t=haze_t)
    foot, mid = _foot_of(fr)
    sprites.append((y, spr, int(x - mid * k), int(y - foot * k)))


def dust(img, cx, cy, w, n):
    """Пыль схватки у линии столкновения"""
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for i in range(n):
        x = cx + rng.uniform(-w / 2, w / 2)
        y = cy + rng.uniform(-18, 18)
        r = rng.uniform(26, 60)
        d.ellipse([x - r * 1.4, y - r * 0.7, x + r * 1.4, y + r * 0.5], fill=(190, 170, 120, 70))
    img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(18)))


# ── ПОБОИЩЕ ПЕРЕД КОПЕЙЩИКАМИ (ТЗ 30.10.2026) ──────────────────────────────
# Готовых спрайтов тел нет — как в игре (CorpseRenderer), тело — кадр бойца,
# положенный набок, приплюснутый перспективой и притушенный. Стрелы в земле —
# Arrow.png лучника, наконечник в грунте (нижняя треть кадра срезана)
ARROW = Image.open(os.path.join(HUM, "units", "Blue Units", "Archer", "Arrow.png")).convert("RGBA")
GOB_IDLE = frames(os.path.join(GOB, "Spear Goblin_Run.png"), 256, 256)


def corpse(sprites, x, y, k, goblin=True):
    seq = GOB_IDLE if goblin else LANCER
    fr = seq[rng.randrange(len(seq))]
    fr = fr.crop(fr.getbbox())
    if rng.random() < 0.5:
        fr = ImageOps.mirror(fr)
    fr = fr.rotate(90 if rng.random() < 0.5 else -90, expand=True, resample=Image.NEAREST)
    kk = k * (1.05 if goblin else 0.80) * rng.uniform(0.9, 1.1)
    fr = fr.resize((max(1, int(fr.width * kk)), max(1, int(fr.height * kk * 0.62))),
                   Image.NEAREST if kk >= 0.99 else Image.LANCZOS)
    spr = grade(fr, (0.80, 0.76, 0.72), add=(4, 2, 0))
    # тёмное пятно под телом — тело лежит, а не висит над травой
    pad = int(spr.height * 0.5)
    under = Image.new("RGBA", (spr.width + 2 * pad, spr.height + 2 * pad), (0, 0, 0, 0))
    ImageDraw.Draw(under).ellipse([pad * 0.6, pad + spr.height * 0.45, under.width - pad * 0.6,
                                   pad + spr.height * 1.25], fill=(52, 30, 20, 120))
    under = under.filter(ImageFilter.GaussianBlur(max(2, pad // 3)))
    under.alpha_composite(spr, (pad, pad))
    # тела лежат НА земле: сортируются чуть раньше стоящих в той же строке
    sprites.append((y - 4, under, int(x - under.width / 2), int(y - spr.height - pad)))


def stuck_arrow(sprites, x, y, k):
    ang = rng.uniform(52, 78) * (1 if rng.random() < 0.7 else -1)
    a = ARROW.crop(ARROW.getbbox())
    # остриё вправо → вниз-вправо (или вниз-влево): наконечник в землю
    a = a.rotate(-ang, expand=True, resample=Image.BICUBIC)
    kk = k * 1.35 * rng.uniform(0.85, 1.15)
    a = a.resize((max(1, int(a.width * kk)), max(1, int(a.height * kk))), Image.LANCZOS)
    keep_h = int(a.height * 0.70)
    a = a.crop((0, 0, a.width, keep_h))
    tip_x = a.width * (0.78 if ang > 0 else 0.22)
    sprites.append((y - 2, grade(a, (0.92, 0.88, 0.84)), int(x - tip_x), int(y - keep_h)))


def trampled(img, pts):
    """Вытоптанная трава и пятна земли под побоищем"""
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for x, y, r in pts:
        d.ellipse([x - r * 1.6, y - r * 0.45, x + r * 1.6, y + r * 0.45],
                  fill=(86, 74, 40, 70) if rng.random() < 0.6 else (60, 52, 34, 60))
    img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(16)))


# ── СТРЕЛЫ: ЗАЛПЫ С БАШЕН ПО ВСЕЙ ПОЛОСЕ НАСТУПЛЕНИЯ ────────────────────────
def arrows(img, shots, n, target):
    """n стрел из точек shots (верх башен и замок) по дугам к орде; у каждой —
    свой отрезок пути (взлёт, вершина, снижение, у земли), за наконечником —
    светлый след: траектории читаются по всей площади наступления.
    target() -> (x, y) — точка падения в орде"""
    layer = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    def flight(p0, p1, apex, t0, t1, alpha, size):
        pts = []
        m = 48
        for j in range(m + 1):
            t = lerp(t0, t1, j / m)
            x = lerp(p0[0], p1[0], t)
            y = lerp(p0[1], p1[1], t) - apex * 4 * t * (1 - t)
            pts.append((x * SS, y * SS))
        for j in range(len(pts) - 1):
            a = int(alpha * 0.55 * (j / m) ** 1.4)
            d.line([pts[j], pts[j + 1]], fill=(255, 228, 186, a), width=max(1, int(size * 0.35 * SS)))
        hx, hy = pts[-1]
        px, py = pts[-4]
        ang = math.atan2(hy - py, hx - px)
        ln = size * 9 * SS
        tx, ty = hx - math.cos(ang) * ln, hy - math.sin(ang) * ln
        d.line([(tx, ty), (hx, hy)], fill=(30, 18, 14, alpha), width=max(2, int(size * 0.9 * SS)))
        nx, ny = -math.sin(ang), math.cos(ang)
        hl = size * 2.4 * SS
        d.polygon([(hx + math.cos(ang) * hl, hy + math.sin(ang) * hl),
                   (hx + nx * hl * 0.45, hy + ny * hl * 0.45),
                   (hx - nx * hl * 0.45, hy - ny * hl * 0.45)], fill=(40, 26, 20, alpha))
        for s in (-1, 1):
            d.line([(tx, ty), (tx - math.cos(ang - s * 0.5) * hl, ty - math.sin(ang - s * 0.5) * hl)],
                   fill=(210, 190, 170, alpha), width=max(1, int(size * 0.5 * SS)))

    for i in range(n):
        p0 = shots[rng.randrange(len(shots))]
        p1 = target()
        apex = H * rng.uniform(0.20, 0.34)
        # голова стрелы равномерно по всей дуге, хвост — 10-22 % пути
        t1 = rng.uniform(0.15, 0.50) if rng.random() < 0.35 else rng.uniform(0.50, 0.99)
        t0 = max(0.0, t1 - rng.uniform(0.10, 0.22))
        size = lerp(2.6, 4.4, (p1[1] - HORIZON) / (H - HORIZON)) * rng.uniform(0.9, 1.1)
        flight(p0, p1, apex, t0, t1, rng.randint(170, 240), size)
    img.alpha_composite(layer.resize((W, H), Image.LANCZOS))


def main():
    img = sky()
    sun(img)
    clouds(img)
    ridge(img, HORIZON - H * 0.17, H * 0.11, (104, 56, 74), 9)
    ridge(img, HORIZON - H * 0.07, H * 0.075, (72, 40, 56), 13)
    mist(img, HORIZON - H * 0.05, H * 0.05, (246, 150, 95), 60)
    field(img)
    forest(img, W * 0.55, W * 1.03, 90)

    haze = (236, 160, 100)
    near = []
    shots = fortress(img)

    # ── копейщики: две плотные линии отрядов вдоль линии башен, лицом к орде ─
    # Ось линии параллельна башням (TOWERS): от верхней башни вниз-влево.
    # Знамёна — ранги из игры: вымпелы 1-6, легенда, штандарт элиты
    mul = (1.0, 0.95, 0.92)
    a0, a1 = (W * 0.322, H * 0.628), (W * 0.244, H * 0.840)
    # Синие вымпелы шкалы 30.10: лычки белые 1-3, красные 4-6, золотые 7-9
    flags_front = ["human_3", "human_8", "human_6", "human_2"]
    flags_back = ["human_1", "human_5", "human_9", "human_4"]
    FRONT_SHIFT = W * 0.016       # передняя линия правее — ровный зазор между линиями
    for i in range(4):
        t = i / 3.0
        x = lerp(a0[0], a1[0], t)
        y = lerp(a0[1], a1[1], t)
        k = lerp(0.48, 0.80, t)
        ht = lerp(0.24, 0.02, t)
        block(near, x - W * 0.070 - k * 30, y - H * 0.004, 10, 5, k * 0.97, mul, haze, ht + 0.02,
              flags_back[i], pose="idle")
        block(near, x + FRONT_SHIFT, y, 10, 5, k, mul, haze, ht, flags_front[i], pose="right")

    # ── орда справа: косой фронт, зеркальный линии копейщиков ─────────────
    # Фронт орды параллелен линии копейщиков и отстоит от неё на полосу
    # побоища: орда надвигается через всю середину поля (ТЗ 30.10.2026)
    def spear_front(y):
        t = (y - a0[1]) / (a1[1] - a0[1])
        return lerp(a0[0], a1[0], t) + FRONT_SHIFT + 9 * 44 * lerp(0.48, 0.80, t) / 2 + 60

    def front_line(y):
        return spear_front(y) + W * 0.055

    rider_box = (W * 0.520, H * 0.840, W * 0.660, H * 0.960)

    def keep(x, y):
        if x < front_line(y):
            return False
        return not (rider_box[0] < x < rider_box[2] and rider_box[1] < y < rider_box[3])

    goblin_wave(near, W * 0.38, HORIZON + H * 0.03, W * 1.02, HORIZON + H * 0.10, 300, 0.42, 0.52,
                lambda x, y: x < front_line(y) + 60, haze_t=0.36, keep=keep)
    goblin_wave(near, W * 0.34, HORIZON + H * 0.10, W * 1.03, H * 0.80, 420, 0.52, 0.74,
                lambda x, y: x < front_line(y) + 80, haze_t=0.18, keep=keep)
    goblin_wave(near, W * 0.33, H * 0.80, W * 1.04, H * 1.02, 300, 0.76, 1.02,
                lambda x, y: x < front_line(y) + 110, haze_t=0.0, keep=keep)
    troll(near, W * 0.83, HORIZON + H * 0.075, 1.0, haze_t=0.25)
    troll(near, W * 0.95, HORIZON + H * 0.065, 0.95, haze_t=0.28)
    troll(near, W * 0.745, H * 0.700, 1.30, haze_t=0.10)
    troll(near, W * 0.56, H * 0.66, 1.15, haze_t=0.16)
    troll(near, W * 0.905, H * 0.79, 1.5, haze_t=0.08)
    troll(near, W * 0.835, H * 0.975, 2.0, attack=True)
    troll(near, W * 0.965, H * 0.945, 2.1)
    # знамёна орды из игры — вымпелы рангов, НИЗКО над толпой (ТЗ 30.10.2026:
    # прежние k × 1.3 задирали древки над головами); рваного штандарта легенды
    # нет — его принимали за знамя Свинобосса
    for name, fx, fy, k in [("goblin_2", 0.715, 0.650, 0.95), ("goblin_5", 0.880, 0.640, 0.90),
                            ("goblin_4", 0.600, 0.700, 1.05), ("goblin_3", 0.960, 0.760, 1.15),
                            ("goblin_6", 0.900, 0.900, 1.50), ("goblin_1", 0.520, 0.640, 0.90)]:
        banner(near, name, W * fx, H * fy, k * 0.82, lerp(0.3, 0.0, (fy - 0.62) / 0.3))
    # свиносадники орды — клин на нижнем фланге, бегом во фланг копейщикам
    pig_riders(near, W * 0.540, H * 0.880, 4, 5, 0.92, 1.08, 86.0, 30.0, haze_t=0.02)

    # ── побоище: тела, стрелы в земле, вытоптанная трава ────────────────────
    def depth_k(y):
        return lerp(0.48, 0.80, (y - a0[1]) / (a1[1] - a0[1]))

    tramp = []
    for i in range(170):
        y = rng.uniform(H * 0.60, H * 1.0)
        x0, x1 = spear_front(y) - 20, front_line(y) + 40
        x = rng.uniform(x0, x1)
        k = depth_k(y)
        tramp.append((x, y, 70 * k * rng.uniform(0.7, 1.3)))
        if i % 2 == 0:
            corpse(near, x, y, k, goblin=rng.random() < 0.8)
    for i in range(150):
        y = rng.uniform(H * 0.60, H * 1.0)
        x = rng.uniform(spear_front(y) - 30, front_line(y) + 60)
        stuck_arrow(near, x, y, depth_k(y))
    trampled(img, tramp)

    draw_sorted(img, near)
    dust(img, W * 0.45, H * 0.86, 520, 14)

    # стрелы: залпы с башен и замка по всей полосе наступления орды
    def target():
        y = rng.uniform(HORIZON + H * 0.04, H * 0.86)
        return (rng.uniform(front_line(y) - W * 0.02, W * 1.02), y)

    arrows(img, shots, 130, target)

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    img.convert("RGB").save(OUT, optimize=True)
    print(OUT, os.path.getsize(OUT) // 1024, "KB")


if __name__ == "__main__":
    main()
