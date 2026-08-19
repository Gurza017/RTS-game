extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: МЕТКИ ПОД НОГАМИ И ВЫХОД ОТРЯДА ИЗ ЗАМКА
## ═══════════════════════════════════════════════════════════════════════════
##   A ПРИВЯЗКА — кольцо/тень/полоска стоят там же, где НАРИСОВАН боец
##   B ЯКОРЬ    — сам спрайт посажен ногами на землю (проверка по альфе ленты)
##   C ЗАМОК    — гарнизон выходит одним строем, а не двумя кучками
##
## ПОЧЕМУ ИМЕННО «ГДЕ НАРИСОВАН», А НЕ «ГДЕ СТОИТ». Логическая точка бойца
## честна всегда, и кольцо в ней стояло с самого начала. Уезжает КАРТИНКА:
## между физическими шагами она сглаживается (Unit._smoothed), а при
## шардировании боец шагает раз в три кадра, и догон отстаёт на длину шага —
## замерено 0.28 м по каждой оси, то есть почти полметра по диагонали марша.
## Поэтому проверка ведётся против draw_position(), и раздел A специально
## гоняет три шарда: на одном шарде сглаживания нет вовсе и стенд был бы
## зелёным даже на сломанном коде.

const _Opt := preload("res://scripts/perf_config.gd")

