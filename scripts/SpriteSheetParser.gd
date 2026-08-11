extends RefCounted
class_name SpriteSheetParser

## Сканирует папку с горизонтальными спрайт-шитами и строит AnimatedSprite3D.
## Ожидаемые суффиксы: _Idle-Sheet, _Walk-Sheet, _Run-Sheet,
##   _Attack-Sheet / _Shoot-Sheet, _Death-Sheet, _Hurt-Sheet
## Кадры — квадратные (ширина / высота = количество кадров).
## Работает без .import-метаданных Godot — грузит PNG напрямую через Image.load().
##
## КЭШ (критично для фриза при найме отряда). Раньше КАЖДЫЙ юнит при
## instantiate() заново сканировал папку через DirAccess и читал PNG с диска
## через Image.load() — заказ отряда 20 копейщиков означал ~160 чтений файлов
## в одном кадре. Теперь текстуры и готовый SpriteFrames строятся ОДИН раз на
## папку и переиспользуются: SpriteFrames — обычный ресурс, несколько
## AnimatedSprite3D спокойно делят его (кадр/скорость проигрывания у каждого
## узла свои). Спавн второго и последующих юнитов диск больше не трогает.

static var _frames_cache: Dictionary = {}   # ключ папки/карты → SpriteFrames
static var _tex_cache:    Dictionary = {}   # res-путь PNG      → ImageTexture

## Сбросить кэш (например, при смене фракции). В обычной игре не нужен.
static func clear_cache() -> void:
	_frames_cache.clear()
	_tex_cache.clear()
	_probe_cache.clear()

# ═════════════════════════════════════════════════════════════════════════════
# ЕСТЬ ЛИ НАБОР СПРАЙТОВ В ЭТОЙ ПАПКЕ — ПРОВЕРКА ПО ФАЙЛУ, НЕ ПО КАТАЛОГУ
#
# Раньше все юниты спрашивали `DirAccess.open(folder) != null`. В экспортной
# сборке это ненадёжно: каталог в .pck существует лишь постольку, поскольку в
# нём лежат ресурсы, а лежат там не исходные .png, а перенаправители .remap и
# готовые .ctex в res://.godot/imported/. Ответ такой пробы зависит от того,
# как именно упакован проект, — то есть от вещей, которые из игры не видны.
#
# ResourceLoader.exists() ходит через ТУ ЖЕ таблицу перенаправления, что и
# load(), поэтому отвечает одинаково в редакторе и в .exe. Пробуем конкретный
# файл, который у набора обязан быть (обычно лента idle).
#
# Кэш обязателен: проба зовётся на КАЖДОМ спавне юнита, а найм отряда — это
# два десятка спавнов в одном кадре.
# ═════════════════════════════════════════════════════════════════════════════
static var _probe_cache: Dictionary = {}

static func folder_has(folder_path: String, probe_file: String) -> bool:
	if folder_path.is_empty():
		return false
	var full: String = folder_path.path_join(probe_file)
	if _probe_cache.has(full):
		return _probe_cache[full]
	var ok: bool = ResourceLoader.exists(full)
	_probe_cache[full] = ok
	return ok

## ПЕРЕЧИСЛЕНИЕ КАТАЛОГА — ТОЛЬКО ЗАПАСНОЙ ПУТЬ, НЕ ОСНОВНОЙ.
##
## В экспортной сборке исходных .png в пакете нет: импортёр кладёт готовую
## текстуру в res://.godot/imported/<имя>.png-<хэш>.ctex, а на месте исходника
## оставляет перенаправитель <имя>.png.remap. Перечисление каталога поэтому
## возвращает имена с ХВОСТОМ, а не «...png», и наивная проверка расширения не
## находит ничего. Именно на этом лучник в собранном .exe превращался в
## процедурную заглушку, пока остальные юниты (у них явные карты имён) работали.
##
## Хвост здесь снимается, так что скан переживает и сборку, — но полагаться на
## него как на ОСНОВНОЙ способ загрузки нельзя: он зависит от того, как упакован
## проект. Новый юнит обязан перечислять свои ленты поимённо через
## build_sprite_from_map (см. Archer.SHEETS_COLOR).
static func build_animated_sprite(folder_path: String) -> AnimatedSprite3D:
	if _frames_cache.has(folder_path):
		var cached: SpriteFrames = _frames_cache[folder_path]
		return _make_sprite(cached) if cached != null else null

	var dir := DirAccess.open(folder_path)
	if dir == null:
		_frames_cache[folder_path] = null      # запоминаем и промах: папки нет
		return null

	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	var found_any := false
	var seen: Dictionary = {}                  # один и тот же лист дважды не берём

	dir.list_dir_begin()
	var filename: String = dir.get_next()
	while filename != "":
		if not dir.current_is_dir():
			# В редакторе имя приходит как «Archer_Idle.png», в сборке — как
			# «Archer_Idle.png.remap». Снимаем служебный хвост и работаем с
			# исходным именем: по нему load() найдёт ресурс в обоих случаях
			var clean: String = filename
			for tail in [".remap", ".import"]:
				if clean.ends_with(tail):
					clean = clean.substr(0, clean.length() - tail.length())
			if clean.ends_with(".png") and not seen.has(clean):
				seen[clean] = true
				var anim: String = _detect_anim(clean)
				if anim != "":
					var full: String = folder_path.path_join(clean)
					var tex := _load_texture(full)
					if tex != null:
						_add_frames(frames, anim, tex)
						found_any = true
		filename = dir.get_next()
	dir.list_dir_end()

	if not found_any or not frames.has_animation("idle"):
		_frames_cache[folder_path] = null
		return null

	_frames_cache[folder_path] = frames
	return _make_sprite(frames)

