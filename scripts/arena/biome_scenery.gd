class_name BiomeScenery
extends RefCounted
## Escenografía NO colisionable de cada bioma: cielo/niebla/luz, perímetro de la arena, edificios y siluetas del fondo
## (en capas para dar profundidad), marcas de suelo y pequeños detalles. Todo se funde en pocas mallas
## estáticas (una llamada de dibujo por capa) y sin sombras propias: coste bajo para móviles.

static func _x(pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE) -> Transform3D:
	return MeshBuilder.xf(pos, rot, scl)


static func _g(c: Color, amount := 1.0) -> Color:
	return MeshBuilder.glow(c, amount)


static func _vary(c: Color, rng: RandomNumberGenerator, amt := 0.04) -> Color:
	return Color(clampf(c.r + rng.randf_range(-amt, amt), 0, 1), clampf(c.g + rng.randf_range(-amt, amt), 0, 1), clampf(c.b + rng.randf_range(-amt, amt), 0, 1), c.a)


## Caja con transform local dentro de un edificio (bt = transform del edificio).
static func _bx(b: MeshBuilder, bt: Transform3D, size: Vector3, lpos: Vector3, lrot: Vector3, col: Color) -> void:
	b.box(size, bt * _x(lpos, lrot), col)


static func _qd(b: MeshBuilder, bt: Transform3D, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, hint: Vector3, col: Color) -> void:
	b.quad(bt * p0, bt * p1, bt * p2, bt * p3, bt * hint, col)


# =====================================================================================
#  ENTORNO: cielo, niebla, luz
# =====================================================================================
static func environment(root: Node3D, pal: Dictionary, index: int) -> WorldEnvironment:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = pal["sky_top"]
	sm.sky_horizon_color = pal["sky_horizon"]
	sm.ground_horizon_color = (pal["sky_horizon"] as Color).lerp(pal["fog"], 0.5)
	sm.ground_bottom_color = pal["fog"]
	sm.sky_curve = 0.22
	sm.sun_angle_max = 18.0
	sky.sky_material = sm
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = pal["ambient"]
	env.ambient_light_energy = float(pal["ambient_energy"])
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = pal["fog"]
	env.fog_density = float(pal["fog_density"])
	env.fog_sky_affect = 0.35
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = pal["sun"]
	sun.light_energy = float(pal["sun_energy"])
	sun.rotation_degrees = Vector3(float(pal["sun_pitch"]), 38.0 + float(index % 5) * 23.0 + float(int(pal["biome"])) * 31.0, 0.0)
	root.add_child(sun)
	Config.configure_sun(sun)
	return we


# =====================================================================================
#  PERÍMETRO (reemplaza al antiguo wall_visual)
# =====================================================================================
static func walls(half: float, pal: Dictionary, rng: RandomNumberGenerator) -> ArrayMesh:
	var b := MeshBuilder.new()
	var style := String(pal.get("wall_style", "rail"))
	var wc: Color = pal["wall"]
	var accent: Color = pal["wall_accent"]
	var step := 2.0
	var n := int(half * 2.0 / step)
	for side in 4:
		for i in n + 1:
			var t := -half + i * step
			var pos := Vector3.ZERO
			var rot := 0.0
			match side:
				0: pos = Vector3(t, 0, -half - 0.2)
				1: pos = Vector3(t, 0, half + 0.2)
				2: pos = Vector3(-half - 0.2, 0, t); rot = 90.0
				3: pos = Vector3(half + 0.2, 0, t); rot = 90.0
			pos.y = Terrain.ground_y(pos.x, pos.z)
			var tr := Basis.from_euler(Vector3(0, deg_to_rad(rot), 0))
			var bt := Transform3D(tr, pos)
			match style:
				"urban":   # barrera de hormigón + valla metálica con cinta y luces de obra
					_bx(b, bt, Vector3(step, 0.9, 0.55), Vector3(0, 0.45, 0), Vector3.ZERO, _vary(wc, rng, 0.03))
					_bx(b, bt, Vector3(step, 0.16, 0.7), Vector3(0, 0.95, 0), Vector3.ZERO, wc.lightened(0.1))
					if i % 2 == 0:
						_bx(b, bt, Vector3(0.08, 1.7, 0.08), Vector3(-step * 0.5, 1.75, 0), Vector3.ZERO, Color(0.3, 0.32, 0.36))
					_bx(b, bt, Vector3(step, 1.2, 0.03), Vector3(0, 1.75, 0), Vector3.ZERO, Color(0.36, 0.38, 0.4))
					_bx(b, bt, Vector3(step, 0.06, 0.06), Vector3(0, 2.38, 0), Vector3.ZERO, Color(0.3, 0.32, 0.36))
					if i % 5 == 2:
						b.sphere(0.13, 5, 4, bt * _x(Vector3(0, 2.55, 0)), _g(accent, 1.0))
					if i % 3 == 0:
						_bx(b, bt, Vector3(0.9, 0.12, 0.05), Vector3(0.3, 1.2, 0.3), Vector3.ZERO, Color(0.95, 0.75, 0.1))
				"hedge":   # seto + valla de madera
					for k in 3:
						b.sphere(rng.randf_range(0.7, 1.0), 6, 4, bt * _x(Vector3(-0.7 + k * 0.7, rng.randf_range(0.5, 0.9), rng.randf_range(-0.2, 0.2))), _vary(Color(0.17, 0.33, 0.16), rng, 0.04))
					_bx(b, bt, Vector3(0.14, 1.5, 0.14), Vector3(0, 0.75, -0.3), Vector3.ZERO, wc)
					if i % 4 == 0:
						b.sphere(0.12, 4, 3, bt * _x(Vector3(0, 1.4, -0.3)), _g(accent, 0.9))
				"rocks":   # hilera de rocas rojizas
					for k in 2:
						var s := Vector3(rng.randf_range(1.0, 1.8), rng.randf_range(0.9, 1.9), rng.randf_range(0.9, 1.5))
						_bx(b, bt, s, Vector3(-0.5 + k, s.y * 0.4, 0), Vector3(rng.randf_range(-10, 10), rng.randf_range(0, 90), rng.randf_range(-10, 10)), _vary(wc, rng, 0.05).lightened(0.05 * k))
				"crystal":   # cristales luminosos
					for k in 2:
						var h := rng.randf_range(0.8, 1.9)
						b.frustum(Vector2(0.55, 0.55), Vector2(0.04, 0.04), h, bt * _x(Vector3(-0.5 + k, h * 0.5, 0), Vector3(rng.randf_range(-8, 8), rng.randf() * 90.0, rng.randf_range(-8, 8))), _g(accent.lerp(wc, rng.randf() * 0.5), 0.55))
					_bx(b, bt, Vector3(step, 0.3, 0.5), Vector3(0, 0.15, 0), Vector3.ZERO, wc.darkened(0.15))
				"columns":   # balaustrada de mármol con columnillas y orbes
					_bx(b, bt, Vector3(step, 0.3, 0.6), Vector3(0, 0.15, 0), Vector3.ZERO, wc.darkened(0.1))
					_bx(b, bt, Vector3(step, 0.16, 0.5), Vector3(0, 1.05, 0), Vector3.ZERO, wc.lightened(0.1))
					for k in 3:
						b.cylinder(0.1, 0.14, 0.75, 6, bt * _x(Vector3(-0.66 + k * 0.66, 0.62, 0)), wc)
					if i % 4 == 0:
						b.sphere(0.2, 6, 4, bt * _x(Vector3(0, 1.35, 0)), _g(accent, 0.85))
				_:   # rail
					_bx(b, bt, Vector3(0.14, 1.2, 0.14), Vector3(0, 0.6, 0), Vector3.ZERO, wc.darkened(0.2))
					_bx(b, bt, Vector3(step, 0.08, 0.1), Vector3(0, 1.15, 0), Vector3.ZERO, wc)
					_bx(b, bt, Vector3(step, 0.06, 0.08), Vector3(0, 0.7, 0), Vector3.ZERO, wc.darkened(0.1))
					if i % 4 == 0:
						b.sphere(0.12, 5, 4, bt * _x(Vector3(0, 1.3, 0)), _g(accent, 0.8))
	return b.build()


## Los muros invisibles (sin el suelo plano del lobby: el suelo lo pone Terrain).
static func wall_colliders(half: float) -> Array:
	var out: Array = []
	var thick := 3.0
	var hgt := 14.0
	var e := half + 0.4
	var defs := [
		[Vector3(half * 2.0 + thick * 2.0, hgt, thick), Vector3(0, hgt * 0.5 - 2.0, -e - thick * 0.5)],
		[Vector3(half * 2.0 + thick * 2.0, hgt, thick), Vector3(0, hgt * 0.5 - 2.0, e + thick * 0.5)],
		[Vector3(thick, hgt, half * 2.0), Vector3(-e - thick * 0.5, hgt * 0.5 - 2.0, 0)],
		[Vector3(thick, hgt, half * 2.0), Vector3(e + thick * 0.5, hgt * 0.5 - 2.0, 0)],
	]
	for d in defs:
		# solo capa de mundo: la cámara NO choca con el perímetro (se mantiene dentro de la arena por recorte continuo, ver CameraRig)
		var sb := PropsFactory.static_body(d[0], d[1], Config.L_WORLD)
		sb.name = "WallCollider"
		out.append(sb)
	return out


