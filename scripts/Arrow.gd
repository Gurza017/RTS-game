extends Node3D
class_name Arrow

## ФИЗИЧЕСКИЙ СНАРЯД. Урон НЕ наносится в момент выстрела — стрела летит по
## баллистической дуге и списывает урон СТРОГО при касании юнита (Area3D →
## body_entered). Промахнувшаяся стрела втыкается в землю НАКОНЕЧНИКОМ.
##
## НАКЛОН ПО ВЕКТОРУ СКОРОСТИ. Каждый кадр ось стрелы выставляется ровно по
## производной параболы: на взлёте остриё смотрит вверх, в вершине дуги —
## горизонтально, на нисходящей ветви — вниз к цели. Разворот делает шейдер
## axis_billboard (квад лежит вдоль оси и крутится ВОКРУГ НЕЁ лицом к камере),
## поэтому наклон виден с любого ракурса и стрела не исчезает «с ребра».
##
## Прицеливание с УПРЕЖДЕНИЕМ и разбросом считает стрелок (см. Archer.gd):
## сюда приходит уже готовая точка попадания.

const _AXIS_SHADER := preload("res://shaders/axis_billboard.gdshader")

var _start_pos:  Vector3 = Vector3.ZERO
var _end_pos:    Vector3 = Vector3.ZERO
var _speed:      float   = 9.0    # замедлена — дуга читается глазом
var _progress:   float   = 0.0
var _dist:       float   = 0.0

# Доля дальности, уходящая в высоту дуги (задаёт Archer из unit_stats_config.gd)
var _arc_factor: float = 0.5
var _arc_height: float = 3.0

# ── Боевые параметры (задаёт стрелок перед add_child) ────────────────────────
var damage:  float   = 0.0
var shooter: Node3D  = null
var faction: int     = -1          # чьей фракции стрела: своих не задевает

# Радиус «наконечника»: попадание засчитывается при входе в этот объём
const HIT_RADIUS := 0.35
# ЖЁСТКИЙ СРОК ЖИЗНИ СТРЕЛЫ, секунды ОТ ВЫСТРЕЛА.
# Раньше отсчёт начинался только в момент втыкания, поэтому стрела, зависшая
# по любой причине в полёте, не удалялась вовсе. Теперь таймер заводится в
# _ready() и снимает со сцены ЛЮБУЮ стрелу — и летящую, и торчащую в земле.
# 10.5 вместо прежних 15.0 (−30%): полёт занимает около секунды, так что срок
# торчания в грунте падает с ~14 с до ~9.5 с. Воткнувшиеся стрелы копились на
# поле залпами по 10 штук и держали лишние квады с прозрачностью
const MAX_LIFETIME := 10.5
# Длина стрелы в метрах. Задаётся ЯВНО, а не из пикселей: сама картинка
# 64x64 почти пустая (полезная область 43x12), и вывод длины из размера листа
# давал квадрат 0.69x0.69 с крошечной стрелой посередине
const ARROW_LENGTH := 0.75
# Какая доля длины стрелы ТОРЧИТ над землёй после промаха (остальное в грунте)
const STUCK_EXPOSED := 2.0 / 3.0
# Минимальный наклон ВНИЗ при втыкании: почти горизонтальная стрела легла бы
# на грунт плашмя вместо того, чтобы воткнуться
const STUCK_MIN_DOWN := 0.35

# Пропорции полезной части картинки (ширина/высота), считаются при обрезке
var _arrow_aspect: float = 43.0 / 12.0

var _area: Area3D = null
var _spent: bool  = false          # уже попала/воткнулась — больше не летит

const _ARROW_PATHS := [
	"res://assets/factions/humans/units/archer/Arrow-Sheet.png",
	"res://assets/sprites/units/Arrow.png",
]

func _ready() -> void:
	_arc_height = _dist * _arc_factor
	_build_visual()
	_build_hitbox()
	# Ось выставляем СРАЗУ: первый кадр полёта уже с правильным наклоном
	_apply_axis(_velocity_dir(0.0))
	# Срок жизни отсчитывается ОТ ВЫСТРЕЛА и покрывает все состояния стрелы.
	# Узел освобождается вместе со всеми потрохами (Area3D, спрайт наконечника),
	# так что «зависших» стрел на карте не остаётся в принципе.
	# Если стрела погибнет раньше (попадание), Godot снимет эту связь сам
	get_tree().create_timer(MAX_LIFETIME).timeout.connect(queue_free)

