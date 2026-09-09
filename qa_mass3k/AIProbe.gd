extends Node
## Зонд цены МЫШЛЕНИЯ ИИ (headless). qa_mass3k показал стабильные 2.3-2.5 мс
## кадра на «мышление ИИ», при том что оба ИИ думают раз в THINK_INTERVAL и
## между тактами выходят в две строки. Значит, это амортизированный ГОРБ самого
## такта. Зонд поднимает ту же свалку 1500+800+1000, глушит штатный _process
## обоих ИИ и дёргает его вручную с секундомером: кто из двух, сколько стоит
## один такт и сколько кадров он съедает.

const _GobCfg = preload("res://scripts/goblin/goblin_config.gd")

var main = null

const MIX := {
	"res://scenes/units/Spearman.tscn": 0.45,
	"res://scenes/units/Archer.tscn":   0.25,
	"res://scenes/units/Warrior.tscn":  0.20,
	"res://scenes/units/GoblinPigRider.tscn": 0.10,
}
const SQUAD_SIZE := 40

func _ready() -> void:
	call_deferred("_run")

func frames(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame

func _mix_list(n: int) -> Array:
	var out: Array = []
	var total := 0.0
	for k in MIX: total += float(MIX[k])
	for k in MIX:
		var cnt: int = int(round(float(n) * float(MIX[k]) / total))
		for _i in range(cnt): out.append(k)
	while out.size() < n: out.append("res://scenes/units/Spearman.tscn")
	return out

func _stat_of(scene: String) -> String:
	if scene.contains("Archer"): return "archer"
	if scene.contains("Warrior"): return "warrior"
	if scene.contains("PigRider"): return "goblin_rider"
	return "spearman"

func _spawn_army(list: Array, fac: int, at: Vector3, course: Vector3) -> Array:
	var out: Array = []
	var i := 0
	var col := 0
	while i < list.size():
		var n: int = mini(SQUAD_SIZE, list.size() - i)
		var kind: String = String(list[i])
		var sid: int = GameManager.new_squad(fac, _stat_of(kind))
		var bx: float = at.x + float(col % 6) * 9.0
		var bz: float = at.z + float(col / 6) * 8.0
		var slots: Array = []
		for k in range(n):
			var u: Unit = load(kind).instantiate()
			u.faction = fac
			main.world_add(u)
			var px: float = bx + float(k % 8) * 0.75
			var pz: float = bz + float(k / 8) * 0.75
			u.global_position = Vector3(px, GameManager.get_terrain_height(px, pz), pz)
			u.sync_row()
			GameManager.add_to_squad(sid, u)
			out.append(u)
			slots.append(u.global_position)
		GameManager.squad_set_formation(sid, slots, course, false)
		i += n
		col += 1
	return out

func _charge(from: Array, to: Array) -> void:
	var c := Vector3.ZERO
	var n := 0
	for u in to:
		if is_instance_valid(u):
			c += (u as Node3D).global_position
			n += 1
	if n == 0:
		return
	c /= float(n)
	for u in from:
		if is_instance_valid(u):
			(u as Unit).command_move(c, false, Vector3.ZERO, false, true)

func _run() -> void:
	seed(11)
	main = load("res://scenes/Main.tscn").instantiate()
	get_tree().root.add_child(main)
	await frames(20)
	GameManager.world_bounds_enabled = false

	var mine: Array  = _spawn_army(_mix_list(1500), Constants.FACTION_PLAYER,
		Vector3(-46.0, 0.0, -22.0), Vector3(1, 0, 0))
	var foes: Array  = _spawn_army(_mix_list(800), Constants.FACTION_ENEMY,
		Vector3(20.0, 0.0, -18.0), Vector3(-1, 0, 0))
	var horde: Array = _spawn_army(_mix_list(1000), Constants.FACTION_GOBLIN,
		Vector3(20.0, 0.0, 16.0), Vector3(-1, 0, 0))
	await frames(30)
	_charge(mine, foes)
	_charge(foes, mine)
	_charge(horde, mine)
	await frames(60 * 8)

	var eai: Node = main.get("enemy_ai")
	var gai: Node = main.get("goblin_ai")
	if eai == null or gai == null:
		print("НЕ НАШЁЛ ИИ: enemy=%s goblin=%s" % [eai, gai])
		get_tree().quit()
		return
	eai.set_process(false)
	gai.set_process(false)

	# 900 кадров ручного прогона с секундомером вокруг каждого ИИ
	var e_sum := 0
	var g_sum := 0
	var e_max := 0
	var g_max := 0
	var e_spikes: Array = []
	var g_spikes: Array = []
	var n_frames := 900
	for _i in range(n_frames):
		await get_tree().process_frame
		var dt: float = get_process_delta_time()
		var t0: int = Time.get_ticks_usec()
		eai._process(dt)
		var t1: int = Time.get_ticks_usec()
		gai._process(dt)
		var t2: int = Time.get_ticks_usec()
		var de: int = t1 - t0
		var dg: int = t2 - t1
		e_sum += de
		g_sum += dg
		e_max = maxi(e_max, de)
		g_max = maxi(g_max, dg)
		if de > 2000: e_spikes.append(de)
		if dg > 2000: g_spikes.append(dg)

	print("\n═════ ЦЕНА МЫШЛЕНИЯ (%d кадров, свалка ~3300) ═════" % n_frames)
	print("  красный ИИ : всего %7.1f мс | средн %6.3f мс/кадр | макс %6.2f мс | горбов>2мс: %d %s"
		% [e_sum / 1000.0, e_sum / 1000.0 / n_frames, e_max / 1000.0,
			e_spikes.size(), str(e_spikes.map(func(x): return int(x / 1000)))])
	print("  гоблины    : всего %7.1f мс | средн %6.3f мс/кадр | макс %6.2f мс | горбов>2мс: %d %s"
		% [g_sum / 1000.0, g_sum / 1000.0 / n_frames, g_max / 1000.0,
			g_spikes.size(), str(g_spikes.map(func(x): return int(x / 1000)))])
	print("=== AIPROBE DONE ===")
	get_tree().quit()
