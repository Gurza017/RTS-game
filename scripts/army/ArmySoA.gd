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
	return _c.WritePoseBatch(rows, xs, ys, zs, vxs, vzs, sts, gates, eff)

## ПАКЕТНЫЙ ПРОХОД БОЯ. Возвращает бойцов, которых пакет НЕ закрыл, — им нужен
## полный автомат. Разбор — в шапке ArmyCore.BatchCombat
func batch_combat(delta: float, attacking_state: int, pull_up_speed: float,
		pull_up_max: float, shards: int, phase: int) -> PackedByteArray:
	return _c.BatchCombat(delta, attacking_state, pull_up_speed, pull_up_max,
		shards, phase)

## Строка цели атаки (пишется по событию из Unit.set_attack_target)
func set_target(i: int, t: int) -> void:
	_c.SetTarget(i, t)

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

func enemy_block(row: int, tx: float, tz: float, min_dist: float) -> Vector3:
	return _c.EnemyBlock(row, tx, tz, min_dist)

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
		water_on, block_r, trunk_clear, relief_amp, gm)

func batch_separation(delta: float, min_dist: float, max_step: float,
		interval: float, lim_x: float, lim_z: float, moving_state: int,
		attacking_state: int, water_on: bool, gm, deadzone: float = 0.0,
		relief_amp: float = 0.0) -> int:
	return _c.BatchSeparation(delta, min_dist, max_step, interval, lim_x, lim_z,
		moving_state, attacking_state, water_on, gm, deadzone, relief_amp)

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
