extends MeshInstance3D
## ЗВЁЗДОЧКА ВЕТЕРАНА над отрядом.
##
## Маленькая ярко-жёлтая пятиконечная звезда, висящая над головой командира
## отряда. Готовой картинки под неё в ассет-паке нет, поэтому геометрия
## строится процедурно — как и остальные вспомогательные меши проекта.
##
## Узел цепляется ДОЧЕРНИМ к бойцу-носителю: тогда он ездит вместе с ним сам,
## без единой строчки в _process. Носитель погиб — GameManager перевешивает
## звезду на следующего живого (см. _refresh_star).
##
## Файл намеренно без class_name: подключается через preload.

const _UCfg := preload("res://scripts/unit_stats_config.gd")

## Высота над центром юнита, метры
const STAR_HEIGHT := 2.35
## Внешний радиус звезды, метры.
## УВЕЛИЧЕН РОВНО ВДВОЕ (0.098 → 0.196) по заказу владельца. Прежний размер
## подбирался под звезду, висевшую над головой ОДНОГО бойца-командира, — там
## она и должна была быть мелкой, чтобы не закрывать его. Теперь звезда стоит
## над центром масс всего отряда (см. GameManager.refresh_star), то есть
## заметно дальше от глаза при том же зуме, и мелкая просто терялась в строю
const STAR_RADIUS := 0.196
## Отношение внутреннего радиуса к внешнему: чем меньше, тем острее лучи
const INNER_RATIO := 0.45

## Просвет между соседними звёздами ряда. Считается от радиуса, а не задан
## числом: у красной звезды радиус больше (VET_TIER_SCALE), и фиксированный
## шаг заставил бы её лучи налезать на соседей
const SPACING_RATIO := 2.43

static func create(level: int) -> MeshInstance3D:
	var root := MeshInstance3D.new()
	root.set_script(load("res://scripts/VeterancyStar.gd"))
	root.name = "VeterancyStar"
	root.build(level)
	return root

## Уровень, под который сейчас построен ряд звёзд. По нему GameManager видит,
## что отряд подрос, и перестраивает мех, не создавая узел заново
var shown_level: int = 0

## ГРЕЙД, ПОД КОТОРЫЙ ПОСТРОЕН РЯД. Число звёзд и цвет берутся не из уровня
## напрямую, а из таблицы конфига (VET_STAR_TIERS): уровень 4 — это ОДНА
## серебряная звезда, а не четыре бронзовых
func build(level: int) -> void:
	shown_level = maxi(level, 1)
	var tier: Dictionary = _UCfg.veteran_star_tier(shown_level)
	if tier.is_empty():
		mesh = null
		return
	mesh = _make_star_row(int(tier["count"]),
		tier["color"] as Color, float(tier["scale"]))
	position.y = STAR_HEIGHT
	# Поверх спрайтов: звезда не должна тонуть в фигуре бойца
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## Ряд из n звёзд одного грейда, центрированный по X
func _make_star_row(n: int, col: Color, scale_mul: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r: float = STAR_RADIUS * scale_mul
	var step: float = r * SPACING_RATIO
	for i in range(n):
		var dx: float = (float(i) - float(n - 1) * 0.5) * step
		_add_star(st, dx, r, col)
	st.generate_normals()
	var m: ArrayMesh = st.commit()
	m.surface_set_material(0, _make_material(col))
	return m

## Одна пятиконечная звезда: 10 внешних/внутренних вершин веером от центра
func _add_star(st: SurfaceTool, dx: float, r: float, col: Color) -> void:
	var points: Array = []
	for i in range(10):
		var ang: float = -PI * 0.5 + TAU * float(i) / 10.0
		var rr: float = r if i % 2 == 0 else r * INNER_RATIO
		points.append(Vector3(dx + cos(ang) * rr, sin(ang) * rr, 0.0))
	var center := Vector3(dx, 0.0, 0.0)
	for i in range(10):
		var a: Vector3 = points[i]
		var b: Vector3 = points[(i + 1) % 10]
		st.set_color(col)
		st.add_vertex(center)
		st.set_color(col)
		st.add_vertex(a)
		st.set_color(col)
		st.add_vertex(b)

func _make_material(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color            = col
	m.vertex_color_use_as_albedo = true
	m.shading_mode            = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode          = BaseMaterial3D.BILLBOARD_ENABLED
	m.cull_mode               = BaseMaterial3D.CULL_DISABLED
	# Звезда — индикатор, а не часть мира: её видно поверх любых спрайтов
	m.no_depth_test           = true
	m.render_priority         = 8
	return m
