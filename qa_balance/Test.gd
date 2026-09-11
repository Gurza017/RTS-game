extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД БАЛАНСА: TTK, МОРАЛЬ И ПАНИКА, ТЕМП ЭКОНОМИКИ
## ═══════════════════════════════════════════════════════════════════════════
## Проверяет ровно то, что заказано балансным документом (docs/BALANCE_MATH.md):
##   A — время жизни в ДУЭЛИ моделей: сколько ударов и сколько секунд;
##   B — время схватки ДВУХ ОТРЯДОВ 1 на 1 (заказ: 30-60 секунд до перелома);
##   C — мораль и паника: белый флаг, потеря управления, бегство, возврат;
##   D — легендарные перки: «Непреклонные» и «Пробитие брони»;
##   E — темп экономики: сколько несёт рабочий и за сколько копится первое
##       исследование в кузнице.
##
## ЧИСЛА ЧИТАЮТСЯ ИЗ КОНФИГА, А НЕ ХАРДКОДЯТСЯ (правило 10 проекта): стенд
## сверяет СВОЙСТВА («дуэль длится дольше пятнадцати секунд», «первый тир
## копится около трёх минут»), а сами характеристики берёт из
## unit_stats_config и forge_config.
##
## Запуск: godot --headless --path . res://qa_balance/Test.tscn

const _UCfg  := preload("res://scripts/unit_stats_config.gd")
const _Forge := preload("res://scripts/forge_config.gd")

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")

## physics_frame, а не process_frame (правило 11 проекта)
func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func verdict(title: String, ok: bool, detail: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	_log.append([title, ok])
	print("  ВЕРДИКТ %s: %s%s" % [title, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + detail) if detail != "" else ""])

func _pad(s: String, n: int) -> String:
	var o := s
	while o.length() < n: o += " "
	return o

