extends Unit
class_name Monk

## МОНАХ — третий найм Замка (владелец: "проанализируй папки проекта, найди
## ассет monk"). У ассета (assets/factions/humans/units/<Цвет> Units/Monk/)
## есть только Idle.png/Run.png/Heal.png/Heal_Effect.png — атаки в листе нет,
## поэтому монах дерётся ГОЛЫМИ РУКАМИ через ту же общую боевую петлю, что и
## остальные юниты (Unit._strike_damage() без переопределения), просто со
## скромными характеристиками из unit_stats_config.gd ("monk").
##
## ── ЦЕЛИТЕЛЬ (заказ владельца, 09.09.2026) ─────────────────────────────────
## Раз в MONK_HEAL_TICK секунд монах ищет раненых СВОИХ в радиусе
## MONK_HEAL_RADIUS и лечит самого раненого: MONK_HEAL_SEC_PER_MAN секунд на
## полный запас одного бойца, то есть за такт возвращается
## max_health × tick / 10. Воскрешения нет: лечатся только живые. Лента Heal
## играет, пока идёт лечение; отдельного узла-эффекта не заводится
const _SSParser := preload("res://scripts/SpriteSheetParser.gd")
const _BBUtilM := preload("res://scripts/BillboardUtil.gd")
const _MCfg := preload("res://scripts/unit_stats_config.gd")

var _heal_t: float = 0.0
## Кого лечили последним тактом и сколько всего вылечено (диагностика стенда)
var heal_target: Node3D = null
var healed_total: float = 0.0

func _ready() -> void:
	_apply_config_stats("monk")
	display_name = "Монах"
	super._ready()
	_setup_monk_visual()

func _setup_monk_visual() -> void:
	var fname := GameManager.race_of(faction)
	var pack_path := GameManager.unit_sprite_folder(faction, "monk")
	# Проба ПО ФАЙЛУ, а не по каталогу (см. SpriteSheetParser.folder_has)
	var colored := _SSParser.folder_has(pack_path, "Idle.png")
	if not colored:
		pack_path = "res://assets/factions/%s/units/soldier_pack" % fname
	var tint := Color.WHITE
	if not colored:
		tint = Color(1.0, 0.55, 0.55) if faction == Constants.FACTION_ENEMY else Color(0.82, 0.92, 1.0)

	var mapped: AnimatedSprite3D = _SSParser.build_sprite_from_map(pack_path, {
		"idle": "Idle.png",
		"walk": "Run.png",
		"heal": "Heal.png",
	}, [])
	if mapped:
		for child in get_children():
			if child is MeshInstance3D and child != selection_ring:
				child.visible = false
		mapped.modulate = tint
		add_child(mapped)
		_active_sprite = mapped
		return

	var asp: AnimatedSprite3D = _SSParser.build_animated_sprite(pack_path)
	if asp:
		for child in get_children():
			if child is MeshInstance3D and child != selection_ring:
				child.visible = false
		asp.modulate = tint
		add_child(asp)
		_active_sprite = asp
		return

	# Цветовой оттенок на базовом billboard-спрайте — крайний случай, как у Warrior
	_ensure_body_quad()
	if _sprite_node:
		var mat := _sprite_node.get_active_material(0) as StandardMaterial3D
		if mat:
			mat.albedo_color = Color(0.95, 0.90, 0.55) if faction == Constants.FACTION_PLAYER else Color(0.90, 0.30, 0.30)

## ── ТИК ЛЕЧЕНИЯ ───────────────────────────────────────────────────────────
## Поверх базового тика: монах ходит и дерётся как все, а лечение — своя
## редкая работа (раз в MONK_HEAL_TICK), не покадровая
func tick_physics(delta: float, prof: bool = false, bm: bool = true,
		bonus_ver: int = -1) -> void:
	super.tick_physics(delta, prof, bm, bonus_ver)
	# МОНАХ ВЫБЫЛ — ЭФФЕКТ ГАСНЕТ ТЕМ ЖЕ КАДРОМ. Заказ прямо называет случаи
	# прекращения («юнит вылечен, монах переключился, монах умер или отошёл»),
	# и два из них проходят здесь
	if state == State.DEAD or garrisoned:
		_stop_heal_vfx()
		return
	_ride_heal_vfx()
	_heal_t -= delta
	if _heal_t > 0.0:
		return
	_heal_t = _MCfg.MONK_HEAL_TICK
	_heal_pulse()

