extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ТАРАН, ТОПТАНИЕ, ДУГА ДУБИНЫ И СБИВАНИЕ С НОГ У ТРОЛЛЯ (09.09.2026)
## ═══════════════════════════════════════════════════════════════════════════
##   A КОНФИГ — скорость +20 %, патруль +30 %, толчок на 20 % сильнее конницы
##     (charge_push_mult), топтание/дуга/сбивание заданы.
##   B ТАРАН — тролль с разгона входит в фалангу СКВОЗЬ стенку копий, первые
##     TROLL_TRAMPLE_COUNT по ходу гибнут на месте в кадр удара.
##   C ДУБИНА — удар накрывает до TROLL_SWEEP_COUNT бойцов, все впереди по
##     взгляду; накрытые отлетают (м), лежат сбитыми (слот отрисовки снят,
##     на месте лежит тело), через TROLL_KNOCKDOWN_SEC встают и снова в бою.
##   D ВИЗУАЛ УРОНА — пик вспышки у тролля ниже общего, пятна крови включены
##     у его бакета и есть в шейдере.
##
## Числа — из конфигов (правило 10), ожидание физкадрами (правило 11).
## Запуск: godot --headless --path . res://qa_troll_impact/Test.tscn

const _UCfg   := preload("res://scripts/unit_stats_config.gd")
const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")
const _TrollScript := preload("res://scripts/goblin/Troll.gd")

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	var t := get_tree().create_timer(300.0)
	t.timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 300 с")
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
	print("\n═════ ИТОГ qa_troll_impact: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

## Фаланга: cols колонн, шаг строевой — как в игре
func _spawn_squad(kind: String, at: Vector3, n: int, cols: int = 6) -> Array:
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, kind)
	var men: Array = []
	var scene: PackedScene = Building.PRELOAD_SCENES[kind]
	var gap: float = Building.new().squad_spacing
	for i in range(n):
		var u: Unit = scene.instantiate()
		u.faction = Constants.FACTION_PLAYER
		main.world_add(u)
		var px: float = at.x + (float(i % cols) - float(cols - 1) * 0.5) * gap
		var pz: float = at.z + float(i / cols) * gap
		u.global_position = Vector3(px, GameManager.get_terrain_height(px, pz), pz)
		u.sync_row()
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return [sid, men]

func _alive(men: Array) -> int:
	var n := 0
	for m in men:
		if is_instance_valid(m) and not (m as Unit).is_dead():
			n += 1
	return n

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
	_check_config()
	await _check_charge()
	await _check_pick_and_death()
	_finish()

