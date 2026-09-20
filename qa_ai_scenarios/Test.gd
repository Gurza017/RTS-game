extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_ai_scenarios — СЦЕНАРИЙ ГЛОБАЛЬНОГО ИИ КАРТЫ (13.09.2026)
## ═══════════════════════════════════════════════════════════════════════════
##   A  РЕЗЕРВ ОРДЫ — на 00:00 за лагерем стоят 14 отрядов заказанного состава
##      и ранга (2 конных I, 2 конных III, 2 конных IV-синих, 3 туш, 5 пехоты),
##      все спят; штурм лагеря их будит, после — возвращаются и засыпают;
##      вожак берёт конницу взаймы и возвращает
##   B  КРАСНЫЙ ИИ — ударная группа (3 копейщика + лучники) идёт на рудник у
##      брода; на марше копейщики широко (PHALANX_RANKS_MARCH шеренги), у брода
##      перестраиваются в глубокий строй (PHALANX_RANKS); лучники позади
##   C  ГНОЛЛЫ — не выходят на брод и не лезут к базе людей (зона: слева,
##      справа, снизу от пня); рабочего игрока в лесу у пня берут на охоту
##      (преследуют, кидают кости), рабочего со стороны базы — нет
##
## Запуск: <godot> --headless --path . res://qa_ai_scenarios/Test.tscn

const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")
const _AICfg := preload("res://scripts/ai_start_army_limit.gd")

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	var t := get_tree().create_timer(420.0)
	t.timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 420 с")
		_finish())

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	_log.append([t, ok])
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + d) if d != "" else ""])

