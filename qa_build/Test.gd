extends Node
## ═══════════════════════════════════════════════════════════════════════════
## ЗОНД СБОРКИ: проверяет ассеты ТАМ, ГДЕ ОНИ ЛОМАЮТСЯ — внутри .exe
## ═══════════════════════════════════════════════════════════════════════════
## Запускается ДВАЖДЫ и результаты сравниваются:
##   в редакторе  godot --headless --path . res://qa_build/Test.tscn
##   в сборке     alfa.exe --headless res://qa_build/Test.tscn
## Расхождение любой строки = ассет, который есть в редакторе и пропал в билде.

const _SSParser := preload("res://scripts/SpriteSheetParser.gd")
const _GS       := preload("res://scripts/game_settings.gd")

var _fail := 0

func _ready() -> void:
	call_deferred("_run")

func _chk(title: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_fail += 1
	print("  %s %s%s" % ["OK  " if ok else "FAIL", title,
		("  — " + detail) if detail != "" else ""])

func _run() -> void:
	print("\n===== ЗОНД АССЕТОВ =====")
	print("  окружение: %s" % ("РЕДАКТОР" if OS.has_feature("editor") else "СБОРКА (.exe)"))

	# ── 1. ЛЕНТЫ ЛУЧНИКА: то самое, что превращалось в манекен ──────────────
	for color in ["Blue", "Red"]:
		var dir: String = _GS.unit_folder("humans", color, "archer")
		for f in ["Archer_Idle.png", "Archer_Run.png", "Archer_Shoot.png"]:
			_chk("лучник %s/%s" % [color, f], ResourceLoader.exists(dir.path_join(f)), dir)

	# Реальная сборка кадров — не «файл есть», а «спрайт построился»
	for color2 in ["Blue", "Red"]:
		var d2: String = _GS.unit_folder("humans", color2, "archer")
		var asp := _SSParser.build_sprite_from_map(d2, {
			"idle": "Archer_Idle.png", "walk": "Archer_Run.png",
			"attack": "Archer_Shoot.png"})
		var frames: int = 0
		if asp != null and asp.sprite_frames != null:
			frames = asp.sprite_frames.get_frame_count("idle")
		_chk("лучник %s: кадры idle собраны" % color2, frames > 0, "кадров %d" % frames)
		if asp != null:
			asp.queue_free()

	# ── 1б. СТАРЫЙ СПОСОБ (скан каталога) — ДИАГНОСТИКА, НЕ ВЕРДИКТ ─────────
	# Ради этого зонд и писался: надо доказать, что лучник ломался ИМЕННО из-за
	# перечисления каталога, а не по другой причине. Здесь только печатаем факт
	var dbg: String = _GS.unit_folder("humans", "Blue", "archer")
	var dir_ok := DirAccess.open(dbg)
	var listed: Array = []
	if dir_ok != null:
		dir_ok.list_dir_begin()
		var fn: String = dir_ok.get_next()
		while fn != "" and listed.size() < 8:
			if not dir_ok.current_is_dir():
				listed.append(fn)
			fn = dir_ok.get_next()
		dir_ok.list_dir_end()
	print("  [диагностика] DirAccess.open: %s; каталог видит: %s"
		% ["есть" if dir_ok != null else "НЕТ", str(listed)])
	var scanned := _SSParser.build_animated_sprite(dbg)
	var sc_frames: int = 0
	if scanned != null and scanned.sprite_frames != null:
		sc_frames = scanned.sprite_frames.get_frame_count("idle")
	print("  [диагностика] СТАРЫЙ путь (скан каталога) собрал кадров idle: %d" % sc_frames)
	if scanned != null:
		scanned.queue_free()
	# Кэш парсера чистим: диагностика не должна влиять на остальные проверки
	_SSParser.clear_cache()

	# ── 2. ИНТЕРФЕЙС: папка «menu ui» (регистр!) ────────────────────────────
	var ui := "res://assets/environment/menu ui"
	for f2 in ["Cursor_01.png", "BigBar_Base.png", "SmallBar_Fill.png"]:
		_chk("UI %s" % f2, ResourceLoader.exists(ui.path_join(f2)))
	var cur := _UIA.cursor(1)
	_chk("UI: курсор реально построен", cur != null)
	var bar := _UIA.big_bar_base()
	_chk("UI: полоса HP реально построена", bar != null)

	# ── 3. ОСТАЛЬНЫЕ ЮНИТЫ (контроль: они и раньше работали) ───────────────
	var probes := {
		"spearman": "Lancer_Idle.png",
		"worker":   "Pawn_Idle.png",
		"warrior":  "Warrior_Idle.png",
		"monk":     "Idle.png",
	}
	for uid in probes:
		var d3: String = _GS.unit_folder("humans", "Blue", String(uid))
		_chk("юнит %s" % uid, _SSParser.folder_has(d3, String(probes[uid])), d3)

	# ── 4. ЗДАНИЯ И ЗВУК ────────────────────────────────────────────────────
	for b in ["castle", "barracks", "smithy", "mine", "house"]:
		var p: String = _GS.building_sprite("humans", "Blue", String(b))
		_chk("здание %s" % b, ResourceLoader.exists(p), p)

	print("  ── ПРОВАЛОВ: %d ──" % _fail)
	print("===== ЗОНД ЗАВЕРШЁН =====\n")
	get_tree().quit(1 if _fail > 0 else 0)

const _UIA := preload("res://scripts/UIAssets.gd")
