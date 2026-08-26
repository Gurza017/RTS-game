extends Unit
class_name Spearman

const _SSParser := preload("res://scripts/SpriteSheetParser.gd")

# Directional sprite textures — загружаются один раз, переключаются по направлению
var _dir_sprite: Sprite3D = null
var _dir_textures: Dictionary = {}   # ключ: "idle"|"run"|"attack_down" и т.д.
var _dir_frames: Dictionary = {}     # ключ → число кадров в горизонтальном шите
var _cur_tex_key: String = ""        # последний применённый ключ (для dedupe)
## ── КЛЮЧИ ПОЗ ЛЕЖАТ ГОТОВЫМИ, А НЕ СКЛЕИВАЮТСЯ КАЖДЫЙ РАЗ ───────────────────
## Здесь было `"attack_" + (result[0] as String)`, а сектор возвращался НОВЫМ
## Array из двух элементов. То есть на КАЖДОЕ обновление позы приходились две
## аллокации кучи, а обновлений в контактном бою около восьмисот в кадр
## (замер счётчиками: 34 788 полных обновлений слота за 90 кадров).
## Строка в горячем пути — известная и уже однажды оплаченная в этом проекте
## ошибка (см. шапку FarUnitRenderer про сборку ключа бакета).
##
## Теперь сектор — это ИНДЕКС, а ключ берётся из готовой таблицы по индексу.
## Ни одной аллокации, а сравнение `tex_key == _cur_tex_key` для одинаковых
## литералов сводится к сравнению ссылок на общую строку.
const SECTOR_MIRROR := [false, false, false, true, true, true, false, false]
const ATTACK_KEYS := ["attack_right", "attack_downright", "attack_down",
	"attack_downright", "attack_right", "attack_upright", "attack_up",
	"attack_upright"]
const DEFENCE_KEYS := ["defence_right", "defence_downright", "defence_down",
	"defence_downright", "defence_right", "defence_upright", "defence_up",
	"defence_upright"]
## Род текущей позы, чтобы не сканировать строку begins_with() в горячем пути:
## 0 — обычная (idle/run), 1 — attack_*, 2 — defence_*
const KIND_PLAIN := 0
const KIND_ATTACK := 1
const KIND_DEFENCE := 2
var _cur_kind: int = KIND_PLAIN
var _used_color_folder: bool = false # спрайты взяты из цветной папки фракции

func _ready() -> void:
	_apply_config_stats("spearman")   # характеристики — из unit_stats_config.gd
	display_name   = "Копейщик"
	super._ready()
	_add_spear_to_billboard()

# Тычок копьём: короткий выпад спрайта в сторону цели и возврат
func _on_attack_fired(_target: Node3D, _damage: float) -> void:
	if _dir_sprite == null or not is_instance_valid(_dir_sprite):
		return
	# В общей отрисовке узел невидим: выпад никто не увидит, а Tween — это
	# объект и покадровая работа на КАЖДЫЙ удар КАЖДОГО бойца
	if _mm_only:
		return
	var lunge := _facing * 0.35
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_dir_sprite, "position:x", lunge.x, 0.07)
	tw.parallel().tween_property(_dir_sprite, "position:z", lunge.z, 0.07)
	tw.tween_property(_dir_sprite, "position:x", 0.0, 0.16)
	tw.parallel().tween_property(_dir_sprite, "position:z", 0.0, 0.16)

