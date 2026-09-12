extends Unit

## ═══════════════════════════════════════════════════════════════════════════
## ТРОЛЛЬ — БОСС ЛОГОВА (заказ владельца, 09.09.2026)
## ═══════════════════════════════════════════════════════════════════════════
## Обычный Unit третьей стороны (гоблины), и почти всё у него от базы: бой,
## движение, туман, общая отрисовка, вспышка попадания, тело на поле. Своего
## здесь ровно пять вещей, и каждая — переопределение, а не развилка в Unit:
##   • РАЗМЕР — примерно вчетверо крупнее копейщика (goblin_config.TROLL_*);
##   • ЦИКЛ ДУБИНЫ И ОДЫШКИ — TROLL_SWINGS ударов подряд, потом TROLL_REST_SEC
##     секунд «Out of Breath» (лента Recovery): не бьёт и не идёт;
##   • РАЗГОН — тот же таран, что у кабанов (charge_* в STATS["troll"]), с
##     замахом (лента Windup) на входе в разгон и брызгами от удара;
##   • ПОЛОВИНА ЗАПАСА — из логова выходят TROLL_REINFORCE_COUNT троллей;
##   • ЦЕНА СМЕРТИ — нападавшим отрядам засчитывается TROLL_KILL_WORTH убийств
##     (три полных отряда копейщиков), пропорционально нанесённому урону.
## Патрулирует кольцо вокруг логова, отвечает на удар и авто-агро как все.
## Вожак орды (GoblinAI) троллей НЕ водит — они стражи, а не волна.
##
## Файл без class_name: подключается через preload/load.

const _SSParser := preload("res://scripts/SpriteSheetParser.gd")
const _GobCfgT  := preload("res://scripts/goblin/goblin_config.gd")

const SHEET_DIR := "res://assets/factions/orc/Troll/"
## Ключи idle/walk/attack — те, что знает базовый автомат внешности.
## death — лента гибели (кадр для тела на поле), recovery — одышка, windup —
## замах перед тараном
const SHEETS := {
	"idle":     "Troll_Idle.png",
	"walk":     "Troll_Walk.png",
	"attack":   "Troll_Attack.png",
	"windup":   "Troll_Windup.png",
	"recovery": "Troll_Recovery.png",
	"death":    "Troll_Dead.png",
}

## Логово, которое тролль охраняет (TrollLair). Null — вольный тролль
var lair: Node3D = null

var _swings: int = 0
var _winded_until_ms: int = 0
var _patrol_t: float = 0.0
## ── РЫК (спринт 18) ──────────────────────────────────────────────────────
## Выход из пня: гарантированный рык через _spawn_growl_t (разнесён по
## троллям, чтобы три стража не рычали одним кадром в одно окно категории);
## марш: раз в TROLL_GROWL_MIN..MAX секунд хода с шансом TROLL_GROWL_MARCH_P;
## бой: редкие подрыкивания при ударах (_shout_chance). Слышимость — общие
## правила play_3d: логово в тумане молчит
var _spawn_growl_t: float = -1.0
var _growl_t: float = 0.0
var growls: int = 0                 # для стендов: сколько рыков запрошено
var _was_charging: bool = false
var _reinforced: bool = false
## «Стандартная» подмога на трети запаса действует только у троллей бонусной
## пары (ставит логово); первую группу поднимает агро-вызов (TrollLair.on_guard_hit)
var standard_reinforce: bool = false
## Скорость без боевого множителя (из конфига) — в бою ×TROLL_COMBAT_SPEED_MULT
var _base_move_speed: float = 0.0
## sid → нанесённый урон: по нему делится цена смерти
var _dmg_by_squad: Dictionary = {}
var _dmg_total: float = 0.0

## ── ГОЛОД: ТРОЛЛЬ ЕСТ ОВЕЦ ЛОГОВА (заказ владельца, 10.09.2026) ─────────────
## Раз в TROLL_HUNGER_SEC (или когда стадо больше TROLL_HUNGRY_FLOCK) тролль
## в покое идёт к ближайшей овце, у неё замахивается дубиной (та же лента
## удара), хрустит (звук nom_nom) — овца исчезает, тролль лечится на долю
## TROLL_EAT_HEAL. Бой важнее обеда: цель атаки снимает обед. Патруль на
## время обеда не трогается
var _hunger_t: float = 0.0
var _meal: Node3D = null
var _meal_t: float = 0.0
var meals_eaten: int = 0
var meal_sound_tries: int = 0
var meal_sound_ok: int = 0
var last_meal_heal: float = 0.0

func force_hunger() -> void:
	_hunger_t = 0.0

func is_hungry() -> bool:
	return _hunger_t <= 0.0

func hunger_left() -> float:
	return _hunger_t

## true — занят обедом (идёт к овце или ест), патруль пропускается
func _tick_hunger(delta: float) -> bool:
	_hunger_t -= delta
	if _meal != null:
		if not is_instance_valid(_meal) or bool(_meal.get("eaten")):
			_meal = null
		elif attack_target != null:
			_meal = null
		else:
			var d: Vector3 = _meal.global_position - global_position
			d.y = 0.0
			if d.length() <= _GobCfgT.TROLL_EAT_RANGE:
				_eat(_meal)
				return true
			_meal_t -= delta
			if _meal_t <= 0.0 or state == State.IDLE:
				_meal_t = 1.0
				command_move(GameManager.land_target(_meal.global_position))
			return true
	if state != State.IDLE or attack_target != null or lair == null or not is_instance_valid(lair):
		return false
	if not lair.has_method("nearest_sheep"):
		return false
	var flock: int = int(lair.call("sheep_alive"))
	if flock <= 0:
		return false
	if _hunger_t > 0.0 and flock <= _GobCfgT.TROLL_HUNGRY_FLOCK:
		return false
	var s: Node3D = lair.call("nearest_sheep", global_position) as Node3D
	if s == null:
		return false
	_meal = s
	_meal_t = 1.0
	command_move(GameManager.land_target(s.global_position))
	return true

