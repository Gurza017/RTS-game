extends RefCounted
## ═══════════════════════════════════════════════════════════════════════════
## ТЕЛА ПАВШИХ: ОДИН MultiMesh НА ЛЕНТУ, НИ ОДНОГО УЗЛА НА ТРУП
## ═══════════════════════════════════════════════════════════════════════════
## Труп — это ДЕКОРАЦИЯ, а не юнит. У него нет ни строки в ядре армии, ни
## состояния, ни цели, ни физического тика: он не попадает ни в _live_units,
## ни в пространственную сетку, ни в пакетное расталкивание — потому что
## заводится он ПОСЛЕ того, как боец снял с себя всё это в _die(), и заводится
## не узлом дерева, а слотом в общем буфере.
##
## Почему не узел. В свалке гибнут сотнями за десяток секунд; узел на труп —
## это узел, трансформ и вызов отрисовки на каждого павшего, ровно та статья
## расхода, ради которой в этом проекте уже вынесены в MultiMesh и дальние
## бойцы, и кольца выделения, и полоски здоровья, и растительность.
##
## Устройство скопировано с FarUnitRenderer намеренно, до имён полей: бакет на
## ленту (лента + число кадров + размер пикселя), теневая копия буфера, одна
## подача set_buffer на бакет за кадр. Отличий три.
##
## 1. ТРУП ЛЕЖИТ, А НЕ СТОИТ. Живой боец — билборд, всегда лицом к камере;
##    лежащий развёрнут так, как упал. Поэтому у него свой шейдер без
##    билборда (mm_corpse.gdshader), а базис трансформа кладёт квад плашмя на
##    грунт и крутит вокруг вертикали на свой угол.
##
## 2. ТРУП НЕ ДВИЖЕТСЯ. Записал один раз при спавне — и до самого исчезновения
##    в буфер никто не пишет. Покадровая работа здесь есть ровно у тех, кто
##    прямо сейчас РАСТВОРЯЕТСЯ (их единицы), и её нет вовсе, пока не растёт
##    никто: поле в тысячу трупов не стоит ни одной операции в кадр.
##
## 3. ЛИМИТ И ВЫТЕСНЕНИЕ. Трупов не может стать больше MAX_CORPSES; при
##    переполнении САМЫЙ СТАРЫЙ начинает гаснуть и, догорев, освобождает слот.
##    Гаснет, а не пропадает: труп, исчезающий мгновенно у игрока на глазах,
##    читается как ошибка отрисовки.
##
## Крови и ран здесь нет намеренно — задание первой очереди этого не
## предусматривает. Труп рисуется ТЕМ ЖЕ кадром той же ленты, каким боец был в
## последний свой миг: отдельный арт для павших не нужен.
##
## Владелец — GameManager (как far_units/sel_decals/hp_bars): RefCounted не
## может сам быть узлом дерева, MultiMeshInstance3D добавляется в мир через
## переданный world_root.

const _SHADER := preload("res://shaders/mm_corpse.gdshader")
const _Opt := preload("res://scripts/perf_config.gd")
const _GobCfgCR := preload("res://scripts/goblin/goblin_config.gd")
const _ArrowC := preload("res://scripts/Arrow.gd")
const _Vis := preload("res://scripts/units/UnitVisuals.gd")
const _UCfgC := preload("res://scripts/unit_stats_config.gd")

const GROW_STEP := 512

## ПОТОЛОК ЧИСЛА ТЕЛ НА ПОЛЕ. Заказан владельцем: пять тысяч.
##
## ПОЧЕМУ ЭТО НЕ СТОИТ КАДРА. Тело — это шестнадцать float в буфере бакета и
## НИ ОДНОГО узла; лежащее тело не считает ничего вовсе (см. update). Пять
## тысяч квадов лежат в тех же MultiMeshInstance3D, что и пятьсот, — число
## вызовов отрисовки от потолка не зависит совсем, оно равно числу РАЗНЫХ ЛЕНТ
## на поле (см. bucket_count), а лент на карте единицы.
##
## Единственная статья, которая от потолка растёт, — подача буфера в
## RenderingServer: set_buffer гонит бакет ЦЕЛИКОМ, и на пяти тысячах тел это
## 320 КБ. Поэтому запись растворения загрублена по времени
## (DISSOLVE_WRITE_STEP): полностью неподвижное поле не подаёт буфер вовсе, а
## растворяющееся — десять раз в секунду вместо шестидесяти
const MAX_CORPSES := 5000

## ── СКОЛЬКО ТЕЛО ЛЕЖИТ ЦЕЛЫМ И СКОЛЬКО РАСТВОРЯЕТСЯ ────────────────────────
## Заказ владельца: пятнадцать минут при полной видимости, затем полминуты
## медленного разложения. Разложение — это НЕ просто прозрачность: тело сперва
## землеет и темнеет (шейдер считает это из той же доли, см. mm_corpse), и лишь
## потом рассыпается дизером. Поле боя после большой рубки должно выглядеть
## заброшенным, а не мигающим.
const LIFE_SEC := 900.0
const DISSOLVE_SEC := 30.0

## Сколько секунд длится растворение ВЫТЕСНЕННОГО тела (перебор потолка).
## Короткое намеренно и к сроку жизни отношения не имеет: вытеснение случается
## только когда поле уже забито под завязку, и слот там нужен следующему
## павшему прямо сейчас, а не через полминуты
const FADE_SEC := 2.0

## Как часто доля растворения уезжает в буфер. Растворение длится тридцать
## секунд — десяти записей в секунду хватает с большим запасом, а подача
## буфера при этом идёт вшестеро реже (см. разбор у MAX_CORPSES)
const DISSOLVE_WRITE_STEP := 0.1

## Сколько снятых мест накапливаем, прежде чем уплотнить очередь. Erase по
## значению стоит прохода по всему списку, и на пяти тысячах тел это заметно;
## уплотнение делает ровно один такой проход на пачку снятых
const COMPACT_MIN := 32

## На сколько труп приподнят над грунтом. Меньше сантиметра было бы мало:
## рельеф считается по той же формуле, но в ДРУГОЙ точке (труп занимает метр с
## лишним), и край квада уходил бы под землю на склоне
const GROUND_LIFT := 0.05

## ── СТУПЕНЬКА ВЫСОТЫ: ЗАВАЛ НЕ ДОЛЖЕН ДРОЖАТЬ ──────────────────────────────
## Тела непрозрачны, порядок им решает буфер глубины — но два тела, легшие
## РОВНО на одной высоте, дают классический z-fighting: на общих пикселях
## побеждает то одно, то другое, и куча мигает.
##
## Поэтому каждое следующее тело ложится на волосок выше предыдущего. Номер
## берётся из счётчика и закрепляется за телом НАВСЕГДА: сортировка внутри
## завала перестаёт зависеть и от камеры, и от того, кто умер позже.
## Шаг ЗАМЕТНО меньше миллиметра, ступенька из 64 тел — шесть сантиметров:
## глазом не видно, буферу глубины хватает с запасом
const LAYER_STEP := 0.001
const LAYER_WRAP := 64

## ── ЗАТЕМНЕНИЕ НИЖНИХ СЛОЁВ ЗАВАЛА ─────────────────────────────────────────
## Заказ владельца: куча обязана читаться объёмом, а не ковром. Тело, на
## которое легли сверху, притеняется — ровно так, как притенило бы его то, что
## лежит выше. Считается ОДИН РАЗ при укладке и больше не меняется, поэтому
## уезжает в буфер числом (альфа instance-цвета).
##
## Глубина берётся не «сколько тел рядом» (это был бы скан на каждую смерть), а
## по СВОЕЙ ступеньке высоты: она и так означает «сколько тел легло до меня в
## этом круге» (см. LAYER_STEP). Тело с номером 0 — самое нижнее в текущем
## обороте счётчика, с номером LAYER_WRAP-1 — самое верхнее.
##
## Диапазон узкий намеренно: 0.62 внизу против единицы наверху. Шире — и нижние
## тела уходят в черноту, то есть возвращается ровно та «чёрная клякса», от
## которой лечили тени
const TINT_DARKEST := 0.62

## ── РАЗНОКАЛИБЕРНОСТЬ ТЕЛ ──────────────────────────────────────────────────
## Заказ владельца: тела не должны выглядеть штампованными клонами. Угол уже
## разбросан на ±45° (COFFIN_SPREAD), но при одной и той же ленте, одном кадре
## покоя и одном размере завал всё равно читается как повторённая наклейка.
## Самый дешёвый и самый заметный разброс — РАЗМЕР: он вписывается прямо в
## базис трансформа, то есть не стоит ни байта сверх уже записываемых.
## ±7% — это разница в росте между рослым и невысоким, а не карикатура
const SIZE_JITTER := 0.07

## ── СТРЕЛА В ТЕЛЕ РОВНО ОДНА ────────────────────────────────────────────────
## Пересмотр заказа владельца: раньше держали одну-две при одиночном попадании
## и две-три при залпе, и «недостающие» приходилось РОЖДАТЬ отдельными узлами
## из пула (GameManager.spawn_stuck_arrow). Цена этого выяснилась на завале:
## каждая торчащая стрела — это узел со СВОИМ QuadMesh и СВОИМ ShaderMaterial,
## то есть отдельный вызов отрисовки. Пятьсот тел по три стрелы — полторы
## тысячи вызовов на одну декорацию, и кадр в свалке проседал вдвое.
##
## Теперь правило простое и без развилок: убит стрелой — в теле остаётся ТА
## САМАЯ стрела, которая его убила, одна. Убит в рукопашной — стрел нет вовсе,
## и это получается само собой, потому что втыкать их некому
const MAX_ARROWS_PER_CORPSE := 1

## ── РАЗБРОС УГЛА ЛЕЖАЩЕГО ТЕЛА ─────────────────────────────────────────────
## На сколько тело может отклониться от «строго поперёк экрана». 45 градусов —
## это заказанные «набок или по диагонали»: при большем разбросе часть тел
## снова начнёт читаться как стоящие (см. разбор в spawn)
const COFFIN_SPREAD := PI * 0.25

