extends Node
## Prueba de flujo con renderizado real (xvfb + Mesa): menú → partida → cofre/portal → guardado →
## "cerrar el juego" → reabrir → continuar. Dos procesos distintos para simular el reinicio:
##   godot ... -- --flowtest --stage=1 --out=DIR      (juega y guarda)
##   godot ... -- --flowtest --stage=2 --out=DIR      (reabre, continúa y comprueba)
## Escribe capturas y un informe en DIR. Un fallo termina con código 1.

var main: Node
var out_dir := "/tmp/flowtest"
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


func _find(kind: String) -> Interactable:
	for n in get_tree().get_nodes_in_group("interactable"):
		if n.kind == kind:
			return n
	return null


func _overlay(cls: Variant) -> Node:
	for n in main._ov_root().get_children():
		if is_instance_of(n, cls):
			return n
	return null


func _wait_state(st: int, timeout := 10.0) -> bool:
	var t := 0.0
	while main.state != st and t < timeout:
		await _frames(2)
		t += 0.03
	return main.state == st


func _finish() -> void:
	print("[RESULT] flujo etapa %d: %d ok, %d fallos" % [stage, passes, fails.size()])
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


# ------------------------------------------------------------------ etapa 1
func _stage1() -> void:
	ok(not SaveSystem.has_valid_run(), "F1 sin partida guardada")
	ok(not main.lobby.stations["continue"].enabled, "F2 el portal CONTINUAR está desactivado sin guardado")
	await _shot("f01_vestibulo_sin_guardado")
	main._on_play()
	ok(await _wait_state(main.St.RUN), "F3 empieza la partida")
	await _secs(1.2)
	ok(SaveSystem.has_valid_run(), "F4 se guardó automáticamente al empezar la arena")
	ok(String(SaveSystem.get_run()["stage"]) == "fight", "F5 el punto de control inicial es 'fight'")
	GameState.add_coins(77, false)
	Config.dev_god_mode = true
	main.arena.force_complete()
	var t := 0.0
	while main.arena.phase != Arena.Phase.CLEARED and t < 20.0:
		await _secs(0.2)
		t += 0.2
	ok(main.arena.phase == Arena.Phase.CLEARED, "F6 la arena se completa")
	await _secs(0.6)
	ok(String(SaveSystem.get_run()["stage"]) == "reward", "F7 al completar la arena se guarda (etapa 'reward')")
	var chest := _find("chest")
	var portal := _find("portal")
	ok(chest != null and portal != null, "F8 aparecen cofre y portal")
	ok(chest.indicator_visible(), "F9 el indicador ABRIR es visible sobre el cofre")
	ok(not portal.enabled, "F10 el portal está bloqueado hasta abrir el cofre")
	ok(portal.indicator_visible() and portal._ind_label.text == "ABRE EL COFRE", "F11 el portal indica que primero hay que abrir el cofre")
	await _shot("f02_cofre_indicador")
	# lejos: el indicador se oculta
	var far := chest.global_position + Vector3(0, 0, 22)
	far.z = clampf(far.z, -main.arena.half + 1.0, main.arena.half - 1.0)
	var far_pos := Vector3(chest.global_position.x + 24.0 if chest.global_position.x < 0 else chest.global_position.x - 24.0, 0.3, chest.global_position.z)
	GameState.player.teleport_to(far_pos)
	await _secs(0.4)
	ok(not chest.indicator_visible(), "F12 el indicador se oculta cuando el jugador está muy lejos")
	# cerca: aparece el botón táctil
	GameState.player.teleport_to(chest.global_position + Vector3(1.8, 0, 0))
	await _secs(0.5)
	ok(GameState.player.interact_target == chest, "F13 cerca del cofre es el objetivo de interacción")
	ok(main.touch.show_interact, "F14 aparece el botón táctil de interacción")
	await _shot("f03_boton_tactil")
	# abrir con un TOQUE real sobre el botón táctil
	var btn_center: Vector2 = main.touch._center("interact")
	var down := InputEventScreenTouch.new()
	down.index = 5
	down.position = btn_center
	down.pressed = true
	Input.parse_input_event(down)
	await _frames(4)
	var up := InputEventScreenTouch.new()
	up.index = 5
	up.position = btn_center
	up.pressed = false
	Input.parse_input_event(up)
	await _secs(1.2)
	ok(main.arena.chest_taken, "F15 tocar el botón abre el cofre")
	ok(not chest.indicator_visible(), "F16 el indicador desaparece al abrir el cofre")
	ok(portal.enabled, "F17 el portal se activa tras abrir el cofre")
	var cs := _overlay(CardSelect) as CardSelect
	ok(cs != null, "F18 aparecen las cartas de recompensa")
	# intentar abrir otra vez: no debe duplicar
	var before_cs := 0
	for n in main._ov_root().get_children():
		if n is CardSelect:
			before_cs += 1
	main.arena._open_chest(0)
	chest.activate(GameState.player)
	await _secs(0.8)
	var after_cs := 0
	for n in main._ov_root().get_children():
		if n is CardSelect:
			after_cs += 1
	ok(after_cs == before_cs, "F19 abrir el cofre otra vez no duplica la recompensa")
	await _shot("f04_cartas")
	var picks0: int = GameState.build.picks.size()
	cs._select(0)
	cs._on_confirm()
	await _secs(0.6)
	ok(GameState.build.picks.size() == picks0 + 1, "F20 la recompensa se entrega una sola vez")
	ok(String(SaveSystem.get_run()["stage"]) == "portal", "F21 al recoger la recompensa se guarda (etapa 'portal')")
	var saved := SaveSystem.get_run()
	var f := FileAccess.open(out_dir + "/stage1.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"coins": GameState.coins, "kills": GameState.kills, "picks": GameState.build.picks.size(),
		"arena": GameState.arena_index, "level": GameState.level, "hp": GameState.player.hp, "seed": saved["arena_seed"],
		"chest_pos": [chest.position.x, chest.position.z], "portal_pos": [portal.position.x, portal.position.z]}))
	f.close()
	ok(int(saved["coins"]) == GameState.coins, "F22 el guardado contiene las monedas actuales")
	await _shot("f05_portal_activo")
	# el juego se "cierra" aquí: SaveSystem ya escribió todo en disco


