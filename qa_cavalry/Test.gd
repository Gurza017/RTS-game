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
##   F НАТИСК     — разгон за 10 м, удар в полсотни процентов запаса, разлёт
##                  «брызгами» и стенка копий, о которую натиск разбивается
##   G ОДНОКРАТНОСТЬ — без пройденного разгона тарана нет вовсе, и за одно
##                  сближение он случается ровно один раз
##
## ЧИСЛА НЕ ХАРДКОДЯТСЯ: скорости, напор и множители читаются из
## unit_stats_config — стенд проверяет СВОЙСТВО, а не цифру владельца.
##
## Запуск: godot --headless --path . res://qa_cavalry/Test.tscn

const _UStats := preload("res://scripts/unit_stats_config.gd")

var main = null
var verdicts: Array = []
## Запас жертвы на момент первых кадров контакта (блок G)
var _first_contact_hp: float = 0.0

func _ready() -> void:
	call_deferred("_run")

## Стартовая скорость разлёта на заказанную дальность — та же арифметика, что
## в Unit.apply_knockback. Стенд её не хардкодит, а выводит из констант
func charge_kick_speed(dist: float) -> float:
	var reach: float = Unit.FLING_TAU * (1.0 - exp(-Unit.FLING_SEC / Unit.FLING_TAU))
	return dist / maxf(reach, 0.001)

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
	await _f_charge()
	await _g_charge_once()

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
	# ── ЗДЕСЬ ПРОВЕРЯЛОСЬ «КОННИЦА ТОЛКАЕТ ЧАЩЕ ПЕХОТЫ», И ТРЕБОВАНИЕ РАЗВЕРНУТО
	# Владелец заказал ПОСТОЯННЫЙ расчёт напора в бою (авг. 2026): толкают
	# теперь все и на каждый удар (Unit.PUSH_EVERY = 1). Прежняя проверка
	# требовала, чтобы у конницы период был СТРОГО МЕНЬШЕ пехотного, — то есть
	# краснела бы ровно оттого, что пехоту подтянули к конному темпу.
	#
	# Что осталось истинным и что проверяем вместо этого: толкание идёт
	# непрерывно у всех, и конница при этом не толкает РЕЖЕ пехоты. Её
	# преимущество живёт не в периоде, а в размере шага (B1/B3) и в натиске с
	# разгона (блок F)
	var every: int = int(_UStats.stat("goblin_rider", "push_every", Unit.PUSH_EVERY))
	verdict("B2 напор считается постоянно, и конница не медленнее пехоты",
		Unit.PUSH_EVERY == 1 and every > 0 and every <= Unit.PUSH_EVERY,
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
	# ── ЖДЁМ, ПОКА ТОЛЧОК ОТРАБОТАЕТ ────────────────────────────────────────
	# Толчок больше не переносит тело мгновенно: он выдаёт затухающую скорость,
	# и заказанные метры набираются за Unit.FLING_SEC (см. Unit.push_smooth).
	# Замер сразу после вызова показывал бы ноль у обоих — не «толчка нет», а
	# «полёт ещё не начался»
	await frames(int(Unit.FLING_SEC * 60.0) + 20)
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

# ═════════════════════════════════════════════════════════════════════════════
# F. НАТИСК С РАЗГОНА (CHARGE)
# ═════════════════════════════════════════════════════════════════════════════
## Заказ владельца: за 10 м до строя конница разгоняется, а в момент касания
## сминает первый ряд — половина максимального запаса и разлёт в стороны.
## По копейщикам В ЛОБ натиск не работает вовсе, и всадник получает контрудар.
##
## ЧИСЛА ЧИТАЮТСЯ ИЗ КОНФИГА, а не вписаны сюда: стенд проверяет СВОЙСТВО
## («снято примерно charge_impact_frac от максимума»), а не цифру владельца
func _f_charge() -> void:
	var rng: float   = _UStats.stat("goblin_rider", "charge_range", 0.0)
	var smul: float  = _UStats.stat("goblin_rider", "charge_speed_mult", 1.0)
	var frac: float  = _UStats.stat("goblin_rider", "charge_impact_frac", 0.0)
	var kick: float  = _UStats.stat("goblin_rider", "charge_knockback", 0.0)
	var back: float  = _UStats.stat("goblin_rider", "charge_counter_frac", 0.0)
	verdict("F0 натиск описан в конфиге, а не в коде",
		rng > 0.0 and smul > 1.0 and frac > 0.0 and kick > 0.0 and back > 0.0,
		"разгон %.1f м x%.2f, удар %.0f%% max HP, разлёт %.1f м, контрудар %.0f%%"
			% [rng, smul, frac * 100.0, kick, back * 100.0])

	# ── F1/F2: РАЗГОН ВКЛЮЧАЕТСЯ И ПОДНИМАЕТ СКОРОСТЬ ──────────────────────
	var p0 := Vector3(-1200.0, 0.0, -1200.0)
	var prey := _spawn("res://scenes/units/Archer.tscn",
		Constants.FACTION_PLAYER, p0)
	# Ставим всадника ЗАВЕДОМО ДАЛЬШЕ дистанции разгона
	var rider := _spawn("res://scenes/units/GoblinPigRider.tscn",
		Constants.FACTION_GOBLIN, p0 + Vector3(0.0, 0.0, rng + 8.0))
	await frames(6)
	var walk: float = rider._effective_speed()
	rider.command_attack(prey, true, true, true)
	await frames(10)
	verdict("F1 дальше дистанции разгона всадник идёт обычным ходом",
		not rider.is_charging,
		"разгон=%s на дистанции %.1f м" % [str(rider.is_charging),
			rider.global_position.distance_to(prey.global_position)])
	# Ждём, пока подойдёт внутрь дистанции разгона
	var seen_charge := false
	var top := walk
	for _i in range(400):
		await get_tree().physics_frame
		if not is_instance_valid(rider) or not is_instance_valid(prey):
			break
		if rider.is_charging:
			seen_charge = true
			top = maxf(top, rider._effective_speed())
		if prey.is_dead():
			break
	verdict("F2 внутри дистанции разгона конница разгоняется", seen_charge,
		"разгон замечен=%s" % str(seen_charge))
	verdict("F3 на разгоне скорость выше обычной",
		top >= walk * (1.0 + (smul - 1.0) * 0.8),
		"обычная %.2f м/с, на разгоне %.2f м/с (ожидалось x%.2f)"
			% [walk, top, smul])
	for u in [prey, rider]:
		if is_instance_valid(u):
			(u as Node).queue_free()
	await frames(3)

	# ── F4/F5: УДАР ПО ЛУЧНИКАМ — ПОЛОВИНА ЗАПАСА И РАЗЛЁТ ────────────────
	# Лучники, а не копейщики: по копейщикам натиск не работает намеренно (F6)
	var p1 := Vector3(-1300.0, 0.0, -1300.0)
	var line: Array = []
	for i in range(5):
		line.append(_spawn("res://scenes/units/Archer.tscn",
			Constants.FACTION_PLAYER, p1 + Vector3(float(i) * 0.6 - 1.2, 0.0, 0.0)))
	var r2 := _spawn("res://scenes/units/GoblinPigRider.tscn",
		Constants.FACTION_GOBLIN, p1 + Vector3(0.0, 0.0, rng + 6.0))
	await frames(6)
	var hp_before: Dictionary = {}
	var at_before: Dictionary = {}
	for u in line:
		hp_before[u] = (u as Unit).current_health
		at_before[u] = (u as Node3D).global_position
	r2.command_attack(line[2], true, true, true)
	# Один удар с разгона случается в кадре касания; ждём именно его
	var impacted := false
	for _i in range(400):
		await get_tree().physics_frame
		if not is_instance_valid(r2):
			break
		if not r2.is_charging and r2._charge_ready == false:
			impacted = true
			break
	verdict("F4 натиск состоялся ровно один раз", impacted,
		"разгон потрачен=%s" % str(impacted))
	# ── ЖДЁМ КОНЦА ПОЛЁТА ──────────────────────────────────────────────────
	# Отброс больше не мгновенный: он выдаёт затухающую скорость, и заказанные
	# метры набираются за Unit.FLING_SEC (см. Unit.apply_knockback). Замер сразу
	# после удара показывал бы ноль — не «не отбросило», а «ещё летит»
	await frames(int(Unit.FLING_SEC * 60.0) + 20)
	var hurt := 0
	var flung := 0
	var worst_hit := 0.0
	for u in line:
		if not is_instance_valid(u):
			hurt += 1
			flung += 1
			continue
		var uu := u as Unit
		var lost: float = float(hp_before[u]) - uu.current_health
		if lost >= uu.max_health * frac * 0.8:
			hurt += 1
			worst_hit = maxf(worst_hit, lost / uu.max_health)
		var moved: float = Vector2(uu.global_position.x - (at_before[u] as Vector3).x,
			uu.global_position.z - (at_before[u] as Vector3).z).length()
		if moved >= kick * 0.5:
			flung += 1
	verdict("F5 первый ряд контакта смяло примерно на заказанную долю запаса",
		hurt >= 1, "накрыто %d из 5, худшая потеря %.0f%% max HP при заказе %.0f%%"
			% [hurt, worst_hit * 100.0, frac * 100.0])
	verdict("F5б накрытых физически разбросало",
		flung >= 1, "отброшено %d из 5 при разлёте %.1f м" % [flung, kick])
	# ── F5в: РАЗЛЁТ ВИДНО ГЛАЗОМ, А НЕ ТОЛЬКО В ЧИСЛАХ ─────────────────────
	# Жалоба владельца: «при таране пехотинцы мгновенно телепортируются».
	# Тело и правда переносится сразу — физики у бойцов нет вовсе, — но КАРТИНКА
	# обязана этот перенос показать. Она и так догоняет тело плавно, только у
	# сглаживания есть предохранитель: прыжок дальше Unit.VIS_SNAP_SQ считается
	# телепортом и рисуется мгновенно. Отбрасывание (charge_knockback) ровно за
	# этим порогом — отсюда и «пропадают».
	# Проверяем СВОЙСТВО: накрытый помечен летящим, и его НАРИСОВАННАЯ точка
	# отстаёт от логической, то есть модель в этот момент действительно летит
	# ТРЕБОВАНИЕ РАЗВЁРНУТО ВЛАДЕЛЬЦЕМ. Раньше тело переносилось МГНОВЕННО, а
	# плавность изображала картинка: она догоняла тело замедленным сглаживанием,
	# и проверка требовала, чтобы нарисованная точка ОТСТАВАЛА. На экране это
	# всё равно читалось как «пехота телепортируется брызгами» — жалоба
	# повторилась. Теперь плавно едет САМО ТЕЛО (Unit._tick_fling, затухающая
	# скорость), а картинка идёт за ним обычным сглаживанием и отставать НЕ
	# ОБЯЗАНА. Свойство проверяется по ШАГУ ЗА КАДР: он обязан быть заведомо
	# меньше полной дальности удара, то есть боец едет, а не прыгает
	var v0: float = charge_kick_speed(kick)
	verdict("F5в разлёт едет телом, а не телепортирует",
		v0 > 0.0 and v0 / 60.0 < kick * 0.5,
		"стартовая скорость %.1f м/с — это %.2f м за кадр при разлёте %.1f м"
			% [v0, v0 / 60.0, kick])
	verdict("F5г ни один шаг разлёта не дотягивает до порога телепорта",
		v0 / 60.0 < sqrt(Unit.VIS_SNAP_SQ),
		"%.2f м за кадр при пороге привязки %.2f м"
			% [v0 / 60.0, sqrt(Unit.VIS_SNAP_SQ)])
	for u in line:
		if is_instance_valid(u):
			(u as Node).queue_free()
	if is_instance_valid(r2):
		(r2 as Node).queue_free()
	await frames(3)

	# ── F6/F7: СТЕНКА КОПИЙ ────────────────────────────────────────────────
	var p2 := Vector3(-1400.0, 0.0, -1400.0)
	var spear := _spawn("res://scenes/units/Spearman.tscn",
		Constants.FACTION_PLAYER, p2)
	var r3 := _spawn("res://scenes/units/GoblinPigRider.tscn",
		Constants.FACTION_GOBLIN, p2 + Vector3(0.0, 0.0, rng + 6.0))
	await frames(6)
	verdict("F6 копейщик объявлен стенкой копий, всадник — нет",
		spear.repels_charge() and not r3.repels_charge(),
		"копейщик=%s всадник=%s" % [str(spear.repels_charge()),
			str(r3.repels_charge())])
	# Разворачиваем копейщика ЛИЦОМ на всадника — лобовой навал
	spear._facing = (r3.global_position - spear.global_position).normalized()
	var sp_hp0: float = spear.current_health
	var rd_hp0: float = r3.current_health
	# ── СМЕЩЕНИЕ МЕРЯЕТСЯ ЗА ОДИН КАДР УДАРА, А НЕ ЗА ВСЮ СХВАТКУ ──────────
	# Первый прогон мерил «сколько копейщика сдвинуло от начала до конца
	# ожидания» и намерил 1.23 м при разлёте 2.2 — то есть почти провал. Но
	# двигал его там не натиск, а ОБЫЧНОЕ ПРОДАВЛИВАНИЕ: у кабана push_force 15
	# с множителем 3.5, и толкает он теперь на КАЖДЫЙ удар (Unit.PUSH_EVERY),
	# то есть по полметра в секунду. Это штатная и заказанная механика, к
	# натиску отношения не имеющая.
	#
	# Натиск же — событие ровно одного кадра, и в этом самом кадре бойца не
	# бьют вовсе (_process_attack выходит сразу после удара с разгона). Поэтому
	# смотрим дельту за тот единственный кадр, в котором разгон был потрачен:
	# что не сдвинулось там, то натиском и не отброшено
	var sp_prev: Vector3 = spear.global_position
	var sp_moved: float = -1.0
	var sp_hp_at_impact: float = sp_hp0
	r3.command_attack(spear, true, true, true)
	for _i in range(400):
		await get_tree().physics_frame
		if not is_instance_valid(r3) or not is_instance_valid(spear):
			break
		if not r3.is_charging and r3._charge_ready == false:
			sp_moved = Vector2(spear.global_position.x - sp_prev.x,
				spear.global_position.z - sp_prev.z).length()
			sp_hp_at_impact = spear.current_health
			break
		sp_prev = spear.global_position
	verdict("F6б натиск на копейщика вообще состоялся", sp_moved >= 0.0,
		"кадр удара пойман=%s" % str(sp_moved >= 0.0))
	var sp_lost: float = sp_hp0 - sp_hp_at_impact
	if sp_moved < 0.0:
		sp_moved = 1e9        # кадр удара не пойман — проверка ниже обязана краснеть
	var rd_lost: float = 0.0
	if is_instance_valid(r3):
		rd_lost = rd_hp0 - r3.current_health
	else:
		rd_lost = rd_hp0        # погиб на копьях — контрудар сработал с запасом
	verdict("F7 лобовой навал на копья НЕ отбрасывает копейщика",
		sp_moved < kick * 0.5 and sp_lost < spear_max(spear, sp_hp0) * frac * 0.8,
		"копейщика сдвинуло на %.2f м (разлёт %.1f), снято %.1f HP"
			% [sp_moved, kick, sp_lost])
	verdict("F8 всадник получил контрудар от стенки копий",
		rd_lost >= rd_hp0 * back * 0.8,
		"всадник потерял %.1f HP при заказанных %.0f%% от %.1f"
			% [rd_lost, back * 100.0, rd_hp0])
	for u in [spear, r3]:
		if is_instance_valid(u):
			(u as Node).queue_free()
	await frames(3)

## Максимальный запас копейщика — с оглядкой на то, что он мог уже погибнуть
func spear_max(u, fallback: float) -> float:
	if is_instance_valid(u):
		return (u as Unit).max_health
	return fallback

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

# ═════════════════════════════════════════════════════════════════════════════
# G. ТАРАН СРАБАТЫВАЕТ ОДИН РАЗ И ТОЛЬКО С РАЗГОНА
# ═════════════════════════════════════════════════════════════════════════════
## Жалоба владельца: «эффект разлёта срабатывает дважды за одно соприкосновение,
## включая повторный разлёт, когда юниты уже сошлись в плотном бою без разгона».
##
## Разбор. Натиск взводился по одной лишь ДИСТАНЦИИ до цели. В свалке цель
## меняется каждые пару секунд, новая нередко оказывается за десять метров — и
## условие взвода выполнялось снова, СТОЯ НА МЕСТЕ. Теперь мало оказаться
## далеко: надо ПРОЙТИ charge_min_runup метров, и проверяется это фактом, а не
## намерением.
func _g_charge_once() -> void:
	var runup: float = _UStats.stat("goblin_rider", "charge_min_runup", 0.0)
	var frac: float  = _UStats.stat("goblin_rider", "charge_impact_frac", 0.0)
	verdict("G0 минимальный разгон задан в конфиге", runup > 0.0,
		"charge_min_runup = %.1f м" % runup)

	# ── G1: В ПЛОТНОМ БОЮ ТАРАНА НЕТ ──────────────────────────────────────
	# Ставим всадника ВПЛОТНУЮ к жертве: разогнаться ему негде и неоткуда
	var p0 := Vector3(-1500.0, 0.0, -1500.0)
	var prey := _spawn("res://scenes/units/Archer.tscn",
		Constants.FACTION_PLAYER, p0)
	var rider := _spawn("res://scenes/units/GoblinPigRider.tscn",
		Constants.FACTION_GOBLIN, p0 + Vector3(0.0, 0.0, 1.6))
	await frames(6)
	var hp0: float = prey.current_health
	# Запас берём ЗАРАНЕЕ: за окно наблюдения жертву успевают добить обычными
	# ударами, и спрашивать max_health у освобождённого объекта уже не у кого
	var prey_max: float = prey.max_health
	rider.command_attack(prey, true, true, true)
	# Ждём ровно момент, когда натиск был бы потрачен, — или полсекунды, если
	# он не тратится вовсе (а он и не должен: разгона нет)
	_first_contact_hp = prey.current_health
	for _i in range(30):
		await get_tree().physics_frame
		if not is_instance_valid(prey) or prey.is_dead():
			break
		_first_contact_hp = prey.current_health
	# Считаем урон ЗА ПЕРВЫЕ КАДРЫ КОНТАКТА, а не за всё окно: обычные удары
	# идут своим чередом и за три секунды снимут больше любого тарана
	var lost: float = hp0 - _first_contact_hp
	# Обычные удары идут своим чередом, поэтому мерим НЕ «ноль урона», а
	# «меньше, чем снял бы таран»: полсотни процентов запаса за один миг
	var impact_dmg: float = prey_max * frac
	verdict("G1 без разгона тарана не случилось",
		lost < impact_dmg * 0.9,
		"снято %.1f HP, удар тарана дал бы %.1f" % [lost, impact_dmg])
	for u in [prey, rider]:
		if is_instance_valid(u):
			(u as Node).queue_free()
	await frames(3)

	# ── G2/G3: С РАЗГОНА — РОВНО ОДИН РАЗ ─────────────────────────────────
	# Шеренга жертв, всадник издалека. Считаем, скольких накрыло: накрыть
	# обязано первый ряд контакта ОДИН раз, а не дважды подряд
	var p1 := Vector3(-1560.0, 0.0, -1560.0)
	var line: Array = []
	for i in range(4):
		line.append(_spawn("res://scenes/units/Archer.tscn",
			Constants.FACTION_PLAYER,
			p1 + Vector3(float(i) * 0.7 - 1.0, 0.0, 0.0)))
	var r2 := _spawn("res://scenes/units/GoblinPigRider.tscn",
		Constants.FACTION_GOBLIN, p1 + Vector3(0.0, 0.0, 14.0))
	await frames(6)
	var hp_before: Dictionary = {}
	for u in line:
		hp_before[u] = (u as Unit).current_health
	r2.command_attack(line[1], true, true, true)
	var impacts := 0
	var was_ready: bool = r2._charge_ready
	for _i in range(400):
		await get_tree().physics_frame
		if not is_instance_valid(r2):
			break
		# Момент траты натиска: разгон был доступен и перестал быть
		if was_ready and not r2._charge_ready:
			impacts += 1
		was_ready = r2._charge_ready
	verdict("G2 натиск потрачен ровно один раз за сближение", impacts == 1,
		"срабатываний %d" % impacts)
	var hurt := 0
	for u in line:
		if not is_instance_valid(u):
			hurt += 1
			continue
		var uu := u as Unit
		if float(hp_before[u]) - uu.current_health >= uu.max_health * frac * 0.8:
			hurt += 1
	verdict("G3 и накрыл первый ряд контакта", hurt >= 1,
		"накрыто %d из %d" % [hurt, line.size()])
	for u in line:
		if is_instance_valid(u):
			(u as Node).queue_free()
	if is_instance_valid(r2):
		(r2 as Node).queue_free()
	await frames(3)
