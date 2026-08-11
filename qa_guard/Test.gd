extends Node

## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД: ЗАЩИТА ЩИТОМ МЕЧНИКА (WARRIOR_GUARD / AUTO-GUARD)
## ═══════════════════════════════════════════════════════════════════════════
##   A СПРАЙТ      — лист Warrior_Guard.png найден, анимация зарегистрирована
##   B ФЛИП        — разворот влево/вправо зеркалом билборда
##   C УРОН        — стрелы −70%, ближний −50%, удар в спину без скидки
##   D ПОКОЙ       — стоя щит поднимается сам
##   E СКОРОСТЬ    — под щитом шаг медленнее на 35%, но юнит НЕ встаёт
##   F ВЫКЛЮЧЕНО   — переключатель снят: щита нет, урон полный, скорость полная
##   G UI          — кнопка есть, горит/тухнет, реально переключает
##   H СОН         — армия со щитами не мешает _process засыпать

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

func _pad(s: String, n: int) -> String:
	var out := s
	while out.length() < n: out += " "
	return out

## Чистый мечник в заданной точке, без отряда и без приказов
func _new_warrior(at: Vector3, fac: int = Constants.FACTION_PLAYER) -> Warrior:
	var w := Warrior.new()
	w.faction = fac
	main.world_add(w)
	w.global_position = at
	return w

func _new_archer(at: Vector3, fac: int = Constants.FACTION_ENEMY) -> Archer:
	var a := Archer.new()
	a.faction = fac
	main.world_add(a)
	a.global_position = at
	return a

func _run() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(5)
	# Границы мира стенду мешают: арены вынесены далеко от игровой карты
	GameManager.world_bounds_enabled = false
	# ОТСЕЧЕНИЕ ДАЛЬНИХ СПРАЙТОВ СНИМАЕМ. Площадка стенда вынесена за сотни
	# метров от точки обзора камеры, то есть заведомо за perf_config.lod_radius:
	# поза спрайта там намеренно не пересчитывается (её всё равно не видно),
	# и проверять анимацию щита в таких условиях бессмысленно
	preload("res://scripts/perf_config.gd").sprite_lod = false
	for t in [Constants.RESOURCE_WOOD, Constants.RESOURCE_GOLD,
			Constants.RESOURCE_STONE, Constants.RESOURCE_FOOD]:
		ResourceManager.add_resource(Constants.FACTION_PLAYER, int(t), 1000000.0)
	if main.enemy_ai != null:
		main.enemy_ai.set_process(false)
	await frames(3)

	await _a_sprite()
	await _b_flip()
	await _c_damage()
	await _d_idle()
	await _e_speed()
	await _f_disabled()
	await _g_ui()
	await _h_sleep()
	await _i_order()
	await _j_wake_speed()

	print("\n═════ ИТОГ ═════")
	for e in _log:
		var row: Array = e
		print("  %s%s" % [_pad(String(row[0]), 62), "ПРОШЛО" if bool(row[1]) else "НЕ ПРОШЛО"])
	print("  провалов: %d из %d" % [_fail, _pass + _fail])
	print("\n=== GUARD TEST DONE ===")
	get_tree().quit()

