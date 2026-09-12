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
## Пауза между приказами идти к раненому (см. MONK_STEP_SEC)
var _step_t: float = 0.0
## Куда монах в последний раз послал себя: приказ переиздаётся, только если
## цель заметно съехала с этой точки
var _step_to: Vector3 = Vector3.INF
## Кого лечили последним тактом и сколько всего вылечено (диагностика стенда)
var heal_target: Node3D = null
var healed_total: float = 0.0
## ── ВОСКРЕШЕНИЕ (письмо 12) ────────────────────────────────────────────────
var _res_target = null          # CorpseRenderer.Corpse
var _res_left: float = 0.0
var _res_cool: float = 0.0
var resurrected_total: int = 0
## Опыт за лечение: накопленные очки до следующего «убийства» в счёт
var _xp_acc: float = 0.0
var heal_xp_kills: int = 0
## Ауры и дистанция — свои редкие такты
var _aura_t: float = 0.0
var _space_t: float = 0.0
var aura_touched: int = 0
var spacing_moves: int = 0

func _ready() -> void:
	_apply_config_stats("monk")
	display_name = "Монах"
	super._ready()
	_setup_monk_visual()

## ── МОНАХ НЕ ДЕРЁТСЯ (спринт 19, письмо 12) ─────────────────────────────
## Урона у него нет (STATS: attack_1 = 0), значит нет авто-агро, ответа на
## удар и тылового напора. Приказ атаки монах НЕ ПРИНИМАЕТ вовсе: ни цели,
## ни марша на неё — он остаётся при раненых (авто-поиск пациентов) и идёт
## только по приказу на движение
func command_attack(_target: Node3D, _forced: bool = true, _charge: bool = false,
		_lock: bool = false) -> void:
	pass

func is_combatant() -> bool:
	return false

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
		_stop_res()
		return
	_ride_heal_vfx()
	_step_t = maxf(_step_t - delta, 0.0)
	_res_cool = maxf(_res_cool - delta, 0.0)
	_tick_aura(delta)
	_tick_spacing(delta)
	# Канал воскрешения идёт своим ходом; без «Двойного попечения» лечение
	# на это время замирает
	if _res_target != null:
		_tick_res(delta)
		if not parallel_care():
			return
	_heal_t -= delta
	if _heal_t > 0.0:
		return
	_heal_t = heal_tick_sec()
	_heal_pulse()

# ═════════════════════════════════════════════════════════════════════════════
# ДИСТАНЦИЯ МЕЖДУ МОНАХАМИ (письмо 12): свободный монах отходит от соседа
# ═════════════════════════════════════════════════════════════════════════════
func _tick_spacing(delta: float) -> void:
	_space_t -= delta
	if _space_t > 0.0:
		return
	_space_t = 1.0
	if state != State.IDLE or player_order_active() or _panicked or retreating:
		return
	var mp: Vector3 = global_position
	var nearest: Monk = null
	var nd: float = _MCfg.MONK_SPACING
	for n in GameManager.unit_grid.query_radius(mp, _MCfg.MONK_SPACING):
		if n == null or not is_instance_valid(n) or n == self:
			continue
		var m := n as Monk
		if m == null or m.is_dead() or m.faction != faction:
			continue
		var d: float = mp.distance_to(m.global_position)
		if d < nd:
			nd = d
			nearest = m
	if nearest == null:
		return
	var away: Vector3 = mp - nearest.global_position
	away.y = 0.0
	if away.length_squared() < 1e-4:
		away = Vector3(1.0, 0.0, 0.0).rotated(Vector3.UP, float(get_instance_id() % 7))
	var goal: Vector3 = mp + away.normalized() * (_MCfg.MONK_SPACING - nd + 0.5)
	spacing_moves += 1
	command_move(GameManager.land_target(goal))

# ═════════════════════════════════════════════════════════════════════════════
# АУРЫ ПОДДЕРЖКИ (письмо 12): награды ветеранства монаха
# ═════════════════════════════════════════════════════════════════════════════
func aura_radius() -> float:
	return _MCfg.MONK_AURA_BASE_R + GameManager.squad_bonus(squad_id, "aura_radius")

