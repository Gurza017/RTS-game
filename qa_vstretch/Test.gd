extends Node

## СТЕНД: ПРОПОРЦИИ НА ЭКРАНЕ (компенсация наклона камеры)
##
## qa_aspect сверяет МИРОВОЙ квад с кадром текстуры и на «приплюснутость» не
## реагирует вовсе: сжатие возникает не в геометрии, а в ПРОЕКЦИИ. Камера
## ортографическая и наклонена на 45°, спрайты — билборды с МИРОВОЙ осью Y,
## поэтому метр высоты занимает на экране cos(45°) = 0.707 метра, а метр
## ширины — целый. Отсюда и «все модели сплющены».
##
## Здесь проверяется итог: ЭКРАННЫЕ пропорции нарисованного прямоугольника
## обязаны совпадать с пропорциями кадра PNG. Меряется честной проекцией
## Camera3D.unproject_position, а не повторением формулы из кода.
##
## Разделы:
##   A — сама константа BillboardUtil.V_STRETCH выведена из угла камеры
##   B — постройки: экранные пропорции = пропорции картинки, низ на грунте
##   C — деревья: то же
##   D — бойцы: квад в MultiMesh растянут, подошва осталась на грунте

const _BB   := preload("res://scripts/BillboardUtil.gd")
const _UCfg := preload("res://scripts/unit_stats_config.gd")

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

## Экранная ширина отрезка, положенного ГОРИЗОНТАЛЬНО поперёк взгляда
func _screen_w(center: Vector3, w: float) -> float:
	var a := cam.unproject_position(center - Vector3(w * 0.5, 0.0, 0.0))
	var b := cam.unproject_position(center + Vector3(w * 0.5, 0.0, 0.0))
	return a.distance_to(b)

## Экранная высота отрезка, поднятого ВЕРТИКАЛЬНО от точки на земле
func _screen_h(ground: Vector3, h: float) -> float:
	var a := cam.unproject_position(ground)
	var b := cam.unproject_position(ground + Vector3(0.0, h, 0.0))
	return a.distance_to(b)

func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	GameManager.world_bounds_enabled = false
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	await frames(3)
	cam = main._camera
	if cam == null:
		print("КАМЕРЫ НЕТ — стенд бессмыслен")
		get_tree().quit(1)
		return

	_test_constant()
	await _test_buildings()
	await _test_trees()
	await _test_units()

	print("\n=== ИТОГ qa_vstretch: провалов: %d из %d ===" % [_fail, _pass + _fail])
	get_tree().quit(1 if _fail > 0 else 0)

# ═════════════════════════════════════════════════════════════════════════════
# A. КОНСТАНТА
# ═════════════════════════════════════════════════════════════════════════════
func _test_constant() -> void:
	print("\n═════ A. КОНСТАНТА ═════")
	# Ожидание выводится из угла камеры, а не переписывается числом: сменят
	# наклон — стенд поедет за ним вместе с игрой
	var want: float = 1.0 / cos(deg_to_rad(RTSCamera.FIXED_PITCH))
	print("  наклон камеры %.1f°, компенсация %.4f (ожидалось %.4f)"
		% [RTSCamera.FIXED_PITCH, _BB.V_STRETCH, want])
	verdict("A1: V_STRETCH выведен из наклона камеры",
		absf(_BB.V_STRETCH - want) < 0.0005,
		"получено %.4f, ожидалось %.4f" % [_BB.V_STRETCH, want])
	verdict("A2: компенсация вообще есть", _BB.V_STRETCH > 1.0,
		"%.4f" % _BB.V_STRETCH)
	# Камера обязана остаться ортографической: в перспективе множитель зависел
	# бы ещё и от места на экране, и одной константой было бы не обойтись
	verdict("A3: камера ортографическая",
		cam.projection == Camera3D.PROJECTION_ORTHOGONAL,
		"projection = %d" % cam.projection)

