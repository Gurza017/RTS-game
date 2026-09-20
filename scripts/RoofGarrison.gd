extends RefCounted
## ═══════════════════════════════════════════════════════════════════════════
## ГАРНИЗОН НА КРЫШЕ — ОБЩИЙ МОДУЛЬ БАШНИ, БАРАКОВ И КРЕПОСТИ (ТЗ 14.09.2026)
## ═══════════════════════════════════════════════════════════════════════════
## Вырос из башни (Tower.gd, 09-10.09.2026): спрайты лучников на площадке,
## огонь с площадки за укрытых, урон дальнего боя — по лучнику на площадке,
## тела у подножия. Здесь всё это живёт ОДНИМ кодом на три здания, а хозяин
## (Castle-наследник) даёт только раскладку мест и параметры:
##   • раскладка — LAYOUT_RING (башня: один в центре, прочие по эллипсу),
##     LAYOUT_GRID (бараки: плотный прямоугольник на скате крыши),
##     LAYOUT_KEEP (крепость: 30 на настиле в центре, по 15 на башнях по
##     краям); место idx → (вбок, вверх, вглубь) от середины рисунка;
##   • foot_frac — на какой доле высоты рисунка стоят ноги (у крепости своя
##     для флангов);
##   • cap — сколько спрайтов видно (столько же и стреляет).
##
## ── СОРТИРОВКА РЯДОВ: ЗА ГЛУБИНУ ПЛАТИТ Z, А НЕ Y ─────────────────────────
## Спрайт бойца на крыше — квад с мировой ориентацией, глубину ему даёт точка
## его подножия. Под камерой в 45° подъём на dy приближает к камере на
## 0.71·dy, а отход на dz по Z удаляет на 0.71·dz: ряд, поднятый ВВЕРХ по
## крыше, рисовался бы ПОВЕРХ переднего. Поэтому задние ряды уходят НАЗАД по
## Z (ROW_DZ) и почти не поднимаются (ROW_DY): на экране отход по Z сам
## читается как подъём (те же 0.71·dz), а порядок перекрытия верен.
##
## ── БАФФ ВЫСОТЫ (ТЗ, п. 3) ────────────────────────────────────────────────
## Дальность и урон укрытого — ×GARRISON_RANGE_MULT / GARRISON_DAMAGE_MULT
## (unit_stats_config). Дальность применяется здесь (стрельбу ведёт модуль, а
## не автомат бойца), урон — множителем к damage в _on_attack_fired; снайпер
## читает тот же множитель сам (Archer.garrison_mult) — его выстрел
## откладывается и уходит из его tick, который модуль дёргает (roof_tick).

const _UCfgR := preload("res://scripts/unit_stats_config.gd")
const _BBUtilR := preload("res://scripts/BillboardUtil.gd")
const _OptR := preload("res://scripts/perf_config.gd")

enum { LAYOUT_RING = 0, LAYOUT_GRID = 1, LAYOUT_KEEP = 2 }

## Сторона квада лучника, метры (кадр Archer_Idle 192 px при пикселе ~0.0108)
const SPRITE_SIZE_M := 1.9
## Пустое поле под ступнями в кадре Archer_Idle: 56 px из 192
const FOOT_PAD := 56.0 / 192.0
## Кольцо башни (см. Tower.sentinel_spot): радиус, подъём и глубина.
## 15.09.2026: ЭЛЛИПС ДЕЛАЕТСЯ ГЛУБИНОЙ, А НЕ ПОДЪЁМОМ. Прежний подъём дальней
## дуги по Y (0.42·r) приближал её к камере (0.71·dy) сильнее, чем отход по Z
## на 0.16 м удалял — задние стрелки рисовались ПОВЕРХ передних. Теперь дуга
## уходит назад по Z на RING_DEPTH_FRAC·r: на экране это тот же овал
## (0.71·dz вверх), а порядок перекрытия верен по построению (см. ROW_DZ)
const RING_FRAC := 0.30
const RING_SQUASH := 0.04
const RING_DEPTH_FRAC := 0.62
## Сетка на крыше: шаг вбок (м), отход ряда назад по Z и подъём (см. шапку).
## ТЗ 19.09.2026 (п. 4): рассадка РАЗРЕЖЕНА — шаг 0.44 → 0.62 м, ряды глубже
## (−0.42 → −0.55); бараки — 15 видимых в три ряда по 5
const GRID_DX := 0.62
## Сдвиг точки сортировки крыши к камере от подножия постройки, м (см.
## _build_sprite): передний ряд ROOF_SORT_LIFT, каждый метр глубины ряда
## снимает ROOF_SORT_ROW, не ниже ROOF_SORT_MIN — крыша всегда поверх стены
const ROOF_SORT_LIFT := 0.30
const ROOF_SORT_ROW := 0.10
const ROOF_SORT_MIN := 0.05
const ROW_DZ := -0.55
const ROW_DY := 0.05
## Крепость (ТЗ 19.09.2026): 22 на настиле ДВУМЯ ПОЛОВИНКАМИ по 11 (колонки
## по KEEP_CENTRE_COLS, просвет KEEP_CENTRE_GAP между ними), по 9 на каждой
## фланговой полубашне (KEEP_FLANK_COLS колонки, выше настила —
## CASTLE_FLANK_FOOT_FRAC). Итого 40 видимых из 60 сидящих
const KEEP_FLANK_X := 0.70
const KEEP_CENTRE_MEN := 22
const KEEP_HALF_MEN := 11
const KEEP_CENTRE_COLS := 4
const KEEP_CENTRE_GAP := 1.3
const KEEP_FLANK_COLS := 3
const GRID_COLS := 5

