extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_home_guard — СТАРТОВАЯ ОБОРОНА КРЕПОСТИ КРАСНОГО ИИ (15.09.2026)
## ═══════════════════════════════════════════════════════════════════════════
##   A  РАССТАНОВКА: башни по таблице HOME_TOWERS (число, дистанции), в каждой
##      сидит отряд лучников (на настиле), на крыше замка — свой отряд лучников;
##      охрана по таблице HOME_GUARD_SQUADS (2 мечника IV — синий гвидон,
##      3 копейщика II — красный вымпел), стоит ЗА замком, копейщики в обороне
##   B  СОН: вся охрана спит (dormant, тик снят); чужой отряд вне зоны охраны
##      её не будит и не сдвигает; EnemyAI её не подбирает в свои отряды
##   C  ПРОБУЖДЕНИЕ: прорыв в зону — охрана просыпается и идёт в бой; после
##      ухода угрозы возвращается на посты и засыпает снова
##   D  УДАР ПО ЗАМКУ будит охрану даже без чужих в зоне; признак home_guard
##      уезжает в слепок
##
## Запуск: <godot> --headless --path . res://qa_home_guard/Test.tscn

const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _AICfg := preload("res://scripts/ai_start_army_limit.gd")
const _SaveLoad := preload("res://scripts/SaveLoadManager.gd")
const _TowerS := preload("res://scripts/Tower.gd")

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
	print("\n═════ ИТОГ qa_home_guard: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _xz(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _enemy_castle() -> Castle:
	for b in get_tree().get_nodes_in_group("enemy_buildings"):
		if is_instance_valid(b) and b is Castle and (b as Castle).is_stronghold():
			return b as Castle
	return null

func _enemy_towers() -> Array:
	var out: Array = []
	for b in get_tree().get_nodes_in_group("enemy_buildings"):
		if is_instance_valid(b) and b is _TowerS and not (b as Building).is_dead():
			out.append(b)
	return out

func _members(sid: int) -> Array:
	var rec: Variant = GameManager.squads.get(sid)
	if rec == null:
		return []
	var out: Array = []
	for m in (rec as Dictionary).get("members", []):
		if is_instance_valid(m) and not (m as Unit).is_dead():
			out.append(m)
	return out

func _centroid(sid: int) -> Vector3:
	var ms: Array = _members(sid)
	return GameManager._centroid_of(ms) if not ms.is_empty() else Vector3.INF

func _spawn_player_squad(uid: String, n: int, at: Vector3) -> int:
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, uid)
	for k in range(n):
		var u: Unit = Building.PRELOAD_SCENES[uid].instantiate()
		u.faction = Constants.FACTION_PLAYER
		main.world_add(u)
		var p: Vector3 = at + Vector3(float(k % 6) * 0.7, 0.0, float(k / 6) * 0.7)
		u.global_position = Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)
		u.sync_row()
		u.post_pos = u.global_position
		GameManager.add_to_squad(sid, u)
	return sid

func _kill_squad(sid: int) -> void:
	for m in _members(sid):
		(m as Unit).take_damage(1.0e9)

func _run() -> void:
	Engine.max_fps = 0
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	for _i in range(10):
		await get_tree().process_frame
	# Орда и гноллы стенду не нужны, а красный ИИ оставляем ЖИВЫМ: блок B
	# стережёт, что его такт не подбирает охрану
	if main.goblin_ai != null:
		main.goblin_ai.set_process(false)
	if main.get("gnoll_ai") != null:
		main.gnoll_ai.set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	GameManager.pop_limit_enabled = false
	await pframes(4)
	print("\n═════ qa_home_guard ═════")
	await _a_layout()
	await _b_sleep()
	await _c_wake()
	await _d_castle_hit_and_save()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
