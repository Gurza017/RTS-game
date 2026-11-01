extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_tz1031b — ЗНАМЁНА СТОРОН, КЛИК ПО ЗНАМЕНИ, ОВЦЕФЕРМА, РУДНИК
## (ТЗ 31.10.2026, пакет UI)
## ═══════════════════════════════════════════════════════════════════════════
##   A ЗНАМЁНА — лычки старших ступеней оранжевые, легенда без жёлтого (синее
##              поле, фиолетовая рамка), красный ИИ — красное поле с теми же
##              лычками, Свинобосс — зелёный; ручка faction_banners.
##   B КЛИК ПО ЗНАМЕНИ — клик по полотнищу выбирает отряд; ручка banner_click.
##   C ОВЦЕФЕРМА — клик по овце открывает ферму, без выделения над фермой
##              палец и подсветка, рабочий над фермой — нож; ручка pen_hover.
##   D РУДНИК — рабочие над своим рудником: кирка, приказ — рудник мигает и
##              реплика «worker_gold»; ручка mine_confirm.
## Запуск: godot --headless --path . res://qa_tz1031b/Test.tscn [-- only=abcd]

const F := Constants.FACTION_PLAYER
const _Opt := preload("res://scripts/perf_config.gd")
const _BA := preload("res://scripts/BannerArt.gd")
const _U := preload("res://scripts/unit_stats_config.gd")
const _Pen := preload("res://scripts/SheepPen.gd")
const _Sheep := preload("res://scripts/goblin/Sheep.gd")
const _CA := preload("res://scripts/CursorArt.gd")
const _BB := preload("res://scripts/BillboardUtil.gd")

var main = null
var sm = null
var _pass := 0
var _fail := 0
var _log: Array = []
var _only: String = "abcd"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("only="):
			_only = String(a).substr(5)
	call_deferred("_run")
	get_tree().create_timer(300.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 300 с")
		_finish())

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	_log.append([t, ok])
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО", ("  — " + d) if d != "" else ""])

