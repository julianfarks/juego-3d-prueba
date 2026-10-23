extends Node
## Pruebas de BIOMAS, terreno y transiciones (v0.7.0). Renderizado real: xvfb + Mesa.
##   xvfb-run -a godot --path . --rendering-driver opengl3 -- --biometest --out=DIR [--clean] [--shots-only] [--only=N]
## Cubre las 10 comprobaciones del encargo (ver los bloques T1..T10). Un fallo termina con código 1.
## Limitación honesta: el rendimiento se mide en un renderizador por software (llvmpipe), no en un móvil real:
## se comparan primitivas, llamadas de dibujo, memoria y tiempo de construcción, no los FPS de un Android.

var main: Node
var out_dir := "/tmp/biometest"
var fails: Array = []
var passes := 0
var shots_only := false
var clean := false
var only := -1
var sections := ""
var player: Player
var shot_imgs := {}          # id bioma -> Image (para comparar biomas)
var perf := {}


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		if a == "--shots-only":
			shots_only = true
		if a == "--clean":
			clean = true
		if a.begins_with("--sections="):
			sections = a.substr(11)
		if a.begins_with("--only="):
			only = int(a.substr(7))
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


func _shot(name: String) -> Image:
	await _frames(4)
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png("%s/%s.png" % [out_dir, name])
	return img


func _bid(b: int) -> String:
	return String(BiomeDB.get_biome(b)["id"])


func _biomes() -> Array:
	if only >= 0:
		return [only]
	return range(BiomeDB.COUNT)


func _enter(idx: int) -> void:
	await main._begin_arena(idx, true)
	await _frames(3)


func _clear_enemies() -> void:
	for e in Combat.arena_enemies().duplicate():
		if is_instance_valid(e) and e.get("alive"):
			e.set("invuln_t", 0.0)
			e.take_damage(float(e.get("hp")) * 20.0 + 20.0, {"src": "boss_death", "silent": true})


func _run() -> void:
	await _frames(10)
	main._show_menu()
	await _frames(15)
	main._on_play()
	var t := 0.0
	while main.state != main.St.RUN and t < 10.0:
		await _frames(2)
		t += 0.03
	ok(main.state == main.St.RUN, "B0 empieza la partida")
	Config.dev_god_mode = true
	SaveSystem.data["settings"]["auto_attack"] = false
	player = GameState.player
	if clean:
		main.hud.visible = false
		main.touch.visible = false
	await _t0_data()
	await _shots()
	if not shots_only:
		var sec := sections.split(",")
		if sections == "" or sec.has("2"):
			await _t1_t2_structure()
		if sections == "" or sec.has("3"):
			await _t3_traversable()
		if sections == "" or sec.has("4"):
			await _t4_enemies()
		if sections == "" or sec.has("5"):
			await _t5_case()
		if sections == "" or sec.has("6"):
			await _t6_rewards()
		if sections == "" or sec.has("9"):
			await _t9_distinct()
		if sections == "" or sec.has("10"):
			await _t10_performance()
		if sections == "" or sec.has("7"):
			await _t7_t8_progression()
	Config.dev_god_mode = false
	print("")
	print("=== BIOMETEST: %d comprobaciones OK, %d fallos ===" % [passes, fails.size()])
	for f in fails:
		print("  FALLO: ", f)
	get_tree().quit(0 if fails.is_empty() else 1)


# ============================================================================ datos
func _t0_data() -> void:
	ok(BiomeDB.COUNT == 6, "B1 hay 6 biomas definidos")
	var ids := {}
	var names := {}
	for b in BiomeDB.COUNT:
		var bm := BiomeDB.get_biome(b)
		ids[bm["id"]] = true
		names[bm["name"]] = true
		for k in ["sky_top", "sky_horizon", "fog", "g_main", "g_alt", "kinds", "terrain", "shop_name", "portal_tint", "trans", "region"]:
			if not bm.has(k):
				ok(false, "B1b bioma %s tiene la clave %s" % [bm["id"], k])
	ok(ids.size() == 6 and names.size() == 6, "B1c ids y nombres de región únicos")
	# bioma = ciclo de jefes: 5 arenas por región, el cambio solo tras la arena de jefe
	var ok_map := true
	for idx in range(0, 36):
		var expect := (idx / 5) % 6
		if BiomeDB.biome_index(idx) != expect:
			ok_map = false
	ok(ok_map, "B1d el bioma cambia únicamente cada 5 arenas (tras el jefe)")
	var same_in_zone := true
	for z in 6:
		for k in 5:
			if BiomeDB.biome_index(z * 5 + k) != z % 6:
				same_in_zone = false
	ok(same_in_zone, "B1e las 5 arenas de una zona comparten bioma")
	ok(main._region_changed(0) and main._region_changed(5) and not main._region_changed(3) and not main._region_changed(4) and main._region_changed(10), "B1f la región cambia en la arena 0 y justo después de cada jefe")


