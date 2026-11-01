# Проект архитектуры: SquadBrick, диспетчер движения, приоритет приказов, фронт орды

Продолжение разбора `docs/ANALYSIS_2026-10-28_ORDERS_BRICK_PIGBOSS.md`
(там — лог партии, карта кода и причины; здесь — что строим). Номера строк
по HEAD 28.10.2026. Код и имена — предложение к реализации, не готовый патч.

---

## 0. Четыре принципа, из которых всё выводится

1. **Истина об отряде лежит в одной записи, боец — исполнитель.** Форма
   (кирпич) и воля (приказ) принадлежат отряду. У бойца нет своей точки
   назначения, своего приказа и своего права их менять: у него есть место
   в кирпиче и допуск отклонения от места.
2. **Один диспетчер шага.** Куда шагает боец в этом такте, решает одна
   функция по одному намерению (`MoveIntent`); три сегодняшних движителя
   (GDScript-подтягивание, автопилот pull, тыловой напор) становятся тремя
   режимами одного прохода ядра.
3. **Прогресс меряется по факту смещения, а не по намерению.** «Бег на
   месте» — это `|Δpos| ≈ 0` при `velocity ≠ 0`; детектор один, в ядре, и
   он же управляет лентой походки.
4. **Приоритет — свойство источника, а не таймер.** Приказ игрока не
   «защищён три секунды», он старше любого внутреннего источника, пока
   не исполнен или не заменён игроком.

Всё, что ниже, — следствия. Если какое-то правило им противоречит, оно
написано неверно.

---

## 1. Состав изменений по файлам

### 1.1. Новые файлы

| Файл | Что | Хранение |
|---|---|---|
| `scripts/army/SquadBrick.gd` | геометрия отряда: рамка, сетка, посадка, операции | `GameManager.squads[sid]["brick"]` (RefCounted), горячие колонки — в ядре |
| `scripts/army/SquadOrder.gd` | приказ отряда и его приоритет | `squads[sid]["order"]` |
| `scripts/army/MoveIntent.gd` | константы режимов шага и упаковка намерения в ядро | без состояния (static) |
| `csharp/ArmyCore.Brick.cs` (partial) | `BrickWrite`, `BrickLag`, `BrickFront`, `ProgressPass`, `HoldPass` | колонки `_bkSid`, `_bkCell`, `_bkRow`, `_bkCol`, `_postX/_postZ` (есть), `_progAcc`, `_progRef`, `_stallN`, `_intent` |
| `qa_brick/`, `qa_squad_order/`, `qa_stall/`, `qa_horde_front/` | стенды | — |

### 1.2. Изменяемые

| Файл | Что меняется |
|---|---|
| `scripts/Unit.gd` | `command_move/command_attack` становятся **исполнителями** (вызов только из `GameManager.squad_issue` и из кирпича); `_process_move`/`_process_attack` читают приказ отряда первой строкой; удаляются `_move_lock`/`player_order_active`/`_player_march`/`_disengaging`/`_march_target`/`_march_pending`/`_leash_*`/`_pursuit_*`/`_tick_stuck`/`_stall_arrived`/`_should_pull_up`; `_may_unstick`/`_unstick` остаются как **реакция на событие `STALL_HARD`** из ядра, а не как самостоятельный детектор |
| `scripts/GameManager.gd` | `squad_issue(sid, order)` — единственный писатель приказа; `_cohesion_guard`, `squad_close_ranks`, `_sweep_reform`, `_reform_check`, `_slots_recentered`, `_formation_settle`, `_formation_in_place`, `_default_block_slots`, `free_squad_spot`, `squad_counter_charge`, `_assign_rear`, `_recalc_melee` (аренда напора) — удаляются или сводятся к вызовам кирпича; `squads[sid]` теряет ключи `slots`, `course`, `at_order`, `reshuffled`, `reform_*`, `calm_ms`, `arrived`, `catch_up`, `dent` |
| `scripts/units/SquadFormation.gd` | удаляется целиком (`close_ranks`, `centred_tail`, `_per_row` заменяет `SquadBrick`) |
| `scripts/army/SquadBox.gd` | вливается в `SquadBrick` (режим `front`): `_write_goals`, `_refill`, `_advance`, `_press`, `_push_off`, `_friend_ahead`; `_wants_box`/`_release` исчезают — кирпич есть всегда |
| `scripts/SelectionManager.gd` | все раскладки (`_compute_line_slots`, `_block_formation_slots`, `_deep_formation_slots`, `_layered_formation_slots`, `_issue_march_keeping_shape`, `_box_template`) заменяются на параметры кирпича (`cols`, `C`, `course`) + `GameManager.squad_issue`; любой клик по выделению — один `squad_issue` на отряд, который сам снимает [A] |
| `scripts/SquadCommander.gd` | становится исполнителем приказа `ATTACK_MOVE`: своя очередь `_oq` живёт внутри записи приказа и умирает вместе с ней; `_keep_column` заменяется гейтом отставания кирпича |
| `scripts/EnemyAI.gd`, `scripts/goblin/GoblinAI.gd`, `GoblinFortressAssaultEvent.gd`, `CavalryCommander.gd`, `ai/HomeGuard.gd` | свои планы мест (`_slot_at`, `horde_offset`, `cols`) → `squad_issue` с параметрами кирпича; свои очереди приказов → источник `SRC_AI` в `squad_issue` |
| `csharp/ArmyCore.cs` | `SquadRecalc` перестаёт считать ряды (их пишет кирпич); `RearPressPass`, `AutopilotPass` (режим pull) и `TickSnooze` сводятся в `MovePass` по `_intent`; `BatchMoveRows` — без изменений (ScanBlock, пол союзников, билеты) |
| `scripts/perf_config.gd` | ручки `brick`, `squad_order`, `move_dispatch`, `horde_front` — каждая с проверкой выключением на своём стенде |

