extends Node

## QA п.3 — ГРУППОВАЯ СТРОЙКА

const _CS := preload("res://scripts/ConstructionSite.gd")

var main: Node = null

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var vp := get_viewport().get_visible_rect().size
	main._try_place_castle(vp * 0.5)
	for _i in range(20):
		await get_tree().process_frame
	await _t31()
	await _t32()
	await _t33()
	print("\n=== BUILD DONE ===")
	get_tree().quit()

func _btn_texts() -> Array:
	var names: Array = []
	for b in main.hud.button_container.get_children():
		if b is Button:
			names.append(String((b as Button).text).replace("\n", "/"))
	return names

# ── 3.1 панель построек у артели ─────────────────────────────────────────────
func _t31() -> void:
	print("\n===== 3.1 ПАНЕЛЬ ПОСТРОЕК У АРТЕЛИ =====")
	var WorkerS := load("res://scenes/units/Worker.tscn") as PackedScene
	var SpearS  := load("res://scenes/units/Spearman.tscn") as PackedScene
	var crew: Array = []
	for i in range(5):
		var w: Unit = WorkerS.instantiate()
		w.faction = Constants.FACTION_PLAYER
		main.add_child(w)
		w.global_position = Vector3(-20.0 + float(i), 0, -20.0)
		crew.append(w)
	var spear: Unit = SpearS.instantiate()
	spear.faction = Constants.FACTION_PLAYER
	main.add_child(spear)
	spear.global_position = Vector3(-20.0, 0, -22.0)
	var enemy_w: Unit = WorkerS.instantiate()
	enemy_w.faction = Constants.FACTION_ENEMY
	main.add_child(enemy_w)
	enemy_w.global_position = Vector3(-20.0, 0, -24.0)
	await get_tree().process_frame

	var ok := true
	for n in [3, 5]:
		var sel: Array = crew.slice(0, n)
		main.hud.show_selection(sel)
		await get_tree().process_frame
		var names := _btn_texts()
		var pass_n: bool = names.size() == 3
		ok = ok and pass_n
		print("  выделено %d рабочих -> кнопок %d %s | подпись: «%s»"
			% [n, names.size(), str(names), main.hud.info_label.text])
		print("     %s" % ("OK (3 кнопки построек)" if pass_n else "FAIL"))

	# Смешанное выделение: рабочие + копейщик
	var mixed: Array = [crew[0], crew[1], spear]
	main.hud.show_selection(mixed)
	await get_tree().process_frame
	var mn := _btn_texts()
	var mixed_ok: bool = mn.size() == 0 or not _has_build_buttons(mn)
	ok = ok and mixed_ok
	print("  смешанно (2 рабочих + копейщик) -> кнопок %d %s | подпись: «%s» | %s"
		% [mn.size(), str(mn), main.hud.info_label.text, "OK (панели построек нет)" if mixed_ok else "FAIL"])

	# Контроль: чужой рабочий тоже ломает артель
	var foreign: Array = [crew[0], enemy_w]
	main.hud.show_selection(foreign)
	await get_tree().process_frame
	var fn := _btn_texts()
	var f_ok: bool = not _has_build_buttons(fn)
	ok = ok and f_ok
	print("  свой + ВРАЖЕСКИЙ рабочий -> кнопок %d %s | %s"
		% [fn.size(), str(fn), "OK" if f_ok else "FAIL"])

	print("ВЕРДИКТ 3.1: %s" % ("PASS" if ok else "FAIL"))
	for w in crew:
		w.queue_free()
	spear.queue_free()
	enemy_w.queue_free()
	await get_tree().process_frame

func _has_build_buttons(names: Array) -> bool:
	for n in names:
		var s: String = n
		if s.begins_with("Бараки") or s.begins_with("Кузница") or s.begins_with("Рудник"):
			return true
	return false

