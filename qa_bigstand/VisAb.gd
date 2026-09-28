extends "res://qa_bigstand/Four.gd"
## ═══════════════════════════════════════════════════════════════════════════
## A/B ЧЕРЕДОВАНИЕМ НА СЦЕНЕ 4000: ручка perf_config против её выключения
## ═══════════════════════════════════════════════════════════════════════════
## Единственный законный способ подтвердить правку меньше миллисекунды
## (CLAUDE.md, «Правила замера»): база и правка подряд, раундами, порядок
## фаз в раунде переворачивается, всё на ОДНОЙ живой сцене. Сцена — Four
## (2500 на 1500 в живой партии), фаза — CLASH; потери не замораживаются,
## поэтому окна короткие, а раундов несколько: дрейф сцены ложится на обе
## стороны поровну.
## Печатает по окнам кадр логики (vis_meter — весь GameManager._process),
## физтик, FPS, строк в GDScript-тике картинки и тихих; в конце — средние
## по сторонам и разницу.
## Запуск: `godot --path . res://qa_bigstand/VisAb.tscn -- ab=vis_quiet_sync
## win=8 rounds=3 [player= horde=]` (ручка ОБЯЗАНА быть bool в perf_config;
## `knob=имя:значение` по-прежнему ставит прочие ручки на весь прогон)

var AB_KNOB := "vis_quiet_sync"
var WIN_SEC := 8.0
var ROUNDS := 3

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("ab="):
			AB_KNOB = s.substr(3)
		elif s.begins_with("win="):
			WIN_SEC = maxf(float(s.substr(4)), 2.0)
		elif s.begins_with("rounds="):
			ROUNDS = maxi(int(s.substr(7)), 1)
	super._ready()

func _run() -> void:
	if not await _setup():
		get_tree().quit()
		return
	var headless: bool = DisplayServer.get_name() == "headless"
	var opt_inst = _Opt.new()
	var cur: Variant = opt_inst.get(AB_KNOB)
	if cur == null or not (cur is bool):
		print("  ручки %s (bool) в perf_config нет — A/B невозможен" % AB_KNOB)
		get_tree().quit()
		return
	await pframes(WARM)
	_start_clash()
	# ПОТЕРИ ЗАМОРОЖЕНЫ: первый прогон без этого закончил бой внутри трёх
	# раундов (живых 3322 → 1490), и стороны A/B сравнивались на разных
	# сценах. Запас 1e9 не держал долевой урон конницы (доля от максимума) —
	# замораживает сам take_damage (Unit.losses_frozen): удар отмечается,
	# запас не убывает, свалка стационарна
	Unit.losses_frozen = true
	await pframes(WARM)
	print("\n═════ A/B ЧЕРЕДОВАНИЕМ: %s ВЫКЛ (A) против ВКЛ (B), окно %.0f с, раундов %d, потери заморожены ═════" % [AB_KNOB, WIN_SEC, ROUNDS])
	var res_a: Array = []
	var res_b: Array = []
	for rnd in range(ROUNDS):
		var order: Array = [false, true] if rnd % 2 == 0 else [true, false]
		for on in order:
			opt_inst.set(AB_KNOB, on)
			await pframes(45)
			_Opt.vis_why_reset()
			GameManager.army.vis_wake_why()
			var r: Dictionary = await _measure("раунд %d, %s=%s" % [rnd + 1, AB_KNOB, "ВКЛ" if on else "ВЫКЛ"], WIN_SEC, headless, false)
			_print_why(WIN_SEC)
			if on:
				res_b.append(r)
			else:
				res_a.append(r)
	opt_inst.set(AB_KNOB, true)
	_ab_summary(res_a, res_b)
	get_tree().quit()

