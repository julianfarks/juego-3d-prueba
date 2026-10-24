class_name NavGrid
extends RefCounted
## Navegación de enemigos para arenas 3D con terreno, plataformas con rampas y obstáculos de cualquier bioma.
## No depende de mallas de navegación: lee la FÍSICA real de la arena (la misma que usan los enemigos al moverse).
##
##  1. Mapa de transitabilidad (por tiempo, pocas celdas por tick): por cada celda de 1 m se lanza un rayo hacia abajo
##     (altura y pendiente del suelo) y se prueba un cilindro del tamaño del enemigo (libre de muros, cajas, edificios…).
##     Dos clases: 0 = pequeño (r≈0.55) y 1 = grande (r≈0.95: tanque, élite, minijefe, jefe).
##  2. Campo de flujo (BFS por oleadas, repartido en varios ticks) desde la celda del jugador: cada celda guarda
##     su distancia en pasos hasta el jugador. Un cambio de altura brusco (cajas, plataformas sin rampa) no es transitable;
##     las rampas y colinas suaves sí.
##  3. waypoint(): si hay línea directa libre devuelve el destino; si no, sigue el campo hasta 6 celdas y devuelve el punto más
##     lejano al que se llega en línea recta (suavizado). Así los enemigos rodean obstáculos sin zigzag.
## Todo el coste es pequeño y escalonado: el mapa se calcula una vez por arena; el campo se recalcula como máximo cada 0.25 s.

const CELL := 1.0
const R_SMALL := 0.55
const R_LARGE := 0.95
const CLEAR_BOTTOM := [0.4, 0.6]          # por clase: obstáculos más bajos que esto no cuentan
const CLEAR_H := 1.3
const MIN_NORMAL_Y := 0.80                # suelo más inclinado que ~37° no es transitable
const MAX_TAN := 0.42                     # desnivel máximo entre celdas vecinas por metro (≈23°): rampas 16° y colinas ≤21° pasan; escalones de 0.5 m no
const BUILD_PER_TICK := 140
const FLOW_PER_TICK := 450
const FLOW_MIN_INTERVAL := 0.25
const LOOKAHEAD := 6
const FLAT_EPS := 0.04                    # desniveles menores se consideran suelo llano (no se comprueban)
const EDGE_PER_TICK := 260
const DIRS := [Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1)]

var half := 26.0
var n := 0
var origin := 0.0
var floor_y := PackedFloat32Array()
var floor_n := PackedVector3Array()         # normal del suelo por celda (para barridos paralelos a la superficie)
var blocked: Array = [PackedByteArray(), PackedByteArray()]    # por clase: 1 = no transitable
var dist: Array = [PackedInt32Array(), PackedInt32Array()]      # por clase: pasos hasta el jugador (-1 = inalcanzable)
var ready := false
var edge_bad := PackedByteArray()            # por celda: bit i = la arista hacia DIRS[i] tiene un escalón físico (borde lateral de rampa, etc.)
var _phase := 0                              # 0 = sondeo de celdas, 1 = comprobación de aristas
var _edge_i := 0
var _ball := SphereShape3D.new()
var _warm := 3
var _build_i := 0
var _cyl: Array = []
var _ray := PhysicsRayQueryParameters3D.new()
var _shp := PhysicsShapeQueryParameters3D.new()

# trabajo del campo de flujo (uno a la vez)
var _want := [false, false]
var _job_cls := -1
var _job_next: PackedInt32Array
var _job_queue := PackedInt32Array()
var _job_qh := 0
var _job_qt := 0
var _last_start := [-9.0, -9.0]
var _last_src := [-1, -1]
var _clock := 0.0
var _last_reprobe := -9.0
var _rr := 0                            # alterna clases
var stats := {"build_ms": 0.0, "flow_runs": 0, "flow_ms_max": 0.0, "blocked_small": 0, "blocked_large": 0, "queries": 0, "reprobes": 0}