## ── E. КЛИК ПО ВСЕМУ СПРАЙТУ, КОЛЬЦО, ГИБЕЛЬ ПРОЧЬ ОТ УДАРА (10.09.2026) ────
func _check_pick_and_death() -> void:
	print("\n═════ E. КЛИК, КОЛЬЦО, ГИБЕЛЬ ═════")
	var lair = GameManager.troll_lair
	if lair == null or not is_instance_valid(lair):
		verdict("E0 логова нет", false)
		return
	var fresh: Array = lair.spawn_guards(1)
	if fresh.is_empty():
		verdict("E0 тролля нет", false)
		return
	var troll: Unit = fresh[0]
	await frames(6)
	verdict("E1 у тролля своё кольцо и своя зона клика (крупнее пехоты)",
		troll.ring_scale() > 1.5 and troll.pick_body_h() > 1.0 and troll.pick_radius() > 0.5,
		"кольцо ×%.1f, полувысота %.1f м, круг %.1f м" % [troll.ring_scale(), troll.pick_body_h(), troll.pick_radius()])
	var sd = GameManager.sel_decals
	sd.register(troll, main.world_root())
	var idx: int = int(sd._slot[troll])
	var buf: PackedFloat32Array = GameManager.army.rb_slot(sd._rings.core_id, idx)
	var b0: float = buf[0] if buf.size() > 0 else -1.0
	var b10: float = buf[10] if buf.size() > 10 else -1.0
	# ── КОЛЬЦО ТРОЛЛЯ — ОВАЛ (заказ владельца 10.09.2026) ──────────────────
	# Было «растянуто в ring_scale раз по обеим осям»; теперь поверх идёт
	# ring_oval (шире по X, уже по Z), а ТЕНИ под троллем нет вовсе
	var ov: Vector2 = troll.ring_oval()
	verdict("E2 базис кольца в буфере — овал ring_scale × ring_oval",
		buf.size() >= 12 and is_equal_approx(b0, troll.ring_scale() * ov.x)
			and is_equal_approx(b10, troll.ring_scale() * ov.y) and ov.x > ov.y,
		"buf[0]=%.2f buf[10]=%.2f при кольце %.1f и овале %.2f×%.2f" % [
			b0, b10, troll.ring_scale(), ov.x, ov.y])
	var sbuf: PackedFloat32Array = GameManager.army.rb_slot(sd._shadows.core_id, idx)
	var s0: float = sbuf[0] if sbuf.size() > 0 else -1.0
	verdict("E2б тени под троллем нет: базис тени нулевой",
		is_equal_approx(troll.shadow_scale(), 0.0) and absf(s0) < 0.001,
		"shadow_scale %.2f, buf[0]=%.3f" % [troll.shadow_scale(), s0])
	# Камера над троллем, заморожена (правило стендов, целящихся по экрану)
	main.focus_camera_on(troll.global_position)
	await frames(4)
	var cam: Camera3D = get_viewport().get_camera_3d()
	main.set_process(false)
	(main._camera as Node).set_process(false)
	await frames(2)
	var sm = main.selection_manager
	var tp: Vector3 = troll.global_position
	var aims: Array = [
		["E3 клик в середину спрайта", tp + Vector3(0.0, troll.pick_body_h(), 0.0)],
		["E4 клик в макушку", tp + Vector3(0.0, troll.pick_body_h() * 1.8, 0.0)],
		["E5 клик в край кольца у ног", tp + Vector3(troll.pick_radius() * 0.8, 0.0, 0.0)],
	]
	for a in aims:
		var scr: Vector2 = cam.unproject_position(a[1] as Vector3)
		var hit = sm._pick_at(scr, Constants.LAYER_UNITS).get("target")
		verdict(String(a[0]) + " берёт тролля", hit == troll,
			"взят %s" % (str(hit.name) if hit != null else "никто"))
	var far_scr: Vector2 = cam.unproject_position(tp + Vector3(0.0, 0.0, 14.0))
	var far_hit = sm._pick_at(far_scr, Constants.LAYER_UNITS).get("target")
	verdict("E6 клик в траву в 14 м перед троллем тролля НЕ берёт", far_hit != troll)
	# Гибель: удар слева по экрану — тело падает вправо (зеркало), общий слой
	# тел не пополняется, узел стоит низом на грунте
	var right: Vector3 = cam.global_transform.basis.x
	var hitter_at: Vector3 = tp - right * 6.0
	var sp: Array = _spawn_squad("spearman", hitter_at, 1)
	var hitter: Unit = sp[1][0]
	await pframes(2)
	var corpses_before: int = GameManager.corpses.spawned_total
	var expect_mirror: bool = (tp - hitter.global_position).dot(right) > 0.0
	troll.take_damage(1.0e9, hitter)
	await frames(3)
	# Тролль к этому кадру уже освобождён (правило 5): константы — со скрипта
	var mi: MeshInstance3D = main.world_root().get_node_or_null(_TrollScript.CORPSE_NAME) as MeshInstance3D
	verdict("E7 тело тролля — свой билборд, а не квад общего слоя", mi != null
		and GameManager.corpses.spawned_total == corpses_before,
		"узел %s, общий слой +%d" % [str(mi != null), GameManager.corpses.spawned_total - corpses_before])
	if mi != null:
		verdict("E8 тело упало ПРОЧЬ от удара (зеркало по стороне обидчика)",
			bool(mi.get_meta("mirror", not expect_mirror)) == expect_mirror,
			"зеркало %s при ожидаемом %s" % [str(mi.get_meta("mirror")), str(expect_mirror)])
		var q: QuadMesh = mi.mesh as QuadMesh
		var foot: float = mi.global_position.y - q.size.y * 0.5
		var gy: float = GameManager.get_terrain_height(mi.global_position.x, mi.global_position.z)
		verdict("E9 низ рисунка лежит на грунте (не обрезан рельефом, не висит)",
			absf(foot - gy) < 0.05, "низ %.2f, грунт %.2f, квад %.1f×%.1f м" % [foot, gy, q.size.x, q.size.y])
		var n_frames: int = int(mi.get_meta("frames", 0))
		await get_tree().create_timer(float(n_frames) / _TrollScript.DEATH_FPS + 0.4).timeout
		verdict("E10 лента гибели доиграна до последнего кадра и замерла",
			int(mi.get_meta("frame", 0)) == n_frames - 1,
			"кадр %d из %d" % [int(mi.get_meta("frame", 0)), n_frames])