func _tick_aura(delta: float) -> void:
	_aura_t -= delta
	if _aura_t > 0.0:
		return
	_aura_t = _MCfg.MONK_AURA_TICK
	if squad_id <= 0:
		return
	var a: float = GameManager.squad_bonus(squad_id, "aura_armor")
	var k: float = GameManager.squad_bonus(squad_id, "aura_attack")
	var r: float = GameManager.squad_bonus(squad_id, "aura_rate")
	if a <= 0.0 and k <= 0.0 and r <= 0.0:
		return
	var until: int = now_ms + _MCfg.MONK_AURA_HOLD_MS
	var touched := 0
	for n in GameManager.unit_grid.query_radius(global_position, aura_radius()):
		if n == null or not is_instance_valid(n):
			continue
		var u := n as Unit
		if u == null or u.is_dead() or u.faction != faction or u == self:
			continue
		u.aura_apply(a, k, r, until)
		touched += 1
	aura_touched = touched

## Опыт за лечение (письмо 12): каждые MONK_XP_HP_PER_KILL очков — зачёт
func _credit_heal_xp(amount: float) -> void:
	if amount <= 0.0 or squad_id <= 0:
		return
	_xp_acc += amount
	var n: int = int(_xp_acc / _MCfg.MONK_XP_HP_PER_KILL)
	if n > 0:
		_xp_acc -= float(n) * _MCfg.MONK_XP_HP_PER_KILL
		heal_xp_kills += n
		GameManager.credit_kills(squad_id, n)

# ═════════════════════════════════════════════════════════════════════════════
# ВОСКРЕШЕНИЕ (письмо 12, forge monk_3d)
# ═════════════════════════════════════════════════════════════════════════════
func can_resurrect() -> bool:
	return GameManager.is_researched(faction, "monk_3d")

## «Двойное попечение» (monk_4d): лечит во время канала, канал короче
func parallel_care() -> bool:
	return GameManager.is_researched(faction, "monk_4d")

func res_sec() -> float:
	var t: float = _MCfg.MONK_RES_SEC
	if parallel_care():
		t *= _MCfg.MONK_RES_PARALLEL_MULT
	return t

func res_target():
	return _res_target

func res_left() -> float:
	return _res_left

## Раненых нет, срок остывания вышел — искать тело в радиусе лечения
func _try_resurrect() -> bool:
	if not can_resurrect() or _res_cool > 0.0 or GameManager.corpses == null:
		return false
	var c = GameManager.corpses.find_raisable(faction, global_position, heal_radius())
	if c == null:
		return false
	_res_target = c
	_res_left = res_sec()
	return true

func _stop_res() -> void:
	_res_target = null
	_res_left = 0.0
	if _heal_aura != null and is_instance_valid(_heal_aura) and _heal_vfx_target == null:
		_heal_aura.visible = false

func _tick_res(delta: float) -> void:
	var c = _res_target
	if c == null or int(c.get("index")) < 0 or not bool(c.get("raisable")):
		_stop_res()
		return
	var cp: Vector3 = c.get("pos")
	var gap: float = Vector2(cp.x - global_position.x, cp.z - global_position.z).length()
	if gap > _MCfg.MONK_CAST_RANGE:
		# Подойти к телу тем же приказом, что к пациенту
		if not player_order_active() and _step_t <= 0.0 and not _panicked:
			var to_me: Vector3 = global_position - cp
			to_me.y = 0.0
			if to_me.length() < 0.01:
				to_me = Vector3(1.0, 0.0, 0.0)
			var stand: Vector3 = cp + to_me.normalized() * (_MCfg.MONK_CAST_RANGE * 0.7)
			_step_t = _MCfg.MONK_STEP_SEC
			_step_to = stand
			command_move(GameManager.land_target(stand))
		return
	# Канал: лента лечения, аура над телом
	_res_left -= delta
	if _heal_vfx == null or not is_instance_valid(_heal_vfx):
		_heal_vfx = _build_heal_vfx()
	if _heal_aura != null and is_instance_valid(_heal_aura) and _heal_vfx_target == null:
		_heal_aura.visible = true
		_heal_aura.global_position = Vector3(cp.x, cp.y + AURA_DIAM_M * AURA_OVAL_K * 0.5, cp.z)
	if now_ms >= _anim_lock_until_ms:
		_play_attack_anim("heal", 600)
	if _res_left > 0.0:
		return
	var u: Unit = GameManager.raise_fallen(c, self)
	_stop_res()
	_res_cool = _MCfg.MONK_RES_COOLDOWN
	if u != null:
		resurrected_total += 1
		heal_target = u
		if squad_id > 0:
			heal_xp_kills += _MCfg.MONK_RES_XP_KILLS
			GameManager.credit_kills(squad_id, _MCfg.MONK_RES_XP_KILLS)

