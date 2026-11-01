# -*- coding: utf-8 -*-
"""Иконки исследований Кузницы гоблинов (ТЗ 28.10.2026).

Пять процедурных значков 64×64 в стиле панели: тёмная круглая плашка с
бронзовой обводкой и простой силуэт темы ветки. Рисуются кодом, а не берутся
из чужих наборов: у орды своих иконок кузницы нет, а иконки людей
(icons_for_smith) читались бы как «та же кузница».

Запуск из корня проекта:  python tools/make_goblin_forge_icons.py
Выход: assets/ui/goblin_forge/<ветка>.png
"""
import os
from PIL import Image, ImageDraw

OUT = "assets/ui/goblin_forge"
SIZE = 64
BG = (34, 26, 20, 255)
RIM = (176, 132, 64, 255)
RIM_DARK = (92, 64, 28, 255)
LEATHER = (122, 84, 46, 255)
IRON = (168, 170, 176, 255)
IRON_DARK = (96, 98, 104, 255)
BONE = (228, 220, 196, 255)
GREEN = (96, 196, 72, 255)
GREEN_DARK = (40, 110, 36, 255)
MOON = (236, 230, 190, 255)
RED = (180, 44, 40, 255)


def plate(d: ImageDraw.ImageDraw) -> None:
    d.ellipse((2, 2, SIZE - 3, SIZE - 3), fill=BG, outline=RIM_DARK, width=3)
    d.ellipse((4, 4, SIZE - 5, SIZE - 5), outline=RIM, width=2)


def hide(d: ImageDraw.ImageDraw) -> None:
    """Чёрствая шкура: растянутая шкура на колышках."""
    pts = [(18, 16), (46, 16), (52, 32), (46, 50), (18, 50), (12, 32)]
    d.polygon(pts, fill=LEATHER, outline=RIM_DARK)
    for (x, y) in [(18, 16), (46, 16), (46, 50), (18, 50)]:
        d.ellipse((x - 3, y - 3, x + 3, y + 3), fill=IRON_DARK)
    d.line((22, 26, 30, 40), fill=RIM_DARK, width=2)
    d.line((34, 24, 42, 42), fill=RIM_DARK, width=2)


def pikes(d: ImageDraw.ImageDraw) -> None:
    """Зазубренные пики: древко с зубчатым наконечником."""
    d.line((16, 52, 40, 24), fill=LEATHER, width=5)
    tip = [(40, 24), (52, 12), (50, 22), (56, 20), (44, 30), (46, 36)]
    d.polygon(tip, fill=IRON, outline=IRON_DARK)
    d.line((34, 30, 44, 20), fill=IRON_DARK, width=1)


def howl(d: ImageDraw.ImageDraw) -> None:
    """Ночной вой: луна и три волны воя."""
    d.ellipse((14, 12, 44, 42), fill=MOON)
    d.ellipse((22, 8, 50, 36), fill=BG)
    for i, r in enumerate((10, 16, 22)):
        box = (44 - r, 40 - r, 44 + r, 40 + r)
        d.arc(box, 300, 30, fill=BONE, width=2)


def poison(d: ImageDraw.ImageDraw) -> None:
    """Ядовитые наконечники: наконечник стрелы и зелёные капли."""
    head = [(32, 10), (44, 34), (32, 28), (20, 34)]
    d.polygon(head, fill=IRON, outline=IRON_DARK)
    d.line((32, 28, 32, 50), fill=LEATHER, width=3)
    for (x, y) in [(22, 44), (42, 46), (30, 54)]:
        d.ellipse((x - 4, y - 4, x + 4, y + 4), fill=GREEN, outline=GREEN_DARK)


def doping(d: ImageDraw.ImageDraw) -> None:
    """Орочий допинг: череп над кубком."""
    d.ellipse((22, 10, 42, 30), fill=BONE)
    d.rectangle((26, 26, 38, 34), fill=BONE)
    for x in (27, 35):
        d.ellipse((x - 1, 17, x + 5, 23), fill=BG)
    d.polygon([(18, 38), (46, 38), (40, 54), (24, 54)], fill=RED, outline=RIM_DARK)
    d.rectangle((29, 54, 35, 58), fill=RIM_DARK)


ICONS = {
    "hide": hide,
    "pikes": pikes,
    "howl": howl,
    "poison": poison,
    "doping": doping,
}


def main() -> None:
    os.makedirs(OUT, exist_ok=True)
    for name, fn in ICONS.items():
        img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        plate(d)
        fn(d)
        path = os.path.join(OUT, name + ".png")
        img.save(path)
        print("записано", path)


if __name__ == "__main__":
    main()
