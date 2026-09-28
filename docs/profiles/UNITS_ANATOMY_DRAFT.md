# Анатомия тика по родам войск (черновик, 28.09.2026)

Паспорт «что делает один тик логики» для каждого класса бойца: диспетчер,
ведомые ядром, вызовы наружу, таймеры и радиусы. Только факты из кода;
строки указаны как `файл:строка` на HEAD рабочей копии 28.09.2026. Замеров
здесь нет (машина занята) — цифры стоимости взяты из `docs/ENGINEERING_LOG.md`
там, где они уже были.

Сокращения: **GD** — GDScript, **C#** — `csharp/ArmyCore.cs` (через фасады
`scripts/army/ArmySoA.gd` и `scripts/SpatialGrid.gd`), **движок** — вызов в
Godot (`global_position`, `Time.*`, `is_instance_valid`, сигналы).
`U:` = `scripts/Unit.gd`, `GM:` = `scripts/GameManager.gd`, `AC:` =
`csharp/ArmyCore.cs`, `US:` = `scripts/unit_stats_config.gd`,
`GC:` = `scripts/goblin/goblin_config.gd`.

---

## 0. Сводная таблица радиусов по классам

| Класс | `attack_range` (US:STATS) | `aggro_radius()` | `pursuit_limit()` | `sep_radius()` (личный круг разведения) | `nav_clearance()` | Особые радиусы |
|---|---|---|---|---|---|---|
| **Unit (база)** | — | `AGGRO_RADIUS` 5.0 (U:414); орда — `vision_radius(range)` = max(1.6·range, 15) (US:1867-1874, U:7698) | `PURSUIT_LIMIT` 7.0 (U:7764) | 0 → общая `SEP_MIN_DIST` = 0.25·(2−1/3) ≈ 0.417 (U:168-172) | 1.5 / 2.2 / 3.5 (US:328-330, U:278) | `LOCK_BLOCKER_RANGE` = 0.55·2+0.5 = 1.6 (U:1478); `BLOCK_RADIUS` 0.55 (U:110); `PERSONAL_RADIUS` 0.25; `SEP_CROSS_SQUAD` 1.6 (U:189); `AGGRO_LEASH` 14 (U:7676); `COUNTER_CHARGE_RANGE` 12 (U:7759); `PULL_UP_RANGE` 7 (U:8082); `PULL_UP_MAX` 14 (U:2795); `FORCED_RETARGET_RANGE` 6 (U:397); `STUCK_RETARGET_RANGE` 5 (U:8088); `INTERCEPT_MARGIN` 0.8 (U:5523) |
| **Копейщик** `Spearman.gd` | 2.5 (cd 2.0) | в «Защите» `FORMATION_AGGRO_RADIUS` 5.0, иначе база 5.0 (Spearman:801-807) | 7.0 | общий 0.417 | 1.5 | `PHALANX_FRONT_COS` 0.34 ≈ ±70° (U:8093); ряд: `FILE_LOOK_AHEAD` 1.9 × `FILE_HALF_WIDTH` 0.45 (U:906-919); смыкание `PHALANX_GAP` 0.7 / `PHALANX_HOLE_GAP` 0.9 (U:921-932); вес для конницы 0.4 в строю (Spearman:810) |
| **Мечник** `Warrior.gd` | 1.6 (cd 1.6) | `WARRIOR_AGGRO_RADIUS` 5.0; в окне `RUSH_HOT_SEC` 6 с после рывка — `RUSH_AGGRO_R` 14 (Warrior:19-29, 65-67) | 7.0 | общий | 1.5 | `SHIELD_WALL_RANGE` 8 (Warrior:79); рассечение `CLEAVE_PAD` 0.8, `CLEAVE_ARC_COS` 0.15 (Warrior:244-245); вес для конницы 1.6 (Warrior:33) |
| **Лучник** `Archer.gd` | 15.0, потолок `attack_range_cap` 25 (US:51-53), cd 3.0 | max(5, attack_range) — см. `watch` в U:7975 | не преследует вовсе (`pursues_target` false, Archer:504) | общий | 1.5 | снайпер `SNIPE_RANGE` 25 (US:1793); радар отряда `attack_range + RADAR_MARGIN 5` (GM:5503); замок цели `max(3·range, 60)` (U:7834-7840); `SQUAD_SHOT_SLACK` 6 (U:6712); `GARRISON_RANGE_MULT` 1.30 (US:847); вес для конницы 2.2 (Archer:480) |
| **Монах** `Monk.gd` | 1.4, урон 0 (US:66-73) — не дерётся | не применяется (`attack_damage` 0 → ветка агро не входит, U:4805) | — | общий | 1.5 | аура лечения `MONK_HEAL_RADIUS` 20 + кузница (US:947, Monk:1259); стоять на 0.7·R (`MONK_STAND_FRAC`, US:953); аура наград `MONK_AURA_BASE_R` 4 (US:977); расстановка `MONK_SPACING` 5 (US:961); поводок одиночки `MONK_HEAL_LEASH` 14; поиск тел `MONK_RES_SEARCH_RADIUS` 30 |
| **Гоблин-копейщик** `goblin/GoblinSpearman.gd` | 2.2 (cd 2.5) | орда: `vision_radius(2.2)` = 15 (U:7698) | 7.0 | `SEP_MIN_DIST · SIZE_SCALE 1.445` ≈ 0.602 (GoblinSpearman:89, GC:54) | 1.5 | поводок орды `max(14, aggro+2)` = 17 (U:7684-7690); бег к цели ×`GOBLIN_RUN_MULT` 1.3 (GC:545) |
| **Туша** `goblin/BigGoblin.gd` | 3.5 (cd 2.7) | охота `BIG_AGGRO_RADIUS` 18 (GC:530); базовое авто-агро через `super` — `vision_radius(3.5)` = 15 | `BIG_PURSUIT_LIMIT` 60 на охоте, иначе 7 (BigGoblin:417) | `SEP_MIN_DIST·2.4·2.2/3` ≈ 0.733 (BigGoblin:118) | 3.5 (гигант) | добор `BIG_HUNT_RADIUS` 28; связка `BIG_ESCORT_RADIUS` 30 / `BIG_ESCORT_FOLLOW` 22; свип `attack_range + BIG_SWEEP_HALF_W 1.5` = 5.0, сектор `BIG_SWEEP_ARC_COS` 0.5 (±60°), до `BIG_SWEEP_MAX` 6 (GC:500-539) |
| **Свиноконница** `goblin/GoblinPigRider.gd` | 2.5 (cd 2.1) | `RIDER_AGGRO_RADIUS` 20 (GC:553) | `RIDER_PURSUIT_LIMIT` 40 на охоте, иначе 7 (PigRider:64) | `SEP_MIN_DIST · 1.445` ≈ 0.602 (PigRider:142) | 2.2 (конница) | охота `RIDER_HUNT_RADIUS` 30 (GC:550); разгон `charge_range` 14, `charge_min_runup` 10, `charge_splash` 2.0, `charge_knockback` 1.3 (US:159-178); сектор удара `CavalryImpactHandler.FRONT_COS` 0.34 |
| **Тролль** `goblin/Troll.gd` (для сравнения) | 4.5 (cd 1.7) | `TROLL_AGGRO_RADIUS` 12 (GC:163, Troll:950) | поводок временем `TROLL_CHASE_SEC` 10 и `TROLL_CHASE_RADIUS` 45 (Troll:966-1006) | `SEP_MIN_DIST · 3.4` ≈ 1.417 (Troll:191) | 4.0 (Troll:269) | кольцо `attack_range + TROLL_SWEEP_REACH_PAD 0.8` = 5.3 (Troll:616-637); дуга 6 целей, cos 0.5; `TROLL_SURROUND_FOES` 4; таран `charge_range` 10, runup 6, splash 2.5 |

Прочие общие числа: `ARRIVE_RADIUS` 0.48 (U:80), `SEP_INTERVAL` 0.067 с
(U:219), `ATK_SNOOZE_REACH_SLACK` 0.6 (U:608), `NAV_DIR_MIN` 2.0 (U:2194),
`ROUTE_WP_RADIUS` 1.6 (U:2091), `PASS_CORE_FRAC` 0.55 (U:119, AC:796).

---

## 1. Диспетчер тика и «ведомые ядром»

