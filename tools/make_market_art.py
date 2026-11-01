# -*- coding: utf-8 -*-
"""Спрайты Рынка и Склада (ТЗ 27.10.2026, пп. 4-5) — по одному на цвет стороны.

Рынок — три торговые палатки (полосатый навес цвета стороны + кремовый,
прилавок с товаром), холст 192x256 как у бараков, низ рисунка на той же
высоте (y 245). Склад — крыша дома (вырезана из House1 того же цвета, чтобы
черепица и обводка совпали с паком) на четырёх столбах над помостом с
ящиками, мешками и брёвнами; холст 128x192 как у дома.

Палитра — из пака: обводка (22, 28, 46), дерево (141, 104, 87)/(189, 138, 89),
цвет стороны — с черепицы House1. Запуск: python tools/make_market_art.py
"""
from PIL import Image, ImageDraw
import os, random

ROOT = os.path.join(os.path.dirname(__file__), "..", "assets", "factions", "humans", "buildings")
COLORS = ["Blue", "Red", "Black", "Purple", "Yellow"]
INK = (22, 28, 46, 255)
WOOD = (141, 104, 87, 255)
WOOD_L = (189, 138, 89, 255)
WOOD_D = (96, 66, 58, 255)
CREAM = (236, 222, 186, 255)
CREAM_D = (196, 178, 140, 255)
SHADOW = (0, 0, 0, 70)


def faction_tones(col):
    """Светлый и тёмный тон стороны — самые частые цвета ската крыши House1."""
    im = Image.open(os.path.join(ROOT, "%s Buildings" % col, "House1.png")).convert("RGBA")
    cnt = {}
    for y in range(40, 100):
        for x in range(15, 45):
            p = im.getpixel((x, y))
            if p[3] > 200 and p[:3] != INK[:3]:
                cnt[p[:3]] = cnt.get(p[:3], 0) + 1
    top = sorted(cnt.items(), key=lambda kv: -kv[1])
    a, b = top[0][0], top[1][0]
    # светлый — с большей суммой каналов
    if sum(a) < sum(b):
        a, b = b, a
    return a + (255,), b + (255,)


def box(d, x0, y0, x1, y1, fill, ink=INK):
    d.rectangle([x0, y0, x1, y1], fill=fill, outline=ink)


