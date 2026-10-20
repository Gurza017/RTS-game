extends Node

## ═══════════════════════════════════════════════════════════════════════════
## ОЧЕРЕДЬ КУЗНИЦЫ НЕ ЗАВИСАЕТ «В ОЧЕРЕДИ (-1)» (ТЗ 11.10.2026, второе письмо)
## ═══════════════════════════════════════════════════════════════════════════
## A — кузницу снесли посреди исследования: отметка «в работе» снята, цена
##     вернулась, новая кузница заказывает тот же узел.
## B — сирота (отметка без кузницы-владельца): панель кузницы снимает её сама
##     при построении дерева, узел снова доступен, цена вернулась.
## C — ПКМ по узлу, который качает ДРУГАЯ кузница фракции, снимает заказ там.
## D — «Играть заново»: заказ и изученное прошлой партии не переживают сцену.
## Запуск: godot --headless --path . res://qa_forge_queue/Test.tscn

const F := Constants.FACTION_PLAYER
const _Forge := preload("res://scripts/forge_config.gd")

var main = null
var hud = null
var _pass := 0
var _fail := 0

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(180.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился")
		_finish())

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО", ("  — " + d) if d != "" else ""])

var _done := false
func _finish() -> void:
	if _done:
		return
	_done = true
	print("\n═════ ИТОГ qa_forge_queue: прошло %d, провалов: %d ═════" % [_pass, _fail])
	get_tree().quit()

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _give(v: float) -> void:
	for t in [Constants.RESOURCE_WOOD, Constants.RESOURCE_STONE, Constants.RESOURCE_GOLD, Constants.RESOURCE_FOOD]:
		ResourceManager.set_amount(F, int(t), v)

func _smithy(at: Vector3) -> Smithy:
	var s := Smithy.new()
	s.faction = F
	main.world_add(s)
	s.global_position = at
	return s

func _wood() -> float:
	return ResourceManager.get_amount(F, Constants.RESOURCE_WOOD)

func _boot() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(5)
	hud = main.hud
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	await frames(3)

func _unboot() -> void:
	get_tree().root.remove_child(main)
	main.queue_free()
	await frames(3)

func _run() -> void:
	await _boot()
	var n1: String = _Forge.node_id("spearman", "1a")
	var n2: String = _Forge.node_id("spearman", "1b")

	# ── A. СНОС ПОСРЕДИ ИССЛЕДОВАНИЯ ─────────────────────────────────────────
	_give(100000.0)
	var s1 := _smithy(Vector3(-60, 0, 60))
	await frames(3)
	var w0: float = _wood()
	s1.research(n1)
	var paid: bool = _wood() < w0
	s1._die()
	await frames(3)
	verdict("A1 снос кузницы снимает отметку «в работе»", paid and not GameManager.is_researching(F, n1),
		"списано=%s, в работе=%s" % [paid, GameManager.is_researching(F, n1)])
	verdict("A2 цена вернулась", absf(_wood() - w0) < 0.5, "дерево %.0f → %.0f" % [w0, _wood()])
	var s2 := _smithy(Vector3(-50, 0, 60))
	await frames(3)
	verdict("A3 новая кузница заказывает тот же узел", s2.research(n1) and s2.queue_position(n1) == 0)
	s2.cancel_research(n1)

	# ── B. СИРОТА ────────────────────────────────────────────────────────────
	var w1: float = _wood()
	GameManager.start_research(F, n2)          # отметка без кузницы-владельца
	hud.show_selection([s2])
	await frames(3)
	verdict("B1 панель снимает сироту", not GameManager.is_researching(F, n2))
	verdict("B2 цена сироты вернулась", absf(_wood() - w1) < 0.5, "дерево %.0f → %.0f" % [w1, _wood()])
	verdict("B3 узел снова можно заказать", GameManager.can_research(F, n2))

	# ── C. ПКМ ПО ЗАКАЗУ ДРУГОЙ КУЗНИЦЫ ──────────────────────────────────────
	var s3 := _smithy(Vector3(-40, 0, 60))
	await frames(3)
	s3.research(n2)
	hud.show_selection([s2])
	await frames(2)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_RIGHT
	ev.pressed = true
	hud._on_upgrade_gui_input(ev, s2, n2)
	await frames(2)
	verdict("C1 ПКМ снимает заказ другой кузницы", not GameManager.is_researching(F, n2) and s3.queue_position(n2) == -1,
		"в работе=%s, место в s3=%d" % [GameManager.is_researching(F, n2), s3.queue_position(n2)])

	# ── D. «ИГРАТЬ ЗАНОВО» ───────────────────────────────────────────────────
	s3.research(n2)
	GameManager.finish_research(F, n1)
	verdict("D0 перед перезапуском: заказ идёт, узел изучен",
		GameManager.is_researching(F, n2) and GameManager.is_researched(F, n1))
	await _unboot()
	await _boot()
	verdict("D1 после перезапуска заказ прошлой партии не висит", not GameManager.is_researching(F, n2))
	verdict("D2 изученное прошлой партии не переехало", not GameManager.is_researched(F, n1))
	await _unboot()
	_finish()
