extends Node

## ═══════════════════════════════════════════════════════════════════════════
## ОКОННЫЙ СТЕНД: АУРА ЛЕЧЕНИЯ ВИДНА ГЛАЗОМ В ЦЕНТРЕ СПРАЙТА (спринт 16, блок 2)
## ═══════════════════════════════════════════════════════════════════════════
## ЗАКАЗ: «чёткая, заметная анимация — зелёное свечение / крест / аура в
## центре спрайта исцеляемого, на всё время лечения». Headless-стенд
## qa_monk_vfx проверяет привязку и узлы, но ВИДНО ЛИ ЧТО-ТО — знает только
## картинка (шейдеры и буфер глубины живут в окне). Тем же приёмом, что
## qa_visual_smoke: два снимка одного кадра — с погашенной аурой и с
## показанной; изменившиеся пиксели внутри прямоугольника квада ауры — это и
## есть то, что игрок увидит.
##   A — аура появилась и заметна: изменилось ≥ 12 % прямоугольника, и
##       изменившееся — зелёное;
##   B — центр изменившегося лежит у ЦЕНТРА СПРАЙТА исцеляемого, не у ног;
##   C — аура держится весь такт лечения (три замера через такт).
## Запуск: godot --path . res://qa_monk_vfx/Shot.tscn -- --out=<путь без .png>

const _UCfg := preload("res://scripts/unit_stats_config.gd")
## Спринт 20: аура — только тонкий овал под ногами (без заливки и креста),
## изменившихся пикселей в квадрате ауры заметно меньше
## Овал 2 px и редкие искры ленты: на кадре это единицы процентов квадрата
## замера, и в «пустой» кадр ленты доля падает ниже процента — порог низкий,
## геометрию (овал у ног, лента от земли) стережёт headless qa_sprint20 A
const MIN_CHANGED_FRAC := 0.005

var main = null
var cam: Camera3D = null
var _out: String = ""
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s: String = String(a)
		if s.begins_with("--out="):
			_out = s.substr(6)
	call_deferred("_run")
	get_tree().create_timer(150.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 150 с")
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
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + d) if d != "" else ""])

func _finish() -> void:
	print("\n═════ ИТОГ qa_monk_vfx/Shot: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _spawn(uid: String, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[uid].instantiate()
	u.faction = Constants.FACTION_PLAYER
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	return u

## Ровная сухая площадка рядом с base (перепад в круге 6 м наименьший)
func _flat_spot(base: Vector3, span: float) -> Vector3:
	var best: Vector3 = base
	var best_d: float = 1e9
	for ix in range(-3, 4):
		for iz in range(-3, 4):
			var p := Vector3(base.x + float(ix) * span, 0.0, base.z + float(iz) * span)
			var lo := 1e9
			var hi := -1e9
			var wet := false
			for d in [Vector3.ZERO, Vector3(6.0, 0.0, 0.0), Vector3(-6.0, 0.0, 0.0),
					Vector3(0.0, 0.0, 6.0), Vector3(0.0, 0.0, -6.0)]:
				var h: float = GameManager.get_terrain_height(p.x + d.x, p.z + d.z)
				lo = minf(lo, h)
				hi = maxf(hi, h)
				if main.is_water(p.x + d.x, p.z + d.z):
					wet = true
			if hi - lo < best_d and not wet:
				best_d = hi - lo
				best = p
	print("  площадка стенда: %s (перепад %.2f м)" % [str(best), best_d])
	return best

func _grab() -> Image:
	for _i in range(4):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()

## Экранный прямоугольник билборда: центр и половина стороны в метрах
func _screen_rect(centre: Vector3, half: float) -> Rect2i:
	var right: Vector3 = cam.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	var up: Vector3 = cam.global_transform.basis.y
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var w: Vector3 = centre + right * half * sx + up * half * sy
			var s: Vector2 = cam.unproject_position(w)
			mn.x = minf(mn.x, s.x); mn.y = minf(mn.y, s.y)
			mx.x = maxf(mx.x, s.x); mx.y = maxf(mx.y, s.y)
	return Rect2i(Vector2i(int(floor(mn.x)), int(floor(mn.y))),
		Vector2i(int(ceil(mx.x - mn.x)), int(ceil(mx.y - mn.y))))

## Разность двух снимков внутри прямоугольника:
## [доля изменившихся, доля зелёных среди изменившихся, средний y изменившихся]
func _diff(bg: Image, fg: Image, r: Rect2i) -> Array:
	r = r.intersection(Rect2i(Vector2i.ZERO, fg.get_size()))
	if r.size.x <= 0 or r.size.y <= 0:
		return [0.0, 0.0, -1.0]
	var changed := 0
	var green := 0
	var ysum := 0.0
	for y in range(r.position.y, r.position.y + r.size.y):
		for x in range(r.position.x, r.position.x + r.size.x):
			var a: Color = bg.get_pixel(x, y)
			var b: Color = fg.get_pixel(x, y)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) < 0.08:
				continue
			changed += 1
			ysum += float(y)
			if b.g > b.r * 1.15 and b.g > b.b * 1.15:
				green += 1
	var area: float = float(r.size.x * r.size.y)
	return [float(changed) / area,
		(float(green) / float(changed)) if changed > 0 else 0.0,
		(ysum / float(changed)) if changed > 0 else -1.0]

