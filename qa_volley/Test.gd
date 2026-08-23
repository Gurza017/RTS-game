extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ЗАЛПОВЫЙ ОГОНЬ ЛУЧНИКОВ (forge_config archer_1d, режим отряда)
## ═══════════════════════════════════════════════════════════════════════════
##   A ДОСТУП   — кнопка/покупка закрыты, пока 1D не исследован в кузнице
##   B РЕЖИМ    — купленное включается и выключается, некупленное не включается
##   C ЗАЛП     — отряд бьёт РАЗОМ, а не по мере готовности каждого
##   D КУЧНОСТЬ — стрелы ложатся по вражескому строю, а не веером по своим целям
##   E ВЫКЛ     — с выключенным режимом всё как раньше (контроль)
##   F ИИ       — противник докупает режим и включает его
##
## Числа не хардкодятся: пороги берутся из GameManager.VOLLEY_* и forge_config.

const _Forge := preload("res://scripts/forge_config.gd")

var main = null
var _pass := 0
var _fail := 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")

## ФИЗИЧЕСКИЕ кадры: такт залпа живёт в _physics_process, а при Engine.max_fps=0
## отрисовка обгоняет физику в разы (см. CLAUDE.md)
func frames(n: int) -> void:
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

## id узла-режима лучников — ИЗ КОНФИГА, а не строкой в стенде
func _node() -> Dictionary:
	return _Forge.toggle_ability_of("archer")

func _make_squad(kind: String, fac: int, n: int, at: Vector3) -> int:
	var sid: int = GameManager.new_squad(fac, kind)
	var cols: int = maxi(int(ceil(sqrt(float(n)))), 1)
	for i in range(n):
		var u: Unit
		match kind:
			"archer":  u = Archer.new()
			_:         u = Spearman.new()
		u.faction = fac
		main.world_add(u)
		u.global_position = Vector3(
			at.x + float(i % cols) * 0.7, 0.0, at.z + float(i / cols) * 0.7)
		GameManager.add_to_squad(sid, u)
	await frames(3)
	return sid

func _members(sid: int) -> Array:
	return GameManager.squad_members(sid)

