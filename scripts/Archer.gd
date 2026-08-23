extends Unit
class_name Archer

const GLB_PATH    := "res://assets/models/archer.glb"
const SPRITE_PATH := "res://assets/sprites/units/Archer_Idle.png"
const MODEL_SCALE := 0.75
# Сама стрела берётся из общего пула (GameManager.spawn_arrow); ссылка на
# скрипт нужна только затем, чтобы стенды могли выйти на класс через лучника
const _Arrow      := preload("res://scripts/Arrow.gd")
const _SSParser   := preload("res://scripts/SpriteSheetParser.gd")

func _ready() -> void:
	_apply_config_stats("archer")   # характеристики — из unit_stats_config.gd
	display_name  = "Лучник"
	super._ready()
	_setup_visual()

# ═════════════════════════════════════════════════════════════════════════════
# ЛЕНТЫ АНИМАЦИЙ — ЯВНЫМИ ИМЕНАМИ, А НЕ СКАНОМ ПАПКИ.
#
# ЭТО БЫЛ БАГ ЭКСПОРТА: «в редакторе всё хорошо, в .exe вместо лучников серые
# манекены». Лучник был ЕДИНСТВЕННЫМ юнитом, который собирал анимации
# сканированием каталога (SpriteSheetParser.build_animated_sprite → DirAccess),
# а копейщик, рабочий, мечник и монах перечисляют файлы поимённо — потому они
# в сборке и работали, а лучник нет.
#
# Почему скан не переживает экспорт: в .pck исходных .png не существует вовсе.
# Импортёр кладёт в пакет готовую текстуру .ctex (в res://.godot/imported/) и
# рядом файл-перенаправитель <имя>.png.remap. DirAccess честно перечисляет
# содержимое пакета, но имён, оканчивающихся на «.png», там уже нет — проверка
# filename.ends_with(".png") не срабатывает ни разу, набор кадров выходит
# пустым, и юнит скатывается по цепочке запасных вариантов до процедурного
# лука. На диске в редакторе .png лежат, поэтому там всё исправно.
#
# По ИМЕНИ файл грузится нормально и в сборке: load()/ResourceLoader.exists()
# проходят через ту самую таблицу перенаправления. Поэтому правило простое —
# ассеты адресуются именами, каталог не перечисляется никогда.
# ═════════════════════════════════════════════════════════════════════════════
## Цветные наборы («{Цвет} Units/Archer»): Archer_Idle / Archer_Run / Archer_Shoot
const SHEETS_COLOR := {
	"idle":   "Archer_Idle.png",
	"walk":   "Archer_Run.png",
	"attack": "Archer_Shoot.png",
}
## Общий бесцветный набор (units/archer): у него другие имена, с «-Sheet»
## и строчной «w» в walk — регистр здесь именно такой, как на диске
const SHEETS_PLAIN := {
	"idle":   "Archer_Idle-Sheet.png",
	"walk":   "Archer_walk-Sheet.png",
	"attack": "Archer_Shoot-Sheet.png",
}

func _setup_visual() -> void:
	# 1. Спрайты ЦВЕТА СВОЕЙ ФРАКЦИИ; запасной вариант — общая папка archer/
	var fname := GameManager.race_of(faction)
	var archer_path := GameManager.unit_sprite_folder(faction, "archer")
	# Наличие набора проверяем ПО ФАЙЛУ, а не по каталогу (см. folder_has)
	var colored := _SSParser.folder_has(archer_path, SHEETS_COLOR["idle"])
	var sheets: Dictionary = SHEETS_COLOR
	if not colored:
		archer_path = "res://assets/factions/%s/units/archer" % fname
		sheets = SHEETS_PLAIN
	var asp: AnimatedSprite3D = _SSParser.build_sprite_from_map(archer_path, sheets)
	if asp:
		for child in get_children():
			if child is MeshInstance3D and child != selection_ring:
				child.visible = false
		# Цветной спрайт красить не надо — он уже нужного цвета
		if colored:
			asp.modulate = Color.WHITE
		else:
			asp.modulate = Color(1.0, 0.55, 0.55) if faction == Constants.FACTION_ENEMY else Color(0.75, 0.85, 1.0)
		add_child(asp)
		_active_sprite = asp
		return

	# 2. GLB model
	if ResourceLoader.exists(GLB_PATH):
		var scene := load(GLB_PATH) as PackedScene
		if scene:
			for child in get_children():
				if child is MeshInstance3D and child != selection_ring:
					child.visible = false
			_glb_model = scene.instantiate()
			_glb_model.scale = Vector3.ONE * MODEL_SCALE
			add_child(_glb_model)
			return

	# 3. Single PNG sprite
	if ResourceLoader.exists(SPRITE_PATH):
		var tex := load(SPRITE_PATH) as Texture2D
		if tex:
			set_sprite_texture(tex)
			return

	# 4. Procedural bow
	_add_bow_procedural()

