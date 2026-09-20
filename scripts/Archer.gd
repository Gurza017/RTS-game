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
## ── «ПО ГОТОВНОСТИ» — ШИРОКИЙ РАЗБРОС, ЗАЛП — КУЧНАЯ ТУЧА (спринт 16) ──────
## Заказ: залп — «высокая точность и кучность, выгодный основной режим»;
## по готовности — «увеличен разброс, больше промахов, стрелы накрывают
## широкую область без фокуса». Залп и так кладёт стрелы золотым углом с
## сантиметровым дрожанием (см. VOLLEY_JITTER); у одиночной стрельбы разброс
## умножается на READY_SCATTER_MULT — множитель, а не новое число, чтобы
## кузница и выучка резали его так же, как раньше
const READY_SCATTER_MULT := 1.7
# Добавка разброса на каждый м/с скорости цели: бегущая пехота ловит
# заметно больше промахов, чем строй, стоящий на месте.
# 0.34 → 0.20 (15.09.2026): с полным упреждением промах по бегущему даёт
# только этот разброс, и 3.3 м радиуса по всаднику (4.6 м/с) означали
# «в модель не попадает никто» — qa_archer_lead A3 меряет долю попаданий
# по бегущему против стоящего
const SCATTER_PER_SPEED := 0.20

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
	# ── МЕСТО В ТУЧЕ — ПОРЯДКОВЫЙ НОМЕР В ОТРЯДЕ (спринт 16) ─────────────
	# Здесь стоял `get_instance_id() % VOLLEY_SLOTS`. Номера узлов у бойцов
	# одного заказа идут с ОДИНАКОВЫМ шагом (сцена рождает одно и то же число
	# объектов), и при шаге, кратном 97, весь отряд получал ОДНО k: залп
	# ложился в точку в 1.1 м от центра чужого строя, мимо всех
	# (qa_volley_fix B3 «залп 90 % в землю, разброс 0.07 м»; тот же жребий
	# мигал в qa_volley D2 «совпавших пар»). Номер в отряде у всех разный по
	# построению; одиночка без отряда — прежний путь
	# Диск Фогеля на N точек заполняется равномерно, только если N — ЧИСЛО
	# точек: с номерами 0..9 при делителе 97 все десять ложились в центральную
	# треть радиуса, и залп задевал двоих из шестнадцати (qa_volley D5)
	var ord: int = GameManager.squad_member_ordinal(squad_id, self)
	var n: int = GameManager.squad_member_count(squad_id) if ord >= 0 else VOLLEY_SLOTS
	var k: float = float((ord if ord >= 0 else int(get_instance_id())) % maxi(n, 1))
	var ang: float = k * 2.39996323            # золотой угол, радианы
	var r: float = sqrt((k + 0.5) / float(maxi(n, 1))) * radius
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
	cd = cd / maxf(fire, 0.01)
	# «Частота снайперов» (archer_3d): у снайпера своя, короче, перезарядка
	if _sniper:
		var k: float = GameManager.unit_bonus(faction, stat_id, "bonus_snipe_cd")
		if k > 0.0:
			cd *= (1.0 - minf(k, 0.8))
	return maxf(cd, _UStats.MIN_COOLDOWN)

# ═════════════════════════════════════════════════════════════════════════════
# СНАЙПЕРСКИЙ ВЫСТРЕЛ (ТЗ 14.09.2026, forge_config archer_2d / archer_3d)
# ═════════════════════════════════════════════════════════════════════════════
# Снайперы — первые N по порядковому номеру в отряде (GameManager.squad_snipers):
# выбыл один — снайпером становится следующий. Снайпер стреляет ПО ПРЯМОЙ
# (дуга 0), на SNIPE_RANGE м, стрелой в SNIPE_SPEED_MULT раз быстрее, своим
# звуком, и НЕ в ту же точку, что отряд: сам выбирает цель — отступающих,
# паникующих и одиночек в приоритете, иначе конкретную модель целевого
# отряда, не занятую другим снайпером (заявка GameManager.snipe_claim).
# Трое стреляют не разом, а «раз-два-три»: k-й снайпер с задержкой
# k × SNIPE_STAGGER_SEC (отложенный выстрел ведёт tick_physics).
#
# ДАЛЬНОСТЬ 25 м — ЭТО ЛИЧНОЕ attack_range СНАЙПЕРА: поле читают все горячие
# ветки (скан целей, замок, обзор), и подменять его на лету нельзя — статус
# пересчитывается раз в SNIPER_RECHECK_SEC и вписывает дальность в поле, как
# это делает кузница (см. Unit._ready / _apply_range_bonus_now)
const SNIPER_RECHECK_SEC := 0.5
var _sniper: bool = false
var _sniper_t: float = 0.0
var _snipe_pending_t: float = -1.0   # < 0 — отложенного выстрела нет
var _snipe_target = null             # сырая ссылка (правило 5)
var _snipe_dmg: float = 0.0
## Счётчики для стендов
static var snipe_shots: int = 0
static var snipe_p1_picks: int = 0   # цель взята из приоритета 1 (бегущие/одиночки)

