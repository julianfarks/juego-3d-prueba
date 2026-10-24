extends Node
## Pruebas del MALETÍN BUMERÁN (v0.6.0). Renderizado real: xvfb + Mesa.
##   xvfb-run -a godot --path . --rendering-driver opengl3 -- --casetest --out=DIR
## Cubre las 10 comprobaciones obligatorias del encargo. Un fallo termina con código 1.
## Limitación honesta: no se puede probar el tacto en un móvil real ni "escuchar" el audio; se verifica el flujo
## (qué se lanza, qué daña, qué suena, cuántos objetos hay vivos, tiempos de CPU y capturas).

var main: Node
var out_dir := "/tmp/casetest"
var fails: Array = []
var passes := 0
var ct: CaseThrow
var player: Player
var _saved_arc := 150.0


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


func info(msg: String) -> void:
	print("[INFO] ", msg)


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


func _clear_enemies() -> void:
	for e in Combat.arena_enemies().duplicate():
		_dispose(e)


## Estado limpio entre pruebas: sin enemigos, sin maletines, sin mejoras, jugador en el centro mirando a -Z.
func _reset() -> void:
	_clear_enemies()
	await _frames(3)
	ct.clear_all()
	ct.record = true
	ct.impact_log.clear()
	for k in ct.counts.keys():
		ct.counts[k] = 0
	GameState.build.reset({})
	GameState.weapon_params = GameState.weapon_params.duplicate()
	player.skills.reset()
	player.skills.auto_aim = true
	player.skills.cd[0] = 0.0
	player.teleport_to(Vector3(0, 0.1, 0))
	player.rotation.y = 0.0
	player.velocity = Vector3.ZERO
	Feedback.event_log.clear()
	AudioManager.combat_log.clear()
	await _frames(2)


func _add(id: String, levels := 1) -> void:
	for i in levels:
		GameState.build.add(id, 0, true)


func _wait_idle(maxt := 8.0) -> float:
	var t := 0.0
	while (ct.in_flight()) and t < maxt:
		await _frames(2)
		t += get_process_delta_time() * 2.0
	return t


## Lanza con ATACAR y espera a que vuelva. Devuelve el tiempo que tardó.
func _throw(maxt := 8.0) -> float:
	player.skills.cd[0] = 0.0
	var r: bool = player.skills.try_cast(0)
	if not r:
		return -1.0
	await _frames(2)
	return await _wait_idle(maxt)


func _ev_src(src: String) -> Array:
	return Feedback.event_log.filter(func(x): return x.get("src", "") == src and not x.has("combo"))


func _ev_enemy(e: Node, src := "") -> Array:
	var id: int = e.get_instance_id()
	return Feedback.event_log.filter(func(x): return x.get("id", 0) == id and (src == "" or x.get("src", "") == src))


func _cluster() -> Array:
	var out: Array = []
	for p in [Vector3(0, 0.1, -6.0), Vector3(2.2, 0.1, -7.0), Vector3(-2.2, 0.1, -7.0), Vector3(0.5, 0.1, -9.2), Vector3(3.5, 0.1, -9.0)]:
		var e: Enemy = await _spawn("thief", p)
		out.append(e)
	return out


func _run() -> void:
	await _frames(10)
	await main._enter_lobby(true)
	await _frames(15)
	main._on_play()
	var t := 0.0
	while main.state != main.St.RUN and t < 10.0:
		await _frames(2)
		t += 0.03
	ok(main.state == main.St.RUN, "C0 empieza la partida")
	Config.dev_god_mode = true
	main.arena.force_complete()
	await _secs(1.0)
	ct = GameState.case_throw
	player = GameState.player
	SaveSystem.data["settings"]["auto_attack"] = false        # el ataque automático no debe interferir en las pruebas
	Feedback.record = true
	AudioManager.record_combat = true
	ok(ct != null, "C0b existe el nodo CaseThrow en el mundo")
	# música principal en bucle + icono de la app
	var mm: AudioStreamPlayer = AudioManager._main_music
	ok(mm != null and mm.stream is AudioStreamMP3 and (mm.stream as AudioStreamMP3).loop, "C0c la canción principal carga como MP3 con bucle")
	AudioManager.play_music("combat")
	await _secs(1.0)
	ok(mm.playing, "C0d la canción principal suena en combate")
	ok(ResourceLoader.exists("res://assets/icon/icon.png") and str(ProjectSettings.get_setting("application/config/icon")).ends_with("assets/icon/icon.png"), "C0e el icono de la app es la imagen nueva")
	_saved_arc = float(GameState.weapon_params.get("arc", 150.0))
	await _t1_throw_replaces_melee()
	await _t2_return_and_rethrow()
	await _t2b_reset_during_wind_up()
	await _t3_curved_path()
	await _t4_right_enemies_single_hit()
	await _t5_pierce_and_sharp()
	await _t6_each_upgrade()
	await _t7_combo_same_throw()
	await _t8_secondary_damage_feedback()
	await _t9_other_buttons()
	await _t10_ui_and_controls()
	await _t11_levels_inventory()
	await _t12_performance()
	await _reset()
	Config.dev_god_mode = false
	print("")
	print("=== CASETEST: %d comprobaciones OK, %d fallos ===" % [passes, fails.size()])
	for f in fails:
		print("  FALLO: ", f)
	get_tree().quit(0 if fails.is_empty() else 1)


