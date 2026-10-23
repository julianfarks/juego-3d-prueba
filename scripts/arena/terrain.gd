class_name Terrain
extends RefCounted
## Terreno de la arena: relieve suave y TRANSITABLE (colinas, depresiones, rampas) definido por una función
## pura height(x,z). De ella salen (1) la malla visible (low-poly, color por vértice según el bioma),
## (2) un HeightMapShape3D como colisión (barato, sin trimesh) y (3) ground_y(), que usan el resto de sistemas
## (aparición de enemigos, jugador, monedas, cofres, portales, vuelo del maletín) para quedar sobre el suelo.
##
## Reglas de jugabilidad: las zonas "planas" (centro, calles, obstáculos, plataformas, recompensas) se aplanan con
## una máscara suave; las pendientes máximas se comprueban en el test (--biometest) y no superan ~21°.

const CELL := 1.0
const MARGIN := 5          # celdas de terreno visibles por fuera del muro

static var active := false
static var style := "flat"
static var amp := 0.0
static var freq := 0.05
static var half := 26.0
static var flat_r := 8.0
static var flats: Array = []        # Vector3(x, z, radio): zonas que deben quedar planas
static var body_rid := RID()        # colisión del terreno (se excluye de rayos de proyectiles/maletín)
static var _n1: FastNoiseLite
static var _n2: FastNoiseLite
static var _n3: FastNoiseLite


