extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_army/MatrixLive — А ВКЛЮЧАЕТСЯ ЛИ МАТРИЦА ВООБЩЕ
## ═══════════════════════════════════════════════════════════════════════════
## Замер скорости бессмыслен, пока не известно, СРАБАТЫВАЕТ ли оптимизация в
## измеряемой сцене. Матрица отказывается вести отряд, если в его коридоре есть
## стволы или чужие, — а марш в qa_mass_perf идёт по лесистой середине карты.
##
## Стенд гоняет марш и считает ДОЛЮ отрядо-кадров, проведённых на матрице:
##   доля близка к 1 — оптимизация работает, разницу во времени можно верить;
##   доля близка к 0 — она не включалась, и любой замер говорит не о ней.
##
## Печатает долю в чистом поле и в лесу отдельно: это разные ответы.
##
## Запуск: godot --headless --path . res://qa_army/MatrixLive.tscn

const _Opt := preload("res://scripts/perf_config.gd")

const SQUAD_SIZE := 20
const COLS := 5
const GAP := 0.9
const SQUADS := 12

var main = null
var _units: Array = []
var _squads: Array = []
var _fail := 0
var _checks := 0

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func ok(name: String, cond: bool, detail: String = "") -> void:
	_checks += 1
	if not cond:
		_fail += 1
	print("  [%s] %s%s" % ["OK " if cond else "НЕ ПРОШЛО", name,
		("  — " + detail) if detail != "" else ""])

func _spawn(at: Vector3) -> void:
	for s in range(SQUADS):
		var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
		_squads.append(sid)
		var bx: float = at.x + float(s % 4) * (float(COLS) * GAP + 3.0)
		var bz: float = at.z + float(s / 4) * (5.0 * GAP + 3.0)
		for i in range(SQUAD_SIZE):
			var u: Unit = Spearman.new()
			u.faction = Constants.FACTION_PLAYER
			main.world_add(u)
			u.global_position = Vector3(bx + float(i % COLS) * GAP, 0.0,
				bz + float(i / COLS) * GAP)
			u.max_health = 1e9
			u.current_health = 1e9
			GameManager.add_to_squad(sid, u)
			_units.append(u)

func _clear() -> void:
	# СНАЧАЛА ВЫВЕСТИ ИЗ ОТРЯДА, ПОТОМ ОСВОБОЖДАТЬ. Голый queue_free оставляет
	# в составе отряда ссылку на уже снесённый узел, и следующий обход состава
	# падает на «Trying to cast a freed object». В игре так не бывает — смерть
	# идёт через remove_from_squad, — но стенд сносит армию мимо этого пути
	for u in _units:
		if is_instance_valid(u):
			GameManager.remove_from_squad(u as Unit)
	for u in _units:
		if is_instance_valid(u):
			(u as Node).queue_free()
	_units.clear()
	_squads.clear()
	await frames(8)

## Марш и доля отрядо-кадров на матрице
func _march_share(offset: Vector3, steps: int) -> float:
	for sid in _squads:
		for m in GameManager.squad_members(int(sid)):
			var u := m as Unit
			if u != null:
				u.command_move(u.global_position + offset)
	var on := 0
	var total := 0
	var why := {}                       # почему отряд не попал в матрицу
	for _i in range(steps):
		await get_tree().physics_frame
		on += GameManager.matrix_squads()
		total += _squads.size()
		if GameManager.matrix_squads() == 0 and _i % 15 == 0:
			var r: String = _refusal(int(_squads[0]))
			why[r] = int(why.get(r, 0)) + 1
	if not why.is_empty():
		print("    причины отказа (по первому отряду): %s" % str(why))
	return float(on) / maxf(float(total), 1.0)