## Вспышка «пуф»: квад ауры вырастает и гаснет за RES_FLASH_SEC над точкой
## воскрешения. Свой узел на вспышку, гаснет твином и освобождается сам
const RES_FLASH_SEC := 0.7
const RES_FLASH_SIZE := 2.4
var res_flashes: int = 0

func _res_flash(at: Vector3) -> void:
	var root: Node = GameManager.main.world_root() if GameManager.main != null else get_parent()
	if root == null:
		return
	var q := QuadMesh.new()
	q.size = Vector2(0.4, 0.4)
	var mat: ShaderMaterial = _BBUtilM.make_material(_aura_texture(), Color.WHITE, 0.5, AURA_FPS)
	mat.set_shader_parameter("frame_count", float(AURA_FRAMES))
	mat.set_shader_parameter("ground_depth", 1.0)
	mat.set_shader_parameter("depth_push", -HEAL_VFX_DEPTH_PULL)
	mat.set_shader_parameter("v_stretch", 1.0)
	mat.render_priority = 6
	q.material = mat
	var mi := MeshInstance3D.new()
	mi.name = "ResFlash"
	mi.mesh = q
	root.add_child(mi)
	mi.global_position = Vector3(at.x, at.y + 0.7, at.z)
	res_flashes += 1
	var tw := mi.create_tween()
	tw.tween_property(q, "size", Vector2(RES_FLASH_SIZE, RES_FLASH_SIZE), RES_FLASH_SEC * 0.45)
	tw.tween_property(mi, "scale", Vector3(0.01, 0.01, 0.01), RES_FLASH_SEC * 0.55)
	tw.tween_callback(mi.queue_free)

## Годится ли этот боец в пациенты: свой, живой, на карте и с неполным запасом
func _may_heal(u: Unit) -> bool:
	if u == null or not is_instance_valid(u):
		return false
	if u.is_dead() or u.garrisoned or u.faction != faction:
		return false
	if u.max_health <= 0.0:
		return false
	return u.current_health < u.max_health - 0.01

## ── ЦЕЛЬ ДЕРЖИТСЯ ДО ПОЛНОГО ИЗЛЕЧЕНИЯ, А НЕ ВЫБИРАЕТСЯ ЗАНОВО КАЖДЫЙ ТАКТ ──
## Заказ владельца: «лечит юнитов ПООЧЕРЁДНО ПО ОДНОМУ… после полного излечения
## первого монах переключается на следующего». Прежняя версия выбирала самого
## раненого КАЖДЫЙ такт — при двух примерно одинаково побитых бойцах она лечила
## их по очереди через такт, то есть обоих сразу, и переключение «по одному»
## на экране не читалось вовсе. Бросается цель только по причине: вылечена,
## погибла, ушла с карты или оторвалась дальше поводка
func _keep_or_pick() -> Unit:
	# ПРАВИЛО 5: пациент гибнет и освобождается между тактами (поймал
	# qa_performance_stress — 13 «Trying to cast a freed object» за бой);
	# приведение типа только после проверки СЫРОЙ ссылки
	var cur: Unit = null
	if heal_target != null and is_instance_valid(heal_target):
		cur = heal_target as Unit
	if _may_heal(cur) \
			and global_position.distance_to(cur.global_position) <= _MCfg.MONK_HEAL_LEASH:
		return cur
	var best: Unit = null
	var best_frac: float = 1.0
	# САМ МОНАХ — ТОЖЕ ПАЦИЕНТ (заказ спринта 15: «…а также сам монах»).
	# Отдельной ветки на это не нужно: он лежит в той же сетке и судится тем же
	# правилом, надо лишь не выбрасывать себя из выборки
	for n in GameManager.unit_grid.query_radius(global_position, heal_radius()):
		if n == null or not is_instance_valid(n):
			continue
		var u := n as Unit
		if not _may_heal(u):
			continue
		# ПРИОРИТЕТ — НАИМЕНЬШАЯ ДОЛЯ ЗАПАСА, а не наименьший остаток: иначе
		# рыцарь с половиной своих трёхсот всегда перевешивал бы лучника,
		# которому до смерти один удар
		var frac: float = u.current_health / u.max_health
		if frac < best_frac:
			best_frac = frac
			best = u
	return best

