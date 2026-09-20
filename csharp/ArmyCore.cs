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
    // ── РЕЛЬЕФ: ГОРА И РУСЛО (09.09.2026) ────────────────────────────────
    // Высота земли в ядре считалась ТРЕМЯ КОПИЯМИ одной формулы гармоник; с
    // горой у замка игрока и рекой посередине карты (Main.get_terrain_height)
    // формула стала составной, и копии обязаны совпасть с GDScript — иначе
    // боец на холме уходил бы под землю. Параметры подаёт GameManager
    // (refresh_map_bounds); нули означают «нет горы» / «нет реки».
    // Вода реки проверяется ЗДЕСЬ, без вызова is_water в GDScript на каждый
    // шаг (тот стоил бы два межъязыковых перехода на ходящего бойца);
    // наружу уходит только slide_around_water, и только когда шаг упёрся
    private bool _hillOn = false;
    private float _hillCx, _hillCz, _hillH, _hillSigma2 = 1.0f;
    private bool _riverOn = false;
    private float _riverHalfW, _riverMeander, _riverK, _fordZ, _fordHalf;
    private float _riverDepth, _fordDepth, _riverBank, _riverMargin;
    // Просадка дна, начиная с которой грунт скрыт зеркалом воды (Main.wet_depth).
    // Подаётся числом, а не выводится здесь: правило берега обязано быть ОДНИМ
    // на оба языка — ровно как высота земли (см. Height)
    private float _wetDepth = 0.0f;
    // Русло только в поле карты (|z| <= _riverHalfZ) — см. Main.river_in_field
    private float _riverHalfZ = 1e9f;
    // Плато (Main.plateau_list): по 5 чисел — cx, cz, r_flat, h, ramp_dir
    private float[] _plat = System.Array.Empty<float>();
    private float _platGentle = 14.0f, _platSteep = 4.5f, _platCone = 0.75f;

    public void SetPlateaus(float[] data, float gentle, float steep, float cone)
    {
        _plat = data ?? System.Array.Empty<float>();
        _platGentle = gentle; _platSteep = steep; _platCone = cone;
    }

    // ── СКАЛЫ: МАСКА НЕПРОХОДИМЫХ СКЛОНОВ (спринт 18) ─────────────────────
    // Поиска пути в игре нет, и до сих пор непроходимых склонов не было
    // (обрыв только рисовался стеной). Заказ владельца: боковые скалы
    // возвышенностей — непроходимы. Маска строится один раз при сборке карты
    // по крутизне высоты ядра (та же Height, что у шага): ячейка cell метров,
    // байт на ячейку. Шаг в скалу СКОЛЬЗИТ вдоль неё (по X или по Z), разведение
    // на скалу не выталкивает. Вне маски — проходимо (стенды за краем карты)
    private byte[] _cliff = System.Array.Empty<byte>();
    private int _cliffCols = 0, _cliffRows = 0;
    private float _cliffOx = 0.0f, _cliffOz = 0.0f, _cliffCell = 1.0f;
    private bool _cliffOn = false;
    public int CliffCells = 0;

    public void BuildCliffMask(float ox, float oz, float cell, int cols, int rows,
        float reliefAmp, float slopeThr)
    {
        _cliffCols = cols; _cliffRows = rows; _cliffOx = ox; _cliffOz = oz; _cliffCell = cell;
        _cliff = new byte[Math.Max(cols * rows, 1)];
        CliffCells = 0;
        float h2 = cell * 0.5f;
        for (int r = 0; r < rows; r++)
        {
            float z = oz + (r + 0.5f) * cell;
            for (int c = 0; c < cols; c++)
            {
                float x = ox + (c + 0.5f) * cell;
                // Русло реки в маску НЕ входит: откос берега (RIVER_BANK) по
                // крутизне у самого порога, и с гармониками берег превращался
                // бы в стену — боец не доходил бы до брода (qa_map C1).
                // Скалы — это плато и гора: высота считается БЕЗ просадки русла
                float dhx = DryHeight(x + h2, z, reliefAmp) - DryHeight(x - h2, z, reliefAmp);
                float dhz = DryHeight(x, z + h2, reliefAmp) - DryHeight(x, z - h2, reliefAmp);
                float slope = Math.Max(Math.Abs(dhx), Math.Abs(dhz)) / cell;
                if (slope > slopeThr) { _cliff[r * cols + c] = 1; CliffCells++; }
            }
        }
        _cliffThr = slopeThr; _cliffAmp = reliefAmp;
        // Расширение на ячейку: точный тест зовётся и у самой кромки
        _cliffNear = new byte[_cliff.Length];
        for (int r = 0; r < rows; r++)
            for (int c = 0; c < cols; c++)
            {
                if (_cliff[r * cols + c] == 0) continue;
                for (int dr = -1; dr <= 1; dr++)
                    for (int dc = -1; dc <= 1; dc++)
                    {
                        int rr = r + dr, cc = c + dc;
                        if (rr < 0 || cc < 0 || rr >= rows || cc >= cols) continue;
                        _cliffNear[rr * cols + cc] = 1;
                    }
            }
        _cliffOn = CliffCells > 0;
    }

    public void SetCliffEnabled(bool on) { _cliffOn = on && _cliff.Length > 1; }

    // Высота без русла: гармоники + гора + плато (см. Height)
    private float DryHeight(float x, float z, float reliefAmp)
    {
        return Height(x, z, reliefAmp) + RiverDepth(x, z);
    }

    // ── ТОЧНАЯ ПРОВЕРКА: МАСКА — ТОЛЬКО ГРУБЫЙ ФИЛЬТР ─────────────────────
    // Ячейка в 1 м даёт зубчатую границу, и во «вогнутых углах» зубцов боец
    // застревал (касательная к шагу, а не к склону). Маска расширена на
    // ячейку и отвечает «рядом обрыв?»; сама крутизна считается в ТОЧКЕ по
    // четырём высотам (непрерывно), а скольжение идёт вдоль настоящего
    // градиента склона (CliffGrad). Цена — четыре высоты только у обрывов
    private float _cliffThr = 0.45f, _cliffAmp = 0.0f;
    private byte[] _cliffNear = System.Array.Empty<byte>();

    private bool CliffNear(float x, float z)
    {
        int c = (int)Math.Floor((x - _cliffOx) / _cliffCell);
        int r = (int)Math.Floor((z - _cliffOz) / _cliffCell);
        if (c < 0 || r < 0 || c >= _cliffCols || r >= _cliffRows) return false;
        return _cliffNear[r * _cliffCols + c] != 0;
    }

    // Градиент «сухой» высоты в точке; возвращает крутизну (max по осям)
    private float CliffGrad(float x, float z, out float gx, out float gz)
    {
        const float h2 = 0.5f;
        gx = (DryHeight(x + h2, z, _cliffAmp) - DryHeight(x - h2, z, _cliffAmp));
        gz = (DryHeight(x, z + h2, _cliffAmp) - DryHeight(x, z - h2, _cliffAmp));
        return Math.Max(Math.Abs(gx), Math.Abs(gz));
    }

    // Стоящий НА скале (рождён там, вытолкнут, перенесён разлётом) вправе
    // шагнуть, только если новая точка ПОЛОЖЕ текущей: уйти со стены можно,
    // пройти сквозь неё — нет
    private bool CliffEscape(float x, float z, float nx, float nz)
    {
        if (!CliffNear(x, z)) return false;
        float gx, gz, hx, hz;
        float here = CliffGrad(x, z, out gx, out gz);
        if (here <= _cliffThr) return false;
        float there = CliffGrad(nx, nz, out hx, out hz);
        // Не круче текущего: вдоль склона и вниз — можно, глубже в стену — нет
        return there <= here + 1e-4f;
    }

    public bool IsCliffAt(float x, float z)
    {
        if (!_cliffOn || !CliffNear(x, z)) return false;
        float gx, gz;
        return CliffGrad(x, z, out gx, out gz) > _cliffThr;
    }

    // Та же формула, что Main.plateau_height
    private float PlateauHeight(float x, float z)
    {
        float total = 0.0f;
        for (int i = 0; i + 4 < _plat.Length; i += 5)
        {
            float dx = x - _plat[i], dz = z - _plat[i + 1];
            float rf = _plat[i + 2];
            float reach = rf + _platGentle;
            if (Math.Abs(dx) > reach || Math.Abs(dz) > reach) continue;
            float h = _plat[i + 3];
            float d = Mathf.Sqrt(dx * dx + dz * dz);
            if (d <= rf) { total += h; continue; }
            float da = Math.Abs(Mathf.Wrap(Mathf.Atan2(dz, dx) - _plat[i + 4], -Mathf.Pi, Mathf.Pi));
            float k = 1.0f - Mathf.SmoothStep(_platCone, _platCone + 0.6f, da);
            float w = _platSteep + (_platGentle - _platSteep) * k;
            float t = Mathf.Clamp((d - rf) / w, 0.0f, 1.0f);
            total += h * (1.0f - t * t * (3.0f - 2.0f * t));
        }
        return total;
    }

    // Высота ядра наружу — стендам, сверяющим обе копии формулы (qa_map F4)
    public float HeightAt(float x, float z, float reliefAmp) => Height(x, z, reliefAmp);

    public void SetHill(float cx, float cz, float h, float radius)
    {
        _hillOn = h > 0.0f && radius > 0.0f;
        _hillCx = cx; _hillCz = cz; _hillH = h;
        float s = radius * 0.5f;
        _hillSigma2 = 2.0f * s * s;
    }

    public void SetRiver(bool on, float halfW, float meander, float k, float fordZ,
        float fordHalf, float depth, float fordDepth, float bank, float margin,
        float halfZ, float wetDepth)
    {
        _riverOn = on;
        _riverHalfZ = halfZ;
        _riverHalfW = halfW; _riverMeander = meander; _riverK = k;
        _fordZ = fordZ; _fordHalf = fordHalf;
        _riverDepth = depth; _fordDepth = fordDepth; _riverBank = bank; _riverMargin = margin;
        _wetDepth = wetDepth;
    }

    private float RiverX(float z) => _riverMeander * Mathf.Sin(z * _riverK);
    private bool InFord(float z) => Mathf.Abs(z - _fordZ) < _fordHalf;

    private float RiverDepth(float x, float z)
    {
        if (!_riverOn || Mathf.Abs(z) > _riverHalfZ) return 0.0f;
        float d = Mathf.Abs(x - RiverX(z));
        float edge = _riverHalfW + _riverBank;
        if (d >= edge) return 0.0f;
        float depth = InFord(z) ? _fordDepth : _riverDepth;
        float t = Mathf.Clamp((edge - d) / _riverBank, 0.0f, 1.0f);
        return depth * t;
    }

    private float HillHeight(float x, float z)
    {
        if (!_hillOn) return 0.0f;
        float dx = x - _hillCx, dz = z - _hillCz;
        float q = (dx * dx + dz * dz) / _hillSigma2;
        if (q > 12.0f) return 0.0f;
        return _hillH * Mathf.Exp(-q);
    }

    // Та же формула, что Main.get_terrain_height: гармоники + гора − русло
    private float Height(float x, float z, float reliefAmp)
    {
        if (reliefAmp == 0.0f) return 0.0f;
        return reliefAmp * (
              0.55f * Mathf.Sin(x * 0.031f + z * 0.017f)
            + 0.30f * Mathf.Sin(x * 0.013f - z * 0.041f + 1.7f)
            + 0.15f * Mathf.Sin(x * 0.077f + z * 0.059f + 3.1f))
            + HillHeight(x, z) + PlateauHeight(x, z) - RiverDepth(x, z);
    }

    // Вода реки — то же правило, что Main.is_water для русла
    // Вода там, где грунт ушёл под зеркало (та же мера, что Main.is_water).
    // Полосой вокруг оси это считалось до спринта 15, и верх откоса оставался
    // проходимым — «юниты сидят ногами в воде»
    private bool RiverWater(float x, float z)
    {
        if (!_riverOn || Mathf.Abs(z) > _riverHalfZ) return false;
        if (InFord(z)) return false;
        return RiverDepth(x, z) > _wetDepth;
    }

    // Река — своей арифметикой; озеро (если когда-нибудь включат) — GDScript
    private bool IsWaterAt(float x, float z, GodotObject gm)
    {
        if (_riverOn) return RiverWater(x, z);
        return gm != null && (bool)gm.Call("is_water", x, z);
    }
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
    // ── НАКОПЛЕННЫЙ, НО НЕ ЗАПИСАННЫЙ В УЗЕЛ СДВИГ (BigStand, этап 2) ──────
    // Колонка ядра ведёт точную позицию, а узел сцены получает её только когда
    // накопленный сдвиг дорос до NodeWriteMin: запись Position и пробуждение
    // спящего по картинке на каждую миллиметровую поправку стоили дороже
    // самого разбора наложения. Любая другая запись узла (шаг, PushToNodes,
    // SetPos, Release) обнуляет накопитель — узел и колонка снова совпадают
    private float[] _sepAccX = Array.Empty<float>();
    private float[] _sepAccZ = Array.Empty<float>();
    public static float NodeWriteMin = 0.01f;
    // ── ЯКОРЬ: ДВА СТОЯЩИХ СОСЕДА ОДНОГО ОТРЯДА (BigStand, этап 2) ──────────
    // Оба дошли (FSettled) и стоят — им разрешено стоять теснее нормы на
    // SettledDeadzone (личный круг бойца, 0.25 м), и поправки между ними нет:
    // это заявленное поведение «ЯКОРЬ» у прибытия, которого бит не давал,
    // потому что ядро его не читало. Идущий, дерущийся и чужой отряд толкают
    // как прежде — строй остаётся проходимым и разводится после боя
    public static float SettledDeadzone = 0.25f;
    // Сторона обхода обрыва (спринт 18): 0 — не идём вдоль стены, ±1 — идём;
    // держится, пока прямой шаг упирается, сбрасывается свободным шагом
    private sbyte[] _cliffSide = Array.Empty<sbyte>();
    private byte[] _cliffFree = Array.Empty<byte>();
    // Сторона обхода фундамента (ТЗ 19.09.2026 «обтекание»): пока боец трётся
    // о стену дома, сторона не меняется; сброс — первым свободным шагом
    private sbyte[] _bldSide = Array.Empty<sbyte>();
    private const float CliffBack = 0.35f;
    // Сколько свободных шагов подряд забывают сторону обхода: отступ от стены
    // делает прямой шаг свободным на такт-другой, и сброс на первом же
    // свободном шаге возвращал выбор стороны «куда ближе цель» — с
    // переворотом в точке, где стена перпендикулярна цели
    private const int CliffForget = 45;

    /// Число потоков пакетных проходов (ставит GDScript из perf_config;
    /// 1 — однопоточно). Потокам разрешена ТОЛЬКО чистая математика по
    /// колонкам: ни вызовов GDScript, ни дерева сцены, ни RenderingServer
    public static int CoreThreads = 1;
    public void SetThreads(int t) { CoreThreads = Math.Max(1, t); }

    private float[] _pressX = Array.Empty<float>();
    private float[] _pressZ = Array.Empty<float>();
    private float[] _pressV = Array.Empty<float>();
    private float[] _pressStop = Array.Empty<float>();
    // ── ВОРОТА БОЯ (BigStand, этап 4): автопилот подхода без ворот «чистый путь» ──
    // Темп подтягивания и его порог (reach + PULL_UP_MAX; < 0 — подтягивания
    // нет, боец вне отряда), плановый возврат в GDScript (_gateT — до него,
    // _gateEl — сколько прошло с взвода: GDScript доводит свои таймеры на
    // это время одним вычитанием), обход своих по вердикту «проход занят»
    // (_flankB) в свою сторону (_sideS) — копия Unit._flank_step
    private float[] _pressV2 = Array.Empty<float>();
    private float[] _pressLim = Array.Empty<float>();
    private float[] _gateT = Array.Empty<float>();
    private float[] _gateEl = Array.Empty<float>();
    private float[] _sideS = Array.Empty<float>();
    private byte[] _flankB = Array.Empty<byte>();
    private float[] _pressWakeEl = Array.Empty<float>();
    // Режим автопилота: 0 — подход к строке цели, 1 — ПОДТЯГИВАНИЕ (упор в
    // чужое тело НЕ будит: GDScript-ветка _should_pull_up заслон не сканирует
    // и просто давит — иначе каждый заблокированный шаг возвращал бойца в
    // автомат), 2 — МАРШ СТЕНЫ к точке _pressX/Z (Unit._phalanx_march)
    private byte[] _gateMode = Array.Empty<byte>();
    public const byte GatePull = 1;
    public const byte GateGoal = 2;
    private float[] _aggroT = Array.Empty<float>();
    private float[] _atkDmg = Array.Empty<float>();
    private float[] _atkRange = Array.Empty<float>();
    private float[] _speed = Array.Empty<float>();
    // ВЕС ЦЕЛИ ДЛЯ СТРЕЛКОВ (ТЗ 14.09.2026, п. 10): BestEnemy с usePrio делит
    // дистанцию на этот вес — большой гоблин (2.0) выбирается вдвое охотнее.
    // Единица — «как у всех»; ставится при рождении строки (Unit.target_weight)
    private float[] _tgtW = Array.Empty<float>();
    /// Вес цели для КОННИЦЫ (ТЗ 18.09.2026, п. 4): свино-всадник делит счёт
    /// на него — лучник/мечник/рабочий тянут к себе, копейщик в строю
    /// отталкивает. Свойство цели (Unit.cav_target_weight), своя колонка:
    /// стрелковый вес (_tgtW) про другое и читается другим родом войск
    private float[] _tgtWc = Array.Empty<float>();
    private float[] _sepT = Array.Empty<float>();
    // ЛИЧНЫЙ РАДИУС РАСТАЛКИВАНИЯ. Ноль — «как у всех», то есть minDist из
    // аргумента BatchSeparation; ненулевое значение перекрывает его для этой
    // строки. Заведён ради гоблинов: их спрайт крупнее людского в 1.7 раза, и
    // единая на всю армию дистанция либо склеивала орду, либо раздвигала людей
    private float[] _sepR = Array.Empty<float>();
    // ── ТЕЛО ГИГАНТА (ТЗ 19.09.2026-3, п. 3) ──────────────────────────────
    // Добавка к радиусу блокировки чужого шага: пехотинец не входит в тушу
    // ближе blockR + _bodyR. Гигантов единицы — они лежат отдельным списком,
    // и ScanBlock/EnemyBlock обходят его целиком вместо расширения окна
    // ячеек для всех (цена — по числу гигантов, не по радиусу)
    private float[] _bodyR = Array.Empty<float>();
    private readonly System.Collections.Generic.List<int> _giants = new System.Collections.Generic.List<int>();
    private float _bodyMax = 0.0f;
    // ── ФУНДАМЕНТЫ ПОСТРОЕК (ТЗ 19.09.2026 «коллизии зданий») ─────────────
    // Постройка — ряд кругов (x, z, r) в той же редкой сетке ObstCell, что и
    // стволы. Шаг ЛЮБОЙ стороны в круг не проходит и скользит вдоль него;
    // стоящий ВНУТРИ (площадка заложена поверх отряда, слепок) выходит
    // наружу. Своя запись, а не RegisterTrunk: ствол для застрявшего
    // отключается (FTrunkIgnore) и в сетке навигации — цена, а не стена;
    // фундамент не отключается никогда и в сетке — непроходимая ячейка
    private struct BldCircle { public float X, Z, R; public long Id; }
    private readonly System.Collections.Generic.Dictionary<long, System.Collections.Generic.List<BldCircle>> _blds
        = new System.Collections.Generic.Dictionary<long, System.Collections.Generic.List<BldCircle>>();
    private readonly System.Collections.Generic.Dictionary<long, System.Collections.Generic.List<long>> _bldCells
        = new System.Collections.Generic.Dictionary<long, System.Collections.Generic.List<long>>();
    private float _bldMaxR = 0.0f;
    private bool _navBldDirty = false;
    public int BldCount = 0;
    // Зазор тела бойца до стены: центр не ближе r + BldClear к центру круга
    public const float BldClear = 0.25f;
    // ── СЕТКА НАВИГАЦИИ И ЗДАНИЯ (ТЗ 19.09.2026 «обтекание вплотную») ────
    // Ячейка считается стеной, когда её ПРЯМОУГОЛЬНИК задевает круг с зазором
    // NavBldPad (прежде — центр ячейки внутри круга: башня между центрами
    // четырёх ячеек не попадала в сетку вовсе, A* её не видел, и шаг обходил
    // её скольжением — половина отряда налево, половина направо). Здание —
    // не скала: у стены нет ни штрафа дистанции (_navWall считает только
    // скалы и воду), ни отступа нити clear + halfW — нить и угол держат
    // NavBldSidePad / NavBldCornerPush, а угол ещё и ПОДТЯГИВАЕТСЯ к
    // настоящему кругу фундамента на NavBldHug (по точным кругам, не по
    // ячейкам) — отряд огибает дом по самому краю, сжимаясь в гармошку
    // (NavSpread гасит смещение, легшее в дом), и выравнивается за углом
    public const float NavBldPad = 0.25f;
    public const float NavBldSidePad = 0.9f;
    public const float NavBldCornerPush = 1.0f;
    public const float NavBldHug = 0.8f;
    public const float NavBldAdjCost = 0.5f;
    private byte[] _navBldAdj = System.Array.Empty<byte>();
    public int NavBldCells = 0;
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
    /// GC-зонд для стендов: байт выделено за всё время (churn), число сборок
    /// по поколениям. Читается раз в фазу замера — не покадрово
    public long GcAllocated() => GC.GetTotalAllocatedBytes(true);
    public int GcCount(int gen) => GC.CollectionCount(gen);

    /// GC-зонд (BigStand-5, этап 4): сведения о ПОСЛЕДНЕЙ сборке и режиме.
    /// [поколение, номер, пауза мс (сумма), куча всего МБ, gen0 МБ, gen1 МБ,
    ///  gen2 МБ, LOH МБ, POH МБ, продвинуто МБ, уплотняющая, фоновая,
    ///  режим задержки, серверный GC, фрагментация МБ]
    public double[] GcInfo()
    {
        var i = GC.GetGCMemoryInfo(GCKind.Any);
        double pause = 0.0;
        foreach (var p in i.PauseDurations) pause += p.TotalMilliseconds;
        const double mb = 1.0 / (1024.0 * 1024.0);
        return new[]
        {
            (double)i.Generation, (double)i.Index, pause, i.HeapSizeBytes * mb,
            i.GenerationInfo[0].SizeAfterBytes * mb, i.GenerationInfo[1].SizeAfterBytes * mb,
            i.GenerationInfo[2].SizeAfterBytes * mb, i.GenerationInfo[3].SizeAfterBytes * mb,
            i.GenerationInfo[4].SizeAfterBytes * mb, i.PromotedBytes * mb,
            i.Compacted ? 1.0 : 0.0, i.Concurrent ? 1.0 : 0.0,
            (double)(int)System.Runtime.GCSettings.LatencyMode,
            System.Runtime.GCSettings.IsServerGC ? 1.0 : 0.0,
            i.FragmentedBytes * mb,
            // 15..: до сборки gen0/gen1/gen2 МБ, ждущих финализации, закреплённых
            i.GenerationInfo[0].SizeBeforeBytes * mb, i.GenerationInfo[1].SizeBeforeBytes * mb,
            i.GenerationInfo[2].SizeBeforeBytes * mb,
            (double)i.FinalizationPendingCount, (double)i.PinnedObjectsCount,
        };
    }

    /// Зонд: принудительная полная сборка → сколько объектов ждут финализации
    /// (те, что были живы только ради финализатора) и байт выделено всего
    public double[] GcProbe()
    {
        GC.Collect(2, GCCollectionMode.Forced, true);
        var i = GC.GetGCMemoryInfo(GCKind.Any);
        return new[] { (double)i.FinalizationPendingCount, (double)GC.GetTotalAllocatedBytes(true),
            i.HeapSizeBytes / (1024.0 * 1024.0) };
    }

    /// Режим задержки GC: 0 Batch, 1 Interactive (умолчание), 2 LowLatency,
    /// 3 SustainedLowLatency, 4 NoGCRegion. Возвращает установленный
    public int GcSetLatency(int mode)
    {
        try { System.Runtime.GCSettings.LatencyMode = (System.Runtime.GCLatencyMode)mode; }
        catch (Exception) { }
        return (int)System.Runtime.GCSettings.LatencyMode;
    }

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
        _navTreeDirty = true;
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
                _navTreeDirty = true;
                return;
            }
        }
    }

    public void ClearTrunks()
    {
        _trunks.Clear();
        _trunkMaxR = 0.0f;
        _navTreeDirty = true;
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

    // ── ФУНДАМЕНТЫ: реестр и запросы ─────────────────────────────────────
    public void RegisterObstacle(long id, float[] flat)
    {
        UnregisterObstacle(id);
        if (flat == null || flat.Length < 3) return;
        var cells = new System.Collections.Generic.List<long>(4);
        for (int k = 0; k + 2 < flat.Length; k += 3)
        {
            float x = flat[k], z = flat[k + 1], r = flat[k + 2];
            if (r <= 0.0f) continue;
            int cx = Mathf.FloorToInt(x / ObstCell);
            int cz = Mathf.FloorToInt(z / ObstCell);
            long key = TrunkKey(cx, cz);
            if (!_blds.TryGetValue(key, out var list))
            {
                list = new System.Collections.Generic.List<BldCircle>(4);
                _blds[key] = list;
            }
            list.Add(new BldCircle { X = x, Z = z, R = r, Id = id });
            cells.Add(key);
            if (r > _bldMaxR) _bldMaxR = r;
        }
        if (cells.Count == 0) return;
        _bldCells[id] = cells;
        BldCount++;
        _navBldDirty = true;
    }

    public void UnregisterObstacle(long id)
    {
        if (!_bldCells.TryGetValue(id, out var cells)) return;
        for (int c = 0; c < cells.Count; c++)
        {
            if (!_blds.TryGetValue(cells[c], out var list)) continue;
            for (int i = list.Count - 1; i >= 0; i--)
                if (list[i].Id == id) list.RemoveAt(i);
            if (list.Count == 0) _blds.Remove(cells[c]);
        }
        _bldCells.Remove(id);
        BldCount--;
        _bldMaxR = 0.0f;
        foreach (var kv in _blds)
            for (int i = 0; i < kv.Value.Count; i++)
                if (kv.Value[i].R > _bldMaxR) _bldMaxR = kv.Value[i].R;
        _navBldDirty = true;
    }

    public void ClearObstacles()
    {
        _blds.Clear(); _bldCells.Clear(); _bldMaxR = 0.0f; BldCount = 0;
        _navBldDirty = true;
    }

    public int ObstacleCount() { return BldCount; }

    /// Глубина проникновения точки (с телом bodyR) в самый глубокий круг
    /// фундамента; 0 — свободно. ox/oz — единичное направление НАРУЖУ
    private float BldPenetration(float x, float z, float bodyR, out float ox, out float oz)
    {
        ox = 0.0f; oz = 0.0f;
        if (BldCount == 0) return 0.0f;
        float reach = bodyR + _bldMaxR;
        const float inv = 1.0f / ObstCell;
        int cx0 = Mathf.FloorToInt((x - reach) * inv);
        int cz0 = Mathf.FloorToInt((z - reach) * inv);
        int cx1 = Mathf.FloorToInt((x + reach) * inv);
        int cz1 = Mathf.FloorToInt((z + reach) * inv);
        float best = 0.0f;
        for (int cx = cx0; cx <= cx1; cx++)
            for (int cz = cz0; cz <= cz1; cz++)
            {
                if (!_blds.TryGetValue(TrunkKey(cx, cz), out var list)) continue;
                for (int i = 0; i < list.Count; i++)
                {
                    var b = list[i];
                    float dx = x - b.X, dz = z - b.Z;
                    float rr = b.R + bodyR;
                    float d2 = dx * dx + dz * dz;
                    if (d2 >= rr * rr) continue;
                    float d = Mathf.Sqrt(d2);
                    float pen = rr - d;
                    if (pen <= best) continue;
                    best = pen;
                    if (d < 1e-6f) { ox = 1.0f; oz = 0.0f; }
                    else { ox = dx / d; oz = dz / d; }
                }
            }
        return best;
    }

    public Vector3 BldBlock(float x, float z, float bodyR)
    {
        float ox, oz;
        float pen = BldPenetration(x, z, bodyR, out ox, out oz);
        if (pen <= 0.0f) return Vector3.Zero;
        return new Vector3(ox * pen, 0.0f, oz * pen);
    }

    public float BldDepth(float x, float z, float bodyR)
    {
        float ox, oz;
        return BldPenetration(x, z, bodyR, out ox, out oz);
    }

    public bool BldNear(float x, float z, float radius)
    {
        if (BldCount == 0) return false;
        float reach = radius + _bldMaxR;
        const float inv = 1.0f / ObstCell;
        int cx0 = Mathf.FloorToInt((x - reach) * inv);
        int cz0 = Mathf.FloorToInt((z - reach) * inv);
        int cx1 = Mathf.FloorToInt((x + reach) * inv);
        int cz1 = Mathf.FloorToInt((z + reach) * inv);
        for (int cx = cx0; cx <= cx1; cx++)
            for (int cz = cz0; cz <= cz1; cz++)
            {
                if (!_blds.TryGetValue(TrunkKey(cx, cz), out var list)) continue;
                for (int i = 0; i < list.Count; i++)
                {
                    var b = list[i];
                    float dx = x - b.X, dz = z - b.Z;
                    float rr = b.R + radius;
                    if (dx * dx + dz * dz < rr * rr) return true;
                }
            }
        return false;
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
        Array.Resize(ref _sepAccX, cap); Array.Resize(ref _sepAccZ, cap);
        Array.Resize(ref _cliffSide, cap);
        Array.Resize(ref _cliffFree, cap);
        Array.Resize(ref _bldSide, cap);
        Array.Resize(ref _pressX, cap); Array.Resize(ref _pressZ, cap);
        Array.Resize(ref _pressV, cap); Array.Resize(ref _pressStop, cap);
        Array.Resize(ref _pressV2, cap); Array.Resize(ref _pressLim, cap);
        Array.Resize(ref _gateT, cap); Array.Resize(ref _gateEl, cap);
        Array.Resize(ref _sideS, cap); Array.Resize(ref _flankB, cap);
        Array.Resize(ref _gateMode, cap);
        Array.Resize(ref _rbB, cap); Array.Resize(ref _rbI, cap);
        Array.Resize(ref _rbBaseY, cap);
        Array.Resize(ref _drawX, cap); Array.Resize(ref _drawY, cap);
        Array.Resize(ref _drawZ, cap); Array.Resize(ref _bobPhase, cap);
        Array.Resize(ref _anFps, cap); Array.Resize(ref _anFrames, cap);
        Array.Resize(ref _anLoop, cap); Array.Resize(ref _anPhase, cap);
        Array.Resize(ref _anFrame, cap);
        Array.Resize(ref _vqLx, cap); Array.Resize(ref _vqLz, cap);
        Array.Resize(ref _vqPx, cap); Array.Resize(ref _vqPz, cap);
        Array.Resize(ref _vqMs, cap); Array.Resize(ref _vqWake, cap);
        Array.Resize(ref _vqMv2, cap);
        Array.Resize(ref _vFlash, cap); Array.Resize(ref _vPeak, cap);
        Array.Resize(ref _ringB, cap); Array.Resize(ref _shB, cap);
        Array.Resize(ref _decI, cap); Array.Resize(ref _hpB, cap); Array.Resize(ref _hpI, cap);
        // Новые ячейки привязки к отрисовке обязаны быть «не привязан»
        for (int ri = _capacity; ri < cap; ri++)
        { _rbB[ri] = -1; _ringB[ri] = -1; _shB[ri] = -1; _hpB[ri] = -1; _anFrame[ri] = -1; }
        Array.Resize(ref _atkDmg, cap); Array.Resize(ref _atkRange, cap);
        int oldW = _tgtW.Length;
        Array.Resize(ref _tgtW, cap);
        Array.Resize(ref _tgtWc, cap);
        for (int w = oldW; w < cap; w++) { _tgtW[w] = 1.0f; _tgtWc[w] = 1.0f; }
        Array.Resize(ref _speed, cap);
        Array.Resize(ref _sepT, cap); Array.Resize(ref _sepR, cap);
        Array.Resize(ref _bodyR, cap);
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
        _vFlash[i] = 0; _vPeak[i] = 0; _vqWake[i] = 0;
        _atkDmg[i] = 0; _atkRange[i] = 0; _speed[i] = 0; _tgtW[i] = 1.0f; _tgtWc[i] = 1.0f;
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
        _anFrames[i] = 0; _anFrame[i] = -1;
        _ringB[i] = -1; _shB[i] = -1; _hpB[i] = -1;
        _st[i] = 0;
        _fac[i] = -1;
        _sq[i] = 0;
        _sepAccX[i] = 0.0f; _sepAccZ[i] = 0.0f;
        if (_bodyR[i] > 0.0f) SetBodyRadius(i, 0.0f);
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
    public void SetPos(int i, float x, float y, float z) { _px[i] = x; _py[i] = y; _pz[i] = z; _sepAccX[i] = 0.0f; _sepAccZ[i] = 0.0f; }
    /// БОЕЦ ВНЕ КАРТЫ (гарнизон): строка живёт, но координата «ненастоящая».
    /// Без этого вошедший в замок или башню оставался в сетке соседей на
    /// последней точке у ворот, и его находили и BestEnemy, и стрелы (EnemyAt):
    /// «лучники в башне получают урон» (09.09.2026). Возврат — WritePose
    /// (sync_row при выходе) снова ставит FPosValid
    public void SetOffMap(int i, bool on)
    {
        if (i < 0 || i >= _capacity) return;
        if (on) _flags[i] &= ~FPosValid; else _flags[i] |= FPosValid;
    }
    public void SetVel(int i, float x, float z) { _vx[i] = x; _vz[i] = z; }
    public void SetHp(int i, float cur, float mx) { _hp[i] = cur; _hpMax[i] = mx; }
    public void SetState(int i, int s) { _st[i] = s; }
    public void SetFaction(int i, int f) { _fac[i] = f; }
    public void SetSquad(int i, int s) { _sq[i] = s; }
    public void SetCombat(int i, float dmg, float rng, float spd)
    { _atkDmg[i] = dmg; _atkRange[i] = rng; _speed[i] = spd; }
    public void SetTargetWeight(int i, float w) { if (i >= 0 && i < _capacity) _tgtW[i] = w > 0.01f ? w : 1.0f; }
    public void SetCavWeight(int i, float w) { if (i >= 0 && i < _capacity) _tgtWc[i] = w > 0.01f ? w : 1.0f; }
    public void SetSlot(int i, float ox, float oz) { if (i >= 0) { _slX[i] = ox; _slZ[i] = oz; } }
    public void SetAttackers(int i, int n) { if (i >= 0 && i < _capacity) _attackers[i] = n; }
    /// Строка цели атаки. Пишется по событию из Unit.set_attack_target
    public void SetTarget(int i, int t) { if (i >= 0 && i < _capacity) _tgt[i] = t; }
    public float FacingX(int i) => (i >= 0 && i < _capacity) ? _fx[i] : 0.0f;
    public float FacingZ(int i) => (i >= 0 && i < _capacity) ? _fz[i] : 0.0f;

    public void WritePose(int i, Vector3 p, Vector3 v, int state)
    {
        if (i < 0) return;
        _px[i] = p.X; _py[i] = p.Y; _pz[i] = p.Z; _sepAccX[i] = 0.0f; _sepAccZ[i] = 0.0f;
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
            _px[i] = xs[k]; _py[i] = ys[k]; _pz[i] = zs[k]; _sepAccX[i] = 0.0f; _sepAccZ[i] = 0.0f;
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
        if (row < 0 || SkipBodyScan) return Vector3.Zero;
        int myf = _fac[row];
        int mySlot = FacSlot(myf);
        if (!EnemyNear(tx, tz, myf, minDist + _bodyMax)) return Vector3.Zero;
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
        if (_giants.Count > 0) GiantBlock(row, tx, tz, minDist, mySlot, DeadState, ref nx, ref nz, awayOk);
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
        return BestEnemyW(row, radius, crowdPenalty, false);
    }

    /// usePrio — делить счёт на вес цели (_tgtW): стрелки предпочитают
    /// больших гоблинов (ТЗ 14.09.2026, п. 10). Рукопашная веса не читает
    public GodotObject BestEnemyW(int row, float radius, float crowdPenalty, bool usePrio)
    {
        return BestEnemyPrio(row, radius, crowdPenalty, usePrio ? 1 : 0);
    }

    /// prio: 0 — ближайший, 1 — вес стрелка (_tgtW), 2 — вес конницы (_tgtWc)
    public GodotObject BestEnemyPrio(int row, float radius, float crowdPenalty, int prio)
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
                        if (prio == 1) score /= _tgtW[j];
                        else if (prio == 2) score /= _tgtWc[j];
                        if (score < bestScore) { bestScore = score; best = u; }
                        j = _next[j];
                    }
                }
            }
        }
        return best;
    }

    /// САМЫЙ РАНЕНЫЙ СВОЙ В РАДИУСЕ (монах, qa_melee_bench 14.09.2026): по
    /// колонкам hp/hpMax, без Godot-массива на каждый такт. Прежний путь
    /// (QueryRadius + фильтр в GDScript по 300 бойцам свалки) давал тик
    /// монаха до 5.8 мс. excludeRow — сам монах (он лечится своим правилом).
    /// Возвращает null, если раненых нет (доля запаса < 0.999)
    public GodotObject MostWoundedOfSide(float x, float z, int side, float radius, int excludeRow)
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
        float rSq = radius * radius;
        int slot = FacSlot(side);
        int dead = DeadState;
        GodotObject best = null;
        float bestFrac = 0.999f;
        for (int cz = cz0; cz <= cz1; cz++)
        {
            int b = cz * _gw;
            for (int cx = cx0; cx <= cx1; cx++)
            {
                int j = _head[(b + cx) * Factions + slot];
                while (j != -1)
                {
                    if (j == excludeRow || _st[j] == dead || _fac[j] != side) { j = _next[j]; continue; }
                    float mx = _hpMax[j];
                    if (mx <= 0f) { j = _next[j]; continue; }
                    float frac = _hp[j] / mx;
                    if (frac >= bestFrac) { j = _next[j]; continue; }
                    float dx = x - _px[j];
                    float dz = z - _pz[j];
                    if (dx * dx + dz * dz > rSq) { j = _next[j]; continue; }
                    var u = _unitOf[j];
                    if (u == null || !GodotObject.IsInstanceValid(u)) { j = _next[j]; continue; }
                    bestFrac = frac;
                    best = u;
                    j = _next[j];
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
        int j = EnemyRowAt(x, z, radius, fac);
        return j < 0 ? null : _unitOf[j] as Godot.Node3D;
    }

    /// То же правило, ответ — СТРОКА (−1 — никого). Снаряды ядра (этап 3
    /// BigStand-5) отдают жертву строкой: узел GDScript берёт из своего
    /// реестра строка → узел, а не из обёртки объекта в событии
    public int EnemyRowAt(float x, float z, float radius, int fac)
    {
        if (_gw == 0) return -1;
        int cx0 = (int)((x - radius - _gx0) * _ginv);
        int cz0 = (int)((z - radius - _gz0) * _ginv);
        int cx1 = (int)((x + radius - _gx0) * _ginv);
        int cz1 = (int)((z + radius - _gz0) * _ginv);
        if (cx1 < 0 || cz1 < 0 || cx0 >= _gw || cz0 >= _gh) return -1;
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
                            var u = _unitOf[j];
                            if (u != null && GodotObject.IsInstanceValid(u))
                                return j;
                        }
                        j = _next[j];
                    }
                }
            }
        }
        return -1;
    }

    /// ВСЕ БОЙЦЫ В РАДИУСЕ — СТРОКАМИ (BigStand-5, этап 4). Тот же обход, что
    /// у QueryRadius, но наружу уходит int[] (PackedInt32Array): у
    /// Godot.Collections.Array КАЖДЫЙ элемент-узел — финализируемая обёртка,
    /// и она переживает gen0 всегда (очередь финализации), набивая gen1 —
    /// зонд GcProbe назвал query_radius единственным источником
    /// финализируемого мусора среди вызовов ядра (~59 на вызов). Узел по
    /// строке GDScript берёт из своего реестра (GameManager._row_units)
    private readonly System.Collections.Generic.List<int> _qrRows = new System.Collections.Generic.List<int>(256);
    public int[] QueryRadiusRows(float x, float z, float radius)
    {
        _qrRows.Clear();
        if (_gw == 0) return Array.Empty<int>();
        int cx0 = (int)((x - radius - _gx0) * _ginv);
        int cz0 = (int)((z - radius - _gz0) * _ginv);
        int cx1 = (int)((x + radius - _gx0) * _ginv);
        int cz1 = (int)((z + radius - _gz0) * _ginv);
        if (cx1 < 0 || cz1 < 0 || cx0 >= _gw || cz0 >= _gh) return Array.Empty<int>();
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
                                _qrRows.Add(j);
                        }
                        j = _next[j];
                    }
                }
            }
        }
        return _qrRows.Count == 0 ? Array.Empty<int>() : _qrRows.ToArray();
    }

    /// СЧЁТ ЖИВЫХ ЧУЖИХ В РАДИУСЕ — без массива вовсе (тролль спрашивает
    /// «сколько вокруг» каждый физтик ради решения об окружении; список ему
    /// не нужен). fac — своя фракция, dead — код состояния DEAD
    public int EnemyCount(float x, float z, float radius, int fac, int dead)
    {
        if (_gw == 0) return 0;
        int cx0 = (int)((x - radius - _gx0) * _ginv);
        int cz0 = (int)((z - radius - _gz0) * _ginv);
        int cx1 = (int)((x + radius - _gx0) * _ginv);
        int cz1 = (int)((z + radius - _gz0) * _ginv);
        if (cx1 < 0 || cz1 < 0 || cx0 >= _gw || cz0 >= _gh) return 0;
        if (cx0 < 0) cx0 = 0;
        if (cz0 < 0) cz0 = 0;
        if (cx1 >= _gw) cx1 = _gw - 1;
        if (cz1 >= _gh) cz1 = _gh - 1;
        float rSq = radius * radius;
        int n = 0;
        for (int cz = cz0; cz <= cz1; cz++)
        {
            int b = cz * _gw;
            for (int cx = cx0; cx <= cx1; cx++)
            {
                int slot = (b + cx) * Factions;
                for (int side = 0; side < Factions; side++)
                {
                    if (side == fac) continue;
                    int j = _head[slot + side];
                    while (j != -1)
                    {
                        if (_st[j] != dead)
                        {
                            float dx = x - _px[j];
                            float dz = z - _pz[j];
                            if (dx * dx + dz * dz <= rSq)
                            {
                                var u = _unitOf[j];
                                if (u != null && GodotObject.IsInstanceValid(u)) n++;
                            }
                        }
                        j = _next[j];
                    }
                }
            }
        }
        return n;
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
                if (IsWaterAt(nx, nz, gm))
                {
                    Vector3 slid = (Vector3)gm.Call("slide_around_water",
                        new Vector3(x, 0.0f, z), new Vector3(sx, 0.0f, sz));
                    sx = slid.X; sz = slid.Z;
                    if (sx * sx + sz * sz < 1e-8f) continue;
                    nx = x + sx; nz = z + sz;
                }
            }
            // ── СКАЛА: скольжение вдоль обрыва, в лоб — стоим ───────────────
            // Стоящий НА скале (рождён там, вытолкнут) вправе уйти с неё: блок
            // только на ВХОД в скалу с проходимой земли
            if (_cliffOn && boundsOn && IsCliffAt(nx, nz) && !CliffEscape(x, z, nx, nz))
            {
                // ВДОЛЬ ОБРЫВА С ПАМЯТЬЮ СТОРОНЫ: кольцо плато замкнуто, выход
                // один — спуск, и боец обязан ползти вдоль стены до него.
                // Касательная — перпендикуляр к градиенту высоты в точке шага.
                // Сторона выбирается на ПЕРВОМ упоре (куда ближе цель) и ДЕРЖИТСЯ,
                // пока прямой шаг упирается: без памяти в точке, где стена
                // перпендикулярна цели, касательная меняла знак и боец замирал
                // (зонд qa_cliff_probe: 20 с у стены на (-40.5, -42)). Вогнутый
                // угол (обе касательные в скале) — сторона переворачивается
                float gx, gz;
                CliffGrad(nx, nz, out gx, out gz);
                float gl = (float)Math.Sqrt(gx * gx + gz * gz);
                float len = (float)Math.Sqrt(sx * sx + sz * sz);
                float tx, tz;
                if (gl > 1e-6f) { tx = -gz / gl * len; tz = gx / gl * len; }
                else { tx = -sz; tz = sx; }
                int side = _cliffSide[i];
                if (side == 0)
                {
                    float d = sx * tx + sz * tz;
                    side = d >= 0.0f ? 1 : -1;
                    if (Math.Abs(d) < 1e-6f) side = ((i & 1) != 0) ? -1 : 1;
                }
                // Касательная с ОТСТУПОМ от стены: хорды вдоль кривой стены
                // сносят бойца в склон, и без отступа обе касательные оказывались
                // в скале. Отступ — НАЗАД ПО ШАГУ (шаг и привёл в стену), а не по
                // градиенту: знак градиента не говорит, сверху боец или снизу
                float bx = -sx * CliffBack, bz = -sz * CliffBack;
                float ux = tx * side + bx, uz = tz * side + bz;
                if (IsCliffAt(x + ux, z + uz))
                {
                    side = -side;
                    ux = tx * side + bx; uz = tz * side + bz;
                    if (IsCliffAt(x + ux, z + uz))
                    {
                        // Вогнутый угол: назад по шагу, прочь от стены
                        ux = bx * 2.0f; uz = bz * 2.0f;
                        if (ux * ux + uz * uz < 1e-10f || IsCliffAt(x + ux, z + uz))
                        {
                            // Стоим НА стене (рождены там, вытолкнуты): скатываемся
                            // вниз по склону — у стены есть подножие, и оно ровное
                            float hx = 0.0f, hz = 0.0f;
                            float here = CliffNear(x, z) ? CliffGrad(x, z, out hx, out hz) : 0.0f;
                            float hl = (float)Math.Sqrt(hx * hx + hz * hz);
                            if (here > _cliffThr && hl > 1e-6f)
                            {
                                ux = -hx / hl * len; uz = -hz / hl * len;
                            }
                            else { _cliffSide[i] = 0; continue; }
                        }
                    }
                }
                _cliffSide[i] = (sbyte)side;
                _cliffFree[i] = 0;
                sx = ux; sz = uz;
                nx = x + sx; nz = z + sz;
            }
            else if (_cliffSide[i] != 0)
            {
                if (_cliffFree[i] < 255) _cliffFree[i]++;
                if (_cliffFree[i] >= CliffForget) { _cliffSide[i] = 0; _cliffFree[i] = 0; }
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
            // ── ФУНДАМЕНТ ПОСТРОЙКИ ────────────────────────────────────────
            // Правило партии, как вода и скалы (boundsOn). Коридор отряда без
            // построек рядом снимает проверку (FClearTrunk считает и их);
            // FTrunkIgnore сюда не смотрит — сквозь дом застрявший не идёт
            if (BldCount > 0 && boundsOn && (fl & FClearTrunk) == 0)
            {
                float ox, oz;
                float pen = BldPenetration(nx, nz, BldClear, out ox, out oz);
                if (pen > 0.0f)
                {
                    float sp = Mathf.Sqrt(sx * sx + sz * sz);
                    float hx, hz;
                    float here = BldPenetration(x, z, BldClear, out hx, out hz);
                    if (here > 0.0f)
                    {
                        // СТОЯЩИЙ ВНУТРИ ВЫХОДИТ: шаг разворачивается наружу
                        // (площадка заложена поверх отряда, боец из слепка)
                        sx = hx * sp; sz = hz * sp;
                    }
                    else
                    {
                        // Обход, как у ствола: снять составляющую «в стену»,
                        // лобовой шаг отклонить вбок. СТОРОНА — ПАМЯТЬ: пока
                        // боец трётся об этот фундамент, она не меняется
                        // (прежде — чётность строки, и соседи по шеренге
                        // расходились по разные стороны башни, а лобовой
                        // боец менял сторону на каждом шаге — «бегают по
                        // кругу»); первый лобовой контакт — сторона отряда
                        float into = -(sx * ox + sz * oz);
                        if (into > 0.0f) { sx += ox * into; sz += oz * into; }
                        float tx = -oz, tz = ox;
                        float along = sx * tx + sz * tz;
                        sbyte side = _bldSide[i];
                        if (Mathf.Abs(along) >= sp * 0.2f) side = along >= 0.0f ? (sbyte)1 : (sbyte)-1;
                        else if (side == 0) side = (((_sq[i] > 0 ? _sq[i] : i) & 1) == 0) ? (sbyte)1 : (sbyte)-1;
                        if (Mathf.Sqrt(sx * sx + sz * sz) < sp * 0.2f)
                        {
                            sx = tx * side * sp; sz = tz * side * sp;
                        }
                        _bldSide[i] = side;
                        float ax2, az2;
                        float again = BldPenetration(x + sx, z + sz, BldClear, out ax2, out az2);
                        if (again > 0.0f) { sx += ax2 * again; sz += az2 * again; }
                        if (sx * sx + sz * sz < 1e-8f) continue;
                    }
                    nx = x + sx; nz = z + sz;
                }
                else _bldSide[i] = 0;
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
                // (+ тело гиганта: тролль блокирует шаг дальше blockR)
                if (EnemyNear(nx, nz, myf, br + _bodyMax))
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
                        // дальше решает полный автомат (перехват, ответ).
                        // И в режиме подтягивания тоже: без пробуждения боец
                        // давил в тела до планового возврата, и строй в
                        // контакте расползался (qa_mega_battle B7-2: 1.14 →
                        // 1.40 м). Цена — вход в автомат на каждом упоре,
                        // как и было у GDScript-ветки
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
                _thY[i] = Height(nx, nz, reliefAmp);
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
            _sepAccX[i] = 0.0f; _sepAccZ[i] = 0.0f;
            moved++;
        }
        return moved;
    }

    /// Суммарная нормаль ОТ чужих тел к точке. Вынесено из BatchMove, чтобы не
    /// повторять двадцать строк дважды; на стороне C# это инлайнится
    /// awayOk — ТОЛЬКО ПОД БИЛЕТОМ ПРОХОДА: тело, от которого шаг УДАЛЯЕТ,
    /// не блокирует, даже если новая точка ещё внутри радиуса. Без билета
    /// блокируется любая точка внутри радиуса (см. разбор ниже)
    /// ИЗМЕРИТЕЛЬНАЯ РУЧКА (хак №2, 09.09.2026): проверка чужих тел на шаге
    /// выключена целиком. Семантику ломает (тела проходят друг сквозь друга),
    /// нужна только чтобы узнать ПОТОЛОК выигрыша любой замены этой проверки
    public bool SkipBodyScan = false;

    private void ScanBlock(int row, float nx, float nz, float blockR, float blockSq,
        int mySlot, int dead, ref float bx, ref float bz, bool awayOk = false)
    {
        if (SkipBodyScan) return;
        if (_gw == 0) { if (_giants.Count > 0) GiantBlock(row, nx, nz, blockR, mySlot, dead, ref bx, ref bz, awayOk); return; }
        int cx0 = (int)((nx - blockR - _gx0) * _ginv);
        int cz0 = (int)((nz - blockR - _gz0) * _ginv);
        int cx1 = (int)((nx + blockR - _gx0) * _ginv);
        int cz1 = (int)((nz + blockR - _gz0) * _ginv);
        if (cx1 < 0 || cz1 < 0 || cx0 >= _gw || cz0 >= _gh) { if (_giants.Count > 0) GiantBlock(row, nx, nz, blockR, mySlot, dead, ref bx, ref bz, awayOk); return; }
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
        if (_giants.Count > 0) GiantBlock(row, nx, nz, blockR, mySlot, dead, ref bx, ref bz, awayOk);
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

    /// Добавка к телу гиганта (метры сверх общего blockR). Ноль снимает
    public void SetBodyRadius(int row, float r)
    {
        if (row < 0 || row >= _capacity) return;
        float v = r > 0.0f ? r : 0.0f;
        _bodyR[row] = v;
        if (v > 0.0f) { if (!_giants.Contains(row)) _giants.Add(row); }
        else _giants.Remove(row);
        _bodyMax = 0.0f;
        for (int k = 0; k < _giants.Count; k++)
            if (_bodyR[_giants[k]] > _bodyMax) _bodyMax = _bodyR[_giants[k]];
    }

    // Нормали от тел гигантов, чью тушу задевает точка (nx, nz)
    private void GiantBlock(int row, float nx, float nz, float blockR, int mySlot, int dead,
        ref float bx, ref float bz, bool awayOk)
    {
        for (int k = 0; k < _giants.Count; k++)
        {
            int j = _giants[k];
            if (j == row || j >= _capacity || _st[j] == dead) continue;
            if ((_flags[j] & FPosValid) == 0 || FacSlot(_fac[j]) == mySlot) continue;
            float rr = blockR + _bodyR[j];
            float dx = nx - _px[j];
            float dz = nz - _pz[j];
            float d2 = dx * dx + dz * dz;
            if (d2 >= rr * rr) continue;
            if (awayOk && d2 >= 0.0001f)
            {
                float cdx = _px[row] - _px[j];
                float cdz = _pz[row] - _pz[j];
                if (d2 >= cdx * cdx + cdz * cdz) continue;
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
        }
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
            bool iCalm = s != movingState && s != attackingState && (_flags[i] & FSettled) != 0;
            // ── ГИГАНТ СРЕДИ МЕЛКИХ СОЮЗНИКОВ (ТЗ 19.09.2026, «Фикс туш») ─────
            // Тушу (тело в ядре, _bodyR > 0) на марше сквозь свою орду каждая
            // пара соседей отталкивала по ЕЁ норме (0.73 м, ×1.6 от чужого
            // отряда): десятки поправок в такт, идущий скользил вбок и терял
            // шаг — «замедляется, впадает в ступор». Теперь идущий гигант
            // мелких союзников НЕ считает вовсе (они уходят с его дороги
            // сами: мелкий сосед берёт норму гиганта, см. ниже), стоящий —
            // считает в доле их радиуса к своему
            bool iGiant = _bodyR[i] > 0.0f;
            bool iGoing = s == movingState || s == attackingState;
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
                        float oR = _sepR[j];
                        float share = 1.0f;
                        if (iGiant && oR < own)
                        {
                            if (iGoing) { j = _next[j]; continue; }
                            share = (oR > 0.0f ? oR : minDist) / own;
                        }
                        else if (!iGiant && _bodyR[j] > 0.0f && oR > lim)
                        {
                            // Мелкий у гиганта держит ЕГО норму: отходит сам,
                            // и гиганту не приходится выталкивать его собой
                            lim = oR;
                            float gNear = Mathf.Max(oR - deadzone, 0.0f);
                            limNearSq = gNear * gNear;
                        }
                        float dx = x - _px[j];
                        float dz = z - _pz[j];
                        float dd = dx * dx + dz * dz;
                        // МЁРТВАЯ ЗОНА: сосед, стоящий чуть теснее нормы, в
                        // расчёт не идёт — иначе строй перетаптывается вечно
                        if (dd >= limNearSq) { j = _next[j]; continue; }
                        // ЯКОРЬ: два стоящих соседа одного отряда (оба дошли)
                        // терпят друг друга до SettledDeadzone — см. шапку
                        if (iCalm && !otherSquad && (_flags[j] & FSettled) != 0
                            && _st[j] != movingState && _st[j] != attackingState)
                        {
                            float calmNear = Mathf.Max(lim - SettledDeadzone, 0.0f);
                            if (dd >= calmNear * calmNear) { j = _next[j]; continue; }
                        }
                        if (dd < 1e-8f)
                        {
                            float ang = (i % 251) * (Mathf.Tau / 251.0f);
                            dx = Mathf.Cos(ang) * 0.01f;
                            dz = Mathf.Sin(ang) * 0.01f;
                            dd = dx * dx + dz * dz;
                        }
                        float d = Mathf.Sqrt(dd);
                        float need = (lim - d) / d * share;
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
            if (waterOn && IsWaterAt(nx2, nz2, gm)) continue;
            if (_cliffOn && waterOn && IsCliffAt(nx2, nz2) && !IsCliffAt(_px[i], _pz[i])) continue;   // на скалу не выталкиваем
            if (BldCount > 0 && waterOn && BldDepth(nx2, nz2, 0.0f) > 0.0f && BldDepth(_px[i], _pz[i], 0.0f) <= 0.0f) continue;   // и в дом тоже
            float ny = Height(nx2, nz2, reliefAmp);
            // Накопитель: колонка точна всегда, узел — когда сдвиг дорос до
            // NodeWriteMin (BigStand, этап 2). Ниже порога — ни записи в
            // дерево сцены, ни пробуждения, ни счёта «сдвинутых»
            float ax = _sepAccX[i] + (nx2 - _px[i]);
            float az = _sepAccZ[i] + (nz2 - _pz[i]);
            _px[i] = nx2; _py[i] = ny; _pz[i] = nz2;
            if (ax * ax + az * az < NodeWriteMin * NodeWriteMin)
            {
                _sepAccX[i] = ax; _sepAccZ[i] = az;
                continue;
            }
            _sepAccX[i] = 0.0f; _sepAccZ[i] = 0.0f;
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
            _px[i] = wx; _pz[i] = wz; _sepAccX[i] = 0.0f; _sepAccZ[i] = 0.0f;
            _py[i] = ny + Height(wx, wz, amp);
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
            _sepAccX[i] = 0.0f; _sepAccZ[i] = 0.0f;
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
    /// То же ПЛОСКИМ float[] пар [строка, остаток]: Godot.Collections.Array
    /// финализируем и переживает gen0 всегда — раз в тик такая обёртка
    /// набивала gen1 и учащала блокирующие сборки (BigStand-5, этап 4).
    /// Узел GDScript берёт из реестра строка → узел
    public float[] TakeWokenF()
    {
        var res = new float[_wokenCount * 2];
        for (int k = 0; k < _wokenCount; k++)
        {
            res[k * 2] = _wokenRows[k];
            res[k * 2 + 1] = _wokenCd[k];
        }
        _wokenCount = 0;
        return res;
    }

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

    /// «Разведано» без «видно»: штамп в _fogSeen (ТЗ 18.09.2026, п. 10 —
    /// рудники на холмах видны с начала партии как ориентир, врагов рядом
    /// это не показывает). Та же математика, что у FogStamp, только в seen
    public void FogStampSeen(float x, float z, float radius)
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
        var seen = _fogSeen;
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
                if (v > seen[o]) seen[o] = (byte)v;
            }
        }
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

    // ── ИСТОЧНИКИ ПО БОЙЦАМ СОБИРАЕТ ЯДРО (09.09.2026) ──────────────────────
    // GDScript обходил все _live_units (global_position — СВОЙСТВО, правило 2,
    // плюс is_instance_valid, is_dead и словарь на каждого): на 4000 бойцах
    // это 3.4 мс из 4.6 мс пересчёта, и всё это ложилось в ОДИН кадр раз в
    // UPDATE_INTERVAL — тот самый микролаг. Здесь те же правила: только живые
    // строки своей фракции с настоящей координатой (гарнизон — нет), радиус
    // обзора от _atkRange по формуле unit_stats_config.vision_radius,
    // слияние по грубой ячейке srcCell с наибольшим радиусом (как _add_source)
    private readonly System.Collections.Generic.Dictionary<long, int> _fogSrcKey = new();
    private float[] _fogSrcX = new float[256], _fogSrcZ = new float[256], _fogSrcR = new float[256];
    private int _fogSrcN;

    public Godot.Collections.Array FogRefreshRows(int faction, float visMult, float visMin,
        float srcCell, float pad, float[] extra)
    {
        int n = _fogCols * _fogRows;
        Array.Clear(_fogLit, 0, n);
        _fogSrcKey.Clear();
        _fogSrcN = 0;
        float inv = 1.0f / Math.Max(srcCell, 0.001f);
        int dead = DeadState;
        for (int k = 0; k < _liveCount; k++)
        {
            int i = _liveRows[k];
            if ((_flags[i] & FPosValid) == 0 || _fac[i] != faction || _st[i] == dead) continue;
            float r = Math.Max(_atkRange[i] * visMult, visMin) + pad;
            int kx = (int)Mathf.Floor(_px[i] * inv);
            int kz = (int)Mathf.Floor(_pz[i] * inv);
            long key = ((long)kz << 32) ^ (uint)kx;
            if (_fogSrcKey.TryGetValue(key, out int idx))
            {
                if (r > _fogSrcR[idx]) _fogSrcR[idx] = r;
                continue;
            }
            if (_fogSrcN >= _fogSrcX.Length)
            {
                int cap = _fogSrcX.Length * 2;
                Array.Resize(ref _fogSrcX, cap); Array.Resize(ref _fogSrcZ, cap); Array.Resize(ref _fogSrcR, cap);
            }
            _fogSrcX[_fogSrcN] = (kx + 0.5f) * srcCell;
            _fogSrcZ[_fogSrcN] = (kz + 0.5f) * srcCell;
            _fogSrcR[_fogSrcN] = r;
            _fogSrcKey[key] = _fogSrcN;
            _fogSrcN++;
        }
        for (int s2 = 0; s2 < _fogSrcN; s2++)
            FogStamp(_fogSrcX[s2], _fogSrcZ[s2], _fogSrcR[s2]);
        for (int k = 0; k + 2 < extra.Length; k += 3)
            FogStamp(extra[k], extra[k + 1], extra[k + 2]);
        return FogFinish();
    }

    /// Число ячеек-источников последнего пересчёта (зонды)
    public int FogSourceCount() => _fogSrcN;

    /// Пересчёт по строкам БЕЗ Godot-обёртки в ответе (BigStand-5, этап 4):
    /// маски читаются потом FogLit/FogSeen/FogRgba плоскими массивами.
    /// Godot.Collections.Array финализируем и раз в 0.15 с ложился в gen1
    public int FogRefreshRowsPacked(int faction, float visMult, float visMin,
        float srcCell, float pad, float[] extra)
    {
        _fogPacked = true;
        FogRefreshRows(faction, visMult, visMin, srcCell, pad, extra);
        _fogPacked = false;
        return _fogSrcN;
    }
    public byte[] FogLit() => _fogLit;
    public byte[] FogSeen() => _fogSeen;
    public byte[] FogRgba() => _fogRgba;

    private Godot.Collections.Array FogFinish()
    {
        int n = _fogCols * _fogRows;
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
        if (!_fogPacked)
        {
            var res = new Godot.Collections.Array();
            res.Add(lit); res.Add(seen); res.Add(rgba);
            return res;
        }
        return null;
    }
    // Ответ без обёртки (FogRefreshRowsPacked): заливка та же, массива нет
    private bool _fogPacked;

    /// Полный пересчёт: источники плоским массивом троек [x, z, r].
    /// Возвращает [lit, seen, rgba] — копии для чтения и текстуры
    public Godot.Collections.Array FogRefresh(float[] src)
    {
        int n = _fogCols * _fogRows;
        Array.Clear(_fogLit, 0, n);
        for (int k = 0; k + 2 < src.Length; k += 3)
            FogStamp(src[k], src[k + 1], src[k + 2]);
        return FogFinish();
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
        {
            int cap2 = Math.Max(64, _pressWakeRows.Length * 2);
            Array.Resize(ref _pressWakeRows, cap2);
            Array.Resize(ref _pressWakeEl, cap2);
        }
        _pressWakeRows[_pressWakeCount] = i;
        _pressWakeEl[_pressWakeCount] = _gateEl[i];
        _pressWakeCount++;
        _gateEl[i] = 0.0f;
    }

    // Сколько СВОИХ (кроме самого бойца) стоит ближе r к точке — копия
    // GDScript unit_grid.allies_count_near, по мелкой сетке ядра
    private int AlliesNearPoint(int self, float x, float z, int fac, float r, int limit)
    {
        if (_gw == 0) return 0;
        int side = FacSlot(fac);
        int dead = DeadState;
        float r2 = r * r;
        int cx0 = (int)((x - r - _gx0) * _ginv);
        int cz0 = (int)((z - r - _gz0) * _ginv);
        int cx1 = (int)((x + r - _gx0) * _ginv);
        int cz1 = (int)((z + r - _gz0) * _ginv);
        if (cx1 < 0 || cz1 < 0 || cx0 >= _gw || cz0 >= _gh) return 0;
        if (cx0 < 0) cx0 = 0;
        if (cz0 < 0) cz0 = 0;
        if (cx1 >= _gw) cx1 = _gw - 1;
        if (cz1 >= _gh) cz1 = _gh - 1;
        int n = 0;
        for (int cz = cz0; cz <= cz1; cz++)
        {
            int b = cz * _gw;
            for (int cx = cx0; cx <= cx1; cx++)
            {
                int j = _head[(b + cx) * Factions + side];
                while (j != -1)
                {
                    if (j != self && _st[j] != dead)
                    {
                        float dx = _px[j] - x, dz = _pz[j] - z;
                        if (dx * dx + dz * dz <= r2)
                        {
                            n++;
                            if (n >= limit) return n;
                        }
                    }
                    j = _next[j];
                }
            }
        }
        return n;
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
    public void AutopilotArm(int i, float speed, float pullSpeed, float stop,
        float pullLim, float cadence, float sideSign)
    {
        if (i < 0 || i >= _capacity) return;
        _pressV[i] = speed; _pressV2[i] = pullSpeed; _pressStop[i] = stop;
        _pressLim[i] = pullLim; _gateT[i] = cadence; _gateEl[i] = 0.0f;
        _sideS[i] = sideSign; _flankB[i] = 0; _gateMode[i] = 0;
        _flags[i] |= FAutopilot;
    }

    // Марш стены к ТОЧКЕ (Unit._phalanx_march): цель — не строка, а место;
    // стоп на ARRIVE_RADIUS, упор и чужой в длине руки будят
    public void AutopilotArmGoal(int i, float speed, float gx, float gz, float stop, float cadence)
    {
        if (i < 0 || i >= _capacity) return;
        _pressV[i] = speed; _pressV2[i] = speed; _pressStop[i] = stop;
        _pressX[i] = gx; _pressZ[i] = gz;
        _pressLim[i] = -1.0f; _gateT[i] = cadence; _gateEl[i] = 0.0f;
        _flankB[i] = 0; _gateMode[i] = GateGoal;
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
        int tick, int scanMod, float scanR,
        float flankTrig, int flankRecheck, float flankStrength)
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
            bool goal = _gateMode[i] == GateGoal;
            if (!goal && (t < 0 || t >= _capacity || (_flags[t] & FPosValid) == 0
                || _st[t] == dead))
            { PressWake(i); continue; }
            armed++;
            // ── ПЛАНОВЫЙ ВОЗВРАТ В GDScript (BigStand, этап 4) ────────────────
            // Автомат боя в GDScript входит раз в cadence (AGGRO_INTERVAL_HOT):
            // сканы заслона и застревания идут в прежнем ритме, а между ними
            // шаг к цели считает ядро. Упор в чужое тело будит сразу (шаг),
            // дистанция удара — тоже; GDScript на входе доводит свои таймеры
            // на прошедшее время (Unit._rear_wake(elapsed))
            _gateEl[i] += delta;
            _gateT[i] -= delta;
            if (_gateT[i] <= 0.0f) { PressWake(i); continue; }
            float x = _px[i], z = _pz[i];
            float dx = (goal ? _pressX[i] : _px[t]) - x;
            float dz = (goal ? _pressZ[i] : _pz[t]) - z;
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
            // Подтягивание рядов: в окне reach + PULL_UP_MAX идём на долю
            // скорости (Unit.PULL_UP_SPEED, без обхода своих — как в
            // GDScript-ветке _should_pull_up), дальше — полным шагом
            float lim = _pressLim[i];
            bool pull = lim > 0.0f && d2 <= lim * lim;
            float sp = pull ? _pressV2[i] : _pressV[i];
            if (!goal) _gateMode[i] = pull ? GatePull : (byte)0;
            // Режим «стоять» (скорость 0): стойка «оборона» ждёт цели на
            // дистанции — только взгляд на цель, шага нет
            if (sp <= 0.0f)
            {
                _vx[i] = 0; _vz[i] = 0;
                _fx[i] = nx; _fz[i] = nz;
                continue;
            }
            float sx = nx, sz = nz;
            if (!pull && !goal)
            {
                // Обход своих — копия Unit._flank_step: ближе flankTrig к
                // цели раз в flankRecheck кадров смотрим, занят ли проход
                // (двое своих в 0.9 м перед носом); занят — шаг с боковой
                // составляющей в свою сторону
                if (d > flankTrig) _flankB[i] = 0;
                else if (((tick + i) % flankRecheck) == 0)
                    _flankB[i] = (byte)(AlliesNearPoint(i, x + nx * 0.8f, z + nz * 0.8f,
                        _fac[i], 0.9f, 2) >= 2 ? 1 : 0);
                if (_flankB[i] != 0)
                {
                    float side = -_sideS[i];
                    sx = nx + (-nz * side) * flankStrength;
                    sz = nz + (nx * side) * flankStrength;
                    float sl = Mathf.Sqrt(sx * sx + sz * sz);
                    if (sl > 1e-6f) { sx /= sl; sz /= sl; }
                }
            }
            _vx[i] = sx * sp; _vz[i] = sz * sp;
            _fx[i] = nx; _fz[i] = nz;
            if (i % shards != phase) continue;
            _stpX[i] = sx * sp * sdelta;
            _stpZ[i] = sz * sp * sdelta;
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

    public int PressWokenCount() => _pressWakeCount;

    /// Пары [строка, секунд с взвода] плоским float[] (см. TakeWokenF)
    public float[] TakePressWokenF()
    {
        var res = new float[_pressWakeCount * 2];
        for (int k = 0; k < _pressWakeCount; k++)
        {
            res[k * 2] = _pressWakeRows[k];
            res[k * 2 + 1] = _pressWakeEl[k];
        }
        _pressWakeCount = 0;
        return res;
    }

    /// Проснувшиеся строки напора — объектами (см. TakeWoken: тот же приём)
    public Godot.Collections.Array TakePressWoken()
    {
        // Пары [боец, секунд с взвода]: GDScript доводит таймеры автомата на
        // прошедшее время (BigStand, этап 4)
        var res = new Godot.Collections.Array();
        for (int k = 0; k < _pressWakeCount; k++)
        {
            var u = _unitOf[_pressWakeRows[k]];
            if (u == null) continue;
            res.Add(u);
            res.Add(_pressWakeEl[k]);
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
        // Свободные слоты слоя СНАРЯДОВ (этап 3 BigStand-5): выдача и возврат
        // без перехода границы за каждый выстрел. У бакетов армии не ведётся
        // (их слотами распоряжается FarUnitRenderer)
        public int[] Free = Array.Empty<int>();
        public int FreeN;
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

    // ── КАДР ЛЕНТЫ ЛИСТАЕТ ЯДРО (визуальный проход, этап E1, 09.09.2026) ────
    // Параметры ленты пишутся ПО СОБЫТИЮ из Unit._set_anim / Spearman
    // (_apply_dir_tex) — RowAnim; фазу и номер кадра ведёт BatchVisual каждый
    // кадр отрисовки и пишет в слот ТОЛЬКО на смену номера. Прежде каждый
    // видимый боец листал кадр в GDScript и на каждую смену пересекал
    // границу (Slot.set_frame → RbWriteFrame). Побочная выгода: стоящий боец
    // с зацикленной лентой покоя может СПАТЬ по картинке — дышать за него
    // продолжает ядро (см. Unit._process_can_sleep)
    private float[] _anFps = Array.Empty<float>();
    private int[] _anFrames = Array.Empty<int>();
    private bool[] _anLoop = Array.Empty<bool>();
    private float[] _anPhase = Array.Empty<float>();
    private int[] _anFrame = Array.Empty<int>();
    // Тихая строка: взгляд позы, точка и время последнего замера хода, срок
    // пробуждения (0 — без срока), признак «идёт» по мягкому порогу (0.6)
    private float[] _vqLx = Array.Empty<float>(), _vqLz = Array.Empty<float>();
    private float[] _vqPx = Array.Empty<float>(), _vqPz = Array.Empty<float>();
    private int[] _vqMs = Array.Empty<int>(), _vqWake = Array.Empty<int>();
    private byte[] _vqMv2 = Array.Empty<byte>();
    // Вспышка попадания и доля жизни у привязанной строки ведёт ядро:
    // остаток вспышки в секундах и её пик (свойство ленты: тролль тусклее)
    private float[] _vFlash = Array.Empty<float>(), _vPeak = Array.Empty<float>();
    private int[] _visOut = new int[1024];
    public int VisListed, VisQuietN;

    // ── КОЛЬЦА ВЫДЕЛЕНИЯ, ТЕНИ И ПОЛОСКИ ЗДОРОВЬЯ — ТОЖЕ СЛОТЫ, ВЕДОМЫЕ ЯДРОМ ─
    // Слои колец/теней (SelectionDecalRenderer) и полосок (HpBarRenderer)
    // держат буферы в тех же Rb, что и бакеты бойцов; привязка строки к слоту
    // — по событию (выделение, Alt), позиция — из нарисованной точки строки в
    // том же проходе. Прежде GDScript на каждый выделенный отряд в каждом
    // кадре читал draw_position (переход границы) и писал 24 float в
    // PackedFloat32Array: две тысячи выделенных стоили 14 мс кадра
    private int[] _ringB = Array.Empty<int>();
    private int[] _shB = Array.Empty<int>();
    private int[] _decI = Array.Empty<int>();
    private int[] _hpB = Array.Empty<int>();
    private int[] _hpI = Array.Empty<int>();
    private float _ringY, _shadowY, _hpBarY;

    // ── ДЕКЛАРАТИВНЫЕ СТРЕЛЫ (хак физтика №1, 09.09.2026) ────────────────
    // Стрела на время полёта — не узел с _process, а ЗАПИСЬ: старт, конец,
    // высота дуги, темп. Ядро каждый кадр двигает все полёты одним проходом,
    // пишет позицию и ось в слот общего MultiMesh стрел и ищет попадание тем
    // же EnemyAt, что звал GDScript (правило XZ-радиуса сохранено дословно).
    // Наружу уходят только СОБЫТИЯ: [id, жертва|null, x, y, z, ax, ay, az] —
    // одна пачка на кадр вместо трёх переходов границы на стрелу на кадр
    // НОМЕР БУФЕРА — У КАЖДОГО ПОЛЁТА СВОЙ (спринт 14). Здесь стояло ОДНО
    // поле `_afB`, и каждый новый запуск перетирал его всем, кто уже в
    // воздухе: BatchArrows писал позиции ВСЕХ полётов в буфер последнего
    // стрелявшего. С появлением второго слоя снарядов (кости гноллов,
    // спринт 13) это стало видно глазом — стрела лучника летела стрелой и
    // на середине дуги превращалась в кость, а на земле лежала костью.
    // Слоёв теперь два, и их будет больше: буфер обязан ехать со снарядом
    private int _afN;
    private int[] _afId = new int[64], _afSlot = new int[64], _afFac = new int[64];
    private int[] _afB = new int[64];
    private float[] _afSx = new float[64], _afSy = new float[64], _afSz = new float[64];
    private float[] _afEx = new float[64], _afEy = new float[64], _afEz = new float[64];
    private float[] _afArc = new float[64], _afT = new float[64], _afRate = new float[64];
    // МАСШТАБ ОСИ — ЭТО ПРИЗНАК «КРУЧУСЬ В ПОЛЁТЕ», А НЕ ГЕОМЕТРИЯ.
    // Шейдер снаряда ось всё равно нормирует, поэтому её МОДУЛЬ свободен:
    // единица — обычная стрела, меньше — кость гнолла, которую рисовать надо
    // кувырком. Канала instance-цвета под это нет (все четыре заняты осью и
    // растворением), а второй слой отрисовки ради одного бита — расточительство
    private float[] _afAxK = new float[64];
    // ── СНАРЯД БЕЗ УЗЛА (BigStand-5, этап 3) ─────────────────────────────
    // Всё, что раньше лежало полями узла Arrow на время полёта, — колонки
    // полёта: урон, стрелок и цель-здание (instance id — GDScript берёт
    // узел через instance_from_id и сам проверяет живость: строка стрелка
    // могла быть переиспользована, id — нет), флаги (снайпер, здание,
    // кость, legacy-узел), длина квада, срок и растворение торчащей, возраст
    // и потолок полёта. Записи узлов (PfLegacy) летят в тех же колонках:
    // ручка perf_config.projectile_core выключена — стрела снова узел, и
    // A/B идёт на одной сборке
    private float[] _afDmg = new float[64], _afLen = new float[64];
    private float[] _afLife = new float[64], _afFade = new float[64];
    private float[] _afAge = new float[64], _afMaxAge = new float[64];
    private int[] _afFlags = new int[64];
    private long[] _afShooter = new long[64], _afTgt = new long[64];
    private readonly Godot.Collections.Array _afEvents = new();
    // Ядро нумерует свои полёты с миллиарда: legacy-узлы ведут свой счётчик
    // с единицы, и ArrowCancel по id не должен снять чужой полёт
    private int _nextFlightId = 1000000000;

    public const int PfLegacy = 1 << 0;
    public const int PfSnipe  = 1 << 1;
    public const int PfTarget = 1 << 2;
    public const int PfBone   = 1 << 3;

    private void AfEnsure()
    {
        if (_afN < _afId.Length) return;
        int cap = _afId.Length * 2;
        Array.Resize(ref _afId, cap); Array.Resize(ref _afSlot, cap); Array.Resize(ref _afFac, cap);
        Array.Resize(ref _afB, cap);
        Array.Resize(ref _afSx, cap); Array.Resize(ref _afSy, cap); Array.Resize(ref _afSz, cap);
        Array.Resize(ref _afEx, cap); Array.Resize(ref _afEy, cap); Array.Resize(ref _afEz, cap);
        Array.Resize(ref _afArc, cap); Array.Resize(ref _afT, cap); Array.Resize(ref _afRate, cap);
        Array.Resize(ref _afAxK, cap);
        Array.Resize(ref _afDmg, cap); Array.Resize(ref _afLen, cap);
        Array.Resize(ref _afLife, cap); Array.Resize(ref _afFade, cap);
        Array.Resize(ref _afAge, cap); Array.Resize(ref _afMaxAge, cap);
        Array.Resize(ref _afFlags, cap);
        Array.Resize(ref _afShooter, cap); Array.Resize(ref _afTgt, cap);
    }

    private int AfPush(int id, int b, int slot, Vector3 s, Vector3 e,
        float arcH, float rate, int fac, float axK, int flags)
    {
        AfEnsure();
        int k = _afN++;
        _afB[k] = b;
        _afId[k] = id; _afSlot[k] = slot; _afFac[k] = fac;
        _afSx[k] = s.X; _afSy[k] = s.Y; _afSz[k] = s.Z;
        _afEx[k] = e.X; _afEy[k] = e.Y; _afEz[k] = e.Z;
        _afArc[k] = arcH; _afT[k] = 0.0f; _afRate[k] = rate;
        _afAxK[k] = axK;
        _afFlags[k] = flags;
        _afDmg[k] = 0.0f; _afLen[k] = 0.0f; _afLife[k] = 0.0f; _afFade[k] = 0.0f;
        _afAge[k] = 0.0f; _afMaxAge[k] = 1e9f;
        _afShooter[k] = 0; _afTgt[k] = 0;
        return k;
    }

    /// Полёт УЗЛА Arrow (legacy-путь, ручка projectile_core = false): события
    /// уходят прежним Godot-массивом с ссылкой на жертву, узел разбирает сам
    public void ArrowLaunch(int id, int b, int slot, Vector3 s, Vector3 e,
        float arcH, float rate, int fac, float axK = 1.0f)
    {
        AfPush(id, b, slot, s, e, arcH, rate, fac, axK, PfLegacy);
    }

    /// ВЫСТРЕЛ БЕЗ УЗЛА: слот слоя берётся здесь же, первый кадр слота пишется
    /// сразу (точка вылета, ось по скорости в t = 0, покрытие 1). −1 — в слое
    /// нет свободного слота: вызывающий растит слой (RbGrow) и повторяет.
    /// shooterId / tgtId — instance id узлов (0 — нет)
    public int ProjectileFire(int b, Vector3 s, Vector3 e, float arcH, float rate,
        int fac, float axK, float dmg, long shooterId, long tgtId, int flags,
        float len, float life, float fade, float maxAge)
    {
        if (b < 0 || b >= _rb.Count) return -1;
        int slot = RbAcquire(b);
        if (slot < 0) return -1;
        int id = _nextFlightId++;
        int k = AfPush(id, b, slot, s, e, arcH, rate, fac, axK, flags & ~PfLegacy);
        _afDmg[k] = dmg; _afLen[k] = len; _afLife[k] = life; _afFade[k] = fade;
        _afMaxAge[k] = maxAge; _afShooter[k] = shooterId; _afTgt[k] = tgtId;
        // Ось в t = 0 — та же формула, что в BatchArrows
        float ax = e.X - s.X, ay = e.Y - s.Y + Mathf.Pi * arcH, az = e.Z - s.Z;
        float al = Mathf.Sqrt(ax * ax + ay * ay + az * az);
        if (al < 1e-4f) { ax = 0.0f; ay = 0.0f; az = -1.0f; } else { ax /= al; ay /= al; az /= al; }
        SlotWrite(b, slot, s.X, s.Y, s.Z, ax * axK, ay * axK, az * axK, 1.0f);
        return id;
    }

    /// Слот снаряда целиком: единичный базис (ориентацию строит шейдер из
    /// оси в цвете), точка, ось и покрытие
    private void SlotWrite(int b, int slot, float x, float y, float z,
        float ax, float ay, float az, float fade)
    {
        var r = _rb[b];
        int o = slot * RbStride;
        var buf = r.Buf;
        if (o + RbStride > buf.Length) return;
        buf[o] = 1.0f; buf[o + 1] = 0.0f; buf[o + 2] = 0.0f; buf[o + 3] = x;
        buf[o + 4] = 0.0f; buf[o + 5] = 1.0f; buf[o + 6] = 0.0f; buf[o + 7] = y;
        buf[o + 8] = 0.0f; buf[o + 9] = 0.0f; buf[o + 10] = 1.0f; buf[o + 11] = z;
        buf[o + 12] = ax * 0.5f + 0.5f; buf[o + 13] = ay * 0.5f + 0.5f;
        buf[o + 14] = az * 0.5f + 0.5f; buf[o + 15] = fade;
        r.Dirty = true;
    }

    public void ArrowCancel(int id)
    {
        for (int k = 0; k < _afN; k++)
            if (_afId[k] == id) { AfRemove(k); return; }
    }

    public int ArrowFlights() => _afN;

    /// Полётов на слое b (стенды и совместимость flight_count у слоя)
    public int FlightsOn(int b)
    {
        int n = 0;
        for (int k = 0; k < _afN; k++) if (_afB[k] == b) n++;
        return n;
    }

    /// Окно стендов: [id, слой, слот, флаги] × N
    public int[] FlightList()
    {
        var res = new int[_afN * 4];
        for (int k = 0; k < _afN; k++)
        {
            res[k * 4] = _afId[k]; res[k * 4 + 1] = _afB[k];
            res[k * 4 + 2] = _afSlot[k]; res[k * 4 + 3] = _afFlags[k];
        }
        return res;
    }

    /// Окно стендов: [sx, sy, sz, ex, ey, ez, t, возраст, дуга, темп, урон] полёта или пусто
    public float[] FlightInfo(int id)
    {
        for (int k = 0; k < _afN; k++)
            if (_afId[k] == id)
                return new[] { _afSx[k], _afSy[k], _afSz[k], _afEx[k], _afEy[k], _afEz[k],
                    _afT[k], _afAge[k], _afArc[k], _afRate[k], _afDmg[k] };
        return Array.Empty<float>();
    }

    /// Окно стендов: instance id стрелка полёта (0 — нет / нет полёта)
    public long FlightShooter(int id)
    {
        for (int k = 0; k < _afN; k++) if (_afId[k] == id) return _afShooter[k];
        return 0;
    }

    private void AfRemove(int k)
    {
        int last = _afN - 1;
        if (k != last)
        {
            _afId[k] = _afId[last]; _afSlot[k] = _afSlot[last]; _afFac[k] = _afFac[last];
            _afB[k] = _afB[last];
            _afSx[k] = _afSx[last]; _afSy[k] = _afSy[last]; _afSz[k] = _afSz[last];
            _afEx[k] = _afEx[last]; _afEy[k] = _afEy[last]; _afEz[k] = _afEz[last];
            _afArc[k] = _afArc[last]; _afT[k] = _afT[last]; _afRate[k] = _afRate[last];
            _afAxK[k] = _afAxK[last];
            _afDmg[k] = _afDmg[last]; _afLen[k] = _afLen[last];
            _afLife[k] = _afLife[last]; _afFade[k] = _afFade[last];
            _afAge[k] = _afAge[last]; _afMaxAge[k] = _afMaxAge[last];
            _afFlags[k] = _afFlags[last];
            _afShooter[k] = _afShooter[last]; _afTgt[k] = _afTgt[last];
        }
        _afN = last;
    }

    // ── СОБЫТИЯ СНАРЯДОВ ЯДРА — ПАЧКОЙ, PACKED-МАССИВАМИ ─────────────────
    // Прежний Godot.Collections.Array нёс ссылку на жертву и Vector3 в
    // Variant-обёртках — финализируемых, то есть сборки gen1 на каждой пачке.
    // Теперь целые — long[] (PackedInt64Array: instance id не влезает в
    // int32), дроби — float[]; жертва — СТРОКА ядра, узел GDScript берёт из
    // своего реестра строка → узел
    private readonly System.Collections.Generic.List<long> _pjEvI = new();
    private readonly System.Collections.Generic.List<float> _pjEvF = new();
    public const int PjEvIStride = 8;   // id, тип, строка жертвы, стрелок, цель, флаги, слой, слот
    public const int PjEvFStride = 8;   // x, y, z, ax, ay, az, урон, длина

    private void PjEvent(int k, int type, int victim, float x, float y, float z,
        float ax, float ay, float az)
    {
        _pjEvI.Add(_afId[k]); _pjEvI.Add(type); _pjEvI.Add(victim);
        _pjEvI.Add(_afShooter[k]); _pjEvI.Add(_afTgt[k]); _pjEvI.Add(_afFlags[k]);
        _pjEvI.Add(_afB[k]); _pjEvI.Add(_afSlot[k]);
        _pjEvF.Add(x); _pjEvF.Add(y); _pjEvF.Add(z);
        _pjEvF.Add(ax); _pjEvF.Add(ay); _pjEvF.Add(az);
        _pjEvF.Add(_afDmg[k]); _pjEvF.Add(_afLen[k]);
    }

    public bool HasProjectileEvents() => _pjEvI.Count > 0;
    public long[] TakeProjectileEventsI() { var r = _pjEvI.ToArray(); _pjEvI.Clear(); return r; }
    public float[] TakeProjectileEventsF() { var r = _pjEvF.ToArray(); _pjEvF.Clear(); return r; }

    // ── АГРЕГАТ ЗВУКА ПРОМАХОВ ЗА КАДР — ПО ГРУППАМ В РАДИУСЕ ─────────────
    // Не play_3d на каждую воткнувшуюся стрелу, а один звук на группу
    // промахов в клетке MissCell метров (до MissMax групп за кадр, лишние
    // сливаются в первую): два залпа на разных концах карты звучат каждый у
    // себя, а сотня стрел одного залпа — одним ударом в центре тяжести.
    // Лимиты AudioManager (gap) и так пускали не больше одного звука в кадр,
    // слышимый результат тот же, вызовов — на два порядка меньше
    private const float MissCell = 32.0f;
    private const int MissMax = 8;
    private int _missK;
    private readonly long[] _missKey = new long[MissMax];
    private readonly int[] _missCnt = new int[MissMax];
    private readonly float[] _missSx = new float[MissMax], _missSy = new float[MissMax], _missSz = new float[MissMax];

    private void MissNote(float x, float y, float z)
    {
        long key = ((long)MathF.Floor(x / MissCell) << 32) ^ (uint)(int)MathF.Floor(z / MissCell);
        int k = -1;
        for (int i = 0; i < _missK; i++) if (_missKey[i] == key) { k = i; break; }
        if (k < 0)
        {
            if (_missK < MissMax) { k = _missK++; _missKey[k] = key; _missCnt[k] = 0; _missSx[k] = 0; _missSy[k] = 0; _missSz[k] = 0; }
            else k = 0;
        }
        _missCnt[k]++; _missSx[k] += x; _missSy[k] += y; _missSz[k] += z;
    }

    /// [n, x, y, z] × групп промахов за кадр (пусто — промахов не было)
    public float[] TakeMissSound()
    {
        if (_missK == 0) return Array.Empty<float>();
        var r = new float[_missK * 4];
        for (int i = 0; i < _missK; i++)
        {
            float inv = 1.0f / _missCnt[i];
            r[i * 4] = _missCnt[i]; r[i * 4 + 1] = _missSx[i] * inv;
            r[i * 4 + 2] = _missSy[i] * inv; r[i * 4 + 3] = _missSz[i] * inv;
        }
        _missK = 0;
        return r;
    }

    // ── ТОРЧАЩИЕ СНАРЯДЫ — МАССИВ ЯДРА (BigStand-5, этап 3) ──────────────
    // Прежний реестр GameManager._stuck_arrows держал УЗЛЫ и звал tick_stuck
    // у каждого каждый кадр (~300 входов в GDScript); потолок перебирал весь
    // список на каждый прилёт. Здесь: срок, растворение и потолок — колонки,
    // один проход в кадр, порядок вставки сохранён (уплотнение, не свап) —
    // «самая старая» это первая в массиве, как и было
    private int _stN;
    private int[] _stId = new int[64], _stB = new int[64], _stSlot = new int[64];
    // id полёта, из которого стрела воткнулась (0 — декор): стендам, ведущим
    // снаряд от выстрела до земли
    private int[] _stSrc = new int[64];
    private float[] _stLeft = new float[64], _stFade = new float[64];
    private bool[] _stFading = new bool[64], _stCorpse = new bool[64];
    private int _nextStuckId = 1;
    // Настройки (GameManager.ProjectileConfig): потолок, растворение при
    // вытеснении, минимальный наклон вниз, доля над грунтом, разброс угла
    private int _pjMaxStuck = 160;
    private float _pjEvictFade = 0.6f, _pjMinDown = 1.0f, _pjExposed = 2.0f / 3.0f, _pjJitter = 0.21f;

    public void ProjectileConfig(int maxStuck, float evictFade, float minDown, float exposed, float jitter)
    {
        _pjMaxStuck = maxStuck; _pjEvictFade = evictFade;
        _pjMinDown = minDown; _pjExposed = exposed; _pjJitter = jitter;
    }

    private int StuckAdd(int b, int slot, float life, float fade, bool corpse, int src = 0)
    {
        if (_stN >= _stId.Length)
        {
            int cap = _stId.Length * 2;
            Array.Resize(ref _stId, cap); Array.Resize(ref _stB, cap); Array.Resize(ref _stSlot, cap);
            Array.Resize(ref _stSrc, cap);
            Array.Resize(ref _stLeft, cap); Array.Resize(ref _stFade, cap);
            Array.Resize(ref _stFading, cap); Array.Resize(ref _stCorpse, cap);
        }
        int k = _stN++;
        int id = _nextStuckId++;
        _stId[k] = id; _stB[k] = b; _stSlot[k] = slot; _stSrc[k] = src;
        _stLeft[k] = life; _stFade[k] = Math.Max(fade, 0.0001f);
        _stFading[k] = false; _stCorpse[k] = corpse;
        // Потолок — как у прежнего note_stuck_arrow: перебор сверх потолка
        // отправляет догорать самых старых, ещё не гаснущих
        int over = _stN - _pjMaxStuck;
        for (int i = 0; over > 0 && i < _stN; i++)
        {
            over--;
            if (!_stFading[i]) StuckFadeAt(i, _pjEvictFade);
        }
        return id;
    }

    private void StuckFadeAt(int k, float secs)
    {
        float want = Math.Max(secs, 0.05f);
        if (_stCorpse[k]) { _stCorpse[k] = false; _stLeft[k] = want; }
        else if (want < _stLeft[k]) _stLeft[k] = want;
        _stFading[k] = true;
    }

    private int StuckIndex(int id)
    {
        for (int k = 0; k < _stN; k++) if (_stId[k] == id) return k;
        return -1;
    }

    /// Стрелу гасит тело, в котором она торчит, или потолок: остаток срока
    /// укорачивается до secs, растворение — своё по виду снаряда
    public void StuckFade(int id, float secs)
    {
        int k = StuckIndex(id);
        if (k >= 0) StuckFadeAt(k, secs);
    }

    /// Снять немедленно (тело догорело): слот в свободные, запись — вон
    public void StuckRemove(int id)
    {
        int k = StuckIndex(id);
        if (k < 0) return;
        RbRelease(_stB[k], _stSlot[k]);
        StuckDrop(k);
    }

    private void StuckDrop(int k)
    {
        int n = _stN - 1;
        for (int i = k; i < n; i++)
        {
            _stId[i] = _stId[i + 1]; _stB[i] = _stB[i + 1]; _stSlot[i] = _stSlot[i + 1];
            _stSrc[i] = _stSrc[i + 1];
            _stLeft[i] = _stLeft[i + 1]; _stFade[i] = _stFade[i + 1];
            _stFading[i] = _stFading[i + 1]; _stCorpse[i] = _stCorpse[i + 1];
        }
        _stN = n;
    }

    /// Новая партия: записи полётов и торчащих прошлой сцены — вон (слои
    /// пересобираются с новыми номерами бакетов, писать в старые незачем)
    public void ProjectilesReset()
    {
        // Слоты полётов и торчащих — обратно в свободные своих слоёв (слой
        // может пережить сброс: стенды чистят поле посреди сцены)
        for (int k = 0; k < _afN; k++)
            if ((_afFlags[k] & PfLegacy) == 0 && _afB[k] >= 0 && _afB[k] < _rb.Count)
                RbRelease(_afB[k], _afSlot[k]);
        for (int k = 0; k < _stN; k++)
            if (_stB[k] >= 0 && _stB[k] < _rb.Count) RbRelease(_stB[k], _stSlot[k]);
        _afN = 0; _stN = 0;
        _pjEvI.Clear(); _pjEvF.Clear(); _afEvents.Clear();
        _missK = 0;
    }

    public int StuckCount() => _stN;
    public int StuckFadingCount() { int n = 0; for (int k = 0; k < _stN; k++) if (_stFading[k]) n++; return n; }
    public float StuckLeft(int id) { int k = StuckIndex(id); return k < 0 ? -1.0f : _stLeft[k]; }
    public bool StuckIsFading(int id) { int k = StuckIndex(id); return k >= 0 && _stFading[k]; }
    public bool StuckInCorpse(int id) { int k = StuckIndex(id); return k >= 0 && _stCorpse[k]; }

    /// Окно стендов: [id, слой, слот, вТеле, id полёта] × N в порядке вставки
    public int[] StuckList()
    {
        var res = new int[_stN * 5];
        for (int k = 0; k < _stN; k++)
        {
            res[k * 5] = _stId[k]; res[k * 5 + 1] = _stB[k];
            res[k * 5 + 2] = _stSlot[k]; res[k * 5 + 3] = _stCorpse[k] ? 1 : 0;
            res[k * 5 + 4] = _stSrc[k];
        }
        return res;
    }

    /// Срок и растворение торчащих — один проход в кадр (в _process: на паузе
    /// стрелы стоят). Растворение — покрытие в альфе цвета слота, тот же дизер
    public void StuckTick(float delta)
    {
        if (_stN == 0) return;
        int w = 0;
        for (int k = 0; k < _stN; k++)
        {
            bool keep = true;
            if (!_stCorpse[k])
            {
                float left = _stLeft[k] - delta;
                if (left <= 0.0f)
                {
                    RbRelease(_stB[k], _stSlot[k]);
                    keep = false;
                }
                else
                {
                    _stLeft[k] = left;
                    if (left <= _stFade[k])
                    {
                        _stFading[k] = true;
                        var r = _rb[_stB[k]];
                        int o = _stSlot[k] * RbStride + 15;
                        if (o < r.Buf.Length) { r.Buf[o] = left / _stFade[k]; r.Dirty = true; }
                    }
                }
            }
            if (!keep) continue;
            if (w != k)
            {
                _stId[w] = _stId[k]; _stB[w] = _stB[k]; _stSlot[w] = _stSlot[k];
                _stSrc[w] = _stSrc[k];
                _stLeft[w] = _stLeft[k]; _stFade[w] = _stFade[k];
                _stFading[w] = _stFading[k]; _stCorpse[w] = _stCorpse[k];
            }
            w++;
        }
        _stN = w;
    }

    private static float Frac(float v) => v - MathF.Floor(v);

    // Поворот вектора вокруг единичной оси (формула Родрига) — как Vector3.rotated
    private static void Rotate(ref float x, ref float y, ref float z, float ux, float uy, float uz, float ang)
    {
        float c = MathF.Cos(ang), sn = MathF.Sin(ang);
        float dot = ux * x + uy * y + uz * z;
        float cx = uy * z - uz * y, cy = uz * x - ux * z, cz = ux * y - uy * x;
        float nx = x * c + cx * sn + ux * dot * (1.0f - c);
        float ny = y * c + cy * sn + uy * dot * (1.0f - c);
        float nz = z * c + cz * sn + uz * dot * (1.0f - c);
        x = nx; y = ny; z = nz;
    }

    /// ПРОМАХ ЦЕЛИКОМ В ЯДРЕ: доворот вниз, детерминированный разброс ±jitter
    /// от точки (та же формула, что Arrow._stick_jitter — два прогона одного
    /// боя дают одно поле), высота грунта той же Height, что у шага, запись
    /// слота и учёт в торчащих. Возвращает id торчащей
    public int ProjectileLand(int b, int slot, float x, float y, float z,
        float ax, float ay, float az, float len, float life, float fade, float reliefAmp,
        int srcId)
    {
        if (b < 0 || b >= _rb.Count) return -1;
        float al = MathF.Sqrt(ax * ax + ay * ay + az * az);
        if (al < 1e-4f) { ax = 0.0f; ay = -1.0f; az = 0.0f; } else { ax /= al; ay /= al; az /= al; }
        if (ay > -_pjMinDown)
        {
            ay = -_pjMinDown;
            al = MathF.Sqrt(ax * ax + ay * ay + az * az);
            ax /= al; ay /= al; az /= al;
        }
        float h1 = Frac(MathF.Sin(x * 12.9898f + z * 78.233f) * 43758.5453f);
        float h2 = Frac(MathF.Sin(x * 39.3468f + z * 11.135f) * 24634.6345f);
        Rotate(ref ax, ref ay, ref az, 0.0f, 1.0f, 0.0f, (h1 - 0.5f) * 2.0f * _pjJitter);
        float sx = az, sz = -ax;
        float sl = MathF.Sqrt(sx * sx + sz * sz);
        if (sl > 1e-3f)
        {
            sx /= sl; sz /= sl;
            Rotate(ref ax, ref ay, ref az, sx, 0.0f, sz, (h2 - 0.5f) * 2.0f * _pjJitter);
        }
        if (ay > -_pjMinDown * 0.75f) ay = -_pjMinDown * 0.75f;
        al = MathF.Sqrt(ax * ax + ay * ay + az * az);
        ax /= al; ay /= al; az /= al;
        float gy = Height(x, z, reliefAmp);
        float back = len * (_pjExposed - 0.5f);
        SlotWrite(b, slot, x - ax * back, gy - ay * back, z - az * back, ax, ay, az, 1.0f);
        return StuckAdd(b, slot, life, fade, false, srcId);
    }

    /// Стрела в теле (или в голове павшего): точка и угол заданы снаружи
    /// (их знает CorpseRenderer), срока нет — гасит тело (StuckFade)
    public int ProjectileStick(int b, int slot, float atX, float atY, float atZ,
        float dx, float dy, float dz, float len, bool inCorpse, float life, float fade)
    {
        if (b < 0 || b >= _rb.Count) return -1;
        float dl = MathF.Sqrt(dx * dx + dy * dy + dz * dz);
        if (dl < 1e-4f) { dx = 0.0f; dy = -1.0f; dz = 0.0f; } else { dx /= dl; dy /= dl; dz /= dl; }
        if (dy > -_pjMinDown)
        {
            dy = -_pjMinDown;
            dl = MathF.Sqrt(dx * dx + dy * dy + dz * dz);
            dx /= dl; dy /= dl; dz /= dl;
        }
        float back = len * (_pjExposed - 0.5f);
        SlotWrite(b, slot, atX - dx * back, atY - dy * back, atZ - dz * back, dx, dy, dz, 1.0f);
        return StuckAdd(b, slot, inCorpse ? 1e9f : life, fade, inCorpse);
    }

    /// Снаряд ядра никуда не воткнулся (жертва мертва/недействительна, здание
    /// не приняло) — слот в свободные без следа
    public void ProjectileDrop(int b, int slot)
    {
        if (b < 0 || b >= _rb.Count) return;
        RbRelease(b, slot);
    }

    /// Шаг всех полётов. Обход С КОНЦА: снятый полёт подменяется последним.
    /// reliefAmp — амплитуда рельефа для высоты грунта у промахов ядра
    public void BatchArrows(float delta, float hitRadius, float reliefAmp = 0.0f)
    {
        if (_afN == 0) return;
        for (int k = _afN - 1; k >= 0; k--)
        {
            // БУФЕР У КАЖДОГО СВОЙ: снаряды разных слоёв (стрелы, кости)
            // летят вперемешку, и писать их в один буфер нельзя
            int bIdx = _afB[k];
            if (bIdx < 0 || bIdx >= _rb.Count) { AfRemove(k); continue; }
            var rb = _rb[bIdx];
            var buf = rb.Buf;
            float t = _afT[k] + _afRate[k] * delta;
            if (t > 1.0f) t = 1.0f;
            _afT[k] = t;
            float sx = _afSx[k], sy = _afSy[k], sz = _afSz[k];
            float ex = _afEx[k], ey = _afEy[k], ez = _afEz[k];
            float x = sx + (ex - sx) * t;
            float y = sy + (ey - sy) * t + Mathf.Sin(t * Mathf.Pi) * _afArc[k];
            float z = sz + (ez - sz) * t;
            // Ось — та же формула, что Arrow._velocity_dir
            float ax = ex - sx, ay = ey - sy + Mathf.Pi * Mathf.Cos(t * Mathf.Pi) * _afArc[k], az = ez - sz;
            float al = Mathf.Sqrt(ax * ax + ay * ay + az * az);
            if (al < 1e-4f) { ax = 0.0f; ay = 0.0f; az = -1.0f; } else { ax /= al; ay /= al; az /= al; }
            int o = _afSlot[k] * RbStride;
            if (o + RbStride <= buf.Length)
            {
                buf[o + 3] = x; buf[o + 7] = y; buf[o + 11] = z;
                // Модуль оси несёт признак кувырка (см. _afAxK)
                float axk = _afAxK[k];
                buf[o + 12] = ax * axk * 0.5f + 0.5f; buf[o + 13] = ay * axk * 0.5f + 0.5f;
                buf[o + 14] = az * axk * 0.5f + 0.5f; buf[o + 15] = 1.0f;
                rb.Dirty = true;
            }
            // Попадание — тем же правилом, что было в Arrow._check_hit
            int j = EnemyRowAt(x, z, hitRadius, _afFac[k]);
            int flags = _afFlags[k];
            if ((flags & PfLegacy) != 0)
            {
                if (j >= 0 || t >= 1.0f)
                {
                    _afEvents.Add(_afId[k]);
                    _afEvents.Add(j >= 0 ? _unitOf[j] as Godot.Node3D : null);
                    _afEvents.Add(new Vector3(x, y, z));
                    _afEvents.Add(new Vector3(ax, ay, az));
                    AfRemove(k);
                }
                continue;
            }
            _afAge[k] += delta;
            if (j >= 0)
            {
                // Касание чужого — решение (броня, щит, тело) за GDScript;
                // слот остаётся за событием, пока его не разберут
                PjEvent(k, 0, j, x, y, z, ax, ay, az);
                AfRemove(k);
                continue;
            }
            if (t >= 1.0f || _afAge[k] >= _afMaxAge[k])
            {
                if ((flags & PfTarget) != 0)
                {
                    // Долетела до назначенного здания — урон списывает GDScript
                    PjEvent(k, 1, -1, x, y, z, ax, ay, az);
                    AfRemove(k);
                    continue;
                }
                // ПРОМАХ — целиком здесь: ни события, ни узла
                ProjectileLand(bIdx, _afSlot[k], x, y, z, ax, ay, az,
                    _afLen[k], _afLife[k], _afFade[k], reliefAmp, _afId[k]);
                MissNote(x, y, z);
                AfRemove(k);
            }
        }
    }

    /// События полётов за кадр (плоско по четыре: id, жертва|null, точка, ось)
    public Godot.Collections.Array TakeArrowEvents()
    {
        var res = new Godot.Collections.Array(_afEvents);
        _afEvents.Clear();
        return res;
    }

    public void DecalConfig(float ringY, float shadowY, float hpBarY)
    { _ringY = ringY; _shadowY = shadowY; _hpBarY = hpBarY; }

    public void RowAnim(int i, int frames, float fps, bool loop, float phase)
    {
        if (i < 0 || i >= _capacity) return;
        _anFrames[i] = frames; _anFps[i] = fps; _anLoop[i] = loop;
        _anPhase[i] = phase; _anFrame[i] = -1;
    }

    public void DecalBind(int i, int ringB, int shB, int idx)
    {
        if (i < 0 || i >= _capacity) return;
        _ringB[i] = ringB; _shB[i] = shB; _decI[i] = idx;
    }
    public void DecalUnbind(int i)
    {
        if (i < 0 || i >= _capacity) return;
        _ringB[i] = -1; _shB[i] = -1;
    }
    public void HpBind(int i, int b, int idx)
    {
        if (i < 0 || i >= _capacity) return;
        _hpB[i] = b; _hpI[i] = idx;
    }
    public void HpUnbind(int i)
    {
        if (i < 0 || i >= _capacity) return;
        _hpB[i] = -1;
    }

    /// Полный трансформ слота тремя строками базиса и точкой (кольца, тени,
    /// полоски — у них базис не единичный). Цвет не трогается
    public void RbWriteXform(int b, int idx, Vector3 b0, Vector3 b1, Vector3 b2, Vector3 pos)
    {
        var r = _rb[b];
        int o = idx * RbStride;
        var buf = r.Buf;
        buf[o] = b0.X; buf[o + 1] = b1.X; buf[o + 2] = b2.X; buf[o + 3] = pos.X;
        buf[o + 4] = b0.Y; buf[o + 5] = b1.Y; buf[o + 6] = b2.Y; buf[o + 7] = pos.Y;
        buf[o + 8] = b0.Z; buf[o + 9] = b1.Z; buf[o + 10] = b2.Z; buf[o + 11] = pos.Z;
        r.Dirty = true;
    }

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

    // ── СПИСОК СТРОК, КОТОРЫМ НУЖЕН GDSCRIPT-ТИК (BigStand-5, этап 1) ─────────
    // Замер qa_bigstand 17.09.2026: в замесе 3886 из 2862 ATTACKING 1460 вёл
    // автопилот, 786 дремали, 15 давил напор — и все они всё равно входили в
    // Unit.tick_physics на своём шарде: окно ходьбы, сравнение позы,
    // queue_pose (позицию записало само ядро), проверки сна и лежания — и
    // выход. ~565 входов в кадр по ~5 мкс = 2.5-3 мс физтика ни на что.
    // Теперь диспетчер GameManager идёт не по реестру узлов, а по списку
    // строк, который собирает ядро: живая, тикающая (FTickOn — зеркало
    // Unit.tick_on), не ведомая ядром. Ведомая — это автопилот, напор или
    // дрёма ПРИ состоянии ATTACKING (ровно те ворота, что стояли в
    // tick_physics), либо матрица отряда (FMatrixLed). Строки родов войск,
    // у которых в тике живут свои часы (лучник — отложенный выстрел
    // снайпера, монах, рабочий, гнолл, тролль, туша), помечены FTickAlways и
    // из списка не выпадают — то же правило, что у may_sleep_physics.
    // Шард — по номеру строки (i % shards == phase): боец опрашивается раз в
    // shards тактов с дельтой delta*shards, как и раньше; порядок обхода —
    // порядок отсортированного списка живых.
    public const int FTickOn = 1 << 23;
    public const int FTickAlways = 1 << 24;
    public const int FMatrixLed = 1 << 25;
    // ── ОЖИДАНИЕ ТАКТА АГРО В ЯДРЕ (BigStand-5, этап 1б) ──────────────────
    // Стоящий в бою боец (IDLE, чужие рядом — сон физики не положен) между
    // тактами авто-агро (0.5-2 с) делал в тике только преамбулу и декремент
    // таймера. Таймер теперь тикает здесь (_aggroT), строка вне списка до
    // истечения; будят события (приказ, удар, смена цели — Unit._core_release).
    // Не взводится у стойки «оборона» (там _phalanx_advance каждый такт), у
    // паникующих, бегущих, отходящих и у родов войск с FTickAlways
    public const int FIdleWait = 1 << 26;
    // ── ВИЗУАЛЬНО ТИХАЯ СТРОКА (BigStand-5, этап 5) ────────────────────────
    // GDScript-тик картинки (Unit.tick_visual) у привязанной к отрисовке
    // строки не входит вовсе, пока ядро не заметит повод: истёк срок замка
    // анимации, сменилась видимость по туману или LOD, началась/кончилась
    // ходьба, повернулся взгляд ведомого ядром. GDScript снимает флаг сам на
    // своих событиях (смена состояния, поза, приказ, удар — _vis_wake)
    public const int FVisQuiet = 1 << 27;
    public const int FVisMoving = 1 << 28;   // объявлено: лента ходьбы идёт
    public const int FVisSeen = 1 << 29;     // объявлено: в поле LOD
    public const int FVisLit = 1 << 30;      // объявлено: освещён (чужой)
    private int[] _tickOut = new int[1024];
    public int TickListed;   // сколько строк ушло в список последним вызовом (стендам)
    public int TickSkipped;  // сколько живых тикающих строк ядро оставило себе
    public int TickSlowed;   // сколько скрытых туманом строк пропущено в этот такт
    public int TickHidden;   // сколько строк тикает на низкой частоте (в тумане)

    public void IdleWaitArm(int i, float t)
    {
        if (i < 0 || i >= _capacity) return;
        _aggroT[i] = t;
        _flags[i] |= FIdleWait;
    }

    /// Снятие ожидания событием: остаток таймера отдаём вызывающему — поле
    /// _aggro_timer у бойца на время ожидания было заморожено (как у дрёмы)
    public float IdleWaitClear(int i)
    {
        if (i < 0 || i >= _capacity) return 0.0f;
        _flags[i] &= ~FIdleWait;
        return _aggroT[i] > 0.0f ? _aggroT[i] : 0.0f;
    }

    /// delta — шаг ЭТОЙ строки (delta кадра × shards): строка посещается раз
    /// в shards тактов, как и её GDScript-тик
    // ── СКРЫТЫЙ ТУМАНОМ ТИКАЕТ РЕЖЕ (ТЗ 19.09.2026, «Fog-of-War Sleep») ──────
    // Чужой боец (fac != playerFac), чья ячейка маски тумана не освещена, и
    // не в бою (st != ATTACKING), посещается раз в fogSlowDiv своих тактов и
    // отдаётся ОТРИЦАТЕЛЬНЫМ номером (−i−1): диспетчер тикает его с дельтой
    // × fogSlowDiv — часы, патруль и шаг честные, только реже. Освещённый
    // (край тумана рассеялся, отряд игрока подошёл) уже в СЛЕДУЮЩЕМ такте
    // идёт полной частотой — маска ядра та же, что у картинки (FogRefresh).
    // Полный сон здесь не годится: патруль обязан ХОДИТЬ, а тик раз в две
    // секунды дал бы шаг в 4-6 м сквозь скалы. fogSlowDiv 0 — как прежде
    public int[] TickRows(int shards, int phase, int attackingState, int idleState, float delta,
        int armyTicks, int playerFac, int fogSlowDiv)
    {
        int n = 0;
        int skipped = 0;
        int slowed = 0, hidden = 0;
        int dead = DeadState;
        int led = FAutopilot | FRearPress | FAtkSnooze;
        bool fogOk = fogSlowDiv > 1 && _fogCols > 0 && _fogLit.Length == _fogCols * _fogRows;
        int sh = Math.Max(shards, 1);
        int slowPhase = (armyTicks / sh) % Math.Max(fogSlowDiv, 1);
        for (int k = 0; k < _liveCount; k++)
        {
            int i = _liveRows[k];
            if (shards > 1 && (i % shards) != phase) continue;
            int fl = _flags[i];
            if ((fl & FTickOn) == 0) continue;
            int st = _st[i];
            if (st == dead) continue;
            if ((fl & FTickAlways) == 0)
            {
                if ((fl & FMatrixLed) != 0) { skipped++; continue; }
                if ((fl & led) != 0 && st == attackingState) { skipped++; continue; }
                if ((fl & FIdleWait) != 0 && st == idleState)
                {
                    float t = _aggroT[i] - delta;
                    _aggroT[i] = t;
                    if (t > 0.0f) { skipped++; continue; }
                    _flags[i] = fl & ~FIdleWait;
                }
            }
            bool slow = false;
            if (fogOk && _fac[i] != playerFac && st != attackingState && (fl & FPosValid) != 0)
            {
                int cx = (int)((_px[i] + _fogHalfX) / _fogCell);
                int cz = (int)((_pz[i] + _fogHalfZ) / _fogCell);
                bool lit = cx >= 0 && cz >= 0 && cx < _fogCols && cz < _fogRows
                    && _fogLit[cz * _fogCols + cx] != 0;
                if (!lit)
                {
                    hidden++;
                    if (((i / sh) % fogSlowDiv) != slowPhase) { slowed++; continue; }
                    slow = true;
                }
            }
            if (n >= _tickOut.Length) Array.Resize(ref _tickOut, _tickOut.Length * 2);
            _tickOut[n++] = slow ? -(i + 1) : i;
        }
        TickListed = n;
        TickSkipped = skipped;
        TickSlowed = slowed;
        TickHidden = hidden;
        var res = new int[n];
        Array.Copy(_tickOut, res, n);
        return res;
    }

    // ── ТИХИЕ СТРОКИ: API (BigStand-5, этап 5) ──────────────────────────────
    /// Строка объявляет себя тихой: что она уже нарисовала (взгляд позы,
    /// идёт ли, видна ли LOD, освещена ли) и когда её разбудить (0 — без срока)
    public void VisQuiet(int i, float lookX, float lookZ, bool moving, bool moving2,
        bool seen, bool lit, int wakeAtMs, int nowMs)
    {
        if (i < 0 || i >= _capacity) return;
        int fl = _flags[i] | FVisQuiet;
        fl = moving ? (fl | FVisMoving) : (fl & ~FVisMoving);
        fl = seen ? (fl | FVisSeen) : (fl & ~FVisSeen);
        fl = lit ? (fl | FVisLit) : (fl & ~FVisLit);
        _flags[i] = fl;
        _vqLx[i] = lookX; _vqLz[i] = lookZ;
        _vqPx[i] = _px[i]; _vqPz[i] = _pz[i];
        _vqMs[i] = nowMs; _vqWake[i] = wakeAtMs;
        _vqMv2[i] = (byte)(moving2 ? 1 : 0);
    }

    public void VisWake(int i)
    {
        if (i >= 0 && i < _capacity) _flags[i] &= ~FVisQuiet;
    }

    public bool VisIsQuiet(int i) => i >= 0 && i < _capacity && (_flags[i] & FVisQuiet) != 0;

    /// Вспышка попадания: пишет ядро (BatchVisual), а не боец — визуальный
    /// тик у тихой строки не идёт, а вспышка обязана погаснуть и без него
    public void VisHit(int i, float peak, float sec)
    {
        if (i < 0 || i >= _capacity) return;
        _vFlash[i] = sec; _vPeak[i] = peak;
        // Пик и доля жизни — В ТОТ ЖЕ КАДР, как прежний Slot.set_damage из
        // take_damage: вспышка в 0.07 с не вправе ждать кадра отрисовки
        int b = _rbB[i];
        if (b < 0) return;
        var r = _rb[b];
        int o = _rbI[i] * RbStride;
        float hfrac = _hpMax[i] > 0.0f ? Mathf.Clamp(_hp[i] / _hpMax[i], 0.0f, 1.0f) : 1.0f;
        r.Buf[o + 14] = peak; r.Buf[o + 15] = hfrac; r.Dirty = true;
    }

    /// Строки, которым НУЖЕН GDScript-тик картинки на этом шарде: живые, не
    /// спящие по картинке (FSleepDraw) и не тихие. Отбор по draw_on делает
    /// GDScript по своему полю — оно у него под рукой
    public int[] VisRows(int shards, int phase)
    {
        int n = 0, quiet = 0;
        int dead = DeadState;
        for (int k = 0; k < _liveCount; k++)
        {
            int i = _liveRows[k];
            if (shards > 1 && (i % shards) != phase) continue;
            int fl = _flags[i];
            if ((fl & FSleepDraw) != 0) continue;
            if (_st[i] == dead) continue;
            if ((fl & FVisQuiet) != 0) { quiet++; continue; }
            if (n >= _visOut.Length) Array.Resize(ref _visOut, _visOut.Length * 2);
            _visOut[n++] = i;
        }
        VisListed = n; VisQuietN = quiet;
        var res = new int[n];
        Array.Copy(_visOut, res, n);
        return res;
    }

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

    /// Свободный слот слоя или −1 (GDScript тогда растит слой RbGrow и
    /// спрашивает снова — рост раз в GROW слотов, а не на каждый выстрел)
    public int RbAcquire(int b)
    {
        var r = _rb[b];
        if (r.FreeN == 0) return -1;
        return r.Free[--r.FreeN];
    }

    /// Вернуть слот слоя: спрятать и положить в свободные
    public void RbRelease(int b, int idx)
    {
        var r = _rb[b];
        if (idx < 0 || idx >= r.Capacity) return;
        Array.Clear(r.Buf, idx * RbStride, RbStride);
        r.Dirty = true;
        if (r.FreeN >= r.Free.Length) Array.Resize(ref r.Free, Math.Max(64, r.Free.Length * 2));
        r.Free[r.FreeN++] = idx;
    }

    /// Нарастить слой снарядов: буфер + новые номера в свободные.
    /// instance_count самому MultiMesh ставит вызывающий (это ресурс сцены)
    public void RbGrow(int b, int newCap)
    {
        var r = _rb[b];
        int old = r.Capacity;
        if (newCap <= old) return;
        RbEnsure(b, newCap);
        int need = r.FreeN + (newCap - old);
        if (need > r.Free.Length) Array.Resize(ref r.Free, Math.Max(need, r.Free.Length * 2));
        for (int i = newCap - 1; i >= old; i--) r.Free[r.FreeN++] = i;
    }

    public int RbFreeCount(int b) => _rb[b].FreeN;

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
        // Переезд между бакетами (смена ленты): GDScript записал слот со своим
        // _look_frame, который у ведомой ядром ленты не листается, — кадр
        // ставится ядром ЗДЕСЬ, из своей фазы
        if (_anFrame[i] >= 0 && b >= 0)
            _rb[b].Buf[idx * RbStride + 12] = _anFrame[i] / 255.0f;
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
        float bobAmp, float bobSprintMult, bool animCore, bool decalCore,
        int nowMs, float viewX, float viewZ, float viewR2, bool fogWatch, int playerFac,
        float flashSec, float walkMin, float moveMin, float turnCos2)
    {
        const float MoveEpsSq = 1e-6f;
        float ringY = _ringY, shadowY = _shadowY, hpBarY = _hpBarY;
        int ledMask = FAutopilot | FRearPress | FMatrixLed | FAtkSnooze;
        float walkMin2 = walkMin * walkMin, moveMin2 = moveMin * moveMin;
        bool fogOk = fogWatch && _fogCols > 0;
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
            int fl = _flags[i];
            // ── НАДЗОР ЗА ТИХОЙ СТРОКОЙ (этап 5): повод — и GDScript будится ─
            if ((fl & FVisQuiet) != 0)
            {
                bool wake = false;
                float qx = _px[i], qz = _pz[i];
                if (_vqWake[i] > 0 && nowMs >= _vqWake[i]) wake = true;
                // Туман: лит по маске ядра (та же, что копия GDScript)
                if (!wake && fogOk && _fac[i] != playerFac)
                {
                    int cx = (int)((qx + _fogHalfX) / _fogCell);
                    int cz = (int)((qz + _fogHalfZ) / _fogCell);
                    bool lit = cx >= 0 && cz >= 0 && cx < _fogCols && cz < _fogRows
                        && _fogLit[cz * _fogCols + cx] != 0;
                    if (lit != ((fl & FVisLit) != 0)) wake = true;
                }
                if (!wake && b >= 0)
                {
                    // LOD: вошёл в поле зрения / вышел из него
                    float vdx = qx - viewX, vdz = qz - viewZ;
                    bool seen = vdx * vdx + vdz * vdz <= viewR2;
                    if (seen != ((fl & FVisSeen) != 0)) wake = true;
                    // Ходьба: тот же замер окном, что Unit._sample_movement
                    int win = nowMs - _vqMs[i];
                    if (!wake && win >= 200)
                    {
                        float mdx = qx - _vqPx[i], mdz = qz - _vqPz[i];
                        float wsec = win * 0.001f;
                        float d2 = mdx * mdx + mdz * mdz;
                        bool moving = d2 > walkMin2 * wsec * wsec;
                        bool moving2 = d2 > moveMin2 * wsec * wsec;
                        if (moving != ((fl & FVisMoving) != 0)) wake = true;
                        else if (moving2 != (_vqMv2[i] != 0)) wake = true;
                        else if (moving2)
                        {
                            // Идёт: направление хода против взгляда позы
                            float lx = _vqLx[i], lz = _vqLz[i];
                            float dd = mdx * lx + mdz * lz;
                            if (dd <= 0.0f || dd * dd < turnCos2 * d2 * (lx * lx + lz * lz)) wake = true;
                        }
                        _vqPx[i] = qx; _vqPz[i] = qz; _vqMs[i] = nowMs;
                    }
                    // Взгляд ведомого ядром: его пишет только ядро, GDScript
                    // своё сравнивает сам в физтике
                    if (!wake && (fl & ledMask) != 0 && _vqMv2[i] == 0)
                    {
                        float fx = _fx[i], fz = _fz[i];
                        float lx = _vqLx[i], lz = _vqLz[i];
                        float dd = fx * lx + fz * lz;
                        float n2 = (fx * fx + fz * fz) * (lx * lx + lz * lz);
                        if (n2 > 1e-8f && (dd <= 0.0f || dd * dd < turnCos2 * n2)) wake = true;
                    }
                }
                if (wake) { fl &= ~FVisQuiet; _flags[i] = fl; }
            }
            if (b < 0) continue;
            // ── КАДР ЛЕНТЫ: ДО ветки разлёта, боец в полёте тоже листает ────
            if (animCore)
            {
                int nfr = _anFrames[i];
                if (nfr > 1 && _anFps[i] > 0.0f)
                {
                    float ph = _anPhase[i] + delta * _anFps[i];
                    int f;
                    if (_anLoop[i])
                    {
                        // Фаза держится в пределах ленты: float не растёт вечно
                        if (ph >= nfr * 4.0f) ph -= nfr * 4.0f;
                        f = ((int)ph) % nfr;
                    }
                    else
                    {
                        if (ph > nfr) ph = nfr;
                        f = Math.Min((int)ph, nfr - 1);
                    }
                    _anPhase[i] = ph;
                    if (f != _anFrame[i])
                    {
                        _anFrame[i] = f;
                        var ra = _rb[b];
                        ra.Buf[_rbI[i] * RbStride + 12] = f / 255.0f;
                        ra.Dirty = true;
                    }
                }
                else if (nfr == 1 && _anFrame[i] != 0)
                {
                    _anFrame[i] = 0;
                }
            }
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
            if (odx * odx + ody * ody + odz * odz >= MoveEpsSq)
            {
                buf[o + 3] = sx; buf[o + 7] = wy; buf[o + 11] = sz;
                r.Dirty = true;
            }
            // ── ВСПЫШКА И ДОЛЯ ЖИЗНИ — ТЕ ЖЕ ДВА КАНАЛА, ЧТО У Slot.set_damage ─
            // Порог 0.004 — шаг восьмибитного канала (см. FarUnitRenderer)
            float vf = _vFlash[i];
            float lvl = 0.0f;
            if (vf > 0.0f)
            {
                vf -= delta;
                if (vf < 0.0f) vf = 0.0f;
                _vFlash[i] = vf;
                lvl = _vPeak[i] * Math.Min(vf / flashSec, 1.0f);
            }
            if (Math.Abs(buf[o + 14] - lvl) >= 0.004f)
            {
                buf[o + 14] = lvl; r.Dirty = true;
            }
            float hfrac = _hpMax[i] > 0.0f ? Mathf.Clamp(_hp[i] / _hpMax[i], 0.0f, 1.0f) : 1.0f;
            if (Math.Abs(buf[o + 15] - hfrac) >= 0.004f)
            {
                buf[o + 15] = hfrac; r.Dirty = true;
            }
            if (!decalCore) continue;
            // ── КОЛЬЦО, ТЕНЬ, ПОЛОСКА — ИЗ ТОЙ ЖЕ НАРИСОВАННОЙ ТОЧКИ ───────
            int rbB = _ringB[i];
            if (rbB >= 0)
            {
                int di = _decI[i] * RbStride;
                var rr = _rb[rbB];
                float ry = py + ringY;
                var rbuf = rr.Buf;
                if (rbuf[di + 3] != sx || rbuf[di + 7] != ry || rbuf[di + 11] != sz)
                {
                    rbuf[di + 3] = sx; rbuf[di + 7] = ry; rbuf[di + 11] = sz;
                    rr.Dirty = true;
                }
                int shB = _shB[i];
                if (shB >= 0)
                {
                    var rs = _rb[shB];
                    float sy = py + shadowY;
                    var sbuf = rs.Buf;
                    if (sbuf[di + 3] != sx || sbuf[di + 7] != sy || sbuf[di + 11] != sz)
                    {
                        sbuf[di + 3] = sx; sbuf[di + 7] = sy; sbuf[di + 11] = sz;
                        rs.Dirty = true;
                    }
                }
            }
            int hb = _hpB[i];
            if (hb >= 0)
            {
                int hi = _hpI[i] * RbStride;
                var rh = _rb[hb];
                float hy = py + hpBarY;
                float frac = _hpMax[i] > 0.0f ? Mathf.Clamp(_hp[i] / _hpMax[i], 0.0f, 1.0f) : 0.0f;
                var hbuf = rh.Buf;
                if (hbuf[hi + 3] != sx || hbuf[hi + 7] != hy || hbuf[hi + 11] != sz
                    || Math.Abs(hbuf[hi + 12] - frac) > 0.002f)
                {
                    hbuf[hi + 3] = sx; hbuf[hi + 7] = hy; hbuf[hi + 11] = sz;
                    hbuf[hi + 12] = frac;
                    rh.Dirty = true;
                }
            }
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

    // ═════════════════════════════════════════════════════════════════════
    // ОТРЯДНЫЕ ПЕРЕСЧЁТЫ ОДНИМ ВЫЗОВОМ (BigStand-5, этап 2)
    // ═════════════════════════════════════════════════════════════════════
    // Коридор отряда (GameManager._recalc_corridor) ходил в ядро трижды —
    // габариты, стволы, чужие — и каждый ответ приходил Godot-массивом
    // (финализируемая обёртка → сборки gen1). Голосование по целям
    // (_recalc_melee) снимало ДВА СНИМКА колонок px/pz на КАЖДЫЙ пересчёт:
    // при ёмкости 4096 это 32 КБ управляемых аллокаций на отряд, ~150 КБ на
    // кадр в замесе — главный неатрибутированный источник GC из отчёта
    // 17.09.2026. Здесь оба пересчёта идут по колонкам за один переход
    // границы и отвечают плоскими массивами (float[] / int[] →
    // Packed*Array, без обёрток с финализатором).

    /// Коридор отряда: [n, cx, cz, far, watch, fac, clearTrunk, clearEnemy].
    /// Габариты — как SquadBounds; стволы ищутся в far + margin от центра,
    /// чужие — в far + margin + watch (та же формула, что была в GDScript)
    public float[] SquadCorridor(int[] rows, int dead, float aggroR, float intercept, float margin)
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
        var res = new float[8];
        res[4] = watch; res[5] = fc;
        if (n == 0) return res;
        float invN = 1.0f / n;
        float cx = sx * invN, cz = sz * invN;
        float rad = 0.0f;
        for (int k = 0; k < rows.Length; k++)
        {
            int i = rows[k];
            if (i < 0 || i >= _capacity) continue;
            if ((_flags[i] & FPosValid) == 0 || _st[i] == dead) continue;
            float dx = _px[i] - cx, dz = _pz[i] - cz;
            float d2 = dx * dx + dz * dz;
            if (d2 > rad) rad = d2;
        }
        rad = Mathf.Sqrt(rad);
        float radius = rad + margin;
        res[0] = n; res[1] = cx; res[2] = cz; res[3] = rad;
        res[6] = (TrunkNear(cx, cz, radius) || BldNear(cx, cz, radius)) ? 0.0f : 1.0f;
        res[7] = EnemyNear(cx, cz, fc, radius + watch) ? 0.0f : 1.0f;
        return res;
    }

    // Скрэтч голосования: ключи в порядке появления (первый максимум — как у
    // обхода GDScript-словаря), счётчики рядом. Отрядов в голосовании единицы
    private int[] _voteSid = new int[32];
    private int[] _voteCnt = new int[32];
    private int[] _meleeOut = new int[256];

    /// Бухгалтерия боя отряда по колонкам: [engaged, free, foeSid, nHad,
    /// nCand, nUnknown, hadRows..., candRows..., unknownRows...].
    /// hadRows — строки, у которых снята аренда напора (GDScript гасит своё
    /// поле); candRows — свободные ATTACKING со строкой цели дальше оружия
    /// (кандидаты в напор, GDScript-условия проверяет вызывающий);
    /// unknownRows — ATTACKING без строки цели (цели нет либо цель — здание:
    /// колонка их не различает, разбирает GDScript, как раньше)
    public int[] SquadMelee(int[] rows, int attacking)
    {
        int engaged = 0, free = 0;
        int nv = 0;
        int nHad = 0, nCand = 0, nUnk = 0;
        // Три списка складываются в скрэтч порознь: сначала считаем размеры
        int need = 6 + rows.Length * 3;
        if (_meleeOut.Length < need) Array.Resize(ref _meleeOut, need);
        int hadBase = 6;
        int candBase = 6 + rows.Length;
        int unkBase = 6 + rows.Length * 2;
        for (int k = 0; k < rows.Length; k++)
        {
            int i = rows[k];
            if (i < 0 || i >= _capacity) continue;
            int fl = _flags[i];
            if ((fl & FRearPress) != 0)
            {
                _flags[i] = fl & ~FRearPress;
                _meleeOut[hadBase + nHad++] = i;
            }
            if (_st[i] != attacking) continue;
            int t = _tgt[i];
            if (t < 0 || t >= _capacity || !_rowUsed[t])
            {
                _meleeOut[unkBase + nUnk++] = i;
                continue;
            }
            float dx = _px[i] - _px[t];
            float dz = _pz[i] - _pz[t];
            float d2 = dx * dx + dz * dz;
            float r = _atkRange[i];
            if (d2 <= r * r) engaged++;
            else
            {
                free++;
                _meleeOut[candBase + nCand++] = i;
            }
            int tsq = _sq[t];
            if (tsq > 0)
            {
                int v = -1;
                for (int q = 0; q < nv; q++) if (_voteSid[q] == tsq) { v = q; break; }
                if (v < 0)
                {
                    if (nv >= _voteSid.Length)
                    {
                        Array.Resize(ref _voteSid, nv * 2);
                        Array.Resize(ref _voteCnt, nv * 2);
                    }
                    _voteSid[nv] = tsq; _voteCnt[nv] = 0; v = nv++;
                }
                _voteCnt[v]++;
            }
        }
        int foe = 0, best = 0;
        for (int q = 0; q < nv; q++)
            if (_voteCnt[q] > best) { best = _voteCnt[q]; foe = _voteSid[q]; }
        var res = new int[6 + nHad + nCand + nUnk];
        res[0] = engaged; res[1] = free; res[2] = foe;
        res[3] = nHad; res[4] = nCand; res[5] = nUnk;
        Array.Copy(_meleeOut, hadBase, res, 6, nHad);
        Array.Copy(_meleeOut, candBase, res, 6 + nHad, nCand);
        Array.Copy(_meleeOut, unkBase, res, 6 + nHad + nCand, nUnk);
        return res;
    }

    // ═════════════════════════════════════════════════════════════════════
    // НАВИГАЦИЯ: КОАРС-СЕТКА ПРОХОДИМОСТИ И A* (спринт 19, письмо 11)
    // ═════════════════════════════════════════════════════════════════════
    // Поиска пути в игре не было: боец шёл по прямой, а скалу и воду обходил
    // скольжением вдоль стены. У замкнутого кольца плато это оборачивалось
    // «отряд упёрся в обрыв и дёргается», у брода — ниткой вдоль берега.
    // Теперь у карты есть сетка ячеек NavCell метров: ячейка непроходима,
    // если в ней есть ячейка маски скал (BuildCliffMask) или вода реки вне
    // брода (RiverWater). По ней A* (8 связей, без срезания углов), потом
    // «натягивание нити» по видимости (NavLineBlocked) — остаются только
    // углы, — и отжим углов от стены (NavCornerPush). Зовётся ИЗ ПРИКАЗА
    // (command_move) и раз в NAV_RECHECK у подхода к цели; в покадровый
    // путь не входит. Всё в ядре: GDScript получает готовый плоский массив
    private byte[] _nav = System.Array.Empty<byte>();
    private int _navCols = 0, _navRows = 0;
    private float _navOx = 0.0f, _navOz = 0.0f, _navCell = 2.0f;
    private bool _navOn = false;
    private bool _navWanted = false;
    // Скалы и вода без построек: слой построек накладывается заново при
    // каждой смене реестра (NavSync), ячейка стены = 2
    private byte[] _navBase = System.Array.Empty<byte>();
    public int NavBlocked = 0;
    public bool NavLastFound = false;
    public float NavLastLength = 0.0f;
    public int NavCalls = 0;
    // Скрэтч A*: печать эпохи вместо очистки массивов на каждый вызов
    private int[] _navStamp = System.Array.Empty<int>();
    private float[] _navG = System.Array.Empty<float>();
    private int[] _navParent = System.Array.Empty<int>();
    private byte[] _navClosed = System.Array.Empty<byte>();
    private int _navEpoch = 0;
    private float[] _heapF = new float[1024];
    private int[] _heapI = new int[1024];
    private int _heapN = 0;
    private const int NavMaxExpand = 60000;
    // ── КОМПОНЕНТЫ СВЯЗНОСТИ СЕТКИ (аудит 19.09.2026) ─────────────────────
    // Цель за обрывом/рекой раньше стоила ПОЛНОЙ заливки A* (до NavMaxExpand
    // ячеек — единицы-десятки мс за вызов): qa_bigstand/Owner давал пиковые
    // кадры 70-100 мс с nav_route 38-40 мс внутри даже при кэше маршрутов.
    // Заливка ОДИН РАЗ при сборке сетки метит каждую свободную ячейку номером
    // компоненты; разные номера у старта и цели — пути нет, ответ мгновенный.
    // Связность по рёбрам: диагональ A* без срезания угла требует обоих
    // ортогональных соседей, то есть по диагонали компоненты не сливаются
    private int[] _navComp = System.Array.Empty<int>();
    public int NavCompCount = 0;
    public int NavUnreach = 0;
    // ── ОТСТУП ОТ СТЕН (ТЗ 19.09.2026, п. 2) ──────────────────────────────
    // A* считал шаг у самой скалы таким же дешёвым, как в чистом поле, и
    // нить натягивалась с зазором 0.7 м — отряд шёл впритирку к обрыву и
    // выстраивался вдоль него гуськом. Теперь у каждой свободной ячейки
    // известна дистанция до ближайшей стены в ячейках (_navWall: 1, 2, 3+),
    // шаг в ячейку у стены дороже (NavWallCost), а нить натягивается с
    // зазором NavThreadClearance — угол обхода отодвигается от кромки
    private byte[] _navWall = System.Array.Empty<byte>();
    private static readonly float[] NavWallCost = { 0f, 2.5f, 0.8f, 0f, 0f };
    private const float NavThreadClearance = 1.6f;
    public float NavWallMargin() { return NavThreadClearance; }
    // ── ГАБАРИТ АГЕНТА (ТЗ 19.09.2026, обход гор и углов) ──────────────────
    // Отступ от стены — СВОЙСТВО РОДА ВОЙСК (Unit.nav_clearance: пехота 1.5,
    // конница 2.2, гиганты 3.5-4.0 м), и он входит во ВСЕ четыре места, где
    // сетка решает за бойца: штраф шага у стены (NavCellPenalty — масштаб от
    // 1.6 м базы, у гигантов платит и третья клетка), зазор нити (pad =
    // clear), отжим угла (push = clear) и видимость прямой (pad = clear/2:
    // прямая, проходящая в метре от кромки, для туши в 1.7 м «упирается»).
    // ── ЛЕС — СТОИМОСТЬ, А НЕ СТЕНА ─────────────────────────────────────────
    // Стволов сетка не знала: шаг обходил их скольжением, а в чаще у угла
    // скалы гигант зависал (скриншот 1). Слой _navTree — число стволов в
    // ячейке (из реестра стволов, пересчёт по флагу рубки NavRefreshTrees):
    // штраф на ствол растёт с габаритом (NavTreeCost), а для гиганта чаща от
    // NavTreeBlockGiant стволов ещё и непрозрачна для нити и прямой
    private byte[] _navTree = System.Array.Empty<byte>();
    private bool _navTreeDirty = true;
    public int NavTreeCells = 0;
    private const int NavTreeBlockGiant = 3;
    private const float NavGiantClear = 3.0f;
    public bool NavTreesDirty() { return _navTreeDirty; }

    public int NavRefreshTrees()
    {
        _navTreeDirty = false;
        int n = _navCols * _navRows;
        if (n <= 0) return 0;
        if (_navTree.Length != n) _navTree = new byte[n];
        else System.Array.Clear(_navTree, 0, n);
        NavTreeCells = 0;
        foreach (var kv in _trunks)
        {
            var list = kv.Value;
            for (int i = 0; i < list.Count; i++)
            {
                var t = list[i];
                int c = (int)Math.Floor((t.X - _navOx) / _navCell);
                int r = (int)Math.Floor((t.Y - _navOz) / _navCell);
                if (c < 0 || r < 0 || c >= _navCols || r >= _navRows) continue;
                int idx = r * _navCols + c;
                if (_navTree[idx] == 0) NavTreeCells++;
                if (_navTree[idx] < 255) _navTree[idx]++;
            }
        }
        return NavTreeCells;
    }

    private static float NavTreeCost(float clear)
    {
        if (clear < 2.0f) return 1.0f;
        if (clear < NavGiantClear) return 1.0f;
        return 3.0f;
    }

    // Штраф шага в ячейку ni для агента с отступом clear
    private float NavCellPenalty(int ni, float clear)
    {
        float pen = 0f;
        if (_navWall.Length == _nav.Length)
        {
            int d = _navWall[ni];
            float scale = clear / NavThreadClearance;
            if (d == 1) pen += NavWallCost[1] * scale;
            else if (d == 2) pen += NavWallCost[2] * scale;
            else if (d == 3 && clear > NavGiantClear) pen += (clear - NavGiantClear) * 1.5f;
        }
        if (_navBldAdj.Length == _nav.Length && _navBldAdj[ni] != 0) pen += NavBldAdjCost;
        if (_navTree.Length == _nav.Length)
        {
            int t = _navTree[ni];
            if (t > 0) pen += t * NavTreeCost(clear);
        }
        return pen;
    }

    // Точка «в стене» для агента: скала всегда, чаща — только для гиганта
    private bool NavBlockedAtC(float x, float z, float clear)
    {
        int c = (int)Math.Floor((x - _navOx) / _navCell);
        int r = (int)Math.Floor((z - _navOz) / _navCell);
        if (c < 0 || r < 0 || c >= _navCols || r >= _navRows) return false;
        int i = r * _navCols + c;
        if (_nav[i] != 0) return true;
        return clear >= NavGiantClear && _navTree.Length == _nav.Length && _navTree[i] >= NavTreeBlockGiant;
    }
    // Зазор от стены при проверке видимости: боец — тело радиусом ~0.55, и
    // нить, натянутая впритык к углу, вела бы его В стену
    private const float NavClearance = 0.7f;

    public int BuildNavGrid(float cell)
    {
        if (_cliff.Length <= 1) { _navOn = false; NavBlocked = 0; return 0; }
        _navCell = cell;
        _navOx = _cliffOx; _navOz = _cliffOz;
        _navCols = Math.Max((int)Math.Ceiling(_cliffCols * _cliffCell / cell), 1);
        _navRows = Math.Max((int)Math.Ceiling(_cliffRows * _cliffCell / cell), 1);
        int n = _navCols * _navRows;
        _nav = new byte[n];
        _navStamp = new int[n]; _navG = new float[n]; _navParent = new int[n]; _navClosed = new byte[n];
        NavBlocked = 0;
        for (int r = 0; r < _navRows; r++)
        {
            float z0 = _navOz + r * cell;
            for (int c = 0; c < _navCols; c++)
            {
                float x0 = _navOx + c * cell;
                bool blocked = false;
                // Любая ячейка маски скал внутри — непроходимо
                int cc0 = (int)Math.Floor((x0 - _cliffOx) / _cliffCell);
                int cr0 = (int)Math.Floor((z0 - _cliffOz) / _cliffCell);
                int cc1 = (int)Math.Floor((x0 + cell - 0.01f - _cliffOx) / _cliffCell);
                int cr1 = (int)Math.Floor((z0 + cell - 0.01f - _cliffOz) / _cliffCell);
                for (int rr = Math.Max(cr0, 0); rr <= cr1 && rr < _cliffRows && !blocked; rr++)
                    for (int cc = Math.Max(cc0, 0); cc <= cc1 && cc < _cliffCols; cc++)
                        if (_cliff[rr * _cliffCols + cc] != 0) { blocked = true; break; }
                // ── ВОДА — СВОЙ КОД 3 (ТЗ 20.09.2026, п. 1) ───────────────
                // Прибавка отступа NavCliffExtra писана под ГОРУ: у скалы
                // строй обязан идти шире. На БРОДЕ она сжимала проход —
                // фронт отряда на переправе 6.0 → 3.0 м, отряд шёл гуськом
                // (qa_river_crossing B4/B5). Вода блокирует шаг так же, как
                // скала, но отступ у неё прежний, и дуги вокруг неё нет
                bool water = false;
                if (!blocked && _riverOn)
                {
                    float q = cell * 0.25f;
                    float cx = x0 + cell * 0.5f, cz = z0 + cell * 0.5f;
                    if (RiverWater(cx, cz) || RiverWater(cx - q, cz - q) || RiverWater(cx + q, cz - q)
                        || RiverWater(cx - q, cz + q) || RiverWater(cx + q, cz + q))
                        water = true;
                }
                if (blocked || water) { _nav[r * _navCols + c] = (byte)(blocked ? 1 : 3); NavBlocked++; }
            }
        }
        _navBase = (byte[])_nav.Clone();
        _navWanted = true;
        _navBldDirty = true;
        NavSync();
        return NavBlocked;
    }

    // Слой построек поверх базового: пересборка стен и компонент. Дёшево
    // (десятки тысяч ячеек), зовётся лениво — при первом запросе после
    // смены реестра, а не на каждую из двадцати хижин деревни
    private void NavSync()
    {
        if (!_navBldDirty) return;
        _navBldDirty = false;
        if (_nav.Length <= 1 || _navBase.Length != _nav.Length) return;
        System.Array.Copy(_navBase, _nav, _nav.Length);
        NavBlocked = 0;
        for (int i = 0; i < _nav.Length; i++) if (_nav[i] != 0) NavBlocked++;
        NavBldCells = 0;
        foreach (var kv in _blds)
        {
            var list = kv.Value;
            for (int i = 0; i < list.Count; i++)
            {
                var b = list[i];
                float rr = b.R + NavBldPad;
                int c0 = (int)Math.Floor((b.X - rr - _navOx) / _navCell);
                int c1 = (int)Math.Floor((b.X + rr - _navOx) / _navCell);
                int r0 = (int)Math.Floor((b.Z - rr - _navOz) / _navCell);
                int r1 = (int)Math.Floor((b.Z + rr - _navOz) / _navCell);
                for (int r = Math.Max(r0, 0); r <= r1 && r < _navRows; r++)
                    for (int c = Math.Max(c0, 0); c <= c1 && c < _navCols; c++)
                    {
                        // Ячейка задевает круг: дистанция от центра круга до
                        // прямоугольника ячейки не больше rr
                        float cx0 = _navOx + c * _navCell, cz0 = _navOz + r * _navCell;
                        float ddx = Math.Max(Math.Max(cx0 - b.X, 0.0f), b.X - (cx0 + _navCell));
                        float ddz = Math.Max(Math.Max(cz0 - b.Z, 0.0f), b.Z - (cz0 + _navCell));
                        if (ddx * ddx + ddz * ddz > rr * rr) continue;
                        int idx = r * _navCols + c;
                        if (_nav[idx] == 0) { _nav[idx] = 2; NavBldCells++; }
                    }
            }
        }
        // Соседи ячеек построек — под малый штраф A* (путь идёт вдоль стены,
        // но при равной длине предпочитает не тереться о неё)
        int nn = _nav.Length;
        if (_navBldAdj.Length != nn) _navBldAdj = new byte[nn];
        else System.Array.Clear(_navBldAdj, 0, nn);
        if (NavBldCells > 0)
            for (int r = 0; r < _navRows; r++)
                for (int c = 0; c < _navCols; c++)
                {
                    if (_nav[r * _navCols + c] != 2) continue;
                    for (int dr = -1; dr <= 1; dr++)
                        for (int dc = -1; dc <= 1; dc++)
                        {
                            int rr2 = r + dr, cc2 = c + dc;
                            if (rr2 < 0 || cc2 < 0 || rr2 >= _navRows || cc2 >= _navCols) continue;
                            int j = rr2 * _navCols + cc2;
                            if (_nav[j] == 0) _navBldAdj[j] = 1;
                        }
                }
        _navOn = _navWanted && (NavBlocked + NavBldCells) > 0;
        NavBuildComponents();
    }

    // Дистанция до стены в ячейках (0 — сама стена, 4 — четыре и дальше;
    // третья клетка нужна гигантам с отступом 3.5-4 м)
    private void NavBuildWallDist()
    {
        int n = _navCols * _navRows;
        _navWall = new byte[n];
        for (int i = 0; i < n; i++) _navWall[i] = (byte)(_nav[i] != 0 ? 0 : 4);
        for (int r = 0; r < _navRows; r++)
            for (int c = 0; c < _navCols; c++)
            {
                int i = r * _navCols + c;
                if (_nav[i] != 0) continue;
                byte d = 4;
                for (int dr = -3; dr <= 3 && d > 1; dr++)
                    for (int dc = -3; dc <= 3; dc++)
                    {
                        if (dr == 0 && dc == 0) continue;
                        // Здание — не стена для отступа: вдоль него идут вплотную
                        if (!NavCellCliff(c + dc, r + dr)) continue;
                        int cheb = Math.Max(Math.Abs(dr), Math.Abs(dc));
                        if (cheb < d) d = (byte)cheb;
                        if (d <= 1) break;
                    }
                _navWall[i] = d;
            }
    }

    private void NavBuildComponents()
    {
        NavBuildWallDist();
        int n = _navCols * _navRows;
        _navComp = new int[n];
        NavCompCount = 0;
        var stack = new int[n];
        for (int i = 0; i < n; i++)
        {
            if (_nav[i] != 0 || _navComp[i] != 0) continue;
            int id = ++NavCompCount;
            int sp = 0; stack[sp++] = i; _navComp[i] = id;
            while (sp > 0)
            {
                int cur = stack[--sp];
                int cc = cur % _navCols, cr = cur / _navCols;
                for (int k = 0; k < 4; k++)
                {
                    int nc = cc + NavDc[k], nr = cr + NavDr[k];
                    if (NavCellBlocked(nc, nr)) continue;
                    int ni = nr * _navCols + nc;
                    if (_navComp[ni] != 0) continue;
                    _navComp[ni] = id; stack[sp++] = ni;
                }
            }
        }
    }

    public void SetNavEnabled(bool on) { _navWanted = on; _navOn = on && _nav.Length > 1; }
    public bool NavEnabled() { NavSync(); return _navOn; }
    public float NavCellSize() { return _navCell; }

    private bool NavCellBlocked(int c, int r)
    {
        if (c < 0 || r < 0 || c >= _navCols || r >= _navRows) return true;
        return _nav[r * _navCols + c] != 0;
    }

    // Скала, вода или край карты — но не здание
    private bool NavCellCliff(int c, int r)
    {
        if (c < 0 || r < 0 || c >= _navCols || r >= _navRows) return true;
        int k = _nav[r * _navCols + c];
        return k == 1 || k == 3;
    }

    // Род помехи в точке: 0 — свободно, 1 — скала/вода (гиганту — и чаща),
    // 2 — фундамент постройки
    private int NavKindAt(float x, float z, float clear)
    {
        int c = (int)Math.Floor((x - _navOx) / _navCell);
        int r = (int)Math.Floor((z - _navOz) / _navCell);
        if (c < 0 || r < 0 || c >= _navCols || r >= _navRows) return 0;
        int i = r * _navCols + c;
        if (_nav[i] != 0) return _nav[i];
        return (clear >= NavGiantClear && _navTree.Length == _nav.Length && _navTree[i] >= NavTreeBlockGiant) ? 1 : 0;
    }

    // Точка вне всех кругов фундаментов с зазором margin: внутри — вытолкнуть
    private void BldPushOut(ref float x, ref float z, float margin)
    {
        if (BldCount == 0) return;
        for (int k = 0; k < 3; k++)
        {
            float ox, oz;
            float pen = BldPenetration(x, z, margin, out ox, out oz);
            if (pen <= 0.0f) return;
            x += ox * (pen + 0.02f); z += oz * (pen + 0.02f);
        }
    }

    private bool NavBlockedAt(float x, float z)
    {
        int c = (int)Math.Floor((x - _navOx) / _navCell);
        int r = (int)Math.Floor((z - _navOz) / _navCell);
        if (c < 0 || r < 0 || c >= _navCols || r >= _navRows) return false;
        return _nav[r * _navCols + c] != 0;
    }

    public bool NavFree(float x, float z)
    {
        NavSync();
        if (!_navOn) return true;
        return !NavBlockedAt(x, z);
    }

    // Видимость по сетке с зазором NavClearance по обе стороны отрезка:
    // выборка каждые полклетки, в каждой точке — центр и два бока
    // ── БОКОВОЙ РАЗНОС ТОЧЕК МАРШРУТА (аудит 19.09.2026) ─────────────────
    // GameManager._nav_spread делал по два перехода границы (NavFree +
    // NavLineBlocked) на КАЖДУЮ точку маршрута КАЖДОГО бойца приказа: у
    // орды в раздаче (_drain_orders) это 90-155 мкс на command_move и кадры
    // по 60-75 мс. Формула та же, что была в GDScript: точка сдвигается
    // поперёк хода на проекцию смещения бойца (потолок maxOff), не прошла —
    // на половину, не прошла — остаётся. flat — [x, z, x, z, …]
    public float[] NavSpread(float[] flat, float fromX, float fromZ, float latX, float latZ, float maxOff, float clear)
    {
        NavSync();
        int n = flat.Length / 2;
        var outp = new float[n * 2];
        float px = fromX, pz = fromZ;
        // Смещение бойца проецируется на перпендикуляр КАЖДОГО колена —
        // блок ПЕРЕНОСИТСЯ за угол, не разворачиваясь: цели бойцов и так
        // разнесены тем же смещением в мировых осях (перенос формы), и за
        // углом поперёк хода ложится глубина блока. «Заворот» (место в
        // колонне по первому колену на все колена) пробован и замерен хуже:
        // qa_cliff_bypass, малый габарит блока 55 → 46 % — у цели боец
        // всё равно стоит по мировому смещению, и второе колено сводило
        // строй клином
        for (int i = 0; i < n; i++)
        {
            float x = flat[i * 2], z = flat[i * 2 + 1];
            float dx = x - px, dz = z - pz;
            float l = (float)Math.Sqrt(dx * dx + dz * dz);
            float qx = x, qz = z;
            if (l > 0.05f)
            {
                float perpX = -dz / l, perpZ = dx / l;
                float off = Math.Clamp(latX * perpX + latZ * perpZ, -maxOff, maxOff);
                float cx = x + perpX * off, cz = z + perpZ * off;
                if (NavFree(cx, cz) && !NavLineBlockedC(px, pz, cx, cz, clear)) { qx = cx; qz = cz; }
                else
                {
                    cx = x + perpX * off * 0.5f; cz = z + perpZ * off * 0.5f;
                    if (NavFree(cx, cz) && !NavLineBlockedC(px, pz, cx, cz, clear)) { qx = cx; qz = cz; }
                }
            }
            BldPushOut(ref qx, ref qz, BldClear + 0.3f);
            outp[i * 2] = qx; outp[i * 2 + 1] = qz;
            px = qx; pz = qz;
        }
        return outp;
    }

    // Годится ли чужой (отрядный) маршрут этому бойцу: прямая от его точки к
    // первому углу и от последнего угла к его цели свободны. Один переход
    // границы вместо двух (GDScript → C# здесь стоит ~7 мкс за вызов)
    public bool NavReusable(float ax, float az, float bx, float bz, float p0x, float p0z, float plx, float plz, float clear)
    {
        NavSync();
        if (NavLineBlockedC(ax, az, p0x, p0z, clear)) return false;
        return !NavLineBlockedC(plx, plz, bx, bz, clear);
    }

    public bool NavLineBlocked(float x0, float z0, float x1, float z1)
    {
        NavSync();
        return NavLineBlockedPad(x0, z0, x1, z1, NavClearance, 0f);
    }

    // Та же прямая глазами агента с отступом clear: зазор — половина отступа
    // (тело в 1.7 м не пройдёт в метре от кромки), чаща непрозрачна гиганту
    public bool NavLineBlockedC(float x0, float z0, float x1, float z1, float clear)
    {
        NavSync();
        return NavLineBlockedPad(x0, z0, x1, z1, Math.Max(NavClearance, clear * 0.5f), clear);
    }

    private bool NavLineBlockedPad(float x0, float z0, float x1, float z1, float pad, float clear)
    {
        if (!_navOn) return false;
        float dx = x1 - x0, dz = z1 - z0;
        float len = (float)Math.Sqrt(dx * dx + dz * dz);
        if (len < 1e-4f) return NavBlockedAtC(x0, z0, clear);
        float ux = dx / len, uz = dz / len;
        float nx = -uz * pad, nz = ux * pad;
        // Вода: зазор БЕЗ прибавки NavCliffExtra — брод узкий, и широкий
        // зазор превращал переправу отряда в цепочку (qa_river_crossing B4/B5)
        float padW = Math.Max(pad - NavCliffExtra * 0.5f, 0.0f);
        float wnx = -uz * padW, wnz = ux * padW;
        // Здание: боковой зазор свой, малый — вдоль дома идут вплотную
        float bp = Math.Min(pad, NavBldSidePad);
        float bnx = -uz * bp, bnz = ux * bp;
        // Концы отрезка в ЯЧЕЙКЕ постройки, но вне самого фундамента (ворота,
        // точка сдачи, подтянутый к стене угол нити): пробы в пределах ячейки
        // от такого конца не считаются — иначе к воротам «дороги нет» никогда
        int startOk = -1, endOk = -1;
        int steps = Math.Max((int)Math.Ceiling(len / (_navCell * 0.45f)), 1);
        for (int i = 0; i <= steps; i++)
        {
            float t = (float)i / steps;
            float x = x0 + dx * t, z = z0 + dz * t;
            float along = len * t;
            int kc = NavKindAt(x, z, clear);
            if (kc == 1 || kc == 3) return true;
            bool bld = kc == 2;
            if (!bld && NavBldCells > 0)
            {
                bld = NavKindAt(x + bnx, z + bnz, clear) == 2 || NavKindAt(x - bnx, z - bnz, clear) == 2;
            }
            if (bld)
            {
                bool ex = false;
                if (along < _navCell)
                {
                    if (startOk < 0) startOk = BldDepth(x0, z0, BldClear) <= 0.0f ? 1 : 0;
                    ex = startOk == 1;
                }
                if (!ex && len - along < _navCell)
                {
                    if (endOk < 0) endOk = BldDepth(x1, z1, BldClear) <= 0.0f ? 1 : 0;
                    ex = endOk == 1;
                }
                if (!ex) return true;
            }
            if (pad > 0.0f && (NavKindAt(x + nx, z + nz, clear) == 1 || NavKindAt(x - nx, z - nz, clear) == 1))
                return true;
            if (padW > 0.0f && (NavKindAt(x + wnx, z + wnz, clear) == 3 || NavKindAt(x - wnx, z - wnz, clear) == 3))
                return true;
        }
        return false;
    }

    // Полоса ОТРЯДА шириной ±halfW задевает здание (ТЗ 19.09.2026, единство
    // строя): дорога отряда строится от центра, и если центру прямая свободна,
    // а фланг упирается в башню, — половина отряда шла своим обходом с другой
    // стороны. Полоса шире прямой: задела дом — маршрут строит A* от центра,
    // и весь отряд огибает его с одной стороны. Концы — как у прямой
    private bool NavBandBlockedBld(float x0, float z0, float x1, float z1, float halfW)
    {
        if (!_navOn || NavBldCells == 0) return false;
        float dx = x1 - x0, dz = z1 - z0;
        float len = (float)Math.Sqrt(dx * dx + dz * dz);
        if (len < 1e-4f) return false;
        float ux = dx / len, uz = dz / len;
        // ── ВЫХОД ИЗ СОБСТВЕННЫХ ВОРОТ — НЕ ПОМЕХА (ТЗ 20.09.2026, п. 2) ───
        // Отряд появляется на площадке в двух-шести метрах от стены, и полоса
        // ±halfW задевала ТО ЖЕ здание, из которого он вышел: полоса звала
        // A*, тот честно огибал казарму — и отряд шёл к точке сбора петлёй
        // вокруг собственного дома («призрачный угол», скриншоты 11, 12).
        // Участок у конца, который и так стоит вплотную к дому, из проверки
        // выпадает: здание, у стены которого путь начинается или кончается,
        // обойти нельзя и не нужно
        float skip0 = _navCell;
        if (BldDepth(x0, z0, halfW + _navCell) > 0.0f) skip0 = halfW + _navCell * 2.0f;
        float skip1 = _navCell;
        if (BldDepth(x1, z1, halfW + _navCell) > 0.0f) skip1 = halfW + _navCell * 2.0f;
        int steps = Math.Max((int)Math.Ceiling(len / (_navCell * 0.45f)), 1);
        for (int i = 0; i <= steps; i++)
        {
            float t = (float)i / steps;
            float along = len * t;
            if (along < skip0 || len - along < skip1) continue;
            float x = x0 + dx * t, z = z0 + dz * t;
            for (int k = 0; k < 2; k++)
            {
                float w = k == 0 ? halfW : halfW * 0.5f;
                if (NavKindAt(x - uz * w, z + ux * w, 0f) == 2 || NavKindAt(x + uz * w, z - ux * w, 0f) == 2)
                    return true;
            }
        }
        return false;
    }

    // Ближайшая проходимая ячейка кольцами (до maxR ячеек); -1 — не нашлась
    private int NavNearestFree(int c, int r, int maxR)
    {
        if (!NavCellBlocked(c, r)) return r * _navCols + c;
        for (int rad = 1; rad <= maxR; rad++)
        {
            int best = -1; float bd = float.MaxValue;
            for (int dr = -rad; dr <= rad; dr++)
                for (int dc = -rad; dc <= rad; dc++)
                {
                    if (Math.Abs(dr) != rad && Math.Abs(dc) != rad) continue;
                    int cc = c + dc, rr = r + dr;
                    if (NavCellBlocked(cc, rr)) continue;
                    float d = dc * dc + dr * dr;
                    if (d < bd) { bd = d; best = rr * _navCols + cc; }
                }
            if (best >= 0) return best;
        }
        return -1;
    }

    private void HeapPush(float f, int idx)
    {
        if (_heapN >= _heapF.Length)
        {
            System.Array.Resize(ref _heapF, _heapF.Length * 2);
            System.Array.Resize(ref _heapI, _heapI.Length * 2);
        }
        int i = _heapN++;
        _heapF[i] = f; _heapI[i] = idx;
        while (i > 0)
        {
            int p = (i - 1) >> 1;
            if (_heapF[p] <= _heapF[i]) break;
            (_heapF[p], _heapF[i]) = (_heapF[i], _heapF[p]);
            (_heapI[p], _heapI[i]) = (_heapI[i], _heapI[p]);
            i = p;
        }
    }

    private int HeapPop()
    {
        int top = _heapI[0];
        _heapN--;
        if (_heapN > 0)
        {
            _heapF[0] = _heapF[_heapN]; _heapI[0] = _heapI[_heapN];
            int i = 0;
            while (true)
            {
                int l = 2 * i + 1, rr = l + 1, m = i;
                if (l < _heapN && _heapF[l] < _heapF[m]) m = l;
                if (rr < _heapN && _heapF[rr] < _heapF[m]) m = rr;
                if (m == i) break;
                (_heapF[m], _heapF[i]) = (_heapF[i], _heapF[m]);
                (_heapI[m], _heapI[i]) = (_heapI[i], _heapI[m]);
                i = m;
            }
        }
        return top;
    }

    private static readonly int[] NavDc = { 1, -1, 0, 0, 1, 1, -1, -1 };
    private static readonly int[] NavDr = { 0, 0, 1, -1, 1, -1, 1, -1 };
    private static readonly float[] NavDw = { 1f, 1f, 1f, 1f, 1.41421f, 1.41421f, 1.41421f, 1.41421f };

    private readonly System.Collections.Generic.List<float> _navOut = new System.Collections.Generic.List<float>(64);
    private readonly System.Collections.Generic.List<int> _navCells = new System.Collections.Generic.List<int>(256);

    /// Маршрут по сетке: плоский массив [x0, z0, x1, z1, ...] ПРОМЕЖУТОЧНЫХ
    /// точек (без начала и конца). Пусто, если путь прямой (NavLastFound = true)
    /// или пути нет вовсе (NavLastFound = false). NavLastLength — длина по
    /// нити в метрах (прямая — расстояние между концами)
    // halfW — полуширина СТРОЯ, огибающего угол (ТЗ 19.09.2026, п. 2): угол
    // отжимается от кромки ещё и на неё, чтобы внутренний ряд колонны прошёл
    // на своём отступе, а не сжался к оси (NavSpread половинит сдвиг, чей
    // путь задевает стену). Одиночке — ноль
    public float[] NavPath(float x0, float z0, float x1, float z1, float clear, float halfW)
    {
        NavSync();
        NavCalls++;
        NavLastFound = true;
        float sdx = x1 - x0, sdz = z1 - z0;
        NavLastLength = (float)Math.Sqrt(sdx * sdx + sdz * sdz);
        if (!_navOn) return System.Array.Empty<float>();
        if (_navTreeDirty) NavRefreshTrees();
        if (!NavLineBlockedC(x0, z0, x1, z1, clear) && (halfW <= 0.0f || !NavBandBlockedBld(x0, z0, x1, z1, halfW)))
            return System.Array.Empty<float>();
        int sc = (int)Math.Floor((x0 - _navOx) / _navCell), sr = (int)Math.Floor((z0 - _navOz) / _navCell);
        int gc = (int)Math.Floor((x1 - _navOx) / _navCell), gr = (int)Math.Floor((z1 - _navOz) / _navCell);
        sc = Math.Clamp(sc, 0, _navCols - 1); sr = Math.Clamp(sr, 0, _navRows - 1);
        gc = Math.Clamp(gc, 0, _navCols - 1); gr = Math.Clamp(gr, 0, _navRows - 1);
        int start = NavNearestFree(sc, sr, 8);
        int goal = NavNearestFree(gc, gr, 8);
        if (start < 0 || goal < 0) { NavLastFound = false; return System.Array.Empty<float>(); }
        if (start == goal) return System.Array.Empty<float>();
        // Разные компоненты — пути нет, и заливать сетку незачем
        if (_navComp.Length == _nav.Length && _navComp[start] != _navComp[goal])
        {
            NavLastFound = false; NavUnreach++;
            return System.Array.Empty<float>();
        }
        // ── A* ────────────────────────────────────────────────────────────
        _navEpoch++;
        if (_navEpoch == int.MaxValue) { System.Array.Clear(_navStamp, 0, _navStamp.Length); _navEpoch = 1; }
        _heapN = 0;
        int gcc = goal % _navCols, gcr = goal / _navCols;
        _navStamp[start] = _navEpoch; _navG[start] = 0f; _navParent[start] = -1; _navClosed[start] = 0;
        HeapPush(0f, start);
        int expanded = 0;
        bool found = false;
        while (_heapN > 0)
        {
            int cur = HeapPop();
            if (_navClosed[cur] != 0 && _navStamp[cur] == _navEpoch) continue;
            _navClosed[cur] = 1;
            if (cur == goal) { found = true; break; }
            if (++expanded > NavMaxExpand) break;
            int cc = cur % _navCols, cr = cur / _navCols;
            float g0 = _navG[cur];
            for (int k = 0; k < 8; k++)
            {
                int nc = cc + NavDc[k], nr = cr + NavDr[k];
                if (NavCellBlocked(nc, nr)) continue;
                // Диагональ без срезания угла: оба ортогональных соседа свободны
                if (k >= 4 && (NavCellBlocked(cc + NavDc[k], cr) || NavCellBlocked(cc, cr + NavDr[k]))) continue;
                int ni = nr * _navCols + nc;
                float g = g0 + NavDw[k] + NavCellPenalty(ni, clear);
                if (_navStamp[ni] == _navEpoch)
                {
                    if (_navClosed[ni] != 0 || g >= _navG[ni]) continue;
                }
                else { _navStamp[ni] = _navEpoch; _navClosed[ni] = 0; }
                _navG[ni] = g; _navParent[ni] = cur;
                int ddx = Math.Abs(nc - gcc), ddz = Math.Abs(nr - gcr);
                float h = (ddx + ddz) + (1.41421f - 2f) * Math.Min(ddx, ddz);
                HeapPush(g + h, ni);
            }
        }
        if (!found) { NavLastFound = false; return System.Array.Empty<float>(); }
        // ── ЦЕПОЧКА ЯЧЕЕК → ТОЧКИ, НАТЯГИВАНИЕ НИТИ ───────────────────────
        _navCells.Clear();
        for (int i = goal; i >= 0; i = _navParent[i]) { _navCells.Add(i); if (i == start) break; }
        _navCells.Reverse();
        int nCells = _navCells.Count;
        // Точки: старт, центры ячеек (кроме первой и последней), цель
        var px = new float[nCells + 2]; var pz = new float[nCells + 2];
        px[0] = x0; pz[0] = z0;
        for (int i = 0; i < nCells; i++)
        {
            int ci = _navCells[i];
            px[i + 1] = _navOx + (ci % _navCols + 0.5f) * _navCell;
            pz[i + 1] = _navOz + (ci / _navCols + 0.5f) * _navCell;
        }
        px[nCells + 1] = x1; pz[nCells + 1] = z1;
        int last = nCells + 1;
        _navOut.Clear();
        float total = 0f;
        int anchor = 0;
        float ax = px[0], az = pz[0];
        while (anchor < last)
        {
            // Самая дальняя точка, видимая из якоря — С ОТСТУПОМ от стен
            // (NavThreadClearance): нить, натянутая впритык к углу, вела бы
            // отряд вдоль обрыва гуськом
            int far = anchor + 1;
            // Зазор нити — ПОЛОВИНА отступа (как у видимости прямой): с полным
            // отступом нить у стены не спрямлялась вовсе, и тролль получал
            // угол на каждую клетку. Отступ целиком — в отжиме угла ниже
            // ...плюс полуширина строя: нить — хорда, касательная к скале, и
            // ряд, идущий на halfW ближе к стене, чем центр, свою хорду
            // терял (NavSpread половинил сдвиг — блок сжимался за углом)
            float pad = Math.Max(NavThreadClearance, clear * 0.5f) + halfW + NavCliffExtra * 0.5f;
            for (int j = last; j > anchor + 1; j--)
            {
                if (!NavLineBlockedPad(ax, az, px[j], pz[j], pad, clear)) { far = j; break; }
            }
            float fx = px[far], fz = pz[far];
            if (far != last)
            {
                NavCornerPush(ref fx, ref fz, Math.Max(_navCell * 1.5f, clear) + halfW + NavCliffExtra, clear);
                _navOut.Add(fx); _navOut.Add(fz);
            }
            float ddx = fx - ax, ddz = fz - az;
            total += (float)Math.Sqrt(ddx * ddx + ddz * ddz);
            ax = fx; az = fz;
            anchor = far;
        }
        // ── ЧИСТКА ЛИШНИХ УГЛОВ И СКРУГЛЕНИЕ (ТЗ 20.09.2026, пп. 1-2) ──────
        // Отжим угла и подтяжка к дому двигают точку ПОСЛЕ выбора, и угол,
        // ставший ненужным (а то и лежащий позади старта — «призрачный угол»
        // у ворот казармы), оставался в нити. Затем острый угол заменяется
        // дугой по свободной земле, чтобы строй огибал выступ, а не ломался
        // о точку
        NavPrune(x0, z0, x1, z1, clear, halfW);
        NavSmooth(x0, z0, x1, z1, clear, halfW);
        total = 0f;
        float lx = x0, lz = z0;
        for (int i = 0; i + 1 < _navOut.Count; i += 2)
        {
            float sx = _navOut[i] - lx, sz = _navOut[i + 1] - lz;
            total += (float)Math.Sqrt(sx * sx + sz * sz);
            lx = _navOut[i]; lz = _navOut[i + 1];
        }
        { float sx = x1 - lx, sz = z1 - lz; total += (float)Math.Sqrt(sx * sx + sz * sz); }
        NavLastLength = total;
        return _navOut.ToArray();
    }

    // ── ГОРЫ ШИРЕ ДОМОВ (ТЗ 20.09.2026, п. 1) ──────────────────────────────
    // Предыдущий заход свёл обход зданий к тесным 0.2-0.6 м и тем же числом
    // прижал войска к склонам: отряд шёл впритирку к обрыву и вытягивался в
    // нитку (скриншоты 1, 2, 6). Отступ РАЗДЕЛЁН: у рукотворной стены он
    // остался тесным (NavBldSidePad / NavBldCornerPush / NavBldHug), а у
    // скалы и воды к габариту агента прибавляется NavCliffExtra — он входит
    // в штраф шага у стены, в зазор нити и в отжим угла, но НЕ в проверку
    // «точка в стене» (иначе узкий брод стал бы непроходимым)
    public const float NavCliffExtraM = 1.0f;
    // Ручка A/B (perf_config.nav_cliff_arc): выключает прибавку отступа у скал
    // и скругление углов разом — они про одно и то же, обход рельефа
    private bool _navArcOn = true;
    public void SetNavArc(bool on) { _navArcOn = on; NavRouteEpoch++; }
    public int NavRouteEpoch = 0;
    private float NavCliffExtra { get { return _navArcOn ? NavCliffExtraM : 0.0f; } }

    // Скругление угла дугой: дальше этого радиуса скала уже не «выступ»
    private const float NavArcMaxR = 16.0f;
    // Грань дуги — около 20°, то есть 8-10 граней на полный оборот
    private const float NavArcStep = 0.35f;
    // Поворот мельче этого — гладить нечего
    private const float NavArcMinTurn = 0.35f;
    // Сколько дуги брать с каждой стороны от угла (доля до соседней точки)
    private const float NavArcShare = 0.6f;
    private const float NavArcMaxSide = 1.05f;   // не больше 60° на сторону
    private readonly System.Collections.Generic.List<float> _navArc =
        new System.Collections.Generic.List<float>(64);

    private static float NavWrapAngle(float a)
    {
        while (a > (float)Math.PI) a -= (float)(Math.PI * 2.0);
        while (a < -(float)Math.PI) a += (float)(Math.PI * 2.0);
        return a;
    }

    // ── СНЯТИЕ ЛИШНИХ УГЛОВ ────────────────────────────────────────────────
    // Натягивание нити выбирает самую дальнюю видимую точку, но отжим угла
    // и подтяжка к дому двигают её ПОСЛЕ выбора — и соседи угла нередко
    // видят друг друга напрямую. Такой угол — чистый крюк; у самых ворот
    // казармы он ложился ПОЗАДИ бойца, и отряд выходил петлёй (скриншоты
    // 11, 12). Удаляем, пока удаляется, с тем же зазором, что у натягивания
    private void NavPrune(float x0, float z0, float x1, float z1, float clear, float halfW)
    {
        if (_navOut.Count < 2) return;
        float pad = Math.Max(NavThreadClearance, clear * 0.5f) + halfW + NavCliffExtra * 0.5f;
        for (int guard = 0; guard < 8; guard++)
        {
            bool changed = false;
            for (int i = 0; i + 1 < _navOut.Count; i += 2)
            {
                float ax = i == 0 ? x0 : _navOut[i - 2];
                float az = i == 0 ? z0 : _navOut[i - 1];
                float bx = (i + 2 < _navOut.Count) ? _navOut[i + 2] : x1;
                float bz = (i + 2 < _navOut.Count) ? _navOut[i + 3] : z1;
                if (!NavLineBlockedPad(ax, az, bx, bz, pad, clear))
                {
                    _navOut.RemoveAt(i + 1); _navOut.RemoveAt(i);
                    changed = true;
                    break;
                }
            }
            if (!changed) break;
        }
    }

    // ── УГОЛ РЕЛЬЕФА — ДУГА, А НЕ ИЗЛОМ (ТЗ 20.09.2026, п. 1) ───────────────
    // Ломаная из A* давала отряду одну точку поворота: колонна доходила до
    // неё, разворачивалась на месте и вытягивалась. Выступ скалы
    // аппроксимируется окружностью вокруг ближайшей непроходимой ячейки, и
    // угол заменяется дугой по СВОБОДНОЙ земле (2-6 граней, около 20° на
    // грань). Не вышло — угол остаётся как был: сглаживание никогда не
    // делает путь непроходимым
    private void NavSmooth(float x0, float z0, float x1, float z1, float clear, float halfW)
    {
        int n = _navOut.Count / 2;
        if (n == 0) return;
        float pad = Math.Max(NavThreadClearance, clear * 0.5f) + halfW;
        _navArc.Clear();
        for (int k = 0; k < n; k++)
        {
            float px = _navOut[k * 2], pz = _navOut[k * 2 + 1];
            float ax = k == 0 ? x0 : _navOut[k * 2 - 2];
            float az = k == 0 ? z0 : _navOut[k * 2 - 1];
            float bx = (k + 1 < n) ? _navOut[k * 2 + 2] : x1;
            float bz = (k + 1 < n) ? _navOut[k * 2 + 3] : z1;
            if (!_navArcOn || !NavArcCorner(px, pz, ax, az, bx, bz, clear, pad))
            {
                _navArc.Add(px); _navArc.Add(pz);
            }
        }
        _navOut.Clear();
        _navOut.AddRange(_navArc);
    }

    private bool NavArcCorner(float px, float pz, float ax, float az, float bx, float bz,
        float clear, float pad)
    {
        // Ближайшая СКАЛА (kind 1): у дома угол подтянут вплотную намеренно
        int c = (int)Math.Floor((px - _navOx) / _navCell), r = (int)Math.Floor((pz - _navOz) / _navCell);
        int R = (int)Math.Ceiling(NavArcMaxR / _navCell);
        float bestD2 = float.MaxValue, cx = 0f, cz = 0f;
        for (int dr = -R; dr <= R; dr++)
            for (int dc = -R; dc <= R; dc++)
            {
                int cc = c + dc, rr = r + dr;
                if (cc < 0 || rr < 0 || cc >= _navCols || rr >= _navRows) continue;
                if (_nav[rr * _navCols + cc] != 1) continue;
                float wx = _navOx + (cc + 0.5f) * _navCell, wz = _navOz + (rr + 0.5f) * _navCell;
                float ddx = wx - px, ddz = wz - pz;
                float d2 = ddx * ddx + ddz * ddz;
                if (d2 < bestD2) { bestD2 = d2; cx = wx; cz = wz; }
            }
        if (bestD2 == float.MaxValue || bestD2 > NavArcMaxR * NavArcMaxR) return false;
        float rad = (float)Math.Sqrt(bestD2);
        if (rad < 0.6f) return false;
        float pa = (float)Math.Atan2(pz - cz, px - cx);
        float aa = (float)Math.Atan2(az - cz, ax - cx);
        float ba = (float)Math.Atan2(bz - cz, bx - cx);
        float d1 = NavWrapAngle(pa - aa), d2s = NavWrapAngle(ba - pa);
        // Обход выпуклости: обе половины поворачивают в одну сторону
        if (d1 * d2s <= 0.0f) return false;
        if (Math.Abs(d1) + Math.Abs(d2s) < NavArcMinTurn) return false;
        float s1 = Math.Min(Math.Abs(d1) * NavArcShare, NavArcMaxSide) * Math.Sign(d1);
        float s2 = Math.Min(Math.Abs(d2s) * NavArcShare, NavArcMaxSide) * Math.Sign(d2s);
        int segs = Math.Clamp((int)Math.Ceiling((Math.Abs(s1) + Math.Abs(s2)) / NavArcStep), 2, 6);
        var qx = new float[segs + 1]; var qz = new float[segs + 1];
        for (int i = 0; i <= segs; i++)
        {
            float t = (float)i / segs;
            float ang = pa - s1 + (s1 + s2) * t;
            qx[i] = cx + (float)Math.Cos(ang) * rad;
            qz[i] = cz + (float)Math.Sin(ang) * rad;
            if (NavBlockedAtC(qx[i], qz[i], clear)) return false;
        }
        float half = pad * 0.6f;
        if (NavLineBlockedPad(ax, az, qx[0], qz[0], half, clear)) return false;
        for (int i = 0; i < segs; i++)
            if (NavLineBlockedPad(qx[i], qz[i], qx[i + 1], qz[i + 1], half, clear)) return false;
        if (NavLineBlockedPad(qx[segs], qz[segs], bx, bz, half, clear)) return false;
        for (int i = 0; i <= segs; i++) { _navArc.Add(qx[i]); _navArc.Add(qz[i]); }
        return true;
    }
    // Отжим угла от стены НА ЗАДАННЫЙ ОТСТУП (ТЗ 19.09.2026): ищется
    // ближайшая непроходимая клетка в радиусе отжима, и точка уезжает от
    // неё ровно настолько, чтобы отстоять на push (отступ агента плюс
    // полуширина строя). Прежний отжим смотрел только восемь соседей: угол
    // нити на второй-третьей клетке от стены (туда его ставит штраф A*) не
    // отжимался вовсе, и полуширина строя не работала. Не прошло — ступенями
    private void NavCornerPush(ref float x, ref float z, float push, float clear)
    {
        int c = (int)Math.Floor((x - _navOx) / _navCell), r = (int)Math.Floor((z - _navOz) / _navCell);
        int R = (int)Math.Ceiling(push / _navCell) + 1;
        float bestD2 = float.MaxValue, bx = 0f, bz = 0f;
        int kind = 0;
        for (int dr = -R; dr <= R; dr++)
            for (int dc = -R; dc <= R; dc++)
            {
                if (!NavCellBlocked(c + dc, r + dr)) continue;
                float wx = _navOx + (c + dc + 0.5f) * _navCell, wz = _navOz + (r + dr + 0.5f) * _navCell;
                float ddx = wx - x, ddz = wz - z;
                float d2 = ddx * ddx + ddz * ddz;
                if (d2 < bestD2)
                {
                    bestD2 = d2; bx = ddx; bz = ddz;
                    int cc = c + dc, rr = r + dr;
                    kind = (cc < 0 || rr < 0 || cc >= _navCols || rr >= _navRows) ? 1 : _nav[rr * _navCols + cc];
                }
            }
        if (bestD2 == float.MaxValue) return;
        float l = (float)Math.Sqrt(bestD2);
        if (l < 1e-4f) return;
        // ЗДАНИЕ — ВПЛОТНУЮ: угол не дальше NavBldCornerPush от ячейки стены,
        // а затем подтягивается к настоящему кругу фундамента (NavBldHug)
        if (kind == 2)
        {
            float needB = NavBldCornerPush - (l - _navCell * 0.5f);
            if (needB > 0f)
            {
                float nx = x - bx / l * needB, nz = z - bz / l * needB;
                if (!NavBlockedAtC(nx, nz, clear)) { x = nx; z = nz; }
            }
            BldHug(ref x, ref z, bx / l, bz / l, clear);
            return;
        }
        // Вода отжимает угол на прежний отступ: прибавка — про гору
        if (kind == 3) push = Math.Max(push - NavCliffExtra, _navCell * 0.5f);
        float need = push - (l - _navCell * 0.5f);
        if (need <= 0f) return;
        for (float f = 1.0f; f >= 0.4f; f -= 0.3f)
        {
            float nx = x - bx / l * need * f, nz = z - bz / l * need * f;
            if (!NavBlockedAtC(nx, nz, clear) && !NavLineBlockedPad(x, z, nx, nz, 0f, clear)) { x = nx; z = nz; return; }
        }
        float ex = x - bx / l * _navCell * 0.6f, ez = z - bz / l * _navCell * 0.6f;
        if (!NavBlockedAt(ex, ez)) { x = ex; z = ez; }
    }

    // Подтяжка угла к стене дома: сперва вон из кругов (с зазором NavBldHug),
    // потом шагами к ячейке стены, пока круг не в зазоре, — не дальше 2.4 м
    // и не в скалу. Ячейки сетки грубые (2 м), а круги точные: угол ложится
    // у самого фундамента, а не у края ячейки
    private void BldHug(ref float x, ref float z, float dirX, float dirZ, float clear)
    {
        BldPushOut(ref x, ref z, NavBldHug);
        float cx = x, cz = z;
        for (int k = 1; k <= 8; k++)
        {
            float tx = x + dirX * 0.3f * k, tz = z + dirZ * 0.3f * k;
            if (NavKindAt(tx, tz, clear) == 1) break;
            float ox, oz;
            if (BldPenetration(tx, tz, NavBldHug, out ox, out oz) > 0.0f) break;
            cx = tx; cz = tz;
        }
        x = cx; z = cz;
    }
}