func _init(p_half := 26.0) -> void:
	half = p_half
	n = int(ceil(half * 2.0 / CELL))
	origin = -half
	var total := n * n
	floor_y.resize(total)
	floor_y.fill(-99.0)
	floor_n.resize(total)
	floor_n.fill(Vector3.UP)
	edge_bad.resize(total)
	edge_bad.fill(0)
	_ball.radius = 0.4
	for c in 2:
		var ba := PackedByteArray()
		ba.resize(total)
		ba.fill(1)
		blocked[c] = ba
		dist[c] = PackedInt32Array()
	_job_queue.resize(total)
	for r in [R_SMALL, R_LARGE]:
		var cs := CylinderShape3D.new()
		cs.radius = r
		cs.height = CLEAR_H
		_cyl.append(cs)
	_ray.collision_mask = Config.L_WORLD
	_shp.collision_mask = Config.L_WORLD
	_shp.margin = 0.0


# ------------------------------------------------------------------ coordenadas
func cell_of(p: Vector3) -> Vector2i:
	return Vector2i(clampi(int(floor((p.x - origin) / CELL)), 0, n - 1), clampi(int(floor((p.z - origin) / CELL)), 0, n - 1))


func idx(cx: int, cz: int) -> int:
	return cz * n + cx


func center_of(cx: int, cz: int) -> Vector3:
	return Vector3(origin + (cx + 0.5) * CELL, floor_y[idx(cx, cz)], origin + (cz + 0.5) * CELL)


func is_blocked_at(p: Vector3, cls: int) -> bool:
	if not ready:
		return false
	var c := cell_of(p)
	return blocked[cls][idx(c.x, c.y)] == 1


# ------------------------------------------------------------------ tick (llamar desde Arena._physics_process)
func tick(delta: float, space: PhysicsDirectSpaceState3D, goal: Vector3, has_goal: bool) -> void:
	_clock += delta
	if not ready:
		if _warm > 0:
			_warm -= 1       # los colisionadores recién añadidos entran al espacio físico en el siguiente paso
			return
		_build_step(space)
		return
	if not has_goal:
		return
	if _job_cls >= 0:
		_flow_step()
		return
	# ¿hay que recalcular algún campo?
	var gc := cell_of(goal)
	var gi := idx(gc.x, gc.y)
	for k in 2:
		var c := (_rr + k) % 2
		if not _want[c]:
			continue
		var stale: bool = _last_src[c] != gi
		var age: float = _clock - float(_last_start[c])
		if (stale and age >= FLOW_MIN_INTERVAL) or (dist[c] as PackedInt32Array).is_empty():
			_start_flow(c, gi)
			_rr = (c + 1) % 2
			return


func request(cls: int) -> void:
	_want[cls] = true


# ------------------------------------------------------------------ mapa de transitabilidad
func _build_step(space: PhysicsDirectSpaceState3D) -> void:
	var t0 := Time.get_ticks_usec()
	var total := n * n
	var done := 0
	if _phase == 0:
		while _build_i < total and done < BUILD_PER_TICK:
			_probe_cell(space, _build_i % n, _build_i / n)
			_build_i += 1
			done += 1
		if _build_i >= total:
			_phase = 1
	else:
		while _edge_i < total and done < EDGE_PER_TICK:
			_probe_edges(space, _edge_i % n, _edge_i / n, 4)
			_edge_i += 1
			done += 1
		if _edge_i >= total:
			ready = true
			var bs := 0
			var bl := 0
			var eb := 0
			for i in total:
				bs += blocked[0][i]
				bl += blocked[1][i]
				if edge_bad[i] != 0:
					eb += 1
			stats["blocked_small"] = bs
			stats["blocked_large"] = bl
			stats["cells_with_bad_edges"] = eb
	stats["build_ms"] = float(stats["build_ms"]) + (Time.get_ticks_usec() - t0) / 1000.0


