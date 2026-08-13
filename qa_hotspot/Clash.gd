extends Node

## ═══════════════════════════════════════════════════════════════════════════
## 300 НА 300: СХОДЯТСЯ ИЗДАЛЕКА И ДЕРУТСЯ ВСЕ СРАЗУ
## ═══════════════════════════════════════════════════════════════════════════
## Сценарий по описанию владельца: две линии копейщиков ставятся ДАЛЕКО друг от
## друга, идут навстречу и сходятся в общей свалке. Плюс несколько изученных
## улучшений кузницы — владелец подозревает, что расход там.
##
## Замер идёт ФАЗАМИ (подход / первый контакт / полная свалка), и весь прогон
## делается ДВАЖДЫ: без улучшений и с ними. Разница между прогонами и есть
## ответ по кузнице.
##
## ОКОННЫЙ, V-Sync снят. Запуск:
##   godot --path . res://qa_hotspot/Clash.tscn -- --count=600 --upgrades=5

const _OptCfg = preload("res://scripts/perf_config.gd")
const SpearScene = preload("res://scenes/units/Spearman.tscn")
const _UCfg = preload("res://scripts/unit_stats_config.gd")

const SAMPLE_FRAMES := 120
## Между линиями: столько, чтобы марш занял несколько секунд и отряды успели
## растянуться, как в настоящем бою
const LINE_GAP := 90.0

var main = null
var _units: Array = []
var _rows: Array = []
var _n := 600
var _upg := 5

func _ready() -> void:
	call_deferred("_run")

