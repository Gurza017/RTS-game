extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_knights_push — ДВОЙНОЙ ПКМ, НАБЕГ И ТОЛЧОК ЩИТАМИ (спринт 14)
## ═══════════════════════════════════════════════════════════════════════════
## Заказ дословно: «Рыцари/Мечники, „Яростный Набег“: одиночный ПКМ — обычный
## шаг; ДВОЙНОЙ ПКМ ПО ВРАГУ — ускоренный бег со сменой спрайта/анимации (мечи
## наголо, щиты подняты); врезаются в строй, наносят серию (меч → щит → меч →
## щит) и делают МОЩНЫЙ ТОЛЧОК — увеличить силу отталкивания, чтобы врагов
## заметно раскидывало. Копейщики, „Натиск Фаланги“: по двойному ПКМ строй
## смыкается, копья вперёд, идут медленно и слаженно, бьют синхронно и
## методично оттесняют.»
##
##   A ВКЛЮЧЕНИЕ — двойной ПКМ ПО ВРАГУ раздаёт приём; одиночный — нет.
##   B НАБЕГ     — бег быстрее обычного, щит поднят, поза пересчитана.
##   C СЕРИЯ     — ровно пять ударов чередованием «обычный → мощный», быстрее
##                 обычного темпа, и приём кончается сам.
##   D ТОЛЧОК    — напор в набеге выше обычного в RAGE_PUSH_MULT раз, и живой
##                 замер: строй противника отъезжает заметно дальше.
##   E ФАЛАНГА   — натиск: строй сомкнут, ход медленный, копья опущены, серия
##                 усиленных ударов, затем ОТТЕСНЕНИЕ с повышенным напором и
##                 сниженным входящим уроном.
##
## Числа — из констант самих приёмов (правило 10), ожидание — физкадрами
## (правило 11). Запуск: godot --headless --path . res://qa_knights_push/Test.tscn

const _UCfg  := preload("res://scripts/unit_stats_config.gd")
const _Forge := preload("res://scripts/forge_config.gd")

