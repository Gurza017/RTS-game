extends Node

## ═══════════════════════════════════════════════════════════════════════════
## ЗОНД: КУДА ВЫХОДЯТ БОЙЦЫ ИЗ ЗАМКА
## ═══════════════════════════════════════════════════════════════════════════
## ЖАЛОБА ВЛАДЕЛЬЦА (скриншот со стрелками): «юниты спавнятся далеко внизу
## справа по диагонали, а не прямо перед дверью».
##
## ── ЧТО РАЗДЕЛЯЕМ ─────────────────────────────────────────────────────────
## У выхода из здания ДВЕ независимые величины, и по экрану их не различить:
##   • ТОЧКА ворот (`_gate_position`) — она вправе быть сдвинутой вбок, потому
##     что нарисованные двери не всегда посреди кадра (поправка `_draw_cx`);
##   • НАПРАВЛЕНИЕ выхода — оно обязано совпадать с нарисованным фасадом
##     (`facade_dir`, мировой +Z) и вбок не заваливаться.
##
## Подозрение: направление считается как `spawn_offset.normalized()`, а в
## `spawn_offset` та самая боковая поправка уже подмешана. Тогда сдвиг ТОЧКИ
## заодно НАКЛОНЯЕТ НАПРАВЛЕНИЕ, и отряд уходит по диагонали — ровно то, что
## на скриншоте. Проверяем это числом, а не рассуждением.
##
##   godot --headless --path . res://qa_gate/Test.tscn

var main = null
var _pass := 0
var _fail := 0

func _ready() -> void:
	var t := Timer.new()
	t.wait_time = 180.0
	t.one_shot = true
	t.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(t)
	t.timeout.connect(func():
		print("\n=== ЗОНД ВОРОТ НЕ УЛОЖИЛСЯ В СРОК, провалов: %d ===" % _fail)
		get_tree().quit(2))
	t.start()
	call_deferred("_run")

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func verdict(title: String, ok: bool, detail: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	print("  ВЕРДИКТ %s: %s%s" % [title, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + detail) if detail != "" else ""])