### 1.3. Что удаляется навсегда (список для `git rm`/правок)

Механизмы, которые двигали бойца НЕ к его месту (карта в ANALYSIS, 2.1):
`_cohesion_guard`, `_leash_check`/`CHASE_LEASH`, `PURSUIT_LIMIT`/
`_end_squad_pursuit`/`squad_pursuit_anchor`, `AGGRO_LEASH`,
`_hold_where_i_stand`, `_formation_settle`, `_slots_recentered`,
`_slots_moved_to`, «лишние» шагом 0.9/0.7, `squad_dent` как правка точек,
`_sweep_phalanx_press` как правка точек, `squad_counter_charge`,
`_assign_rear`/`_rear_step`/`battle_lines`, `RearPressPass`,
`_should_pull_up`/`PULL_UP_MAX`, `FORCED_MOVE_SEC`/`_move_lock`,
`_disengaging`/`retreat_squad_lock`, `_lock_sight_range` для пехоты,
`_tick_stuck`/`STUCK_CHECK_SEC`/`_stall_arrived`, `cure_run_in_place`,
`GoblinAttackCommander.gd` (мёртвый). Восемь констант интервалов
(`UNIT_SPACING`, `ROW_DEPTH`, `BLOCK_SPACING`, `BLOCK_ROW_DEPTH`,
`SQUAD_SPOT_SPACING`, `EnemyAI.SQUAD_SPACING`, `REAR_RANK_DEPTH`,
`PHALANX_GAP`) → два поля рода `gx`, `gy` в `unit_stats_config`.

---

## 2. SquadBrick — математика

### 2.1. Рамка и сетка

```
class SquadBrick:
    var sid: int
    var C: Vector2          # центр сетки (XZ). КОМАНДНЫЙ, не измеренный
    var u: Vector2          # курс, единичный; ряд 0 — передний, по +u
    var v: Vector2          # бок = rot90(u) = Vector2(-u.y, u.x)
    var gx: float           # интервал по фронту (род войск)
    var gy: float           # глубина ряда (род войск)
    var cols: int
    var rows: int
    var cell: PackedInt32Array   # cell[row*cols+col] = soa-строка или -1
    var seat: PackedInt32Array   # seat[soa] = индекс ячейки (обратная карта)
    var n: int                   # живых
    var mode: int                # MARCH | STAND | FRONT (бой)
    var ex: float; var ey: float # допуск отклонения (см. 2.5)
    var front_contact: PackedByteArray  # по колонкам, режим FRONT (см. 5)
```

Место ячейки `(col, row)`:

```
slot(col, row) = C + v * ((col - (cols - 1) * 0.5) * gx)
                   - u * ((row - (rows - 1) * 0.5) * gy)
```

Неполная последняя шеренга `k = n - (rows-1)*cols` центрируется сдвигом
колонки: `col' = col + (cols - k) * 0.5` (полуцелый сдвиг, как в
`SquadBox._build` 362). Ширина `W = (cols-1)*gx`, глубина `D = (rows-1)*gy`,
полуразмеры идут в `squad_inside` вместо круга `sqrt(n)*0.5*0.62`.

### 2.2. Число колонок

Одна таблица в `unit_stats_config` на род:

```
BRICK = {
  "spearman": {"gx": 0.55, "gy": 0.60, "min_rows": 2, "wide_max": 3.0, "cols_default": 10},
  "warrior":  {"gx": 0.55, "gy": 0.60, "min_rows": 1, "wide_max": 4.0, "cols_default": 10},
  "archer":   {"gx": 0.60, "gy": 0.70, "min_rows": 2, "wide_max": 3.0, "cols_default": 10},
  "goblin_spearman": {"gx": 0.80, "gy": 0.80, "min_rows": 2, "wide_max": 2.5, "cols_default": 10, "jitter": 0.45},
  ...
}
cols(n, want) = clamp(want, ceil(n / rows_max(n)), floor(sqrt(n * wide_max)))
rows(n, cols) = ceil(n / cols)
```