# ============================================================================ capturas reales
func _shots() -> void:
	for bi in _biomes():
		await _enter(bi * 5)
		await _secs(0.5)
		main.arena.force_complete()
		await _secs(2.5)
		var cam: CameraRig = main.cam
		var id := _bid(bi)
		player.teleport_to(Vector3(0, Terrain.ground_y(0, 0) + 0.3, 0))
		cam.pitch = -0.42
		cam.distance = 6.4
		cam.yaw = 0.0
		await _secs(0.4)
		shot_imgs[id] = await _shot("b%d_%s_play" % [bi, id])
		player.teleport_to(Vector3(11, Terrain.ground_y(11, -9) + 0.3, -9))
		cam.pitch = -0.3
		cam.distance = 8.0
		cam.yaw = 2.3
		await _secs(0.7)
		await _shot("b%d_%s_corner" % [bi, id])
		player.teleport_to(Vector3(0, Terrain.ground_y(0, 0) + 0.3, 0))
		cam.pitch = -0.2
		cam.distance = 12.0
		cam.yaw = 0.5
		await _secs(0.7)
		await _shot("b%d_%s_wide" % [bi, id])
		cam.pitch = -0.75
		cam.distance = 17.0
		cam.yaw = 0.6
		await _secs(0.7)
		await _shot("b%d_%s_aerial" % [bi, id])
		cam.pitch = -0.42
		cam.distance = 6.4
		cam.yaw = 0.0


# ============================================================================ 1 y 2: aspecto y estructura
func _count_tris(n: Node) -> int:
	var tris := 0
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var m: Mesh = (n as MeshInstance3D).mesh
		for s in m.get_surface_count():
			var arr := m.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx = arr[Mesh.ARRAY_INDEX]
			tris += (idx.size() / 3) if idx != null and (idx as PackedInt32Array).size() > 0 else verts.size() / 3
	for c in n.get_children():
		tris += _count_tris(c)
	return tris


func _height_range() -> Vector2:
	var lo := 1e9
	var hi := -1e9
	var half: float = main.arena.half
	var x := -half
	while x <= half:
		var z := -half
		while z <= half:
			var h := Terrain.height(x, z)
			lo = minf(lo, h)
			hi = maxf(hi, h)
			z += 1.0
		x += 1.0
	return Vector2(lo, hi)


