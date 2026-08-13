extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_melee — БУХГАЛТЕРИЯ БОЯ НА УРОВНЕ ОТРЯДА (Этап 2, слой B)
## ═══════════════════════════════════════════════════════════════════════════
## Слой B не обязан ускорять кадр — он обязан сделать бой СВЯЗНЫМ: отряд знает,
## с кем дерётся, кто у него в контакте, а кто ещё нет, и подсказывает цель
## тому, кто свою потерял, вместо личного скана местности.
##
##   A СВЯЗКА          — отряд опознаёт противника большинством, а не первым
##                       встречным; одиночная помеха связку не перебивает.
##   B УЧЁТ            — engaged/free сходятся с фактом, посчитанным вручную.
##   C РАСПРЕДЕЛЕНИЕ   — цели размазываются по чужому отряду, а не сваливаются
##                       на одного; и никого не уводит за дальней целью.
##   D ЗАМЕНА ПАВШЕГО  — гибель цели не оставляет бойца без дела.
##   E ПРИКАЗ ВЫШЕ     — замок цели игрока подсказкой не перебивается.
##   F РАЗРЫВ          — приказ на марш и выход из отряда рвут связку.
##
## Запуск: godot --headless --path . res://qa_melee/Test.tscn

const _Opt := preload("res://scripts/perf_config.gd")
const SPEARMAN := preload("res://scenes/units/Spearman.tscn")

var main = null
var _pass := 0
var _fail := 0
var _trash: Array = []

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func verdict(title: String, ok: bool, detail: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	print("  ВЕРДИКТ %s: %s%s" % [title, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + detail) if detail != "" else ""])

## Отряд из n бойцов прямоугольником cols в ширину
func _squad(fac: int, at: Vector3, n: int, cols: int = 5) -> int:
	var sid: int = GameManager.new_squad(fac, "spearman")
	for i in range(n):
		var u: Unit = SPEARMAN.instantiate()
		u.faction = fac
		main.world_add(u)
		var p := Vector3(at.x + float(i % cols) * 0.9, 0.0,
			at.z + float(i / cols) * 0.9)
		u.global_position = Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)
		u.max_health = 5000.0
		u.current_health = 5000.0
		GameManager.add_to_squad(sid, u)
		_trash.append(u)
	return sid

func _live(sid: int) -> Array:
	var out: Array = []
	for m in GameManager.squad_members(sid):
		var u := m as Unit
		if u != null and is_instance_valid(u) and not u.is_dead():
			out.append(u)
	return out

func _attack(sid: int, foe_sid: int) -> void:
	var foes: Array = _live(foe_sid)
	if foes.is_empty():
		return
	for u in _live(sid):
		(u as Unit).command_attack(foes[0] as Node3D, true, true, false)

