extends RefCounted
## РЕЛИКВИЯ-ШТАНДАРТ: копилка общего опыта армии и аура носителя.
## Логика — RelicManager.gd, кнопка — RelicButton.gd. Заметки — docs/config_notes/relic_config.md
const _Opt := preload("res://scripts/perf_config.gd")

## ── КОПИЛКА ──
## Опыта на одну выдачу или улучшение штандарта (ранг ветеранства не меняет — ТЗ 29.10.2026)
const POOL_COST := 3000.0
## Опыт копилки за одно засчитанное убийство (ТЗ 29.10.2026: ×0.5 — набор вдвое дольше)
const POOL_PER_KILL := 0.5
## Потолок улучшений штандарта: лычки 1-3 красные, 4-6 синие
const STANDARD_MAX_LEVEL := 6

## ── АУРА (союзникам носителя; из перекрывающихся боец берёт лучшую; скорость не меняет) ──
## Радиус, м: база и прибавка за каждый уровень реликвии сверх первого
const AURA_RADIUS := 15.0
const AURA_RADIUS_PER_LEVEL := 5.0
## Прибавка атаки: база и прибавка за уровень
const AURA_ATTACK := 2.0
const AURA_ATTACK_PER_LEVEL := 2.0
## Мораль бойца в ауре (Unit.morale — вес в продавливании) и подпитка морали отряда, очков/с
const AURA_MORALE := 15.0
const AURA_SQUAD_MORALE_PER_SEC := 2.0
## Ускорение удара: доля кулдауна долой (у всех уровней одна)
const AURA_COOLDOWN_FRAC := 0.10

## Такт пересчёта ауры (один проход по всем реликвиям) и такт проверки носителя/подбора, с
const AURA_TICK_SEC := 0.5
const PICK_TICK_SEC := 0.25
## Радиус подбора лежащей реликвии
const PICK_RADIUS := 1.5

## Высота флага над землёй, м: у носителя (выше знамени отряда) и у лежащей
const CARRY_Y := 2.55
const GROUND_Y := 0.75
## Цвет полотнища (золотой штандарт)
const CLOTH := Color(0.93, 0.74, 0.18)

## Радиус ауры штандарта по уровню 1-6 (ТЗ 29.10.2026: небольшая на первом,
## существенно растёт с каждым улучшением)
const AURA_RADII := [8.0, 13.0, 19.0, 26.0, 34.0, 43.0]

static func aura_radius(level: int) -> float:
	if _Opt.standard_squad:
		return float(AURA_RADII[clampi(level, 1, AURA_RADII.size()) - 1])
	return AURA_RADIUS + AURA_RADIUS_PER_LEVEL * float(maxi(level, 1) - 1)

static func aura_attack(level: int) -> float:
	return AURA_ATTACK + AURA_ATTACK_PER_LEVEL * float(maxi(level, 1) - 1)
