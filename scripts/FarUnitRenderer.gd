extends RefCounted
## ═══════════════════════════════════════════════════════════════════════════
## ОБЩИЙ MultiMesh ВМЕСТО УЗЛА-СПРАЙТА НА КАЖДОГО БОЙЦА
## ═══════════════════════════════════════════════════════════════════════════
## Один MultiMeshInstance3D на КАЖДУЮ ЛЕНТУ КАДРОВ (Lancer_Run.png,
## Lancer_Right_Attack.png, Pawn_Idle.png, …) — то есть десятки узлов на всю
## армию вместо тысячи. Замер: 810 бойцов в кадре давали 1130 вызовов
## отрисовки, каждый спрайт своим узлом.
##
## АНИМАЦИЯ И ЗЕРКАЛО СОХРАНЕНЫ. Номер кадра и признак отражения едут в
## instance-цвете (use_colors), шейдер shaders/mm_unit_sprite.gdshader достаёт
## их оттуда и вырезает нужный кадр из ленты. Проверено визуально стендом
## qa_mm_anim: ряд MultiMesh шагает кадр в кадр с обычными Sprite3D.
##
## СОЗНАТЕЛЬНО БЕЗ custom_data — штатного способа передать четыре числа на
## экземпляр: у GL Compatibility (рендерер проекта) с ним открытый непочиненный
## баг (godot/godot#96503). use_colors в проекте уже проверен.
##
## Тон фракции здесь не нужен: стороны отличаются РАЗНЫМИ файлами спрайтов
## (game_settings.unit_folder), а не подкраской, поэтому лента сама по себе
## уже несёт цвет стороны, и бакет по ленте разделяет фракции автоматически.
##
## Владелец — GameManager (как unit_grid): RefCounted не может быть узлом
## дерева, MultiMeshInstance3D добавляется в мир через переданный world_root.
##
## ── ОДНА ПОДАЧА БУФЕРА НА БАКЕТ ЗА КАДР (set_buffer) ────────────────────────
## БЫЛО: каждый боец в каждом кадре сам звал set_instance_transform() +
## set_instance_color() — два обращения в RenderingServer на модель, 1620
## вызовов в кадр на 810 копейщиках. Замер это и показал: выключение одного
## лишь Unit._process поднимало кадры с 33 до 216, при том что времени ВНУТРИ
## GDScript тратилось всего ~4 мс — значит платили не за счёт, а за подачу.
##
## СТАЛО: у бакета есть теневой PackedFloat32Array — точная копия того, что
## лежит у MultiMesh. Бойцы пишут в него (обычная запись в массив, без выхода
## наружу), а раз в кадр GameManager._process зовёт flush(), и каждый ИЗМЕНИВ-
## ШИЙСЯ бакет уезжает в сервер ОДНИМ set_buffer(). Двадцать вызовов в кадр
## вместо полутора тысяч.
##
## Раскладка буфера жёстко задана движком: на экземпляр 12 float трансформа
## (матрица 3×4 построчно) + 4 float цвета, потому что transform_format =
## TRANSFORM_3D и use_colors = true. Отсюда STRIDE = 16.
##
## НЕПОДВИЖНЫХ НЕ ПЕРЕПИСЫВАЕМ. Слот помнит, что в него положили в прошлый раз
## (позиция, кадр, зеркало); совпало — записи нет и бакет не помечается
## грязным. Стоящий строй не стоит вообще ничего, а идущий отряд платит только
## за три float позиции: кадр и зеркало меняются в разы медленнее кадра и
## обновляются отдельным, более редким вызовом refresh().

const GROW_STEP := 128
const _SHADER := preload("res://shaders/mm_unit_sprite.gdshader")
const _BB     := preload("res://scripts/BillboardUtil.gd")

