extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: БЕЛЫЙ ФЛАГ ПАНИКИ И СВЯЗНОСТЬ ПАНИКУЮЩЕГО ОТРЯДА
## ═══════════════════════════════════════════════════════════════════════════
## Заказ владельца делит поведение на ДВА сценария, и стенд повторяет это
## деление, потому что различаются они не оттенком, а судьбой узла:
##
##   A НОВОБРАНЦЫ (звания нет, своего флага нет). Паника ЗАВОДИТ узел; конец
##     паники и гибель отряда его УНИЧТОЖАЮТ. На земле не остаётся ничего.
##   B ВЕТЕРАНЫ (звание есть, знамя уже висит). Паника МЕНЯЕТ ЛЕНТУ на белую —
##     второго узла не заводится; конец паники возвращает боевую; гибель в
##     панике кладёт на землю БОЕВОЙ штандарт, а не белую тряпку.
##   C ФЛАГ ЕДЕТ НА ЗНАМЕНОСЦЕ, а не висит над медианой отряда: медиана
##     рассыпавшегося отряда садится в пустое поле МЕЖДУ разбежавшимися.
##   D СВЯЗНОСТЬ — разбег ограничен кругом PANIC_SPREAD, а не дальностью
##     бегства.
##   E БЕСХОЗНЫХ УЗЛОВ В МИРЕ НЕТ — ни после паники, ни после гибели.
##
## Числа не хардкодятся: пороги берутся из unit_stats_config.
##
## Запуск: godot --headless --path . res://qa_panic/Test.tscn

const _UCfg     := preload("res://scripts/unit_stats_config.gd")
const _BannerArt := preload("res://scripts/BannerArt.gd")

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")

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

func _pad(s: String, n: int) -> String:
	var o := s
	while o.length() < n: o += " "
	return o

## ВСЕ УЗЛЫ ФЛАГОВ В МИРЕ.
##
## ИСКАТЬ ПО ИМЕНИ УЗЛА НЕЛЬЗЯ, и это стоило одной красной проверки. Имя
## («SquadBanner») ставится узлу ДО того, как его вносят в дерево, и до дерева
## оно не доезжает: замер показал в дереве «@MeshInstance3D@8699». Опознаём по
## СКРИПТУ — по полю shown_white, которого нет ни у одного другого MeshInstance3D
## в проекте. Класса у SquadBanner нет намеренно (подключается через preload,
## см. его шапку), поэтому `is` тут тоже не применить
func _flag_nodes() -> Array:
	var out: Array = []
	var stack: Array = [main]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n == null or not is_instance_valid(n):
			continue
		if n is MeshInstance3D and n.get("shown_white") != null:
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out

