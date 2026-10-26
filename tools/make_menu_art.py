# -*- coding: utf-8 -*-
"""Фоновая иллюстрация главного меню и экрана загрузки (ТЗ 22.10.2026).

Собирается из НАСТОЯЩИХ спрайтов игры, а не рисуется силуэтами: замок —
assets/factions/humans/buildings/Blue Buildings/Castle.png (двухъярусные башни,
деревянный настил, синяя окантовка), лучники на настиле — Archer_Shoot,
копейщики — Lancer_Idle, выстроенные прямоугольными блоками отрядов. Небо,
горы, стрелы по дуге, дым и вымпелы рисуются здесь же. Случайность — своё
зерно: повторный запуск даёт ту же картинку байт в байт.

Запуск из корня проекта:  python tools/make_menu_art.py
Итог: assets/ui/menu_background_castle.png (3840x2160).
"""
import math
import os
import random

from PIL import Image, ImageDraw, ImageFilter, ImageOps

W, H = 3840, 2160
SS = 2                      # суперсэмплинг векторных слоёв (стрелы, флажки)
HORIZON = int(H * 0.60)
SEED = 1066
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HUM = os.path.join(ROOT, "assets", "factions", "humans")
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
    """Подкраска под закат: множитель по каналам, прибавка, дымка к цвету неба."""
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


# ── НЕБО ────────────────────────────────────────────────────────────────────
def sky():
    img = Image.new("RGBA", (W, H))
    stops = [(0.00, (18, 18, 41)), (0.30, (56, 31, 61)), (0.55, (158, 66, 51)),
             (0.80, (237, 133, 61)), (1.00, (252, 199, 107))]
    px = ImageDraw.Draw(img)
    for y in range(HORIZON):
        t = y / HORIZON
        for i in range(len(stops) - 1):
            if stops[i][0] <= t <= stops[i + 1][0]:
                k = (t - stops[i][0]) / (stops[i + 1][0] - stops[i][0])
                px.line([(0, y), (W, y)], fill=lerp_col(stops[i][1], stops[i + 1][1], k) + (255,))
                break
    for y in range(HORIZON, H):
        t = (y - HORIZON) / (H - HORIZON)
        px.line([(0, y), (W, y)], fill=lerp_col((52, 30, 30), (16, 10, 12), t) + (255,))
    return img


def glow(img, cx, cy, r, col, alpha):
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=col + (alpha,))
    layer = layer.filter(ImageFilter.GaussianBlur(r * 0.45))
    img.alpha_composite(layer)


def sun(img):
    cx, cy = int(W * 0.70), int(HORIZON - H * 0.17)
    r = int(H * 0.07)
    glow(img, cx, cy, int(r * 5.0), (255, 150, 70), 90)
    glow(img, cx, cy, int(r * 2.2), (255, 190, 110), 140)
    d = ImageDraw.Draw(img)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(255, 222, 150, 255))
    d.ellipse([cx - r * 0.8, cy - r * 0.8, cx + r * 0.8, cy + r * 0.8], fill=(255, 238, 185, 255))


def clouds(img):
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for i in range(11):
        y = H * rng.uniform(0.06, 0.40)
        x0 = W * rng.uniform(-0.15, 0.95)
        ln = W * rng.uniform(0.16, 0.36)
        th = H * rng.uniform(0.010, 0.024)
        col = (70, 36, 60, 150) if y < H * 0.28 else (230, 120, 80, 95)
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


def field(img):
    """Поле под строем: тёплая подсветка у горизонта, холмистая кромка."""
    d = ImageDraw.Draw(img)
    pts = [(0, H)]
    n = 16
    for i in range(n + 1):
        x = W * i / n
        pts.append((x, HORIZON + H * 0.035 + math.sin(i * 1.1 + rng.random()) * H * 0.015))
    pts.append((W, H))
    d.polygon(pts, fill=(78, 56, 44, 255))
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    top = int(HORIZON + H * 0.02)
    for y in range(top, H):
        t = (y - top) / (H - top)
        ld.line([(0, y), (W, y)], fill=(20, 13, 14, int(235 * min(1.0, t * 1.1) ** 1.4)))
    img.alpha_composite(layer)
    # закатный отсвет по полю справа (солнце)
    glow(img, int(W * 0.70), int(HORIZON + H * 0.05), int(H * 0.22), (220, 110, 60), 55)


