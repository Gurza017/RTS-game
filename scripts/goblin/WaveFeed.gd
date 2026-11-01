extends RefCounted

## ═══════════════════════════════════════════════════════════════════════════
## ПОДАЧА ВОЛНЫ В БОЙ ДОЗАМИ (ТЗ 31.10.2026, «главная мысль» владельца)
## ═══════════════════════════════════════════════════════════════════════════
## Прежде на развёртывании КАЖДЫЙ отряд волны получал пару фронта разом
## (GoblinAI._engage_squad) — орда вкатывалась в чужой строй одной кучей.
## Теперь бой ведётся ДОЗАМИ:
##   • чужие отряды у волны — список «фронт» от центра к флангам (нечётное
##     число — центр и два фланга, чётное — два фланга);
##   • на каждый чужой отряд — один свой, а при своём перевесе вдвое — два
##     (FEED_PAIR_RATIO); туши — первыми и на копейщиков, пехота — по краям;
##     новых в бой за такт не больше FEED_DOSE_MAX;
##   • остальные стоят на месте развёртывания — резерв;
##   • лишний резерв (сверх покрытия) — один отряд за раз заходит во фланг
##     крайнему чужому (FEED_FLANK_OFF вбок, удар с разворота);
##   • свой отряд просел ниже FEED_REPLACE_FRAC — на его противника свежий
##     из резерва (подкрепление туда же), просевший дерётся, но не считается;
##   • чужой просел ниже FEED_BREACH_FRAC и уже в бою — до FEED_CAV_MAX
##     отрядов конницы бьют в брешь;
##   • полководец не подаётся — им ведает свой мозг (PigBossCommander).
## Ручка perf_config.wave_feed; строки «[ВОЛНА …] доза/замена/брешь» — в лог.

const _Spawn := preload("res://scripts/spawn_config.gd")
const _Opt := preload("res://scripts/perf_config.gd")
const _WM := preload("res://scripts/goblin/WaveMarch.gd")

## Чужие отряды у точки: [[sid, центр, живых, доля штата], …] от центра
## фронта к флангам; fwd — курс «мы → они» (пишется в w["feed_fwd"])
static func foe_squads(gai, w: Dictionary, around: Vector3, radius: float) -> Array:
	var acc: Dictionary = {}
	for n in GameManager.unit_grid.query_radius(around, radius):
		var e := n as Unit
		if e == null or e.is_dead() or e.squad_id <= 0 or e.garrisoned:
			continue
		if e.faction != Constants.FACTION_PLAYER and e.faction != Constants.FACTION_ENEMY:
			continue
		if e.stat_id == "sheep" or e.is_ghost():
			continue
		var a: Variant = acc.get(e.squad_id)
		if a == null:
			acc[e.squad_id] = [e.position.x, e.position.z, 1]
		else:
			var arr: Array = a
			arr[0] = float(arr[0]) + e.position.x
			arr[1] = float(arr[1]) + e.position.z
			arr[2] = int(arr[2]) + 1
	if acc.is_empty():
		return []
	var mine: Vector3 = gai._wave_centre(w)
	var out: Array = []
	var ex := 0.0
	var ez := 0.0
	for k in acc:
		var a2: Array = acc[k]
		var c := Vector3(float(a2[0]) / float(a2[2]), 0.0, float(a2[1]) / float(a2[2]))
		var alive: int = gai._alive_n(int(k))
		out.append([int(k), c, alive, float(alive) / float(maxi(GameManager.squad_full_size(int(k)), 1))])
		ex += c.x
		ez += c.z
	ex /= float(out.size())
	ez /= float(out.size())
	var fwd := Vector3(ex - mine.x, 0.0, ez - mine.z)
	fwd = fwd.normalized() if fwd.length() > 0.1 else (w.get("dir", Vector3.FORWARD) as Vector3)
	w["feed_fwd"] = fwd
	var side := Vector3(-fwd.z, 0.0, fwd.x)
	var mid: float = ex * side.x + ez * side.z
	for f in out:
		(f as Array).append(absf((f[1] as Vector3).x * side.x + (f[1] as Vector3).z * side.z - mid))
	out.sort_custom(func(a, b): return float(a[4]) < float(b[4]))
	return out

static func _is_cav(gai, sid: int) -> bool:
	var ty: String = gai._type(sid)
	return ty == "goblin_rider"

static func _is_big(gai, sid: int) -> bool:
	var ty: String = gai._type(sid)
	return ty == "big_goblin" or ty == "troll"

static func _frac(gai, sid: int) -> float:
	return float(gai._alive_n(sid)) / float(maxi(GameManager.squad_full_size(sid), 1))