## Куда смотрит «вправо по экрану» в мировых координатах. Берётся у активной
## камеры: её в этой игре можно поворачивать, и зашитая константа развернула бы
## все тела не туда на первом же обороте вида.
##
## Камеры нет (headless-стенд без вида) — отвечаем нулём: тела лягут по оси X,
## что для замера ничем не хуже
static func _screen_side_yaw(world_root: Node3D) -> float:
	if world_root == null:
		return 0.0
	var vp := world_root.get_viewport()
	if vp == null:
		return 0.0
	var cam := vp.get_camera_3d()
	if cam == null:
		return 0.0
	var rgt: Vector3 = cam.global_transform.basis.x
	rgt.y = 0.0
	if rgt.length_squared() < 0.0001:
		return 0.0
	rgt = rgt.normalized()
	# yaw задан так, что локальный +Y квада смотрит в (sin, 0, -cos):
	# приравниваем это направление к экранному «вправо»
	return atan2(rgt.x, -rgt.z)

## ── ТЕНЬ ПОД ТЕЛОМ: ОДНО ТУГОЕ ПЯТНО, КРУГЛОЕ И НЕПОДВИЖНОЕ ────────────────
## Овальная тень, которую носит СТОЯЩИЙ боец, лежащему не годится: она рисуется
## под ногами, и у тела оказывалась сбоку, «между ног». Стоящую снимать не
## пришлось — её носит только ВЫДЕЛЕННЫЙ боец, а выделение уходит вместе с ним
## (Unit._exit_tree → sel_decals.unregister).
##
## Здесь была тень «по габариту тела»: овал, вытянутый вдоль его оси и
## ПОВЁРНУТЫЙ вместе с ним, размером 0.55 квада. На человеческом листе 320x320
## при pixel_size 0.0108 квад — это 3.46 м, то есть пятно выходило почти
## двухметровым: рисунок бойца занимает в квадре меньше трети, всё остальное —
## пустота вокруг спрайта. Пятьсот таких полупрозрачных блинов внахлёст давали
## и муть на завале, и честную перерисовку в несколько экранов.
##
## Теперь пятно ТУГОЕ и КРУГЛОЕ:
##   • круглое — потому что тень на земле не переворачивается вслед за
##     рисунком. Овал, повёрнутый по оси лежащего, как раз и читался как
##     «тень стоит, хотя тело лежит»;
##   • тугое — 0.26 квада вместо 0.55, вчетверо меньше по площади.
##
## ПОЧЕМУ НЕ ЕЩЁ ТУЖЕ. Пробовали 0.15 — размер того овала, что впечатан в сам
## арт под ступнями. На экране его не оказалось вовсе: тело лежит НАД своей
## тенью и целиком её закрывает, потому что фигура на квадре занимает примерно
## метр в длину и полметра в ширину, а пятно выходило вдвое меньше. Тень видна
## ровно настолько, насколько она ВЫСТУПАЕТ из-под тела, и 0.26 (около 0.9 м у
## человека) даёт по краям тот самый ободок, от которого завал перестаёт
## выглядеть наклейкой на траве.
const SHADOW_FRAC := 0.26
## На сколько тень лежит НИЖЕ тела: она обязана быть под ним, а не спорить с
## ним за одни и те же пиксели глубины
const SHADOW_DROP := 0.004


class Bucket:
	## 12 float трансформа + 4 float цвета (TRANSFORM_3D + use_colors)
	const STRIDE := 16

	var mmi: MultiMeshInstance3D
	var mm: MultiMesh
	var free: Array = []
	var capacity: int = 0
	var buf: PackedFloat32Array = PackedFloat32Array()
	var dirty: bool = false
	## Мокрый бакет настроен (полоса фигуры и доля погружения в материале)
	var wet_ready: bool = false
	## Подтон стороны поставлен в материал (ТЗ 23.10.2026, п. 7)
	var tint_set: bool = false
	## Мягкость ступени затемнения кучи (см. _tone_k), считается при создании
	var tone_k: float = 1.0
	## Род тела для палитры кучи: goblin / big / blue / red (см. CORPSE_PALETTES)
	var kind: String = ""
	var faction: int = -1

	## ВСЕ ЗАПИСИ В БУФЕР — ТОЛЬКО ЗДЕСЬ. Packed-массивы в GDScript копируются
	## при записи снаружи владельца (та же оговорка и с тем же обоснованием
	## стоит в FarUnitRenderer.Bucket)
	func grow(step: int) -> void:
		var new_cap: int = capacity + step
		buf.resize(new_cap * STRIDE)
		for i in range(capacity, new_cap):
			free.append(i)
		mm.instance_count = new_cap
		capacity = new_cap
		dirty = true

	## Полная запись тела. yaw — поворот вокруг вертикали, alpha — доля
	## непрозрачности.
	##
	## БАЗИС КЛАДЁТ КВАД ПЛАШМЯ. QuadMesh лежит в плоскости XY лицом к +Z;
	## чтобы он лёг на грунт, его нормаль (локальный +Z) обязана смотреть в
	## мировой верх. Столбцы базиса: X = (cos, 0, sin), Y = (sin, 0, -cos),
	## Z = (0, 1, 0) — именно в таком знаке, иначе определитель отрицателен и
	## картинка выходит зеркальной сверх той зеркальности, что задаёт mirror.
	## В буфер матрица идёт ПОСТРОЧНО, поэтому строки собраны из столбцов
	func write(idx: int, pos: Vector3, yaw: float, frame: int,
			mirror: bool, alpha: float, tint: float = 1.0,
			scl: float = 1.0) -> void:
		var c: float = cos(yaw) * scl
		var s: float = sin(yaw) * scl
		var o: int = idx * STRIDE
		buf[o]      = c
		buf[o + 1]  = s
		buf[o + 2]  = 0.0
		buf[o + 3]  = pos.x
		buf[o + 4]  = 0.0
		buf[o + 5]  = 0.0
		buf[o + 6]  = 1.0
		buf[o + 7]  = pos.y
		buf[o + 8]  = s
		buf[o + 9]  = -c
		buf[o + 10] = 0.0
		buf[o + 11] = pos.z
		buf[o + 12] = float(frame) / 255.0
		buf[o + 13] = 1.0 if mirror else 0.0
		buf[o + 14] = alpha
		# Яркость слоя (см. mm_corpse.gdshader): нижние тела притенены
		buf[o + 15] = tint
		dirty = true

	## Единственное, что меняется у уже лежащего тела, — его непрозрачность
	func write_alpha(idx: int, alpha: float) -> void:
		buf[idx * STRIDE + 14] = alpha
		dirty = true

	func hide_slot(idx: int) -> void:
		var o: int = idx * STRIDE
		for i in range(STRIDE):
			buf[o + i] = 0.0
		dirty = true

	func hide_all() -> void:
		for i in range(buf.size()):
			buf[i] = 0.0
		dirty = true

	func flush() -> void:
		if not dirty:
			return
		dirty = false
		if capacity > 0:
			mm.set_buffer(buf)


## Одно тело. Класс, а не словарь: перебор идёт по всем гаснущим в кадре
class Corpse:
	var bucket: Bucket
	var index: int
	## Секунд осталось гаснуть. Отрицательное — не гаснет вовсе (лежит)
	var fade_left: float = -1.0
	## Сколько всего длится ЭТО растворение. Их два разных: штатное разложение
	## по сроку жизни (DISSOLVE_SEC) и спешное вытеснение по потолку (FADE_SEC).
	## Доля в буфер считается от своей длительности, иначе вытесненное тело
	## прыгало бы на пятнадцатую долю сразу
	var fade_total: float = 1.0
	## Когда тело легло, по часам слоя. По нему и только по нему считается срок
	## жизни: абсолютное время движка на паузе идёт, а часы слоя стоят
	var born: float = 0.0
	## Доля, УЖЕ отданная в буфер. Растворение пишется загрублённо (см.
	## DISSOLVE_WRITE_STEP), и без этого поля пришлось бы держать отдельный
	## таймер на каждое гаснущее тело
	var sent: float = 1.0
	## Как тело легло. В буфере эти же числа лежат размазанными по матрице и
	## обратно из неё не читаются: держим их полем, иначе проверить «каждое
	## тело лежит по-своему» можно было бы только разбором сырого буфера
	var yaw: float = 0.0
	var mirror: bool = false
	## Своя высота над грунтом, навсегда закреплённая (см. LAYER_STEP)
	var lift: float = 0.0
	## Яркость тела (см. TINT_DARKEST). Закрепляется навсегда вместе с высотой
	var tint: float = 1.0
	## Свой размер (см. SIZE_JITTER)
	var scl: float = 1.0
	## Где тело лежит. Нужно стрелам: они втыкаются В ТУЛОВИЩЕ, а не туда, где
	## их застало попадание, — иначе они висят рядом с телом или под ним
	var pos: Vector3 = Vector3.ZERO
	## Кадр ленты, которым тело записано (перезапись при переносе лежащего)
	var frame: int = 0
	## Место в слое теней и поперечник круглого пятна
	var shadow_index: int = -1
	var shadow_size: float = 0.0
	## Стрелы, оставшиеся в этом теле. Растворяются ВМЕСТЕ с ним: стрела,
	## пережившая тело и повисшая в воздухе, — заметнее любой экономии
	var arrows: Array = []
	## ── ЧЬЁ ТЕЛО (письмо 12, воскрешение) ──────────────────────────────
	## Сторона, род войск и отряд павшего: по ним монах ищет, кого поднять,
	## и куда вернуть поднятого. raisable — люди игрока и ИИ; орда и её
	## звери не поднимаются
	var faction: int = -1
	var unit_id: String = ""
	var squad_id: int = 0
	var raisable: bool = false
	## Какой монах ведёт канал над телом (instance id, 0 — никто). ТЗ
	## 24.09.2026, п. 12: три монаха брали ОДНО тело — поднимал первый, двое
	## тратили канал и откат впустую, и подъём «останавливался»
	var claimed_by: int = 0


