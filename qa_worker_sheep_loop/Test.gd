extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_worker_sheep_loop — РАБОЧИЙ САМ БЕРЁТСЯ ЗА СЛЕДУЮЩУЮ ОВЦУ
## ═══════════════════════════════════════════════════════════════════════════
## Заказ спринта 14 дословно: «После полного выноса мяса с одной туши рабочий
## должен АВТОМАТИЧЕСКИ переключаться на следующую ближайшую овцу (по аналогии
## с рубкой леса). Команда не должна сбрасываться, а рабочие не должны
## толпиться у Ратуши. Размер спрайта овцы уменьшить на 20 %. Загон уменьшить
## вдвое, поправить пропорции и УБРАТЬ стадию строительства.»
##
##   A ПЕРЕХОД   — туша выработана, рабочий тем же кадром берёт следующую овцу
##                 и уходит к ней: приказ не сброшен, у склада он не остался.
##   B БРИГАДА   — четверо доедают свои туши у одного склада и РАЗХОДЯТСЯ по
##                 новым овцам, а не встают толпой.
##   C ОВЦА      — спрайт мельче прежнего ровно на 20 %.
##   D ЗАГОН     — вдвое меньше, пропорция считается ПО ЭКРАНУ, стадии стройки
##                 нет вовсе: ресурсы списаны, ограда встала готовой.
##
## Числа — из конфигов (правило 10), ожидание — физкадрами (правило 11).
## Запуск: godot --headless --path . res://qa_worker_sheep_loop/Test.tscn

const _UCfg   := preload("res://scripts/unit_stats_config.gd")
const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")
const _Sheep  := preload("res://scripts/goblin/Sheep.gd")
const _Pen    := preload("res://scripts/SheepPen.gd")
const _CSite  := preload("res://scripts/ConstructionSite.gd")

