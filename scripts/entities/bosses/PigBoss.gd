extends Unit

## ═══════════════════════════════════════════════════════════════════════════
## СВИНОБОСС — ПОЛКОВОДЕЦ ОРДЫ НА КАБАНЕ (ТЗ 28.10.2026)
## ═══════════════════════════════════════════════════════════════════════════
## Обычный `Unit` третьей стороны на ЛЕНТАХ НАЕЗДНИКА, увеличенных втрое и
## перекрашенных в холодный металл (доспех). Бой, строй, туман, разгон и
## общая отрисовка — от базы, ровно как у туши (BigGoblin). Своего здесь:
##
##   • ГАБАРИТ. BOSS_PIXEL_SIZE, свой радиус расталкивания (тело в ядре —
##     set_body_radius по fine_ring_radius, как у тролля), кликбокс и кольцо.
##   • ДОСПЕХ. Копия листов наездника с подтоном BOSS_ARMOR_TINT — своя
##     ImageTexture, значит свой бакет общей отрисовки (ключ бакета — RID
##     листа); шейдер и FarUnitRenderer не трогаются вовсе. Перекраска —
##     один раз на сессию, кэш статический.
##   • СВИП. Удар накрывает сектор перед взглядом (как у туши): урон и
##     отброс BOSS_KNOCKBACK тем же каналом, что у конницы.
##   • АУРА ПОДАВЛЕНИЯ. Раз в BOSS_AURA_TICK строки сетки ядра в BOSS_AURA_R:
##     чужим ставится _suppressed_until_ms — их читатели аур (бонус атаки,
##     перезарядка, броня) и раздатчики (RelicManager, Monk) бонусов не дают.
##     ВЕТЕРАНСТВО (vet_*) НЕ ТРОГАЕТСЯ: это заслуженное звание отряда, а не
##     аура, — толкование наше, владельцу решать.
##   • ВАРВАРСКИЙ КЛИЧ (screech). Откат BOSS_SCREECH_CD_SEC по игровым часам
##     (Unit.game_ms), срок BOSS_SCREECH_SEC: чужие в ауре медлят один раз
##     (_hesitate_until_ms — ворота удара в Unit) и бьют ×FOE_MULT, свои ×ALLY_
##     MULT (множитель читает take_damage у ЖЕРТВЫ по полю АТАКУЮЩЕГО). Всё
##     раздаётся тем же тактом ауры, обхода всех бойцов нет.
##   • ГОБЛИНСКИЙ ГОРН (ТЗ 29.10.2026, ручка boss_horn) — тот же клич с новыми
##     числами: своим ×BOSS_HORN_ALLY_ATK_MULT атаки и ×FRAIL входящего урона
##     (Unit._frail_until_ms), чужим ×FOE_ATK; горн орды и рык отрядов в ауре.
##   • УДАР СВИНОБОССА (ТЗ 29.10.2026, ручка boss_ram) — таран строя: решение и
##     свиту ведёт мозг, здесь исполнение (ram_begin → подготовка → бег сквозь
##     BOSS_RAM_PIERCE_ROWS рядов, полоса гибели и разлёт вбок → стоп перед
##     следующим рядом → бой как у тролля BOSS_BRAWL_SEC). Копья его не держат
##     (immune_to_spears). Оружие — длина, урон и сектор туши (boss_big_weapon).
##   • ЯРОСТЬ И ИССТУПЛЕНИЕ (ТЗ 29.10.2026, 2В, ручка boss_rage): hp <=
##     BOSS_RAGE_HP — скорость ×RAGE_SPEED, перезарядка удара и откаты
##     способностей ×RAGE_CD_MULT, басовые рыки тролля/туши чаще; hp <=
##     BOSS_FRENZY_HP — ×FRENZY_SPEED, ×FRENZY_CD_MULT, взмах ×FRENZY_DMG_MULT,
##     красный накал (вспышка попадания раз в FRENZY_GLOW_SEC).
##   • БЕГСТВО НА БАЗУ (2В, ручка boss_flee_base): решение у мозга; здесь —
##     flee_to (бег ×BOSS_FLEE_SPEED_MULT с билетом выхода), recover_at_base
##     (лечение BOSS_BASE_REGEN_PER_SEC), resume_command.
##   • МОЗГ — отдельный узел PigBossCommander (решения по волне, отход при
##     BOSS_WITHDRAW_HP, возврат при BOSS_RETURN_HP); здесь только исполнение:
##     withdraw_to / resume_command и регенерация внутри своей волны.
##
## Файл без class_name: подключается через preload (как BigGoblin и Troll).

const _SSParser := preload("res://scripts/SpriteSheetParser.gd")
const _GobCfgP  := preload("res://scripts/goblin/goblin_config.gd")
const _OptPB    := preload("res://scripts/perf_config.gd")
const _UStatsPB := preload("res://scripts/unit_stats_config.gd")

const SHEET_DIR := "res://assets/factions/Goblin/"
const SHEETS := {
	"idle":   "Pig Rider_Idle.png",
	"walk":   "Pig Rider_Run.png",
	"attack": "Pig Rider_Attack.png",
}

## Перекрашенные ленты — одни на всех боссов сессии
static var _boss_frames: SpriteFrames = null
static var _boss_frames_tried: bool = false

## ── Аура и клич ────────────────────────────────────────────────────────────
var _aura_t: float = 0.0
var _cry_until_ms: int = 0            ## клич действует до
var _cry_ready_ms: int = 0            ## клич снова готов с
var _cry_id: int = 0                  ## номер клича: замешательство — раз на клич
## Стендам
var suppressed_n: int = 0             ## чужих под подавлением в последнем такте
var hesitated: int = 0                ## сколько раз выдано замешательство
var screeches: int = 0
var sweeps: int = 0
var swept_total: int = 0
var aura_ticks: int = 0
## ── Самосохранение ─────────────────────────────────────────────────────────
var _regen: bool = false              ## внутри своей волны — лечится
var _withdrawing: bool = false
var _hp_push_t: float = 0.0
## ── Горн: отряды орды в ауре, рыкнувшие на этот клич (стендам и зонду) ────
var horn_roared: int = 0
var _roar_pts: Array = []
var _roar_sids: Dictionary = {}
## ── Таран (ТЗ 29.10.2026) ──────────────────────────────────────────────────
const RAM_NONE := 0
const RAM_PREP := 1
const RAM_RUN := 2
var _ram_phase: int = RAM_NONE
var _ram_ready_ms: int = 0
var _ram_t: float = 0.0
var _ram_dir: Vector3 = Vector3.FORWARD
var _ram_origin: Vector3 = Vector3.ZERO
var _ram_stop_along: float = 0.0
var _ram_breach_along: float = 0.0
var _ram_deep_along: float = INF       ## ряд, в котором застревает: его таран не трогает
var _ram_hit: Dictionary = {}
var _ram_internal: bool = false
var ram_target_sid: int = 0
var ram_rows: PackedFloat32Array = PackedFloat32Array()
var ram_breached: bool = false
var ram_breach_at: Vector3 = Vector3.INF
var ram_kills: int = 0
var ram_flung: int = 0
var ram_end_reason: String = ""
var ram_end_along: float = 0.0
## Стендам: таранов всего, погибших от тарана за жизнь
var rams: int = 0
var ram_kills_total: int = 0
## Конец последнего тарана, игровые мс (мозг: «после тарана в ярости — бежать»)
var ram_end_ms: int = 0
## ── Выжившие под копытами, срок бега, рывки (ТЗ 30.10.2026) ─────────────────
var _ram_run_t: float = 0.0
var _ram_surv_acc: float = 0.0
var ram_trampled: int = 0              ## накрыто полосой гибели за таран (и выжившие)
var ram_survived: int = 0              ## из них выжили с BOSS_RAM_SURVIVE_HP
var ram_survived_total: int = 0
var ram_timeouts: int = 0
var _surge: int = 0                    ## 0 — таран; 1 — рывок в бою; 2 — выход насквозь; 3 — прорыв в бегстве
var _surge_n: int = 0
var _surge_t: float = 0.0
var _surge_armed: bool = false         ## конец боя после тарана — выход насквозь
var surges: int = 0
var surge_exits: int = 0
var surge_hits: int = 0
## ── Ярость, исступление, бегство (ТЗ 29.10.2026, 2В) ──────────────────────
const RAGE_NONE := 0
const RAGE_ON := 1
const RAGE_FRENZY := 2
var _rage: int = RAGE_NONE
var _rage_speed0: float = 0.0
var _rage_cd0: float = 0.0
var _growl_t: float = 0.0
var _glow_t: float = 0.0
var _fleeing: bool = false
var _base_regen: bool = false
var rage_enters: int = 0
var frenzy_enters: int = 0
var rage_growls: int = 0
var frenzy_glows: int = 0
## Бой после тарана — как у тролля: сбитые с ног, раздвинутое кольцо
var _brawl_until_ms: int = 0
var _shove_t: float = 0.0
var brawl_knockdowns: int = 0
var brawl_shoves: int = 0
## ── Кольцо ауры ────────────────────────────────────────────────────────────
var _ring: MeshInstance3D = null
var _ring_mat: StandardMaterial3D = null
var _flash_until_ms: int = 0