## Один такт: монах подходит к своему раненому и льёт в него запас
## ── БОНУСЫ КУЗНИЦЫ (спринт 16) ──────────────────────────────────────────────
## Темп (короче такт), объём (больше за такт) и радиус — те же ключи, что в
## forge_config, читаются через unit_bonus, как bonus_range у лучника
func heal_tick_sec() -> float:
	var k: float = 1.0 + GameManager.unit_bonus(faction, "monk", "bonus_heal_rate")
	return _MCfg.MONK_HEAL_TICK / maxf(k, 0.1)

func heal_amount_mult() -> float:
	return 1.0 + GameManager.unit_bonus(faction, "monk", "bonus_heal_amount")

func heal_radius() -> float:
	return _MCfg.MONK_HEAL_RADIUS + GameManager.unit_bonus(faction, "monk", "bonus_heal_radius")

## AOE-перк «Благодать» изучен и включён (переключатель, как залп у лучников)
## Со спринта 19 «Благодать» — узел 2d (tier 2, письмо 12)
func aoe_active() -> bool:
	return squad_id > 0 and GameManager.squad_has_ability(squad_id, "monk_2d") \
		and GameManager.squad_ability_on(squad_id, "monk_2d")

## Один такт AOE: все раненые свои в радиусе, каждый — на MONK_AOE_RATE долю
## одиночного. Цель поиска/подхода остаётся самым раненым (VFX на нём)
func _heal_pulse_aoe(best: Unit) -> void:
	var tick: float = heal_tick_sec()
	var per: float = tick / _MCfg.MONK_HEAL_SEC_PER_MAN * heal_amount_mult() * _MCfg.MONK_AOE_RATE
	var touched := 0
	for n in GameManager.unit_grid.query_radius(global_position, heal_radius()):
		if n == null or not is_instance_valid(n):
			continue
		var u := n as Unit
		if not _may_heal(u):
			continue
		var before: float = u.current_health
		u.current_health = minf(u.max_health, u.current_health + u.max_health * per)
		healed_total += u.current_health - before
		_credit_heal_xp(u.current_health - before)
		u._soa_push_stats()
		touched += 1
	aoe_touched = touched
	_play_attack_anim("heal", int(tick * 1000.0) + 120)
	_bind_heal_vfx(best)

## Стенды: скольких накрыл последний AOE-такт
var aoe_touched: int = 0

func _heal_pulse() -> void:
	var best: Unit = _keep_or_pick()
	heal_target = best
	if best == null:
		# ЛЕЧИТЬ НЕКОГО — СНИМАЕМ ЭФФЕКТ СРАЗУ, а не по догорающему таймеру:
		# «как только монах прекращает лечение, VFX мгновенно отключается».
		# Живые целы — можно поднимать павших (письмо 12: строго после
		# выравнивания запаса живых)
		_stop_heal_vfx()
		if _res_target == null:
			_try_resurrect()
		return
	# ── СНАЧАЛА ПОДОЙТИ ───────────────────────────────────────────────────
	# Дальше дистанции каста монах не лечит вовсе: заклинание — действие в
	# упор, и «лечит через полполя» было бы ровно тем, на что жалуется заказ
	var gap: float = global_position.distance_to(best.global_position)
	if best != self and gap > _MCfg.MONK_CAST_RANGE:
		_walk_to_patient(best)
		_stop_heal_vfx()
		return
	if aoe_active():
		_heal_pulse_aoe(best)
		return
	var amount: float = best.max_health * heal_tick_sec() / _MCfg.MONK_HEAL_SEC_PER_MAN \
		* heal_amount_mult()
	var before: float = best.current_health
	best.current_health = minf(best.max_health, best.current_health + amount)
	healed_total += best.current_health - before
	_credit_heal_xp(best.current_health - before)
	# Строка ядра и полоска здоровья узнают о лечении тем же путём, что у
	# перка «кровь за кровь» (GameManager.credit_kill)
	best._soa_push_stats()
	_play_attack_anim("heal", int(heal_tick_sec() * 1000.0) + 120)
	_bind_heal_vfx(best)