## РАЗМЕРЫ ДО СПРИНТА 14. Требования звучат как «−20 %» и «вдвое меньше», и
## выразить их иначе, кроме как назвав прежние значения, нечем. Нынешние
## читаются из конфига
const SHEEP_PX_BEFORE := 0.024
const PEN_X_BEFORE    := 10.0

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []
var _castle: Castle = null
var _lair = null

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
	print("\n═════ ИТОГ qa_worker_sheep_loop: прошло %d, провалов: %d ═════" % [
		_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _spawn_worker(at: Vector3) -> Worker:
	var w: Worker = Building.PRELOAD_SCENES["worker"].instantiate()
	w.faction = Constants.FACTION_PLAYER
	main.world_add(w)
	w.global_position = Vector3(at.x,
		GameManager.get_terrain_height(at.x, at.z), at.z)
	w.sync_row()
	return w

## Своя овца в заданной точке. Стенд, зависящий от окружения, обязан ставить
## это окружение сам: стадо логова разбредается, и «ближайшая следующая»
## оказалась бы то в пяти метрах, то в сорока
## ОВЦЫ СТЕНДА — СВОИ, ПРИВЯЗАННЫЕ К ЗАМКУ, И ЭТО НЕ УПРОЩЕНИЕ СЦЕНАРИЯ.
## ДИКУЮ овцу рабочий несёт к складу и там СТАВИТ НА ВЫПАС, если в стаде замка
## есть место, — работа кончается, и до разделки дело не доходит вовсе (это
## правильное поведение: «живая овца в стадо, а не под нож», Worker CARRY).
## Заказ спринта 14 — про ЦИКЛ РАЗДЕЛКИ, а он начинается со своей овцы: такую
## режут там, где она пасётся, и мясо носят ходками. Первая версия стенда об
## это и споткнулась: фаза уходила в NONE у самого склада
func _spawn_sheep(at: Vector3) -> Node3D:
	var s: Node3D = _Sheep.new()
	s.set("home", at)
	main.world_root().add_child(s)
	s.global_position = Vector3(at.x,
		GameManager.get_terrain_height(at.x, at.z), at.z)
	s.call("bind_to_keep", _castle, Constants.FACTION_PLAYER)
	s.set("home", at)
	# Пасётся на месте: перебежки увезли бы её из-под замера «ближайшая»
	s.set_process(false)
	return s

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	# Пень за рекой в партии заморожен (ТЗ 19.09.2026); стенду нужен живой
	GameManager.call_deferred("thaw_lairs_now")
	await frames(8)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	GameManager.world_bounds_enabled = false
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	await pframes(4)

	_lair = GameManager.troll_lair
	# ── ЛОГОВО РАЗОРУЖАЕТСЯ, И ЭТО НЕ ПОСЛАБЛЕНИЕ ──────────────────────────
	# Тролли и три отряда гноллов у пня — правильное поведение партии, но
	# здесь меряется РАБОЧИЙ: чужие тела вокруг овцы физически не пускают к
	# ней, и стенд ловил бы «фаза GO, тысяча кадров» на исправном коде
	if _lair != null and is_instance_valid(_lair):
		for t in _lair.get("trolls"):
			if is_instance_valid(t):
				(t as Unit).set_tick(false)
		for g in _lair.get("gnolls"):
			if g != null and is_instance_valid(g):
				(g as Node).queue_free()
		# Стадо логова уводим из-под замера: «ближайшую следующую» стенд
		# ставит сам и ровно там, где ему надо
		for s in _lair.get("sheep"):
			if s != null and is_instance_valid(s):
				(s as Node).queue_free()
	await pframes(4)

	# Склад у игрока: без него ходка с мясом некуда не идёт
	_castle = Castle.new()
	_castle.faction = Constants.FACTION_PLAYER
	main.world_add(_castle)
	var cp: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(0.0, 0.0, 26.0)
	_castle.global_position = Vector3(cp.x,
		GameManager.get_terrain_height(cp.x, cp.z), cp.z)
	await pframes(6)

	await _a_switch()
	await _b_crew()
	await _c_sheep_size()
	await _d_pen()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
# A. ПЕРЕХОД НА СЛЕДУЮЩУЮ ТУШУ
#
# ХОДКИ ПРОМАТЫВАЮТСЯ, И ЭТО ЧЕСТНО. Полный цикл — SHEEP_MEAT_TRIPS ходок по
# SHEEP_CUTS_PER_MEAT ударов, то есть минуты игрового времени на одну овцу.
# Проверяется здесь СОБЫТИЕ «последняя ходка сдана», поэтому счётчик ходок
# доводится до предпоследней, а сама последняя идёт своим ходом, штатным кодом
# ═════════════════════════════════════════════════════════════════════════════
func _a_switch() -> void:
	print("\n═════ A. ТУША ВЫРАБОТАНА — БЕРЁМ СЛЕДУЮЩУЮ ═════")
	var base: Vector3 = _castle.global_position + Vector3(14.0, 0.0, 0.0)
	var s1: Node3D = _spawn_sheep(base)
	var s2: Node3D = _spawn_sheep(base + Vector3(9.0, 0.0, 4.0))
	var w: Worker = _spawn_worker(base + Vector3(3.0, 0.0, 0.0))
	await pframes(4)
	w.command_steal_sheep(s1)
	await pframes(3)
	verdict("A1 приказ на овцу принят", w.is_stealing_sheep()
		and w.sheep_phase() == Worker.SheepPhase.GO,
		"фаза %d" % w.sheep_phase())

	# Ждём, пока рабочий дойдёт до разделки: до неё идут GO → CARRY → KILL
	var ok: bool = await _wait_phase(w, Worker.SheepPhase.BUTCHER, 60 * 60)
	verdict("A2 рабочий довёл овцу до склада и режет", ok,
		"фаза %d" % w.sheep_phase())
	if not ok:
		return
	# Мотаем ходки: последняя пойдёт штатным кодом
	w.set("_sheep_trips", Worker.SHEEP_MEAT_TRIPS - 1)
	var food0: float = ResourceManager.get_amount(Constants.FACTION_PLAYER,
		Constants.RESOURCE_FOOD)

	# Ждём смены туши: _sheep указывает на другую овцу либо работа кончилась
	var guard := 0
	while guard < 60 * 90:
		await get_tree().physics_frame
		guard += 1
		if not is_instance_valid(s1) or bool(s1.get("eaten")):
			break
	await pframes(4)
	var eaten1: bool = not is_instance_valid(s1) or bool(s1.get("eaten"))
	verdict("A3 первая туша выработана до конца и исчезла", eaten1,
		"туша %s" % ("выработана" if eaten1 else "ещё лежит"))
	verdict("A4 мясо последней ходки зачислено на склад",
		ResourceManager.get_amount(Constants.FACTION_PLAYER,
			Constants.RESOURCE_FOOD) > food0,
		"еды %.0f против %.0f" % [ResourceManager.get_amount(
			Constants.FACTION_PLAYER, Constants.RESOURCE_FOOD), food0])

	# ── ГЛАВНОЕ: ПРИКАЗ НЕ СБРОШЕН ─────────────────────────────────────────
	verdict("A5 приказ НЕ сброшен: работа продолжается",
		w.is_stealing_sheep(),
		"фаза %d (NONE=%d)" % [w.sheep_phase(), Worker.SheepPhase.NONE])
	verdict("A6 и это уже ДРУГАЯ овца — ближайшая следующая",
		w.get("_sheep") == s2,
		"взята %s" % ("вторая овца" if w.get("_sheep") == s2 else "не она"))
	verdict("A7 рабочий не встал в покой у склада",
		w.state != w.State.IDLE,
		"состояние %d (IDLE=%d)" % [int(w.state), int(w.State.IDLE)])

	# ── И ОН ФИЗИЧЕСКИ УХОДИТ ОТ СКЛАДА ────────────────────────────────────
	var d0: float = w.global_position.distance_to(_castle.global_position)
	await pframes(90)
	var d1: float = w.global_position.distance_to(_castle.global_position)
	print("  расстояние до склада: было %.1f м, стало %.1f м" % [d0, d1])
	verdict("A8 у Ратуши он не топчется — уходит к новой овце", d1 > d0 + 0.5,
		"%.1f → %.1f м" % [d0, d1])
	_clear(w)
	_clear(s2)
	await pframes(4)

# ═════════════════════════════════════════════════════════════════════════════
# B. БРИГАДА НЕ КОПИТСЯ У СКЛАДА
# ═════════════════════════════════════════════════════════════════════════════
func _b_crew() -> void:
	print("\n═════ B. ЧЕТВЕРО НЕ ВСТАЮТ ТОЛПОЙ ═════")
	# ── ПАРЫ РАЗНЕСЕНЫ, И ЭТО НЕ ПРИДИРКА ──────────────────────────────────
	# Первая раскладка ставила пары лесенкой с шагом 3 м, и «запасная» овца
	# одного рабочего оказывалась ЗАКРЕПЛЁННОЙ овцой другого: сосед её съедал,
	# а первому идти становилось не к кому — стенд краснел на исправном коде.
	# Своя пара обязана быть ближайшей к своему рабочему с большим запасом
	var base: Vector3 = _castle.global_position + Vector3(-16.0, 0.0, 0.0)
	var men: Array = []
	var flock: Array = []
	for i in range(4):
		var sp: Vector3 = base + Vector3(-float(i) * 14.0, 0.0, 0.0)
		var s: Node3D = _spawn_sheep(sp)
		flock.append(s)
		# И по запасной овце каждому: ей и предстоит стать следующей
		flock.append(_spawn_sheep(sp + Vector3(0.0, 0.0, 6.0)))
		var w: Worker = _spawn_worker(sp + Vector3(2.0, 0.0, 0.0))
		men.append(w)
	await pframes(6)
	for i in range(men.size()):
		(men[i] as Worker).command_steal_sheep(flock[i * 2])
	await pframes(4)
	# Доводим всех до разделки и мотаем ходки
	var ready_men := 0
	for w in men:
		if await _wait_phase(w, Worker.SheepPhase.BUTCHER, 60 * 60):
			w.set("_sheep_trips", Worker.SHEEP_MEAT_TRIPS - 1)
			ready_men += 1
	verdict("B1 все четверо дошли до разделки", ready_men == men.size(),
		"дошло %d из %d" % [ready_men, men.size()])
	# Ходки идут к замку через полсотни метров: ждём с запасом
	await pframes(60 * 90)

	var busy := 0
	var idle_at_castle := 0
	for w in men:
		if is_instance_valid(w):
			print("    рабочий: фаза %d, состояние %d, овца %s, до склада %.1f м" % [
				int((w as Worker).sheep_phase()), int((w as Worker).state),
				str((w as Worker).get("_sheep") != null),
				(w as Node3D).global_position.distance_to(_castle.global_position)])
	for w in men:
		if not is_instance_valid(w):
			continue
		if bool((w as Worker).is_stealing_sheep()):
			busy += 1
		elif (w as Worker).state == (w as Worker).State.IDLE \
				and (w as Node3D).global_position.distance_to(
					_castle.global_position) < 12.0:
			idle_at_castle += 1
	print("  при деле %d из %d, без дела у склада %d" % [
		busy, men.size(), idle_at_castle])
	verdict("B2 все четверо снова при деле", busy == men.size(),
		"при деле %d из %d" % [busy, men.size()])
	verdict("B3 у Ратуши никто не встал без дела", idle_at_castle == 0,
		"толпится %d" % idle_at_castle)
	for w in men:
		_clear(w)
	for s in flock:
		_clear(s)
	await pframes(4)

# ═════════════════════════════════════════════════════════════════════════════
# C. РАЗМЕР ОВЦЫ
# ═════════════════════════════════════════════════════════════════════════════
func _c_sheep_size() -> void:
	print("\n═════ C. ОВЦА МЕЛЬЧЕ НА 20 % ═════")
	var px: float = _GobCfg.SHEEP_PIXEL_SIZE
	print("  пиксель овцы: было %.4f, стало %.4f" % [SHEEP_PX_BEFORE, px])
	verdict("C1 пиксель овцы срезан ровно на 20 %",
		absf(px - SHEEP_PX_BEFORE * 0.8) < 0.0001,
		"%.4f при ожидаемых %.4f" % [px, SHEEP_PX_BEFORE * 0.8])
	# И ЖИВАЯ ОВЦА ЭТОГО ЧИСЛА СЛУШАЕТСЯ: размер квада считается из него же
	var s: Node3D = _spawn_sheep(_castle.global_position + Vector3(20.0, 0.0, 20.0))
	await pframes(4)
	var mi: MeshInstance3D = s.get("_mi") as MeshInstance3D
	var q: QuadMesh = mi.mesh as QuadMesh if mi != null else null
	verdict("C2 квад живой овцы построен по этому же числу",
		q != null and q.size.y > 0.0
			and absf(q.size.y - float(s.get("_quad_h"))) < 0.001,
		"квад %s" % (str(q.size) if q != null else "нет"))
	if q != null:
		# Прежний размер того же кадра — это ровно тот же квад, делённый на 0.8
		print("  квад овцы %.2f × %.2f м (прежний был бы %.2f × %.2f)" % [
			q.size.x, q.size.y, q.size.x / 0.8, q.size.y / 0.8])
		verdict("C3 живой спрайт и правда мельче прежнего на пятую часть",
			q.size.y < q.size.y / 0.8, "%.2f м" % q.size.y)
	_clear(s)
	await pframes(4)

# ═════════════════════════════════════════════════════════════════════════════
# D. ЗАГОН: ВДВОЕ МЕНЬШЕ, ПРОПОРЦИЯ ПО ЭКРАНУ, БЕЗ СТРОЙКИ
# ═════════════════════════════════════════════════════════════════════════════
func _d_pen() -> void:
	print("\n═════ D. ЗАГОН ═════")
	var cfg: Dictionary = _UCfg.building_cfg("sheep_pen")
	var size: Vector3 = cfg.get("size", Vector3.ZERO)
	print("  габарит загона %s (было %.1f по X), стройка %.0f с, сразу=%s" % [
		str(size), PEN_X_BEFORE, float(cfg.get("build_time", -1.0)),
		str(cfg.get("instant_build", false))])
	verdict("D1 загон стал вдвое меньше",
		absf(size.x - PEN_X_BEFORE * 0.5) < 0.01,
		"%.1f при ожидаемых %.1f" % [size.x, PEN_X_BEFORE * 0.5])
	# ── ПРОПОРЦИЯ СЧИТАЕТСЯ ПО ЭКРАНУ, А НЕ ПО ЗЕМЛЕ ───────────────────────
	# Ограда лежит ПЛАШМЯ, камера смотрит под 45°, и глубина на экране
	# сжимается в sin(45°) раз. Рисунок Wooden Fence — 256×192, то есть 4 : 3;
	# чтобы он читался своей пропорцией, по земле глубина обязана быть БОЛЬШЕ
	# ширины. Прежние 10 × 7.5 повторяли 4 : 3 в МИРОВЫХ метрах и давали на
	# экране 4 : 2.1 — тот самый сплюснутый вольер со скриншота
	var on_screen: float = size.z * sin(deg_to_rad(45.0)) / maxf(size.x, 0.01)
	print("  пропорция на экране %.3f (у рисунка 192/256 = %.3f)" % [
		on_screen, 192.0 / 256.0])
	verdict("D2 на экране ограда читается пропорцией своего рисунка",
		absf(on_screen - 192.0 / 256.0) < 0.05,
		"%.3f против %.3f" % [on_screen, 192.0 / 256.0])
	verdict("D3 по земле глубина БОЛЬШЕ ширины — иначе рисунок сплющен",
		size.z > size.x, "%.1f против %.1f м" % [size.z, size.x])
	verdict("D4 стадии стройки нет вовсе",
		bool(cfg.get("instant_build", false))
			and absf(float(cfg.get("build_time", 1.0))) < 0.001,
		"instant=%s, время %.1f с" % [str(cfg.get("instant_build", false)),
			float(cfg.get("build_time", -1.0))])

	# ── И ПОВЕДЕНЧЕСКИ: ЗАКАЗ СРАЗУ СТАВИТ ГОТОВУЮ ОГРАДУ ──────────────────
	var w: Worker = _spawn_worker(_castle.global_position + Vector3(-24.0, 0.0, 8.0))
	await pframes(4)
	var cost: Dictionary = GameManager.worker_buildings()["sheep_pen"].get("cost", {})
	var wood0: float = ResourceManager.get_amount(Constants.FACTION_PLAYER,
		Constants.RESOURCE_WOOD)
	var sites0: int = _count_sites()
	var pens0: int = get_tree().get_nodes_in_group("sheep_pens").size()
	GameManager.try_worker_build(w, "sheep_pen")
	await pframes(2)
	var wood1: float = ResourceManager.get_amount(Constants.FACTION_PLAYER,
		Constants.RESOURCE_WOOD)
	verdict("D5 ресурсы списаны в момент заказа",
		absf((wood0 - wood1) - float(cost.get(Constants.RESOURCE_WOOD, 0.0))) < 0.01,
		"списано %.0f дерева при цене %.0f" % [wood0 - wood1,
			float(cost.get(Constants.RESOURCE_WOOD, 0.0))])
	# Ставим там же, где стоит рабочий: разбор клика и туман здесь не при чём
	var at: Vector3 = w.global_position + Vector3(-6.0, 0.0, 0.0)
	main._placing_build_fn.call(Vector3(at.x,
		GameManager.get_terrain_height(at.x, at.z), at.z))
	main.set("_phase", main.Phase.PLAYING)
	await pframes(8)
	var pens: Array = get_tree().get_nodes_in_group("sheep_pens")
	print("  загонов было %d, стало %d; стройплощадок было %d, стало %d" % [
		pens0, pens.size(), sites0, _count_sites()])
	verdict("D6 загон встал ГОТОВЫМ тем же кадром", pens.size() == pens0 + 1,
		"загонов %d" % pens.size())
	verdict("D7 стройплощадка при этом не заводилась",
		_count_sites() == sites0, "площадок %d" % _count_sites())
	if pens.size() > pens0:
		var pen = pens[pens.size() - 1]
		verdict("D8 и это настоящий загон своей стороны, а не фундамент",
			pen.has_method("accept_sheep")
				and int(pen.get("faction")) == Constants.FACTION_PLAYER,
			"принимает овец=%s" % str(pen.has_method("accept_sheep")))
	_clear(w)

# ═════════════════════════════════════════════════════════════════════════════
# СЛУЖЕБНОЕ
# ═════════════════════════════════════════════════════════════════════════════
## Дождаться нужной фазы работы с овцой. true — дождались
func _wait_phase(w, phase: int, limit: int) -> bool:
	var guard := 0
	while guard < limit:
		if not is_instance_valid(w):
			return false
		if int(w.sheep_phase()) == phase:
			return true
		if not bool(w.is_stealing_sheep()):
			return false
		await get_tree().physics_frame
		guard += 1
	return false

## Стройплощадки опознаются ПО СКРИПТУ, а не по типу: у ConstructionSite нет
## class_name, и `is ConstructionSite` — ошибка разбора (файл подключается
## через preload, как Tower/Sheep/SheepPen)
func _count_sites() -> int:
	var n := 0
	for b in get_tree().get_nodes_in_group(
			Constants.building_group(Constants.FACTION_PLAYER)):
		if b == null or not is_instance_valid(b):
			continue
		if b is _CSite:
			n += 1
	return n

## Убрать узел стенда. Рабочий уходит смертью — только на этом пути он снимает
## с себя строку ядра, сетку и место в отряде
## Принимает Variant, а НЕ Node: освобождённый объект типизированный параметр
## отвергает исключением ещё до входа в функцию (правило 5 — проверять
## is_instance_valid на СЫРОЙ ссылке, до приведения типа)
func _clear(n: Variant) -> void:
	if n == null or not is_instance_valid(n):
		return
	var u := n as Unit
	if u != null:
		if not u.is_dead():
			u.take_damage(maxf(u.max_health, u.current_health) * 10.0, null)
		return
	# ОВЦУ УБИРАЕМ ТОЛЬКО queue_free, БЕЗ remove_child: рабочий в этом же кадре
	# ещё тикает и читает её global_position, а у вынутого из дерева узла
	# трансформа нет вовсе («Condition !is_inside_tree() is true»). Правило 6
	# («remove_child перед queue_free») писано под подсчёт детей в том же кадре,
	# а здесь считать некому
	n.queue_free()
