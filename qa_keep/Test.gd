extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ВОРОТА КРЕПОСТИ, ГАРНИЗОН И КЛИК ПО ЗДАНИЮ
## ═══════════════════════════════════════════════════════════════════════════
## Три жалобы владельца по скриншотам, у всех трёх разные причины:
##
##   A ВОРОТА — точка входа/выхода это НАСТОЯЩИЙ УЗЕЛ у дверей, а не формула,
##     и лежит она перед основанием рисунка, по его середине.
##   B ВХОД В ЗАМОК — боец исчезает У ДВЕРЕЙ, а не за пять метров до них, и
##     заходит весь отряд, а не голова очереди.
##   C КОЛЬЦА — вошедший внутрь снимает с себя ВСЁ, что рисуется над ним.
##     Кольцо ездит по НАРИСОВАННОЙ точке, а она у снятого с визуального тика
##     бойца замерзает навсегда: «жёлтые колечки кучей в пустом поле».
##   D КЛИК — курсор на картинке замка выбирает замок, даже когда за зданием
##     стоит рабочий; но боец ПЕРЕД стеной по-прежнему важнее здания.
##   E ПОЛОСЫ ВЫХОДА — одиночный наём в пустом поле выходит У ВОРОТ, а не
##     через полторы полосы вбок; одновременные заказы по-прежнему расходятся.
##
## Числа не хардкодятся: всё меряется у самих текстур, констант и конфига.
##
## Запуск: godot --headless --path . res://qa_keep/Test.tscn

const _BBUtil := preload("res://scripts/BillboardUtil.gd")
const _UCfg   := preload("res://scripts/unit_stats_config.gd")

var main = null
var sm   = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

## ЖДЁМ ФИЗИЧЕСКИЕ КАДРЫ, А НЕ КАДРЫ ОТРИСОВКИ (правило 11 в CLAUDE.md):
## при снятом ограничении кадров отрисовка обгоняет физику, и «подождать, пока
## дойдёт» по process_frame меряет не то
func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	_log.append([t, ok])
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + d) if d != "" else ""])