## Общая обвязка узла: параметры билборда одинаковы для всех юнитов,
## разный только (кэшированный) SpriteFrames.
static func _make_sprite(frames: SpriteFrames) -> AnimatedSprite3D:
	var asp := AnimatedSprite3D.new()
	asp.sprite_frames = frames
	asp.billboard     = BaseMaterial3D.BILLBOARD_FIXED_Y
	# Discard: запись глубины, нет мерцания сортировки в плотном строю
	asp.alpha_cut     = SpriteBase3D.ALPHA_CUT_DISCARD
	# 0.008 * 1.35: единый масштаб юнитов +35% (Unit.UNIT_SCALE)
	asp.pixel_size    = 0.0108
	# Центр кадра на 0.42 — ноги персонажа на земле y=0 (Unit.SPRITE_BASE_Y)
	asp.position.y    = 0.42
	asp.play("idle")
	return asp

## Собирает AnimatedSprite3D из явной карты {имя_анимации: имя_файла.png}.
## Используется для Pawn (инструменты/переноска) и Warrior (attack1/attack2).
## no_loop — список анимаций, которые проигрываются один раз (удары).
static func build_sprite_from_map(folder_path: String, anim_files: Dictionary, no_loop: Array = []) -> AnimatedSprite3D:
	# Ключ кэша включает карту анимаций: у Pawn и Warrior разные наборы файлов
	var cache_key: String = folder_path + "|" + str(anim_files) + "|" + str(no_loop)
	if _frames_cache.has(cache_key):
		var cached: SpriteFrames = _frames_cache[cache_key]
		return _make_sprite(cached) if cached != null else null

	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	var found := false
	for anim in anim_files:
		var fname: String = anim_files[anim]
		var tex := _load_texture(folder_path.path_join(fname))
		if tex == null:
			continue
		_add_frames(frames, anim, tex)
		found = true
	if not found or not frames.has_animation("idle"):
		_frames_cache[cache_key] = null
		return null
	for anim in no_loop:
		if frames.has_animation(anim):
			frames.set_animation_loop(anim, false)
	_frames_cache[cache_key] = frames
	return _make_sprite(frames)

## Загружает текстуру: сначала через ResourceLoader (если файл уже импортирован),
## затем напрямую через Image.load() (работает без .import-метаданных).
## Результат кэшируется по пути: повторный спавн юнита диск не читает.
static func _load_texture(res_path: String) -> ImageTexture:
	if _tex_cache.has(res_path):
		return _tex_cache[res_path]
	var result: ImageTexture = _load_texture_uncached(res_path)
	_tex_cache[res_path] = result    # null тоже кэшируем — не искать файл снова
	return result

static func _load_texture_uncached(res_path: String) -> ImageTexture:
	# Попытка 1: обычный ResourceLoader (файл уже в кэше Godot)
	if ResourceLoader.exists(res_path):
		var tex := load(res_path) as Texture2D
		if tex != null:
			var img := tex.get_image()
			if img != null:
				return ImageTexture.create_from_image(img)

	# Попытка 2: прямая загрузка PNG через Image (обходит систему импорта).
	# Наличие файла проверяем ЗАРАНЕЕ: Image.load() на отсутствующем пути печатает
	# в консоль ERROR движка, а промах здесь — штатное дело (не во всех цветовых
	# наборах есть все ленты, напр. Pawn_Run_Stone.png только у чёрных)
	if not FileAccess.file_exists(res_path):
		return null
	var abs_path: String = ProjectSettings.globalize_path(res_path)
	var img := Image.new()
	if img.load(abs_path) == OK:
		return ImageTexture.create_from_image(img)

	return null

static func _add_frames(frames: SpriteFrames, anim: String, tex: ImageTexture) -> void:
	var img := tex.get_image()
	if img == null:
		return
	var frame_h: int = img.get_height()
	if frame_h <= 0:
		return
	var frame_count: int = img.get_width() / frame_h
	if frame_count <= 0:
		frame_count = 1

	if not frames.has_animation(anim):
		frames.add_animation(anim)
		frames.set_animation_speed(anim, _default_fps(anim))
		frames.set_animation_loop(anim, anim != "death")

	for i in range(frame_count):
		var atlas := AtlasTexture.new()
		atlas.atlas  = tex
		atlas.region = Rect2(i * frame_h, 0, frame_h, frame_h)
		frames.add_frame(anim, atlas)

static func _detect_anim(filename: String) -> String:
	var stem: String = filename.get_basename().to_lower()
	if "_idle"   in stem: return "idle"
	if "_walk"   in stem: return "walk"
	if "_run"    in stem: return "walk"
	if "_guard"  in stem: return "guard"
	if "_attack" in stem: return "attack"
	if "_shoot"  in stem: return "attack"
	if "_death"  in stem: return "death"
	if "_hurt"   in stem: return "hurt"
	return ""

static func _default_fps(anim: String) -> float:
	if anim.begins_with("carry"):  return 10.0   # переноска = темп ходьбы
	if anim.begins_with("attack"): return 10.0   # attack, attack1, attack2
	match anim:
		"idle":    return 6.0
		"walk":    return 10.0
		"death":   return 8.0
		"hurt":    return 8.0
		"chop":    return 8.0    # рубка топором
		"mine":    return 8.0    # удары киркой
		"harvest": return 8.0    # нож (еда)
	return 8.0