func is_sniper() -> bool:
	return _sniper

## Бафф высоты (ТЗ 14.09.2026): укрытый стрелок бьёт дальше; читает снайпер
## для своего радиуса поиска, урон множит сам модуль крыши
func garrison_mult() -> float:
	return _UStats.GARRISON_RANGE_MULT if garrisoned else 1.0

## Тик укрытого: сам боец не тикает (снят с тика хозяином), а статус снайпера
## и отложенный «раз-два-три» жить обязаны — их дёргает RoofGarrison
func roof_tick(delta: float) -> void:
	_sniper_t -= delta
	if _sniper_t <= 0.0:
		_sniper_t = SNIPER_RECHECK_SEC
		_refresh_sniper()
	if _snipe_pending_t >= 0.0:
		_snipe_pending_t -= delta
		if _snipe_pending_t <= 0.0:
			_snipe_pending_t = -1.0
			_snipe_launch()

func tick_physics(delta: float, prof: bool = false, bm: bool = true,
		bonus_ver: int = -1) -> void:
	super.tick_physics(delta, prof, bm, bonus_ver)
	if garrisoned or state == State.DEAD:
		return
	_sniper_t -= delta
	if _sniper_t <= 0.0:
		_sniper_t = SNIPER_RECHECK_SEC
		_refresh_sniper()
	if _snipe_pending_t >= 0.0:
		_snipe_pending_t -= delta
		if _snipe_pending_t <= 0.0:
			_snipe_pending_t = -1.0
			_snipe_launch()
	elif _sniper:
		_snipe_autonomous(delta)

## ── СНАЙПЕР СНИМАЕТ БЕГЛЕЦА САМ (15.09.2026) ───────────────────────────────
## Отряд стоит без цели (радар даёт цель с 20 м, огонь — с дальности лука), а
## одиночка или бегущий проходит в 20-25 м — раньше снайпер молчал: его
## выстрел шёл только из отрядного _on_attack_fired. Теперь стоящий снайпер
## без цели раз в перезарядку сам ищет ПРИОРИТЕТНУЮ цель (одиночка, паника,
## отход — lone_only) в SNIPE_RANGE и стреляет. Отрядные цели он не берёт:
## иначе три снайпера тянули бы весь отряд в бой с 25 м
var _snipe_self_cd: float = 0.0
var snipe_self_shots: int = 0

func _snipe_autonomous(delta: float) -> void:
	_snipe_self_cd -= delta
	if _snipe_self_cd > 0.0:
		return
	_snipe_self_cd = SNIPER_RECHECK_SEC
	if state != State.IDLE or attack_target != null or _panicked or retreating 			or _disengaging or player_order_active() or target_lock:
		return
	var t: Node3D = _snipe_pick(null, true)
	if t == null:
		return
	_snipe_self_cd = _effective_cooldown()
	snipe_self_shots += 1
	face_towards(t.global_position)
	_snipe_schedule(t, _strike_damage() + _upgrade_damage_bonus())

## Статус снайпера и личная дальность: пересчёт по такту, запись в поле
func _refresh_sniper() -> void:
	var n: int = GameManager.squad_snipers(squad_id)
	var want: bool = false
	if n > 0:
		var ord: int = GameManager.squad_member_ordinal(squad_id, self)
		want = ord >= 0 and ord < n
	if want == _sniper:
		return
	_sniper = want
	_apply_sniper_range()

