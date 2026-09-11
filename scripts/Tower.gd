extends Castle
## ═══════════════════════════════════════════════════════════════════════════
## ОБОРОНИТЕЛЬНАЯ БАШНЯ (заказ владельца, 09.09.2026)
## ═══════════════════════════════════════════════════════════════════════════
## НАСЛЕДУЕТ ЗАМОК ради гарнизона — тем же порядком и по той же причине, что
## хижина гоблинов: принять отряд, спрятать с карты, лечить, доукомплектовать,
## выпустить через ворота у нарисованной двери. Писать это заново значило бы
## завести вторую реализацию гарнизона со своими болезнями.
##
## От замка отличается ровно четырьмя вещами, и все они выражены
## ПЕРЕОПРЕДЕЛЕНИЯМИ, а не развилками внутри Castle:
##   • принимает ТОЛЬКО ЛУЧНИКОВ и ровно один отряд
##     (unit_stats_config.TOWER_GARRISON_*, см. garrison_accepts / garrison_limit);
##   • отряд НЕ ВЫХОДИТ САМ, когда вылечен: башня — это пост, а не лазарет
##     (_auto_release). Наружу — по ПКМ по башне или кнопкой в панели;
##   • обзор в тумане TOWER_VISION вместо BUILDING_VISION (vision_radius);
##   • на площадке стоит ЧАСОВОЙ, пока внутри есть лучники (_sync_sentinel).
##
## И ЭТО НЕ КРЕПОСТЬ: is_stronghold() = false. Все места, где «замок» значит
## «столица» — зона застройки, кнопка «в замок», условие поражения, точка
## базы для ИИ, — спрашивают именно это, а не `is Castle`.
##
## Файл НАМЕРЕННО без class_name: подключается через preload/load, поэтому не
## зависит от global_script_class_cache.cfg (тот же приём, что у House).

const _UCfgT := preload("res://scripts/unit_stats_config.gd")
const _BBUtilT := preload("res://scripts/BillboardUtil.gd")

## Ворота у подножия: башня узкая, замковые 6.5 м увели бы точку выхода на
## пустую траву далеко перед рисунком
const TOWER_GATE := 2.6

## ── ЧАСОВОЙ НА ПЛОЩАДКЕ ─────────────────────────────────────────────────────
## Где у Tower.png площадка: деревянный настил лежит на 0.60 высоты рисунка
## (обмер: настил на 100-110 px из 256 снизу). Подбирается глазом в окне
const SENTINEL_FOOT_FRAC := 0.60
## Сторона квада часового, метры. Кадр Archer_Idle 192 px при пикселе бойца
## ~0.0108 м даёт 2.07; чуть меньше — часовой стоит дальше от камеры, чем
## подножие, и не должен читаться крупнее прохожего
const SENTINEL_SIZE_M := 1.9
## Пустое поле под ступнями в кадре Archer_Idle: 56 px из 192 (обмер PIL).
## Низ квада опускается на эту долю ниже настила, чтобы ноги стояли на нём
const SENTINEL_FOOT_PAD := 56.0 / 192.0

## ── МЕСТА НА НАСТИЛЕ: КРУГ, А НЕ ШЕРЕНГА (заказ спринта 14) ───────────────
## Было: все спрайты расходились от середины ВДОЛЬ ОДНОЙ ЛИНИИ, и десять
## лучников вытягивались в длинную полосу шире самой башни — на скриншоте это
## читалось как строй, вставший на карниз.
##
## Стало: один в ЦЕНТРЕ площадки, остальные равномерно по ЭЛЛИПСУ вокруг него.
## Эллипс, а не круг, потому что настил виден под наклоном камеры: круг на
## горизонтальной площадке проецируется в эллипс, сплюснутый по вертикали
## экрана ровно в sin(наклона) раз — это и есть SENTINEL_RING_SQUASH.
##
## ГЛУБИНА БЕРЁТСЯ ИЗ ТОГО ЖЕ СИНУСА: стоящий «за» центром обязан рисоваться
## позади, а спрайты лежат в одной плоскости билборда, и порядок задаёт только
## сдвиг по Z. Поэтому места считаются ОДНОЙ формулой — иначе картинка и
## порядок перекрытия разъехались бы.
const SENTINEL_RING_FRAC := 0.30      # радиус круга, доля ширины постройки
const SENTINEL_RING_SQUASH := 0.42    # сплющивание по экрану (наклон камеры)
const SENTINEL_RING_DEPTH := 0.16     # разнос по глубине, м