var host: Node3D = null
var layout: int = LAYOUT_RING
var cap: int = 10
var foot_frac: float = 0.6
var flank_foot_frac: float = 0.6
## Дальность огня по этому зданию: обзор башни здесь ни при чём — только
## штатная дальность лучников внутри с баффом высоты

var _sprites: Array = []
var _shown: int = 0
var _fire_cd: Dictionary = {}       # Unit → секунд до выстрела
var _fire_target = null             # сырая ссылка (правило 5)
var _retarget_t: float = 0.0
var _volley_wait: Dictionary = {}   # sid → сколько ждём готовности залпа
var _fall_index: int = 0
var shots_fired: int = 0

func setup(p_host: Node3D, p_layout: int, p_cap: int, p_foot: float, p_flank_foot: float = -1.0) -> void:
	host = p_host
	layout = p_layout
	cap = p_cap
	foot_frac = p_foot
	flank_foot_frac = p_flank_foot if p_flank_foot > 0.0 else p_foot

# ─────────────────────────────────────────────────────────────────────────────
# СОСТАВ НА КРЫШЕ
# ─────────────────────────────────────────────────────────────────────────────
## Живые укрытые бойцы стрелковых отрядов хозяина, в порядке гарнизона.
## Массив строится по событию (такт огня, синхронизация) — не покадрово
func roof_units() -> Array:
	var out: Array = []
	for rec in host.garrison:
		var sid: int = int((rec as Dictionary).get("sid", 0))
		if sid <= 0 or not host.roof_accepts(GameManager.squad_type(sid)):
			continue
		for m in GameManager.squad_members(sid):
			if not is_instance_valid(m):
				continue
			var u := m as Unit
			if u != null and u.garrisoned and not u.is_dead():
				out.append(u)
	return out

func men() -> int:
	return roof_units().size()

## Сколько стрелковых отрядов сидит на крыше (для лимита посадки)
func squads() -> int:
	var n := 0
	for rec in host.garrison:
		if host.roof_accepts(String((rec as Dictionary).get("type", ""))):
			n += 1
	for sid in host._incoming:
		if host.roof_accepts(GameManager.squad_type(int(sid))):
			n += 1
	return n

## Порядковый номер отряда среди сидящих на крыше (0, 1, …), −1 — не на крыше.
## По нему знамя ветеранов ставится в центр площадки со сдвигом на второй
## отряд крепости (ТЗ 18.09.2026, п. 7)
func roof_index_of(sid: int) -> int:
	var k := 0
	for rec in host.garrison:
		var r: Dictionary = rec
		if not host.roof_accepts(String(r.get("type", ""))):
			continue
		if int(r.get("sid", 0)) == sid:
			return k
		k += 1
	return -1

## Точка знамени отряда на крыше: центр площадки; второй отряд — рядом по X
func banner_point(sid: int) -> Vector3:
	var k: int = maxi(roof_index_of(sid), 0)
	return platform_point() + Vector3(float(k) * 1.4, 0.0, 0.0)