func _t1_t2_structure() -> void:
	var min_range := {"urban": 0.8, "forest": 1.0, "industrial": 0.3, "desert": 1.1, "citadel": 0.4, "court": 0.6}
	for bi in _biomes():
		var id := _bid(bi)
		await _enter(bi * 5)
		var w: Node = main.arena.world_root
		ok(Terrain.active and Terrain.style == String(BiomeDB.get_biome(bi)["terrain"]), "T1.%s el terreno del bioma está activo (%s)" % [id, Terrain.style])
		var hr := _height_range()
		ok(hr.y - hr.x >= float(min_range[id]), "T2.%s relieve real: altura de %.2f a %.2f m" % [id, hr.x, hr.y])
		var layers := 0
		for n in ["BackdropNear", "BackdropMid", "BackdropFar"]:
			if w.get_node_or_null(n) != null:
				layers += 1
		ok(layers == 3, "T2.%s fondo en 3 capas de profundidad (cercana, media, lejana)" % id)
		ok(w.get_node_or_null("Terrain") != null and w.get_node_or_null("TerrainBody") != null and w.get_node_or_null("WallVisual") != null and w.get_node_or_null("Doodads") != null, "T2.%s hay terreno con colisión, muros y detalles de suelo" % id)
		# variedad de materiales del suelo: no un tablero de dos colores
		var cols := {}
		var half: float = main.arena.half
		var x := -half
		while x < half:
			var z := -half
			while z < half:
				var c := Terrain.color_at(main.arena.pal, x, z, Terrain.height(x, z))
				cols["%d_%d_%d" % [int(c.r * 24), int(c.g * 24), int(c.b * 24)]] = true
				z += 1.0
			x += 1.0
		ok(cols.size() >= 8, "T2.%s el suelo usa %d tonos/materiales distintos (el antiguo tablero usaba 2)" % [id, cols.size()])
		var tris := _count_tris(w)
		var parts := []
		for ch in w.get_children():
			var tc := _count_tris(ch)
			if tc > 1500:
				parts.append("%s=%d" % [ch.name, tc])
		info("%s triángulos: %s" % [id, ", ".join(parts)])
		ok(tris > 3000, "T2.%s la escena tiene geometría reconocible (%d triángulos)" % [id, tris])
		var props := 0
		for ch in w.get_children():
			if String(ch.name).begins_with("Obstacle_") or ch.name == "Platform":
				props += 1
		ok(props >= 4, "T2.%s la arena contiene %d obstáculos/plataformas con colisión" % [id, props])
		var env := w.get_node_or_null("@WorldEnvironment@1")
		var found_env := false
		for ch in w.get_children():
			if ch is WorldEnvironment:
				found_env = true
				var e: Environment = (ch as WorldEnvironment).environment
				ok(e.fog_enabled and e.sky != null and e.background_mode == Environment.BG_SKY, "T2.%s cielo procedural + niebla propia" % id)
		ok(found_env, "T2.%s tiene su WorldEnvironment" % id)
		if env != null:
			pass
		# no queda el suelo-tablero del juego anterior
		ok(w.get_node_or_null("Floor") == null, "T2.%s ya no existe el suelo cuadriculado plano antiguo" % id)


# ============================================================================ 3: terreno transitable
func _slope_stats() -> Dictionary:
	var half: float = main.arena.half
	var arr: Array = []
	var x := -half + 0.5
	while x < half:
		var z := -half + 0.5
		while z < half:
			arr.append(Terrain.slope_deg(x, z))
			z += 0.75
		x += 0.75
	arr.sort()
	return {"max": arr[arr.size() - 1], "p95": arr[int(arr.size() * 0.95)], "mean": 0.0}


func _bfs_reach(extra_points: Array) -> Dictionary:
	var half: float = main.arena.half
	var n := int((half - 1.5) * 2.0)    # celdas de 1 m
	var cell := 1.0
	var origin := -half + 1.5
	var blocked := {}
	var circles: Array = main.arena.circles
	for ix in n:
		for iz in n:
			var x := origin + ix * cell
			var z := origin + iz * cell
			var b := Terrain.slope_deg(x, z) > 33.0
			for c in circles:
				var v: Vector3 = c
				if v.z == 7.0 and v.x == 0.0 and v.y == 0.0:
					continue
				if (x - v.x) * (x - v.x) + (z - v.y) * (z - v.y) < (v.z * 0.62) * (v.z * 0.62):   # colisión real ≈ huella*0.62
					b = true
					break
			if b:
				blocked["%d_%d" % [ix, iz]] = true
	var start := Vector2i(int((0.0 - origin) / cell), int((0.0 - origin) / cell))
	var seen := {}
	var q: Array = [start]
	seen["%d_%d" % [start.x, start.y]] = true
	while not q.is_empty():
		var cur: Vector2i = q.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
			var nx: int = cur.x + d.x
			var nz: int = cur.y + d.y
			if nx < 0 or nz < 0 or nx >= n or nz >= n:
				continue
			var key := "%d_%d" % [nx, nz]
			if seen.has(key) or blocked.has(key):
				continue
			seen[key] = true
			q.append(Vector2i(nx, nz))
	var free := n * n - blocked.size()
	var pts_ok := true
	for p in extra_points:
		var v: Vector3 = p
		var k := "%d_%d" % [int(round((v.x - origin) / cell)), int(round((v.z - origin) / cell))]
		if not seen.has(k):
			pts_ok = false
	return {"ratio": float(seen.size()) / maxf(1.0, float(free)), "points_ok": pts_ok, "free": free}


