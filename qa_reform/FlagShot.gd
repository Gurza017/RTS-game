extends Node
## ═══════════════════════════════════════════════════════════════════════════
## ОКОННЫЙ ЗОНД: ЧТО ИМЕННО ВИДИТ ИГРОК ПОД ЗНАМЁНАМИ ОРДЫ
## ═══════════════════════════════════════════════════════════════════════════
## Headless-зонд (Flags.gd) показал, что узлов знамён ровно столько, сколько
## ветеранских отрядов, и бесхозных нет вовсе. Значит вопрос не в учёте, а в
## КАРТИНКЕ: жалоба владельца — «флажки в пустой траве», и решить, пусто там
## или нет, может только глаз.
##
## Снимки идут по ходу настоящей партии: спящая орда, проснувшаяся орда, марш,
## бой. Камера каждый раз наводится на знамя, а не на толпу, — смотреть надо
## именно на то, что под флагом.
##
## Запуск: godot --path . res://qa_reform/FlagShot.tscn --out=<путь без .png>

var main = null
var _out := ""
var _size := Vector2i(1000, 800)
var _cam = null

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func pf(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _args() -> PackedStringArray:
	return OS.get_cmdline_user_args() if OS.get_cmdline_user_args().size() > 0 \
		else OS.get_cmdline_args()

func _shot(suffix: String) -> void:
	await frames(6)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s_%s.png" % [_out, suffix])
	print("  снимок %s" % suffix)

## Знамя первого ветеранского отряда орды и его знаменосец
func _first_banner() -> Array:
	for key in GameManager.squads.keys():
		var sq: Dictionary = GameManager.squads[key]
		if int(sq.get("faction", -1)) != Constants.FACTION_GOBLIN:
			continue
		var b = sq.get("banner", null)
		if b == null or not is_instance_valid(b):
			continue
		return [int(key), b, GameManager.squad_bearer(int(key))]
	return []

func _look(tag: String) -> void:
	var rec: Array = _first_banner()
	if rec.is_empty():
		print("  %s: знамён у орды нет вовсе" % tag)
		return
	var b: Node3D = rec[1]
	var br = rec[2]
	var live := 0
	var near := 0
	for m in GameManager.squad_members(int(rec[0])):
		var u := m as Unit
		if u == null or not is_instance_valid(u) or u.is_dead():
			continue
		live += 1
		if Vector2(u.global_position.x - b.global_position.x,
				u.global_position.z - b.global_position.z).length() < 6.0:
			near += 1
	print("  %s: знамя в (%.0f, %.0f), видимо=%s, знаменосец=%s, живых в отряде %d, из них в 6 м от знамени %d"
		% [tag, b.global_position.x, b.global_position.z, str(b.visible),
			"есть" if br != null else "НЕТ", live, near])
	if _cam != null:
		_cam.jump_to(b.global_position, 14.0)
	await _shot(tag)

func _run() -> void:
	for a in _args():
		var s := String(a)
		if s.begins_with("--out="):
			_out = s.substr(6)
	if _out == "":
		push_error("нужен --out=<путь без расширения>")
		get_tree().quit(1)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(_size)
	get_tree().root.content_scale_size = _size

	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(12)
	GameManager.world_bounds_enabled = false
	# Туман снят НАМЕРЕННО: под пеленой не видно ничего в принципе, а вопрос
	# стоит про освещённое поле
	if GameManager.fog != null:
		GameManager.fog.enabled = false
		(GameManager.fog as Node3D).visible = false
	_cam = main.get("_camera")
	if _cam != null:
		_cam.set_process(false)
		_cam.min_height = 6.0
	await pf(10)
	print("\n═════ ОКОННЫЙ ЗОНД: ЗНАМЁНА ОРДЫ ═════")
	await _look("sleeping")

	if main.goblin_ai != null:
		main.goblin_ai._wake_horde()
	await pf(90)
	await _look("awake")

	# Противник — чтобы орда пошла в бой и меняла состояния
	var centre: Vector3 = main.goblin_village_center()
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "warrior")
	for i in range(60):
		var u: Unit = load("res://scenes/units/Warrior.tscn").instantiate()
		u.faction = Constants.FACTION_PLAYER
		main.world_add(u)
		var px: float = centre.x + 26.0 + float(i % 10) * 0.9
		var pz: float = centre.z + float(i / 10) * 0.9
		u.global_position = Vector3(px, GameManager.get_terrain_height(px, pz), pz)
		u.sync_row()
		u.max_health *= 40.0
		u.current_health = u.max_health
		u.attack_damage *= 6.0
		GameManager.add_to_squad(sid, u)
	await pf(20)
	for m in GameManager.squad_members(sid):
		(m as Unit).command_move(centre, false)
	await pf(240)
	await _look("battle1")
	await pf(240)
	await _look("battle2")
	await pf(360)
	await _look("battle3")

	# ── ПОСЛЕ БОЙНИ: ЧТО ОСТАЁТСЯ НА ПОЛЕ ──────────────────────────────────
	# Ровно то состояние, с которого начата жалоба: «отряд уничтожен целиком,
	# а флажки остались висеть в траве»
	var centre2: Vector3 = main.goblin_village_center()
	for n in get_tree().get_nodes_in_group("goblin_units"):
		var g := n as Unit
		if g != null and is_instance_valid(g) and not g.is_dead():
			g.take_damage(1e9, null)
	await pf(30)
	_dump_banners("после гибели орды")
	if _cam != null:
		_cam.jump_to(centre2, 26.0)
	await _shot("aftermath")

	print("=== FLAGSHOT DONE ===")
	get_tree().quit()

## Все узлы знамён в дереве: чей, где, видно ли, есть ли под ним живые
func _dump_banners(tag: String) -> void:
	var scr = load("res://scripts/SquadBanner.gd")
	var stack: Array = [get_tree().root]
	var found := 0
	print("  ── %s ──" % tag)
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for ch in node.get_children():
			stack.append(ch)
		if not (node is MeshInstance3D and node.get_script() == scr):
			continue
		found += 1
		var owner_sid := 0
		for key in GameManager.squads.keys():
			if (GameManager.squads[key] as Dictionary).get("banner", null) == node:
				owner_sid = int(key)
				break
		var p: Vector3 = (node as Node3D).global_position
		print("     знамя #%d в (%.0f, %.0f) видимо=%s отряд=%d живых=%d"
			% [found, p.x, p.z, str((node as MeshInstance3D).visible), owner_sid,
				GameManager.squad_members(owner_sid).size() if owner_sid > 0 else -1])
	print("     всего узлов: %d, тел и знамён на поле: %d"
		% [found, GameManager.corpses.count()])
