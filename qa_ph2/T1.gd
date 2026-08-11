extends Node

## БЛОК 1 — ДИНАМИЧЕСКАЯ ФАЛАНГА (пункты 1.1 … 1.5)

var main: Node = null
var Spear: PackedScene = null

const GAP := 0.7          # шаг между шеренгами и колоннами при построении
const ENEMY_X := 2.0      # стенка врагов = ровно attack_range копейщика

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	Spear = load("res://scenes/units/Spearman.tscn") as PackedScene
	await get_tree().process_frame
	await get_tree().process_frame
	await _t11_12_13()
	await _t14_melee()
	await _t15_attack_stance()
	print("\n=== T1 DONE ===")
	get_tree().quit()

# ── вспомогательное ─────────────────────────────────────────────────────────
func _wait(frames: int) -> void:
	for _i in range(frames):
		await get_tree().physics_frame

## ЖДАТЬ ПО НАСТЕННЫМ ЧАСАМ, А НЕ ПО КАДРАМ.
##
## Опускание копья разнесено по времени намеренно (Spearman.DROP_DELAY_MAX_MS):
## у каждого бойца своя задержка до 1.9 с, чтобы щетина пик не падала разом
## «как шлагбаум». Отсчёт ведётся по Time.get_ticks_msec(), то есть по РЕАЛЬНОМУ
## времени, а headless прокручивает физические кадры быстрее реального времени.
## Поэтому «_wait(45) = 0.75 с» здесь неверно: кадры пролетают, а часы стоят,
## и замер попадал в середину разброса задержек (3 копья из 6 вместо 6).
func _wait_ms(ms: int) -> void:
	var end: int = Time.get_ticks_msec() + ms
	while Time.get_ticks_msec() < end:
		await get_tree().physics_frame

## Пауза, заведомо перекрывающая ВЕСЬ разброс задержек опускания копья
func _wait_drop() -> void:
	await _wait_ms(Spearman.DROP_DELAY_MAX_MS + 350)

func _mk(fac: int, pos: Vector3, harmless: bool = true) -> Unit:
	var u: Unit = Spear.instantiate()
	u.faction = fac
	main.add_child(u)
	u.global_position = pos
	if harmless:
		u.attack_damage = 0.0     # бой отключён: проверяем ТОЛЬКО геометрию рядов
	return u

func _alive(arr: Array) -> Array:
	var out: Array = []
	for u in arr:
		if is_instance_valid(u) and not u.is_dead():
			out.append(u)
	return out

## Независимый пересчёт «сколько своих в конусе передо мной» —
## своя реализация, не SpatialGrid.allies_ahead()
func _my_allies_ahead(u: Unit, all: Array, dir: Vector3, look: float, half: float) -> int:
	var c := 0
	for n in all:
		if n == u or not is_instance_valid(n) or n.is_dead():
			continue
		if n.faction != u.faction:
			continue
		var d: Vector3 = n.global_position - u.global_position
		var along: float = d.x * dir.x + d.z * dir.z
		if along <= 0.12 or along > look:
			continue
		var lat: float = absf(d.x * -dir.z + d.z * dir.x)
		if lat > half:
			continue
		c += 1
	return c

func _report(label: String, squad: Array) -> void:
	var hist: Dictionary = {}
	var by_row: Dictionary = {}
	var leveled := 0
	var alive := 0
	for u in squad:
		if not is_instance_valid(u) or u.is_dead():
			continue
		alive += 1
		var r: int = u._live_rank
		hist[r] = int(hist.get(r, 0)) + 1
		var src: int = int(u.get_meta("row"))
		if not by_row.has(src):
			by_row[src] = [0, 0]
		var e: Array = by_row[src]
		e[0] = int(e[0]) + 1
		if bool(u.call("_spear_leveled")):
			leveled += 1
			e[1] = int(e[1]) + 1
	var keys: Array = hist.keys()
	keys.sort()
	var hs := ""
	for k in keys:
		hs += "  _live_rank=%d: %d" % [int(k), int(hist[k])]
	print("  %s" % label)
	print("     живых=%d, копьё горизонтально=%d" % [alive, leveled])
	print("     гистограмма рядов:%s" % hs)
	var rk: Array = by_row.keys()
	rk.sort()
	for k in rk:
		var e2: Array = by_row[k]
		print("       исходная шеренга %d: живых=%d, из них с копьём наперевес=%d"
			% [int(k), int(e2[0]), int(e2[1])])

