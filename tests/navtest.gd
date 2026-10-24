extends Node
## Pruebas de NAVEGACIÓN de enemigos (v0.10.0). Juego REAL bajo xvfb: se colocan enemigos detrás de paredes de verdad
## (colisión física, no maquetas) y se mide si llegan al jugador SIN que este se mueva.
##   xvfb-run -a godot --path . --rendering-driver opengl3 -- --navtest [--only=a,b] [--out=DIR]
## Secciones: map, wall, u, group, ranged, platform, biomes, stuck, perf.
## Limitación honesta: el rendimiento se mide en CPU de servidor con GL por software, no en un Android real;
## se reportan tiempos absolutos y relativos para estimar el margen, no FPS de un móvil.

var main: Node
var fails: Array = []
var passes := 0
var only := ""
var force_seed := -1
var out_dir := "/tmp/navtest"
var player: Player
var arena: Arena
const STILL_WINDOW := 0.1


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		if a.begins_with("--seed="):
			force_seed = int(a.substr(7))
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
		await get_tree().physics_frame


func _secs(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _want(sec: String) -> bool:
	return only == "" or only.split(",").has(sec)


func _run() -> void:
	await _frames(10)
	await main._enter_lobby(true)
	await _frames(15)
	main._on_play()
	var t := 0.0
	while main.state != main.St.RUN and t < 10.0:
		await _frames(2)
		t += 0.03
	ok(main.state == main.St.RUN, "N0 empieza la partida")
	Config.dev_god_mode = true
	SaveSystem.data["settings"]["auto_attack"] = false
	player = GameState.player
	if _want("map"):
		await _t_map()
	if _want("wall"):
		await _t_wall()
	if _want("u"):
		await _t_u()
	if _want("zig"):
		await _t_zig()
	if _want("group"):
		await _t_group()
	if _want("ranged"):
		await _t_ranged()
	if _want("stuck"):
		await _t_stuck()
	if _want("platform"):
		await _t_platform()
	if _want("biomes"):
		await _t_biomes()
	if _want("perf"):
		await _t_perf()
	Config.dev_god_mode = false
	print("")
	print("=== NAVTEST: %d comprobaciones OK, %d fallos ===" % [passes, fails.size()])
	for f in fails:
		print("  FALLO: ", f)
	get_tree().quit(0 if fails.is_empty() else 1)


# ============================================================================ utilidades
## Entra en una arena y la deja "vacía": sin oleadas, sin enemigos y (si clean) sin obstáculos del bioma.
func _setup_arena(idx: int, clean: bool) -> void:
	await main._begin_arena(idx, true)
	await _frames(4)
	arena = main.arena
	if force_seed >= 0:
		var sp: Vector3 = arena.start(idx, force_seed)
		player.teleport_to(sp)
		await _frames(4)
	info("arena %d semilla %d" % [idx, arena.seed_used])
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
	await _frames(3)
	await _rebuild_nav()


## Mapa de navegación de la arena actual (null si el código probado no tiene navegación: sirve para comparar con la versión anterior).
func _nv() -> NavGrid:
	return arena.get("nav")


func _nav_set_ready(b: bool) -> void:
	var nv := _nv()
	if nv != null:
		nv.ready = b


func _rebuild_nav() -> void:
	if not ("nav" in arena):
		return
	arena.set("nav", NavGrid.new(arena.half))
	var guard := 0
	while not _nv().ready and guard < 900:
		await get_tree().physics_frame
		guard += 1


func _box(cx: float, cz: float, sx: float, sy: float, sz: float) -> StaticBody3D:
	var sb := PropsFactory.static_body(Vector3(sx, sy, sz), Vector3(0, sy * 0.5, 0))
	sb.position = Vector3(cx, Terrain.ground_y(cx, cz), cz)
	arena.world_root.add_child(sb)
	return sb


func _put_player(x: float, z: float) -> void:
	player.teleport_to(Vector3(x, Terrain.ground_y(x, z) + 0.3, z))
	player.iframes = 999.0


func _spawn(kind: String, x: float, z: float) -> Enemy:
	var e: Enemy = arena._spawn_enemy(kind, Vector3(x, 0, z))
	e.aggro_range = 999.0
	return e


func _kill_all() -> void:
	for e in arena.active.duplicate():
		if is_instance_valid(e) and e.alive:
			e.invuln_t = 0.0
			e.take_damage(e.hp * 20.0 + 20.0, {"src": "boss_death", "silent": true})
	await _secs(1.2)


func _flat_d(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _in_rect(p: Vector3, r: Rect2) -> bool:
	return r.has_point(Vector2(p.x, p.z))


## Sigue a los enemigos 'secs' segundos y devuelve, por enemigo: reach (s hasta quedar a ≤reach_d), max_still (s máx. parado
## en persecución lejos del jugador), min_d, crossed (¿su centro estuvo dentro de alguno de los rects sólidos?), tele_los / tele_nolos.
func _track(es: Array, secs: float, rects: Array = [], reach_d := 2.8, stop_when_all := true) -> Dictionary:
	var res := {}
	for e in es:
		res[e] = {"reach": -1.0, "still": 0.0, "max_still": 0.0, "min_d": 1e9, "crossed": false,
			"lastpos": e.global_position, "acc": 0.0, "tele_los": 0, "tele_nolos": 0, "prev": e.state, "los_t": 0.0}
	var t := 0.0
	var dt := get_physics_process_delta_time()
	while t < secs:
		await get_tree().physics_frame
		t += dt
		var pp := player.global_position
		var all_in := true
		for e in es:
			var r: Dictionary = res[e]
			if not is_instance_valid(e) or not e.alive:
				continue
			var d := _flat_d(e.global_position, pp)
			r["min_d"] = minf(r["min_d"], d)
			if r["reach"] < 0.0 and d <= reach_d:
				r["reach"] = t
			if r["reach"] < 0.0:
				all_in = false
			for rc in rects:
				if _in_rect(e.global_position, rc):
					r["crossed"] = true
			r["acc"] += dt
			if r["acc"] >= STILL_WINDOW:
				var mv := _flat_d(e.global_position, r["lastpos"])
				r["lastpos"] = e.global_position
				r["acc"] = 0.0
				if e.state == Enemy.S.CHASE and d > 3.2 and mv < 0.1 * 0.4:
					r["still"] += STILL_WINDOW
				else:
					r["still"] = 0.0
				r["max_still"] = maxf(r["max_still"], r["still"])
			if e.state == Enemy.S.TELE and r["prev"] != Enemy.S.TELE:
				var q := PhysicsRayQueryParameters3D.create(e.global_position + Vector3(0, 1, 0), pp + Vector3(0, 1, 0), Config.L_WORLD)
				if Terrain.body_rid.is_valid():
					q.exclude = [Terrain.body_rid]
				if e.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
					r["tele_los"] += 1
				else:
					r["tele_nolos"] += 1
			r["prev"] = e.state
		if stop_when_all and all_in:
			break
	return res


# ============================================================================ mapa de transitabilidad
func _t_map() -> void:
	await _setup_arena(1, true)
	var wall := _box(0, 0, 14, 3, 0.6)
	var crate := _box(10, 10, 2, 1.2, 2)
	await _frames(3)
	await _rebuild_nav()
	var nv: NavGrid = _nv()
	info("mapa %dx%d celdas · bloqueadas pequeño=%d grande=%d · consultas=%d · construcción=%.0f ms (repartida en ticks)" % [nv.n, nv.n, nv.stats["blocked_small"], nv.stats["blocked_large"], nv.stats["queries"], nv.stats["build_ms"]])
	ok(not nv.walkable(Vector3(0, 0, 0), 0), "N1a la pared (0,0) es no transitable")
	ok(not nv.walkable(Vector3(6.5, 0, 0.2), 0), "N1b el extremo de la pared es no transitable")
	ok(nv.walkable(Vector3(0, 0, 4), 0) and nv.walkable(Vector3(0, 0, -4), 0), "N1c el suelo libre a ambos lados SÍ es transitable")
	ok(nv.walkable(Vector3(9.5, 0, 0.2), 0), "N1d pasado el extremo de la pared hay paso")
	ok(not nv.walkable(Vector3(8.7, 0, 10), 0) and not nv.walkable(Vector3(10, 0, 8.7), 0), "N1e el borde de una caja de 1.2 m queda bloqueado (no se puede subir ni atravesar)")
	var wp := nv.stats["blocked_small"] as int
	ok(wp < nv.n * nv.n * 0.1, "N1f arena casi vacía: <10%% de celdas bloqueadas (%d de %d)" % [wp, nv.n * nv.n])
	var marks := {}
	var pc := nv.cell_of(Vector3(0, 0, 7))
	marks[nv.idx(pc.x, pc.y)] = "@"
	var ec := nv.cell_of(Vector3(0, 0, -7))
	marks[nv.idx(ec.x, ec.y)] = "E"
	var f := FileAccess.open(out_dir + "/map_clean.txt", FileAccess.WRITE)
	f.store_string(nv.ascii(0, marks))
	f.close()
	wall.queue_free()
	crate.queue_free()
	await _kill_all()


# ============================================================================ 5 y 6: pared que bloquea el camino directo
func _t_wall() -> void:
	await _setup_arena(1, true)
	var wr := Rect2(-7.0, -0.3, 14.0, 0.6)
	_box(0, 0, 14, 3, 0.6)
	await _frames(3)
	await _rebuild_nav()
	# --- A) sin navegación (comportamiento anterior): debe quedarse atascado contra la pared ---
	_nav_set_ready(false)
	_put_player(0, 7)
	var e0 := _spawn("thief", 0, -7)
	await _secs(1.0)
	var base: Dictionary = await _track([e0], 12.0, [wr], 2.8)
	var br: Dictionary = base[e0]
	info("SIN navegación (código anterior) con una pared simple: llega=%s en %.1f s (el deslizamiento por la pared ya bastaba aquí; el caso difícil es la U)" % [str(br["reach"] >= 0.0), br["reach"]])
	await _kill_all()
	# --- B) con navegación y el jugador QUIETO ---
	_nav_set_ready(true)
	_put_player(0, 7)
	var e1 := _spawn("thief", 0, -7)
	var res: Dictionary = await _track([e1], 20.0, [wr], 2.8)
	var r: Dictionary = res[e1]
	info("CON navegación: llega=%s en %.1f s · mayor parada=%.2f s · cruzó=%s" % [str(r["reach"] >= 0.0), r["reach"], r["max_still"], str(r["crossed"])])
	ok(r["reach"] >= 0.0, "N2b con el camino directo bloqueado, el ladrón encuentra la ruta y llega (jugador quieto)")
	ok(not r["crossed"], "N2c nunca atraviesa la pared")
	ok(r["max_still"] < 1.0, "N3a no se queda inmóvil contra la pared (mayor parada %.2f s < 1 s)" % r["max_still"])
	await _kill_all()
	# --- C) un corredor (rápido) y un tanque (lento, grande) ---
	_put_player(0, 7)
	var er := _spawn("runner", -3, -8)
	var et := _spawn("tank", 3, -8)
	var rs: Dictionary = await _track([er, et], 30.0, [wr], 2.8)
	info("corredor llega en %.1f s · tanque llega en %.1f s" % [rs[er]["reach"], rs[et]["reach"]])
	ok(rs[er]["reach"] >= 0.0 and rs[et]["reach"] >= 0.0, "N2d el corredor y el tanque también rodean la pared")
	ok(rs[er]["reach"] < rs[et]["reach"], "N2e se mantienen las diferencias de velocidad (corredor antes que tanque)")
	ok(not rs[er]["crossed"] and not rs[et]["crossed"], "N2f ninguno cruza la geometría")
	await _kill_all()


# ============================================================================ trampa en U (mínimo local clásico)
func _u_walls() -> Array:
	_box(0, -2, 10.6, 3, 0.6)          # fondo de la U (hacia el jugador)
	_box(-5, -7, 0.6, 3, 10.6)         # brazo izquierdo
	_box(5, -7, 0.6, 3, 10.6)          # brazo derecho
	return [Rect2(-5.3, -2.3, 10.6, 0.6), Rect2(-5.3, -12.3, 0.6, 10.6), Rect2(4.7, -12.3, 0.6, 10.6)]


func _t_u() -> void:
	await _setup_arena(1, true)
	var rects := _u_walls()
	await _frames(3)
	await _rebuild_nav()
	# control: sin navegación (comportamiento anterior) los ladrones dentro de la U se quedan pegados al fondo
	_nav_set_ready(false)
	_put_player(0, 7)
	var c0: Array = [_spawn("thief", 0, -6), _spawn("thief", -2.5, -8), _spawn("thief", 2.5, -8)]
	var cres: Dictionary = await _track(c0, 20.0, rects, 2.8)
	var stuck_n := 0
	for e in c0:
		if cres[e]["reach"] < 0.0:
			stuck_n += 1
	info("SIN navegación: %d de 3 ladrones siguen atrapados en la U tras 20 s" % stuck_n)
	await _kill_all()
	_nav_set_ready(true)
	_put_player(0, 7)
	var es: Array = [_spawn("thief", 0, -6), _spawn("thief", -2.5, -8), _spawn("thief", 2.5, -8)]
	var res: Dictionary = await _track(es, 40.0, rects, 2.8)
	var all_in := true
	var cr := false
	var ms := 0.0
	for e in es:
		var r: Dictionary = res[e]
		info("U: ladrón llega=%s en %.1f s · mayor parada %.2f s" % [str(r["reach"] >= 0.0), r["reach"], r["max_still"]])
		all_in = all_in and r["reach"] >= 0.0
		cr = cr or r["crossed"]
		ms = maxf(ms, r["max_still"])
	ok(all_in, "N4a tres ladrones DENTRO de una U salen (alejándose del jugador) y lo alcanzan")
	ok(not cr, "N4b ninguno atraviesa las paredes de la U")
	ok(ms < 1.5, "N4c sin bloqueo en la U (mayor parada %.2f s < 1.5 s)" % ms)
	await _kill_all()


# ============================================================================ zigzag: dos muros pegados a lados opuestos
func _t_zig() -> void:
	await _setup_arena(1, true)
	_box(-10, -3, 32, 3, 0.6)          # muro 1: ocupa de x=-26 a 6 (hueco a la derecha)
	_box(10, 3, 32, 3, 0.6)            # muro 2: ocupa de x=-6 a 26 (hueco a la izquierda)
	var rects: Array = [Rect2(-26, -3.3, 32, 0.6), Rect2(-6, 2.7, 32, 0.6)]
	await _frames(3)
	await _rebuild_nav()
	# control: comportamiento anterior (sin navegación)
	_nav_set_ready(false)
	_put_player(0, 8)
	var c0 := _spawn("thief", 0, -8)
	var cres: Dictionary = await _track([c0], 30.0, rects, 2.8)
	info("SIN navegación (zigzag): llega=%s min_dist=%.1f m" % [str(cres[c0]["reach"] >= 0.0), cres[c0]["min_d"]])
	await _kill_all()
	_nav_set_ready(true)
	_put_player(0, 8)
	var e := _spawn("thief", 0, -8)
	var e2 := _spawn("thief", 4, -9)
	var res: Dictionary = await _track([e, e2], 45.0, rects, 2.8)
	info("zigzag con navegación: llegan %s / %s en %.1f / %.1f s · mayor parada %.2f s" % [str(res[e]["reach"] >= 0.0), str(res[e2]["reach"] >= 0.0), res[e]["reach"], res[e2]["reach"], maxf(res[e]["max_still"], res[e2]["max_still"])])
	ok(res[e]["reach"] >= 0.0 and res[e2]["reach"] >= 0.0, "N4d los ladrones resuelven el zigzag (dos pasos opuestos) y llegan al jugador quieto")
	ok(not res[e]["crossed"] and not res[e2]["crossed"], "N4e sin atravesar muros")
	await _kill_all()


# ============================================================================ 7: grupo
func _t_group() -> void:
	await _setup_arena(1, true)
	var rects := _u_walls()
	_box(-12, 4, 6, 3, 0.6)
	_box(12, 4, 6, 3, 0.6)
	rects.append(Rect2(-15, 3.7, 6, 0.6))
	rects.append(Rect2(9, 3.7, 6, 0.6))
	await _frames(3)
	await _rebuild_nav()
	_put_player(0, 8)
	var es: Array = []
	for i in 6:
		es.append(_spawn("thief", -4 + i * 1.6, -5 - (i % 2) * 2.0))
	es.append(_spawn("tank", 0, -9))
	es.append(_spawn("runner", -2, -9))
	var res: Dictionary = await _track(es, 60.0, rects, 3.2, false)
	# esperar a que se asienten alrededor del jugador y medir reparto
	await _secs(1.5)
	var reached := 0
	var cr := false
	var ms := 0.0
	var sectors := {}
	for e in es:
		var r: Dictionary = res[e]
		if r["reach"] >= 0.0:
			reached += 1
		cr = cr or r["crossed"]
		ms = maxf(ms, r["max_still"])
		var dd: Vector3 = e.global_position - player.global_position
		if Vector2(dd.x, dd.z).length() < 4.5:
			sectors[int(floor((atan2(dd.z, dd.x) + PI) / (TAU / 8.0)))] = true
	info("grupo: %d/%d llegan · mayor parada %.2f s · sectores ocupados alrededor del jugador: %d/8" % [reached, es.size(), ms, sectors.size()])
	ok(reached == es.size(), "N5a los 8 enemigos (ladrones, tanque, corredor) acaban junto al jugador quieto")
	ok(not cr, "N5b ninguno atraviesa la geometría")
	ok(ms < 2.5, "N5c sin bloqueo en grupo (mayor parada de uno %.2f s < 2.5 s)" % ms)
	ok(sectors.size() >= 3, "N5d se reparten alrededor del jugador en ≥3 sectores (no una fila): %d" % sectors.size())
	await _kill_all()


# ============================================================================ 8: a distancia
func _t_ranged() -> void:
	await _setup_arena(1, true)
	var wr := Rect2(-7.0, -0.3, 14.0, 0.6)
	_box(0, 0, 14, 3, 0.6)
	await _frames(3)
	await _rebuild_nav()
	_put_player(0, 7)
	var e := _spawn("ranged", 0, -9)
	var res: Dictionary = await _track([e], 25.0, [wr], 13.5, false)
	var r: Dictionary = res[e]
	var d := _flat_d(e.global_position, player.global_position)
	var q := PhysicsRayQueryParameters3D.create(e.global_position + Vector3(0, 1, 0), player.global_position + Vector3(0, 1, 0), Config.L_WORLD)
	if Terrain.body_rid.is_valid():
		q.exclude = [Terrain.body_rid]
	var los := e.get_world_3d().direct_space_state.intersect_ray(q).is_empty()
	info("a distancia: dist final %.1f m · línea de tiro=%s · ataques con LOS=%d sin LOS=%d" % [d, str(los), r["tele_los"], r["tele_nolos"]])
	ok(r["tele_los"] >= 1, "N6a el especialista llega a una posición con línea de tiro y dispara (%d disparos)" % r["tele_los"])
	ok(r["tele_nolos"] == 0, "N6b nunca dispara contra la pared (disparos sin línea de tiro: %d)" % r["tele_nolos"])
	ok(not r["crossed"], "N6c no atraviesa la pared")
	ok(d <= 17.0, "N6d termina dentro del alcance de su ataque (%.1f m)" % d)
	await _kill_all()


# ============================================================================ obstáculo desconocido -> reanálisis
func _t_stuck() -> void:
	await _setup_arena(1, true)
	_put_player(0, 8)
	var e := _spawn("thief", 0, -8)
	await _secs(1.0)
	# muro añadido DESPUÉS de construir el mapa: el mapa no lo conoce
	var wr := Rect2(-7.0, -0.3, 14.0, 0.6)
	_box(0, 0, 14, 3, 0.6)
	var res: Dictionary = await _track([e], 30.0, [wr], 2.8)
	var r: Dictionary = res[e]
	info("obstáculo desconocido: llega=%s en %.1f s · intervenciones anti-atasco=%d · reanálisis del mapa=%d" % [str(r["reach"] >= 0.0), r["reach"], int(e.get("nav_unstuck_count")), (_nv().stats["reprobes"] if _nv() != null else 0)])
	ok(int(e.get("nav_unstuck_count")) >= 1 and (_nv().stats["reprobes"] if _nv() != null else 0) >= 1, "N7a se detecta que no avanza y el anti-atasco interviene (reanalizando el mapa)")
	ok(r["reach"] >= 0.0, "N7b tras reanalizar encuentra la ruta alrededor del obstáculo nuevo y llega")
	ok(not r["crossed"], "N7c sin atravesar la pared nueva")
	await _kill_all()


# ============================================================================ plataforma con rampas
func _t_platform() -> void:
	var found := false
	for idx in [1, 2, 3, 6, 7, 8, 11, 12]:
		await _setup_arena(idx, false)
		var plat: Node3D = null
		for ch in arena.world_root.get_children():
			if ch.name.begins_with("Platform"):
				plat = ch
				break
		if plat == null:
			continue
		found = true
		var h: float = plat.get_meta("height")
		var top := plat.global_position + Vector3(0, h + 0.3, 0)
		info("plataforma en arena %d: pos=(%.1f,%.1f) altura %.2f m" % [idx, plat.position.x, plat.position.z, h])
		var nv: NavGrid = _nv()
		ok(nv.walkable(top, 0), "N8a el centro de la plataforma elevada es transitable (se llega por la rampa)")
		player.teleport_to(top)
		player.iframes = 999.0
		await _secs(0.5)
		var es: Array = []
		var ang := 0.0
		for i in 3:
			var sp := arena.spawn_point(14.0)
			es.append(_spawn("thief", sp.x, sp.z))
			ang += 1.0
		var pc := nv.cell_of(player.global_position)
		var marks := {}
		marks[nv.idx(pc.x, pc.y)] = "@"
		for e in es:
			var ec := nv.cell_of(e.global_position)
			marks[nv.idx(ec.x, ec.y)] = "E"
		var fa := FileAccess.open(out_dir + "/map_platform.txt", FileAccess.WRITE)
		fa.store_string(nv.ascii(0, marks))
		fa.close()
		await _secs(1.5)
		var prof := ""
		for dz in range(-12, 13):
			var q := Vector3(plat.global_position.x, 0, plat.global_position.z + dz)
			var qc := nv.cell_of(q)
			var qi := nv.idx(qc.x, qc.y)
			prof += "%d:%.2f%s/%d " % [dz, nv.floor_y[qi], "B" if nv.blocked[0][qi] == 1 else "", nv.dist[0][qi]]
		info("perfil de la rampa (dz:alto[B=bloq]/pasos): " + prof)
		info("campo: pasos en celda del jugador=%d · en celdas de enemigos=%s" % [nv.dist_at(player.global_position, 0), str(es.map(func(e): return nv.dist_at(e.global_position, 0)))])
		var res: Dictionary = await _track(es, 40.0, [], 3.2)
		var n_ok := 0
		for e in es:
			if res[e]["reach"] >= 0.0:
				n_ok += 1
			info("  enemigo: min_d=%.1f estado=%d wp_info=%d stuck_t=%.1f pos=%s plat=%s y_floor=%s wall=%s vel=%s wp=%s" % [res[e]["min_d"], e.state, e._wp_info, e._stuck_t, str(e.global_position), str(plat.global_position), str(e.is_on_floor()), str(e.is_on_wall()), str(e.velocity), str(e._wp)])
		if n_ok < 3:
			for e in es:
				if res[e]["reach"] < 0.0:
					var ec := nv.cell_of(e.global_position)
					var txt := "vecindad de un enemigo atascado (x:z alto/B/pasos):\n"
					for dzz in range(-2, 3):
						for dxx in range(-2, 3):
							var ii := nv.idx(ec.x + dxx, ec.y + dzz)
							txt += "  [%.1f,%.1f] %.2f%s/%d" % [nv.center_of(ec.x + dxx, ec.y + dzz).x, nv.center_of(ec.x + dxx, ec.y + dzz).z, nv.floor_y[ii], "B" if nv.blocked[0][ii] == 1 else "", nv.dist[0][ii]]
						txt += "\n"
					info(txt)
					var f: PackedInt32Array = nv.dist[0]
					var at := nv.idx(ec.x, ec.y)
					var chain := ""
					for _s in 8:
						var nx2 := nv._downhill(at, f, 0)
						if nx2 < 0:
							chain += " FIN"
							break
						chain += " (%.1f,%.1f)f=%d" % [nv.center_of(nx2 % nv.n, nx2 / nv.n).x, nv.center_of(nx2 % nv.n, nx2 / nv.n).z, f[nx2]]
						at = nx2
					var out2 := [0]
					var wpt := nv.waypoint(e.global_position, player.global_position, 0, out2)
					info("cadena de descenso:" + chain + " · waypoint=" + str(wpt) + " info=" + str(out2[0]) + " line_clear=" + str(nv.line_clear(e.global_position, player.global_position, 0)))
					break
		info("plataforma: %d/3 ladrones suben hasta el jugador (alturas jugador y=%.2f)" % [n_ok, player.global_position.y])
		ok(n_ok >= 2, "N8b los ladrones suben por la rampa hasta el jugador en la plataforma (%d/3)" % n_ok)
		await _kill_all()
		break
	if not found:
		info("ninguna de las arenas probadas tenía plataforma")
		ok(false, "N8 se encontró una arena con plataforma")


# ============================================================================ 9: biomas con relieve y obstáculos reales
func _t_biomes() -> void:
	for bi in BiomeDB.COUNT:
		var idx := bi * 5 + 1
		await _setup_arena(idx, false)
		var nv: NavGrid = _nv()
		var bl: float = (float(nv.stats["blocked_small"]) / float(nv.n * nv.n)) if nv != null else 0.0
		_put_player(0, 0)
		await _secs(0.3)
		var es: Array = []
		for i in 8:
			var a := TAU * float(i) / 8.0 + 0.3
			var r := arena.half - 4.0
			es.append(_spawn("thief" if i % 4 != 3 else "tank", cos(a) * r, sin(a) * r))
		var res: Dictionary = await _track(es, 45.0, [], 3.2, false)
		var n_ok := 0
		var ms := 0.0
		for e in es:
			if res[e]["reach"] >= 0.0:
				n_ok += 1
			ms = maxf(ms, res[e]["max_still"])
		var hmin := 1e9
		var hmax := -1e9
		for ix in range(-24, 25, 4):
			for iz in range(-24, 25, 4):
				var hy := Terrain.ground_y(ix, iz)
				hmin = minf(hmin, hy)
				hmax = maxf(hmax, hy)
		info("bioma %s (arena %d): relieve %.1f m · bloqueado %.0f%% · celdas con escalón físico %d · llegan %d/8 · mayor parada %.2f s" % [BiomeDB.get_biome(bi)["id"], idx, hmax - hmin, bl * 100.0, (nv.stats["cells_with_bad_edges"] if nv != null else 0), n_ok, ms])
		ok(n_ok == 8, "N9 %s: los 8 enemigos llegan al jugador quieto rodeando los obstáculos reales (%d/8)" % [BiomeDB.get_biome(bi)["id"], n_ok])
		ok(bl < 0.45, "N9b %s: la rejilla no bloquea de más (%.0f%% de celdas)" % [BiomeDB.get_biome(bi)["id"], bl * 100.0])
		await _kill_all()


# ============================================================================ 10: rendimiento
func _t_perf() -> void:
	await _setup_arena(6, false)
	var nv: NavGrid = _nv()
	info("construcción del mapa: %.1f ms en total (repartidos en ~%d ticks de ≤%d celdas) · %d consultas físicas" % [nv.stats["build_ms"], int(ceil(float(nv.n * nv.n) / NavGrid.BUILD_PER_TICK)), NavGrid.BUILD_PER_TICK, nv.stats["queries"]])
	_put_player(0, 0)
	# 40 enemigos persiguiendo
	var es: Array = []
	for i in 40:
		var a := TAU * float(i) / 40.0
		es.append(_spawn("thief" if i % 5 != 0 else "ranged", cos(a) * 21.0, sin(a) * 21.0))
	await _secs(2.0)
	# A/B intercalado (4 × 2 s con navegación / 4 × 2 s sin ella) para que el ruido de la CPU simulada afecte a ambos por igual
	var sum_nav := 0.0
	var sum_old := 0.0
	Enemy.chase_us = 0
	Enemy.chase_n = 0
	var chase_nav_us := 0
	var chase_nav_n := 0
	var chase_old_us := 0
	var chase_old_n := 0
	for k in 4:
		_nav_set_ready(true)
		Enemy.chase_us = 0
		Enemy.chase_n = 0
		sum_nav += await _avg_physics(2.0)
		chase_nav_us += Enemy.chase_us
		chase_nav_n += Enemy.chase_n
		_nav_set_ready(false)
		Enemy.chase_us = 0
		Enemy.chase_n = 0
		sum_old += await _avg_physics(2.0)
		chase_old_us += Enemy.chase_us
		chase_old_n += Enemy.chase_n
	_nav_set_ready(true)
	var t_nav := sum_nav / 4.0
	var t_old := sum_old / 4.0
	var fl: float = nv.stats["flow_ms_max"]
	info("física por fotograma con 40 enemigos (A/B intercalado): con navegación %.2f ms · sin navegación %.2f ms · diferencia %.2f ms" % [t_nav * 1000.0, t_old * 1000.0, (t_nav - t_old) * 1000.0])
	var us_nav := float(chase_nav_us) / maxf(1.0, float(chase_nav_n))
	var us_old := float(chase_old_us) / maxf(1.0, float(chase_old_n))
	var extra_ms := (us_nav - us_old) * 40.0 / 1000.0
	info("script de persecución por enemigo y fotograma: con navegación %.1f µs · sin %.1f µs → coste extra de la IA %.2f ms por fotograma con 40 enemigos" % [us_nav, us_old, extra_ms])
	info("campo de flujo: %d recálculos · tick más caro %.2f ms (presupuesto %d expansiones/tick)" % [nv.stats["flow_runs"], fl, NavGrid.FLOW_PER_TICK])
	ok(fl < 6.0, "N10a un tick del campo de flujo cuesta %.2f ms (<6 ms en esta CPU)" % fl)
	ok(extra_ms < 3.0, "N10b el coste extra de la IA de navegación con 40 enemigos es %.2f ms por fotograma (<3 ms, medido en el propio script)" % extra_ms)
	# microbenchmark de consultas de ruta
	var t0 := Time.get_ticks_usec()
	var out := [0]
	for i in 2000:
		nv.waypoint(Vector3(-20 + (i % 40), 0, -20 + (i / 40) % 40), Vector3(0, 0, 0), 0, out)
	var per := float(Time.get_ticks_usec() - t0) / 2000.0
	info("waypoint(): %.1f µs por consulta (cada enemigo consulta ~8 veces/s)" % per)
	ok(per < 150.0, "N10c consulta de ruta %.1f µs (<150 µs)" % per)
	await _kill_all()


func _avg_physics(secs: float) -> float:
	var sum := 0.0
	var n := 0
	var t := 0.0
	var dt := get_physics_process_delta_time()
	while t < secs:
		await get_tree().physics_frame
		t += dt
		sum += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		n += 1
	return sum / maxf(1.0, float(n))