func _add_spear_to_billboard() -> void:
	var fname := GameManager.race_of(faction)

	# 1. Направленные спрайты лансера ЦВЕТА СВОЕЙ ФРАКЦИИ (высший приоритет)
	if _load_directional_sprites(fname):
		for child in get_children():
			if child is MeshInstance3D and child != selection_ring:
				child.visible = false
		_dir_sprite = Sprite3D.new()
		_dir_sprite.billboard  = BaseMaterial3D.BILLBOARD_FIXED_Y
		# Discard вместо alpha-блендинга: спрайты пишут глубину — в плотном
		# строю нет мерцания сортировки («фантомных дублей» при остановке)
		_dir_sprite.alpha_cut  = SpriteBase3D.ALPHA_CUT_DISCARD
		# Порог 0.5 срезал тонкие полупрозрачные пиксели ДРЕВКА КОПЬЯ — оно
		# пропадало местами на ходу и в атаке. 0.15 сохраняет копьё целиком,
		# при этом глубина по-прежнему пишется (нет мерцания в плотном строю).
		_dir_sprite.alpha_scissor_threshold = 0.15
		_dir_sprite.pixel_size = PIXEL_SIZE   # +35% (Unit.UNIT_SCALE)
		# Высоту ставит _apply_dir_tex: она своя у каждого листа
		_apply_dir_tex("idle")
		# Спрайты уже НУЖНОГО ЦВЕТА фракции — красить их не надо. Оттенок
		# остаётся только как запасной признак стороны, если цветной папки
		# не нашлось и подхватился общий (бесцветный) набор
		if _used_color_folder:
			_dir_sprite.modulate = Color.WHITE
		else:
			_dir_sprite.modulate = Color(1.0, 0.55, 0.55) if faction == Constants.FACTION_ENEMY else Color(0.75, 0.85, 1.0)
		add_child(_dir_sprite)
		_active_sprite = _dir_sprite
		return

	# 2. Спрайт-шит из soldier_pack (анимированный)
	var pack_path := "res://assets/factions/%s/units/soldier_pack" % fname
	var asp: AnimatedSprite3D = _SSParser.build_animated_sprite(pack_path)
	if asp:
		for child in get_children():
			if child is MeshInstance3D and child != selection_ring:
				child.visible = false
		add_child(asp)
		_active_sprite = asp
		return

	# 3. GLB
	const GLB := "res://assets/models/spearman.glb"
	if ResourceLoader.exists(GLB):
		var scene := load(GLB) as PackedScene
		if scene:
			for child in get_children():
				if child is MeshInstance3D and child != selection_ring:
					child.visible = false
			_glb_model = scene.instantiate()
			_glb_model.scale = Vector3.ONE * 0.85
			add_child(_glb_model)
			return

	# 4. Одиночный PNG
	const SPR := "res://assets/sprites/units/Lancer_Idle.png"
	if ResourceLoader.exists(SPR):
		var tex := load(SPR) as Texture2D
		if tex:
			set_sprite_texture(tex)
			return

	# 5. Процедурное копьё
	_add_spear_procedural()

# ── Загрузка направленных текстур ────────────────────────────────────────────

func _load_directional_sprites(faction_name: String) -> bool:
	# Папка цвета своей фракции; если её нет — старая общая spearman/
	var folder := GameManager.unit_sprite_folder(faction, "spearman")
	# Проба ПО ФАЙЛУ, а не по каталогу (см. SpriteSheetParser.folder_has)
	_used_color_folder = _SSParser.folder_has(folder, "Lancer_Idle.png")
	if not _used_color_folder:
		folder = "res://assets/factions/%s/units/spearman" % faction_name
	var files := {
		"idle":              "Lancer_Idle.png",
		"run":               "Lancer_Run.png",
		"attack_down":       "Lancer_Down_Attack.png",
		"attack_up":         "Lancer_Up_Attack.png",
		"attack_right":      "Lancer_Right_Attack.png",
		"attack_upright":    "Lancer_UpRight_Attack.png",
		"attack_downright":  "Lancer_DownRight_Attack.png",
		"defence_down":      "Lancer_Down_Defence.png",
		"defence_up":        "Lancer_Up_Defence.png",
		"defence_right":     "Lancer_Right_Defence.png",
		"defence_upright":   "Lancer_UpRight_Defence.png",
		"defence_downright": "Lancer_DownRight_Defence.png",
	}
	var count := 0
	for key in files:
		var path: String = folder + "/" + files[key]
		var tex := _SSParser._load_texture(path)
		if tex != null:
			_dir_textures[key] = tex
			# ВАЖНО: Lancer_*.png — горизонтальные спрайт-шиты (Idle = 12 кадров!).
			# Запоминаем число кадров: Sprite3D режет шит через hframes,
			# иначе юнит рисуется лентой из 12 копейщиков («линейка-фантом»)
			var fc: int = _BBUtil.frame_count(tex)
			_dir_frames[key] = fc
			_dir_bottom[key] = _bottom_margin(path, tex, fc)
			count += 1
	return count > 0 and _dir_textures.has("idle")

# ── ПРИВЯЗКА ПО ВЕРТИКАЛИ: ПОЧЕМУ КОПЬЁ «ОБРЕЗАЛОСЬ» ────────────────────────
# Листы Lancer_*.png нарисованы с РАЗНОЙ вертикальной привязкой внутри кадра
# 320x320. Замер альфы (нижний отступ до края кадра):
#     Lancer_Idle          — 122 px      Lancer_Right_Attack  — 122 px
#     Lancer_Up_Attack     — 131 px      Lancer_Down_Attack   —  18 px  (!)
#     Lancer_Down_Defence  —  43 px      Lancer_DownRight_Att —  46 px
# Высота самой фигурки везде одинаковая (150-151 px) — то есть в «нижних»
# позах она просто нарисована на ~100 px ниже в кадре.
# Раньше спрайт сажался жёстко на SPRITE_BASE_Y, подобранный под Idle, и при
# переключении на нижнюю атаку весь рисунок уезжал на 104 px × 0.0108 ≈ 1.1 м
# ПОД ЗЕМЛЮ — копьё скрывалось под плоскостью грунта. Отсюда и «не всегда и
# не у всех»: у Right/Up/UpRight отступ как у Idle, они выглядели нормально.
# Компенсируем: сдвигаем базу так, чтобы низ рисунка в ЛЮБОЙ позе лежал там же,
# где он лежит у Idle, — ноги всегда на земле, ничего не тонет.
const PIXEL_SIZE := 0.0108   # тот же, что у _dir_sprite