# ═════════════════════════════════════════════════════════════════════════════
# A. СПРАЙТ И АНИМАЦИЯ
# ═════════════════════════════════════════════════════════════════════════════
func _a_sprite() -> void:
	print("\n═════ A. СПРАЙТ WARRIOR_GUARD ═════")

	# A1. Файл лежит там, где его ищет Warrior._setup_warrior_visual
	var packs: Array = [
		"res://assets/factions/humans/units/soldier_pack/Warrior_Guard.png",
		"res://assets/factions/humans/units/Blue Units/Warrior/Warrior_Guard.png",
		"res://assets/factions/humans/units/Red Units/Warrior/Warrior_Guard.png",
	]
	var missing: Array = []
	for p in packs:
		var abs_p: String = ProjectSettings.globalize_path(String(p))
		if not FileAccess.file_exists(abs_p):
			missing.append(String(p).get_file())
	verdict("A1 файл Warrior_Guard.png во всех наборах", missing.is_empty(),
		"нет: %s" % str(missing))

	# A2. Анимация действительно попала в SpriteFrames живого мечника
	var w := _new_warrior(Vector3(0, 0, -400))
	await frames(3)
	var asp := w._active_sprite as AnimatedSprite3D
	var has_guard: bool = asp != null and asp.sprite_frames != null \
		and asp.sprite_frames.has_animation(Warrior.GUARD_ANIM)
	var nframes: int = asp.sprite_frames.get_frame_count(Warrior.GUARD_ANIM) if has_guard else 0
	verdict("A2 анимация '%s' зарегистрирована" % Warrior.GUARD_ANIM,
		has_guard and nframes > 0, "кадров: %d" % nframes)

	# A3. Щит ДЕРЖАТ — цикл; удар проигрывается один раз
	var guard_loops: bool = has_guard and asp.sprite_frames.get_animation_loop(Warrior.GUARD_ANIM)
	var atk_once: bool = asp != null and asp.sprite_frames.has_animation("attack1") \
		and not asp.sprite_frames.get_animation_loop("attack1")
	verdict("A3 guard зациклен, attack1 — нет", guard_loops and atk_once,
		"guard.loop=%s attack1.loop=%s" % [guard_loops, not atk_once])

	# A4. Имя листа именно Warrior_Guard.png (константа, а не догадка)
	verdict("A4 источник кадров — Warrior_Guard.png",
		Warrior.GUARD_SHEET == "Warrior_Guard.png", Warrior.GUARD_SHEET)

	w.queue_free()
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# B. ГОРИЗОНТАЛЬНЫЙ ФЛИП (нет отдельных спрайтов влево/вправо)
# ═════════════════════════════════════════════════════════════════════════════
func _b_flip() -> void:
	print("\n═════ B. ЗЕРКАЛЬНЫЙ РАЗВОРОТ ═════")
	var w := _new_warrior(Vector3(0, 0, -400))
	await frames(3)
	# ЗЕРКАЛО И АНИМАЦИЯ ЖИВУТ ЧИСЛАМИ В САМОМ БОЙЦЕ (_flip_h_state / _anim_name),
	# а не в свойствах узла: в общей отрисовке (MultiMesh) узел спрайта невидим и
	# не пишется вовсе, поэтому spr.flip_h — уже не источник правды
	var spr := w._active_sprite as SpriteBase3D
	if spr == null:
		verdict("B1 спрайт мечника существует", false, "_active_sprite не SpriteBase3D")
		w.queue_free()
		return

	var cam := get_viewport().get_camera_3d()
	if cam == null:
		verdict("B1 камера найдена", false, "нет активной камеры")
		w.queue_free()
		return
	var cam_right := cam.global_transform.basis.x

	# Идём ВПРАВО по экрану — зеркала нет
	w.state = Unit.State.MOVING
	w.velocity = cam_right * 3.0
	w._facing = cam_right.normalized()
	w._flip_dirty = true
	w._update_sprite_flip()
	var right_flip: bool = w._flip_h_state

	# Идём ВЛЕВО по экрану — тот же лист, отражённый
	w.velocity = -cam_right * 3.0
	w._facing = (-cam_right).normalized()
	w._flip_dirty = true
	w._update_sprite_flip()
	var left_flip: bool = w._flip_h_state

	verdict("B1 вправо — без зеркала", right_flip == false, "flip_h=%s" % right_flip)
	verdict("B2 влево — зеркало включено", left_flip == true, "flip_h=%s" % left_flip)
	verdict("B3 стороны различаются", right_flip != left_flip)

	# Щит поднят — флип продолжает работать (лист один на обе стороны)
	w._guard_active = true
	w._update_sprite_anim()
	var anim_now: String = String(w._anim_name)
	w.velocity = cam_right * 3.0
	w._facing = cam_right.normalized()
	w._flip_dirty = true
	w._update_sprite_flip()
	verdict("B4 под щитом флип работает и анимация guard",
		w._flip_h_state == false and anim_now == Warrior.GUARD_ANIM,
		"flip_h=%s anim=%s" % [w._flip_h_state, anim_now])

	w.queue_free()
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# C. СНИЖЕНИЕ УРОНА
# Замер честный: один и тот же удар по одному и тому же бойцу, разница только
# в поднятом щите. Сравниваем ФАКТИЧЕСКУЮ убыль здоровья.
# ═════════════════════════════════════════════════════════════════════════════