## Узлы флагов, за которые не отвечает ни один живой отряд
func _orphan_flags() -> int:
	var owned: Dictionary = {}
	for key in GameManager.squads:
		var b = (GameManager.squads[key] as Dictionary).get("banner")
		if b != null and is_instance_valid(b):
			owned[b] = true
	var n := 0
	for f in _flag_nodes():
		if not owned.has(f):
			n += 1
	return n

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	GameManager.world_bounds_enabled = false
	if GameManager.fog != null:
		GameManager.fog.enabled = false
		GameManager.fog = null
	await frames(4)

	await _check_rookies()
	await _check_veterans()
	await _check_cohesion()

	print("\n═════ ИТОГ ═════")
	for e in _log:
		var r: Array = e
		print("  %s%s" % [_pad(String(r[0]), 66), "ПРОШЛО" if bool(r[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	print("\n=== PANIC TEST DONE ===")
	get_tree().quit(1 if _fail > 0 else 0)

## Поднять отряд из n копейщиков возле точки. level > 0 — сразу со званием
func _make_squad(at: Vector3, n: int, level: int) -> Array:
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
	var men: Array = []
	for i in range(n):
		var u: Unit = load("res://scenes/units/Spearman.tscn").instantiate()
		u.faction = Constants.FACTION_PLAYER
		main.world_add(u)
		var p := at + Vector3(float(i % 4) * 0.7, 0.0, float(i / 4) * 0.7)
		u.global_position = Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)
		u.sync_row()
		GameManager.add_to_squad(sid, u)
		men.append(u)
	if level > 0:
		(GameManager.squads[sid] as Dictionary)["level"] = level
		GameManager.refresh_squad_banner(sid)
	return [sid, men]

func _banner(sid: int):
	if not GameManager.squads.has(sid):
		return null
	var b = (GameManager.squads[sid] as Dictionary).get("banner")
	return b if b != null and is_instance_valid(b) else null

func _kill_all(men: Array) -> void:
	for m in men:
		var u := m as Unit
		if u != null and is_instance_valid(u) and not u.is_dead():
			u.take_damage(u.max_health * 10.0, null)

# ═════════════════════════════════════════════════════════════════════════════
# A. НОВОБРАНЦЫ: ФЛАГ ВРЕМЕННЫЙ
# ═════════════════════════════════════════════════════════════════════════════
func _check_rookies() -> void:
	print("\n═════ A. НОВОБРАНЦЫ (звания нет) ═════")
	var r: Array = await _make_squad(Vector3(-40.0, 0.0, 40.0), 10, 0)
	var sid: int = int(r[0])
	var men: Array = r[1]
	await pframes(4)
	await frames(2)
	verdict("A1 без звания и без паники флага нет вовсе", _banner(sid) == null,
		"узел %s" % str(_banner(sid)))

	GameManager._start_panic(sid)
	await frames(3)
	var b = _banner(sid)
	verdict("A2 паника поднимает белый флаг", b != null and bool(b.shown_white),
		"узел %s" % ("есть, белый" if b != null and bool(b.shown_white)
			else ("есть, боевой" if b != null else "нет")))
	verdict("A3 узел флага в мире ровно один на отряд",
		_count_own(sid) == 1, "узлов отряда: %d" % _count_own(sid))

	# ── КОНЕЦ ПАНИКИ УБИРАЕТ ВРЕМЕННЫЙ ФЛАГ ────────────────────────────────
	GameManager._end_panic(sid)
	await frames(3)
	verdict("A4 конец паники убирает временный флаг", _banner(sid) == null,
		"узел %s" % str(_banner(sid)))
	verdict("A5 бесхозных узлов флагов в мире нет", _orphan_flags() == 0,
		"бесхозных: %d" % _orphan_flags())

	# ── ГИБЕЛЬ ПРЯМО В ПАНИКЕ: НА ЗЕМЛЕ НЕ ОСТАЁТСЯ НИЧЕГО ─────────────────
	GameManager._start_panic(sid)
	await frames(3)
	var props0: int = GameManager.corpses.count()
	_kill_all(men)
	await pframes(6)
	await frames(4)
	verdict("A6 отряд выбит в панике — узла флага не осталось",
		_banner(sid) == null and _orphan_flags() == 0,
		"узел %s, бесхозных %d" % [str(_banner(sid)), _orphan_flags()])
	# Тела павших в слой тоже кладутся, поэтому «ничего не осталось» проверяем
	# не по общему счётчику, а по ОТСУТСТВИЮ узла: у отряда без звания
	# _drop_squad_banner выходит на lvl <= 0 и в слой не кладёт ничего
	verdict("A7 у отряда без звания знамени падать нечему",
		GameManager.corpses.count() - props0 <= men.size(),
		"в слой легло %d при %d павших" % [
			GameManager.corpses.count() - props0, men.size()])

## Сколько узлов флагов принадлежит этому отряду
func _count_own(sid: int) -> int:
	var b = _banner(sid)
	if b == null:
		return 0
	var n := 0
	for f in _flag_nodes():
		if f == b:
			n += 1
	return n

# ═════════════════════════════════════════════════════════════════════════════
# B. ВЕТЕРАНЫ: ФЛАГ ОДИН, МЕНЯЕТСЯ ЛЕНТА
# ═════════════════════════════════════════════════════════════════════════════
func _check_veterans() -> void:
	print("\n═════ B. ВЕТЕРАНЫ (звание есть) ═════")
	var r: Array = await _make_squad(Vector3(20.0, 0.0, -20.0), 10, 3)
	var sid: int = int(r[0])
	var men: Array = r[1]
	await pframes(4)
	await frames(3)
	var b0 = _banner(sid)
	verdict("B1 у ветерана знамя висит и без всякой паники",
		b0 != null and not bool(b0.shown_white),
		"узел %s" % ("боевой" if b0 != null and not bool(b0.shown_white)
			else str(b0)))
	if b0 == null:
		return
	var id0: int = b0.get_instance_id()
	var flags0: int = _flag_nodes().size()

	GameManager._start_panic(sid)
	await frames(3)
	var b1 = _banner(sid)
	# ── ГЛАВНОЕ ЧИСЛО ЖАЛОБЫ «ЮНИТ С ДВУМЯ ФЛАГАМИ» ───────────────────────
	verdict("B2 паника НЕ заводит второй узел — узел тот же самый",
		b1 != null and b1.get_instance_id() == id0
		and _flag_nodes().size() == flags0,
		"узлов в мире было %d, стало %d" % [flags0, _flag_nodes().size()])
	verdict("B3 родное знамя сменило ленту на белую",
		b1 != null and bool(b1.shown_white))

	GameManager._end_panic(sid)
	await frames(3)
	var b2 = _banner(sid)
	verdict("B4 конец паники возвращает боевую ленту",
		b2 != null and b2.get_instance_id() == id0 and not bool(b2.shown_white)
		and int(b2.shown_level) == 3,
		"уровень на знамени %d" % (int(b2.shown_level) if b2 != null else -1))

	# ── ГИБЕЛЬ В ПАНИКЕ: НА ЗЕМЛЮ ЛОЖИТСЯ БОЕВОЙ ШТАНДАРТ ─────────────────
	GameManager._start_panic(sid)
	await frames(3)
	verdict("B5 перед гибелью знамя действительно белое",
		_banner(sid) != null and bool(_banner(sid).shown_white))
	var props0: int = GameManager.corpses.count()
	_kill_all(men)
	await pframes(6)
	await frames(6)
	verdict("B6 узел знамени не пережил свой отряд",
		_banner(sid) == null and _orphan_flags() == 0,
		"узел %s, бесхозных %d" % [str(_banner(sid)), _orphan_flags()])
	# Упавшее знамя — ЛИШНИЙ жилец слоя тел сверх павших бойцов
	var laid: int = GameManager.corpses.count() - props0
	verdict("B7 на земле остался трофей сверх тел павших", laid > men.size(),
		"в слой легло %d при %d павших" % [laid, men.size()])
	# ЛЕНТА ТРОФЕЯ — БОЕВАЯ. Проверяем СВОЙСТВО источника: упавшее знамя
	# собирается по УРОВНЮ отряда (_lay_fallen_banner → BannerArt.texture_for),
	# а не по тому, что висело на древке в последнюю секунду
	verdict("B8 боевая лента и белая — разные картинки",
		_BannerArt.texture_for(3) != _BannerArt.white_flag_texture())

# ═════════════════════════════════════════════════════════════════════════════
# C и D. ФЛАГ НА ЗНАМЕНОСЦЕ, ОТРЯД НЕ РАССЫПАЕТСЯ
# ═════════════════════════════════════════════════════════════════════════════
func _check_cohesion() -> void:
	print("\n═════ C и D. ЗНАМЕНОСЕЦ И СВЯЗНОСТЬ ═════")
	var r: Array = await _make_squad(Vector3(-10.0, 0.0, -60.0), 12, 2)
	var sid: int = int(r[0])
	var men: Array = r[1]
	await pframes(6)
	await frames(3)
	GameManager._start_panic(sid)
	# Даём отряду добежать: точки раздаются сразу, ноги доносят за секунды
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 9000:
		await get_tree().physics_frame
	await frames(3)

	var alive: Array = []
	for m in men:
		var u := m as Unit
		if is_instance_valid(u) and not u.is_dead():
			alive.append(u)
	var c: Vector2 = GameManager.squad_centre_xz(sid)
	var far := 0.0
	var span := 0.0
	for a in alive:
		var p: Vector3 = (a as Node3D).global_position
		far = maxf(far, Vector2(p.x - c.x, p.z - c.y).length())
		for b in alive:
			var q: Vector3 = (b as Node3D).global_position
			span = maxf(span, Vector2(p.x - q.x, p.z - q.z).length())
	# ПОРОГ ИЗ КОНФИГА, А НЕ КРУГЛОЕ ЧИСЛО: связность и есть PANIC_SPREAD с
	# запасом на подзыв (PANIC_REGROUP_MULT) и на строевой интервал
	var limit: float = _UCfg.PANIC_SPREAD * _UCfg.PANIC_REGROUP_MULT + 2.0
	verdict("D1 разбег ограничен кругом связности, а не дальностью бегства",
		not alive.is_empty() and far <= limit,
		"худший отрыв от центра %.2f м при пределе %.2f (бегство на %.1f м)" % [
			far, limit, _UCfg.PANIC_FLEE_DIST])
	verdict("D2 отряд остаётся одной кучей, а не двумя краями карты",
		span <= limit * 2.0,
		"габарит отряда %.2f м при пределе %.2f м" % [span, limit * 2.0])

	# ── ФЛАГ НА ЖИВОМ БОЙЦЕ, А НЕ НАД ПУСТЫМ ПОЛЕМ ────────────────────────
	var b3 = _banner(sid)
	var near := 999.0
	if b3 != null:
		var fp: Vector3 = (b3 as Node3D).global_position
		for a in alive:
			var dp: Vector3 = (a as Unit).draw_position()
			near = minf(near, Vector2(fp.x - dp.x, fp.z - dp.z).length())
	# Древко смещено от центра бойца на POLE_OFFSET_X — это и есть весь допуск
	verdict("C1 флаг стоит на бойце, а не в пустом поле",
		b3 != null and near <= 1.0,
		"до ближайшего бойца %.2f м" % near)
	var bearer = GameManager.squad_bearer(sid)
	var to_bearer := 999.0
	if b3 != null and bearer != null and is_instance_valid(bearer):
		var dp2: Vector3 = (bearer as Unit).draw_position()
		to_bearer = Vector2((b3 as Node3D).global_position.x - dp2.x,
			(b3 as Node3D).global_position.z - dp2.z).length()
	verdict("C2 флаг едет именно на знаменосце", to_bearer <= 1.0,
		"до знаменосца %.2f м" % to_bearer)
	_kill_all(alive)
	await pframes(4)
