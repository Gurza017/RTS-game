using Godot;
using System;
using System.Collections.Concurrent;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using System.Threading;

// ═══════════════════════════════════════════════════════════════════════════
// ГОЛОСОВОЙ ВВОД: РАСПОЗНАВАНИЕ ЖИВЁТ В СВОЁМ ПОТОКЕ (прототип, сент. 2026)
// ═══════════════════════════════════════════════════════════════════════════
// Главный поток делает ровно две вещи: кладёт сюда кадры микрофона
// (Push, раз в кадр отрисовки, копия нескольких сотен пар float) и раз в
// кадр спрашивает очередь результатов (PollFinal). Всё остальное — загрузка
// модели, пересчёт частоты, распознавание — идёт в рабочем потоке. Правило
// то же, что у потоков ядра армии: рабочему потоку разрешена только чистая
// математика и библиотека Vosk, ни одного обращения к дереву сцены.
//
// Vosk выбран потому, что принимает ГРАММАТИКУ — список допустимых слов. Наш
// словарь это два десятка слов, и с грамматикой распознаватель не пытается
// услышать в «фаланге» что-то постороннее; всё вне списка приходит как
// [unk]. Модель — vosk-model-small-ru (~45 МБ), лежит в voice_models/ рядом с
// проектом (папка под .gdignore, чтобы Godot не импортировал её файлы).
//
// ── ПОЧЕМУ НЕ ОБЁРТКА Vosk.dll, А ПРЯМЫЕ ВЫЗОВЫ libvosk ─────────────────────
// Обёртка из NuGet маршалит строки как ANSI: грамматика с кириллицей доходила
// до библиотеки знаками вопроса («Ignoring word missing in vocabulary:
// '?????'»), и результат распознавания вернулся бы такими же. Библиотека же
// говорит на UTF-8, поэтому строки идут в неё байтами и читаются байтами.
// Пакет NuGet оставлен ради нативных DLL, которые он кладёт рядом со сборкой.
public partial class VoiceRecognizer : RefCounted
{
    private const float DstRate = 16000f;

    // ── НАТИВНЫЙ ИНТЕРФЕЙС libvosk (UTF-8) ─────────────────────────────────
    private const string Lib = "libvosk";
    [DllImport(Lib)] private static extern void vosk_set_log_level(int level);
    [DllImport(Lib)] private static extern IntPtr vosk_model_new(byte[] path);
    [DllImport(Lib)] private static extern void vosk_model_free(IntPtr model);
    [DllImport(Lib)] private static extern IntPtr vosk_recognizer_new(IntPtr model, float rate);
    [DllImport(Lib)] private static extern IntPtr vosk_recognizer_new_grm(IntPtr model, float rate, byte[] grammar);
    [DllImport(Lib)] private static extern void vosk_recognizer_free(IntPtr rec);
    [DllImport(Lib)] private static extern int vosk_recognizer_accept_waveform_s(IntPtr rec, short[] data, int len);
    [DllImport(Lib)] private static extern IntPtr vosk_recognizer_partial_result(IntPtr rec);
    [DllImport(Lib)] private static extern IntPtr vosk_recognizer_final_result(IntPtr rec);
    [DllImport(Lib)] private static extern void vosk_recognizer_reset(IntPtr rec);

    private IntPtr _model = IntPtr.Zero;
    private IntPtr _rec = IntPtr.Zero;
    private Thread _thread;
    private volatile bool _run;
    private volatile bool _ready;
    private volatile bool _utterance;
    private volatile bool _endRequested;
    private volatile string _error = "";
    private volatile string _partial = "";
    private float _level;
    private float _srcRate = 44100f;
    private string _modelDir = "";
    private string _grammar = "";

    private readonly ConcurrentQueue<Vector2[]> _in = new();
    private readonly ConcurrentQueue<string> _final = new();
    private readonly AutoResetEvent _wake = new(false);

    // Пересчёт частоты: дробная позиция и последний сэмпл прошлого куска,
    // чтобы стык кусков не давал щелчка
    private double _pos;
    private float _prev;