class Bucket:
	## 12 float трансформа + 4 float цвета на экземпляр (TRANSFORM_3D + use_colors)
	const STRIDE := 16

	var mmi: MultiMeshInstance3D
	var mm: MultiMesh
	var free: Array = []
	var capacity: int = 0
	## Материал бакета — только ради привязки ног (см. set_foot). Лента у бакета
	## одна, значит и привязка одна
	var mat: ShaderMaterial = null
	## Что уже отдано шейдеру. Заведомо невозможное число, чтобы первый же
	## вызов прошёл
	var _foot: float = -1.0e9
	## ── БУФЕР ЖИВЁТ В ЯДРЕ (этап C.1) ──────────────────────────────────────
	## Теневая копия буфера MultiMesh переехала в C# (ArmyCore.Rb): у vis_far
	## пакетная природа, и покадровый догон с записью позиций идёт одним
	## C#-проходом BatchVisual. Здесь остался номер бакета в ядре; все записи
	## ниже — делегаты в ArmySoA, и зовутся они ПО СОБЫТИЮ (смена ленты, кадр
	## походки, урон, скрытие), а не покадрово
	var core_id: int = -1

	func grow(step: int) -> void:
		var new_cap: int = capacity + step
		# Новые ячейки — нули: нулевая матрица и есть «спрятанный слот»
		GameManager.army.rb_ensure(core_id, new_cap)
		for i in range(capacity, new_cap):
			free.append(i)
		mm.instance_count = new_cap
		capacity = new_cap

	## ── ПРИВЯЗКА НОГ ЭТОЙ ЛЕНТЫ — В ШЕЙДЕР ─────────────────────────────────
	## Сколько от начала координат слота ВНИЗ до грунта. Шейдер берёт отсюда
	## точку, глубиной которой рисуется весь спрайт (mm_unit_sprite, foot_drop):
	## вывести её из геометрии квада нельзя, между низом квада и ступнями лежит
	## пустое поле кадра, и величина этого поля у каждой ленты своя.
	##
	## ЭТО РОВНО `base_y`, И ПЕРВАЯ ВЕРСИЯ ОШИБЛАСЬ ИМЕННО ЗДЕСЬ. Стояло
	## `half_h - base_y` — «от низа квада до ступней», число само по себе
	## осмысленное и как раз равное прежней ошибке. Но шейдер отсчитывает вниз
	## НЕ ОТ НИЗА КВАДА, А ОТ НАЧАЛА КООРДИНАТ СЛОТА, а оно и стоит на
	## `грунт + base_y`. Вычесть надо ровно подъём — иначе остаётся
	## `half_h - 2*base_y`, то есть у копейщика 1.25 м из прежних 1.85, и
	## армия тонет по-прежнему, только мельче. Поймал qa_visual_smoke: замер
	## сошёлся с этой формулой на всех четырёх размерах листа.
	##
	## ЗАПИСЬ ИДЁТ ТОЛЬКО НА ИЗМЕНЕНИЕ. Зовут это и из горячего пути обновления
	## внешности, а установка uniform'а — обращение в сервер отрисовки; число же
	## постоянно, пока бакет жив, и первый вызов остаётся единственным
	func set_foot(base_y: float) -> void:
		if absf(base_y - _foot) < 0.0005:
			return
		_foot = base_y
		if mat != null:
			mat.set_shader_parameter("foot_drop", base_y)

	## Плотность пятен крови (см. Unit.blood_spots, шейдер blood_spots).
	## Свойство ЛЕНТЫ, как и привязка ног: бакет заведён по ленте, а тролль
	## один на свою. Запись только на изменение — обращение в сервер отрисовки
	## Цвет вспышки удара (см. Unit.hit_flash_color, uniform flash_color) —
	## свойство ленты, запись только на изменение
	var _flash: Color = Color(-1.0, -1.0, -1.0)
	func set_flash(c: Color) -> void:
		if c.is_equal_approx(_flash):
			return
		_flash = c
		if mat != null:
			mat.set_shader_parameter("flash_color", Vector3(c.r, c.g, c.b))

	var _blood: float = -1.0
	func set_blood(v: float) -> void:
		if absf(v - _blood) < 0.0005:
			return
		_blood = v
		if mat != null:
			mat.set_shader_parameter("blood_spots", v)

	## Полная запись: позиция + кадр + зеркало + состояние урона.
	## Кадр и зеркало едут в цвете (r — кадр/255, g — зеркало); состояние
	## урона переписывается ВМЕСТЕ с остальным — полная запись идёт при смене
	## ленты, и раненый, сменивший позу, не должен мигать чистым спрайтом
	func write(idx: int, pos: Vector3, frame: int, mirror: bool,
			flash: float, hp: float) -> void:
		GameManager.army.rb_write_full(core_id, idx, pos, frame, mirror, flash, hp)

	## Быстрый путь идущего бойца: только три float позиции (запасной режим и
	## разлёт; штатный покадровый путь ведёт BatchVisual в ядре)
	func write_pos(idx: int, pos: Vector3) -> void:
		GameManager.army.rb_write_pos(core_id, idx, pos)

	## ТОЛЬКО НОМЕР КАДРА — походка листается на своих 6-10 к/с и обязана
	## доезжать до буфера на каждом шаге ленты
	func write_frame(idx: int, frame: int) -> void:
		GameManager.army.rb_write_frame(core_id, idx, frame)

	## ТОЛЬКО СОСТОЯНИЕ УРОНА — вспышка живёт считанные кадры
	func write_dmg(idx: int, flash: float, hp: float) -> void:
		GameManager.army.rb_write_dmg(core_id, idx, flash, hp)

	## Спрятать слот — нулевая матрица (MultiMesh не умеет «скрыть экземпляр»,
	## зато вырожденный треугольник растеризатор отбрасывает сразу)
	func hide_slot(idx: int) -> void:
		GameManager.army.rb_hide_slot(core_id, idx)

	func hide_all() -> void:
		GameManager.army.rb_hide_all(core_id)

	## Подачу в RenderingServer делает ядро (ArmyCore.RbFlush), одним вызовом
	## на весь мир — см. FarUnitRenderer.flush ниже
	func flush() -> void:
		pass

