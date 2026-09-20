extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_roof_visual_fix — НОГИ НА КРЫШЕ И ПОРЯДОК РЯДОВ (15.09.2026)
## ═══════════════════════════════════════════════════════════════════════════
## Бараки (30), крепость (60: настил + фланги), башня (10) с гарнизоном:
##   • ноги переднего ряда стоят НИЖЕ прежних долей высоты рисунка
##     (заказ: «опустить, чтобы стояли на площадках, а не летали над зубцами»)
##     и внутри нарисованного здания по ширине;
##   • задний ряд ДАЛЬШЕ от камеры, чем передний (глубина по камере партии
##     растёт с номером ряда) и выше на экране — передний перекрывает задний;
##   • спрайты все на местах (число видимых = число укрытых).
## Картинка для глаза — Shot.tscn (оконный). Числа — из конфига (правило 10).
## Запуск: godot --headless --path . res://qa_roof_visual_fix/Test.tscn

const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _BB := preload("res://scripts/BillboardUtil.gd")
const _TowerS := preload("res://scripts/Tower.gd")
const F := Constants.FACTION_PLAYER

## Доли высоты рисунка ДО правки 15.09.2026 — стенд стережёт «не выше прежнего»
const OLD_FOOT := {"tower": 0.60, "barracks": 0.56, "castle": 0.66, "flank": 0.78}