var _dir_bottom: Dictionary = {}          # ключ → нижний отступ альфы, px
static var _bottom_cache: Dictionary = {} # путь PNG → нижний отступ, px

# Нижний отступ непрозрачных пикселей в ПЕРВОМ кадре листа.
# Скан идёт снизу вверх и с прореживанием по X — это дёшево и делается
# ОДИН раз на путь (результат кэшируется статически на весь запуск).
#
# ПРОВЕРЕНО ЗАМЕРОМ (qa_fix): в «нижних» позах вниз уезжает ВСЯ ФИГУРА, а не
# одно копьё — альфа-бокс первого кадра у Idle 150 px высотой, у Down_Attack
# 151 px, то есть рисунок просто сдвинут на ~104 px. Поэтому выравнивание по
# нижней кромке альфы корректно и ставит ноги на землю. Сканировать только
# центральную полосу кадра (была такая попытка) НЕ НУЖНО: она сдвигала отступы
# на 2-9 px и ломала правильную привязку у Right/Up.
static func _bottom_margin(path: String, tex: ImageTexture, frames: int) -> int:
	if _bottom_cache.has(path):
		return _bottom_cache[path]
	var result := 0
	var img := tex.get_image()
	if img != null:
		if img.is_compressed():
			img.decompress()
		var h := img.get_height()
		var fw: int = img.get_width() / maxi(frames, 1)
		var y := h - 1
		while y >= 0:
			var opaque := false
			var x := 0
			while x < fw:
				if img.get_pixel(x, y).a > 0.02:
					opaque = true
					break
				x += 2
			if opaque:
				break
			result += 1
			y -= 1
	_bottom_cache[path] = result
	return result

# Применить текстуру направления с корректной нарезкой шита на кадры
## ── КАК КОПЕЙЩИК ВЫГЛЯДИТ ПАВШИМ ───────────────────────────────────────────
## У копейщика направленные листы, и _look_table у него пуст — базовая версия
## corpse_frame нашла бы там пусто и вернула ТЕКУЩУЮ позу. А текущая у него в
## бою всегда боевая: выпад копья (attack_*) или щит (defence_*). Поле выходило
## заваленным телами, застывшими в замахе.
##
## ЛИСТ ПОКОЯ ТОЖЕ НЕ ГОДИТСЯ, и это выяснилось на картинке: в idle копейщик
## стоит с копьём ВЕРТИКАЛЬНО ВВЕРХ, и лежащее тело с торчащей в небо пикой
## читалось как стоящий боец. Заказ владельца — брать лист ЩИТА (defence): там
## копьё опущено и прижато к телу, силуэт компактный и на «стоящего» не похож.
##
## Направление берём одно и то же (DEFENCE_KEYS[0], «вправо»): куда именно легло
## тело, решает поворот квада на земле, а не выбор листа. Так заказанные «четыре
## базовых направления со случайным поворотом» получаются без нового арта
func corpse_frame() -> Array:
	var key: String = DEFENCE_KEYS[0]
	var tex: ImageTexture = _dir_textures.get(key)
	if tex == null:
		# Щита в наборе нет (урезанный комплект спрайтов) — покой лучше, чем
		# застывший замах
		key = "idle"
		tex = _dir_textures.get(key)
	if tex == null:
		return super()
	return [tex, 0, int(_dir_frames.get(key, 1)), PIXEL_SIZE, SPRITE_BASE_Y]