func is_pig_boss() -> bool:
	return true

func _ready() -> void:
	_apply_config_stats("pig_boss")
	# ОРУЖИЕ ТУШИ (ТЗ 29.10.2026): длина и урон удара — из STATS["big_goblin"],
	# сектор взмаха — BIG_SWEEP_* (см. _sw_*); запас, броня, скорость — свои
	if _OptPB.boss_big_weapon:
		var bs: Dictionary = _UStatsPB.STATS["big_goblin"]
		attack_damage = float(bs.get("attack_1", attack_damage))
		attack_range = float(bs.get("attack_range", attack_range))
	display_name = "Свинобосс"
	super._ready()
	_setup_visual()
	GameManager.pig_boss_register(self)
	GameManager.tm_event("boss_spawn", {"hp": int(max_health)})

# ─────────────────────────────────────────────────────────────────────────────
# КАРТИНКА: ЛЕНТЫ НАЕЗДНИКА ×3 В ХОЛОДНОМ МЕТАЛЛЕ
# ─────────────────────────────────────────────────────────────────────────────
func _setup_visual() -> void:
	var frames: SpriteFrames = _armored_frames()
	var asp: AnimatedSprite3D = null
	if frames != null:
		asp = _SSParser._make_sprite(frames)
	else:
		asp = _SSParser.build_sprite_from_map(SHEET_DIR, SHEETS, ["attack"])
	if asp == null:
		push_warning("PigBoss: ленты не найдены в %s" % SHEET_DIR)
		return
	for child in get_children():
		if child is MeshInstance3D and child != selection_ring:
			child.visible = false
	_apply_boss_scale(asp)
	add_child(asp)
	_active_sprite = asp

## Перекрашенный набор лент: доля BOSS_TINT_MIX цвета каждого пикселя уходит
## в «серый × подтон доспеха». Прозрачность не трогается — силуэт прежний
static func _armored_frames() -> SpriteFrames:
	if _boss_frames != null or _boss_frames_tried:
		return _boss_frames
	_boss_frames_tried = true
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	var found := false
	for anim in SHEETS:
		var src: ImageTexture = _SSParser._load_texture(SHEET_DIR.path_join(String(SHEETS[anim])))
		if src == null:
			continue
		var img: Image = src.get_image()
		if img == null:
			continue
		var tinted: Image = img.duplicate()
		_tint_image(tinted)
		_SSParser._add_frames(frames, String(anim), ImageTexture.create_from_image(tinted))
		found = true
	if not found or not frames.has_animation("idle"):
		return null
	if frames.has_animation("attack"):
		frames.set_animation_loop("attack", false)
	_boss_frames = frames
	return frames

static func _tint_image(img: Image) -> void:
	var tint: Color = _GobCfgP.BOSS_ARMOR_TINT
	var mix: float = _GobCfgP.BOSS_TINT_MIX
	var w: int = img.get_width()
	var h: int = img.get_height()
	for y in range(h):
		for x in range(w):
			var c: Color = img.get_pixel(x, y)
			if c.a <= 0.01:
				continue
			var g: float = c.r * 0.30 + c.g * 0.59 + c.b * 0.11
			var m := Color(g * tint.r, g * tint.g, g * tint.b, c.a)
			img.set_pixel(x, y, c.lerp(m, mix))

## Высота центра — по самой ленте (как у наездника и туши): центр =
## (полкадра − прозрачный низ) × размер пикселя
func _apply_boss_scale(asp: AnimatedSprite3D) -> void:
	asp.pixel_size = _GobCfgP.BOSS_PIXEL_SIZE
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
	var pad: int = _anim_bottom_px(first)
	asp.position.y = (fh * 0.5 - float(pad)) * asp.pixel_size
	var fw: float = at.region.size.x if at != null else first.get_size().x
	_body_h = (fh - float(pad)) * asp.pixel_size
	_body_w = fw * asp.pixel_size

## ── ЗНАМЯ ЗА СПИНОЙ (ТЗ 30.10.2026, скриншот 01:46) ──────────────────────
## Знамя ставилось древком к земле в точке босса, и рваное полотнище
## закрывало ему морду. Древко уходит назад от взгляда (по оси «вправо по
## экрану»), поднимается к спине всадника и чуть вглубь кадра — рисуется
## за телом. Доли — от габарита кадра: BOSS_BANNER_BACK / _UP / _DEPTH
var _body_h: float = 0.0
var _body_w: float = 0.0

func banner_offset() -> Vector3:
	if not GameManager.camera_axes_valid():
		return Vector3.ZERO
	var cr: Vector3 = GameManager.camera_right()
	var look: Vector3 = _mv_dir if (_mv_moving and _mv_dir.length_squared() > 1e-6) else _facing
	# Смотрит вправо по экрану — знамя слева, и наоборот (как зеркалит спрайт)
	var behind: float = -1.0 if cr.dot(look) >= 0.0 else 1.0
	if absf(cr.dot(look)) < 1e-3:
		behind = 1.0 if _flip_h_state else -1.0
	return cr * behind * _body_w * _GobCfgP.BOSS_BANNER_BACK \
		+ GameManager.camera_forward() * _GobCfgP.BOSS_BANNER_DEPTH \
		+ Vector3.UP * _body_h * _GobCfgP.BOSS_BANNER_UP