# A. РАССТАНОВКА
# ═════════════════════════════════════════════════════════════════════════════
func _a_layout() -> void:
	print("\n═════ A. РАССТАНОВКА ═════")
	var keep: Castle = _enemy_castle()
	verdict("A0 крепость красного ИИ стоит", keep != null)
	if keep == null:
		return
	var guard = main.enemy_guard
	verdict("A0б охрана крепости заведена (HomeGuard)", guard != null and is_instance_valid(guard))
	var towers: Array = _enemy_towers()
	var want_n: int = _AICfg.HOME_TOWERS.size()
	verdict("A1 башен вокруг крепости ровно %d" % want_n, towers.size() == want_n,
		"башен %d" % towers.size())
	# Дистанции — по таблице: у каждой строки таблицы нашлась башня в ±1.5 м
	var dist_ok := true
	var dists := ""
	for row in _AICfg.HOME_TOWERS:
		var want: float = float((row as Dictionary)["dist"])
		var found := false
		for t in towers:
			var d: float = _xz((t as Node3D).global_position, keep.global_position)
			if absf(d - want) <= 1.5:
				found = true
				break
		dist_ok = dist_ok and found
	for t in towers:
		dists += "%.1f " % _xz((t as Node3D).global_position, keep.global_position)
	verdict("A2 дистанции башен от центра замка — по таблице (±1.5 м)", dist_ok, "м: " + dists)
	# В каждой башне — отряд лучников, и он на настиле
	var garr_ok := towers.size() > 0
	var roof_men := ""
	for t in towers:
		var c := t as Castle
		var n_sq: int = c.garrison.size()
		var typ: String = String((c.garrison[0] as Dictionary).get("type", "")) if n_sq > 0 else ""
		var men: int = c.garrison_men() if c.has_method("garrison_men") else 0
		roof_men += "%d/%s/%d " % [n_sq, typ, men]
		if n_sq != _AICfg.HOME_TOWER_ARCHERS or typ != "archer" or men < 1:
			garr_ok = false
	verdict("A3 в КАЖДОЙ башне %d отряд лучников, лучники на настиле" % _AICfg.HOME_TOWER_ARCHERS,
		garr_ok, "отрядов/тип/на настиле: " + roof_men)
	# Крыша крепости
	var roof_sq: int = keep._roof.squads() if keep._roof != null else 0
	var roof_n: int = keep._roof.men() if keep._roof != null else 0
	verdict("A4 на крыше крепости %d отряд лучников" % _AICfg.HOME_CASTLE_ARCHERS,
		roof_sq == _AICfg.HOME_CASTLE_ARCHERS and roof_n == _UCfg.squad_size("archer"),
		"отрядов %d, стрелков %d" % [roof_sq, roof_n])
	if guard == null:
		return
	# Охрана: состав и ранг по таблице
	var want: Dictionary = {}
	for row in _AICfg.home_guard_squads():
		var k: String = "%s|%d" % [String((row as Dictionary)["unit"]), int((row as Dictionary)["vet"])]
		want[k] = int(want.get(k, 0)) + 1
	var got: Dictionary = {}
	var tiers_ok := true
	for s in guard.squads:
		var sid: int = int(s["sid"])
		var lvl: int = int(GameManager.squads[sid].get("level", 0))
		var k: String = "%s|%d" % [GameManager.squad_type(sid), lvl]
		got[k] = int(got.get(k, 0)) + 1
		var tier: Dictionary = _UCfg.veteran_banner_tier(lvl)
		if lvl == 4 and not tier.is_empty() and int(tier.get("shape", -1)) != _UCfg.BANNER_GUIDON:
			tiers_ok = false
		if lvl == 2 and not tier.is_empty() and int(tier.get("shape", -1)) != _UCfg.BANNER_PENNANT:
			tiers_ok = false
	verdict("A5 охрана: %d отрядов, состав и ранг по таблице" % _AICfg.home_guard_squads().size(),
		guard.squads.size() == _AICfg.home_guard_squads().size() and got == want,
		"есть %s, надо %s" % [str(got), str(want)])
	verdict("A5б ранг IV — синий гвидон, ранг II — красный вымпел (VET_BANNER_TIERS)", tiers_ok)
	# Все отряды укомплектованы и с наградами (picks применены — pending 0)
	var full_ok := true
	for s in guard.squads:
		var sid: int = int(s["sid"])
		if _members(sid).size() != _UCfg.squad_size(GameManager.squad_type(sid)) \
				or int(GameManager.squads[sid].get("pending", 0)) != 0:
			full_ok = false
	verdict("A6 отряды охраны полные, награды за ранг разобраны", full_ok)
	# За замком: проекция центра на ось «замок → центр карты» отрицательна
	var front: Vector3 = keep.front_dir()
	var behind_ok := true
	var far_ok := true
	var projs := ""
	for s in guard.squads:
		var c: Vector3 = _centroid(int(s["sid"]))
		var off: Vector3 = c - keep.global_position
		var pr: float = off.x * front.x + off.z * front.z
		projs += "%.1f " % pr
		if pr > -4.0:
			behind_ok = false
		if _xz(c, keep.global_position) > 40.0:
			far_ok = false
	verdict("A7 охрана стоит В ГЛУБИНЕ базы: за замком, не дальше 40 м", behind_ok and far_ok,
		"проекции на фронт: " + projs)
	var stance_ok := true
	for s in guard.squads:
		var sid: int = int(s["sid"])
		if GameManager.squad_type(sid) != "spearman":
			continue
		for m in _members(sid):
			if String((m as Unit).stance) != "defense":
				stance_ok = false
	verdict("A8 копейщики охраны в стойке «оборона»", stance_ok)