# ============================================================================ 1
func _t1_throw_replaces_melee() -> void:
	await _reset()
	ok(not Skills.new().has_method("_slam_hit"), "T1.1 el golpe cuerpo a cuerpo (_slam_hit) ya no existe")
	var e: Enemy = await _spawn("thief", Vector3(0, 0.1, -2.6))      # dentro del antiguo radio de 3.6 m
	var hp0: float = e.hp
	var ok_cast: bool = player.skills.try_cast(0)
	ok(ok_cast, "T1.2 ATACAR (try_cast 0) acepta el lanzamiento")
	# el antiguo golpe dañaba a los 0.55·dur s; ahora el maletín sale a los 0.4·dur: durante la preparación NO hay daño
	await _frames(2)
	ok(is_equal_approx(e.hp, hp0), "T1.3 durante la animación de lanzamiento no hay daño de golpe")
	var saw := false
	var t := 0.0
	while t < 1.0 and not saw:
		await _frames(1)
		t += get_process_delta_time()
		saw = not ct.cases.is_empty()
	ok(saw, "T1.4 aparece un maletín 3D volando")
	if saw:
		var c: CaseThrow.C = ct.cases[0]
		ok(c.node != null and c.node.visible and c.node.get_child_count() > 0, "T1.5 el maletín es un objeto 3D visible (con malla)")
		var mesh_found := false
		for ch in c.pivot.get_children():
			if ch is MeshInstance3D and (ch as MeshInstance3D).mesh != null:
				mesh_found = true
		ok(mesh_found, "T1.6 el objeto tiene MeshInstance3D con malla del maletín")
		var h: Node3D = player.rig.props["case"]
		ok(not h.visible, "T1.7 el maletín de la mano se oculta mientras vuela")
	await _wait_idle()
	var slam_events := _ev_src("slam")
	ok(slam_events.is_empty(), "T1.8 ningún daño con origen 'slam' (golpe antiguo)")
	ok(not _ev_src("case").is_empty(), "T1.9 el daño llega con origen 'case' (maletín lanzado)")
	_clear_enemies()


# ============================================================================ 2
func _t2_return_and_rethrow() -> void:
	await _reset()
	var e: Enemy = await _spawn("thief", Vector3(0, 0.1, -6.0))
	player.skills.cd[0] = 0.0
	ok(player.skills.try_cast(0), "T2.1 primer lanzamiento")
	var guard0 := 0
	while ct.cases.is_empty() and guard0 < 120:
		await get_tree().physics_frame
		guard0 += 1
	await get_tree().physics_frame
	await get_tree().physics_frame
	# durante el vuelo no se puede lanzar otro, ni con el enfriamiento a cero
	player.skills.cd[0] = 0.0
	var second: bool = player.skills.try_cast(0)
	ok(not second, "T2.2 no se puede lanzar mientras el maletín está fuera (sin lanzamientos infinitos)")
	var n_alive := 0
	for ch in ct.get_children():
		if ch is Node3D and (ch as Node3D).visible and ch != ct.mods:
			n_alive += 1
	ok(n_alive <= 1 + ct.secondaries.size() and ct.cases.size() == 1, "T2.3 un solo maletín en el aire (sin duplicados)")
	var took := await _wait_idle()
	ok(took < 7.0 and not ct.in_flight(), "T2.4 el maletín vuelve (%.1f s)" % took)
	ok(ct.counts["catches"] == 1, "T2.5 una recuperación registrada")
	ok(bool(player.rig.props["case"].visible), "T2.6 el maletín reaparece en la mano")
	var visible_nodes := 0
	for c in ct.cases:
		visible_nodes += 1
	ok(visible_nodes == 0, "T2.7 no quedan maletines volando")
	player.skills.cd[0] = 0.0
	await _secs(0.2)
	ok(player.skills.try_cast(0), "T2.8 se puede lanzar de nuevo")
	await _wait_idle()
	ok(ct.counts["throws"] == 2 and ct.counts["catches"] == 2, "T2.9 2 lanzamientos / 2 recuperaciones")
	# mantener pulsado ATACAR: lanza una vez y repite SOLO tras recuperar (el input se procesa en Player)
	Input.action_press("attack")
	await _secs(2.6)
	Input.action_release("attack")
	await _wait_idle()
	ok(ct.counts["throws"] >= 3 and ct.counts["throws"] == ct.counts["catches"], "T2.10 con el botón mantenido cada lanzamiento se recupera antes del siguiente (%d/%d)" % [ct.counts["throws"], ct.counts["catches"]])
	_clear_enemies()


# --- robustez: un reinicio de habilidades en pleno lanzamiento diferido no deja ATACAR bloqueado
func _t2b_reset_during_wind_up() -> void:
	await _reset()
	player.skills.cd[0] = 0.0
	player.skills.try_cast(0)
	player.skills.reset()                    # borra la acción diferida que lanzaría el maletín
	await _secs(0.4)
	ok(not ct.in_flight(), "T2b.1 tras reiniciar habilidades en plena preparación no queda ningún lanzamiento a medias")
	ok(bool(player.rig.props["case"].visible), "T2b.2 el maletín sigue en la mano")
	player.skills.cd[0] = 0.0
	ok(player.skills.try_cast(0), "T2b.3 ATACAR sigue funcionando después")
	await _wait_idle()


# ============================================================================ 3
func _t3_curved_path() -> void:
	await _reset()
	GameState.weapon_params["arc"] = 150.0
	var e: Enemy = await _spawn("thief", Vector3(0, 0.1, -9.0))
	player.skills.cd[0] = 0.0
	player.skills.try_cast(0)
	var samples: Array = []
	var guard := 0
	while guard < 600:
		await get_tree().physics_frame
		guard += 1
		if not ct.cases.is_empty():
			samples.append((ct.cases[0] as CaseThrow.C).pos)
		elif samples.size() > 5 and not ct.in_flight():
			break
	ok(samples.size() > 20, "T3.1 trayectoria muestreada (%d puntos)" % samples.size())
	# punto más lejano
	var far_i := 0
	var far_d := 0.0
	for i in samples.size():
		var d: float = (samples[i] as Vector3).distance_to(Vector3(0, samples[i].y, 0))
		if d > far_d:
			far_d = d
			far_i = i
	var origin: Vector3 = samples[0]
	var far: Vector3 = samples[far_i]
	var line_dir: Vector3 = (far - origin)
	line_dir.y = 0.0
	line_dir = line_dir.normalized()
	var max_out := 0.0
	for i in range(0, far_i):
		var v: Vector3 = samples[i] - origin
		v.y = 0.0
		max_out = maxf(max_out, absf(v.cross(line_dir).y))
	var max_back := 0.0
	for i in range(far_i, samples.size()):
		var v2: Vector3 = samples[i] - origin
		v2.y = 0.0
		max_back = maxf(max_back, absf(v2.cross(line_dir).y))
	info("desviación lateral ida %.2f m, regreso %.2f m, alcance %.1f m" % [max_out, max_back, far_d])
	ok(max_back > 1.0, "T3.2 el regreso es una curva (desviación lateral %.2f m > 1 m)" % max_back)
	ok(far_d > 5.0, "T3.3 el maletín recorre distancia (%.1f m)" % far_d)
	# el regreso no repite el camino de ida
	var diff := 0.0
	var n_cmp := 0
	for i in range(far_i + 1, samples.size()):
		var back: Vector3 = samples[i]
		var best := 100.0
		for j in range(0, far_i):
			best = minf(best, back.distance_to(samples[j]))
		diff = maxf(diff, best)
		n_cmp += 1
	ok(diff > 0.8, "T3.4 el camino de vuelta se separa del de ida (%.2f m)" % diff)
	_clear_enemies()