# ─────────────────────────────────────────────────────────────────────────────
# ГАБАРИТ: РАСТАЛКИВАНИЕ, ТЕЛО В ЯДРЕ, КЛИК, ПРИЦЕЛ, КОЛЬЦО
# ─────────────────────────────────────────────────────────────────────────────
func sep_radius() -> float:
	return SEP_MIN_DIST * _GobCfgP.SIZE_SCALE * _GobCfgP.BOSS_SIZE_SCALE * _GobCfgP.BOSS_SEP_MULT

## Аура и регенерация — часы в тике: по физике босс не спит
func may_sleep_physics() -> bool:
	return false

func pick_body_h() -> float:
	return _GobCfgP.BOSS_PICK_BODY_H

func pick_radius() -> float:
	return _GobCfgP.BOSS_PICK_R

func ring_scale() -> float:
	return _GobCfgP.BOSS_SIZE_SCALE

func fine_ring_radius() -> float:
	return _GobCfgP.BOSS_FINE_RING_R

func ring_oval() -> Vector2:
	return _GobCfgP.BOSS_RING_OVAL

func hit_flash_color() -> Color:
	return _GobCfgP.BOSS_FLASH_COLOR

func aim_height() -> float:
	return _GobCfgP.BOSS_AIM_H

func target_weight() -> float:
	return _GobCfgP.BOSS_TARGET_PRIO

func snipe_one_shot() -> bool:
	return false

func giant_class() -> bool:
	return true

func aggro_radius() -> float:
	return _GobCfgP.BOSS_AGGRO_RADIUS

func pursuit_limit() -> float:
	return _GobCfgP.BOSS_PURSUIT_LIMIT

func target_prio_mode() -> int:
	return 2

## В ярости — басовые рыки тролля и туши вперемешку (ТЗ 29.10.2026, 2В)
func _sfx_shout() -> String:
	if _rage != RAGE_NONE and (rage_growls & 1) == 1:
		return "big_grunt"
	return "troll_growl"

func _sfx_grunt() -> String:
	if _rage != RAGE_NONE:
		return "big_grunt"
	return "troll_growl"

func hit_flash_peak() -> float:
	return _GobCfgP.BOSS_FRENZY_GLOW_PEAK if _rage == RAGE_FRENZY else _GobCfgP.BOSS_FLASH_PEAK

func _sfx_hurt() -> String:
	return "troll_grunt"

func _sfx_death() -> String:
	return "goblin_death"

func _sfx_hit() -> String:
	return "sword_hit"

func _sfx_swing() -> String:
	return "big_sweep"

## Копья и «Стена копий» его не держат (ТЗ 29.10.2026, см. Unit.immune_to_spears)
func immune_to_spears() -> bool:
	return _OptPB.boss_ram

## Отходящий по решению мозга и идущий на таран чужих приказов атаки не принимают
func command_attack(target: Node3D, forced: bool = true, charge: bool = false,
		lock: bool = false) -> void:
	if _withdrawing:
		return
	if _ram_phase != RAM_NONE and not _ram_internal:
		return
	super.command_attack(target, forced, charge, lock)

## ОТХОД НЕ ПЕРЕБИВАЕТСЯ МАРШЕМ ВОЛНЫ (ТЗ 29.10.2026, разбор партии): волна,
## ложный отход и сбор орды слали command_move без keep_retreat и снимали
## отход раньше, чем босс доходил до своих. Приказ, несущий отход
## (keep_retreat — его даёт сам withdraw_to), проходит
func command_move(target_pos: Vector3, slow_march: bool = false, face_dir: Vector3 = Vector3.ZERO,
		keep_retreat: bool = false, player_order: bool = false, run: bool = false) -> void:
	if _withdrawing and not keep_retreat and state != State.DEAD:
		return
	if _ram_phase != RAM_NONE and not _ram_internal and state != State.DEAD:
		return
	super.command_move(target_pos, slow_march, face_dir, keep_retreat, player_order, run)

## Пал — окончательно: орда нового полководца не нанимает (см.
## GameManager.pig_boss_fallen). Смерть при сносе мира загрузкой признак
## тоже ставит, но SaveLoadManager.apply переписывает его из файла
func _die() -> void:
	GameManager.pig_boss_fallen = true
	var killer: String = ""
	if _slain_by != null and is_instance_valid(_slain_by) and _slain_by is Unit:
		killer = String((_slain_by as Unit).stat_id)
	GameManager.tm_event("boss_death", {"sid": squad_id, "by": killer})
	super._die()

# ─────────────────────────────────────────────────────────────────────────────
# ТИК: АУРА, КЛИЧ, РЕГЕНЕРАЦИЯ, КОЛЬЦО
# ─────────────────────────────────────────────────────────────────────────────
func tick_physics(delta: float, prof: bool = false, bm: bool = true,
		bonus_ver: int = -1) -> void:
	# Таран ведёт тело сам: базовый автомат (шаг, бой, агро) на это время молчит
	var rammed: bool = false
	if _ram_phase != RAM_NONE and state != State.DEAD:
		rammed = _tick_ram(delta)
	if not rammed:
		super.tick_physics(delta, prof, bm, bonus_ver)
	if state == State.DEAD:
		_ram_phase = RAM_NONE
		_hide_ring()
		return
	_aura_t -= delta
	if _aura_t <= 0.0:
		_aura_t = _GobCfgP.BOSS_AURA_TICK
		_tick_aura()
	_tick_brawl(delta)
	_tick_flee_break(delta)
	_tick_rage(delta)
	if _regen and current_health < max_health:
		var rate: float = _GobCfgP.BOSS_BASE_REGEN_PER_SEC if _base_regen else _GobCfgP.BOSS_REGEN_PER_SEC
		current_health = minf(max_health, current_health + max_health * rate * delta)
		_hp_push_t -= delta
		if _hp_push_t <= 0.0:
			_hp_push_t = _GobCfgP.BOSS_AURA_TICK
			_soa_push_stats()
	_tick_ring()

## ОДИН ПРОХОД по строкам ядра в радиусе ауры: подавление чужим, клич — всем.
## Срок удержания перекрывает такт с запасом (BOSS_AURA_HOLD_MS > TICK)
func _tick_aura() -> void:
	var scr: bool = screech_active()
	var sup: bool = _OptPB.boss_aura
	if not sup and not scr:
		suppressed_n = 0
		return
	aura_ticks += 1
	var reg: Array = GameManager._row_units
	var cap: int = reg.size()
	var mp: Vector3 = position if _local_xform else global_position
	var rows: PackedInt32Array = GameManager.unit_grid.query_radius_rows(mp, _GobCfgP.BOSS_AURA_R)
	var until: int = now_ms + _GobCfgP.BOSS_AURA_HOLD_MS
	var n_sup := 0
	for row in rows:
		if row >= cap:
			continue
		var raw = reg[row]
		if raw == null or not is_instance_valid(raw):
			continue
		var u := raw as Unit
		if u == null or u == self or u.is_dead():
			continue
		if u.faction != faction:
			if sup:
				u._suppressed_until_ms = until
				n_sup += 1
			if scr:
				u._screech_until_ms = _cry_until_ms
				u._screech_mult = _GobCfgP.BOSS_HORN_FOE_ATK_MULT if _OptPB.boss_horn \
					else _GobCfgP.BOSS_SCREECH_FOE_MULT
				# Замешательство — ОДИН раз на клич, а не каждый такт
				if u._screech_seen != _cry_id:
					u._screech_seen = _cry_id
					u._hesitate_until_ms = now_ms + int(_GobCfgP.BOSS_HESITATE_SEC * 1000.0)
					hesitated += 1
		elif scr:
			u._screech_until_ms = _cry_until_ms
			if _OptPB.boss_horn:
				u._screech_mult = _GobCfgP.BOSS_HORN_ALLY_ATK_MULT
				u._frail_until_ms = _cry_until_ms
				u._frail_mult = _GobCfgP.BOSS_HORN_ALLY_FRAIL_MULT
				# Рык — по отряду, а не по бойцу: точка — первый встреченный боец
				if _roar_pending and u.squad_id > 0 and not _roar_sids.has(u.squad_id):
					_roar_sids[u.squad_id] = true
					_roar_pts.append(u.position if u._local_xform else u.global_position)
			else:
				u._screech_mult = _GobCfgP.BOSS_SCREECH_ALLY_MULT
	suppressed_n = n_sup

