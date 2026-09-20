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
## ── ОТСТУПЛЕНИЕ, ЩИТ И СПАСЕНИЯ (заказ 13.09.2026) ────────────────────────
## Монах не дерётся вовсе, и единственный его ответ на удар — отойти. Откат
## нужен, чтобы под градом стрел он не дёргался каждый кадр
var _retreat_cd: float = 0.0
## Куда отходим сейчас. Пока точка задана, монах К ПАЦИЕНТУ НЕ ИДЁТ: иначе
## отход гасится подходом через секунду, и на экране вместо пяти метров
## выходит полметра дрожи (замер qa_monk_forge E3). Разделяет их ФАКТ
## ПРИХОДА, а не срок — тот же приём, что у выхода из боя у пехоты
var _retreat_goal: Vector3 = Vector3.INF
var _retreat_give_up: float = 0.0
var _invuln_until: int = 0
## Щит «Святой Щит» (4c): поглощение, тает под уроном, копится вне боя
var shield_hp: float = 0.0
var _shield_calm: float = 0.0
## Стенды: сколько раз отходил, спасался и потратил ли самовоскрешение
var retreats: int = 0
var death_saves: int = 0
var self_res_used: bool = false

var _aura_t: float = 0.0
var _space_t: float = 0.0
## Гистерезис расстановки монахов, м, и пауза после выданного отхода, с
## (BigStand, этап 1: проверка раз в секунду, приказ — не чаще раза в 4 с)
const SPACING_HYST := 1.0
const SPACING_MOVE_SEC := 4.0
var aura_touched: int = 0
var spacing_moves: int = 0
var approach_moves: int = 0
## Круг КАНАЛА воскрешения — свой узел (ТЗ 17.09.2026): канал идёт
## параллельно лечению, а круг лечения занят пациентом. Гаснет в _stop_res
## БЕЗУСЛОВНО — «зависший зелёный круг без модели» был кругом лечения,
## который канал одалживал и не всегда возвращал
var _res_aura: MeshInstance3D = null

## Дистанция каста = радиус ауры: монах работает с её границы, а не в упор
func cast_range() -> float:
	return heal_radius()

## Где вставать относительно центра отряда-пациента: на доле радиуса ауры,
## снаружи строя, и стоять там без микро-движений
func stand_dist() -> float:
	return heal_radius() * _MCfg.MONK_STAND_FRAC

func res_aura_visible() -> bool:
	return _res_aura != null and is_instance_valid(_res_aura) and _res_aura.visible

func _ready() -> void:
	# ФАЗА ТАКТА СВОЯ У КАЖДОГО МОНАХА (qa_melee_bench, 14.09.2026): три монаха
	# одного заказа пульсировали в один кадр — три поиска раненых и тел разом
	_heal_t = float(get_instance_id() % 97) / 97.0 * _MCfg.MONK_HEAL_TICK
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

## ── ПРИКАЗ ИГРОКА: ЛЕЧИТЬ ЭТОГО / ЭТОТ ОТРЯД (ТЗ 14.09.2026, п. 9) ─────────
## ПКМ монахом по своему бойцу (SelectionManager._try_monk_heal_order):
## автопоиск раненых снят, монах идёт к указанному отряду и лечит его самого
## раненого, затем поднимает павших этого отряда — пока в нём не останется
## ни раненых, ни тел в радиусе поиска. Приказ снимает любой command_move
## игрока (_order_target = null в command_move) или гибель цели
var _order_target: Node3D = null
var _order_sid: int = 0
var heal_orders: int = 0

func command_heal(target: Node3D) -> void:
	if target == null or not is_instance_valid(target) or not (target is Unit):
		return
	var tu := target as Unit
	if tu.faction != faction or tu.is_dead():
		return
	_order_target = tu
	_order_sid = tu.squad_id
	heal_target = null
	_stop_res()
	_stop_heal_vfx()
	_move_lock = 0.0
	_step_t = 0.0
	_step_to = Vector3.INF
	heal_orders += 1
	# Сразу к отряду — не ждать такта лечения
	_heal_t = 0.0
	patient_sid = _order_sid
	_monk_wake()

## Приказ ещё в силе: указанный боец жив, либо жив хоть кто-то из его отряда
## (15.09.2026: монах СОПРОВОЖДАЕТ отряд, а не одного бойца — гибель
## указанного переводит приказ на живого соседа по отряду)
func _order_alive() -> bool:
	if _order_target == null:
		return false
	if is_instance_valid(_order_target) and not (_order_target as Unit).is_dead():
		return true
	_order_target = null
	if _order_sid > 0:
		var raw: Variant = GameManager.squads.get(_order_sid)
		if raw != null:
			for m in (raw as Dictionary).get("members", []):
				if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
					_order_target = m
					return true
	_order_sid = 0
	return false

## Центр отряда приказа (медиана по живым), INF — отряда нет
func _order_centre() -> Vector3:
	if not _order_alive():
		return Vector3.INF
	if _order_sid > 0 and GameManager.squads.has(_order_sid):
		var c: Vector2 = GameManager.squad_centre_xz(_order_sid)
		if c != Vector2.INF:
			return Vector3(c.x, 0.0, c.y)
	return (_order_target as Unit).global_position

## ── СОПРОВОЖДЕНИЕ (ТЗ 15.09.2026, п. 4.2) ─────────────────────────────────
## Лечить некого — монах держится у отряда приказа: отряд ушёл дальше
## MONK_FOLLOW_DIST от монаха — идёт к его центру (не в самый центр, а на
## край каста, чтобы не топтаться в строю). Приказ не «исполняется» и не
## снимается сам: снимает его только приказ игрока на движение или гибель
## всего отряда. Раньше приказ гас, как только все были целы, и «ПКМ монахом
## по здоровому отряду» выглядел проигнорированным
const MONK_FOLLOW_DIST := 6.0
var follow_moves: int = 0

func _follow_order_squad() -> void:
	if player_order_active() or _panicked or retreating or _retreat_goal.x != INF:
		return
	var c: Vector3 = _order_centre()
	if c == Vector3.INF:
		return
	var to_me: Vector3 = global_position - c
	to_me.y = 0.0
	var d: float = to_me.length()
	if d <= MONK_FOLLOW_DIST:
		return
	if _step_t > 0.0:
		return
	if d < 0.01:
		to_me = Vector3(1.0, 0.0, 0.0)
	var stand: Vector3 = c + to_me.normalized() * stand_dist()
	if _step_to != Vector3.INF and _step_to.distance_to(stand) < _MCfg.MONK_MOVE_SLACK \
			and state == State.MOVING:
		return
	_step_t = _MCfg.MONK_STEP_SEC
	_step_to = stand
	follow_moves += 1
	if _Opt.cmd_meter: _Opt.cmd_src = "monk_follow"
	command_move(GameManager.land_target(stand))
	if _Opt.cmd_meter: _Opt.cmd_src = ""

## Самый раненый в отряде приказа (или сам указанный, если он один)
func _order_patient() -> Unit:
	if not _order_alive():
		return null
	var ot := _order_target as Unit
	if _order_sid <= 0 or not GameManager.squads.has(_order_sid):
		return ot if _may_heal(ot) else null
	# ФОКУС (ТЗ 15.09.2026): начатого пациента ведём до 100 %, а не выбираем
	# самого раненого заново каждый такт — при двух одинаково побитых это
	# читалось как «размазывает по всем»
	if heal_target != null and is_instance_valid(heal_target):
		var cur := heal_target as Unit
		if _may_heal(cur) and cur.squad_id == _order_sid:
			return cur
	var best: Unit = null
	var best_frac: float = 1.0
	for m in GameManager.squad_members(_order_sid):
		var u := m as Unit
		if not _may_heal(u):
			continue
		var frac: float = u.current_health / u.max_health
		if frac < best_frac:
			best_frac = frac
			best = u
	return best

