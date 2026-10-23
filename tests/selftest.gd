extends Node
## Autoprueba de juego (se activa con:  godot --path . --selftest [--out=DIR] [--arenas=N] [--stress])
## Juega de verdad: arranca una partida, mueve y ataca automáticamente, completa arenas, abre cofres,
## elige cartas, compra en la tienda y llega al jefe. Guarda capturas y un informe JSON.
## No sustituye a una prueba manual en un móvil real: solo detecta errores de lógica/crash.

var main: Node
var out_dir := "/tmp/selftest"
var max_arenas := 6
var stress := false
var start_idx := 0
var report := {"started": "", "events": [], "errors": [], "arenas": [], "min_enemies": 9999, "max_enemies": 0, "max_projectiles": 0, "fps_samples": []}
var _frame := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a.begins_with("--arenas="):
			max_arenas = int(a.substr(9))
		elif a.begins_with("--start="):
			start_idx = int(a.substr(8))
		elif a == "--stress":
			stress = true
	DirAccess.make_dir_recursive_absolute(out_dir)
	report["started"] = Time.get_datetime_string_from_system()
	call_deferred("_run")


func _log(msg: String) -> void:
	print("[SELFTEST] ", msg)
	(report["events"] as Array).append(msg)


func _fail(msg: String) -> void:
	print("[SELFTEST][FAIL] ", msg)
	(report["errors"] as Array).append(msg)


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


func _run() -> void:
	await _frames(10)
	Engine.time_scale = 1.0
	# --- pruebas de controles táctiles (eventos reales) ---
	main._show_menu()
	await _frames(30)
	await _shot("00_menu")
	main._ov_root().get_child(0).queue_free() if false else null
	main.menu.queue_free()
	main.menu = null
	main.world.remove_child(main.stage)
	main.stage.queue_free()
	main.stage = null
	main._start_run()
	await _frames(20)
	await _test_touch()
	Config.dev_god_mode = true
	if stress:
		_stress_build()
	var idx := start_idx
	if idx > 0:
		main._begin_arena(idx, true)
		await _frames(5)
	while idx < max_arenas:
		var ok := await _play_arena(idx)
		if not ok:
			break
		idx += 1
		if idx < max_arenas:
			main._begin_arena(idx, true)
			await _frames(5)
	_finish()


func _test_touch() -> void:
	Input.use_accumulated_input = false
	var t: TouchControls = main.touch
	_log('touch visible=%s size=%s parent=%s hud=%s ov=%s vp=%s' % [t.visible, t.size, t.get_parent().size, main.hud.size, main._ov_root().size, get_viewport().get_visible_rect().size])
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.pressed = true
	down.position = _w(Vector2(220, 520))
	Input.parse_input_event(down)
	await _frames(2)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = _w(Vector2(300, 440))
	drag.relative = Vector2(80, -80)
	Input.parse_input_event(drag)
	await _frames(2)
	var mv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if mv.length() < 0.2:
		_fail("joystick táctil no produjo movimiento (%s)" % mv)
	else:
		_log("joystick táctil OK: %s" % mv)
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.pressed = false
	up.position = _w(drag.position)
	Input.parse_input_event(up)
	await _frames(2)
	mv = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if mv.length() > 0.01:
		_fail("joystick no se soltó")
	# cámara por gestos
	var yaw0: float = main.cam.yaw
	var d2 := InputEventScreenTouch.new()
	d2.index = 1
	d2.pressed = true
	d2.position = _w(Vector2(900, 300))
	Input.parse_input_event(d2)
	await _frames(2)
	var dr2 := InputEventScreenDrag.new()
	dr2.index = 1
	dr2.position = _w(Vector2(960, 300))
	dr2.relative = Vector2(60, 0)
	Input.parse_input_event(dr2)
	await _frames(2)
	if absf(main.cam.yaw - yaw0) < 0.001:
		_fail("gesto de cámara no registrado")
	else:
		_log("gesto de cámara OK")
	var u2 := InputEventScreenTouch.new()
	u2.index = 1
	u2.pressed = false
	u2.position = _w(dr2.position)
	Input.parse_input_event(u2)
	await _frames(2)
	# botón de ataque
	var c: Vector2 = t._center("attack")
	var ba := InputEventScreenTouch.new()
	ba.index = 2
	ba.pressed = true
	ba.position = _w(c)
	Input.parse_input_event(ba)
	await _frames(2)
	if not Input.is_action_pressed("attack"):
		_fail("botón atacar no activó la acción (centro %s, btn %s, ptrs %s, pressed %s)" % [c, t._button_at(c), t._pointers, t._pressed])
	else:
		_log("botón atacar OK")
	var bu := InputEventScreenTouch.new()
	bu.index = 2
	bu.pressed = false
	bu.position = _w(c)
	Input.parse_input_event(bu)
	await _frames(2)
	if Input.is_action_pressed("attack"):
		_fail("botón atacar no se soltó")
	GameState.look_delta = Vector2.ZERO


