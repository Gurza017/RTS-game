extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_monk_vfx — VFX ЛЕЧЕНИЯ МОНАХА НА ИСЦЕЛЯЕМОМ
## ═══════════════════════════════════════════════════════════════════════════
## Заказ владельца: пока Монах поддерживает лечение, поверх ЦЕЛИ проигрывается
## зацикленный эффект из `Heal_Effect.png`; эффект держится всё время лечения;
## как только лечение прекращается (цель вылечена, монах переключился на
## другую, монах погиб или отошёл) — VFX мгновенно снимается с юнита.
##
##   A ЛЕНТА     — файл на месте, кадры выводятся из пропорций листа, квад
##                 строится с этой лентой и рисуется поверх бойца.
##   B СПАВН     — начал лечить → эффект появился И ПРИВЯЗАН К ЦЕЛИ.
##   C ПРИВЯЗКА  — цель идёт, эффект едет за ней: держится у центра массы, а
##                 не остаётся висеть там, где лечение началось.
##   D НЕПРЕРЫВНОСТЬ — между тактами лечения эффект не мигает.
##   E СНЯТИЕ    — четыре причины прекращения, каждая проверяется отдельно:
##                 цель вылечена, монах переключился на другую, монах отошёл,
##                 монах погиб. Плюс уход монаха со сцены освобождает узел.
##
## Числа — из конфига и самой ленты (правило 10), ожидание — физкадрами
## (правило 11). Запуск: godot --headless --path . res://qa_monk_vfx/Test.tscn