## Дальность заново: база + кузница (как при рождении), снайперу — не меньше
## SNIPE_RANGE. Потолок держит clamp_attack_range (у снайпера он выше)
func _apply_sniper_range() -> void:
	var base: float = _UStats.stat(stat_id, "attack_range", attack_range) \
		+ GameManager.unit_bonus(faction, stat_id, "bonus_range")
	if _sniper:
		base = maxf(base, _UStats.SNIPE_RANGE)
	attack_range = clamp_attack_range(base)
	if _soa >= 0 and not garrisoned:
		_soa_push_stats()

func clamp_attack_range(r: float) -> float:
	if _sniper:
		var cap: float = _UStats.stat(stat_id, "attack_range_cap", 0.0)
		return minf(r, maxf(cap, _UStats.SNIPE_RANGE))
	return super.clamp_attack_range(r)

## Номер снайпера в отряде: 0, 1, 2… — от него задержка «раз-два-три»
func _snipe_slot() -> int:
	return maxi(GameManager.squad_member_ordinal(squad_id, self), 0)

## Выбор цели снайпера. Приоритет 1 — бегущие (паника, отход) и одиночки
## (отряд из одного) в SNIPE_RANGE, не занятые другим снайпером; приоритет
## 2 — незанятая модель, желательно из отряда общей цели; занятые — крайний
## случай; совсем никого — цель отряда. Скан — событие (раз в перезарядку),
## не покадровый путь: массив от query_radius здесь допустим
func _snipe_pick(default_target: Node3D, lone_only: bool = false) -> Node3D:
	var mp: Vector3 = global_position
	var r: float = _UStats.SNIPE_RANGE * garrison_mult()
	var r2: float = r * r
	var best1: Node3D = null
	var best2: Node3D = null
	var claimed_best: Node3D = null
	var d1: float = INF
	var d2: float = INF
	var d3: float = INF
	var tsq: int = 0
	if default_target != null and is_instance_valid(default_target) and default_target is Unit:
		tsq = (default_target as Unit).squad_id
	# ── ПОД ЗАМКОМ ИГРОКА СНАЙПЕР НЕ ВЫБИРАЕТ САМ (ТЗ 19.09.2026-2, п. 3) ──
	# Прямой клик — фокус: одиночка или паникующий рядом его не перебивает.
	# Цель без отряда (тролль, туша) — она и есть выстрел; у отряда —
	# только его модели
	if target_lock and default_target != null and is_instance_valid(default_target) \
			and default_target is Unit and not (default_target as Unit).is_dead():
		if tsq <= 0:
			return default_target
		lone_only = false
	for n in GameManager.unit_grid.query_radius(mp, r):
		if n == null or not is_instance_valid(n):
			continue
		var u := n as Unit
		if u == null or u.faction == faction or u.is_dead() or u.garrisoned:
			continue
		if u.faction == Constants.FACTION_NEUTRAL:
			continue
		var up: Vector3 = u.global_position
		var d: float = (up.x - mp.x) * (up.x - mp.x) + (up.z - mp.z) * (up.z - mp.z)
		if d > r2:
			continue
		if GameManager.snipe_claimed(squad_id, u):
			if d < d3:
				claimed_best = u
				d3 = d
			continue
		if target_lock and tsq > 0 and u.squad_id != tsq:
			continue
		var lone: bool = u.is_panicked() or u.retreating \
			or GameManager.squad_member_count(u.squad_id) <= 1
		if lone:
			if d < d1:
				best1 = u
				d1 = d
		else:
			# Модель ЦЕЛЕВОГО отряда предпочтительнее чужой в четверо ближе
			var dd: float = d if (tsq > 0 and u.squad_id == tsq) else d * 4.0
			if dd < d2:
				best2 = u
				d2 = dd
	if best1 != null:
		snipe_p1_picks += 1
		return best1
	if lone_only:
		return null
	if best2 != null:
		return best2
	if claimed_best != null:
		return claimed_best
	return default_target

## Отложить снайперский выстрел: цель выбрана и заявлена сейчас, стрела
## уйдёт через k × SNIPE_STAGGER_SEC (k — номер снайпера)
func _snipe_schedule(target: Node3D, damage: float) -> void:
	var t: Node3D = _snipe_pick(target)
	if t == null:
		return
	GameManager.snipe_claim(squad_id, t)
	_snipe_target = t
	_snipe_dmg = damage
	var delay: float = float(_snipe_slot()) * _UStats.SNIPE_STAGGER_SEC
	if delay <= 0.0:
		_snipe_launch()
	else:
		_snipe_pending_t = delay

