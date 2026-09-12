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

func nav_free(x: float, z: float) -> bool:
	return bool(_c.NavFree(x, z))

func nav_line_blocked(x0: float, z0: float, x1: float, z1: float) -> bool:
	return bool(_c.NavLineBlocked(x0, z0, x1, z1))

## Плоский массив [x, z, x, z, …] промежуточных точек; пусто — путь прямой
## (nav_last_found = true) либо пути нет (false). Длина нити — nav_last_length
func nav_path(x0: float, z0: float, x1: float, z1: float) -> PackedFloat32Array:
	return PackedFloat32Array(_c.NavPath(x0, z0, x1, z1))

func nav_last_found() -> bool:
	return bool(_c.NavLastFound)

func nav_last_length() -> float:
	return float(_c.NavLastLength)

func nav_calls() -> int:
	return int(_c.NavCalls)

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

func get_sep_radius(i: int) -> float:
	return _c.GetSepRadius(i)

func set_combat(i: int, dmg: float, rng: float, spd: float) -> void:
	_c.SetCombat(i, dmg, rng, spd)

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

## Источники плоскими тройками [x, z, r]; возвращает [lit, seen, rgba]
func fog_refresh(src: PackedFloat32Array) -> Array:
	return _c.FogRefresh(src)

## Источники по бойцам собирает ядро (живые строки фракции с настоящей
## координатой, радиус обзора от attack_range, слияние по ячейке src_cell);
## extra — дополнительные тройки [x, z, r] (постройки, постоянные засветы)
func fog_refresh_rows(faction: int, vis_mult: float, vis_min: float,
		src_cell: float, pad: float, extra: PackedFloat32Array) -> Array:
	return _c.FogRefreshRows(faction, vis_mult, vis_min, src_cell, pad, extra)

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

func autopilot_arm(i: int, speed: float, stop: float) -> void:
	_c.AutopilotArm(i, speed, stop)

func autopilot_clear(i: int) -> void:
	_c.AutopilotClear(i)

func autopilot_pass(delta: float, shards: int, phase: int,
		tick: int, scan_mod: int, scan_r: float) -> int:
	return _c.AutopilotPass(delta, shards, phase, tick, scan_mod, scan_r)

func take_press_woken() -> Array:
	return _c.TakePressWoken()


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
		bob_amp: float, bob_sprint: float, anim_core: bool = false,
		decal_core: bool = false) -> void:
	_c.BatchVisual(delta, lerp_k, snap_sq, bob_amp, bob_sprint, anim_core, decal_core)

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
	_c.BatchArrows(delta, hit_radius)

## [id, жертва|null, точка, ось] × N
func take_arrow_events() -> Array:
	return _c.TakeArrowEvents()

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

func nearest_of_side(x: float, z: float, want_side: int, radius: float):
	return _c.NearestOfSide(x, z, want_side, radius)

func query_radius(x: float, z: float, radius: float) -> Array:
	return _c.QueryRadius(x, z, radius)

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
