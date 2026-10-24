extends Node
## Pruebas de COLISIÓN DE LA TIENDA (v0.10.2): el personaje real (CharacterBody3D con su sistema normal de colisión) camina
## contra el frente y los laterales de cada una de las 6 tiendas desde 8 direcciones, intenta rodearlas, usa el punto de
## atención delante del mostrador, y se repite con el joystick táctil real y con el stick del mando.
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 -- --shopcoltest --out=DIR [--only=0,1]

var main: Node
var out_dir := "/tmp/shopcoltest"
var only := ""
var fails: Array = []
var passes := 0
var player: Player
const ARENAS := [1, 6, 11, 16, 21, 26]
const NAMES := ["urbano", "bosque", "industrial", "desierto", "ciudadela", "tribunal"]


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
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


func _pf(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _secs(t: float) -> void:
	await get_tree().create_timer(t, true, false, true).timeout


func _shot(name: String) -> void:
	await _frames(4)
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png("%s/%s.png" % [out_dir, name])


func _release_all() -> void:
	for a in ["move_left", "move_right", "move_forward", "move_back"]:
		Input.action_release(a)


## Mantiene pulsada la dirección 'dir' (plano XZ, con la cámara en yaw 0) durante 'secs'. Devuelve true si en algún
## momento el centro del jugador estuvo DENTRO de un volumen sólido de la tienda.
func _push(shop: Interactable, dir: Vector3, secs: float) -> bool:
	main.cam.yaw = 0.0
	var inside := false
	var t := 0.0
	while t < secs:
		_release_all()
		if dir.x > 0.01:
			Input.action_press("move_right", dir.x)
		elif dir.x < -0.01:
			Input.action_press("move_left", -dir.x)
		if dir.z > 0.01:
			Input.action_press("move_back", dir.z)
		elif dir.z < -0.01:
			Input.action_press("move_forward", -dir.z)
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if _inside_solid(shop):
			inside = true
	_release_all()
	return inside


func _inside_solid(shop: Interactable) -> bool:
	var body := shop.find_child("ShopCollider", true, false) as StaticBody3D
	if body == null:
		return false
	var lp := body.to_local(player.global_position)
	var feet := lp.y
	for c in body.get_children():
		var cs := c as CollisionShape3D
		if cs == null or cs.shape == null:
			continue
		var q := lp - cs.position
		if cs.shape is BoxShape3D:
			var h := (cs.shape as BoxShape3D).size * 0.5
			if absf(q.x) < h.x and absf(q.z) < h.z and feet + 0.5 > cs.position.y - h.y and feet + 0.2 < cs.position.y + h.y:
				return true
		elif cs.shape is CylinderShape3D:
			var cy := cs.shape as CylinderShape3D
			if Vector2(q.x, q.z).length() < cy.radius and feet + 0.5 > cs.position.y - cy.height * 0.5 and feet + 0.2 < cs.position.y + cy.height * 0.5:
				return true
	return false


func _place(shop: Interactable, local: Vector3) -> void:
	var p := shop.to_global(local)
	player.teleport_to(Vector3(p.x, Terrain.ground_y(p.x, p.z) + 0.3, p.z))
	await _pf(6)


func _find_shop() -> Interactable:
	for n in get_tree().get_nodes_in_group("interactable"):
		if (n as Interactable).kind == "shop":
			return n
	return null


func _enter_shop_arena(idx: int) -> Interactable:
	await main._begin_arena(idx, true)
	await _secs(0.3)
	var arena: Arena = main.arena
	arena.force_complete()
	await _secs(0.3)
	for e in Combat.arena_enemies().duplicate():
		if is_instance_valid(e) and e.get("alive"):
			e.set("invuln_t", 0.0)
			e.take_damage(float(e.get("hp")) * 20.0 + 20.0, {"src": "boss_death", "silent": true})
	var wt := 0.0
	while _find_shop() == null and wt < 12.0:
		await _secs(0.25)
		wt += 0.25
		for e in Combat.arena_enemies().duplicate():
			if is_instance_valid(e) and e.get("alive"):
				e.set("invuln_t", 0.0)
				e.take_damage(float(e.get("hp")) * 20.0 + 20.0, {"src": "boss_death", "silent": true})
	await _secs(0.5)
	# arena despejada de obstáculos del bioma para que la prueba mida SOLO la tienda
	var shop := _find_shop()
	var ks: Array = []
	for n in get_tree().get_nodes_in_group("interactable"):
		ks.append((n as Interactable).kind)
	info("arena %d fase %s interactuables %s índice %d" % [idx, str(arena.phase), str(ks), GameState.arena_index])
	if shop != null:
		for ch in arena.world_root.get_children():
			if ch is Node3D and ch != shop and not (ch is MeshInstance3D) and ch.name != "WallCollider" and not (ch is Interactable):
				for i in range(1, arena.circles.size()):
					var c: Vector3 = arena.circles[i]
					if absf(ch.position.x - c.x) < 0.06 and absf(ch.position.z - c.y) < 0.06:
						ch.queue_free()
						break
	await _frames(3)
	return shop


func _run() -> void:
	await _frames(4)
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
	await _secs(1.0)
	for bi in ARENAS.size():
		if only != "" and not only.split(",").has(str(bi)):
			continue
		await _test_biome(bi)
	await _touch_pad_tests()
	print("[RESULT] colisión de tienda: %d ok, %d fallos" % [passes, fails.size()])
	for f in fails:
		print("  FALLO: ", f)
	get_tree().quit(1 if fails.size() > 0 else 0)


func _test_biome(bi: int) -> void:
	var nm: String = NAMES[bi]
	var shop := await _enter_shop_arena(ARENAS[bi])
	ok(shop != null, "%s: existe la tienda" % nm)
	if shop == null:
		return
	var body := shop.find_child("ShopCollider", true, false) as StaticBody3D
	ok(body != null and body.get_child_count() >= 2, "%s: la tienda tiene colliders (%d formas)" % [nm, body.get_child_count() if body != null else 0])
	ok(body != null and (body.collision_layer & Config.L_WORLD) != 0 and body.collision_mask == 0, "%s: capa de mundo (el personaje la detecta con su máscara %d)" % [nm, player.collision_mask])
	ok((player.collision_mask & body.collision_layer) != 0, "%s: la máscara del jugador incluye la capa de la tienda" % nm)
	ok(not body.process_mode == Node.PROCESS_MODE_DISABLED, "%s: la colisión está activa" % nm)
	if OS.get_environment("SHOPCOL_OFF") != "":
		body.collision_layer = 0          # control negativo: sin colisión la prueba DEBE fallar
	var anchor: Vector3 = shop.anchor
	# --- 8 direcciones: situarse a 6 m del centro y empujar hacia el centro ---
	var bad := 0
	var stopped := 0
	for k in 8:
		var ang := TAU * float(k) / 8.0
		var out := Vector3(sin(ang), 0, cos(ang))       # k=0: delante (+Z)
		await _place(shop, out * 6.5)
		var local_dir := -out
		var gdir := shop.global_transform.basis * local_dir
		var inside := await _push(shop, Vector3(gdir.x, 0, gdir.z).normalized(), 3.5)
		if inside:
			bad += 1
			info("%s: dirección %d (%.0f°) ATRAVESÓ la estructura en %s" % [nm, k, rad_to_deg(ang), str(shop.to_local(player.global_position))])
		var dist_c := Vector2(shop.to_local(player.global_position).x, shop.to_local(player.global_position).z).length()
		if dist_c > 0.9:
			stopped += 1
	ok(bad == 0, "%s: desde 8 direcciones el personaje nunca entra en la estructura" % nm)
	ok(stopped == 8, "%s: el personaje se detiene ante la superficie (no llega al centro) en 8/8 direcciones" % nm)
	# --- frente y laterales concretos, empujando de forma oblicua (deslizar por la pared) ---
	var slid := false
	await _place(shop, Vector3(-5.5, 0, 0.0))
	var inside2 := await _push(shop, Vector3(0.8, 0, 0.35).normalized(), 3.0)
	slid = not inside2
	ok(slid, "%s: empujando en diagonal contra un lateral tampoco se atraviesa" % nm)
	# --- rodear: ir de un lado al opuesto atravesando el centro con la ruta sencilla de «rodear» ---
	await _place(shop, Vector3(-6.0, 0, 0.0))
	var target := shop.to_global(Vector3(6.0, 0, 0.0))
	var ins3 := false
	var reached := false
	var t := 0.0
	var side := 1.0
	var side_t := 0.0
	var chk := player.global_position
	var chk_t := 0.0
	main.cam.yaw = 0.0
	while t < 22.0 and not reached:
		var d := target - player.global_position
		d.y = 0.0
		if d.length() < 1.2:
			reached = true
			break
		var dir := d.normalized()
		chk_t += get_physics_process_delta_time()
		if chk_t > 0.6:
			if (player.global_position - chk).length() < 0.5:
				side_t = 2.2
			chk = player.global_position
			chk_t = 0.0
		if side_t > 0.0:
			side_t -= get_physics_process_delta_time()
			dir = (dir * 0.2 + Vector3(-dir.z, 0, dir.x) * side).normalized()
		_release_all()
		if dir.x > 0.0:
			Input.action_press("move_right", dir.x)
		else:
			Input.action_press("move_left", -dir.x)
		if dir.z > 0.0:
			Input.action_press("move_back", dir.z)
		else:
			Input.action_press("move_forward", -dir.z)
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if _inside_solid(shop):
			ins3 = true
	_release_all()
	ok(reached and not ins3, "%s: el personaje rodea la tienda hasta el lado opuesto (llegó=%s en %.1f s, atravesó=%s)" % [nm, str(reached), t, str(ins3)])
	# --- zona de atención: accesible delante del mostrador y solo allí ---
	await _place(shop, Vector3(anchor.x, 0, anchor.z + 5.0))
	main.cam.yaw = 0.0
	var reached_front := false
	t = 0.0
	while t < 8.0:
		var dd := shop.use_point() - player.global_position
		dd.y = 0.0
		if dd.length() < 0.7:
			reached_front = true
			break
		var dn := dd.normalized()
		_release_all()
		if dn.x > 0.05:
			Input.action_press("move_right", dn.x)
		elif dn.x < -0.05:
			Input.action_press("move_left", -dn.x)
		if dn.z > 0.05:
			Input.action_press("move_back", dn.z)
		elif dn.z < -0.05:
			Input.action_press("move_forward", -dn.z)
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
	_release_all()
	await _pf(8)
	ok(reached_front and player.interact_target == shop, "%s: se llega al punto de atención delante del mostrador y TIENDA se puede usar (objetivo=%s)" % [nm, str(player.interact_target)])
	var shown_front: bool = shop.indicator_visible()
	await _shot("t_%s_frente" % nm)
	# desde un lateral cerca de la estructura NO se ofrece
	await _place(shop, Vector3(-5.0, 0, -0.5))
	await _pf(8)
	ok(player.interact_target != shop, "%s: junto al lateral (fuera de la zona de atención) la tienda NO ofrece interacción" % nm)
	await _place(shop, Vector3(0.0, 0, -4.5))
	await _pf(8)
	ok(player.interact_target != shop, "%s: por detrás de la tienda tampoco" % nm)
	# usar de verdad: abre la interfaz; cerrar no desactiva la colisión
	await _place(shop, anchor)
	await _pf(8)
	if player.interact_target == shop:
		shop.activate(player)
		await _secs(0.5)
		var sh := _overlay_shop()
		ok(sh != null, "%s: la tienda se abre desde el punto de atención" % nm)
		if sh != null:
			(sh.find_child("Shop_close", true, false) as Button).pressed.emit()
			await _secs(0.4)
	ok(is_instance_valid(body) and body.collision_layer == 17 and not body.get_child(0).disabled, "%s: tras abrir y cerrar la tienda la colisión sigue activa" % nm)
	await _place(shop, Vector3(0, 0, -6.5))
	var ins4 := await _push(shop, shop.global_transform.basis * Vector3(0, 0, 1), 3.5)
	ok(not ins4, "%s: y sigue sin poderse atravesar después de usar la tienda" % nm)


func _overlay_shop() -> Node:
	for o in main._overlays:
		if is_instance_valid(o) and o is ShopUI:
			return o
	return null


func _tch(idx: int, pos: Vector2, down: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = idx
	ev.position = pos
	ev.pressed = down
	Input.parse_input_event(ev)
	await _frames(2)


func _drg(idx: int, pos: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = idx
	ev.position = pos
	Input.parse_input_event(ev)
	await _frames(2)


## Joystick táctil real y stick del mando real contra la tienda del bioma 0 (la misma colisión: no cambia el desplazamiento).
func _touch_pad_tests() -> void:
	var shop := await _enter_shop_arena(ARENAS[0])
	if shop == null:
		ok(false, "táctil: no hay tienda")
		return
	main.touch.visible = true
	var tc: TouchControls = main.touch
	var sz := get_viewport().get_visible_rect().size
	# táctil: a la derecha de la tienda, joystick hacia la izquierda (yaw 0)
	main.cam.yaw = 0.0
	await _place(shop, Vector3(7.5, 0, 0.0))
	var p_in := Vector2(sz.x * 0.2, sz.y * 0.75)
	await _tch(1, p_in, true)
	await _drg(1, tc._joy_origin + Vector2(-90, 0))
	var inside := false
	var t := 0.0
	while t < 4.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if _inside_solid(shop):
			inside = true
	var lp := shop.to_local(player.global_position)
	await _tch(1, p_in, false)
	ok(not inside and absf(lp.x) > 1.5, "joystick táctil real: empujar contra el lateral de la tienda no la atraviesa (x local %.1f)" % lp.x)
	# mando: stick izquierdo hacia delante desde atrás (z local -7 empujando +z)
	await _place(shop, Vector3(0.0, 0, -7.0))
	var ev := InputEventJoypadMotion.new()
	ev.axis = JOY_AXIS_LEFT_Y
	ev.axis_value = 1.0
	Input.parse_input_event(ev)
	await _frames(2)
	inside = false
	t = 0.0
	while t < 4.0:
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		if _inside_solid(shop):
			inside = true
	lp = shop.to_local(player.global_position)
	ev.axis_value = 0.0
	Input.parse_input_event(ev)
	await _frames(2)
	ok(not inside and lp.z < -0.6, "stick del mando real: empujar contra la parte trasera no atraviesa la tienda (z local %.1f)" % lp.z)
	# movimiento libre intacto: lejos de la tienda el personaje se mueve con normalidad
	await _place(shop, Vector3(-9.0, 0, -9.0))
	var p0 := player.global_position
	ev.axis = JOY_AXIS_LEFT_X
	ev.axis_value = -1.0
	Input.parse_input_event(ev)
	await _secs(0.8)
	ev.axis_value = 0.0
	Input.parse_input_event(ev)
	await _frames(2)
	ok(player.global_position.distance_to(p0) > 2.0, "el mando mueve al personaje con normalidad lejos de la tienda (%.1f m)" % player.global_position.distance_to(p0))