# ------------------------------------------------------------------ etapa 2
func _stage2() -> void:
	var f := FileAccess.open(out_dir + "/stage1.json", FileAccess.READ)
	var e: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	ok(SaveSystem.has_valid_run(), "G1 tras reabrir el juego hay partida guardada")
	ok(main.state == main.St.LOBBY and main.lobby.stations["continue"].enabled, "G2 el vestíbulo muestra el portal CONTINUAR PARTIDA activo")
	await _shot("g01_vestibulo_continuar")
	# NUEVA PARTIDA no sobrescribe sin avisar
	main._on_station("new_run")
	await _frames(5)
	ok(main.state == main.St.LOBBY and SaveSystem.has_valid_run() and not main._overlays.is_empty(), "G3 NUEVA PARTIDA pide confirmación y no borra el guardado")
	await _shot("g02_confirmar_nueva")
	for bn in main._ov_root().find_children("*", "Button", true, false):
		if (bn as Button).text == "Cancelar":
			(bn as Button).pressed.emit()
	await _frames(8)
	ok(SaveSystem.has_valid_run() and main._overlays.is_empty(), "G4 cancelar conserva la partida guardada")
	main._on_station("continue")
	ok(await _wait_state(main.St.RUN), "G5 CONTINUAR carga la partida")
	await _secs(1.5)
	ok(GameState.coins == int(e["coins"]), "G6 monedas recuperadas (%d)" % GameState.coins)
	ok(GameState.build.picks.size() == int(e["picks"]), "G7 mejoras recuperadas")
	ok(GameState.arena_index == int(e["arena"]), "G8 arena recuperada")
	ok(absf(GameState.player.hp - float(e["hp"])) < 0.5, "G9 salud recuperada")
	ok(main.arena.phase == Arena.Phase.CLEARED, "G10 la arena superada se restaura como completada")
	ok(main.arena.chest_taken, "G11 el cofre ya abierto no se puede volver a abrir")
	var chest := _find("chest")
	var portal := _find("portal")
	ok(chest != null and not chest.enabled, "G12 el cofre abierto está desactivado")
	ok(portal != null and portal.enabled, "G13 el portal sigue activo")
	ok(absf(chest.position.x - float(e["chest_pos"][0])) < 0.01 and absf(chest.position.z - float(e["chest_pos"][1])) < 0.01, "G14 el cofre reaparece en el mismo sitio")
	await _shot("g03_continuada")
	# portal → siguiente arena
	portal.activate(GameState.player)
	await _secs(2.5)
	ok(GameState.arena_index == int(e["arena"]) + 1, "G15 el portal lleva a la siguiente arena")
	ok(String(SaveSystem.get_run()["stage"]) == "fight" and int(SaveSystem.get_run()["arena_index"]) == int(e["arena"]) + 1, "G16 se guarda al empezar la nueva arena")
	# Guardar y salir
	main._toggle_pause()
	await _frames(5)
	main._save_and_leave()
	ok(await _wait_state(main.St.LOBBY), "G17a Guardar y volver lleva al vestíbulo")
	await _secs(1.5)
	ok(main.state == main.St.LOBBY and SaveSystem.has_valid_run(), "G17 Guardar y volver deja una partida guardada")
	await _shot("g04_vestibulo_tras_guardar")
	main._on_station("continue")
	ok(await _wait_state(main.St.RUN), "G18 se puede continuar tras Guardar y salir")
	await _secs(1.0)
	# derrota: la partida deja de ser recuperable
	Config.dev_god_mode = false
	GameState.player.revives_left = 0
	GameState.player.hp = 1.0
	GameState.player.iframes = 0.0
	GameState.player.hurt_iframes = 0.0
	GameState.player.take_damage(99999.0, GameState.player.global_position + Vector3(1, 0, 0), {"src": "test"})
	await _secs(0.3)
	ok(not SaveSystem.has_valid_run(), "G19 al perder la partida deja de ser recuperable")
	await _secs(2.5)
	await _shot("g05_derrota")
	ok(not SaveSystem.has_valid_run(), "G20 sigue sin poder recuperarse tras la pantalla de derrota")