## ── СЛОЙ ТЕНЕЙ: ОДИН НА ВСЕ ТЕЛА ───────────────────────────────────────────
## Бакетов ему не нужно: тень у всех одна и та же картинка, отличается только
## размером — а размер это масштаб в трансформе. Поэтому здесь простой слой с
## одним свободным списком, как у колец выделения (SelectionDecalRenderer)
class ShadowLayer:
	## Только трансформ, без цвета: 3x4 матрица построчно
	const STRIDE := 12

	var mmi: MultiMeshInstance3D
	var mm: MultiMesh
	var free: Array = []
	var capacity: int = 0
	var buf: PackedFloat32Array = PackedFloat32Array()
	var dirty: bool = false

	func grow(step: int) -> void:
		var new_cap: int = capacity + step
		buf.resize(new_cap * STRIDE)
		for i in range(capacity, new_cap):
			free.append(i)
		mm.instance_count = new_cap
		capacity = new_cap
		dirty = true

	## Тень кладётся плашмя и НЕ ПОВОРАЧИВАЕТСЯ вместе с телом: она круглая,
	## поворачивать в ней нечего (см. разбор у SHADOW_FRAC). Базис здесь тот же,
	## что у тела в Bucket.write при yaw = 0, только с масштабом `size`
	func write(idx: int, pos: Vector3, size: float) -> void:
		var o: int = idx * STRIDE
		buf[o]      = size
		buf[o + 1]  = 0.0
		buf[o + 2]  = 0.0
		buf[o + 3]  = pos.x
		buf[o + 4]  = 0.0
		buf[o + 5]  = 0.0
		buf[o + 6]  = 1.0
		buf[o + 7]  = pos.y
		buf[o + 8]  = 0.0
		buf[o + 9]  = -size
		buf[o + 10] = 0.0
		buf[o + 11] = pos.z
		dirty = true

	## Растворения у тени нет: она СЖИМАЕТСЯ вместе с телом. Прозрачность
	## пришлось бы гнать instance-цветом, а StandardMaterial3D его не читает —
	## ради одного пятна заводить свой шейдер незачем
	func write_size(idx: int, size: float) -> void:
		var o: int = idx * STRIDE
		write(idx, Vector3(buf[o + 3], buf[o + 7], buf[o + 11]), size)

	func hide_slot(idx: int) -> void:
		var o: int = idx * STRIDE
		for i in range(STRIDE):
			buf[o + i] = 0.0
		dirty = true

	func flush() -> void:
		if not dirty:
			return
		dirty = false
		if capacity > 0:
			mm.set_buffer(buf)


var _buckets: Dictionary = {}      # ключ ленты -> Bucket
var _shadows: ShadowLayer = null
## Тела В ПОРЯДКЕ ПОЯВЛЕНИЯ: голова очереди — самое старое. Вытеснение по
## лимиту берёт именно оттуда, поэтому очередь, а не множество
var _list: Array = []
## Кто прямо сейчас растворяется. Пока пусто — update() считает один срок
## жизни головы очереди и больше ничего
var _fading: Array = []

## ── ЧАСЫ СЛОЯ ─────────────────────────────────────────────────────────────
## Своё время, а не Time.get_ticks_msec(): на паузе тела обязаны лежать, а не
## доживать свои пятнадцать минут за спиной у игрока. Тикает ровно тем delta,
## который приходит из _process, то есть вместе с миром
var _clock: float = 0.0

## ── ГДЕ ОСТАНОВИЛСЯ ПРОСМОТР СРОКА ЖИЗНИ ──────────────────────────────────
## Очередь _list строго упорядочена по времени укладки, а срок жизни у всех
## один — значит истекает он тоже строго по очереди, и проверять надо ровно
## голову, а не все пять тысяч. Всё, что ЛЕВЕЕ этого указателя, уже растворяется
## или уже снято; на первом же теле, которому рано, просмотр обрывается
var _scan: int = 0

## Сколько мест в _list снято, но ещё не выброшено из массива (см. COMPACT_MIN)
var _dead_slots: int = 0

## Сколько тел заведено за партию. Монотонный: нужен стенду, чтобы отличить
## «труп не появился» от «появился и уже вытеснен»
var spawned_total: int = 0

## Номер слоя для следующего тела (см. LAYER_STEP). Крутится по кругу: важен
## не абсолютный номер, а то, что соседи по времени смерти легли на разной
## высоте, а своя высота у тела больше никогда не меняется
var _layer: int = 0


## Ключ бакета — ровно тот же, что у живых: одна и та же лента в разном
## масштабе обязана попасть в разные бакеты, потому что размер квада вшит в меш
## Доля фигуры под водой: пехота наполовину, великаны (тролль, туша) на треть
const WET_FRAC := 0.50
const WET_FRAC_BIG := 0.32
func _wet_frac(unit: Unit, at: Vector3, ground_y: float) -> float:
	var m = GameManager.main
	if m == null or not m.has_method("water_surface_y") or not m.has_method("in_water_mesh"):
		return 0.0
	if not bool(m.call("in_water_mesh", at.x, at.z)):
		return 0.0
	if float(m.call("water_surface_y", at.x, at.z)) <= ground_y + 0.03:
		return 0.0
	return WET_FRAC_BIG if unit.nav_clearance() >= 3.5 else WET_FRAC

## Полоса фигуры в кадре (доли высоты) — один раз на мокрый бакет
func _setup_wet(b, sheet: Texture2D, frames: int, wet: float, fidx: int = 0) -> void:
	b.wet_ready = true
	var top := 0.0
	var bot := 1.0
	var left := 0.0
	var right := 1.0
	var img: Image = sheet.get_image()
	if img != null:
		if img.is_compressed():
			img.decompress()
		var fw: int = img.get_width() / maxi(frames, 1)
		var h: int = img.get_height()
		var y0 := h
		var y1 := -1
		# Полоса по ШИРИНЕ кадра — по ней теперь идёт линия воды (ТЗ 25.09,
		# п. 2): тело погружается боком вдоль всего туловища
		var x0 := fw
		var x1 := -1
		# Кадр, который РИСУЕТСЯ (у тролля — последний кадр гибели), а не нулевой
		# (ТЗ 29.09.2026, блок 8): полоса фигуры мерилась по стоящей фигуре
		var ox: int = clampi(fidx, 0, maxi(frames - 1, 0)) * fw
		for y in range(0, h, 2):
			for x in range(0, fw, 2):
				if img.get_pixel(ox + x, y).a > 0.3:
					y0 = mini(y0, y)
					y1 = maxi(y1, y)
					x0 = mini(x0, x)
					x1 = maxi(x1, x)
		if y1 > y0:
			top = float(y0) / float(h)
			bot = float(y1 + 1) / float(h)
		if x1 > x0:
			left = float(x0) / float(fw)
			right = float(x1 + 1) / float(fw)
	var mat := (b.mm.mesh as QuadMesh).material as ShaderMaterial
	mat.set_shader_parameter("submerge", wet)
	mat.set_shader_parameter("fig_top", top)
	mat.set_shader_parameter("fig_bot", bot)
	mat.set_shader_parameter("fig_left", left)
	mat.set_shader_parameter("fig_right", right)

## ── ТЕЛА РАЗЛИЧИМЫ ПО СТОРОНАМ (ТЗ 23.10.2026, п. 7) ────────────────────────
## «Сплошная чёрная масса»: тело тускнело (dead_dim 0.74) и уходило в серый
## на 40 % — синие, красные и зелёные павшие сливались в один бурый ковёр.
## Теперь тело светлее и сохраняет цвет своей стороны: серый подмес меньше,
## тёплый «земляной» подтон заменён подтоном стороны (синий у игрока,
## красный у красного ИИ, зелёный у орды). Разложение (бурый тон) — прежнее
const CORPSE_DIM := 0.86
const CORPSE_DESAT := 0.22
const CORPSE_TINTS := {
	Constants.FACTION_PLAYER: Color(0.86, 0.93, 1.0),
	Constants.FACTION_ENEMY: Color(1.0, 0.84, 0.82),
	Constants.FACTION_GOBLIN: Color(0.88, 1.0, 0.80),
}

func _set_faction_tint(b, faction: int, kind: String = "") -> void:
	b.tint_set = true
	b.faction = faction
	b.kind = kind
	_paint_bucket(b)

## ── ПАЛИТРА КУЧИ ТЕЛ (ТЗ 01.11.2026, «оттеночный блицкриг») ─────────────────
## «Скучное серое пятно» на броде: орда ложится тёмно-зелёным ковром, люди в
## нём теряются. Палитра — униформы шейдера тел (mm_corpse): у каждого рода
## три близких подтона (тело берёт свой по хэшу точки), обесцвечивание,
## яркость и подъём тёмных пикселей к подтону (dead_lift); люди бледнее
## массы. Цена кадра — ноль: ни бакетов, ни вызовов отрисовки не прибавилось.
## Индекс 0 — прежний вид (подтон стороны, CORPSE_DIM/CORPSE_DESAT); род без
## своей записи в палитре рисуется так же.
## troll — множитель билборда туши тролля (Troll._leave_corpse, своя отрисовка)
## Переключение в партии — F7 (палитра) и F8 (тень), см. Main._unhandled_input
const CORPSE_PALETTES := [
	{"name": "обычная"},
	# Гибрид раунда 2: «болотный мох», люди бледнее массы
	{"name": "мох (гибрид)",
		"goblin": [[Color(0.78, 0.92, 0.66), Color(0.66, 0.80, 0.62), Color(0.86, 0.90, 0.74)], 0.50, 0.90, 0.40],
		"big": [[Color(0.52, 0.62, 0.56)], 0.55, 0.74, 0.15],
		"blue": [[Color(0.84, 0.90, 0.98)], 0.75, 1.0, 0.65],
		"red": [[Color(0.96, 0.86, 0.84)], 0.75, 1.0, 0.65],
		"troll": Color(0.64, 0.74, 0.66), "water": 0.35},
	# Итог (на базе 3.3 «выжженная степь»): гоблины — серно-жёлтый, олива и
	# рыжий; туши чуть светлее троллей; люди — как в обычной (ключей blue/red
	# нет — _paint_bucket берёт прежний подтон стороны)
	{"name": "степь 3.3 (итог)",
		"goblin": [[Color(1.0, 0.92, 0.55), Color(0.80, 0.90, 0.50), Color(0.96, 0.64, 0.44)], 0.25, 1.0, 0.50],
		"big": [[Color(0.80, 0.70, 0.58)], 0.35, 0.95, 0.35],
		"troll": Color(0.62, 0.50, 0.40), "water": 0.30},
]
## Тень под кучей: [прозрачность центра пятна, множитель размера, имя]; F8
## идёт по кругу 0 → 4 → 0
const CORPSE_SHADOWS := [
	[0.0, 1.0, "нет"],
	[0.20, 1.5, "еле заметная"],
	[0.50, 2.1, "слабая"],
	[0.62, 2.4, "средняя"],
	[0.75, 2.7, "плотная"],
]
const _WATER_MIX_DEFAULT := 0.72
## Множитель пятна, с которым записаны тени (пересчёт при смене уровня)
var _shadow_mult: float = 1.0