func screech_active() -> bool:
	return _OptPB.boss_screech and now_ms < _cry_until_ms

func screech_ready() -> bool:
	return _OptPB.boss_screech and now_ms >= _cry_ready_ms

## Клич: срок, откат по игровым часам, звук, вспышка кольца, такт ауры сразу
func screech() -> bool:
	if not screech_ready():
		return false
	_cry_id += 1
	_cry_until_ms = now_ms + int(_GobCfgP.BOSS_SCREECH_SEC * 1000.0)
	_cry_ready_ms = now_ms + int(_GobCfgP.BOSS_SCREECH_CD_SEC * _cd_mult() * 1000.0)
	_flash_until_ms = now_ms + _GobCfgP.BOSS_RING_FLASH_MS
	screeches += 1
	var mp: Vector3 = position if _local_xform else global_position
	AudioManager.play_3d("boss_screech", mp)
	_aura_t = 0.0
	_roar_pending = _OptPB.boss_horn
	_roar_pts.clear()
	_roar_sids.clear()
	_tick_aura()
	_roar_pending = false
	horn_roared = 0
	if _OptPB.boss_horn:
		# ГОРН И ОТВЕТНЫЙ РЫК ОРДЫ (ТЗ 29.10.2026): горн — канал горна орды,
		# рык — нарезки гоблинов из отрядов в ауре, ближние первыми
		AudioManager.play_horn()
		_roar_pts.sort_custom(func(a, b): return mp.distance_squared_to(a) < mp.distance_squared_to(b))
		if _roar_pts.size() > _GobCfgP.BOSS_HORN_ROAR_SQUADS:
			_roar_pts.resize(_GobCfgP.BOSS_HORN_ROAR_SQUADS)
		horn_roared = _roar_sids.size()
		AudioManager.play_horde_roar(_roar_pts)
	return true

var _roar_pending: bool = false

# ─────────────────────────────────────────────────────────────────────────────
# САМОСОХРАНЕНИЕ: ИСПОЛНЕНИЕ РЕШЕНИЙ МОЗГА
# ─────────────────────────────────────────────────────────────────────────────
func is_withdrawing() -> bool:
	return _withdrawing

## Отход: билет выхода из тел (begin_retreat), точка — от мозга
func withdraw_to(p: Vector3) -> void:
	if _ram_phase != RAM_NONE:
		_ram_end("withdraw")
	_withdrawing = true
	_regen = true
	begin_retreat()
	command_move(GameManager.land_target(p), false, Vector3.ZERO, true)

func resume_command() -> void:
	_withdrawing = false
	_regen = false
	_fleeing = false
	_base_regen = false
	# Фаза по текущему hp: исцелённый выходит без ярости в тот же такт
	_rage = rage_level()
	_apply_pace()
	if retreating:
		end_retreat(true)

## БЕГСТВО НА БАЗУ (ТЗ 29.10.2026, 2В): таран прерван, отход с билетом
## выхода из тел, бегом ×BOSS_FLEE_SPEED_MULT; лечения в пути нет — на базе
func flee_to(p: Vector3) -> void:
	if _ram_phase != RAM_NONE:
		_ram_end("withdraw")
	_brawl_until_ms = 0
	_withdrawing = true
	_fleeing = true
	_regen = false
	_base_regen = false
	begin_retreat()
	_apply_pace()
	_flee_goal = p
	_flee_dash_t = 0.0
	command_move(GameManager.land_target(p), false, Vector3.ZERO, true, false, true)

## ── ПРОРЫВ В БЕГСТВЕ (ТЗ 31.10.2026) ─────────────────────────────────────
## «В критический момент убегать и, расталкивая войска, скрываться»: бегущий
## босс упирался в чужой строй (билет отхода сужает тело, но сквозь шеренгу
## не ведёт) и стоял в нём. Теперь чужие впереди по курсу к базе → рывок
## насквозь (RAM_RUN, _surge 3) на BOSS_FLEE_DASH_DIST: накрытые — отлёт вбок
## и падение, урон крошечный; между рывками тело идёт сквозь тела
var _flee_goal: Vector3 = Vector3.INF
var _flee_dash_t: float = 0.0
var flee_dashes: int = 0

func _tick_flee_break(delta: float) -> void:
	if not _fleeing or not _OptPB.boss_flee_break or _ram_phase != RAM_NONE or _flee_goal.x == INF:
		return
	breaks_bodies = true
	_flee_dash_t -= delta
	if _flee_dash_t > 0.0:
		return
	var mp: Vector3 = global_position
	var to := Vector3(_flee_goal.x - mp.x, 0.0, _flee_goal.z - mp.z)
	if to.length() < _GobCfgP.BOSS_BASE_ARRIVE_R:
		return
	var dir: Vector3 = to.normalized()
	# Курс — ход маршрута, если он есть (обход леса), иначе прямо на базу
	if velocity.length_squared() > 0.25:
		var v := Vector3(velocity.x, 0.0, velocity.z).normalized()
		if v.dot(dir) > 0.0:
			dir = v
	var probe: Vector3 = mp + dir * _GobCfgP.BOSS_FLEE_PROBE_AHEAD
	if GameManager.unit_grid.enemy_count(probe, _GobCfgP.BOSS_FLEE_PROBE_R, faction) <= 0:
		return
	_flee_dash_t = _GobCfgP.BOSS_FLEE_DASH_CD_SEC
	flee_dashes += 1
	_ram_dir = dir
	_surge_begin(3, minf(_GobCfgP.BOSS_FLEE_DASH_DIST, to.length()))

func is_fleeing() -> bool:
	return _fleeing

## Дошёл до базы: стоит и лечится BOSS_BASE_REGEN_PER_SEC; приказов волны не
## принимает (_withdrawing), пока мозг не вернёт его в строй (resume_command)
func recover_at_base() -> void:
	_fleeing = false
	_regen = true
	_base_regen = true
	if retreating:
		end_retreat(true)
	_halt_here()
	_apply_pace()

func is_recovering() -> bool:
	return _base_regen and _withdrawing

# ─────────────────────────────────────────────────────────────────────────────
# ЯРОСТЬ И ИССТУПЛЕНИЕ (ТЗ 29.10.2026, 2В)
# ─────────────────────────────────────────────────────────────────────────────
func rage_level() -> int:
	if not _OptPB.boss_rage:
		return RAGE_NONE
	var f: float = hp_frac()
	if f <= _GobCfgP.BOSS_FRENZY_HP:
		return RAGE_FRENZY
	if f <= _GobCfgP.BOSS_RAGE_HP:
		return RAGE_ON
	return RAGE_NONE

