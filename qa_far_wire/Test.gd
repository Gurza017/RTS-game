extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: СВЯЗКА Unit ↔ FarUnitRenderer ЧЕРЕЗ near_view (LOD)
## ═══════════════════════════════════════════════════════════════════════════
## qa_far_render проверяет модуль изолированно (бухгалтерия слотов).
## Этот стенд проверяет то, что модуль САМ ПО СЕБЕ проверить не может:
## что Unit._process реально переключает юнита между своим узлом и общим
## MultiMesh, когда он пересекает GameManager.near_view() — регистрация,
## снятие узла, обратный переход и очистка при удалении юнита.
##
## Запуск: godot --headless --path . res://qa_far_wire/Test.tscn

const _OptCfg = preload("res://scripts/perf_config.gd")

var main = null
var _pass: int = 0
var _fail: int = 0
var _log: Array = []

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func verdict(title: String, ok: bool, detail: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	_log.append([title, ok])
	print("  ВЕРДИКТ %s: %s%s" % [title, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + detail) if detail != "" else ""])

func _new(kind: String, fac: int, at: Vector3) -> Unit:
	var u: Unit
	match kind:
		"spearman": u = Spearman.new()
		"archer":   u = Archer.new()
		"warrior":  u = Warrior.new()
		_:          u = Worker.new()
	u.faction = fac
	main.world_add(u)
	u.global_position = at
	return u

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(5)
	for n in get_tree().get_nodes_in_group("all_units"):
		(n as Node).queue_free()
	await frames(3)
	# LOD в этом стенде решает сам GameManager.near_view — точку обзора обычно
	# ставит RTSCamera._process, но камера здесь не крутится, выставляем вручную.
	#
	# КАМЕРУ ОБЯЗАТЕЛЬНО ГЛУШИМ. Раньше хватало одной установки точки обзора,
	# потому что партия начиналась с камерой в нуле. Теперь Main.start_game()
	# уводит её к базе игрока (PLAYER_BASE_ANCHOR, сотни метров от начала
	# координат) и RTSCamera._process переписывает точку обзора КАЖДЫЙ кадр —
	# юнит в (5, 0, 5) оказывался «дальним», и проверки 1 и 3 падали, хотя
	# переключение LOD работает правильно
	if main._camera != null:
		main._camera.set_process(false)
		main._camera.set_physics_process(false)
	GameManager.update_view_point(Vector3.ZERO)
	# ── ГРАНИЦЫ МИРА СНЯТЫ, И ЭТО НЕ ПРИДИРКА ───────────────────────────────
	# Стенд ставит «дальних» на lod_radius × 3 = 270 м, а карта вдвое меньше
	# (полуразмер ~71 м). Любой шаг такого бойца зажимался краем карты, он
	# оказывался на 71 м от центра — то есть ВНУТРИ радиуса LOD, — и проверка
	# «ушедший вдаль зарегистрирован» падала. Падала не всегда, а когда боец
	# успевал сделать хоть один шаг: отсюда и историческая «раз из трёх» в
	# комментарии ниже. Точки за картой здесь намеренные, значит и границы
	# должны быть сняты
	GameManager.world_bounds_enabled = false
	# ТУМАН ЗДЕСЬ ГЛУШИМ — по той же причине, что и камеру выше.
	# Стенд проверяет переключение LOD по ДАЛЬНОСТИ, а половина его юнитов —
	# чужие и стоят за сотни метров, то есть в неразведанном тумане. Чужой в
	# тумане снимается с общей отрисовки намеренно (Unit.tick_visual), и без
	# этой строки проверки 2/3/6 меряли бы уже не LOD, а сокрытие туманом
	if GameManager.fog != null:
		GameManager.fog.enabled = false
		GameManager.fog.set_plane_visible(false)

	print("\n╔══════════════════════════════════════════════════════════════════╗")
	print("║  Unit ↔ FarUnitRenderer: ПЕРЕКЛЮЧЕНИЕ ПО near_view                ║")
	print("╚══════════════════════════════════════════════════════════════════╝")
	# ЭТОТ СТЕНД ПРОВЕРЯЕТ ИМЕННО ПЕРЕКЛЮЧЕНИЕ ПО ДАЛЬНОСТИ, поэтому режим
	# «вся армия в общем MultiMesh» здесь выключен: с ним регистрируются ВСЕ
	# бойцы, и переключаться нечему. Сам режим проверяется ниже, отдельным
	# блоком, и это разные механики, а не одна с разными настройками
	_OptCfg.mm_render_all = false
	await frames(3)

	var radius: float = sqrt(GameManager._view_r2)

	# ═════ 1. БЛИЗКИЙ ЮНИТ — СВОЙ УЗЕЛ, БЕЗ РЕГИСТРАЦИИ ═════
	var near_u := _new("spearman", Constants.FACTION_PLAYER, Vector3(5, 0, 5))
	await frames(20)
	verdict("1 близкий юнит НЕ зарегистрирован в far_units", not GameManager.far_units.is_registered(near_u))
	verdict("1 свой спрайт близкого юнита виден", near_u._active_sprite != null and near_u._active_sprite.visible)

	# ═════ 2. ДАЛЬНИЙ ЮНИТ — СВОЙ УЗЕЛ СПРЯТАН, ЗАРЕГИСТРИРОВАН ═════
	var far_u := _new("archer", Constants.FACTION_ENEMY, Vector3(radius * 3.0, 0, 0))
	await frames(20)
	verdict("2 дальний юнит зарегистрирован в far_units", GameManager.far_units.is_registered(far_u))
	verdict("2 свой спрайт дальнего юнита спрятан", far_u._active_sprite != null and not far_u._active_sprite.visible)

	# ═════ 3. ДАЛЬНИЙ ПОДХОДИТ БЛИЖЕ — ВОЗВРАТ К СВОЕМУ УЗЛУ ═════
	far_u.global_position = Vector3(1, 0, 1)
	# СЫРОЙ ПЕРЕНОС ОБЯЗАН ПОПРАВИТЬ СТРОКУ ЯДРА АРМИИ (правило из CLAUDE.md:
	# «sync_row() для всего, что двигает бойца в обход тика»). Кадр отрисовки
	# берёт координату ИЗ СТРОКИ, а не у узла, и без синхронизации LOD считает
	# расстояние до СТАРОЙ точки — проверка то проходила, то нет, в зависимости
	# от того, успел ли кто-то обновить строку по своим причинам
	far_u.sync_row()
	await frames(20)
	verdict("3 вернувшийся юнит снят с far_units", not GameManager.far_units.is_registered(far_u))
	verdict("3 свой спрайт вернувшегося юнита снова виден", far_u._active_sprite != null and far_u._active_sprite.visible)

	# ═════ 4. БЛИЗКИЙ УХОДИТ ДАЛЕКО — РЕГИСТРАЦИЯ ═════
	# ПОСЛЕ ТЕЛЕПОРТА ЮНИТА НАДО РАЗБУДИТЬ. Осевший в IDLE боец выключает свой
	# _process (см. «РАСКЛАДКА РАБОТЫ ПО КАДРАМ» в Unit.gd), а вместе с ним и
	# _sync_far_render, так что сырая запись в global_position мимо системы
	# приказов остаётся им незамеченной — ровно та же оговорка, что уже описана
	# у проверки 6 ниже. В настоящей игре юнит, который куда-то уехал, движется
	# приказом и потому не спит; здесь роль пробуждения играет wake_for_lod()
	# Будим КАЖДЫЙ кадр, а не один раз: осевший боец гасит свой _process снова
	# в том же tick_visual, и одиночное пробуждение выигрывало гонку не всегда
	# (проверка падала примерно раз из трёх). Идущий приказом юнит в реальной
	# игре не спит вовсе — здесь это и воспроизводим
	near_u.global_position = Vector3(0, 0, radius * 3.0)
	near_u.sync_row()
	for _i in range(20):
		near_u.wake_for_lod()
		await get_tree().process_frame
	verdict("4 ушедший вдаль юнит зарегистрирован", GameManager.far_units.is_registered(near_u))
	verdict("4 свой спрайт ушедшего вдаль спрятан", near_u._active_sprite != null and not near_u._active_sprite.visible)

	# ═════ 5. УДАЛЕНИЕ ДАЛЬНЕГО ЮНИТА ЧИСТИТ РЕЕСТР ═════
	var before: int = GameManager.far_units.registered_count()
	near_u.queue_free()
	await frames(3)
	verdict("5 удаление зарегистрированного юнита снимает слот",
		GameManager.far_units.registered_count() == before - 1,
		"было %d, стало %d" % [before, GameManager.far_units.registered_count()])

	# ═════ 6. ГИБЕЛЬ ДАЛЬНЕГО ЮНИТА ТОЖЕ ЧИСТИТ РЕЕСТР ═════
	# Свежий юнит — far_u из шага 3 уже осел near_view и уснул (_proc_sleeping),
	# а сырой телепорт (не боевое движение) спящего не будит, это не баг
	# реального геймплея (см. wake_for_lod), просто не годится для этой проверки
	var dying_u := _new("warrior", Constants.FACTION_ENEMY, Vector3(radius * 3.0, 0, radius * 3.0))
	await frames(20)
	var before2: int = GameManager.far_units.registered_count()
	verdict("6 юнит перед гибелью зарегистрирован (подготовка)", GameManager.far_units.is_registered(dying_u))
	dying_u.take_damage(100000.0, null)
	await frames(3)
	verdict("6 гибель дальнего юнита снимает слот",
		GameManager.far_units.registered_count() == before2 - 1,
		"было %d, стало %d" % [before2, GameManager.far_units.registered_count()])

	for u in [near_u, far_u]:
		if is_instance_valid(u): (u as Node).queue_free()
	await frames(3)

	# ═════ 7. РЕЖИМ «ВСЯ АРМИЯ В ОБЩЕМ MultiMesh» ═════
	# Другая механика, а не настройка предыдущей: здесь в общую отрисовку идёт
	# и БЛИЖНИЙ боец тоже, и его собственный узел-спрайт спрятан навсегда —
	# именно это снимает вызовы отрисовки с тех, кого видно в кадре
	_OptCfg.mm_render_all = true
	var close_u := _new("spearman", Constants.FACTION_PLAYER, Vector3(3, 0, 3))
	await frames(20)
	verdict("7 близкий боец зарегистрирован в общей отрисовке",
		GameManager.far_units.is_registered(close_u))
	verdict("7 свой узел близкого бойца спрятан",
		close_u._active_sprite != null and not close_u._active_sprite.visible)
	# Лента и кадр обязаны читаться — иначе рисовать в MultiMesh нечего
	var sf: Array = close_u.sheet_frame()
	verdict("7 у бойца читается лента кадров", not sf.is_empty(),
		"sheet_frame() вернул %d полей" % sf.size())
	verdict("7 заведён хотя бы один бакет отрисовки",
		GameManager.far_units.bucket_count() > 0,
		"бакетов: %d" % GameManager.far_units.bucket_count())
	if is_instance_valid(close_u):
		(close_u as Node).queue_free()
	await frames(3)

	print("\n═════ ИТОГ ═════")
	for row in _log:
		print("  %-58s%s" % [String(row[0]), "ПРОШЛО" if bool(row[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	print("\n=== FAR WIRE TEST DONE ===")
	get_tree().quit()