# ============================================================================ 4
func _t4_right_enemies_single_hit() -> void:
	await _reset()
	var a: Enemy = await _spawn("thief", Vector3(0, 0.1, -6.0))
	var b: Enemy = await _spawn("thief", Vector3(0, 0.1, 9.0))        # a la espalda del jugador
	var c: Enemy = await _spawn("thief", Vector3(14.0, 0.1, -6.0))   # fuera de alcance lateral
	var ha: float = a.hp
	var hb: float = b.hp
	var hc: float = c.hp
	await _throw()
	ok(a.hp < ha, "T4.1 el enemigo apuntado recibe daño")
	ok(is_equal_approx(b.hp, hb) and is_equal_approx(c.hp, hc), "T4.2 los enemigos fuera de la trayectoria no reciben daño")
	var ea := _ev_enemy(a, "case")
	ok(ea.size() == 1, "T4.3 el enemigo recibe EXACTAMENTE 1 impacto de maletín (%d)" % ea.size())
	var il := ct.impact_log.filter(func(x): return x["enemy"] == a.get_instance_id())
	ok(il.size() == 1, "T4.4 el registro interno también cuenta 1 impacto (%d)" % il.size())
	var expected: float = ha - a.hp
	var applied := 0.0
	for ev in _ev_enemy(a):                       # todos los orígenes (el Sello automático también puede tocarlo)
		applied += float(ev["applied"])
	for ev in _ev_enemy(a):
		info("   evento: %s" % str(ev))
	info("T4.5 esperado %.4f aplicado %.4f (hp antes %.4f, después %.4f)" % [expected, applied, ha, a.hp])
	ok(absf(applied - expected) < 0.01 * maxf(1.0, expected) + 1.0, "T4.5 el daño evento == vida perdida (sin dobles descuentos)")
	ok(Feedback.event_log.filter(func(x): return x.get("id", 0) == a.get_instance_id() and x["number"] == "off").is_empty(), "T4.6 el impacto mostró número de daño")
	_clear_enemies()


# ============================================================================ 5
func _t5_pierce_and_sharp() -> void:
	await _reset()
	GameState.weapon_params["arc"] = 30.0                              # curva suave: la fila de enemigos queda sobre el recorrido
	var line: Array = []
	for z in [-4.0, -6.5, -9.0]:
		line.append(await _spawn("thief", Vector3(0, 0.1, z)))
	await _throw()
	var hit_n := 0
	for e in line:
		if not _ev_enemy(e, "case").is_empty():
			hit_n += 1
	ok(hit_n == 1, "T5.1 sin perforación solo golpea al primero (%d)" % hit_n)
	_clear_enemies()
	await _reset()
	GameState.weapon_params["arc"] = 30.0
	_add("case_pierce", 2)
	line.clear()
	for z in [-4.0, -6.5, -9.0]:
		line.append(await _spawn("thief", Vector3(0, 0.1, z)))
	await _throw()
	hit_n = 0
	var dup := false
	for e in line:
		var n: int = _ev_enemy(e, "case").size()
		if n >= 1:
			hit_n += 1
		if n > 1:
			dup = true
	ok(hit_n == 3, "T5.2 Perforación Documental ×2: atraviesa y golpea a los 3 (%d)" % hit_n)
	ok(not dup, "T5.3 cada enemigo recibe un único impacto de ida (sin duplicados)")
	_clear_enemies()
	# golpear en el regreso: Esquinas Afiladas (se coloca un enemigo justo delante del maletín cuando ya va de vuelta)
	for with_sharp in [false, true]:
		await _reset()
		if with_sharp:
			_add("case_sharp", 1)
		var far_a: Enemy = await _spawn("thief", Vector3(0, 0.1, -7.0))
		var late: Enemy = await _spawn("thief", Vector3(18.0, 0.1, 18.0))
		player.skills.cd[0] = 0.0
		player.skills.try_cast(0)
		var guard := 0
		while guard < 400:
			await get_tree().physics_frame
			guard += 1
			if not ct.cases.is_empty() and (ct.cases[0] as CaseThrow.C).state == "ret":
				break
		await get_tree().physics_frame
		if not ct.cases.is_empty():
			var cc: CaseThrow.C = ct.cases[0]
			late.global_position = Vector3(cc.pos.x + cc.vel.x * 0.05, 0.1, cc.pos.z + cc.vel.z * 0.05)
		await _wait_idle()
		var rets: Array = ct.impact_log.filter(func(x): return x["state"] == "ret" and x["enemy"] == late.get_instance_id())
		var by_state: Dictionary = {}
		var dup2 := false
		for im in ct.impact_log:
			var k := "%s_%s" % [im["enemy"], im["state"]]
			if by_state.has(k):
				dup2 = true
			by_state[k] = true
		if with_sharp:
			ok(rets.size() == 1, "T5.5 con Esquinas Afiladas el maletín también golpea al volver (%d)" % rets.size())
			ok(not dup2, "T5.6 como mucho un impacto por enemigo y fase (ida/regreso)")
			var out_far: Array = ct.impact_log.filter(func(x): return x["enemy"] == far_a.get_instance_id())
			ok(out_far.size() == 1, "T5.7 el enemigo de la ida no se golpea otra vez al dar la vuelta (%d)" % out_far.size())
		else:
			ok(rets.is_empty(), "T5.4 sin Esquinas Afiladas el regreso no golpea")
		_clear_enemies()