# ── 1.1 / 1.2 / 1.3 ─────────────────────────────────────────────────────────
func _t11_12_13() -> void:
	print("\n══════ 1.1 РЯДЫ В СТРОЮ 6×5 ══════")
	var squad: Array = []
	for row in range(5):
		for col in range(6):
			var u := _mk(Constants.FACTION_PLAYER,
				Vector3(-float(row) * GAP, 0.0, float(col) * GAP))
			u.set_meta("row", row)
			u.set_meta("sx", -float(row) * GAP)
			u.set_meta("sz", float(col) * GAP)
			squad.append(u)
	var foes: Array = []
	for col in range(6):
		foes.append(_mk(Constants.FACTION_ENEMY, Vector3(ENEMY_X, 0.0, float(col) * GAP)))
	await get_tree().process_frame
	for u in squad:
		u.set_stance("defense")
	print("  построение: 6 колонн × 5 шеренг, шаг %.2f м, фронт на +X" % GAP)
	print("  враг: стенка из %d бойцов на x=%.1f (= attack_range копейщика 2.0)"
		% [foes.size(), ENEMY_X])
	print("  константы: PHALANX_FRONT_RANKS=%d RANK_RECHECK=%.2f FILE_LOOK_AHEAD=%.2f FILE_HALF_WIDTH=%.2f"
		% [Unit.PHALANX_FRONT_RANKS, Unit.RANK_RECHECK, Unit.FILE_LOOK_AHEAD, Unit.FILE_HALF_WIDTH])
	await _wait_drop()       # весь разброс задержек опускания копья + запас
	_report("после полного опускания копий в стойке ЗАЩИТА:", squad)
	# Явная проверка условия пункта
	var ok11 := true
	var bad: Array = []
	for u in squad:
		if not is_instance_valid(u) or u.is_dead():
			continue
		var src: int = int(u.get_meta("row"))
		var lev: bool = bool(u.call("_spear_leveled"))
		var want: bool = src <= 1
		if lev != want:
			ok11 = false
			bad.append("шеренга%d rank=%d lev=%s" % [src, u._live_rank, str(lev)])
	print("  ИТОГ 1.1: %s%s" % ["PASS" if ok11 else "FAIL", "" if ok11 else ("  нарушители: " + str(bad))])

	# ── 1.2 гибель первой шеренги ───────────────────────────────────────────
	print("\n══════ 1.2 ПЕРЕТЕКАНИЕ КОПИЙ ПРИ ГИБЕЛИ ШЕРЕНГ ══════")
	var k0 := 0
	for u in squad:
		if is_instance_valid(u) and int(u.get_meta("row")) == 0:
			u._die()
			k0 += 1
	print("  убито в шеренге 0: %d" % k0)
	# Выдвинувшимся вперёд задержка не полагается (копьё выставляется сразу),
	# но соседям по бывшим задним шеренгам ещё может «доигрывать» свой отсчёт
	await _wait_ms(900)
	_report("после гибели шеренги 0 (+0.9 с):", squad)
	var ok12a := true
	for u in squad:
		if not is_instance_valid(u) or u.is_dead():
			continue
		var src: int = int(u.get_meta("row"))
		var lev: bool = bool(u.call("_spear_leveled"))
		if (src in [1, 2]) != lev:
			ok12a = false
	print("  ожидание: копья у бывших шеренг 1-2, у 3-4 подняты → %s"
		% ["PASS" if ok12a else "FAIL"])

	var k1 := 0
	for u in squad:
		if is_instance_valid(u) and not u.is_dead() and int(u.get_meta("row")) == 1:
			u._die()
			k1 += 1
	print("  убито в шеренге 1: %d" % k1)
	await _wait_ms(900)
	_report("после гибели шеренги 1 (+0.9 с):", squad)
	var ok12b := true
	for u in squad:
		if not is_instance_valid(u) or u.is_dead():
			continue
		var src: int = int(u.get_meta("row"))
		var lev: bool = bool(u.call("_spear_leveled"))
		if (src in [2, 3]) != lev:
			ok12b = false
	print("  ожидание: копья у бывших шеренг 2-3, у 4 подняты → %s"
		% ["PASS" if ok12b else "FAIL"])

	# ── 1.3 смыкание ─────────────────────────────────────────────────────────
	print("\n══════ 1.3 СМЫКАНИЕ СТРОЯ ══════")
	print("  PHALANX_GAP=%.2f PHALANX_FILL_SPEED=%.2f attack_range=2.0"
		% [Unit.PHALANX_GAP, Unit.PHALANX_FILL_SPEED])
	# 3 с не хватало на ПОСЛЕДНЮЮ шеренгу: она трогается только после того, как
	# уйдут вперёд передние, а идёт смыкание на PHALANX_FILL_SPEED (45%% шага)
	await _wait_ms(5000)
	var rows_x: Dictionary = {}
	var max_dz := 0.0
	var max_x := -99.0
	var sum_adv := 0.0
	var n_alive := 0
	for u in squad:
		if not is_instance_valid(u) or u.is_dead():
			continue
		n_alive += 1
		var adv: float = u.global_position.x - float(u.get_meta("sx"))
		var dz: float = absf(u.global_position.z - float(u.get_meta("sz")))
		sum_adv += adv
		max_dz = maxf(max_dz, dz)
		max_x = maxf(max_x, u.global_position.x)
		var src: int = int(u.get_meta("row"))
		if not rows_x.has(src):
			rows_x[src] = []
		(rows_x[src] as Array).append(u.global_position.x)
	print("  выживших=%d, средний сдвиг вперёд=%+.3f м, макс. боковой снос |dz|=%.3f м"
		% [n_alive, sum_adv / maxf(float(n_alive), 1.0), max_dz])
	print("  передний край строя x=%.3f (враг на x=%.1f → зазор %.3f м, копьё достаёт 2.0)"
		% [max_x, ENEMY_X, ENEMY_X - max_x])
	var rk: Array = rows_x.keys()
	rk.sort()
	var prev_mean := INF
	var worst_gap := 0.0
	for k in rk:
		var arr: Array = rows_x[k]
		var s := 0.0
		for v in arr:
			s += float(v)
		var mean: float = s / float(arr.size())
		var gap_s := ""
		if prev_mean != INF:
			var g: float = prev_mean - mean
			worst_gap = maxf(worst_gap, g)
			gap_s = "  интервал до предыдущей шеренги=%.3f м" % g
		print("     бывшая шеренга %d: средний x=%+.3f (старт %+.3f)%s"
			% [int(k), mean, -float(k) * GAP, gap_s])
		prev_mean = mean
	print("  макс. интервал между шеренгами=%.3f м (порог PHALANX_GAP+0.2=%.2f)"
		% [worst_gap, Unit.PHALANX_GAP + 0.2])
	var ok13 := max_x <= ENEMY_X - 2.0 + 0.35 and max_dz < 0.35 and worst_gap <= Unit.PHALANX_GAP + 0.2
	print("  ИТОГ 1.3: %s (шаг строго на врага, за attack_range не лезут, строй цел)"
		% ["PASS" if ok13 else "FAIL"])

	for u in squad + foes:
		if is_instance_valid(u):
			u.queue_free()
	await get_tree().process_frame