# super даёт общий бонус урона + бонус кузницы для "archer" (слот "Стрелы");
# сверху — устаревший общий arrow_dmg. Без вызова super новый слот
# «Стрелы» до лучника не доходил вовсе.
func _upgrade_damage_bonus() -> float:
	return super._upgrade_damage_bonus() + GameManager.get_upgrade(faction, "arrow_dmg")

# ── УПРЕЖДЕНИЕ ЖИВЁТ В БАЛАНСНОЙ ТАБЛИЦЕ ────────────────────────────────────
# Доля честного баллистического выноса и его потолок в метрах — в
# unit_stats_config (ARCHER_LEAD_FACTOR / ARCHER_LEAD_MAX), там же разбор,
# почему 0.65 давало «дорогу из стрел» в пустом поле. Здесь только формула.
# Базовый разброс в метрах даже по стоящей цели
const SCATTER_BASE := 0.35
# Добавка разброса на каждый м/с скорости цели: бегущая пехота ловит
# заметно больше промахов, чем строй, стоящий на месте
const SCATTER_PER_SPEED := 0.34

# ═════════════════════════════════════════════════════════════════════════════
# ЗАЛПОВЫЙ ОГОНЬ (способность отряда, forge_config archer_1d)
# ═════════════════════════════════════════════════════════════════════════════
# Режим ВЫКЛЮЧЕН — всё ниже мертво, лучник работает ровно как раньше: стреляет
# сам по себе по мере перезарядки, со штатным разбросом SCATTER_*.
#
# Режим ВКЛЮЧЁН — отряд бьёт разом (см. GameManager._sweep_volleys), и стрелок
# целится не в свою цель, а в ОБЩУЮ точку залпа — центр масс вражеского строя.
#
# ── ПОЧЕМУ РАЗБРОС НЕ ОБНУЛЁН, А ЗАМЕНЁН ───────────────────────────────────
# В заказе сказано «разброс урезать до минимума, стрелы летят кучной тучей
# точно в указанную точку». Буквальный ноль проверен на бумаге и отброшен:
# стрела бьёт того, кто оказался в HIT_RADIUS = 0.35 м от неё (Arrow._check_hit),
# поэтому двадцать стрел, сошедшихся в одну точку, вошли бы в ОДНОГО бойца —
# девятнадцать из них ушли бы в уже мёртвого, и «максимальный суммарный урон по
# скоплению» превратился бы в свою противоположность.
#
# Поэтому убран именно СЛУЧАЙНЫЙ разброс (VOLLEY_JITTER — считанные сантиметры
# против 0.35-1.5 м обычного), а вместо него стрелы РОВНО раскладываются по
# площади вражеского строя: смещение считается детерминированно, по номеру
# стрелка, золотым углом. Получается плотная туча, накрывающая блок целиком и
# без дыр, — то самое «100% попадание по плотным построениям», но без
# перерасхода на одного человека.
## Случайная составляющая залпа. Не ноль ради живости картинки: одинаковые
## спирали у двух соседних залпов читались бы как узор
const VOLLEY_JITTER := 0.10
## Потолок «тучи». Строй шире этого накрывается не целиком — залп есть залп,
## а не удар по площади всей карты
const VOLLEY_CLUSTER_MAX := 3.2
## Столько разных мест в спирали. Простое число: смежные instance_id дают
## заметно разные позиции, и соседние по спавну лучники не садятся рядом
const VOLLEY_SLOTS := 97

## Смещение ЭТОГО стрелка внутри тучи, метры. Золотой угол раскладывает точки
## по диску равномерно при любом их числе — в отличие от случайного разброса,
## который на двадцати стрелах даёт и сгустки, и дыры
func _volley_offset(radius: float) -> Vector3:
	if radius <= 0.01:
		return Vector3.ZERO
	var k: float = float(get_instance_id() % VOLLEY_SLOTS)
	var ang: float = k * 2.39996323            # золотой угол, радианы
	var r: float = sqrt((k + 0.5) / float(VOLLEY_SLOTS)) * radius
	return Vector3(cos(ang) * r, 0.0, sin(ang) * r)

## Уровень выучки отряда: он же уровень ветеранства. Одиночка вне отряда —
## уставная норма (индекс 3), а не новобранец: стенды и гарнизонные стрелки не
## должны страдать за отсутствие отряда
func _drill_level() -> int:
	if squad_id <= 0:
		return 3
	return GameManager.squad_level(squad_id)

