extends Node
## Medición de rendimiento en 5 escenarios (CPU de scripts, llamadas de dibujo, memoria, objetos, picos).
## SIN GPU real: los FPS por software no son representativos; solo se informan tiempos de script/física,
## draw calls, memoria y picos de fotograma como comparación antes/después en el mismo entorno.
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 -- --perftest --out=DIR [--tag=base]

var main: Node
var out_dir := "/tmp/perftest"
var tag := "run"
var player: Player
var ct: CaseThrow
var results: Dictionary = {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		if a.begins_with("--tag="):
			tag = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out_dir)
	call_deferred("_run")


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _secs(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _clear() -> void:
	for e in Combat.arena_enemies().duplicate():
		if is_instance_valid(e) and e.get("alive"):
			e.set("invuln_t", 0.0)
			e.take_damage(float(e.get("hp")) * 20.0 + 20.0, {"src": "boss_death", "silent": true})
	await _frames(5)
	ct.clear_all()
	GameState.build.reset({})
	player.skills.reset()
	player.teleport_to(Vector3(0, 0.1, 0))
	await _frames(5)


func _spawn_many(n: int, kinds: Array) -> Dictionary:
	var worst := 0.0
	var tot := 0.0
	for i in n:
		var t0 := Time.get_ticks_usec()
		var ang := TAU * float(i) / float(maxi(1, n))
		var r := 8.0 + float(i % 4) * 2.5
		main.arena._spawn_enemy(kinds[i % kinds.size()], Vector3(cos(ang) * r, 0.1, sin(ang) * r))
		var dt := float(Time.get_ticks_usec() - t0) / 1000.0
		worst = maxf(worst, dt)
		tot += dt
	return {"spawn_worst_ms": worst, "spawn_avg_ms": tot / float(maxi(1, n))}


func _measure(name: String, secs: float, cast_every := 0.0, extra := {}) -> void:
	var ft: Array = []
	var proc: Array = []
	var phys: Array = []
	var dc: Array = []
	var cast_worst := 0.0
	var t := 0.0
	var next_cast := 0.0
	var last := Time.get_ticks_usec()
	var chase0 := Enemy.chase_us
	var chasen0 := Enemy.chase_n
	var frames := 0
	while t < secs:
		if cast_every > 0.0 and t >= next_cast:
			next_cast = t + cast_every
			player.skills.cd[0] = 0.0
			var c0 := Time.get_ticks_usec()
			player.skills.try_cast(0)
			cast_worst = maxf(cast_worst, float(Time.get_ticks_usec() - c0) / 1000.0)
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var dt := float(now - last) / 1000.0
		last = now
		t += dt / 1000.0
		frames += 1
		if frames > 3:
			ft.append(dt)
			proc.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
			phys.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
			dc.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var alive := 0
	for e in Combat.arena_enemies():
		if is_instance_valid(e) and e.alive:
			alive += 1
	var r := {
		"enemies": alive,
		"frames": frames,
		"frame_ms_avg": _avg(ft), "frame_ms_p95": _pct(ft, 0.95), "frame_ms_max": _max(ft),
		"proc_ms_avg": _avg(proc), "proc_ms_max": _max(proc),
		"phys_ms_avg": _avg(phys), "phys_ms_p95": _pct(phys, 0.95), "phys_ms_max": _max(phys),
		"draw_calls_avg": _avg(dc), "draw_calls_max": _max(dc),
		"mem_static_mb": OS.get_static_memory_usage() / 1048576.0,
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"cast_worst_ms": cast_worst,
		"chase_us_per_call": float(Enemy.chase_us - chase0) / float(maxi(1, Enemy.chase_n - chasen0)),
	}
	r.merge(extra)
	results[name] = r
	print("[PERF] %s %s" % [name, JSON.stringify(r)])


func _avg(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += float(v)
	return s / float(a.size())


func _max(a: Array) -> float:
	var m := 0.0
	for v in a:
		m = maxf(m, float(v))
	return m


func _pct(a: Array, p: float) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	return float(b[mini(b.size() - 1, int(float(b.size()) * p))])


func _run() -> void:
	await _frames(10)
	await main._enter_lobby(true)
	await _frames(15)
	main._on_play()
	var t := 0.0
	while main.state != main.St.RUN and t < 10.0:
		await _frames(2)
		t += 0.03
	Config.dev_god_mode = true
	main.arena.force_complete()
	await _secs(1.0)
	ct = GameState.case_throw
	player = GameState.player
	SaveSystem.data["settings"]["auto_attack"] = false
	var kinds := ["thief", "thief", "elite", "thief"]
	print("[PERF] quality=%s version=%s" % [str(Config.quality()), Config.VERSION])

	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
	if only == "3":
		await _clear()
		var sp3 := _spawn_many(50, kinds)
		await _secs(1.5)
		await _measure("3_muchos", 4.0, 0.0, sp3)
		get_tree().quit(0)
		return
	# 1. pocos enemigos
	await _clear()
	var sp := _spawn_many(5, kinds)
	await _secs(1.5)
	await _measure("1_pocos", 4.0, 0.0, sp)
	# 2. intermedio
	await _clear()
	sp = _spawn_many(20, kinds)
	await _secs(1.5)
	await _measure("2_intermedio", 4.0, 0.0, sp)
	# 3. muchos
	await _clear()
	sp = _spawn_many(50, kinds)
	await _secs(1.5)
	await _measure("3_muchos", 4.0, 0.0, sp)
	# 4. proyectiles / explosiones / habilidades
	await _clear()
	for id in ["case_knives", "case_missiles", "case_rays", "case_orbit", "case_files", "case_ghost", "case_fireworks", "case_discs", "case_laser",
			"case_open", "case_retray", "case_kfall", "case_wave", "case_gren", "case_chase", "case_blast", "case_shock", "case_bounce",
			"case_more_knives", "case_more_missiles", "case_more_rays", "case_xtra", "case_both", "case_split", "case_seek", "case_blast_n",
			"case_cases", "case_double", "case_magazine", "case_multi", "case_pyro", "case_frag", "case_docs", "case_rain"]:
		var d: Dictionary = UpgradeDB.get_def(id)
		if d.is_empty():
			continue
		for k in mini(int(d["max"]), 6):
			GameState.build.add(id, 3, true)
	sp = _spawn_many(30, kinds)
	for e in Combat.arena_enemies():
		e.max_hp = 1.0e12
		e.hp = 1.0e12
	await _secs(1.0)
	await _measure("4_efectos", 8.0, 0.8, sp)
	# 5. jefe + otros
	await _clear()
	GameState.arena_index = 5
	main.arena.index = 5
	main.arena._spawn_enemy("boss", Vector3(0, 0.3, -9))
	sp = _spawn_many(15, kinds)
	await _secs(2.0)
	await _measure("5_jefe", 8.0, 1.0, sp)

	var f := FileAccess.open("%s/perf_%s.json" % [out_dir, tag], FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "  "))
	f.close()
	print("[PERF] DONE")
	get_tree().quit(0)