## Множитель откатов (перезарядка удара, горн, таран) по фазе ярости
func _cd_mult() -> float:
	match _rage:
		RAGE_FRENZY: return _GobCfgP.BOSS_FRENZY_CD_MULT
		RAGE_ON: return _GobCfgP.BOSS_RAGE_CD_MULT
	return 1.0

func _speed_mult() -> float:
	var k: float = 1.0
	match _rage:
		RAGE_FRENZY: k = _GobCfgP.BOSS_FRENZY_SPEED
		RAGE_ON: k = _GobCfgP.BOSS_RAGE_SPEED
	if _fleeing:
		k *= _GobCfgP.BOSS_FLEE_SPEED_MULT
	return k

## Скорость и перезарядка от базовых (снимаются при первом обращении: кузница
## орды правит статы уже после _ready) — пересчёт только при смене фазы
func _apply_pace() -> void:
	if _rage_speed0 <= 0.0:
		_rage_speed0 = move_speed
		_rage_cd0 = attack_cooldown
	move_speed = _rage_speed0 * _speed_mult()
	attack_cooldown = _rage_cd0 * _cd_mult()
	_soa_push_stats()

func _tick_rage(delta: float) -> void:
	var lvl: int = rage_level()
	if lvl != _rage:
		var was: int = _rage
		_rage = lvl
		if lvl == RAGE_ON and was == RAGE_NONE:
			rage_enters += 1
		if lvl == RAGE_FRENZY:
			frenzy_enters += 1
		_growl_t = 0.0
		_apply_pace()
		var cmd = GameManager.main.get("pig_boss_cmd") if GameManager.main != null else null
		if cmd != null and is_instance_valid(cmd) and lvl > was:
			cmd.call("_bprobe", "boss_rage", {"lvl": lvl, "hp": snappedf(hp_frac(), 0.01),
				"speed": snappedf(move_speed, 0.01), "cd": snappedf(attack_cooldown, 0.01)},
				"%s: hp %.2f, скорость %.2f, перезарядка %.2f с" % [
				"исступление" if lvl == RAGE_FRENZY else "ярость", hp_frac(), move_speed, attack_cooldown])
	if _rage == RAGE_NONE:
		return
	# Рыки чаще: в ярости раз в BOSS_RAGE_GROWL_SEC, в исступлении вдвое чаще
	_growl_t -= delta
	if _growl_t <= 0.0:
		_growl_t = _GobCfgP.BOSS_RAGE_GROWL_SEC * (0.5 if _rage == RAGE_FRENZY else 1.0)
		rage_growls += 1
		AudioManager.play_3d("troll_growl" if (rage_growls & 1) == 1 else "big_grunt", global_position)
	# Исступление: красный накал — вспышка попадания (подтон BOSS_FLASH_COLOR) без перерыва
	if _rage == RAGE_FRENZY:
		_glow_t -= delta
		if _glow_t <= 0.0:
			_glow_t = _GobCfgP.BOSS_FRENZY_GLOW_SEC
			frenzy_glows += 1
			_frenzy_glow()

func _frenzy_glow() -> void:
	if _rb_bound and _Opt.vis_core_path and _Opt.vis_quiet_rows and _soa >= 0:
		GameManager.army.vis_hit(_soa, _GobCfgP.BOSS_FRENZY_GLOW_PEAK, _GobCfgP.BOSS_FRENZY_GLOW_SEC * 1.4)
	else:
		_hit_flash = HIT_FLASH_SEC
		_dmg_dirty = true
		_push_damage_shade()

func set_regen(on: bool) -> void:
	_regen = on

func hp_frac() -> float:
	return current_health / maxf(max_health, 1.0)

# ─────────────────────────────────────────────────────────────────────────────
# УДАР: СЕКТОР ПЕРЕД ВЗГЛЯДОМ, ОТБРОС (как у туши)
# ─────────────────────────────────────────────────────────────────────────────
func _strike_damage() -> float:
	_play_attack_anim("attack", 420)
	var t := attack_target
	if t != null and is_instance_valid(t):
		var tp: Vector3 = (t as Node3D).global_position
		var mp0: Vector3 = position if _local_xform else global_position
		var to := Vector3(tp.x - mp0.x, 0.0, tp.z - mp0.z)
		if to.length_squared() > 1e-4:
			_facing = to.normalized()
	_sweep_now()
	_hit_building()
	return attack_damage

func _damage_on_strike() -> bool:
	return false          # урон несёт свип

func _hit_building() -> void:
	var t := attack_target
	if t == null or not is_instance_valid(t) or not (t is Building) or (t as Building).is_dead():
		return
	var tp: Vector3 = (t as Node3D).global_position
	var mp: Vector3 = position if _local_xform else global_position
	var r: float = attack_range + _pad_of(t) + MELEE_HIT_MISS_SLACK + _sw_half()
	if Vector2(tp.x - mp.x, tp.z - mp.z).length_squared() > r * r:
		return
	(t as Building).take_damage((attack_damage + _upgrade_damage_bonus()) * _GobCfgP.BOSS_BUILDING_DMG_MULT, self)

## Сектор взмаха: у туши (ТЗ 29.10.2026, boss_big_weapon) или свой
func _sw_half() -> float:
	return _GobCfgP.BIG_SWEEP_HALF_W if _OptPB.boss_big_weapon else _GobCfgP.BOSS_SWEEP_HALF_W

func _sw_arc() -> float:
	return _GobCfgP.BIG_SWEEP_ARC_COS if _OptPB.boss_big_weapon else _GobCfgP.BOSS_SWEEP_ARC_COS

func _sw_max() -> int:
	return _GobCfgP.BIG_SWEEP_MAX if _OptPB.boss_big_weapon else _GobCfgP.BOSS_SWEEP_MAX

func _sw_kb() -> float:
	return _GobCfgP.BIG_KNOCKBACK if _OptPB.boss_big_weapon else _GobCfgP.BOSS_KNOCKBACK

func _sweep_now() -> void:
	var dir: Vector3 = _facing
	if dir.length_squared() < 1e-6:
		dir = Vector3(0.0, 0.0, -1.0)
	dir = dir.normalized()
	var mp: Vector3 = position if _local_xform else global_position
	var reach: float = attack_range + _sw_half()
	var brawl: bool = brawling()
	var hits: Array = GameManager.unit_grid.query_radius(mp, reach)
	var picked: Array = []
	for n in hits:
		if n == null or not is_instance_valid(n):
			continue
		var u := n as Unit
		if u == null or u.is_dead() or u.faction == faction:
			continue
		var dp: Vector3 = u.position if u._local_xform else u.global_position
		var to := Vector3(dp.x - mp.x, 0.0, dp.z - mp.z)
		var d: float = to.length()
		if d < 0.01:
			picked.append([0.0, u])
			continue
		if to.normalized().dot(dir) < _sw_arc():
			continue
		picked.append([d, u])
	if picked.is_empty():
		return
	picked.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var dmg: float = attack_damage + _upgrade_damage_bonus()
	# Исступление: сокрушительные удары — прорваться из окружения
	if _rage == RAGE_FRENZY:
		dmg *= _GobCfgP.BOSS_FRENZY_DMG_MULT
	var n_hit := 0
	for row in picked:
		if n_hit >= _sw_max():
			break
		var u := (row[1]) as Unit
		if u == null or not is_instance_valid(u) or u.is_dead():
			continue
		n_hit += 1
		u.take_damage(dmg, self)
		if is_instance_valid(u) and not u.is_dead():
			var away := Vector3(u.global_position.x - mp.x, 0.0, u.global_position.z - mp.z)
			if away.length_squared() < 1e-4:
				away = dir
			u.apply_knockback(away.normalized(), _sw_kb(), mp)
			# После тарана — дубина тролля: накрытый лежит (Troll._release_swing)
			if brawl:
				u.knock_down(_GobCfgP.TROLL_KNOCKDOWN_SEC)
				brawl_knockdowns += 1
	if n_hit > 0:
		sweeps += 1
		swept_total += n_hit
		AudioManager.play_3d("big_sweep", mp)
		_grunt_attack()

