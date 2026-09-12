extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ГНОЛЛ — ПАТРУЛЬ, АГРО ПО УРОНУ, НАСКОК-БРОСОК-ОТХОД, УКРЫТИЕ В ПНЕ
## (спринт 16, блок 4)
## ═══════════════════════════════════════════════════════════════════════════
## ЗАКАЗ ВЛАДЕЛЬЦА: «гноллы не атакуют, а просто бегают». Логика:
##   1. изначально патрулируют;
##   2. получили урон — агрятся на стрелка/ближайшего: подбегают, метают, отходят;
##   3. мало запаса — бегут к ближайшему пню, прячутся внутри, лечатся, выходят.
##
## Числа — из goblin_config (правило 10), ожидание — физкадрами (правило 11).
## Запуск: godot --headless --path . res://qa_gnoll_behavior/Test.tscn

const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")
const _Lair := preload("res://scripts/goblin/TrollLair.gd")

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	var t := get_tree().create_timer(240.0)
	t.timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 240 с")
		_finish())

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
	print("\n═════ ИТОГ qa_gnoll_behavior: прошло %d, провалов: %d ═════"
		% [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _spawn(uid: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[uid].instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	return u

func _xz(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

var _lair = null
var _g: Unit = null
var _archer: Unit = null

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	GameManager.world_bounds_enabled = false
	await pframes(4)
	await _a_patrol()
	await _b_aggro()
	await _c_hide()
	await _d_lair_dies()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
func _a_patrol() -> void:
	print("\n═════ A. ПАТРУЛЬ ═════")
	var p0 := Vector3(-1200.0, 0.0, -1200.0)
	_lair = _Lair.new()
	_lair.faction = Constants.FACTION_GOBLIN
	main.world_add(_lair)
	_lair.global_position = Vector3(p0.x, GameManager.get_terrain_height(p0.x, p0.z), p0.z)
	await pframes(4)
	# Свою стаю логово заводит само; она нам не нужна — уводим её с площадки
	for raw in _lair.gnolls.duplicate():
		if raw != null and is_instance_valid(raw):
			(raw as Unit).take_damage(1e9)
	await pframes(3)
	_g = _spawn("gnoll", Constants.FACTION_GOBLIN, p0 + Vector3(8.0, 0.0, 0.0))
	_g.set("lair", _lair)
	await pframes(4)
	var start: Vector3 = _g.global_position
	var far := 0.0
	for _i in range(60 * 9):
		await get_tree().physics_frame
		far = maxf(far, _xz(_g.global_position, start))
	verdict("A1 без врагов гнолл патрулирует — ходит вокруг пня", far > 1.5,
		"ушёл на %.1f м" % far)
	verdict("A2 и никого не бьёт", int(_g.get("bones_thrown")) == 0 and _g.attack_target == null)

# ═════════════════════════════════════════════════════════════════════════════
func _b_aggro() -> void:
	print("\n═════ B. УЖАЛИЛИ — НАСКОК, БРОСОК, ОТХОД ═════")
	# Стрелок стоит дальше броска, но в пределах поводка, и ЗАМОРОЖЕН: бьёт
	# его стенд (take_damage от его имени), чтобы не зависеть от прицела
	var at: Vector3 = _lair.global_position + Vector3(20.0, 0.0, 3.0)
	_archer = _spawn("archer", Constants.FACTION_PLAYER, at)
	_archer.set_tick(false)
	_archer.current_health = _archer.max_health * 50.0
	await pframes(4)
	var thrown0: int = int(_g.get("bones_thrown"))
	_g.take_damage(3.0, _archer)
	await pframes(3)
	# Целью стрелок может стать и раньше укола — патрулирующий гнолл сам
	# подходит к нему на поводок; важно, что ПОСЛЕ укола цель — обидчик
	verdict("B1 ужаленный гнолл берёт обидчика целью",
		_g.attack_target == _archer,
		"цель %s, ответов на укол %d" % [str(_g.attack_target), int(_g.get("aggro_answers"))])
	var thrown := false
	var d_at_throw := 0.0
	for _i in range(60 * 12):
		await get_tree().physics_frame
		if int(_g.get("bones_thrown")) > thrown0:
			thrown = true
			d_at_throw = _xz(_g.global_position, _archer.global_position)
			break
	verdict("B2 подбежал на бросок и метнул кость", thrown,
		"брошено %d, дистанция броска %.1f м" % [int(_g.get("bones_thrown")) - thrown0, d_at_throw])
	if thrown:
		verdict("B2б бросок с дистанции броска, а не с двадцати метров",
			d_at_throw <= _GobCfg.GNOLL_THROW_RANGE + 1.0, "%.1f м" % d_at_throw)
	# Отход меряется ПИКОМ дистанции за окно: отойдя, гнолл вправе тут же
	# пойти на новый наскок, и снимок в конце окна застал бы его на обратном
	# пути (первая версия так и намеряла «было 7.1, стало 6.9»)
	var d_far: float = d_at_throw
	for _i in range(150):
		await get_tree().physics_frame
		d_far = maxf(d_far, _xz(_g.global_position, _archer.global_position))
	verdict("B3 после броска отошёл (дальше от стрелка, чем в миг броска)",
		int(_g.get("run_backs")) >= 1 and d_far > d_at_throw + 1.0,
		"было %.1f, отходил до %.1f м, отходов %d" % [d_at_throw, d_far, int(_g.get("run_backs"))])
	# Второй укол — второй наскок
	var thrown1: int = int(_g.get("bones_thrown"))
	_g.take_damage(3.0, _archer)
	var again := false
	for _i in range(60 * 12):
		await get_tree().physics_frame
		if int(_g.get("bones_thrown")) > thrown1:
			again = true
			break
	verdict("B4 новый укол — новый наскок и бросок", again)

# ═════════════════════════════════════════════════════════════════════════════
func _c_hide() -> void:
	print("\n═════ C. МАЛО ЗАПАСА — В ПЕНЬ, ЛЕЧИТЬСЯ, ОБРАТНО ═════")
	# Просаживаем до порога укрытия одним ударом стрелка
	var want: float = _g.max_health * (_GobCfg.GNOLL_HIDE_HP - 0.08)
	_g.current_health = want + 1.0
	_g._soa_push_stats()
	_g.take_damage(1.0, _archer)
	# броня режет урон долей: дожимаем поле, если удар прошёл слабее порога
	if _g.current_health >= _g.max_health * _GobCfg.GNOLL_HIDE_HP:
		_g.current_health = want
		_g._soa_push_stats()
		_g.take_damage(0.5, _archer)
	await pframes(2)
	verdict("C1 ниже порога запаса гнолл бежит к пню", bool(_g.get("hiding_to_lair")),
		"запас %.0f из %.0f, бежит=%s" % [_g.current_health, _g.max_health,
			str(_g.get("hiding_to_lair"))])
	var hid := false
	for _i in range(60 * 25):
		await get_tree().physics_frame
		if bool(_g.get("hidden")):
			hid = true
			break
	verdict("C2 добежал и спрятался внутри пня", hid and _lair.hidden_gnolls() == 1,
		"внутри %d" % _lair.hidden_gnolls())
	if hid:
		verdict("C2б спрятанного нет на карте: невидим, не в группе, не тикает",
			not _g.visible and not _g.is_in_group(Constants.unit_group(_g.faction))
			and not _g.tick_on)
	var hp_in: float = _g.current_health
	var out := false
	for _i in range(60 * 20):
		await get_tree().physics_frame
		if not bool(_g.get("hidden")):
			out = true
			break
	verdict("C3 внутри лечится и на полном запасе выходит", out
		and _g.current_health >= _g.max_health - 0.5,
		"вошёл с %.0f, вышел с %.0f из %.0f; вышло всего %d" % [hp_in, _g.current_health,
			_g.max_health, int(_lair.get("released_total"))])
	verdict("C4 вышедший снова на карте: виден, в группе, тикает",
		_g.visible and _g.is_in_group(Constants.unit_group(_g.faction)) and _g.tick_on)

# ═════════════════════════════════════════════════════════════════════════════
func _d_lair_dies() -> void:
	print("\n═════ D. ПЕНЬ СНЕСЛИ, ПОКА ГНОЛЛ ВНУТРИ ═════")
	_g.current_health = _g.max_health * 0.3
	_g._soa_push_stats()
	_g.take_damage(0.5, _archer)
	var hid := false
	for _i in range(60 * 25):
		await get_tree().physics_frame
		if bool(_g.get("hidden")):
			hid = true
			break
	verdict("D1 снова спрятался", hid)
	_lair.take_damage(1e9)
	await pframes(4)
	verdict("D2 пень снесён — укрывшийся выходит наружу и не теряется",
		not bool(_g.get("hidden")) and _g.visible and _g.tick_on and not _g.is_dead(),
		"скрыт=%s, виден=%s" % [str(_g.get("hidden")), str(_g.visible)])
	if is_instance_valid(_g):
		_g.take_damage(1e9)
	if is_instance_valid(_archer):
		_archer.take_damage(1e9)
	await pframes(2)