var main = null
var _pass := 0
var _fail := 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(240.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 240 с")
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
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО", ("  — " + d) if d != "" else ""])

func _finish() -> void:
	print("\n═════ ИТОГ qa_roof_visual_fix: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _spawn(kind: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[kind].instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _squad(kind: String, fac: int, at: Vector3, n: int, cols: int = 6) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var men: Array = []
	for i in range(n):
		var u: Unit = _spawn(kind, fac, Vector3(at.x - float(i / cols) * 0.9, 0.0,
			at.z + float(i % cols) * 0.7 - float(cols - 1) * 0.35))
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return [sid, men]

func _place(b: Building, at: Vector3) -> void:
	b.faction = F
	main.world_add(b)
	b.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)

func _inside(arr: Array) -> int:
	var n := 0
	for u in arr:
		if is_instance_valid(u) and (u as Unit).garrisoned:
			n += 1
	return n

func _sprite_h(b: Building) -> float:
	var spr := b.get_node_or_null("BuildingSprite") as MeshInstance3D
	if spr != null and spr.mesh is QuadMesh:
		return (spr.mesh as QuadMesh).size.y * _BB.V_STRETCH
	return b.build_size.y * 2.0

func _half_w(b: Building) -> float:
	return b._draw_half_w if b._draw_half_w > 0.0 else b.build_size.x * 0.5

## Глубина точки по камере партии: чем больше, тем дальше от объектива
func _depth(cam: Camera3D, p: Vector3) -> float:
	return (p - cam.global_position).dot(-cam.global_transform.basis.z)

## Проверка одного здания: ряды row_a (передний) и row_b (следующий) по
## индексам мест; foot_key — ключ в ROOF_FOOT_FRAC / OLD_FOOT
func _check_building(tag: String, b: Building, roof, cam: Camera3D, idx_front: int,
		idx_back: int, foot_frac: float, old_key: String, cap: int, idx_foot: int = 0) -> void:
	var h: float = _sprite_h(b)
	var hw: float = _half_w(b)
	var pf: Vector3 = roof.slot_local(idx_front)
	var pb: Vector3 = roof.slot_local(idx_back)
	var p0: Vector3 = roof.slot_local(idx_foot)
	verdict("%s ноги площадки опущены: %.2f высоты рисунка ≤ прежних %.2f и в пределах ската [0.30; 0.62]" % [
		tag, p0.y / h, float(OLD_FOOT[old_key])],
		p0.y / h <= float(OLD_FOOT[old_key]) - 0.04 and p0.y / h >= 0.30 and p0.y / h <= 0.62
		and is_equal_approx(p0.y, h * foot_frac))
	verdict("%s передний ряд внутри рисунка по ширине" % tag,
		absf(pf.x - b._draw_cx) <= hw * 0.95, "x %.2f при полуширине %.2f" % [pf.x - b._draw_cx, hw])
	var wf: Vector3 = b.to_global(pf)
	var wb: Vector3 = b.to_global(pb)
	var df: float = _depth(cam, wf)
	var db: float = _depth(cam, wb)
	var sf: Vector2 = cam.unproject_position(wf)
	var sb: Vector2 = cam.unproject_position(wb)
	verdict("%s задний ряд дальше от камеры (глубина %.2f > %.2f) и выше на экране — передний перекрывает задний" % [
		tag, db, df], db > df + 0.05 and sb.y < sf.y,
		"экран y: передний %.0f, задний %.0f" % [sf.y, sb.y])
	verdict("%s спрайтов на крыше столько, сколько укрытых (потолок %d)" % [tag, cap],
		int(roof.shown()) == mini(int(roof.men()), cap), "показано %d, людей %d" % [int(roof.shown()), int(roof.men())])

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	if main.get("gnoll_ai") != null:
		main.gnoll_ai.set_process(false)
	GameManager.world_bounds_enabled = false
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	for n in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(n) and n is Unit:
			(n as Unit).take_damage(1.0e12)
	await pframes(6)
	var base := Vector3(0.0, 0.0, -420.0)
	var bar: Building = Barracks.new()
	_place(bar, base + Vector3(-16.0, 0.0, 0.0))
	var keep: Castle = Castle.new()
	_place(keep, base + Vector3(2.0, 0.0, 0.0))
	var tower: Building = _TowerS.new()
	_place(tower, base + Vector3(18.0, 0.0, 0.0))
	await pframes(6)
	var s1: Array = _squad("archer", F, base + Vector3(-16.0, 0.0, 12.0), 30)
	var s2: Array = _squad("archer", F, base + Vector3(0.0, 0.0, 12.0), 30)
	var s3: Array = _squad("archer", F, base + Vector3(6.0, 0.0, 12.0), 30)
	var s4: Array = _squad("archer", F, base + Vector3(18.0, 0.0, 12.0), 30)
	await pframes(30)
	bar.request_garrison(int(s1[0]))
	keep.request_garrison(int(s2[0]))
	keep.request_garrison(int(s3[0]))
	tower.request_garrison(int(s4[0]))
	var all: Array = s1[1] + s2[1] + s3[1] + s4[1]
	var w := 0
	while w < 60 * 40:
		await get_tree().physics_frame
		w += 1
		if _inside(all) == all.size():
			break
	verdict("0 все 120 лучников на крышах", _inside(all) == 120, "внутри %d за %d физкадров" % [_inside(all), w])
	await frames(4)
	var cam: Camera3D = main.selection_manager.camera
	# Камера партии над площадкой — глубина и экранные точки считаются по ней
	main._camera.pan_to(base)
	main._camera._update_position()
	await frames(2)
	print("\n═════ A. БАРАКИ ═════")
	_check_building("A", bar, bar._roof, cam, 0, bar._roof.GRID_COLS,
		float(_UCfg.ROOF_FOOT_FRAC["barracks"]), "barracks", int(_UCfg.ROOF_VISIBLE["barracks"]))
	print("\n═════ B. КРЕПОСТЬ: НАСТИЛ ═════")
	_check_building("B", keep, keep._roof, cam, 0, keep._roof.KEEP_CENTRE_COLS,
		float(_UCfg.ROOF_FOOT_FRAC["castle"]), "castle", int(_UCfg.ROOF_VISIBLE["castle"]))
	print("\n═════ C. КРЕПОСТЬ: ФЛАНГИ ═════")
	var fl0: int = keep._roof.KEEP_CENTRE_MEN
	var fl1: int = fl0 + keep._roof.KEEP_FLANK_COLS
	var hK: float = _sprite_h(keep)
	var pfl: Vector3 = keep._roof.slot_local(fl0)
	var pc: Vector3 = keep._roof.slot_local(0)
	verdict("C ноги фланга опущены: %.2f высоты ≤ прежних %.2f, и фланг выше настила" % [pfl.y / hK, float(OLD_FOOT["flank"])],
		pfl.y / hK <= float(OLD_FOOT["flank"]) - 0.04 and pfl.y > pc.y
		and is_equal_approx(pfl.y - keep._roof.spot(fl0, keep._roof.cap).y + keep._roof.spot(0, keep._roof.cap).y, pc.y))
	var wfl: Vector3 = keep.to_global(pfl)
	var wfl2: Vector3 = keep.to_global(keep._roof.slot_local(fl1))
	verdict("C фланг: задний ряд дальше от камеры и выше на экране",
		_depth(cam, wfl2) > _depth(cam, wfl) + 0.05 and cam.unproject_position(wfl2).y < cam.unproject_position(wfl).y)
	# ТЗ 19.09.2026: на фланге 9, правый начинается с fl0 + 9
	verdict("C фланги — по обе стороны настила", pfl.x < keep._draw_cx - _half_w(keep) * 0.4
		and keep._roof.slot_local(fl0 + 9).x > keep._draw_cx + _half_w(keep) * 0.4)
	print("\n═════ D. БАШНЯ ═════")
	# Кольцо башни: место 0 — центр, дальше по эллипсу; передний — с наибольшим
	# экранным y, задний — с наименьшим
	var best_f := 0
	var best_b := 0
	var yf := -1e9
	var yb := 1e9
	for i in range(int(_UCfg.ROOF_VISIBLE["tower"])):
		var sy: float = cam.unproject_position(tower.to_global(tower._roof.slot_local(i))).y
		if sy > yf:
			yf = sy
			best_f = i
		if sy < yb:
			yb = sy
			best_b = i
	_check_building("D", tower, tower._roof, cam, best_f, best_b,
		float(_UCfg.ROOF_FOOT_FRAC["tower"]), "tower", int(_UCfg.ROOF_VISIBLE["tower"]))
	_finish()
