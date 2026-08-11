extends Node

## Проверяет: (A) кучи ресурсов — компактные и разнообразные, без линий;
## (B) материал блеска золота режет спрайт-шит на кадры.

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	_check_clusters()
	_check_shimmer()
	_check_base_zones()
	print("\n=== CLUSTERCHECK DONE ===")
	get_tree().quit()

# ── C. Безопасные зоны баз и лесной карман ───────────────────────────────────
func _check_base_zones() -> void:
	print("\n───── БАЗЫ: ЧИСТАЯ ПЛОЩАДКА И ЛЕСНОЙ КАРМАН ─────")
	var m: Node = GameManager.main
	var anchors := {
		"игрок": m.PLAYER_BASE_ANCHOR,
		"ИИ":    m.ENEMY_BASE_ANCHOR,
	}
	for label in anchors:
		var a: Vector3 = anchors[label]
		var inside := 0        # что угодно внутри безопасной зоны
		var ore_near: Array = []   # кучи руды рядом
		# Гистограмма деревьев по секторам вокруг базы (12 секторов по 30°)
		var sectors: Array = []
		sectors.resize(12)
		sectors.fill(0)
		for n in get_tree().get_nodes_in_group("resource_nodes"):
			var rn := n as ResourceNode
			if rn == null:
				continue
			var dx: float = rn.global_position.x - a.x
			var dz: float = rn.global_position.z - a.z
			var d := Vector2(dx, dz).length()
			if d < m.BASE_CLEAR_RADIUS:
				inside += 1
			if rn.resource_type == Constants.RESOURCE_WOOD:
				if d >= m.POCKET_INNER - 1.0 and d <= m.POCKET_OUTER + 2.0:
					var ang := atan2(dz, dx)
					if ang < 0.0:
						ang += TAU
					var si := int(ang / (TAU / 12.0)) % 12
					sectors[si] = int(sectors[si]) + 1
			elif d < 26.0:
				ore_near.append({"t": rn.resource_type, "d": d,
					"ang": rad_to_deg(atan2(dz, dx))})

		print("\nбаза «%s» @ (%.0f, %.0f)" % [label, a.x, a.z])
		print("  ресурсов внутри радиуса %.0f м: %d  (должно быть 0)"
			% [m.BASE_CLEAR_RADIUS, inside])

		# Открытый сектор смотрит в центр карты
		var to_c := Vector3.ZERO - a
		var open_ang := rad_to_deg(atan2(to_c.z, to_c.x))
		if open_ang < 0.0:
			open_ang += 360.0
		var open_si := int(open_ang / 30.0) % 12
		var open_cnt := 0
		var closed_cnt := 0
		for i in range(12):
			# Открытый сектор ±60° = 4 сектора по 30°
			var diff: int = mini(abs(i - open_si), 12 - abs(i - open_si))
			if diff <= 1:
				open_cnt += int(sectors[i])
			else:
				closed_cnt += int(sectors[i])
		print("  деревьев в полосе %.0f-%.0f м: перед замком=%d, с трёх сторон=%d"
			% [m.POCKET_INNER, m.POCKET_OUTER, open_cnt, closed_cnt])
		print("  по секторам (30° каждый, начиная с востока): %s" % str(sectors))
		print("  открытый сектор смотрит на %d° (индекс %d)" % [int(open_ang), open_si])

		var gold_d := -1.0
		var stone_d := -1.0
		for e in ore_near:
			var d: Dictionary = e
			var dist: float = d["d"]
			if int(d["t"]) == Constants.RESOURCE_GOLD:
				if gold_d < 0.0 or dist < gold_d: gold_d = dist
			elif int(d["t"]) == Constants.RESOURCE_STONE:
				if stone_d < 0.0 or dist < stone_d: stone_d = dist
		print("  ближайшее золото: %.1f м, ближайший камень: %.1f м" % [gold_d, stone_d])