## Что и куда положено про конкретного бойца. Класс, а не словарь: обращение к
## полю дешевле поиска по строковому ключу, а трогаем мы это на каждого бойца
## в каждом кадре. Ссылка на сам бакет тоже лежит здесь — чтобы не искать его
## в словаре по строке ключа
class Slot:
	var key: String
	var bucket: Bucket
	var index: int
	## Из чего сложен ключ. Сравниваем эти три значения напрямую, чтобы НЕ
	## собирать строку ключа на каждого бойца в каждом кадре: форматирование
	## строки было одной из самых дорогих операций всего горячего пути
	var tex: Texture2D
	var frames: int
	var px: float
	## Высота центра спрайта над ногами — часть геометрии, а не позиции; её
	## задаёт спрайт и меняет только смена ленты
	var base_y: float = 0.0
	## Что уже лежит в буфере: повторную такую же запись делать незачем
	var pos: Vector3 = Vector3(1e9, 1e9, 1e9)
	var frame: int = -1
	var mirror: bool = false
	## Состояние урона, лежащее в буфере: вспышка от удара и доля жизни.
	## Хранится здесь ровно затем же, зачем позиция и кадр, — чтобы не писать
	## в буфер то, что в нём и так лежит: целый строй не платит ничего
	var flash: float = 0.0
	var hp: float = 1.0

	## Порог «боец сдвинулся»: квадрат смещения. 1 мм² — то есть отсекаем
	## только точные совпадения и шум последнего бита, а не реальное движение
	const MOVE_EPS_SQ := 1e-6

	## БЫСТРЫЙ ПУТЬ ИДУЩЕГО, ЦЕЛИКОМ ВНУТРИ СЛОТА. Боец держит ссылку на свой
	## слот (Unit._far_slot) и зовёт этот метод напрямую — без поиска по
	## словарю бойцов и без захода в сам реестр. world_pos приходит с
	## покачиванием шага, высота центра спрайта добавляется здесь
	func move_to(world_pos: Vector3) -> void:
		var px: float = world_pos.x
		var py: float = world_pos.y + base_y
		var pz: float = world_pos.z
		var dx: float = px - pos.x
		var dy: float = py - pos.y
		var dz: float = pz - pos.z
		# НЕПОДВИЖНОГО НЕ ПЕРЕПИСЫВАЕМ: стоящий строй не помечает бакет грязным
		# вовсе, и flush() для него не делает ничего
		if dx * dx + dy * dy + dz * dz < MOVE_EPS_SQ:
			return
		pos = Vector3(px, py, pz)
		bucket.write_pos(index, pos)

	## БЫСТРЫЙ ПУТЬ ЛИСТАНИЯ ЛЕНТЫ. Зовёт сам боец, когда шагнул кадр походки
	## (см. Unit._advance_look_frame): в буфер уходит один float, разбора
	## спрайта и поиска бакета тут нет
	func set_frame(f: int) -> void:
		if f == frame:
			return
		frame = f
		bucket.write_frame(index, f)

	## БЫСТРЫЙ ПУТЬ СОСТОЯНИЯ УРОНА. Зовёт сам боец, когда вспышка сдвинулась
	## или изменилось здоровье (см. Unit.tick_visual). Порог у вспышки — шаг
	## восьмибитного канала: писать разницу, которой в буфере всё равно не
	## будет, незачем
	func set_damage(f: float, h: float) -> void:
		if absf(f - flash) < 0.004 and absf(h - hp) < 0.004:
			return
		flash = f
		hp = h
		bucket.write_dmg(index, f, h)

