extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_panic_edge — БЕГЛЕЦЫ НЕ ЗАБИВАЮТСЯ В КРАЙ КАРТЫ
## ═══════════════════════════════════════════════════════════════════════════
## Жалоба владельца со скриншотом: в эндшпиле деморализованные отряды уходят
## к правому краю карты и стоят там плотной колонной, упёршись в границу.
##
## Причина: точка бегства зажимается границей мира (`land_target` →
## `clamp_to_map`), и отряд, чей вектор бегства смотрит наружу, получал точку
## РОВНО НА КРОМКЕ — ВЕСЬ, до последнего бойца. Дальше туда же его возвращал
## подзыв связности (`_panic_regroup`).
##
##   A  У КРАЯ — беглецы держатся от кромки и расходятся ВДОЛЬ неё
##   B  В УГЛУ — уходят по той стороне, до которой дальше, а не в сам угол
##   C  КОНУС — разбег идёт веером ±PANIC_CONE_DEG от вектора «от угрозы»,
##      а не полным кругом (половина отряда бежала навстречу своей же половине)
##   D  СРОК — ступор сокращён на 30 %
##
## Запуск: <godot> --headless --path . res://qa_panic_edge/Test.tscn

const _UCfg := preload("res://scripts/unit_stats_config.gd")