# ═════════════════════════════════════════════════════════════════════════════
# B. ПОСТРОЙКИ
# ═════════════════════════════════════════════════════════════════════════════
func _find_mesh(n: Node, want_name: String) -> MeshInstance3D:
	for c in n.get_children():
		if c is MeshInstance3D and c.name == want_name:
			return c
		var deep := _find_mesh(c, want_name)
		if deep != null:
			return deep
	return null

func _test_buildings() -> void:
	print("\n═════ B. ПОСТРОЙКИ ═════")
	print("  %-10s %-9s %-9s %s" % ["постройка", "картинка", "на экране", "вердикт"])
	var kinds := {"castle": Castle, "barracks": Barracks, "smithy": Smithy, "mine": Mine}
	for id in kinds:
		var bid: String = String(id)
		var b: Building = (kinds[bid] as GDScript).new()
		b.faction = Constants.FACTION_PLAYER
		main.world_add(b)
		b.global_position = Vector3(-120.0 + float(bid.length()) * 3.0, 0.0, -120.0)
		await frames(2)
		var mi := _find_mesh(b, "BuildingSprite")
		var quad: QuadMesh = mi.mesh as QuadMesh if mi != null else null
		if quad == null:
			print("  %-10s спрайта нет — процедурный вид, пропуск" % bid)
			b.queue_free()
			await frames(1)
			continue
		var mat := quad.material as ShaderMaterial
		var tex: Texture2D = mat.get_shader_parameter("albedo_tex") as Texture2D
		var want: float = _BB.frame_aspect(tex)
		# Шейдер тянет квад от НИЖНЕЙ кромки, поэтому нарисованная высота —
		# size.y * v_stretch, а низ остался там же, где стоял узел минус половина
		var v: float = float(mat.get_shader_parameter("v_stretch"))
		var ground := b.global_position
		var drawn_h: float = quad.size.y * v
		var got: float = _screen_w(ground, quad.size.x) / maxf(_screen_h(ground, drawn_h), 0.001)
		var ok: bool = absf(got - want) < 0.02
		print("  %-10s %-9.3f %-9.3f %s" % [bid, want, got, "OK" if ok else "СПЛЮЩЕНО"])
		verdict("B %s: экранные пропорции = пропорциям картинки" % bid, ok,
			"картинка %.3f, на экране %.3f" % [want, got])
		verdict("B %s: коррекция дошла до материала" % bid,
			absf(v - _BB.V_STRETCH) < 0.0005, "v_stretch = %.4f" % v)
		# Низ спрайта = грунт: узел поднят на половину НЕрастянутой высоты, а
		# тянется он от нижней кромки, значит подошва не двигается вовсе
		verdict("B %s: низ спрайта остался на грунте" % bid,
			absf(mi.position.y - quad.size.y * 0.5) < 0.01,
			"центр %.2f, половина высоты %.2f" % [mi.position.y, quad.size.y * 0.5])
		b.queue_free()
		await frames(1)

# ═════════════════════════════════════════════════════════════════════════════
# C. ДЕРЕВЬЯ
# ═════════════════════════════════════════════════════════════════════════════
func _find_quad_mesh(n: Node) -> MeshInstance3D:
	for c in n.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh is QuadMesh:
			return c
		var deep := _find_quad_mesh(c)
		if deep != null:
			return deep
	return null