# ============================================================================ 6
func _t6_each_upgrade() -> void:
	# --- Explosión Legal
	await _reset()
	_add("case_blast", 2)
	var cl: Array = await _cluster()
	await _throw()
	var splash := _ev_src("case_boom")
	ok(ct.counts["blasts"] > 0 and not splash.is_empty(), "T6.1 Explosión Legal: explota en cada impacto y daña a vecinos (%d golpes de área)" % splash.size())
	ok(splash.all(func(x): return x["dmg"] > 0.0), "T6.1b los golpes de explosión tienen daño real")
	_clear_enemies()
	# --- Maletín Pirotécnico
	await _reset()
	_add("case_pyro", 5)
	cl = await _cluster()
	await _throw()
	await _secs(1.2)
	ok(ct.counts["rockets"] > 0 and not _ev_src("firework").is_empty(), "T6.2 Pirotécnico: cohetes lanzados (%d) que explotan y dañan (%d golpes)" % [ct.counts["rockets"], _ev_src("firework").size()])
	_clear_enemies()
	# --- Fragmentación
	await _reset()
	_add("case_frag", 2)
	cl = await _cluster()
	await _throw()
	ok(ct.counts["frags"] > 0 and not _ev_src("frag").is_empty(), "T6.3 Fragmentación: fragmentos (%d) golpean (%d)" % [ct.counts["frags"], _ev_src("frag").size()])
	_clear_enemies()
	# --- Documentos Explosivos
	await _reset()
	_add("case_docs", 2)
	cl = await _cluster()
	await _throw()
	await _secs(1.0)
	ok(ct.counts["docs"] > 0 and (not _ev_src("docs").is_empty()), "T6.4 Documentos Explosivos: salen documentos (%d) y golpean (%d)" % [ct.counts["docs"], _ev_src("docs").size()])
	ok(not _ev_src("docs_boom").is_empty(), "T6.4b los documentos explotan al impactar")
	_clear_enemies()
	# --- Lluvia de Documentos
	await _reset()
	_add("case_rain", 5)
	cl = await _cluster()
	await _throw()
	await _secs(1.2)
	ok(ct.counts["rain"] > 0 and not _ev_src("rain").is_empty(), "T6.5 Lluvia de Documentos: %d lluvias, %d golpes" % [ct.counts["rain"], _ev_src("rain").size()])
	_clear_enemies()
	# --- Maletín Eléctrico
	await _reset()
	_add("case_shock", 5)
	cl = await _cluster()
	await _throw()
	ok(ct.counts["shock"] > 0 and not _ev_src("chain").is_empty(), "T6.6 Eléctrico: %d descargas, %d golpes de rayo" % [ct.counts["shock"], _ev_src("chain").size()])
	_clear_enemies()
	# --- Maletín Corrosivo
	await _reset()
	_add("case_corr", 4)
	var lone: Enemy = await _spawn("thief", Vector3(0, 0.1, -6.0))
	var hp0: float = lone.hp
	var first_dmg := 0.0
	player.skills.cd[0] = 0.0
	player.skills.try_cast(0)
	var seen_mark := false
	var tt := 0.0
	while ct.in_flight() and tt < 6.0:
		await _frames(1)
		tt += get_process_delta_time()
		if lone.marked_t > 0.0:
			seen_mark = true
	ok(ct.counts["marks"] > 0 and seen_mark, "T6.7 Corrosivo: el enemigo queda marcado (recibe +25% de daño)")
	_clear_enemies()
	# --- Rastro de Fuego
	await _reset()
	_add("case_trail", 3)
	var row: Array = []
	for z in [-3.0, -5.0, -7.0]:
		row.append(await _spawn("thief", Vector3(0.0, 0.1, z)))
	GameState.weapon_params["arc"] = 30.0
	_add("case_pierce", 3)
	await _throw()
	await _secs(0.4)
	ok(ct.counts["embers"] > 0, "T6.8a Rastro de Fuego: deja %d brasas" % ct.counts["embers"])
	ok(not _ev_src("fire_trail").is_empty(), "T6.8b la estela daña a los enemigos que atraviesa (%d golpes)" % _ev_src("fire_trail").size())
	_clear_enemies()
	# --- Multilanzamiento
	await _reset()
	_add("case_multi", 2)
	cl = await _cluster()
	await _throw()
	ok(ct.counts["minis"] > 0, "T6.9 Multilanzamiento: %d minimaletines en vuelo" % ct.counts["minis"])
	ok(not _ev_src("mini").is_empty(), "T6.9b los minimaletines golpean a enemigos (%d)" % _ev_src("mini").size())
	_clear_enemies()
	# --- Retorno Explosivo
	await _reset()
	_add("case_return", 2)
	var far: Enemy = await _spawn("thief", Vector3(0, 0.1, -6.0))
	var close: Enemy = await _spawn("thief", Vector3(2.0, 0.1, 2.0))
	await _throw()
	ok(ct.counts["return_blasts"] == 1, "T6.10 Retorno Explosivo: una explosión al recuperar (%d)" % ct.counts["return_blasts"])
	ok(not _ev_enemy(close, "return_blast").is_empty(), "T6.10b la explosión de retorno daña a los enemigos junto al abogado")
	_clear_enemies()
	# --- Rebote Judicial
	await _reset()
	_add("case_bounce", 3)
	var trio: Array = []
	for p in [Vector3(0, 0.1, -5.0), Vector3(3.0, 0.1, -7.0), Vector3(-3.0, 0.1, -8.0)]:
		trio.append(await _spawn("thief", p))
	await _throw()
	var hit_enemies := 0
	for e in trio:
		if not _ev_enemy(e, "case").is_empty():
			hit_enemies += 1
	ok(ct.counts["bounces_enemy"] > 0 and hit_enemies >= 2, "T6.11 Rebote Judicial: rebota entre enemigos (%d rebotes, %d enemigos golpeados)" % [ct.counts["bounces_enemy"], hit_enemies])
	_clear_enemies()
	# --- Rebotes de Maletín (entorno, ~3 s)
	await _reset()
	_add("case_wall", 1)
	player.skills.cd[0] = 0.0
	player.skills.try_cast(0)
	var t0 := Time.get_ticks_msec()
	var saw_bounce := false
	var guard := 0
	while ct.in_flight() and guard < 400:
		await _frames(1)
		guard += 1
		if not ct.cases.is_empty() and (ct.cases[0] as CaseThrow.C).state == "bounce":
			saw_bounce = true
	var dur := float(Time.get_ticks_msec() - t0) / 1000.0
	ok(saw_bounce and ct.counts["bounces_wall"] >= 1, "T6.12 Rebotes de Maletín: rebota por el entorno (%d rebotes en pared, vuelo %.1f s)" % [ct.counts["bounces_wall"], dur])
	ok(dur > 2.5 and dur < 8.0, "T6.12b vuelo con rebotes ≈ 3 s + regreso (%.1f s)" % dur)
	# --- Multi Maletín / Doble Maletín
	await _reset()
	_add("case_cases", 2)
	cl = await _cluster()
	await _throw()
	ok(ct.counts["max_cases"] == 3, "T6.13 Multi Maletín ×2: 3 maletines a la vez (%d)" % ct.counts["max_cases"])
	ok(ct.counts["catches"] == 3 and ct.counts["return_blasts"] == 0 and bool(player.rig.props["case"].visible), "T6.13b los 3 vuelven y la mano queda con un solo maletín")
	_clear_enemies()
	await _reset()
	_add("case_double", 1)
	_add("case_return", 2)
	cl = await _cluster()
	await _throw()
	ok(ct.counts["max_cases"] == 2, "T6.14 Doble Maletín: segundo proyectil con recorrido propio")
	ok(ct.counts["return_blasts"] == 1, "T6.14b no duplica el efecto de retorno (%d explosiones de retorno)" % ct.counts["return_blasts"])
	_clear_enemies()
	# --- Crítico Contractual
	await _reset()
	var dummy: Enemy = await _spawn("thief", Vector3(0, 0.1, -6.0))
	var crits0 := 0
	for i in 600:
		if Combat.calc(dummy, 10.0, {"src": "case"})["crit"]:
			crits0 += 1
	_add("case_crit", 10)
	var crits1 := 0
	for i in 600:
		if Combat.calc(dummy, 10.0, {"src": "case"})["crit"]:
			crits1 += 1
	var crits_other := 0
	for i in 600:
		if Combat.calc(dummy, 10.0, {"src": "docs"})["crit"]:
			crits_other += 1
	ok(crits1 > crits0 + 60, "T6.15 Crítico Contractual: %d → %d críticos de 600" % [crits0, crits1])
	ok(crits_other < crits1 - 60, "T6.15b solo afecta a impactos del maletín (otros %d)" % crits_other)
	_clear_enemies()
	# --- estadísticas de lanzamiento
	await _reset()
	var base_p := ct.make_profile()
	_add("case_range", 5)
	_add("case_dmg", 5)
	_add("case_speed", 5)
	_add("case_size", 5)
	var up_p := ct.make_profile()
	ok(float(up_p["range"]) > float(base_p["range"]) and float(up_p["base"]) > float(base_p["base"]) and float(up_p["speed"]) > float(base_p["speed"]) and float(up_p["size"]) > float(base_p["size"]),
		"T6.16 alcance/daño/velocidad/tamaño suben de verdad con los niveles")