## ТЕМП СТРЕЛЬБЫ ПО ВЫУЧКЕ. Кузница (bonus_cooldown) и стойка считаются в базе,
## а множитель отряда применяется поверх — так же, как множитель разброса
func _effective_cooldown() -> float:
	var cd: float = super._effective_cooldown()
	var fire: float = float(_UStats.archer_drill(_drill_level()).get("fire", 1.0))
	return maxf(cd / maxf(fire, 0.01), _UStats.MIN_COOLDOWN)

func _may_strike_now() -> bool:
	# Отряда нет (одиночный лучник стенда) или режим выключен — обычная стрельба
	if squad_id <= 0 or not GameManager.squad_volley_mode(squad_id):
		return true
	return GameManager.squad_volley_open(squad_id)

func _damage_on_strike() -> bool:
	return false   # урон несёт стрела и списывает его при касании

## ЛУЧНИК НЕ ПРЕСЛЕДУЕТ — НИКОГДА И НИ ПРИ КАКИХ УСЛОВИЯХ (правило игрока).
## Приказ игрока он исполняет: подходит на дистанцию выстрела и стреляет. Но
## как только цель хоть раз оказалась в зоне поражения, шаг за ней запрещён —
## убежала дальше, значит стрелок остаётся стоять и ищет новую цель в своём
## радиусе. Без этого отряд лучников уходил за отступающим противником прямо
## к его замку и погибал там. См. Unit.pursues_target / _engaged_once
func pursues_target() -> bool:
	return false

# У лучника нет ни замаха мечом, ни тычка копьём: весь его звук — тетива
# в _on_attack_fired и прилёт стрелы в Arrow.gd
func _sfx_swing() -> String:
	return ""

func _sfx_hit() -> String:
	return ""

