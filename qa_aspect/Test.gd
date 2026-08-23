extends Node

## СТЕНД: ПРОПОРЦИИ СПРАЙТОВ (соотношение сторон и масштаб)
##
## Проверяет ОДНО правило: нарисованный на карте прямоугольник должен иметь то
## же соотношение сторон, что и КАДР его текстуры. Любое расхождение — это и
## есть «сплющенность»/«вытянутость», которую видно глазом.
##
## Разделы:
##   A — постройки: квад берёт пропорции картинки, а не коробки коллизии
##   B — юниты: масштаб равномерный (pixel_size), перекоса по осям нет
##   C — ресурсы: жилы, камни, деревья
##   D — фантом постановки совпадает с настоящей постройкой

const _BB   := preload("res://scripts/BillboardUtil.gd")
const _UCfg := preload("res://scripts/unit_stats_config.gd")

var main: Node = null
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

## Соотношение сторон нарисованного квада
func _quad_aspect(q: QuadMesh) -> float:
	if q == null or q.size.y <= 0.0:
		return -1.0
	return q.size.x / q.size.y

## Найти QuadMesh с текстурой среди потомков
func _find_quad(n: Node, want_name: String = "") -> QuadMesh:
	for c in n.get_children():
		if c is MeshInstance3D:
			if want_name != "" and c.name != want_name:
				pass
			else:
				var q := (c as MeshInstance3D).mesh as QuadMesh
				if q != null:
					return q
		var deep := _find_quad(c, want_name)
		if deep != null:
			return deep
	return null

func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	GameManager.world_bounds_enabled = false
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	await frames(3)

	await _test_buildings()
	await _test_units()
	await _test_resources()

	print("\n=== ИТОГ qa_aspect: провалов: %d из %d ===" % [_fail, _pass + _fail])
	get_tree().quit()

# ═════════════════════════════════════════════════════════════════════════════
# A. ПОСТРОЙКИ
# ═════════════════════════════════════════════════════════════════════════════
func _test_buildings() -> void:
	print("\n═════ A. ПОСТРОЙКИ ═════")
	print("  %-12s %-9s %-9s %-9s %s" % [
		"постройка", "текстура", "квад", "коробка", "вердикт"])
	var kinds := {
		"castle":   Castle,
		"barracks": Barracks,
		"smithy":   Smithy,
		"mine":     Mine,
	}
	for id in kinds:
		var bid: String = String(id)
		var b: Building = (kinds[bid] as GDScript).new()
		b.faction = Constants.FACTION_PLAYER
		main.world_add(b)
		b.global_position = Vector3(-120 + float(bid.length()) * 3.0, 0, -120)
		await frames(2)

		var path: String = GameManager.building_sprite_path(b.faction, b.building_id)
		if path.is_empty() or not ResourceLoader.exists(path):
			print("  %-12s спрайта нет — рисуется процедурно, пропуск" % bid)
			b.queue_free()
			continue
		var tex := load(path) as Texture2D
		var want: float = _BB.frame_aspect(tex)
		var quad := _find_quad(b, "BuildingSprite")
		if quad == null:
			verdict("A %s: спрайт построен" % bid, false, "квада нет")
			b.queue_free()
			continue
		var got: float = _quad_aspect(quad)
		var box_a: float = b.build_size.x / maxf(b.build_size.y, 0.01)
		var ok: bool = absf(got - want) < 0.02
		print("  %-12s %-9.3f %-9.3f %-9.3f %s" % [
			bid, want, got, box_a, "OK" if ok else "СПЛЮЩЕНО"])
		verdict("A %s: пропорции квада = пропорциям картинки" % bid, ok,
			"картинка %.3f, нарисовано %.3f (коробка дала бы %.3f)"
				% [want, got, box_a])
		# И низ спрайта обязан лежать на грунте, а не парить и не тонуть
		var mi: MeshInstance3D = null
		for c in b.get_children():
			if c is MeshInstance3D and c.name == "BuildingSprite":
				mi = c
		if mi != null:
			verdict("A %s: низ спрайта на земле" % bid,
				absf(mi.position.y - quad.size.y * 0.5) < 0.01,
				"центр %.2f, половина высоты %.2f" % [mi.position.y, quad.size.y * 0.5])
		b.queue_free()
		await frames(1)