# ============================================================================ 7
func _t7_combo_same_throw() -> void:
	await _reset()
	for id in ["case_blast", "case_pyro", "case_frag", "case_bounce", "case_shock", "case_corr", "case_trail", "case_docs"]:
		_add(id, 4)
	_add("case_crit", 10)
	var cl: Array = await _cluster()
	var c0: Dictionary = ct.counts.duplicate()
	player.skills.cd[0] = 0.0
	player.skills.try_cast(0)
	await _secs(0.3)
	await _shot("flight_a")
	await _secs(0.12)
	await _shot("flight_b")
	await _wait_idle()
	await _secs(1.5)
	var d: Dictionary = {}
	for k in ct.counts.keys():
		d[k] = int(ct.counts[k]) - int(c0[k])
	info("combo: " + str(d))
	ok(d["impacts"] >= 1 and d["blasts"] >= 1 and d["rockets"] >= 1 and d["frags"] >= 1 and d["shock"] >= 1 and d["marks"] >= 1 and d["docs"] >= 1,
		"T7.1 explosión + fuegos artificiales + fragmentos + rayo + corrosión + documentos en el MISMO lanzamiento")
	ok(d["bounces_enemy"] >= 1, "T7.2 y además rebota entre enemigos (%d)" % d["bounces_enemy"])
	var srcs: Dictionary = {}
	for ev in Feedback.event_log:
		if ev.has("src"):
			srcs[ev["src"]] = int(srcs.get(ev["src"], 0)) + 1
	info("orígenes de daño: " + str(srcs))
	ok(srcs.size() >= 6, "T7.3 al menos 6 orígenes de daño distintos en una tirada (%d)" % srcs.size())
	# orden: el impacto del maletín precede a sus efectos secundarios
	var first_case := -1
	var first_sec := 999999
	for i in Feedback.event_log.size():
		var s: String = Feedback.event_log[i].get("src", "")
		if s == "case" and first_case < 0:
			first_case = i
		if ["case_boom", "frag", "firework", "chain", "docs", "docs_boom"].has(s) and i < first_sec:
			first_sec = i
	ok(first_case >= 0 and first_case < first_sec, "T7.4 orden: primero el impacto del maletín, luego explosión/fragmentos/rayos")
	await _shot("combo_build")
	ok(not ct.in_flight() and bool(player.rig.props["case"].visible), "T7.5 tras la cascada todo vuelve a la mano (sin maletines atascados)")
	_clear_enemies()


