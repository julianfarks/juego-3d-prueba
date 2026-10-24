extends Node
## Pruebas del JOYSTICK táctil y de los MANDOS (v0.8.0). Render real (xvfb). Dos procesos para la persistencia:
##   xvfb-run -a godot --path . --rendering-driver opengl3 -- --padtest --stage=1 --out=DIR
##   xvfb-run -a godot --path . --rendering-driver opengl3 -- --padtest --stage=2 --out=DIR
## Todo se hace con eventos reales: InputEventScreenTouch/Drag para el táctil y InputEventJoypadButton/Motion para
## el mando (con el id de dispositivo), más la señal Input.joy_connection_changed que emite el sistema al conectar.
## LIMITACIÓN HONESTA: no hay un mando físico ni un Android aquí; se verifica la lógica de detección, nombres y mapeo con
## los nombres/IDs que reportan Xbox y PlayStation, no el hardware real.

var main: Node
var out_dir := "/tmp/padtest"
var stage := 1
var fails: Array = []
var passes := 0
var player: Player
var pi: PadInput
var only := ""          # letras de las secciones a ejecutar (vacío = todas)


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a.begins_with("--stage="):
			stage = int(a.substr(8))
		elif a.begins_with("--only="):
			only = a.substr(7)
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
	await _frames(4)
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png("%s/%s.png" % [out_dir, name])


# ---------------------------------------------------------------- entrada simulada
var _scale := Vector2.ONE      # relación ventana → lienzo (para simular toques con otras resoluciones)


func _calibrate() -> void:
	# envía un toque de calibración y mira dónde llega al lienzo
	var ev := InputEventScreenTouch.new()
	ev.index = 9
	ev.position = Vector2(200, 100)
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(2)
	var got: Vector2 = main.touch.last_event_pos
	ev = InputEventScreenTouch.new()
	ev.index = 9
	ev.position = Vector2(200, 100)
	ev.pressed = false
	Input.parse_input_event(ev)
	await _frames(2)
	_scale = Vector2(got.x / 200.0, got.y / 100.0)