    // ── НАТИВНАЯ БИБЛИОТЕКА ГРУЗИТСЯ ЯВНО, ПО ПОЛНОМУ ПУТИ ─────────────────
    // Godot поднимает игровую сборку из .godot/mono/temp/bin/Debug плагинным
    // контекстом, и обычный DllImport("libvosk") эту папку в поиске не видит:
    // «Unable to load DLL 'libvosk' or one of its dependencies», хотя все
    // четыре DLL лежат рядом со сборкой. Грузим зависимости в порядке
    // (pthread → gcc → stdc++ → vosk) по полному пути и отдаём дескриптор
    // резолверу НАШЕЙ сборки. В экспорте те же файлы лежат рядом с exe
    private static IntPtr _voskHandle = IntPtr.Zero;
    private static string _nativeError = "";
    private static bool _resolverSet;

    private static bool EnsureNative()
    {
        if (_voskHandle != IntPtr.Zero) return true;
        try
        {
            string asmDir = Path.GetDirectoryName(typeof(VoiceRecognizer).Assembly.Location) ?? "";
            string exeDir = AppContext.BaseDirectory ?? "";
            string[] dirs = { asmDir, exeDir, Path.Combine(exeDir, "data_Ten Thousand Spearmen") };
            string[] deps = { "libwinpthread-1.dll", "libgcc_s_seh-1.dll", "libstdc++-6.dll" };
            foreach (var d in dirs)
            {
                if (string.IsNullOrEmpty(d) || !File.Exists(Path.Combine(d, "libvosk.dll"))) continue;
                foreach (var dep in deps)
                {
                    var dp = Path.Combine(d, dep);
                    if (File.Exists(dp)) NativeLibrary.Load(dp);
                }
                _voskHandle = NativeLibrary.Load(Path.Combine(d, "libvosk.dll"));
                break;
            }
            if (_voskHandle == IntPtr.Zero)
            {
                _nativeError = "libvosk.dll не найдена рядом со сборкой или exe";
                return false;
            }
            if (!_resolverSet)
            {
                NativeLibrary.SetDllImportResolver(typeof(VoiceRecognizer).Assembly,
                    (name, asm, path) => name == Lib ? _voskHandle : IntPtr.Zero);
                _resolverSet = true;
            }
            return true;
        }
        catch (Exception e)
        {
            _nativeError = e.Message;
            return false;
        }
    }

    private static byte[] Utf8Z(string s)
    {
        var b = Encoding.UTF8.GetBytes(s ?? "");
        var z = new byte[b.Length + 1];
        Array.Copy(b, z, b.Length);
        return z;
    }

    private static string Utf8From(IntPtr p)
    {
        return p == IntPtr.Zero ? "" : (Marshal.PtrToStringUTF8(p) ?? "");
    }

    /// Запуск: модель грузится в рабочем потоке (около секунды), до её
    /// готовности Push складывает кадры в очередь, а IsReady отвечает false
    public bool Start(string modelDir, string grammarJson, float sampleRate)
    {
        if (_run) return true;
        if (!EnsureNative())
        {
            _error = "native: " + _nativeError;
            return false;
        }
        _modelDir = modelDir;
        _grammar = grammarJson;
        _srcRate = sampleRate > 1000f ? sampleRate : 44100f;
        _run = true;
        try
        {
            _thread = new Thread(Worker) { IsBackground = true, Name = "VoiceRecognizer" };
            _thread.Start();
        }
        catch (Exception e)
        {
            _error = e.Message;
            _run = false;
            return false;
        }
        return true;
    }

    public void Stop()
    {
        _run = false;
        _wake.Set();
    }

    public bool IsReady() => _ready;
    public string GetError() => _error;
    public string GetPartial() => _partial;
    public float GetLevel() => _level;
    public bool IsListening() => _utterance;

    /// Кнопка зажата: с этого момента кадры микрофона идут в распознаватель
    public void BeginUtterance()
    {
        while (_in.TryDequeue(out _)) { }
        _partial = "";
        _utterance = true;
        _endRequested = false;
    }

    /// Кнопка отпущена: досушить очередь и выдать финальный текст
    public void EndUtterance()
    {
        if (!_utterance) return;
        _utterance = false;
        _endRequested = true;
        _wake.Set();
    }

    /// Кадры микрофона (стерео пары из AudioEffectCapture). Копия массива
    /// уже сделана маршалингом — очередь держит её до рабочего потока
    public void Push(Vector2[] frames)
    {
        if (!_utterance || frames == null || frames.Length == 0) return;
        _in.Enqueue(frames);
        _wake.Set();
    }

    /// Финальный текст последней фразы или пустая строка
    public string PollFinal()
    {
        return _final.TryDequeue(out var s) ? s : "";
    }