## Есть ли у отряда приказа тела, которые можно поднять (в радиусе поиска)
func _order_corpse():
	if _order_sid <= 0 or GameManager.corpses == null or not can_resurrect():
		return null
	return GameManager.corpses.find_raisable_of_squad(faction, _order_sid,
		global_position, _MCfg.MONK_RES_SEARCH_RADIUS * 2.0)

## Общий сон по коридору (BigStand, этап 3) монаху не нужен: он засыпает САМ
## из _monk_step, когда некого лечить и не к кому идти (ТЗ 16.09.2026), и
## будится ударом, приказом и собственным событием. Коридорный сон мог бы
## усыпить его посреди канала воскрешения
func may_sleep_physics() -> bool:
	return false

## Тик снят (гарнизон, спячка, снятие с карты) — картинки лечения гаснут ТЕМ ЖЕ
## вызовом. Иначе их некому погасить: и лента, и овал, и круг канала гаснут
## только из tick_physics, а он после set_tick(false) не идёт (ТЗ 18.09.2026,
## п. 1: «зелёные круги остаются на земле» — монах, ушедший в крепость
## лечиться, оставлял овал под последним пациентом)
func set_tick(enable: bool) -> void:
	super.set_tick(enable)
	if not enable:
		_stop_heal_vfx()
		_stop_res()

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

## ── ТИК МОНАХА: СОБЫТИЯ И РЕДКИЙ СКАН (ТЗ 16.09.2026) ─────────────────────
## Покадрово тикают только текущие процессы (отход, канал воскрешения, ленты
## VFX). Всё остальное — по такту heal_tick_sec (MONK_SCAN_SEC, короче у
## кузницы) или по событию (закончил лечить, получил приказ, ударили): выбор
## ОТРЯДА-пациента, марш к фронту, сон, ауры. Прежние покадровые такты
## (лечение 0.5 с, ауры 1 с, расстановка 1 с) сняты — их работу делает один
## скан
var _scan_t: float = 0.0
## Такт дремоты (некого лечить и не к кому идти), с
const MONK_IDLE_SCAN_SEC := 1.5
## Отряд-пациент (0 — нет); ставится сканом или приказом ПКМ
var patient_sid: int = 0
## Цели лечения последнего такта (для стендов и VFX)
var heal_targets: Array = []
## Диагностика: сканов, тактов лечения, маршей к фронту, засыпаний
var scans: int = 0
var heal_ticks: int = 0
var front_moves: int = 0
var sleeps: int = 0

func tick_physics(delta: float, prof: bool = false, bm: bool = true,
		bonus_ver: int = -1) -> void:
	super.tick_physics(delta, prof, bm, bonus_ver)
	if state == State.DEAD or garrisoned:
		_stop_heal_vfx()
		_stop_res()
		return
	_ride_heal_vfx()
	_step_t = maxf(_step_t - delta, 0.0)
	_res_cool = maxf(_res_cool - delta, 0.0)
	_retreat_cd = maxf(_retreat_cd - delta, 0.0)
	_tick_retreat(delta)
	_tick_shield(delta)
	var _pm: bool = _prof_on
	var _tm: int = Time.get_ticks_usec() if _pm else 0
	# Канал воскрешения — процесс, идёт покадрово, пока есть тело
	# ТЗ 17.09.2026: канал идёт ПАРАЛЛЕЛЬНО лечению всегда («Двойное
	# попечение» 4d теперь только укорачивает канал)
	if _res_target != null:
		_tick_res(delta)
		if _pm: _Opt.prof_add("monk_res", Time.get_ticks_usec() - _tm)
	_scan_t -= delta
	if _scan_t > 0.0:
		return
	_scan_t = heal_tick_sec()
	if _pm: _tm = Time.get_ticks_usec()
	_monk_step()

	if _pm: _Opt.prof_add("monk_pulse", Time.get_ticks_usec() - _tm)

## Событие, требующее немедленного пересмотра (приказ, удар, конец лечения)
func _monk_wake() -> void:
	_scan_t = 0.0
	wake_physics()

## Один шаг автомата монаха. Порядок: отход в силе — ничего; приказ игрока —
## отряд-пациент задан; иначе скан самого побитого отряда в ауре; есть работа
## — этап A (раненые) / этап B (тела); нет работы в ауре — марш к ближайшему
## своему отряду; нет никого — сон
func _monk_step() -> void:
	if _retreat_goal.x != INF:
		# На отходе лечим только тех, кто и так в дистанции каста, — подхода
		# нет (qa_monk_forge E3/E4: отход не гасится подходом, лечение не
		# прерывается)
		if patient_sid > 0 and _care_squad(patient_sid, false):
			return
		if _care_lone(false):
			return
		_stop_heal_vfx()
		return
	scans += 1
	_tick_aura(0.0, true)
	# Дистанция между монахами — часть того же скана (гистерезис и пауза
	# после приказа внутри _tick_spacing; delta 0 = «прошёл один такт скана»)
	_tick_spacing(0.0)
	if _order_alive():
		patient_sid = _order_sid
	elif not _squad_needs_care(patient_sid):
		patient_sid = _pick_patient_squad()
	if patient_sid > 0:
		if _care_squad(patient_sid):
			return
		# Пациент вылечен и укомплектован: приказ исполнен, дальше автономия
		if _order_alive() and _order_sid == patient_sid:
			_order_target = null
			_order_sid = 0
		patient_sid = 0
	# Одиночки вне отрядов (рабочий, гарнизонный выходец, сам монах) — по
	# колонке ядра: самый раненый свой в ауре
	if _care_lone():
		return
	_stop_heal_vfx()
	# Ни одного раненого в ауре: к фронту
	if _go_to_front():
		return
	# Некому помогать и не к кому идти: ДРЕМОТА — редкий скан раз в
	# MONK_IDLE_SCAN_SEC. Полный сон физики (set_tick(false)) пробовался и
	# снят: раненый, появившийся рядом со спящим монахом, не событие — его
	# заметит только скан (qa_monk_vfx B2). Цена дремоты — одно вычитание
	# таймера в тике и один обход реестра отрядов раз в несколько секунд
	if state == State.IDLE and not moved_recently() and may_sleep_now():
		sleeps += 1
		_scan_t = MONK_IDLE_SCAN_SEC

func may_sleep_now() -> bool:
	return _res_target == null and _retreat_goal.x == INF and not player_order_active()

## Отряду нужен монах: есть раненый живой или (с воскрешением) павший
func _squad_needs_care(sid: int) -> bool:
	if sid <= 0:
		return false
	var raw: Variant = GameManager.squads.get(sid)
	if raw == null:
		return false
	var members: Array = (raw as Dictionary).get("members", [])
	var alive := 0
	for m in members:
		if m == null or not is_instance_valid(m):
			continue
		var u := m as Unit
		if u == null or u.is_dead():
			continue
		alive += 1
		if _may_heal(u):
			return true
	if alive == 0:
		return false
	return _squad_short(sid, alive)

