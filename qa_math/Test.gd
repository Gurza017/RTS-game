extends Node

## ═══════════════════════════════════════════════════════════════════════════
## МАТЕМАТИКА УРОНА, БРОНИ И ЗАЩИТЫ — ЗАМЕР, А НЕ ПЕРЕСЧЁТ
## ═══════════════════════════════════════════════════════════════════════════
## Все числа в таблице получены ВЫЗОВОМ БОЕВОГО КОДА:
##   • итоговая атака     — Unit._upgrade_damage_bonus() (та же функция, что в ударе)
##   • полученный урон    — Unit.take_damage(), замеряется по убыли current_health
## Формулы в отчёте сверяются с этими замерами: если код и формула разойдутся,
## расхождение будет видно в столбце «сверка».

const _UCfg = preload("res://scripts/unit_stats_config.gd")

var main = null
var _fails: int = 0

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func _spawn(kind: String, fac: int, pos: Vector3) -> Unit:
	var u: Unit = null
	match kind:
		"spearman": u = Spearman.new()
		"archer":   u = Archer.new()
		"warrior":  u = Warrior.new()
	u.faction = fac
	main.world_add(u)
	u.global_position = pos
	return u

## Дать фракции денег и купить слот кузницы мгновенно
func _buy(fac: int, upg: String) -> bool:
	for t in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD,
			Constants.RESOURCE_STONE, Constants.RESOURCE_FOOD]:
		ResourceManager.add_resource(fac, t, 100000.0)
	return GameManager.research_upgrade(fac, upg)

## ЗАМЕР: сколько HP реально снимет удар силой amount. Бьём боевым take_damage
func _hit(victim: Unit, amount: float, attacker: Unit) -> float:
	victim.current_health = victim.max_health
	victim.take_damage(amount, attacker)
	var lost: float = victim.max_health - victim.current_health
	victim.current_health = victim.max_health
	return lost

## Итоговая атака бойца — ровно то число, что уходит в take_damage
func _atk(u: Unit) -> float:
	return u.attack_damage + u._upgrade_damage_bonus()

## Сумма всех вычитаемых из урона слагаемых (по формуле из take_damage)
func _mitigation(u: Unit) -> float:
	return u.defense + u.armor \
		+ GameManager.get_upgrade(u.faction, "defense") \
		+ GameManager.unit_bonus(u.faction, u.stat_id, "bonus_armor") \
		+ u.vet_armor + u.vet_defense \
		+ _UCfg.stance_stat(u.stance, "defense_bonus", 0.0)

func _pad(s: String, n: int) -> String:
	var out := s
	while out.length() < n:
		out += " "
	return out

func _row(cells: Array, widths: Array) -> String:
	var out := "│"
	for i in range(cells.size()):
		out += " " + _pad(String(cells[i]), int(widths[i])) + " │"
	return out

func _rule(widths: Array, l: String, m: String, r: String) -> String:
	var out := l
	for i in range(widths.size()):
		out += "─".repeat(int(widths[i]) + 2)
		out += r if i == widths.size() - 1 else m
	return out

func _check(title: String, got: float, want: float, eps: float = 0.001) -> String:
	if absf(got - want) <= eps:
		return "ок"
	_fails += 1
	print("  !!! РАСХОЖДЕНИЕ %s: код даёт %.3f, формула %.3f" % [title, got, want])
	return "РАСХОЖДЕНИЕ"

