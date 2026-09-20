extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД qa_audio_update — AUDIO SYSTEM UPDATE (ТЗ 19.09.2026)
## ═══════════════════════════════════════════════════════════════════════════
##   A. банк: пулы рыцарей (angry ×4, excited) и нарезка пака (тролль / туши /
##      мелкие) — категории, файлы, лимиты с shuffle;
##   B. shuffle: файл не повторяется подряд; squad_voice: окно на отряд,
##      один жребий на окно, шанс;
##   C. рыцари: выкрик на ПЕРВЫЙ удар «Яростной атаки» и только один на отряд
##      в окне; «Excited» при добивании последнего врага отряда;
##   D. монстры: грюнт тролля на удар и на урон, туши — на свип и урон,
##      гоблины — на урон и марш (хуки открывают окно; сам звук — жребий).
## Запуск: godot --headless --path . res://qa_audio_update/Test.tscn

const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")
const F := Constants.FACTION_PLAYER
const G := Constants.FACTION_GOBLIN

var main = null
var _pass := 0
var _fail := 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(240.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 240 с")
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
	print("\n═════ ИТОГ qa_audio_update: прошло %d, провалов: %d ═════" % [_pass, _fail])
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
		var u: Unit = _spawn(kind, fac, Vector3(at.x + float(i % cols) * 0.8, 0.0, at.z + float(i / cols) * 0.9))
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return [sid, men]

func _cnt(cat: String) -> int:
	return int(AudioManager.sfx_trace_counts.get(cat, 0))

func _files_ok(cat: String) -> bool:
	var fv: Variant = AudioManager.SFX_BANK.get(cat)
	if fv == null or (fv as Array).is_empty():
		return false
	for f in (fv as Array):
		if not ResourceLoader.exists(AudioManager.sfx_path(String(f))):
			print("    нет файла: %s" % String(f))
			return false
	return true

func _alive(arr: Array) -> int:
	var n := 0
	for u in arr:
		if is_instance_valid(u) and not (u as Unit).is_dead():
			n += 1
	return n

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	main.enemy_ai.set_process(false)
	main.goblin_ai.set_process(false)
	if main.get("gnoll_ai") != null:
		main.gnoll_ai.set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	GameManager.world_bounds_enabled = false
	AudioManager.enabled = true
	AudioManager.sfx_trace = true
	for n in get_tree().get_nodes_in_group("all_units"):
		if is_instance_valid(n) and n is Unit:
			(n as Unit).take_damage(1.0e12)
	await pframes(6)
	var base := Vector3(0.0, 0.0, -400.0)

	print("\n═════ A. БАНК ═════")
	verdict("A1 knight_angry — четыре файла, все на месте", (AudioManager.SFX_BANK["knight_angry"] as Array).size() == 4 and _files_ok("knight_angry"))
	verdict("A2 knight_victory — один файл на месте", (AudioManager.SFX_BANK["knight_victory"] as Array).size() == 1 and _files_ok("knight_victory"))
	var nt: int = (AudioManager.SFX_BANK["troll_grunt"] as Array).size()
	var nb: int = (AudioManager.SFX_BANK["big_grunt"] as Array).size()
	var ns: int = (AudioManager.SFX_BANK["goblin_grunt"] as Array).size()
	verdict("A3 нарезка пака: тролль ≥ 12, туши ≥ 5, мелкие ≥ 10 сэмплов, все файлы на месте",
		nt >= 12 and nb >= 5 and ns >= 10 and _files_ok("troll_grunt") and _files_ok("big_grunt") and _files_ok("goblin_grunt"),
		"тролль %d, туши %d, мелкие %d" % [nt, nb, ns])
	var lim_ok := true
	for cat in ["knight_angry", "troll_grunt", "big_grunt", "goblin_grunt"]:
		var lim: Dictionary = AudioManager.SFX_LIMITS.get(cat, {})
		if not bool(lim.get("shuffle", false)) or float(lim.get("gap", 0.0)) <= 0.0:
			lim_ok = false
	verdict("A4 у пулов shuffle и пауза категории", lim_ok)
	verdict("A5 шанс грюнта 25-35 %%, кулдаун отряда 1.5-2 с (конфиг)",
		AudioManager.GRUNT_CHANCE >= 0.25 and AudioManager.GRUNT_CHANCE <= 0.35
		and AudioManager.GRUNT_SQUAD_GAP >= 1.5 and AudioManager.GRUNT_SQUAD_GAP <= 2.0,
		"шанс %.2f, окно %.2f" % [AudioManager.GRUNT_CHANCE, AudioManager.GRUNT_SQUAD_GAP])
	# Сэмплы нарезки короткие (грюнт, а не кусок пака)
	var long_ok := true
	for cat in ["troll_grunt", "big_grunt", "goblin_grunt"]:
		for f in (AudioManager.SFX_BANK[cat] as Array):
			var st: AudioStream = load(AudioManager.sfx_path(String(f)))
			if st == null or st.get_length() > 3.0 or st.get_length() < 0.1:
				long_ok = false
	verdict("A6 каждый сэмпл нарезки — 0.1…3 с", long_ok)

	print("\n═════ B. SHUFFLE И ОКНО ОТРЯДА ═════")
	# У слушателя: дальний звук отсекается до пула (SFX_CULL_DISTANCE)
	var lis: Node3D = AudioManager._listener_node()
	var near: Vector3 = lis.global_position if lis != null else base
	var repeats := 0
	var prev: int = -1
	var played := 0
	# Пул мелких грюнтов: сэмплы короткие, голоса освобождаются между
	# запусками (в headless dummy-драйвер играет в реальном времени)
	for i in range(16):
		AudioManager._cat_last.erase("goblin_grunt")
		if AudioManager.play_3d("goblin_grunt", near):
			played += 1
			var cur: int = AudioManager.last_file_index("goblin_grunt")
			if cur == prev:
				repeats += 1
			prev = cur
		await get_tree().create_timer(0.3).timeout
	verdict("B1 shuffle: 16 запусков, ни одного повтора файла подряд", played >= 12 and repeats == 0,
		"прозвучало %d, повторов %d" % [played, repeats])
	# Окно отряда: сто вызовов в один кадр — одно окно, один жребий
	var c0: int = AudioManager.squad_voice_calls
	var p0: int = AudioManager.squad_voice_played
	for i in range(100):
		AudioManager.squad_voice("goblin_grunt", 777001, near, 1.0, 1.75)
	verdict("B2 сто вызовов в кадр одним отрядом — одно окно, один звук",
		AudioManager.squad_voice_calls - c0 == 1 and AudioManager.squad_voice_played - p0 == 1)
	# Шанс: при 0.0 не звучит никогда, окно всё равно открывается
	p0 = AudioManager.squad_voice_played
	AudioManager.squad_voice("goblin_grunt", 777002, base, 0.0, 1.75)
	verdict("B3 шанс 0 — окно открыто, звука нет", AudioManager.squad_voice_played == p0)
	# Разные отряды — свои окна
	c0 = AudioManager.squad_voice_calls
	AudioManager.squad_voice("goblin_grunt", 777003, base, 1.0, 1.75)
	AudioManager.squad_voice("goblin_grunt", 777004, base, 1.0, 1.75)
	verdict("B4 два отряда — два окна", AudioManager.squad_voice_calls - c0 == 2)

	print("\n═════ C. РЫЦАРИ ═════")
	var kn: Array = _squad("warrior", F, base + Vector3(0.0, 0.0, 0.0), 8)
	var gob: Array = _squad("goblin_spearman", G, base + Vector3(0.0, 0.0, 14.0), 3)
	for u in gob[1]:
		(u as Unit).set_tick(false)
	await pframes(4)
	var a0: int = _cnt("knight_angry")
	for u in kn[1]:
		(u as Warrior).start_rage_dash()
		(u as Unit).command_attack(gob[1][0], true, false, true)
	var first_hit := -1
	var shout_at := -1
	for f in range(60 * 20):
		await get_tree().physics_frame
		var hits := 0
		for u in kn[1]:
			hits += int((u as Unit).get("hits_released")) if (u as Unit).get("hits_released") != null else 0
		var sh := 0
		for u in kn[1]:
			sh += int((u as Warrior).angry_shouts)
		if first_hit < 0 and _alive(gob[1]) < 3:
			first_hit = f
		if shout_at < 0 and sh > 0:
			shout_at = f
		if shout_at >= 0 and first_hit >= 0:
			break
	var shouts := 0
	for u in kn[1]:
		shouts += int((u as Warrior).angry_shouts)
	verdict("C1 выкрик взведён рывком и снят первым ударом (у ударивших — по одному)", shouts >= 1 and shouts <= 8,
		"взведений снято %d, кадр %d" % [shouts, shout_at])
	verdict("C2 «Angry» прозвучал ровно один раз на отряд (окно %.1f с)" % AudioManager.KNIGHT_ANGRY_GAP,
		_cnt("knight_angry") - a0 == 1, "прозвучало %d" % (_cnt("knight_angry") - a0))
	# Победа: добиваем отряд гоблинов до последнего
	var v0: int = _cnt("knight_victory")
	var ev0: int = GameManager.knight_victory_events
	for f in range(60 * 30):
		await get_tree().physics_frame
		if _alive(gob[1]) == 0:
			break
	await pframes(2)
	verdict("C3 последний гоблин добит мечником — «Excited» в момент гибели",
		_alive(gob[1]) == 0 and GameManager.knight_victory_events - ev0 == 1 and _cnt("knight_victory") - v0 == 1,
		"живых %d, событий %d, звуков %d" % [_alive(gob[1]), GameManager.knight_victory_events - ev0, _cnt("knight_victory") - v0])
	for u in kn[1]:
		(u as Unit).take_damage(1.0e12)
	await pframes(2)

	print("\n═════ D. МОНСТРЫ ═════")
	# Тролль под стрелами: урон открывает окна troll_grunt
	GameManager.troll_lair = null
	var troll: Unit = _spawn("troll", G, base + Vector3(40.0, 0.0, 0.0))
	troll.set_tick(false)
	var arch: Array = _squad("archer", F, base + Vector3(40.0, 0.0, 14.0), 8)
	await pframes(4)
	var c_troll0: int = AudioManager.squad_voice_calls
	var t_hurt0: int = _cnt("troll_grunt")
	for u in arch[1]:
		(u as Unit).command_attack(troll, true, false, true)
	await pframes(60 * 8)
	verdict("D1 тролль под обстрелом открывает окна грюнта (урон → троллевый пул)",
		AudioManager.squad_voice_calls - c_troll0 >= 3, "окон %d, прозвучало %d" % [AudioManager.squad_voice_calls - c_troll0, _cnt("troll_grunt") - t_hurt0])
	for u in arch[1]:
		(u as Unit).take_damage(1.0e12)
	# Тролль бьёт: свип дубиной открывает окно
	var sp: Array = _squad("spearman", F, base + Vector3(40.0, 0.0, 3.0), 6)
	for u in sp[1]:
		(u as Unit).set_tick(false)
		(u as Unit).max_health = 1.0e9
		(u as Unit).current_health = 1.0e9
		(u as Unit)._soa_push_stats()
	troll.set_tick(true)
	troll.command_attack(sp[1][0], true, false, true)
	await pframes(2)
	c_troll0 = AudioManager.squad_voice_calls
	var t_cat0: int = _cnt("troll_grunt")
	await pframes(60 * 10)
	verdict("D2 удары дубиной открывают окна грюнта тролля", AudioManager.squad_voice_calls - c_troll0 >= 2,
		"окон %d, прозвучало %d" % [AudioManager.squad_voice_calls - c_troll0, _cnt("troll_grunt") - t_cat0])
	troll.take_damage(1.0e12)
	for u in sp[1]:
		(u as Unit).take_damage(1.0e12)
	await pframes(2)
	# Туша: урон и свип
	var big: Unit = _spawn("big_goblin", G, base + Vector3(-40.0, 0.0, 0.0))
	big.set_tick(false)
	var sp2: Array = _squad("spearman", F, base + Vector3(-40.0, 0.0, 3.0), 6)
	for u in sp2[1]:
		(u as Unit).max_health = 1.0e9
		(u as Unit).current_health = 1.0e9
		(u as Unit)._soa_push_stats()
	await pframes(4)
	var c_big0: int = AudioManager.squad_voice_calls
	var b_cat0: int = _cnt("big_grunt")
	for u in sp2[1]:
		(u as Unit).command_attack(big, true, false, true)
	await pframes(60 * 6)
	var hurt_windows: int = AudioManager.squad_voice_calls - c_big0
	verdict("D3 туша под ударами открывает окна big_grunt", hurt_windows >= 2, "окон %d, прозвучало %d" % [hurt_windows, _cnt("big_grunt") - b_cat0])
	big.take_damage(1.0e12)
	for u in sp2[1]:
		(u as Unit).take_damage(1.0e12)
	await pframes(2)
	# Гоблины: приказ марша открывает окно goblin_grunt (раз на отряд)
	var gs: Array = _squad("goblin_spearman", G, base + Vector3(0.0, 0.0, -40.0), 12)
	await pframes(4)
	var c_g0: int = AudioManager.squad_voice_calls
	for u in gs[1]:
		(u as Unit).command_move(base + Vector3(30.0, 0.0, -40.0), false, Vector3.ZERO, false, true)
	verdict("D4 приказ марша отряду гоблинов — ровно одно окно на отряд",
		AudioManager.squad_voice_calls - c_g0 == 1, "окон %d" % (AudioManager.squad_voice_calls - c_g0))
	c_g0 = AudioManager.squad_voice_calls
	for u in gs[1]:
		(u as Unit).command_move((u as Unit).global_position, false, Vector3.ZERO, false, true)
	verdict("D5 «встать здесь» окна не открывает", AudioManager.squad_voice_calls - c_g0 == 0)
	# Люди грюнтов не имеют: спавн копейщика и удар по нему окон не открывает
	var hum: Unit = _spawn("spearman", F, base + Vector3(60.0, 0.0, -40.0))
	var gob2: Unit = _spawn("goblin_spearman", G, base + Vector3(60.0, 0.0, -38.0))
	gob2.set_tick(false)
	await pframes(2)
	c_g0 = AudioManager.squad_voice_calls
	hum.take_damage(5.0, gob2)
	hum.command_move(base + Vector3(60.0, 0.0, 0.0), false, Vector3.ZERO, false, true)
	verdict("D6 у людей грюнтов нет: урон и марш копейщика окон не открывают", AudioManager.squad_voice_calls - c_g0 == 0)
	_finish()