def tent(img, cx, base, w, h, light, dark, seed):
    """Палатка: столбы, прилавок с товаром, полосатый навес с фестонами.
    cx — центр, base — земля под прилавком, w — ширина навеса, h — высота
    от земли до конька"""
    d = ImageDraw.Draw(img)
    rnd = random.Random(seed)
    hw = w // 2
    eave = base - int(h * 0.40)        # нижняя кромка навеса
    peak = base - h
    # тень на земле
    sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).ellipse([cx - hw - 2, base - 6, cx + hw + 4, base + 5], fill=SHADOW)
    img.alpha_composite(sh)
    # задняя стенка (тёмная ткань)
    box(d, cx - hw + 4, eave, cx + hw - 4, base - 14, dark)
    # столбы
    for px in (cx - hw + 3, cx + hw - 6):
        box(d, px, eave - 2, px + 3, base, WOOD)
        d.line([px + 1, eave, px + 1, base - 1], fill=WOOD_L)
    # прилавок
    cy0 = base - 16
    box(d, cx - hw + 5, cy0, cx + hw - 6, base - 2, WOOD)
    d.line([cx - hw + 6, cy0 + 1, cx + hw - 7, cy0 + 1], fill=WOOD_L)
    for k in range(cx - hw + 12, cx + hw - 8, 9):
        d.line([k, cy0 + 3, k, base - 3], fill=WOOD_D)
    # товар на прилавке
    x = cx - hw + 8
    goods = ["apple", "sack", "crate", "melon", "bread", "apple", "sack"]
    rnd.shuffle(goods)
    gi = 0
    while x < cx + hw - 14:
        g = goods[gi % len(goods)]
        gi += 1
        if g == "apple":
            for j in range(3):
                ax = x + j * 3
                d.ellipse([ax, cy0 - 5, ax + 4, cy0 - 1], fill=(200, 52, 48, 255), outline=INK)
            x += 12
        elif g == "melon":
            d.ellipse([x, cy0 - 7, x + 8, cy0 - 1], fill=(96, 150, 62, 255), outline=INK)
            x += 10
        elif g == "sack":
            d.polygon([(x, cy0 - 1), (x + 1, cy0 - 7), (x + 3, cy0 - 9), (x + 5, cy0 - 7), (x + 7, cy0 - 1)],
                      fill=CREAM_D, outline=INK)
            x += 9
        elif g == "bread":
            d.ellipse([x, cy0 - 5, x + 9, cy0 - 1], fill=(206, 150, 82, 255), outline=INK)
            x += 11
        else:
            box(d, x, cy0 - 8, x + 7, cy0 - 1, WOOD_L)
            d.line([x + 1, cy0 - 4, x + 6, cy0 - 4], fill=WOOD_D)
            x += 9
    # навес: конёк и два ската, полосы вертикальные
    poly = [(cx, peak), (cx + hw, eave - 6), (cx + hw, eave), (cx - hw, eave), (cx - hw, eave - 6)]
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).polygon(poly, fill=255)
    stripes = Image.new("RGBA", img.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(stripes)
    sw = 7
    for i, sx in enumerate(range(cx - hw, cx + hw + 1, sw)):
        right = sx >= cx
        c = (light if i % 2 == 0 else CREAM) if not right else (dark if i % 2 == 0 else CREAM_D)
        sd.rectangle([sx, peak, sx + sw - 1, eave], fill=c)
    img.paste(stripes, (0, 0), mask)
    d.polygon(poly, outline=INK)
    # фестоны по кромке
    for i, sx in enumerate(range(cx - hw, cx + hw - 3, sw)):
        right = sx >= cx
        c = (light if i % 2 == 0 else CREAM) if not right else (dark if i % 2 == 0 else CREAM_D)
        d.pieslice([sx, eave - 3, sx + sw, eave + 4], 0, 180, fill=c, outline=INK)
    # навершие-флажок
    d.line([cx, peak - 7, cx, peak], fill=INK)
    d.polygon([(cx + 1, peak - 7), (cx + 6, peak - 5), (cx + 1, peak - 3)], fill=light, outline=INK)


def make_market(col):
    light, dark = faction_tones(col)
    img = Image.new("RGBA", (192, 256), (0, 0, 0, 0))
    # задняя палатка — выше и в центре, передние — по бокам и ниже
    tent(img, 96, 208, 84, 124, light, dark, 1)
    tent(img, 46, 244, 84, 104, light, dark, 2)
    tent(img, 146, 244, 84, 104, light, dark, 3)
    # бочка и ящики между передними палатками
    d = ImageDraw.Draw(img)
    box(d, 88, 228, 103, 244, WOOD)
    d.line([88, 233, 103, 233], fill=INK)
    d.line([88, 239, 103, 239], fill=INK)
    box(d, 82, 236, 89, 244, WOOD_L)
    return img


def make_storehouse(col):
    house = Image.open(os.path.join(ROOT, "%s Buildings" % col, "House1.png")).convert("RGBA")
    img = Image.new("RGBA", (128, 192), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    base = 172
    # тень и помост
    sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).ellipse([10, base - 8, 120, base + 6], fill=SHADOW)
    img.alpha_composite(sh)
    box(d, 12, base - 10, 116, base, WOOD)
    d.line([13, base - 9, 115, base - 9], fill=WOOD_L)
    for k in range(22, 112, 12):
        d.line([k, base - 7, k, base - 1], fill=WOOD_D)
    # груз под навесом: ящики, мешки, брёвна, камень, золото
    box(d, 24, base - 30, 43, base - 11, WOOD_L)
    d.line([24, base - 21, 43, base - 21], fill=INK)
    box(d, 30, base - 44, 45, base - 31, WOOD_L)
    for i in range(3):
        y = base - 13 - i * 6
        d.ellipse([52 + i * 2, y - 5, 60 + i * 2, y + 1], fill=WOOD, outline=INK)
        d.rectangle([56 + i * 2, y - 5, 80, y + 1], fill=WOOD)
        d.line([56 + i * 2, y - 5, 80, y - 5], fill=INK)
        d.line([56 + i * 2, y + 1, 80, y + 1], fill=INK)
        d.ellipse([77, y - 5, 83, y + 1], fill=WOOD_L, outline=INK)
    d.polygon([(88, base - 11), (89, base - 22), (93, base - 26), (97, base - 22), (98, base - 11)],
              fill=CREAM_D, outline=INK)
    d.polygon([(98, base - 11), (99, base - 20), (103, base - 24), (107, base - 20), (108, base - 11)],
              fill=CREAM, outline=INK)
    d.ellipse([60, base - 34, 70, base - 27], fill=(150, 150, 160, 255), outline=INK)
    d.ellipse([66, base - 38, 74, base - 31], fill=(232, 192, 64, 255), outline=INK)
    # четыре столба: два задних (короче, темнее) и два передних
    for px, top, c in ((20, base - 78, WOOD_D), (104, base - 78, WOOD_D), (14, base - 70, WOOD), (110, base - 70, WOOD)):
        box(d, px, top, px + 4, base - 2, c)
        d.line([px + 1, top + 1, px + 1, base - 3], fill=WOOD_L if c == WOOD else WOOD)
    # крыша дома: верх House1 до карниза (стены и дверь не берём)
    roof = house.crop((0, 0, 128, 112))
    img.alpha_composite(roof, (0, base - 78 - 92))
    return img


def main():
    for col in COLORS:
        folder = os.path.join(ROOT, "%s Buildings" % col)
        make_market(col).save(os.path.join(folder, "Market.png"))
        make_storehouse(col).save(os.path.join(folder, "Storehouse.png"))
        print("ok", col)


if __name__ == "__main__":
    main()
