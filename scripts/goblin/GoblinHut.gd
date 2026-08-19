extends Castle

## ═══════════════════════════════════════════════════════════════════════════
## ХИЖИНА ГОБЛИНОВ
## ═══════════════════════════════════════════════════════════════════════════
## НАСЛЕДУЕТ ЗАМОК, И ЭТО ГЛАВНОЕ РЕШЕНИЕ ЗДЕСЬ.
##
## Задание требует от хижины ровно того, что Замок уже умеет и что стоило этому
## проекту нескольких проходов отладки: принять разбитый отряд, спрятать его с
## карты, лечить раны, ДОУКОМПЛЕКТОВАТЬ до полного состава и выпустить наружу
## через ворота у нарисованной двери. Плюс к этому — весь общий обвес здания:
## полоска здоровья, пелена тумана, руины на месте гибели, эвакуация гарнизона
## при разрушении.
##
## Написать это заново значило бы завести вторую реализацию гарнизона со своими
## болезнями — а первая уже вылечена (софтлок «отряд марширует на месте у
## ворот», раскол отряда при отмене приказа, ghosts после сноса замка). Поэтому
## наследование, а от Замка отключается только то, что хижине не подходит:
## склад ресурсов (у гоблинов нет рабочих) и золотой доход (у них еда).
##
## Проверено, что подмена безопасна: `is Castle` встречается в пяти местах, и
## все они ограничены либо группой player_buildings, либо enemy_buildings, либо
## явной проверкой faction == FACTION_PLAYER. Хижина лежит в goblin_buildings.

const _UCfgH  := preload("res://scripts/unit_stats_config.gd")
const _GobCfg := preload("res://scripts/goblin/goblin_config.gd")

const SPRITE := "res://assets/factions/Goblin/Goblins building/Goblin Hut.png"

var _food_timer: float = 0.0

## Замок вынес настройку полей в _configure() именно ради этого наследника:
## _ready() у него общий, а всё, что у хижины своё, заменяется здесь
func _configure() -> void:
	building_id  = "goblin_hut"
	# Картинки в цветовых наборах людей у хижины нет, поэтому она берётся
	# запасным путём sprite_path (см. Building._maybe_load_building_sprite)
	sprite_path  = SPRITE
	max_health   = _UCfgH.building_stat("goblin_hut", "max_hp", 600.0)
	build_size   = _UCfgH.building_size("goblin_hut", Vector3(4.0, 3.5, 4.0))
	display_name = String(_UCfgH.building_cfg("goblin_hut").get("name", "Хижина гоблинов"))
	# СКЛАДА НЕТ: у гоблинов нет рабочих, а регистрация точки сдачи заставила бы
	# чужих рабочих считать хижину своей свалкой
	is_dropoff   = false
	squad_size   = 1
	squad_cols   = 4
	squad_spacing = _GobCfg.SQUAD_SPACING
	spawn_offset = Vector3(0.0, 0.0, HUT_GATE)

## Ворота ближе, чем у замка: хижина втрое меньше
const HUT_GATE := 3.2

## ── ДЫМ ИЗ ТРУБЫ ───────────────────────────────────────────────────────────
## Goblin Hut.png — не одна картинка, а лента из двенадцати кадров 256x256.
## Здание рисуется тем же шейдером, что и растения, и умеет их листать; раньше
## сюда жёстко передавался ноль кадров в секунду, и хижина навсегда замирала на
## первом кадре — дым стоял столбом. Фаза у каждой хижины своя (см.
## Building.sprite_frame_phase), иначе вся деревня пыхтит в один такт
func sprite_fps() -> float:
	return _GobCfg.HUT_SMOKE_FPS

func gate_depth() -> float:
	return HUT_GATE

## ЗАМКОВОЙ МОДЕЛИ У ХИЖИНЫ НЕТ. База Castle грузит castle.glb; здесь нужен
## только коллайдер и запасной примитив — картинку положит поверх
## Building._maybe_load_building_sprite
func _build_visual() -> void:
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = build_size
	collider.shape = shape
	collider.position.y = build_size.y * 0.5
	add_child(collider)
	_build_procedural_visual()
	selection_ring = make_selection_marker()
	add_child(selection_ring)

## ── ДОХОД ХИЖИНЫ ───────────────────────────────────────────────────────────
## +HUT_FOOD_PER_MIN еды в минуту, начисляется долями раз в HUT_TICK_SEC:
## непрерывный ручеёк вместо ступеньки на сто единиц раз в минуту. Идёт через
## gather_resource, а не add_resource, — это ДОБЫЧА, и она обязана попадать в
## счётчик притока наравне с рудником и домом людей
func _process(delta: float) -> void:
	super._process(delta)
	_food_timer += delta
	if _food_timer < _GobCfg.HUT_TICK_SEC:
		return
	var ticks: float = _food_timer / _GobCfg.HUT_TICK_SEC
	_food_timer = 0.0
	ResourceManager.gather_resource(faction, Constants.RESOURCE_FOOD,
		_GobCfg.HUT_FOOD_PER_MIN * (_GobCfg.HUT_TICK_SEC / 60.0) * ticks)

## Хижине покадровый тик нужен ВСЕГДА: она капает еду, а не только держит
## гарнизон. Замковое условие «тикаю, если я игрок или есть гарнизон» здесь
## оставило бы орду без экономики
func _needs_tick() -> bool:
	return true
