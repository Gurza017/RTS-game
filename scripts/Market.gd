extends Building
## РЫНОК (ТЗ 27.10.2026, п. 4) — обменник ресурсов «как в Казаках»: три
## торговые палатки, по клику — окно обмена (scripts/ui/MarketPanel.gd).
##
## Курс ФИКСИРОВАННЫЙ: у каждого ресурса своя «цена» в общих единицах
## (unit_stats_config.MARKET.value), с обмена берётся пошлина MARKET.fee.
## Отдать N ресурса A — получить N · value[A] / value[B] · (1 − fee) ресурса B.
## Пошлина и разные цены — то, что не даёт гонять ресурс по кругу в плюс:
## A → B → A всегда возвращает меньше, чем ушло.
##
## Файл НАМЕРЕННО без class_name: подключается preload/load (тот же приём,
## что у House / Archery).

const _UCfg := preload("res://scripts/unit_stats_config.gd")

func _ready() -> void:
	building_id  = "market"
	sprite_path  = ""
	is_dropoff   = false
	max_health   = _UCfg.building_stat("market", "max_hp", 3000.0)
	build_size   = _UCfg.building_size("market", Vector3(3.5, 2.2, 3.5))
	display_name = String(_UCfg.building_cfg("market").get("name", "Рынок"))
	super._ready()

## Сколько B выйдет за amount ресурса A (без проверки запаса)
static func quote(from_type: int, to_type: int, amount: float) -> float:
	if from_type == to_type or amount <= 0.0:
		return 0.0
	var val: Dictionary = _UCfg.MARKET["value"]
	var va: float = float(val.get(from_type, 1.0))
	var vb: float = float(val.get(to_type, 1.0))
	if vb <= 0.0:
		return 0.0
	return floorf(amount * va / vb * (1.0 - float(_UCfg.MARKET["fee"])))

## Обмен: списать amount ресурса A, зачислить B по курсу. false — не хватает
## запаса или рынок не годен (снесён / недострой / чужой)
func trade(by_faction: int, from_type: int, to_type: int, amount: float) -> bool:
	if is_dead() or by_faction != faction or from_type == to_type or amount <= 0.0:
		return false
	var got: float = quote(from_type, to_type, amount)
	if got <= 0.0:
		return false
	if not ResourceManager.spend(by_faction, {from_type: amount}):
		return false
	ResourceManager.add_resource(by_faction, to_type, got)
	trades += 1
	return true

## Сколько сделок прошло (стенды, телеметрия)
var trades: int = 0
