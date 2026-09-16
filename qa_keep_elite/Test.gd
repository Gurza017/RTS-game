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
##   B  РАНГ    — отряд из Крепости рождается с лычкой (ранг I = красный
##                вымпел, одна лычка), из Бараков — без
##   C  ЛЕСТНИЦА — исследования I→II→III→IV ПО ВРЕМЕНИ (13.09.2026, вторая
##                правка: 7000 золота, часы, а не мгновенная покупка), цена
##                растёт, потолок держится
##   D  СОДЕРЖАНИЕ — еда по рангу и отдельная статья золотом
##   E  СОХРАНЕНИЕ — ранг и идущее исследование переживают слепок
##   F  ПАНЕЛЬ  — в Крепости РОВНО ОДНА иконка рыцаря с лычками, под ней
##                кнопка [ I ] с радаром; после исследования [ II ] и новые
##                рыцари выходят рангом II (две лычки)
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
	await _f_panel()
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
			# ── ЖДЁМ ПЕРВОГО БОЙЦА, А НЕ ЗАПИСЬ В РЕЕСТРЕ ──────────────────
			# Запись заводится в момент выхода заказа из очереди, а бойцы
			# доезжают отложенными вызовами следующими кадрами — и ранг элиты
			# выдаётся по ПЕРВОМУ бойцу (Building._place_spawned). Читать
			# уровень по голой записи значит прочитать ноль на исправном коде
			var arr: Array = sq.get("members", [])
			if arr.is_empty():
				continue
			await get_tree().physics_frame
			await get_tree().physics_frame
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
	# «Синий флаг» с жалобы — это грейд 4-6 (ласточкин хвост). Ранг I обязан
	# быть КРАСНЫМ ВЫМПЕЛОМ С ОДНОЙ ЛЫЧКОЙ — сверяем по таблице грейдов
	var tier: Dictionary = _UCfg.veteran_banner_tier(lvl)
	var cloth: Color = tier.get("cloth", Color.BLACK)
	verdict("B3б ранг I — красный вымпел с одной лычкой, не синий флаг",
		int(tier.get("shape", -1)) == _UCfg.BANNER_PENNANT
			and int(tier.get("chevrons", 0)) == 1
			and cloth.r > cloth.b,
		"форма %d, лычек %d, полотнище %s" % [int(tier.get("shape", -1)),
			int(tier.get("chevrons", 0)), str(cloth)])
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
	print("\n═════ C. ЛЕСТНИЦА ИССЛЕДОВАНИЙ ═════")
	GameManager.keep_vet_level.erase(F)
	GameManager.keep_vet_research.erase(F)
	verdict("C0 первая ступень стоит KNIGHT_UPGRADE_COST золота и только золота",
		GameManager.keep_vet_cost(F) == {Constants.RESOURCE_GOLD: _UCfg.KNIGHT_UPGRADE_COST},
		"цена %s" % str(GameManager.keep_vet_cost(F)))
	var seen: Array = []
	var prev_gold := 0.0
	var rising := true
	for _step in range(6):
		var nxt: int = GameManager.keep_vet_next(F)
		if nxt == 0:
			break
		var cost: Dictionary = GameManager.keep_vet_cost(F)
		var g: float = float(cost.get(Constants.RESOURCE_GOLD, 0.0))
		var t: float = GameManager.keep_vet_time(F)
		print("  исследование до %s: %.0f золота, %.0f с" % [_UCfg.roman(nxt), g, t])
		if g <= prev_gold:
			rising = false
		prev_gold = g
		ResourceManager.set_amount(F, Constants.RESOURCE_GOLD, g + 10.0)
		var before: int = GameManager.keep_warrior_vet(F)
		var started: bool = GameManager.keep_vet_buy(F)
		var gold_after: float = ResourceManager.get_amount(F, Constants.RESOURCE_GOLD)
		verdict("C%d исследование до %s запущено: золото списано, ранг ЕЩЁ прежний" % [
			seen.size() + 1, _UCfg.roman(nxt)],
			started and GameManager.keep_vet_researching(F)
				and absf(gold_after - 10.0) < 0.01
				and GameManager.keep_warrior_vet(F) == before
				and GameManager.keep_vet_research_target(F) == nxt,
			"запущено %s, золота осталось %.0f, ранг %d, цель %d" % [
				str(started), gold_after, GameManager.keep_warrior_vet(F),
				GameManager.keep_vet_research_target(F)])
		# Второе исследование поверх идущего не берётся
		ResourceManager.set_amount(F, Constants.RESOURCE_GOLD, 99999.0)
		verdict("C%dб пока идёт одно — второе не запускается" % (seen.size() + 1),
			not GameManager.keep_vet_buy(F)
				and absf(ResourceManager.get_amount(F, Constants.RESOURCE_GOLD) - 99999.0) < 0.01)
		# Половина часов — ранг всё ещё прежний, прогресс около половины
		GameManager.keep_vet_tick(t * 0.5)
		var half: float = GameManager.keep_vet_progress(F)
		verdict("C%dв на половине часов ранг прежний, прогресс ~0.5" % (seen.size() + 1),
			GameManager.keep_warrior_vet(F) == before and absf(half - 0.5) < 0.02,
			"прогресс %.2f" % half)
		# Дотикали — ранг поднялся, запись исследования снята
		GameManager.keep_vet_tick(t * 0.5 + 0.01)
		verdict("C%dг по истечении часов ранг стал %s" % [seen.size() + 1, _UCfg.roman(nxt)],
			GameManager.keep_warrior_vet(F) == nxt and not GameManager.keep_vet_researching(F),
			"ранг %d" % GameManager.keep_warrior_vet(F))
		seen.append(nxt)
	verdict("C-итог лестница доходит ровно до IV",
		seen == [2, 3, 4] and GameManager.keep_warrior_vet(F) == _UCfg.KEEP_WARRIOR_VET_MAX,
		"ступени %s, ранг %d" % [str(seen), GameManager.keep_warrior_vet(F)])
	verdict("C-потолок дальше IV исследований нет",
		GameManager.keep_vet_next(F) == 0 and not GameManager.keep_vet_buy(F))
	verdict("C-цена каждая следующая ступень дороже предыдущей", rising)
	# Без денег исследование не запускается
	GameManager.keep_vet_level[F] = 1
	ResourceManager.set_amount(F, Constants.RESOURCE_GOLD, 0.0)
	verdict("C-касса без золота ступень не берётся",
		not GameManager.keep_vet_buy(F) and not GameManager.keep_vet_researching(F),
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
	# Идущее исследование — золото за него уже списано — тоже едет в слепок
	GameManager.keep_vet_level[F] = 1
	GameManager.keep_vet_research[F] = {"target": 2, "left": 17.5, "total": 60.0}
	var snap2: Dictionary = _Save.capture(main)
	GameManager.keep_vet_research.clear()
	_Save._restore_keep_vet(snap2.get("keep_vet", {}))
	_Save._restore_keep_vet_research(snap2.get("keep_vet_research", {}))
	verdict("E2 идущее исследование переживает слепок (цель и остаток часов)",
		GameManager.keep_vet_research_target(F) == 2
			and absf(GameManager.keep_vet_research_left(F) - 17.5) < 0.01,
		"цель %d, осталось %.1f" % [GameManager.keep_vet_research_target(F),
			GameManager.keep_vet_research_left(F)])
	GameManager.keep_vet_research.clear()
	GameManager.keep_vet_level.erase(F)

# ═════════════════════════════════════════════════════════════════════════════
# F. ПАНЕЛЬ КРЕПОСТИ: ОДНА ИКОНКА РЫЦАРЯ, КНОПКА [ I ] С РАДАРОМ, [ II ] ПОСЛЕ
# ═════════════════════════════════════════════════════════════════════════════
## Кнопки найма ищутся ПО ИКОНКЕ (путь текстуры Warrior.png), а не по тексту:
## у кнопки с картинкой text пуст, название лежит в tooltip_text
func _panel_buttons(root: Node, out: Array) -> void:
	for c in root.get_children():
		if c is Button:
			out.append(c)
		if c is Control:
			_panel_buttons(c, out)

func _knight_buttons(hud) -> Array:
	var res: Array = []
	var all: Array = []
	_panel_buttons(hud.button_container, all)
	var warrior_path: String = String(hud.UNIT_ICONS.get("warrior", ""))
	for b in all:
		for ch in (b as Button).get_children():
			var tr := ch as TextureRect
			if tr != null and tr.texture != null \
					and tr.texture.resource_path == warrior_path:
				res.append(b)
				break
	return res

func _rank_button(hud) -> Button:
	var all: Array = []
	_panel_buttons(hud.button_container, all)
	for b in all:
		if (b as Button).name == "KeepRankButton":
			return b as Button
	return null

func _f_panel() -> void:
	print("\n═════ F. ПАНЕЛЬ КРЕПОСТИ ═════")
	var hud = main.hud
	var castle: Building = null
	for b in GameManager.nodes_in_group_cached(Constants.building_group(F)):
		if not is_instance_valid(b):
			continue
		var bb := b as Building
		if bb != null and bb is Castle and bb.has_method("is_stronghold") \
				and bool(bb.call("is_stronghold")):
			castle = bb
			break
	verdict("F0 крепость для панели найдена", castle != null)
	if castle == null or hud == null:
		return
	GameManager.keep_vet_level.erase(F)
	GameManager.keep_vet_research.erase(F)
	ResourceManager.set_amount(F, Constants.RESOURCE_GOLD, 20000.0)
	# Выделение — ЧЕРЕЗ SelectionManager, как у игрока: панель после клика
	# и по завершении исследования пересобирается из sm.selected_units, и
	# прямой hud.show_selection([castle]) на этом шаге терял бы крепость
	var sm = main.selection_manager
	sm._clear_selection()
	sm._select(castle)
	GameManager.on_selection_changed(sm.selected_units, true)
	await pframes(3)
	var knights: Array = _knight_buttons(hud)
	verdict("F1 в панели Крепости РОВНО ОДНА иконка рыцаря (дубль снят)",
		knights.size() == 1, "иконок с Warrior.png: %d" % knights.size())
	if knights.is_empty():
		return
	var kb: Button = knights[0]
	var chev: Label = kb.get_node_or_null("RankChevrons") as Label
	verdict("F2 на иконке рыцаря нарисованы лычки ранга I",
		chev != null and chev.visible and chev.text == _UCfg.veteran_badge_text(1),
		"лычки «%s»" % (chev.text if chev != null else "нет"))
	var rb: Button = _rank_button(hud)
	verdict("F3 под иконкой — кнопка ранга с римской цифрой [ I ]",
		rb != null and rb.text == "[ I ]" and not rb.disabled,
		"кнопка %s" % (rb.text if rb != null else "нет"))
	if rb == null:
		return
	var kr: Rect2 = kb.get_global_rect()
	var rr: Rect2 = rb.get_global_rect()
	verdict("F3б кнопка ранга стоит ПОД иконкой рыцаря",
		rr.position.y >= kr.position.y + kr.size.y - 0.5
			and absf((rr.position.x + rr.size.x * 0.5) - (kr.position.x + kr.size.x * 0.5)) <= 2.0,
		"иконка y=%.0f..%.0f, кнопка y=%.0f, центры x %.0f/%.0f" % [
			kr.position.y, kr.position.y + kr.size.y, rr.position.y,
			kr.position.x + kr.size.x * 0.5, rr.position.x + rr.size.x * 0.5])
	var radar: Control = rb.get_node_or_null("RankRadar") as Control
	verdict("F4 до клика радар прогресса скрыт",
		radar != null and not radar.visible)
	# Клик по кнопке — исследование пошло: золото списано, радар виден
	var g0: float = ResourceManager.get_amount(F, Constants.RESOURCE_GOLD)
	rb.emit_signal("pressed")
	await pframes(3)
	verdict("F5 клик запускает исследование и списывает золото",
		GameManager.keep_vet_researching(F)
			and absf((g0 - ResourceManager.get_amount(F, Constants.RESOURCE_GOLD)) - _UCfg.KNIGHT_UPGRADE_COST) < 0.01,
		"списано %.0f" % (g0 - ResourceManager.get_amount(F, Constants.RESOURCE_GOLD)))
	rb = _rank_button(hud)
	radar = rb.get_node_or_null("RankRadar") as Control if rb != null else null
	verdict("F6 во время исследования кнопка [ I ] не нажимается, радар виден",
		rb != null and rb.disabled and rb.text == "[ I ]" and radar != null and radar.visible,
		"кнопка %s, disabled=%s, радар виден=%s" % [
			rb.text if rb != null else "нет", str(rb.disabled if rb != null else false),
			str(radar.visible if radar != null else false)])
	# Часы идут — радар заполняется (долю ведёт _refresh_keep_rank из _process)
	var total: float = float(GameManager.keep_vet_research[F]["total"])
	GameManager.keep_vet_tick(total * 0.4)
	await get_tree().process_frame
	await get_tree().process_frame
	var p1: float = float(radar.progress) if radar != null else -1.0
	GameManager.keep_vet_tick(total * 0.3)
	await get_tree().process_frame
	await get_tree().process_frame
	var p2: float = float(radar.progress) if radar != null else -1.0
	verdict("F7 радар заполняется по часам исследования",
		p1 > 0.3 and p2 > p1 and p2 < 1.0, "доля %.2f → %.2f" % [p1, p2])
	# Дотикали — панель пересобралась по сигналу, цифра стала [ II ]
	GameManager.keep_vet_tick(total)
	await pframes(3)
	rb = _rank_button(hud)
	knights = _knight_buttons(hud)
	chev = (knights[0] as Button).get_node_or_null("RankChevrons") as Label if not knights.is_empty() else null
	verdict("F8 после исследования кнопка показывает [ II ], радар скрыт",
		rb != null and rb.text == "[ II ]" and not rb.disabled
			and rb.get_node_or_null("RankRadar") != null
			and not (rb.get_node_or_null("RankRadar") as Control).visible,
		"кнопка %s" % (rb.text if rb != null else "нет"))
	verdict("F8б иконка рыцаря по-прежнему одна, лычек на ней две",
		knights.size() == 1 and chev != null and chev.text == _UCfg.veteran_badge_text(2),
		"иконок %d, лычки «%s»" % [knights.size(), chev.text if chev != null else "нет"])
	# Новый найм из Крепости — ранг II (две лычки), из Бараков — новобранец
	var sid: int = await _order(castle, "warrior")
	var lvl: int = int(GameManager.squads[sid].get("level", -1)) if sid != 0 else -1
	verdict("F9 новые рыцари Крепости после исследования выходят рангом II",
		sid != 0 and lvl == 2, "ранг %d" % lvl)
	var tier2: Dictionary = _UCfg.veteran_banner_tier(2)
	verdict("F9б ранг II — две лычки на красном вымпеле",
		int(tier2.get("chevrons", 0)) == 2
			and int(tier2.get("shape", -1)) == _UCfg.BANNER_PENNANT)
	var barracks: Building = null
	for b in GameManager.nodes_in_group_cached(Constants.building_group(F)):
		if is_instance_valid(b) and b is Barracks:
			barracks = b as Building
			break
	if barracks == null:
		barracks = Barracks.new()
		barracks.faction = F
		main.world_add(barracks)
		var bp: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(-22.0, 0.0, 26.0)
		barracks.global_position = Vector3(bp.x,
			GameManager.get_terrain_height(bp.x, bp.z), bp.z)
		await pframes(6)
	var bsid: int = await _order(barracks, "warrior")
	var blvl: int = int(GameManager.squads[bsid].get("level", -1)) if bsid != 0 else -1
	verdict("F10 рыцари из Бараков исследования не получают (ранг 0)",
		bsid != 0 and blvl == 0, "ранг %d" % blvl)
	sm._clear_selection()
	GameManager.on_selection_changed(sm.selected_units, true)
	GameManager.keep_vet_level.erase(F)
	GameManager.keep_vet_research.erase(F)