## Первый стрелковый отряд на крыше, 0 — пусто
func squad_id() -> int:
	for rec in host.garrison:
		if host.roof_accepts(String((rec as Dictionary).get("type", ""))):
			return int((rec as Dictionary).get("sid", 0))
	return 0

# ─────────────────────────────────────────────────────────────────────────────
# МЕСТА
# ─────────────────────────────────────────────────────────────────────────────
## Высота нарисованного рисунка, м (уже с V_STRETCH), и его полуширина
func _sprite_h() -> float:
	var spr := host.get_node_or_null("BuildingSprite") as MeshInstance3D
	if spr != null and spr.mesh is QuadMesh:
		return (spr.mesh as QuadMesh).size.y * _BBUtilR.V_STRETCH
	return host.build_size.y * 2.0

func _half_w() -> float:
	if host._draw_half_w > 0.0:
		return host._draw_half_w
	return host.build_size.x * 0.5

## Место idx из total: (вбок, вверх, вглубь) от середины рисунка на высоте
## foot_frac (ноги). Ноль — ЦЕНТР площадки
func spot(idx: int, total: int) -> Vector3:
	match layout:
		LAYOUT_GRID:
			return _grid_spot(idx, GRID_COLS, 0.0)
		LAYOUT_KEEP:
			if idx < KEEP_CENTRE_MEN:
				# Две аккуратные половинки по 11: левая и правая, между ними
				# просвет KEEP_CENTRE_GAP (проход/лестница в середине настила)
				var half: int = 0 if idx < KEEP_HALF_MEN else 1
				var j0: int = idx if half == 0 else idx - KEEP_HALF_MEN
				var dxc: float = _grid_dx(KEEP_CENTRE_COLS)
				var shift: float = KEEP_CENTRE_GAP * 0.5 + dxc * float(KEEP_CENTRE_COLS - 1) * 0.5
				return _grid_spot(j0, KEEP_CENTRE_COLS, -shift if half == 0 else shift)
			var k: int = idx - KEEP_CENTRE_MEN
			var per_flank: int = maxi((total - KEEP_CENTRE_MEN + 1) / 2, 1)
			var side: float = -1.0 if k < per_flank else 1.0
			var j: int = k if k < per_flank else k - per_flank
			var s: Vector3 = _grid_spot(j, KEEP_FLANK_COLS, 0.0)
			s.x += side * _half_w() * KEEP_FLANK_X
			# Фланги — свои башни: ноги на их высоте
			s.y += (flank_foot_frac - foot_frac) * _sprite_h()
			return s
		_:
			return _ring_spot(idx, total)

## Шаг колонки: заказанный GRID_DX, но не шире, чем влезает в рисунок
func _grid_dx(cols: int) -> float:
	return minf(GRID_DX, _half_w() * 1.6 / float(maxi(cols, 1)))

## Сетка: ряд за рядом назад по Z, колонки от середины
func _grid_spot(idx: int, cols: int, x0: float) -> Vector3:
	var col: int = idx % cols
	var row: int = idx / cols
	var dx: float = _grid_dx(cols)
	# Соседние ряды сдвинуты на полшага — шахматка читается плотнее и не
	# закрывает лица заднего ряда целиком
	var stagger: float = 0.5 * dx if (row % 2 == 1) else 0.0
	return Vector3(x0 + (float(col) - float(cols - 1) * 0.5) * dx + stagger,
		float(row) * ROW_DY, float(row) * ROW_DZ)

func _ring_spot(idx: int, total: int) -> Vector3:
	if idx <= 0 or total <= 1:
		return Vector3.ZERO
	var r: float = host.build_size.x * RING_FRAC
	var on_ring: int = maxi(total - 1, 1)
	var a: float = TAU * (float(idx - 1) + 0.5) / float(on_ring)
	return Vector3(cos(a) * r, sin(a) * r * RING_SQUASH, -sin(a) * r * RING_DEPTH_FRAC)

## Локальная точка ног места idx (для спрайта и для вылета стрелы)
func slot_local(idx: int) -> Vector3:
	var s: Vector3 = spot(idx, cap)
	return Vector3(host._draw_cx + s.x, _sprite_h() * foot_frac + s.y, 0.08 + s.z)

## Мировая точка вылета стрелы с места idx (грудь стрелка над ногами)
func fire_point(idx: int) -> Vector3:
	return host.to_global(slot_local(mini(maxi(idx, 0), cap - 1)) + Vector3(0.0, 0.9, 0.0))

