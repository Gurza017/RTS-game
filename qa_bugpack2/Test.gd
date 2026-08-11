extends Node

## ═════════════════════════════════════════════════════════════════════════════
## СТЕНД «НЕЗАКРЫТЫЕ КРАЯ» ПАКЕТА БАГФИКСОВ
##
## qa_bugpack/Test.tscn проверяет ОСНОВНЫЕ сценарии (37 проверок). Здесь —
## только то, что там НЕ покрыто: краевые случаи, обратные условия и замеры.
##
##   1 СТОЙКА    — прямой приказ стойку меняет, авто-агро и урон — НЕТ
##   2 БЕГ       — Warrior/Archer не машут оружием на бегу; лучник не гонится
##   3 КЛИКИ     — верхушка замка, пустая земля, боец перед зданием, враг
##   4 РАКУРС    — все 8 секторов, гистерезис при облёте, замер сна
##   5 ГАРНИЗОН  — ПОЛНЫЙ ЗДОРОВЫЙ отряд: нет мигания «зашёл-вышел»
##   6 БЛОКИ     — 1 отряд, 5 отрядов на короткой линии, разные размеры,
##                 отряд + одиночки, совпадение превью и приказа
##   7 ИИ        — патрули реально ходят, звёзды реально усиливают, нет вечного while
##   8 ОЗЕРО     — рабочий с грузом за озером, приказ в воду, юнит В воде
##   9 ЗАМЕРЫ    — 200 лучников (агро-скан) и 300 копейщиков в защите (спрайты)
## ═════════════════════════════════════════════════════════════════════════════

const _UCfg  := preload("res://scripts/unit_stats_config.gd")
const _PerfCfg := preload("res://scripts/perf_config.gd")
const _AICfg := preload("res://scripts/ai_start_army_limit.gd")

var main = null
var verdicts: Array = []

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func verdict(title: String, ok: bool, detail: String = "") -> void:
	verdicts.append([title, ok])
	print("  ВЕРДИКТ %s: %s%s" % [title, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + detail) if detail != "" else ""])

func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	# СТЕНД РАБОТАЕТ ЗА ПРЕДЕЛАМИ КАРТЫ: площадки вынесены далеко в сторону,
	# чтобы ни ИИ, ни лес, ни чужие отряды не мешали замеру. Жёсткая граница
	# мира стянула бы их все в угол поля — на время стенда её снимаем
	GameManager.world_bounds_enabled = false
	# И ОТСЕЧЕНИЕ ДАЛЬНИХ СПРАЙТОВ ТОЖЕ: площадки стенда вынесены за сотни
	# метров от точки обзора, поэтому LOD честно перестаёт считать им позу.
	# Проверки ракурса и поз должны видеть спрайты живыми
	_PerfCfg.sprite_lod = false
	await frames(2)
	for t in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD,
			Constants.RESOURCE_STONE, Constants.RESOURCE_FOOD]:
		ResourceManager.add_resource(Constants.FACTION_PLAYER, int(t), 100000.0)
	await frames(1)

	await _t1_stance_not_broken()
	await _t2_no_swing_on_run()
	await _t3_pick_edges()
	await _t4_sprite_sectors()
	await _t5_garrison_full_healthy()
	await _t6_block_edges()
	await _t7_defensive_ai_live()
	await _t8_lake_edges()
	await _t9_perf()

	_summary()
	print("\n=== BUGPACK2 TEST DONE ===")
	get_tree().quit()

