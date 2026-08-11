# MAP_ASSETS — Навигатор по папкам ассетов

Здесь написано **куда именно класть** каждый файл.  
Движок автоматически подхватывает ассеты без перезапуска редактора.

---

## Полная структура папок

```
assets/
├── environment/           ← ОБЩИЕ ЭЛЕМЕНТЫ КАРТЫ
│   ├── terrain/           ← Текстуры/спрайты ландшафта
│   └── resources/         ← Спрайты ресурсных узлов (золото, камень, еда, вода)
│
├── ui/                    ← ОБЩИЙ ИНТЕРФЕЙС
│   └── icons/             ← Иконки для HUD-кнопок (зарезервировано)
│
└── factions/              ← ФРАКЦИИ
    └── humans/            ← ФРАКЦИЯ №1: ЛЮДИ
        ├── icons/         ← Иконки меню фракции (кнопки построек, найм)
        ├── buildings/     ← Спрайты/GLB зданий (замок, кузница, бараки, рудник)
        └── units/         ← Войска людей
            ├── soldier_pack/   ← ГЛАВНЫЙ ПАК: горизонтальные спрайт-шиты пехоты
            ├── spearman/       ← Отдельные PNG копейщика
            ├── archer/         ← Отдельные PNG лучника
            └── worker/         ← Отдельные PNG рабочего
```

---

## Таблица: что куда класть

| Путь к папке | Что сюда класть | Пример имени файла |
|---|---|---|
| `assets/environment/terrain/` | Текстуры земли, травы, дорог, гор | `grass_green.png`, `dirt_path.png` |
| `assets/environment/resources/` | Спрайты узлов ресурсов на карте | `Gold Stone 5.png`, `Rock2.png`, `Meat Resource.png`, `Water Background color.png` |
| `assets/ui/icons/` | Иконки для кнопок HUD (64–128 px) | `icon_worker.png`, `icon_castle.png` |
| `assets/factions/humans/icons/` | Иконки меню людей (64–128 px PNG) | `btn_castle.png`, `btn_barracks.png` |
| `assets/factions/humans/buildings/` | Спрайты/GLB зданий людей | `castle.png`, `barracks.png`, `smithy.glb` |
| **`assets/factions/humans/units/soldier_pack/`** | **Спрайт-шиты пехоты (With_Shadows)** | `Human_Soldier_Idle-Sheet.png`, `Human_Soldier_Walk-Sheet.png` |
| `assets/factions/humans/units/spearman/` | Одиночные PNG копейщика (fallback) | `Lancer_Idle.png`, `Lancer_Attack.png` |
| `assets/factions/humans/units/archer/` | Одиночные PNG лучника (fallback) | `Archer_Idle.png`, `Archer_Shoot.png` |
| `assets/factions/humans/units/worker/` | Одиночные PNG рабочего (fallback) | `Warrior_Idle.png`, `Warrior_Run.png` |

---

## Подробно: `soldier_pack/` — Главный пак пехоты

Это самая важная папка. Движок читает её через `SpriteSheetParser` и строит анимированный спрайт автоматически.

**Как скачать:** ищи пак типа `2D Game Assets - Human Soldier` на itch.io или Kenney.  
**Нужна папка `With_Shadows`** из пака — кладёшь её содержимое прямо в `soldier_pack/`.

### Правила именования файлов внутри `soldier_pack/`

| Суффикс файла | Анимация | Пример |
|---|---|---|
| `_Idle-Sheet.png` | Стоит | `Human_Soldier_Idle-Sheet.png` |
| `_Walk-Sheet.png` или `_Run-Sheet.png` | Идёт/бежит | `Human_Soldier_Walk-Sheet.png` |
| `_Attack-Sheet.png` | Атакует | `Human_Soldier_Attack-Sheet.png` |
| `_Death-Sheet.png` | Умирает | `Human_Soldier_Death-Sheet.png` |
| `_Hurt-Sheet.png` | Получает удар | `Human_Soldier_Hurt-Sheet.png` |

### Формат файла спрайт-шита

```
[ кадр 1 ][ кадр 2 ][ кадр 3 ] ... [ кадр N ]   ← горизонтальная полоска
```

- Каждый кадр — **квадратный** (например, 128×128)
- Итоговый размер файла: ширина = высота × количество кадров
- Пример: 8 кадров по 128×128 → файл 1024×128 px
- Формат: **PNG с прозрачностью (RGBA)**, без полей между кадрами

---

## Подробно: `buildings/` — Спрайты зданий

| Имя файла | Здание | Примечание |
|---|---|---|
| `castle.png` | Замок | 512×512, RGBA |
| `barracks.png` | Бараки | 512×512, RGBA |
| `smithy.png` | Кузница | 512×512, RGBA |
| `mine.png` | Рудник | 256×256, RGBA |

Если файл есть — движок показывает его вместо процедурного куба.  
Если файла нет — здание строится из кодовой геометрии (так тоже работает).

---

## Приоритет загрузки ассетов в движке

Для каждого юнита движок перебирает варианты по порядку:

```
1. Спрайт-шит из soldier_pack/ (SpriteSheetParser — анимация)
2. GLB-модель (assets/models/spearman.glb)
3. Одиночный PNG-спрайт (assets/sprites/units/Lancer_Idle.png)
4. Процедурная геометрия (всегда работает, без файлов)
```

Чем выше в списке — тем красивее результат.

---

## Быстрый старт: добавить пехоту за 3 шага

1. Скачай пак солдата (itch.io, Kenney и т.д.)
2. Найди папку `With_Shadows` в архиве
3. Скопируй все `*-Sheet.png` файлы в:
   ```
   assets/factions/humans/units/soldier_pack/
   ```
4. Запусти игру — анимированные спрайты подхватятся автоматически