## Место idx на настиле: (вбок, вверх, вглубь) от середины площадки.
## Нулевой — в центре, остальные по кругу. Всего мест — сколько видимых
## лучников держит башня (unit_stats_config.TOWER_VISIBLE_ARCHERS)
static func sentinel_spot(idx: int, total: int, width: float) -> Vector3:
	if idx <= 0 or total <= 1:
		return Vector3.ZERO
	var r: float = width * SENTINEL_RING_FRAC
	# Углы считаются по числу мест НА КОЛЬЦЕ (всего минус центральный), и
	# отсчёт сдвинут на пол-шага: иначе один лучник встаёт ровно перед центром
	# и закрывает его собой
	var on_ring: int = maxi(total - 1, 1)
	var a: float = TAU * (float(idx - 1) + 0.5) / float(on_ring)
	return Vector3(cos(a) * r, sin(a) * r * SENTINEL_RING_SQUASH,
		-sin(a) * SENTINEL_RING_DEPTH)

var _sentinel: MeshInstance3D = null
var _sentinel_shown: bool = false
## Спрайты лучников на настиле: до TOWER_VISIBLE_ARCHERS штук слева направо
var _archers: Array = []
## Сколько спрайтов показано сейчас (по числу живых в гарнизоне)
var _archers_shown: int = 0

## ── ГАРНИЗОН СТРЕЛЯЕТ С ПЛОЩАДКИ (заказ владельца, 09.09.2026) ──────────────
## Укрытый лучник с карты снят (Castle.absorb_unit: невидим, без тика, вне
## сетки соседей), и стрелять сам он не может — стреляет за него БАШНЯ: раз в
## его же перезарядку зовёт его же _on_attack_fired, то есть стрела летит с
## его уроном, кучностью, выучкой отряда и записывается на его счёт убийств.
## Цель одна на всю площадку (ближайший чужой в TOWER_FIRE_RANGE) и ищется не
## чаще TOWER_RETARGET_SEC: сетку ядра спрашивают десятки раз в секунду, а не
## по лучнику на кадр. Урон по укрытым идёт в запас башни (absorb_damage_for)
var _fire_cd: Dictionary = {}          # Unit → секунд до выстрела
## Нетипизировано намеренно (правило 5): убитая цель освобождается между
## тиками, а типизированная ссылка на освобождённый объект бросает исключение
var _fire_target = null
var _retarget_t: float = 0.0
## Сколько выстрелов сделано с площадки (стенды)
var shots_fired: int = 0

func _configure() -> void:
	building_id  = "tower"
	sprite_path  = ""
	max_health   = _UCfgT.building_stat("tower", "max_hp", 1200.0)
	build_size   = _UCfgT.building_size("tower", Vector3(3.4, 3.0, 3.4))
	display_name = String(_UCfgT.building_cfg("tower").get("name", "Башня"))
	# СКЛАДА НЕТ: башня — не столица, рабочим сдавать сюда нечего
	is_dropoff   = false
	squad_size   = 1
	squad_cols   = 4
	squad_spacing = 0.55
	spawn_offset = Vector3(0.0, 0.0, TOWER_GATE)

## Не дальше периметра рисунка — см. Building.gate_depth
func gate_depth() -> float:
	if _draw_half_w >= 0.0:
		return minf(TOWER_GATE, _draw_half_w + GATE_CLEARANCE)
	return TOWER_GATE

## Башня — не крепость (см. шапку)
func is_stronghold() -> bool:
	return false

func garrison_limit() -> int:
	return _UCfgT.TOWER_GARRISON_LIMIT

func garrison_accepts(unit_type: String) -> bool:
	return unit_type in _UCfgT.TOWER_GARRISON_TYPES

