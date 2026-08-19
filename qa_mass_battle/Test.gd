extends Node

const _OptCfgG = preload("res://scripts/perf_config.gd")

## ═══════════════════════════════════════════════════════════════════════════
## МАСШТАБ В БОЮ: ДВЕ АРМИИ СХОДЯТСЯ И ДЕРУТСЯ
## ═══════════════════════════════════════════════════════════════════════════
## qa_mass_perf меряет МАРШ и врагов не ставит вовсе — ветка process_attack там
## показывает 0.0%. Этот стенд закрывает вторую половину вопроса: во что
## обходится кадр, когда бойцы ищут цели, бьют и получают урон.
##
## Устройство: армия делится пополам, стороны ставятся друг напротив друга и
## получают приказ атаковать. Замеры снимаются ТРИЖДЫ — до сходки (сближение),
## в момент свалки (первые секунды контакта) и в затяжном бою.
##
## ТИХО ПО УМОЛЧАНИЮ, как и остальные массовые стенды: за прогон в терминал не
## уходит ни строки, всё копится и печатается одной таблицей.
##
## Запуск: godot --headless --path . res://qa_mass_battle/Test.tscn
##         ... -- --count=15000        (по умолчанию 5000 и 15000)
##         ... -- --verbose            (разбивка по веткам)

const _OptCfg = preload("res://scripts/perf_config.gd")
const Spearman = preload("res://scripts/Spearman.gd")

const DEFAULT_STEPS := [5000, 15000]
const SQUAD_SIZE := 50
const COLS       := 10
const GAP        := 0.9
const SQUAD_GAP  := 3.0
## Между линиями: сходятся за несколько секунд, но не стоят вплотную с начала
const LINE_GAP   := 34.0
const BUDGET_MS  := 16.6

var main = null
var _units: Array = []
var _rows: Array = []
var _notes: Array = []
var _verbose := false
var _steps: Array = []

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _args() -> PackedStringArray:
	var all := PackedStringArray()
	all.append_array(OS.get_cmdline_args())
	all.append_array(OS.get_cmdline_user_args())
	return all

func _run() -> void:
	_steps = DEFAULT_STEPS.duplicate()
	for a in _args():
		var s := String(a)
		if s == "--verbose":
			_verbose = true
		elif s.begins_with("--count="):
			var n := int(s.substr(8))
			if n > 0:
				_steps = [n]
	Engine.max_fps = 0
	# ДЕРЕВНЯ ГОБЛИНОВ ВЫКЛЮЧЕНА: стенд меряет ровно ту армию, которую
	# заявляет, и не растягивает габарит сетки на свой угол карты
	_OptCfgG.goblin_village = false
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(6)
	# Вражеский ИИ и производство замеру только мешают: он начнёт нанимать своих
	if main.get("enemy_ai") != null:
		main.enemy_ai.set_process(false)
	for step in _steps:
		await _measure(int(step))
	_report()
	get_tree().quit(0)

## Одна ступень: поставить две армии, свести и снять три замера
func _measure(total: int) -> void:
	await _clear_army()
	var half: int = total / 2
	var sq_p := _spawn_side(half, Constants.FACTION_PLAYER, -LINE_GAP * 0.5, 1.0)
	var sq_e := _spawn_side(half, Constants.FACTION_ENEMY,   LINE_GAP * 0.5, -1.0)
	await frames(10)

	# Приказ: каждая сторона идёт на встречную линию
	_order(sq_p, Vector3(0.0, 0.0, LINE_GAP))
	_order(sq_e, Vector3(0.0, 0.0, -LINE_GAP))

	var closing := await _sample(60)          # сближение
	# ПРИКАЗ АТАКИ, А НЕ ПРОСТО СХОЖДЕНИЕ. Раньше стенд разводил стороны одним
	# command_move навстречу друг другу, и это меряло НЕ ТО: бойцы оставались в
	# состоянии «марш», упирались в чужой строй и всю дорогу платили за проверку
	# «можно ли шагнуть в противника» (mb_enemyblock), а в бою участвовала только
	# линия соприкосновения. Игрок так не играет — он выделяет отряды и жмёт ПКМ
	# по врагу, то есть отдаёт command_attack с замком приказа.
	# Разница видна в разбивке: с движением process_attack давал 13.7 % тика,
	# и вывод «узкое место — поиск целей» на таком замере был бы построен на
	# сцене, которой в игре не бывает
	_attack_order(sq_p, sq_e)
	_attack_order(sq_e, sq_p)
	var clash   := await _sample(90)          # первые секунды свалки
	var grind   := await _sample(120)         # затяжной бой
	# РАЗБИВКА ПО ВЕТКАМ — ОТДЕЛЬНЫМ ОКНОМ, ВРЕМЯ КОТОРОГО ВЫБРАСЫВАЕТСЯ.
	# Раньше отчёт печатал prof_report(), но профиль никто не включал, и раздел
	# «Разбивка последней ступени» выходил пустым: флаг был, данных по нему не
	# было ни разу.
	# Профиль стоит дорого (две метки времени на ветку на бойца) и завышает тик
	# примерно вдвое, поэтому его нельзя включать поверх замеряемого окна — иначе
	# испортится само число, ради которого стенд существует. Отсюда берутся
	# ТОЛЬКО ДОЛИ, абсолюты — из строки таблицы выше
	if _verbose:
		_OptCfg.profile_physics = true
		_OptCfg.prof_reset()
		await _sample(120)
		_OptCfg.profile_physics = false

	var alive := 0
	for u in _units:
		if is_instance_valid(u) and not u.is_dead():
			alive += 1
	# ПЕРЕПИСЬ ЛИНИИ СОПРИКОСНОВЕНИЯ. Решающее число для планирования: сколько
	# бойцов в свалке реально достают оружием до противника, а сколько всё это
	# время считают подход, проверку чужого строя и стволы — то есть платят
	# полную цену шага, стоя в задних шеренгах и не имея по кому ударить
	var in_reach := 0
	var has_target := 0
	for u in _units:
		var un := u as Unit
		if un == null or not is_instance_valid(un) or un.is_dead():
			continue
		if un.attack_target != null:
			has_target += 1
			var t := un.attack_target as Node3D
			if t != null and is_instance_valid(t) \
					and un.global_position.distance_to(t.global_position) <= un.attack_range:
				in_reach += 1
	_notes.append("")
	_notes.append("  ЛИНИЯ СОПРИКОСНОВЕНИЯ на %d бойцов:" % alive)
	_notes.append("    достают до цели оружием: %d (%.0f%%)"
		% [in_reach, 100.0 * float(in_reach) / maxf(float(alive), 1.0)])
	_notes.append("    имеют цель, но идут к ней:  %d (%.0f%%)"
		% [has_target - in_reach,
		100.0 * float(has_target - in_reach) / maxf(float(alive), 1.0)])
	_rows.append([total, closing, clash, grind, alive])

