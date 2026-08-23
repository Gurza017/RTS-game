extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: КУЧИ РЕСУРСОВ, ЖЁСТКИЙ КЛИК, АВТО-ЦИКЛ ДОБЫЧИ
## ═══════════════════════════════════════════════════════════════════════════
##   A КУЧА       — куски не садятся друг в друга, реестр заполнен, овал
##                  накрывает то, что стоит на карте; РУДНИК КАК ЕДИНЫЙ ОБЪЕКТ:
##                  общий пул из конфига, рабочие места СНАРУЖИ навала,
##                  выталкивание изнутри, косметика выработки
##   B КЛИК       — что подсвечено, то и приказано; камень не проигрывает
##                  дереву, стоящему за ним (та самая жалоба)
##   C АВТО-ЦИКЛ  — свой кластер у игрока, следующий кластер у ИИ
##   D ЛЕС        — соседний ствол в пределах делянки
##   E ЗВУК       — топор чаще кирки, лимиты пропускают темп бригады
##   F ДОБЫЧА     — сквозная: приказ → место на периметре → работа → общий пул,
##                  и ни разу внутри навала
##   G КУЗНИЦА    — экономическая ветка рабочего доходит до самого рабочего
##
## Числа НЕ хардкодятся: все пороги выводятся из Main.PIECE_CLASSES,
## Main.CLUSTER_LAYOUTS, unit_stats_config.cluster_stock, forge_config.tree и
## Worker.*_SWING_RATE — см. «Config is the source of truth» в CLAUDE.md. Стенд
## headless-совместим: камера нужна только разделу B, и там она ставится явно.

const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _Forge := preload("res://scripts/forge_config.gd")

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")

## ФИЗИЧЕСКИЕ кадры, а не process_frame: при Engine.max_fps = 0 отрисовка
## обгоняет фиксированные 60 Гц физики, и «подожди N кадров» перестаёт
## соответствовать N/60 секундам симуляции (см. CLAUDE.md)
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
	var out := s
	while out.length() < n: out += " "
	return out

func _new_node(rtype: int, at: Vector3, scale_v: float = 1.0,
		amount: float = 100000.0, cid: int = 0) -> ResourceNode:
	var r := ResourceNode.new()
	r.resource_type = rtype
	r.size_scale    = scale_v
	r.remaining     = amount
	r.cluster_id    = cid
	main.world_add(r)
	r.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	return r

func _new_worker(at: Vector3, fac: int = Constants.FACTION_PLAYER) -> Worker:
	var w := Worker.new()
	w.faction = fac
	main.world_add(w)
	w.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	return w

