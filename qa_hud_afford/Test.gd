extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ЖИВЫЕ ИКОНКИ ДОСТУПНОСТИ И ЦЕНА ИКОНКАМИ (заказ 10.09.2026)
## ═══════════════════════════════════════════════════════════════════════════
##   A ЗАМОК — кнопки найма перекрашиваются по сигналу склада без
##     перевыделения: денег нет → «нет денег», деньги пришли → «доступно».
##   B КУЗНИЦА — доступный узел без денег помечен красной рамкой, и она
##     снимается по притоку; в плашке узла цена — иконками ресурсов, без
##     буквенных суффиксов.
##   C РЕПЛИКИ — «держать строй» играет через раз, окна повтора не короче 9 с;
##     шаги тише прежнего на 30 % (−3.1 дБ) и в бюджете.
## Запуск: godot --headless --path . res://qa_hud_afford/Test.tscn

const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _Forge := preload("res://scripts/forge_config.gd")

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(180.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился за 180 с"); _finish())

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
	print("\n═════ ИТОГ qa_hud_afford: прошло %d, провалов: %d ═════" % [_pass, _fail])
	for l in _log:
		if not bool(l[1]):
			print("  НЕ ПРОШЛО: %s" % String(l[0]))
	get_tree().quit()

func _set_all(amount: float) -> void:
	for t in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD, Constants.RESOURCE_STONE, Constants.RESOURCE_FOOD]:
		ResourceManager.set_amount(Constants.FACTION_PLAYER, int(t), amount)