## Середина площадки (совместимость: Tower.platform_point)
func platform_point() -> Vector3:
	return host.global_position + Vector3(host._draw_cx, _sprite_h() * foot_frac, 0.0)

# ─────────────────────────────────────────────────────────────────────────────
# СПРАЙТЫ
# ─────────────────────────────────────────────────────────────────────────────
## Спрайтов ровно столько, сколько живых на крыше (не больше cap). Строятся
## ЛЕНИВО и только по изменению числа: обрезка листа — не покадровая работа.
## Укрытым бойцам тем же обходом ставится точка их места — оттуда летят
## стрелы и туда смотрит снайперский поиск
func sync() -> void:
	var units: Array = roof_units()
	var want: int = mini(units.size(), cap)
	for i in range(want):
		(units[i] as Unit).global_position = host.to_global(slot_local(i))
	if want == _shown:
		return
	_shown = want
	while _sprites.size() < want:
		var mi := _build_sprite(_sprites.size())
		if mi == null:
			break
		_sprites.append(mi)
	for i in range(_sprites.size()):
		var node = _sprites[i]
		if node != null and is_instance_valid(node):
			(node as MeshInstance3D).visible = i < want

func shown() -> int:
	var n := 0
	for a in _sprites:
		if a != null and is_instance_valid(a) and (a as MeshInstance3D).visible:
			n += 1
	return n

func first_sprite() -> MeshInstance3D:
	return _sprites[0] if not _sprites.is_empty() else null

func _build_sprite(idx: int) -> MeshInstance3D:
	var folder: String = GameManager.unit_sprite_folder(host.faction, "archer")
	var path: String = folder + "/Archer_Idle.png"
	if folder.is_empty() or not ResourceLoader.exists(path):
		return null
	var sheet := load(path) as Texture2D
	if sheet == null:
		return null
	var img: Image = sheet.get_image()
	if img == null:
		return null
	var side: int = mini(img.get_height(), img.get_width())
	var frame: Image = img.get_region(Rect2i(0, 0, side, side))
	var tex := ImageTexture.create_from_image(frame)
	var quad := QuadMesh.new()
	quad.size = Vector2(SPRITE_SIZE_M, SPRITE_SIZE_M)
	quad.material = _BBUtilR.make_static_material(tex, Color.WHITE, 0.5)
	var mi := MeshInstance3D.new()
	mi.name = "Sentinel"
	mi.mesh = quad
	var feet: Vector3 = slot_local(idx)
	# Низ квада — на поле под ступнями ниже ног, центр квада — на полстороны выше
	mi.position = Vector3(feet.x, feet.y - SPRITE_SIZE_M * FOOT_PAD + SPRITE_SIZE_M * 0.5, feet.z)
	mi.rotation = Vector3.ZERO
	# ── СОРТИРОВКА ПО ПОДНОЖИЮ ХОЗЯИНА (ТЗ 19.09.2026 «Y-sort тролля») ─────
	# Своя точка на земле у спрайта лежит на высоте крыши и под камерой 45°
	# приближает его к камере на 0.71·h — гарнизон рисовался поверх тролля,
	# стоящего перед башней. Якорь — точка сортировки самой постройки (низ её
	# рисунка, z = 0 узла), плюс сдвиг К КАМЕРЕ: спереди ROOF_SORT_LIFT, чтобы
	# крыша шла поверх стены, задние ряды на ROOF_SORT_ROW за метр глубины
	# ближе к стене — порядок рядов между собой цел
	var mat := quad.material as ShaderMaterial
	mat.set_shader_parameter("depth_anchor_on", 1.0)
	mat.set_shader_parameter("depth_anchor", host.global_position + Vector3(host._draw_cx, 0.0, 0.0))
	var s: Vector3 = spot(idx, cap)
	mat.set_shader_parameter("depth_push", -maxf(ROOF_SORT_LIFT + s.z * ROOF_SORT_ROW, ROOF_SORT_MIN))
	host.add_child(mi)
	return mi

# ─────────────────────────────────────────────────────────────────────────────
# ОГОНЬ С КРЫШИ
# ─────────────────────────────────────────────────────────────────────────────
## Дальность огня: наибольшая штатная дальность лучников на крыше × бафф
func fire_range() -> float:
	var r: float = 0.0
	for u in roof_units():
		r = maxf(r, (u as Unit).attack_range)
	return r * _UCfgR.GARRISON_RANGE_MULT

