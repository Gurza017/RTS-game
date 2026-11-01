"""Карта конфигов: файл → раздел → параметр (строка, значение, пояснение).
Запуск из корня проекта: python -I cfg_map.py > docs/CONFIG_MAP.md
"""
import re, sys, io, os

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", newline="\n")

FILES = [
    ("scripts/spawn_config.gd", "Карта, базы, пни/гноллы/тролли, овцы, красный ИИ (лимиты, дома, башни, охрана, поздние рейды)"),
    ("scripts/ai_start_army_limit.gd", "Поведение красного ИИ: роли, отход, тактики, стартовый состав"),
    ("scripts/unit_stats_config.gd", "Характеристики родов войск, стойки, ветеранство, цены, здания, еда/население, монах, сплочённость, легенда"),
    ("scripts/goblin/goblin_config.gd", "Орда: лагерь, еда, волны, охрана рудников, рейды, штурм, строй-толпа"),
    ("scripts/forge_config.gd", "Древо кузницы: ячейки улучшений, цены, множители"),
    ("scripts/game_difficulty_config.gd", "Пресеты сложности — множители поверх базовых таблиц"),
    ("scripts/perf_config.gd", "Ручки оптимизаций и поведения (A/B-выключатели), шарды"),
    ("scripts/economy_model.gd", "Модель партии на 90 минут"),
    ("scripts/relic_config.gd", "Реликвия-штандарт"),
    ("scripts/tooltip_config.gd", "Тексты подсказок"),
    ("scripts/Constants.gd", "Фракции, группы узлов, слои"),
]

DECL = re.compile(r"^(const|static var|var)\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?::\s*[A-Za-z0-9_\[\]]+)?\s*:?=\s*(.*)$")
SECTION = re.compile(r"^#+\s*[─═]+\s*(.*?)\s*[─═]*\s*$")


def short(v: str, n: int = 38) -> str:
    v = v.strip()
    if v.startswith("{") or v.startswith("["):
        return v[0] + "…" + v[-1] if len(v) > 1 and v[-1] in "}]" else v[0] + "…"
    return v if len(v) <= n else v[: n - 1] + "…"


def main():
    print("# Карта конфигов проекта\n")
    print("Сгенерировано скриптом `tools/cfg_map.py` 27.10.2026. Номер строки — в текущей версии файла;")
    print("после правок перегенерировать: `python -I tools/cfg_map.py > docs/CONFIG_MAP.md`.\n")
    print("| Файл | За что отвечает |\n|---|---|")
    for f, what in FILES:
        print("| `%s` | %s |" % (f, what))
    print()
    for f, what in FILES:
        if not os.path.exists(f):
            continue
        print("\n## `%s`\n\n%s\n" % (f, what))
        lines = open(f, encoding="utf-8").read().replace("\r\n", "\n").split("\n")
        pending_doc = []
        section = None
        rows = []
        for i, ln in enumerate(lines, 1):
            s = ln.strip()
            m = SECTION.match(s)
            if m and (s.startswith("# ") or s.startswith("## ")) and m.group(1):
                if rows:
                    _flush(section, rows)
                    rows = []
                section = m.group(1)
                pending_doc = []
                continue
            if s.startswith("##"):
                pending_doc.append(s.lstrip("#").strip())
                continue
            d = DECL.match(ln)
            if d and not ln.startswith("\t"):
                kind, name, val = d.groups()
                tail = ""
                if "#" in val:
                    head, _, tail = val.partition("#")
                    val = head
                    tail = tail.strip()
                doc = " ".join(pending_doc) if pending_doc else tail
                rows.append((i, name, short(val), doc[:110]))
                pending_doc = []
                continue
            if s and not s.startswith("#"):
                pending_doc = []
        if rows:
            _flush(section, rows)


def _flush(section, rows):
    print("\n### %s\n" % (section or "(без раздела)"))
    print("| Строка | Параметр | Значение | Назначение |\n|---:|---|---|---|")
    for i, name, val, doc in rows:
        print("| %d | `%s` | `%s` | %s |" % (i, name, val.replace("|", "\\|"), doc.replace("|", "\\|")))


if __name__ == "__main__":
    main()
