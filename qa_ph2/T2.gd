extends Node

## БЛОК 2 — РЕБАЛАНС ТОЛЧКОВ (пункты 2.1 … 2.5)

var main: Node = null
var Spear: PackedScene = null
var UCfg = null

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	Spear = load("res://scenes/units/Spearman.tscn") as PackedScene
	UCfg  = load("res://scripts/unit_stats_config.gd")
	await get_tree().process_frame
	await get_tree().process_frame
	_print_config()
	await _t21_numbers()
	await _t22_phalanx_no_push()
	await _t23_incoming_halved()
	await _t24_stand_power()
	await _t25_battle()
	await _t25b_control()
	print("\n=== T2 DONE ===")
	get_tree().quit()

func _wait(frames: int) -> void:
	for _i in range(frames):
		await get_tree().physics_frame

func _pair(a_stance: String, b_stance: String, extra_push: float) -> Array:
	var a: Unit = Spear.instantiate()
	var b: Unit = Spear.instantiate()
	a.faction = Constants.FACTION_PLAYER
	b.faction = Constants.FACTION_ENEMY
	main.add_child(a)
	main.add_child(b)
	a.global_position = Vector3(120.0, 0.0, 120.0)
	b.global_position = Vector3(121.0, 0.0, 120.0)
	await get_tree().process_frame
	a.set_stance(a_stance)
	b.set_stance(b_stance)
	a.push_force += extra_push
	return [a, b]

func _print_config() -> void:
	print("\n══════ КОНФИГУРАЦИЯ ══════")
	print("  PUSH_GLOBAL_SCALE = %.2f" % UCfg.PUSH_GLOBAL_SCALE)
	print("  стойка АТАКА : push_mult=%.2f push_resist=%.2f morale_mult=%.2f"
		% [UCfg.stance_stat("attack", "push_mult", 1.0),
		   UCfg.stance_stat("attack", "push_resist", 1.0),
		   UCfg.stance_stat("attack", "morale_mult", 1.0)])
	print("  стойка ЗАЩИТА: push_mult=%.2f push_resist=%.2f morale_mult=%.2f"
		% [UCfg.stance_stat("defense", "push_mult", 1.0),
		   UCfg.stance_stat("defense", "push_resist", 1.0),
		   UCfg.stance_stat("defense", "morale_mult", 1.0)])

# ── 2.1 ─────────────────────────────────────────────────────────────────────
func _t21_numbers() -> void:
	print("\n══════ 2.1 ЧИСЛА: СРАВНЕНИЕ С ПРЕЖНЕЙ ФОРМУЛОЙ ══════")
	print("  прежняя формула шага: clamp(diff*0.15, 0.04, 0.4)")
	print("  текущая:              то же × PUSH_GLOBAL_SCALE(0.35) × push_resist(цели)")
	print("   доп.push |  diff  | старый шаг | факт. сдвиг | доля | шаг толкающего")
	var all_ok := true
	for extra in [0.2, 1.0, 2.0, 3.0, 10.0]:
		var e: float = extra
		var p: Array = await _pair("attack", "attack", e)
		var a: Unit = p[0]
		var b: Unit = p[1]
		var diff: float = float(a.call("_push_power")) - float(b.call("_stand_power"))
		var old_step: float = clampf(diff * 0.15, 0.04, 0.4)
		var bx0: float = b.global_position.x
		var ax0: float = a.global_position.x
		a._apply_push(b, Vector3(1, 0, 0))
		var db: float = b.global_position.x - bx0
		var da: float = a.global_position.x - ax0
		var ratio: float = db / maxf(old_step, 1e-9)
		if absf(ratio - 0.35) > 0.002:
			all_ok = false
		print("    %+6.2f  | %6.3f |  %.5f   |   %.5f   | %.3f |    %.5f"
			% [e, diff, old_step, db, ratio, da])
		a.queue_free(); b.queue_free()
		await get_tree().process_frame
	print("  ИТОГ 2.1: %s — падение силы толчка ровно до 35%% на всём диапазоне"
		% ["PASS" if all_ok else "FAIL"])