## Цель жива и в дальности огня: боец — по точке, ПОСТРОЙКА — до края её
## рисунка (Unit._pad_of), иначе крепость в 25 м от башни числилась бы
## «за дальностью», хотя её стена в 20
func _target_alive(t) -> bool:
	if t == null or not is_instance_valid(t):
		return false
	var pad: float = 0.0
	var u := t as Unit
	if u != null:
		if u.is_dead() or u.garrisoned:
			return false
	else:
		var b := t as Building
		if b == null or b.is_dead() or int(b.faction) == int(host.faction) \
				or int(b.faction) == Constants.FACTION_NEUTRAL:
			return false
		pad = b.ring_radius()
	var p := host.global_position
	var q := (t as Node3D).global_position
	var r: float = fire_range() + pad
	return Vector2(q.x - p.x, q.z - p.z).length_squared() <= r * r

## ── ПРЯМОЙ ПРИКАЗ ГАРНИЗОНУ (ТЗ 19.09.2026, Garrison Manual Targeting) ─────
## Игрок выделил здание и кликнул ПКМ по чужому отряду или постройке: весь
## гарнизон переносит огонь на указанную цель и держит её, пока она жива и в
## дальности; погибла или ушла — обратно к авто-выбору ближайшего. Держится
## СЫРАЯ ссылка (правило 5): живость проверяется в _target_alive
var _manual_target = null
var manual_orders: int = 0

func order_fire(t: Node3D) -> bool:
	if t == null or not is_instance_valid(t):
		return false
	var tu := t as Unit
	if tu != null:
		if tu.is_dead() or tu.garrisoned or int(tu.faction) == int(host.faction):
			return false
	else:
		var tb := t as Building
		if tb == null or tb.is_dead() or int(tb.faction) == int(host.faction) \
				or int(tb.faction) == Constants.FACTION_NEUTRAL:
			return false
	_manual_target = t
	_fire_target = t
	_retarget_t = 0.0
	manual_orders += 1
	# Отряду в режиме залпа — окно сразу: готовые стреляют на своём тике
	for rec in host.garrison:
		var sid: int = int((rec as Dictionary).get("sid", 0))
		if sid > 0 and host.roof_accepts(GameManager.squad_type(sid)):
			GameManager.squad_note_order(sid, GameManager.ORDER_ATTACK,
				(t as Node3D).global_position, t)
			if GameManager.squad_volley_mode(sid):
				GameManager.squad_volley_prime(sid, t)
	return true

## Текущая ручная цель (null — гарнизон на авто-агро)
func manual_target():
	if _manual_target == null or not is_instance_valid(_manual_target) 			or not _target_alive(_manual_target):
		_manual_target = null
	return _manual_target

func has_manual_target() -> bool:
	return manual_target() != null

## Ближайший чужой боец в дальности огня — по сетке ядра, по всем чужим сторонам
func _pick_target() -> Node3D:
	var p := host.global_position
	var best: Node3D = null
	var best_d2: float = INF
	var r: float = fire_range()
	for f in Constants.other_factions(host.faction):
		var cand = GameManager.army.nearest_of_side(p.x, p.z, int(f), r)
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