## Самый побитый свой отряд в ауре: доля недостающего запаса плюс доля
## недостающих моделей (0..2). Один обход реестра отрядов, без сетки
func _pick_patient_squad() -> int:
	var mp: Vector3 = position if _local_xform else global_position
	var r: float = heal_radius()
	var r2: float = r * r
	var best_sid := 0
	var best_score := 0.0
	var res_ok: bool = can_resurrect()
	for key in GameManager.squads:
		var sid: int = int(key)
		var sq: Dictionary = GameManager.squads[key]
		if int(sq.get("faction", -1)) != faction:
			continue
		if String(sq.get("type", "")) == "worker":
			continue
		var c: Vector2 = GameManager.squad_centre_xz(sid)
		if c == Vector2.INF:
			continue
		var dx: float = c.x - mp.x
		var dz: float = c.y - mp.z
		if dx * dx + dz * dz > r2:
			continue
		var hp := 0.0
		var hpmax := 0.0
		var alive := 0
		for m in sq.get("members", []):
			if m == null or not is_instance_valid(m):
				continue
			var u := m as Unit
			if u == null or u.is_dead():
				continue
			alive += 1
			hp += u.current_health
			hpmax += u.max_health
		if alive == 0 or hpmax <= 0.0:
			continue
		var score: float = 1.0 - hp / hpmax
		if res_ok:
			var full: int = int(sq.get("full", alive))
			if full > alive:
				score += float(full - alive) / float(full)
		if score > best_score + 0.001:
			best_score = score
			best_sid = sid
	return best_sid

## Лечить отряд: этап A — раненые (до max_heal_targets за такт, VFX на каждом),
## этап B — павшие. true — работа была (или идём к ней)
func _care_squad(sid: int, may_walk: bool = true) -> bool:
	var raw: Variant = GameManager.squads.get(sid)
	if raw == null:
		return false
	var hurt: Array = []      # [frac, Unit]
	var alive := 0
	var first_live: Unit = null
	for m in (raw as Dictionary).get("members", []):
		if m == null or not is_instance_valid(m):
			continue
		var u := m as Unit
		if u == null or u.is_dead():
			continue
		alive += 1
		if first_live == null:
			first_live = u
		if _may_heal(u):
			hurt.append([u.current_health / maxf(u.max_health, 1.0), u])
	# Этап B — павшие отряда — ОТКРЫВАЕТСЯ И ПРИ РАНЕНЫХ (ТЗ 17.09.2026):
	# канал воскрешения идёт параллельно лечению, а не после него
	if can_resurrect() and _res_target == null and _res_cool <= 0.0 and alive > 0:
		var c = _squad_corpse(sid)
		if c != null:
			_res_target = c
			_res_spot = Vector3.INF
			_res_left = res_sec()
			_res_cool = res_cooldown()
	if hurt.is_empty():
		if _res_target != null:
			return true
		# Раненых нет, но отряд не укомплектован: ждём откат канала у отряда,
		# приказ и пациент не сбрасываются (ТЗ 18.09.2026, п. 2). Отряд ушёл
		# за ауру — подходим тем же приказом, что к пациенту
		if not _squad_short(sid, alive):
			return false
		if may_walk and first_live != null \
				and global_position.distance_to(first_live.global_position) > cast_range():
			_walk_to_patient(first_live, sid)
			_stop_heal_vfx()
		return true
	hurt.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var worst: Unit = hurt[0][1]
	# ФОКУС: начатый пациент ведётся до 100 % (Fix Pack 15.09), более раненый
	# сосед его не перехватывает — иначе лечение размазывается по всем
	if heal_target != null and is_instance_valid(heal_target):
		var cur := heal_target as Unit
		if _may_heal(cur) and cur.squad_id == sid:
			worst = cur
	# Подход — только когда пациент ЗА границей ауры; встаём на stand_dist
	# от центра его отряда, снаружи строя (ТЗ 17.09.2026)
	var gap: float = global_position.distance_to(worst.global_position)
	if gap > cast_range():
		if not may_walk:
			return false
		heal_target = worst          # «взял в лечение» — с момента подхода
		_walk_to_patient(worst, sid)
		_stop_heal_vfx()
		return true
	# Этап A: лечим до cap целей за такт
	var tick: float = heal_tick_sec()
	var cap: int = max_heal_targets()
	var full: bool = full_heal_tick()
	var per: float = tick / _MCfg.MONK_HEAL_SEC_PER_MAN * heal_amount_mult()
	var given := 0.0
	var touched := 0
	heal_targets.clear()
	var cast_r2: float = cast_range() * cast_range()
	for row in hurt:
		if touched >= cap:
			break
		var u2 := (row[1]) as Unit
		if u2 == null or not is_instance_valid(u2) or u2.is_dead():
			continue
		# Массовый каст бьёт по ауре, одиночный — только в дистанции каста
		var d2: float = global_position.distance_squared_to(u2.global_position)
		if cap == 1 and u2 != worst:
			continue                 # фокус: одиночный каст — только самому раненому
		if d2 > cast_r2:
			continue
		touched += 1
		var before2: float = u2.current_health
		if full:
			u2.current_health = u2.max_health
		else:
			u2.current_health = minf(u2.max_health, u2.current_health + u2.max_health * per)
		var got: float = u2.current_health - before2
		given += got
		healed_total += got
		_credit_heal_xp(got)
		u2._soa_push_stats()
		heal_targets.append(u2)
	if touched == 0:
		_stop_heal_vfx()             # лечить некого — эффект не висит на прежнем
		return true
	heal_ticks += 1
	aoe_touched = touched
	heal_target = worst
	_play_attack_anim("heal", int(tick * 1000.0) + 120)
	_bind_heal_vfx_many(heal_targets)
	_self_heal(given)
	return true

## Пациент-одиночка: самый раненый свой в ауре по колонке ядра (без отряда
## в реестре — рабочий, одиночка, сам монах). Держится начатый (heal_target),
## пока он ранен и в поводке, — фокус, а не размазывание
func _care_lone(may_walk: bool = true) -> bool:
	var cur: Unit = null
	if heal_target != null and is_instance_valid(heal_target):
		cur = heal_target as Unit
	var best: Unit = null
	# Фокус держится в пределах КАСТА (ТЗ 18.09.2026): каст идёт из ауры
	# (20 м, 17.09.2026), и поводок 14 м терял начатого пациента в 16 м на
	# каждом такте — лечение размазывалось (qa_monk_healing C3/E1)
	if _may_heal(cur) and cur.squad_id == 0 \
			and global_position.distance_to(cur.global_position) \
				<= maxf(_MCfg.MONK_HEAL_LEASH, cast_range()):
		best = cur
	else:
		var mp: Vector3 = position if _local_xform else global_position
		var cand = GameManager.army.most_wounded_of_side(mp.x, mp.z, int(faction), heal_radius(), _soa)
		if cand != null and is_instance_valid(cand):
			var cu := cand as Unit
			if _may_heal(cu):
				best = cu
		if _may_heal(self) and (best == null or current_health / max_health < best.current_health / best.max_health):
			best = self
	if best == null:
		return false
	# Раненый состоит в отряде — ведём его отряд целиком (общий путь)
	if best.squad_id > 0 and best != self:
		patient_sid = best.squad_id
		return _care_squad(best.squad_id)
	var gap: float = global_position.distance_to(best.global_position)
	if best != self and gap > cast_range():
		if not may_walk:
			return false
		heal_target = best
		_walk_to_patient(best)
		_stop_heal_vfx()
		return true
	var tick: float = heal_tick_sec()
	var per: float = tick / _MCfg.MONK_HEAL_SEC_PER_MAN * heal_amount_mult()
	var before: float = best.current_health
	if full_heal_tick():
		best.current_health = best.max_health
	else:
		best.current_health = minf(best.max_health, best.current_health + best.max_health * per)
	var got: float = best.current_health - before
	healed_total += got
	_credit_heal_xp(got)
	best._soa_push_stats()
	heal_target = best
	heal_targets.clear()
	heal_targets.append(best)
	heal_ticks += 1
	_play_attack_anim("heal", int(tick * 1000.0) + 120)
	_bind_heal_vfx_many(heal_targets)
	if best != self:
		_self_heal(got)
	return true