# =====================================================================================
#  EDIFICIOS CON FACHADA
# =====================================================================================
## Edificio en coordenadas locales: base centrada en el origen (y=0), fachada hacia +Z.
## detail: 2 = cerca (balcones, repisas, escaleras), 1 = medio, 0 = lejano (solo ventanas).
static func building(b: MeshBuilder, bt: Transform3D, w: float, d: float, h: float, wall: Color, pal: Dictionary, rng: RandomNumberGenerator, detail: int, ruin: bool, lit_chance := 0.14) -> void:
	var trim := wall.lightened(0.14)
	var dark := wall.darkened(0.3)
	var glass := Color(0.1, 0.14, 0.2)
	var lit: Color = pal.get("window", Color(1.0, 0.82, 0.45))
	var accents: Array = pal.get("paints", [Color(0.7, 0.2, 0.2)])
	# --- cuerpo (con un mordisco derrumbado en edificios en ruinas) ---
	var sec_h: Array = [h, h]   # altura de la mitad izquierda / derecha
	if ruin:
		sec_h[0] = h * rng.randf_range(0.5, 0.85)
	var halfw := w * 0.5
	_bx(b, bt, Vector3(halfw, sec_h[0], d), Vector3(-halfw * 0.5, sec_h[0] * 0.5, 0), Vector3.ZERO, wall)
	_bx(b, bt, Vector3(halfw, sec_h[1], d), Vector3(halfw * 0.5, sec_h[1] * 0.5, 0), Vector3.ZERO, wall.lerp(trim, 0.2))
	# zócalo y cornisa
	_bx(b, bt, Vector3(w + 0.3, 1.0, d + 0.3), Vector3(0, 0.5, 0), Vector3.ZERO, dark)
	_bx(b, bt, Vector3(halfw + 0.4, 0.45, d + 0.4), Vector3(halfw * 0.5, sec_h[1] + 0.22, 0), Vector3.ZERO, trim)
	if not ruin or sec_h[0] >= h * 0.99:
		_bx(b, bt, Vector3(halfw + 0.4, 0.45, d + 0.4), Vector3(-halfw * 0.5, sec_h[0] + 0.22, 0), Vector3.ZERO, trim)
	# pilastras en las esquinas de la fachada
	_bx(b, bt, Vector3(0.5, sec_h[1], 0.4), Vector3(w * 0.5 - 0.1, sec_h[1] * 0.5, d * 0.5 + 0.12), Vector3.ZERO, trim.darkened(0.05))
	_bx(b, bt, Vector3(0.5, sec_h[0], 0.4), Vector3(-w * 0.5 + 0.1, sec_h[0] * 0.5, d * 0.5 + 0.12), Vector3.ZERO, trim.darkened(0.05))
	# --- ventanas ---
	var cols := maxi(2, int(w / 2.6))
	var rows := maxi(1, int((h - 4.0) / 3.2))
	var cw := w / float(cols)
	var zf := d * 0.5
	for c in cols:
		var lx := -w * 0.5 + (c + 0.5) * cw
		var sec: float = sec_h[0] if lx < 0.0 else sec_h[1]
		for r in rows:
			var cy := 3.4 + r * 3.2
			if cy + 1.3 > sec:
				continue
			var hx := cw * 0.3
			# marco (solo en edificios con detalle)
			if detail >= 1:
				_qd(b, bt, Vector3(lx - hx - 0.12, cy - 1.0, zf + 0.04), Vector3(lx + hx + 0.12, cy - 1.0, zf + 0.04), Vector3(lx + hx + 0.12, cy + 1.0, zf + 0.04), Vector3(lx - hx - 0.12, cy + 1.0, zf + 0.04), Vector3(lx, cy, 0), trim.darkened(0.12))
			var roll := rng.randf()
			var gc := glass
			var em := 0.0
			if roll < lit_chance:
				gc = lit
				em = 0.85
			elif roll < lit_chance + 0.12:
				gc = Color(0.02, 0.02, 0.03)     # hueco roto
			elif roll < lit_chance + 0.2:
				gc = Color(0.3, 0.38, 0.42)      # cristal reflejando el cielo
				em = 0.12
			_qd(b, bt, Vector3(lx - hx, cy - 0.88, zf + 0.08), Vector3(lx + hx, cy - 0.88, zf + 0.08), Vector3(lx + hx, cy + 0.88, zf + 0.08), Vector3(lx - hx, cy + 0.88, zf + 0.08), Vector3(lx, cy, 0), _g(gc, em))
			if detail >= 2:
				# repisa como una sola tira (2 triángulos) en vez de una caja
				_qd(b, bt, Vector3(lx - cw * 0.33, cy - 1.0, zf + 0.3), Vector3(lx + cw * 0.33, cy - 1.0, zf + 0.3), Vector3(lx + cw * 0.33, cy - 1.0, zf + 0.04), Vector3(lx - cw * 0.33, cy - 1.0, zf + 0.04), Vector3(lx, cy - 3.0, zf), trim)
				if roll > 0.86 and r > 0:
					# balcón
					_bx(b, bt, Vector3(cw * 0.7, 0.12, 0.85), Vector3(lx, cy - 1.0, zf + 0.45), Vector3.ZERO, trim.darkened(0.05))
					_bx(b, bt, Vector3(cw * 0.7, 0.55, 0.05), Vector3(lx, cy - 0.65, zf + 0.85), Vector3.ZERO, dark)
	# bandas de forjado
	if detail >= 1:
		for r in rows + 1:
			var by := 2.0 + r * 3.2
			if by < sec_h[1]:
				_bx(b, bt, Vector3(halfw + 0.2, 0.18, 0.14), Vector3(halfw * 0.5, by, zf + 0.06), Vector3.ZERO, trim.darkened(0.08))
			if by < sec_h[0]:
				_bx(b, bt, Vector3(halfw + 0.2, 0.18, 0.14), Vector3(-halfw * 0.5, by, zf + 0.06), Vector3.ZERO, trim.darkened(0.08))
	# planta baja: escaparate oscuro + cartel luminoso + toldo
	if detail >= 1:
		_bx(b, bt, Vector3(w - 1.8, 2.3, 0.22), Vector3(0, 1.55, zf + 0.06), Vector3.ZERO, Color(0.07, 0.08, 0.1))
		var sign_c: Color = accents[rng.randi() % accents.size()]
		if rng.randf() < 0.55:
			_bx(b, bt, Vector3(w * 0.5, 0.45, 0.1), Vector3(rng.randf_range(-1.0, 1.0), 2.95, zf + 0.22), Vector3.ZERO, _g(sign_c, 0.85))
		if rng.randf() < 0.7:
			_bx(b, bt, Vector3(w * 0.6, 0.08, 1.2), Vector3(0, 2.55, zf + 0.7), Vector3(-14, 0, 0), sign_c.darkened(0.15))
	# --- daños y azotea ---
	if ruin:
		var top_l: float = sec_h[0]
		for i in 4:
			var sx := rng.randf_range(-halfw, 0.0) - 0.0
			_bx(b, bt, Vector3(rng.randf_range(1.0, 2.4), 0.2, rng.randf_range(1.5, d * 0.9)), Vector3(sx, top_l + rng.randf_range(-1.8, 0.1), 0), Vector3(rng.randf_range(-14, 14), rng.randf_range(-10, 10), rng.randf_range(-22, 22)), wall.darkened(0.12))
		for i in 6:
			b.cylinder(0.03, 0.03, rng.randf_range(1.0, 2.4), 4, bt * _x(Vector3(rng.randf_range(-halfw, -0.3), top_l + 0.6, rng.randf_range(-d * 0.4, d * 0.4)), Vector3(rng.randf_range(-25, 25), 0, rng.randf_range(-25, 25))), Color(0.46, 0.25, 0.14))
		# manchas de hollín sobre la fachada
		_qd(b, bt, Vector3(-halfw - 0.5, top_l - 5.0, zf + 0.1), Vector3(-halfw + 2.0, top_l - 6.0, zf + 0.1), Vector3(-halfw + 2.5, top_l, zf + 0.1), Vector3(-halfw - 0.8, top_l, zf + 0.1), Vector3(0, 0, 0), Color(0.07, 0.065, 0.065))
	var roof_h: float = sec_h[1]
	if detail >= 1 and rng.randf() < 0.8:
		var pick := rng.randi() % 3
		if pick == 0:
			# depósito de agua sobre patas
			for sx in [-0.7, 0.7]:
				for sz in [-0.7, 0.7]:
					_bx(b, bt, Vector3(0.12, 1.6, 0.12), Vector3(halfw * 0.5 + sx, roof_h + 0.8, sz), Vector3.ZERO, Color(0.3, 0.26, 0.22))
			b.cylinder(1.0, 1.0, 1.6, 8, bt * _x(Vector3(halfw * 0.5, roof_h + 2.4, 0)), Color(0.5, 0.36, 0.24))
			b.frustum(Vector2(2.0, 2.0), Vector2(0.2, 0.2), 0.6, bt * _x(Vector3(halfw * 0.5, roof_h + 3.5, 0)), Color(0.4, 0.28, 0.2))
		elif pick == 1:
			for i in 3:
				_bx(b, bt, Vector3(1.6, 0.9, 1.1), Vector3(halfw * 0.25 + i * 1.8, roof_h + 0.45, rng.randf_range(-1, 1)), Vector3.ZERO, Color(0.7, 0.72, 0.74))
		else:
			b.cylinder(0.06, 0.06, 6.0, 4, bt * _x(Vector3(halfw * 0.5, roof_h + 3.0, 0)), Color(0.4, 0.4, 0.44))
			b.sphere(0.25, 4, 3, bt * _x(Vector3(halfw * 0.5, roof_h + 6.1, 0)), _g(Color(1.0, 0.15, 0.1), 1.0))
	if detail >= 2 and rng.randf() < 0.45:
		# escalera de incendios en zigzag sobre la fachada
		var fe := Color(0.22, 0.22, 0.26)
		var fx := w * 0.5 - 1.8
		var k := 0
		var y := 3.6
		while y + 3.2 < sec_h[1] and k < 5:
			_bx(b, bt, Vector3(1.5, 0.08, 1.0), Vector3(fx, y, zf + 0.55), Vector3.ZERO, fe)
			_bx(b, bt, Vector3(1.5, 0.5, 0.04), Vector3(fx, y + 0.35, zf + 1.04), Vector3.ZERO, fe)
			_bx(b, bt, Vector3(0.12, 3.4, 0.05), Vector3(fx + (-0.6 if k % 2 == 0 else 0.6), y + 1.6, zf + 0.7), Vector3(0, 0, 28 if k % 2 == 0 else -28), fe)
			y += 3.2
			k += 1


## Anillo de edificios de primera fila alrededor de la arena (con ruinas, esquinas y escombros).
static func building_row(b: MeshBuilder, half: float, pal: Dictionary, rng: RandomNumberGenerator, tints: Array) -> void:
	var gap := half + 7.0
	for side in 4:
		var span := half + 11.0 if side < 2 else half - 1.0
		var x := -span
		while x < span - 6.0:
			var w := rng.randf_range(9.0, 15.0)
			var d := rng.randf_range(9.0, 14.0)
			var h := rng.randf_range(15.0, 40.0)
			var cx := x + w * 0.5
			var dist := gap + d * 0.5 + rng.randf_range(0.0, 1.5)
			var pos := Vector3.ZERO
			var yaw := 0.0
			match side:
				0: pos = Vector3(cx, 0, -dist); yaw = 0.0 + 180.0
				1: pos = Vector3(cx, 0, dist); yaw = 0.0
				2: pos = Vector3(-dist, 0, cx); yaw = 90.0
				3: pos = Vector3(dist, 0, cx); yaw = -90.0
			# yaw: la fachada local +Z debe mirar al centro. side1 (z>0): hay que girar 180º.
			match side:
				0: yaw = 0.0
				1: yaw = 180.0
				2: yaw = 90.0
				3: yaw = -90.0
			pos.y = -0.3
			var bt := Transform3D(Basis.from_euler(Vector3(0, deg_to_rad(yaw), 0)), pos)
			var tint: Color = tints[rng.randi() % tints.size()]
			building(b, bt, w, d, h, tint, pal, rng, 2, rng.randf() < 0.55)
			# escombros al pie
			for i in 3:
				_bx(b, bt, Vector3(rng.randf_range(0.5, 1.4), rng.randf_range(0.3, 0.7), rng.randf_range(0.5, 1.2)), Vector3(rng.randf_range(-w * 0.4, w * 0.4), 0.25, d * 0.5 + rng.randf_range(0.8, 2.0)), Vector3(0, rng.randf() * 90.0, 0), Color(0.4, 0.38, 0.36))
			x += w + rng.randf_range(0.2, 1.2)


## Capa lejana: torres y siluetas distribuidas en anillo.
static func tower_ring(b: MeshBuilder, pal: Dictionary, rng: RandomNumberGenerator, count: int, r_min: float, r_max: float, h_min: float, h_max: float, tints: Array, detail: int) -> void:
	for i in count:
		var ang := TAU * (float(i) + rng.randf_range(-0.3, 0.3)) / float(count)
		var dist := rng.randf_range(r_min, r_max)
		var w := rng.randf_range(10.0, 20.0)
		var d := rng.randf_range(10.0, 18.0)
		var h := rng.randf_range(h_min, h_max)
		var pos := Vector3(cos(ang) * dist, -0.5, sin(ang) * dist)
		var yaw := rad_to_deg(atan2(-pos.x, -pos.z))
		var bt := Transform3D(Basis.from_euler(Vector3(0, deg_to_rad(yaw), 0)), pos)
		var tint: Color = tints[rng.randi() % tints.size()]
		building(b, bt, w, d, h, tint, pal, rng, detail, rng.randf() < 0.35, 0.1)


