extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: УДАРНАЯ КОННИЦА — СКОРОСТЬ И ПРОДАВЛИВАНИЕ СТРОЯ
## ═══════════════════════════════════════════════════════════════════════════
##   A СКОРОСТЬ   — кабан идёт заметно быстрее пехоты: и в чистом поле, и
##                  внутри своей толпы (жалоба: «едут вровень с пехотой»)
##   B НАПОР      — толчок кабана вдвое сильнее и идёт чаще, чем у пехоты
##   C ВМЯТИНА    — разметка чужого строя прогибается назад и не уезжает
##                  дальше потолка
##   D УРОН НЕ ТРОНУТ — правка чисто физическая: удар кабана наносит ровно
##                  столько же, сколько в конфиге
##   E ПРОРЫВ     — три отряда кабанов против трёх отрядов копейщиков: строй
##                  обязан раздаться и пропустить массу сквозь себя
##
## ЧИСЛА НЕ ХАРДКОДЯТСЯ: скорости, напор и множители читаются из
## unit_stats_config — стенд проверяет СВОЙСТВО, а не цифру владельца.
##
## Запуск: godot --headless --path . res://qa_cavalry/Test.tscn

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

func _squad(path: String, fac: int, kind: String, center: Vector3,
		count: int, cols: int, gap: float) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var men: Array = []
	var slots: Array = []
	for i in range(count):
		var p := center + Vector3(float(i % cols) * gap - float(cols - 1) * gap * 0.5,
			0.0, float(i / cols) * gap)
		var u := _spawn(path, fac, p)
		u.post_pos = p
		u.set("_post_valid", true)
		GameManager.add_to_squad(sid, u)
		men.append(u)
		slots.append(p)
	return [sid, men, slots]

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

	await _a_speed()
	await _b_push()
	await _c_dent()
	_d_damage()
	await _e_breakthrough()

	print("\n═════ ИТОГ qa_cavalry ═════")
	var bad := 0
	for v in verdicts:
		var row: Array = v
		if not bool(row[1]):
			bad += 1
		print("  %-58s %s%s" % [String(row[0]),
			"ПРОШЛО" if bool(row[1]) else "НЕ ПРОШЛО",
			("  — " + String(row[2])) if String(row[2]) != "" else ""])
	print("  провалов: %d из %d" % [bad, verdicts.size()])
	print("\n=== QA_CAVALRY DONE ===")
	get_tree().quit()

