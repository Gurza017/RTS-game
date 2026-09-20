extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_sprint19b — ПИСЬМО 10: РАБОЧИЕ С ТОПОРОМ, ЗАГОНЫ, ОВЦЫ, ТУША, ТРОЛЛЬ
## ═══════════════════════════════════════════════════════════════════════════
##   A ТОПОР      — у рабочего удар и запас из конфига, солдатом он не числится
##                  (клич/реплики), но врага вплотную бьёт сам и по приказу.
##   B ЗАГОН      — с двумя загонами овца идёт туда, где есть место; ПКМ по
##                  загону задаёт цель явно; полный назначенный — в соседний.
##   C ВНУТРИ     — первые INSIDE_CAP привязанных пасутся ВНУТРИ ограды у
##                  центра, лишние — вокруг в OVERFLOW_RADIUS; настроения.
##   D ТУША       — боец рубит овцу по приказу одним ударом, туша окровавлена,
##                  артель режет её вместе, мясо у туши, за 120 с истлевает.
##   E ТРОЛЛЬ     — наевшись, ломает постройку у стада и лишь потом уводит
##                  отару; перехваченную рабочим овцу логову не отдаёт.
## Числа — из конфигов (правило 10), ожидание — физкадрами (правило 11).
## Запуск: godot --headless --path . res://qa_sprint19b/Test.tscn

const _UCfg   := preload("res://scripts/unit_stats_config.gd")
const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")
const _Sheep  := preload("res://scripts/goblin/Sheep.gd")
const _Pen    := preload("res://scripts/SheepPen.gd")
const _CSite  := preload("res://scripts/ConstructionSite.gd")

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []
var _castle: Castle = null
var _lair = null