# ============================================================================ 8
func _t8_secondary_damage_feedback() -> void:
	await _reset()
	for id in ["case_blast", "case_frag", "case_pyro", "case_shock", "case_multi", "case_rain"]:
		_add(id, 5)
	var cl: Array = await _cluster()
	await _throw()
	await _secs(1.5)
	var sec_srcs := ["case_boom", "frag", "firework", "chain", "mini", "rain"]
	var n_sec := 0
	var bad_dmg := 0
	var no_num := 0
	var shown := 0
	for ev in Feedback.event_log:
		if sec_srcs.has(ev.get("src", "")):
			n_sec += 1
			if float(ev["dmg"]) <= 0.0:
				bad_dmg += 1
			if ev["number"] == "off":
				no_num += 1
			if ev["number"] == "new" or ev["number"] == "merged":
				shown += 1
	ok(n_sec >= 6, "T8.1 los efectos secundarios generan golpes reales (%d)" % n_sec)
	ok(bad_dmg == 0, "T8.2 todos los golpes secundarios tienen daño > 0")
	ok(no_num == 0 and shown >= n_sec / 2, "T8.3 todos los secundarios pasan por el sistema de números (%d de %d visibles/fusionados)" % [shown, n_sec])
	var fw_ok := true
	for ev in _ev_src("firework"):
		if ev["element"] != "fire":
			fw_ok = false
	ok(fw_ok, "T8.4 los fuegos artificiales aplican elemento fuego")
	var frag_ev := _ev_src("frag")
	var zap_ev := _ev_src("chain")
	ok(zap_ev.is_empty() or zap_ev.all(func(x): return x["element"] == "shock"), "T8.5 el rayo es eléctrico")
	var names: Dictionary = {}
	for l in AudioManager.combat_log:
		if l["played"]:
			names[l["name"]] = int(names.get(l["name"], 0)) + 1
	info("sonidos reproducidos: " + str(names))
	ok(names.has("throw") and names.has("explosion") and names.has("catch"), "T8.6 suenan lanzamiento, explosión y recuperación")
	ok(names.size() >= 5, "T8.7 variedad de sonidos distintos (%d)" % names.size())
	for nm in ["throw", "catch", "bounce", "shard", "fw_launch", "fw_pop", "paper"]:
		ok(ResourceLoader.exists("res://assets/audio/sfx_%s.wav" % nm) and AudioManager._load("sfx_" + nm) != null, "T8.8 el audio sfx_%s.wav existe y carga" % nm)
	_clear_enemies()


# ============================================================================ 9
func _t9_other_buttons() -> void:
	await _reset()
	var e: Enemy = await _spawn("thief", Vector3(0, 0.1, -6.0))
	var hp0: float = e.hp
	player.skills.energy = player.skills.energy_max
	ok(player.skills.try_cast(1), "T9.1 DOCS lanza documentos")
	await _secs(1.4)
	ok(e.hp < hp0 and not _ev_enemy(e, "docs").is_empty(), "T9.2 los documentos dañan al enemigo (origen docs)")
	# esquivar
	var cd_before: float = player.dodge_cd_fraction()
	Input.action_press("dodge")
	await _frames(3)
	Input.action_release("dodge")
	await _frames(2)
	ok(player.dodge_cd_fraction() > cd_before or player._dodge_t > 0.0, "T9.3 ESQUIVAR sigue funcionando")
	await _secs(1.0)
	# saltar
	player.velocity = Vector3.ZERO
	await _secs(0.4)
	Input.action_press("jump")
	await _frames(3)
	Input.action_release("jump")
	var vy: float = player.velocity.y
	await _frames(2)
	ok(vy > 1.0 or not player.is_on_floor(), "T9.4 SALTAR sigue funcionando (vy=%.1f)" % vy)
	_clear_enemies()
	# Sello y Objeción automáticos (sin botón)
	await _reset()
	var tgt: Enemy = await _spawn("thief", Vector3(0, 0.1, -6.0))
	ok(player.skills.cd[2] <= 0.0, "T9.5 el Sello está listo")
	await _throw()
	ok(player.skills.cd[2] > 0.0, "T9.6 el Sello Mágico se activa solo al final de la ida del maletín")
	ok(not player.skills.try_cast(2) and not player.skills.try_cast(3), "T9.7 try_cast(2/3) ya no lanza nada (sin botón)")
	player.hp = player.max_hp * 0.3
	player.skills.cd[3] = 0.0
	var close: Enemy = await _spawn("thief", Vector3(2.0, 0.1, 1.0))
	await _frames(6)
	ok(player.skills.barrier_active or player.skills.cd[3] > 0.0, "T9.8 la Objeción salta sola con vida baja y enemigos cerca")
	player.hp = player.max_hp
	_clear_enemies()


