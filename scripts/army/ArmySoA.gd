extends RefCounted

## ═══════════════════════════════════════════════════════════════════════════
## ЯДРО АРМИИ — ФАСАД НАД C#-СОЛВЕРОМ (csharp/ArmyCore.cs)
## ═══════════════════════════════════════════════════════════════════════════
## ЗДЕСЬ БОЛЬШЕ НЕТ НИ ОДНОЙ КОЛОНКИ И НИ ОДНОГО СКАНА. Всё это переехало в
## ArmyCore.cs; этот файл — тонкая переадресация, сохранённая ради того, чтобы
## ни один вызывающий не заметил переезда. На него ссылаются Unit, Worker,
## Castle, Arrow, SelectionManager, GameManager, SpatialGrid и полтора десятка
## стендов — переписывать их всех ради смены языка вычислителя незачем и опасно.
##
## ПОЧЕМУ КОЛОНКАМИ ВЛАДЕЕТ C#, А НЕ GDScript. На границе языков в Godot 4
## Packed*Array маршалится КОПИЕЙ. Если бы массивы жили здесь, каждый пакетный
## проход означал бы копирование десятка массивов по три тысячи чисел в кадр —
## то есть солвер вернул бы весь свой выигрыш обратно на переходе границы.
## Массивы живут у солвера и наружу не выходят; отсюда уходят только числа.
##
## ЧТО ОСТАЛОСЬ В GDScript: ничего из математики. Автоматы бойцов, приказы,
## отряды, ИИ и интерфейс — как были.
##
## СНИМКИ КОЛОНОК (px/py/pz/flags/st/fac) отдают КОПИЮ и предназначены только
## для ХОЛОДНЫХ читателей — стендов, сверяющих строки с узлами. Покадровый код
## обязан брать pos_of()/pos_x()/pos_z(): одно число за вызов вместо копии
## всего массива. Это не удобство, а разница между 0.1 мкс и 12 килобайтами.

const _CORE := preload("res://csharp/ArmyCore.cs")

var _c = _CORE.new()

## Прямая ссылка на солвер. Нужна пакетным проходам GameManager, чтобы не
## платить за лишний слой переадресации в покадровом коде
func core():
	return _c

# ── БИТЫ ПРИЗНАКОВ ──────────────────────────────────────────────────────────
# Номера обязаны совпадать с ArmyCore.F* и с литеральными сдвигами в Unit —
# сходимость сторожит qa_army A1
const F_POS_VALID   := 1 << 0
const F_RETREATING  := 1 << 1
const F_SPRINTING   := 1 << 2
const F_SETTLED     := 1 << 3
const F_DISENGAGE   := 1 << 4
const F_LOCKED      := 1 << 5
const F_GARRISONED  := 1 << 6
const F_CLEAR_TRUNK := 1 << 7
const F_CLEAR_ENEMY := 1 << 8
const F_SELECTED    := 1 << 9
const F_WORKING     := 1 << 10
const F_STEP_PENDING := 1 << 11
const F_TRUNK_IGNORE := 1 << 12
## Мировая матрица родителя единична — можно писать локальный трансформ.
## Раньше это было поле бойца и читалось пакетным проходом через Variant на
## каждого сдвинутого; в колонке это один бит
const F_LOCAL_XFORM := 1 << 13
## Бой этого бойца можно считать пакетно (см. ArmyCore.FAtkSimple)
const F_ATK_SIMPLE := 1 << 14
## ── ПРИКАЗ ИГРОКА ПРОХОДИТ СКВОЗЬ ЧУЖИЕ ТЕЛА ────────────────────────────────
## Живёт ровно столько, сколько тикает замок приказа игрока минус его хвост
## (Unit._forced_move_pass): полторы секунды, за которые из свалки выходят, но
## сквозь оборону не проходят. Второй и последний признак, дающий сквозной
## проход, — F_RETREATING. Битов 15 и 16 не берём: там спячка и сон отрисовки
const F_ORDER_PASS := 1 << 17

## Во сколько раз теснее обычного разрешено стоять работающему у жилы
const WORK_OVERLAP := 0.62

## Номер состояния «мёртв». Присваивание уходит в солвер: там он сравнивается
## с каждым кандидатом внутри сканов
var _dead_state: int = 5
var dead_state: int:
	get:
		return _dead_state
	set(v):
		_dead_state = v
		_c.SetDeadState(v)

# ── СНИМКИ КОЛОНОК: ХОЛОДНЫЙ ПУТЬ, СМ. ШАПКУ ────────────────────────────────
var px: PackedFloat32Array:
	get: return _c.SnapshotPx()
var py: PackedFloat32Array:
	get: return _c.SnapshotPy()
var pz: PackedFloat32Array:
	get: return _c.SnapshotPz()
var flags: PackedInt32Array:
	get: return _c.SnapshotFlags()
var st: PackedInt32Array:
	get: return _c.SnapshotSt()
var fac: PackedInt32Array:
	get: return _c.SnapshotFac()
var hp: PackedFloat32Array:
	get: return _c.SnapshotHp()
var sq: PackedInt32Array:
	get: return _c.SnapshotSq()

# ── ГОРЯЧЕЕ ЧТЕНИЕ: ОДНО ЧИСЛО ЗА ВЫЗОВ ─────────────────────────────────────
func pos_of(i: int) -> Vector3:
	return _c.Pos(i)

## Точка строки, если она настоящая; иначе — переданная запасная (позиция узла).
## Один вызов вместо «проверь флаг, потом собери вектор из трёх колонок»
func pos_or(i: int, fallback: Vector3) -> Vector3:
	return _c.PosOr(i, fallback)

func pos_x(i: int) -> float:
	return _c.PosX(i)

func pos_z(i: int) -> float:
	return _c.PosZ(i)

func state_of(i: int) -> int:
	return _c.State(i)