# ═════════════════════════════════════════════════════════════════════════════
# B. СОН
# ═════════════════════════════════════════════════════════════════════════════
var _intruder_sid: int = 0

func _b_sleep() -> void:
	print("\n═════ B. СОН ═════")
	var guard = main.enemy_guard
	var keep: Castle = _enemy_castle()
	if guard == null or keep == null:
		return
	var n_sq: int = guard.squads.size()
	verdict("B1 вся охрана спит (asleep_count = отрядов)", guard.asleep_count() == n_sq,
		"спит %d из %d" % [guard.asleep_count(), n_sq])
	var dormant_ok := true
	for s in guard.squads:
		for m in _members(int(s["sid"])):
			var u := m as Unit
			if not u.dormant or u.tick_on:
				dormant_ok = false
	verdict("B2 у спящих снят физтик и стоит dormant", dormant_ok)
	# Раздражитель ВНЕ зоны охраны: чужой отряд в 1.6 зоны от замка
	var front: Vector3 = keep.front_dir()
	var far: Vector3 = keep.global_position + front * (_AICfg.HOME_GUARD_ZONE * 1.6)
	_intruder_sid = _spawn_player_squad("spearman", 12, far)
	var before: Array = []
	for s in guard.squads:
		before.append(_centroid(int(s["sid"])))
	await pframes(int(_AICfg.HOME_GUARD_TICK_SEC * 60.0) * 4 + 10)
	var moved := 0.0
	for i in range(guard.squads.size()):
		var c: Vector3 = _centroid(int(guard.squads[i]["sid"]))
		if c.x != INF and before[i].x != INF:
			moved = maxf(moved, _xz(c, before[i]))
	verdict("B3 чужие в %.0f м (вне зоны %.0f) охрану не будят" % [
			_AICfg.HOME_GUARD_ZONE * 1.6, _AICfg.HOME_GUARD_ZONE],
		guard.asleep_count() == n_sq and not guard.alarm, "спит %d, тревога %s" % [
			guard.asleep_count(), str(guard.alarm)])
	verdict("B4 …и не сдвигают ни на шаг", moved < 0.05, "сдвиг центра %.3f м" % moved)
	# EnemyAI не подбирает охрану в свои отряды
	var ai = main.enemy_ai
	if ai != null:
		ai._regroup()
		var stolen := 0
		var guard_ids: Dictionary = {}
		for s in guard.squads:
			for m in _members(int(s["sid"])):
				guard_ids[(m as Node).get_instance_id()] = true
		for sq in ai.squads:
			for m in (sq as Dictionary)["members"]:
				if is_instance_valid(m) and guard_ids.has((m as Node).get_instance_id()):
					stolen += 1
		verdict("B5 EnemyAI._regroup не берёт охрану в армию", stolen == 0, "забрал %d бойцов" % stolen)