# ── A. Геометрия куч ─────────────────────────────────────────────────────────
func _check_clusters() -> void:
	print("\n───── КУЧИ РЕСУРСОВ ─────")
	for res_type in [Constants.RESOURCE_GOLD, Constants.RESOURCE_STONE]:
		var pts: Array = []
		var scales: Array = []
		for n in get_tree().get_nodes_in_group("resource_nodes"):
			var rn := n as ResourceNode
			if rn == null or rn.resource_type != res_type:
				continue
			pts.append(Vector2(rn.global_position.x, rn.global_position.z))
			scales.append(rn.size_scale)
		var label := "ЗОЛОТО" if res_type == Constants.RESOURCE_GOLD else "КАМЕНЬ"
		if pts.is_empty():
			print("%s: узлов нет" % label)
			continue

		var groups := _group(pts, 6.0)
		print("\n%s: узлов=%d, куч=%d" % [label, pts.size(), groups.size()])
		var sizes: Array = []
		for g in groups:
			var grp: Array = g
			sizes.append(grp.size())
			var stat := _spread(grp)
			# Линейность: отношение большей полуоси разброса к меньшей.
			# ~1 = круглая куча, >4 = вытянутая цепочка/«забор»
			print("   куча из %2d шт: радиус=%.2f м, вытянутость=%.2f, плотность=%.2f шт/м²"
				% [grp.size(), stat.x, stat.y, float(grp.size()) / maxf(PI * stat.x * stat.x, 0.01)])
		var uniq: Array = []
		for s in sizes:
			if not (s in uniq):
				uniq.append(s)
		uniq.sort()
		print("   размеры куч (шт в куче): %s  <- разные = пресеты работают" % str(uniq))
		var smin := 99.0
		var smax := 0.0
		for s in scales:
			smin = minf(smin, s)
			smax = maxf(smax, s)
		print("   масштабы кусков: от %.2f до %.2f" % [smin, smax])

# Разбивает точки на кучи: соседи ближе link_dist попадают в одну
func _group(pts: Array, link_dist: float) -> Array:
	var used: Array = []
	used.resize(pts.size())
	used.fill(false)
	var groups: Array = []
	for i in range(pts.size()):
		if used[i]:
			continue
		var queue: Array = [i]
		used[i] = true
		var grp: Array = []
		while not queue.is_empty():
			var k: int = queue.pop_back()
			var p: Vector2 = pts[k]
			grp.append(p)
			for j in range(pts.size()):
				if used[j]:
					continue
				if p.distance_to(pts[j]) <= link_dist:
					used[j] = true
					queue.append(j)
		groups.append(grp)
	return groups

# Возвращает (радиус, вытянутость) кучи через разброс по главным осям
func _spread(grp: Array) -> Vector2:
	var c := Vector2.ZERO
	for p in grp:
		c += p
	c /= float(grp.size())
	var rmax := 0.0
	# Ковариация -> собственные значения 2x2
	var sxx := 0.0
	var szz := 0.0
	var sxz := 0.0
	for p in grp:
		var d: Vector2 = p - c
		rmax = maxf(rmax, d.length())
		sxx += d.x * d.x
		szz += d.y * d.y
		sxz += d.x * d.y
	var n := float(grp.size())
	sxx /= n; szz /= n; sxz /= n
	var tr := sxx + szz
	var det := sxx * szz - sxz * sxz
	var disc: float = maxf(tr * tr * 0.25 - det, 0.0)
	var l1: float = tr * 0.5 + sqrt(disc)
	var l2: float = tr * 0.5 - sqrt(disc)
	var elong: float = sqrt(maxf(l1, 1e-6)) / sqrt(maxf(l2, 1e-6))
	return Vector2(maxf(rmax, 0.01), elong)

# ── B. Материал блеска ───────────────────────────────────────────────────────
func _check_shimmer() -> void:
	print("\n───── БЛЕСК ЗОЛОТА ─────")
	var checked := 0
	for n in get_tree().get_nodes_in_group("resource_nodes"):
		var rn := n as ResourceNode
		if rn == null or rn.resource_type != Constants.RESOURCE_GOLD:
			continue
		var shim: MeshInstance3D = null
		for c in rn.get_children():
			for cc in c.get_children():
				if cc.name == "GoldShimmer":
					shim = cc as MeshInstance3D
		if shim == null:
			continue
		var q := shim.mesh as QuadMesh
		var mat := q.material as ShaderMaterial
		var fc: float  = mat.get_shader_parameter("frame_count")
		var fps: float = mat.get_shader_parameter("frame_fps")
		var ph: float  = mat.get_shader_parameter("phase")
		var tex: Texture2D = mat.get_shader_parameter("highlight_tex")
		var sz := tex.get_size()
		if checked < 4:
			print("жила: лист %dx%d -> кадров=%.0f (ожидалось %.0f), fps=%.1f, фаза=%.2f"
				% [int(sz.x), int(sz.y), fc, sz.x / sz.y, fps, ph])
		checked += 1
	print("проверено жил с блеском: %d" % checked)
	print("frame_count должен равняться w/h — тогда шейдер берёт ОДИН кадр, а не весь лист")