# ── 2.2 ─────────────────────────────────────────────────────────────────────
func _t22_phalanx_no_push() -> void:
	print("\n══════ 2.2 ФАЛАНГА САМА НЕ ТОЛКАЕТ ══════")
	for extra in [0.0, 10.0, 100.0]:
		var e: float = extra
		var p: Array = await _pair("defense", "attack", e)
		var a: Unit = p[0]
		var b: Unit = p[1]
		var bx0: float = b.global_position.x
		var ax0: float = a.global_position.x
		a._apply_push(b, Vector3(1, 0, 0))
		print("    толкающий в ЗАЩИТЕ, доп.push=%+.1f: _push_power=%.2f → цель сдвинулась на %.5f м, сам подался на %.5f м"
			% [e, float(a.call("_push_power")),
			   b.global_position.x - bx0, a.global_position.x - ax0])
		a.queue_free(); b.queue_free()
		await get_tree().process_frame
	print("  ИТОГ 2.2: PASS если во всех строках обе величины = 0.00000")

# ── 2.3 ─────────────────────────────────────────────────────────────────────
func _t23_incoming_halved() -> void:
	print("\n══════ 2.3 ВХОДЯЩИЙ ТОЛЧОК ПО ФАЛАНГЕ СРЕЗАН ВДВОЕ ══════")
	print("  (а) агрессор с запасом (шаг упирается в clamp 0.4) — изолирован ровно push_resist")
	var res: Array[float] = []
	for st in ["attack", "defense"]:
		var s: String = st
		var p: Array = await _pair("attack", s, 10.0)
		var a: Unit = p[0]
		var b: Unit = p[1]
		var diff: float = float(a.call("_push_power")) - float(b.call("_stand_power"))
		var bx0: float = b.global_position.x
		a._apply_push(b, Vector3(1, 0, 0))
		var db: float = b.global_position.x - bx0
		res.append(db)
		print("      цель в стойке %-8s: упор=%.2f diff=%.2f (clamp сработал) → сдвиг %.5f м"
			% [s, float(b.call("_stand_power")), diff, db])
		a.queue_free(); b.queue_free()
		await get_tree().process_frame
	var k: float = res[0] / maxf(res[1], 1e-9)
	print("      отношение атака/защита = %.4f (ожидание ровно 2.0000) → %s"
		% [k, "PASS" if absf(k - 2.0) < 0.001 else "FAIL"])
	print("  (б) реальный бой (без clamp): к push_resist добавляется +30%% морали фаланги")
	var res2: Array[float] = []
	for st in ["attack", "defense"]:
		var s2: String = st
		var p2: Array = await _pair("attack", s2, 2.0)
		var a2: Unit = p2[0]
		var b2: Unit = p2[1]
		var diff2: float = float(a2.call("_push_power")) - float(b2.call("_stand_power"))
		var bx2: float = b2.global_position.x
		a2._apply_push(b2, Vector3(1, 0, 0))
		var db2: float = b2.global_position.x - bx2
		res2.append(db2)
		print("      цель в стойке %-8s: упор=%.2f diff=%.2f → сдвиг %.5f м"
			% [s2, float(b2.call("_stand_power")), diff2, db2])
		a2.queue_free(); b2.queue_free()
		await get_tree().process_frame
	print("      отношение атака/защита = %.4f (>2 за счёт морали)"
		% [res2[0] / maxf(res2[1], 1e-9)])