# ── ОТРЯДЫ КОПЕЙЩИКОВ БЛОКАМИ ───────────────────────────────────────────────
LANCER = frames(os.path.join(HUM, "units", "Blue Units", "Lancer", "Lancer_Idle.png"), 320, 320)
LANCER_FOOT = 198          # низ ног в кадре (bbox 48..198)
LANCER_CX = 150            # ось фигуры в кадре
LANCER_TIP = 48            # остриё копья


def pennant(d, tip_x, tip_y, length, col, wave):
    """Треугольный вымпел у острия: древко — копьё, полотнище вправо."""
    h = length * 0.42
    pts = [(tip_x, tip_y), (tip_x + length, tip_y + h * 0.5 + wave), (tip_x, tip_y + h)]
    d.polygon(pts, fill=col)
    d.line(pts + [pts[0]], fill=tuple(int(c * 0.55) for c in col[:3]) + (col[3],), width=max(1, int(length * 0.05)))


LANCER_POSES = {
    "right": (frames(os.path.join(HUM, "units", "Blue Units", "Lancer", "Lancer_Right_Defence.png"), 320, 320),
              frames(os.path.join(HUM, "units", "Blue Units", "Lancer", "Lancer_Right_Attack.png"), 320, 320)),
    "downright": (frames(os.path.join(HUM, "units", "Blue Units", "Lancer", "Lancer_DownRight_Defence.png"), 320, 320),
                  frames(os.path.join(HUM, "units", "Blue Units", "Lancer", "Lancer_DownRight_Attack.png"), 320, 320)),
}


def block(img, cx, foot_y, cols, rows, k, mul, haze, haze_t, flag_col, pose="idle", sprites=None):
    """Прямоугольный отряд: ряды сзади вперёд, у каждого ряда свой сдвиг по
    глубине; ОДНО знамя-вымпел на высоком древке над центром отряда.
    pose: "idle" — копья вверх; "right"/"downright" — копья опущены к врагу
    (стойка Defence), передний край колет (Attack): у "right" — правая
    колонна, у "downright" — передняя шеренга и правая колонна.
    sprites — список ближнего плана: фигуры не рисуются сразу, а копятся
    для сортировки по глубине вместе с гоблинами"""
    sx = 56 * k              # интервал по фронту (в пикселях кадра × масштаб)
    sy = 30 * k              # шаг ряда вглубь
    lean = 16 * k            # ряды чуть смещены вбок — видна глубина блока
    width = (cols - 1) * sx
    for r in range(rows - 1, -1, -1):
        ry = foot_y - r * sy
        rx = cx - width / 2 + r * lean
        t_row = haze_t + (r / max(1, rows - 1)) * 0.08
        for c in range(cols):
            if pose == "idle":
                fr = LANCER[(c * 5 + r * 3) % len(LANCER)]
            else:
                defence, attack = LANCER_POSES[pose]
                front = c == cols - 1 or (pose == "downright" and r == 0)
                seq = attack if front else defence
                fr = seq[(c * 2 + r) % len(seq)]
            spr = grade(scaled(fr, k, nearest=k >= 0.99), mul, haze=haze, haze_t=min(1.0, t_row))
            x = rx + c * sx + rng.uniform(-4, 4) * k
            y = ry + rng.uniform(-3, 3) * k
            ox = int(x - LANCER_CX * k)
            oy = int(y - LANCER_FOOT * k)
            if sprites is not None:
                sprites.append((y, spr, ox, oy))
            else:
                img.alpha_composite(spr, (ox, oy))
    # знамя отряда — одно, на высоком древке за центром
    flags = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))
    fd = ImageDraw.Draw(flags)
    px = cx + rows * lean * 0.5
    top = foot_y - rows * sy - (LANCER_FOOT - LANCER_TIP) * k - 70 * k
    fd.line([(px * SS, top * SS), (px * SS, (foot_y - rows * sy * 0.5) * SS)],
            fill=(40, 26, 22, flag_col[3]), width=max(2, int(5 * k * SS)))
    pennant(fd, px * SS, top * SS, 120 * k * SS, flag_col, 6 * k * SS)
    return flags.resize((W, H), Image.LANCZOS)


