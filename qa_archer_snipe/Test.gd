extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_archer_snipe — ДРЕВО ЛУЧНИКА И СНАЙПЕРСКИЙ ВЫСТРЕЛ (ТЗ 14.09.2026)
## ═══════════════════════════════════════════════════════════════════════════
##   A КУЗНИЦА    — база 15 м, ряд A доводит до 17.5 / 20 / 25 и раздаёт уже
##                  стоящим; ряд B режет перезарядку на 10/20/30 %;
##                  бронепробитие 25/50 % (4a/5a) читается из take_damage;
##                  «Гроза великанов» ×1.5/×2.0 (4b/5b) по туше; колонка D
##                  открывается рядом, 2d даёт 3 снайпера, 3d — 5.
##   B СНАЙПЕРЫ   — отряд из 30 лучников против трёх ОТСТУПАЮЩИХ гоблинов за
##                  дальностью отряда: три прямых быстрых стрелы уходят
##                  «раз-два-три» (разными кадрами), в трёх разных гоблинов,
##                  каждый гибнет с одной стрелы, стрела в голове тела, звук
##                  свой.
##   C БЕЗ ОДИНОЧЕК — отступающих нет: снайперы выбивают три РАЗНЫЕ модели
##                  вражеского отряда.
##   D КРУПНЫЕ    — туша не гибнет с одной снайперской стрелы; добивающая
##                  стрела остаётся в голове.
## Числа — из конфига и полей (правило 10), ожидание — физкадрами (правило 11).
## Запуск: godot --headless --path . res://qa_archer_snipe/Test.tscn

const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _Forge := preload("res://scripts/forge_config.gd")
const _ArrowS := preload("res://scripts/Arrow.gd")
const _ArcherS := preload("res://scripts/Archer.gd")