# ── 2.4 ─────────────────────────────────────────────────────────────────────
func _t24_stand_power() -> void:
	print("\n══════ 2.4 УПОР ФАЛАНГИ ══════")
	var p: Array = await _pair("attack", "defense", 0.0)
	var a: Unit = p[0]
	var b: Unit = p[1]
	var sa: float = float(a.call("_stand_power"))
	var sb: float = float(b.call("_stand_power"))
	var pa: float = float(a.call("_push_power"))
	print("  копейщик в АТАКЕ : push_force=%.1f мораль=%.0f → _stand_power=%.2f, _push_power=%.2f"
		% [a.push_force, float(a.call("_effective_morale")), sa, pa])
	print("  копейщик в ЗАЩИТЕ: push_force=%.1f мораль=%.0f (×1.30) → _stand_power=%.2f"
		% [b.push_force, float(b.call("_effective_morale")), sb])
	var diff: float = pa - sb
	var bx0: float = b.global_position.x
	a._apply_push(b, Vector3(1, 0, 0))
	var db: float = b.global_position.x - bx0
	print("  diff равного копейщика против фаланги = %.2f (нужно ≤ 0) → фактический сдвиг %.5f м"
		% [diff, db])
	print("  ИТОГ 2.4: %s (упор в защите на %+.1f%% выше, равный боец фалангу не двигает)"
		% ["PASS" if diff <= 0.0 and absf(db) < 1e-6 else "FAIL", (sb / sa - 1.0) * 100.0])
	a.queue_free(); b.queue_free()
	await get_tree().process_frame

# ── 2.5 ─────────────────────────────────────────────────────────────────────
const N_SIDE := 40
const BATTLE_SECONDS := 30.0

func _com(arr: Array) -> Vector3:
	var s := Vector3.ZERO
	var n := 0
	for u in arr:
		if is_instance_valid(u) and not u.is_dead():
			s += u.global_position
			n += 1
	if n == 0:
		return Vector3.ZERO
	return s / float(n)

func _t25_battle() -> void:
	print("\n══════ 2.5 БОЕВОЙ СЦЕНАРИЙ: 40 В АТАКЕ × 40 В ЗАЩИТЕ ══════")
	var att: Array = []
	var def: Array = []
	# Оборона стоит стеной на x = 0, атакующие приходят с -X
	for i in range(N_SIDE):
		var d: Unit = Spear.instantiate()
		d.faction = Constants.FACTION_ENEMY
		main.add_child(d)
		d.global_position = Vector3(float(i / 10) * 0.7, 0.0, -3.5 + float(i % 10) * 0.7)
		d.max_health = 1.0e7
		d.current_health = 1.0e7
		def.append(d)
		var a: Unit = Spear.instantiate()
		a.faction = Constants.FACTION_PLAYER
		main.add_child(a)
		a.global_position = Vector3(-4.0 - float(i / 10) * 0.7, 0.0, -3.5 + float(i % 10) * 0.7)
		a.max_health = 1.0e7
		a.current_health = 1.0e7
		att.append(a)
	await get_tree().process_frame
	for d in def:
		d.set_stance("defense")
	for a in att:
		a.set_stance("attack")
		a.command_move(Vector3(1.5, 0.0, a.global_position.z))
	var com_d0 := _com(def)
	var com_a0 := _com(att)
	print("  здоровье поднято до 1e7: никто не гибнет, меряем ЧИСТО перемещение от толчков")
	print("  старт: центр масс обороны x=%+.3f, атаки x=%+.3f" % [com_d0.x, com_a0.x])

	var prev: Array[Vector3] = []
	for u in att + def:
		prev.append((u as Node3D).global_position)
	var all_u: Array = att + def
	var max_step := 0.0
	var max_step_frame := 0
	var frames: int = int(BATTLE_SECONDS * 60.0)
	var hist: Dictionary = {}
	for f in range(frames):
		await get_tree().physics_frame
		for i in range(all_u.size()):
			var u: Unit = all_u[i]
			if not is_instance_valid(u):
				continue
			var p: Vector3 = u.global_position
			var d: float = Vector2(p.x - prev[i].x, p.z - prev[i].z).length()
			prev[i] = p
			if d > max_step:
				max_step = d
				max_step_frame = f
			var bucket: int = int(d / 0.05)
			hist[bucket] = int(hist.get(bucket, 0)) + 1
		if f % 600 == 0:
			print("    %5.1f с: центр обороны x=%+.3f (сдвиг %+.3f), центр атаки x=%+.3f (сдвиг %+.3f)"
				% [float(f) / 60.0, _com(def).x, _com(def).x - com_d0.x,
				   _com(att).x, _com(att).x - com_a0.x])
	var com_d1 := _com(def)
	var com_a1 := _com(att)
	print("  ФИНАЛ за %.0f с боя:" % BATTLE_SECONDS)
	print("    оборона: центр масс %+.3f → %+.3f, СДВИГ %+.3f м (боковой %+.3f)"
		% [com_d0.x, com_d1.x, com_d1.x - com_d0.x, com_d1.z - com_d0.z])
	print("    атака  : центр масс %+.3f → %+.3f, СДВИГ %+.3f м (боковой %+.3f)"
		% [com_a0.x, com_a1.x, com_a1.x - com_a0.x, com_a1.z - com_a0.z])
	print("    максимальное перемещение ОДНОГО бойца за один физ. кадр: %.4f м (кадр %d, %.1f с)"
		% [max_step, max_step_frame, float(max_step_frame) / 60.0])
	# Расталкивания союзников больше нет вовсе, поэтому сравнивать шаг остаётся
	# только с толчком в ближнем бою и с обычным ходом
	print("    для сравнения: шаг толчка ≤ %.4f м, ход бегом за кадр = %.4f м"
		% [0.4 * 0.35, 3.5 / 60.0])
	var keys: Array = hist.keys()
	keys.sort()
	var line := ""
	for k in keys:
		line += "  [%.2f-%.2f):%d" % [float(k) * 0.05, float(k) * 0.05 + 0.05, int(hist[k])]
	print("    распределение шага за кадр по всем бойцам:%s" % line)
	for u in att + def:
		if is_instance_valid(u):
			u.queue_free()
	await get_tree().process_frame