## Colinas / montañas lejanas (conos achatados teñidos del color del horizonte).
static func far_hills(b: MeshBuilder, pal: Dictionary, rng: RandomNumberGenerator, count: int, dist: float, h_min: float, h_max: float, tint: Color, rocky := false) -> void:
	for i in count:
		var ang := TAU * (float(i) + rng.randf_range(-0.4, 0.4)) / float(count)
		var r := dist + rng.randf_range(-20.0, 30.0)
		var h := rng.randf_range(h_min, h_max)
		var w := rng.randf_range(50.0, 110.0)
		var c := _vary(tint, rng, 0.03)
		var p := Vector3(cos(ang) * r, h * 0.5 - 4.0, sin(ang) * r)
		if rocky:
			b.frustum(Vector2(w, w * 0.8), Vector2(w * 0.28, w * 0.2), h, _x(p, Vector3(0, rng.randf() * 90.0, 0)), c)
			b.frustum(Vector2(w * 0.3, w * 0.22), Vector2(w * 0.2, w * 0.16), h * 0.12, _x(p + Vector3(0, h * 0.55, 0), Vector3(0, rng.randf() * 90.0, 0)), c.darkened(0.12))
		else:
			b.frustum(Vector2(w, w * 0.9), Vector2(w * 0.12, w * 0.1), h, _x(p, Vector3(0, rng.randf() * 90.0, 0)), c)


# =====================================================================================
#  MARCAS DE CALLE Y DETALLES (bioma urbano)
# =====================================================================================
static func urban_markings(half: float, pal: Dictionary) -> ArrayMesh:
	var b := MeshBuilder.new()
	var yel: Color = pal["floor_line"]
	var white := Color(0.82, 0.82, 0.8)
	var y := 0.025
	var hint := Vector3(0, -3, 0)
	# línea central discontinua en ambos ejes
	var s := -half
	while s < half:
		if absf(s) > 4.2:
			b.quad(Vector3(s, y, -0.09), Vector3(s + 2.0, y, -0.09), Vector3(s + 2.0, y, 0.09), Vector3(s, y, 0.09), hint, yel)
			b.quad(Vector3(-0.09, y, s), Vector3(0.09, y, s), Vector3(0.09, y, s + 2.0), Vector3(-0.09, y, s + 2.0), hint, yel)
		s += 4.0
	# líneas laterales continuas
	for sgn in [-1.0, 1.0]:
		b.quad(Vector3(-half, y, sgn * 3.35), Vector3(-4.2, y, sgn * 3.35), Vector3(-4.2, y, sgn * 3.35 + 0.1 * sgn), Vector3(-half, y, sgn * 3.35 + 0.1 * sgn), hint, white)
		b.quad(Vector3(4.2, y, sgn * 3.35), Vector3(half, y, sgn * 3.35), Vector3(half, y, sgn * 3.35 + 0.1 * sgn), Vector3(4.2, y, sgn * 3.35 + 0.1 * sgn), hint, white)
		b.quad(Vector3(sgn * 3.35, y, -half), Vector3(sgn * 3.35 + 0.1 * sgn, y, -half), Vector3(sgn * 3.35 + 0.1 * sgn, y, -4.2), Vector3(sgn * 3.35, y, -4.2), hint, white)
		b.quad(Vector3(sgn * 3.35, y, 4.2), Vector3(sgn * 3.35 + 0.1 * sgn, y, 4.2), Vector3(sgn * 3.35 + 0.1 * sgn, y, half), Vector3(sgn * 3.35, y, half), hint, white)
	# pasos de cebra en los cuatro accesos al cruce
	for k in 7:
		var o := -3.0 + k * 1.0
		for sgn in [-1.0, 1.0]:
			b.quad(Vector3(sgn * 4.9, y, o - 0.28), Vector3(sgn * 6.1, y, o - 0.28), Vector3(sgn * 6.1, y, o + 0.28), Vector3(sgn * 4.9, y, o + 0.28), hint, white)
			b.quad(Vector3(o - 0.28, y, sgn * 4.9), Vector3(o + 0.28, y, sgn * 4.9), Vector3(o + 0.28, y, sgn * 6.1), Vector3(o - 0.28, y, sgn * 6.1), hint, white)
	return b.build()


## Marcas de suelo y pequeños detalles sin colisión del bioma.
static func ground_details(root: Node3D, half: float, pal: Dictionary, rng: RandomNumberGenerator, circles: Array) -> void:
	var id := String(pal["id"])
	if id == "urban":
		var mk := Mats.mesh_instance(urban_markings(half, pal), Mats.world_material(), root)
		mk.name = "StreetMarkings"
		var jr := RandomNumberGenerator.new()
		jr.seed = 4242 + int(half)
		judicial_details(root, half, pal, jr)
	if id == "urban" or id == "court":
		_paper_wind(root, half)
	var dd := Mats.mesh_instance(doodads(id, half, pal, rng, circles, 70 if id == "urban" else 90), Mats.world_material(), root)
	dd.name = "Doodads"
	ambient_fx(root, half, pal)

## Personalidad urbana (Task L): acera con bordillo, letreros judiciales en postes, guirnaldas de luces. Todo sin colisión,
## fuera de la zona de juego (junto al muro o detrás) y en pocas mallas estáticas.
const SIGN_TEXTS := ["BUFETE & ASOCIADOS", "JUZGADO Nº 3", "NOTARÍA", "FIANZAS 24H", "ABOGADOS · DIVORCIOS", "TRIBUNAL DE FALTAS", "HABEAS CORPUS S.L.", "OBJECIÓN!"]

static func judicial_details(root: Node3D, half: float, pal: Dictionary, rng: RandomNumberGenerator) -> void:
	var b := MeshBuilder.new()
	var hint := Vector3(0, -3, 0)
	# --- acera + bordillo pegados al muro (por dentro, 1,6 m: la arena sigue despejada) ---
	var walk := Color(0.36, 0.36, 0.36)
	var curb := Color(0.62, 0.6, 0.55)
	var seg := 2.0
	var n := int(half * 2.0 / seg)
	for side in 4:
		for i in n:
			var t0 := -half + i * seg
			var t1 := t0 + seg
			var pts: Array = []
			for pair in [[t0, half - 1.6], [t1, half - 1.6], [t1, half - 0.2], [t0, half - 0.2]]:
				var u: float = pair[0]
				var v: float = pair[1]
				var pt := Vector3.ZERO
				match side:
					0: pt = Vector3(u, 0, -v)
					1: pt = Vector3(u, 0, v)
					2: pt = Vector3(-v, 0, u)
					3: pt = Vector3(v, 0, u)
				pt.y = Terrain.ground_y(pt.x, pt.z) + 0.05
				pts.append(pt)
			b.quad(pts[0], pts[1], pts[2], pts[3], hint, walk.lerp(curb, 0.12 * float(i % 2)))
			# bordillo: franja estrecha en el lado interior
			var q0: Vector3 = pts[0]
			var q1: Vector3 = pts[1]
			var o := (Vector3(0, 0, 1) if side < 2 else Vector3(1, 0, 0)) * (0.16 * (1.0 if side == 0 or side == 2 else -1.0))
			b.quad(q0 + Vector3(0, 0.02, 0), q1 + Vector3(0, 0.02, 0), q1 + o + Vector3(0, 0.02, 0), q0 + o + Vector3(0, 0.02, 0), hint, curb)
	var m := Mats.mesh_instance(b.build(), Mats.world_material(), root)
	m.name = "Sidewalk"
	# --- letreros judiciales sobre postes, fuera del muro (se ven por encima de la barrera) ---
	var sb := MeshBuilder.new()
	var holder := Node3D.new()
	holder.name = "JudicialSigns"
	root.add_child(holder)
	var spots := [[0, -0.55], [0, 0.5], [1, -0.4], [1, 0.62], [2, -0.5], [2, 0.45], [3, -0.6], [3, 0.5]]
	var texts := SIGN_TEXTS.duplicate()
	for k in spots.size():
		var side: int = spots[k][0]
		var along: float = float(spots[k][1]) * half + rng.randf_range(-1.5, 1.5)
		var d := half + 3.4
		var pos := Vector3.ZERO
		var yaw := 0.0
		match side:
			0: pos = Vector3(along, 0, -d); yaw = 0.0
			1: pos = Vector3(along, 0, d); yaw = 180.0
			2: pos = Vector3(-d, 0, along); yaw = 90.0
			3: pos = Vector3(d, 0, along); yaw = -90.0
		pos.y = Terrain.ground_y(pos.x, pos.z)
		var bt := Transform3D(Basis.from_euler(Vector3(0, deg_to_rad(yaw), 0)), pos)
		var hgt := rng.randf_range(4.2, 5.4)
		var board := Color(0.14, 0.15, 0.2) if k % 2 == 0 else Color(0.2, 0.1, 0.1)
		sb.box(Vector3(0.18, hgt, 0.18), bt * MeshBuilder.xf(Vector3(-1.9, hgt * 0.5, 0)), Color(0.25, 0.25, 0.28))
		sb.box(Vector3(0.18, hgt, 0.18), bt * MeshBuilder.xf(Vector3(1.9, hgt * 0.5, 0)), Color(0.25, 0.25, 0.28))
		sb.box(Vector3(4.4, 1.15, 0.14), bt * MeshBuilder.xf(Vector3(0, hgt, 0)), board)
		sb.box(Vector3(4.5, 0.08, 0.2), bt * MeshBuilder.xf(Vector3(0, hgt + 0.6, 0)), Color(0.85, 0.65, 0.25))
		var l := Label3D.new()
		l.text = String(texts[k % texts.size()])
		l.font_size = 40
		l.pixel_size = 0.0125
		l.outline_size = 3
		l.modulate = Color(0.98, 0.86, 0.5) if k % 2 == 0 else Color(0.95, 0.92, 0.85)
		l.outline_modulate = Color(0, 0, 0, 0.8)
		l.shaded = false
		l.double_sided = false
		l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		l.visibility_range_end = 70.0
		holder.add_child(l)
		l.transform = bt * MeshBuilder.xf(Vector3(0, hgt, 0.09))
		# guirnalda de luces entre dos postes: bombillas pequeñas en catenaria (emisivas, sin luz dinámica)
		if k % 2 == 0:
			for j in 9:
				var u := float(j) / 8.0
				var sag := sin(u * PI) * 0.55
				var c2 := MeshBuilder.glow(Color(1.0, 0.85, 0.5) if j % 2 == 0 else Color(1.0, 0.6, 0.35), 1.4)
				sb.box(Vector3(0.16, 0.16, 0.16), bt * MeshBuilder.xf(Vector3(-1.9 + 3.8 * u, hgt - 0.55 - sag, 0.0)), c2)
	var sm := Mats.mesh_instance(sb.build(), Mats.world_material(), root)
	sm.name = "SignPosts"
	sm.visibility_range_end = 90.0