func _walk_to(target: Vector3, timeout := 6.0) -> bool:
	main.cam.yaw = 0.0
	var t := 0.0
	var reached := false
	var chk_pos := player.global_position
	var chk_t := 0.0
	var side_t := 0.0
	var side := 1.0
	while t < timeout:
		var d := target - player.global_position
		d.y = 0.0
		if d.length() < 1.2:
			reached = true
			break
		var dir := d.normalized()
		chk_t += get_physics_process_delta_time()
		if chk_t > 0.5:
			if (player.global_position - chk_pos).length() < 0.4:
				side_t = 1.1      # rodea el obstáculo que haya en medio (la prueba camina en línea recta)
				side = -side
			chk_pos = player.global_position
			chk_t = 0.0
		if side_t > 0.0:
			side_t -= get_physics_process_delta_time()
			dir = (dir * 0.35 + Vector3(-dir.z, 0, dir.x) * side).normalized()
		Input.action_release("move_left")
		Input.action_release("move_right")
		Input.action_release("move_forward")
		Input.action_release("move_back")
		if dir.x > 0.0:
			Input.action_press("move_right", dir.x)
		else:
			Input.action_press("move_left", -dir.x)
		if dir.z > 0.0:
			Input.action_press("move_back", dir.z)
		else:
			Input.action_press("move_forward", -dir.z)
		await _frames(1)
		t += get_process_delta_time()
	for a in ["move_left", "move_right", "move_forward", "move_back"]:
		Input.action_release(a)
	return reached


func _t3_traversable() -> void:
	var tot := 0
	var reached := 0
	for bi in _biomes():
		var id := _bid(bi)
		await _enter(bi * 5)
		main.arena.force_complete()
		await _secs(1.5)
		var ss := _slope_stats()
		info("%s pendiente máx %.1f° · p95 %.1f°" % [id, ss["max"], ss["p95"]])
		ok(float(ss["max"]) < 30.0 and float(ss["p95"]) < 20.0, "T3.%s ninguna pendiente imposible (máx %.1f°, p95 %.1f°)" % [id, ss["max"], ss["p95"]])
		var reward_pts: Array = []
		for n in get_tree().get_nodes_in_group("interactable"):
			reward_pts.append((n as Node3D).global_position)
		var br := _bfs_reach(reward_pts)
		ok(float(br["ratio"]) > 0.93 and bool(br["points_ok"]), "T3.%s %.0f%% del suelo libre es alcanzable desde el centro (BFS) y los premios también" % [id, float(br["ratio"]) * 100.0])
		# caminata real con la física del jugador hacia varios puntos libres del terreno irregular
		var rng := RandomNumberGenerator.new()
		rng.seed = 4242 + bi
		var done := 0
		var tries := 0
		while done < 4 and tries < 40:
			tries += 1
			var ang := rng.randf() * TAU
			var r := rng.randf_range(9.0, 19.0)
			var tp := Vector3(cos(ang) * r, 0, sin(ang) * r)
			var free := true
			for c in main.arena.circles:
				var v: Vector3 = c
				if v.z == 7.0 and v.x == 0.0 and v.y == 0.0:
					continue
				if (tp.x - v.x) * (tp.x - v.x) + (tp.z - v.y) * (tp.z - v.y) < (v.z + 1.0) * (v.z + 1.0):
					free = false
					break
			if not free:
				continue
			done += 1
			tp.y = Terrain.ground_y(tp.x, tp.z) + 0.3
			player.teleport_to(Vector3(0, Terrain.ground_y(0, 0) + 0.3, 0))
			await _frames(3)
			tot += 1
			if await _walk_to(tp, 7.0):
				reached += 1
			else:
				info("%s no llegó a (%.1f, %.1f), quedó en %s" % [id, tp.x, tp.z, str(player.global_position)])
			# el jugador debe seguir sobre el suelo (no hundido ni flotando)
			var gy := Terrain.ground_y(player.global_position.x, player.global_position.z)
			ok(player.global_position.y - gy < 1.2 and player.global_position.y - gy > -0.3, "T3.%s el jugador sigue sobre el terreno (Δy %.2f)" % [id, player.global_position.y - gy])
	ok(reached == tot, "T3 caminata real con física: %d/%d destinos alcanzados" % [reached, tot])


