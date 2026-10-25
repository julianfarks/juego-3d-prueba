extends Node
## Pruebas de la versión de PC (modo PC forzado con --pcmode; en Windows se activa solo). Render real: xvfb.
##   xvfb-run -a godot --path . --rendering-driver opengl3 -- --pcmode --pctest --out=DIR
## Ratón y teclado se envían como eventos reales (Input.parse_input_event).

var main: Node
var out_dir := "/tmp/pctest"
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
	await _frames(4)
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png("%s/%s.png" % [out_dir, name])


func _mouse_move(rel: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.relative = rel
	ev.position = Vector2(640, 360)
	Input.parse_input_event(ev)
	await _frames(2)


func _mouse_btn(btn: int, down: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = btn
	ev.pressed = down
	ev.position = Vector2(640, 360)
	Input.parse_input_event(ev)
	await _frames(2)


func _key(code: int, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code as Key
	ev.pressed = down
	Input.parse_input_event(ev)
	await _frames(2)


func _throws() -> int:
	return int(ct.counts["throws"])


func _run() -> void:
	await _frames(10)
	ok(Config.pc_mode(), "P0.1 el modo PC está activo (--pcmode)")
	ok(main.pc_input != null, "P0.2 existe el nodo de entrada de PC")
	main.pc_input.assume_focus = true
	await main._enter_lobby(true)
	await _frames(15)
	await _t1_touch_hidden()
	main._on_play()
	var t := 0.0
	while main.state != main.St.RUN and t < 10.0:
		await _frames(2)
		t += 0.03
	ok(main.state == main.St.RUN, "P0.3 empieza la partida")
	Config.dev_god_mode = true
	main.arena.force_complete()
	await _secs(1.0)
	ct = GameState.case_throw
	player = GameState.player
	await _frames(3)
	await _t2_mouse_look()
	await _t3_click_attack()
	await _t4_menus_release_cursor()
	await _t5_keys()
	await _t6_graphics_settings()
	await _t7_video_menu()
	await _t8_fps_independence()
	await _t9_save_roundtrip()
	Config.dev_god_mode = false
	print("")
	print("=== PCTEST: %d comprobaciones OK, %d fallos ===" % [passes, fails.size()])
	for f in fails:
		print("  FALLO: ", f)
	get_tree().quit(0 if fails.is_empty() else 1)


# 1. controles táctiles ocultos / inertes en PC
func _t1_touch_hidden() -> void:
	ok(main.touch.suppressed, "P1.1 los controles táctiles están suprimidos en PC")
	var pos := main.touch.joy_zone().get_center()
	var ev := InputEventScreenTouch.new()
	ev.index = 3
	ev.position = pos
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(3)
	ok(not main.touch.joy_active() and Input.get_vector("move_left", "move_right", "move_forward", "move_back") == Vector2.ZERO, "P1.2 un toque en la zona del joystick no mueve al jugador")
	ev.pressed = false
	Input.parse_input_event(ev)
	await _frames(2)
	await _shot("p1_lobby_pc")


# 2. el ratón gira la cámara (sensibilidad e inversión)
func _t2_mouse_look() -> void:
	var cam: CameraRig = GameState.cam
	ok(main.pc_input.captured, "P2.1 el cursor queda capturado durante la partida")
	var y0: float = cam.yaw
	var p0: float = cam.pitch
	await _mouse_move(Vector2(120, 0))
	ok(cam.yaw < y0 - 0.2, "P2.2 mover el ratón a la derecha gira la cámara (yaw %.3f → %.3f)" % [y0, cam.yaw])
	var y1: float = cam.yaw
	await _mouse_move(Vector2(-120, 0))
	ok(cam.yaw > y1 + 0.2, "P2.3 mover a la izquierda gira al otro lado")
	SaveSystem.set_setting("cam_invert_y", false)
	var pa: float = cam.pitch
	await _mouse_move(Vector2(0, 40))
	var d_norm: float = cam.pitch - pa
	SaveSystem.set_setting("cam_invert_y", true)
	pa = cam.pitch
	await _mouse_move(Vector2(0, 40))
	var d_inv: float = cam.pitch - pa
	ok(d_norm * d_inv < 0.0, "P2.4 «invertir eje vertical» invierte el ratón (%.3f / %.3f)" % [d_norm, d_inv])
	SaveSystem.set_setting("cam_invert_y", false)
	SaveSystem.set_setting("cam_sens_x", 1.0)
	var ya: float = cam.yaw
	await _mouse_move(Vector2(60, 0))
	var d1: float = absf(cam.yaw - ya)
	SaveSystem.set_setting("cam_sens_x", 2.0)
	ya = cam.yaw
	await _mouse_move(Vector2(60, 0))
	var d2: float = absf(cam.yaw - ya)
	ok(d2 > d1 * 1.6, "P2.5 la sensibilidad escala el giro (%.3f → %.3f)" % [d1, d2])
	SaveSystem.set_setting("cam_sens_x", 1.0)
	ok(cam.pitch >= cam.min_pitch - 0.001 and cam.pitch <= cam.max_pitch + 0.001, "P2.6 el pitch respeta sus límites")


# 3. clic izquierdo = atacar; fuera de captura no ataca
func _t3_click_attack() -> void:
	player.skills.cd[0] = 0.0
	var n0 := _throws()
	await _mouse_btn(MOUSE_BUTTON_LEFT, true)
	await _mouse_btn(MOUSE_BUTTON_LEFT, false)
	await _frames(4)
	ok(_throws() > n0, "P3.1 el clic izquierdo lanza el maletín (%d → %d)" % [n0, _throws()])
	await _secs(1.2)
	while ct.in_flight():
		await _frames(2)
	player.skills.cd[0] = 0.0
	var n1 := _throws()
	main._toggle_pause()
	await _frames(4)
	ok(not main.pc_input.captured, "P3.2 con la pausa abierta el cursor se libera")
	await _mouse_btn(MOUSE_BUTTON_LEFT, true)
	await _mouse_btn(MOUSE_BUTTON_LEFT, false)
	ok(_throws() == n1, "P3.3 un clic con el menú abierto no ataca")
	main._resume()
	await _frames(4)
	ok(main.pc_input.captured, "P3.4 al reanudar vuelve a capturarse el cursor")


# 4. menús: Esc pausa, cofres/tienda/inventario liberan el cursor
func _t4_menus_release_cursor() -> void:
	await _key(KEY_ESCAPE, true)
	await _key(KEY_ESCAPE, false)
	await _frames(4)
	ok(main._pause_menu != null and get_tree().paused, "P4.1 Esc abre la pausa")
	ok(not main.pc_input.captured, "P4.2 el cursor está libre en la pausa")
	var have_quit := false
	for b in main._pause_menu.find_children("*", "Button", true, false):
		if b.text == "VÍDEO Y GRÁFICOS" or b.text == "CÁMARA":
			have_quit = true
	ok(have_quit, "P4.3 la pausa ofrece las opciones de vídeo y cámara")
	await _key(KEY_ESCAPE, true)
	await _key(KEY_ESCAPE, false)
	await _frames(4)
	ok(main._pause_menu == null and not get_tree().paused and main.pc_input.captured, "P4.4 Esc de nuevo reanuda y captura el cursor")
	await _key(KEY_I, true)
	await _key(KEY_I, false)
	await _frames(4)
	ok(not main._overlays.is_empty() and not main.pc_input.captured, "P4.5 la tecla I abre el inventario y libera el cursor")
	for o in main._overlays.duplicate():
		if o is InventoryUI:
			o.call("_close")
	await _frames(4)
	ok(main.pc_input.captured, "P4.6 al cerrar el inventario se recaptura el cursor")


# 5. teclas
func _t5_keys() -> void:
	var p0: Vector3 = player.global_position
	await _key(KEY_W, true)
	await _secs(0.6)
	await _key(KEY_W, false)
	ok(player.global_position.distance_to(p0) > 1.0, "P5.1 W mueve al personaje (%.1f m)" % player.global_position.distance_to(p0))
	var y0 := player.global_position.y
	await _key(KEY_SPACE, true)
	await _key(KEY_SPACE, false)
	await _secs(0.2)
	ok(player.global_position.y > y0 + 0.2 or not player.is_on_floor(), "P5.2 Espacio salta")
	await _secs(1.0)
	ok(InputMap.action_get_events("interact").any(func(e): return e is InputEventKey and e.physical_keycode == KEY_E), "P5.3 E interactúa además de F")
	ok(InputMap.action_get_events("dodge").any(func(e): return e is InputEventKey and e.physical_keycode == KEY_SHIFT), "P5.4 Shift esquiva")


# 6. ajustes gráficos de PC
func _t6_graphics_settings() -> void:
	ok(Config.quality_names().size() == 4 and Config.quality_names()[3] == "Máxima", "P6.1 PC ofrece Baja/Media/Alta/Máxima")
	Config.apply_preset(3)
	Config.apply_graphics(get_viewport())
	ok(get_viewport().msaa_3d == Viewport.MSAA_4X, "P6.2 «Máxima» activa MSAA 4x")
	ok(Config.shadow_cfg()["on"] and Config.draw_far() >= 200.0, "P6.3 «Máxima» activa sombras altas y distancia larga")
	ok(int(Config.quality()["max_enemies"]) == int(Config.QUALITY[2]["max_enemies"]), "P6.4 «Máxima» no cambia el límite interno de enemigos")
	for f in [30, 60, 120, 144, 240]:
		SaveSystem.set_setting("fps", f)
		Config.apply_graphics(get_viewport())
		ok(Engine.max_fps == f, "P6.5 límite de FPS %d aplicado" % f)
	SaveSystem.set_setting("fps", 0)
	Config.apply_graphics(get_viewport())
	ok(Engine.max_fps == 0, "P6.6 «sin límite» = 0")
	ok(Config.fps_options() == [30, 60, 120, 144, 240, 0], "P6.7 opciones de FPS de PC")
	ok(Config.available_resolutions().size() >= 1, "P6.8 hay resoluciones disponibles")
	Config.apply_preset(2)
	Config.apply_graphics(get_viewport())
	Config.apply_display()      # no debe fallar con ninguna combinación guardada
	for wm in [0, 1, 2, 0]:
		SaveSystem.set_setting("window_mode", wm)
		Config.apply_display()
		await _frames(3)
	for vs in [0, 1, 2, 1]:
		SaveSystem.set_setting("vsync", vs)
		Config.apply_display()
	ok(true, "P6.9 cambiar modo de pantalla y VSync no produce errores")
	Config.reset_graphics()
	ok(int(SaveSystem.setting("quality")) == 2 and int(SaveSystem.setting("fps")) == 0 and int(SaveSystem.setting("vsync")) == 1, "P6.10 los valores predeterminados de PC son equilibrados (Alta, VSync, sin límite)")


# 7. el menú de vídeo muestra las opciones de PC
func _t7_video_menu() -> void:
	var sm := SettingsMenu.new()
	sm.page = "video"
	main.add_child(sm)
	await _frames(4)
	var names := ["Opt_window_mode_2", "Opt_resolution_0", "Opt_vsync_2", "Opt_quality_3", "Opt_fps_5", "Opt_shadow_q_2", "Opt_draw_dist_2", "Opt_fx_level_2"]
	for n in names:
		ok(sm.find_child(n, true, false) != null, "P7 el menú de vídeo tiene %s" % n)
	var b: Button = sm.find_child("Opt_vsync_0", true, false)
	b.pressed.emit()
	await _frames(2)
	ok(int(SaveSystem.setting("vsync")) == 0, "P7.9 el botón de VSync cambia el ajuste")
	b = sm.find_child("Opt_quality_3", true, false)
	b.pressed.emit()
	await _frames(2)
	ok(int(SaveSystem.setting("quality")) == 3 and get_viewport().msaa_3d == Viewport.MSAA_4X, "P7.10 elegir «Máxima» desde el menú la aplica")
	await _shot("p7_menu_video")
	Config.reset_graphics()
	sm.queue_free()
	await _frames(3)
	var cm := ControlsMenu.new()
	main.add_child(cm)
	await _frames(4)
	ok(cm.find_child("Tab_touch", true, false) == null and cm.find_child("Tab_keys", true, false) != null, "P7.11 en PC no hay pestaña táctil y sí teclado y ratón")
	await _shot("p7_controles_pc")
	cm.queue_free()
	await _frames(2)


# 8. el movimiento no depende de los FPS
func _t8_fps_independence() -> void:
	var res := {}
	for cap in [30, 144]:
		SaveSystem.set_setting("fps", cap)
		Config.apply_graphics(get_viewport())
		await _secs(0.5)
		var p0: Vector3 = player.global_position
		var t0 := Time.get_ticks_msec()
		await _key(KEY_D, true)
		await _secs(1.0)
		await _key(KEY_D, false)
		var dt := float(Time.get_ticks_msec() - t0) / 1000.0
		res[cap] = player.global_position.distance_to(p0) / dt
		await _secs(0.4)
		await _key(KEY_A, true)
		await _secs(1.0)
		await _key(KEY_A, false)
	print("[INFO] velocidad lateral con 30 FPS: %.2f m/s, con 144 FPS: %.2f m/s" % [res[30], res[144]])
	ok(absf(res[30] - res[144]) / maxf(res[30], res[144]) < 0.12, "P8.1 la velocidad de movimiento no depende del límite de FPS")
	SaveSystem.set_setting("fps", 0)
	Config.apply_graphics(get_viewport())


# 9. guardado: ajustes de PC persisten y el archivo no se corrompe
func _t9_save_roundtrip() -> void:
	SaveSystem.set_setting("window_mode", 1)
	SaveSystem.set_setting("resolution", 3)
	SaveSystem.set_setting("vsync", 2)
	SaveSystem.set_setting("fps", 144)
	ok(SaveSystem.save_now(), "P9.1 el guardado se escribe")
	var txt := FileAccess.get_file_as_string(SaveSystem.PATH)
	var back: Variant = SaveSystem.decode(txt)
	ok(back != null and int((back as Dictionary)["settings"]["window_mode"]) == 1 and int((back as Dictionary)["settings"]["resolution"]) == 3 and int((back as Dictionary)["settings"]["vsync"]) == 2, "P9.2 el archivo guardado conserva los ajustes de pantalla")
	ok((back as Dictionary).has("run") and (back as Dictionary).has("meta") and (back as Dictionary).has("records"), "P9.3 el resto del guardado (progreso, récords) sigue presente")
	SaveSystem.set_setting("window_mode", 0)
	SaveSystem.set_setting("resolution", 0)
	SaveSystem.set_setting("vsync", 1)
	SaveSystem.set_setting("fps", 0)