## Comprueba con un barrido de esfera las aristas con desnivel de la celda (primeras 'ndirs' direcciones de DIRS; 8 = todas).
## Un barrido que choca = escalón vertical (lateral de una rampa, borde de plataforma, caja baja): no se puede pasar.
func _probe_edges(space: PhysicsDirectSpaceState3D, cx: int, cz: int, ndirs: int) -> void:
	var i := idx(cx, cz)
	if blocked[0][i] == 1:
		return
	for k in ndirs:
		var d: Vector2i = DIRS[k]
		var nx := cx + d.x
		var nz := cz + d.y
		if nx < 0 or nz < 0 or nx >= n or nz >= n:
			continue
		var j := idx(nx, nz)
		if blocked[0][j] == 1:
			continue
		if absf(floor_y[i] - floor_y[j]) <= FLAT_EPS:
			continue
		var off := _ball.radius + 0.04
		var a := Vector3(origin + (cx + 0.5) * CELL, floor_y[i], origin + (cz + 0.5) * CELL) + floor_n[i] * off
		var b := Vector3(origin + (nx + 0.5) * CELL, floor_y[j], origin + (nz + 0.5) * CELL) + floor_n[j] * off
		_shp.shape = _ball
		_shp.transform = Transform3D(Basis.IDENTITY, a)
		_shp.motion = b - a
		var r := space.cast_motion(_shp)
		stats["queries"] = int(stats["queries"]) + 1
		if r.size() >= 2 and float(r[0]) < 0.999:
			edge_bad[i] = edge_bad[i] | (1 << k)
			edge_bad[j] = edge_bad[j] | (1 << ((k + 4) % 8))
		_shp.motion = Vector3.ZERO


func _probe_cell(space: PhysicsDirectSpaceState3D, cx: int, cz: int) -> void:
	var i := idx(cx, cz)
	var x := origin + (cx + 0.5) * CELL
	var z := origin + (cz + 0.5) * CELL
	_ray.from = Vector3(x, 14.0, z)
	_ray.to = Vector3(x, -8.0, z)
	var hit := space.intersect_ray(_ray)
	stats["queries"] = int(stats["queries"]) + 1
	if hit.is_empty():
		return                                  # sin suelo: bloqueado (ya está en 1)
	var hp: Vector3 = hit["position"]
	var nrm: Vector3 = hit["normal"]
	floor_y[i] = hp.y
	floor_n[i] = nrm
	if nrm.y < MIN_NORMAL_Y:
		return
	for c in 2:
		_shp.shape = _cyl[c]
		_shp.transform = Transform3D(Basis.IDENTITY, Vector3(x, hp.y + float(CLEAR_BOTTOM[c]) + CLEAR_H * 0.5, z))
		var r := space.intersect_shape(_shp, 1)
		stats["queries"] = int(stats["queries"]) + 1
		if not r.is_empty():
			return                              # si el pequeño no cabe, el grande tampoco (queda en 1)
		blocked[c][i] = 0


## Vuelve a leer la física alrededor de 'p' (radio en celdas). Lo usa el anti-atasco cuando un enemigo choca con algo que el mapa
## no conocía (obstáculo añadido o movido después de construirlo) y fuerza recalcular el campo de flujo.
func reprobe(space: PhysicsDirectSpaceState3D, p: Vector3, r := 3) -> void:
	if not ready or _clock - _last_reprobe < 0.15:
		return
	_last_reprobe = _clock
	var c0 := cell_of(p)
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var cx := c0.x + dx
			var cz := c0.y + dz
			if cx < 0 or cz < 0 or cx >= n or cz >= n:
				continue
			var i := idx(cx, cz)
			blocked[0][i] = 1
			blocked[1][i] = 1
			floor_y[i] = -99.0
			edge_bad[i] = 0
			_probe_cell(space, cx, cz)
	for dz in range(-r - 1, r + 2):
		for dx in range(-r - 1, r + 2):
			var cx2 := c0.x + dx
			var cz2 := c0.y + dz
			if cx2 < 0 or cz2 < 0 or cx2 >= n or cz2 >= n:
				continue
			_probe_edges(space, cx2, cz2, 8)
	_last_src = [-1, -1]
	stats["reprobes"] = int(stats["reprobes"]) + 1


# ------------------------------------------------------------------ campo de flujo
func _passable(a: int, b: int, c: int, diag: bool) -> bool:
	var bb: PackedByteArray = blocked[c]
	if bb[b] == 1:
		return false
	if edge_bad[a] != 0:
		var k := _dir_index((b % n) - (a % n), (b / n) - (a / n))
		if k >= 0 and (edge_bad[a] & (1 << k)) != 0:
			return false
	var lim := MAX_TAN * (1.4142 if diag else 1.0) * CELL + 0.05
	return absf(floor_y[a] - floor_y[b]) <= lim