### 1.1 Порядок одного физкадра (`GM:_physics_process`, GM:491-770)

1. Накопление дельты под `army_tick_div` (=1) — GM:500-508.
2. Часы армии один раз: `Unit.now_ms`, `Unit.phys_frame`, `Unit.nav_active` — GM:527-530.
3. `army.rebuild_grid()` — плоская сетка соседей целиком, C# (GM:541).
4. `_ttl_scale = squad_ttl_scale(active_units())` — растяжение отрядных сроков от 2500 ходящих (perf_config:922-928).
5. `_sweep_corridors()` — раз на отряд по `CORRIDOR_TTL_MS` 200 (+ джиттер 67), бюджет `CORRIDOR_BUDGET` 64 отрядов/кадр; `army.squad_corridor(rows, …, AGGRO_RADIUS, INTERCEPT_MARGIN, CORRIDOR_MARGIN 8)` — C# (GM:1187-1240).
6. `_sweep_melee()` — раз на отряд по `MELEE_TTL_MS` 400; `army.squad_melee(rows)` — C# (GM:1829-1930).
7. `_sweep_volleys()` — раз в `VOLLEY_SWEEP_EVERY` 3 кадра, только стрелковые отряды (GM:6020-6144).
8. `_sweep_squad_radar()` — стрелковые отряды раз в `RADAR_INTERVAL_MS` 500, скан знаменосцем `radar_scan(range+5)` (GM:5780-5850). `_sweep_march_radar()` — все отряды раз в `MARCH_RADAR_SEC` 5 с, три точки фронта × `nearest_of_side` по чужим фракциям на 10 м (GM:5651-5750).
9. `_advance_matrices()` — ручка `squad_matrix` **false** (perf_config:479), не работает.
10. `army.tick_snooze(delta, ATK_SNOOZE_SPARE)` → `take_woken_f()` → `Unit._atk_wake(cd)` (GM:600-625; AC:3380-3420).
11. `shards = shards_for(active_units())`: 1 до 800, 2 до 1200, 3 до 2200, 4 выше (perf_config:393-431) — **личная частота бойца 60/15 Гц**.
12. **Список строк от ядра** `army.tick_rows(...)` (AC:4824-4890): отдаёт живые, `FTickOn`, не `DEAD`, своего шарда (`i % shards == phase`), **исключая** `FMatrixLed`, а при `st == ATTACKING` — `FAutopilot | FRearPress | FAtkSnooze`; при `st == IDLE` и `FIdleWait` — тикает таймер в колонке `_aggroT` и не отдаёт строку до истечения. Роды с `FTickAlways` (AC:4771, комментарий AC:4760-4767: лучник, монах, рабочий, гнолл, тролль, туша — те, у кого `may_sleep_physics()` false) из списка не выпадают. Чужой в неосвещённой ячейке тумана и не в бою — отдаётся раз в `fog_slow_div` 6 тактов с дельтой ×6 (AC:4852-4866, perf_config:690).
13. Для каждой строки — `unit.tick_physics(delta·shards, …)` (GM:653-668).
14. `_flush_poses()` (очередь `queue_pose` → C# одним вызовом), `rear_press_pass`, `autopilot_pass(… scanMod 12, scanR = LOCK_BLOCKER_RANGE + INTERCEPT_MARGIN = 2.4 …)`, `batch_move_queued` (пакетный шаг всех заявок), `take_press_woken_f` → `_rear_wake(elapsed)` (GM:690-745).
15. `army.batch_separation(...)` — разведение всех живых каждый кадр, такт в колонке `SEP_INTERVAL` (GM:750-762).
16. `_physics_tail`: `_wake_returned_far_units` раз в 15 кадров, `_sweep_reform`, `_sweep_phalanx_press` (раз в `PHALANX_PRESS_SEC` 0.3, только отряды копейщиков в «Защите»), `_sweep_morale`, еда, овцы, марш-аудио (GM:772-812).

### 1.2 Когда GDScript-тик бойца **не входит** вовсе

| Признак | Кто ставит | Кто снимает | Что делает ядро вместо GD |
|---|---|---|---|
| `_matrix_driven` / `FMatrixLed` | `GM._advance_matrices` (выключено, `squad_matrix=false`) | тот же проход | — |
| `_idle_wait` / `FIdleWait` (только IDLE) | `U:tick_physics` IDLE-ветка при `core_tick_list`, `_aggro_timer > 0`, не «оборона», не паника/разлёт/лежание, `may_sleep_physics()` (U:4810-4820) | истечение таймера в `TickRows`; событие — `set_attack_target`, `command_attack`, `_core_release` (U:2934-2938, 2580-2583, 643-647) | декремент `_aggroT[i]` (AC:4847-4852) |
| `_atk_snooze` / `FAtkSnooze` (только ATTACKING) | взвод дрёмы в конце `_process_attack` при `_attack_timer > ATK_SNOOZE_SPARE`, не разгон (U:6640-6655) | `TickSnooze`: `cd <= spare`, цель мертва/без позы, или (`SnoozeRangeWake`) цель дальше `_atkReach` = range + pad + 0.6 (AC:3380-3410); `set_attack_target`, `_core_release` | таймер и стража цели по колонкам |
| `_rear_press` / `FRearPress` (ATTACKING) | аренда из `GM._recalc_melee` кандидатам (ранг ≥ 2, цель дальше оружия), ручка `rear_press` true | `RearPressPass`: дошёл до `stop`; упор в чужое тело в `BatchMoveRows`; `set_attack_target`; удар/паника (`_core_release`) | шаг к точке боя без сканов (AC:3782-3822) |
| `_auto_pilot` / `FAutopilot` (ATTACKING) | `_arm_autopilot` (подход, подтягивание), `_arm_hold_autopilot` («оборона» ждёт на дистанции, скорость 0), `autopilot_arm_goal` (ход стены `_phalanx_march`) — U:733-770, 6766-6826 | `AutopilotPass`: плановый возврат раз в `cadence` = `AGGRO_INTERVAL_HOT` 0.5 с; дистанция удара достигнута; чужой в 2.4 м (`EnemyNear`, стража раз в 12 тактов на строку); цель мертва (AC:3856-3945) | шаг к живой строке цели, подтягивание на `PULL_UP_SPEED`, обход своих как `_flank_step` |

`Unit._core_led()` (U:663-669) — единая проверка «строку ведёт ядро»: тогда
окно ходьбы (`_mv_tick`) считает визуальный тик, а не физический.
Возврат в GD (`_rear_wake(elapsed)`, U:619-641) доводит `_aggro_timer`,
`_stuck_timer`, `_nav_t`, `_reform_permit`, `_rank_timer` на прошедшее время.

**Кто НЕ уходит в ядро никогда** (U:733-748, 751-760): стойка «оборона» на
подходе (только `hold`-режим со скоростью 0), конница с `charge_range > 0`,
отход, бег, `_disengaging`, тыловой напор, обход по навигации (`nav_detour`),
сцепка `_melee_grip`, стрелки (`pursues_target` false — в ветку подхода с
автопилотом они попадают только под приказом до `_engaged_once`).

### 1.3 Таймеры и частоты общей базы

| Таймер | Значение | Где | Кому |
|---|---|---|---|
| `_aggro_timer` | `AGGRO_INTERVAL_HOT` 0.5 / `CALM` 2.0 (U:7670-7671); стартовая фаза `_sep_phase·0.12` (U:_ready) | IDLE-ветка тика; `_process_move` перехват; `_process_attack` hold/blocker | все вооружённые |
| `_rank_timer` | `RANK_RECHECK` 0.25 (U:905) | `_update_live_rank` | только `_stance_holds_ground()` (U:4770-4777) |
| `_retarget_timer` | `RETARGET_RETRY_SEC` 0.2 (U:5951) | `_process_attack` при `attack_target == null` | ATTACKING без цели |
| `_nav_t` | `NAV_RECHECK_SEC` 0.4 (+ `id%7·0.03`), свободная прямая — `NAV_RECHECK_FREE_SEC` 1.2 (U:2097, 2198) | `_atk_waypoint`, инлайн в `_process_move` | идущие дальше `NAV_DIR_MIN` 2 м |
| `_route_los_t` | `ROUTE_LOS_SEC` 0.5 (U:2092) | пропуск угла маршрута | идущие по `_route` |
| `_stuck_timer` | `STUCK_CHECK_SEC` 0.5, `STUCK_PROGRESS` 0.35 (U:5595-5597) | `_tick_stuck` | MOVING и подход в ATTACKING |
| `_flank_blocked` | раз в `FLANK_RECHECK_FRAMES` 10 кадров при dist ≤ 3.5 (U:6939-6947) | `_flank_step` → `allies_count_near` | подход вне «обороны» |
| `_sep_timer` (колонка) | `SEP_INTERVAL` 0.067 (U:219) | `BatchSeparation` | все |
| `_mv_sample_ms` | `MOVE_ANIM_SAMPLE_MS` 200 (U:4172) | `_sample_movement` — преамбула каждого тика | все |
| `_hit_pend_ms` | `MELEE_HIT_DELAY_MS` 150 (U:6867) | касание по кадру замаха, `_release_hit` в преамбуле | рукопашные |
| кэш цели отряда | `perf_config.squad_target_ttl` 0.4 с (perf_config:58) | `squad_target_get/put` (GM:9874-9891) | `_squad_cached_enemy` |
| кэш точки врага отряда | `SQUAD_FACE_TTL` 0.25 (GM:9915) | `squad_enemy_point` (GM:9923-9980) | `_update_live_rank` |
| `squad_in_combat` | кэш на физкадр; `RECENT_HIT_WINDOW_MS` 3000 (GM:4379-4440) | все, кто спрашивает | — |
| сплочённость | `SQUAD_COHESION_COOLDOWN_MS` 2500, `SQUAD_COHESION_DIST` 14 (US:1802-1804) | `GM._cohesion_guard` (GM:1520) из `_recalc_corridor` | отряд, не MOVING, не под приказом |

### 1.4 Что стоит преамбула любого тика (U:4557-4790, все состояния)

Без единого вызова наружу, кроме перечисленных:
- `_reform_permit`, `_tick_fling` (если летит), `_mv_tick()` → `_sample_movement()` — читает `position` (поле, правило 2), пишет `mark_pose_dirty` по событию.
- `_release_hit()` при истечении задержки касания — **наружу**: `tgt.take_damage`, `AudioManager.play_3d` ×2, `_apply_push`.
- Лежащий (`_down_until_ms`) — `GameManager.corpses.move_now` и `return`.
- Позиция/скорость/состояние сравниваются с `_sent_*`; при изменении — `GameManager.queue_pose(...)` (запись в Packed-массивы автозагрузки, без границы языков; `_effective_speed()` считается только при `batch_combat`, который **выключен**).
- Тихая строка (`_vis_quiet`) — сравнение взгляда с `_pose_look`, `mark_pose_dirty` по повороту > 20° (`POSE_TURN_COS2`).
- В «обороне»: `_rank_timer` → `_update_live_rank()` раз в 0.25 с.

### 1.5 Таблица состояний общей базы

| Состояние | Что делает тик | Запросы наружу (куда / частота) | Радиусы |
|---|---|---|---|
| **IDLE** (U:4795-4838) | `velocity = 0`; снять `_idle_wait`; если вооружён и не отход/бег — декремент `_aggro_timer`; на истечении: `_clear_enemy` → взвести CALM без скана, иначе `_check_auto_aggro()`; затем при `core_tick_list` и `may_sleep_physics()` — `army.idle_wait_arm` (**строка уходит из списка**); в «обороне» ещё `_phalanx_advance()` каждый тик | `_check_auto_aggro` (раз в 0.5-2 с): `_lock_next_victim` → `squad_pick_member` (GD-обход состава чужого отряда, GM:9702); `squad_in_combat` (кэш кадра); в «обороне» `_squad_cached_enemy(attack_range)` → `squad_target_get` (GD-словарь) / `_find_nearest_enemy_in_range` у **знаменосца** (`squad_bearer`) → `unit_grid.best_enemy` (C# `BestEnemyPrio`, AC:1913) + `enemy_buildings_snapshot` (GD-снимок раз в кадр на фракцию, GM:8660) + `_nearest_of_squad` (GD-обход состава чужого отряда, U:8438); вне «обороны»: стрелок с `squad_radar` — `squad_radar_foe` (готовый ответ), иначе `_squad_cached_enemy(watch)`; поводок — `squad_bearer`, `aggro_leash`; `nav_unreachable` (C# A*, GM:10234) если цель дальше оружия; `_in_phalanx_front` → `_phalanx_dir` → `squad_enemy_dir` + `squad_in_combat` + `squad_course` (GD-словари). `_phalanx_advance` (каждый тик в обороне при виденном враге): `unit_grid.allies_ahead` ×1-3 (C# `AlliesAhead`, AC:1756), `_move_blocked` (поштучный шаг GD → C# `EnemyBlock`/стволы) | `watch = max(aggro_radius, attack_range)`, в бою отряда `max(…, PULL_UP_RANGE 7)` (U:7975-7990); поводок `AGGRO_LEASH` 14 от знаменосца; `_lock_sight_range` = `max(2·range, 10)`, у стрелка `max(3·range, 60)` |
| **MOVING** (`_process_move`, U:5656-5945) | замок `_move_lock`; `wall = _enemy_contact and (not moved_recently() or sprinting&player_run)`; бегущий об стену копий — `unit_grid.enemy_at(LOCK_BLOCKER_RANGE+BLOCK_RADIUS)` раз за забег; перехват (при `wall` или таймере 0.5 с, если не `_clear_enemy` и не `squad_march_clear`): `_find_nearest_enemy_in_range(attack_range+0.8, "blocker_reach")`, у рукопашной не меньше `AGGRO_RADIUS` 5 → `command_attack(blocker,false)` + `_melee_grip`; `dir/dist` до `move_target`; `_tick_stuck`; маршрут (`_route_advance`, пропуск угла раз в 0.5 с через `nav_blocked`); прибытие в `ARRIVE_RADIUS` → IDLE, `squad_note_arrival`, `squad_course` для взгляда; иначе инлайн-обход раз в `NAV_RECHECK_SEC`: `nav_blocked` → `squad_leg` + `_nav_spread` (C# A*, кэш 120 кадров на отряд) → `_commit_step` (заявка в очередь) | `squad_march_clear` (GD-словарь, каждый истёкший такт агро), `_find_nearest_enemy_in_range` (C#), `nav_blocked` (C# `NavLineBlocked`, ~10-13 мкс по зонду NavProbe), `squad_leg` (GD-кэш → C# `NavPath`), `_effective_speed` (кэш базы, `GameManager.bonus_version`), `queue_step` | перехват `attack_range + INTERCEPT_MARGIN 0.8`, рукопашной — до 5.0 (`MARCH_INTERCEPT_MELEE_MAX` 5.0, U:5537-5540); `NAV_DIR_MIN` 2; `ROUTE_WP_RADIUS` 1.6 |
| **бег / sprint** | то же MOVING, скорость ×`SPRINT_SPEED_FACTOR` 1.35 (U:4975); перехват по таймеру **выключен**, только `wall` (U:5720); авто-агро в IDLE и ответ на удар глушатся (`sprinting` в гейтах U:4805, 8790); входящий урон ×1.35 | `enemy_at` один раз за забег при контакте (U:5705-5714) | `LOCK_BLOCKER_RANGE + BLOCK_RADIUS` = 2.15 |
| **ATTACKING без цели** (U:5954-6060) | `_retarget_timer` 0.2 с; в «обороне» с точкой приказа — `_phalanx_march`; замок: `_lock_next_victim`; иначе `squad_duel_target(seek)` → `squad_pick_member` (GD-обход состава, GM:2247) → `_find_nearest_enemy_in_range(seek, "retarget_lost")`; нет — `_resume_march`/`_resume_attack`/IDLE + `squad_close_ranks` deferred | `squad_foe`, `squad_pick_member`, `best_enemy` (C#), `squad_in_combat`, `call_deferred` (движок) | `seek = max(attack_range, FORCED_RETARGET_RANGE 6)` под приказом, иначе `attack_range` |
| **ATTACKING, цель дальше `rng = attack_range + _target_pad`** (U:6108-6520) | конница: взвод/сброс разгона, `_charge_impact` по `_enemy_contact`; «оборона» с точкой → `_phalanx_march`; **«оборона» без точки** → стоим, раз в 0.5 с `_find_nearest_enemy_in_range(attack_range, "hold_at_reach")` если не `_clear_enemy`, `_arm_hold_autopilot` (уход в ядро); подтягивание рядов `_should_pull_up` (`dist ≤ reach + 14`) на 0.55 скорости + `_arm_autopilot`; сцепка `_melee_grip` в полосе `rng + 0.8`; поводок погони `squad_pursuit_anchor` (GD-словарь, только у `_pursuit_anchored`); `squad_ranged_engaged` у стрелков; бросок цели (`not forced` или `_engaged_once and not pursues_target`) → `_resume_march`/IDLE; детектор застревания → `STUCK_RETARGET_RANGE` 5 через 2 проверки; заслон раз в 0.5 с или по `_enemy_contact`: `_find_nearest_enemy_in_range(blk_range, "blocker_march")`; к зданию — `squad_attack_anchor`/`squad_attack_hold` (GD-словари); обход скал `_atk_waypoint` (раз в 0.4 с `nav_blocked` → `squad_leg`); `_flank_step` → `allies_count_near` (C#) раз в 10 кадров; `_arm_autopilot` если не обход; `_commit_step` | как в таблице; `_find_nearest_enemy_in_range` до 2 раз в 0.5 с на бойца (hold/blocker/stuck) | `blk_range = attack_range + 0.8`, под замком `min(range, 1.6) + 0.8` (U:6386-6388); `PULL_UP_MAX` 14, `PULL_UP_SPEED` 0.55; `FLANK_TRIGGER_DIST` 3.5 |
| **ATTACKING, цель в дальности (свалка)** (U:6520-6655) | `velocity = 0`; конница — `_charge_impact`; первый раз — якорь погони `squad_pursuit_anchor_set` (+ `squad_ranged_engaged_set` у стрелков); `_attack_timer -= delta`; `_may_strike_now()`; удар: `_effective_cooldown`, `_strike_damage + _upgrade_damage_bonus` (GD `unit_bonus` — словарь), отложенное касание (`_hit_pend_*`) либо сразу `tgt.take_damage` + 2× `AudioManager.play_3d` + `_grunt_attack` + `_after_melee_hit` + `_apply_push` раз в `push_every` + `_on_attack_fired`; **взвод дрёмы** `army.atk_snooze_arm(_soa, cd, range+pad+0.6)` — дальше до пробуждения GD-тик не входит | `AudioManager.play_3d` (движок, 3D-пул), `take_damage` цели (см. 1.6), `GameManager.unit_bonus`, `army.atk_snooze_arm` (C#, по событию) | `reach()` = `attack_range + _target_pad` (pad = `ring_radius()` здания или `sep_radius()` гиганта, U:2869-2882) |
| **тыл (`_rear_line`)** | ручка `battle_lines` **false** — не работает; код `_rear_step` (U:5433-5520) без сканов кроме `enemy_block` при `not _clear_enemy` | — | `REAR_RANK_DEPTH` 0.85 |

### 1.6 Ответ на удар (`take_damage`, U:8614-8845) — событие, не тик

`squad_mark_hit` (GD), 4 чтения `unit_bonus`/`get_upgrade` (GD-словари),
`squad_armor_pierce`, `_soa_push_stats` (C#), `_update_hp_bar`, `tm_damage`
(телеметрия, ручка `telemetry` true), `army.vis_hit` (C#). Ответ: бегущий
в `LOCK_BLOCKER_RANGE` → `command_attack`; IDLE/MOVING с `_may_answer_blow`
(`moved_recently`, `global_position` обидчика) → при `atk_dist ≤ hit_close`
— `command_attack(attacker,false)` или `squad_counter_charge` (GD-обход
состава отряда, откат `COUNTER_CHARGE_COOLDOWN_MS`); при
`≤ COUNTER_CHARGE_RANGE` 12 — контратака отряда; `_answer_far_fire` для
дальнего обстрела (`squad_engaged`, `squad_counter_charge`). В свалке это
**сотни вызовов в секунду** и все с `global_position` (свойство).

---

## 2. Копейщик — `scripts/Spearman.gd`

Своего `tick_physics` нет: весь тик — базовый. Особенности класса — в
переопределениях, которые база зовёт из горячих веток.

| Состояние | Что добавляет класс | Запросы (куда / частота) | Радиусы |
|---|---|---|---|
| IDLE, стойка «Атака» | база | база | `aggro_radius()` 5.0 |
| IDLE, стойка «Защита» (`_stance_holds_ground`) | `_update_live_rank` раз в 0.25 с: `squad_enemy_point(sid, self, AGGRO_RADIUS)` — кэш 0.25 с на отряд, промах = `unit_grid.nearest_enemy_pos` (C# `NearestEnemyOffset`, квадрат 2r×2r ячеек 1 м); `allies_ahead` только если `_line_valid`/`_rank_fresh` не сняли (ряд обычно приходит от `GM._push_squad_ranks` пакетно, GM:1409); `_phalanx_advance` каждый тик при виденном враге: `allies_ahead(PHALANX_GAP 0.7)`, при защёлке ещё два `allies_ahead` (1.9 и 0.9); шаг поштучным `_move_blocked` (не пакетный!) на `PHALANX_FILL_SPEED` 0.45; авто-агро берёт только `_in_phalanx_front` (cos 0.34) в `attack_range`; `_arm_hold_autopilot` не ставится в IDLE | `squad_enemy_point` (GD-словарь + C# раз в 0.25 с на отряд), `allies_ahead` (C#) 1-3 раза за тик при виденном враге, `squad_enemy_dir`/`squad_in_combat`/`squad_course` в `_phalanx_dir` (GD-словари, каждый вызов) | `FORMATION_AGGRO_RADIUS` 5.0 (Spearman:801); `AGGRO_RADIUS` 5 для точки врага; `FILE_LOOK_AHEAD` 1.9 × 0.45 |
| MOVING | база; ход стены по приказу атаки идёт в ATTACKING (`_phalanx_march`) | база | перехват до 5 м (рукопашная) |
| бег | копья вверх (`_spear_leveled` первым проверяет `sprinting`, Spearman:482-500); бег ×1.35, штраф стойки ×0.65 применяется и на бегу (U:5060-5070) | база | — |
| ATTACKING, «Защита» с точкой приказа | `_phalanx_march` (U:6766-6826): дистанция до `_hold_goal`; раз в 0.5 с или по контакту `_find_nearest_enemy_in_range(attack_range, "march_at_hand")`; шаг → `_commit_step`; **уход в ядро** `autopilot_arm_goal` (стоп `ARRIVE_RADIUS`, возврат раз в 0.5 с) | `best_enemy` (C#) раз в 0.5 с, `_effective_speed` | `attack_range` 2.5 |
| ATTACKING, «Защита», цель дальше | стоим; `hold_at_reach` скан раз в 0.5 с (если не `_clear_enemy`, не под замком) + `_in_phalanx_front`; `_arm_hold_autopilot` → строка в ядре (скорость 0) до возврата раз в 0.5 с / чужой в 2.4 м / дистанция | `best_enemy` (C#), `_phalanx_dir` (3 GD-словаря) | — |
| ATTACKING в дальности | база + `_strike_damage` (натиск `PHALANX_PUSH_*`, Spearman:882-892), `spear_wall_strike` при таране конницы (U:540-575, вызывает `_charge_impact` всадника), `_incoming_damage_factor` (Spearman:910) | `GameManager.spear_wall_ready(sid)` в `spear_wall_active` (GD-словарь) — читается конницей при ударе и `_spear_leveled` в визуальном тике | дрёма: `range+0.6` |
| «Стена копий» (`spear_wall_active`) | стойка «Защита» + `spear_wall_ready(sid)`; урон ×`SPEAR_WALL_DMG_MULT` 3, замедление 0.30 на 5 с (U:518-520) | — | лоб `CHARGE_FRONT_COS` 0.34 (U:571) |

**Визуальный тик копейщика** (Spearman:589-660, `_update_dir_sprite`): на
каждом пересчёте позы — `_squad_face` → `squad_in_combat` + `squad_course`
(GD-словари), `target_in_range()` (два `position`), `_own_enemy_dir`,
`_spear_leveled` → `spear_wall_ready(sid)`. Направленная поза не спит
(`_process_can_sleep` возвращает false при `_cur_kind != KIND_PLAIN`,
Spearman:351-374) — стоящая фаланга в «Защите» **не усыпляет визуальный тик**.

Подозреваемые ветки:
- `_phalanx_advance` идёт **каждый тик** у каждого копейщика в «Защите», пока `_enemy_seen_dist != INF`, и делает 1-3 `allies_ahead` (C#-переход ~2 мкс каждый) плюс поштучный `_move_blocked` при закрытии бреши (U:8236-8317).
- `_phalanx_dir` — три словарных чтения GD (`squad_enemy_dir`, `squad_in_combat`, `squad_course`) на каждый вызов, а зовётся из `_update_live_rank`, `_phalanx_advance`, `_in_phalanx_front` (U:8129-8162).
- Стойка «Защита» + отряд в бою держит `_spear_leveled` в «нет сна» — визуальный пересчёт сектора у всех передних.
- В докладе `ENGINEERING_LOG.md:7247`: копейщики 6.5-7.3 мкс/тик (замес 578).

---

## 3. Мечник — `scripts/Warrior.gd`

Своего `tick_physics` нет; переопределён `tick_visual` (Warrior:459-466) —
на каждом визуальном тике `_update_guard()` → возможно `_rush_aggro()`.

| Состояние | Что добавляет класс | Запросы | Радиусы |
|---|---|---|---|
| IDLE | база; `aggro_radius()` = 5.0, а в окне `RUSH_HOT_SEC` 6 с после рывка без цели — 14 (Warrior:21-29, читает `Time.get_ticks_msec()` — **движок** на каждый вызов) | `Time.get_ticks_msec` в `aggro_radius`, `_threatened`, `rage_active`, `shield_wall_active` — каждый из них читает часы движка, а не `now_ms` | `WARRIOR_AGGRO_RADIUS` 5 / `RUSH_AGGRO_R` 14 |
| MOVING / бег (рывок по двойному ПКМ) | `start_rage_dash` → `_rush_pending`; скорость ×`RAGE_SPEED_MULT` 1.45, в `SHIELD_WALL_RANGE` 8 м от цели ещё ×1.3 (`_effective_speed`, Warrior:515-529 — `shield_wall_active` читает `attack_target.global_position`); конец бега → `_set_sprinting(false)` → `_rush_aggro()`: **прямой** `unit_grid.best_enemy(self, RUSH_AGGRO_R 14, CROWD_PENALTY)` мимо отрядного кэша, затем `command_attack(foe, true)` (Warrior:165-182) | `best_enemy` (C#) один раз на рывок; `_rush_aggro` также зовётся из `_update_guard` **каждый визуальный тик**, пока `_rush_pending` и не бег и не `rage_active` (Warrior:479-481) | 14 м |
| ATTACKING | база; `_strike_damage` (ротация 3+1, серия `RAGE_HITS` 5 с `RAGE_COOLDOWN_MULT` 0.45, `_refresh_forge` по `bonus_version`, Warrior:119-128, 208-235); `_after_melee_hit` — рассечение: скан соседей цели (Warrior:250-297; по коду `cleave_targets()` > 0 только с узлом кузницы); `_push_power` ×`RAGE_PUSH_MULT` 2.6 в серии | `GameManager.unit_bonus` ×4 при смене `bonus_version`; в `_after_melee_hit` — скан сетки (см. Warrior:250-297) при `cleave_targets() > 0` | `CLEAVE_PAD` 0.8, `CLEAVE_ARC_COS` 0.15 |
| щит (`_guard_active`) | `_update_guard` на каждом визуальном тике; `notify_incoming_fire` (Warrior:400) ставит угрозу `GUARD_HOLD_MS` 1600; скорость ×`GUARD_SPEED_FACTOR` 0.65 при штрафе стойки; `_incoming_damage_factor`: `_is_front_attack` читает `attacker.global_position` (Warrior:431-457); под угрозой/в серии `_process_can_sleep` false (Warrior:539-546) | `Time.get_ticks_msec` ×2-3 за визуальный тик | `GUARD_FRONT_COS` 0.0 |

Подозреваемые ветки:
- `_update_guard` каждый визуальный тик у каждого мечника: три чтения `Time.get_ticks_msec()` (`_threatened`, `rage_active`, `_anim_lock_until_ms`) — часы движка, а не `now_ms` (Warrior:370-373, 157-158, 479-487).
- `shield_wall_active` в `_effective_speed` — `attack_target.global_position` на каждый расчёт скорости в серии.
- В докладе `ENGINEERING_LOG.md:7247`: мечники 11 мкс/тик — почти вдвое дороже копейщика при том же базовом тике.

---

## 4. Лучник — `scripts/Archer.gd`

`tick_physics` переопределён (Archer:252-277): `super.tick_physics(...)`, затем
свои часы снайпера — **поэтому `may_sleep_physics()` false (Archer:501) и
`FTickAlways`: лучник никогда не уходит в `idle_wait`**.

| Состояние | Что делает тик | Запросы | Радиусы |
|---|---|---|---|
| IDLE | база: авто-агро раз в 0.5-2 с; при `squad_radar` (true) и отряде — `squad_radar_active`/`squad_radar_foe` (готовый ответ, скан ведёт `GM._sweep_squad_radar` знаменосцем раз в 0.5 с на отряд, детект `range + 5`); `holds_ground_on_aggro()` true → цель дальше оружия не берётся, вместо неё `_find_nearest_enemy_in_range(attack_range, "ranged_at_hand")`; **плюс каждый тик** после super: `_sniper_t` (0.5 с) → `_refresh_sniper` (`squad_snipers` + `squad_member_ordinal` — GD-обходы состава), `_snipe_pending_t`, `_snipe_autonomous` (Archer:279-293) раз в 0.5 с у снайпера без цели → `_snipe_pick(null, true)` — **`unit_grid.query_radius(mp, 25·garrison)` с Godot-массивом** и GD-фильтр (Archer:332-397: `snipe_claimed`, `squad_member_count`) | `squad_radar_foe` (GD-словарь), `best_enemy` (C#) при `ranged_at_hand`, `query_radius` (C# → GD-массив узлов) у снайперов раз в 0.5 с, `squad_snipers`/`squad_member_ordinal` раз в 0.5 с у всех лучников | `watch = max(5, attack_range)` = 15-25; `SNIPE_RANGE` 25 |
| MOVING | база; `pursues_target()` false → на марше по приказу радар пишет `RADAR_MARCH` без огня (GM:5822); ответ на удар: `state == MOVING and self is Archer` → нет контратаки на 12 м (U:8804) | база | перехват `range + 0.8` = 15.8-25.8 м, но только при `not _clear_enemy` и `not squad_march_clear` |
| ATTACKING, цель дальше | подход к приказанной цели базовой скоростью (не подтягивание: `holds_ground_on_aggro` в U:6230); `squad_shot` через `squad_ranged_engaged` (GD-словарь) при `dist > rng + 6`; после `_engaged_once` цель за дальностью бросается (`pursues_target` false); заслон `blocker_march` раз в 0.5 с в `range + 0.8` (под замком `1.6 + 0.8`); `_arm_autopilot` **не** ставится (проверка `pursues_target` в `_arm_autopilot` отсутствует, но ветка подтягивания закрыта `holds_ground_on_aggro`; ветка полного подхода U:6510 зовёт `_arm_autopilot` и для стрелка — см. открытые вопросы) | `best_enemy` (C#) раз в 0.5 с | `attack_range + _target_pad` |
| ATTACKING в дальности (выстрел) | `_may_strike_now` → `squad_volley_mode` + `squad_volley_open` (GD-словари, **каждый тик** пока ждёт окна; таймер зажат в 0 → дрёма не взводится, U:6640); выстрел `_on_attack_fired` (Archer:535-693): `_lead_point` (скорость цели), `_clamp_reach`, `squad_volley_open/mode/point/foe/spread` (5 GD-вызовов), `unit_bonus(bonus_spread)`, `GameManager.fire_projectile` → C# `ProjectileFire` (ручка `projectile_core` true); снайпер — `_snipe_schedule` → `_snipe_pick` (`query_radius` 25 м) | 5-7 GD-вызовов GameManager на выстрел + 1 C# | `SHOT_RANGE_SLACK` 0.75; `VOLLEY_MIN_SPREAD` 1.10 |
| гарнизон (`garrisoned`) | тик снят хозяином; `roof_tick` из `RoofGarrison` ведёт снайперские часы (Archer:241-250) | — | `GARRISON_RANGE_MULT` 1.30 |

Подозреваемые ветки:
- Лучник в режиме залпа между окнами **не дремлет** (U:6640 — `_attack_timer` зажат в 0 ≤ `ATK_SNOOZE_SPARE`) и каждый тик зовёт `squad_volley_mode` + `squad_volley_open` — два GD-вызова со словарями на 30 бойцов × отряд.
- `_refresh_sniper` раз в 0.5 с у **каждого** лучника: `squad_snipers(sid)` + `squad_member_ordinal(sid, self)` — обходы состава отряда в GD (Archer:295-306).
- `_snipe_pick` — `query_radius` с Godot-массивом узлов на 25 м (в свалке — сотни узлов), раз в перезарядку на снайпера (3 на отряд, `SNIPE_SQUAD_BASE`).
- `holds_ground_on_aggro` не закрывает ветку полного подхода: при `_attack_is_forced` (приказ) стрелок идёт `_commit_step` + `_arm_autopilot` (U:6505-6520) — это штатно.
- Замер: лучники 12 мкс/тик (ENGINEERING_LOG.md:7247).

---

## 5. Монах — `scripts/Monk.gd`

`tick_physics` переопределён (Monk:314-343): `super.tick_physics` (база: у
монаха `attack_damage` 0 — ветка агро в IDLE не входит; `command_attack`
переопределён в no-op, Monk:99-111; `is_combatant()` false), затем **каждый
тик**: `_ride_heal_vfx()` (движок: позиции узлов VFX), четыре таймера,
`_tick_retreat`, `_tick_shield`, `_tick_res` (пока есть тело), и раз в
`heal_tick_sec()` (= `MONK_SCAN_SEC` 1.2 / (1 + bonus_heal_rate), пол
`FLOW_TICK` 0.3) — `_monk_step()`. `may_sleep_physics()` false (Monk:235) —
`FTickAlways`.

| Состояние | Что делает тик | Запросы | Радиусы |
|---|---|---|---|
| IDLE / дремота | каждый тик — преамбула базы + `_ride_heal_vfx` + таймеры; раз в 1.2 с (в дремоте `MONK_IDLE_SCAN_SEC` 1.5) — `_monk_step` (Monk:353-396): `_tick_aura(force)` → `squad_bonus` ×3 (GD) и при ненулевой ауре **`unit_grid.query_radius(aura_radius 4+)` с GD-фильтром и `aura_apply` на каждого**; `_tick_spacing` → раз в такт **`query_radius(MONK_SPACING − 1 = 4 м)`** с фильтром по `Monk` и `moved_recently` + `global_position` каждого; `_order_alive`; `_squad_needs_care` (GD-обход состава, `_may_heal` на каждого); `_pick_patient_squad` — **обход ВСЕХ отрядов реестра** `GameManager.squads` с `squad_centre_xz` (GD) и обходом состава каждого своего отряда в 20 м (Monk:425-470); `_care_squad` — обход состава пациента; `_care_lone` → `army.most_wounded_of_side` (C#); `_go_to_front` — **второй обход всех отрядов** с `squad_is_combat` + `squad_centre_xz` (Monk:664-708) | 2× `query_radius` (C# → GD-массив), 2× полный обход `GameManager.squads`, `squad_centre_xz` на отряд, обход состава 1-2 отрядов, `most_wounded_of_side` (C#) — **всё раз в 1.2 с** | аура 20 м (`heal_radius`), стоять на 14 м (`stand_dist` = 0.7·20), расстановка 5 м, аура наград 4 м |
| MOVING (подход) | подход — обычный `command_move` (`_walk_to_patient`, Monk:1305-1330; `_go_to_front`), не чаще `MONK_STEP_SEC` 0.6 и только при сдвиге точки > `MONK_MOVE_SLACK` 3 м; шаг — базовый `_process_move` (пакетный) | `squad_centre_xz`, `land_target` (GD) при выдаче приказа | `stand_dist` 14 |
| лечение (стоит, пациент в `cast_range` 20) | `_care_squad`: сбор раненых `[frac, Unit]`, сортировка, до `max_heal_targets()` целей; `_soa_push_stats` каждому (C#), `_bind_heal_vfx_many` (движок: узлы VFX), `_play_attack_anim`; воскрешение `_tick_res` покадрово: `raise_spot` кэш 0.5 с (`RES_SPOT_REFRESH_SEC`, Monk:1071) | движок (VFX-узлы) каждый тик пока лечит | — |
| отход (`_retreat_goal`) | `take_damage` (Monk:902-940) → `_step_away_from` → `_nearest_ally_squad_dir` (обход отрядов) + `command_move`; откат `RETREAT_CD` 1.0; в отходе лечит только в дистанции каста | обход `GameManager.squads` на удар (не чаще 1 с) | `RETREAT_DIST` 5 |
| ATTACKING | не бывает: `command_attack` — заглушка (Monk:99-111) | — | — |

Подозреваемые ветки:
- `_monk_step` делает **два полных обхода реестра отрядов** (`_pick_patient_squad`, `_go_to_front`) и два `query_radius` с Godot-массивами раз в 1.2 с на монаха; на 3 монахах × 100 отрядов это сотни `squad_centre_xz` (медиана состава, GD) в одном кадре. Фазы разведены по `get_instance_id() % 97` (Monk:88).
- `_ride_heal_vfx` — движок, каждый тик, пока висит VFX.
- В докладе: монахи 35-45 мкс/тик, худший тик 6-9 мс → 0.7 мс после кэша `raise_spot` и `MostWoundedOfSide` (ENGINEERING_LOG.md:7247-7280); `monk_pulse`/`monk_res` — метки профиля (Monk:330-343).

---

## 6. Гоблин-копейщик — `scripts/goblin/GoblinSpearman.gd`

«Обычный Unit без единой особой ветки» (GoblinSpearman:1-17): своего тика
нет, всё — база (раздел 1). Отличия только в свойствах:

| Состояние | Что добавляет класс | Запросы | Радиусы |
|---|---|---|---|
| IDLE | `aggro_radius()` базы для `FACTION_GOBLIN` = `vision_radius(2.2)` = **15 м** (U:7698-7701, US:1867-1874) → `watch` 15 м; поводок `aggro_leash()` = max(14, 15+2) = **17 м** (U:7684-7690); при малом запасе под дальним обстрелом — отход к `goblin_camp_point` (U:7738-7745); `may_sleep_physics()` true → `idle_wait` в ядре между тактами | база; `goblin_camp_point` (GD) по событию | 15 / 17 |
| MOVING | база; орда идёт `command_move` от `GoblinAI._drain_orders` порциями (`ORDER_BUDGET_MEMBERS`) | база | перехват до 5 м |
| бег к цели | не `sprinting`: `set_attack_target` → `_sync_run_speed` → `move_speed ×1.3` + `_soa_push_stats` (C#, по событию, GoblinSpearman:59-70) | 1 C#-вызов на смену цели | — |
| ATTACKING | база; `_strike_damage` ротация `STRONG_EVERY` 4 (`_play_attack_anim` — визуал по событию); `repels_charge()` true — держит лоб конницы как копейщик (GoblinSpearman:174) | база | `attack_range` 2.2 |
| разведение | `sep_radius()` = 0.417·1.445 ≈ 0.60 (колонка `_sepR`, один раз при рождении) | — | — |

Подозреваемые ветки: те же, что у базы; отдельных нет. Замер: гоблины 5.8
мкс/тик — самый дешёвый род (ENGINEERING_LOG.md:7247). Заметное отличие от
людей — радиус агро 15 вместо 5: `best_enemy` на 15 м обходит квадрат
30×30 ячеек (900 против 100 при 5 м; ячейка сетки ядра 1 м).

---

## 7. Большой гоблин (туша) — `scripts/goblin/BigGoblin.gd`

`tick_physics` переопределён (BigGoblin:224-249): `super.tick_physics`, затем
**каждый тик** — второй удар комбо (`_combo_left`), тяжёлый шаг
(`walk_anim_recently` → раз в `BIG_STEP_SEC` 1.45 `AudioManager.play_3d`),
`_tick_hunt(delta)`. `may_sleep_physics()` false (BigGoblin:122) —
`FTickAlways`, из `idle_wait` не выпадает. `giant_class()` true,
`fine_ring_radius` 0.75 → `nav_clearance` 3.5, `_target_pad` у тех, кто бьёт
тушу, = её `sep_radius` 0.733 (U:2874-2880).

| Состояние | Что делает тик | Запросы | Радиусы |
|---|---|---|---|
| IDLE | база (авто-агро через переопределение `_check_auto_aggro`, BigGoblin:527-542: под замком — база; `_target_still_good()` (2 `position`) → HOT без скана; заморозка скана на КД до `BIG_SCAN_LEAD` 0.6 с до готовности; иначе `super._check_auto_aggro()` с `aggro_radius()` = `vision_radius(3.5)` = 15); **плюс `_tick_hunt` раз в `BIG_HUNT_TICK` 0.5 с** (BigGoblin:365-415): без охоты в IDLE/MOVING без цели — `_hunt_scan(BIG_AGGRO_RADIUS 18)` = **`query_radius(18 м)` + GD-фильтр** (`is_combatant`, `garrisoned`, `position`); никого — `_escort_target()` = **`query_radius(30 м)`** с чтением `attack_target` каждого своего; никого и IDLE — `_escort_follow()` = **`query_radius(60 м)`** + `squad_centre_xz` | до **3 `query_radius`** (18 / 30 / 60 м, Godot-массивы узлов) раз в 0.5 с в пустом покое; `best_enemy` (C#) базы раз в 0.5-2 с; `AudioManager.play_3d` раз в 1.45 с на ходу | 18 / 30 / 60 |
| MOVING (марш орды) | база + `_tick_hunt`: чужой в 18 м → `_engage` (`command_attack(foe, true)`, марш запомнен в `_resume_to`); `take_damage` (BigGoblin:421-433) — любой удар → `_engage(attacker)` | как IDLE | 18 |
| ATTACKING, цель жива | `_tick_hunt`: если цель не боец (рабочий/монах) и не замок — `_hunt_scan(18, combat_only)` раз в 0.5 с; иначе выход; база ведёт подход (`_arm_autopilot` — туша не конница, уходит в ядро) | `query_radius(18)` раз в 0.5 с пока цель — небоевой | `BIG_PURSUIT_LIMIT` 60 |
| ATTACKING, цель кончилась | `_tick_hunt`: `_hunt_scan(BIG_HUNT_RADIUS 28)` → `_escort_target()` (30 м) → `command_attack`, иначе `command_move(_resume_to)` | `query_radius(28)` + `query_radius(30)` | 28 / 30 |
| ATTACKING в дальности (свип) | `_strike_damage` (BigGoblin:440-452): `_effective_cooldown`, заморозка скана, `_play_attack_anim`, `_sweep_now(true)`: **`query_radius(attack_range + 1.5 = 5 м)`**, GD-фильтр по сектору cos 0.5, `sort_custom` (лямбда, аллокации), до 6 целей: `take_damage` + `apply_knockback(1.5)` каждому + `AudioManager.play_3d`; каждый 3-й взмах — второй свип через 0.45 с из тика; `_damage_on_strike()` false — базовый удар по цели урона не наносит; дрёма взводится штатно (`_attack_timer` = cd 2.7 > 0.15) | `query_radius(5)` + до 6 `take_damage` (каждый — см. 1.6) + до 6 `apply_knockback` (`_core_release` + C#) на взмах; раз в 2.7 с (+ комбо) | сектор ±60°, 5 м |

Подозреваемые ветки:
- **Пустой покой дороже боя**: до трёх `query_radius` (18/30/60 м) с Godot-массивами раз в 0.5 с на тушу, когда вокруг никого (BigGoblin:378-400). Ячейка 1 м: 60 м — квадрат 120×120 = 14 400 ячеек за вызов.
- `_sweep_now` — Godot-массив + `sort_custom` с лямбдой + до 6 `take_damage`/`apply_knockback` в одном тике; в докладе худший тик туши 0.6-1.0 мс (свип), средний 11-12 мкс (ENGINEERING_LOG.md:7247-7249). Отдельного числа «132 мкс/тик» в `docs/` **не найдено** (в логе 132 встречается только как цена прилёта стрелы и FPS стенда марша).
- `_escort_target` читает `attack_target` у каждого своего в 30 м (GD-поле + `is_instance_valid`).

---

## 8. Свиноконница — `scripts/goblin/GoblinPigRider.gd`

`tick_physics` переопределён (PigRider:67-70): **сначала** `_tick_hunt(delta)`,
потом `super.tick_physics`. `may_sleep_physics()` false — `FTickAlways`.
`target_prio_mode()` = 2 → `best_enemy` ядра делит счёт на `_tgtWc`
(вес для конницы: копейщик в строю 0.4, мечник 1.6, лучник 2.2). `charge_range`
14 > 0 → `nav_clearance` 2.2 и **автопилот никогда не взводится**
(U:741-742) — подход конницы всегда в GDScript.

| Состояние | Что делает тик | Запросы | Радиусы |
|---|---|---|---|
| IDLE | `_tick_hunt` раз в `RIDER_HUNT_TICK` 0.5 с (PigRider:95-130): без цели — `_hunt_scan(RIDER_HUNT_RADIUS 30)` = `_find_nearest_enemy_in_range(30, "rider_hunt")` → `best_enemy` C# **prio 2** + снимок зданий; нашёл — `_engage` → `command_attack(foe, true)`; затем база: авто-агро с `aggro_radius()` 20 (не `idle_wait` — `FTickAlways`) | `best_enemy(30 м)` (C#, квадрат 60×60 ячеек) раз в 0.5 с + авто-агро базы `best_enemy(20 м)` раз в 0.5-2 с | 30 / 20 |
| MOVING (марш орды) | `_tick_hunt` как в IDLE (`player_order_active`/`target_lock` глушат); `take_damage` (PigRider:132-140) → `_engage(attacker)` если своей цели нет; база — перехват `blocker_reach` в `attack_range+0.8` (у конницы `attack_range` 2.5 ≤ 5 → расширяется до 5 м) | как IDLE | 30 |
| **чардж** (ATTACKING, цель дальше `rng`) | база U:6120-6135: при `dist > charge_range 14` — `_charge_ready`, `is_charging=false`; при `_charge_ready` и не «оборона»/отход — `is_charging=true`, `_charge_from`, путь `_charge_path` копится **каждый тик** (`Vector2.length`); скорость ×`charge_speed_mult` 1.8 (U:5050); удар ловится по `_enemy_contact` (ставит пакетный шаг) → `_charge_impact(tu, dir)` (U:7227-7440): проверка `charge_min_runup` 10 м и `CHARGE_STRAIGHT_FRAC` 0.85 по пройденному пути; лоб копейщика (`repels_charge` + `_faces_charge`, cos 0.34) → `CavalryImpactHandler.front_wave_frac` (GD, обращения к отряду копейщика, `WAVE_WINDOW_MS` 1500) → `take_frac_damage` 0.50/0.25 (×3 при стене копий) и выход; иначе `CavalryImpactHandler.profile` (сектор: `squad_enemy_dir`/`squad_in_combat`/`squad_course` жертвы — GD-словари) → **`query_radius(at, charge_splash 2.0)`** → `take_damage` цели `max_health·0.5·cav_dmg`, `apply_knockback(1.3·kb)`, ряды `_charge_rows` (сортировка по проекции, `charge_row_kill` 1 насмерть, `charge_row2_frac` 0.3, `knock_down` 2 с) | подход — GD `_process_attack` целиком (без автопилота): `blocker_march` раз в 0.5 с, `_tick_stuck`, `_flank_step`; `_tick_hunt` раз в 0.5 с при цели, у которой `cav_target_weight < 1` (копейщик в строю) — `best_enemy(30)` ради смены на слабую цель; удар — событие: 1 `query_radius` + N `take_damage`/`apply_knockback`/`knock_down` | `charge_range` 14, runup 10, splash 2.0, knockback 1.3, breakthrough 2.0 |
| ATTACKING в дальности | база: `velocity=0`; если `is_charging` — `_charge_impact` и выход; удар `_strike_damage` (`_play_attack_anim`), `push_every` 1 → `_apply_push` **каждый удар** с `push_force` 18 и `charge_push_mult` 2.5 (U:7088-7225); дрёма взводится только `not is_charging` (U:6641) | `_apply_push` — читает цель, `_core_release`, `push_smooth` → C# | `attack_range` 2.5 |
| охота (`hunting`) | `pursuit_limit()` 40 вместо 7 — поводок погони от `squad_pursuit_anchor` почти не рвётся; цель кончилась → `_hunt_scan(30)` → `command_move(_resume_to)` | — | 40 |

Подозреваемые ветки:
- **Удар с разгона — самый дорогой одиночный тик в игре**: в докладе конница 2.2-3.6 мс за тик (`_charge_impact`: `query_radius`, гибель ряда с телами, `knock_down`, разлёт — ENGINEERING_LOG.md:7249-7250); средний тик 7-9 мкс. Замер 28.09 (CLAUDE.md, раздел ТЗ 25.09): свиноконница 28 мкс/тик, худший 6.1 мс.
- Конница **никогда не уходит в автопилот** (U:741): весь подход по 30 м — GD `_process_attack` каждый тик со всеми ветками (заслон, застревание, обход своих, здание, навигация).
- `_charge_path` — `Vector2.length` каждый тик на разгоне (U:6130).
- `_tick_hunt` при живой цели-копейщике в строю — `best_enemy(30 м)` раз в 0.5 с (PigRider:113-120): каждый всадник, упёршийся в фалангу, сканирует 60×60 ячеек дважды в секунду.

---

## 9. Тролль — `scripts/goblin/Troll.gd` (для полноты «тела гиганта»)

`tick_physics` (Troll:645-737): отложенное касание `_swing_left`; на одышке
(`is_winded`) — только `_sample_movement`, раз в `TROLL_SHOVE_SEC` 0.6
`_foes_around()` = **`unit_grid.enemy_count(5.3 м)` (C#, без массива)** и
`_shove_ring()` = `query_radius(5.3)` + `apply_knockback` всем; иначе
`super.tick_physics`, `_tick_growl`, `_tick_chase` (поводок 10 с / 45 м),
усыновление логова (`nearest_lair`), скорость ×1.2 в бою (`_soa_push_stats`
по смене), **`_foes_around()` каждый тик** (C# `EnemyCount`, AC:2185 —
обход ячеек с `IsInstanceValid` на каждого чужого в радиусе), `breaks_bodies`
при ≥ 4 чужих (бит `F_ORDER_PASS` в `_commit_step`), `_tick_raid`
(раз в `TROLL_RAID_CHECK_SEC` 6), `_tick_hunger` (`lair.nearest_sheep`),
патруль раз в 9 с (`randf` — общий поток случайности!). `may_sleep_physics()`
false. Удар: серия `TROLL_SWINGS` 3 → `TROLL_REST_SEC` 2.75; `_release_swing`
дуга 6 целей cos 0.5 с `knock_down` 2.5 с. Замер: тролли 35 мкс/тик
(ENGINEERING_LOG.md:7248).

---

## 10. Отрядные проходы, на которые опираются тики (кто считает «раз на отряд»)

| Проход | Частота | Что читает / куда пишет | Кому раздаёт |
|---|---|---|---|
| `_recalc_corridor` (GM:1206) | `CORRIDOR_TTL_MS` 200 (+67 джиттер) × `_ttl_scale`, бюджет 64/кадр | `army.squad_corridor` (C#: габарит, стволы, чужие в `AGGRO_RADIUS + INTERCEPT_MARGIN + CORRIDOR_MARGIN 8`); `_push_corridor` → `_clear_trunk`/`_clear_enemy` (GM:1739); `_push_squad_ranks` (ряды пакетно, GM:1409); `_cohesion_guard` раз в 2.5 с (GM:1520); сон физики отряда (`squad_phys_sleep`) | всем бойцам отряда — поля |
| `_recalc_melee` (GM:1843) | `MELEE_TTL_MS` 400 × `_ttl_scale`, бюджет 64/кадр | `army.squad_melee(rows)` (C#: engaged/free/голосование за чужой отряд); аренда `_rear_press` кандидатам → `army.rear_press_arm` | `squad_foe`, `squad_engaged`, `squad_duel_target` |
| `_sweep_squad_radar` (GM:5780) | `RADAR_INTERVAL_MS` 500, фаза `sid·37` | стрелковые отряды (кэш списка по `squads_version`); знаменосец `radar_scan(range + 5)` → `best_enemy` C#; `_radar_open_fire` → `command_attack` только тем, кто без цели | `squad_radar_foe`, `squad_radar_active` |
| `_sweep_march_radar` (GM:5651) | `MARCH_RADAR_SEC` 5, фаза `sid·53` | все отряды с хоть одним MOVING: 3 точки × `nearest_of_side` по чужим фракциям (C#, 10 м); порог `MARCH_RADAR_CONTACT 4 + 5·3` = 19 м → `mradar_phase` | `squad_march_clear` — гасит `blocker_reach` на марше |
| `_sweep_volleys` (GM:6022) | раз в 3 кадра | обход состава стрелкового отряда: готовность, центр масс целей → `volley_until/next/aim/foe/spread` | `squad_volley_open/point/…` |
| `_sweep_phalanx_press` (GM:3498) | `PHALANX_PRESS_SEC` 0.3 | отряды копейщиков в «Защите», все не MOVING и без приказа: `_centroid_of`, зонд на `PHALANX_PRESS_RANGE 5·0.5` вперёд по курсу — `nearest_of_side` | подача фаланги вперёд (`command_attack` всем) |
| `_sweep_reform` (GM:3644) | `REFORM_SWEEP_SEC` 0.3 | развал строя → `squad_close_ranks` | `command_move` всем |
| `_sweep_morale` (GM:7481) | свой такт | мораль, паника (очередью) | `panic_flee` |
| `squad_target_get/put` (GM:9874) | TTL 0.4 с | словарь `_squad_target[sid]` | `_squad_cached_enemy` |
| `squad_enemy_point` (GM:9923) | TTL 0.25 с | `unit_grid.nearest_enemy_pos` (C#) | `_update_live_rank` |
| `squad_pursuit_anchor` (GM:3906) | по событию | словарь | поводок погони |

---

## 11. Не найдено / открытые вопросы

- Число «BigGoblin 132 мкс/тик» в `docs/` не найдено; последний опубликованный ряд по родам — `ENGINEERING_LOG.md:7247` (замес 578, 17.09): гоблины 5.8, копейщики 6.5-7.3, конница 7-9, мечники 11, лучники 12, туши 11-12, гноллы 15, монахи 35-45, тролли 35 мкс/тик; худшие одиночные: конница 2.2-3.6 мс, туши 0.6-1.0 мс, монахи 6-9 → 0.7 мс. Свежее число 28.09 (CLAUDE.md): свиноконница 28 мкс/тик, худший 6.1 мс.
- Метка `worst tick всадника в ATTACKING` как отдельная строка отчёта в коде не найдена; `class_max` (perf_config:265) считает худший тик по `stat_id`, состояние идёт третьим аргументом `class_add` (GM:660).
- Метки `scan_meter` (`_Opt.scan_hit(site)`, U:8557): в коде встречаются `blocker_reach`, `blocker_march`, `retarget_lost`, `stuck_retarget`, `hold_at_reach`, `march_at_hand`, `leash_at_hand`, `nav_at_hand`, `fleeing_at_hand`, `ranged_at_hand`, `squad_cache_fill`, `cache_miss_range`, `cache_off`, `radar`, `rider_hunt`, `pull_up` (мёртвая ветка, `PHALANX_PULL_UP_SINGLE` false). Все они сходятся в один `unit_grid.best_enemy` + снимок зданий.
- `_rear_line`/`_rear_step` (тыл свалки) — код жив, ручка `battle_lines` false (perf_config:965); `squad_matrix` false (perf_config:479); `batch_combat` false (perf_config:635). Тик их не проходит.
- В `_check_auto_aggro` для стрелка с `squad_radar` (perf_config:112 true) личного скана нет — только `squad_radar_foe`; но `_find_nearest_enemy_in_range(attack_range, "ranged_at_hand")` всё равно вызывается, когда цель радара дальше оружия (U:8060-8066).
- `Warrior.aggro_radius()`, `_threatened()`, `rage_active()` читают `Time.get_ticks_msec()` вместо `Unit.now_ms` — по правилу 3 это лишние вызовы в движок в горячем месте; замера цены нет.
