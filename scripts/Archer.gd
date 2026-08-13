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

# Доля расчётного упреждения, которую лучник реально выносит вперёд.
# Было 0.5 (вдвое короче честного баллистического выноса) — стрелы стали
# отставать от бегущей цели, поэтому +30%: 0.5 × 1.3 = 0.65.
# Залп по-прежнему кучный, но ложится уже перед носом бегущего, а не позади
const LEAD_FACTOR := 0.65
# Базовый разброс в метрах даже по стоящей цели
const SCATTER_BASE := 0.35
# Добавка разброса на каждый м/с скорости цели: бегущая пехота ловит
# заметно больше промахов, чем строй, стоящий на месте
const SCATTER_PER_SPEED := 0.34

func _damage_on_strike() -> bool:
	return false   # урон несёт стрела и списывает его при касании

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
	var aim := target.global_position + Vector3(0, 0.8, 0)
	for _i in range(2):
		var travel: float = from_pos.distance_to(aim) / maxf(speed, 0.1)
		aim = target.global_position + Vector3(0, 0.8, 0) + tvel * (travel * LEAD_FACTOR)

	# ── РАЗБРОС ──────────────────────────────────────────────────────────────
	# Чем быстрее цель, тем больше промахов: такие стрелы уходят в землю рядом
	var scatter := SCATTER_BASE + tvel.length() * SCATTER_PER_SPEED
	var ang := randf() * TAU
	var off := sqrt(randf()) * scatter          # равномерно по диску
	aim += Vector3(cos(ang) * off, 0.0, sin(ang) * off)

	var dist: float = from_pos.distance_to(aim)
	# СТРЕЛА БЕРЁТСЯ ИЗ ПУЛА, а не создаётся заново (см. GameManager.spawn_arrow):
	# комплект из узлов, меша и материала переживает выстрел и идёт в следующий.
	# Скорость и высота дуги — из unit_stats_config.gd (навесная траектория);
	# урон летит вместе со стрелой и списывается только при попадании
	GameManager.spawn_arrow(parent, from_pos, aim, dist, speed,
		_UStats.stat("archer", "arrow_arc", 0.5), damage, self, faction)

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