func _apply_dir_tex(key: String) -> void:
	if _dir_sprite == null:
		return
	var tex: ImageTexture = _dir_textures.get(key)
	if tex == null:
		key = "idle"
		tex = _dir_textures.get("idle")
	if tex == null:
		return
	# ФАЗА АНИМАЦИИ СОХРАНЯЕТСЯ, если в новом листе столько же кадров. Ракурс
	# теперь пересчитывается и при обороте камеры (см. _screen_angle), а сброс
	# _frame_time в ноль на каждой смене сектора дёргал бы анимацию бега и удара
	# при каждом повороте вида
	var new_frames: int = _dir_frames.get(key, 1)
	if new_frames != _look_frames:
		# Своя фаза у каждого бойца — иначе шеренга дышит в один такт
		# (см. Unit._anim_offset). Удары начинаются с нуля: замах обязан быть
		# виден с первого кадра
		_anim_phase = 0.0 if key.begins_with("attack") 			else _anim_offset * float(maxi(new_frames, 1))
	_cur_tex_key = key
	# Род позы запоминается ЧИСЛОМ: begins_with() сканирует строку, а спрашивают
	# о нём из горячего пути (разворот спрайта и решение «можно ли спать»)
	if key.begins_with("attack"):
		_cur_kind = KIND_ATTACK
	elif key.begins_with("defence"):
		_cur_kind = KIND_DEFENCE
	else:
		_cur_kind = KIND_PLAIN
	# ── ВИД ЖИВЁТ ЧИСЛАМИ (см. Unit._look_bind) ──────────────────────────────
	# Лента, число кадров и темп листания — поля бойца. Узел Sprite3D в общей
	# отрисовке невидим, и запись в его texture/hframes/frame означала бы
	# пересборку кадра и AABB ради картинки, которую никто не увидит
	_look_tex    = tex
	_look_frames = new_frames
	_look_frame  = 0
	_look_px     = PIXEL_SIZE
	_look_loop   = true
	_look_fps    = 10.0 if (key == "run" or key.begins_with("attack")) else 6.0
	# Компенсация привязки листа: низ рисунка встаёт туда же, где у Idle
	var ref: int  = int(_dir_bottom.get("idle", 0))
	var mine: int = int(_dir_bottom.get(key, ref))
	_sprite_base_y = SPRITE_BASE_Y + float(ref - mine) * PIXEL_SIZE
	if _mm_only:
		return
	_dir_sprite.texture = tex
	_dir_sprite.vframes = 1
	_dir_sprite.hframes = new_frames
	_dir_sprite.frame   = 0
	_dir_sprite.position.y = _sprite_base_y

# ── Переключение спрайта по направлению и состоянию FSM ──────────────────────

# ВЫБОР РАКУРСА встроен в общий такт обновления внешности (Unit._process зовёт
# _update_sprite_anim раз в ANIM_EVERY кадров со сдвигом фазы и только у тех,
# кого видно). Своего _process у копейщика больше нет: он дублировал и проверку
# видимости, и такт, и листание кадров — а листание теперь ведёт база числом
# (Unit._advance_look_frame), без единого обращения к Sprite3D
func _update_sprite_anim() -> void:
	if _dir_sprite == null or not is_instance_valid(_dir_sprite):
		return
	_update_dir_sprite()

# Зеркалом направленных поз (attack_*/defence_*) управляет _update_dir_sprite:
# он сам считает 8 направлений из одного набора шитов. Базовый разворот по
# камере применяем только к ненаправленным позам (idle/run) — иначе два
# механизма перебивают flip_h друг у друга каждый кадр и отряд мерцает
func _update_sprite_flip() -> void:
	# Условие по ТЕКУЩЕМУ ЛИСТУ, а не по состоянию FSM: в State.ATTACKING боец
	# может бежать к далёкой цели с обычным листом "run", и его зеркало обязан
	# считать базовый механизм — иначе бегущий на врага копейщик едет спиной
	if _cur_kind != KIND_PLAIN:
		return
	super._update_sprite_flip()

# Кадры направленного Sprite3D листает НАШ _process (в отличие от
# AnimatedSprite3D, который тикает сам). Поэтому усыплять _process можно
# только если в шите покоя один кадр — иначе стоящий копейщик застывал
# статуей вместо анимации дыхания/перьев на шлеме.
func _process_can_sleep() -> bool:
	if _dir_sprite == null:
		return true
	# ЖДЁМ СВОЕЙ ОЧЕРЕДИ ОПУСТИТЬ КОПЬЁ — спать нельзя. Уснувший боец не
	# перерисовал бы позу, и его пика так и осталась бы поднятой навсегда
	if _spear_ready_ms > 0 and Time.get_ticks_msec() < _spear_ready_ms:
		return false
	# СРОК ВЫШЕЛ, НО ПОЗА ЕЩЁ НЕ ДОГНАЛА СОСТОЯНИЕ — тоже спать нельзя.
	# Гонка: _spear_down переключается ВНУТРИ _spear_leveled(), а зовёт её
	# только _update_dir_sprite(). Стоило бойцу уснуть ровно в тот кадр, когда
	# его личная задержка истекла, — и переключать состояние было уже некому:
	# копьё так и оставалось поднятым. На стенде это читалось как «фалангу
	# выставили 3 из 20», причём число плавало от прогона к прогону
	# (qa_formation, D1: 3, 6, 8 при ожидаемых 10)
	if (_stance_holds_ground() or _charging()) \
			and _spear_down != (_live_rank < PHALANX_FRONT_RANKS):
		return false
	# НАПРАВЛЕННУЮ ПОЗУ НЕ УСЫПЛЯЕМ. Ракурс листов defence_*/attack_* зависит от
	# положения камеры (см. _screen_angle), поэтому стоящий боец в такой позе
	# обязан пересчитывать сектор — иначе при облёте камеры копья передней
	# шеренги остались бы направленными «в старую сторону экрана»
	if _cur_kind != KIND_PLAIN:
		return false
	# Спать можно, если в ТЕКУЩЕМ шите один кадр — листать нечего
	return int(_dir_frames.get(_cur_tex_key, 1)) <= 1