func _finish() -> void:
	print("\n═════ ИТОГ qa_tz1031b: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(30)
	for n in ["enemy_ai", "goblin_ai", "assault_event", "gnoll_ai", "cav_commander", "pig_boss_cmd", "raid_manager"]:
		var nd = main.get(n)
		if nd != null:
			nd.set_process(false)
			nd.set_physics_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	sm = main.selection_manager
	if "a" in _only: await _block_a()
	if "b" in _only: await _block_b()
	if "c" in _only: await _block_c()
	if "d" in _only: await _block_d()
	_finish()

# ── пиксели ────────────────────────────────────────────────────────────────
## Сколько непрозрачных пикселей картинки ближе tol к цвету c
func _count(tex: Texture2D, c: Color, tol: float = 0.06) -> int:
	if tex == null:
		return 0
	var img: Image = tex.get_image()
	var n := 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var p: Color = img.get_pixel(x, y)
			if p.a > 0.5 and absf(p.r - c.r) < tol and absf(p.g - c.g) < tol and absf(p.b - c.b) < tol:
				n += 1
	return n

func _greenish(tex: Texture2D) -> int:
	var img: Image = tex.get_image()
	var n := 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var p: Color = img.get_pixel(x, y)
			if p.a > 0.5 and p.g > p.r + 0.2 and p.g > p.b + 0.2:
				n += 1
	return n

func _block_a() -> void:
	print("\n── A. Знамёна сторон и лычки ──")
	_BA.clear_cache()
	var t7: Texture2D = _BA.texture_for(7)
	verdict("A1 старшие ступени — оранжевые лычки, не золотые",
		_count(t7, _U.CHEV_ORANGE) > 20 and _count(t7, _U.CHEV_GOLD) == 0,
		"оранжевых %d, золотых %d" % [_count(t7, _U.CHEV_ORANGE), _count(t7, _U.CHEV_GOLD)])
	var lg: Texture2D = _BA.legend_texture(2)
	verdict("A2 легенда — синее поле, фиолетовая рамка, оранжевые лычки, жёлтого нет",
		_count(lg, _U.BANNER_BLUE) > 200 and _count(lg, _U.BANNER_PURPLE) > 40
			and _count(lg, _U.CHEV_ORANGE) > 40 and _count(lg, _U.LEGEND_GOLD, 0.1) == 0,
		"синих %d, фиолетовых %d, оранжевых %d, жёлтых %d" % [_count(lg, _U.BANNER_BLUE),
			_count(lg, _U.BANNER_PURPLE), _count(lg, _U.CHEV_ORANGE), _count(lg, _U.LEGEND_GOLD, 0.1)])
	var red4: Texture2D = _BA.texture_for(4, _BA.SIDE_RED)
	verdict("A3 красный ИИ — красное поле, красные лычки в светлом канте",
		_count(red4, _U.BANNER_RED) > 200 and _count(red4, _U.BANNER_BLUE) == 0
			and _count(red4, _U.CHEV_RED) > 20 and _count(red4, _U.CHEV_WHITE) > 20,
		"красного поля %d, синего %d, лычки %d, канта %d" % [_count(red4, _U.BANNER_RED),
			_count(red4, _U.BANNER_BLUE), _count(red4, _U.CHEV_RED), _count(red4, _U.CHEV_WHITE)])
	var el: Texture2D = _BA.elite_texture(1, 3, _BA.SIDE_RED)
	verdict("A4 штандарт красного — красный пятак вместо синего",
		_count(el, _U.BANNER_RED) > 30 and _count(el, _BA.ELITE_PLATE) == 0,
		"красного %d, синего пятака %d" % [_count(el, _U.BANNER_RED), _count(el, _BA.ELITE_PLATE)])
	var boss: Texture2D = _BA.boss_texture(3)
	verdict("A5 знамя Свинобосса зелёное", _greenish(boss) > 100 and _count(boss, _U.BANNER_BLUE) == 0,
		"зелёных %d, синих %d" % [_greenish(boss), _count(boss, _U.BANNER_BLUE)])
	# Живое знамя отряда красного ИИ
	var sid: int = GameManager.new_squad(Constants.FACTION_ENEMY, "spearman")
	var at := Vector3(20, 0, 20)
	var u: Unit = Building.PRELOAD_SCENES["spearman"].instantiate()
	u.faction = Constants.FACTION_ENEMY
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	GameManager.add_to_squad(sid, u)
	(GameManager.squads[sid] as Dictionary)["level"] = 4
	GameManager.refresh_squad_banner(sid)
	var b = (GameManager.squads[sid] as Dictionary).get("banner")
	verdict("A6 знамя отряда красного ИИ — сторона красная", b != null and int(b.shown_side) == _BA.SIDE_RED,
		"side %s" % (str(b.shown_side) if b != null else "нет знамени"))
	_Opt.faction_banners = false
	_BA.clear_cache()
	var off_side: int = _BA.side_of(Constants.FACTION_ENEMY)
	var boss_off: Texture2D = _BA.boss_texture(3)
	verdict("A0 без ручки — красный под синим, босс синий", off_side == 0 and _count(boss_off, _U.BANNER_BLUE) > 100,
		"side %d, синих у босса %d" % [off_side, _count(boss_off, _U.BANNER_BLUE)])
	_Opt.faction_banners = true
	_BA.clear_cache()
	u.take_damage(1e12)
	await pframes(4)

# ── камера ──────────────────────────────────────────────────────────────────
func _freeze_cam(at: Vector3) -> void:
	main.set_process(false)
	main._camera.set_process(false)
	main._camera.pan_to(Vector3(at.x, 0.0, at.z))
	main._camera._update_position()
	await frames(3)

func _spawn(kind: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[kind].instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _clear_area(c: Vector3) -> void:
	main._clear_area_of_resources(c, 30.0)
	main._clear_trees(c, 30.0)
	for n in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(n) and n is Unit and (n as Node3D).global_position.distance_to(c) < 30.0:
			(n as Unit).take_damage(1e12)
	await pframes(6)

## Экранная точка в полотнище знамени отряда (верхняя часть квада)
func _banner_point(sid: int) -> Vector2:
	var b = (GameManager.squads[sid] as Dictionary).get("banner")
	var qm: QuadMesh = (b as MeshInstance3D).mesh as QuadMesh
	var c: Vector3 = (b as Node3D).global_position + Vector3.UP * qm.size.y * 0.5 * _BB.V_STRETCH * 0.55
	return sm.camera.unproject_position(c)

func _block_b() -> void:
	print("\n── B. Клик по знамени выбирает отряд ──")
	var at := Vector3(10, 0, 30)
	await _clear_area(at)
	var sid: int = GameManager.new_squad(F, "spearman")
	var men: Array = []
	for i in range(12):
		var u: Unit = _spawn("spearman", F, at + Vector3(float(i % 4) * 0.6, 0, float(i / 4) * 0.6))
		GameManager.add_to_squad(sid, u)
		men.append(u)
	(GameManager.squads[sid] as Dictionary)["level"] = 4
	GameManager.refresh_squad_banner(sid)
	await pframes(10)
	await _freeze_cam(at)
	await frames(3)
	sm.clear_selection()
	var scr: Vector2 = _banner_point(sid)
	var hit: Unit = sm.banner_unit_at(scr)
	sm._handle_single_click(scr, false)
	await frames(2)
	var sel_ok: bool = false
	for m in men:
		if sm.selected_units.has(m):
			sel_ok = true
	verdict("B1 клик по полотнищу знамени выделяет его отряд", hit != null and hit.squad_id == sid and sel_ok,
		"под курсором %s, выделено %d" % [str(hit.squad_id) if hit != null else "никто", sm.selected_units.size()])
	# Мимо знамени, высоко над ним — ничего
	var miss: Unit = sm.banner_unit_at(scr + Vector2(0, -300))
	verdict("B2 мимо знамени — знамя не ловит клик", miss == null, "")
	sm.clear_selection()
	_Opt.banner_click = false
	var off: Unit = sm.banner_unit_at(scr)
	verdict("B0 без ручки — знамя не кликается", off == null, "")
	_Opt.banner_click = true
	for m2 in men:
		if is_instance_valid(m2):
			(m2 as Unit).take_damage(1e12)
	main.set_process(true)
	main._camera.set_process(true)
	await pframes(4)

# ── овцеферма ───────────────────────────────────────────────────────────────
func _block_c() -> void:
	print("\n── C. Овцеферма: клик, палец, подсветка, нож ──")
	var at := Vector3(-20, 0, 40)
	await _clear_area(at)
	var pen: Building = _Pen.new()
	pen.faction = F
	pen.set("auto_restock", false)
	main.world_add(pen)
	pen.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	await pframes(10)
	var s: Node3D = _Sheep.new()
	s.set("home", at)
	main.world_root().add_child(s)
	s.global_position = Vector3(at.x + 0.6, GameManager.get_terrain_height(at.x, at.z), at.z + 0.6)
	s.set("owner_faction", F)
	s.set("pen", pen)
	s.set_process(false)
	await pframes(6)
	await _freeze_cam(at)
	sm.clear_selection()
	var cam: Camera3D = sm.camera
	var scr_s: Vector2 = cam.unproject_position(s.global_position + Vector3.UP * 0.3)
	sm._handle_single_click(scr_s, false)
	await frames(2)
	verdict("C1 клик по своей овце открывает её овцеферму", sm.selected_units.has(pen),
		"выделено %d, ферма %s" % [sm.selected_units.size(), str(sm.selected_units.has(pen))])
	sm.clear_selection()
	await frames(1)
	var scr_p: Vector2 = cam.unproject_position((pen._pick_shape as Node3D).global_position) \
		if pen.get("_pick_shape") != null else cam.unproject_position(pen.global_position)
	var k_empty: int = sm.hover_cursor_kind(scr_p)
	main._update_pen_glow(scr_p)
	verdict("C2 без выделения над фермой — палец и подсветка", k_empty == _CA.FINGER and pen.hover_glow,
		"курсор %d, подсветка %s" % [k_empty, str(pen.hover_glow)])
	main._update_pen_glow(scr_p + Vector2(0, -400))
	verdict("C3 курсор ушёл — подсветка гаснет", not pen.hover_glow, "")
	var w: Unit = _spawn("worker", F, at + Vector3(6, 0, 0))
	GameManager.add_to_squad(GameManager.new_squad(F, "worker"), w)
	sm.select_units([w])
	await frames(1)
	var k_w: int = sm.hover_cursor_kind(scr_p)
	var k_ws: int = sm.hover_cursor_kind(scr_s)
	verdict("C4 рабочий над фермой и над овцой — нож", k_w == _CA.KNIFE and k_ws == _CA.KNIFE,
		"ферма %d, овца %d" % [k_w, k_ws])
	sm.clear_selection()
	_Opt.pen_hover = false
	var k_off: int = sm.hover_cursor_kind(scr_p)
	sm._handle_single_click(scr_s, false)
	await frames(2)
	verdict("C0 без ручки — пальца нет, клик по овце ферму не открывает",
		k_off == _CA.NONE and not sm.selected_units.has(pen), "курсор %d" % k_off)
	_Opt.pen_hover = true
	sm.clear_selection()
	w.take_damage(1e12)
	main.set_process(true)
	main._camera.set_process(true)
	await pframes(4)

# ── рудник ──────────────────────────────────────────────────────────────────
func _block_d() -> void:
	print("\n── D. Золотой рудник: кирка, мигание, реплика ──")
	var mine: Mine = null
	for b in get_tree().get_nodes_in_group("buildings"):
		if is_instance_valid(b) and b is Mine and not (b as Mine).is_dead():
			mine = b
			break
	if mine == null:
		for n in main.find_children("*", "", true, false):
			if n is Mine:
				mine = n
				break
	if mine == null:
		verdict("D рудник на карте", false, "рудника нет")
		return
	mine.faction = F
	# Туман стенд выключил после старта: рудник, спрятанный им до того, не
	# ловит луч (Building.set_fog_hidden снимает слой клика)
	mine.set_fog_hidden(false)
	var at: Vector3 = mine.global_position
	await _freeze_cam(at)
	var w: Unit = _spawn("worker", F, at + Vector3(8, 0, 0))
	GameManager.add_to_squad(GameManager.new_squad(F, "worker"), w)
	sm.select_units([w])
	await frames(2)
	var cam: Camera3D = sm.camera
	var scr: Vector2 = cam.unproject_position((mine._pick_shape as Node3D).global_position) \
		if mine.get("_pick_shape") != null else cam.unproject_position(mine.global_position)
	var k: int = sm.hover_cursor_kind(scr)
	verdict("D1 рабочий над своим рудником — кирка", k == _CA.PICKAXE, "курсор %d" % k)
	var f0: int = mine.accept_flashes
	AudioManager.voice_last = ""
	var ok: bool = sm._try_enter_mine(mine)
	verdict("D2 приказ в рудник — рудник мигнул, реплика рабочих",
		ok and mine.accept_flashes == f0 + 1 and AudioManager.voice_last == "worker_gold",
		"приказ %s, миганий %d, реплика «%s»" % [str(ok), mine.accept_flashes - f0, AudioManager.voice_last])
	verdict("D3 реплика — из пула «Go / Come on»",
		(AudioManager.REPLY_POOL_EVENTS["worker_gold"] as Array).has(AudioManager.reply_last_id) or not AudioManager.enabled,
		"фраза %s" % AudioManager.reply_last_id)
	var w2: Unit = _spawn("worker", F, at + Vector3(9, 0, 1))
	GameManager.add_to_squad(GameManager.new_squad(F, "worker"), w2)
	sm.select_units([w2])
	await frames(2)
	_Opt.mine_confirm = false
	var k_off: int = sm.hover_cursor_kind(scr)
	var f1: int = mine.accept_flashes
	sm._try_enter_mine(mine)
	verdict("D0 без ручки — не кирка, рудник не мигает", k_off != _CA.PICKAXE and mine.accept_flashes == f1,
		"курсор %d, миганий %d" % [k_off, mine.accept_flashes - f1])
	_Opt.mine_confirm = true
	sm.clear_selection()
	main.set_process(true)
	main._camera.set_process(true)
