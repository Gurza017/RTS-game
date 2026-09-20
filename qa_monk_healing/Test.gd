extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ЛЕЧЕНИЕ МОНАХА — ПОИСК, ПОДХОД, КАСТ, ОЧЕРЕДЬ, VFX (спринт 15)
## ═══════════════════════════════════════════════════════════════════════════
## ЗАКАЗ ВЛАДЕЛЬЦА, ПЯТЬ ПУНКТОВ ПОДРЯД:
##   1. монах ищет раненых своих в радиусе 10 м (включая себя);
##   2. ПОДХОДИТ на дистанцию заклинания и играет анимацию каста;
##   3. лечит ПООЧЕРЁДНО ПО ОДНОМУ, приоритет — наименьший процент запаса;
##   4. на спрайте лечимого крутится heal effect, ровно по центру рисунка;
##   5. вылечил — эффект гаснет, монах переключается на следующего.
##
## ЧТО ЗДЕСЬ НЕ ПРОВЕРЯЕТСЯ И ПОЧЕМУ: устройство самого квада эффекта (лента,
## кадры, приоритет отрисовки, один узел на монаха, четыре причины снятия) —
## это `qa_monk_vfx`, и дублировать его здесь незачем. Здесь проверяется
## МЕХАНИКА ЛЕЧЕНИЯ и то, что эффект доезжает до неё.
##
## Числа берутся из unit_stats_config (правило 10), ожидание — физкадрами
## (правило 11). Запуск:
##   godot --headless --path . res://qa_monk_healing/Test.tscn

const _UCfg := preload("res://scripts/unit_stats_config.gd")
## Компенсация наклона камеры: ею растянут каждый билборд, и без неё середина
## спрайта не считается (см. D2)
const _BBv := preload("res://scripts/BillboardUtil.gd")

## Запас раненых по заказу: «3 раненых солдата с 20 % HP»
const HURT_FRAC := 0.2