# ─────────────────────────────────────────────────────────────────────────────
# ПОПАДАНИЕ СЧИТАЕТСЯ ГЕОМЕТРИЕЙ, А НЕ ФИЗИКОЙ
#
# Здесь была Area3D с маской LAYER_UNITS и сигналом body_entered. Она перестала
# срабатывать, когда бойцы перестали быть физическими телами (см. шапку
# Unit.gd): ловить стало нечего, стрелы пролетали сквозь строй насквозь, и
# лучники не наносили урона вовсе.
#
# Возвращать телá ради этого нельзя — они стоили 5.7 мкс на бойца в кадр, ради
# чего всё и затевалось. Проверка перенесена на ту же пространственную сетку,
# по которой в проекте уже считаются и чужой строй, и поиск цели: на каждом
# шаге полёта смотрим, нет ли в HIT_RADIUS от наконечника живого чужого.
# Стрел в воздухе единицы, радиус меньше метра — это один-два просмотра ячейки.
func _build_hitbox() -> void:
	pass

## Оставлено для совместимости с местами, где стрела «снимается с физики»
## (втыкание в грунт): физики у неё больше нет вовсе
func _disable_physics() -> void:
	_area = null

## Проверка попадания на текущем шаге полёта. Зовётся из движения стрелы
func _check_hit() -> void:
	if _spent:
		return
	var hit: Unit = null
	for n in GameManager.unit_grid.query_radius(global_position, HIT_RADIUS):
		# Сетка может отдать УЖЕ ОСВОБОЖДЁННЫЙ узел (боец умер в этом же кадре,
		# запись из ячейки ещё не вычищена). Обращение к его полям — та самая
		# ошибка «previously freed», поэтому валидность проверяем ДО чтения faction
		if n == null or not is_instance_valid(n):
			continue
		var u := n as Unit
		if u == null or u == shooter:
			continue
		if u.faction == faction or u.is_dead():
			continue
		hit = u
		break
	if hit != null:
		_strike(hit)

func _strike(u: Unit) -> void:
	if _spent:
		return
	# Цель могла погибнуть между выбором в _check_hit и этим вызовом (или прийти
	# из внешнего кода). take_damage на освобождённом объекте — краш «Invalid
	# type in function 'take_damage' in base ... (previously freed)». Проверяем
	# ОБА признака смерти узла: is_instance_valid ловит уже освобождённый объект,
	# is_queued_for_deletion — тот, что жив этот кадр, но уже помечен на удаление
	# (queue_free вызван, но объект ещё не снят с дерева)
	if not is_instance_valid(u) or u.is_queued_for_deletion():
		_spent = true
		queue_free()
		return
	_spent = true
	set_process(false)
	set_physics_process(false)
	_disable_physics()
	# Стрелок мог погибнуть, пока стрела летела: передавать освобождённый
	# объект в take_damage нельзя — движок ругается на «previously freed»
	# и ответная агрессия жертвы уходит в никуда
	var valid_shooter: Node = null
	if is_instance_valid(shooter) and not shooter.is_queued_for_deletion():
		valid_shooter = shooter
	# ПОПАДАНИЕ В ЖИВОГО — глухой удар в тело. Звучит В ТОЧКЕ ЦЕЛИ, а не у
	# стрелка: залп с 20 м должен приходить оттуда, куда он прилетел
	AudioManager.play_3d("bow_impact", global_position)
	u.take_damage(damage, valid_shooter)
	queue_free()

var _visual: MeshInstance3D = null
var _mat: ShaderMaterial = null

# Квад строится ВДОЛЬ ЛОКАЛЬНОЙ ОСИ X: size = (длина, толщина). Шейдер
# axis_billboard кладёт этот +X на переданную мировую ось — то есть на вектор
# скорости. Текстура нарисована остриём ВПРАВО (замер альфы: слева оперение
# толщиной 10-12 px, справа сходящий на нет наконечник 12→2 px), поэтому
# локальный +X = направление полёта, и разворот на 180° не нужен.
func _build_visual() -> void:
	_visual  = MeshInstance3D.new()
	_visual.name = "ArrowSprite"
	var quad := QuadMesh.new()
	_mat = ShaderMaterial.new()
	_mat.shader = _AXIS_SHADER
	var tex := _load_arrow_texture()
	if tex:
		var sz := tex.get_size()
		if sz.y > 0.0:
			_arrow_aspect = sz.x / sz.y
		_mat.set_shader_parameter("albedo_tex", tex)
		_mat.set_shader_parameter("modulate", Color.WHITE)
	else:
		# Fallback: тонкая золотистая полоска в полную длину стрелы
		_arrow_aspect = 6.0
		_mat.set_shader_parameter("modulate", Color(0.85, 0.70, 0.20))
	_mat.set_shader_parameter("alpha_scissor", 0.2)
	quad.size = Vector2(ARROW_LENGTH, ARROW_LENGTH / maxf(_arrow_aspect, 0.01))
	quad.material = _mat
	_visual.mesh = quad
	add_child(_visual)