## Вылеченный отряд остаётся на посту
func _auto_release() -> bool:
	return false

## Обзор выше стрелка (см. unit_stats_config.TOWER_VISION)
func vision_radius() -> float:
	return _UCfgT.TOWER_VISION

## Тик нужен только с гарнизоном (или очередью ко входу); золота башня не даёт
func _needs_tick() -> bool:
	return not garrison.is_empty() or not _incoming.is_empty()

## ЗАМКОВОЙ МОДЕЛИ У БАШНИ НЕТ. База Castle грузит castle.glb; здесь нужен
## только коллайдер и запасной примитив — картинку положит поверх
## Building._maybe_load_building_sprite
func _build_visual() -> void:
	_add_pick_shape()
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = build_size.x * 0.32
	cyl.bottom_radius = build_size.x * 0.4
	cyl.height = build_size.y * 2.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.50, 0.48, 0.44)
	mat.roughness = 0.9
	cyl.material = mat
	body.mesh = cyl
	body.position.y = build_size.y
	add_child(body)
	selection_ring = make_selection_marker()
	add_child(selection_ring)

func _process(delta: float) -> void:
	super._process(delta)
	_sync_sentinel()
	if not garrison.is_empty():
		_tick_fire(delta)
	elif not _fire_cd.is_empty():
		_fire_cd.clear()
		_fire_target = null

## Дальность огня с площадки — ШТАТНАЯ дальность самих лучников внутри
## (наибольший attack_range по гарнизону), а не обзор башни: башня светит на
## TOWER_VISION, но стрела дальше своей нормы не летит (заказ 09.09.2026,
## разворот первой версии с 35 м). Гарнизон пуст — ноль, стрелять некому
func fire_range() -> float:
	var r: float = 0.0
	for rec in garrison:
		var sid: int = int((rec as Dictionary).get("sid", 0))
		if sid <= 0:
			continue
		for m in GameManager.squad_members(sid):
			if not is_instance_valid(m):
				continue
			var u := m as Unit
			if u != null and u.garrisoned and not u.is_dead():
				r = maxf(r, u.attack_range)
	return r

## Точка, откуда летят стрелы: настил площадки (тот же расчёт, что у часового)
func platform_point() -> Vector3:
	var sprite_h: float = build_size.y * 2.0
	var spr := get_node_or_null("BuildingSprite") as MeshInstance3D
	if spr != null and spr.mesh is QuadMesh:
		sprite_h = (spr.mesh as QuadMesh).size.y * _BBUtilT.V_STRETCH
	return global_position + Vector3(_draw_cx, sprite_h * SENTINEL_FOOT_FRAC, 0.0)

func _target_alive(t) -> bool:
	if t == null or not is_instance_valid(t):
		return false
	var u := t as Unit
	if u == null or u.is_dead() or u.garrisoned:
		return false
	var p := global_position
	var q := u.global_position
	var r: float = fire_range()
	return Vector2(q.x - p.x, q.z - p.z).length_squared() <= r * r

## Ближайший чужой боец в дальности огня — по сетке ядра, по всем чужим сторонам
func _pick_target() -> Node3D:
	var p := global_position
	var best: Node3D = null
	var best_d2: float = INF
	for f in Constants.other_factions(faction):
		var cand = GameManager.army.nearest_of_side(p.x, p.z, int(f), fire_range())
		if cand == null or not is_instance_valid(cand):
			continue
		var u := cand as Unit
		if u == null or u.is_dead():
			continue
		var q := u.global_position
		var d2: float = Vector2(q.x - p.x, q.z - p.z).length_squared()
		if d2 < best_d2:
			best_d2 = d2
			best = u
	return best