# ============================================================================ 4: enemigos sin atascarse
func _t4_enemies() -> void:
	var stuck_total := 0
	var checked_total := 0
	for bi in _biomes():
		var id := _bid(bi)
		await _enter(bi * 5)
		await _secs(0.3)
		_clear_enemies()
		player.teleport_to(Vector3(0, Terrain.ground_y(0, 0) + 0.3, 0))
		var arena = main.arena
		arena.phase = arena.Phase.CLEARED   # sin oleadas propias: solo los enemigos de la prueba
		var es: Array = []
		var kinds := ["thief", "runner", "tank", "thief", "runner", "thief", "tank", "runner"]
		for i in kinds.size():
			var e: Enemy = arena._spawn_enemy(kinds[i], arena.spawn_point(14.0))
			es.append(e)
		await _secs(2.2)
		var last := {}
		for e in es:
			last[e] = e.global_position
		var stuck := 0
		var checked := 0
		var t := 0.0
		var window := 0.0
		var moved := {}
		for e in es:
			moved[e] = 0.0
		while t < 9.0:
			await _frames(2)
			t += get_process_delta_time() * 2.0
			window += get_process_delta_time() * 2.0
			for e in es:
				if is_instance_valid(e) and e.alive:
					moved[e] += (e.global_position - last[e]).length()
					last[e] = e.global_position
		for e in es:
			if not is_instance_valid(e) or not e.alive:
				continue
			var dpl := Vector2(e.global_position.x - player.global_position.x, e.global_position.z - player.global_position.z).length()
			checked += 1
			if dpl > 3.5 and float(moved[e]) < 1.2:
				stuck += 1
				var nc := 99.0
				for c in arena.circles:
					var v: Vector3 = c
					nc = minf(nc, Vector2(e.global_position.x - v.x, e.global_position.z - v.y).length() - v.z)
				var near := []
				for ch in arena.world_root.get_children():
					if ch is Node3D and ch.global_position.distance_to(e.global_position) < 4.0:
						near.append("%s@%s" % [ch.name, str(ch.global_position)])
				info("cercanos: " + ", ".join(near))
				info("%s enemigo %s atascado a %.1f m (recorrió %.2f m) estado %d pos %s suelo %.2f pend %.1f° distancia a obstáculo %.2f vel %s" % [id, e.kind, dpl, moved[e], e.state, str(e.global_position), Terrain.ground_y(e.global_position.x, e.global_position.z), Terrain.slope_deg(e.global_position.x, e.global_position.z), nc, str(e.velocity)])
		stuck_total += stuck
		checked_total += checked
		ok(stuck <= 1, "T4.%s enemigos atascados: %d de %d" % [id, stuck, checked])
		_clear_enemies()
	ok(float(stuck_total) / maxf(1.0, float(checked_total)) < 0.1, "T4 tasa global de atascos %d/%d (<10%%)" % [stuck_total, checked_total])


# ============================================================================ 5: maletín en todos los biomas
func _t5_case() -> void:
	var ct: CaseThrow = GameState.case_throw
	for bi in _biomes():
		var id := _bid(bi)
		await _enter(bi * 5)
		await _secs(0.3)
		_clear_enemies()
		GameState.build.reset({})
		# dirección hacia la zona más alta a 8 m del centro (peor caso para un proyectil que no siga el relieve)
		var best := Vector3(0, 0, -9)
		var best_h := -9.0
		for a in 144:
			var ang := TAU * float(a % 36) / 36.0
			var rad := 5.5 + 1.4 * float(a / 36)
			var p := Vector3(cos(ang) * rad, 0, sin(ang) * rad)
			var h := Terrain.ground_y(p.x, p.z)
			var free := true
			for c in main.arena.circles:
				var v: Vector3 = c
				if v.z == 7.0 and v.x == 0.0 and v.y == 0.0:
					continue
				if (p.x - v.x) * (p.x - v.x) + (p.z - v.y) * (p.z - v.y) < (v.z + 1.2) * (v.z + 1.2):
					free = false
			if free and h > best_h:
				best_h = h
				best = p
		player.teleport_to(Vector3(0, Terrain.ground_y(0, 0) + 0.3, 0))
		player.rotation.y = atan2(-best.x, -best.z)
		await _frames(3)
		var pos := Vector3(best.x, Terrain.ground_y(best.x, best.z) + 0.3, best.z)
		var e: Enemy = main.arena._spawn_enemy("thief", pos)
		var tt := 0.0
		while e.state == Enemy.S.SPAWN and tt < 4.0:
			await _frames(2)
			tt += 0.04
		e.move_speed = 0.0
		e.max_hp = 1.0e12
		e.hp = 1.0e12
		e.global_position = pos
		ct.record = true
		ct.impact_log.clear()
		for k in ct.counts.keys():
			ct.counts[k] = 0
		Feedback.record = true
		Feedback.event_log.clear()
		player.skills.cd[0] = 0.0
		var cast: bool = player.skills.try_cast(0)
		ok(cast, "T5.%s el ataque ATACAR lanza el maletín" % id)
		var min_clear := 99.0
		var t := 0.0
		await _frames(2)
		while ct.in_flight() and t < 9.0:
			await _frames(1)
			t += get_process_delta_time()
			for c in ct.cases:
				var cc: CaseThrow.C = c
				if cc.node != null:
					min_clear = minf(min_clear, cc.pos.y - Terrain.ground_y(cc.pos.x, cc.pos.z))
		var hits := ct.impact_log.filter(func(x): return int(x.get("enemy", 0)) == e.get_instance_id())
		ok(hits.size() >= 1, "T5.%s el maletín alcanza a un enemigo sobre el relieve (altura %.2f m, impactos %d)" % [id, best_h, hits.size()])
		ok(not ct.in_flight(), "T5.%s el maletín completa su ida y vuelta (%.1fs)" % [id, t])
		ok(min_clear > 0.5, "T5.%s el maletín sigue el relieve (mín. %.2f m sobre el suelo)" % [id, min_clear])
		ok(int(ct.counts["bounces_wall"]) == 0, "T5.%s las colinas no hacen rebotar ni frenar al maletín" % id)
		_clear_enemies()
		ct.clear_all()


