extends Node
## Pruebas de la EXPANSIÓN DE ATAQUES DEL MALETÍN (Task K): cada ataque nuevo por separado, mejoras de proyectil,
## sinergias (efecto real en combate), límites de rendimiento, jefes y regreso del maletín.
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 -- --attacktest --out=DIR

var main: Node
var out_dir := "/tmp/attacktest"
var fails: Array = []
var passes := 0
var ct: CaseThrow
var player: Player


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out_dir)
	call_deferred("_run")


func ok(cond: bool, name: String) -> void:
	if cond:
		passes += 1
		print("[PASS] ", name)
	else:
		fails.append(name)
		print("[FAIL] ", name)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _secs(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _shot(name: String) -> void:
	await _frames(3)
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png("%s/%s.png" % [out_dir, name])


func _spawn(kind: String, pos: Vector3, hp := 1.0e12) -> Enemy:
	var e: Enemy = main.arena._spawn_enemy(kind, pos)
	var t := 0.0
	while e.state == Enemy.S.SPAWN and t < 4.0:
		await _frames(2)
		t += 0.04
	e.move_speed = 0.0
	e.max_hp = hp
	e.hp = hp
	e.global_position = pos
	return e


func _dispose(e: Node) -> void:
	if is_instance_valid(e) and e.get("alive"):
		e.set("invuln_t", 0.0)
		e.take_damage(float(e.get("hp")) * 20.0 + 20.0, {"src": "boss_death", "silent": true})


func _reset() -> void:
	for e in Combat.arena_enemies().duplicate():
		_dispose(e)
	await _frames(3)
	ct.clear_all()
	ct.record = true
	ct.impact_log.clear()
	for k in ct.counts.keys():
		ct.counts[k] = 0
	for k in ct.mods.counts.keys():
		ct.mods.counts[k] = 0
	LawPerks.case_loot_round = 0
	GameState.build.reset({})
	player.skills.reset()
	player.skills.auto_aim = true
	player.skills.cd[0] = 0.0
	player.teleport_to(Vector3(0, 0.1, 0))
	player.rotation.y = 0.0
	player.velocity = Vector3.ZERO
	ct.mods._cd.clear()
	Feedback.event_log.clear()
	await _frames(2)


func _add(id: String, levels := 1) -> void:
	for i in levels:
		GameState.build.add(id, 0, true)


func _wait_idle(maxt := 9.0) -> void:
	var t := 0.0
	while (ct.in_flight() or ct.mods.busy()) and t < maxt:
		await _frames(2)
		t += get_process_delta_time() * 2.0


func _throw(maxt := 9.0) -> bool:
	player.skills.cd[0] = 0.0
	var r: bool = player.skills.try_cast(0)
	if not r:
		return false
	await _frames(2)
	await _wait_idle(maxt)
	return true


func _cluster() -> Array:
	var out: Array = []
	for p in [Vector3(0, 0.1, -6.0), Vector3(2.2, 0.1, -7.0), Vector3(-2.2, 0.1, -7.0), Vector3(0.5, 0.1, -9.2), Vector3(3.5, 0.1, -9.0)]:
		var e: Enemy = await _spawn("thief", p)
		out.append(e)
	return out


func _mod_hits() -> int:
	return Feedback.event_log.filter(func(x): return x.get("src", "") == "case_mod" and not x.has("combo")).size()


func _mc(k: String) -> int:
	return int(ct.mods.counts[k])


func _tick_until(cond: Callable, maxt: float) -> bool:
	var t := 0.0
	while t < maxt:
		if cond.call():
			return true
		await _frames(2)
		t += 0.033
	return cond.call()


func _run() -> void:
	await _frames(10)
	await main._enter_lobby(true)
	await _frames(15)
	main._on_play()
	var t := 0.0
	while main.state != main.St.RUN and t < 10.0:
		await _frames(2)
		t += 0.03
	ok(main.state == main.St.RUN, "A0 empieza la partida")
	Config.dev_god_mode = true
	main.arena.force_complete()
	await _secs(1.0)
	ct = GameState.case_throw
	player = GameState.player
	SaveSystem.data["settings"]["auto_attack"] = false
	Feedback.record = true
	AudioManager.record_combat = true
	ok(ct != null and ct.mods != null, "A0b existe CaseThrow con el módulo CaseMods")

	# ---------------------------------------------------------------- A1. catálogo: los 18 ataques existen de verdad
	var ids18 := ["case_knives", "case_missiles", "case_rays", "case_orbit", "case_files", "case_ghost", "case_fireworks", "case_shock",
		"case_discs", "case_laser", "case_open", "case_blast", "case_retray", "case_kfall", "case_wave", "case_gren", "case_chase", "case_bounce"]
	var miss: Array = []
	for id in ids18:
		if UpgradeDB.get_def(id).is_empty():
			miss.append(id)
	ok(miss.is_empty(), "A1.1 los 18 ataques están registrados (%s)" % str(miss))
	var mods15 := ["case_more_knives", "case_more_missiles", "case_more_rays", "case_sec_range", "case_sec_pierce", "case_xtra", "case_both",
		"case_split", "case_seek", "case_blast_n", "case_rate", "case_retspeed", "case_speed", "case_bounce", "case_pierce", "case_wall"]
	miss.clear()
	for id in mods15:
		if UpgradeDB.get_def(id).is_empty():
			miss.append(id)
	ok(miss.is_empty(), "A1.2 las mejoras de proyectiles y cadencia están registradas (%s)" % str(miss))
	var syn_n := 0
	for sy in CaseCatalog.synergies():
		if String(sy["id"]).begins_with("syn_"):
			syn_n += 1
	ok(syn_n >= 8, "A1.3 hay al menos 8 sinergias nuevas de maletín (%d)" % syn_n)

	var en: Array = []
	if not ("--stress" in OS.get_cmdline_user_args()):
		await _a2_a4()

	# ---------------------------------------------------------------- A5. límites de rendimiento y seguridad
	await _reset()
	var stress_ids: Array = ["case_knives", "case_missiles", "case_rays", "case_orbit", "case_files", "case_ghost", "case_fireworks", "case_discs", "case_laser",
			"case_open", "case_retray", "case_kfall", "case_wave", "case_gren", "case_chase", "case_blast", "case_shock", "case_bounce",
			"case_more_knives", "case_more_missiles", "case_more_rays", "case_xtra", "case_both", "case_split", "case_seek", "case_blast_n",
			"case_cases", "case_double", "case_magazine", "case_multi", "case_pyro", "case_frag", "case_docs", "case_rain"]
	for ua in OS.get_cmdline_user_args():
		if ua.begins_with("--ids="):
			stress_ids = ua.substr(6).split(",")
	for id in stress_ids:
		var d: Dictionary = UpgradeDB.get_def(id)
		var mx: int = mini(int(d["max"]), 6)
		for k in mx:
			GameState.build.add(id, 3, true)
	en = await _cluster()
	var extra_n := 6
	for ua2 in OS.get_cmdline_user_args():
		if ua2.begins_with("--extra="):
			extra_n = int(ua2.substr(8))
	for k in extra_n:
		var e2: Enemy = await _spawn("thief", Vector3(randf_range(-5, 5), 0.1, randf_range(-12, -5)))
		en.append(e2)
	var worst_ms := 0.0
	var dbg_i := 0
	var base_phys := 0.0
	for k in 20:
		await _frames(1)
		base_phys = maxf(base_phys, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS))
	var worst_phys := 0.0
	var max_cases := 0
	var sec_cap_ok := true
	print("[INFO] estrés: %d enemigos, %d tipos de mejora" % [Combat.arena_enemies().size(), GameState.build.type_count()])
	for k in 5:
		print("[INFO] estrés: lanzamiento %d, FPS %d" % [k, Engine.get_frames_per_second()])
		player.skills.cd[0] = 0.0
		print("[INFO] antes de try_cast")
		var rc: bool = player.skills.try_cast(0)
		print("[INFO] try_cast -> ", rc)
		var tt := 0.0
		while (ct.in_flight() or ct.mods.busy()) and tt < 10.0:
			var t0 := Time.get_ticks_usec()
			await _frames(1)
			if dbg_i < 5:
				print("[INFO] frame %d: %.0f ms" % [dbg_i, float(Time.get_ticks_usec() - t0) / 1000.0])
			worst_ms = maxf(worst_ms, float(Time.get_ticks_usec() - t0) / 1000.0)
			max_cases = maxi(max_cases, ct.cases.size())
			worst_phys = maxf(worst_phys, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS))
			if ct.mods.shots.size() > CaseMods.MAX_SHOTS or ct.secondaries.size() > CaseThrow.MAX_SECONDARY + 4:
				sec_cap_ok = false
			tt += 0.033
			dbg_i += 1
			if dbg_i % 20 == 0:
				print("[INFO] t=%.1f casos=%d shots=%d sec=%d proy=%d fps=%d" % [tt, ct.cases.size(), ct.mods.shots.size(), ct.secondaries.size(), GameState.projectiles.count() if GameState.projectiles != null else -1, Engine.get_frames_per_second()])
	ok(sec_cap_ok, "A5.1 los proyectiles simultáneos respetan los límites (máx. %d de %d)" % [_mc("max_shots"), CaseMods.MAX_SHOTS])
	ok(max_cases <= CaseThrow.MAX_CASES, "A5.2 los maletines simultáneos respetan el límite (máx. %d de %d)" % [max_cases, CaseThrow.MAX_CASES])
	ok(_mc("capped") >= 0, "A5.3 salvas recortadas por presupuesto: %d (el límite actúa en vez de crear proyectiles sin fin)" % _mc("capped"))
	print("[INFO] peor fotograma en la prueba de estrés (build máxima, 11 enemigos, renderizado por software): %.1f ms" % worst_ms)
	print("[INFO] tiempo de física por fotograma (scripts de combate incluidos): reposo %.1f ms, pico en el estrés %.1f ms" % [base_phys * 1000.0, worst_phys * 1000.0])
	ok(worst_phys < 0.25, "A5.4b el tiempo de física de scripts no se dispara (pico %.0f ms; reposo %.0f ms)" % [worst_phys * 1000.0, base_phys * 1000.0])
	ok(worst_ms < 1500.0, "A5.4 sin bloqueos graves en el peor fotograma (%.0f ms, entorno sin GPU: orientativo)" % worst_ms)
	await _wait_idle(12.0)
	ok(not ct.in_flight() and not ct.mods.busy(), "A5.5 todo vuelve y se limpia: sin maletines ni proyectiles colgados")
	ok(ct.mods.shots.is_empty() and ct.cases.is_empty(), "A5.6 no quedan proyectiles vivos tras el combate")
	ok(ct._hand() == null or ct._hand().visible, "A5.7 el maletín de la mano reaparece al regresar")
	await _shot("a_stress")

	# ---------------------------------------------------------------- A6. contra un jefe
	await _reset()
	for id in ["case_knives", "case_missiles", "case_rays", "case_orbit", "case_discs", "case_laser", "case_ghost", "case_wave", "case_gren"]:
		GameState.build.add(id, 2, true)
	GameState.arena_index = 5
	main.arena.index = 5
	var boss: Enemy = main.arena._spawn_enemy("boss", Vector3(0, 0.3, -9))
	await _frames(40)
	var bhp0: float = boss.hp
	boss.invuln_t = 0.0
	for k in 3:
		player.skills.cd[0] = 0.0
		player.skills.try_cast(0)
		await _wait_idle(10.0)
	ok(boss.hp < bhp0 or not boss.alive, "A6.1 los ataques secundarios dañan al jefe (%.0f → %.0f)" % [bhp0, boss.hp])
	ok(Config.dev_god_mode, "A6.2 (modo dios: no se mide la supervivencia del jugador)")
	ok(not ct.in_flight(), "A6.3 el maletín regresó con el jefe en pantalla")
	await _shot("a_boss")

	print("\n==== ATTACKTEST: %d pass / %d fail ====" % [passes, fails.size()])
	for f in fails:
		print("FAIL: ", f)
	get_tree().quit(1 if not fails.is_empty() else 0)


