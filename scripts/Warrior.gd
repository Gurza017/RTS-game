extends Unit
class_name Warrior

const _SSParser := preload("res://scripts/SpriteSheetParser.gd")

# Ротация атак: 3 обычных удара (attack_1), затем 1 мощный (attack_2)
var _attack_2_damage: float = 24.0
var _combo_step: int = 0

func _ready() -> void:
	_apply_config_stats("warrior")   # характеристики — из unit_stats_config.gd
	_attack_2_damage = _UStats.stat("warrior", "attack_2", attack_damage * 2.4)
	display_name    = "Мечник"
	super._ready()
	_setup_warrior_visual()

# Мечник рубит сталью: замах — свист меча, попадание — лязг по броне
func _sfx_swing() -> String:
	return "sword_attack"

# Каждый 4-й удар — мощный: другой урон и другая анимация
func _strike_damage() -> float:
	_combo_step += 1
	if _combo_step >= 4:
		_combo_step = 0
		_play_attack_anim("attack2", 600)
		return _attack_2_damage
	_play_attack_anim("attack1", 450)
	return attack_damage

# ─────────────────────────────────────────────────────────────────────────────
# ЗАЩИТА ЩИТОМ (AUTO-GUARD)
#
# ПОЧЕМУ ЭТО НЕ НОВОЕ ЗНАЧЕНИЕ В enum State, А НАДСТРОЙКА НАД ним.
# Стейт-машина Unit (IDLE/MOVING/ATTACKING/…) отвечает на вопрос «какой приказ
# юнит выполняет». Щит на этот вопрос не отвечает: мечник закрывается И стоя,
# И на марше, И между замахами в рубке — приказ при этом не меняется. Отдельное
# State.DEFENDING пришлось бы разбирать в каждом match по стейту (движение,
# поиск цели, строй, ИИ, HUD), и любая пропущенная ветка означала бы застрявшего
# бойца. Поэтому щит — независимый признак `_guard_active` поверх обычного
# стейта: он меняет анимацию, скорость и входящий урон, но не трогает приказ.
#
# Файл листа — Warrior_Guard.png (лежит в каждом цветном наборе). Направлений у
# него нет, в отличие от копейщика с его Lancer_*_Defence.png: разворот
# влево/вправо делает горизонтальный флип билборда в Unit._update_sprite_flip.
# ─────────────────────────────────────────────────────────────────────────────
const GUARD_ANIM  := "guard"
const GUARD_SHEET := "Warrior_Guard.png"

## Сколько щит остаётся поднятым после последней угрозы (выстрел, попадание)
const GUARD_HOLD_MS := 1600
## Доля урона, которую съедает щит: ближний бой и стрелы режутся по-разному
const GUARD_CUT_MELEE  := 0.50
const GUARD_CUT_RANGED := 0.70
## Косинус границы фронтального сектора. 0.0 — ровно передняя полусфера:
## всё, что прилетело сзади, щит не видит (backstab бьёт в полную силу)
const GUARD_FRONT_COS := 0.0
## Скорость под щитом: −35% (просили 30–40%). Мечник не останавливается,
## а идёт под обстрелом медленнее, прикрываясь на ходу
const GUARD_SPEED_FACTOR := 0.65

## Переключатель с панели юнита. Выключен — мечник игнорирует стрелы,
## щит сам не поднимает и ходит на полной скорости
var auto_guard: bool = true
## Щит поднят прямо сейчас (пересчитывается каждый кадр в _process)
var _guard_active: bool = false
## До какого момента (ticks_msec) действует «в меня стреляют / меня бьют»
var _threat_until_ms: int = 0

## Угроза свежая — есть повод держать щит
func _threatened() -> bool:
	return Time.get_ticks_msec() < _threat_until_ms

func _mark_threat() -> void:
	_threat_until_ms = Time.get_ticks_msec() + GUARD_HOLD_MS

## Щит поднят? Читает HUD для подсветки и стенды QA
func is_guarding() -> bool:
	return _guard_active

func set_auto_guard(on: bool) -> void:
	if auto_guard == on:
		return
	auto_guard = on
	if not on:
		_guard_active = false
		_threat_until_ms = 0
	_wake_process()

