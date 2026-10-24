extends Node
## Pruebas de ARRANQUE y PAUSA (v0.9.0): el juego abre directamente en el Vestíbulo del Bufete, la pausa es un menú completo
## y los ajustes de vídeo/audio/controles cambian el motor de verdad y persisten. Render real (xvfb), SIN tocar nada de main
## salvo lo que haría un jugador: toques reales (InputEventScreenTouch/Drag) y botones de mando reales.
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 -- --starttest --stage=1 --out=DIR
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 -- --starttest --stage=2 --out=DIR
## main.gd NO retira el arranque normal con esta bandera: este nodo observa el arranque en frío real.

var main: Node
var out_dir := "/tmp/starttest"
var stage := 1
var fails: Array = []
var passes := 0
var player: Player
var _first_state := -99


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


func _finish() -> void:
	print("[RESULT] arranque etapa %d: %d ok, %d fallos" % [stage, passes, fails.size()])
	for f in fails:
		print("  FALLO: ", f)
	get_tree().quit(1 if fails.size() > 0 else 0)


# ---------------------------------------------------------------- entrada real
func _touch(idx: int, pos: Vector2, down: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = idx
	ev.position = pos
	ev.pressed = down
	Input.parse_input_event(ev)
	await _frames(2)


func _drag(idx: int, pos: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = idx
	ev.position = pos
	ev.relative = Vector2(1, 0)
	Input.parse_input_event(ev)
	await _frames(2)


func _tap(pos: Vector2, idx := 9) -> void:
	await _touch(idx, pos, true)
	await _touch(idx, pos, false)
	await _frames(3)


## Toca el centro de un control (como lo haría un dedo).
func _tap_ctl(c: Control) -> void:
	# si está dentro de un panel con desplazamiento, se desplaza hasta verlo (como haría el jugador)
	var n: Node = c.get_parent()
	while n != null:
		if n is ScrollContainer:
			(n as ScrollContainer).ensure_control_visible(c)
			await _frames(3)
			break
		n = n.get_parent()
	await _tap(c.get_global_rect().get_center())


func _joy(btn: int, down: bool) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = btn
	ev.pressed = down
	Input.parse_input_event(ev)
	await _frames(2)


func _press(btn: int) -> void:
	await _joy(btn, true)
	await _joy(btn, false)
	await _frames(3)


func _wait_state(st: int, timeout := 12.0) -> bool:
	var t := 0.0
	while main.state != st and t < timeout:
		await _secs(0.1)
		t += 0.1
	return main.state == st


func _overlay_of(cls: Variant) -> Node:
	for o in main._overlays:
		if is_instance_valid(o) and is_instance_of(o, cls):
			return o
	return null


func _btn(root: Node, node_name: String) -> Button:
	if root == null:
		return null
	return root.find_child(node_name, true, false) as Button


func _btn_text(root: Node, txt: String) -> Button:
	for b in root.find_children("*", "Button", true, false):
		if String((b as Button).text).strip_edges().to_lower() == txt.to_lower() and (b as Button).is_visible_in_tree():
			return b
	return null


func _pause_btn() -> Control:
	return main.hud.get_node("PauseButton")


func _throws() -> int:
	return int(GameState.case_throw.counts["throws"])


func _wait_idle() -> void:
	var t := 0.0
	while GameState.case_throw.in_flight() and t < 8.0:
		await _frames(2)
		t += 0.05
	await _frames(3)


func _sun() -> DirectionalLight3D:
	var l := get_tree().get_nodes_in_group("sun_light")
	return l[0] as DirectionalLight3D if not l.is_empty() else null


## Abre la pausa tocando el botón «II» de la esquina (toque real).
func _open_pause() -> void:
	await _tap_ctl(_pause_btn())
	await _frames(6)


func _close_top_overlay() -> void:
	var top: Control = main._overlays.back() if not main._overlays.is_empty() else null
	if top != null:
		var b := _btn_text(top, "volver")
		if b == null:
			b = _btn_text(top, "cerrar")
		if b != null:
			await _tap_ctl(b)
		else:
			top.queue_free()
	await _frames(6)


# ---------------------------------------------------------------- flujo
func _run() -> void:
	await _frames(2)
	_first_state = main.state
	if stage == 2:
		await _stage2()
	elif stage == 3:
		await _stage3()
	elif stage == 4:
		await _stage4()
	else:
		await _stage1()
	_finish()


func _stage1() -> void:
	await _t_boot()
	await _t_move_and_stations()
	await _t_pause_lobby()
	await _t_video()
	await _t_audio_controls()
	await _t_resume_and_run()
	await _t_pad()
	await _t_persist_setup()


# ================================================================ 1-3. arranque en frío
func _t_boot() -> void:
	ok(String(ProjectSettings.get_setting("application/run/main_scene")) == "res://scenes/main.tscn", "A1 la escena principal del proyecto es main.tscn")
	ok(not ResourceLoader.exists("res://scripts/ui/main_menu.gd"), "A2 el script del menú inicial ya no existe")
	var has_cls := false
	for c in ProjectSettings.get_global_class_list():
		if String(c["class"]) == "MainMenu":
			has_cls = true
	ok(not has_cls, "A3 no queda ninguna clase MainMenu")
	# el estado justo al arrancar (primer frame de la prueba) ya es el vestíbulo, nunca un menú
	ok(_first_state == main.St.LOBBY, "A4 en el primer frame el estado ya es VESTÍBULO (no hay estado de menú)")
	ok(await _wait_state(main.St.LOBBY, 6.0), "A5 el juego queda en el Vestíbulo del Bufete")
	await _secs(1.2)
	ok(main.lobby != null and main.lobby.name == "Lobby" and main.lobby.stations.size() == 9, "A6 es la escena 3D real del vestíbulo con sus 9 estaciones")
	ok(main.world.get_node_or_null("MenuStage") == null, "A7 no existe el escenario del menú del personaje sobre la plataforma")
	var menu_btn := false
	for b in main._ov_root().find_children("*", "Button", true, false):
		var tx := String((b as Button).text)
		if tx.begins_with("NUEVA PARTIDA") or tx == "Sala Central" or tx == "El Despacho" or tx == "Récords":
			menu_btn = true
	ok(main._ov_root().get_child_count() == 0 and not menu_btn, "A8 no hay ningún panel ni botón del menú inicial en pantalla")
	ok(main.player.visible and main.hud.visible and main.touch.visible, "A9 el personaje, el HUD y los controles táctiles están visibles")
	await _shot("01_arranque_vestibulo")
	# punto de aparición seguro
	player = GameState.player
	var sp: Vector3 = main.lobby.spawn_position()
	ok(player.global_position.distance_to(sp) < 0.6, "B1 el personaje aparece en el punto previsto (%s)" % str(player.global_position))
	ok(player.is_on_floor() and player.global_position.y > -0.1 and player.global_position.y < 1.0, "B2 está sobre el suelo, no debajo ni flotando (y=%.2f)" % player.global_position.y)
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	var pq := PhysicsPointQueryParameters3D.new()
	pq.position = player.global_position + Vector3(0, 1.0, 0)
	pq.collision_mask = Config.L_WORLD
	ok(space.intersect_point(pq).is_empty(), "B3 no aparece dentro de una estación ni de un muro")
	var near_station := false
	for st in main.lobby.stations.values():
		if player.global_position.distance_to((st as Node3D).global_position) < float((st as Interactable).radius):
			near_station = true
	ok(not near_station and player.interact_target == null, "B4 no aparece dentro del radio de ninguna estación")
	var rq := PhysicsRayQueryParameters3D.create(player.global_position + Vector3(0, 1.0, 0), player.global_position + Vector3(0, 1.0, -4.0), Config.L_WORLD)
	ok(space.intersect_ray(rq).is_empty(), "B5 no mira de frente a una pared (4 m libres hacia delante)")
	var cam_z: float = main.cam.cam.global_position.z
	ok(main.cam.yaw == 0.0 and cam_z > player.global_position.z + 3.0 and float(main.cam.get("_cur_dist")) > 5.0, "B6 la cámara está detrás del personaje y sin obstáculos (distancia %.1f)" % float(main.cam.get("_cur_dist")))


# ================================================================ 3-5. moverse y estaciones
func _t_move_and_stations() -> void:
	var tc: TouchControls = main.touch
	var zone := tc.joy_zone()
	var p0 := player.global_position
	var start := zone.get_center()
	await _touch(1, start, true)
	ok(tc.joy_active(), "C1 un toque en la zona del joystick lo activa")
	await _drag(1, start + Vector2(0, -70))
	await _secs(0.9)
	var moved := player.global_position.distance_to(p0)
	ok(moved > 2.5, "C2 el personaje recorre el vestíbulo con el joystick (%.1f m)" % moved)
	await _touch(1, start + Vector2(0, -70), false)
	await _secs(0.7)
	var v := Vector2(player.velocity.x, player.velocity.z).length()
	ok(v < 0.5 and not tc.joy_active(), "C3 al soltar el joystick se detiene (%.2f m/s)" % v)
	# estaciones de equipamiento, dificultad, despacho y archivo: con el botón táctil de interacción
	for pair in [["equip:weapon", EquipStationUI], ["difficulty", DifficultyUI], ["meta", MetaScreen], ["stats", StatsPanel]]:
		var id: String = pair[0]
		var st: Interactable = main.lobby.stations[id]
		player.teleport_to(st.global_position + Vector3(0.0, 0.0, 0.5))
		await _secs(0.5)
		var targeted := player.interact_target == st
		await _tap(tc._center("interact"), 6)
		await _secs(0.5)
		var ui := _overlay_of(pair[1])
		ok(targeted and ui != null, "D-%s la estación se interactúa y abre su interfaz" % id)
		if ui != null:
			ui.queue_free()
		await _secs(0.4)
	ok(not get_tree().paused, "D5 al cerrar las interfaces de las estaciones el juego sigue en marcha")
	player.teleport_to(main.lobby.spawn_position())
	await _secs(0.4)


# ================================================================ 6. pausa en el vestíbulo
func _t_pause_lobby() -> void:
	var tc: TouchControls = main.touch
	await _open_pause()
	var pm: PauseMenu = main._pause_menu
	ok(pm != null and is_instance_valid(pm) and get_tree().paused, "E1 el botón de pausa de la esquina abre el menú y pausa el juego")
	ok(pm.context == "lobby", "E2 en el vestíbulo el menú es el de vestíbulo")
	var want := ["resume", "settings", "video", "audio", "controls", "records", "meta"]
	var missing := want.filter(func(i): return _btn(pm, "Pause_" + i) == null)
	ok(missing.is_empty(), "E3 muestra CONTINUAR, AJUSTES, VÍDEO Y GRÁFICOS, AUDIO, CONTROLES, RÉCORDS y EL DESPACHO (faltan %s)" % str(missing))
	ok(_btn(pm, "Pause_save") == null and _btn(pm, "Pause_inventory") == null and _btn(pm, "Pause_leave") == null, "E4 no muestra opciones de run (guardar, inventario, volver) en el vestíbulo")
	await _shot("02_pausa_vestibulo")
	# los botones del menú no provocan movimiento ni ataques: se toca donde están los controles táctiles
	var t0 := _throws()
	var p0 := player.global_position
	await _tap(tc._center("attack"), 4)
	await _touch(2, tc.joy_zone().get_center(), true)
	ok(not tc.joy_active(), "F1 con la pausa abierta un toque en la zona del joystick no lo activa")
	await _touch(2, tc.joy_zone().get_center(), false)
	await _secs(0.3)
	ok(_throws() == t0 and player.global_position.distance_to(p0) < 0.1, "F2 con la pausa abierta no se lanza el maletín ni se mueve el personaje")
	# RÉCORDS desde la pausa
	await _tap_ctl(_btn(pm, "Pause_records"))
	await _frames(6)
	ok(_overlay_of(StatsPanel) != null, "G1 RÉCORDS abre las estadísticas desde la pausa")
	await _close_top_overlay()
	ok(main._pause_menu != null and is_instance_valid(main._pause_menu) and _overlay_of(StatsPanel) == null, "G2 al cerrar los récords se vuelve a la pausa")
	# EL DESPACHO desde la pausa
	await _tap_ctl(_btn(main._pause_menu, "Pause_meta"))
	await _frames(6)
	ok(_overlay_of(MetaScreen) != null, "G3 EL DESPACHO abre las mejoras permanentes desde la pausa")
	await _close_top_overlay()
	ok(_overlay_of(MetaScreen) == null and main._pause_menu != null, "G4 se cierra y se vuelve a la pausa")
	# cerrar con CONTINUAR
	await _tap_ctl(_btn(main._pause_menu, "Pause_resume"))
	await _frames(8)
	ok(main._pause_menu == null and not get_tree().paused, "H1 CONTINUAR cierra la pausa y reanuda el juego")
	# el control se recupera: el joystick vuelve a funcionar
	var q0 := player.global_position
	var c := tc.joy_zone().get_center()
	await _touch(1, c, true)
	await _drag(1, c + Vector2(70, 0))
	await _secs(0.7)
	await _touch(1, c + Vector2(70, 0), false)
	ok(player.global_position.distance_to(q0) > 2.0, "H2 tras cerrar la pausa el personaje responde al joystick (%.1f m)" % player.global_position.distance_to(q0))
	player.teleport_to(main.lobby.spawn_position())
	await _secs(0.3)


# ================================================================ 7. VÍDEO Y GRÁFICOS: cambia el motor de verdad
func _opt(page: Node, key: String, i: int) -> Button:
	return _btn(page, "Opt_%s_%d" % [key, i])


func _t_video() -> void:
	await _open_pause()
	await _tap_ctl(_btn(main._pause_menu, "Pause_video"))
	await _frames(6)
	var page: SettingsMenu = _overlay_of(SettingsMenu)
	ok(page != null and page.page == "video" and page.find_child("PageTitle", true, false).text == "VÍDEO Y GRÁFICOS", "I1 VÍDEO Y GRÁFICOS abre su página")
	await _shot("03_video")
	# escala de renderizado
	await _tap_ctl(_opt(page, "render_scale", 0))
	await _frames(4)
	ok(is_equal_approx(get_viewport().scaling_3d_scale, 0.5) and is_equal_approx(float(SaveSystem.setting("render_scale")), 0.5), "I2 escala de renderizado 50 %% cambia el viewport real (%.2f)" % get_viewport().scaling_3d_scale)
	await _shot("04_escala_50")
	await _tap_ctl(_opt(page, "render_scale", 3))
	await _frames(4)
	ok(is_equal_approx(get_viewport().scaling_3d_scale, 1.0), "I3 escala 100 %% restablece el viewport (%.2f)" % get_viewport().scaling_3d_scale)
	# sombras
	var sun := _sun()
	ok(sun != null, "I4 el sol del vestíbulo está registrado para ajustes gráficos")
	await _tap_ctl(_opt(page, "shadow_q", 2))
	await _frames(4)
	ok(sun.shadow_enabled and is_equal_approx(sun.directional_shadow_max_distance, 60.0), "I5 sombras Altas: la luz proyecta sombras a 60 m")
	await _shot("05_sombras_altas")
	await _tap_ctl(_opt(page, "shadow_q", 1))
	await _frames(4)
	ok(sun.shadow_enabled and is_equal_approx(sun.directional_shadow_max_distance, 32.0), "I6 sombras Bajas: sombras con alcance corto (32 m)")
	await _tap_ctl(_opt(page, "shadow_q", 0))
	await _frames(4)
	ok(not sun.shadow_enabled, "I7 sombras Apagadas: la luz ya no proyecta sombras")
	# distancia de dibujado
	await _tap_ctl(_opt(page, "draw_dist", 0))
	await _frames(4)
	ok(is_equal_approx(main.cam.cam.far, 90.0), "I8 distancia Corta: el plano lejano de la cámara baja a 90 (%.0f)" % main.cam.cam.far)
	await _tap_ctl(_opt(page, "draw_dist", 2))
	await _frames(4)
	ok(is_equal_approx(main.cam.cam.far, 220.0), "I9 distancia Larga: 220 (%.0f)" % main.cam.cam.far)
	# efectos
	await _tap_ctl(_opt(page, "fx_level", 0))
	await _frames(4)
	ok(GameState.fx.max_fx == 24 and is_equal_approx(GameState.fx.particle_scale, 0.5), "I10 efectos Reducidos: 24 efectos y mitad de partículas")
	await _tap_ctl(_opt(page, "fx_level", 2))
	await _frames(4)
	ok(GameState.fx.max_fx == 80 and is_equal_approx(GameState.fx.particle_scale, 1.0), "I11 efectos Completos: 80 efectos y partículas al 100 %%")
	# FPS: solo se ofrecen los límites que el dispositivo puede cumplir
	var fo := Config.fps_options()
	ok(_opt(page, "fps", fo.size() - 1) != null and _opt(page, "fps", fo.size()) == null, "I12 solo se ofrecen los límites de FPS compatibles %s" % str(fo))
	await _tap_ctl(_opt(page, "fps", 0))
	await _frames(4)
	ok(Engine.max_fps == 30, "I13 límite de FPS 30 aplicado al motor (%d)" % Engine.max_fps)
	await _tap_ctl(_opt(page, "fps", 1))
	await _frames(4)
	ok(Engine.max_fps == 60, "I14 límite de FPS 60 aplicado al motor (%d)" % Engine.max_fps)
	# preset de calidad: cambia todos los ajustes sueltos
	await _tap_ctl(_opt(page, "quality", 0))
	await _frames(4)
	ok(is_equal_approx(get_viewport().scaling_3d_scale, 0.67) and not sun.shadow_enabled and is_equal_approx(main.cam.cam.far, 90.0) and GameState.fx.max_fx == 24, "I15 calidad Baja: escala 0.67, sin sombras, distancia corta y efectos reducidos")
	ok(String(page.find_child("PresetNote", true, false).text) == "", "I16 con el preset puro no aparece «Personalizado»")
	await _tap_ctl(_opt(page, "quality", 2))
	await _frames(4)
	ok(is_equal_approx(get_viewport().scaling_3d_scale, 1.0) and sun.shadow_enabled and is_equal_approx(main.cam.cam.far, 220.0) and GameState.fx.max_fx == 80, "I17 calidad Alta: escala 1.0, sombras, distancia larga y efectos completos")
	await _tap_ctl(_opt(page, "shadow_q", 0))
	await _frames(4)
	ok(String(page.find_child("PresetNote", true, false).text).begins_with("Personalizado"), "I18 al cambiar un ajuste suelto aparece «Personalizado»")
	# restaurar valores predeterminados
	await _tap_ctl(_btn(page, "ResetVideo"))
	await _frames(6)
	ok(int(SaveSystem.setting("quality")) == 1 and is_equal_approx(get_viewport().scaling_3d_scale, 0.85) and not sun.shadow_enabled and is_equal_approx(main.cam.cam.far, 140.0) and GameState.fx.max_fx == 48 and Engine.max_fps == 60, "I19 restaurar deja los valores predeterminados (Media, 0.85, 140 m, 48 efectos, 60 FPS)")
	ok(_opt(page, "quality", 1).button_pressed and _opt(page, "render_scale", 2).button_pressed, "I20 la interfaz refleja los valores restaurados")
	await _close_top_overlay()
	ok(main._pause_menu != null and _overlay_of(SettingsMenu) == null, "I21 «Volver» regresa a la pausa")
	await _tap_ctl(_btn(main._pause_menu, "Pause_resume"))
	await _frames(8)


# ================================================================ 8. AUDIO y CONTROLES
func _bus_db(n: String) -> float:
	return AudioServer.get_bus_volume_db(AudioServer.get_bus_index(n))


func _t_audio_controls() -> void:
	await _open_pause()
	await _tap_ctl(_btn(main._pause_menu, "Pause_audio"))
	await _frames(6)
	var page: SettingsMenu = _overlay_of(SettingsMenu)
	ok(page != null and page.page == "audio", "J1 AUDIO abre su página")
	var sm: HSlider = page.find_child("Slider_music", true, false)
	var sc: HSlider = page.find_child("Slider_combat_sfx", true, false)
	var combat_before := _bus_db("Combat")
	var r := sm.get_global_rect()
	await _tap(Vector2(r.position.x + r.size.x * 0.3, r.get_center().y))
	await _frames(4)
	ok(absf(float(SaveSystem.setting("music")) - 0.3) < 0.15 and absf(_bus_db("Music") - linear_to_db(float(SaveSystem.setting("music")))) < 0.05, "J2 tocar el deslizador de música cambia el bus de música (%.2f → %.1f dB)" % [float(SaveSystem.setting("music")), _bus_db("Music")])
	ok(absf(_bus_db("Combat") - combat_before) < 0.01, "J3 la música no altera el volumen de los efectos de combate")
	var r2 := sc.get_global_rect()
	var music_before := _bus_db("Music")
	await _tap(Vector2(r2.position.x + r2.size.x * 0.5, r2.get_center().y))
	await _frames(4)
	ok(absf(float(SaveSystem.setting("combat_sfx")) - 0.5) < 0.15 and absf(_bus_db("Combat") - linear_to_db(float(SaveSystem.setting("combat_sfx")))) < 0.05 and absf(_bus_db("Music") - music_before) < 0.01, "J4 los efectos se ajustan por separado de la música")
	await _shot("06_audio")
	await _tap_ctl(_btn(page, "ResetAudio"))
	await _frames(4)
	ok(is_equal_approx(float(SaveSystem.setting("music")), 0.7) and absf(_bus_db("Music") - linear_to_db(0.7)) < 0.05, "J5 restaurar audio vuelve a 70 %% de música")
	await _close_top_overlay()
	# CONTROLES desde la pausa
	await _tap_ctl(_btn(main._pause_menu, "Pause_controls"))
	await _frames(8)
	var cm: ControlsMenu = _overlay_of(ControlsMenu)
	ok(cm != null and cm.find_child("Tab_touch", true, false) != null and cm.find_child("Tab_pad", true, false) != null and cm.find_child("Tab_keys", true, false) != null, "K1 CONTROLES abre las pestañas TÁCTIL, MANDO y TECLADO desde la pausa")
	var js: HSlider = cm.find_child("S_joy_sens", true, false)
	var before := float(SaveSystem.setting("joy_sens"))
	var r3 := js.get_global_rect()
	await _tap(Vector2(r3.position.x + r3.size.x * 0.95, r3.get_center().y))
	await _frames(4)
	ok(float(SaveSystem.setting("joy_sens")) > before + 0.3, "K2 la sensibilidad del joystick se cambia de verdad (%.2f → %.2f)" % [before, float(SaveSystem.setting("joy_sens"))])
	await _shot("07_controles")
	await _close_top_overlay()
	ok(main._pause_menu != null and _overlay_of(ControlsMenu) == null, "K3 «Volver» regresa a la pausa")
	await _tap_ctl(_btn(main._pause_menu, "Pause_resume"))
	await _frames(8)


# ================================================================ 9. portal → run → pausa de run
func _t_resume_and_run() -> void:
	var tc: TouchControls = main.touch
	var st: Interactable = main.lobby.stations["new_run"]
	player.teleport_to(st.global_position + Vector3(0.0, 0.0, 0.5))
	await _secs(0.5)
	ok(player.interact_target == st, "L1 al acercarse al portal NUEVA PARTIDA es el objetivo de interacción")
	await _tap(tc._center("interact"), 6)
	ok(await _wait_state(main.St.RUN, 8.0), "L2 el portal inicia una run")
	await _secs(2.0)
	ok(GameState.in_run and main.arena.phase != Arena.Phase.IDLE and main.player.visible, "L3 la run está en marcha (arena %d)" % (GameState.arena_index + 1))
	Config.dev_god_mode = true
	# ataque táctil funciona
	var t0 := _throws()
	await _tap(tc._center("attack"), 4)
	await _frames(4)
	ok(_throws() == t0 + 1, "L4 el botón de ataque lanza el maletín en la run")
	await _wait_idle()
	# pausa de run
	await _open_pause()
	var pm: PauseMenu = main._pause_menu
	ok(pm != null and pm.context == "run" and get_tree().paused, "M1 en la run la pausa es la de partida")
	var want := ["resume", "inventory", "build", "save", "settings", "video", "audio", "controls", "leave"]
	var missing := want.filter(func(i): return _btn(pm, "Pause_" + i) == null)
	ok(missing.is_empty(), "M2 muestra CONTINUAR, INVENTARIO, MI BUILD, GUARDAR PARTIDA, AJUSTES, VÍDEO, AUDIO, CONTROLES y VOLVER AL VESTÍBULO (faltan %s)" % str(missing))
	ok(_btn(pm, "Pause_records") == null and not _btn(pm, "Pause_save").disabled, "M3 no muestra opciones de vestíbulo y GUARDAR PARTIDA está disponible")
	await _shot("08_pausa_run")
	# INVENTARIO desde la pausa
	await _tap_ctl(_btn(pm, "Pause_inventory"))
	await _frames(8)
	ok(_overlay_of(InventoryUI) != null, "M4 INVENTARIO abre las mejoras de la run desde la pausa")
	await _close_top_overlay()
	ok(_overlay_of(InventoryUI) == null and main._pause_menu != null, "M5 al cerrar el inventario se vuelve a la pausa")
	# GUARDAR PARTIDA
	SaveSystem.clear_run()
	await _tap_ctl(_btn(main._pause_menu, "Pause_save"))
	await _frames(8)
	ok(SaveSystem.has_valid_run(), "M6 GUARDAR PARTIDA guarda la run (arena %d)" % (int(SaveSystem.get_run().get("arena_index", -1)) + 1))
	ok(main._pause_menu != null, "M6b guardar no cierra la pausa")
	# ajustes gráficos durante la run: afectan a las luces de la arena
	await _tap_ctl(_btn(main._pause_menu, "Pause_video"))
	await _frames(6)
	var page: SettingsMenu = _overlay_of(SettingsMenu)
	await _tap_ctl(_opt(page, "shadow_q", 2))
	await _frames(4)
	var suns := get_tree().get_nodes_in_group("sun_light")
	var all_on := not suns.is_empty()
	for sn in suns:
		if not (sn as DirectionalLight3D).shadow_enabled:
			all_on = false
	ok(all_on, "M7 las sombras Altas se aplican a la luz de la arena durante la run (%d luces)" % suns.size())
	await _tap_ctl(_btn(page, "ResetVideo"))
	await _frames(4)
	await _close_top_overlay()
	# reanudar: el control se recupera
	await _tap_ctl(_btn(main._pause_menu, "Pause_resume"))
	await _frames(8)
	ok(main._pause_menu == null and not get_tree().paused and main.state == main.St.RUN, "N1 CONTINUAR reanuda la run")
	var p0 := player.global_position
	var c := tc.joy_zone().get_center()
	await _touch(1, c, true)
	await _drag(1, c + Vector2(0, -70))
	await _secs(0.7)
	await _touch(1, c + Vector2(0, -70), false)
	ok(player.global_position.distance_to(p0) > 1.5, "N2 el personaje se mueve tras reanudar (%.1f m)" % player.global_position.distance_to(p0))
	var t1 := _throws()
	await _tap(tc._center("attack"), 4)
	await _frames(4)
	ok(_throws() == t1 + 1, "N3 y vuelve a atacar al primer toque")
	await _wait_idle()
	# VOLVER AL VESTÍBULO pide confirmación
	await _open_pause()
	await _tap_ctl(_btn(main._pause_menu, "Pause_leave"))
	await _frames(6)
	var box: Node = main._pause_menu.find_child("LeaveBox", true, false)
	ok(box != null and _btn(box, "Leave_save") != null and _btn(box, "Leave_abandon") != null and _btn(box, "Leave_cancel") != null, "O1 VOLVER AL VESTÍBULO muestra una confirmación (guardar, abandonar, cancelar)")
	await _tap_ctl(_btn(box, "Leave_cancel"))
	await _frames(6)
	ok(main.state == main.St.RUN and main._pause_menu != null and main._pause_menu.find_child("LeaveBox", true, false) == null, "O2 cancelar no abandona la run")
	await _tap_ctl(_btn(main._pause_menu, "Pause_leave"))
	await _frames(6)
	box = main._pause_menu.find_child("LeaveBox", true, false)
	var idx_before := GameState.arena_index
	await _tap_ctl(_btn(box, "Leave_save"))
	ok(await _wait_state(main.St.LOBBY, 10.0), "O3 GUARDAR Y VOLVER lleva al vestíbulo")
	await _secs(1.5)
	ok(SaveSystem.has_valid_run() and int(SaveSystem.get_run()["arena_index"]) == idx_before and main.lobby.stations["continue"].enabled, "O4 la partida queda guardada y el portal CONTINUAR se activa")
	# continuar desde el menú de pausa del vestíbulo
	await _open_pause()
	var cs := _btn(main._pause_menu, "Pause_continue_saved")
	ok(cs != null, "O5 la pausa del vestíbulo ofrece CONTINUAR PARTIDA GUARDADA")
	await _tap_ctl(cs)
	ok(await _wait_state(main.St.RUN, 10.0), "O6 continuar la partida guardada vuelve a la run")
	await _secs(1.5)
	ok(GameState.arena_index == idx_before, "O7 la run retomada conserva la arena (%d)" % (GameState.arena_index + 1))
	# ABANDONAR RUN
	Config.dev_god_mode = true
	await _open_pause()
	await _tap_ctl(_btn(main._pause_menu, "Pause_leave"))
	await _frames(6)
	box = main._pause_menu.find_child("LeaveBox", true, false)
	await _tap_ctl(_btn(box, "Leave_abandon"))
	await _secs(1.5)
	var es: Node = _overlay_of(EndScreen)
	ok(es != null and _btn(es, "End_lobby") != null and _btn(es, "End_settings") != null and not SaveSystem.has_valid_run(), "P1 abandonar muestra la pantalla de fin con VOLVER AL VESTÍBULO y AJUSTES y borra el guardado")
	await _shot("09_pantalla_fin")
	await _tap_ctl(_btn(es, "End_settings"))
	await _frames(6)
	ok(_overlay_of(SettingsMenu) != null, "P2 la pantalla de fin permite abrir AJUSTES")
	await _close_top_overlay()
	await _tap_ctl(_btn(es, "End_lobby"))
	ok(await _wait_state(main.St.LOBBY, 10.0), "P3 VOLVER AL VESTÍBULO desde la pantalla de fin")
	await _secs(1.2)
	ok(not get_tree().paused and main._overlays.is_empty(), "P4 el vestíbulo queda jugable (sin pausa ni paneles)")
	player = GameState.player
	Config.dev_god_mode = false


# ================================================================ 10. mando: pausa y navegación
func _t_pad() -> void:
	var pi: PadInput = main.pad
	pi.debug_names[0] = "Xbox Wireless Controller"
	Input.joy_connection_changed.emit(0, true)
	await _frames(6)
	ok(PadInput.pad_mode and main.touch.suppressed, "Q1 al conectar un mando se ocultan los controles táctiles")
	await _press(JOY_BUTTON_START)
	await _frames(6)
	ok(main._pause_menu != null and is_instance_valid(main._pause_menu) and get_tree().paused, "Q2 Start abre la pausa con el mando")
	var fo := get_viewport().gui_get_focus_owner()
	ok(fo != null and main._pause_menu.is_ancestor_of(fo), "Q3 el foco queda dentro del menú de pausa (%s)" % (fo.name if fo != null else "nada"))
	# navegar con la cruceta hasta VÍDEO Y GRÁFICOS y entrar con A
	var guard := 0
	var target := _btn(main._pause_menu, "Pause_video")
	while guard < 14:
		fo = get_viewport().gui_get_focus_owner()
		if fo == target:
			break
		var fr := fo.get_global_rect()
		var tr := target.get_global_rect()
		if tr.position.y > fr.position.y + 10.0:
			await _press(JOY_BUTTON_DPAD_DOWN)
		elif tr.position.x > fr.position.x + 10.0:
			await _press(JOY_BUTTON_DPAD_RIGHT)
		elif tr.position.x < fr.position.x - 10.0:
			await _press(JOY_BUTTON_DPAD_LEFT)
		else:
			await _press(JOY_BUTTON_DPAD_UP)
		guard += 1
	fo = get_viewport().gui_get_focus_owner()
	ok(fo == target, "Q4 la cruceta recorre el menú de pausa hasta VÍDEO Y GRÁFICOS (%d pasos)" % guard)
	await _press(JOY_BUTTON_A)
	await _frames(8)
	var page: SettingsMenu = _overlay_of(SettingsMenu)
	ok(page != null and page.page == "video", "Q5 A abre VÍDEO Y GRÁFICOS")
	await _press(JOY_BUTTON_B)
	await _frames(8)
	ok(_overlay_of(SettingsMenu) == null and main._pause_menu != null, "Q6 B vuelve a la pausa")
	await _press(JOY_BUTTON_B)
	await _frames(8)
	ok(main._pause_menu == null and not get_tree().paused, "Q7 B en la pausa la cierra y reanuda")
	# Start con un submenú abierto cierra primero el submenú
	await _press(JOY_BUTTON_START)
	await _frames(6)
	main._open_settings("audio")
	await _frames(6)
	await _press(JOY_BUTTON_START)
	await _frames(8)
	ok(_overlay_of(SettingsMenu) == null and main._pause_menu != null, "Q8 Start con un submenú abierto lo cierra antes que la pausa")
	await _press(JOY_BUTTON_START)
	await _frames(8)
	ok(main._pause_menu == null and not get_tree().paused, "Q9 Start vuelve a cerrar la pausa")
	# desconectar: vuelven los controles táctiles
	Input.joy_connection_changed.emit(0, false)
	await _frames(6)
	ok(not PadInput.pad_mode and not main.touch.suppressed, "Q10 al desconectar el mando vuelven los controles táctiles")


# ================================================================ guardado para la etapa 2
func _t_persist_setup() -> void:
	# valores distintos de los predeterminados a través de la interfaz real
	await _open_pause()
	await _tap_ctl(_btn(main._pause_menu, "Pause_video"))
	await _frames(6)
	var page: SettingsMenu = _overlay_of(SettingsMenu)
	await _tap_ctl(_opt(page, "render_scale", 1))
	await _tap_ctl(_opt(page, "shadow_q", 1))
	await _tap_ctl(_opt(page, "draw_dist", 0))
	await _tap_ctl(_opt(page, "fx_level", 2))
	await _tap_ctl(_opt(page, "fps", 0))
	await _frames(4)
	await _close_top_overlay()
	await _tap_ctl(_btn(main._pause_menu, "Pause_audio"))
	await _frames(6)
	page = _overlay_of(SettingsMenu)
	var sm: HSlider = page.find_child("Slider_music", true, false)
	sm.value = 0.35
	await _frames(3)
	await _close_top_overlay()
	await _tap_ctl(_btn(main._pause_menu, "Pause_controls"))
	await _frames(6)
	var cm: ControlsMenu = _overlay_of(ControlsMenu)
	(cm.find_child("S_joy_sens", true, false) as HSlider).value = 1.3
	await _frames(3)
	await _close_top_overlay()
	await _tap_ctl(_btn(main._pause_menu, "Pause_resume"))
	await _frames(6)
	# dejamos una partida guardada para comprobar que al reabrir hay una forma clara de continuarla
	var f := FileAccess.open(out_dir + "/stage1.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"music": float(SaveSystem.setting("music")), "joy_sens": float(SaveSystem.setting("joy_sens"))}))
	f.close()
	SaveSystem.save_now()
	info("etapa 1 guardada: escala %s sombras %s distancia %s efectos %s fps %s música %s" % [SaveSystem.setting("render_scale"), SaveSystem.setting("shadow_q"), SaveSystem.setting("draw_dist"), SaveSystem.setting("fx_level"), SaveSystem.setting("fps"), SaveSystem.setting("music")])


# ================================================================ etapa 2: reiniciar la aplicación
func _stage2() -> void:
	var f := FileAccess.open(out_dir + "/stage1.json", FileAccess.READ)
	var e: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	ok(_first_state == main.St.LOBBY, "R1 al reabrir la aplicación se está directamente en el vestíbulo")
	ok(await _wait_state(main.St.LOBBY, 6.0), "R2 el vestíbulo es la primera pantalla jugable otra vez")
	await _secs(1.5)
	ok(is_equal_approx(get_viewport().scaling_3d_scale, 0.67), "R3 la escala de renderizado guardada se aplica sola (%.2f)" % get_viewport().scaling_3d_scale)
	ok(Engine.max_fps == 30, "R4 el límite de FPS guardado se aplica solo (%d)" % Engine.max_fps)
	ok(is_equal_approx(main.cam.cam.far, 90.0), "R5 la distancia de dibujado guardada se aplica sola (%.0f)" % main.cam.cam.far)
	var sun := _sun()
	ok(sun != null and sun.shadow_enabled and is_equal_approx(sun.directional_shadow_max_distance, 32.0), "R6 las sombras Bajas guardadas se aplican a la luz del vestíbulo")
	ok(GameState.fx.max_fx == 80, "R7 el nivel de efectos guardado se aplica solo (%d)" % GameState.fx.max_fx)
	ok(absf(float(SaveSystem.setting("music")) - float(e["music"])) < 0.001 and absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")) - linear_to_db(float(e["music"]))) < 0.05, "R8 el volumen de música guardado se aplica al bus")
	ok(absf(float(SaveSystem.setting("joy_sens")) - float(e["joy_sens"])) < 0.001, "R9 la sensibilidad del joystick persiste (%.2f)" % float(SaveSystem.setting("joy_sens")))
	# la interfaz de ajustes refleja lo guardado
	await _open_pause()
	await _tap_ctl(_btn(main._pause_menu, "Pause_video"))
	await _frames(6)
	var page: SettingsMenu = _overlay_of(SettingsMenu)
	ok(_opt(page, "render_scale", 1).button_pressed and _opt(page, "shadow_q", 1).button_pressed and _opt(page, "draw_dist", 0).button_pressed and _opt(page, "fx_level", 2).button_pressed and _opt(page, "fps", 0).button_pressed, "R10 la página de vídeo muestra las opciones guardadas")
	ok(String(page.find_child("PresetNote", true, false).text).begins_with("Personalizado"), "R11 y marca la calidad como personalizada")
	await _shot("10_video_tras_reiniciar")
	await _close_top_overlay()
	await _tap_ctl(_btn(main._pause_menu, "Pause_resume"))
	await _frames(6)
	# restablecemos para no contaminar otras ejecuciones
	Config.reset_graphics()
	SaveSystem.set_setting("music", 0.7)
	SaveSystem.set_setting("joy_sens", 1.0)
	SaveSystem.save_now()


# ================================================================ etapa 3: guardado de una versión anterior (sin ajustes sueltos)
## Antes de arrancar se escribe un guardado «antiguo» con la calidad ALTA elegida y sin sombras/distancia/efectos/escala.
func _stage3() -> void:
	ok(await _wait_state(main.St.LOBBY, 6.0), "S1 un guardado antiguo también abre directamente en el vestíbulo")
	await _secs(1.2)
	ok(int(SaveSystem.setting("quality")) == 2 and int(SaveSystem.setting("shadow_q")) == 2 and int(SaveSystem.setting("draw_dist")) == 2 and int(SaveSystem.setting("fx_level")) == 2 and is_equal_approx(float(SaveSystem.setting("render_scale")), 1.0), "S2 los ajustes sueltos parten del preset ALTA que tenía elegido")
	var sun := _sun()
	ok(sun != null and sun.shadow_enabled and is_equal_approx(main.cam.cam.far, 220.0) and is_equal_approx(get_viewport().scaling_3d_scale, 1.0), "S3 y se aplican al motor (sombras, 220 m, escala 1.0)")
	ok(is_equal_approx(float(SaveSystem.setting("music")), 0.4), "S4 el resto de ajustes antiguos se conserva (música 0.4)")


# ================================================================ etapa 4: cerrar la pausa con el mando no debe saltar ni esquivar
func _watch_player(frames: int) -> Dictionary:
	var out := {"max_vy": -99.0, "dodged": false, "moved": 0.0}
	var p0 := player.global_position
	for i in frames:
		await get_tree().physics_frame
		out["max_vy"] = maxf(out["max_vy"], player.velocity.y)
		if float(player.get("_dodge_t")) > 0.0:
			out["dodged"] = true
	out["moved"] = player.global_position.distance_to(p0)
	return out


func _stage4() -> void:
	ok(await _wait_state(main.St.LOBBY, 6.0), "U0 vestíbulo al arrancar")
	await _secs(1.2)
	player = GameState.player
	main.pad.debug_names[0] = "Xbox Wireless Controller"
	Input.joy_connection_changed.emit(0, true)
	await _frames(6)
	# A sobre CONTINUAR
	await _press(JOY_BUTTON_START)
	await _frames(6)
	var fo := get_viewport().gui_get_focus_owner()
	ok(fo != null and fo.name == "Pause_resume", "U1 la pausa abre con el foco en CONTINUAR")
	await _joy(JOY_BUTTON_A, true)
	await _joy(JOY_BUTTON_A, false)
	var w := await _watch_player(20)
	ok(main._pause_menu == null and not get_tree().paused, "U2 A cierra la pausa")
	ok(w["max_vy"] < 2.0, "U3 al confirmar con A en la pausa el personaje NO salta (vy máx %.1f)" % w["max_vy"])
	await _secs(0.6)
	# B para cerrar
	await _press(JOY_BUTTON_START)
	await _frames(6)
	await _joy(JOY_BUTTON_B, true)
	await _joy(JOY_BUTTON_B, false)
	w = await _watch_player(20)
	ok(main._pause_menu == null and not get_tree().paused, "U4 B cierra la pausa")
	ok(not w["dodged"] and w["moved"] < 0.3, "U5 al cancelar con B en la pausa el personaje NO esquiva (movió %.2f m)" % w["moved"])
	await _secs(0.6)
	# lo mismo dentro de un submenú: A en VOLVER y luego B hasta salir
	await _press(JOY_BUTTON_START)
	await _frames(6)
	main._open_settings("audio")
	await _frames(8)
	await _joy(JOY_BUTTON_B, true)
	await _joy(JOY_BUTTON_B, false)
	await _frames(6)
	await _joy(JOY_BUTTON_B, true)
	await _joy(JOY_BUTTON_B, false)
	w = await _watch_player(20)
	ok(main._pause_menu == null and not w["dodged"] and w["moved"] < 0.3, "U6 B dos veces (submenú y pausa) no provoca esquiva")
	# un salto REAL con A después sí funciona
	await _secs(0.4)
	await _joy(JOY_BUTTON_A, true)
	w = await _watch_player(8)
	await _joy(JOY_BUTTON_A, false)
	ok(w["max_vy"] > 4.0, "U7 con el juego en marcha, A sí salta (vy máx %.1f)" % w["max_vy"])
	Input.joy_connection_changed.emit(0, false)
	await _frames(4)
