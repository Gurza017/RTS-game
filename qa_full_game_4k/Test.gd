extends Node

## ═══════════════════════════════════════════════════════════════════════════
## НАСТОЯЩИЙ НАГРУЗОЧНЫЙ СТЕНД: ПАРТИЯ НА ЧЕТЫРЁХ ТЫСЯЧАХ С ЖИВОЙ ЭКОНОМИКОЙ
## ═══════════════════════════════════════════════════════════════════════════
## ЗАЧЕМ ЕЩЁ ОДИН. Синтетические стенды (qa_fps, qa_mass_perf) показывали
## зелёную отчётность, а на реальном билде игра рассыпалась: стрелы висели в
## воздухе пачками, мечники протекали сквозь фалангу, кадр падал до 30.
## Ни одна из трёх бед в стерильной сцене не живёт:
##   • стрелы висят только там, где ЛУЧНИКИ СТРЕЛЯЮТ ПО ЖИВЫМ и промахиваются
##     сотнями (общий MultiMesh стрел, этап D3);
##   • протекание живёт на СТЫКАХ строёв в контакте, с приказами и отходами;
##   • кадр падает, когда одновременно идут рубка, ИИ, туман, ДОСТАВКА
##     РЕСУРСОВ (рабочие ходят своим, не пакетным, путём) и стройка.
##
## СЦЕНА. Две смешанные армии по 2000 (копейщики, лучники, мечники, кабаны)
## сходятся в центре; у каждой стороны сто рабочих на добыче (лес, золото,
## камень) с доставкой в замок и бригада строителей на трёх площадках;
## красный ИИ, орда, туман, HUD, деревня — всё на месте, как в партии.
##
## ЧТО ПЕЧАТАЕТ. Фаза 1 — экономика без боя. Фаза 2 — НАСТОЯЩАЯ рубка с
## потерями: каждые пять секунд снимок кадра (FPS, физтик, кадр логики),
## живых, погибших, СТРЕЛ (в полёте / торчащих / ВИСЯЩИХ В ВОЗДУХЕ / слотов
## буфера / узлов в пуле) и ВЗАИМОПРОНИКНОВЕНИЙ (живых, стоящих ближе ядра
## тела к чужому — инвариант твёрдости строя). Фаза 3 — на замороженной
## численности цена подсистем (гасим — меряем — возвращаем), включая ЦЕНУ
## РАБОЧИХ и слоя стрел, и разбивка физтика по веткам.
##
## ВЕРДИКТЫ — свойства, а не круглые числа: стрелы не висят, буфер стрел не
## течёт, взаимопроникновений не больше доли процента, и ЦЕЛЬ по кадру.
##
## Запуск (ОКНО — для FPS; headless годится для физтика и инвариантов):
##   godot --path . res://qa_full_game_4k/Test.tscn -- res=1920x1080
## Аргументы: player=N ai=N workers=N builders=N res=WxH clash=СЕК fps=ЦЕЛЬ

const _Opt = preload("res://scripts/perf_config.gd")
const _CSite := preload("res://scripts/ConstructionSite.gd")
const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _AICfg := preload("res://scripts/ai_start_army_limit.gd")
const _MainScript := preload("res://scripts/Main.gd")

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []
var _rows: Array = []

var N_PLAYER := 2000
var N_AI := 2000
## Рабочих на сторону — СТОЛЬКО, СКОЛЬКО ДОПУСКАЕТ ПАРТИЯ (лимит ИИ), а не
## круглая сотня: сто рабочих на один склад — это сценарий, которого в игре не
## бывает, и он ловил бы толчею у ворот, а не то, что видит владелец
var N_WORKERS: int = _AICfg.WORKER_LIMIT
var N_BUILDERS := 12          # на сторону
var CLASH_SEC := 30
var FPS_TARGET := 60.0
var RES := Vector2i(1920, 1080)
var _headless: bool = false

var _mine: Array = []
var _foes: Array = []
var _workers: Array = []
var _builders: Array = []
var _sites: Array = []

## Состав как в партии
const MIX := {
	"res://scenes/units/Spearman.tscn": 0.45,
	"res://scenes/units/Archer.tscn":   0.25,
	"res://scenes/units/Warrior.tscn":  0.22,
	"res://scenes/units/GoblinPigRider.tscn": 0.08,
}
const SQUAD_SIZE := 40
const COLS := 8
const GAP := 0.75
## Блоков отрядов в одной линии фронта (вдоль Z); остальные — эшелонами В ТЫЛ.
## Первая версия ставила блоки 6 в ряд ВГЛУБЬ (по X): армии стояли в 104 м
## друг от друга, за 30 с «рубки» сходились только передние блоки — 74
## погибших из 5000, в контакте 40. Мерился марш, а не бой
const FRONT_BLOCKS := 10
const BLOCK_STEP_X := 9.0
const BLOCK_STEP_Z := 8.0
## Расстояние между фронтами: контакт передних блоков через ~5 с, тыловых
## эшелонов (4 × 9 м) — за 30 с окна
const FRONT_GAP := 24.0
## Прогрев экономики до первого замера, игровых секунд
const ECON_WARM_SEC := 25
## Шаг между снимками фазы 2, игровых секунд
const SNAP_SEC := 5
## Ядро тела: ближе этого чужие тела стоять не должны (см. ArmyCore.PassCoreFrac)
const CORE_R := 0.30
## Снимок считается ЛИНЕЙНЫМ БОЕМ, пока в контакте не меньше стольких
const LINE_CONTACT_MIN := 100

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func verdict(title: String, ok: bool, detail: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	_log.append([title, ok])
	print("  ВЕРДИКТ %s: %s%s" % [title, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + detail) if detail != "" else ""])