## Павший отряда, годный к подъёму (только для отряда-пациента)
## ТЗ 18.09.2026, п. 2: тело ищется ПО ОТРЯДУ (find_raisable_of_squad), а не
## «ближайшее своей стороны с последующей сверкой отряда» — сверка в замесе
## отвечала «нет» на первом же чужом по отряду теле, и подъём кончался одной
## моделью. Радиус — поиск воскрешения (у приказа — вдвое шире)
func _squad_corpse(sid: int):
	if sid <= 0 or GameManager.corpses == null or not can_resurrect():
		return null
	var r: float = maxf(heal_radius(), _MCfg.MONK_RES_SEARCH_RADIUS)
	if _order_alive() and _order_sid == sid:
		r = maxf(r, _MCfg.MONK_RES_SEARCH_RADIUS * 2.0)
	return GameManager.corpses.find_raisable_of_squad(faction, sid, global_position, r)

## Отряд НЕ УКОМПЛЕКТОВАН и есть кого поднять: живых меньше штата и в
## радиусе поиска лежит его тело. По этому признаку монах держит отряд
## пациентом (и приказ ПКМ — исполняемым) и на откате канала: раньше откат
## 5 с читался как «работы нет», приказ сбрасывался, монах уходил к фронту
func _squad_short(sid: int, alive: int) -> bool:
	if not can_resurrect() or alive <= 0:
		return false
	var raw: Variant = GameManager.squads.get(sid)
	if raw == null:
		return false
	var full: int = int((raw as Dictionary).get("full", alive))
	if alive >= full:
		return false
	return _squad_corpse(sid) != null

## Нет работы в ауре: ОДИН скан реестра отрядов — ближайший свой боевой отряд,
## идём к нему на MONK_FRONT_DIST. true — идём или уже стоим у фронта
func _go_to_front() -> bool:
	if player_order_active() or _panicked or retreating:
		return false
	var mp: Vector3 = position if _local_xform else global_position
	var best := Vector2.INF
	var best_d2 := INF
	for key in GameManager.squads:
		var sid: int = int(key)
		if sid == squad_id:
			continue
		var sq: Dictionary = GameManager.squads[key]
		if int(sq.get("faction", -1)) != faction:
			continue
		if not GameManager.squad_is_combat(sid):
			continue
		var c: Vector2 = GameManager.squad_centre_xz(sid)
		if c == Vector2.INF:
			continue
		var dx: float = c.x - mp.x
		var dz: float = c.y - mp.z
		var d2: float = dx * dx + dz * dz
		if d2 < best_d2:
			best_d2 = d2
			best = c
	if best == Vector2.INF:
		return false
	var d: float = sqrt(best_d2)
	# Уже у фронта — на границе ауры: стоим (гистерезис, чтобы не дёргаться)
	var sd: float = stand_dist()
	if d <= sd + 3.0:
		return false
	if _step_t > 0.0:
		return true
	var dir := Vector3(best.x - mp.x, 0.0, best.y - mp.z) / d
	var stand: Vector3 = Vector3(best.x, 0.0, best.y) - dir * sd
	if _step_to != Vector3.INF and _step_to.distance_to(stand) < _MCfg.MONK_MOVE_SLACK \
			and state == State.MOVING:
		return true
	_step_t = _MCfg.MONK_STEP_SEC
	_step_to = stand
	front_moves += 1
	if _Opt.cmd_meter: _Opt.cmd_src = "monk_front"
	command_move(GameManager.land_target(stand))
	if _Opt.cmd_meter: _Opt.cmd_src = ""
	return true

func _tick_spacing(delta: float) -> void:
	_space_t -= delta if delta > 0.0 else heal_tick_sec()
	if _space_t > 0.0:
		return
	_space_t = 0.0
	# ── ВО ВРЕМЯ ОТХОДА РАССТАНОВКА МОЛЧИТ ────────────────────────────────
	# Иначе она перебивает отход своим приказом: монах, вставший на секунду
	# (такт расстановки ловит именно IDLE), получал новую точку в полуметре
	# и до точки отхода не доходил (замер qa_monk_forge E3: 3.3 м из пяти)
	if _retreat_goal.x != INF:
		return
	if state != State.IDLE or player_order_active() or _panicked or retreating:
		return
	var mp: Vector3 = global_position
	var nearest: Monk = null
	# ── ГИСТЕРЕЗИС (BigStand, этап 1) ──────────────────────────────────────
	# Отход заводится только с MONK_SPACING − SPACING_HYST, а точка отхода
	# считается до полной дистанции: иначе два монаха, вставшие ровно на
	# 4.9 м, по очереди отходили на полметра каждую секунду (зонд: 4.8
	# приказов/с на 12 стоящих монахов). Сосед, который сам идёт, отойдёт
	# или подойдёт сам — от него не отходим: расстановка — дело стоящих
	var nd: float = _MCfg.MONK_SPACING - SPACING_HYST
	for n in GameManager.unit_grid.query_radius(mp, nd):
		if n == null or not is_instance_valid(n) or n == self:
			continue
		var m := n as Monk
		if m == null or m.is_dead() or m.faction != faction:
			continue
		if m.state != State.IDLE or m.moved_recently():
			continue
		var d: float = mp.distance_to(m.global_position)
		if d < nd:
			nd = d
			nearest = m
	if nearest == null:
		return
	_space_t = SPACING_MOVE_SEC
	var away: Vector3 = mp - nearest.global_position
	away.y = 0.0
	if away.length_squared() < 1e-4:
		away = Vector3(1.0, 0.0, 0.0).rotated(Vector3.UP, float(get_instance_id() % 7))
	var goal: Vector3 = mp + away.normalized() * (_MCfg.MONK_SPACING - nd + 0.5)
	spacing_moves += 1
	if _Opt.cmd_meter: _Opt.cmd_src = "monk_spacing"
	command_move(GameManager.land_target(goal))
	if _Opt.cmd_meter: _Opt.cmd_src = ""

# ═════════════════════════════════════════════════════════════════════════════
# АУРЫ ПОДДЕРЖКИ (письмо 12): награды ветеранства монаха
# ═════════════════════════════════════════════════════════════════════════════
func aura_radius() -> float:
	return _MCfg.MONK_AURA_BASE_R + GameManager.squad_bonus(squad_id, "aura_radius")

## Ауры раздаются в такт скана (ТЗ 16.09.2026: без тяжёлых тиков): `force` —
## вызов из _monk_step, свой таймер тогда не спрашивается. Срок удержания
## покрывает такт с запасом (MONK_AURA_HOLD_MS 1.7 с > MONK_SCAN_SEC 1.2)
func _tick_aura(delta: float, force: bool = false) -> void:
	if not force:
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
	var until: int = now_ms + maxi(_MCfg.MONK_AURA_HOLD_MS, int(heal_tick_sec() * 1000.0) + 500)
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
## ── ВОСКРЕШЕНИЕ ОТКРЫВАЕТ БОНУС РЯДА 2, А НЕ 3d ──────────────────────────
## Ветка переставлена заказом 13.09.2026: 2d «Первое Чудо» включает подъём,
## 4d поднимает двоих, 5d — конвейер по 3-4
func can_resurrect() -> bool:
	return _node("2d") or _node("4d") or _node("5d")

## Скольких павших поднимает ОДИН канал
func max_resurrect_count() -> int:
	if _node("5d"):
		return 4
	if _node("4d"):
		return 2
	return 1

## Доля запаса, с которой встаёт поднятый
func res_health_frac() -> float:
	return 0.5 if (_node("4d") or _node("5d")) else 0.3

## Откат между каналами: MONK_RES_COOLDOWN / _4D / _5D (5 / 4 / 2 с)
func res_cooldown() -> float:
	if _node("5d"):
		return _MCfg.MONK_RES_COOLDOWN_5D
	if _node("4d"):
		return _MCfg.MONK_RES_COOLDOWN_4D
	return _MCfg.MONK_RES_COOLDOWN