func _eat(s: Node3D) -> void:
	_play_attack_anim("attack", 600)
	meal_sound_tries += 1
	if AudioManager.play_3d("nom_nom", global_position):
		meal_sound_ok += 1
	s.call("eat")
	var before: float = current_health
	current_health = minf(max_health, current_health + max_health * _GobCfgT.TROLL_EAT_HEAL)
	last_meal_heal = current_health - before
	_soa_push_stats()
	_update_hp_bar()
	meals_eaten += 1
	_hunger_t = _GobCfgT.TROLL_HUNGER_SEC * randf_range(0.8, 1.2)
	_meal = null
	command_move(global_position)

func _ready() -> void:
	_apply_config_stats("troll")
	display_name = "Тролль"
	super._ready()
	_setup_visual()
	_patrol_t = randf_range(1.0, _GobCfgT.TROLL_PATROL_SEC)
	_hunger_t = _GobCfgT.TROLL_HUNGER_SEC * randf_range(0.5, 1.0)
	# Жребии рыка — из генератора звука (AudioManager.rng), а не из общего
	# потока партии: иначе рождение тролля сдвигало бы все жребии боя
	_spawn_growl_t = AudioManager.rng.randf_range(0.15, 1.4)
	_growl_t = AudioManager.rng.randf_range(_GobCfgT.TROLL_GROWL_MIN_SEC, _GobCfgT.TROLL_GROWL_MAX_SEC)
	_base_move_speed = move_speed

## ── ВНЕШНОСТЬ ──────────────────────────────────────────────────────────────
func _setup_visual() -> void:
	var asp: AnimatedSprite3D = _SSParser.build_sprite_from_map(
		SHEET_DIR, SHEETS, ["attack", "windup", "death"])
	if asp == null:
		push_warning("Troll: ленты не найдены в %s" % SHEET_DIR)
		return
	for child in get_children():
		if child is MeshInstance3D and child != selection_ring:
			child.visible = false
	_apply_troll_scale(asp)
	add_child(asp)
	_active_sprite = asp

## Тот же приём, что у гоблинов (_apply_goblin_scale): свой размер пикселя и
## центр спрайта ПО ЛЕНТЕ, чтобы ноги стояли на земле при любом масштабе
func _apply_troll_scale(asp: AnimatedSprite3D) -> void:
	asp.pixel_size = _GobCfgT.TROLL_PIXEL_SIZE
	var frames: SpriteFrames = asp.sprite_frames
	if frames == null or not frames.has_animation("idle"):
		return
	var first: Texture2D = frames.get_frame_texture("idle", 0)
	if first == null:
		return
	var at := first as AtlasTexture
	var fh: float = at.region.size.y if at != null else first.get_size().y
	if fh <= 0.0:
		return
	# Ступни — по плотной краске (TROLL_FOOT_ALPHA), а не по краю тени
	var pad: int = _anim_bottom_px(first, _GobCfgT.TROLL_FOOT_ALPHA)
	asp.position.y = (fh * 0.5 - float(pad)) * asp.pixel_size

## Личный габарит — вчетверо шире пехотинца (см. Unit.sep_radius)
func sep_radius() -> float:
	return SEP_MIN_DIST * _GobCfgT.TROLL_SIZE_SCALE

## Клик — по всему спрайту и кольцу у ног; кольцо крупнее (см. Unit)
func pick_body_h() -> float:
	return _GobCfgT.TROLL_PICK_BODY_H

func pick_radius() -> float:
	return _GobCfgT.TROLL_PICK_RADIUS

func ring_scale() -> float:
	return _GobCfgT.TROLL_RING_SCALE

## ── МЕТКА ПОД НОГАМИ: ОВАЛ БЕЗ ТЕНИ (заказ владельца 10.09.2026) ──────────
## Тени нет вовсе: тёмное пятно вчетверо шире пехотинца читалось как зелёный
## круг, приклеенный к траве. Кольцо — ОВАЛ и шире прежнего: под тушей в шесть
## метров круг выглядел уже её самой
func shadow_scale() -> float:
	return 0.0

func ring_oval() -> Vector2:
	return _GobCfgT.TROLL_RING_OVAL

## Стрелок целится в СЕРЕДИНУ ТУШИ, а не в точку на земле
func aim_height() -> float:
	return _GobCfgT.TROLL_AIM_HEIGHT

## ── СТРЕЛЫ В ТУШЕ БОЛЬШЕ НЕ ТОРЧАТ (заказ спринта 14) ─────────────────────
## Здесь жили ГНЁЗДА: до TROLL_ARROW_SOCKETS стрел и костей висели на спрайте,
## их точки вёл сам тролль в своём тике (стрела — не его узел и за ним не
## поедет). На экране это читалось как мусор, налипший на брюхо, — жалоба со
## скриншотом. Снято ЦЕЛИКОМ: `arrow_sockets()` отвечает нулём, и базовый путь
## попадания (`Arrow._strike`) даже не спрашивает про застревание.
##
## ПОЧЕМУ НУЛЬ, А НЕ УДАЛЁННЫЙ МЕТОД: `arrow_sockets()` — виртуал базы, и
## пехота платит за него ОДНО сравнение числа. Ноль означает «мест нет
## вовсе», то есть ровно требуемое поведение, и второй развилки в стреле
## заводить не нужно.
func arrow_sockets() -> int:
	return 0

## ── ТОНКИЙ ОВАЛ ВМЕСТО ТОЛСТЫХ ДУГ ────────────────────────────────────────
## Радиус в МЕТРАХ для 64-сегментного меша обвода; ноль у пехоты означает
## «рисовать обычным кольцом бойца» (см. Unit.fine_ring_radius)
func fine_ring_radius() -> float:
	return _GobCfgT.TROLL_FINE_RING_R

## ── ДИСПЕРСИЯ ПО ТУШЕ ─────────────────────────────────────────────────────
## Доля выстрелов, уходящая в землю рядом, и её разброс (см. Unit)
func aim_miss_chance() -> float:
	return _GobCfgT.TROLL_AIM_MISS_CHANCE

func aim_miss_spread() -> float:
	return _GobCfgT.TROLL_AIM_MISS_SPREAD

