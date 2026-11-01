extends Node
## ═══════════════════════════════════════════════════════════════════════════
## СТЕНД ТЗ 29.10.2026 «ЗНАМЁНА ПО СКЕТЧАМ И ОБЩИЙ ОПЫТ»
## ═══════════════════════════════════════════════════════════════════════════
## A — рисунок знамён орды (BannerArt):
##   A1-A2 ранги 1-6 — горизонтальный зелёный вымпел, у древка вертикальные
##         лычки: 1-3 красные, 4-6 синие, число растёт;
##   A3-A4 легенда — рваный штандарт с шевронами: ступень 1 + престиж,
##         красный 1-3 → синий → жёлтый;
##   A5    паника — те же формы белые, без знаков;
##   A6    Свинобосс — рваный зелёный штандарт с дырами, без знаков.
## B — престиж легенды орды: знак на штандарте без прибавок (goblin_legend_marks).
## C — общий опыт отдельно от личного: копилка ×0.5 за убийство, убийства
##     штандарта не дают; радиус ауры растёт существенно по уровням.
## (Выдача, потолок, передача соседу и легенда со штандартом — qa_relic B/D/E/J.)
## Запуск: godot --headless --path . res://qa_banner1029/Test.tscn [-- knob=…]

const F := Constants.FACTION_PLAYER
const G := Constants.FACTION_GOBLIN
const R := Constants.FACTION_ENEMY
const _BA := preload("res://scripts/BannerArt.gd")
const _SB := preload("res://scripts/SquadBanner.gd")
const _UCfg := preload("res://scripts/unit_stats_config.gd")
const _RCfg := preload("res://scripts/relic_config.gd")

var main: Node = null
var _pass := 0
var _fail := 0
var _done := false

func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(300.0).timeout.connect(func():
		print("  СТОРОЖ: стенд не завершился")
		_finish())

func verdict(t: String, ok: bool, d: String = "") -> void:
	if ok: _pass += 1
	else:  _fail += 1
	print("  ВЕРДИКТ %s: %s%s" % [t, "ПРОШЛО" if ok else "НЕ ПРОШЛО", ("  — " + d) if d != "" else ""])

func _finish() -> void:
	if _done:
		return
	_done = true
	print("\n═════ ИТОГ qa_banner1029: прошло %d, провалов: %d ═════" % [_pass, _fail])
	get_tree().quit()

func pframes(n: int) -> void:
	for _i in range(n):
		await get_tree().physics_frame

func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.02 and absf(a.g - b.g) < 0.02 and absf(a.b - b.b) < 0.02

## Пикселей цвета col на текстуре
func _count(tex: Texture2D, col: Color) -> int:
	var img: Image = tex.get_image()
	var n := 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c: Color = img.get_pixel(x, y)
			if c.a > 0.5 and _near(c, col):
				n += 1
	return n

## Зелёных пикселей ткани
func _green(tex: Texture2D) -> int:
	var img: Image = tex.get_image()
	var n := 0
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c: Color = img.get_pixel(x, y)
			if c.a > 0.5 and c.g > c.r + 0.2 and c.g > c.b + 0.2:
				n += 1
	return n

## Габарит зелёной ткани: Vector2(ширина, высота)
func _green_box(tex: Texture2D) -> Vector2:
	var img: Image = tex.get_image()
	var x0 := 9999
	var x1 := -1
	var y0 := 9999
	var y1 := -1
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			var c: Color = img.get_pixel(x, y)
			if c.a > 0.5 and c.g > c.r + 0.2 and c.g > c.b + 0.2:
				x0 = mini(x0, x)
				x1 = maxi(x1, x)
				y0 = mini(y0, y)
				y1 = maxi(y1, y)
	return Vector2(x1 - x0 + 1, y1 - y0 + 1)

func _marks(tex: Texture2D) -> Array:
	return [_count(tex, _BA.GOB_RED), _count(tex, _BA.GOB_BLUE), _count(tex, _BA.GOB_YELLOW)]

func _run() -> void:
	_block_a()
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await pframes(30)
	for n in ["enemy_ai", "goblin_ai", "assault_event", "gnoll_ai", "cav_commander", "raid_manager", "boss_commander"]:
		var nd = main.get(n)
		if nd != null:
			nd.set_process(false)
			nd.set_physics_process(false)
	await _block_b()
	await _block_c()
	_finish()