# ═════════════════════════════════════════════════════════════════════════════
# C. ПРОБУЖДЕНИЕ И ВОЗВРАТ
# ═════════════════════════════════════════════════════════════════════════════
func _c_wake() -> void:
	print("\n═════ C. ПРОБУЖДЕНИЕ ═════")
	var guard = main.enemy_guard
	var keep: Castle = _enemy_castle()
	if guard == null or keep == null:
		return
	var n_sq: int = guard.squads.size()
	# Прорыв: тот же чужой отряд переставляется внутрь зоны (телепорт стенда)
	var front: Vector3 = keep.front_dir()
	var inside: Vector3 = keep.global_position + front * (_AICfg.HOME_GUARD_ZONE * 0.7)
	var k := 0
	for m in _members(_intruder_sid):
		var u := m as Unit
		var p: Vector3 = inside + Vector3(float(k % 6) * 0.7, 0.0, float(k / 6) * 0.7)
		u.global_position = Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)
		u.sync_row()
		u.post_pos = u.global_position
		# Стоять на месте: иначе он сам полезет к замку и смажет замер
		u.set_stance("defense")
		k += 1
	await pframes(int(_AICfg.HOME_GUARD_TICK_SEC * 60.0) * 2 + 6)
	# ТЗ 19.09.2026 (блок 3.3): по тревоге просыпается ПЕРВАЯ ВОЛНА
	# (HOME_GUARD_WAVE_SQUADS отрядов), остальные — через HOME_GUARD_WAVE_GAP_SEC
	var n_guard: int = guard.squads.size()
	var wave1: int = mini(_AICfg.HOME_GUARD_WAVE_SQUADS, n_guard)
	verdict("C1 прорыв в зону охраны — тревога, проснулась первая волна (%d из %d)" % [wave1, n_guard],
		guard.alarm and guard.asleep_count() == n_guard - wave1,
		"тревога %s, спит %d" % [str(guard.alarm), guard.asleep_count()])
	var awake_ok := true
	var targeting := 0
	var total := 0
	for s in guard.squads:
		if guard.is_asleep(int(s["sid"])):
			continue
		for m in _members(int(s["sid"])):
			var u := m as Unit
			total += 1
			if u.dormant or not u.tick_on:
				awake_ok = false
			if u.attack_target != null or u.state == Unit.State.ATTACKING:
				targeting += 1
	verdict("C2 проснувшиеся тикают и получили цель (атака)", awake_ok and targeting >= total / 2,
		"с целью %d из %d" % [targeting, total])
	# Вторая волна — по истечении срока тревоги (часы двигаем сами)
	guard.wave_clock = _AICfg.HOME_GUARD_WAVE_GAP_SEC
	await pframes(int(_AICfg.HOME_GUARD_TICK_SEC * 60.0) * 2 + 6)
	verdict("C2б через %.0f с тревоги — вторая волна (проснулись все %d)" % [_AICfg.HOME_GUARD_WAVE_GAP_SEC, n_guard],
		guard.asleep_count() == maxi(n_guard - 2 * wave1, 0), "спит %d" % guard.asleep_count())
	# Охрана реально пошла на прорыв: центр хотя бы одного отряда сдвинулся к чужим
	var c0: Array = []
	for s in guard.squads:
		c0.append(_centroid(int(s["sid"])))
	await pframes(180)
	var closer := 0
	for i in range(guard.squads.size()):
		var c1: Vector3 = _centroid(int(guard.squads[i]["sid"]))
		if c1.x != INF and c0[i].x != INF and _xz(c1, inside) < _xz(c0[i], inside) - 1.0:
			closer += 1
	verdict("C3 охрана идёт на противника (центры отрядов приблизились)", closer >= 3,
		"приблизилось отрядов %d из %d" % [closer, n_sq])
	# Угроза снята: чужие убиты — через CALM_SEC охрана идёт домой, у постов засыпает
	_kill_squad(_intruder_sid)
	await pframes(6)
	var calm_frames: int = int(_AICfg.HOME_GUARD_CALM_SEC * 60.0) + 60
	await pframes(calm_frames)
	verdict("C4 угрозы нет %.0f с — тревога снята" % _AICfg.HOME_GUARD_CALM_SEC, not guard.alarm,
		"тревога %s" % str(guard.alarm))
	# Домой идут пешком: ждём СВОЙСТВО (все уснули), потолок в физкадрах
	var slept := false
	for _w in range(60):
		await pframes(60)
		if guard.asleep_count() == guard.squads.size():
			slept = true
			break
	var at_post := true
	var dd := ""
	for s in guard.squads:
		var c: Vector3 = _centroid(int(s["sid"]))
		var d: float = _xz(c, s["post"]) if c.x != INF else 999.0
		dd += "%.1f " % d
		if d > _AICfg.HOME_GUARD_HOME_R + 1.0:
			at_post = false
	verdict("C5 охрана вернулась на посты (в HOME_R от точки) и уснула снова", slept and at_post,
		"до постов, м: " + dd + "спит %d/%d" % [guard.asleep_count(), guard.squads.size()])
	verdict("C6 отрядов охраны не убыло (чужие 12 копейщиков — не угроза для 210)",
		guard.squads.size() == n_sq, "%d из %d" % [guard.squads.size(), n_sq])

