extends RefCounted

## ═══════════════════════════════════════════════════════════════════════════
## МАРШ ВОЛНЫ КРАСНЫХ ПРИВАЛАМИ (ТЗ 31.10.2026, «главная мысль», ручка
## perf_config.ai_wave_stages)
## ═══════════════════════════════════════════════════════════════════════════
## Тот же порядок, что у орды (scripts/goblin/WaveMarch.gd), но для красного
## ИИ: волна штурма идёт к цели этапами — выход с базы, подступ к броду, за
## бродом — и на каждом привале встаёт ВСЕМ боевым порядком (план волны
## EnemyAI._command_squads переносится на точку привала целиком: ряды, крылья
## и разнос родов сохраняются). Дальше — когда собрались все (центр каждого
## отряда ближе HALT_ARRIVE_R к своему месту) и простояли RED_HALT_MIN_SEC,
## либо вышел срок этапа. Скан — по центру волны раз в такт ИИ: игрок ближе
## CONTACT_R — привалы снимаются, волна развёртывается к цели.
## Числа — блок HALT_* в spawn_config (общие с ордой) и RED_HALT_MIN_SEC.

const _Spawn := preload("res://scripts/spawn_config.gd")

## Стоянка на привале после сбора всех, с
const RED_HALT_MIN_SEC := 5.0

var ai = null                    # EnemyAI
var legs: Array = []
var leg: int = -1
var leg_t: float = 0.0
var leg_len: float = 0.0
var gather_t: float = -1.0
var launched: bool = false
var active: bool = false
# Счётчики стендам
var launches: int = 0
var halts_done: int = 0
var halts_timeout: int = 0
var contacts: int = 0

func reset() -> void:
	legs = []
	leg = -1
	launched = false
	active = false
	gather_t = -1.0

func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()

## Выход волны: привалы от центра волны к цели
func launch(wave_c: Vector3, target: Vector3) -> void:
	launched = true
	launches += 1
	legs = []
	var dir0: Vector3 = target - wave_c
	dir0.y = 0.0
	if dir0.length() < 1.0:
		active = false
		return
	dir0 = dir0.normalized()
	var raw: Array = [wave_c + dir0 * _Spawn.HALT_EXIT_DIST]
	var main = ai.main
	if main != null and main.has_method("ford_route"):
		var fr: Array = main.call("ford_route", wave_c, target, 0.0)
		if fr.size() == 2:
			var a: Vector3 = fr[0]
			var b: Vector3 = fr[1]
			var across: Vector3 = b - a
			across.y = 0.0
			across = across.normalized() if across.length() > 0.1 else dir0
			raw.append(a - across * _Spawn.HALT_FORD_APPROACH)
			raw.append(b + across * _Spawn.HALT_FORD_EXIT)
	var prev: Vector3 = wave_c
	var stage_r: float = _Spawn.WAVE_STAGE_DIST + _Spawn.HALT_MIN_GAP * 0.5
	for p in raw:
		var q: Vector3 = p
		var dq: float = _flat(q - target)
		if _flat(q - prev) < _Spawn.HALT_MIN_GAP or dq >= _flat(prev - target) or dq < stage_r:
			continue
		legs.append(GameManager.land_target(q))
		prev = q
	active = not legs.is_empty()
	if active:
		_next(wave_c, 0)

func _next(from: Vector3, li: int) -> void:
	leg = li
	leg_t = ai.clock
	gather_t = -1.0
	if leg >= legs.size():
		active = false
		return
	leg_len = _flat((legs[leg] as Vector3) - from)

## Подменить цели плана волны точками привала; plan — [sq, tgt, uid]
func stage(plan: Array, target_pos: Vector3, wave_c: Vector3) -> void:
	if not active or leg < 0 or leg >= legs.size():
		return
	if wave_c != Vector3.ZERO and ai._nearest_player_target(wave_c, _Spawn.CONTACT_R) != null:
		contacts += 1
		active = false
		return
	var p: Vector3 = legs[leg]
	var shift: Vector3 = p - target_pos
	shift.y = 0.0
	var all_in := true
	for e in plan:
		var t: Vector3 = GameManager.land_target((e[1] as Vector3) + shift)
		e[1] = t
		var c: Vector3 = ai._squad_centroid((e[0] as Dictionary)["members"])
		if c == Vector3.ZERO or _flat(c - t) > _Spawn.HALT_ARRIVE_R:
			all_in = false
	if all_in and gather_t < 0.0:
		gather_t = ai.clock
	var over: bool = ai.clock - leg_t > _Spawn.HALT_LEG_BASE_SEC + leg_len / _Spawn.HALT_LEG_SPEED
	if (all_in and ai.clock - gather_t >= RED_HALT_MIN_SEC) or over:
		if all_in:
			halts_done += 1
		else:
			halts_timeout += 1
		_next(p, leg + 1)

## Точка текущего привала (Vector3.INF — привалов нет)
func halt_point() -> Vector3:
	if not active or leg < 0 or leg >= legs.size():
		return Vector3.INF
	return legs[leg]