# ═════════════════════════════════════════════════════════════════════════════
func _block_a() -> void:
	print("\n═════ A. РИСУНОК ЗНАМЁН ОРДЫ ═════")
	var ok1 := true
	var info: Array = []
	var prev := 0
	for lvl in range(1, 7):
		var m: Array = _marks(_BA.goblin_tongue_texture(lvl))
		var own: int = int(m[0]) if lvl <= 3 else int(m[1])
		var other: int = int(m[1]) if lvl <= 3 else int(m[0])
		info.append("%d:%s" % [lvl, str(m)])
		# Внутри цвета число лычек растёт; чужого цвета и жёлтого нет
		var grows: bool = own > 0 and (lvl == 1 or lvl == 4 or own > prev)
		ok1 = ok1 and grows and other == 0 and int(m[2]) == 0
		prev = own
	verdict("A1 вымпел орды: лычки 1-3 красные, 4-6 синие, число растёт", ok1, " ".join(info))
	var box: Vector2 = _green_box(_BA.goblin_tongue_texture(2))
	verdict("A2 вымпел горизонтальный и длинный (ширина ≥ 3 высоты)", box.x >= box.y * 3.0,
		"%.0f × %.0f" % [box.x, box.y])
	var l0: Texture2D = _BA.goblin_tongue_texture(_UCfg.LEGEND_TIER)
	var lb: Vector2 = _green_box(l0)
	verdict("A3 легенда орды — рваный штандарт (вертикальный) с красным шевроном",
		l0 == _BA.goblin_rag_texture(1) and lb.y > lb.x and int(_marks(l0)[0]) > 0,
		"%.0f × %.0f, знаки %s" % [lb.x, lb.y, str(_marks(l0))])
	var s3: Array = _marks(_BA.goblin_tongue_texture(_UCfg.LEGEND_TIER, false, 2))
	var s4: Array = _marks(_BA.goblin_tongue_texture(_UCfg.LEGEND_TIER, false, 3))
	var s7: Array = _marks(_BA.goblin_tongue_texture(_UCfg.LEGEND_TIER, false, 6))
	verdict("A4 шевроны по престижу: 3 красных → синий → жёлтый",
		int(s3[0]) > int(_marks(l0)[0]) and int(s4[1]) > 0 and int(s4[0]) == 0 and int(s7[2]) > 0 and int(s7[1]) == 0,
		"престиж 2 %s, 3 %s, 6 %s" % [str(s3), str(s4), str(s7)])
	var w2: Array = _marks(_BA.goblin_tongue_texture(2, true))
	var w7: Array = _marks(_BA.goblin_tongue_texture(_UCfg.LEGEND_TIER, true, 3))
	verdict("A5 паника: белые полотнища без знаков, форма та же",
		int(w2[0]) + int(w2[1]) + int(w2[2]) == 0 and int(w7[0]) + int(w7[1]) + int(w7[2]) == 0
		and _green(_BA.goblin_tongue_texture(2, true)) == 0, "вымпел %s, штандарт %s" % [str(w2), str(w7)])
	# РАЗВОРОТ ТЗ 30.10.2026: знамя Свинобосса — общая синяя шкала, не ниже
	# трёх белых лычек (подробно — qa_pig_boss A11)
	var bt: Texture2D = _BA.boss_texture()
	# РАЗВОРОТ ТЗ 31.10.2026: орда и Свинобосс — зелёные знамёна
	verdict("A6 знамя Свинобосса — зелёные язычки орды, ранг не ниже BOSS_BANNER_MIN_TIER",
		bt == _BA.goblin_tongue_texture(_BA.BOSS_BANNER_MIN_TIER) and _green(bt) > 0,
		"зелёных %d" % _green(bt))
	var sp: Array = _SB.spec(_UCfg.LEGEND_TIER, false, true, 0, 2)
	verdict("A7 знамя легенды орды висит древком на бойце (сдвиг как у штандарта)",
		sp[0] == _BA.goblin_tongue_texture(_UCfg.LEGEND_TIER, false, 2) and is_equal_approx(float(sp[2]),
		_BA.elite_pole_offset_px() * _SB.PIXEL_SIZE))

