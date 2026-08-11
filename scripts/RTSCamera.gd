extends Camera3D
class_name RTSCamera

## КАМЕРА В СТИЛЕ «КАЗАКИ 3»: РАКУРС ЗАФИКСИРОВАН НАМЕРТВО.
##
## АРХИТЕКТУРНОЕ ПРАВИЛО: мир (World/Main) НИКОГДА не вращается. Камера —
## ребёнок узла CameraPivot; пивот стоит в точке фокуса на земле, камера
## висит на фиксированном отступе от него.
##
## ЧТО ИГРОКУ РАЗРЕШЕНО:
##   • двигать карту — WASD / стрелки / край экрана / ЗАЖАТАЯ СРЕДНЯЯ КНОПКА;
##   • менять высоту — колесо мыши (в пределах min_height…max_height).
## ЧТО ЗАПРЕЩЕНО СОВСЕМ:
##   • крутить сцену вокруг (yaw) — прежние Q/E и перетаскивание средней
##     кнопкой; теперь средняя кнопка ТАЩИТ карту, а не вращает её;
##   • менять наклон (pitch) — он прибит к FIXED_PITCH.
##
## _orbit_yaw/_orbit_pitch как переменные ОСТАВЛЕНЫ: на них опирается расчёт
## положения и тесты, которые проверяют, что спрайты разворачиваются
## относительно камеры. Их просто больше некому изменить из ввода.

## ЕДИНСТВЕННАЯ РУЧКА РАКУРСА. Градусы НИЖЕ ГОРИЗОНТА: 90 = объектив смотрит
## строго в землю, 25 = почти сбоку. Меньше значение — выше задран нос.
##
## 45° — классическая изометрия «Казаков 3» / Warcraft 3: видно фасады построек
## и деревья в полный рост, а не их макушки. Было 60°, и камера заметно клевала
## носом — спрайты «ложились» на землю, объём терялся.
## Крутить ракурс — ЗДЕСЬ, это единственное место.
const FIXED_PITCH := 45.0
## Фиксированный поворот вокруг вертикали. Менять не нужно: при 0 камера
## смотрит вдоль -Z, и мировые оси совпадают с экранными
const FIXED_YAW := 0.0

# ─────────────────────────────────────────────────────────────────────────────
# ПРОЕКЦИЯ: ОРТОГРАФИЧЕСКАЯ
#
# Была перспектива с углом обзора 75°. У широкой перспективы вертикальные
# объекты у КРАЁВ кадра «заваливаются» наружу: чем дальше спрайт от центра
# экрана, тем сильнее его верх уезжает от вертикали. На спрайтовых деревьях
# это читалось как веер/лучи, расходящиеся от середины экрана, и как «круг»
# из наклонённых стволов. Это не баг билбордов — это сама природа
# перспективной проекции.
#
# Ортография убирает искажение полностью: лучи проекции ПАРАЛЛЕЛЬНЫ, поэтому
# дерево в углу экрана рисуется ровно так же, как дерево в центре. Ровно так
# сделаны «Казаки» и вся классическая изометрия.
#
# Что меняется в устройстве камеры:
#   • масштаб задаёт не высота, а SIZE — сколько метров мира влезает в кадр
#     по вертикали. Зум крутит именно его;
#   • камеру уносим на фиксированное расстояние ORTHO_DISTANCE вдоль взгляда.
#     В ортографии дистанция на масштаб НЕ влияет, но должна быть заведомо
#     больше карты: всё, что окажется ПОЗАДИ камеры, обрежется near-плоскостью.
# ─────────────────────────────────────────────────────────────────────────────
## Насколько камера отнесена назад вдоль взгляда. На картинку не влияет
const ORTHO_DISTANCE := 400.0