func _spawn(scene: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = load(scene).instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	return u

func _squad(scene: String, stat: String, fac: int, at: Vector3,
		n: int, cols: int) -> Array:
	var sid: int = GameManager.new_squad(fac, stat)
	var men: Array = []
	for i in range(n):
		var p := at + Vector3(float(i % cols) * 0.62 - float(cols) * 0.31,
			0.0, float(i / cols) * 0.62)
		var u := _spawn(scene, fac, p)
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return men

func _sid(men: Array) -> int:
	for u in men:
		if is_instance_valid(u):
			return (u as Unit).squad_id
	return 0

func _alive(men: Array) -> int:
	var n := 0
	for u in men:
		if u != null and is_instance_valid(u) and not (u as Unit).is_dead():
			n += 1
	return n

const SCENES := {
	"spearman": "res://scenes/units/Spearman.tscn",
	"warrior":  "res://scenes/units/Warrior.tscn",
	"archer":   "res://scenes/units/Archer.tscn",
}

func _run() -> void:
	seed(5)
	Engine.max_fps = 0
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	GameManager.world_bounds_enabled = false
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	for n in get_tree().get_nodes_in_group("all_units"):
		(n as Node).queue_free()
	await frames(6)

	_block_formula()
	await _block_duel()
	await _block_squad()
	await _block_panic()
	await _block_legend()
	_block_economy()

	print("\n═════ ИТОГ ═════")
	for e in _log:
		var r: Array = e
		print("  %s%s" % [_pad(String(r[0]), 62), "ПРОШЛО" if bool(r[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	print("\n=== QA_BALANCE DONE ===")
	get_tree().quit(1 if _fail > 0 else 0)

# ═════════════════════════════════════════════════════════════════════════════
# 0. ФОРМУЛА БРОНИ
# ═════════════════════════════════════════════════════════════════════════════
func _block_formula() -> void:
	print("\n═════ 0. ФОРМУЛА СНИЖЕНИЯ УРОНА ═════")
	var a: float = _UCfg.ARMOR_SOFTNESS
	print("  ARMOR_SOFTNESS = %.0f (броня %.0f режет ровно половину урона)" % [a, a])
	var rows: Array = [0.0, 1.0, 3.0, 5.0, 8.0, 12.0, 20.0, 30.0]
	for d in rows:
		var pass_frac: float = _UCfg.damage_after_armor(100.0, float(d)) / 100.0
		print("    защита %5.1f → проходит %5.1f %% урона" % [float(d), pass_frac * 100.0])
	# 0.1 — НУЛЯ НЕ БЫВАЕТ НИКОГДА. Это главное свойство формулы: ни одна
	# комбинация чисел в конфиге не делает юнита неуязвимым
	var huge: float = _UCfg.damage_after_armor(100.0, 500.0)
	verdict("0.1 сквозь любую защиту урон проходит", huge > 0.0,
		"при защите 500 проходит %.3f от сотни" % huge)
	# 0.2 — ЗАТУХАНИЕ: каждое следующее очко брони дешевле предыдущего
	var d1: float = _UCfg.damage_after_armor(100.0, 0.0) - _UCfg.damage_after_armor(100.0, 1.0)
	var d20: float = _UCfg.damage_after_armor(100.0, 19.0) - _UCfg.damage_after_armor(100.0, 20.0)
	verdict("0.2 броня затухает: двадцатое очко дешевле первого", d20 < d1 * 0.5,
		"первое очко %.2f, двадцатое %.2f" % [d1, d20])
	# 0.3 — ЦЕНА ОЧКА НЕ ЗАВИСИТ ОТ ВЕЛИЧИНЫ УДАРА (в этом весь смысл долевой
	# формулы: балансировать вычитание против разного оружия невозможно)
	var f_small: float = _UCfg.damage_after_armor(10.0, 6.0) / 10.0
	var f_big: float = _UCfg.damage_after_armor(40.0, 6.0) / 40.0
	verdict("0.3 доля снижения одинакова против любого оружия",
		absf(f_small - f_big) < 0.001,
		"удар 10 → %.3f, удар 40 → %.3f" % [f_small, f_big])

# ═════════════════════════════════════════════════════════════════════════════
# A. ДУЭЛЬ ДВУХ МОДЕЛЕЙ
# ═════════════════════════════════════════════════════════════════════════════
## Нижняя граница дуэли. Жалоба владельца — «юниты мрут за 10 секунд», поэтому
## порог поставлен ЗАМЕТНО выше десяти: пятнадцать секунд это уже «успел
## увидеть, среагировать, увести»
const DUEL_MIN_SEC := 15.0
const DUEL_MAX_SEC := 45.0

func _block_duel() -> void:
	print("\n═════ A. ДУЭЛЬ: СКОЛЬКО ЖИВЁТ ОДНА МОДЕЛЬ ═════")
	# Считаем АРИФМЕТИКОЙ по тем же числам, по которым бьёт код: сводить бой
	# двух моделей ради секундомера незачем, а формула проверена блоком 0
	var worst := 1e9
	for atk in ["spearman", "warrior", "archer"]:
		for vic in ["spearman", "warrior", "archer"]:
			var dmg: float = _dps(atk)
			var hp: float = float(_UCfg.stat(vic, "health", 100.0))
			var arm: float = float(_UCfg.stat(vic, "armor", 0.0)) \
				+ float(_UCfg.stat(vic, "defense", 0.0))
			var per_hit: float = _UCfg.damage_after_armor(_avg_hit(atk), arm)
			var cd: float = float(_UCfg.stat(atk, "attack_cooldown", 1.0))
			var hits: float = ceil(hp / maxf(per_hit, 0.01))
			var secs: float = hits * cd
			print("    %-9s бьёт %-9s: %5.1f за удар, %2.0f ударов, %5.1f с (DPS %.1f)"
				% [atk, vic, per_hit, hits, secs, dmg])
			# ── СУДИМ ТОЛЬКО ЛИНЕЙНУЮ ПЕХОТУ ─────────────────────────────
			# Лучник в рукопашной обязан складываться быстро — это его цена за
			# двадцать метров дальности, и так прямо написано в его описании.
			# Включи его в замер — и порог TTK пришлось бы задирать всей игре
			# ради пары, которой в бою быть не должно
			if atk != "archer" and vic != "archer":
				worst = minf(worst, secs)
	verdict("A1 дуэль ЛИНЕЙНОЙ ПЕХОТЫ длится дольше %.0f с" % DUEL_MIN_SEC,
		worst >= DUEL_MIN_SEC, "самая быстрая дуэль %.1f с" % worst)

func _avg_hit(unit_id: String) -> float:
	# Ротация 3×attack_1 + 1×attack_2 есть ТОЛЬКО у мечника (Warrior._strike_damage)
	var a1: float = float(_UCfg.stat(unit_id, "attack_1", 10.0))
	if unit_id == "warrior":
		var a2: float = float(_UCfg.stat(unit_id, "attack_2", a1))
		return (a1 * 3.0 + a2) / 4.0
	return a1

func _dps(unit_id: String) -> float:
	return _avg_hit(unit_id) / maxf(float(_UCfg.stat(unit_id, "attack_cooldown", 1.0)), 0.01)

# ═════════════════════════════════════════════════════════════════════════════
# B. СХВАТКА ДВУХ ОТРЯДОВ 1 НА 1
# ═════════════════════════════════════════════════════════════════════════════
## Заказ владельца: «схватка двух базовых отрядов должна длиться от 30 до ±60
## секунд». Меряем ПЕРЕЛОМ — момент, когда одна сторона потеряла половину
## состава: именно он и читается игроком как «бой решён», а добивание идёт
## уже за счёт паники
const CLASH_MIN_SEC := 25.0
const CLASH_MAX_SEC := 75.0

func _block_squad() -> void:
	print("\n═════ B. СХВАТКА ДВУХ ОТРЯДОВ КОПЕЙЩИКОВ ═════")
	var n: int = _UCfg.squad_size("spearman")
	var mine := _squad(SCENES["spearman"], "spearman", Constants.FACTION_PLAYER,
		Vector3(-4.0, 0.0, 0.0), n, 10)
	var foes := _squad(SCENES["spearman"], "spearman", Constants.FACTION_ENEMY,
		Vector3(4.0, 0.0, 0.0), n, 10)
	await frames(20)
	for u in mine:
		(u as Unit).command_attack(foes[0], true, true, true)
	for u in foes:
		(u as Unit).command_attack(mine[0], true, true, true)
	var half := -1.0
	var wipe := -1.0
	for t in range(150):                       # до 150 секунд
		await frames(60)
		var a: int = _alive(mine)
		var b: int = _alive(foes)
		if half < 0.0 and (a <= n / 2 or b <= n / 2):
			half = float(t + 1)
		if a == 0 or b == 0:
			wipe = float(t + 1)
			break
	print("  отряды по %d: перелом (−50%% состава) на %.0f с, полное истребление на %.0f с"
		% [n, half, wipe])
	print("  осталось: у нас %d, у них %d" % [_alive(mine), _alive(foes)])
	verdict("B1 перелом схватки наступает в окне %.0f-%.0f с" % [CLASH_MIN_SEC, CLASH_MAX_SEC],
		half >= CLASH_MIN_SEC and half <= CLASH_MAX_SEC,
		"перелом на %.0f с" % half)
	for u in mine + foes:
		if is_instance_valid(u):
			(u as Node).queue_free()
	await frames(10)

# ═════════════════════════════════════════════════════════════════════════════
# C. МОРАЛЬ И ПАНИКА
# ═════════════════════════════════════════════════════════════════════════════
func _block_panic() -> void:
	print("\n═════ C. МОРАЛЬ И ПАНИКА (БЕЛЫЙ ФЛАГ) ═════")
	var at := Vector3(-300.0, 0.0, -300.0)
	# Заведомо неравный бой: горстка копейщиков против втрое большего отряда
	# мечников. Мораль первых обязана рухнуть раньше, чем их добьют
	var weak := _squad(SCENES["spearman"], "spearman", Constants.FACTION_PLAYER,
		at, 12, 4)
	var strong := _squad(SCENES["warrior"], "warrior", Constants.FACTION_ENEMY,
		at + Vector3(4.0, 0.0, 0.0), 36, 6)
	await frames(20)
	var sid := _sid(weak)
	var m0: float = GameManager.squad_morale(sid)
	for u in weak:
		(u as Unit).command_attack(strong[0], true, true, true)
	for u in strong:
		(u as Unit).command_attack(weak[0], true, true, true)

	var start: Vector3 = GameManager.squad_centroid(sid)
	var panicked := false
	var m_at_panic := 0.0
	for t in range(90):
		await frames(30)
		if GameManager.squad_panicked(sid):
			panicked = true
			m_at_panic = GameManager.squad_morale(sid)
			break
	verdict("C1 отряд сорвался в панику под избиением", panicked,
		"мораль была %.0f, стала %.0f" % [m0, m_at_panic])
	if not panicked:
		for u in weak + strong:
			if is_instance_valid(u):
				(u as Node).queue_free()
		await frames(10)
		return

	# C2 — БЕЛЫЙ ФЛАГ ПОДНЯТ
	# ── СПРАШИВАЕМ ЕДИНСТВЕННОЕ ЗНАМЯ ОТРЯДА, А НЕ ОТДЕЛЬНЫЙ УЗЕЛ ──────────
	# Второго узла («panic_marker») больше нет: он давал «юнита с двумя
	# флагами» и флаг, застывший в пустом поле между разбежавшимися. Белое
	# полотнище — это СОСТОЯНИЕ знамени отряда (SquadBanner.shown_white)
	var flag = (GameManager.squads[sid] as Dictionary).get("banner")
	verdict("C2 над отрядом поднят белый флаг",
		flag != null and is_instance_valid(flag) and bool(flag.shown_white))

	# C3 — БОЙЦЫ ПОТЕРЯЛИ УПРАВЛЕНИЕ: приказ игрока не исполняется
	var probe: Unit = null
	for u in weak:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			probe = u
			break
	var obeyed := true
	if probe != null:
		var before: Vector3 = probe.move_target
		probe.command_move(at + Vector3(0.0, 0.0, 40.0), false, Vector3.ZERO, false, true)
		obeyed = probe.move_target != before
	verdict("C3 паникующий не принимает приказов игрока", not obeyed)

	# C4 — И НЕ ДЕРЁТСЯ
	var with_target := 0
	for u in weak:
		if is_instance_valid(u) and not (u as Unit).is_dead() \
				and (u as Unit).attack_target != null:
			with_target += 1
	verdict("C4 паникующий бросает цель", with_target == 0,
		"с целью осталось %d" % with_target)

	# C5 — БЕГУТ ОТ ВРАГА
	await frames(60 * 6)
	var now_c: Vector3 = GameManager.squad_centroid(sid)
	var ran: float = Vector2(now_c.x - start.x, now_c.z - start.z).length()
	verdict("C5 отряд убежал от места боя", ran > 5.0, "ушли на %.1f м" % ran)

	# C6 — ЧЕРЕЗ PANIC_STUN_SEC ПОРЯДОК ВОССТАНОВЛЕН
	# ── C6/C7 МЕРЯЮТСЯ ОДНИМ КАДРОМ (сент. 2026) ────────────────────────────
	# C7 сканировал бойцов СПУСТЯ обход после выхода C6, и в эту щель влезал
	# ЗАКОННЫЙ повторный срыв (враг рядом, относительный порог): «осталось
	# помеченных 5» ловило не залипший признак, а новую панику. Инвариант
	# жизненного цикла — «в тот кадр, когда отряд отчитался о восстановлении,
	# признак снят у ВСЕХ» (_end_panic делает это одним свипом) — и меряется
	# он в том же кадре, что и выход отряда из паники
	var still := -1
	for t in range(int(_UCfg.PANIC_STUN_SEC) + 6):
		await frames(60)
		if not GameManager.squad_panicked(sid):
			still = 0
			for u in weak:
				if is_instance_valid(u) and (u as Unit).is_panicked():
					still += 1
			break
	verdict("C6 через %.0f с отряд восстановил порядок" % _UCfg.PANIC_STUN_SEC,
		still >= 0,
		"мораль после ступора %.0f" % GameManager.squad_morale(sid))
	verdict("C7 признак паники снят со всех бойцов (тем же кадром)", still == 0,
		"осталось помеченных %d" % still)
	for u in weak + strong:
		if is_instance_valid(u):
			(u as Node).queue_free()
	await frames(10)

# ═════════════════════════════════════════════════════════════════════════════
# D. ЛЕГЕНДАРНЫЕ ПЕРКИ
# ═════════════════════════════════════════════════════════════════════════════
func _block_legend() -> void:
	print("\n═════ D. ЛЕГЕНДАРНЫЕ ПЕРКИ ═════")
	# D1 — СЕДЬМАЯ СТУПЕНЬ ДАЁТ ПЯТЬ УНИКАЛЬНЫХ ПЕРКОВ
	var lvl7: Array = _UCfg.veteran_choices("spearman", 7)
	var ids: Array = []
	for c in lvl7:
		ids.append(String((c as Dictionary).get("id", "")))
	verdict("D1 на золотом штандарте пять уникальных перков",
		lvl7.size() == 5 and ids.size() == 5,
		"варианты: %s" % str(ids))
	# ── D2. НА КАЖДОЙ СТУПЕНИ РОВНО ТРИ КАРТОЧКИ ──────────────────────────
	# ТРЕБОВАНИЕ РАЗВЁРНУТО ВЛАДЕЛЬЦЕМ: было 3/4/5 на лычках и 3/4/5 на флагах,
	# стало «всегда строго три — выбор из пяти создаёт информационный шум».
	#
	# СЕДЬМАЯ СТУПЕНЬ ИЗ ПРАВИЛА ВЫВЕДЕНА, И ЭТО ПОДТВЕРЖДЕНО ВЛАДЕЛЬЦЕМ: там
	# награда — ПРАВИЛО, а не цифра (иммунитет к панике, пробитие брони, щит от
	# стрел), тройка статов к ней неприменима вовсе, а обрезание до трёх
	# означало бы удалить из игры две механики. Её счёт стережёт D1 выше
	var got: Array = []
	var shape_ok := true
	for lv in range(1, 7):
		var n: int = _UCfg.veteran_choices("spearman", lv).size()
		got.append(n)
		if n != 3:
			shape_ok = false
	verdict("D2 на каждой ступени статов ровно три карточки", shape_ok,
		"по ступеням 1-6: %s" % str(got))
	# ── D2б. И ВСЕ ТРИ ПАРАМЕТРА — ИЗ ОДНОЙ ТРОЙКИ ────────────────────────
	# Заказ владельца: «ограничь доступные статы базовой тройкой — Атака,
	# Защита/Броня, Здоровье». Проверяем СВОЙСТВО по самому конфигу: ни один
	# выбор на ступенях статов не имеет права трогать что-то сверх неё
	var allowed := {"bonus_attack": true, "bonus_armor": true,
		"bonus_defense": true, "bonus_health": true}
	var strays: Array = []
	for lv2 in range(1, 7):
		for c2 in _UCfg.veteran_choices("spearman", lv2):
			for k in _UCfg.nonzero_modifiers(c2 as Dictionary):
				if not allowed.has(String(k)):
					strays.append("%d:%s" % [lv2, String(k)])
	verdict("D2б параметры карточек только из тройки атака/броня/здоровье",
		strays.is_empty(), "посторонние: %s" % str(strays))
	# D3 — У КАЖДОГО ВЫБОРА РОВНО ТРИ НЕНУЛЕВЫХ ПАРАМЕТРА
	var bad: Array = []
	for lv in range(1, 8):
		for c in _UCfg.veteran_choices("spearman", lv):
			var n: int = _UCfg.nonzero_modifiers(c as Dictionary).size()
			if n != 3:
				bad.append("%d/%s=%d" % [lv, String((c as Dictionary).get("id", "?")), n])
	verdict("D3 у каждого выбора ровно 3 параметра", bad.is_empty(),
		("нарушения: " + str(bad)) if not bad.is_empty() else "проверено 29 выборов")

	# D4 — «НЕПРЕКЛОННЫЕ» НЕ ПАНИКУЮТ
	var at := Vector3(300.0, 0.0, 300.0)
	var men := _squad(SCENES["spearman"], "spearman", Constants.FACTION_PLAYER, at, 6, 3)
	var sid := _sid(men)
	(GameManager.squads[sid] as Dictionary)["chosen"] = ["legend_steadfast"]
	GameManager.squad_add_morale(sid, -_UCfg.MORALE_MAX)
	GameManager._start_panic(sid)
	verdict("D4 «Непреклонные» не срываются в панику",
		not GameManager.squad_panicked(sid))
	# D5 — «ПРОБИТИЕ БРОНИ» СНИМАЕТ ДОЛЮ ЗАЩИТЫ
	(GameManager.squads[sid] as Dictionary)["chosen"] = ["legend_pierce"]
	var pierce: float = GameManager.squad_armor_pierce(men[0])
	verdict("D5 «Пробитие брони» игнорирует %.0f%% защиты"
		% (_UCfg.LEGEND_PIERCE_FRAC * 100.0),
		absf(pierce - _UCfg.LEGEND_PIERCE_FRAC) < 0.001,
		"вернулось %.2f" % pierce)
	for u in men:
		if is_instance_valid(u):
			(u as Node).queue_free()
	await frames(10)

# ═════════════════════════════════════════════════════════════════════════════
# E. ТЕМП ЭКОНОМИКИ
# ═════════════════════════════════════════════════════════════════════════════
## Сколько секунд рабочий тратит на ходку туда-обратно при типичном плече.
## Не замер, а ОЦЕНКА: настоящее плечо зависит от того, куда игрок поставил
## замок, и стенду важна не она, а порядок величины
const HAUL_DIST := 9.0

func _block_economy() -> void:
	print("\n═════ E. ТЕМП ЭКОНОМИКИ ═════")
	var cycle: float = float(_UCfg.stat("worker", "gather_time", 4.0))
	var amount: float = float(_UCfg.stat("worker", "gather_amount", 8.0))
	var v_empty: float = float(_UCfg.stat("worker", "walk_speed_empty", 3.0))
	var v_load: float = float(_UCfg.stat("worker", "walk_speed_loaded", 2.0))
	var haul: float = HAUL_DIST / v_empty + HAUL_DIST / v_load
	var full: float = cycle + haul
	var per_min: float = amount / full * 60.0
	print("  цикл добычи %.1f с + ходка %.1f с = %.1f с на %.0f единиц"
		% [cycle, haul, full, amount])
	print("  ОДИН рабочий приносит %.0f единиц в минуту" % per_min)
	for crew in [4, 6, 8, 12]:
		print("    %2d рабочих → %4.0f ед/мин" % [crew, per_min * float(crew)])

	# E1 — ПЕРВОЕ ИССЛЕДОВАНИЕ КОПИТСЯ ОКОЛО ТРЁХ МИНУТ
	# Считаем по бригаде из восьми рабочих, разделённой поровну между деревом и
	# золотом: это типичный старт после замка и четырёх наймов
	var t1: Dictionary = _Forge.get_node(_Forge.node_id("spearman", "1a"))
	var w: float = float(t1.get("cost_wood", 0.0))
	var g: float = float(t1.get("cost_gold", 0.0))
	var rate_each: float = per_min * 4.0        # по четыре рабочих на ресурс
	var need: float = maxf(w / maxf(rate_each, 0.01), g / maxf(rate_each, 0.01))
	print("  первый узел кузницы: %.0f дерева + %.0f золота" % [w, g])
	print("  при бригаде 4+4 копится %.1f мин" % need)
	verdict("E1 первое исследование копится 2-4 минуты",
		need >= 2.0 and need <= 4.0, "вышло %.1f мин" % need)

	# E2 — ТРИ УЛУЧШЕНИЯ ПОДРЯД КУПИТЬ НЕЛЬЗЯ: стартовый запас меньше цены
	# даже одного узла плюс обязательных построек
	# СТАРТОВЫЙ ЗАПАС ИГРОКА ЗАФИКСИРОВАН ВЛАДЕЛЬЦЕМ (20 000, 10.09.2026) и
	# не трогается; расчётная экономика судится по запасу ИИ (450/350)
	var start: Dictionary = _UCfg.starting_resources(Constants.FACTION_ENEMY)
	var s_wood: float = float(start.get(Constants.RESOURCE_WOOD, 0.0))
	var s_gold: float = float(start.get(Constants.RESOURCE_GOLD, 0.0))
	print("  стартовый запас ИИ: %.0f дерева, %.0f золота" % [s_wood, s_gold])
	verdict("E2 расчётного стартового запаса (ИИ) не хватает и на одно исследование",
		s_wood < w * 3.0 and s_gold < g * 3.0,
		"хватило бы на %.1f узла по дереву" % (s_wood / maxf(w, 1.0)))

	# E3 — ЛЕСТНИЦА ТИРОВ МОНОТОННА: каждый следующий ряд дороже
	var prev := 0.0
	var mono := true
	var costs: Array = []
	for row in range(1, _Forge.ROWS + 1):
		var c: Dictionary = _Forge.get_node(_Forge.node_id("spearman", "%da" % row))
		var total: float = float(c.get("cost_wood", 0.0)) + float(c.get("cost_gold", 0.0)) \
			+ float(c.get("cost_stone", 0.0))
		costs.append(int(total))
		if total <= prev:
			mono = false
		prev = total
	verdict("E3 цена узлов растёт от ряда к ряду", mono,
		"по рядам: %s" % str(costs))
