extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ВРАЖЕСКОЕ ЗДАНИЕ КАК ПОЛНОЦЕННАЯ ЦЕЛЬ АТАКИ
## ═══════════════════════════════════════════════════════════════════════════
##   A/B ПРИКАЗ    — лучник и пехотинец по прямому приказу бьют постройку
##   C   КЛИК      — разбор клика находит здание, ПКМ назначает его целью
##   D   ПОДСВЕТКА — наведение на чужое здание даёт цель подсветки, и кольцо
##                   под ней растянуто по основанию, а не по бойцу
##   E   ГАБАРИТ   — дистанция считается до СТЕНЫ, а не до центра коробки:
##                   пехота встаёт у стены, а не влезает внутрь здания
##
## ЧТО ЗДЕСЬ ГЛАВНОЕ. Блоки A–C зелёные и БЫЛИ зелёными до правки: весь боевой
## путь по зданиям работал. Жалоба «здание нельзя выбрать целью» была про
## блоки D и E — про то, что игрок ВИДИТ. Держать A–C всё равно нужно: они и
## есть страховка от того, что починка обратной связи сломает саму атаку.
##
## Числа не хардкодятся: габарит берётся у самой постройки (`build_size`),
## дальность — у бойца.
##
## Запуск: godot --headless --path . res://qa_bldattack/Test.tscn

const _UStats := preload("res://scripts/unit_stats_config.gd")

var main = null
var verdicts: Array = []

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func verdict(title: String, ok: bool, detail: String = "") -> void:
	verdicts.append([title, ok, detail])

