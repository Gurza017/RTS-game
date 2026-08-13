extends Node

## СКОЛЬКО СТОИТ РАСТИТЕЛЬНОСТЬ САМА ПО СЕБЕ.
## Камера отводится на максимум и ставится в центр карты, так что в кадр
## попадает вся декорация разом — худший возможный случай. Армии нет вовсе:
## всё, что здесь меряется, — это лес, кусты и грунт.
##
## ОКОННЫЙ стенд: в headless не рисуется ничего и вызовы отрисовки равны нулю.
## Запуск: godot --path . res://qa_veg/Test.tscn

var main = null

func _ready() -> void:
	call_deferred("_run")

func _avg(mon: int, n: int) -> float:
	var acc := 0.0
	for _i in range(n):
		await get_tree().process_frame
		acc += Performance.get_monitor(mon)
	return acc / float(n)

func _run() -> void:
	# БЕЗ ЭТОГО СТЕНД МЕРЯЕТ МОНИТОР, А НЕ ИГРУ. Первый прогон дал ровно 75
	# кадров в секунду и до, и после четырёхкратного падения числа вызовов
	# отрисовки — потому что упирался в вертикальную синхронизацию, а не в лес
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	for _i in range(10):
		await get_tree().process_frame

	# Камеру прибиваем: её _process крутит краевую прокрутку по курсору
	var cam = main.get("_camera")
	if cam != null:
		cam.set_process(false)
		cam.jump_to(Vector3.ZERO, cam.max_height)
	for _i in range(30):
		await get_tree().process_frame

	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var res_nodes := get_tree().get_nodes_in_group("resource_nodes").size()

	var draws := await _avg(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME, 90)
	var objs  := await _avg(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME, 90)
	# ВРЕМЯ КАДРА МЕРЯЕТСЯ ЧАСАМИ, А НЕ МОНИТОРАМИ ДВИЖКА. Performance.TIME_FPS
	# в оконном прогоне отдавал то ровно частоту монитора (упор в вертикальную
	# синхронизацию), то откровенную чушь вроде «1», а TIME_PROCESS показывал
	# 0.00 мс при полной карте в кадре — оба мимо. Здесь считается настоящее
	# время между кадрами: сколько прошло часов на N кадрах отрисовки
	const N := 240
	var t0 := Time.get_ticks_usec()
	for _i in range(N):
		await get_tree().process_frame
	var frame := float(Time.get_ticks_usec() - t0) / 1000.0 / float(N)
	var fps := 1000.0 / maxf(frame, 0.001)

	var out := PackedStringArray()
	out.append("")
	out.append("═══ ЦЕНА ДЕКОРАЦИИ: ВСЯ КАРТА В КАДРЕ, АРМИИ НЕТ ═══")
	out.append("узлов в дереве:            %d" % nodes)
	out.append("ресурсных узлов на карте:  %d" % res_nodes)
	out.append("вызовов отрисовки в кадре: %.0f" % draws)
	out.append("объектов в кадре:          %.0f" % objs)
	out.append("время кадра (по часам):    %.2f мс" % frame)
	out.append("кадров в секунду:          %.0f" % fps)
	out.append("")
	out.append("Бюджет кадра: 120 к/с = 8.33 мс, 100 к/с = 10.00 мс")
	print("\n".join(out))
	get_tree().quit(0)