## Один такт: самый раненый свой в радиусе получает долю запаса
func _heal_pulse() -> void:
	var best: Unit = null
	var best_frac: float = 1.0
	for n in GameManager.unit_grid.query_radius(global_position, _MCfg.MONK_HEAL_RADIUS):
		if n == null or not is_instance_valid(n) or n == self:
			continue
		var u := n as Unit
		if u == null or u.is_dead() or u.garrisoned or u.faction != faction:
			continue
		if u.max_health <= 0.0 or u.current_health >= u.max_health - 0.01:
			continue
		var frac: float = u.current_health / u.max_health
		if frac < best_frac:
			best_frac = frac
			best = u
	heal_target = best
	if best == null:
		# ЛЕЧИТЬ НЕКОГО — СНИМАЕМ ЭФФЕКТ СРАЗУ, а не по догорающему таймеру:
		# «как только монах прекращает лечение, VFX мгновенно отключается»
		_stop_heal_vfx()
		return
	var amount: float = best.max_health * _MCfg.MONK_HEAL_TICK / _MCfg.MONK_HEAL_SEC_PER_MAN
	var before: float = best.current_health
	best.current_health = minf(best.max_health, best.current_health + amount)
	healed_total += best.current_health - before
	# Строка ядра и полоска здоровья узнают о лечении тем же путём, что у
	# перка «кровь за кровь» (GameManager.credit_kill)
	best._soa_push_stats()
	_play_attack_anim("heal", int(_MCfg.MONK_HEAL_TICK * 1000.0) + 120)
	_bind_heal_vfx(best)

# ═════════════════════════════════════════════════════════════════════════════
# VFX ЛЕЧЕНИЯ ЖИВЁТ НА ИСЦЕЛЯЕМОМ, А НЕ НА МОНАХЕ
# ═════════════════════════════════════════════════════════════════════════════
# Заказ владельца: пока монах поддерживает лечение, поверх ЦЕЛИ крутится
# зацикленный `Heal_Effect.png`; как только лечение прекратилось — цель
# вылечена, монах переключился на другую, монах погиб или отошёл — эффект
# МГНОВЕННО снимается с юнита.
#
# ── УЗЕЛ ОДИН НА МОНАХА, А ПРИВЯЗКА — ПОЛЕ ───────────────────────────────────
# Лечение идёт два раза в секунду (MONK_HEAL_TICK 0.5), и заводить квад на
# каждый такт значило бы два узла в секунду на монаха до конца партии. Поэтому
# узел один и переиспользуется, а «эффект на юните» выражается ПРИВЯЗКОЙ
# (`_heal_vfx_target`): снять эффект с юнита — это разорвать привязку и спрятать
# квад, и снаружи это ровно то же самое, что удалить его. Совсем освобождается
# узел только вместе с монахом (_exit_tree).
#
# ── ЕДЕТ ЗА ЦЕЛЬЮ КАЖДЫЙ ТИК, А НЕ РАЗ В ТАКТ ────────────────────────────────
# Прежняя версия ставила точку ОДИН РАЗ на такт лечения: раненый успевал уйти
# на метр-полтора, и эффект оставался висеть у него за спиной. Точка берётся
# НАРИСОВАННАЯ (draw_position) — та же, по которой едут знамёна: логическая
# точка скачет на толчках и разлёте, а сглаженная совпадает со спрайтом.
#
# ── ВЫСОТА — ЦЕНТР МАССЫ ЦЕЛИ ───────────────────────────────────────────────
# Берётся `aim_height()` — то же число, по которому целятся лучники. Своей
# константы здесь заводить нельзя: у тролля центр массы на 2.7 м, у пехотинца
# на 0.8, и общая цифра повесила бы заклинание либо в ноги, либо в небо