    /// Для стендов: прогнать готовый моно-сигнал 16 кГц как одну фразу и
    /// вернуть текст (блокирующе, в вызывающем потоке). Живой микрофон этим
    /// путём не ходит — он идёт очередью через рабочий поток
    public string RecognizeBlocking(int[] pcm16kInt)
    {
        if (!_ready || _rec == IntPtr.Zero || pcm16kInt == null || pcm16kInt.Length == 0) return "";
        var pcm16k = new short[pcm16kInt.Length];
        for (int i = 0; i < pcm16kInt.Length; i++)
            pcm16k[i] = (short)Math.Clamp(pcm16kInt[i], short.MinValue, short.MaxValue);
        lock (this)
        {
            vosk_recognizer_accept_waveform_s(_rec, pcm16k, pcm16k.Length);
            var text = Extract(Utf8From(vosk_recognizer_final_result(_rec)), "text");
            vosk_recognizer_reset(_rec);
            return text;
        }
    }

    // ── РАБОЧИЙ ПОТОК ───────────────────────────────────────────────────────
    private void Worker()
    {
        try
        {
            vosk_set_log_level(-1);
            _model = vosk_model_new(Utf8Z(_modelDir));
            if (_model == IntPtr.Zero) throw new Exception("модель не открылась: " + _modelDir);
            _rec = string.IsNullOrEmpty(_grammar)
                ? vosk_recognizer_new(_model, DstRate)
                : vosk_recognizer_new_grm(_model, DstRate, Utf8Z(_grammar));
            if (_rec == IntPtr.Zero) throw new Exception("распознаватель не создался");
            _ready = true;
        }
        catch (Exception e)
        {
            _error = "model: " + e.Message;
            _run = false;
            return;
        }
        var pcm = new short[8192];
        while (_run)
        {
            _wake.WaitOne(50);
            if (!_run) break;
            bool got = false;
            while (_in.TryDequeue(out var frames))
            {
                got = true;
                int n = Resample(frames, ref pcm);
                if (n > 0)
                {
                    try
                    {
                        lock (this)
                        {
                            vosk_recognizer_accept_waveform_s(_rec, pcm, n);
                            _partial = Extract(Utf8From(vosk_recognizer_partial_result(_rec)), "partial");
                        }
                    }
                    catch (Exception e) { _error = "accept: " + e.Message; }
                }
            }
            if (_endRequested)
            {
                _endRequested = false;
                string text = "";
                try
                {
                    lock (this)
                    {
                        text = Extract(Utf8From(vosk_recognizer_final_result(_rec)), "text");
                        vosk_recognizer_reset(_rec);
                    }
                }
                catch (Exception e) { _error = "final: " + e.Message; }
                _final.Enqueue(text);
                _partial = "";
                _pos = 0.0;
                _prev = 0f;
                _level = 0f;
            }
            if (!got && !_utterance) _level = 0f;
        }
        try
        {
            if (_rec != IntPtr.Zero) vosk_recognizer_free(_rec);
            if (_model != IntPtr.Zero) vosk_model_free(_model);
        }
        catch { }
        _rec = IntPtr.Zero;
        _model = IntPtr.Zero;
    }

    /// Стерео float в 16 кГц моно int16 линейной интерполяцией; заодно уровень
    private int Resample(Vector2[] frames, ref short[] pcm)
    {
        double step = _srcRate / DstRate;
        int n = 0;
        float sq = 0f;
        int len = frames.Length;
        double p = _pos;
        while (true)
        {
            int i0 = (int)Math.Floor(p);
            int i1 = i0 + 1;
            if (i1 >= len) break;
            float a = i0 < 0 ? _prev : Mono(frames[i0]);
            float b = Mono(frames[i1]);
            float t = (float)(p - i0);
            float v = a + (b - a) * t;
            if (n >= pcm.Length) Array.Resize(ref pcm, pcm.Length * 2);
            float c = Math.Clamp(v, -1f, 1f);
            pcm[n++] = (short)(c * 32767f);
            sq += c * c;
            p += step;
        }
        _prev = Mono(frames[len - 1]);
        _pos = p - len;
        if (n > 0) _level = (float)Math.Sqrt(sq / n);
        return n;
    }

    private static float Mono(Vector2 f) => (f.X + f.Y) * 0.5f;

    private static string Extract(string json, string key)
    {
        if (string.IsNullOrEmpty(json)) return "";
        try
        {
            using var doc = JsonDocument.Parse(json);
            if (doc.RootElement.TryGetProperty(key, out var el))
                return el.GetString() ?? "";
        }
        catch { }
        return "";
    }
}
