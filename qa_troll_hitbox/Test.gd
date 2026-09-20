extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_troll_hitbox — ТРОЛЛЬ: ЗАПАС, СТРЕЛЫ, ОВАЛ, КЛИК (спринт 14)
## ═══════════════════════════════════════════════════════════════════════════
##   A ЗАПАС    — максимум срезан на 20 % против прежнего.
##   B СТРЕЛЫ   — в туше не остаётся НИ ОДНОЙ: гнёзд нет вовсе, путь втыкания
##                в тело отказывает, а торчащие в ЗЕМЛЕ никуда не делись.
##   C ОВАЛ     — обвод рисуется ТОНКИМ 64-сегментным мешем (тем же, что у
##                здания), а не растянутым в четыре раза кольцом бойца; он
##                овальный и примерно обводит основание спрайта. Тени нет.
##   D КЛИК     — НАСТОЯЩИМ лучом мыши: попадает и по кругу у ног, и по
##                туловищу вверх по спрайту; по пустой траве — не попадает.
##   E ПРИЦЕЛ   — стрелы летят в центр массы (живот/грудь), а часть выстрелов
##                намеренно уходит в землю рядом.
##
## Числа берутся у конфига и у самих мешей (правило 10), ожидание — физкадрами
## (правило 11). Запуск: godot --headless --path . res://qa_troll_hitbox/Test.tscn

const _UCfg   := preload("res://scripts/unit_stats_config.gd")
const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")
const _Vis    := preload("res://scripts/units/UnitVisuals.gd")
const _SDR    := preload("res://scripts/SelectionDecalRenderer.gd")

## ЗАПАС ТРОЛЛЯ ДО СПРИНТА 14. Единственное число, записанное здесь прямо:
## требование звучит как «−20 % от того, что было», и выразить его иначе, кроме
## как назвав прежнее значение, нечем. Нынешнее читается из конфига
const HP_BEFORE_S14 := 22680.0

var main = null
var sm   = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []
var _troll: Unit = null
var _arch: Unit  = null

func _ready() -> void:
	call_deferred("_run")
	var t := get_tree().create_timer(300.0)
	t.timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 300 с")
		_finish())

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	_log.append([t, ok])
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + d) if d != "" else ""])