## Ударить мечника и вернуть, сколько здоровья он потерял
func _hit(w: Warrior, attacker: Node3D, dmg: float, guard: bool) -> float:
	w.current_health = w.max_health
	w._guard_active = guard
	var before: float = w.current_health
	w.take_damage(dmg, attacker)
	return before - w.current_health

func _c_damage() -> void:
	print("\n═════ C. УРОН ПОД ЩИТОМ ═════")
	var w := _new_warrior(Vector3(0, 0, -400))
	# Смотрит на +X: атакующий с +X — в лоб, с −X — в спину
	w._facing = Vector3(1, 0, 0)
	var front := _new_archer(Vector3(10, 0, -400))
	var back  := _new_archer(Vector3(-10, 0, -400))
	# Ближний бой изображает копейщик: щит должен отличать его от лучника
	var melee := Spearman.new()
	melee.faction = Constants.FACTION_ENEMY
	main.world_add(melee)
	melee.global_position = Vector3(3, 0, -400)
	await frames(3)
	# Мечник не должен убегать в атаку и менять _facing посреди замера
	front.set_process(false); front.set_physics_process(false)
	back.set_process(false);  back.set_physics_process(false)
	melee.set_process(false); melee.set_physics_process(false)
	w.set_physics_process(false)
	# ВАЖНО: ракурс задаётся ПОСЛЕ ожидания кадров. Лучники — живые враги и
	# успевают выстрелить, а notify_incoming_fire разворачивает стоящего лицом к
	# стрелку. Если не переставить _facing здесь, «спереди» и «сзади» в замере
	# меняются местами по воле случая
	w._facing = Vector3(1, 0, 0)
	w._threat_until_ms = 0

	var dmg := 40.0
	var base_arrow: float = _hit(w, front, dmg, false)
	var guard_arrow: float = _hit(w, front, dmg, true)
	var base_melee: float = _hit(w, melee, dmg, false)
	var guard_melee: float = _hit(w, melee, dmg, true)
	var guard_back: float = _hit(w, back, dmg, true)

	print("  стрела: без щита %.2f → под щитом %.2f" % [base_arrow, guard_arrow])
	print("  ближний: без щита %.2f → под щитом %.2f" % [base_melee, guard_melee])
	print("  в спину под щитом: %.2f (эталон без щита %.2f)" % [guard_back, base_arrow])

	var want_arrow: float = base_arrow * (1.0 - Warrior.GUARD_CUT_RANGED)
	var want_melee: float = base_melee * (1.0 - Warrior.GUARD_CUT_MELEE)
	verdict("C1 стрела режется на 70%%", absf(guard_arrow - want_arrow) < 0.01,
		"ждали %.2f, получили %.2f" % [want_arrow, guard_arrow])
	verdict("C2 ближний бой режется на 50%%", absf(guard_melee - want_melee) < 0.01,
		"ждали %.2f, получили %.2f" % [want_melee, guard_melee])
	verdict("C3 удар в спину щит НЕ держит", absf(guard_back - base_arrow) < 0.01,
		"в спину %.2f, без щита %.2f" % [guard_back, base_arrow])
	verdict("C4 щит не даёт бессмертия", guard_arrow > 0.0, "%.3f" % guard_arrow)

	# Предупреждение о выстреле поднимает щит ДО прилёта стрелы
	w.set_physics_process(true)
	w._guard_active = false
	w._threat_until_ms = 0
	w.state = Unit.State.IDLE
	w.notify_incoming_fire(front.global_position)
	w._update_guard()
	verdict("C5 выстрел поднимает щит заранее", w.is_guarding(),
		"threat=%s guard=%s" % [w._threatened(), w.is_guarding()])

	# И разворачивает стоящего лицом к стрелку
	w.state = Unit.State.IDLE
	w._facing = Vector3(1, 0, 0)
	w.notify_incoming_fire(back.global_position)   # стрелок слева (−X)
	verdict("C6 стоящий разворачивается к стрелку", w._facing.x < -0.5,
		"_facing=%s" % str(w._facing))

	w.queue_free(); front.queue_free(); back.queue_free(); melee.queue_free()
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# D. ЩИТ В ПОКОЕ
# ═════════════════════════════════════════════════════════════════════════════
func _d_idle() -> void:
	print("\n═════ D. ЩИТ В ПОКОЕ ═════")
	var w := _new_warrior(Vector3(0, 0, -400))
	await frames(10)
	var asp := w._active_sprite as AnimatedSprite3D
	verdict("D1 стоя без дела щит поднят", w.is_guarding(),
		"state=%d guard=%s" % [w.state, w.is_guarding()])
	verdict("D2 играет анимация guard", asp != null and asp.animation == Warrior.GUARD_ANIM,
		"anim=%s" % (asp.animation if asp else "нет"))

	# Замах опускает щит: одновременно бить и закрываться нельзя
	w._anim_lock_until_ms = Time.get_ticks_msec() + 400
	w._update_guard()
	verdict("D3 во время замаха щит опущен", not w.is_guarding())
	w._anim_lock_until_ms = 0

	w.queue_free()
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# E. СКОРОСТЬ ПОД ЩИТОМ
# ═════════════════════════════════════════════════════════════════════════════
func _e_speed() -> void:
	print("\n═════ E. МАРШ ПОД ОБСТРЕЛОМ ═════")
	var w := _new_warrior(Vector3(0, 0, -400))
	await frames(3)
	w.state = Unit.State.MOVING
	w._guard_active = false
	var free_speed: float = w._effective_speed()
	w._guard_active = true
	var guard_speed: float = w._effective_speed()
	var ratio: float = guard_speed / maxf(free_speed, 0.001)
	print("  скорость: свободно %.2f → под щитом %.2f (×%.2f)" % [free_speed, guard_speed, ratio])
	verdict("E1 под щитом скорость −30..40%%", ratio >= 0.60 and ratio <= 0.70,
		"×%.3f" % ratio)
	verdict("E2 мечник НЕ останавливается", guard_speed > 0.5, "%.2f м/с" % guard_speed)
	w.queue_free()

	# Интеграционно: два мечника идут в одну точку, одного обстреливают
	var a := _new_warrior(Vector3(0, 0, -420))
	var b := _new_warrior(Vector3(0, 0, -440))
	await frames(3)
	a.command_move(Vector3(40, 0, -420))
	b.command_move(Vector3(40, 0, -440))
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 2500:
		# b держим под непрерывным обстрелом, a идёт спокойно
		b.notify_incoming_fire(Vector3(0, 0, -440))
		await get_tree().process_frame
	var da: float = a.global_position.x
	var db: float = b.global_position.x
	print("  прошли за 2.5 с: спокойно %.1f м, под обстрелом %.1f м" % [da, db])
	verdict("E3 обстрелянный отстал, но идёт", db > 1.0 and db < da * 0.95,
		"%.1f против %.1f" % [db, da])
	verdict("E4 под обстрелом щит поднят на ходу", b.is_guarding(),
		"state=%d guard=%s" % [b.state, b.is_guarding()])
	a.queue_free(); b.queue_free()
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# F. ПЕРЕКЛЮЧАТЕЛЬ СНЯТ
# ═════════════════════════════════════════════════════════════════════════════
func _f_disabled() -> void:
	print("\n═════ F. АВТО-ЗАЩИТА ВЫКЛЮЧЕНА ═════")
	var w := _new_warrior(Vector3(0, 0, -400))
	w._facing = Vector3(1, 0, 0)
	var arch := _new_archer(Vector3(10, 0, -400))
	await frames(3)
	arch.set_process(false); arch.set_physics_process(false)
	w.set_auto_guard(false)
	await frames(5)

	verdict("F1 стоя щит НЕ поднимается", not w.is_guarding())

	w.notify_incoming_fire(arch.global_position)
	w._update_guard()
	verdict("F2 стрелы игнорируются", not w.is_guarding() and not w._threatened())

	w.set_physics_process(false)
	var dealt: float = _hit(w, arch, 40.0, false)
	w._update_guard()
	var still_off: bool = not w.is_guarding()
	# После попадания угроза тоже не взводится — переключатель снят
	verdict("F3 попадание не взводит щит", still_off and not w._threatened())

	w.state = Unit.State.MOVING
	w._guard_active = false
	var full: float = w._effective_speed()
	w._update_guard()
	verdict("F4 скорость полная (100%%)", absf(w._effective_speed() - full) < 0.001,
		"%.2f м/с" % full)

	# Обратно включаем — механика оживает
	w.set_auto_guard(true)
	w.state = Unit.State.IDLE
	w._update_guard()
	verdict("F5 повторное включение возвращает щит", w.is_guarding(),
		"урон без щита был %.1f" % dealt)

	w.queue_free(); arch.queue_free()
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# G. КНОПКА НА ПАНЕЛИ ЮНИТА
# ═════════════════════════════════════════════════════════════════════════════
func _find_btn(label: String) -> Button:
	var hud = main.hud
	if hud == null or hud.button_container == null:
		return null
	for c in hud.button_container.get_children():
		var b := c as Button
		if b == null:
			continue
		if b.text == label or b.tooltip_text.begins_with(label):
			return b
	return null

