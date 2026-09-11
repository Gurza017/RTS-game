extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ОВЦЫ У ЛОГОВА И ГОЛОД ТРОЛЛЯ (заказ владельца, 10.09.2026)
## ═══════════════════════════════════════════════════════════════════════════
##   A СПРАЙТЫ И СТАДО — ленты из resources/Sheep грузятся (8 кадров покоя,
##     6 ходьбы), у логова с первого кадра SHEEP_START овец, прирост по
##     таймеру SHEEP_BREED_COUNT, потолок SHEEP_MAX.
##   B ПЕРЕБЕЖКИ — овца выбирает точку в 5–10 м, идёт с лентой ходьбы, по
##     приходу стоит с лентой покоя; не уходит дальше SHEEP_GRAZE_RADIUS.
##   C ОБЕД ТРОЛЛЯ — голодный тролль подходит к овце, овца исчезает, тролль
##     лечится на TROLL_EAT_HEAL, звук «ням-ням» в банке и попытка его сыграть.
## Числа — из конфигов (правило 10), ожидание физкадрами (правило 11).
## Запуск: godot --headless --path . res://qa_sheep/Test.tscn

const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")
const _SheepS := preload("res://scripts/goblin/Sheep.gd")

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(240.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 240 с"); _finish())

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
	print("\n═════ ИТОГ qa_sheep: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

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

	# ── A. Спрайты и стадо ─────────────────────────────────────────────────
	print("\n═════ A. СПРАЙТЫ И СТАДО ═════")
	verdict("A1 ленты овцы найдены в resources/Sheep", _SheepS.sheets_ok())
	verdict("A2 покой — 8 кадров, ходьба — 6 (квадратный кадр 128)",
		_SheepS.frames_in(_SheepS.SHEET_IDLE) == 8 and _SheepS.frames_in(_SheepS.SHEET_WALK) == 6,
		"покой %d, ходьба %d" % [_SheepS.frames_in(_SheepS.SHEET_IDLE), _SheepS.frames_in(_SheepS.SHEET_WALK)])
	var lair = GameManager.troll_lair
	if lair == null or not is_instance_valid(lair):
		verdict("A0 логова нет", false)
		_finish()
		return
	await frames(4)
	var n0: int = int(lair.call("sheep_alive"))
	verdict("A3 у логова с первого кадра %d овец (SHEEP_START)" % _GobCfg.SHEEP_START,
		n0 == _GobCfg.SHEEP_START, "овец %d" % n0)
	var all_ok := true
	var near := 0
	for s in get_tree().get_nodes_in_group("sheep"):
		var mi := (s as Node).get_node_or_null("SheepSprite") as MeshInstance3D
		if mi == null or (s as Node3D).call("sprite_texture") == null:
			all_ok = false
		if (s as Node3D).global_position.distance_to((lair as Node3D).global_position) <= _GobCfg.SHEEP_GRAZE_RADIUS + 1.0:
			near += 1
	verdict("A4 у каждой овцы билборд с лентой, все в радиусе выпаса логова",
		all_ok and near == n0, "с картинкой %s, у логова %d из %d" % [str(all_ok), near, n0])
	var born: int = int(lair.call("breed_sheep"))
	verdict("A5 прирост по таймеру: +%d" % _GobCfg.SHEEP_BREED_COUNT,
		born == _GobCfg.SHEEP_BREED_COUNT and int(lair.call("sheep_alive")) == n0 + _GobCfg.SHEEP_BREED_COUNT,
		"родилось %d, стало %d" % [born, int(lair.call("sheep_alive"))])
	for _k in range(10):
		lair.call("breed_sheep")
	var extra: int = int(lair.call("breed_sheep"))
	verdict("A6 потолок стада SHEEP_MAX = %d, сверх него не родится" % _GobCfg.SHEEP_MAX,
		int(lair.call("sheep_alive")) == _GobCfg.SHEEP_MAX and extra == 0,
		"овец %d, лишний прирост %d" % [int(lair.call("sheep_alive")), extra])

	# ── B. Перебежки ───────────────────────────────────────────────────────
	print("\n═════ B. ПЕРЕБЕЖКИ ═════")
	var sheep: Array = lair.get("sheep")
	var s0: Node3D = sheep[0]
	var start: Vector3 = s0.global_position
	s0.call("force_hop")
	var tgt: Vector3 = s0.call("current_target")
	var hop: float = Vector2(tgt.x - start.x, tgt.z - start.z).length()
	verdict("B1 точка перебежки в %.0f–%.0f м от овцы (вода обойдена)" % [_GobCfg.SHEEP_HOP_MIN, _GobCfg.SHEEP_HOP_MAX],
		hop >= _GobCfg.SHEEP_HOP_MIN - 1.0 and hop <= _GobCfg.SHEEP_HOP_MAX + 1.0
			and not GameManager.is_water(tgt.x, tgt.z),
		"%.2f м" % hop)
	verdict("B2 на переходе играет лента ходьбы", bool(s0.call("is_walking"))
		and s0.call("sprite_texture") != _SheepS._texture("idle", false),
		"walking=%s" % str(s0.call("is_walking")))
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 700:
		await get_tree().process_frame
	var moved: float = s0.global_position.distance_to(start)
	verdict("B3 овца реально идёт к точке (сдвиг за 0.7 с > 0.3 м, не дальше цели)",
		moved > 0.3 and moved <= hop + 0.3, "прошла %.2f м" % moved)
	s0.call("arrive_now")
	verdict("B4 по приходу стоит, лента покоя", not bool(s0.call("is_walking"))
		and s0.global_position.distance_to(Vector3(tgt.x, s0.global_position.y, tgt.z)) < 0.05)
	# Дальше радиуса выпаса не уходит: сто перебежек подряд «телепортом»
	var far := 0
	for _h in range(100):
		s0.call("force_hop")
		s0.call("arrive_now")
		if s0.global_position.distance_to((lair as Node3D).global_position) > _GobCfg.SHEEP_GRAZE_RADIUS + 0.5:
			far += 1
	verdict("B5 за сто перебежек овца не вышла за радиус выпаса", far == 0, "вышла %d раз" % far)

	# ── C. Обед тролля ─────────────────────────────────────────────────────
	print("\n═════ C. ОБЕД ТРОЛЛЯ ═════")
	verdict("C1 звук «ням-ням» в банке и его файлы существуют",
		AudioManager.SFX_BANK.has("nom_nom")
			and ResourceLoader.exists(AudioManager.DIR_SFX + String(AudioManager.SFX_BANK["nom_nom"][0])))
	var fresh: Array = lair.call("spawn_guards", 1)
	if fresh.is_empty():
		verdict("C0 тролля нет", false)
		_finish()
		return
	var troll: Unit = fresh[0]
	await pframes(2)
	troll.current_health = troll.max_health * 0.5
	troll._soa_push_stats()
	var flock_before: int = int(lair.call("sheep_alive"))
	# Ближайшая овца — рядом с троллем, чтобы не ждать перехода через всё пастбище
	var s1: Node3D = lair.call("nearest_sheep", troll.global_position)
	s1.global_position = troll.global_position + Vector3(6.0, 0.0, 0.0)
	s1.call("arrive_now")
	troll.call("force_hunger")
	var guard := 0
	while guard < 60 * 30 and int(troll.get("meals_eaten")) < 1:
		await get_tree().physics_frame
		guard += 1
	verdict("C2 голодный тролль подошёл и съел овцу", int(troll.get("meals_eaten")) >= 1,
		"физкадров %d" % guard)
	# Физкадры, а не кадры отрисовки (правило 11): под нагрузкой шлюза два
	# кадра отрисовки вмещали десятки физкадров, и стадо > TROLL_HUNGRY_FLOCK
	# успевало потерять третью овцу
	await pframes(2)
	# Стартовый страж логова тоже ест (стадо больше TROLL_HUNGRY_FLOCK), поэтому
	# убыль считается «не меньше одной и не больше числа троллей»
	var trolls_n: int = int(lair.call("trolls_alive"))
	var flock_after: int = int(lair.call("sheep_alive"))
	verdict("C3 овца исчезла с карты, стадо уменьшилось (на 1…число троллей)",
		not is_instance_valid(s1) and flock_after < flock_before and flock_before - flock_after <= trolls_n,
		"было %d, стало %d, троллей %d" % [flock_before, flock_after, trolls_n])
	var want: float = troll.max_health * (0.5 + _GobCfg.TROLL_EAT_HEAL)
	verdict("C4 тролль вылечился на %.0f %% запаса" % (_GobCfg.TROLL_EAT_HEAL * 100.0),
		absf(troll.current_health - want) <= troll.max_health * 0.01,
		"%.0f при ожидаемых %.0f" % [troll.current_health, want])
	verdict("C5 звук поедания запрошен у AudioManager", int(troll.get("meal_sound_tries")) >= 1,
		"попыток %d, сыграно %d" % [int(troll.get("meal_sound_tries")), int(troll.get("meal_sound_ok"))])
	verdict("C6 голод после обеда взведён заново (не ест подряд)",
		float(troll.call("hunger_left")) > _GobCfg.TROLL_HUNGER_SEC * 0.5,
		"до следующего обеда %.0f с" % float(troll.call("hunger_left")))
	_finish()
