using Godot;
using System;

// ═══════════════════════════════════════════════════════════════════════════
// ЯДРО АРМИИ НА C#: КОЛОНКИ, СЕТКА, СКАНЫ И ДВА ПАКЕТНЫХ ПРОХОДА
// ═══════════════════════════════════════════════════════════════════════════
// ЧТО ЭТО. Точный перенос scripts/army/ArmySoA.gd на C#. Правила не меняются
// НИ В ОДНОМ месте: тот же порядок стадий шага, те же формулы расталкивания,
// те же радиусы и пороги, та же семантика «одновременного» снимка сетки.
// Меняется только язык, на котором это считается.
//
// ПОЧЕМУ ВЛАДЕТЬ КОЛОНКАМИ ОБЯЗАН ИМЕННО СОЛВЕР. На границе GDScript↔C# в
// Godot 4 Packed*Array маршалится КОПИЕЙ. Отдавать солверу десяток массивов по
// три тысячи чисел каждый кадр — значит подарить ему обратно весь выигрыш.
// Поэтому массивы живут здесь и наружу не выходят вовсе; GDScript видит только
// тонкие сеттеры (одно число за вызов) и команды «посчитай кадр».
//
// ПОЧЕМУ ВМЕСТЕ С НИМИ ПЕРЕЕХАЛИ СЕТКА, СКАНЫ И РЕЕСТР СТВОЛОВ. Они читают те
// же колонки. Оставь их в GDScript — и каждый пакетный проход дёргал бы
// интерпретатор обратно НА КАЖДОГО БОЙЦА, то есть платил бы за переход границы
// ровно там, где мы её и убирали. Реестр стволов перенесён по той же причине:
// это последний вызов наружу, который оставался внутри шага.
//
// ГДЕ ЭТО УПИРАЕТСЯ В ПОТОЛОК (замер 26.08.2026, qa_mass_battle --count=6000).
// Шесть тысяч бойцов в свалке дают около 18 мс физического кадра при бюджете
// 16.6. Из них на солвер приходится: BatchSeparation ≈1.5 мс, BatchMove ≈1.2 мс,
// перестройка сетки ≈0.15 мс — то есть ЯДРО НЕ ЯВЛЯЕТСЯ УЗКИМ МЕСТОМ. Три
// четверти времени тика съедает ветка подхода в GDScript у тех 74 % бойцов,
// которым в свалке не по кому ударить.
//
// ЧТО ИЗ ЭТОГО СЛЕДУЕТ ДЛЯ ЭТОГО ФАЙЛА. Резерв здесь один — параллелить
// BatchSeparation, — и он НЕ БЕРЁТСЯ по двум причинам сразу. Первая:
// цикл не только считает поправки, но и ПРИМЕНЯЕТ их — пишет Node3D.Position
// и зовёт метод узла, а к узлам сцены из рабочих потоков Godot обращаться
// нельзя. Вторая: разделение на «посчитать параллельно / применить линейно»
// превращает Гаусса-Зейделя в Якоби (сейчас каждый следующий боец видит уже
// сдвинутых соседей), и результат разбора наложения меняется на сантиметры —
// а его стерегут qa_push и qa_crowd с точностью до сантиметров.
// Полный разбор — в docs/PERF_6000.md.
//
// ЧЕГО ЗДЕСЬ НЕТ И НЕ ДОЛЖНО БЫТЬ: решений. Куда идти, кого бить, не пора ли
// перехватить чужой строй — это по-прежнему автомат бойца в GDScript. Здесь
// только математика: на входе числа, на выходе числа.
public partial class ArmyCore : RefCounted
{
    private const int GrowStep = 1024;

    // ── КОЛОНКИ ────────────────────────────────────────────────────────────
    private float[] _px = Array.Empty<float>();
    private float[] _py = Array.Empty<float>();
    private float[] _pz = Array.Empty<float>();
    private float[] _vx = Array.Empty<float>();
    private float[] _vz = Array.Empty<float>();
    private float[] _hp = Array.Empty<float>();
    private float[] _hpMax = Array.Empty<float>();
    private float[] _atkCd = Array.Empty<float>();
    // Радиус, в котором дремлющий держит цель (attack_range + поправка на
    // габарит цели); пишется ОДИН раз при взводе дрёмы (AtkSnoozeArm)
    private float[] _atkReach = Array.Empty<float>();
    // Тыловой напор: точка, куда давить; скорость шага; дистанция остановки.
    // Пишутся АРЕНДОЙ раз в MELEE_TTL (см. GameManager._recalc_melee)
    // ── СКРЭТЧ ДВУХФАЗНОГО РАЗВЕДЕНИЯ (этап D2) ────────────────────────────
    // Фаза расчёта пишет кандидата сюда, фаза применения (последовательная)
    // проводит его через воду и узлы. Двухфазность БЕЗУСЛОВНАЯ: и серийный, и
    // многопоточный расчёт читают один и тот же снимок позиций, поэтому число
    // потоков не меняет результат ни на бит — детерминизм по построению
    private float[] _sepNX = Array.Empty<float>();
    private float[] _sepNZ = Array.Empty<float>();
    private byte[] _sepGo = Array.Empty<byte>();

    /// Число потоков пакетных проходов (ставит GDScript из perf_config;
    /// 1 — однопоточно). Потокам разрешена ТОЛЬКО чистая математика по
    /// колонкам: ни вызовов GDScript, ни дерева сцены, ни RenderingServer
    public static int CoreThreads = 1;
    public void SetThreads(int t) { CoreThreads = Math.Max(1, t); }

    private float[] _pressX = Array.Empty<float>();
    private float[] _pressZ = Array.Empty<float>();
    private float[] _pressV = Array.Empty<float>();
    private float[] _pressStop = Array.Empty<float>();
    private float[] _aggroT = Array.Empty<float>();
    private float[] _atkDmg = Array.Empty<float>();
    private float[] _atkRange = Array.Empty<float>();
    private float[] _speed = Array.Empty<float>();
    private float[] _sepT = Array.Empty<float>();
    // ЛИЧНЫЙ РАДИУС РАСТАЛКИВАНИЯ. Ноль — «как у всех», то есть minDist из
    // аргумента BatchSeparation; ненулевое значение перекрывает его для этой
    // строки. Заведён ради гоблинов: их спрайт крупнее людского в 1.7 раза, и
    // единая на всю армию дистанция либо склеивала орду, либо раздвигала людей
    private float[] _sepR = Array.Empty<float>();
    private float[] _slX = Array.Empty<float>();
    private float[] _slZ = Array.Empty<float>();
    private float[] _stpX = Array.Empty<float>();
    private float[] _stpZ = Array.Empty<float>();
    private float[] _thX = Array.Empty<float>();
    private float[] _thZ = Array.Empty<float>();
    private float[] _thY = Array.Empty<float>();
    private int[] _st = Array.Empty<int>();
    private int[] _fac = Array.Empty<int>();
    private int[] _sq = Array.Empty<int>();
    private int[] _flags = Array.Empty<int>();
    // Сколько бойцов уже целится в этого. Раньше best_enemy читал это поле у
    // ОБЪЕКТА; из C# такое чтение — обращение через Variant на каждого
    // кандидата, то есть дороже самого скана. Здесь это колонка, а GDScript
    // обновляет её там же, где менял поле (три места в Unit)
    private int[] _attackers = Array.Empty<int>();
    // Cтрока ЦЕЛИ атаки; -1 - цели нет или она не боец (здание, ресурс).
    // Пишется по событию, из Unit.set_attack_target: смена цели редка
    private int[] _tgt = Array.Empty<int>();
    // Эффективная скорость подхода. Отдельно от _speed: та базовая, а эта уже
    // с множителями стойки и бега. Пакетный бой считает по ней шаг подтягивания
    private float[] _effSpeed = Array.Empty<float>();
    // Направление взгляда, посчитанное пакетным боем
    private float[] _fx = Array.Empty<float>();
    private float[] _fz = Array.Empty<float>();
    private GodotObject[] _unitOf = Array.Empty<GodotObject>();

    private int _capacity;
    private int[] _free = Array.Empty<int>();
    private int _freeCount;
    private int _used;

    // ── ВЕРХНЯЯ ГРАНИЦА ЗАНЯТЫХ СТРОК ──────────────────────────────────────
    // ЁМКОСТЬ ТОЛЬКО РАСТЁТ, А ЖИВЫЕ УБЫВАЮТ. Массивы расширяются под ПИК
    // армии и назад не сжимаются никогда: после большой рубки, где из семи
    // тысяч осталась тысяча, _capacity по-прежнему семь тысяч. А покадровые
    // проходы (FillGrid, BatchSeparation, BatchCombat) обходили ИМЕННО
    // ёмкость — то есть в конце партии впустую перебирали в семь раз больше
    // строк, чем есть бойцов.
    //
    // _top — «за этим номером занятых строк нет». Свободные строки выдаются с
    // КОНЦА списка (см. Grow), поэтому подряд заспавненный отряд занимает
    // подряд идущие номера, и граница держится плотно к живым.
    //
    // Признак занятости ведём ОТДЕЛЬНЫМ массивом, а не битом в _flags: флаги
    // переписывают и пакетная запись поз (WritePoseBatch маскирует GateMask),
    // и SetFlag из GDScript, и «строка освободилась» — величина уровня
    // распределителя, ей нечего делать в одном слове с игровыми признаками
    private bool[] _rowUsed = Array.Empty<bool>();
    private int _top;

    /// За этим номером занятых строк нет. Читают стенды: по нему видно, что
    /// граница действительно опускается после гибели армии, а не стоит на пике
    public int Top() => _top;

    // ── ПЛОТНЫЙ СПИСОК ЖИВЫХ СТРОК, И ОН ОТСОРТИРОВАН (сент. 2026) ─────────
    // _top упирается в самого верхнего живого: при рассеянных потерях (а в бою
    // они именно такие) покадровые проходы перебирали пустые строки до самой
    // верхушки (замер qa_ab/Probe: выбили нижние 1900 из 2000 — вхолостую
    // 1900 строк каждый кадр). Список живых убирает это совсем.
    //
    // ОТСОРТИРОВАННЫЙ — НЕ ПРИХОТЬ, А СОХРАНЕНИЕ ПОВЕДЕНИЯ. FillGrid строит
    // списки ячеек вставкой в голову, то есть порядок обхода строк задаёт
    // порядок СОСЕДЕЙ, а по нему разрешаются ничьи в EnemyAt/BestEnemy/
    // NearestOfSide. Обычный плотный список (удаление свапом с последним)
    // перестаёт быть отсортированным после первой же смерти — и выбор цели в
    // равных ситуациях «поедет» на десятках стендов (разбор — ENGINEERING_LOG,
    // «Roadmap: плотный список живых строк»). Возрастающий список даёт ровно
    // тот же порядок, что прежний скан 0.._top по занятым.
    //
    // Цена порядка — вставка/удаление СДВИГОМ (Array.Copy, двоичный поиск
    // позиции). Событий сотни в секунду, сдвиг — десятки килобайт памяти;
    // против них стоит экономия ИТЕРАЦИИ в каждом из трёх проходов КАЖДЫЙ кадр
    private int[] _liveRows = Array.Empty<int>();
    private int _liveCount;

    private void LiveInsert(int row)
    {
        if (_liveCount >= _liveRows.Length)
            Array.Resize(ref _liveRows, Math.Max(64, _liveRows.Length * 2));
        int at = Array.BinarySearch(_liveRows, 0, _liveCount, row);
        if (at >= 0) return;                    // уже в списке (двойной Alloc невозможен, но пусть)
        at = ~at;
        Array.Copy(_liveRows, at, _liveRows, at + 1, _liveCount - at);
        _liveRows[at] = row;
        _liveCount++;
    }

    private void LiveRemove(int row)
    {
        int at = Array.BinarySearch(_liveRows, 0, _liveCount, row);
        if (at < 0) return;
        Array.Copy(_liveRows, at + 1, _liveRows, at, _liveCount - at - 1);
        _liveCount--;
    }

    // ── БИТЫ ПРИЗНАКОВ (номера обязаны совпадать с ArmySoA.F_*) ────────────
    public const int FPosValid = 1 << 0;
    public const int FRetreating = 1 << 1;
    public const int FSprinting = 1 << 2;
    public const int FSettled = 1 << 3;
    public const int FDisengage = 1 << 4;
    public const int FLocked = 1 << 5;
    public const int FGarrisoned = 1 << 6;
    public const int FClearTrunk = 1 << 7;
    public const int FClearEnemy = 1 << 8;
    public const int FSelected = 1 << 9;
    public const int FWorking = 1 << 10;
    public const int FStepPending = 1 << 11;
    public const int FTrunkIgnore = 1 << 12;
    // Мировая матрица родителя единична — писать можно локальный трансформ.
    // Раньше это было поле бойца (_local_xform) и читалось из пакетного прохода
    // через Variant на каждого сдвинутого; в колонке это один бит
    public const int FLocalXform = 1 << 13;
    /// Бой этого бойца можно считать пакетно: нет замка приказа, стойка не
    /// держит место, не бежит, не отходит, не выходит из боя, есть отряд.
    /// Ставит сам боец вместе с позой: все эти условия он и так проверяет
    public const int FAtkSimple = 1 << 14;
    /// СПЯЩИЙ. Боец жив, стоит на карте, попадает в сетку соседей и блокирует
    /// чужой шаг — но не тикает и не двигается сам (спящая деревня гоблинов до
    /// тридцатой минуты). Пакетное расталкивание его ПРОПУСКАЕТ: разводить
    /// неподвижный строй, который никто не сдвигает, — чистая трата кадра, а
    /// на семистах спящих это измеримые миллисекунды
    public const int FDormant = 1 << 15;
    // ── СПЛЮ ПО КАРТИНКЕ (зеркало Unit._proc_sleeping) ────────────────────
    // Заведён РАДИ ОДНОЙ СТРОКИ в разборе наложения: сдвинутого бойца надо
    // разбудить, иначе стоящий не перерисует себя на новом месте. Будильник
    // (wake_for_lod) — вызов ЧЕРЕЗ ГРАНИЦУ ЯЗЫКОВ по имени метода, и в плотной
    // свалке он шёл почти на каждого сдвинутого — то есть до двух тысяч раз в
    // кадр. При этом сам метод первым же условием выходит: дерущийся боец по
    // картинке не спит, будить его не от чего.
    //
    // Теперь состояние сна лежит битом в колонке, и вызов идёт только тому,
    // кто действительно спит. Бит ведёт GDScript по СОБЫТИЮ (засыпание и
    // пробуждение — редкие), а не каждый кадр
    public const int FSleepDraw = 1 << 16;

    /// ── ПРИКАЗ ИГРОКА ПРОХОДИТ СКВОЗЬ ЧУЖИЕ ТЕЛА ──────────────────────────
    /// Ставится на время замка приказа игрока (см. Unit._forced_move_pass).
    /// ЗАЧЕМ: в плотной свалке враги стоят СО ВСЕХ СТОРОН, лобовая
    /// составляющая шага съедается блокировкой целиком, боковая упирается на
    /// втором проходе — и боец не сдвигается ни на сантиметр. Приказ игрока
    /// принят честно, исполнить его нечем; со стороны это «первый правый клик
    /// не работает, нужен второй».
    /// Второй и последний признак сквозного прохода — FRetreating, и по той же
    /// причине: отряду, которого уводят, перекрытая дорога означает вечное
    /// трение боком о чужую шеренгу
    public const int FOrderPass = 1 << 17;

    // ── ДРЁМА ПЕРЕЗАРЯДКИ ЖИВЁТ В ЯДРЕ (сент. 2026, этап C) ─────────────────
    // Боец в упоре к цели пережидает остывание удара; пока флаг стоит, его
    // GDScript-автомат боя — голый return, а таймер и стражу цели ведёт
    // TickSnooze по колонкам. Это ОДНОРОДНАЯ часть боевого автомата — ровно то
    // условие, под которое прежний полный BatchCombat был оставлен выключенным
    // («смена языка ничего не даёт, если у задачи нет пакетной природы»)
    public const int FAtkSnooze = 1 << 18;

    /// Признаки, приходящие ВМЕСТЕ С ПОЗОЙ и переписываемые целиком
    private const int GateMask = FAtkSimple | FRetreating | FSprinting;

    private const float WorkOverlap = 0.62f;
    // Насколько близко к чужому телу разведение своих не имеет права протолкнуть.
    // То же число, что BLOCK_RADIUS шага (Unit.BLOCK_RADIUS = 0.55): одна и та
    // же «толщина строя» для обеих дорог, которыми боец может сдвинуться
    private const float EnemyPushClear = 0.55f;
    // ── ЖЁСТКОЕ ЯДРО ТЕЛА: БИЛЕТ ПРОХОДА НЕ ОТМЕНЯЕТ ГЕОМЕТРИЮ ─────────────
    // Билет (FOrderPass — выход из свалки по приказу игрока и билет отхода)
    // раньше СНИМАЛ проверку чужих тел целиком: две с половиной метра
    // «выхода» — это больше глубины фаланги в контакте (qa_clash: четыре
    // шеренги сжимаются до 1.2 м), и мечник, получивший приказ в упор к
    // строю, проходил его насквозь как призрак. Теперь билет только СУЖАЕТ
    // радиус тела до ядра: сквозь щель между двумя телами шеренги (0.33-0.55 м
    // между центрами, то есть 0.17-0.28 м до ближайшего) пройти нельзя ни с
    // каким билетом, а выбраться из окружения, где чужие стоят на 0.5 м,
    // можно — ровно то, ради чего билет заводился. То же ядро стережёт
    // бегущего: его скольжение по касательной шло БЕЗ второго прохода и в
    // кривой шеренге заводило внутрь тел. Число — доля BLOCK_RADIUS, дубль
    // в Unit.PASS_CORE_FRAC (запасная дорога _move_blocked)
    private const float PassCoreFrac = 0.55f;
    // Доля шага, добавляемая НАРУЖУ от тела при скольжении под билетом (см.
    // BatchMoveRows). Дубль в Unit.PASS_SLIDE_OUT
    private const float PassSlideOut = 0.25f;
    private const int StepFlagMask =
        FRetreating | FSprinting | FClearTrunk | FClearEnemy | FTrunkIgnore
        | FOrderPass;