## Разбор отказа: те же условия, что и в GameManager._matrix_allowed
func _refusal(sid: int) -> String:
	var members: Array = GameManager.squad_members(sid)
	if members.size() < _Opt.squad_matrix_min:
		return "отряд мал (%d)" % members.size()
	var corr: Variant = GameManager._corridors.get(sid)
	if corr == null:
		return "коридор не посчитан"
	var r: Array = corr
	if not bool(r[1]):
		return "в коридоре стволы"
	if not bool(r[2]):
		return "в коридоре чужие"
	for m in members:
		if not is_instance_valid(m):
			return "в составе снесённый узел"
		var u := m as Unit
		if u.state != Unit.State.MOVING:
			return "не в марше (состояние %d)" % u.state
		if u.attack_target != null:
			return "есть цель атаки"
		if u._soa < 0:
			return "нет строки в ядре"
	return "условия выполнены (матрица должна была включиться)"

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(6)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	await frames(3)

	print("\n───── ВКЛЮЧАТЕЛЬ ─────")
	print("  _Opt.squad_matrix = %s, порог отряда %d"
		% [str(_Opt.squad_matrix), _Opt.squad_matrix_min])
	if not _Opt.squad_matrix:
		print("  ФЛАГ ВЫКЛЮЧЕН — доля заведомо 0, стенд ничего не измеряет")

	# ЧИСТОЕ ПОЛЕ. Ставим армию туда, где стволов заведомо нет: лес растёт по
	# краям и пятнами, а сюда его не сажают
	print("\n───── A. МАРШ ПО ЧИСТОМУ ПОЛЮ ─────")
	# ИЩЕМ САМОЕ ЧИСТОЕ ПЯТНО НА ВСЕЙ КАРТЕ, а не первое подходящее. Грубый
	# перебор находил «чистое» место через раз, и стенд то мерил матрицу, то
	# нет — при том что интересен как раз потолок: сколько механика даёт ТАМ,
	# ГДЕ ЕЙ НИЧЕГО НЕ МЕШАЕТ. Заодно печатаем, сколько чистых пятен вообще есть
	# на карте: это и есть ответ, часто ли условие выполнимо в реальной игре
	var clear_at := Vector3(0.0, 0.0, 0.0)
	var best_r := -1.0
	var spots_clear := 0
	var spots_total := 0
	for gx in range(-12, 13):
		for gz in range(-7, 8):
			var p := Vector3(float(gx) * 10.0, 0.0, float(gz) * 10.0)
			spots_total += 1
			# Бинарный поиск запаса: до какого радиуса вокруг точки нет стволов
			var r := 0.0
			for probe_r in [26.0, 22.0, 18.0, 14.0, 10.0, 6.0]:
				if not GameManager.trunk_near(p.x, p.z, float(probe_r)):
					r = float(probe_r)
					break
			if r >= 14.0:
				spots_clear += 1
			if r > best_r:
				best_r = r
				clear_at = p
	print("  чистых пятен (радиус ≥14 м без стволов): %d из %d проверенных"
		% [spots_clear, spots_total])
	print("  армия ставится в (%.0f, %.0f), запас до ближайшего ствола %.0f м"
		% [clear_at.x, clear_at.z, best_r])
	_spawn(clear_at)
	await frames(6)
	var share_clear: float = await _march_share(Vector3(0, 0, 26.0), 90)
	print("  доля отрядо-кадров на матрице в поле: %.0f%%" % (share_clear * 100.0))
	await _clear()

	print("\n───── B. МАРШ ПО ЛЕСИСТОЙ СЕРЕДИНЕ (как в qa_mass_perf) ─────")
	_spawn(Vector3(0.0, 0.0, 0.0))
	await frames(6)
	var share_wood: float = await _march_share(Vector3(0, 0, 26.0), 90)
	print("  доля отрядо-кадров на матрице у начала координат: %.0f%%"
		% (share_wood * 100.0))
	await _clear()

	print("\n───── ВЫВОД ─────")
	if _Opt.squad_matrix:
		# Порог низкий НАМЕРЕННО. Стенд отвечает на двоичный вопрос «работает ли
		# механика в измеряемой сцене вообще», а не на «насколько часто»: доля
		# гуляет 43–58 % от прогона к прогону, потому что отряд входит в матрицу
		# не с первого кадра марша и выходит из неё за MATRIX_RELEASE_DIST до
		# цели. Само число — это вывод стенда, а не его вердикт
		ok("A1 в чистом поле матрица действительно ведёт отряды",
			share_clear > 0.25, "доля %.0f%%" % (share_clear * 100.0))
		print("  ЕСЛИ доля в лесу заметно ниже — замер на лесной карте измеряет")
		print("  НЕ матрицу, и сравнивать по нему цену механики нельзя")
	else:
		print("  флаг выключен, вердиктов нет")

	print("\n=== MatrixLive: провалов: %d из %d ===" % [_fail, _checks])
	get_tree().quit(1 if _fail > 0 else 0)