## ── ТЕЛО ТРОЛЛЯ — ВЕРТИКАЛЬНЫЙ БИЛБОРД, А НЕ КВАД ПЛАШМЯ (10.09.2026) ────
## Лента Troll_Dead уже НАРИСОВАНА лежащей (в перспективе, со своей тенью).
## Общий слой тел кладёт квад плашмя и крутит вокруг вертикали — лежащий
## рисунок ложился бы на бок ещё раз, а квад в 11.8 м на волнистом рельефе
## (±0.85 м) уходил в грунт: это и был «обрезанный спрайт» со скриншота.
## Тролль гибнет единицы раз за партию, поэтому у него свой узел: билборд по
## правилам декораций (cyl_billboard, глубина по точке на земле), ДОИГРЫВАЕТ
## ленту гибели кадр за кадром и замирает на последнем. ПАДАЕТ ПРОЧЬ ОТ
## УДАРА: голова в кадре смотрит влево; если обидчик стоял слева по экрану,
## лента зеркалится — тролль валится в сторону от него. Лента обрезана по
## строкам рисунка: у декорации низ квада лежит на грунте по построению, а
## пустое поле под ступнями (88 px = 2.7 м) поднимало бы тело в воздух
const DEATH_FPS := 8.0
const DEATH_LIFE_SEC := 900.0     # как у тел общего слоя (CorpseRenderer.LIFE_SEC)
const CORPSE_NAME := "TrollCorpse"
var _last_hit_from: Vector3 = Vector3.INF

func _falls_screen_right() -> bool:
	if _last_hit_from.x == INF:
		return false
	var right := Vector3.RIGHT
	if is_inside_tree():
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			right = cam.global_transform.basis.x
	var away: Vector3 = global_position - _last_hit_from
	return away.x * right.x + away.z * right.z > 0.0

func _leave_corpse() -> void:
	var main = GameManager.main
	if main == null:
		return
	var tex := load(SHEET_DIR + String(SHEETS["death"])) as Texture2D
	var img: Image = tex.get_image() if tex != null else null
	if img == null:
		super._leave_corpse()
		return
	var h: int = img.get_height()
	var frames: int = maxi(img.get_width() / maxi(h, 1), 1)
	var fw: int = img.get_width() / frames
	var top: int = h
	var bot: int = 0
	for f in range(frames):
		var r: Rect2i = img.get_region(Rect2i(f * fw, 0, fw, h)).get_used_rect()
		if r.size.y <= 0:
			continue
		top = mini(top, r.position.y)
		bot = maxi(bot, r.end.y)
	if bot <= top:
		super._leave_corpse()
		return
	var mirror: bool = _falls_screen_right()
	var ch: int = bot - top
	var texs: Array = []
	for f2 in range(frames):
		var fr: Image = img.get_region(Rect2i(f2 * fw, top, fw, ch))
		if mirror:
			fr.flip_x()
		texs.append(ImageTexture.create_from_image(fr))
	var px: float = _GobCfgT.TROLL_PIXEL_SIZE
	var q := QuadMesh.new()
	q.size = Vector2(float(fw) * px, float(ch) * px)
	# Туша краснеет (заказ спринта 15: «усилить красный оттенок при смерти»)
	var mat: ShaderMaterial = _BBUtil.make_material(texs[0], _GobCfgT.TROLL_DEATH_TINT, 0.5, 0.0)
	mat.set_shader_parameter("frame_count", 1.0)
	mat.set_shader_parameter("frame_fps", 0.0)
	q.material = mat
	var mi := MeshInstance3D.new()
	mi.name = CORPSE_NAME
	mi.mesh = q
	# ── ПАДАЕТ ПОД РАЗНЫМИ УГЛАМИ (заказ владельца 10.09.2026) ────────────
	# Туша валилась строго вертикально, и лежащий тролль читался как стоящий.
	# Квад ставится в МИРОВОЙ ориентации (world_fixed у материала — ракурс
	# камеры в игре зафиксирован намертво) и КРЕНИТСЯ вокруг оси взгляда: сам
	# рисунок при этом не трогается вовсе, поэтому обрезок текстуры нет.
	# Угол — от точки гибели, а не через randf(): два прогона одного боя
	# обязаны дать одну картину
	var dp: Vector3 = global_position
	var tilt: float = (fposmod(sin(dp.x * 12.9898 + dp.z * 78.233) * 43758.5453, 1.0)
		- 0.5) * 2.0 * _GobCfgT.TROLL_DEATH_TILT
	if mirror:
		tilt = -tilt
	mat.set_shader_parameter("world_fixed", 1.0)
	mi.rotation_degrees = Vector3(0.0, 0.0, tilt)
	mi.set_meta("tilt", tilt)
	mi.set_meta("mirror", mirror)
	mi.set_meta("frames", frames)
	mi.set_meta("frame", 0)
	var gp: Vector3 = global_position
	var gy: float = GameManager.get_terrain_height(gp.x, gp.z)
	main.world_root().add_child(mi)
	mi.global_position = Vector3(gp.x, gy + q.size.y * 0.5, gp.z)
	# Кадры листает свой таймер под узлом тела: лента идёт с НУЛЕВОГО кадра
	# (шейдерные часы TIME общие и с момента гибели не отсчитываются), а
	# узел тролля к следующему кадру уже освобождён — корутина на нём умерла бы
	var tm := Timer.new()
	tm.wait_time = 1.0 / DEATH_FPS
	tm.one_shot = false
	mi.add_child(tm)
	var step: Array = [0]
	tm.timeout.connect(func():
		step[0] += 1
		if step[0] >= texs.size():
			tm.stop()
			return
		mat.set_shader_parameter("albedo_tex", texs[step[0]])
		mi.set_meta("frame", step[0]))
	tm.start()
	var life := Timer.new()
	life.wait_time = DEATH_LIFE_SEC
	life.one_shot = true
	mi.add_child(life)
	life.timeout.connect(func():
		if is_instance_valid(mi):
			mi.queue_free())
	life.start()