## Общая лента эффекта: её берут фракции, у которых своей в цветовой папке нет
const HEAL_VFX_FALLBACK := "res://assets/factions/humans/units/Heal_Effect.png"
## Размер квада эффекта в метрах и темп ленты
const HEAL_VFX_SIZE_M := 1.6
const HEAL_VFX_FPS := 12.0
## Насколько эффект переживает последний такт лечения. Ноль был бы миганием:
## лечение идёт ТАКТАМИ, и между двумя тактами монах формально «не лечит».
## Окно чуть шире такта — это и есть «непрерывно, пока идёт процесс»
const HEAL_VFX_GRACE := 0.25

var _heal_vfx: MeshInstance3D = null
## На ком сейчас висит эффект. null — ни на ком
var _heal_vfx_target: Unit = null
var _heal_vfx_left: float = 0.0

## ── ДЛЯ СТЕНДОВ ───────────────────────────────────────────────────────────
## На ком висит эффект прямо сейчас (null — ни на ком). Спрашивается СВОЙСТВО,
## а не «есть ли узел»: узел переиспользуется и живёт дольше одного лечения
func heal_vfx_target() -> Node3D:
	if _heal_vfx == null or not is_instance_valid(_heal_vfx):
		return null
	if not _heal_vfx.visible:
		return null
	return _heal_vfx_target

## Сам узел эффекта (может быть null, пока монах ещё никого не лечил)
func heal_vfx_node() -> Node3D:
	return _heal_vfx if is_instance_valid(_heal_vfx) else null

## Привязать эффект к цели. Идемпотентно: повторный такт по той же цели только
## продлевает окно, переезд на другую — переносит квад
func _bind_heal_vfx(target: Unit) -> void:
	if target == null or not is_instance_valid(target):
		_stop_heal_vfx()
		return
	if _heal_vfx == null or not is_instance_valid(_heal_vfx):
		_heal_vfx = _build_heal_vfx()
	if _heal_vfx == null:
		return
	_heal_vfx_target = target
	_heal_vfx_left = _MCfg.MONK_HEAL_TICK + HEAL_VFX_GRACE
	_heal_vfx.visible = true
	_place_heal_vfx()

## Снять эффект с юнита. Мгновенно и без следа: привязки нет, квад невидим
func _stop_heal_vfx() -> void:
	_heal_vfx_target = null
	_heal_vfx_left = 0.0
	if _heal_vfx != null and is_instance_valid(_heal_vfx):
		_heal_vfx.visible = false

## Поставить квад в центр массы цели по НАРИСОВАННОЙ точке
func _place_heal_vfx() -> void:
	if _heal_vfx == null or not is_instance_valid(_heal_vfx):
		return
	if _heal_vfx_target == null or not is_instance_valid(_heal_vfx_target):
		return
	var p: Vector3 = _heal_vfx_target.draw_position()
	_heal_vfx.global_position = Vector3(p.x,
		p.y + _heal_vfx_target.aim_height(), p.z)

## Такт эффекта: едет за целью и гаснет, как только лечить эту цель перестали.
## Зовётся из tick_physics монаха — своего тика узел не заводит (то же правило,
## что у торчащих стрел и тел павших: декорация не платит нотификацией движка)
func _ride_heal_vfx() -> void:
	if _heal_vfx_target == null:
		return
	# ── ПРИЧИНЫ ПРЕКРАЩЕНИЯ, ВСЕ ЧЕТЫРЕ ИЗ ЗАКАЗА ──────────────────────────
	# Цель исчезла или погибла; цель ушла в гарнизон; цель ВЫЛЕЧЕНА до конца;
	# монах отошёл дальше радиуса лечения. Пятая («переключился на другую»)
	# обрабатывается сама — _bind_heal_vfx переносит квад
	var t: Unit = _heal_vfx_target
	if not is_instance_valid(t) or t.is_dead() or t.garrisoned:
		_stop_heal_vfx()
		return
	if t.max_health > 0.0 and t.current_health >= t.max_health - 0.01:
		_stop_heal_vfx()
		return
	if global_position.distance_to(t.global_position) > _MCfg.MONK_HEAL_RADIUS:
		_stop_heal_vfx()
		return
	_heal_vfx_left -= get_physics_process_delta_time()
	if _heal_vfx_left <= 0.0:
		_stop_heal_vfx()
		return
	_place_heal_vfx()