# ── ПОЛОЖЕНИЕ КОПЬЯ ──────────────────────────────────────────────────────────
# ГОРИЗОНТАЛЬНОЕ КОПЬЁ = СТОЙКА «ЗАЩИТА» + ПЕРВЫЕ ДВЕ ШЕРЕНГИ.
#
# В обычном режиме атаки (в том числе сразу после найма и после Ctrl+1..9)
# копьё поднято у ВСЕХ — позы Idle/Run. По кнопке [ЗАЩИТА] отряд строится
# фалангой: ряды 0-1 выставляют копья вперёд (Lancer_*_Defence), ряды 2+
# держат древки вверх и подтягиваются к передовой.
#
# Ряд берётся не из приказа на построение, а из живого замера окружения
# (Unit._update_live_rank): сколько своих стоит прямо передо мной, такой
# у меня и ряд. Поэтому щетина копий сама «перетекает» на новых передовых,
# когда первую шеренгу выбивают или строй рассыпается в свалку.
# ── АСИНХРОННОЕ ОПУСКАНИЕ ПИК ────────────────────────────────────────────────
# ФАЛАНГА — НЕ ШЛАГБАУМ. Раньше признак «копьё горизонтально» вычислялся
# мгновенно и одинаково у всех, поэтому весь отряд ронял пики В ОДИН КАДР:
# двадцать человек синхронно, как одно механическое устройство.
#
# Теперь у каждого бойца своя микро-задержка. Она НЕ случайная в момент
# приказа, а выведена из его собственного instance_id: при одном и том же
# составе отряд опускает копья одинаково, и поведение воспроизводимо на стенде.
# Разброс — весь заданный диапазон, от мгновенного до DROP_DELAY_MAX, отсюда
# и нужный на слух эффект «раз-раз-раз-раз, и фаланга готова».
const DROP_DELAY_MAX_MS := 1900

## Момент (ticks_msec), с которого ЭТОТ боец готов опустить копьё.
## 0 — приказа на фалангу сейчас нет
var _spear_ready_ms: int = 0
## Признак предыдущего кадра: отслеживаем именно ПЕРЕХОД в стойку защиты
var _was_holding: bool = false
## Копьё СЕЙЧАС опущено. Отдельное состояние, а не выражение от ряда: между
## порогами опускания и подъёма лежит мёртвая зона, в которой решение держится
var _spear_down: bool = false

## Своя задержка бойца, 0..DROP_DELAY_MAX_MS. Младшие биты instance_id
## распределены равномерно, поэтому и задержки ложатся по всему диапазону
func _own_drop_delay_ms() -> int:
	# absi обязателен: умножение id на большую константу переполняет int64
	# и уходит в минус, а остаток от отрицательного в GDScript тоже
	# отрицательный — задержка вышла бы «в прошлом» у половины отряда
	return absi(get_instance_id() * 2654435761) % DROP_DELAY_MAX_MS

## ИДЁМ В АТАКУ ПО ПРИКАЗУ. Отличается от «дерусь, потому что подвернулся враг»:
## копья выставляются только под ПРЯМОЙ приказ игрока или ИИ по конкретной цели.
## Именно этим сохраняется старое правило «в стойке АТАКА копья подняты»: боец,
## сцепившийся с врагом сам по авто-агро, древко не опускает
func _charging() -> bool:
	return _charge_order and attack_target != null