## Тело на поле — последний кадр ленты гибели, а не поза покоя
func corpse_frame() -> Array:
	if not _look_ok:
		_look_bind()
	var row: Variant = _look_table.get("death")
	if row != null:
		var r: Array = row
		return [r[0], maxi(int(r[1]) - 1, 0), int(r[1]), _look_px, _sprite_base_y]
	return super.corpse_frame()

## Рык: выход из пня — гарантированный; марш — редкий с шансом
func _tick_growl(delta: float) -> void:
	if _spawn_growl_t >= 0.0:
		_spawn_growl_t -= delta
		if _spawn_growl_t < 0.0:
			growls += 1
			AudioManager.play_3d("troll_growl", global_position)
		return
	if not moved_recently():
		return
	_growl_t -= delta
	if _growl_t > 0.0:
		return
	_growl_t = AudioManager.rng.randf_range(_GobCfgT.TROLL_GROWL_MIN_SEC, _GobCfgT.TROLL_GROWL_MAX_SEC)
	if AudioManager.rng.randf() < _GobCfgT.TROLL_GROWL_MARCH_P:
		growls += 1
		AudioManager.play_3d("troll_growl", global_position)

## Подрыкивание в бою — тот же рык, редкий (вероятность на удар)
func _sfx_shout() -> String:
	return "troll_growl"

func _shout_chance() -> float:
	return _GobCfgT.TROLL_GROWL_FIGHT_P

## Тролль не кричит человеческим голосом и на смерти: у его туши свой звук
## не заказан — предсмертный человеческий стон снят
func _sfx_death() -> String:
	return "troll_growl"

func _sfx_swing() -> String:
	return "sword_attack"

func _sfx_hit() -> String:
	return "sword_hit"

## ── ОДЫШКА ─────────────────────────────────────────────────────────────────
func is_winded() -> bool:
	return now_ms < _winded_until_ms

## Пока отдыхает — не бьёт (таймер удара зажимается в ноль, см. Unit)
func _may_strike_now() -> bool:
	return not is_winded()

## УДАР ДУБИНОЙ: серия из TROLL_SWINGS, затем одышка. Дубина бьёт ДУГОЙ ПЕРЕД
## СПРАЙТОМ (заказ 09.09.2026): не больше TROLL_SWEEP_COUNT ближайших чужих в
## секторе TROLL_SWEEP_ARC_COS от взгляда и не дальше длины дубины. Каждый
## накрытый получает урон, ОТЛЕТАЕТ (apply_knockback — тот же канал, что у
## тяжёлой конницы) и ЛЕЖИТ TROLL_KNOCKDOWN_SEC сбитым с ног. Назначенная
## цель получает урон штатным путём (возврат), остальные здесь; сбивание и
## отлёт — всем шести, включая цель
## ЗАМАХ — СЕЙЧАС, КАСАНИЕ — ЧЕРЕЗ TROLL_SWING_HIT_SEC (разбор у константы).
## Базовый удар по цели тоже отложен (см. _damage_on_strike): иначе цель
## получала бы урон в начале замаха, а соседи — в конце
var _swing_left: float = 0.0
var _swing_look: Vector3 = Vector3.FORWARD
var _swing_dmg: float = 0.0
var _swing_target: Node3D = null

func _damage_on_strike() -> bool:
	return false   # урон списывает _release_swing, синхронно с касанием

## ── СЕРИЯ ПРИВЯЗАНА К ЦЕЛИ (спринт 16) ─────────────────────────────────────
## Заказ: «[1] → [2] → [3] → одышка; перебежал к новой цели — серия заново».
## Смена цели между ударами обнуляет счёт: бить новую цель «третьим» ударом
## с одышкой сразу после — не серия, а обрывок
var _series_target: Node3D = null

func _strike_damage() -> float:
	var tgt_now: Node3D = attack_target as Node3D
	if tgt_now != _series_target:
		_series_target = tgt_now
		_swings = 0
	_swings += 1
	var dmg: float = attack_damage * _GobCfgT.TROLL_SWEEP_DMG_MULT
	_play_attack_anim("attack", 600)
	var mp: Vector3 = global_position
	var tgt := attack_target as Node3D
	var look: Vector3 = _facing
	if tgt != null and is_instance_valid(tgt):
		var to: Vector3 = tgt.global_position - mp
		to.y = 0.0
		if to.length_squared() > 1e-4:
			look = to.normalized()
	if look.length_squared() < 1e-6:
		look = Vector3.FORWARD
	# ── СВЯЗКА: ПОЛШАГА К ЦЕЛИ НА КАЖДЫЙ УДАР ────────────────────────────
	# Тем же плавным каналом, что у отлёта (push_smooth): шаг проходит через
	# проверку чужих тел, в строй он не въезжает
	push_smooth(look, _GobCfgT.TROLL_SWING_STEP, true)
	_swing_look = look
	_swing_dmg = dmg
	_swing_target = tgt
	_swing_left = _GobCfgT.TROLL_SWING_HIT_SEC
	if _swings >= _GobCfgT.TROLL_SWINGS:
		_swings = 0
		_start_rest()
	return dmg