## Такт подачи. false — чужих отрядов у волны нет (прежняя логика: постройки,
## точка удара). on — sid → чужой sid; spent — просевшие (дерутся, не в счёт)
static func tick(gai, w: Dictionary) -> bool:
	var around: Vector3 = gai._wave_centre(w)
	var foes: Array = foe_squads(gai, w, around, _Spawn.FEED_SCAN_R)
	if foes.is_empty():
		return false
	if not w.has("feed"):
		w["feed"] = {"on": {}, "spent": {}, "flank": {}, "cav": {}}
		gai.feed_starts += 1
	var fd: Dictionary = w["feed"]
	var on: Dictionary = fd["on"]
	var spent: Dictionary = fd["spent"]
	var flank: Dictionary = fd["flank"]
	var cav_on: Dictionary = fd["cav"]
	var foe_ids: Dictionary = {}
	for f in foes:
		foe_ids[int(f[0])] = f
	var live: Array = w["sids"]
	# ── Уборка: выбитые свои, выбитые/ушедшие чужие ───────────────────────────
	for d in [on, spent, flank, cav_on]:
		for sid in (d as Dictionary).keys():
			if not live.has(sid):
				(d as Dictionary).erase(sid)
	for sid2 in on.keys():
		if not foe_ids.has(int(on[sid2])):
			on.erase(sid2)
	for sid2b in cav_on.keys():
		if not foe_ids.has(int(cav_on[sid2b])):
			cav_on.erase(sid2b)
	if _Opt.boss_wave_sync:
		_boss_open(gai, w, fd, foes)
	# ── Просевшие: на их противника — свежий ──────────────────────────────────
	for sid3 in on.keys():
		if not spent.has(sid3) and _frac(gai, int(sid3)) < _Spawn.FEED_REPLACE_FRAC:
			spent[sid3] = int(on[sid3])
			gai.feed_replaced += 1
			_WM._log(gai, w, "замена: отряд %d (%s) просел до %.0f%% — на отряд %d нужен свежий" % [
				int(sid3), gai._type(int(sid3)), _frac(gai, int(sid3)) * 100.0, int(on[sid3])])
	# ── Резерв: пехота и туши вне боя и не во фланговом заходе ────────────────
	var res_front: Array = []
	var res_cav: Array = []
	for s in live:
		var sid4: int = int(s)
		if on.has(sid4) or flank.has(sid4) or cav_on.has(sid4) or gai._is_boss_sid(sid4):
			continue
		if _is_cav(gai, sid4):
			res_cav.append(sid4)
		else:
			res_front.append(sid4)
	var n_front: int = res_front.size()
	for sid5 in on:
		if not spent.has(sid5):
			n_front += 1
	var k_per: int = 2 if n_front >= _Spawn.FEED_PAIR_RATIO * foes.size() else 1
	# ── Покрытие: от центра к флангам, по k_per на чужой отряд ─────────────────
	var dosed := 0
	if _Opt.boss_wave_sync and fd.has("boss_t"):
		var bt0: int = int(fd["boss_t"])
		for fi in range(foes.size()):
			if int(foes[fi][0]) == bt0 and fi > 0:
				foes = foes.duplicate()
				var head: Array = foes[fi]
				foes.remove_at(fi)
				foes.push_front(head)
				break
	for f in foes:
		var fid: int = int(f[0])
		var have := 0
		for sid6 in on:
			if int(on[sid6]) == fid and not spent.has(sid6):
				have += 1
		while have < k_per and not res_front.is_empty() and dosed < _Spawn.FEED_DOSE_MAX:
			var pick: int = _pick_for(gai, res_front, f)
			res_front.erase(pick)
			on[pick] = fid
			have += 1
			dosed += 1
			gai.feed_doses += 1
			gai._order_attack_squad(pick, fid)
			_WM._log(gai, w, "доза: отряд %d (%s) → отряд %d (%s, %.0f%%)" % [
				pick, gai._type(pick), fid, GameManager.squad_type(fid), float(f[3]) * 100.0])
	# ── Фланг: один лишний резерв за раз — во фланг крайнему ──────────────────
	if flank.is_empty() and res_front.size() >= 1 and dosed == 0:
		var edge: Array = foes[foes.size() - 1]
		var fwd: Vector3 = w.get("feed_fwd", Vector3.FORWARD)
		var side := Vector3(-fwd.z, 0.0, fwd.x)
		var ec: Vector3 = edge[1]
		var sgn: float = 1.0 if (ec - around).dot(side) >= 0.0 else -1.0
		var fsid: int = int(res_front[res_front.size() - 1])
		var fp: Vector3 = GameManager.land_target(ec + side * sgn * _Spawn.FEED_FLANK_OFF)
		flank[fsid] = {"pt": fp, "foe": int(edge[0]), "t": gai.clock}
		res_front.erase(fsid)
		gai.feed_flanks += 1
		gai._order_move(fsid, fp, true)
		_WM._log(gai, w, "фланг: отряд %d (%s) заходит во фланг отряду %d" % [fsid, gai._type(fsid), int(edge[0])])
	for fs in flank.keys():
		var fl: Dictionary = flank[fs]
		var fc: Vector3 = gai._centre(int(fs))
		var arrived: bool = fc.x != INF and Vector2(fc.x - (fl["pt"] as Vector3).x, fc.z - (fl["pt"] as Vector3).z).length() < _Spawn.HALT_ARRIVE_R
		if arrived or gai.clock - float(fl["t"]) > _Spawn.FEED_FLANK_SEC:
			var foe2: int = int(fl["foe"]) if foe_ids.has(int(fl["foe"])) else int(foes[foes.size() - 1][0])
			flank.erase(fs)
			on[fs] = foe2
			gai._order_attack_squad(int(fs), foe2)
	# ── Брешь: ослабший чужой в бою — конница (до FEED_CAV_MAX) ────────────────
	if not res_cav.is_empty():
		for f2 in foes:
			if float(f2[3]) >= _Spawn.FEED_BREACH_FRAC:
				continue
			var fid2: int = int(f2[0])
			var hit := false
			for sid7 in on:
				if int(on[sid7]) == fid2:
					hit = true
			if not hit:
				continue
			var cn := 0
			for sid8 in cav_on:
				if int(cav_on[sid8]) == fid2:
					cn += 1
			while cn < _Spawn.FEED_CAV_MAX and not res_cav.is_empty():
				var cs: int = int(res_cav.pop_front())
				cav_on[cs] = fid2
				cn += 1
				gai.feed_breaches += 1
				gai._order_attack_squad(cs, fid2)
				_WM._log(gai, w, "брешь: конница %d → отряд %d (%.0f%%)" % [cs, fid2, float(f2[3]) * 100.0])
	# ── В бою, но встал без дела (цель ушла из строя) — тот же приказ ещё раз ──
	for sid9 in on:
		if gai._squad_idle(int(sid9)):
			gai._order_attack_squad(int(sid9), int(on[sid9]))
	for sid10 in cav_on:
		if gai._squad_idle(int(sid10)):
			gai._order_attack_squad(int(sid10), int(cav_on[sid10]))
	return true