var _buckets: Dictionary = {}      # ключ ленты -> Bucket
var _slot: Dictionary = {}         # Unit -> Slot

## Ключ бакета — лента плюс размер пикселя: один и тот же PNG, показанный в
## разном масштабе, обязан попасть в разные бакеты, потому что размер квада
## вшит в меш.
##
## ВЫСОТА ЦЕНТРА СПРАЙТА В КЛЮЧ НЕ ВХОДИТ, хотя тоже приходит из спрайта: в неё
## подмешано покачивание при ходьбе (Unit._update_walk_anim). Будь она частью
## ключа, боец перекладывался бы из бакета в бакет на каждом шаге. Высота —
## часть позиции, а не геометрии
static func _bucket_key(sheet: Texture2D, frames: int, pixel_size: float) -> String:
	return "%d|%d|%.5f" % [sheet.get_rid().get_id(), frames, pixel_size]

func _get_or_make_bucket(key: String, sheet: Texture2D, frames: int,
		pixel_size: float, world_root: Node3D) -> Bucket:
	if _buckets.has(key):
		return _buckets[key]
	var b := Bucket.new()
	var sz := sheet.get_size()
	var fw: float = sz.x / float(maxi(frames, 1))

	var quad := QuadMesh.new()
	# Размер квада ровно тот же, что у Sprite3D с этим размером пикселя, —
	# иначе боец в общей отрисовке был бы крупнее или мельче своего же узла.
	#
	# ВЫСОТА ДОМНОЖЕНА НА V_STRETCH: билборд держит МИРОВУЮ ось Y, и под
	# ортокамерой с наклоном 45° спрайт рисовался бы сплющенным на 29%
	# (см. BillboardUtil.V_STRETCH). Здесь коррекция делается размером самого
	# квада, а не шейдером: высота центра спрайта (base_y) живёт в этом же
	# файле, и её надо растянуть тем же числом — иначе боец повиснет над землёй
	quad.size = Vector2(fw * pixel_size, sz.y * pixel_size * _BB.V_STRETCH)

	var mat := ShaderMaterial.new()
	mat.shader = _SHADER
	mat.set_shader_parameter("albedo_tex", sheet)
	mat.set_shader_parameter("frame_count", float(maxi(frames, 1)))
	# 0.15, как у направленных спрайтов копейщика: порог 0.5 срезал полупрозрачные
	# пиксели древка, и копьё пропадало местами
	mat.set_shader_parameter("alpha_scissor", 0.15)
	# ПРИОРИТЕТ ОТРИСОВКИ ВЫШЕ НАЗЕМНОЙ ДЕКОРАЦИИ (см. BillboardUtil.make_material,
	# приоритет 0 по умолчанию у травы/кустов/жил/пней). Без явного render_priority
	# оба билборда сортировались по расстоянию камере от СВОЕГО начала координат,
	# и мелкий куст/камушек у самых ног бойца иногда оказывался «ближе» и рисовался
	# поверх — боец казался наполовину утопленным в декорацию. Раз выставленный
	# приоритет решает сортировку раз и навсегда, независимо от дистанций.
	# mm_render_all = true — это единственный активный путь отрисовки бойцов
	# (см. GameManager.far_units), поэтому число здесь совпадает с тем, что у
	# запасного Sprite3D-пути стоит в UnitVisuals.gd (render_priority = 1)
	mat.render_priority = 1
	quad.material = mat

	# Привязку ног ставит первый же зарегистрировавшийся боец (см. set_foot):
	# здесь её взять неоткуда — бакет знает ленту, но не знает, на какой высоте
	# у неё нарисованы ступни
	b.mat = mat

	b.mm = MultiMesh.new()
	b.mm.transform_format = MultiMesh.TRANSFORM_3D
	b.mm.use_colors = true
	b.mm.mesh = quad
	b.mm.instance_count = 0
	# Буфер бакета заводится в ядре (см. шапку класса Bucket): подача в
	# RenderingServer и покадровый догон позиций идут оттуда
	b.core_id = GameManager.army.rb_create(b.mm.get_rid())

	b.mmi = MultiMeshInstance3D.new()
	b.mmi.multimesh = b.mm
	# Пирамиду видимости считает один узел на весь бакет, а бойцы в нём
	# разбросаны по всей карте: без запаса бакет целиком пропадал бы с экрана,
	# как только его условный центр уходит за край кадра
	b.mmi.extra_cull_margin = 16384.0
	world_root.add_child(b.mmi)

	_buckets[key] = b
	return b