@export var pan_speed: float = 32.0
@export var edge_pan_margin: float = 16.0
## СКОРОСТЬ СКРОЛЛА КРАЕМ ЭКРАНА = pan_speed × этот множитель.
##
## Раньше край экрана вёз камеру ровно с той же скоростью, что и WASD, и на
## большой карте прогулка от базы до базы «мышью у бортика» ощущалась вязкой:
## на клавиатуре можно жать по диагонали и не отрывать руку, а край экрана —
## единственный способ вести камеру, не бросая курсор.
##
## 1.35 — это +35% (просили 30–40%). Отдельная ручка, а НЕ поднятый pan_speed:
## скорость WASD трогать нельзя, она согласована с шагом юнита и зумом
@export var edge_pan_boost: float = 1.35
## Шаг зума в МЕТРАХ ВИДИМОЙ ВЫСОТЫ за одну щелчок колеса
@export var zoom_speed: float = 6.0
## Пределы зума: сколько метров мира влезает в кадр по вертикали.
## 22 м — вплотную (видно отдельных бойцов), 88 м — обзор поля боя.
##
## ПОТОЛОК ОПУЩЕН СО 110 ДО 88 М (−20%). На прежнем отдалении в кадр влезала
## почти треть карты, и бойцы превращались в едва различимые фишки — читать
## строй и род войск было нечем. Теперь на максимальном отдалении войска
## заметно крупнее и ближе, а поле боя целиком по-прежнему видно
@export var min_height: float = 22.0
@export var max_height: float = 88.0
## Эффективные границы прогулки ФОКУСА на текущем зуме — читаемы для отладки,
## но не задаются руками: пересчитываются в _clamp_focus() из _map_half
@export var bounds_min: Vector2 = Vector2(-75, -75)
@export var bounds_max: Vector2 = Vector2(75, 75)
## Половина карты (сырая, без отступа под текущий зум) — ставится set_bounds()
var _map_half: Vector2 = Vector2(1e9, 1e9)

# _height / _target_height теперь означают ВИДИМУЮ ВЫСОТУ КАДРА в метрах
# (Camera3D.size), а не высоту подвеса. Имена оставлены: на них завязаны
# зум, пределы и стенды
var _height: float = 48.0
var _target_height: float = 48.0
var _focus: Vector3 = Vector3(0, 0, 0)
var _orbit_yaw: float = FIXED_YAW
var _orbit_pitch: float = FIXED_PITCH
var _mmb_pressed: bool = false
var _last_mouse_pos: Vector2 = Vector2.ZERO
# CameraPivot — узел, в котором живёт точка фокуса
var _pivot: Node3D = null

func _ready() -> void:
	var p := get_parent()
	if p is Node3D and p.name == "CameraPivot":
		_pivot = p
	_orbit_pitch = FIXED_PITCH
	_orbit_yaw   = FIXED_YAW
	# ОРТОГРАФИЯ. near держим маленьким, far — заведомо больше выноса камеры
	# плюс глубины карты, иначе дальний край поля обрежется
	projection = PROJECTION_ORTHOGONAL
	near = 0.05
	far  = ORTHO_DISTANCE * 2.0 + 600.0
	_update_position()

func _process(delta: float) -> void:
	var move := Vector2.ZERO

	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		move.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		move.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		move.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		move.x += 1

	# Скролл краем экрана отключается, пока карту тащат средней кнопкой:
	# иначе курсор, уехавший к границе, начинал бы гнать камеру сам.
	# Направление от края копится ОТДЕЛЬНО от клавиатурного: у него своя,
	# повышенная скорость (edge_pan_boost)
	var edge := Vector2.ZERO
	# Курсор над любым элементом Control (HUD-панели, кнопки, тултипы) —
	# край экрана под ним не должен гнать камеру: иначе наведение на
	# верхнюю/боковую панель само по себе прокручивало карту.
	# ФОКУС ОКНА обязателен по той же причине, по которой раньше курсор
	# запирался в окне (Main._confine_mouse, снят): с курсором на втором
	# мониторе позиция мыши упирается в границу вьюпорта и читается как
	# «игрок держит курсор у края» — карта уезжала сама по себе. Проверка
	# фокуса решает это, не отнимая у игрока полосу заголовка Windows
	if not _mmb_pressed and get_viewport().gui_get_hovered_control() == null \
			and _window_focused():
		var viewport      := get_viewport()
		var mouse_pos     := viewport.get_mouse_position()
		var viewport_size := viewport.get_visible_rect().size
		if mouse_pos.x <= edge_pan_margin:
			edge.x -= 1
		elif mouse_pos.x >= viewport_size.x - edge_pan_margin:
			edge.x += 1
		if mouse_pos.y <= edge_pan_margin:
			edge.y -= 1
		elif mouse_pos.y >= viewport_size.y - edge_pan_margin:
			edge.y += 1

	if move.length() > 0.0:
		_pan_by(move.normalized() * pan_speed * delta)
	if edge.length() > 0.0:
		_pan_by(edge.normalized() * pan_speed * edge_pan_boost * delta)

	_height = lerp(_height, _target_height, delta * 6.0)
	# Зум сам по себе (без пана) должен подтягивать границы: отдаляясь у самого
	# края карты, игрок иначе видел бы черноту, пока не шевельнёт мышью/WASD
	_clamp_focus()
	_update_position()
	# Точка обзора для отсечения дальних спрайтов обновляется ОДИН раз за кадр
	GameManager.update_view_point(_focus)