func _build_heal_vfx() -> MeshInstance3D:
	var folder: String = GameManager.unit_sprite_folder(faction, "monk")
	var path: String = folder + "/Heal_Effect.png"
	# ЗАПАСНОЙ ПУТЬ — ОБЩАЯ ЛЕНТА: у части цветовых папок своего эффекта нет,
	# а проверять каталоги перебором нельзя (правило 8, PCK регистрозависим)
	if folder.is_empty() or not ResourceLoader.exists(path):
		path = HEAL_VFX_FALLBACK
	if not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	if tex == null:
		return null
	var q := QuadMesh.new()
	q.size = Vector2(HEAL_VFX_SIZE_M, HEAL_VFX_SIZE_M)
	# Число кадров ВЫВОДИТСЯ из пропорций листа, а не стоит числом: лист
	# (2112×192 = 11 кадров) могут перерисовать, и забытая константа дала бы
	# рваную анимацию
	var sz: Vector2 = tex.get_size()
	var frames: float = maxf(round(sz.x / maxf(sz.y, 1.0)), 1.0)
	var mat: ShaderMaterial = _BBUtilM.make_material(tex, Color.WHITE, 0.05, HEAL_VFX_FPS)
	mat.set_shader_parameter("frame_count", frames)
	# Поверх бойца, а не под ним: это не наземная декорация, а заклинание над
	# головой — глубина по точке на земле ей не нужна
	mat.set_shader_parameter("ground_depth", 0.0)
	mat.render_priority = 6
	q.material = mat
	var mi := MeshInstance3D.new()
	mi.name = "HealVFX"
	mi.mesh = q
	mi.visible = false
	# УЗЕЛ ЖИВЁТ В МИРЕ, А НЕ РЕБЁНКОМ ЦЕЛИ: ребёнок ехал бы по ЛОГИЧЕСКОЙ
	# точке, а спрайт — по сглаженной (та же грабля, на которой обжигались
	# жёлтые кольца выделения и знамёна)
	var root: Node = GameManager.main.world_root() if GameManager.main != null else get_parent()
	if root == null:
		return null
	root.add_child(mi)
	return mi

## СМЕРТЬ МОНАХА ГАСИТ ЭФФЕКТ В ТОТ ЖЕ КАДР, а не на выходе из дерева:
## освобождение узла отложено (queue_free), и между гибелью и уходом со сцены
## заклинание светилось бы над уже брошенным раненым
func _die() -> void:
	_stop_heal_vfx()
	super._die()

## Монах уходит со сцены — эффект уходит с ним. Узел лежит в МИРЕ, и без этого
## он остался бы висеть над последним исцелённым до конца партии
func _exit_tree() -> void:
	_stop_heal_vfx()
	if _heal_vfx != null and is_instance_valid(_heal_vfx):
		# ── ЗДЕСЬ НЕЛЬЗЯ remove_child, И ЭТО ПОЙМАЛ СТЕНД ──────────────────
		# Правило 6 («remove_child перед queue_free») писано для случая, когда
		# детей контейнера считают В ТОМ ЖЕ КАДРЕ. Но приходим мы сюда из
		# _exit_tree, то есть когда движок УЖЕ ПЕРЕСТРАИВАЕТ ДЕРЕВО, и он
		# отбивает правку списка детей: «Parent node is busy adding/removing
		# children». Та же грабля, что у укладки упавшего знамени, только там
		# отбивался add_child.
		# Видимым узел при этом не остаётся ни на кадр: _stop_heal_vfx выше уже
		# его погасил, а освобождение доедет концом кадра
		_heal_vfx.queue_free()
	_heal_vfx = null
	super._exit_tree()
