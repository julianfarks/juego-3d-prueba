extends Node
## Pruebas de CONTROLES (v0.7.1): acceso al inventario y ataque 100% manual. Render real: xvfb.
##   xvfb-run -a godot --path . --rendering-driver opengl3 -- --controltest --out=DIR
## Los toques se envían como InputEventScreenTouch reales a los controles táctiles; el mando, como InputEventJoypadButton.

var main: Node
var out_dir := "/tmp/controltest"
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


func _touch(idx: int, pos: Vector2, down: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = idx
	ev.position = pos
	ev.pressed = down
	Input.parse_input_event(ev)
	await _frames(2)


func _joy(btn: int, down: bool) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = btn
	ev.pressed = down
	Input.parse_input_event(ev)
	await _frames(2)


## Gatillo analógico del mando (RT = eje 5, LT = eje 4).
func _trig(axis: int, down: bool) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = 1.0 if down else 0.0
	Input.parse_input_event(ev)
	await _frames(2)


func _wait_idle(max_s := 8.0) -> void:
	var t := 0.0
	while ct.in_flight() and t < max_s:
		await _frames(2)
		t += get_process_delta_time() * 2.0
	await _frames(3)


func _throws() -> int:
	return int(ct.counts["throws"])


func _run() -> void:
	await _frames(10)
	await main._enter_lobby(true)
	await _frames(15)
	main._on_play()
	var t := 0.0
	while main.state != main.St.RUN and t < 10.0:
		await _frames(2)
		t += 0.03
	ok(main.state == main.St.RUN, "K0 empieza la partida")
	Config.dev_god_mode = true
	main.arena.force_complete()
	await _secs(1.0)
	ct = GameState.case_throw
	player = GameState.player
	main.touch.visible = true
	await _frames(3)
	await _t1_inventory_button()
	await _t2_no_auto_attack()
	await _t3_touch_attack()
	await _t4_upgrades()
	await _t5_other_controls()
	await _t6_gamepad()
	Config.dev_god_mode = false
	print("")
	print("=== CONTROLTEST: %d comprobaciones OK, %d fallos ===" % [passes, fails.size()])
	for f in fails:
		print("  FALLO: ", f)
	get_tree().quit(0 if fails.is_empty() else 1)


# ---------------------------------------------------------------- 1. inventario
func _t1_inventory_button() -> void:
	GameState.build.reset({})
	main.hud._refresh_build()
	var btn: Button = main.hud.get_node_or_null("InventoryButton")
	ok(btn != null, "K1.1 existe el botón de inventario en el HUD")
	var txt := btn.text
	ok(txt.contains("INVENTARIO") and not txt.contains("MEJ "), "K1.2 el botón dice INVENTARIO (texto: '%s')" % txt.replace("\n", " "))
	ok(btn.icon != null, "K1.3 el botón lleva el icono de maletín")
	var r := btn.get_global_rect()
	ok(r.size.y >= 64.0 and r.size.x >= 150.0, "K1.4 tamaño táctil cómodo (%dx%d px)" % [r.size.x, r.size.y])
	var pause_btn: Button = null
	for ch in main.hud.get_children():
		if ch is Button and ch.text == "II":
			pause_btn = ch
	var gap := pause_btn.get_global_rect().position.x - (r.position.x + r.size.x)
	ok(gap >= 12.0, "K1.5 separación con el botón de pausa de %d px (≥12)" % gap)
	var vp := get_viewport().get_visible_rect().size
	ok(r.position.x >= 0.0 and r.end.x <= vp.x and r.position.y >= 0.0, "K1.6 el botón queda dentro de la pantalla (%s de %s)" % [str(r), str(vp)])
	# contador = tipos distintos (no la suma de niveles)
	ok(txt.ends_with("0/%d" % Build.MAX_TYPES), "K1.7 contador inicial 0/%d" % Build.MAX_TYPES)
	GameState.build.add("heavy_case", 0, true)
	GameState.build.add("heavy_case", 0, true)
	GameState.build.add("wide_sweep", 0, true)
	main.hud._refresh_build()
	ok(btn.text.ends_with("2/%d" % Build.MAX_TYPES) and GameState.build.type_count() == 2, "K1.8 el contador cuenta tipos distintos (3 mejoras, 2 tipos → '%s')" % btn.text.replace("\n", " "))
	await _shot("k1_hud_inventario")
	# abrir con un toque real
	var thr0 := _throws()
	await _touch(7, r.get_center(), true)
	await _touch(7, r.get_center(), false)
	await _frames(4)
	var inv: InventoryUI = null
	for o in main._overlays:
		if o is InventoryUI:
			inv = o
	ok(inv != null, "K1.9 un toque en el botón abre el inventario")
	ok(get_tree().paused, "K1.10 la partida queda en pausa mientras se consulta")
	await _shot("k1_inventario_abierto")
	if inv != null:
		var slots := inv.find_children("*", "Button", true, false).filter(func(b): return b.text == "" or b.text.length() > 0)
		ok(slots.size() >= 3, "K1.11 el inventario muestra las mejoras y botones (%d controles)" % slots.size())
		inv._show_tab(false)
		await _frames(3)
		await _shot("k1_inventario_sinergias")
		inv._show_tab(true)
	ok(_throws() == thr0, "K1.12 abrir el inventario no lanza el maletín")
	var hp_before: float = player.hp
	var coins_before: int = GameState.coins
	if inv != null:
		for b in inv.find_children("*", "Button", true, false):
			if b.text == "CERRAR":
				b.pressed.emit()
	await _frames(4)
	var still := false
	for o in main._overlays:
		if o is InventoryUI:
			still = true
	ok(not still and not get_tree().paused, "K1.13 CERRAR devuelve a la partida")
	ok(GameState.build.type_count() == 2 and GameState.coins == coins_before and player.hp == hp_before and GameState.in_run, "K1.14 no se pierde progreso al cerrar (2 tipos, monedas %d)" % GameState.coins)
	ok(_throws() == thr0, "K1.15 cerrar el inventario tampoco lanza el maletín")


# ---------------------------------------------------------------- 2. sin ataque automático
func _t2_no_auto_attack() -> void:
	SaveSystem.data["settings"]["auto_attack"] = true      # ajuste heredado de partidas antiguas: debe ignorarse
	GameState.build.reset({})
	await _wait_idle()
	var e: Enemy = main.arena._spawn_enemy("tank", player.global_position + Vector3(0, 0, -4.0))
	var tt := 0.0
	while e.state == Enemy.S.SPAWN and tt < 4.0:
		await _frames(2)
		tt += 0.04
	e.move_speed = 0.0
	e.max_hp = 1.0e12
	e.hp = 1.0e12
	ct.record = true
	ct.impact_log.clear()
	for k in ct.counts.keys():
		ct.counts[k] = 0
	player.skills.cd[0] = 0.0
	await _secs(6.0)
	ok(_throws() == 0 and not ct.in_flight(), "K2.1 con un enemigo a 4 m y 6 s sin pulsar ATACAR no se lanza ningún maletín (lanzamientos %d)" % _throws())
	# mantener una tecla de ataque NO repite el lanzamiento
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_J
	ev.pressed = true
	Input.parse_input_event(ev)
	await _secs(4.0)
	ev = InputEventKey.new()
	ev.physical_keycode = KEY_J
	ev.pressed = false
	Input.parse_input_event(ev)
	await _frames(3)
	ok(_throws() == 1, "K2.2 mantener ATACAR 4 s (teclado) produce un único lanzamiento (%d)" % _throws())
	await _wait_idle()
	await _secs(2.0)
	ok(_throws() == 1, "K2.3 al recuperar el maletín no se vuelve a lanzar solo (%d lanzamientos tras 2 s)" % _throws())
	ok(ct.cases.is_empty() and not ct.in_flight(), "K2.4 el maletín quedó recogido (sin copias en vuelo)")
	ok(ct.can_throw(), "K2.5 el arma queda lista para otro lanzamiento manual")
	e.queue_free()


# ---------------------------------------------------------------- 3. ataque táctil
func _t3_touch_attack() -> void:
	for k in ct.counts.keys():
		ct.counts[k] = 0
	GameState.build.reset({})
	await _frames(3)
	var pos: Vector2 = main.touch._center("attack")
	await _touch(3, pos, true)
	await _frames(3)
	ok(_throws() == 1, "K3.1 un toque en ATACAR inicia un lanzamiento (%d)" % _throws())
	await _shot("k3_maletin_en_vuelo")
	# seguir pulsando durante todo el vuelo y el regreso no genera copias ni repeticiones
	var max_cases := 0
	var t := 0.0
	while ct.in_flight() and t < 6.0:
		await _frames(2)
		t += get_process_delta_time() * 2.0
		max_cases = maxi(max_cases, ct.cases.size())
	await _secs(1.5)
	ok(_throws() == 1 and max_cases <= 1, "K3.2 con el dedo mantenido: 1 lanzamiento y máx. %d maletín(es) vivos" % max_cases)
	await _touch(3, pos, false)
	await _frames(3)
	ok(int(ct.counts["catches"]) >= 1 and ct.can_throw(), "K3.3 el maletín regresa (recogidas %d) y queda listo" % int(ct.counts["catches"]))
	await _touch(3, pos, true)
	await _touch(3, pos, false)
	await _frames(3)
	ok(_throws() == 2, "K3.4 una nueva pulsación lanza de nuevo (%d)" % _throws())
	# pulsar mientras está en vuelo no crea otro
	await _touch(3, pos, true)
	await _touch(3, pos, false)
	await _touch(3, pos, true)
	await _touch(3, pos, false)
	await _frames(2)
	ok(_throws() == 2 and ct.cases.size() <= 1, "K3.5 pulsar ATACAR con el maletín fuera no genera copias (%d lanzamientos, %d vivos)" % [_throws(), ct.cases.size()])
	await _wait_idle()


# ---------------------------------------------------------------- 4. mejoras que alteran el lanzamiento
func _t4_upgrades() -> void:
	GameState.build.reset({})
	for id in ["case_blast", "case_pyro", "case_bounce", "case_cases", "heavy_case"]:
		GameState.build.add(id, 0, true)
	for k in ct.counts.keys():
		ct.counts[k] = 0
	ct.record = true
	ct.impact_log.clear()
	await _wait_idle()
	var es: Array = []
	for i in 4:
		var e: Enemy = main.arena._spawn_enemy("tank", player.global_position + Vector3(float(i - 2) * 1.6, 0, -5.5))
		es.append(e)
	await _secs(1.2)
	for e in es:
		e.move_speed = 0.0
		e.max_hp = 1.0e12
		e.hp = 1.0e12
	await _secs(3.0)
	ok(_throws() == 0, "K4.1 con mejoras de lanzamiento activas y enemigos cerca, sin pulsar no se lanza nada (%d)" % _throws())
	player.skills.cd[0] = 0.0
	player.skills.try_cast(0)
	await _wait_idle()
	await _secs(1.5)
	var secondary := int(ct.counts["blasts"]) + int(ct.counts["rockets"]) + int(ct.counts["frags"]) + int(ct.counts["minis"])
	ok(_throws() == 1, "K4.2 un lanzamiento manual con todas esas mejoras = %d lanzamiento principal" % _throws())
	ok(ct.impact_log.size() >= 1, "K4.3 los impactos ocurren (%d)" % ct.impact_log.size())
	info("efectos secundarios disparados por los impactos: blasts %d, rockets %d, frags %d, minis %d" % [int(ct.counts["blasts"]), int(ct.counts["rockets"]), int(ct.counts["frags"]), int(ct.counts["minis"])])
	ok(secondary >= 1, "K4.4 las mejoras se activan por los impactos (%d efectos secundarios)" % secondary)
	await _secs(3.0)
	ok(_throws() == 1, "K4.5 esos efectos no inician nuevos lanzamientos principales (%d tras 3 s más)" % _throws())
	for e in es:
		if is_instance_valid(e):
			e.queue_free()


# ---------------------------------------------------------------- 5. el resto de controles
func _t5_other_controls() -> void:
	GameState.build.reset({})
	await _wait_idle()
	var thr0 := _throws()
	# SALTAR (toque real)
	await _frames(20)
	var jp: Vector2 = main.touch._center("jump")
	var y0 := player.global_position.y
	await _touch(4, jp, true)
	var vy_max := -99.0
	for i in 8:
		await _frames(1)
		vy_max = maxf(vy_max, player.velocity.y)
	await _touch(4, jp, false)
	ok(vy_max > 2.0, "K5.1 SALTAR (toque) hace saltar al jugador (vel. vertical máx. %.1f)" % vy_max)
	await _secs(1.2)
	# ESQUIVAR
	player._dodge_cd = 0.0
	var dp: Vector2 = main.touch._center("dodge")
	await _touch(5, dp, true)
	var dodged := false
	for i in 8:
		await _frames(1)
		if player._dodge_t > 0.0:
			dodged = true
	await _touch(5, dp, false)
	ok(dodged, "K5.2 ESQUIVAR (toque) inicia la esquiva")
	await _secs(1.0)
	# DOCS
	player.skills.energy = player.skills.energy_max
	player.skills.cd[1] = 0.0
	var docs0 := int(ct.counts["docs"])
	var projectiles_before: int = main.projectiles.get_child_count() if main.projectiles.get_child_count() > 0 else 0
	var kp: Vector2 = main.touch._center("skill1")
	await _touch(6, kp, true)
	await _frames(3)
	await _touch(6, kp, false)
	ok(player.skills.cd[1] > 0.0, "K5.3 DOCS (toque) se lanza y entra en enfriamiento (%.1f s)" % player.skills.cd[1])
	ok(_throws() == thr0, "K5.4 SALTAR, ESQUIVAR y DOCS no lanzan el maletín (%d → %d)" % [thr0, _throws()])


# ---------------------------------------------------------------- 6. mando
func _t6_gamepad() -> void:
	await _wait_idle()
	await _secs(1.0)
	for k in ct.counts.keys():
		ct.counts[k] = 0
	ok(InputMap.action_get_events("attack").any(func(e): return e is InputEventJoypadMotion and e.axis == 5), "K6.1 la acción ATACAR tiene el gatillo RT asignado")
	await _secs(3.0)
	ok(_throws() == 0, "K6.2 con el mando conectado sin pulsar nada no se lanza nada (%d)" % _throws())
	await _trig(5, true)
	await _frames(3)
	ok(_throws() == 1, "K6.3 el botón de ataque del mando lanza una vez (%d)" % _throws())
	await _secs(4.0)
	await _trig(5, false)
	ok(_throws() == 1, "K6.4 mantenerlo pulsado no repite el lanzamiento (%d)" % _throws())
	await _wait_idle()
	player.skills.cd[0] = 0.0
	await _trig(5, true)
	await _trig(5, false)
	await _frames(3)
	ok(_throws() == 2, "K6.5 pulsar de nuevo tras recuperar el maletín lanza otra vez (%d)" % _throws())
	await _wait_idle()
	await _secs(1.0)
	var vy_max := -99.0
	await _joy(JOY_BUTTON_A, true)
	for i in 8:
		await _frames(1)
		vy_max = maxf(vy_max, player.velocity.y)
	await _joy(JOY_BUTTON_A, false)
	ok(vy_max > 2.0, "K6.6 el botón de salto del mando salta")
	await _secs(1.0)
	player._dodge_cd = 0.0
	await _joy(JOY_BUTTON_B, true)
	var dodged := false
	for i in 8:
		await _frames(1)
		if player._dodge_t > 0.0:
			dodged = true
	await _joy(JOY_BUTTON_B, false)
	ok(dodged, "K6.7 el botón de esquiva del mando esquiva")
	player.skills.energy = player.skills.energy_max
	player.skills.cd[1] = 0.0
	await _trig(4, true)
	await _trig(4, false)
	ok(player.skills.cd[1] > 0.0, "K6.8 el botón DOCS del mando lanza DOCS")
	ok(_throws() == 2, "K6.9 salto, esquiva y DOCS con mando no lanzaron el maletín (%d)" % _throws())
