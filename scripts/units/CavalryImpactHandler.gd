extends RefCounted
## ═══════════════════════════════════════════════════════════════════════════
## НАПРАВЛЕННЫЙ ЧАРДЖ КОННИЦЫ: СЕКТОР УДАРА, УРОН, РАЗЛЁТ, МОРАЛЬ
## (ТЗ 19.09.2026, «Направленный Чардж и Фланговый Урон»)
## ═══════════════════════════════════════════════════════════════════════════
## Модуль БЕЗ узла и БЕЗ тика: зовётся ОДИН раз на СОБЫТИЕ касания — из
## Unit._charge_impact, в тот кадр, когда пакетный шаг всадника упёрся в
## чужое тело (_enemy_contact). Цена — несколько умножений на отряд:
##   • сектор удара — скалярное произведение двух векторов, O(1) на отряд:
##       dot(направление конницы, направление строя копейщиков)
##       dot ≈ −1 → ЛОБ, dot ≈ 0 → ФЛАНГ, dot ≈ +1 → ТЫЛ / СПИНА;
##   • направление строя жертвы — ГОТОВОЕ отрядное число (в бою —
##     squad_enemy_dir, иначе курс разметки squad_course), а не усреднение
##     взглядов состава; у одиночки — его взгляд;
##   • множители урона и отлёта и удар по морали — по сектору из таблицы.
## Ни RayCast, ни перебора моделей здесь нет: круг первого ряда контакта
## (charge_splash) и так собирает _charge_impact одним запросом сетки, и
## этот модуль лишь умножает то, что он снимает с накрытых.
##
## ЛОБ НЕ ТРОГАЕТСЯ: удар в лоб копейщикам — прежние правила (repels_charge,
## контрукол charge_counter_frac, «Стена копий»). Здесь только фланг и тыл.
##
## Пороги те же, что у фаланги (PHALANX_FRONT_COS / CHARGE_FRONT_COS): «в лоб»
## обязано означать одно и то же во всех механиках проекта.

const FRONT_COS := 0.34

const SECTOR_FRONT := 0
const SECTOR_FLANK := 1
const SECTOR_REAR  := 2

## ── ТАБЛИЦА СЕКТОРОВ ────────────────────────────────────────────────────────
## Урон тарана (charge_impact_frac от запаса жертвы) и второго ряда
## (charge_row2_frac) умножаются на DMG; отлёт (charge_knockback) — на KB;
## отряд жертвы теряет MORALE очков морали разом (один раз на касание)
const FLANK_DMG_MULT := 1.5
const REAR_DMG_MULT  := 2.0
const FLANK_KB_MULT  := 1.25
const REAR_KB_MULT   := 1.5
const FLANK_MORALE_HIT := 6.0
const REAR_MORALE_HIT  := 15.0

## ── ДОЛИ ЗАПАСА ПО СЕКТОРУ (ТЗ 24.09.2026, п. 2) ──────────────────────────
## Удар в тыл снимает у каждого накрытого REAR_FRAC его МАКСИМАЛЬНОГО запаса,
## во фланг — FLANK_FRAC; мимо брони (Unit.take_frac_damage)
const REAR_FRAC  := 0.50
const FLANK_FRAC := 0.25
## Круг накрытия при ударе сбоку и сзади — шире лобового
const SIDE_SPLASH_MULT := 1.5
## Отлёт при ударе сбоку/сзади — доля charge_knockback (ТЗ 24.09.2026-2:
## разлёт короче, летят только первые два ряда)
const SIDE_KNOCK_MULT := 0.6

static func sector_frac(sec: int) -> float:
	return REAR_FRAC if sec == SECTOR_REAR else (FLANK_FRAC if sec == SECTOR_FLANK else 0.0)

## ── ЛОБ НА КОПЬЯ: ПЕРВАЯ ВОЛНА И ПОСЛЕДУЮЩИЕ ──────────────────────────────
## Без «Стены копий» всадник первой волны теряет FIRST_WAVE_FRAC своего
## максимального запаса, следующих волн — NEXT_WAVE_FRAC; со стеной — то же ×
## WALL_COUNTER_MULT («300 % входящего урона»).
## ВОЛНА СЧИТАЕТСЯ ПО ОТРЯДУ КОПЕЙЩИКОВ: эпизод открывает первое касание; всё,
## что влетело в тот же отряд за WAVE_WINDOW_MS, — первая волна (всадники
## одного натиска касаются строя вразнобой, в пределах секунды-двух), позже —
## вторая. Эпизод гаснет, если касаний не было WAVE_RESET_MS: следующий
## натиск снова встречает «свежие» копья
const FIRST_WAVE_FRAC := 0.50
## Каждый второй всадник первой волны — насмерть (доля > 1 с запасом)
const FIRST_WAVE_LETHAL := 1.05
const NEXT_WAVE_FRAC  := 0.25
const WALL_COUNTER_MULT := 3.0
const WAVE_WINDOW_MS := 1500
const WAVE_RESET_MS  := 10000
## sid копейщиков → [начало эпизода, последнее касание], мс
static var _waves: Dictionary = {}