## ── СВИНОБОСС ВСКРЫВАЕТ ОБОРОНУ (ТЗ 31.10.2026, ручка boss_wave_sync) ─────
## Подача началась — босс бьёт центральный чужой отряд (фронт отсортирован от
## центра), дозы идут на тот же; цель сломлена (ниже FEED_BREACH_FRAC) или
## ушла — следующий по фронту, всего BOSS_OPEN_MAX. Дальше босс свободен
const BOSS_OPEN_MAX := 2

static func _boss_open(gai, w: Dictionary, fd: Dictionary, foes: Array) -> void:
	var boss := -1
	for s in (w["sids"] as Array):
		if gai._is_boss_sid(int(s)):
			boss = int(s)
			break
	if boss < 0:
		return
	var bt: int = int(fd.get("boss_t", -1))
	for f in foes:
		if int(f[0]) == bt and float(f[3]) >= _Spawn.FEED_BREACH_FRAC:
			return
	var n: int = int(fd.get("boss_n", 0))
	if n >= BOSS_OPEN_MAX:
		return
	var tgt := -1
	for f2 in foes:
		if int(f2[0]) != bt and float(f2[3]) >= _Spawn.FEED_BREACH_FRAC:
			tgt = int(f2[0])
			break
	if tgt < 0:
		return
	fd["boss_t"] = tgt
	fd["boss_n"] = n + 1
	gai.feed_boss_opens += 1
	gai._order_attack_squad(boss, tgt)
	_WM._log(gai, w, "босс вскрывает: отряд %d → отряд %d (%s)" % [boss, tgt, GameManager.squad_type(tgt)])

## Кого из резерва на этого чужого: против копейщиков — туша первой, иначе
## ближайший; пехота по краям достаётся сама (фронт отсортирован от центра)
static func _pick_for(gai, res: Array, foe: Array) -> int:
	var fc: Vector3 = foe[1]
	var spear: bool = GameManager.squad_type(int(foe[0])) == "spearman"
	var best: int = int(res[0])
	var best_k := INF
	for s in res:
		var sid: int = int(s)
		var c: Vector3 = gai._centre(sid)
		var k: float = 1.0e6 if c.x == INF else Vector2(c.x - fc.x, c.z - fc.z).length()
		if _is_big(gai, sid):
			k += -40.0 if spear else 0.0
		if k < best_k:
			best_k = k
			best = sid
	return best