var main = null
var _pass := 0
var _fail := 0
var _log: Array = []

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
	var out := s
	while out.length() < n: out += " "
	return out

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(8)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	await pframes(2)

	await _a_decals()
	await _b_anchor()
	await _c_castle()

	print("\n═════ ИТОГ ═════")
	for e in _log:
		var row: Array = e
		print("  %s%s" % [_pad(String(row[0]), 66), "ПРОШЛО" if bool(row[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	print("\n=== QA_RING DONE ===")
	get_tree().quit(1 if _fail > 0 else 0)

func _make(kind: String) -> Unit:
	match kind:
		"spearman": return Spearman.new()
		"archer":   return Archer.new()
		"warrior":  return Warrior.new()
		_:          return Worker.new()

# ═════════════════════════════════════════════════════════════════════════════
# A. МЕТКИ ЕДУТ ЗА КАРТИНКОЙ
# ═════════════════════════════════════════════════════════════════════════════
func _a_decals() -> void:
	print("\n═════ A. ПРИВЯЗКА МЕТОК ═════")
	var men: Array = []
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
	for i in range(4):
		var u: Unit = _make(["worker", "spearman", "archer", "warrior"][i])
		u.faction = Constants.FACTION_PLAYER
		main.world_add(u)
		u.global_position = Vector3(-6.0 + float(i) * 3.0, 0.0, 0.0)
		u.sync_row()
		if i > 0:
			GameManager.add_to_squad(sid, u)
		men.append(u)
	await pframes(6)
	var sm = main.selection_manager
	sm._clear_selection()
	for u in men:
		sm._select(u)
	GameManager.on_selection_changed(sm.selected_units)
	GameManager.set_hp_bars_forced(true)
	await frames(6)

	var worst_stand := _decal_gap(men)
	verdict("A1 стоящий боец: кольцо ровно под спрайтом",
		worst_stand < 0.02, "макс. расхождение %.3f м" % worst_stand)

	# ── ТРИ ШАРДА: ИМЕННО ТАК ТИКАЕТ ИГРА ПРИ 1200+ БОЙЦАХ ─────────────────
	_Opt.tick_shards_force = 3
	for u in men:
		(u as Unit).command_move(Vector3(50.0, 0.0, 50.0))
	await frames(90)
	var worst_march := _decal_gap(men)
	verdict("A2 идущий боец на трёх шардах: кольцо всё так же под спрайтом",
		worst_march < 0.02, "макс. расхождение %.3f м" % worst_march)

	# И убеждаемся, что сглаживание ДЕЙСТВИТЕЛЬНО работает — иначе A2 зелёный
	# просто потому, что картинке некуда отставать
	var lag := 0.0
	for u in men:
		var unit: Unit = u
		lag = maxf(lag, Vector2(unit.draw_position().x - unit.global_position.x,
			unit.draw_position().z - unit.global_position.z).length())
	verdict("A3 картинка и правда отстаёт от логики (иначе A2 ничего не проверяет)",
		lag > 0.05, "отставание картинки %.3f м" % lag)

	var hp_gap := 0.0
	for u in men:
		var unit: Unit = u
		var p: Vector3 = GameManager.hp_bars._last.get(unit, Vector3.INF)
		if p.x == INF:
			continue
		hp_gap = maxf(hp_gap, Vector2(p.x - unit.draw_position().x,
			p.y - unit.draw_position().z).length())
	verdict("A4 полоска здоровья висит над той же точкой",
		hp_gap < 0.02, "макс. расхождение %.3f м" % hp_gap)

	# Красное кольцо прицела — тот же слой, та же привязка
	GameManager.sel_decals.set_hover_units(men, main.world_root())
	await frames(4)
	var hov := 0.0
	for u in men:
		var unit: Unit = u
		var p: Vector3 = GameManager.sel_decals._hover_last.get(unit, Vector3.INF)
		if p.x == INF:
			continue
		hov = maxf(hov, Vector2(p.x - unit.draw_position().x,
			p.z - unit.draw_position().z).length())
	verdict("A5 красное кольцо прицела привязано так же",
		hov < 0.02, "макс. расхождение %.3f м" % hov)
	GameManager.sel_decals.clear_hover()

	_Opt.tick_shards_force = 0
	GameManager.set_hp_bars_forced(false)
	sm._clear_selection()
	for u in men:
		(u as Node).queue_free()
	await pframes(3)

func _decal_gap(men: Array) -> float:
	var worst := 0.0
	for u in men:
		var unit: Unit = u
		var p: Vector3 = GameManager.sel_decals._last_pos.get(unit, Vector3.INF)
		if p.x == INF:
			continue
		var d: Vector3 = unit.draw_position()
		worst = maxf(worst, Vector2(p.x - d.x, p.z - d.z).length())
	return worst

# ═════════════════════════════════════════════════════════════════════════════
# B. ЯКОРЬ СПРАЙТА
# ═════════════════════════════════════════════════════════════════════════════
## Ноги нарисованного бойца обязаны стоять в его логической точке. Считается из
## геометрии квада и НЕПРОЗРАЧНОЙ рамки текущего кадра ленты: наклон камеры и
## растяжка V_STRETCH взаимно сокращаются (V_STRETCH = 1/cos(pitch)), поэтому
## смещение выходит прямо в метрах земли
func _b_anchor() -> void:
	print("\n═════ B. ЯКОРЬ СПРАЙТА ═════")
	for kind in ["worker", "spearman", "archer", "warrior"]:
		var u: Unit = _make(String(kind))
		u.faction = Constants.FACTION_PLAYER
		main.world_add(u)
		u.global_position = Vector3(0.0, 0.0, 30.0)
		u.sync_row()
		await pframes(4)
		await frames(3)
		var sf: Array = u.sheet_frame()
		var tex: Texture2D = sf[0]
		if tex == null:
			verdict("B %s: лента собрана" % kind, false, "спрайта нет")
			u.queue_free()
			continue
		var img: Image = tex.get_image()
		var nf: int = maxi(int(sf[2]), 1)
		var px: float = float(sf[3])
		var fw: int = int(img.get_width() / nf)
		var fh: int = img.get_height()
		var sub: Image = img.get_region(Rect2i(int(sf[1]) * fw, 0, fw, fh))
		var used: Rect2i = sub.get_used_rect()
		var pad: int = fh - (used.position.y + used.size.y)
		var dy: float = float(sf[4]) - 0.5 * float(fh) * px + float(pad) * px
		verdict("B %s: ноги стоят на своей точке" % kind,
			absf(dy) < 0.05, "по вертикали %+.3f м" % dy)
		u.queue_free()
		await pframes(2)

# ═════════════════════════════════════════════════════════════════════════════
# C. ВЫХОД ИЗ ЗАМКА
# ═════════════════════════════════════════════════════════════════════════════
func _c_castle() -> void:
	print("\n═════ C. ВЫХОД ИЗ ЗАМКА ═════")
	var c := Castle.new()
	c.faction = Constants.FACTION_PLAYER
	main.world_add(c)
	c.global_position = Vector3(0.0, GameManager.get_terrain_height(0.0, 60.0), 60.0)
	await pframes(6)

	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
	var men: Array = []
	for i in range(8):
		var u := Spearman.new()
		u.faction = Constants.FACTION_PLAYER
		main.world_add(u)
		u.global_position = Vector3(-3.0 + float(i) * 0.8, 0.0, 56.0)
		GameManager.add_to_squad(sid, u)
		men.append(u)
	await pframes(4)

	# Половина отряда заходит внутрь, половина остаётся снаружи и УХОДИТ
	# далеко — это и есть картинка «две кучки» из отчёта
	for i in range(4):
		c.absorb_unit(men[i])
	for i in range(4, 8):
		(men[i] as Unit).global_position = Vector3(40.0, 0.0, 20.0)
		(men[i] as Unit).sync_row()
	await pframes(3)
	verdict("C1 половина отряда внутри, половина далеко снаружи",
		(men[0] as Unit).garrisoned and not (men[7] as Unit).garrisoned)

	c._release_members(sid)
	await pframes(3)
	var out_n := 0
	for u in men:
		if not (u as Unit).garrisoned:
			out_n += 1
	verdict("C2 после выпуска внутри не осталось никого",
		out_n == 8, "снаружи %d из 8" % out_n)

	# ГЛАВНОЕ: приказ получают ВСЕ, включая тех, кто внутри не сидел, —
	# иначе отряд так и останется разорванным
	var far_ordered := 0
	for i in range(4, 8):
		var u: Unit = men[i]
		if u.global_position.distance_to(u.move_target) > 1.0 \
				and u.move_target.distance_to(c.global_position) < 40.0:
			far_ordered += 1
	verdict("C3 отставшие получили приказ идти к строю у ворот",
		far_ordered == 4, "получили %d из 4" % far_ordered)

	var slots: Array = GameManager.squads[sid].get("slots", [])
	verdict("C4 у отряда появилась настоящая разметка строя, а не пустота",
		slots.size() == 8, "мест в разметке %d" % slots.size())

	# Разметка ПЛОТНАЯ: расстояние между соседними местами — интервал отряда,
	# а не разброс по карте
	var far_slot := 0.0
	var cen := Vector3.ZERO
	for s in slots:
		cen += s
	cen /= float(maxi(slots.size(), 1))
	for s in slots:
		far_slot = maxf(far_slot, (s as Vector3).distance_to(cen))
	verdict("C5 строй на выходе плотный (все места в одном блоке)",
		far_slot < 6.0, "самое дальнее место в %.1f м от центра строя" % far_slot)

	# ── ОТМЕНА ПОХОДА НЕ ОСТАВЛЯЕТ ПРИЗРАКОВ ВНУТРИ ────────────────────────
	var sid2: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
	var men2: Array = []
	for i in range(4):
		var u := Spearman.new()
		u.faction = Constants.FACTION_PLAYER
		main.world_add(u)
		u.global_position = Vector3(float(i) * 0.8, 0.0, 58.0)
		GameManager.add_to_squad(sid2, u)
		men2.append(u)
	await pframes(4)
	c.request_garrison(sid2)
	await pframes(4)
	c.absorb_unit(men2[0])
	c.absorb_unit(men2[1])
	# Игрок уводит одного из оставшихся — поход отменяется
	# Цель ВНУТРИ карты: за краем её зажимает clamp_to_map, и стенд мерил бы
	# этот зажим, а не сохранность приказа
	(men2[3] as Unit).command_move(Vector3(30.0, 0.0, 40.0))
	await pframes(20)
	var inside := 0
	for u in men2:
		if (u as Unit).garrisoned:
			inside += 1
	verdict("C6 отменённый поход в замок не оставляет бойцов внутри навсегда",
		inside == 0, "осталось внутри %d" % inside)
	# И приказ игрока при этом НЕ переписан обратно на ворота
	verdict("C7 приказ игрока при отмене уцелел",
		(men2[3] as Unit).move_target.distance_to(Vector3(30.0, 0.0, 40.0)) < 2.0,
		"цель приказа (%.1f, %.1f)" % [(men2[3] as Unit).move_target.x,
			(men2[3] as Unit).move_target.z])