func _spawn(path: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = load(path).instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = at
	u.sync_row()
	return u

func _run() -> void:
	Engine.max_fps = 0
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(5)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.goblin_ai != null:
		main.goblin_ai.set_process(false)
	for n in get_tree().get_nodes_in_group("all_units"):
		(n as Node).queue_free()
	GameManager.world_bounds_enabled = false
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	await frames(3)

	await _probe()
	await _probe_click()
	await _probe_feedback()

	print("\n═════ ИТОГ qa_bldattack ═════")
	var bad := 0
	for v in verdicts:
		var row: Array = v
		if not bool(row[1]):
			bad += 1
		print("  %-58s %s%s" % [String(row[0]),
			"ПРОШЛО" if bool(row[1]) else "НЕ ПРОШЛО",
			("  — " + String(row[2])) if String(row[2]) != "" else ""])
	print("  провалов: %d из %d" % [bad, verdicts.size()])
	print("\n=== QA_BLDATTACK DONE ===")
	get_tree().quit()

func _make_barracks(at: Vector3) -> Building:
	var b: Building = load("res://scripts/Barracks.gd").new()
	b.faction = Constants.FACTION_ENEMY
	main.world_add(b)
	b.global_position = at
	return b

func _probe() -> void:
	var b := _make_barracks(Vector3(200.0, 0.0, 200.0))
	await frames(3)
	print("[зонд] барак: hp=%.1f размер=%s слой=%d группы=%s" %
		[b.current_health, str(b.build_size), b.collision_layer, str(b.get_groups())])

	# ── ЛУЧНИК ────────────────────────────────────────────────────────────
	var a := _spawn("res://scenes/units/Archer.tscn", Constants.FACTION_PLAYER,
		Vector3(200.0, 0.0, 215.0))
	await frames(3)
	var hp0: float = b.current_health
	a.command_attack(b, true, true, true)
	print("[зонд] лучник: цель=%s замок=%s состояние=%d дальность=%.1f" %
		[str(a.attack_target), str(a.target_lock), a.state, a.attack_range])
	await frames(600)
	print("[зонд] лучник через 600 кадров: цель=%s состояние=%d поз=%s урон=%.1f стрел=%d" %
		[str(a.attack_target), a.state, str(a.global_position),
		hp0 - b.current_health, GameManager.arrows_fired])
	verdict("A лучник по приказу бьёт вражеское здание", b.current_health < hp0,
		"снято %.1f HP" % (hp0 - b.current_health))
	verdict("A2 лучник не полез вплотную к стене",
		a.global_position.distance_to(b.global_position) > 3.0,
		"расстояние %.1f м" % a.global_position.distance_to(b.global_position))

	# ── ПЕХОТИНЕЦ ─────────────────────────────────────────────────────────
	var hp1: float = b.current_health
	var w := _spawn("res://scenes/units/Spearman.tscn", Constants.FACTION_PLAYER,
		Vector3(215.0, 0.0, 200.0))
	await frames(3)
	w.command_attack(b, true, true, true)
	print("[зонд] копейщик: цель=%s замок=%s состояние=%d" %
		[str(w.attack_target), str(w.target_lock), w.state])
	await frames(600)
	print("[зонд] копейщик через 600 кадров: цель=%s состояние=%d поз=%s урон=%.1f" %
		[str(w.attack_target), w.state, str(w.global_position), hp1 - b.current_health])
	verdict("B пехотинец по приказу бьёт вражеское здание",
		b.current_health < hp1, "снято %.1f HP" % (hp1 - b.current_health))
	verdict("B2 пехотинец не влез внутрь коробки здания",
		Vector2(w.global_position.x - b.global_position.x,
			w.global_position.z - b.global_position.z).length()
			> maxf(b.build_size.x, b.build_size.z) * 0.4,
		"от центра %.2f м при габарите %.1f" % [
			Vector2(w.global_position.x - b.global_position.x,
				w.global_position.z - b.global_position.z).length(),
			maxf(b.build_size.x, b.build_size.z)])


## ── ВТОРОЙ ЗОНД: ПУТЬ КЛИКА ────────────────────────────────────────────────
## Прямой command_attack по зданию работает (блоки A/B). Жалоба владельца — про
## КЛИК, а это другой путь: разбор луча (_pick_at) и обработчик ПКМ
func _probe_click() -> void:
	var sel = main.selection_manager
	var cam: Camera3D = main.get_viewport().get_camera_3d()
	print("[зонд] камера=%s менеджер=%s" % [str(cam), str(sel)])
	var b := _make_barracks(Vector3(240.0, 0.0, 240.0))
	await frames(3)
	# Наводим камеру на здание
	if main.has_method("focus_camera_on"):
		main.focus_camera_on(b.global_position)
	elif cam != null:
		cam.global_position = b.global_position + Vector3(0.0, 30.0, 30.0)
		cam.look_at(b.global_position, Vector3.UP)
	await frames(10)
	cam = main.get_viewport().get_camera_3d()
	var scr: Vector2 = cam.unproject_position(
		b.global_position + Vector3(0.0, b.build_size.y * 0.5, 0.0))
	print("[зонд] экранная точка здания: %s (окно %s)" % [str(scr),
		str(main.get_viewport().get_visible_rect().size)])
	var pick: Dictionary = sel._pick_at(scr, sel.order_pick_mask())
	print("[зонд] pick = %s" % str(pick))
	verdict("C клик по вражескому зданию находит именно его",
		pick.get("target", null) == b, "нашли %s" % str(pick.get("target", null)))

	var a2 := _spawn("res://scenes/units/Archer.tscn", Constants.FACTION_PLAYER,
		b.global_position + Vector3(0.0, 0.0, 12.0))
	await frames(3)
	sel._clear_selection()
	sel._select(a2)
	var hp0: float = b.current_health
	sel._handle_right_click(scr, false)
	print("[зонд] после ПКМ: цель=%s замок=%s состояние=%d" %
		[str(a2.attack_target), str(a2.target_lock), a2.state])
	verdict("C2 ПКМ по зданию назначает его целью", a2.attack_target == b,
		"цель %s" % str(a2.attack_target))
	await frames(600)
	verdict("C3 после клика лучник действительно бьёт здание",
		b.current_health < hp0, "снято %.1f HP" % (hp0 - b.current_health))


## ── ТРЕТИЙ БЛОК: ОБРАТНАЯ СВЯЗЬ И ГАБАРИТ ──────────────────────────────────
## Ровно то, чего не было и что читалось игроком как «здание нельзя выбрать»
func _probe_feedback() -> void:
	var sel = main.selection_manager
	var cam: Camera3D = main.get_viewport().get_camera_3d()
	# КРУПНАЯ постройка: на бараке в 3.5 м разница между центром и стеной ещё
	# терпима, а замок — это уже метры
	var castle: Building = load("res://scripts/Castle.gd").new()
	castle.faction = Constants.FACTION_ENEMY
	main.world_add(castle)
	castle.global_position = Vector3(-240.0, 0.0, -240.0)
	await frames(5)
	var half: float = maxf(castle.build_size.x, castle.build_size.z) * 0.5
	print("[зонд] замок: габарит=%s половина=%.2f" % [str(castle.build_size), half])

	cam.global_position = castle.global_position + Vector3(0.0, 40.0, 40.0)
	cam.look_at(castle.global_position, Vector3.UP)
	await frames(6)
	var scr: Vector2 = cam.unproject_position(castle.global_position)

	var sp := _spawn("res://scenes/units/Spearman.tscn", Constants.FACTION_PLAYER,
		castle.global_position + Vector3(0.0, 0.0, 25.0))
	await frames(3)
	sel._clear_selection()
	sel._select(sp)

	# D — наведение обязано вернуть именно постройку
	var hov: Array = sel.enemy_squad_under_cursor(scr)
	verdict("D наведение на чужое здание даёт цель подсветки",
		hov.size() == 1 and hov[0] == castle, "вернулось %s" % str(hov))

	# D2 — КОНТУР ПОД ЗДАНИЕМ ЛОЖИТСЯ ПО ЕГО ОСНОВАНИЮ.
	# Мерим в МЕТРАХ, а не в кратности кольцу бойца: у здания теперь свой меш
	# единичного радиуса (см. UnitVisuals.building_ring_mesh), потому что
	# растянутое кольцо бойца давало толстый угловатый многоугольник
	var k_b: float = GameManager.sel_decals.building_ring_scale(castle)
	var k_u: float = GameManager.sel_decals.building_ring_scale(sp)
	var want_r: float = maxf(castle.build_size.x, castle.build_size.z) * 0.5
	verdict("D2 контур под зданием ложится по его основанию",
		absf(k_b - want_r - GameManager.sel_decals.BUILD_RING_MARGIN) < 0.01
			and is_equal_approx(k_u, 1.0),
		"контур %.2f м при половине габарита %.2f, боец %.2f" % [k_b, want_r, k_u])

	# E — копейщик останавливается У СТЕНЫ, а не в центре коробки
	var hp0: float = castle.current_health
	sp.command_attack(castle, true, true, true)
	verdict("E дальность до здания считается до стены",
		is_equal_approx(sp.reach(), sp.attack_range + half),
		"reach=%.2f при дальности %.2f и половине габарита %.2f" %
			[sp.reach(), sp.attack_range, half])
	await frames(900)
	var d: float = Vector2(sp.global_position.x - castle.global_position.x,
		sp.global_position.z - castle.global_position.z).length()
	print("[зонд] копейщик у замка: %.2f м от центра (стена на %.2f), урон %.1f" %
		[d, half, hp0 - castle.current_health])
	verdict("E2 пехотинец встал у стены, а не влез в коробку", d >= half - 0.5,
		"%.2f м от центра при стене %.2f" % [d, half])
	verdict("E3 и при этом достаёт до здания", castle.current_health < hp0,
		"снято %.1f HP" % (hp0 - castle.current_health))