    // Номер состояния «мёртв». Отдаётся МЕТОДОМ, а не полем: из GDScript
    // надёжно доступны только методы C#-объекта (поля требуют [Export] и
    // становятся частью инспектора, чего тут не нужно)
    private int DeadState = 5;
    public void SetDeadState(int s) { DeadState = s; }

    // ── СЕТКА ──────────────────────────────────────────────────────────────
    private const float CellBase = 1.0f;
    private const int MaxCells = 1 << 18;
    private const float CoarseCell = 16.0f;
    private const float CoarseInv = 1.0f / CoarseCell;

    // ═══════════════════════════════════════════════════════════════════════
    // СКОЛЬКО СТОРОН ДЕРЖИТ СЕТКА
    // ═══════════════════════════════════════════════════════════════════════
    // Ячейка сетки — это НЕ один список, а по списку на фракцию: скан «есть ли
    // рядом свои» ходит ровно по своему списку, скан «есть ли чужие» — по всем
    // остальным. Ни один из них не перебирает лишних и не проверяет _fac[j] на
    // каждом элементе — ради этого разделение и делалось.
    //
    // ДО ЭТОГО ЗДЕСЬ БЫЛА ДВОЙКА, и это было ЗАПИСАННОЕ В КОДЕ ДОПУЩЕНИЕ
    // «фракций ровно две»: слот считался как `fac == 0 ? 0 : 1`. С появлением
    // третьей стороны (гоблины) допущение сломалось бы молча и в худшую
    // сторону — гоблин и красный оказались бы в одном списке, то есть друг для
    // друга «своими»: не блокировали бы шаг, не искались бы как цели и
    // расталкивались бы как союзники. Теперь слот — это номер фракции.
    //
    // Значение с запасом: 3 занято (игрок / красные / гоблины), 4-й слот —
    // место под нейтралов. Память: массив голов сетки это w*h*Factions int,
    // на типовой карте это единицы мегабайт и он переиспользуется между кадрами.
    public const int Factions = 4;

    /// Номер списка для фракции. Отрицательные и вышедшие за таблицу сводятся
    /// в последний слот: строка без фракции не должна ронять индексацию
    private static int FacSlot(int f)
    {
        if (f < 0 || f >= Factions) return Factions - 1;
        return f;
    }

    private int[] _head = Array.Empty<int>();
    private int[] _next = Array.Empty<int>();
    private int[] _coarse = Array.Empty<int>();
    private int _gw, _gh, _cw, _chh;
    private float _gx0, _gz0;
    private float _gcell = CellBase;
    private float _ginv = 1.0f / CellBase;
    private int _gridN;

    // ── ДИАГНОСТИКА ПАКЕТНОГО ШАГА ─────────────────────────────────────────
    private int BmPending, BmTrunkCalls, BmEnemyScans, BmBlocked;
    public int GetBmPending() => BmPending;
    public int GetBmTrunkCalls() => BmTrunkCalls;
    public int GetBmEnemyScans() => BmEnemyScans;
    public int GetBmBlocked() => BmBlocked;

    // ═══════════════════════════════════════════════════════════════════════
    // РЕЕСТР СТВОЛОВ
    // ═══════════════════════════════════════════════════════════════════════
    // Своя РЕДКАЯ сетка ячейками по ObstCell метров, как и была в GameManager.
    // Переехал сюда потому, что это ПОСЛЕДНИЙ вызов наружу, остававшийся внутри
    // шага: без него пакетный проход не пересекает границу языков вовсе.
    private const float ObstCell = 4.0f;
    private const int TrunkCellCap = 8;
    // Плоское хранилище: клетка → до TrunkCellCap стволов (x, z, r).
    // Словаря нет намеренно — поиск по нему и был половиной цены mb_trunk
    private System.Collections.Generic.Dictionary<long, System.Collections.Generic.List<Vector3>> _trunks
        = new System.Collections.Generic.Dictionary<long, System.Collections.Generic.List<Vector3>>();
    private float _trunkMaxR;

    private static long TrunkKey(int cx, int cz)
    {
        return ((long)cx << 32) ^ (uint)cz;
    }

    public void RegisterTrunk(Vector3 pos, float radius)
    {
        int cx = Mathf.FloorToInt(pos.X / ObstCell);
        int cz = Mathf.FloorToInt(pos.Z / ObstCell);
        long k = TrunkKey(cx, cz);
        if (!_trunks.TryGetValue(k, out var list))
        {
            list = new System.Collections.Generic.List<Vector3>(TrunkCellCap);
            _trunks[k] = list;
        }
        list.Add(new Vector3(pos.X, pos.Z, radius));
        if (radius > _trunkMaxR) _trunkMaxR = radius;
    }

    public void UnregisterTrunk(Vector3 pos)
    {
        int cx = Mathf.FloorToInt(pos.X / ObstCell);
        int cz = Mathf.FloorToInt(pos.Z / ObstCell);
        long k = TrunkKey(cx, cz);
        if (!_trunks.TryGetValue(k, out var list)) return;
        for (int i = 0; i < list.Count; i++)
        {
            var t = list[i];
            float dx = t.X - pos.X;
            float dz = t.Y - pos.Z;
            if (dx * dx + dz * dz < 0.01f)
            {
                list.RemoveAt(i);
                return;
            }
        }
    }

    public void ClearTrunks()
    {
        _trunks.Clear();
        _trunkMaxR = 0.0f;
    }

    public int TrunkCount()
    {
        int n = 0;
        foreach (var kv in _trunks) n += kv.Value.Count;
        return n;
    }

    /// Насколько надо вытолкнуть точку наружу из ближайшего ствола.
    /// Vector3.Zero — свободно. Обходятся ТОЛЬКО клетки, до которых реально
    /// дотягиваемся (та же оговорка, что была в GameManager.trunk_block)
    public Vector3 TrunkBlock(float x, float z, float bodyR)
    {
        if (_trunks.Count == 0) return Vector3.Zero;
        float reach = bodyR + _trunkMaxR;
        const float inv = 1.0f / ObstCell;
        int cx0 = Mathf.FloorToInt((x - reach) * inv);
        int cz0 = Mathf.FloorToInt((z - reach) * inv);
        int cx1 = Mathf.FloorToInt((x + reach) * inv);
        int cz1 = Mathf.FloorToInt((z + reach) * inv);
        for (int cx = cx0; cx <= cx1; cx++)
        {
            for (int cz = cz0; cz <= cz1; cz++)
            {
                if (!_trunks.TryGetValue(TrunkKey(cx, cz), out var list)) continue;
                for (int i = 0; i < list.Count; i++)
                {
                    var t = list[i];
                    float dx = x - t.X;
                    float dz = z - t.Y;
                    float rr = t.Z + bodyR;
                    float d2 = dx * dx + dz * dz;
                    if (d2 >= rr * rr) continue;
                    if (d2 < 1e-8f) return new Vector3(rr, 0.0f, 0.0f);
                    float d = Mathf.Sqrt(d2);
                    float k = (rr - d) / d;
                    return new Vector3(dx * k, 0.0f, dz * k);
                }
            }
        }
        return Vector3.Zero;
    }

