extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: МОНАХ-ЦЕЛИТЕЛЬ (09.09.2026)
## ═══════════════════════════════════════════════════════════════════════════
##   A НАЙМ — одиночный юнит из замка, не больше MONK_LIMIT (живые + заказ),
##     аватарка из Human avatar, ленты ходьбы и лечения подключены.
##   B ЛЕЧЕНИЕ — самый раненый свой в радиусе получает запас со скоростью
##     «один полный боец за MONK_HEAL_SEC_PER_MAN секунд»; целых не трогает,
##     чужих не лечит, павших не поднимает; лента Heal играет.
##
## Числа — из конфига (правило 10), ожидание физкадрами (правило 11).
## Запуск: godot --headless --path . res://qa_monk/Test.tscn

const _UCfg := preload("res://scripts/unit_stats_config.gd")

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	var t := get_tree().create_timer(180.0)
	t.timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 180 с")
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
	print("\n═════ ИТОГ qa_monk: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _spawn(kind: String, faction: int, at: Vector3) -> Unit:
	var u: Unit = (Building.PRELOAD_SCENES[kind] as PackedScene).instantiate()
	u.faction = faction
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	var sid: int = GameManager.new_squad(faction, kind)
	GameManager.add_to_squad(sid, u)
	return u

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
	await pframes(4)
	await _check_hire()
	await _check_heal()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
func _check_hire() -> void:
	print("\n═════ A. НАЙМ ═════")
	var c: Dictionary = _UCfg.train_cfg("castle", "monk")
	verdict("A1 монах заказывается в замке одиночным юнитом", not c.is_empty()
		and int(c.get("squad", 0)) == 1 and _UCfg.squad_size("monk") == 1,
		"squad=%d" % int(c.get("squad", 0)))
	var icon: String = String(main.hud.UNIT_ICONS.get("monk", ""))
	verdict("A2 аватарка монаха — из Human avatar", icon.find("Human avatar") >= 0
		and ResourceLoader.exists(icon), icon)
	var keep := Castle.new()
	keep.faction = Constants.FACTION_PLAYER
	main.world_add(keep)
	keep.global_position = Vector3(-60.0, GameManager.get_terrain_height(-60.0, -40.0), -40.0)
	await pframes(3)
	ResourceManager.add_resource(Constants.FACTION_PLAYER, Constants.RESOURCE_WOOD, 5000.0)
	ResourceManager.add_resource(Constants.FACTION_PLAYER, Constants.RESOURCE_GOLD, 5000.0)
	# ── ПОТОЛОК ЧИТАЕТСЯ ИЗ КОНФИГА, А НЕ СТОИТ ЕДИНИЦЕЙ (правило 10) ──────
	# Спринт 13 поднял MONK_LIMIT с одного до трёх. Прежняя проверка требовала
	# отказа НА ВТОРОМ заказе — то есть утверждала само число, а не правило.
	# Правило же одно: заказов принимается ровно потолок, следующий отбивается
	var taken := 0
	for _i in range(_UCfg.MONK_LIMIT):
		if keep.train_from_config("monk"):
			taken += 1
	var over: bool = keep.train_from_config("monk")
	verdict("A3 монахов принимается ровно MONK_LIMIT (%d), следующий заказ отклонён" % _UCfg.MONK_LIMIT,
		taken == _UCfg.MONK_LIMIT and not over
			and GameManager.monks_used(Constants.FACTION_PLAYER) == _UCfg.MONK_LIMIT,
		"принято %d, лишний=%s, занято %d" % [taken, str(over),
			GameManager.monks_used(Constants.FACTION_PLAYER)])
	# Доводим заказ до выхода
	var guard := 0
	while guard < 600 and (not keep.production_queue.is_empty() or not keep._pending_spawns.is_empty()):
		keep._production_timer = 99999.0
		keep._row_gate = 0.0
		await get_tree().physics_frame
		guard += 1
	var monk: Unit = null
	var monks_out := 0
	for u in get_tree().get_nodes_in_group("player_units"):
		if u is Monk:
			monk = u
			monks_out += 1
	verdict("A4 из замка вышли все заказанные монахи, и их ровно потолок",
		monk != null and monks_out == _UCfg.MONK_LIMIT
			and GameManager.monks_used(Constants.FACTION_PLAYER) == _UCfg.MONK_LIMIT,
		"вышло %d, занято %d при потолке %d" % [monks_out,
			GameManager.monks_used(Constants.FACTION_PLAYER), _UCfg.MONK_LIMIT])
	if monk != null:
		# Таблица лент снимается с узла лениво (Unit._look_bind) — снимаем явно
		monk.sheet_frame()
		var has := monk._has_anim("idle") and monk._has_anim("walk") and monk._has_anim("heal")
		verdict("A5 ленты покоя, ходьбы и лечения подключены", has)
		verdict("A6 живые монахи занимают лимит: новый заказ отклонён",
			not keep.train_from_config("monk"),
			"занято %d из %d" % [GameManager.monks_used(Constants.FACTION_PLAYER),
				_UCfg.MONK_LIMIT])
		monk.take_damage(1e9)
		await pframes(2)
		verdict("A7 после гибели лимит свободен", keep.train_from_config("monk"))
		keep.cancel_order("monk")
	keep.queue_free()
	await pframes(2)

# ═════════════════════════════════════════════════════════════════════════════
func _check_heal() -> void:
	print("\n═════ B. ЛЕЧЕНИЕ ═════")
	var at := Vector3(-60.0, 0.0, 0.0)
	var monk: Unit = _spawn("monk", Constants.FACTION_PLAYER, at)
	# СПРИНТ 15: монах лечит только в упор (MONK_CAST_RANGE), к дальнему сначала
	# идёт — раненый ставится внутри дистанции каста, иначе замер темпа
	# считает и дорогу (54 против 72 при трёх метрах ровно на пороге)
	var wounded: Unit = _spawn("spearman", Constants.FACTION_PLAYER,
		at + Vector3(_UCfg.MONK_CAST_RANGE * 0.6, 0.0, 0.0))
	var whole: Unit = _spawn("spearman", Constants.FACTION_PLAYER, at + Vector3(-3.0, 0.0, 0.0))
	var foe: Unit = _spawn("spearman", Constants.FACTION_ENEMY, at + Vector3(0.0, 0.0, 4.0))
	var far_w: Unit = _spawn("spearman", Constants.FACTION_PLAYER, at + Vector3(_UCfg.MONK_HEAL_RADIUS + 10.0, 0.0, 0.0))
	await pframes(2)
	# Раним без боя: прямо в поле запаса
	wounded.current_health = wounded.max_health * 0.2
	wounded._soa_push_stats()
	foe.current_health = foe.max_health * 0.2
	foe._soa_push_stats()
	far_w.current_health = far_w.max_health * 0.2
	far_w._soa_push_stats()
	# Никто не дерётся: враг и свои в покое, монах стоит
	foe.set_process(false)
	# Тик бойца идёт из GameManager, set_process его не глушит: чужой копейщик
	# бил раненого, и «вылечено» зависело от жребия боя (спринт 18: сдвиг
	# общего RNG дал 63 → 50 HP при ожидании 72). Чужой здесь — цель проверки
	# «не лечат», а не боец: замораживаем тик
	foe.set_tick(false)
	var hp0: float = wounded.current_health
	var t_sec: float = 4.0
	await pframes(int(t_sec * 60.0))
	var gained: float = wounded.current_health - hp0
	var want: float = wounded.max_health * t_sec / _UCfg.MONK_HEAL_SEC_PER_MAN
	print("  за %.0f с вылечено %.1f HP (ожидалось ~%.1f: %.0f HP за %.0f с)" % [
		t_sec, gained, want, wounded.max_health, _UCfg.MONK_HEAL_SEC_PER_MAN])
	verdict("B1 темп лечения: полный боец за %.0f с (±25 %%)" % _UCfg.MONK_HEAL_SEC_PER_MAN,
		gained > want * 0.75 and gained < want * 1.25, "вылечено %.1f при ожидании %.1f" % [gained, want])
	verdict("B2 целый сосед не тронут, чужой не лечится, дальний вне радиуса не лечится",
		is_equal_approx(whole.current_health, whole.max_health)
			and (not is_instance_valid(foe) or foe.is_dead()
				or foe.current_health <= foe.max_health * 0.2 + 0.01)
			and far_w.current_health <= far_w.max_health * 0.2 + 0.01)
	verdict("B3 лечится самый раненый (цель такта — раненый копейщик)", monk.heal_target == wounded)
	verdict("B4 во время лечения играет лента Heal", String(monk._anim_name) == "heal",
		"лента «%s»" % String(monk._anim_name))
	# Павшего не поднимает
	wounded.take_damage(1e9)
	await pframes(int(1.5 * 60.0))
	verdict("B5 павших не воскрешает", not is_instance_valid(wounded) or wounded.is_dead())
	# Долечивает до полного и останавливается
	whole.current_health = whole.max_health * 0.9
	whole._soa_push_stats()
	await pframes(int(2.0 * 60.0))
	verdict("B6 лечение не превышает запас", whole.current_health <= whole.max_health + 0.001
		and whole.current_health > whole.max_health * 0.9)
	for u in [monk, whole, foe, far_w]:
		if is_instance_valid(u):
			(u as Unit).take_damage(1e9)
	await pframes(2)
