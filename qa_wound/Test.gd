extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ВИЗУАЛИЗАЦИЯ УРОНА — ВСПЫШКА ОТ УДАРА И ОКРОВАВЛЕННОСТЬ
## ═══════════════════════════════════════════════════════════════════════════
## Проверяется НЕ картинка (её headless не покажет вовсе — см. qa_wound/Shot.gd),
## а то единственное, что вообще может сломаться в этой цепочке: доезжают ли два
## числа до буфера MultiMesh и в тот ли момент.
##
## Раскладка проверяемых чисел — шапка shaders/mm_unit_sprite.gdshader:
##   COLOR.b — сила вспышки, COLOR.a — доля жизни. В теневом буфере бакета это
##   14-й и 15-й float экземпляра (см. FarUnitRenderer.Bucket.STRIDE).
##
## ПОРОГИ ОКРОВАВЛЕННОСТИ (85% / 40%) ЖИВУТ В ШЕЙДЕРЕ И ЗДЕСЬ НЕ ПРОВЕРЯЮТСЯ:
## стенд стережёт СВОЙСТВО «в буфере лежит ровно то, что вернул health_shade()»,
## а не число из настройки (см. CLAUDE.md, правило 10). Владелец волен двигать
## пороги в шейдере, не краснея этим стендом.
##
## Запуск: godot --headless --path . res://qa_wound/Test.tscn

var main = null
var _pass: int = 0
var _fail: int = 0

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