func tick(delta: float) -> void:
	sync()
	var units: Array = roof_units()
	if units.is_empty():
		if not _fire_cd.is_empty():
			_fire_cd.clear()
			_fire_target = null
		return
	_retarget_t -= delta
	# Ручная цель игрока (order_fire) сильнее авто-выбора, пока жива и в
	# дальности; ушла или пала — гарнизон сам возвращается к ближайшему
	# Освобождённый объект в Variant РАВЕН null (правило 5): живость — только
	# через is_instance_valid, иначе выбитая цель висела бы в поле вечно
	if _manual_target != null and is_instance_valid(_manual_target):
		if _target_alive(_manual_target):
			_fire_target = _manual_target
		else:
			_manual_target = null
			_fire_target = null
	else:
		_manual_target = null
	if not _target_alive(_fire_target):
		_fire_target = null
		if _retarget_t <= 0.0:
			_retarget_t = _UCfgR.TOWER_RETARGET_SEC
			_fire_target = _pick_target()
	var have_target: bool = _fire_target != null
	var tpos: Vector3 = (_fire_target as Node3D).global_position if have_target else Vector3.ZERO
	# Постройка: дальность меряется до края рисунка, а не до центра коробки
	var tpad: float = Unit._pad_of(_fire_target as Node3D) if have_target else 0.0
	var hp: Vector3 = host.global_position
	var mult: float = _UCfgR.GARRISON_RANGE_MULT
	# ОГОНЬ ВЕДУТ ТОЛЬКО ВИДИМЫЕ НА КРЫШЕ: остальные — резерв, они не стреляют
	var n: int = mini(units.size(), cap)
	# ── ЗАЛП С КРЫШИ (Volley Fire): готовые ждут друг друга ───────────────
	# Автомат отряда (_sweep_volleys) укрытых не видит, синхронность держит
	# модуль: у отряда в режиме залпа стрелы уходят, только когда готова доля
	# VOLLEY_READY_FRACTION видимых, либо ожидание перевалило VOLLEY_FORCE_MS
	var hold: Dictionary = {}
	var by_sid: Dictionary = {}
	for i in range(n):
		var u: Unit = units[i]
		var cd: float = float(_fire_cd.get(u, 0.0)) - delta
		_fire_cd[u] = maxf(cd, 0.0)
		if u.squad_id > 0 and GameManager.squad_volley_mode(u.squad_id):
			var st: Variant = by_sid.get(u.squad_id)
			var arr: Array
			if st == null:
				arr = [0, 0]
				by_sid[u.squad_id] = arr
			else:
				arr = st
			arr[0] += 1
			if cd <= 0.0:
				arr[1] += 1
	for sid in by_sid.keys():
		var arr: Array = by_sid[sid]
		var ready: bool = float(arr[1]) >= float(arr[0]) * GameManager.VOLLEY_READY_FRACTION
		var wait: float = float(_volley_wait.get(sid, 0.0))
		if not ready and arr[1] > 0:
			wait += delta
		if not ready and wait * 1000.0 < float(GameManager.VOLLEY_FORCE_MS):
			hold[sid] = true
		else:
			wait = 0.0
			if have_target:
				GameManager.squad_volley_prime(int(sid), _fire_target as Node3D)
		_volley_wait[sid] = wait
	for i in range(n):
		var u: Unit = units[i]
		# Снайпер: статус и отложенный выстрел ведёт модуль — сам он не тикает
		if u is Archer:
			(u as Archer).roof_tick(delta)
		if float(_fire_cd.get(u, 0.0)) > 0.0:
			continue
		if not have_target:
			continue
		if hold.has(u.squad_id):
			continue
		# Личная дальность с баффом: кто не достаёт — ждёт
		var reach: float = u.attack_range * mult + tpad
		if Vector2(tpos.x - hp.x, tpos.z - hp.z).length_squared() > reach * reach:
			continue
		u.global_position = fire_point(i)
		# Досягаемость выстрела (Archer._shot_reach) читает поправку на габарит
		# цели из поля бойца — у укрытого set_attack_target не зовётся, ставим сами
		u._target_pad = tpad
		u._on_attack_fired(_fire_target,
			(u._strike_damage() + u._upgrade_damage_bonus()) * _UCfgR.GARRISON_DAMAGE_MULT)
		shots_fired += 1
		_fire_cd[u] = u._effective_cooldown()

# ─────────────────────────────────────────────────────────────────────────────
# УРОН ПО ЛУЧНИКУ НА КРЫШЕ
# ─────────────────────────────────────────────────────────────────────────────
## Кого накрыло: САМЫЙ ЗДОРОВЫЙ из видимых (иначе одна модель добивалась бы
## залпом, и «резервист встаёт на место» случалось бы вдесятеро реже).
## Второй элемент ответа — его место на площадке (индекс видимого)
func pick_hit_archer() -> Unit:
	return _pick_hit()[0]

func _pick_hit() -> Array:
	var best: Unit = null
	var best_hp: float = -1.0
	var best_i: int = 0
	var units: Array = roof_units()
	for i in range(mini(units.size(), cap)):
		var u: Unit = units[i]
		if u.current_health > best_hp:
			best_hp = u.current_health
			best = u
			best_i = i
	return [best, best_i]