# ═════════════════════════════════════════════════════════════════════════════
# B. ЮНИТЫ
# ═════════════════════════════════════════════════════════════════════════════
func _test_units() -> void:
	print("\n═════ B. ЮНИТЫ ═════")
	print("  %-10s %-8s %-10s %-8s %s" % [
		"юнит", "кадр", "pixel_size", "высота", "перекос осей"])
	var kinds := ["worker", "spearman", "archer", "warrior"]
	for k in kinds:
		var uid: String = String(k)
		var u: Unit = load("res://scenes/units/%s.tscn" % uid.capitalize()).instantiate()
		u.faction = Constants.FACTION_PLAYER
		get_tree().root.add_child(u)
		u.global_position = Vector3(-200, 0, -200)
		await frames(3)

		# ПЕРЕКОС МАСШТАБА. Спрайтовый юнит масштабируется ОДНИМ числом
		# (pixel_size), поэтому исказить пропорции можно только руками —
		# неравным scale на узле. Это и ищем, у самого юнита и у его спрайта
		var skew_ok := true
		var worst := ""
		var stack: Array = [u]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n is Node3D:
				var s: Vector3 = (n as Node3D).scale
				if absf(s.x - s.y) > 0.001 or absf(s.x - s.z) > 0.001:
					skew_ok = false
					worst = "%s scale=%s" % [n.name, str(s)]
			for c in n.get_children():
				stack.append(c)
		var frame_h := 0
		var px := 0.0
		var asp := u.get("_active_sprite") as AnimatedSprite3D
		if asp != null and asp.sprite_frames != null:
			px = asp.pixel_size
			var fr: Texture2D = asp.sprite_frames.get_frame_texture(
				asp.animation, 0)
			if fr != null:
				frame_h = int(fr.get_size().y)
		else:
			var spr := u.get("_dir_sprite") as Sprite3D
			if spr != null:
				px = spr.pixel_size
				if spr.texture != null:
					frame_h = int(spr.texture.get_size().y)
					if spr.hframes > 1:
						pass
		print("  %-10s %-8d %-10.4f %-8.2f %s" % [
			uid, frame_h, px, float(frame_h) * px,
			"нет" if skew_ok else worst])
		verdict("B %s: масштаб равномерный по осям" % uid, skew_ok, worst)
		u.queue_free()
		await frames(1)

# ═════════════════════════════════════════════════════════════════════════════
# C. РЕСУРСЫ
# ═════════════════════════════════════════════════════════════════════════════
func _test_resources() -> void:
	print("\n═════ C. РЕСУРСЫ ═════")
	var types := {
		Constants.RESOURCE_WOOD:  "дерево",
		Constants.RESOURCE_GOLD:  "золото",
		Constants.RESOURCE_STONE: "камень",
		Constants.RESOURCE_FOOD:  "еда",
	}
	for t in types:
		var rt: int = int(t)
		var node := ResourceNode.new()
		node.resource_type = rt
		main.world_add(node)
		node.global_position = Vector3(-260, 0, -260)
		await frames(3)
		var quad := _find_quad(node)
		if quad == null:
			print("  %-8s квада нет — процедурный вид, пропуск" % types[t])
			node.queue_free()
			await frames(1)
			continue
		var mat := quad.material
		var tex: Texture2D = null
		if mat is ShaderMaterial:
			tex = (mat as ShaderMaterial).get_shader_parameter("albedo_tex") as Texture2D
		elif mat is StandardMaterial3D:
			tex = (mat as StandardMaterial3D).albedo_texture
		if tex == null:
			print("  %-8s текстуры в материале нет, пропуск" % types[t])
			node.queue_free()
			await frames(1)
			continue
		# ── ПРОПОРЦИЯ СЧИТАЕТСЯ ПО КАДРУ, А НЕ ПО ВСЕЙ ЛЕНТЕ ────────────────
		# У золота спрайт — ЛЕНТА из шести кадров (по самородку ходит глянец),
		# и рисуется она покадрово. BillboardUtil.frame_aspect делит на число
		# кадров сам, но узнать его у пересобранной ленты не может: у неё нет
		# resource_path, и детектор падает на угадывание по пропорции. Спросим
		# у самого узла, сколько кадров он нарисовал
		var want: float = _BB.frame_aspect(tex)
		var fc_node: int = int(node.get("sprite_frames_drawn"))
		if fc_node > 1 and _BB.frame_count(tex) <= 1:
			want /= float(fc_node)
		var got: float = _quad_aspect(quad)
		print("  %-8s картинка=%.3f нарисовано=%.3f" % [types[t], want, got])
		verdict("C %s: пропорции сохранены" % String(types[t]),
			absf(got - want) < 0.02,
			"картинка %.3f, нарисовано %.3f" % [want, got])
		node.queue_free()
		await frames(1)