## Papeles que el viento arrastra por la calle: pocas piezas planas, sin sombra, sin colisión.
static func _paper_wind(root: Node3D, half: float) -> void:
	var amount := int(round(14.0 * float(Config.fx_cfg()["particles"])))
	if amount <= 0:
		return
	var ps := CPUParticles3D.new()
	ps.name = "WindPapers"
	ps.amount = amount
	ps.lifetime = 9.0
	ps.preprocess = 9.0
	ps.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	ps.emission_box_extents = Vector3(half, 0.6, half)
	ps.position = Vector3(0, 0.8, 0)
	ps.direction = Vector3(1.0, 0.15, 0.35)
	ps.spread = 18.0
	ps.gravity = Vector3(0, -0.02, 0)
	ps.initial_velocity_min = 1.6
	ps.initial_velocity_max = 3.2
	ps.angular_velocity_min = -220.0
	ps.angular_velocity_max = 220.0
	ps.local_coords = true
	var bm := BoxMesh.new()
	bm.size = Vector3(0.36, 0.02, 0.48)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.93, 0.9, 0.8)
	bm.material = mat
	ps.mesh = bm
	ps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ps.visibility_range_end = 60.0
	root.add_child(ps)



## Pequeñas partículas ambientales discretas (pocas, sin sombras): polvo, luciérnagas, chispas, motas mágicas.
static func ambient_fx(root: Node3D, half: float, pal: Dictionary) -> void:
	var id := String(pal["id"])
	var col := Color(1, 1, 1, 0.5)
	var amount := 36
	var size := 0.09
	var vel_y := 0.15
	var life := 7.0
	match id:
		"urban":
			col = Color(0.95, 0.9, 0.8, 0.35)
			size = 0.07
		"forest":
			col = Color(0.8, 1.0, 0.55, 0.9)
			amount = 40
			size = 0.11
		"industrial":
			col = Color(1.0, 0.55, 0.15, 0.9)
			vel_y = 0.9
			size = 0.07
			life = 4.0
		"desert":
			col = Color(1.0, 0.88, 0.65, 0.4)
			amount = 50
			size = 0.08
		"citadel":
			col = Color(0.65, 0.95, 1.0, 0.9)
			vel_y = 0.35
			size = 0.1
		"court":
			col = Color(1.0, 0.78, 0.3, 0.9)
			vel_y = 0.6
			size = 0.09
	var ps := CPUParticles3D.new()
	ps.name = "AmbientFx"
	ps.amount = amount
	ps.lifetime = life
	ps.preprocess = life
	ps.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	ps.emission_box_extents = Vector3(half, 3.0, half)
	ps.position = Vector3(0, 3.0, 0)
	ps.direction = Vector3(0.3, 1.0, 0.1)
	ps.spread = 40.0
	ps.gravity = Vector3.ZERO
	ps.initial_velocity_min = vel_y * 0.5
	ps.initial_velocity_max = vel_y * 1.5
	ps.scale_amount_min = 0.7
	ps.scale_amount_max = 1.3
	var qm := QuadMesh.new()
	qm.size = Vector2(size, size)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = col
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if id != "urban" and id != "desert" else BaseMaterial3D.BLEND_MODE_MIX
	qm.material = mat
	ps.mesh = qm
	ps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ps)


## Detalles pequeños sin colisión repartidos por el suelo. 'circles' = huecos ocupados.
static func doodads(id: String, half: float, pal: Dictionary, rng: RandomNumberGenerator, circles: Array, count: int) -> ArrayMesh:
	var b := MeshBuilder.new()
	var hint := Vector3(0, -3, 0)
	var green: Color = pal.get("g_detail", Color(0.3, 0.45, 0.22))
	var placed := 0
	var tries := 0
	while placed < count and tries < count * 6:
		tries += 1
		var x := rng.randf_range(-half + 1.2, half - 1.2)
		var z := rng.randf_range(-half + 1.2, half - 1.2)
		var ok := true
		for c in circles:
			var v: Vector3 = c
			if v.z == 7.0 and v.x == 0.0 and v.y == 0.0:
				continue
			if (x - v.x) * (x - v.x) + (z - v.y) * (z - v.y) < (v.z + 0.3) * (v.z + 0.3):
				ok = false
				break
		if not ok:
			continue
		var y := Terrain.ground_y(x, z)
		var p := Vector3(x, y, z)
		match id:
			"urban": _doodad_urban(b, p, rng, hint, green)
			"forest": _doodad_forest(b, p, rng, hint, pal)
			"industrial": _doodad_industrial(b, p, rng, hint, pal)
			"desert": _doodad_desert(b, p, rng, hint, pal)
			"citadel": _doodad_citadel(b, p, rng, hint, pal)
			"court": _doodad_court(b, p, rng, hint, pal)
		placed += 1
	return b.build()


static func _page(b: MeshBuilder, p: Vector3, rng: RandomNumberGenerator, hint: Vector3, n := 3, spread := 0.6) -> void:
	for i in n:
		var q := p + Vector3(rng.randf_range(-spread, spread), 0.04, rng.randf_range(-spread, spread))
		var a := rng.randf() * TAU
		var ux := Vector3(cos(a), 0, sin(a)) * 0.22
		var uz := Vector3(-sin(a), 0, cos(a)) * 0.3
		b.quad(q - ux - uz, q + ux - uz, q + ux + uz, q - ux + uz, hint, _g(Color(0.95, 0.94, 0.88), 0.18))


static func _tuft(b: MeshBuilder, p: Vector3, rng: RandomNumberGenerator, col: Color, n := 4, h := 0.6) -> void:
	for i in n:
		var q := p + Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))
		b.frustum(Vector2(0.14, 0.14), Vector2(0.02, 0.02), rng.randf_range(h * 0.5, h), _x(q + Vector3(0, h * 0.4, 0), Vector3(rng.randf_range(-18, 18), rng.randf() * 90.0, rng.randf_range(-18, 18))), _vary(col, rng, 0.06))


static func _pebbles(b: MeshBuilder, p: Vector3, rng: RandomNumberGenerator, col: Color, n := 3) -> void:
	for i in n:
		var s := rng.randf_range(0.12, 0.35)
		b.box(Vector3(s * 1.4, s, s * 1.1), _x(p + Vector3(rng.randf_range(-0.5, 0.5), s * 0.4, rng.randf_range(-0.5, 0.5)), Vector3(rng.randf_range(-20, 20), rng.randf() * 90.0, rng.randf_range(-20, 20))), _vary(col, rng, 0.05))


static func _doodad_urban(b: MeshBuilder, p: Vector3, rng: RandomNumberGenerator, hint: Vector3, green: Color) -> void:
	match rng.randi() % 8:
		0:   # cono de obra
			b.frustum(Vector2(0.36, 0.36), Vector2(0.1, 0.1), 0.5, _x(p + Vector3(0, 0.27, 0), Vector3(0, 0, rng.randf_range(-5, 5) if rng.randf() < 0.3 else 0.0)), Color(0.95, 0.4, 0.1))
			b.cylinder(0.14, 0.17, 0.12, 6, _x(p + Vector3(0, 0.34, 0)), Color(0.95, 0.95, 0.92))
			b.box(Vector3(0.5, 0.05, 0.5), _x(p + Vector3(0, 0.03, 0)), Color(0.15, 0.15, 0.17))
		1, 2:
			_page(b, p, rng, hint)
		3:   # bolsa de basura
			b.sphere(0.32, 5, 4, _x(p + Vector3(0, 0.25, 0), Vector3.ZERO, Vector3(1, 0.8, 1)), Color(0.1, 0.1, 0.13))
			b.sphere(0.12, 4, 3, _x(p + Vector3(0, 0.55, 0)), Color(0.1, 0.1, 0.13))
		4:   # neumático
			b.cylinder(0.42, 0.42, 0.22, 8, _x(p + Vector3(0, 0.22, 0), Vector3(rng.randf_range(0, 80), rng.randf() * 90.0, 0)), Color(0.06, 0.06, 0.07))
		5, 6:
			_tuft(b, p, rng, green, 4, 0.7)
		7:   # charco
			var rr := rng.randf_range(0.6, 1.2)
			b.quad(p + Vector3(-rr, 0.02, -rr * 0.7), p + Vector3(rr, 0.02, -rr * 0.7), p + Vector3(rr, 0.02, rr * 0.7), p + Vector3(-rr, 0.02, rr * 0.7), hint, _g(Color(0.35, 0.45, 0.55), 0.12))


static func _doodad_forest(b: MeshBuilder, p: Vector3, rng: RandomNumberGenerator, hint: Vector3, pal: Dictionary) -> void:
	match rng.randi() % 6:
		0, 1, 2:
			_tuft(b, p, rng, (pal["g_alt"] as Color).lightened(0.05), 6, 0.75)
		3:   # flores luminosas
			for i in 4:
				var q := p + Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4))
				b.cylinder(0.02, 0.02, 0.4, 4, _x(q + Vector3(0, 0.2, 0)), Color(0.25, 0.5, 0.25))
				b.sphere(0.09, 4, 3, _x(q + Vector3(0, 0.42, 0)), _g(Color.from_hsv(rng.randf_range(0.0, 0.95), 0.5, 1.0), 0.7))
		4:
			_pebbles(b, p, rng, Color(0.45, 0.46, 0.44), 4)
		5:   # hojas caídas
			for i in 5:
				var q2 := p + Vector3(rng.randf_range(-0.6, 0.6), 0.03, rng.randf_range(-0.6, 0.6))
				var a := rng.randf() * TAU
				var ux := Vector3(cos(a), 0, sin(a)) * 0.12
				var uz := Vector3(-sin(a), 0, cos(a)) * 0.16
				b.quad(q2 - ux - uz, q2 + ux - uz, q2 + ux + uz, q2 - ux + uz, hint, Color(0.75, 0.5, 0.15) if rng.randf() < 0.6 else Color(0.5, 0.6, 0.2))


static func _doodad_industrial(b: MeshBuilder, p: Vector3, rng: RandomNumberGenerator, hint: Vector3, pal: Dictionary) -> void:
	match rng.randi() % 6:
		0:   # barril
			var c: Color = pal["paints"][rng.randi() % 3]
			b.cylinder(0.32, 0.32, 0.9, 8, _x(p + Vector3(0, 0.45, 0)), c)
			b.cylinder(0.34, 0.34, 0.06, 8, _x(p + Vector3(0, 0.55, 0)), c.darkened(0.3))
			b.cylinder(0.34, 0.34, 0.06, 8, _x(p + Vector3(0, 0.25, 0)), c.darkened(0.3))
		1, 2:   # mancha de aceite / óxido
			var rr := rng.randf_range(0.7, 1.4)
			b.quad(p + Vector3(-rr, 0.02, -rr * 0.8), p + Vector3(rr, 0.02, -rr * 0.6), p + Vector3(rr * 0.8, 0.02, rr), p + Vector3(-rr * 0.7, 0.02, rr * 0.7), hint, Color(0.05, 0.05, 0.07))
		3:   # rejilla de ventilación con brillo
			b.box(Vector3(1.2, 0.04, 0.8), _x(p + Vector3(0, 0.03, 0), Vector3(0, rng.randf() * 90.0, 0)), Color(0.12, 0.12, 0.14))
			b.box(Vector3(1.0, 0.03, 0.55), _x(p + Vector3(0, 0.05, 0), Vector3(0, 0, 0)), _g(Color(1.0, 0.5, 0.1), 0.5))
		4:
			_pebbles(b, p, rng, Color(0.35, 0.34, 0.34), 4)
		5:
			b.box(Vector3(0.9, 0.12, 0.4), _x(p + Vector3(0, 0.06, 0), Vector3(0, rng.randf() * 90.0, 0)), Color(0.95, 0.75, 0.1))
			b.box(Vector3(0.12, 0.13, 0.41), _x(p + Vector3(0.2, 0.06, 0), Vector3(0, 0, 0)), Color(0.1, 0.1, 0.1))


