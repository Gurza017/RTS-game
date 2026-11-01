extends RefCounted
## ═══════════════════════════════════════════════════════════════════════════
## БОНУСЫ КУЗНИЦЫ ГОБЛИНОВ — ПРИМЕНЕНИЕ (ТЗ 28.10.2026)
## ═══════════════════════════════════════════════════════════════════════════
## Копит бонусы GameManager._accumulate_upgrade по фракции и роду войск
## (unit_bonuses[FACTION_GOBLIN][род]); читаются они ВЖИВУЮ теми же ветками,
## что и бонусы людей: броня — Unit.take_damage, удар — _upgrade_damage_bonus,
## скорость — _base_speed, темп — _effective_cooldown (bonus_cooldown_pct),
## мораль — _effective_morale, против конницы — GoblinSpearman._strike_damage
## (bonus_giant_melee). Запас жизни вживую не читается: уже стоящим его
## поднимает GameManager._apply_health_bonus_now, а новорождённым орды — on_born
## из Main._horde_one (единственная точка спавна орды).

static func is_forge(n) -> bool:
	return n != null and is_instance_valid(n) and n is Building \
		and String((n as Building).building_id) == "goblin_forge"

## Живая кузница фракции (null — нет)
static func forge_of(tree: SceneTree, faction: int) -> Node:
	if tree == null:
		return null
	for b in tree.get_nodes_in_group(Constants.building_group(faction)):
		if is_forge(b) and not (b as Building).is_dead():
			return b
	return null

## Новорождённый гоблин: запас жизни из изученного «Орочьего допинга» вписывается
## в поле при рождении (bonus_health не читается вживую, см. Unit._ready)
static func on_born(u: Unit) -> void:
	if u == null or not is_instance_valid(u) or u.faction != Constants.FACTION_GOBLIN:
		return
	var hp: float = GameManager.unit_bonus(u.faction, u.stat_id, "bonus_health")
	if hp == 0.0:
		return
	u.max_health += hp
	u.current_health += hp
	u._soa_push_stats()