var main = null
var _monk: Monk = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	var t := get_tree().create_timer(300.0)
	t.timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 300 с")
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
	print("\n═════ ИТОГ qa_monk_healing: прошло %d, провалов: %d ═════"
		% [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _spawn(uid: String, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[uid].instantiate()
	u.faction = Constants.FACTION_PLAYER
	main.world_add(u)
	u.global_position = Vector3(at.x,
		GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	return u

func _hurt(uid: String, at: Vector3, frac: float = HURT_FRAC) -> Unit:
	var u: Unit = _spawn(uid, at)
	u.current_health = u.max_health * frac
	u._soa_push_stats()
	# ЗАМОРАЖИВАЕМ ПАЦИЕНТА, А НЕ МОНАХА: раненый в стенде никуда не идёт и ни
	# с кем не дерётся, а монаху тик НУЖЕН — в нём живёт и поиск, и подход, и
	# сам такт лечения
	u.set_tick(false)
	return u

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
	await pframes(4)
	await _a_scene()
	await _b_approach()
	await _c_heal()
	await _d_vfx()
	await _e_queue()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
# A. СЦЕНА: МОНАХ И ТРОЕ РАНЕНЫХ
# ═════════════════════════════════════════════════════════════════════════════
var _men: Array[Unit] = []
var _spot: Vector3 = Vector3.ZERO

func _a_scene() -> void:
	print("\n═════ A. СЦЕНА ═════")
	# ТЗ 16.09.2026: аура 20 м по умолчанию (прежний заказ 10 м развёрнут)
	verdict("A1 радиус ауры — 20 м (ТЗ 16.09.2026)",
		absf(_UCfg.MONK_HEAL_RADIUS - _UCfg.MONK_AURA_R) < 0.01,
		"%.1f м" % _UCfg.MONK_HEAL_RADIUS)
	# ТЗ 17.09.2026: каст — из любой точки ауры (cast_range = heal_radius),
	# подход — только к пациенту ЗА аурой (стережёт qa_monk_fix A)
	verdict("A2 дистанция каста равна радиусу ауры (лечит с границы, не в упор)",
		_UCfg.MONK_STAND_FRAC < 1.0 and _UCfg.MONK_STAND_FRAC > 0.0,
		"доля стояния %.2f радиуса" % _UCfg.MONK_STAND_FRAC)
	# Ровное место подальше от воды и склонов: подход меряется в метрах, и
	# обход берега исказил бы замер
	_spot = _flat_spot()
	_monk = _spawn("monk", _spot) as Monk
	# ТРОЕ РАЗНЫХ РОДОВ ВОЙСК (заказ: мечник, копейщик, рыцарь). Рыцаря у людей
	# нет — это род войск орды; берём третьим лучника, он в том же списке
	# заказа («мечники, копейщики, лучники, рыцари, а также сам монах»).
	# Разные роды здесь не для красоты: у них разные ленты и разная привязка
	# ног, и ровно на этом ломается «эффект по центру спрайта»
	var far: float = _UCfg.MONK_HEAL_RADIUS * 0.8
	_men = [
		_hurt("warrior", _spot + Vector3(far, 0.0, 0.0), 0.20),
		_hurt("spearman", _spot + Vector3(far * 0.75, 0.0, far * 0.5), 0.35),
		_hurt("archer", _spot + Vector3(far * 0.6, 0.0, -far * 0.6), 0.50),
	]
	await pframes(6)
	var seen := 0
	for u in _men:
		if u.current_health < u.max_health:
			seen += 1
	verdict("A3 трое раненых на месте и в радиусе поиска", seen == 3
		and _monk.global_position.distance_to(_men[0].global_position)
			<= _UCfg.MONK_HEAL_RADIUS,
		"раненых %d, до дальнего %.1f м" % [seen,
			_monk.global_position.distance_to(_men[0].global_position)])
	verdict("A4 и все они в дистанции каста (монаху идти незачем)",
		_monk.global_position.distance_to(_men[0].global_position)
			<= float(_monk.call("cast_range")))
	verdict("A4б каст равен радиусу ауры",
		absf(float(_monk.call("cast_range")) - float(_monk.call("heal_radius"))) < 0.01,
		"каст %.1f, аура %.1f" % [float(_monk.call("cast_range")), float(_monk.call("heal_radius"))])

## Ровная площадка без воды и склонов
func _flat_spot() -> Vector3:
	for r in range(0, 80, 5):
		for a in range(0, 12):
			var ang: float = TAU * float(a) / 12.0
			var p := Vector3(cos(ang) * float(r), 0.0, sin(ang) * float(r))
			if absf(p.x) > 60.0 or absf(p.z) > 40.0:
				continue
			var bad := false
			for dx in [-12.0, 0.0, 12.0]:
				for dz in [-12.0, 0.0, 12.0]:
					if main.is_water(p.x + dx, p.z + dz):
						bad = true
					if main.near_river(p.x + dx, p.z + dz, main.RIVER_BANK + 4.0):
						bad = true
					if main.plateau_height(p.x + dx, p.z + dz) > 0.05:
						bad = true
			if not bad:
				return p
	return Vector3.ZERO

# ═════════════════════════════════════════════════════════════════════════════
# B. ПОДХОД
# ═════════════════════════════════════════════════════════════════════════════
func _b_approach() -> void:
	print("\n═════ B. ПОДХОД К РАНЕНОМУ ═════")
	# Самый раненый — мечник (20 %), к нему монах и обязан пойти
	# ТЗ 17.09.2026: раненый В АУРЕ — монах с места не сходит и лечит оттуда;
	# ждём первый такт лечения (heal_ticks), сдвиг монаха за это время < 1 м
	var want: Unit = _men[0]
	var p0: Vector3 = _monk.global_position
	var drift := 0.0
	var ticked := false
	for _i in range(int(_monk.heal_tick_sec() * 3.0 * 60.0) + 60):
		await get_tree().physics_frame
		drift = maxf(drift, _monk.global_position.distance_to(p0))
		if int(_monk.get("heal_ticks")) > 0:
			ticked = true
			break
	print("  сдвиг монаха %.2f м, такт лечения %s" % [drift, str(ticked)])
	verdict("B1 монах к раненому в ауре НЕ идёт (сдвиг < 1 м)", drift < 1.0,
		"сдвиг %.2f м" % drift)
	verdict("B2 и начал лечить с места", ticked, "тактов %d" % int(_monk.get("heal_ticks")))
	verdict("B3 лечит САМОГО раненого, а не ближайшего",
		_monk.heal_target == want,
		"цель %s" % str(_monk.heal_target))

# ═════════════════════════════════════════════════════════════════════════════
# C. КАСТ И РОСТ ЗАПАСА
# ═════════════════════════════════════════════════════════════════════════════
func _c_heal() -> void:
	print("\n═════ C. ЗАКЛИНАНИЕ ═════")
	var want: Unit = _men[0]
	var hp0: float = want.current_health
	var cast_frames := 0
	for _i in range(int(_UCfg.MONK_HEAL_TICK * 6.0 * 60.0)):
		await get_tree().physics_frame
		# Анимация каста читается с самого бойца: _play_attack_anim ставит имя
		# ленты сразу, не дожидаясь визуального такта (в headless его нет)
		if String(_monk._anim_name) == "heal":
			cast_frames += 1
	var gained: float = want.current_health - hp0
	print("  запас %.0f → %.0f (+%.0f), кадров каста %d" % [
		hp0, want.current_health, gained, cast_frames])
	verdict("C1 запас раненого растёт", gained > 0.0, "+%.0f" % gained)
	verdict("C2 монах играет анимацию каста, а не стоит столбом",
		cast_frames > 0, "кадров %d" % cast_frames)
	# ТЕМП ЛЕЧЕНИЯ — ИЗ КОНФИГА, А НЕ КРУГЛОЕ ЧИСЛО (правило 10): за время t
	# монах отдаёт долю t / MONK_HEAL_SEC_PER_MAN полного запаса цели
	var secs: float = _UCfg.MONK_HEAL_TICK * 6.0
	var want_gain: float = want.max_health * secs / _UCfg.MONK_HEAL_SEC_PER_MAN
	verdict("C3 темп совпадает с конфигом (±40 %)",
		gained > want_gain * 0.6 and gained < want_gain * 1.4,
		"+%.0f при ожидаемых %.0f" % [gained, want_gain])

# ═════════════════════════════════════════════════════════════════════════════
# D. ЭФФЕКТ НА СПРАЙТЕ ЛЕЧИМОГО
# ═════════════════════════════════════════════════════════════════════════════
func _d_vfx() -> void:
	print("\n═════ D. ЭФФЕКТ НА СПРАЙТЕ ═════")
	var want: Unit = _men[0]
	var vfx: Node3D = _monk.heal_vfx_node()
	verdict("D1 во время лечения эффект есть и висит на лечимом",
		vfx != null and bool(vfx.get("visible")) and _monk.heal_vfx_target() == want,
		"цель эффекта %s" % str(_monk.heal_vfx_target()))
	if vfx == null:
		return
	# ── ЦЕНТР СПРАЙТА СЧИТАЕТСЯ ИЗ ЛЕНТЫ ЦЕЛИ ─────────────────────────────
	# Не из числа в коде монаха: так проверка остаётся независимой от того,
	# как он это делает, и остаётся верной для любого рода войск
	var sf: Array = want.sheet_frame()
	var mid: float = 0.0
	var tall: float = 0.0
	if sf.size() >= 5:
		mid = float(sf[4]) * _BBv.V_STRETCH
		var tx: Texture2D = sf[0]
		if tx != null:
			tall = float(tx.get_height()) * float(sf[3]) * _BBv.V_STRETCH
	var foot: Vector3 = want.draw_position()
	print("  эффект на высоте %.2f, середина рисунка %.2f, рисунок %.2f м" % [
		vfx.global_position.y - foot.y, mid, tall])
	verdict("D2 эффект в центре спрайта, а не в ногах",
		absf(vfx.global_position.y - foot.y - mid) < 0.25,
		"%.2f против %.2f" % [vfx.global_position.y - foot.y, mid])
	# Спринт 18 (третье письмо): размер VFX ФИКСИРОВАН (HEAL_VFX_SIZE_M), без
	# гигантского кольца на крупной цели — прежнее «не меньше 60 % рисунка» снято
	verdict("D3 размер эффекта фиксирован (HEAL_VFX_SIZE_M), не растёт с рисунком",
		tall > 0.0 and absf(((vfx as MeshInstance3D).mesh as QuadMesh).size.y - Monk.HEAL_VFX_SIZE_M) < 0.01,
		"квад %.2f при рисунке %.2f м" % [
			((vfx as MeshInstance3D).mesh as QuadMesh).size.y, tall])
	# ── ЦЕЛЬ ТРОНУЛАСЬ — ЭФФЕКТ ГАСНЕТ (ТЗ 18.09.2026, п. 1) ──────────────
	# Разворот прежнего «эффект едет за лечимым»: зелёный овал разрешён
	# только у стоящих, идущий лечимый теряет картинку (лечение при этом
	# идёт). Признак — факт смещения (moved_recently, порог 0.6 м/с): здесь
	# цель едет 0.9 м/с
	var hidden_frames := 0
	for i in range(60):
		var p: Vector3 = want.global_position + Vector3(0.0, 0.0, 0.02)
		want.global_position = Vector3(p.x,
			GameManager.get_terrain_height(p.x, p.z), p.z)
		want.sync_row()
		await get_tree().physics_frame
		if i < 20:
			continue
		if _monk.heal_vfx_target() != want or not bool(vfx.get("visible")):
			hidden_frames += 1
	verdict("D4 эффект гаснет, пока лечимый идёт (ТЗ 18.09.2026)", hidden_frames >= 12,
		"погашен %d кадров из 40" % hidden_frames)
	# Встал — эффект возвращается ближайшим тактом лечения
	var back := -1
	for i in range(int(_monk.heal_tick_sec() * 3.0 * 60.0) + 60):
		await get_tree().physics_frame
		if _monk.heal_vfx_target() != null and bool(vfx.get("visible")):
			back = i
			break
	verdict("D4б лечимый встал — эффект вернулся", back >= 0, "через %d физкадров" % back)

# ═════════════════════════════════════════════════════════════════════════════
# E. ОЧЕРЕДЬ: ПО ОДНОМУ, СЛЕДУЮЩИЙ — ПОСЛЕ ПОЛНОГО ИЗЛЕЧЕНИЯ
# ═════════════════════════════════════════════════════════════════════════════
func _e_queue() -> void:
	print("\n═════ E. ОЧЕРЕДЬ ═════")
	var first: Unit = _men[0]
	var others: Array[Unit] = [_men[1], _men[2]]
	var hp_before := [others[0].current_health, others[1].current_health]
	await pframes(int(_UCfg.MONK_HEAL_TICK * 4.0 * 60.0))
	var moved := 0
	for i in range(2):
		if others[i].current_health > float(hp_before[i]) + 0.01:
			moved += 1
	verdict("E1 пока первый не вылечен, остальные не лечатся", moved == 0,
		"тронулось запасов %d" % moved)
	verdict("E1б и эффект всё ещё на первом", _monk.heal_vfx_target() == first)
	# ── ПЕРВЫЙ ВЫЛЕЧЕН ────────────────────────────────────────────────────
	first.current_health = first.max_health
	first._soa_push_stats()
	await pframes(6)
	verdict("E2 вылечен — эффект с него снят",
		_monk.heal_vfx_target() != first,
		"висит на %s" % str(_monk.heal_vfx_target()))
	# Следующий по заказу — самый раненый из оставшихся, то есть копейщик
	var next_man: Unit = others[0]
	var hp0: float = next_man.current_health
	var got := false
	for _i in range(60 * 40):
		await get_tree().physics_frame
		if _monk.heal_vfx_target() == next_man and next_man.current_health > hp0 + 0.01:
			got = true
			break
	print("  следующий: запас %.0f → %.0f" % [hp0, next_man.current_health])
	verdict("E3 монах переключился на следующего раненого и лечит его", got,
		"цель %s, запас %+.0f" % [str(_monk.heal_vfx_target()),
			next_man.current_health - hp0])
	verdict("E4 целого монах не трогает вовсе",
		absf(first.current_health - first.max_health) < 0.01,
		"запас первого %.0f из %.0f" % [first.current_health, first.max_health])