func _stress_build() -> void:
	var all := UpgradeDB.all()
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for i in 40:
		var d: Dictionary = all[rng.randi() % all.size()]
		GameState.build.add(d["id"], rng.randi() % 4)
	GameState.build_changed.emit()
	_log("build de estrés: %d mejoras, sinergias %s" % [GameState.build.picks.size(), GameState.build.active_synergies])


func _play_arena(idx: int) -> bool:
	var arena: Arena = main.arena
	var rec := {"index": idx, "kind": arena.kind, "ok": false, "time": 0.0, "kills_start": GameState.kills, "forced": false}
	_log("== Arena %d (%s) ==" % [idx + 1, arena.kind])
	var t0 := 0.0
	var shot_mid := false
	var shot_start := false
	var cast_t := 0.0
	var timeout := 120.0 if arena.kind != "boss" else 220.0
	while arena.phase != Arena.Phase.CLEARED:
		var dt := get_process_delta_time()
		await get_tree().physics_frame
		dt = get_physics_process_delta_time()
		t0 += dt
		_autoplay(dt)
		cast_t += dt
		var ne := arena.alive_count()
		report["min_enemies"] = mini(report["min_enemies"], ne)
		report["max_enemies"] = maxi(report["max_enemies"], ne)
		report["max_projectiles"] = maxi(report["max_projectiles"], GameState.projectiles.count())
		if not shot_start and t0 > 3.5:
			shot_start = true
			await _shot("a%02d_start" % (idx + 1))
		if not shot_mid and ne >= 5 and t0 > 6.0:
			shot_mid = true
			await _shot("a%02d_fight" % (idx + 1))
		if t0 > timeout:
			_fail("arena %d: tiempo agotado (%d vivos); se fuerza" % [idx + 1, ne])
			rec["forced"] = true
			arena.force_complete()
			await _secs(1.0)
			if t0 > timeout + 30.0:
				break
		if not GameState.player.alive:
			_fail("el jugador murió con modo Dios activo")
			return false
		Engine.get_frames_per_second()
	rec["time"] = t0
	rec["ok"] = true
	rec["kills"] = GameState.kills - rec["kills_start"]
	(report["fps_samples"] as Array).append(Engine.get_frames_per_second())
	(report["arenas"] as Array).append(rec)
	_log("arena %d completada en %.1fs (bajas %d, forzada=%s)" % [idx + 1, t0, rec["kills"], rec["forced"]])
	await _frames(10)
	Input.action_release("move_forward")
	Input.action_release("attack")
	await _reward_flow(idx)
	return true