`want` приходит от режима: [1] широкий — `cols_default`, [2] глубокий —
`ceil(n / rows_target)`, протяжка — `floor(L / gx)`, ИИ — свой. Зажим
гарантирует `rows ≥ min_rows` и `W ≤ wide_max · D`. Для 60 копейщиков
допустимы 6×10, 5×12, 10×6, 12×5; 15×4 — нет (W/D = 4.3 > 3).

### 2.3. Посадка (assignment)

Полная посадка — только при выдаче приказа и при перестройке (смена
`cols`). Алгоритм `_topo_order` из SelectionManager (сортировка по `along`
= `(pos-C)·u`, затем `lat` = `(pos-C)·v`, раздача ячеек спереди назад,
слева направо) — O(n log n), без пересечений дорог в типичном случае.
Венгерский алгоритм не нужен: отряд ≤ 100, пересечения при топологической
посадке редки и разрешаются расталкиванием.

Частичная посадка (смерть, пополнение) — **локальная**, без перебора
(2.4). Это принцип «тугости»: соседство фиксировано между приказами.

### 2.4. Операции

**`rotate(theta_target, dt)`.** `u` поворачивается к цели не быстрее
`OMEGA` (рад/с, у пехоты ≈ 1.2, у конницы 2.0). Места пересчитываются,
посадка **не меняется** — бойцы идут к новым местам. Если поворот больше
`FLIP_DEG` (120°), выгоднее пересадка: ряды меняются местами
(`cell[r][c] ↔ cell[rows-1-r][cols-1-c]`) — O(n) и без пересечений, бойцы
стоят, меняется только нумерация. Разворот «кругом» бесплатен по движению.

**`translate(step)`.** `C += step`, где `|step| ≤ v_brick · dt`,
`v_brick = min(v_slowest_member, v_order)`. Гейт отставания: ядро
возвращает `lag80 = p80(|pos_i − slot_i|)` (`BrickLag`), и при
`lag80 > LAG_MAX` (0.7, из SquadBox) центр **не двигается**: кирпич ждёт
отставших, а не растягивается. Это единственное место, где «стягивание»
существует: не бойцы тянутся к центру масс, а центр не убегает от бойцов.

**`on_death(soa)`.** Ячейка `(col,row)` освобождается, колонка
сдвигается вперёд: `cell[r][col] = cell[r+1][col]` для `r ≥ row`
(`SquadBox._refill`). Затем проверка монолитности:

```
h[c] = высота колонки c
if max(h) - h[col] >= 2:            # дыра в две глубины — рваный край
    # перенести хвостового из самой высокой колонки в col
    move cell[h[c*]-1][c*] -> (col, h[col])
if rows*cols - n >= cols:           # освободилась целая шеренга
    rows -= 1
if rows < min_rows:                 # стало слишком широко
    cols = cols(n, cols-1); re-seat (2.3) — редкое событие
```

Так сжатие идёт **с хвоста и монолитно**: углов нет по построению, потому
что ячейка существует только внутри `rows × cols`, а в неполной шеренге
только центрированные позиции.

**`on_join(soa)`.** Место в хвосте (`n`-я ячейка), при `n > rows*cols` —
`rows += 1`. Пополнение из замка встаёт назад, а не «лишней шеренгой» с
захардкоженным шагом.

**`stretch(L)`.** `cols = cols(n, floor(L/gx))`, `rows = ceil(n/cols)`,
пересадка 2.3. Протяжка ПКМ меняет только `cols` и `u` — всё.

**`set_frame(C, u)`** — приказ: новая рамка, пересадка 2.3 **по текущим
позициям** (ближние к новому центру садятся вперёд). Форма при этом
никогда не берётся с позиций (это и было «пятно как форма» в
`_issue_march_keeping_shape`).

### 2.5. Эластичность: допуск, а не сила

Отклонение бойца `e_i = pos_i − slot_i`, в координатах рамки
`(e_i·v, e_i·u)`. Боец **внутри**, если `|e_i·v| ≤ ex` и `|e_i·u| ≤ ey`.

| Режим | `ex` | `ey` | Смысл |
|---|---|---|---|
| MARCH | 0.7·gx | 1.0·gy | обойти ствол, тело, скользнуть |
| STAND | 0.5·gx | 0.5·gy | стоять |
| FRONT (бой) | 1.5·gx | 2.0·gy | дотянуться до цели, обойти труп, войти во фланг |

Правила:
- Внутри допуска боец вправе брать личные цели в длине оружия, скользить,
  отвечать на удар. Снаружи — **не вправе ничего**, кроме шага к месту
  (`MoveIntent.TO_SLOT`). Нет ни возврат-приказа, ни силы, ни якоря:
  право на инициативу просто выключается.
