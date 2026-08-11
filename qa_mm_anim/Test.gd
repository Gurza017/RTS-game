extends Node

## ═══════════════════════════════════════════════════════════════════════════
## ВИЗУАЛЬНЫЙ СПАЙК: АНИМАЦИЯ В MultiMesh БЕЗ custom_data
## ═══════════════════════════════════════════════════════════════════════════
## ЗАПУСКАТЬ БЕЗ --headless И СМОТРЕТЬ ГЛАЗАМИ. Headless не рисует ни пикселя,
## а проверяется здесь именно картинка: заработает ли покадровая анимация и
## зеркало спрайта, если гнать их через use_colors (см. shaders/mm_unit_sprite).
## Тот же приём, что и с qa_mm_spike, — проверить нельзя иначе.
##
## На экране ДВА РЯДА одних и тех же копейщиков:
##   ВЕРХНИЙ  (дальше от камеры) — обычные Sprite3D, как в игре сейчас;
##   НИЖНИЙ   (ближе к камере)   — те же кадры через общий MultiMesh.
## Они обязаны шагать ОДИНАКОВО. Слева половина каждого ряда развёрнута
## зеркально — проверка канала g.
##
## ЧТО СЧИТАТЬ УСПЕХОМ:
##   • нижний ряд анимирован (а не замер на первом кадре);
##   • нижний ряд шагает в ногу с верхним;
##   • левые половины рядов смотрят в другую сторону, чем правые;
##   • спрайты не «завалены» и не растянуты.
## ЧТО СЧИТАТЬ ПРОВАЛОМ: нижний ряд статичен, мигает, или все бойцы показывают
## один и тот же кадр — значит instance-цвет в GL Compatibility не доезжает и
## анимацию придётся делать иначе (бакет на кадр).

const SHEET := "res://assets/factions/humans/units/spearman/Lancer_Run.png"
const ROW    := 14        # бойцов в ряду
const PIXEL_SIZE := 0.0108
const FPS := 10.0

var _mm: MultiMesh = null
var _sprites: Array = []
var _frames: int = 1
var _t: float = 0.0

func _ready() -> void:
	var tex := _load(SHEET)
	if tex == null:
		print("НЕ НАЙДЕН ЛИСТ: %s" % SHEET)
		get_tree().quit(1)
		return
	var sz := tex.get_size()
	# Кадры квадратные: ширина ленты / высота = сколько их (SpriteSheetParser)
	_frames = maxi(1, int(round(sz.x / maxf(sz.y, 1.0))))
	print("лист %s: %d×%d, кадров %d" % [SHEET.get_file(), int(sz.x), int(sz.y), _frames])

	_setup_world()
	_build_reference_row(tex)
	_build_multimesh_row(tex)
	_build_hud()
	# РЕЖИМ СНИМКОВ: картинку надо не только показать человеку, но и уметь
	# посмотреть без него. С `-- --shots` стенд сам проходит по кадрам ленты,
	# сохраняет по PNG на каждый и выходит — эти файлы уже можно разглядывать
	for a in OS.get_cmdline_user_args():
		if a == "--shots":
			call_deferred("_shoot_series")
			return

## По снимку на каждый кадр ленты: если MultiMesh-ряд анимируется, кадры будут
## отличаться между собой И совпадать с верхним рядом
func _shoot_series() -> void:
	var dir: String = "res://qa_mm_anim/shots"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	set_process(false)          # кадр выставляем вручную, а не по времени
	await get_tree().process_frame
	for f in range(_frames):
		for s in _sprites:
			(s as Sprite3D).frame = f
		for i in range(ROW):
			_mm.set_instance_color(i, Color(float(f) / 255.0,
				1.0 if i < ROW / 2 else 0.0, 0.0, 1.0))
		# Два кадра ожидания: первый применяет изменения, второй гарантирует,
		# что нарисовано именно новое состояние
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img: Image = get_viewport().get_texture().get_image()
		var path: String = "%s/frame_%d.png" % [dir, f]
		img.save_png(path)
		print("снимок кадра %d → %s" % [f, ProjectSettings.globalize_path(path)])
	print("=== MM ANIM SHOTS DONE ===")
	get_tree().quit()