static func _doodad_desert(b: MeshBuilder, p: Vector3, rng: RandomNumberGenerator, hint: Vector3, pal: Dictionary) -> void:
	match rng.randi() % 6:
		0, 1:
			_pebbles(b, p, rng, Color(0.62, 0.42, 0.28), 5)
		2:   # hierba seca
			_tuft(b, p, rng, Color(0.7, 0.6, 0.3), 5, 0.6)
		3, 4:   # hojas de expediente enterradas por el viento
			_page(b, p, rng, hint, 3, 0.5)
		5:
			b.cylinder(0.04, 0.05, 0.9, 4, _x(p + Vector3(0, 0.35, 0), Vector3(0, 0, rng.randf_range(-20, 20))), Color(0.9, 0.86, 0.75))


static func _doodad_citadel(b: MeshBuilder, p: Vector3, rng: RandomNumberGenerator, hint: Vector3, pal: Dictionary) -> void:
	match rng.randi() % 4:
		0, 1:   # esquirlas de cristal
			var c: Color = pal["paints"][rng.randi() % 3]
			for i in 3:
				var h := rng.randf_range(0.3, 0.8)
				b.frustum(Vector2(0.18, 0.18), Vector2(0.02, 0.02), h, _x(p + Vector3(rng.randf_range(-0.3, 0.3), h * 0.5, rng.randf_range(-0.3, 0.3)), Vector3(rng.randf_range(-15, 15), rng.randf() * 90.0, rng.randf_range(-15, 15))), _g(c, 0.55))
		2:
			_pebbles(b, p, rng, Color(0.7, 0.72, 0.84), 3)
		3:   # pétalos luminosos
			for i in 4:
				var q := p + Vector3(rng.randf_range(-0.6, 0.6), 0.03, rng.randf_range(-0.6, 0.6))
				b.quad(q + Vector3(-0.1, 0, -0.06), q + Vector3(0.1, 0, -0.06), q + Vector3(0.1, 0, 0.06), q + Vector3(-0.1, 0, 0.06), hint, _g(Color(1.0, 0.7, 0.95), 0.6))


static func _doodad_court(b: MeshBuilder, p: Vector3, rng: RandomNumberGenerator, hint: Vector3, pal: Dictionary) -> void:
	match rng.randi() % 4:
		0, 1:
			_page(b, p, rng, hint, 3, 0.7)
		2:   # mazo del juez caído
			b.cylinder(0.05, 0.05, 0.5, 5, _x(p + Vector3(0, 0.06, 0), Vector3(0, rng.randf() * 90.0, 90)), Color(0.35, 0.2, 0.12))
			b.cylinder(0.12, 0.12, 0.25, 6, _x(p + Vector3(0.25, 0.12, 0), Vector3(0, 0, 90)), Color(0.4, 0.24, 0.14))
		3:   # monedas de oro
			for i in 3:
				b.cylinder(0.12, 0.12, 0.03, 8, _x(p + Vector3(rng.randf_range(-0.3, 0.3), 0.03 + i * 0.03, rng.randf_range(-0.3, 0.3))), _g(Color(1.0, 0.8, 0.25), 0.5))


# =====================================================================================
#  FONDO COMPLETO POR BIOMA
# =====================================================================================
## Crea las capas de fondo.
static func backdrop(root: Node3D, half: float, pal: Dictionary, rng: RandomNumberGenerator) -> void:
	match String(pal["id"]):
		"urban": _backdrop_urban(root, half, pal, rng)
		"forest": _backdrop_forest(root, half, pal, rng)
		"industrial": _backdrop_industrial(root, half, pal, rng)
		"desert": _backdrop_desert(root, half, pal, rng)
		"citadel": _backdrop_citadel(root, half, pal, rng)
		_: _backdrop_court(root, half, pal, rng)


static func _layer(root: Node3D, b: MeshBuilder, name: String, vis_end := 480.0) -> void:
	var m := b.build()
	if m == null:
		return
	var mi := Mats.mesh_instance(m, Mats.world_material(), root)
	mi.name = name
	mi.visibility_range_end = vis_end


static func _backdrop_urban(root: Node3D, half: float, pal: Dictionary, rng: RandomNumberGenerator) -> void:
	var tints := [Color(0.5, 0.36, 0.3), Color(0.46, 0.45, 0.43), Color(0.62, 0.52, 0.4), Color(0.36, 0.4, 0.42), Color(0.55, 0.42, 0.34), Color(0.3, 0.32, 0.36)]
	# capa 1: edificios cercanos con detalle completo
	var near := MeshBuilder.new()
	building_row(near, half, pal, rng, tints)
	var n1 := Mats.mesh_instance(near.build(), Mats.world_material(), root)
	n1.name = "BackdropNear"
	# capa 2: rascacielos medios
	var mid := MeshBuilder.new()
	var mid_tints := [Color(0.34, 0.38, 0.44), Color(0.4, 0.4, 0.42), Color(0.3, 0.33, 0.4)]
	tower_ring(mid, pal, rng, 14, half + 34.0, half + 60.0, 38.0, 90.0, mid_tints, 0)
	var n2 := Mats.mesh_instance(mid.build(), Mats.world_material(), root)
	n2.name = "BackdropMid"
	# capa 3: siluetas lejanas + colinas azuladas
	var far := MeshBuilder.new()
	tower_ring(far, pal, rng, 20, 120.0, 190.0, 50.0, 130.0, [Color(0.4, 0.44, 0.52), Color(0.36, 0.4, 0.5)], 0)
	far_hills(far, pal, rng, 9, 270.0, 40.0, 85.0, Color(0.42, 0.5, 0.58))
	var n3 := Mats.mesh_instance(far.build(), Mats.world_material(), root)
	n3.name = "BackdropFar"
	for mi in [n1, n2, n3]:
		(mi as GeometryInstance3D).visibility_range_end = 420.0


# =====================================================================================
#  PIEZAS REUTILIZABLES DEL FONDO
# =====================================================================================
static func _ring_pos(rng: RandomNumberGenerator, r_min: float, r_max: float, y := -0.3) -> Vector3:
	var a := rng.randf() * TAU
	var r := rng.randf_range(r_min, r_max)
	return Vector3(cos(a) * r, y, sin(a) * r)


static func _cone_tree(b: MeshBuilder, p: Vector3, h: float, leaf: Color, bark: Color, rng: RandomNumberGenerator) -> void:
	b.cylinder(h * 0.035, h * 0.06, h * 0.4, 5, _x(p + Vector3(0, h * 0.2, 0)), bark)
	var layers := 4
	for i in layers:
		var t := float(i) / float(layers)
		var w := (1.0 - t * 0.72) * h * 0.34
		b.frustum(Vector2(w * 2.0, w * 2.0), Vector2(w * 0.6, w * 0.6), h * 0.3, _x(p + Vector3(0, h * (0.3 + t * 0.2) + h * 0.12, 0), Vector3(0, rng.randf() * 90.0, 0)), _vary(leaf.lightened(t * 0.08), rng, 0.03))


static func _oak_tree(b: MeshBuilder, p: Vector3, h: float, leaf: Color, bark: Color, rng: RandomNumberGenerator) -> void:
	b.cylinder(h * 0.04, h * 0.075, h * 0.55, 6, _x(p + Vector3(0, h * 0.27, 0), Vector3(rng.randf_range(-4, 4), 0, rng.randf_range(-4, 4))), bark)
	for i in 5:
		var o := Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(0.0, 0.14), rng.randf_range(-0.2, 0.2)) * h
		b.sphere(h * rng.randf_range(0.17, 0.26), 6, 4, _x(p + Vector3(0, h * 0.68, 0) + o), _vary(leaf, rng, 0.04))


static func _column(b: MeshBuilder, p: Vector3, r: float, h: float, col: Color, fluted := true) -> void:
	b.box(Vector3(r * 2.8, r * 0.5, r * 2.8), _x(p + Vector3(0, r * 0.25, 0)), col.darkened(0.12))
	b.cylinder(r * 0.88, r, h, 10 if fluted else 7, _x(p + Vector3(0, h * 0.5 + r * 0.5, 0)), col)
	b.cylinder(r * 1.25, r * 0.9, r * 0.5, 10, _x(p + Vector3(0, h + r * 0.75, 0)), col.lightened(0.05))
	b.box(Vector3(r * 3.0, r * 0.5, r * 3.0), _x(p + Vector3(0, h + r * 1.2, 0)), col.darkened(0.05))


static func _mesa(b: MeshBuilder, p: Vector3, w: float, h: float, col: Color, rng: RandomNumberGenerator) -> void:
	var y := 0.0
	var cw := w
	var layers := 4
	for i in layers:
		var lh := h / float(layers) * rng.randf_range(0.8, 1.2)
		var nw := cw * rng.randf_range(0.82, 0.95)
		b.frustum(Vector2(cw, cw * rng.randf_range(0.7, 1.0)), Vector2(nw, nw * 0.85), lh, _x(p + Vector3(0, y + lh * 0.5, 0), Vector3(0, rng.randf() * 30.0, 0)), _vary(col.lerp(Color(0.85, 0.6, 0.4), float(i) / float(layers) * 0.35), rng, 0.04).darkened(0.06 * float(layers - i) / float(layers)))
		y += lh
		cw = nw


static func _dune(b: MeshBuilder, p: Vector3, w: float, h: float, col: Color, rng: RandomNumberGenerator) -> void:
	b.frustum(Vector2(w, w * rng.randf_range(0.5, 0.8)), Vector2(w * 0.12, w * 0.05), h, _x(p + Vector3(0, h * 0.5 - 1.0, 0), Vector3(0, rng.randf() * 180.0, 0)), col)


static func _cloud(b: MeshBuilder, p: Vector3, s: float, col: Color, rng: RandomNumberGenerator) -> void:
	for i in 5:
		b.sphere(s * rng.randf_range(0.5, 1.0), 6, 4, _x(p + Vector3(rng.randf_range(-1.0, 1.0) * s, rng.randf_range(-0.2, 0.3) * s, rng.randf_range(-1.0, 1.0) * s), Vector3.ZERO, Vector3(1.4, 0.55, 1.2)), col)