## Поставить бойца в общую отрисовку. Лента, кадр и геометрия берутся из его
## собственного спрайта (Unit.sheet_frame), поэтому картинка не меняется
## Возвращает слот бойца (или null, если рисовать пока нечего): боец держит
## ссылку на него и обновляет позицию напрямую, без поиска по словарю
# ── СЧЁТЧИКИ ПЕРЕЕЗДОВ МЕЖДУ БАКЕТАМИ ───────────────────────────────────────
# Смена ленты (анимация, ракурс) переселяет бойца в другой бакет: это снятие
# слота в одном буфере и занятие в другом, то есть ДВА грязных бакета вместо
# нуля. В свалке анимации переключаются постоянно, и именно эта величина
# отвечает на вопрос «сколько стоит бой в отрисовке». Два целых на кадр —
# счётчики стоят дешевле, чем стоил бы спор о том, велика ли цифра
var reg_calls: int = 0
var unreg_calls: int = 0
var migrations: int = 0

func reset_counters() -> void:
	reg_calls = 0
	unreg_calls = 0
	migrations = 0

func register(unit: Unit, world_root: Node3D, mirror: bool) -> Slot:
	reg_calls += 1
	if _slot.has(unit):
		unregister(unit)
	var sf: Array = unit.sheet_frame()
	if sf.is_empty():
		return null     # рисовать нечего (спрайт ещё не построен) — молча выходим
	var sheet: Texture2D = sf[0]
	var frames: int      = sf[2]
	var px: float        = sf[3]
	var base_y: float    = sf[4]
	var key: String = _bucket_key(sheet, frames, px)
	var b := _get_or_make_bucket(key, sheet, frames, px, world_root)
	if b.free.is_empty():
		b.grow(GROW_STEP)
	var s := Slot.new()
	s.key    = key
	s.bucket = b
	s.index  = b.free.pop_back()
	s.tex    = sheet
	s.frames = frames
	s.px     = px
	# Тем же числом, что и высота квада: ноги бойца стоят ровно в его начале
	# координат (центр кадра поднят на base_y — см. SpriteSheetParser._make_sprite),
	# поэтому растяжение высоты и подъёма центра одним множителем оставляет
	# подошву на грунте
	s.base_y = base_y * _BB.V_STRETCH
	b.set_foot(s.base_y)
	b.set_blood(unit.blood_spots())
	b.set_flash(unit.hit_flash_color())
	s.frame  = sf[1]
	s.mirror = mirror
	s.pos    = unit.global_position + Vector3(0.0, s.base_y, 0.0)
	# Состояние урона берётся у бойца ЗДЕСЬ ЖЕ: подкрепление выходит целым, а
	# вот раненый, вернувшийся из тумана или сменивший ленту, обязан выйти в
	# буфер уже окровавленным — иначе он мигнёт чистым спрайтом
	s.flash  = unit.hit_flash_level()
	s.hp     = unit.health_shade()
	_slot[unit] = s
	b.write(s.index, s.pos, s.frame, mirror, s.flash, s.hp)
	# ── ПРИВЯЗКА СТРОКИ К СЛОТУ: ПОКАДРОВЫЙ ДОГОН ВЕДЁТ ЯДРО ────────────────
	# Нарисованная точка передаётся отсюда: при переезде между бакетами (смена
	# ленты) она обязана сохраниться, иначе картинка прыгнет на логическую.
	# Боец без строки в ядре (_soa < 0) остаётся на событийных записях слота —
	# как и раньше
	if unit._soa >= 0:
		GameManager.army.row_bind(unit._soa, b.core_id, s.index, s.base_y,
			unit._draw_pos if unit._draw_init else unit.global_position,
			unit._draw_init)
		unit._rb_bound = true
		# Лента — в строку СРАЗУ: _set_anim мог пройти до привязки (этап E1)
		unit._push_row_anim()
	return s