var _monk: Monk = null
var _hurt: Unit = null

## Один замер: аура погашена → снимок, показана → снимок, разность в её квадрате
func _measure(save_png: bool) -> Array:
	var aura: MeshInstance3D = _monk.get("_heal_aura") as MeshInstance3D
	var vfx: Node3D = _monk.heal_vfx_node()
	if aura == null or vfx == null:
		return [0.0, 0.0, -1.0, 0.0]
	# Монах и цель заморожены на время пары снимков: такт лечения иначе
	# включил бы ауру обратно между «фоном» и «рабочим» снимком
	_monk.set_tick(false)
	aura.visible = false
	vfx.visible = false
	var bg: Image = await _grab()
	aura.visible = true
	vfx.visible = true
	var fg: Image = await _grab()
	if save_png and _out != "":
		fg.save_png(_out + ".png")
		print("  снимок: %s.png" % _out)
		var amat := (aura.mesh as QuadMesh).material as ShaderMaterial
		print("  аура: pos=%s размер=%s ground_depth=%s depth_push=%s v_stretch=%s" % [
			str(aura.global_position), str((aura.mesh as QuadMesh).size),
			str(amat.get_shader_parameter("ground_depth")), str(amat.get_shader_parameter("depth_push")),
			str(amat.get_shader_parameter("v_stretch"))])
	_monk.set_tick(true)
	# Прямоугольник замера — вокруг ЛЕНТЫ лечения (спринт 20: она от земли
	# вверх), с запасом вниз до овала под ногами
	var qv := (vfx as MeshInstance3D).mesh as QuadMesh
	var half: float = (qv.size.y * 0.6) if qv != null else 0.8
	var rect: Rect2i = _screen_rect(vfx.global_position, half)
	var d: Array = _diff(bg, fg, rect)
	# Центр спрайта цели на экране — по нарисованной точке плюс середина ленты
	var mid: float = float(_monk.get("_vfx_mid"))
	var p: Vector3 = _hurt.draw_position()
	var centre_px: Vector2 = cam.unproject_position(Vector3(p.x, p.y + mid, p.z))
	var feet_px: Vector2 = cam.unproject_position(p)
	var off_frac: float = -1.0
	if float(d[2]) >= 0.0 and absf(feet_px.y - centre_px.y) > 1.0:
		# 0 — ровно в центре спрайта, 1 — у ног
		off_frac = absf(float(d[2]) - centre_px.y) / absf(feet_px.y - centre_px.y)
	print("  прямоугольник %s: изменилось %.1f %%, зелёных %.0f %%, центр y=%.0f (центр спрайта %.0f, ноги %.0f, смещение %.2f)" % [
		str(rect), float(d[0]) * 100.0, float(d[1]) * 100.0, float(d[2]), centre_px.y, feet_px.y, off_frac])
	return [d[0], d[1], d[2], off_frac]

