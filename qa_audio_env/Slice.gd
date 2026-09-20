extends Node
## ═══════════════════════════════════════════════════════════════════════════
## НАРЕЗЧИК ПАКА ГРЮНТОВ (ТЗ 19.09.2026 «Audio System Update», блок 2)
## ═══════════════════════════════════════════════════════════════════════════
## Проигрывает voicebosch-monster-grunts-174559.mp3 через AudioEffectCapture
## (в headless dummy-драйвер микширует, PCM читается — тот же приём, что у
## qa_audio_env/Probe), режет по тишине на отдельные сэмплы и пишет WAV:
##   • первая половина файла (тяжёлые рыки)     → Troll_voice/troll_grunt_N.wav
##   • середина (средние рыки, выкрики)          → Goblins_voice/big_grunt_N.wav
##   • завершающая треть (визги, хрюканье)       → Goblins_voice/goblin_grunt_N.wav
## Границы третей — по ВРЕМЕНИ файла (BIG_FROM / SMALL_FROM доли длины).
## Ключи: -- dry (только печать отрезков), -- gap=0.18 thresh=0.06 minlen=0.12
## Запуск: godot --headless --path . res://qa_audio_env/Slice.tscn

const SRC := "res://assets/factions/humans/Sounds Human/voicebosch-monster-grunts-174559.mp3"
const OUT_TROLL := "res://assets/factions/orc/Troll/Troll_voice/"
const OUT_GOBLIN := "res://assets/factions/Goblin/Goblins_voice/"
const WIN_SEC := 0.01
const BIG_FROM := 0.50     # доля длины: с неё — «середина» (туши)
const SMALL_FROM := 0.67   # с неё — «завершающая треть» (мелкие)
const PAD_SEC := 0.04      # запас тишины по краям отрезка
const MAX_SEG_SEC := 2.5   # длиннее — режется по самому тихому окну внутри

var gap_sec := 0.16
var thresh := 0.06
var min_len := 0.12
var dry := false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s == "dry":
			dry = true
		elif s.begins_with("gap="):
			gap_sec = float(s.substr(4))
		elif s.begins_with("thresh="):
			thresh = float(s.substr(7))
		elif s.begins_with("minlen="):
			min_len = float(s.substr(7))
	call_deferred("_run")