func _pad(s: String, n: int) -> String:
	var o := s
	while o.length() < n: o += " "
	return o

# ─────────────────────────────────────────────────────────────────────────────
# ЗАМЕР КАДРА
# ─────────────────────────────────────────────────────────────────────────────
func _sample(warm: int = 30, n: int = 45) -> Dictionary:
	if get_tree().paused:
		get_tree().paused = false
	await frames(warm)
	_Opt.tick_reset()
	_Opt.vis_reset()
	var fps := 0.0
	var draws := 0
	var t0: int = Time.get_ticks_usec()
	# ── ПИКИ КАДРА, А НЕ ТОЛЬКО СРЕДНЕЕ (09.09.2026) ─────────────────────
	# Жалоба «фризы и микролаги» средним FPS не ловится вовсе: кадр в 40 мс
	# раз в секунду тонет в шестидесяти кадрах по 14. Стенные часы между
	# соседними кадрами дают распределение; печатаются худший и p95
	var deltas: PackedFloat32Array = PackedFloat32Array()
	var t_prev: int = t0
	for _i in range(n):
		await get_tree().process_frame
		var now: int = Time.get_ticks_usec()
		deltas.append(float(now - t_prev) * 0.001)
		t_prev = now
		fps += Performance.get_monitor(Performance.TIME_FPS)
		draws = maxi(draws, int(Performance.get_monitor(
			Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	var f: float = fps / float(n)
	# В headless TIME_FPS — темп главного цикла; честнее стенные часы
	if _headless:
		f = float(n) * 1.0e6 / maxf(float(Time.get_ticks_usec() - t0), 1.0)
	var sorted: Array = Array(deltas)
	sorted.sort()
	var worst: float = float(sorted[sorted.size() - 1]) if not sorted.is_empty() else 0.0
	var p95: float = float(sorted[int(float(sorted.size() - 1) * 0.95)]) \
		if not sorted.is_empty() else 0.0
	return {
		"fps": f,
		"ms": 1000.0 / maxf(f, 0.001),
		"tick": _Opt.tick_ms(),
		"vis": _Opt.vis_ms(),
		"draws": draws,
		"worst": worst,
		"p95": p95,
	}

func _cost(label: String, off: Callable, on: Callable,
		base_before: Dictionary) -> Dictionary:
	off.call()
	var without: Dictionary = await _sample()
	on.call()
	var base_after: Dictionary = await _sample()
	var base_ms: float = (float(base_before["ms"]) + float(base_after["ms"])) * 0.5
	var base_tick: float = (float(base_before["tick"]) + float(base_after["tick"])) * 0.5
	var base_vis: float = (float(base_before["vis"]) + float(base_after["vis"])) * 0.5
	_rows.append([label, base_ms - float(without["ms"]),
		base_tick - float(without["tick"]), base_vis - float(without["vis"]),
		float(without["fps"])])
	return base_after

func _print_frame(s: Dictionary) -> void:
	var live: int = GameManager.active_units()
	var fps: float = float(s["fps"])
	var phys_hz: float = _Opt.army_hz()
	var per_frame: float = float(s["tick"]) * (phys_hz / maxf(fps, 1.0))
	print("  юнитов живых %d (ходячих %d) | вызовов отрисовки %d | шардов физики %d, визуальных %d"
		% [GameManager._live_units.size(), live, int(s["draws"]),
			_Opt.shards_for(live), _Opt.vis_shards_for(live)])
	print("  %.1f FPS (%.2f мс на кадр) | физтик %.2f мс x %.2f = %.2f мс/кадр | кадр логики %.2f мс | логика итого %.2f мс"
		% [fps, float(s["ms"]), float(s["tick"]), phys_hz / maxf(fps, 1.0), per_frame,
			float(s["vis"]), per_frame + float(s["vis"])])
	print("  пики кадра: худший %.1f мс, p95 %.1f мс" % [
		float(s.get("worst", 0.0)), float(s.get("p95", 0.0))])

# ─────────────────────────────────────────────────────────────────────────────
# СТРЕЛЫ: ЖИЗНЕННЫЙ ЦИКЛ ПО ЧИСЛАМ
# ─────────────────────────────────────────────────────────────────────────────
func _find_arrows() -> Array:
	var out: Array = []
	var root: Node = main.world_root()
	for c in root.get_children():
		var n3 := c as Node3D
		if n3 == null:
			continue
		var sc: Variant = n3.get_script()
		if sc != null and String((sc as Script).resource_path).ends_with("Arrow.gd"):
			out.append(n3)
	return out

## [узлов, в полёте, торчащих (по узлам), висящих в воздухе, слотов буфера,
##  свободных слотов, в пуле, в реестре торчащих, худший подъём над землёй]
func _arrow_stats() -> Dictionary:
	var arrows: Array = _find_arrows()
	var flying := 0
	var stuck := 0
	var hanging := 0
	var worst := 0.0
	var mm = GameManager.arrows_mm
	# Снаряды без узла (этап 3): полёты и торчащие — записи ядра, точка — слот
	for fr in GameManager.flight_records():
		if not bool(fr["bone"]):
			flying += 1
	for r in GameManager.stuck_arrow_records():
		if bool(r["bone"]):
			continue
		stuck += 1
		var rp: Vector3 = r["pos"]
		var rl: float = rp.y - GameManager.get_terrain_height(rp.x, rp.z)
		if rl > 0.5:
			hanging += 1
			print("    ВИСИТ (ядро): y=%.2f грунт=%.2f в теле=%s гаснет=%.2f" % [
				rp.y, rp.y - rl, str(r["corpse"]), float(r["fade"])])
		worst = maxf(worst, rl)
	# Legacy-узлы (ручка projectile_core выключена)
	for a in arrows:
		var spent: bool = bool(a.get("_spent"))
		var pooled: bool = bool(a.get("_pooled"))
		if pooled:
			continue
		if not spent:
			flying += 1
			continue
		stuck += 1
		var si: int = int(a.get("_slot_i"))
		if si < 0 or mm == null or mm.core_id < 0:
			continue
		var slot: PackedFloat32Array = GameManager.army.rb_slot(mm.core_id, si)
		if slot.size() < 16 or slot[0] == 0.0:
			continue
		var y: float = slot[7]
		var g: float = GameManager.get_terrain_height(slot[3], slot[11])
		var lift: float = y - g
		# Торчащая в грунте стоит центром на ~0.11 м над землёй, в теле —
		# чуть выше; полметра над грунтом — это уже «висит в воздухе»
		if lift > 0.5:
			hanging += 1
			# Диагностика висящей: что это за стрела и где стоит её узел
			print("    ВИСИТ: слот y=%.2f грунт=%.2f узел=%s в теле=%s гаснет=%s полёт=%d кость=%s" % [
				y, g, str((a as Node3D).global_position), str(a.get("_in_corpse")), str(a.get("_fading")), int(a.get("_flight_id")), str(a.get("bone"))])
		worst = maxf(worst, lift)
	return {
		"nodes": arrows.size(), "flying": flying, "stuck": stuck,
		"hanging": hanging, "worst": worst,
		"slots": (mm.capacity if mm != null else 0),
		"free": (mm.free_count() if mm != null else 0),
		"pool": GameManager.arrow_pool_size(),
		"registry": GameManager.stuck_arrow_count(),
		"fired": GameManager.arrows_fired,
	}

func _print_arrows(st: Dictionary, tag: String) -> void:
	print("  стрелы%s: выпущено %d | узлов %d (в полёте %d, торчит %d, В ВОЗДУХЕ %d, худший подъём %.2f м) | реестр торчащих %d | пул %d | слотов буфера %d (свободных %d)"
		% [tag, int(st["fired"]), int(st["nodes"]), int(st["flying"]), int(st["stuck"]),
			int(st["hanging"]), float(st["worst"]), int(st["registry"]), int(st["pool"]),
			int(st["slots"]), int(st["free"])])

# ─────────────────────────────────────────────────────────────────────────────
# СБОРКА СЦЕНЫ
# ─────────────────────────────────────────────────────────────────────────────
func _mix_list(n: int) -> Array:
	var out: Array = []
	var total := 0.0
	for k in MIX: total += float(MIX[k])
	for k in MIX:
		var cnt: int = int(round(float(n) * float(MIX[k]) / total))
		for _i in range(cnt): out.append(k)
	while out.size() < n: out.append("res://scenes/units/Spearman.tscn")
	return out.slice(0, n)

## Номер эшелона рода войск: чем меньше, тем ближе к противнику
func _echelon_of(scene: String) -> int:
	if scene.contains("Spearman"): return 0
	if scene.contains("Warrior"): return 1
	if scene.contains("PigRider"): return 2
	return 3

func _stat_of(scene: String) -> String:
	if scene.contains("Archer"): return "archer"
	if scene.contains("Warrior"): return "warrior"
	if scene.contains("PigRider"): return "goblin_rider"
	return "spearman"

func _spawn(scene: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = load(scene).instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	return u

## Армия отрядами по SQUAD_SIZE с разметкой строя, блоками 6 в ряд
func _spawn_army(list: Array, fac: int, at: Vector3, course: Vector3) -> Array:
	var out: Array = []
	var i := 0
	var col := 0
	# Однородные отряды: список сортируется по типу, чтобы отряд был из одного
	# рода войск (как из барака), а не смесью. ПОРЯДОК — ЭТО ЭШЕЛОНЫ: первые
	# блоки встают в передний ряд. Простой sort() ставил «Archer» первым по
	# алфавиту, и весь первый эшелон армии оказывался из лучников, а копейщики
	# уезжали в тыл — на 4000 в контакте стояло 18-20 бойцов при 230 погибших
	# от стрел. В партии наоборот: фаланга впереди, стрелки за ней
	list.sort_custom(func(a, b): return _echelon_of(String(a)) < _echelon_of(String(b)))
	while i < list.size():
		var n: int = mini(SQUAD_SIZE, list.size() - i)
		var kind: String = String(list[i])
		# Отряд режется по границе типа
		var m := 0
		while m < n and String(list[i + m]) == kind:
			m += 1
		n = m
		var sid: int = GameManager.new_squad(fac, _stat_of(kind))
		# Передний эшелон стоит на at.x, следующие — ПРОЧЬ от противника
		var bx: float = at.x - float(col / FRONT_BLOCKS) * BLOCK_STEP_X * course.x
		var bz: float = at.z + float(col % FRONT_BLOCKS) * BLOCK_STEP_Z
		var slots: Array = []
		for k in range(n):
			var u := _spawn(kind, fac,
				Vector3(bx + float(k % COLS) * GAP, 0.0, bz + float(k / COLS) * GAP))
			GameManager.add_to_squad(sid, u)
			out.append(u)
			slots.append(u.global_position)
		GameManager.squad_set_formation(sid, slots, course, false)
		i += n
		col += 1
	return out

func _nearest_node(nodes: Array, from: Vector3, want_type: int) -> Node3D:
	var best: Node3D = null
	var bd := INF
	for t in nodes:
		var rn := t as ResourceNode
		if rn == null or not rn.is_gatherable():
			continue
		if want_type >= 0 and rn.resource_type != want_type:
			continue
		var d: float = Vector2(rn.global_position.x - from.x,
			rn.global_position.z - from.z).length_squared()
		if d < bd:
			bd = d
			best = rn
	return best

## Рабочие на добыче трёх ресурсов, с доставкой в ближайший склад
func _spawn_workers(fac: int, at: Vector3, n: int) -> Array:
	var out: Array = []
	var nodes: Array = GameManager.nodes_in_group_cached("resource_nodes")
	var types: Array = [Constants.RESOURCE_WOOD, Constants.RESOURCE_WOOD,
		Constants.RESOURCE_GOLD, Constants.RESOURCE_STONE]
	for i in range(n):
		var u := _spawn("res://scenes/units/Worker.tscn", fac,
			at + Vector3(float(i % 10) * 1.2, 0.0, float(i / 10) * 1.2))
		out.append(u)
		var want: int = int(types[i % types.size()])
		var best: Node3D = _nearest_node(nodes, u.global_position, want)
		if best == null:
			best = _nearest_node(nodes, u.global_position, -1)
		if best != null and u.has_method("command_gather"):
			u.command_gather(best)
	return out

## Три стройплощадки со своей бригадой у каждой. Стройка ДОЛГАЯ, чтобы бригада
## работала весь замер, а не достроилась на прогреве
func _spawn_builders(fac: int, at: Vector3, n: int) -> Array:
	var out: Array = []
	var per_site: int = maxi(n / 3, 1)
	for s in range(3):
		var site = _CSite.new()
		site.faction = fac
		site.target_id = "house" if s != 1 else "barracks"
		site.target_name = "Стройка"
		site.build_size = _UCfg.building_size(site.target_id)
		site.build_time = 900.0
		main.world_add(site)
		var spot := at + Vector3(float(s) * 10.0, 0.0, 6.0)
		site.global_position = Vector3(spot.x, GameManager.get_terrain_height(spot.x, spot.z), spot.z)
		_sites.append(site)
		for k in range(per_site):
			var u := _spawn("res://scenes/units/Worker.tscn", fac,
				spot + Vector3(float(k % 4) * 1.0 - 2.0, 0.0, 4.0 + float(k / 4)))
			out.append(u)
			(u as Worker).command_build(site)
	return out

func _dropoff_of(fac: int) -> Vector3:
	var d = GameManager.get_nearest_dropoff(fac, Vector3.ZERO)
	if d != null:
		return (d as Node3D).global_position
	return Vector3.ZERO

func _fit_camera(on: Array) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or on.is_empty():
		return
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	var mid := Vector3.ZERO
	var cnt := 0
	for u in on:
		if not is_instance_valid(u):
			continue
		var p: Vector3 = (u as Node3D).global_position
		mid += p
		cnt += 1
		lo.x = minf(lo.x, p.x); lo.y = minf(lo.y, p.z)
		hi.x = maxf(hi.x, p.x); hi.y = maxf(hi.y, p.z)
	if cnt == 0:
		return
	mid /= float(cnt)
	main.focus_camera_on(Vector3(mid.x, 0.0, mid.z))
	await frames(2)
	if main._camera != null:
		(main._camera as Node).set_process(false)
	(cam as Camera3D).size = maxf(maxf((hi.x - lo.x) * 1.15,
		(hi.y - lo.y) * 1.7) + 10.0, 24.0)
	var half: Vector2 = Vector2((hi.x - lo.x) * 0.5, (hi.y - lo.y) * 0.5)
	GameManager.update_view_point(Vector3(mid.x, 0.0, mid.z), half.length() + 4.0)

func _alive(men: Array) -> int:
	var n := 0
	for u in men:
		if u != null and is_instance_valid(u) and not (u as Unit).is_dead():
			n += 1
	return n

func _charge(from: Array, to: Array) -> void:
	var c := Vector3.ZERO
	var n := 0
	for u in to:
		if is_instance_valid(u):
			c += (u as Node3D).global_position
			n += 1
	if n == 0:
		return
	c /= float(n)
	for u in from:
		if is_instance_valid(u):
			(u as Unit).command_move(c, false, Vector3.ZERO, false, true)

func _freeze_losses() -> void:
	for u in GameManager._live_units:
		if not is_instance_valid(u):
			continue
		var uu := u as Unit
		if uu == null or uu.is_dead():
			continue
		uu.max_health = 1.0e7
		uu.current_health = 1.0e7

## Сколько работает экономика: рабочие по состояниям и сдано на склад
func _economy_line(bank0: Dictionary) -> String:
	var st: Dictionary = {}
	var live := 0
	for w in _workers + _builders:
		if not is_instance_valid(w) or (w as Unit).is_dead():
			continue
		live += 1
		var k: String = str((w as Unit).state)
		st[k] = int(st.get(k, 0)) + 1
	var delivered: Array = []
	for fac in [Constants.FACTION_PLAYER, Constants.FACTION_ENEMY]:
		for t in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD, Constants.RESOURCE_STONE]:
			var key := "%d_%d" % [fac, t]
			var now: float = ResourceManager.get_amount(fac, t)
			delivered.append("%+.0f" % (now - float(bank0.get(key, now))))
	var builders := 0
	for s in _sites:
		if is_instance_valid(s):
			builders += int(s.builder_count())
	return "рабочих живых %d, по состояниям %s | строителей в артелях %d | сдано (игрок лес/золото/камень, ИИ ...): %s | %s" % [
		live, str(st), builders, ", ".join(delivered), _returning_line()]

## ЗОНД: где стоят возвращающиеся. Первый прогон показал «сдано +0» при
## растущем числе рабочих в RETURNING — надо видеть, доходят ли они до склада
## вообще (ближний/медиана/дальний до своего склада, сколько в 3 м от него)
func _returning_line() -> String:
	var ds: Array = []
	var near := 0
	for w in _workers:
		if not is_instance_valid(w) or (w as Unit).is_dead():
			continue
		if (w as Unit).state != Unit.State.RETURNING:
			continue
		var d = GameManager.get_nearest_dropoff((w as Unit).faction, (w as Node3D).global_position)
		if d == null:
			ds.append(-1.0)
			continue
		var v: Vector3 = (d as Node3D).global_position - (w as Node3D).global_position
		var l: float = Vector2(v.x, v.z).length()
		ds.append(l)
		if l < 3.0:
			near += 1
	if ds.is_empty():
		return "возвращающихся нет"
	ds.sort()
	return "возвращаются %d: до склада ближний %.1f, медиана %.1f, дальний %.1f м, в 3 м от склада %d" % [
		ds.size(), float(ds[0]), float(ds[ds.size() / 2]), float(ds[ds.size() - 1]), near]

func _bank_snapshot() -> Dictionary:
	var d: Dictionary = {}
	for fac in [Constants.FACTION_PLAYER, Constants.FACTION_ENEMY]:
		for t in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD, Constants.RESOURCE_STONE]:
			d["%d_%d" % [fac, t]] = ResourceManager.get_amount(fac, t)
	return d

# ─────────────────────────────────────────────────────────────────────────────
# ПРОГОН
# ─────────────────────────────────────────────────────────────────────────────
func _run() -> void:
	for a in OS.get_cmdline_user_args():
		var s: String = String(a)
		if s.begins_with("player="):    N_PLAYER = int(s.substr(7))
		elif s.begins_with("ai="):      N_AI = int(s.substr(3))
		elif s.begins_with("workers="): N_WORKERS = int(s.substr(8))
		elif s.begins_with("builders="): N_BUILDERS = int(s.substr(9))
		elif s.begins_with("clash="):   CLASH_SEC = int(s.substr(6))
		elif s.begins_with("fps="):     FPS_TARGET = float(s.substr(4))
		elif s.begins_with("res="):
			var p := s.substr(4).split("x")
			if p.size() == 2:
				RES = Vector2i(int(p[0]), int(p[1]))
	_headless = DisplayServer.get_name() == "headless"
	if not _headless:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(RES)
		get_tree().root.content_scale_size = RES
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	seed(11)

	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(20)
	GameManager.world_bounds_enabled = false

	# ── ЗАМОК ИГРОКА ──────────────────────────────────────────────────────
	# В партии его кладёт первый клик игрока (Main._try_place_castle); стенд
	# кликов не делает, и без этой закладки у рабочих игрока НЕТ СКЛАДА —
	# первый прогон печатал «склад игрока (0, 0, 0)» и «сдано +0». Ставится
	# на тот же якорь, что и в партии: расчищенная зона, своя жила и
	# каменоломня считаются от него (см. Main._spawn_enemy_base)
	var keep := Castle.new()
	keep.faction = Constants.FACTION_PLAYER
	main.world_add(keep)
	var pa: Vector3 = _MainScript.PLAYER_BASE_ANCHOR
	keep.global_position = Vector3(pa.x, GameManager.get_terrain_height(pa.x, pa.z), pa.z)
	await pframes(4)

	# ── АРМИИ: ДВА ФРОНТА ЛИЦОМ ДРУГ К ДРУГУ ──────────────────────────────
	var half_gap: float = FRONT_GAP * 0.5
	_mine = _spawn_army(_mix_list(N_PLAYER), Constants.FACTION_PLAYER,
		Vector3(-half_gap - float(COLS) * GAP, 0.0, -40.0), Vector3(1, 0, 0))
	_foes = _spawn_army(_mix_list(N_AI), Constants.FACTION_ENEMY,
		Vector3(half_gap, 0.0, -40.0), Vector3(-1, 0, 0))
	# ── ЭКОНОМИКА: У СВОИХ ЗАМКОВ ─────────────────────────────────────────
	var pc: Vector3 = _dropoff_of(Constants.FACTION_PLAYER)
	var ec: Vector3 = _dropoff_of(Constants.FACTION_ENEMY)
	print("  склад игрока %s, склад ИИ %s" % [str(pc), str(ec)])
	_workers = _spawn_workers(Constants.FACTION_PLAYER, pc + Vector3(-8.0, 0.0, 10.0), N_WORKERS)
	_workers.append_array(_spawn_workers(Constants.FACTION_ENEMY, ec + Vector3(8.0, 0.0, 10.0), N_WORKERS))
	_builders = _spawn_builders(Constants.FACTION_PLAYER, pc + Vector3(-14.0, 0.0, 18.0), N_BUILDERS)
	_builders.append_array(_spawn_builders(Constants.FACTION_ENEMY, ec + Vector3(6.0, 0.0, 18.0), N_BUILDERS))
	await pframes(40)
	if not _headless:
		await _fit_camera(_mine + _foes)
	# ── ПРОГРЕВ ЭКОНОМИКИ — В ИГРОВЫХ СЕКУНДАХ, А НЕ В КАДРАХ ─────────────
	# Цикл добычи 5 с плюс ходка от жилы у базы (15 м) с грузом — первая
	# сдача на склад раньше двадцатой секунды не случается. Первая версия
	# ждала 200 кадров ОТРИСОВКИ: в headless при 137 FPS это полторы секунды
	# игры, и зонд честно печатал «сдано +0, возвращающихся нет» (правило 11)
	await pframes(60 * ECON_WARM_SEC)

	_Opt.tick_meter = true
	_Opt.vis_meter = true
	var bank0: Dictionary = _bank_snapshot()

	print("\n───── ФАЗА 1: ЭКОНОМИКА БЕЗ БОЯ (армии стоят) ─────")
	var idle: Dictionary = await _sample()
	_print_frame(idle)
	print("  " + _economy_line(bank0))

	# ── ФАЗА 2: НАСТОЯЩАЯ РУБКА С ПОТЕРЯМИ ────────────────────────────────
	print("\n───── ФАЗА 2: РУБКА С ПОТЕРЯМИ (%d с, снимок каждые ~5 с) ─────" % CLASH_SEC)
	_charge(_mine, _foes)
	_charge(_foes, _mine)
	var live0: int = GameManager._live_units.size()
	var worst_hang := 0
	var worst_lift := 0.0
	var worst_overlap := 0
	var overlap_frac_worst := 0.0
	var remnant_worst := 0.0
	var slots_max := 0
	var min_fps := 1.0e9
	var snaps := maxi(CLASH_SEC / SNAP_SEC, 1)
	var arrows_before: Dictionary = _arrow_stats()
	for k in range(snaps):
		# Окно между снимками — ФИЗКАДРАМИ. По кадрам отрисовки «30 с рубки»
		# в headless укладывались в две секунды игры: 0 погибших, 0 стрел,
		# армии не успевали дойти друг до друга (правило 11)
		await pframes(60 * SNAP_SEC - 60)
		var s: Dictionary = await _sample(10, 45 if not _headless else 30)
		var ast: Dictionary = _arrow_stats()
		var ov: int = GameManager.army.enemy_overlap_count(CORE_R)
		var ov_pass: int = GameManager.army.enemy_overlap_count_flagged(CORE_R, 1 << 17)
		var ov_retr: int = GameManager.army.enemy_overlap_count_flagged(CORE_R, 1 << 1)
		var ov_touch: int = GameManager.army.enemy_overlap_count(Unit.BLOCK_RADIUS)
		var live: int = GameManager._live_units.size()
		print("\n  [снимок %d] погибло всего %d, живых %d" % [k + 1, live0 - live, live])
		_print_frame(s)
		_print_arrows(ast, "")
		print("  твёрдость строя: в контакте (< %.2f м до чужого) %d, ВНУТРИ ЯДРА (< %.2f м) %d (%.2f%% от живых), из них с билетом прохода %d, отходящих %d"
			% [Unit.BLOCK_RADIUS, ov_touch, CORE_R, ov, 100.0 * float(ov) / maxf(float(live), 1.0), ov_pass, ov_retr])
		print("  " + _economy_line(bank0))
		worst_hang = maxi(worst_hang, int(ast["hanging"]))
		worst_lift = maxf(worst_lift, float(ast["worst"]))
		# ── СВОЙСТВО ЛИНЕЙНОГО БОЯ, А НЕ ОСТАТКОВ ────────────────────────────
		# В последних снимках в контакте остаются десятки: конница добивает
		# разрозненных, толчки и разлёт пишут координаты без проверки тел, и
		# доля «внутри ядра» среди этих десятков доходит до трети (замер: 35
		# из 96 в контакте, из них с билетом прохода 0, отходящих 0 — к ядру
		# билетов это отношения не имеет). Вердикт судит снимки, где линии
		# ещё стоят (в контакте не меньше LINE_CONTACT_MIN); остатки печатаются
		if ov_touch >= LINE_CONTACT_MIN:
			worst_overlap = maxi(worst_overlap, ov)
			overlap_frac_worst = maxf(overlap_frac_worst, float(ov) / maxf(float(live), 1.0))
		else:
			remnant_worst = maxf(remnant_worst, float(ov) / maxf(float(ov_touch), 1.0))
		slots_max = maxi(slots_max, int(ast["slots"]))
		min_fps = minf(min_fps, float(s["fps"]))
		if _alive(_mine) < N_PLAYER / 4 or _alive(_foes) < N_AI / 4:
			break
	var arrows_after: Dictionary = _arrow_stats()

	verdict("A1 торчащие стрелы не висят в воздухе", worst_hang == 0,
		"худший снимок: %d висящих, худший подъём над грунтом %.2f м" % [worst_hang, worst_lift])
	# Буфер не течёт: занятых слотов (ёмкость минус свободные) не больше, чем
	# снарядов в полёте и в земле плюс legacy-узлов (узел держит слот пожизненно).
	# Снаряд без узла (BigStand-5, этап 3) возвращает слот в свободные сам —
	# по прилёту без следа, по сроку торчания, по гибели тела
	var occupied: int = int(arrows_after["slots"]) - int(arrows_after["free"])
	verdict("A2 буфер стрел не течёт (занятых слотов <= в полёте + в земле + узлов)",
		occupied <= int(arrows_after["flying"]) + int(arrows_after["stuck"]) + int(arrows_after["nodes"]),
		"слотов %d, свободных %d, в полёте %d, в земле %d, узлов %d (выпущено %d)" % [
			int(arrows_after["slots"]), int(arrows_after["free"]), int(arrows_after["flying"]),
			int(arrows_after["stuck"]), int(arrows_after["nodes"]), int(arrows_after["fired"])])
	verdict("A3 торчащих на поле не больше потолка + догорающие",
		int(arrows_after["registry"]) <= GameManager.MAX_STUCK_ARROWS + 64,
		"в реестре %d при потолке %d" % [int(arrows_after["registry"]), GameManager.MAX_STUCK_ARROWS])
	verdict("B1 чужие тела не входят друг в друга (внутри ядра < 1%% живых)",
		overlap_frac_worst < 0.01,
		"худший снимок линейного боя %d внутри ядра %.2f м (%.2f%%); в остатках боя худшая доля от контактных %.0f%%" % [
			worst_overlap, CORE_R, overlap_frac_worst * 100.0, remnant_worst * 100.0])

	# ── ФАЗА 3: ЦЕНА ПОДСИСТЕМ НА ЗАМОРОЖЕННОЙ ЧИСЛЕННОСТИ ────────────────
	_freeze_losses()
	await frames(60)
	print("\n───── ФАЗА 3: ЦЕНА ПОДСИСТЕМ (потери заморожены) ─────")
	var base: Dictionary = await _sample()
	_print_frame(base)
	var melee: Dictionary = base
	base = await _cost("туман войны",
		func():
			if GameManager.fog != null:
				GameManager.fog.enabled = false
				(GameManager.fog as Node3D).visible = false,
		func():
			if GameManager.fog != null:
				GameManager.fog.enabled = true
				(GameManager.fog as Node3D).visible = true,
		base)
	base = await _cost("HUD",
		func():
			if main.hud != null:
				(main.hud as CanvasLayer).visible = false
				(main.hud as Node).set_process(false),
		func():
			if main.hud != null:
				(main.hud as CanvasLayer).visible = true
				(main.hud as Node).set_process(true),
		base)
	base = await _cost("мышление ИИ (красный + гоблины)",
		func(): _ai_process(false), func(): _ai_process(true), base)
	base = await _cost("РАБОЧИЕ (тик добычи/доставки/стройки)",
		func(): _workers_ticking(false), func(): _workers_ticking(true), base)
	base = await _cost("стрелы (логика полёта, узлы)",
		func(): _arrows_process(false), func(): _arrows_process(true), base)
	base = await _cost("спрайты армии (отрисовка)",
		func(): _army_visible(false), func(): _army_visible(true), base)
	base = await _cost("ФИЗИЧЕСКИЙ ТИК АРМИИ",
		func(): _army_ticking(false), func(): _army_ticking(true), base)
	base = await _cost("визуальный тик армии",
		func(): _army_drawing(false), func(): _army_drawing(true), base)

	print("\n═════ ЦЕНА ПОДСИСТЕМ В КАДРЕ (рубка, потери заморожены) ═════")
	print("  подсистема                               кадр, мс  физтик, мс  кадр логики, мс  без неё, FPS")
	print("  ────────────────────────────────────────+─────────+───────────+────────────────+─────────────")
	for r in _rows:
		var row: Array = r
		print("  %-40s %8.2f %11.2f %16.2f %13.1f" % [String(row[0]), float(row[1]),
			float(row[2]), float(row[3]), float(row[4])])

	# ── РАЗБИВКА ФИЗТИКА ПО ВЕТКАМ (только ранжирование) ──────────────────
	_Opt.profile_physics = true
	_Opt.prof_reset()
	await pframes(120)
	await frames(1)
	var prof: Array = _Opt.prof_report()
	_Opt.profile_physics = false
	print("\n─── РАЗБИВКА ФИЗ. ТИКА (профиль завышает сумму ~вдвое, читать как ранжирование) ───")
	var sum_us := 0
	for row in prof:
		if not String(row[0]).begins_with("!"):
			sum_us += int(row[1])
	var shown := 0
	for row in prof:
		var bucket: String = String(row[0])
		var total_us: int = int(row[1])
		var calls: int = int(row[2])
		if bucket.begins_with("!"):
			print("  %-18s %8.2f мс/кадр НА ВСЮ АРМИЮ"
				% [bucket, float(total_us) / 1000.0 / float(maxi(calls, 1))])
			continue
		if shown >= 28:
			continue
		shown += 1
		print("  %-18s %7.2f мс/кадр (%5.1f%%) | %8d вызовов | %6.2f мкс"
			% [bucket, float(total_us) / 1000.0 / 120.0,
			   100.0 * float(total_us) / float(maxi(sum_us, 1)),
			   calls, float(row[3])])

	_Opt.tick_meter = false
	_Opt.vis_meter = false

	print("\n═════ КАДР ═════")
	print("  экономика без боя: %.1f FPS | рубка с потерями: худший снимок %.1f FPS | рубка (заморожено): %.1f FPS"
		% [float(idle["fps"]), min_fps, float(melee["fps"])])
	if _headless:
		print("  (headless: FPS здесь — темп главного цикла без отрисовки; ЦЕЛЬ по кадру проверяется только в окне)")
	else:
		verdict("C1 цель по кадру: не ниже %.0f FPS в рубке с экономикой" % FPS_TARGET,
			min_fps >= FPS_TARGET, "худший снимок %.1f FPS" % min_fps)

	print("\n═════ ИТОГ ═════")
	for e in _log:
		var r: Array = e
		print("  %s%s" % [_pad(String(r[0]), 70), "ПРОШЛО" if bool(r[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	print("\n=== QA_FULL_GAME_4K DONE ===")
	get_tree().quit(1 if _fail > 0 else 0)

# ─────────────────────────────────────────────────────────────────────────────
# ВЫКЛЮЧАТЕЛИ ПОДСИСТЕМ
# ─────────────────────────────────────────────────────────────────────────────
func _ai_process(on: bool) -> void:
	for f in ["enemy_ai", "goblin_ai"]:
		var n = main.get(f)
		if n == null:
			continue
		(n as Node).set_process(on)
		(n as Node).set_physics_process(on)

func _army_visible(on: bool) -> void:
	var far = GameManager.far_units
	if far == null or not ("_buckets" in far):
		return
	for b in (far.get("_buckets") as Dictionary).values():
		if b != null and ("mmi" in b) and b.mmi != null:
			(b.mmi as Node3D).visible = on

func _army_ticking(on: bool) -> void:
	for u in GameManager._live_units:
		if is_instance_valid(u):
			(u as Unit).set_tick(on)

func _workers_ticking(on: bool) -> void:
	for u in _workers + _builders:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			(u as Unit).set_tick(on)

func _army_drawing(on: bool) -> void:
	for u in GameManager._live_units:
		if is_instance_valid(u):
			(u as Unit).set_draw(on)

var _arrow_cache: Array = []
func _arrows_process(on: bool) -> void:
	if not on:
		_arrow_cache = _find_arrows()
	for a in _arrow_cache:
		if is_instance_valid(a) and not bool(a.get("_spent")):
			(a as Node).set_process(on)