func _sweep() -> void:
	for n in _trash:
		if is_instance_valid(n):
			GameManager.remove_from_squad(n as Unit)
	for n in _trash:
		if is_instance_valid(n):
			(n as Node).queue_free()
	_trash.clear()
	await frames(8)

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(6)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	await frames(3)
	print("\n  выключатель squad_melee = %s" % str(_Opt.squad_melee))

	# ── A. СВЯЗКА ────────────────────────────────────────────────────────────
	print("\n───── A. ОТРЯД ОПОЗНАЁТ ПРОТИВНИКА ─────")
	var mine := _squad(Constants.FACTION_PLAYER, Vector3(-70, 0, -20), 20)
	var theirs := _squad(Constants.FACTION_ENEMY, Vector3(-70, 0, -14), 20)
	# Одиночка сбоку — «случайная помеха», которая не должна перебить связку
	var lone := _squad(Constants.FACTION_ENEMY, Vector3(-62, 0, -20), 1)
	await frames(4)
	_attack(mine, theirs)
	await frames(300)
	var foe: int = GameManager.squad_foe(mine)
	verdict("A1 связка установлена", foe > 0, "противник = отряд %d" % foe)
	verdict("A2 противником назван настоящий отряд, а не одиночная помеха",
		foe == theirs, "ожидался %d, получен %d (одиночка %d)" % [theirs, foe, lone])

	# ── B. УЧЁТ ──────────────────────────────────────────────────────────────
	print("\n───── B. УЧЁТ СХОДИТСЯ С ФАКТОМ ─────")
	var cnt: Array = GameManager.melee_counts(mine)
	# Считаем то же самое вручную
	var eng := 0
	var fre := 0
	for m in _live(mine):
		var u := m as Unit
		if u.state != Unit.State.ATTACKING:
			continue
		var t: Node3D = u.attack_target
		if t == null or not is_instance_valid(t):
			fre += 1
		elif u.global_position.distance_to(t.global_position) <= u.attack_range:
			eng += 1
		else:
			fre += 1
	verdict("B1 в контакте посчитано верно", int(cnt[0]) == eng,
		"отряд говорит %d, вручную %d" % [int(cnt[0]), eng])
	verdict("B2 свободных посчитано верно", int(cnt[1]) == fre,
		"отряд говорит %d, вручную %d" % [int(cnt[1]), fre])
	verdict("B3 кто-то действительно дерётся", eng > 0, "в контакте %d" % eng)

	# ── C. РАСПРЕДЕЛЕНИЕ ─────────────────────────────────────────────────────
	print("\n───── C. ЦЕЛИ РАЗМАЗАНЫ ПО ЧУЖОМУ ОТРЯДУ ─────")
	var hit: Dictionary = {}
	var far_target := 0
	var on_lone := 0
	for m in _live(mine):
		var u := m as Unit
		var t := u.attack_target as Unit
		if t == null or not is_instance_valid(t):
			continue
		hit[t.get_instance_id()] = int(hit.get(t.get_instance_id(), 0)) + 1
		if t.squad_id == lone:
			on_lone += 1
		# Никого не должно уводить за дальней целью: подсказка ограничена seek
		if u.global_position.distance_to(t.global_position) \
				> maxf(u.attack_range, Unit.FORCED_RETARGET_RANGE) + 4.0:
			far_target += 1
	var worst := 0
	for k in hit:
		worst = maxi(worst, int(hit[k]))
	print("  целей задействовано: %d, самая популярная собрала %d бойцов"
		% [hit.size(), worst])
	verdict("C1 отряд бьёт не в одну модель", hit.size() >= 3,
		"разных целей: %d" % hit.size())
	verdict("C2 никого не увело за дальней целью", far_target == 0,
		"ушло за дальней: %d" % far_target)

	# ── D. ЗАМЕНА ПАВШЕГО ────────────────────────────────────────────────────
	print("\n───── D. ГИБЕЛЬ ЦЕЛИ НЕ ОСТАВЛЯЕТ БЕЗ ДЕЛА ─────")
	# Убиваем самую популярную цель и смотрим, что её бойцы нашли новую
	var victim: Unit = null
	var vbest := 0
	for m in _live(theirs):
		var u := m as Unit
		if u.attackers > vbest:
			vbest = u.attackers
			victim = u
	var orphans: Array = []
	if victim != null:
		for m in _live(mine):
			var u := m as Unit
			if u.attack_target == victim:
				orphans.append(u)
		victim.take_damage(1e9, null)
	await frames(60)
	var rehomed := 0
	for o in orphans:
		var u := o as Unit
		if is_instance_valid(u) and u.attack_target != null \
				and is_instance_valid(u.attack_target):
			rehomed += 1
	verdict("D1 осиротевшие бойцы получили новую цель",
		orphans.size() > 0 and rehomed == orphans.size(),
		"перенацелено %d из %d" % [rehomed, orphans.size()])
	# И новая цель — из ТОГО ЖЕ вражеского отряда, а не кто попало
	var same := 0
	for o in orphans:
		var u := o as Unit
		var t := u.attack_target as Unit
		if t != null and is_instance_valid(t) and t.squad_id == theirs:
			same += 1
	verdict("D2 новая цель — из того же вражеского отряда", same == rehomed,
		"из того же отряда %d из %d" % [same, rehomed])
	await _sweep()

	# ── E. ПРИКАЗ ИГРОКА ВЫШЕ ПОДСКАЗКИ ──────────────────────────────────────
	print("\n───── E. ЗАМОК ЦЕЛИ ИГРОКА НЕ ПЕРЕБИВАЕТСЯ ─────")
	var m2 := _squad(Constants.FACTION_PLAYER, Vector3(0, 0, -20), 12)
	var near_foe := _squad(Constants.FACTION_ENEMY, Vector3(0, 0, -15), 12)
	var far_foe := _squad(Constants.FACTION_ENEMY, Vector3(0, 0, -8), 12)
	await frames(4)
	# Приказ игрока — на ДАЛЬНИЙ отряд, мимо ближнего
	var far_list: Array = _live(far_foe)
	for u in _live(m2):
		(u as Unit).command_attack(far_list[0] as Node3D, true, true, true)
	await frames(300)
	# ЧТО ИМЕННО ОБЯЗАНО СОХРАНИТЬСЯ. Не цель, а ЗАМОК: приказ игрока держится за
	# вражеский ОТРЯД (Unit._lock_squad), а ближний заслон вплотную — это
	# приоритет №2, и драться с ним под замком не только можно, но и нужно
	# (см. шапку про target_lock и qa_approach_intercept). Первая версия проверки
	# требовала, чтобы все целились в назначенный отряд, и краснела на штатном
	# поведении — ошибка была в ожидании, а не в коде
	var locked := 0
	var kept := 0
	for u in _live(m2):
		var un := u as Unit
		if un.target_lock:
			locked += 1
			if un._lock_squad == far_foe:
				kept += 1
	print("  под замком %d, замок держит назначенный отряд %d из %d"
		% [locked, kept, _live(m2).size()])
	verdict("E1 замок цели держится", locked > 0, "под замком %d" % locked)
	verdict("E2 подсказка отряда не подменила назначенный отряд",
		kept == locked, "замок на назначенном отряде %d из %d" % [kept, locked])
	await _sweep()

	# ── F. РАЗРЫВ СВЯЗКИ ─────────────────────────────────────────────────────
	print("\n───── F. ПРИКАЗ РВЁТ СВЯЗКУ ─────")
	var m3 := _squad(Constants.FACTION_PLAYER, Vector3(70, 0, -20), 12)
	var f3 := _squad(Constants.FACTION_ENEMY, Vector3(70, 0, -15), 12)
	await frames(4)
	_attack(m3, f3)
	await frames(300)
	verdict("F1 связка была установлена", GameManager.squad_foe(m3) == f3,
		"противник = %d" % GameManager.squad_foe(m3))
	# Уводим отряд приказом на марш
	for u in _live(m3):
		(u as Unit).command_move(Vector3(70, 0, -50))
	await frames(240)
	var still_fighting := 0
	for u in _live(m3):
		if (u as Unit).attack_target != null:
			still_fighting += 1
	verdict("F2 приказ на марш вывел отряд из боя", still_fighting == 0,
		"осталось с целью: %d" % still_fighting)
	# МЕРА — СДВИГ ЦЕНТРА МАСС, А НЕ ПОДСЧЁТ ПООДИНОЧКЕ. Поштучный счёт («сколько
	# бойцов удалились больше чем на 6 м») давал 4-6 из 12 от прогона к прогону:
	# отряд расцепляется со свалкой вразнобой, задние трогаются позже передних,
	# и порог по числу бойцов ловит момент замера, а не факт ухода. «Отряд ушёл»
	# — это про отряд, вот его и меряем
	var cm := Vector3.ZERO
	var alive: Array = _live(m3)
	for u in alive:
		cm += (u as Node3D).global_position
	cm /= maxf(float(alive.size()), 1.0)
	var shift: float = Vector2(cm.x - 70.0, cm.z - (-20.0)).length()
	# Порог 3 м, а не «сколько успеют за окно»: отряд выцарапывается из свалки
	# медленно (чужой строй он не проходит насквозь, а обтекает), и устойчиво
	# даёт 5.6-5.7 м. Топтание на месте — это меньше метра, так что тройка
	# разделяет два состояния с запасом и не зависит от длины окна замера
	verdict("F3 отряд действительно ушёл, а не топчется", shift > 3.0,
		"центр масс сместился на %.1f м" % shift)
	await _sweep()

	print("\n═══ qa_melee: прошло %d, провалов: %d ═══" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)