## Самовоскрешение — бонус ряда 3, один раз за бой
func has_self_revive() -> bool:
	return _node("3d") and not self_res_used

## Сколько живых в отряде. Состав читается НАПРЯМУЮ: squad_members() не
## читатель — он распускает опустевший отряд прямо в геттере, а спрашиваем
## мы именно про опустевший
func _squad_alive(sid: int) -> int:
	var raw: Variant = GameManager.squads.get(sid)
	if raw == null:
		return 0
	var n := 0
	for m in (raw as Dictionary).get("members", []):
		if m != null and is_instance_valid(m) and not (m as Unit).is_dead():
			n += 1
	return n

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
	# ── ПРИОРИТЕТ: СНАЧАЛА ПАВШИЕ МОНАХИ ─────────────────────────────────
	# Прямой заказ. Приоритет ПО РОДУ, а не по отряду: «свой отряд» у монахов —
	# это Ctrl-группа игрока (сам монах — отряд из одного), а Ctrl-группы
	# живут списком ЖИВЫХ узлов, и у тела спросить его группу уже нечем
	var c = null
	if _order_alive() and _order_sid > 0:
		c = _order_corpse()
	else:
		c = GameManager.corpses.find_raisable_priority(faction, global_position,
			maxf(heal_radius(), _MCfg.MONK_RES_SEARCH_RADIUS), "monk")
	if c == null:
		return false
	# ── ПОЛНОСТЬЮ ВЫБИТЫЙ ОТРЯД НЕ ПОДНИМАЕТСЯ ВОВСЕ («Дух-Спас») ─────────
	# НО ЭТО НЕ КАСАЕТСЯ ОДИНОЧЕК: у павшего монаха живых в отряде НОЛЬ
	# всегда, и общее правило запретило бы подъём монахов насовсем
	var csid: int = int(c.squad_id) if ("squad_id" in c) else 0
	if csid > 0 and not GameManager.squad_is_single_agent(csid) \
		and _squad_alive(csid) == 0:
		return false
	_res_target = c
	_res_spot = Vector3.INF
	_res_left = res_sec()
	_res_cool = res_cooldown()
	return true

# ═════════════════════════════════════════════════════════════════════════════
# УРОН ПО МОНАХУ: ЩИТ → ВТОРОЕ ДЫХАНИЕ → САМОВОСКРЕШЕНИЕ → ОТХОД
# ═════════════════════════════════════════════════════════════════════════════
## Порядок здесь и есть баланс: щит съедает урон ДО запаса жизни, «Второе
## Дыхание» ловит смертельный удар по запасу, самовоскрешение — последний
## рубеж. Все спасения ловят удар ДО базового take_damage: после него монах
## уже снят со строки ядра, из сетки и из отряда, тело уложено в слой павших,
## и «поднять его обратно» означало бы собрать бойца заново
func take_damage(amount: float, attacker: Node3D = null) -> void:
	if is_dead():
		return
	wake_physics()
	# Неуязвимость «Второго Дыхания»
	if _invuln_until > now_ms:
		_step_away_from(attacker)
		return
	# «Святой Щит» (4c)
	if shield_hp > 0.0 and amount > 0.0:
		var eaten: float = minf(shield_hp, amount)
		shield_hp -= eaten
		amount -= eaten
	_shield_calm = SHIELD_CALM_SEC
	# «Второе Дыхание» (5c): смертельный удар оставляет 1 HP и 5 с неуязвимости
	if _node("5c") and amount >= current_health:
		current_health = 1.0
		_invuln_until = now_ms + int(SECOND_WIND_SEC * 1000.0)
		death_saves += 1
		_soa_push_stats()
		_step_away_from(attacker)
		return
	# Самовоскрешение (бонус ряда 3): один раз за бой, половина запаса
	if amount >= current_health and has_self_revive():
		self_res_used = true
		current_health = max_health * SELF_REVIVE_FRAC
		_soa_push_stats()
		_res_flash(global_position)
		_step_away_from(attacker)
		return
	super.take_damage(amount, attacker)
	if is_dead():
		return
	_step_away_from(attacker)

## Отход кончается ПРИХОДОМ, а не часами. Потолок нужен на случай, когда
## дойти нельзя вовсе (упёрся в своих, в воду, в край карты), и ВЫВОДИТСЯ
## ИЗ ШАГА: монах медленный, и жёсткие три секунды обрывали отход на
## трёх метрах из пяти (замер qa_monk_forge E3)
func _retreat_timeout() -> float:
	return RETREAT_DIST / maxf(move_speed, 0.5) + 1.5

func _tick_retreat(delta: float) -> void:
	if _retreat_goal.x == INF:
		return
	_retreat_give_up -= delta
	var d: float = Vector2(global_position.x - _retreat_goal.x,
		global_position.z - _retreat_goal.z).length()
	if d <= ARRIVE_RADIUS or _retreat_give_up <= 0.0:
		_retreat_goal = Vector3.INF

## ── ЩИТ КОПИТСЯ ВНЕ БОЯ ──────────────────────────────────────────────────
## Узел не изучен — щита нет вовсе, и такт стоит одно сравнение
func _tick_shield(delta: float) -> void:
	if not _node("4c"):
		shield_hp = 0.0
		return
	if _shield_calm > 0.0:
		_shield_calm -= delta
		return
	if shield_hp < SHIELD_MAX:
		shield_hp = minf(SHIELD_MAX, shield_hp + SHIELD_REGEN_PER_SEC * delta)

## ── ОТХОД ПОД УРОНОМ ─────────────────────────────────────────────────────
## Обычным command_move: своей механики ходьбы у монаха нет и быть не должно —
## движение мимо пакетного шага означало бы движение мимо проверки чужих тел,
## воды и границ карты. Лечение при этом НЕ прерывается: такт ауры идёт в
## tick_physics и на состояние MOVING не смотрит вовсе
## ИМЯ НЕ `_retreat_from`: в Unit так зовётся ПОЛЕ (точка начала отхода, по
## ней считается билет прохода). Совпадение имён метода и поля базы GDScript
## ловит как «Member is not a function» — и ловит только при компиляции
func _step_away_from(attacker: Node3D) -> void:
	if _retreat_cd > 0.0 or is_dead() or garrisoned:
		return
	# Приказ игрока важнее: послали стоять — значит стоять
	if player_order_active():
		return
	var mp: Vector3 = global_position
	var away := Vector3(1.0, 0.0, 0.0)
	if attacker != null and is_instance_valid(attacker):
		var v := Vector3(mp.x - attacker.global_position.x, 0.0,
			mp.z - attacker.global_position.z)
		if v.length_squared() > 1e-4:
			away = v.normalized()
	_retreat_cd = RETREAT_CD
	retreats += 1
	# ── ОТХОД К СВОИМ, А НЕ ПРОСТО ПРОЧЬ (ТЗ 16.09.2026) ─────────────────
	# Ближайший свой боевой отряд в двух радиусах ауры тянет точку отхода к
	# себе: «прочь от обидчика» и «к своим» складываются, дальность
	# MONK_RETREAT_DIST. Своих нет — прежний отход прочь
	var toward: Vector3 = _nearest_ally_squad_dir(mp)
	if toward != Vector3.ZERO:
		away = (away + toward * 1.5).normalized() if (away + toward * 1.5).length_squared() > 1e-4 else toward
	var goal: Vector3 = GameManager.land_target(mp + away * _MCfg.MONK_RETREAT_DIST)
	_retreat_goal = goal
	_retreat_give_up = _MCfg.MONK_RETREAT_DIST / maxf(move_speed, 0.5) + 1.5
	_stop_heal_vfx()
	if _Opt.cmd_meter: _Opt.cmd_src = "monk_retreat"
	command_move(goal)
	if _Opt.cmd_meter: _Opt.cmd_src = ""