func _spear_leveled() -> bool:
	# Копьё горизонтально в двух случаях и ТОЛЬКО у первых двух шеренг:
	#   • фаланга — стойка ЗАЩИТА (держим рубеж);
	#   • АТАКА ПО ПРИКАЗУ — отряд идёт на указанного врага щетиной пик вперёд.
	# Ряд живой — см. Unit._update_live_rank(): погиб передний, и стоящий сзади
	# в тот же миг становится первым рядом
	# НА БЕГУ ФАЛАНГИ НЕТ. Двойной ПКМ распускает строй: копья идут вертикально
	# вверх и отряд просто бежит. Проверка стоит ПЕРВОЙ и перебивает и стойку
	# ЗАЩИТА, и приказ атаки — бежать щетиной пик нельзя ни при каких условиях.
	# Флаг снимается сам по прибытии (Unit._arrive_at_target), и копья
	# опускаются обратно тем же путём, что и всегда
	var holds: bool = (not sprinting) and (_stance_holds_ground() or _charging())
	if holds != _was_holding:
		_was_holding = holds
		# Вошли в стойку — заводим ЛИЧНЫЙ отсчёт до опускания копья
		_spear_ready_ms = (Time.get_ticks_msec() + _own_drop_delay_ms()) if holds else 0
	if not holds:
		_spear_down = false
		return false
	# ── ГИСТЕРЕЗИС ПО РЯДУ ───────────────────────────────────────────────────
	# Ряд считается по живому окружению и на границе ПОСТОЯННО ДРОЖИТ: сосед
	# качнулся на полшага — и боец то второй ряд, то третий. Пока решение
	# принималось голым сравнением, это давало две беды разом:
	#   • визуально — копьё дёргалось вверх-вниз по нескольку раз в секунду;
	#   • по производительности — каждая смена позы переписывает текстуру
	#     Sprite3D, а это не запись поля, а пересборка кадра и AABB. Замер
	#     (qa_bugpack2, 9b): стойка ЗАЩИТА обходилась в 8-15 мс на 300 бойцов
	#     против 1.5 мс в стойке АТАКА — впятеро дороже на ровном месте.
	# Теперь опустить копьё можно с ряда 0-1, а поднять обратно — только с ряда
	# 3 и глубже. Между ними мёртвая зона, в которой решение НЕ МЕНЯЕТСЯ
	if _spear_down:
		if _live_rank > PHALANX_FRONT_RANKS:
			_spear_down = false
	elif _live_rank < PHALANX_FRONT_RANKS:
		# ЗАДЕРЖКА ТОЛЬКО НА ВХОДЕ В СТОЙКУ. Боец, который стал передовым уже
		# ПОСЛЕ построения (перед ним выбили соседа), выставляет копьё немедленно:
		# там пауза означала бы дыру в щетине пик ровно в момент удара
		if Time.get_ticks_msec() >= _spear_ready_ms:
			_spear_down = true
	return _spear_down

## Зеркало НАПРАВЛЕННОЙ позы. Пишется в то же поле _flip_h_state, что и базовый
## разворот по камере: в общей отрисовке именно оно уезжает в MultiMesh каналом
## цвета. Раньше направленные позы писали flip_h ПРЯМО В УЗЕЛ, мимо этого поля,
## — и в MultiMesh щетина копий рисовалась со старым (базовым) зеркалом
func _set_dir_flip(value: bool) -> void:
	_flip_h_state = value
	_apply_flip_to_node()

## Поза СТОЯЩЕГО копейщика: передние ряды держат копьё выставленным, задние —
## поднятым. Вынесена отдельно, потому что нужна теперь в трёх местах: в покое
## и в обоих ходовых случаях, когда боец «идёт», но фактически стоит
func _standing_key() -> String:
	if _spear_leveled():
		var ssec := _facing_to_dir_key(_facing.normalized())
		_set_dir_flip(SECTOR_MIRROR[ssec])
		return DEFENCE_KEYS[ssec]
	return "idle"