# ── ВОЛНЫ ГОБЛИНОВ ──────────────────────────────────────────────────────────
GOB = os.path.join(ROOT, "assets", "factions", "Goblin")
GOB_RUN = frames(os.path.join(GOB, "Spear Goblin_Run.png"), 256, 256)
def no_swoosh(seq, max_w=125):
    """Кадры удара БЕЗ белой дуги взмаха: у кадра с дугой рамка непрозрачного
    вдвое шире фигуры (167-216 px против 80-125). На арте дуги сливались в
    кашу, а чистка по цвету резала и шлемы — берём только узкие кадры"""
    out = []
    for f in seq:
        bb = f.getbbox()
        if bb is not None and bb[2] - bb[0] <= max_w:
            out.append(f)
    return out or seq


GOB_ATK = no_swoosh(frames(os.path.join(GOB, "Spear Goblin_Attack Fast.png"), 256, 256))
GOB_ATK2 = no_swoosh(frames(os.path.join(GOB, "Spear Goblin_Attack Strong.png"), 256, 256), 126)
PIG_RUN = frames(os.path.join(GOB, "Pig Rider_Run.png"), 256, 256)
PIG_ATK = no_swoosh(frames(os.path.join(GOB, "Pig Rider_Attack.png"), 256, 256))


def _foot_of(fr):
    """Низ непрозрачного (ноги) и середина фигуры по кадру"""
    bb = fr.getbbox() or (0, 0, fr.width, fr.height)
    return bb[3], (bb[0] + bb[2]) * 0.5


def goblin_wave(sprites, x0, y0, x1, y1, n, k, front, riders=0.25, mul=(0.92, 0.80, 0.80)):
    """Толпа гоблинов в прямоугольнике (x0..x1, y0..y1), лицом ВЛЕВО-ВВЕРХ
    (зеркально). front(x, y) -> True: фигура у строя — кадр удара, иначе бег.
    Кабаньи наездники — доля riders"""
    for i in range(n):
        x = rng.uniform(x0, x1)
        y = rng.uniform(y0, y1)
        rider = rng.random() < riders
        hit = front(x, y)
        if rider:
            seq = PIG_ATK if hit else PIG_RUN
        else:
            seq = (GOB_ATK if rng.random() < 0.6 else GOB_ATK2) if hit else GOB_RUN
        fr = seq[rng.randrange(len(seq))]
        fr = ImageOps.mirror(fr)
        kk = k * rng.uniform(0.94, 1.06) * (1.12 if rider else 1.0)
        spr = grade(scaled(fr, kk, nearest=kk >= 0.99), mul, add=(10, 0, -6))
        foot, mid = _foot_of(fr)
        sprites.append((y, spr, int(x - mid * kk), int(y - foot * kk)))


def draw_sorted(img, sprites):
    for y, spr, ox, oy in sorted(sprites, key=lambda e: e[0]):
        img.alpha_composite(spr, (ox, oy))


def dust(img, cx, cy, w, n):
    """Пыль схватки у линии столкновения — низкие бурые клубы"""
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for i in range(n):
        x = cx + rng.uniform(-w / 2, w / 2)
        y = cy + rng.uniform(-18, 18)
        r = rng.uniform(26, 60)
        d.ellipse([x - r * 1.4, y - r * 0.7, x + r * 1.4, y + r * 0.5], fill=(150, 112, 84, 70))
    img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(18)))


# ── ЗАМОК С ЛУЧНИКАМИ НА НАСТИЛЕ ────────────────────────────────────────────
ARCHER = frames(os.path.join(HUM, "units", "Blue Units", "Archer", "Archer_Shoot.png"), 192, 192)


