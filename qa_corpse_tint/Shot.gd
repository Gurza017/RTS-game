extends Node

## ОКОННЫЙ СТЕНД: ПАЛИТРА КУЧИ ТЕЛ (ТЗ 01.11.2026, «оттеночный блицкриг»).
##
## Кладёт завал на броде (гоблины, туши, тролли, синие и красные люди) и
## второй на траве у берега, снимает его в прежнем виде, а потом переключает
## палитру и тень НАСТОЯЩИМИ клавишами партии (F7 — палитра, F8 — тень; см.
## Main._unhandled_input, CorpseRenderer.CORPSE_PALETTES / CORPSE_SHADOWS):
## на снимке видна и плашка HUD с подписью.
##
## Запуск (окно, без звука):
##   godot --audio-driver Dummy --windowed --position -5000,-5000 --path . \
##     res://qa_corpse_tint/Shot.tscn -- --out=<абс.путь без .png> bg=1
## Пишет <out>_base.png (палитра 0, тень 0) и <out>_p<палитра>s<тень>.png по
## списку --set=2:1,1:1 (по умолчанию 2:1 — гибрид «мох + тень охры»).

const _Opt := preload("res://scripts/perf_config.gd")

var _out := ""
var _sets: Array = [[2, 1]]
var _size := Vector2i(1600, 1000)
var main = null

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _shot(suffix: String) -> void:
	await frames(6)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s_%s.png" % [_out, suffix])
	print("  снимок %-8s вызовов отрисовки: %d" % [suffix,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])

func _spawn(path: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = load(path).instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	return u

## Завал: плотное пятно, гуще в середине
func _heap(c: Vector3, r: float, rng: RandomNumberGenerator, plan: Array) -> Array:
	var out: Array = []
	for p in plan:
		for _i in range(int(p[2])):
			var a: float = rng.randf() * TAU
			var d: float = sqrt(rng.randf()) * r
			var at := c + Vector3(cos(a) * d, 0.0, sin(a) * d * 0.7)
			if main.is_water(at.x, at.z):
				continue
			out.append(_spawn(String(p[0]), int(p[1]), at))
	return out

## Нажатие клавиши — настоящим вводом, как в партии
func _press(key: Key, shift: bool = false) -> void:
	for down in [true, false]:
		var e := InputEventKey.new()
		e.keycode = key
		e.physical_keycode = key
		e.shift_pressed = shift
		e.pressed = down
		Input.parse_input_event(e)
		await frames(2)

## Дойти клавишами до палитры p и тени s (по кругу, как игрок)
func _dial(p: int, s: int, v: int = 0) -> void:
	var guard := 0
	while _Opt.corpse_vivid != v and guard < 10:
		await _press(KEY_F9)
		guard += 1
	guard = 0
	while _Opt.corpse_palette != p and guard < 10:
		await _press(KEY_F7)
		guard += 1
	guard = 0
	while _Opt.corpse_shadow != s and guard < 10:
		await _press(KEY_F8)
		guard += 1

func _run() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--out="):
			_out = s.substr(6)
		elif s.begins_with("--set="):
			_sets.clear()
			for pair in s.substr(6).split(","):
				var ps: PackedStringArray = pair.split(":")
				if ps.size() >= 2:
					_sets.append([int(ps[0]), int(ps[1]), int(ps[2]) if ps.size() > 2 else 0])
	if _out == "":
		push_error("нужен --out=<путь без расширения>")
		get_tree().quit(1)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(_size)
	get_tree().root.content_scale_size = _size
	# Сторож: корутина, упавшая с ошибкой, иначе висела бы вечно
	get_tree().create_timer(300.0).timeout.connect(func(): get_tree().quit(2))
	# Снимок «как было» — прежняя палитра и прежняя тень
	_Opt.corpse_palette = 0
	_Opt.corpse_shadow = 0
	_Opt.corpse_vivid = 0

	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(12)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
		(GameManager.fog as Node3D).visible = false
	main.set_process(false)
	var cam = main.get("_camera")
	if cam != null:
		cam.set_process(false)

	var rng := RandomNumberGenerator.new()
	rng.seed = 1031
	var ford: Vector3 = main.ford_point()
	# Второй завал — на траве у берега, по направлению от реки к базе игрока
	var bank := ford + Vector3(-16.0, 0.0, 4.0)
	var G := Constants.FACTION_GOBLIN
	var P := Constants.FACTION_PLAYER
	var E := Constants.FACTION_ENEMY
	var plan_ford := [
		["res://scenes/units/GoblinSpearman.tscn", G, 320],
		["res://scenes/units/Troll.tscn", G, 3],
		["res://scenes/units/BigGoblin.tscn", G, 5],
		["res://scenes/units/Spearman.tscn", P, 24],
		["res://scenes/units/Spearman.tscn", E, 14],
	]
	var plan_bank := [
		["res://scenes/units/GoblinSpearman.tscn", G, 70],
		["res://scenes/units/BigGoblin.tscn", G, 3],
		["res://scenes/units/Spearman.tscn", P, 20],
		["res://scenes/units/Warrior.tscn", E, 12],
	]
	var all: Array = []
	all.append_array(_heap(ford, 8.0, rng, plan_ford))
	all.append_array(_heap(bank, 5.5, rng, plan_bank))
	for u in all:
		u.set_tick(false)
	await pframes(4)
	# Тролль от одного удара валится с ног, а не гибнет — бьём до смерти
	for _k in range(30):
		var left := 0
		for u in all:
			if is_instance_valid(u) and not u.is_dead():
				left += 1
				u.current_health = 1.0
				u.take_damage(u.max_health * 50.0 + 5000.0, null)
		if left == 0:
			break
		await pframes(3)
	# Туша тролля сперва летит (разлёт смерти) и лишь потом ложится телом
	await pframes(240)
	GameManager.corpses.flush()
	print("тел: %d, бакетов тел: %d, туш троллей: %d" % [GameManager.corpses.count(),
		GameManager.corpses.bucket_count(), get_tree().get_nodes_in_group("troll_corpse").size()])
	cam.jump_to((ford + bank) * 0.5 + Vector3(2.0, 0.0, 0.0), 19.0)
	await frames(30)
	await _shot("base")
	for st in _sets:
		var vv: int = int(st[2]) if st.size() > 2 else 0
		await _dial(int(st[0]), int(st[1]), vv)
		print(GameManager.corpses.palette_caption())
		await _shot("p%ds%dv%d" % [int(st[0]), int(st[1]), vv])
	print("=== CORPSE TINT DONE ===")
	get_tree().quit(0)