## Сам выстрел: прямая стрела (дуга 0), быстрее на SNIPE_SPEED_MULT, свой звук
## ── УПРЕЖДЕНИЕ (ТЗ 15.09.2026, п. 3.2) ─────────────────────────────────────
## Точка прицела = позиция цели + её скорость × время полёта; время зависит
## от точки, поэтому два прохода. Вынос не дальше ARCHER_LEAD_MAX (страховка:
## по цели за пределами дальности стрела и так не долетит). Одна функция на
## обычную стрелу, залп и снайпера — три расчёта разошлись бы по знаку
func _lead_point(from_pos: Vector3, tbase: Vector3, tvel: Vector3, speed: float) -> Vector3:
	var aim: Vector3 = tbase
	var lead_k: float = _UStats.ARCHER_LEAD_FACTOR
	if lead_k <= 0.0 or tvel.length_squared() <= 1e-4:
		return aim
	for _i in range(2):
		var travel: float = from_pos.distance_to(aim) / maxf(speed, 0.1)
		var lead: Vector3 = tvel * (travel * lead_k)
		var ll: float = lead.length()
		if ll > _UStats.ARCHER_LEAD_MAX:
			lead *= _UStats.ARCHER_LEAD_MAX / ll
		aim = tbase + lead
	return aim

func _snipe_launch() -> void:
	var t = _snipe_target
	_snipe_target = null
	if t == null or not is_instance_valid(t) or not (t is Unit) or (t as Unit).is_dead():
		t = _snipe_pick(null)
		if t == null or not is_instance_valid(t) or not (t is Unit) or (t as Unit).is_dead():
			return
	var parent := get_parent()
	if parent == null:
		return
	var tu := t as Unit
	_play_attack_anim("attack", 600)
	AudioManager.play_3d("snipe_shot", global_position)
	GameManager.tm_ability("snipe_shot", faction)
	tu.notify_incoming_fire(global_position)
	var from_pos: Vector3 = global_position + Vector3(0, 1.2, 0)
	var speed: float = _arrow_speed_cached() * _UStats.SNIPE_SPEED_MULT
	# Снайпер бьёт в ТОЧКУ ВСТРЕЧИ (ТЗ 15.09.2026): прямая стрела по бегущему
	# без выноса ложилась ровно позади цели
	var tv: Vector3 = tu.velocity
	tv.y = 0.0
	var tb: Vector3 = tu.global_position + Vector3(0, tu.aim_height(), 0)
	var s_reach: float = _shot_reach()
	if _xz_dist(from_pos, tb) > s_reach + SHOT_RANGE_SLACK:
		shots_refused_range += 1
		return
	var aim: Vector3 = _clamp_reach(from_pos, _lead_point(from_pos, tb, tv, speed), s_reach)
	var dist: float = from_pos.distance_to(aim)
	GameManager.fire_projectile(parent, from_pos, aim, dist, speed, 0.0, _snipe_dmg,
		self, faction, false, true)
	snipe_shots += 1

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
## Стрелок выбирает цель с весом: большие гоблины ×2 (ТЗ 14.09.2026, п. 10)
## Лучник — главная добыча конницы (ТЗ 18.09.2026, п. 4)
func cav_target_weight() -> float:
	return 2.2

func target_prio_scan() -> bool:
	return true

## Цель авто-агро за дальностью — стоим и бьём то, что достаём: шаг за ней
## делает только приказ игрока (ТЗ 17.09.2026, «рассыпание на одиночные ноды»)
func holds_ground_on_aggro() -> bool:
	return true

## ── «ЗАЩИТА» ЛУЧНИКУ ХОДЬБУ НЕ РЕЖЕТ (ТЗ 20.09.2026, п. 4.2) ───────────────
## Заказ: «лучники не режут свою скорость и не являются фалангой; при включении
## щита просто стоят на месте и ведут огонь». Штраф −35 % писан под щит и
## опущенные копья фаланги; у стрелка ни того, ни другого нет, а замедленный
## отход из-под конницы — это уже не «оборона», а смерть отряда
func stance_slows_move() -> bool:
	return false

## Стрелок в покое ищет цели дальше коридорного дозора (снайпер — 25 м сам,
## отряд — радар на 20+), поэтому по физике не спит (BigStand, этап 3)
func may_sleep_physics() -> bool:
	return false

func pursues_target() -> bool:
	return false

