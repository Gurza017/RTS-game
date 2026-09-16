extends Castle
class_name Barracks
## ═══════════════════════════════════════════════════════════════════════════
## БАРАКИ: НАЙМ ПЕХОТЫ + ОТРЯД ЛУЧНИКОВ НА КРЫШЕ (ТЗ 14.09.2026)
## ═══════════════════════════════════════════════════════════════════════════
## НАСЛЕДУЮТ ЗАМОК ради гарнизона — тем же порядком, что башня и хижина орды:
## принять отряд, спрятать с карты, выпустить через ворота. Крыша — общий
## модуль RoofGarrison (плотная сетка 6 × 5 на скате крыши, до 30 стрелков).
## Лучники наверху стреляют с баффом высоты и ловят чужие стрелы; пехоту
## бараки не принимают, вылеченных сами не выпускают (это пост), золота не
## дают и столицей не являются (is_stronghold = false — зона застройки,
## лимит населения, условие поражения бараков не видят).
##
## Найм — как прежде: копейщики и мечники из TRAINING["barracks"].

func _configure() -> void:
	building_id  = "barracks"
	sprite_path   = "res://assets/sprites/buildings/barracks.png"
	max_health    = _UCfg.building_stat("barracks", "max_hp", 300.0)
	build_size    = _UCfg.building_size("barracks", Vector3(3.5, 2.2, 3.5))
	display_name  = String(_UCfg.building_cfg("barracks").get("name", "Бараки"))
	is_dropoff    = false
	squad_size    = 20
	squad_cols    = 5
	squad_spacing = 0.35
	# spawn_offset здесь не задаётся: точку выхода держит узел SpawnPoint у
	# нарисованных дверей, и _face_front() перезаписывает офсет по нему
	# (см. Building — «ТОЧКА ВЫХОДА»)

func _roof_setup():
	var r = _Roof.new()
	r.setup(self, _Roof.LAYOUT_GRID, int(_UCfg.ROOF_VISIBLE.get("barracks", 30)),
		float(_UCfg.ROOF_FOOT_FRAC.get("barracks", 0.56)))
	return r

## Бараки — не столица
func is_stronghold() -> bool:
	return false

## Один отряд, и только лучники — на крышу
func garrison_limit() -> int:
	return roof_squads_max()

func garrison_accepts(unit_type: String) -> bool:
	return unit_type == "archer"

## Пост, а не лазарет
func _auto_release() -> bool:
	return false

## Обзор обычного дома, не крепости
func vision_radius() -> float:
	return _UCfg.BUILDING_VISION

## Ворота — правило обычной постройки (Building.gate_depth), не замковые 6.5 м
func gate_depth() -> float:
	var by_box: float = build_size.z * 0.5
	var d: float = by_box
	if _draw_half_w >= 0.0:
		d = minf(by_box, _draw_half_w)
	return minf(d, GATE_MAX_DEPTH) + GATE_CLEARANCE

## Тик — на время очереди найма (Building) и гарнизона
func _needs_tick() -> bool:
	return not garrison.is_empty() or not _incoming.is_empty()

## Замковой модели у бараков нет: примитив + форма клика, картинку кладёт
## Building._maybe_load_building_sprite (та же коробка, что у обычной постройки)
func _build_visual() -> void:
	_add_pick_shape()
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = build_size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.35, 0.85) if faction == Constants.FACTION_PLAYER else Color(0.75, 0.2, 0.2)
	box.material = mat
	mesh_instance.mesh = box
	mesh_instance.position.y = build_size.y / 2.0
	add_child(mesh_instance)
	selection_ring = make_selection_marker()
	add_child(selection_ring)

## Выпустить лучников с крыши (кнопка панели / ПКМ пустым выделением)
func release_all() -> bool:
	return release_roof()

func has_garrison() -> bool:
	return not garrison.is_empty()

## Стрелковый отряд на крыше (подпись панели, тот же контракт, что у башни)
func garrison_squad_id() -> int:
	return int(_roof.squad_id()) if _roof != null else 0

# Цена, время и размер отряда — из конфига (TRAINING["barracks"])
func train_spearman() -> bool:
	return train_from_config("spearman")

func train_archer() -> bool:
	return train_from_config("archer")
