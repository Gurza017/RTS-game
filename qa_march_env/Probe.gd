extends Node
## ЗОНД: ОГИБАЮЩАЯ ГРОМКОСТИ ЛУПОВ МАРША (headless).
## Dummy-драйвер AudioServer микширует, и AudioEffectCapture на своей шине
## отдаёт PCM — так по файлу видно то, чего не видно в редакторе: тишину в
## начале, набивку mp3, пики. По нему найден MARCH_RUN_START_SEC (0.78 с).
## Вердиктов нет — это измеритель, в шлюз не входит.
## Запуск: godot --headless --path . res://qa_march_env/Probe.tscn
func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, "Probe")
	var cap := AudioEffectCapture.new()
	cap.buffer_length = 4.0
	AudioServer.add_bus_effect(idx, cap)
	for path in [AudioManager.MARCH_RUN_LOOP, AudioManager.MARCH_WALK_LOOP]:
		var s: AudioStream = load(path)
		var p := AudioStreamPlayer.new()
		p.bus = "Probe"
		p.stream = s
		add_child(p)
		p.play(0.0)
		var t0 := Time.get_ticks_msec()
		var rms: Array = []
		var acc: float = 0.0
		var n: int = 0
		var mix: float = AudioServer.get_mix_rate()
		var win: int = int(mix * 0.02)
		while Time.get_ticks_msec() - t0 < 2500:
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
		var line := ""
		var first_loud := -1
		var peak := 0.0
		for r in rms: peak = maxf(peak, float(r))
		for i in range(rms.size()):
			if first_loud < 0 and float(rms[i]) > peak * 0.25:
				first_loud = i
		print("FILE %s mix=%d windows=%d peak=%.4f first>25%%peak at %.3f s" % [path.get_file(), int(mix), rms.size(), peak, float(first_loud) * 0.02])
		for i in range(mini(rms.size(), 60)):
			line += "%.3f " % float(rms[i])
		print("  env(20ms): " + line)
	get_tree().quit()