## ── ПОДХОД — ЭТО ПРИКАЗ, А НЕ ВТОРАЯ МЕХАНИКА ХОДЬБЫ ──────────────────────
## Монах идёт к пациенту обычным command_move, тем же, каким его двигает игрок.
## Своего шага у него нет и быть не должно: любое движение мимо пакетного шага
## означало бы движение мимо проверки чужих тел, воды и границ карты.
##
## ПРИКАЗ ИГРОКА ВАЖНЕЕ. Пока он жив (player_order_active), монах идёт туда,
## куда послали, и лечит только тех, до кого дотянется по дороге
func _walk_to_patient(p: Unit) -> void:
	if player_order_active() or _panicked or retreating:
		return
	if _step_t > 0.0:
		return
	# Встаём НЕ В САМОГО пациента, а рядом: точка в его теле недостижима, и
	# монах топтался бы у него вплотную, никогда не отчитавшись о приходе
	var to_me: Vector3 = global_position - p.global_position
	to_me.y = 0.0
	if to_me.length() < 0.01:
		to_me = Vector3(1.0, 0.0, 0.0)
	var stand: Vector3 = p.global_position \
		+ to_me.normalized() * (_MCfg.MONK_CAST_RANGE * 0.7)
	# Цель не сдвинулась с прошлого приказа — переиздавать нечего: каждый
	# command_move будит бойца и метит позу грязной (см. CLAUDE.md, «цена
	# костыля была не там, где её мерили»)
	if _step_to != Vector3.INF and _step_to.distance_to(stand) < 1.0 \
			and state == State.MOVING:
		return
	_step_t = _MCfg.MONK_STEP_SEC
	_step_to = stand
	command_move(GameManager.land_target(stand))

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
## ── РАЗМЕР ЭФФЕКТА БЕРЁТСЯ У САМОГО СПРАЙТА ЦЕЛИ ─────────────────────────
## Заказ владельца (спринт 15): эффект «не на земле под ногами, а обволакивает
## сам спрайт юнита», и «корректно накладывается на любые категории» — пехоту,
## копейщиков, конницу, лучников, монахов. Одна константа в метрах этого не
## даёт по построению: нарисованная высота у рабочего 2.1 м, у копейщика 4.9,
## у тролля под двенадцать. Поэтому квад равен нарисованной высоте цели,
## умноженной на HEAL_VFX_COVER, а константа ниже осталась ЗАПАСНЫМ ответом
## для цели, у которой ленту ещё не сняли с узла
## ── СПРИНТ 18 (второе письмо): РАЗМЕР ЭФФЕКТА СТРОГО ФИКСИРОВАН ──────────
## Прежнее «квад равен нарисованной высоте цели» (спринт 15) на копейщике
## давало кольцо 3.4 м и крест на полотряда — «гигантский жирный круг» из
## жалобы; на лучнике то же правило давало аккуратный метр. Теперь размер
## один на всех и на 20 % меньше прежнего минимума: HEAL_VFX_COVER и
## HEAL_VFX_MAX_M — история, _vfx_geom отдаёт константу
const HEAL_VFX_SIZE_M := 1.3
## ИСТОРИЯ (не читаются): доля высоты цели и потолок прежнего правила
const HEAL_VFX_COVER := 1.05
const HEAL_VFX_MAX_M := 6.0
const HEAL_VFX_FPS := 12.0
## Насколько эффект переживает последний такт лечения. Ноль был бы миганием:
## лечение идёт ТАКТАМИ, и между двумя тактами монах формально «не лечит».
## Окно чуть шире такта — это и есть «непрерывно, пока идёт процесс»
const HEAL_VFX_GRACE := 0.25