func faction_of(i: int) -> int:
	return _c.Faction(i)

func flags_of(i: int) -> int:
	return _c.Flags(i)

func hp_of(i: int) -> float:
	return _c.Hp(i)

func squad_of(i: int) -> int:
	return _c.Squad(i)

# ── РАСПРЕДЕЛЕНИЕ СТРОК ─────────────────────────────────────────────────────
func capacity() -> int:
	return _c.Capacity()

func used() -> int:
	return _c.Used()

## За этим номером занятых строк нет. По нему, а не по ёмкости, идут покадровые
## проходы солвера (см. ArmyCore._top): ёмкость растёт под ПИК армии и назад не
## сжимается, и после большой рубки обход по ней перебирал бы впустую в разы
## больше строк, чем есть бойцов
## GC-зонд (стенды): байт выделено в C# за всё время, сборок по поколению
func gc_allocated() -> int:
	return int(_c.GcAllocated())
func gc_count(gen: int) -> int:
	return int(_c.GcCount(gen))
## Сведения о последней сборке (см. ArmyCore.GcInfo)
func gc_info() -> PackedFloat64Array:
	return _c.GcInfo()
func gc_probe() -> PackedFloat64Array:
	return _c.GcProbe()
func gc_set_latency(mode: int) -> int:
	return _c.GcSetLatency(mode)

func top() -> int:
	return _c.Top()

func alloc_for(u) -> int:
	return _c.AllocFor(u)

func alloc() -> int:
	return _c.Alloc()

func release(i: int) -> void:
	_c.Release(i)

func clear() -> void:
	_c.Clear()

# ── ЗАПИСЬ ──────────────────────────────────────────────────────────────────
func set_pos(i: int, x: float, y: float, z: float) -> void:
	_c.SetPos(i, x, y, z)

func set_vel(i: int, x: float, z: float) -> void:
	_c.SetVel(i, x, z)

func set_hp(i: int, cur: float, mx: float) -> void:
	_c.SetHp(i, cur, mx)

func set_state(i: int, s: int) -> void:
	_c.SetState(i, s)

## Сколько сторон держит сетка соседей (см. ArmyCore.Factions). Ответ нужен
## стенду: игра знает Constants.FACTION_COUNT, солвер — своё число, и разойтись
## Бит «спящий» (см. ArmyCore.FDormant). Спящего бойца пакетное расталкивание
## пропускает: он неподвижен, и разводить его не с кем и незачем
const F_DORMANT := 1 << 15

## Боец вне карты (гарнизон): координата «ненастоящая», в сетку не попадает
func set_off_map(i: int, on: bool) -> void:
	_c.SetOffMap(i, on)

func set_dormant(i: int, on: bool) -> void:
	_c.SetFlag(i, F_DORMANT, on)

## они не имеют права
func grid_factions() -> int:
	return _c.GridFactions()


func set_faction(i: int, f: int) -> void:
	_c.SetFaction(i, f)

func set_squad(i: int, s: int) -> void:
	_c.SetSquad(i, s)

## ЛИЧНЫЙ РАДИУС РАСТАЛКИВАНИЯ строки. Ноль — «как у всех», то есть общая
## дистанция из аргумента batch_separation. Ставится ОДИН РАЗ при рождении
## бойца: в покадровый путь этот вызов не входит и границу не греет
## Гора и река — в формулу высоты и проверку воды ядра (см. ArmyCore.SetHill)
func set_hill(cx: float, cz: float, h: float, radius: float) -> void:
	_c.SetHill(cx, cz, h, radius)

func set_plateaus(data: PackedFloat32Array, gentle: float, steep: float, cone: float) -> void:
	_c.SetPlateaus(data, gentle, steep, cone)

## Скалы (спринт 18): маска непроходимых склонов по крутизне высоты ядра
func build_cliff_mask(ox: float, oz: float, cell: float, cols: int, rows: int,
		relief_amp: float, slope_thr: float) -> int:
	_c.BuildCliffMask(ox, oz, cell, cols, rows, relief_amp, slope_thr)
	return int(_c.CliffCells)

func set_cliff_enabled(on: bool) -> void:
	_c.SetCliffEnabled(on)

func is_cliff(x: float, z: float) -> bool:
	return bool(_c.IsCliffAt(x, z))

## ── НАВИГАЦИЯ (спринт 19, письмо 11): сетка проходимости и A* ядра ───────
## Строится ПОСЛЕ маски скал и реки (из них и складывается); зовётся из
## приказа, не из кадра
func build_nav_grid(cell: float) -> int:
	return int(_c.BuildNavGrid(cell))

func set_nav_enabled(on: bool) -> void:
	_c.SetNavEnabled(on)

## Отступ у скал и скругление углов нити (ТЗ 20.09.2026, п. 1): ручка A/B
func set_nav_arc(on: bool) -> void:
	_c.SetNavArc(on)

func nav_free(x: float, z: float) -> bool:
	return bool(_c.NavFree(x, z))

func nav_line_blocked(x0: float, z0: float, x1: float, z1: float, clear: float = 0.0) -> bool:
	if clear > 0.0:
		return bool(_c.NavLineBlockedC(x0, z0, x1, z1, clear))
	return bool(_c.NavLineBlocked(x0, z0, x1, z1))

## Слой стволов сетки навигации: пересчёт по флагу рубки (ТЗ 19.09.2026)
func nav_trees_dirty() -> bool:
	return bool(_c.NavTreesDirty())

func nav_refresh_trees() -> int:
	return int(_c.NavRefreshTrees())

## Концы чужой нити видны с точек бойца (см. GameManager._nav_reusable)
func nav_reusable(ax: float, az: float, bx: float, bz: float, p0: Vector3, pl: Vector3, clear: float = 1.5) -> bool:
	return bool(_c.NavReusable(ax, az, bx, bz, p0.x, p0.z, pl.x, pl.z, clear))

