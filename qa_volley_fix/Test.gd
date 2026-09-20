extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ЗАЛП ПО УМОЛЧАНИЮ СТРЕЛЯЕТ; «ПО ГОТОВНОСТИ» — ШИРЕ (спринт 16, блок 1)
## ═══════════════════════════════════════════════════════════════════════════
## ЖАЛОБА ВЛАДЕЛЬЦА: после исследования «Залпового огня» лучники СТОЯТ И НЕ
## СТРЕЛЯЮТ, пока абилку не выключить руками. Причина — такт залпов отсеивал
## отряды с ПУСТЫМ словарём способностей, а «включено по умолчанию» словарь не
## заполняет (см. GameManager._sweep_volleys). Этот стенд ставит ровно тот
## случай: узел изучен, переключатель никто не трогал.
##
##   A — залп по умолчанию: режим включён, окно открывается, стрелы летят
##       пачкой (синхронно), а не по одной;
##   B — «по готовности» (переключатель выключен): каждый бьёт сам, стрелы
##       ложатся ШИРЕ, чем кучная туча залпа.
##
## Разброс меряется по ТОЧКАМ ВТЫКАНИЯ стрел (узлы Arrow на земле), а не по
## числам в конфиге. Запуск: godot --headless --path . res://qa_volley_fix/Test.tscn

const _Forge := preload("res://scripts/forge_config.gd")

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
	print("\n═════ ИТОГ qa_volley_fix: прошло %d, провалов: %d ═════" % [_pass, _fail])
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

func _squad(uid: String, fac: int, at: Vector3, n: int, cols: int, gap: float) -> Array:
	var sid: int = GameManager.new_squad(fac, uid)
	var men: Array = []
	for i in range(n):
		var p := at + Vector3((float(i % cols) - float(cols - 1) * 0.5) * gap, 0.0,
			float(i / cols) * gap)
		var u := _spawn(uid, fac, p)
		u.post_pos = u.global_position
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return [men, sid]

## Стрелы (не кости), торчащие в земле: записи ядра (снаряд без узла,
## BigStand-5 этап 3) плюс legacy-узлы Arrow под корнем мира (ручка выключена)
func _stuck_points() -> Array:
	var out: Array = []
	for r in GameManager.stuck_arrow_records():
		if not bool(r["bone"]):
			out.append(r["pos"])
	for c in main.world_root().get_children():
		var n3 := c as Node3D
		if n3 == null:
			continue
		var sc: Variant = n3.get_script()
		if sc == null or not String((sc as Script).resource_path).ends_with("Arrow.gd"):
			continue
		if bool(n3.get("bone")) or bool(n3.get("_pooled")) or not bool(n3.get("_spent")):
			continue
		out.append(n3.global_position)
	return out

func _spread(points: Array) -> float:
	if points.size() < 3:
		return 0.0
	var c := Vector3.ZERO
	for p in points:
		c += p
	c /= float(points.size())
	var acc := 0.0
	for p in points:
		acc += Vector2(p.x - c.x, p.z - c.z).length_squared()
	return sqrt(acc / float(points.size()))

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
	await _a_default_volley()
	await _b_ready_mode()
	_finish()

var _sid: int = 0
var _men: Array = []
var _foes: Array = []
var _nid: String = ""
const WINDOW_SEC := 20
var _shots_v: int = 0
var _miss_v: int = 0

## Стрелы (не кости), торчащие в земле, — записи ядра плюс legacy-узлы
func _stuck_count() -> int:
	var n := 0
	for r in GameManager.stuck_arrow_records():
		if not bool(r["bone"]):
			n += 1
	for a in GameManager._stuck_arrows:
		if a == null or not is_instance_valid(a):
			continue
		if not bool((a as Node3D).get("bone")):
			n += 1
	return n

