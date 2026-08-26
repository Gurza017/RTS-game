extends Node

## СТЕНД: ОПЫТ ОТРЯДА (ЗВЁЗДОЧКИ)
##   1 КОНФИГ    — зонд: пороги и величина бонуса берутся ИЗ КОНФИГА
##   2 СЧЁТ      — общий счёт отряда, границы N-1/N всех пяти порогов, перескок
##   3 ИСТОЧНИКИ — ближний бой, стрела лучника, снос здания, свой/без атакующего
##   4 ЗВЕЗДА    — лучи по уровню, носитель, перевешивание, отсутствие утечки
##   5 БОНУСЫ    — фактический урон/снижение урона/скорость/HP в бою
##   6 UI        — 5 кнопок вместо стоек, прирост через плюс, pending = 2
##   7 ПОПОЛНЕНИЕ— apply_squad_bonuses_to() выдаёт новобранцу всё заслуженное
##   8 НАГРУЗКА  — 330 юнитов со звёздами, медиана TIME_PHYSICS_PROCESS

const _Banner := preload("res://scripts/SquadBanner.gd")
const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _House := preload("res://scripts/House.gd")

var main: Node = null
var hud = null
var sm = null
var verdicts: Array = []
var barracks: Building = null
var squad: int = 0

## Свободный угол карты под одноразовые жертвы (подальше от боевых стендов)
var _dump_x: float = 400.0

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func verdict(title: String, ok: bool, detail: String = "") -> void:
	verdicts.append([title, ok])
	print("  ВЕРДИКТ %s: %s%s" % [title, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + detail) if detail != "" else ""])

func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	# СТЕНД РАБОТАЕТ ЗА ПРЕДЕЛАМИ КАРТЫ: площадки вынесены далеко в сторону,
	# чтобы ни ИИ, ни лес, ни чужие отряды не мешали замеру. Жёсткая граница
	# мира стянула бы их все в угол поля — на время стенда её снимаем
	GameManager.world_bounds_enabled = false
	await frames(2)
	hud = main.hud
	sm  = main.selection_manager
	for t in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD,
			Constants.RESOURCE_STONE, Constants.RESOURCE_FOOD]:
		ResourceManager.add_resource(Constants.FACTION_PLAYER, int(t), 500000.0)
	await frames(1)

	_test_config()
	await _test_config_probe()
	await _make_squad()
	await _test_kill_counting()
	await _test_boundaries()
	await _test_multi_pending()
	await _test_kill_sources()
	await _test_star_and_choice()
	await _test_all_levels()
	await _test_bonus_effects()
	await _test_ui()
	await _test_reinforcement()
	await _test_bearer_returns()
	await _test_leader_death()
	await _test_load()
	_summary()
	print("\n=== VET TEST DONE ===")
	get_tree().quit()