## Боковой разнос точек маршрута одним вызовом (см. GameManager._nav_spread)
func nav_spread(flat: PackedFloat32Array, fx: float, fz: float, latx: float, latz: float, max_off: float, clear: float = 1.5) -> PackedFloat32Array:
	return PackedFloat32Array(_c.NavSpread(flat, fx, fz, latx, latz, max_off, clear))

## Плоский массив [x, z, x, z, …] промежуточных точек; пусто — путь прямой
## (nav_last_found = true) либо пути нет (false). Длина нити — nav_last_length
## clear — отступ агента от стены (Unit.nav_clearance: пехота 1.5, конница
## 2.2, гиганты 3.5-4.0): штраф у стены, зазор нити, отжим угла и видимость
## half_w — полуширина строя: угол отжимается от стены и на неё
func nav_path(x0: float, z0: float, x1: float, z1: float, clear: float = 1.5, half_w: float = 0.0) -> PackedFloat32Array:
	return PackedFloat32Array(_c.NavPath(x0, z0, x1, z1, clear, half_w))

func nav_last_found() -> bool:
	return bool(_c.NavLastFound)

func nav_last_length() -> float:
	return float(_c.NavLastLength)

func nav_calls() -> int:
	return int(_c.NavCalls)

## Сколько запросов отбито компонентами связности (пути нет — без A*)
func nav_unreach() -> int:
	return int(_c.NavUnreach)

func nav_comp_count() -> int:
	return int(_c.NavCompCount)

## Отступ нити маршрута от стен, м (ТЗ 19.09.2026, п. 2)
func nav_wall_margin() -> float:
	return float(_c.NavWallMargin())

## Высота по формуле ядра (стенды сверяют с Main.get_terrain_height)
func height_at(x: float, z: float, relief_amp: float) -> float:
	return _c.HeightAt(x, z, relief_amp)

func set_river(on: bool, half_w: float, meander: float, k: float, ford_z: float,
		ford_half: float, depth: float, ford_depth: float, bank: float, margin: float,
		half_z: float, wet_depth: float) -> void:
	_c.SetRiver(on, half_w, meander, k, ford_z, ford_half, depth, ford_depth, bank,
		margin, half_z, wet_depth)

func set_sep_radius(i: int, r: float) -> void:
	_c.SetSepRadius(i, r)

## Тело гиганта: добавка к радиусу блокировки чужого шага (ТЗ 19.09.2026-3)
func set_body_radius(i: int, r: float) -> void:
	_c.SetBodyRadius(i, r)

func get_sep_radius(i: int) -> float:
	return _c.GetSepRadius(i)

func set_combat(i: int, dmg: float, rng: float, spd: float) -> void:
	_c.SetCombat(i, dmg, rng, spd)

## Вес цели для стрелков (ТЗ 14.09.2026, п. 10; см. Unit.target_weight)
func set_target_weight(i: int, w: float) -> void:
	_c.SetTargetWeight(i, w)

## Вес цели для конницы (ТЗ 18.09.2026, п. 4; см. Unit.cav_target_weight)
func set_cav_weight(i: int, w: float) -> void:
	_c.SetCavWeight(i, w)

func set_slot(i: int, off_x: float, off_z: float) -> void:
	_c.SetSlot(i, off_x, off_z)

## Сколько бойцов уже целится в этого. Раньше best_enemy читал поле у объекта;
## из солвера такое чтение — обращение через Variant на КАЖДОГО кандидата
func set_attackers(i: int, n: int) -> void:
	_c.SetAttackers(i, n)

func write_pose(i: int, p: Vector3, v: Vector3, state: int) -> void:
	_c.WritePose(i, p, v, state)

## Позы ПАЧКОЙ: один переход границы на кадр вместо одного на бойца.
## Разбор — в шапке ArmyCore.WritePoseBatch
func write_pose_batch(rows: PackedInt32Array, xs: PackedFloat32Array,
		ys: PackedFloat32Array, zs: PackedFloat32Array,
		vxs: PackedFloat32Array, vzs: PackedFloat32Array,
		sts: PackedInt32Array, gates: PackedInt32Array,
		eff: PackedFloat32Array) -> int:
	return _c.WritePoseBatch(rows, xs, ys, zs, vxs, vzs, sts, gates, eff, -1)

## ПАКЕТНЫЙ ПРОХОД БОЯ. Возвращает бойцов, которых пакет НЕ закрыл, — им нужен
## полный автомат. Разбор — в шапке ArmyCore.BatchCombat
func batch_combat(delta: float, attacking_state: int, pull_up_speed: float,
		pull_up_max: float, shards: int, phase: int) -> PackedByteArray:
	return _c.BatchCombat(delta, attacking_state, pull_up_speed, pull_up_max,
		shards, phase)

## Строка цели атаки (пишется по событию из Unit.set_attack_target)
func set_target(i: int, t: int) -> void:
	_c.SetTarget(i, t)

## ── ДРЁМА ПЕРЕЗАРЯДКИ В ЯДРЕ (этап C, сент. 2026) ──────────────────────────
## Пока строка под F_ATK_SNOOZE, таймер удара и стражу цели ведёт TickSnooze по
## колонкам, а GDScript-автомат боя у бойца — голый return. Взвод и снятие —
## события; покадровый путь — один вызов tick_snooze на весь мир
const F_ATK_SNOOZE := 1 << 18

func atk_snooze_arm(i: int, cd: float, reach: float) -> void:
	_c.AtkSnoozeArm(i, cd, reach)

func atk_snooze_clear(i: int) -> float:
	return _c.AtkSnoozeClear(i)

## Возвращает ЧИСЛО проснувшихся; сам список забирается take_woken() и только
## при ненулевом счёте — в тихий кадр ни одной аллокации
func tick_snooze(delta: float, spare: float) -> int:
	return _c.TickSnooze(delta, spare)