- Место бойца не меняет никто, кроме кирпича. `post_pos` в `Unit`
  становится кэшем `slot(seat[soa])`, который ядро обновляет при
  `BrickWrite`.
- «Центр масс» в модели не используется для управления. `drift =
  median(pos) − C` считается только зондом (`squad_split`) и для гейта
  `lag80`.
- **Отставший навсегда** (застрял у леса, `STALL_HARD` дважды, см. 3):
  кирпич зовёт `on_leave(soa)` — ячейка сдвигается как при смерти, боец
  получает `TO_SLOT` к **хвосту** кирпича через навигацию отряда
  (`squad_leg`), а когда входит в `ey` от хвоста — `on_join`. Он не
  становится агентом: у него по-прежнему нет целей и нет приказа,
  только место «в хвосте».

### 2.6. Ряды и ядро

`BrickWrite(sid, soa[], cellIdx[], x[], z[], row[])` — один вызов на
пересчёт, пишет `_postX/_postZ`, `_rank = row`, `_bkCell`, `_bkRow`,
`_bkCol`. `SquadRecalc` больше не ищет «сколько своих впереди в полосе
0.45 м»: ряд известен по сетке (минус ветка `rank_recompute`). Все
потребители `_live_rank` (дрёма, коробка, напор, ИИ) читают тот же ряд.

Пересчёт мест — по событию (приказ, смерть, поворот > 2°, перенос > 0.1 м),
не покадрово: на марше это один `BrickWrite` в такт кирпича
(`BRICK_TICK_SEC` 0.1), в стоянке — ноль.

---

## 3. Диспетчер движения и прогресс (бег на месте, зависания)

### 3.1. Намерение шага — одно на бойца

Боец не пишет `velocity` и не зовёт `_commit_step` из пяти веток. Он
пишет **намерение**, ядро — шаг:

```
MoveIntent { mode, gx, gz, speed, stop, flags }
mode: HOLD        — стоять (ячейка в бою, ожидание фронта, тупик)
      TO_SLOT     — к своему месту (марш, стоянка, возврат в допуск)
      TO_TARGET   — к цели в бою до дистанции stop (подход, сцепка)
      RETREAT     — к точке отхода с билетом F_ORDER_PASS, без боя
      FLEE        — паника (как сегодня panic_flee)
      FLING       — разлёт от тарана (как сегодня _tick_fling)
```

`MovePass` в ядре раз в такт бойца: `TO_*` — направление `_nav_dir`
(обход у любого хода, как сегодня), скорость `speed`, флаги в
`BatchMoveRows` без изменений. `AutopilotPass` (режим goal/pull),
`RearPressPass`, `TickSnooze`, `_arm_hold_autopilot` — это четыре частных
случая `MovePass` и сливаются в него. GDScript-тик бойца пропускается,
пока намерение исполняется (как `TickRows` сегодня), и просыпается по
событию (3.3).

### 3.2. Прогресс — по факту смещения

В ядре на строку: `_progX/_progZ` (позиция на начало окна), `_progRef`
(дистанция до `gx,gz` на начало окна), `_stallN`. Раз в `PROG_WINDOW`
(0.4 с, как `NAV_RECHECK_SEC`) `ProgressPass`:

```
disp   = |pos - prog|                     # фактическое смещение
expect = speed * PROG_WINDOW
dref   = |goal - pos|
stalled = (mode in TO_*) and disp < 0.15 * expect and dref > stop + 0.1
_stallN = stalled ? _stallN + 1 : 0
prog = pos; progRef = dref
```

События по `_stallN` (одно поле, одна лестница вместо `_tick_stuck`,
`_stall_arrived`, `STUCK_RETARGET_STREAK`, `ProbeStuckRows`,
`cure_run_in_place`):

| `_stallN` | Событие | Кто обрабатывает | Что делает |
|---|---|---|---|
| 1 | `STALL_SOFT` | ядро | repath: сброс кэша `nav_last_ok`, `_nav_dir` пересчитан немедленно, `F_TRUNK_IGNORE` |
| 2 | `STALL_ARRIVE` (если `dref ≤ clamp(2·r·1.6, 1.2, 3.0)`) | ядро | считать прибывшим: `mode = HOLD`, событие `ARRIVED` бойцу |
| 2 | `STALL_HARD` | GDScript, событие | `_unstick`: `passable_exit`/`nearest_passable`, затем `TO_SLOT` к хвосту кирпича (2.5); **приказ отряда не трогается** |
| 4 | `STALL_GIVEUP` | кирпич | `on_leave(soa)`; боец идёт дорогой отряда `squad_leg` к хвосту; личных целей нет (2.5) |