func _dir_index(dx: int, dz: int) -> int:
	for k in 8:
		if DIRS[k].x == dx and DIRS[k].y == dz:
			return k
	return -1


## ¿Puede el campo de flujo expandirse de la celda 'a' a la vecina 'b'? (mismas reglas en la expansión y en el descenso)
func _edge_ok(a: int, b: int, c: int) -> bool:
	var ax := a % n
	var az := a / n
	var bx := b % n
	var bz := b / n
	var diag: bool = ax != bx and az != bz
	if not _passable(a, b, c, diag):
		return false
	if diag and (not _passable(a, az * n + bx, c, false) or not _passable(a, bz * n + ax, c, false)):
		return false         # no cortar esquinas
	return true


func _start_flow(c: int, src: int) -> void:
	_job_cls = c
	_job_next = PackedInt32Array()
	_job_next.resize(n * n)
	_job_next.fill(-1)
	_last_start[c] = _clock
	_last_src[c] = src
	var bb: PackedByteArray = blocked[c]
	var seed_i := src
	if bb[src] == 1 or _isolated(src, c):
		seed_i = _nearest_free(src, c)          # jugador sobre una caja/zona aislada o pegado a un muro: se parte de la celda libre más cercana
	_job_qh = 0
	_job_qt = 0
	if seed_i >= 0:
		_job_next[seed_i] = 0
		_job_queue[_job_qt] = seed_i
		_job_qt += 1
	_flow_step()


func _flow_step() -> void:
	var t0 := Time.get_ticks_usec()
	var c := _job_cls
	var done := 0
	while _job_qh < _job_qt and done < FLOW_PER_TICK:
		var cur := _job_queue[_job_qh]
		_job_qh += 1
		done += 1
		var cx := cur % n
		var cz := cur / n
		var d := _job_next[cur] + 1
		for dz in [-1, 0, 1]:
			var nz: int = cz + dz
			if nz < 0 or nz >= n:
				continue
			for dx in [-1, 0, 1]:
				if dx == 0 and dz == 0:
					continue
				var nx: int = cx + dx
				if nx < 0 or nx >= n:
					continue
				var ni := nz * n + nx
				if _job_next[ni] != -1:
					continue
				if not _edge_ok(cur, ni, c):
					continue
				_job_next[ni] = d
				_job_queue[_job_qt] = ni
				_job_qt += 1
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	stats["flow_ms_max"] = maxf(float(stats["flow_ms_max"]), ms)
	if _job_qh >= _job_qt:
		dist[c] = _job_next
		_job_next = PackedInt32Array()
		_job_cls = -1
		stats["flow_runs"] = int(stats["flow_runs"]) + 1


## ¿Todas las celdas vecinas bloqueadas? (isla: cima de una caja o pilar)
func _isolated(i: int, c: int) -> bool:
	var cx := i % n
	var cz := i / n
	var bb: PackedByteArray = blocked[c]
	for dz in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if dx == 0 and dz == 0:
				continue
			var nx: int = cx + dx
			var nz: int = cz + dz
			if nx < 0 or nz < 0 or nx >= n or nz >= n:
				continue
			if bb[nz * n + nx] == 0:
				return false
	return true


## Celda libre más cercana (anillos) a 'src'; -1 si no hay en 5 celdas.
func _nearest_free(src: int, c: int) -> int:
	var cx := src % n
	var cz := src / n
	var bb: PackedByteArray = blocked[c]
	for r in range(1, 6):
		var best := -1
		var bd := 1e9
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var nx := cx + dx
				var nz := cz + dz
				if nx < 0 or nz < 0 or nx >= n or nz >= n:
					continue
				var ni := nz * n + nx
				if bb[ni] == 0:
					var dd := float(dx * dx + dz * dz)
					if dd < bd:
						bd = dd
						best = ni
		if best >= 0:
			return best
	return -1