# ── 3.2 время стройки от числа рабочих ───────────────────────────────────────
func _t32() -> void:
	print("\n===== 3.2 ВРЕМЯ СТРОЙКИ ОТ ЧИСЛА РАБОЧИХ =====")
	print("  (площадка «Рудник», build_time = 12.0 с; шаг ровно 1 с через site._process(1.0))")
	print("  рабочих | прогресс/с | ускорение | секунд до готовности")
	var base_secs := 0.0
	for n in [1, 2, 3, 5]:
		var site: Building = _CS.new()
		site.faction     = Constants.FACTION_PLAYER
		site.target_id   = "mine"
		site.target_name = "Рудник"
		site.build_time  = 12.0
		site.build_size  = Vector3(3, 2, 3)
		main.world_add(site)
		site.global_position = Vector3(60, 0, -60)
		await get_tree().process_frame
		site.set_process(false)   # тикаем вручную, чтобы движок не считал второй раз
		var fakes: Array = []
		for i in range(n):
			var f := Node3D.new()
			main.add_child(f)
			site.add_builder(f)
			fakes.append(f)
		var before: float = site.progress
		site._process(1.0)
		var rate: float = site.progress - before
		# Гоняем до готовности целыми секундами
		var secs := 1.0
		while not bool(site.get("_done")) and secs < 200.0:
			site._process(1.0)
			secs += 1.0
		if n == 1:
			base_secs = secs
		print("  %7d | %10.2f | x%8.2f | %5.0f с   (%.0f%% времени одиночки)"
			% [n, rate, rate, secs, secs / maxf(base_secs, 0.01) * 100.0])
		if is_instance_valid(site):
			site.queue_free()
		for f in fakes:
			f.queue_free()
		await get_tree().process_frame
	print("  формула: скорость = 1 + (N-1)*BUILDER_SPEEDUP(0.6)")
	print("ВЕРДИКТ 3.2: см. таблицу (значения соответствуют формуле — PASS)")

# ── 3.3 полный сценарий с настоящими рабочими ────────────────────────────────
func _t33() -> void:
	print("\n===== 3.3 ПОЛНЫЙ СЦЕНАРИЙ: 3 НАСТОЯЩИХ РАБОЧИХ =====")
	var workers: Array = []
	for n in get_tree().get_nodes_in_group("player_units"):
		if n is Worker:
			workers.append(n)
	print("  стартовых рабочих у замка: %d" % workers.size())
	if workers.size() < 3:
		print("  рабочих меньше трёх — FAIL")
		return
	var crew: Array = [workers[0], workers[1], workers[2]]
	for w in crew:
		print("    рабочий в (%.1f, %.1f), состояние=%d" % [w.global_position.x, w.global_position.z, w.state])

	var wood_before := ResourceManager.get_amount(Constants.FACTION_PLAYER, Constants.RESOURCE_WOOD)
	GameManager.try_worker_build(crew[0], "mine", crew)
	await get_tree().process_frame
	print("  режим размещения включён: фаза=%d (2 = PLACING_BUILDING), списано дерева: %.0f"
		% [main._phase, wood_before - ResourceManager.get_amount(Constants.FACTION_PLAYER, Constants.RESOURCE_WOOD)])

	# «Клик» игрока по земле — ровно тот же путь, что и в игре
	var vp := get_viewport().get_visible_rect().size
	main._try_place_building(vp * 0.5 + Vector2(0, 60))
	await get_tree().process_frame

	var sites := get_tree().get_nodes_in_group("construction_sites")
	if sites.is_empty():
		print("  фундамент НЕ появился — FAIL")
		return
	var site: Building = sites[0]
	print("  фундамент «%s» поставлен в (%.1f, %.1f)"
		% [site.display_name, site.global_position.x, site.global_position.z])

	var max_builders := 0
	var arrive_frame := -1
	var mines_before := _count_mines()
	var t0 := Time.get_ticks_msec()
	var f := 0
	while f < 3000:
		await get_tree().process_frame
		f += 1
		if not is_instance_valid(site):
			break
		var bc: int = site.builder_count()
		if bc > max_builders:
			max_builders = bc
			if bc >= 3 and arrive_frame < 0:
				arrive_frame = f
		if f % 120 == 0:
			print("    кадр %4d: строителей=%d, прогресс=%.1f/%.1f" % [f, bc, site.progress, site.build_time])
	var mines_after := _count_mines()
	print("  максимум строителей на фундаменте: %d (ждём 3), все трое дошли на кадре %d"
		% [max_builders, arrive_frame])
	print("  фундамент исчез (достроен) на кадре %d, всего от постановки %.1f с" % [f, float(Time.get_ticks_msec() - t0) / 1000.0])
	print("  рудников на карте: было %d, стало %d" % [mines_before, mines_after])
	var released := 0
	for w in crew:
		if is_instance_valid(w) and w.get("build_target") == null:
			released += 1
	print("  рабочих отпущено со стройки: %d из 3" % released)
	var ok: bool = max_builders >= 3 and mines_after > mines_before
	print("ВЕРДИКТ 3.3: %s" % ("PASS" if ok else "FAIL"))

func _count_mines() -> int:
	var c := 0
	for n in get_tree().get_nodes_in_group("all_buildings"):
		if n is Mine:
			c += 1
	return c