func _btn_bg(b: Button) -> Color:
	var sb := b.get_theme_stylebox("normal") as StyleBoxFlat
	return sb.bg_color if sb != null else Color.BLACK

func _g_ui() -> void:
	print("\n═════ G. КНОПКА «АВТО-ЩИТ» ═════")
	var w := _new_warrior(Vector3(0, 0, -400))
	await frames(3)

	main.hud.show_selection([w])
	await frames(2)
	var btn: Button = _find_btn("Пассивное умение")
	verdict("G1 кнопка появилась у мечника", btn != null)
	if btn == null:
		w.queue_free()
		return

	var col_on: Color = _btn_bg(btn)
	var lum_on: float = col_on.r + col_on.g + col_on.b
	verdict("G2 тултип «Стена щитов» на месте", "Стена щитов" in btn.tooltip_text and "обстрел" in btn.tooltip_text,
		btn.tooltip_text)

	# Нажатие
	btn.pressed.emit()
	await frames(2)
	verdict("G3 клик выключает авто-защиту", not w.auto_guard)

	var btn2: Button = _find_btn("Пассивное умение")
	verdict("G4 кнопка на месте после перерисовки", btn2 != null)
	if btn2 != null:
		var col_off: Color = _btn_bg(btn2)
		var lum_off: float = col_off.r + col_off.g + col_off.b
		print("  яркость: ВКЛ %.2f → ВЫКЛ %.2f" % [lum_on, lum_off])
		verdict("G5 выключенная кнопка тухнет", lum_off < lum_on * 0.75,
			"%.2f против %.2f" % [lum_off, lum_on])
		btn2.pressed.emit()
		await frames(2)
		verdict("G6 повторный клик включает обратно", w.auto_guard)

	# Кнопка не должна лезть к рабочим
	var wk := Worker.new()
	wk.faction = Constants.FACTION_PLAYER
	main.world_add(wk)
	wk.global_position = Vector3(5, 0, -400)
	await frames(3)
	main.hud.show_selection([wk])
	await frames(2)
	verdict("G7 у рабочего кнопки нет", _find_btn("Пассивное умение") == null)

	# Групповое переключение: три мечника разом
	var men: Array = []
	for i in range(3):
		men.append(_new_warrior(Vector3(i * 2, 0, -410)))
	await frames(3)
	main.hud.show_selection(men)
	await frames(2)
	var gb: Button = _find_btn("Пассивное умение")
	# ЗАПОМИНАЕМ ФАКТ СРАЗУ: нажатие перерисовывает панель и освобождает кнопку,
	# а освобождённый объект в Godot 4 сравнивается с null как РАВНЫЙ — проверка
	# «gb != null» после клика соврала бы
	var had_btn: bool = gb != null
	if had_btn:
		gb.pressed.emit()
		await frames(2)
	var all_off := true
	for m in men:
		if (m as Warrior).auto_guard:
			all_off = false
	verdict("G8 переключает весь выделенный отряд", had_btn and all_off)

	w.queue_free(); wk.queue_free()
	for m in men:
		(m as Node).queue_free()
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# H. СОН _process СО ЩИТОМ
# Главный риск щита «в покое»: базовый _process_can_sleep не спит ни при какой
# анимации, кроме idle. Стоящая армия мечников не должна съесть кадр.
# ═════════════════════════════════════════════════════════════════════════════
func _h_sleep() -> void:
	print("\n═════ H. СОН СТОЯЩЕГО МЕЧНИКА ═════")
	var men: Array = []
	for i in range(20):
		men.append(_new_warrior(Vector3(i * 1.5, 0, -460)))
	# Ждём, пока улягутся: расталкивание соседей сначала держит их в движении
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 4000:
		await get_tree().process_frame
	var asleep := 0
	var guarding := 0
	for m in men:
		var mw := m as Warrior
		if not mw.is_processing():
			asleep += 1
		if mw.is_guarding():
			guarding += 1
	print("  из 20: спит %d, щит поднят %d" % [asleep, guarding])
	verdict("H1 стоящие мечники засыпают", asleep >= 18, "спит %d из 20" % asleep)

	# Разбудить обстрелом и снова заснуть, когда угроза прошла
	var target := men[0] as Warrior
	target.notify_incoming_fire(Vector3(0, 0, -450))
	await frames(2)
	var woke: bool = target.is_processing()
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 2600:
		await get_tree().process_frame
	verdict("H2 обстрел будит, тишина усыпляет обратно",
		woke and not target.is_processing(),
		"проснулся=%s, потом спит=%s" % [woke, not target.is_processing()])

	for m in men:
		(m as Node).queue_free()
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# I. ПОРЯДОК СОБЫТИЙ: ПЕРВЫЙ УДАР ПРОХОДИТ ПОЛНОСТЬЮ
# Щит не должен резать тот самый удар, которым он же и взводится. Идущий
# мечник, которого ещё не обстреливали, обязан поймать первое попадание в
# полную силу — и только следующее уже прикрыть.
# ═════════════════════════════════════════════════════════════════════════════
func _i_order() -> void:
	print("\n═════ I. ПЕРВЫЙ УДАР ═════")
	var w := _new_warrior(Vector3(0, 0, -480))
	var arch := _new_archer(Vector3(20, 0, -480))
	await frames(3)
	arch.set_process(false); arch.set_physics_process(false)
	w.set_physics_process(false)

	# Мечник ИДЁТ и ни о чём не подозревает: угрозы не было, щит опущен
	w.state = Unit.State.MOVING
	w._facing = Vector3(1, 0, 0)
	w._threat_until_ms = 0
	w._update_guard()
	var guard_before: bool = w.is_guarding()

	# Эталон «без щита вообще» — на отдельном бойце, чтобы не путать состояния
	var ref := _new_warrior(Vector3(0, 0, -490))
	ref._facing = Vector3(1, 0, 0)
	await frames(3)
	ref.set_physics_process(false)
	ref.set_auto_guard(false)
	ref.current_health = ref.max_health
	ref.take_damage(40.0, arch)
	var full: float = ref.max_health - ref.current_health

	# ПЕРВОЕ попадание — щита не было
	w.current_health = w.max_health
	w.take_damage(40.0, arch)
	var first: float = w.max_health - w.current_health

	# Попадание взвело угрозу — щит встаёт, ВТОРОЕ попадание уже режется
	w._update_guard()
	var guard_after: bool = w.is_guarding()
	w.current_health = w.max_health
	w.take_damage(40.0, arch)
	var second: float = w.max_health - w.current_health

	print("  урон: эталон %.2f → первый %.2f → второй %.2f" % [full, first, second])
	verdict("I1 до обстрела щит опущен", not guard_before)
	verdict("I2 первый удар проходит в полную силу", absf(first - full) < 0.01,
		"%.2f против эталона %.2f" % [first, full])
	verdict("I3 попадание взводит щит", guard_after)
	verdict("I4 второй удар уже режется", second < first * 0.4,
		"%.2f против %.2f" % [second, first])

	# I5. «СТЕНА ЩИТОВ» — ПАССИВКА ПРОТИВ ОБСТРЕЛА. Рубка мечом щит сама не
	# поднимает: в ближнем бою он управляется игроком с панели
	var melee := Spearman.new()
	melee.faction = Constants.FACTION_ENEMY
	main.world_add(melee)
	melee.global_position = Vector3(2, 0, -480)
	await frames(3)
	melee.set_process(false); melee.set_physics_process(false)
	w.state = Unit.State.MOVING
	w._threat_until_ms = 0
	w._update_guard()
	w.current_health = w.max_health
	w.take_damage(20.0, melee)
	verdict("I5 ближний бой щит сам НЕ поднимает", not w._threatened(),
		"угроза=%s" % w._threatened())
	melee.queue_free()

	w.queue_free(); ref.queue_free(); arch.queue_free()
	await frames(2)