## ЖДЁМ ФИЗКАДРАМИ, А НЕ КАДРАМИ ОТРИСОВКИ. При снятом V-Sync игра идёт на
## 250+ к/с, и «подождать 120 кадров» — это полсекунды: армии за это время не
## проходят и десятой части девяноста метров, а стенд честно показывает «в бою
## 0», меряя марш вместо свалки. Физкадр всегда 1/60 с, по нему и считаем
func _frames(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _run() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("--count="):
			_n = maxi(2, int(s.substr(8)))
		elif s.begins_with("--upgrades="):
			_upg = maxi(0, int(s.substr(11)))
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await _frames(20)
	# ИИ и экономика замеру мешают: он начнёт нанимать своих и цифры поплывут
	if main.get("enemy_ai") != null:
		main.enemy_ai.set_process(false)

	# ── СВЕРКА ПО ДРОБЛЕНИЮ ТИКА ────────────────────────────────────────────
	# Лестница шардов включается только с 1500 бойцов (perf_config), то есть на
	# полутора тысячах игрок платит полную цену 60 опросов в секунду на бойца.
	# Здесь тот же бой прогоняется с принудительным дроблением 1 / 2 / 3, чтобы
	# увидеть, что именно покупает понижение частоты опроса
	for sh in [1, 2, 3]:
		_OptCfg.tick_shards_force = sh
		await _pass("шардов %d" % sh, 0)
	_OptCfg.tick_shards_force = 0
	_report()
	get_tree().quit(0)

func _pass(tag: String, upgrades: int) -> void:
	await _clear()
	var applied := 0
	if upgrades > 0:
		applied = _research(upgrades)
	_spawn()
	# Камера на середину поля, как смотрит игрок
	var cam = main.get("_camera")
	if cam != null:
		cam.set_process(false)
		cam.jump_to(Vector3.ZERO, cam.min_height * 2.6)
	await _frames(30)

	_rows.append(await _sample("%s | стоят" % tag, applied))
	# ПРИКАЗ В СЕРЕДИНУ ПОЛЯ, А НЕ «НА N МЕТРОВ ВПЕРЁД». Первая версия посылала
	# каждую сторону на LINE_GAP вперёд — то есть ЗА СПИНУ противнику: линии
	# расходились, и стенд честно показывал «в бою 0», меряя марш вместо боя
	for u in _units:
		var un := u as Unit
		if not is_instance_valid(un):
			continue
		var p := un.global_position
		# Строй сохраняется: каждый идёт в свою точку у средней линии
		var dir: float = 1.0 if un.faction == Constants.FACTION_PLAYER else -1.0
		un.command_move(Vector3(p.x, 0.0, dir * 1.5), false, Vector3(0.0, 0.0, dir))
	_rows.append(await _sample("%s | идут навстречу" % tag, applied))
	# 45 м на брата при ~4 м/с — это около 11 секунд, то есть ~660 физкадров.
	# Берём с запасом и ждём, пока хоть кто-то не сцепится
	await _wait_contact(900)
	_rows.append(await _sample("%s | первый контакт" % tag, applied))
	await _frames(240)
	_rows.append(await _sample("%s | полная свалка" % tag, applied))

## Ждать, пока в бою не окажется заметная часть армии (или пока не выйдет срок)
func _wait_contact(limit: int) -> void:
	for _i in range(limit):
		await get_tree().physics_frame
		if _i % 30 != 0:
			continue
		var f := 0
		for u in _units:
			var un := u as Unit
			if is_instance_valid(un) and un.state == Unit.State.ATTACKING:
				f += 1
				if f > _n / 8:
					return

## Изучить n улучшений ОБЕИМ сторонам. Слоты ищем перебором: индексировать
## UPGRADE_SLOTS по позиции нельзя — нулевой несёт заглушку "requires", и
## can_research() отвергает его навсегда (см. CLAUDE.md)
func _research(n: int) -> int:
	var done := 0
	for faction in [Constants.FACTION_PLAYER, Constants.FACTION_ENEMY]:
		var got := 0
		for slot in _UCfg.UPGRADE_SLOTS:
			if got >= n:
				break
			var id: String = String((slot as Dictionary).get("id", ""))
			if id.is_empty() or not GameManager.can_research(faction, id):
				continue
			GameManager.finish_research(faction, id)
			got += 1
		done = maxi(done, got)
	return done

func _clear() -> void:
	for u in _units:
		if is_instance_valid(u):
			u.free()
	_units.clear()
	GameManager.reset_squads()
	GameManager.researched.clear()
	GameManager.unit_bonuses.clear()
	GameManager.upgrades = {
		Constants.FACTION_PLAYER: {}, Constants.FACTION_ENEMY: {},
	}
	await _frames(10)

func _spawn() -> void:
	var half: int = _n / 2
	var world: Node3D = main.world_root()
	var cols := 20
	for side in range(2):
		var faction: int = Constants.FACTION_PLAYER if side == 0 else Constants.FACTION_ENEMY
		var z0: float = -LINE_GAP * 0.5 if side == 0 else LINE_GAP * 0.5
		var sid: int = GameManager.new_squad(faction, "spearman")
		for i in range(half):
			var u: Unit = SpearScene.instantiate()
			u.faction = faction
			world.add_child(u)
			u.global_position = Vector3(
				float(i % cols) * 0.95 - float(cols) * 0.475,
				0.0,
				z0 + float(i / cols) * 0.95 * (1.0 if side == 0 else -1.0))
			# Бой должен идти всё время замера, а не кончиться за пять секунд
			u.max_health = 3000.0
			u.current_health = 3000.0
			if i % 50 == 0 and i > 0:
				sid = GameManager.new_squad(faction, "spearman")
			GameManager.add_to_squad(sid, u)
			_units.append(u)

func _sample(name: String, applied: int) -> Dictionary:
	_OptCfg.tick_meter = true
	_OptCfg.vis_meter = true
	_OptCfg.tick_reset()
	_OptCfg.vis_reset()
	var draws := 0.0
	var t0 := Time.get_ticks_usec()
	for _i in range(SAMPLE_FRAMES):
		await get_tree().process_frame
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var frame_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / float(SAMPLE_FRAMES)
	_OptCfg.tick_meter = false
	_OptCfg.vis_meter = false
	var fighting := 0
	for u in _units:
		var un := u as Unit
		if is_instance_valid(un) and un.state == Unit.State.ATTACKING:
			fighting += 1
	return {
		"name": name, "frame": frame_ms, "fps": 1000.0 / maxf(frame_ms, 0.001),
		"tick": _OptCfg.tick_ms(), "vis": _OptCfg.vis_ms(),
		"draws": draws / float(SAMPLE_FRAMES), "fight": fighting, "upg": applied,
	}

func _report() -> void:
	var out := PackedStringArray()
	out.append("")
	out.append("═══ %d КОПЕЙЩИКОВ, СХОДЯТСЯ С %.0f м (окно, V-Sync снят) ═══"
		% [_n, LINE_GAP])
	out.append("")
	out.append("  фаза                                    кадр    к/с  физтик визуал вызовы  в бою")
	out.append("  --------------------------------------+-------+-----+------+------+------+------")
	for r in _rows:
		out.append("  %-38s %5.2f мс %4.0f %5.2f %5.2f %6.0f %5d" % [
			r["name"], r["frame"], r["fps"], maxf(r["tick"], 0.0),
			maxf(r["vis"], 0.0), r["draws"], r["fight"]])
	out.append("")
	out.append("  Разница между двумя половинами таблицы — цена улучшений кузницы.")
	print("\n".join(out))