func _pad(s: String, n: int) -> String:
	var o := s
	while o.length() < n: o += " "
	return o

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	sm = main.selection_manager
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	GameManager.world_bounds_enabled = false
	if GameManager.fog != null:
		GameManager.fog.enabled = false
		GameManager.fog = null
	await frames(4)

	var keep := Castle.new()
	keep.faction = Constants.FACTION_PLAYER
	main.world_add(keep)
	keep.global_position = Vector3(-90.0,
		GameManager.get_terrain_height(-90.0, 90.0), 90.0)
	await pframes(6)

	# ── ВОРОТА ПРОВЕРЯЕМ У ВСЕХ, КТО ВЫПУСКАЕТ ИЛИ ПРИНИМАЕТ ЮНИТОВ ─────────
	# Гарнизон есть у Замка и у Хижины гоблинов (она его и наследует), выпуск —
	# ещё и у Бараков. Считают все они одним кодом (Building._face_front), но
	# рисунки у них разные, а вся геометрия ворот выводится из рисунка
	_check_gate(keep, "замок")
	var hut = load("res://scripts/goblin/GoblinHut.gd").new()
	hut.faction = Constants.FACTION_GOBLIN
	main.world_add(hut)
	hut.global_position = Vector3(-60.0, GameManager.get_terrain_height(-60.0, 90.0), 90.0)
	await pframes(4)
	_check_gate(hut, "хижина")
	hut.queue_free()
	var yard = load("res://scripts/Barracks.gd").new()
	yard.faction = Constants.FACTION_PLAYER
	main.world_add(yard)
	yard.global_position = Vector3(-120.0, GameManager.get_terrain_height(-120.0, 90.0), 90.0)
	await pframes(4)
	_check_gate(yard, "бараки")
	yard.queue_free()
	await pframes(2)

	await _check_click(keep)
	await _check_garrison(keep)
	await _check_lanes(keep)

	print("\n═════ ИТОГ ═════")
	for e in _log:
		var r: Array = e
		print("  %s%s" % [_pad(String(r[0]), 68), "ПРОШЛО" if bool(r[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	print("\n=== KEEP TEST DONE ===")
	get_tree().quit(1 if _fail > 0 else 0)

# ═════════════════════════════════════════════════════════════════════════════
# A. ВОРОТА
# ═════════════════════════════════════════════════════════════════════════════
func _check_gate(b: Building, nm: String) -> void:
	print("\n═════ A. ВОРОТА: %s ═════" % nm.to_upper())
	var node: Node3D = b.get_node_or_null(Building.SPAWN_POINT_NAME) as Node3D
	verdict("A1 %s: ворота — настоящий узел в дереве постройки" % nm, node != null,
		"ищем '%s'" % Building.SPAWN_POINT_NAME)
	if node == null:
		return
	var gate: Vector3 = b._gate_position()
	verdict("A2 %s: спавн берётся У УЗЛА, а не складывается формулой" % nm,
		gate.distance_to(node.global_position) < 0.001,
		"_gate_position %s, узел %s" % [str(gate), str(node.global_position)])

	# ── ВОРОТА ПЕРЕД ДВЕРЬМИ, А НЕ ЗА КРУГОМ ────────────────────────────────
	# «Перед дверьми» для билборда — это передний край НАРИСОВАННОГО основания:
	# ровно тот круг, который игра сама и рисует под зданием (ring_radius).
	# Дальше него ворота уезжают в пустую траву, ближе — внутрь дома
	var dz: float = (gate - b.global_position).dot(b.facade_dir())
	verdict("A3 %s: ворота вынесены вперёд по фасаду, а не вбок и не назад" % nm,
		dz > 0.0 and absf((gate - b.ring_center()).x) < 0.05,
		"вынос %.2f м, отклонение по X %.3f м" % [
			dz, (gate - b.ring_center()).x])
	# Спринт 19: вынос ворот ограничен GATE_MAX_DEPTH («~3 м от стенки»)
	verdict("A4 %s: ворота стоят у края рисунка, а не в поле за ним" % nm,
		dz <= b.ring_radius() + Building.GATE_CLEARANCE + 0.01
		and dz >= minf(minf(b.ring_radius(), b.build_size.z * 0.5), Building.GATE_MAX_DEPTH) - 0.01,
		"вынос %.2f м при радиусе рисунка %.2f м и зазоре %.2f" % [
			dz, b.ring_radius(), Building.GATE_CLEARANCE])
	# СЕРЕДИНА ВОРОТ — СЕРЕДИНА РИСУНКА, а не начало координат: непрозрачная
	# часть кадра нередко смещена внутри самого кадра (см. Building._face_front)
	verdict("A5 %s: ворота против середины рисунка, а не против нуля" % nm,
		absf((gate.x - b.global_position.x) - b._draw_cx) < 0.001,
		"сдвиг ворот %.3f м, середина рисунка %.3f м" % [
			gate.x - b.global_position.x, b._draw_cx])

	# ── ЗОНА КЛИКА НАКРЫВАЕТ ВЕСЬ РИСУНОК, А НЕ ТОЛЬКО ФУНДАМЕНТ ────────────
	# Прямое требование заказа. Пластина подгоняется под непрозрачную часть
	# кадра (Building._fit_pick_to_sprite), а меряем мы её той же функцией
	# обмера, какой режет шейдер (BillboardUtil.opaque_rect) — иначе проверка
	# судила бы о картинке, которой на экране нет (разбор — в CLAUDE.md,
	# «Обмер спрайта обязан резать по тому же порогу, что и шейдер»)
	var shape: CollisionShape3D = null
	for c in b.get_children():
		var cs := c as CollisionShape3D
		if cs != null and cs.shape is BoxShape3D:
			shape = cs
			break
	verdict("A6 %s: у постройки есть форма попадания для луча мыши" % nm,
		shape != null and b.collision_layer == Constants.LAYER_BUILDINGS,
		"слой %d при LAYER_BUILDINGS %d" % [b.collision_layer,
			Constants.LAYER_BUILDINGS])
	if shape == null:
		return
	var box: BoxShape3D = shape.shape as BoxShape3D
	var lo: float = shape.position.y - box.size.y * 0.5
	var hi: float = shape.position.y + box.size.y * 0.5
	var top: float = _drawn_top(b)
	verdict("A7 %s: зона клика накрывает ВЕСЬ рисунок, а не фундамент" % nm,
		lo <= b._draw_base_y + 0.01 and hi >= top - 0.01
		and box.size.x >= b._draw_half_w * 2.0 - 0.01,
		"пластина %.2f…%.2f м при рисунке %.2f…%.2f м, ширина %.2f при %.2f" % [
			lo, hi, b._draw_base_y, top, box.size.x, b._draw_half_w * 2.0])

# ═════════════════════════════════════════════════════════════════════════════
# D. КЛИК ПО ЗДАНИЮ (идёт раньше гарнизона: тот уводит бойцов с карты)
# ═════════════════════════════════════════════════════════════════════════════
func _check_click(b: Building) -> void:
	print("\n═════ D. КЛИК ═════")
	var cam: Camera3D = main.get("_camera") as Camera3D
	main.focus_camera_on(b.global_position)
	await pframes(8)
	await frames(4)
	var top: float = _drawn_top(b)
	# Целимся в ВЕРХНЮЮ часть картинки — туда, где луч уходит выше коробки
	var aim: Vector3 = b.global_position + Vector3(b._draw_cx,
		b._draw_base_y + (top - b._draw_base_y) * 0.78, 0.0)
	var scr: Vector2 = cam.unproject_position(aim)
	var ground: Vector3 = _ground_under(cam, scr)
	var away: float = Vector2(ground.x - b.global_position.x,
		ground.z - b.global_position.z).length()
	verdict("D0 точка земли под курсором и правда уходит ЗА здание",
		away > maxf(b.build_size.x, b.build_size.z) * 0.5,
		"%.2f м при полугабарите коробки %.2f м" % [
			away, maxf(b.build_size.x, b.build_size.z) * 0.5])

	# ── РАБОЧИЙ РОВНО В ТОЧКЕ ЗЕМЛИ ПОД КУРСОРОМ ────────────────────────────
	# Это и есть жалоба: игрок целится в стену, а клик забирает крестьянина,
	# которого сам же замок и загораживает
	var behind: Unit = _spawn_worker(ground)
	await pframes(4)
	scr = cam.unproject_position(aim)
	var hit = sm._pick_at(scr,
		Constants.LAYER_UNITS | Constants.LAYER_BUILDINGS).get("target")
	verdict("D1 курсор на картинке: замок важнее бойца ЗА зданием", hit == b,
		"под курсором %s (рабочий в %.1f м за замком)" % [
			("ЗАМОК" if hit == b else ("РАБОЧИЙ" if hit == behind else str(hit))),
			away])
	_kill(behind)
	await pframes(2)

	# ── А ВОТ БОЕЦ ПЕРЕД СТЕНОЙ ПО-ПРЕЖНЕМУ ВАЖНЕЕ ЗДАНИЯ ───────────────────
	# Правило «боец важнее» отменять нельзя: масок столкновений в проекте нет,
	# бойцы свободно стоят на габарите построек, и клик по бойцу у стены обязан
	# выбрать бойца. Целимся в ЕГО туловище, а не в стену
	var front_pos: Vector3 = b.global_position + b.facade_dir() * 0.5
	front_pos.y = GameManager.get_terrain_height(front_pos.x, front_pos.z)
	var front: Unit = _spawn_worker(front_pos)
	await pframes(4)
	var body: Vector3 = front.global_position + Vector3(0.0, 1.0, 0.0)
	var scr2: Vector2 = cam.unproject_position(body)
	var hit2 = sm._pick_at(scr2,
		Constants.LAYER_UNITS | Constants.LAYER_BUILDINGS).get("target")
	verdict("D2 боец ПЕРЕД стеной по-прежнему важнее здания", hit2 == front,
		"под курсором %s" % ("РАБОЧИЙ" if hit2 == front
			else ("ЗАМОК" if hit2 == b else str(hit2))))
	_kill(front)
	await pframes(2)

	# ── КЛИК ПО ПУСТОЙ ТРАВЕ ПЕРЕД ЗДАНИЕМ ЗДАНИЕМ НЕ СЧИТАЕТСЯ ─────────────
	# Обратная страховка: раздутый допуск сделал бы замок «жирной» целью и он
	# начал бы перехватывать клики по земле у своих стен
	var grass: Vector3 = b.global_position + b.facade_dir() * (b.ring_radius() + 6.0)
	grass.y = GameManager.get_terrain_height(grass.x, grass.z)
	var scr3: Vector2 = cam.unproject_position(grass)
	var hit3 = sm._pick_at(scr3,
		Constants.LAYER_UNITS | Constants.LAYER_BUILDINGS).get("target")
	verdict("D3 клик по траве перед зданием зданием не считается", hit3 != b,
		"под курсором %s" % str(hit3))

# ═════════════════════════════════════════════════════════════════════════════
# B и C. ГАРНИЗОН
# ═════════════════════════════════════════════════════════════════════════════
func _check_garrison(keep: Castle) -> void:
	print("\n═════ B и C. ГАРНИЗОН ═════")
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
	var men: Array = []
	# Двадцать человек — не шесть: тугой радиус входа обязан выдержать ОЧЕРЕДЬ,
	# а на шестерых очереди не возникает вовсе
	for i in range(20):
		var u: Unit = load("res://scenes/units/Spearman.tscn").instantiate()
		u.faction = Constants.FACTION_PLAYER
		main.world_add(u)
		var off := Vector3(float(i % 5) * 0.7 - 1.4, 0.0, 14.0 + float(i / 5) * 0.7)
		u.global_position = keep.global_position + off
		u.sync_row()
		GameManager.add_to_squad(sid, u)
		u.set_selected(true)
		sm.selected_units.append(u)
		men.append(u)
	sm._sel_rebuild()
	await pframes(4)
	var rings0: int = GameManager.sel_decals.registered_count()
	verdict("C0 до входа кольца у всех выделенных есть", rings0 >= men.size(),
		"колец %d при %d выделенных" % [rings0, men.size()])

	var gate: Vector3 = keep._gate_position()
	keep.request_garrison(sid)
	# ТОЧКУ ИСЧЕЗНОВЕНИЯ СНИМАЕМ ВЖИВУЮ: после absorb_unit логическая точка
	# бойца равна центру замка, и по ней уже ничего не узнать
	var vanish: Array = []
	var waited: int = 0
	while waited < 1800:
		await get_tree().physics_frame
		waited += 1
		var inside := 0
		for m in men:
			var u := m as Unit
			if not is_instance_valid(u):
				continue
			if u.garrisoned:
				inside += 1
			elif u.global_position.distance_to(gate) <= keep._door_radius() + 0.05:
				vanish.append(u.global_position)
		if inside == men.size():
			break
	var inside2 := 0
	var rings := 0
	var bars := 0
	for m in men:
		var u := m as Unit
		if not is_instance_valid(u):
			continue
		if u.garrisoned:
			inside2 += 1
		if GameManager.sel_decals.is_registered(u):
			rings += 1
		if GameManager.hp_bars.is_registered(u):
			bars += 1

	verdict("B1 весь отряд зашёл в замок", inside2 == men.size(),
		"внутри %d из %d за %d физкадров" % [inside2, men.size(), waited])
	# ── ГЛАВНОЕ ЧИСЛО ЖАЛОБЫ ────────────────────────────────────────────────
	# Боец обязан пропадать У ДВЕРЕЙ. Меряем от ворот и сравниваем с ДОПУСКОМ
	# ИЗ КОНФИГА — тем самым, по которому зачисляли раньше: проверяем СВОЙСТВО
	# («ближе, чем прежний широкий допуск»), а не выдуманное круглое число
	var worst: float = 0.0
	for p in vanish:
		worst = maxf(worst, (p as Vector3).distance_to(gate))
	verdict("B2 боец исчезает у дверей, а не за пять метров до них",
		not vanish.is_empty() and worst <= keep._door_radius() + 0.06,
		"худший в %.2f м от ворот при радиусе дверей %.2f (прежний допуск %.1f)" % [
			worst, keep._door_radius(), _UCfg.GARRISON_ENTER_RADIUS])
	verdict("C1 колец на карте не осталось", rings == 0,
		"осталось %d" % rings)
	verdict("C2 полосок здоровья на карте не осталось", bars == 0,
		"осталось %d" % bars)
	verdict("C3 вошедших нет в выделении", sm.selected_units.is_empty(),
		"выделено %d" % sm.selected_units.size())

	# ── ВЫПУСК: ОТРЯД ВОЗВРАЩАЕТСЯ К ВОРОТАМ, А НЕ В ПОЛЕ ───────────────────
	keep.release_garrison(sid)
	await pframes(4)
	var out_ok := 0
	var far: float = 0.0
	for m in GameManager.squad_members(sid):
		var u := m as Unit
		if u == null or not is_instance_valid(u) or u.garrisoned:
			continue
		out_ok += 1
		far = maxf(far, u.global_position.distance_to(gate))
	# Выпущенные встают строем ОТ ворот: глубина строя честно растёт наружу,
	# поэтому мерим по числу шеренг, а не круглым числом
	var rows: float = ceil(float(men.size()) / float(Building.square_cols(
		men.size(), keep.squad_cols)))
	var allow: float = keep.SQUAD_EXIT_DISTANCE + rows * keep.squad_spacing + 2.0
	verdict("B3 выпущенные встают у ворот, а не в чистом поле",
		out_ok > 0 and far <= allow,
		"дальний в %.2f м от ворот при допуске %.2f м" % [far, allow])
	for m in GameManager.squad_members(sid):
		_kill(m as Unit)
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
# E. ПОЛОСЫ ВЫХОДА
# ═════════════════════════════════════════════════════════════════════════════
func _check_lanes(keep: Castle) -> void:
	print("\n═════ E. ПОЛОСЫ ВЫХОДА ═════")
	# Полоса 0 — это «прямо перед воротами». Пустое поле обязано давать её
	# любому числу заказов ПОДРЯД, если предыдущий отряд уже уведён
	var lane_a: int = keep._free_exit_lane(0, 20, Building.square_cols(20, keep.squad_cols),
		keep.squad_spacing)
	verdict("E1 первый наём в пустом поле выходит прямо у ворот", lane_a == 0,
		"полоса %d" % lane_a)
	var step: float = keep._lane_step(20, Building.square_cols(20, keep.squad_cols),
		keep.squad_spacing)
	var c1: Vector3 = keep._lane_centre(1, 20, Building.square_cols(20,
		keep.squad_cols), keep.squad_spacing)
	var c0: Vector3 = keep._lane_centre(0, 20, Building.square_cols(20,
		keep.squad_cols), keep.squad_spacing)
	# ── ТРЕБОВАНИЕ РАЗВЁРНУТО: ПОЛОСА УХОДИТ КЛИНОМ, А НЕ ВБОК ─────────────
	# Здесь стояло «расстояние между соседними полосами РАВНО шагу», то есть
	# полосы обязаны были расходиться строго вбок. Ровно эта раскладка и дала
	# жалобу владельца «юниты собираются далеко справа по диагонали»: вперёд у
	# всех полос было одно и то же SQUAD_EXIT_DISTANCE, а вбок прибавлялся шаг
	# (разбор — в Building._lane_shift, замер — qa_gate G5, 72° к фасаду).
	# Теперь полосы лежат клином в 45°, и проверяем мы ДВА свойства порознь:
	# боковой разнос (ради него полосы и заведены) и фронтальный конус.
	var face := (keep.spawn_offset * Vector3(1.0, 0.0, 1.0)).normalized()
	var sidev := Vector3(-face.z, 0.0, face.x)
	var d10: Vector3 = c1 - c0
	var lat: float = absf(d10.dot(sidev))
	var fwd: float = d10.dot(face)
	# ── ТРЕБОВАНИЕ РАЗВЁРНУТО ВТОРОЙ РАЗ: ПОЛОСЫ ИДУТ ВГЛУБЬ ───────────────
	# Клин в 45° жалобу не закрыл: даже под ним второй заказ уходит на семь
	# метров вбок, а четвёртый на четырнадцать (замер qa_gate). Владелец
	# повторил её дословно — «а не ровно перед воротами». Теперь полосы
	# расходятся ТОЛЬКО В ГЛУБИНУ, и разносить их надо на глубину отряда, а
	# она втрое меньше ширины (разбор — в Building._lane_shift).
	#
	# ПРОВЕРЯЕМ ДВА СВОЙСТВА, И ОБА ОБЯЗАТЕЛЬНЫ: полосы разнесены (иначе два
	# одновременных заказа встанут друг на друга — ради этого полосы и
	# заведены) и разнесены ВПЕРЁД, а не вбок (иначе возвращается жалоба)
	var depth_step: float = keep._lane_depth_step(20,
		Building.square_cols(20, keep.squad_cols), keep.squad_spacing)
	verdict("E2 соседняя полоса разносит отряды на глубину строя",
		absf(fwd - depth_step) < 0.01 and depth_step > 1.0,
		"разнос вперёд %.2f м при шаге вглубь %.2f м" % [fwd, depth_step])
	verdict("E2б соседняя полоса не уходит вбок от ворот",
		lat <= 0.05,
		"вбок %.2f м, вперёд %.2f м" % [lat, fwd])

	# ── ЗАНЯТУЮ ПОЛОСУ ОБХОДИМ ──────────────────────────────────────────────
	var squatters: Array = []
	for i in range(6):
		var p: Vector3 = c0 + Vector3(float(i) * 0.5 - 1.2, 0.0, 0.0)
		p.y = GameManager.get_terrain_height(p.x, p.z)
		squatters.append(_spawn_worker(p))
	await pframes(4)
	var lane_b: int = keep._free_exit_lane(0, 20, Building.square_cols(20,
		keep.squad_cols), keep.squad_spacing)
	verdict("E3 занятую полосу наём обходит", lane_b != 0,
		"полоса %d при занятой нулевой" % lane_b)
	for s in squatters:
		_kill(s as Unit)
	await pframes(4)
	var lane_c: int = keep._free_exit_lane(0, 20, Building.square_cols(20,
		keep.squad_cols), keep.squad_spacing)
	verdict("E4 освободившаяся полоса возвращается к воротам", lane_c == 0,
		"полоса %d после ухода занявших" % lane_c)

	# ── ОДНОВРЕМЕННЫЙ НАЁМ ПО-ПРЕЖНЕМУ РАСХОДИТСЯ ──────────────────────────
	# Ради этого полосы и заведены: пока заказ не вышел из дверей, на его полосе
	# физически никого нет, и по одной занятости она выглядела бы свободной
	# Кладём в очередь выхода настоящую заявку на полосу 0 — ровно такую, какую
	# кладёт _process при найме, — и спрашиваем полосу для следующего заказа
	keep._pending_spawns.append({
		"name": "spearman", "idx": 0,
		"cols": Building.square_cols(20, keep.squad_cols),
		"spacing": keep.squad_spacing, "squad": 0, "total": 20, "lane": 0,
		"has_rally": false, "rally": Vector3.ZERO, "spot": Vector3.ZERO,
	})
	var lanes: Dictionary = {}
	for job in keep._pending_spawns:
		lanes[int((job as Dictionary).get("lane", 0))] = true
	var lane_d: int = keep._free_exit_lane(0, 20, Building.square_cols(20,
		keep.squad_cols), keep.squad_spacing)
	verdict("E5 полоса ещё не вышедшего заказа считается занятой",
		lane_d != 0 and lanes.has(0),
		"полоса %d при заявке, держащей нулевую" % lane_d)
	keep._pending_spawns.clear()

func _drawn_top(b: Building) -> float:
	var spr: MeshInstance3D = b.get_node_or_null("BuildingSprite") as MeshInstance3D
	if spr == null:
		return b.build_size.y
	var q: QuadMesh = spr.mesh as QuadMesh
	var mat: ShaderMaterial = q.material as ShaderMaterial
	var tex: Texture2D = mat.get_shader_parameter("albedo_tex") as Texture2D
	var r: Rect2 = _BBUtil.opaque_rect(tex)
	return q.size.y * (1.0 - r.position.y) * _BBUtil.V_STRETCH

func _ground_under(cam: Camera3D, scr: Vector2) -> Vector3:
	var from := cam.project_ray_origin(scr)
	var dirn := cam.project_ray_normal(scr)
	if absf(dirn.y) < 1e-4:
		return Vector3.ZERO
	return from + dirn * (-from.y / dirn.y)

func _spawn_worker(at: Vector3) -> Unit:
	var u: Unit = load("res://scenes/units/Worker.tscn").instantiate()
	u.faction = Constants.FACTION_PLAYER
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	return u

## Убираем СМЕРТЬЮ, а не queue_free: только на этом пути боец снимает с себя
## строку в ядре армии, место в сетке и место в отряде (см. CLAUDE.md)
func _kill(u: Unit) -> void:
	if u == null or not is_instance_valid(u) or u.is_dead():
		return
	u.take_damage(u.max_health * 10.0, null)