func _tick_fire(delta: float) -> void:
	_retarget_t -= delta
	if not _target_alive(_fire_target):
		_fire_target = null
		if _retarget_t <= 0.0:
			_retarget_t = _UCfgT.TOWER_RETARGET_SEC
			_fire_target = _pick_target()
	var have_target: bool = _fire_target != null
	var from: Vector3 = platform_point() if have_target else Vector3.ZERO
	# ОГОНЬ ВЕДУТ ТОЛЬКО ВИДИМЫЕ НА НАСТИЛЕ (заказ 10.09.2026): остальные —
	# резерв внутри, они не стреляют и на экране их нет
	var shooters := 0
	for rec in garrison:
		var sid: int = int((rec as Dictionary).get("sid", 0))
		if sid <= 0:
			continue
		for m in GameManager.squad_members(sid):
			if not is_instance_valid(m):
				continue
			var u := m as Unit
			if u == null or not u.garrisoned or u.is_dead():
				continue
			shooters += 1
			if shooters > _UCfgT.TOWER_VISIBLE_ARCHERS:
				break
			var cd: float = float(_fire_cd.get(u, 0.0)) - delta
			if cd > 0.0:
				_fire_cd[u] = cd
				continue
			if not have_target:
				_fire_cd[u] = 0.0
				continue
			# Стрела вылетает с площадки: _on_attack_fired берёт global_position
			# стрелка, а укрытому её ставит хозяин
			u.global_position = from
			u._on_attack_fired(_fire_target, u._strike_damage() + u._upgrade_damage_bonus())
			shots_fired += 1
			_fire_cd[u] = u._effective_cooldown()

## Есть ли внутри хоть один отряд
## ── КТО ПОЛУЧАЕТ УРОН: ЛУЧНИК НА ПЛОЩАДКЕ ИЛИ САМА БАШНЯ ──────────────────
## Заказ владельца (10.09.2026), два правила:
##   ДАЛЬНИЙ БОЙ (чужие луки, башни) — урон получает ЛУЧНИК НА НАСТИЛЕ. Погиб
##       — с края башни падает труп (у подножия, с воткнувшейся стрелой), а на
##       его место встаёт резервист изнутри (спрайтов ровно столько, сколько
##       живых, см. _sync_sentinel).
##   БЛИЖНИЙ БОЙ (пехота) — достать укрытых нельзя вовсе: удар идёт в СТЕНЫ,
##       как и раньше (Castle.absorb_damage_for).
##
## РАЗДЕЛИТЕЛЬ — ДАЛЬНОСТЬ ОРУЖИЯ НАПАДАЮЩЕГО, а не тип узла: стрела приходит
## с полем shooter, копьё — самим копейщиком, и оба доходят сюда через
## take_damage постройки. MELEE_RANGE_MAX — та же граница, по которой отличают
## стрелка от пехотинца в панели (HUD.MELEE_RANGE_MAX): длина руки пехоты
## 2-3 м, лук — 20
const MELEE_RANGE_MAX := 5.0
func take_damage(amount: float, attacker: Node = null) -> void:
	if is_dead() or amount <= 0.0:
		return
	if _ranged_attacker(attacker):
		var victim: Unit = _pick_hit_archer()
		if victim != null:
			_hurt_garrison_archer(victim, amount, attacker)
			return
	super.take_damage(amount, attacker)

func _ranged_attacker(attacker: Node) -> bool:
	if attacker == null or not is_instance_valid(attacker):
		return false
	var u := attacker as Unit
	if u == null:
		# Башня противника (Building) стреляет с площадки — тоже дальний бой
		return attacker is Building
	return u.attack_range > MELEE_RANGE_MAX

## Кого накрыло: САМЫЙ ЗДОРОВЫЙ из видимых на настиле. Не самый раненый: иначе
## одна и та же модель добивалась бы залпом, и «резервист встаёт на место»
## случалось бы вдесятеро реже
func _pick_hit_archer() -> Unit:
	var best: Unit = null
	var best_hp: float = -1.0
	var seen := 0
	for rec in garrison:
		var sid: int = int((rec as Dictionary).get("sid", 0))
		if sid <= 0:
			continue
		for m in GameManager.squad_members(sid):
			if not is_instance_valid(m):
				continue
			var u := m as Unit
			if u == null or u.is_dead() or not u.garrisoned:
				continue
			seen += 1
			if seen > _UCfgT.TOWER_VISIBLE_ARCHERS:
				break
			if u.current_health > best_hp:
				best_hp = u.current_health
				best = u
	return best

