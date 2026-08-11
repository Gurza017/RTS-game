extends Node

## СТЕНД: РАМКА ВЫДЕЛЕНИЯ ПОСТРОЙКИ ОБВОДИТ САМУ ПОСТРОЙКУ
##
## Жалоба игрока: «при выборе Замка, Бараков или Кузницы белая рамка улетает
## далеко от здания». Причина была не в рамке, а в том, ЧЕМ её мерили: маркер
## строился по коробке из unit_stats_config (build_size), а коробка описывает
## пятно для коллизии и размещения. Постройка же — билборд без всякой глубины.
## Положенный на землю квадрат 8×8 м под 45° превращается в ромб, ближний угол
## которого висит далеко перед стеной, а дальний уходит внутрь здания.
##
## Здесь проверяется итог НА ЭКРАНЕ: прямоугольник рамки обязан совпасть с
## прямоугольником нарисованной части картинки с точностью до заданного запаса
## (Building.MARKER_MARGIN). Меряется проекцией камеры, а не повторением формул.

const _BB := preload("res://scripts/BillboardUtil.gd")

var main: Node = null
var cam: Camera3D = null
var _pass := 0
var _fail := 0

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func verdict(title: String, ok: bool, detail: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	print("  ВЕРДИКТ %s: %s%s" % [title, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + detail) if detail != "" else ""])

func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	GameManager.world_bounds_enabled = false
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	await frames(3)
	cam = main._camera
	main._camera.pan_to(Vector3.ZERO)
	await frames(3)

	print("  %-10s %-22s %-22s %s" % ["постройка", "рисунок (экран)", "рамка (экран)", "расхождение"])
	var kinds := {"castle": Castle, "barracks": Barracks, "smithy": Smithy, "mine": Mine}
	for id in kinds:
		await _check(String(id), kinds[id] as GDScript)

	print("\n=== ИТОГ qa_bounds: провалов: %d из %d ===" % [_fail, _pass + _fail])
	get_tree().quit(1 if _fail > 0 else 0)

## Экранный прямоугольник мирового прямоугольника, стоящего вертикально в
## плоскости XY здания (x — поперёк взгляда, y — мировая высота)
func _screen_rect(origin: Vector3, x0: float, x1: float, y0: float, y1: float) -> Rect2:
	var a := cam.unproject_position(origin + Vector3(x0, y0, 0.0))
	var b := cam.unproject_position(origin + Vector3(x1, y1, 0.0))
	return Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)),
		Vector2(absf(b.x - a.x), absf(b.y - a.y)))

func _check(bid: String, cls: GDScript) -> void:
	var b: Building = cls.new()
	b.faction = Constants.FACTION_PLAYER
	main.world_add(b)
	b.global_position = Vector3.ZERO
	await frames(3)

	var spr: MeshInstance3D = null
	var mark: MeshInstance3D = null
	for c in b.get_children():
		if c is MeshInstance3D:
			if c.name == "BuildingSprite": spr = c
			elif c.name == "SelectionMarker": mark = c
	if spr == null:
		print("  %-10s спрайта нет — рисуется процедурно, пропуск" % bid)
		b.queue_free()
		await frames(1)
		return
	if mark == null:
		verdict("%s: маркер выделения есть" % bid, false, "узла SelectionMarker нет")
		b.queue_free()
		await frames(1)
		return

	var sq: QuadMesh = spr.mesh as QuadMesh
	var mq: QuadMesh = mark.mesh as QuadMesh
	if mq == null:
		print("  %-10s маркер не квад (запасное кольцо), пропуск" % bid)
		b.queue_free()
		await frames(1)
		return
	var tex: Texture2D = (sq.material as ShaderMaterial).get_shader_parameter("albedo_tex") as Texture2D
	var v: float = _BB.V_STRETCH
	var r: Rect2 = _BB.opaque_rect(tex)
	var o := b.global_position

	# Где на самом деле НАРИСОВАНО здание (низ квада на грунте, тянет шейдер)
	var art := _screen_rect(o,
		sq.size.x * (r.position.x - 0.5), sq.size.x * (r.end.x - 0.5),
		sq.size.y * (1.0 - r.end.y) * v,  sq.size.y * (1.0 - r.position.y) * v)
	# Где лежит рамка: свой квад, свой центр, свой масштаб по Y
	var half_w: float = mq.size.x * 0.5 * mark.scale.x
	var half_h: float = mq.size.y * 0.5 * mark.scale.y
	var frame := _screen_rect(o,
		mark.position.x - half_w, mark.position.x + half_w,
		mark.position.y - half_h, mark.position.y + half_h)

	var dx: float = absf(frame.get_center().x - art.get_center().x)
	var dy: float = absf(frame.get_center().y - art.get_center().y)
	# Рамка обязана быть чуть больше рисунка (запас), но не в разы
	var kw: float = frame.size.x / maxf(art.size.x, 1.0)
	var kh: float = frame.size.y / maxf(art.size.y, 1.0)
	print("  %-10s %5.0fx%-5.0f при (%4.0f,%4.0f) %5.0fx%-5.0f при (%4.0f,%4.0f)  центр %.0f/%.0f px, ×%.2f/%.2f"
		% [bid, art.size.x, art.size.y, art.get_center().x, art.get_center().y,
			frame.size.x, frame.size.y, frame.get_center().x, frame.get_center().y,
			dx, dy, kw, kh])

	# 3 px — это меньше толщины линии рамки на 1280x720
	verdict("%s: центр рамки совпал с центром рисунка" % bid, dx < 3.0 and dy < 3.0,
		"смещение %.1f / %.1f px" % [dx, dy])
	var want_k: float = 1.0 + Building.MARKER_MARGIN * 2.0
	verdict("%s: рамка обводит рисунок с заданным запасом" % bid,
		absf(kw - want_k) < 0.04 and absf(kh - want_k) < 0.04,
		"ширина ×%.3f, высота ×%.3f, ожидалось ×%.3f" % [kw, kh, want_k])
	# Главное, на что жаловался игрок: рамка не должна свисать под подошву
	var foot_y: float = cam.unproject_position(o).y
	var below: float = frame.end.y - foot_y
	verdict("%s: рамка не свисает под подошву" % bid,
		below < art.size.y * 0.10,
		"ниже подошвы на %.0f px (%.0f%% высоты здания)"
			% [below, 100.0 * below / maxf(art.size.y, 1.0)])
	b.queue_free()
	await frames(1)