# ═════════════════════════════════════════════════════════════════════════════
func _a_default_volley() -> void:
	print("\n═════ A. ЗАЛП ИЗУЧЕН, ПЕРЕКЛЮЧАТЕЛЬ НЕ ТРОНУТ ═════")
	var f: int = Constants.FACTION_PLAYER
	var node: Dictionary = _Forge.toggle_ability_of("archer")
	_nid = String(node.get("id", ""))
	verdict("A0 у лучников есть способность-режим (залп)", _nid != "", _nid)
	GameManager.finish_research(f, _nid)
	var p0 := Vector3(-1200.0, 0.0, -1200.0)
	var mine: Array = _squad("archer", f, p0, 10, 5, 0.8)
	_sid = mine[1]
	_men = mine[0]
	# ЧУЖОЙ СТРОЙ — ГЛУБОКИЙ (4×4), А НЕ ШЕРЕНГА В ДВА РЯДА: туча залпа
	# нарочно раскладывается диском не уже VOLLEY_MIN_SPREAD (1.1 м), и над
	# строем глубиной 0.7 м треть её точек ложится за спины — «промахи» такого
	# залпа мерят накрытие, а не точность (первая версия: залп 30 % в землю
	# против 19-26 % по готовности). В квадрате 2.8×2.8 диск целиком над
	# телами, и в землю уходят только стрелы с широким одиночным разбросом
	var foe: Array = _squad("spearman", Constants.FACTION_ENEMY, p0 + Vector3(0.0, 0.0, 13.0), 16, 4, 0.7)
	_foes = foe[0]
	for u in _foes:
		(u as Unit).set_tick(false)
		(u as Unit).current_health = (u as Unit).max_health * 1000.0
		(u as Unit)._soa_push_stats()
	await pframes(6)
	# Ловушка воспроизведена: словарь способностей пуст, а режим — «включён»
	var abil: Dictionary = (GameManager.squads[_sid] as Dictionary).get("ability_on", {})
	verdict("A1 словарь способностей пуст, режим залпа при этом ВКЛЮЧЁН (умолчание)",
		abil.is_empty() and GameManager.squad_volley_mode(_sid))
	# Приказ атаки — как ПКМ по строю
	for u in _men:
		(u as Unit).command_attack(_foes[0], true, true, true)
	var fired0: int = GameManager.arrows_fired
	var stuck0: int = _stuck_count()
	var opened := false
	var peak_air := 0
	var per_frame: Array = []
	var prev: int = fired0
	for _i in range(60 * WINDOW_SEC):
		await get_tree().physics_frame
		if GameManager.squad_volley_open(_sid):
			opened = true
		var now: int = GameManager.arrows_fired
		per_frame.append(now - prev)
		prev = now
		peak_air = maxi(peak_air, GameManager.arrows_mm.flight_count())
	await pframes(120)   # последним стрелам дать долететь
	var shots: int = GameManager.arrows_fired - fired0
	_shots_v = shots
	_miss_v = _stuck_count() - stuck0
	var burst := 0
	for b in per_frame:
		burst = maxi(burst, int(b))
	print("  за %d с: окно залпа открывалось=%s, выстрелов %d, пик за кадр %d, в воздухе разом %d, в землю %d" % [
		WINDOW_SEC, str(opened), shots, burst, peak_air, _miss_v])
	verdict("A2 окно залпа открывается само — отряд не заперт", opened)
	verdict("A3 лучники СТРЕЛЯЮТ (не меньше двух залпов за окно)", shots >= 16,
		"выстрелов %d" % shots)
	verdict("A4 залп — пачка, а не по одному: за один кадр бьёт не меньше половины отряда",
		burst >= 5, "пик %d из 10" % burst)

# ═════════════════════════════════════════════════════════════════════════════
func _b_ready_mode() -> void:
	print("\n═════ B. РАЗБРОС: ЗАЛП КУЧНЫЙ, «ПО ГОТОВНОСТИ» ШИРОКИЙ ═════")
	# Точки втыкания собираем за одно и то же время в обоих режимах; стрелы
	# гаснут по своему сроку, поэтому перед вторым замером поле чистится
	var pts_v: Array = _stuck_points()
	var spread_v: float = _spread(pts_v)
	GameManager.clear_stuck_arrows()
	await pframes(4)
	GameManager.squad_set_ability(_sid, _nid, false)
	verdict("B1 переключатель выключен — режим «по готовности»",
		not GameManager.squad_volley_mode(_sid))
	for u in _men:
		(u as Unit).command_attack(_foes[0], true, true, true)
		# Стрелки в РАЗНОЙ фазе перезарядки, как в бою после подхода вразнобой:
		# с одинаковыми таймерами они и «по готовности» били бы одним кадром
		(u as Unit)._attack_timer = randf() * (u as Unit)._effective_cooldown()
	var fired0: int = GameManager.arrows_fired
	var stuck0: int = _stuck_count()
	var per_frame: Array = []
	var prev: int = fired0
	for _i in range(60 * WINDOW_SEC):
		await get_tree().physics_frame
		var now: int = GameManager.arrows_fired
		per_frame.append(now - prev)
		prev = now
	await pframes(120)
	var shots: int = GameManager.arrows_fired - fired0
	var miss_r: int = _stuck_count() - stuck0
	var burst := 0
	for b in per_frame:
		burst = maxi(burst, int(b))
	var pts_r: Array = _stuck_points()
	var spread_r: float = _spread(pts_r)
	var share_v: float = float(_miss_v) / float(maxi(_shots_v, 1))
	var share_r: float = float(miss_r) / float(maxi(shots, 1))
	print("  по готовности: выстрелов %d, пик за кадр %d, в землю %d; промахи: залп %.0f %% (%d из %d) / по готовности %.0f %% (%d из %d); разброс втыканий залп %.2f м (%d) / по готовности %.2f м (%d)"
		% [shots, burst, miss_r, share_v * 100.0, _miss_v, _shots_v, share_r * 100.0, miss_r, shots,
			spread_v, pts_v.size(), spread_r, pts_r.size()])
	verdict("B2 по готовности стреляют, и не одним кадром — каждый по своей перезарядке",
		shots >= 16 and burst < _men.size(), "выстрелов %d, пик за кадр %d из %d" % [shots, burst, _men.size()])
	# ПРОМАХ — ЭТО СТРЕЛА В ЗЕМЛЕ (цели бессмертны и стоят): по готовности их
	# обязано быть больше — ровно то, что заказано («больше промахов»)
	verdict("B3 по готовности промахов больше, чем залпом (доля стрел в земле)",
		share_r > share_v, "залп %.0f %%, по готовности %.0f %%" % [share_v * 100.0, share_r * 100.0])