static func kind_of(unit: Unit) -> String:
	var id: String = String(unit.stat_id)
	if id.find("troll") >= 0 or id.find("big") >= 0 or id.find("boss") >= 0:
		return "big"
	if int(unit.faction) == Constants.FACTION_GOBLIN:
		return "goblin"
	return "blue" if int(unit.faction) == Constants.FACTION_PLAYER else "red"

func _palette() -> Dictionary:
	return CORPSE_PALETTES[clampi(_Opt.corpse_palette, 0, CORPSE_PALETTES.size() - 1)]

func _paint_bucket(b) -> void:
	var mat := (b.mm.mesh as QuadMesh).material as ShaderMaterial
	if mat == null:
		return
	var pal: Dictionary = _palette()
	var p: Variant = pal.get(b.kind)
	if p == null:
		# Прежний вид: подтон стороны (или серо-бурый ковёр без ручки)
		var on: bool = _Opt.corpse_faction_tint
		mat.set_shader_parameter("dead_dim", CORPSE_DIM if on else 0.74)
		mat.set_shader_parameter("dead_desat", CORPSE_DESAT if on else 0.40)
		mat.set_shader_parameter("dead_tint", CORPSE_TINTS.get(b.faction, Color(1.0, 0.94, 0.86)) if on else Color(1.0, 0.94, 0.86))
		mat.set_shader_parameter("tint_var", 0.0)
		mat.set_shader_parameter("dead_lift", 0.0)
		mat.set_shader_parameter("water_mix", _WATER_MIX_DEFAULT)
		mat.set_shader_parameter("dead_vivid", float(_Opt.corpse_vivid))
		return
	var row: Array = p
	var t: Array = row[0]
	mat.set_shader_parameter("dead_tint", t[0])
	mat.set_shader_parameter("dead_tint2", t[mini(1, t.size() - 1)])
	mat.set_shader_parameter("dead_tint3", t[mini(2, t.size() - 1)])
	mat.set_shader_parameter("tint_var", 1.0 if t.size() > 1 else 0.0)
	mat.set_shader_parameter("dead_desat", float(row[1]))
	mat.set_shader_parameter("dead_dim", float(row[2]))
	mat.set_shader_parameter("dead_lift", float(row[3]))
	mat.set_shader_parameter("water_mix", float(pal.get("water", _WATER_MIX_DEFAULT)))
	mat.set_shader_parameter("dead_vivid", float(_Opt.corpse_vivid))

## Множитель туши тролля под текущую палитру (Troll._leave_corpse)
func troll_modulate() -> Color:
	var cv: Variant = _palette().get("troll")
	var c: Color = cv if cv != null else _GobCfgCR.TROLL_DEATH_TINT
	# Сочность (F9) — по множителю: насыщенность и яркость, как у бакетов
	var v: float = float(_Opt.corpse_vivid)
	if v == 0.0:
		return c
	var l: float = c.r * 0.299 + c.g * 0.587 + c.b * 0.114
	var g := Color(l, l, l)
	var m: Color = g.lerp(c, 1.0 + 0.15 * v) * (1.0 + 0.03 * v)
	return Color(maxf(m.r, 0.0), maxf(m.g, 0.0), maxf(m.b, 0.0), c.a)

func _shadow_row() -> Array:
	return CORPSE_SHADOWS[clampi(_Opt.corpse_shadow, 0, CORPSE_SHADOWS.size() - 1)]

## Перекрасить всё, что уже лежит, под текущие ручки corpse_palette /
## corpse_shadow: бакеты тел, туши троллей и слой теней. Зовётся по смене
## (горячие клавиши), не в кадре
func apply_palette() -> void:
	for k in _buckets:
		var b = _buckets[k]
		if b.tint_set:
			_paint_bucket(b)
	var tm: Color = troll_modulate()
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		for n in tree.get_nodes_in_group(TROLL_CORPSE_GROUP):
			var mi := n as MeshInstance3D
			if mi != null and mi.mesh != null and mi.mesh.surface_get_material(0) is ShaderMaterial:
				(mi.mesh.surface_get_material(0) as ShaderMaterial).set_shader_parameter("modulate", tm)
	_apply_shadow_level()

const TROLL_CORPSE_GROUP := "troll_corpse"

func _apply_shadow_level() -> void:
	var sh: Array = _shadow_row()
	var smat := _Vis.corpse_shadow_mesh().material as StandardMaterial3D
	if smat != null and smat.albedo_texture is GradientTexture2D:
		(smat.albedo_texture as GradientTexture2D).gradient.set_color(0, Color(0.0, 0.0, 0.0, float(sh[0])))
	var m: float = float(sh[1])
	if is_equal_approx(m, _shadow_mult):
		return
	var r: float = m / _shadow_mult
	_shadow_mult = m
	if _shadows == null:
		return
	for cc in _list:
		if cc != null and cc.shadow_index >= 0:
			cc.shadow_size *= r
			_shadows.write_size(cc.shadow_index, cc.shadow_size * cc.sent)
	_shadows.flush()

## Горячие клавиши: следующая палитра / следующий уровень тени. Ответ —
## строка для плашки HUD
func cycle_palette(step: int = 1) -> String:
	_Opt.corpse_palette = posmod(_Opt.corpse_palette + step, CORPSE_PALETTES.size())
	apply_palette()
	return palette_caption()

func cycle_shadow(step: int = 1) -> String:
	_Opt.corpse_shadow = posmod(_Opt.corpse_shadow + step, CORPSE_SHADOWS.size())
	apply_palette()
	return palette_caption()

## Сочность −2…3 по кругу (F9)
func cycle_vivid(step: int = 1) -> String:
	_Opt.corpse_vivid = posmod(_Opt.corpse_vivid + 2 + step, 6) - 2
	apply_palette()
	return palette_caption()

func palette_caption() -> String:
	var pi: int = clampi(_Opt.corpse_palette, 0, CORPSE_PALETTES.size() - 1)
	var si: int = clampi(_Opt.corpse_shadow, 0, CORPSE_SHADOWS.size() - 1)
	var v: int = _Opt.corpse_vivid
	return "Палитра: %d %s [F7] | Тень: ур. %d %s [F8] | Насыщенность: %s [F9]" % [
		pi + 1, String(CORPSE_PALETTES[pi]["name"]), si, String(CORPSE_SHADOWS[si][2]),
		("+%d" % v) if v > 0 else str(v)]

static func _bucket_key(sheet: Texture2D, frames: int, pixel_size: float) -> String:
	return "%d|%d|%.5f" % [sheet.get_rid().get_id(), frames, pixel_size]


func _get_or_make_shadows(world_root: Node3D) -> ShadowLayer:
	if _shadows != null:
		return _shadows
	var l := ShadowLayer.new()
	# Уровень тени кучи (ручка corpse_shadow) — с первого же тела
	_apply_shadow_level()
	# Меш свой, а МАТЕРИАЛ общий с мини-тенью выделения: пятно и там и здесь
	# одно и то же, а размер задаётся масштабом в трансформе, не мешем
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	# СВОЙ материал, а не общий с тенью выделения: тень лежащего обязана быть
	# ещё бледнее, потому что на завале тени складываются (см. UnitVisuals)
	quad.material = _Vis.corpse_shadow_mesh().material
	l.mm = MultiMesh.new()
	l.mm.transform_format = MultiMesh.TRANSFORM_3D
	l.mm.mesh = quad
	l.mm.instance_count = 0
	l.mmi = MultiMeshInstance3D.new()
	l.mmi.multimesh = l.mm
	l.mmi.extra_cull_margin = 16384.0
	if world_root != null:
		world_root.add_child(l.mmi)
	_shadows = l
	return l


func _get_or_make_bucket(key: String, sheet: Texture2D, frames: int,
		pixel_size: float, world_root: Node3D) -> Bucket:
	if _buckets.has(key):
		return _buckets[key]
	var b := Bucket.new()
	b.tone_k = _tone_k(sheet, frames)
	var sz := sheet.get_size()
	var fw: float = sz.x / float(maxi(frames, 1))

	var quad := QuadMesh.new()
	# РАСТЯЖЕНИЯ ПО ВЕРТИКАЛИ ЗДЕСЬ НЕТ, и это не забытая строка. У стоящего
	# билборда высота домножается на BillboardUtil.V_STRETCH, потому что
	# наклонённая на 45° камера сплющивает вертикаль. Лежащий квад по вертикали
	# не тянется вовсе — он весь горизонтален, и та же камера укорачивает его
	# ровно настолько, насколько и полагается укоротить лежащее тело
	quad.size = Vector2(fw * pixel_size, sz.y * pixel_size)

	var mat := ShaderMaterial.new()
	mat.shader = _SHADER
	mat.set_shader_parameter("albedo_tex", sheet)
	mat.set_shader_parameter("frame_count", float(maxi(frames, 1)))
	# render_priority ЗДЕСЬ НЕ СТАВИТСЯ, и это осознанно. Он решает порядок
	# только среди ПРОЗРАЧНЫХ поверхностей, а тело непрозрачно (см. шапку
	# mm_corpse.gdshader): его место в кадре определяет буфер глубины. Куст,
	# растущий над телом, закроет его сам — растительность прозрачна и рисуется
	# после всего непрозрачного
	quad.material = mat

	b.mm = MultiMesh.new()
	b.mm.transform_format = MultiMesh.TRANSFORM_3D
	b.mm.use_colors = true
	b.mm.mesh = quad
	b.mm.instance_count = 0

	b.mmi = MultiMeshInstance3D.new()
	b.mmi.multimesh = b.mm
	# Пирамиду видимости считает один узел на весь бакет, а тела разбросаны по
	# всей карте (та же оговорка и та же величина, что у FarUnitRenderer)
	b.mmi.extra_cull_margin = 16384.0
	if world_root != null:
		world_root.add_child(b.mmi)

	_buckets[key] = b
	return b