## Замер: усреднённое время тика за n физкадров лёгким счётчиком
func _sample(n: int) -> float:
	_OptCfg.tick_meter = true
	_OptCfg.tick_reset()
	await frames(n)
	_OptCfg.tick_meter = false
	return _OptCfg.tick_ms()

func _clear_army() -> void:
	for u in _units:
		if is_instance_valid(u):
			u.free()
	_units.clear()
	GameManager.reset_squads()
	await frames(6)

## Линия из отрядов: сторона стоит квадратами, фронтом к противнику
func _spawn_side(total: int, faction: int, z_off: float, _facing: float) -> Array:
	var squads_n: int = int(ceil(float(total) / float(SQUAD_SIZE)))
	var per_row: int = int(ceil(sqrt(float(squads_n))))
	var rows_in_squad: int = int(ceil(float(SQUAD_SIZE) / float(COLS)))
	var sq_w: float = float(COLS) * GAP + SQUAD_GAP
	var sq_h: float = float(rows_in_squad) * GAP + SQUAD_GAP
	var origin_x: float = -0.5 * float(per_row) * sq_w
	var origin_z: float = z_off - 0.5 * float(per_row) * sq_h * 0.5
	var out: Array = []
	var placed := 0
	for s in range(squads_n):
		var sid: int = GameManager.new_squad(faction, "spearman")
		out.append(sid)
		var base_x: float = origin_x + float(s % per_row) * sq_w
		var base_z: float = origin_z + float(s / per_row) * sq_h * 0.5
		for i in range(SQUAD_SIZE):
			if placed >= total:
				break
			var u: Unit = Spearman.new()
			u.faction = faction
			main.world_add(u)
			u.global_position = Vector3(
				base_x + float(i % COLS) * GAP, 0.0,
				base_z + float(i / COLS) * GAP)
			# ЗДОРОВЬЯ ПОБОЛЬШЕ, НО НЕ БЕСКОНЕЧНО: бой должен идти всё время
			# замера, иначе к третьему отсчёту одна сторона уже выбита и
			# меряется снова марш. Гибель при этом происходит — она и есть
			# часть боевой цены (списание урона, смыкание рядов, снятие строк)
			u.max_health = 900.0
			u.current_health = 900.0
			GameManager.add_to_squad(sid, u)
			_units.append(u)
			placed += 1
	return out

## Приказ атаки, как его отдаёт игрок: каждому отряду — ближайший вражеский
## отряд, всем бойцам ОДНА цель с замком (см. SelectionManager._handle_right_click
## и Unit.command_attack: замок держится за отряд, а не за модель)
func _attack_order(mine: Array, foes: Array) -> void:
	for sid in mine:
		var members: Array = GameManager.squad_members(int(sid))
		if members.is_empty():
			continue
		var centre: Vector3 = (members[0] as Node3D).global_position
		# Ближайший вражеский отряд — по первому живому бойцу каждого
		var best: Unit = null
		var best_d := INF
		for fsid in foes:
			for m in GameManager.squad_members(int(fsid)):
				var fu := m as Unit
				if fu == null or fu.is_dead():
					continue
				var d: float = centre.distance_squared_to(fu.global_position)
				if d < best_d:
					best_d = d
					best = fu
				break
		if best == null:
			continue
		for m in members:
			var u := m as Unit
			if u != null and not u.is_dead():
				u.command_attack(best, true, true, true)