def castle(img):
    k = 3.7
    base = Image.open(os.path.join(HUM, "buildings", "Blue Buildings", "Castle.png")).convert("RGBA")
    cas = grade(scaled(base, k), (0.92, 0.80, 0.80), add=(14, 2, -4))
    left = int(W * 0.035)
    bottom = int(H * 0.93)
    top = bottom - cas.height
    # тень-подножие
    sh = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(sh).ellipse([left + 60, bottom - 120, left + cas.width - 40, bottom + 30], fill=(8, 4, 6, 170))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(30)))
    img.alpha_composite(cas, (left, top))
    # закатный контровой свет справа
    glow(img, left + cas.width - 80, top + cas.height // 2, int(cas.width * 0.35), (255, 140, 70), 28)
    # лучники на настиле: два ряда за зубцами (координаты — в пикселях спрайта)
    ak = 1.45
    spots = []
    for row, (y, xs) in enumerate([(96, range(46, 296, 30)), (120, range(62, 284, 34))]):
        for x in xs:
            if 140 < x < 180 and row == 0:
                continue
            spots.append((x + rng.uniform(-3, 3), y + rng.uniform(-2, 2)))
    for i, (sx, sy) in enumerate(spots):
        fr = ARCHER[(i * 3) % len(ARCHER)]
        spr = grade(scaled(fr, ak), (0.90, 0.80, 0.82), add=(10, 0, -4))
        img.alpha_composite(spr, (int(left + sx * k - 96 * ak), int(top + sy * k - 136 * ak)))
    # передний ряд зубцов поверх ног лучников: перекладываем полосу кромки
    rim_top, rim_bot = 128, 150
    rim = cas.crop((0, int(rim_top * k), cas.width, int(rim_bot * k)))
    img.alpha_composite(rim, (left, top + int(rim_top * k)))
    return left, top, cas.width, bottom


# ── СТРЕЛЫ ПО ДУГЕ ──────────────────────────────────────────────────────────
def arrows(img, src_box):
    layer = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    sx0, sy0, sx1, sy1 = src_box

    def flight(p0, p1, apex, t0, t1, col, alpha, size):
        pts = []
        n = 40
        for j in range(n + 1):
            t = lerp(t0, t1, j / n)
            x = lerp(p0[0], p1[0], t)
            y = lerp(p0[1], p1[1], t) - apex * 4 * t * (1 - t)
            pts.append((x * SS, y * SS))
        # след — тускнеет к хвосту
        for j in range(len(pts) - 1):
            a = int(alpha * 0.45 * (j / n) ** 1.6)
            d.line([pts[j], pts[j + 1]], fill=col + (a,), width=max(1, int(size * 0.35 * SS)))
        # сама стрела у головы следа
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
        for s in (-1, 1):   # оперение
            d.line([(tx, ty), (tx - math.cos(ang - s * 0.5) * hl, ty - math.sin(ang - s * 0.5) * hl)],
                   fill=(210, 190, 170, alpha), width=max(1, int(size * 0.5 * SS)))

    # залп с замка вправо, к дальнему краю поля
    for i in range(26):
        p0 = (rng.uniform(sx0 + 150, sx1 - 100), rng.uniform(sy0 + 380, sy0 + 470))
        p1 = (W * rng.uniform(0.80, 1.10), HORIZON + H * rng.uniform(-0.02, 0.06))
        apex = H * rng.uniform(0.36, 0.50)
        t1 = rng.uniform(0.32, 0.62)
        flight(p0, p1, apex, max(0.0, t1 - rng.uniform(0.16, 0.26)), t1, (255, 220, 170), rng.randint(170, 235),
               rng.uniform(3.6, 4.6))
    # встречный обстрел издали — мельче, к стенам замка
    for i in range(14):
        p0 = (W * rng.uniform(0.92, 1.15), HORIZON + H * rng.uniform(-0.04, 0.02))
        p1 = (rng.uniform(sx0 + 200, sx1), rng.uniform(sy0 + 300, sy1 - 200))
        apex = H * rng.uniform(0.25, 0.34)
        t1 = rng.uniform(0.55, 0.85)
        flight(p0, p1, apex, max(0.0, t1 - rng.uniform(0.12, 0.2)), t1, (255, 200, 150), rng.randint(130, 190),
               rng.uniform(2.6, 3.2))
    img.alpha_composite(layer.resize((W, H), Image.LANCZOS))


# ── ДЫМ И ОГОНЬ У ПОДНОЖИЯ ──────────────────────────────────────────────────
def smoke(img, cx, base_y, width, height, puffs, dark=0.0, fire=True):
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    if fire:
        for i in range(max(2, puffs // 6)):
            x = cx + rng.uniform(-width * 0.35, width * 0.35)
            r = rng.uniform(10, 18)
            d.ellipse([x - r, base_y - r * 1.6, x + r, base_y + r * 0.4], fill=(255, 150, 60, 150))
    for i in range(puffs):
        t = rng.random() ** 0.8
        x = cx + rng.uniform(-width / 2, width / 2) * (1 - 0.5 * t) + t * width * 0.35
        y = base_y - t * height
        r = lerp(28, 95, t) * rng.uniform(0.7, 1.3)
        g = int(lerp(lerp(70, 40, dark), lerp(120, 70, dark), t))
        col = (g + 18, g, g - 6, int(lerp(150, 45, t)))
        d.ellipse([x - r, y - r, x + r, y + r], fill=col)
    layer = layer.filter(ImageFilter.GaussianBlur(24))
    img.alpha_composite(layer)
    if fire:
        glow(img, int(cx), int(base_y - 20), int(width * 0.35), (255, 120, 40), 60)


def main():
    img = sky()
    sun(img)
    clouds(img)
    ridge(img, HORIZON - H * 0.15, H * 0.10, (92, 51, 66), 9)
    ridge(img, HORIZON - H * 0.065, H * 0.07, (64, 36, 48), 13)
    mist(img, HORIZON - H * 0.05, H * 0.05, (242, 140, 90), 60)
    field(img)

    haze = (205, 115, 85)
    # дальние блоки — у горизонта за замком и вправо
    for i, cx in enumerate([W * 0.08, W * 0.21, W * 0.34, W * 0.47, W * 0.60, W * 0.73, W * 0.86, W * 0.97]):
        img.alpha_composite(block(img, cx, HORIZON + H * 0.072 + (i % 2) * 12, 12, 4, 0.36,
                                  (0.58, 0.45, 0.50), haze, 0.50, (190, 40, 30, 210)))
    smoke(img, W * 0.52, HORIZON + H * 0.10, 380, 520, 30, dark=0.3, fire=True)
    # средние блоки — сзади замка и справа от него
    for i, cx in enumerate([W * 0.12, W * 0.29, W * 0.45, W * 0.71, W * 0.95]):
        img.alpha_composite(block(img, cx, HORIZON + H * 0.175 + (i % 2) * 22, 12, 5, 0.56,
                                  (0.70, 0.56, 0.60), haze, 0.26, (205, 42, 32, 235)))

    cbox = castle(img)
    left, top, cw, bottom = cbox
    smoke(img, left + cw * 0.12, bottom - 20, 360, 520, 36, dark=0.15)
    smoke(img, left + cw * 0.97, bottom - 10, 320, 440, 30, dark=0.25)

    # ── БЛИЖНИЙ ПЛАН: ЗАМЕС С ОРДОЙ ─────────────────────────────────────
    # Два ближних отряда встречают волны гоблинов из правого нижнего угла:
    # левый — копья опущены вправо (правая колонна колет), правый — копья
    # вниз-вправо (передняя шеренга и правая колонна колют). Фигуры людей и
    # гоблинов копятся одним списком и рисуются по глубине (по ногам)
    near = []
    k1, k2 = 0.86, 0.92
    b1x, b1y = W * 0.600, H * 0.825
    b2x, b2y = W * 0.830, H * 0.835
    f1 = block(img, b1x, b1y, 10, 4, k1, (0.95, 0.82, 0.82), haze, 0.04, (215, 44, 34, 255),
               pose="right", sprites=near)
    f2 = block(img, b2x, b2y, 11, 4, k2, (0.95, 0.82, 0.82), haze, 0.02, (215, 44, 34, 255),
               pose="downright", sprites=near)
    b1_right = b1x + 9 * 56 * k1 / 2 + 4 * 16 * k1
    b2_right = b2x + 10 * 56 * k2 / 2 + 4 * 16 * k2
    # Волна 1: бьёт в правый фланг левого отряда (между ближними блоками)
    goblin_wave(near, b1_right + 30, b1y - 110, b1_right + 330, b1y + 40, 30, k1 * 1.05,
                lambda x, y: x < b1_right + 120)
    # Волна 2: из правого нижнего угла на передние шеренги правого отряда
    goblin_wave(near, b2x - 120, b2y + 60, W + 60, H + 40, 40, k2 * 1.1,
                lambda x, y: y < b2y + 150)
    # Волна 3: хвост, бегущий из-за правого края
    goblin_wave(near, W * 0.93, b2y - 160, W + 120, b2y + 40, 14, k2 * 1.05,
                lambda x, y: x < b2_right + 90 and y > b2y - 40, riders=0.45)
    draw_sorted(img, near)
    img.alpha_composite(f1)
    img.alpha_composite(f2)
    dust(img, b1_right + 90, b1y + 10, 260, 14)
    dust(img, b2x + 60, b2y + 110, 600, 22)
    smoke(img, W * 0.70, H * 0.80, 260, 380, 22, dark=0.45, fire=False)

    arrows(img, (left, top, left + cw, bottom))

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    img.convert("RGB").save(OUT, optimize=True)
    print(OUT, os.path.getsize(OUT) // 1024, "KB")


if __name__ == "__main__":
    main()