func _announces_squad_shot() -> bool:
	return not _sniper

# У лучника нет ни замаха мечом, ни тычка копьём: весь его звук — тетива
# в _on_attack_fired и прилёт стрелы в Arrow.gd
func _sfx_swing() -> String:
	return ""

func _sfx_hit() -> String:
	return ""

## ── СКОРОСТЬ И ДУГА СТРЕЛЫ — ЧИСЛОМ, А НЕ ПОИСКОМ ПО СТРОКАМ ──────────────
## `_UStats.stat("archer", "arrow_speed")` — два словарных поиска по строкам
## на выстрел (правило 4); залп пятисот стрел за тик — тысяча поисков.
## Конфиг статичен, читается один раз
static var _arrow_speed_c: float = -1.0
static var _arrow_arc_c: float = -1.0

static func _arrow_speed_cached() -> float:
	if _arrow_speed_c < 0.0:
		_arrow_speed_c = _UStats.stat("archer", "arrow_speed", 9.0)
	return _arrow_speed_c

static func _arrow_arc_cached() -> float:
	if _arrow_arc_c < 0.0:
		_arrow_arc_c = _UStats.stat("archer", "arrow_arc", 0.5)
	return _arrow_arc_c

func _on_attack_fired(target: Node3D, damage: float) -> void:
	# ── СНАЙПЕР СТРЕЛЯЕТ СВОИМ ПУТЁМ (по бойцам; по зданию — как все) ──────
	if _sniper and (target == null or target is Unit):
		_snipe_schedule(target, damage)
		return
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
	# По павшему стрела не выпускается (ТЗ 17.09.2026): цель могла пасть в
	# этом же кадре между решением автомата и спуском тетивы
	if tw != null and tw.is_dead():
		return
	if tw != null:
		tw.notify_incoming_fire(global_position)
	var speed: float = _arrow_speed_cached()

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
	# ВЫСОТА ПРИЦЕЛА — У ЦЕЛИ, А НЕ ЧИСЛОМ ЗДЕСЬ (заказ 10.09.2026): у тролля
	# 0.8 м это ступни, и весь залп уходил в землю под ним
	# У постройки тоже может быть своя точка (пень тролля: центр пня, а не
	# корни, см. TrollLair.aim_height); у прочих зданий — прежние 0.8
	var aim_h: float = 0.8
	if target is Unit:
		aim_h = (target as Unit).aim_height()
	elif target != null and target.has_method("aim_height"):
		aim_h = float(target.call("aim_height"))
	var tbase: Vector3 = target.global_position + Vector3(0, aim_h, 0)
	# ── СТРОГИЙ ПОТОЛОК ДАЛЬНОСТИ (ТЗ 19.09.2026-2, п. 3) ───────────────
	# Цель дальше досягаемости — выстрела нет: снаряд не рождается вовсе
	# (стрелы «через всю карту» рождались по цели, ушедшей за дальность
	# между тактом решения и кадром выстрела, и по выносу упреждения)
	var max_reach: float = _shot_reach()
	if _xz_dist(from_pos, tbase) > max_reach + SHOT_RANGE_SLACK:
		shots_refused_range += 1
		return
	var aim: Vector3 = _clamp_reach(from_pos, _lead_point(from_pos, tbase, tvel, speed), max_reach)
	var lead_vec: Vector3 = aim - tbase

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
		# ── ТОЧКА ЗАЛПА ОБЯЗАНА БЫТЬ ТОЧКОЙ МОЕЙ ЦЕЛИ (ТЗ 19.09.2026) ─────
		# Окно залпа переживает смену цели: приказ по зданию открывал его
		# на volley_aim ПРОШЛОГО противника — залп ложился в его трупы
		# (qa_garrison_archers_test A4: 24 стрелы из 192 — в павшего гоблина).
		# Здание — бьём в само здание; отряд — только если залп ведётся по
		# ЭТОМУ отряду; одиночка — точка не дальше корпусов от него
		if target is Building:
			vp = tbase
		elif tu != null:
			var vfoe: int = GameManager.squad_volley_foe(squad_id)
			if tu.squad_id > 0 and vfoe != tu.squad_id:
				vp = tbase
			elif vfoe == 0 and _xz_dist(vp, tbase) > VOLLEY_STALE_DIST:
				vp = tbase
		if vp != Vector3.ZERO:
			# Упреждение и у залпа (ТЗ 15.09.2026): туча ложилась в центр
			# строя ТАМ, ГДЕ ОН БЫЛ, и по бегущей цели весь залп падал позади —
			# «дорога из стрел» за спиной. Вынос считается по скорости своей
			# цели: отряд идёт как целое, и его центр движется той же скоростью
			vp += lead_vec
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
		var scatter := (SCATTER_BASE + tvel.length() * SCATTER_PER_SPEED) \
			* READY_SCATTER_MULT
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
		# ── ПРОМАХ ПО КРУПНОЙ ТУШЕ УХОДИТ В ЗЕМЛЮ (заказ спринта 14) ────────
		# Разброс выше — ГОРИЗОНТАЛЬНЫЙ, и по цели ростом с человека этого
		# довольно: стрела мимо всё равно кончается у земли. По туше в шесть
		# метров КАЖДЫЙ выстрел кончался на высоте живота, то есть промахов на
		# экране не было вовсе — вокруг тролля не появлялось ни одной стрелы в
		# траве. Доля выстрелов теперь намеренно идёт В ЗЕМЛЮ рядом с ним, и
		# там же втыкается штатным путём (Arrow._stick_into_ground).
		# Числа — свойство ЦЕЛИ, а не стрелка: у пехоты они нулевые, и ветка
		# стоит одно сравнение с нулём
		var miss_p: float = tu.aim_miss_chance() if tu != null else 0.0
		if miss_p > 0.0 and randf() < miss_p:
			var mang := randf() * TAU
			var moff := sqrt(randf()) * tu.aim_miss_spread()
			aim = Vector3(tbase.x + cos(mang) * moff, 0.0, tbase.z + sin(mang) * moff)

	aim = _clamp_reach(from_pos, aim, max_reach)
	var dist: float = from_pos.distance_to(aim)
	# СТРЕЛА БЕРЁТСЯ ИЗ ПУЛА, а не создаётся заново (см. GameManager.spawn_arrow):
	# комплект из узлов, меша и материала переживает выстрел и идёт в следующий.
	# Скорость и высота дуги — из unit_stats_config.gd (навесная траектория);
	# урон летит вместе со стрелой и списывается только при попадании
	# ── СТРЕЛА ПО ЗДАНИЮ ЗАПОМИНАЕТ СВОЮ ЦЕЛЬ ──────────────────────────────
	# Попадание в бойца стрела ищет сама, сканом сетки — но здание в этой
	# сетке не состоит, и стрелы по стенам просто втыкались в землю рядом, не
	# нанося ни очка. Сканировать группу зданий на каждую стрелу в каждом кадре
	# полёта незачем: стрелок и так ЗНАЕТ, куда целится, и передаёт цель вместе
	# с выстрелом. Проверка одна и в самом конце дуги.
	# СНАРЯД — ЗАПИСЬ В ЯДРЕ, НЕ УЗЕЛ (BigStand-5, этап 3): один вызов, без
	# пула; при выключенной ручке fire_projectile сам берёт узел из пула
	GameManager.fire_projectile(parent, from_pos, aim, dist, speed,
		_arrow_arc_cached(), damage, self, faction, false, false,
		target if target is Building else null)

## Досягаемость выстрела: дальность плюс поправка на габарит цели, у укрытого
## — с баффом высоты (стреляет за него модуль крыши в пределах fire_range)
const SHOT_RANGE_SLACK := 0.75
## Точка залпа дальше этого от собственной цели — устаревшая, бьём по цели
const VOLLEY_STALE_DIST := 6.0
var shots_refused_range: int = 0

func _shot_reach() -> float:
	return reach() * garrison_mult()

static func _xz_dist(a: Vector3, b: Vector3) -> float:
	var dx: float = b.x - a.x
	var dz: float = b.z - a.z
	return sqrt(dx * dx + dz * dz)

## Точка прицела не дальше досягаемости: вынос упреждения, разброс и точка
## залпа режутся по кругу дальности от стрелка (высота точки сохраняется)
func _clamp_reach(from_pos: Vector3, aim: Vector3, max_reach: float) -> Vector3:
	var d: float = _xz_dist(from_pos, aim)
	if d <= max_reach:
		return aim
	var k: float = max_reach / d
	return Vector3(from_pos.x + (aim.x - from_pos.x) * k, aim.y, from_pos.z + (aim.z - from_pos.z) * k)

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