static func _island(b: MeshBuilder, p: Vector3, r: float, depth: float, top: Color, rock: Color, rng: RandomNumberGenerator, built: bool, pal: Dictionary) -> void:
	# roca invertida bajo la isla + cara superior de césped/mármol
	b.frustum(Vector2(r * 2.0, r * 2.0), Vector2(r * 0.25, r * 0.25), depth, _x(p + Vector3(0, -depth * 0.5, 0), Vector3(180, rng.randf() * 90.0, 0)), rock)
	b.frustum(Vector2(r * 2.0, r * 2.0), Vector2(r * 1.9, r * 1.9), 0.8, _x(p + Vector3(0, 0.1, 0), Vector3(0, rng.randf() * 90.0, 0)), top)
	for i in 3:
		b.frustum(Vector2(r * 0.5, r * 0.4), Vector2(0.03, 0.03), rng.randf_range(4.0, depth * 0.5), _x(p + Vector3(rng.randf_range(-r, r) * 0.5, -depth * 0.3, rng.randf_range(-r, r) * 0.5), Vector3(180, 0, 0)), rock.darkened(0.15))
	if built:
		var marble: Color = pal.get("marble", Color(0.92, 0.93, 0.98))
		var n := rng.randi_range(2, 4)
		for i in n:
			var o := Vector3(rng.randf_range(-r, r) * 0.55, 0.5, rng.randf_range(-r, r) * 0.55)
			var w := rng.randf_range(4.0, 8.0)
			var h := rng.randf_range(6.0, 20.0)
			b.box(Vector3(w, h, w), _x(p + o + Vector3(0, h * 0.5, 0), Vector3(0, rng.randf() * 90.0, 0)), _vary(marble, rng, 0.03))
			b.box(Vector3(w + 0.8, 0.6, w + 0.8), _x(p + o + Vector3(0, h, 0), Vector3(0, 0, 0)), marble.darkened(0.12))
			if rng.randf() < 0.55:
				b.frustum(Vector2(w * 1.1, w * 1.1), Vector2(0.1, 0.1), w * 1.4, _x(p + o + Vector3(0, h + w * 0.7 + 0.3, 0), Vector3(0, 45, 0)), _g(pal["accent"], 0.45))
			else:
				b.sphere(w * 0.5, 7, 5, _x(p + o + Vector3(0, h + 0.3, 0)), _g(pal["paints"][rng.randi() % 3], 0.4))
			for k in int(h / 3.5):
				b.quad(p + o + Vector3(-w * 0.2, 2.5 + k * 3.2, w * 0.51), p + o + Vector3(w * 0.2, 2.5 + k * 3.2, w * 0.51), p + o + Vector3(w * 0.2, 3.7 + k * 3.2, w * 0.51), p + o + Vector3(-w * 0.2, 3.7 + k * 3.2, w * 0.51), p + o, _g(Color(0.7, 0.95, 1.0), 0.8))
	else:
		for i in 6:
			_oak_tree(b, p + Vector3(rng.randf_range(-r, r) * 0.7, 0.5, rng.randf_range(-r, r) * 0.7), rng.randf_range(5.0, 9.0), Color(0.45, 0.72, 0.62), Color(0.5, 0.4, 0.45), rng)


static func _chimney(b: MeshBuilder, p: Vector3, h: float, r: float, rng: RandomNumberGenerator) -> void:
	b.cylinder(r * 0.8, r, h, 10, _x(p + Vector3(0, h * 0.5, 0)), Color(0.5, 0.36, 0.3))
	for k in 3:
		b.cylinder(r * 0.82 + 0.01, r * 0.9 + 0.01, h * 0.07, 10, _x(p + Vector3(0, h * (0.65 + k * 0.1), 0)), Color(0.85, 0.85, 0.82) if k % 2 == 0 else Color(0.8, 0.2, 0.15))
	b.cylinder(r * 0.95, r * 0.8, r * 0.4, 10, _x(p + Vector3(0, h + 0.1, 0)), Color(0.2, 0.18, 0.18))
	b.cylinder(r * 0.6, r * 0.6, 0.3, 8, _x(p + Vector3(0, h + 0.3, 0)), _g(Color(1.0, 0.45, 0.1), 0.9))
	# columna de humo estática (conos apilados difuminados)
	for k in 4:
		b.sphere(r * (1.0 + k * 0.55), 6, 4, _x(p + Vector3(rng.randf_range(-2, 2) + k * 2.0, h + 3.0 + k * r * 1.2, 0), Vector3.ZERO, Vector3(1, 0.7, 1)), Color(0.3, 0.28, 0.3).lightened(k * 0.04))


static func _tank_big(b: MeshBuilder, p: Vector3, r: float, h: float, col: Color) -> void:
	b.cylinder(r, r, h, 12, _x(p + Vector3(0, h * 0.5, 0)), col)
	b.cylinder(r * 0.05, r, r * 0.25, 12, _x(p + Vector3(0, h + r * 0.12, 0)), col.darkened(0.15))
	for k in 3:
		b.cylinder(r + 0.04, r + 0.04, 0.2, 12, _x(p + Vector3(0, h * (0.2 + k * 0.3), 0)), col.darkened(0.3))
	b.box(Vector3(0.5, h, 0.2), _x(p + Vector3(r + 0.2, h * 0.5, 0)), Color(0.25, 0.25, 0.28))


static func _crane(b: MeshBuilder, p: Vector3, h: float, yaw: float, col: Color) -> void:
	var bt := Transform3D(Basis.from_euler(Vector3(0, deg_to_rad(yaw), 0)), p)
	for sx in [-1.0, 1.0]:
		_bx(b, bt, Vector3(0.5, h, 0.5), Vector3(sx * 3.0, h * 0.5, 0), Vector3.ZERO, col)
	_bx(b, bt, Vector3(0.7, 0.7, 12.0), Vector3(0, h, 0), Vector3.ZERO, col.lightened(0.05))
	_bx(b, bt, Vector3(7.0, 0.8, 1.0), Vector3(0, h - 0.4, 0), Vector3.ZERO, col)
	_bx(b, bt, Vector3(0.08, 7.0, 0.08), Vector3(0, h - 4.0, 5.0), Vector3.ZERO, Color(0.15, 0.15, 0.18))
	_bx(b, bt, Vector3(0.8, 0.8, 0.8), Vector3(0, h - 7.6, 5.0), Vector3.ZERO, Color(0.85, 0.65, 0.1))
	b.sphere(0.25, 4, 3, bt * _x(Vector3(0, h + 0.7, -6.0)), _g(Color(1.0, 0.2, 0.1), 1.0))


static func _pipe_run(b: MeshBuilder, a: Vector3, c: Vector3, r: float, col: Color) -> void:
	var d := c - a
	var len := d.length()
	if len < 0.1:
		return
	var up := d.normalized()
	var axis := Vector3.UP.cross(up)
	var ang := 0.0 if axis.length() < 0.001 else acos(clampf(Vector3.UP.dot(up), -1.0, 1.0))
	var basis := Basis(axis.normalized(), ang) if axis.length() > 0.001 else Basis.IDENTITY
	b.cylinder(r, r, len, 8, Transform3D(basis, (a + c) * 0.5), col)


# =====================================================================================
#  FONDOS DE LOS DEMÁS BIOMAS
# =====================================================================================
static func _backdrop_forest(root: Node3D, half: float, pal: Dictionary, rng: RandomNumberGenerator) -> void:
	var leaf: Color = (pal["g_main"] as Color).lerp(Color(0.12, 0.45, 0.3), 0.35)
	var bark: Color = pal["wood"]
	# capa cercana: muro de árboles y arbustos justo tras el perímetro
	var near := MeshBuilder.new()
	for i in 70:
		var p := _ring_pos(rng, half + 3.0, half + 17.0)
		if absf(p.x) < half + 2.0 and absf(p.z) < half + 2.0:
			continue
		var h := rng.randf_range(8.0, 15.0)
		if rng.randf() < 0.5:
			_cone_tree(near, p, h, leaf, bark, rng)
		else:
			_oak_tree(near, p, h, leaf.lightened(0.08), bark, rng)
	for i in 36:
		var p2 := _ring_pos(rng, half + 1.5, half + 9.0)
		if absf(p2.x) < half + 1.5 and absf(p2.z) < half + 1.5:
			continue
		near.sphere(rng.randf_range(0.9, 1.7), 6, 4, _x(p2 + Vector3(0, 0.8, 0), Vector3.ZERO, Vector3(1.3, 0.8, 1.3)), _vary(leaf.lightened(0.12), rng, 0.04))
	# ruinas de juzgado entre los árboles (columnas rotas y un arco con balanza)
	var marble: Color = pal["marble"]
	for i in 7:
		var p3 := _ring_pos(rng, half + 10.0, half + 28.0)
		if absf(p3.x) < half + 8.0 and absf(p3.z) < half + 8.0:
			continue
		var hh := rng.randf_range(4.0, 11.0)
		_column(near, p3, 0.9, hh, marble.darkened(0.12), true)
		if rng.randf() < 0.5:
			near.cylinder(0.85, 0.95, 3.0, 8, _x(p3 + Vector3(2.4, 0.9, 1.2), Vector3(0, 20, 84)), marble.darkened(0.18))
		for k in 3:
			near.sphere(0.5, 4, 3, _x(p3 + Vector3(rng.randf_range(-1.2, 1.2), hh * rng.randf_range(0.2, 0.9), rng.randf_range(-1.2, 1.2)), Vector3.ZERO, Vector3(1, 0.7, 1)), Color(0.3, 0.5, 0.26))
	_layer(root, near, "BackdropNear")
	# capa media: bosque denso + árboles ancestrales gigantes con copas luminosas
	var mid := MeshBuilder.new()
	for i in 60:
		var p4 := _ring_pos(rng, half + 20.0, half + 60.0)
		var h2 := rng.randf_range(14.0, 26.0)
		if rng.randf() < 0.55:
			_cone_tree(mid, p4, h2, leaf.darkened(0.04), bark, rng)
		else:
			_oak_tree(mid, p4, h2, leaf, bark, rng)
	for i in 9:
		var p5 := _ring_pos(rng, half + 30.0, half + 80.0)
		var gh := rng.randf_range(34.0, 52.0)
		mid.cylinder(gh * 0.05, gh * 0.09, gh * 0.6, 8, _x(p5 + Vector3(0, gh * 0.3, 0)), bark)
		for k in 6:
			var a := TAU * float(k) / 6.0
			mid.cylinder(gh * 0.012, gh * 0.04, gh * 0.18, 5, _x(p5 + Vector3(cos(a) * gh * 0.07, gh * 0.06, sin(a) * gh * 0.07), Vector3(sin(a) * 60.0, 0, -cos(a) * 60.0)), bark.darkened(0.1))
		for k in 7:
			mid.sphere(gh * rng.randf_range(0.14, 0.22), 6, 4, _x(p5 + Vector3(rng.randf_range(-0.2, 0.2) * gh, gh * rng.randf_range(0.62, 0.85), rng.randf_range(-0.2, 0.2) * gh), Vector3.ZERO, Vector3(1.2, 0.8, 1.2)), _vary(leaf.lightened(0.1), rng, 0.04))
		for k in 10:
			mid.sphere(0.3, 4, 3, _x(p5 + Vector3(rng.randf_range(-0.25, 0.25) * gh, gh * rng.randf_range(0.5, 0.8), rng.randf_range(-0.25, 0.25) * gh)), _g(Color(0.7, 1.0, 0.8), 0.95))
	_layer(root, mid, "BackdropMid")
	# capa lejana: colinas boscosas azuladas
	var far := MeshBuilder.new()
	far_hills(far, pal, rng, 12, 230.0, 30.0, 70.0, Color(0.3, 0.5, 0.48))
	for i in 40:
		_cone_tree(far, _ring_pos(rng, 110.0, 190.0), rng.randf_range(24.0, 40.0), Color(0.24, 0.45, 0.42), Color(0.3, 0.3, 0.3), rng)
	_layer(root, far, "BackdropFar")
	# haces de luz filtrados entre los árboles (translúcidos, aditivos, bordes suaves; muy baratos)
	for i in 6:
		var c := _ring_pos(rng, 14.0, half + 4.0, 0.0)
		for k in 2:
			var mi := MeshInstance3D.new()
			mi.mesh = _shaft_mesh(rng.randf_range(2.5, 4.5), 24.0, Color(1.0, 0.95, 0.6, 0.075))
			mi.material_override = _shaft_mat()
			mi.position = c + Vector3(0, 12.0, 0)
			mi.rotation_degrees = Vector3(0, k * 90.0 + rng.randf_range(-20, 20), rng.randf_range(-8, 8))
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.name = "LightShaft"
			root.add_child(mi)