func _test_trees() -> void:
	print("\n═════ C. ДЕРЕВЬЯ ═════")
	var node := ResourceNode.new()
	node.resource_type = Constants.RESOURCE_WOOD
	main.world_add(node)
	node.global_position = Vector3(-260.0, 0.0, -260.0)
	await frames(3)
	var mi := _find_quad_mesh(node)
	if mi == null:
		print("  квада нет — процедурный вид, пропуск")
		node.queue_free()
		return
	var quad: QuadMesh = mi.mesh as QuadMesh
	var mat := quad.material as ShaderMaterial
	if mat == null:
		print("  материал не шейдерный, пропуск")
		node.queue_free()
		return
	var tex: Texture2D = mat.get_shader_parameter("albedo_tex") as Texture2D
	var want: float = _BB.frame_aspect(tex)
	var v: float = float(mat.get_shader_parameter("v_stretch"))
	var ground := node.global_position
	var got: float = _screen_w(ground, quad.size.x) / maxf(_screen_h(ground, quad.size.y * v), 0.001)
	print("  дерево: картинка=%.3f на экране=%.3f (компенсация %.3f)" % [want, got, v])
	verdict("C1: экранные пропорции дерева = пропорциям кадра",
		absf(got - want) < 0.02, "картинка %.3f, на экране %.3f" % [want, got])
	verdict("C2: коррекция дошла до материала дерева",
		absf(v - _BB.V_STRETCH) < 0.0005, "v_stretch = %.4f" % v)
	node.queue_free()
	await frames(1)

# ═════════════════════════════════════════════════════════════════════════════
# D. БОЙЦЫ
# ═════════════════════════════════════════════════════════════════════════════
func _test_units() -> void:
	print("\n═════ D. БОЙЦЫ ═════")
	print("  %-10s %-9s %-9s %s" % ["боец", "картинка", "на экране", "вердикт"])
	for k in ["worker", "spearman", "archer", "warrior"]:
		var uid: String = String(k)
		var u: Unit = load("res://scenes/units/%s.tscn" % uid.capitalize()).instantiate()
		u.faction = Constants.FACTION_PLAYER
		main.world_add(u)
		u.global_position = Vector3(-200.0, GameManager.get_terrain_height(-200.0, -200.0), -200.0)
		await frames(4)
		var slot = GameManager.far_units.slot_of(u)
		if slot == null:
			verdict("D %s: боец попал в общую отрисовку" % uid, false, "слота нет")
			u.queue_free()
			await frames(1)
			continue
		var quad: QuadMesh = slot.bucket.mm.mesh as QuadMesh
		var sf: Array = u.sheet_frame()
		var frame_h: float = float((sf[0] as Texture2D).get_size().y)
		var frame_w: float = float((sf[0] as Texture2D).get_size().x) / float(maxi(sf[2], 1))
		var px: float = sf[3]
		# Высота квада растянута на CPU (см. FarUnitRenderer._get_or_make_bucket)
		verdict("D %s: высота квада домножена на V_STRETCH" % uid,
			absf(quad.size.y - frame_h * px * _BB.V_STRETCH) < 0.001,
			"квад %.3f, ожидалось %.3f" % [quad.size.y, frame_h * px * _BB.V_STRETCH])
		verdict("D %s: ширина квада НЕ тронута" % uid,
			absf(quad.size.x - frame_w * px) < 0.001,
			"квад %.3f, ожидалось %.3f" % [quad.size.x, frame_w * px])
		# Подошва на грунте: центр спрайта поднят на base_y * V, а половина
		# высоты квада выросла тем же множителем — низ фигуры не поехал
		verdict("D %s: высота центра растянута тем же числом" % uid,
			absf(slot.base_y - sf[4] * _BB.V_STRETCH) < 0.001,
			"base_y слота %.3f, у бойца %.3f" % [slot.base_y, sf[4]])
		var ground := u.global_position
		var want: float = frame_w / frame_h
		var got: float = _screen_w(ground, quad.size.x) / maxf(_screen_h(ground, quad.size.y), 0.001)
		var ok: bool = absf(got - want) < 0.02
		print("  %-10s %-9.3f %-9.3f %s" % [uid, want, got, "OK" if ok else "СПЛЮЩЕНО"])
		verdict("D %s: экранные пропорции = пропорциям кадра" % uid, ok,
			"кадр %.3f, на экране %.3f" % [want, got])
		u.queue_free()
		await frames(1)