# ------------------------------------------------------------------ consultas para los enemigos
## ¿Línea recta TRANSITABLE entre dos puntos? Se exige que las celdas del trayecto no estén bloqueadas (salvo 0.8 m junto al inicio y
## 1.1 m junto al final) y que el suelo sea continuo (sin saltos de altura: una plataforma sin rampa o una caja no se "atraviesan").
func line_clear(a: Vector3, b: Vector3, cls: int) -> bool:
	if not ready:
		return true
	var bb: PackedByteArray = blocked[cls]
	var dx := b.x - a.x
	var dz := b.z - a.z
	var len := sqrt(dx * dx + dz * dz)
	if len < 0.05:
		return true
	var steps := maxi(1, int(ceil(len / 0.4)))
	var inv := 1.0 / float(steps)
	var prev := -1
	for s in range(0, steps + 1):
		var t := s * inv
		var d := t * len
		var cx := int(floor((a.x + dx * t - origin) / CELL))
		var cz := int(floor((a.z + dz * t - origin) / CELL))
		if cx < 0 or cz < 0 or cx >= n or cz >= n:
			return false
		var ci := cz * n + cx
		if ci == prev:
			continue
		if prev >= 0:
			var ddx := (ci % n) - (prev % n)
			var ddz := (ci / n) - (prev / n)
			var dg: bool = ddx != 0 and ddz != 0
			if absf(floor_y[ci] - floor_y[prev]) > MAX_TAN * (1.4142 if dg else 1.0) * CELL + 0.05:
				return false
			if edge_bad[prev] != 0:
				var kk := _dir_index(ddx, ddz)
				if kk >= 0 and (edge_bad[prev] & (1 << kk)) != 0:
					return false
		prev = ci
		if d >= 0.8 and len - d >= 1.1 and bb[ci] == 1:
			return false
	return true


## Pasos de campo de flujo hasta el jugador desde 'p' (-1 si no hay dato).
func dist_at(p: Vector3, cls: int) -> int:
	var f: PackedInt32Array = dist[cls]
	if not ready or f.is_empty():
		return -1
	var c := cell_of(p)
	return f[idx(c.x, c.y)]


func walkable(p: Vector3, cls: int) -> bool:
	if not ready:
		return true
	var c := cell_of(p)
	return blocked[cls][idx(c.x, c.y)] == 0


## ¿Se puede avanzar 'len' metros en 'dir' (plano) sin entrar en celdas bloqueadas?
func free_ahead(from: Vector3, dir: Vector3, len: float, cls: int) -> bool:
	if not ready or dir.length() < 0.01:
		return true
	var d := dir.normalized()
	var bb: PackedByteArray = blocked[cls]
	var s := 0.5
	while s <= len:
		var cx := int(floor((from.x + d.x * s - origin) / CELL))
		var cz := int(floor((from.z + d.z * s - origin) / CELL))
		if cx < 0 or cz < 0 or cx >= n or cz >= n or bb[cz * n + cx] == 1:
			return false
		s += 0.5
	return true


## Próximo punto de paso hacia 'goal'. Devuelve 'goal' si hay línea recta; Vector3.INF si no hay ruta conocida.
## 'route' (out) = 0 directo, 1 por campo de flujo, 2 sin información (campo no calculado: el llamante usa dirección directa).
func waypoint(from: Vector3, goal: Vector3, cls: int, out: Array = []) -> Vector3:
	var info := 0
	var res := goal
	if ready and not line_clear(from, goal, cls):
		var f: PackedInt32Array = dist[cls]
		if f.is_empty():
			request(cls)
			info = 2
		else:
			var c0 := cell_of(from)
			var cur := idx(c0.x, c0.y)
			if f[cur] < 0:
				# la celda propia es no transitable o inalcanzable: buscar la mejor celda cercana
				var nb := _best_near(c0.x, c0.y, f)
				if nb < 0:
					info = 3
					res = Vector3.INF
				else:
					info = 1
					res = center_of(nb % n, nb / n)
			else:
				var chain: Array = []
				var at := cur
				for _s in LOOKAHEAD:
					var nxt := _downhill(at, f, cls)
					if nxt < 0:
						break
					chain.append(nxt)
					at = nxt
					if f[at] == 0:
						break
				if chain.is_empty():
					res = goal
					info = 0
				else:
					info = 1
					var pick: int = chain[0]
					for k in range(chain.size() - 1, -1, -1):
						var cc := center_of(chain[k] % n, chain[k] / n)
						if line_clear(from, cc, cls) or k == 0:
							pick = chain[k]
							break
					res = center_of(pick % n, pick / n)
					if f[pick] == 0:
						res = goal
	if out.size() > 0:
		out[0] = info
	return res