## Пары [строка, остаток кулдауна] плоско (без Godot-обёртки — этап 4)
func take_woken_f() -> PackedFloat32Array:
	return _c.TakeWokenF()

func press_woken_count() -> int:
	return _c.PressWokenCount()

## Пары [строка, секунд с взвода] плоско
func take_press_woken_f() -> PackedFloat32Array:
	return _c.TakePressWokenF()

func take_woken() -> Array:
	return _c.TakeWoken()

## ── ОБЩАЯ ОТРИСОВКА: БУФЕРЫ БАКЕТОВ И ПОКАДРОВЫЙ ДОГОН (этап C.1) ──────────
## Буферы MultiMesh и покадровый догон картинки живут в ядре; GDScript
## (FarUnitRenderer) остаётся владельцем жизненного цикла бакетов и редких
## записей. Разбор — в шапке ArmyCore, раздел «ОБЩАЯ ОТРИСОВКА»
const F_VIS_SELF := 1 << 19
## Тыловой напор (этап D1): строка давит к точке боя без входа в GDScript.
## Аренда из GameManager._recalc_melee, шаг — ArmyCore.RearPressPass
const F_REAR_PRESS := 1 << 21

## Маска тумана войны (этап D3): попиксельная часть в ядре
func fog_setup(cols: int, rows: int, half_x: float, half_z: float,
		mask_cell: float, edge_feather: float) -> void:
	_c.FogSetup(cols, rows, half_x, half_z, mask_cell, edge_feather)

func fog_reset() -> void:
	_c.FogReset()

## Штамп «разведано» без «видно» (ориентир на карте, ТЗ 18.09.2026, п. 10)
func fog_stamp_seen(x: float, z: float, r: float) -> void:
	_c.FogStampSeen(x, z, r)

## Источники плоскими тройками [x, z, r]; возвращает [lit, seen, rgba]
func fog_refresh(src: PackedFloat32Array) -> Array:
	return _c.FogRefresh(src)

## Источники по бойцам собирает ядро (живые строки фракции с настоящей
## координатой, радиус обзора от attack_range, слияние по ячейке src_cell);
## extra — дополнительные тройки [x, z, r] (постройки, постоянные засветы)
func fog_refresh_rows(faction: int, vis_mult: float, vis_min: float,
		src_cell: float, pad: float, extra: PackedFloat32Array) -> Array:
	return _c.FogRefreshRows(faction, vis_mult, vis_min, src_cell, pad, extra)

## Пересчёт без Godot-обёртки в ответе; маски — fog_lit/fog_seen/fog_rgba
func fog_refresh_rows_packed(faction: int, vis_mult: float, vis_min: float,
		src_cell: float, pad: float, extra: PackedFloat32Array) -> int:
	return _c.FogRefreshRowsPacked(faction, vis_mult, vis_min, src_cell, pad, extra)
func fog_lit() -> PackedByteArray:
	return _c.FogLit()
func fog_seen() -> PackedByteArray:
	return _c.FogSeen()
func fog_rgba() -> PackedByteArray:
	return _c.FogRgba()

func fog_source_count() -> int:
	return _c.FogSourceCount()

## Число потоков пакетных проходов ядра (этап D2). Потокам разрешена только
## чистая математика по колонкам; вода/узлы/подача — главный поток
func set_threads(t: int) -> void:
	_c.SetThreads(t)

func rear_press_arm(i: int, tx: float, tz: float, speed: float, stop: float) -> void:
	_c.RearPressArm(i, tx, tz, speed, stop)

func rear_press_clear(i: int) -> void:
	_c.RearPressClear(i)

func rear_press_pass(delta: float, shards: int, phase: int) -> int:
	return _c.RearPressPass(delta, shards, phase)

## Автопилот подхода (этап D1): дальняя дорога к назначенной цели без входа
## в GDScript-автомат; направление — на живую строку цели каждый такт
const F_AUTOPILOT := 1 << 22

## BigStand, этап 4: темп подтягивания и его порог, плановый возврат в
## GDScript раз в cadence, сторона обхода своих — всё, чем ядро заменяет
## покадровый вход в _process_attack у идущего к цели
func autopilot_arm(i: int, speed: float, pull_speed: float, stop: float,
		pull_lim: float, cadence: float, side_sign: float) -> void:
	_c.AutopilotArm(i, speed, pull_speed, stop, pull_lim, cadence, side_sign)

## Марш стены к точке (Unit._phalanx_march): стоп на ARRIVE_RADIUS
func autopilot_arm_goal(i: int, speed: float, gx: float, gz: float,
		stop: float, cadence: float) -> void:
	_c.AutopilotArmGoal(i, speed, gx, gz, stop, cadence)

func autopilot_clear(i: int) -> void:
	_c.AutopilotClear(i)

func autopilot_pass(delta: float, shards: int, phase: int,
		tick: int, scan_mod: int, scan_r: float,
		flank_trig: float, flank_recheck: int, flank_strength: float) -> int:
	return _c.AutopilotPass(delta, shards, phase, tick, scan_mod, scan_r,
		flank_trig, flank_recheck, flank_strength)

func take_press_woken() -> Array:
	return _c.TakePressWoken()

## ── СПИСОК СТРОК, КОТОРЫМ НУЖЕН GDSCRIPT-ТИК (BigStand-5, этап 1) ─────────
## Диспетчер GameManager идёт по этому списку, а не по реестру узлов: ведомые
## ядром (автопилот, напор, дрёма в ATTACKING, матрица отряда) в него не
## попадают и в интерпретатор не входят вовсе. Биты — зеркало Unit.tick_on
## (F_TICK_ON), «в тике свои часы» (F_TICK_ALWAYS, may_sleep_physics = false)
## и «отряд ведёт матрицей» (F_MATRIX_LED). Разбор — ArmyCore.TickRows
const F_TICK_ON := 1 << 23
const F_TICK_ALWAYS := 1 << 24
const F_MATRIX_LED := 1 << 25
## Ожидание такта агро в ядре (этап 1б): таймер тикает в TickRows
const F_IDLE_WAIT := 1 << 26