Замечания по корням сегодняшних «бегов на месте»:
- Спящая охрана «бежала» 42 мин (аудит 28.10): строка узнавала `state`
  только из `queue_pose`. В модели состояние ленты **не читает `state`**:
  `LookPass` берёт `disp` из `ProgressPass` — смещение за окно < 0.05 м →
  лента покоя, независимо от того, что думает GDScript. Бег на месте
  невозможен по построению, зонд `stuck_running` становится проверкой
  инварианта «лента ходьбы ⇒ disp > 0».
- Упор в соседа у точки = прибытие (`stall_arrive`) — остаётся как
  `STALL_ARRIVE`, но считается ядром и для всех режимов `TO_*`, а не только
  MOVING без цели.
- «Ступор под ударами»: удар не меняет `mode`. `take_damage` может только
  (а) поставить `_melee_grip` на бьющего в упор, если допуск позволяет
  (2.5) и приказ отряда не `RETREAT`/`MOVE`; (б) запросить у отряда
  `squad_note_hit` для морали. Никакого `command_attack` из `take_damage`
  и никакого `squad_counter_charge`: ответ отряда на обстрел — решение
  приказа уровня P4 (4.2), т.е. отряд без приказа игрока разворачивается
  целиком кирпичом (`rotate` к стрелку + `set_order(ATTACK, SRC_REFLEX)`),
  а не каждый боец врозь.

### 3.3. Автомат бойца — три состояния и события

`State { IDLE, MOVING, ATTACKING }` остаются (рабочие — свои), но
переходы задаёт **приказ отряда + допуск**, а не таймеры:

```
tick(unit):
    o = squad.order
    if not brick.inside(unit): intent = TO_SLOT; return     # вне допуска — только домой
    match o.kind:
        RETREAT, MOVE, HOLD:  intent = TO_SLOT (или HOLD, если на месте)
                              # боя нет. wall → скольжение с билетом; grip только на бьющего в упор
        ATTACK, ATTACK_MOVE:  if target in reach: strike; intent = HOLD (snooze в ядре)
                              elif row < strike_rows and front free: intent = TO_TARGET
                              else: intent = HOLD (ждать фронт, см. 5)
        NONE:                 ambient: auto-aggro в длине оружия + AGGRO_RADIUS, внутри допуска
```

События, будящие GDScript-тик (всё остальное время боец спит в ядре):
`ARRIVED`, `STALL_HARD`, `STALL_GIVEUP`, `ENEMY_CONTACT` (как сегодня
`PressWake`), `TARGET_LOST`, `HIT`, `SLOT_MOVED` (кирпич переписал место
дальше `ey`), `ORDER_CHANGED` (от `squad_issue`, рассылается пачкой через
`TickRows`-список отряда, без обхода бойцов из GDScript).

---

## 4. Приоритет приказов

### 4.1. Запись приказа

```
class SquadOrder:
    var kind: int      # NONE, MOVE, HOLD, ATTACK, ATTACK_MOVE, RETREAT, GARRISON
    var src: int       # SRC_PLAYER=0, SRC_COMMANDER=1 (ИИ/босс/конница), SRC_REFLEX=2, SRC_AMBIENT=3
    var prio: int      # вычисляется: см. таблицу
    var point: Vector2 # цель хода / точка отхода
    var target_sid: int = -1 ; var target_bld: int = -1
    var issued_ms: int ; var by_player: bool
    var exec: RefCounted # исполнитель: SquadCommander-контекст у ATTACK_MOVE (очередь _oq живёт здесь)
```

| Приоритет | Вид | Источник | Кто вправе заменить |
|---|---|---|---|
| **P0** | `RETREAT`, `GARRISON` | игрок | только игрок |
| **P1** | `MOVE`, `HOLD` | игрок | игрок |
| **P2** | `ATTACK`, `ATTACK_MOVE` | игрок | игрок; истребление цели → `HOLD`(P1-авто) |
| **P3** | любой | командир ИИ (EnemyAI, GoblinAI, CavalryCommander, босс) | игрок (у своих), командир |
| **P4** | `ATTACK` | рефлекс отряда (обстрел ≤ 12 м, удар по стоящему отряду без приказа) | всё старше |
| **P5** | личная цель в длине оружия | боец, внутри допуска | не приказ вовсе: не пишется в запись |

### 4.2. Единственный писатель

```
GameManager.squad_issue(sid, order) -> bool:
    cur = squads[sid].order
    if order.prio > cur.prio and not cur.done: return false     # младший не перебивает старшего
    if cur.exec: cur.exec.cancel()                                # [A]: очередь _oq, _am, pace — атомарно
    squads[sid].order = order
    brick.set_frame(order.frame_C, order.frame_u) if order.has_frame
    army.order_broadcast(sid, order.kind)                         # ORDER_CHANGED всем строкам отряда (ядро)
    return true
```

Следствия, закрывающие семь механизмов из ANALYSIS 1.2:

