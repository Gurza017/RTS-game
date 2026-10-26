# -*- coding: utf-8 -*-
"""Фигурки бойцов в полный рост для панелей (ТЗ 25.10.2026, письмо UI №4, п. 2).

Вместо портретов-«голов» в карточке выделения, панели отряда и полосе
мульти-выбора стоят фигуры из спрайтов игры: первый кадр ленты покоя рыцаря,
копейщика, лучника и монаха, по каждому цвету стороны. Кадр обрезается по
непрозрачному силуэту (тень под ногами — полупрозрачный овал — отбрасывается
порогом альфы) и сохраняется в исходных пикселях; в ячейку её вписывает
интерфейс.

Запуск из корня проекта:  python tools/make_unit_figures.py
Выход: assets/ui/unit_figures/<Цвет>/<род>.png (по силуэту)
"""
import os
from PIL import Image

ROOT = "assets/factions/humans/units"
OUT = "assets/ui/unit_figures"
COLORS = ["Blue", "Red", "Purple", "Black"]
UNITS = {
    "warrior": "Warrior/Warrior_Idle.png",
    "spearman": "Lancer/Lancer_Idle.png",
    "archer": "Archer/Archer_Idle.png",
    "monk": "Monk/Idle.png",
}
PAD = 4
SHADOW_ALPHA = 120


def frame_of(sheet: Image.Image) -> Image.Image:
    h = sheet.size[1]
    return sheet.crop((0, 0, h, h))


## Полоса голого древка копейщика (ряды кадра между флажком и шлемом),
## которая вырезается: копьё в 2 роста задаёт высоту, и в квадратной ячейке
## тело выходило вдвое мельче соседей. Наконечник и флажок остаются
SHAFT_CUT = {"spearman": (101, 122)}


def figure(src: str, uid: str = "") -> Image.Image:
    fr = frame_of(Image.open(src).convert("RGBA"))
    cut = SHAFT_CUT.get(uid)
    if cut is not None:
        top = fr.crop((0, 0, fr.size[0], cut[0]))
        bot = fr.crop((0, cut[1], fr.size[0], fr.size[1]))
        joined = Image.new("RGBA", (fr.size[0], fr.size[1] - (cut[1] - cut[0])), (0, 0, 0, 0))
        joined.paste(top, (0, 0))
        joined.paste(bot, (0, cut[0]))
        fr = joined
        # Древко в 2-3 пикселя кадра при вписывании в ячейку 36 px тает в
        # подложку: над шлемом (выше cut[0]) каждый непрозрачный пиксель
        # копируется на соседние по горизонтали — копьё вдвое толще
        src_px = fr.copy().load()
        dst = fr.load()
        for y in range(cut[0]):
            for x in range(1, fr.size[0] - 1):
                if src_px[x, y][3] >= SHADOW_ALPHA:
                    for dx in (-1, 1):
                        if src_px[x + dx, y][3] < SHADOW_ALPHA:
                            dst[x + dx, y] = src_px[x, y]
    px = fr.load()
    w, h = fr.size
    for y in range(h):
        for x in range(w):
            if px[x, y][3] < SHADOW_ALPHA:
                px[x, y] = (0, 0, 0, 0)
    fr = fr.crop(fr.getbbox())
    # Обрезано по силуэту с отступом PAD: в ячейку панели фигуру вписывает
    # сам TextureRect (KEEP_ASPECT_CENTERED) — каждая занимает ячейку целиком
    # по большей стороне. Общий холст «как на поле» пробовали: копейщик с
    # копьём задаёт высоту, и рыцарь в ячейке 34 px выходил в 10 px
    out = Image.new("RGBA", (fr.size[0] + 2 * PAD, fr.size[1] + 2 * PAD), (0, 0, 0, 0))
    out.paste(fr, (PAD, PAD), fr)
    return out


def main() -> None:
    for c in COLORS:
        os.makedirs(os.path.join(OUT, c), exist_ok=True)
        for uid, rel in UNITS.items():
            src = os.path.join(ROOT, c + " Units", rel)
            if not os.path.exists(src):
                print("нет", src)
                continue
            figure(src, uid).save(os.path.join(OUT, c, uid + ".png"))
    print("ok")


if __name__ == "__main__":
    main()