## Свет не нужен (шейдер unshaded), нужна камера и фон
func _setup_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.16, 0.18, 0.22)
	env.environment = e
	add_child(env)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 9.0
	cam.position = Vector3(0.0, 3.2, 7.0)
	cam.rotation_degrees = Vector3(-18.0, 0.0, 0.0)
	add_child(cam)

func _frame_w(tex: Texture2D) -> float:
	return tex.get_size().x / float(_frames)

## ВЕРХНИЙ РЯД — как в игре сейчас: отдельный Sprite3D на бойца
func _build_reference_row(tex: Texture2D) -> void:
	for i in range(ROW):
		var s := Sprite3D.new()
		s.texture   = tex
		s.hframes   = _frames
		s.frame     = 0
		s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		s.alpha_scissor_threshold = 0.15
		s.pixel_size = PIXEL_SIZE
		s.flip_h = i < ROW / 2       # левая половина — зеркально
		s.position = Vector3(-6.0 + float(i) * 0.92, 1.6, -1.6)
		add_child(s)
		_sprites.append(s)

## НИЖНИЙ РЯД — те же бойцы одним MultiMesh
func _build_multimesh_row(tex: Texture2D) -> void:
	var fw := _frame_w(tex)
	var quad := QuadMesh.new()
	# Размер квада — ровно как у Sprite3D с этим pixel_size: кадр в пикселях
	# умножается на pixel_size. Иначе ряды нельзя сравнивать
	quad.size = Vector2(fw * PIXEL_SIZE, tex.get_size().y * PIXEL_SIZE)

	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/mm_unit_sprite.gdshader")
	mat.set_shader_parameter("albedo_tex", tex)
	mat.set_shader_parameter("frame_count", float(_frames))
	mat.set_shader_parameter("alpha_scissor", 0.15)
	quad.material = mat

	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = quad
	_mm.instance_count = ROW

	for i in range(ROW):
		# Квад QuadMesh центрирован, у Sprite3D центр тоже в середине —
		# ставим на ту же высоту, чтобы ряды были сравнимы
		_mm.set_instance_transform(i, Transform3D(Basis(),
			Vector3(-6.0 + float(i) * 0.92, 0.55, 0.6)))
		_mm.set_instance_color(i, Color(0.0, 1.0 if i < ROW / 2 else 0.0, 0.0, 1.0))

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	add_child(mmi)

func _build_hud() -> void:
	var lbl := Label.new()
	lbl.text = "ВЕРХНИЙ ряд — обычные Sprite3D (как в игре).\nНИЖНИЙ ряд — общий MultiMesh + шейдер.\n\nДолжны шагать ОДИНАКОВО; левые половины — зеркально.\nESC — выход."
	lbl.position = Vector2(16, 12)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	var ui := CanvasLayer.new()
	ui.add_child(lbl)
	add_child(ui)

func _process(delta: float) -> void:
	_t += delta
	var f: int = int(_t * FPS) % _frames
	for s in _sprites:
		(s as Sprite3D).frame = f
	if _mm != null:
		for i in range(ROW):
			# Кадр едет в канале r как frame/255 (см. шапку шейдера)
			_mm.set_instance_color(i, Color(float(f) / 255.0,
				1.0 if i < ROW / 2 else 0.0, 0.0, 1.0))

func _input(e: InputEvent) -> void:
	if e is InputEventKey and (e as InputEventKey).pressed \
			and (e as InputEventKey).keycode == KEY_ESCAPE:
		get_tree().quit()

func _load(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var t := load(path) as Texture2D
		if t != null:
			return t
	var img := Image.new()
	if img.load(ProjectSettings.globalize_path(path)) == OK:
		return ImageTexture.create_from_image(img)
	return null