const _UCfg := preload("res://scripts/unit_stats_config.gd")

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

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
	print("\n═════ ИТОГ qa_monk_vfx: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _spawn(uid: String, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[uid].instantiate()
	u.faction = Constants.FACTION_PLAYER
	main.world_add(u)
	u.global_position = Vector3(at.x,
		GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	return u

## Раненый боец: лечить целого монах не станет вовсе
func _wounded(at: Vector3, frac: float) -> Unit:
	var u: Unit = _spawn("spearman", at)
	u.current_health = u.max_health * frac
	u._soa_push_stats()
	return u

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	GameManager.world_bounds_enabled = false
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	await pframes(4)

	await _a_sheet()
	await _b_spawn()
	await _c_follow()
	await _d_continuous()
	await _e_stop()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
# A. ЛЕНТА ЭФФЕКТА
# ═════════════════════════════════════════════════════════════════════════════
func _a_sheet() -> void:
	print("\n═════ A. ЛЕНТА heal effect ═════")
	var folder: String = GameManager.unit_sprite_folder(
		Constants.FACTION_PLAYER, "monk")
	var path: String = folder + "/Heal_Effect.png"
	var own: bool = not folder.is_empty() and ResourceLoader.exists(path)
	if not own:
		path = Monk.HEAL_VFX_FALLBACK
	print("  лента: %s (своя у цветовой папки: %s)" % [path, str(own)])
	verdict("A1 лента эффекта лежит на месте и грузится",
		ResourceLoader.exists(path), path)
	var tex := load(path) as Texture2D
	verdict("A2 это картинка", tex != null)
	if tex == null:
		return
	var sz: Vector2 = tex.get_size()
	var frames_n: float = maxf(round(sz.x / maxf(sz.y, 1.0)), 1.0)
	print("  лист %d×%d → кадров %d" % [int(sz.x), int(sz.y), int(frames_n)])
	verdict("A3 лист горизонтальный и режется на несколько кадров",
		sz.x > sz.y and frames_n >= 2.0,
		"%d кадров при листе %d×%d" % [int(frames_n), int(sz.x), int(sz.y)])

# ═════════════════════════════════════════════════════════════════════════════
# B. НАЧАЛ ЛЕЧИТЬ — ЭФФЕКТ ПОЯВИЛСЯ НА ЦЕЛИ
# ═════════════════════════════════════════════════════════════════════════════
var _monk: Monk = null
var _hurt: Unit = null

func _b_spawn() -> void:
	print("\n═════ B. СПАВН ЭФФЕКТА ═════")
	var spot: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(30.0, 0.0, 30.0)
	_monk = _spawn("monk", spot) as Monk
	await pframes(4)
	verdict("B1 до лечения эффекта нет ни на ком",
		_monk.heal_vfx_target() == null)
	_hurt = _wounded(spot + Vector3(4.0, 0.0, 0.0), 0.3)
	await pframes(4)
	# Раненый заморожен: здесь меряется ЭФФЕКТ, а не то, куда боец ушёл
	_hurt.set_tick(false)
	# Такт лечения редкий (MONK_HEAL_TICK), ждём с запасом
	await pframes(int(_UCfg.MONK_HEAL_TICK * 3.0 * 60.0))
	print("  цель лечения %s, эффект на %s" % [
		str(_monk.heal_target == _hurt), str(_monk.heal_vfx_target() == _hurt)])
	verdict("B2 монах взял раненого в лечение", _monk.heal_target == _hurt)
	verdict("B3 эффект появился и привязан ИМЕННО К ЦЕЛИ",
		_monk.heal_vfx_target() == _hurt)
	var vfx: Node3D = _monk.heal_vfx_node()
	verdict("B4 узел эффекта заведён и виден",
		vfx != null and bool(vfx.get("visible")))
	if vfx != null:
		var mi := vfx as MeshInstance3D
		var q: QuadMesh = mi.mesh as QuadMesh
		var mat: ShaderMaterial = q.material as ShaderMaterial if q != null else null
		verdict("B5 это квад с лентой эффекта, а не пустышка",
			q != null and mat != null
				and mat.get_shader_parameter("albedo_tex") != null,
			"квад %s" % (str(q.size) if q != null else "нет"))
		if mat != null:
			print("  кадров в материале %s, приоритет отрисовки %d" % [
				str(mat.get_shader_parameter("frame_count")), mat.render_priority])
			verdict("B6 лента зациклена по кадрам, а не показывает один кадр",
				float(mat.get_shader_parameter("frame_count")) >= 2.0,
				"кадров %s" % str(mat.get_shader_parameter("frame_count")))
			verdict("B7 рисуется ПОВЕРХ бойца, а не под ним",
				mat.render_priority > 0,
				"приоритет %d" % mat.render_priority)
		# ── ВИСИТ НА ЦЕЛИ, А НЕ НА МОНАХЕ ──────────────────────────────────
		var d_t: float = Vector2(vfx.global_position.x - _hurt.global_position.x,
			vfx.global_position.z - _hurt.global_position.z).length()
		var d_m: float = Vector2(vfx.global_position.x - _monk.global_position.x,
			vfx.global_position.z - _monk.global_position.z).length()
		print("  эффект в %.2f м от цели и в %.2f м от монаха" % [d_t, d_m])
		verdict("B8 эффект стоит НА ИСЦЕЛЯЕМОМ, а не на монахе",
			d_t < 0.3 and d_t < d_m, "%.2f против %.2f м" % [d_t, d_m])
		verdict("B9 и поднят к центру массы цели, а не лежит в ногах",
			absf(vfx.global_position.y - (_hurt.draw_position().y
				+ _hurt.aim_height())) < 0.2,
			"высота %.2f при центре массы %.2f" % [vfx.global_position.y,
				_hurt.draw_position().y + _hurt.aim_height()])

# ═════════════════════════════════════════════════════════════════════════════
# C. ЕДЕТ ЗА ЦЕЛЬЮ
#
# ПРЕЖНЯЯ ВЕРСИЯ СТАВИЛА ТОЧКУ РАЗ В ТАКТ, и уходящий раненый оставлял эффект
# висеть за спиной. Здесь цель двигается ВРУЧНУЮ, чтобы замер не зависел от
# того, куда её поведёт автомат
# ═════════════════════════════════════════════════════════════════════════════
func _c_follow() -> void:
	print("\n═════ C. ЭФФЕКТ ЕДЕТ ЗА ЦЕЛЬЮ ═════")
	var vfx: Node3D = _monk.heal_vfx_node()
	if vfx == null or _hurt == null or not is_instance_valid(_hurt):
		verdict("C0 эффект и цель на месте", false)
		return
	var worst := 0.0
	for i in range(90):
		# Двигаем раненого мелкими шагами, оставаясь в радиусе лечения
		var p: Vector3 = _hurt.global_position + Vector3(0.0, 0.0, 0.06)
		_hurt.global_position = Vector3(p.x,
			GameManager.get_terrain_height(p.x, p.z), p.z)
		_hurt.sync_row()
		# Раненого лечат — не даём ему вылечиться до конца замера
		_hurt.current_health = _hurt.max_health * 0.3
		await get_tree().physics_frame
		if i < 10:
			continue
		worst = maxf(worst, Vector2(
			vfx.global_position.x - _hurt.draw_position().x,
			vfx.global_position.z - _hurt.draw_position().z).length())
	print("  цель прошла %.2f м, худший отрыв эффекта %.2f м" % [90.0 * 0.06, worst])
	verdict("C1 эффект держится на цели всю дорогу", worst < 0.35,
		"худший отрыв %.2f м" % worst)

# ═════════════════════════════════════════════════════════════════════════════
# D. НЕПРЕРЫВНОСТЬ МЕЖДУ ТАКТАМИ
# ═════════════════════════════════════════════════════════════════════════════
func _d_continuous() -> void:
	print("\n═════ D. ЭФФЕКТ НЕ МИГАЕТ МЕЖДУ ТАКТАМИ ═════")
	if _hurt == null or not is_instance_valid(_hurt):
		verdict("D0 цель на месте", false)
		return
	var off := 0
	var total := 0
	# Пять тактов лечения подряд: между ними эффект обязан гореть непрерывно
	for _i in range(int(_UCfg.MONK_HEAL_TICK * 5.0 * 60.0)):
		_hurt.current_health = _hurt.max_health * 0.3
		await get_tree().physics_frame
		total += 1
		if _monk.heal_vfx_target() != _hurt:
			off += 1
	print("  кадров под лечением %d, из них без эффекта %d" % [total, off])
	verdict("D1 эффект горит непрерывно всё время лечения", off == 0,
		"погас на %d кадрах из %d" % [off, total])

# ═════════════════════════════════════════════════════════════════════════════
# E. СНЯТИЕ: ЧЕТЫРЕ ПРИЧИНЫ
# ═════════════════════════════════════════════════════════════════════════════
func _e_stop() -> void:
	print("\n═════ E. СНЯТИЕ ЭФФЕКТА ═════")
	# ── E1. ЦЕЛЬ ВЫЛЕЧЕНА ──────────────────────────────────────────────────
	if _hurt != null and is_instance_valid(_hurt):
		_hurt.current_health = _hurt.max_health
		_hurt._soa_push_stats()
		await pframes(6)
		print("  после полного исцеления эффект на %s" % str(_monk.heal_vfx_target()))
		verdict("E1 цель вылечена — эффект снят",
			_monk.heal_vfx_target() == null,
			"висит на %s" % str(_monk.heal_vfx_target()))
		var vfx: Node3D = _monk.heal_vfx_node()
		verdict("E1б и квад невидим",
			vfx == null or not bool(vfx.get("visible")))

	# ── E2. ПЕРЕКЛЮЧЕНИЕ НА ДРУГУЮ ЦЕЛЬ ────────────────────────────────────
	var spot: Vector3 = _monk.global_position
	var a: Unit = _wounded(spot + Vector3(3.0, 0.0, 2.0), 0.2)
	await pframes(4)
	a.set_tick(false)
	await pframes(int(_UCfg.MONK_HEAL_TICK * 3.0 * 60.0))
	var on_a: bool = _monk.heal_vfx_target() == a
	# Второй, РАНЕНЫЙ СИЛЬНЕЕ: монах лечит самого раненого, значит переключится
	var b: Unit = _wounded(spot + Vector3(-3.0, 0.0, 2.0), 0.05)
	await pframes(4)
	b.set_tick(false)
	await pframes(int(_UCfg.MONK_HEAL_TICK * 3.0 * 60.0))
	var on_b: bool = _monk.heal_vfx_target() == b
	print("  был на первом: %s, переехал на второго: %s" % [str(on_a), str(on_b)])
	verdict("E2 эффект был на первой цели", on_a)
	verdict("E3 монах переключился — эффект переехал на новую цель и только на неё",
		on_b and _monk.heal_vfx_target() != a,
		"висит на %s" % ("втором" if on_b else "не на втором"))
	# Узел при этом ОДИН: эффект переиспользуется, а не плодит квады
	var vfx_nodes := 0
	for c in main.world_root().get_children():
		if (c as Node).name.begins_with("HealVFX"):
			vfx_nodes += 1
	verdict("E4 квад эффекта один, а не по узлу на такт лечения",
		vfx_nodes == 1, "узлов %d" % vfx_nodes)

	# ── E5. МОНАХ ОТОШЁЛ ───────────────────────────────────────────────────
	var far: Vector3 = spot + Vector3(_UCfg.MONK_HEAL_RADIUS * 3.0, 0.0, 0.0)
	_monk.global_position = Vector3(far.x,
		GameManager.get_terrain_height(far.x, far.z), far.z)
	_monk.sync_row()
	await pframes(10)
	print("  монах отошёл на %.0f м при радиусе лечения %.0f м, эффект на %s" % [
		_monk.global_position.distance_to(b.global_position),
		_UCfg.MONK_HEAL_RADIUS, str(_monk.heal_vfx_target())])
	verdict("E5 монах отошёл дальше радиуса — эффект снят",
		_monk.heal_vfx_target() == null,
		"висит на %s" % str(_monk.heal_vfx_target()))

	# ── E6. МОНАХ ПОГИБ ────────────────────────────────────────────────────
	_monk.global_position = Vector3(spot.x, spot.y, spot.z)
	_monk.sync_row()
	await pframes(int(_UCfg.MONK_HEAL_TICK * 3.0 * 60.0))
	verdict("E6 вернулся — эффект снова на раненом",
		_monk.heal_vfx_target() != null,
		"висит на %s" % str(_monk.heal_vfx_target()))
	# ── СПРАШИВАТЬ НАДО У УЗЛА ЭФФЕКТА, А НЕ У ПОКОЙНИКА ───────────────────
	# Первая версия звала heal_vfx_target() ПОСЛЕ гибели монаха: узел к тому
	# моменту освобождён, и вызов бросал исключение — а исключение внутри
	# корутины стенда убивает её МОЛЧА, оставляя «провалов: 0» при двух
	# непроверенных вердиктах. Ссылку на квад берём заранее и судим по нему
	var vfx_node: Node3D = _monk.heal_vfx_node()
	verdict("E7а квад эффекта перед гибелью монаха горит",
		vfx_node != null and bool(vfx_node.get("visible")))
	_monk.take_damage(_monk.max_health * 10.0, null)
	await pframes(2)
	var still_on: bool = vfx_node != null and is_instance_valid(vfx_node) 		and bool(vfx_node.get("visible"))
	verdict("E7 монах погиб — эффект снят в тот же кадр", not still_on,
		"квад %s" % ("ещё горит" if still_on else "погашен"))
	# Узел уходит со сцены вместе с монахом: он лежит в МИРЕ и сам бы не исчез
	await pframes(20)
	var left := 0
	for c in main.world_root().get_children():
		if is_instance_valid(c) and not (c as Node).is_queued_for_deletion() \
				and (c as Node).name.begins_with("HealVFX"):
			left += 1
	verdict("E8 и узел эффекта освобождён, а не висит над полем",
		left == 0, "осталось узлов %d" % left)
	for u in [a, b]:
		if u != null and is_instance_valid(u) and not u.is_dead():
			u.take_damage(u.max_health * 10.0, null)
	await pframes(4)