# ─────────────────────────────────────────────────────────────────────────────
# УДАР СВИНОБОССА: ТАРАН СТРОЯ (ТЗ 29.10.2026)
# ─────────────────────────────────────────────────────────────────────────────
## Решение (кого, когда, со свитой) — у мозга; здесь исполнение. Бег пишет
## координату сам (как разлёт, _tick_fling), мимо пакетного шага: чужие тела и
## копья его не держат — в этом и суть способности. Вода и непроходимое — стоп
func ram_ready() -> bool:
	return _OptPB.boss_ram and _ram_phase == RAM_NONE and not _withdrawing \
		and now_ms >= _ram_ready_ms

func ram_phase() -> int:
	return _ram_phase

func ram_ready_in() -> float:
	return maxf(float(_ram_ready_ms - now_ms) * 0.001, 0.0)

func horn_ready_in() -> float:
	return maxf(float(_cry_ready_ms - now_ms) * 0.001, 0.0)

func brawling() -> bool:
	return now_ms < _brawl_until_ms

## Начать таран отряда target_sid: откат взводится сразу, подготовка
## BOSS_RAM_PREP_SEC (босс встаёт лицом к строю, свита собирается за спиной)
func ram_begin(target_sid: int) -> bool:
	if not ram_ready():
		return false
	var c: Vector2 = GameManager.squad_centre_xz(target_sid)
	if c == Vector2.INF:
		return false
	var mp: Vector3 = global_position
	var to := Vector3(c.x - mp.x, 0.0, c.y - mp.z)
	if to.length_squared() < 1.0:
		return false
	_ram_dir = to.normalized()
	ram_target_sid = target_sid
	_ram_ready_ms = now_ms + int(_GobCfgP.BOSS_RAM_CD_SEC * _cd_mult() * 1000.0)
	_ram_phase = RAM_PREP
	_ram_t = _GobCfgP.BOSS_RAM_PREP_SEC
	ram_breached = false
	ram_breach_at = Vector3.INF
	ram_kills = 0
	ram_flung = 0
	ram_end_reason = ""
	ram_trampled = 0
	ram_survived = 0
	_surge = 0
	_surge_armed = false
	_ram_hit.clear()
	rams += 1
	_halt_here()
	_facing = _ram_dir
	return true

## Встать: ни цели, ни хода, строка ядра — в покой
func _halt_here() -> void:
	_core_release()
	set_attack_target(null)
	_atk_pending = false
	_attack_is_forced = false
	velocity = Vector3.ZERO
	_march_pending = false
	_move_lock = 0.0
	is_charging = false
	_hold_where_i_stand()
	state = State.IDLE
	if _soa >= 0:
		GameManager.army.set_state(_soa, State.IDLE)
		GameManager.army.set_vel(_soa, 0.0, 0.0)

## РЯДЫ СТРОЯ ПО ХОДУ: бойцы отряда-цели в полосе BOSS_RAM_ROW_LANE поперёк
## курса, по проекции на курс; разрыв больше BOSS_RAM_ROW_GAP — новый ряд.
## Стоп — перед рядом номер BOSS_RAM_PIERCE_ROWS, брешь — за последним
## пробиваемым. Ряды считаются в момент старта бега, по факту стоящих
func _ram_plan() -> void:
	_ram_origin = global_position
	# Курс — ещё раз на центр цели: за подготовку строй мог сместиться
	var c: Vector2 = GameManager.squad_centre_xz(ram_target_sid)
	if c != Vector2.INF:
		var to := Vector3(c.x - _ram_origin.x, 0.0, c.y - _ram_origin.z)
		if to.length_squared() > 1.0:
			_ram_dir = to.normalized()
	var side := Vector3(-_ram_dir.z, 0.0, _ram_dir.x)
	var al: Array = []
	var sq: Variant = GameManager.squads.get(ram_target_sid)
	if sq != null:
		for raw in ((sq as Dictionary)["members"] as Array):
			if not is_instance_valid(raw):
				continue
			var u := raw as Unit
			if u == null or u.is_dead():
				continue
			var off: Vector3 = u.global_position - _ram_origin
			var a: float = off.x * _ram_dir.x + off.z * _ram_dir.z
			var l: float = off.x * side.x + off.z * side.z
			if a > 0.0 and absf(l) <= _GobCfgP.BOSS_RAM_ROW_LANE:
				al.append(a)
	al.sort()
	ram_rows = PackedFloat32Array()
	var prev := -INF
	for a in al:
		if float(a) - prev > _GobCfgP.BOSS_RAM_ROW_GAP:
			ram_rows.append(float(a))
		prev = float(a)
	var pr: int = _GobCfgP.BOSS_RAM_PIERCE_ROWS
	_ram_deep_along = INF
	if ram_rows.size() > pr:
		# Застревает В следующем ряду: за последним пробитым, но не дальше
		# STOP_GAP до него (у плотного строя ряды ближе STOP_GAP)
		_ram_stop_along = maxf(ram_rows[pr] - _GobCfgP.BOSS_RAM_STOP_GAP, ram_rows[pr - 1] + 0.25)
		_ram_breach_along = ram_rows[pr - 1] + 0.25
		_ram_deep_along = ram_rows[pr] - _GobCfgP.BOSS_RAM_ROW_GAP * 0.5
	elif not ram_rows.is_empty():
		_ram_stop_along = ram_rows[ram_rows.size() - 1] + 1.5
		_ram_breach_along = ram_rows[ram_rows.size() - 1] + 0.3
	else:
		_ram_stop_along = _GobCfgP.BOSS_RAM_MAX_DIST * 0.5
		_ram_breach_along = _ram_stop_along
	_ram_stop_along = minf(_ram_stop_along, _GobCfgP.BOSS_RAM_MAX_DIST)
	_ram_breach_along = minf(_ram_breach_along, _ram_stop_along)