func _order(squad_ids: Array, offset: Vector3) -> void:
	for sid in squad_ids:
		var members: Array = GameManager.squad_members(int(sid))
		if members.is_empty():
			continue
		var centroid := Vector3.ZERO
		for u in members:
			centroid += (u as Node3D).global_position
		centroid /= float(members.size())
		centroid.y = 0.0
		var target: Vector3 = centroid + offset
		var course: Vector3 = offset.normalized()
		for u in members:
			var slot: Vector3 = target + ((u as Node3D).global_position - centroid)
			slot.y = 0.0
			(u as Unit).command_move(slot, false, course)

func _report() -> void:
	var out := PackedStringArray()
	out.append("")
	out.append("=== MASS BATTLE | HEADLESS | бюджет физтика 60 Гц = %.2f мс ===" % BUDGET_MS)
	out.append("")
	out.append("  Две армии равной численности сходятся и дерутся. «Тик» —")
	out.append("  вся армия в физическом кадре, лёгкий счётчик (не профиль).")
	out.append("")
	out.append("  бойцов | сближение | свалка | затяжной бой | живых | итог")
	out.append("  -------+-----------+--------+--------------+-------+------")
	var fail := false
	for r in _rows:
		var worst: float = maxf(maxf(float(r[1]), float(r[2])), float(r[3]))
		var ok: bool = worst <= BUDGET_MS
		if not ok:
			fail = true
		out.append("  %6d | %7.2f мс | %6.2f мс | %10.2f мс | %5d | %s"
			% [r[0], r[1], r[2], r[3], r[4], "PASS" if ok else "FAIL"])
	out.append("")
	if _verbose:
		out.append("Разбивка последней ступени (затяжной бой, отдельное окно).")
		out.append("ДОЛИ, НЕ АБСОЛЮТЫ: профиль удваивает тик, см. _measure.")
		out.append("")
		var rep: Array = _OptCfg.prof_report()
		# Общий знаменатель — сумма веток ВЕРХНЕГО уровня тика. Вложенные
		# счётчики (mb_*, atk_*) считать в неё нельзя: они уже входят в свои
		# родительские ветки, и сумма получилась бы больше ста процентов
		const TOP := ["process_move", "process_attack", "check_auto_aggro",
			"grid_update", "rank_recompute", "phalanx_advance", "matrix_skip",
			"rear_step"]
		var whole := 0.0
		for row in rep:
			if String(row[0]) in TOP:
				whole += float(row[1])
		out.append("  ── ВЕТКИ ТИКА ─────────────────────────────────────────")
		for row in rep:
			if not (String(row[0]) in TOP):
				continue
			out.append("    %-18s %6.1f%% | %7.2f мкс/вызов | %8d вызовов"
				% [row[0], 100.0 * float(row[1]) / maxf(whole, 1.0),
				float(row[3]), int(row[2])])
		out.append("")
		out.append("  ── ВНУТРИ БОЯ (доля от всего тика) ────────────────────")
		for name in ["atk_find_enemy", "atk_damage", "atk_strike"]:
			var hit := false
			for row in rep:
				if String(row[0]) == name:
					hit = true
					out.append("    %-18s %6.1f%% | %7.2f мкс/вызов | %8d вызовов"
						% [name, 100.0 * float(row[1]) / maxf(whole, 1.0),
						float(row[3]), int(row[2])])
			if not hit:
				out.append("    %-18s   —  ни одного вызова" % name)
		out.append("")
		out.append("  ── ВНУТРИ ШАГА (доля от всего тика) ───────────────────")
		for row in rep:
			if not String(row[0]).begins_with("mb_") \
					and not String(row[0]).begins_with("mv_"):
				continue
			out.append("    %-18s %6.1f%% | %7.2f мкс/вызов | %8d вызовов"
				% [row[0], 100.0 * float(row[1]) / maxf(whole, 1.0),
				float(row[3]), int(row[2])])
		# ── ВСЁ ОСТАЛЬНОЕ ────────────────────────────────────────────────────
		# Раздел-страховка, и он появился не от аккуратности: разбивка уже дважды
		# молчала о том, чего в неё не вписали руками. Сначала --verbose вообще не
		# включал профиль, потом новые счётчики (rear_step, battle_line) не попали
		# ни в один из списков выше и выглядели как «механика не работает».
		# Здесь печатается ВСЁ, что не показано раньше, — спрятаться больше нечему
		out.append("")
		out.append("  ── ОСТАЛЬНОЕ (общее на кадр, не на бойца) ─────────────")
		for row in rep:
			var nm := String(row[0])
			if nm in TOP or nm.begins_with("mb_") or nm.begins_with("mv_") \
					or nm.begins_with("atk_"):
				continue
			out.append("    %-18s %6.1f%% | %7.2f мкс/вызов | %8d вызовов"
				% [nm, 100.0 * float(row[1]) / maxf(whole, 1.0),
				float(row[3]), int(row[2])])
	for n in _notes:
		out.append(n)
	out.append("=== ИТОГ: %s ===" % ("FAIL" if fail else "PASS"))
	print("\n".join(out))