## Дубина коснулась: урон цели и дуге, отлёт и падение накрытых
func _release_swing() -> void:
	_swing_left = 0.0
	if state == State.DEAD:
		return
	var mp: Vector3 = global_position
	var look: Vector3 = _swing_look
	var dmg: float = _swing_dmg
	var tgt: Node3D = _swing_target if (_swing_target != null
		and is_instance_valid(_swing_target)) else null
	_swing_target = null
	var reach: float = attack_range + _GobCfgT.TROLL_SWEEP_REACH_PAD
	var hit: Array = []      # [dist, Unit]
	for n in GameManager.unit_grid.query_radius(mp, reach):
		if n == null or not is_instance_valid(n):
			continue
		var v := n as Unit
		if v == null or v.is_dead() or v.faction == faction:
			continue
		var off: Vector3 = v.global_position - mp
		off.y = 0.0
		var d: float = off.length()
		if d > reach:
			continue
		if d > 0.2 and (off.x * look.x + off.z * look.z) / d < _GobCfgT.TROLL_SWEEP_ARC_COS:
			continue
		hit.append([d, v])
	hit.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var n_hit: int = mini(hit.size(), _GobCfgT.TROLL_SWEEP_COUNT)
	last_sweep_count = n_hit
	last_sweep_look = look
	last_sweep_units.clear()
	var tgt_hit: bool = false
	if n_hit > 0:
		_note_hit_landed()
	for k in range(n_hit):
		var v: Unit = hit[k][1]
		last_sweep_units.append(v)
		if not is_instance_valid(v) or v.is_dead():
			continue
		if v == tgt:
			tgt_hit = true
			v.take_damage(dmg, self)
		else:
			v.take_damage(dmg * _GobCfgT.TROLL_SPLASH_FRAC, self)
		if not is_instance_valid(v) or v.is_dead():
			continue
		var off2: Vector3 = v.global_position - mp
		off2.y = 0.0
		var dirn: Vector3 = off2.normalized() if off2.length_squared() > 1e-4 else look
		v.apply_knockback(dirn, _GobCfgT.TROLL_SWEEP_KNOCKBACK, mp)
		v.knock_down(_GobCfgT.TROLL_KNOCKDOWN_SEC)
	# Цель, не попавшая в дугу (отошла на шаг), всё равно получает удар, если
	# дубина до неё достаёт: так было и до синхронизации
	if not tgt_hit and tgt != null:
		var tu := tgt as Unit
		if tu != null and not tu.is_dead() \
				and mp.distance_to(tu.global_position) <= reach:
			tu.take_damage(dmg, self)
		# ── ПОСТРОЙКА ПОД ДУБИНОЙ (спринт 19, письмо 10) ─────────────────
		# Дуга ищет по сетке БОЙЦОВ, а здание в ней не состоит: приказ «сломай
		# дом» принимался, тролль подходил и махал — а урона не было вовсе.
		# Стена цели — по рисунку (ring_radius), как у любого удара по зданию
		var tb := tgt as Building
		if tb != null and not tb.is_dead() and may_attack_building(tb) \
				and mp.distance_to(tb.global_position) <= reach + tb.ring_radius():
			tb.take_damage(dmg, self)

var last_sweep_count: int = 0
var last_sweep_units: Array = []
var last_sweep_look: Vector3 = Vector3.FORWARD

## Топтание при таране (см. Unit._charge_impact)
func _trample_count() -> int:
	return _GobCfgT.TROLL_TRAMPLE_COUNT

## Вспышка слабее общей, кровь пятнами (см. goblin_config)
func hit_flash_peak() -> float:
	return _GobCfgT.TROLL_FLASH_PEAK

func hit_flash_color() -> Color:
	return _GobCfgT.TROLL_FLASH_COLOR

func blood_spots() -> float:
	return _GobCfgT.TROLL_BLOOD_SPOTS

## Такт расталкивания кольца
var _shove_t: float = 0.0

## Сколько чужих стоит в пределах дубины (кольцо вокруг тролля)
func _foes_around() -> int:
	var mp: Vector3 = global_position
	var reach: float = attack_range + _GobCfgT.TROLL_SWEEP_REACH_PAD
	var n := 0
	for u in GameManager.unit_grid.query_radius(mp, reach):
		if u == null or not is_instance_valid(u):
			continue
		var v := u as Unit
		if v == null or v.is_dead() or v.faction == faction:
			continue
		n += 1
	return n

## РАЗДВИНУТЬ КОЛЬЦО. Не удар и не урон: всех чужих в пределах дубины сдвигает
## НАРУЖУ на TROLL_SHOVE_PUSH тем же каналом скорости, что у конницы
## (apply_knockback) — то есть плавно и с проверкой чужих тел
func _shove_ring() -> void:
	var mp: Vector3 = global_position
	var reach: float = attack_range + _GobCfgT.TROLL_SWEEP_REACH_PAD
	for u in GameManager.unit_grid.query_radius(mp, reach):
		if u == null or not is_instance_valid(u):
			continue
		var v := u as Unit
		if v == null or v.is_dead() or v.faction == faction:
			continue
		var off: Vector3 = v.global_position - mp
		off.y = 0.0
		var d: float = off.length()
		var dirn: Vector3 = off / d if d > 0.05 else Vector3(cos(float(v.get_instance_id() % 360)), 0.0, sin(float(v.get_instance_id() % 360)))
		v.apply_knockback(dirn, _GobCfgT.TROLL_SHOVE_PUSH, mp)

func _start_rest() -> void:
	var ms: int = int(_GobCfgT.TROLL_REST_SEC * 1000.0)
	_winded_until_ms = now_ms + ms
	_play_attack_anim("recovery", ms)

