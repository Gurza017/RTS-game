extends Unit

## ═══════════════════════════════════════════════════════════════════════════
## ГОБЛИН-КОПЕЙЩИК
## ═══════════════════════════════════════════════════════════════════════════
## Обычный Unit без единой особой ветки: весь бой, движение, строй, ветеранство,
## туман и общая отрисовка достаются ему от базы даром — ровно этого и требует
## задание («использует ВСЕ базовые механики»). Своего здесь только две вещи:
## набор спрайт-лент и ротация двух ударов.
##
## ПОЧЕМУ ОН НЕ ПРОХОДИТ СКВОЗЬ СТРОЙ КОПЕЙЩИКОВ. Не потому, что здесь что-то
## для этого написано, а потому, что здесь НЕ написано исключений: блокировку
## шага чужим строем делает пакетный проход (ArmyCore.BatchMove), и обходят её
## только два признака — отход (retreating) и «коридор чист» (F_CLEAR_ENEMY),
## которые гоблин получает на общих основаниях. Отдельная оговорка потребовалась
## в другом месте: сетка соседей раньше делила мир на ДВЕ стороны, и третья
## фракция молча склеивалась с красными — см. ArmyCore.Factions.

const _SSParser := preload("res://scripts/SpriteSheetParser.gd")
const _GobCfgV  := preload("res://scripts/goblin/goblin_config.gd")

## Каталог гоблинских лент. Имя папки — С ЗАГЛАВНОЙ, ровно как на диске:
## PCK регистрозависим на всех ОС
const SHEET_DIR := "res://assets/factions/Goblin/"

## Ленты. Ключи — те же имена анимаций, что у людей (idle/walk/attack1/attack2),
## поэтому базовый автомат внешности работает без переопределений
const SHEETS := {
	"idle":    "Spear Goblin_Idle.png",
	"walk":    "Spear Goblin_Run.png",
	"attack1": "Spear Goblin_Attack Fast.png",
	"attack2": "Spear Goblin_Attack Strong.png",
}

## Каждый четвёртый удар — «Attack Strong». Та же ротация 3+1, что у мечника:
## два разных удара в спрайтах обязаны отличаться и в цифрах, иначе вторая
## лента — просто другая картинка того же самого
const STRONG_EVERY := 4

var _strong_damage: float = 20.0
var _combo_step: int = 0

func _ready() -> void:
	_apply_config_stats("goblin_spearman")
	_strong_damage = _UStats.stat("goblin_spearman", "attack_2", attack_damage * 2.0)
	display_name = "Гоблин-копейщик"
	super._ready()
	_setup_visual()

func _strike_damage() -> float:
	_combo_step += 1
	if _combo_step >= STRONG_EVERY:
		_combo_step = 0
		_play_attack_anim("attack2", 600)
		return _strong_damage
	_play_attack_anim("attack1", 380)
	return attack_damage

## ── ЛИЧНЫЙ ГАБАРИТ ─────────────────────────────────────────────────────────
## Спрайт гоблина в SIZE_SCALE раз крупнее людского, и общая на всю армию
## Unit.SEP_MIN_DIST оставляла бы орду слипшейся в сплошной ковёр. Раздвигать
## ради этого ВСЮ пехоту нельзя — у людей строй выверен по своим числам,
## поэтому радиус личный, колонкой в солвере (ArmySoA.set_sep_radius)
func sep_radius() -> float:
	return SEP_MIN_DIST * _GobCfgV.SIZE_SCALE

func _sfx_swing() -> String:
	return "spear_hit"

func _sfx_hit() -> String:
	return "sword_hit"

func _setup_visual() -> void:
	# Ленты ударов НЕ зациклены: удар проигрывается один раз и возвращает бойца
	# в idle/walk — это третий аргумент build_sprite_from_map
	var asp: AnimatedSprite3D = _SSParser.build_sprite_from_map(
		SHEET_DIR, SHEETS, ["attack1", "attack2"])
	if asp == null:
		# Ассетов нет — остаётся процедурный примитив базы. Падать нельзя:
		# правило проекта — отсутствующий ассет не роняет игру
		push_warning("GoblinSpearman: ленты не найдены в %s" % SHEET_DIR)
		return
	for child in get_children():
		if child is MeshInstance3D and child != selection_ring:
			child.visible = false
	_apply_goblin_scale(asp)
	add_child(asp)
	_active_sprite = asp

## ── СВОЙ МАСШТАБ И ЧЕСТНАЯ ПРИВЯЗКА К ЗЕМЛЕ ────────────────────────────────
## Общий размер пикселя (0.0108) подобран под кадры людей; у гоблина кадр
## крупнее (256 против 192-320), а рисунок в нём другой пропорции — при общем
## числе гоблин выходил ШИРЕ человека, будучи ниже его. Разбор и вывод числа —
## в goblin_config.PIXEL_SIZE.
##
## Высота центра спрайта пересчитывается ПО САМОЙ ЛЕНТЕ, а не берётся
## константой: константа 0.42 подобрана под старый размер пикселя, и с новым
## гоблин ушёл бы ногами под землю. Формула та же, по которой стенд qa_ring
## проверяет привязку: центр = (полкадра - прозрачный низ) x размер пикселя
func _apply_goblin_scale(asp: AnimatedSprite3D) -> void:
	asp.pixel_size = _GobCfgV.PIXEL_SIZE
	var frames: SpriteFrames = asp.sprite_frames
	if frames == null or not frames.has_animation("idle"):
		return
	var first: Texture2D = frames.get_frame_texture("idle", 0)
	if first == null:
		return
	var at := first as AtlasTexture
	var fh: float = at.region.size.y if at != null else first.get_size().y
	if fh <= 0.0:
		return
	var pad: int = _anim_bottom_px(first)
	asp.position.y = (fh * 0.5 - float(pad)) * asp.pixel_size