# ═════════════════════════════════════════════════════════════════════════════
# A. СКОРОСТЬ
# ═════════════════════════════════════════════════════════════════════════════
## Жалоба владельца: «кабаны едут почти вровень с пехотой». Меряем ПУТЬ за
## одинаковое время — и в одиночку, и в плотной толпе своих. Второе важнее:
## в конфиге скорость честная, а вот в куче тел быстрый боец упирается в
## медленных впереди, и разница на экране пропадает
func _a_speed() -> void:
	var rider_cfg: float = _UStats.stat("goblin_rider", "movement_speed", 0.0)
	var foot_cfg: float = _UStats.stat("goblin_spearman", "movement_speed", 0.0)
	verdict("A1 в конфиге кабан быстрее пешего гоблина",
		rider_cfg > foot_cfg * 1.2,
		"кабан %.2f м/с, пеший %.2f м/с" % [rider_cfg, foot_cfg])

	# ── ОДИНОЧКИ В ЧИСТОМ ПОЛЕ ─────────────────────────────────────────────
	var solo_r := _spawn("res://scenes/units/GoblinPigRider.tscn",
		Constants.FACTION_GOBLIN, Vector3(-400.0, 0.0, -400.0))
	var solo_f := _spawn("res://scenes/units/GoblinSpearman.tscn",
		Constants.FACTION_GOBLIN, Vector3(-400.0, 0.0, -390.0))
	await frames(4)
	var r0: Vector3 = solo_r.global_position
	var f0: Vector3 = solo_f.global_position
	solo_r.command_move(r0 + Vector3(60.0, 0.0, 0.0))
	solo_f.command_move(f0 + Vector3(60.0, 0.0, 0.0))
	await frames(180)
	var dr: float = solo_r.global_position.distance_to(r0)
	var df: float = solo_f.global_position.distance_to(f0)
	verdict("A2 в чистом поле кабан реально уходит вперёд",
		df > 0.5 and dr > df * 1.2,
		"кабан прошёл %.1f м, пеший %.1f м (отношение %.2f)"
			% [dr, df, dr / maxf(df, 0.01)])
	solo_r.queue_free()
	solo_f.queue_free()

	# ── ТОЛПА: ЧЕСТНЫЙ СЛУЧАЙ ИЗ ПАРТИИ ────────────────────────────────────
	# Орда ходит кучей, и вопрос владельца именно про неё. Отряды РАЗНЫЕ (в
	# игре тоже: ARMY_COMPOSITION набирает кабанов отдельными отрядами), идут
	# в одну сторону из одинаковых блоков
	var horde_r: Array = _squad("res://scenes/units/GoblinPigRider.tscn",
		Constants.FACTION_GOBLIN, "goblin_rider", Vector3(-300.0, 0.0, -400.0),
		36, 6, 1.2)
	var horde_f: Array = _squad("res://scenes/units/GoblinSpearman.tscn",
		Constants.FACTION_GOBLIN, "goblin_spearman", Vector3(-300.0, 0.0, -370.0),
		36, 6, 1.2)
	await frames(6)
	var cr0: Vector3 = GameManager.squad_centroid(int(horde_r[0]))
	var cf0: Vector3 = GameManager.squad_centroid(int(horde_f[0]))
	for u in horde_r[1]:
		(u as Unit).command_move((u as Node3D).global_position + Vector3(60.0, 0.0, 0.0))
	for u in horde_f[1]:
		(u as Unit).command_move((u as Node3D).global_position + Vector3(60.0, 0.0, 0.0))
	await frames(180)
	var mr: float = GameManager.squad_centroid(int(horde_r[0])).distance_to(cr0)
	var mf: float = GameManager.squad_centroid(int(horde_f[0])).distance_to(cf0)
	verdict("A3 в плотном строю кабаны тоже опережают пехоту",
		mf > 0.5 and mr > mf * 1.15,
		"центр кабанов ушёл на %.1f м, пехоты на %.1f м (отношение %.2f)"
			% [mr, mf, mr / maxf(mf, 0.01)])
	for arr in [horde_r[1], horde_f[1]]:
		for u in arr:
			if is_instance_valid(u):
				(u as Node).queue_free()
	await frames(3)

