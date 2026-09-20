extends Node
## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: РЕМОНТ МОНАХА (ТЗ 17.09.2026), headless
## ═══════════════════════════════════════════════════════════════════════════
##   A ГРАНИЦА  — раненый отряд за аурой: монах подходит, встаёт НА ГРАНИЦЕ
##                ауры (снаружи строя, MONK_STAND_FRAC × радиус от центра
##                отряда) и стоит без микро-движений; лечит оттуда
##   B ХИЛ      — раненый лечится до 100 % без обрыва, VFX держится всё
##                лечение (не мигает между тактами) и гаснет по излечении,
##                доля жизни в буфере отрисовки возвращается к 1.0
##   C ПОДЪЁМ   — канал воскрешения 5 с идёт ПАРАЛЛЕЛЬНО лечению (такты
##                лечения не прерываются), павший встаёт в отряд, круг канала
##                гаснет; каст канала — из ауры, к телу вплотную не бежит
##   D ОБРЫВ    — тело исчезло посреди канала: круг гаснет, модели нет,
##                зависшего круга нет
## Числа — из unit_stats_config (правило 10), время — физкадрами (правило 11).

const _UCfg := preload("res://scripts/unit_stats_config.gd")
const F := Constants.FACTION_PLAYER

var main = null
var _pass := 0
var _fail := 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(420.0).timeout.connect(func():
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
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО", ("  — " + d) if d != "" else ""])

func _finish() -> void:
	print("\n═════ ИТОГ qa_monk_fix: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _spawn(kind: String, fac: int, at: Vector3) -> Unit:
	var u: Unit = Building.PRELOAD_SCENES[kind].instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	u.post_pos = u.global_position
	return u

func _squad(kind: String, fac: int, at: Vector3, n: int, cols: int = 4) -> Array:
	var sid: int = GameManager.new_squad(fac, kind)
	var men: Array = []
	for i in range(n):
		var u: Unit = _spawn(kind, fac, Vector3(at.x - float(i / cols) * 0.8, 0.0,
			at.z + float(i % cols) * 0.7 - float(cols - 1) * 0.35))
		GameManager.add_to_squad(sid, u)
		men.append(u)
	# Разметка отряда — как после приказа игрока
	for u in men:
		(u as Unit).command_move((u as Unit).global_position, false, Vector3.FORWARD)
	GameManager.squad_close_ranks(sid, true)
	return [sid, men]

func _wound(u: Unit, frac: float) -> void:
	u.current_health = u.max_health * frac
	u._soa_push_stats()

func _kill_all(men: Array) -> void:
	for u in men:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			(u as Unit).take_damage(1e12)

func _alive(men: Array) -> Array:
	var out: Array = []
	for u in men:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			out.append(u)
	return out

func _centre(men: Array) -> Vector3:
	var c := Vector3.ZERO
	var n := 0
	for u in _alive(men):
		c += (u as Unit).global_position
		n += 1
	return c / float(maxi(n, 1))

func _half_extent(men: Array) -> float:
	var c: Vector3 = _centre(men)
	var r := 0.0
	for u in _alive(men):
		r = maxf(r, _xz((u as Unit).global_position, c))
	return r

func _xz(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _hp_sum(men: Array) -> float:
	var s := 0.0
	for u in _alive(men):
		s += (u as Unit).current_health
	return s

func _all_full(men: Array) -> bool:
	for u in _alive(men):
		if (u as Unit).current_health < (u as Unit).max_health - 0.01:
			return false
	return true

## Что лежит в буфере отрисовки про бойца: [вспышка, доля жизни]; пусто — нет слота
func _dmg_of(u: Unit) -> Array:
	var s = GameManager.far_units.slot_of(u)
	if s == null or s.bucket == null:
		return []
	var raw: PackedFloat32Array = GameManager.army.rb_slot(s.bucket.core_id, s.index)
	if raw.size() < 16:
		return []
	return [raw[14], raw[15]]

func _flat_spot(base: Vector3) -> Vector3:
	var best: Vector3 = base
	var best_h: float = 1e9
	for ix in range(-3, 4):
		for iz in range(-3, 4):
			var p := Vector3(base.x + float(ix) * 12.0, 0.0, base.z + float(iz) * 12.0)
			var h := 0.0
			for d in [Vector3.ZERO, Vector3(14.0, 0.0, 0.0), Vector3(-14.0, 0.0, 0.0), Vector3(0.0, 0.0, 8.0), Vector3(30.0, 0.0, 0.0), Vector3(36.0, 0.0, 0.0)]:
				h = maxf(h, absf(GameManager.get_terrain_height(p.x + d.x, p.z + d.z)))
			if GameManager.is_water(p.x, p.z) or GameManager.is_water(p.x + 30.0, p.z) or GameManager.is_water(p.x + 36.0, p.z):
				h += 100.0
			if h < best_h:
				best_h = h
				best = p
	return best

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(6)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.goblin_ai != null:
		main.goblin_ai.set_process(false)
	if main.fog != null:
		main.fog.enabled = false
	GameManager.pop_limit_enabled = false
	await frames(3)
	var base: Vector3 = _flat_spot(main.PLAYER_BASE_ANCHOR + Vector3(40.0, 0.0, 30.0))
	main._clear_area_of_resources(base, 70.0)
	await _a_border(base)
	await _b_heal(base + Vector3(0.0, 0.0, 60.0))
	await _c_revive(base + Vector3(-60.0, 0.0, 0.0))
	await _d_abort(base + Vector3(60.0, 0.0, 0.0))
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
# A. ГРАНИЦА АУРЫ, БЕЗ СУЕТЫ
# ═════════════════════════════════════════════════════════════════════════════
func _a_border(base: Vector3) -> void:
	print("\n═════ A. МОНАХ ВСТАЁТ НА ГРАНИЦУ АУРЫ И НЕ СУЕТИТСЯ ═════")
	var monk: Unit = _spawn("monk", F, base)
	var r: float = float(monk.call("heal_radius"))
	# Отряд за аурой (1.6 R), раненый наполовину
	var sq: Array = _squad("spearman", F, base + Vector3(r * 1.6, 0.0, 0.0), 12)
	for u in sq[1]: _wound(u, 0.5)
	await pframes(10)
	# Ждём прихода: монах стоит (IDLE, не двигался) и пациент в ауре
	var arrived_f := -1
	for f in range(60 * 30):
		await get_tree().physics_frame
		var c: Vector3 = _centre(sq[1])
		if _xz(monk.global_position, c) <= r and monk.state == Unit.State.IDLE \
				and not monk.moved_recently():
			arrived_f = f
			break
	verdict("A1 монах подошёл к отряду за аурой и встал", arrived_f >= 0,
		"за %d физкадров, до центра %.1f м (R %.1f)" % [arrived_f, _xz(monk.global_position, _centre(sq[1])), r])
	var c0: Vector3 = _centre(sq[1])
	var d0: float = _xz(monk.global_position, c0)
	var he: float = _half_extent(sq[1])
	verdict("A2 стоит СНАРУЖИ строя, у границы ауры (≥ 0.5 R и ≥ габарит + 2 м от центра, ≤ R)",
		d0 >= r * 0.5 and d0 >= he + 2.0 and d0 <= r,
		"до центра %.1f м, полугабарит строя %.1f, R %.1f" % [d0, he, r])
	# Микро-движения: 12 с после прихода — сдвиг и число приказов подхода
	var p0: Vector3 = monk.global_position
	var moves0: int = int(monk.get("approach_moves"))
	var worst := 0.0
	var hp0: float = _hp_sum(sq[1])
	for _f in range(60 * 12):
		await get_tree().physics_frame
		worst = maxf(worst, _xz(monk.global_position, p0))
	var moves1: int = int(monk.get("approach_moves"))
	verdict("A3 после прихода стоит на месте (сдвиг < 0.5 м за 12 с)", worst < 0.5,
		"наибольший сдвиг %.2f м" % worst)
	verdict("A4 приказов подхода за 12 с стояния — ноль", moves1 == moves0,
		"%d → %d" % [moves0, moves1])
	verdict("A5 лечит с границы ауры", _hp_sum(sq[1]) > hp0 + 1.0,
		"запас отряда %.0f → %.0f" % [hp0, _hp_sum(sq[1])])
	monk.take_damage(1e12)
	_kill_all(sq[1])
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
# B. ДОЛЕЧИВАНИЕ ДО 100 % И ЧЕСТНЫЙ VFX
# ═════════════════════════════════════════════════════════════════════════════
func _b_heal(base: Vector3) -> void:
	print("\n═════ B. ХИЛ ДО 100 %, VFX БЕЗ МИГАНИЯ И БЕЗ ЗАВИСАНИЯ ═════")
	var monk: Unit = _spawn("monk", F, base)
	var sq: Array = _squad("spearman", F, base + Vector3(8.0, 0.0, 0.0), 4)
	await pframes(10)
	var hurt: Unit = sq[1][1]
	_wound(hurt, 0.4)
	await pframes(3)
	var d: Array = _dmg_of(hurt)
	verdict("B0 доля жизни раненого в буфере отрисовки ниже 0.5", d.size() == 2 and float(d[1]) < 0.5,
		"буфер %s" % str(d))
	# Ждём полного излечения; по дороге считаем кадры «VFX висит на раненом»
	var tick: float = float(monk.call("heal_tick_sec"))
	var budget: int = int(60.0 * (_UCfg.MONK_HEAL_SEC_PER_MAN * 1.5 + tick * 4.0 + 3.0))
	var vfx_on := 0
	var vfx_frames := 0
	var started := false
	var healed_f := -1
	for f in range(budget):
		await get_tree().physics_frame
		var t = monk.call("heal_vfx_target")
		if not started and t == hurt:
			started = true
		if started:
			vfx_frames += 1
			if t == hurt:
				vfx_on += 1
		if hurt.current_health >= hurt.max_health - 0.01:
			healed_f = f
			break
	verdict("B1 раненый долечен до 100 %", healed_f >= 0,
		"за %.1f с, запас %.0f/%.0f" % [float(healed_f) / 60.0, hurt.current_health, hurt.max_health])
	var share: float = float(vfx_on) / float(maxi(vfx_frames, 1))
	verdict("B2 VFX держится на пациенте всё лечение (≥ 90 % кадров, не мигает между тактами)",
		started and share >= 0.9, "%.0f %% кадров (%d из %d)" % [share * 100.0, vfx_on, vfx_frames])
	# Гаснет по излечении — не позже такта
	var off_f := -1
	for f in range(int(tick * 60.0) + 30):
		await get_tree().physics_frame
		if monk.call("heal_vfx_target") == null:
			off_f = f
			break
	verdict("B3 VFX снят по излечении", off_f >= 0, "через %d физкадров" % off_f)
	await frames(3)
	var d1: Array = _dmg_of(hurt)
	verdict("B4 доля жизни в буфере отрисовки вернулась к 1.0 (модель не «красная»)",
		d1.size() == 2 and float(d1[1]) >= 0.99, "буфер %s" % str(d1))
	monk.take_damage(1e12)
	_kill_all(sq[1])
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
# C. ВОСКРЕШЕНИЕ 5 С ПАРАЛЛЕЛЬНО ЛЕЧЕНИЮ
# ═════════════════════════════════════════════════════════════════════════════
func _research_res() -> void:
	GameManager.researched.erase(F)
	for cell in ["1a", "1b", "1c", "1d", "2a", "2b", "2c", "2d"]:
		GameManager.finish_research(F, "monk_" + cell)

func _c_revive(base: Vector3) -> void:
	print("\n═════ C. КАНАЛ 5 С ПАРАЛЛЕЛЬНО ЛЕЧЕНИЮ ═════")
	_research_res()
	var monk: Unit = _spawn("monk", F, base)
	var r: float = float(monk.call("heal_radius"))
	var sq: Array = _squad("spearman", F, base + Vector3(12.0, 0.0, 0.0), 8)
	await pframes(20)
	verdict("C0 воскрешение изучено (2d)", bool(monk.call("can_resurrect")))
	verdict("C1 канал воскрешения — 5 с", float(monk.call("res_sec")) <= 5.01,
		"%.1f с" % float(monk.call("res_sec")))
	# Половина живых ранена, один павший
	for i in range(1, 8):
		_wound(sq[1][i], 0.5)
	var victim: Unit = sq[1][0]
	victim.take_damage(1e12)
	await pframes(3)
	var ch_start := -1
	var ticks_at_start := 0
	var ticks_in_channel := 0
	var wounded_at_start := false
	var raised_f := -1
	var min_gap := 1e9
	for f in range(60 * 30):
		await get_tree().physics_frame
		var rt = monk.call("res_target")
		if rt != null:
			if ch_start < 0:
				ch_start = f
				ticks_at_start = int(monk.get("heal_ticks"))
				wounded_at_start = not _all_full(sq[1])
			var sp: Vector3 = monk.get("_res_spot")
			if sp.x != INF:
				min_gap = minf(min_gap, _xz(monk.global_position, sp))
			ticks_in_channel = int(monk.get("heal_ticks")) - ticks_at_start
		if int(monk.get("resurrected_total")) > 0:
			raised_f = f
			break
	verdict("C2 канал открылся, пока в отряде ещё есть раненые (параллельно лечению)",
		ch_start >= 0 and wounded_at_start, "старт канала на кадре %d, раненые были=%s" % [ch_start, str(wounded_at_start)])
	verdict("C3 лечение НЕ прерывается на время канала (такты лечения идут)",
		ticks_in_channel >= 2, "тактов за канал %d" % ticks_in_channel)
	var ch_len: float = (float(raised_f - ch_start) / 60.0) if (raised_f >= 0 and ch_start >= 0) else -1.0
	verdict("C4 павший поднят за канал (≤ res_sec + 3 с от старта)",
		raised_f >= 0 and ch_start >= 0 and ch_len <= float(monk.call("res_sec")) + 3.0,
		"канал %.1f с" % ch_len)
	verdict("C5 в отряде снова 8 живых", _alive(GameManager.squad_members(int(sq[0]))).size() == 8,
		"живых %d" % _alive(GameManager.squad_members(int(sq[0]))).size())
	verdict("C6 каст канала — из ауры, к телу вплотную не бежал (ближе 4 м к точке не подходил)",
		min_gap >= 4.0 and min_gap <= r, "ближайшая дистанция до точки подъёма %.1f м" % min_gap)
	await pframes(20)
	verdict("C7 круг канала погашен после подъёма", not bool(monk.call("res_aura_visible")))
	monk.take_damage(1e12)
	_kill_all(GameManager.squad_members(int(sq[0])))
	GameManager.researched.erase(F)
	await pframes(3)

# ═════════════════════════════════════════════════════════════════════════════
# D. ТЕЛО ИСЧЕЗЛО ПОСРЕДИ КАНАЛА — КРУГ НЕ ЗАВИСАЕТ
# ═════════════════════════════════════════════════════════════════════════════
func _d_abort(base: Vector3) -> void:
	print("\n═════ D. ОБРЫВ КАНАЛА БЕЗ ЗАВИСШЕГО КРУГА ═════")
	_research_res()
	var monk: Unit = _spawn("monk", F, base)
	var sq: Array = _squad("spearman", F, base + Vector3(10.0, 0.0, 0.0), 6)
	await pframes(20)
	var victim: Unit = sq[1][0]
	victim.take_damage(1e12)
	await pframes(3)
	var opened := false
	for _f in range(60 * 10):
		await get_tree().physics_frame
		# Круг канала вырезан ТЗ 19.09.2026 (п. 1) — судим по самому каналу
		if monk.call("res_target") != null:
			opened = true
			break
	verdict("D1 канал открыт (круга на земле нет по ТЗ 19.09)", opened and not bool(monk.call("res_aura_visible")))
	# Тело снимается со слоя (как при вытеснении/растворении)
	var c = monk.call("res_target")
	if c != null:
		GameManager.corpses.remove_now(c)
	var closed_f := -1
	for f in range(60 * 3):
		await get_tree().physics_frame
		if monk.call("res_target") == null and not bool(monk.call("res_aura_visible")):
			closed_f = f
			break
	verdict("D2 без тела канал закрыт и круг погашен за секунду", closed_f >= 0 and closed_f <= 60,
		"через %d физкадров" % closed_f)
	await pframes(60 * 7)
	verdict("D3 модель из ничего не появилась", _alive(GameManager.squad_members(int(sq[0]))).size() == 5
		and int(monk.get("resurrected_total")) == 0,
		"живых %d, поднято %d" % [_alive(GameManager.squad_members(int(sq[0]))).size(), int(monk.get("resurrected_total"))])
	verdict("D4 круг канала не завис", not bool(monk.call("res_aura_visible")))
	monk.take_damage(1e12)
	_kill_all(GameManager.squad_members(int(sq[0])))
	GameManager.researched.erase(F)
	await pframes(3)