## Куда падает труп: у ПОДНОЖИЯ башни, чуть в сторону от ворот
func corpse_spot(idx: int = 0) -> Vector3:
	var side := Vector3(-spawn_offset.z, 0.0, spawn_offset.x)
	if side.length() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized()
	var fwd := spawn_offset
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.BACK
	var off: float = (float(idx % 5) - 2.0) * 0.6
	var p: Vector3 = global_position + fwd * (ring_radius() * 0.9) + side * off
	return Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)

## УРОН ЛУЧНИКУ НА НАСТИЛЕ. Боец на время удара ВЫХОДИТ с карты обратно (снят
## признак garrisoned), получает урон штатным take_damage и, если погиб, кладёт
## тело у подножия — то есть всей обычной машинерией: фраг, ветеранство
## обидчика, труп в общем слое. Выжил — возвращается внутрь
func _hurt_garrison_archer(u: Unit, amount: float, attacker: Node) -> void:
	var spot: Vector3 = corpse_spot(_fall_index)
	_fall_index += 1
	u.garrisoned = false
	u.garrison_host = null
	u.global_position = spot
	u.take_damage(amount, attacker)
	if not is_instance_valid(u):
		_sync_sentinel()
		return
	if u.is_dead():
		# ТРУП С ТОРЧАЩЕЙ СТРЕЛОЙ: тело уже лежит (Unit._leave_corpse внутри
		# take_damage), стрелу приписываем к нему тем же путём, каким это
		# делает добившая стрела (CorpseRenderer.stick_arrows)
		_stick_arrow_into(u, spot)
		_sync_sentinel()
		return
	# Жив — обратно внутрь
	u.garrisoned = false
	absorb_unit(u)

## Счётчик упавших: тела ложатся веером у подножия, а не одно в другое
var _fall_index: int = 0

func _stick_arrow_into(u: Unit, spot: Vector3) -> void:
	var body = u.corpse_ref()
	if body == null:
		return
	var from := spot + Vector3(0.0, 3.0, 0.0)
	var a: Node3D = GameManager.spawn_arrow(get_parent(), from, spot, 0.25,
		12.0, 0.0, 0.0, null, faction)
	if a == null:
		return
	GameManager.corpses.stick_arrows(body, a, Vector3(0.0, -1.0, 0.2).normalized())

func has_garrison() -> bool:
	return not garrison.is_empty()

## Отряд внутри (первый; у башни он один). 0 — пусто
func garrison_squad_id() -> int:
	if garrison.is_empty():
		return 0
	return int((garrison[0] as Dictionary).get("sid", 0))

## ── ЧАСОВОЙ ────────────────────────────────────────────────────────────────
## Ставится ЛЕНИВО при первом отряде внутри и дальше только прячется/кажется:
## обмер и обрезка листа лучника — не покадровая работа
func _sync_sentinel() -> void:
	# ── ДО ДЕСЯТИ ЛУЧНИКОВ НА НАСТИЛЕ (заказ владельца 10.09.2026) ─────────
	# Был ОДИН часовой-декорация. Теперь спрайтов ровно столько, сколько живых
	# в гарнизоне (но не больше TOWER_VISIBLE_ARCHERS): погиб один — ряд
	# сомкнулся, и это и есть «на его место встаёт резервист изнутри».
	# Строятся ЛЕНИВО и только по изменению числа: обмер и обрезка листа
	# лучника — не покадровая работа
	var want: int = mini(garrison_men(), _UCfgT.TOWER_VISIBLE_ARCHERS)
	_sentinel_shown = want > 0
	if want == _archers_shown:
		return
	_archers_shown = want
	while _archers.size() < want:
		var mi := _build_sentinel(_archers.size())
		if mi == null:
			break
		_archers.append(mi)
	for i in range(_archers.size()):
		var node = _archers[i]
		if node != null and is_instance_valid(node):
			(node as MeshInstance3D).visible = i < want
	# Совместимость: прежнее поле указывает на первого в ряду — по нему
	# стенд спрашивает «часовой виден»
	_sentinel = _archers[0] if not _archers.is_empty() else null