## Подождать РЕАЛЬНОЕ время, а не число кадров: вспышка гаснет по секундам, а
## при снятом ограничении кадров headless успевает нарисовать их сотни
func wait_sec(sec: float) -> void:
	var until: int = Time.get_ticks_msec() + int(sec * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame

func verdict(title: String, ok: bool, detail: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	print("  ВЕРДИКТ %s: %s%s" % [title, "ПРОШЛО" if ok else "НЕ ПРОШЛО",
		("  — " + detail) if detail != "" else ""])

## Что ЛЕЖИТ В БУФЕРЕ про этого бойца: [вспышка, доля жизни]. Пусто — слота нет
func dmg_of(u: Unit) -> Array:
	var s = GameManager.far_units.slot_of(u)
	if s == null or s.bucket == null:
		return []
	var buf: PackedFloat32Array = s.bucket.buf
	var o: int = s.index * s.bucket.STRIDE
	if o + 15 >= buf.size():
		return []
	return [buf[o + 14], buf[o + 15]]

func spawn(fac: int, at: Vector3) -> Unit:
	var u: Unit = load("res://scenes/units/Spearman.tscn").instantiate()
	u.faction = fac
	main.world_add(u)
	u.global_position = Vector3(at.x, GameManager.get_terrain_height(at.x, at.z), at.z)
	u.sync_row()
	return u

func _run() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(10)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	if GameManager.fog != null:
		GameManager.fog.enabled = false
	for n in get_tree().get_nodes_in_group("all_units"):
		(n as Node).queue_free()
	await frames(4)

	print("\n╔══════════════════════════════════════════════════════════════════╗")
	print("║  ВИЗУАЛИЗАЦИЯ УРОНА: ВСПЫШКА И ОКРОВАВЛЕННОСТЬ                    ║")
	print("╚══════════════════════════════════════════════════════════════════╝")

	# ═════ A. ЦЕЛЫЙ БОЕЦ НЕ ПОДКРАШЕН ВОВСЕ ═════
	var u := spawn(Constants.FACTION_PLAYER, Vector3(0.0, 0.0, 0.0))
	await pframes(4)
	await frames(4)
	var d: Array = dmg_of(u)
	verdict("A1 целый боец попал в общую отрисовку", not d.is_empty())
	if d.is_empty():
		print("  провалов: %d из %d" % [_fail, _pass + _fail])
		print("=== WOUND TEST DONE ===")
		get_tree().quit(1)
		return
	verdict("A2 у целого доля жизни = 1", is_equal_approx(float(d[1]), 1.0),
		"в буфере %.3f" % float(d[1]))
	verdict("A3 у целого вспышки нет", is_zero_approx(float(d[0])),
		"в буфере %.3f" % float(d[0]))

	# ═════ B. ОТКЛИК НА УДАР — В ТОМ ЖЕ КАДРЕ ═════
	# Ждать визуального тика нельзя: он шардирован, и вспышка длиной 0.07 с
	# успела бы догореть до первой отрисовки
	u.take_damage(u.max_health * 0.20, null)
	var d2: Array = dmg_of(u)
	verdict("B1 вспышка в буфере СРАЗУ, без единого кадра",
		float(d2[0]) > 0.5, "в буфере %.3f" % float(d2[0]))
	verdict("B2 сила вспышки — заявленный пик",
		is_equal_approx(float(d2[0]), Unit.HIT_FLASH_PEAK),
		"%.3f против HIT_FLASH_PEAK=%.3f" % [float(d2[0]), Unit.HIT_FLASH_PEAK])
	verdict("B3 доля жизни поехала вниз тем же ударом",
		is_equal_approx(float(d2[1]), u.health_shade()),
		"буфер %.3f, health_shade %.3f" % [float(d2[1]), u.health_shade()])

	# ═════ C. ВСПЫШКА ГАСНЕТ САМА ═════
	await wait_sec(Unit.HIT_FLASH_SEC * 3.0 + 0.1)
	var d3: Array = dmg_of(u)
	verdict("C1 вспышка погасла за свой срок", is_zero_approx(float(d3[0])),
		"через %.2f с в буфере %.3f" % [Unit.HIT_FLASH_SEC * 3.0, float(d3[0])])
	verdict("C2 окровавленность ОСТАЛАСЬ (это состояние, а не событие)",
		is_equal_approx(float(d3[1]), u.health_shade()),
		"буфер %.3f, health_shade %.3f" % [float(d3[1]), u.health_shade()])
	verdict("C3 боец не уснул с горящей вспышкой", u.draw_on or float(d3[0]) == 0.0)

	# ═════ D. РАНЕНИЕ ДЕРЖИТСЯ ЧЕРЕЗ СМЕНУ ЛЕНТЫ ═════
	# Пойдя, боец переезжает в бакет другой ленты (idle → walk), а это ПОЛНАЯ
	# перезапись всех шестнадцати чисел его экземпляра. Раньше на этом месте
	# стояли константы «вспышки нет, боец цел», и раненый мигал бы чистым
	u.take_damage(u.max_health * 0.45, null)
	var hp_want: float = u.health_shade()
	u.command_move(Vector3(u.global_position.x + 22.0, 0.0,
		u.global_position.z))
	await pframes(30)
	await frames(6)
	var d4: Array = dmg_of(u)
	verdict("D1 боец на ходу всё ещё в отрисовке", not d4.is_empty())
	if not d4.is_empty():
		verdict("D2 окровавленность пережила смену ленты",
			is_equal_approx(float(d4[1]), hp_want),
			"буфер %.3f, ждали %.3f" % [float(d4[1]), hp_want])

	# ═════ E. ЛЕЧЕНИЕ ВОЗВРАЩАЕТ ЧИСТЫЙ СПРАЙТ ═════
	# Отдельного вызова «обнови подкраску» нет и заводить его нельзя: лечат
	# бойца из четырёх разных мест. Визуальный тик сам замечает, что здоровье
	# разошлось с отданным в отрисовку (см. Unit.tick_visual)
	u.current_health = u.max_health
	await pframes(4)
	await frames(6)
	var d5: Array = dmg_of(u)
	verdict("E1 вылеченный снова чист", is_equal_approx(float(d5[1]), 1.0),
		"в буфере %.3f" % float(d5[1]))

	# ═════ F. ЦЕЛЫЙ СТРОЙ НЕ ПИШЕТ В БУФЕР НИЧЕГО ЛИШНЕГО ═════
	# Цена фичи на неподвижном целом строю обязана быть нулевой: два сравнения
	# float на бойца и ни одной записи. Проверяем по признаку грязи бакета
	var crowd: Array = []
	for i in range(40):
		crowd.append(spawn(Constants.FACTION_PLAYER,
			Vector3(-40.0 + float(i % 8) * 1.5, 0.0, -40.0 + float(i / 8) * 1.5)))
	await pframes(40)
	await frames(20)
	var s0 = GameManager.far_units.slot_of(crowd[0])
	var before: Array = dmg_of(crowd[0])
	s0.bucket.dirty = false
	await frames(3)
	verdict("F1 целый неподвижный строй не грязнит буфер", not s0.bucket.dirty)
	var after: Array = dmg_of(crowd[0])
	verdict("F2 и не переписывает состояние урона",
		before.size() == 2 and after.size() == 2
		and is_equal_approx(float(before[0]), float(after[0]))
		and is_equal_approx(float(before[1]), float(after[1])))

	# ═════ G. ЗАЛП ПО СТРОЮ: ОКРОВАВЛЕНЫ РОВНО ЗАДЕТЫЕ ═════
	var hurt: Array = []
	for i in range(0, crowd.size(), 3):
		var v: Unit = crowd[i]
		v.take_damage(v.max_health * 0.55, null)
		hurt.append(v)
	await pframes(4)
	await frames(6)
	var bad_hurt: int = 0
	var bad_whole: int = 0
	for c in crowd:
		var cu: Unit = c
		if not is_instance_valid(cu) or cu.is_dead():
			continue
		var cd: Array = dmg_of(cu)
		if cd.is_empty():
			continue
		if cu in hurt:
			if not is_equal_approx(float(cd[1]), cu.health_shade()):
				bad_hurt += 1
		elif not is_equal_approx(float(cd[1]), 1.0):
			bad_whole += 1
	verdict("G1 у задетых доля жизни верна", bad_hurt == 0,
		"расхождений: %d" % bad_hurt)
	verdict("G2 соседей залпом не запачкало", bad_whole == 0,
		"лишних: %d" % bad_whole)

	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	print("=== WOUND TEST DONE ===")
	get_tree().quit(1 if _fail > 0 else 0)
