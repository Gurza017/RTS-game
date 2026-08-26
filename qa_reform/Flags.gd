extends Node
## ═══════════════════════════════════════════════════════════════════════════
## ЗОНД: ОТКУДА БЕРУТСЯ «ЛИШНИЕ» ЗНАМЁНА ОРДЫ
## ═══════════════════════════════════════════════════════════════════════════
## Жалоба владельца по скриншоту: у ветеранских отрядов орды при движении, бое
## и смене состояния на карте плодятся флажки и остаются висеть в пустом поле.
##
## Зонд проверяет ДВЕ гипотезы разом, потому что на экране они выглядят
## одинаково («флаг стоит один в траве»):
##   1. УТЕЧКА УЗЛОВ — знамён в дереве больше, чем отрядов, которые их держат;
##   2. ЗНАМЯ БЕЗ ХОЗЯИНА НА ЭКРАНЕ — узел один и он законный, но его
##      знаменосец в этот момент НЕ РИСУЕТСЯ (туман, LOD, сон), а знамя
##      рисуется. Тогда игрок и видит флаг в пустой траве.
##
## Партия поднимается настоящая: деревня, орда из Main, живой GoblinAI, туман
## ВКЛЮЧЁН — без него вторая гипотеза непроверяема вовсе.
##
## Запуск: godot --headless --path . res://qa_reform/Flags.tscn

var main = null
var _prev_orphans: int = 0
var _lonely_seen: int = 0

func _ready() -> void:
	call_deferred("_run")

func pf(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

## Все узлы знамён в дереве
func _banner_nodes() -> Array:
	var scr = load("res://scripts/SquadBanner.gd")
	var out: Array = []
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for ch in node.get_children():
			stack.append(ch)
		if node is MeshInstance3D and node.get_script() == scr:
			out.append(node)
	return out

## Узлы, на которые ссылается хоть один отряд
func _owned() -> Dictionary:
	var d: Dictionary = {}
	for key in GameManager.squads.keys():
		var b = (GameManager.squads[key] as Dictionary).get("banner", null)
		if b != null and is_instance_valid(b):
			d[b.get_instance_id()] = int(key)
	return d

## Знамя видно, а знаменосца — нет. Именно это и выглядит как «флаг в поле»
func _lonely() -> Array:
	var out: Array = []
	for key in GameManager.squads.keys():
		var sq: Dictionary = GameManager.squads[key]
		var b = sq.get("banner", null)
		if b == null or not is_instance_valid(b) or not (b as MeshInstance3D).visible:
			continue
		var br = GameManager.squad_bearer(int(key))
		if br == null:
			out.append([int(key), "знаменосца нет вовсе", (b as Node3D).global_position])
			continue
		var u := br as Unit
		if not u._far_registered:
			out.append([int(key), "знаменосец снят с отрисовки", (b as Node3D).global_position])
	return out

func _report(tag: String) -> void:
	var nodes: Array = _banner_nodes()
	var owned: Dictionary = _owned()
	var orphans: Array = []
	for n in nodes:
		if not owned.has((n as Node).get_instance_id()):
			orphans.append(n)
	var vets := 0
	var shown := 0
	for key in GameManager.squads.keys():
		if int((GameManager.squads[key] as Dictionary).get("level", 0)) > 0:
			vets += 1
		var bb = (GameManager.squads[key] as Dictionary).get("banner", null)
		if bb != null and is_instance_valid(bb) and (bb as MeshInstance3D).visible:
			shown += 1
	var lonely: Array = _lonely()
	print("  %-22s узлов %3d | у отрядов %3d | бесхозных %3d | видно %3d | ЗНАМЯ БЕЗ ХОЗЯИНА %3d | ветеранских %3d"
		% [tag, nodes.size(), owned.size(), orphans.size(), shown, lonely.size(), vets])
	for rec in lonely:
		var p: Vector3 = (rec as Array)[2]
		print("      отряд %d: %s — знамя в (%.0f, %.0f)"
			% [int((rec as Array)[0]), String((rec as Array)[1]), p.x, p.z])
	_lonely_seen = maxi(_lonely_seen, lonely.size())
	_prev_orphans = orphans.size()

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pf(10)
	GameManager.world_bounds_enabled = false
	print("\n═════ ЗОНД: ЗНАМЁНА ОРДЫ (туман включён) ═════")
	print("  туман: %s" % str(GameManager.fog != null and GameManager.fog.enabled))
	_report("старт партии")

	# Орда просыпается: в партии это 30-я минута, ждать её незачем
	if main.goblin_ai != null:
		main.goblin_ai._wake_horde()
	await pf(60)
	_report("орда проснулась")

	# Людской отряд — в деревню. Орда обязана драться, отходить в хижины,
	# лечиться, пополняться и выходить снова
	var centre: Vector3 = main.goblin_village_center()
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "warrior")
	for i in range(60):
		var u: Unit = load("res://scenes/units/Warrior.tscn").instantiate()
		u.faction = Constants.FACTION_PLAYER
		main.world_add(u)
		var px: float = centre.x + 26.0 + float(i % 10) * 0.9
		var pz: float = centre.z + float(i / 10) * 0.9
		u.global_position = Vector3(px, GameManager.get_terrain_height(px, pz), pz)
		u.sync_row()
		u.max_health *= 40.0
		u.current_health = u.max_health
		u.attack_damage *= 6.0
		GameManager.add_to_squad(sid, u)
	await pf(20)
	for m in GameManager.squad_members(sid):
		(m as Unit).command_move(centre, false)
	_report("людской отряд пошёл")

	for step in range(24):
		await pf(120)
		_report("такт %d" % (step + 1))
		var men: Array = GameManager.squad_members(sid)
		if men.is_empty():
			continue
		# Отряд гоняется туда-сюда: это и есть «смена состояния», после которой
		# владелец видит флажки. Заодно свет то приходит в деревню, то уходит
		var to: Vector3 = centre if (step % 2 == 0) else centre + Vector3(70.0, 0.0, 70.0)
		for m2 in men:
			(m2 as Unit).command_move(to, false)

	print("\n  ХУДШЕЕ ЗА ПРОГОН: знамён без видимого хозяина — %d" % _lonely_seen)
	print("\n=== FLAGS PROBE DONE ===")
	get_tree().quit(0)