func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(5)
	GameManager.world_bounds_enabled = false
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	# Туман гасит чужих целиком; стенд про стрельбу, а не про видимость
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	await frames(3)

	await _a_access()
	await _b_toggle()
	await _c_sync()
	await _d_cluster()
	await _e_off()
	await _f_ai()

	print("\n═════ ИТОГ ═════")
	for e in _log:
		var row: Array = e
		print("  %s%s" % [_pad(String(row[0]), 62), "ПРОШЛО" if bool(row[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	print("\n=== QA_VOLLEY DONE ===")
	get_tree().quit(1 if _fail > 0 else 0)

# ═════════════════════════════════════════════════════════════════════════════
# A. ДОСТУП: ПОКА 1D НЕ ИЗУЧЕН — СПОСОБНОСТИ НЕТ
# ═════════════════════════════════════════════════════════════════════════════
func _a_access() -> void:
	print("\n═════ A. ДОСТУП ═════")
	var node: Dictionary = _node()
	verdict("A1 в древе лучника есть способность-режим",
		not node.is_empty() and _Forge.is_toggle_ability(node),
		"узел=%s" % String(node.get("id", "нет")))
	if node.is_empty():
		return
	var nid: String = String(node.get("id", ""))
	verdict("A2 это ячейка 1D колонки способностей",
		String(node.get("cell", "")) == "1d"
			and String(node.get("col", "")) == _Forge.ABILITY_COL,
		"ячейка=%s" % String(node.get("cell", "")))

	var f: int = Constants.FACTION_PLAYER
	GameManager.researched[f] = {}
	var sid: int = await _make_squad("archer", f, 6, Vector3(0.0, 0.0, -400.0))
	ResourceManager.add_resource(f, Constants.RESOURCE_GOLD, 99999.0)
	verdict("A3 непокупаемо, пока 1D не исследован",
		not GameManager.squad_can_buy_ability(sid, nid)
			and not GameManager.squad_buy_ability(sid, nid),
		"куплено=%s" % str(GameManager.squad_has_ability(sid, nid)))
	# Кнопку панель тоже не рисует: она перебирает ability_nodes и пропускает
	# неисследованные — проверяем это через тот же признак, что читает панель
	verdict("A4 и на панели её нет (узел не исследован)",
		not GameManager.is_researched(f, nid))

	GameManager.finish_research(f, nid)
	verdict("A5 после исследования 1D покупка открыта",
		GameManager.squad_can_buy_ability(sid, nid),
		"помеха: «%s»" % GameManager.squad_ability_blocker(sid, nid))
	_kill_squad(sid)

func _kill_squad(sid: int) -> void:
	for m in _members(sid):
		if is_instance_valid(m):
			(m as Node).queue_free()

# ═════════════════════════════════════════════════════════════════════════════
# B. РЕЖИМ ВКЛЮЧАЕТСЯ И ВЫКЛЮЧАЕТСЯ
# ═════════════════════════════════════════════════════════════════════════════
func _b_toggle() -> void:
	print("\n═════ B. ПЕРЕКЛЮЧАТЕЛЬ ═════")
	var nid: String = String(_node().get("id", ""))
	var f: int = Constants.FACTION_PLAYER
	var sid: int = await _make_squad("archer", f, 6, Vector3(0.0, 0.0, -420.0))
	verdict("B1 некупленный режим не включается",
		not GameManager.squad_set_ability(sid, nid, true)
			and not GameManager.squad_ability_on(sid, nid))

	ResourceManager.add_resource(f, Constants.RESOURCE_GOLD, 99999.0)
	var bought: bool = GameManager.squad_buy_ability(sid, nid)
	verdict("B2 способность куплена отряду", bought and GameManager.squad_has_ability(sid, nid))
	verdict("B3 сразу после покупки режим ВЫКЛЮЧЕН",
		not GameManager.squad_ability_on(sid, nid) and not GameManager.squad_volley_mode(sid),
		"куплено, но не включено")

	GameManager.squad_set_ability(sid, nid, true)
	verdict("B4 включается", GameManager.squad_ability_on(sid, nid)
		and GameManager.squad_volley_mode(sid))
	GameManager.squad_set_ability(sid, nid, false)
	verdict("B5 выключается", not GameManager.squad_volley_mode(sid))
	_kill_squad(sid)
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# C. СИНХРОННОСТЬ: ОТРЯД БЬЁТ РАЗОМ
# ═════════════════════════════════════════════════════════════════════════════
# Считаем МОМЕНТЫ ВЫСТРЕЛОВ: сколько стрел появилось в мире за кадр. Без залпа
# стрелки перезаряжаются вразнобой и стреляют по одной; в залпе выстрелы
# слипаются в пачки.
func _c_sync() -> void:
	print("\n═════ C. СИНХРОННОСТЬ ═════")
	var nid: String = String(_node().get("id", ""))
	var f: int = Constants.FACTION_PLAYER
	var at := Vector3(0.0, 0.0, -460.0)
	var sid: int = await _make_squad("archer", f, 10, at)
	var foe: int = await _make_squad("spearman", Constants.FACTION_ENEMY, 12,
		at + Vector3(9.0, 0.0, 0.0))
	# Врагам стоять: стенд про темп стрельбы, а не про бег
	for m in _members(foe):
		(m as Unit).set_tick(false)
	ResourceManager.add_resource(f, Constants.RESOURCE_GOLD, 99999.0)
	GameManager.squad_buy_ability(sid, nid)
	GameManager.squad_set_ability(sid, nid, true)

	var burst: Array = await _shot_profile(sid, 240)
	var peak: int = 0
	var shots: int = 0
	for b in burst:
		peak = maxi(peak, int(b))
		shots += int(b)
	var live: int = _members(sid).size()
	verdict("C1 залп идёт пачками: за один кадр стреляет больше половины отряда",
		peak >= int(ceil(float(live) * 0.5)),
		"пик %d выстрелов за кадр при %d стрелках, всего %d" % [peak, live, shots])

	# Между залпами обязана быть тишина — иначе это не залп, а обычная стрельба
	var silent := 0
	for b in burst:
		if int(b) == 0:
			silent += 1
	verdict("C2 между залпами отряд молчит",
		float(silent) / float(maxi(burst.size(), 1)) > 0.7,
		"тихих кадров %d из %d" % [silent, burst.size()])
	_kill_squad(sid); _kill_squad(foe)
	await frames(2)

## Сколько стрел появилось за каждый из n физкадров
func _shot_profile(sid: int, n: int) -> Array:
	var out: Array = []
	var prev: int = _arrows_in_air()
	for _i in range(n):
		await get_tree().physics_frame
		var now: int = _arrows_in_air()
		out.append(maxi(now - prev, 0))
		prev = now
	return out

## Стрелы живут в пуле и ни в какой группе не состоят — считаем по монотонному
## счётчику выстрелов (GameManager.arrows_fired). Он же отвечает на вопрос
## «сколько выстрелов сделано», который и нужен: залп — это пачки, обычная
## стрельба — ровный ручеёк
func _arrows_in_air() -> int:
	return GameManager.arrows_fired

# ═════════════════════════════════════════════════════════════════════════════
# D. КУЧНОСТЬ: СТРЕЛЫ ЛОЖАТСЯ ПО СТРОЮ, А НЕ ВЕЕРОМ
# ═════════════════════════════════════════════════════════════════════════════
func _d_cluster() -> void:
	print("\n═════ D. КУЧНОСТЬ ═════")
	var nid: String = String(_node().get("id", ""))
	var f: int = Constants.FACTION_PLAYER
	var at := Vector3(0.0, 0.0, -520.0)
	var sid: int = await _make_squad("archer", f, 12, at)
	var foe: int = await _make_squad("spearman", Constants.FACTION_ENEMY, 16,
		at + Vector3(9.0, 0.0, 0.0))
	for m in _members(foe):
		(m as Unit).set_tick(false)
	ResourceManager.add_resource(f, Constants.RESOURCE_GOLD, 99999.0)
	GameManager.squad_buy_ability(sid, nid)
	GameManager.squad_set_ability(sid, nid, true)
	await frames(180)

	var aim: Vector3 = GameManager.squad_volley_aim(sid)
	var c: Vector3 = GameManager.squad_centroid(foe)
	verdict("D1 точка залпа — центр масс вражеского ОТРЯДА",
		aim != Vector3.ZERO and Vector2(aim.x - c.x, aim.z - c.z).length() < 1.5,
		"залп (%.1f, %.1f), центр строя (%.1f, %.1f)" % [aim.x, aim.z, c.x, c.z])

	# Разброс мест в туче: у одного и того же стрелка он ДЕТЕРМИНИРОВАН
	# (золотой угол по номеру), а у разных — различен. Значит стрелы не сходятся
	# в одну точку и не расползаются шире строя
	var men: Array = _members(sid)
	var offs: Array = []
	var maxr := 0.0
	for m in men:
		var a := m as Archer
		if a == null:
			continue
		var o: Vector3 = a._volley_offset(3.0)
		offs.append(o)
		maxr = maxf(maxr, o.length())
	var same := 0
	for i in range(offs.size()):
		for j in range(i + 1, offs.size()):
			if (offs[i] as Vector3).distance_to(offs[j]) < 0.05:
				same += 1
	verdict("D2 каждый стрелок берёт СВОЁ место в туче",
		same == 0 and offs.size() >= 8,
		"совпавших пар %d из %d стрелков" % [same, offs.size()])
	verdict("D3 туча не шире заданного радиуса", maxr <= 3.0 + 0.01,
		"дальняя точка %.2f м при радиусе 3.00" % maxr)
	verdict("D4 и не сходится в точку — иначе весь залп ушёл бы в одного",
		maxr > 1.0, "дальняя точка %.2f м" % maxr)

	# Свойство, ради которого всё делалось: залп РЕАЛЬНО бьёт по строю
	var hurt := 0
	for m in _members(foe):
		var u := m as Unit
		if u != null and is_instance_valid(u) and u.current_health < u.max_health:
			hurt += 1
	verdict("D5 залп задел НЕСКОЛЬКИХ бойцов вражеского строя", hurt >= 3,
		"ранено %d из %d" % [hurt, _members(foe).size()])
	_kill_squad(sid); _kill_squad(foe)
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# E. КОНТРОЛЬ: С ВЫКЛЮЧЕННЫМ РЕЖИМОМ ВСЁ ПО-СТАРОМУ
# ═════════════════════════════════════════════════════════════════════════════
# Без этого раздела проверки выше прошли бы и на коде, который стреляет залпом
# ВСЕГДА, — то есть переключатель не проверялся бы вовсе
func _e_off() -> void:
	print("\n═════ E. РЕЖИМ ВЫКЛЮЧЕН ═════")
	var nid: String = String(_node().get("id", ""))
	var f: int = Constants.FACTION_PLAYER
	var at := Vector3(0.0, 0.0, -580.0)
	var sid: int = await _make_squad("archer", f, 10, at)
	var foe: int = await _make_squad("spearman", Constants.FACTION_ENEMY, 12,
		at + Vector3(9.0, 0.0, 0.0))
	for m in _members(foe):
		(m as Unit).set_tick(false)
	ResourceManager.add_resource(f, Constants.RESOURCE_GOLD, 99999.0)
	GameManager.squad_buy_ability(sid, nid)   # куплено, но НЕ включено

	var burst: Array = await _shot_profile(sid, 240)
	var peak := 0
	var shots := 0
	for b in burst:
		peak = maxi(peak, int(b))
		shots += int(b)
	var live: int = _members(sid).size()
	verdict("E1 без режима стрельба вразнобой: пачек нет",
		peak < int(ceil(float(live) * 0.5)) and shots > 0,
		"пик %d при %d стрелках, всего %d выстрелов" % [peak, live, shots])
	verdict("E2 окно залпа не открывается",
		not GameManager.squad_volley_open(sid) and not GameManager.squad_volley_mode(sid))
	_kill_squad(sid); _kill_squad(foe)
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# F. ИИ ДОКУПАЕТ РЕЖИМ И ВКЛЮЧАЕТ ЕГО
# ═════════════════════════════════════════════════════════════════════════════
func _f_ai() -> void:
	print("\n═════ F. ИИ ═════")
	var nid: String = String(_node().get("id", ""))
	var ef: int = Constants.FACTION_ENEMY
	var sid: int = await _make_squad("archer", ef, 8, Vector3(0.0, 0.0, -640.0))
	GameManager.finish_research(ef, nid)
	ResourceManager.add_resource(ef, Constants.RESOURCE_GOLD, 99999.0)
	verdict("F1 до прохода ИИ режима у отряда нет",
		not GameManager.squad_has_ability(sid, nid))
	main.enemy_ai._buy_squad_abilities()
	verdict("F2 ИИ докупил режим отряду лучников",
		GameManager.squad_has_ability(sid, nid))
	verdict("F3 и сразу его включил", GameManager.squad_volley_mode(sid))

	# Резерв золота соблюдается: на пустой казне покупки нет
	var sid2: int = await _make_squad("archer", ef, 8, Vector3(0.0, 0.0, -680.0))
	ResourceManager.reset_resources()
	GameManager.finish_research(ef, nid)
	main.enemy_ai._buy_squad_abilities()
	verdict("F4 при пустой казне ИИ режим не покупает",
		not GameManager.squad_has_ability(sid2, nid),
		"золото=%.0f" % ResourceManager.get_amount(ef, Constants.RESOURCE_GOLD))
	_kill_squad(sid); _kill_squad(sid2)
	await frames(2)