var _heal_vfx: MeshInstance3D = null
## ── АУРА: КОЛЬЦО И КРЕСТ, НАРИСОВАННЫЕ КОДОМ (заказ спринта 16) ─────────────
## Лист Heal_Effect — редкие искры (непрозрачных пикселей 4 %, средняя альфа
## 10 из 255): в бою его не видно. Владелец просит «чёткую, заметную анимацию —
## зелёное свечение / крест / ауру». Готовой картинки в паке нет, поэтому она
## строится кодом, как знамя (BannerArt): четыре кадра пульсирующего кольца с
## крестом, пиксель-арт без полутонов (срез 0.5, как у всех билбордов).
## Кэш статический — картинка одна на всех монахов
static var _aura_tex: Texture2D = null
const AURA_PX := 64
const AURA_FRAMES := 4
const AURA_FPS := 6.0
## Сочный ярко-зелёный (спринт 18): кольцо и крест ТОНКИЕ (2 px из 64), крест
## короче; диаметр ауры фиксированный AURA_DIAM_M — по фигуре больше не
## считается (см. HEAL_VFX_SIZE_M)
## Ярче и крупнее (письмо 12): кольцо 3 px, мягкое свечение внутри
const AURA_COLOR := Color(0.30, 1.0, 0.40)
const AURA_GLOW := Color(0.35, 1.0, 0.45)
## ── СПРИНТ 20 (модуль 1): АУРА — ТОЛЬКО ОВАЛ ПОД НОГАМИ ────────────────────
## Заливка, крест и свечение сняты заказом владельца: остаётся маленький
## зелёный овал выделения строго под фигуркой (AURA_DIAM_M по ширине, высота
## AURA_OVAL_K от неё — овал читается лежащим на земле под камерой 45°) и
## сама лента лечения. Овал ставится в ТОЧКУ НА ЗЕМЛЕ, а не в центр спрайта
const AURA_DIAM_M := 1.0
const AURA_OVAL_K := 0.45
const AURA_RING_PX := 2.0
## ИСТОРИЯ: диаметр по высоте центра спрайта и пол прежнего правила
const AURA_DIAM_PER_MID := 2.4
const AURA_DIAM_MIN := 1.0
## На сколько метров VFX подтянут к камере по глубине (больше depth_lift бойца)
const HEAL_VFX_DEPTH_PULL := 0.6
const AURA_CROSS := Color(0.55, 1.0, 0.62)
var _heal_aura: MeshInstance3D = null