static func _mk_noise(seed_v: int, f: float, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.seed = seed_v
	n.frequency = f
	n.fractal_type = FastNoiseLite.FRACTAL_FBM if octaves > 1 else FastNoiseLite.FRACTAL_NONE
	n.fractal_octaves = octaves
	return n


static func configure(pal: Dictionary, half_v: float, seed_v: int, flat_list: Array) -> void:
	style = String(pal.get("terrain", "flat"))
	amp = float(pal.get("amp", 0.0))
	freq = float(pal.get("freq", 0.05))
	flat_r = float(pal.get("flat_r", 8.0))
	half = half_v
	flats = flat_list
	_n1 = _mk_noise(seed_v, freq, 3)
	_n2 = _mk_noise(seed_v + 77, freq * 1.7, 2)
	_n3 = _mk_noise(seed_v + 191, 0.33, 1)
	active = true


static func clear() -> void:
	active = false
	body_rid = RID()
	flats = []


static func _sstep(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## 0 = debe estar plano, 1 = relieve libre.
static func _flat_mask(x: float, z: float) -> float:
	var m := _sstep(flat_r, flat_r + 7.0, sqrt(x * x + z * z))
	for c in flats:
		var v: Vector3 = c
		var d := sqrt((x - v.x) * (x - v.x) + (z - v.y) * (z - v.y))
		m = minf(m, _sstep(v.z, v.z + 4.2, d))
	if style == "urban":
		# las calles (ejes) quedan llanas: es el espacio de combate principal
		m = minf(m, _sstep(3.8, 8.6, minf(absf(x), absf(z))))
	elif style == "industrial":
		m = minf(m, _sstep(2.5, 5.5, minf(absf(x), absf(z))) * 0.6 + 0.4)
	return m


static func height(x: float, z: float) -> float:
	if not active:
		return 0.0
	var edge := maxf(absf(x), absf(z))
	var e := 1.0 - _sstep(half + 0.5, half + 4.5, edge)
	if e <= 0.0:
		return 0.0
	var n := _n1.get_noise_2d(x, z)
	var n2 := _n2.get_noise_2d(x, z)
	var h := 0.0
	match style:
		"urban":
			# manzanas elevadas (aceras) con montones de escombros; las calles son llanas
			h = 0.28 + amp * (n * 0.5 + 0.5) + amp * 0.9 * pow(maxf(0.0, n2), 2.0)
		"forest":
			h = amp * (n * 0.9 + n2 * 0.45)
		"industrial":
			h = amp * (n * 0.5 + 0.5)
		"dunes":
			var r := 1.0 - absf(n2)
			h = amp * (0.5 * n + 0.5 * r * r) - amp * 0.15
		"floating":
			h = amp * (n * 0.7 + _n2.get_noise_2d(x, z) * 0.3)
		"court":
			h = amp * n * 0.25
			# estrado: anillo de dos peldaños suaves (rampas muy tendidas) alrededor del centro libre
			var d := sqrt(x * x + z * z)
			h += 0.35 * _sstep(15.0, 19.5, d) + 0.35 * _sstep(20.5, 25.0, d)
		_:
			h = 0.0
	return h * _flat_mask(x, z) * e


static func ground_y(x: float, z: float) -> float:
	return height(x, z) if active else 0.0


static func ground_at(p: Vector3) -> Vector3:
	return Vector3(p.x, ground_y(p.x, p.z), p.z)


## Pendiente (grados) en un punto.
static func slope_deg(x: float, z: float) -> float:
	var d := 0.5
	var gx := (height(x + d, z) - height(x - d, z)) / (2.0 * d)
	var gz := (height(x, z + d) - height(x, z - d)) / (2.0 * d)
	return rad_to_deg(atan(sqrt(gx * gx + gz * gz)))


# ------------------------------------------------------------------ color del suelo por bioma
static func _speck(x: float, z: float) -> float:
	return _n3.get_noise_2d(x, z)


static func _jit(c: Color, v: float, amt: float) -> Color:
	return Color(clampf(c.r + v * amt, 0.0, 1.0), clampf(c.g + v * amt, 0.0, 1.0), clampf(c.b + v * amt, 0.0, 1.0), c.a)


static func color_at(pal: Dictionary, x: float, z: float, h: float) -> Color:
	var main: Color = pal["g_main"]
	var alt: Color = pal["g_alt"]
	var det: Color = pal["g_detail"]
	var path: Color = pal["g_path"]
	var sp := _speck(x, z)
	var big := _n2.get_noise_2d(x * 1.3 + 40.0, z * 1.3)
	var out := main
	match style:
		"urban":
			var d := minf(absf(x), absf(z))
			if d < 3.6:
				out = _jit(main, sp, 0.025)
				if sp > 0.72:
					out = out.darkened(0.3)           # grietas
			elif d < 4.5:
				out = path.lightened(0.1)               # bordillo
			else:
				var tile := (int(floor(x / 2.0)) + int(floor(z / 2.0))) & 1
				out = _jit(alt if tile == 0 else alt.darkened(0.07), sp, 0.03)
				if big > 0.28 and d > 6.5:
					out = _jit(det, sp, 0.05)           # zona ajardinada
				elif h > amp * 0.9:
					out = _jit(Color(0.33, 0.3, 0.27), sp, 0.04)   # escombros
				elif sp > 0.7:
					out = out.darkened(0.25)
		"forest":
			out = _jit(main.lerp(alt, clampf(big * 0.8 + 0.4, 0.0, 1.0)), sp, 0.03)
			var trail := absf(z - 7.0 * sin(x * 0.11 + 0.6))
			var trail2 := absf(x - 7.0 * sin(z * 0.1 - 0.4))
			if minf(trail, trail2) < 1.5:
				out = _jit(path, sp, 0.03)
			elif h < -0.25:
				out = _jit(det.darkened(0.15), sp, 0.03)         # barro en las depresiones
			elif sp > 0.62:
				out = out.lightened(0.12)                           # musgo / hojas
		"industrial":
			var tile2 := (int(floor(x / 4.0)) + int(floor(z / 4.0))) & 1
			out = _jit(main if tile2 == 0 else alt, sp, 0.02)
			var seam := absf(fposmod(x, 4.0) - 2.0) > 1.88 or absf(fposmod(z, 4.0) - 2.0) > 1.88
			if seam:
				out = out.darkened(0.35)
			var d3 := minf(absf(x), absf(z))
			if d3 > 2.2 and d3 < 2.7:
				out = path                                          # franja amarilla de la calle de servicio
			elif big > 0.35:
				out = _jit(det, sp, 0.04)                          # óxido / aceite
		"dunes":
			var rip := sin((x * 0.8 + z * 0.35) * 1.6 + big * 3.0) * 0.5 + 0.5
			out = main.lerp(alt, clampf(h / maxf(amp, 0.1) * 0.6 + 0.35, 0.0, 1.0))
			out = out.lerp(path, rip * 0.18)
			out = _jit(out, sp, 0.025)
			if big > 0.42:
				out = _jit(det, sp, 0.04)                          # lecho de roca
			elif h < -0.1:
				out = out.darkened(0.12)
		"floating":
			var tile3 := (int(floor(x / 3.0)) + int(floor(z / 3.0))) & 1
			var th := absi((int(floor(x / 3.0)) * 73856093) ^ (int(floor(z / 3.0)) * 19349663)) % 4
			out = _jit(main if tile3 == 0 else alt, sp, 0.015)
			out = out.lightened(0.06 * float(th)).lerp(det, clampf(h * 0.35 + 0.1, 0.0, 0.5) * 0.4)
			var dd := sqrt(x * x + z * z)
			if absf(dd - 12.0) < 0.35 or absf(dd - 20.0) < 0.3:
				out = Color(det.r, det.g, det.b, 0.55)               # anillos de runas luminosas
			elif minf(absf(x), absf(z)) < 0.5:
				out = path
		"court":
			var tile4 := (int(floor(x / 3.0)) + int(floor(z / 3.0))) & 1
			out = _jit(main if tile4 == 0 else alt, sp, 0.012)
			if absf(x) < 2.2:
				out = _jit(path, sp, 0.015)                           # alfombra roja
				if absf(x) > 1.8:
					out = Color(det.r, det.g, det.b, 0.35)             # galón dorado
			else:
				var gx2 := absf(fposmod(x, 3.0) - 1.5) > 1.45 or absf(fposmod(z, 3.0) - 1.5) > 1.45
				if gx2:
					out = out.darkened(0.3)
		_:
			out = main
	return out


# ------------------------------------------------------------------ malla + colisión
static func extent() -> int:
	return int(ceil(half)) + MARGIN


## Crea la malla del terreno y su colisión bajo 'root'. Devuelve {"mesh": MeshInstance3D, "body": StaticBody3D}.
static func build(root: Node3D, pal: Dictionary) -> Dictionary:
	var ext := extent()
	var w := ext * 2 + 1
	var hs := PackedFloat32Array()
	hs.resize(w * w)
	for iz in w:
		for ix in w:
			hs[iz * w + ix] = height(float(ix - ext) * CELL, float(iz - ext) * CELL)
	var b := MeshBuilder.new()
	for iz in w - 1:
		for ix in w - 1:
			var x0 := float(ix - ext) * CELL
			var z0 := float(iz - ext) * CELL
			var h00 := hs[iz * w + ix]
			var h10 := hs[iz * w + ix + 1]
			var h01 := hs[(iz + 1) * w + ix]
			var h11 := hs[(iz + 1) * w + ix + 1]
			var hc := (h00 + h10 + h01 + h11) * 0.25
			var col := color_at(pal, x0 + CELL * 0.5, z0 + CELL * 0.5, hc)
			var a := Vector3(x0, h00, z0)
			var bb := Vector3(x0 + CELL, h10, z0)
			var c := Vector3(x0 + CELL, h11, z0 + CELL)
			var d := Vector3(x0, h01, z0 + CELL)
			var hint := Vector3(x0 + CELL * 0.5, hc - 6.0, z0 + CELL * 0.5)
			# dos triángulos con la misma diagonal que usa HeightMapShape3D (a-c)
			b.tri(a, bb, c, hint, col)
			b.tri(a, c, d, hint, col)
	# horizonte exterior bajo el terreno (evita ver el vacío entre el borde y los edificios)
	var out_c: Color = pal.get("ground", Color(0.08, 0.08, 0.1))
	var f := 400.0
	var lo := -0.05
	if not bool(pal.get("void", false)):
		b.quad(Vector3(-f, lo, -f), Vector3(f, lo, -f), Vector3(f, lo, f), Vector3(-f, lo, f), Vector3(0, -3, 0), out_c)
	var mi := Mats.mesh_instance(b.build(), Mats.world_material(), root)
	mi.name = "Terrain"
	# colisión
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = Config.L_WORLD
	body.collision_mask = 0
	var shape := HeightMapShape3D.new()
	shape.map_width = w
	shape.map_depth = w
	shape.map_data = hs
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	root.add_child(body)
	body_rid = body.get_rid()
	# suelo de seguridad muy por debajo (por si algo cae por el borde)
	var safe := PropsFactory.static_body(Vector3(half * 2.0 + 40.0, 2.0, half * 2.0 + 40.0), Vector3(0, -6.0, 0), 1)
	safe.name = "SafetyFloor"
	root.add_child(safe)
	return {"mesh": mi, "body": body}