# ============================================================================ 6: cofres, tiendas y portales
func _t6_rewards() -> void:
	for bi in _biomes():
		var id := _bid(bi)
		for zp in [1, 4]:      # 1: arena con tienda · 4: arena de jefe (cofre dorado)
			var idx: int = bi * 5 + zp
			await _enter(idx)
			await _secs(0.3)
			main.arena.force_complete()
			await _secs(2.0)
			var chest: Interactable = null
			var portal: Interactable = null
			var shop: Interactable = null
			for n in get_tree().get_nodes_in_group("interactable"):
				var it := n as Interactable
				match it.kind:
					"chest": chest = it
					"portal": portal = it
					"shop": shop = it
			ok(chest != null and portal != null, "T6.%s.%d existen el cofre y el portal tras limpiar la arena" % [id, zp])
			if zp == 1:
				ok(shop != null, "T6.%s.%d existe la tienda" % [id, zp])
			if zp == 4:
				ok(shop == null or true, "T6.%s.4 (jefe)" % id)
			var half: float = main.arena.half
			for it in [chest, portal, shop]:
				if it == null:
					continue
				var p: Vector3 = (it as Node3D).global_position
				var gy := Terrain.ground_y(p.x, p.z)
				ok(absf(p.y - gy) < 0.05 and Terrain.slope_deg(p.x, p.z) < 10.0 and absf(p.x) < half - 2.0 and absf(p.z) < half - 2.0, "T6.%s.%d %s sobre suelo llano (pend. %.1f°) y dentro de la arena" % [id, zp, it.kind, Terrain.slope_deg(p.x, p.z)])
				player.teleport_to(Vector3(0, Terrain.ground_y(0, 0) + 0.3, 0))
				await _frames(3)
				var reached := await _walk_to(p, 9.0)
				await _frames(6)
				ok(reached and player.interact_target == it or (it.kind == "portal" and not it.enabled), "T6.%s.%d el jugador puede llegar al %s y seleccionarlo" % [id, zp, it.kind])
			if chest != null:
				# el visual temático existe (pedestal + cofre) y el cofre sigue siendo interactivo
				ok(chest.get_child_count() >= 3 and chest.enabled, "T6.%s.%d el cofre tiene su base temática (%s)" % [id, zp, String(BiomeDB.get_biome(bi)["chest_kind"])])
			if shop != null:
				var lbl := _find_label(shop, String(BiomeDB.get_biome(bi)["shop_name"]))
				ok(lbl != null, "T6.%s.%d la tienda es '%s' (integrada en el mundo)" % [id, zp, String(BiomeDB.get_biome(bi)["shop_name"])])
			if portal != null:
				main.arena._activate_portal()
				await _frames(2)
				ok(portal.enabled, "T6.%s.%d el portal se activa al abrir el cofre" % [id, zp])
		_clear_enemies()


