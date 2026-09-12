extends Node

## ═══════════════════════════════════════════════════════════════════════════
## ЗОНД: ДЛИННЫЙ ПРОГОН ПАРТИИ БЕЗ ИГРОКА (спринт 17)
## ═══════════════════════════════════════════════════════════════════════════
## Жалоба: «на 4:30-5:00 партия выдаёт Победу и закрывается». Зонд поднимает
## живую сцену Main (ИИ людей, орда, туман, HUD) и гонит её ускоренным
## временем до SMOKE_MIN минут игрового времени, печатая раз в минуту фазы
## обоих ИИ и численность сторон. Вердикт один: до срока конец партии не
## наступил (ни «Победа», ни «Поражение»). Игрок ничего не делает — его пять
## рабочих стоят; поражение по правилу «ни построек, ни бойцов» возможно,
## только если орда их вырежет, и это тоже сигнал: ранняя игра обязана быть
## мирной.
## Ускорение: time_scale × TICKS_MULT при physics_ticks_per_second × TICKS_MULT
## — дельта физического тика остаётся 1/60, ходов в секунду стены больше.
## Запуск: godot --headless --path . res://qa_ai_loop/Smoke.tscn [-- minutes=N]

const TICKS_MULT := 4
var SMOKE_MIN := 40.0

var main = null
var _last_min: int = -1
var _done := false
var _fail: int = 0
var _pass: int = 0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("minutes="):
			SMOKE_MIN = float(s.substr(8))
	call_deferred("_run")
	get_tree().create_timer(3000.0).timeout.connect(func():
		print("  СТОРОЖ: зонд не завершился")
		_finish())

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + d) if d != "" else ""])

func _finish() -> void:
	if _done:
		return
	_done = true
	print("\n═════ ИТОГ qa_ai_loop/Smoke: прошло %d, провалов: %d ═════" % [_pass, _fail])
	get_tree().quit()

func _count(group: String) -> int:
	var n := 0
	for u in get_tree().get_nodes_in_group(group):
		if is_instance_valid(u) and u is Unit and not (u as Unit).is_dead():
			n += 1
	return n

func _bld(group: String) -> int:
	var n := 0
	for b in get_tree().get_nodes_in_group(group):
		if is_instance_valid(b) and b is Building and not (b as Building).is_dead():
			n += 1
	return n

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	for _i in range(8):
		await get_tree().process_frame
	Engine.physics_ticks_per_second = 60 * TICKS_MULT
	Engine.max_physics_steps_per_frame = 8 * TICKS_MULT
	Engine.time_scale = float(TICKS_MULT)
	print("  зонд: %.0f минут игрового времени, ускорение ×%d" % [SMOKE_MIN, TICKS_MULT])

func _process(_delta: float) -> void:
	if main == null or _done:
		return
	var clock: float = float(main._match_clock)
	var m: int = int(clock / 60.0)
	var ph: int = int(main._phase)
	if ph == main.Phase.VICTORY or ph == main.Phase.DEFEAT:
		var what: String = "ПОБЕДА" if ph == main.Phase.VICTORY else "ПОРАЖЕНИЕ"
		print("  КОНЕЦ ПАРТИИ: %s на %d:%02d" % [what, m, int(clock) % 60])
		verdict("S1 партия не кончается до %.0f-й минуты" % SMOKE_MIN, false,
			"%s на %.0f с" % [what, clock])
		_finish()
		return
	if m != _last_min:
		_last_min = m
		var gai = main.goblin_ai
		var eai = main.enemy_ai
		var gs: String = ""
		if gai != null:
			gs = "орда: фаза=%s отр=%d рейдов=%d/отх=%d вылазок=%d/укус=%d баз=%d" % [
				String(gai.phase), gai.squads.size(), gai.raids_launched, gai.raid_retreats,
				gai.scout_sorties, gai.scout_harasses, gai.known_bases.size()]
		var es: String = ""
		if eai != null:
			es = "ИИ: отр=%d башен=%d рудн=%d рейдов=%d/отх=%d" % [
				eai.squads.size(), eai._towers_count(), eai.mines_captured,
				eai.raids_launched, eai.raid_retreats]
		print("  [%2d мин] игрок: %d б/%d зд · ИИ: %d б/%d зд · орда: %d б · %s · %s" % [
			m, _count("player_units"), _bld("player_buildings"),
			_count("enemy_units"), _bld("enemy_buildings"), _count("goblin_units"), gs, es])
	if clock >= SMOKE_MIN * 60.0:
		verdict("S1 партия не кончается до %.0f-й минуты" % SMOKE_MIN, true,
			"фаза сцены %d" % ph)
		var eai2 = main.enemy_ai
		if eai2 != null:
			verdict("S2 у ИИ людей есть крепость и живые", _bld("enemy_buildings") > 0 and _count("enemy_units") > 0,
				"зданий %d, бойцов %d" % [_bld("enemy_buildings"), _count("enemy_units")])
		var gai2 = main.goblin_ai
		if gai2 != null:
			verdict("S3 орда жива", _count("goblin_units") > 0)
		_finish()