static func _aura_texture() -> Texture2D:
	if _aura_tex != null:
		return _aura_tex
	var img := Image.create(AURA_PX * AURA_FRAMES, AURA_PX, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c: float = float(AURA_PX) * 0.5
	for f in range(AURA_FRAMES):
		var ox: int = f * AURA_PX
		# пульс: радиус кольца ходит 22 → 26 → 22
		var pulse: float = 0.5 - 0.5 * cos(TAU * float(f) / float(AURA_FRAMES))
		var r: float = 26.0 + 3.0 * pulse
		for y in range(AURA_PX):
			for x in range(AURA_PX):
				var dx: float = float(x) + 0.5 - c
				# ОВАЛ: вертикаль растянута в 1/AURA_OVAL_K раза, чтобы кольцо
				# на билборде читалось лежащим на земле (спринт 20). Ни креста,
				# ни заливки — только контур
				var dy: float = (float(y) + 0.5 - c) / AURA_OVAL_K
				var d: float = sqrt(dx * dx + dy * dy)
				if absf(d - r) <= AURA_RING_PX:
					img.set_pixel(ox + x, y, AURA_COLOR)
	# Сэмплер билборда — filter_nearest_mipmap: текстуре без мип-уровней в GL
	# Compatibility он отдаёт пустоту, и аура не рисовалась вовсе
	# (qa_monk_vfx/Shot: «изменилось 0.0 %»)
	img.generate_mipmaps()
	_aura_tex = ImageTexture.create_from_image(img)
	return _aura_tex
## На ком сейчас висит эффект. null — ни на ком
var _heal_vfx_target: Unit = null
var _heal_vfx_left: float = 0.0
## Высота центра спрайта текущей цели над её точкой на земле (см. _vfx_geom)
var _vfx_mid: float = 0.0

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
	# ── ГЕОМЕТРИЯ СНИМАЕТСЯ НА СМЕНЕ ЦЕЛИ, А НЕ В КАДРЕ ───────────────────
	# Эффект переезжает с бойца на бойца, а размеры у родов войск разные; при
	# этом квад один на монаха, и менять его размер надо ровно тогда, когда
	# сменился хозяин
	if target != _heal_vfx_target:
		var g: Vector2 = _vfx_geom(target)
		_vfx_mid = g.x
		var q := _heal_vfx.mesh as QuadMesh
		if q != null and absf(q.size.y - g.y) > 0.01:
			q.size = Vector2(g.y, g.y)
		# Аура — по ФИГУРЕ, а не по листу: лист копейщика 320 px при видимой
		# фигуре вдвое ниже, и кольцо «по листу» лежало далеко за силуэтом.
		# Центр спрайта стоит на mid над ногами, значит фигура ≈ 2·mid
		# высотой; кольцо чуть шире её (AURA_DIAM_PER_MID), не уже пола
		if _heal_aura != null and is_instance_valid(_heal_aura):
			var qa := _heal_aura.mesh as QuadMesh
			if qa != null and absf(qa.size.x - AURA_DIAM_M) > 0.01:
				qa.size = Vector2(AURA_DIAM_M, AURA_DIAM_M * AURA_OVAL_K)   # овал
	_heal_vfx_target = target
	_heal_vfx_left = _MCfg.MONK_HEAL_TICK + HEAL_VFX_GRACE
	_heal_vfx.visible = true
	if _heal_aura != null and is_instance_valid(_heal_aura):
		_heal_aura.visible = true
	_place_heal_vfx()

## Снять эффект с юнита. Мгновенно и без следа: привязки нет, квад невидим
func _stop_heal_vfx() -> void:
	_heal_vfx_target = null
	_heal_vfx_left = 0.0
	if _heal_vfx != null and is_instance_valid(_heal_vfx):
		_heal_vfx.visible = false
	if _heal_aura != null and is_instance_valid(_heal_aura):
		_heal_aura.visible = false

## ── ЦЕНТР СПРАЙТА, А НЕ ГРУДЬ И НЕ НОГИ ──────────────────────────────────
## Высота центра нарисованной фигуры над её точкой на земле — это привязка ног
## ленты, растянутая компенсацией наклона камеры (ровно так же её считает
## qa_visual_smoke._probe_unit, и второго описания «где середина спрайта» в
## проекте быть не должно). Прежде сюда подставлялась aim_height() — точка
## ПРИЦЕЛИВАНИЯ, то есть грудь: у копейщика это 0.8 м при середине рисунка на
## 1.4 м, и заклинание висело у колен.
##
## Снимается один раз на привязку, а не каждый кадр: лента у цели постоянна,
## а sheet_frame() при первом вызове ещё и разбирает лист
func _vfx_geom(t: Unit) -> Vector2:
	var sf: Array = t.sheet_frame()
	if sf.size() < 5:
		return Vector2(t.aim_height(), HEAL_VFX_SIZE_M)
	# ── СПРИНТ 20: ЛЕНТА ЛЕЧЕНИЯ ИДЁТ ОТ ЗЕМЛИ, А НЕ ОТ ПОЯСА ────────────
	# Заказ: «сдвинуть точку проигрывания анимации ниже — строго от ног
	# спрайта». Центр квада ставится на половину его высоты над точкой на
	# земле: нижняя кромка ленты лежит у ступней при любом росте цели.
	# Привязка ленты цели (sf[4]) больше не нужна, но sheet_frame() всё равно
	# читается — так остаётся ленивый разбор листа у только что рождённого
	return Vector2(HEAL_VFX_SIZE_M * 0.5, HEAL_VFX_SIZE_M)

## Поставить квад в ЦЕНТР СПРАЙТА цели по НАРИСОВАННОЙ точке
func _place_heal_vfx() -> void:
	if _heal_vfx == null or not is_instance_valid(_heal_vfx):
		return
	if _heal_vfx_target == null or not is_instance_valid(_heal_vfx_target):
		return
	var p: Vector3 = _heal_vfx_target.draw_position()
	_heal_vfx.global_position = Vector3(p.x, p.y + _vfx_mid, p.z)
	# Овал — ПОД НОГАМИ: центр квада чуть выше точки на земле (половина
	# высоты овала), глубина — от той же точки, без подтяжки к камере
	if _heal_aura != null and is_instance_valid(_heal_aura):
		_heal_aura.global_position = Vector3(p.x, p.y + AURA_DIAM_M * AURA_OVAL_K * 0.5, p.z)

## Такт эффекта: едет за целью и гаснет, как только лечить эту цель перестали.
## Зовётся из tick_physics монаха — своего тика узел не заводит (то же правило,
## что у торчащих стрел и тел павших: декорация не платит нотификацией движка)
func _ride_heal_vfx() -> void:
	# ОСВОБОЖДЁННЫЙ ОБЪЕКТ В VARIANT РАВЕН NULL (спринт 19): павшая и уже
	# освобождённая цель проходила эту проверку как «никого не лечу», и
	# эффект оставался висеть над трупом до следующего лечения (поймал
	# qa_performance_stress B7). Пустая привязка при видимом кваде — гасим
	if _heal_vfx_target == null:
		if _heal_vfx != null and is_instance_valid(_heal_vfx) and _heal_vfx.visible:
			_stop_heal_vfx()
		return
	# ── ПРИЧИНЫ ПРЕКРАЩЕНИЯ, ВСЕ ЧЕТЫРЕ ИЗ ЗАКАЗА ──────────────────────────
	# Цель исчезла или погибла; цель ушла в гарнизон; цель ВЫЛЕЧЕНА до конца;
	# монах отошёл дальше радиуса лечения. Пятая («переключился на другую»)
	# обрабатывается сама — _bind_heal_vfx переносит квад
	# Та же оговорка: цель могла быть освобождена — сырая ссылка первой
	if not is_instance_valid(_heal_vfx_target):
		_stop_heal_vfx()
		return
	var t: Unit = _heal_vfx_target
	if t.is_dead() or t.garrisoned:
		_stop_heal_vfx()
		return
	if t.max_health > 0.0 and t.current_health >= t.max_health - 0.01:
		_stop_heal_vfx()
		return
	if global_position.distance_to(t.global_position) > heal_radius():
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
	# ── ПОВЕРХ БОЙЦА (спринт 16) ──────────────────────────────────────────
	# Глубина — от точки на земле (низ квада, у ног цели), ПОДТЯНУТАЯ к камере
	# на HEAL_VFX_DEPTH_PULL: спрайт бойца сам приподнят к камере на
	# depth_lift 0.35 (mm_unit_sprite), и с меньшим сдвигом крест в центре
	# ауры прятался бы за телом. Прежний ground_depth = 0 не рисовал квад
	# ВООБЩЕ (см. cyl_billboard, ветка else)
	mat.set_shader_parameter("ground_depth", 1.0)
	mat.set_shader_parameter("depth_push", -HEAL_VFX_DEPTH_PULL)
	# ── БЕЗ КОМПЕНСАЦИИ НАКЛОНА (спринт 16) ───────────────────────────────
	# v_stretch тянет квад ОТ НИЖНЕЙ КРОМКИ вверх — это правило наземных
	# декораций, у которых низ стоит на грунте. Заклинание ставится ЦЕНТРОМ в
	# центр спрайта, и с растяжением его середина уезжала на 0.2 высоты квада
	# вверх — над голову. Единица: квад рисуется ровно вокруг своего узла
	mat.set_shader_parameter("v_stretch", 1.0)
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
	# Аура — второй квад тем же путём, чуть ниже искр по приоритету
	var aq := QuadMesh.new()
	aq.size = Vector2(AURA_DIAM_M, AURA_DIAM_M * AURA_OVAL_K)
	var amat: ShaderMaterial = _BBUtilM.make_material(_aura_texture(), Color.WHITE, 0.5, AURA_FPS)
	amat.set_shader_parameter("frame_count", float(AURA_FRAMES))
	# Овал под ногами сортируется ТОЧКОЙ НА ЗЕМЛЕ без подтяжки: спрайт бойца
	# приподнят к камере (depth_lift) и честно перекрывает дальнюю дугу —
	# так кольцо читается ПОД фигуркой, а не поверх неё
	amat.set_shader_parameter("ground_depth", 1.0)
	amat.set_shader_parameter("depth_push", 0.0)
	amat.set_shader_parameter("v_stretch", 1.0)
	amat.render_priority = 5
	aq.material = amat
	var ami := MeshInstance3D.new()
	ami.name = "HealAura"
	ami.mesh = aq
	ami.visible = false
	root.add_child(ami)
	_heal_aura = ami
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
	if _heal_aura != null and is_instance_valid(_heal_aura):
		_heal_aura.queue_free()
	_heal_aura = null
	super._exit_tree()