# Картинка обрезается по непрозрачной области: в исходных 64x64 стрела
# занимает 43x12 в середине, и без обрезки квад был бы почти пустым
static var _tex_cache: Dictionary = {}

func _load_arrow_texture() -> Texture2D:
	for p in _ARROW_PATHS:
		var path: String = p
		if _tex_cache.has(path):
			return _tex_cache[path]
		if not ResourceLoader.exists(path):
			continue
		var tex := load(path) as Texture2D
		if tex == null:
			continue
		var img := tex.get_image()
		if img == null:
			continue
		if img.is_compressed() and img.decompress() != OK:
			continue
		var rect := img.get_used_rect()
		var out: Texture2D = tex
		if rect.size.x > 0 and rect.size.y > 0:
			out = ImageTexture.create_from_image(img.get_region(rect))
		_tex_cache[path] = out
		return out
	return null

# ── ПОЛЁТ ────────────────────────────────────────────────────────────────────

## Единичный вектор скорости в точке t дуги.
## pos(t) = lerp(start, end, t) + UP · sin(π·t) · h
## d/dt   = (end − start) + UP · π · cos(π·t) · h
func _velocity_dir(t: float) -> Vector3:
	var v := _end_pos - _start_pos
	v.y += PI * cos(t * PI) * _arc_height
	if v.length_squared() < 1e-8:
		return Vector3.FORWARD
	return v.normalized()

func _apply_axis(dir: Vector3) -> void:
	if _mat != null:
		_mat.set_shader_parameter("axis", dir)

func _process(delta: float) -> void:
	if _spent:
		return
	if _dist < 0.001:
		queue_free()
		return

	_progress = minf(_progress + _speed * delta / _dist, 1.0)
	var t := _progress

	# Параболическая дуга: горизонтально = lerp, вертикально = sin(π·t)·высота
	var straight := _start_pos.lerp(_end_pos, t)
	var arc_y    := sin(t * PI) * _arc_height
	global_position = Vector3(straight.x, straight.y + arc_y, straight.z)
	# НАКЛОН РОВНО ПО СКОРОСТИ — каждый кадр
	_apply_axis(_velocity_dir(t))

	# ПОПАДАНИЕ ПРОВЕРЯЕТСЯ ЗДЕСЬ, сразу после переноса наконечника: раньше это
	# делала Area3D сигналом body_entered, но у бойцов больше нет физических тел
	# (см. _build_hitbox)
	_check_hit()
	if _spent:
		return

	if _progress >= 1.0:
		_stick_into_ground()

# ПРОМАХ: стрела долетела до расчётной точки, никого не задев — ВТЫКАЕТСЯ
# в землю НАКОНЕЧНИКОМ вперёд и торчит там до конца MAX_LIFETIME, выступая
# над грунтом на STUCK_EXPOSED своей длины.
func _stick_into_ground() -> void:
	_spent = true
	set_process(false)
	set_physics_process(false)
	_disable_physics()
	# ВТЫКАНИЕ В ЗЕМЛЮ — сухой удар мимо цели. Тише попадания в тело (см.
	# SFX_LIMITS): промахов в залпе много, и они не должны забивать попадания
	AudioManager.play_3d("bow_block", global_position)

	# Направление удара — вектор скорости в конце дуги (смотрит вниз).
	# Страховка на настильный выстрел: совсем пологую стрелу доворачиваем вниз,
	# иначе она легла бы на грунт плашмя вместо того, чтобы воткнуться
	var dir := _velocity_dir(1.0)
	if dir.y > -STUCK_MIN_DOWN:
		dir.y = -STUCK_MIN_DOWN
		dir = dir.normalized()
	_apply_axis(dir)

	# Точка входа в грунт: остриё уходит под землю на 1/3 длины, оперение
	# остаётся снаружи. Центр квада = точка входа − dir · (len/6)
	var gy := GameManager.get_terrain_height(global_position.x, global_position.z)
	var entry := Vector3(global_position.x, gy, global_position.z)
	global_position = entry - dir * (ARROW_LENGTH / 6.0)

	# Своего таймера у воткнувшейся стрелы больше нет: её снимет общий
	# MAX_LIFETIME, заведённый в _ready() ещё в момент выстрела