# Лучник зовёт это В МОМЕНТ ВЫСТРЕЛА (см. Archer._on_attack_fired), поэтому щит
# успевает встать до прилёта стрелы
func notify_incoming_fire(from: Vector3) -> void:
	if not auto_guard or state == State.DEAD:
		return
	_mark_threat()
	# Стоящий разворачивается ЛИЦОМ к стрелку: иначе щит окажется не с той
	# стороны и фронтальная проверка честно откажет в защите. Идущего не
	# доворачиваем — это сбило бы приказ на движение
	if state == State.IDLE:
		var d := from - global_position
		d.y = 0.0
		if d.length_squared() > 1e-4:
			_facing = d.normalized()
			_flip_dirty = true
	_wake_process()

# Поймал стрелу — держим щит поднятым ещё пару секунд.
#
# ТОЛЬКО ОБСТРЕЛ. «Стена щитов» — пассивка ПРОТИВ СТРЕЛЬБЫ: в ближнем бою щит
# остаётся ручным (переключатель игрока), иначе мечник закрывался бы сам в любой
# рубке и −50% превращались бы в постоянную прибавку к броне.
#
# Отметка ставится ПОСЛЕ super: множитель урона считается по тому щиту, который
# уже стоял, а не по поднятому этим же попаданием
func take_damage(amount: float, attacker: Node3D = null) -> void:
	super.take_damage(amount, attacker)
	if state == State.DEAD or not auto_guard:
		return
	if attacker is Archer:
		_mark_threat()

## Долевое снижение входящего урона щитом
func _incoming_damage_factor(attacker: Node3D) -> float:
	if not _guard_active:
		return 1.0
	# УДАР В СПИНУ ЩИТ ИГНОРИРУЕТ полностью
	if attacker != null and not _is_front_attack(attacker):
		return 1.0
	# Стрелы щит держит лучше, чем сталь в упор
	var cut: float = GUARD_CUT_RANGED if attacker is Archer else GUARD_CUT_MELEE
	return 1.0 - cut

## Атакующий во фронтальном секторе?
func _is_front_attack(attacker: Node3D) -> bool:
	if _facing.length_squared() < 1e-6:
		return true          # направление неизвестно — считаем удар лобовым
	var to_atk := attacker.global_position - global_position
	to_atk.y = 0.0
	if to_atk.length_squared() < 1e-6:
		return true          # бьют вплотную сверху — сторону не определить
	return _facing.normalized().dot(to_atk.normalized()) > GUARD_FRONT_COS

func tick_visual(delta: float, frame: int = -1, anim_every: int = ANIM_EVERY,
		view_x: float = 0.0, view_z: float = 0.0, view_r2: float = INF,
		lerp_k: float = 1.0, mm_all: bool = true, prof: bool = false,
		fog_on: bool = true) -> void:
	_update_guard()
	super.tick_visual(delta, frame, anim_every, view_x, view_z, view_r2,
		lerp_k, mm_all, prof, fog_on)

## Пересчёт признака «щит поднят». Поводов закрыться ДВА:
##   1) в юнита летит стрела или его только что ударили (_threatened);
##   2) отряду ВКЛЮЧЕН режим обороны игроком (стойка «Защита»).
## Во время самого замаха (_anim_lock_until_ms) щит опущен: одновременно бить
## и закрываться нельзя, да и анимация удара всё равно перекрыла бы guard.
##
## ── ПОКОЙ ЩИТА БОЛЬШЕ НЕ ПОДНИМАЕТ ─────────────────────────────────────────
## Здесь стояло `or state == State.IDLE`, и мечник стоял под щитом ВСЕГДА:
## любой боец без дела — это IDLE, то есть вся армия на марше между приказами
## и весь гарнизон жили в оборонительной позе. Заказ владельца прямой: в покое
## щит опущен, поднимается на включённый режим или на первый же прилёт.
## Реакция на угрозу при этом не изменилась ни на кадр — она в _threatened()
func _update_guard() -> void:
	var want := false
	if auto_guard and state != State.DEAD and Time.get_ticks_msec() >= _anim_lock_until_ms:
		want = _threatened() or _stance_holds_ground()
	if want != _guard_active:
		# Щит поднялся или опустился — поза обязана смениться В ЭТОМ ЖЕ КАДРЕ.
		# Обычный пересчёт идёт раз в ANIM_EVERY кадров, и стрела вполне
		# успевает долететь за эту паузу: со стороны щит «не срабатывает»
		mark_pose_dirty()
	_guard_active = want

# Анимация щита важнее walk/idle, но НЕ важнее анимации удара: пока идёт замах,
# базовая проверка _anim_lock_until_ms не пускает сюда никого
func _update_sprite_anim() -> void:
	if Time.get_ticks_msec() < _anim_lock_until_ms:
		return
	if _guard_active and _has_anim(GUARD_ANIM):
		if _anim_name != GUARD_ANIM:
			_set_anim(GUARD_ANIM)
		return
	super._update_sprite_anim()