## ── ТИК: ОДЫШКА СТОИТ НА МЕСТЕ, ПАТРУЛЬ, ЗАМАХ НА РАЗГОНЕ ──────────────────
func tick_physics(delta: float, prof: bool = false, bm: bool = true,
		bonus_ver: int = -1) -> void:
	# Отложенное касание дубины идёт и на одышке: замах начат до неё
	if _swing_left > 0.0:
		_swing_left -= delta
		if _swing_left <= 0.0:
			_release_swing()
	if is_winded():
		# Стоит и дышит: ни шага, ни удара. Окно замера движения тикает,
		# иначе зеркало и анимация ходьбы застыли бы на последнем шаге
		_sample_movement()
		# ОДЫШКА — НЕ СТУПОР: тролль стоит на месте, но продолжает
		# расталкивать сомкнувшееся вокруг кольцо (заказ 10.09.2026), а
		# торчащие стрелы едут с тушей
		_shove_t -= delta
		if _shove_t <= 0.0 and _foes_around() >= _GobCfgT.TROLL_SURROUND_FOES:
			_shove_t = _GobCfgT.TROLL_SHOVE_SEC
			_shove_ring()
		return
	super.tick_physics(delta, prof, bm, bonus_ver)
	if state == State.DEAD:
		return
	_tick_growl(delta)
	# Поводок погони (спринт 20): 10 с без удара — цель брошена, домой
	_tick_chase(delta)
	# Тролль из сохранённой партии рождается без логова — подхватываем
	# логово партии, чтобы патруль, подмога и месть работали и после загрузки
	if lair == null and GameManager.troll_lair != null \
			and is_instance_valid(GameManager.troll_lair):
		var nl: Node = GameManager.nearest_lair(global_position)   # логов два (спринт 18)
		lair = (nl if nl != null else GameManager.troll_lair) as Node3D
		if lair.has_method("adopt"):
			lair.call("adopt", self)
	# Замах — на входе в разгон (лента Windup), дальше базовый таран
	if is_charging and not _was_charging:
		_play_attack_anim("windup", 700)
	_was_charging = is_charging
	# В БОЮ БЫСТРЕЕ (заказ 10.09.2026): есть цель или разгон — ×1.2 к шагу,
	# патруль и обед — обычным темпом. Кэш скорости бойца читает move_speed
	# (Unit._base_speed), строку ядра обновляет тот же путь, что у лечения
	var want_speed: float = _base_move_speed * (_GobCfgT.TROLL_COMBAT_SPEED_MULT
		if (attack_target != null or is_charging) else 1.0)
	if _base_move_speed > 0.0 and not is_equal_approx(want_speed, move_speed):
		move_speed = want_speed
		_soa_push_stats()
	# ── ОКРУЖЕНИЕ НЕ ДЕРЖИТ ТРОЛЛЯ (заказ владельца 10.09.2026) ────────────
	# Жалоба: «при окружении копейщиками тролль застревает и замирает». Так и
	# было: шаг упирался в чужие тела со всех сторон (ArmyCore.ScanBlock), и
	# босс стоял в кольце, пока его пилили. Лечение — ДВА приёма, и оба нужны:
	#   1) пока вокруг смыкается кольцо, тролль ПРОБИВАЕТ тела шагом (тот же
	#      бит F_ORDER_PASS, что у билета игрока: чужое тело сужается до ядра);
	#   2) раз в TROLL_SHOVE_SEC он РАСТАЛКИВАЕТ всех вокруг на
	#      TROLL_SHOVE_PUSH метров — и делает это ДАЖЕ НА ОДЫШКЕ, поэтому
	#      «замер» на экране больше не читается: строй вокруг него ходит
	var foes: int = _foes_around()
	breaks_bodies = foes >= _GobCfgT.TROLL_SURROUND_FOES
	_shove_t -= delta
	if breaks_bodies and _shove_t <= 0.0:
		_shove_t = _GobCfgT.TROLL_SHOVE_SEC
		_shove_ring()
	# Рейд за чужими овцами (спринт 18): важнее обеда и патруля
	if _tick_raid(delta):
		return
	# Обед: голодный тролль идёт к овце (см. _tick_hunger); патруль ждёт
	if _tick_hunger(delta):
		return
	# Патруль кольца логова: только в покое и без цели
	if state == State.IDLE and attack_target == null and lair != null \
			and is_instance_valid(lair):
		_patrol_t -= delta
		if _patrol_t <= 0.0:
			_patrol_t = _GobCfgT.TROLL_PATROL_SEC
			var a: float = randf() * TAU
			var r: float = _GobCfgT.TROLL_PATROL_RADIUS * randf_range(0.4, 1.0)
			var p: Vector3 = lair.global_position + Vector3(cos(a) * r, 0.0, sin(a) * r)
			command_move(GameManager.land_target(p))

# ═════════════════════════════════════════════════════════════════════════════
# РЕЙД ЗА ОВЦАМИ (спринт 18, второе письмо)
# ═════════════════════════════════════════════════════════════════════════════
# У стороны (игрок или красный ИИ) больше TROLL_RAID_SHEEP овец — свободный
# тролль идёт к их стаду, съедает TROLL_RAID_EAT, берёт под пастьбу
# TROLL_RAID_HERD (Sheep.herd_by: привязка к загону снята, овца идёт за ним) и
# возвращается к пню, где отара становится его (TrollLair.adopt_sheep). По
# дороге ломает постройки в TROLL_RAID_SMASH_R, но КРЕПОСТЬ (ратушу) не
# трогает никогда — см. command_attack. Фазы: "go" → "eat" → "herd" → "home"
var _raid: Dictionary = {}
var _raid_check_t: float = 3.0
var _raid_cool_t: float = 0.0
var raids_done: int = 0             # стендам
var raid_eaten: int = 0
var raid_herded: int = 0
var is_dead_flag: bool = false       # для овец: пастух пал

func raid_phase() -> String:
	return String(_raid.get("phase", ""))

func _raid_faction_ready() -> int:
	for f in [Constants.FACTION_PLAYER, Constants.FACTION_ENEMY]:
		if GameManager.faction_sheep_count(f) > _GobCfgT.TROLL_RAID_SHEEP:
			return f
	return -1

func _owned_sheep_near(f: int, from: Vector3, radius: float) -> Node3D:
	var best: Node3D = null
	var bd: float = radius * radius
	for sh in get_tree().get_nodes_in_group("sheep"):
		if sh == null or not is_instance_valid(sh):
			continue
		if bool(sh.get("eaten")) or bool(sh.get("dead")) or sh.get("herder") != null:
			continue
		if int(sh.get("owner_faction")) != f or not bool(sh.call("is_owned")):
			continue
		var d: float = from.distance_squared_to((sh as Node3D).global_position)
		if d < bd:
			bd = d
			best = sh
	return best