## Направление к центру ближайшего своего боевого отряда (ZERO — нет)
func _nearest_ally_squad_dir(mp: Vector3) -> Vector3:
	var best := Vector2.INF
	var best_d2: float = (heal_radius() * 2.0) * (heal_radius() * 2.0)
	for key in GameManager.squads:
		var sid: int = int(key)
		if sid == squad_id:
			continue
		var sq: Dictionary = GameManager.squads[key]
		if int(sq.get("faction", -1)) != faction or not GameManager.squad_is_combat(sid):
			continue
		var c: Vector2 = GameManager.squad_centre_xz(sid)
		if c == Vector2.INF:
			continue
		var dx: float = c.x - mp.x
		var dz: float = c.y - mp.z
		var d2: float = dx * dx + dz * dz
		if d2 < best_d2 and d2 > 1.0:
			best_d2 = d2
			best = c
	if best == Vector2.INF:
		return Vector3.ZERO
	return Vector3(best.x - mp.x, 0.0, best.y - mp.z).normalized()

## ── ПРИКАЗ ИГРОКА ЖИВЁТ ДО ПРИХОДА (ТЗ 19.09.2026, блок 2) ────────────────
## Общий замок приказа (FORCED_MOVE_SEC) — 3 с, у монаха это ~6 м пути. Дальше
## его автоматы (к фронту, к пациенту, к точке подъёма, дистанция между
## монахами, отход под уроном) переписывали точку, и ПКМ по земле дальше
## шести метров «не срабатывал». Пока монах ИДЁТ по приказу игрока, приказ
## действует: все гейты спрашивают player_order_active()
var _player_goal: bool = false
var player_goal_moves: int = 0

func player_order_active() -> bool:
	if _player_goal and state == State.MOVING:
		return true
	return super.player_order_active()

## Приказ на движение от игрока снимает приказ лечения
func command_move(target_pos: Vector3, slow_march: bool = false, face_dir: Vector3 = Vector3.ZERO,
		keep_retreat: bool = false, player_order: bool = false, run: bool = false) -> void:
	if player_order:
		_order_target = null
		_order_sid = 0
		patient_sid = 0
		_stop_heal_vfx()
		_retreat_goal = Vector3.INF
		_step_to = Vector3.INF
		_player_goal = true
		player_goal_moves += 1
	else:
		_player_goal = false
	super.command_move(target_pos, slow_march, face_dir, keep_retreat, player_order, run)

func _stop_res() -> void:
	_res_target = null
	_res_left = 0.0
	_res_spot = Vector3.INF
	if _res_aura != null and is_instance_valid(_res_aura):
		_res_aura.visible = false

## Точка воскрешения кэшируется на RES_SPOT_REFRESH_SEC (qa_melee_bench,
## 14.09.2026): raise_spot — обход состава × слотов отряда (до 3600 пар с
## чтением global_position) и звался КАЖДЫЙ кадр канала — худший тик монаха
## 7.9 мс. Отряд за полсекунды уходит на метр, ауре это безразлично, а сам
## подъём (raise_fallen) считает точку заново
const RES_SPOT_REFRESH_SEC := 0.5
var _res_spot: Vector3 = Vector3.INF
var _res_spot_t: float = 0.0

func _tick_res(delta: float) -> void:
	var c = _res_target
	if c == null or int(c.get("index")) < 0 or not bool(c.get("raisable")):
		_stop_res()
		return
	# ── КАСТ В ТОЧКУ ОТРЯДА, А НЕ К ТЕЛУ (ТЗ 14.09.2026, п. 9) ────────────
	# Боец встанет в своём слоте строя (GameManager.raise_spot), туда монах и
	# подходит, там и держит ауру: бегать к телу, а потом за вставшим — незачем
	_res_spot_t -= delta
	if _res_spot.x == INF or _res_spot_t <= 0.0:
		_res_spot_t = RES_SPOT_REFRESH_SEC
		var sp: Vector3 = GameManager.raise_spot(c)
		if sp.x == INF:
			sp = c.get("pos")
		sp.y = GameManager.get_terrain_height(sp.x, sp.z)
		_res_spot = sp
	var cp: Vector3 = _res_spot
	var gap: float = Vector2(cp.x - global_position.x, cp.z - global_position.z).length()
	if gap > cast_range():
		# Точка подъёма за аурой: подойти на границу ауры тем же приказом,
		# что к пациенту (слабина — чтобы не переиздавать приказ каждый такт)
		if _res_aura != null and is_instance_valid(_res_aura):
			_res_aura.visible = false
		# Только СТОЯ: идущему к пациенту второй приказ с точкой в паре метров
		# от первой — те самые перебежки; дойдя к отряду, он и в ауру точки
		# подъёма попадёт
		if not player_order_active() and _step_t <= 0.0 and not _panicked \
				and state != State.MOVING:
			var to_me: Vector3 = global_position - cp
			to_me.y = 0.0
			if to_me.length() < 0.01:
				to_me = Vector3(1.0, 0.0, 0.0)
			var stand: Vector3 = cp + to_me.normalized() * stand_dist()
			if _step_to == Vector3.INF or _step_to.distance_to(stand) >= _MCfg.MONK_MOVE_SLACK \
					or state != State.MOVING:
				_step_t = _MCfg.MONK_STEP_SEC
				_step_to = stand
				approach_moves += 1
				if _Opt.cmd_meter: _Opt.cmd_src = "monk_res_approach"
				command_move(GameManager.land_target(stand))
				if _Opt.cmd_meter: _Opt.cmd_src = ""
		return
	# Канал: лента лечения, свой круг над точкой подъёма. Круг — только у
	# СТОЯЩЕГО монаха (ТЗ 18.09.2026, п. 1): идущий к точке подъёма канал
	# держит, но картинки на земле не оставляет
	_res_left -= delta
	if _res_aura == null or not is_instance_valid(_res_aura):
		_res_aura = _make_aura_node("ResAura")
	if _res_aura != null and is_instance_valid(_res_aura):
		_res_aura.visible = _vfx_caster_still()
		_res_aura.global_position = Vector3(cp.x, cp.y + AURA_LIFT_M, cp.z)
	if now_ms >= _anim_lock_until_ms:
		_play_attack_anim("heal", 600)
	if _res_left > 0.0:
		return
	var _tr: int = Time.get_ticks_usec() if _prof_on else 0
	var u: Unit = GameManager.raise_fallen(c, self)
	if _prof_on: _Opt.prof_add("monk_raise", Time.get_ticks_usec() - _tr)
	_stop_res()
	_res_cool = res_cooldown()
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
## Один такт: монах подходит к своему раненому и льёт в него запас
## ── БОНУСЫ КУЗНИЦЫ (спринт 16) ──────────────────────────────────────────────
## Темп (короче такт), объём (больше за такт) и радиус — те же ключи, что в
## forge_config, читаются через unit_bonus, как bonus_range у лучника
## ── УЗЛЫ ВЕТКИ МОНАХА ЧИТАЮТСЯ ОДНИМ СПОСОБОМ ─────────────────────────────
## Один помощник на пятнадцать узлов и пять бонусов: по функции на узел — это
## двадцать почти одинаковых чтений реестра исследований
func _node(cell: String) -> bool:
	return GameManager.is_researched(faction, "monk_" + cell)

## Доля отданного исцеления, которую монах забирает себе («Самохил I», 1c)
func self_heal_frac() -> float:
	return 0.30 if _node("1c") else 0.0

## Скольких раненых накрывает один такт: 1 — как было, 3 — «Троичный Поток»
## (1d), весь отряд — «Опека» (3d) и прежняя «Благодать»
func max_heal_targets() -> int:
	if _node("3d") or aoe_active():
		return 1000000
	if _node("1d"):
		return 3
	return 1