## Такт тарана; true — тело вёл таран, базовый автомат пропускается
func _tick_ram(delta: float) -> bool:
	if _ram_phase == RAM_PREP:
		_ram_t -= delta
		_facing = _ram_dir
		_sample_movement()
		if _ram_t <= 0.0:
			_ram_plan()
			_ram_phase = RAM_RUN
			_ram_run_t = 0.0
			_play_attack_anim("attack", 420)
			AudioManager.play_3d("boss_screech", global_position)
		return true
	if _ram_phase != RAM_RUN:
		return false
	# ── БЕГ — ЭТО ХОД, А НЕ ПОКОЙ (ТЗ 30.10.2026) ────────────────────────────
	# После _halt_here строка ядра стояла в IDLE, а стоящего гиганта своё
	# разведение толкает: свита, бегущая «в прорыв за спину», выдавливала босса
	# назад быстрее, чем он бежал, — второй таран партии 30.10 шёл 45 с,
	# раскидал 189. Идущего гиганта мелкие свои не толкают (BatchSeparation)
	if _OptPB.boss_ram_survive:
		_ram_run_t += delta
		if _ram_run_t >= _GobCfgP.BOSS_RAM_RUN_MAX_SEC:
			ram_timeouts += 1
			_ram_end("timeout")
			return true
		state = State.MOVING
		velocity = _ram_dir * move_speed * _GobCfgP.BOSS_RAM_SPEED_MULT
		if _soa >= 0:
			GameManager.army.set_state(_soa, State.MOVING)
			GameManager.army.set_vel(_soa, velocity.x, velocity.z)
	var mp: Vector3 = global_position
	var along_now: float = (mp.x - _ram_origin.x) * _ram_dir.x + (mp.z - _ram_origin.z) * _ram_dir.z
	var step: float = move_speed * _GobCfgP.BOSS_RAM_SPEED_MULT * delta
	var along_to: float = minf(along_now + step, _ram_stop_along)
	var np: Vector3 = _ram_origin + _ram_dir * along_to
	if GameManager.is_water(np.x, np.z) or not GameManager.is_passable(np.x, np.z):
		_ram_end("terrain")
		return true
	var lim: Vector2 = GameManager.clamp_to_map(np.x, np.z)
	np = Vector3(lim.x, GameManager.get_terrain_height(lim.x, lim.y), lim.y)
	global_position = np
	sync_row()
	_facing = _ram_dir
	_ram_hits(np)
	if not ram_breached and along_to >= _ram_breach_along:
		ram_breached = true
		ram_breach_at = np
	_sample_movement()
	if along_to >= _ram_stop_along - 1e-3:
		if _surge != 0:
			_ram_end("surge")
		else:
			_ram_end("rows" if ram_rows.size() > _GobCfgP.BOSS_RAM_PIERCE_ROWS else "through")
	return true

## Накрытые бегом: полоса гибели по оси, остальные — урон долей запаса, отлёт
## вбок и падение. Ряд, перед которым босс встанет, не трогается
func _ram_hits(mp: Vector3) -> void:
	var side := Vector3(-_ram_dir.z, 0.0, _ram_dir.x)
	var deep: float = minf(_ram_deep_along, _ram_stop_along + _GobCfgP.BOSS_RAM_STOP_GAP * 0.5)
	for n in GameManager.unit_grid.query_radius(mp, _GobCfgP.BOSS_RAM_HIT_R):
		if n == null or not is_instance_valid(n):
			continue
		var u := n as Unit
		if u == null or u.is_dead() or u.faction == faction or u._ghost:
			continue
		var iid: int = u.get_instance_id()
		if _ram_hit.has(iid):
			continue
		var up: Vector3 = u.global_position
		var rel_a: float = (up.x - mp.x) * _ram_dir.x + (up.z - mp.z) * _ram_dir.z
		if rel_a < -0.8:
			continue
		var ab_a: float = (up.x - _ram_origin.x) * _ram_dir.x + (up.z - _ram_origin.z) * _ram_dir.z
		if ab_a > deep:
			continue
		_ram_hit[iid] = true
		var lat: float = (up.x - _ram_origin.x) * side.x + (up.z - _ram_origin.z) * side.z
		var surv: bool = _OptPB.boss_ram_survive
		var lane_cap: int = ram_trampled if surv else ram_kills
		if _surge == 0 and absf(lat) <= _GobCfgP.BOSS_RAM_KILL_LANE and lane_cap < _GobCfgP.BOSS_RAM_KILL_MAX:
			ram_trampled += 1
			# ── ПОЛОВИНА РАСТОПТАННЫХ ВЫЖИВАЕТ (ТЗ 30.10.2026) ──────────────
			# Накопитель, а не жребий: доля держится в каждом таране, а сеяные
			# лотереи партии (AudioManager.rng) не сдвигаются
			var lives: bool = false
			if surv:
				_ram_surv_acc += _GobCfgP.BOSS_RAM_SURVIVE_SHARE
				if _ram_surv_acc >= 1.0:
					_ram_surv_acc -= 1.0
					lives = true
			if not lives:
				ram_kills += 1
				ram_kills_total += 1
				u.take_damage(u.max_health * 100.0, self)
				continue
			var keep: float = u.max_health * _GobCfgP.BOSS_RAM_SURVIVE_HP
			if u.current_health > keep:
				u.take_frac_damage((u.current_health - keep) / u.max_health, self)
			if not is_instance_valid(u) or u.is_dead():
				ram_kills += 1
				ram_kills_total += 1
				continue
			ram_survived += 1
			ram_survived_total += 1
		elif _surge == 3:
			u.take_frac_damage(_GobCfgP.BOSS_FLEE_DASH_FRAC, self)
		elif _surge != 0:
			surge_hits += 1
			u.take_frac_damage(_GobCfgP.BOSS_SURGE_FRAC, self)
		else:
			u.take_frac_damage(_GobCfgP.BOSS_RAM_SIDE_FRAC, self)
		if not is_instance_valid(u) or u.is_dead():
			ram_kills_total += 1
			continue
		var sgn: float = signf(lat)
		if sgn == 0.0:
			sgn = 1.0 if (iid & 1) == 0 else -1.0
		var away: Vector3 = (side * sgn * 0.85 + _ram_dir * 0.35).normalized()
		u.apply_knockback(away, _GobCfgP.BOSS_RAM_SIDE_KNOCK, mp)
		u.knock_down(_GobCfgP.BOSS_RAM_KNOCKDOWN_SEC)
		ram_flung += 1

## Конец тарана: босс в бою «как тролль» BOSS_BRAWL_SEC, цель — ближайший
## чужой у морды (обычно третий ряд)
func _ram_end(reason: String) -> void:
	var mp: Vector3 = global_position
	if _surge != 0:
		_surge_end(reason)
		return
	ram_end_reason = reason
	ram_end_along = (mp.x - _ram_origin.x) * _ram_dir.x + (mp.z - _ram_origin.z) * _ram_dir.z
	if not ram_breached and reason != "withdraw" and _ram_phase == RAM_RUN:
		ram_breach_at = mp
	_ram_phase = RAM_NONE
	ram_end_ms = now_ms
	if reason == "withdraw":
		return
	_brawl_until_ms = now_ms + int(_GobCfgP.BOSS_BRAWL_SEC * 1000.0)
	if _OptPB.boss_surge:
		_surge_n = 0
		_surge_t = _GobCfgP.BOSS_SURGE_FIRST_SEC
		_surge_armed = true
	_brawl_engage(mp)

## Встать и бить ближайшего у морды
func _brawl_engage(mp: Vector3) -> void:
	_hold_where_i_stand()
	if state == State.MOVING:
		state = State.IDLE
		velocity = Vector3.ZERO
		if _soa >= 0:
			GameManager.army.set_state(_soa, State.IDLE)
			GameManager.army.set_vel(_soa, 0.0, 0.0)
	var foe: Node3D = GameManager.unit_grid.enemy_at(mp, attack_range + 3.0, faction)
	if foe != null and is_instance_valid(foe):
		_ram_internal = true
		command_attack(foe, true)
		_ram_internal = false

