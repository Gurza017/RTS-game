extends Node

## ═══════════════════════════════════════════════════════════════════════════
## ЗАМЕР: ПЯТНАДЦАТЬ ОТРЯДОВ В РЕЖИМЕ ATTACK-MOVE (ТЗ 23.09.2026, требование 2)
## ═══════════════════════════════════════════════════════════════════════════
## Заказ: «проверь прогон 15+ отрядов через Attack-Move: FPS не должен
## проседать». Меряем ЧЕСТНО И ЧЕРЕДОВАНИЕМ — так же, как это делает qa_ab:
## одна и та же живая сцена, один и тот же состав, фазы БАЗА и ПРАВКА идут
## подряд раундами, порядок фаз в раунде переворачивается.
##
## ПОЧЕМУ ЧЕРЕДОВАНИЕМ, А НЕ «ДО И ПОСЛЕ». Разброс между прогонами на
## НЕИЗМЕННОМ коде — ±3-5 к/с (CLAUDE.md, «Правила замера», п. 3), а весь
## эффект здесь заведомо меньше миллисекунды: пятнадцать сканов раз в 0.3 с —
## это пятьдесят вызовов в секунду на всю партию. Сравнение двух отдельных
## запусков показало бы дрейф машины, а не цену механики.
##
## ЧАСЫ — `perf_config.tick_meter` (одна пара get_ticks_usec вокруг ВСЕГО
## _physics_process). Мониторы Performance.TIME_* для разбора кадра не годятся:
## при снятом ограничении кадров они усредняются по кадрам отрисовки.
##
## Запуск: godot --headless --path . res://qa_attack_move/Bench.tscn
##   -- squads=15 men=30 rounds=4

const _Opt := preload("res://scripts/perf_config.gd")

var main = null
var _squads: int = 15
var _men: int = 30
var _rounds: int = 4
var _dest: Vector3 = Vector3.ZERO
var _sids: Array = []

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s: String = String(a)
		if s.begins_with("squads="):
			_squads = int(s.substr(7))
		elif s.begins_with("men="):
			_men = int(s.substr(4))
		elif s.begins_with("rounds="):
			_rounds = int(s.substr(7))
	call_deferred("_run")
	get_tree().create_timer(600.0).timeout.connect(func():
		print("  СТОРОЖ: замер не завершился за 600 с")
		get_tree().quit())

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _spawn(uid: String, at: Vector3, n: int) -> Array:
	var sid: int = GameManager.new_squad(Constants.FACTION_PLAYER, uid)
	_sids.append(sid)
	var men: Array = []
	for i in range(n):
		var u: Unit = Building.PRELOAD_SCENES[uid].instantiate()
		u.faction = Constants.FACTION_PLAYER
		main.world_add(u)
		var p := at + Vector3(float(i % 6) * 0.7, 0.0, float(i / 6) * 0.7)
		u.global_position = Vector3(p.x, GameManager.get_terrain_height(p.x, p.z), p.z)
		u.sync_row()
		u.post_pos = u.global_position
		GameManager.add_to_squad(sid, u)
		men.append(u)
	return men

## Средний тик за N физкадров, миллисекунды
func _measure(frames: int) -> float:
	_Opt.tick_reset()
	await pframes(frames)
	var ms: float = _Opt.tick_ms()
	return maxf(ms, 0.0)

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(10)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	if main.get("gnoll_ai") != null:
		main.gnoll_ai.set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	GameManager.world_bounds_enabled = false
	GameManager.pop_limit_enabled = false
	_Opt.tick_meter = true
	await pframes(4)

	var sm = main.selection_manager
	var cmd = sm.squad_commander()
	var base := Vector3(-260.0, 0.0, -160.0)
	var all: Array = []
	for k in range(_squads):
		var col: int = k % 5
		var row: int = k / 5
		all += _spawn("spearman", base + Vector3(float(col) * 26.0, 0.0, float(row) * 22.0), _men)
	await pframes(20)
	_dest = base + Vector3(60.0, 0.0, 150.0)
	sm.selected_units = all.duplicate()
	GameManager.on_selection_changed(sm.selected_units)
	print("\n═══ ATTACK-MOVE BENCH: %d отрядов × %d бойцов = %d ═══"
		% [_squads, _men, all.size()])

	var base_ms: Array = []
	var am_ms: Array = []
	for r in range(_rounds):
		# ПОРЯДОК ФАЗ В РАУНДЕ ПЕРЕВОРАЧИВАЕТСЯ: дрейф машины попадает в обе
		# выборки одинаково
		var am_first: bool = (r % 2) == 1
		for phase in range(2):
			var do_am: bool = am_first if phase == 0 else not am_first
			# Отряды возвращаются в исходную точку перед каждой фазой, иначе
			# вторая фаза мерила бы уже сошедшуюся кучу
			for u in all:
				if is_instance_valid(u):
					(u as Unit).command_move((u as Unit).post_pos, false,
						Vector3.ZERO, false, true, false)
			await pframes(40)
			if do_am:
				cmd.attack_move(sm, _dest, false)
			else:
				sm.march_selection_to(_dest, false)
			await pframes(20)         # прогрев: приказ разошёлся
			var ms: float = await _measure(150)
			if do_am:
				am_ms.append(ms)
			else:
				base_ms.append(ms)
			for sid in _sids:
				cmd.cancel_squad(int(sid))
		print("  раунд %d: марш %.3f мс, attack-move %.3f мс"
			% [r + 1, base_ms[base_ms.size() - 1], am_ms[am_ms.size() - 1]])

	var b := 0.0
	for v in base_ms: b += float(v)
	var a := 0.0
	for v in am_ms: a += float(v)
	b /= maxf(float(base_ms.size()), 1.0)
	a /= maxf(float(am_ms.size()), 1.0)
	print("\n  ОБЫЧНЫЙ МАРШ:  %.3f мс тика" % b)
	print("  ATTACK-MOVE:   %.3f мс тика" % a)
	print("  РАЗНИЦА:       %+.3f мс (%+.1f %%), сканов всего %d"
		% [a - b, (a - b) / maxf(b, 0.001) * 100.0, cmd.scans])
	# ВЕРДИКТ ОДИН И ПО СВОЙСТВУ: механика, которая тикает пятнадцать раз в
	# 0.3 с, обязана теряться в шуме одного кадра. Порог — 0.5 мс: это меньше
	# межпрогонного разброса (±3-5 к/с), то есть заведомо не «просадка FPS»
	var ok: bool = (a - b) <= 0.5
	print("  ВЕРДИКТ F1 пятнадцать отрядов в режиме атаки не грузят тик: %s"
		% ("ПРОШЛО" if ok else "НЕ ПРОШЛО"))
	print("\n═════ ИТОГ qa_attack_move/Bench: провалов: %d ═════" % (0 if ok else 1))
	get_tree().quit()