# ═════════════════════════════════════════════════════════════════════════════
# J. ПРОБУЖДЕНИЕ СО ЩИТОМ: НЕ ОСТАЁТСЯ ЛИ МЕЧНИК МЕДЛЕННЫМ НАВСЕГДА
# Самое опасное место всей механики. Стоящий мечник со щитом ЗАСЫПАЕТ — его
# _process выключен, а именно _process пересчитывает _guard_active. Если приказ
# на движение не разбудит юнита, флаг щита останется взведённым, и боец будет
# ходить на 65% скорости до конца партии, ничем это не показывая.
# ═════════════════════════════════════════════════════════════════════════════
func _j_wake_speed() -> void:
	print("\n═════ J. ПРОБУЖДЕНИЕ СО ЩИТОМ ═════")
	var w := _new_warrior(Vector3(0, 0, -500))
	# Даём улечься и заснуть со щитом наизготовку
	var t0: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 2500:
		await get_tree().process_frame
	var slept: bool = not w.is_processing()
	var guarded: bool = w.is_guarding()
	verdict("J1 стоящий заснул со щитом", slept and guarded,
		"спит=%s щит=%s" % [slept, guarded])

	# Приказ идти. Проверяем СЛЕДУЮЩИЙ же кадр: если _process не проснулся,
	# _guard_active останется true и скорость не восстановится
	w.command_move(Vector3(45, 0, -500))
	await frames(2)
	verdict("J2 приказ разбудил _process", w.is_processing())
	verdict("J3 щит опустился на марше без угрозы", not w.is_guarding(),
		"guard=%s state=%d" % [w.is_guarding(), w.state])

	# И скорость реально полная: сравниваем пройденный путь с эталоном
	var ref := _new_warrior(Vector3(0, 0, -520))
	await frames(3)
	ref.set_auto_guard(false)
	ref.command_move(Vector3(45, 0, -520))
	var x0: float = w.global_position.x
	var r0: float = ref.global_position.x
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 2000:
		await get_tree().process_frame
	var dw: float = w.global_position.x - x0
	var dr: float = ref.global_position.x - r0
	print("  прошли за 2 с: разбуженный %.2f м, эталон без щита %.2f м" % [dw, dr])
	verdict("J4 скорость восстановилась полностью", dw > dr * 0.95,
		"%.2f против %.2f" % [dw, dr])

	# Обратный сценарий: обстрел кончился — скорость возвращается сама
	w.notify_incoming_fire(Vector3(0, 0, -500))
	await frames(2)
	var slow_now: bool = w.is_guarding()
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 2200:   # больше GUARD_HOLD_MS = 1600
		await get_tree().process_frame
	verdict("J5 после обстрела щит опускается сам",
		slow_now and not w.is_guarding(),
		"под обстрелом=%s, через 2.2 с=%s" % [slow_now, w.is_guarding()])

	w.queue_free(); ref.queue_free()
	await frames(2)
