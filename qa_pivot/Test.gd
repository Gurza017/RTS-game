extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ПИВОТЫ ПОСТРОЕК И ДЕРЕВЬЕВ — КЛИК, КОЛЬЦО, ОСНОВАНИЕ РИСУНКА
## ═══════════════════════════════════════════════════════════════════════════
##   A КЛИК ПО КАРТИНКЕ — луч мыши, пущенный в ВЕРХНЮЮ половину рисунка,
##     попадает в постройку, а не пролетает над её коробкой в землю за ней.
##   B КОЛЬЦО НА ЗЕМЛЕ — радиус по НАРИСОВАННОМУ основанию, а не по коробке
##     конфига, и центр — середина этого основания.
##   C ПОДЪЁМ КОЛЬЦА ДЕРЕВА — учитывает растяжение квада шейдером (V_STRETCH),
##     иначе кольцо садится на траву ПОД деревом.
##
## Числа не хардкодятся: всё меряется у самих текстур и констант проекта.
##
## Запуск: godot --headless --path . res://qa_pivot/Test.tscn

const _BBUtil := preload("res://scripts/BillboardUtil.gd")
const _Decal  := preload("res://scripts/SelectionDecalRenderer.gd")

var main = null
var sm   = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

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

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	sm = main.selection_manager
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	GameManager.world_bounds_enabled = false
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	await frames(4)

	await _check_building(load("res://scripts/goblin/GoblinHut.gd").new(), "хижина")
	await _check_building(Castle.new(), "замок")
	_check_tree()

	print("\n═════ ИТОГ ═════")
	for e in _log:
		var r: Array = e
		print("  %s%s" % [_pad(String(r[0]), 64), "ПРОШЛО" if bool(r[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	print("\n=== PIVOT TEST DONE ===")
	get_tree().quit(1 if _fail > 0 else 0)

## Геометрия нарисованной постройки в метрах: [полуширина, низ, верх, сдвиг X]
func _drawn_of(b) -> Array:
	var spr: MeshInstance3D = b.get_node_or_null("BuildingSprite") as MeshInstance3D
	if spr == null:
		return []
	var q: QuadMesh = spr.mesh as QuadMesh
	var mat: ShaderMaterial = q.material as ShaderMaterial
	var tex: Texture2D = mat.get_shader_parameter("albedo_tex") as Texture2D
	var r: Rect2 = _BBUtil.opaque_rect(tex)
	var vs: float = _BBUtil.V_STRETCH
	return [q.size.x * r.size.x * 0.5,
			q.size.y * (1.0 - r.end.y) * vs,
			q.size.y * (1.0 - r.position.y) * vs,
			q.size.x * (r.position.x + r.size.x * 0.5 - 0.5)]

func _check_building(b, nm: String) -> void:
	print("\n═════ %s ═════" % nm.to_upper())
	b.faction = Constants.FACTION_ENEMY
	main.world_add(b)
	b.global_position = Vector3(-90.0, GameManager.get_terrain_height(-90.0, 90.0), 90.0)
	await frames(5)
	var d: Array = _drawn_of(b)
	if d.is_empty():
		verdict("%s: рисунок загружен" % nm, false)
		b.queue_free()
		await frames(2)
		return
	var half: float  = float(d[0])
	var base: float  = float(d[1])
	var top: float   = float(d[2])
	var cx: float    = float(d[3])

	# ── A. ЛУЧ МЫШИ ПОПАДАЕТ В ВЕРХНЮЮ ПОЛОВИНУ РИСУНКА ────────────────────
	var cam: Camera3D = main.get("_camera") as Camera3D
	main.focus_camera_on(b.global_position)
	await frames(3)
	var aim: Vector3 = b.global_position + Vector3(cx, base + (top - base) * 0.78, 0.0)
	var scr: Vector2 = cam.unproject_position(aim)
	var pick: Dictionary = sm._pick_at(scr,
		Constants.LAYER_UNITS | Constants.LAYER_BUILDINGS)
	var hit = pick.get("target", null) if pick != null else null
	verdict("A %s: клик в верх рисунка попадает в постройку" % nm, hit == b,
		"под курсором %s (целились в y=%.2f м, коробка до %.2f м)" % [
			str(hit), aim.y, b.build_size.y])

	# ── B. КОЛЬЦО НА ЗЕМЛЕ ─────────────────────────────────────────────────
	var ring_r: float = _Decal.building_ring_scale(b)
	verdict("B1 %s: кольцо не шире рисунка сверх запаса" % nm,
		ring_r <= half + _Decal.BUILD_RING_MARGIN + 0.01,
		"радиус %.2f м при полуширине рисунка %.2f м" % [ring_r, half])
	verdict("B2 %s: кольцо описывает рисунок, а не коробку конфига" % nm,
		absf(ring_r - (half + _Decal.BUILD_RING_MARGIN)) < 0.01,
		"радиус %.2f м, полугабарит коробки %.2f м" % [
			ring_r, maxf(b.build_size.x, b.build_size.z) * 0.5])
	var c: Vector3 = b.ring_center()
	verdict("B3 %s: кольцо поднято на основание рисунка" % nm,
		absf((c.y - b.global_position.y) - base) < 0.01 and base > 0.0,
		"подъём %.3f м, низ рисунка %.3f м" % [c.y - b.global_position.y, base])
	b.queue_free()
	await frames(2)

## ── C. ДЕРЕВО ──────────────────────────────────────────────────────────────
## Прозрачное поле под стволом меряется в кадре, а рисуется растянутым: квад
## тянет шейдер растительности от нижней кромки вверх (V_STRETCH). Проверяем,
## что подъём кольца это учитывает, — иначе он выходит на 29% ниже нужного
func _check_tree() -> void:
	print("\n═════ ДЕРЕВО ═════")
	var trees: Array = get_tree().get_nodes_in_group("resource_nodes")
	var tree: ResourceNode = null
	for t in trees:
		var rn := t as ResourceNode
		if rn != null and rn.resource_type == Constants.RESOURCE_WOOD:
			tree = rn
			break
	if tree == null:
		verdict("C0 дерево на карте найдено", false)
		return
	var lift: float = tree.hover_ring_lift()
	verdict("C1 подъём кольца у комля больше нуля", lift > 0.0,
		"%.3f м" % lift)
	# ── СЧИТАЕМ ТО ЖЕ НАПРЯМУЮ ПО ТЕКСТУРЕ И СВЕРЯЕМ ───────────────────────
	# ПОРОГ ОБЯЗАН БЫТЬ ТОТ ЖЕ, ПО КОТОРОМУ РЕЖЕТ ШЕЙДЕР. Здесь стоял
	# Image.get_used_rect(), то есть «непрозрачно всё, где альфа > 0», а
	# veg_multimesh отбрасывает пустоту по ALPHA_SCISSOR_THRESHOLD = 0.5.
	# Пиксели между двумя порогами не рисуются вовсе, и проверка сверяла
	# подъём с основанием, которого на экране нет (замер: мимо на 0.19-0.26 м).
	# Единый обмер — BillboardUtil.opaque_rect, он режет по тому же числу
	var rr: Rect2 = _BBUtil.opaque_rect(tree._veg_tex)
	var frac: float = clampf(1.0 - rr.end.y, 0.0, 0.4)
	var want: float = frac * tree.TREE_HEIGHT * _BBUtil.V_STRETCH
	verdict("C2 подъём считается по полю текстуры И с растяжением квада",
		absf(lift - want) < 0.001,
		"%.3f м, без растяжения было бы %.3f м" % [lift, frac * tree.TREE_HEIGHT])