func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	# СТЕНД РАБОТАЕТ ЗА ПРЕДЕЛАМИ КАРТЫ: площадки вынесены далеко в сторону,
	# чтобы ни ИИ, ни лес, ни чужие отряды не мешали замеру. Жёсткая граница
	# мира стянула бы их все в угол поля — на время стенда её снимаем
	GameManager.world_bounds_enabled = false
	await frames(5)

	var P: int = Constants.FACTION_PLAYER
	var E: int = Constants.FACTION_ENEMY
	var base := Vector3(3000.0, 0.0, 3000.0)

	print("\n\n╔══════════════════════════════════════════════════════════════════════════╗")
	print("║  МАТЕМАТИКА УРОНА, БРОНИ И ЗАЩИТЫ — ЗАМЕР БОЕВОГО КОДА                   ║")
	print("╚══════════════════════════════════════════════════════════════════════════╝")

	# ── КОНСТАНТЫ ФОРМУЛЫ ───────────────────────────────────────────────────
	print("\n─── КОНСТАНТЫ ───")
	print("  MIN_DAMAGE_FRACTION = %.2f  (сквозь любую защиту всегда проходит %d%% удара)" % [
		Unit.MIN_DAMAGE_FRACTION, int(Unit.MIN_DAMAGE_FRACTION * 100.0)])
	print("  стойка ЗАЩИТА: defense_bonus=%.0f, push_mult=%.2f, push_resist=%.2f, attack_speed_mult=%.2f" % [
		_UCfg.stance_stat("defense", "defense_bonus"), _UCfg.stance_stat("defense", "push_mult"),
		_UCfg.stance_stat("defense", "push_resist"), _UCfg.stance_stat("defense", "attack_speed_mult")])

	# ── ГЛАВНАЯ ТАБЛИЦА: КОПЕЙЩИК ───────────────────────────────────────────
	var vic := _spawn("spearman", P, base)
	var foe := _spawn("spearman", E, base + Vector3(2.0, 0.0, 0.0))
	await frames(3)
	foe.attack_damage = 20.0     # «враг с атакой 20» из задания

	var W: Array = [26, 13, 11, 24, 15, 12]
	var head: Array = ["ЭТАП ПРОКАЧКИ", "АТАКА", "БРОНЯ", "ЗАЩИТА / МОДИФИКАТОРЫ",
		"УРОН ОТ 20", "СВЕРКА"]
	var lines: Array = []

	# 1. база
	var d1: float = _hit(vic, 20.0, foe)
	lines.append([ "1. Базовый",
		"%.0f" % _atk(vic), "%.0f" % vic.armor,
		"%.0f (стойка АТАКА)" % vic.defense,
		"%.2f" % d1, _check("база", d1, maxf(20.0 * 0.15, 20.0 - _mitigation(vic)))])

	# 2. кузница: копья (+3 атака), щиты (+2 броня), броня (+3 броня)
	var ok_s: bool = _buy(P, "spears")
	var ok_h: bool = _buy(P, "shields")
	var ok_a: bool = _buy(P, "armor")
	await frames(3)
	var d2: float = _hit(vic, 20.0, foe)
	var arm2: float = vic.armor + GameManager.unit_bonus(P, "spearman", "bonus_armor")
	lines.append([ "2. + Кузница (копья/щиты/броня)",
		"%.0f" % _atk(vic), "%.0f" % arm2,
		"%.0f (стойка АТАКА)" % vic.defense,
		"%.2f" % d2, _check("кузница", d2, maxf(20.0 * 0.15, 20.0 - _mitigation(vic)))])
	print("  куплено: копья=%s щиты=%s броня=%s" % [str(ok_s), str(ok_h), str(ok_a)])

	# 3. первая звезда опыта — вариант «+5 Броня»
	vic.vet_armor += 5.0
	var d3: float = _hit(vic, 20.0, foe)
	lines.append([ "3. + 1★ опыта (+5 Броня)",
		"%.0f" % _atk(vic), "%.0f" % (arm2 + vic.vet_armor),
		"%.0f (стойка АТАКА)" % vic.defense,
		"%.2f" % d3, _check("звезда-броня", d3, maxf(20.0 * 0.15, 20.0 - _mitigation(vic)))])

	# 3-бис. та же звезда, но вариант «+5 Защита» — ДОЛЖНО СОВПАСТЬ до цифры
	vic.vet_armor -= 5.0
	vic.vet_defense += 5.0
	var d3b: float = _hit(vic, 20.0, foe)
	lines.append([ "3-бис. та же ★, но «+5 Защита»",
		"%.0f" % _atk(vic), "%.0f" % arm2,
		"%.0f + 5 опыт" % vic.defense,
		"%.2f" % d3b, _check("звезда-защита", d3b, d3)])

	# 4. стойка ЗАЩИТА
	vic.set_stance(_UCfg.STANCE_DEFENSE)
	var d4: float = _hit(vic, 20.0, foe)
	lines.append([ "4. + стойка ЗАЩИТА",
		"%.0f" % _atk(vic), "%.0f" % arm2,
		"%.0f + 5 опыт + 5 стойка" % vic.defense,
		"%.2f" % d4, _check("стойка", d4, maxf(20.0 * 0.15, 20.0 - _mitigation(vic)))])

	print("\n─── КОПЕЙЩИК ПОД УДАРОМ ВРАГА С АТАКОЙ 20 ───")
	print(_rule(W, "┌", "┬", "┐"))
	print(_row(head, W))
	print(_rule(W, "├", "┼", "┤"))
	for l in lines:
		print(_row(l, W))
	print(_rule(W, "└", "┴", "┘"))

	# ── ПОРОГ ОТСЕЧКИ: КОГДА ЗАЩИТА ПЕРЕСТАЁТ РАБОТАТЬ ──────────────────────
	print("\n─── ГДЕ УПИРАЕТСЯ В ПОЛ 15%% (удар 20) ───")
	vic.set_stance(_UCfg.STANCE_ATTACK)
	vic.vet_defense = 0.0
	var W2: Array = [16, 14, 14, 18]
	print(_rule(W2, "┌", "┬", "┐"))
	print(_row(["СУММА ЗАЩИТЫ", "УРОН", "СРЕЗАНО", "РЕЖИМ"], W2))
	print(_rule(W2, "├", "┼", "┤"))
	for extra in [0.0, 4.0, 8.0, 12.0, 16.0, 17.0, 20.0, 40.0]:
		vic.vet_armor = extra
		var m: float = _mitigation(vic)
		var dd: float = _hit(vic, 20.0, foe)
		var mode: String = "пол 15%" if dd <= 20.0 * 0.15 + 0.001 else "вычитание"
		print(_row(["%.0f" % m, "%.2f" % dd, "%.0f%%" % ((1.0 - dd / 20.0) * 100.0), mode], W2))
	print(_rule(W2, "└", "┴", "┘"))
	vic.vet_armor = 0.0

	# ── БРОНЯ И ЗАЩИТА: ОДНО И ТО ЖЕ ЧИСЛО? ─────────────────────────────────
	print("\n─── ПРОВЕРКА: РАЗЛИЧАЮТСЯ ЛИ БРОНЯ И ЗАЩИТА ХОТЬ ЧЕМ-ТО ───")
	vic.vet_armor = 7.0; vic.vet_defense = 0.0
	var only_armor: float = _hit(vic, 20.0, foe)
	vic.vet_armor = 0.0; vic.vet_defense = 7.0
	var only_def: float = _hit(vic, 20.0, foe)
	vic.vet_armor = 3.0; vic.vet_defense = 4.0
	var mixed: float = _hit(vic, 20.0, foe)
	print("  +7 только в БРОНЮ  → урон %.2f" % only_armor)
	print("  +7 только в ЗАЩИТУ → урон %.2f" % only_def)
	print("  3 брони + 4 защиты → урон %.2f" % mixed)
	print("  ВЫВОД: %s" % ("оба слагаемых складываются в ОДНУ сумму, разницы нет"
		if absf(only_armor - only_def) < 0.001 and absf(mixed - only_def) < 0.001
		else "поведение различается — см. цифры выше"))
	vic.vet_armor = 0.0; vic.vet_defense = 0.0

	# ── ЗДАНИЯ: ЕСТЬ ЛИ У НИХ ЗАЩИТА ────────────────────────────────────────
	print("\n─── ЗДАНИЯ ───")
	var castle := Castle.new()
	castle.faction = P
	main.world_add(castle)
	castle.global_position = base + Vector3(30.0, 0.0, 30.0)
	await frames(3)
	var hp0: float = castle.current_health
	castle.take_damage(20.0, foe)
	print("  замок: удар 20 → снято %.2f HP (у построек снижения урона нет вовсе)" % [
		hp0 - castle.current_health])
	castle.queue_free()

	# ── ЛУЧНИК: ГДЕ СЧИТАЕТСЯ УРОН СТРЕЛЫ ───────────────────────────────────
	print("\n─── СТРЕЛКИ ───")
	var arc := _spawn("archer", P, base + Vector3(0.0, 0.0, 10.0))
	await frames(3)
	var arc_before: float = _atk(arc)
	var ok_arrows: bool = _buy(P, "arrows")
	print("  лучник: база %.0f → после слота «Стрелы» (куплен=%s) %.0f, уходит в стрелу целиком" % [
		arc_before, str(ok_arrows), _atk(arc)])
	print("  защита цели вычитается ПРИ КАСАНИИ стрелы, а не при выстреле")
	print("  устаревший канал get_upgrade(\"arrow_dmg\") = %.0f" % GameManager.get_upgrade(P, "arrow_dmg"))

	# ── ШЛЕМЫ: СВЕРКА ПОДПИСИ И ФАКТИЧЕСКОГО ЗНАЧЕНИЯ ───────────────────────
	print("\n─── СЛОТ «ШЛЕМЫ»: ЧТО НАПИСАНО И ЧТО ПРИМЕНЯЕТСЯ ───")
	var hp_before: float = vic.max_health
	var slot_h: Dictionary = _UCfg.get_upgrade_slot("helmets")
	var ok_helm: bool = _buy(P, "helmets")
	await frames(3)
	print("  подпись в кузнице: «%s», в конфиге bonus_health=%.0f" % [
		String(slot_h.get("desc", "")), float(slot_h.get("bonus_health", 0.0))])
	print("  куплено=%s: макс. HP копейщика %.0f → %.0f (прирост %.0f)" % [
		str(ok_helm), hp_before, vic.max_health, vic.max_health - hp_before])

	# ── СКОЛЬКО УДАРОВ ДО СМЕРТИ ────────────────────────────────────────────
	print("\n─── ЖИВУЧЕСТЬ: УДАРОВ ПО 20 ДО СМЕРТИ КОПЕЙЩИКА ───")
	var W3: Array = [34, 10, 12, 12]
	print(_rule(W3, "┌", "┬", "┐"))
	print(_row(["СОСТОЯНИЕ", "HP", "УРОН/УДАР", "УДАРОВ"], W3))
	print(_rule(W3, "├", "┼", "┤"))
	var probe := _spawn("spearman", E, base + Vector3(0.0, 0.0, 20.0))
	await frames(3)
	for cfg in [["голый рекрут (без кузницы)", false, false],
			["кузница, стойка АТАКА", true, false],
			["кузница, стойка ЗАЩИТА", true, true]]:
		var use_smithy: bool = bool(cfg[1])
		var use_def: bool    = bool(cfg[2])
		# probe — вражеской фракции, бонусы кузницы игрока на него не действуют
		var target: Unit = vic if use_smithy else probe
		target.set_stance(_UCfg.STANCE_DEFENSE if use_def else _UCfg.STANCE_ATTACK)
		var per: float = _hit(target, 20.0, foe)
		var hits: int = int(ceil(target.max_health / maxf(per, 0.001)))
		print(_row([String(cfg[0]), "%.0f" % target.max_health, "%.2f" % per, str(hits)], W3))
	print(_rule(W3, "└", "┴", "┘"))
	vic.set_stance(_UCfg.STANCE_ATTACK)

	# ── МЁРТВЫЕ КАНАЛЫ ──────────────────────────────────────────────────────
	print("\n─── СТАРЫЕ ОБЩЕФРАКЦИОННЫЕ АПГРЕЙДЫ (GameManager.upgrades) ───")
	print("  damage=%.0f  defense=%.0f  arrow_dmg=%.0f  health=%.0f" % [
		GameManager.get_upgrade(P, "damage"), GameManager.get_upgrade(P, "defense"),
		GameManager.get_upgrade(P, "arrow_dmg"), GameManager.get_upgrade(P, "health")])
	print("  (после ПОКУПКИ ВСЕХ доступных слотов кузницы — если тут нули, канал мёртв)")

	print("\n─── ИТОГ СВЕРКИ ───")
	print("  расхождений формулы и кода: %d" % _fails)
	print("\n=== MATH REPORT DONE ===")
	get_tree().quit()