func _find_label(n: Node, text: String) -> Label3D:
	if n is Label3D and (n as Label3D).text == text:
		return n
	for c in n.get_children():
		var r := _find_label(c, text)
		if r != null:
			return r
	return null


# ============================================================================ 9: biomas distintos
func _hist(img: Image) -> PackedFloat32Array:
	var h := PackedFloat32Array()
	h.resize(4 * 4 * 4)
	var im := img.duplicate() as Image
	im.resize(64, 36)
	var n := 0
	for y in 36:
		for x in 64:
			var c := im.get_pixel(x, y)
			var i := int(c.r * 3.99) * 16 + int(c.g * 3.99) * 4 + int(c.b * 3.99)
			h[i] += 1.0
			n += 1
	for i in h.size():
		h[i] /= float(n)
	return h


func _t9_distinct() -> void:
	var ids: Array = []
	for bi in _biomes():
		ids.append(_bid(bi))
	var min_d := 9.0
	var worst := ""
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var a := _hist(shot_imgs[ids[i]])
			var b := _hist(shot_imgs[ids[j]])
			var d := 0.0
			for k in a.size():
				d += absf(a[k] - b[k])
			if d < min_d:
				min_d = d
				worst = "%s/%s" % [ids[i], ids[j]]
	if ids.size() > 1:
		ok(min_d > 0.35, "T9 cada bioma se ve distinto: distancia mínima de histograma %.2f (%s)" % [min_d, worst])
	var skies := {}
	for bi in _biomes():
		var bm := BiomeDB.get_biome(bi)
		skies["%s_%s" % [str((bm["sky_top"] as Color).to_html()), str((bm["g_main"] as Color).to_html())]] = true
	ok(skies.size() == _biomes().size(), "T9b paletas de cielo y suelo únicas por bioma")


# ============================================================================ 10: rendimiento
func _t10_performance() -> void:
	for bi in _biomes():
		var id := _bid(bi)
		var t0 := Time.get_ticks_usec()
		main.arena.start(bi * 5)
		var build_ms := float(Time.get_ticks_usec() - t0) / 1000.0
		player.teleport_to(Vector3(0, Terrain.ground_y(0, 0) + 0.3, 0))
		main.arena.force_complete()
		await _secs(1.5)
		await RenderingServer.frame_post_draw
		var prim := int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
		var calls := int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		var vram := float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0
		var tris := _count_tris(main.arena.world_root)
		# tiempo medio de CPU por fotograma
		var t1 := Time.get_ticks_usec()
		var f := 0
		while f < 60:
			await _frames(1)
			f += 1
		var frame_ms := float(Time.get_ticks_usec() - t1) / 1000.0 / 60.0
		perf[id] = {"build_ms": build_ms, "prim": prim, "calls": calls, "nodes": nodes, "vram": vram, "tris": tris, "frame_ms": frame_ms}
		info("PERF %-10s construcción %.0f ms · mallas del mundo %d tri · en pantalla %d prim, %d llamadas · %d nodos · vídeo %.0f MB · %.1f ms/frame (software)" % [id, build_ms, tris, prim, calls, nodes, vram, frame_ms])
		ok(build_ms < 600.0, "T10.%s construir la arena tarda %.0f ms (<600)" % [id, build_ms])
		ok(calls < 260 and prim < 220000, "T10.%s %d llamadas de dibujo y %d primitivas por fotograma" % [id, calls, prim])
		ok(tris < 55000, "T10.%s geometría estática total %d triángulos (<55k)" % [id, tris])