# ═════════════════════════════════════════════════════════════════════════════
func _squad(kind: String, at: Vector3, n: int, fac: int) -> int:
	var sid: int = GameManager.new_squad(fac, kind)
	for k in range(n):
		var u: Unit = Building.PRELOAD_SCENES[kind].instantiate()
		u.faction = fac
		main.world_add(u)
		u.global_position = Vector3(at.x + float(k % 4) * 0.9, GameManager.get_terrain_height(at.x, at.z), at.z + float(k / 4) * 0.9)
		u.sync_row()
		GameManager.add_to_squad(sid, u)
		u.set_tick(false)
	return sid

func _block_b() -> void:
	print("\n═════ B. ПРЕСТИЖ ЛЕГЕНДЫ ОРДЫ ═════")
	var ut := "goblin_spearman"
	var sid: int = _squad(ut, Vector3(-120, 0, 120), 6, G)
	await pframes(3)
	var top: int = _UCfg.max_veteran_level(ut)
	GameManager.credit_kills(sid, _UCfg.veteran_threshold(ut, top))
	var u0: Unit = (GameManager.squads[sid]["members"] as Array)[0]
	var att0: float = u0.vet_attack
	var t2: int = _UCfg.legend_extra_threshold(ut, 2)
	GameManager.credit_kills(sid, t2 - int(GameManager.squads[sid]["kills"]))
	await pframes(3)
	var sq: Dictionary = GameManager.squads[sid]
	var bn = sq.get("banner")
	verdict("B1 гоблины на легенде копят престиж — знак на штандарте (2 ступени)",
		int(sq["level"]) == top and int(sq.get("legend_extra", 0)) == 2 and bn != null and int(bn.shown_flags) == 2,
		"ранг %d, престиж %d, на знамени %s" % [int(sq["level"]), int(sq.get("legend_extra", 0)),
		str(bn.shown_flags) if bn != null else "-"])
	verdict("B2 престиж орды — только знак, без прибавок", is_equal_approx(u0.vet_attack, att0),
		"атака %.2f → %.2f" % [att0, u0.vet_attack])

# ═════════════════════════════════════════════════════════════════════════════
func _block_c() -> void:
	print("\n═════ C. ОБЩИЙ ОПЫТ ОТДЕЛЬНО ОТ ЛИЧНОГО ═════")
	var rm = GameManager.relic_mgr()
	var sid: int = _squad("spearman", Vector3(-120, 0, 140), 6, F)
	var foe: int = _squad("spearman", Vector3(-120, 0, 160), 1, R)
	await pframes(3)
	var victim = (GameManager.squads[foe]["members"] as Array)[0]
	var p0: float = rm.pool
	GameManager.credit_kills(sid, 10, victim)
	verdict("C1 десять убийств — копилка +%.1f (вдвое медленнее прежнего)" % (10.0 * _RCfg.POOL_PER_KILL),
		is_equal_approx(rm.pool - p0, 5.0) and is_equal_approx(_RCfg.POOL_PER_KILL, 0.5),
		"Δ %.2f" % (rm.pool - p0))
	var top: int = _UCfg.max_veteran_level("spearman")
	GameManager.credit_kills(sid, _UCfg.veteran_threshold("spearman", top) + 5000, victim)
	verdict("C2 личный опыт до легенды и престижа штандарта не даёт",
		int(GameManager.squads[sid]["level"]) == top and not GameManager.squad_elite(sid)
		and rm.relic_of_squad(sid) == null)
	var radii: Array = []
	var inc := true
	for l in range(1, _RCfg.STANDARD_MAX_LEVEL + 1):
		radii.append(_RCfg.aura_radius(l))
		if l > 1:
			inc = inc and _RCfg.aura_radius(l) >= _RCfg.aura_radius(l - 1) + 4.0
	verdict("C3 аура небольшая на первом уровне и растёт существенно (≥ 4 м за ступень)",
		inc and _RCfg.aura_radius(1) <= 10.0 and _RCfg.aura_radius(_RCfg.STANDARD_MAX_LEVEL) >= _RCfg.aura_radius(1) * 4.0,
		str(radii))
