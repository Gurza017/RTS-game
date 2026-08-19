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
    private float[] _aggroT = Array.Empty<float>();
    private float[] _atkDmg = Array.Empty<float>();
    private float[] _atkRange = Array.Empty<float>();
    private float[] _speed = Array.Empty<float>();
    private float[] _sepT = Array.Empty<float>();
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

    /// Признаки, приходящие ВМЕСТЕ С ПОЗОЙ и переписываемые целиком
    private const int GateMask = FAtkSimple | FRetreating | FSprinting;

    private const float WorkOverlap = 0.62f;
    // Насколько близко к чужому телу разведение своих не имеет права протолкнуть.
    // То же число, что BLOCK_RADIUS шага (Unit.BLOCK_RADIUS = 0.55): одна и та
    // же «толщина строя» для обеих дорог, которыми боец может сдвинуться
    private const float EnemyPushClear = 0.55f;
    private const int StepFlagMask =
        FRetreating | FSprinting | FClearTrunk | FClearEnemy | FTrunkIgnore;

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
        Array.Resize(ref _atkDmg, cap); Array.Resize(ref _atkRange, cap);
        Array.Resize(ref _speed, cap);
        Array.Resize(ref _sepT, cap);
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
        _px[i] = 0; _py[i] = 0; _pz[i] = 0;
        _vx[i] = 0; _vz[i] = 0;
        _hp[i] = 0; _hpMax[i] = 0;
        _atkCd[i] = 0; _aggroT[i] = 0;
        _atkDmg[i] = 0; _atkRange[i] = 0; _speed[i] = 0;
        // Фаза разбора наложения разводится по номеру строки: иначе весь отряд,
        // вышедший из барака одним заказом, разбирается в один и тот же кадр
        _sepT[i] = (i & 7) * 0.008f;
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
    public int WritePoseBatch(int[] rows, float[] xs, float[] ys, float[] zs,
        float[] vxs, float[] vzs, int[] sts, int[] gates, float[] effSpd)
    {
        int n = rows.Length;
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
        for (int i = 0; i < _capacity; i++)
        {
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
        for (int i = 0; i < _capacity; i++)
        {
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

    public Vector3 EnemyBlock(int row, float tx, float tz, float minDist)
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

    /// ВСЕ БОЙЦЫ В РАДИУСЕ. Холодный путь: клик мышью, попадание стрелы —
    /// единственный скан, которому нужны ОБЕ стороны
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
        int count = rows != null ? rows.Length : _capacity;
        for (int k = 0; k < count; k++)
        {
            int i = rows != null ? rows[k] : k;
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
            // Отходящий проходит насквозь: отряду, которого отзывают в замок,
            // перекрытая дорога означала бы вечное трение о чужую шеренгу
            if ((fl & (FClearEnemy | FRetreating)) == 0)
            {
                int myf = _fac[i];
                // Дешёвый отсев по редкой сетке — ровно тот же, что делает
                // EnemyBlock: без него скан идёт даже по пустой округе
                if (EnemyNear(nx, nz, myf, blockR))
                {
                    BmEnemyScans++;
                    float bx = 0.0f, bz = 0.0f;
                    ScanBlock(i, nx, nz, blockR, blockSq, FacSlot(myf), dead, ref bx, ref bz);
                    if (bx != 0.0f || bz != 0.0f)
                    {
                        BmBlocked++;
                        // УПЁРЛИСЬ В ЧУЖОЙ СТРОЙ. Отмечаем на бойце: идущий
                        // отряд обязан ВСТУПИТЬ В БОЙ, а не обтекать шеренгу
                        var ub = _unitOf[i];
                        if (ub != null && GodotObject.IsInstanceValid(ub))
                            ub.Set("_enemy_contact", true);
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
                            // Второго прохода тут нет НАМЕРЕННО: скольжение
                            // вдоль строя оставляет бойца на прежнем удалении
                            // от тел, и повторная проверка отменяла бы обход
                        }
                        else
                        {
                            float into2 = sx * bnx + sz * bnz;
                            if (into2 > 0.0f) { sx -= bnx * into2; sz -= bnz * into2; }
                            if (sx * sx + sz * sz < 1e-8f) continue;
                            nx = x + sx; nz = z + sz;
                            // Второй проход: боковой шаг тоже упёрся — стоим
                            float ax = 0.0f, az = 0.0f;
                            ScanBlock(i, nx, nz, blockR, blockSq, FacSlot(myf), dead, ref ax, ref az);
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
    private void ScanBlock(int row, float nx, float nz, float blockR, float blockSq,
        int mySlot, int dead, ref float bx, ref float bz)
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
    public int BatchMoveQueued(int[] rows, float[] xs, float[] zs, int[] fls,
        float limX, float limZ, bool boundsOn, bool waterOn,
        float blockR, float trunkClear, float reliefAmp, GodotObject gm)
    {
        int n = rows.Length;
        for (int k = 0; k < n; k++)
        {
            int i = rows[k];
            if (i < 0 || i >= _capacity) continue;
            _stpX[i] = xs[k];
            _stpZ[i] = zs[k];
            _flags[i] = (_flags[i] & ~StepFlagMask) | (fls[k] & StepFlagMask) | FStepPending;
        }
        return BatchMoveRows(rows, limX, limZ, boundsOn, waterOn, blockR,
            trunkClear, reliefAmp, gm);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // ПАКЕТНОЕ РАЗВЕДЕНИЕ НАЛОЖИВШИХСЯ СОЮЗНИКОВ
    // ═══════════════════════════════════════════════════════════════════════
    // Правило не изменилось ни на йоту: поправка монотонна (только наружу и
    // только пока есть наложение), у идущего по приказу из неё вырезается
    // составляющая ПРОТИВ курса, за край карты она не выталкивает и в воду не
    // выдавливает.
    public int BatchSeparation(float delta, float minDist, float maxStep, float interval,
        float limX, float limZ, int movingState, int attackingState, bool waterOn,
        GodotObject gm, float deadzone, float reliefAmp)
    {
        if (_gw == 0) return 0;
        int dead = DeadState;
        float maxSq = maxStep * maxStep;
        float nearD = Mathf.Max(minDist - deadzone, 0.0f);
        float nearSq = nearD * nearD;
        float workD = minDist * WorkOverlap;
        float workNear = Mathf.Max(workD - deadzone, 0.0f);
        float workNearSq = workNear * workNear;
        int moved = 0;
        for (int i = 0; i < _capacity; i++)
        {
            if ((_flags[i] & (FPosValid | FDormant)) != FPosValid) continue;
            int s = _st[i];
            if (s == dead) continue;
            float myMin = minDist;
            float myNearSq = nearSq;
            if ((_flags[i] & FWorking) != 0) { myMin = workD; myNearSq = workNearSq; }
            float t = _sepT[i] - delta;
            if (t > 0.0f) { _sepT[i] = t; continue; }
            _sepT[i] = interval;
            float x = _px[i], z = _pz[i];
            int cx0 = (int)((x - myMin - _gx0) * _ginv);
            int cz0 = (int)((z - myMin - _gz0) * _ginv);
            int cx1 = (int)((x + myMin - _gx0) * _ginv);
            int cz1 = (int)((z + myMin - _gz0) * _ginv);
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
                        float dx = x - _px[j];
                        float dz = z - _pz[j];
                        float dd = dx * dx + dz * dz;
                        // МЁРТВАЯ ЗОНА: сосед, стоящий чуть теснее нормы, в
                        // расчёт не идёт — иначе строй перетаптывается вечно
                        if (dd >= myNearSq) { j = _next[j]; continue; }
                        if (dd < 1e-8f)
                        {
                            float ang = (i % 251) * (Mathf.Tau / 251.0f);
                            dx = Mathf.Cos(ang) * 0.01f;
                            dz = Mathf.Sin(ang) * 0.01f;
                            dd = dx * dx + dz * dz;
                        }
                        float d = Mathf.Sqrt(dd);
                        float need = (myMin - d) / d;
                        pxa += dx * need;
                        pza += dz * need;
                        j = _next[j];
                    }
                }
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
                    ScanBlock(i, nx2, nz2, EnemyPushClear,
                        EnemyPushClear * EnemyPushClear, FacSlot(_fac[i]), dead, ref ex, ref ez);
                    if (ex != 0.0f || ez != 0.0f) continue;
                }
            }
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
            // перерисует
            u.Call("wake_for_lod");
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
        if (_needMask.Length < _capacity) Array.Resize(ref _needMask, _capacity);
        Array.Clear(_needMask, 0, _capacity);
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
        for (int i = 0; i < _capacity; i++)
        {
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