# ═════════════════════════════════════════════════════════════════════════════
# D. УДАР ПО ЗАМКУ И СЛЕПОК
# ═════════════════════════════════════════════════════════════════════════════
func _d_castle_hit_and_save() -> void:
	print("\n═════ D. УДАР ПО ЗАМКУ, СЛЕПОК ═════")
	var guard = main.enemy_guard
	var keep: Castle = _enemy_castle()
	if guard == null or keep == null:
		return
	# Обидчик — далеко за зоной, но в радиусе поиска цели (ZONE + 20)
	var front: Vector3 = keep.front_dir()
	var far: Vector3 = keep.global_position + front * (_AICfg.HOME_GUARD_ZONE + 12.0)
	var sid_far: int = _spawn_player_squad("archer", 6, far)
	var shooter: Unit = _members(sid_far)[0]
	await pframes(int(_AICfg.HOME_GUARD_TICK_SEC * 60.0) + 4)
	verdict("D0 стрелок за зоной охрану не будит", guard.asleep_count() == guard.squads.size(),
		"спит %d" % guard.asleep_count())
	var hp0: float = keep.current_health
	keep.take_damage(25.0, shooter)
	await pframes(int(_AICfg.HOME_GUARD_TICK_SEC * 60.0) * 2 + 6)
	verdict("D1 удар по замку будит охрану — первую волну (замок под ударом %.0f с)" % _AICfg.HOME_GUARD_HIT_SEC,
		guard.alarm and guard.asleep_count() == guard.squads.size() - mini(_AICfg.HOME_GUARD_WAVE_SQUADS, guard.squads.size()),
		"тревога %s, спит %d, запас замка %.0f → %.0f" % [str(guard.alarm), guard.asleep_count(),
			hp0, keep.current_health])
	var on_shooter := 0
	for s in guard.squads:
		for m in _members(int(s["sid"])):
			var t = (m as Unit).attack_target
			if t != null and is_instance_valid(t) and (t as Unit).squad_id == sid_far:
				on_shooter += 1
	verdict("D2 цель — отряд обидчика", on_shooter > 0, "на обидчика %d бойцов" % on_shooter)
	# Слепок: признак home_guard у всех отрядов охраны
	var snap: Dictionary = _SaveLoad.capture(main)
	var flagged := 0
	for row in snap.get("squads", []):
		if bool((row as Dictionary).get("home_guard", false)):
			flagged += 1
	verdict("D3 в слепке %d отрядов с признаком home_guard" % guard.squads.size(),
		flagged == guard.squads.size(), "помечено %d" % flagged)
	_kill_squad(sid_far)
	await pframes(6)