## Окно сейчас в фокусе? В headless-прогонах DisplayServer отвечать не обязан,
## поэтому там всегда true — стенды не должны зависеть от фокуса
func _window_focused() -> bool:
	if DisplayServer.get_name() == "headless":
		return true
	return DisplayServer.window_is_focused()

## Сдвиг фокуса в ЭКРАННЫХ осях: x — вправо по экрану, y — вглубь экрана.
## Оси берутся из фактической ориентации камеры и проецируются на плоскость XZ
func _pan_by(step: Vector2) -> void:
	var basis     := global_transform.basis
	var fwd_xz    := Vector3(basis.z.x, 0.0, basis.z.z)
	var right_xz  := Vector3(basis.x.x, 0.0, basis.x.z)
	# Защита от вырожденного случая (камера строго сверху)
	if fwd_xz.length() <= 0.01:
		return
	var cam_fwd   := -fwd_xz.normalized()
	var cam_right :=  right_xz.normalized()
	var dp := cam_right * step.x + cam_fwd * (-step.y)
	_focus.x += dp.x
	_focus.z += dp.z
	_clamp_focus()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_target_height = clamp(_target_height - zoom_speed, min_height, max_height)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_target_height = clamp(_target_height + zoom_speed, min_height, max_height)
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_mmb_pressed = event.pressed
			_last_mouse_pos = event.position

	elif event is InputEventMouseMotion and _mmb_pressed:
		# СРЕДНЯЯ КНОПКА ТАЩИТ КАРТУ (раньше вращала сцену). Карта едет ЗА
		# курсором: тянем вправо — содержимое уходит вправо, значит фокус
		# смещается влево, поэтому знак обратный.
		#
		# ИСПРАВЛЕНА ИНВЕРСИЯ ПО ВЕРТИКАЛИ. Было Vector2(-d.x, d.y): по X знак
		# перевёрнут, по Y — нет. _pan_by внутри само меняет знак step.y
		# (там ось «вглубь экрана»), поэтому неперевёрнутый d.y давал ДВОЙНОЕ
		# согласование: тянешь мышь вниз — карта уезжала вверх. Горизонталь при
		# этом работала правильно, отчего баг и читался как «перепутаны только
		# верх и низ». Теперь оба знака обратные, и обе оси тянутся одинаково:
		# куда ведёшь курсор, туда и едет содержимое.
		#
		# В ОРТОГРАФИИ масштаб точный: метров на пиксель = size / высота вьюпорта.
		# Поэтому точка под курсором остаётся под курсором на любом зуме
		var d: Vector2 = event.position - _last_mouse_pos
		var vh: float = get_viewport().get_visible_rect().size.y
		var mpp: float = _height / maxf(vh, 1.0)
		_pan_by(Vector2(-d.x, -d.y) * mpp)
		_last_mouse_pos = event.position

func pan_to(world_pos: Vector3) -> void:
	_focus.x = world_pos.x
	_focus.z = world_pos.z
	_clamp_focus()

## Мгновенная постановка камеры (без плавного lerp): фокус + зум сразу же,
## одним кадром. Используется на старте матча — камера должна встречать
## игрока уже в стартовой зоне на максимальном приближении, а не наезжать
## туда через полсекунды анимации.
## Высота выставляется ДО pan_to(): граница фокуса зависит от зума
## (_clamp_focus читает _height/_target_height), иначе прыжок на новую высоту
## зажимался бы по старой, ещё не применённой
func jump_to(world_pos: Vector3, height: float = -1.0) -> void:
	if height >= 0.0:
		_target_height = clamp(height, min_height, max_height)
		_height = _target_height
	pan_to(world_pos)
	_update_position()

## Половина карты, СЫРАЯ (не отступ под камеру). Ставится из Main по размеру
## карты; фактический отступ, на который объектив не пускают, теперь
## вычисляется в _clamp_focus() из текущего зума и аспекта экрана — см. её
## комментарий. Второй аргумент можно опустить — тогда получится квадрат
func set_bounds(half_x: float, half_z: float = -1.0) -> void:
	var hz: float = half_z if half_z >= 0.0 else half_x
	_map_half = Vector2(half_x, hz)
	_clamp_focus()

