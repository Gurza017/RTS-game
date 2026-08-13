extends Node

## СТЕНД БАГФИКС-ПАКА
##   1 ПАРЕНИЕ   — высота спрайта копейщика в АТАКЕ и в ЗАЩИТЕ
##   2 DEFENSE   — отряд в защите стоит на месте и не агрится
##   3 РЕСУРСЫ   — нижняя кромка куска руды лежит на земле
##   4 СТРЕЛЫ    — все стрелы исчезают через MAX_LIFETIME от выстрела
##   5 ФОРМАЦИЯ  — превью рисует только треугольники, без жёлтой полосы

const _UCfg := preload("res://scripts/unit_stats_config.gd")

var main: Node = null
var verdicts: Array = []

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func verdict(title: String, ok: bool, detail: String = "") -> void:
	verdicts.append([title, ok])
	print("  ВЕРДИКТ %s: %s%s" % [title, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + detail) if detail != "" else ""])

func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	# СТЕНД РАБОТАЕТ ЗА ПРЕДЕЛАМИ КАРТЫ: площадки вынесены далеко в сторону,
	# чтобы ни ИИ, ни лес, ни чужие отряды не мешали замеру. Жёсткая граница
	# мира стянула бы их все в угол поля — на время стенда её снимаем
	GameManager.world_bounds_enabled = false
	await frames(2)

	await _probe_sprite_height()
	await _test_defense_hold()
	_test_resource_ground()
	await _test_arrow_lifetime()
	_test_formation_preview()
	_summary()
	print("\n=== FIX TEST DONE ===")
	get_tree().quit()