- **Перехват марша** (`_process_move` 6667-6731): боец под `MOVE`/`RETREAT`
  не входит в `ATTACKING`. `wall` → скольжение с билетом (`_retreat_pass`
  уже выдаёт `F_ORDER_PASS` на 2.5 м; под `RETREAT` билет выдаётся на всю
  дорогу), при `STALL_ARRIVE` — `HOLD` без боя; `_melee_grip` только на
  того, кто бьёт в упор, и только пока он в допуске. `_disengaging` не
  нужен: «выход из боя» — это `RETREAT`/`MOVE` любого бойца, у которого
  была цель, и его снимает только игрок.
- **Вызволение**: реакция на `STALL_HARD` (3.2); не пишет приказ, не
  пишет место; `_giveup_hold` не нужен — вне допуска целей нет.
- **Сплочённость**: нет. Допуск (2.5) + гейт `lag80` (2.4).
- **Смыкание**: нет. `on_death` (2.4) — немедленно, в бою тоже
  (сдвиг колонки — это и есть замещение фронта).
- **Поводки**: нет. Под `ATTACK` P2 цель, отошедшая дальше
  `standoff + ENGAGE_R` от грани, не преследуется бойцами (они вне
  допуска не шагают), а кирпич переходит в `FRONT_HOLD` у точки
  последнего контакта; возобновление, когда цель снова в `ENGAGE_R`.
  Замок не снимается: его снимает игрок или истребление отряда-цели.
  `lock_lost_sight` у пехоты — удаляется; у стрелков — остаётся как
  `3·range`, но переводит в `FRONT_HOLD`, а не в авто-агро.
- **Контратака отряда** (`squad_counter_charge`): становится `squad_issue(
  ATTACK, SRC_REFLEX)` — проходит только при `cur.prio ≥ P4`, т.е. у отряда
  без приказа игрока/командира. Под P0-P3 обстрел игнорируется (стрелки
  отвечают из допуска, пехота идёт дальше).
- **[A] и «Отойти»**: `ATTACK_MOVE` — приказ P2 с исполнителем
  (`SquadCommander` в роли `exec`). Любой `squad_issue` P0/P1 зовёт
  `exec.cancel()` **до** записи: `_oq`, `_am`, `pace`, `_keep_column`
  умирают атомарно, отложенные приказы не догоняют. Протяжка ПКМ и
  повторный [A] идут тем же путём. Паразитных разворотов нет, потому
  что единственный источник `command_attack` под P0 — никто.
- **Лазарет, стройка, ловушка**: `transient`-намерения (`TO_SLOT`-подобные
  с чужой точкой), не приказ: по завершении боец возвращается к
  исполнению приказа отряда, место не переписано.

### 4.3. Исполнение и завершение

Приказ исполнен (`done`), когда кирпич прибыл: `lag80 ≤ ex` и `|C −
point| ≤ ARRIVE`. Тогда `kind = HOLD(P1-авто)`, а через `AMBIENT_AFTER_SEC`
(2 с) — `NONE`: только теперь разрешены авто-агро (P5) и рефлексы (P4).
«Воля игрока имеет абсолютный вес» формально означает: `prio(player) <
prio(всё остальное)` и `done` ставит только исполнение или сам игрок.

Для ИИ (`SRC_COMMANDER`) — тот же API: `GoblinAI._order_*`,
`EnemyAI._issue`, `CavalryCommander` зовут `squad_issue(sid, order,
SRC_COMMANDER)`; у фракций ИИ P0-P2 никто не выдаёт, поэтому для них
командир — старший. Бюджет раздачи (`ORDER_BUDGET` 40 бойцов/кадр) больше
не нужен: `squad_issue` — один вызов на отряд, бойцы узнают о приказе
через `order_broadcast` в ядре (запись одного int в колонку по списку
строк отряда).

### 4.4. Миграция вызовов

| Сегодня | Станет |
|---|---|
| `Unit.command_move(p, …, player_order=true)` из SelectionManager | `squad_issue(sid, MOVE, point, frame)` |
| `Unit.command_attack(t, forced, charge, lock)` из SelectionManager | `squad_issue(sid, ATTACK, target_sid/bld)` |
| `SquadCommander.attack_move` | `squad_issue(sid, ATTACK_MOVE, point, exec=SquadCommanderCtx)` |
| F1 / `squad_to_castle` | `squad_issue(sid, GARRISON, bld)` → `Castle.request_garrison` |
| `GoblinAI._order_attack_squad` | `squad_issue(sid, ATTACK, foe, SRC_COMMANDER)` |
| внутренние `command_move` (unstick, heal, build) | `unit.set_transient(point, run)` — не приказ |
| `command_attack(blocker, false)` (перехват, grip) | `unit.set_grip(foe)` — личная цель P5 внутри допуска |

---

## 5. Фронт орды: ожидание и смена