## Сколько ЖИВЫХ бойцов сидит внутри
func garrison_men() -> int:
	var n := 0
	for rec in garrison:
		var sid: int = int((rec as Dictionary).get("sid", 0))
		if sid <= 0:
			continue
		for m in GameManager.squad_members(sid):
			if not is_instance_valid(m):
				continue
			var u := m as Unit
			if u != null and u.garrisoned and not u.is_dead():
				n += 1
	return n

func sentinel_visible() -> bool:
	return _sentinel != null and is_instance_valid(_sentinel) and _sentinel.visible

## Сколько спрайтов лучников видно на настиле (стенды)
func archers_shown() -> int:
	var n := 0
	for a in _archers:
		if a != null and is_instance_valid(a) and (a as MeshInstance3D).visible:
			n += 1
	return n

## Первый кадр Archer_Idle цвета фракции, квадом над настилом башни
## idx — место в ряду: спрайты расходятся вдоль настила от середины
func _build_sentinel(idx: int = 0) -> MeshInstance3D:
	var folder: String = GameManager.unit_sprite_folder(faction, "archer")
	var path: String = folder + "/Archer_Idle.png"
	if folder.is_empty() or not ResourceLoader.exists(path):
		return null
	var sheet := load(path) as Texture2D
	if sheet == null:
		return null
	var img: Image = sheet.get_image()
	if img == null:
		return null
	# Лист — полоса квадратных кадров; берём первый
	var side: int = mini(img.get_height(), img.get_width())
	var frame: Image = img.get_region(Rect2i(0, 0, side, side))
	var tex := ImageTexture.create_from_image(frame)
	var quad := QuadMesh.new()
	quad.size = Vector2(SENTINEL_SIZE_M, SENTINEL_SIZE_M)
	# Тот же материал, что у самой постройки: мировая ориентация, компенсация
	# наклона камеры шейдером от нижней кромки квада вверх
	quad.material = _BBUtilT.make_static_material(tex, Color.WHITE, 0.5)
	var mi := MeshInstance3D.new()
	mi.name = "Sentinel"
	mi.mesh = quad
	# Настил — доля высоты НАРИСОВАННОГО квада, уже растянутого (см.
	# Building._fit_pick_to_sprite: шейдер тянет от низа вверх в V_STRETCH раз)
	var sprite_h: float = 0.0
	var spr := get_node_or_null("BuildingSprite") as MeshInstance3D
	if spr != null and spr.mesh is QuadMesh:
		sprite_h = (spr.mesh as QuadMesh).size.y * _BBUtilT.V_STRETCH
	else:
		sprite_h = build_size.y * 2.0
	var floor_y: float = sprite_h * SENTINEL_FOOT_FRAC
	var bottom: float = floor_y - SENTINEL_SIZE_M * SENTINEL_FOOT_PAD
	# МЕСТО НА НАСТИЛЕ — КРУГОМ (см. sentinel_spot): один в центре, прочие
	# по эллипсу вокруг него
	var spot: Vector3 = sentinel_spot(idx, _UCfgT.TOWER_VISIBLE_ARCHERS, build_size.x)
	mi.position = Vector3(_draw_cx + spot.x,
		bottom + SENTINEL_SIZE_M * 0.5 + spot.y,
		0.08 + spot.z)
	mi.rotation = Vector3.ZERO
	add_child(mi)
	return mi

## Выпустить всех (ПКМ по башне или кнопка панели). false — внутри пусто
func release_all() -> bool:
	if garrison.is_empty():
		return false
	var ids: Array = []
	for rec in garrison:
		ids.append(int((rec as Dictionary).get("sid", 0)))
	for sid in ids:
		release_garrison(int(sid))
	_sync_sentinel()
	return true

## Пепелище общее «домовое», на башне — в долю (см. Building.spawn_ruin)
func ruin_scale() -> float:
	return _UCfgT.building_stat("tower", "ruin_scale", 1.0)