func _update_dir_sprite() -> void:
	var tex_key: String
	# ── ПОЗА БЕГА ТРЕБУЕТ ФАКТИЧЕСКОГО СМЕЩЕНИЯ ────────────────────────────
	# Здесь поза бралась прямо по `state`, и оба ходовых случая врали одинаково:
	# боец второй шеренги стоит в State.ATTACKING (цель за спинами первого
	# ряда), шагнуть не может — а лента крутит бег. То же и с State.MOVING у
	# запертого в тесноте. Спрашиваем, СДВИНУЛСЯ ли он на самом деле
	# (см. Unit.moved_recently); не сдвинулся — стоит, как и положено
	var afoot: bool = moved_recently()
	match state:
		State.MOVING:
			if not afoot:
				tex_key = _standing_key()
			elif _spear_leveled():
				# Передние шеренги идут с копьями наперевес, в сторону марша
				var mdir := velocity if velocity.length() > 0.05 else _facing
				var msec := _facing_to_dir_key(mdir.normalized())
				tex_key = DEFENCE_KEYS[msec]
				_set_dir_flip(SECTOR_MIRROR[msec])
			else:
				tex_key = "run"       # задние ряды — копьё вверх
		State.ATTACKING:
			# Вектор НА СВОЕГО противника: у каждого бойца он свой, поэтому
			# шеренга бьёт «веером» по реальным целям, а не вся в одну сторону
			var dir := _own_enemy_dir()
			var sec := _facing_to_dir_key(dir)
			if not target_in_range():
				# БЕЖИМ К ЦЕЛИ, А НЕ МАШЕМ КОПЬЁМ В ВОЗДУХ. Поза удара включается
				# строго после входа в зону поражения; по дороге это обычный бег
				# (у передних шеренг — марш с копьём наперевес в сторону цели).
				# НО ТОЛЬКО ЕСЛИ БОЕЦ И ПРАВДА ИДЁТ: упёршийся в своих СТОИТ —
				# это и есть «бег на месте» из жалобы
				if not afoot:
					tex_key = _standing_key()
				elif _spear_leveled():
					tex_key = DEFENCE_KEYS[sec]
					_set_dir_flip(SECTOR_MIRROR[sec])
				else:
					tex_key = "run"
			else:
				tex_key = ATTACK_KEYS[sec]
				_set_dir_flip(SECTOR_MIRROR[sec])
		_:
			# На месте передние ряды ДЕРЖАТ копьё выставленным (defence),
			# задние стоят с поднятым (idle)
			if _spear_leveled():
				var ssec := _facing_to_dir_key(_facing.normalized())
				tex_key = DEFENCE_KEYS[ssec]
				_set_dir_flip(SECTOR_MIRROR[ssec])
			else:
				tex_key = "idle"
			# flip_h у idle НЕ трогаем: этим занимается _update_sprite_flip.
			# Раньше тут стояло flip_h = false, и два механизма перебивали
			# друг друга каждый кадр — отряд мерцал «право-лево-право».

	if tex_key == _cur_tex_key:
		return  # dedupe — не переписываем ресурс без нужды
	_apply_dir_tex(tex_key)

# Направление на ЛИЧНОГО ближайшего противника этого бойца
func _own_enemy_dir() -> Vector3:
	var dir := Vector3.ZERO
	if attack_target != null and is_instance_valid(attack_target):
		# Дешёвые точки: эта функция зовётся из выбора позы, то есть сотни раз
		# в кадр (см. Unit.world_pos_cheap)
		# Дешёвые точки: эта функция зовётся из выбора позы, сотни раз в кадр
		# (тот же разбор, что в Unit.target_in_range)
		var tu2 := attack_target as Unit
		var tp2: Vector3 = tu2.position if (tu2 != null and tu2._local_xform) 			else attack_target.global_position
		dir = tp2 - (position if _local_xform else global_position)
		dir.y = 0.0
	if dir.length_squared() < 1e-6:
		# Цель уже мертва/не назначена — берём ближайшего врага в радиусе удара
		var near := _find_nearest_enemy_in_range(attack_range * 1.5)
		if near != null:
			dir = near.global_position - (position if _local_xform else global_position)
			dir.y = 0.0
	if dir.length_squared() < 1e-6:
		dir = velocity if velocity.length() > 0.05 else _facing
	if dir.length_squared() < 1e-6:
		return Vector3.FORWARD
	return dir.normalized()

# Преобразует 3D-вектор направления в ключ спрайта и флаг горизонтального зеркала
# Возвращает [direction_key: String, flip_h: bool]
#
# ГИСТЕРЕЗИС: на границе секторов угол дрожит, и при вращении камеры спрайт
# мерцал, перескакивая между двумя ракурсами. Держим текущий сектор, пока
# угол не уйдёт от его центра дальше 22.5° + HYSTERESIS_DEG.
const HYSTERESIS_DEG := 15.0
var _cur_sector: int = -1

