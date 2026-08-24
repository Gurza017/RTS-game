extends Node

## ВИЗУАЛЬНЫЙ СТЕНД: КАК ВЫГЛЯДИТ РАНЕНЫЙ БОЕЦ.
##
## Зачем окно. Вся фича живёт в шейдере (shaders/mm_unit_sprite.gdshader), а
## headless не рисует ничего вовсе — в нём нельзя даже узнать, компилируется ли
## шейдер. Бухгалтерию (доезжают ли числа до буфера) стережёт qa_wound/Test.gd;
## здесь — единственное, чего тот не увидит: сама картинка.
##
## Запуск:
##   godot --path . res://qa_wound/Shot.tscn -- --out=<абс.путь без .png>
##
## Снимки:
##   _ladder — лесенка состояний: 100 / 90 / 70 / 50 / 30 / 10 % запаса. Первые
##             двое обязаны быть неотличимы от исходного арта (порог 85%),
##             дальше подкраска нарастает;
##   _flash  — вспышка от удара в момент попадания;
##   _crowd  — строй под обстрелом: раненые обязаны читаться СРЕДИ целых, то
##             есть подкраска должна быть заметна, но не превращать бойца в
##             красный силуэт другой фракции.

var _out := ""
var _size := Vector2i(1280, 720)
var main = null
var _flash_keep: Array = []

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

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

## ВСПЫШКА ЖИВЁТ 0.07 с, А СНИМОК ЖДЁТ ШЕСТЬ КАДРОВ — то есть догорает раньше,
## чем срабатывает затвор. Поэтому на время съёмки удар «повторяется» каждый
## кадр: это ровно то же, что делает take_damage, только без урона
func _rearm_flash() -> void:
	for u in _flash_keep:
		if is_instance_valid(u) and not u.is_dead():
			u._hit_flash = Unit.HIT_FLASH_SEC
			u._dmg_dirty = true
			u._push_damage_shade()

func _shot(suffix: String) -> void:
	for _i in range(6):
		_rearm_flash()
		await get_tree().process_frame
	_rearm_flash()
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s_%s.png" % [_out, suffix])
	print("  снимок %-8s вызовов отрисовки: %d" % [suffix,
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])

func _spawn(fac: int, at: Vector3) -> Unit:
	var u: Unit = load("res://scenes/units/Spearman.tscn").instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	return u

## Ранить БЕЗ пути урона: нам нужна ровно заданная доля запаса, а take_damage
## режет броню, стойку и ветеранство и даёт долю приблизительную
func _set_hp(u: Unit, frac: float) -> void:
	u.current_health = u.max_health * frac
	u._dmg_dirty = true

func _run() -> void:
	for a in _args():
		var s := String(a)
		if s.begins_with("--out="):
			_out = s.substr(6)
		elif s.begins_with("--size="):
			var p := s.substr(7).split("x")
			if p.size() == 2:
				_size = Vector2i(int(p[0]), int(p[1]))
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
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
		(GameManager.fog as Node3D).visible = false
	main.set_process(false)
	var cam = main.get("_camera")
	if cam != null:
		cam.set_process(false)
		cam.min_height = 5.0
	for n in get_tree().get_nodes_in_group("all_units"):
		(n as Node).queue_free()
	await frames(4)

	var base: Vector3 = _clear_spot(-70.0)
	var crowd_at: Vector3 = _clear_spot(10.0)

	# ── 1. ЛЕСЕНКА СОСТОЯНИЙ ───────────────────────────────────────────────
	var steps: Array = [1.0, 0.9, 0.7, 0.5, 0.3, 0.1]
	var row: Array = []
	for i in range(steps.size()):
		var u := _spawn(Constants.FACTION_PLAYER,
			base + Vector3(float(i) * 1.7 - 4.2, 0.0, 0.0))
		row.append(u)
	await pframes(6)
	for i in range(steps.size()):
		_set_hp(row[i], float(steps[i]))
	await pframes(2)
	cam.jump_to(base, 8.5)
	await _shot("ladder")

	# ── 2. ВСПЫШКА ОТ УДАРА ────────────────────────────────────────────────
	# Половина ряда мигает, половина нет: рядом видно, насколько сильна засветка
	_flash_keep = [row[0], row[2], row[4]]
	await _shot("flash")
	_flash_keep = []

	# ── 3. РАНЕНЫЕ В СТРОЮ ─────────────────────────────────────────────────
	var crowd: Array = []
	for i in range(48):
		crowd.append(_spawn(Constants.FACTION_PLAYER,
			crowd_at + Vector3(float(i % 8) * 1.3 - 4.5, 0.0,
				float(i / 8) * 1.3 - 3.2)))
	await pframes(8)
	for i in range(crowd.size()):
		if i % 3 == 0:
			_set_hp(crowd[i], 0.25)
		elif i % 3 == 1:
			_set_hp(crowd[i], 0.6)
	await pframes(2)
	cam.jump_to(crowd_at, 11.0)
	await _shot("crowd")

	print("=== WOUND SHOT DONE ===")
	get_tree().quit(0)

## Чистая площадка около заданного x (та же, что в qa_shotcorpse): карта
## заросшая, и в роще бойца закрывает крона — судить по такому снимку нельзя
func _clear_spot(x0: float) -> Vector3:
	for r in range(0, 60, 3):
		for a in range(0, 12):
			var ang: float = TAU * float(a) / 12.0
			var p := Vector3(x0 + cos(ang) * float(r), 0.0, sin(ang) * float(r))
			if absf(p.x) > 110.0 or absf(p.z) > 55.0:
				continue
			if main.is_water(p.x, p.z):
				continue
			var ok := true
			for n in get_tree().get_nodes_in_group("resource_nodes"):
				var rn := n as ResourceNode
				if rn != null and rn.global_position.distance_to(p) < 13.0:
					ok = false
					break
			if ok:
				return p
	return Vector3(x0, 0.0, 0.0)
