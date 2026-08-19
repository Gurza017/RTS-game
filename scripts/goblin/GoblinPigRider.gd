extends Unit

## ═══════════════════════════════════════════════════════════════════════════
## ГОБЛИН НА КАБАНЕ
## ═══════════════════════════════════════════════════════════════════════════
## Быстрая ударная конница орды: догоняет, продавливает строй напором кабана
## (push_force вдвое выше рыцарского) и быстро гибнет под копьями. Механики —
## все базовые, как и у пешего гоблина.

const _SSParser := preload("res://scripts/SpriteSheetParser.gd")
const _GobCfgV  := preload("res://scripts/goblin/goblin_config.gd")

const SHEET_DIR := "res://assets/factions/Goblin/"
const SHEETS := {
	"idle":   "Pig Rider_Idle.png",
	"walk":   "Pig Rider_Run.png",
	"attack": "Pig Rider_Attack.png",
}

func _ready() -> void:
	_apply_config_stats("goblin_rider")
	display_name = "Наездник на кабане"
	super._ready()
	_setup_visual()

func _strike_damage() -> float:
	_play_attack_anim("attack", 420)
	return attack_damage

func _sfx_swing() -> String:
	return "sword_attack"

func _sfx_hit() -> String:
	return "sword_hit"

func _setup_visual() -> void:
	var asp: AnimatedSprite3D = _SSParser.build_sprite_from_map(
		SHEET_DIR, SHEETS, ["attack"])
	if asp == null:
		push_warning("GoblinPigRider: ленты не найдены в %s" % SHEET_DIR)
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