func _touch(idx: int, pos: Vector2, down: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = idx
	ev.position = pos / _scale
	ev.pressed = down
	Input.parse_input_event(ev)
	await _frames(2)


func _drag(idx: int, pos: Vector2, rel := Vector2.ZERO) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = idx
	ev.position = pos / _scale
	ev.relative = rel / _scale
	Input.parse_input_event(ev)
	await _frames(2)


func _conn(dev: int, joy_name: String, on: bool) -> void:
	pi.debug_names[dev] = joy_name
	Input.joy_connection_changed.emit(dev, on)
	await _frames(3)


func _btn(idx: int, down: bool, dev := 0) -> void:
	var ev := InputEventJoypadButton.new()
	ev.device = dev
	ev.button_index = idx
	ev.pressed = down
	Input.parse_input_event(ev)
	await _frames(2)


func _press(idx: int, dev := 0) -> void:
	await _btn(idx, true, dev)
	await _btn(idx, false, dev)


func _axis(ax: int, v: float, dev := 0) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.device = dev
	ev.axis = ax
	ev.axis_value = v
	Input.parse_input_event(ev)
	await _frames(2)


func _trigger(ax: int, dev := 0) -> void:
	await _axis(ax, 1.0, dev)
	await _frames(2)
	await _axis(ax, 0.0, dev)


func _throws() -> int:
	return int(GameState.case_throw.counts["throws"])


func _wait_case() -> void:
	var t := 0.0
	while GameState.case_throw.in_flight() and t < 8.0:
		await _frames(2)
		t += get_process_delta_time() * 2.0
	await _frames(3)


func _overlay_of(cls: Variant) -> Node:
	for o in main._overlays:
		if is_instance_of(o, cls):
			return o
	return null


func _btn_by_text(root: Node, txt: String) -> Button:
	for b in root.find_children("*", "Button", true, false):
		if String(b.text).strip_edges().to_lower() == txt.to_lower() and (b as Button).is_visible_in_tree():
			return b
	return null


## Lleva el foco hasta un control usando solo la cruceta (como haría el jugador).
func _nav_to(target: Control, max_steps := 25) -> bool:
	for i in max_steps:
		var fo := get_viewport().gui_get_focus_owner()
		if fo == target:
			return true
		if fo == null:
			await _frames(2)
			continue
		var d := target.get_global_rect().get_center() - fo.get_global_rect().get_center()
		var btn := JOY_BUTTON_DPAD_RIGHT if d.x > 0 else JOY_BUTTON_DPAD_LEFT
		var vert := JOY_BUTTON_DPAD_DOWN if d.y > 0 else JOY_BUTTON_DPAD_UP
		if absf(d.y) > absf(d.x) * 0.6 or i % 3 == 2:
			btn = vert
		await _press(btn)
		await _frames(1)
	return get_viewport().gui_get_focus_owner() == target


func _focus_text() -> String:
	var fo := get_viewport().gui_get_focus_owner()
	return "" if fo == null else (String(fo.get("text")) if fo is Button else fo.name)


# ---------------------------------------------------------------- flujo
func _run() -> void:
	await _frames(10)
	pi = main.pad
	if stage == 2:
		await _stage2()
		_finish()
		return
	await _unit_detection()
	main._show_menu()
	await _frames(15)
	main._on_play()
	var t := 0.0
	while main.state != main.St.RUN and t < 10.0:
		await _frames(2)
		t += 0.03
	ok(main.state == main.St.RUN, "P0 empieza la partida")
	Config.dev_god_mode = true
	player = GameState.player
	main.arena.force_complete()
	await _secs(1.0)
	main.touch.visible = true
	await _frames(3)
	if only == "" or only.contains("B"):
		await _joystick_tests()
		await _resolution_tests()
	if only == "" or only.contains("C"):
		await _connection_tests()
	else:
		await _conn(0, "Xbox Wireless Controller", true)
	if only == "" or only.contains("D"):
		await _mapping_tests()
	if only == "" or only.contains("E"):
		await _remap_tests()
	if only == "" or only.contains("F"):
		await _menu_nav_tests()
	if only == "" or only.contains("G"):
		await _controls_ui_tests()
	if only == "" or only.contains("H"):
		await _lobby_nav_tests()
	if only == "":
		await _persist_prepare()
	Config.dev_god_mode = false
	_finish()


func _finish() -> void:
	print("")
	print("=== PADTEST etapa %d: %d comprobaciones OK, %d fallos ===" % [stage, passes, fails.size()])
	for f in fails:
		print("  FALLO: ", f)
	get_tree().quit(0 if fails.is_empty() else 1)


# ---------------------------------------------------------------- A. nombres de mandos
func _unit_detection() -> void:
	var cases := {
		"Xbox Wireless Controller": "xbox", "Xbox 360 Controller": "xbox", "Xbox One Controller": "xbox", "XInput Gamepad": "xbox",
		"Microsoft X-Box One pad": "xbox", "DualSense Wireless Controller": "ps", "PS5 Controller": "ps", "PS4 Controller": "ps",
		"Sony Interactive Entertainment Wireless Controller": "ps", "Wireless Controller": "ps", "PLAYSTATION(R)3 Controller": "ps",
		"DUALSHOCK 4": "ps", "Generic USB Joystick": "generic", "8BitDo Pro 2": "generic",
	}
	var all_ok := true
	for n in cases.keys():
		if PadInput.kind_from_name(n) != cases[n]:
			all_ok = false
			info("nombre mal clasificado: %s → %s (esperado %s)" % [n, PadInput.kind_from_name(n), cases[n]])
	ok(all_ok, "P1.1 %d nombres de mandos Xbox/PlayStation/otros se clasifican bien" % cases.size())
	ok(PadInput.kind_from_name("???", 0x054c) == "ps" and PadInput.kind_from_name("???", 0x045e) == "xbox", "P1.2 el vendor ID de Sony/Microsoft también sirve")
	# equivalencias de botones: mismas posiciones físicas, nombres distintos
	pi.debug_names[0] = "Xbox Wireless Controller"
	pi.active = 0
	var xb := [pi.button_name({"t": "b", "i": JOY_BUTTON_A}), pi.button_name({"t": "b", "i": JOY_BUTTON_B}), pi.button_name({"t": "b", "i": JOY_BUTTON_X}), pi.button_name({"t": "b", "i": JOY_BUTTON_Y}), pi.button_name({"t": "a", "i": 5}), pi.button_name({"t": "a", "i": 4}), pi.button_name({"t": "b", "i": JOY_BUTTON_RIGHT_SHOULDER}), pi.button_name({"t": "b", "i": JOY_BUTTON_START})]
	pi.debug_names[0] = "DualSense Wireless Controller"
	var ps := [pi.button_name({"t": "b", "i": JOY_BUTTON_A}), pi.button_name({"t": "b", "i": JOY_BUTTON_B}), pi.button_name({"t": "b", "i": JOY_BUTTON_X}), pi.button_name({"t": "b", "i": JOY_BUTTON_Y}), pi.button_name({"t": "a", "i": 5}), pi.button_name({"t": "a", "i": 4}), pi.button_name({"t": "b", "i": JOY_BUTTON_RIGHT_SHOULDER}), pi.button_name({"t": "b", "i": JOY_BUTTON_START})]
	ok(xb == ["A", "B", "X", "Y", "RT", "LT", "RB", "Menu"], "P1.3 etiquetas Xbox: %s" % str(xb))
	ok(ps == ["Cruz", "Círculo", "Cuadrado", "Triángulo", "R2", "L2", "R1", "Options"], "P1.4 etiquetas PlayStation: %s" % str(ps))
	pi.debug_names.erase(0)
	pi.active = -1


# ---------------------------------------------------------------- B. joystick táctil
func _joystick_tests() -> void:
	var tc: TouchControls = main.touch
	var sz: Vector2 = tc.size
	var zone := tc.joy_zone()
	info("pantalla %s · zona del joystick %s" % [str(sz), str(zone)])
	ok(zone.position.x == 0.0 and zone.end.x <= sz.x * 0.45 and zone.position.y >= sz.y * 0.3 and zone.end.y <= sz.y + 0.5, "J0 la zona es el cuadrante inferior izquierdo (%s de %s)" % [str(zone), str(sz)])
	# 1. dentro de la zona: se activa y nace bajo el dedo
	var p_in := Vector2(sz.x * 0.2, sz.y * 0.75)
	await _touch(1, p_in, true)
	ok(tc.joy_active(), "J1 tocar dentro de la zona activa el joystick")
	ok(tc._joy_origin.distance_to(p_in) < 2.0, "J1b la base nace bajo el pulgar (origen %s, toque %s)" % [str(tc._joy_origin), str(p_in)])
	# 3. arrastrar cambia de dirección con fluidez
	var dirs := {"right": Vector2(60, 0), "left": Vector2(-60, 0), "up": Vector2(0, -60), "down": Vector2(0, 60)}
	var good := true
	for k in dirs.keys():
		await _drag(1, tc._joy_origin + dirs[k])
		var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		var dv: Vector2 = dirs[k].normalized()
		if v.length() < 0.2 or v.normalized().dot(dv) < 0.95:
			good = false
			info("dirección %s dio %s" % [k, str(v)])
	ok(good, "J3 arrastrar el dedo cambia la dirección en las 4 direcciones (arriba = adelante)")
	# proporcionalidad: más lejos = más rápido
	await _drag(1, tc._joy_origin + Vector2(20, 0))
	var small := Input.get_vector("move_left", "move_right", "move_forward", "move_back").length()
	await _drag(1, tc._joy_origin + Vector2(80, 0))
	var big := Input.get_vector("move_left", "move_right", "move_forward", "move_back").length()
	ok(small < big and big > 0.9, "J3b la magnitud crece con la distancia (%.2f → %.2f)" % [small, big])
	# 5. diagonal sin ventaja de velocidad
	var r := 96.0 * float(SaveSystem.data["controls"]["joystick"]["scale"])
	await _drag(1, tc._joy_origin + Vector2(r * 0.7, 0))
	var straight := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	await _drag(1, tc._joy_origin + Vector2(r * 0.7, r * 0.7) / sqrt(2.0))
	var diag := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	ok(absf(straight.length() - diag.length()) < 0.03 and diag.x > 0.3 and diag.y > 0.3, "J5 la diagonal no es más rápida: recto %.3f · diagonal %.3f" % [straight.length(), diag.length()])
	# velocidad real del personaje
	await _drag(1, tc._joy_origin + Vector2(r, 0))
	await _secs(0.6)
	var v_straight := Vector2(player.velocity.x, player.velocity.z).length()
	await _drag(1, tc._joy_origin + Vector2(r, r))
	await _secs(0.6)
	var v_diag := Vector2(player.velocity.x, player.velocity.z).length()
	ok(v_straight > 3.0 and absf(v_straight - v_diag) < 0.08 * v_straight, "J5b velocidad real del personaje: recto %.2f · diagonal %.2f m/s" % [v_straight, v_diag])
	# el dedo sale del área visual: se mantiene el seguimiento
	await _drag(1, Vector2(sz.x * 0.9, sz.y * 0.1))
	ok(tc.joy_active() and Input.get_action_strength("move_right") > 0.0, "J2b con el dedo muy lejos del círculo se sigue controlando")
	# 6. mover y atacar a la vez (dos dedos)
	var thr0 := _throws()
	var pos0 := player.global_position
	await _drag(1, tc._joy_origin + Vector2(r, 0))
	await _touch(2, tc._center("attack"), true)
	await _touch(2, tc._center("attack"), false)
	await _secs(0.7)
	ok(_throws() == thr0 + 1, "J6a el segundo dedo lanza el maletín (%d → %d)" % [thr0, _throws()])
	ok(tc.joy_active() and Input.get_action_strength("move_right") > 0.5 and player.global_position.distance_to(pos0) > 1.0, "J6b mientras tanto se sigue moviendo (recorrió %.1f m)" % player.global_position.distance_to(pos0))
	await _touch(1, tc._joy_origin, false)
	# 4. soltar detiene las órdenes
	ok(not tc.joy_active() and Input.get_action_strength("move_right") == 0.0 and Input.get_action_strength("move_left") == 0.0 and Input.get_action_strength("move_forward") == 0.0 and Input.get_action_strength("move_back") == 0.0, "J4 soltar el dedo apaga el joystick y todas las órdenes de movimiento")
	await _secs(0.6)
	ok(Vector2(player.velocity.x, player.velocity.z).length() < 0.5, "J4b el personaje se detiene (%.2f m/s)" % Vector2(player.velocity.x, player.velocity.z).length())
	await _wait_case()
	# 2. fuera de la zona: no se activa
	var outside := {
		"arriba-izquierda (antes activaba)": Vector2(sz.x * 0.2, sz.y * 0.18),
		"borde medio (x=44 %, antes activaba)": Vector2(sz.x * 0.44, sz.y * 0.75),
		"centro de la pantalla": Vector2(sz.x * 0.5, sz.y * 0.6),
		"izquierda a media altura": Vector2(sz.x * 0.1, sz.y * 0.3),
	}
	for k in outside.keys():
		await _touch(3, outside[k], true)
		ok(not tc.joy_active() and Input.get_action_strength("move_right") + Input.get_action_strength("move_left") == 0.0, "J2 tocar «%s» no activa el joystick" % k)
		await _touch(3, outside[k], false)
	# tocar fuera de la zona y arrastrar hacia dentro tampoco lo activa
	await _touch(3, Vector2(sz.x * 0.2, sz.y * 0.2), true)
	await _drag(3, Vector2(sz.x * 0.2, sz.y * 0.8))
	ok(not tc.joy_active(), "J2c un toque nacido fuera de la zona nunca se convierte en joystick al arrastrarlo dentro")
	await _touch(3, Vector2(sz.x * 0.2, sz.y * 0.2), false)
	# 7. botones, inventario y pausa no activan el joystick ni la cámara
	var ui_targets := {
		"botón INVENTARIO": main.hud.get_node("InventoryButton").get_global_rect().get_center(),
		"botón PAUSA": main.hud.get_node("PauseButton").get_global_rect().get_center(),
		"botón SALTAR": tc._center("jump"),
		"botón ESQUIVAR": tc._center("dodge"),
		"botón DOCS": tc._center("skill1"),
	}
	var yaw0: float = main.cam.yaw
	for k in ["botón SALTAR", "botón ESQUIVAR", "botón DOCS"]:
		await _touch(4, ui_targets[k], true)
		ok(not tc.joy_active() and tc._pointers.get(4, {}).get("role", "") == "button", "J7 tocar el %s es un botón, no joystick ni cámara" % k.substr(6))
		await _touch(4, ui_targets[k], false)
	await _secs(1.0)
	for k in ["botón INVENTARIO", "botón PAUSA"]:
		var nptr0 := tc._pointers.size()
		await _touch(5, ui_targets[k], true)
		var ptr_role: String = tc._pointers.get(5, {}).get("role", "none")
		ok(not tc.joy_active() and ptr_role == "none", "J7 tocar el %s no inicia joystick ni arrastre de cámara (rol: %s)" % [k.substr(6), ptr_role])
		await _touch(5, ui_targets[k], false)
		# cerrar lo que haya abierto
		if k == "botón INVENTARIO":
			var inv := _overlay_of(InventoryUI)
			ok(inv != null, "J7b el toque en INVENTARIO sí abre el inventario")
			if inv != null:
				inv.call("_close")
			await _frames(3)
		else:
			await _frames(3)
			if main._pause_menu != null and is_instance_valid(main._pause_menu):
				main._resume()
				await _frames(3)
	# 9. no queda activado al cambiar de interfaz o pausar
	await _touch(1, p_in, true)
	await _drag(1, tc._joy_origin + Vector2(r, 0))
	ok(tc.joy_active(), "J9 (preparación) joystick activo")
	main._toggle_pause()
	await _frames(4)
	ok(not tc.joy_active() and Input.get_action_strength("move_right") == 0.0, "J9 al pausar el joystick se suelta y no queda ninguna orden de movimiento")
	main._resume()
	await _frames(4)
	await _touch(1, p_in, false)
	await _touch(1, p_in, true)
	await _drag(1, tc._joy_origin + Vector2(r, 0))
	main._open_inventory()
	await _frames(4)
	ok(not tc.joy_active() and Input.get_action_strength("move_right") == 0.0, "J9b al abrir el inventario con el dedo puesto el joystick se suelta")
	var inv2 := _overlay_of(InventoryUI)
	if inv2 != null:
		inv2.call("_close")
	await _touch(1, p_in, false)
	await _frames(4)
	# cámara: arrastrar en la derecha mueve la cámara, mover el joystick no
	yaw0 = main.cam.yaw
	await _touch(1, p_in, true)
	await _drag(1, tc._joy_origin + Vector2(r, 0), Vector2(10, 0))
	await _frames(6)
	ok(absf(main.cam.yaw - yaw0) < 0.001, "J4c mover el joystick no gira la cámara (Δyaw %.4f)" % (main.cam.yaw - yaw0))
	await _touch(1, p_in, false)
	await _touch(6, Vector2(sz.x * 0.7, sz.y * 0.35), true)
	for i in 5:
		await _drag(6, Vector2(sz.x * 0.7 + 20.0 * (i + 1), sz.y * 0.35), Vector2(20, 0))
	await _frames(4)
	await _touch(6, Vector2(sz.x * 0.7 + 100.0, sz.y * 0.35), false)
	ok(absf(main.cam.yaw - yaw0) > 0.05, "J4d arrastrar en la mitad derecha sí gira la cámara (Δyaw %.3f)" % (main.cam.yaw - yaw0))
	await _shot("p_joystick_activo")
	# ajustes: tamaño de la zona
	SaveSystem.data["settings"]["joy_zone"] = 0.6
	var z_small := tc.joy_zone()
	SaveSystem.data["settings"]["joy_zone"] = 1.4
	var z_big := tc.joy_zone()
	SaveSystem.data["settings"]["joy_zone"] = 1.0
	ok(z_small.size.x < tc.joy_zone().size.x and tc.joy_zone().size.x < z_big.size.x and z_big.end.x < sz.x * CAM_X_LIMIT, "J10a la opción de zona cambia el área (%d / %d / %d px) sin invadir la cámara" % [z_small.size.x, tc.joy_zone().size.x, z_big.size.x])
	SaveSystem.data["settings"]["joy_sens"] = 1.8
	await _touch(1, p_in, true)
	await _drag(1, tc._joy_origin + Vector2(30, 0))
	var v_hi := Input.get_vector("move_left", "move_right", "move_forward", "move_back").length()
	await _touch(1, p_in, false)
	SaveSystem.data["settings"]["joy_sens"] = 0.5
	await _touch(1, p_in, true)
	await _drag(1, tc._joy_origin + Vector2(30, 0))
	var v_lo := Input.get_vector("move_left", "move_right", "move_forward", "move_back").length()
	await _touch(1, p_in, false)
	SaveSystem.data["settings"]["joy_sens"] = 1.0
	ok(v_hi > v_lo, "J10b la sensibilidad del joystick cambia la respuesta (%.2f vs %.2f)" % [v_lo, v_hi])


const CAM_X_LIMIT := 0.46


func _resolution_tests() -> void:
	var tc: TouchControls = main.touch
	var win := get_window()
	var orig := win.size
	var sizes := [Vector2i(960, 540), Vector2i(800, 360), Vector2i(1024, 768), Vector2i(1280, 720), Vector2i(2400, 1080)]
	var all_ok := true
	var changed := 0
	for s in sizes:
		win.size = s
		await _frames(8)
		await _calibrate()
		if win.size != s:
			info("el servidor gráfico no aceptó %s (quedó %s)" % [str(s), str(win.size)])
			continue
		changed += 1
		var sz: Vector2 = tc.size
		var zone := tc.joy_zone()
		var r := 96.0 * float(SaveSystem.data["controls"]["joystick"]["scale"])
		var inside := Vector2(zone.size.x * 0.4, zone.position.y + zone.size.y * 0.55)
		var outside_pts := [Vector2(zone.end.x + 30.0, zone.position.y + zone.size.y * 0.5), Vector2(zone.size.x * 0.4, zone.position.y - 40.0)]
		await _touch(1, inside, true)
		var a := tc.joy_active()
		# la base completa cabe dentro de la pantalla
		var org := tc._joy_origin
		var fits := org.x - r >= 0.0 and org.y + r <= sz.y + 0.5 and org.x + r <= sz.x
		await _touch(1, inside, false)
		var b := true
		for o in outside_pts:
			await _touch(1, o, true)
			if tc.joy_active():
				b = false
				info("  (%s) un toque en %s activó el joystick (zona %s)" % [str(s), str(o), str(zone)])
			await _touch(1, o, false)
		# no pisa botones: ningún botón dentro de la zona
		var overlap := false
		for n in TouchControls.BUTTONS:
			var c := tc._center(n)
			if zone.grow(-1.0).has_point(c):
				overlap = true
		if not (a and b and fits and not overlap):
			all_ok = false
			info("resolución %s: dentro=%s fuera_ok=%s cabe=%s solapa_botones=%s" % [str(s), a, b, fits, overlap])
		await _shot("p_res_%dx%d" % [s.x, s.y])
	win.size = orig
	await _frames(6)
	await _calibrate()
	ok(changed >= 3 and all_ok, "J8 el joystick respeta la zona y los márgenes en %d resoluciones/aspectos probados" % changed)


# ---------------------------------------------------------------- C. conexión y modo
func _connection_tests() -> void:
	var tc: TouchControls = main.touch
	ok(not PadInput.pad_mode and not tc.suppressed, "C0 sin mando: modo táctil y controles visibles")
	await _conn(0, "Xbox Wireless Controller", true)
	ok(pi.connected() and pi.active == 0 and pi.device_kind() == "xbox", "C1 se detecta un mando Xbox al conectarlo (%s)" % pi.device_name(0))
	ok(PadInput.pad_mode and tc.suppressed, "C2 al conectar, el modo cambia a mando y los controles táctiles se ocultan")
	ok(main.hud.visible and main.hud.get_node_or_null("InventoryButton").visible and main.hud.get_node_or_null("PauseButton").visible, "C2b la salud, el objetivo, el inventario y la pausa siguen visibles")
	# el joystick ya no captura (el mando ya dio señales de vida: un botón)
	await _press(JOY_BUTTON_BACK)
	var sz: Vector2 = tc.size
	await _touch(1, Vector2(sz.x * 0.2, sz.y * 0.75), true)
	ok(not tc.joy_active(), "C3 con el mando activo el joystick táctil no captura toques")
	await _touch(1, Vector2(sz.x * 0.2, sz.y * 0.75), false)
	await _shot("p_modo_mando")
	# seguro contra mandos fantasma: sin actividad del mando durante 8 s, tocar la pantalla devuelve los controles táctiles
	await _secs(pi.OVERRIDE_IDLE + 0.5)
	await _touch(1, Vector2(sz.x * 0.2, sz.y * 0.75), true)
	ok(not PadInput.pad_mode and not tc.suppressed and tc.joy_active(), "C3b mando conectado pero inactivo + toque en pantalla → vuelven los controles táctiles y el joystick responde")
	await _touch(1, Vector2(sz.x * 0.2, sz.y * 0.75), false)
	await _press(JOY_BUTTON_BACK)
	ok(PadInput.pad_mode and tc.suppressed, "C3c en cuanto el mando se usa de nuevo se ocultan otra vez")
	# segundo mando (PlayStation): el activo es el último usado
	await _conn(1, "DualSense Wireless Controller", true)
	ok(pi.devices.size() == 2 and pi.active == 0, "C4 con dos mandos se conservan ambos (activo %d)" % pi.active)
	await _btn(JOY_BUTTON_A, true, 1)
	await _btn(JOY_BUTTON_A, false, 1)
	ok(pi.active == 1 and pi.device_kind() == "ps", "C4b el activo pasa a ser el último que se usó (PlayStation)")
	ok(PadInput.label("jump") == "Cruz" and PadInput.label("attack") == "R2", "C4c las etiquetas siguen al mando activo: Cruz / R2")
	await _btn(JOY_BUTTON_B, true, 0)
	await _btn(JOY_BUTTON_B, false, 0)
	ok(pi.active == 0 and PadInput.label("jump") == "A" and PadInput.label("attack") == "RT", "C4d vuelve al Xbox al usarlo: A / RT")
	await _conn(0, "", false)
	ok(pi.devices == [1] and pi.active == 1 and PadInput.pad_mode, "C5 al desconectar el activo se pasa al otro mando y se sigue en modo mando")
	await _conn(1, "", false)
	ok(not pi.connected() and not PadInput.pad_mode and not tc.suppressed, "C6 al desconectar todos reaparecen los controles táctiles")
	await _touch(1, Vector2(sz.x * 0.2, sz.y * 0.75), true)
	ok(tc.joy_active(), "C7 el joystick táctil vuelve a funcionar tras desconectar")
	await _touch(1, Vector2(sz.x * 0.2, sz.y * 0.75), false)
	# cambio manual
	pi.set_mode_setting("pad")
	await _frames(2)
	ok(PadInput.pad_mode and tc.suppressed, "C8 «solo mando» fuerza el modo mando aunque no haya mando")
	pi.set_mode_setting("touch")
	await _conn(0, "Xbox Wireless Controller", true)
	ok(not PadInput.pad_mode and not tc.suppressed, "C9 «solo táctil» mantiene los controles táctiles aunque haya un mando")
	pi.set_mode_setting("auto")
	await _frames(2)
	ok(PadInput.pad_mode, "C10 «automático» vuelve a seguir al mando")


# ---------------------------------------------------------------- D. botones y sticks
func _mapping_tests() -> void:
	# mando Xbox conectado (activo 0)
	var ct: CaseThrow = GameState.case_throw
	await _wait_case()
	await _secs(1.0)
	var t0 := _throws()
	await _trigger(5)
	ok(_throws() == t0 + 1, "D1 RT lanza el maletín (%d → %d)" % [t0, _throws()])
	await _wait_case()
	var t1 := _throws()
	await _axis(5, 1.0)
	await _secs(2.5)
	await _axis(5, 0.0)
	ok(_throws() == t1 + 1, "D1b mantener RT no repite el lanzamiento (%d)" % (_throws() - t1))
	await _wait_case()
	# LT = DOCS
	player.skills.energy = player.skills.energy_max
	player.skills.cd[1] = 0.0
	await _trigger(4)
	ok(player.skills.cd[1] > 0.0, "D2 LT usa DOCS")
	# A salta
	await _secs(1.0)
	var vy := -99.0
	await _btn(JOY_BUTTON_A, true)
	for i in 8:
		await _frames(1)
		vy = maxf(vy, player.velocity.y)
	await _btn(JOY_BUTTON_A, false)
	ok(vy > 2.0, "D3 A salta (vel. vertical %.1f)" % vy)
	await _secs(1.0)
	# B esquiva
	player._dodge_cd = 0.0
	await _btn(JOY_BUTTON_B, true)
	var dodged := false
	for i in 8:
		await _frames(1)
		if player._dodge_t > 0.0:
			dodged = true
	await _btn(JOY_BUTTON_B, false)
	ok(dodged, "D4 B esquiva")
	await _secs(1.0)
	# X interactúa: se ve en el estado de la acción
	await _btn(JOY_BUTTON_X, true)
	ok(Input.is_action_pressed("interact") and not Input.is_action_pressed("jump") and not Input.is_action_pressed("dodge"), "D5 X activa solo «interactuar»")
	await _btn(JOY_BUTTON_X, false)
	# ninguna otra acción por el mismo botón
	var singles := {JOY_BUTTON_A: "jump", JOY_BUTTON_B: "dodge", JOY_BUTTON_X: "interact", JOY_BUTTON_Y: "inventory", JOY_BUTTON_START: "pause"}
	var acts := ["attack", "skill1", "jump", "dodge", "interact", "inventory", "pause"]
	var clean := true
	for b in singles.keys():
		if b == JOY_BUTTON_Y or b == JOY_BUTTON_START:
			continue
		await _btn(b, true)
		for a in acts:
			if (a == singles[b]) != Input.is_action_pressed(a):
				clean = false
				info("el botón %d activó «%s»" % [b, a])
		await _btn(b, false)
	await _axis(5, 1.0)
	for a in acts:
		if (a == "attack") != Input.is_action_pressed(a):
			clean = false
	await _axis(5, 0.0)
	ok(clean, "D6 cada botón activa únicamente su propia acción (sin pulsaciones dobles)")
	# stick izquierdo mueve
	await _wait_case()
	var p0 := player.global_position
	await _axis(1, -1.0)       # adelante
	await _secs(0.8)
	var moved := player.global_position.distance_to(p0)
	ok(moved > 1.5, "D7 el stick izquierdo mueve al personaje (%.1f m)" % moved)
	var dir := (player.global_position - p0).normalized()
	ok(dir.dot(main.cam.forward_flat()) > 0.8, "D7b hacia delante respecto a la cámara (cos %.2f)" % dir.dot(main.cam.forward_flat()))
	await _axis(1, 0.0)
	await _secs(0.6)
	ok(Vector2(player.velocity.x, player.velocity.z).length() < 0.6, "D7c al soltar el stick el personaje se detiene")
	# zona muerta
	var p1 := player.global_position
	await _axis(0, 0.12)
	await _axis(1, 0.1)
	await _secs(0.5)
	ok(player.global_position.distance_to(p1) < 0.3, "D8 un temblor del stick dentro de la zona muerta no mueve al personaje (%.2f m)" % player.global_position.distance_to(p1))
	await _axis(0, 0.0)
	await _axis(1, 0.0)
	# diagonal con el stick: magnitud acotada a 1
	await _axis(0, 1.0)
	await _axis(1, 1.0)
	var mv := pi.move_vector()
	ok(mv.length() <= 1.001 and mv.length() > 0.95, "D8b diagonal completa del stick = magnitud %.3f (no 1.41)" % mv.length())
	await _axis(0, 0.0)
	await _axis(1, 0.0)
	# stick derecho gira la cámara
	var yaw0: float = main.cam.yaw
	await _axis(2, 1.0)
	await _secs(0.5)
	await _axis(2, 0.0)
	ok(absf(main.cam.yaw - yaw0) > 0.3, "D9 el stick derecho gira la cámara (Δyaw %.2f rad)" % (main.cam.yaw - yaw0))
	# sensibilidad
	PadInput.cfg()["look_sens"] = 2.0
	yaw0 = main.cam.yaw
	await _axis(2, 1.0)
	await _secs(0.5)
	await _axis(2, 0.0)
	var d_hi := absf(main.cam.yaw - yaw0)
	PadInput.cfg()["look_sens"] = 0.5
	yaw0 = main.cam.yaw
	await _axis(2, 1.0)
	await _secs(0.5)
	await _axis(2, 0.0)
	var d_lo := absf(main.cam.yaw - yaw0)
	PadInput.cfg()["look_sens"] = 1.0
	ok(d_hi > d_lo * 2.0, "D10 la sensibilidad del stick de cámara cambia el giro (%.2f vs %.2f rad)" % [d_lo, d_hi])
	# intercambiar sticks
	PadInput.cfg()["move_stick"] = "right"
	p1 = player.global_position
	await _axis(3, -1.0)
	await _secs(0.7)
	var moved_r := player.global_position.distance_to(p1)
	await _axis(3, 0.0)
	yaw0 = main.cam.yaw
	await _axis(0, 1.0)
	await _secs(0.4)
	await _axis(0, 0.0)
	ok(moved_r > 0.7 and absf(main.cam.yaw - yaw0) > 0.2, "D11 con los sticks intercambiados el derecho mueve (%.1f m) y el izquierdo gira la cámara (Δyaw %.2f)" % [moved_r, main.cam.yaw - yaw0])
	PadInput.cfg()["move_stick"] = "left"
	# 6. mover y atacar con el mando a la vez
	await _wait_case()
	var tt := _throws()
	p1 = player.global_position
	await _axis(0, 1.0)
	await _trigger(5)
	await _secs(0.5)
	await _axis(0, 0.0)
	ok(_throws() == tt + 1 and player.global_position.distance_to(p1) > 1.0, "D12 mover con el stick y atacar con RT a la vez funciona")
	await _wait_case()
	# Y abre/cierra el inventario; Start pausa
	await _press(JOY_BUTTON_Y)
	await _frames(4)
	ok(_overlay_of(InventoryUI) != null, "D13 Y abre el inventario")
	await _shot("p_inventario_mando")
	await _press(JOY_BUTTON_Y)
	await _frames(4)
	ok(_overlay_of(InventoryUI) == null and not get_tree().paused, "D13b Y lo vuelve a cerrar y la partida continúa")
	await _press(JOY_BUTTON_START)
	await _frames(4)
	ok(main._pause_menu != null and is_instance_valid(main._pause_menu) and get_tree().paused, "D14 Start pausa el juego")
	await _press(JOY_BUTTON_B)       # ui_cancel → Continuar
	await _frames(4)
	ok(main._pause_menu == null and not get_tree().paused, "D14b B (cancelar) reanuda desde la pausa")


# ---------------------------------------------------------------- E. reasignación
func _remap_tests() -> void:
	# captura real: RB para lanzar el maletín
	var got := {}
	pi.begin_capture("pad", func(b): got.merge(b, true))
	await _frames(25)
	await _press(JOY_BUTTON_RIGHT_SHOULDER)
	ok(got.get("t", "") == "b" and int(got.get("i", -1)) == JOY_BUTTON_RIGHT_SHOULDER and not pi.capturing, "E1 la captura recibe el botón pulsado (RB)")
	ok(PadInput.find_conflict("attack", got) == "", "E1b RB no entra en conflicto (no estaba en el grupo de juego)")
	PadInput.set_binding("attack", got)
	await _frames(2)
	await _wait_case()
	var t0 := _throws()
	await _press(JOY_BUTTON_RIGHT_SHOULDER)
	await _frames(3)
	ok(_throws() == t0 + 1, "E2 tras reasignar, RB lanza el maletín de inmediato (%d → %d)" % [t0, _throws()])
	await _wait_case()
	var t1 := _throws()
	await _trigger(5)
	await _frames(3)
	ok(_throws() == t1, "E3 RT ya no lanza el maletín tras reasignarlo (no activa otra función)")
	ok(PadInput.label("attack") == "RB", "E3b la etiqueta del HUD cambia a RB (%s)" % PadInput.label("attack"))
	await _shot("p_hud_reasignado")
	# conflicto: asignar «jump» a B (ya usado por «dodge»)
	var conflict := PadInput.find_conflict("jump", {"t": "b", "i": JOY_BUTTON_B})
	ok(conflict == "dodge", "E4 se detecta el conflicto: B ya es «%s»" % conflict)
	PadInput.swap_bindings("jump", "dodge")
	await _frames(2)
	await _btn(JOY_BUTTON_B, true)
	var jump_b := Input.is_action_pressed("jump")
	var dodge_b := Input.is_action_pressed("dodge")
	await _btn(JOY_BUTTON_B, false)
	await _btn(JOY_BUTTON_A, true)
	var jump_a := Input.is_action_pressed("jump")
	var dodge_a := Input.is_action_pressed("dodge")
	await _btn(JOY_BUTTON_A, false)
	ok(jump_b and not dodge_b and dodge_a and not jump_a, "E5 al intercambiar: B salta y A esquiva, sin activar ambas")
	PadInput.swap_bindings("jump", "dodge")       # deja A salta / B esquiva
	# conflicto en los menús (ui) es independiente del juego: A puede ser «saltar» y «confirmar»
	ok(PadInput.find_conflict("ui_accept", {"t": "b", "i": JOY_BUTTON_A}) == "" or PadInput.find_conflict("ui_accept", {"t": "b", "i": JOY_BUTTON_A}) == "ui_cancel", "E6 los grupos juego/menú no se mezclan")
	# desasignar
	PadInput.set_binding("interact", {"t": "none"})
	await _btn(JOY_BUTTON_X, true)
	ok(not Input.is_action_pressed("interact"), "E7 una acción sin asignar no se dispara con el botón anterior")
	await _btn(JOY_BUTTON_X, false)
	# restaurar
	PadInput.reset_bindings()
	await _frames(2)
	var t2 := _throws()
	await _trigger(5)
	await _frames(3)
	ok(_throws() == t2 + 1 and PadInput.label("attack") == "RT", "E8 «restaurar» devuelve RT al ataque")
	await _wait_case()
	# teclado
	PadInput.set_key("attack", KEY_K)
	var kev := InputEventKey.new()
	kev.physical_keycode = KEY_K
	kev.pressed = true
	Input.parse_input_event(kev)
	await _frames(2)
	ok(Input.is_action_pressed("attack"), "E9 la tecla reasignada (K) ejecuta el ataque")
	kev = InputEventKey.new()
	kev.physical_keycode = KEY_K
	kev.pressed = false
	Input.parse_input_event(kev)
	var kj := InputEventKey.new()
	kj.physical_keycode = KEY_J
	kj.pressed = true
	Input.parse_input_event(kj)
	await _frames(2)
	ok(not Input.is_action_pressed("attack"), "E9b la tecla antigua (J) ya no ataca")
	kj = InputEventKey.new()
	kj.physical_keycode = KEY_J
	kj.pressed = false
	Input.parse_input_event(kj)
	PadInput.reset_keys()
	await _wait_case()


# ---------------------------------------------------------------- F. navegación de menús sin tocar la pantalla
func _menu_nav_tests() -> void:
	# inventario con Y; foco dentro; cruceta + A cambian de pestaña; B cierra
	await _press(JOY_BUTTON_Y)
	await _frames(6)
	var inv := _overlay_of(InventoryUI)
	ok(inv != null, "F1 Y abre el inventario")
	var fo := get_viewport().gui_get_focus_owner()
	ok(fo != null and inv.is_ancestor_of(fo), "F1b el foco cae dentro del inventario (%s)" % _focus_text())
	var tab_syn := _btn_by_text(inv, "SINERGIAS")
	ok(tab_syn != null, "F1c existe la pestaña SINERGIAS")
	var reached := await _nav_to(tab_syn)
	var tries := 0
	ok(reached, "F2 la cruceta lleva el foco a SINERGIAS")
	await _press(JOY_BUTTON_A)
	await _frames(4)
	ok(not inv._body_items.visible, "F3 A confirma: se abre la pestaña de sinergias")
	await _press(JOY_BUTTON_B)
	await _frames(4)
	ok(_overlay_of(InventoryUI) == null and not get_tree().paused, "F4 B cierra el inventario y regresa a la partida")
	# vender/desechar con el mando
	GameState.build.reset({})
	GameState.build.add("heavy_case", 0, true)
	GameState.build.add("wide_sweep", 0, true)
	await _press(JOY_BUTTON_Y)
	await _frames(6)
	inv = _overlay_of(InventoryUI)
	var slots := inv.find_children("*", "Button", true, false).filter(func(b): return b.has_meta("upgrade_id") or (b as Button).get_meta("id", "") != "")
	info("botones de mejora detectados: %d" % slots.size())
	var disc: Button = null
	# seleccionar la primera mejora con el mando: ir al primer botón de la rejilla
	var grid_btn: Button = null
	for b in inv.find_children("*", "Button", true, false):
		if (b as Button).focus_mode == Control.FOCUS_ALL and (b as Button).is_visible_in_tree() and String(b.text) != "CERRAR" and String(b.text) != "MEJORAS" and String(b.text) != "SINERGIAS" and not String(b.text).begins_with("Categoría") and not String(b.text).begins_with("Rareza"):
			grid_btn = b
			break
	ok(grid_btn != null, "F5 las mejoras del inventario son enfocables con el mando")
	if grid_btn != null:
		grid_btn.grab_focus()
		await _frames(2)
		await _press(JOY_BUTTON_A)
		await _frames(4)
		disc = _btn_by_text(inv, "DESECHAR")
		ok(disc != null, "F5b A selecciona una mejora y aparece DESECHAR")
		if disc != null:
			disc.grab_focus()
			await _frames(2)
			var n0 := GameState.build.type_count()
			await _press(JOY_BUTTON_A)
			await _frames(4)
			var conf := _btn_by_text(inv, "CANCELAR")
			ok(conf != null, "F5c se pide confirmación antes de desechar")
			ok(get_viewport().gui_get_focus_owner() != null and conf != null and (conf.get_parent().get_parent() as Node).is_ancestor_of(get_viewport().gui_get_focus_owner()), "F5d el foco pasa al cuadro de confirmación (%s)" % _focus_text())
			await _press(JOY_BUTTON_B)       # B = Cancelar la confirmación
			await _frames(4)
			ok(GameState.build.type_count() == n0 and _overlay_of(InventoryUI) != null, "F5e B cancela la confirmación sin desechar ni cerrar el inventario")
	await _press(JOY_BUTTON_B)
	await _frames(4)
	# cartas de un cofre
	GameState.build.reset({})
	main._open_cards(0, false)
	await _frames(8)
	var cs: CardSelect = null
	for o in main._ov_root().get_children():
		if o is CardSelect:
			cs = o
	if cs == null:
		for o in main._overlays:
			if o is CardSelect:
				cs = o
	ok(cs != null, "F6 se abren las cartas del cofre")
	if cs != null:
		await _frames(30)
		ok(cs._selected == 0, "F6b con el mando la primera carta queda enfocada/seleccionada (%d)" % cs._selected)
		await _press(JOY_BUTTON_DPAD_RIGHT)
		await _frames(3)
		ok(cs._selected == 1, "F7 la cruceta pasa a la segunda carta (%d)" % cs._selected)
		await _press(JOY_BUTTON_RIGHT_SHOULDER)    # RB = ui_focus_next
		await _frames(3)
		info("RB mueve el foco a: %s" % _focus_text())
		var cards_before := int(GameState.run_stats["cards"])
		cs._select(1)
		var fo2 := cs._card_nodes[1] as Control
		fo2.grab_focus()
		await _frames(2)
		await _press(JOY_BUTTON_A)
		await _frames(4)
		ok(int(GameState.run_stats["cards"]) == cards_before + 1 and GameState.build.type_count() == 1, "F8 A confirma la carta elegida y se añade a la build (%d mejora)" % GameState.build.type_count())
	await _frames(6)
	# tienda
	main._on_shop()
	await _frames(8)
	var shop := _overlay_of(ShopUI)
	ok(shop != null, "F9 se abre la tienda")
	if shop != null:
		var fo3 := get_viewport().gui_get_focus_owner()
		ok(fo3 != null and shop.is_ancestor_of(fo3), "F9b el foco está dentro de la tienda (%s)" % _focus_text())
		await _press(JOY_BUTTON_B)
		await _frames(4)
		ok(_overlay_of(ShopUI) == null, "F9c B sale de la tienda")
	ok(not get_tree().paused, "F10 la partida sigue sin tocar la pantalla")


# ---------------------------------------------------------------- G. ajustes → CONTROLES con mando
func _controls_ui_tests() -> void:
	main._open_settings()
	await _frames(6)
	var st := _overlay_of(SettingsMenu)
	ok(st != null, "G1 se abre Ajustes")
	var open_btn: Button = st.find_child("OpenControls", true, false)
	ok(open_btn != null, "G1b hay una sección CONTROLES en los ajustes")
	open_btn.grab_focus()
	await _frames(2)
	await _press(JOY_BUTTON_A)
	await _frames(8)
	var cm: ControlsMenu = null
	for c in st.get_children():
		if c is ControlsMenu:
			cm = c
	ok(cm != null, "G2 A abre CONTROLES con el mando")
	if cm == null:
		return
	ok(cm.find_child("Tab_touch", true, false) != null and cm.find_child("Tab_pad", true, false) != null and cm.find_child("Tab_keys", true, false) != null, "G2b existen las pestañas TÁCTIL, MANDO y TECLADO")
	cm._show_tab("pad")
	await _frames(6)
	var status: Label = cm.find_child("PadStatus", true, false)
	info("estado: '%s' · dispositivos %s · pad_mode %s · pestaña %s" % [status.text if status != null else "(sin etiqueta)", str(pi.devices), str(PadInput.pad_mode), cm._tab])
	ok(status != null and status.text.contains("Mando detectado"), "G3 la pestaña MANDO muestra el mando detectado: «%s»" % (status.text if status != null else ""))
	var acts_listed := 0
	for a in PadInput.GAME_ACTIONS + PadInput.UI_ACTIONS:
		if cm.find_child("Bind_" + a, true, false) != null:
			acts_listed += 1
	ok(acts_listed == PadInput.GAME_ACTIONS.size() + PadInput.UI_ACTIONS.size(), "G4 la lista muestra las %d acciones configurables" % acts_listed)
	await _shot("p_controles_mando")
	# reasignar «Lanzar el maletín» a LB desde la interfaz, con el mando
	var bind_attack: Button = cm.find_child("Bind_attack", true, false)
	bind_attack.grab_focus()
	await _frames(2)
	await _press(JOY_BUTTON_A)
	await _frames(4)
	ok(pi.capturing and cm.find_child("CaptureBox", true, false) != null, "G5 al elegir la acción el juego espera el nuevo botón")
	await _shot("p_reasignando")
	await _frames(25)
	await _press(JOY_BUTTON_LEFT_SHOULDER)
	await _frames(6)
	ok(not pi.capturing and PadInput.binding("attack") == {"t": "b", "i": JOY_BUTTON_LEFT_SHOULDER} and bind_attack.text == "LB", "G6 pulsar LB asigna «Lanzar el maletín» a LB (botón: «%s»)" % bind_attack.text)
	# cancelar una reasignación
	cm._start_capture("dodge", "pad")
	await _frames(3)
	var cancel_b: Button = cm.find_child("CaptureCancel", true, false)
	cancel_b.pressed.emit()
	await _frames(4)
	ok(not pi.capturing and PadInput.binding("dodge") == {"t": "b", "i": JOY_BUTTON_B}, "G7 CANCELAR deja la acción como estaba")
	# cancelación por tiempo
	cm._start_capture("dodge", "pad")
	await _secs(8.6)
	ok(not pi.capturing and cm.find_child("CaptureBox", true, false) == null, "G7b si no se pulsa nada la espera se cancela sola")
	# conflicto desde la interfaz: dodge → LB (ya es «attack»)
	cm._start_capture("dodge", "pad")
	await _frames(25)
	await _press(JOY_BUTTON_LEFT_SHOULDER)
	await _frames(6)
	var swap_b: Button = cm.find_child("ConflictSwap", true, false)
	ok(swap_b != null and cm.find_child("ConflictReplace", true, false) != null and cm.find_child("ConflictCancel", true, false) != null, "G8 el aviso de conflicto ofrece intercambiar, reemplazar o cancelar")
	await _shot("p_conflicto")
	var fo := get_viewport().gui_get_focus_owner()
	ok(fo != null and fo.name.begins_with("Conflict"), "G8b el foco está en el aviso (%s)" % _focus_text())
	await _press(JOY_BUTTON_B)             # B = cancelar el conflicto
	await _frames(5)
	ok(cm.find_child("ConflictSwap", true, false) == null and PadInput.binding("dodge") == {"t": "b", "i": JOY_BUTTON_B} and PadInput.binding("attack") == {"t": "b", "i": JOY_BUTTON_LEFT_SHOULDER}, "G9 B cancela el conflicto sin cambiar nada")
	cm._start_capture("dodge", "pad")
	await _frames(25)
	await _press(JOY_BUTTON_LEFT_SHOULDER)
	await _frames(6)
	cm.find_child("ConflictSwap", true, false).pressed.emit()
	await _frames(5)
	ok(PadInput.binding("dodge") == {"t": "b", "i": JOY_BUTTON_LEFT_SHOULDER} and PadInput.binding("attack") == {"t": "b", "i": JOY_BUTTON_B}, "G10 INTERCAMBIAR intercambia los botones de las dos acciones")
	# restaurar
	var rst: Button = cm.find_child("ResetPad", true, false)
	rst.pressed.emit()
	await _frames(6)
	ok(PadInput.binding("attack") == PadInput.default_binding("attack") and PadInput.binding("dodge") == PadInput.default_binding("dodge"), "G11 «Restaurar» devuelve los valores predeterminados")
	# cambiar modo desde ajustes
	cm._show_tab("pad")
	await _frames(4)
	var mode_touch: Button = cm.find_child("Mode_touch", true, false)
	mode_touch.pressed.emit()
	await _frames(4)
	ok(not PadInput.pad_mode and not main.touch.suppressed, "G12 «SOLO TÁCTIL» desde ajustes muestra los controles táctiles aun con mando")
	cm.find_child("Mode_auto", true, false).pressed.emit()
	await _frames(4)
	ok(PadInput.pad_mode, "G12b «AUTOMÁTICO» vuelve al mando")
	# B cierra CONTROLES y luego Ajustes
	await _press(JOY_BUTTON_B)
	await _frames(5)
	ok(not is_instance_valid(cm) or cm.is_queued_for_deletion(), "G13 B cierra CONTROLES")
	await _press(JOY_BUTTON_B)
	await _frames(5)
	ok(_overlay_of(SettingsMenu) == null, "G13b B cierra Ajustes")


# ---------------------------------------------------------------- H. sala central y portal
func _lobby_nav_tests() -> void:
	await main._back_to_menu()
	await _frames(10)
	main._enter_lobby()
	var t := 0.0
	while main.state != main.St.LOBBY and t < 10.0:
		await _frames(2)
		t += 0.03
	await _secs(1.0)
	ok(main.state == main.St.LOBBY, "H1 se entra a la sala central")
	ok(PadInput.pad_mode and main.touch.suppressed, "H1b en la sala central siguen ocultos los controles táctiles")
	player = GameState.player
	var p0 := player.global_position
	await _axis(1, -1.0)
	await _secs(0.8)
	await _axis(1, 0.0)
	ok(player.global_position.distance_to(p0) > 1.5, "H2 el stick mueve al personaje por la sala (%.1f m)" % player.global_position.distance_to(p0))
	# estación de dificultad: acercarse y usar X
	var st: Interactable = main.lobby.stations["difficulty"]
	player.teleport_to(st.global_position + Vector3(0.0, 0.0, 0.5))
	await _secs(0.5)
	ok(player.interact_target == st, "H3 al acercarse la estación es el objetivo de interacción")
	ok(main.hud._prompt.text.contains("X"), "H3b el aviso muestra el botón del mando: «%s»" % main.hud._prompt.text)
	await _press(JOY_BUTTON_X)
	await _frames(8)
	var du := _overlay_of(DifficultyUI)
	ok(du != null, "H4 X abre la estación de dificultad")
	if du != null:
		var before := LoadoutDB.selected_difficulty()
		var fo := get_viewport().gui_get_focus_owner()
		ok(fo != null and du.is_ancestor_of(fo), "H4b el foco está dentro del panel (%s)" % _focus_text())
		var chosen := false
		var tries := 0
		while tries < 8 and not chosen:
			var f2 := get_viewport().gui_get_focus_owner()
			if f2 is Button and String((f2 as Button).text) == "ELEGIR" and LoadoutDB.selected_difficulty() == before:
				await _press(JOY_BUTTON_A)
				await _frames(4)
				chosen = true
			else:
				await _press(JOY_BUTTON_DPAD_DOWN)
				tries += 1
		ok(LoadoutDB.selected_difficulty() != before, "H5 se elige otra dificultad solo con el mando (%s → %s)" % [before, LoadoutDB.selected_difficulty()])
		await _press(JOY_BUTTON_B)
		await _frames(4)
		ok(_overlay_of(DifficultyUI) == null, "H6 B cierra el panel")
	# portal de nueva partida con X
	var np: Interactable = main.lobby.stations["new_run"]
	player.teleport_to(np.global_position + Vector3(0.0, 0.0, 0.5))
	await _secs(0.5)
	ok(player.interact_target == np, "H7 el portal NUEVA PARTIDA es el objetivo")
	await _press(JOY_BUTTON_X)
	await _frames(8)
	var dlg := _btn_by_text(main._ov_root(), "Sobrescribir")
	ok(dlg != null and SaveSystem.has_valid_run(), "H7b con una partida guardada se pide confirmar antes de sobrescribir")
	await _press(JOY_BUTTON_B)
	await _frames(5)
	ok(main.state == main.St.LOBBY and _btn_by_text(main._ov_root(), "Sobrescribir") == null, "H7c B cancela el aviso y sigue en la sala")
	await _press(JOY_BUTTON_X)
	await _frames(8)
	dlg = _btn_by_text(main._ov_root(), "Sobrescribir")
	if dlg != null:
		await _nav_to(dlg)
		await _press(JOY_BUTTON_A)
	t = 0.0
	while main.state != main.St.RUN and t < 12.0:
		await _frames(2)
		t += 0.04
	await _secs(1.5)
	ok(main.state == main.St.RUN, "H8 X en el portal inicia una partida sin tocar la pantalla")
	# desconectar en plena partida: reaparecen los controles
	await _conn(0, "", false)
	ok(not PadInput.pad_mode and not main.touch.suppressed and main.touch.visible, "H9 al desconectar en plena partida el juego sigue con controles táctiles")
	var sz: Vector2 = main.touch.size
	await _touch(1, Vector2(sz.x * 0.2, sz.y * 0.75), true)
	ok(main.touch.joy_active(), "H10 y el joystick táctil responde")
	await _touch(1, Vector2(sz.x * 0.2, sz.y * 0.75), false)


# ---------------------------------------------------------------- persistencia
func _persist_prepare() -> void:
	PadInput.set_binding("attack", {"t": "b", "i": JOY_BUTTON_RIGHT_SHOULDER})
	PadInput.set_binding("inventory", {"t": "b", "i": JOY_BUTTON_BACK})
	PadInput.set_key("jump", KEY_Z)
	PadInput.cfg()["look_sens"] = 1.7
	PadInput.cfg()["dead_move"] = 0.31
	PadInput.cfg()["move_stick"] = "right"
	pi.set_mode_setting("pad")
	SaveSystem.data["settings"]["joy_zone"] = 0.8
	SaveSystem.data["settings"]["joy_sens"] = 1.3
	ok(SaveSystem.save_now(), "S1 la configuración se guarda en disco")


func _stage2() -> void:
	# proceso nuevo: la configuración debe haberse cargado sola desde el archivo
	ok(PadInput.same(PadInput.binding("attack"), {"t": "b", "i": JOY_BUTTON_RIGHT_SHOULDER}), "S2 «lanzar maletín» sigue en RB tras reabrir el juego")
	ok(PadInput.same(PadInput.binding("inventory"), {"t": "b", "i": JOY_BUTTON_BACK}), "S2b «inventario» sigue en View/Share")
	ok(PadInput.keycode_for("jump") == KEY_Z, "S2c la tecla de salto sigue en Z")
	ok(is_equal_approx(float(PadInput.cfg()["look_sens"]), 1.7) and is_equal_approx(float(PadInput.cfg()["dead_move"]), 0.31) and PadInput.cfg()["move_stick"] == "right", "S2d sensibilidad, zona muerta e intercambio de sticks persisten")
	ok(is_equal_approx(float(SaveSystem.setting("joy_zone")), 0.8) and is_equal_approx(float(SaveSystem.setting("joy_sens")), 1.3), "S2e los ajustes del joystick persisten")
	ok(PadInput.pad_mode and pi.mode_setting() == "pad", "S2f el modo «solo mando» persiste")
	# y se aplicaron al InputMap sin iniciar ninguna run
	var has_rb := false
	var has_rt := false
	for ev in InputMap.action_get_events("attack"):
		if ev is InputEventJoypadButton and ev.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			has_rb = true
		if ev is InputEventJoypadMotion and ev.axis == 5:
			has_rt = true
	ok(has_rb and not has_rt, "S3 el InputMap ya usa RB para atacar (y no RT) nada más abrir")
	main._show_menu()
	await _frames(10)
	main._on_play()
	var t := 0.0
	while main.state != main.St.RUN and t < 10.0:
		await _frames(2)
		t += 0.03
	await _secs(1.0)
	ok(PadInput.same(PadInput.binding("attack"), {"t": "b", "i": JOY_BUTTON_RIGHT_SHOULDER}), "S4 empezar una run no restablece los controles")
	# limpieza
	PadInput.reset_bindings()
	PadInput.reset_keys()
	pi.set_mode_setting("auto")
	SaveSystem.data["settings"]["joy_zone"] = 1.0
	SaveSystem.data["settings"]["joy_sens"] = 1.0
	SaveSystem.save_now()