func _finish() -> void:
	print("\n═════ ИТОГ qa_ai_scenarios: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _spawn(scene_path: String, faction: int, at: Vector3) -> Unit:
	var u: Unit = load(scene_path).instantiate()
	u.faction = faction
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	return u

func _squad(scene_path: String, uid: String, faction: int, n: int, at: Vector3) -> int:
	var sid: int = GameManager.new_squad(faction, uid)
	for k in range(n):
		var u: Unit = _spawn(scene_path, faction,
			at + Vector3(float(k % 6) * 0.7, 0.0, float(k / 6) * 0.7))
		GameManager.add_to_squad(sid, u)
	return sid

func _xz(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _run() -> void:
	Engine.max_fps = 0
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	# Пень за рекой в партии заморожен (ТЗ 19.09.2026); стенду нужен живой
	GameManager.call_deferred("thaw_lairs_now")
	for _i in range(10):
		await get_tree().process_frame
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.goblin_ai != null:
		main.goblin_ai.set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	GameManager.pop_limit_enabled = false
	await pframes(4)
	print("\n═════ qa_ai_scenarios ═════")
	await _a_reserve()
	await _b_red_ford()
	await _c_gnolls()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
# A. ДРЕМЛЮЩИЙ РЕЗЕРВ ОРДЫ
# ═════════════════════════════════════════════════════════════════════════════
func _a_reserve() -> void:
	print("\n═════ A. РЕЗЕРВ ОРДЫ ═════")
	var res = main.goblin_reserve
	verdict("A0 резерв заведён на старте партии", res != null and is_instance_valid(res))
	if res == null:
		return
	verdict("A1 в резерве ровно %d отрядов (по таблице RESERVE_SQUADS)" % _GobCfg.RESERVE_SQUADS.size(),
		res.squads.size() == _GobCfg.RESERVE_SQUADS.size(),
		"отрядов %d" % res.squads.size())
	# Состав по роду войск и рангу — ровно по заказу
	# 13.09.2026: туш в резерве один отряд (было три — «слишком много»)
	var want: Dictionary = {"goblin_rider|1": 2, "goblin_rider|3": 2, "goblin_rider|4": 2,
		"big_goblin|0": 1, "goblin_spearman|0": 5}
	var got: Dictionary = {}
	var lvl_ok := true
	for s in res.squads:
		var key: String = "%s|%d" % [String(s["unit"]), int(s["vet"])]
		got[key] = int(got.get(key, 0)) + 1
		var sid: int = int(s["sid"])
		var lvl: int = int(GameManager.squads[sid].get("level", 0)) if GameManager.squads.has(sid) else -1
		if lvl != int(s["vet"]):
			lvl_ok = false
	verdict("A2 состав: 2 конных I, 2 конных III, 2 конных IV, 3 туш, 5 пехоты",
		got == want, str(got))
	verdict("A2б ранг отрядов в реестре совпадает с заказанным", lvl_ok)
	var t1: Dictionary = _UCfg.veteran_banner_tier(1)
	var t4: Dictionary = _UCfg.veteran_banner_tier(4)
	var c1: Color = t1.get("cloth", Color.BLACK)
	var c4: Color = t4.get("cloth", Color.BLACK)
	verdict("A2в ранг I/III — красный вымпел, ранг IV — синий флаг",
		int(t1.get("shape", -1)) == _UCfg.BANNER_PENNANT and c1.r > c1.b
			and int(t4.get("shape", -1)) == _UCfg.BANNER_GUIDON and c4.b > c4.r)
	verdict("A3 все отряды резерва спят", res.asleep_count() == res.squads.size(),
		"спят %d" % res.asleep_count())
	# Спящий — без физтика и с битом сна
	var dormant_ok := true
	var n_units := 0
	for s in res.squads:
		for m in res._members(int(s["sid"])):
			n_units += 1
			if not bool((m as Unit).dormant) or bool((m as Unit).tick_on):
				dormant_ok = false
	verdict("A3б у бойцов резерва снят физтик и стоит признак сна", dormant_ok,
		"бойцов %d" % n_units)
	# За лагерем: дальше от центра карты, чем деревня
	var village: Vector3 = res.village
	var vd: float = Vector2(village.x, village.z).length()
	var behind := true
	for s in res.squads:
		var p: Vector3 = s["post"]
		if Vector2(p.x, p.z).length() <= vd + _GobCfg.VILLAGE_RADIUS:
			behind = false
	verdict("A4 резерв стоит ЗА лагерем (дальше деревни от центра карты)", behind)
	verdict("A5 резерв — особые отряды вожака (вне волн)",
		main.goblin_ai != null and main.goblin_ai.reserve_sids.size() == res.squads.size()
			and main.goblin_ai._is_special(int(res.squads[0]["sid"])))
	# ── ШТУРМ ЛАГЕРЯ БУДИТ РЕЗЕРВ ──────────────────────────────────────────
	var foes: Array = []
	for k in range(_GobCfg.RESERVE_WAKE_FOES + 2):
		foes.append(_spawn("res://scenes/units/Spearman.tscn", Constants.FACTION_PLAYER,
			village + Vector3(float(k) * 0.8 - 3.0, 0.0, 4.0)))
	# ТЗ 19.09.2026 (блок 3.3): по тревоге просыпается ПЕРВАЯ ВОЛНА
	# (RESERVE_WAVE_SQUADS отрядов), остальные — через RESERVE_WAVE_GAP_SEC
	var n_res: int = res.squads.size()
	var wave1: int = mini(_GobCfg.RESERVE_WAVE_SQUADS, n_res)
	var woke := false
	for _f in range(60 * 6):
		await get_tree().physics_frame
		if res.alarm and res.asleep_count() == n_res - wave1:
			woke = true
			break
	verdict("A6 штурм лагеря будит резерв — первую волну (%d из %d), остальные спят" % [wave1, n_res], woke,
		"тревога %s, спят %d" % [str(res.alarm), res.asleep_count()])
	# Проснувшиеся идут в бой: у бойцов есть цель или они в движении
	await pframes(30)
	var active := 0
	var total := 0
	for s in res.squads:
		if res.is_asleep(int(s["sid"])):
			continue
		for m in res._members(int(s["sid"])):
			total += 1
			var u := m as Unit
			if u.attack_target != null or u.state != Unit.State.IDLE:
				active += 1
	verdict("A6б проснувшаяся волна отбивает штурм (бойцы с целью или в движении)",
		active * 2 >= total, "%d из %d" % [active, total])
	# Угроза снята — резерв возвращается и засыпает
	for f in foes:
		if is_instance_valid(f):
			(f as Unit).take_damage(1e12)
	await pframes(6)
	var slept := false
	for _f in range(60 * 90):
		await get_tree().physics_frame
		if not res.alarm and res.asleep_count() >= 12:
			slept = true
			break
	verdict("A7 после штурма резерв возвращается на посты и снова спит", slept,
		"тревога %s, спят %d из %d" % [str(res.alarm), res.asleep_count(), res.squads.size()])
	# ── КОННИЦА ВЗАЙМЫ ─────────────────────────────────────────────────────
	var lent: Array = res.borrow_cavalry(2)
	var all_riders := true
	for sid in lent:
		if String(GameManager.squads[int(sid)].get("type", "")) != "goblin_rider" or res.is_asleep(int(sid)):
			all_riders = false
	verdict("A8 вожак берёт взаймы два конных отряда, они разбужены",
		lent.size() == 2 and all_riders and res.lent.size() == 2, "взято %d" % lent.size())
	var over: Array = res.borrow_cavalry(2)
	verdict("A8б больше RESERVE_LEND_MAX сразу не даёт", over.is_empty())
	for sid in lent:
		res.return_squad(int(sid))
	var back := false
	for _f in range(60 * 40):
		await get_tree().physics_frame
		if res.lent.is_empty() and res.is_asleep(int(lent[0])) and res.is_asleep(int(lent[1])):
			back = true
			break
	verdict("A9 возвращённая конница доходит до поста и засыпает", back,
		"спят %d" % res.asleep_count())

# ═════════════════════════════════════════════════════════════════════════════
# B. КРАСНЫЙ ИИ: ГРУППА НА БРОД И ГЛУБОКИЙ СТРОЙ
# ═════════════════════════════════════════════════════════════════════════════
func _max_row(sid: int) -> int:
	var mx := 0
	for m in GameManager.squad_members(sid):
		mx = maxi(mx, int((m as Unit).formation_row))
	return mx

func _b_red_ford() -> void:
	print("\n═════ B. КРАСНЫЙ ИИ У БРОДА ═════")
	var ai = main.enemy_ai
	var ford: Vector3 = main.ford_point()
	var mine: Node3D = ai.red.ford_mine()
	# Разворот 13.09.2026: рудника на броде НЕТ, группа держит саму переправу
	verdict("B0 на броде рудника нет (штатных ничейных — два, на плато)",
		mine == null, "рудник у брода %s" % ("есть" if mine != null else "нет"))
	verdict("B0б точка сбора обоих ИИ — сам брод",
		_xz(ai._rally_point(), ford) < 1.0, "сбор %s, брод %s" % [str(ai._rally_point()), str(ford)])
	# Крепость ИИ и четыре отряда далеко от брода, со стороны ИИ
	var castle := Castle.new()
	castle.faction = Constants.FACTION_ENEMY
	main.world_add(castle)
	var cp: Vector3 = main.ENEMY_BASE_ANCHOR
	castle.global_position = Vector3(cp.x, GameManager.get_terrain_height(cp.x, cp.z), cp.z)
	await pframes(4)
	var dir: Vector3 = (cp - ford)
	dir.y = 0.0
	dir = dir.normalized()
	var far: Vector3 = ford + dir * 110.0
	main._clear_area_of_resources(far, 40.0)
	# УСТАВНЫЕ РАЗМЕРЫ: ИИ собирает записи по роду войск до полного штата, и
	# неполные отряды он слил бы в одну запись (qa: 3×24 копейщиков → 2 записи)
	var sids: Array = []
	var nsp: int = _UCfg.squad_size("spearman")
	for i in range(3):
		sids.append(_squad("res://scenes/units/Spearman.tscn", "spearman",
			Constants.FACTION_ENEMY, nsp, far + Vector3(float(i - 1) * 12.0, 0.0, 0.0)))
	var asid: int = _squad("res://scenes/units/Archer.tscn", "archer",
		Constants.FACTION_ENEMY, _UCfg.squad_size("archer"), far + dir * 10.0)
	# Группа на брод формируется только у НАБРАННОЙ армии (FORD_MIN_SQUADS):
	# добираем мечниками до порога, они уйдут на рудник и в рейд
	var extra: Array = []
	for i in range(maxi(_AICfg.FORD_MIN_SQUADS - 4, 0)):
		extra.append(_squad("res://scenes/units/Warrior.tscn", "warrior",
			Constants.FACTION_ENEMY, _UCfg.squad_size("warrior"), far + dir * (20.0 + float(i) * 8.0)))
	await pframes(4)
	ai.set_process(false)
	ai._peace_over = true
	ai._home_pos = castle.global_position
	ai.clock = 700.0
	ai._regroup()
	verdict("B1 ИИ видит 3 отряда копейщиков и 1 лучников",
		ai.squad_count("spearman") == 3 and ai.squad_count("archer") == 1
			and ai.squads.size() >= _AICfg.FORD_MIN_SQUADS,
		"копейщиков %d, лучников %d" % [ai.squad_count("spearman"), ai.squad_count("archer")])
	ai._refresh_target_cache()
	ai._command_squads_defensive(castle)
	for _i in range(4):
		ai._drain_orders()
		await pframes(2)
	verdict("B2 ударная группа на брод собрана: 3 копейщика + 1 лучники",
		ai.red.ford_group.size() == 4, "в группе %d" % ai.red.ford_group.size())
	# Цели группы — у рудника: копейщики впереди (ближе к броду), лучники сзади
	var sp_d := 0.0
	var ar_d := 0.0
	var all_field := true
	for s in ai.squads:
		var sq: Dictionary = s
		if String(sq["type"]) == "warrior":
			continue                      # мечники — рудник и рейд, не группа
		if String(sq["role"]) != ai.ROLE_FIELD:
			all_field = false
			continue
		# Глубина по оси «брод → база ИИ»: кто дальше от брода, тот сзади
		var d: float = ((sq["target"] as Vector3) - ford).dot(dir)
		if String(sq["type"]) == "archer":
			ar_d = d
		else:
			sp_d = maxf(sp_d, d)
	verdict("B3 все четыре отряда — полевая роль с целью у брода",
		all_field and sp_d < 30.0 and ar_d < 40.0,
		"копейщики до %.1f м, лучники %.1f м от брода по оси" % [sp_d, ar_d])
	verdict("B3б лучники держатся ПОЗАДИ копейщиков (дистанция прикрытия)",
		ar_d > sp_d + 2.0, "лучники %.1f, копейщики %.1f" % [ar_d, sp_d])
	# На марше (далеко от брода) — широкий строй
	var wide_ok := true
	var rows_txt := ""
	for sid in sids:
		var sq: Dictionary = {}
		for s in ai.squads:
			if ai._sid_of(s) == sid:
				sq = s
		var rn: int = int(sq.get("ranks_now", 0))
		var mr: int = _max_row(sid)
		rows_txt += "[ranks %d, max row %d] " % [rn, mr]
		if rn != _AICfg.PHALANX_RANKS_MARCH or mr != _AICfg.PHALANX_RANKS_MARCH - 1:
			wide_ok = false
	verdict("B4 на марше копейщики идут ШИРОКО (%d шеренги)" % _AICfg.PHALANX_RANKS_MARCH,
		wide_ok, rows_txt)
	# Подошли к броду — переставляем группу на FORD_DEEP_RANGE − 10 и думаем снова
	var near: Vector3 = ford + dir * (_AICfg.FORD_DEEP_RANGE - 14.0)
	var right := Vector3(-dir.z, 0.0, dir.x)
	for sid in sids:
		var k := 0
		for m in GameManager.squad_members(sid):
			var u := m as Unit
			# Отряды бок о бок ПОПЕРЁК оси, тесно: все три обязаны оказаться
			# внутри FORD_DEEP_RANGE, иначе третий останется «на марше»
			var p: Vector3 = near + right * (float(sids.find(sid) - 1) * 7.0) 				+ Vector3(float(k % 6) * 0.7, 0.0, float(k / 6) * 0.7)
			u.global_position = Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)
			u.sync_row()
			k += 1
	await pframes(2)
	var sw0: int = ai.red.deep_switches
	ai._refresh_target_cache()
	ai._command_squads_defensive(castle)
	for _i in range(4):
		ai._drain_orders()
		await pframes(2)
	var deep_ok := true
	rows_txt = ""
	for sid in sids:
		var sq: Dictionary = {}
		for s in ai.squads:
			if ai._sid_of(s) == sid:
				sq = s
		var rn: int = int(sq.get("ranks_now", 0))
		var mr: int = _max_row(sid)
		rows_txt += "[ranks %d, max row %d] " % [rn, mr]
		if rn != _AICfg.PHALANX_RANKS or mr != _AICfg.PHALANX_RANKS - 1:
			deep_ok = false
	verdict("B5 у брода копейщики перестроились в ГЛУБОКИЙ строй (%d шеренги)" % _AICfg.PHALANX_RANKS,
		deep_ok, rows_txt)
	verdict("B5б перестроение — событие: счётчик смен глубины вырос на 3",
		ai.red.deep_switches - sw0 == 3, "смен %d" % (ai.red.deep_switches - sw0))
	# Генеральный штурм запрещён до 30-й минуты
	verdict("B6 штурм базы игрока не раньше 30-й минуты (оба ИИ)",
		_AICfg.AI_ASSAULT_AT_SEC >= 1800.0 and _GobCfg.ASSAULT_EARLIEST_SEC >= 1800.0
			and not ai._assault_time(),
		"люди %.0f с, орда %.0f с" % [_AICfg.AI_ASSAULT_AT_SEC, _GobCfg.ASSAULT_EARLIEST_SEC])
	verdict("B7 разведка 2:1: каждый третий рейд — чистая разведка, остальные — боем",
		not ai.red.recon_mode(1) and not ai.red.recon_mode(2) and ai.red.recon_mode(3)
			and not ai.red.recon_mode(4) and ai.red.recon_mode(6))
	# Прибираемся
	for sid in sids + [asid] + extra:
		for m in GameManager.squad_members(sid):
			(m as Unit).take_damage(1e12)
	castle.take_damage(1e12)
	await pframes(6)
	ai.squads.clear()

# ═════════════════════════════════════════════════════════════════════════════
# C. ГНОЛЛЫ: ЗОНА И ОХОТА
# ═════════════════════════════════════════════════════════════════════════════
func _pack(lair) -> Array:
	var out: Array = []
	for g in lair.gnolls:
		if is_instance_valid(g) and not (g as Unit).is_dead() and not bool(g.get("hidden")):
			out.append(g)
	return out

func _c_gnolls() -> void:
	print("\n═════ C. ГНОЛЛЫ ═════")
	var gai = main.gnoll_ai
	var lair = GameManager.troll_lair
	verdict("C0 контроллер гноллов и пень на месте",
		gai != null and lair != null and is_instance_valid(lair))
	if gai == null or lair == null:
		return
	var lp: Vector3 = lair.global_position
	var bd: Vector3 = gai.base_dir(lair)
	var ford: Vector3 = main.ford_point()
	print("  пень %s, к базе %s, брод %s" % [str(lp), str(bd), str(ford)])
	verdict("C1 брод — вне зоны гноллов, точка зоны никогда не на броде",
		not gai.in_zone(lair, ford) and not gai.in_ford_band(gai.clamp_to_zone(lair, ford))
			and _xz(gai.clamp_to_zone(lair, ford), ford) > _GobCfg.GNOLL_FORD_PAD)
	var toward: Vector3 = lp + bd * 30.0
	var side: Vector3 = lp + Vector3(-bd.z, 0.0, bd.x) * 30.0
	var below: Vector3 = lp - bd * 30.0
	verdict("C2 зона: к базе людей нельзя, вбок и вниз от пня — можно",
		not gai.in_zone(lair, toward) and gai.in_zone(lair, side) and gai.in_zone(lair, below))
	var pack: Array = _pack(lair)
	verdict("C3 у пня есть стая", pack.size() >= 6, "гноллов %d" % pack.size())
	if pack.is_empty():
		return
	# Заморозим троллей и стадо — чтобы стая не отвлекалась
	for t in lair.trolls:
		if is_instance_valid(t):
			(t as Unit).set_tick(false)
	# Гнолл ОКАЗАЛСЯ за радиусом зоны (в сторону брода) — зона возвращает его.
	# Ставим телепортом: пешком за 70 м он идёт полминуты, а к базе людей
	# дорогу ещё и закрывает гора — важен сам возврат, а не путь туда
	var g0: Unit = pack[0]
	var r0: int = int(g0.zone_returns)
	var out_pt: Vector3 = lp + (ford - lp).normalized() * (_GobCfg.GNOLL_ZONE_RADIUS + 12.0)
	out_pt = GameManager.land_target(out_pt)
	g0.global_position = Vector3(out_pt.x, GameManager.get_terrain_height(out_pt.x, out_pt.z), out_pt.z)
	g0.sync_row()
	var back0 := false
	# У пня между базами (14.09.2026) зона к броду — узкий клин (две
	# полуплоскости), и от точки выброса до зоны гноллу идти ~50 м: ждём дольше
	for _f in range(60 * 40):
		await get_tree().physics_frame
		if int(g0.zone_returns) > r0 and gai.in_zone(lair, g0.global_position, 3.0):
			back0 = true
			break
	verdict("C4 гнолл, ушедший к броду за радиус зоны, возвращается в зону",
		back0, "возвратов +%d, до пня %.1f м" % [int(g0.zone_returns) - r0, _xz(g0.global_position, lp)])
	# Гнолл оказался СО СТОРОНЫ БАЗЫ ЛЮДЕЙ — тоже назад
	var g1: Unit = pack[1]
	var r1: int = int(g1.zone_returns)
	var up_pt: Vector3 = GameManager.land_target(lp + bd * 22.0)
	g1.global_position = Vector3(up_pt.x, GameManager.get_terrain_height(up_pt.x, up_pt.z), up_pt.z)
	g1.sync_row()
	var back1 := false
	for _f in range(60 * 14):
		await get_tree().physics_frame
		var d: Vector3 = g1.global_position - lp
		if int(g1.zone_returns) > r1 and d.dot(bd) <= _GobCfg.GNOLL_ZONE_TOWARD_BASE + 3.0:
			back1 = true
			break
	verdict("C5 гнолл со стороны базы людей уходит назад (вверх не лезет)",
		back1, "возвратов +%d, продвижение к базе %.1f м" % [
			int(g1.zone_returns) - r1, (g1.global_position - lp).dot(bd)])
	# ── ОХОТА НА РАБОЧЕГО В ЛЕСУ ─────────────────────────────────────────────
	var wp: Vector3 = lp + Vector3(-bd.z, 0.0, bd.x) * 26.0
	var worker: Unit = _spawn("res://scenes/units/Worker.tscn", Constants.FACTION_PLAYER, wp)
	worker.max_health = 100000.0
	worker.current_health = 100000.0
	worker._soa_push_stats()
	var hp0: float = worker.current_health
	var bones0 := 0
	for g in pack:
		bones0 += int(g.bones_thrown)
	var h0: int = int(gai.hunts_issued)
	var hunters := 0
	for _f in range(60 * 12):
		await get_tree().physics_frame
		hunters = 0
		for g in pack:
			if is_instance_valid(g) and (g as Unit).attack_target == worker and bool(g.get("hunting")):
				hunters += 1
		if hunters >= 1 and int(gai.hunts_issued) > h0:
			break
	verdict("C6 рабочий в лесу у пня берётся на охоту (цель с преследованием)",
		hunters >= 1 and int(gai.hunts_issued) > h0, "охотников %d" % hunters)
	verdict("C6б на добычу уходит не больше GNOLL_HUNTERS_PER_PREY",
		hunters <= _GobCfg.GNOLL_HUNTERS_PER_PREY, "охотников %d" % hunters)
	var bones1 := 0
	var hit := false
	for _f in range(60 * 20):
		await get_tree().physics_frame
		bones1 = 0
		for g in pack:
			if is_instance_valid(g):
				bones1 += int(g.bones_thrown)
		if bones1 > bones0 and worker.current_health < hp0:
			hit = true
			break
	verdict("C7 охотники закидывают рабочего костями и наносят урон", hit,
		"костей +%d, запас %.0f → %.0f" % [bones1 - bones0, hp0, worker.current_health])
	# Рабочий СО СТОРОНЫ БАЗЫ (вверх) — не добыча
	var w2: Unit = _spawn("res://scenes/units/Worker.tscn", Constants.FACTION_PLAYER, lp + bd * 30.0)
	worker.take_damage(1e12)
	await pframes(60 * 4)
	var hunt2 := 0
	for g in pack:
		if is_instance_valid(g) and (g as Unit).attack_target == w2:
			hunt2 += 1
	verdict("C8 рабочий со стороны базы людей на охоту не берётся", hunt2 == 0,
		"охотников %d" % hunt2)
	w2.take_damage(1e12)
	await pframes(4)
