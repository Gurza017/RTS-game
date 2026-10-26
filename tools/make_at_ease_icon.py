# -*- coding: utf-8 -*-
"""Значок «Вольно» [C] (ТЗ 25.10.2026, письмо UI №4, п. 1).

Чистый силуэт копейщика в расслабленной позе: копьё стоит древком в землю у
плеча, рука держит его на уровне груди, вторая опущена, одна нога прямая,
другая отставлена в сторону. Рисуется полигонами на крупном холсте и
сжимается сглаживанием: силуэт из кадра покоя Lancer_Idle (чиби-фигурка без
видимых ног) в 64 пикселях читался бесформенным пятном. Заливка — светлая
сталь, контур — тёмный, как у соседних значков ряда команд (меч, щит).

Запуск из корня проекта:  python tools/make_at_ease_icon.py
Выход: assets/ui/icons_units_human/AtEase_spearman.png (64x64)
"""
from PIL import Image, ImageDraw, ImageFilter

OUT = "assets/ui/icons_units_human/AtEase_spearman.png"
FILL = (214, 226, 232, 255)
EDGE = (24, 28, 44, 255)
SIZE = 64
BIG = 256


def figure(d: ImageDraw.ImageDraw) -> None:
    w = 255
    # Копьё: древко и наконечник
    d.line((72, 40, 72, 246), fill=w, width=10)
    d.polygon([(72, 4), (58, 44), (72, 38), (86, 44)], fill=w)
    d.rectangle((62, 44, 82, 50), fill=w)
    # Голова в шлеме: купол, поля, лицо
    d.ellipse((116, 34, 168, 86), fill=w)
    d.chord((110, 26, 174, 82), 180, 360, fill=w)
    d.rectangle((108, 52, 176, 60), fill=w)
    # Корпус: плечи шире пояса
    d.polygon([(106, 92), (176, 92), (166, 162), (116, 162)], fill=w)
    d.ellipse((100, 86, 124, 110), fill=w)
    d.ellipse((158, 86, 182, 110), fill=w)
    # Рука к древку и кисть на древке
    d.line((112, 100, 80, 128), fill=w, width=18)
    d.ellipse((64, 118, 88, 140), fill=w)
    # Вторая рука опущена вдоль тела
    d.line((172, 100, 186, 152), fill=w, width=16)
    d.ellipse((176, 146, 196, 166), fill=w)
    # Пояс и бёдра
    d.polygon([(114, 158), (168, 158), (172, 180), (110, 180)], fill=w)
    # Опорная нога прямо, ступня носком наружу
    d.polygon([(114, 176), (138, 176), (136, 236), (116, 236)], fill=w)
    d.polygon([(102, 232), (138, 232), (138, 246), (98, 246)], fill=w)
    # Отставленная в сторону нога
    d.polygon([(146, 174), (170, 172), (214, 232), (194, 240)], fill=w)
    d.polygon([(190, 232), (222, 230), (226, 246), (188, 246)], fill=w)


def main() -> None:
    mask = Image.new("L", (BIG, BIG), 0)
    figure(ImageDraw.Draw(mask))
    bbox = mask.getbbox()
    crop = mask.crop(bbox)
    w, h = crop.size
    pad = 14
    k = min((BIG - 2 * pad) / w, (BIG - 2 * pad) / h)
    crop = crop.resize((int(w * k), int(h * k)), Image.LANCZOS)
    canvas = Image.new("L", (BIG, BIG), 0)
    canvas.paste(crop, ((BIG - crop.size[0]) // 2, (BIG - crop.size[1]) // 2))
    edge = canvas.filter(ImageFilter.MaxFilter(13))
    img = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
    img.paste(Image.new("RGBA", (BIG, BIG), EDGE), (0, 0), edge)
    img.paste(Image.new("RGBA", (BIG, BIG), FILL), (0, 0), canvas)
    img = img.resize((SIZE, SIZE), Image.LANCZOS)
    img.save(OUT)
    print("ok", OUT)


if __name__ == "__main__":
    main()