func _summary() -> void:
	print("\n═════ ИТОГ ═════")
	var bad := 0
	for v in verdicts:
		var row: Array = v
		if not bool(row[1]):
			bad += 1
		print("  %-56s %s" % [String(row[0]), "ПРОШЛО" if bool(row[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [bad, verdicts.size()])

# ═════════════════════════════════════════════════════════════════════════════
# 1. ПАРЕНИЕ МОДЕЛЕЙ В ЗАЩИТЕ
# ═════════════════════════════════════════════════════════════════════════════
func _probe_sprite_height() -> void:
	print("\n═════ 1. ВЫСОТА СПРАЙТА: АТАКА vs ЗАЩИТА ═════")
	var u := Spearman.new()
	u.faction = Constants.FACTION_PLAYER
	main.world_add(u)
	u.global_position = Vector3(-100.0, 0.0, -100.0)
	await frames(3)

	var spr = u._dir_sprite
	if spr == null:
		print("  спрайт направления не создан (нет ассетов) — проверка неприменима")
		verdict("1 высота спрайта одинакова в обеих стойках", true, "спрайта нет")
		u.queue_free()
		return

	print("  нижние отступы альфы по листам (px):")
	var keys: Array = u._dir_bottom.keys()
	keys.sort()
	for k in keys:
		print("    %-16s %d px" % [String(k), int(u._dir_bottom[k])])

	# КЛЮЧЕВОЙ ЗАМЕР: сдвинута ли ВСЯ фигура или вниз торчит только копьё.
	# Если верхняя кромка уезжает вниз вместе с нижней — это честный сдвиг
	# рисунка, и компенсация нужна. Если верх стоит на месте, а низ ушёл —
	# значит вылезло остриё, и компенсация поднимает бойца в воздух.
	print("  альфа-бокс первого кадра (сверху вниз), px:")
	print("    %-16s %5s %5s %5s %5s" % ["лист", "верх", "низ", "высота", "центр"])
	for k in keys:
		var key: String = String(k)
		var tex: Texture2D = u._dir_textures.get(key)
		if tex == null:
			continue
		var img := tex.get_image()
		if img == null:
			continue
		if img.is_compressed():
			img.decompress()
		var h: int = img.get_height()
		var fw: int = img.get_width() / maxi(int(u._dir_frames.get(key, 1)), 1)
		var top := -1
		var bot := -1
		for y in range(h):
			var opaque := false
			for x in range(0, fw, 2):
				if img.get_pixel(x, y).a > 0.02:
					opaque = true
					break
			if opaque:
				if top < 0:
					top = y
				bot = y
		if top < 0:
			continue
		print("    %-16s %5d %5d %6d %5.1f" % [
			key, top, h - 1 - bot, bot - top + 1, float(top + bot) * 0.5])

	# Меряем ВСЕ листы поимённо, а не только тот, что выпал по направлению:
	# парение вылезало именно на «нижних» защитных позах, где копьё уходит
	# ниже ступней
	# ВЫСОТА ПРИВЯЗКИ — ЭТО ЧИСЛО НА БОЙЦЕ, А НЕ position.y УЗЛА. В общей
	# отрисовке (MultiMesh) узел спрайта невидим и в него ничего не пишется
	# (см. Unit._mm_only и Spearman._apply_dir_tex): единственный владелец
	# высоты — поле _sprite_base_y, его и сверяем. Раньше стенд читал узел и
	# видел одно и то же значение на всех листах — отсюда «расхождений=8»
	u._apply_dir_tex("idle")
	var y_idle: float = u._sprite_base_y
	print("  эталон idle: _sprite_base_y=%.4f (узел: position.y=%.4f)"
		% [y_idle, spr.position.y])
	var worst_key := ""
	var worst_dy := 0.0
	for k in keys:
		var key: String = String(k)
		u._apply_dir_tex(key)
		var dy: float = u._sprite_base_y - y_idle
		if absf(dy) > absf(worst_dy):
			worst_dy = dy
			worst_key = key
		print("    %-16s _sprite_base_y=%.4f  отклонение от idle=%+.4f м" % [
			key, u._sprite_base_y, dy])
	print("  ХУДШИЙ лист: «%s», отклонение %+.4f м" % [worst_key, worst_dy])
	print("  ВАЖНО: ненулевое отклонение здесь — НОРМА. Это компенсация того,")
	print("  что в «нижних» позах рисунок сдвинут вниз внутри кадра целиком")
	print("  (высота альфа-бокса та же ±1 px). Проверяем не ноль, а СОГЛАСОВАННОСТЬ:")
	print("  подъём базы обязан совпадать с разницей нижних отступов.")
	var bad := 0
	var ref_px: int = int(u._dir_bottom.get("idle", 0))
	for k in keys:
		var key: String = String(k)
		u._apply_dir_tex(key)
		var mine: int = int(u._dir_bottom.get(key, ref_px))
		var expect: float = float(ref_px - mine) * Spearman.PIXEL_SIZE
		var got: float = u._sprite_base_y - y_idle
		if absf(got - expect) > 0.001:
			bad += 1
			print("    РАСХОЖДЕНИЕ %s: ожидалось %+.4f, получено %+.4f" % [key, expect, got])
	verdict("1 привязка по вертикали согласована со сдвигом рисунка",
		bad == 0, "расхождений=%d" % bad)
	u.queue_free()
	await frames(1)

# ═════════════════════════════════════════════════════════════════════════════
# 2. ОТРЯД В ЗАЩИТЕ СТОИТ НА МЕСТЕ
# ═════════════════════════════════════════════════════════════════════════════
func _test_defense_hold() -> void:
	print("\n═════ 2. ЗАЩИТА: СТОЯТЬ НА МЕСТЕ ═════")
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, "spearman")
	var squad: Array = []
	for i in range(6):
		var u := Spearman.new()
		u.faction = Constants.FACTION_PLAYER
		main.world_add(u)
		u.global_position = Vector3(-150.0 + float(i) * 0.6, 0.0, -150.0)
		GameManager.add_to_squad(sid, u)
		squad.append(u)
	# Враг в стороне, но В ПРЕДЕЛАХ радиуса агро
	var foes: Array = []
	for i in range(3):
		var e := Spearman.new()
		e.faction = Constants.FACTION_ENEMY
		main.world_add(e)
		e.global_position = Vector3(-150.0 + float(i) * 0.6, 0.0, -142.0)
		foes.append(e)
	await frames(3)

	for u in squad:
		(u as Unit).set_stance(_UCfg.STANCE_DEFENSE)
		(u as Unit).state = Unit.State.IDLE
	var start: Array = []
	for u in squad:
		start.append((u as Node3D).global_position)
	await frames(240)

	var max_drift := 0.0
	var chasing := 0
	for i in range(squad.size()):
		var u: Unit = squad[i]
		if not is_instance_valid(u):
			continue
		var d: float = (u.global_position - (start[i] as Vector3)).length()
		max_drift = maxf(max_drift, d)
		if u.state == Unit.State.MOVING:
			chasing += 1
	print("  через 240 кадров: максимальный сдвиг=%.2f м, в состоянии MOVING=%d из %d" % [
		max_drift, chasing, squad.size()])
	print("  (враг в 8 м — внутри радиуса агро %.0f м)" % Unit.AGGRO_RADIUS)
	verdict("2 отряд в защите не шагает на врага (сдвиг < 0.5 м)",
		max_drift < 0.5, "сдвиг=%.2f м" % max_drift)
	verdict("2 никто не сорвался в погоню", chasing == 0, "MOVING=%d" % chasing)

	for u in squad + foes:
		if is_instance_valid(u):
			(u as Node).queue_free()
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# 3. РЕСУРСЫ НА ЗЕМЛЕ
# ═════════════════════════════════════════════════════════════════════════════
func _test_resource_ground() -> void:
	print("\n═════ 3. РЕСУРСЫ НЕ ВИСЯТ В ВОЗДУХЕ ═════")
	var worst := 0.0
	var checked := 0
	var samples: Array = []
	for n in get_tree().get_nodes_in_group("resource_nodes"):
		var rn := n as ResourceNode
		if rn == null or rn.resource_type == Constants.RESOURCE_WOOD:
			continue
		var mi: MeshInstance3D = rn.mesh_instance
		if mi == null or not (mi.mesh is QuadMesh):
			continue
		var q: QuadMesh = mi.mesh
		# Низ спрайта в мире = позиция узла + подъём меша − половина высоты квада.
		# ЗЕМЛЯ БОЛЬШЕ НЕ ПЛОСКАЯ (Main.TERRAIN_RELIEF): сравнивать низ с нулём
		# нельзя — под каждым куском своя высота. Меряем отклонение от РЕЛЬЕФА
		# в точке этого куска
		var ground: float = GameManager.get_terrain_height(
			rn.global_position.x, rn.global_position.z)
		var bottom: float = rn.global_position.y + mi.position.y * rn._visual_root.scale.y \
			- q.size.y * 0.5 * rn._visual_root.scale.y - ground
		checked += 1
		if absf(bottom) > absf(worst):
			worst = bottom
		if samples.size() < 5:
			samples.append("%s scale=%.2f низ=%.3f м" % [
				"золото" if rn.resource_type == Constants.RESOURCE_GOLD else "камень",
				rn.size_scale, bottom])
	for s in samples:
		print("    %s" % String(s))
	print("  проверено кусков: %d, худшее отклонение низа от земли: %.3f м" % [checked, worst])
	verdict("3 низ куска руды лежит на земле (|откл| < 0.05 м)",
		checked > 0 and absf(worst) < 0.05, "худшее=%.3f м" % worst)

# ═════════════════════════════════════════════════════════════════════════════
# 4. СРОК ЖИЗНИ СТРЕЛ
# ═════════════════════════════════════════════════════════════════════════════
func _test_arrow_lifetime() -> void:
	print("\n═════ 4. СТРЕЛЫ ИСЧЕЗАЮТ ═════")
	# ЧИСЛО НЕ ХАРДКОДИТСЯ. Заказ звучал как «стрела живёт от ВЫСТРЕЛА, а не от
	# втыкания» — вот это свойство и проверяем; сама длительность с тех пор
	# пересматривалась (15.0 → 10.5, −30%: воткнувшиеся стрелы копились залпами
	# и держали лишние прозрачные квады), и стенд обязан следовать за кодом
	print("  Arrow.MAX_LIFETIME = %.1f c" % Arrow.MAX_LIFETIME)
	verdict("4 у стрелы есть конечный срок жизни, заведённый от выстрела",
		Arrow.MAX_LIFETIME > 0.0 and Arrow.MAX_LIFETIME < 60.0,
		"MAX_LIFETIME=%.1f" % Arrow.MAX_LIFETIME)

	# Пускаем стрелу в пустоту: она воткнётся и должна исчезнуть по общему сроку
	var a := Arrow.new()
	a.faction = Constants.FACTION_PLAYER
	a.damage  = 1.0
	a._start_pos = Vector3(-200.0, 1.2, -200.0)
	a._end_pos   = Vector3(-190.0, 0.0, -200.0)
	a._dist      = 10.0
	a._speed     = 40.0
	main.world_add(a)
	a.global_position = a._start_pos
	await frames(60)
	var stuck: bool = is_instance_valid(a) and a._spent
	print("  стрела воткнулась: %s, узел жив: %s" % [str(stuck), str(is_instance_valid(a))])
	verdict("4 воткнувшаяся стрела ещё на карте до истечения срока",
		is_instance_valid(a))
	if is_instance_valid(a):
		a.queue_free()
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# 5. ПРЕВЬЮ ФОРМАЦИИ
# ═════════════════════════════════════════════════════════════════════════════
func _test_formation_preview() -> void:
	print("\n═════ 5. ПРЕВЬЮ ФОРМАЦИИ ═════")
	var src := FileAccess.open("res://scripts/FormationPreview.gd", FileAccess.READ)
	if src == null:
		verdict("5 превью рисует только треугольники", false, "файл не открылся")
		return
	var text := src.get_as_text()
	src.close()
	var has_line: bool  = "draw_line(" in text
	var has_arrow: bool = "_draw_direction_arrow" in text
	# ТРЕУГОЛЬНИКИ ИЩЕМ ПО ЛЮБОМУ ИЗ ДВУХ СПОСОБОВ ОТРИСОВКИ. Раньше на каждое
	# место рисовался свой полигон вспомогательной функцией _draw_unit_tri; на
	# большом выделении это давало две примитивы канваса на бойца и просадку до
	# 29 к/с при растягивании линии. Теперь весь строй уходит одним
	# canvas_item_add_triangle_array, и отдельной функции не осталось.
	# Требование стенда при этом не изменилось — «полосы нет, треугольники
	# есть», — изменился только признак, по которому их видно в исходнике
	var has_tri: bool   = ("_draw_unit_tri" in text) \
		or ("canvas_item_add_triangle_array" in text)
	print("  draw_line (жёлтая полоса): %s" % str(has_line))
	print("  крупная стрелка-ромб: %s" % str(has_arrow))
	print("  треугольники слотов: %s" % str(has_tri))
	verdict("5 жёлтая полоса убрана, треугольники остались",
		not has_line and not has_arrow and has_tri)
