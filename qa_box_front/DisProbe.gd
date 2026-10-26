extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ПРИОРИТЕТ ПРИКАЗА ИГРОКА НАД БОЕМ (Unit._disengaging)
## ═══════════════════════════════════════════════════════════════════════════
##   A ЛУЧНИКИ   — приказ отойти посреди боя не даёт стрелкам развернуться
##                 обратно и продолжить стрельбу
##   B КОПЕЙЩИКИ — то же самое в ближнем бою (никаких «двух шагов назад»)
##   D ОКРУЖЕНИЕ — приказ игрока выводит бойца из свалки ТЕЛОМ: с первого
##                 клика, а не со второго
##   C ФЛАГ СНИМАЕТСЯ — после прихода в точку отряд снова ловит НОВОГО врага
##                 на пути как обычно (march-перехват не сломан навсегда)
##
## Запуск: godot --headless --path . res://qa_disengage/Test.tscn

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

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

func _new(kind: String, fac: int, at: Vector3) -> Unit:
	var u: Unit
	match kind:
		"spearman": u = Spearman.new()
		"archer":   u = Archer.new()
		"warrior":  u = Warrior.new()
		_:          u = Worker.new()
	u.faction = fac
	main.world_add(u)
	u.global_position = at
	return u

func _squad(kind: String, fac: int, center: Vector3, count: int) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var men: Array = []
	for i in range(count):
		var p := center + Vector3(float(i % 5) * 0.6 - 1.2, 0.0, float(i / 5) * 0.6)
		var u := _new(kind, fac, p)
		u.post_pos = p
		u.set("_post_valid", true)
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return men

func _alive(arr: Array) -> Array:
	var out: Array = []
	for u in arr:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			out.append(u)
	return out

## Срок на дорогу по живой скорости бойцов, а не по потолку с потолка
## (см. CLAUDE.md — «Config is the source of truth»)
func travel_budget_ms(men: Array, to: Vector3) -> int:
	var far := 0.0
	var slow := 1e9
	for m in men:
		if not is_instance_valid(m):
			continue
		var u: Unit = m
		var p: Vector3 = u.global_position
		far = maxf(far, Vector2(p.x - to.x, p.z - to.z).length())
		slow = minf(slow, maxf(u.move_speed, 0.1))
	return int(far / slow * 3000.0) + 2000

func _run() -> void:
	seed(1234)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(5)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	for n in get_tree().get_nodes_in_group("all_units"):
		(n as Node).queue_free()
	GameManager.world_bounds_enabled = false
	await frames(3)
	var start := Vector3(60, 0, -500)
	var mine := _squad("spearman", Constants.FACTION_PLAYER, start, 6)
	var foes := _squad("spearman", Constants.FACTION_ENEMY, start + Vector3(0, 0, 1.2), 6)
	for i in range(mine.size()):
		(mine[i] as Unit).command_attack(foes[i % foes.size()], true)
	await frames(3)
	var away := start + Vector3(0, 0, -60)
	for u in mine:
		(u as Unit).command_move(away)
	for k in range(12):
		for _i in range(60):
			await get_tree().physics_frame
		var line := "t=%ds  НАШИ:" % (k + 1)
		for u in mine:
			if not is_instance_valid(u):
				line += " [нет]"; continue
			var un: Unit = u
			var p := un.global_position
			line += " [%s d=%.1f st=%d hp=%.0f]" % ["Х" if un.is_dead() else "ж", Vector2(p.x - start.x, p.z - start.z).length(), un.state, un.current_health]
		line += "  ИХ:"
		for u in foes:
			if not is_instance_valid(u):
				continue
			var fu: Unit = u
			var q := fu.global_position
			line += " [d=%.1f st=%d box=%s]" % [Vector2(q.x - start.x, q.z - start.z).length(), fu.state, "да" if fu._box_goal.x != INF else "нет"]
		print(line)
	get_tree().quit()