## Половина ВИДИМОЙ НА ЗЕМЛЕ области при вертикальном размере кадра s (метры,
## Camera3D.size) и текущем соотношении сторон окна.
## По ширине — обычная KEEP_HEIGHT-зависимость (s * aspect / 2).
## По глубине — НЕ s/2: камера смотрит на землю под углом FIXED_PITCH снизу
## от горизонта, и наклон "растягивает" видимую глубину относительно видимой
## высоты кадра в 1/sin(pitch) раз (вывод: луч через верх/низ кадра пересекает
## плоскость Y=0 на расстоянии (s/2)/sin(pitch) от точки фокуса, а не s/2).
## При pitch=45° это ×1.41 — то есть по Z карта "кончается" раньше, чем по X,
## и старый плоский отступ в 12 м (без разницы X/Z и без зависимости от зума)
## открывал черноту за краем именно по этой оси в первую очередь
func _visible_ground_half(s: float) -> Vector2:
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var aspect: float = vp_size.x / maxf(vp_size.y, 1.0)
	var sin_p: float = maxf(sin(deg_to_rad(_orbit_pitch)), 0.05)
	return Vector2(s * aspect * 0.5, s * 0.5 / sin_p)

## Пересчитывает bounds_min/max из _map_half под ТЕКУЩИЙ/ЦЕЛЕВОЙ зум и
## соотношение сторон, и тут же зажимает _focus в них. max(_height,
## _target_height) — при зуме наружу используем ещё не осевшую (большую)
## высоту, иначе на середине анимации зума можно панорамой проскочить дальше,
## чем окажется допустимо, когда зум доедет до цели.
##
## EDGE_OVERSCROLL — НАМЕРЕННЫЙ ЗАПАС ЗА КРАЕМ КАРТЫ. Без него камера
## упиралась ровно в границу поля: угловой замок или отряд оказывались
## прижаты к самому краю экрана (а частью и под панелями HUD), рассмотреть и
## выделить их было нечем. Разрешая фокусу выехать за край, мы пускаем в кадр
## полосу черноты по краю — это правильный размен, ровно так делают Казаки/AoE:
## угол карты уезжает ближе к центру экрана и становится доступен.
const EDGE_OVERSCROLL := 26.0

func _clamp_focus() -> void:
	var s: float = maxf(_height, _target_height)
	var half: Vector2 = _visible_ground_half(s)
	# maxf(..., EDGE_OVERSCROLL): даже когда видимая область шире самой карты
	# (сильное отдаление), запас на прогулку остаётся — камера не «прилипает»
	# намертво к центру
	bounds_min = Vector2(
		-maxf(_map_half.x - half.x + EDGE_OVERSCROLL, EDGE_OVERSCROLL),
		-maxf(_map_half.y - half.y + EDGE_OVERSCROLL, EDGE_OVERSCROLL))
	bounds_max = -bounds_min
	_focus.x = clamp(_focus.x, bounds_min.x, bounds_max.x)
	_focus.z = clamp(_focus.z, bounds_min.y, bounds_max.y)

func _update_position() -> void:
	var yaw_rad   := deg_to_rad(_orbit_yaw)
	var pitch_rad := deg_to_rad(_orbit_pitch)
	# МАСШТАБ В ОРТОГРАФИИ ЗАДАЁТ ТОЛЬКО size. Камеру уносим назад вдоль взгляда
	# на постоянное расстояние: на картинку это не влияет совсем, но гарантирует,
	# что ни один объект не окажется позади near-плоскости
	size = maxf(_height, 0.1)
	var up_off:   float = ORTHO_DISTANCE * sin(pitch_rad)
	var back_off: float = ORTHO_DISTANCE * cos(pitch_rad)
	if _pivot != null:
		# Пивот стоит в точке фокуса на земле; камера — его ребёнок на
		# фиксированном локальном отступе. Мир (World) не трансформируется вообще
		_pivot.position = Vector3(_focus.x, 0.0, _focus.z)
		_pivot.rotation = Vector3(0.0, -yaw_rad, 0.0)
		position = Vector3(0.0, up_off, back_off)
		look_at(_pivot.global_position, Vector3.UP)
	else:
		# Fallback без пивота (камера добавлена напрямую): двигаем саму камеру
		global_position = Vector3(
			_focus.x - sin(yaw_rad) * back_off,
			up_off,
			_focus.z + cos(yaw_rad) * back_off
		)
		look_at(_focus, Vector3.UP)