static var _shaft_material: StandardMaterial3D


static func _shaft_mat() -> StandardMaterial3D:
	if _shaft_material == null:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.vertex_color_use_as_albedo = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_shaft_material = m
	return _shaft_material


## Haz de luz vertical: 3 columnas x 2 filas con alfa que se desvanece en los bordes y hacia arriba.
static func _shaft_mesh(w: float, h: float, col: Color) -> ArrayMesh:
	var v := PackedVector3Array()
	var c := PackedColorArray()
	var idx := PackedInt32Array()
	var xs := [-w * 0.5, 0.0, w * 0.5]
	var ya := [-h * 0.5, h * 0.5]
	for r in 2:
		for k in 3:
			v.append(Vector3(xs[k], ya[r], 0))
			var a := col.a * (0.0 if k != 1 else 1.0) * (0.15 if r == 1 else 1.0)
			c.append(Color(col.r, col.g, col.b, a))
	for k in 2:
		var i0 := k
		idx.append_array([i0, i0 + 1, i0 + 3, i0 + 1, i0 + 4, i0 + 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_COLOR] = c
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


static func _backdrop_industrial(root: Node3D, half: float, pal: Dictionary, rng: RandomNumberGenerator) -> void:
	var tints := [Color(0.42, 0.3, 0.26), Color(0.36, 0.38, 0.42), Color(0.5, 0.42, 0.34), Color(0.3, 0.32, 0.36)]
	var near := MeshBuilder.new()
	# fábricas con cubiertas dentadas, chimeneas y tuberías puente
	var side_pos: Array = []
	for side in 4:
		var span := half + 8.0 if side < 2 else half - 2.0
		var x := -span
		while x < span - 6.0:
			var w := rng.randf_range(12.0, 20.0)
			var d := rng.randf_range(10.0, 16.0)
			var h := rng.randf_range(10.0, 22.0)
			var dist := half + 7.0 + d * 0.5
			var pos := Vector3.ZERO
			var yaw := 0.0
			match side:
				0: pos = Vector3(x + w * 0.5, -0.3, -dist); yaw = 0.0
				1: pos = Vector3(x + w * 0.5, -0.3, dist); yaw = 180.0
				2: pos = Vector3(-dist, -0.3, x + w * 0.5); yaw = 90.0
				3: pos = Vector3(dist, -0.3, x + w * 0.5); yaw = -90.0
			var bt := Transform3D(Basis.from_euler(Vector3(0, deg_to_rad(yaw), 0)), pos)
			building(near, bt, w, d, h, tints[rng.randi() % tints.size()], pal, rng, 1, false, 0.3)
			# cubierta dentada (sierra)
			for k in int(w / 3.0):
				_bx(near, bt, Vector3(2.6, 2.2, d * 0.9), Vector3(-w * 0.5 + 1.5 + k * 3.0, h + 1.2, 0), Vector3(0, 0, -14), tints[0].darkened(0.2))
			if rng.randf() < 0.6:
				_chimney(near, pos + Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-3, 3)) + (bt.basis * Vector3(0, 0, -d * 0.2)), rng.randf_range(24.0, 44.0), rng.randf_range(1.3, 2.0), rng)
			side_pos.append(pos + Vector3(0, h * 0.6, 0))
			x += w + rng.randf_range(1.0, 3.0)
	# tuberías que unen edificios cercanos
	for i in side_pos.size() - 1:
		if rng.randf() < 0.5:
			var a: Vector3 = side_pos[i]
			var c: Vector3 = side_pos[i + 1]
			if a.distance_to(c) < 30.0:
				_pipe_run(near, a + Vector3(0, 3.0, 0), c + Vector3(0, 3.0, 0), 0.5, Color(0.5, 0.52, 0.56))
				_pipe_run(near, a + Vector3(0, 4.2, 0), c + Vector3(0, 4.2, 0), 0.3, Color(0.7, 0.3, 0.15))
	_layer(root, near, "BackdropNear")
	var mid := MeshBuilder.new()
	for i in 12:
		var p := _ring_pos(rng, half + 28.0, half + 70.0)
		_tank_big(mid, p, rng.randf_range(4.0, 8.0), rng.randf_range(8.0, 16.0), tints[rng.randi() % tints.size()].lightened(0.1))
	for i in 7:
		_crane(mid, _ring_pos(rng, half + 25.0, half + 65.0), rng.randf_range(24.0, 34.0), rng.randf() * 360.0, Color(0.85, 0.6, 0.12))
	for i in 9:
		_chimney(mid, _ring_pos(rng, half + 30.0, half + 90.0), rng.randf_range(36.0, 60.0), rng.randf_range(1.8, 3.0), rng)
	tower_ring(mid, pal, rng, 8, half + 35.0, half + 70.0, 26.0, 50.0, tints, 0)
	_layer(root, mid, "BackdropMid")
	var far := MeshBuilder.new()
	tower_ring(far, pal, rng, 16, 130.0, 200.0, 40.0, 90.0, [Color(0.36, 0.3, 0.3), Color(0.32, 0.32, 0.36)], 0)
	for i in 12:
		_chimney(far, _ring_pos(rng, 130.0, 220.0), rng.randf_range(60.0, 100.0), rng.randf_range(3.0, 5.0), rng)
	far_hills(far, pal, rng, 8, 280.0, 30.0, 60.0, Color(0.45, 0.34, 0.32))
	_layer(root, far, "BackdropFar")


static func _backdrop_desert(root: Node3D, half: float, pal: Dictionary, rng: RandomNumberGenerator) -> void:
	var rock := Color(0.66, 0.38, 0.26)
	var sand: Color = pal["g_main"]
	var near := MeshBuilder.new()
	# rocas rojizas cercanas formando un anillo de cañón
	for i in 40:
		var p := _ring_pos(rng, half + 4.0, half + 20.0)
		if absf(p.x) < half + 3.0 and absf(p.z) < half + 3.0:
			continue
		_mesa(near, p, rng.randf_range(6.0, 14.0), rng.randf_range(6.0, 20.0), rock, rng)
	# ruinas: columnas, arcos y una gigantesca cabeza de estatua medio enterrada
	var stone: Color = (pal["marble"] as Color).darkened(0.08)
	for i in 8:
		var p2 := _ring_pos(rng, half + 8.0, half + 26.0)
		if absf(p2.x) < half + 6.0 and absf(p2.z) < half + 6.0:
			continue
		_column(near, p2, 1.0, rng.randf_range(4.0, 10.0), stone, true)
	var head := _ring_pos(rng, half + 18.0, half + 30.0, 0.0)
	near.sphere(5.5, 8, 6, _x(head + Vector3(0, 1.5, 0), Vector3.ZERO, Vector3(1.0, 1.15, 1.0)), stone)
	near.box(Vector3(2.0, 2.4, 2.6), _x(head + Vector3(0, 0.6, 5.0)), stone.darkened(0.06))
	for sx in [-2.0, 2.0]:
		near.box(Vector3(1.4, 0.7, 1.0), _x(head + Vector3(sx, 3.2, 4.8)), Color(0.12, 0.1, 0.1))
	near.box(Vector3(7.0, 0.8, 5.0), _x(head + Vector3(0, 6.5, 0)), stone.darkened(0.15))   # tocado
	_layer(root, near, "BackdropNear")
	var mid := MeshBuilder.new()
	for i in 18:
		_dune(mid, _ring_pos(rng, half + 22.0, half + 70.0, -0.5), rng.randf_range(40.0, 80.0), rng.randf_range(6.0, 16.0), sand.lerp(pal["g_alt"], rng.randf() * 0.6), rng)
	for i in 10:
		_mesa(mid, _ring_pos(rng, half + 40.0, half + 110.0), rng.randf_range(18.0, 36.0), rng.randf_range(24.0, 55.0), rock.lightened(0.04), rng)
	# arco de roca natural
	for i in 2:
		var ap := _ring_pos(rng, half + 50.0, half + 90.0)
		var yaw := rad_to_deg(atan2(-ap.x, -ap.z))
		var bt := Transform3D(Basis.from_euler(Vector3(0, deg_to_rad(yaw), 0)), ap)
		_bx(mid, bt, Vector3(8.0, 24.0, 10.0), Vector3(-9.0, 12.0, 0), Vector3.ZERO, rock)
		_bx(mid, bt, Vector3(8.0, 20.0, 10.0), Vector3(9.0, 10.0, 0), Vector3.ZERO, rock.darkened(0.06))
		_bx(mid, bt, Vector3(30.0, 7.0, 10.0), Vector3(0, 23.0, 0), Vector3(0, 0, 3), rock.lightened(0.05))
	# torres de expedientes gigantes (archivo olvidado)
	for i in 6:
		var tp := _ring_pos(rng, half + 30.0, half + 80.0)
		var y := 0.0
		for k in rng.randi_range(8, 16):
			var s := Vector3(rng.randf_range(7.0, 11.0), rng.randf_range(1.2, 2.2), rng.randf_range(5.0, 8.0))
			mid.box(s, _x(tp + Vector3(rng.randf_range(-0.8, 0.8), y + s.y * 0.5, rng.randf_range(-0.8, 0.8)), Vector3(0, rng.randf_range(-12, 12), rng.randf_range(-1.5, 1.5))), [Color(0.82, 0.74, 0.55), Color(0.72, 0.62, 0.42), Color(0.88, 0.8, 0.62)][rng.randi() % 3])
			y += s.y
	_layer(root, mid, "BackdropMid")
	var far := MeshBuilder.new()
	far_hills(far, pal, rng, 14, 260.0, 30.0, 90.0, Color(0.78, 0.55, 0.38), true)
	for i in 6:
		_mesa(far, _ring_pos(rng, 150.0, 240.0), rng.randf_range(40.0, 70.0), rng.randf_range(60.0, 110.0), Color(0.74, 0.5, 0.36), rng)
	_layer(root, far, "BackdropFar")


