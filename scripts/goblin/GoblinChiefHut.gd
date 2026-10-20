extends "res://scripts/goblin/GoblinHut.gd"

## ═══════════════════════════════════════════════════════════════════════════
## ГЛАВНАЯ ХАТА ЛАГЕРЯ ОРДЫ (ТЗ 11.10.2026, часть 2)
## ═══════════════════════════════════════════════════════════════════════════
## Единственное место, где рождаются войска орды (GoblinAI покупает отряды
## за еду и выпускает их на площадку сбора перед хатой). Вдвое больше хижины
## (CHIEF_HUT_SIZE_MULT — тот же рисунок, квад растёт от build_size), запас
## CHIEF_HUT_HP, и сама чинится: если по ней не били CHIEF_HUT_REGEN_DELAY_SEC,
## прибавляет CHIEF_HUT_REGEN_PER_SEC в секунду до полного запаса.
## Без class_name — подключается через preload (кэш классов не трогаем).

const _SpawnC := preload("res://scripts/spawn_config.gd")

func _configure() -> void:
	super._configure()
	building_id  = "goblin_chief_hut"
	max_health   = _SpawnC.CHIEF_HUT_HP
	build_size   = build_size * _SpawnC.CHIEF_HUT_SIZE_MULT
	display_name = "Главная хата орды"
	spawn_offset = Vector3(0.0, 0.0, HUT_GATE * _SpawnC.CHIEF_HUT_SIZE_MULT)

## Тикает ради починки: пока запас полный, вход дешёвый (одно сравнение)
func _process(delta: float) -> void:
	super._process(delta)
	if _dead or current_health >= max_health:
		return
	if Time.get_ticks_msec() - last_hit_ms < int(_SpawnC.CHIEF_HUT_REGEN_DELAY_SEC * 1000.0):
		return
	current_health = minf(max_health, current_health + _SpawnC.CHIEF_HUT_REGEN_PER_SEC * delta)
	_update_hp_bar()

func _needs_tick() -> bool:
	return true