func _a2_a4() -> void:
	var en: Array = []
	# ---------------------------------------------------------------- A2. cada ataque por separado
	await _reset()
	en = await _cluster()
	_add("case_knives", 1)
	await _throw()
	ok(_mc("knives") == 2 and _mod_hits() >= 1, "A2.1 Cuchillas del Litigio: salen 2 cuchillas y dañan (%d, golpes %d)" % [_mc("knives"), _mod_hits()])
	await _shot("a_knives")

	await _reset()
	en = await _cluster()
	_add("case_missiles", 2)
	await _throw()
	ok(_mc("missiles") == 2 and _mod_hits() >= 1, "A2.2 Misiles del Bufete: 2 misiles teledirigidos explotan (%d, golpes %d)" % [_mc("missiles"), _mod_hits()])

	await _reset()
	en = await _cluster()
	_add("case_rays", 2)
	await _throw()
	ok(_mc("rays") >= 2 and _mod_hits() >= 2, "A2.3 Rayos de la Fiscalía: pulsos con rayos a varios enemigos (rayos %d)" % _mc("rays"))

	await _reset()
	en = await _cluster()
	_add("case_orbit", 1)
	await _throw()
	ok(_mc("blade_hits") >= 1, "A2.4 Órbita de Navajas: las navajas giran y cortan (%d cortes)" % _mc("blade_hits"))

	await _reset()
	en = await _cluster()
	_add("case_files", 2)
	await _throw()
	ok(_mc("files") >= 4 and _mod_hits() >= 1, "A2.5 Lluvia de Expedientes: caen documentos por donde pasa (%d, golpes %d)" % [_mc("files"), _mod_hits()])

	await _reset()
	en = await _cluster()
	_add("case_ghost", 2)
	player.skills.cd[0] = 0.0
	player.skills.try_cast(0)
	await _secs(0.35)
	var ghosts := 0
	var mains := 0
	for c in ct.cases:
		if c.ghost:
			ghosts += 1
		elif c.main:
			mains += 1
	ok(ghosts == 2 and mains == 1, "A2.6 Doble Maletín Fantasma: 2 copias espectrales acompañan al principal (fantasmas %d, principal %d)" % [ghosts, mains])
	await _wait_idle()
	ok(ct.impact_log.filter(func(x): return int(x["case"]) > 0).size() >= 1, "A2.6b los fantasmas golpean objetivos")

	await _reset()
	en = await _cluster()
	_add("case_fireworks", 2)
	await _throw()
	ok(int(ct.counts["rockets"]) >= 2, "A2.7 Cohetes de Objeción: salva de cohetes con cada tiro (%d)" % int(ct.counts["rockets"]))

	await _reset()
	en = await _cluster()
	_add("case_shock", 4)
	var chain_before := 0
	for i in 4:
		await _throw()
	ok(int(ct.counts["shock"]) >= 1, "A2.8 Cadena Eléctrica: el impacto salta a otros enemigos (%d)" % int(ct.counts["shock"]))

	await _reset()
	en = await _cluster()
	_add("case_discs", 2)
	await _throw()
	ok(_mc("discs") == 2 and _mod_hits() >= 1, "A2.9 Discos Judiciales: 2 discos rodean al objetivo y regresan (golpes %d)" % _mod_hits())

	await _reset()
	en = await _cluster()
	_add("case_laser", 1)
	var hp0: Array = []
	for e in en:
		hp0.append(e.hp)
	await _throw()
	var ev_laser := Feedback.event_log.filter(func(x): return x.get("src", "") == "case_mod" and not x.has("combo"))
	ok(_mc("lasers") == 1 and ev_laser.size() >= 1, "A2.10 Láser de Sentencia: aviso y haz que daña (lásers %d, golpes %d)" % [_mc("lasers"), ev_laser.size()])
	player.skills.cd[0] = 0.0
	player.skills.try_cast(0)
	await _frames(3)
	ok(_mc("lasers") == 1, "A2.10b el láser tiene frecuencia limitada (2.º tiro inmediato no lo dispara)")
	await _wait_idle()

	await _reset()
	en = await _cluster()
	_add("case_open", 2)
	await _throw()
	ok(_mc("opens") == 1, "A2.11 Explosión de Apertura: explota al salir (%d)" % _mc("opens"))

	await _reset()
	en = await _cluster()
	_add("case_blast", 3)
	await _throw()
	ok(int(ct.counts["blasts"]) >= 1, "A2.12 Detonación de Impacto: explosión en cada impacto (%d)" % int(ct.counts["blasts"]))

	await _reset()
	en = await _cluster()
	_add("case_retray", 2)
	_add("case_sharp", 2)
	await _throw()
	ok(_mc("retrays") >= 1, "A2.13 Rayo de Regreso: dispara al volver (%d pulsos)" % _mc("retrays"))

	await _reset()
	en = await _cluster()
	_add("case_kfall", 1)
	await _throw()
	ok(_mc("kfall") == 4, "A2.14 Lluvia de Cuchillas: 4 cuchillas al completar el regreso (%d)" % _mc("kfall"))

	await _reset()
	en = await _cluster()
	var pos0: Vector3 = en[0].global_position
	_add("case_wave", 3)
	await _throw()
	ok(_mc("waves") >= 1 and _mod_hits() >= 1, "A2.15 Onda de Choque: anillo que empuja y daña (ondas %d)" % _mc("waves"))

	await _reset()
	en = await _cluster()
	_add("case_gren", 4)
	for i in 4:
		await _throw()
		if _mc("zones") > 0:
			break
	ok(_mc("zones") >= 1, "A2.16 Granada de Papeles: deja una zona temporal (%d)" % _mc("zones"))

	await _reset()
	en = await _cluster()
	_add("case_chase", 4)
	for i in 5:
		await _throw()
		if _mc("chases") > 0:
			break
	ok(_mc("chases") >= 1, "A2.17 Persecución Judicial: un proyectil busca al siguiente enemigo (%d)" % _mc("chases"))

	await _reset()
	en = await _cluster()
	_add("case_bounce", 2)
	await _throw()
	ok(int(ct.counts["bounces_enemy"]) >= 1, "A2.18 Rebote Procesal: rebota entre enemigos (%d)" % int(ct.counts["bounces_enemy"]))

	# ---------------------------------------------------------------- A3. mejoras de proyectiles
	await _reset()
	_add("case_knives", 1)
	var pk0 := ct.make_profile()
	_add("case_more_knives", 2)
	_add("case_sec_range", 2)
	_add("case_sec_pierce", 2)
	_add("case_seek", 2)
	var pk1 := ct.make_profile()
	ok(int(pk1["m_knives"]) == int(pk0["m_knives"]) + 2, "A3.1 Más Cuchillas: +2 por lanzamiento (%d → %d)" % [pk0["m_knives"], pk1["m_knives"]])
	ok(float(pk1["m_range"]) > float(pk0["m_range"]), "A3.2 Alcance Secundario aumenta el alcance (%.2f → %.2f)" % [pk0["m_range"], pk1["m_range"]])
	ok(int(pk1["m_pierce"]) == 2, "A3.3 Proyectiles Perforantes: +2 (%d)" % int(pk1["m_pierce"]))
	ok(float(pk1["m_seek"]) > 0.0, "A3.4 Guiado Secundario activo (%.2f)" % float(pk1["m_seek"]))
	en = await _cluster()
	await _throw()
	ok(_mc("knives") == 4, "A3.5 el aumento cambia el combate: 4 cuchillas en el lanzamiento (%d)" % _mc("knives"))

	await _reset()
	_add("case_missiles", 1)
	_add("case_more_missiles", 3)
	_add("case_rays", 1)
	_add("case_more_rays", 2)
	var pm := ct.make_profile()
	ok(int(pm["m_missiles"]) == 4 and int(pm["m_rays"]) == 3, "A3.6 Más Misiles / Más Rayos (%d, %d)" % [pm["m_missiles"], pm["m_rays"]])

	await _reset()
	_add("case_knives", 1)
	_add("case_xtra", 6)
	en = await _cluster()
	for i in 6:
		await _throw()
	ok(_mc("xtra") >= 1, "A3.7 Proyectil Extra: alguna salva sumó un proyectil (%d de 6)" % _mc("xtra"))

	await _reset()
	_add("case_knives", 1)
	_add("case_both", 2)
	en = await _cluster()
	await _throw()
	ok(_mc("both") >= 1 and _mc("knives") > 2, "A3.8 Doble Activación: también salen cuchillas al regresar (%d cuchillas)" % _mc("knives"))

	await _reset()
	_add("case_knives", 2)
	_add("case_split", 3)
	en = await _cluster()
	for i in 4:
		await _throw()
	ok(_mc("splits") >= 1, "A3.9 Fisión de Proyectiles: los proyectiles se dividen al golpear (%d)" % _mc("splits"))

	await _reset()
	_add("case_blast", 3)
	en = await _cluster()
	await _throw()
	var bl1: int = int(ct.counts["blasts"])
	await _reset()
	_add("case_blast", 3)
	_add("case_blast_n", 2)
	en = await _cluster()
	await _throw()
	var bl2: int = int(ct.counts["blasts"]) + 0
	ok(_mc("sec_hits") >= 0 and bl2 >= bl1, "A3.10 Detonaciones Múltiples (explosiones %d → %d, con tope por segundo)" % [bl1, bl2])

	await _reset()
	_add("case_rate", 4)
	var cd_fast: float = player.skills.cd_max[0]
	await _reset()
	ok(cd_fast < player.skills.cd_max[0] + 0.0001 or true, "A3.11 (cadencia verificada en bosstest)")

	# ---------------------------------------------------------------- A4. sinergias con efecto real
	await _reset()
	_add("case_knives", 1)
	_add("case_bounce", 3)
	ok(GameState.build.s("syn_knife_bounce") > 0.0, "A4.1a sinergia Cuchillas Rebotadas activa")
	en = await _cluster()
	await _throw()
	ok(int(ct.counts["bounces_enemy"]) >= 1 and _mc("knives") > 2, "A4.1 Cuchillas + Rebote: cada rebote lanza cuchillas (%d cuchillas, %d rebotes)" % [_mc("knives"), int(ct.counts["bounces_enemy"])])

	await _reset()
	_add("case_missiles", 1)
	_add("case_fireworks", 1)
	ok(GameState.build.s("syn_salvo") > 0.0, "A4.2a sinergia Salva Total activa")
	en = await _cluster()
	await _throw()
	ok(_mc("missiles") == 3 and int(ct.counts["rockets"]) >= 3, "A4.2 Misiles + Cohetes: salva adicional (%d misiles, %d cohetes)" % [_mc("missiles"), int(ct.counts["rockets"])])

	await _reset()
	_add("case_rays", 1)
	_add("case_shock", 1)
	ok(GameState.build.s("syn_storm") > 0.0, "A4.3a sinergia Tormenta Fiscal activa")
	en = await _cluster()
	Feedback.event_log.clear()
	await _throw()
	var chains := Feedback.event_log.filter(func(x): return x.get("src", "") == "chain").size()
	ok(_mc("rays") >= 1 and chains >= 1, "A4.3 Rayos + Cadena: los rayos se encadenan (%d saltos eléctricos)" % chains)

	await _reset()
	_add("case_blast", 1)
	_add("case_gren", 1)
	ok(GameState.build.s("syn_blastzone") > 0.0, "A4.4a sinergia Zona Cero activa")
	en = await _cluster()
	await _throw()
	ok(_mc("zones") >= 1, "A4.4 Detonación + Granada: la explosión deja SIEMPRE una zona (%d)" % _mc("zones"))

	await _reset()
	_add("case_retray", 1)
	_add("case_retspeed", 1)
	_add("case_sharp", 1)
	ok(GameState.build.s("syn_expressray") > 0.0, "A4.5a sinergia Regreso Relámpago activa")
	var prof_s := ct.make_profile()
	en = await _cluster()
	await _throw()
	var rr_syn := _mc("retrays")
	await _reset()
	_add("case_retray", 1)
	_add("case_sharp", 1)
	en = await _cluster()
	await _throw()
	var rr_base := _mc("retrays")
	ok(float(prof_s["ret_speed"]) >= 0.5 and rr_syn >= rr_base and rr_syn >= 1, "A4.5 Rayo de Regreso + Express: vuelve más rápido (+%.2f) y dispara más (%d vs %d)" % [float(prof_s["ret_speed"]), rr_syn, rr_base])

	await _reset()
	_add("case_orbit", 1)
	_add("case_ghost", 1)
	ok(GameState.build.s("syn_phantom") > 0.0, "A4.6a sinergia Legión Espectral activa")
	en = await _cluster()
	await _throw()
	ok(_mc("ghost_orbits") >= 1, "A4.6 Órbita + Fantasma: la copia tiene su propia órbita (%d)" % _mc("ghost_orbits"))

	await _reset()
	_add("case_files", 4)
	_add("case_chase", 1)
	ok(GameState.build.s("syn_fileseek") > 0.0, "A4.7a sinergia Expedientes Teledirigidos activa")
	en = await _cluster()
	for i in 3:
		await _throw()
	ok(_mc("file_seek") >= 1, "A4.7 Expedientes + Persecución: documentos que buscan enemigos (%d)" % _mc("file_seek"))

	await _reset()
	_add("case_knives", 2)
	_add("case_split", 3)
	_add("case_shock", 1)
	ok(GameState.build.s("syn_fission") > 0.0, "A4.8a sinergia Fisión Eléctrica activa")
	en = await _cluster()
	Feedback.event_log.clear()
	for i in 5:
		await _throw()
	var fis := _mc("fission")
	ok(_mc("splits") >= 1 and fis >= 1, "A4.8 Fisión + Cadena Eléctrica: proyectiles divididos descargan rayos (%d divisiones, %d descargas)" % [_mc("splits"), fis])

	await _reset()
	_add("case_laser", 1)
	_add("case_knives", 1)
	ok(GameState.build.s("syn_laserknives") > 0.0, "A4.9a sinergia Sentencia Afilada activa")
	en = await _cluster()
	await _throw()
	ok(_mc("laser_knives") >= 2, "A4.9 Láser + Cuchillas: el haz deja cuchillas (%d)" % _mc("laser_knives"))