func _downhill(at: int, f: PackedInt32Array, cls: int) -> int:
	var cx := at % n
	var cz := at / n
	var best := -1
	var bd := f[at]
	for dz in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if dx == 0 and dz == 0:
				continue
			var nx: int = cx + dx
			var nz: int = cz + dz
			if nx < 0 or nz < 0 or nx >= n or nz >= n:
				continue
			var ni := nz * n + nx
			var dd := f[ni]
			if dd < 0 or dd >= bd:
				continue
			if not _edge_ok(ni, at, cls):
				continue                     # el vecino con menor distancia debe estar realmente conectado (sin escalón)
			bd = dd
			best = ni
	return best


## Celda cercana (≤3) con menor distancia al objetivo cuando la propia no tiene valor (p. ej. pegado a un muro, en una celda
## inflada). Solo cuenta si el suelo es continuo con el de la celda propia (no "salta" a la rampa o la plataforma de al lado).
func _best_near(cx: int, cz: int, f: PackedInt32Array) -> int:
	var own_y := floor_y[cz * n + cx]
	for r in range(1, 4):
		var best := -1
		var bd := 1 << 30
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var nx := cx + dx
				var nz := cz + dz
				if nx < 0 or nz < 0 or nx >= n or nz >= n:
					continue
				var ni := nz * n + nx
				var d := f[ni]
				if d >= 0 and d < bd and absf(floor_y[ni] - own_y) <= 0.2 * r + 0.05:
					bd = d
					best = ni
		if best >= 0:
			return best
	return -1


## Punto alternativo para desatascar: celda transitable a 2–4 celdas, con línea libre, que progresa hacia el objetivo
## (menor distancia de campo) y no está en la dirección bloqueada. 'side' = ±1 para elegir el lado preferido.
func alt_point(from: Vector3, cls: int, side: float) -> Vector3:
	if not ready:
		return Vector3.INF
	var f: PackedInt32Array = dist[cls]
	var c0 := cell_of(from)
	var best := Vector3.INF
	var bs := 1e9
	var own: int = f[idx(c0.x, c0.y)] if not f.is_empty() else 0
	for r in [3, 2, 4]:
		for k in 12:
			var a := TAU * float(k) / 12.0 * side
			var cx := c0.x + int(round(cos(a) * r))
			var cz := c0.y + int(round(sin(a) * r))
			if cx < 0 or cz < 0 or cx >= n or cz >= n:
				continue
			var i := idx(cx, cz)
			if blocked[cls][i] == 1:
				continue
			var cc := center_of(cx, cz)
			if not line_clear(from, cc, cls):
				continue
			var score := 0.0
			if not f.is_empty():
				var d := f[i]
				if d < 0:
					continue
				score = float(d) - float(own)
			score += randf() * 1.5
			if score < bs:
				bs = score
				best = cc
		if best != Vector3.INF:
			return best
	return best


## Centro de la celda transitable más cercana a 'p' (≤4 celdas); INF si no hay.
func nearest_walkable(p: Vector3, cls: int) -> Vector3:
	if not ready:
		return Vector3.INF
	var c0 := cell_of(p)
	var i0 := idx(c0.x, c0.y)
	if blocked[cls][i0] == 0:
		return center_of(c0.x, c0.y)
	var j := _nearest_free(i0, cls)
	return center_of(j % n, j / n) if j >= 0 else Vector3.INF


## Texto del mapa (depuración / tests): '#' bloqueado, '.' libre, '@' jugador, 'E' enemigo.
func ascii(cls: int, marks: Dictionary = {}) -> String:
	var s := ""
	for cz in n:
		var line := ""
		for cx in n:
			var i := idx(cx, cz)
			var ch := "#" if blocked[cls][i] == 1 else "."
			if marks.has(i):
				ch = marks[i]
			line += ch
		s += line + "\n"
	return s
