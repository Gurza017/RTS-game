"""Иллюстрация окна «Красный игрок разбит» (ТЗ 30.10.2026).

Из спрайтов игры: поле, догорающий красный замок, павшие красные бойцы
(кадр покоя на боку, притемнён), брошенные красные вымпелы и копья, слева —
синие копейщики-победители со знаменем. Пиксель-арт без сглаживания.

    python -X utf8 tools/make_red_defeat_art.py
    затем <godot> --headless --import
"""
import os
import random

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
U = os.path.join(ROOT, "assets", "factions", "humans", "units")
B = os.path.join(ROOT, "assets", "factions", "humans", "buildings")
OUT = os.path.join(ROOT, "assets", "ui", "red_defeated.png")

W, H = 960, 400
rng = random.Random(3010)


def frames(path, fw, fh):
    sheet = Image.open(path).convert("RGBA")
    return [sheet.crop((i * fw, 0, (i + 1) * fw, fh)) for i in range(sheet.width // fw)]


def tight(img):
    bb = img.getbbox()
    return img.crop(bb) if bb else img


def scaled(img, k):
    return img.resize((max(1, round(img.width * k)), max(1, round(img.height * k))), Image.NEAREST)


def grade(img, mul, add=(0, 0, 0)):
    r, g, b, a = img.split()
    out = []
    for ch, m, ad in zip((r, g, b), mul, add):
        out.append(ch.point([int(max(0, min(255, v * m + ad))) for v in range(256)]))
    return Image.merge("RGBA", (*out, a))


def shadow_under(canvas, cx, cy, w, h, alpha=90):
    sh = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(sh).ellipse((0, 0, w - 1, h - 1), fill=(10, 20, 8, alpha))
    canvas.alpha_composite(sh, (int(cx - w / 2), int(cy - h / 2)))


def pennant(colour, length=34, height=20, chevrons=0, chev=(245, 245, 240)):
    img = Image.new("RGBA", (length + 4, height + 4), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.polygon([(2, 2), (2 + length, 2 + height // 2), (2, 2 + height)], fill=colour, outline=(30, 10, 10))
    for k in range(chevrons):
        x = 6 + k * 7
        d.line([(x, 6), (x + 5, 2 + height // 2), (x, height - 2)], fill=chev, width=2)
    return img


def background():
    img = Image.new("RGBA", (W, H))
    px = img.load()
    for y in range(H):
        t = y / H
        top = (92, 128, 70)
        bot = (58, 94, 44)
        c = tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3))
        for x in range(W):
            n = rng.randint(-6, 6)
            px[x, y] = (c[0] + n, c[1] + n, c[2] + n, 255)
    d = ImageDraw.Draw(img)
    # Вытоптанная земля поля боя
    for _ in range(26):
        x = rng.randint(120, W - 60)
        y = rng.randint(170, H - 20)
        rx, ry = rng.randint(30, 80), rng.randint(8, 20)
        d.ellipse((x - rx, y - ry, x + rx, y + ry), fill=(104, 88, 58, 255))
    img = img.filter(ImageFilter.GaussianBlur(1.2))
    # Дымное небо сверху
    sky = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sky)
    for y in range(110):
        a = int(150 * (1 - y / 110))
        sd.line([(0, y), (W, y)], fill=(54, 44, 40, a))
    img.alpha_composite(sky)
    return img


def smoke(canvas, x, y):
    sm = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(sm)
    for k in range(14):
        r = 14 + k * 5
        cx = x + rng.randint(-10, 10) + k * 6
        cy = y - k * 14
        d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(40, 36, 34, max(0, 110 - k * 7)))
    canvas.alpha_composite(sm.filter(ImageFilter.GaussianBlur(6)))


def main():
    cv = background()
    # ── Догорающий красный замок ──
    castle = Image.open(os.path.join(B, "Red Buildings", "Castle.png")).convert("RGBA")
    castle = grade(tight(castle), (0.55, 0.45, 0.42), (6, 0, 0))
    castle = scaled(castle, 1.15).rotate(-4, resample=Image.NEAREST, expand=True)
    cx, cy = 600, 40
    smoke(cv, cx + castle.width // 2, cy + 30)
    shadow_under(cv, cx + castle.width // 2, cy + castle.height - 8, castle.width, 26)
    cv.alpha_composite(castle, (cx, cy))
    # Языки пламени у стен
    fire = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    fd = ImageDraw.Draw(fire)
    for _ in range(9):
        fx = cx + rng.randint(20, castle.width - 20)
        fy = cy + rng.randint(castle.height // 3, castle.height - 30)
        fd.polygon([(fx - 8, fy + 12), (fx, fy - 16), (fx + 8, fy + 12)], fill=(236, 120, 34, 210))
        fd.polygon([(fx - 4, fy + 12), (fx, fy - 6), (fx + 4, fy + 12)], fill=(255, 214, 90, 230))
    cv.alpha_composite(fire)

    # ── Павшие красные: кадр покоя на боку, притемнён ──
    kinds = [
        (os.path.join(U, "Red Units", "Lancer", "Lancer_Idle.png"), 320, 0.42),
        (os.path.join(U, "Red Units", "Warrior", "Warrior_Idle.png"), 192, 0.55),
        (os.path.join(U, "Red Units", "Archer", "Archer_Idle.png"), 192, 0.55),
    ]
    pool = []
    for path, fw, k in kinds:
        fr = tight(frames(path, fw, fw)[0])
        pool.append(scaled(fr, k))
    spots = []
    for _ in range(19):
        spots.append((rng.randint(250, W - 40), rng.randint(215, H - 30)))
    spots.sort(key=lambda p: p[1])
    for (x, y) in spots:
        body = rng.choice(pool)
        body = body.rotate(rng.choice([88, 92, -88, -92]) + rng.uniform(-8, 8), resample=Image.NEAREST, expand=True)
        body = grade(body, (0.62, 0.55, 0.55), (10, 0, 0))
        shadow_under(cv, x, y + body.height // 3, body.width + 8, 12, 80)
        cv.alpha_composite(body, (x - body.width // 2, y - body.height // 2))
    # Брошенные копья и вымпелы
    d = ImageDraw.Draw(cv)
    for _ in range(8):
        x = rng.randint(260, W - 60)
        y = rng.randint(230, H - 20)
        ang = rng.uniform(-0.4, 0.4)
        d.line([(x, y), (x + 60, y + int(60 * ang))], fill=(92, 66, 40), width=3)
        d.polygon([(x + 60, y + int(60 * ang) - 3), (x + 70, y + int(60 * ang)), (x + 60, y + int(60 * ang) + 3)],
                  fill=(200, 200, 205))
    for _ in range(4):
        x = rng.randint(300, W - 80)
        y = rng.randint(240, H - 30)
        pole_h = 46
        d.line([(x, y), (x + 22, y - pole_h)], fill=(98, 70, 42), width=3)
        fl = pennant((150, 24, 26), chevrons=0).rotate(-28, resample=Image.NEAREST, expand=True)
        cv.alpha_composite(fl, (x + 16, y - pole_h - 6))

    # ── Победители: синие копейщики слева, знамя поднято ──
    blue = tight(frames(os.path.join(U, "Blue Units", "Lancer", "Lancer_Idle.png"), 320, 320)[0])
    blue = scaled(blue, 0.46)
    for i, (x, y) in enumerate([(70, 250), (130, 235), (110, 300), (175, 280), (55, 330), (160, 340), (225, 318)]):
        shadow_under(cv, x, y + blue.height // 2 - 6, blue.width - 10, 12)
        cv.alpha_composite(blue, (x - blue.width // 2, y - blue.height // 2))
        if i == 1:
            d.line([(x + 10, y + 10), (x + 10, y - 80)], fill=(110, 80, 46), width=4)
            cv.alpha_composite(pennant((41, 87, 179), 52, 30, 3), (x + 12, y - 80))

    # Виньетка
    vg = Image.new("L", (W, H), 0)
    vd = ImageDraw.Draw(vg)
    for i in range(40):
        vd.rectangle((i, i, W - 1 - i, H - 1 - i), outline=int(180 * (1 - i / 40)))
    dark = Image.new("RGBA", (W, H), (12, 8, 6, 255))
    cv = Image.composite(dark, cv, vg.filter(ImageFilter.GaussianBlur(8)))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    cv.convert("RGB").save(OUT)
    print("записано", OUT, cv.size)


if __name__ == "__main__":
    main()