    public bool TrunkNear(float x, float z, float radius)
    {
        if (_trunks.Count == 0) return false;
        float reach = radius + _trunkMaxR;
        const float inv = 1.0f / ObstCell;
        int cx0 = Mathf.FloorToInt((x - reach) * inv);
        int cz0 = Mathf.FloorToInt((z - reach) * inv);
        int cx1 = Mathf.FloorToInt((x + reach) * inv);
        int cz1 = Mathf.FloorToInt((z + reach) * inv);
        float rr = reach * reach;
        for (int cx = cx0; cx <= cx1; cx++)
        {
            for (int cz = cz0; cz <= cz1; cz++)
            {
                if (!_trunks.TryGetValue(TrunkKey(cx, cz), out var list)) continue;
                for (int i = 0; i < list.Count; i++)
                {
                    var t = list[i];
                    float dx = x - t.X;
                    float dz = z - t.Y;
                    if (dx * dx + dz * dz < rr) return true;
                }
            }
        }
        return false;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // РАСПРЕДЕЛЕНИЕ СТРОК
    // ═══════════════════════════════════════════════════════════════════════
    public int Capacity() => _capacity;
    public int Used() => _used;

    private void Grow()
    {
        int cap = _capacity + GrowStep;
        Array.Resize(ref _px, cap); Array.Resize(ref _py, cap); Array.Resize(ref _pz, cap);
        Array.Resize(ref _vx, cap); Array.Resize(ref _vz, cap);
        Array.Resize(ref _hp, cap); Array.Resize(ref _hpMax, cap);
        Array.Resize(ref _atkCd, cap); Array.Resize(ref _aggroT, cap);
        Array.Resize(ref _atkReach, cap);
        Array.Resize(ref _sepNX, cap); Array.Resize(ref _sepNZ, cap);
        Array.Resize(ref _sepGo, cap);
        Array.Resize(ref _pressX, cap); Array.Resize(ref _pressZ, cap);
        Array.Resize(ref _pressV, cap); Array.Resize(ref _pressStop, cap);
        Array.Resize(ref _rbB, cap); Array.Resize(ref _rbI, cap);
        Array.Resize(ref _rbBaseY, cap);
        Array.Resize(ref _drawX, cap); Array.Resize(ref _drawY, cap);
        Array.Resize(ref _drawZ, cap); Array.Resize(ref _bobPhase, cap);
        // Новые ячейки привязки к отрисовке обязаны быть «не привязан»
        for (int ri = _capacity; ri < cap; ri++) _rbB[ri] = -1;
        Array.Resize(ref _atkDmg, cap); Array.Resize(ref _atkRange, cap);
        Array.Resize(ref _speed, cap);
        Array.Resize(ref _sepT, cap); Array.Resize(ref _sepR, cap);
        Array.Resize(ref _slX, cap); Array.Resize(ref _slZ, cap);
        Array.Resize(ref _stpX, cap); Array.Resize(ref _stpZ, cap);
        Array.Resize(ref _thX, cap); Array.Resize(ref _thZ, cap); Array.Resize(ref _thY, cap);
        Array.Resize(ref _st, cap); Array.Resize(ref _fac, cap); Array.Resize(ref _sq, cap);
        Array.Resize(ref _flags, cap); Array.Resize(ref _attackers, cap);
        Array.Resize(ref _tgt, cap); Array.Resize(ref _effSpeed, cap);
        Array.Resize(ref _fx, cap); Array.Resize(ref _fz, cap);
        Array.Resize(ref _unitOf, cap);
        Array.Resize(ref _next, cap);
        Array.Resize(ref _free, cap);
        Array.Resize(ref _rowUsed, cap);
        // Свободные строки кладём в обратном порядке: снимаются они с конца, и
        // подряд заспавненный отряд займёт подряд идущие строки — пакетному
        // обходу это ложится в кэш процессора
        for (int i = cap - 1; i >= _capacity; i--)
        {
            _free[_freeCount++] = i;
        }
        _capacity = cap;
    }

    public int AllocFor(GodotObject u)
    {
        int i = Alloc();
        _unitOf[i] = u;
        return i;
    }

    public int Alloc()
    {
        if (_freeCount == 0) Grow();
        int i = _free[--_freeCount];
        _used++;
        _rowUsed[i] = true;
        LiveInsert(i);
        if (i >= _top) _top = i + 1;
        _px[i] = 0; _py[i] = 0; _pz[i] = 0;
        _vx[i] = 0; _vz[i] = 0;
        _hp[i] = 0; _hpMax[i] = 0;
        _atkCd[i] = 0; _aggroT[i] = 0; _atkReach[i] = 0;
        _rbB[i] = -1; _bobPhase[i] = 0;
        _atkDmg[i] = 0; _atkRange[i] = 0; _speed[i] = 0;
        // Фаза разбора наложения разводится по номеру строки: иначе весь отряд,
        // вышедший из барака одним заказом, разбирается в один и тот же кадр
        _sepT[i] = (i & 7) * 0.008f;
        _sepR[i] = 0.0f;
        _stpX[i] = 0; _stpZ[i] = 0;
        _thX[i] = 1e9f; _thZ[i] = 1e9f; _thY[i] = 0;
        _st[i] = 0; _fac[i] = -1; _sq[i] = 0; _flags[i] = 0; _attackers[i] = 0;
        _tgt[i] = -1; _effSpeed[i] = 0.0f;
        return i;
    }

    public void Release(int i)
    {
        if (i < 0 || i >= _capacity) return;
        _flags[i] = 0;
        _st[i] = 0;
        _fac[i] = -1;
        _sq[i] = 0;
        _attackers[i] = 0;
        _tgt[i] = -1;
        _unitOf[i] = null;
        if (_freeCount < _free.Length) _free[_freeCount++] = i;
        _used--;
        // ГРАНИЦА ОПУСКАЕТСЯ ТОЛЬКО С ВЕРХУШКИ. Освободили строку в середине —
        // граница не двигается (за ней ещё есть живые); освободили последнюю —
        // сползаем вниз по уже освободившимся. Стоимость размазана: каждая
        // строка проходится этим спуском не больше одного раза за своё
        // освобождение, то есть амортизированно O(1) на выбывшего
        _rowUsed[i] = false;
        LiveRemove(i);
        if (i == _top - 1)
        {
            while (_top > 0 && !_rowUsed[_top - 1]) _top--;
        }
    }

    public void Clear()
    {
        _freeCount = 0;
        for (int i = _capacity - 1; i >= 0; i--)
        {
            _flags[i] = 0;
            _fac[i] = -1;
            _unitOf[i] = null;
            _free[_freeCount++] = i;
        }
        _used = 0;
        if (_rowUsed.Length > 0) Array.Clear(_rowUsed, 0, _rowUsed.Length);
        _liveCount = 0;
        _top = 0;
        _gw = 0; _gh = 0; _gridN = 0;
    }

    // ── ТОНКИЕ СЕТТЕРЫ ─────────────────────────────────────────────────────
    // Одно число за вызов: их зовёт сам боец оттуда, где он и так менял эту
    // величину. Массивы наружу не отдаются НИКОГДА — см. шапку файла
    public void SetPos(int i, float x, float y, float z) { _px[i] = x; _py[i] = y; _pz[i] = z; }
    public void SetVel(int i, float x, float z) { _vx[i] = x; _vz[i] = z; }
    public void SetHp(int i, float cur, float mx) { _hp[i] = cur; _hpMax[i] = mx; }
    public void SetState(int i, int s) { _st[i] = s; }
    public void SetFaction(int i, int f) { _fac[i] = f; }
    public void SetSquad(int i, int s) { _sq[i] = s; }
    public void SetCombat(int i, float dmg, float rng, float spd)
    { _atkDmg[i] = dmg; _atkRange[i] = rng; _speed[i] = spd; }
    public void SetSlot(int i, float ox, float oz) { if (i >= 0) { _slX[i] = ox; _slZ[i] = oz; } }
    public void SetAttackers(int i, int n) { if (i >= 0 && i < _capacity) _attackers[i] = n; }
    /// Строка цели атаки. Пишется по событию из Unit.set_attack_target
    public void SetTarget(int i, int t) { if (i >= 0 && i < _capacity) _tgt[i] = t; }
    public float FacingX(int i) => (i >= 0 && i < _capacity) ? _fx[i] : 0.0f;
    public float FacingZ(int i) => (i >= 0 && i < _capacity) ? _fz[i] : 0.0f;

    public void WritePose(int i, Vector3 p, Vector3 v, int state)
    {
        if (i < 0) return;
        _px[i] = p.X; _py[i] = p.Y; _pz[i] = p.Z;
        _vx[i] = v.X; _vz[i] = v.Z;
        _st[i] = state;
        _flags[i] |= FPosValid;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ПОЗЫ ПРИНИМАЮТСЯ ПАЧКОЙ — ПО ТОЙ ЖЕ ПРИЧИНЕ, ЧТО И ЗАЯВКИ НА ШАГ
    // ═══════════════════════════════════════════════════════════════════════
    // WritePose выше — переход границы на КАЖДОГО бойца в КАЖДОМ тике. Замер
    // (qa_fx, 3000, фаза контакта): 908 вызовов в кадр по 2.14 мкс — 1.9 мс,
    // вторая по величине статья тика после самого боя. Пропуск неизменившихся
    // поз тут не спасает: в контактном бою почти все подтягиваются, то есть
    // поза меняется у всех.
    //
    // Порядок вызова важен: пачка поз применяется ДО BatchMove. Иначе она
    // затёрла бы уже посчитанный шаг координатой НА НАЧАЛО кадра
    /// `gates` несёт признаки, от которых зависит пакетный бой, а `effSpd` -
    /// эффективную скорость подхода. Они едут ВМЕСТЕ С ПОЗОЙ, а не отдельным
    /// вызовом: массив и так пересылается, лишнее поле в нём бесплатно, а
    /// отдельный сеттер стоил бы перехода границы на бойца - ровно того, от
    /// чего мы и уходим
    // `count` — сколько записей значимы; см. разбор у BatchMoveQueued
    public int WritePoseBatch(int[] rows, float[] xs, float[] ys, float[] zs,
        float[] vxs, float[] vzs, int[] sts, int[] gates, float[] effSpd,
        int count = -1)
    {
        int n = count >= 0 ? Math.Min(count, rows.Length) : rows.Length;
        for (int k = 0; k < n; k++)
        {
            int i = rows[k];
            if (i < 0 || i >= _capacity) continue;
            _px[i] = xs[k]; _py[i] = ys[k]; _pz[i] = zs[k];
            _vx[i] = vxs[k]; _vz[i] = vzs[k];
            _st[i] = sts[k];
            _effSpeed[i] = effSpd[k];
            _flags[i] = (_flags[i] & ~GateMask) | (gates[k] & GateMask) | FPosValid;
        }
        return n;
    }

    public void SetFlag(int i, int bit, bool on)
    {
        if (i < 0 || i >= _capacity) return;
        if (on) _flags[i] |= bit; else _flags[i] &= ~bit;
    }

    public bool HasFlag(int i, int bit)
    {
        if (i < 0 || i >= _capacity) return false;
        return (_flags[i] & bit) != 0;
    }

    public bool PosReady(int i)
    {
        if (i < 0 || i >= _capacity) return false;
        return (_flags[i] & FPosValid) != 0;
    }

    /// Точка строки. Заменяет собой четыре обращения к массивам через ссылку на
    /// чужой объект, которые делал визуальный тик на КАЖДОГО бойца в КАЖДОМ
    /// кадре отрисовки
    public Vector3 Pos(int i)
    {
        if (i < 0 || i >= _capacity) return Vector3.Zero;
        return new Vector3(_px[i], _py[i], _pz[i]);
    }

    /// Точка, если она настоящая; иначе — переданная запасная (позиция узла).
    /// Один вызов вместо «проверить флаг, потом собрать вектор из трёх колонок»
    public Vector3 PosOr(int i, Vector3 fallback)
    {
        if (i < 0 || i >= _capacity || (_flags[i] & FPosValid) == 0) return fallback;
        return new Vector3(_px[i], _py[i], _pz[i]);
    }

    public float PosX(int i) => (i >= 0 && i < _capacity) ? _px[i] : 0.0f;
    public float PosZ(int i) => (i >= 0 && i < _capacity) ? _pz[i] : 0.0f;
    public float PosY(int i) => (i >= 0 && i < _capacity) ? _py[i] : 0.0f;
    public int State(int i) => (i >= 0 && i < _capacity) ? _st[i] : 0;
    public int Faction(int i) => (i >= 0 && i < _capacity) ? _fac[i] : -1;

    /// Сколько сторон держит сетка. Спрашивает стенд: игра и солвер обязаны
    /// сходиться в числе фракций, иначе третья сторона молча склеится со второй
    public int GridFactions() => Factions;
    public int Flags(int i) => (i >= 0 && i < _capacity) ? _flags[i] : 0;

    // ── СНИМКИ КОЛОНОК: ТОЛЬКО ХОЛОДНЫЙ ПУТЬ ───────────────────────────────
    // Отдают КОПИЮ (на границе языков Packed*Array иначе и не передать), и
    // именно поэтому звать их из покадрового кода НЕЛЬЗЯ. Они существуют ради
    // стендов, которые сверяют колонки с узлами, и ради редких проходов вроде
    // разметки боя. Горячие читатели берут PosOr/PosX/PosZ — одно число за вызов
    public float[] SnapshotPx() => (float[])_px.Clone();
    public float[] SnapshotPy() => (float[])_py.Clone();
    public float[] SnapshotPz() => (float[])_pz.Clone();
    public int[] SnapshotFlags() => (int[])_flags.Clone();
    public int[] SnapshotSt() => (int[])_st.Clone();
    public int[] SnapshotFac() => (int[])_fac.Clone();
    public float[] SnapshotHp() => (float[])_hp.Clone();
    public int[] SnapshotSq() => (int[])_sq.Clone();
    public float Hp(int i) => (i >= 0 && i < _capacity) ? _hp[i] : 0.0f;
    public int Squad(int i) => (i >= 0 && i < _capacity) ? _sq[i] : 0;

    // ═══════════════════════════════════════════════════════════════════════
    // СЕТКА
    // ═══════════════════════════════════════════════════════════════════════
    public int GridCells() => _gw * _gh;
    public int GridUnits() => _gridN;
    public float GridCellSize() => _gcell;

    /// ГАБАРИТЫ ПЕРЕСЧИТЫВАЮТСЯ НЕ КАЖДЫЙ КАДР: сперва пробуем разложить по
    /// прежним границам, и только если кто-то вне сетки — считаем заново
    public void RebuildGrid()
    {
        if (_gw == 0)
        {
            RecomputeBounds();
            if (_gw == 0) return;
        }
        if (FillGrid()) return;
        RecomputeBounds();
        if (_gw == 0) return;
        FillGrid();
    }

    private void RecomputeBounds()
    {
        float minx = float.MaxValue, minz = float.MaxValue;
        float maxx = float.MinValue, maxz = float.MinValue;
        int cnt = 0;
        // ПО ПЛОТНОМУ СПИСКУ ЖИВЫХ (см. _liveRows: тот же порядок, без пустых)
        for (int k = 0; k < _liveCount; k++)
        {
            int i = _liveRows[k];
            if ((_flags[i] & FPosValid) == 0) continue;
            float x = _px[i], z = _pz[i];
            if (x < minx) minx = x;
            if (x > maxx) maxx = x;
            if (z < minz) minz = z;
            if (z > maxz) maxz = z;
            cnt++;
        }
        _gridN = cnt;
        if (cnt == 0) { _gw = 0; _gh = 0; return; }
        float cell = CellBase;
        int w, h;
        while (true)
        {
            float inv = 1.0f / cell;
            w = (int)((maxx - minx) * inv) + 3;
            h = (int)((maxz - minz) * inv) + 3;
            if (w * h <= MaxCells || cell > 64.0f) break;
            cell *= 2.0f;
        }
        _gcell = cell;
        _ginv = 1.0f / cell;
        _gx0 = minx - cell;
        _gz0 = minz - cell;
        _gw = w; _gh = h;
        int total = w * h * Factions;
        if (_head.Length < total) Array.Resize(ref _head, total);
        _cw = (int)(w * cell * CoarseInv) + 2;
        _chh = (int)(h * cell * CoarseInv) + 2;
        int ctotal = _cw * _chh * Factions;
        if (_coarse.Length < ctotal) Array.Resize(ref _coarse, ctotal);
    }

    private bool FillGrid()
    {
        if (_gw == 0) return false;
        int used = _gw * _gh * Factions;
        Array.Fill(_head, -1, 0, used);
        Array.Fill(_coarse, 0, 0, _cw * _chh * Factions);
        float gx0 = _gx0, gz0 = _gz0, inv2 = _ginv;
        int cw = _cw, w = _gw, h = _gh;
        int n = 0;
        // ПО ПЛОТНОМУ СПИСКУ ЖИВЫХ (см. _liveRows: тот же порядок, без пустых)
        for (int k = 0; k < _liveCount; k++)
        {
            int i = _liveRows[k];
            if ((_flags[i] & FPosValid) == 0) continue;
            float x = _px[i], z = _pz[i];
            int cx = (int)((x - gx0) * inv2);
            int cz = (int)((z - gz0) * inv2);
            if (cx < 0 || cz < 0 || cx >= w || cz >= h) return false;
            int f = FacSlot(_fac[i]);
            int c = (cz * w + cx) * Factions + f;
            _next[i] = _head[c];
            _head[c] = i;
            {
                int qx = (int)((x - gx0) * CoarseInv);
                int qz = (int)((z - gz0) * CoarseInv);
                _coarse[(qz * cw + qx) * Factions + f] += 1;
            }
            n++;
        }
        _gridN = n;
        return true;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // СКАНЫ СОСЕДЕЙ. Ответы обязаны совпадать с прежними ДО ЗНАКА
    // ═══════════════════════════════════════════════════════════════════════

    public bool EnemyNear(float x, float z, int myFaction, float radius)
    {
        if (_cw == 0) return false;
        int mine = FacSlot(myFaction);
        int cx0 = (int)((x - radius - _gx0) * CoarseInv);
        int cz0 = (int)((z - radius - _gz0) * CoarseInv);
        int cx1 = (int)((x + radius - _gx0) * CoarseInv);
        int cz1 = (int)((z + radius - _gz0) * CoarseInv);
        if (cx1 < 0 || cz1 < 0 || cx0 >= _cw || cz0 >= _chh) return false;
        if (cx0 < 0) cx0 = 0;
        if (cz0 < 0) cz0 = 0;
        if (cx1 >= _cw) cx1 = _cw - 1;
        if (cz1 >= _chh) cz1 = _chh - 1;
        for (int cz = cz0; cz <= cz1; cz++)
        {
            int b = cz * _cw;
            for (int cx = cx0; cx <= cx1; cx++)
            {
                int slot = (b + cx) * Factions;
                for (int f = 0; f < Factions; f++)
                {
                    if (f == mine) continue;
                    if (_coarse[slot + f] > 0) return true;
                }
            }
        }
        return false;
    }

    /// ОКНО ДЛЯ СТЕНДОВ: сколько живых строк стоят ближе `radius` к чужому
    /// живому телу (по колонкам). Инвариант твёрдости строя: шаг и разведение
    /// не пускают ближе BLOCK_RADIUS, и при исправной геометрии на радиусе
    /// ядра (см. PassCoreFrac) ответ обязан быть около нуля. Не покадровый
    /// путь — полный обход живых, зовут только измерители (qa_full_game_4k)
    public int EnemyOverlapCount(float radius) => EnemyOverlapCountFlagged(radius, 0);

    /// То же окно, но считаются только строки, у которых стоят ВСЕ биты
    /// flagMask (0 — все строки). Нужно стендам, чтобы приписать
    /// взаимопроникновение билету прохода (FOrderPass), а не гадать
    public int EnemyOverlapCountFlagged(float radius, int flagMask)
    {
        if (_gw == 0) return 0;
        int dead = DeadState;
        float lim = radius * radius;
        int count = 0;
        for (int k = 0; k < _liveCount; k++)
        {
            int i = _liveRows[k];
            if ((_flags[i] & FPosValid) == 0 || _st[i] == dead) continue;
            if (flagMask != 0 && (_flags[i] & flagMask) != flagMask) continue;
            float x = _px[i], z = _pz[i];
            int cx0 = (int)((x - radius - _gx0) * _ginv);
            int cz0 = (int)((z - radius - _gz0) * _ginv);
            int cx1 = (int)((x + radius - _gx0) * _ginv);
            int cz1 = (int)((z + radius - _gz0) * _ginv);
            if (cx1 < 0 || cz1 < 0 || cx0 >= _gw || cz0 >= _gh) continue;
            if (cx0 < 0) cx0 = 0;
            if (cz0 < 0) cz0 = 0;
            if (cx1 >= _gw) cx1 = _gw - 1;
            if (cz1 >= _gh) cz1 = _gh - 1;
            int mySlot = FacSlot(_fac[i]);
            bool hit = false;
            for (int cz = cz0; cz <= cz1 && !hit; cz++)
            {
                int b = cz * _gw;
                for (int cx = cx0; cx <= cx1 && !hit; cx++)
                {
                    for (int fs = 0; fs < Factions && !hit; fs++)
                    {
                        if (fs == mySlot) continue;
                        int j = _head[(b + cx) * Factions + fs];
                        while (j != -1)
                        {
                            if (j != i && _st[j] != dead)
                            {
                                float dx = x - _px[j], dz = z - _pz[j];
                                if (dx * dx + dz * dz < lim) { hit = true; break; }
                            }
                            j = _next[j];
                        }
                    }
                }
            }
            if (hit) count++;
        }
        return count;
    }

    public int AlliesCountNear(int row, float atX, float atZ, float radius, int limit)
    {
        if (_gw == 0 || row < 0) return 0;
        int cx0 = (int)((atX - radius - _gx0) * _ginv);
        int cz0 = (int)((atZ - radius - _gz0) * _ginv);
        int cx1 = (int)((atX + radius - _gx0) * _ginv);
        int cz1 = (int)((atZ + radius - _gz0) * _ginv);
        if (cx1 < 0 || cz1 < 0 || cx0 >= _gw || cz0 >= _gh) return 0;
        if (cx0 < 0) cx0 = 0;
        if (cz0 < 0) cz0 = 0;
        if (cx1 >= _gw) cx1 = _gw - 1;
        if (cz1 >= _gh) cz1 = _gh - 1;
        int myside = FacSlot(_fac[row]);
        float rSq = radius * radius;
        int found = 0;
        int dead = DeadState;
        for (int cz = cz0; cz <= cz1; cz++)
        {
            int b = cz * _gw;
            for (int cx = cx0; cx <= cx1; cx++)
            {
                int j = _head[(b + cx) * Factions + myside];
                while (j != -1)
                {
                    if (j != row && _st[j] != dead)
                    {
                        float dx = atX - _px[j];
                        float dz = atZ - _pz[j];
                        if (dx * dx + dz * dz < rSq)
                        {
                            found++;
                            if (found >= limit) return found;
                        }
                    }
                    j = _next[j];
                }
            }
        }
        return found;
    }

    public Vector3 AllyOverlap(int row, float atX, float atZ, float minDist, float maxPush)
    {
        if (_gw == 0 || row < 0) return Vector3.Zero;
        int cx0 = (int)((atX - minDist - _gx0) * _ginv);
        int cz0 = (int)((atZ - minDist - _gz0) * _ginv);
        int cx1 = (int)((atX + minDist - _gx0) * _ginv);
        int cz1 = (int)((atZ + minDist - _gz0) * _ginv);
        if (cx1 < 0 || cz1 < 0 || cx0 >= _gw || cz0 >= _gh) return Vector3.Zero;
        if (cx0 < 0) cx0 = 0;
        if (cz0 < 0) cz0 = 0;
        if (cx1 >= _gw) cx1 = _gw - 1;
        if (cz1 >= _gh) cz1 = _gh - 1;
        int myside = FacSlot(_fac[row]);
        float dSq = minDist * minDist;
        float pxa = 0.0f, pza = 0.0f;
        int dead = DeadState;
        for (int cz = cz0; cz <= cz1; cz++)
        {
            int b = cz * _gw;
            for (int cx = cx0; cx <= cx1; cx++)
            {
                int j = _head[(b + cx) * Factions + myside];
                while (j != -1)
                {
                    if (j == row || _st[j] == dead) { j = _next[j]; continue; }
                    float dx = atX - _px[j];
                    float dz = atZ - _pz[j];
                    float dd = dx * dx + dz * dz;
                    if (dd >= dSq) { j = _next[j]; continue; }
                    if (dd < 1e-8f)
                    {
                        // Ровно в одной точке: направление своё у каждого,
                        // иначе куча не расходится, а разъезжается лучами
                        float ang = (row % 251) * (Mathf.Tau / 251.0f);
                        dx = Mathf.Cos(ang) * 0.01f;
                        dz = Mathf.Sin(ang) * 0.01f;
                        dd = dx * dx + dz * dz;
                    }
                    float d = Mathf.Sqrt(dd);
                    float need = (minDist - d) / d;
                    pxa += dx * need;
                    pza += dz * need;
                    j = _next[j];
                }
            }
        }
        float plen = pxa * pxa + pza * pza;
        if (plen <= 1e-10f) return Vector3.Zero;
        if (plen > maxPush * maxPush)
        {
            float k = maxPush / Mathf.Sqrt(plen);
            pxa *= k; pza *= k;
        }
        return new Vector3(pxa, 0.0f, pza);
    }

    public Vector3 EnemyBlock(int row, float tx, float tz, float minDist, bool awayOk = false)
    {
        if (row < 0) return Vector3.Zero;
        int myf = _fac[row];
        int mySlot = FacSlot(myf);
        if (!EnemyNear(tx, tz, myf, minDist)) return Vector3.Zero;
        if (_gw == 0) return Vector3.Zero;
        int cx0 = (int)((tx - minDist - _gx0) * _ginv);
        int cz0 = (int)((tz - minDist - _gz0) * _ginv);
        int cx1 = (int)((tx + minDist - _gx0) * _ginv);
        int cz1 = (int)((tz + minDist - _gz0) * _ginv);
        if (cx1 < 0 || cz1 < 0 || cx0 >= _gw || cz0 >= _gh) return Vector3.Zero;
        if (cx0 < 0) cx0 = 0;
        if (cz0 < 0) cz0 = 0;
        if (cx1 >= _gw) cx1 = _gw - 1;
        if (cz1 >= _gh) cz1 = _gh - 1;
        float lim = minDist * minDist;
        float nx = 0.0f, nz = 0.0f;
        int dead = DeadState;
        for (int cz = cz0; cz <= cz1; cz++)
        {
            int b = cz * _gw;
            for (int cx = cx0; cx <= cx1; cx++)
            {
                for (int fs = 0; fs < Factions; fs++)
                {
                    if (fs == mySlot) continue;
                    int j = _head[(b + cx) * Factions + fs];
                    while (j != -1)
                    {
                        if (j == row || _st[j] == dead) { j = _next[j]; continue; }
                        float dx = tx - _px[j];
                        float dz = tz - _pz[j];
                        float d2 = dx * dx + dz * dz;
                        if (d2 >= lim) { j = _next[j]; continue; }
                        // То же правило, что в ScanBlock: под билетом шаг ПРОЧЬ
                        // от тела не блокируется (дороги обязаны совпадать)
                        if (awayOk && d2 >= 0.0001f)
                        {
                            float cdx = _px[row] - _px[j];
                            float cdz = _pz[row] - _pz[j];
                            if (d2 >= cdx * cdx + cdz * cdz) { j = _next[j]; continue; }
                        }
                        if (d2 < 0.0001f)
                        {
                            float ang = (row % 251) * (Mathf.Tau / 251.0f);
                            nx += Mathf.Cos(ang);
                            nz += Mathf.Sin(ang);
                        }
                        else
                        {
                            float inv = 1.0f / Mathf.Sqrt(d2);
                            nx += dx * inv;
                            nz += dz * inv;
                        }
                        j = _next[j];
                    }
                }
            }
        }
        return new Vector3(nx, 0.0f, nz);
    }

    public int AlliesAhead(int row, float dxDir, float dzDir, float look, float halfWidth)
    {
        if (_gw == 0 || row < 0) return 0;
        float x = _px[row], z = _pz[row];
        float mx = x + dxDir * look * 0.5f;
        float mz = z + dzDir * look * 0.5f;
        float r = look * 0.5f + halfWidth + _gcell;
        int cx0 = (int)((mx - r - _gx0) * _ginv);
        int cz0 = (int)((mz - r - _gz0) * _ginv);
        int cx1 = (int)((mx + r - _gx0) * _ginv);
        int cz1 = (int)((mz + r - _gz0) * _ginv);
        if (cx1 < 0 || cz1 < 0 || cx0 >= _gw || cz0 >= _gh) return 0;
        if (cx0 < 0) cx0 = 0;
        if (cz0 < 0) cz0 = 0;
        if (cx1 >= _gw) cx1 = _gw - 1;
        if (cz1 >= _gh) cz1 = _gh - 1;
        int myside = FacSlot(_fac[row]);
        int count = 0;
        int dead = DeadState;
        for (int cz = cz0; cz <= cz1; cz++)
        {
            int b = cz * _gw;
            for (int cx = cx0; cx <= cx1; cx++)
            {
                int j = _head[(b + cx) * Factions + myside];
                while (j != -1)
                {
                    if (j == row || _st[j] == dead) { j = _next[j]; continue; }
                    float dx = _px[j] - x;
                    float dz = _pz[j] - z;
                    float along = dx * dxDir + dz * dzDir;
                    if (along <= 0.12f || along > look) { j = _next[j]; continue; }
                    float lat = Mathf.Abs(dx * -dzDir + dz * dxDir);
                    if (lat <= halfWidth) count++;
                    j = _next[j];
                }
            }
        }
        return count;
    }

    /// РЯДЫ ЦЕЛОГО ОТРЯДА ЗА ОДИН ПЕРЕХОД ГРАНИЦЫ.
    ///
    /// AlliesAhead считает одного бойца, и звали её персонально: замер
    /// (qa_fps, 4000 юнитов) дал 112 вызовов в кадр по 8.6 мкс — 0.96 мс,
    /// самая дорогая строка всего тика. Работа внутри при этом копеечная:
    /// обойти три десятка ячеек. Дорог был сам путь наружу — два прыжка по
    /// GDScript плюс переход границы на КАЖДОГО бойца.
    ///
    /// Шеренга и так обязана смотреть в одну сторону (см. Unit._phalanx_dir),
    /// поэтому направление одно на весь отряд, а строки приходят пачкой.
    /// Пересчёт ряда идёт раз в четверть секунды на отряд — то есть вместо
    /// сотни переходов в кадр остаётся пять.
    ///
    /// Возвращает массив той же длины, что и rows: ряд для каждой строки
    public int[] SquadRanks(int[] rows, float dxDir, float dzDir,
        float look, float halfWidth)
    {
        int n = rows != null ? rows.Length : 0;
        var outRanks = new int[n];
        if (n == 0 || _gw == 0) return outRanks;
        int dead = DeadState;
        for (int k = 0; k < n; k++)
        {
            int row = rows[k];
            if (row < 0 || row >= _capacity) { outRanks[k] = 0; continue; }
            float x = _px[row], z = _pz[row];
            float mx = x + dxDir * look * 0.5f;
            float mz = z + dzDir * look * 0.5f;
            float r = look * 0.5f + halfWidth + _gcell;
            int cx0 = (int)((mx - r - _gx0) * _ginv);
            int cz0 = (int)((mz - r - _gz0) * _ginv);
            int cx1 = (int)((mx + r - _gx0) * _ginv);
            int cz1 = (int)((mz + r - _gz0) * _ginv);
            if (cx1 < 0 || cz1 < 0 || cx0 >= _gw || cz0 >= _gh) { outRanks[k] = 0; continue; }
            if (cx0 < 0) cx0 = 0;
            if (cz0 < 0) cz0 = 0;
            if (cx1 >= _gw) cx1 = _gw - 1;
            if (cz1 >= _gh) cz1 = _gh - 1;
            int myside = FacSlot(_fac[row]);
            int count = 0;
            for (int cz = cz0; cz <= cz1; cz++)
            {
                int b = cz * _gw;
                for (int cx = cx0; cx <= cx1; cx++)
                {
                    int j = _head[(b + cx) * Factions + myside];
                    while (j != -1)
                    {
                        if (j == row || _st[j] == dead) { j = _next[j]; continue; }
                        float dx = _px[j] - x;
                        float dz = _pz[j] - z;
                        float along = dx * dxDir + dz * dzDir;
                        if (along <= 0.12f || along > look) { j = _next[j]; continue; }
                        float lat = Mathf.Abs(dx * -dzDir + dz * dxDir);
                        if (lat <= halfWidth) count++;
                        j = _next[j];
                    }
                }
            }
            outRanks[k] = count;
        }
        return outRanks;
    }

    public Vector3 NearestEnemyOffset(int row, float radius)
    {
        if (row < 0) return Vector3.Zero;
        float x = _px[row], z = _pz[row];
        int myf = _fac[row];
        int mySlot = FacSlot(myf);
        if (!EnemyNear(x, z, myf, radius)) return Vector3.Zero;
        if (_gw == 0) return Vector3.Zero;
        int cx0 = (int)((x - radius - _gx0) * _ginv);
        int cz0 = (int)((z - radius - _gz0) * _ginv);
        int cx1 = (int)((x + radius - _gx0) * _ginv);
        int cz1 = (int)((z + radius - _gz0) * _ginv);
        if (cx1 < 0 || cz1 < 0 || cx0 >= _gw || cz0 >= _gh) return Vector3.Zero;
        if (cx0 < 0) cx0 = 0;
        if (cz0 < 0) cz0 = 0;
        if (cx1 >= _gw) cx1 = _gw - 1;
        if (cz1 >= _gh) cz1 = _gh - 1;
        float bestSq = radius * radius;
        float bx = 0.0f, bz = 0.0f;
        bool found = false;
        int dead = DeadState;
        for (int cz = cz0; cz <= cz1; cz++)
        {
            int b = cz * _gw;
            for (int cx = cx0; cx <= cx1; cx++)
            {
                for (int fs = 0; fs < Factions; fs++)
                {
                    if (fs == mySlot) continue;
                    int j = _head[(b + cx) * Factions + fs];
                    while (j != -1)
                    {
                        if (j == row || _st[j] == dead) { j = _next[j]; continue; }
                        float dx = _px[j] - x;
                        float dz = _pz[j] - z;
                        float d2 = dx * dx + dz * dz;
                        if (d2 < bestSq) { bestSq = d2; bx = dx; bz = dz; found = true; }
                        j = _next[j];
                    }
                }
            }
        }
        return found ? new Vector3(bx, 0.0f, bz) : Vector3.Zero;
    }

    public GodotObject BestEnemy(int row, float radius, float crowdPenalty)
    {
        if (row < 0) return null;
        float x = _px[row], z = _pz[row];
        int myf = _fac[row];
        int mySlot = FacSlot(myf);
        if (!EnemyNear(x, z, myf, radius)) return null;
        if (_gw == 0) return null;
        int cx0 = (int)((x - radius - _gx0) * _ginv);
        int cz0 = (int)((z - radius - _gz0) * _ginv);
        int cx1 = (int)((x + radius - _gx0) * _ginv);
        int cz1 = (int)((z + radius - _gz0) * _ginv);
        if (cx1 < 0 || cz1 < 0 || cx0 >= _gw || cz0 >= _gh) return null;
        if (cx0 < 0) cx0 = 0;
        if (cz0 < 0) cz0 = 0;
        if (cx1 >= _gw) cx1 = _gw - 1;
        if (cz1 >= _gh) cz1 = _gh - 1;
        float rSq = radius * radius;
        GodotObject best = null;
        float bestScore = float.MaxValue;
        int dead = DeadState;
        for (int cz = cz0; cz <= cz1; cz++)
        {
            int b = cz * _gw;
            for (int cx = cx0; cx <= cx1; cx++)
            {
                for (int fs = 0; fs < Factions; fs++)
                {
                    if (fs == mySlot) continue;
                    int j = _head[(b + cx) * Factions + fs];
                    while (j != -1)
                    {
                        if (j == row || _st[j] == dead) { j = _next[j]; continue; }
                        float dx = x - _px[j];
                        float dz = z - _pz[j];
                        float d2 = dx * dx + dz * dz;
                        if (d2 > rSq) { j = _next[j]; continue; }
                        var u = _unitOf[j];
                        if (u == null || !GodotObject.IsInstanceValid(u)) { j = _next[j]; continue; }
                        // Число целящихся — из КОЛОНКИ, а не из поля объекта:
                        // чтение поля через Variant стоило бы дороже всего скана
                        float score = Mathf.Sqrt(d2) + _attackers[j] * crowdPenalty;
                        if (score < bestScore) { bestScore = score; best = u; }
                        j = _next[j];
                    }
                }
            }
        }
        return best;
    }

    public GodotObject NearestOfSide(float x, float z, int wantSide, float radius)
    {
        if (_gw == 0) return null;
        int cx0 = (int)((x - radius - _gx0) * _ginv);
        int cz0 = (int)((z - radius - _gz0) * _ginv);
        int cx1 = (int)((x + radius - _gx0) * _ginv);
        int cz1 = (int)((z + radius - _gz0) * _ginv);
        if (cx1 < 0 || cz1 < 0 || cx0 >= _gw || cz0 >= _gh) return null;
        if (cx0 < 0) cx0 = 0;
        if (cz0 < 0) cz0 = 0;
        if (cx1 >= _gw) cx1 = _gw - 1;
        if (cz1 >= _gh) cz1 = _gh - 1;
        int side = FacSlot(wantSide);
        GodotObject best = null;
        float bestSq = radius * radius;
        int dead = DeadState;
        for (int cz = cz0; cz <= cz1; cz++)
        {
            int b = cz * _gw;
            for (int cx = cx0; cx <= cx1; cx++)
            {
                int j = _head[(b + cx) * Factions + side];
                while (j != -1)
                {
                    if (_st[j] != dead)
                    {
                        float dx = x - _px[j];
                        float dz = z - _pz[j];
                        float d2 = dx * dx + dz * dz;
                        if (d2 < bestSq)
                        {
                            var u = _unitOf[j];
                            if (u != null && GodotObject.IsInstanceValid(u))
                            {
                                bestSq = d2;
                                best = u;
                            }
                        }
                    }
                    j = _next[j];
                }
            }
        }
        return best;
    }

    /// ПЕРВЫЙ ЖИВОЙ ЧУЖОЙ В РАДИУСЕ ОТ ТОЧКИ — для летящей стрелы.
    ///
    /// От QueryRadius отличается тем, что НЕ СТРОИТ МАССИВ и не отдаёт наружу
    /// список кандидатов: отбор «своих, мёртвых и пустых слотов» делается прямо
    /// здесь, а через границу уходит одно значение. Стрел в воздухе десятки, и
    /// каждая проверяется в каждом кадре полёта — Godot-массив на каждую такую
    /// проверку был отдельной статьёй расхода залпа (правило №1 в CLAUDE.md).
    ///
    /// `fac` — фракция СТРЕЛКА. Цель — всё, что не она: гоблины враждебны всем,
    /// поэтому делить стороны на «мою и противоположную» здесь нельзя.
    /// Ближайшего не ищем намеренно: радиус попадания меньше метра, в нём
    /// физически не помещается двух бойцов настолько по-разному, чтобы выбор
    /// был виден — а прежний GDScript-разбор точно так же брал первого
    public Godot.Node3D EnemyAt(float x, float z, float radius, int fac)
    {
        if (_gw == 0) return null;
        int cx0 = (int)((x - radius - _gx0) * _ginv);
        int cz0 = (int)((z - radius - _gz0) * _ginv);
        int cx1 = (int)((x + radius - _gx0) * _ginv);
        int cz1 = (int)((z + radius - _gz0) * _ginv);
        if (cx1 < 0 || cz1 < 0 || cx0 >= _gw || cz0 >= _gh) return null;
        if (cx0 < 0) cx0 = 0;
        if (cz0 < 0) cz0 = 0;
        if (cx1 >= _gw) cx1 = _gw - 1;
        if (cz1 >= _gh) cz1 = _gh - 1;
        int mySlot = FacSlot(fac);
        float rSq = radius * radius;
        int dead = DeadState;
        for (int cz = cz0; cz <= cz1; cz++)
        {
            int b = cz * _gw;
            for (int cx = cx0; cx <= cx1; cx++)
            {
                int slot = (b + cx) * Factions;
                for (int side = 0; side < Factions; side++)
                {
                    if (side == mySlot) continue;
                    int j = _head[slot + side];
                    while (j != -1)
                    {
                        if (_st[j] == dead) { j = _next[j]; continue; }
                        float dx = x - _px[j];
                        float dz = z - _pz[j];
                        if (dx * dx + dz * dz <= rSq)
                        {
                            var u = _unitOf[j] as Godot.Node3D;
                            if (u != null && GodotObject.IsInstanceValid(u))
                                return u;
                        }
                        j = _next[j];
                    }
                }
            }
        }
        return null;
    }

    /// ВСЕ БОЙЦЫ В РАДИУСЕ. Холодный путь: разбор клика мышью — единственный
    /// скан, которому нужны ОБЕ стороны сразу
    public Godot.Collections.Array QueryRadius(float x, float z, float radius)
    {
        var outArr = new Godot.Collections.Array();
        if (_gw == 0) return outArr;
        int cx0 = (int)((x - radius - _gx0) * _ginv);
        int cz0 = (int)((z - radius - _gz0) * _ginv);
        int cx1 = (int)((x + radius - _gx0) * _ginv);
        int cz1 = (int)((z + radius - _gz0) * _ginv);
        if (cx1 < 0 || cz1 < 0 || cx0 >= _gw || cz0 >= _gh) return outArr;
        if (cx0 < 0) cx0 = 0;
        if (cz0 < 0) cz0 = 0;
        if (cx1 >= _gw) cx1 = _gw - 1;
        if (cz1 >= _gh) cz1 = _gh - 1;
        float rSq = radius * radius;
        for (int cz = cz0; cz <= cz1; cz++)
        {
            int b = cz * _gw;
            for (int cx = cx0; cx <= cx1; cx++)
            {
                int slot = (b + cx) * Factions;
                for (int side = 0; side < Factions; side++)
                {
                    int j = _head[slot + side];
                    while (j != -1)
                    {
                        float dx = x - _px[j];
                        float dz = z - _pz[j];
                        if (dx * dx + dz * dz <= rSq)
                        {
                            var u = _unitOf[j];
                            if (u != null && GodotObject.IsInstanceValid(u))
                                outArr.Add(u);
                        }
                        j = _next[j];
                    }
                }
            }
        }
        return outArr;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ПАКЕТНЫЙ ШАГ МАРША
    // ═══════════════════════════════════════════════════════════════════════
    // Порядок стадий и все формулы — те же, что были в поштучном пути
    // (Unit._move_blocked): вода → ствол → чужой строй → зажим карты → рельеф →
    // запись. Отличие ровно одно: ни одна из стадий больше не выходит за
    // границу языка. Вода — исключение и оговорено ниже.
    public int BatchMove(float limX, float limZ, bool boundsOn, bool waterOn,
        float blockR, float trunkClear, float reliefAmp, GodotObject gm)
    {
        return BatchMoveRows(null, limX, limZ, boundsOn, waterOn, blockR,
            trunkClear, reliefAmp, gm);
    }

    /// `rows` == null — обойти всю ёмкость (запасной путь); иначе только
    /// перечисленные строки, что заметно дешевле: заявок сотни, строк тысячи
    private int BatchMoveRows(int[] rows, float limX, float limZ, bool boundsOn,
        bool waterOn, float blockR, float trunkClear, float reliefAmp, GodotObject gm)
    {
        if (_gw == 0) return 0;
        int dead = DeadState;
        int moved = 0;
        float blockSq = blockR * blockR;
        const float thStep = 0.0625f;   // (0.25 м)² — как Unit.TERRAIN_RECHECK_SQ
        BmPending = 0; BmTrunkCalls = 0; BmEnemyScans = 0; BmBlocked = 0;
        int count = rows != null ? rows.Length : _liveCount;
        for (int k = 0; k < count; k++)
        {
            int i = rows != null ? rows[k] : _liveRows[k];
            if (i < 0 || i >= _capacity) continue;
            int fl = _flags[i];
            if ((fl & FStepPending) == 0) continue;
            _flags[i] = fl & ~FStepPending;
            if ((fl & FPosValid) == 0 || _st[i] == dead) continue;
            float sx = _stpX[i], sz = _stpZ[i];
            if (sx * sx + sz * sz < 1e-8f) continue;
            BmPending++;
            float x = _px[i], z = _pz[i];
            float nx = x + sx, nz = z + sz;
            // ── ВОДА ───────────────────────────────────────────────────────
            // ЕДИНСТВЕННЫЙ вызов наружу, оставшийся в этом проходе, и он
            // выполняется только при живом озере. В текущей карте вода
            // выключена (GameManager.water_active = false), то есть ветка не
            // стоит ничего. Переносить генерацию озера сюда ради этого — цена
            // выше выгоды
            if (waterOn && gm != null)
            {
                if ((bool)gm.Call("is_water", nx, nz))
                {
                    Vector3 slid = (Vector3)gm.Call("slide_around_water",
                        new Vector3(x, 0.0f, z), new Vector3(sx, 0.0f, sz));
                    sx = slid.X; sz = slid.Z;
                    if (sx * sx + sz * sz < 1e-8f) continue;
                    nx = x + sx; nz = z + sz;
                }
            }
            // ── СТВОЛ ДЕРЕВА ───────────────────────────────────────────────
            if ((fl & (FClearTrunk | FTrunkIgnore)) == 0)
            {
                BmTrunkCalls++;
                Vector3 trunk = TrunkBlock(nx, nz, trunkClear);
                if (trunk.X != 0.0f || trunk.Z != 0.0f)
                {
                    // ОБХОД, А НЕ УПОР: убираем составляющую «в ствол»,
                    // касательная остаётся. Лобовой случай отклоняем вбок,
                    // иначе шаг съедается целиком и боец замирает у комля
                    float tl = Mathf.Sqrt(trunk.X * trunk.X + trunk.Z * trunk.Z);
                    float tnx = trunk.X / tl, tnz = trunk.Z / tl;
                    float sp = Mathf.Sqrt(sx * sx + sz * sz);
                    float into = -(sx * tnx + sz * tnz);
                    if (into > 0.0f) { sx += tnx * into; sz += tnz * into; }
                    if (Mathf.Sqrt(sx * sx + sz * sz) < sp * 0.2f)
                    {
                        // Сторона — по номеру строки: соседи расходятся в
                        // РАЗНЫЕ стороны и не собираются в очередь за деревом
                        float sgn = (i & 1) == 0 ? 1.0f : -1.0f;
                        sx = -tnz * sgn * sp;
                        sz = tnx * sgn * sp;
                    }
                    nx = x + sx; nz = z + sz;
                    Vector3 again = TrunkBlock(nx, nz, trunkClear);
                    if (again.X != 0.0f || again.Z != 0.0f)
                    {
                        nx += again.X; nz += again.Z;
                        sx = nx - x; sz = nz - z;
                    }
                    if (sx * sx + sz * sz < 1e-8f) continue;
                }
            }
            // ── ЧУЖОЙ СТРОЙ ────────────────────────────────────────────────
            // ЗДЕСЬ СТОЯЛ FRetreating, И ЭТО БЫЛ «ПРОХОД СКВОЗЬ ФАЛАНГУ».
            // Довод был такой: отряду, которого отзывают в замок, перекрытая
            // дорога означала бы вечное трение о чужую шеренгу. На экране это
            // оборачивалось ровно тем, на что жалуется владелец: отряд ИИ,
            // решивший уйти домой, идёт по прямой И ПРОХОДИТ СКВОЗЬ строй
            // копейщиков, как призрак. Замер qa_mega_battle B2-3: сквозь
            // фалангу прошли 141 отходящий рыцарь из 151.
            //
            // Обычным приказом сквозь строй не проходят (B2-1: 0 из 495) —
            // то есть дыра была ровно одна, и она в отходе. Убрана: отступать
            // теперь надо ВОКРУГ чужой шеренги, а не через неё. Вечного трения
            // это не создаёт — отряд в контакте не отступает вовсе
            // (AICfg.AI_NO_RETREAT_IN_MELEE), а разведение своих ему помогает
            // прежним послаблением (SEP_PASS_RELIEF).
            //
            // FOrderPass остаётся: это билет игрока НА ВЫХОД из свалки, он
            // заработанный и гаснет по факту выхода (Unit._forced_move_pass)
            if ((fl & FClearEnemy) == 0)
            {
                int myf = _fac[i];
                // БИЛЕТ ПРОХОДА СУЖАЕТ ТЕЛО ДО ЯДРА, А НЕ СНИМАЕТ ЕГО (см.
                // PassCoreFrac): выбраться из окружения можно, пройти сквозь
                // сомкнутую шеренгу — нет
                float br = blockR, brSq = blockSq;
                if ((fl & FOrderPass) != 0)
                {
                    br = blockR * PassCoreFrac;
                    brSq = br * br;
                }
                // Дешёвый отсев по редкой сетке — ровно тот же, что делает
                // EnemyBlock: без него скан идёт даже по пустой округе
                if (EnemyNear(nx, nz, myf, br))
                {
                    BmEnemyScans++;
                    float bx = 0.0f, bz = 0.0f;
                    bool awayOk = (fl & FOrderPass) != 0;
                    ScanBlock(i, nx, nz, br, brSq, FacSlot(myf), dead, ref bx, ref bz, awayOk);
                    if (bx != 0.0f || bz != 0.0f)
                    {
                        BmBlocked++;
                        // УПЁРЛИСЬ В ЧУЖОЙ СТРОЙ. Отмечаем на бойце: идущий
                        // отряд обязан ВСТУПИТЬ В БОЙ, а не обтекать шеренгу
                        var ub = _unitOf[i];
                        if (ub != null && GodotObject.IsInstanceValid(ub))
                            ub.Set("_enemy_contact", true);
                        // Напор и автопилот, упёршиеся в ЧУЖОЕ тело, будятся:
                        // дальше решает полный автомат (перехват, ответ)
                        if ((fl & (FRearPress | FAutopilot)) != 0) PressWake(i);
                        float bl = Mathf.Sqrt(bx * bx + bz * bz);
                        float bnx = bx / bl, bnz = bz / bl;
                        float full = Mathf.Sqrt(sx * sx + sz * sz);
                        if ((fl & FSprinting) != 0)
                        {
                            // БЕГУЩИЙ ОБХОДИТ СТРОЙ: шаг РАЗВОРАЧИВАЕТСЯ по
                            // касательной с сохранением длины. Обрезка
                            // оставила бы идущему почти в лоб считанные
                            // сантиметры вбок, и он полз бы вдоль шеренги
                            float tgx = -bnz, tgz = bnx;
                            float lat = tgx * sx + tgz * sz;
                            float s2;
                            if (Mathf.Abs(lat) < full * 0.15f)
                                s2 = (i & 1) == 0 ? 1.0f : -1.0f;
                            else
                                s2 = lat > 0.0f ? 1.0f : -1.0f;
                            sx = tgx * (s2 * full);
                            sz = tgz * (s2 * full);
                            nx = x + sx; nz = z + sz;
                            // Второго прохода ПОЛНЫМ радиусом тут нет
                            // НАМЕРЕННО: скольжение вдоль строя оставляет
                            // бойца на прежнем удалении от тел, и повторная
                            // проверка отменяла бы обход. Но касательная
                            // считается от СУММЫ нормалей, и в кривой или
                            // рваной шеренге она ведёт ВНУТРЬ соседнего тела
                            // (бегущий мечник «протекал» сквозь копейщиков
                            // именно так). Поэтому второй проход есть — по
                            // ЯДРУ тела: скользить вдоль можно, входить в
                            // тело нельзя
                            float cr = blockR * PassCoreFrac;
                            float ax = 0.0f, az = 0.0f;
                            ScanBlock(i, nx, nz, cr, cr * cr, FacSlot(myf), dead, ref ax, ref az);
                            if (ax != 0.0f || az != 0.0f) continue;
                        }
                        else
                        {
                            float into2 = sx * bnx + sz * bnz;
                            if ((fl & FOrderPass) != 0)
                            {
                                // ── ПОД БИЛЕТОМ — СКОЛЬЖЕНИЕ ВДОЛЬ ТЕЛА ─────────
                                // Нормаль bn смотрит ОТ тела наружу, значит шаг
                                // «внутрь» имеет into2 < 0 — снимаем именно
                                // его и оставляем касательную. Ветка ниже (для
                                // всех остальных) снимает составляющую при
                                // into2 > 0, то есть НАРУЖНУЮ, а шаг внутрь
                                // оставляет как есть — и второй проход его
                                // блокирует: идущий пехотинец у чужого тела
                                // ВСТАЁТ, а не скользит. Для него это и есть
                                // тюнингованное «упёрся — дерись» (qa_wall C1,
                                // «щель 0.1 м»), и трогать его нельзя. А вот
                                // билет заведён ровно на то, чтобы ВЫБРАТЬСЯ:
                                // qa_spear C9 — отозванный в гарнизон стоял
                                // 12 с в 0.32 м от одного-единственного врага,
                                // требуя от шага честно обойти его
                                // В ЛОБ — ВЫБИРАЕМ СТОРОНУ, КАК БЕГУЩИЙ. Тело ровно на
                                // пути: касательная остаётся нулевой, сдвиг наружу
                                // ведёт назад, и боец топчется на границе ядра
                                // (qa_disengage D2b: 0.72 м за 2 с при радиусе кольца
                                // 1.03 — ровно ядро от тела на 270°). Сторона — по
                                // чётности строки, длина шага сохраняется
                                {
                                    float tgx = -bnz, tgz = bnx;
                                    float lat = tgx * sx + tgz * sz;
                                    if (Mathf.Abs(lat) < full * 0.15f)
                                    {
                                        float s2 = (i & 1) == 0 ? 1.0f : -1.0f;
                                        sx = tgx * (s2 * full);
                                        sz = tgz * (s2 * full);
                                        into2 = 0.0f;
                                    }
                                }
                                if (into2 < 0.0f) { sx -= bnx * into2; sz -= bnz * into2; }
                                // И ЧУТЬ НАРУЖУ. Нормаль bn считана в НОВОЙ точке
                                // прямого шага, а она ближе к телу, чем текущая;
                                // «касательная» к окружности через неё проходит
                                // на миллиметры БЛИЖЕ к телу, чем стоит боец
                                // (qa_spear C9: 0.302 против 0.3035 м), и правило
                                // «прочь» (awayOk) её честно отвергает — боец
                                // стоял 12 с. Четверть шага наружу это лечит, а
                                // сквозь щель по-прежнему не ведёт: там второе
                                // тело, и к нему это сближение
                                sx += bnx * full * PassSlideOut;
                                sz += bnz * full * PassSlideOut;
                            }
                            else if (into2 > 0.0f) { sx -= bnx * into2; sz -= bnz * into2; }
                            if (sx * sx + sz * sz < 1e-8f) continue;
                            nx = x + sx; nz = z + sz;
                            // Второй проход: боковой шаг тоже упёрся — стоим
                            float ax = 0.0f, az = 0.0f;
                            ScanBlock(i, nx, nz, br, brSq, FacSlot(myf), dead, ref ax, ref az, awayOk);
                            if (ax != 0.0f || az != 0.0f) continue;
                        }
                    }
                }
            }
            // ── КРАЙ МИРА ──────────────────────────────────────────────────
            if (boundsOn)
            {
                if (nx < -limX) nx = -limX; else if (nx > limX) nx = limX;
                if (nz < -limZ) nz = -limZ; else if (nz > limZ) nz = limZ;
            }
            // ── ВЫСОТА РЕЛЬЕФА ─────────────────────────────────────────────
            // Копия формулы Main.get_terrain_height. ЕДИНСТВЕННЫЙ ИСТОЧНИК
            // высоты по-прежнему там, и меняться они обязаны вместе
            float tdx = nx - _thX[i];
            float tdz = nz - _thZ[i];
            if (tdx * tdx + tdz * tdz > thStep)
            {
                _thX[i] = nx; _thZ[i] = nz;
                _thY[i] = reliefAmp != 0.0f
                    ? reliefAmp * (
                        0.55f * Mathf.Sin(nx * 0.031f + nz * 0.017f)
                      + 0.30f * Mathf.Sin(nx * 0.013f - nz * 0.041f + 1.7f)
                      + 0.15f * Mathf.Sin(nx * 0.077f + nz * 0.059f + 3.1f))
                    : 0.0f;
            }
            float ny = _thY[i];
            _px[i] = nx; _py[i] = ny; _pz[i] = nz;
            var u2 = _unitOf[i];
            if (u2 == null || !GodotObject.IsInstanceValid(u2)) continue;
            // Локальный трансформ вдвое дешевле мирового под неподвижным World.
            // Признак читается ИЗ КОЛОНКИ: поле объекта здесь стоило бы
            // обращения через Variant на каждого сдвинутого бойца
            if (u2 is Node3D n3)
            {
                if ((fl & FLocalXform) != 0) n3.Position = new Vector3(nx, ny, nz);
                else n3.GlobalPosition = new Vector3(nx, ny, nz);
            }
            moved++;
        }
        return moved;
    }

    /// Суммарная нормаль ОТ чужих тел к точке. Вынесено из BatchMove, чтобы не
    /// повторять двадцать строк дважды; на стороне C# это инлайнится
    /// awayOk — ТОЛЬКО ПОД БИЛЕТОМ ПРОХОДА: тело, от которого шаг УДАЛЯЕТ,
    /// не блокирует, даже если новая точка ещё внутри радиуса. Без билета
    /// блокируется любая точка внутри радиуса (см. разбор ниже)
    private void ScanBlock(int row, float nx, float nz, float blockR, float blockSq,
        int mySlot, int dead, ref float bx, ref float bz, bool awayOk = false)
    {
        int cx0 = (int)((nx - blockR - _gx0) * _ginv);
        int cz0 = (int)((nz - blockR - _gz0) * _ginv);
        int cx1 = (int)((nx + blockR - _gx0) * _ginv);
        int cz1 = (int)((nz + blockR - _gz0) * _ginv);
        if (cx1 < 0 || cz1 < 0 || cx0 >= _gw || cz0 >= _gh) return;
        if (cx0 < 0) cx0 = 0;
        if (cz0 < 0) cz0 = 0;
        if (cx1 >= _gw) cx1 = _gw - 1;
        if (cz1 >= _gh) cz1 = _gh - 1;
        for (int cz = cz0; cz <= cz1; cz++)
        {
            int b = cz * _gw;
            for (int cx = cx0; cx <= cx1; cx++)
            {
                for (int fs = 0; fs < Factions; fs++)
                {
                    if (fs == mySlot) continue;
                    int j = _head[(b + cx) * Factions + fs];
                    while (j != -1)
                    {
                        if (j == row || _st[j] == dead) { j = _next[j]; continue; }
                        float dx = nx - _px[j];
                        float dz = nz - _pz[j];
                        float d2 = dx * dx + dz * dz;
                        if (d2 >= blockSq) { j = _next[j]; continue; }
                        // ЗАМЕТЬТЕ: без билета блокируется ЛЮБАЯ новая точка
                        // внутри радиуса, в том числе шаг вдоль или прочь от
                        // тела. Правило «запрещено сближение, а не пребывание»
                        // ДЛЯ ВСЕХ пробовали (03.09.2026) и откатили: qa_crowd
                        // A1/A3 — толпа из 24 своих у спящей орды переставала
                        // замирать (дрожание 0.0000 → 0.0647 м): прижатый своими
                        // к чужому телу полз вдоль него вместо того, чтобы
                        // встать. ПОД БИЛЕТОМ оно необходимо: ядро 0.30 меньше
                        // игрового просвета 0.33, боец законно оказывается
                        // внутри, и без этого он заперт (qa_spear C9: 5 из 6
                        // при одном лишь скольжении, 6 из 6 с обоими)
                        if (awayOk && d2 >= 0.0001f)
                        {
                            float cdx = _px[row] - _px[j];
                            float cdz = _pz[row] - _pz[j];
                            if (d2 >= cdx * cdx + cdz * cdz) { j = _next[j]; continue; }
                        }
                        if (d2 < 0.0001f)
                        {
                            float ang = (row % 251) * (Mathf.Tau / 251.0f);
                            bx += Mathf.Cos(ang);
                            bz += Mathf.Sin(ang);
                        }
                        else
                        {
                            float inv = 1.0f / Mathf.Sqrt(d2);
                            bx += dx * inv;
                            bz += dz * inv;
                        }
                        j = _next[j];
                    }
                }
            }
        }
    }

    public void RequestStep(int i, float sx, float sz, int fl)
    {
        if (i < 0 || i >= _capacity) return;
        _stpX[i] = sx;
        _stpZ[i] = sz;
        _flags[i] = (_flags[i] & ~StepFlagMask) | (fl & StepFlagMask) | FStepPending;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ЗАЯВКИ НА ШАГ ПОДАЮТСЯ ПАЧКОЙ, А НЕ ПО ОДНОЙ
    // ═══════════════════════════════════════════════════════════════════════
    // RequestStep выше — по вызову на бойца, то есть по ПЕРЕХОДУ ГРАНИЦЫ на
    // бойца. Замер (qa_fx, 3000, фаза контакта): восемьсот таких переходов в
    // кадр по ~2.2 мкс — полторы миллисекунды на ровном месте, и это при том,
    // что 93 % из них приходят из одной-единственной ветки (подтягивание рядов
    // в бою, 60143 вызова из 64532 за 90 кадров).
    //
    // Здесь заявки принимаются ЧЕТЫРЬМЯ МАССИВАМИ за один переход. Массивы
    // маленькие (по числу реально шагающих, не по ёмкости), собирает их
    // GameManager обычными записями в свои же Packed-массивы — это операция
    // внутри GDScript, а не через границу.
    //
    // Побочная выгода: цикл идёт ПО ЗАЯВКАМ, а не по всей ёмкости строк, то
    // есть исчезает и холостой проход по трём тысячам записей ради восьмисот.
    // `count` — сколько записей в массивах ЗНАЧИМЫ. Очередь на стороне
    // GDScript держит ёмкость и не пересобирается между кадрами (иначе на
    // каждый элемент шёл бы append с проверкой ёмкости), поэтому длина массива
    // говорит о его ВМЕСТИМОСТИ, а не о числе заявок. Значение -1 означает
    // «весь массив» — так зовут старые стенды
    public int BatchMoveQueued(int[] rows, float[] xs, float[] zs, int[] fls,
        float limX, float limZ, bool boundsOn, bool waterOn,
        float blockR, float trunkClear, float reliefAmp, GodotObject gm,
        int count = -1)
    {
        int n = count >= 0 ? Math.Min(count, rows.Length) : rows.Length;
        for (int k = 0; k < n; k++)
        {
            int i = rows[k];
            if (i < 0 || i >= _capacity) continue;
            _stpX[i] = xs[k];
            _stpZ[i] = zs[k];
            _flags[i] = (_flags[i] & ~StepFlagMask) | (fls[k] & StepFlagMask) | FStepPending;
        }
        // Проход — по ПЛОТНОМУ СПИСКУ ЖИВЫХ, а не по массиву очереди: заявки
        // тылового напора (RearPressPass) кладут FStepPending мимо очереди и
        // обязаны пройти ту же геометрию. Строки без заявки отсеивает первый
        // же флаг — обход живых этим не дорожает
        return BatchMoveRows(null, limX, limZ, boundsOn, waterOn, blockR,
            trunkClear, reliefAmp, gm);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ПАКЕТНОЕ РАЗВЕДЕНИЕ НАЛОЖИВШИХСЯ СОЮЗНИКОВ
    // ═══════════════════════════════════════════════════════════════════════
    // Правило не изменилось ни на йоту: поправка монотонна (только наружу и
    // только пока есть наложение), у идущего по приказу из неё вырезается
    // составляющая ПРОТИВ курса, за край карты она не выталкивает и в воду не
    // выдавливает.
    /// Личный радиус расталкивания строки. Ноль возвращает её к общей
    /// дистанции. Ставится один раз при рождении бойца, в покадровый путь не
    /// входит — границу GDScript-C# этот вызов пересекает не чаще спавна
    public void SetSepRadius(int row, float r)
    {
        if (row < 0 || row >= _capacity) return;
        _sepR[row] = r > 0.0f ? r : 0.0f;
    }

    public float GetSepRadius(int row)
    {
        if (row < 0 || row >= _capacity) return 0.0f;
        return _sepR[row];
    }

    // ═══════════════════════════════════════════════════════════════════════
    // РАЗБОР НАЛОЖЕНИЯ. crossSquad — ВО СКОЛЬКО РАЗ ШИРЕ ДЕРЖАТСЯ ЧУЖИЕ ОТРЯДЫ
    // ═══════════════════════════════════════════════════════════════════════
    // Жалоба владельца: десять отрядов, посланных в одну точку, спрессовываются
    // в комок размером в два. Так и было, и причина ровно одна: расталкивание
    // не различало «сосед по шеренге» и «боец чужого отряда, влезший в мой
    // строй». Норма у них была общая — самый плотный строевой интервал, — и
    // десять отрядов честно укладывались в него, как один.
    //
    // ПОЧЕМУ ЭТО РЕШАЕТСЯ ЗДЕСЬ, А НЕ ОТТАЛКИВАНИЕМ ЦЕНТРОВ ОТРЯДОВ. Центр
    // отряда — величина производная (медиана по осям, GameManager._centroid_of),
    // и двигать по ней людей означало бы завести вторую, параллельную механику
    // перемещения: с силами, с затуханием, с борьбой против разметки строя.
    // Ровно от этого в проекте уже отказались однажды («союзники друг друга не
    // толкают», см. Unit.SEP_MIN_DIST). Здесь же ничего нового не появляется
    // вовсе: та же монотонная поправка, тот же такт, та же мёртвая зона —
    // меняется ОДНО ЧИСЛО в зависимости от того, свой это сосед по отряду или
    // чужой. Строй внутри отряда остаётся ровно таким же плотным, каким был.
    //
    // ОТРЯД 0 — ЭТО «БЕЗ ОТРЯДА» (рабочие, одиночки, гарнизон), и для него
    // расширение не действует ни в какую сторону: иначе артель рабочих у одной
    // жилы разъезжалась бы вдвое шире положенного, а причин у неё держать
    // строевую дистанцию нет никаких.
    //
    // ЦЕНА. Радиус скана берётся по БОЛЬШЕЙ из двух норм, то есть на ячейку-две
    // шире прежнего; сравнение внутри — один int против int на соседа.
    /// trunkClear — личный зазор бойца до ствола. Ноль отключает ВЫТАЛКИВАНИЕ
    /// ИЗ СТВОЛА (см. блок в цикле): разбор наложения — единственный проход,
    /// который обходит ВСЕХ живых, включая стоящих, и потому единственное
    /// место, где застрявшему вообще можно помочь
    public int BatchSeparation(float delta, float minDist, float maxStep, float interval,
        float limX, float limZ, int movingState, int attackingState, bool waterOn,
        GodotObject gm, float deadzone, float reliefAmp, float crossSquad = 1.0f,
        float passRelief = 1.0f, float trunkClear = 0.0f)
    {
        if (_gw == 0) return 0;
        int dead = DeadState;
        float maxSq = maxStep * maxStep;
        float nearD = Mathf.Max(minDist - deadzone, 0.0f);
        float nearSq = nearD * nearD;
        if (crossSquad < 1.0f) crossSquad = 1.0f;
        // ═══ ФАЗА РАСЧЁТА (этап D2) ════════════════════════════════════════
        // Читает СНИМОК позиций (до фазы применения никто их не двигает),
        // пишет только скрэтч СВОЕЙ строки и свой таймер — поэтому диапазоны
        // строк можно считать в параллель без единого лока, а результат
        // одинаков при любом числе потоков
        void ComputeRange(int lo, int hi)
        {
        for (int li = lo; li < hi; li++)
        {
            int i = _liveRows[li];
            if ((_flags[i] & (FPosValid | FDormant)) != FPosValid) continue;
            int s = _st[i];
            if (s == dead) continue;
            // ЛИЧНЫЙ РАДИУС ПЕРЕКРЫВАЕТ ОБЩИЙ. Поправка считается по СВОЕЙ
            // норме каждого: крупный сосед отходит дальше, мелкий — на своё.
            // Равновесие пары выходит по большему из двух радиусов, потому что
            // тот, кому тесно, продолжает отталкиваться, а поправка монотонна
            float myMin = minDist;
            float myNearSq = nearSq;
            float own = _sepR[i];
            if (own > 0.0f)
            {
                myMin = own;
                float ownNear = Mathf.Max(own - deadzone, 0.0f);
                myNearSq = ownNear * ownNear;
            }
            if ((_flags[i] & FWorking) != 0)
            {
                float w = myMin * WorkOverlap;
                float wNear = Mathf.Max(w - deadzone, 0.0f);
                myMin = w; myNearSq = wNear * wNear;
            }
            // ── НОРМА ДЛЯ ЧУЖОГО ОТРЯДА ────────────────────────────────────
            // Считается ОТ УЖЕ ГОТОВОЙ личной нормы, поэтому и крупный габарит
            // (_sepR), и поблажка работающему (WorkOverlap) переносятся на неё
            // сами собой, без второй копии тех же развилок
            int mySq = _sq[i];
            float crossMin = myMin;
            float crossNearSq = myNearSq;
            if (crossSquad > 1.0f && mySq != 0)
            {
                crossMin = myMin * crossSquad;
                float cNear = Mathf.Max(crossMin - deadzone, 0.0f);
                crossNearSq = cNear * cNear;
            }
            float t = _sepT[i] - delta;
            if (t > 0.0f) { _sepT[i] = t; continue; }
            _sepT[i] = interval;
            float x = _px[i], z = _pz[i];
            // Скан по БОЛЬШЕЙ из норм: сосед из чужого отряда обязан попасть в
            // просмотр, даже если по своей норме он уже достаточно далеко
            float scanR = crossMin;
            int cx0 = (int)((x - scanR - _gx0) * _ginv);
            int cz0 = (int)((z - scanR - _gz0) * _ginv);
            int cx1 = (int)((x + scanR - _gx0) * _ginv);
            int cz1 = (int)((z + scanR - _gz0) * _ginv);
            if (cx0 < 0) cx0 = 0;
            if (cz0 < 0) cz0 = 0;
            if (cx1 >= _gw) cx1 = _gw - 1;
            if (cz1 >= _gh) cz1 = _gh - 1;
            int myside = FacSlot(_fac[i]);
            float pxa = 0.0f, pza = 0.0f;
            for (int cz = cz0; cz <= cz1; cz++)
            {
                int b = cz * _gw;
                for (int cx = cx0; cx <= cx1; cx++)
                {
                    int j = _head[(b + cx) * Factions + myside];
                    while (j != -1)
                    {
                        if (j == i || _st[j] == dead) { j = _next[j]; continue; }
                        // Своя шеренга держится вплотную, чужой отряд — шире
                        // (см. шапку). Ноль в любой из сторон означает «вне
                        // отрядов» и расширения не даёт
                        int oSq = _sq[j];
                        float lim = myMin;
                        float limNearSq = myNearSq;
                        bool otherSquad = oSq != mySq && oSq != 0 && mySq != 0;
                        if (otherSquad)
                        {
                            lim = crossMin;
                            limNearSq = crossNearSq;
                        }
                        // ── ПРОХОД СКВОЗЬ СОЮЗНЫЙ СТРОЙ ───────────────────
                        // Жалоба владельца: «отряды при прохождении друг через
                        // друга застревают, дёргаются и блокируют движение».
                        //
                        // Масок коллизий в игре нет вовсе — союзники и так
                        // проходят друг сквозь друга геометрически. Заклинивал
                        // их ИМЕННО ЭТОТ разбор, и вдвойне: для ЧУЖОГО отряда
                        // норма расстояния здесь ещё и УМНОЖАЕТСЯ (crossSquad =
                        // 1.6), то есть союзные отряды расталкиваются СИЛЬНЕЕ,
                        // чем свои по шеренге. Идущий упирался в стоящих, те
                        // упирались в него — и оба топтались.
                        //
                        // Правило: если ОДИН из пары идёт, а ДРУГОЙ стоит, и
                        // они из разных отрядов — расширение снимается, а сама
                        // норма ослабляется до passRelief. Тела при этом не
                        // слипаются: личная норма остаётся, просто мягкая.
                        if (otherSquad && passRelief < 1.0f)
                        {
                            bool iMove = _st[i] == movingState;
                            bool oMove = _st[j] == movingState;
                            if (iMove != oMove)
                            {
                                lim = myMin * passRelief;
                                float pNear = Mathf.Max(lim - deadzone, 0.0f);
                                limNearSq = pNear * pNear;
                            }
                        }
                        float dx = x - _px[j];
                        float dz = z - _pz[j];
                        float dd = dx * dx + dz * dz;
                        // МЁРТВАЯ ЗОНА: сосед, стоящий чуть теснее нормы, в
                        // расчёт не идёт — иначе строй перетаптывается вечно
                        if (dd >= limNearSq) { j = _next[j]; continue; }
                        if (dd < 1e-8f)
                        {
                            float ang = (i % 251) * (Mathf.Tau / 251.0f);
                            dx = Mathf.Cos(ang) * 0.01f;
                            dz = Mathf.Sin(ang) * 0.01f;
                            dd = dx * dx + dz * dz;
                        }
                        float d = Mathf.Sqrt(dd);
                        float need = (lim - d) / d;
                        pxa += dx * need;
                        pza += dz * need;
                        j = _next[j];
                    }
                }
            }
            // ── ВЫТАЛКИВАНИЕ ИЗ СТВОЛА ─────────────────────────────────────
            // ЖАЛОБА ВЛАДЕЛЬЦА: «рабочий зашёл внутрь коллизии дерева и
            // бесконечно дёргается на месте».
            //
            // Обход стволов в шаге умеет ровно ОДНО — не пускать внутрь. Он
            // срабатывает, когда боец ДЕЛАЕТ ШАГ, и правит НОВУЮ точку;
            // вытолкнуть того, кто уже внутри и СТОИТ (рубит, строит, ждёт),
            // некому вовсе: шага нет — обхода нет. А внутрь его заводит и
            // разбор наложения, и доводка к стволу, и выключение стволов
            // детектором зацикливания.
            //
            // Здесь — единственный проход, который обходит ВСЕХ живых, а не
            // только идущих, и делает это целиком внутри C#: перехода границы
            // языков не добавляется ни одного. Поправка складывается с
            // расталкиванием и так же зажимается maxStep, поэтому боец
            // ВЫПОЛЗАЕТ из ствола, а не выпрыгивает.
            //
            // FTrunkIgnore не трогаем: этот признак означает «боец признан
            // наматывающим круги, стволы ему временно выключены», и выталкивать
            // его отсюда значило бы отменять побег из тупика
            if (trunkClear > 0.0f && (_flags[i] & FTrunkIgnore) == 0)
            {
                Vector3 tOut = TrunkBlock(x, z, trunkClear);
                if (tOut.X != 0.0f || tOut.Z != 0.0f) { pxa += tOut.X; pza += tOut.Z; }
            }
            float plen = pxa * pxa + pza * pza;
            if (plen <= 1e-10f) continue;
            if (plen > maxSq)
            {
                float k = maxStep / Mathf.Sqrt(plen);
                pxa *= k; pza *= k;
            }
            // ИДУЩЕГО ПО ПРИКАЗУ ПОПРАВКА НЕ ОТБРАСЫВАЕТ НАЗАД
            if (s == movingState || s == attackingState)
            {
                float vxx = _vx[i], vzz = _vz[i];
                float vlen = Mathf.Sqrt(vxx * vxx + vzz * vzz);
                if (vlen > 0.001f)
                {
                    float nx0 = vxx / vlen, nz0 = vzz / vlen;
                    float along = pxa * nx0 + pza * nz0;
                    if (along < 0.0f)
                    {
                        pxa -= nx0 * along;
                        pza -= nz0 * along;
                        if (Mathf.Abs(pxa) < 1e-5f && Mathf.Abs(pza) < 1e-5f) continue;
                    }
                }
            }
            // КРАЙ КАРТЫ. Зажим РАСШИРЕН текущей точкой: поправка вправе не
            // пускать за край, но не вправе затаскивать внутрь того, кто уже
            // снаружи (стенды работают в сотнях метров от центра карты)
            float nx2 = Mathf.Clamp(x + pxa, Mathf.Min(-limX, x), Mathf.Max(limX, x));
            float nz2 = Mathf.Clamp(z + pza, Mathf.Min(-limZ, z), Mathf.Max(limZ, z));
            // ── РАЗВЕДЕНИЕ СВОИХ НЕ ИМЕЕТ ПРАВА ПРОТОЛКНУТЬ В ЧУЖОЙ СТРОЙ ──
            // Этот проход разводит ТОЛЬКО союзников и о чужих телах не знал
            // вовсе. В плотной свалке поправка от своих же напирающих сзади
            // выталкивала бойца прямо СКВОЗЬ вражескую шеренгу — так рыцари
            // на чардже проходили копейщиков насквозь, не получив ни укола.
            // Шаг движения такую проверку делает (BatchMoveRows), а этот —
            // нет; теперь делает. Отбрасываем поправку целиком, а не режем её
            // по касательной: поправка и так монотонна и повторится на
            // следующем такте, а «скольжение вдоль чужого строя» здесь
            // означало бы протискивание вдоль копий.
            {
                if (EnemyNear(nx2, nz2, _fac[i], EnemyPushClear))
                {
                    float ex = 0.0f, ez = 0.0f;
                    // Под билетом прохода своим разрешено вытолкнуть бойца
                    // ПРОЧЬ от чужого тела (к телу — нет): отозванный в
                    // гарнизон, стоящий в 0.32 м от врага, иначе не выходил
                    // из ядра билета (qa_spear C9: 5 из 6). Без билета
                    // поправка у чужого тела отбрасывается целиком, как было
                    ScanBlock(i, nx2, nz2, EnemyPushClear,
                        EnemyPushClear * EnemyPushClear, FacSlot(_fac[i]), dead, ref ex, ref ez,
                        (_flags[i] & FOrderPass) != 0);
                    if (ex != 0.0f || ez != 0.0f) continue;
                }
            }
            _sepNX[i] = nx2; _sepNZ[i] = nz2; _sepGo[i] = 1;
        }
        }
        int T = CoreThreads;
        if (T > 1 && _liveCount >= 256)
        {
            int n = _liveCount;
            System.Threading.Tasks.Parallel.For(0, T, t =>
                ComputeRange(n * t / T, n * (t + 1) / T));
        }
        else
        {
            ComputeRange(0, _liveCount);
        }
        // ═══ ФАЗА ПРИМЕНЕНИЯ: ПОСЛЕДОВАТЕЛЬНАЯ ════════════════════════════
        // Вода — вызов GDScript, узлы — дерево сцены, пробуждение — Call:
        // потокам сюда нельзя. Порядок применения — порядок списка живых,
        // тот же, что был у однофазного проходa
        int moved = 0;
        for (int li = 0; li < _liveCount; li++)
        {
            int i = _liveRows[li];
            if (_sepGo[i] == 0) continue;
            _sepGo[i] = 0;
            float nx2 = _sepNX[i], nz2 = _sepNZ[i];
            var u = _unitOf[i];
            if (u == null || !GodotObject.IsInstanceValid(u)) continue;
            if (waterOn && gm != null && (bool)gm.Call("is_water", nx2, nz2)) continue;
            float ny = reliefAmp != 0.0f
                ? reliefAmp * (
                    0.55f * Mathf.Sin(nx2 * 0.031f + nz2 * 0.017f)
                  + 0.30f * Mathf.Sin(nx2 * 0.013f - nz2 * 0.041f + 1.7f)
                  + 0.15f * Mathf.Sin(nx2 * 0.077f + nz2 * 0.059f + 3.1f))
                : 0.0f;
            _px[i] = nx2; _py[i] = ny; _pz[i] = nz2;
            if (u is Node3D n3)
            {
                if ((_flags[i] & FLocalXform) != 0) n3.Position = new Vector3(nx2, ny, nz2);
                else n3.GlobalPosition = new Vector3(nx2, ny, nz2);
            }
            // Стоящий боец спит по картинке и своего нового места сам не
            // перерисует. Будим ТОЛЬКО спящего — см. FSleepDraw
            if ((_flags[i] & FSleepDraw) != 0) u.Call("wake_for_lod");
            moved++;
        }
        return moved;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ШАГ ОТРЯДА МАТРИЦЕЙ
    // ═══════════════════════════════════════════════════════════════════════
    public int AdvanceMatrix(int[] rows, float ax, float az, float ny,
        float cx, float cz, float amp)
    {
        float rx = cz, rz = -cx;
        int n = 0;
        for (int k = 0; k < rows.Length; k++)
        {
            int i = rows[k];
            if (i < 0 || i >= _capacity) continue;
            float ox = _slX[i], oz = _slZ[i];
            float wx = ax + rx * ox + cx * oz;
            float wz = az + rz * ox + cz * oz;
            _px[i] = wx; _pz[i] = wz;
            _py[i] = amp != 0.0f
                ? ny + amp * (
                    0.55f * Mathf.Sin(wx * 0.031f + wz * 0.017f)
                  + 0.30f * Mathf.Sin(wx * 0.013f - wz * 0.041f + 1.7f)
                  + 0.15f * Mathf.Sin(wx * 0.077f + wz * 0.059f + 3.1f))
                : ny;
            _flags[i] |= FPosValid;
            n++;
        }
        return n;
    }

    public void PushToNodes(int[] rows)
    {
        for (int k = 0; k < rows.Length; k++)
        {
            int i = rows[k];
            if (i < 0 || i >= _capacity) continue;
            var u = _unitOf[i];
            if (u == null || !GodotObject.IsInstanceValid(u)) continue;
            var p = new Vector3(_px[i], _py[i], _pz[i]);
            if (u is Node3D n3)
            {
                if ((_flags[i] & FLocalXform) != 0) n3.Position = p;
                else n3.GlobalPosition = p;
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ПАКЕТНЫЙ ПРОХОД БОЯ
    // ═══════════════════════════════════════════════════════════════════════
    // ЗАЧЕМ ИМЕННО ЭТО, А НЕ «весь бой». Замер веток боя (qa_fx, 3000, фаза
    // контакта, 90 кадров):
    //     подход         64532, ИЗ НИХ ПОДТЯГИВАНИЕ РЯДОВ 60143 (93 %)
    //     в досягаемости 12185
    //     ударов             0
    // То есть узкое место боя - не удары и не поиск целей, а ОДНА ветка: боец
    // стоит в свалке и ползёт к своей цели на 55 % скорости. Она чистая
    // арифметика (направление, скорость, шаг), и ей незачем заходить в
    // интерпретатор восемьсот раз в кадр.
    //
    // ЧТО ЗДЕСЬ НЕ СЧИТАЕТСЯ И НЕ БУДЕТ: выбор цели, замок приказа игрока,
    // перехват заслоном, ход стены, сам удар с его звуком, стрелой, толчком и
    // засчитыванием убийства. Всё это остаётся в GDScript - это игровые
    // решения и события, а не математика.
    //
    // Возвращает бойцов, которых пакет НЕ ЗАКРЫЛ: им нужен полный автомат.
    // В фазе контакта это около пятой части состава.
    // ── ОТМЕТКА КАЖДЫЙ КАДР, РАБОТА — ПО ШАРДАМ ────────────────────────────
    // Обход армии в GDScript раздроблен по кадрам (perf_config.shards_for), а
    // этот проход сначала не был — и делал втрое больше работы, чем нужно:
    // подтягивание считалось каждый кадр вместо каждого третьего, а пакетный
    // шаг получал впятеро больше заявок. Замер поймал это сразу (фаза контакта
    // 51.9 → 48.7 к/с, свалка 91.8 → 55.1).
    //
    // Разделены два разных дела:
    //   • ОТМЕТКА «нужен полный автомат» ставится КАЖДЫЙ кадр всем — иначе боец,
    //     до которого обход армии дойдёт на своём кадре, не увидел бы свежей
    //     отметки (разбиения у обхода и у этого прохода разные);
    //   • САМ ШАГ подтягивания считается только для своей доли строк и с
    //     delta, умноженной на число шардов, — ровно как это делает обход армии.
    //     Путь за секунду от этого не меняется, меняется частота опроса.
    // ── ОТВЕТ ОТДАЁТСЯ МАСКОЙ БАЙТ, А НЕ СПИСКОМ ОБЪЕКТОВ ──────────────────
    // Первая версия возвращала Godot.Collections.Array с бойцами, которым нужен
    // полный автомат, и GameManager проставлял им отметку. Замер (qa_fx, 3000,
    // один посев, A/B по выключателю) отверг это начисто:
    //     свалка  58.9 к/с с пакетом против 106.3 без него
    //     сближение 58.1 против 71.5
    // Двести объектов в кадр через границу — это двести маршалов Variant плюс
    // двести записей свойства в GDScript, и стоит это дороже всего, что пакет
    // экономит. Граница дорога В ОБЕ СТОРОНЫ, и возврат — такой же переход,
    // как и вызов.
    //
    // Маска — один массив байт по числу строк (три килобайта на три тысячи),
    // то есть ОДИН маршал за кадр. Боец читает свой байт обычным индексом.
    private byte[] _needMask = Array.Empty<byte>();

    public byte[] BatchCombat(float delta, int attackingState,
        float pullUpSpeed, float pullUpMax, int shards, int phase)
    {
        // Размер держим по ёмкости (боец читает свой байт по номеру строки),
        // а ЧИСТИМ только занятую часть: за границей строк нет ни у кого
        if (_needMask.Length < _capacity) Array.Resize(ref _needMask, _capacity);
        if (_top > 0) Array.Clear(_needMask, 0, _top);
        var need = _needMask;
        int dead = DeadState;
        if (shards < 1) shards = 1;
        float sdelta = delta * shards;
        // ── ПОРЯДОК ПРОВЕРОК = ПОРЯДОК ИХ ЦЕНЫ ─────────────────────────────
        // Состояние — одно чтение массива и сравнение, и оно отсекает почти всю
        // армию: в бою одновременно находится меньшинство. Всё дорогое (объект,
        // проверка его живости, добавление в возвращаемый список) идёт ПОСЛЕ.
        //
        // GodotObject.IsInstanceValid из этого цикла УБРАН, и это не мелочь:
        // он уходит в движок, а звался на все три тысячи строк в каждом кадре —
        // замер поймал регресс сразу (свалка 91.8 → 60.5 к/с). Живость строки и
        // так выражена признаком F_POS_VALID: _exit_tree возвращает строку, и
        // признак гаснет. Сам объект проверяется только у тех немногих, кто
        // реально уходит в GDScript.
        // ПО ПЛОТНОМУ СПИСКУ ЖИВЫХ (см. _liveRows: тот же порядок, без пустых)
        for (int k = 0; k < _liveCount; k++)
        {
            int i = _liveRows[k];
            if (_st[i] != attackingState) continue;
            int fl = _flags[i];
            if ((fl & FPosValid) == 0) continue;
            // Не «простой» бой - полный автомат без разговоров
            if ((fl & FAtkSimple) == 0) { AddNeed(need, i); continue; }
            int t = _tgt[i];
            // Цели нет, она не боец или уже мертва - это событие, а не счёт
            if (t < 0 || t >= _capacity || (_flags[t] & FPosValid) == 0
                || _st[t] == dead)
            { AddNeed(need, i); continue; }
            float dx = _px[t] - _px[i];
            float dz = _pz[t] - _pz[i];
            float d2 = dx * dx + dz * dz;
            float rng = _atkRange[i];
            if (d2 <= rng * rng) { AddNeed(need, i); continue; }  // достаём - бьёт GDScript
            float lim = rng + pullUpMax;
            if (d2 > lim * lim) { AddNeed(need, i); continue; }   // далеко - полный подход
            // ── ПОДТЯГИВАНИЕ РЯДА ──────────────────────────────────────────
            // Шаг делает только своя доля строк — см. шапку про шарды
            if (shards > 1 && (i % shards) != phase) continue;
            float d = Mathf.Sqrt(d2);
            float inv = 1.0f / d;
            float nx = dx * inv, nz = dz * inv;
            float sp = _effSpeed[i] * pullUpSpeed;
            _vx[i] = nx * sp;
            _vz[i] = nz * sp;
            float step = sp * sdelta;
            _stpX[i] = nx * step;
            _stpZ[i] = nz * step;
            _flags[i] = fl | FStepPending;
            _fx[i] = nx;
            _fz[i] = nz;
        }
        return need;
    }

    private static void AddNeed(byte[] need, int i)
    {
        need[i] = 1;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ДРЁМА ПЕРЕЗАРЯДКИ — ТАЙМЕР И СТРАЖА ЦЕЛИ ПО КОЛОНКАМ (этап C)
    // ═══════════════════════════════════════════════════════════════════════
    // Пока строка под FAtkSnooze, боец не входит в GDScript-автомат боя вовсе:
    // здесь тикает его кулдаун и стережётся цель (жива и в досягаемости).
    // Пробуждение — СОБЫТИЕ: строки складываются во внутренний список, и
    // вызывающий забирает их вторым вызовом ТОЛЬКО когда счёт ненулевой —
    // ноль переходов границы и ноль аллокаций в тихий кадр.
    //
    // Дельта здесь ПОЛНОКАДРОВАЯ и проход НЕ шардирован: дрёма — реальное
    // время, и прежний GDScript-вариант тикал её той же арифметикой (delta
    // юниту приходит уже домноженной на шарды). Просыпаться боец обязан:
    //   • за spare до готовности удара (следующий полный тик заново меряет
    //     дистанцию и бьёт штатной веткой — бить по ушедшей цели нельзя
    //     по построению);
    //   • при потере цели (строка освободилась или цель мертва);
    //   • при уходе цели из досягаемости (полный автомат решает, догонять ли).
    private int[] _wokenRows = Array.Empty<int>();
    private float[] _wokenCd = Array.Empty<float>();
    private int _wokenCount;

    // A/B-ручка изоляции: пробуждение по уходу цели из досягаемости
    public static bool SnoozeRangeWake = true;

    public int TickSnooze(float delta, float spare)
    {
        int dead = DeadState;
        _wokenCount = 0;
        for (int k = 0; k < _liveCount; k++)
        {
            int i = _liveRows[k];
            int fl = _flags[i];
            if ((fl & FAtkSnooze) == 0) continue;
            float cd = _atkCd[i] - delta;
            _atkCd[i] = cd;
            bool wake = cd <= spare;
            if (!wake)
            {
                int t = _tgt[i];
                if (t < 0 || t >= _capacity || (_flags[t] & FPosValid) == 0
                    || _st[t] == dead)
                {
                    wake = true;
                }
                else if (SnoozeRangeWake)
                {
                    float dx = _px[t] - _px[i];
                    float dz = _pz[t] - _pz[i];
                    float reach = _atkReach[i];
                    if (dx * dx + dz * dz > reach * reach) wake = true;
                }
            }
            if (!wake) continue;
            _flags[i] = fl & ~FAtkSnooze;
            if (_wokenCount >= _wokenRows.Length)
            {
                int cap2 = Math.Max(64, _wokenRows.Length * 2);
                Array.Resize(ref _wokenRows, cap2);
                Array.Resize(ref _wokenCd, cap2);
            }
            _wokenRows[_wokenCount] = i;
            _wokenCd[_wokenCount] = cd;
            _wokenCount++;
        }
        return _wokenCount;
    }

    // Проснувшиеся — плоским массивом [объект, остаток кулдауна, ...]. Остаток
    // обязателен: пробуждение по потере цели приходит ПОСРЕДИ остывания, и
    // подмена остатка на spare дала бы удар по новой цели раньше срока
    public Godot.Collections.Array TakeWoken()
    {
        var res = new Godot.Collections.Array();
        for (int k = 0; k < _wokenCount; k++)
        {
            var u = _unitOf[_wokenRows[k]];
            if (u == null) continue;
            res.Add(u);
            res.Add(_wokenCd[k]);
        }
        _wokenCount = 0;
        return res;
    }

    /// Взвод дрёмы: кулдаун, досягаемость и флаг — одним переходом границы.
    /// Зовётся ПО СОБЫТИЮ (в момент удара/ожидания), не покадрово
    public void AtkSnoozeArm(int i, float cd, float reach)
    {
        if (i < 0 || i >= _capacity) return;
        _atkCd[i] = cd;
        _atkReach[i] = reach;
        _flags[i] |= FAtkSnooze;
    }

    /// Снятие дрёмы (смена цели, приказ). Остаток кулдауна отдаём вызывающему:
    /// GDScript-поле _attack_timer на время дрёмы было заморожено
    public float AtkSnoozeClear(int i)
    {
        if (i < 0 || i >= _capacity) return 0.0f;
        _flags[i] &= ~FAtkSnooze;
        return _atkCd[i];
    }

    // ═══════════════════════════════════════════════════════════════════════
    // МАСКА ТУМАНА ВОЙНЫ (этап D3)
    // ═══════════════════════════════════════════════════════════════════════
    // Попиксельная часть пересчёта (очистка, штампы кругов с мягкой каймой,
    // накопление «разведано», сборка RGBA) переехала из GDScript: на маске в
    // десятки тысяч ячеек это были самые дорогие циклы кадра логики. GDScript
    // (FogOfWar) остаётся владельцем ИСТОЧНИКОВ (сбор по группам, слияние по
    // ячейкам, постоянные засветы) и ЧТЕНИЯ (is_lit/is_seen идут по его
    // локальным копиям — иначе каждый боец платил бы переход границы за кадр).
    // Копии lit/seen и готовый RGBA возвращаются одним маршалом на пересчёт
    // (раз в UPDATE_INTERVAL, не покадрово).
    private byte[] _fogLit = Array.Empty<byte>();
    private byte[] _fogSeen = Array.Empty<byte>();
    private byte[] _fogRgba = Array.Empty<byte>();
    private int _fogCols, _fogRows;
    private float _fogHalfX, _fogHalfZ, _fogCell, _fogFeather;

    public void FogSetup(int cols, int rows, float halfX, float halfZ,
        float maskCell, float edgeFeather)
    {
        _fogCols = cols; _fogRows = rows;
        _fogHalfX = halfX; _fogHalfZ = halfZ;
        _fogCell = maskCell; _fogFeather = edgeFeather;
        _fogLit = new byte[cols * rows];
        _fogSeen = new byte[cols * rows];
        _fogRgba = new byte[cols * rows * 4];
    }

    public void FogReset()
    {
        Array.Clear(_fogLit, 0, _fogLit.Length);
        Array.Clear(_fogSeen, 0, _fogSeen.Length);
    }

    /// Начальное «разведано» при загрузке партии (слепок сохранения)
    public void FogLoadSeen(byte[] seen)
    {
        if (seen.Length == _fogSeen.Length)
            Array.Copy(seen, _fogSeen, seen.Length);
    }

    private void FogStamp(float x, float z, float radius)
    {
        if (radius <= 0.0f || _fogCols <= 0) return;
        float cx = (x + _fogHalfX) / _fogCell;
        float cz = (z + _fogHalfZ) / _fogCell;
        float rc = radius / _fogCell;
        float inner = Mathf.Max(rc - _fogFeather / _fogCell, 0.0f);
        float inner2 = inner * inner;
        float feather = Mathf.Max(rc - inner, 0.001f);
        int z0 = Math.Max((int)Mathf.Floor(cz - rc), 0);
        int z1 = Math.Min((int)Mathf.Ceil(cz + rc), _fogRows - 1);
        float r2 = rc * rc;
        var lit = _fogLit;
        for (int iz = z0; iz <= z1; iz++)
        {
            float dz = iz + 0.5f - cz;
            float dz2 = dz * dz;
            float half = r2 - dz2;
            if (half <= 0.0f) continue;
            half = Mathf.Sqrt(half);
            int x0 = Math.Max((int)Mathf.Floor(cx - half), 0);
            int x1 = Math.Min((int)Mathf.Ceil(cx + half), _fogCols - 1);
            int b = iz * _fogCols;
            for (int ix = x0; ix <= x1; ix++)
            {
                float dx = ix + 0.5f - cx;
                float d2 = dx * dx + dz2;
                int v = 255;
                if (d2 > inner2)
                    v = (int)(Mathf.Clamp((rc - Mathf.Sqrt(d2)) / feather, 0.0f, 1.0f) * 255.0f);
                int o = b + ix;
                if (v > lit[o]) lit[o] = (byte)v;
            }
        }
    }

    /// Полный пересчёт: источники плоским массивом троек [x, z, r].
    /// Возвращает [lit, seen, rgba] — копии для чтения и текстуры
    public Godot.Collections.Array FogRefresh(float[] src)
    {
        int n = _fogCols * _fogRows;
        Array.Clear(_fogLit, 0, n);
        for (int k = 0; k + 2 < src.Length; k += 3)
            FogStamp(src[k], src[k + 1], src[k + 2]);
        var lit = _fogLit; var seen = _fogSeen; var rgba = _fogRgba;
        for (int i = 0; i < n; i++)
        {
            byte l = lit[i];
            if (l > seen[i]) seen[i] = l;
            int o = i * 4;
            rgba[o] = l;
            rgba[o + 1] = seen[i];
            rgba[o + 2] = 0;
            rgba[o + 3] = 255;
        }
        var res = new Godot.Collections.Array();
        res.Add(lit); res.Add(seen); res.Add(rgba);
        return res;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ТЫЛОВОЙ НАПОР: ШАГ БЕЗ ВХОДА В GDScript (этап D1)
    // ═══════════════════════════════════════════════════════════════════════
    private int[] _pressWakeRows = Array.Empty<int>();
    private int _pressWakeCount;

    private void PressWake(int i)
    {
        _flags[i] &= ~(FRearPress | FAutopilot);
        if (_pressWakeCount >= _pressWakeRows.Length)
            Array.Resize(ref _pressWakeRows, Math.Max(64, _pressWakeRows.Length * 2));
        _pressWakeRows[_pressWakeCount++] = i;
    }

    /// Аренда напора: точка боя, скорость (уже с множителем подтягивания) и
    /// дистанция остановки. Зовётся раз в MELEE_TTL на бойца, не покадрово
    public void RearPressArm(int i, float tx, float tz, float speed, float stop)
    {
        if (i < 0 || i >= _capacity) return;
        _pressX[i] = tx; _pressZ[i] = tz;
        _pressV[i] = speed; _pressStop[i] = stop;
        _flags[i] |= FRearPress;
    }

    public void RearPressClear(int i)
    {
        if (i < 0 || i >= _capacity) return;
        _flags[i] &= ~FRearPress;
    }

    /// Шаг напора всем арендованным строкам. Заявка кладётся тем же способом,
    /// что у очереди шагов (FStepPending), и проходит ту же геометрию
    /// BatchMoveRows — вода, стволы, ЧУЖОЙ СТРОЙ; шардирование то же, что у
    /// личного тика: заявка раз в shards тактов с дельтой delta*shards.
    /// ЧУЖИЕ ТЕЛА НАПОРУ ПРЕГРАДА ВСЕГДА: биты просвета коридора здесь
    /// гасятся — упор в противника обязан родить контакт, а не проход
    public int RearPressPass(float delta, int shards, int phase)
    {
        if (shards < 1) shards = 1;
        float sdelta = delta * shards;
        int armed = 0;
        int dead = DeadState;
        for (int k = 0; k < _liveCount; k++)
        {
            int i = _liveRows[k];
            int fl = _flags[i];
            if ((fl & FRearPress) == 0) continue;
            if ((fl & (FPosValid | FDormant)) != FPosValid || _st[i] == dead)
            { _flags[i] = fl & ~FRearPress; continue; }
            armed++;
            float dx = _pressX[i] - _px[i];
            float dz = _pressZ[i] - _pz[i];
            float d2 = dx * dx + dz * dz;
            float stop = _pressStop[i];
            if (d2 <= stop * stop)
            {
                // Дошёл до дистанции оружия от точки боя — дальше решает
                // полный автомат (бить, перенацелиться, ответить)
                PressWake(i);
                _vx[i] = 0; _vz[i] = 0;
                continue;
            }
            float d = Mathf.Sqrt(d2);
            float nx = dx / d, nz = dz / d;
            float sp = _pressV[i];
            _vx[i] = nx * sp; _vz[i] = nz * sp;
            _fx[i] = nx; _fz[i] = nz;
            if (i % shards != phase) continue;
            _stpX[i] = nx * sp * sdelta;
            _stpZ[i] = nz * sp * sdelta;
            _flags[i] = (fl & ~(FClearEnemy | FOrderPass)) | FStepPending;
        }
        return armed;
    }

    /// Аренда автопилота: скорость и дистанция остановки (колонки напора
    /// переиспользуются — режимы взаимоисключающие). Точка НЕ хранится:
    /// направление берётся на живую строку цели каждый такт
    public void AutopilotArm(int i, float speed, float stop)
    {
        if (i < 0 || i >= _capacity) return;
        _pressV[i] = speed; _pressStop[i] = stop;
        _flags[i] |= FAutopilot;
    }

    public void AutopilotClear(int i)
    {
        if (i < 0 || i >= _capacity) return;
        _flags[i] &= ~FAutopilot;
    }

    /// Шаг автопилота. scanMod задаёт такт стражи «враг рядом»: полный автомат
    /// проверял перехват раз в AGGRO-интервал, здесь та же редкость — скан по
    /// сетке для (i + tick) % scanMod == 0. Радиус — длина руки с запасом:
    /// перехват обязан быть ФИЗИЧЕСКИМ телом на пути (правило замка приказа)
    public int AutopilotPass(float delta, int shards, int phase,
        int tick, int scanMod, float scanR)
    {
        if (shards < 1) shards = 1;
        float sdelta = delta * shards;
        int armed = 0;
        int dead = DeadState;
        for (int k = 0; k < _liveCount; k++)
        {
            int i = _liveRows[k];
            int fl = _flags[i];
            if ((fl & FAutopilot) == 0) continue;
            if ((fl & (FPosValid | FDormant)) != FPosValid || _st[i] == dead)
            { _flags[i] = fl & ~FAutopilot; continue; }
            int t = _tgt[i];
            if (t < 0 || t >= _capacity || (_flags[t] & FPosValid) == 0
                || _st[t] == dead)
            { PressWake(i); continue; }
            armed++;
            float x = _px[i], z = _pz[i];
            float dx = _px[t] - x;
            float dz = _pz[t] - z;
            float d2 = dx * dx + dz * dz;
            float stop = _pressStop[i];
            if (d2 <= stop * stop)
            {
                // Дистанция удара/выстрела достигнута — решает полный автомат
                PressWake(i);
                _vx[i] = 0; _vz[i] = 0;
                continue;
            }
            // Стража перехвата: чужое тело в длине руки — будит немедленно
            if (scanMod > 1 && ((i + tick) % scanMod) == 0
                && EnemyNear(x, z, _fac[i], scanR))
            { PressWake(i); continue; }
            float d = Mathf.Sqrt(d2);
            float nx = dx / d, nz = dz / d;
            float sp = _pressV[i];
            _vx[i] = nx * sp; _vz[i] = nz * sp;
            _fx[i] = nx; _fz[i] = nz;
            if (i % shards != phase) continue;
            _stpX[i] = nx * sp * sdelta;
            _stpZ[i] = nz * sp * sdelta;
            // ЧУЖОЙ СТРОЙ АВТОПИЛОТУ ПРЕГРАДА ВСЕГДА: бит «путь чист»
            // достался от коридора НА МОМЕНТ ВЗВОДА и стареет, а 5-Гц стража
            // выше даёт окно в десяток тактов — qa_wall A1 тут же поймал 7
            // просочившихся. Скан чужих в шаге стоит доли микросекунды на
            // строку, целостность стены — жалоба владельца номер один.
            // Билет прохода гасится по той же причине
            _flags[i] = (fl & ~(FOrderPass | FClearEnemy)) | FStepPending;
        }
        return armed;
    }

    /// Проснувшиеся строки напора — объектами (см. TakeWoken: тот же приём)
    public Godot.Collections.Array TakePressWoken()
    {
        var res = new Godot.Collections.Array();
        for (int k = 0; k < _pressWakeCount; k++)
        {
            var u = _unitOf[_pressWakeRows[k]];
            if (u == null) continue;
            res.Add(u);
        }
        _pressWakeCount = 0;
        return res;
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ОБЩАЯ ОТРИСОВКА: БУФЕРЫ БАКЕТОВ И ПОКАДРОВЫЙ ДОГОН КАРТИНКИ (этап C.1)
    // ═══════════════════════════════════════════════════════════════════════
    // Буферы MultiMesh переехали из GDScript (FarUnitRenderer.Bucket.buf,
    // PackedFloat32Array) во владение ядра: у vis_far, в отличие от боевого
    // автомата, ПАКЕТНАЯ природа — одинаковый догон точки и одинаковые три
    // float на каждого бойца в каждом кадре. GDScript остаётся владельцем
    // ЖИЗНЕННОГО ЦИКЛА бакетов (создание, материалы, foot_drop, раздача
    // слотов) и РЕДКИХ записей (полная запись при смене ленты, кадр походки,
    // урон, скрытие) — это события; покадровый же путь (сглаживание
    // нарисованной точки, покачивание шага, запись позиции) идёт здесь одним
    // проходом BatchVisual по плотному списку живых, и подача в RenderingServer
    // (MultimeshSetBuffer) тоже здешняя — RbFlush, один вызов на грязный бакет.
    //
    // Раскладка буфера — как была: 12 float трансформа + 4 float цвета
    // (TRANSFORM_3D + use_colors), см. шапку FarUnitRenderer.
    private sealed class Rb
    {
        public Rid Multimesh;
        public float[] Buf = Array.Empty<float>();
        public int Capacity;   // в экземплярах
        public bool Dirty;
    }
    private readonly System.Collections.Generic.List<Rb> _rb = new();
    private const int RbStride = 16;

    // ── ПРИВЯЗКА СТРОКИ К СЛОТУ БАКЕТА ─────────────────────────────────────
    // Пишется по событию (регистрация/переезд/снятие в FarUnitRenderer);
    // -1 в _rbB означает «строку в общей отрисовке не ведём»
    private int[] _rbB = Array.Empty<int>();
    private int[] _rbI = Array.Empty<int>();
    private float[] _rbBaseY = Array.Empty<float>();
    private float[] _drawX = Array.Empty<float>();
    private float[] _drawY = Array.Empty<float>();
    private float[] _drawZ = Array.Empty<float>();
    private float[] _bobPhase = Array.Empty<float>();

    /// Разлёт от тарана ведёт картинку сам (Unit._smoothed, свой темп догона):
    /// на это окно строка выходит из пакетного догона
    public const int FVisSelf = 1 << 19;
    /// Нарисованная точка строки инициализирована (первый кадр после привязки
    /// берёт логическую точку, а не догоняет из нуля через полкарты)
    public const int FDrawInit = 1 << 20;

    // ── ТЫЛОВОЙ НАПОР (этап D1) ────────────────────────────────────────────
    // Строка с рангом >= 2 в дерущемся отряде: ей не до решений — она давит к
    // своей свалке. Шаг ей считает RearPressPass (то же подтягивание рядов,
    // что делала ветка _should_pull_up, но без входа в GDScript), а её
    // GDScript-тик пропускается целиком (прецедент — _matrix_driven).
    // Выдаётся АРЕНДОЙ из GameManager._recalc_melee и гаснет там же; будят
    // события: упор в чужое тело (см. BatchMoveRows), удар, смена цели
    public const int FRearPress = 1 << 21;
    // ── АВТОПИЛОТ ПОДХОДА (этап D1) ────────────────────────────────────────
    // Дальний подход к назначенной цели: направление на ЖИВУЮ строку цели
    // считает AutopilotPass, GDScript-автомат не входит. Пробуждения: цель
    // достигнута/пала, упор в чужое тело (BatchMoveRows), враг рядом
    // (периодический скан по сетке — цена перехвата, которую нёс личный тик)
    public const int FAutopilot = 1 << 22;

    public int RbCreate(Rid multimesh)
    {
        _rb.Add(new Rb { Multimesh = multimesh });
        return _rb.Count - 1;
    }

    public void RbEnsure(int b, int instances)
    {
        var r = _rb[b];
        if (instances <= r.Capacity) return;
        Array.Resize(ref r.Buf, instances * RbStride);
        r.Capacity = instances;
        r.Dirty = true;
    }

    public void RbWriteFull(int b, int idx, float x, float y, float z,
        int frame, bool mirror, float flash, float hp)
    {
        var r = _rb[b];
        int o = idx * RbStride;
        var buf = r.Buf;
        buf[o] = 1.0f; buf[o + 1] = 0.0f; buf[o + 2] = 0.0f; buf[o + 3] = x;
        buf[o + 4] = 0.0f; buf[o + 5] = 1.0f; buf[o + 6] = 0.0f; buf[o + 7] = y;
        buf[o + 8] = 0.0f; buf[o + 9] = 0.0f; buf[o + 10] = 1.0f; buf[o + 11] = z;
        buf[o + 12] = frame / 255.0f;
        buf[o + 13] = mirror ? 1.0f : 0.0f;
        buf[o + 14] = flash;
        buf[o + 15] = hp;
        r.Dirty = true;
    }

    public void RbWritePos(int b, int idx, float x, float y, float z)
    {
        var r = _rb[b];
        int o = idx * RbStride;
        r.Buf[o + 3] = x; r.Buf[o + 7] = y; r.Buf[o + 11] = z;
        r.Dirty = true;
    }

    public void RbWriteFrame(int b, int idx, int frame)
    {
        var r = _rb[b];
        r.Buf[idx * RbStride + 12] = frame / 255.0f;
        r.Dirty = true;
    }

    /// Все четыре float цвета слота (стрелы: ось + доля покрытия)
    public void RbWriteColor(int b, int idx, float r, float g, float bl, float a)
    {
        var rb = _rb[b];
        int o = idx * RbStride;
        rb.Buf[o + 12] = r; rb.Buf[o + 13] = g;
        rb.Buf[o + 14] = bl; rb.Buf[o + 15] = a;
        rb.Dirty = true;
    }

    public void RbWriteDmg(int b, int idx, float flash, float hp)
    {
        var r = _rb[b];
        int o = idx * RbStride;
        r.Buf[o + 14] = flash; r.Buf[o + 15] = hp;
        r.Dirty = true;
    }

    public void RbHideSlot(int b, int idx)
    {
        var r = _rb[b];
        Array.Clear(r.Buf, idx * RbStride, RbStride);
        r.Dirty = true;
    }

    public void RbHideAll(int b)
    {
        var r = _rb[b];
        Array.Clear(r.Buf, 0, r.Buf.Length);
        r.Dirty = true;
    }

    /// Окна для СТЕНДОВ: флаг грязности бакета (проверка «неподвижный строй
    /// не грязнит буфер» ловится ровно этим)
    public bool RbDirty(int b) => _rb[b].Dirty;
    public void RbClearDirty(int b) { _rb[b].Dirty = false; }

    /// Окно чтения для СТЕНДОВ: 16 float слота как есть. Не покадровый путь —
    /// аллокация массива здесь допустима (читают только проверки)
    public float[] RbSlot(int b, int idx)
    {
        var r = _rb[b];
        int o = idx * RbStride;
        if (o + RbStride > r.Buf.Length) return Array.Empty<float>();
        var res = new float[RbStride];
        Array.Copy(r.Buf, o, res, 0, RbStride);
        return res;
    }

    /// Подача накопленного в RenderingServer: один MultimeshSetBuffer на
    /// ИЗМЕНИВШИЙСЯ бакет за кадр — тот же контракт, что был у GDScript flush
    public void RbFlush()
    {
        for (int k = 0; k < _rb.Count; k++)
        {
            var r = _rb[k];
            if (!r.Dirty || r.Capacity == 0) continue;
            r.Dirty = false;
            RenderingServer.MultimeshSetBuffer(r.Multimesh, r.Buf);
        }
    }

    /// Привязать строку к слоту бакета. Нарисованная точка приходит от
    /// вызывающего: при переезде между бакетами она обязана сохраниться,
    /// иначе картинка прыгнет на логическую точку
    public void RowBind(int i, int b, int idx, float baseY,
        float dx, float dy, float dz, bool drawInit)
    {
        if (i < 0 || i >= _capacity) return;
        _rbB[i] = b;
        _rbI[i] = idx;
        _rbBaseY[i] = baseY;
        _drawX[i] = dx; _drawY[i] = dy; _drawZ[i] = dz;
        if (drawInit) _flags[i] |= FDrawInit;
        else _flags[i] &= ~FDrawInit;
    }

    public void RowUnbind(int i)
    {
        if (i < 0 || i >= _capacity) return;
        _rbB[i] = -1;
    }

    /// Нарисованная точка строки (читают знамёна/кольца через Unit.draw_position)
    public Vector3 DrawPos(int i)
    {
        if (i < 0 || i >= _capacity || (_flags[i] & FDrawInit) == 0)
            return new Vector3(_px[i], _py[i], _pz[i]);
        return new Vector3(_drawX[i], _drawY[i], _drawZ[i]);
    }

    /// Синхронизация нарисованной точки из GDScript (конец разлёта: картинку
    /// вёл сам боец, ядро продолжает с того же места)
    public void RowSyncDraw(int i, float x, float y, float z)
    {
        if (i < 0 || i >= _capacity) return;
        _drawX[i] = x; _drawY[i] = y; _drawZ[i] = z;
        _flags[i] |= FDrawInit;
    }

    // ── ПОКАДРОВЫЙ ДОГОН: ОДИН ПРОХОД НА ВЕСЬ МИР ──────────────────────────
    // Семантика повторяет быстрый путь Unit.tick_visual дословно:
    //   • X/Z догоняют логическую точку долей lerpK, Y идёт за логикой сразу
    //     (так было и в GDScript: сглаживаются только горизонтали);
    //   • прыжок дальше snapSq — телепорт (гарнизон, постановка стендом),
    //     картинка переставляется мгновенно;
    //   • покачивание шага — sin² по фазе, накапливаемой от ФАКТИЧЕСКОЙ
    //     скорости строки (та же формула, что Unit._update_walk_anim), у
    //     стоящего сбрасывается в ноль тем же кадром;
    //   • неподвижного не переписываем — порог тот же, что у Slot.move_to.
    // Строки под FVisSelf (разлёт) и без привязки пропускаются.
    public void BatchVisual(float delta, float lerpK, float snapSq,
        float bobAmp, float bobSprintMult)
    {
        const float MoveEpsSq = 1e-6f;
        // Проход целиком из чистой математики по колонкам и буферам (записи —
        // только в СВОЮ строку и в СВОЙ слот бакета), поэтому параллелится
        // диапазонами без локов; флаг Dirty — благоприятная гонка (все пишут
        // true). Подача в RenderingServer (RbFlush) остаётся в главном потоке
        void VisRange(int klo, int khi)
        {
        for (int k = klo; k < khi; k++)
        {
            int i = _liveRows[k];
            int b = _rbB[i];
            if (b < 0) continue;
            int fl = _flags[i];
            if ((fl & FVisSelf) != 0) continue;
            float px = _px[i], py = _py[i], pz = _pz[i];
            float sx, sz;
            if ((fl & FDrawInit) == 0)
            {
                sx = px; sz = pz;
                _flags[i] = fl | FDrawInit;
            }
            else
            {
                float ddx = px - _drawX[i];
                float ddz = pz - _drawZ[i];
                if (ddx * ddx + ddz * ddz > snapSq)
                {
                    sx = px; sz = pz;
                }
                else
                {
                    sx = _drawX[i] + ddx * lerpK;
                    sz = _drawZ[i] + ddz * lerpK;
                }
            }
            _drawX[i] = sx; _drawY[i] = py; _drawZ[i] = sz;
            // Покачивание шага — от фактической скорости строки
            float vx = _vx[i], vz = _vz[i];
            float sp2 = vx * vx + vz * vz;
            float bob = 0.0f;
            if (sp2 > 0.01f)
            {
                _bobPhase[i] += delta * Mathf.Sqrt(sp2) * 3.0f;
                float amp = (fl & FSprinting) != 0 ? bobAmp * bobSprintMult : bobAmp;
                float sn = Mathf.Sin(_bobPhase[i]);
                bob = sn * sn * amp;
            }
            else
            {
                _bobPhase[i] = 0.0f;
            }
            // Запись позиции слота: тот же состав, что у Slot.move_to
            var r = _rb[b];
            int o = _rbI[i] * RbStride;
            float wy = py + _rbBaseY[i] + bob;
            var buf = r.Buf;
            float odx = sx - buf[o + 3];
            float ody = wy - buf[o + 7];
            float odz = sz - buf[o + 11];
            if (odx * odx + ody * ody + odz * odz < MoveEpsSq) continue;
            buf[o + 3] = sx; buf[o + 7] = wy; buf[o + 11] = sz;
            r.Dirty = true;
        }
        }
        int T = CoreThreads;
        if (T > 1 && _liveCount >= 256)
        {
            int n = _liveCount;
            System.Threading.Tasks.Parallel.For(0, T, t =>
                VisRange(n * t / T, n * (t + 1) / T));
        }
        else
        {
            VisRange(0, _liveCount);
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ГАБАРИТЫ ОТРЯДА — ЧИСТО ПО КОЛОНКАМ
    // ═══════════════════════════════════════════════════════════════════════
    // ЗДЕСЬ БЫЛ HarvestSquad, И ОН ОКАЗАЛСЯ САМОЙ ДОРОГОЙ ОШИБКОЙ ПЕРЕЕЗДА.
    // Он принимал СПИСОК ОБЪЕКТОВ и читал у каждого три свойства через Variant
    // (_soa, state, global_position). В GDScript это стоило копейки, а через
    // границу языков — 2977 мкс на кадр против прежних 615, то есть ветка
    // squad_corridor подорожала впятеро и съела весь выигрыш пакетных проходов.
    //
    // Снимать точки из УЗЛОВ больше не нужно вовсе: колонку ведут пакетный шаг и
    // разбор наложения, то есть она и есть свежая правда. Осталась чистая
    // арифметика по строкам — один переход границы на отряд вместо трёх на
    // бойца. Список живых бойцов собирает вызывающий: ему он и так нужен.
    //
    // Возвращает [n, cx, cz, radius, watch, faction]
    public Godot.Collections.Array SquadBounds(int[] rows, int dead,
        float aggroR, float intercept)
    {
        float sx = 0.0f, sz = 0.0f;
        int n = 0;
        int fc = -1;
        float watch = aggroR;
        for (int k = 0; k < rows.Length; k++)
        {
            int i = rows[k];
            if (i < 0 || i >= _capacity) continue;
            if ((_flags[i] & FPosValid) == 0 || _st[i] == dead) continue;
            if (fc < 0) fc = _fac[i];
            sx += _px[i]; sz += _pz[i];
            float ar = _atkRange[i] + intercept;
            if (ar > watch) watch = ar;
            n++;
        }
        var res = new Godot.Collections.Array();
        if (n == 0)
        {
            res.Add(0); res.Add(0.0f); res.Add(0.0f); res.Add(0.0f);
            res.Add(watch); res.Add(fc);
            return res;
        }
        float invN = 1.0f / n;
        float cx = sx * invN, cz = sz * invN;
        float rad = 0.0f;
        for (int k = 0; k < rows.Length; k++)
        {
            int i = rows[k];
            if (i < 0 || i >= _capacity) continue;
            if ((_flags[i] & FPosValid) == 0 || _st[i] == dead) continue;
            float dx = _px[i] - cx, dz = _pz[i] - cz;
            float d = Mathf.Sqrt(dx * dx + dz * dz);
            if (d > rad) rad = d;
        }
        res.Add(n); res.Add(cx); res.Add(cz); res.Add(rad); res.Add(watch); res.Add(fc);
        return res;
    }
}