# ═════════════════════════════════════════════════════════════════════════════
# A. КОНФИГ
# ═════════════════════════════════════════════════════════════════════════════
func _check_config() -> void:
	print("\n═════ A. КОНФИГ ═════")
	var spd: float = _UCfg.stat("troll", "movement_speed", 0.0)
	verdict("A1 скорость тролля +20 % (не ниже 2.4 × 1.2)", spd >= 2.4 * 1.2 - 1e-6,
		"%.2f м/с" % spd)
	verdict("A2 радиус патруля +30 % (не ниже 18 × 1.3)",
		_GobCfg.TROLL_PATROL_RADIUS >= 18.0 * 1.3 - 1e-6, "%.1f м" % _GobCfg.TROLL_PATROL_RADIUS)
	# Конница — тот род войск в STATS, у которого есть разгон и который не тролль
	var cav_mult := 0.0
	var cav_name := ""
	for k in _UCfg.STATS.keys():
		if String(k) == "troll":
			continue
		var d: Dictionary = _UCfg.STATS[k]
		if float(d.get("charge_range", 0.0)) > 0.0:
			cav_mult = maxf(cav_mult, float(d.get("charge_push_mult", 1.0)))
			cav_name = String(k)
	var troll_mult: float = _UCfg.stat("troll", "charge_push_mult", 1.0)
	var troll_pf: float = _UCfg.stat("troll", "push_force", 0.0)
	verdict("A3 толчок тролля на 20 %% сильнее конницы (%s): множитель и напор" % cav_name,
		troll_mult >= cav_mult * 1.2 - 1e-6 and troll_pf >= float(_UCfg.STATS[cav_name].get("push_force", 0.0)),
		"тролль ×%.2f при напоре %.0f, конница ×%.2f" % [troll_mult, troll_pf, cav_mult])
	verdict("A4 топтание, дуга и сбивание заданы",
		_GobCfg.TROLL_TRAMPLE_COUNT == 3 and _GobCfg.TROLL_SWEEP_COUNT == 6
			and _GobCfg.TROLL_KNOCKDOWN_SEC > 0.0 and _GobCfg.TROLL_SWEEP_KNOCKBACK > 0.0)