## ── ОТРЯДНЫЕ ПЕРЕСЧЁТЫ ОДНИМ ВЫЗОВОМ (BigStand-5, этап 2) ────────────────
## Коридор: [n, cx, cz, far, watch, fac, clear_trunk, clear_enemy] — габариты,
## стволы и чужие за один переход границы, ответ плоским массивом
func squad_corridor(rows: PackedInt32Array, dead: int, aggro_r: float,
		intercept: float, margin: float) -> PackedFloat32Array:
	return _c.SquadCorridor(rows, dead, aggro_r, intercept, margin)

## Бухгалтерия боя отряда по колонкам (см. ArmyCore.SquadMelee): снимков
## px/pz больше нет — они стоили 32 КБ управляемых аллокаций на пересчёт
func squad_melee(rows: PackedInt32Array, attacking_state: int) -> PackedInt32Array:
	return _c.SquadMelee(rows, attacking_state)

## Отрицательный номер (−i−1) — строка скрыта туманом и тикает реже: дельта
## × fog_slow_div (ТЗ 19.09.2026, Fog-of-War Sleep)
func tick_rows(shards: int, phase: int, attacking_state: int, idle_state: int,
		delta: float, army_ticks: int = 0, player_fac: int = 0, fog_slow_div: int = 0) -> PackedInt32Array:
	return _c.TickRows(shards, phase, attacking_state, idle_state, delta, army_ticks, player_fac, fog_slow_div)

func tick_hidden() -> int:
	return int(_c.TickHidden)

func tick_slowed() -> int:
	return int(_c.TickSlowed)

func idle_wait_arm(i: int, t: float) -> void:
	_c.IdleWaitArm(i, t)

## Возвращает остаток таймера агро — поле бойца на время ожидания заморожено
func idle_wait_clear(i: int) -> float:
	return _c.IdleWaitClear(i)

## Сколько строк ядро оставило себе последним TickRows (стендам)
func tick_skipped() -> int:
	return int(_c.TickSkipped)

func tick_listed() -> int:
	return int(_c.TickListed)


func rb_create(mm_rid: RID) -> int:
	return _c.RbCreate(mm_rid)

func rb_ensure(b: int, instances: int) -> void:
	_c.RbEnsure(b, instances)

func rb_write_full(b: int, idx: int, pos: Vector3, frame: int, mirror: bool,
		flash: float, hp: float) -> void:
	_c.RbWriteFull(b, idx, pos.x, pos.y, pos.z, frame, mirror, flash, hp)

func rb_write_pos(b: int, idx: int, pos: Vector3) -> void:
	_c.RbWritePos(b, idx, pos.x, pos.y, pos.z)

func rb_write_frame(b: int, idx: int, frame: int) -> void:
	_c.RbWriteFrame(b, idx, frame)

func rb_write_color(b: int, idx: int, r: float, g: float, bl: float, a: float) -> void:
	_c.RbWriteColor(b, idx, r, g, bl, a)

func rb_write_dmg(b: int, idx: int, flash: float, hp: float) -> void:
	_c.RbWriteDmg(b, idx, flash, hp)

func rb_hide_slot(b: int, idx: int) -> void:
	_c.RbHideSlot(b, idx)

func rb_hide_all(b: int) -> void:
	_c.RbHideAll(b)

## Окно чтения слота для стендов: 16 float как есть (не покадровый путь)
func rb_slot(b: int, idx: int) -> PackedFloat32Array:
	return _c.RbSlot(b, idx)

func rb_dirty(b: int) -> bool:
	return _c.RbDirty(b)

func rb_clear_dirty(b: int) -> void:
	_c.RbClearDirty(b)

func rb_flush() -> void:
	_c.RbFlush()

func row_bind(i: int, b: int, idx: int, base_y: float,
		draw: Vector3, draw_init: bool) -> void:
	_c.RowBind(i, b, idx, base_y, draw.x, draw.y, draw.z, draw_init)

func row_unbind(i: int) -> void:
	_c.RowUnbind(i)

func draw_pos(i: int) -> Vector3:
	return _c.DrawPos(i)

func row_sync_draw(i: int, p: Vector3) -> void:
	_c.RowSyncDraw(i, p.x, p.y, p.z)

func batch_visual(delta: float, lerp_k: float, snap_sq: float,
		bob_amp: float, bob_sprint: float, anim_core: bool, decal_core: bool,
		now_ms: int, view_x: float, view_z: float, view_r2: float,
		fog_watch: bool, player_fac: int, flash_sec: float,
		walk_min: float, move_min: float, turn_cos2: float) -> void:
	_c.BatchVisual(delta, lerp_k, snap_sq, bob_amp, bob_sprint, anim_core, decal_core,
		now_ms, view_x, view_z, view_r2, fog_watch, player_fac, flash_sec,
		walk_min, move_min, turn_cos2)

## ── ТИХИЕ СТРОКИ (BigStand-5, этап 5) ─────────────────────────────────────
## Боец объявляет себя тихим: GDScript-тик картинки не идёт, пока ядро не
## заметит повод (срок, туман, LOD, ходьба, взгляд ведомого)
func vis_quiet(i: int, look_x: float, look_z: float, moving: bool, moving2: bool,
		seen: bool, lit: bool, wake_at_ms: int, now_ms: int) -> void:
	_c.VisQuiet(i, look_x, look_z, moving, moving2, seen, lit, wake_at_ms, now_ms)

func vis_wake(i: int) -> void:
	_c.VisWake(i)

func vis_is_quiet(i: int) -> bool:
	return _c.VisIsQuiet(i)

