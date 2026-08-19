extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ПОСТРОЕНИЕ ГРУППЫ ПО РАСТЯНУТОМУ ПКМ
## ═══════════════════════════════════════════════════════════════════════════
##   A ЦЕНТРИРОВАНИЕ — тыловой эшелон (лучники) встаёт ПО ЦЕНТРУ фронта
##                     копейщиков, а не растягивается на всю линию ниткой
##                     и не сваливается на фланг
##   B БЕЗ ПЕРЕТАСОВКИ — отряды получают участки линии по своему фактическому
##                     положению: кто стоял левее, тот левее и встал. Векторы
##                     движения параллельны, пути не пересекаются
##
## Проверяются СВОЙСТВА раскладки, а не числа из конфига: ширина фронта берётся
## из самой раскладки, доля тыла — из отношения численностей, порядок — из
## сравнения «до» и «после». Поменяются интервалы строя — стенд не покраснеет.
##
## Считается ПЛАН (_layered_formation_slots / _block_formation_slots), а не
## итог марша: это чистая геометрия приказа, и мешать её с ходьбой, деревьями и
## расталкиванием незачем — для ходьбы есть qa_group_grid.

var main = null
var sel = null
var _pass := 0
var _fail := 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")

func pframes(n: int) -> void:
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

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(8)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	GameManager.world_bounds_enabled = false
	sel = main.selection_manager
	await pframes(2)

	await _a_center_rear()
	await _b_no_cross()

	print("\n═════ ИТОГ ═════")
	for e in _log:
		var row: Array = e
		print("  %s%s" % [_pad(String(row[0]), 62), "ПРОШЛО" if bool(row[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	print("\n=== QA_LINE2 DONE ===")
	get_tree().quit(1 if _fail > 0 else 0)

func _spawn(kind: String, pos: Vector3) -> Unit:
	var u: Unit
	match kind:
		"spearman": u = Spearman.new()
		"archer":   u = Archer.new()
		_:          u = Warrior.new()
	u.faction = Constants.FACTION_PLAYER
	main.world_add(u)
	u.global_position = Vector3(pos.x, GameManager.get_terrain_height(pos.x, pos.z), pos.z)
	u.sync_row()
	u.set_physics_process(false)     # план считается по СТОЯЩИМ: ходьба здесь лишняя
	return u

## Отряд из n бойцов кучкой вокруг точки
func _make_squad(kind: String, at: Vector3, n: int) -> Array:
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, kind)
	var men: Array = []
	for i in range(n):
		var u := _spawn(kind, at + Vector3(float(i % 5) * 0.6, 0.0, float(i / 5) * 0.6))
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return men

## Проекции слотов на ось линии — по ним и меряются ширина и центр эшелона
func _spread(slots: Array, from: Vector3, dir: Vector3) -> Array:
	var lo := INF
	var hi := -INF
	for s in slots:
		var t: float = ((s as Vector3) - from).dot(dir)
		lo = minf(lo, t)
		hi = maxf(hi, t)
	return [lo, hi, (lo + hi) * 0.5, hi - lo]

# ═════════════════════════════════════════════════════════════════════════════
# A. ТЫЛОВОЙ ЭШЕЛОН ЦЕНТРИРУЕТСЯ ПО ФРОНТУ
# ═════════════════════════════════════════════════════════════════════════════
func _a_center_rear() -> void:
	print("\n═════ A. ЦЕНТРИРОВАНИЕ ТЫЛА ═════")
	# Четыре отряда копейщиков по 20 и ОДИН отряд лучников на 20 — ровно тот
	# состав, который назвал владелец
	var all: Array = []
	for k in range(4):
		all.append_array(_make_squad("spearman", Vector3(-300.0 + float(k) * 4.0, 0.0, -300.0), 20))
	var archers: Array = _make_squad("archer", Vector3(-284.0, 0.0, -300.0), 20)
	all.append_array(archers)
	await pframes(4)

	var a := Vector3(-320.0, 0.0, -280.0)
	var b := Vector3(-280.0, 0.0, -280.0)      # линия в 40 м
	var dir := (b - a).normalized()
	var plan: Dictionary = sel._layered_formation_slots(a, b, all)
	var flat: Array = plan["flat"]
	var slots: Array = plan["slots"]
	verdict("A0 план построен на весь состав",
		flat.size() == all.size(), "мест %d на %d бойцов" % [slots.size(), all.size()])
	if flat.size() != all.size():
		_cleanup(all)
		return

	# Разложить слоты обратно по родам войск
	var spear_slots: Array = []
	var arch_slots: Array = []
	for i in range(flat.size()):
		if (flat[i] as Unit) is Archer:
			arch_slots.append(slots[i])
		else:
			spear_slots.append(slots[i])
	var sp := _spread(spear_slots, a, dir)
	var ar := _spread(arch_slots, a, dir)
	var front_w: float = sp[3]
	var rear_w: float = ar[3]

	verdict("A1 лучники не растянуты на весь фронт копейщиков",
		rear_w < front_w * 0.6,
		"фронт %.1f м, лучники %.1f м" % [front_w, rear_w])
	verdict("A2 середина лучников совпадает с серединой фронта",
		absf(float(ar[2]) - float(sp[2])) < 1.5,
		"центр фронта %.2f м, центр лучников %.2f м" % [sp[2], ar[2]])
	# Именно «по центру», а не «прижались к флангу»: край лучников заведомо
	# внутри фронта с обеих сторон
	verdict("A3 лучники целиком внутри фронта, а не с краю",
		float(ar[0]) > float(sp[0]) + 0.5 and float(ar[1]) < float(sp[1]) - 0.5,
		"фронт [%.1f..%.1f], лучники [%.1f..%.1f]" % [sp[0], sp[1], ar[0], ar[1]])
	# И они действительно ПОЗАДИ: эшелон смещается против направления взгляда
	var facing := Vector3(dir.z, 0.0, -dir.x)
	var sp_depth := 0.0
	for s in spear_slots:
		sp_depth += (s as Vector3).dot(facing)
	sp_depth /= float(spear_slots.size())
	var ar_depth := 0.0
	for s in arch_slots:
		ar_depth += (s as Vector3).dot(facing)
	ar_depth /= float(arch_slots.size())
	verdict("A4 лучники стоят ЗА спиной копейщиков",
		ar_depth < sp_depth - 1.0,
		"глубина копейщиков %.2f, лучников %.2f" % [sp_depth, ar_depth])
	# ── ПЛОТНОСТЬ СТРОЯ У ЭШЕЛОНОВ ОДИНАКОВАЯ ──────────────────────────────
	# Это и есть точная формулировка «не ниткой»: сколько метров фронта
	# приходится на бойца. Проверять «у тыла не меньше двух шеренг» нельзя —
	# при длинном растягивании и САМ ФРОНТ ложится в одну шеренгу, и такая
	# проверка требовала бы от тыла строя гуще, чем у копейщиков впереди.
	# Считается по числу бойцов, не по слотам: слоты и есть предмет проверки
	var front_dens: float = front_w / float(all.size() - archers.size())
	var rear_dens: float = rear_w / float(archers.size())
	verdict("A5 плотность строя у тыла та же, что у фронта",
		rear_dens > front_dens * 0.7 and rear_dens < front_dens * 1.4,
		"фронт %.2f м/бойца, тыл %.2f м/бойца" % [front_dens, rear_dens])
	_cleanup(all)
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
# B. ОТРЯДЫ НЕ ПЕРЕТАСОВЫВАЮТСЯ
# ═════════════════════════════════════════════════════════════════════════════
func _b_no_cross() -> void:
	print("\n═════ B. БЕЗ ПЕРЕТАСОВКИ ═════")
	# Пять отрядов ОДНОГО типа, стоящих слева направо. Порядок ВЫДЕЛЕНИЯ
	# намеренно обратный порядку на земле — именно на этом и ловится ошибка:
	# раздача участков по порядку реестра отправила бы крайний левый отряд
	# на правый край
	var squads: Array = []
	for k in range(5):
		squads.append(_make_squad("spearman", Vector3(-300.0 + float(k) * 12.0, 0.0, -200.0), 12))
	await pframes(4)
	var movable: Array = []
	for k in range(squads.size() - 1, -1, -1):
		movable.append_array(squads[k] as Array)

	var a := Vector3(-320.0, 0.0, -180.0)
	var b := Vector3(-260.0, 0.0, -180.0)
	var dir := (b - a).normalized()
	var plan: Dictionary = sel._block_formation_slots(a, b, movable)
	var flat: Array = plan["flat"]
	var slots: Array = plan["slots"]
	verdict("B0 план построен на весь состав",
		flat.size() == movable.size(), "мест %d на %d бойцов" % [slots.size(), movable.size()])
	if flat.size() != movable.size():
		_cleanup(movable)
		return

	# Для каждого отряда: где он стоял по оси линии и куда его назначили
	var was: Dictionary = {}
	var will: Dictionary = {}
	var cnt: Dictionary = {}
	for i in range(flat.size()):
		var u := flat[i] as Unit
		var sid: int = u.squad_id
		was[sid] = float(was.get(sid, 0.0)) + (u.global_position - a).dot(dir)
		will[sid] = float(will.get(sid, 0.0)) + ((slots[i] as Vector3) - a).dot(dir)
		cnt[sid] = int(cnt.get(sid, 0)) + 1
	var ids: Array = []
	for sid in was:
		was[sid] = float(was[sid]) / float(cnt[sid])
		will[sid] = float(will[sid]) / float(cnt[sid])
		ids.append(sid)
	ids.sort_custom(func(x, y): return float(was[x]) < float(was[y]))

	# ГЛАВНОЕ СВОЙСТВО: порядок отрядов по оси линии сохранён. Если он сохранён,
	# пути отрядов не пересекаются — они идут параллельно
	var inversions := 0
	for i in range(ids.size() - 1):
		if float(will[ids[i]]) >= float(will[ids[i + 1]]):
			inversions += 1
	var order_txt: Array = []
	for sid in ids:
		order_txt.append("%d: %.0f→%.0f" % [sid, was[sid], will[sid]])
	verdict("B1 отряды не поменялись местами по фронту",
		inversions == 0, "перестановок %d | %s" % [inversions, ", ".join(order_txt)])
	verdict("B2 крайний левый остался крайним левым",
		float(will[ids[0]]) < float(will[ids[ids.size() - 1]]),
		"левый встал на %.1f м, правый на %.1f м" % [will[ids[0]], will[ids[ids.size() - 1]]])
	_cleanup(movable)
	await pframes(3)

func _cleanup(units: Array) -> void:
	for u in units:
		if is_instance_valid(u):
			(u as Node).queue_free()
