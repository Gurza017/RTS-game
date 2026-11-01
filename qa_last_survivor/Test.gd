extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ПОСЛЕДНИЙ ВЫЖИВШИЙ / ТАКТИЧЕСКОЕ ОТСТУПЛЕНИЕ (ТЗ 28.10.2026, блок 3)
## ═══════════════════════════════════════════════════════════════════════════
## Узел 3c пехоты в кузнице: последний боец выбитого отряда с шансом
## LAST_STAND_CHANCE уцелевает призраком (LAST_STAND_HP_FRAC запаса), чужие
## его не видят (ArmyCore.FGhost), он мигает и уходит в крепость штатным
## путём отхода, лечится, отряд пополняется до штата и выходит.
##
##   A  без узла — последний гибнет всегда (серия из 30 отрядов);
##   B  с узлом — доля уцелевших ≈ LAST_STAND_CHANCE на серии из 60 отрядов
##      (жребий сеяный — утверждается серия, не исход); уцелевший — призрак
##      с долей запаса из конфига; повторный «удар насмерть» убивает честно;
##   C  ручка perf_config.last_stand выключена — последний гибнет всегда;
##   D  призрака не выбирают целью ни ядро (стрелы — enemy_at, выбор —
##      best_enemy, счёт чужих, чужое тело на шаге), ни авто-агро пехоты и
##      стрелков рядом; запас не меняется; физика не спит; мигает;
##   E  срок призрака истёк — снова цель;
##   F  с крепостью: уходит в неё, принят, вылечен, отряд пополнен до штата и
##      выпущен — бывший призрак в строю, здоров, не призрак;
##   G  слоты отрисовки и строки ядра не текут (образец — qa_deathslots).
##
## Числа — из конфига (LAST_STAND_*), не хардкод. Ждём physics_frame;
## игровые сроки — Unit.game_ms(). Сторож 480 с.
## Запуск: godot --headless --path . res://qa_last_survivor/Test.tscn