func _border_of(btn: Button) -> Color:
	var sb := btn.get_theme_stylebox("normal") as StyleBoxFlat
	return sb.border_color if sb != null else Color.BLACK

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(8)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if main.get("goblin_ai") != null:
		main.goblin_ai.set_process(false)
	GameManager.world_bounds_enabled = false
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	await pframes(4)
	var hud = main.hud

	# ── A. Замок: кнопки найма живут по сигналу склада ────────────────────
	print("\n═════ A. КНОПКИ НАЙМА ═════")
	var castle := Castle.new()
	castle.faction = Constants.FACTION_PLAYER
	main.world_add(castle)
	var cp := Vector3(-120.0, 0.0, -60.0)
	castle.global_position = Vector3(cp.x, GameManager.get_terrain_height(cp.x, cp.z), cp.z)
	await frames(3)
	_set_all(20000.0)
	main.selection_manager.selected_units = [castle]
	hud.show_selection([castle])
	await frames(3)
	var watch: Array = hud._afford_watch
	verdict("A1 кнопки найма записаны в реестр живой доступности", watch.size() >= 1, "кнопок %d" % watch.size())
	if watch.is_empty():
		_finish()
		return
	var entry: Dictionary = watch[0]
	var btn: Button = entry["btn"]
	var ok_border: Color = _border_of(btn)
	verdict("A2 при полном складе кнопка помечена доступной", bool(entry["ok"]))
	_set_all(0.0)
	await frames(2)
	var lack_border: Color = _border_of(btn)
	verdict("A3 склад опустел — кнопка перекрашена в «нет денег» БЕЗ перевыделения",
		not bool(entry["ok"]) and lack_border != ok_border and lack_border.r > lack_border.g,
		"рамка %s → %s" % [str(ok_border), str(lack_border)])
	_set_all(20000.0)
	await frames(2)
	verdict("A4 деньги пришли — кнопка снова доступна тем же кадром сигнала",
		bool(entry["ok"]) and _border_of(btn) == ok_border)
	hud.show_selection([])
	await frames(2)
	_set_all(0.0)
	await frames(2)
	verdict("A5 реестр не держит мёртвые кнопки после смены панели", hud._afford_watch.is_empty(),
		"в реестре %d" % hud._afford_watch.size())
	_set_all(20000.0)

	# ── B. Кузница ─────────────────────────────────────────────────────────
	print("\n═════ B. КУЗНИЦА ═════")
	var smithy := Smithy.new()
	smithy.faction = Constants.FACTION_PLAYER
	main.world_add(smithy)
	var spp := cp + Vector3(16.0, 0.0, 0.0)
	smithy.global_position = Vector3(spp.x, GameManager.get_terrain_height(spp.x, spp.z), spp.z)
	await frames(3)
	hud.show_forge(smithy)
	hud.forge_set_tab("worker")
	await frames(3)
	var nid := ""
	for k in hud._forge_node_avail.keys():
		if bool(hud._forge_node_avail[k]):
			nid = String(k)
			break
	verdict("B1 в сетке есть доступный узел", nid != "", nid)
	var nbtn: Button = hud._forge_nodes.get(nid)
	var ok_b: Color = _border_of(nbtn)
	verdict("B2 при полном складе узел оплатен", hud.forge_node_afford(nid) and ok_b != hud.FORGE_LACK_BORDER)
	_set_all(0.0)
	await frames(2)
	verdict("B3 склад пуст — узел помечен красной рамкой по сигналу, без пересборки сетки",
		not hud.forge_node_afford(nid) and _border_of(nbtn) == hud.FORGE_LACK_BORDER,
		"рамка %s" % str(_border_of(nbtn)))
	_set_all(20000.0)
	await frames(2)
	verdict("B4 деньги пришли — рамка узла вернулась", hud.forge_node_afford(nid) and _border_of(nbtn) == ok_b)
	hud._show_forge_tip(nid)
	await frames(1)
	var tip: Node = hud._forge_tip
	var icons := 0
	var letter_costs := 0
	if tip != null:
		for n in tip.find_children("*", "", true, false):
			if n is TextureRect and (n as TextureRect).texture != null:
				icons += 1
			if n is Label:
				var t: String = (n as Label).text
				if t.begins_with("Цена:") and (t.contains(" з") or t.contains(" л") or t.contains(" к")):
					letter_costs += 1
	var cost: Dictionary = _UCfg.upgrade_cost(_Forge.get_node(nid))
	verdict("B5 в плашке узла цена иконками ресурсов, без буквенных суффиксов",
		tip != null and icons >= cost.size() and letter_costs == 0,
		"иконок %d при %d ресурсах в цене, строк с буквами %d" % [icons, cost.size(), letter_costs])
	hud._hide_forge_tip()
	hud.hide_forge()

	# ── C. Реплики и шаги ──────────────────────────────────────────────────
	print("\n═════ C. РЕПЛИКИ И ШАГИ ═════")
	AudioManager._voice_last.clear()
	AudioManager._voice_last_any = -999.0
	AudioManager._voice_alt.clear()
	var r1: bool = AudioManager.play_voice("hold_line")
	AudioManager._voice_last.clear()
	AudioManager._voice_last_any = -999.0
	var r2: bool = AudioManager.play_voice("hold_line")
	AudioManager._voice_last.clear()
	AudioManager._voice_last_any = -999.0
	var r3: bool = AudioManager.play_voice("hold_line")
	verdict("C1 «держать строй» играет через раз", r1 and not r2 and r3, "%s %s %s" % [str(r1), str(r2), str(r3)])
	var gap_ok := true
	for ev in AudioManager.VOICE_LIMITS:
		if String(ev) != "horn_attack" and float((AudioManager.VOICE_LIMITS[ev] as Dictionary)["gap"]) < 9.0:
			gap_ok = false
	verdict("C2 окна повтора реплик команд не короче 9 с", gap_ok)
	var loud_db: float = maxf(AudioManager.MARCH_WALK_DB, AudioManager.MARCH_RUN_DB)
	var ceiling_db: float = 20.0 * log(AudioManager.MARCH_BUDGET / sqrt(float(AudioManager.MARCH_VOICES))) / log(10.0)
	verdict("C3 шаги на 30 %% тише прежних (−14.1 / −12.2 дБ) и в бюджете (потолок %.1f дБ)" % ceiling_db,
		AudioManager.MARCH_WALK_DB <= -14.0 and AudioManager.MARCH_RUN_DB <= -12.1 and loud_db <= ceiling_db + 0.01,
		"шаг %.1f, бег %.1f" % [AudioManager.MARCH_WALK_DB, AudioManager.MARCH_RUN_DB])
	_finish()
