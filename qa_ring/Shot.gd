extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ПРИВЯЗКА КОЛЬЦА ВЫДЕЛЕНИЯ К НОГАМ СПРАЙТА
## ═══════════════════════════════════════════════════════════════════════════
## headless не рисует ничего — окно обязательно (как qa_shotvis/qa_veg).
##   godot --path . res://qa_ring/Shot.tscn -- --out=<абс.путь без .png>
##
## Пишет два снимка (_stand — все стоят, _march — все идут) и, ГЛАВНОЕ,
## печатает ЧИСЛА: где на экране логическая точка бойца и где нарисованы его
## ступни. Кольцо пишется ровно в global_position, поэтому расхождение
## «ступни ↔ точка» и есть видимый сдвиг кольца.
##
## Ступни считаются из ГЕОМЕТРИИ, а не на глаз: высота центра квада, его
## полувысота и непрозрачная рамка кадра в самой ленте. Наклон камеры и
## растяжка V_STRETCH взаимно сокращаются (V_STRETCH = 1/cos(pitch)), поэтому
## смещение по вертикали считается прямо в метрах земли.

const _BB := preload("res://scripts/BillboardUtil.gd")

var _out := ""
var _size := Vector2i(1100, 700)
var main = null
var _cam = null

func _ready() -> void:
	call_deferred("_run")

func _args() -> PackedStringArray:
	var all := PackedStringArray()
	all.append_array(OS.get_cmdline_args())
	all.append_array(OS.get_cmdline_user_args())
	return all

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func _shot(suffix: String) -> void:
	if _out == "":
		return
	await frames(4)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s_%s.png" % [_out, suffix])
	print("  снимок: %s_%s.png" % [_out, suffix])

func _run() -> void:
	for a in _args():
		var s := String(a)
		if s.begins_with("--out="):
			_out = s.substr(6)
		elif s.begins_with("--size="):
			var p := s.substr(7).split("x")
			if p.size() == 2:
				_size = Vector2i(int(p[0]), int(p[1]))
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(_size)
	get_tree().root.content_scale_size = _size

	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(12)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
		(GameManager.fog as Node3D).visible = false
	main.set_process(false)
	_cam = main.get("_camera")
	_cam.set_process(false)
	_cam.min_height = 6.0

	# Ровная площадка подальше от леса
	var at := Vector3(0.0, 0.0, 0.0)
	var men: Array = []
	var kinds := ["worker", "spearman", "archer", "warrior"]
	for i in range(kinds.size()):
		var u: Unit = _make(String(kinds[i]))
		u.faction = Constants.FACTION_PLAYER
		main.world_add(u)
		var x: float = at.x - 4.5 + float(i) * 3.0
		u.global_position = Vector3(x, GameManager.get_terrain_height(x, at.z), at.z)
		u.sync_row()
		men.append(u)
	await frames(20)

	var sm = main.selection_manager
	sm._clear_selection()
	for u in men:
		sm._select(u)
	GameManager.on_selection_changed(sm.selected_units)
	_cam.jump_to(at, 8.0)
	await frames(10)
	print("\n═════ СТОЯТ ═════")
	_measure(men)
	await _shot("stand")

	# ── ТЕ ЖЕ БОЙЦЫ НА ХОДУ ────────────────────────────────────────────────
	for u in men:
		(u as Unit).command_move(Vector3(at.x + 60.0, 0.0, at.z + 60.0))
	await frames(90)
	print("\n═════ ИДУТ ═════")
	_measure(men)
	await _shot("march")

	# ── ТО ЖЕ, НО НА ТРЁХ ШАРДАХ ───────────────────────────────────────────
	# Именно так игра тикает при 1200+ бойцах, а жалоба пришла из большого боя.
	# Четырёх бойцов в стенде мало, чтобы лестница включила шардирование сама,
	# поэтому число задаётся принудительно
	preload("res://scripts/perf_config.gd").tick_shards_force = 3
	for u in men:
		(u as Unit).command_move(Vector3(at.x - 60.0, 0.0, at.z + 60.0))
	await frames(120)
	print("\n═════ ИДУТ, 3 ШАРДА (как в большом бою) ═════")
	_measure(men)
	await _shot("march3")
	preload("res://scripts/perf_config.gd").tick_shards_force = 0

	print("\n=== QA_RING DONE ===")
	get_tree().quit(0)

func _make(kind: String) -> Unit:
	match kind:
		"spearman": return Spearman.new()
		"archer":   return Archer.new()
		"warrior":  return Warrior.new()
		_:          return Worker.new()

## Экранная разница «нарисованные ступни минус логическая точка», в МЕТРАХ
## земли (по горизонтали — прямо, по вертикали — с учётом того, что растяжка
## спрайта и наклон камеры взаимно сокращаются)
func _measure(men: Array) -> void:
	for u in men:
		var unit: Unit = u
		var sf: Array = unit.sheet_frame()
		var tex: Texture2D = sf[0]
		if tex == null:
			print("  %s: спрайт не собран" % unit.display_name)
			continue
		var nf: int = int(sf[2])
		var px: float = float(sf[3])
		var base_y: float = float(sf[4])
		var img: Image = tex.get_image()
		if img == null:
			print("  %s: нет картинки ленты" % unit.display_name)
			continue
		var fw: int = int(img.get_width() / maxi(nf, 1))
		var fh: int = img.get_height()
		var fr: int = int(sf[1])
		# Непрозрачная рамка ТЕКУЩЕГО кадра
		var reg := Rect2i(fr * fw, 0, fw, fh)
		var sub: Image = img.get_region(reg)
		var used: Rect2i = sub.get_used_rect()
		var art_cx: float = float(used.position.x) + float(used.size.x) * 0.5
		var art_bottom_pad: int = fh - (used.position.y + used.size.y)
		# Геометрия квада: полувысота на экране = половина кадра в метрах
		var half_h: float = 0.5 * float(fh) * px
		var feet_dy: float = base_y - half_h + float(art_bottom_pad) * px
		var feet_dx: float = (art_cx - float(fw) * 0.5) * px
		# Логическая точка бойца против точки, из которой рисуется спрайт
		var drawn: Vector3 = unit._draw_pos if unit._draw_init else unit.global_position
		var lag: Vector3 = drawn - unit.global_position
		# Где на самом деле лежит кольцо — берём из бухгалтерии слоя
		var ring: Vector3 = GameManager.sel_decals._last_pos.get(unit, Vector3.INF)
		var gap := Vector2(ring.x - drawn.x, ring.z - drawn.z).length() if ring.x != INF else -1.0
		print("  %-22s кадр %dx%d n=%d  ноги: dx=%+.3f м dy=%+.3f м | картинка отстаёт dx=%+.3f dz=%+.3f | КОЛЬЦО ↔ КАРТИНКА %.3f м"
			% [unit.display_name, fw, fh, nf, feet_dx, feet_dy, lag.x, lag.z, gap])