### 5.1. Фронт как свойство кирпича

Режим `FRONT` включается у любого кирпича с приказом `ATTACK*` при
`|C − enemy| ≤ ENGAGE_R` (как `_wants_box`, но без исключения орды).
Ядро раз в такт кирпича (`FRONT_TICK_SEC` 0.25) считает по колонкам
`front_contact[c]` = у бойца ячейки `(c, 0)` есть враг в `reach + 0.6`
(тот же критерий, что у дрёмы, `ATK_SNOOZE_REACH_SLACK`), и
`front_free = число колонок без контакта`.

### 5.2. Правило ряда

```
row == 0, 1 (strike_rows):  TO_TARGET до standoff; удар; snooze в ядре
row >= 2:
    if front_contact[col]:         intent = HOLD   # «фронт перед нами занят»
    elif column_front_free:        intent = TO_SLOT (слот уже на standoff — колонна подтягивается кирпичом)
```

`HOLD` — это `MovePass` без шага и без сканов: ни `EnemyNear`, ни
`ScanAllyFloor`, ни GDScript. Пробуждение — событиями: `SLOT_MOVED`
(сдвиг колонки после смерти переднего: ряд 2 стал рядом 1 — шаг вперёд
на `gy`), `FRONT_MOVED` (грань продвинулась), `ENEMY_CONTACT` сбоку/сзади
(`ScanBlock` уже ставит его), `ORDER_CHANGED`.

Напор остаётся только как `_press` по рядам (`PRESS_ROW_W`), который
теснит **врага** суммой сил и двигает грань; толкать своих некому.
`RearPressPass`, `_should_pull_up`, автопилот pull — удалены (1.3).

### 5.3. Обход по флангам — операция кирпича

Раз в такт кирпича, если `front_free == 0` и `rows ≥ 3`:

```
for side in (-1, +1):
    p = F + v*side*(W/2 + gx)            # точка рядом с краем фронта
    if army.enemy_count(p, gx*1.5, fac) == 0 and allies_near(p) == 0 and passable(p):
        cols += 1 на стороне side          # новая колонка; хвост последней шеренги переезжает в неё
        break
```

Фланг открывается **колонкой**, а не бойцом: ячейки хвоста получают
места в новой колонке у фронта, и `strike_rows` этой колонки начинают
бить во фланг. Если обе точки заняты (свои кирпичи или враг) — ждём.
При `rows` упавшем до `min_rows` фланг не открывается (нечем).

Второй кирпич орды за первым (`_friend_ahead` из SquadBox): встаёт в
`FRONT_HOLD` за союзным, а по тому же правилу 5.3 уходит в свой фланг
колонками, не телами.

### 5.4. Смена фронта («римская»)

Два дешёвых правила, оба — своп двух ячеек:
- `on_death` — сдвиг колонки (уже).
- Раненый в ряду 0 с `hp < RELIEF_HP` (0.3) и ряд 1 за ним цел →
  `swap(cell[0][c], cell[1][c])` с остыванием `RELIEF_CD` 4 с на колонку.
  Два `SLOT_MOVED`, два шага на `gy`. Контакт не рвётся: передний
  отходит на `gy` назад, задний — вперёд, оба внутри допуска.

### 5.5. Что это даёт по тику и ворота

Сегодня у 100-гоблинского отряда 10×10 в контакте 10-20 бойцов, остальные
80-90 каждый личный тик шагают в пол своих (три движителя + `ScanAllyFloor`
×2). В модели эти 80-90 — `HOLD` в ядре: ноль GDScript и ноль сканов до
события. Ожидание по замерам проекта: ветка подхода — «три четверти
тика у 74 % бойцов без цели» (`ArmyCore.cs:24-29`), худший физтик партии
17 мс при 2664 атакующих.

Ворота (A/B чередованием `qa_ab`/`qa_mass3k`, ручка `horde_front`):

| Метрика | База (`battle_lines` выкл) | Требование |
|---|---|---|
| физтик рубки | 24.4 мс (qa_mass_battle 5000) | −20 % и больше |
| доля в контакте | 33 % | ≥ 30 % |
| ударов за окно | 1650 | ≥ 90 % |
| исход боя орды (qa_box_front A) | −91 наших без коробки | не хуже, чем с коробкой (−18) |

Если контакт падает ниже 30 % — гипотеза «сдвиг колонки + подтягивание
кирпича держат фронт» не подтвердилась; `battle_lines` падал до 18 %
именно потому, что фронт не пополнялся. Разница модели ровно в
`on_death` и `translate` грани.

---

## 6. Что меняется для стендов и ручек

### 6.1. Ручки (`perf_config`)

`brick` (этап B0-B2), `squad_order` (B1), `move_dispatch` (3),
`horde_front` (5), `brick_relief` (5.4), `brick_flank` (5.3). Каждая
проверяется выключением на своём стенде; при выключенной `brick`
старый путь (`slots`/`close_ranks`) остаётся до конца миграции, потом
удаляется.

