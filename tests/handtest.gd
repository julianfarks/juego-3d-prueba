extends Node
## El objeto en la mano sigue a la herramienta equipada: Maletín Clásico / Mazo del Juez / Pluma Estilete.
## Sala central, entrar a la partida, durante el combate, volver a la sala y reanudar una partida guardada. Capturas en --out=DIR.
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 -- --handtest --out=DIR

var main: Node
var out_dir := "/tmp/handtest"
var fails: Array = []
var passes := 0
const IDS := ["case", "gavel", "quill"]


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
	await get_tree().create_timer(t, true, false, true).timeout


func _hand_mesh() -> Mesh:
	var pl = GameState.player
	var node := pl.rig.props.get("case", null) as Node3D
	var mi := node.get_node_or_null("BriefcaseMesh") as MeshInstance3D
	return mi.mesh


func _check(id: String, label: String) -> void:
	var pl = GameState.player
	ok(GameState.hand_weapon_id() == id, "H %s: la herramienta de la partida es %s (%s)" % [label, id, GameState.hand_weapon_id()])
	ok(String(pl.rig.props.get("weapon_id", "")) == id, "H %s: el rig sostiene el modelo de %s" % [label, id])
	ok(_hand_mesh() == ModelFactory.weapon_mesh(id), "H %s: la malla visible en la mano es la de %s" % [label, id])
	var node := pl.rig.props.get("case", null) as Node3D
	var mi := node.get_node_or_null("BriefcaseMesh") as MeshInstance3D
	var bb := mi.get_aabb()
	ok(bb.size.length() > 0.5 and bb.size.length() < 1.6, "H %s: tamaño razonable del objeto (%.2f m de diagonal)" % [label, bb.size.length()])
	var wp: Dictionary = LoadoutDB.item(id)["weapon_params"]
	ok(GameState.weapon_params == wp, "H %s: estadísticas de ataque de %s intactas (dmg×%.2f, cd×%.2f)" % [label, id, float(wp["dmg_x"]), float(wp["cd_x"])])


func _closeup(name: String) -> void:
	var pl = GameState.player
	var cam := Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	var base: Vector3 = pl.global_position
	var fwd: Vector3 = -pl.global_transform.basis.z
	var right: Vector3 = pl.global_transform.basis.x
	cam.global_position = base + Vector3(0, 1.15, 0) + fwd * 2.4 + right * 1.9
	cam.look_at(base + Vector3(0, 0.75, 0) + right * 0.25, Vector3.UP)
	cam.current = true
	await _frames(6)
	get_viewport().get_texture().get_image().save_png("%s/%s_frente.png" % [out_dir, name])
	cam.global_position = base + Vector3(0, 1.1, 0) + right * 2.6 - fwd * 0.2
	cam.look_at(base + Vector3(0, 0.8, 0) + right * 0.3, Vector3.UP)
	await _frames(6)
	get_viewport().get_texture().get_image().save_png("%s/%s_lado.png" % [out_dir, name])
	cam.queue_free()
	if GameState.cam != null and GameState.cam.cam != null:
		GameState.cam.cam.current = true
	await _frames(3)


func _run() -> void:
	await _frames(10)
	await main._enter_lobby(true)
	await _frames(15)
	for id in IDS:
		if not (SaveSystem.data["meta"]["unlocks"] as Array).has(id) and int(LoadoutDB.item(id)["cost"]) > 0:
			(SaveSystem.data["meta"]["unlocks"] as Array).append(id)
	# --- 1. sala central: equipar uno por uno ---
	for id in IDS:
		ok(LoadoutDB.equip("weapon", id), "H1 equipar %s" % id)
		main._lobby_changed()
		await _frames(6)
		await _check(id, "sala/" + id)
		await _closeup("sala_" + id)
	# --- 2. partida con cada herramienta ---
	for id in IDS:
		LoadoutDB.equip("weapon", id)
		main._lobby_changed()
		main._on_play()
		var t := 0.0
		while main.state != main.St.RUN and t < 10.0:
			await _frames(2)
			t += 0.03
		await _secs(1.0)
		await _check(id, "partida/" + id)
		Config.dev_god_mode = true
		main.arena.phase = Arena.Phase.IDLE
		var pl = GameState.player
		var ct: CaseThrow = GameState.case_throw
		# combate: lanzar y comprobar que la mano se oculta, vuelve y conserva el modelo
		var e: Enemy = main.arena._spawn_enemy("thief", pl.global_position + Vector3(0, 0, -7))
		await _secs(1.5)
		pl.skills.cd[0] = 0.0
		var thrown: bool = pl.skills.try_cast(0)
		await _frames(3)
		ok(thrown, "H2 %s: el ataque primario se lanza" % id)
		var hand := pl.rig.props["case"] as Node3D
		ok(not hand.visible, "H2 %s: la mano se vacía mientras el arma vuela" % id)
		if id != "case":
			await _frames(4)
			get_viewport().get_texture().get_image().save_png("%s/vuelo_%s.png" % [out_dir, id])
		var tt := 0.0
		while ct.in_flight() and tt < 9.0:
			await _frames(2)
			tt += 0.05
		await _secs(0.6)
		ok(hand.visible, "H2 %s: el arma vuelve a la mano" % id)
		await _check(id, "combate/" + id)
		await _closeup("partida_" + id)
		# guardar y reanudar con OTRA herramienta equipada en la sala: manda la de la partida guardada
		var snap: Dictionary = GameState.snapshot_run("fight")
		await main._back_to_lobby() if main.has_method("_back_to_lobby") else null
		await _secs(1.0)
		await _check_lobby(id)
		var other: String = IDS[(IDS.find(id) + 1) % IDS.size()]
		LoadoutDB.equip("weapon", other)
		main._lobby_changed()
		await _frames(4)
		await _check(other, "sala-tras-volver/" + other)
		main._go_to_run(snap)
		t = 0.0
		while main.state != main.St.RUN and t < 12.0:
			await _frames(2)
			t += 0.03
		await _secs(1.0)
		await _check(id, "reanudada/" + id)
		await main._back_to_lobby()
		await _secs(1.0)
	print("[RESULT] herramienta en la mano: %d ok, %d fallos" % [passes, fails.size()])
	for f in fails:
		print("  FALLO: ", f)
	get_tree().quit(1 if fails.size() > 0 else 0)


func _check_lobby(_id: String) -> void:
	ok(main.state == main.St.LOBBY, "H3 al volver a la sala central se está en la sala")