## ── ПОЛОЖИТЬ ТЕЛО ───────────────────────────────────────────────────────────
## Зовётся из Unit._die() ОДИН РАЗ на бойца. Лента, кадр и масштаб берутся из
## его собственного спрайта (Unit.sheet_frame) — тем самым труп подходит любой
## фракции и любому роду войск даром, включая гоблинов и конницу: своей ветки
## ни у кого нет, потому что и различать некого.
##
## Возвращает ЛЕЖАЩЕЕ ТЕЛО (его держит у себя стрела, которая в нём осталась)
## или null, если рисовать нечего — так бывает у бойца, погибшего в первый же
## свой кадр, когда спрайт ещё не построен
## ── ЗАТЕМНЕНИЕ ПО КУЧЕ, А НЕ ПО СЧЁТЧИКУ (ТЗ 24.09.2026, второе письмо) ────
## «Затемняются ТОЛЬКО убитые, слоями: нижние в куче темнее, верхние — чуть
## темнее живых; золотая середина, без черноты». Прежний тон брался от
## кругового счётчика слоёв (TINT_DARKEST..1) и к куче отношения не имел:
## одиночное тело бывало самым тёмным, а сбитый с ног ЖИВОЙ (knock_down тоже
## кладёт тело) темнел наравне с мёртвыми.
## Теперь: новое тело кладётся на верх кучи с тоном PILE_TOP_TINT; тела, на
## которые оно легло (та же клетка PILE_CELL), темнеют на ступень, но не ниже
## PILE_FLOOR_TINT. Ступень МЯГЧЕ у тёмных спрайтов (зелёные гоблины, тёмная
## броня): по средней яркости ленты, один раз на бакет — тёмное, притенённое
## наравне со светлым, уходило бы в кляксу
const PILE_TOP_TINT := 0.92
const PILE_STEP := 0.07
const PILE_FLOOR_TINT := 0.70
const PILE_CELL := 0.9
var _piles: Dictionary = {}          # ключ клетки → Array[Corpse]

func _pile_key(p: Vector3) -> int:
	return (int(floor(p.x / PILE_CELL)) << 20) ^ (int(floor(p.z / PILE_CELL)) & 0xFFFFF)

## Стендам: сколько тел легло в воду вторым слоем (сухим, поверх лежащего)
var wet_layer2: int = 0

## Лежит ли уже в клетке кучи хоть одно тело (живой слот)
func _pile_occupied(p: Vector3) -> bool:
	var arr: Variant = _piles.get(_pile_key(p))
	if arr == null:
		return false
	for o in arr:
		var c := o as Corpse
		if c != null and c.index >= 0:
			return true
	return false

func _pile_push(c) -> void:
	var k: int = _pile_key(c.pos)
	var arr: Variant = _piles.get(k)
	if arr == null:
		_piles[k] = [c]
		return
	var lst: Array = arr
	var i: int = lst.size() - 1
	while i >= 0:
		var o := lst[i] as Corpse
		if o == null or o.index < 0:
			lst.remove_at(i)
		else:
			var step: float = PILE_STEP * float(o.bucket.tone_k)
			o.tint = maxf(PILE_FLOOR_TINT, o.tint - step)
			o.bucket.write(o.index, o.pos, o.yaw, o.frame, o.mirror, o.sent, o.tint, o.scl)
		i -= 1
	lst.append(c)

## Мягкость ступени по яркости ленты: 1.0 у светлых, до 0.55 у тёмных
static func _tone_k(sheet: Texture2D, frames: int) -> float:
	var img: Image = sheet.get_image()
	if img == null:
		return 1.0
	if img.is_compressed():
		img.decompress()
	var fw: int = img.get_width() / maxi(frames, 1)
	var h: int = img.get_height()
	var sum := 0.0
	var n := 0
	for y in range(0, h, 4):
		for x in range(0, fw, 4):
			var px: Color = img.get_pixel(x, y)
			if px.a > 0.5:
				sum += px.r * 0.299 + px.g * 0.587 + px.b * 0.114
				n += 1
	if n == 0:
		return 1.0
	return clampf((sum / float(n)) / 0.5, 0.55, 1.0)

func spawn(unit: Unit, world_root: Node3D, ground_y: float, live: bool = false) -> Corpse:
	if unit == null or not is_instance_valid(unit):
		return null
	# ПОЗА ПАВШЕГО, А НЕ ТЕКУЩАЯ. sheet_frame() отдал бы ту ленту и тот кадр,
	# на которых бойца застала смерть, — то есть замах, выпад копья или щит.
	# Поле выходило заваленным телами, застывшими в атаке, а у гоблина в кадре
	# «Attack Strong» нарисован ещё и белый след удара: на завале эти следы
	# читались как клочья тумана. Спрашиваем бойца, как он выглядит МЁРТВЫМ
	# (Unit.corpse_frame): лента покоя, нулевой кадр
	var sf: Array = unit.corpse_frame()
	if sf.is_empty():
		return null
	var sheet: Texture2D = sf[0]
	var frames: int      = sf[2]
	var px: float        = sf[3]
	if sheet == null:
		return null
	var key: String = _bucket_key(sheet, frames, px)
	# ── ТЕЛО В ВОДЕ ПОГРУЖЕНО ЧАСТЬЮ (ТЗ 24.09.2026, п. 10) ────────────────
	# В броду и на мелком откосе грунт ниже зеркала: тело на грунте целиком
	# пряталось под непрозрачной водой. Теперь оно ложится на ЗЕРКАЛО, а
	# нижняя доля фигуры (WET_FRAC у пехоты, WET_FRAC_BIG у великанов)
	# подкрашивается водой в шейдере — «наполовину под водой». Отдельный бакет
	# на долю: uniform'ом, а не каналом экземпляра — все четыре заняты
	var wet: float = _wet_frac(unit, unit.global_position, ground_y)
	if wet > 0.0:
		var m = GameManager.main
		ground_y = maxf(ground_y, float(m.call("water_surface_y", unit.global_position.x, unit.global_position.z)))
		# ── ВТОРОЙ СЛОЙ: ТЕЛО НА ТЕЛЕ НЕ ТОНЕТ (ТЗ 25.09.2026, п. 2) ───────
		# Упавший поверх того, кто уже лежит в воде, лежит НА НЁМ, а не в
		# воде: сухой бакет на том же зеркале. Слой кучи — та же клетка
		# PILE_CELL, по которой темнеет завал (_pile_push), второго реестра
		# «кто где лежит» не заводится
		if _pile_occupied(unit.global_position):
			wet = 0.0
			wet_layer2 += 1
		else:
			key += "|wet%.2f" % wet
	var b := _get_or_make_bucket(key, sheet, frames, px, world_root)
	if not b.tint_set:
		_set_faction_tint(b, int(unit.faction), kind_of(unit))
	if wet > 0.0 and not b.wet_ready:
		_setup_wet(b, sheet, frames, wet, int(sf[1]))
	if b.free.is_empty():
		b.grow(GROW_STEP)

	var c := Corpse.new()
	c.bucket = b
	c.index = b.free.pop_back()

	# ── КАЖДОЕ ТЕЛО ЛЕЖИТ ПО-СВОЕМУ, НО НИ ОДНО НЕ СТОИТ ───────────────────
	# Угол и зеркало берутся из номера узла, а не из RandomNumberGenerator: то
	# же требование детерминированности, из-за которого раскладка толпы у
	# гоблинов считается по числам (goblin_config.horde_offset). Два прогона
	# одного боя обязаны дать одно поле — иначе стенд не проверить.
	#
	# ── ПОЧЕМУ УГОЛ НЕ ПРОСТО СЛУЧАЙНЫЙ ────────────────────────────────────
	# Тело лежит плашмя, но рисунок на нём — стоящая фигура. Когда её продольная
	# ось случайно совпадает с вертикалью ЭКРАНА (голова «вверх кадра»), лежащий
	# читается как СТОЯЩИЙ: под этой камерой у лежащего и у стоящего в такой позе
	# один и тот же силуэт. Именно это владелец и увидел как «труп застыл
	# вертикально, с копьём в небо».
	#
	# Поэтому продольная ось тела разворачивается ПОПЕРЁК экрана — вбок или по
	# диагонали, с разбросом до COFFIN_SPREAD в обе стороны, но никогда вдоль
	# экранной вертикали. Опорное направление берётся у камеры, а не константой:
	# камеру в этой игре можно поворачивать
	var id: int = int(unit.get_instance_id())
	var r: float = fposmod(float(id) * 0.61803398875, 1.0)
	var side: float = 1.0 if (id & 2) == 0 else -1.0
	# _screen_side_yaw — угол, при котором ГОЛОВА фигуры смотрит вправо по
	# экрану, то есть тело лежит поперёк кадра. Прибавлять к нему прямой угол
	# НЕЛЬЗЯ: это и есть та самая поза «головой вверх кадра», в которой лежащий
	# неотличим от стоящего. Второй вариант — головой ВЛЕВО, это те же 180°
	var yaw: float = _screen_side_yaw(world_root) 		+ (0.0 if side > 0.0 else PI) + (r - 0.5) * 2.0 * COFFIN_SPREAD
	var mirror: bool = (id & 1) == 1
	var gp: Vector3 = unit.global_position
	c.yaw = yaw
	c.mirror = mirror
	# Своя ступенька высоты — навсегда (см. LAYER_STEP)
	c.lift = GROUND_LIFT + float(_layer) * LAYER_STEP
	# Яркость: живой (сбит с ног) — как живой; мёртвый — верх кучи
	c.tint = 1.0 if live else PILE_TOP_TINT
	_layer = (_layer + 1) % LAYER_WRAP
	var at := Vector3(gp.x, ground_y + c.lift, gp.z)
	c.pos = at
	# Размер — из того же числа, что угол и зеркало: два прогона одного боя
	# обязаны дать одно поле
	c.scl = 1.0 + (fposmod(float(id) * 0.31830988618, 1.0) - 0.5) * 2.0 * SIZE_JITTER
	c.frame = int(sf[1])
	if not live:
		_pile_push(c)
	b.write(c.index, at, yaw, int(sf[1]), mirror, 1.0, c.tint, c.scl)

	# ── ТЕНЬ ПОД ТУЛОВИЩЕМ ─────────────────────────────────────────────────
	# Размер выводится из самого квада тела, а не задаётся числом: гоблин и
	# человек разного размера, и пятно обязано следовать за ними.
	# Круг, а не овал по оси тела, и поворота у него нет (см. SHADOW_FRAC)
	var sl := _get_or_make_shadows(world_root)
	if sl.free.is_empty():
		sl.grow(GROW_STEP)
	c.shadow_index = sl.free.pop_back()
	var qs: Vector2 = (b.mm.mesh as QuadMesh).size
	c.shadow_size = minf(qs.x, qs.y) * SHADOW_FRAC * _shadow_mult
	sl.write(c.shadow_index, Vector3(at.x, ground_y + SHADOW_DROP, at.z),
		c.shadow_size)
	c.born = _clock
	c.faction = int(unit.faction)
	c.unit_id = String(unit.stat_id)
	c.squad_id = int(unit.squad_id)
	c.raisable = c.faction != Constants.FACTION_GOBLIN \
		and Building.PRELOAD_SCENES.has(c.unit_id) and c.unit_id != "troll"
	_list.append(c)
	if c.raisable:
		_raisable_add(c)
	spawned_total += 1

	# ── ЛИМИТ: САМЫЕ СТАРЫЕ НАЧИНАЮТ ГАСНУТЬ ───────────────────────────────
	# Не «удалить сразу»: исчезновение тела на глазах читается как сбой. Слот
	# освободится, когда труп догорит, поэтому на время растворения их на поле
	# чуть больше лимита — это осознанный запас, а не просчёт.
	#
	# ПРОТИВ ЛИМИТА СЧИТАЮТСЯ ТОЛЬКО ТЕ, КТО ЕЩЁ НЕ ГАСНЕТ, и это не мелочь.
	# Считали по всей длине списка — и получали лавину: догорающий остаётся в
	# списке до конца растворения, поэтому следующая же смерть снова видела
	# перебор и назначала гаснуть ещё одного, и так каждая. Стенд qa_corpse
	# поймал это в чистом виде: из 540 тел растворяться начали ВСЕ 540, а поле
	# после боя оставалось пустым
	_evict_over_limit()
	return c