# ═════════════════════════════════════════════════════════════════════════════
# B-D. ТАРАН, ДУБИНА, ВИЗУАЛ
# ═════════════════════════════════════════════════════════════════════════════
func _check_charge() -> void:
	print("\n═════ B. ТАРАН И ТОПТАНИЕ ═════")
	var lair = GameManager.troll_lair
	# Агро-вызов логова (10.09.2026) здесь выключен: стенд меряет ОДНОГО тролля,
	# а помощники прибежали бы к копейщикам раньше кадра удара
	if lair != null and is_instance_valid(lair):
		lair.set("aggro_enabled", false)
	if lair == null:
		verdict("B0 логова нет", false)
		return
	var troll: Unit = null
	for t in lair.trolls:
		if is_instance_valid(t):
			troll = t
			break
	if troll == null:
		verdict("B0 тролля нет", false)
		return
	# Тролля ставим в чистое поле подальше от логова, фалангу — по курсу
	var base := Vector3(0.0, 0.0, -40.0)
	troll.global_position = Vector3(base.x, GameManager.get_terrain_height(base.x, base.z), base.z)
	troll.sync_row()
	var sp := _spawn_squad("spearman", base + Vector3(0.0, 0.0, 26.0), 30, 6)
	var men: Array = sp[1]
	# Фаланга смотрит на тролля — стенка копий ЛБОМ (repels_charge)
	for m in men:
		(m as Unit).set_stance("defense")
		(m as Unit)._facing = Vector3(0, 0, -1)
	await pframes(2)
	var alive0: int = _alive(men)
	troll.command_attack(men[0], true, false)
	var guard := 0
	var impact_frame := -1
	var dead_at_impact := 0
	while guard < 60 * 25:
		await get_tree().physics_frame
		guard += 1
		if troll._trample_kills > 0:
			impact_frame = guard
			dead_at_impact = alive0 - _alive(men)
			break
	verdict("B1 удар с разгона сквозь стенку копий состоялся", impact_frame > 0,
		"кадр %d" % impact_frame)
	verdict("B2 первые %d по ходу раздавлены в кадр удара" % _GobCfg.TROLL_TRAMPLE_COUNT,
		troll._trample_kills == _GobCfg.TROLL_TRAMPLE_COUNT
			and dead_at_impact >= _GobCfg.TROLL_TRAMPLE_COUNT,
		"раздавлено %d, погибло к кадру удара %d" % [troll._trample_kills, dead_at_impact])

	# ── C. Дубина: дуга, отлёт, лежание, подъём ────────────────────────────
	print("\n═════ C. ДУБИНА ═════")
	# ЖДЁМ ВЗМАХ, НАКРЫВШИЙ ДВОИХ И БОЛЬШЕ: после тарана строй разбросан
	# (трое раздавлены, остальные отлетели), и первый взмах нередко достаёт
	# только саму цель — это не поломка дуги, а пустота перед троллем. Свойство
	# дуги — «не больше шести и все впереди», его и меряем на первом же
	# взмахе, где впереди стояло больше одного
	var swept: Array = []
	var pos0: Dictionary = {}
	var swings_seen := 0
	var max_seen := 0
	guard = 0
	while guard < 60 * 30:
		await get_tree().physics_frame
		guard += 1
		if troll.last_sweep_count > 0 and troll.last_sweep_count != max_seen:
			swings_seen += 1
		max_seen = maxi(max_seen, troll.last_sweep_count)
		if troll.last_sweep_count >= 2:
			swept = (troll.last_sweep_units as Array).duplicate()
			for u in swept:
				if is_instance_valid(u):
					pos0[u] = (u as Unit).global_position
			break
	var n_sw: int = swept.size()
	verdict("C1 удар дубиной накрывает от 2 до %d бойцов" % _GobCfg.TROLL_SWEEP_COUNT,
		n_sw >= 2 and n_sw <= _GobCfg.TROLL_SWEEP_COUNT,
		"накрыто %d (взмахов до этого %d, кадр %d)" % [n_sw, swings_seen, guard])
	# Все накрытые — ВПЕРЕДИ по взгляду тролля в момент удара
	var tp: Vector3 = troll.global_position
	var look: Vector3 = troll.last_sweep_look
	var ahead := 0
	for u in swept:
		if not is_instance_valid(u):
			continue
		var off: Vector3 = Vector3(pos0[u]) - tp
		off.y = 0.0
		var d: float = off.length()
		if d < 0.2 or (off.x * look.x + off.z * look.z) / d >= _GobCfg.TROLL_SWEEP_ARC_COS - 0.05:
			ahead += 1
	verdict("C2 все накрытые стояли в дуге перед спрайтом", n_sw > 0 and ahead == n_sw,
		"впереди %d из %d" % [ahead, n_sw])
	var down_now := 0
	var hidden := 0
	var with_body := 0
	for u in swept:
		if not is_instance_valid(u) or (u as Unit).is_dead():
			continue
		var un: Unit = u
		if un.is_down():
			down_now += 1
		if not un._far_registered:
			hidden += 1
		if un._down_prop != null:
			with_body += 1
	verdict("C3 накрытые сбиты с ног: лежат, слот отрисовки снят, на месте лежит тело",
		down_now >= 2 and hidden == down_now and with_body == down_now,
		"лежат %d, скрыты %d, с телом %d" % [down_now, hidden, with_body])
	# ТРОЛЛЬ ЗАМИРАЕТ: следующий взмах (раз в 1.4 с) снова уложил бы тех же
	# бойцов и продлил лежание — и C6 мерил бы очередной удар, а не подъём.
	# Тик снят, тело на месте: копейщикам есть на кого идти в бой (C7)
	troll.set_tick(false)
	# Отлёт: через полсекунды они дальше от тролля, чем были
	await pframes(30)
	var flew := 0
	var far_max := 0.0
	for u in swept:
		if not is_instance_valid(u) or (u as Unit).is_dead():
			continue
		var moved: float = ((u as Unit).global_position - Vector3(pos0[u])).length()
		far_max = maxf(far_max, moved)
		if moved >= 0.8:
			flew += 1
	verdict("C4 накрытые ОТЛЕТЕЛИ (не меньше 0.8 м за полсекунды)", flew >= 1,
		"отлетело %d, дальний сдвиг %.2f м" % [flew, far_max])
	# Пока лежат — не встают раньше срока
	verdict("C5 через полсекунды ещё лежат", down_now == 0 or _down_count(swept) >= 1,
		"лежат %d" % _down_count(swept))
	# Подъём: после TROLL_KNOCKDOWN_SEC + запас все живые встали и снова в бою
	await pframes(int(_GobCfg.TROLL_KNOCKDOWN_SEC * 60.0) + 30)
	var still_down: int = _down_count(swept)
	var up_drawn := 0
	var up_alive := 0
	var fighting := 0
	for u in swept:
		if not is_instance_valid(u) or (u as Unit).is_dead():
			continue
		var un: Unit = u
		up_alive += 1
		if un._far_registered and un._down_prop == null:
			up_drawn += 1
		if un.attack_target != null or un.state == Unit.State.ATTACKING or un.state == Unit.State.MOVING:
			fighting += 1
	verdict("C6 по истечении срока все живые встали: слот вернулся, тело снято",
		still_down == 0 and up_alive > 0 and up_drawn == up_alive,
		"живых %d, нарисованы %d, лежат %d" % [up_alive, up_drawn, still_down])
	# Тролль оживает. До 10.09.2026 вставшим было с кем драться и при
	# замороженном тролле — шла подмога на трети запаса; у стартового стража
	# её больше нет (агро-цепочка), а сам тролль после прорыва стоит в 5-7 м —
	# вне копья и вне авто-агро обороны. Свойство «встал и снова боеспособен»
	# меряем приказом: лежащий приказ не исполняет, вставший идёт и бьёт
	troll.set_tick(true)
	var d0: Dictionary = {}
	for u in swept:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			d0[u] = (u as Unit).global_position.distance_to(troll.global_position)
			(u as Unit).command_attack(troll, true, true)
	await pframes(45)
	fighting = 0
	for u in swept:
		if not is_instance_valid(u) or (u as Unit).is_dead():
			continue
		var un2: Unit = u
		var closer: bool = un2.global_position.distance_to(troll.global_position) < float(d0[u]) - 0.3
		if un2.attack_target != null and (un2.state == Unit.State.ATTACKING or closer or un2.global_position.distance_to(troll.global_position) <= un2.attack_range + 1.5):
			fighting += 1
	verdict("C7 вставшие снова идут в бой", up_alive > 0 and fighting >= 1,
		"в бою %d из %d" % [fighting, up_alive])

	# ── D. Визуал урона тролля ──────────────────────────────────────────────
	print("\n═════ D. ВИЗУАЛ УРОНА ═════")
	var sp_unit: Unit = null
	for m in men:
		if is_instance_valid(m) and not (m as Unit).is_dead():
			sp_unit = m
			break
	var peak_ok: bool = troll.hit_flash_peak() < Unit.HIT_FLASH_PEAK * 0.5 \
		and (sp_unit == null or sp_unit.hit_flash_peak() > troll.hit_flash_peak())
	# ── D1 РАЗВЁРНУТ СПРИНТОМ 15: «усилить красный оттенок при уроне» ──────
	# Прежде проверялось, что пик вспышки тролля ВДВОЕ НИЖЕ общего (его
	# засвечивали десятки стрел). Владелец попросил обратного: вспышка ярче и
	# КРАСНАЯ. Цвет — свойство ленты (Unit.hit_flash_color), пик — не ниже
	# половины общего и не выше него
	# ── D1 РАЗВЁРНУТ ВНОВЬ (спринт 18, третье письмо): «оверлей очень мягкий,
	# едва заметный; насыщенный красный проявляется по мере падения HP» —
	# пик вспышки не выше 0.1 (TROLL_FLASH_PEAK 0.07), цвет по-прежнему красный,
	# насыщенность даёт окровавленность шейдера, а не вспышка
	verdict("D1 вспышка тролля едва заметна (пик ≤ 0.1) и красная",
		troll.hit_flash_peak() <= 0.1 and troll.hit_flash_peak() > 0.0
		and troll.hit_flash_color().r > 0.8 and troll.hit_flash_color().g < 0.4,
		"пик %.2f, цвет %s" % [troll.hit_flash_peak(), str(troll.hit_flash_color())])
	# 10.09.2026: процедурные пятна СНЯТЫ и у тролля — он просто краснеет
	# общей подкраской раненого (COLOR.a → wound_*)
	verdict("D2 пятна крови выключены у всех: тролль краснеет подкраской, а не пятнами",
		troll.blood_spots() == 0.0 and (sp_unit == null or sp_unit.blood_spots() == 0.0))
	verdict("D2б темп ударов тролля +20 % (кулдаун не выше 1.4 / 1.2)",
		troll.attack_cooldown <= 1.4 / 1.2 + 1e-3, "кулдаун %.3f" % troll.attack_cooldown)
	var sh := load("res://shaders/mm_unit_sprite.gdshader") as Shader
	verdict("D3 шейдер спрайта знает пятна крови (uniform blood_spots)",
		sh != null and sh.code.find("uniform float blood_spots") >= 0)
	# Uniform доехал до бакета тролля
	await frames(6)
	var slot = troll._far_slot
	var got := -1.0
	if slot != null and slot.bucket != null and slot.bucket.mat != null:
		got = float(slot.bucket.mat.get_shader_parameter("blood_spots"))
	verdict("D4 бакет тролля получил blood_spots = %.1f" % troll.blood_spots(),
		is_equal_approx(got, troll.blood_spots()), "в материале %.2f" % got)

func _down_count(list: Array) -> int:
	var n := 0
	for u in list:
		if is_instance_valid(u) and not (u as Unit).is_dead() and (u as Unit).is_down():
			n += 1
	return n