## ── РЫВКИ В БОЮ И ВЫХОД НАСКВОЗЬ (ТЗ 30.10.2026) ────────────────────────────
## «Забежать, ударить, расталкивать, чуть пробежать дальше, снова подраться и
## выскочить, не застревая»: в окружении раз в BOSS_SURGE_EVERY_SEC — короткий
## бег тем же курсом на BOSS_SURGE_DIST (урон долей, отлёт, падение — без
## гибели), в конце боя — бег насквозь на BOSS_SURGE_EXIT_DIST. Ход — тот же
## RAM_RUN; статистика тарана (ram_end_reason, ряды, убитые) не трогается
func _surge_begin(kind: int, dist: float) -> void:
	_surge = kind
	_core_release()
	set_attack_target(null)
	_atk_pending = false
	_ram_origin = global_position
	_ram_stop_along = dist
	_ram_breach_along = INF
	_ram_deep_along = INF
	_ram_hit.clear()
	_ram_run_t = 0.0
	_ram_phase = RAM_RUN
	_facing = _ram_dir
	_play_attack_anim("attack", 420)
	if kind == 2:
		surge_exits += 1
	elif kind == 1:
		surges += 1
		_surge_n += 1

func _surge_end(reason: String) -> void:
	var kind: int = _surge
	_surge = 0
	_ram_phase = RAM_NONE
	if reason == "withdraw":
		return
	var mp: Vector3 = global_position
	if kind == 3:
		# Прорвался — бег к базе дальше тем же приказом
		if _fleeing and _flee_goal.x != INF:
			command_move(GameManager.land_target(_flee_goal), false, Vector3.ZERO, true, false, true)
		return
	if kind == 2:
		_brawl_until_ms = 0
		_hold_where_i_stand()
		state = State.IDLE
		if _soa >= 0:
			GameManager.army.set_state(_soa, State.IDLE)
			GameManager.army.set_vel(_soa, 0.0, 0.0)
		return
	_brawl_engage(mp)

## Бой после тарана: окружили — тело пробивает чужие тела шагом (как у
## тролля, бит прохода) и раз в TROLL_SHOVE_SEC раздвигает кольцо
func _tick_brawl(delta: float) -> void:
	if not brawling():
		if breaks_bodies:
			breaks_bodies = false
		if _surge_armed:
			_surge_armed = false
			if _OptPB.boss_surge and _ram_phase == RAM_NONE and not _withdrawing and not _fleeing \
					and GameManager.unit_grid.enemy_count(global_position,
					attack_range + _GobCfgP.TROLL_SWEEP_REACH_PAD, faction) > 0:
				_surge_begin(2, _GobCfgP.BOSS_SURGE_EXIT_DIST)
		return
	var mp: Vector3 = global_position
	var reach: float = attack_range + _GobCfgP.TROLL_SWEEP_REACH_PAD
	var foes: int = GameManager.unit_grid.enemy_count(mp, reach, faction)
	breaks_bodies = foes >= _GobCfgP.TROLL_SURROUND_FOES
	if _OptPB.boss_surge and _ram_phase == RAM_NONE and _surge_n < _GobCfgP.BOSS_SURGE_MAX:
		_surge_t -= delta
		if _surge_t <= 0.0 and breaks_bodies:
			_surge_t = _GobCfgP.BOSS_SURGE_EVERY_SEC
			_surge_begin(1, _GobCfgP.BOSS_SURGE_DIST)
			return
	_shove_t -= delta
	if breaks_bodies and _shove_t <= 0.0:
		_shove_t = _GobCfgP.TROLL_SHOVE_SEC
		brawl_shoves += 1
		for n in GameManager.unit_grid.query_radius(mp, reach):
			if n == null or not is_instance_valid(n):
				continue
			var v := n as Unit
			if v == null or v.is_dead() or v.faction == faction:
				continue
			var off: Vector3 = v.global_position - mp
			off.y = 0.0
			var d: float = off.length()
			var dirn: Vector3 = off / d if d > 0.05 else _ram_dir
			v.apply_knockback(dirn, _GobCfgP.TROLL_SHOVE_PUSH, mp)

# ─────────────────────────────────────────────────────────────────────────────
# КОЛЬЦО АУРЫ: ВИДНО ПОД КУРСОРОМ, КАК ЦЕЛЬ ПРИКАЗА И НА ВСПЫШКЕ КЛИЧА
# ─────────────────────────────────────────────────────────────────────────────
## Та же конструкция, что у RelicManager._ring_node / _update_tower_range_view:
## плоский тор единичного радиуса, растянутый по XZ до BOSS_AURA_R, без
## теста глубины (ручка aura_ring_no_depth), узел — в корне мира
func _ring_node() -> MeshInstance3D:
	if _ring != null and is_instance_valid(_ring):
		return _ring
	var m = GameManager.main
	if m == null or not is_instance_valid(m) or not m.has_method("world_root"):
		return null
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.albedo_color = _GobCfgP.BOSS_RING_COLOR
	_ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if _OptPB.aura_ring_no_depth:
		_ring_mat.no_depth_test = true
		_ring_mat.render_priority = 10
	var tm := TorusMesh.new()
	tm.inner_radius = 0.988
	tm.outer_radius = 1.0
	tm.rings = 96
	tm.ring_segments = 3
	var mi := MeshInstance3D.new()
	mi.name = "PigBossAuraRing"
	mi.mesh = tm
	mi.material_override = _ring_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	(m.call("world_root") as Node3D).add_child(mi)
	_ring = mi
	return mi

func _ring_wanted() -> bool:
	if now_ms < _flash_until_ms:
		return true
	var sd = GameManager.sel_decals
	if sd == null:
		return false
	if sd.is_hovered(self):
		return true
	return (sd._order_slot as Dictionary).has(self)

func _tick_ring() -> void:
	var want: bool = _ring_wanted()
	if not want:
		_hide_ring()
		return
	var ring: MeshInstance3D = _ring_node()
	if ring == null:
		return
	var p: Vector3 = global_position
	ring.global_position = Vector3(p.x, GameManager.get_terrain_height(p.x, p.z) + 0.12, p.z)
	var r: float = _GobCfgP.BOSS_AURA_R
	# Вспышка клича: кольцо ярче и чуть шире, гаснет за BOSS_RING_FLASH_MS
	if now_ms < _flash_until_ms:
		var k: float = float(_flash_until_ms - now_ms) / float(maxi(_GobCfgP.BOSS_RING_FLASH_MS, 1))
		r *= 1.0 + 0.15 * k
		_ring_mat.albedo_color = _GobCfgP.BOSS_RING_COLOR.lerp(_GobCfgP.BOSS_RING_FLASH_COLOR, k)
	else:
		_ring_mat.albedo_color = _GobCfgP.BOSS_RING_COLOR
	ring.scale = Vector3(r, 1.0, r)
	ring.visible = true

func _hide_ring() -> void:
	if _ring != null and is_instance_valid(_ring) and _ring.visible:
		_ring.visible = false

func ring_visible() -> bool:
	return _ring != null and is_instance_valid(_ring) and _ring.visible

func _exit_tree() -> void:
	if _ring != null and is_instance_valid(_ring):
		_ring.queue_free()
	_ring = null
	super._exit_tree()