## «Непрерывный Поток» (4b) задаёт такт АБСОЛЮТНО, а не долей
const FLOW_TICK := 0.3
## «Абсолютное Целительство» (5b): такт восполняет живым весь запас
func full_heal_tick() -> bool:
	return _node("5b")

const RETREAT_DIST := 5.0
const RETREAT_CD := 1.0
const SHIELD_MAX := 150.0
const SHIELD_CALM_SEC := 6.0
const SHIELD_REGEN_PER_SEC := 15.0
const SECOND_WIND_SEC := 5.0
const SELF_REVIVE_FRAC := 0.5

## Такт скана и лечения (ТЗ 16.09.2026: 1.0-1.5 с вместо 0.5). Объём за такт
## пропорционален такту (per = tick / SEC_PER_MAN), поэтому темп исцеления в
## секунду от длины такта не зависит; кузница ускоряет такт (bonus_heal_rate,
## «Непрерывный поток» 4b — пол FLOW_TICK), а не удваивает объём
func heal_tick_sec() -> float:
	var k: float = 1.0 + GameManager.unit_bonus(faction, "monk", "bonus_heal_rate")
	var t: float = _MCfg.MONK_SCAN_SEC / maxf(k, 0.1)
	if _node("4b"):
		t = minf(t, FLOW_TICK)
	return maxf(t, FLOW_TICK)

func heal_amount_mult() -> float:
	return 1.0 + GameManager.unit_bonus(faction, "monk", "bonus_heal_amount")

func heal_radius() -> float:
	# «Глобальный Покров» (5a): аура на всю карту. ЧИСЛОМ, а не признаком —
	# все, кто радиус читает, продолжают читать метры
	if _node("5a"):
		return 1.0e6
	return _MCfg.MONK_HEAL_RADIUS + GameManager.unit_bonus(faction, "monk", "bonus_heal_radius")

## AOE-перк «Благодать» изучен и включён (переключатель, как залп у лучников)
## Со спринта 19 «Благодать» — узел 2d (tier 2, письмо 12)
func aoe_active() -> bool:
	return squad_id > 0 and GameManager.squad_has_ability(squad_id, "monk_2d") \
		and GameManager.squad_ability_on(squad_id, "monk_2d")

## Один такт AOE: все раненые свои в радиусе, каждый — на MONK_AOE_RATE долю
## одиночного. Цель поиска/подхода остаётся самым раненым (VFX на нём)
## ── ТАКТ ПО НЕСКОЛЬКИМ ЦЕЛЯМ ──────────────────────────────────────────────
## Накрывает max_heal_targets() самых раненых в ауре. Прежний «Благодатный»
## путь (весь отряд, каждому MONK_AOE_RATE доля) — его частный случай.
## «Абсолютное Целительство» (5b) восполняет запас ЦЕЛИКОМ: это не прибавка
## к объёму, а другое правило, и потому стоит отдельной веткой
## ── САМОХИЛ (1c): доля ОТДАННОГО исцеления возвращается монаху ────────────
## Считается от того, что реально зашло в чужие полоски, а не от заявленного
## объёма: целый боец не лечится, и платить монаху за несделанное незачем
func _self_heal(given: float) -> void:
	var k: float = self_heal_frac()
	if k <= 0.0 or given <= 0.0 or is_dead():
		return
	var was: float = current_health
	current_health = minf(max_health, current_health + given * k)
	if current_health > was:
		_soa_push_stats()

## Стенды: скольких накрыл последний AOE-такт
var aoe_touched: int = 0

## Обёртка для стендов (qa_sprint13 зовёт напрямую): один шаг автомата
func _heal_pulse() -> void:
	_monk_step()

## ── ПОДХОД — ЭТО ПРИКАЗ, А НЕ ВТОРАЯ МЕХАНИКА ХОДЬБЫ ──────────────────────
## Монах идёт к пациенту обычным command_move, тем же, каким его двигает игрок.
## Своего шага у него нет и быть не должно: любое движение мимо пакетного шага
## означало бы движение мимо проверки чужих тел, воды и границ карты.
##
## ПРИКАЗ ИГРОКА ВАЖНЕЕ. Пока он жив (player_order_active), монах идёт туда,
## куда послали, и лечит только тех, до кого дотянется по дороге
func _walk_to_patient(p: Unit, sid: int = 0) -> void:
	if player_order_active() or _panicked or retreating:
		return
	if _step_t > 0.0:
		return
	# ── ВСТАЁМ НА ГРАНИЦУ АУРЫ, СНАРУЖИ СТРОЯ (ТЗ 17.09.2026) ─────────────
	# Якорь — центр отряда пациента (у одиночки — он сам); точка стояния —
	# на stand_dist от якоря в нашу сторону. Прежние 0.7 × 3 м вели монаха
	# ВНУТРЬ строя, и там его толкала каждая шеренга
	var anchor: Vector3 = p.global_position
	if sid > 0:
		var c: Vector2 = GameManager.squad_centre_xz(sid)
		if c != Vector2.INF:
			anchor = Vector3(c.x, anchor.y, c.y)
	var to_me: Vector3 = global_position - anchor
	to_me.y = 0.0
	if to_me.length() < 0.01:
		to_me = Vector3(1.0, 0.0, 0.0)
	var stand: Vector3 = anchor + to_me.normalized() * stand_dist()
	# Точка не ушла дальше слабины — переиздавать нечего: каждый
	# command_move будит бойца и метит позу грязной (см. CLAUDE.md, «цена
	# костыля была не там, где её мерили»); слабина в метры, а не в метр —
	# это и были «перебежки по 1-5 м»
	if _step_to != Vector3.INF and _step_to.distance_to(stand) < _MCfg.MONK_MOVE_SLACK \
			and state == State.MOVING:
		return
	_step_t = _MCfg.MONK_STEP_SEC
	_step_to = stand
	approach_moves += 1
	if _Opt.cmd_meter: _Opt.cmd_src = "monk_approach"
	command_move(GameManager.land_target(stand))
	if _Opt.cmd_meter: _Opt.cmd_src = ""

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
## Подъём плоского овала над грунтом — как у колец выделения (UnitVisuals.RING_Y)
const AURA_LIFT_M := 0.035
## ИСТОРИЯ: сжатие по вертикали у прежнего вертикального квада; овал теперь
## даёт сам ракурс камеры над кругом, лежащим на земле
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
				# КРУГ (ТЗ 14.09.2026): квад лежит плашмя на земле, овал
				# даёт ракурс камеры. Ни креста, ни заливки — только контур
				var dy: float = float(y) + 0.5 - c
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
## Где стояла цель в момент привязки: сдвиг дальше VFX_MOVE_TOL — цель
## тронулась, даже если её тик не ведёт окно хода (замороженный стендом или
## переставленный боец) — ТЗ 18.09.2026, п. 1
var _heal_vfx_pos: Vector3 = Vector3.INF
const VFX_MOVE_TOL := 0.35
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
		var _tv: int = Time.get_ticks_usec() if _prof_on else 0
		_heal_vfx = _build_heal_vfx()
		if _prof_on: _Opt.prof_add("monk_build_vfx", Time.get_ticks_usec() - _tv)
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
				qa.size = Vector2(AURA_DIAM_M, AURA_DIAM_M)   # круг плашмя
	_heal_vfx_target = target
	_heal_vfx_pos = target.global_position
	# Окно — ДЛИНОЙ В ТАКТ ЛЕЧЕНИЯ (heal_tick_sec, 1.2 с), а не в прежний
	# MONK_HEAL_TICK 0.5: с коротким окном эффект гас между тактами и мигал
	_heal_vfx_left = heal_tick_sec() + HEAL_VFX_GRACE
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
	_stop_extra_vfx()