static func front_wave_frac(spear: Unit) -> float:
	var key: int = spear.squad_id if spear.squad_id > 0 else -spear.get_instance_id()
	var now: int = Unit.game_ms()
	var w: Variant = _waves.get(key)
	if w == null or now - int(w[1]) > WAVE_RESET_MS:
		_waves[key] = PackedInt64Array([now, now, 1])
		return FIRST_WAVE_FRAC
	var ep: PackedInt64Array = w
	ep[1] = now
	if now - ep[0] > WAVE_WINDOW_MS:
		_waves[key] = ep
		return NEXT_WAVE_FRAC
	# ── ПЕРВАЯ ВОЛНА: КАЖДЫЙ ВТОРОЙ ГИБНЕТ НА КОПЬЯХ (ТЗ 24.09.2026, второе
	# письмо) ── нечётные касания эпизода — 50 % запаса, чётные — насмерть
	ep[2] = ep[2] + 1
	_waves[key] = ep
	return FIRST_WAVE_LETHAL if ep[2] % 2 == 0 else FIRST_WAVE_FRAC

## Стендам: сколько касаний пришлось на каждый сектор и последний профиль
static var hits: PackedInt32Array = PackedInt32Array([0, 0, 0])
static var last: Dictionary = {}

static func reset_stats() -> void:
	_waves.clear()
	hits = PackedInt32Array([0, 0, 0])
	last = {}

## Сектор по скалярному произведению направления конницы и строя (XZ).
## Нет направления строя (стоят как попало) — считаем фланг
static func sector_of(cav_dir: Vector3, facing: Vector3) -> int:
	var fl: float = facing.x * facing.x + facing.z * facing.z
	var cl: float = cav_dir.x * cav_dir.x + cav_dir.z * cav_dir.z
	if fl < 1e-6 or cl < 1e-6:
		return SECTOR_FLANK
	var d: float = (cav_dir.x * facing.x + cav_dir.z * facing.z) / sqrt(fl * cl)
	if d < -FRONT_COS:
		return SECTOR_FRONT
	if d > FRONT_COS:
		return SECTOR_REAR
	return SECTOR_FLANK

## Направление строя жертвы — отрядное, без обхода состава
static func squad_facing(victim: Unit) -> Vector3:
	if victim.squad_id > 0:
		var d: Vector3 = GameManager.squad_enemy_dir(victim.squad_id)
		if d.length_squared() > 1e-6 and GameManager.squad_in_combat(victim.squad_id):
			return d
		var c: Vector3 = GameManager.squad_course(victim.squad_id)
		if c.length_squared() > 1e-6:
			return c
	return victim._facing

## Профиль касания: {sector, dot, dmg, kb, morale}
static func profile(cav_dir: Vector3, victim: Unit) -> Dictionary:
	var facing: Vector3 = squad_facing(victim)
	var sec: int = sector_of(cav_dir, facing)
	var dmg: float = 1.0
	var kb: float = 1.0
	var morale: float = 0.0
	match sec:
		SECTOR_FLANK:
			dmg = FLANK_DMG_MULT
			kb = FLANK_KB_MULT
			morale = FLANK_MORALE_HIT
		SECTOR_REAR:
			dmg = REAR_DMG_MULT
			kb = REAR_KB_MULT
			morale = REAR_MORALE_HIT
	var fl: float = facing.length()
	var dot: float = 0.0
	if fl > 1e-6:
		dot = (cav_dir.x * facing.x + cav_dir.z * facing.z) / fl
	var out: Dictionary = {"sector": sec, "dot": dot, "dmg": dmg, "kb": kb, "morale": morale}
	if sec >= 0 and sec < 3:
		hits[sec] += 1
	last = out
	return out

## Удар по морали отряда жертвы — раз на касание, через тот же канал, что
## потери и попадания (GameManager.squad_add_morale)
static func apply_morale(victim: Unit, prof: Dictionary) -> void:
	var m: float = float(prof.get("morale", 0.0))
	if m <= 0.0 or victim == null or not is_instance_valid(victim) or victim.squad_id <= 0:
		return
	GameManager.squad_add_morale(victim.squad_id, -m)
