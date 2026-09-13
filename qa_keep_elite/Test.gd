extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_keep_elite — МЕЧНИКИ КРЕПОСТИ ВЫХОДЯТ ВЕТЕРАНАМИ
## ═══════════════════════════════════════════════════════════════════════════
## Заказ владельца 13.09.2026: развести обычных мечников из Бараков и элитных
## из Крепости. Из Крепости они выходят УЖЕ С ЛЫЧКОЙ (ранг I), ранг поднимают
## исследования в самой Крепости (II, III, IV), найм стоит в разы дороже, а
## содержание идёт не только едой, но и золотом, и растёт с рангом.
##
##   A  ЦЕНА    — найм в Крепости кратно дороже, чем те же мечники в Бараках
##   B  РАНГ    — отряд из Крепости рождается с лычкой, из Бараков — без
##   C  ЛЕСТНИЦА — улучшения I→II→III→IV, цена растёт, потолок держится
##   D  СОДЕРЖАНИЕ — еда по рангу и отдельная статья золотом
##
## Запуск: <godot> --headless --path . res://qa_keep_elite/Test.tscn

const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _Save := preload("res://scripts/SaveLoadManager.gd")

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []
const F := Constants.FACTION_PLAYER

func _ready() -> void:
	call_deferred("_run")
	var t := get_tree().create_timer(420.0)
	t.timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 420 с")
		_finish())

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
	print("\n═════ ИТОГ qa_keep_elite: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	for _i in range(8):
		await get_tree().process_frame
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	# Лимит населения для стенда не нужен: он про экономику элиты
	GameManager.pop_limit_enabled = false
	await pframes(4)
	print("\n═════ qa_keep_elite ═════")
	_a_cost()
	await _b_rank()
	_c_ladder()
	await _d_upkeep()
	_e_save()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
func _a_cost() -> void:
	print("\n═════ A. ЦЕНА НАЙМА ═════")
	var keep: Dictionary = _UCfg.train_cfg("castle", "warrior")
	var barr: Dictionary = _UCfg.train_cfg("barracks", "warrior")
	var kg: float = float(keep.get("cost_gold", 0.0))
	var bg: float = float(barr.get("cost_gold", 0.0))
	var kw: float = float(keep.get("cost_wood", 0.0))
	var bw: float = float(barr.get("cost_wood", 0.0))
	print("  Крепость: %.0f дерева / %.0f золота / %.0f с" % [
		kw, kg, float(keep.get("time", 0.0))])
	print("  Бараки:   %.0f дерева / %.0f золота / %.0f с" % [
		bw, bg, float(barr.get("time", 0.0))])
	verdict("A1 золото в Крепости дороже вдвое-втрое",
		kg >= bg * 2.0 and kg <= bg * 3.5,
		"×%.1f (%.0f против %.0f)" % [kg / maxf(bg, 1.0), kg, bg])
	verdict("A2 дерево тоже дороже",
		kw > bw, "%.0f против %.0f" % [kw, bw])
	verdict("A3 и обучение дольше",
		float(keep.get("time", 0.0)) > float(barr.get("time", 0.0)),
		"%.0f против %.0f с" % [float(keep.get("time", 0.0)),
			float(barr.get("time", 0.0))])

# ═════════════════════════════════════════════════════════════════════════════
## Заказать отряд в здании и дождаться, пока он выйдет. Возвращает sid или 0
func _order(bld: Building, unit_id: String) -> int:
	var before: Array = GameManager.squads.keys().duplicate()
	ResourceManager.add_resource(bld.faction, Constants.RESOURCE_GOLD, 99999.0)
	ResourceManager.add_resource(bld.faction, Constants.RESOURCE_WOOD, 99999.0)
	ResourceManager.add_resource(bld.faction, Constants.RESOURCE_STONE, 99999.0)
	bld.train_from_config(unit_id)
	# Обучение идёт по своим часам — ждём появления НОВОГО отряда
	for _f in range(60 * 120):
		await get_tree().physics_frame
		# ── НОВЫЙ ОТРЯД ИЩЕМ ПО ТИПУ И СТОРОНЕ, А НЕ ПРОСТО «НОВЫЙ КЛЮЧ» ──
		# Логово тролля выпускает волны гноллов по своим часам, и первая версия
		# ловила ИХ отряд: B2 мигал «ранг 0» через прогон на исправном коде
		for k in GameManager.squads.keys():
			if k in before:
				continue
			var sq: Dictionary = GameManager.squads[k]
			if int(sq.get("faction", -1)) != bld.faction:
				continue
			if String(sq.get("type", "")) != unit_id:
				continue
			return int(k)
	return 0

func _b_rank() -> void:
	print("\n═════ B. РАНГ ПРИ РОЖДЕНИИ ═════")
	var castle: Building = null
	var barracks: Building = null
	for b in GameManager.nodes_in_group_cached(Constants.building_group(F)):
		if not is_instance_valid(b):
			continue
		var bb := b as Building
		if bb == null:
			continue
		if bb is Castle and bb.has_method("is_stronghold") \
				and bool(bb.call("is_stronghold")) and castle == null:
			castle = bb
		elif bb is Barracks and barracks == null:
			barracks = bb
	if castle == null:
		# ПАРТИЯ ОТКРЫВАЕТСЯ БЕЗ КРЕПОСТИ (спринт 12) — ставим свою
		var keep := Castle.new()
		keep.faction = F
		main.world_add(keep)
		var kp: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(18.0, 0.0, 18.0)
		keep.global_position = Vector3(kp.x,
			GameManager.get_terrain_height(kp.x, kp.z), kp.z)
		await pframes(6)
		castle = keep
	verdict("B0 крепость игрока найдена", castle != null)
	if castle == null:
		return
	print("  ранг найма в Крепости сейчас: %s" % _UCfg.roman(
		GameManager.keep_warrior_vet(F)))
	var sid: int = await _order(castle, "warrior")
	verdict("B1 отряд из Крепости заказан и вышел", sid != 0, "sid %d" % sid)
	if sid == 0:
		return
	var lvl: int = int(GameManager.squads[sid].get("level", 0))
	verdict("B2 мечники Крепости рождаются с лычкой (ранг I)",
		lvl == _UCfg.KEEP_WARRIOR_VET,
		"ранг %d, ожидали %d" % [lvl, _UCfg.KEEP_WARRIOR_VET])
	verdict("B3 у ранга есть знамя с лычками",
		_UCfg.veteran_badge_text(lvl) != "",
		"значок «%s»" % _UCfg.veteran_badge_text(lvl))
	if barracks != null:
		var bsid: int = await _order(barracks, "warrior")
		if bsid != 0:
			verdict("B4 мечники из Бараков — по-прежнему новобранцы",
				int(GameManager.squads[bsid].get("level", 0)) == 0,
				"ранг %d" % int(GameManager.squads[bsid].get("level", 0)))
	else:
		print("  бараков на старте нет — сравнение с новобранцами пропущено")

# ═════════════════════════════════════════════════════════════════════════════
func _c_ladder() -> void:
	print("\n═════ C. ЛЕСТНИЦА УЛУЧШЕНИЙ ═════")
	GameManager.keep_vet_level.erase(F)
	var seen: Array = []
	var prev_gold := 0.0
	var rising := true
	for _step in range(6):
		var nxt: int = GameManager.keep_vet_next(F)
		if nxt == 0:
			break
		var cost: Dictionary = GameManager.keep_vet_cost(F)
		var g: float = float(cost.get(Constants.RESOURCE_GOLD, 0.0))
		print("  улучшение до %s: %.0f золота, %.0f дерева, %.0f камня" % [
			_UCfg.roman(nxt), g,
			float(cost.get(Constants.RESOURCE_WOOD, 0.0)),
			float(cost.get(Constants.RESOURCE_STONE, 0.0))])
		if g <= prev_gold:
			rising = false
		prev_gold = g
		ResourceManager.add_resource(F, Constants.RESOURCE_GOLD, g + 10.0)
		ResourceManager.add_resource(F, Constants.RESOURCE_WOOD,
			float(cost.get(Constants.RESOURCE_WOOD, 0.0)) + 10.0)
		ResourceManager.add_resource(F, Constants.RESOURCE_STONE,
			float(cost.get(Constants.RESOURCE_STONE, 0.0)) + 10.0)
		verdict("C%d улучшение до %s куплено" % [seen.size() + 1, _UCfg.roman(nxt)],
			GameManager.keep_vet_buy(F), "ранг стал %d" % GameManager.keep_warrior_vet(F))
		seen.append(nxt)
	verdict("C-итог лестница доходит ровно до IV",
		seen == [2, 3, 4] and GameManager.keep_warrior_vet(F) == _UCfg.KEEP_WARRIOR_VET_MAX,
		"ступени %s, ранг %d" % [str(seen), GameManager.keep_warrior_vet(F)])
	verdict("C-потолок дальше IV улучшений нет",
		GameManager.keep_vet_next(F) == 0)
	verdict("C-цена каждая следующая ступень дороже предыдущей", rising)
	# Без денег улучшение не покупается
	GameManager.keep_vet_level[F] = 1
	ResourceManager.set_amount(F, Constants.RESOURCE_GOLD, 0.0)
	verdict("C-касса без золота ступень не берётся",
		not GameManager.keep_vet_buy(F),
		"ранг остался %d" % GameManager.keep_warrior_vet(F))

# ═════════════════════════════════════════════════════════════════════════════
func _d_upkeep() -> void:
	print("\n═════ D. СОДЕРЖАНИЕ ═════")
	print("  еда: новобранец ×%.2f, I ×%.2f, II ×%.2f, IV ×%.2f" % [
		_UCfg.keep_food_mult(0), _UCfg.keep_food_mult(1),
		_UCfg.keep_food_mult(2), _UCfg.keep_food_mult(4)])
	print("  золото в секунду на отряд: I %.2f, II %.2f, IV %.2f" % [
		_UCfg.keep_gold_rate(1), _UCfg.keep_gold_rate(2), _UCfg.keep_gold_rate(4)])
	verdict("D1 новобранец золота не ест вовсе",
		_UCfg.keep_gold_rate(0) == 0.0)
	verdict("D2 с рангом растёт и еда, и золото",
		_UCfg.keep_food_mult(4) > _UCfg.keep_food_mult(1)
			and _UCfg.keep_gold_rate(4) > _UCfg.keep_gold_rate(1))
	# ── ЖИВОЙ ЗАМЕР: ЗОЛОТО РЕАЛЬНО СПИСЫВАЕТСЯ ───────────────────────────
	# Заводим отряд с лычками и смотрим, тратит ли он золото за такт снабжения
	var sid: int = GameManager.new_squad(F, "warrior")
	var men: Array = []
	for k in range(6):
		var u: Unit = load("res://scenes/units/Warrior.tscn").instantiate()
		u.faction = F
		main.world_add(u)
		u.global_position = Vector3(main.PLAYER_BASE_ANCHOR.x + 40.0 + float(k),
			0.0, main.PLAYER_BASE_ANCHOR.z + 40.0)
		u.sync_row()
		GameManager.add_to_squad(sid, u)
		men.append(u)
	GameManager.squads[sid]["level"] = 3
	ResourceManager.set_amount(F, Constants.RESOURCE_GOLD, 500.0)
	ResourceManager.set_amount(F, Constants.RESOURCE_FOOD, 500.0)
	var g0: float = ResourceManager.get_amount(F, Constants.RESOURCE_GOLD)
	await pframes(int(60 * (_UCfg.FOOD_UPKEEP_TICK * 3.0 + 1.0)))
	var g1: float = ResourceManager.get_amount(F, Constants.RESOURCE_GOLD)
	print("  золото за %.0f с: %.1f → %.1f (ставка %.2f/с)" % [
		_UCfg.FOOD_UPKEEP_TICK * 3.0, g0, g1,
		float(GameManager.gold_upkeep_rate.get(F, 0.0))])
	verdict("D3 отряд с лычками реально ест золото",
		g1 < g0 and float(GameManager.gold_upkeep_rate.get(F, 0.0)) > 0.0,
		"убыло %.1f" % (g0 - g1))
	for m in men:
		if is_instance_valid(m):
			(m as Unit).take_damage(1e12)
	await pframes(6)

# ═════════════════════════════════════════════════════════════════════════════
# E. РАНГ ПЕРЕЖИВАЕТ СОХРАНЕНИЕ
# ═════════════════════════════════════════════════════════════════════════════
func _e_save() -> void:
	print("
═════ E. СОХРАНЕНИЕ ═════")
	# Купленные ступени — одно число на фракцию; без него загруженная партия
	# возвращала бы найм первого ранга после оплаченного четвёртого
	GameManager.keep_vet_level[F] = 4
	var snap: Dictionary = _Save.capture(main)
	GameManager.keep_vet_level[F] = 1
	_Save._restore_keep_vet(snap.get("keep_vet", {}))
	verdict("E1 ранг элиты переживает круговой рейс слепка",
		GameManager.keep_warrior_vet(F) == 4,
		"после восстановления ранг %d" % GameManager.keep_warrior_vet(F))