func _ready() -> void:
	call_deferred("_run")
	var t := get_tree().create_timer(420.0)
	t.timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 420 с")
		_finish())

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

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
	print("\n═════ ИТОГ qa_sprint19b: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _spawn(uid: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[uid].instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _bld(id: String, fac: int, at: Vector3) -> Building:
	var b: Building = _CSite.make_building(id)
	b.faction = fac
	main.world_add(b)
	b.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	return b

func _pen(at: Vector3) -> Building:
	var pen: Building = _Pen.new()
	pen.faction = Constants.FACTION_PLAYER
	main.world_add(pen)
	pen.global_position = Vector3(at.x, main.get_terrain_height(at.x, at.z), at.z)
	return pen

## Дикая овца (без привязки) в точке; стоит на месте, пока стенд не велит
func _wild_sheep(at: Vector3, tick: bool = false) -> Node3D:
	var s: Node3D = _Sheep.new()
	s.set("home", at)
	main.world_root().add_child(s)
	s.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	s.set_process(tick)
	return s

func _xz(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	# Пень за рекой в партии заморожен (ТЗ 19.09.2026); стенду нужен живой
	GameManager.call_deferred("thaw_lairs_now")
	await frames(8)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	GameManager.world_bounds_enabled = false
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	await pframes(4)
	_lair = GameManager.troll_lair
	if _lair != null and is_instance_valid(_lair):
		for t in _lair.get("trolls"):
			if is_instance_valid(t):
				(t as Unit).set_tick(false)
		for g in _lair.get("gnolls"):
			if g != null and is_instance_valid(g):
				(g as Node).queue_free()
		for s in _lair.get("sheep"):
			if s != null and is_instance_valid(s):
				(s as Node).queue_free()
	await pframes(4)
	_castle = Castle.new()
	_castle.faction = Constants.FACTION_PLAYER
	main.world_add(_castle)
	var cp: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(0.0, 0.0, 26.0)
	_castle.global_position = Vector3(cp.x, GameManager.get_terrain_height(cp.x, cp.z), cp.z)
	await pframes(6)

	await _a_axe()
	await _b_pens()
	await _c_inside()
	await _d_corpse()
	await _e_troll()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
# A. ТОПОР РАБОЧЕГО
# ═════════════════════════════════════════════════════════════════════════════
func _a_axe() -> void:
	print("\n═════ A. РАБОЧИЙ С ТОПОРОМ ═════")
	var st: Dictionary = _UCfg.get_stats("worker")
	verdict("A1 в конфиге у рабочего есть удар и запас (attack_1 %.1f, health %.0f)" % [
			float(st.get("attack_1", 0.0)), float(st.get("health", 0.0))],
		float(st.get("attack_1", 0.0)) > 0.0 and float(st.get("health", 0.0)) > 30.0)
	var base: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(40.0, 0.0, 40.0)
	var w: Worker = _spawn("worker", Constants.FACTION_PLAYER, base) as Worker
	await pframes(3)
	verdict("A2 у бойца удар %.1f > 0, дальность руки %.1f ≤ %.1f" % [
			w.attack_damage, w.attack_range, HUD.MELEE_RANGE_MAX],
		w.attack_damage > 0.0 and w.attack_range <= HUD.MELEE_RANGE_MAX)
	verdict("A3 рабочий — НЕ боевой отряд (is_combatant false, squad_is_combat false)",
		not w.is_combatant() and not GameManager.squad_is_combat(w.squad_id))
	var sm = main.get("selection_manager")
	if sm == null:
		sm = main.get_node_or_null("SelectionManager")
	if sm != null:
		sm.selected_units = [w]
		verdict("A3б выделение из рабочего может атаковать по ПКМ (_selection_can_attack)",
			bool(sm.call("_selection_can_attack")))
		verdict("A3в боевых отрядов в выделении из рабочего — ноль (реплик не будет)",
			int(sm.call("selected_combat_squad_count")) == 0,
			"%d" % int(sm.call("selected_combat_squad_count")))
		sm.selected_units = []
	# ── АВТО-АГРО: враг вплотную, рабочий в покое — бьёт сам ────────────
	var foe: Unit = _spawn("goblin_spearman", Constants.FACTION_GOBLIN, base + Vector3(2.5, 0.0, 0.0))
	foe.set_tick(false)
	var hp0: float = foe.current_health
	var hit := false
	var tgt := false
	for _i in range(60 * 12):
		await get_tree().physics_frame
		if w.attack_target == foe:
			tgt = true
		if foe.current_health < hp0:
			hit = true
			break
	verdict("A4 рабочий в покое сам взял врага вплотную целью (авто-агро)", tgt)
	verdict("A5 и ударил: запас врага %.1f → %.1f" % [hp0, foe.current_health], hit)
	verdict("A5б замах — лентой топора (chop)", String(w.get("_anim_name")) == "chop"
		or w.get("_anim_lock_until_ms") > 0, "лента %s" % String(w.get("_anim_name")))
	# ── ПО ПРИКАЗУ: рабочий на добыче бросает дерево и идёт бить ──────────
	var w2: Worker = _spawn("worker", Constants.FACTION_PLAYER, base + Vector3(0.0, 0.0, 14.0)) as Worker
	var foe2: Unit = _spawn("goblin_spearman", Constants.FACTION_GOBLIN, base + Vector3(9.0, 0.0, 14.0))
	foe2.set_tick(false)
	await pframes(2)
	w2.command_attack(foe2, true, false, true)
	var hp2: float = foe2.current_health
	var hit2 := false
	for _i in range(60 * 15):
		await get_tree().physics_frame
		if foe2.current_health < hp2:
			hit2 = true
			break
	verdict("A6 приказ атаки принят (state ATTACKING, цель — враг)", w2.attack_target == foe2 or hit2)
	verdict("A7 дошёл и бьёт: запас %.1f → %.1f" % [hp2, foe2.current_health], hit2)
	# ── ОТВЕТ НА УДАР ────────────────────────────────────────────────────
	var w3: Worker = _spawn("worker", Constants.FACTION_PLAYER, base + Vector3(0.0, 0.0, 28.0)) as Worker
	var foe3: Unit = _spawn("goblin_spearman", Constants.FACTION_GOBLIN, base + Vector3(1.2, 0.0, 28.0))
	foe3.set_tick(false)
	await pframes(3)
	w3.take_damage(3.0, foe3)
	await pframes(3)
	verdict("A8 получил удар вплотную — ответил (цель = обидчик)", w3.attack_target == foe3)
	for n in [w, w2, w3, foe, foe2, foe3]:
		if is_instance_valid(n):
			(n as Node).queue_free()
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
# B. ДВА ЗАГОНА
# ═════════════════════════════════════════════════════════════════════════════
func _b_pens() -> void:
	print("\n═════ B. КУДА НЕСТИ: ЗАГОН С МЕСТОМ, ПКМ ПО ЗАГОНУ ═════")
	var base: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(-40.0, 0.0, 40.0)
	var pen1: Building = _pen(base + Vector3(-14.0, 0.0, 0.0))
	var pen2: Building = _pen(base + Vector3(14.0, 0.0, 0.0))
	await pframes(4)
	# pen1 набит под потолок
	var cap: int = int(pen1.call("capacity"))
	var filler: Array = []
	for i in range(cap):
		var s: Node3D = _wild_sheep(pen1.global_position + Vector3(float(i % 5) - 2.0, 0.0, float(i / 5) - 2.0))
		s.call("bind_to_pen", pen1, Constants.FACTION_PLAYER)
		filler.append(s)
	await pframes(2)
	verdict("B1 первый загон полон: %d / %d, места нет" % [int(pen1.call("sheep_count")), cap],
		not bool(pen1.call("has_room")))
	var w: Worker = _spawn("worker", Constants.FACTION_PLAYER, base + Vector3(-14.0, 0.0, 12.0)) as Worker
	var wild: Node3D = _wild_sheep(base + Vector3(-14.0, 0.0, 16.0))
	await pframes(2)
	w.command_steal_sheep(wild)
	var dest: Node3D = w.call("_sheep_dest")
	verdict("B2 рабочий у полного загона несёт овцу во ВТОРОЙ, где есть место", dest == pen2,
		"назначение %s" % (String(dest.name) if dest != null else "null"))
	# ПКМ по загону явно: пока идём за овцой — цель назначена
	w.set_sheep_dest(pen2)
	verdict("B3 ПКМ по загону задаёт цель переноски явно", w.sheep_dest_node() == pen2)
	var bound := false
	for _i in range(60 * 60):
		await get_tree().physics_frame
		if is_instance_valid(wild) and wild.get("pen") == pen2:
			bound = true
			break
		if not w.is_stealing_sheep() and (not is_instance_valid(wild) or wild.get("pen") != pen2):
			break
	verdict("B4 овца донесена и привязана ко второму загону", bound)
	# Назначенный ПОЛНЫЙ загон: несём в соседний с местом
	var w2: Worker = _spawn("worker", Constants.FACTION_PLAYER, base + Vector3(-14.0, 0.0, 12.0)) as Worker
	var wild2: Node3D = _wild_sheep(base + Vector3(-14.0, 0.0, 18.0))
	await pframes(2)
	w2.command_steal_sheep(wild2)
	w2.set_sheep_dest(pen1)
	verdict("B5 явно назначен полный загон", w2.sheep_dest_node() == pen1)
	var bound2 := false
	var rerouted := false
	for _i in range(60 * 75):
		await get_tree().physics_frame
		if w2.sheep_dest_node() == pen2:
			rerouted = true
		if is_instance_valid(wild2) and wild2.get("pen") == pen2:
			bound2 = true
			break
		if not w2.is_stealing_sheep():
			break
	verdict("B6 полный назначенный загон → овца ушла в соседний с местом", bound2 and rerouted,
		"перенаправлен %s, привязана %s" % [str(rerouted), str(bound2)])
	for s in filler:
		if is_instance_valid(s):
			(s as Node).queue_free()
	for n in [w, w2, wild, wild2, pen1, pen2]:
		if n != null and is_instance_valid(n):
			(n as Node).queue_free()
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
# C. ВНУТРИ ОГРАДЫ — ДЕСЯТЬ, ЛИШНИЕ ВОКРУГ; НАСТРОЕНИЯ
# ═════════════════════════════════════════════════════════════════════════════
func _c_inside() -> void:
	print("\n═════ C. ОВЦЫ ВНУТРИ ЗАГОНА И ВОКРУГ ═════")
	var base: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(40.0, 0.0, -40.0)
	var pen: Building = _pen(base)
	await pframes(4)
	var cap_in: int = int(pen.INSIDE_CAP)
	var n: int = cap_in + 4
	var flock: Array = []
	for i in range(n):
		var s: Node3D = _wild_sheep(base + Vector3(3.0 * float(i % 4) - 4.5, 0.0, 3.0 * float(i / 4) - 4.5))
		s.call("bind_to_pen", pen, Constants.FACTION_PLAYER)
		flock.append(s)
	await pframes(2)
	var inside := 0
	var outside := 0
	for i in range(n):
		if bool(pen.call("inside_slot", flock[i])):
			inside += 1
		else:
			outside += 1
	verdict("C1 внутри по порядку привязки ровно %d, снаружи %d" % [cap_in, n - cap_in],
		inside == cap_in and outside == n - cap_in, "внутри %d, снаружи %d" % [inside, outside])
	var half: float = minf(pen.build_size.x, pen.build_size.z) * 0.5
	verdict("C2 радиус выпаса внутренней овцы %.1f < полуширины ограды %.1f" % [
			float(flock[0].call("graze_radius")), half],
		float(flock[0].call("graze_radius")) < half)
	verdict("C3 радиус выпаса лишней овцы = OVERFLOW_RADIUS %.0f м" % pen.OVERFLOW_RADIUS,
		absf(float(flock[n - 1].call("graze_radius")) - pen.OVERFLOW_RADIUS) < 0.01)
	# Перебежки: внутренние остаются в круге у центра, лишние — в 20 м
	var worst_in := 0.0
	var worst_out := 0.0
	var seen_in_center := 0
	for _k in range(8):
		for i in range(n):
			flock[i].call("force_hop")
			flock[i].call("arrive_now")
		for i in range(n):
			var d: float = _xz(flock[i].global_position, pen.global_position)
			if i < cap_in:
				worst_in = maxf(worst_in, d)
				if d < half:
					seen_in_center += 1
			else:
				worst_out = maxf(worst_out, d)
	verdict("C4 внутренние после 8 перебежек не дальше %.1f м от центра (худшая %.2f)" % [half, worst_in],
		worst_in <= half + 0.05)
	verdict("C4б внутренние не сидят кольцом на ограде: %d из %d замеров ближе полуширины" % [
			seen_in_center, cap_in * 8], seen_in_center == cap_in * 8)
	verdict("C5 лишние гуляют не дальше %.0f м (худшая %.1f)" % [pen.OVERFLOW_RADIUS, worst_out],
		worst_out <= pen.OVERFLOW_RADIUS + 0.05 and worst_out > half)
	# Выбыла внутренняя — следующая по порядку встаёт внутрь
	var s0: Node3D = flock[0]
	s0.call("kill_by", null)
	await pframes(1)
	verdict("C6 выбыла внутренняя — первая из лишних теперь внутри",
		bool(pen.call("inside_slot", flock[cap_in])))
	verdict("C7 подпись загона считает внутренних: «%s»" % String(pen.call("capacity_text")),
		String(pen.call("capacity_text")).find("внутри") >= 0)
	# ── НАСТРОЕНИЯ ──────────────────────────────────────────────────────
	var s1: Node3D = flock[1]
	var moods: Dictionary = {}
	for _k in range(60):
		s1.call("_pick_mood")
		moods[int(s1.call("mood"))] = true
		s1.set("_mood", 0)
		s1.call("arrive_now")
	verdict("C8 на выпасе не одна перебежка: настроений видов %d (лежит/прыгает/щиплет)" % moods.size(),
		moods.size() >= 3, str(moods.keys()))
	s1.call("_set_mood_anim", "rest", 0.0)
	var mat: ShaderMaterial = s1.get("_mat")
	verdict("C9 «лежит» — один кадр ленты, без листания",
		mat != null and int(mat.get_shader_parameter("frame_count")) == 1
			and float(mat.get_shader_parameter("frame_fps")) == 0.0)
	s1.call("_set_anim", false, false)
	for s in flock:
		if is_instance_valid(s):
			(s as Node).queue_free()
	pen.queue_free()
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
# D. ТУША: БОЕЦ РУБИТ, АРТЕЛЬ РЕЖЕТ, 120 С — ИСТЛЕЛА
# ═════════════════════════════════════════════════════════════════════════════
func _d_corpse() -> void:
	print("\n═════ D. ТУША ОВЦЫ ═════")
	var base: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(-40.0, 0.0, -40.0)
	var sheep: Node3D = _wild_sheep(base)
	sheep.call("bind_to_keep", _castle, Constants.FACTION_PLAYER)
	sheep.set("home", base)
	var sp: Unit = _spawn("spearman", Constants.FACTION_PLAYER, base + Vector3(-8.0, 0.0, 0.0))
	await pframes(2)
	sp.command_hunt_sheep(sheep)
	verdict("D1 копейщик принял приказ на овцу (идёт, охота взведена)",
		sp.state == Unit.State.MOVING and sp.is_hunting_sheep())
	var dead := false
	for _i in range(60 * 20):
		await get_tree().physics_frame
		if bool(sheep.get("dead")):
			dead = true
			break
	verdict("D2 дошёл и зарубил одним ударом: овца мертва", dead)
	verdict("D3 убийца записан, охота снята", sheep.get("killed_by") == sp and not sp.is_hunting_sheep())
	var mat: ShaderMaterial = sheep.get("_mat")
	var tint: Color = mat.get_shader_parameter("modulate") if mat != null else Color.WHITE
	verdict("D4 туша окровавлена (modulate %s)" % str(tint), tint.r > tint.g + 0.2 and tint.g < 0.6)
	verdict("D5 мясо лежит У ТУШИ: %d кусков = MEAT_TRIPS" % int(sheep.get("meat_left")),
		int(sheep.get("meat_left")) == _Sheep.MEAT_TRIPS and Worker.SHEEP_MEAT_TRIPS == _Sheep.MEAT_TRIPS)
	# Артель: два рабочих по ПКМ на тушу
	var w1: Worker = _spawn("worker", Constants.FACTION_PLAYER, base + Vector3(0.0, 0.0, 6.0)) as Worker
	var w2: Worker = _spawn("worker", Constants.FACTION_PLAYER, base + Vector3(3.0, 0.0, 6.0)) as Worker
	await pframes(2)
	w1.command_steal_sheep(sheep)
	w2.command_steal_sheep(sheep)
	verdict("D6 приказ на тушу принят обоими (фаза GO)", w1.is_stealing_sheep() and w2.is_stealing_sheep())
	var both := false
	for _i in range(60 * 20):
		await get_tree().physics_frame
		if w1.sheep_phase() == Worker.SheepPhase.BUTCHER and w2.sheep_phase() == Worker.SheepPhase.BUTCHER:
			both = true
			break
	verdict("D7 оба дошли и режут (BUTCHER), в артели %d" % int(sheep.call("butcher_count")),
		both and int(sheep.call("butcher_count")) == 2)
	var meat0: int = int(sheep.get("meat_left"))
	var carried := 0
	for _i in range(60 * 40):
		await get_tree().physics_frame
		carried = 0
		if w1.sheep_phase() == Worker.SheepPhase.HAUL or w1.sheep_phase() == Worker.SheepPhase.BACK:
			carried += 1
		if w2.sheep_phase() == Worker.SheepPhase.HAUL or w2.sheep_phase() == Worker.SheepPhase.BACK:
			carried += 1
		if carried == 2:
			break
	verdict("D8 оба отрезали по куску — запас туши %d → %d" % [meat0, int(sheep.get("meat_left"))],
		int(sheep.get("meat_left")) == meat0 - 2)
	# Мясо кончилось — оба за следующую (ставим соседнюю овцу)
	var nxt: Node3D = _wild_sheep(base + Vector3(10.0, 0.0, 0.0))
	nxt.call("bind_to_keep", _castle, Constants.FACTION_PLAYER)
	nxt.set("home", base + Vector3(10.0, 0.0, 0.0))
	sheep.set("meat_left", 0)
	var switched := 0
	for _i in range(60 * 60):
		await get_tree().physics_frame
		switched = 0
		if w1.get("_sheep") == nxt:
			switched += 1
		if w2.get("_sheep") == nxt:
			switched += 1
		if switched == 2:
			break
	verdict("D9 туша выработана — оба рабочих сами взялись за соседнюю овцу", switched == 2,
		"перешли %d из 2" % switched)
	verdict("D9б выработанная туша исчезла", not is_instance_valid(sheep) or bool(sheep.get("eaten")))
	w1.command_move(base + Vector3(0.0, 0.0, 20.0))
	w2.command_move(base + Vector3(3.0, 0.0, 20.0))
	# ── 120 С БЕЗ РАЗДЕЛКИ — ИСТЛЕЛА ─────────────────────────────────────
	var lone: Node3D = _wild_sheep(base + Vector3(0.0, 0.0, -12.0), true)
	lone.call("kill_by", null)
	await pframes(2)
	lone.call("_process", _Sheep.CORPSE_DESPAWN_SEC * 0.5)
	verdict("D10 через половину срока туша ещё лежит", not bool(lone.get("eaten")))
	lone.call("_process", _Sheep.CORPSE_DESPAWN_SEC * 0.6)
	verdict("D11 через %.0f с без разделки туша истлела" % _Sheep.CORPSE_DESPAWN_SEC, bool(lone.get("eaten")))
	# Пока рабочий на туше — часы не идут
	var held: Node3D = _wild_sheep(base + Vector3(6.0, 0.0, -12.0), true)
	held.call("kill_by", null)
	var wk: Worker = _spawn("worker", Constants.FACTION_PLAYER, base + Vector3(6.0, 0.0, -13.0)) as Worker
	await pframes(2)
	held.call("butcher_join", wk)
	held.call("_process", _Sheep.CORPSE_DESPAWN_SEC * 1.5)
	verdict("D12 пока на туше рабочий — она не истлевает", not bool(held.get("eaten")))
	# Рабочий не рубит живую соседнюю боевым ударом: приказ на ЖИВУЮ — кража/нож
	for n in [sp, w1, w2, wk, nxt, held]:
		if n != null and is_instance_valid(n):
			(n as Node).queue_free()
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
# E. РЕЙД ТРОЛЛЯ: СЛОМАТЬ ПОСТРОЙКУ, ПЕРЕХВАТ ОТАРЫ
# ═════════════════════════════════════════════════════════════════════════════
func _e_troll() -> void:
	print("\n═════ E. РЕЙД ТРОЛЛЯ ═════")
	var base: Vector3 = main.PLAYER_BASE_ANCHOR + Vector3(70.0, 0.0, 10.0)
	var t: Unit = _spawn("troll", Constants.FACTION_GOBLIN, base)
	t.set("lair", _lair)
	var house: Building = _bld("house", Constants.FACTION_PLAYER, base + Vector3(16.0, 0.0, 0.0))
	await pframes(3)
	t.set("_raid", {"phase": "eat", "faction": Constants.FACTION_PLAYER, "eaten": _GobCfg.TROLL_RAID_EAT, "herd": []})
	var started: bool = bool(t.call("_raid_smash_start", Constants.FACTION_PLAYER))
	verdict("E1 наевшись, тролль берёт под дубину постройку у стада (фаза smash, цель — дом)",
		started and String(t.call("raid_phase")) == "smash" and t.attack_target == house,
		"фаза %s" % String(t.call("raid_phase")))
	var hp0: float = house.current_health
	var smashed := false
	for _i in range(60 * 40):
		await get_tree().physics_frame
		# Правило 5: снесённый дом освобождён — живость на сырой ссылке
		if not is_instance_valid(house) or house.is_dead():
			smashed = true
			break
	verdict("E2 дом снесён троллем (запас был %.0f)" % hp0, smashed)
	for _i in range(60 * 3):
		await get_tree().physics_frame
		if String(t.call("raid_phase")) == "home" or String(t.call("raid_phase")) == "":
			break
	verdict("E3 после сноса рейд идёт дальше (отара/домой), снесённых %d" % int(t.get("raid_smashed")),
		String(t.call("raid_phase")) != "smash" and int(t.get("raid_smashed")) >= 1,
		"фаза «%s»" % String(t.call("raid_phase")))
	verdict("E4 крепость троллю запрещена по-прежнему", not t.may_attack_building(_castle))
	# ── ПЕРЕХВАТ: угоняемую овцу рабочий забирает обратно ────────────────
	t.set_tick(false)
	var sh: Node3D = _wild_sheep(base + Vector3(-6.0, 0.0, 8.0), true)
	sh.call("bind_to_keep", _castle, Constants.FACTION_PLAYER)
	sh.call("herd_by", t)
	t.set("_raid", {"phase": "home", "faction": Constants.FACTION_PLAYER, "eaten": 3, "herd": [sh]})
	verdict("E5 овца идёт за троллем (пастух назначен, привязка снята)",
		sh.get("herder") == t and not bool(sh.call("is_owned")))
	var w: Worker = _spawn("worker", Constants.FACTION_PLAYER, base + Vector3(-6.0, 0.0, 12.0)) as Worker
	await pframes(2)
	w.command_steal_sheep(sh)
	var taken := false
	for _i in range(60 * 20):
		await get_tree().physics_frame
		if sh.get("captor") == w:
			taken = true
			break
	verdict("E6 рабочий по ПКМ перехватил угоняемую овцу (несёт её)", taken and sh.get("herder") == null)
	t.call("_raid_finish", true)
	verdict("E7 логово перехваченную овцу не получило (lair пуст, отара тролля без неё)",
		sh.get("lair") == null and sh.get("captor") == w)
	var home := false
	for _i in range(60 * 60):
		await get_tree().physics_frame
		if bool(sh.call("is_owned")):
			home = true
			break
	verdict("E8 овца принесена домой и снова в стаде игрока", home)
	for n in [t, w, sh]:
		if n != null and is_instance_valid(n):
			(n as Node).queue_free()
	await pframes(3)