## Вспышка попадания у привязанной строки — гасит ядро
func vis_hit(i: int, peak: float, sec: float) -> void:
	_c.VisHit(i, peak, sec)

## Строки, которым нужен GDScript-тик картинки на этом шарде
func vis_rows(shards: int, phase: int) -> PackedInt32Array:
	return _c.VisRows(shards, phase)

func vis_listed() -> int:
	return _c.VisListed

func vis_quiet_count() -> int:
	return _c.VisQuietN

## ── ДЕКЛАРАТИВНЫЕ СТРЕЛЫ (хак физтика №1) ─────────────────────────────────
## Измерительная ручка: проверка чужих тел на шаге выключена (потолок хака №2)
func set_skip_body_scan(on: bool) -> void:
	_c.SkipBodyScan = on

## ax_k — масштаб оси: единица у стрелы, меньше у кости гнолла (признак
## кувырка в полёте, разбор — в ArmyCore._afAxK и mm_arrow.gdshader)
func arrow_launch(id: int, b: int, slot: int, s: Vector3, e: Vector3,
		arc_h: float, rate: float, fac: int, ax_k: float = 1.0) -> void:
	_c.ArrowLaunch(id, b, slot, s, e, arc_h, rate, fac, ax_k)

func arrow_cancel(id: int) -> void:
	_c.ArrowCancel(id)

func arrow_flights() -> int:
	return _c.ArrowFlights()

func batch_arrows(delta: float, hit_radius: float) -> void:
	_c.BatchArrows(delta, hit_radius, 0.0)

## [id, жертва|null, точка, ось] × N
func take_arrow_events() -> Array:
	return _c.TakeArrowEvents()

## ── СНАРЯДЫ БЕЗ УЗЛА (BigStand-5, этап 3) ────────────────────────────────
## Флаги полёта — те же биты, что ArmyCore.Pf*
const PF_SNIPE := 1 << 1
const PF_TARGET := 1 << 2
const PF_BONE := 1 << 3

## Выстрел: слот слоя ядро берёт само; −1 — в слое нет свободного слота
## (вызывающий растит слой rb_grow и повторяет)
func projectile_fire(b: int, s: Vector3, e: Vector3, arc_h: float, rate: float,
		fac: int, ax_k: float, dmg: float, shooter_id: int, tgt_id: int, flags: int,
		length: float, life: float, fade: float, max_age: float) -> int:
	return _c.ProjectileFire(b, s, e, arc_h, rate, fac, ax_k, dmg, shooter_id,
		tgt_id, flags, length, life, fade, max_age)

func batch_arrows_relief(delta: float, hit_radius: float, relief_amp: float) -> void:
	_c.BatchArrows(delta, hit_radius, relief_amp)

func has_projectile_events() -> bool:
	return _c.HasProjectileEvents()

## [id, тип, строка жертвы, id стрелка, id цели, флаги, слой, слот] × N
func take_projectile_events_i() -> PackedInt64Array:
	return _c.TakeProjectileEventsI()

## [x, y, z, ax, ay, az, урон, длина] × N
func take_projectile_events_f() -> PackedFloat32Array:
	return _c.TakeProjectileEventsF()

## [n, x, y, z] × групп промахов за кадр (клетки 32 м) или пусто
func take_miss_sound() -> PackedFloat32Array:
	return _c.TakeMissSound()

## Промах / посадка у здания: втыкание в грунт целиком в ядре → id торчащей
func projectile_land(b: int, slot: int, pos: Vector3, axis: Vector3,
		length: float, life: float, fade: float, relief_amp: float, src_id: int = 0) -> int:
	return _c.ProjectileLand(b, slot, pos.x, pos.y, pos.z, axis.x, axis.y, axis.z,
		length, life, fade, relief_amp, src_id)

## В тело (in_corpse — без срока, гасит тело) или декором с сроком
func projectile_stick(b: int, slot: int, at: Vector3, dir: Vector3, length: float,
		in_corpse: bool, life: float, fade: float) -> int:
	return _c.ProjectileStick(b, slot, at.x, at.y, at.z, dir.x, dir.y, dir.z,
		length, in_corpse, life, fade)

func projectile_drop(b: int, slot: int) -> void:
	_c.ProjectileDrop(b, slot)

func projectile_config(max_stuck: int, evict_fade: float, min_down: float,
		exposed: float, jitter: float) -> void:
	_c.ProjectileConfig(max_stuck, evict_fade, min_down, exposed, jitter)

func flights_on(b: int) -> int:
	return _c.FlightsOn(b)

## Стендам: [id, слой, слот, флаги] × N
func flight_list() -> PackedInt32Array:
	return _c.FlightList()

## Стендам: [sx, sy, sz, ex, ey, ez, t, возраст, дуга, темп, урон] или пусто
func flight_info(id: int) -> PackedFloat32Array:
	return _c.FlightInfo(id)

## Стендам: instance id стрелка полёта (0 — нет)
func flight_shooter(id: int) -> int:
	return _c.FlightShooter(id)

func stuck_tick(delta: float) -> void:
	_c.StuckTick(delta)

func stuck_fade(id: int, secs: float) -> void:
	_c.StuckFade(id, secs)

func stuck_remove(id: int) -> void:
	_c.StuckRemove(id)

func stuck_count() -> int:
	return _c.StuckCount()

func projectiles_reset() -> void:
	_c.ProjectilesReset()

func stuck_fading_count() -> int:
	return _c.StuckFadingCount()

func stuck_left(id: int) -> float:
	return _c.StuckLeft(id)

func stuck_is_fading(id: int) -> bool:
	return _c.StuckIsFading(id)

func stuck_in_corpse(id: int) -> bool:
	return _c.StuckInCorpse(id)

## Стендам: [id, слой, слот, вТеле, id полёта] × N в порядке вставки
func stuck_list() -> PackedInt32Array:
	return _c.StuckList()