# ── 1.4 свалка ───────────────────────────────────────────────────────────────
func _t14_melee() -> void:
	print("\n══════ 1.4 СВАЛКА: КОПЬЯ У ТЕХ, ПЕРЕД КЕМ ПУСТО ══════")
	seed(20260729)
	var squad: Array = []
	for i in range(20):
		var a: float = randf() * TAU
		var r: float = 2.2 + randf() * 3.0
		var u := _mk(Constants.FACTION_PLAYER,
			Vector3(40.0 + cos(a) * r, 0.0, 40.0 + sin(a) * r))
		u.set_meta("row", i)
		squad.append(u)
	var foes: Array = []
	for i in range(6):
		var a2: float = float(i) / 6.0 * TAU
		foes.append(_mk(Constants.FACTION_ENEMY,
			Vector3(40.0 + cos(a2) * 0.6, 0.0, 40.0 + sin(a2) * 0.6)))
	await get_tree().process_frame
	for u in squad:
		u.set_stance("defense")
	await _wait(120)
	# Замер строго синхронный: сами просим пересчёт, тут же считаем геометрию
	var mismatch := 0
	var lev_cnt := 0
	var rows: Dictionary = {}
	print("  боец |  свой _live_rank | мой независимый счёт | копьё")
	for u in squad:
		if not is_instance_valid(u) or u.is_dead():
			continue
		u.call("_update_live_rank")
	for u in squad:
		if not is_instance_valid(u) or u.is_dead():
			continue
		var dir: Vector3 = u.call("_phalanx_dir")
		var mine: int = _my_allies_ahead(u, squad, dir, Unit.FILE_LOOK_AHEAD, Unit.FILE_HALF_WIDTH)
		var got: int = u._live_rank
		var lev: bool = bool(u.call("_spear_leveled"))
		if lev:
			lev_cnt += 1
		rows[got] = int(rows.get(got, 0)) + 1
		if mine != got:
			mismatch += 1
		print("   %2d   |        %d         |          %d           |  %s%s"
			% [int(u.get_meta("row")), got, mine, "ГОРИЗ" if lev else "верт",
			   "   <-- РАСХОЖДЕНИЕ" if mine != got else ""])
	var keys: Array = rows.keys()
	keys.sort()
	var hs := ""
	for k in keys:
		hs += "  rank=%d:%d" % [int(k), int(rows[k])]
	print("  гистограмма:%s   копий горизонтально=%d/20" % [hs, lev_cnt])
	print("  ИТОГ 1.4: %s (расхождений с независимым геометрическим счётом: %d)"
		% ["PASS" if mismatch == 0 else "FAIL", mismatch])
	for u in squad + foes:
		if is_instance_valid(u):
			u.queue_free()
	await get_tree().process_frame