func _run() -> void:
	Engine.max_fps = 0
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(12)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	for node in get_tree().get_nodes_in_group("all_units"):
		(node as Node).queue_free()
	await pframes(6)

	# Замок ставим САМИ, в известную точку: замок партии стоит в углу карты, и
	# «диагональ» там легко спутать с положением базы
	var keep := Castle.new()
	keep.faction = Constants.FACTION_PLAYER
	main.world_add(keep)
	keep.global_position = Vector3(0.0, GameManager.get_terrain_height(0.0, 0.0), 0.0)
	await pframes(10)

	var gate: Vector3 = keep._gate_position()
	var off: Vector3 = keep.spawn_offset
	var dir: Vector3 = Vector3(off.x, 0.0, off.z).normalized()
	print("\n═════ ВОРОТА ЗАМКА ═════")
	print("  замок в %s" % str(keep.global_position))
	print("  сдвиг рисунка _draw_cx %.2f м, полуширина рисунка %.2f м"
		% [keep._draw_cx, keep._draw_half_w])
	print("  вынос ворот gate_depth %.2f м" % keep.gate_depth())
	print("  spawn_offset %s -> точка ворот %s" % [str(off), str(gate)])
	print("  направление выхода %s (фасад = %s)"
		% [str(dir), str(keep.facade_dir())])

	# ── НАПРАВЛЕНИЕ ОБЯЗАНО БЫТЬ ФАСАДОМ ──────────────────────────────────
	# Отклонение считаем в градусах: так видно, «чуть-чуть» это или диагональ
	var face: Vector3 = keep.facade_dir().normalized()
	var ang: float = rad_to_deg(acos(clampf(dir.dot(face), -1.0, 1.0)))
	verdict("G1 направление выхода совпадает с фасадом", ang <= 5.0,
		"отклонение %.1f°" % ang)

	# ── БОЕЦ ВЫХОДИТ ПЕРЕД ДВЕРЬМИ ────────────────────────────────────────
	# Спрашиваем не формулу, а РЕЗУЛЬТАТ: ставим одного бойца штатным путём
	var before: Array = []
	for n in get_tree().get_nodes_in_group("all_units"):
		before.append(n)
	keep._spawn_one("worker", 0, -1, -1.0, 0, 0, 1)
	await pframes(6)
	var born: Unit = null
	for n2 in get_tree().get_nodes_in_group("all_units"):
		if not (n2 in before):
			born = n2 as Unit
			break
	if born == null:
		verdict("G2 боец родился", false, "никого не появилось")
	else:
		var p: Vector3 = born.global_position
		var dx: float = absf(p.x - gate.x)
		var dz: float = p.z - gate.z
		print("  боец родился в %s (ворота %s)" % [str(p), str(gate)])
		verdict("G2 боец выходит ПЕРЕД воротами, а не вбок", dx <= 1.0,
			"вбок от оси ворот %.2f м (вперёд %.2f м)" % [dx, dz])
		verdict("G3 боец выходит НАРУЖУ, а не в стену", dz >= 0.0,
			"вперёд от ворот %.2f м" % dz)

	# ── ОТРЯД, А НЕ ОДИНОЧКА ──────────────────────────────────────────────
	# У одиночки своя раскладка (спираль золотого угла), у отряда — шеренга
	# плюс ПОЛОСЫ ВЫХОДА, которые разводят отряды вбок от оси ворот. Жалоба со
	# скриншота про диагональ вполне может жить именно там, а не в направлении
	var before2: Array = []
	for n3 in get_tree().get_nodes_in_group("all_units"):
		before2.append(n3)
	for i in range(6):
		keep._spawn_one("spearman", i, -1, -1.0, 0, 0, 6)
	await pframes(8)
	var worst_side := 0.0
	var worst_fwd := 0.0
	var n_born := 0
	for n4 in get_tree().get_nodes_in_group("all_units"):
		if n4 in before2:
			continue
		n_born += 1
		var q: Vector3 = (n4 as Unit).global_position
		worst_side = maxf(worst_side, absf(q.x - gate.x))
		worst_fwd = maxf(worst_fwd, q.z - gate.z)
	print("  отряд из 6: родилось %d, худший сдвиг вбок %.2f м, вперёд до %.2f м"
		% [n_born, worst_side, worst_fwd])
	verdict("G4 отряд выходит перед воротами, а не по диагонали",
		n_born > 0 and worst_side <= 3.0,
		"вбок %.2f м (порог 3.0), вперёд %.2f м" % [worst_side, worst_fwd])


	# ── ЧЕТЫРЕ ЗАКАЗА ПОДРЯД: КУДА ОТРЯД ПРИХОДИТ ──────────────────────────
	# Блоки G1-G4 меряли ТОЧКУ РОЖДЕНИЯ (бойцы стоят в воротах), а жалоба про
	# то, КУДА отряд уходит. Плюс они звали _spawn_one с lane = 0, то есть в
	# обход выбора полосы — а вся боковая составляющая живёт именно там.
	#
	# Сценарий владельца: нанял отряд, дождался, нанял ещё. Полоса выбирается
	# настоящим _free_exit_lane, отряду дают дойти и встать
	var bar := Barracks.new()
	bar.faction = Constants.FACTION_PLAYER
	main.world_add(bar)
	bar.global_position = Vector3(30.0, GameManager.get_terrain_height(30.0, 0.0), 0.0)
	await pframes(10)
	var bgate: Vector3 = bar._gate_position()
	var bdir: Vector3 = Vector3(bar.spawn_offset.x, 0.0, bar.spawn_offset.z).normalized()
	var bside := Vector3(-bdir.z, 0.0, bdir.x)
	var sz: int = bar.squad_size
	var bcols: int = bar.square_cols(sz, bar.squad_cols)
	print("\n═════ ЧЕТЫРЕ ЗАКАЗА ИЗ БАРАКА ═════")
	print("  отряд %d бойцов, колонн %d, шаг полосы %.2f м"
		% [sz, bcols, bar._lane_step(sz, bcols, bar.squad_spacing)])
	var worst_lat := 0.0
	var worst_ratio := 0.0
	for order in range(4):
		var sid: int = GameManager.new_squad(bar.faction, "spearman")
		var lane: int = bar._free_exit_lane(sid, sz, bcols, bar.squad_spacing)
		for i in range(sz):
			bar._spawn_one("spearman", i, bar.squad_cols, bar.squad_spacing,
				sid, lane, sz)
		# Даём дойти и встать: 12 секунд физики хватает на 4-15 м хода
		await pframes(720)
		var pts: Array = []
		var sq: Variant = GameManager.squads.get(sid)
		if sq != null:
			for m in ((sq as Dictionary)["members"] as Array):
				var u := m as Unit
				if u != null and is_instance_valid(u) and not u.is_dead():
					pts.append(u.global_position)
		if pts.is_empty():
			print("  заказ %d: отряд пуст" % order)
			continue
		var c := Vector3.ZERO
		for p2 in pts:
			c += p2 as Vector3
		c /= float(pts.size())
		var rel: Vector3 = c - bgate
		var lat: float = absf(rel.dot(bside))
		var fwd: float = rel.dot(bdir)
		worst_lat = maxf(worst_lat, lat)
		# СВОЙСТВО, А НЕ КРУГЛОЕ ЧИСЛО: «перед воротами» означает, что вбок отряд
		# ушёл не дальше, чем вперёд. Порог в метрах пришлось бы подбирать заново
		# под каждый размер отряда — шаг полосы считается от его габарита
		worst_ratio = maxf(worst_ratio, lat / maxf(fwd, 0.01))
		print("  заказ %d: полоса %d, центр вбок %.2f м, вперёд %.2f м (%d бойцов)"
			% [order, lane, lat, fwd, pts.size()])
	verdict("G5 отряды собираются ПЕРЕД воротами, а не по диагонали вбок",
		worst_ratio <= 1.0,
		"худшее отношение вбок/вперёд %.2f (при вбок до %.2f м), это %.0f° к фасаду"
		% [worst_ratio, worst_lat, rad_to_deg(atan(worst_ratio))])

	print("\n=== ЗОНД ВОРОТ: пройдено %d, провалов: %d ===" % [_pass, _fail])
	get_tree().quit(0)