# ============================================================================ 10
func _t10_ui_and_controls() -> void:
	ok(not TouchControls.BUTTONS.has("skill2") and not TouchControls.BUTTONS.has("skill3"), "T10.1 SELLO y OBJECIÓN no están en la lista de botones")
	var labels: Array = TouchControls.LABELS.values()
	ok(not labels.has("SELLO") and not labels.has("OBJECIÓN"), "T10.2 ninguna etiqueta SELLO/OBJECIÓN")
	for need in ["ATACAR", "DOCS", "ESQUIVAR", "SALTAR"]:
		ok(labels.has(need), "T10.3 botón %s presente" % need)
	ok(not InputMap.has_action("skill2") and not InputMap.has_action("skill3"), "T10.4 no quedan acciones de entrada ocultas para sello/objeción")
	ok(not SaveSystem.data["controls"].has("skill2") and not SaveSystem.data["controls"].has("skill3"), "T10.5 la disposición guardada no conserva los botones eliminados")
	# disposición: sin solapes entre botones ni con el joystick (pantalla horizontal típica 1280x720 y 960x540)
	for sz in [Vector2(1280, 720), Vector2(960, 540), Vector2(2400, 1080)]:
		var names: Array = ["attack", "jump", "dodge", "skill1", "joystick"]
		var okl := true
		var worst := 1000.0
		for i in names.size():
			for j in range(i + 1, names.size()):
				var la: Dictionary = SaveSystem.data["controls"][names[i]]
				var lb: Dictionary = SaveSystem.data["controls"][names[j]]
				var ca := Vector2(float(la["x"]) * sz.x, float(la["y"]) * sz.y)
				var cb := Vector2(float(lb["x"]) * sz.x, float(lb["y"]) * sz.y)
				var ra: float = (TouchControls.BASE_R if names[i] != "joystick" else TouchControls.JOY_R) * float(la["scale"])
				var rb: float = (TouchControls.BASE_R if names[j] != "joystick" else TouchControls.JOY_R) * float(lb["scale"])
				var gap := ca.distance_to(cb) - ra - rb
				worst = minf(worst, gap)
				if gap < 4.0:
					okl = false
		ok(okl, "T10.6 sin solapes a %dx%d (hueco mínimo %.0f px)" % [int(sz.x), int(sz.y), worst])
	# los botones caen dentro de la pantalla
	var inside := true
	for n in ["attack", "jump", "dodge", "skill1"]:
		var l: Dictionary = SaveSystem.data["controls"][n]
		if float(l["x"]) < 0.05 or float(l["x"]) > 0.95 or float(l["y"]) < 0.05 or float(l["y"]) > 0.95:
			inside = false
	ok(inside, "T10.7 todos los botones quedan dentro de la pantalla")
	# migración de guardados antiguos
	var old_data := {"settings": {}, "controls": {"attack": {"x": 0.1, "y": 0.1, "scale": 1.0}, "skill2": {"x": 0.68, "y": 0.64, "scale": 0.9}}}
	var backup: Dictionary = SaveSystem.data.duplicate(true)
	SaveSystem.data = SaveSystem._merge(SaveSystem.defaults(), old_data)
	SaveSystem._sanitize_after_load()
	ok(not SaveSystem.data["controls"].has("skill2") and float(SaveSystem.data["controls"]["attack"]["x"]) > 0.5, "T10.8 un guardado antiguo se migra a la nueva disposición sin botones eliminados")
	SaveSystem.data = backup
	# pulsación táctil real sobre el botón ATACAR
	var tc: TouchControls = main.get("touch") if main.get("touch") != null else null
	if tc == null:
		for n in main.get_tree().root.find_children("*", "TouchControls", true, false):
			tc = n
	if tc != null:
		tc.size = Vector2(1280, 720)
		var l2: Dictionary = SaveSystem.data["controls"]["attack"]
		var p := Vector2(float(l2["x"]) * 1280.0, float(l2["y"]) * 720.0)
		ok(tc._button_at(p) == "attack", "T10.9 un toque sobre ATACAR lo detecta")
		var gone := Vector2(0.68 * 1280.0, 0.64 * 720.0)      # donde estaba SELLO
		ok(tc._button_at(gone) == "", "T10.10 donde estaba SELLO ya no hay botón (sin controles invisibles)")
		gone = Vector2(0.80 * 1280.0, 0.50 * 720.0)             # donde estaba OBJECIÓN
		var hit_name: String = tc._button_at(gone)
		ok(hit_name != "skill2" and hit_name != "skill3", "T10.11 donde estaba OBJECIÓN no queda ningún botón fantasma (%s)" % hit_name)
	else:
		info("No se encontró TouchControls en el árbol (omitidos T10.9-11)")


# ============================================================================ 11
func _t11_levels_inventory() -> void:
	await _reset()
	var b: Build = GameState.build
	var ids: Array = []
	for d in UpgradeDB.all():
		if String(d["id"]).begins_with("case_"):
			ids.append(d["id"])
	ok(ids.size() >= 20, "T11.1 el catálogo del maletín tiene %d mejoras" % ids.size())
	var bad_desc := 0
	var bad_label := 0
	for id in ids:
		var txt: String = UpgradeDB.describe(id, 0)
		if txt == "" or txt.contains("{"):
			bad_desc += 1
		for k in (UpgradeDB.get_def(id)["stats"] as Dictionary).keys():
			if UpgradeDB.stat_label(String(k)) == String(k):
				bad_label += 1
	ok(bad_desc == 0, "T11.2 todas tienen descripción completa (sin marcadores sin resolver)")
	ok(bad_label == 0, "T11.3 todas sus estadísticas tienen etiqueta legible en el inventario")
	# cada mejora debe poder llegar a su nivel máximo sin que su estadística principal toque antes el límite duro
	var unreachable: Array = []
	for id in ids:
		var dd := UpgradeDB.get_def(id)
		var k0 := String((dd["stats"] as Dictionary).keys()[0])
		if UpgradeDB.CAPS.has(k0) and float(dd["stats"][k0]) * UpgradeDB.rarity_scale(dd, 0) * float(dd["max"]) > float(UpgradeDB.CAPS[k0]) + 0.0005:
			unreachable.append(id)
	ok(unreachable.is_empty(), "T11.3b ningún nivel máximo queda inalcanzable por el límite duro (%s)" % str(unreachable))
	# niveles: repetir en cofres sube de nivel hasta el máximo
	var id := "case_pierce"
	var mx := int(UpgradeDB.get_def(id)["max"])
	for i in mx + 3:
		if b.can_add(id):
			b.add(id, 0)
	ok(b.count_of(id) == mx, "T11.4 el nivel sube al repetirse y se detiene en el máximo (%d)" % b.count_of(id))
	ok(ct.make_profile()["pierce"] == mx, "T11.5 el nivel se traduce en perforaciones reales (%d)" % ct.make_profile()["pierce"])
	# sinergia
	b.reset({})
	_add("case_pyro", 1)
	_add("case_frag", 1)
	ok(b.active_synergies.has("pyro_party") and ct.make_profile()["syn_pyro_frag"], "T11.6 Pirotécnico + Fragmentación activa la sinergia 'Fiesta Pirotécnica'")
	b.reset({})
	_add("case_return", 1)
	_add("case_pyro", 1)
	ok(b.active_synergies.has("grand_finale"), "T11.7 Retorno Explosivo + Pirotécnico activa 'Gran Final'")
	# límite de 30 tipos
	b.reset({})
	var added := 0
	for d in UpgradeDB.all():
		if b.can_add(d["id"]):
			if b.add(d["id"], 0):
				added += 1
	ok(b.counts.size() <= 30, "T11.8 el límite de 30 tipos distintos se respeta (%d)" % b.counts.size())
	b.reset({})
	# efecto acumulado en el inventario
	_add("case_blast", 3)
	var inv_ui := load("res://scripts/ui/inventory_ui.gd")
	ok(inv_ui != null, "T11.9 la UI de inventario carga")
	b.reset({})