func _finish() -> void:
	print("\n═════ ИТОГ qa_troll_hitbox: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _spawn(uid: String, fac: int, at: Vector3) -> Unit:
	var sc: PackedScene = Building.PRELOAD_SCENES.get(uid)
	if sc == null:
		return null
	var u: Unit = sc.instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x,
		GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	return u

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	# Пень за рекой в партии заморожен (ТЗ 19.09.2026); стенду нужен живой
	GameManager.call_deferred("thaw_lairs_now")
	await frames(8)
	sm = main.selection_manager
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	GameManager.world_bounds_enabled = false
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	await pframes(4)

	# Площадка своя: стенд, зависящий от окружения, обязан задать его сам
	var spot: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(30.0, 0.0, 30.0)
	_troll = _spawn("troll", Constants.FACTION_GOBLIN, spot)
	if _troll == null:
		verdict("A0 тролль поставлен", false, "сцены troll нет в PRELOAD_SCENES")
		_finish()
		return
	await pframes(6)
	# Замораживаем: патруль и обед увезли бы его с площадки замера
	_troll.set_tick(false)

	await _a_hp()
	await _b_arrows()
	await _c_ring()
	await _d_click()
	await _e_aim()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
func _a_hp() -> void:
	print("\n═════ A. ЗАПАС ЖИЗНИ ═════")
	var hp: float = _UCfg.stat("troll", "health", 0.0)
	print("  запас тролля: было %.0f, стало %.0f" % [HP_BEFORE_S14, hp])
	# СПРИНТ 15: поверх −20 % спринта 14 владелец срезал ещё 30 %
	# СПРИНТ 20: ещё −20 % (10 160)
	verdict("A1 запас тролля срезан на 20 % (спринт 14), 30 % (спринт 15) и 20 % (спринт 20)",
		absf(hp - HP_BEFORE_S14 * 0.8 * 0.7 * 0.8) < 1.0,
		"%.0f при ожидаемых %.0f" % [hp, HP_BEFORE_S14 * 0.8 * 0.7 * 0.8])
	verdict("A2 живой тролль поднялся с этим запасом",
		absf(_troll.max_health - hp) < 1.0,
		"максимум у бойца %.0f" % _troll.max_health)

# ═════════════════════════════════════════════════════════════════════════════
func _b_arrows() -> void:
	print("\n═════ B. СТРЕЛЫ НЕ ТОРЧАТ В ТУШЕ ═════")
	verdict("B1 гнёзд под стрелы у тролля нет вовсе", _troll.arrow_sockets() == 0,
		"гнёзд %d" % _troll.arrow_sockets())
	# И САМ ПУТЬ ЗАСТРЕВАНИЯ ОТКАЗЫВАЕТ: базовый stick_arrow отвечает false, то
	# есть стрела не воткнётся в тушу ни при каких условиях
	verdict("B2 попытка воткнуть стрелу в тушу отклоняется",
		not _troll.stick_arrow(null))

	var before_stuck: int = GameManager.stuck_arrow_count()
	_arch = _spawn("archer", Constants.FACTION_PLAYER,
		_troll.global_position + Vector3(-9.0, 0.0, 0.0))
	await pframes(4)
	_arch.set_tick(false)
	var hp0: float = _troll.current_health
	for _i in range(14):
		_arch._on_attack_fired(_troll, _arch.attack_damage)
	# Долетают за пару секунд: ждём ФИЗКАДРАМИ (правило 11)
	await pframes(220)

	# Стрела, застрявшая В ТУШЕ, отличается от воткнувшейся в землю ровно тем,
	# что висит ВЫШЕ грунта. Считаем по реестру торчащих, а не по детям мира:
	# там же лежат стрелы из пула, стоящие где попало
	var on_body := 0
	var tp: Vector3 = _troll.global_position
	# Торчащие — записи ядра (снаряд без узла, этап 3) плюс legacy-узлы
	var pts: Array = []
	for r in GameManager.stuck_arrow_records():
		pts.append(r["pos"])
	for a in GameManager._stuck_arrows:
		if a == null or not is_instance_valid(a):
			continue
		var n3 := a as Node3D
		if n3 != null:
			pts.append(n3.global_position)
	for p in pts:
		var d: float = Vector2(p.x - tp.x, p.z - tp.z).length()
		var lift: float = p.y - GameManager.get_terrain_height(p.x, p.z)
		if d < _troll.pick_radius() + 1.0 and lift > 1.0:
			on_body += 1
	print("  выстрелов 14: запас %.0f → %.0f, торчащих было %d, стало %d, на туше %d" % [
		hp0, _troll.current_health, before_stuck,
		GameManager.stuck_arrow_count(), on_body])
	verdict("B3 на туше не висит ни одной стрелы", on_body == 0,
		"на туше %d" % on_body)
	verdict("B4 урон при этом доходит", _troll.current_health < hp0,
		"запас %.0f → %.0f" % [hp0, _troll.current_health])
	verdict("B5 промахи по-прежнему втыкаются в ЗЕМЛЮ",
		GameManager.stuck_arrow_count() > before_stuck,
		"торчащих %d против %d" % [GameManager.stuck_arrow_count(), before_stuck])

# ═════════════════════════════════════════════════════════════════════════════
func _c_ring() -> void:
	print("\n═════ C. ТОНКИЙ ОВАЛ ВМЕСТО ТОЛСТЫХ ДУГ ═════")
	verdict("C1 тролль просит ТОНКИЙ обвод, пехота — обычное кольцо",
		_SDR.wants_fine_ring(_troll) and not _SDR.wants_fine_ring(_arch),
		"тролль=%s, лучник=%s" % [str(_SDR.wants_fine_ring(_troll)),
			str(_SDR.wants_fine_ring(_arch))])
	# ТОНКИЙ МЕШ — ТОТ ЖЕ, ЧТО У ЗДАНИЯ: 64 сегмента против двенадцати у кольца
	# бойца. Именно двенадцать, растянутые в 4.2 раза, и давали «толстые кривые
	# красные дуги» со скриншота владельца
	var fine: TorusMesh = _Vis.building_ring_mesh()
	var coarse: TorusMesh = _Vis.hover_ring_mesh()
	print("  сегментов: тонкий меш %d, кольцо бойца %d" % [fine.rings, coarse.rings])
	verdict("C2 тонкий меш заметно глаже кольца бойца",
		fine.rings >= coarse.rings * 4,
		"%d против %d" % [fine.rings, coarse.rings])
	# ТОЛЩИНА ТРУБКИ ПОСЛЕ МАСШТАБА. У тонкого меша радиус единичный, поэтому
	# масштаб равен радиусу в метрах, а трубка остаётся своей
	var fine_tube: float = (fine.outer_radius - fine.inner_radius) * _SDR.fine_ring_scale(_troll)
	var coarse_tube: float = (coarse.outer_radius - coarse.inner_radius) * _troll.ring_scale()
	print("  толщина обвода: тонкий %.3f м, прежний растянутый %.3f м" % [
		fine_tube, coarse_tube])
	verdict("C3 обвод стал ТОНКИМ, а не растянутой трубой",
		fine_tube < coarse_tube * 0.5,
		"%.3f против %.3f м" % [fine_tube, coarse_tube])
	verdict("C4 обвод овальный, а не круг",
		_SDR.fine_ring_oval(_troll) != Vector2.ONE,
		str(_SDR.fine_ring_oval(_troll)))
	verdict("C5 радиус обвода примерно обводит основание спрайта",
		_troll.fine_ring_radius() > _troll.pick_radius() * 0.7
			and _troll.fine_ring_radius() < _troll.pick_radius() * 1.6,
		"радиус %.2f м при круге у ног %.2f м" % [_troll.fine_ring_radius(),
			_troll.pick_radius()])
	verdict("C6 тени под троллем нет вовсе",
		absf(_troll.shadow_scale()) < 0.0001,
		"тень %.3f" % _troll.shadow_scale())

# ═════════════════════════════════════════════════════════════════════════════
# D. КЛИК — НАСТОЯЩИМ ЛУЧОМ МЫШИ ЧЕРЕЗ SelectionManager._pick_at
#
# ЛОВУШКИ (все записаны в CLAUDE.md и все ловили раньше): камеру заморозить,
# экранную точку считать В ТОМ ЖЕ КАДРЕ, что и разбор, площадку очистить самим
# стендом — иначе клик заберёт случайного соседа
# ═════════════════════════════════════════════════════════════════════════════
func _d_click() -> void:
	print("\n═════ D. КЛИК ПО ТУЛОВИЩУ И ПО ОВАЛУ ═════")
	var cam: Camera3D = main.get("_camera") as Camera3D
	if cam == null:
		verdict("D0 камера есть", false)
		return
	# Лучник рядом перехватывал бы клик по ногам тролля — убираем с площадки
	if _arch != null and is_instance_valid(_arch):
		_arch.global_position += Vector3(0.0, 0.0, 40.0)
		_arch.sync_row()
	main.focus_camera_on(_troll.global_position)
	await pframes(8)
	await frames(4)
	main.set_process(false)
	cam.set_process(false)
	await frames(2)

	var mask: int = Constants.LAYER_UNITS | Constants.LAYER_BUILDINGS
	var tp: Vector3 = _troll.global_position
	# ── У НОГ (там же лежит красный овал) ──────────────────────────────────
	var scr_feet: Vector2 = cam.unproject_position(tp + Vector3(0.0, 0.05, 0.0))
	var hit_feet = sm._pick_at(scr_feet, mask).get("target")
	# ── ПО ТУЛОВИЩУ: середина рисунка, туда и целится игрок ────────────────
	var body: Vector3 = tp + Vector3(0.0, _troll.pick_body_h(), 0.0)
	var scr_body: Vector2 = cam.unproject_position(body)
	var hit_body = sm._pick_at(scr_body, mask).get("target")
	# ── ЗАВЕДОМО МИМО: пустая трава сбоку ─────────────────────────────────
	var grass: Vector3 = tp + Vector3(_troll.pick_radius() * 4.0 + 10.0, 0.0, 0.0)
	grass.y = GameManager.get_terrain_height(grass.x, grass.z)
	var scr_far: Vector2 = cam.unproject_position(grass)
	var hit_far = sm._pick_at(scr_far, mask).get("target")

	print("  ноги: %s | туловище (+%.1f м): %s | трава в %.0f м: %s" % [
		str(hit_feet == _troll), _troll.pick_body_h(), str(hit_body == _troll),
		_troll.pick_radius() * 4.0 + 10.0, str(hit_far)])
	verdict("D1 клик у ног (по красному овалу) берёт тролля", hit_feet == _troll)
	verdict("D2 клик ПО ТУЛОВИЩУ берёт тролля", hit_body == _troll)
	verdict("D3 клик по пустой траве тролля не берёт", hit_far != _troll,
		"под курсором %s" % str(hit_far))
	main.set_process(true)
	cam.set_process(true)

# ═════════════════════════════════════════════════════════════════════════════
func _e_aim() -> void:
	print("\n═════ E. ПРИЦЕЛ В ЦЕНТР МАССЫ ═════")
	verdict("E1 стрелок целится в тушу, а не в ступни",
		_troll.aim_height() > 1.5,
		"высота прицела %.2f м" % _troll.aim_height())
	verdict("E2 прицел — примерно середина рисунка (живот/грудь)",
		absf(_troll.aim_height() - _troll.pick_body_h()) < 1.0,
		"прицел %.2f м при середине рисунка %.2f м" % [_troll.aim_height(),
			_troll.pick_body_h()])
	verdict("E3 у крупной цели есть доля промахов В ЗЕМЛЮ",
		_troll.aim_miss_chance() > 0.0 and _troll.aim_miss_spread() > 0.0,
		"доля %.2f, разброс %.1f м" % [_troll.aim_miss_chance(),
			_troll.aim_miss_spread()])
	verdict("E4 у пехоты этой дисперсии нет вовсе",
		absf(_arch.aim_miss_chance()) < 0.0001)