func _run() -> void:
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, "Slice")
	var cap := AudioEffectCapture.new()
	cap.buffer_length = 16.0
	AudioServer.add_bus_effect(idx, cap)
	var mix: int = int(AudioServer.get_mix_rate())
	var s: AudioStream = load(SRC)
	if s == null:
		print("НЕТ ФАЙЛА " + SRC)
		get_tree().quit()
		return
	var length: float = s.get_length()
	print("файл %s: %.2f с, mix %d Гц" % [SRC.get_file(), length, mix])
	var p := AudioStreamPlayer.new()
	p.bus = "Slice"
	p.stream = s
	add_child(p)
	cap.clear_buffer()
	p.play(0.0)
	# Весь PCM (моно = среднее каналов) в памяти: 2-3 минуты по 44.1 кГц —
	# несколько мегабайт float, это допустимо для инструмента
	var pcm := PackedFloat32Array()
	var t0 := Time.get_ticks_msec()
	var budget: int = int((length + 0.5) * 1000.0)
	while Time.get_ticks_msec() - t0 < budget:
		await get_tree().process_frame
		var avail := cap.get_frames_available()
		if avail > 0:
			var buf := cap.get_buffer(avail)
			var base: int = pcm.size()
			pcm.resize(base + buf.size())
			for i in range(buf.size()):
				pcm[base + i] = (buf[i].x + buf[i].y) * 0.5
	p.stop()
	print("захвачено %d сэмплов (%.2f с)" % [pcm.size(), float(pcm.size()) / float(mix)])
	# Огибающая RMS по окнам
	var win: int = int(mix * WIN_SEC)
	var nwin: int = pcm.size() / win
	var rms := PackedFloat32Array()
	rms.resize(nwin)
	var peak := 0.0
	for w in range(nwin):
		var acc := 0.0
		var o: int = w * win
		for i in range(win):
			var v: float = pcm[o + i]
			acc += v * v
		var r: float = sqrt(acc / float(win))
		rms[w] = r
		peak = maxf(peak, r)
	# Отрезки: громкое окно открывает, тишина длиннее gap закрывает
	var segs: Array = []
	var open := -1
	var quiet := 0
	var gap_w: int = int(gap_sec / WIN_SEC)
	for i in range(nwin):
		var loud: bool = rms[i] > peak * thresh
		if loud:
			if open < 0:
				open = i
			quiet = 0
		elif open >= 0:
			quiet += 1
			if quiet >= gap_w:
				segs.append([open, i - quiet + 1])
				open = -1
				quiet = 0
	if open >= 0:
		segs.append([open, nwin])
	# Длинные отрезки — по самому тихому окну внутри, пока не уложатся
	var out_segs: Array = []
	var stack: Array = segs.duplicate()
	while not stack.is_empty():
		var sg: Array = stack.pop_front()
		var a: int = int(sg[0])
		var b: int = int(sg[1])
		if float(b - a) * WIN_SEC <= MAX_SEG_SEC:
			out_segs.append(sg)
			continue
		var best := -1
		var best_v := 1e9
		for i in range(a + int(0.3 / WIN_SEC), b - int(0.3 / WIN_SEC)):
			if rms[i] < best_v:
				best_v = rms[i]
				best = i
		if best < 0:
			out_segs.append(sg)
			continue
		stack.push_front([best, b])
		stack.push_front([a, best])
	out_segs.sort_custom(func(x, y): return int(x[0]) < int(y[0]))
	var kept: Array = []
	for sg in out_segs:
		if float(int(sg[1]) - int(sg[0])) * WIN_SEC >= min_len:
			kept.append(sg)
	print("отрезков %d (после фильтра ≥ %.2f с), пик %.3f" % [kept.size(), min_len, peak])
	var n_troll := 0
	var n_big := 0
	var n_small := 0
	var pad: int = int(PAD_SEC * mix)
	for sg in kept:
		var a_s: int = maxi(int(sg[0]) * win - pad, 0)
		var b_s: int = mini(int(sg[1]) * win + pad, pcm.size())
		var t_a: float = float(a_s) / float(mix)
		var t_b: float = float(b_s) / float(mix)
		var centre: float = (t_a + t_b) * 0.5 / length
		var seg_peak := 0.0
		for i in range(a_s, b_s):
			seg_peak = maxf(seg_peak, absf(pcm[i]))
		var kind := "troll"
		var path := ""
		if centre >= SMALL_FROM:
			kind = "small"
			n_small += 1
			path = OUT_GOBLIN + "goblin_grunt_%d.wav" % n_small
		elif centre >= BIG_FROM:
			kind = "big"
			n_big += 1
			path = OUT_GOBLIN + "big_grunt_%d.wav" % n_big
		else:
			n_troll += 1
			path = OUT_TROLL + "troll_grunt_%d.wav" % n_troll
		print("  [%6.2f-%6.2f] %.2f с пик %.2f → %s %s" % [t_a, t_b, t_b - t_a, seg_peak, kind, path.get_file()])
		if dry:
			continue
		# Нормировка к −3 дБ по пику и короткие фейды по краям (щелчков нет)
		var gain: float = 0.7079 / maxf(seg_peak, 1e-4)
		var n: int = b_s - a_s
		var fade: int = mini(int(0.006 * mix), n / 4)
		var data := PackedByteArray()
		data.resize(n * 2)
		for i in range(n):
			var v: float = pcm[a_s + i] * gain
			if i < fade:
				v *= float(i) / float(fade)
			elif n - i <= fade:
				v *= float(n - i) / float(fade)
			var q: int = int(clampf(v, -1.0, 1.0) * 32767.0)
			data.encode_s16(i * 2, q)
		var wav := AudioStreamWAV.new()
		wav.format = AudioStreamWAV.FORMAT_16_BITS
		wav.mix_rate = mix
		wav.stereo = false
		wav.data = data
		var err: int = wav.save_to_wav(path)
		if err != OK:
			print("    ОШИБКА записи %s: %d" % [path, err])
	print("итого: тролль %d, туши %d, мелкие %d" % [n_troll, n_big, n_small])
	get_tree().quit()