## Перебор потолка: самые старые начинают гаснуть (см. разбор у вызывающего)
## СНЯТЫЕ МЕСТА (index < 0) — НЕ ТЕЛА (лог партии 26.10.2026, 5000 тел у
## потолка 40 минут). До уплотнения (_compact) догоревшее и снятое лежат в
## очереди с отрицательным fade_left, как лежащее, — и вытеснение пускало их
## гаснуть ПОВТОРНО: hide_slot(-1) отрицательным индексом Packed-массива
## гасил ПОСЛЕДНИЙ слот бакета (чужое тело пропадало), в свободный список
## уходил −1, и новое тело ложилось в тот же последний слот. Они же
## считались живыми против потолка — гасли лишние
func _evict_over_limit() -> void:
	var over: int = (_list.size() - _fading.size() - _dead_slots) - MAX_CORPSES
	var k: int = 0
	while over > 0 and k < _list.size():
		var old: Corpse = _list[k]
		if old.index >= 0 and old.fade_left < 0.0:
			_begin_fade(old, FADE_SEC)
			over -= 1
		k += 1


## ── ПУСТИТЬ ТЕЛО РАСТВОРЯТЬСЯ ──────────────────────────────────────────────
## Одна точка на оба повода (истёк срок жизни / вытеснено потолком): различаются
## они ровно длительностью, и она же становится знаменателем доли, которая
## уезжает в буфер. Стрелы гаснут ВМЕСТЕ с телом и в тот же срок — стрела,
## пережившая тело и повисшая в воздухе, заметнее любой экономии
func _begin_fade(cc: Corpse, secs: float) -> void:
	cc.fade_left  = secs
	cc.fade_total = maxf(secs, 0.0001)
	cc.sent       = 1.0
	_fading.append(cc)
	for a in cc.arrows:
		# Стрела ядра (id записи, этап 3) или legacy-узел Arrow
		if a is int:
			GameManager.army.stuck_fade(int(a), secs)
		elif is_instance_valid(a) and a.has_method("fade_out_in"):
			a.fade_out_in(secs)


## ── ПОЛОЖИТЬ НА ПОЛЕ ПРЕДМЕТ, А НЕ ТЕЛО ────────────────────────────────────
## Зовётся, когда отряд выбит целиком и его знамя падает наземь
## (GameManager._drop_squad_banner). Предмет — это тот же слот в том же буфере,
## что и труп: та же лента, тот же шейдер, тот же потолок, то же вытеснение и
## то же разложение за пятнадцать минут. Отдельного слоя, отдельного узла и
## отдельного вызова отрисовки у него нет и не нужно.
##
## ПОЧЕМУ ЭТО ВООБЩЕ ВОЗМОЖНО. Слой тел не знает слова «труп»: он умеет класть
## плашмя КВАД С ЛЕНТОЙ и гасить его по времени (см. шапку файла). Знамя
## нарисовано текстурой именно ради этого (см. BannerArt) — и ложится сюда той
## же строчкой, что и павший копейщик.
##
## ОТЛИЧИЙ ОТ ТЕЛА РОВНО ДВА, И ОБА ОСОЗНАННЫЕ:
##   • ЯРКОСТЬ ВСЕГДА ПОЛНАЯ. Тела притеняются по своей ступеньке в куче
##     (TINT_DARKEST) — так читается объём завала. Знамя в куче не лежит, оно
##     ОДНО, и притенённое читалось бы не как «под телами», а как выцветшее;
##   • РАЗМЕР БЕЗ РАЗБРОСА. ±7% у тел лечат «штампованных клонов», а знамя на
##     поле одно на отряд, и клонов среди них не бывает.
##
## `seed_id` задаёт угол падения: два прогона одного боя обязаны положить знамя
## одинаково (то же требование детерминированности, что и у тел)
func spawn_prop(sheet: Texture2D, frames: int, px: float, at: Vector3,
		seed_id: int, world_root: Node3D, ground_y: float) -> Corpse:
	if sheet == null:
		return null
	var key: String = _bucket_key(sheet, frames, px)
	var b := _get_or_make_bucket(key, sheet, frames, px, world_root)
	if b.free.is_empty():
		b.grow(GROW_STEP)
	var c := Corpse.new()
	c.bucket = b
	c.index = b.free.pop_back()
	# Угол — по тому же правилу, что у тел: поперёк экрана с разбросом. Древко,
	# легшее вдоль экранной вертикали, читалось бы как стоящее знамя (ровно та
	# же ловушка, из-за которой тела разворачивают поперёк, см. COFFIN_SPREAD)
	var r: float = fposmod(float(seed_id) * 0.61803398875, 1.0)
	var side: float = 1.0 if (seed_id & 2) == 0 else -1.0
	c.yaw = _screen_side_yaw(world_root) \
		+ (0.0 if side > 0.0 else PI) + (r - 0.5) * 2.0 * COFFIN_SPREAD
	c.mirror = (seed_id & 1) == 1
	c.lift = GROUND_LIFT + float(_layer) * LAYER_STEP
	c.tint = 1.0
	c.scl = 1.0
	_layer = (_layer + 1) % LAYER_WRAP
	var pos := Vector3(at.x, ground_y + c.lift, at.z)
	c.pos = pos
	b.write(c.index, pos, c.yaw, 0, c.mirror, 1.0, c.tint, c.scl)

	var sl := _get_or_make_shadows(world_root)
	if sl.free.is_empty():
		sl.grow(GROW_STEP)
	c.shadow_index = sl.free.pop_back()
	var qs: Vector2 = (b.mm.mesh as QuadMesh).size
	c.shadow_size = minf(qs.x, qs.y) * SHADOW_FRAC * _shadow_mult
	sl.write(c.shadow_index, Vector3(pos.x, ground_y + SHADOW_DROP, pos.z),
		c.shadow_size)
	c.born = _clock
	_list.append(c)
	spawned_total += 1
	_evict_over_limit()
	return c


