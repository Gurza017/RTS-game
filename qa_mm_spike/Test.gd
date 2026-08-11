extends Node3D

## ═══════════════════════════════════════════════════════════════════════════
## СПАЙК: ПРОВЕРКА MultiMesh В GL COMPATIBILITY БЕЗ custom_data
## ═══════════════════════════════════════════════════════════════════════════
## Godot 4.x имеет открытый, непочиненный баг (godot/godot#96503): custom_data
## у MultiMesh в рендерере GL Compatibility читается ненадёжно. План перехода
## дальних юнитов на MultiMesh рассчитан на то, чтобы обойтись БЕЗ custom_data
## вовсе — только transform (позиция + масштаб) и use_colors (тон фракции).
## Это визуальная проверка, headless её не подтвердит (--headless не рисует
## пикселей). ЗАПУСТИ ЭТУ СЦЕНУ НАПРЯМУЮ (F5 при открытом Test.tscn) и посмотри:
##
##   1. Все квады смотрят на камеру (BILLBOARD_FIXED_Y работает на MultiMesh).
##   2. Ровно половина — синеватая, половина — красноватая (use_colors=true
##      реально доходит до GPU в этом рендерере).
##   3. Каждый третий отражён по горизонтали (отрицательный масштаб X в
##      transform пережил доворот к камере — так дальние юниты будут
##      смотреть влево/вправо без custom_data).
##
## Если тон/зеркало не видны или все квады белые — use_colors в этом билде
## ненадёжен так же, как custom_data, и придётся вернуться к варианту
## "своя текстура на фракцию" (см. план, шаг 1, план Б).

const COLS := 10
const ROWS := 6
const SPACING := 2.0

const _Billboard := preload("res://scripts/BillboardUtil.gd")

func _ready() -> void:
	# Lancer_Idle.png — ЛЕНТА кадров (3840×320, ~12×320), не один спрайт.
	# Вырезаем ПЕРВЫЙ кадр в AtlasTexture — ровно так, как реальный дальний
	# юнит получит свой "канонический" кадр из уже загруженного листа
	var sheet: Texture2D = load("res://assets/factions/humans/units/spearman/Lancer_Idle.png")
	var fc: int = _Billboard.frame_count(sheet)
	var fw: float = sheet.get_size().x / float(fc)
	var tex := AtlasTexture.new()
	tex.atlas = sheet
	tex.region = Rect2(0.0, 0.0, fw, sheet.get_size().y)

	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0 * sheet.get_size().y / fw)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = tex
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = mat

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = COLS * ROWS

	var i := 0
	for row in range(ROWS):
		for col in range(COLS):
			var pos := Vector3((col - COLS * 0.5) * SPACING, 0.7, (row - ROWS * 0.5) * SPACING)
			var basis := Basis()
			if i % 3 == 0:
				basis = basis.scaled(Vector3(-1.0, 1.0, 1.0))   # зеркало без custom_data
			mm.set_instance_transform(i, Transform3D(basis, pos))
			var tint: Color = Color(0.35, 0.55, 1.0) if (col + row) % 2 == 0 else Color(1.0, 0.4, 0.35)
			mm.set_instance_color(i, tint)
			i += 1

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)

	var cam := Camera3D.new()
	cam.position = Vector3(0, 9, 14)
	add_child(cam)
	cam.look_at(Vector3.ZERO, Vector3.UP)
	cam.current = true

	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.15, 0.15, 0.18)
	env_node.environment = env
	add_child(env_node)

	print("MultiMesh-спайк: %d билбордов, use_colors=true, custom_data НЕ используется." % mm.instance_count)
	print("Смотри глазами (F5): чередование синий/красный тон + каждый третий зеркально отражён.")