const F := Constants.FACTION_PLAYER
const GF := Constants.FACTION_GOBLIN

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	var t := get_tree().create_timer(400.0)
	t.timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 400 с")
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
	print("\n═════ ИТОГ qa_archer_snipe: прошло %d, провалов: %d ═════" % [
		_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _spawn(kind: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[kind].instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

## Отряд блоком: cols колонок по оси Z, ряды назад по −X
func _squad(kind: String, fac: int, at: Vector3, n: int, cols: int = 6) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var men: Array = []
	for i in range(n):
		var px: float = at.x - float(i / cols) * 0.9
		var pz: float = at.z + float(i % cols) * 0.7 - float(cols - 1) * 0.35
		var u: Unit = _spawn(kind, fac, Vector3(px, 0.0, pz))
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return [sid, men]

func _kill_all(arr: Array) -> void:
	for u in arr:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			(u as Unit).take_damage(1.0e12)

func _research(cell: String) -> bool:
	return GameManager.research_upgrade(F, _Forge.node_id("archer", cell))

func _alive(arr: Array) -> int:
	var n := 0
	for u in arr:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			n += 1
	return n

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	if main.get("gnoll_ai") != null:
		main.gnoll_ai.set_process(false)
	GameManager.world_bounds_enabled = false
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	AudioManager.sfx_trace = true
	# Стартовая бригада и орда партии — прочь с площадки
	for n in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(n) and n is Unit:
			(n as Unit).take_damage(1.0e12)
	await pframes(6)
	# Площадка вне карты: своя, сухая, без леса и стволов
	await _a_forge()
	await _b_snipers()
	await _c_no_loners()
	await _d_giants()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
# A. КУЗНИЦА
# ═════════════════════════════════════════════════════════════════════════════
func _a_forge() -> void:
	print("\n═════ A. ДРЕВО ЛУЧНИКА В КУЗНИЦЕ ═════")
	var base_r: float = _UCfg.stat("archer", "attack_range", 0.0)
	var cap_r: float = _UCfg.stat("archer", "attack_range_cap", 0.0)
	verdict("A1 базовая дальность 15 м, потолок 25", base_r == 15.0 and cap_r >= 25.0,
		"база %.1f, потолок %.1f" % [base_r, cap_r])
	var a: Unit = _spawn("archer", F, Vector3(300.0, 0.0, 300.0))
	await pframes(2)
	verdict("A2 стоящий на карте стреляет на базу", absf(a.attack_range - base_r) < 0.01,
		"%.1f" % a.attack_range)
	var cd0: float = a._effective_cooldown()
	# ── ряд A: дальность ──────────────────────────────────────────────────
	verdict("A3 узел 1a исследуется", _research("1a"))
	await pframes(1)
	verdict("A3б +2.5 м раздаётся стоящему", absf(a.attack_range - (base_r + 2.5)) < 0.01,
		"%.1f" % a.attack_range)
	_research("2a")
	await pframes(1)
	verdict("A3в 2a: 20 м", absf(a.attack_range - (base_r + 5.0)) < 0.01, "%.1f" % a.attack_range)
	_research("3a")
	await pframes(1)
	verdict("A3г 3a: 25 м", absf(a.attack_range - (base_r + 10.0)) < 0.01, "%.1f" % a.attack_range)
	var fresh: Unit = _spawn("archer", F, Vector3(302.0, 0.0, 300.0))
	await pframes(1)
	verdict("A3д новорождённый получает те же 25 м", absf(fresh.attack_range - 25.0) < 0.01,
		"%.1f" % fresh.attack_range)
	# ── ряд B: темп ───────────────────────────────────────────────────────
	_research("1b")
	var cd1: float = a._effective_cooldown()
	verdict("A4 1b: перезарядка −10 %", absf(cd1 / cd0 - 0.9) < 0.02, "%.3f → %.3f" % [cd0, cd1])
	_research("2b")
	_research("3b")
	var cd3: float = a._effective_cooldown()
	verdict("A4б 3b: перезарядка −30 % всего", absf(cd3 / cd0 - 0.7) < 0.02, "%.3f → %.3f" % [cd0, cd3])
	# ── ряд C: урон ───────────────────────────────────────────────────────
	_research("1c"); _research("2c"); _research("3c")
	var atk: float = GameManager.unit_bonus(F, "archer", "bonus_attack")
	verdict("A5 ряд C копит урон стрелы", atk >= 5.5, "+%.1f" % atk)
	# ── колонка D: ряд И предыдущий узел D открывают узел (ТЗ-B 19.09.2026:
	# колонка D идёт цепочкой у всех веток — 2d требует 1d) ─────────────
	var n2d: Dictionary = _Forge.get_node("archer_2d")
	verdict("A6 2d закрыт, пока не изучен 1d (цепочка D)", not GameManager.research_blockers(F, n2d).is_empty())
	verdict("A6а 1d (залп) исследуется", _research("1d"))
	verdict("A6 2d открыт после ряда 2 (A+B+C) и 1d", GameManager.research_blockers(F, n2d).is_empty())
	verdict("A6б 1d — залп, способность-режим", _Forge.is_toggle_ability(_Forge.get_node("archer_1d")))
	var sq: Array = _squad("archer", F, Vector3(320.0, 0.0, 320.0), 6)
	var sid: int = sq[0]
	verdict("A7 без 2d снайперов ноль", GameManager.squad_snipers(sid) == 0)
	verdict("A7б 2d исследуется", _research("2d"))
	verdict("A7в 2d: снайперов %d" % _UCfg.SNIPE_SQUAD_BASE,
		GameManager.squad_snipers(sid) == _UCfg.SNIPE_SQUAD_BASE, "%d" % GameManager.squad_snipers(sid))
	verdict("A7г 3d исследуется (ряд 3 изучен, 2d изучен)", _research("3d"))
	verdict("A7д 3d: снайперов 5", GameManager.squad_snipers(sid) == 5, "%d" % GameManager.squad_snipers(sid))
	await pframes(40)   # такт пересчёта статуса снайпера 0.5 с
	var snipers := 0
	var sn_range: float = 0.0
	for u in sq[1]:
		if (u as Archer).is_sniper():
			snipers += 1
			sn_range = (u as Unit).attack_range
	verdict("A7е в отряде из 6 — 5 снайперов, дальность ≥ %.0f" % _UCfg.SNIPE_RANGE,
		snipers == 5 and sn_range >= _UCfg.SNIPE_RANGE, "снайперов %d, дальность %.1f" % [snipers, sn_range])
	var cds: float = (sq[1][0] as Unit)._effective_cooldown()
	verdict("A7ж 3d: перезарядка снайпера короче обычной", cds < cd3 * 0.8, "%.3f против %.3f" % [cds, cd3])
	# ── бронепробитие ─────────────────────────────────────────────────────
	verdict("A8 4a исследуется", _research("4a"))
	var pen1: float = GameManager.squad_armor_pierce(a)
	_research("5a")
	var pen2: float = GameManager.squad_armor_pierce(a)
	verdict("A8б бронепробитие 25 % → 50 %", absf(pen1 - 0.25) < 0.01 and absf(pen2 - 0.5) < 0.01,
		"%.2f → %.2f" % [pen1, pen2])
	var g: Unit = _spawn("goblin_spearman", GF, Vector3(340.0, 0.0, 300.0))
	g.set_tick(false)
	await pframes(1)
	var hp_a: float = g.current_health
	g.take_damage(20.0, null)
	var d_plain: float = hp_a - g.current_health
	var hp_b: float = g.current_health
	g.take_damage(20.0, a)
	var d_pen: float = hp_b - g.current_health
	var def_g: float = g.defense + g.armor
	verdict("A8в удар лучника проходит сквозь броню больнее (защита цели %.0f)" % def_g,
		d_pen > d_plain + 0.01 and def_g > 0.0, "%.2f против %.2f" % [d_pen, d_plain])
	# ── гроза великанов ───────────────────────────────────────────────────
	var big: Unit = _spawn("big_goblin", GF, Vector3(350.0, 0.0, 300.0))
	big.set_tick(false)
	await pframes(1)
	var b0: float = big.current_health
	# Попадание снаряда ядра «здесь и сейчас» — тем же путём, что событие полёта
	GameManager.projectile_hit_now(big, 20.0, a, F)
	var dmg_a: float = b0 - big.current_health
	_research("4b"); _research("5b")
	var giant: float = GameManager.unit_bonus(F, "archer", "bonus_giant")
	verdict("A9 4b+5b: множитель по крупным ×2.0", absf(giant - 1.0) < 0.01, "+%.2f" % giant)
	var b1: float = big.current_health
	GameManager.projectile_hit_now(big, 20.0, a, F)
	var dmg_b: float = b1 - big.current_health
	verdict("A9б урон стрелы по туше удвоился", absf(dmg_b / maxf(dmg_a, 0.01) - 2.0) < 0.05,
		"%.1f → %.1f" % [dmg_a, dmg_b])
	verdict("A9в конница — крупная цель, пехота — нет",
		_spawn("goblin_rider", GF, Vector3(360.0, 0.0, 300.0)).giant_class() and not g.giant_class())
	_kill_all([a, fresh, g, big])
	_kill_all(sq[1])
	for n in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(n) and n is Unit and not (n as Unit).is_dead():
			(n as Unit).take_damage(1.0e12)
	await pframes(4)

# ═════════════════════════════════════════════════════════════════════════════
# B. СНАЙПЕРЫ ПРОТИВ ОТСТУПАЮЩИХ
# ═════════════════════════════════════════════════════════════════════════════
func _b_snipers() -> void:
	print("\n═════ B. ТРИ СНАЙПЕРА — ТРИ ОТСТУПАЮЩИХ ГОБЛИНА ═════")
	# Полное древо изучено в A: дальность отряда 25 (потолок), снайперов 5.
	# Чтобы разница «снайперы бьют дальше отряда» была видна, число снайперов
	# здесь не важно — проверяется сама механика; отряд из 30
	var sq: Array = _squad("archer", F, Vector3(400.0, 0.0, 400.0), 30)
	var sid: int = sq[0]
	await pframes(40)
	var snipers: Array = []
	for u in sq[1]:
		if (u as Archer).is_sniper():
			snipers.append(u)
	verdict("B1 снайперов в отряде из 30 — 5 (2d + 3d)", snipers.size() == 5, "%d" % snipers.size())
	# Три гоблина в 21 м впереди, ОТСТУПАЮТ (retreating), заморожены на месте
	var gobs: Array = []
	for i in range(3):
		var g: Unit = _spawn("goblin_spearman", GF, Vector3(421.0, 0.0, 400.0 + float(i - 1) * 3.0))
		g.begin_retreat()
		g.set_tick(false)
		gobs.append(g)
	await pframes(2)
	var shots0: int = _ArcherS.snipe_shots
	var pins0: int = _ArrowS.snipe_head_pins
	var fired0: int = GameManager.arrows_fired
	AudioManager.sfx_trace_counts.clear()
	var hp_full: bool = true
	for g in gobs:
		if (g as Unit).current_health < (g as Unit).max_health - 0.01:
			hp_full = false
	# Приказ атаки отряду — как ПКМ игрока
	for u in sq[1]:
		(u as Unit).command_attack(gobs[0], true, true)
	# Кадры выстрелов снайперов — для проверки «раз-два-три»
	var shot_frames: Array = []
	var last: int = shots0
	var straight_ok := true
	var fast_ok := true
	var snipe_seen := 0
	for f in range(60 * 4):
		await get_tree().physics_frame
		var now: int = _ArcherS.snipe_shots
		if now > last:
			for _k in range(now - last):
				shot_frames.append(f)
			last = now
		# Летящие снайперские стрелы: дуга ноль, скорость ×1.3. Снаряд без
		# узла (этап 3): полёт — запись ядра, читается flight_records
		for fr in GameManager.flight_records():
			if bool(fr["snipe"]):
				snipe_seen += 1
				if float(fr["arc"]) != 0.0:
					straight_ok = false
				if absf(float(fr["speed"]) - _UCfg.stat("archer", "arrow_speed", 0.0) * _UCfg.SNIPE_SPEED_MULT) > 0.01:
					fast_ok = false
		if _alive(gobs) == 0 and f > 90:
			break
	var shots: int = _ArcherS.snipe_shots - shots0
	verdict("B2 снайперы выстрелили (первый залп)", shots >= 3, "выстрелов %d" % shots)
	verdict("B3 снайперская стрела летит по прямой", snipe_seen > 0 and straight_ok,
		"замечено летящих %d" % snipe_seen)
	verdict("B3б …и на 30 %% быстрее обычной", snipe_seen > 0 and fast_ok)
	var span: int = 0
	if shot_frames.size() >= 3:
		span = int(shot_frames[2]) - int(shot_frames[0])
	verdict("B4 «раз-два-три»: три выстрела разными кадрами, разлёт ≥ %d кадров" % int(_UCfg.SNIPE_STAGGER_SEC * 2.0 * 60.0 * 0.8),
		shot_frames.size() >= 3 and span >= int(_UCfg.SNIPE_STAGGER_SEC * 2.0 * 60.0 * 0.8),
		"кадры %s" % str(shot_frames.slice(0, 5)))
	verdict("B5 все три гоблина мертвы — по одной стреле каждый",
		hp_full and _alive(gobs) == 0 and _ArrowS.snipe_head_pins - pins0 >= 3,
		"живых %d, стрел в голове %d" % [_alive(gobs), _ArrowS.snipe_head_pins - pins0])
	# СВОЙСТВО, А НЕ ИМЯ ФАЙЛА (правило 10): категория своя, и каждый файл,
	# который в ней сейчас настроен, обязан существовать — а не конкретный
	# снятый 15.09.2026 «snd_snipe_shot.wav» (был единственным на тот момент)
	var _snipe_files: Array = AudioManager.SFX_BANK.get("snipe_shot", [])
	var _snipe_files_ok: bool = not _snipe_files.is_empty()
	for _sf in _snipe_files:
		if not ResourceLoader.exists(AudioManager.sfx_path(String(_sf))):
			_snipe_files_ok = false
	verdict("B6 звук снайперского спуска свой (snipe_shot)",
		int(AudioManager.sfx_trace_counts.get("snipe_shot", 0)) >= 3
		and AudioManager.SFX_BANK.has("snipe_shot")
		and _snipe_files_ok,
		"сыграно %d" % int(AudioManager.sfx_trace_counts.get("snipe_shot", 0)))
	# Стрела в голове: позиция стрелы у точки головы тела
	# Узлы павших уже освобождены (corpse_ref живёт кадр смерти) — тела ищем
	# в слое тел по стороне и месту
	var head_ok := 0
	var head_worst: float = 0.0
	for body in GameManager.corpses._list:
		if int(body.faction) != GF or body.arrows.is_empty():
			continue
		if Vector2(body.pos.x - 421.0, body.pos.z - 400.0).length() > 8.0:
			continue
		var hs: Vector3 = GameManager.corpses.head_spot_of(body)
		for ar in body.arrows:
			# В теле лежит id записи ядра (стрела без узла) либо legacy-узел
			var ap: Vector3 = Vector3.INF
			if ar is int:
				ap = GameManager.stuck_arrow_pos(int(ar))
			elif is_instance_valid(ar):
				ap = ar.global_position
			if ap.x != INF:
				var dd: float = Vector2(ap.x - hs.x, ap.z - hs.z).length()
				head_worst = maxf(head_worst, dd)
				if dd < 0.25:
					head_ok += 1
	verdict("B7 стрела торчит в голове павшего (не дальше 0.25 м от точки головы)",
		head_ok >= 3, "в голове %d, худший %.2f м" % [head_ok, head_worst])
	_kill_all(sq[1])
	await pframes(4)

# ═════════════════════════════════════════════════════════════════════════════
# C. ОТСТУПАЮЩИХ НЕТ — ВЫБИВАЮТ РАЗНЫЕ МОДЕЛИ ОТРЯДА
# ═════════════════════════════════════════════════════════════════════════════
func _c_no_loners() -> void:
	print("\n═════ C. БЕЗ ОДИНОЧЕК: РАЗНЫЕ МОДЕЛИ ЦЕЛЕВОГО ОТРЯДА ═════")
	var sq: Array = _squad("archer", F, Vector3(500.0, 0.0, 500.0), 30)
	await pframes(40)
	var foe: Array = _squad("goblin_spearman", GF, Vector3(519.0, 0.0, 500.0), 12, 4)
	for g in foe[1]:
		(g as Unit).set_tick(false)
	await pframes(2)
	var pins0: int = _ArrowS.snipe_head_pins
	var shots0: int = _ArcherS.snipe_shots
	for u in sq[1]:
		(u as Unit).command_attack(foe[1][0], true, true)
	for _f in range(60 * 3):
		await get_tree().physics_frame
		if _ArcherS.snipe_shots - shots0 >= 5 and _ArrowS.snipe_head_pins - pins0 >= 3:
			break
	await pframes(60)
	var dead := 0
	for g in foe[1]:
		if not is_instance_valid(g) or (g as Unit).is_dead():
			dead += 1
	verdict("C1 снайперы выбили не меньше трёх РАЗНЫХ моделей отряда",
		_ArrowS.snipe_head_pins - pins0 >= 3 and dead >= 3,
		"стрел в голове %d, мёртвых %d" % [_ArrowS.snipe_head_pins - pins0, dead])
	verdict("C2 заявка на цель: одна снайперская стрела — один труп",
		_ArrowS.snipe_head_pins - pins0 >= mini(_ArcherS.snipe_shots - shots0, 5) - 1,
		"выстрелов %d, стрел в голове %d" % [_ArcherS.snipe_shots - shots0, _ArrowS.snipe_head_pins - pins0])
	_kill_all(sq[1])
	_kill_all(foe[1])
	await pframes(4)

# ═════════════════════════════════════════════════════════════════════════════
# D. КРУПНЫЕ ЦЕЛИ
# ═════════════════════════════════════════════════════════════════════════════
func _d_giants() -> void:
	print("\n═════ D. ТУША: НЕ С ОДНОЙ СТРЕЛЫ, ДОБИВАЮЩАЯ — В ГОЛОВУ ═════")
	var sq: Array = _squad("archer", F, Vector3(600.0, 0.0, 600.0), 6)
	await pframes(40)
	var a: Unit = sq[1][0]
	verdict("D0 стрелок — снайпер", (a as Archer).is_sniper())
	var big: Unit = _spawn("big_goblin", GF, Vector3(615.0, 0.0, 600.0))
	big.set_tick(false)
	await pframes(1)
	var hp0: float = big.current_health
	GameManager.projectile_hit_now(big, 20.0, a, F, true)
	verdict("D1 туша жива после снайперской стрелы (не one-shot)",
		is_instance_valid(big) and not big.is_dead() and big.current_health < hp0,
		"%.0f → %.0f" % [hp0, big.current_health if is_instance_valid(big) else 0.0])
	verdict("D1б пехота — one-shot, туша и тролль — нет",
		_spawn("gnoll", GF, Vector3(630.0, 0.0, 600.0)).snipe_one_shot() and not big.snipe_one_shot())
	# Добивающий выстрел
	big.current_health = 1.0
	big._soa_push_stats()
	var pins0: int = _ArrowS.snipe_head_pins
	GameManager.projectile_hit_now(big, 20.0, a, F, true)
	var dead: bool = not is_instance_valid(big) or big.is_dead()
	verdict("D2 добивающая снайперская стрела остаётся в голове туши",
		dead and _ArrowS.snipe_head_pins - pins0 >= 1,
		"мёртв %s, в голове +%d" % [str(dead), _ArrowS.snipe_head_pins - pins0])
	_kill_all(sq[1])
	for n in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(n) and n is Unit and not (n as Unit).is_dead():
			(n as Unit).take_damage(1.0e12)
	await pframes(4)