## ── VFX НА КАЖДОЙ ЦЕЛИ ТАКТА (ТЗ 16.09.2026) ───────────────────────────────
## Главный квад (_heal_vfx + аура) висит на самом раненом, как прежде; на
## остальных целях такта — квады из пула (до MONK_VFX_MAX − 1). Пул растёт
## лениво и не освобождается: узел дешевле пересоздания, а видимость гасится
var _extra_vfx: Array = []          # MeshInstance3D
var _extra_targets: Array = []      # Unit, по индексу квада
var _extra_left: float = 0.0

func _bind_heal_vfx_many(targets_in: Array) -> void:
	# Идущий монах и идущие цели эффекта не получают (ТЗ 18.09.2026, п. 1):
	# лечение при этом идёт — гаснет только картинка
	var targets: Array = []
	if _vfx_caster_still():
		for t in targets_in:
			if _vfx_target_still(t as Unit):
				targets.append(t)
	if targets.is_empty():
		_stop_heal_vfx()
		return
	_bind_heal_vfx(targets[0] as Unit)
	var n: int = mini(targets.size() - 1, _MCfg.MONK_VFX_MAX - 1)
	while _extra_vfx.size() < n:
		var q: MeshInstance3D = _build_heal_vfx()
		if q == null:
			break
		_extra_vfx.append(q)
	_extra_targets.clear()
	for i in range(_extra_vfx.size()):
		var q2: MeshInstance3D = _extra_vfx[i]
		if not is_instance_valid(q2):
			continue
		if i < n:
			var t: Unit = targets[i + 1] as Unit
			_extra_targets.append(t)
			q2.visible = true
			var p: Vector3 = t.draw_position()
			q2.global_position = Vector3(p.x, p.y + _vfx_mid, p.z)
		else:
			q2.visible = false
	_extra_left = heal_tick_sec() + HEAL_VFX_GRACE

func _stop_extra_vfx() -> void:
	_extra_targets.clear()
	_extra_left = 0.0
	for q in _extra_vfx:
		if is_instance_valid(q):
			(q as MeshInstance3D).visible = false

func _ride_extra_vfx() -> void:
	if _extra_targets.is_empty():
		return
	_extra_left -= get_physics_process_delta_time()
	if _extra_left <= 0.0 or not _vfx_caster_still():
		_stop_extra_vfx()
		return
	for i in range(_extra_targets.size()):
		var t = _extra_targets[i]
		var q: MeshInstance3D = _extra_vfx[i]
		if t == null or not is_instance_valid(t) or (t as Unit).is_dead() or not is_instance_valid(q) \
				or (t as Unit).garrisoned or not _vfx_target_still(t as Unit):
			if is_instance_valid(q):
				q.visible = false
			continue
		var p: Vector3 = (t as Unit).draw_position()
		q.global_position = Vector3(p.x, p.y + _vfx_mid, p.z)

## ── ЭФФЕКТ ЛЕЧЕНИЯ ТОЛЬКО У СТОЯЩИХ (ТЗ 18.09.2026, п. 1) ──────────────────
## Зелёный овал и лента лечения разрешены, пока и монах, и цель СТОЯТ: любой
## из них тронулся (приказ на движение, атака, марш отряда) — эффект гаснет
## тем же тиком. Раньше квад ЕХАЛ за ушедшей целью по её нарисованной точке
## и висел над ней до конца такта: на экране это читалось как «круги лечения
## остаются на земле / уезжают с отрядом». Признак — факт смещения
## (moved_recently, окно 200 мс, порог 0.6 м/с: расталкивание строя за
## движение не считается) либо состояние MOVING
func _vfx_caster_still() -> bool:
	return state != State.MOVING and not moved_recently() and _retreat_goal.x == INF

func _vfx_target_still(t: Unit) -> bool:
	if t == null:
		return false
	if t == self:
		return true
	return t.state != State.MOVING and not t.moved_recently()

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
		_heal_aura.global_position = Vector3(p.x, p.y + AURA_LIFT_M, p.z)

## Такт эффекта: едет за целью и гаснет, как только лечить эту цель перестали.
## Зовётся из tick_physics монаха — своего тика узел не заводит (то же правило,
## что у торчащих стрел и тел павших: декорация не платит нотификацией движка)
func _ride_heal_vfx() -> void:
	_ride_extra_vfx()
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
	# Шестая причина (ТЗ 18.09.2026, п. 1): монах или цель тронулись с места
	if not _vfx_caster_still() or not _vfx_target_still(t) \
			or (_heal_vfx_pos.x != INF and t.global_position.distance_to(_heal_vfx_pos) > VFX_MOVE_TOL):
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
	# ── ОВАЛ ЛЕЖИТ НА ЗЕМЛЕ (ТЗ 14.09.2026, п. 9) ─────────────────────────
	# Прежде это был ВЕРТИКАЛЬНЫЙ билборд высотой 0.45 м с центром на 0.22 м
	# над точкой земли: под камерой 45° он читался кольцом у пояса цели
	# (скриншот 9 — зелёный эллипс у спины копейщика). Теперь квад
	# КВАДРАТНЫЙ и положен плашмя (world_fixed, поворот −90° по X, подъём
	# RING_Y как у колец выделения), текстура — круг: овал даёт сам ракурс.
	# Глубина — по фрагменту: плоский квад на земле сортируется честно
	_heal_aura = _make_aura_node("HealAura")
	return mi

## ── ЗЕЛЁНЫХ КОЛЕЦ НА ЗЕМЛЕ НЕТ ВОВСЕ (ТЗ 19.09.2026, п. 1) ──────────────
## Овал под лечимым и круг канала багуются и остаются на земле — владелец
## вырезал их целиком. Узлы не заводятся: _heal_aura / _res_aura остаются
## null, а все читатели уже проверяют is_instance_valid. Остаётся ТОЛЬКО
## лента лечения над моделью (heal_vfx_node). Ручка — на случай возврата;
## текстура ауры (_aura_texture) и геометрия ниже оставлены как история
const GROUND_RINGS_ENABLED := false

## Круг на земле (лечения или канала): квадрат плашмя, текстура — круг
func _make_aura_node(nm: String) -> MeshInstance3D:
	if not GROUND_RINGS_ENABLED:
		return null
	var root: Node = GameManager.main.world_root() if GameManager.main != null else get_parent()
	if root == null:
		return null
	var aq := QuadMesh.new()
	aq.size = Vector2(AURA_DIAM_M, AURA_DIAM_M)
	var amat: ShaderMaterial = _BBUtilM.make_material(_aura_texture(), Color.WHITE, 0.5, AURA_FPS)
	amat.set_shader_parameter("frame_count", float(AURA_FRAMES))
	amat.set_shader_parameter("world_fixed", 1.0)
	amat.set_shader_parameter("ground_depth", 0.0)
	amat.set_shader_parameter("depth_push", 0.0)
	amat.set_shader_parameter("v_stretch", 1.0)
	amat.render_priority = 5
	aq.material = amat
	var ami := MeshInstance3D.new()
	ami.name = nm
	ami.mesh = aq
	ami.visible = false
	ami.rotation_degrees = Vector3(-90.0, 0.0, 0.0)   # плашмя
	root.add_child(ami)
	return ami

## СМЕРТЬ МОНАХА ГАСИТ ЭФФЕКТ В ТОТ ЖЕ КАДР, а не на выходе из дерева:
## освобождение узла отложено (queue_free), и между гибелью и уходом со сцены
## заклинание светилось бы над уже брошенным раненым
func _die() -> void:
	_stop_heal_vfx()
	_stop_res()
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
	if _res_aura != null and is_instance_valid(_res_aura):
		_res_aura.queue_free()
	_res_aura = null
	super._exit_tree()