## Слот бойца или null (для тех, кто держит на него прямую ссылку)
func slot_of(unit: Unit) -> Slot:
	return _slot.get(unit)

## Убрать бойца из общей отрисовки. Идемпотентно
func unregister(unit: Unit) -> void:
	unreg_calls += 1
	if not _slot.has(unit):
		return
	var s: Slot = _slot[unit]
	if s.bucket != null and s.bucket.mm != null:
		s.bucket.hide_slot(s.index)
		s.bucket.free.append(s.index)
	# Отвязать строку от слота: догон ядра не должен писать в отданное место.
	# Живость — на сырой ссылке (правило 5): сюда приходят и из _exit_tree
	if is_instance_valid(unit):
		if unit._soa >= 0:
			GameManager.army.row_unbind(unit._soa)
		unit._rb_bound = false
	_slot.erase(unit)

## ПОЛНОЕ ОБНОВЛЕНИЕ: позиция, кадр, зеркало, при необходимости — переезд в
## бакет другой ленты. Зовётся РЕДКО (раз в Unit.ANIM_EVERY кадров или по
## срочному признаку), потому что внешность бойца меняется в разы медленнее
## кадра: анимация идёт на 6-10 fps, ракурс — на поворотах.
##
## pos — уже с покачиванием шага (см. Unit._sync_far_render): высота центра
## спрайта добавляется здесь из слота
## Возвращает АКТУАЛЬНЫЙ слот: при смене ленты боец переезжает в другой бакет,
## и прежняя ссылка (Unit._far_slot) становится недействительной
## ── БЕЗ СЛОВАРЯ И БЕЗ АЛЛОКАЦИИ ─────────────────────────────────────────────
## Две вещи, которые эта функция делала зря на КАЖДОМ вызове (а их сотни в кадр,
## ветка vis_far — 3.6 мкс на бойца, вторая по величине статья визуального
## прохода):
##   • `_slot.get(unit)` — поиск по словарю с объектом-ключом, хотя вызывающий
##     (Unit._sync_far_render) держит ПРЯМУЮ ссылку на слот и передаёт её сюда;
##   • `unit.sheet_frame()` — вызов, СОБИРАЮЩИЙ Array из пяти элементов, то есть
##     аллокация кучи на каждое обновление позы. Все пять величин — обычные поля
##     бойца, и прочитать их напрямую дешевле, чем сложить из них массив.
## Словарь остался для тех, кто ссылки не держит (update_pos, стенды)
func refresh(unit: Unit, pos: Vector3, mirror: bool, known: Slot = null) -> Slot:
	var s: Slot = known
	if s == null:
		s = _slot.get(unit)
	if s == null:
		return null
	if not unit._look_ok:
		unit._look_bind()
	var tex: Texture2D = unit._look_tex
	if tex == null:
		return s
	var frames: int    = unit._look_frames
	var px: float      = unit._look_px
	# СРАВНИВАЕМ СОСТАВЛЯЮЩИЕ КЛЮЧА, А НЕ СОБРАННУЮ СТРОКУ: одинаковая текстура
	# — это один и тот же объект, сравнение ссылок бесплатно, а "%d|%d|%.5f"
	# стоило дороже всего остального в этой функции вместе взятого
	if tex != s.tex or frames != s.frames or not is_equal_approx(px, s.px):
		# Лента сменилась — это смена ракурса или анимации, событие не покадровое
		migrations += 1
		var world_root: Node3D = null
		if s.bucket != null and s.bucket.mmi != null:
			world_root = s.bucket.mmi.get_parent()
		unregister(unit)
		if world_root != null:
			return register(unit, world_root, mirror)
		return null
	# Высоту центра берём заново: в запасном режиме (mm_render_all выключен) в
	# неё подмешано покачивание шага, которое пишет сам узел спрайта
	s.base_y = unit._sprite_base_y * _BB.V_STRETCH
	# И ЗДЕСЬ ТОЖЕ, а не только при регистрации: у копейщика sheet_frame()
	# отдаёт общий SPRITE_BASE_Y, а настоящая привязка ленты (_sprite_base_y)
	# доезжает только сюда. Запись идёт лишь на изменение, см. set_foot
	s.bucket.set_foot(s.base_y)
	var p := Vector3(pos.x, pos.y + s.base_y, pos.z)
	var frame: int = unit._look_frame
	if frame == s.frame and mirror == s.mirror:
		# Внешность та же — довольно быстрого пути по позиции
		s.move_to(pos)
		return s
	s.frame  = frame
	s.mirror = mirror
	s.pos    = p
	s.bucket.write(s.index, p, frame, mirror, s.flash, s.hp)
	return s