func rb_acquire(b: int) -> int:
	return _c.RbAcquire(b)

func rb_release(b: int, idx: int) -> void:
	_c.RbRelease(b, idx)

func rb_grow(b: int, new_cap: int) -> void:
	_c.RbGrow(b, new_cap)

func rb_free_count(b: int) -> int:
	return _c.RbFreeCount(b)

## Лента строки: кадров, к/с, зацикленность, стартовая фаза (в кадрах). Кадр
## дальше листает BatchVisual (этап E1)
func row_anim(i: int, frames: int, fps: float, loop: bool, phase: float) -> void:
	_c.RowAnim(i, frames, fps, loop, phase)

## Смещения по высоте колец, теней и полосок — один раз
func decal_config(ring_y: float, shadow_y: float, hp_y: float) -> void:
	_c.DecalConfig(ring_y, shadow_y, hp_y)

func decal_bind(i: int, ring_b: int, sh_b: int, idx: int) -> void:
	_c.DecalBind(i, ring_b, sh_b, idx)

func decal_unbind(i: int) -> void:
	_c.DecalUnbind(i)

func hp_bind(i: int, b: int, idx: int) -> void:
	_c.HpBind(i, b, idx)

func hp_unbind(i: int) -> void:
	_c.HpUnbind(i)

## Полный трансформ слота (базис + точка), цвет не трогается
func rb_write_xform(b: int, idx: int, b0: Vector3, b1: Vector3, b2: Vector3,
		pos: Vector3) -> void:
	_c.RbWriteXform(b, idx, b0, b1, b2, pos)

## Направление, посчитанное пакетным боем
func facing_x(i: int) -> float:
	return _c.FacingX(i)

func facing_z(i: int) -> float:
	return _c.FacingZ(i)

func set_flag(i: int, bit: int, on: bool) -> void:
	_c.SetFlag(i, bit, on)

func has_flag(i: int, bit: int) -> bool:
	return _c.HasFlag(i, bit)

func pos_ready(i: int) -> bool:
	return _c.PosReady(i)

# ── СЕТКА ───────────────────────────────────────────────────────────────────
func rebuild_grid() -> void:
	_c.RebuildGrid()

func grid_cells() -> int:
	return _c.GridCells()

func grid_units() -> int:
	return _c.GridUnits()

func grid_cell_size() -> float:
	return _c.GridCellSize()

# ── СКАНЫ СОСЕДЕЙ ───────────────────────────────────────────────────────────
func enemy_near(x: float, z: float, my_faction: int, radius: float) -> bool:
	return _c.EnemyNear(x, z, my_faction, radius)

func allies_count_near(row: int, at_x: float, at_z: float, radius: float,
		limit: int) -> int:
	return _c.AlliesCountNear(row, at_x, at_z, radius, limit)

func ally_overlap(row: int, at_x: float, at_z: float, min_dist: float,
		max_push: float) -> Vector3:
	return _c.AllyOverlap(row, at_x, at_z, min_dist, max_push)

func enemy_block(row: int, tx: float, tz: float, min_dist: float, away_ok: bool = false) -> Vector3:
	return _c.EnemyBlock(row, tx, tz, min_dist, away_ok)

## Окно для стендов: сколько живых С ЭТИМИ БИТАМИ стоят ближе radius к чужому
func enemy_overlap_count_flagged(radius: float, mask: int) -> int:
	return _c.EnemyOverlapCountFlagged(radius, mask)

## Окно для стендов: сколько живых стоят ближе radius к чужому телу
## (инвариант твёрдости строя, см. ArmyCore.EnemyOverlapCount)
func enemy_overlap_count(radius: float) -> int:
	return _c.EnemyOverlapCount(radius)

func allies_ahead(row: int, dx_dir: float, dz_dir: float, look: float,
		half_width: float) -> int:
	return _c.AlliesAhead(row, dx_dir, dz_dir, look, half_width)

func nearest_enemy_offset(row: int, radius: float) -> Vector3:
	return _c.NearestEnemyOffset(row, radius)

func best_enemy(row: int, radius: float, crowd_penalty: float):
	return _c.BestEnemy(row, radius, crowd_penalty)

func best_enemy_w(row: int, radius: float, crowd_penalty: float, use_prio: bool):
	return _c.BestEnemyW(row, radius, crowd_penalty, use_prio)

## prio: 0 — ближайший, 1 — вес стрелка, 2 — вес конницы
func best_enemy_prio(row: int, radius: float, crowd_penalty: float, prio: int):
	return _c.BestEnemyPrio(row, radius, crowd_penalty, prio)

func nearest_of_side(x: float, z: float, want_side: int, radius: float):
	return _c.NearestOfSide(x, z, want_side, radius)

## Самый раненый свой (доля запаса) в радиусе, без массива; null — раненых нет
func most_wounded_of_side(x: float, z: float, side: int, radius: float, exclude_row: int):
	return _c.MostWoundedOfSide(x, z, side, radius, exclude_row)

## Узлы собирает GDScript по строкам (SpatialGrid.query_radius, этап 4):
## Godot-массив узлов из C# — финализируемая обёртка на каждый элемент
func query_radius(x: float, z: float, radius: float) -> Array:
	return GameManager.unit_grid.query_radius(Vector3(x, 0.0, z), radius)

## Те же бойцы — СТРОКАМИ ядра (PackedInt32Array, без финализируемых
## обёрток на элемент; BigStand-5, этап 4). Узел по строке — GameManager._row_units
func query_radius_rows(x: float, z: float, radius: float) -> PackedInt32Array:
	return _c.QueryRadiusRows(x, z, radius)

## Счёт живых чужих в радиусе без массива
func enemy_count(x: float, z: float, radius: float, fac: int) -> int:
	return _c.EnemyCount(x, z, radius, fac, Unit.State.DEAD)