func _summary() -> void:
	print("\n═════ ИТОГ ═════")
	var bad := 0
	for v in verdicts:
		var row: Array = v
		if not bool(row[1]):
			bad += 1
		print("  %-62s %s" % [String(row[0]), "ПРОШЛО" if bool(row[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [bad, verdicts.size()])

# ── помощники ────────────────────────────────────────────────────────────────

func _spawn(unit_id: String, f: int) -> Unit:
	var u: Unit
	match unit_id:
		"spearman": u = Spearman.new()
		"archer":   u = Archer.new()
		"warrior":  u = Warrior.new()
		_:          u = Worker.new()
	u.faction = f
	main.world_add(u)
	return u

func _squad(unit_id: String, n: int, at: Vector3, f: int = Constants.FACTION_PLAYER) -> Dictionary:
	var sid: int = GameManager.new_squad(f, unit_id)
	var units: Array = []
	for i in range(n):
		var u := _spawn(unit_id, f)
		u.global_position = at + Vector3(float(i % 5) * 0.6, 0.0, float(i / 5) * 0.6)
		GameManager.add_to_squad(sid, u)
		units.append(u)
	return {"sid": sid, "units": units}

func _kill(units: Array) -> void:
	for u in units:
		if is_instance_valid(u):
			u.queue_free()

# ═════════════════════════════════════════════════════════════════════════════
# 1. СТОЙКА ЗАЩИТА: ПРИКАЗ ЕЁ МЕНЯЕТ, АВТО-АГРО И УРОН — НЕТ
# ═════════════════════════════════════════════════════════════════════════════
# command_attack(forced=true) теперь переводит бойца из ЗАЩИТЫ в АТАКУ.
# Обратная сторона: если бы этот же путь дёргали авто-агро или ответ на урон,
# рубеж расползся бы сам собой. Оба обязаны идти с forced=false.
func _t1_stance_not_broken() -> void:
	print("\n═════ 1. СТОЙКА ЗАЩИТА ПРОТИВ АВТО-АГРО И УРОНА ═════")
	var base := Vector3(-800.0, 0.0, -800.0)
	var d := _spawn("spearman", Constants.FACTION_PLAYER)
	d.global_position = base
	# Враг тоже в защите — иначе он сам побежит и испортит замер дистанции
	var e := _spawn("spearman", Constants.FACTION_ENEMY)
	e.global_position = base + Vector3(6.0, 0.0, 0.0)
	await frames(3)
	d.set_stance(_UCfg.STANCE_DEFENSE)
	e.set_stance(_UCfg.STANCE_DEFENSE)
	await frames(2)
	var p0: Vector3 = d.global_position
	print("  дальность удара %.2f м, агро-радиус %.1f м, дистанция до врага %.1f м" % [
		d.attack_range, d.AGGRO_RADIUS, p0.distance_to(e.global_position)])

	# (а) враг в агро-радиусе, но вне удара — авто-агро НЕ должен сменить стойку
	d._aggro_timer = 0.0
	await frames(40)
	var moved_a: float = p0.distance_to(d.global_position)
	print("  после 40 кадров рядом с врагом: стойка=«%s», сдвиг %.3f м, состояние=%d" % [
		d.stance, moved_a, d.state])
	verdict("1a авто-агро НЕ выбивает бойца из стойки ЗАЩИТА",
		d.stance == _UCfg.STANCE_DEFENSE, "стойка «%s»" % d.stance)
	verdict("1b в защите боец не сходит с места ради дальнего врага",
		moved_a < 0.3, "сдвинулся на %.3f м" % moved_a)

	# (б) обстрел ИЗДАЛЕКА (атакующий вне радиуса удара) — тоже не меняет стойку
	d.take_damage(5.0, e)
	await frames(6)
	print("  после урона с 6 м: стойка=«%s», цель=%s, принудительный приказ=%s" % [
		d.stance, str(d.attack_target != null), str(d._attack_is_forced)])
	verdict("1c урон издалека не меняет стойку и не срывает с места",
		d.stance == _UCfg.STANCE_DEFENSE and d.attack_target == null,
		"стойка «%s», цель=%s" % [d.stance, str(d.attack_target != null)])

	# (в) враг ВПЛОТНУЮ: боец отвечает, но остаётся в защите и не преследует
	e.global_position = d.global_position + Vector3(1.0, 0.0, 0.0)
	await frames(3)
	d.state = Unit.State.IDLE
	d.take_damage(5.0, e)
	await frames(4)
	print("  после урона вплотную: стойка=«%s», есть цель=%s, forced=%s" % [
		d.stance, str(d.attack_target != null), str(d._attack_is_forced)])
	verdict("1d ответ на удар вплотную идёт БЕЗ смены стойки",
		d.stance == _UCfg.STANCE_DEFENSE and d.attack_target != null
			and not d._attack_is_forced,
		"стойка «%s», forced=%s" % [d.stance, str(d._attack_is_forced)])

	# (г) а вот ПРЯМОЙ приказ обязан вывести из защиты (это и чинили)
	d.command_attack(e)
	await frames(2)
	print("  после прямого приказа атаковать: стойка=«%s», forced=%s" % [
		d.stance, str(d._attack_is_forced)])
	verdict("1e прямой приказ переводит из ЗАЩИТЫ в АТАКУ",
		d.stance == _UCfg.STANCE_ATTACK and d._attack_is_forced,
		"стойка «%s», forced=%s" % [d.stance, str(d._attack_is_forced)])
	_kill([d, e])
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# 2. НА БЕГУ ОРУЖИЕМ НЕ МАШУТ (Warrior, Archer) + ЛУЧНИК НЕ ГОНИТСЯ
# ═════════════════════════════════════════════════════════════════════════════
func _t2_no_swing_on_run() -> void:
	print("\n═════ 2. WARRIOR / ARCHER: УДАР ТОЛЬКО В ЗОНЕ ПОРАЖЕНИЯ ═════")
	var base := Vector3(-900.0, 0.0, -900.0)

	# ── Мечник бежит к далёкой цели ──────────────────────────────────────────
	var w := _spawn("warrior", Constants.FACTION_PLAYER) as Warrior
	w.global_position = base
	var wt := _spawn("spearman", Constants.FACTION_ENEMY)
	wt.global_position = base + Vector3(14.0, 0.0, 0.0)
	wt.set_stance(_UCfg.STANCE_DEFENSE)
	await frames(3)
	w.command_attack(wt)
	await frames(10)
	var w_anim := ""
	var wasp := w._active_sprite as AnimatedSprite3D
	if wasp != null:
		w_anim = String(wasp.animation)
	var w_locked: bool = Time.get_ticks_msec() < w._anim_lock_until_ms
	print("  мечник: в зоне=%s, анимация=«%s», блокировка удара=%s, комбо-шаг=%d" % [
		str(w.target_in_range()), w_anim, str(w_locked), w._combo_step])
	verdict("2a мечник на бегу к цели не проигрывает удар",
		not w.target_in_range() and not w_locked and not w_anim.begins_with("attack"),
		"анимация «%s», блок=%s" % [w_anim, str(w_locked)])

	# ── Лучник по прямому приказу тоже не «стреляет на бегу» ────────────────
	var a := _spawn("archer", Constants.FACTION_PLAYER) as Archer
	a.global_position = base + Vector3(0.0, 0.0, 40.0)
	var at := _spawn("spearman", Constants.FACTION_ENEMY)
	at.global_position = a.global_position + Vector3(35.0, 0.0, 0.0)   # 35 м > 20 м
	at.set_stance(_UCfg.STANCE_DEFENSE)
	await frames(3)
	var arrows0 := _count_arrows()
	a.command_attack(at)
	await frames(8)
	var a_anim := ""
	var aasp := a._active_sprite as AnimatedSprite3D
	if aasp != null:
		a_anim = String(aasp.animation)
	var arrows1 := _count_arrows()
	print("  лучник: дальность %.0f м, дистанция %.0f м, в зоне=%s, анимация=«%s», стрел выпущено=%d" % [
		a.attack_range, a.global_position.distance_to(at.global_position),
		str(a.target_in_range()), a_anim, arrows1 - arrows0])
	verdict("2b лучник вне дальности не стреляет и не тянет тетиву",
		not a.target_in_range() and arrows1 == arrows0 and not a_anim.begins_with("attack"),
		"стрел %d, анимация «%s»" % [arrows1 - arrows0, a_anim])

	# ── Лучник САМ берёт цель на 15 м и стреляет С МЕСТА ────────────────────
	var s := _spawn("archer", Constants.FACTION_PLAYER) as Archer
	s.global_position = base + Vector3(0.0, 0.0, 80.0)
	var st := _spawn("spearman", Constants.FACTION_ENEMY)
	st.global_position = s.global_position + Vector3(15.0, 0.0, 0.0)
	st.set_stance(_UCfg.STANCE_DEFENSE)
	await frames(3)
	var sp0: Vector3 = s.global_position
	s._aggro_timer = 0.0
	await frames(60)
	var s_moved: float = sp0.distance_to(s.global_position)
	print("  лучник в 15 м от врага: цель взята=%s, сдвиг %.3f м, forced=%s" % [
		str(s.attack_target != null), s_moved, str(s._attack_is_forced)])
	verdict("2c лучник сам открывает огонь на 15 м и НЕ бежит на цель",
		s.attack_target != null and s_moved < 0.3 and not s._attack_is_forced,
		"цель=%s, сдвиг %.3f м" % [str(s.attack_target != null), s_moved])

	# ── А вот на 25 м (за дальностью) цель браться НЕ должна ────────────────
	var f := _spawn("archer", Constants.FACTION_PLAYER) as Archer
	f.global_position = base + Vector3(0.0, 0.0, 140.0)
	var ft := _spawn("spearman", Constants.FACTION_ENEMY)
	ft.global_position = f.global_position + Vector3(25.0, 0.0, 0.0)
	ft.set_stance(_UCfg.STANCE_DEFENSE)
	await frames(3)
	var fp0: Vector3 = f.global_position
	f._aggro_timer = 0.0
	await frames(60)
	print("  лучник в 25 м от врага: цель взята=%s, сдвиг %.3f м" % [
		str(f.attack_target != null), fp0.distance_to(f.global_position)])
	verdict("2d за пределами дальности лучник цель НЕ берёт (не агрится через полкарты)",
		f.attack_target == null and fp0.distance_to(f.global_position) < 0.3,
		"цель=%s" % str(f.attack_target != null))

	_kill([w, wt, a, at, s, st, f, ft])
	await frames(3)

func _count_arrows() -> int:
	var n := 0
	for c in main.get_children():
		if c.get_script() != null and String(c.get_script().resource_path).ends_with("Arrow.gd"):
			n += 1
	return n

# ═════════════════════════════════════════════════════════════════════════════
# 3. РАЗБОР КЛИКА: КРАЕВЫЕ СЛУЧАИ
# ═════════════════════════════════════════════════════════════════════════════
func _t3_pick_edges() -> void:
	print("\n═════ 3. КЛИКИ: ЗАМОК, ПУСТАЯ ЗЕМЛЯ, БОЕЦ, ВРАГ ═════")
	var sm = main.selection_manager
	var cam: Camera3D = sm.camera
	var mask: int = Constants.LAYER_UNITS | Constants.LAYER_BUILDINGS \
		| Constants.LAYER_RESOURCES | Constants.LAYER_GROUND

	# КООРДИНАТЫ ОБЯЗАНЫ ЛЕЖАТЬ В ГРАНИЦАХ КАМЕРЫ (RTSCamera.bounds ±75):
	# _focus за пределами прижимается к границе, и объект уходит за экран —
	# unproject_position тогда даёт отрицательные координаты, а клик мимо.
	# Кроме того, в headless курсор стоит в (0,0), и камера каждый кадр ползёт
	# краевым скроллом, поэтому между наводкой и кликом кадров НЕ ждём.
	# ПЛОЩАДКА ОБЯЗАНА БЫТЬ ПУСТОЙ. (45,45) не годится: там база ИИ
	# (ENEMY_BASE_ANCHOR = 55,55, коробка замка 8×8 → клетки 51..59), и точка
	# «пустой земли» попадала ровно на габарит вражеского замка
	var spot := Vector3(-45.0, 0.0, 45.0)
	_clear_area(spot, 30.0)
	await frames(3)
	var castle := Castle.new()
	castle.faction = Constants.FACTION_PLAYER
	main.world_add(castle)
	castle.global_position = spot
	await frames(3)
	var half: float = maxf(castle.build_size.x, castle.build_size.z) * 0.5
	# Боец стоит вплотную к стене замка, СО СТОРОНЫ КАМЕРЫ
	var guard := _spawn("spearman", Constants.FACTION_PLAYER)
	guard.global_position = spot + Vector3(0.0, 0.0, half + 0.8)
	await frames(3)

	# (а) клик по ВЕРХУШКЕ замка — должен выбрать замок, а не бойца у стены
	cam._focus = spot
	cam._orbit_yaw = 0.0
	cam._update_position()
	var top: Vector2 = cam.unproject_position(spot + Vector3(0, castle.build_size.y * 0.95, 0))
	var p_top: Dictionary = sm._pick_at(top, mask)
	var t_top = p_top["target"]
	print("  габарит замка %.1f×%.1f×%.1f, боец в %.1f м от центра" % [
		castle.build_size.x, castle.build_size.y, castle.build_size.z,
		spot.distance_to(guard.global_position)])
	print("  клик по верхушке замка (%.0f,%.0f) выбрал: %s" % [
		top.x, top.y, _name_of(t_top)])
	verdict("3a клик по верхушке замка выбирает ЗАМОК, а не бойца у стены",
		t_top is Castle, "выбрано: %s" % _name_of(t_top))

	# (б) клик по самому бойцу — должен выбрать бойца, а не замок за ним
	cam._focus = spot
	cam._update_position()
	var gs: Vector2 = cam.unproject_position(guard.global_position + Vector3(0, 0.9, 0))
	var p_g: Dictionary = sm._pick_at(gs, mask)
	var t_g = p_g["target"]
	print("  клик по бойцу перед зданием (%.0f,%.0f) выбрал: %s" % [gs.x, gs.y, _name_of(t_g)])
	verdict("3b клик по бойцу перед зданием выбирает БОЙЦА",
		t_g is Unit, "выбрано: %s" % _name_of(t_g))

	# (в) клик по чистой земле — цели нет, но точка земли посчитана
	var empty_world := spot + Vector3(14.0, 0.0, 14.0)
	cam._focus = spot
	cam._update_position()
	var es: Vector2 = cam.unproject_position(empty_world)
	var p_e: Dictionary = sm._pick_at(es, mask)
	var e_pos: Vector3 = p_e["position"]
	print("  клик по пустой земле: цель=%s, точка (%.1f, %.1f), ждали (%.1f, %.1f)" % [
		_name_of(p_e["target"]), e_pos.x, e_pos.z, empty_world.x, empty_world.z])
	verdict("3c клик по пустой земле не выбирает ничего",
		p_e["target"] == null, "выбрано: %s" % _name_of(p_e["target"]))
	verdict("3d точка земли под курсором посчитана верно",
		Vector2(e_pos.x, e_pos.z).distance_to(Vector2(empty_world.x, empty_world.z)) < 1.5,
		"ошибка %.2f м" % Vector2(e_pos.x, e_pos.z).distance_to(
			Vector2(empty_world.x, empty_world.z)))

	# (г) клик по ВРАЖЕСКОМУ бойцу выбирается так же, как по своему
	var foe := _spawn("spearman", Constants.FACTION_ENEMY)
	foe.global_position = spot + Vector3(12.0, 0.0, 12.0)
	await frames(3)
	cam._focus = spot
	cam._update_position()
	var fs: Vector2 = cam.unproject_position(foe.global_position + Vector3(0, 0.9, 0))
	var p_f: Dictionary = sm._pick_at(fs, mask)
	var t_f = p_f["target"]
	print("  клик по вражескому бойцу выбрал: %s (фракция %s)" % [
		_name_of(t_f), str(t_f.faction) if t_f != null else "—"])
	verdict("3e вражеская цель выбирается кликом",
		t_f is Unit and (t_f as Unit).faction == Constants.FACTION_ENEMY,
		"выбрано: %s" % _name_of(t_f))

	# (е) боец, стоящий ВНУТРИ габарита замка (маски столкновений нулевые,
	# бойцы свободно ходят сквозь постройки) — клик обязан выбрать бойца
	var inside := _spawn("spearman", Constants.FACTION_PLAYER)
	inside.global_position = spot + Vector3(1.5, 0.0, 1.5)
	await frames(3)
	cam._focus = spot
	cam._update_position()
	var is_pos: Vector2 = cam.unproject_position(inside.global_position + Vector3(0, 0.9, 0))
	var p_i: Dictionary = sm._pick_at(is_pos, mask)
	var t_i = p_i["target"]
	print("  боец внутри коробки замка (отступ 1.5 м от центра) выбран как: %s" % _name_of(t_i))
	verdict("3g боец на габарите здания всё равно выбирается кликом",
		t_i is Unit, "выбрано: %s" % _name_of(t_i))

	# (ж) при этом сам замок кликом по свободному углу габарита не потерян
	cam._focus = spot
	cam._update_position()
	var corner: Vector2 = cam.unproject_position(spot + Vector3(-3.0, 0.0, -3.0))
	var p_k: Dictionary = sm._pick_at(corner, mask)
	print("  клик по свободному углу габарита замка выбрал: %s" % _name_of(p_k["target"]))
	verdict("3h клик по свободной части габарита по-прежнему выбирает здание",
		p_k["target"] is Castle, "выбрано: %s" % _name_of(p_k["target"]))
	_kill([inside])
	await frames(3)

	# (д) клик по КРОНЕ дерева, когда рядом НЕТ золота — дерево обязано остаться
	var tspot := Vector3(45.0, 0.0, -45.0)
	_clear_area(tspot, 12.0)
	await frames(3)
	var tree := ResourceNode.new()
	tree.resource_type = Constants.RESOURCE_WOOD
	main.world_add(tree)
	tree.global_position = tspot
	await frames(3)
	cam._focus = tspot
	cam._update_position()
	var crown: Vector2 = cam.unproject_position(tspot + Vector3(0, 3.6, 0))
	var p_c: Dictionary = sm._pick_at(crown, mask)
	var t_c = p_c["target"]
	print("  клик по кроне одиноко стоящего дерева выбрал: %s" % _name_of(t_c))
	verdict("3f клик по кроне без золота рядом всё ещё выбирает дерево",
		t_c is ResourceNode and (t_c as ResourceNode).resource_type == Constants.RESOURCE_WOOD,
		"выбрано: %s" % _name_of(t_c))

	tree.queue_free()
	castle.queue_free()
	_kill([guard, foe])
	await frames(3)

## Освободить площадку: карта уже застроена (базы, жилы, лес), и рядом с ними
## «пустой земли» не бывает — проверка кликов требует чистого поля
func _clear_area(center: Vector3, radius: float) -> void:
	var c2 := Vector2(center.x, center.z)
	for grp in ["all_buildings", "resource_nodes", "all_units"]:
		for n in get_tree().get_nodes_in_group(grp):
			var n3 := n as Node3D
			if n3 == null:
				continue
			if Vector2(n3.global_position.x, n3.global_position.z).distance_to(c2) <= radius:
				n3.queue_free()

func _name_of(n) -> String:
	if n == null:
		return "ничего"
	if n is Castle:
		return "замок"
	if n is Building:
		return "здание"
	if n is ResourceNode:
		var r := n as ResourceNode
		return "дерево" if r.resource_type == Constants.RESOURCE_WOOD else "ресурс"
	if n is Unit:
		return "боец"
	return String(n.name)

# ═════════════════════════════════════════════════════════════════════════════
# 4. РАКУРС СПРАЙТА: ВСЕ 8 СЕКТОРОВ И ГИСТЕРЕЗИС ПРИ ОБЛЁТЕ
# ═════════════════════════════════════════════════════════════════════════════
func _t4_sprite_sectors() -> void:
	print("\n═════ 4. ВОСЕМЬ СЕКТОРОВ РАКУРСА И ГИСТЕРЕЗИС ═════")
	var cam: Camera3D = main.selection_manager.camera
	var u := _spawn("spearman", Constants.FACTION_PLAYER) as Spearman
	u.global_position = Vector3(1000.0, 0.0, 1000.0)
	await frames(3)
	cam._focus = u.global_position
	cam._orbit_yaw = 0.0
	cam._update_position()
	await frames(2)

	# (а) восемь мировых направлений при неподвижной камере обязаны дать
	#     восемь РАЗНЫХ пар (лист, зеркало)
	var seen: Dictionary = {}
	var line := ""
	for i in range(8):
		var ang: float = TAU * float(i) / 8.0
		var dirv := Vector3(cos(ang), 0.0, sin(ang))
		u._cur_sector = -1                      # гистерезис не должен мешать замеру
		var r: Array = u._facing_to_dir_key(dirv)
		var key: String = "%s|%s" % [String(r[0]), str(r[1])]
		seen[key] = true
		line += "%d°→%s%s  " % [int(round(rad_to_deg(ang))), String(r[0]),
			"(зерк)" if bool(r[1]) else ""]
	print("  " + line)
	verdict("4a все 8 секторов дают 8 разных ракурсов", seen.size() == 8,
		"различных ракурсов %d" % seen.size())

	# (б) ОБЛЁТ КАМЕРЫ мелким шагом. Сектор обязан меняться ~8 раз за оборот;
	#     без гистерезиса на границах он «дребезжит» и смен становится втрое больше
	var facing := Vector3(0.0, 0.0, -1.0)
	u._cur_sector = -1
	var switches := 0
	var prev := ""
	var steps := 360
	for i in range(steps):
		cam._orbit_yaw = float(i)
		cam._update_position()
		var rr: Array = u._facing_to_dir_key(facing)
		var k: String = "%s|%s" % [String(rr[0]), str(rr[1])]
		if prev != "" and k != prev:
			switches += 1
		prev = k
	print("  оборот камеры на 360° шагом 1°: смен ракурса %d (идеал 8, порог дребезга 12)" % switches)
	verdict("4b гистерезис не даёт мерцания на границах секторов",
		switches <= 12, "смен %d за оборот" % switches)

	# (в) при ОДНОМ И ТОМ ЖЕ ракурсе повторный вызов не должен «прыгать»
	cam._orbit_yaw = 22.5     # ровно граница секторов
	cam._update_position()
	u._cur_sector = -1
	var first: Array = u._facing_to_dir_key(facing)
	var jitter := 0
	for _i in range(50):
		var rr2: Array = u._facing_to_dir_key(facing)
		if String(rr2[0]) != String(first[0]) or bool(rr2[1]) != bool(first[1]):
			jitter += 1
	print("  50 пересчётов ровно на границе сектора: расхождений %d" % jitter)
	verdict("4c на границе сектора ракурс стабилен", jitter == 0,
		"расхождений %d" % jitter)

	cam._orbit_yaw = 0.0
	cam._update_position()
	_kill([u])
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# 5. ГАРНИЗОН: ПОЛНЫЙ И ЗДОРОВЫЙ ОТРЯД
# ═════════════════════════════════════════════════════════════════════════════
# Отряд без потерь и без ран заводить в замок бессмысленно, но игрок это сделает.
# Опасность: авто-выход сработает в тот же тик — «зашёл-вышел», а если приказ
# движения снова заведёт бойцов в радиус входа, начнётся вечное мигание.
func _t5_garrison_full_healthy() -> void:
	print("\n═════ 5. ГАРНИЗОН: ПОЛНЫЙ ЗДОРОВЫЙ ОТРЯД ═════")
	var castle := Castle.new()
	castle.faction = Constants.FACTION_PLAYER
	main.world_add(castle)
	castle.global_position = Vector3(1200.0, 0.0, 1200.0)
	await frames(3)

	var full: int = _UCfg.squad_size("spearman")
	var sq := _squad("spearman", full, castle.global_position + Vector3(2.0, 0.0, 0.0))
	await frames(3)
	print("  отряд из %d бойцов, ВСЕ на полном здоровье, радиус входа %.1f м" % [
		full, _UCfg.GARRISON_ENTER_RADIUS])

	var ok1: bool = castle.request_garrison(int(sq["sid"]))
	# Повторный запрос не должен задваивать запись
	var ok2: bool = castle.request_garrison(int(sq["sid"]))
	print("  request_garrison: первый=%s, повторный=%s, _incoming=%d" % [
		str(ok1), str(ok2), castle._incoming.size()])
	verdict("5a повторный запрос не задваивает очередь на вход",
		castle._incoming.size() <= 1, "_incoming=%d" % castle._incoming.size())

	# Считаем ПЕРЕХОДЫ «внутри ↔ снаружи» за 8 секунд
	var enters := 0
	var exits  := 0
	var was_inside := false
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 8000:
		await frames(4)
		var inside: bool = not castle.garrison.is_empty()
		if inside and not was_inside:
			enters += 1
		elif not inside and was_inside:
			exits += 1
		was_inside = inside
	var outside := 0
	var hp_ok := 0
	for m in sq["units"]:
		if not is_instance_valid(m):
			continue
		var u: Unit = m
		if not u.garrisoned:
			outside += 1
		if u.current_health >= u.max_health - 0.01:
			hp_ok += 1
	print("  за 8 с: заходов внутрь=%d, выходов наружу=%d; снаружи %d из %d, здоровы %d" % [
		enters, exits, outside, full, hp_ok])
	print("  остаток: garrison=%d, _incoming=%d" % [castle.garrison.size(), castle._incoming.size()])
	verdict("5b полный здоровый отряд не мигает «зашёл-вышел»",
		enters <= 1, "заходов внутрь %d" % enters)
	verdict("5c после авто-выхода отряд снаружи целиком",
		outside == full, "снаружи %d из %d" % [outside, full])
	verdict("5d очередь на вход не зависла",
		castle._incoming.is_empty(), "_incoming=%d" % castle._incoming.size())
	verdict("5e бойцы не потеряли здоровье в замке", hp_ok == full,
		"здоровых %d из %d" % [hp_ok, full])

	_kill(sq["units"])
	castle.queue_free()
	await frames(3)

# ═════════════════════════════════════════════════════════════════════════════
# 6. ФОРМАЦИЯ БЛОКАМИ: КРАЕВЫЕ РАСКЛАДЫ
# ═════════════════════════════════════════════════════════════════════════════
func _t6_block_edges() -> void:
	print("\n═════ 6. БЛОКИ: 1 ОТРЯД, 5 НА КОРОТКОЙ ЛИНИИ, РАЗНЫЕ РАЗМЕРЫ, СМЕСЬ ═════")
	var sm = main.selection_manager
	var base := Vector3(1500.0, 0.0, 1500.0)

	# ── (а) ОДИН отряд: блок ровно один, слоты у всех разные ────────────────
	var one := _squad("spearman", 12, base)
	await frames(3)
	var m1: Array = one["units"]
	var blocks1: Array = sm._split_into_blocks(m1)
	var plan1: Dictionary = sm._block_formation_slots(
		base + Vector3(10.0, 0.0, -10.0), base + Vector3(10.0, 0.0, 10.0), m1)
	var s1: Array = plan1["slots"]
	var uniq1: Dictionary = {}
	for s in s1:
		var v: Vector3 = s
		uniq1["%.2f|%.2f" % [v.x, v.z]] = true
	print("  1 отряд ×12: блоков=%d, слотов=%d, различных позиций=%d" % [
		blocks1.size(), s1.size(), uniq1.size()])
	verdict("6a один отряд не ломает разбиение на блоки",
		blocks1.size() == 1 and s1.size() == 12 and uniq1.size() == 12,
		"блоков %d, слотов %d, уникальных %d" % [blocks1.size(), s1.size(), uniq1.size()])

	# ── (б) ПЯТЬ отрядов на КОРОТКОЙ линии (3 м) ────────────────────────────
	var five: Array = []
	var units5: Array = []
	for i in range(5):
		var sqd := _squad("spearman", 6, base + Vector3(0.0, 0.0, 40.0 + float(i) * 5.0))
		five.append(sqd)
		units5.append_array(sqd["units"])
	await frames(3)
	var short_a := base + Vector3(30.0, 0.0, 40.0)
	var short_b := short_a + Vector3(0.0, 0.0, 3.0)      # линия ВСЕГО 3 м
	var plan5: Dictionary = sm._block_formation_slots(short_a, short_b, units5)
	var s5: Array = plan5["slots"]
	var r5: Array = plan5["rows"]
	var bad5 := 0
	for s in s5:
		var v: Vector3 = s
		if not (is_finite(v.x) and is_finite(v.y) and is_finite(v.z)):
			bad5 += 1
	var maxrow := 0
	for r in r5:
		maxrow = maxi(maxrow, int(r))
	print("  5 отрядов ×6 на линии 3 м: слотов=%d (ждали %d), рядов=%d, некорректных координат=%d, макс. ряд=%d" % [
		s5.size(), units5.size(), r5.size(), bad5, maxrow])
	verdict("6b пять отрядов на короткой линии: слоты считаются без сбоя",
		s5.size() == units5.size() and r5.size() == units5.size() and bad5 == 0,
		"слотов %d, битых %d" % [s5.size(), bad5])

	# Приказ по этой же короткой линии не должен ронять игру и терять бойцов
	sm.selected_units = units5.duplicate()
	sm._execute_line_formation(short_a, short_b)
	await frames(3)
	var ordered := 0
	for m in units5:
		var u: Unit = m
		if u.state == Unit.State.MOVING:
			ordered += 1
	print("  приказ по короткой линии получили %d из %d бойцов" % [ordered, units5.size()])
	verdict("6c приказ по короткой линии доходит до всех",
		ordered == units5.size(), "получили %d из %d" % [ordered, units5.size()])
	sm.selected_units = []

	# ── (в) ОТРЯДЫ РАЗНОГО РАЗМЕРА: ширина секции пропорциональна составу ──
	var big := _squad("spearman", 20, base + Vector3(0.0, 0.0, 90.0))
	var small := _squad("archer", 5, base + Vector3(0.0, 0.0, 100.0))
	await frames(3)
	var mixed: Array = []
	mixed.append_array(big["units"])
	mixed.append_array(small["units"])
	var la := base + Vector3(60.0, 0.0, 80.0)
	var lb := base + Vector3(60.0, 0.0, 120.0)          # линия 40 м
	var planm: Dictionary = sm._block_formation_slots(la, lb, mixed)
	var sm_slots: Array = planm["slots"]
	var flat: Array = sm._blocks_flat(mixed)
	var dirv := (lb - la).normalized()
	var span: Dictionary = {}
	for i in range(flat.size()):
		var u: Unit = flat[i]
		var t: float = ((sm_slots[i] as Vector3) - la).dot(dirv)
		var sid: int = u.squad_id
		if not span.has(sid):
			span[sid] = [t, t]
		else:
			var pr: Array = span[sid]
			pr[0] = minf(float(pr[0]), t)
			pr[1] = maxf(float(pr[1]), t)
	var w_big: float = 0.0
	var w_small: float = 0.0
	for sid in span:
		var pr: Array = span[sid]
		var width: float = float(pr[1]) - float(pr[0])
		if int(sid) == int(big["sid"]):
			w_big = width
		else:
			w_small = width
		print("    отряд %d (%s, %d чел.): участок %.1f .. %.1f м (ширина %.1f)" % [
			int(sid), GameManager.squad_type(int(sid)),
			GameManager.squad_members(int(sid)).size(), float(pr[0]), float(pr[1]), width])
	print("  ширина секции: отряд 20 чел. = %.1f м, отряд 5 чел. = %.1f м" % [w_big, w_small])
	verdict("6d широкий отряд получает больший участок линии",
		w_big > w_small, "%.1f м против %.1f м" % [w_big, w_small])

	# ── (г) ОТРЯД + ОДИНОЧНЫЕ РАБОЧИЕ (squad_id = 0) ───────────────────────
	var loose: Array = []
	for i in range(4):
		var wk := _spawn("worker", Constants.FACTION_PLAYER)
		wk.global_position = base + Vector3(float(i), 0.0, 140.0)
		loose.append(wk)
	await frames(3)
	var combo: Array = []
	combo.append_array(big["units"])
	combo.append_array(loose)
	var blocksc: Array = sm._split_into_blocks(combo)
	var sizes := ""
	for b in blocksc:
		sizes += "%d " % (b as Array).size()
	print("  отряд(20) + 4 одиночных рабочих: блоков=%d, размеры: %s" % [blocksc.size(), sizes])
	verdict("6e одиночки (squad_id = 0) собираются в ОДИН отдельный блок",
		blocksc.size() == 2 and (blocksc[1] as Array).size() == 4,
		"блоков %d" % blocksc.size())

	# ── (д) ПРЕВЬЮ СОВПАДАЕТ С ПРИКАЗОМ ────────────────────────────────────
	sm.selected_units = mixed.duplicate()
	var preview: Array = sm._block_formation_slots(la, lb, mixed)["slots"]
	sm._execute_line_formation(la, lb)
	await frames(3)
	var order_flat: Array = sm._blocks_flat(mixed)
	var mism := 0
	var worst := 0.0
	for i in range(order_flat.size()):
		var u2: Unit = order_flat[i]
		var want: Vector3 = preview[i]
		var d: float = Vector2(u2.move_target.x, u2.move_target.z).distance_to(
			Vector2(want.x, want.z))
		worst = maxf(worst, d)
		if d > 0.05:
			mism += 1
	print("  сверка превью и приказа: расхождений %d из %d, максимум %.3f м" % [
		mism, order_flat.size(), worst])
	verdict("6f превью формации совпадает с фактическим приказом",
		mism == 0, "расхождений %d, макс %.3f м" % [mism, worst])
	sm.selected_units = []

	_kill(m1)
	for sqd in five:
		_kill(sqd["units"])
	_kill(big["units"]); _kill(small["units"]); _kill(loose)
	await frames(3)

# ═════════════════════════════════════════════════════════════════════════════
# 7. ОБОРОНИТЕЛЬНЫЙ ИИ В ДИНАМИКЕ
# ═════════════════════════════════════════════════════════════════════════════
func _t7_defensive_ai_live() -> void:
	print("\n═════ 7. ОБОРОНИТЕЛЬНЫЙ ИИ: ПАТРУЛИ, ЗВЁЗДЫ, ЗАСЛОН ═════")
	var ai = main.enemy_ai
	if ai == null:
		verdict("7a ИИ доступен", false, "main.enemy_ai == null")
		return

	var ec := Castle.new()
	ec.faction = Constants.FACTION_ENEMY
	main.world_add(ec)
	ec.global_position = Vector3(2000.0, 0.0, 2000.0)
	var pc := Castle.new()
	pc.faction = Constants.FACTION_PLAYER
	main.world_add(pc)
	pc.global_position = Vector3(1900.0, 0.0, 1900.0)
	await frames(3)

	# Шесть маленьких отрядов: 1 уйдёт в гарнизон, остальные — заслон и патрули
	var saved: Array = ai.squads.duplicate()
	ai.squads = []
	var made: Array = []
	for i in range(6):
		var us: Array = []
		for j in range(2):
			var u := _spawn("spearman", Constants.FACTION_ENEMY)
			u.global_position = ec.global_position + Vector3(float(i), 0.0, float(j))
			us.append(u)
		made.append_array(us)
		ai.squads.append({"type": "spearman", "members": us, "role": "guard",
			"target": ec.global_position, "issued": false})
	await frames(3)

	ai._command_squads_defensive(ec)
	await frames(2)
	var roles: Dictionary = {}
	var patrol_sq: Array = []
	var line_sq: Array = []
	for s in ai.squads:
		var sq: Dictionary = s
		var r: String = String(sq["role"])
		roles[r] = int(roles.get(r, 0)) + 1
		if r == ai.ROLE_PATROL:
			patrol_sq.append(sq)
		elif r == ai.ROLE_LINE:
			line_sq.append(sq)
	print("  роли после раздачи: %s" % str(roles))
	verdict("7a при обороне раздаются роли заслона и патруля",
		line_sq.size() > 0 and patrol_sq.size() > 0,
		"заслон %d, патруль %d" % [line_sq.size(), patrol_sq.size()])

	# (б) ПАТРУЛИ РЕАЛЬНО ХОДЯТ: смена фазы обязана дать новую точку и новый приказ
	var before: Array = []
	for s in patrol_sq:
		before.append((s as Dictionary)["target"] as Vector3)
	var mt_before: Array = []
	for s in patrol_sq:
		var mm: Array = (s as Dictionary)["members"]
		var u0: Unit = mm[0]
		mt_before.append(u0.move_target)
	ai._patrol_phase += 1
	ai._command_squads_defensive(ec)
	await frames(3)
	var moved_pts := 0
	var moved_orders := 0
	for i in range(patrol_sq.size()):
		var sq2: Dictionary = patrol_sq[i]
		var t_now: Vector3 = sq2["target"]
		var t_old: Vector3 = before[i]
		if t_now.distance_to(t_old) > 2.0:
			moved_pts += 1
		var mm2: Array = sq2["members"]
		var u1: Unit = mm2[0]
		var o_old: Vector3 = mt_before[i]
		if u1.move_target.distance_to(o_old) > 2.0:
			moved_orders += 1
	print("  смена фазы патруля: новых точек %d из %d, новых приказов бойцам %d" % [
		moved_pts, patrol_sq.size(), moved_orders])
	verdict("7b патрули действительно перемещаются при смене фазы",
		moved_pts == patrol_sq.size() and moved_orders == patrol_sq.size(),
		"точек %d, приказов %d из %d" % [moved_pts, moved_orders, patrol_sq.size()])

	# (в) ЗАСЛОН стоит в стойке ЗАЩИТА и не получает приказа атаки
	var holds := 0
	var line_units := 0
	for s in line_sq:
		var mm3: Array = (s as Dictionary)["members"]
		for m in mm3:
			var u: Unit = m
			line_units += 1
			if u.stance == _UCfg.STANCE_DEFENSE:
				holds += 1
	print("  бойцов заслона в стойке ЗАЩИТА: %d из %d" % [holds, line_units])
	verdict("7c заслон держит рубеж в стойке ЗАЩИТА",
		line_units > 0 and holds == line_units,
		"%d из %d" % [holds, line_units])

	# (г) заслон не заходит на половину игрока
	var center: Vector3 = ai._defense_center(ec)
	var d_own: float = center.distance_to(ec.global_position)
	var d_foe: float = center.distance_to(pc.global_position)
	var beyond := 0
	for s in line_sq:
		var t: Vector3 = (s as Dictionary)["target"]
		if t.distance_to(pc.global_position) < d_foe * 0.5:
			beyond += 1
	print("  рубеж: свой замок %.0f м, база игрока %.0f м; секций заслона за половиной пути к игроку: %d" % [
		d_own, d_foe, beyond])
	verdict("7d ни одна секция заслона не уходит к базе игрока", beyond == 0,
		"нарушителей %d" % beyond)

	# (д) АВТО-ЗВЁЗДЫ: пять уровней разом разбираются без вечного цикла
	var sid: int = GameManager.new_squad(Constants.FACTION_ENEMY, "spearman")
	var vets: Array = []
	for i in range(3):
		var u := _spawn("spearman", Constants.FACTION_ENEMY)
		u.global_position = ec.global_position + Vector3(20.0 + float(i), 0.0, 20.0)
		GameManager.add_to_squad(sid, u)
		vets.append(u)
	await frames(3)
	var rec: Dictionary = GameManager.squads[sid]
	rec["level"] = 5
	rec["pending"] = 5                       # заведомо больше, чем за один тик
	var probe: Unit = vets[0]
	var dmg0: float = probe._strike_damage() + probe._upgrade_damage_bonus()
	var hp0: float = probe.max_health
	var t0: int = Time.get_ticks_msec()
	ai._auto_veteran()
	var spent: int = Time.get_ticks_msec() - t0
	var dmg1: float = probe._strike_damage() + probe._upgrade_damage_bonus()
	var hp1: float = probe.max_health
	print("  разбор 5 уровней занял %d мс; осталось неразобранных: %d" % [
		spent, GameManager.squad_pending(sid)])
	print("  урон бойца ИИ %.1f → %.1f, макс. HP %.0f → %.0f, vet_attack=%.1f" % [
		dmg0, dmg1, hp0, hp1, probe.vet_attack])
	verdict("7e авто-выбор звёзд завершается (нет вечного while)", spent < 1000,
		"заняло %d мс" % spent)
	verdict("7f все накопленные уровни разобраны",
		GameManager.squad_pending(sid) == 0,
		"осталось %d" % GameManager.squad_pending(sid))
	verdict("7g награды реально усиливают отряд ИИ",
		dmg1 > dmg0 or hp1 > hp0,
		"урон %.1f→%.1f, HP %.0f→%.0f" % [dmg0, dmg1, hp0, hp1])

	ai.squads = saved
	_kill(made); _kill(vets)
	ec.queue_free(); pc.queue_free()
	await frames(3)

# ═════════════════════════════════════════════════════════════════════════════
# 8. ОЗЕРО: КРАЕВЫЕ СЛУЧАИ
# ═════════════════════════════════════════════════════════════════════════════
func _t8_lake_edges() -> void:
	print("\n═════ 8. ОЗЕРО: РАБОЧИЙ С ГРУЗОМ, ПРИКАЗ В ВОДУ, ЮНИТ В ВОДЕ ═════")
	# ОЗЕРО ВРЕМЕННО ВЫКЛЮЧЕНО (Main.LAKE_ENABLED): воды на карте нет, проверять
	# обход берега не на чем. Раздел не удалён — вернётся вместе с флагом
	if not main.LAKE_ENABLED:
		print("  ПРОПУЩЕНО: озеро отключено флагом Main.LAKE_ENABLED")
		return
	var c: Vector3 = main.LAKE_CENTER
	var lr: float = main.LAKE_RADIUS

	# (а) nearest_land не зацикливается ни в одной точке озера
	var t0: int = Time.get_ticks_msec()
	var probes := 0
	var still_water := 0
	for ix in range(-12, 13):
		for iz in range(-12, 13):
			var x: float = c.x + float(ix)
			var z: float = c.z + float(iz)
			if not main.is_water(x, z):
				continue
			probes += 1
			var p: Vector2 = main.nearest_land(x, z)
			if main.is_water(p.x, p.y):
				still_water += 1
	var ms: int = Time.get_ticks_msec() - t0
	print("  nearest_land: %d точек воды обработано за %d мс, осталось в воде: %d" % [
		probes, ms, still_water])
	verdict("8a nearest_land не зацикливается и всегда выводит на сушу",
		probes > 0 and still_water == 0 and ms < 2000,
		"в воде %d из %d, %d мс" % [still_water, probes, ms])

	# ВАЖНО ПРО ЗАМЕРЫ: движение живёт в _physics_process (60 тиков/с реального
	# времени), а await process_frame в headless крутится в разы быстрее. Ждать
	# «кадрами» бессмысленно — ждём по ЧАСАМ. Скорость подопытных поднимаем,
	# чтобы стенд не стоял по полминуты на каждую проверку: проверяется маршрут,
	# а не то, как быстро юнит переставляет ноги.

	# (б) юнит, которому приказали идти В ВОДУ, встаёт на берегу и НЕ дёргается
	var u := _spawn("spearman", Constants.FACTION_PLAYER)
	u.global_position = Vector3(c.x - lr - 6.0, 0.0, c.z)
	await frames(3)
	u.move_speed = 12.0
	# Точка ВНУТРИ озера со стороны юнита: берег ищется по той же радиали,
	# поэтому цель ляжет на ближний берег, а не на противоположный
	var wet_goal := Vector3(c.x - lr * 0.5, 0.0, c.z)
	print("  цель (%.1f, %.1f) это вода=%s" % [
		wet_goal.x, wet_goal.z, str(main.is_water(wet_goal.x, wet_goal.z))])
	u.command_move(wet_goal)
	print("  приказ в воду превращён в цель (%.1f, %.1f), это вода=%s" % [
		u.move_target.x, u.move_target.z, str(main.is_water(u.move_target.x, u.move_target.z))])
	await _wait_until_idle(u, 8000)
	var settle: Vector3 = u.global_position
	var jitter := 0.0
	var in_water := 0
	var tj: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - tj < 2000:
		await frames(3)
		jitter = maxf(jitter, settle.distance_to(u.global_position))
		if main.is_water(u.global_position.x, u.global_position.z):
			in_water += 1
	print("  через 2 с после прибытия: состояние=%d, дрожание %.3f м, замеров в воде %d" % [
		u.state, jitter, in_water])
	verdict("8b приказ в воду не оставляет юнита в воде", in_water == 0,
		"замеров в воде %d" % in_water)
	verdict("8c дойдя до берега, юнит не дёргается", jitter < 0.5,
		"дрожание %.3f м" % jitter)

	# (в) РАБОЧИЙ С ГРУЗОМ ЗА ОЗЕРОМ доходит до склада на другом берегу.
	# Маршрут строит сам Worker._process_return по реестру складов
	var castle := Castle.new()
	castle.faction = Constants.FACTION_PLAYER
	main.world_add(castle)
	castle.global_position = Vector3(c.x - lr - 8.0, 0.0, c.z)
	await frames(3)
	var w := _spawn("worker", Constants.FACTION_PLAYER) as Worker
	w.global_position = Vector3(c.x + lr + 6.0, 0.0, c.z)   # ровно за озером
	await frames(3)
	w.walk_speed_loaded = 14.0
	w.carrying_amount = 10.0
	w.carrying_type = Constants.RESOURCE_WOOD
	w.state = Unit.State.RETURNING
	var d0: float = w.global_position.distance_to(castle.global_position)
	var stuck := 0
	var last: Vector3 = w.global_position
	var wet := 0
	var tw: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - tw < 20000:
		await frames(3)
		if w.global_position.distance_to(last) < 0.002:
			stuck += 1
		last = w.global_position
		if main.is_water(w.global_position.x, w.global_position.z):
			wet += 1
		if w.global_position.distance_to(castle.global_position) < 4.0:
			break
	var d1: float = w.global_position.distance_to(castle.global_position)
	var secs: float = float(Time.get_ticks_msec() - tw) / 1000.0
	print("  рабочий с грузом: было %.1f м до склада, стало %.1f м за %.1f с; в воде %d замеров" % [
		d0, d1, secs, wet])
	verdict("8d рабочий с грузом обходит озеро и доходит до склада",
		d1 < 5.0, "осталось %.1f м из %.1f за %.1f с" % [d1, d0, secs])
	verdict("8e по дороге рабочий не идёт напрямик через воду", wet == 0,
		"замеров в воде %d" % wet)

	# (г) юнит, ОКАЗАВШИЙСЯ В ВОДЕ (выход из гарнизона у берега, спавн из ворот),
	# обязан выбраться — иначе он застревает в озере навсегда
	var drown := _spawn("spearman", Constants.FACTION_PLAYER)
	drown.global_position = Vector3(c.x, 0.0, c.z)          # ровно в центре озера
	await frames(3)
	drown.move_speed = 12.0
	var land: Vector3 = GameManager.land_target(Vector3(c.x - lr - 5.0, 0.0, c.z))
	drown.command_move(land)
	var escaped := false
	var td: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - td < 12000:
		await frames(3)
		if not main.is_water(drown.global_position.x, drown.global_position.z):
			escaped = true
			break
	print("  юнит, оказавшийся в центре озера: выбрался=%s за %.1f с, позиция (%.1f, %.1f)" % [
		str(escaped), float(Time.get_ticks_msec() - td) / 1000.0,
		drown.global_position.x, drown.global_position.z])
	verdict("8f юнит, оказавшийся в воде, способен из неё выйти", escaped,
		"остался в (%.1f, %.1f)" % [drown.global_position.x, drown.global_position.z])

	# (д) и точка выхода из гарнизона у самого берега тоже не должна лечь в воду
	var shore_castle := Castle.new()
	shore_castle.faction = Constants.FACTION_PLAYER
	main.world_add(shore_castle)
	shore_castle.global_position = Vector3(c.x - lr - 2.0, 0.0, c.z)
	await frames(3)
	var probe := _spawn("spearman", Constants.FACTION_PLAYER)
	probe.global_position = shore_castle.global_position
	await frames(3)
	probe.garrisoned = true
	# Точка выхода намеренно взята В ОЗЕРЕ
	shore_castle.release_unit(probe, Vector3(c.x, 0.0, c.z))
	await frames(2)
	print("  выпуск из гарнизона в точку (%.1f, %.1f): боец встал в (%.1f, %.1f), вода=%s" % [
		c.x, c.z, probe.global_position.x, probe.global_position.z,
		str(main.is_water(probe.global_position.x, probe.global_position.z))])
	verdict("8g выход из гарнизона не ставит бойца в воду",
		not main.is_water(probe.global_position.x, probe.global_position.z),
		"встал в (%.1f, %.1f)" % [probe.global_position.x, probe.global_position.z])

	_kill([u, w, drown, probe])
	castle.queue_free(); shore_castle.queue_free()
	await frames(3)

## Ждать, пока юнит не встанет (state IDLE), но не дольше limit_ms
func _wait_until_idle(u: Unit, limit_ms: int) -> void:
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < limit_ms:
		await frames(3)
		if u.state == Unit.State.IDLE:
			return

# ═════════════════════════════════════════════════════════════════════════════
# 9. ЗАМЕРЫ ПРОИЗВОДИТЕЛЬНОСТИ
# ═════════════════════════════════════════════════════════════════════════════
# В headless кадр короче 1/60 с, поэтому стену часов мерить бессмысленно —
# берём мониторы движка. Скан агро живёт в _physics_process, работа со
# спрайтами (_process_can_sleep / _update_dir_sprite) — в _process.
func _t9_perf() -> void:
	print("\n═════ 9. ЗАМЕРЫ: 200 ЛУЧНИКОВ И 300 КОПЕЙЩИКОВ В ЗАЩИТЕ ═════")

	await frames(20)
	var idle_phys := await _avg_monitor(Performance.TIME_PHYSICS_PROCESS, 30)
	var idle_proc := await _avg_monitor(Performance.TIME_PROCESS, 30)
	print("  фон (пустая сцена): физика %.3f мс, кадр %.3f мс" % [
		idle_phys * 1000.0, idle_proc * 1000.0])

	# ── 200 лучников: агро-скан идёт радиусом 20 м вместо прежних 10 ────────
	var base := Vector3(3000.0, 0.0, 3000.0)
	var archers: Array = []
	for i in range(200):
		var a := _spawn("archer", Constants.FACTION_PLAYER)
		a.global_position = base + Vector3(float(i % 20) * 1.2, 0.0, float(i / 20) * 1.2)
		archers.append(a)
	# Немного целей, чтобы скан шёл в «горячем» режиме, а не в дежурном
	var foes: Array = []
	for i in range(20):
		var f := _spawn("spearman", Constants.FACTION_ENEMY)
		f.global_position = base + Vector3(float(i) * 1.2, 0.0, 30.0)
		f.set_stance(_UCfg.STANCE_DEFENSE)
		foes.append(f)
	await frames(60)
	var a_phys := await _avg_monitor(Performance.TIME_PHYSICS_PROCESS, 60)
	var aggro := 0
	for m in archers:
		var u: Unit = m
		if u.attack_target != null:
			aggro += 1
	print("  200 лучников + 20 целей: физика %.3f мс (было %.3f), взяли цель %d лучников" % [
		a_phys * 1000.0, idle_phys * 1000.0, aggro])
	print("    цена на юнита: %.4f мс" % ((a_phys - idle_phys) * 1000.0 / 200.0))
	verdict("9a агро-скан лучников на 20 м не рушит производительность",
		a_phys < 0.020, "физика %.2f мс на 200 лучников" % (a_phys * 1000.0))
	_kill(archers); _kill(foes)
	await frames(20)

	# ── 300 копейщиков: КОНТРОЛЬ (стойка АТАКА) против ЗАЩИТЫ ──────────────
	# Один замер сам по себе ничего не значит: спрайтовый копейщик дорог и в
	# обычной стойке. Смысл имеет только РАЗНИЦА — сколько добавила направленная
	# поза, из-за которой _process_can_sleep() отказывается усыплять юнита
	var base2 := Vector3(4000.0, 0.0, 4000.0)
	var spears: Array = []
	for i in range(300):
		var s := _spawn("spearman", Constants.FACTION_PLAYER)
		s.global_position = base2 + Vector3(float(i % 25) * 1.0, 0.0, float(i / 25) * 1.0)
		spears.append(s)
	await frames(90)
	# ПЕРВОЕ ОКНО ПОСЛЕ СПАВНА МЕРЯТЬ НЕЛЬЗЯ: в него попадает разбор спрайтлистов
	# (для 300 копейщиков это ~250 мс на кадр), и контроль оказывается завышен
	# в сто раз. Прогреваем вхолостую и меряем только установившуюся цену
	var _warmup := await _avg_monitor(Performance.TIME_PROCESS, 60)
	await frames(30)
	var atk_proc := await _avg_monitor(Performance.TIME_PROCESS, 60)
	var atk_awake := 0
	for m in spears:
		if not (m as Spearman)._proc_sleeping:
			atk_awake += 1
	print("  300 копейщиков в АТАКЕ  (контроль): кадр %.3f мс, не спят %d" % [
		atk_proc * 1000.0, atk_awake])

	for m in spears:
		(m as Unit).set_stance(_UCfg.STANCE_DEFENSE)
	# ЖДЁМ ПО СТЕННЫМ ЧАСАМ, А НЕ ПО КАДРАМ. Копья опускаются ВРАЗНОБОЙ:
	# у каждого бойца своя микро-задержка до Spearman.DROP_DELAY_MAX_MS, и
	# отсчитывается она по Time.get_ticks_msec(). В headless кадры крутятся
	# намного быстрее реального времени, поэтому «подождать 90 кадров» здесь
	# означает подождать доли секунды — и замер ловил фалангу на середине
	# опускания, когда копьё выставила едва половина отряда
	var t_drop: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t_drop < Spearman.DROP_DELAY_MAX_MS + 400:
		await get_tree().process_frame
	var s_proc := await _avg_monitor(Performance.TIME_PROCESS, 60)
	var awake := 0
	var dirpose := 0
	for m in spears:
		var sp: Spearman = m
		if not sp._proc_sleeping:
			awake += 1
		if sp._cur_tex_key.begins_with("defence") or sp._cur_tex_key.begins_with("attack"):
			dirpose += 1
	print("  300 копейщиков в ЗАЩИТЕ (замер):    кадр %.3f мс, не спят %d, направленная поза у %d" % [
		s_proc * 1000.0, awake, dirpose])
	print("  фон пустой сцены %.3f мс; надбавка защиты к атаке: %.3f мс (%.1f%%)" % [
		idle_proc * 1000.0, (s_proc - atk_proc) * 1000.0,
		(s_proc / maxf(atk_proc, 1e-6) - 1.0) * 100.0])
	# ПОРОГ ПО ОТНОШЕНИЮ ОТСЮДА УБРАН СОЗНАТЕЛЬНО. Обе цифры порядка 1.3-2.5 мс,
	# а разброс машины между прогонами — около 1 мс (замер одной и той же стойки
	# дал 1.25, 1.51, 1.58, 1.93 мс). Отношение таких чисел скачет от 0.97 до
	# 1.7, и проверка падала в половине прогонов, ничего не сообщая об игре.
	# Меряем то, что действительно важно: АБСОЛЮТНУЮ цену кадра. Весь кадр при
	# 60 fps это 16.7 мс; если 300 бойцов в одной стойке съедают больше 5 мс
	# (17 мкс на бойца) — это настоящая беда, а не шум замера
	var def_ms: float = s_proc * 1000.0
	var extra_ms: float = (s_proc - atk_proc) * 1000.0
	verdict("9b стойка ЗАЩИТА укладывается в бюджет кадра (<5 мс на 300 бойцов)",
		def_ms < 5.0,
		"защита %.2f мс, атака %.2f мс, надбавка %.2f мс (%.1f мкс на бойца)" % [
			def_ms, atk_proc * 1000.0, extra_ms, def_ms / 300.0 * 1000.0])
	verdict("9c направленную позу получают именно те, кто не спит",
		awake <= dirpose + 30, "не спят %d, направленных поз %d" % [awake, dirpose])
	_kill(spears)
	await frames(20)

func _avg_monitor(mon: int, n: int) -> float:
	var acc := 0.0
	for _i in range(n):
		await get_tree().process_frame
		acc += Performance.get_monitor(mon)
	return acc / float(n)