func _reward_flow(idx: int) -> void:
	var arena: Arena = main.arena
	await _frames(20)
	# cofre
	var chest: Interactable = null
	var portal: Interactable = null
	for n in get_tree().get_nodes_in_group("interactable"):
		if n.kind == "chest":
			chest = n
		elif n.kind == "portal":
			portal = n
	if chest == null or portal == null:
		_fail("no aparecieron cofre/portal tras completar la arena %d" % (idx + 1))
		return
	if portal.enabled:
		_fail("el portal estaba activo antes de abrir el cofre")
	await _shot("a%02d_rewards" % (idx + 1))
	chest.activate(GameState.player)
	await _secs(1.0)
	var cs: CardSelect = null
	for n in main._ov_root().get_children():
		if n is CardSelect:
			cs = n
	if cs == null:
		_fail("el cofre no abrió la selección de cartas")
	else:
		await _secs(0.8)
		await _shot("a%02d_cards" % (idx + 1))
		var before := GameState.build.picks.size()
		cs._select(0)
		cs._on_confirm()
		await _frames(5)
		if GameState.build.picks.size() != before + 1:
			_fail("elegir carta no añadió la mejora (%d → %d)" % [before, GameState.build.picks.size()])
		else:
			_log("carta elegida OK (%d mejoras)" % GameState.build.picks.size())
		if arena.kind == "boss":
			await _secs(0.5)
			for n in main._ov_root().get_children():
				if n is CardSelect:
					n._select(1)
					n._on_confirm()
	await _frames(10)
	if not portal.enabled:
		_fail("el portal no se activó tras abrir el cofre")
	# tienda
	if arena._shop != null:
		GameState.add_coins(400, false)
		arena._shop.activate(GameState.player)
		await _secs(0.5)
		var sh: ShopUI = null
		for n in main._ov_root().get_children():
			if n is ShopUI:
				sh = n
		if sh == null:
			_fail("la tienda no se abrió")
		else:
			await _shot("a%02d_shop" % (idx + 1))
			var coins0 := GameState.coins
			sh._buy(0)
			if GameState.coins >= coins0:
				_fail("comprar no descontó monedas")
			else:
				_log("compra OK (%d → %d)" % [coins0, GameState.coins])
			# saldo insuficiente: no debe permitir comprar
			var c1 := GameState.coins
			GameState.coins = 0
			sh._buy(1)
			if GameState.coins != 0 or GameState.coins < 0:
				_fail("compra con saldo 0 modificó el saldo")
			GameState.coins = c1
			sh.queue_free()
			await _frames(5)
	get_tree().paused = false


func _autoplay(_dt: float) -> void:
	var p: Player = GameState.player
	var cam: CameraRig = main.cam
	if p == null or not p.alive:
		return
	var en := Combat.nearest_enemy(p.global_position, 80.0)
	if en == null:
		Input.action_release("move_forward")
		return
	var d: Vector3 = en.global_position - p.global_position
	d.y = 0.0
	cam.yaw = atan2(-d.x, -d.z)
	var dist := d.length()
	if dist > 3.0:
		Input.action_press("move_forward", 1.0)
	else:
		Input.action_release("move_forward")
	Input.action_press("attack")
	_frame += 1
	if _frame % 90 == 0:
		p.skills.try_cast(1)
	if _frame % 120 == 0:
		Input.action_press("dodge")
	elif _frame % 120 == 3:
		Input.action_release("dodge")
	if _frame % 70 == 0:
		Input.action_press("jump")
	elif _frame % 70 == 2:
		Input.action_release("jump")


func _finish() -> void:
	var f := FileAccess.open("%s/report.json" % out_dir, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
	var errs: int = (report["errors"] as Array).size()
	print("[SELFTEST] FIN: %d arenas, %d errores de lógica, enemigos máx %d, proyectiles máx %d" % [(report["arenas"] as Array).size(), errs, report["max_enemies"], report["max_projectiles"]])
	get_tree().quit(1 if errs > 0 else 0)


## Convierte coordenadas del lienzo 1280x720 a coordenadas de ventana (el autojuego usa ventanas pequeñas).
func _w(v: Vector2) -> Vector2:
	return v * Vector2(get_window().size) / Vector2(1280, 720)
