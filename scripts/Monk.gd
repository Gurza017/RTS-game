extends Unit
class_name Monk

## МОНАХ — третий найм Замка (владелец: "проанализируй папки проекта, найди
## ассет monk"). У ассета (assets/factions/humans/units/<Цвет> Units/Monk/)
## есть только Idle.png/Run.png/Heal.png/Heal_Effect.png — атаки в листе нет,
## поэтому монах дерётся ГОЛЫМИ РУКАМИ через ту же общую боевую петлю, что и
## остальные юниты (Unit._strike_damage() без переопределения), просто со
## скромными характеристиками из unit_stats_config.gd ("monk"). Heal.png —
## задел на будущее (лечение союзников), в этом проходе не подключён:
## задача была "найм Монаха работает", а не полноценный хилер.
const _SSParser := preload("res://scripts/SpriteSheetParser.gd")

func _ready() -> void:
	_apply_config_stats("monk")
	display_name = "Монах"
	super._ready()
	_setup_monk_visual()

func _setup_monk_visual() -> void:
	var fname := GameManager.race_of(faction)
	var pack_path := GameManager.unit_sprite_folder(faction, "monk")
	# Проба ПО ФАЙЛУ, а не по каталогу (см. SpriteSheetParser.folder_has)
	var colored := _SSParser.folder_has(pack_path, "Idle.png")
	if not colored:
		pack_path = "res://assets/factions/%s/units/soldier_pack" % fname
	var tint := Color.WHITE
	if not colored:
		tint = Color(1.0, 0.55, 0.55) if faction == Constants.FACTION_ENEMY else Color(0.82, 0.92, 1.0)

	var mapped: AnimatedSprite3D = _SSParser.build_sprite_from_map(pack_path, {
		"idle": "Idle.png",
		"walk": "Run.png",
	}, [])
	if mapped:
		for child in get_children():
			if child is MeshInstance3D and child != selection_ring:
				child.visible = false
		mapped.modulate = tint
		add_child(mapped)
		_active_sprite = mapped
		return

	var asp: AnimatedSprite3D = _SSParser.build_animated_sprite(pack_path)
	if asp:
		for child in get_children():
			if child is MeshInstance3D and child != selection_ring:
				child.visible = false
		asp.modulate = tint
		add_child(asp)
		_active_sprite = asp
		return

	# Цветовой оттенок на базовом billboard-спрайте — крайний случай, как у Warrior
	_ensure_body_quad()
	if _sprite_node:
		var mat := _sprite_node.get_active_material(0) as StandardMaterial3D
		if mat:
			mat.albedo_color = Color(0.95, 0.90, 0.55) if faction == Constants.FACTION_PLAYER else Color(0.90, 0.30, 0.30)