# ── РЕЕСТР СТВОЛОВ ──────────────────────────────────────────────────────────
# Переехал сюда из GameManager вместе с колонками: это был последний вызов
# наружу, остававшийся ВНУТРИ шага. Теперь пакетный проход не пересекает
# границу языков вовсе
func register_trunk(pos: Vector3, radius: float) -> void:
	_c.RegisterTrunk(pos, radius)

func unregister_trunk(pos: Vector3) -> void:
	_c.UnregisterTrunk(pos)

func clear_trunks() -> void:
	_c.ClearTrunks()

func trunk_count() -> int:
	return _c.TrunkCount()

func trunk_block(x: float, z: float, body_r: float) -> Vector3:
	return _c.TrunkBlock(x, z, body_r)

func trunk_near(x: float, z: float, radius: float) -> bool:
	return _c.TrunkNear(x, z, radius)

# ── ФУНДАМЕНТЫ ПОСТРОЕК (ТЗ 19.09.2026 «коллизии зданий») ──────────────────
# Постройка — ряд кругов (x, z, r), ключ — instance id; блокируют шаг любой
# стороны (скольжение вдоль, стоящий внутри выходит) и режут сетку навигации
func register_obstacle(id: int, flat: PackedFloat32Array) -> void:
	_c.RegisterObstacle(id, flat)

func unregister_obstacle(id: int) -> void:
	_c.UnregisterObstacle(id)

func clear_obstacles() -> void:
	_c.ClearObstacles()

func obstacle_count() -> int:
	return int(_c.ObstacleCount())

## Вектор выталкивания из ближайшего фундамента (как trunk_block)
func bld_block(x: float, z: float, body_r: float) -> Vector3:
	return _c.BldBlock(x, z, body_r)

## Глубина проникновения точки в фундамент; 0 — свободно
func bld_depth(x: float, z: float, body_r: float) -> float:
	return float(_c.BldDepth(x, z, body_r))

func bld_near(x: float, z: float, radius: float) -> bool:
	return bool(_c.BldNear(x, z, radius))

## Сколько ячеек сетки навигации заняли постройки (стендам)
func nav_bld_cells() -> int:
	return int(_c.NavBldCells)

# ── ПАКЕТНЫЕ ПРОХОДЫ ────────────────────────────────────────────────────────
func batch_move(lim_x: float, lim_z: float, bounds_on: bool, water_on: bool,
		block_r: float, trunk_clear: float, relief_amp: float, gm) -> int:
	return _c.BatchMove(lim_x, lim_z, bounds_on, water_on, block_r, trunk_clear,
		relief_amp, gm)

func request_step(i: int, sx: float, sz: float, fl: int) -> void:
	_c.RequestStep(i, sx, sz, fl)

## Заявки на шаг ПАЧКОЙ: один переход границы на кадр вместо одного на бойца.
## Разбор — в шапке ArmyCore.BatchMoveQueued
func batch_move_queued(rows: PackedInt32Array, xs: PackedFloat32Array,
		zs: PackedFloat32Array, fls: PackedInt32Array,
		lim_x: float, lim_z: float, bounds_on: bool, water_on: bool,
		block_r: float, trunk_clear: float, relief_amp: float, gm) -> int:
	return _c.BatchMoveQueued(rows, xs, zs, fls, lim_x, lim_z, bounds_on,
		water_on, block_r, trunk_clear, relief_amp, gm, -1)

## cross_squad — во сколько раз шире держатся бойцы РАЗНЫХ отрядов
## (см. Unit.SEP_CROSS_SQUAD и разбор в ArmyCore.BatchSeparation)
func batch_separation(delta: float, min_dist: float, max_step: float,
		interval: float, lim_x: float, lim_z: float, moving_state: int,
		attacking_state: int, water_on: bool, gm, deadzone: float = 0.0,
		relief_amp: float = 0.0, cross_squad: float = 1.0,
		pass_relief: float = 1.0, trunk_clear: float = 0.0) -> int:
	return _c.BatchSeparation(delta, min_dist, max_step, interval, lim_x, lim_z,
		moving_state, attacking_state, water_on, gm, deadzone, relief_amp,
		cross_squad, pass_relief, trunk_clear)

func advance_matrix(rows: PackedInt32Array, ax: float, az: float, ny: float,
		cx: float, cz: float, amp: float = 0.0) -> int:
	return _c.AdvanceMatrix(rows, ax, az, ny, cx, cz, amp)

func push_to_nodes(rows: PackedInt32Array) -> void:
	_c.PushToNodes(rows)

## ГАБАРИТЫ ОТРЯДА ПО СТРОКАМ. Возвращает [n, cx, cz, radius, watch, faction].
##
## Здесь был harvest_squad, который принимал СПИСОК ОБЪЕКТОВ и снимал точки из
## узлов. С переездом колонок в солвер это стало худшим местом всего перехода:
## три чтения свойства через Variant на каждого бойца — ветка squad_corridor
## подорожала с 615 до 2977 мкс на кадр. Снимать точки из узлов больше не нужно
## вовсе — колонку ведут пакетный шаг и разбор наложения. Остался один переход
## границы на ОТРЯД вместо трёх на БОЙЦА
func squad_bounds(rows: PackedInt32Array, dead: int,
		aggro_r: float, intercept: float) -> Array:
	return _c.SquadBounds(rows, dead, aggro_r, intercept)

# ── ДИАГНОСТИКА ПАКЕТНОГО ШАГА (читают стенды) ──────────────────────────────
var bm_pending: int:
	get: return _c.GetBmPending()
var bm_trunk_calls: int:
	get: return _c.GetBmTrunkCalls()
var bm_enemy_scans: int:
	get: return _c.GetBmEnemyScans()
var bm_blocked: int:
	get: return _c.GetBmBlocked()