## КОНТРОЛЬ к 2.5: в равном бою толчков нет вовсе (diff<0), поэтому отдельно
## проверяем, что механика вообще работает — даём атакующим +3 к push_force
func _t25b_control() -> void:
	print("\n══════ 2.5-контроль: АТАКУЮЩИЕ С ПЕРЕВЕСОМ push_force +3 ══════")
	var att: Array = []
	var def: Array = []
	for i in range(N_SIDE):
		var d: Unit = Spear.instantiate()
		d.faction = Constants.FACTION_ENEMY
		main.add_child(d)
		d.global_position = Vector3(200.0 + float(i / 10) * 0.7, 0.0, 200.0 + float(i % 10) * 0.7)
		d.max_health = 1.0e7
		d.current_health = 1.0e7
		def.append(d)
		var a: Unit = Spear.instantiate()
		a.faction = Constants.FACTION_PLAYER
		main.add_child(a)
		a.global_position = Vector3(196.0 - float(i / 10) * 0.7, 0.0, 200.0 + float(i % 10) * 0.7)
		a.max_health = 1.0e7
		a.current_health = 1.0e7
		a.push_force += 3.0
		att.append(a)
	await get_tree().process_frame
	for d in def:
		d.set_stance("defense")
	for a in att:
		a.command_move(Vector3(201.5, 0.0, a.global_position.z))
	var c0 := _com(def)
	var prev: Array[Vector3] = []
	var all_u: Array = att + def
	for u in all_u:
		prev.append((u as Node3D).global_position)
	var max_step := 0.0
	for f in range(int(BATTLE_SECONDS * 60.0)):
		await get_tree().physics_frame
		for i in range(all_u.size()):
			var u: Unit = all_u[i]
			var p: Vector3 = u.global_position
			var dd: float = Vector2(p.x - prev[i].x, p.z - prev[i].z).length()
			prev[i] = p
			max_step = maxf(max_step, dd)
		if f % 600 == 0:
			print("    %5.1f с: центр обороны x=%+.3f (сдвиг %+.3f м)"
				% [float(f) / 60.0, _com(def).x, _com(def).x - c0.x])
	var c1 := _com(def)
	print("  за %.0f с оборону продавили на %+.3f м (%.4f м/с) — медленно и слитно"
		% [BATTLE_SECONDS, c1.x - c0.x, (c1.x - c0.x) / BATTLE_SECONDS])
	print("  максимальное перемещение одного бойца за физ. кадр: %.4f м" % max_step)
	for u in all_u:
		if is_instance_valid(u):
			u.queue_free()
	await get_tree().process_frame
