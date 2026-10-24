extends Node
## Pruebas de CÁMARA (v0.10.0): distancia por defecto, página CÁMARA de Ajustes (táctil y mando), efecto inmediato,
## persistencia entre dos procesos, colisión contra muros y suavidad en movimiento. Render real (xvfb).
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 -- --cameratest --stage=1 --out=DIR
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 -- --cameratest --stage=2 --out=DIR
## Etapa 1 deja valores no predeterminados guardados; etapa 2 (proceso nuevo) comprueba que se han cargado y se aplican.
## Nota: el juego arranca como siempre (Vestíbulo) y esta prueba observa; la entrada es real (toques, botones de mando).

const OLD_DIST := 6.4            # distancia por defecto de la versión anterior
const OLD_PITCH_DEG := 24.0      # inclinación (0.42 rad) de la versión anterior
const OLD_HEIGHT := 1.7

var main: Node
var out_dir := "/tmp/cameratest"
var stage := 1
var only := ""
var fails: Array = []
var passes := 0
var player: Player
var arena: Arena


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


func _pframes(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _secs(t: float) -> void:
	await get_tree().create_timer(t, true, false, true).timeout


func _shot(name: String) -> void:
	await _frames(4)
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png("%s/%s.png" % [out_dir, name])


func _finish() -> void:
	print("[RESULT] cámara etapa %d: %d ok, %d fallos" % [stage, passes, fails.size()])
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


func _drag(idx: int, pos: Vector2, rel: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = idx
	ev.position = pos
	ev.relative = rel
	Input.parse_input_event(ev)
	await _frames(1)


func _tap(pos: Vector2, idx := 9) -> void:
	await _touch(idx, pos, true)
	await _touch(idx, pos, false)
	await _frames(3)


func _tap_ctl(c: Control) -> void:
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


func _act(action: String, down: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = down
	Input.parse_input_event(ev)
	await _frames(1)


func _btn(root: Node, node_name: String) -> Button:
	return root.find_child(node_name, true, false) as Button if root != null else null


func _overlay_of(cls: Variant) -> Node:
	for o in main._overlays:
		if is_instance_valid(o) and is_instance_of(o, cls):
			return o
	return null


# ---------------------------------------------------------------- utilidades de cámara
func _cam() -> CameraRig:
	return main.cam


func _set_cam(dist: float, height: float, pitch_deg: float) -> void:
	SaveSystem.set_setting("cam_dist", dist)
	SaveSystem.set_setting("cam_height", height)
	SaveSystem.set_setting("cam_pitch", pitch_deg)
	Config.apply_camera()


func _head_feet_px() -> Vector2:
	var c := _cam().cam
	var feet := c.unproject_position(player.global_position)
	var head := c.unproject_position(player.global_position + Vector3(0, 1.8, 0))
	return Vector2(feet.y - head.y, head.x)


## Distancia (m) hacia delante del jugador a la que cae, sobre el suelo, el píxel de la fila 'row' (fracción de alto) de la pantalla.
func _terrain_ahead_m(row := 0.3) -> float:
	var c := _cam().cam
	var vs := get_viewport().get_visible_rect().size
	var o := c.project_ray_origin(Vector2(vs.x * 0.5, vs.y * row))
	var d := c.project_ray_normal(Vector2(vs.x * 0.5, vs.y * row))
	var gy := player.global_position.y
	if d.y >= -0.001:
		return 999.0                 # el borde superior ya mira al horizonte: se ve todo hasta el fondo
	var t := (gy - o.y) / d.y
	var p := o + d * t
	return Vector2(p.x - player.global_position.x, p.z - player.global_position.z).length()


func _setup_arena(idx: int, clean: bool) -> void:
	await main._begin_arena(idx, true)
	await _pframes(4)
	arena = main.arena
	arena.phase = Arena.Phase.IDLE
	arena._queue.clear()
	for e in arena.active.duplicate():
		if is_instance_valid(e) and e.alive:
			e.invuln_t = 0.0
			e.take_damage(e.hp * 20.0 + 20.0, {"src": "boss_death", "silent": true})
	if clean:
		for ch in arena.world_root.get_children():
			if ch is Node3D and not (ch is MeshInstance3D) and ch.name != "WallCollider":
				for i in range(1, arena.circles.size()):
					var c: Vector3 = arena.circles[i]
					if absf(ch.position.x - c.x) < 0.06 and absf(ch.position.z - c.y) < 0.06:
						ch.queue_free()
						break
	await _pframes(4)


func _put_player(x: float, z: float) -> void:
	player.teleport_to(Vector3(x, Terrain.ground_y(x, z) + 0.3, z))
	player.iframes = 999.0
	_cam().snap_to_target()


func _box(cx: float, cz: float, sx: float, sy: float, sz: float) -> StaticBody3D:
	var sb := PropsFactory.static_body(Vector3(sx, sy, sz), Vector3(0, sy * 0.5, 0))
	sb.position = Vector3(cx, Terrain.ground_y(cx, cz), cz)
	arena.world_root.add_child(sb)
	return sb


# ================================================================== flujo
func _run() -> void:
	await _frames(4)
	if stage == 2:
		await _stage2()
	else:
		await _stage1()
	_finish()


func _start_run() -> void:
	var t := 0.0
	while main.state != main.St.LOBBY and t < 10.0:
		await _secs(0.1)
		t += 0.1
	await _secs(1.0)
	main._on_play()
	t = 0.0
	while main.state != main.St.RUN and t < 10.0:
		await _secs(0.1)
		t += 0.1
	Config.dev_god_mode = true
	SaveSystem.data["settings"]["auto_attack"] = false
	player = GameState.player


func _want(sec: String) -> bool:
	return only == "" or only.split(",").has(sec)


func _stage1() -> void:
	# --- valores por defecto con partida nueva (sin guardado) ---
	var d := Config.CAM_DIST
	ok(float(SaveSystem.setting("cam_dist")) == float(d["def"]) and float(SaveSystem.setting("cam_height")) == float(Config.CAM_HEIGHT["def"]) and float(SaveSystem.setting("cam_pitch")) == float(Config.CAM_PITCH["def"]), "C0 con guardado nuevo los ajustes de cámara son los predeterminados (%.1f m · %.1f m · %.0f°)" % [float(SaveSystem.setting("cam_dist")), float(SaveSystem.setting("cam_height")), float(SaveSystem.setting("cam_pitch"))])
	await _start_run()
	ok(main.state == main.St.RUN, "C0b empieza la partida")
	await _setup_arena(1, true)
	_put_player(0, 0)
	await _secs(1.6)
	if _want("farther"):
		await _t_default_farther()
	if _want("visibility"):
		await _t_enemy_visibility()
	if _want("page"):
		await _t_settings_page()
	if _want("look"):
		await _t_look_sens_invert()
	if _want("walls"):
		await _t_walls()
	if _want("motion"):
		await _t_motion()
	if only == "":
		await _t_persist_setup()


# ================================================================== C1: más lejos que antes
func _t_default_farther() -> void:
	var cam := _cam()
	Config.reset_camera()
	await _secs(1.6)
	var real := (cam.cam.global_position - (player.global_position + Vector3(0, cam.pivot_height, 0))).length()
	var m_new := _head_feet_px()
	var ahead_new := _terrain_ahead_m()
	await _shot("c1_nueva")
	_set_cam(OLD_DIST, OLD_HEIGHT, OLD_PITCH_DEG)
	cam.shoulder = 0.55
	await _secs(1.6)
	var m_old := _head_feet_px()
	var ahead_old := _terrain_ahead_m()
	var real_old := (cam.cam.global_position - (player.global_position + Vector3(0, cam.pivot_height, 0))).length()
	await _shot("c1_antigua")
	Config.reset_camera()
	await _secs(1.2)
	var vh := get_viewport().get_visible_rect().size.y
	info("distancia real cámara↔pivote: nueva %.1f m · antigua %.1f m" % [real, real_old])
	info("altura del abogado en pantalla: nueva %.0f px (%.1f%% de la pantalla) · antigua %.0f px (%.1f%%)" % [m_new.x, m_new.x / vh * 100.0, m_old.x, m_old.x / vh * 100.0])
	info("terreno visible por delante hasta el 30%% superior de la pantalla: nueva %.1f m · antigua %.1f m" % [ahead_new, ahead_old])
	ok(real > real_old + 2.5 and real >= 9.0, "C1a la cámara por defecto está más lejos que la anterior (%.1f m frente a %.1f m)" % [real, real_old])
	ok(m_new.x / vh >= 0.08 and m_new.x < m_old.x, "C1b el abogado sigue siendo reconocible: ocupa %.1f%% de la altura de pantalla (antes %.1f%%)" % [m_new.x / vh * 100.0, m_old.x / vh * 100.0])
	ok(ahead_new > ahead_old + 1.5, "C1c se ve más terreno por delante (%.1f m frente a %.1f m)" % [ahead_new, ahead_old])
	ok(cam.distance >= 9.0 and cam.distance <= 10.5, "C1d el valor de distancia del rig es el nuevo por defecto (%.1f)" % cam.distance)


func _enemies_ring(r: float, a0: float, a1: float, n: int) -> Array:
	var es: Array = []
	for i in n:
		var a := lerpf(a0, a1, float(i) / maxf(1.0, float(n - 1)))
		var f := _cam().forward_flat()
		var v := f.rotated(Vector3.UP, a) * r
		var e: Enemy = arena._spawn_enemy("thief", player.global_position + v)
		e.aggro_range = 999.0
		e.set_physics_process(false)        # quietos: solo se mira si están a la vista
		es.append(e)
	return es


func _visible_count(es: Array) -> int:
	var n := 0
	var c := _cam().cam
	for e in es:
		var p: Vector3 = e.global_position + Vector3(0, 1.0, 0)
		if c.is_position_in_frustum(p):
			n += 1
	return n


func _t_enemy_visibility() -> void:
	var cam := _cam()
	Config.reset_camera()
	cam.yaw = 0.0
	await _secs(1.2)
	# enemigos que se acercan desde todos los lados a 7 m del jugador y una fila adelantada a 12 m
	var ring := _enemies_ring(7.0, -PI, PI * 0.75, 8)
	var front := _enemies_ring(12.0, -0.7, 0.7, 5)
	await _secs(0.3)
	var v_new := _visible_count(ring) + _visible_count(front)
	var vr_new := _visible_count(ring)
	var vf_new := _visible_count(front)
	_set_cam(OLD_DIST, OLD_HEIGHT, OLD_PITCH_DEG)
	await _secs(1.4)
	var v_old := _visible_count(ring) + _visible_count(front)
	Config.reset_camera()
	await _secs(1.2)
	info("enemigos a la vista (13 colocados: 8 en anillo a 7 m, 5 delante a 12 m): nueva %d (anillo %d, delante %d) · antigua %d" % [v_new, vr_new, vf_new, v_old])
	ok(v_new >= v_old and vf_new == 5, "C5 la cámara no impide ver a los enemigos que se acercan: ve %d (antes %d) y toda la fila delantera (%d/5)" % [v_new, v_old, vf_new])
	for e in ring + front:
		if is_instance_valid(e) and e.alive:
			e.invuln_t = 0.0
			e.take_damage(e.hp * 20.0 + 20.0, {"src": "boss_death", "silent": true})
	await _secs(1.2)


# ================================================================== C2/C3: página CÁMARA
func _t_settings_page() -> void:
	var cam := _cam()
	Config.reset_camera()
	await _secs(0.6)
	var pb: Control = main.hud.get_node("PauseButton")
	await _tap_ctl(pb)
	await _frames(6)
	ok(get_tree().paused and main._pause_menu != null, "C2a el menú de pausa se abre con un toque")
	var pcam := _btn(main._pause_menu, "Pause_camera")
	ok(pcam != null and pcam.text == "CÁMARA", "C2b el menú de pausa tiene el botón CÁMARA")
	await _tap_ctl(pcam)
	await _frames(8)
	var page: SettingsMenu = _overlay_of(SettingsMenu)
	var title := page.find_child("PageTitle", true, false) as Label if page != null else null
	ok(page != null and page.page == "camera" and title != null and title.text == "CÁMARA", "C2c se abre la sección CÁMARA dentro de Ajustes")
	if page == null:
		return
	ok(get_tree().paused and not main._pause_menu.visible, "C2d la sección se ve sobre la escena (el menú de pausa se aparta para ver la cámara)")
	await _shot("c2_pagina_camara")
	# --- distancia: + / − con toques reales ---
	var base_d := float(SaveSystem.setting("cam_dist"))
	var real_before := (cam.cam.global_position - (player.global_position + Vector3(0, cam.pivot_height, 0))).length()
	await _tap_ctl(_btn(page, "Cam_cam_dist_plus"))
	await _tap_ctl(_btn(page, "Cam_cam_dist_plus"))
	await _tap_ctl(_btn(page, "Cam_cam_dist_plus"))
	var d1 := float(SaveSystem.setting("cam_dist"))
	ok(absf((d1 - base_d) - 1.2) < 0.05 and absf(cam.distance - d1) < 0.01, "C3a ALEJAR (+) aplica al instante: %.1f → %.1f m y el rig usa %.1f" % [base_d, d1, cam.distance])
	await _secs(1.4)
	var real1 := (cam.cam.global_position - (player.global_position + Vector3(0, cam.pivot_height, 0))).length()
	ok(real1 > real_before + 0.8, "C3b con el juego en pausa la cámara se aleja de verdad mientras se edita (%.1f → %.1f m)" % [real_before, real1])
	await _tap_ctl(_btn(page, "Cam_cam_dist_minus"))
	await _tap_ctl(_btn(page, "Cam_cam_dist_minus"))
	ok(float(SaveSystem.setting("cam_dist")) < d1 - 0.7, "C2e ACERCAR (−) reduce la distancia (%.1f m)" % float(SaveSystem.setting("cam_dist")))
	# --- altura ---
	var h0 := float(SaveSystem.setting("cam_height"))
	for i in 3:
		await _tap_ctl(_btn(page, "Cam_cam_height_plus"))
	ok(float(SaveSystem.setting("cam_height")) > h0 + 0.25 and absf(cam.pivot_height - float(SaveSystem.setting("cam_height"))) < 0.01, "C2f SUBIR aumenta la altura y se aplica al instante (%.1f → %.1f m)" % [h0, float(SaveSystem.setting("cam_height"))])
	for i in 5:
		await _tap_ctl(_btn(page, "Cam_cam_height_minus"))
	ok(float(SaveSystem.setting("cam_height")) < h0 - 0.1, "C2g BAJAR reduce la altura (%.1f m)" % float(SaveSystem.setting("cam_height")))
	# --- inclinación ---
	var p0 := float(SaveSystem.setting("cam_pitch"))
	var pitch_rad0 := cam.pitch
	for i in 4:
		await _tap_ctl(_btn(page, "Cam_cam_pitch_plus"))
	ok(float(SaveSystem.setting("cam_pitch")) > p0 + 6.0 and cam.pitch < pitch_rad0 - 0.1, "C2h la inclinación aumenta y la cámara se pica de inmediato (%.0f° → %.0f°)" % [p0, float(SaveSystem.setting("cam_pitch"))])
	# --- deslizador con un toque real en el extremo derecho / izquierdo ---
	var sl := page.find_child("Slider_cam_dist", true, false) as HSlider
	var r := sl.get_global_rect()
	await _tap(Vector2(r.position.x + r.size.x - 3.0, r.get_center().y))
	ok(absf(float(SaveSystem.setting("cam_dist")) - float(Config.CAM_DIST["max"])) < 0.6, "C2i tocar el extremo del deslizador de distancia lleva al máximo (%.1f m)" % float(SaveSystem.setting("cam_dist")))
	await _tap(Vector2(r.position.x + 3.0, r.get_center().y))
	ok(absf(float(SaveSystem.setting("cam_dist")) - float(Config.CAM_DIST["min"])) < 0.6, "C2j y el otro extremo al mínimo (%.1f m)" % float(SaveSystem.setting("cam_dist")))
	# --- límites: muchas pulsaciones no sobrepasan min/max ---
	for i in 60:
		SaveSystem.set_setting("cam_dist", 1000.0)
		Config.apply_camera()
		break
	ok(cam.distance <= float(Config.CAM_DIST["max"]) + 0.001, "C2k un valor guardado fuera de rango se recorta al máximo (%.1f ≤ %.1f)" % [cam.distance, float(Config.CAM_DIST["max"])])
	SaveSystem.set_setting("cam_dist", -5.0)
	SaveSystem.set_setting("cam_height", 99.0)
	SaveSystem.set_setting("cam_pitch", 0.0)
	Config.apply_camera()
	ok(cam.distance >= float(Config.CAM_DIST["min"]) - 0.001 and cam.pivot_height <= float(Config.CAM_HEIGHT["max"]) + 0.001 and rad_to_deg(-cam.pitch) >= float(Config.CAM_PITCH["min"]) - 0.5, "C2l mínimos y máximos: distancia %.1f ≥ 5, altura %.1f ≤ 3.2, inclinación %.0f° ≥ 15°" % [cam.distance, cam.pivot_height, rad_to_deg(-cam.pitch)])
	# --- mando: se conecta uno (como en la prueba de arranque) y se usa foco + A y flechas ---
	var pi: PadInput = main.pad
	pi.debug_names[0] = "Xbox Wireless Controller"
	Input.joy_connection_changed.emit(0, true)
	await _frames(6)
	_set_cam(9.0, 1.7, 30.0)
	page.call("_sync")
	var plus := _btn(page, "Cam_cam_dist_plus")
	plus.grab_focus()
	await _frames(2)
	var before := float(SaveSystem.setting("cam_dist"))
	await _press(JOY_BUTTON_A)
	ok(float(SaveSystem.setting("cam_dist")) > before + 0.3, "C2m con mando: botón A sobre ALEJAR (+) sube la distancia (%.1f → %.1f)" % [before, float(SaveSystem.setting("cam_dist"))])
	var hs := page.find_child("Slider_cam_height", true, false) as HSlider
	hs.grab_focus()
	await _frames(2)
	var hb := float(SaveSystem.setting("cam_height"))
	await _press(JOY_BUTTON_DPAD_RIGHT)
	await _press(JOY_BUTTON_DPAD_RIGHT)
	ok(float(SaveSystem.setting("cam_height")) > hb + 0.05, "C2n con mando: ► sobre el deslizador de altura la sube (%.2f → %.2f)" % [hb, float(SaveSystem.setting("cam_height"))])
	await _press(JOY_BUTTON_DPAD_LEFT)
	await _press(JOY_BUTTON_DPAD_LEFT)
	await _press(JOY_BUTTON_DPAD_LEFT)
	ok(float(SaveSystem.setting("cam_height")) < hb, "C2o con mando: ◄ la baja")
	# navegación con cruceta desde el primer foco hasta el botón Restablecer
	var guard := 0
	while guard < 30 and not (get_viewport().gui_get_focus_owner() != null and get_viewport().gui_get_focus_owner().name == "ResetCamera"):
		await _press(JOY_BUTTON_DPAD_DOWN)
		guard += 1
	var fo := get_viewport().gui_get_focus_owner()
	ok(fo != null and fo.name == "ResetCamera", "C2p con mando se llega con la cruceta al botón Restablecer (%d pulsaciones)" % guard)
	_set_cam(12.0, 2.4, 45.0)
	SaveSystem.set_setting("cam_sens_x", 2.0)
	await _press(JOY_BUTTON_A)
	var back := float(SaveSystem.setting("cam_dist")) == float(Config.CAM_DIST["def"]) and float(SaveSystem.setting("cam_height")) == float(Config.CAM_HEIGHT["def"]) and float(SaveSystem.setting("cam_pitch")) == float(Config.CAM_PITCH["def"]) and float(SaveSystem.setting("cam_sens_x")) == 1.0
	ok(back and absf(cam.distance - float(Config.CAM_DIST["def"])) < 0.01, "C2q Restablecer (con mando) devuelve distancia, altura, inclinación y sensibilidad a los valores por defecto")
	# --- Volver cierra la página y devuelve al menú de pausa, y el juego sigue ---
	await _tap_ctl(_btn(page, "Close"))
	await _frames(6)
	# se desconecta el mando para volver a los controles táctiles
	Input.joy_connection_changed.emit(0, false)
	await _frames(6)
	ok(not PadInput.pad_mode and not main.touch.suppressed, "C2r0 al desconectar el mando vuelven los controles táctiles")
	ok(_overlay_of(SettingsMenu) == null and main._pause_menu != null and main._pause_menu.visible, "C2r «Volver» cierra CÁMARA y reaparece el menú de pausa")
	await _tap_ctl(_btn(main._pause_menu, "Pause_resume"))
	await _frames(6)
	ok(not get_tree().paused, "C2s se reanuda la partida")


# ================================================================== sensibilidad e inversión (entrada táctil real)
## Punto de la mitad derecha que no cae sobre un botón de acción ni sobre la interfaz (donde un dedo mueve la cámara).
func _free_look_pos() -> Vector2:
	var tc: TouchControls = main.touch
	var vs := get_viewport().get_visible_rect().size
	for fy in [0.5, 0.42, 0.58, 0.35, 0.65]:
		for fx in [0.68, 0.6, 0.76, 0.84]:
			var q := Vector2(vs.x * fx, vs.y * fy)
			if tc._button_at(q) == "" and not tc._over_ui(q) and not tc.in_joy_zone(q) and q.x >= vs.x * TouchControls.CAM_X:
				return q
	return Vector2(vs.x * 0.7, vs.y * 0.5)


func _look_drag(dx: float, dy: float) -> void:
	# arrastre real con un dedo en la mitad derecha de la pantalla (zona de cámara)
	var p := _free_look_pos()
	await _touch(3, p, true)
	for i in 5:
		p += Vector2(dx, dy) / 5.0
		await _drag(3, p, Vector2(dx, dy) / 5.0)
	await _touch(3, p, false)
	await _frames(2)


func _t_look_sens_invert() -> void:
	var cam := _cam()
	Config.reset_camera()
	cam.yaw = 0.0
	await _frames(3)
	var y0 := cam.yaw
	var p0 := cam.pitch
	await _look_drag(100.0, 60.0)
	var dyaw1 := cam.yaw - y0
	var dpit1 := cam.pitch - p0
	info("arrastre (100,60) con sensibilidad 1.0: Δyaw %.3f rad, Δpitch %.3f rad" % [dyaw1, dpit1])
	ok(absf(dyaw1) > 0.01 and absf(dpit1) > 0.01, "C6a un arrastre táctil gira la cámara en horizontal y vertical")
	# sensibilidad x2 en horizontal y x0.5 en vertical
	SaveSystem.set_setting("cam_sens_x", 2.0)
	SaveSystem.set_setting("cam_sens_y", 0.5)
	cam.yaw = 0.0
	cam.pitch = p0
	await _frames(3)
	await _look_drag(100.0, 60.0)
	var dyaw2 := cam.yaw
	var dpit2 := cam.pitch - p0
	ok(absf(dyaw2 / dyaw1 - 2.0) < 0.25, "C6b sensibilidad horizontal ×2 duplica el giro (relación %.2f)" % (dyaw2 / dyaw1))
	ok(absf(dpit2 / dpit1 - 0.5) < 0.15, "C6c sensibilidad vertical ×0.5 reduce a la mitad la inclinación (relación %.2f)" % (dpit2 / dpit1))
	# invertir eje vertical
	SaveSystem.set_setting("cam_sens_x", 1.0)
	SaveSystem.set_setting("cam_sens_y", 1.0)
	SaveSystem.set_setting("cam_invert_y", true)
	cam.pitch = p0
	await _frames(3)
	await _look_drag(0.0, 60.0)
	var dpit3 := cam.pitch - p0
	ok(dpit3 * dpit1 < 0.0 and absf(absf(dpit3) / absf(dpit1) - 1.0) < 0.3, "C6d invertir el eje vertical cambia el sentido del giro (Δ %.3f frente a %.3f)" % [dpit3, dpit1])
	SaveSystem.set_setting("cam_invert_y", false)
	Config.reset_camera()
	await _frames(3)


# ================================================================== C4: muros y objetos sólidos
func _t_walls() -> void:
	var cam := _cam()
	Config.reset_camera()
	await _setup_arena(1, true)
	_put_player(0, 0)
	# sala cuadrada de 8×8 m con muros altos (caras interiores a ±4 m); con muros bajos la cámara, que mira desde arriba, pasa por encima
	_box(0, -4.3, 9.2, 12, 0.6)
	_box(0, 4.3, 9.2, 12, 0.6)
	_box(-4.3, 0, 0.6, 12, 9.2)
	_box(4.3, 0, 0.6, 12, 9.2)
	await _pframes(4)
	var worst := 0.0
	var inside_all := true
	var vis_all := true
	var below := false
	var space := player.get_world_3d().direct_space_state
	for k in 8:
		cam.yaw = TAU * float(k) / 8.0
		await _secs(0.55)
		var cp := cam.cam.global_position
		var rel := cp - player.global_position
		worst = maxf(worst, maxf(absf(rel.x), absf(rel.z)))
		if absf(rel.x) > 4.0 or absf(rel.z) > 4.0:
			inside_all = false
		if cp.y < Terrain.ground_y(cp.x, cp.z) + 0.1:
			below = true
		var q := PhysicsRayQueryParameters3D.create(cp, player.global_position + Vector3(0, 1.5, 0), Config.L_CAMERA)
		if not space.intersect_ray(q).is_empty():
			vis_all = false
	info("sala de 8×8 m, 8 orientaciones: desplazamiento máximo de la cámara %.2f m desde el jugador (muro a 4.0 m)" % worst)
	ok(inside_all, "C4a la cámara nunca atraviesa los muros de la sala (máx. %.2f m < 4.0 m)" % worst)
	ok(not below, "C4b la cámara no se hunde bajo el terreno")
	ok(vis_all, "C4c el abogado nunca queda tapado por un muro entre la cámara y su cabeza (8 orientaciones)")
	await _shot("c4_sala")
	# con inclinación extrema y distancia máxima también respeta los muros
	_set_cam(16.0, 3.2, 15.0)
	var inside2 := true
	for k in 8:
		cam.yaw = TAU * (float(k) + 0.5) / 8.0
		await _secs(0.5)
		var rel2 := cam.cam.global_position - player.global_position
		if absf(rel2.x) > 4.0 or absf(rel2.z) > 4.0:
			inside2 = false
	ok(inside2, "C4d con distancia máxima (16 m) e inclinación mínima tampoco atraviesa los muros")
	# junto al perímetro de la arena: la cámara se queda dentro y al girar no da saltos
	Config.reset_camera()
	_put_player(25.0, 25.0)
	await _secs(1.2)
	var half: float = arena.half
	var prev_cp := cam.cam.global_position
	var max_jump := 0.0
	var outside := false
	for f in 140:
		cam.yaw += 0.045
		await _frames(1)
		var cpp := cam.cam.global_position
		max_jump = maxf(max_jump, (cpp - prev_cp).length())
		prev_cp = cpp
		if absf(cpp.x) > half + 0.01 or absf(cpp.z) > half + 0.01:
			outside = true
	info("junto a la esquina de la arena girando 360°: salto máximo de la cámara por fotograma %.2f m" % max_jump)
	ok(not outside, "C4g junto al borde de la arena la cámara nunca sale del recinto")
	ok(max_jump < 1.2, "C4h girar 360° pegado a la esquina no provoca saltos bruscos de la cámara (máx. %.2f m por fotograma)" % max_jump)
	# columna sólida alta detrás del personaje: la esfera de cámara se acerca en vez de atravesarla
	Config.reset_camera()
	_put_player(12, 12)
	_box(12, 15, 3, 10, 3)
	cam.yaw = 0.0
	await _secs(0.9)
	var rel3 := cam.cam.global_position - player.global_position
	ok(rel3.z < 3.0, "C4e la cámara se acerca ante una columna sólida detrás del personaje (z relativa %.2f < 3.0)" % rel3.z)
	# al despejarse vuelve a alejarse suavemente (sin saltos bruscos)
	_put_player(-12, -12)
	cam.yaw = 0.0
	await _secs(2.6)
	var real := (cam.cam.global_position - (player.global_position + Vector3(0, cam.pivot_height, 0))).length()
	ok(real > 8.5, "C4f en campo abierto la cámara recupera su distancia (%.1f m)" % real)


# ================================================================== suavidad: giros, saltos, esquivas y lanzamientos
func _t_motion() -> void:
	var cam := _cam()
	Config.reset_camera()
	await _setup_arena(1, true)
	_put_player(0, 0)
	await _secs(1.5)
	var vs := get_viewport().get_visible_rect()
	var tc: TouchControls = main.touch
	# correr con el joystick real + girar la cámara arrastrando
	var zone := tc.joy_zone()
	var start := zone.get_center()
	await _touch(1, start, true)
	await _drag(1, start + Vector2(60, -60), Vector2(60, -60))
	var prev := cam.cam.global_position
	var prev_d := (cam.cam.global_position - player.global_position).length()
	var max_step := 0.0
	var max_dd := 0.0
	var max_rate := 0.0
	var series: Array = []
	var worst_px := 0.0
	var inside := true
	for f in 150:
		if f % 6 == 0:
			var p := _free_look_pos()
			await _touch(3, p, true)
			await _drag(3, p + Vector2(18, 0), Vector2(18, 0))
			await _touch(3, p + Vector2(18, 0), false)
		await _frames(1)
		var cp := cam.cam.global_position
		max_step = maxf(max_step, (cp - prev).length())
		prev = cp
		var dnow := (cp - player.global_position).length()
		max_dd = maxf(max_dd, absf(dnow - prev_d))
		if absf(dnow - prev_d) > 0.8:
			info("  salto de distancia %.2f m en un fotograma: jugador=%s yaw=%.2f cur_dist=%.2f dt=%.3f" % [dnow - prev_d, str(player.global_position), cam.yaw, float(cam.get("_cur_dist")), get_process_delta_time()])
		series.append(Vector2(Time.get_ticks_msec() / 1000.0, dnow))
		prev_d = dnow
		var sp := cam.cam.unproject_position(player.global_position + Vector3(0, 1.0, 0))
		if not vs.grow(-20.0).has_point(sp):
			inside = false
		worst_px = maxf(worst_px, sp.distance_to(vs.get_center()))
	await _touch(1, start + Vector2(60, -60), false)
	# ritmo máximo en ventanas de ≥0.2 s (un fotograma suelto con dt minúsculo no es una medida fiable)
	for i in series.size():
		for j in range(i + 1, series.size()):
			var dtw: float = series[j].x - series[i].x
			if dtw >= 0.2:
				max_rate = maxf(max_rate, absf(series[j].y - series[i].y) / dtw)
				break
	info("correr y girar 2.5 s: variación máxima de la distancia cámara↔jugador %.1f m/s (%.3f m por fotograma)" % [max_rate, max_dd])
	ok(max_rate < 6.0, "C7a al correr y girar la distancia a la cámara no cambia bruscamente (máx. %.1f m/s)" % max_rate)
	ok(inside, "C7b el abogado se mantiene siempre dentro de la pantalla al correr y girar")
	# salto, esquiva y lanzamiento del maletín (acciones reales)
	for act in ["jump", "dodge", "attack"]:
		_put_player(0, 0)
		await _secs(0.8)
		var d0 := (cam.cam.global_position - player.global_position).length()
		var step_max := 0.0
		var rate_max := 0.0
		var dev_max := 0.0
		var d_prev := d0
		var in_screen := true
		var y_max := player.global_position.y
		var throws0 := int(GameState.case_throw.counts["throws"])
		await _act(act, true)
		await _act(act, false)
		for f in 90:
			await _frames(1)
			var dn := (cam.cam.global_position - player.global_position).length()
			step_max = maxf(step_max, absf(dn - d_prev))
			rate_max = maxf(rate_max, absf(dn - d_prev) / maxf(0.001, get_process_delta_time()))
			dev_max = maxf(dev_max, absf(dn - d0))
			d_prev = dn
			y_max = maxf(y_max, player.global_position.y)
			var sp2 := cam.cam.unproject_position(player.global_position + Vector3(0, 1.0, 0))
			if not vs.grow(-20.0).has_point(sp2):
				in_screen = false
		if act == "attack":
			ok(int(GameState.case_throw.counts["throws"]) > throws0, "C7x el botón de ataque lanzó el maletín boomerang de verdad (lanzamientos %d → %d)" % [throws0, int(GameState.case_throw.counts["throws"])])
		var label: String = {"jump": "SALTO", "dodge": "ESQUIVA", "attack": "LANZAMIENTO del maletín"}[act]
		info("%s: altura máxima %.2f m · distancia cámara↔jugador %.1f → %.1f m · desviación máx. %.2f m · ritmo máx. %.1f m/s" % [label, y_max - Terrain.ground_y(0, 0), d0, d_prev, dev_max, rate_max])
		ok(dev_max < 1.6 and absf(d_prev - d0) < 0.3 and in_screen, "C7 %s: la cámara sigue al personaje (desviación máx. de distancia %.2f m < 1.6, vuelve a la normal) y lo mantiene en pantalla" % [label, dev_max])
	await _secs(0.5)


func _t_persist_setup() -> void:
	# valores no predeterminados que deben sobrevivir al reinicio
	SaveSystem.set_setting("cam_dist", 12.4)
	SaveSystem.set_setting("cam_height", 2.2)
	SaveSystem.set_setting("cam_pitch", 40.0)
	SaveSystem.set_setting("cam_sens_x", 1.7)
	SaveSystem.set_setting("cam_sens_y", 0.6)
	SaveSystem.set_setting("cam_invert_y", true)
	Config.apply_camera()
	SaveSystem.save_now()
	await _secs(0.5)
	info("guardados: dist 12.4 · altura 2.2 · inclinación 40° · sens 1.7/0.6 · invertido")
	Config.dev_god_mode = false


func _stage2() -> void:
	await _start_run()
	await _setup_arena(1, true)
	_put_player(0, 0)
	await _secs(1.8)
	var cam := _cam()
	ok(absf(float(SaveSystem.setting("cam_dist")) - 12.4) < 0.001 and absf(float(SaveSystem.setting("cam_height")) - 2.2) < 0.001 and absf(float(SaveSystem.setting("cam_pitch")) - 40.0) < 0.001, "C3c tras reiniciar el juego distancia, altura e inclinación guardadas se cargan (12.4 / 2.2 / 40)")
	ok(absf(float(SaveSystem.setting("cam_sens_x")) - 1.7) < 0.001 and absf(float(SaveSystem.setting("cam_sens_y")) - 0.6) < 0.001 and bool(SaveSystem.setting("cam_invert_y")), "C3d y también las sensibilidades y la inversión del eje vertical")
	ok(absf(cam.distance - 12.4) < 0.01 and absf(cam.pivot_height - 2.2) < 0.01 and absf(rad_to_deg(-cam.pitch) - 40.0) < 0.5, "C3e el rig las aplica desde el primer momento (dist %.1f · altura %.1f · incl. %.0f°)" % [cam.distance, cam.pivot_height, rad_to_deg(-cam.pitch)])
	var real := (cam.cam.global_position - (player.global_position + Vector3(0, cam.pivot_height, 0))).length()
	ok(absf(real - 12.4) < 0.6, "C3f la cámara real está a esa distancia en la partida (%.1f m)" % real)
	await _shot("c3_persistido")
	# restablecer y guardar para no dejar valores raros
	Config.reset_camera()
	SaveSystem.save_now()
	Config.dev_god_mode = false