## Куда падает труп У ПОДНОЖИЯ (ТЗ 19.09.2026, п. 3): ВРАССЫПНУЮ вокруг
## основания — по золотому углу от номера падения, радиус чуть шире рисунка
## с разбросом. Прежний веер «чуть в сторону от ворот» клал всех в одну точку
const FALL_SPREAD_MIN := 0.85
const FALL_SPREAD_MAX := 1.35
func corpse_spot(idx: int = 0) -> Vector3:
	var a: float = float(idx) * 2.39996323 + 0.7
	var t: float = fposmod(float(idx) * 0.61803398875, 1.0)
	var r: float = host.ring_radius() * lerpf(FALL_SPREAD_MIN, FALL_SPREAD_MAX, t)
	var p: Vector3 = host.global_position + Vector3(cos(a) * r, 0.0, sin(a) * r)
	return Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)

## Ложится ли павший НА КРЫШЕ (иначе падает к подножию). ТЗ 19.09.2026
## (Garrison Archers): ТРУПЫ ЗАЩИТНИКОВ ОСТАЮТСЯ НА ПЛОЩАДКЕ — все, а не
## каждый второй (прежнее чередование FALL_STAY_EVERY 2 — история; 1 = все)
const FALL_STAY_EVERY := 1

## ── ПАРАЛЛЕЛЬНЫЙ УРОН (ТЗ 19.09.2026, Parallel Damage Split) ─────────────
## Град стрел по укреплению бьёт ДВУМЯ РУСЛАМИ разом: здание получает свой
## полный урон (его списывает хозяин — Castle.take_damage), а защитники на
## крыше — те же стрелы со срезом укрытия GARRISON_COVER_FRAC (0.5×). Сюда
## приходит УЖЕ срезанная доля; кому она достаётся — самому здоровому из
## видимых (иначе одна модель добивалась бы залпом). false — на крыше никого
func absorb_ranged_hit(amount: float, attacker: Node) -> bool:
	var pick: Array = _pick_hit()
	var u: Unit = pick[0]
	if u == null:
		return false
	var idx: int = _fall_index
	_fall_index += 1
	var stay_on_roof: bool = (idx % FALL_STAY_EVERY) == 0
	var spot: Vector3
	if stay_on_roof:
		# Тело остаётся на площадке: точка ног его места, высота — крыши
		spot = host.to_global(slot_local(int(pick[1])))
	else:
		spot = corpse_spot(idx)
	u.garrisoned = false
	u.garrison_host = null
	u.global_position = spot
	u.corpse_ground_override = spot.y if stay_on_roof else -INF
	u.take_damage(amount, attacker)
	if not is_instance_valid(u):
		sync()
		return true
	if u.is_dead():
		_stick_arrow_into(u, spot)
		sync()
		return true
	u.corpse_ground_override = -INF
	u.garrisoned = false
	host.absorb_unit(u)
	sync()
	return true

func _stick_arrow_into(u: Unit, spot: Vector3) -> void:
	var body = u.corpse_ref()
	if body == null:
		return
	var dir: Vector3 = Vector3(0.0, -1.0, 0.2).normalized()
	if _OptR.projectile_core:
		# Стрела без узла (этап 3): слот слоя стрел прямо в тело
		var lay = GameManager.arrows_mm
		if not lay.ensure_layer(host.get_parent() as Node3D):
			return
		var slot: int = lay.acquire()
		if slot < 0:
			return
		if not GameManager.corpses.stick_arrows(body, lay.core_id, dir, false, slot,
				lay.quad_length()):
			GameManager.army.projectile_drop(lay.core_id, slot)
		return
	var from := spot + Vector3(0.0, 3.0, 0.0)
	var a: Node3D = GameManager.spawn_arrow(host.get_parent(), from, spot, 0.25,
		12.0, 0.0, 0.0, null, host.faction)
	if a == null:
		return
	GameManager.corpses.stick_arrows(body, a, dir)

# ─────────────────────────────────────────────────────────────────────────────
# ВЫГРУЗКА
# ─────────────────────────────────────────────────────────────────────────────
## Выпустить все стрелковые отряды с крыши (ПКМ пустым выделением или кнопка
## панели). Остальной гарнизон крепости (лазарет) не трогается
func release_all() -> bool:
	var ids: Array = []
	for rec in host.garrison:
		if host.roof_accepts(String((rec as Dictionary).get("type", ""))):
			ids.append(int((rec as Dictionary).get("sid", 0)))
	for sid in ids:
		host.release_garrison(int(sid))
	sync()
	return not ids.is_empty()