var main = null
var sm   = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	var t := get_tree().create_timer(400.0)
	t.timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 400 с")
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
	print("\n═════ ИТОГ qa_knights_push: прошло %d, провалов: %d ═════" % [
		_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

## ── РОВНАЯ ПЛОЩАДКА ПОД КЛИК ──────────────────────────────────────────────
## Разбор клика считает точку земли под курсором АНАЛИТИЧЕСКИ, пересечением
## луча с плоскостью y = 0 (см. SelectionManager._pick_at, «грунт плоский»).
## Боец, стоящий на плато или на склоне, оказывается выше этой плоскости, и
## точка земли уезжает от него на высоту, делённую на тангенс наклона камеры:
## на плато в 5.65 м это 6.5 м, то есть мимо любого радиуса поиска. Стенд ловил
## на этом сам себя — «под курсором <null>» на исправном коде. Площадку
## выбираем ровную; сама особенность разбора клика записана в ENGINEERING_LOG
func _flat_spot(base: Vector3, span: float) -> Vector3:
	var best: Vector3 = base
	var best_h: float = 1e9
	for ix in range(-3, 4):
		for iz in range(-3, 4):
			var p := Vector3(base.x + float(ix) * span, 0.0, base.z + float(iz) * span)
			var h := 0.0
			# Ровная — это когда и середина, и оба края площадки лежат низко
			for d in [Vector3.ZERO, Vector3(16.0, 0.0, 0.0), Vector3(0.0, 0.0, 6.0)]:
				h = maxf(h, absf(GameManager.get_terrain_height(p.x + d.x, p.z + d.z)))
			if h < best_h:
				best_h = h
				best = p
	print("  площадка стенда: %s (перепад %.2f м)" % [str(best), best_h])
	return best

func _squad(kind: String, fac: int, at: Vector3, n: int, step: float) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var men: Array = []
	var sc: PackedScene = Building.PRELOAD_SCENES[kind]
	for i in range(n):
		var u: Unit = sc.instantiate()
		u.faction = fac
		main.world_add(u)
		var px: float = at.x + float(i / 4) * step
		var pz: float = at.z + float(i % 4) * step - step * 1.5
		u.global_position = Vector3(px,
			GameManager.get_terrain_height(px, pz), pz)
		u.sync_row()
		GameManager.add_to_squad(sid, u)
		u.post_pos = u.global_position
		men.append(u)
	return [sid, men]

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	sm = main.selection_manager
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	GameManager.world_bounds_enabled = false
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	# ПРИЁМЫ ОТКРЫТЫ ФРАКЦИИ, А НЕ КУПЛЕНЫ ОТРЯДОМ: со спринта 13 плата за
	# доступ снята, узел кузницы открывает приём ВСЕМ отрядам своего рода
	GameManager.finish_research(Constants.FACTION_PLAYER, "warrior_1d")
	GameManager.finish_research(Constants.FACTION_PLAYER, "spearman_4d")
	await pframes(4)

	await _a_trigger()
	await _b_dash()
	await _c_series()
	await _d_push()
	await _e_phalanx()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
# A. ДВОЙНОЙ ПКМ ПО ВРАГУ ВКЛЮЧАЕТ ПРИЁМ, ОДИНОЧНЫЙ — НЕТ
#
# Проверяется НАСТОЯЩИЙ путь клика (SelectionManager._handle_right_click), а не
# вызов раздачи напрямую: заказ спринта 13 был исполнен только для клика ПО
# ЗЕМЛЕ, и именно потому, что ветка приказа АТАКИ до раздачи не доходила
# ═════════════════════════════════════════════════════════════════════════════
func _a_trigger() -> void:
	print("\n═════ A. ДВОЙНОЙ ПКМ ПО ВРАГУ ═════")
	var spot: Vector3 = _flat_spot(
		main.PLAYER_BASE_ANCHOR + Vector3(0.0, 0.0, 60.0), 12.0)
	var mine: Array = _squad("warrior", Constants.FACTION_PLAYER, spot, 8, 1.0)
	var sid: int = mine[0]
	var men: Array = mine[1]
	# ── ЦЕЛЬ СТАВИТСЯ ВНУТРИ РАДИУСА УДЕРЖАНИЯ ЗАМКА ──────────────────────
	# Замок приказа держится, пока цель ближе _lock_sight_range() = максимум
	# из двойной дальности оружия и 2 × AGGRO_RADIUS (20 м у мечника). Цель
	# дальше — «приказ исчерпан», и замок снимается ПЕРВЫМ ЖЕ тиком: стенд
	# ловил на этом сам себя, поставив противника в 24 м
	var foe: Array = _squad("spearman", Constants.FACTION_ENEMY,
		spot + Vector3(Unit.AGGRO_RADIUS * 2.0 - 6.0, 0.0, 0.0), 8, 1.0)
	var foes: Array = foe[1]
	await pframes(6)
	for f in foes:
		(f as Unit).set_tick(false)
		(f as Unit).current_health = (f as Unit).max_health * 500.0
	verdict("A0 приём открыт кузницей и включён по умолчанию",
		GameManager.squad_has_ability(sid, "warrior_1d")
			and GameManager.squad_ability_on(sid, "warrior_1d"))

	# Выделяем отряд ровно так, как это делает игрок
	sm.selected_units.clear()
	for u in men:
		sm.selected_units.append(u)
	sm._sel_rebuild()
	await pframes(2)

	var cam: Camera3D = main.get("_camera") as Camera3D
	main.focus_camera_on((foes[0] as Node3D).global_position)
	await pframes(8)
	await frames(4)
	main.set_process(false)
	cam.set_process(false)
	await frames(2)
	var scr: Vector2 = cam.unproject_position(
		(foes[0] as Node3D).global_position + Vector3(0.0, 0.9, 0.0))

	# ── ОДИНОЧНЫЙ ПКМ: ОБЫЧНЫЙ ШАГ ─────────────────────────────────────────
	# Курсор обязан и правда накрывать врага: клик мимо него сделал бы весь
	# блок пустым — приказ ушёл бы в землю, а приём всё равно раздался бы
	# (двойной ПКМ по ЗЕМЛЕ его тоже включает, заказ спринта 13)
	var under = sm._pick_at(scr, sm.order_pick_mask()).get("target")
	print("  под курсором: %s" % ("враг" if under == foes[0] else str(under)))
	verdict("A0б курсор наведён на врага, а не на траву", under == foes[0])
	sm._handle_right_click(scr, false)
	await pframes(3)
	var raged_single := 0
	for u in men:
		if bool((u as Object).call("rage_active")):
			raged_single += 1
	verdict("A1 одиночный ПКМ приёма НЕ включает", raged_single == 0,
		"в набеге %d из %d" % [raged_single, men.size()])
	# ── ПРИКАЗ ПРОВЕРЯЕТСЯ ПО ЗАМКУ, А НЕ ПО attack_target ─────────────────
	# Замок взводится В МОМЕНТ приказа (_arm_target_lock), а сама цель
	# доезжает до поля ближайшим тиком БОЙЦА — а тик шардирован по кадрам, и
	# три кадра его могут не застать
	var locked := 0
	for u in men:
		if (u as Unit).target_lock:
			locked += 1
	verdict("A2 но приказ атаки принят всем отрядом", locked == men.size(),
		"замок у %d из %d" % [locked, men.size()])

	# ── ДВОЙНОЙ ПКМ: НАБЕГ ─────────────────────────────────────────────────
	sm._handle_right_click(scr, true)
	await pframes(3)
	var raged := 0
	for u in men:
		if bool((u as Object).call("rage_active")):
			raged += 1
	print("  раздано приёмов %d, в набеге %d из %d" % [
		int(sm.double_rmb_triggered), raged, men.size()])
	verdict("A3 двойной ПКМ ПО ВРАГУ включает набег ВСЕМУ отряду",
		raged == men.size(), "в набеге %d из %d" % [raged, men.size()])
	verdict("A4 раздача прошла отрядом, а не поштучно вслепую",
		int(sm.double_rmb_triggered) == men.size(),
		"раздано %d" % int(sm.double_rmb_triggered))
	main.set_process(true)
	cam.set_process(true)
	sm.selected_units.clear()
	sm._sel_rebuild()
	for u in men:
		_kill(u)
	for f in foes:
		_kill(f)
	await pframes(6)

# ═════════════════════════════════════════════════════════════════════════════
# B. БЕГ БЫСТРЕЕ, ЩИТ ПОДНЯТ, ПОЗА СМЕНИЛАСЬ
# ═════════════════════════════════════════════════════════════════════════════
func _b_dash() -> void:
	print("\n═════ B. МЕЧИ НАГОЛО, ЩИТЫ ПОДНЯТЫ ═════")
	var spot: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(0.0, 0.0, -60.0)
	var mine: Array = _squad("warrior", Constants.FACTION_PLAYER, spot, 1, 1.0)
	var w: Unit = mine[1][0]
	await pframes(4)
	var base_speed: float = w._effective_speed()
	var guard0: bool = bool(w.get("_guard_active"))
	w.call("start_rage_dash")
	await pframes(4)
	var dash_speed: float = w._effective_speed()
	print("  шаг %.2f → %.2f м/с (×%.2f)" % [base_speed, dash_speed,
		dash_speed / maxf(base_speed, 0.01)])
	verdict("B1 в набеге боец идёт быстрее обычного",
		dash_speed > base_speed * 1.2,
		"×%.2f" % (dash_speed / maxf(base_speed, 0.01)))
	verdict("B2 и ровно во столько, во сколько заказано",
		absf(dash_speed / maxf(base_speed, 0.01) - Warrior.RAGE_SPEED_MULT) < 0.05,
		"×%.2f при заказанных ×%.2f" % [dash_speed / maxf(base_speed, 0.01),
			Warrior.RAGE_SPEED_MULT])
	# Щит поднимается БЕЗУСЛОВНО: режим включил сам игрок, и настройка
	# «закрываться самому» тут ни при чём
	w.call("_update_guard")
	await pframes(2)
	verdict("B3 щит поднят на всё время набега",
		bool(w.get("_guard_active")),
		"щит был %s, стал %s" % [str(guard0), str(w.get("_guard_active"))])
	verdict("B4 поза помечена грязной — картинка пересчитается в тот же кадр",
		bool(w.call("rage_active")))
	_kill(w)
	await pframes(4)

# ═════════════════════════════════════════════════════════════════════════════
# C. СЕРИЯ «МЕЧ → ЩИТ → МЕЧ → ЩИТ → МЕЧ»
# ═════════════════════════════════════════════════════════════════════════════
func _c_series() -> void:
	print("\n═════ C. СЕРИЯ УДАРОВ ═════")
	var spot: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(60.0, 0.0, 0.0)
	var mine: Array = _squad("warrior", Constants.FACTION_PLAYER, spot, 1, 1.0)
	var w: Unit = mine[1][0]
	await pframes(4)
	var cd_base: float = w._effective_cooldown()
	w.call("start_rage_dash")
	var cd_rage: float = w._effective_cooldown()
	verdict("C1 удары серии быстрее обычных",
		cd_rage < cd_base * 0.9,
		"%.2f против %.2f с" % [cd_rage, cd_base])
	# Прогоняем серию вручную: _strike_damage и есть то место, где ротация
	# решается, и звать его напрямую честнее, чем ждать случайной свалки
	var seq: Array = []
	for _i in range(Warrior.RAGE_HITS):
		var before: int = int(w.get("rage_strong_done"))
		w.call("_strike_damage")
		seq.append(int(w.get("rage_strong_done")) > before)
	print("  серия: %s (заказано %s)" % [str(seq), str(Warrior.RAGE_STRONG)])
	var want: Array = []
	for f in Warrior.RAGE_STRONG:
		want.append(bool(f))
	verdict("C2 серия ровно та, что заказана: меч → щит → меч → щит → меч",
		seq == want,
		"вышло %s, ждали %s" % [str(seq), str(want)])
	verdict("C3 ударов в серии ровно %d" % Warrior.RAGE_HITS,
		int(w.get("rage_hits_done")) == Warrior.RAGE_HITS,
		"нанесено %d" % int(w.get("rage_hits_done")))
	verdict("C4 серия исчерпана — приём кончился сам",
		not bool(w.call("rage_active")),
		"набег %s" % str(w.call("rage_active")))
	verdict("C5 и темп удара вернулся к обычному",
		absf(w._effective_cooldown() - cd_base) < 0.01,
		"%.2f против %.2f с" % [w._effective_cooldown(), cd_base])
	_kill(w)
	await pframes(4)

# ═════════════════════════════════════════════════════════════════════════════
# D. ТОЛЧОК ЩИТАМИ — ГЛАВНОЕ ТРЕБОВАНИЕ СПРИНТА
#
# Толчок идёт НА КАЖДЫЙ удар (Unit.PUSH_EVERY = 1), а множитель применяется
# ПОСЛЕ потолка шага — голый push_force потолком съедается (разбор в
# Unit._apply_push). Поэтому проверяется и множитель, и живой отъезд жертвы
# ═════════════════════════════════════════════════════════════════════════════
func _d_push() -> void:
	print("\n═════ D. МОЩНЫЙ ТОЛЧОК ═════")
	var spot: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(-60.0, 0.0, 0.0)
	var mine: Array = _squad("warrior", Constants.FACTION_PLAYER, spot, 1, 1.0)
	var w: Unit = mine[1][0]
	await pframes(4)
	var p_base: float = w.call("_push_power")
	w.call("start_rage_dash")
	var p_rage: float = w.call("_push_power")
	print("  напор %.2f → %.2f (×%.2f, заказано ×%.2f)" % [
		p_base, p_rage, p_rage / maxf(p_base, 0.01), Warrior.RAGE_PUSH_MULT])
	verdict("D1 напор в набеге выше обычного",
		p_rage > p_base * 1.5, "×%.2f" % (p_rage / maxf(p_base, 0.01)))
	verdict("D2 и ровно во столько, во сколько заказано",
		absf(p_rage / maxf(p_base, 0.01) - Warrior.RAGE_PUSH_MULT) < 0.05,
		"×%.2f при заказанных ×%.2f" % [p_rage / maxf(p_base, 0.01),
			Warrior.RAGE_PUSH_MULT])
	verdict("D3 толчок идёт на КАЖДЫЙ удар — серия читается одним навалом",
		int(w.get("push_every")) == 1, "раз в %d ударов" % int(w.get("push_every")))
	_kill(w)
	await pframes(4)

	# ── ЖИВОЙ ЗАМЕР: ТУ ЖЕ ЖЕРТВУ ТОЛКАЮТ ДВАЖДЫ, С НАБЕГОМ И БЕЗ ──────────
	# Сцена одна и та же, разница только в приёме: иначе замер судил бы о
	# разнице площадок, а не о толчке
	var plain: float = await _push_probe(false)
	var raged: float = await _push_probe(true)
	print("  жертву отодвинуло: без набега %.2f м, в набеге %.2f м" % [
		plain, raged])
	verdict("D4 в набеге строй противника отъезжает заметно дальше",
		raged > plain * 1.5,
		"%.2f против %.2f м" % [raged, plain])

## Насколько сдвинется жертва за одинаковое число ударов. rage — включать ли
## набег. Возвращает пройденные метры
func _push_probe(rage: bool) -> float:
	var spot: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(-60.0, 0.0, 40.0)
	var mine: Array = _squad("warrior", Constants.FACTION_PLAYER, spot, 1, 1.0)
	var w: Unit = mine[1][0]
	var foe: Array = _squad("spearman", Constants.FACTION_ENEMY,
		spot + Vector3(1.2, 0.0, 0.0), 1, 1.0)
	var v: Unit = foe[1][0]
	await pframes(4)
	# ── ЖЕРТВА ТИКАЕТ, И ЭТО ОБЯЗАТЕЛЬНО ───────────────────────────────────
	# Тяжёлый толчок едет ПЛАВНЫМ КАНАЛОМ (Unit.push_smooth): скорость кладут
	# жертве, а интегрирует её ЕЁ ЖЕ физический тик. Замороженная жертва не
	# сдвигается ни на сантиметр — первая версия зонда так и намеряла «в
	# набеге 0.00 м» на работающем толчке. Бессмертной она остаётся: меряется
	# ТОЛЧОК, а не исход схватки
	v.current_health = v.max_health * 5000.0
	if rage:
		w.call("start_rage_dash")
	var from: Vector3 = v.global_position
	for _i in range(Warrior.RAGE_HITS):
		w.call("_apply_push", v, Vector3(1.0, 0.0, 0.0))
		await pframes(2)
	# ── ПЛАВНОМУ ТОЛЧКУ НАДО ДАТЬ ДОЕХАТЬ ─────────────────────────────────
	# Тяжёлый навал кладёт жертве СКОРОСТЬ (push_smooth), и та гасится за
	# доли секунды её же тиком; обычный пехотный толчок переносит точку сразу.
	# Мерить оба в один и тот же кадр значит сравнивать законченное движение
	# с начатым — зонд ждёт, пока скорость погаснет
	await pframes(60)
	var moved: float = Vector2(v.global_position.x - from.x,
		v.global_position.z - from.z).length()
	_kill(w)
	_kill(v)
	await pframes(4)
	return moved

# ═════════════════════════════════════════════════════════════════════════════
# E. «НАТИСК ФАЛАНГИ»: ДВЕ ФАЗЫ, СОМКНУТЫЙ СТРОЙ, КОПЬЯ ВПЕРЁД
# ═════════════════════════════════════════════════════════════════════════════
func _e_phalanx() -> void:
	print("\n═════ E. НАТИСК ФАЛАНГИ ═════")
	var spot: Vector3 = _flat_spot(
		main.PLAYER_BASE_ANCHOR + Vector3(60.0, 0.0, 60.0), 12.0)
	var mine: Array = _squad("spearman", Constants.FACTION_PLAYER, spot, 8, 1.0)
	var sid: int = mine[0]
	var men: Array = mine[1]
	var foe: Array = _squad("warrior", Constants.FACTION_ENEMY,
		spot + Vector3(20.0, 0.0, 0.0), 6, 1.0)
	var foes: Array = foe[1]
	await pframes(6)
	for f in foes:
		(f as Unit).set_tick(false)
		(f as Unit).current_health = (f as Unit).max_health * 500.0
	verdict("E0 приём открыт кузницей и включён по умолчанию",
		GameManager.squad_has_ability(sid, "spearman_4d")
			and GameManager.squad_ability_on(sid, "spearman_4d"))

	var s: Unit = men[0]
	var speed0: float = s._effective_speed()
	# Двойной ПКМ по врагу: приказ атаки плюс раздача приёма
	sm.selected_units.clear()
	for u in men:
		sm.selected_units.append(u)
	sm._sel_rebuild()
	await pframes(2)
	var cam: Camera3D = main.get("_camera") as Camera3D
	main.focus_camera_on((foes[0] as Node3D).global_position)
	await pframes(8)
	await frames(4)
	main.set_process(false)
	cam.set_process(false)
	await frames(2)
	var scr: Vector2 = cam.unproject_position(
		(foes[0] as Node3D).global_position + Vector3(0.0, 0.9, 0.0))
	sm._handle_right_click(scr, true)
	await pframes(3)
	main.set_process(true)
	cam.set_process(true)

	var pushing := 0
	for u in men:
		if bool((u as Object).call("phalanx_push_active")):
			pushing += 1
	verdict("E1 двойной ПКМ включает натиск всему отряду",
		pushing == men.size(), "в натиске %d из %d" % [pushing, men.size()])
	var speed1: float = s._effective_speed()
	print("  шаг фаланги %.2f → %.2f м/с (×%.2f)" % [speed0, speed1,
		speed1 / maxf(speed0, 0.01)])
	verdict("E2 строй идёт МЕДЛЕННЕЕ обычного — слаженно, а не бегом",
		speed1 < speed0 and absf(speed1 / maxf(speed0, 0.01)
			- Spearman.PHALANX_PUSH_SPEED) < 0.05,
		"×%.2f при заказанных ×%.2f" % [speed1 / maxf(speed0, 0.01),
			Spearman.PHALANX_PUSH_SPEED])
	verdict("E3 бег двойным ПКМ фалангу не распускает — копья остаются делом",
		not bool(s.get("sprinting")),
		"бежит=%s" % str(s.get("sprinting")))
	verdict("E4 приказ атаки принят и цель назначена",
		s.attack_target != null)
	# ── КОПЬЯ ВПЕРЁД ───────────────────────────────────────────────────────
	# Копьё опускают ПЕРВЫЕ шеренги и только при бое или приказе атаки; сам
	# признак считается внутри _spear_leveled
	var leveled := 0
	for _i in range(90):
		await get_tree().physics_frame
		leveled = 0
		for u in men:
			if bool((u as Object).call("_spear_leveled")):
				leveled += 1
		if leveled > 0:
			break
	verdict("E5 копья опущены вперёд", leveled > 0,
		"опустили %d из %d" % [leveled, men.size()])

	# ── ФАЗА 1: СЕРИЯ УСИЛЕННЫХ УДАРОВ ─────────────────────────────────────
	var strong := 0
	for _i in range(Spearman.PHALANX_PUSH_HITS):
		s.call("_strike_damage")
		strong += 1
	verdict("E6 серия усиленных ударов ровно та, что заказана",
		int(s.get("push_hits_done")) == Spearman.PHALANX_PUSH_HITS,
		"усиленных %d из %d" % [int(s.get("push_hits_done")),
			Spearman.PHALANX_PUSH_HITS])
	# ── ФАЗА 2: ОТТЕСНЕНИЕ ─────────────────────────────────────────────────
	verdict("E7 серия исчерпана — начинается ОТТЕСНЕНИЕ, а не выход из режима",
		bool(s.call("phalanx_wall_active"))
			and bool(s.call("phalanx_push_active")),
		"оттеснение=%s, натиск=%s" % [str(s.call("phalanx_wall_active")),
			str(s.call("phalanx_push_active"))])
	var s2: Unit = men[1]
	print("  напор: обычный %.2f, в оттеснении %.2f (×%.2f)" % [
		s2.call("_push_power"), s.call("_push_power"),
		float(s.call("_push_power")) / maxf(float(s2.call("_push_power")), 0.01)])
	verdict("E8 в оттеснении напор выше — строй методично двигает врага",
		float(s.call("_push_power")) > float(s2.call("_push_power")) * 1.5,
		"×%.2f" % (float(s.call("_push_power"))
			/ maxf(float(s2.call("_push_power")), 0.01)))
	verdict("E9 и входящий урон ниже — сомкнутый строй держит удар",
		float(s.call("_incoming_damage_factor", foes[0]))
			< float(s2.call("_incoming_damage_factor", foes[0])),
		"%.2f против %.2f" % [s.call("_incoming_damage_factor", foes[0]),
			s2.call("_incoming_damage_factor", foes[0])])
	sm.selected_units.clear()
	sm._sel_rebuild()
	for u in men:
		_kill(u)
	for f in foes:
		_kill(f)
	await pframes(4)

# ═════════════════════════════════════════════════════════════════════════════
func _kill(u: Node) -> void:
	if u == null or not is_instance_valid(u):
		return
	var un := u as Unit
	if un != null and not un.is_dead():
		un.take_damage(maxf(un.max_health, un.current_health) * 10.0, null)