## ── ПОКАДРОВЫЙ ХОД ──────────────────────────────────────────────────────────
## Поле, заваленное телами, стоит ПОЧТИ ноль и на пяти тысячах: работы здесь
## ровно две, и обе не зависят от числа лежащих.
##
## 1. СРОК ЖИЗНИ ПРОВЕРЯЕТСЯ ТОЛЬКО У ГОЛОВЫ ОЧЕРЕДИ. Очередь упорядочена по
##    времени укладки, срок у всех один — значит истекает он строго по порядку.
##    Обходить весь список, спрашивая у каждого возраст, означало бы платить
##    пятью тысячами сравнений в кадр за событие, которое случается раз в
##    пятнадцать минут. Указатель _scan стоит на первом теле, которому ещё рано,
##    и сдвигается ровно на столько тел, сколько в этом кадре действительно
##    истекло.
##
## 2. РАСТВОРЯЮЩИЕСЯ ПИШУТСЯ ЗАГРУБЛЁННО. Растворение идёт тридцать секунд, и
##    подавать из-за него буфер бакета целиком (320 КБ на пять тысяч тел)
##    шестьдесят раз в секунду незачем: доля уезжает шагами по
##    DISSOLVE_WRITE_STEP, то есть вшестеро реже. Разницы на экране нет —
##    дизер и так рассыпает тело пятнами, а не ровной пеленой
func update(delta: float) -> void:
	_clock += delta
	# ── ИСТЁК ЛИ СРОК У ГОЛОВЫ ──────────────────────────────────────────────
	var n: int = _list.size()
	while _scan < n:
		var head: Corpse = _list[_scan]
		# Слева от указателя остаются уже снятые и уже гаснущие — переступаем
		if head.index < 0 or head.fade_left >= 0.0:
			_scan += 1
			continue
		if _clock - head.born < LIFE_SEC:
			break
		_begin_fade(head, DISSOLVE_SEC)
		_scan += 1
	if _fading.is_empty():
		return
	var keep: Array = []
	for c in _fading:
		var cc: Corpse = c
		if cc.index < 0:
			continue            # снято, пока гасло (см. _evict_over_limit)
		cc.fade_left -= delta
		if cc.fade_left <= 0.0:
			cc.bucket.hide_slot(cc.index)
			cc.bucket.free.append(cc.index)
			if _shadows != null and cc.shadow_index >= 0:
				_shadows.hide_slot(cc.shadow_index)
				_shadows.free.append(cc.shadow_index)
				cc.shadow_index = -1
			_drop_arrows(cc)
			# Место в очереди помечается снятым, а сам массив уплотняется
			# пачкой (см. COMPACT_MIN): erase по значению — это проход по всем
			# пяти тысячам на каждое догоревшее тело
			cc.index = -1
			_dead_slots += 1
		else:
			var k: float = cc.fade_left / cc.fade_total
			if cc.sent - k >= DISSOLVE_WRITE_STEP or k <= 0.0:
				cc.sent = k
				cc.bucket.write_alpha(cc.index, k)
				# Тень сжимается вместе с телом (см. ShadowLayer.write_size)
				if _shadows != null and cc.shadow_index >= 0:
					_shadows.write_size(cc.shadow_index, cc.shadow_size * k)
			keep.append(cc)
	_fading = keep
	if _dead_slots >= COMPACT_MIN:
		_compact()


## ── ВРЕМЕННОЕ ТЕЛО ЛЕЖАЩЕГО БОЙЦА (Unit.knock_down) ─────────────────────────
## Снять сразу, без растворения: боец встал. Место в очереди помечается
## снятым и уплотняется пачкой, как у догоревшего
func remove_now(c) -> void:
	var cc := c as Corpse
	if cc == null or cc.index < 0:
		return
	cc.bucket.hide_slot(cc.index)
	cc.bucket.free.append(cc.index)
	if _shadows != null and cc.shadow_index >= 0:
		_shadows.hide_slot(cc.shadow_index)
		_shadows.free.append(cc.shadow_index)
		cc.shadow_index = -1
	_drop_arrows(cc)
	if cc.fade_left >= 0.0:
		_fading.erase(cc)
	cc.index = -1
	_dead_slots += 1

## Подвинуть тело вслед за бойцом, которого ещё несёт разлётом
func move_now(c, at: Vector3) -> void:
	var cc := c as Corpse
	if cc == null or cc.index < 0:
		return
	var p := Vector3(at.x, GameManager.get_terrain_height(at.x, at.z) + cc.lift, at.z)
	cc.pos = p
	cc.bucket.write(cc.index, p, cc.yaw, cc.frame, cc.mirror, 1.0, cc.tint, cc.scl)
	if _shadows != null and cc.shadow_index >= 0:
		_shadows.write(cc.shadow_index, Vector3(p.x, p.y - cc.lift + SHADOW_DROP, p.z), cc.shadow_size)

## Выбросить снятые места из очереди одним проходом. Указатель срока жизни
## переносится вместе с ними: он считает МЕСТА, а не тела
func _compact() -> void:
	if _dead_slots <= 0:
		return
	var out: Array = []
	var new_scan: int = 0
	for i in range(_list.size()):
		var cc: Corpse = _list[i]
		if cc.index < 0:
			continue
		if i < _scan:
			new_scan += 1
		out.append(cc)
	_list = out
	_scan = new_scan
	_dead_slots = 0


func flush() -> void:
	for b in _buckets.values():
		(b as Bucket).flush()
	if _shadows != null:
		_shadows.flush()


## ── СТРЕЛЫ, ОСТАВШИЕСЯ В ТЕЛЕ ──────────────────────────────────────────────
## Зовёт сама стрела сразу после смертельного попадания (Arrow._stick_into_corpse).
## Больше MAX_ARROWS_PER_CORPSE в одном теле не держим: добитый залпом иначе
## превращался бы в ёжика, а каждая стрела — это отдельный вызов отрисовки
func attach_arrow(c, arrow) -> bool:
	var cc := c as Corpse
	if cc == null or arrow == null:
		return false
	if cc.arrows.size() >= MAX_ARROWS_PER_CORPSE:
		return false
	cc.arrows.append(arrow)
	return true

## ── СТРЕЛА В ТУЛОВИЩЕ ──────────────────────────────────────────────────────
## Ставит ЕДИНСТВЕННУЮ стрелу — ту, что бойца добила.
##
## СКОЛЬКО. Ровно одна (см. MAX_ARROWS_PER_CORPSE). Прежний порядок добирал
## «недостающие» из пула отдельными узлами, потому что реально долетает только
## последняя стрела залпа, а остальные ушли в пул ещё при жизни бойца. Ради
## двух лишних стрелок на теле каждая смерть заводила два лишних узла с личным
## мешем и личным материалом — то есть два лишних вызова отрисовки, живущих на
## поле десятками секунд. На завале это и оказалось главной статьёй проседания.
##
## КУДА. Точка раскладывается ПО ТУЛОВИЩУ в системе координат самого тела:
## вдоль оси и поперёк, вразброс, но в габарите туловища. Поэтому стрела лежит
## ровно на теле при любом его повороте и не висит в воздухе рядом.
##
## ПОД КАКИМ УГЛОМ. Вектор попадания доворачивается на свой для каждого тела
## угол: строго по траектории все стрелы на поле смотрели бы в одну сторону,
## как расчёска
## ── СТРЕЛА БЕЗ УЗЛА (BigStand-5, этап 3) ─────────────────────────────────
## killer — либо legacy-узел Arrow (stick_decor), либо НОМЕР СЛОЯ ядра; тогда
## slot — слот стрелы в слое, length — длина её квада, а в списке тела лежит
## id записи торчащей (ArmyCore.ProjectileStick): тело гасит её StuckFade
func stick_arrows(c, killer, incoming: Vector3, head: bool = false,
		slot: int = -1, length: float = 0.0) -> bool:
	var cc := c as Corpse
	if cc == null or killer == null:
		return false
	if cc.arrows.size() >= MAX_ARROWS_PER_CORPSE:
		return false
	var spot: Vector3 = _head_spot(cc) if head else _arrow_spot(cc)
	if killer is int:
		if slot < 0:
			return false
		# Растворение — своё по виду снаряда (кость тает быстрее стрелы)
		var fade: float = _ArrowC.BONE_STUCK_FADE if int(killer) == GameManager.bones_mm.core_id 			else _ArrowC.STUCK_FADE
		var sid: int = GameManager.army.projectile_stick(int(killer), slot, spot,
			_arrow_dir(cc, incoming), length, true, 0.0, fade)
		if sid < 0:
			return false
		cc.arrows.append(sid)
		return true
	cc.arrows.append(killer)
	killer.call("stick_decor", spot, _arrow_dir(cc, incoming))
	return true

## ── ГОЛОВА ЛЕЖАЩЕГО (снайперская стрела, ТЗ 14.09.2026) ───────────────────
## Локальный +Y квада (верх рисунка, голова) лежит по (sin yaw, 0, −cos yaw) —
## та же ось, что «along» у _arrow_spot. Смещение — доля высоты квада
## (SNIPE_HEAD_ALONG) с масштабом тела: верхняя часть силуэта
func _head_spot(cc: Corpse) -> Vector3:
	var qs: Vector2 = (cc.bucket.mm.mesh as QuadMesh).size
	var along: float = qs.y * cc.scl * _UCfgC.SNIPE_HEAD_ALONG
	return Vector3(cc.pos.x + sin(cc.yaw) * along,
		cc.pos.y + 0.02,
		cc.pos.z - cos(cc.yaw) * along)

## Точка головы тела (для стендов): та же геометрия, что у стрелы
func head_spot_of(c) -> Vector3:
	var cc := c as Corpse
	if cc == null:
		return Vector3.INF
	return _head_spot(cc)

## Точка стрелы в туловище. Считается в осях ТЕЛА и переводится в мировые его
## же поворотом — так стрела лежит на теле при любой его ориентации
func _arrow_spot(cc: Corpse) -> Vector3:
	var cy: float = cos(cc.yaw)
	var sy: float = sin(cc.yaw)
	# Псевдослучайно, но устойчиво: два прогона одного боя обязаны дать одно
	# поле (то же требование, что и к самому углу тела)
	var h1: float = fposmod(sin(cc.pos.x * 12.9898 + cc.pos.z * 4.1414) * 43758.5453, 1.0)
	var h2: float = fposmod(sin(cc.pos.z * 78.2330 + cc.pos.x * 7.7373) * 24634.6345, 1.0)
	var along: float = (h1 - 0.5) * cc.shadow_size * 0.7
	var across: float = (h2 - 0.5) * cc.shadow_size * 0.7
	# Оси тела те же, что в Bucket.write: X — поперёк, Y — вдоль.
	# Собираем мировое смещение из них
	return Vector3(cc.pos.x + cy * across + sy * along,
		cc.pos.y + 0.02,
		cc.pos.z + sy * across - cy * along)

## Угол стрелы в теле: траектория попадания плюс свой разворот вокруг
## вертикали. Разброс до ±25°, детерминированно от места гибели
func _arrow_dir(cc: Corpse, incoming: Vector3) -> Vector3:
	var h: float = fposmod(sin(cc.pos.x * 3.7411 + cc.pos.z * 9.2213) * 15731.7431, 1.0)
	return incoming.rotated(Vector3.UP, (h - 0.5) * 0.87)