func _tick_raid(delta: float) -> bool:
	_raid_cool_t -= delta
	if _raid.is_empty():
		_raid_check_t -= delta
		if _raid_check_t > 0.0 or _raid_cool_t > 0.0:
			return false
		_raid_check_t = _GobCfgT.TROLL_RAID_CHECK_SEC
		if state != State.IDLE or attack_target != null or lair == null or not is_instance_valid(lair):
			return false
		var f: int = _raid_faction_ready()
		if f < 0:
			return false
		var s0: Node3D = _owned_sheep_near(f, global_position, 1.0e5)
		if s0 == null:
			return false
		_raid = {"phase": "go", "faction": f, "eaten": 0, "herd": []}
		command_move(GameManager.land_target(s0.global_position))
		return true
	var f2: int = int(_raid["faction"])
	var phase: String = String(_raid["phase"])
	# Бой важнее: пока есть цель, рейд ждёт (кроме ратуши — её не трогаем).
	# Снос постройки (фаза smash) — тоже бой, и срок ему идёт здесь: вышел —
	# бросаем стену и уводим отару
	if attack_target != null:
		if phase == "smash":
			_raid["smash_t"] = float(_raid.get("smash_t", 0.0)) + delta
			if float(_raid["smash_t"]) > _GobCfgT.TROLL_RAID_SMASH_SEC:
				set_attack_target(null)
				_raid_gather(f2)
				return true
		return false
	match phase:
		"go", "eat":
			var s1: Node3D = _owned_sheep_near(f2, global_position, 60.0)
			if s1 == null:
				s1 = _owned_sheep_near(f2, global_position, 1.0e5)
				if s1 == null:
					_raid_finish(false)
					return true
			var d: Vector3 = s1.global_position - global_position
			d.y = 0.0
			if d.length() <= _GobCfgT.TROLL_EAT_RANGE:
				_raid["phase"] = "eat"
				_eat(s1)
				_raid["eaten"] = int(_raid["eaten"]) + 1
				raid_eaten += 1
				if int(_raid["eaten"]) >= _GobCfgT.TROLL_RAID_EAT:
					# Наелся — сперва СЛОМАТЬ ПОСТРОЙКУ у стада (письмо 10),
					# отара уводится после неё
					if not _raid_smash_start(f2):
						_raid_gather(f2)
				return true
			_smash_nearby(f2)
			if state == State.IDLE:
				command_move(GameManager.land_target(s1.global_position))
			return true
		"smash":
			# Наевшись — СЛОМАТЬ ПОСТРОЙКУ у стада (письмо 10): бой с ней ведёт
			# обычный автомат, рейд ждёт; снесена или вышел срок — уводим отару
			var tb = _raid.get("smash")
			var alive: bool = tb != null and is_instance_valid(tb) and not bool(tb.call("is_dead"))
			_raid["smash_t"] = float(_raid.get("smash_t", 0.0)) + delta
			if not alive or float(_raid["smash_t"]) > _GobCfgT.TROLL_RAID_SMASH_SEC:
				if not alive:
					raid_smashed += 1
				_raid_gather(f2)
				return true
			if attack_target == null:
				command_attack(tb as Node3D, true)
			return true
		"home":
			var lp: Vector3 = (lair as Node3D).global_position
			var dh: Vector3 = lp - global_position
			dh.y = 0.0
			if dh.length() <= _GobCfgT.TROLL_RAID_HOME_R:
				_raid_finish(true)
				return true
			if state == State.IDLE:
				command_move(GameManager.land_target(lp))
			return true
	return false

## Ближайшая постройка стороны у стада (кроме крепости) — под дубину.
## false — ломать нечего, отара уводится сразу
var raid_smashed: int = 0

func _raid_smash_start(f: int) -> bool:
	var best: Node3D = null
	var bd: float = _GobCfgT.TROLL_RAID_SMASH_SEEK * _GobCfgT.TROLL_RAID_SMASH_SEEK
	for b in GameManager.nodes_in_group_cached(Constants.building_group(f)):
		if b == null or not is_instance_valid(b) or not (b is Building):
			continue
		var bld := b as Building
		if bld.is_dead() or not may_attack_building(bld):
			continue
		var d: float = global_position.distance_squared_to(bld.global_position)
		if d < bd:
			bd = d
			best = bld
	if best == null:
		return false
	_raid["phase"] = "smash"
	_raid["smash"] = best
	_raid["smash_t"] = 0.0
	command_attack(best, true)
	return attack_target == best

## Взять под пастьбу TROLL_RAID_HERD ближайших овец стороны и идти домой
func _raid_gather(f: int) -> void:
	var herd: Array = []
	for _i in range(_GobCfgT.TROLL_RAID_HERD):
		var sh: Node3D = _owned_sheep_near(f, global_position, 60.0)
		if sh == null:
			break
		sh.call("herd_by", self)
		herd.append(sh)
	_raid["herd"] = herd
	raid_herded += herd.size()
	_raid["phase"] = "home"
	if lair != null and is_instance_valid(lair):
		command_move(GameManager.land_target((lair as Node3D).global_position))

## Дошли: отара — логову; сорвался (овец не стало) — просто домой
func _raid_finish(ok: bool) -> void:
	for sh in _raid.get("herd", []):
		if sh == null or not is_instance_valid(sh):
			continue
		# Отбитую по дороге овцу (рабочий перехватил, Sheep.captured_by
		# снял пастуха) логову не отдаём — она уже не в отаре
		if sh.get("herder") != self:
			continue
		sh.call("release_herd")
		if ok and lair != null and is_instance_valid(lair) and lair.has_method("adopt_sheep"):
			lair.call("adopt_sheep", sh)
	_raid = {}
	_raid_cool_t = _GobCfgT.TROLL_RAID_COOLDOWN_SEC
	raids_done += 1
	if ok and lair != null and is_instance_valid(lair) and lair.has_method("on_raid_success"):
		lair.call("on_raid_success")

## По дороге ломает постройки стороны в TROLL_RAID_SMASH_R — кроме ратуши
func _smash_nearby(f: int) -> void:
	var best: Node3D = null
	var bd: float = _GobCfgT.TROLL_RAID_SMASH_R * _GobCfgT.TROLL_RAID_SMASH_R
	for b in GameManager.nodes_in_group_cached(Constants.building_group(f)):
		if b == null or not is_instance_valid(b) or not (b is Building):
			continue
		var bld := b as Building
		if bld.is_dead() or (bld.has_method("is_stronghold") and bool(bld.call("is_stronghold"))):
			continue
		var d: float = global_position.distance_squared_to(bld.global_position)
		if d < bd:
			bd = d
			best = bld
	if best != null:
		command_attack(best, true)

## РАТУША НЕПРИКОСНОВЕННА (спринт 18): тролль ломает постройки, но крепость —
## никогда: ни по приказу логова, ни по агро, ни в рейде
## Троллю нельзя ни одну крепость (ни игрока, ни ИИ) — см. Unit.may_attack_building
func may_attack_building(b: Building) -> bool:
	if b == null or not is_instance_valid(b):
		return false
	return not (b.has_method("is_stronghold") and bool(b.call("is_stronghold")))

