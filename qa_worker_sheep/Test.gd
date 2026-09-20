extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: РАБОЧИЙ — МОЛОТОК ТОЛЬКО У СТРОЙКИ, КРАЖА ОВЦЫ, РАЗДЕЛКА НА МЯСО,
## ЛИСТ КАМНЯ ЧЁРНОГО РАБОЧЕГО (заказ владельца, 10.09.2026)
## ═══════════════════════════════════════════════════════════════════════════
##   A СТРОЙКА — по приказу рабочий идёт с лентой ходьбы, молоток включается
##     только после прихода к площадке (_build_settled).
##   B ОВЦА — рабочий подходит, берёт (овца над головой, лента «несёт мясо»),
##     несёт к складу, режет ножом SHEEP_CUTS раз (овца мигает), каждый надрез
##     даёт мясо, последний — овцу целиком; загон (sheep_pens) в приоритете.
##   C ОТМЕНА — новый приказ бросает овцу, она снова свободна.
##   D КАМЕНЬ — лист Pawn_Run_Stone у чёрного рабочего того же размера и
##     на те же шесть кадров, что остальные ленты бега.
## Запуск: godot --headless --path . res://qa_worker_sheep/Test.tscn

const _CSite := preload("res://scripts/ConstructionSite.gd")
const _UCfg := preload("res://scripts/unit_stats_config.gd")

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(300.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 300 с"); _finish())

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
	print("\n═════ ИТОГ qa_worker_sheep: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

## Ближайшая свободная, живая и ДИКАЯ овца. Три условия, и каждое нужно:
## занятую `command_steal_sheep` отвергает сразу (приказ пропадает молча),
## мёртвую не режут повторно, а СВОЮ (из стада замка) рабочий режет НА МЕСТЕ
## и никуда не несёт — а блок C проверяет отмену именно у НЕСУЩЕГО
func _free_sheep_near(from: Vector3) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for cand in get_tree().get_nodes_in_group("sheep"):
		if cand == null or not is_instance_valid(cand):
			continue
		if bool(cand.get("eaten")) or bool(cand.get("dead")):
			continue
		if not bool(cand.call("is_free")):
			continue
		if bool(cand.call("is_owned")):
			continue
		var d: float = from.distance_to((cand as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = cand
	return best

func _spawn_worker(at: Vector3) -> Worker:
	var w: Unit = (Building.PRELOAD_SCENES["worker"] as PackedScene).instantiate()
	w.faction = Constants.FACTION_PLAYER
	main.world_add(w)
	w.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	w.sync_row()
	GameManager.add_to_squad(GameManager.new_squad(Constants.FACTION_PLAYER, "worker"), w)
	return w as Worker

func _food() -> float:
	return ResourceManager.get_amount(Constants.FACTION_PLAYER, Constants.RESOURCE_FOOD)

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	# Пень за рекой в партии заморожен (ТЗ 19.09.2026); стенду нужен живой
	GameManager.call_deferred("thaw_lairs_now")
	await frames(8)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	GameManager.world_bounds_enabled = false
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	await pframes(4)

	# ── A. Молоток только у стройки ────────────────────────────────────────
	print("\n═════ A. АНИМАЦИЯ СТРОИТЕЛЯ ═════")
	var base := Vector3(-120.0, 0.0, -60.0)
	main._clear_area_of_resources(base, 30.0)
	var w: Worker = _spawn_worker(base)
	var site: Building = _CSite.new()
	site.faction = Constants.FACTION_PLAYER
	site.target_id = "house"
	site.target_name = "Дом"
	site.build_time = 60.0
	site.build_size = _UCfg.building_size("house")
	main.world_add(site)
	var sp: Vector3 = base + Vector3(14.0, 0.0, 0.0)
	site.global_position = Vector3(sp.x, GameManager.get_terrain_height(sp.x, sp.z), sp.z)
	await pframes(2)
	w.command_build(site)
	await pframes(3)
	w.sheet_frame()
	w._update_sprite_anim()
	verdict("A1 сразу после приказа — лента ходьбы, а не молоток",
		w._anim_name == "walk" and not w._build_settled, "лента «%s»" % w._anim_name)
	var hammer_on_road := 0
	var guard := 0
	while guard < 60 * 15 and not w._build_settled:
		await get_tree().physics_frame
		guard += 1
		w._update_sprite_anim()
		# Кадр прихода не считается: защёлка взводится внутри этого же физкадра
		if w._anim_name == "build" and not w._build_settled:
			hammer_on_road += 1
	verdict("A2 по дороге к площадке молоток не включался ни разу",
		w._build_settled and hammer_on_road == 0, "кадров с молотком в пути %d, дошёл за %d" % [hammer_on_road, guard])
	await pframes(3)
	w._update_sprite_anim()
	verdict("A3 у площадки — молоток", w._anim_name == "build" and site.builder_count() == 1,
		"лента «%s», строителей %d" % [w._anim_name, site.builder_count()])
	site.queue_free()
	w.take_damage(1.0e9)
	await pframes(3)

	# ── B. Кража овцы ──────────────────────────────────────────────────────
	print("\n═════ B. КРАЖА ОВЦЫ И РАЗДЕЛКА ═════")
	var lair = GameManager.troll_lair
	if lair == null:
		verdict("B0 логова нет", false)
		_finish()
		return
	# Тролли логова на время стенда спят: вор — не их дело здесь
	for t in lair.get("trolls"):
		if is_instance_valid(t):
			(t as Unit).set_tick(false)
	# ── СТАЯ ГНОЛЛОВ УБИРАЕТСЯ, И ЭТО НЕ ПОСЛАБЛЕНИЕ ────────────────────────
	# Со спринта 13 у пня стоят три отряда гноллов (36 метателей), и это
	# ПРАВИЛЬНО: заказ прямо требует, чтобы пень защищали. Но здесь меряется
	# РАБОЧИЙ, а не бой: тридцать шесть чужих ТЕЛ вокруг овцы физически не
	# пускают вора к ней (enemy_block на шаге), и стенд ловил «фаза GO,
	# 1200 физкадров» на исправном коде. Сценарий, зависящий от окружения,
	# обязан ставить это окружение сам
	for g in lair.get("gnolls"):
		if g != null and is_instance_valid(g):
			(g as Node).queue_free()
	await pframes(4)
	var sheep: Array = lair.get("sheep")
	var s: Node3D = sheep[0]
	var spot: Vector3 = s.global_position
	var castle := Castle.new()
	castle.faction = Constants.FACTION_PLAYER
	main.world_add(castle)
	var cp: Vector3 = spot + Vector3(22.0, 0.0, 0.0)
	castle.global_position = Vector3(cp.x, GameManager.get_terrain_height(cp.x, cp.z), cp.z)
	var thief: Worker = _spawn_worker(spot + Vector3(6.0, 0.0, 0.0))
	await pframes(2)
	var flock0: int = int(lair.call("sheep_alive"))
	var food0: float = _food()
	thief.command_steal_sheep(s)
	await pframes(3)
	thief.sheet_frame()
	thief._update_sprite_anim()
	verdict("B1 приказ принят: идёт к овце с лентой ходьбы",
		thief.is_stealing_sheep() and thief.sheep_phase() == Worker.SheepPhase.GO and thief._anim_name == "walk",
		"фаза %d, лента «%s»" % [thief.sheep_phase(), thief._anim_name])
	guard = 0
	while guard < 60 * 20 and thief.sheep_phase() == Worker.SheepPhase.GO:
		await get_tree().physics_frame
		guard += 1
	await pframes(2)
	thief.sheet_frame()
	thief._update_sprite_anim()
	verdict("B2 овца взята: не свободна, рабочий несёт ЕЁ (RETURNING, обычная ходьба)",
		thief.sheep_phase() == Worker.SheepPhase.CARRY and s.get("captor") == thief and not bool(s.call("is_free"))
			and thief.state == Unit.State.RETURNING and thief._anim_name == "walk",
		"фаза %d, лента «%s», физкадров до взятия %d" % [thief.sheep_phase(), thief._anim_name, guard])
	# Овцу поднимает СЛЕДУЮЩИЙ тик рабочего (ветка CARRY), а тик шардирован:
	# на живой карте партии шардов три, и два физкадра после смены фазы его
	# не гарантируют — ждём СВОЙСТВО с потолком (правило 11)
	guard = 0
	while guard < 12 and absf((s.global_position.y - thief.global_position.y) - Worker.SHEEP_CARRY_Y) > 0.05:
		await get_tree().physics_frame
		guard += 1
	var lift: float = s.global_position.y - thief.global_position.y
	var off: float = Vector2(s.global_position.x - thief.global_position.x, s.global_position.z - thief.global_position.z).length()
	verdict("B3 овца едет над головой рабочего", absf(lift - Worker.SHEEP_CARRY_Y) < 0.05 and off < 0.3,
		"подъём %.2f м, сдвиг %.2f м" % [lift, off])
	guard = 0
	while guard < 60 * 40 and thief.sheep_phase() == Worker.SheepPhase.CARRY:
		await get_tree().physics_frame
		guard += 1
	await pframes(2)
	thief.sheet_frame()
	thief._update_sprite_anim()
	var dist_castle: float = Vector2(s.global_position.x - castle.global_position.x, s.global_position.z - castle.global_position.z).length()
	# ── ТРЕБОВАНИЕ РАЗВЁРНУТО СПРИНТОМ 13: ДОНЕСЛИ — НА ВЫПАС ──────────────
	# Прежде рабочий у склада сразу начинал резать. Теперь живая овца сперва
	# ПРИВЯЗЫВАЕТСЯ к загону или к зоне замка (потолок CASTLE_GRAZE_LIMIT) и
	# пасётся там, а разделка — отдельный приказ по СВОЕЙ овце. Мест нет
	# нигде — режут здесь же, у склада (та ветка проверяется ниже, B4в)
	verdict("B4 живая овца у склада уходит НА ВЫПАС, а не под нож",
		not thief.is_stealing_sheep() and thief.state == Unit.State.IDLE
			and bool(s.call("is_owned")) and s.get("keep") == castle
			and not bool(s.call("is_carried")) and dist_castle < castle.ring_radius() + 6.0,
		"работа кончена=%s, привязана=%s, овца в %.1f м от замка, физкадров пути %d" % [
			str(not thief.is_stealing_sheep()), str(bool(s.call("is_owned"))),
			dist_castle, guard])
	verdict("B4б потолок выпаса у замка — CASTLE_GRAZE_LIMIT",
		s.flock_limit() == _UCfg.CASTLE_GRAZE_LIMIT,
		"потолок %d" % s.flock_limit())
	# ── РАЗДЕЛКА: ВТОРОЙ ПРИКАЗ, ПО УЖЕ СВОЕЙ ОВЦЕ ────────────────────────
	thief.command_steal_sheep(s)
	guard = 0
	while guard < 60 * 20 and thief.sheep_phase() == Worker.SheepPhase.GO:
		await get_tree().physics_frame
		guard += 1
	await pframes(2)
	thief.sheet_frame()
	thief._update_sprite_anim()
	verdict("B4в приказ по СВОЕЙ овце — разделка на месте, ножом",
		thief.sheep_phase() == Worker.SheepPhase.KILL
			and thief.state == Unit.State.GATHERING and thief._anim_name == "harvest",
		"фаза %d, лента «%s», физкадров %d" % [
			thief.sheep_phase(), thief._anim_name, guard])
	var flashes := 0
	var cuts_seen := 0
	var hauls_seen := 0
	var flipped := false
	guard = 0
	# ДВЕСТИ ПЯТЬ УДАРОВ И ДВАДЦАТЬ ХОДОК: цикл длиннее прежнего, поэтому и
	# терпение стенда больше — 92 с под ножом плюс дорога. КРАСНОГО МИГАНИЯ
	# БОЛЬШЕ НЕТ ВОВСЕ (заказ спринта 13), и считаем мы его теперь для того,
	# чтобы убедиться, что его НЕТ
	while guard < 60 * 240 and thief.is_stealing_sheep():
		await get_tree().physics_frame
		guard += 1
		var c: int = thief.sheep_cuts_total()
		if c > cuts_seen:
			cuts_seen = c
			if is_instance_valid(s):
				# Окровавленная туша (спринт 19) — ПОСТОЯННАЯ подкраска
				# BLOOD_TINT, а не мигание: считаем только всё остальное
				var mod = s._mat.get_shader_parameter("modulate")
				if mod != null and (mod as Color).g < 0.95 						and not (mod as Color).is_equal_approx(s.BLOOD_TINT):
					flashes += 1
		if thief.sheep_phase() == Worker.SheepPhase.HAUL and thief.carrying_amount > 0.0 \
				and thief.carrying_type == Constants.RESOURCE_FOOD:
			hauls_seen = maxi(hauls_seen, thief.sheep_trips() + 1)
		if is_instance_valid(s) and bool(s.get("dead")):
			flipped = true
	await pframes(2)
	var want_cuts: int = Worker.SHEEP_KILL_CUTS \
		+ Worker.SHEEP_CUTS_PER_MEAT * Worker.SHEEP_MEAT_TRIPS
	var want_meat: float = Worker.MEAT_PER_TRIP * float(Worker.SHEEP_MEAT_TRIPS)
	verdict("B5 %d ударов ножом (%d до смерти + %d × %d на кусок), БЕЗ красного мигания" % [
			want_cuts, Worker.SHEEP_KILL_CUTS, Worker.SHEEP_MEAT_TRIPS,
			Worker.SHEEP_CUTS_PER_MEAT],
		cuts_seen == want_cuts and flashes == 0,
		"ударов %d, миганий %d" % [cuts_seen, flashes])
	verdict("B5в на пятом ударе овца погибла и легла тушей", flipped,
		"признак смерти замечен=%s" % str(flipped))
	# ── СУДИМ ПО ЗАМЕЧЕННЫМ ХОДКАМ, А НЕ ПО СЧЁТЧИКУ В КОНЦЕ ──────────────
	# Со спринта 14 рабочий, выработавший тушу, ТЕМ ЖЕ КАДРОМ берётся за
	# следующую овцу (заказ: «команда не должна сбрасываться»), а новая работа
	# обнуляет счётчик ходок. Требование «мясо носили ходками» от этого не
	# изменилось — изменилось только то, что счётчик к моменту проверки уже
	# принадлежит СЛЕДУЮЩЕЙ туше
	verdict("B5б мясо носили %d ходками, а не зачислялось на месте" % Worker.SHEEP_MEAT_TRIPS,
		hauls_seen >= Worker.SHEEP_MEAT_TRIPS,
		"ходок замечено %d из %d" % [hauls_seen, Worker.SHEEP_MEAT_TRIPS])
	# ПРИРОСТ СКЛАДА МЕНЬШЕ СДАННОГО, И ЭТО НЕ ПОТЕРЯ: разделка идёт полсотни
	# ударов и пять ходок (около сорока секунд игры), а армия всё это время
	# ЕСТ (GameManager._sweep_food). Судим по сданному мясу точно, а по складу
	# — с поправкой на содержание
	verdict("B6 мясо сдано: %.0f (%d ходок по %.0f)" % [want_meat,
			Worker.SHEEP_MEAT_TRIPS, Worker.MEAT_PER_TRIP],
		is_equal_approx(thief.meat_delivered, want_meat)
			and _food() - food0 >= want_meat * 0.8,
		"сдано %.0f, склад +%.1f (остальное съело содержание)" % [
			thief.meat_delivered, _food() - food0])
	# СТАДО ЛОГОВА ЗДЕСЬ УЖЕ НЕ ПРИ ЧЁМ: украденная овца привязана к ЗАМКУ
	# (см. B4), из реестра логова она вышла ещё при краже, а само стадо за
	# полторы минуты успевает подрасти своим приплодом
	verdict("B7 туша выработана и исчезла, рабочий свободен",
		not is_instance_valid(s) and not thief.is_stealing_sheep()
			and thief.state == Unit.State.IDLE,
		"узел жив=%s, работа идёт=%s" % [str(is_instance_valid(s)),
			str(thief.is_stealing_sheep())])
	# Загон в приоритете над складом (задел на будущее)
	var pen_script := GDScript.new()
	pen_script.source_code = "extends Node3D\nvar faction: int = 0\nfunc accept_sheep(_s) -> void:\n\tpass\n"
	pen_script.reload()
	var pen := Node3D.new()
	pen.set_script(pen_script)
	pen.add_to_group("sheep_pens")
	main.world_add(pen)
	pen.global_position = thief.global_position + Vector3(0.0, 0.0, 4.0)
	await frames(1)
	verdict("B8 загон (sheep_pens.accept_sheep) в приоритете над складом",
		thief._sheep_dest() == pen)
	pen.queue_free()
	await frames(1)
	var cheaper: float = want_meat / (_UCfg.HOUSE_FOOD_INCOME / _UCfg.HOUSE_FOOD_INTERVAL)
	# Сдача мяса идёт ходками, поэтому «мяса за тушу» считается по ним
	verdict("B9 одна овца стоит больше минуты дохода дома",
		cheaper >= 60.0, "туша = %.0f с дохода одного дома" % cheaper)

	# ── C. Отмена ──────────────────────────────────────────────────────────
	print("\n═════ C. ОТМЕНА ═════")
	# ── СНАЧАЛА ОСВОБОЖДАЕМ РАБОЧЕГО, И ЭТО НЕ ФОРМАЛЬНОСТЬ ───────────────
	# Со спринта 14 он к этому моменту УЖЕ несёт следующую овцу: доев тушу,
	# он сам берётся за ближайшую. А `command_steal_sheep` по несвободной овце
	# выходит сразу (`is_free` = false) — то есть приказ стенда уходил бы в
	# никуда, и проверка мерила бы чужую, уже идущую работу
	thief.command_move(thief.global_position)
	await pframes(4)
	var s2: Node3D = _free_sheep_near(thief.global_position)
	verdict("C0 свободная овца для проверки отмены нашлась", s2 != null)
	if s2 == null:
		s2 = lair.call("nearest_sheep", thief.global_position)
	thief.command_steal_sheep(s2)
	guard = 0
	while guard < 60 * 25 and thief.sheep_phase() == Worker.SheepPhase.GO:
		await get_tree().physics_frame
		guard += 1
	var was_carry: bool = thief.sheep_phase() == Worker.SheepPhase.CARRY
	thief.command_move(thief.global_position + Vector3(0.0, 0.0, -5.0))
	await pframes(2)
	verdict("C1 новый приказ бросает овцу: рабочий свободен, овца снова свободна и на земле",
		was_carry and not thief.is_stealing_sheep() and bool(s2.call("is_free")) and not bool(s2.call("is_carried"))
			and absf(s2.global_position.y - GameManager.get_terrain_height(s2.global_position.x, s2.global_position.z)) < 0.05,
		"нёс=%s, свободна=%s" % [str(was_carry), str(s2.call("is_free"))])

	# ── D. Лист камня чёрного рабочего ─────────────────────────────────────
	print("\n═════ D. ЛИСТ КАМНЯ (Black) ═════")
	var d := "res://assets/factions/humans/units/Black Units/Pawn/"
	var st := load(d + "Pawn_Run_Stone.png") as Texture2D
	var gd := load(d + "Pawn_Run Gold.png") as Texture2D
	verdict("D1 лист камня того же размера, что лист золота, и на шесть кадров",
		st != null and gd != null and st.get_size() == gd.get_size() and int(st.get_size().x / st.get_size().y) == 6,
		"камень %s, золото %s" % [str(st.get_size() if st else Vector2.ZERO), str(gd.get_size() if gd else Vector2.ZERO)])
	var img: Image = st.get_image() if st != null else null
	var yellow := 0
	if img != null:
		for y in range(0, img.get_height(), 2):
			for x in range(0, img.get_width(), 2):
				var c: Color = img.get_pixel(x, y)
				if c.a > 0.5 and c.r > 0.8 and c.g > 0.8 and c.b < 0.5:
					yellow += 1
	verdict("D2 в листе камня не осталось золотой краски", img != null and yellow == 0, "жёлтых пикселей %d" % yellow)
	_finish()