const _Opt := preload("res://scripts/perf_config.gd")
const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _Forge := preload("res://scripts/forge_config.gd")

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []
var _done: bool = false
var _killer: Unit = null

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(480.0).timeout.connect(func():
		if not _done:
			print("  СТОРОЖ: стенд не завершился за 480 с")
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
	if _done:
		return
	_done = true
	print("\n═════ ИТОГ qa_last_survivor: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit(1 if _fail > 0 else 0)

# ─────────────────────────────────────────────────────────────────────────────
# СЛУЖЕБНОЕ
# ─────────────────────────────────────────────────────────────────────────────
func _spawn(kind: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = load("res://scenes/units/%s.tscn" % kind).instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	return u

## Отряд из n бойцов рода kind в точке at. Ответ: {"sid", "men"}
func _mk_squad(kind: String, scene: String, n: int, at: Vector3, fac: int) -> Dictionary:
	var sid: int = GameManager.new_squad(fac, kind)
	var men: Array = []
	var cols: int = maxi(1, int(ceil(sqrt(float(n)))))
	for i in range(n):
		var u: Unit = _spawn(scene, fac, at + Vector3(float(i % cols) * 0.8, 0.0, float(i / cols) * 0.8))
		u.post_pos = u.global_position
		u.set("_post_valid", true)
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return {"sid": sid, "men": men}

## Выбить отряд: всех по очереди ударом насмерть от killer. Ответ — последний,
## если он уцелел (жив и не мёртв), иначе null
func _wipe(men: Array) -> Unit:
	var last: Unit = null
	for i in range(men.size()):
		var u: Unit = men[i]
		if u == null or not is_instance_valid(u) or u.is_dead():
			continue
		u.take_damage(u.max_health * 100.0 + 1000.0, _killer)
		last = u
	if last != null and is_instance_valid(last) and not last.is_dead():
		return last
	return null

## Серия из k отрядов по 3 копейщика: сколько уцелело призраками (и сами они)
func _series(k: int, at: Vector3, fac: int) -> Dictionary:
	var ghosts: Array = []
	var sids: Array = []
	for i in range(k):
		var spot: Vector3 = at + Vector3(float(i % 10) * 4.0, 0.0, float(i / 10) * 4.0)
		var sq: Dictionary = _mk_squad("spearman", "Spearman", 3, spot, fac)
		sids.append(int(sq["sid"]))
	await pframes(6)
	var n_ok := 0
	for sid in sids:
		var members: Array = (GameManager.squads[sid]["members"] as Array).duplicate()
		var g: Unit = _wipe(members)
		if g != null:
			ghosts.append(g)
			n_ok += 1
	await pframes(4)
	return {"n": n_ok, "ghosts": ghosts, "sids": sids}

## Сделать одного призрака: отряды по 3 на площадке, пока жребий не выпадет
func _make_ghost(at: Vector3, fac: int, tries: int = 20) -> Unit:
	for i in range(tries):
		var sq: Dictionary = _mk_squad("spearman", "Spearman", 3, at, fac)
		await pframes(4)
		var g: Unit = _wipe((sq["men"] as Array).duplicate())
		await pframes(2)
		if g != null:
			return g
	return null

func _clear_area(c: Vector3, r: float) -> void:
	for u in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(u) and u is Unit and not (u as Unit).is_dead():
			var p: Vector3 = (u as Node3D).global_position
			if Vector2(p.x - c.x, p.z - c.z).length() < r:
				(u as Unit).take_damage(1.0e9, null)

## Живые слоты во ВСЕХ бакетах бойцов (образец — qa_deathslots)
func _live_slots() -> int:
	var fu = GameManager.far_units
	var n := 0
	for b in fu._buckets.values():
		if b == null or b.core_id < 0:
			continue
		for i in range(b.capacity):
			var s: PackedFloat32Array = GameManager.army.rb_slot(b.core_id, i)
			if s.size() < 16:
				continue
			var basis_sq := 0.0
			for k in [0, 1, 2, 4, 5, 6, 8, 9, 10]:
				basis_sq += s[k] * s[k]
			if basis_sq >= 1e-6:
				n += 1
	return n

## Вспышка в слоте отрисовки бойца (float 14 буфера), −1 — слота нет
func _flash_of(u: Unit) -> float:
	var fu = GameManager.far_units
	var s = fu._slot.get(u)
	if s == null or s.bucket == null or s.bucket.core_id < 0:
		return -1.0
	var buf: PackedFloat32Array = GameManager.army.rb_slot(s.bucket.core_id, s.index)
	if buf.size() < 16:
		return -1.0
	return buf[14]

func _alive_rows() -> int:
	var n := 0
	for u in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(u) and u is Unit and not (u as Unit).is_dead() and (u as Unit)._soa >= 0:
			n += 1
	return n

# ─────────────────────────────────────────────────────────────────────────────
func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	GameManager.world_bounds_enabled = false
	await frames(2)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
		(GameManager.fog as Node3D).visible = false
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	await pframes(4)
	var PF: int = Constants.FACTION_PLAYER
	var EF: int = Constants.FACTION_ENEMY
	# Площадка в поле карты, чужих и своих на ней нет: стенд на случайной карте
	# — не доказательство (ловушка стендов)
	var base := Vector3(60.0, 0.0, -120.0)
	_clear_area(base, 220.0)
	await pframes(6)
	# Убийца — чужой боец вдали, замороженный: удар насмерть идёт от него
	_killer = _spawn("Spearman", EF, base + Vector3(-110.0, 0.0, -60.0))
	_killer.set_tick(false)
	var node_id: String = _Forge.node_id("spearman", _UCfg.LAST_STAND_CELL)
	var chance: float = _UCfg.LAST_STAND_CHANCE
	var hp_frac: float = _UCfg.LAST_STAND_HP_FRAC
	print("  узел %s, шанс %.2f, доля запаса %.2f, срок %.0f с, ручка last_stand=%s" % [
		node_id, chance, hp_frac, _UCfg.LAST_STAND_GHOST_SEC, str(_Opt.last_stand)])
	verdict("A0 узел «%s» есть в древе пехоты у копейщика и мечника" % node_id,
		not _Forge.get_node(node_id).is_empty() and not _Forge.get_node(_Forge.node_id("warrior", _UCfg.LAST_STAND_CELL)).is_empty())

	print("\n═════ A. БЕЗ УЗЛА — ПОСЛЕДНИЙ ГИБНЕТ ВСЕГДА ═════")
	verdict("A1 узел не изучен", not GameManager.is_researched(PF, node_id))
	var ra: Dictionary = await _series(30, base, PF)
	verdict("A2 без узла уцелевших 0 из 30", int(ra["n"]) == 0, "уцелело %d" % int(ra["n"]))

	print("\n═════ B. С УЗЛОМ — ДОЛЯ УЦЕЛЕВШИХ ≈ %.2f НА СЕРИИ ═════" % chance)
	GameManager.finish_research(PF, node_id)
	verdict("B0 узел изучен (finish_research)", GameManager.is_researched(PF, node_id))
	var rb: Dictionary = await _series(60, base + Vector3(0.0, 0.0, 30.0), PF)
	var nb: int = int(rb["n"])
	var share: float = float(nb) / 60.0
	# Биномиальный коридор ±2.5σ при n = 60: σ = √(60·p·(1−p))
	var sig: float = sqrt(60.0 * chance * (1.0 - chance)) / 60.0
	verdict("B1 доля уцелевших %.2f в коридоре %.2f..%.2f (уцелело %d из 60)" % [
		share, chance - 2.5 * sig, chance + 2.5 * sig, nb],
		share >= chance - 2.5 * sig and share <= chance + 2.5 * sig)
	var ghosts: Array = rb["ghosts"]
	var ok_flag := 0
	var ok_core := 0
	var ok_hp := 0
	var ok_retreat := 0
	var ok_squad := 0
	for g0 in ghosts:
		var g: Unit = g0
		if not is_instance_valid(g) or g.is_dead():
			continue
		if g.is_ghost(): ok_flag += 1
		if GameManager.army.is_ghost(g._soa): ok_core += 1
		if absf(g.current_health - g.max_health * hp_frac) < 0.01: ok_hp += 1
		if g.retreating: ok_retreat += 1
		if g.squad_id > 0 and GameManager.squads.has(g.squad_id): ok_squad += 1
	verdict("B2 у каждого уцелевшего признак призрака и в бойце, и в строке ядра",
		nb > 0 and ok_flag == nb and ok_core == nb, "боец %d, ядро %d из %d" % [ok_flag, ok_core, nb])
	verdict("B3 запас уцелевшего = %.0f %% максимума" % (hp_frac * 100.0), nb > 0 and ok_hp == nb, "%d из %d" % [ok_hp, nb])
	verdict("B4 уцелевший в режиме отхода, его отряд не распущен",
		nb > 0 and ok_retreat == nb and ok_squad == nb, "отход %d, отряд %d из %d" % [ok_retreat, ok_squad, nb])
	# Повторный удар насмерть — второго жребия нет
	var died2 := 0
	for g0 in ghosts:
		var g: Unit = g0
		if not is_instance_valid(g) or g.is_dead():
			continue
		g.take_damage(g.max_health * 100.0 + 1000.0, _killer)
		if g.is_dead():
			died2 += 1
	await pframes(4)
	verdict("B5 повторный удар насмерть убивает призрака честно (%d из %d)" % [died2, nb], nb > 0 and died2 == nb)

	print("\n═════ C. РУЧКА last_stand ВЫКЛЮЧЕНА — ПОСЛЕДНИЙ ГИБНЕТ ВСЕГДА ═════")
	_Opt.last_stand = false
	var rc: Dictionary = await _series(20, base + Vector3(0.0, 0.0, 60.0), PF)
	verdict("C1 с узлом, но без ручки уцелевших 0 из 20", int(rc["n"]) == 0, "уцелело %d" % int(rc["n"]))
	_Opt.last_stand = true

	print("\n═════ D. ПРИЗРАКА НЕ ВИДЯТ: ЯДРО, АВТО-АГРО, СТРЕЛКИ ═════")
	var dspot := base + Vector3(50.0, 0.0, 0.0)
	var ghost: Unit = await _make_ghost(dspot, PF)
	verdict("D0 призрак получен (крепости нет — стоит на месте в отходе)", ghost != null)
	if ghost == null:
		_finish()
		return
	await pframes(10)
	var gp: Vector3 = ghost.global_position
	# Чужая пехота в 3 м (авто-агро 5 м) и стрелки в 12 м (дальность 20+)
	var foes: Dictionary = _mk_squad("spearman", "Spearman", 6, gp + Vector3(3.0, 0.0, 0.0), EF)
	var bows: Dictionary = _mk_squad("archer", "Archer", 6, gp + Vector3(0.0, 0.0, 12.0), EF)
	var all_foes: Array = (foes["men"] as Array) + (bows["men"] as Array)
	await pframes(4)
	var hp0: float = ghost.current_health
	var targeted := 0
	var saw_flash := false
	var slept := false
	var ticks: int = int(3.5 * float(Engine.physics_ticks_per_second))
	for _i in range(ticks):
		await get_tree().physics_frame
		for f0 in all_foes:
			var f: Unit = f0
			if is_instance_valid(f) and f.attack_target == ghost:
				targeted += 1
		if _flash_of(ghost) > 0.05:
			saw_flash = true
		if ghost._phys_asleep:
			slept = true
	var sp0: Unit = (foes["men"] as Array)[0]
	verdict("D1 enemy_at у точки призрака (путь стрелы) не находит его",
		GameManager.unit_grid.enemy_at(ghost.global_position, 1.0, EF) == null)
	var be = GameManager.unit_grid.best_enemy(sp0, 10.0, 0.0)
	verdict("D2 best_enemy у чужого копейщика в 3 м — не призрак", be == null or be != ghost, "выбор %s" % str(be))
	verdict("D3 счёт чужих вокруг чужого копейщика (enemy_count) — ноль",
		GameManager.unit_grid.enemy_count(sp0.global_position, 6.0, EF) == 0)
	var blk: Vector3 = GameManager.unit_grid.enemy_block(sp0, ghost.global_position, 0.55)
	verdict("D4 тело призрака не блокирует чужой шаг (enemy_block = 0)", blk.length_squared() < 1e-8, str(blk))
	verdict("D5 за 3.5 с ни один чужой (6 копейщиков в 3 м, 6 лучников в 12 м) не взял призрака целью",
		targeted == 0, "взятий %d" % targeted)
	verdict("D6 запас призрака не изменился (%.1f → %.1f)" % [hp0, ghost.current_health],
		absf(ghost.current_health - hp0) < 0.01 and not ghost.is_dead())
	verdict("D7 призрак мигает (вспышка в слоте отрисовки) и физика его не спит",
		saw_flash and not slept, "вспышка %s, спал %s" % [str(saw_flash), str(slept)])

	print("\n═════ E. СРОК ПРИЗРАКА ИСТЁК — СНОВА ЦЕЛЬ ═════")
	ghost._ghost_until_ms = Unit.game_ms() + 1000
	var cleared := false
	for _i in range(int(3.0 * float(Engine.physics_ticks_per_second))):
		await get_tree().physics_frame
		if not ghost.is_ghost():
			cleared = true
			break
	verdict("E1 по сроку признак снят и в бойце, и в ядре",
		cleared and not GameManager.army.is_ghost(ghost._soa))
	verdict("E2 enemy_at у точки бывшего призрака снова находит его",
		GameManager.unit_grid.enemy_at(ghost.global_position, 1.0, EF) == ghost)
	var retook := 0
	var hurt := false
	for _i in range(int(4.0 * float(Engine.physics_ticks_per_second))):
		await get_tree().physics_frame
		if not is_instance_valid(ghost) or ghost.is_dead():
			hurt = true
			break
		if ghost.current_health < hp0 - 0.01:
			hurt = true
		for f0 in foes["men"]:
			var f: Unit = f0
			if is_instance_valid(f) and f.attack_target == ghost:
				retook += 1
	verdict("E3 чужая пехота рядом берёт его целью и бьёт", retook > 0 or hurt, "взятий %d, задет %s" % [retook, str(hurt)])
	_clear_area(dspot, 40.0)
	await pframes(6)

	print("\n═════ F. С КРЕПОСТЬЮ: В ЗАМОК, ЛАЗАРЕТ, ДО ШТАТА, ВЫХОД ═════")
	var fspot := base + Vector3(-60.0, 0.0, 40.0)
	var keep := Castle.new()
	keep.faction = PF
	main.world_add(keep)
	keep.global_position = Vector3(fspot.x, GameManager.get_terrain_height(fspot.x, fspot.z), fspot.z)
	await pframes(8)
	var gate: Vector3 = keep._gate_position()
	var start: Vector3 = gate + Vector3(28.0, 0.0, 0.0)
	var g2: Unit = await _make_ghost(start, PF)
	verdict("F0 призрак получен у крепости", g2 != null)
	if g2 == null:
		_finish()
		return
	var sid2: int = g2.squad_id
	await pframes(2)
	verdict("F1 отряд призрака идёт в замок штатной заявкой (squad_is_to_castle) в режиме отхода",
		GameManager.squad_is_to_castle(sid2) and g2.retreating)
	var inside := false
	var t_in := 0
	for _i in range(int(40.0 * float(Engine.physics_ticks_per_second))):
		await get_tree().physics_frame
		t_in += 1
		if not is_instance_valid(g2) or g2.is_dead():
			break
		if g2.garrisoned:
			inside = true
			break
	verdict("F2 призрак дошёл от %.0f м и принят в гарнизон (%.1f с)" % [start.distance_to(gate), float(t_in) / float(Engine.physics_ticks_per_second)], inside)
	verdict("F3 в гарнизоне признак призрака снят", inside and not g2.is_ghost() and not GameManager.army.is_ghost(g2._soa))
	# Лечение до полного и подъём до штата идут минутами игрового времени —
	# ускоряем часы, как qa_ai_loop/Smoke (time_scale × такты физики)
	var want: int = _UCfg.squad_size("spearman")
	var mult := 6
	var tps0: int = Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = tps0 * mult
	Engine.time_scale = float(mult)
	var released := false
	var g_sec := 0.0
	var cap_sec := 420.0
	while g_sec < cap_sec and inside:
		await get_tree().physics_frame
		g_sec += 1.0 / float(tps0)
		if not GameManager.squads.has(sid2):
			break
		var mem: Array = GameManager.squads[sid2]["members"]
		if mem.size() < want:
			continue
		var out_all := true
		for m in mem:
			if m == null or not is_instance_valid(m) or (m as Unit).garrisoned or (m as Unit).is_dead():
				out_all = false
				break
		if out_all:
			released = true
			break
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = tps0
	await pframes(4)
	var mem2: Array = GameManager.squads[sid2]["members"] if GameManager.squads.has(sid2) else []
	verdict("F4 отряд пополнен до штата (%d) и выпущен из замка за %.0f игровых с" % [want, g_sec],
		released and mem2.size() == want, "в отряде %d" % mem2.size())
	var g2_ok: bool = is_instance_valid(g2) and not g2.is_dead() and g2.squad_id == sid2 \
		and not g2.garrisoned and not g2.is_ghost() and g2.visible
	verdict("F5 бывший призрак в строю своего отряда, не в гарнизоне, не призрак",
		g2_ok, "жив %s, sid %d, гарнизон %s" % [str(is_instance_valid(g2) and not g2.is_dead()), (g2.squad_id if is_instance_valid(g2) else -1), str(g2.garrisoned if is_instance_valid(g2) else "-")])
	verdict("F6 бывший призрак вылечен (%.0f из %.0f)" % [(g2.current_health if is_instance_valid(g2) else -1.0), (g2.max_health if is_instance_valid(g2) else -1.0)],
		is_instance_valid(g2) and g2.current_health >= g2.max_health - 0.5)

	print("\n═════ G. СЛОТЫ ОТРИСОВКИ И СТРОКИ ЯДРА НЕ ТЕКУТ ═════")
	await pframes(30)
	var reg: int = GameManager.far_units._slot.size()
	var live: int = _live_slots()
	verdict("G1 живых слотов отрисовки ровно столько, сколько зарегистрированных (%d)" % reg, live == reg, "слотов %d" % live)
	var dead_keys := 0
	for k in GameManager.far_units._slot.keys():
		if not is_instance_valid(k) or (k is Unit and (k as Unit).is_dead()):
			dead_keys += 1
	verdict("G2 в реестре отрисовки нет мёртвых/освобождённых", dead_keys == 0, "мёртвых ключей %d" % dead_keys)
	var rows_alive: int = _alive_rows()
	var top: int = GameManager.army.top()
	verdict("G3 строк ядра у живых %d, верхняя граница %d — не меньше живых" % [rows_alive, top], top >= rows_alive)
	_finish()
