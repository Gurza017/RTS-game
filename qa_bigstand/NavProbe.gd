extends Node
## ═══════════════════════════════════════════════════════════════════════════
## ЗОНД ЦЕНЫ МАРШРУТА (аудит 19.09.2026; измеритель, вердиктов нет)
## ═══════════════════════════════════════════════════════════════════════════
## cm_route (build_route внутри command_move) держал 60-100 мкс на приказ при
## том, что до A* доходил лишь каждый восьмой запрос. Зонд гоняет по N раз
## каждую часть дороги на живой карте партии и печатает мкс на вызов:
## проверка линии в ядре, попадание в кэш маршрутов, полный build_route.
## Запуск: <godot> --headless --path . res://qa_bigstand/NavProbe.tscn

const N := 2000
var main = null

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(120.0).timeout.connect(func():
		print("  СТОРОЖ"); get_tree().quit())

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _t(label: String, f: Callable, n: int = N) -> void:
	var t0: int = Time.get_ticks_usec()
	for _i in range(n):
		f.call()
	var dt: int = Time.get_ticks_usec() - t0
	print("  %-46s %8.2f мкс/вызов  (×%d)" % [label, float(dt) / float(n), n])

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	# Пень за рекой в партии заморожен (ТЗ 19.09.2026); стенду нужен живой
	GameManager.call_deferred("thaw_lairs_now")
	await pframes(10)
	var lair = GameManager.troll_lair
	var lp: Vector3 = lair.global_position if lair != null else Vector3.ZERO
	var a := Vector3(lp.x - 44.0, 0.0, lp.z)
	var b := Vector3(lp.x + 30.0, 0.0, lp.z - 5.0)
	var far := Vector3(lp.x - 150.0, 0.0, lp.z + 60.0)
	var army = GameManager.army
	print("  nav_on = %s, ячеек скал %d, компонент %d" % [str(GameManager.nav_on()), GameManager.nav_cells_blocked, army.nav_comp_count()])
	print("  прямая a→b упирается: %s; a→far: %s" % [str(army.nav_line_blocked(a.x, a.z, b.x, b.z)), str(army.nav_line_blocked(a.x, a.z, far.x, far.z))])
	_t("army.nav_line_blocked 75 м", func(): army.nav_line_blocked(a.x, a.z, b.x, b.z))
	_t("army.nav_line_blocked 160 м", func(): army.nav_line_blocked(a.x, a.z, far.x, far.z))
	_t("army.nav_free", func(): army.nav_free(a.x, a.z))
	_t("GameManager.nav_blocked (кэш кадра)", func(): GameManager.nav_blocked(a, b))
	_t("GameManager._nav_key_route", func(): GameManager._nav_key_route(a, b))
	_t("GameManager.nav_route a→b (кэш)", func(): GameManager.nav_route(a, b))
	_t("GameManager.nav_route a→far (кэш)", func(): GameManager.nav_route(a, far))
	_t("GameManager.ford_route", func(): GameManager.ford_route(a, b, 0.0))
	_t("GameManager.build_route a→b lat 0", func(): GameManager.build_route(a, b, 0.0, Vector2.ZERO))
	_t("GameManager.build_route a→b lat 2", func(): GameManager.build_route(a, b, 0.0, Vector2(2.0, 1.0)))
	_t("GameManager.build_route a→far lat 2", func(): GameManager.build_route(a, far, 0.0, Vector2(2.0, 1.0)))
	_t("GameManager.land_target", func(): GameManager.land_target(b))
	_t("army.nav_path a→b (без кэша)", func(): army.nav_path(a.x, a.z, b.x, b.z), 200)
	_t("army.nav_path a→far (без кэша)", func(): army.nav_path(a.x, a.z, far.x, far.z), 200)
	var r: PackedVector3Array = GameManager.nav_route(a, far)
	print("  маршрут a→far: точек %d" % r.size())
	get_tree().quit()