# ── 1.5 регрессия: стойка АТАКА ─────────────────────────────────────────────
func _t15_attack_stance() -> void:
	print("\n══════ 1.5 РЕГРЕССИЯ: В СТОЙКЕ АТАКА КОПЬЯ ВСЕГДА ПОДНЯТЫ ══════")
	# (а) марш строем
	var squad: Array = []
	for row in range(5):
		for col in range(6):
			var u := _mk(Constants.FACTION_PLAYER,
				Vector3(60.0 - float(row) * GAP, 0.0, 60.0 + float(col) * GAP))
			u.set_meta("row", row)
			squad.append(u)
	var foes: Array = []
	for col in range(6):
		foes.append(_mk(Constants.FACTION_ENEMY, Vector3(64.0, 0.0, 60.0 + float(col) * GAP)))
	await get_tree().process_frame
	# Сначала ПОБЫВАЕМ в защите — чтобы _live_rank реально насчитался,
	# и проверка «атака гасит копья» не прошла на нулях по умолчанию
	for u in squad:
		u.set_stance("defense")
	await _wait(45)
	var lev_def := 0
	for u in squad:
		if bool(u.call("_spear_leveled")):
			lev_def += 1
	print("  контроль: в ЗАЩИТЕ копий горизонтально=%d/30" % lev_def)
	for u in squad:
		u.set_stance("attack")
	for u in squad:
		u.command_move(Vector3(70.0, 0.0, u.global_position.z))
	await _wait(20)
	var moving := 0
	var lev_march := 0
	var ranks_nonzero := 0
	for u in squad:
		if u.state == Unit.State.MOVING:
			moving += 1
		if u._live_rank > 0:
			ranks_nonzero += 1
		if bool(u.call("_spear_leveled")):
			lev_march += 1
	print("  (а) НА МАРШЕ: в состоянии MOVING=%d/30, у %d бойцов _live_rank>0 (остался от защиты)"
		% [moving, ranks_nonzero])
	print("      копий горизонтально=%d/30 → %s" % [lev_march, "PASS" if lev_march == 0 else "FAIL"])
	for u in squad + foes:
		if is_instance_valid(u):
			u.queue_free()
	await get_tree().process_frame

	# (б) в контакте
	var s2: Array = []
	for row in range(5):
		for col in range(6):
			var u := _mk(Constants.FACTION_PLAYER,
				Vector3(80.0 - float(row) * GAP, 0.0, 80.0 + float(col) * GAP), false)
			u.max_health = 100000.0
			u.current_health = 100000.0
			u.set_meta("row", row)
			s2.append(u)
	var f2: Array = []
	for col in range(6):
		var e := _mk(Constants.FACTION_ENEMY, Vector3(81.2, 0.0, 80.0 + float(col) * GAP), false)
		e.max_health = 100000.0
		e.current_health = 100000.0
		f2.append(e)
	await get_tree().process_frame
	for u in s2:
		u.set_stance("defense")
	await _wait(45)
	var lev_d2 := 0
	for u in s2:
		if bool(u.call("_spear_leveled")):
			lev_d2 += 1
	for u in s2:
		u.set_stance("attack")
	await _wait(120)
	var att := 0
	var lev_fight := 0
	var rnz := 0
	for u in s2:
		if not is_instance_valid(u) or u.is_dead():
			continue
		if u.state == Unit.State.ATTACKING:
			att += 1
		if u._live_rank > 0:
			rnz += 1
		if bool(u.call("_spear_leveled")):
			lev_fight += 1
	print("  (б) В КОНТАКТЕ: контроль в защите было %d/30 горизонтальных" % lev_d2)
	print("      в стойке АТАКА: ATTACKING=%d/30, _live_rank>0 у %d, копий горизонтально=%d/30 → %s"
		% [att, rnz, lev_fight, "PASS" if lev_fight == 0 else "FAIL"])
	for u in s2 + f2:
		if is_instance_valid(u):
			u.queue_free()
	await get_tree().process_frame