## Тело догорело — снять с поля и его стрелы. Стрела гасится своим же способом
## (уходит в пул), а не queue_free: пул на то и заведён
func _drop_arrows(cc: Corpse) -> void:
	for a in cc.arrows:
		if a is int:
			GameManager.army.stuck_remove(int(a))
		elif is_instance_valid(a) and a.has_method("despawn_now"):
			a.despawn_now()
	cc.arrows.clear()

## Сколько тел лежит прямо сейчас (включая догорающие).
##
## УПЛОТНЯЕТ ОЧЕРЕДЬ ПЕРЕД ОТВЕТОМ, и это не мелочь: снятые места живут в
## массиве до накопления пачки (см. COMPACT_MIN), и без уплотнения и счёт, и
## индексы в lay_of поехали бы на число догоревших. Зовут это всё только стенды
## и панель, в покадровом пути таких вызовов нет
## ── КОГО ПОДНЯТЬ (письмо 12): ближайшее целое тело своей стороны ───────────
## Тело на растворении не поднимается (его уже нет наполовину)
## ── ТО ЖЕ, НО С ПРИОРИТЕТОМ ПО РОДУ ВОЙСК (заказ 13.09.2026) ──────────────
## Монах поднимает СНАЧАЛА павших монахов, и только потом пехоту.
##
## ПРИОРИТЕТ ПО РОДУ, А НЕ ПО ОТРЯДУ, И ЭТО НЕ УПРОЩЕНИЕ. «Свой отряд» у
## монаха — это Ctrl-группа игрока (монах сам по себе отряд из одного,
## SQUAD_SIZE_MONKS = 1), а Ctrl-группы живут в SelectionManager списком
## ЖИВЫХ узлов: павший из них выбывает, и у тела спросить его группу уже
## нечем. По роду войск ответ выходит тот же самый — монахов на поле
## единицы, — и не требует второго реестра, который пришлось бы вести
## через смерть.
## ── РЕЕСТР ГОДНЫХ К ПОДЪЁМУ — ПО ФРАКЦИИ (qa_melee_bench, 14.09.2026) ──────
## Монах спрашивает тела раз в такт, и прежний обход шёл по ВСЕМУ слою
## (до 5000 тел, орда и тролли включительно) — тик монаха до 5.8 мс в
## замесе. Здесь только тела людей своей стороны; погасшие и снятые
## отсеиваются лениво, при обходе (swap-remove), второго события не нужно
var _raisable: Dictionary = {}     # faction → Array[Corpse]

func _raisable_add(c) -> void:
	var f: int = int(c.faction)
	var arr: Variant = _raisable.get(f)
	if arr == null:
		_raisable[f] = [c]
	else:
		(arr as Array).append(c)

## Живые (не снятые, не гаснущие) тела фракции; список чистится по ходу
func _raisable_list(fac: int) -> Array:
	var raw: Variant = _raisable.get(fac)
	if raw == null:
		return []
	var arr: Array = raw
	var i: int = arr.size() - 1
	while i >= 0:
		var cc := arr[i] as Corpse
		if cc == null or cc.index < 0 or cc.fade_left >= 0.0:
			arr[i] = arr[arr.size() - 1]
			arr.pop_back()
		i -= 1
	return arr

## Тело, чей отряд уже в штате, поднимать некуда (GameManager.squad_has_room);
## ответ по отряду кэшируется на один поиск
func _no_room(cc: Corpse, memo: Dictionary) -> bool:
	if cc.squad_id <= 0:
		return false
	var v: Variant = memo.get(cc.squad_id)
	if v == null:
		v = not GameManager.squad_has_room(cc.squad_id)
		memo[cc.squad_id] = v
	return bool(v)

func find_raisable_priority(fac: int, at: Vector3, radius: float,
	want_id: String, _asker_squad: int = 0):
	var best_want = null
	var best_any = null
	var dw: float = radius * radius
	var da: float = radius * radius
	var memo: Dictionary = {}
	for c in _raisable_list(fac):
		var cc := c as Corpse
		if _no_room(cc, memo):
			continue
		var dx: float = cc.pos.x - at.x
		var dz: float = cc.pos.z - at.z
		var d2: float = dx * dx + dz * dz
		if cc.unit_id == want_id:
			if d2 < dw:
				dw = d2
				best_want = cc
		elif d2 < da:
			da = d2
			best_any = cc
	return best_want if best_want != null else best_any

## Ближайшее годное тело ИМЕННО ЭТОГО ОТРЯДА (ТЗ 18.09.2026, п. 2). Монах
## ведёт отряд-пациент до полного штата, и спрашивать «ближайшее тело своей
## стороны, а потом сверить отряд» нельзя: в замесе ближайшим почти всегда
## лежит чужой по отряду павший, сверка отвечает «нет», и подъём кончался на
## первом теле — отряд оставался с 31 из 60
## Тело занято ДРУГИМ живым монахом (захват снимается сам, если монах пал)
static func claimed_by_other(cc, me: int) -> bool:
	var cb: int = int(cc.claimed_by)
	if cb == 0 or cb == me:
		return false
	var o: Object = instance_from_id(cb)
	if o == null or not is_instance_valid(o) or o.get("_res_target") != cc:
		cc.claimed_by = 0
		return false
	return true

func find_raisable_of_squad(fac: int, sid: int, at: Vector3, radius: float, me: int = 0):
	var best: Corpse = null
	var bd: float = radius * radius
	if sid > 0 and not GameManager.squad_has_room(sid):
		return null
	for c in _raisable_list(fac):
		var cc := c as Corpse
		if cc.squad_id != sid:
			continue
		if me != 0 and claimed_by_other(cc, me):
			continue
		var dx: float = cc.pos.x - at.x
		var dz: float = cc.pos.z - at.z
		var d: float = dx * dx + dz * dz
		if d < bd:
			bd = d
			best = cc
	return best

func raisable_count_of_squad(fac: int, sid: int) -> int:
	var n := 0
	for c in _raisable_list(fac):
		if (c as Corpse).squad_id == sid:
			n += 1
	return n

func find_raisable(fac: int, at: Vector3, radius: float):
	var best: Corpse = null
	var bd: float = radius * radius
	var memo: Dictionary = {}
	for c in _raisable_list(fac):
		var cc := c as Corpse
		if _no_room(cc, memo):
			continue
		var dx: float = cc.pos.x - at.x
		var dz: float = cc.pos.z - at.z
		var d: float = dx * dx + dz * dz
		if d < bd:
			bd = d
			best = cc
	return best

func raisable_count(fac: int) -> int:
	return _raisable_list(fac).size()

func count() -> int:
	_compact()
	return _list.size()

## Сколько тел прямо сейчас растворяется
func fading_count() -> int:
	return _fading.size()

## Сколько узлов MultiMeshInstance3D заведено (столько же вызовов отрисовки)
func bucket_count() -> int:
	return _buckets.size()

## Как лёг i-е по счёту тело: [поворот, зеркало, доля непрозрачности, высота
## над грунтом, число стрел в нём, яркость слоя, размер].
## Только для стендов — в игре это не нужно
func lay_of(i: int) -> Array:
	_compact()
	if i < 0 or i >= _list.size():
		return []
	var c: Corpse = _list[i]
	var a: float = 1.0 if c.fade_left < 0.0 else c.fade_left / c.fade_total
	return [c.yaw, c.mirror, a, c.lift, c.arrows.size(), c.tint, c.scl]


## Сколько секунд i-е тело уже лежит (по часам слоя). Нужно стенду срока жизни:
## гонять его пятнадцать минут реального времени нельзя, поэтому часы
## подкручиваются через age_shift()
func age_of(i: int) -> float:
	_compact()
	if i < 0 or i >= _list.size():
		return -1.0
	return _clock - (_list[i] as Corpse).born


## Сколько ещё растворяться i-му телу и сколько всего длится ЕГО растворение.
## [-1, 0] — тело лежит целым и не растворяется вовсе
func dissolve_of(i: int) -> Array:
	_compact()
	if i < 0 or i >= _list.size():
		return [-1.0, 0.0]
	var c: Corpse = _list[i]
	return [c.fade_left, c.fade_total]


## ПОСТАВИТЬ ТЕЛУ ДОЛЮ РАЗЛОЖЕНИЯ НАПРЯМУЮ (1 — целое, 0 — растаяло).
## Только для ОКОННОГО стенда: фазу разложения судят глазом, а ждать её
## тридцать секунд ради одного снимка незачем. Пишет ровно то же число, что
## пишет update() — COLOR.b слота (см. mm_corpse.gdshader)
func set_dissolve(i: int, left: float) -> void:
	_compact()
	if i < 0 or i >= _list.size():
		return
	var c: Corpse = _list[i]
	if c.index < 0:
		return
	c.bucket.write_alpha(c.index, clampf(left, 0.0, 1.0))


## ПЕРЕВЕСТИ ЧАСЫ СЛОЯ ВПЕРЁД. Только для стендов: срок жизни тела — пятнадцать
## минут, и ждать их взаправду нельзя ни на одном стенде. Сдвигается ИМЕННО
## время укладки, а не часы: часы монотонны, и прыжок в них сбил бы отсчёт
## растворения у тех, кто уже гаснет
func age_shift(secs: float) -> void:
	for c in _list:
		(c as Corpse).born -= secs


## Полная очистка (смена сцены или сброс партии). Сами MultiMeshInstance3D
## уходят вместе со старым World — здесь снимаются только ссылки, иначе реестр
## пережил бы сцену и держал освобождённые узлы (та же оговорка у far_units)
func clear() -> void:
	_piles.clear()
	_list.clear()
	_fading.clear()
	_buckets.clear()
	_shadows = null
	_layer = 0
	spawned_total = 0
	_clock = 0.0
	_scan = 0
	_dead_slots = 0

## Есть ли у тела своё пятно тени (нужно стенду)
func has_shadow(i: int) -> bool:
	_compact()
	if i < 0 or i >= _list.size():
		return false
	return (_list[i] as Corpse).shadow_index >= 0