func _summary() -> void:
	print("\n═════ ИТОГ ═════")
	var bad := 0
	for v in verdicts:
		var row: Array = v
		if not bool(row[1]):
			bad += 1
		print("  %-58s %s" % [String(row[0]), "ПРОШЛО" if bool(row[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [bad, verdicts.size()])

# ═════════════════════════════════════════════════════════════════════════════
# ОБЩИЕ ХЕЛПЕРЫ
# ═════════════════════════════════════════════════════════════════════════════

## Небольшой отряд копейщиков «руками»: тот же API, что у бараков, но быстро
func make_squad(n: int, pos: Vector3, p_faction: int = Constants.FACTION_PLAYER) -> int:
	var sid: int = GameManager.new_squad(p_faction, "spearman")
	for i in range(n):
		var u := Spearman.new()
		u.faction = p_faction
		main.world_add(u)
		u.global_position = pos + Vector3(float(i) * 1.2, 0.0, 0.0)
		GameManager.add_to_squad(sid, u)
	await frames(1)
	return sid

## Одноразовая жертва вражеской фракции
func spawn_victim(p_faction: int, pos: Vector3, hp: float = -1.0) -> Unit:
	var v := Spearman.new()
	v.faction = p_faction
	main.world_add(v)
	v.global_position = pos
	if hp > 0.0:
		v.max_health = hp
		v.current_health = hp
	return v

func enemy_of(f: int) -> int:
	return Constants.FACTION_ENEMY if f == Constants.FACTION_PLAYER else Constants.FACTION_PLAYER

## Скормить отряду n настоящих фрагов (жертв бьют РАЗНЫЕ бойцы по кругу)
func feed_kills(sid: int, n: int) -> void:
	var members := GameManager.squad_members(sid)
	if members.is_empty():
		return
	var f: int = (members[0] as Unit).faction
	for i in range(n):
		_dump_x += 0.7
		if _dump_x > 460.0:
			_dump_x = 400.0
		var v := spawn_victim(enemy_of(f), Vector3(_dump_x, 0.0, 400.0))
		var killer: Unit = members[i % members.size()]
		v.take_damage(99999.0, killer)
		if i % 25 == 24:
			await get_tree().process_frame
	await frames(1)

## Подкрутить счётчик убийств отряда напрямую (уровень пересчитает credit_kill)
func set_kills(sid: int, k: int) -> void:
	if GameManager.squads.has(sid):
		GameManager.squads[sid]["kills"] = k

# ═════════════════════════════════════════════════════════════════════════════
func _test_config() -> void:
	print("\n═════ 1. КОНФИГ ВЕТЕРАНСТВА ═════")
	# Конфиг теперь раздельный по 4 боевым типам (VET_CONFIG) — стенд гоняет
	# копейщиков ("spearman"), поэтому и числа читает из их блока
	var utype := "spearman"
	print("  VET_CONFIG[%s].thresholds = %s" % [utype, str(_UCfg.VET_CONFIG[utype]["thresholds"])])
	print("  уровней всего: %d" % _UCfg.max_veteran_level(utype))
	for lvl in range(1, _UCfg.max_veteran_level(utype) + 1):
		var names: Array = []
		for c in _UCfg.veteran_choices(utype, lvl):
			var d: Dictionary = c
			names.append("%s(%s +%.1f)" % [
				String(d["name"]), String(d["stat"]), float(d["value"])])
		print("    уровень %d, порог %3d убийств: %s" % [
			lvl, _UCfg.veteran_threshold(utype, lvl), ", ".join(names)])
	var ok: bool = (_UCfg.VET_CONFIG[utype]["thresholds"] as Array).size() \
		== (_UCfg.VET_CONFIG[utype]["bonuses"] as Array).size()
	verdict("1 длина порогов = длине таблицы бонусов", ok)

## ЗОНД КОНФИГА. Печатает три числа, которые ОБЯЗАНЫ измениться, если поправить
## unit_stats_config.gd: порог 1-го уровня, уровень ровно на этом числе фрагов
## и величину прибавки, реально осевшей в поле бойца.
func _test_config_probe() -> void:
	print("\n═════ 1б. ЗОНД: ЧИСЛА ПРИХОДЯТ ИЗ КОНФИГА ═════")
	var t1: int = _UCfg.veteran_threshold("spearman", 1)
	var want: float = float((_UCfg.veteran_choices("spearman", 1)[0] as Dictionary)["value"])
	var sid: int = await make_squad(3, Vector3(-120.0, 0.0, -120.0))
	await feed_kills(sid, t1 - 1)
	var lvl_before: int = GameManager.squad_level(sid)
	await feed_kills(sid, 1)
	var lvl_after: int = GameManager.squad_level(sid)
	GameManager.apply_veteran_choice(sid, 0)
	var m0: Unit = GameManager.squad_members(sid)[0]
	print("  ЗОНД порог1=%d  уровень при %d фрагах=%d  при %d фрагах=%d  прибавка атаки в поле=%.1f (в конфиге %.1f)" % [
		t1, t1 - 1, lvl_before, t1, lvl_after, m0.vet_attack, want])
	verdict("1б порог из конфига сработал ровно на %d фрагах" % t1,
		lvl_before == 0 and lvl_after == 1)
	verdict("1б величина бонуса из конфига (%.1f) осела в бойце" % want,
		absf(m0.vet_attack - want) < 0.001, "vet_attack=%.1f" % m0.vet_attack)
	for m in GameManager.squad_members(sid):
		(m as Unit)._die()
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
func flush(bld: Building, cap: int = 400) -> void:
	var guard := 0
	while guard < cap:
		if bld == null or not is_instance_valid(bld):
			return
		if bld.production_queue.is_empty() and bld._pending_spawns.is_empty():
			return
		bld._production_timer = 99999.0
		await get_tree().process_frame
		guard += 1

func _make_squad() -> void:
	barracks = Barracks.new()
	barracks.faction = Constants.FACTION_PLAYER
	main.world_add(barracks)
	barracks.global_position = Vector3(-40.0, 0.0, -40.0)
	await frames(2)
	var before: Array = GameManager.squads.keys().duplicate()
	barracks.train_spearman()
	await flush(barracks)
	await frames(3)
	for key in GameManager.squads.keys():
		if not (key in before):
			squad = int(key)
			break
	print("\n  создан отряд из бараков id=%d, бойцов=%d" % [
		squad, GameManager.squad_members(squad).size()])

# ═════════════════════════════════════════════════════════════════════════════
func _test_kill_counting() -> void:
	print("\n═════ 2. СЧЁТ УБИЙСТВ ═════")
	var t1: int = _UCfg.veteran_threshold("spearman", 1)
	await feed_kills(squad, 5)
	print("  после 5 фрагов разными бойцами: счёт отряда=%d, уровень=%d, ждут выбора=%d" % [
		GameManager.squad_kills(squad), GameManager.squad_level(squad),
		GameManager.squad_pending(squad)])
	verdict("2 фраги любого бойца идут в общий счёт отряда",
		GameManager.squad_kills(squad) == 5,
		"счёт=%d" % GameManager.squad_kills(squad))
	verdict("2 до порога звания нет", GameManager.squad_level(squad) == 0)

	await feed_kills(squad, t1 - 5 - 1)
	var before_lvl: int = GameManager.squad_level(squad)
	print("  на %d убийстве (порог %d): уровень=%d" % [
		GameManager.squad_kills(squad), t1, before_lvl])
	await feed_kills(squad, 1)
	print("  на %d убийстве: уровень=%d, ждут выбора=%d" % [
		GameManager.squad_kills(squad), GameManager.squad_level(squad),
		GameManager.squad_pending(squad)])
	verdict("2 уровень выдан ровно на пороге %d" % t1,
		before_lvl == 0 and GameManager.squad_level(squad) == 1,
		"до=%d после=%d" % [before_lvl, GameManager.squad_level(squad)])

## ГРАНИЦЫ ВСЕХ ПЯТИ ПОРОГОВ: N-1 уровня ещё не даёт, N — даёт.
## Счётчик подкручивается до N-2, оба последних фрага — настоящие.
func _test_boundaries() -> void:
	print("\n═════ 2б. ГРАНИЦЫ ВСЕХ ПОРОГОВ (N-1 / N) ═════")
	var sid: int = await make_squad(3, Vector3(-140.0, 0.0, -120.0))
	# ОЖИДАЕМЫЙ УРОВЕНЬ СЧИТАЕТСЯ ПО КОНФИГУ, А НЕ ПО НОМЕРУ ШАГА ЦИКЛА.
	# В VET_CONFIG[type]["thresholds"] пороги НЕ обязаны быть строго возрастающими: сейчас
	# там [40, 120, 200, 200, 300] — два уровня выдаются на одном и том же счёте,
	# и 200-й фраг честно поднимает отряд сразу со 2-го на 4-й. Прежняя проверка
	# ждала «шаг цикла = уровень» и объявляла это сбоем, хотя сбоя нет: числа
	# в конфиге правит игрок под баланс, и стенд обязан следовать за ними
	# Порог, взятый ДВАЖДЫ, проверяем ОДИН раз. Уровень отряда не понижается
	# никогда — это правильно, — а стенд для проверки границы откатывает
	# счётчик на N-1. Повторно подойдя к тому же числу, отряд уже носит
	# добытое звание, и «ожидание по счётчику» на нём заведомо не сойдётся
	var distinct: Array = []
	for lvl0 in range(1, _UCfg.max_veteran_level("spearman") + 1):
		var t0: int = _UCfg.veteran_threshold("spearman", lvl0)
		if not (t0 in distinct):
			distinct.append(t0)
	var all_ok := true
	for thr_v in distinct:
		var thr: int = int(thr_v)
		set_kills(sid, thr - 2)
		await feed_kills(sid, 1)                       # ровно N-1
		var k1: int = GameManager.squad_kills(sid)
		var l1: int = GameManager.squad_level(sid)
		await feed_kills(sid, 1)                       # ровно N
		var k2: int = GameManager.squad_kills(sid)
		var l2: int = GameManager.squad_level(sid)
		var want1: int = _level_for_kills(thr - 1)
		var want2: int = _level_for_kills(thr)
		var ok: bool = (k1 == thr - 1 and l1 == want1 and k2 == thr and l2 == want2)
		all_ok = all_ok and ok
		print("    порог %3d: при %3d фрагах уровень=%d (ждали %d), при %3d фрагах уровень=%d (ждали %d)  %s" % [
			thr, k1, l1, want1, k2, l2, want2, "ок" if ok else "СБОЙ"])
	print("  накоплено наград без выбора: pending=%d" % GameManager.squad_pending(sid))
	verdict("2б уровень выдаётся РОВНО на пороге (порогов из конфига: %d)" % distinct.size(), all_ok)
	verdict("2б непотраченные награды копятся (pending=%d)" % _UCfg.max_veteran_level("spearman"),
		GameManager.squad_pending(sid) == _UCfg.max_veteran_level("spearman"),
		"pending=%d" % GameManager.squad_pending(sid))
	for m in GameManager.squad_members(sid):
		(m as Unit)._die()
	await frames(2)

## ПЕРЕСКОК ЧЕРЕЗ НЕСКОЛЬКО ПОРОГОВ РАЗОМ должен дать НЕСКОЛЬКО pending.
## Счётчик выставлен на порог2-1 при уровне 0 (имитация «выкосили толпу разом»),
## затем один НАСТОЯЩИЙ фраг.
func _test_multi_pending() -> void:
	print("\n═════ 2в. ПЕРЕСКОК ЧЕРЕЗ ДВА ПОРОГА ОДНИМ ФРАГОМ ═════")
	var sid: int = await make_squad(3, Vector3(-160.0, 0.0, -120.0))
	var t2: int = _UCfg.veteran_threshold("spearman", 2)
	set_kills(sid, t2 - 1)
	print("  счётчик выставлен на %d, уровень=%d, pending=%d" % [
		GameManager.squad_kills(sid), GameManager.squad_level(sid),
		GameManager.squad_pending(sid)])
	await feed_kills(sid, 1)
	print("  после ОДНОГО фрага: счёт=%d, уровень=%d, pending=%d" % [
		GameManager.squad_kills(sid), GameManager.squad_level(sid),
		GameManager.squad_pending(sid)])
	verdict("2в один фраг через два порога → уровень 2",
		GameManager.squad_level(sid) == 2, "уровень=%d" % GameManager.squad_level(sid))
	verdict("2в выдано СРАЗУ ДВЕ награды, а не одна",
		GameManager.squad_pending(sid) == 2, "pending=%d" % GameManager.squad_pending(sid))
	var grade: int = _banner_grade(sid)
	print("  знамя сразу под грейд %d" % grade)
	verdict("2в знамя сразу показывает 2 уровня", grade == 2, "грейд=%d" % grade)
	for m in GameManager.squad_members(sid):
		(m as Unit)._die()
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# 3. ИСТОЧНИКИ ФРАГОВ
# ═════════════════════════════════════════════════════════════════════════════
func _test_kill_sources() -> void:
	print("\n═════ 3. ИСТОЧНИКИ ФРАГОВ ═════")

	# ── 3.1 БЛИЖНИЙ БОЙ (настоящий удар копьём) ──────────────────────────────
	var sid: int = await make_squad(1, Vector3(200.0, 0.0, 0.0))
	var hero: Unit = GameManager.squad_members(sid)[0]
	var v := spawn_victim(Constants.FACTION_ENEMY, Vector3(201.5, 0.0, 0.0), 6.0)
	await frames(1)
	hero.command_attack(v, true)
	var k0: int = GameManager.squad_kills(sid)
	# ЖДЁМ ФИЗИЧЕСКИЕ КАДРЫ, А НЕ КАДРЫ ОТРИСОВКИ. При Engine.max_fps = 0
	# отрисовка обгоняет фиксированные 60 Гц физики, и «400 кадров» означали
	# то полсекунды симуляции, то семь — отсюда и плавающая краснота
	var waited := 0
	while waited < 400 and is_instance_valid(v) and not v.is_dead():
		await get_tree().physics_frame
		waited += 1
	var k1: int = GameManager.squad_kills(sid)
	print("  ближний бой: цель убита за %d кадров, счёт %d → %d" % [waited, k0, k1])
	verdict("3 ближний бой засчитан", k1 == k0 + 1, "счёт %d→%d" % [k0, k1])
	hero.command_move(hero.global_position)
	await frames(2)

	# ── 3.2 СТРЕЛА ЛУЧНИКА (урон списывает Arrow, стрелок передан) ───────────
	var asid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "archer")
	var arch := Archer.new()
	arch.faction = Constants.FACTION_PLAYER
	main.world_add(arch)
	arch.global_position = Vector3(220.0, 0.0, 0.0)
	GameManager.add_to_squad(asid, arch)
	await frames(2)
	var av := spawn_victim(Constants.FACTION_ENEMY, Vector3(228.0, 0.0, 0.0), 6.0)
	await frames(1)
	av.command_move(av.global_position)      # чтобы не бежал на лучника
	arch.command_attack(av, true)
	var ak0: int = GameManager.squad_kills(asid)
	waited = 0
	# Запас по времени щедрый НАМЕРЕННО: проверка про ЗАЧЁТ ФРАГА, а не про
	# меткость. Разброс стрелка случайный, и у отряда нулевого уровня выучки
	# он ещё и шире (unit_stats_config.ARCHER_DRILL) — короткий бюджет делал
	# вердикт про бухгалтерию убийств броском монеты
	while waited < 1200 and is_instance_valid(av) and not av.is_dead():
		await get_tree().physics_frame
		waited += 1
	var ak1: int = GameManager.squad_kills(asid)
	print("  стрела: цель убита за %d кадров, счёт отряда лучников %d → %d" % [
		waited, ak0, ak1])
	verdict("3 фраг стрелой засчитан отряду лучника", ak1 == ak0 + 1,
		"счёт %d→%d" % [ak0, ak1])
	arch._die()
	await frames(2)

	# ── 3.3 СНОС ВРАЖЕСКОГО ЗДАНИЯ ──────────────────────────────────────────
	var bsid: int = await make_squad(1, Vector3(240.0, 0.0, 0.0))
	var sapper: Unit = GameManager.squad_members(bsid)[0]
	var house: Building = _House.new()
	house.faction = Constants.FACTION_ENEMY
	main.world_add(house)
	house.global_position = Vector3(242.0, 0.0, 0.0)
	await frames(2)
	house.current_health = 5.0
	sapper.command_attack(house, true)
	var bk0: int = GameManager.squad_kills(bsid)
	waited = 0
	while waited < 400 and is_instance_valid(house) and not house.is_dead():
		await get_tree().process_frame
		waited += 1
	var bk1: int = GameManager.squad_kills(bsid)
	print("  снос дома: рухнул за %d кадров, счёт %d → %d" % [waited, bk0, bk1])
	verdict("3 снос вражеского здания засчитан", bk1 == bk0 + 1,
		"счёт %d→%d" % [bk0, bk1])

	# ── 3.4 УБИЙСТВО СВОЕГО — начисляться НЕ должно ─────────────────────────
	var fk0: int = GameManager.squad_kills(bsid)
	var friend := spawn_victim(Constants.FACTION_PLAYER, Vector3(250.0, 0.0, 10.0), 10.0)
	await frames(1)
	friend.take_damage(9999.0, sapper)
	await frames(2)
	var fk1: int = GameManager.squad_kills(bsid)
	print("  убит СВОЙ юнит: счёт %d → %d" % [fk0, fk1])
	verdict("3 убийство своего НЕ засчитывается", fk1 == fk0,
		"счёт %d→%d" % [fk0, fk1])

	# ── 3.5 СМЕРТЬ БЕЗ АТАКУЮЩЕГО (null) ────────────────────────────────────
	var nk0: int = GameManager.squad_kills(bsid)
	var nobody := spawn_victim(Constants.FACTION_ENEMY, Vector3(250.0, 0.0, 20.0), 10.0)
	await frames(1)
	nobody.take_damage(9999.0, null)
	await frames(2)
	var nk1: int = GameManager.squad_kills(bsid)
	print("  смерть без атакующего: счёт %d → %d" % [nk0, nk1])
	verdict("3 смерть без атакующего ничего не начисляет", nk1 == nk0,
		"счёт %d→%d" % [nk0, nk1])
	for m in GameManager.squad_members(bsid):
		(m as Unit)._die()
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
## ── ЗВЁЗДЫ ЗАМЕНЕНЫ ЗНАМЁНАМИ (заказ владельца, авг. 2026) ─────────────────
## Проверки ниже переписаны с «сколько лучей у звезды» на «под какой грейд
## построено знамя». Смысл у них тот же и остался прежним: метка обязана
## показывать ровно тот уровень, который отряд заслужил, и обязана появляться на
## пороге. Менялась не проверка, а то, чем эта метка нарисована.
func _find_banner(sid: int) -> Node:
	if not GameManager.squads.has(sid):
		return null
	var s = (GameManager.squads[sid] as Dictionary).get("banner")
	return s if (s != null and is_instance_valid(s)) else null

## КАКОЙ УРОВЕНЬ ПОЛОЖЕН ЗА ТАКОЙ СЧЁТ — по конфигу и только по нему.
## Считаем, сколько порогов уже взято. Формула не делает НИКАКИХ допущений о
## порогах: они могут повторяться, идти с любым шагом, их может быть сколько
## угодно — стенд следует за таблицей, а не наоборот
func _level_for_kills(kills: int, unit_type: String = "spearman") -> int:
	var lvl := 0
	for i in range(_UCfg.max_veteran_level(unit_type)):
		if kills >= _UCfg.veteran_threshold(unit_type, i + 1):
			lvl = i + 1
	return lvl

## Под какой грейд построено знамя. Ноль — знамени нет вовсе
func _banner_grade(sid: int) -> int:
	var b := _find_banner(sid)
	return int(b.shown_level) if b != null else 0

## Сколько лычек показывает панель на этом уровне. Из того же конфига, по
## которому нарисовано само знамя (veteran_badge_text) — держать в стенде свою
## копию шкалы нельзя, она разъедется с игрой при первой правке
func _want_badge(lvl: int) -> String:
	return _UCfg.veteran_badge_text(lvl)

func _test_star_and_choice() -> void:
	print("\n═════ 4. ЗНАМЯ ВЕТЕРАНСТВА И ВЫБОР БОНУСА ═════")
	var banner := _find_banner(squad)
	var bearer = GameManager.squad_bearer(squad)
	print("  знамя есть: %s, грейд=%d, знаменосец=%s" % [
		str(banner != null), _banner_grade(squad), str(bearer != null)])
	verdict("4 знамя зажглось на пороге", banner != null)
	verdict("4 у знамени есть знаменосец", bearer != null)

	# ── ЗДЕСЬ ПРОВЕРЯЛОСЬ «ЗВЕЗДА СТОИТ ПО ЦЕНТРУ МАСС», И ЭТО РАЗВЁРНУТО ────
	# Звезда была меткой над отрядом и потому висела над средней точкой — над
	# местом, где может вообще никого не быть. Знамя — ПРЕДМЕТ В РУКАХ бойца, и
	# требование теперь ровно обратное: оно обязано стоять НА ЗНАМЕНОСЦЕ.
	# Допуск — смещение древка от центра бойца плюс сантиметр на сглаживание
	# картинки (знамя ставится по НАРИСОВАННОЙ точке, см. SquadBanner)
	for _i in range(90):
		await get_tree().physics_frame
	banner = _find_banner(squad)
	bearer = GameManager.squad_bearer(squad)
	var bp: Vector3 = (bearer as Unit).draw_position() if bearer != null else Vector3.ZERO
	var got_c: Vector3 = (banner as Node3D).global_position if banner != null else Vector3.ZERO
	var off: float = Vector2(got_c.x - bp.x - _Banner.POLE_OFFSET_X,
		got_c.z - bp.z).length()
	verdict("4 знамя стоит на знаменосце, а не над центром масс",
		banner != null and bearer != null and off <= 0.10,
		"боец=(%.2f, %.2f) знамя=(%.2f, %.2f), расхождение %.3f м" % [
			bp.x, bp.z, got_c.x, got_c.z, off])
	verdict("4 знамя не ребёнок бойца (иначе отстаёт от спрайта)",
		banner != null and not (banner.get_parent() is Unit))
	verdict("4 на 1 уровне знамя первого грейда", _banner_grade(squad) == 1,
		"грейд=%d" % _banner_grade(squad))

	var members := GameManager.squad_members(squad)
	sm._clear_selection()
	sm._select(members[0])
	GameManager.on_selection_changed(sm.selected_units)
	await frames(3)
	var labels: Array = []
	for b in hud.button_container.get_children():
		labels.append(((b as Button).text if (b as Button).text != "" else (b as Button).tooltip_text))
	print("  подпись панели: «%s»" % hud.info_label.text)
	print("  кнопки: %s" % str(labels))
	# СТЕНД НЕ ХАРДКОДИТ ЧИСЛО НАГРАД. Сколько их на уровне —
	# решает владелец в unit_stats_config; проверять надо СООТВЕТСТВИЕ
	# панели конфигу, а не равенство пятёрке (правило проекта 10)
	var want_btn: int = _UCfg.veteran_choices("spearman", 1).size()
	verdict("4 кнопок на панели столько же, сколько наград в конфиге",
		labels.size() == want_btn, "кнопок=%d, в конфиге=%d" % [labels.size(), want_btn])

	var atk_before: float = (members[0] as Unit).vet_attack
	var choices: Array = _UCfg.veteran_choices("spearman", 1)
	var want: float = float((choices[0] as Dictionary)["value"])
	(hud.button_container.get_child(0) as Button).pressed.emit()
	await frames(3)
	var applied := 0
	for m in GameManager.squad_members(squad):
		if absf((m as Unit).vet_attack - (atk_before + want)) < 0.001:
			applied += 1
	print("  после нажатия «%s»: vet_attack=%.1f у %d бойцов из %d" % [
		String((choices[0] as Dictionary)["name"]),
		(members[0] as Unit).vet_attack, applied, GameManager.squad_members(squad).size()])
	verdict("4 бонус получили ВСЕ модели отряда",
		applied == GameManager.squad_members(squad).size(),
		"получили=%d из %d" % [applied, GameManager.squad_members(squad).size()])
	verdict("4 награда списана (pending снова 0)",
		GameManager.squad_pending(squad) == 0,
		"pending=%d" % GameManager.squad_pending(squad))
	print("  суммарный ветеранский бонус отряда по атаке: +%.1f" % [
		GameManager.squad_bonus(squad, "attack")])

# ═════════════════════════════════════════════════════════════════════════════
func _test_all_levels() -> void:
	print("\n═════ 4б-6. ВСЕ 5 УРОВНЕЙ, СТАТЫ И ЛУЧИ ЗВЕЗДЫ ═════")
	var members := GameManager.squad_members(squad)
	sm._clear_selection()
	sm._select(members[0])
	GameManager.on_selection_changed(sm.selected_units)
	await frames(3)
	print("  строка статов: «%s»" % hud.progress_label.text)
	# ОЖИДАЕМАЯ СТРОКА СОБИРАЕТСЯ ИЗ ЖИВЫХ ЧИСЕЛ. Раньше здесь стояло
	# «Атака: 15 (+5)» текстом: стоило поправить value в конфиге — и проверка
	# падала, хотя интерфейс работал правильно
	var got_att: float = GameManager.squad_bonus(squad, "attack")
	var want_att := "(+%d)" % int(round(got_att))
	verdict("6 прирост показан через плюс («Атака: N (+M)»)",
		got_att <= 0.0 or want_att in hud.progress_label.text,
		"ждали «%s» в строке, получили «%s»" % [want_att, hud.progress_label.text])

	var maxlvl: int = _UCfg.max_veteran_level("spearman")
	var rays_ok := true
	# СУММА ОЖИДАЕМЫХ БОНУСОВ КОПИТСЯ ПО ФАКТУ ВЫБОРА. Уровни дают разные
	# величины (в конфиге сейчас 2/3/5/5/5), поэтому «maxlvl × значение первого
	# выбора» — заведомо неверная арифметика
	var want_total: float = GameManager.squad_bonus(squad, "attack") \
		+ GameManager.squad_bonus(squad, "armor") \
		+ GameManager.squad_bonus(squad, "defense") \
		+ GameManager.squad_bonus(squad, "speed") \
		+ GameManager.squad_bonus(squad, "health")
	var awarded := 0
	# Идём НЕ по номерам уровней, а по НЕВЫБРАННЫМ наградам: при повторяющихся
	# порогах один фраг приносит сразу две, и цикл по уровням их бы пропустил
	var guard := 0
	while GameManager.squad_level(squad) < maxlvl and guard < 50:
		guard += 1
		if GameManager.squad_pending(squad) <= 0:
			var nxt: int = GameManager.squad_level(squad) + 1
			set_kills(squad, _UCfg.veteran_threshold("spearman", nxt) - 1)
			await feed_kills(squad, 1)
			continue
		var lvl: int = GameManager.squad_level(squad)
		var choices: Array = _UCfg.veteran_choices("spearman", lvl)
		var pick: int = mini(lvl - 1, choices.size() - 1)
		var entry: Dictionary = choices[pick]
		var ok: bool = GameManager.apply_veteran_choice(squad, pick)
		if ok:
			want_total += _reward_sum(entry)
			awarded += 1
		var grade: int = _banner_grade(squad)
		if grade != GameManager.squad_level(squad):
			rays_ok = false
		print("    уровень %d при %d убийствах, выбрано «%s» (+%.1f) → %s, грейд знамени=%d" % [
			GameManager.squad_level(squad), GameManager.squad_kills(squad),
			String(entry.get("name", "?")), float(entry.get("value", 0.0)),
			str(ok), grade])
	# Добираем награды, накопившиеся на последнем шаге
	while GameManager.squad_pending(squad) > 0 and guard < 60:
		guard += 1
		var lvl2: int = GameManager.squad_level(squad)
		var ch2: Array = _UCfg.veteran_choices("spearman", lvl2)
		var pick2: int = mini(lvl2 - 1, ch2.size() - 1)
		var e2: Dictionary = ch2[pick2]
		if GameManager.apply_veteran_choice(squad, pick2):
			want_total += _reward_sum(e2)
			awarded += 1
			print("    добор награды на уровне %d: «%s» (+%.1f)" % [
				lvl2, String(e2.get("name", "?")), float(e2.get("value", 0.0))])
		if _banner_grade(squad) != GameManager.squad_level(squad):
			rays_ok = false
	verdict("6 достигнут максимальный уровень %d" % maxlvl,
		GameManager.squad_level(squad) == maxlvl,
		"уровень=%d" % GameManager.squad_level(squad))
	verdict("6 все награды выбраны", GameManager.squad_pending(squad) == 0)
	verdict("4б грейд знамени = уровню отряда на всех уровнях", rays_ok)

	var m0: Unit = GameManager.squad_members(squad)[0]
	print("  итог по бойцу: атака+%.0f броня+%.0f защита+%.0f скорость+%.1f HP=%.0f" % [
		m0.vet_attack, m0.vet_armor, m0.vet_defense, m0.vet_speed, m0.max_health])
	var bonuses: Dictionary = GameManager.squads[squad]["bonuses"]
	print("  бонусы отряда: %s" % str(bonuses))
	var total := 0.0
	for k in bonuses:
		total += float(bonuses[k])
	# Сверяем с суммой того, что РЕАЛЬНО было выбрано (величины взяты из
	# конфига в момент выбора), а не с числом, посчитанным заранее
	# ОЖИДАЕМОЕ ПЕРЕСЧИТЫВАЕТСЯ ИЗ КОНФИГА ПО СПИСКУ ВЫБРАННОГО,
	# а не копится по ходу теста. Отряд помнит свой выбор (sq["chosen"],
	# i-я запись — награда за уровень i+1), и этого достаточно, чтобы
	# собрать ожидание заново. Накопление по ходу пропускало награды,
	# выданные не циклом стенда, а подготовкой (arm_squad)
	var chosen: Array = GameManager.squads[squad].get("chosen", [])
	var want_cfg := 0.0
	for ci in range(chosen.size()):
		var lst: Array = _UCfg.veteran_choices("spearman", ci + 1)
		for e3 in lst:
			if String((e3 as Dictionary).get("id", "")) == String(chosen[ci]):
				want_cfg += _reward_sum(e3)
				break
	print("  выбрано по уровням: %s" % str(chosen))
	verdict("6 сумма начисленного равна сумме модификаторов выбранного",
		absf(total - want_cfg) < 0.01,
		"начислено=%.1f, по конфигу=%.1f (наград %d)" % [total, want_cfg, chosen.size()])

	sm._clear_selection()
	sm._select(GameManager.squad_members(squad)[0])
	GameManager.on_selection_changed(sm.selected_units)
	await frames(2)
	print("  подпись панели с максимумом: «%s»" % hud.info_label.text)
	# ── ЗДЕСЬ ПРОВЕРЯЛСЯ ЗНАЧОК ЛЫЧЕК В ПОДПИСИ, И ТРЕБОВАНИЕ РАЗВЁРНУТО ────
	# Заказ владельца (авг. 2026): «убрать символьные лычки из заголовков UI»,
	# а название отряда собирать словами — «Отряд легендарных копейщиков».
	# Значок остался там, где на слова нет места: на портрете и на карточке
	# отряда. Проверяем ровно новое требование: в заголовке ЕСТЬ звание и НЕТ
	# значка
	verdict("6 в подписи звание словами, а не значок",
		_UCfg.veteran_rank_name("spearman", maxlvl) in hud.info_label.text
			and not (_want_badge(maxlvl) in hud.info_label.text),
		"подпись «%s», ждали «%s» без значка «%s»" % [hud.info_label.text,
			_UCfg.veteran_rank_name("spearman", maxlvl), _want_badge(maxlvl)])

# ═════════════════════════════════════════════════════════════════════════════
# 5. БОНУСЫ РАБОТАЮТ В БОЮ
# ═════════════════════════════════════════════════════════════════════════════

## Довести отряд до 1 уровня с одной невыбранной наградой
func arm_squad(sid: int, unit_type: String = "spearman") -> void:
	set_kills(sid, _UCfg.veteran_threshold(unit_type, 1) - 1)
	await feed_kills(sid, 1)

## НАСТОЯЩИЙ удар копьём по живой цели.
## Возвращает [снятое HP, восстановленный урон удара].
## Собственные защита/броня жертвы обнулены, а фракционные апгрейды читаются
## В МОМЕНТ ПОПАДАНИЯ: вражеский ИИ по ходу партии исследует «Щиты»/«Броню»,
## и без этой поправки замер «до» и «после» шёл бы по разной цели.
func measure_melee(attacker: Unit, at: Vector3) -> Array:
	var v := spawn_victim(enemy_of(attacker.faction), at + Vector3(1.4, 0.0, 0.0), 100000.0)
	await frames(1)
	v.defense = 0.0
	v.armor   = 0.0
	v.command_move(v.global_position)
	attacker.global_position = at
	attacker.command_attack(v, true)
	var before: float = v.current_health
	var got := 0.0
	var soak := 0.0
	for _i in range(400):
		await get_tree().process_frame
		if not is_instance_valid(v):
			break
		if v.current_health < before - 0.0001:
			got = before - v.current_health
			# Полное зеркало формулы Unit.take_damage: ИИ по ходу партии и
			# исследует броню, и переводит своих в стойку «защита» (+5)
			soak = v.defense + v.armor \
				+ GameManager.get_upgrade(v.faction, "defense") \
				+ GameManager.unit_bonus(v.faction, v.stat_id, "bonus_armor") \
				+ v.vet_armor + v.vet_defense \
				+ _UCfg.stance_stat(v.stance, "defense_bonus", 0.0)
			break
	attacker.command_move(attacker.global_position)
	if is_instance_valid(v):
		v.queue_free()
	await frames(1)
	return [got, got + soak]

## Реальное снижение входящего урона: бьём фиксированной цифрой через take_damage
func measure_taken(target: Unit, amount: float) -> float:
	target.max_health     = 100000.0
	target.current_health = 100000.0
	var before: float = target.current_health
	target.take_damage(amount, null)
	return before - target.current_health

func _test_bonus_effects() -> void:
	print("\n═════ 5. БОНУСЫ РАБОТАЮТ В БОЮ (фактические числа) ═════")
	# ── БЛОК ИДЁТ ПО СОСТАВУ КОНФИГА, А НЕ ПО НОМЕРАМ 0..4 ─────────────────
	# Прежняя версия брала награды по фиксированным индексам и сверяла эффект
	# с полем "value". Оба допущения больше неверны: владелец меняет и ЧИСЛО
	# наград на уровень, и их набор, а сама награда давно не одна пара
	# stat/value, а НАБОР модификаторов («+3 к Броне» даёт ещё и защиту, и
	# урон, и минус к скорости). Поэтому каждая награда проверяется ПО СВОИМ
	# МОДИФИКАТОРАМ: сколько обещала — столько и обязана дать
	var lst: Array = _UCfg.veteran_choices("spearman", 1)
	for idx in range(lst.size()):
		var e: Dictionary = lst[idx]
		var eid: String = String(e.get("id", ""))
		var nm: String = String(e.get("name", eid))
		var at: Vector3 = Vector3(300.0 + float(idx) * 10.0, 0.0, 0.0)
		var b_atk: float = float(e.get("bonus_attack", 0.0))
		var b_arm: float = float(e.get("bonus_armor", 0.0))
		var b_def: float = float(e.get("bonus_defense", 0.0))
		var b_spd: float = float(e.get("bonus_speed", 0.0))
		var b_hp: float  = float(e.get("bonus_health", 0.0))
		if eid == "attack" and b_atk > 0.0:
			var sq_a: int = await make_squad(1, at)
			var a: Unit = GameManager.squad_members(sq_a)[0]
			var r1: Array = await measure_melee(a, at)
			await arm_squad(sq_a)
			GameManager.apply_veteran_choice(sq_a, idx)
			var r2: Array = await measure_melee(a, at)
			var d_before: float = float(r1[1])
			var d_after: float = float(r2[1])
			print("  АТАКА «%s»: сила удара %.1f → %.1f (ждали +%.1f), vet_attack=%.1f" % [
				nm, d_before, d_after, b_atk, a.vet_attack])
			verdict("5 «%s» реально увеличила урон на %.1f" % [nm, b_atk],
				absf((d_after - d_before) - b_atk) < 0.01,
				"было %.1f стало %.1f" % [d_before, d_after])
		elif (eid == "armor" or eid == "defense") and (b_arm + b_def) > 0.0:
			# БРОНЯ И ЗАЩИТА СРЕЗАЮТ УРОН ОДИНАКОВО, поэтому ждём их СУММУ:
			# награда «+3 к Броне» в конфиге даёт и то, и другое
			var sq_b: int = await make_squad(1, at)
			var bu: Unit = GameManager.squad_members(sq_b)[0]
			var t_before: float = measure_taken(bu, 60.0)
			await arm_squad(sq_b)
			GameManager.apply_veteran_choice(sq_b, idx)
			var t_after: float = measure_taken(bu, 60.0)
			var want_cut: float = b_arm + b_def
			print("  ЗАЩИТА «%s»: из 60 прошло %.1f → %.1f (ждали -%.1f), vet_armor=%.1f vet_defense=%.1f" % [
				nm, t_before, t_after, want_cut, bu.vet_armor, bu.vet_defense])
			verdict("5 «%s» реально срезала урон на %.1f" % [nm, want_cut],
				absf((t_before - t_after) - want_cut) < 0.01,
				"было %.1f стало %.1f" % [t_before, t_after])
		elif eid == "health" and b_hp > 0.0:
			var sq_h: int = await make_squad(1, at)
			var h: Unit = GameManager.squad_members(sq_h)[0]
			var hp_before: float = h.max_health
			await arm_squad(sq_h)
			GameManager.apply_veteran_choice(sq_h, idx)
			print("  HP «%s»: max_health %.0f → %.0f (ждали +%.0f)" % [
				nm, hp_before, h.max_health, b_hp])
			verdict("5 «%s» реально подняла max_health" % nm,
				absf((h.max_health - hp_before) - b_hp) < 0.01,
				"было %.0f стало %.0f" % [hp_before, h.max_health])
		elif eid == "speed" and absf(b_spd) > 0.0:
			var sq_s: int = await make_squad(1, at)
			var su: Unit = GameManager.squad_members(sq_s)[0]
			var v_before: float = su._effective_speed()
			await arm_squad(sq_s)
			GameManager.apply_veteran_choice(sq_s, idx)
			var v_after: float = su._effective_speed()
			print("  СКОРОСТЬ «%s»: %.2f → %.2f (ждали %+.2f)" % [
				nm, v_before, v_after, b_spd])
			verdict("5 «%s» реально изменила _effective_speed()" % nm,
				absf((v_after - v_before) - b_spd) < 0.01,
				"было %.2f стало %.2f" % [v_before, v_after])
		else:
			# Мораль, напор, откат и прочее здесь не мерятся: их действие
			# проверяют свои блоки. Строка в печати обязательна — без неё
			# непонятно, что награда вообще была рассмотрена
			print("  «%s» (%s): прямого боевого замера нет, пропущена" % [nm, eid])

func button_labels() -> Array:
	var labels: Array = []
	for b in hud.button_container.get_children():
		labels.append(((b as Button).text if (b as Button).text != "" else (b as Button).tooltip_text))
	return labels

func select_squad(sid: int) -> void:
	sm._clear_selection()
	sm._select(GameManager.squad_members(sid)[0])
	GameManager.on_selection_changed(sm.selected_units)
	await frames(3)

func _test_ui() -> void:
	print("\n═════ 6. ИНТЕРФЕЙС: pending = 2, ДВА ВЫБОРА ПОДРЯД ═════")
	var sid: int = await make_squad(4, Vector3(-180.0, 0.0, -120.0))
	set_kills(sid, _UCfg.veteran_threshold("spearman", 2) - 1)
	await feed_kills(sid, 1)                 # сразу два уровня → pending = 2
	await select_squad(sid)
	var l1: Array = button_labels()
	print("  pending=%d, подпись: «%s»" % [GameManager.squad_pending(sid), hud.info_label.text])
	print("  кнопки: %s" % str(l1))
	print("  строка статов: «%s»" % hud.progress_label.text)
	var want_b1: int = _UCfg.veteran_choices("spearman", maxi(GameManager.squad_level(sid) - GameManager.squad_pending(sid) + 1, 1)).size()
	verdict("6 при pending>0 кнопок столько же, сколько наград в конфиге",
		l1.size() == want_b1, "кнопок=%d, в конфиге=%d" % [l1.size(), want_b1])
	verdict("6 стоек [Attack]/[Defend] на панели нет",
		not ("Attack" in l1) and not ("Defend" in l1), "кнопки=%s" % str(l1))
	# ── СЛУЖЕБНОЙ СТРОКИ «★ Ветеран N» БОЛЬШЕ НЕТ, А ЗВАНИЕ ОСТАЛОСЬ ───────
	# Требование развёрнуто владельцем (авг. 2026) и тут же уточнено: убрать
	# надо было СЛУЖЕБНУЮ подсказку, а название со званием («Отряд опытных
	# копейщиков») — «не убирать ни в коем случае». Вместо подсказки в панели
	# стоят знамёна рангов (HUD._show_vet_rank_row)
	verdict("6 вместо служебной подписи показан ряд флажков ранга",
		hud._vet_rank_row != null and hud._vet_rank_row.visible
		and hud._vet_rank_row.get_child_count() > 0
		and not String(hud.info_label.text).contains("выберите награду"),
		"флажков=%d, подпись «%s»" % [
			hud._vet_rank_row.get_child_count() if hud._vet_rank_row != null else -1,
			hud.info_label.text])

	(hud.button_container.get_child(0) as Button).pressed.emit()
	await frames(3)
	var l2: Array = button_labels()
	print("  после ПЕРВОГО выбора: pending=%d, подпись «%s», кнопки %s" % [
		GameManager.squad_pending(sid), hud.info_label.text, str(l2)])
	# Второй уровень виден не подписью, а ВТОРЫМ флажком в ряду: у ранга 2 своё
	# знамя (две лычки), и узел его так и называется — VetFlag_2
	var flag2: Node = null
	if hud._vet_rank_row != null:
		flag2 = hud._vet_rank_row.get_node_or_null("VetFlag_2")
	verdict("6 после первого выбора панель предлагает ВТОРУЮ награду",
		GameManager.squad_pending(sid) == 1
		and l2.size() == _UCfg.veteran_choices("spearman",
			maxi(GameManager.squad_level(sid) - GameManager.squad_pending(sid) + 1, 1)).size()
		and flag2 != null,
		"pending=%d кнопок=%d флажок 2-го ранга=%s" % [
			GameManager.squad_pending(sid), l2.size(), str(flag2 != null)])

	(hud.button_container.get_child(1) as Button).pressed.emit()
	await frames(3)
	var l3: Array = button_labels()
	print("  после ВТОРОГО выбора: pending=%d, подпись «%s», кнопки %s" % [
		GameManager.squad_pending(sid), hud.info_label.text, str(l3)])
	print("  строка статов: «%s»" % hud.progress_label.text)
	verdict("6 стойки вернулись после выбора всех наград",
		# Кнопок теперь три: к двум стойкам добавилась «В ЗАМОК» (отправить
		# отряд лечиться). Проверяем СОСТАВ, а не точное число — иначе любая
		# новая команда отряда будет валить эту проверку на ровном месте
		("Attack" in l3) and ("Defend" in l3), "кнопки=%s" % str(l3))
	verdict("6 в подписи звание второго грейда словами",
		_UCfg.veteran_rank_name("spearman", 2) in hud.info_label.text
			and not (_want_badge(2) in hud.info_label.text),
		"подпись «%s», ждали «%s» без значка «%s»" % [hud.info_label.text,
			_UCfg.veteran_rank_name("spearman", 2), _want_badge(2)])
	for m in GameManager.squad_members(sid):
		(m as Unit)._die()
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# 7. ПОПОЛНЕНИЕ ОТРЯДА
# ═════════════════════════════════════════════════════════════════════════════
func _test_reinforcement() -> void:
	print("\n═════ 7. ПОПОЛНЕНИЕ: НОВОБРАНЕЦ ПОЛУЧАЕТ ВСЁ ЗАСЛУЖЕННОЕ ═════")
	var sid: int = await make_squad(3, Vector3(-200.0, 0.0, -120.0))
	# Три награды: атака, броня, макс. HP
	for step in [0, 1, 4]:
		set_kills(sid, _UCfg.veteran_threshold("spearman", GameManager.squad_level(sid) + 1) - 1)
		await feed_kills(sid, 1)
		GameManager.apply_veteran_choice(sid, int(step))
	var vet: Unit = GameManager.squad_members(sid)[0]
	print("  бонусы отряда: %s" % str(GameManager.squads[sid]["bonuses"]))
	print("  ветеран: атака+%.1f броня+%.1f защита+%.1f скорость+%.1f max_hp=%.0f" % [
		vet.vet_attack, vet.vet_armor, vet.vet_defense, vet.vet_speed, vet.max_health])

	var recruit := Spearman.new()
	recruit.faction = Constants.FACTION_PLAYER
	main.world_add(recruit)
	recruit.global_position = Vector3(-200.0, 0.0, -110.0)
	await frames(1)
	var raw_hp: float = recruit.max_health
	GameManager.add_to_squad(sid, recruit)
	GameManager.apply_squad_bonuses_to(sid, recruit)
	print("  новобранец до пополнения max_hp=%.0f, после: атака+%.1f броня+%.1f защита+%.1f скорость+%.1f max_hp=%.0f" % [
		raw_hp, recruit.vet_attack, recruit.vet_armor, recruit.vet_defense,
		recruit.vet_speed, recruit.max_health])
	var same: bool = absf(recruit.vet_attack  - vet.vet_attack)  < 0.001 \
		and absf(recruit.vet_armor   - vet.vet_armor)   < 0.001 \
		and absf(recruit.vet_defense - vet.vet_defense) < 0.001 \
		and absf(recruit.vet_speed   - vet.vet_speed)   < 0.001 \
		and absf(recruit.max_health  - vet.max_health)  < 0.001
	verdict("7 новобранец догнал ветеранов по всем 3 наградам", same,
		"новобранец атака+%.1f броня+%.1f hp=%.0f / ветеран атака+%.1f броня+%.1f hp=%.0f" % [
			recruit.vet_attack, recruit.vet_armor, recruit.max_health,
			vet.vet_attack, vet.vet_armor, vet.max_health])
	for m in GameManager.squad_members(sid):
		(m as Unit)._die()
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# ═════════════════════════════════════════════════════════════════════════════
# 4г. ЗНАМЯ ВОЗВРАЩАЕТСЯ НА СВОЁ МЕСТО ПРИ ПЕРЕСТРОЕНИИ
# ═════════════════════════════════════════════════════════════════════════════
## Заказ владельца: знамя привязано к бойцу ПЕРВОГО РЯДА С КРАЙНЕГО ЛЕВОГО
## края, а если в бою строй перемешался — знаменосец возвращается на своё место
## при перестроении.
##
## В бою знаменосец меняется по ДРУГОМУ правилу (ближайший к павшему, см. 4в),
## и это намеренно: выбор по строю уводил бы знамя в тыл через полстроя посреди
## рубки. Значит, «вернуть на место» обязано случаться ровно в одной точке — в
## смыкании рядов, то есть по окончании боя.
func _test_bearer_returns() -> void:
	print("\n═════ 4г. ВОЗВРАТ ЗНАМЕНОСЦА НА ЛЕВЫЙ ФЛАНГ ═════")
	var sid: int = await make_squad(12, Vector3(-300.0, 0.0, -300.0))
	GameManager.squads[sid]["level"] = 2
	GameManager.refresh_squad_banner(sid)
	# Курс отряда: без него понятия «первый ряд» и «лево» не существует
	var course := Vector3(0.0, 0.0, -1.0)
	var men: Array = GameManager.squad_members(sid)
	var slots: Array = []
	for i in range(men.size()):
		slots.append(Vector3(-300.0 + float(i % 6) * 0.8 - 2.0, 0.0,
			-300.0 - float(i / 6) * 0.8))
	GameManager.squad_set_formation(sid, slots, course, false)
	await frames(4)

	# ── ПЕРЕМЕШИВАЕМ СТРОЙ, как это делает свалка ──────────────────────────
	for i in range(men.size()):
		var u := men[i] as Unit
		var p := Vector3(-300.0 + float((i * 7) % 11) - 5.0, 0.0,
			-300.0 + float((i * 5) % 9) - 4.0)
		u.global_position = Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)
		u.sync_row()
	await frames(3)

	# ── ПЕРЕСТРОЕНИЕ ───────────────────────────────────────────────────────
	var closed: bool = GameManager.squad_close_ranks(sid, true)
	await frames(3)
	var bearer = GameManager.squad_bearer(sid)
	verdict("4г перестроение состоялось и знаменосец есть",
		closed and bearer != null,
		"смыкание=%s знаменосец=%s" % [str(closed), str(bearer != null)])
	if bearer == null:
		for m in GameManager.squad_members(sid):
			(m as Unit)._die()
		await frames(2)
		return

	# ── ОН ЛИ КРАЙНИЙ ЛЕВЫЙ В ПЕРВОМ РЯДУ ──────────────────────────────────
	# Считаем ПО МЕСТАМ РАЗМЕТКИ (post_pos), а не по текущим точкам: приказы
	# только что розданы, никто ещё не сделал ни шагу — ровно та причина, по
	# которой и сам выбор знаменосца идёт по посту (GameManager._bearer_anchor)
	var fwd := course.normalized()
	var left := Vector3(fwd.z, 0.0, -fwd.x)
	var front := -INF
	for m in GameManager.squad_members(sid):
		var mu := m as Unit
		if mu == null or mu.is_dead():
			continue
		var ap: Vector3 = mu.post_pos if mu._post_valid else mu.global_position
		front = maxf(front, ap.dot(fwd))
	var best_lat := -INF
	for m2 in GameManager.squad_members(sid):
		var mu2 := m2 as Unit
		if mu2 == null or mu2.is_dead():
			continue
		var ap2: Vector3 = mu2.post_pos if mu2._post_valid else mu2.global_position
		if ap2.dot(fwd) < front - GameManager.BEARER_ROW_BAND:
			continue
		best_lat = maxf(best_lat, ap2.dot(left))
	var bu := bearer as Unit
	var bp: Vector3 = bu.post_pos if bu._post_valid else bu.global_position
	var in_front: bool = bp.dot(fwd) >= front - GameManager.BEARER_ROW_BAND
	var is_left: bool = absf(bp.dot(left) - best_lat) < 0.01
	print("  знаменосец: глубина %.2f (фронт %.2f), левизна %.2f (крайняя %.2f)"
		% [bp.dot(fwd), front, bp.dot(left), best_lat])
	verdict("4г знаменосец стоит в ПЕРВОМ ряду", in_front,
		"глубина %.2f при фронте %.2f" % [bp.dot(fwd), front])
	verdict("4г и на КРАЙНЕМ ЛЕВОМ месте этого ряда", is_left,
		"левизна %.2f, крайняя %.2f" % [bp.dot(left), best_lat])
	for m in GameManager.squad_members(sid):
		(m as Unit)._die()
	await frames(2)

func _test_leader_death() -> void:
	print("\n═════ 4в. ГИБЕЛЬ ЗНАМЕНОСЦА И ПАДЕНИЕ ЗНАМЕНИ ═════")
	# ── ЗДЕСЬ ПРОВЕРЯЛОСЬ «ЗВЕЗДА ПЕРЕВЕШЕНА НА ЖИВОГО БОЙЦА», И ЭТО СТАЛО
	# ПРАВДОЙ ЛИШЬ ТЕПЕРЬ. Звезда к моменту написания блока уже была вынесена
	# в мир и висела над центром масс — её «носитель» был фикцией, и проверка
	# мерила get_parent() у узла, чей родитель всегда один и тот же (мир).
	# У знамени носитель настоящий, и его смена — заказанная механика
	var lvl0: int = GameManager.squad_level(squad)
	var banner := _find_banner(squad)
	var old_bearer = GameManager.squad_bearer(squad)
	print("  знамя грейда %d, знаменосец «%s»" % [_banner_grade(squad),
		(str((old_bearer as Node).name) if old_bearer != null else "—")])
	verdict("4в у отряда есть знаменосец", old_bearer != null)
	(old_bearer as Unit)._die()
	await frames(3)
	var banner2 := _find_banner(squad)
	var new_bearer = GameManager.squad_bearer(squad)
	print("  после гибели: знаменосец «%s», грейд=%d, в отряде %d бойцов" % [
		(str((new_bearer as Node).name) if new_bearer != null else "—"),
		_banner_grade(squad), GameManager.squad_members(squad).size()])
	verdict("4в знамя перешло к другому ЖИВОМУ бойцу ЭТОГО отряда",
		new_bearer != null and new_bearer != old_bearer
		and (new_bearer as Unit).squad_id == squad
		and not (new_bearer as Unit).is_dead())
	verdict("4в само знамя при передаче не пересоздавалось",
		banner2 != null and banner2 == banner)
	verdict("4в грейд после передачи не потерялся",
		_banner_grade(squad) == lvl0,
		"грейд=%d, ждали %d" % [_banner_grade(squad), lvl0])

	# ── ЗНАМЯ ПОДХВАТЫВАЕТ БЛИЖАЙШИЙ, А НЕ СЛУЧАЙНЫЙ ────────────────────────
	# Заказ владельца дословно: «знамя переезжает на копьё БЛИЖАЙШЕГО
	# выжившего». Проверяем свойством: ни один живой боец отряда не стоял к
	# павшему ближе, чем новый знаменосец
	var fallen_at: Vector3 = (new_bearer as Unit).global_position
	var closest_ok := true
	var nb_d: float = 1e18
	for m in GameManager.squad_members(squad):
		var mu := m as Unit
		if mu == null or mu.is_dead():
			continue
		var d: float = Vector2(mu.global_position.x - fallen_at.x,
			mu.global_position.z - fallen_at.z).length_squared()
		if mu == new_bearer:
			nb_d = d
	for m2 in GameManager.squad_members(squad):
		var mu2 := m2 as Unit
		if mu2 == null or mu2.is_dead() or mu2 == new_bearer:
			continue
		var d2: float = Vector2(mu2.global_position.x - fallen_at.x,
			mu2.global_position.z - fallen_at.z).length_squared()
		if d2 < nb_d - 0.0001:
			closest_ok = false
	verdict("4в знамя подхватил ближайший к павшему", closest_ok)

	# ── ГИБНЕТ ПОСЛЕДНИЙ: ЗНАМЯ ПАДАЕТ В СЛОЙ ТЕЛ ──────────────────────────
	# Заказ владельца: упавшее копьё со знаменем запекается в ТОТ ЖЕ MultiMesh,
	# что и тела. Значит на поле обязано прибавиться на ОДНО больше, чем павших
	# бойцов, и НИ ОДНОГО нового узла в мире
	var live: Array = GameManager.squad_members(squad)
	var n_live: int = live.size()
	var corpses0: int = GameManager.corpses.count()
	var nodes0: int = get_tree().get_node_count()
	for m in live:
		(m as Unit)._die()
	await frames(3)
	# Укладка отложена на кадр: knock приходит из _exit_tree, когда дерево
	# занято перестройкой (см. GameManager._drop_squad_banner)
	for _i in range(4):
		await get_tree().physics_frame
	await frames(2)
	var got: int = GameManager.corpses.count() - corpses0
	print("  павших %d, тел на поле прибавилось %d (тела + упавшее знамя)" % [
		n_live, got])
	verdict("4в отряд расформирован", not GameManager.squads.has(squad))
	verdict("4в упавшее знамя легло в слой тел, а не пропало",
		got == n_live + 1, "прибавилось %d, ждали %d" % [got, n_live + 1])
	# Ни одного узла на упавшее знамя: оно слот в общем буфере
	var nodes1: int = get_tree().get_node_count()
	verdict("4в на упавшее знамя не заведено ни одного узла",
		nodes1 <= nodes0, "узлов было %d, стало %d" % [nodes0, nodes1])
	var orphan: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	print("  осиротевших узлов: %d" % orphan)
	verdict("4в нет утечки узлов после гибели отряда", orphan == 0, "orphan=%d" % orphan)

# ═════════════════════════════════════════════════════════════════════════════
# 8. НАГРУЗКА
# ═════════════════════════════════════════════════════════════════════════════
const LOAD_SQUADS  := 60
const LOAD_PER     := 6
const WARMUP       := 100
const SAMPLES      := 240

func sample_physics_ms() -> float:
	var vals: Array = []
	for _i in range(SAMPLES):
		await get_tree().process_frame
		vals.append(float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0)
	vals.sort()
	return float(vals[vals.size() / 2])

func _test_load() -> void:
	print("\n═════ 8. НАГРУЗКА: %d ЮНИТОВ, %d ЗВЁЗД ═════" % [
		LOAD_SQUADS * LOAD_PER, LOAD_SQUADS])
	var sids: Array = []
	for i in range(LOAD_SQUADS):
		var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
		for j in range(LOAD_PER):
			var u := Spearman.new()
			u.faction = Constants.FACTION_PLAYER
			main.world_add(u)
			u.global_position = Vector3(-300.0 + float(i) * 1.6, 0.0,
				100.0 + float(j) * 1.6)
			GameManager.add_to_squad(sid, u)
		sids.append(sid)
		if i % 10 == 9:
			await get_tree().process_frame
	await frames(3)
	var total := 0
	for sid in sids:
		total += GameManager.squad_members(int(sid)).size()
	print("  создано юнитов: %d в %d отрядах" % [total, sids.size()])

	# Контроль: те же юниты БЕЗ звёзд
	for sid in sids:
		for m in GameManager.squad_members(int(sid)):
			(m as Unit).command_move((m as Unit).global_position + Vector3(0.0, 0.0, 60.0))
	await frames(WARMUP)
	var base_ms: float = await sample_physics_ms()

	# Те же юниты СО звёздами (3 уровень → ряд из трёх звёзд у каждого отряда)
	var stars := 0
	for sid in sids:
		var s: int = int(sid)
		GameManager.squads[s]["level"] = 3
		GameManager.refresh_squad_banner(s)
		if _find_banner(s) != null:
			stars += 1
	await frames(3)
	for sid in sids:
		for m in GameManager.squad_members(int(sid)):
			(m as Unit).command_move((m as Unit).global_position - Vector3(0.0, 0.0, 60.0))
	await frames(WARMUP)
	var star_ms: float = await sample_physics_ms()

	print("  медиана TIME_PHYSICS_PROCESS по %d кадрам: без звёзд %.3f мс, со звёздами %.3f мс (дельта %+.3f мс)" % [
		SAMPLES, base_ms, star_ms, star_ms - base_ms])
	print("  зажжено знамён: %d" % stars)
	verdict("8 все %d отрядов получили знамя" % LOAD_SQUADS, stars == LOAD_SQUADS,
		"знамён=%d" % stars)
	verdict("8 медиана физики со знамёнами < 16.6 мс", star_ms < 16.6,
		"%.3f мс" % star_ms)

	for sid in sids:
		for m in GameManager.squad_members(int(sid)):
			(m as Unit)._die()
	await frames(5)
	var orphan: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var nodes: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	print("  после роспуска: осиротевших узлов=%d, узлов в дереве=%d, отрядов в реестре=%d" % [
		orphan, nodes, GameManager.squads.size()])
	verdict("8 OBJECT_ORPHAN_NODE_COUNT == 0", orphan == 0, "orphan=%d" % orphan)


# СУММА ВСЕХ МОДИФИКАТОРОВ НАГРАДЫ, А НЕ ОДНО ПОЛЕ "value".
# Награда в конфиге — ПОЛНЫЙ шаблон модификаторов и вправе дать
# сразу несколько прибавок (так же работает GameManager.apply_veteran_choice).
# "value" — это короткая ПОДПИСЬ для кнопки, и сверять с ней сумму
# начисленного — значит сравнивать разные величины
func _reward_sum(entry: Dictionary) -> float:
	var t := 0.0
	for k in _UCfg.nonzero_modifiers(entry):
		t += float(_UCfg.nonzero_modifiers(entry)[k])
	return t