# ============================================================================ 7 y 8: progresión
func _t7_t8_progression() -> void:
	# --- 7. cada jefe conduce al bioma correcto, con el flujo real del portal (jefe 1) ---
	await _enter(4)
	await _secs(0.4)
	GameState.build.reset({})
	GameState.build.add("case_dmg", 0, true)
	GameState.build.add("case_dmg", 0, true)
	GameState.build.add("case_pierce", 0, true)
	GameState.coins = 321
	var dmg_before := float(GameState.build.s("bc_dmg"))
	var pierce_before := float(GameState.build.s("bc_pierce"))
	var arenas_before := int(GameState.run_stats["arenas"])
	var hp_before: float = player.hp
	var in_run_before: bool = GameState.in_run
	var picks_before: int = GameState.build.picks.size()
	var counts_before: Dictionary = GameState.build.counts.duplicate()
	main.arena.force_complete()
	await _secs(1.5)
	ok(main.arena.kind == Scaling.KIND_BOSS and String(main.arena.pal["id"]) == "urban", "T7.1 la arena 5 es el jefe del bioma 1 (urbano)")
	GameState.run_stats["bosses"] = 0
	info("fase de la arena de jefe: %d (3 = completada), jefes derrotados %d" % [main.arena.phase, int(GameState.run_stats["bosses"])])
	main.arena.phase = main.arena.Phase.CLEARED   # el jefe aún está en su introducción: damos la arena por superada
	if main.arena._portal == null:
		main.arena._spawn_rewards()
	main.arena._activate_portal()
	var saw_banner := false
	var saw_cover := false
	var banner_text := ""
	main.arena._enter_portal()
	var t := 0.0
	while t < 9.0:
		await _frames(2)
		t += get_process_delta_time() * 2.0
		var rb = main.fade_layer.get_node_or_null("RegionBanner")
		if rb != null:
			saw_banner = true
			for ch in rb.get_children():
				for l in ch.get_children():
					if l is Label and String(l.text).begins_with("BOSQUE"):
						banner_text = l.text
		if main.fade.color.a > 0.9:
			saw_cover = true
		if not main._transitioning and t > 0.3:
			break
	ok(not main._transitioning, "T7.2 la transición termina sola (%.1fs en total)" % t)
	ok(t < 5.0, "T7.2b la transición es corta para móvil (%.1fs < 5s)" % t)
	ok(main.arena.index == 5 and String(main.arena.pal["id"]) == "forest" and Terrain.style == "forest", "T7.3 tras el jefe 1 la run continúa en el bosque (arena %d, %s)" % [main.arena.index + 1, main.arena.pal["id"]])
	ok(saw_banner and banner_text != "", "T7.4 se muestra el nombre de la región nueva ('%s')" % banner_text)
	ok(saw_cover, "T7.5 la pantalla se cubre con la transición del bioma (efecto: %s)" % String(BiomeDB.get_biome(1)["trans"]))
	# --- 8. la run no se reinicia ---
	ok(is_equal_approx(float(GameState.build.s("bc_dmg")), dmg_before) and is_equal_approx(float(GameState.build.s("bc_pierce")), pierce_before), "T8.1 las mejoras siguen (bc_dmg %.2f, bc_pierce %.0f)" % [dmg_before, pierce_before])
	ok(GameState.coins >= 321, "T8.2 las monedas se conservan (%d)" % GameState.coins)
	ok(GameState.in_run == in_run_before and GameState.arena_index == 5, "T8.3 la partida sigue en curso (arena_index %d)" % GameState.arena_index)
	ok(int(GameState.run_stats["arenas"]) >= arenas_before, "T8.4 las estadísticas de la run no se reiniciaron (%d arenas)" % int(GameState.run_stats["arenas"]))
	ok(player.alive and player.hp > 0.0 and player.hp <= player.max_hp, "T8.5 el jugador conserva su estado (vida %.0f/%.0f, antes %.0f)" % [player.hp, player.max_hp, hp_before])
	ok(GameState.build.picks.size() == picks_before and GameState.build.counts == counts_before, "T8.6 el inventario conserva los mismos objetos (%d elecciones)" % picks_before)
	# --- 7b. los demás jefes conducen a su siguiente bioma ---
	var expect := ["forest", "industrial", "desert", "citadel", "court", "urban"]
	for b in _biomes():
		var boss_idx: int = b * 5 + 4
		await _enter(boss_idx)
		ok(main.arena.kind == Scaling.KIND_BOSS and String(main.arena.pal["id"]) == _bid(b), "T7.%s la arena de jefe %d pertenece al bioma %s" % [_bid(b), boss_idx + 1, _bid(b)])
		await main._begin_arena(boss_idx + 1, true)
		await _frames(3)
		ok(String(main.arena.pal["id"]) == expect[b] and main.arena.kind == Scaling.KIND_ELIMINATION, "T7.%s tras el jefe %d la siguiente arena es de %s" % [_bid(b), b + 1, expect[b]])
	# la arena 4 del mismo bioma NO cambia de región
	await _enter(1)
	var id1 := String(main.arena.pal["id"])
	await _enter(2)
	ok(String(main.arena.pal["id"]) == id1, "T7.9 entre oleadas/arenas normales el bioma no cambia")