func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(5)
	GameManager.world_bounds_enabled = false
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	await frames(3)

	await _a_cluster()
	await _b_click()
	await _c_autocycle()
	await _d_wood()
	await _e_sound()
	await _f_mining()
	await _g_worker_forge()
	await _h_stuck()

	print("\n═════ ИТОГ ═════")
	for e in _log:
		var row: Array = e
		print("  %s%s" % [_pad(String(row[0]), 64), "ПРОШЛО" if bool(row[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	print("\n=== RES2 TEST DONE ===")
	get_tree().quit(1 if _fail > 0 else 0)

# ═════════════════════════════════════════════════════════════════════════════
# A. КУЧА
# ═════════════════════════════════════════════════════════════════════════════
## Полуширина НАРИСОВАННОГО куска в метрах — грубая, но достаточная оценка:
## кусок класса рисуется высотой PIECE_TARGET_H * scale, силуэт примерно
## квадратный. Порог «центр соседа не внутри моего силуэта» берётся от неё
func _silhouette_half(cls: String) -> float:
	var pc: Dictionary = main.PIECE_CLASSES[cls]
	return 0.62 * float(pc.get("scale", 1.0))

func _a_cluster() -> void:
	print("\n═════ A. КУЧА ═════")
	var layouts: Array = main.CLUSTER_LAYOUTS

	# A1. Кусков в шаблоне ровно вдвое против прежних восьми
	var sizes: Array = []
	var all16 := true
	for l in layouts:
		var arr: Array = l
		sizes.append(arr.size())
		if arr.size() != 16:
			all16 = false
	verdict("A1 в каждом шаблоне 16 кусков (было 8)", all16, "размеры %s" % [sizes])

	# A2. ВИД КУЧИ И ЕЁ ЗАПАС РАЗВЯЗАНЫ.
	#
	# Раньше здесь проверялось «запас кучи не меньше удвоенного прежнего»,
	# сложенный из PIECE_CLASSES.amount по составу шаблона. Ровно эта связка и
	# была проблемой: запас месторождения выводился из ЕГО ВНЕШНЕГО ВИДА, то есть
	# правка раскладки молча меняла баланс и наоборот. Запас переехал в конфиг
	# единой цифрой на кучу, а класс куска отвечает теперь только за размер.
	# Проверяем именно это свойство — что связки больше нет
	var no_amount := true
	for k in main.PIECE_CLASSES.keys():
		var pc: Dictionary = main.PIECE_CLASSES[k]
		if pc.has("amount"):
			no_amount = false
	var cap_gold: float = _UCfg.cluster_stock("gold")
	var cap_stone: float = _UCfg.cluster_stock("stone")
	verdict("A2 ёмкость кучи задаётся конфигом, а не составом раскладки",
		no_amount and cap_gold > 0.0 and cap_stone > 0.0,
		"класс несёт запас: %s, конфиг золото=%d камень=%d" % [
			str(not no_amount), int(cap_gold), int(cap_stone)])

	# A3. Куски соприкасаются, но ни один не садится соседу в середину
	var worst := INF
	var worst_txt := ""
	for li in range(layouts.size()):
		var arr: Array = layouts[li]
		for i in range(arr.size()):
			for j in range(i + 1, arr.size()):
				var a: Array = arr[i]
				var b: Array = arr[j]
				var d: float = Vector2(float(a[0]) - float(b[0]),
					float(a[1]) - float(b[1])).length()
				var need: float = maxf(_silhouette_half(String(a[2])),
					_silhouette_half(String(b[2])))
				var slack: float = d - need
				if slack < worst:
					worst = slack
					worst_txt = "шаблон %d, %s↔%s: %.3f при пороге %.3f" % [li, a[2], b[2], d, need]
	verdict("A3 центр соседа не внутри силуэта куска", worst >= 0.0, worst_txt)

	# A4. Настоящая куча на карте: единый номер, реестр, овал накрывает куски
	var before: int = main.res_clusters.size()
	var center := Vector3(0.0, 0.0, -420.0)
	main._spawn_resource_cluster(center, Constants.RESOURCE_GOLD, true)
	await frames(3)
	verdict("A4а куча зарегистрирована", main.res_clusters.size() == before + 1,
		"было %d, стало %d" % [before, main.res_clusters.size()])

	var cid: int = main._cluster_seq
	var mine: Array = []
	for n in get_tree().get_nodes_in_group("resource_nodes"):
		var rn := n as ResourceNode
		if rn != null and rn.cluster_id == cid:
			mine.append(rn)
	verdict("A4б все куски получили один номер кучи", mine.size() >= 16,
		"кусков с id=%d: %d" % [cid, mine.size()])

	var info: Dictionary = main.res_clusters.get(cid, {})
	var covered := true
	var far_txt := ""
	if info.is_empty():
		covered = false
	else:
		var c: Vector3 = info["center"]
		var half: Vector2 = info["half"]
		var rim: float = main.CLUSTER_RIM
		for n2 in mine:
			var rn2: ResourceNode = n2
			var dx: float = absf(rn2.global_position.x - c.x)
			var dz: float = absf(rn2.global_position.z - c.z)
			if dx > half.x + rim or dz > half.y + rim:
				covered = false
				far_txt = "кусок вне овала: dx=%.2f/%.2f dz=%.2f/%.2f" % [dx, half.x + rim, dz, half.y + rim]
	verdict("A4в овал подсветки накрывает все куски кучи", covered, far_txt)

	# ── A5. РУДНИК КАК ЕДИНЫЙ ОБЪЕКТ ────────────────────────────────────────
	var mc = info.get("mine", null)
	verdict("A5а куча собрана в единый объект с общим пулом из конфига",
		mc != null and is_equal_approx(float(mc.max_stock), cap_gold)
			and is_equal_approx(float(mc.stock), cap_gold),
		"пул=%s при конфиге %d" % [
			("%.0f" % float(mc.stock)) if mc != null else "нет объекта", int(cap_gold)])

	# Остаток КУСКА — зеркало остатка КУЧИ: на этом держатся все существующие
	# проверки вида `rn.remaining <= 0`, ничего не знающие про кластер
	var mirror := true
	for n4 in mine:
		if not is_equal_approx((n4 as ResourceNode).remaining, float(mc.stock)):
			mirror = false
	verdict("A5б остаток каждого куска — это остаток кучи", mirror,
		"пул=%.0f" % float(mc.stock))

	# ── A6. РАБОЧИЕ МЕСТА СНАРУЖИ НАВАЛА ────────────────────────────────────
	# Главное требование блока: «рабочим ЗАПРЕЩЕНО заходить внутрь зоны
	# камушков». Проверяем не намерение, а геометрию: НИ ОДНА точка разметки не
	# должна попасть внутрь нарисованного овала
	var inside_slots := 0
	var worst_k := INF
	var total_slots: int = int(mc.slot_total())
	for i in range(total_slots):
		var p: Vector3 = mc.slot_position(i)
		# Нормированный радиус по овалу подсветки: <1 значит «внутри навала»
		var kx: float = (p.x - mc.center.x) / maxf(mc.outline.x, 0.001)
		var kz: float = (p.z - mc.center.z) / maxf(mc.outline.y, 0.001)
		var k: float = sqrt(kx * kx + kz * kz)
		worst_k = minf(worst_k, k)
		if k < 1.0:
			inside_slots += 1
	verdict("A6а все рабочие места лежат СНАРУЖИ овала кучи",
		total_slots > 0 and inside_slots == 0,
		"мест %d, внутри %d, ближайшее k=%.3f (надо >1)" % [
			total_slots, inside_slots, worst_k])

	# И со своего места инструмент обязан доставать до жилы — иначе рабочий
	# встанет и не начнёт работать вовсе (тот самый «стоит и не работает»)
	var reach_ok := true
	for i2 in range(total_slots):
		if not mc.in_reach(mc.slot_position(i2)):
			reach_ok = false
	verdict("A6б с любого места инструмент достаёт до жилы", reach_ok)

	# Двое не встают в одну точку — это и было причиной дёрганья у старых кусков
	var w1 := _new_worker(Vector3(center.x + 14.0, 0.0, center.z))
	var w2 := _new_worker(Vector3(center.x + 14.5, 0.0, center.z + 0.5))
	await frames(2)
	var s1: Vector3 = mc.claim_slot(w1)
	var s2: Vector3 = mc.claim_slot(w2)
	verdict("A6в двое рабочих получают разные точки",
		s1.distance_to(s2) > 0.3, "просвет %.2f м" % s1.distance_to(s2))

	# ── A7. ВЫТАЛКИВАНИЕ ИЗ НАВАЛА ──────────────────────────────────────────
	# Приказ внутрь не выдаётся никогда, но затолкать рабочего могут соседи.
	# Проверяем, что страховка отвечает наружу, а снаружи молчит
	var push_in: Vector3 = mc.outward_push(mc.center)
	var push_out: Vector3 = mc.outward_push(
		Vector3(mc.center.x + mc.stand.x + 3.0, 0.0, mc.center.z))
	verdict("A7 изнутри навала рабочего выталкивает, снаружи — не трогает",
		push_in != Vector3.ZERO and push_out == Vector3.ZERO,
		"внутри→%s, снаружи→%s" % [str(push_in.round()), str(push_out)])

	# ── A8. КОСМЕТИКА ВЫРАБОТКИ ─────────────────────────────────────────────
	var vis_full: int = _visible_pieces(mine)
	mc.extract(mc.max_stock * 0.75)          # осталась четверть
	await frames(2)
	var vis_quarter: int = _visible_pieces(mine)
	verdict("A8а на выработанной на три четверти куче кусков стало меньше",
		vis_quarter < vis_full and vis_quarter >= 1,
		"было %d, стало %d" % [vis_full, vis_quarter])

	mc.extract(mc.max_stock)                  # выбрали до дна
	await frames(3)
	var left: int = 0
	for n5 in mine:
		if is_instance_valid(n5):
			left += 1
	verdict("A8б выработанная куча исчезает с карты целиком",
		mc.is_empty() and left == 0, "осталось узлов %d" % left)

	w1.queue_free(); w2.queue_free()
	for n3 in mine:
		if is_instance_valid(n3):
			(n3 as ResourceNode).queue_free()
	await frames(3)

## Сколько кусков кучи ещё нарисовано (косметически скрытые уходят из группы)
func _visible_pieces(list: Array) -> int:
	var n := 0
	for e in list:
		var rn := e as ResourceNode
		if rn != null and is_instance_valid(rn) and rn.is_in_group("resource_nodes"):
			n += 1
	return n

# ═════════════════════════════════════════════════════════════════════════════
# B. ЖЁСТКИЙ КЛИК
# ═════════════════════════════════════════════════════════════════════════════
# ВОСПРОИЗВЕДЕНИЕ ЖАЛОБЫ. Камера смотрит под 45°, поэтому точка ЗЕМЛИ под
# курсором уходит за основание того, на что игрок навёлся, ровно на высоту
# наведённой точки. Целясь в ВЕРХ крупного самородка (а это ~2 м), игрок получал
# точку земли в двух метрах за камнем — и дерево, стоящее там, выигрывало спор,
# потому что его наземный круг (1.35 м) накрывал эту точку, а круг камня (1.36 м
# вокруг СВОЕГО основания) — нет. Здесь дерево ставится ровно в эту точку, то
# есть в самый неблагоприятный случай.
func _b_click() -> void:
	print("\n═════ B. ЖЁСТКИЙ КЛИК ═════")
	var sm = main.selection_manager
	var cam = main._camera
	if sm == null or cam == null:
		verdict("B0 камера и разбор клика доступны", false, "нет camera/selection_manager")
		return

	var spot := Vector3(0.0, 0.0, 0.0)
	cam.jump_to(spot, cam.min_height)
	# Камера каждый кадр пересчитывает себя из фокуса — на время замера
	# останавливаем её, иначе разбор пойдёт по уже уехавшему кадру
	cam.set_process(false)
	await frames(3)

	var scale_v: float = float(main.PIECE_CLASSES["big"]["scale"])
	var rock := _new_node(Constants.RESOURCE_GOLD, spot, scale_v)
	await frames(3)

	# Целимся в ВЕРХ нарисованного куска. Высота куска задаётся самим
	# ResourceNode (PIECE_TARGET_H × size_scale) — берём её оттуда, а не числом
	var aim_h: float = ResourceNode.PIECE_TARGET_H * scale_v * 0.95
	var aim_world := rock.global_position + Vector3(0.0, aim_h, 0.0)
	# RTSCamera сама и есть Camera3D (extends Camera3D)
	var cam3: Camera3D = cam as Camera3D
	var sp: Vector2 = cam3.unproject_position(aim_world)
	var dirn: Vector3 = cam3.project_ray_normal(sp)
	var lean := Vector2(dirn.x, dirn.z) / absf(dirn.y)
	# Точка земли, которую даст этот пиксель — туда и ставим дерево
	var gp := Vector2(rock.global_position.x, rock.global_position.z) + lean * aim_h
	var tree := _new_node(Constants.RESOURCE_WOOD, Vector3(gp.x, 0.0, gp.y))
	await frames(3)

	# Без рабочего в выделении жила вообще не должна выбираться
	var none_sel = sm.resource_under_cursor(sp)
	verdict("B1 без рабочего в выделении жила не подсвечивается", none_sel == null,
		"вернулось %s" % [none_sel])

	var w := _new_worker(Vector3(6.0, 0.0, 6.0))
	await frames(2)
	sm._select_one(w)
	await frames(2)

	var hovered = sm.resource_under_cursor(sp)
	verdict("B2 камень выигрывает у дерева за ним", hovered == rock,
		"выбрано %s (камень=%s, дерево=%s), дерево в %.2f м за камнем" % [
			hovered, rock, tree,
			Vector2(gp.x - rock.global_position.x, gp.y - rock.global_position.z).length()])

	# Приказ обязан прийти В ТУ ЖЕ ЦЕЛЬ, что подсвечена: маска у них общая
	var pick: Dictionary = sm._pick_at(sp, sm.order_pick_mask())
	verdict("B3 подсветка и приказ дают один и тот же узел", pick["target"] == hovered,
		"приказ→%s, подсветка→%s" % [pick["target"], hovered])

	# И приказ действительно фиксируется на этом типе ресурса
	sm._handle_right_click(sp)
	await frames(3)
	verdict("B4 клик закрепил приказ на этой жиле", w.gather_target == rock,
		"gather_target=%s, тип=%d" % [w.gather_target, w._gather_res_type])

	# ── B5: ПРОМАХ В ПРОСВЕТ КУЧИ ───────────────────────────────────────────
	# Ставим настоящую кучу и целимся в ПУСТОЕ МЕСТО между кусками, но внутрь
	# овала подсветки. Это должно читаться как приказ на кучу, а не как «идите
	# в эту точку» — иначе обещание «клик по подсвеченной зоне» сдерживается
	# через раз
	rock.queue_free(); tree.queue_free()
	await frames(3)
	var cl_center := Vector3(0.0, 0.0, 0.0)
	main._spawn_resource_cluster(cl_center, Constants.RESOURCE_STONE, true)
	await frames(3)
	var cid2: int = main._cluster_seq
	var info2: Dictionary = main.res_clusters.get(cid2, {})
	var gap_ok := false
	var gap_txt := "куча не создалась"
	if not info2.is_empty():
		var c2: Vector3 = info2["center"]
		var half2: Vector2 = info2["half"]
		# Точка внутри овала, но подальше от центра — там просветы между кусками
		var probe := Vector3(c2.x + (half2.x + main.CLUSTER_RIM) * 0.75, 0.0, c2.z)
		var got = sm._ore_in_cluster_zone(probe)
		gap_ok = got != null and got.cluster_id == cid2
		gap_txt = "точка (%.1f, %.1f) → %s" % [probe.x, probe.z, got]
	verdict("B5 промах в просвет кучи читается как приказ на кучу", gap_ok, gap_txt)

	# И ровно за краем овала — уже НЕ приказ на добычу
	var out_ok := false
	var out_txt := ""
	if not info2.is_empty():
		var c3: Vector3 = info2["center"]
		var h3: Vector2 = info2["half"]
		var far_probe := Vector3(c3.x + (h3.x + main.CLUSTER_RIM) * 1.6, 0.0, c3.z)
		var got2 = sm._ore_in_cluster_zone(far_probe)
		out_ok = got2 == null
		out_txt = "точка вне овала → %s" % [got2]
	verdict("B6 за краем овала приказа на добычу нет", out_ok, out_txt)

	for n in get_tree().get_nodes_in_group("resource_nodes"):
		var rn2 := n as ResourceNode
		if rn2 != null and rn2.cluster_id == cid2:
			rn2.queue_free()
	sm._clear_selection()
	w.queue_free()
	await frames(3)
	cam.set_process(true)

# ═════════════════════════════════════════════════════════════════════════════
# C. АВТО-ЦИКЛ ПО КУЧЕ
# ═════════════════════════════════════════════════════════════════════════════
func _c_autocycle() -> void:
	print("\n═════ C. АВТО-ЦИКЛ ═════")
	# Своя куча из двух кусков и ЧУЖАЯ куча поодаль. Реестр заполняем руками:
	# _spawn_resource_cluster ставит шаблон целиком, а здесь нужна ровно
	# управляемая геометрия
	var base := Vector3(0.0, 0.0, -300.0)
	var cid := 9001
	var near_a := _new_node(Constants.RESOURCE_GOLD, base, 1.0, 20.0, cid)
	var near_b := _new_node(Constants.RESOURCE_GOLD, base + Vector3(3.0, 0, 0), 1.0, 20.0, cid)
	main.res_clusters[cid] = {
		"type": Constants.RESOURCE_GOLD,
		"center": base + Vector3(1.5, 0, 0),
		"radius": 1.5 + main.CLUSTER_RIM,
		"half": Vector2(1.5, 0.0),
	}
	# Чужая куча — далеко за пределами своей, но ближе, чем что-либо ещё
	var far_cid := 9002
	var far_node := _new_node(Constants.RESOURCE_GOLD, base + Vector3(60.0, 0, 0), 1.0, 20000.0, far_cid)
	main.res_clusters[far_cid] = {
		"type": Constants.RESOURCE_GOLD,
		"center": base + Vector3(60.0, 0, 0),
		"radius": main.CLUSTER_RIM,
		"half": Vector2(0.0, 0.0),
	}
	await frames(3)

	# C1. Игрок: выработал кусок — взял СОСЕДНИЙ В СВОЕЙ куче
	var w := _new_worker(base + Vector3(0, 0, 2.0))
	await frames(2)
	w.command_gather(near_a)
	verdict("C1а рабочий запомнил номер кучи", w._gather_cluster == cid,
		"_gather_cluster=%d" % w._gather_cluster)
	near_a.remaining = 0.0
	w.gather_target = null
	w._auto_find_resource(Constants.RESOURCE_GOLD)
	verdict("C1б взял соседний кусок в своей куче", w.gather_target == near_b,
		"цель=%s (сосед=%s, чужая куча=%s)" % [w.gather_target, near_b, far_node])

	# C2. Игрок: куча выработана целиком — встаёт и попадает в счётчик простоя
	near_b.remaining = 0.0
	w.gather_target = null
	w.carrying_amount = 0.0
	w._auto_find_resource(Constants.RESOURCE_GOLD)
	verdict("C2а рабочий игрока встал, а не ушёл на чужую кучу",
		w.gather_target == null and w.state == Unit.State.IDLE,
		"цель=%s, state=%d" % [w.gather_target, w.state])
	await frames(2)
	var idle: Array = main.hud._idle_workers()
	verdict("C2б встал в счётчик простаивающих", w in idle,
		"в списке %d" % idle.size())

	# C3. ИИ в той же ситуации уходит на СЛЕДУЮЩУЮ кучу
	var ai := _new_worker(base + Vector3(0, 0, 2.0), Constants.FACTION_ENEMY)
	await frames(2)
	ai._gather_cluster = cid
	ai._gather_res_type = Constants.RESOURCE_GOLD
	ai.gather_target = null
	ai._auto_find_resource(Constants.RESOURCE_GOLD)
	verdict("C3 рабочий ИИ не застревает — ушёл на следующую кучу",
		ai.gather_target == far_node,
		"цель=%s (ожидали %s)" % [ai.gather_target, far_node])

	w.queue_free(); ai.queue_free()
	near_a.queue_free(); near_b.queue_free(); far_node.queue_free()
	main.res_clusters.erase(cid)
	main.res_clusters.erase(far_cid)
	await frames(3)

# ═════════════════════════════════════════════════════════════════════════════
# D. ЛЕС
# ═════════════════════════════════════════════════════════════════════════════
# У леса номера кучи нет вовсе (деревья сажаются россыпью), поэтому «соседний
# ствол» ограничен радиусом делянки. Проверяем обе стороны порога
func _d_wood() -> void:
	print("\n═════ D. ЛЕС ═════")
	var base := Vector3(0.0, 0.0, -200.0)
	var r: float = main.WOOD_NEXT_RADIUS
	var t1 := _new_node(Constants.RESOURCE_WOOD, base, 1.0, 20.0)
	var t2 := _new_node(Constants.RESOURCE_WOOD, base + Vector3(r * 0.4, 0, 0), 1.0, 500.0)
	# Дерево ЗА пределами делянки — на него игрок уходить не должен
	var t_far := _new_node(Constants.RESOURCE_WOOD, base + Vector3(r * 2.0, 0, 0), 1.0, 500.0)
	await frames(3)

	var w := _new_worker(base + Vector3(0, 0, 1.5))
	await frames(2)
	w.command_gather(t1)
	t1.remaining = 0.0
	w.gather_target = null
	w._auto_find_resource(Constants.RESOURCE_WOOD)
	verdict("D1 срубил — сам пошёл на соседний ствол", w.gather_target == t2,
		"цель=%s (сосед=%s)" % [w.gather_target, t2])

	# Ближний сосед тоже кончился — остаётся только дальний, за делянкой
	t2.remaining = 0.0
	w.gather_target = null
	w.carrying_amount = 0.0
	w._auto_find_resource(Constants.RESOURCE_WOOD)
	verdict("D2 за делянкой рабочий игрока встаёт, а не бежит через карту",
		w.gather_target == null and w.state == Unit.State.IDLE,
		"цель=%s, до дальнего %.1f м при радиусе делянки %.1f" % [
			w.gather_target, r * 2.0, r])

	# ИИ в той же обстановке дальнее дерево возьмёт
	var ai := _new_worker(base + Vector3(0, 0, 1.5), Constants.FACTION_ENEMY)
	await frames(2)
	ai._gather_res_type = Constants.RESOURCE_WOOD
	ai._auto_find_resource(Constants.RESOURCE_WOOD)
	verdict("D3 рабочий ИИ дошёл бы и до дальнего дерева", ai.gather_target == t_far,
		"цель=%s" % [ai.gather_target])

	w.queue_free(); ai.queue_free()
	t1.queue_free(); t2.queue_free(); t_far.queue_free()
	await frames(3)

# ═════════════════════════════════════════════════════════════════════════════
# E. ЗВУК РАБОТЫ
# ═════════════════════════════════════════════════════════════════════════════
func _e_sound() -> void:
	print("\n═════ E. ЗВУК ═════")
	var chop_hz: float = Worker.CHOP_SWING_RATE / TAU
	var mine_hz: float = Worker.MINE_SWING_RATE / TAU
	verdict("E1 топор бьёт чаще кирки", chop_hz > mine_hz,
		"топор %.2f уд/с, кирка %.2f уд/с" % [chop_hz, mine_hz])
	verdict("E2 рубка — не реже удара в секунду", chop_hz >= 0.99,
		"%.2f уд/с (полный взмах %.2f с)" % [chop_hz, 1.0 / chop_hz])

	# Ограничитель категории не должен резать бригаду: окно gap обязано
	# пропускать поток от WORK_DENSITY_FULL рабочих, бьющих в темпе топора
	var lim: Dictionary = AudioManager.SFX_LIMITS["chop"]
	var gap: float = float(lim["gap"])
	var crew: int = AudioManager.WORK_DENSITY_FULL
	var crew_hz: float = chop_hz * float(crew)
	verdict("E3 окно ограничителя пропускает удары полной бригады",
		gap <= 1.0 / crew_hz,
		"бригада %d даёт %.1f уд/с, окно пропускает %.1f уд/с" % [
			crew, crew_hz, 1.0 / gap])
	verdict("E4 голосов рубки хватает на бригаду", int(lim["voices"]) >= 6,
		"voices=%d" % int(lim["voices"]))

# ═════════════════════════════════════════════════════════════════════════════
# F. ДОБЫЧА С ПЕРИМЕТРА — СКВОЗНАЯ ПРОВЕРКА
# ═════════════════════════════════════════════════════════════════════════════
# Разделы A5-A8 проверяют геометрию и пул сами по себе. Здесь то же самое, но
# через настоящего рабочего и настоящий приказ: он обязан дойти, встать СНАРУЖИ,
# начать работать и вычерпывать ОБЩИЙ пул кучи — при этом ни разу не оказавшись
# внутри навала. Именно связка «приказ → место → работа» и разваливалась раньше.
func _f_mining() -> void:
	print("\n═════ F. ДОБЫЧА С ПЕРИМЕТРА ═════")
	var center := Vector3(0.0, 0.0, -520.0)
	main._spawn_resource_cluster(center, Constants.RESOURCE_STONE, true)
	await frames(3)
	var cid: int = main._cluster_seq
	var info: Dictionary = main.res_clusters.get(cid, {})
	var mc = info.get("mine", null)
	if mc == null:
		verdict("F0 куча создана", false, "нет объекта кучи")
		return
	# Склад рядом, чтобы рабочий не убегал сдавать груз через всю карту
	var hub := Castle.new()
	hub.faction = Constants.FACTION_PLAYER
	main.world_add(hub)
	hub.global_position = Vector3(center.x + 22.0, GameManager.get_terrain_height(
		center.x + 22.0, center.z), center.z)
	await frames(3)

	# Кликаем по КРАЙНЕМУ куску — цель обязана подмениться на якорь кучи
	var pieces: Array = []
	for n in get_tree().get_nodes_in_group("resource_nodes"):
		var rn := n as ResourceNode
		if rn != null and rn.cluster_id == cid:
			pieces.append(rn)
	var edge: ResourceNode = pieces[0]
	for p in pieces:
		var rp: ResourceNode = p
		if rp.global_position.distance_to(mc.center) > edge.global_position.distance_to(mc.center):
			edge = rp

	var w := _new_worker(Vector3(center.x + 16.0, 0.0, center.z + 2.0))
	await frames(2)
	w.command_gather(edge)
	verdict("F1 цель добычи — якорь кучи, а не тот камушек, по которому кликнули",
		w.gather_target == edge.gather_anchor(),
		"цель=%s, якорь=%s" % [str(w.gather_target), str(edge.gather_anchor())])
	verdict("F2 приказ ведёт на точку СНАРУЖИ навала",
		not mc.is_inside(w.move_target),
		"точка %s" % str(w.move_target.round()))

	# Идём и работаем. Заодно каждый кадр следим, не залез ли внутрь
	var start_stock: float = float(mc.stock)
	var got_gathering := false
	var breached := false
	for _i in range(900):
		await get_tree().physics_frame
		if mc.is_inside(w.global_position):
			breached = true
		if w.state == Worker.State.GATHERING:
			got_gathering = true
		if got_gathering and float(mc.stock) < start_stock:
			break
	verdict("F3 рабочий дошёл и взялся за работу", got_gathering,
		"state=%d, дистанция до кромки k=%.2f" % [w.state,
			Vector2(w.global_position.x - mc.center.x,
				w.global_position.z - mc.center.z).length()])
	verdict("F4 добыча черпает ОБЩИЙ пул кучи", float(mc.stock) < start_stock,
		"было %.0f, стало %.0f" % [start_stock, float(mc.stock)])
	verdict("F5 внутрь навала рабочий не заходил ни разу", not breached)

	w.queue_free(); hub.queue_free()
	for p2 in pieces:
		if is_instance_valid(p2):
			(p2 as ResourceNode).queue_free()
	await frames(3)

# ═════════════════════════════════════════════════════════════════════════════
# G. ЭКОНОМИЧЕСКАЯ ВЕТКА РАБОЧЕГО В КУЗНИЦЕ
# ═════════════════════════════════════════════════════════════════════════════
# Новые ключи бонусов (bonus_carry, bonus_gather) обязаны ДОХОДИТЬ до рабочего,
# а не оставаться числом в таблице. Числа берутся из конфига, а не пишутся сюда:
# стенд проверяет, что прибавка равна ровно той, что объявлена в узле.
func _g_worker_forge() -> void:
	print("\n═════ G. ВЕТКА РАБОЧЕГО ═════")
	var f: int = Constants.FACTION_PLAYER
	var w := _new_worker(Vector3(0.0, 0.0, -600.0))
	await frames(2)

	# Ищем в древе рабочего узлы с нужными ключами — позицию не хардкодим
	var carry_id := ""
	var carry_val := 0.0
	var gather_id := ""
	var gather_val := 0.0
	for n in _Forge.tree("worker"):
		var d: Dictionary = n
		if carry_id.is_empty() and float(d.get("bonus_carry", 0.0)) > 0.0:
			carry_id = String(d["id"]); carry_val = float(d["bonus_carry"])
		if gather_id.is_empty() and float(d.get("bonus_gather", 0.0)) > 0.0:
			gather_id = String(d["id"]); gather_val = float(d["bonus_gather"])
	verdict("G0 в ветке рабочего есть узлы вместимости и темпа добычи",
		not carry_id.is_empty() and not gather_id.is_empty(),
		"груз=%s (+%.2f), темп=%s (−%.2f с)" % [carry_id, carry_val, gather_id, gather_val])
	if carry_id.is_empty() or gather_id.is_empty():
		w.queue_free()
		return

	var carry0: float = w.carry_capacity()
	var cycle0: float = w._cycle_time()
	GameManager.finish_research(f, carry_id)
	GameManager.finish_research(f, gather_id)
	await frames(2)
	var carry1: float = w.carry_capacity()
	var cycle1: float = w._cycle_time()

	verdict("G1 вместимость выросла ровно на объявленное узлом",
		is_equal_approx(carry1 - carry0, carry_val),
		"было %.1f, стало %.1f (узел даёт %.1f)" % [carry0, carry1, carry_val])
	verdict("G2 цикл добычи сократился ровно на объявленное узлом",
		is_equal_approx(cycle0 - cycle1, gather_val),
		"было %.2f с, стало %.2f с (узел даёт %.2f с)" % [cycle0, cycle1, gather_val])

	# Экономический бонус НЕ должен протекать на бойцов: узлы древа адресные
	var leak: float = GameManager.unit_bonus(f, "spearman", "bonus_carry") \
		+ GameManager.unit_bonus(f, "spearman", "bonus_gather")
	verdict("G3 экономический бонус не протекает на копейщиков",
		is_zero_approx(leak), "утечка %.2f" % leak)

	# Пол цикла: никакая прокачка не должна превратить добычу в струю
	GameManager.unit_bonuses[f]["worker"]["bonus_gather"] = 999.0
	verdict("G4 цикл добычи не опускается ниже порога",
		is_equal_approx(w._cycle_time(), Worker.MIN_CYCLE_TIME),
		"цикл %.2f при пороге %.2f" % [w._cycle_time(), Worker.MIN_CYCLE_TIME])

	w.queue_free()
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# H. НЕДОСТУПНАЯ ЖИЛА: НИКАКОГО «БИТОГО IDLE»
# ═════════════════════════════════════════════════════════════════════════════
# Рабочий, которому назначили жилу, до которой не дойти, раз в секунду
# перевыдавал себе приказ — ВЕЧНО. Работы нет, в счётчик простаивающих он не
# попадает (цель-то назначена), и дёргается так до конца партии. Именно это
# владелец описал как «выпадают в битый Idle с 2-секундным тиком».
#
# Недостижимость здесь делается честно и без физики: жила ставится за пределами
# карты и рабочему запрещается двигаться (set_physics_process на его шаг не
# влияет — тик рабочего зовёт GameManager, — поэтому цель просто уносится так
# далеко, что за отведённое время он до неё не дойдёт).
func _h_stuck() -> void:
	print("\n═════ H. НЕДОСТУПНАЯ ЖИЛА ═════")
	var base := Vector3(0.0, 0.0, -800.0)
	# Ствол, до которого рабочий заведомо не дойдёт за время проверки
	var far_tree := _new_node(Constants.RESOURCE_WOOD, base + Vector3(0, 0, -400.0), 1.0, 500.0)
	# И ЖИВОЙ ствол чуть в стороне — замена, которую он обязан найти
	var near_tree := _new_node(Constants.RESOURCE_WOOD, base + Vector3(6.0, 0, 0), 1.0, 500.0)
	await frames(3)

	var w := _new_worker(base)
	await frames(2)
	w.command_gather(far_tree)
	# Рабочий уже «в состоянии IDLE с назначенной целью»: ровно тот случай,
	# который и уходил в вечный повтор. Двигаться ему не даём
	w.state = Unit.State.IDLE
	w.set_tick(false)
	var issued := 0
	# APPROACH_GIVE_UP попыток по секунде + запас
	for i in range(int(Worker.APPROACH_GIVE_UP) + 3):
		w.set_tick(true)
		w.state = Unit.State.IDLE
		w.tick_physics(1.0)          # ровно одна секунда — ровно одна попытка
		w.set_tick(false)
		issued += 1
		if w.gather_target == null or w.gather_target == near_tree:
			break
		await frames(1)
	verdict("H1 рабочий перестал долбиться в недостижимую жилу",
		w.gather_target != far_tree,
		"попыток %d при пороге %d, цель теперь %s" % [issued, Worker.APPROACH_GIVE_UP,
			"нет" if w.gather_target == null
			else ("ТА ЖЕ недостижимая" if w.gather_target == far_tree else "другая")])
	verdict("H2 и взял доступную замену поблизости",
		w.gather_target == near_tree,
		"цель = %s" % ("соседний ствол" if w.gather_target == near_tree else str(w.gather_target)))

	# Второй случай: замены нет вовсе — рабочий обязан честно встать
	# бездельником, а не топтаться
	near_tree.remaining = 0.0
	w.command_gather(far_tree)
	w.state = Unit.State.IDLE
	for i in range(int(Worker.APPROACH_GIVE_UP) + 3):
		w.set_tick(true)
		w.state = Unit.State.IDLE
		w.tick_physics(1.0)
		w.set_tick(false)
		if w.gather_target == null:
			break
		await frames(1)
	verdict("H3 замены нет — рабочий встал бездельником, а не топчется",
		w.gather_target == null and w.state == Unit.State.IDLE,
		"цель=%s состояние=%d" % ["нет" if w.gather_target == null else "есть", w.state])
	w.queue_free()
	far_tree.queue_free()
	near_tree.queue_free()
	await frames(2)