# МАРШ ПОД ЩИТОМ: мечник не встаёт под обстрелом, а идёт медленнее.
#
# ШТРАФЫ НЕ ПЕРЕМНОЖАЮТСЯ. Штраф стойки «Защита» (STANCES.move_speed_mult, те же
# −35%) и штраф поднятого щита — это ОДНО И ТО ЖЕ замедление, названное дважды:
# боец идёт шагом, прикрываясь. Перемножение давало 0.65 × 0.65 = 0.42, то есть
# мечник в обороне под обстрелом полз вдвое медленнее заказанного. Берём
# наибольший штраф из двух, а не их произведение.
func _effective_speed() -> float:
	var s: float = super._effective_speed()
	if _guard_active:
		var stance_mult: float = _UStats.stance_stat(stance, "move_speed_mult", 1.0)
		if stance_mult > GUARD_SPEED_FACTOR:
			s *= GUARD_SPEED_FACTOR / maxf(stance_mult, 0.01)
	return s

# Сон _process. Базовая версия отказывается спать при любой анимации, кроме
# "idle", — со щитом наизготовку стоящая армия мечников не заснула бы никогда
# и съела бы кадр. Спать со щитом можно: AnimatedSprite3D крутит цикл сам,
# без нашего _process. Под угрозой не спим — щит должен опуститься вовремя
func _process_can_sleep() -> bool:
	if Time.get_ticks_msec() < _anim_lock_until_ms:
		return false
	if _threatened():
		return false
	if _anim_name != &"" and _anim_name != &"idle" and _anim_name != GUARD_ANIM:
		return false
	return true

func _setup_warrior_visual() -> void:
	var fname := GameManager.race_of(faction)
	# Набор ЦВЕТА СВОЕЙ ФРАКЦИИ, запасной — общий soldier_pack
	var pack_path := GameManager.unit_sprite_folder(faction, "warrior")
	# Проба ПО ФАЙЛУ, а не по каталогу (см. SpriteSheetParser.folder_has)
	var colored := _SSParser.folder_has(pack_path, "Warrior_Idle.png")
	if not colored:
		pack_path = "res://assets/factions/%s/units/soldier_pack" % fname
	var tint := Color.WHITE
	if not colored:
		tint = Color(1.0, 0.55, 0.55) if faction == Constants.FACTION_ENEMY else Color(0.82, 0.92, 1.0)

	# 1. Явная карта листов: idle/walk + раздельные анимации ударов + щит.
	# GUARD_SHEET зациклен намеренно (в no_loop его нет): щит держат, пока есть
	# угроза, а не проигрывают один раз
	var mapped: AnimatedSprite3D = _SSParser.build_sprite_from_map(pack_path, {
		"idle":    "Warrior_Idle.png",
		"walk":    "Warrior_Run.png",
		"attack1": "Warrior_Attack1.png",
		"attack2": "Warrior_Attack2.png",
		GUARD_ANIM: GUARD_SHEET,
	}, ["attack1", "attack2"])
	if mapped:
		for child in get_children():
			if child is MeshInstance3D and child != selection_ring:
				child.visible = false
		mapped.modulate = tint
		add_child(mapped)
		_active_sprite = mapped
		return

	# 2. Автосканирование папки (общая анимация attack)
	var asp: AnimatedSprite3D = _SSParser.build_animated_sprite(pack_path)
	if asp:
		for child in get_children():
			if child is MeshInstance3D and child != selection_ring:
				child.visible = false
		asp.modulate = tint
		add_child(asp)
		_active_sprite = asp
		return

	# 3. Один PNG из soldier_pack
	var idle_path := "res://assets/factions/%s/units/soldier_pack/Warrior_Idle.png" % fname
	if ResourceLoader.exists(idle_path):
		var tex := load(idle_path) as Texture2D
		if tex:
			set_sprite_texture(tex)
			return

	# 4. Цветовой оттенок на базовом billboard-спрайте.
	# Квад заводится ТОЛЬКО здесь: у мечника со спрайт-листом его нет
	_ensure_body_quad()
	if _sprite_node:
		var mat := _sprite_node.get_active_material(0) as StandardMaterial3D
		if mat:
			mat.albedo_color = Color(0.75, 0.30, 0.90) if faction == Constants.FACTION_PLAYER else Color(0.90, 0.30, 0.30)