const MEN := 24
const SPEAR := "res://scenes/units/Spearman.tscn"
const FOE := "res://scenes/units/GoblinSpearman.tscn"

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	var t := get_tree().create_timer(420.0)
	t.timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 420 с")
		_finish())

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
	print("\n═════ ИТОГ qa_panic_edge: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _spawn(scene: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = load(scene).instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x,
		GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	return u

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	for _i in range(8):
		await get_tree().process_frame
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	await pframes(4)
	print("\n═════ qa_panic_edge ═════")
	print("  границы мира: ±%.1f по X, ±%.1f по Z; запас беглеца %.1f м" % [
		GameManager.map_lim_x, GameManager.map_lim_z, _UCfg.PANIC_EDGE_MARGIN])
	await _a_edge()
	await _b_corner()
	await _c_cone()
	_d_timing()
	_finish()

## Отряд у края, угроза ИЗНУТРИ карты — то есть бежать ему «наружу».
## Возвращает [самое близкое расстояние до кромки, разброс вдоль кромки]
func _panic_at(spot: Vector3, threat_off: Vector3) -> Array:
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
	var men: Array = []
	for k in range(MEN):
		var u := _spawn(SPEAR, Constants.FACTION_PLAYER,
			spot + Vector3(float(k % 6) * 0.8, 0.0, float(k / 6) * 0.8))
		GameManager.add_to_squad(sid, u)
		men.append(u)
	# Угроза: живой противник, от которого и считается вектор бегства
	var foe := _spawn(FOE, Constants.FACTION_GOBLIN, spot + threat_off)
	foe.max_health = 1e9
	foe.current_health = 1e9
	await pframes(30)
	# Срываем отряд принудительно — стенд про ВЕКТОР бегства, а не про мораль
	GameManager.squads[sid]["morale"] = 1.0
	GameManager._start_panic(sid)
	await pframes(60 * 8)
	var near: float = INF
	var lo := INF
	var hi := -INF
	var n := 0
	for m in men:
		var u := m as Unit
		if u == null or not is_instance_valid(u) or u.is_dead():
			continue
		var p: Vector3 = u.global_position
		near = minf(near, minf(GameManager.map_lim_x - absf(p.x),
			GameManager.map_lim_z - absf(p.z)))
		# Разброс вдоль кромки: по той оси, которая НЕ упирается в край
		var along: float = p.z if (GameManager.map_lim_x - absf(p.x)) \
			< (GameManager.map_lim_z - absf(p.z)) else p.x
		lo = minf(lo, along)
		hi = maxf(hi, along)
		n += 1
	for m in men:
		if is_instance_valid(m):
			(m as Unit).take_damage(1e12)
	if is_instance_valid(foe):
		foe.take_damage(1e12)
	await pframes(8)
	return [near, hi - lo, n]

func _a_edge() -> void:
	print("\n═════ A. ОТРЯД У БОКОВОГО КРАЯ ═════")
	var x: float = GameManager.map_lim_x - 12.0
	var spot := Vector3(x, 0.0, 0.0)
	var r: Array = await _panic_at(spot, Vector3(-14.0, 0.0, 0.0))
	print("  ближайший к кромке: %.1f м; разброс вдоль кромки %.1f м (живых %d)" % [
		float(r[0]), float(r[1]), int(r[2])])
	verdict("A1 беглецы не впечатаны в кромку карты",
		float(r[0]) >= 2.0, "ближайший в %.1f м от края" % float(r[0]))
	verdict("A2 отряд расходится вдоль края, а не стоит колонной в одной точке",
		float(r[1]) >= 4.0, "разброс %.1f м" % float(r[1]))

func _b_corner() -> void:
	print("\n═════ B. ОТРЯД В УГЛУ КАРТЫ ═════")
	var spot := Vector3(GameManager.map_lim_x - 10.0, 0.0,
		GameManager.map_lim_z - 10.0)
	# Угроза со стороны центра карты: «от неё» = ровно в угол
	var r: Array = await _panic_at(spot, Vector3(-12.0, 0.0, -12.0))
	print("  ближайший к кромке: %.1f м; разброс %.1f м (живых %d)" % [
		float(r[0]), float(r[1]), int(r[2])])
	verdict("B1 в углу беглецы не сбиваются в саму вершину",
		float(r[0]) >= 2.0, "ближайший в %.1f м от края" % float(r[0]))

func _c_cone() -> void:
	print("\n═════ C. КОНУС РАЗБЕГА ═════")
	# Открытое поле: тут край ни при чём, проверяется форма веера
	var spot := Vector3(0.0, 0.0, 40.0)
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
	var men: Array = []
	for k in range(MEN):
		var u := _spawn(SPEAR, Constants.FACTION_PLAYER,
			spot + Vector3(float(k % 6) * 0.8, 0.0, float(k / 6) * 0.8))
		GameManager.add_to_squad(sid, u)
		men.append(u)
	var foe := _spawn(FOE, Constants.FACTION_GOBLIN, spot + Vector3(0.0, 0.0, -14.0))
	foe.max_health = 1e9
	foe.current_health = 1e9
	await pframes(30)
	var c0: Vector2 = GameManager.squad_centre_xz(sid)
	GameManager.squads[sid]["morale"] = 1.0
	GameManager._start_panic(sid)
	await pframes(60 * 7)
	# Ось бегства — от угрозы к центру отряда ДО срыва
	var axis := Vector2(c0.x - foe.global_position.x, c0.y - foe.global_position.z)
	if axis.length() < 0.01:
		axis = Vector2(0.0, 1.0)
	axis = axis.normalized()
	var worst := 0.0
	var behind := 0
	var n := 0
	var in_cone := 0
	var fled := 0
	var near_d := INF
	var far_d := 0.0
	for m in men:
		var u := m as Unit
		if u == null or not is_instance_valid(u) or u.is_dead():
			continue
		var d := Vector2(u.global_position.x - c0.x, u.global_position.z - c0.y)
		near_d = minf(near_d, d.length())
		far_d = maxf(far_d, d.length())
		# ── УГОЛ ЕСТЬ ТОЛЬКО У ТОГО, КТО РЕАЛЬНО УБЕЖАЛ ────────────────────
		# Первые две версии брали сдвинувшихся на 1 и на 3 метра — а столько
		# бойцу даёт и разбор наложения в куче. У почти не сдвинувшегося
		# направления нет вовсе, и он давал «отклонение 84°» на исправном
		# веере: точка бегства лежит в двадцати метрах, и мерить направление
		# по трёхметровому сдвигу бессмысленно
		if d.length() < _UCfg.PANIC_FLEE_DIST * 0.5:
			continue
		fled += 1
		var a: float = rad_to_deg(absf(axis.angle_to(d.normalized())))
		worst = maxf(worst, a)
		if a <= _UCfg.PANIC_CONE_DEG + 20.0:
			in_cone += 1
		if a > 90.0:
			behind += 1
		n += 1
	print("  сдвиг: ближний %.1f м, дальний %.1f м; убежало (>%.0f м) %d из %d" % [
		near_d, far_d, _UCfg.PANIC_FLEE_DIST * 0.5, fled, men.size()])
	verdict("C1 никто не бежит НАВСТРЕЧУ угрозе",
		behind == 0, "против оси пошли %d из %d" % [behind, n])
	# Запас к конусу — угловой размер круга связности на дальности бегства:
	# atan(PANIC_SPREAD / PANIC_FLEE_DIST) плюс поправка на толчею
	verdict("C2 подавляющее большинство убежавших — внутри конуса",
		fled > 0 and float(in_cone) >= float(fled) * 0.8,
		"в конусе ±%.0f° — %d из %d убежавших, худший %.0f°" % [
			_UCfg.PANIC_CONE_DEG + 20.0, in_cone, fled, worst])
	for m in men:
		if is_instance_valid(m):
			(m as Unit).take_damage(1e12)
	if is_instance_valid(foe):
		foe.take_damage(1e12)
	await pframes(8)

func _d_timing() -> void:
	print("\n═════ D. СРОК СТУПОРА ═════")
	verdict("D1 ступор сокращён примерно на 30 % (было 20 с)",
		absf(_UCfg.PANIC_STUN_SEC - 14.0) < 0.01,
		"%.1f с" % _UCfg.PANIC_STUN_SEC)
	verdict("D2 мораль гнолла поднята — стая не в вечном ужасе",
		_UCfg.stat("gnoll", "morale", 0.0) >= 50.0,
		"мораль %.0f" % _UCfg.stat("gnoll", "morale", 0.0))
