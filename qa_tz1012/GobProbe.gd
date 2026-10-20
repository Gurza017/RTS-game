extends Node
## Зонд экономики орды (ТЗ 12.10.2026, второе письмо, блок 2): живая партия
## ×4, раз в игровую минуту — еда, приход/расход, отряды на площадке, план,
## готовые волны, волны в поле, выпущено всего, последнее действие.
## Запуск: godot --headless --path . res://qa_tz1012/GobProbe.tscn [-- minutes=40]
var main = null
var _min := 40.0
var _next := 0.0
var _launch_t: Array = []
var _last_launched := 0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("minutes="):
			_min = float(s.substr(8))
	call_deferred("_run")

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	for _i in range(8):
		await get_tree().process_frame
	Engine.physics_ticks_per_second = 240
	Engine.max_physics_steps_per_frame = 32
	Engine.time_scale = 4.0

func _process(_d: float) -> void:
	if main == null:
		return
	var g = main.goblin_ai
	if g == null:
		return
	var t: float = float(g.clock)
	if int(g.waves_launched) > _last_launched:
		_last_launched = int(g.waves_launched)
		_launch_t.append(snappedf(t / 60.0, 0.1))
	if t < _next:
		return
	_next = t + 60.0
	var food: float = ResourceManager.get_amount(Constants.FACTION_GOBLIN, Constants.RESOURCE_FOOD)
	var plan: String = String((g._plan as Dictionary).get("tpl", "-")) if not (g._plan as Dictionary).is_empty() else "-"
	print("  мин %4.1f еда %5.0f (+%.0f −%.0f/мин) поле %d площадка %d план %s готово %d в поле %d выпущено %d | %s" % [
		t / 60.0, food, float(g.income_min), float(g.upkeep_min), int(g.field_units), (g.muster as Dictionary).size(),
		plan, (g._ready_q as Array).size(), (g.waves as Array).size(), int(g.waves_launched), String(g.last_action)])
	if t >= _min * 60.0:
		print("  ВЫХОДЫ ВОЛН (мин): %s" % str(_launch_t))
		get_tree().quit()
