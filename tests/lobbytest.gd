extends Node
## Prueba con renderizado real de la Sala Central: estaciones, equipamiento, práctica, dificultad,
## portales y persistencia. Dos procesos (--stage=1 y --stage=2) para simular cerrar y reabrir el juego.
##   godot ... -- --lobbytest --stage=1 --out=DIR

var main: Node
var out_dir := "/tmp/lobbytest"
var stage := 1
var fails: Array = []
var passes := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a.begins_with("--stage="):
			stage = int(a.substr(8))
	DirAccess.make_dir_recursive_absolute(out_dir)
	call_deferred("_run")


func ok(cond: bool, name: String) -> void:
	if cond:
		passes += 1
		print("[PASS] ", name)
	else:
		fails.append(name)
		print("[FAIL] ", name)


func _shot(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png("%s/%s.png" % [out_dir, name])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _secs(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _overlay(cls: Variant) -> Node:
	for n in main._ov_root().get_children():
		if is_instance_of(n, cls):
			return n
	return null


func _buttons(root: Node, prefix: String) -> Array:
	var out: Array = []
	for b in root.find_children("*", "Button", true, false):
		if (b as Button).text.begins_with(prefix):
			out.append(b)
	return out


func _wait_state(st: int, timeout := 12.0) -> bool:
	var t := 0.0
	while main.state != st and t < timeout:
		await _secs(0.1)
		t += 0.1
	return main.state == st


func _tp(pos: Vector3, yaw := 0.0) -> void:
	GameState.player.teleport_to(pos)
	main.cam.yaw = yaw
	main.cam.snap_to_target()
	await _secs(0.5)


func _finish() -> void:
	print("[RESULT] sala etapa %d: %d ok, %d fallos" % [stage, passes, fails.size()])
	get_tree().quit(1 if fails.size() > 0 else 0)


func _run() -> void:
	await _frames(10)
	await main._enter_lobby(true)
	await _frames(20)
	if stage == 1:
		await _stage1()
	else:
		await _stage2()
	_finish()


func _station_ui(id: String) -> void:
	var st: Interactable = main.lobby.stations[id]
	GameState.player.teleport_to(st.global_position + Vector3(0.0, 0.0, 0.5))
	await _secs(0.4)
	ok(GameState.player.interact_target == st, "L-estación %s es el objetivo de interacción al acercarse" % id)
	# toque real sobre el botón táctil de interacción
	var c: Vector2 = main.touch._center("interact")
	var down := InputEventScreenTouch.new()
	down.index = 6
	down.position = c
	down.pressed = true
	Input.parse_input_event(down)
	await _frames(4)
	var up := InputEventScreenTouch.new()
	up.index = 6
	up.position = c
	up.pressed = false
	Input.parse_input_event(up)
	await _secs(0.6)


func _stage1() -> void:
	# --- el juego abre directamente en el vestíbulo (sin pantalla de menú) ---
	ok(main.state == main.St.LOBBY and main.lobby != null, "L1 el juego abre directamente en el Vestíbulo del Bufete")
	ok(await _wait_state(main.St.LOBBY), "L2 se está en el vestíbulo")
	await _secs(1.0)
	ok(main.lobby != null and main.lobby.stations.size() == 9, "L3 la sala tiene 9 estaciones (portales, 4 pedestales, dificultad, despacho, archivo)")
	ok(main.lobby.dummies.size() == 3, "L4 la zona de práctica tiene 3 muñecos")
	ok(not main.lobby.stations["continue"].enabled, "L5 sin partida guardada el portal CONTINUAR está desactivado")
	ok(main.lobby._cont_sub.text == "Sin partida guardada", "L6 el portal CONTINUAR indica que no hay partida")
	await _shot("l01_spawn")
	# --- vistas de cada zona ---
	await _tp(Vector3(-6.5, 0.3, -12.0), 0.0)
	await _shot("l02_portales")
	await _tp(Vector3(-10.5, 0.3, 0.0), PI * 0.5)
	await _shot("l03_armeria")
	await _tp(Vector3(10.0, 0.3, -6.0), -PI * 0.5)
	await _shot("l04_este_dificultad")
	await _tp(Vector3(10.0, 0.3, 4.5), -PI * 0.5)
	await _shot("l05_este_despacho_archivo")
	await _tp(Vector3(0.0, 0.3, 11.0), PI)
	await _shot("l06_practica")
	# --- indicador de estaciones lejos/cerca ---
	var wst: Interactable = main.lobby.stations["equip:weapon"]
	await _tp(wst.global_position + Vector3(30.0 if false else 0.0, 0.0, 9.0), 0.0)
	# --- armería: bloqueado → desbloquear → equipar (por toque real al botón de interacción) ---
	SaveSystem.data["records"]["best_arena"] = 6
	SaveSystem.data["meta"]["fees"] = 1000
	await _station_ui("equip:weapon")
	var ui := _overlay(EquipStationUI) as EquipStationUI
	ok(ui != null, "L7 tocar el botón táctil abre la estación de la Herramienta principal")
	await _shot("l07_estacion_herramienta")
	ok(String(LoadoutDB.equipped()["weapon"]) == "case", "L8 al inicio está equipado el Maletín")
	var unl: Array = _buttons(ui, "DESBLOQUEAR")
	ok(unl.size() == 2 and not (unl[0] as Button).disabled, "L9 los objetos bloqueados muestran el coste y se pueden comprar")
	(unl[0] as Button).pressed.emit()
	await _frames(5)
	ok(LoadoutDB.is_unlocked("gavel") and int(SaveSystem.data["meta"]["fees"]) == 860, "L10 se desbloquea el Mazo y se descuentan honorarios")
	var eq: Array = _buttons(ui, "EQUIPAR")
	ok(eq.size() >= 1, "L11 el objeto desbloqueado se puede equipar")
	(eq[0] as Button).pressed.emit()
	await _frames(5)
	ok(String(LoadoutDB.equipped()["weapon"]) == "gavel", "L12 el Mazo queda equipado")
	await _shot("l08_mazo_equipado")
	ui.closed.emit()
	ui.queue_free()
	await _secs(0.6)
	ok(main.lobby._pedestals["weapon"]["name"].text == "Mazo del Juez", "L13 el pedestal muestra el objeto equipado")
	ok(float(GameState.weapon_params["dmg_x"]) == 2.1, "L14 la zona de práctica ya usa el Mazo")
	# --- práctica: el equipo cambia el combate real ---
	var dummy: PracticeDummy = main.lobby.dummies[1]
	var avg := {}
	var cdm := {}
	for w in ["case", "gavel", "quill"]:
		SaveSystem.data["loadout"]["weapon"] = w
		SaveSystem.data["meta"]["unlocks"] = ["gavel", "quill"]
		main._lobby_changed()
		await _frames(3)
		await _tp(dummy.global_position + Vector3(0, 0, 1.6), 0.0)
		var tot := 0.0
		var n := 0
		for i in 8:
			GameState.player.skills.cd[0] = 0.0
			dummy._last_dmg = 0.0
			Feedback.record = true
			Feedback.event_log.clear()
			GameState.player.skills.try_cast(0)
			await _secs(1.6)                      # el maletín va, golpea y vuelve (el Sello automático añade otros golpes: se mide solo el del maletín)
			var case_hits: Array = Feedback.event_log.filter(func(x): return x.get("src", "") == "case")
			if not case_hits.is_empty():
				tot += float(case_hits[0]["dmg"])
				n += 1
			await _secs(0.5)
		avg[w] = tot / maxf(1.0, float(n))
		cdm[w] = GameState.player.skills.cd_max[0]
		print("  arma ", w, ": daño medio ", avg[w], " recarga ", cdm[w])
	ok(avg["gavel"] > avg["case"] * 1.5, "L15 el Mazo golpea claramente más fuerte que el Maletín (%.1f vs %.1f)" % [avg["gavel"], avg["case"]])
	ok(avg["quill"] < avg["case"] * 0.85, "L16 la Pluma golpea más flojo que el Maletín (%.1f vs %.1f)" % [avg["quill"], avg["case"]])
	ok(cdm["gavel"] > cdm["case"] and cdm["quill"] < cdm["case"], "L17 el Mazo es más lento y la Pluma más rápida")
	ok(dummy.hp == dummy.max_hp, "L18 el muñeco no se destruye")
	await _shot("l09_practica_golpe")
	# restaurar Mazo para la partida
	SaveSystem.data["loadout"]["weapon"] = "gavel"
	main._lobby_changed()
	# habilidad especial: cambia de verdad las estadísticas de la build
	var docs_before := GameState.build.s("docs_extra")
	LoadoutDB.equip("skill", "docs_burst")
	main._lobby_changed()
	ok(GameState.build.s("docs_extra") == 2.0 and docs_before == 2.0, "L19 la habilidad especial aporta sus estadísticas")
	LoadoutDB.unlock("seal_master")
	LoadoutDB.equip("skill", "seal_master")
	main._lobby_changed()
	ok(GameState.build.s("seal_extra") == 1.0 and GameState.build.s("docs_extra") == 0.0, "L20 cambiar de habilidad especial cambia las estadísticas")
	# --- dificultad ---
	await _station_ui("difficulty")
	var dui := _overlay(DifficultyUI) as DifficultyUI
	ok(dui != null, "L21 se abre la Mesa del Juez")
	await _shot("l10_dificultad")
	var el: Array = _buttons(dui, "ELEGIR")
	ok(el.size() >= 2, "L22 hay dificultades elegibles")
	LoadoutDB.select_difficulty("partner")
	dui.changed.emit()
	dui._refresh()
	await _frames(3)
	dui.closed.emit()
	dui.queue_free()
	await _secs(0.5)
	ok(LoadoutDB.selected_difficulty() == "partner" and Scaling.diff_id == "partner", "L23 la dificultad Socio queda elegida")
	ok(main.lobby._diff_sign.text == "SOCIO", "L24 el cartel de la Mesa del Juez muestra Socio")
	# --- despacho y archivo ---
	await _station_ui("meta")
	ok(_overlay(MetaScreen) != null, "L25 el Despacho abre las mejoras permanentes")
	await _shot("l11_despacho")
	var ms := _overlay(MetaScreen) as MetaScreen
	var fees0 := int(SaveSystem.data["meta"]["fees"])
	var buy := _buttons(ms, "6")
	ms._buy(Config.PERM_UPGRADES[0])
	ok(int(SaveSystem.data["meta"]["fees"]) < fees0 and int(SaveSystem.data["meta"]["perm"].get("perm_hp", 0)) == 1, "L26 comprar una mejora permanente descuenta honorarios y la guarda")
	ms.closed.emit()
	ms.queue_free()
	await _secs(0.5)
	await _station_ui("stats")
	ok(_overlay(StatsPanel) != null, "L27 el Archivo muestra estadísticas")
	await _shot("l12_estadisticas")
	_overlay(StatsPanel).queue_free()
	await _secs(0.4)
	# --- portal NUEVA PARTIDA: la partida usa lo elegido ---
	await _station_ui("new_run")
	ok(await _wait_state(main.St.RUN), "L28 el portal NUEVA PARTIDA empieza la partida")
	await _secs(3.5)
	ok(GameState.difficulty_id == "partner", "L29 la partida usa la dificultad elegida")
	ok(String(GameState.loadout["weapon"]) == "gavel" and String(GameState.loadout["skill"]) == "seal_master", "L30 la partida usa el equipamiento elegido")
	ok(float(GameState.weapon_params["dmg_x"]) == 2.1, "L31 el ataque primario de la partida es el del Mazo")
	ok(GameState.build.s("seal_extra") == 1.0, "L32 las estadísticas del equipamiento están en la build de la partida")
	var en: Enemy = null
	for e in main.arena.active:
		if is_instance_valid(e) and e.alive:
			en = e
	ok(en != null, "L33 aparecen enemigos")
	if en != null:
		var base_hp := float(EnemyDefs.DEFS[en.kind]["hp"]) * (1.0 + 0.11 * 0)
		ok(en.max_hp >= base_hp * 1.3, "L34 la vida enemiga refleja la dificultad Socio (%.0f vs base %.0f)" % [en.max_hp, base_hp])
	ok(float(GameState.player.max_hp) > 100.0, "L35 las mejoras permanentes y el equipo afectan a la salud inicial (%.0f)" % GameState.player.max_hp)
	await _shot("l13_partida_equipada")
	ok(SaveSystem.has_valid_run() and String(SaveSystem.get_run()["difficulty"]) == "partner", "L36 la partida guardada recuerda la dificultad")
	# guardar y salir → sala → CONTINUAR activo
	main._toggle_pause()
	await _frames(5)
	main._save_and_leave()
	ok(await _wait_state(main.St.LOBBY), "L37 Guardar y volver lleva al vestíbulo")
	await _secs(1.5)
	ok(main.state == main.St.LOBBY and main.lobby != null, "L38 se vuelve a la sala")
	await _secs(1.0)
	var cont: Interactable = main.lobby.stations["continue"]
	ok(cont.enabled and main.lobby._cont_sub.text.begins_with("Arena 1"), "L39 con partida guardada el portal CONTINUAR se activa")
	await _tp(cont.global_position + Vector3(-3.0, 0, 3.0), 0.0)
	await _shot("l14_continuar_activo")
	cont.activate(GameState.player)
	ok(await _wait_state(main.St.RUN), "L40 el portal CONTINUAR retoma la partida")
	await _secs(1.5)
	ok(GameState.difficulty_id == "partner" and GameState.arena_index == 0, "L41 la partida retomada conserva dificultad y arena")
	# desde la partida, guardar y salir otra vez para dejar un guardado para la etapa 2
	main._toggle_pause()
	await _frames(5)
	main._save_and_leave()
	ok(await _wait_state(main.St.LOBBY), "L42 queda una partida guardada para la siguiente etapa")
	await _secs(0.5)
	SaveSystem.save_now()


func _stage2() -> void:
	ok(SaveSystem.has_valid_run(), "M1 tras reabrir hay partida guardada")
	ok(LoadoutDB.is_unlocked("gavel") and LoadoutDB.is_unlocked("seal_master"), "M2 los desbloqueos persisten")
	ok(String(LoadoutDB.equipped()["weapon"]) == "gavel" and String(LoadoutDB.equipped()["skill"]) == "seal_master", "M3 el equipamiento elegido persiste")
	ok(LoadoutDB.selected_difficulty() == "partner", "M4 la dificultad elegida persiste")
	ok(int(SaveSystem.data["meta"]["perm"].get("perm_hp", 0)) == 1, "M5 la mejora permanente comprada persiste")
	ok(int(SaveSystem.data["stats"]["runs"]) == 1, "M6 las estadísticas persisten (partidas: 1, sin duplicar por reanudar)")
	ok(await _wait_state(main.St.LOBBY), "M7 al reabrir se está directamente en la sala")
	await _secs(1.0)
	ok(main.lobby._pedestals["weapon"]["name"].text == "Mazo del Juez", "M8 el pedestal muestra el Mazo tras reiniciar")
	ok(main.lobby._diff_sign.text == "SOCIO", "M9 la Mesa del Juez muestra Socio tras reiniciar")
	ok(main.lobby.stations["continue"].enabled, "M10 el portal CONTINUAR está activo tras reiniciar")
	await _shot("m01_sala_tras_reiniciar")