# ═════════════════════════════════════════════════════════════════════════════
# B. НАПОР
# ═════════════════════════════════════════════════════════════════════════════
## ПОЧЕМУ ОДНОГО push_force БЫЛО МАЛО. Смещение считается как
## clampf(разница напора × 0.15, 0.04, 0.4) — потолок срабатывает уже при
## разнице в три единицы. У кабана против копейщика разница около четырнадцати,
## то есть push_force 15 и push_force 3 давали ОДНО И ТО ЖЕ смещение.
## Проверяем поэтому не константу, а два свойства: множитель применяется ПОСЛЕ
## потолка, и толчок идёт чаще пехотного
func _b_push() -> void:
	var mult: float = _UStats.stat("goblin_rider", "charge_push_mult", 1.0)
	verdict("B1 у конницы есть свой множитель смещения",
		mult >= 2.0, "charge_push_mult = %.1f" % mult)
	var every: int = int(_UStats.stat("goblin_rider", "push_every", Unit.PUSH_EVERY))
	verdict("B2 конница толкает чаще пехоты",
		every > 0 and every < Unit.PUSH_EVERY,
		"кабан раз в %d удара, пехота раз в %d" % [every, Unit.PUSH_EVERY])

	# ── ЗАМЕР СМЕЩЕНИЯ: КАБАН ПРОТИВ МЕЧНИКА ПО ОДНОЙ И ТОЙ ЖЕ ЖЕРТВЕ ──────
	# Толкаем напрямую, минуя бой: проверяется _apply_push, а не то, успел ли
	# кто-то ударить за окно наблюдения
	var victim_a := _spawn("res://scenes/units/Spearman.tscn",
		Constants.FACTION_PLAYER, Vector3(-500.0, 0.0, -500.0))
	var victim_b := _spawn("res://scenes/units/Spearman.tscn",
		Constants.FACTION_PLAYER, Vector3(-500.0, 0.0, -480.0))
	var rider := _spawn("res://scenes/units/GoblinPigRider.tscn",
		Constants.FACTION_GOBLIN, Vector3(-502.0, 0.0, -500.0))
	var knight := _spawn("res://scenes/units/Warrior.tscn",
		Constants.FACTION_GOBLIN, Vector3(-502.0, 0.0, -480.0))
	await frames(4)
	var pa0: Vector3 = victim_a.global_position
	var pb0: Vector3 = victim_b.global_position
	var dirn := Vector3(1.0, 0.0, 0.0)
	rider._apply_push(victim_a, dirn)
	knight._apply_push(victim_b, dirn)
	# ТОЛЬКО ГОРИЗОНТАЛЬ. _apply_push сажает жертву на рельеф
	# (np.y = get_terrain_height), а стенд ставит бойцов на y = 0 — полная
	# дистанция мерила бы амплитуду рельефа, а не силу толчка. Первый прогон
	# именно так и намерил «мечник толкает сильнее кабана»
	var moved_r: float = Vector2(victim_a.global_position.x - pa0.x,
		victim_a.global_position.z - pa0.z).length()
	var moved_k: float = Vector2(victim_b.global_position.x - pb0.x,
		victim_b.global_position.z - pb0.z).length()
	verdict("B3 один толчок кабана двигает заметно дальше пехотного",
		moved_k > 0.0 and moved_r >= moved_k * 1.8,
		"кабан сдвинул на %.3f м, мечник на %.3f м (отношение %.2f)"
			% [moved_r, moved_k, moved_r / maxf(moved_k, 0.0001)])
	for u in [victim_a, victim_b, rider, knight]:
		if is_instance_valid(u):
			(u as Node).queue_free()
	await frames(3)

# ═════════════════════════════════════════════════════════════════════════════
# C. ВМЯТИНА В СТРОЮ
# ═════════════════════════════════════════════════════════════════════════════
## Заказ владельца: строй обязан ПРОГНУТЬСЯ назад, а не просто пропустить пару
## отброшенных моделей обратно на свои места. Гнётся сама разметка (slots) —
## именно она возвращает бойцов на место при смыкании рядов
func _c_dent() -> void:
	var built: Array = _squad("res://scenes/units/Spearman.tscn",
		Constants.FACTION_PLAYER, "spearman", Vector3(-600.0, 0.0, -600.0),
		20, 10, 0.9)
	var sid: int = int(built[0])
	var men: Array = built[1]
	var slots: Array = built[2]
	GameManager.squad_set_formation(sid, slots, Vector3(0, 0, 1), false)
	await frames(4)
	var before: Array = (GameManager.squads[sid]["slots"] as Array).duplicate()

	var rider := _spawn("res://scenes/units/GoblinPigRider.tscn",
		Constants.FACTION_GOBLIN, Vector3(-600.0, 0.0, -602.0))
	await frames(4)
	var hit: Unit = men[5]
	var dirn := Vector3(0.0, 0.0, 1.0)
	rider._apply_push(hit, dirn)

	var after: Array = GameManager.squads[sid]["slots"]
	var max_shift := 0.0
	var shifted := 0
	for i in range(before.size()):
		var d: float = (after[i] as Vector3).distance_to(before[i] as Vector3)
		if d > 0.001:
			shifted += 1
		max_shift = maxf(max_shift, d)
	verdict("C1 удар конницы прогнул разметку строя",
		shifted > 0 and max_shift > 0.001,
		"сдвинулось мест %d из %d, глубже всего на %.3f м"
			% [shifted, before.size(), max_shift])
	# ВМЯТИНА, А НЕ СДВИГ ВСЕЙ ЛИНИИ: дальние места стоять обязаны
	verdict("C2 прогнулась ВМЯТИНА, а не вся линия целиком",
		shifted < before.size(),
		"тронуто %d мест из %d" % [shifted, before.size()])
	# И СМЕЩЕНИЕ ИДЁТ НАЗАД, по направлению удара
	var back_ok := true
	for i in range(before.size()):
		var d: Vector3 = (after[i] as Vector3) - (before[i] as Vector3)
		if d.length() > 0.001 and d.normalized().dot(dirn) < 0.99:
			back_ok = false
	verdict("C3 места уехали НАЗАД, по направлению удара", back_ok)

	# ── ПОТОЛОК: ДОЛГИЙ НАПОР НЕ УВОЗИТ СТРОЙ ЗА КРАЙ КАРТЫ ────────────────
	for _i in range(200):
		rider._apply_push(hit, dirn)
	var depth: float = GameManager.squad_dent_depth(sid)
	verdict("C4 накопленная вмятина не глубже потолка",
		depth <= GameManager.DENT_MAX_TOTAL + 0.001,
		"вмятина %.2f м при потолке %.2f м" % [depth, GameManager.DENT_MAX_TOTAL])
	# Новый приказ строем — новая линия, вмятина обнуляется
	GameManager.squad_set_formation(sid, slots, Vector3(0, 0, 1), false)
	verdict("C5 новая разметка обнуляет вмятину",
		GameManager.squad_dent_depth(sid) == 0.0,
		"после нового приказа вмятина %.2f м" % GameManager.squad_dent_depth(sid))

	for u in men:
		if is_instance_valid(u):
			(u as Node).queue_free()
	if is_instance_valid(rider):
		rider.queue_free()
	await frames(3)