static func _backdrop_citadel(root: Node3D, half: float, pal: Dictionary, rng: RandomNumberGenerator) -> void:
	var top := Color(0.55, 0.78, 0.7)
	var rock := Color(0.48, 0.5, 0.64)
	# la propia arena es una isla: roca invertida bajo el terreno
	var near := MeshBuilder.new()
	var r0 := half + 5.0
	near.frustum(Vector2(r0 * 2.0, r0 * 2.0), Vector2(r0 * 0.3, r0 * 0.3), 46.0, _x(Vector3(0, -23.5, 0), Vector3(180, 0, 0)), rock)
	for i in 5:
		var a := TAU * float(i) / 5.0
		near.frustum(Vector2(9.0, 9.0), Vector2(0.4, 0.4), rng.randf_range(20.0, 40.0), _x(Vector3(cos(a) * r0 * 0.55, -22.0, sin(a) * r0 * 0.55), Vector3(180, rng.randf() * 90.0, 0)), rock.darkened(0.15))
	for i in 24:
		var a2 := TAU * float(i) / 24.0
		near.box(Vector3(2.2, 5.0, 2.2), _x(Vector3(cos(a2) * (half + 3.5), -2.2, sin(a2) * (half + 3.5)), Vector3(0, -rad_to_deg(a2), 0)), rock.lightened(0.05))
	# islas cercanas con edificios y puentes
	var islands: Array = []
	for i in 9:
		var a3 := TAU * (float(i) + rng.randf_range(-0.25, 0.25)) / 9.0
		var dist := rng.randf_range(half + 28.0, half + 70.0)
		var p := Vector3(cos(a3) * dist, rng.randf_range(-12.0, 14.0), sin(a3) * dist)
		var r := rng.randf_range(12.0, 22.0)
		_island(near, p, r, rng.randf_range(20.0, 36.0), (pal["marble"] as Color).darkened(0.06) if i % 2 == 0 else top, rock, rng, i % 2 == 0, pal)
		islands.append(Vector3(p.x, p.y, p.z))
	# puentes de luz entre la isla principal y las más cercanas, y entre islas
	for i in islands.size():
		var a4: Vector3 = islands[i]
		var c4: Vector3 = islands[(i + 1) % islands.size()]
		if a4.distance_to(c4) < 80.0:
			_pipe_run(near, a4 + Vector3(0, 0.9, 0), c4 + Vector3(0, 0.9, 0), 0.45, _g(Color(0.6, 0.95, 1.0), 0.7))
	_layer(root, near, "BackdropNear")
	var mid := MeshBuilder.new()
	for i in 12:
		var a5 := rng.randf() * TAU
		var d5 := rng.randf_range(half + 90.0, half + 190.0)
		_island(mid, Vector3(cos(a5) * d5, rng.randf_range(-30.0, 40.0), sin(a5) * d5), rng.randf_range(16.0, 38.0), rng.randf_range(30.0, 60.0), top.lightened(0.05), rock, rng, rng.randf() < 0.5, pal)
	for i in 8:
		var a6 := rng.randf() * TAU
		var d6 := rng.randf_range(half + 60.0, half + 160.0)
		var ch := rng.randf_range(30.0, 70.0)
		mid.frustum(Vector2(9.0, 9.0), Vector2(0.4, 0.4), ch, _x(Vector3(cos(a6) * d6, -10.0 + ch * 0.5, sin(a6) * d6), Vector3(rng.randf_range(-6, 6), rng.randf() * 90.0, rng.randf_range(-6, 6))), _g(pal["paints"][rng.randi() % 3], 0.5))
	_layer(root, mid, "BackdropMid", 520.0)
	var far := MeshBuilder.new()
	for i in 26:
		var a7 := rng.randf() * TAU
		var d7 := rng.randf_range(160.0, 330.0)
		_cloud(far, Vector3(cos(a7) * d7, rng.randf_range(-70.0, -15.0), sin(a7) * d7), rng.randf_range(12.0, 28.0), Color(0.95, 0.86, 0.98).darkened(rng.randf() * 0.1), rng)
	for i in 10:
		var a8 := rng.randf() * TAU
		var d8 := rng.randf_range(200.0, 340.0)
		_island(far, Vector3(cos(a8) * d8, rng.randf_range(10.0, 90.0), sin(a8) * d8), rng.randf_range(20.0, 40.0), rng.randf_range(40.0, 70.0), top, rock, rng, true, pal)
	_layer(root, far, "BackdropFar", 640.0)


static func _backdrop_court(root: Node3D, half: float, pal: Dictionary, rng: RandomNumberGenerator) -> void:
	var marble: Color = (pal["marble"] as Color).darkened(0.1)
	var gold: Color = pal["metal"]
	var red: Color = pal["paints"][0]
	var near := MeshBuilder.new()
	# dos colonnatas monumentales alrededor del patio + entablamento + muro vidriera
	for row in 2:
		var off := half + 7.0 + float(row) * 9.0
		var ch := 20.0 + float(row) * 6.0
		var rad := 1.3 + float(row) * 0.2
		var n := int((half * 2.0 + 20.0) / 6.5)
		for side in 4:
			for k in n + 1:
				var t := -half - 10.0 + float(k) * 6.5
				var p := Vector3.ZERO
				match side:
					0: p = Vector3(t, -0.3, -off)
					1: p = Vector3(t, -0.3, off)
					2: p = Vector3(-off, -0.3, t)
					3: p = Vector3(off, -0.3, t)
				if side >= 2 and absf(t) > half + 4.0:
					continue
				_column(near, p, rad, ch, marble.lightened(0.04 * row), true)
			# entablamento continuo
			var span := half * 2.0 + 24.0
			var ey := ch + rad * 2.0 + 1.6
			match side:
				0: near.box(Vector3(span, 3.0, 2.6), _x(Vector3(0, ey, -off)), marble.darkened(0.08))
				1: near.box(Vector3(span, 3.0, 2.6), _x(Vector3(0, ey, off)), marble.darkened(0.08))
				2: near.box(Vector3(2.6, 3.0, half * 2.0 + 8.0), _x(Vector3(-off, ey, 0)), marble.darkened(0.08))
				3: near.box(Vector3(2.6, 3.0, half * 2.0 + 8.0), _x(Vector3(off, ey, 0)), marble.darkened(0.08))
	# muro posterior con grandes vidrieras luminosas y estandartes entre columnas
	var wall_d := half + 27.0
	for side in 4:
		var bt := Transform3D(Basis.from_euler(Vector3(0, deg_to_rad([0.0, 180.0, 90.0, -90.0][side]), 0)), Vector3.ZERO)
		var sgn := -1.0 if side == 0 else (1.0 if side == 1 else (-1.0 if side == 2 else 1.0))
		var along := Vector3(0, 0, 0)
		if side < 2:
			along = Vector3(0, 0, sgn * wall_d)
		else:
			along = Vector3(sgn * wall_d, 0, 0)
		var wbt := Transform3D(bt.basis, along)
		_bx(near, wbt, Vector3(half * 2.0 + 60.0, 44.0, 3.0), Vector3(0, 22.0, -1.5), Vector3.ZERO, pal["building"])
		for k in 7:
			var wx := -half + 4.0 + float(k) * (half * 2.0 - 8.0) / 6.0
			var wc: Color = [Color(1.0, 0.7, 0.25), Color(0.85, 0.3, 0.45), Color(0.4, 0.45, 0.95)][k % 3]
			_qd(near, wbt, Vector3(wx - 2.2, 6.0, 0.05), Vector3(wx + 2.2, 6.0, 0.05), Vector3(wx + 2.2, 26.0, 0.05), Vector3(wx - 2.2, 26.0, 0.05), Vector3(wx, 16.0, -3.0), _g(wc, 0.7))
			_qd(near, wbt, Vector3(wx - 1.4, 26.0, 0.06), Vector3(wx + 1.4, 26.0, 0.06), Vector3(wx, 30.0, 0.06), Vector3(wx, 30.0, 0.06), Vector3(wx, 16.0, -3.0), _g(wc, 0.7))
			_bx(near, wbt, Vector3(0.3, 20.0, 0.2), Vector3(wx, 16.0, 0.12), Vector3.ZERO, gold)
			if k % 2 == 0:
				_bx(near, wbt, Vector3(2.4, 10.0, 0.15), Vector3(wx + (half * 2.0 - 8.0) / 12.0, 17.0, 0.5), Vector3.ZERO, red)
				_bx(near, wbt, Vector3(0.9, 0.9, 0.18), Vector3(wx + (half * 2.0 - 8.0) / 12.0, 19.0, 0.6), Vector3(0, 0, 45), _g(gold, 0.6))
	for i in 8:
		var a := TAU * float(i) / 8.0 + 0.39
		var bp := Vector3(cos(a) * (half + 4.5), 0.0, sin(a) * (half + 4.5))
		near.cylinder(0.3, 0.45, 1.8, 6, _x(bp + Vector3(0, 0.9, 0)), gold.darkened(0.2))
		near.frustum(Vector2(0.9, 0.9), Vector2(0.1, 0.1), 1.4, _x(bp + Vector3(0, 2.4, 0)), _g(Color(1.0, 0.55, 0.15), 0.95))
	_layer(root, near, "BackdropNear")
	# capa media: anillo de energía flotante y haces + cúpula del tribunal
	var mid := MeshBuilder.new()
	var ring_r := half + 2.0
	for i in 40:
		var a2 := TAU * float(i) / 40.0
		mid.box(Vector3(2.4, 0.5, 0.5), _x(Vector3(cos(a2) * ring_r, 40.0 + sin(a2 * 3.0) * 1.5, sin(a2) * ring_r), Vector3(0, -rad_to_deg(a2) + 90.0, 0)), _g(Color(1.0, 0.75, 0.3), 0.9) if i % 2 == 0 else _g(Color(0.75, 0.4, 1.0), 0.9))
	var dome_p := Vector3(0, 0, -(half + 90.0))
	mid.cylinder(28.0, 30.0, 40.0, 16, _x(dome_p + Vector3(0, 20, 0)), (pal["building"] as Color).lightened(0.08))
	mid.sphere(30.0, 12, 8, _x(dome_p + Vector3(0, 40, 0), Vector3.ZERO, Vector3(1, 0.75, 1)), (pal["building"] as Color).lightened(0.14))
	mid.cylinder(1.0, 3.0, 22.0, 6, _x(dome_p + Vector3(0, 72, 0)), gold)
	mid.sphere(2.5, 6, 5, _x(dome_p + Vector3(0, 84, 0)), _g(Color(1.0, 0.8, 0.35), 1.0))
	tower_ring(mid, pal, rng, 10, half + 70.0, half + 120.0, 50.0, 110.0, [Color(0.22, 0.2, 0.32), Color(0.26, 0.22, 0.36)], 0)
	_layer(root, mid, "BackdropMid", 560.0)
	var far := MeshBuilder.new()
	# balanza gigante lejana
	var sp := Vector3(-30.0, 0, -(half + 180.0))
	far.cylinder(4.0, 7.0, 90.0, 8, _x(sp + Vector3(0, 45, 0)), marble.darkened(0.1))
	far.box(Vector3(90.0, 3.0, 3.0), _x(sp + Vector3(0, 92, 0), Vector3(0, 0, 4)), gold)
	for sx in [-42.0, 42.0]:
		far.cylinder(14.0, 14.0, 1.2, 10, _x(sp + Vector3(sx, 70.0 + (3.0 if sx > 0 else -3.0), 0)), _g(gold, 0.45))
		far.frustum(Vector2(0.8, 0.8), Vector2(0.8, 0.8), 22.0, _x(sp + Vector3(sx * 0.98, 82.0, 0)), gold)
	for i in 12:
		var a3 := rng.randf() * TAU
		far.sphere(rng.randf_range(2.0, 6.0), 5, 4, _x(Vector3(cos(a3) * 330.0, rng.randf_range(60.0, 140.0), sin(a3) * 330.0)), _g(Color(0.7, 0.4, 1.0), 0.5))
	var moon := Vector3(120.0, 160.0, -300.0)
	far.sphere(34.0, 12, 8, _x(moon), _g(Color(0.95, 0.88, 0.8), 0.7))
	far_hills(far, pal, rng, 8, 300.0, 40.0, 90.0, Color(0.18, 0.12, 0.26))
	_layer(root, far, "BackdropFar", 700.0)
	# haces verticales de energía (aditivos) en las esquinas
	for i in 4:
		var a4 := TAU * (float(i) + 0.5) / 4.0
		for k in 2:
			var mi := MeshInstance3D.new()
			mi.mesh = _shaft_mesh(4.0, 60.0, Color(1.0, 0.7, 0.25, 0.16))
			mi.material_override = _shaft_mat()
			mi.position = Vector3(cos(a4) * (half + 3.0), 30.0, sin(a4) * (half + 3.0))
			mi.rotation_degrees = Vector3(0, k * 90.0, 0)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.name = "EnergyBeam"
			root.add_child(mi)