### 6.2. Стенды

| Стенд | Проверки |
|---|---|
| `qa_brick` (новый) | 60 → −40 даёт 5×4 без углов (`h[c]` разброс ≤ 1); поворот на 90° — ноль пересечений дорог, на 180° — ноль шагов; протяжка 6×10 → 10×6 за одну пересадку; пополнение 12 из замка — в хвост; `lag80`-гейт: кирпич ждёт застрявшего и не растягивается > ey |
| `qa_squad_order` (новый) | сценарии из лога: отряд 107 (замок не гаснет порциями, `order_override_bug` = 0), отряд 290 (половина не уходит за целью на 100 м), «Отойти» под [A] сквозь свалку (0 разворотов, `_oq` пуст) |
| `qa_stall` (новый) | бег на месте невозможен: 0 строк с лентой ходьбы при `disp < 0.05`; `STALL_ARRIVE` у соседа; `STALL_GIVEUP` у лесной стены → `on_leave` → `on_join` |
| `qa_horde_front` (новый) | 10×10 против стены копий: ряды ≥ 2 в HOLD, сканов у них 0; смерть переднего → шаг за один такт; фланг открывается колонкой; контакт ≥ 30 % |
| переписать | `qa_target_lock`, `qa_attack_move_override`, `qa_forced_retreat_in_combat`, `qa_squad_leash_test`, `qa_reform`, `qa_reform_idle`, `qa_formation_keys`, `qa_squad_reordering_fix`, `qa_box_front`, `qa_wall` A2, `qa_mega_battle` B2-2, `qa_combat_gate` E, `qa_houses_and_phalanx_march`, `qa_movement_trajectories` |
| регрессия | весь шлюз + `qa_ai_loop/Smoke 15` + `qa_bigstand/Owner` + оконный `qa_visual_smoke` (лента походки теперь от ядра) |

---

## 7. Порядок внедрения

| Этап | Содержание | Ворота |
|---|---|---|
| B0 | `SquadBrick` как зеркало `slots` (строится при `squad_set_formation`), пишет ряды в ядро вместо `SquadRecalc`; `ProgressPass` считает `_stallN` **параллельно** старому детектору, только зонд | шлюз как на HEAD; `qa_ab` тик не хуже; зонд `stall` совпадает со `stuck_running` ≥ 90 % |
| B1 | `SquadOrder` + `squad_issue`; все приказы игрока и ИИ через него; семь механизмов читают `order.prio` вместо `_move_lock`; `exec.cancel()` у [A]; `_disengaging` удалён | `qa_squad_order`; Smoke 15 мин: `order_override_bug` только `panic` |
| B2 | `MoveIntent`/`MovePass`: слияние автопилота, напора, дрёмы, hold; лента походки от `disp`; `_tick_stuck`/`cure_run_in_place` удалены | `qa_stall`; `qa_log_1028` A переписан; `qa_ab` |
| B3 | Кирпич — источник мест: `on_death/on_join/rotate/stretch/set_frame`; `SquadFormation.gd` удалён; `SelectionManager` раскладки → параметры кирпича | `qa_brick`, `qa_reform*`, `qa_formation_keys` |
| B4 | Режим `FRONT` (SquadBox внутрь кирпича), допуск 2.5, поводки и сплочённость удалены | `qa_box_front`, `qa_wall`, `qa_mega_battle`, `qa_clash`; A/B |
| B5 | Орда в кирпиче с джиттером, `horde_front` (HOLD, фланг колонкой, смена) | `qa_horde_front`; ворота 5.5; `qa_goblin_base_assault`, `qa_horde2` |
| B6 | Слияние огрызков для всех фракций (`_regroup` → `GameManager.squad_merge`), удаление мёртвого кода и старых ручек | `qa_tz1027d` F/G, шлюз |

Каждый этап — отдельная ручка и отдельный коммит; A/B на HEAD через
`git stash` + `dotnet build` по правилам замера из CLAUDE.md.

---

## 8. Развороты требований, которые модель затрагивает

1. Коробки отрядов выключены 25.10 (`box_front=false`) — кирпич их
   возвращает на всю жизнь отряда.
2. Орда — «толпа, не прямоугольник» (ТЗ 25.10) — кирпич с джиттером.
3. Поводок отряда игрока 8 м (ТЗ 22.10) и поводок погони 7 м — удаляются,
   их роль играет допуск.
4. `FORCED_MOVE_SEC` 3 с как срок приказа — удаляется.
5. Контратака отряда по обстрелу — только у отряда без приказа игрока.

Без явного «да» по пунктам 1-2 этапы B4-B5 не начинать (CLAUDE.md:
«ручки, которые качались туда-сюда»). B0-B3 разворотов не требуют.
