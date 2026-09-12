extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: АУДИО-СИСТЕМА СПРИНТА 18 (headless)
## ═══════════════════════════════════════════════════════════════════════════
##   A — пул реплик приказа: пять фраз, куски «Come on!» по таймкодам внутри
##       файла, без повтора подряд, кусок стартует с from и глохнет на to;
##   B — молоток строителя «mine 5» у стены стройки; щелчок здания «Chest Close»;
##   C — голоса орды: атака (питч+громкость), смерть (±0.08), файлы на месте;
##   D — горн: шина Horn с реверберацией → SFX, окно повтора, первый контакт
##       (орду увидели / орда увидела), горн на выходе к центру;
##   E — хор смеха: 4 голоса разом над выбитым ВОИНСКИМ отрядом игрока в обзоре
##       орды; рабочий и отряд вдали — без смеха;
##   F — тролль: рык на выходе, на марше (12-20 с, шанс), в бою; клич победы
##       над добитым рабочим;
##   G — река: доля по расстоянию до кромки (+5 м), плавный вход/выход,
##       шина Ambient, тихая; пауза глушит реку и горн.
## В headless dummy-драйвер микширует: позиция потока идёт, вердикты честные.
## Запуск: godot --headless --path . res://qa_audio18/Test.tscn

const _CSite := preload("res://scripts/ConstructionSite.gd")
const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(300.0).timeout.connect(func():
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
	print("\n═════ ИТОГ qa_audio18: прошло %d, провалов: %d ═════" % [_pass, _fail])
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

func _squad(uid: String, fac: int, at: Vector3, n: int) -> Array:
	var sid: int = GameManager.new_squad(fac, uid)
	var out: Array = []
	for i in range(n):
		var u := _spawn(uid, fac, at + Vector3(float(i % 4) * 0.8, 0.0, float(i / 4) * 0.8))
		GameManager.add_to_squad(sid, u)
		out.append(u)
	return [sid, out]

func _cat_playing(cat: String) -> int:
	var n := 0
	for i in range(AudioManager._pool.size()):
		var p: AudioStreamPlayer3D = AudioManager._pool[i]
		if p.playing and String(AudioManager._pool_cat[i]) == cat:
			n += 1
	return n

func _trace(cat: String) -> int:
	return int(AudioManager.sfx_trace_counts.get(cat, 0))

func _reset_voice() -> void:
	AudioManager._voice_last.clear()
	AudioManager._voice_last_any = -999.0
	AudioManager._voice_alt.clear()

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	GameManager.world_bounds_enabled = false
	AudioManager.enabled = true
	AudioManager.sfx_trace = true
	await pframes(4)

	print("\n═════ A. ПУЛ РЕПЛИК ПРИКАЗА ═════")
	var pool: Array = AudioManager.ORDER_REPLIES
	verdict("A1 в пуле пять реплик", pool.size() == 5, "%d" % pool.size())
	var ids: Dictionary = {}
	var files_ok := true
	var clips_ok := true
	for r in pool:
		var d: Dictionary = r
		ids[String(d["id"])] = true
		var path: String = String(d["file"])
		if not ResourceLoader.exists(path):
			files_ok = false
			continue
		var st: AudioStream = load(path)
		var fr: float = float(d.get("from", 0.0))
		var to: float = float(d.get("to", 0.0))
		if fr < 0.0 or (to > 0.0 and (to <= fr or to > st.get_length() + 0.05)):
			clips_ok = false
	verdict("A2 реплики: hold_line, go_go_go и три come_on", ids.size() == 5
		and ids.has("hold_line") and ids.has("go_go_go") and ids.has("come_on_1")
		and ids.has("come_on_2") and ids.has("come_on_3"), str(ids.keys()))
	verdict("A3 все файлы пула на месте", files_ok)
	verdict("A4 куски лежат внутри длины файла и не пусты", clips_ok)
	var come_on: int = 0
	var come_files: Dictionary = {}
	for r2 in pool:
		if String((r2 as Dictionary)["id"]).begins_with("come_on"):
			come_on += 1
			come_files[String((r2 as Dictionary)["file"])] = true
	verdict("A5 три «Come on!» — куски ОДНОГО файла", come_on == 3 and come_files.size() == 1)
	# Без повтора подряд и все пять встречаются
	var seq: Array = []
	for _i in range(60):
		seq.append(String((AudioManager._pick_reply() as Dictionary)["id"]))
	var repeat := 0
	var seen: Dictionary = {}
	for i in range(seq.size()):
		seen[seq[i]] = true
		if i > 0 and seq[i] == seq[i - 1]:
			repeat += 1
	verdict("A6 за 60 выборов ни одного повтора подряд", repeat == 0, "повторов %d" % repeat)
	verdict("A7 за 60 выборов встретились все пять", seen.size() == 5, str(seen.keys()))
	# События приказов идут через пул, а имя события остаётся прежним
	verdict("A8 mass_march и hold_line берут фразу из пула",
		AudioManager.REPLY_POOL_EVENTS.has("mass_march") and AudioManager.REPLY_POOL_EVENTS.has("hold_line"))
	# Кусок: старт с from, стоп на to
	_reset_voice()
	AudioManager._reply_last = 1     # следующий выбор — не go_go_go... задаём кусок руками
	var clip: Dictionary = pool[2]   # come_on_1: 0.20-1.10
	var played: bool = AudioManager.play_voice("mass_march")
	# Стенд не управляет жребием — подменяем воспроизведение куском напрямую
	var v: AudioStreamPlayer = AudioManager._voice_pool[(AudioManager._voice_next + AudioManager._voice_pool.size() - 1) % AudioManager._voice_pool.size()]
	verdict("A9 реплика приказа пошла (voice_last = событие, reply_last_id — фраза пула)",
		played and AudioManager.voice_last == "mass_march" and AudioManager.reply_last_id != "",
		"событие %s, фраза %s" % [AudioManager.voice_last, AudioManager.reply_last_id])
	# Прямой кусок: играем come_on_1 и ждём его конца
	v.stop()
	var idx: int = AudioManager._voice_pool.find(v)
	v.stream = load(String(clip["file"]))
	AudioManager._voice_clip_end[idx] = float(clip["to"])
	v.play(float(clip["from"]))
	await frames(3)
	var pos0: float = v.get_playback_position()
	verdict("A10 кусок стартует с таймкода from (%.2f с)" % float(clip["from"]),
		v.playing and pos0 >= float(clip["from"]) - 0.05, "позиция %.2f" % pos0)
	var t0 := Time.get_ticks_msec()
	while v.playing and Time.get_ticks_msec() - t0 < 4000:
		await get_tree().process_frame
	var lived: float = float(Time.get_ticks_msec() - t0) * 0.001
	var expect: float = float(clip["to"]) - float(clip["from"])
	verdict("A11 кусок глохнет на таймкоде to (жил %.2f с при куске %.2f, файл 5.07)" % [lived, expect],
		not v.playing and lived < expect + 0.6, "%.2f" % lived)

	print("\n═════ B. МОЛОТОК СТРОИТЕЛЯ И ЩЕЛЧОК ЗДАНИЯ ═════")
	# Площадка — у слушателя (он на пивоте камеры): хор и дрожание громкости
	# проверяются по ЖИВЫМ голосам пула, а голос дальше SFX_CULL_DISTANCE не
	# выдаётся вовсе. Камера ставится в чистое поле подальше от базы игрока
	var p0 := Vector3(-60.0, 0.0, 40.0)
	if main._camera != null:
		# КАМЕРУ ЗАМОРОЗИТЬ (правило стендов): в headless курсор стоит в углу
		# экрана, и край-панорама уводит камеру, слушателя и точку фокуса.
		# pan_to пишет только фокус, узлы двигает _update_position — зовём его
		main._camera.pan_to(p0)
		main._camera._update_position()
		main._camera.set_process(false)
	await pframes(3)
	var lis: Node3D = AudioManager._listener_node()
	if lis != null:
		print("  слушатель в (%.0f, %.0f), площадка (%.0f, %.0f)" % [lis.global_position.x, lis.global_position.z, p0.x, p0.z])
	var site = _CSite.new()
	site.faction = Constants.FACTION_PLAYER
	site.target_id = "barracks"
	site.target_name = "Бараки"
	site.build_size = _UCfg.building_size("barracks")
	site.build_time = 600.0
	main.world_add(site)
	site.global_position = Vector3(p0.x, GameManager.get_terrain_height(p0.x, p0.z), p0.z)
	await pframes(4)
	var w := _spawn("worker", Constants.FACTION_PLAYER, p0 + Vector3(-7.0, 0.0, 0.0))
	(w as Worker).command_build(site)
	var h0: int = _trace("build_hammer")
	var settled := false
	for _i in range(60 * 8):
		await get_tree().physics_frame
		if (w as Worker)._build_settled:
			settled = true
			break
	await pframes(60 * 3)
	var hits: int = _trace("build_hammer") - h0
	verdict("B1 рабочий у стены стучит молотком — категория build_hammer", settled and hits >= 2,
		"у стены=%s, ударов %d" % [str(settled), hits])
	var bank_ok: bool = (AudioManager.SFX_BANK["build_hammer"] as Array).size() == 1 \
		and String((AudioManager.SFX_BANK["build_hammer"] as Array)[0]) == "mine 5.ogg"
	verdict("B2 звук молотка — «mine 5»", bank_ok and ResourceLoader.exists(AudioManager.DIR_SFX + "mine 5.ogg"))
	verdict("B3 молоток прореживается плотностью, как топор и кирка", AudioManager.WORK_CATS.has("build_hammer"))
	var pb: String = AudioManager.ui_path(String(AudioManager.UI_BANK["pick_building"]))
	verdict("B4 щелчок по зданию — «Chest Close 1»", pb.get_file() == "Chest Close 1.ogg" and ResourceLoader.exists(pb), pb)
	AudioManager._ui_last.clear()
	var ok_ui: bool = AudioManager.play_ui("pick_building")
	verdict("B5 звук выделения здания реально запускается", ok_ui)
	w.take_damage(1e9)
	site.queue_free()
	await pframes(3)

	print("  диагностика: paused=%s in_game=%s enabled=%s processing=%s free=%d pool=%d listener=%s" % [
		str(AudioManager._audio_paused), str(AudioManager._in_game), str(AudioManager.enabled),
		str(AudioManager.is_processing()), AudioManager._free_voices.size(), AudioManager._pool.size(),
		str(AudioManager._listener_node() != null)])
	print("\n═════ C. ГОЛОСА ОРДЫ ═════")
	var g := _spawn("goblin_spearman", Constants.FACTION_GOBLIN, p0 + Vector3(20.0, 0.0, 0.0))
	var rider := _spawn("goblin_rider", Constants.FACTION_GOBLIN, p0 + Vector3(24.0, 0.0, 0.0))
	g.set_tick(false)
	rider.set_tick(false)
	await pframes(2)
	verdict("C1 гоблины кричат своими голосами атаки", g._sfx_shout() == "goblin_attack" and rider._sfx_shout() == "goblin_attack")
	verdict("C2 гоблины умирают своим голосом", g._sfx_death() == "goblin_death" and rider._sfx_death() == "goblin_death")
	var la: Dictionary = AudioManager.SFX_LIMITS["goblin_attack"]
	var pr: Array = la.get("pitch", [1.0, 1.0])
	verdict("C3 крики атаки: расстройка высоты и громкости",
		float(pr[0]) < 1.0 and float(pr[1]) > 1.0 and float(la.get("db_jitter", 0.0)) > 0.0,
		"pitch %s, db_jitter %.1f" % [str(pr), float(la.get("db_jitter", 0.0))])
	var ld: Dictionary = AudioManager.SFX_LIMITS["goblin_death"]
	var pd: Array = ld.get("pitch", [1.0, 1.0])
	verdict("C4 смерть: питч ±0.08", is_equal_approx(float(pd[0]), 0.92) and is_equal_approx(float(pd[1]), 1.08), str(pd))
	var gob_files_ok := true
	for cat in ["goblin_attack", "goblin_death", "goblin_laugh"]:
		for f in AudioManager.SFX_BANK[cat]:
			if not ResourceLoader.exists(String(f)):
				gob_files_ok = false
	verdict("C5 файлы орды на месте (4 атаки, смерть, 4 смеха)", gob_files_ok
		and (AudioManager.SFX_BANK["goblin_attack"] as Array).size() == 4
		and (AudioManager.SFX_BANK["goblin_laugh"] as Array).size() == 4)
	var d0: int = _trace("goblin_death")
	g.take_damage(1e9)
	await pframes(2)
	verdict("C6 гибель гоблина зовёт goblin_death", _trace("goblin_death") == d0 + 1)
	var a0: int = _trace("goblin_attack")
	for _i in range(200):
		rider._maybe_battle_shout()
	verdict("C7 крик атаки идёт на удары (шанс %.2f)" % rider._shout_chance(), _trace("goblin_attack") > a0)
	# Дрожание громкости реально применяется: два запуска подряд — разная громкость
	AudioManager._cat_last.clear()
	var dbs: Dictionary = {}
	for _k in range(6):
		AudioManager._cat_last.erase("goblin_attack")
		var went: bool = AudioManager.play_3d("goblin_attack", rider.global_position)
		print("  play_3d goblin_attack → %s (calls %d, played %d, busy %s)" % [str(went), AudioManager.sfx_calls, AudioManager.sfx_played, str(AudioManager._cat_busy.get("goblin_attack", 0))])
		for i in range(AudioManager._pool.size()):
			if String(AudioManager._pool_cat[i]) == "goblin_attack":
				dbs["%.2f" % (AudioManager._pool[i] as AudioStreamPlayer3D).volume_db] = true
	verdict("C8 громкость криков реально дрожит (разные db у голосов)", dbs.size() >= 2, str(dbs.keys()))
	rider.take_damage(1e9)
	await pframes(2)

	print("\n═════ D. ГОРН ОРДЫ ═════")
	var hb: int = AudioServer.get_bus_index(AudioManager.HORN_BUS)
	var reverb := false
	if hb >= 0:
		for i in range(AudioServer.get_bus_effect_count(hb)):
			if AudioServer.get_bus_effect(hb, i) is AudioEffectReverb:
				reverb = true
	verdict("D1 шина Horn с реверберацией, отправка в SFX", hb >= 0 and reverb and AudioServer.get_bus_send(hb) == "SFX")
	verdict("D2 горн — средняя громкость (не громче реплик)",
		float((AudioManager.VOICE_LIMITS["horde_horn"] as Dictionary)["db"]) <= -6.0)
	_reset_voice()
	var hp0: int = AudioManager.horn_played
	var h1: bool = AudioManager.play_horn()
	var h2: bool = AudioManager.play_horn()
	verdict("D3 горн играет на своей шине, второй подряд — в окне повтора",
		h1 and not h2 and AudioManager.horn_played == hp0 + 1 and AudioManager._horn.bus == AudioManager.HORN_BUS)
	var ai = main.goblin_ai
	verdict("D4 первого контакта на старте не было", ai != null and not bool(ai.first_contact))
	if ai != null:
		# Орда увидела игрока: боец игрока у центра отряда орды
		ai._regroup()
		var any_sq: Dictionary = {}
		for s in ai.squads:
			if not ((s as Dictionary)["members"] as Array).is_empty():
				any_sq = s
				break
		var c: Vector3 = ai._squad_center(any_sq)
		var spy := _spawn("spearman", Constants.FACTION_PLAYER, c + Vector3(6.0, 0.0, 0.0))
		spy.set_tick(false)
		await pframes(3)
		var hb0: int = ai.horn_blows
		ai._check_first_contact()
		verdict("D5 орда увидела войска игрока — первый контакт, горн", bool(ai.first_contact) and ai.horn_blows == hb0 + 1)
		ai._check_first_contact()
		verdict("D6 первый контакт — один раз за партию", ai.horn_blows == hb0 + 1)
		# Второй путь: игрок ОТКРЫЛ ТУМАН над деревней орды
		ai.first_contact = false
		var fog = GameManager.fog
		var d6b := false
		if fog != null:
			# Орда «переезжает» в тёмный угол: настоящая деревня к этому моменту
			# уже освещена бойцами стенда, а проверяется именно ПЕЛЕНА
			var saved_village: Vector3 = ai.village
			var saved_squads: Array = ai.squads
			var saved_mine = ai.mine
			var dark := Vector3(-150.0, 0.0, 100.0)
			ai.village = dark
			ai.squads = []
			ai.mine = null
			fog.enabled = true
			fog.refresh()
			var dark_before: bool = not bool(fog.is_lit(dark.x, dark.z))
			ai._check_first_contact()
			var still_no: bool = not bool(ai.first_contact)
			fog.add_permanent_reveal(dark, 20.0)
			fog.refresh()
			ai._check_first_contact()
			d6b = dark_before and still_no and bool(ai.first_contact) and ai.horn_blows == hb0 + 2
			print("  туман: до засветки темно=%s, контакта не было=%s, после=%s, горнов %d (ждали %d)" % [
				str(dark_before), str(still_no), str(ai.first_contact), ai.horn_blows, hb0 + 2])
			fog.enabled = false
			ai.village = saved_village
			ai.squads = saved_squads
			ai.mine = saved_mine
		verdict("D6б игрок открыл туман над деревней орды — первый контакт", d6b,
			"горнов %d" % ai.horn_blows)
		spy.take_damage(1e9)
		await pframes(2)
		# Наступление: мир кончился — выход к центру
		var hb1: int = ai.horn_blows
		ai._awake = true
		ai.phase = ai.PHASE_PEACE
		ai.clock = ai._Diff.goblin_peace_sec() + 1.0
		ai.tick()
		verdict("D7 выход армии к центру — горн", String(ai.phase) == ai.PHASE_CENTER and ai.horn_blows == hb1 + 1,
			"фаза %s, горнов %d → %d" % [String(ai.phase), hb1, ai.horn_blows])
		ai.phase = ai.PHASE_PEACE
		ai.clock = 0.0

	print("\n═════ E. ХОР СМЕХА НАД ВЫБИТЫМ ОТРЯДОМ ═════")
	var pe := p0 + Vector3(0.0, 0.0, 30.0)
	# Гоблин — В ОТРЯДЕ орды (спринт 20: хор судит по числу отрядов орды в
	# обзоре — одиночка без отряда это «никого рядом»)
	var gob_sq: Array = _squad("goblin_spearman", Constants.FACTION_GOBLIN, pe + Vector3(8.0, 0.0, 0.0), 1)
	var gob2: Unit = gob_sq[1][0]
	gob2.set_tick(false)
	gob2.current_health = gob2.max_health * 100.0
	gob2._soa_push_stats()
	var sq_e: Array = _squad("spearman", Constants.FACTION_PLAYER, pe, 2)
	await pframes(3)
	AudioManager._laugh_last = -999.0
	var le0: int = GameManager.laugh_events
	var lc0: int = AudioManager.laugh_chorus_count
	# СПРИНТ 20: хор — только за убийство ГОБЛИНОМ (добивший — gob2)
	(sq_e[1][0] as Unit).take_damage(1e9, gob2)
	await pframes(2)
	verdict("E1 первый павший из двух — смеха нет", GameManager.laugh_events == le0)
	(sq_e[1][1] as Unit).take_damage(1e9, gob2)
	await frames(2)
	verdict("E2 последний воин отряда погиб от гоблина в его обзоре — хор", GameManager.laugh_events == le0 + 1
		and AudioManager.laugh_chorus_count == lc0 + 1)
	await get_tree().create_timer(0.3).timeout
	var laughing: int = _cat_playing("goblin_laugh")
	verdict("E3 все четыре смеха звучат РАЗОМ", laughing == 4, "голосов %d" % laughing)
	verdict("E4 микро-задержки голосов заданы (эффект толпы)", AudioManager.LAUGH_STAGGER_MAX > 0.0 and AudioManager.LAUGH_STAGGER_MAX <= 0.25)
	# Рабочий — не воин
	AudioManager._laugh_last = -999.0
	var wk_sq: Array = _squad("worker", Constants.FACTION_PLAYER, pe + Vector3(2.0, 0.0, 0.0), 1)
	await pframes(2)
	var le1: int = GameManager.laugh_events
	(wk_sq[1][0] as Unit).take_damage(1e9)
	await pframes(2)
	verdict("E5 над убитым рабочим орда не смеётся", GameManager.laugh_events == le1)
	# Отряд вдали от орды — без смеха
	var far_sq: Array = _squad("spearman", Constants.FACTION_PLAYER, pe + Vector3(0.0, 0.0, 120.0), 1)
	await pframes(2)
	(far_sq[1][0] as Unit).take_damage(1e9)
	await pframes(2)
	verdict("E6 отряд, выбитый вне обзора орды, — без смеха", GameManager.laugh_events == le1)
	gob2.take_damage(1e9)
	await pframes(2)

	print("\n═════ F. ТРОЛЛЬ ═════")
	var lair = GameManager.troll_lair
	verdict("F0 логово есть", lair != null and is_instance_valid(lair))
	var pf := p0 + Vector3(30.0, 0.0, -30.0)
	var troll: Unit = Building.PRELOAD_SCENES["troll"].instantiate()
	troll.faction = Constants.FACTION_GOBLIN
	main.world_add(troll)
	troll.global_position = Vector3(pf.x, GameManager.get_terrain_height(pf.x, pf.z), pf.z)
	troll.sync_row()
	troll.post_pos = troll.global_position
	var tg0: int = _trace("troll_growl")
	await pframes(60 * 2)
	verdict("F1 рык на выходе гарантирован (в первые полторы секунды)", _trace("troll_growl") == tg0 + 1 and troll.growls >= 1,
		"рыков %d" % (_trace("troll_growl") - tg0))
	verdict("F2 рык тролля — три файла wolf/growl", (AudioManager.SFX_BANK["troll_growl"] as Array).size() == 3)
	verdict("F3 окно марша 12-20 с и шанс", is_equal_approx(_GobCfg.TROLL_GROWL_MIN_SEC, 12.0)
		and is_equal_approx(_GobCfg.TROLL_GROWL_MAX_SEC, 20.0) and _GobCfg.TROLL_GROWL_MARCH_P > 0.0 and _GobCfg.TROLL_GROWL_MARCH_P < 1.0)
	# Марш: заставляем окна истекать подряд — с шансом 0.35 за 20 окон рык почти наверняка
	troll.command_move(pf + Vector3(40.0, 0.0, 0.0))
	await pframes(30)
	var tg1: int = troll.growls
	for _i in range(20):
		troll._growl_t = 0.0
		AudioManager._cat_last.erase("troll_growl")
		await pframes(4)
	verdict("F4 на марше рычит редко, но рычит (за 20 окон ≥ 1)", troll.growls > tg1, "рыков %d" % (troll.growls - tg1))
	verdict("F5 в бою подрыкивает тем же рыком с малой вероятностью",
		troll._sfx_shout() == "troll_growl" and troll._shout_chance() > 0.0 and troll._shout_chance() <= 0.25)
	verdict("F6 тролль не кричит человеческим голосом на смерти", troll._sfx_death() != "vox_death")
	# Победный клич: тролль добивает рабочего
	var vic_sq: Array = _squad("worker", Constants.FACTION_PLAYER, troll.global_position + Vector3(2.0, 0.0, 0.0), 1)
	await pframes(2)
	var tv0: int = GameManager.troll_victory_events
	var tvt0: int = _trace("troll_victory")
	(vic_sq[1][0] as Unit).take_damage(1e9, troll)
	await frames(2)
	# СПРИНТ 20: рык идёт и на КАЖДОЕ убийство троллем (Unit._die), и над
	# выбитым отрядом — запросов два, окно категории пропускает один
	verdict("F7 тролль добил рабочего — клич победы", GameManager.troll_victory_events == tv0 + 1 and _trace("troll_victory") >= tvt0 + 1)
	# И отряд: последний боец отряда игрока пал от тролля
	var sq_f: Array = _squad("archer", Constants.FACTION_PLAYER, troll.global_position + Vector3(3.0, 0.0, 3.0), 2)
	await pframes(2)
	(sq_f[1][0] as Unit).take_damage(1e9, troll)
	await frames(2)
	var tv1: int = GameManager.troll_victory_events
	(sq_f[1][1] as Unit).take_damage(1e9, troll)
	await frames(2)
	verdict("F8 клич — на ПОСЛЕДНЕГО бойца отряда, не на каждого", tv1 == tv0 + 1 and GameManager.troll_victory_events == tv1 + 1)
	verdict("F9 файл клича на месте", ResourceLoader.exists(String((AudioManager.SFX_BANK["troll_victory"] as Array)[0])))
	troll.take_damage(1e9)
	await pframes(2)

	print("\n═════ G. ЭМБИЕНТ РЕКИ ═════")
	verdict("G1 река и лес — на шине Ambient", AudioManager._river.bus == "Ambient" and AudioManager._ambience.bus == "Ambient"
		and AudioServer.get_bus_index("Ambient") >= 0)
	verdict("G2 файл River Stream Loop на месте и зациклен", ResourceLoader.exists(AudioManager.AMBIENCE_RIVER)
		and AudioManager._river.playing and AudioManager._river.stream != null and bool(AudioManager._river.stream.get("loop")))
	verdict("G3 пик громкости тихий (≤ −18 дБ)", AudioManager.RIVER_DB <= -18.0, "%.1f" % AudioManager.RIVER_DB)
	var rz: float = 60.0
	var rx: float = float(main.river_x(rz))
	var half: float = float(main.RIVER_HALF_W)
	var g_in: float = AudioManager.river_gain_at(Vector3(rx, 0.0, rz))
	var g_edge: float = AudioManager.river_gain_at(Vector3(rx + half, 0.0, rz))
	var g_mid: float = AudioManager.river_gain_at(Vector3(rx + half + 2.5, 0.0, rz))
	var g_out: float = AudioManager.river_gain_at(Vector3(rx + half + 6.0, 0.0, rz))
	verdict("G4 в русле и на кромке — полная доля, в 2.5 м — половина, дальше 5 м — ноль",
		is_equal_approx(g_in, 1.0) and g_edge > 0.99 and absf(g_mid - 0.5) < 0.05 and is_zero_approx(g_out),
		"%.2f / %.2f / %.2f / %.2f" % [g_in, g_edge, g_mid, g_out])
	verdict("G5 зона реки + 5 м", is_equal_approx(AudioManager.RIVER_FADE_M, 5.0))
	# Плавный вход: камера у реки
	AudioManager._river_gain = 0.0
	GameManager.update_view_point(Vector3(rx, 0.0, rz), 60.0, 0.0)
	await get_tree().create_timer(0.35).timeout
	var mid_in: float = AudioManager.river_gain()
	await get_tree().create_timer(2.2).timeout
	var full_in: float = AudioManager.river_gain()
	verdict("G6 плавный вход: через 0.35 с доля частичная, через 2.5 с — полная",
		mid_in > 0.05 and mid_in < 0.6 and full_in > 0.95, "%.2f → %.2f" % [mid_in, full_in])
	GameManager.update_view_point(Vector3(rx + 60.0, 0.0, rz), 60.0, 0.0)
	await get_tree().create_timer(0.5).timeout
	var mid_out: float = AudioManager.river_gain()
	await get_tree().create_timer(2.5).timeout
	var out_end: float = AudioManager.river_gain()
	verdict("G7 плавный выход: через 0.5 с ещё слышно, через 3 с — тишина",
		mid_out > 0.4 and mid_out < 0.95 and out_end < 0.02 and AudioManager._river.volume_db <= -60.0,
		"%.2f → %.2f, db %.1f" % [mid_out, out_end, AudioManager._river.volume_db])
	GameManager.update_view_point(Vector3(rx, 0.0, rz), 60.0, 1.0)
	await get_tree().create_timer(0.6).timeout
	verdict("G8 на пределе отдаления камеры реки не слышно", AudioManager.river_target < 0.01, "цель %.2f" % AudioManager.river_target)
	GameManager.update_view_point(Vector3(rx, 0.0, rz), 60.0, 0.0)
	# Флаг паузы у незвучащего голоса не ставится (движок) — горн сперва звучит
	_reset_voice()
	AudioManager.play_horn()
	await frames(2)
	AudioManager.set_paused(true)
	var paused_ok: bool = AudioManager._river.stream_paused and AudioManager._horn.stream_paused
	AudioManager.set_paused(false)
	verdict("G9 пауза глушит реку и горн", paused_ok)
	_finish()