## РАКУРС СЧИТАЕТСЯ ОТНОСИТЕЛЬНО КАМЕРЫ, А НЕ В МИРОВЫХ ОСЯХ.
##
## Спрайт — билборд: квад всегда развёрнут к зрителю, а КАКАЯ ИМЕННО поза на нём
## нарисована, выбирает этот метод. Раньше сектор брался из мирового угла
## atan2(z, x): боец, идущий на север, вечно рисовался листом "up" (спина).
## Игрок облетал камеру на другую сторону, видел ту же спину — и читал это как
## «солдаты и копья поворачиваются вслед за камерой».
##
## Теперь направление проецируется на оси КАМЕРЫ: вправо по экрану — basis.x,
## «от зрителя» — горизонтальная проекция взгляда камеры. При обороте камеры за
## спину строю игрок видит именно спины, а копья по-прежнему смотрят туда, куда
## боец реально повёрнут в мире.
##
## Совместимость: при стартовой ориентации камеры (взгляд вдоль −Z) формула
## сходится к прежней, поэтому вид «по умолчанию» не изменился.
func _screen_angle(facing: Vector3) -> float:
	# Оси камеры — из общего кэша GameManager (снимаются раз в кадр на всех).
	# Прежний get_viewport().get_camera_3d() здесь звался КАЖДЫМ копейщиком
	# КАЖДЫЙ раз при пересчёте ракурса
	if not GameManager.camera_axes_valid():
		return rad_to_deg(atan2(facing.z, facing.x))
	var right := GameManager.camera_right()
	var fwd   := GameManager.camera_forward()
	# sx > 0 — боец повёрнут вправо по экрану; sy > 0 — от зрителя (видим спину)
	var sx := facing.dot(right)
	var sy := facing.dot(fwd)
	# Знак sy инвертирован: в прежней мировой формуле «к зрителю» давало +z
	return rad_to_deg(atan2(-sy, sx))

## Возвращает НОМЕР СЕКТОРА (0..7), а не пару в новом массиве: см. таблицы выше
func _facing_to_dir_key(facing: Vector3) -> int:
	var ang := _screen_angle(facing)
	if ang < 0.0: ang += 360.0
	var sector := int(round(ang / 45.0)) % 8
	if _cur_sector >= 0 and sector != _cur_sector:
		# Насколько угол отошёл от ЦЕНТРА удерживаемого сектора
		var delta := absf(_angle_diff(ang, float(_cur_sector) * 45.0))
		if delta < 22.5 + HYSTERESIS_DEG:
			sector = _cur_sector      # ещё в зоне удержания — ракурс не меняем
	_cur_sector = sector
	return sector

## Прежняя форма — возвращала [имя, зеркало] НОВЫМ массивом на каждый вызов.
## Оставлена для тех, кому нужна пара; горячий путь пользуется индексом
static func _sector_to_key(sector: int) -> Array:
	return [SECTOR_NAMES[sector % 8], SECTOR_MIRROR[sector % 8]]

const SECTOR_NAMES := ["right", "downright", "down", "downright",
	"right", "upright", "up", "upright"]

# Разница углов в диапазоне [-180, 180]
static func _angle_diff(a: float, b: float) -> float:
	var d := fmod(a - b + 180.0, 360.0)
	if d < 0.0:
		d += 360.0
	return d - 180.0

# 8 секторов по 45°; atan2(z,x): 0°=right, 90°=down, 180°=left, 270°=up.
# Таблицы SECTOR_NAMES/SECTOR_MIRROR/ATTACK_KEYS/DEFENCE_KEYS — вверху файла

# ── Процедурное копьё (fallback) ──────────────────────────────────────────────

func _add_spear_procedural() -> void:
	var shaft := MeshInstance3D.new()
	var cyl   := CylinderMesh.new()
	cyl.top_radius    = 0.022; cyl.bottom_radius = 0.030; cyl.height = 2.2
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.44, 0.30, 0.14); mat.roughness = 0.9
	cyl.material = mat; shaft.mesh = cyl
	shaft.position      = Vector3(0.55, 1.30, 0.0)
	shaft.rotation_degrees = Vector3(8.0, 0.0, 0.0)
	add_child(shaft)

	var tip  := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius    = 0.0; cone.bottom_radius = 0.050; cone.height = 0.22
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(0.72, 0.74, 0.78); tmat.metallic = 0.75; tmat.roughness = 0.18
	cone.material = tmat; tip.mesh = cone
	tip.position = Vector3(0.55, 2.50, -0.05)
	add_child(tip)

## ── СТЕНКА КОПИЙ ПРОТИВ КОННИЦЫ ────────────────────────────────────────────
## Копейщик — единственный род войск, который держит лобовой навал: кабан
## налетает на выставленные копья и получает контрудар вместо того, чтобы смять
## строй (см. Unit._charge_impact). Свойство РОДА ВОЙСК, а не стойки: копья
## опущены навстречу коннице и в «атаке» — иначе фаланга была бы беззащитна
## ровно в тот момент, когда идёт вперёд.
## С фланга и с тыла не работает вовсе, и это главное: копья смотрят в одну
## сторону, обойти строй конница по-прежнему обязана уметь
func repels_charge() -> bool:
	return true