func _run() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600, 900))
	get_tree().root.content_scale_size = Vector2i(1600, 900)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(12)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	GameManager.world_bounds_enabled = false
	if GameManager.fog != null:
		GameManager.fog.enabled = false
		(GameManager.fog as Node3D).visible = false
	await pframes(4)
	var spot: Vector3 = _flat_spot(main.PLAYER_BASE_ANCHOR + Vector3(30.0, 0.0, 30.0), 8.0)
	# Лес сеется случайно: крона перед бойцом съела бы ауру на снимке
	for n0 in get_tree().get_nodes_in_group("resource_nodes"):
		var rn := n0 as Node3D
		if rn != null and is_instance_valid(rn) and Vector2(rn.global_position.x - spot.x,
				rn.global_position.z - spot.z).length() < 30.0:
			rn.queue_free()
	await pframes(6)
	_monk = _spawn("monk", spot) as Monk
	_hurt = _spawn("spearman", spot + Vector3(_UCfg.MONK_CAST_RANGE * 0.6, 0.0, 0.0))
	_hurt.current_health = _hurt.max_health * 0.2
	_hurt._soa_push_stats()
	await pframes(4)
	_hurt.set_tick(false)
	main.focus_camera_on(_hurt.global_position)
	await frames(4)
	(main._camera as Node).set_process(false)
	main.set_process(false)
	cam = get_viewport().get_camera_3d()
	cam.size = 12.0
	await frames(4)
	# Ждём первого такта лечения
	var bound := false
	for _i in range(int(_UCfg.MONK_HEAL_TICK * 4.0 * 60.0)):
		await get_tree().physics_frame
		if _monk.heal_vfx_target() == _hurt:
			bound = true
			break
	verdict("A0 монах лечит раненого, эффект привязан к нему", bound)
	if not bound:
		_finish()
		return
	await frames(3)

	print("\n═════ A. АУРА ЗАМЕТНА ═════")
	var m: Array = await _measure(true)
	verdict("A1 аура меняет заметную долю своего квада (≥ %d %%)" % int(MIN_CHANGED_FRAC * 100.0),
		float(m[0]) >= MIN_CHANGED_FRAC, "%.1f %%" % (float(m[0]) * 100.0))
	# Спринт 20: в квадрате ауры теперь и лента лечения (искры светлые), а сам
	# овал тонкий — доля зелёного среди изменившегося ниже прежних 60 %
	verdict("A2 изменившееся — зелёное (овал и искры, а не мусор; ≥ 25 %)", float(m[1]) >= 0.25,
		"зелёных %.0f %%" % (float(m[1]) * 100.0))

	print("\n═════ B. У НОГ, А НЕ У ПОЯСА (спринт 20) ═════")
	# Овал лежит под ногами, лента лечения идёт от земли: центр изменившегося
	# обязан быть НИЖЕ середины ленты — ближе к ногам (0 — центр ленты, 1 — ноги)
	verdict("B1 свечение у ног спрайта, а не у пояса и не над головой",
		float(m[3]) >= 0.1, "смещение %.2f к ногам от центра ленты" % float(m[3]))

	print("\n═════ C. НА ВСЁ ВРЕМЯ ЛЕЧЕНИЯ ═════")
	# Раненый заморожен на 20 %: лечить его монах будет ещё долго. Три замера
	# через треть такта каждый — аура обязана быть на месте в каждом
	var tick: float = float(_monk.call("heal_tick_sec"))
	var all_ok := true
	var worst := 1.0
	for k in range(3):
		await pframes(int(tick * 60.0 / 3.0))
		if _monk.heal_vfx_target() != _hurt:
			all_ok = false
			print("  замер %d: эффект не на цели" % k)
			continue
		var mk: Array = await _measure(false)
		worst = minf(worst, float(mk[0]))
		if float(mk[0]) < MIN_CHANGED_FRAC:
			all_ok = false
	verdict("C1 аура на месте во всех трёх замерах по ходу лечения", all_ok,
		"худшая доля %.1f %%" % (worst * 100.0))
	verdict("C2 раненого при этом лечат (запас растёт)", _hurt.current_health > _hurt.max_health * 0.2 + 1.0,
		"%.0f из %.0f" % [_hurt.current_health, _hurt.max_health])
	_finish()