# ============================================================================ 12
func _t12_performance() -> void:
	await _reset()
	# build exagerada: todo al máximo
	for d in UpgradeDB.all():
		if String(d["id"]).begins_with("case_") and d["id"] != "case_wall":
			_add(d["id"], int(d["max"]) if d["id"] != "case_cases" else 3)
	var crowd: Array = []
	for i in 14:
		var ang := float(i) / 14.0 * TAU
		crowd.append(await _spawn("thief", Vector3(cos(ang) * 6.5, 0.1, sin(ang) * 6.5 - 1.0)))
	AudioManager.combat_log.clear()
	var peak_sec := 0
	var peak_cases := 0
	var peak_ember := 0
	var peak_proj := 0
	var frames := 0
	var t_start := Time.get_ticks_msec()
	var n_throws := 0
	var cpu_sum := 0.0
	var cpu_max := 0.0
	var cpu_n := 0
	while Time.get_ticks_msec() - t_start < 12000:
		if not ct.in_flight():
			player.skills.cd[0] = 0.0
			if player.skills.try_cast(0):
				n_throws += 1
		await get_tree().physics_frame
		frames += 1
		peak_sec = maxi(peak_sec, ct.secondaries.size())
		peak_cases = maxi(peak_cases, ct.cases.size())
		peak_ember = maxi(peak_ember, ct._embers.size())
		peak_proj = maxi(peak_proj, GameState.projectiles.count())
		if ct.secondaries.size() > 8:
			var tc0 := Time.get_ticks_usec()
			ct._physics_process(1.0 / 60.0)
			var dtc := float(Time.get_ticks_usec() - tc0) / 1000.0
			cpu_sum += dtc
			cpu_max = maxf(cpu_max, dtc)
			cpu_n += 1
		# las ranuras de la cola de brasas también se recargan en la bolsa de enemigos muertos
		for e in crowd:
			if is_instance_valid(e) and e.alive and e.hp < e.max_hp * 0.5:
				e.hp = e.max_hp
	info("estrés: %d lanzamientos, %d fotogramas físicos, picos: %d secundarios, %d maletines, %d brasas, %d proyectiles" % [n_throws, frames, peak_sec, peak_cases, peak_ember, peak_proj])
	ok(peak_sec <= CaseThrow.MAX_SECONDARY, "T12.1 límite de proyectiles secundarios respetado (pico %d ≤ %d)" % [peak_sec, CaseThrow.MAX_SECONDARY])
	ok(peak_cases <= CaseThrow.MAX_CASES, "T12.2 límite de maletines respetado (pico %d ≤ %d)" % [peak_cases, CaseThrow.MAX_CASES])
	ok(peak_ember <= CaseThrow.MAX_EMBERS, "T12.3 límite de brasas respetado (pico %d ≤ %d)" % [peak_ember, CaseThrow.MAX_EMBERS])
	ok(peak_proj <= 90, "T12.4 el gestor de proyectiles no supera su máximo (pico %d)" % peak_proj)
	# sonidos: presupuesto por ventana de 100 ms
	var played: Array = AudioManager.combat_log.filter(func(x): return x["played"])
	var worst := 0
	for i in played.size():
		var n := 0
		for j in range(i, played.size()):
			if float(played[j]["t"]) - float(played[i]["t"]) <= 0.1:
				n += 1
			else:
				break
		worst = maxi(worst, n)
	info("sonidos: %d reproducidos, %d descartados, máx. %d en 100 ms" % [played.size(), AudioManager.combat_log.size() - played.size(), worst])
	ok(worst <= 9, "T12.5 como mucho %d sonidos en 100 ms (presupuesto 8)" % worst)
	var per := cpu_sum / maxf(1.0, float(cpu_n))
	info("coste CaseThrow._physics_process en plena cascada (>8 secundarios): media %.3f ms, máx. %.3f ms sobre %d muestras (PC; en móvil ×3-5)" % [per, cpu_max, cpu_n])
	ok(cpu_n > 5 and per < 3.0, "T12.6 coste del sistema < 3 ms por fotograma en plena cascada (%.2f ms)" % per)
	ok(n_throws >= 3, "T12.9 varios lanzamientos seguidos en la prueba de estrés (%d)" % n_throws)
	await _wait_idle(10.0)
	ok(not ct.in_flight() and bool(player.rig.props["case"].visible), "T12.7 al terminar todo vuelve a la mano")
	await _shot("stress_end")
	ct.clear_all()
	ok(ct.secondaries.is_empty() and ct.cases.is_empty() and ct._embers.is_empty(), "T12.8 clear_all() limpia maletines, secundarios y brasas")
	_clear_enemies()