## БЫСТРЫЙ ПУТЬ ИДУЩЕГО: только позиция, без единого обращения к спрайту.
## Держащим прямую ссылку на слот (Unit) сюда заходить незачем — они зовут
## Slot.move_to() сами
func update_pos(unit: Unit, pos: Vector3) -> void:
	var s: Slot = _slot.get(unit)
	if s != null:
		s.move_to(pos)

## Совместимость со старым именем (стенды, GameManager.update_far_transform)
func update_transform(unit: Unit, pos: Vector3, mirror: bool) -> void:
	refresh(unit, pos, mirror)

## ОТДАТЬ НАКОПЛЕННОЕ В РЕНДЕР. Один MultimeshSetBuffer на изменившийся бакет
## за кадр, и делает это ЯДРО (буферы живут там, см. шапку класса Bucket);
## зовётся из GameManager._process ПОСЛЕ всех юнитов (см. process_priority)
func flush() -> void:
	GameManager.army.rb_flush()

func is_registered(unit: Unit) -> bool:
	return _slot.has(unit)

## Отладка/стенды: сколько бойцов сейчас в общей отрисовке
func registered_count() -> int:
	return _slot.size()

## Сколько узлов MultiMeshInstance3D заведено (столько же вызовов отрисовки)
func bucket_count() -> int:
	return _buckets.size()

## Бойцы, сейчас числящиеся в общей отрисовке (см.
## GameManager._wake_returned_far_units: спящий боец сам не заметит возврат)
func registered_units() -> Array:
	return _slot.keys()

## Полная очистка (смена сцены/сброс партии). Сами MultiMeshInstance3D остаются
## в дереве — их удаляет владелец world_root при выгрузке сцены
func clear_bookkeeping() -> void:
	for key in _buckets:
		var b: Bucket = _buckets[key]
		if b.mm != null:
			b.hide_all()
			b.free = range(b.capacity)
	GameManager.army.rb_flush()
	_slot.clear()
