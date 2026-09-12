extends Node
## ЗОНД: ОГИБАЮЩАЯ И ГРАНИЦЫ РЕПЛИК В СОСТАВНЫХ ФАЙЛАХ (headless, спринт 18).
## Dummy-драйвер AudioServer микширует, AudioEffectCapture отдаёт PCM.
## Печатает для каждого файла длину, пик и ОТРЕЗКИ ГРОМКОСТИ (выше доли пика
## после паузы длиннее GAP_SEC) — по ним режется «Come on! ×3».
## Вердиктов нет — измеритель, в шлюз не входит.
## Запуск: godot --headless --path . res://qa_audio_env/Probe.tscn [-- file=res://...]

const FILES := [
	"res://assets/factions/humans/Sounds Human/magiaz-man_saying_come_on-396180.mp3",
	"res://assets/factions/humans/Sounds Human/magiaz-man_saying_go_go_go-396189.mp3",
	"res://assets/factions/Goblin/Goblins_voice/goblin_death.mp3",
	"res://assets/factions/Goblin/Goblins_voice/horde_horn.mp3",
	"res://assets/factions/Goblin/Goblins_voice/goblin_laugh_1.mp3",
	"res://assets/factions/Goblin/Goblins_voice/goblin_attack_1.mp3",
	"res://assets/factions/orc/Troll/Troll_voice/troll_growl_2.mp3",
	"res://assets/factions/orc/Troll/Troll_voice/troll_victory.mp3",
	"res://assets/environment/Main Sounds/River Stream Loop.ogg",
	"res://assets/factions/humans/Sounds Human/mine 5.ogg",
	"res://assets/factions/humans/Sounds Human/Chest Close 1.ogg",
]
const WIN_SEC := 0.02
const GAP_SEC := 0.12
const THRESH := 0.08

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var files: Array = FILES.duplicate()
	for a in OS.get_cmdline_user_args():
		var s := String(a)
		if s.begins_with("file="):
			files = [s.substr(5)]
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, "Probe")
	var cap := AudioEffectCapture.new()
	cap.buffer_length = 8.0
	AudioServer.add_bus_effect(idx, cap)
	var mix: float = AudioServer.get_mix_rate()
	var win: int = int(mix * WIN_SEC)
	for path in files:
		if not ResourceLoader.exists(path):
			print("FILE %s: НЕТ ФАЙЛА" % path)
			continue
		var s: AudioStream = load(path)
		var length: float = s.get_length()
		var p := AudioStreamPlayer.new()
		p.bus = "Probe"
		p.stream = s
		add_child(p)
		cap.clear_buffer()
		p.play(0.0)
		var t0 := Time.get_ticks_msec()
		var rms: Array = []
		var acc: float = 0.0
		var n: int = 0
		var budget: int = int(minf(length + 0.3, 12.0) * 1000.0)
		while Time.get_ticks_msec() - t0 < budget:
			await get_tree().process_frame
			var avail := cap.get_frames_available()
			if avail > 0:
				var buf := cap.get_buffer(avail)
				for v in buf:
					acc += v.x * v.x
					n += 1
					if n >= win:
						rms.append(sqrt(acc / float(n)))
						acc = 0.0
						n = 0
		p.stop()
		p.queue_free()
		var peak := 0.0
		for r in rms: peak = maxf(peak, float(r))
		# Отрезки: громкое окно открывает отрезок, тишина длиннее GAP_SEC закрывает
		var segs: Array = []
		var open := -1
		var quiet := 0
		var gap_w: int = int(GAP_SEC / WIN_SEC)
		for i in range(rms.size()):
			var loud: bool = float(rms[i]) > peak * THRESH
			if loud:
				if open < 0:
					open = i
				quiet = 0
			elif open >= 0:
				quiet += 1
				if quiet >= gap_w:
					segs.append([open, i - quiet])
					open = -1
					quiet = 0
		if open >= 0:
			segs.append([open, rms.size() - 1])
		var txt := ""
		for sg in segs:
			txt += "[%.2f-%.2f] " % [float(sg[0]) * WIN_SEC, float(sg[1] + 1) * WIN_SEC]
		print("FILE %s: длина %.2f с, пик %.3f, отрезков %d: %s" % [
			path.get_file(), length, peak, segs.size(), txt])
		var line := ""
		for i in range(mini(rms.size(), 200)):
			line += "%d" % int(clampf(float(rms[i]) / maxf(peak, 1e-6) * 9.0, 0.0, 9.0))
		print("  env(20мс, 0-9): " + line)
	get_tree().quit()