## Кто будил строки и почему они не засыпали — в секунду, за окно
const CORE_WHY := ["срок wake_at", "туман", "LOD", "ход↔стоп (лента)", "ход↔стоп (факт)", "разворот хода", "взгляд ведомого"]
func _print_why(secs: float) -> void:
	var core: PackedInt32Array = GameManager.army.vis_wake_why()
	var s := "    ПОВОДЫ ЯДРА (/с): "
	for k in range(mini(core.size(), CORE_WHY.size())):
		if core[k] > 0:
			s += "%s %.0f; " % [CORE_WHY[k], float(core[k]) / secs]
	print(s)
	s = "    ПОВОДЫ GDScript (/с): "
	for k in range(_Opt.vis_why.size()):
		if _Opt.vis_why[k] > 0:
			s += "%s %.0f; " % [_Opt.VIS_WHY_NAMES[k], float(_Opt.vis_why[k]) / secs]
	print(s)
	s = "    НЕ УСНУЛИ, тиков/с по воротам: "
	for k in range(_Opt.vis_noq.size()):
		if _Opt.vis_noq[k] > 0:
			s += "%s %.0f; " % [_Opt.VIS_NOQ_NAMES[k], float(_Opt.vis_noq[k]) / secs]
	print(s)

func _ab_avg(rs: Array, key: String) -> float:
	if rs.is_empty():
		return 0.0
	var s := 0.0
	for r in rs:
		s += float((r as Dictionary).get(key, 0.0))
	return s / float(rs.size())

func _ab_summary(res_a: Array, res_b: Array) -> void:
	print("\n  | сторона | кадр логики, мс | физтик, мс | стена ср / p95 / p99 / худший, мс | картинка: строк/вызов | тихих | живых в конце |")
	print("  | :--- | ---: | ---: | ---: | ---: | ---: | ---: |")
	for pair in [["A ВЫКЛ", res_a], ["B ВКЛ", res_b]]:
		var rs: Array = pair[1]
		for r in rs:
			var d: Dictionary = r
			print("  | %s %s | %.2f | %.2f | %.1f / %.1f / %.1f / %.1f | %.0f | %.0f | %d |" % [String(pair[0]), String(d["label"]),
				float(d["vis"]), float(d["tick"]), float(d.get("wall_avg", 0.0)), float(d.get("wall_p95", 0.0)),
				float(d.get("wall_p99", 0.0)), float(d.get("wall_worst", 0.0)), float(d.get("vis_listed", 0.0)),
				float(d.get("vis_quiet", 0.0)), int(d.get("alive1", 0))])
	# Разность по ПАРАМ внутри раунда — устойчивее к дрейфу, чем средние
	var pairs := ""
	for k in range(mini(res_a.size(), res_b.size())):
		pairs += "%+.2f " % (float((res_b[k] as Dictionary)["vis"]) - float((res_a[k] as Dictionary)["vis"]))
	print("  по раундам, кадр логики B−A, мс: " + pairs)
	var va: float = _ab_avg(res_a, "vis"); var vb: float = _ab_avg(res_b, "vis")
	var ta: float = _ab_avg(res_a, "tick"); var tb: float = _ab_avg(res_b, "tick")
	var fa: float = _ab_avg(res_a, "fps_avg"); var fb: float = _ab_avg(res_b, "fps_avg")
	var la: float = _ab_avg(res_a, "vis_listed"); var lb: float = _ab_avg(res_b, "vis_listed")
	print("  ИТОГ %s: кадр логики %.2f → %.2f мс (%+.2f), физтик %.2f → %.2f (%+.2f), FPS %.1f → %.1f (%+.1f), строк в GDScript-тике картинки %.0f → %.0f" % [
		AB_KNOB, va, vb, vb - va, ta, tb, tb - ta, fa, fb, fb - fa, la, lb])
	# Пики: средние по окнам p95 / p99 / худшего — для правок этапа 3
	print("  ПИКИ %s: стена ср %.1f → %.1f, p95 %.1f → %.1f, p99 %.1f → %.1f, худший %.1f → %.1f мс" % [
		AB_KNOB, _ab_avg(res_a, "wall_avg"), _ab_avg(res_b, "wall_avg"), _ab_avg(res_a, "wall_p95"), _ab_avg(res_b, "wall_p95"),
		_ab_avg(res_a, "wall_p99"), _ab_avg(res_b, "wall_p99"), _ab_avg(res_a, "wall_worst"), _ab_avg(res_b, "wall_worst")])