## ── УРОН: КТО СКОЛЬКО НАНЁС, И ПОЛОВИНА ЗАПАСА ──────────────────────────────
## Ответ на обстрел у тролля ведёт логово (TrollLair.on_guard_hit): общий
## отход к лагерю боссу не положен
func answers_far_fire() -> bool:
	return false

## ── МАЛЫЙ РАДИУС АГРО И ПОВОДОК ПОГОНИ (спринт 20, модуль 2.4) ─────────────
## Тролль реагирует на врага в TROLL_AGGRO_RADIUS, а не на весь обзор орды.
## Погоня — не дольше TROLL_CHASE_SEC без НАНЕСЁННОГО удара: цель
## сбрасывается, тролль возвращается к пню на патруль, и следующие
## TROLL_CHASE_COOL_SEC сам никого не берёт (иначе тот же враг в двенадцати
## метрах взводил бы погоню заново тем же тактом). Удар по нему в это окно
## агрит его как обычно (on_guard_hit → command_attack)
const TROLL_CHASE_COOL_SEC := 3.0
var _chase_t: float = 0.0
var _chase_target: Node3D = null
var _chase_cool: float = 0.0
var chase_resets: int = 0            # стендам: сколько раз поводок сработал

func aggro_radius() -> float:
	return _GobCfgT.TROLL_AGGRO_RADIUS

func _check_auto_aggro() -> void:
	if _chase_cool > 0.0:
		_aggro_timer = AGGRO_INTERVAL_CALM
		return
	super._check_auto_aggro()

## Удар дошёл до цели — погоня не напрасна, часы заново
func _note_hit_landed() -> void:
	_chase_t = 0.0

func chase_left() -> float:
	return maxf(_GobCfgT.TROLL_CHASE_SEC - _chase_t, 0.0)

func _tick_chase(delta: float) -> bool:
	if _chase_cool > 0.0:
		_chase_cool -= delta
	var t: Node3D = attack_target
	if t == null or not is_instance_valid(t) or not _raid.is_empty():
		_chase_t = 0.0
		_chase_target = null
		return false
	if t != _chase_target:
		_chase_target = t
		_chase_t = 0.0
	_chase_t += delta
	if _chase_t < _GobCfgT.TROLL_CHASE_SEC:
		return false
	# Не догнал за отведённое — агро сброшено, домой
	chase_resets += 1
	_chase_t = 0.0
	_chase_target = null
	_chase_cool = TROLL_CHASE_COOL_SEC
	release_target_lock()
	set_attack_target(null)
	_atk_pending = false
	velocity = Vector3.ZERO
	state = State.IDLE
	if lair != null and is_instance_valid(lair):
		var a: float = randf() * TAU
		var r: float = _GobCfgT.TROLL_PATROL_RADIUS * 0.5
		var p: Vector3 = lair.global_position + Vector3(cos(a) * r, 0.0, sin(a) * r)
		command_move(GameManager.land_target(p))
		_patrol_t = _GobCfgT.TROLL_PATROL_SEC
	return true

func take_damage(amount: float, attacker: Node3D = null) -> void:
	if state == State.DEAD:
		return
	if attacker != null and is_instance_valid(attacker):
		_last_hit_from = attacker.global_position
	if attacker != null and is_instance_valid(attacker) and attacker is Unit:
		var sid: int = (attacker as Unit).squad_id
		if sid > 0 and int((attacker as Unit).faction) != int(faction):
			_dmg_by_squad[sid] = float(_dmg_by_squad.get(sid, 0.0)) + amount
			_dmg_total += amount
	super.take_damage(amount, attacker)
	if state == State.DEAD:
		return
	# АГРО-ВЫЗОВ (10.09.2026): любой удар по стражу — логово решает, выпускать
	# ли помощников (первый удар по группе) и агрит самого тролля на обидчика
	if lair != null and is_instance_valid(lair) and lair.has_method("on_guard_hit"):
		lair.call("on_guard_hit", self, attacker)
	# «Стандартная» подмога на трети запаса — только у бонусной пары, один раз
	if standard_reinforce and not _reinforced and max_health > 0.0 \
			and current_health <= max_health * _GobCfgT.TROLL_REINFORCE_AT:
		_reinforced = true
		if lair != null and is_instance_valid(lair) and lair.has_method("call_guards"):
			lair.call("call_guards", _GobCfgT.TROLL_REINFORCE_COUNT, self)

## ── СМЕРТЬ: ЦЕНА В УБИЙСТВАХ ДЕЛИТСЯ ПО УРОНУ ───────────────────────────────
func _die() -> void:
	is_dead_flag = true
	if not _raid.is_empty():
		_raid_finish(false)
	if state != State.DEAD:
		_award_kills()
		if lair != null and is_instance_valid(lair) and lair.has_method("on_troll_died"):
			lair.call("on_troll_died", self)
	super._die()

func _award_kills() -> void:
	# Добивающий удар и так даёт отряду обычный +1 (Unit.take_damage →
	# credit_kill), поэтому здесь раздаётся worth − 1: итог ровно worth
	var worth: int = _GobCfgT.TROLL_KILL_WORTH - 1
	if worth <= 0 or _dmg_total <= 0.0 or _dmg_by_squad.is_empty():
		return
	# Доли по урону, остаток — тому, кто нанёс больше всех
	var given := 0
	var best_sid := 0
	var best_dmg := -1.0
	var shares: Dictionary = {}
	for k in _dmg_by_squad:
		var sid: int = int(k)
		var d: float = float(_dmg_by_squad[k])
		var n: int = int(floor(float(worth) * d / _dmg_total))
		shares[sid] = n
		given += n
		if d > best_dmg:
			best_dmg = d
			best_sid = sid
	if best_sid > 0:
		shares[best_sid] = int(shares[best_sid]) + (worth - given)
	for sid2 in shares:
		var n2: int = int(shares[sid2])
		if n2 > 0:
			GameManager.credit_kills(int(sid2), n2, self)
