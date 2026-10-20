extends Node

## ═══════════════════════════════════════════════════════════════════════════
## «ИГРАТЬ ЗАНОВО»: ПОСЛЕ ПЕРЕЗАПУСКА СЦЕНЫ БОЙЦЫ ВИДИМЫ (ТЗ 11.10.2026, ч. 1 п. 1)
## ═══════════════════════════════════════════════════════════════════════════
## Слои общей отрисовки (FarUnitRenderer, SelectionDecalRenderer,
## HpBarRenderer) живут в автозагрузке, их узлы MultiMeshInstance3D — под
## World партии. Стенд поднимает Main, выделяет рабочих (кольца, полоски),
## выгружает сцену так же, как reload_current_scene/change_scene, поднимает
## новую и проверяет, что у КАЖДОГО рабочего бакет рисуется узлом В ДЕРЕВЕ,
## а слои колец и полосок тоже на месте. Три круга подряд.
## Запуск: godot --headless --path . res://qa_restart/Test.tscn

var _pass := 0
var _fail := 0

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(240.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился")
		_finish())

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО", ("  — " + d) if d != "" else ""])

var _done := false
func _finish() -> void:
	if _done:
		return
	_done = true
	print("\n═════ ИТОГ qa_restart: прошло %d, провалов: %d ═════" % [_pass, _fail])
	get_tree().quit()

func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _workers() -> Array:
	var o: Array = []
	for u in get_tree().get_nodes_in_group("player_units"):
		if is_instance_valid(u) and u is Worker and not (u as Unit).is_dead():
			o.append(u)
	return o

func _check(round_i: int, main: Node) -> void:
	var ws: Array = _workers()
	var drawn := 0
	for w in ws:
		var s = GameManager.far_units._slot.get(w)
		if s == null:
			continue
		var mmi = s.bucket.mmi
		if is_instance_valid(mmi) and (mmi as Node).is_inside_tree() \
				and (mmi as MultiMeshInstance3D).multimesh == s.bucket.mm \
				and main.is_ancestor_of(mmi):
			drawn += 1
	verdict("R%d.1 все рабочие рисуются узлом новой сцены" % round_i, ws.size() > 0 and drawn == ws.size(),
		"рабочих %d, рисуются %d" % [ws.size(), drawn])
	var sm = main.selection_manager
	sm.select_units(ws)
	await _frames(4)
	var rings = GameManager.sel_decals._rings
	var ok_r: bool = rings == null or (is_instance_valid(rings.mmi) and main.is_ancestor_of(rings.mmi))
	verdict("R%d.2 слой колец выделения в новой сцене" % round_i, ok_r)
	var hl = GameManager.hp_bars._layer
	var ok_h: bool = hl == null or (is_instance_valid(hl.mmi) and main.is_ancestor_of(hl.mmi))
	verdict("R%d.3 слой полосок здоровья в новой сцене" % round_i, ok_h)

func _run() -> void:
	var main: Node = null
	for r in range(1, 4):
		main = load("res://scenes/Main.tscn").instantiate()
		get_tree().root.add_child(main)
		await _frames(30)
		await _check(r, main)
		# Выгрузка сцены — тем же порядком, что change_scene: узел уходит из
		# дерева и освобождается, автозагрузки живут дальше
		get_tree().root.remove_child(main)
		main.queue_free()
		await _frames(3)
	_finish()