func _on_attack_fired(target: Node3D, damage: float) -> void:
	_play_attack_anim("attack", 600)   # анимация выстрела (Shoot-Sheet)
	# Щелчок тетивы — в момент выстрела. Попадание и втыкание в землю звучат
	# позже и отдельно, когда стрела реально долетит (см. Arrow.gd)
	AudioManager.play_3d("bow_attack", global_position)
	var parent := get_parent()
	if parent == null:
		return
	var from_pos := global_position + Vector3(0, 1.2, 0)
	# ПРЕДУПРЕЖДЕНИЕ ЦЕЛИ — в момент спуска тетивы. Мечник успевает поднять щит
	# ДО прилёта стрелы; если ждать касания, щит вставал бы уже после урона
	var tw := target as Unit
	if tw != null:
		tw.notify_incoming_fire(global_position)
	var speed: float = _UStats.stat("archer", "arrow_speed", 9.0)

	# ── УПРЕЖДЕНИЕ ───────────────────────────────────────────────────────────
	# Целимся не в цель, а туда, где она окажется к моменту прилёта.
	# Два прохода: время полёта зависит от точки, а точка — от времени.
	#
	# LEAD_FACTOR срезает вынос ВДВОЕ. При полном упреждении залп сорока
	# лучников по одному бегущему юниту выкладывал длинную «дорогу из стрел»
	# далеко впереди цели: у дальних стрелков время полёта большое, вынос
	# получался в несколько корпусов. С половинным выносом залп ложится кучно
	# в реальную зону движения — цель всё ещё ловит стрелы «наперерез».
	var tvel := Vector3.ZERO
	var tu := target as Unit
	if tu != null:
		tvel = tu.velocity
		tvel.y = 0.0
	# ── КООРДИНАТЫ ЦЕЛИ БЕРУТСЯ ЗДЕСЬ, В МОМЕНТ ВЫЛЕТА ──────────────────────
	# Не при постановке анимации замаха и не при открытии окна залпа: между
	# этими моментами проходит до кадра анимации, и на бегущем строе выстрел
	# уходил в точку, которую цель уже покинула
	var tbase: Vector3 = target.global_position + Vector3(0, 0.8, 0)
	var aim := tbase
	var lead_k: float = _UStats.ARCHER_LEAD_FACTOR
	if lead_k > 0.0 and tvel.length_squared() > 1e-4:
		# Два прохода: время полёта зависит от точки, а точка — от времени
		for _i in range(2):
			var travel: float = from_pos.distance_to(aim) / maxf(speed, 0.1)
			var lead: Vector3 = tvel * (travel * lead_k)
			# ПОТОЛОК ВЫНОСА. Без него длинный полёт по быстрой цели уводил
			# точку прицеливания на несколько корпусов вперёд — в пустое поле
			var ll: float = lead.length()
			if ll > _UStats.ARCHER_LEAD_MAX:
				lead *= _UStats.ARCHER_LEAD_MAX / ll
			aim = tbase + lead

	# ── ЗАЛП: ОБЩАЯ ТОЧКА ВМЕСТО СВОЕЙ ЦЕЛИ ─────────────────────────────────
	# Отряд бьёт в центр масс чужого строя, а стрелок берёт своё место в туче.
	# Упреждение здесь не нужно и вредно: точка уже общая на весь отряд, а
	# вынос считается по скорости ОДНОЙ цели и растащил бы залп веером
	var volley: bool = squad_id > 0 and GameManager.squad_volley_open(squad_id) \
		and GameManager.squad_volley_mode(squad_id)
	if volley:
		# ТОЧКА ЗАЛПА ПЕРЕСЧИТЫВАЕТСЯ СЕЙЧАС, А НЕ ЧИТАЕТСЯ ИЗ ЗАПИСИ ОТРЯДА.
		# Окно залпа живёт VOLLEY_WINDOW_MS (200 мс), и стрелки входят в него
		# вразнобой: последний стрелял по центру строя, который тот покинул
		# полсекунды назад. Свежий центр стоит одного вызова на выстрел
		var vp: Vector3 = GameManager.squad_volley_point(squad_id)
		if vp != Vector3.ZERO:
			# НАКРЫТИЕ ЕСТЬ ВСЕГДА. Габарит вражеского строя — это лишь ВЕРХНЯЯ
			# граница тучи; нижняя (VOLLEY_MIN_SPREAD) не даёт залпу схлопнуться
			# в точку по одиночной цели, по отряду из одного бойца или по зданию
			var cluster: float = clampf(GameManager.squad_volley_spread(squad_id),
				_UStats.VOLLEY_MIN_SPREAD, VOLLEY_CLUSTER_MAX)
			aim = vp + Vector3(0.0, 0.8, 0.0) + _volley_offset(cluster)
			var ja: float = randf() * TAU
			var jr: float = sqrt(randf()) * VOLLEY_JITTER
			aim += Vector3(cos(ja) * jr, 0.0, sin(ja) * jr)
		else:
			volley = false
	if not volley:
		# ── ОБЫЧНЫЙ РАЗБРОС ─────────────────────────────────────────────────
		# Чем быстрее цель, тем больше промахов: такие стрелы уходят в землю рядом
		var scatter := SCATTER_BASE + tvel.length() * SCATTER_PER_SPEED
		# КУЧНОСТЬ ИЗ КУЗНИЦЫ (bonus_spread) — доля, на которую срезается
		# разброс. Зажата в [0; 0.9): полностью обнулять разброс исследованием
		# нельзя, иначе весь отряд кладёт стрелы в одну точку и добивает уже
		# мёртвого (та же причина, по которой у залпа не нулевая кучность)
		var tighten: float = clampf(
			GameManager.unit_bonus(faction, stat_id, "bonus_spread") + vet_spread,
			0.0, 0.9)
		scatter *= (1.0 - tighten)
		# ВЫУЧКА ОТРЯДА: новобранцы кладут шире, ветераны кучнее
		# (unit_stats_config.ARCHER_DRILL — таблица, а не число в коде)
		scatter *= float(_UStats.archer_drill(_drill_level()).get("spread", 1.0))
		var ang := randf() * TAU
		var off := sqrt(randf()) * scatter          # равномерно по диску
		aim += Vector3(cos(ang) * off, 0.0, sin(ang) * off)

	var dist: float = from_pos.distance_to(aim)
	# СТРЕЛА БЕРЁТСЯ ИЗ ПУЛА, а не создаётся заново (см. GameManager.spawn_arrow):
	# комплект из узлов, меша и материала переживает выстрел и идёт в следующий.
	# Скорость и высота дуги — из unit_stats_config.gd (навесная траектория);
	# урон летит вместе со стрелой и списывается только при попадании
	var shaft = GameManager.spawn_arrow(parent, from_pos, aim, dist, speed,
		_UStats.stat("archer", "arrow_arc", 0.5), damage, self, faction)
	# ── СТРЕЛА ПО ЗДАНИЮ ЗАПОМИНАЕТ СВОЮ ЦЕЛЬ ──────────────────────────────
	# Попадание в бойца стрела ищет сама, сканом сетки (Arrow._check_hit) — но
	# здание в этой сетке не состоит, и стрелы по стенам просто втыкались в
	# землю рядом, не нанося ни очка. Сканировать группу зданий на каждую
	# стрелу в каждом кадре полёта незачем: стрелок и так ЗНАЕТ, куда целится,
	# и передаёт цель вместе с выстрелом. Проверка одна и в самом конце дуги
	if shaft != null and target is Building:
		shaft.set("_hit_node", target)

func _add_bow_procedural() -> void:
	var bow := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.03
	cyl.bottom_radius = 0.03
	cyl.height = 1.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.40, 0.25, 0.08)
	mat.roughness = 0.85
	cyl.material = mat
	bow.mesh = cyl
	bow.position = Vector3(-0.30, 1.0, 0.0)
	bow.rotation_degrees = Vector3(0, 0, 15)
	add_child(bow)