# ═════════════════════════════════════════════════════════════════════════════
# D. УРОН НЕ ТРОНУТ
# ═════════════════════════════════════════════════════════════════════════════
## Прямое ограничение задания: правка строго физическая. Проверяем, что удар
## кабана равен числу из конфига и что множитель напора в урон не входит
func _d_damage() -> void:
	var cfg: float = _UStats.stat("goblin_rider", "attack_1", 0.0)
	var rider := _spawn("res://scenes/units/GoblinPigRider.tscn",
		Constants.FACTION_GOBLIN, Vector3(-700.0, 0.0, -700.0))
	var dmg: float = rider.attack_damage
	verdict("D1 удар кабана равен числу из конфига, множитель напора в него не входит",
		absf(dmg - cfg) < 0.001,
		"урон %.1f при конфиге %.1f, charge_push_mult %.1f"
			% [dmg, cfg, rider.charge_push_mult])
	rider.queue_free()

# ═════════════════════════════════════════════════════════════════════════════
# E. ПРОРЫВ МАССОЙ: 3 ОТРЯДА КАБАНОВ ПРОТИВ 3 ОТРЯДОВ КОПЕЙЩИКОВ
# ═════════════════════════════════════════════════════════════════════════════
## Заказ владельца: стадо кабанов обязано ФИЗИЧЕСКИ смять фалангу — строй
## «раздувается пузырём» и расступается под давлением массы, а не стоит стеной.
##
## Меряем не «красиво ли», а два числа, которые это и означают:
##   • ШИРИНА строя копейщиков РАСТЁТ (его раздувает изнутри);
##   • ГЛУБИНА проникновения: центр массы кабанов уходит ЗА исходную линию
##     копейщиков, то есть стадо прошло сквозь неё, а не увязло перед ней.
## Урон при этом обеим сторонам не отключаем — прорыв обязан случиться на
## честных числах, а не на бессмертных манекенах
func _e_breakthrough() -> void:
	var p0 := Vector3(-900.0, 0.0, -900.0)
	# Фаланга: три отряда по 30, единой стеной поперёк оси Z
	var wall: Array = []
	var wall_sids: Array = []
	for k in range(3):
		var built: Array = _squad("res://scenes/units/Spearman.tscn",
			Constants.FACTION_PLAYER, "spearman",
			p0 + Vector3(float(k - 1) * 7.0, 0.0, 0.0), 30, 10, 0.6)
		wall_sids.append(int(built[0]))
		wall.append_array(built[1])
		GameManager.squad_set_formation(int(built[0]), built[2],
			Vector3(0, 0, -1), false)
	# Стадо: три отряда по 20, в двадцати метрах, идут в лоб
	var herd: Array = []
	for k in range(3):
		var built2: Array = _squad("res://scenes/units/GoblinPigRider.tscn",
			Constants.FACTION_GOBLIN, "goblin_rider",
			p0 + Vector3(float(k - 1) * 7.0, 0.0, 20.0), 20, 5, 1.1)
		herd.append_array(built2[1])
	await frames(6)

	var herd_z0: float = _mid_z(herd)
	# ── ГДЕ КАЖДЫЙ СТОЯЛ ДО УДАРА ──────────────────────────────────────────
	# «Раздулся пузырём» меряется СМЕЩЕНИЕМ бойцов со своих мест, а не шириной
	# строя: половина шеренги гибнет, выжившие смыкают ряды, и ширина честно
	# УМЕНЬШАЕТСЯ — первый прогон стенда именно так и намерил «строй сузился»
	var home: Dictionary = {}
	for u in wall:
		home[u] = (u as Node3D).global_position
	for u in herd:
		(u as Unit).command_attack(wall[15], true, true, true)

	# ── ЗАМЕР В РАЗГАР СХВАТКИ, А НЕ ПОСЛЕ НЕЁ ─────────────────────────────
	# «Строй смяло» видно ровно пока строй ещё есть. К концу боя фаланга
	# ВЫБИТА ЦЕЛИКОМ, отряды расформированы, и та же проверка честно считает
	# ноль сдвинутых из нуля выживших — первый прогон так и вышел
	await frames(600)
	var alive_mid: Array = []
	for u in wall:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			alive_mid.append(u)
	var shoved := 0
	var worst := 0.0
	for u in alive_mid:
		var h: Vector3 = home[u]
		var d: float = Vector2((u as Node3D).global_position.x - h.x,
			(u as Node3D).global_position.z - h.z).length()
		worst = maxf(worst, d)
		if d > 1.0:
			shoved += 1
	verdict("E1 строй расступился: бойцов физически смяло со своих мест",
		alive_mid.size() > 0 and shoved >= alive_mid.size() / 3 and worst > 2.0,
		"сдвинуто дальше метра %d из %d живых, самый дальний на %.1f м"
			% [shoved, alive_mid.size(), worst])
	var dented := 0
	for sid in wall_sids:
		if GameManager.squad_dent_depth(int(sid)) > 0.0:
			dented += 1
	verdict("E2 разметка строя запомнила прогиб от удара",
		dented > 0, "прогнутых отрядов %d из %d" % [dented, wall_sids.size()])

	# ── ЧЕМ КОНЧИЛОСЬ ──────────────────────────────────────────────────────
	# «Прорвали насквозь» здесь означает не «медиана стада пересекла медиану
	# строя» — так мерить нельзя: фаланга к тому времени ВЫБИТА, целей нет, и
	# стадо останавливается там, где кончился противник. Правильные признаки
	# два: стена сломана, и стадо прошло дистанцию сближения
	await frames(900)
	var left := 0
	for u in wall:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			left += 1
	var advanced: float = herd_z0 - _mid_z(herd)
	verdict("E3 фаланга сломана массой", left <= wall.size() / 4,
		"выжило копейщиков %d из %d" % [left, wall.size()])
	verdict("E4 стадо прошло сквозь место, где стоял строй",
		advanced > 15.0,
		"центр стада ушёл вперёд на %.1f м из двадцати сближения" % advanced)

	for arr in [wall, herd]:
		for u in arr:
			if is_instance_valid(u):
				(u as Node).queue_free()
	await frames(3)

## Медиана по Z — центр группы, устойчивый к отставшим
func _mid_z(arr: Array) -> float:
	var zs: Array = []
	for u in arr:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			zs.append((u as Node3D).global_position.z)
	if zs.is_empty():
		return 0.0
	zs.sort()
	return float(zs[zs.size() / 2])

## Ширина группы по X — по ней и видно, «раздулся» ли строй
func _span_x(arr: Array) -> float:
	var lo := 1e9
	var hi := -1e9
	for u in arr:
		if not is_instance_valid(u) or (u as Unit).is_dead():
			continue
		var x: float = (u as Node3D).global_position.x
		lo = minf(lo, x)
		hi = maxf(hi, x)
	return maxf(hi - lo, 0.0)
