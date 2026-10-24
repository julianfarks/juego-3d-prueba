class_name BiomeProps
extends RefCounted
## Objetos del escenario con colisión por bioma (obstáculos jugables) y estructuras interactivas temáticas
## (tienda, cofre, portal). Los tipos antiguos (coche, barrera, contenedor…) siguen en PropsFactory.make_obstacle;
## aquí se añaden los nuevos y se delega lo demás. Cada obstáculo devuelve {"node": StaticBody3D, "size": Vector3}
## donde 'size' es la HUELLA para colocarlo sin bloquear (la colisión real suele ser menor que lo que se ve:
## las copas de los árboles, los toldos, etc. NO bloquean al jugador ni a los ataques).

static func _x(pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE) -> Transform3D:
	return MeshBuilder.xf(pos, rot, scl)


static func _g(c: Color, amount := 1.0) -> Color:
	return MeshBuilder.glow(c, amount)


static func _vary(c: Color, rng: RandomNumberGenerator, amt := 0.05) -> Color:
	return Color(clampf(c.r + rng.randf_range(-amt, amt), 0, 1), clampf(c.g + rng.randf_range(-amt, amt), 0, 1), clampf(c.b + rng.randf_range(-amt, amt), 0, 1), c.a)


static func _finish(b: MeshBuilder, kind: String, footprint: Vector3, col_size: Vector3, col_center: Vector3) -> Dictionary:
	var body := PropsFactory.static_body(col_size, col_center)
	body.name = "Obstacle_" + kind
	Mats.mesh_instance(b.build(), Mats.world_material(), body)
	return {"node": body, "size": footprint}


static func make(kind: String, rng: RandomNumberGenerator, pal: Dictionary) -> Dictionary:
	match kind:
		"lamp": return _lamp(rng, pal)
		"sign": return _sign(rng, pal)
		"planter": return _planter(rng, pal)
		"rubble": return _rubble(rng, pal)
		"bus_stop": return _bus_stop(rng, pal)
		"tree_city": return _tree(rng, pal, 4.2, true)
		"tree": return _tree(rng, pal, rng.randf_range(5.0, 7.0), false)
		"tree_big": return _tree(rng, pal, rng.randf_range(8.0, 10.5), false, 1.6)
		"bush": return _bush(rng, pal)
		"stump": return _stump(rng, pal)
		"log": return _log(rng, pal)
		"mushrooms": return _mushrooms(rng, pal)
		"rock": return _rock(rng, pal, false)
		"rock_red": return _rock(rng, pal, true)
		"pipes": return _pipes(rng, pal)
		"machine": return _machine(rng, pal)
		"pylon": return _pylon(rng, pal)
		"cactus": return _cactus(rng, pal)
		"ruin_pillar": return _ruin_pillar(rng, pal)
		"archive_stack": return _archive_stack(rng, pal)
		"bones": return _bones(rng, pal)
		"dead_tree": return _dead_tree(rng, pal)
		"buried_arch": return _buried_arch(rng, pal)
		"crystal": return _crystal(rng, pal)
		"float_pillar": return _float_pillar(rng, pal)
		"arch": return _arch(rng, pal)
		"lantern": return _lantern(rng, pal)
		"planter_magic": return _planter_magic(rng, pal)
		"brazier": return _brazier(rng, pal)
		"scale_statue": return _scale_statue(rng, pal)
		"banner": return _banner(rng, pal)
	return PropsFactory.make_obstacle(kind, rng, pal)


# ====================================================================== URBANO
static func _lamp(rng: RandomNumberGenerator, pal: Dictionary) -> Dictionary:
	var b := MeshBuilder.new()
	var m := Color(0.22, 0.24, 0.27)
	b.cylinder(0.3, 0.38, 0.5, 8, _x(Vector3(0, 0.25, 0)), m.lightened(0.05))
	b.cylinder(0.09, 0.14, 5.4, 6, _x(Vector3(0, 2.9, 0)), m)
	b.box(Vector3(1.3, 0.1, 0.12), _x(Vector3(0.55, 5.55, 0), Vector3(0, 0, 4)), m)
	var on := rng.randf() < 0.6
	b.box(Vector3(0.55, 0.14, 0.32), _x(Vector3(1.15, 5.45, 0)), _g(Color(1.0, 0.85, 0.5), 1.0) if on else m.darkened(0.3))
	b.box(Vector3(0.62, 0.06, 0.4), _x(Vector3(1.15, 5.56, 0)), m.darkened(0.2))
	return _finish(b, "lamp", Vector3(1.2, 5.6, 1.2), Vector3(0.6, 5.0, 0.6), Vector3(0, 2.5, 0))


static func _sign(rng: RandomNumberGenerator, pal: Dictionary) -> Dictionary:
	var b := MeshBuilder.new()
	var m := Color(0.4, 0.42, 0.45)
	var lean := rng.randf_range(-6.0, 6.0)
	b.cylinder(0.05, 0.06, 3.0, 5, _x(Vector3(0, 1.5, 0), Vector3(0, 0, lean)), m)
	var kind := rng.randi() % 3
	var plate := Color(0.85, 0.15, 0.12) if kind == 0 else (Color(0.95, 0.78, 0.15) if kind == 1 else Color(0.15, 0.4, 0.75))
	var top := Vector3(sin(deg_to_rad(-lean)) * 3.0 * -1.0, 3.0, 0)
	if kind == 1:
		b.box(Vector3(0.9, 0.9, 0.06), _x(Vector3(top.x, 3.2, 0.06), Vector3(0, 0, 45 + lean)), plate)
		b.box(Vector3(0.6, 0.1, 0.07), _x(Vector3(top.x, 3.2, 0.08), Vector3(0, 0, 45 + lean)), Color(0.1, 0.1, 0.1))
	else:
		b.cylinder(0.5, 0.5, 0.06, 8, _x(Vector3(top.x, 3.2, 0.06), Vector3(90, 0, lean)), plate)
		b.box(Vector3(0.62, 0.12, 0.07), _x(Vector3(top.x, 3.2, 0.1), Vector3(0, 0, lean)), Color(0.95, 0.95, 0.95))
	b.cylinder(0.25, 0.3, 0.2, 8, _x(Vector3(0, 0.1, 0)), Color(0.3, 0.3, 0.32))
	return _finish(b, "sign", Vector3(0.9, 3.6, 0.9), Vector3(0.4, 3.0, 0.4), Vector3(0, 1.5, 0))


static func _foliage(b: MeshBuilder, rng: RandomNumberGenerator, center: Vector3, r: float, col: Color, blobs := 4) -> void:
	for i in blobs:
		var o := Vector3(rng.randf_range(-r, r) * 0.7, rng.randf_range(-r, r) * 0.45, rng.randf_range(-r, r) * 0.7)
		b.sphere(r * rng.randf_range(0.65, 1.0), 6, 4, _x(center + o), _vary(col, rng, 0.04))


static func _planter(rng: RandomNumberGenerator, pal: Dictionary) -> Dictionary:
	var b := MeshBuilder.new()
	var conc := Color(0.55, 0.54, 0.5)
	b.box(Vector3(2.8, 0.8, 1.3), _x(Vector3(0, 0.4, 0)), conc)
	b.box(Vector3(2.9, 0.12, 1.4), _x(Vector3(0, 0.82, 0)), conc.lightened(0.1))
	b.box(Vector3(2.6, 0.12, 1.1), _x(Vector3(0, 0.84, 0)), Color(0.28, 0.2, 0.14))
	var green: Color = pal.get("g_detail", Color(0.3, 0.45, 0.22))
	_foliage(b, rng, Vector3(-0.6, 1.2, 0), 0.5, green, 3)
	_foliage(b, rng, Vector3(0.9, 1.1, 0.1), 0.42, green.lightened(0.08), 3)
	b.cylinder(0.08, 0.12, 1.8, 5, _x(Vector3(0.1, 1.7, 0)), Color(0.35, 0.24, 0.14))
	_foliage(b, rng, Vector3(0.1, 2.8, 0), 0.95, green.darkened(0.05), 5)
	return _finish(b, "planter", Vector3(3.0, 3.6, 1.6), Vector3(2.8, 0.9, 1.3), Vector3(0, 0.45, 0))


static func _rubble(rng: RandomNumberGenerator, pal: Dictionary) -> Dictionary:
	var b := MeshBuilder.new()
	var base := Color(0.46, 0.43, 0.4)
	for i in 10:
		var s := Vector3(rng.randf_range(0.5, 1.4), rng.randf_range(0.25, 0.7), rng.randf_range(0.5, 1.3))
		var px := rng.randf_range(-1.0, 1.0) * (1.0 - float(i) * 0.06)
		var pz := rng.randf_range(-0.9, 0.9) * (1.0 - float(i) * 0.06)
		var py := s.y * 0.5 + float(i % 4) * 0.22
		b.box(s, _x(Vector3(px, py, pz), Vector3(rng.randf_range(-15, 15), rng.randf_range(0, 90), rng.randf_range(-15, 15))), _vary(base, rng, 0.07))
	for i in 3:
		b.cylinder(0.025, 0.025, 1.3, 4, _x(Vector3(rng.randf_range(-0.8, 0.8), 1.0, rng.randf_range(-0.7, 0.7)), Vector3(rng.randf_range(-35, 35), 0, rng.randf_range(-35, 35))), Color(0.5, 0.26, 0.14))
	return _finish(b, "rubble", Vector3(3.4, 1.4, 3.0), Vector3(2.4, 0.9, 2.2), Vector3(0, 0.45, 0))


static func _bus_stop(rng: RandomNumberGenerator, pal: Dictionary) -> Dictionary:
	var b := MeshBuilder.new()
	var m := Color(0.3, 0.32, 0.36)
	for sx in [-1.7, 1.7]:
		b.box(Vector3(0.14, 2.6, 0.14), _x(Vector3(sx, 1.3, -0.5)), m)
		b.box(Vector3(0.14, 2.4, 0.14), _x(Vector3(sx, 1.2, 0.5)), m)
	b.box(Vector3(3.8, 0.12, 1.5), _x(Vector3(0, 2.55, 0), Vector3(4, 0, 0)), m.lightened(0.1))
	b.box(Vector3(3.4, 1.8, 0.05), _x(Vector3(0, 1.4, -0.52)), _g(Color(0.5, 0.75, 0.85), 0.12))
	b.box(Vector3(1.0, 1.5, 0.08), _x(Vector3(1.0, 1.4, -0.46)), _g(Color(0.95, 0.85, 0.5), 0.55))
	b.box(Vector3(2.2, 0.1, 0.5), _x(Vector3(-0.3, 0.55, -0.15)), Color(0.45, 0.32, 0.2))
	b.box(Vector3(0.1, 0.5, 0.4), _x(Vector3(-1.2, 0.3, -0.15)), m)
	b.box(Vector3(0.1, 0.5, 0.4), _x(Vector3(0.6, 0.3, -0.15)), m)
	return _finish(b, "bus_stop", Vector3(3.9, 2.8, 1.8), Vector3(3.6, 2.4, 0.35), Vector3(0, 1.2, -0.5))


# ====================================================================== ÁRBOLES / ROCAS
static func _tree(rng: RandomNumberGenerator, pal: Dictionary, h: float, urban: bool, width := 1.0) -> Dictionary:
	var b := MeshBuilder.new()
	var bark: Color = pal.get("wood", Color(0.4, 0.27, 0.15))
	var leaf: Color = pal.get("g_main", Color(0.2, 0.4, 0.2))
	if urban:
		leaf = Color(0.34, 0.42, 0.2) if rng.randf() < 0.65 else Color(0.62, 0.38, 0.14)
	else:
		leaf = leaf.lerp(Color(0.12, 0.42, 0.28), 0.4).lightened(0.05 + rng.randf() * 0.08)
	var tr := 0.3 * width
	b.cylinder(tr * 0.7, tr * 1.25, h * 0.55, 7, _x(Vector3(0, h * 0.275, 0)), _vary(bark, rng, 0.03))
	# raíces vistas
	for i in 5:
		var a := TAU * float(i) / 5.0 + rng.randf() * 0.4
		b.cylinder(tr * 0.12, tr * 0.5, tr * 3.0, 4, _x(Vector3(cos(a) * tr * 1.3, tr * 0.5, sin(a) * tr * 1.3), Vector3(sin(a) * 55.0, 0, -cos(a) * 55.0)), bark.darkened(0.12))
	if urban:
		_foliage(b, rng, Vector3(0, h * 0.78, 0), h * 0.28, leaf, 5)
	else:
		# copa en capas de frustos (aspecto de conífera/roble estilizado)
		var layers := 4
		for i in layers:
			var t := float(i) / float(layers)
			var lw := (1.0 - t * 0.7) * h * 0.3 * width
			b.frustum(Vector2(lw * 2.0, lw * 2.0), Vector2(lw * 0.9, lw * 0.9), h * 0.28, _x(Vector3(rng.randf_range(-0.12, 0.12), h * (0.38 + t * 0.2), rng.randf_range(-0.12, 0.12)), Vector3(0, rng.randf() * 90.0, 0)), _vary(leaf.lerp(Color(0.5, 0.9, 0.55), t * 0.18), rng, 0.03))
		if width > 1.2:
			# árbol grande: copa redondeada extra con puntos luminosos (flores de luz)
			b.sphere(h * 0.22, 6, 4, _x(Vector3(0, h * 0.8, 0)), leaf.lightened(0.1))
			for i in 6:
				b.sphere(0.12, 4, 3, _x(Vector3(rng.randf_range(-h, h) * 0.2, h * rng.randf_range(0.55, 0.9), rng.randf_range(-h, h) * 0.2)), _g(Color(0.7, 1.0, 0.8), 0.95))
	var fp := Vector3(maxf(1.6, h * 0.3 * width), h, maxf(1.6, h * 0.3 * width))
	return _finish(b, "tree", fp, Vector3(tr * 2.2, minf(h, 3.0), tr * 2.2), Vector3(0, minf(h, 3.0) * 0.5, 0))


static func _bush(rng: RandomNumberGenerator, pal: Dictionary) -> Dictionary:
	var b := MeshBuilder.new()
	var leaf: Color = pal.get("g_alt", Color(0.3, 0.5, 0.25))
	leaf = leaf.darkened(0.1)
	for i in 5:
		b.sphere(rng.randf_range(0.45, 0.8), 6, 4, _x(Vector3(rng.randf_range(-0.7, 0.7), rng.randf_range(0.3, 0.6), rng.randf_range(-0.6, 0.6))), _vary(leaf, rng, 0.05))
	for i in 3:
		b.sphere(0.07, 4, 3, _x(Vector3(rng.randf_range(-0.9, 0.9), rng.randf_range(0.5, 0.9), rng.randf_range(-0.7, 0.7))), _g(Color(0.95, 0.5, 0.65), 0.6))
	return _finish(b, "bush", Vector3(2.4, 1.2, 2.2), Vector3(1.4, 0.7, 1.3), Vector3(0, 0.35, 0))


static func _stump(rng: RandomNumberGenerator, pal: Dictionary) -> Dictionary:
	var b := MeshBuilder.new()
	var bark: Color = pal.get("wood", Color(0.4, 0.27, 0.15))
	b.cylinder(0.75, 0.95, 1.1, 8, _x(Vector3(0, 0.55, 0)), bark)
	b.cylinder(0.7, 0.7, 0.05, 8, _x(Vector3(0, 1.1, 0)), bark.lightened(0.25))
	for i in 4:
		var a := TAU * float(i) / 4.0
		b.cylinder(0.1, 0.25, 1.0, 4, _x(Vector3(cos(a) * 0.9, 0.2, sin(a) * 0.9), Vector3(sin(a) * 60.0, 0, -cos(a) * 60.0)), bark.darkened(0.1))
	b.sphere(0.35, 5, 4, _x(Vector3(0.3, 1.2, 0.1)), Color(0.28, 0.5, 0.25))
	return _finish(b, "stump", Vector3(2.4, 1.3, 2.4), Vector3(1.6, 1.1, 1.6), Vector3(0, 0.55, 0))


static func _log(rng: RandomNumberGenerator, pal: Dictionary) -> Dictionary:
	var b := MeshBuilder.new()
	var bark: Color = pal.get("wood", Color(0.4, 0.27, 0.15))
	b.cylinder(0.45, 0.5, 3.6, 8, _x(Vector3(0, 0.5, 0), Vector3(0, 0, 90)), bark)
	b.cylinder(0.4, 0.4, 0.06, 8, _x(Vector3(1.8, 0.5, 0), Vector3(0, 0, 90)), bark.lightened(0.3))
	for i in 3:
		b.sphere(0.2, 4, 3, _x(Vector3(-1.0 + i * 0.9, 0.95, rng.randf_range(-0.1, 0.1))), Color(0.3, 0.52, 0.28))
	return _finish(b, "log", Vector3(3.8, 1.2, 1.3), Vector3(3.6, 0.9, 1.0), Vector3(0, 0.45, 0))


static func _mushrooms(rng: RandomNumberGenerator, pal: Dictionary) -> Dictionary:
	var b := MeshBuilder.new()
	var glow: Color = pal.get("accent", Color(0.55, 1.0, 0.65))
	for i in 5:
		var h := rng.randf_range(0.5, 1.5)
		var r := h * rng.randf_range(0.5, 0.8)
		var p := Vector3(rng.randf_range(-0.9, 0.9), 0, rng.randf_range(-0.9, 0.9))
		b.cylinder(0.09, 0.13, h, 5, _x(p + Vector3(0, h * 0.5, 0)), Color(0.88, 0.85, 0.78))
		b.frustum(Vector2(r * 2.0, r * 2.0), Vector2(r * 0.5, r * 0.5), r * 0.7, _x(p + Vector3(0, h + r * 0.2, 0)), _g(glow.lerp(Color(0.5, 0.6, 1.0), rng.randf() * 0.5), 0.75))
	return _finish(b, "mushrooms", Vector3(2.4, 1.8, 2.4), Vector3(0.5, 0.8, 0.5), Vector3(0, 0.4, 0))


static func _rock(rng: RandomNumberGenerator, pal: Dictionary, red: bool) -> Dictionary:
	var b := MeshBuilder.new()
	var base: Color = Color(0.55, 0.33, 0.22) if red else Color(0.42, 0.44, 0.42)
	if not red:
		base = base.lerp(pal.get("g_main", base), 0.15)
	var big := 1.0 + rng.randf() * (0.9 if red else 0.6)
	for i in 4:
		var s := Vector3(rng.randf_range(1.0, 2.0), rng.randf_range(0.9, 1.8), rng.randf_range(1.0, 2.0)) * big
		var p := Vector3(rng.randf_range(-0.9, 0.9), s.y * 0.38 + 0.05, rng.randf_range(-0.9, 0.9)) * (1.0 if i > 0 else 0.0) * big
		b.box(s, _x(p, Vector3(rng.randf_range(-12, 12), rng.randf_range(0, 360), rng.randf_range(-12, 12))), _vary(base, rng, 0.04).lightened(0.04 * float(i)))
	if red:
		# estratos (bandas de roca sedimentaria)
		for i in 3:
			b.box(Vector3(3.6, 0.12, 3.2) * big * 0.6, _x(Vector3(0, 0.5 + i * 0.5, 0), Vector3(0, 20, 0)), base.darkened(0.22))
	else:
		b.sphere(0.35 * big, 5, 4, _x(Vector3(0.5, 1.5 * big, 0.2)), Color(0.28, 0.46, 0.26))   # musgo
	var fp := Vector3(3.6, 2.4, 3.6) * big
	return _finish(b, "rock", fp, Vector3(fp.x * 0.62, fp.y * 0.8, fp.z * 0.62), Vector3(0, fp.y * 0.4, 0))


# ====================================================================== INDUSTRIAL
static func _pipes(rng: RandomNumberGenerator, pal: Dictionary) -> Dictionary:
	var b := MeshBuilder.new()
	var metal: Color = pal.get("metal", Color(0.5, 0.52, 0.56))
	var rust := Color(0.5, 0.3, 0.18)
	for i in 3:
		b.cylinder(0.32, 0.32, 4.4, 8, _x(Vector3(0, 0.45 + i * 0.1, -0.7 + i * 0.7), Vector3(0, 0, 90)), metal if i != 1 else rust)
		for k in 4:
			b.cylinder(0.38, 0.38, 0.14, 8, _x(Vector3(-1.6 + k * 1.07, 0.45 + i * 0.1, -0.7 + i * 0.7), Vector3(0, 0, 90)), metal.darkened(0.3))
	for sx in [-1.6, 1.6]:
		b.box(Vector3(0.2, 0.5, 2.6), _x(Vector3(sx, 0.25, 0)), Color(0.3, 0.3, 0.34))
	b.cylinder(0.1, 0.1, 1.4, 6, _x(Vector3(0.4, 1.1, 0.6)), Color(0.8, 0.2, 0.15))
	b.sphere(0.16, 5, 4, _x(Vector3(0.4, 1.85, 0.6)), Color(0.85, 0.2, 0.15))
	return _finish(b, "pipes", Vector3(4.6, 1.6, 2.8), Vector3(4.4, 1.1, 2.4), Vector3(0, 0.55, 0))


static func _machine(rng: RandomNumberGenerator, pal: Dictionary) -> Dictionary:
	var b := MeshBuilder.new()
	var paints: Array = pal.get("paints", [Color(0.85, 0.5, 0.1)])
	var body: Color = paints[rng.randi() % paints.size()]
	b.box(Vector3(3.2, 2.0, 2.2), _x(Vector3(0, 1.0, 0)), body)
	b.box(Vector3(3.3, 0.18, 2.3), _x(Vector3(0, 2.05, 0)), body.darkened(0.3))
	b.box(Vector3(1.4, 1.1, 0.1), _x(Vector3(-0.5, 1.2, 1.12)), Color(0.12, 0.13, 0.16))
	b.box(Vector3(1.0, 0.7, 0.05), _x(Vector3(-0.5, 1.3, 1.18)), _g(Color(0.4, 1.0, 0.6), 0.7))
	b.cylinder(0.35, 0.35, 1.8, 8, _x(Vector3(1.0, 2.9, -0.4)), Color(0.35, 0.36, 0.4))
	b.cylinder(0.45, 0.35, 0.3, 8, _x(Vector3(1.0, 3.9, -0.4)), Color(0.3, 0.3, 0.34))
	b.sphere(0.14, 5, 4, _x(Vector3(-1.4, 2.3, 0.9)), _g(Color(1.0, 0.25, 0.15), 1.0))
	for sx in [-1.2, 0.0, 1.2]:
		b.box(Vector3(0.5, 0.12, 0.06), _x(Vector3(sx, 0.4, 1.13)), Color(0.15, 0.16, 0.18))
	return _finish(b, "machine", Vector3(3.4, 4.0, 2.4), Vector3(3.2, 2.2, 2.2), Vector3(0, 1.1, 0))


static func _pylon(rng: RandomNumberGenerator, pal: Dictionary) -> Dictionary:
	var b := MeshBuilder.new()
	var m: Color = pal.get("metal", Color(0.5, 0.52, 0.56)).darkened(0.1)
	var h := 6.5
	for sx in [-0.5, 0.5]:
		for sz in [-0.5, 0.5]:
			b.box(Vector3(0.12, h, 0.12), _x(Vector3(sx * 0.9, h * 0.5, sz * 0.9), Vector3(sz * 3.0, 0, -sx * 3.0)), m)
	for k in 4:
		var y := 1.0 + k * 1.5
		b.box(Vector3(1.0, 0.07, 0.07), _x(Vector3(0, y, 0.45), Vector3(0, 0, 18)), m.darkened(0.1))
		b.box(Vector3(1.0, 0.07, 0.07), _x(Vector3(0, y, -0.45), Vector3(0, 0, -18)), m.darkened(0.1))
	b.box(Vector3(2.4, 0.1, 0.1), _x(Vector3(0, h - 0.4, 0)), m)
	for sx in [-1.1, 1.1]:
		b.cylinder(0.16, 0.16, 0.5, 6, _x(Vector3(sx, h - 0.7, 0)), Color(0.82, 0.82, 0.78))
	b.sphere(0.18, 5, 4, _x(Vector3(0, h + 0.1, 0)), _g(Color(1.0, 0.3, 0.15), 1.0))
	return _finish(b, "pylon", Vector3(2.4, h, 2.4), Vector3(1.4, 4.0, 1.4), Vector3(0, 2.0, 0))


# ====================================================================== DESIERTO
static func _cactus(rng: RandomNumberGenerator, pal: Dictionary) -> Dictionary:
	var b := MeshBuilder.new()
	var g := Color(0.34, 0.52, 0.3)
	var h := rng.randf_range(2.2, 3.4)
	b.cylinder(0.3, 0.38, h, 7, _x(Vector3(0, h * 0.5, 0)), g)
	b.sphere(0.3, 6, 4, _x(Vector3(0, h, 0)), g.lightened(0.05))
	for side in [-1.0, 1.0]:
		if rng.randf() < 0.8:
			var ah := rng.randf_range(0.8, 1.3)
			var ay := h * rng.randf_range(0.4, 0.65)
			b.cylinder(0.17, 0.2, 0.7, 6, _x(Vector3(side * 0.55, ay, 0), Vector3(0, 0, 90)), g)
			b.cylinder(0.15, 0.17, ah, 6, _x(Vector3(side * 0.85, ay + ah * 0.5, 0)), g)
			b.sphere(0.16, 5, 4, _x(Vector3(side * 0.85, ay + ah, 0)), g.lightened(0.05))
	b.sphere(0.1, 4, 3, _x(Vector3(0.1, h + 0.25, 0.1)), _g(Color(1.0, 0.45, 0.6), 0.5))
	return _finish(b, "cactus", Vector3(2.0, h + 0.4, 2.0), Vector3(0.7, h, 0.7), Vector3(0, h * 0.5, 0))


static func _ruin_pillar(rng: RandomNumberGenerator, pal: Dictionary) -> Dictionary:
	var b := MeshBuilder.new()
	var st: Color = pal.get("marble", Color(0.9, 0.82, 0.66)).darkened(0.12)
	var h := rng.randf_range(2.6, 4.6)
	b.box(Vector3(1.8, 0.5, 1.8), _x(Vector3(0, 0.15, 0), Vector3(0, 0, rng.randf_range(-6, 6))), st.darkened(0.1))
	b.cylinder(0.62, 0.72, h, 8, _x(Vector3(0.05, h * 0.5 + 0.2, 0), Vector3(rng.randf_range(-4, 4), 0, rng.randf_range(-4, 4))), st)
	for k in 3:
		b.cylinder(0.66, 0.66, 0.08, 8, _x(Vector3(0.05, 0.6 + k * h * 0.3, 0)), st.darkened(0.2))
	# fragmento caído
	b.cylinder(0.55, 0.62, 1.4, 8, _x(Vector3(1.5, 0.55, 0.8), Vector3(0, 20, 80)), st.darkened(0.05))
	return _finish(b, "ruin_pillar", Vector3(3.2, h + 0.4, 2.4), Vector3(1.5, h, 1.5), Vector3(0, h * 0.5, 0))


static func _archive_stack(rng: RandomNumberGenerator, pal: Dictionary) -> Dictionary:
	var b := MeshBuilder.new()
	# pila de gigantescos expedientes semienterrados
	var cols := [Color(0.82, 0.74, 0.55), Color(0.72, 0.62, 0.42), Color(0.6, 0.5, 0.32), Color(0.88, 0.8, 0.62)]
	var y := 0.0
	for i in 5:
		var s := Vector3(rng.randf_range(2.2, 3.2), rng.randf_range(0.28, 0.45), rng.randf_range(1.6, 2.4))
		var c: Color = cols[rng.randi() % cols.size()]
		b.box(s, _x(Vector3(rng.randf_range(-0.2, 0.2), y + s.y * 0.5, rng.randf_range(-0.2, 0.2)), Vector3(0, rng.randf_range(-25, 25), rng.randf_range(-3, 3))), c)
		b.box(Vector3(s.x * 0.96, s.y * 0.6, 0.04), _x(Vector3(0, y + s.y * 0.5, s.z * 0.5 + 0.02)), Color(0.95, 0.93, 0.85))
		y += s.y
	b.box(Vector3(0.5, 0.06, 0.4), _x(Vector3(0.6, y + 0.04, 0.2), Vector3(0, 20, 0)), Color(0.75, 0.15, 0.15))   # sello
	return _finish(b, "archive_stack", Vector3(3.4, y + 0.2, 2.8), Vector3(3.0, y, 2.2), Vector3(0, y * 0.5, 0))


static func _bones(rng: RandomNumberGenerator, pal: Dictionary) -> Dictionary:
	var b := MeshBuilder.new()
	var bn := Color(0.9, 0.87, 0.78)
	for i in 6:
		b.cylinder(0.07, 0.07, 1.6, 5, _x(Vector3(0, 0.3 + i * 0.015, 0) + Vector3(0, 0, -0.8 + i * 0.32), Vector3(0, 0, 90) + Vector3(0, 0, 0), Vector3(1, 1, 1)), bn)
	for i in 6:
		var a := rng.randf_range(0.6, 2.5)
		b.cylinder(0.08, 0.08, 1.4, 5, _x(Vector3(0, 0.55, -0.8 + i * 0.32), Vector3(0, 0, 90 - a * 25.0)), bn.darkened(0.05))
	b.sphere(0.4, 6, 4, _x(Vector3(1.9, 0.4, 0)), bn)
	return _finish(b, "bones", Vector3(3.6, 1.0, 2.2), Vector3(0.9, 0.7, 0.9), Vector3(1.9, 0.35, 0))


static func _dead_tree(rng: RandomNumberGenerator, pal: Dictionary) -> Dictionary:
	var b := MeshBuilder.new()
	var bark := Color(0.38, 0.3, 0.24)
	b.cylinder(0.15, 0.3, 3.4, 6, _x(Vector3(0, 1.7, 0), Vector3(0, 0, rng.randf_range(-6, 6))), bark)
	for i in 4:
		var y := 1.8 + i * 0.5
		var s := 1.0 if i % 2 == 0 else -1.0
		b.cylinder(0.04, 0.12, 1.3, 5, _x(Vector3(s * 0.55, y + 0.3, rng.randf_range(-0.3, 0.3)), Vector3(0, 0, -s * 55.0)), bark.darkened(0.08))
	return _finish(b, "dead_tree", Vector3(2.4, 3.6, 2.4), Vector3(0.6, 3.0, 0.6), Vector3(0, 1.5, 0))


static func _buried_arch(rng: RandomNumberGenerator, pal: Dictionary) -> Dictionary:
	var b := MeshBuilder.new()
	var st: Color = pal.get("marble", Color(0.9, 0.82, 0.66)).darkened(0.1)
	b.box(Vector3(1.0, 3.6, 1.2), _x(Vector3(-1.8, 1.2, 0), Vector3(0, 0, -4)), st)
	b.box(Vector3(1.0, 2.8, 1.2), _x(Vector3(1.8, 0.8, 0), Vector3(0, 0, 3)), st.darkened(0.04))
	b.box(Vector3(4.6, 0.9, 1.3), _x(Vector3(-0.2, 3.1, 0), Vector3(0, 0, -5)), st.lightened(0.02))
	b.box(Vector3(1.0, 0.7, 1.0), _x(Vector3(0.8, 3.65, 0), Vector3(0, 0, 14)), st.darkened(0.12))
	for i in 4:
		b.box(Vector3(0.9, 0.35, 0.05), _x(Vector3(-0.2 + (i - 1.5) * 1.0, 3.1, 0.67)), st.darkened(0.25))
	return _finish(b, "buried_arch", Vector3(5.0, 4.0, 2.0), Vector3(1.0, 3.4, 1.2), Vector3(-1.8, 1.7, 0))


# ====================================================================== CIUDADELA
static func _crystal(rng: RandomNumberGenerator, pal: Dictionary) -> Dictionary:
	var b := MeshBuilder.new()
	var c: Color = pal["paints"][rng.randi() % 3]
	for i in 5:
		var h := rng.randf_range(1.4, 3.6)
		var w := rng.randf_range(0.3, 0.55)
		var p := Vector3(rng.randf_range(-0.8, 0.8), 0, rng.randf_range(-0.8, 0.8))
		b.frustum(Vector2(w * 2.0, w * 2.0), Vector2(0.05, 0.05), h, _x(p + Vector3(0, h * 0.5, 0), Vector3(rng.randf_range(-12, 12), rng.randf() * 90.0, rng.randf_range(-12, 12))), _g(c.lightened(0.1 + rng.randf() * 0.2), 0.6))
	b.cylinder(1.2, 1.4, 0.3, 7, _x(Vector3(0, 0.15, 0)), Color(0.6, 0.64, 0.78))
	return _finish(b, "crystal", Vector3(2.8, 3.8, 2.8), Vector3(1.6, 2.0, 1.6), Vector3(0, 1.0, 0))


static func _float_pillar(rng: RandomNumberGenerator, pal: Dictionary) -> Dictionary:
	var b := MeshBuilder.new()
	var st: Color = pal.get("marble", Color(0.92, 0.93, 0.98))
	var h := 4.6
	b.cylinder(0.5, 0.58, h, 8, _x(Vector3(0, h * 0.5 + 0.3, 0)), st)
	b.box(Vector3(1.4, 0.3, 1.4), _x(Vector3(0, 0.15, 0)), st.darkened(0.1))
	b.box(Vector3(1.4, 0.3, 1.4), _x(Vector3(0, h + 0.45, 0)), st.darkened(0.05))
	b.sphere(0.4, 6, 5, _x(Vector3(0, h + 1.2, 0)), _g(pal.get("accent", Color(0.5, 0.95, 1.0)), 0.9))
	for i in 3:
		var a := TAU * float(i) / 3.0
		b.box(Vector3(0.3, 0.06, 0.3), _x(Vector3(cos(a) * 0.9, h + 1.2, sin(a) * 0.9), Vector3(0, -rad_to_deg(a), 45)), _g(Color(0.8, 1.0, 1.0), 0.8))
	return _finish(b, "float_pillar", Vector3(1.8, h + 1.6, 1.8), Vector3(1.2, h, 1.2), Vector3(0, h * 0.5, 0))


static func _arch(rng: RandomNumberGenerator, pal: Dictionary) -> Dictionary:
	var b := MeshBuilder.new()
	var st: Color = pal.get("marble", Color(0.92, 0.93, 0.98))
	b.box(Vector3(0.7, 3.8, 0.9), _x(Vector3(-1.5, 1.9, 0)), st)
	b.box(Vector3(0.7, 3.8, 0.9), _x(Vector3(1.5, 1.9, 0)), st)
	b.box(Vector3(3.9, 0.7, 1.0), _x(Vector3(0, 4.05, 0)), st.lightened(0.04))
	b.box(Vector3(2.0, 0.12, 0.12), _x(Vector3(0, 3.55, 0)), _g(pal.get("accent", Color(0.5, 0.95, 1.0)), 0.9))
	return _finish(b, "arch", Vector3(4.2, 4.5, 1.6), Vector3(0.8, 3.8, 0.9), Vector3(-1.5, 1.9, 0))


static func _lantern(rng: RandomNumberGenerator, pal: Dictionary) -> Dictionary:
	var b := MeshBuilder.new()
	var st: Color = pal.get("metal", Color(0.7, 0.75, 0.85))
	b.cylinder(0.12, 0.2, 2.6, 6, _x(Vector3(0, 1.3, 0)), st)
	b.sphere(0.38, 6, 5, _x(Vector3(0, 2.9, 0)), _g(pal.get("accent", Color(0.5, 0.95, 1.0)), 0.95))
	b.cylinder(0.3, 0.45, 0.2, 6, _x(Vector3(0, 0.1, 0)), st.darkened(0.1))
	return _finish(b, "lantern", Vector3(1.0, 3.4, 1.0), Vector3(0.45, 2.4, 0.45), Vector3(0, 1.2, 0))


static func _planter_magic(rng: RandomNumberGenerator, pal: Dictionary) -> Dictionary:
	var b := MeshBuilder.new()
	var st: Color = pal.get("marble", Color(0.92, 0.93, 0.98))
	b.cylinder(1.1, 1.2, 0.7, 8, _x(Vector3(0, 0.35, 0)), st)
	b.cylinder(0.95, 0.95, 0.08, 8, _x(Vector3(0, 0.72, 0)), Color(0.35, 0.28, 0.4))
	for i in 5:
		var a := TAU * float(i) / 5.0
		b.sphere(0.32, 5, 4, _x(Vector3(cos(a) * 0.5, 1.0 + (i % 2) * 0.2, sin(a) * 0.5)), _vary(Color(0.5, 0.78, 0.7), rng, 0.05))
		b.sphere(0.1, 4, 3, _x(Vector3(cos(a) * 0.6, 1.4 + (i % 3) * 0.15, sin(a) * 0.6)), _g(Color(1.0, 0.7, 0.95), 0.9))
	return _finish(b, "planter_magic", Vector3(2.5, 2.0, 2.5), Vector3(2.2, 0.8, 2.2), Vector3(0, 0.4, 0))


# ====================================================================== TRIBUNAL
static func _brazier(rng: RandomNumberGenerator, pal: Dictionary) -> Dictionary:
	var b := MeshBuilder.new()
	var gold: Color = pal.get("metal", Color(0.7, 0.58, 0.25))
	b.cylinder(0.3, 0.5, 0.35, 6, _x(Vector3(0, 0.18, 0)), gold.darkened(0.2))
	b.cylinder(0.12, 0.2, 1.2, 6, _x(Vector3(0, 0.95, 0)), gold)
	b.frustum(Vector2(1.1, 1.1), Vector2(1.5, 1.5), 0.45, _x(Vector3(0, 1.75, 0)), gold)
	b.frustum(Vector2(0.9, 0.9), Vector2(0.15, 0.15), 1.1, _x(Vector3(0, 2.35, 0)), _g(Color(1.0, 0.55, 0.15), 0.95))
	b.frustum(Vector2(0.5, 0.5), Vector2(0.05, 0.05), 1.0, _x(Vector3(0, 2.45, 0)), _g(Color(1.0, 0.9, 0.5), 1.0))
	return _finish(b, "brazier", Vector3(1.8, 3.2, 1.8), Vector3(0.9, 2.0, 0.9), Vector3(0, 1.0, 0))


static func _scale_statue(rng: RandomNumberGenerator, pal: Dictionary) -> Dictionary:
	var b := MeshBuilder.new()
	var st: Color = pal.get("marble", Color(0.7, 0.66, 0.72))
	var gold: Color = pal.get("metal", Color(0.7, 0.58, 0.25))
	b.box(Vector3(2.0, 1.2, 2.0), _x(Vector3(0, 0.6, 0)), st.darkened(0.12))
	b.cylinder(0.3, 0.6, 2.4, 7, _x(Vector3(0, 2.4, 0)), st)
	b.sphere(0.32, 6, 5, _x(Vector3(0, 3.8, 0)), st.lightened(0.05))
	b.box(Vector3(2.4, 0.1, 0.1), _x(Vector3(0, 3.35, 0), Vector3(0, 0, 5)), gold)
	for sx in [-1.2, 1.2]:
		b.cylinder(0.4, 0.4, 0.05, 8, _x(Vector3(sx, 2.8 + (0.1 if sx > 0 else -0.05), 0)), _g(gold, 0.35))
		for k in [-1.0, 1.0]:
			b.box(Vector3(0.03, 0.55, 0.03), _x(Vector3(sx + k * 0.2, 3.05, 0), Vector3(0, 0, -k * 20.0)), gold)
	return _finish(b, "scale_statue", Vector3(2.4, 4.4, 2.4), Vector3(1.8, 3.6, 1.8), Vector3(0, 1.8, 0))


static func _banner(rng: RandomNumberGenerator, pal: Dictionary) -> Dictionary:
	var b := MeshBuilder.new()
	var gold: Color = pal.get("metal", Color(0.7, 0.58, 0.25))
	var red: Color = pal["paints"][0]
	b.cylinder(0.07, 0.07, 4.6, 6, _x(Vector3(0, 2.3, 0)), gold.darkened(0.2))
	b.box(Vector3(1.4, 0.1, 0.1), _x(Vector3(0, 4.45, 0)), gold)
	b.box(Vector3(1.1, 3.0, 0.05), _x(Vector3(0, 2.9, 0.05)), red)
	b.box(Vector3(0.5, 0.5, 0.06), _x(Vector3(0, 3.6, 0.09), Vector3(0, 0, 45)), _g(gold, 0.6))
	b.cylinder(0.35, 0.45, 0.2, 6, _x(Vector3(0, 0.1, 0)), Color(0.25, 0.22, 0.3))
	return _finish(b, "banner", Vector3(1.6, 4.7, 1.6), Vector3(0.5, 4.0, 0.5), Vector3(0, 2.0, 0))


# ====================================================================== COLISIONES DE LA TIENDA
## Colisiones físicas de la tienda, ajustadas a la geometría REAL de cada variante (coordenadas locales de la tienda;
## el frente del mostrador mira a +Z). Cajas [min, max]; los cilindros [centro_xz, radio, y_min, y_max].
## El mostrador es sólido; la zona de atención (frente al mostrador) queda libre. Las cajas bajan hasta y=-0.6 para
## no dejar huecos por debajo en terreno irregular. 'anchor' = punto de uso (accesible, delante del mostrador).
static func shop_collision(kind: String) -> Dictionary:
	var boxes: Array = []
	var cyls: Array = []
	var anchor := Vector3(0, 0, 2.5)
	match kind:
		"truck":
			boxes.append([Vector3(-2.1, -0.6, -1.4), Vector3(2.1, 2.5, 0.8)])           # caja de la furgoneta + bajos
			boxes.append([Vector3(-3.45, -0.6, -1.35), Vector3(-2.1, 1.95, 0.75)])      # cabina
			boxes.append([Vector3(-1.1, -0.6, 0.8), Vector3(1.9, 1.5, 1.5)])            # mostrador con género
			anchor = Vector3(0.4, 0, 2.5)
		"hut":
			boxes.append([Vector3(-1.8, -0.6, -1.6), Vector3(1.8, 2.4, 0.8)])
			boxes.append([Vector3(-1.6, -0.6, 0.8), Vector3(1.6, 1.4, 1.55)])
			anchor = Vector3(0, 0, 2.5)
		"container":
			boxes.append([Vector3(-2.6, -0.6, -1.6), Vector3(2.6, 2.7, 0.8)])
			boxes.append([Vector3(-2.0, -0.6, 0.8), Vector3(2.0, 1.4, 1.55)])
			anchor = Vector3(0, 0, 2.5)
		"tent":
			boxes.append([Vector3(-2.1, -0.6, -1.7), Vector3(2.1, 1.2, 1.7)])           # faldón de la carpa
			boxes.append([Vector3(-1.45, 1.2, -1.2), Vector3(1.45, 2.6, 1.2)])          # cuerpo cónico
			boxes.append([Vector3(-1.4, -0.6, 1.0), Vector3(1.4, 1.1, 2.0)])            # mostrador
			anchor = Vector3(0, 0, 3.0)
		"pavilion":
			cyls.append([Vector2(0, 0), 2.3, -0.6, 0.4])                                # plataforma
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					boxes.append([Vector3(sx * 1.34 - 0.17, 0.0, sz * 1.34 - 0.17), Vector3(sx * 1.34 + 0.17, 3.4, sz * 1.34 + 0.17)])   # columnas
			boxes.append([Vector3(-1.3, 0.0, 0.35), Vector3(1.3, 1.3, 1.25)])           # mostrador
			anchor = Vector3(0, 0, 3.1)
		_:   # booth
			boxes.append([Vector3(-2.15, -0.6, -0.95), Vector3(2.15, 1.4, 0.95)])       # mostrador de mármol
			for sx in [-1.9, 1.9]:
				boxes.append([Vector3(sx - 0.3, -0.6, -0.8), Vector3(sx + 0.3, 3.7, -0.2)])   # columnas
			boxes.append([Vector3(-1.7, 1.25, -1.05), Vector3(1.7, 3.55, -0.85)])       # panel trasero
			anchor = Vector3(0, 0, 2.4)
	return {"boxes": boxes, "cyls": cyls, "anchor": anchor}


static func _shop_body(kind: String) -> StaticBody3D:
	var data := shop_collision(kind)
	var sb := StaticBody3D.new()
	sb.name = "ShopCollider"
	sb.collision_layer = 17          # mundo + bloqueo de cámara, como el resto de estructuras
	sb.collision_mask = 0
	for bx in data["boxes"]:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		var mn: Vector3 = bx[0]
		var mx: Vector3 = bx[1]
		sh.size = mx - mn
		cs.shape = sh
		cs.position = (mn + mx) * 0.5
		sb.add_child(cs)
	for cy in data["cyls"]:
		var cs2 := CollisionShape3D.new()
		var sh2 := CylinderShape3D.new()
		sh2.radius = float(cy[1])
		sh2.height = float(cy[3]) - float(cy[2])
		cs2.shape = sh2
		cs2.position = Vector3((cy[0] as Vector2).x, (float(cy[2]) + float(cy[3])) * 0.5, (cy[0] as Vector2).y)
		sb.add_child(cs2)
	return sb


# ====================================================================== TIENDA / COFRE / PORTAL TEMÁTICOS
## Tienda con identidad por bioma. Mantiene el mismo contrato que PropsFactory.shop_node() (Node3D visual).
static func shop(pal: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "ShopVisual"
	var b := MeshBuilder.new()
	var accent: Color = pal.get("accent", Color(0.6, 1.0, 0.7))
	var wood: Color = pal.get("wood", Color(0.42, 0.26, 0.14))
	var metal: Color = pal.get("metal", Color(0.5, 0.52, 0.56))
	var kind := String(pal.get("shop_kind", "truck"))
	var sign_y := 3.55
	match kind:
		"truck":   # furgoneta-puesto con toldo
			var body := Color(0.78, 0.74, 0.62)
			b.box(Vector3(4.2, 1.9, 2.2), _x(Vector3(0, 1.45, -0.3)), body)
			b.box(Vector3(1.5, 1.4, 2.1), _x(Vector3(-2.7, 1.2, -0.3)), body.darkened(0.12))
			b.box(Vector3(1.3, 0.7, 2.14), _x(Vector3(-2.75, 1.65, -0.3)), _g(Color(0.5, 0.75, 0.9), 0.15))
			b.box(Vector3(4.2, 0.12, 2.3), _x(Vector3(0.0, 2.45, -0.3)), body.darkened(0.25))
			b.box(Vector3(3.0, 1.0, 0.1), _x(Vector3(0.4, 1.7, 0.84)), Color(0.1, 0.12, 0.14))
			b.box(Vector3(3.0, 0.1, 0.8), _x(Vector3(0.4, 1.2, 1.1)), Color(0.8, 0.8, 0.82))
			for i in 7:
				b.box(Vector3(0.44, 0.06, 1.7), _x(Vector3(-1.2 + i * 0.44, 2.7, 1.0), Vector3(-18, 0, 0)), Color(0.85, 0.22, 0.2) if i % 2 == 0 else Color(0.95, 0.95, 0.9))
			for sx in [-2.9, -0.4]:
				b.cylinder(0.4, 0.4, 0.3, 8, _x(Vector3(sx, 0.4, 0.6), Vector3(0, 0, 90)), Color(0.08, 0.08, 0.1))
				b.cylinder(0.4, 0.4, 0.3, 8, _x(Vector3(sx, 0.4, -1.2), Vector3(0, 0, 90)), Color(0.08, 0.08, 0.1))
			for i in 4:
				b.box(Vector3(0.3, 0.3, 0.3), _x(Vector3(-0.3 + i * 0.6, 1.4, 1.1)), _g(Color.from_hsv(0.1 + i * 0.2, 0.7, 0.95), 0.5))
			b.box(Vector3(2.6, 0.5, 0.1), _x(Vector3(0.4, 3.0, 0.9)), _g(accent, 0.9))
			sign_y = 3.35
		"hut":   # cabaña de madera con luces de hada
			b.box(Vector3(3.6, 2.2, 2.4), _x(Vector3(0, 1.1, -0.4)), wood)
			for i in 6:
				b.box(Vector3(0.08, 2.2, 0.06), _x(Vector3(-1.6 + i * 0.64, 1.1, 0.82)), wood.darkened(0.3))
			b.box(Vector3(4.4, 0.3, 3.2), _x(Vector3(0, 2.45, -0.2), Vector3(0, 0, 0)), Color(0.28, 0.4, 0.2))
			b.frustum(Vector2(4.6, 3.4), Vector2(1.0, 0.8), 1.2, _x(Vector3(0, 3.1, -0.2)), Color(0.3, 0.45, 0.22))
			b.box(Vector3(3.0, 0.9, 0.12), _x(Vector3(0, 1.4, 0.86)), Color(0.1, 0.07, 0.05))
			b.box(Vector3(3.2, 0.12, 0.9), _x(Vector3(0, 1.0, 1.1)), wood.lightened(0.15))
			for i in 5:
				b.sphere(0.17, 5, 4, _x(Vector3(-1.2 + i * 0.6, 1.25, 1.1)), _g(Color.from_hsv(0.3 + i * 0.12, 0.6, 1.0), 0.6))
			for i in 8:
				b.sphere(0.08, 4, 3, _x(Vector3(-2.0 + i * 0.57, 2.3 - absf(sin(i * 0.9)) * 0.25, 1.4)), _g(Color(1.0, 0.9, 0.55), 1.0))
			sign_y = 3.5
		"container":   # contenedor abierto reconvertido
			var pc: Color = pal["paints"][1]
			b.box(Vector3(5.2, 2.6, 2.4), _x(Vector3(0, 1.3, -0.4)), pc)
			for i in 12:
				b.box(Vector3(0.1, 2.6, 0.06), _x(Vector3(-2.4 + i * 0.44, 1.3, 0.82)), pc.darkened(0.28))
			b.box(Vector3(4.0, 1.3, 0.1), _x(Vector3(0, 1.6, 0.84)), Color(0.08, 0.08, 0.1))
			b.box(Vector3(4.0, 0.12, 0.9), _x(Vector3(0, 1.0, 1.1)), metal)
			b.box(Vector3(4.4, 0.12, 1.2), _x(Vector3(0, 2.75, 0.9), Vector3(-15, 0, 0)), Color(0.8, 0.5, 0.1))
			for i in 5:
				b.box(Vector3(0.4, 0.4, 0.4), _x(Vector3(-1.6 + i * 0.8, 1.25, 1.1)), _g(Color.from_hsv(0.05 + i * 0.1, 0.8, 0.95), 0.45))
			for sx in [-2.0, 2.0]:
				b.sphere(0.2, 5, 4, _x(Vector3(sx, 3.0, 1.2)), _g(Color(1.0, 0.7, 0.3), 1.0))
			sign_y = 3.45
		"tent":   # carpa de caravana
			var cloth := Color(0.78, 0.35, 0.2)
			b.frustum(Vector2(5.0, 4.0), Vector2(0.4, 0.4), 3.2, _x(Vector3(0, 1.9, 0)), cloth)
			b.frustum(Vector2(5.2, 4.2), Vector2(4.8, 3.8), 0.4, _x(Vector3(0, 0.2, 0)), cloth.darkened(0.3))
			b.box(Vector3(2.8, 0.9, 1.0), _x(Vector3(0, 0.45, 1.5)), wood)
			b.box(Vector3(3.0, 0.1, 1.2), _x(Vector3(0, 0.95, 1.5)), Color(0.85, 0.8, 0.7))
			for i in 4:
				b.box(Vector3(0.4, 0.28, 0.3), _x(Vector3(-1.0 + i * 0.66, 1.15, 1.5)), _g(Color(0.95, 0.9, 0.7), 0.4))
			b.cylinder(0.06, 0.06, 4.4, 5, _x(Vector3(0, 2.3, 0)), wood.darkened(0.2))
			b.sphere(0.24, 5, 4, _x(Vector3(0, 4.5, 0)), _g(accent, 1.0))
			for sx in [-1.9, 1.9]:
				b.sphere(0.2, 5, 4, _x(Vector3(sx, 2.2, 1.9)), _g(Color(1.0, 0.8, 0.4), 1.0))
				b.cylinder(0.05, 0.05, 2.2, 4, _x(Vector3(sx, 1.1, 1.9)), wood)
			sign_y = 4.0
		"pavilion":   # pabellón de cristal flotante
			var st: Color = pal.get("marble", Color(0.92, 0.93, 0.98))
			b.cylinder(2.2, 2.4, 0.4, 8, _x(Vector3(0, 0.2, 0)), st.darkened(0.08))
			for i in 4:
				var a := TAU * (float(i) + 0.5) / 4.0
				b.cylinder(0.12, 0.14, 3.0, 6, _x(Vector3(cos(a) * 1.9, 1.9, sin(a) * 1.9)), st)
			b.frustum(Vector2(4.6, 4.6), Vector2(0.5, 0.5), 1.4, _x(Vector3(0, 4.1, 0), Vector3(0, 45, 0)), _g(accent, 0.28))
			b.box(Vector3(2.6, 0.9, 0.9), _x(Vector3(0, 0.85, 0.8)), st)
			for i in 4:
				b.sphere(0.2, 5, 4, _x(Vector3(-0.9 + i * 0.6, 1.5, 0.8)), _g(Color.from_hsv(0.5 + i * 0.1, 0.6, 1.0), 0.75))
			b.sphere(0.35, 6, 5, _x(Vector3(0, 5.0, 0)), _g(accent, 1.0))
			sign_y = 3.9
		_:   # "booth": despacho de mármol y oro
			var st2: Color = pal.get("platform", Color(0.3, 0.26, 0.38))
			var gold: Color = pal.get("metal", Color(0.7, 0.58, 0.25))
			b.box(Vector3(4.0, 1.2, 1.6), _x(Vector3(0, 0.6, 0)), st2)
			b.box(Vector3(4.3, 0.18, 1.9), _x(Vector3(0, 1.27, 0)), gold)
			for sx in [-1.9, 1.9]:
				b.cylinder(0.28, 0.3, 3.6, 8, _x(Vector3(sx, 1.8, -0.5)), st2.lightened(0.15))
			b.box(Vector3(4.4, 0.5, 1.4), _x(Vector3(0, 3.85, -0.5)), gold.darkened(0.1))
			b.box(Vector3(3.4, 2.3, 0.2), _x(Vector3(0, 2.4, -0.95)), st2.darkened(0.1))
			for i in 4:
				b.box(Vector3(0.45, 0.45, 0.45), _x(Vector3(-1.2 + i * 0.8, 1.6, 0.0)), _g(Color.from_hsv(0.1 + i * 0.12, 0.7, 1.0), 0.5))
			b.box(Vector3(2.4, 0.4, 0.1), _x(Vector3(0, 3.2, 0.1)), _g(accent, 0.9))
			sign_y = 4.4
	Mats.mesh_instance(b.build(), Mats.world_material(), root)
	root.add_child(_shop_body(kind))       # estructura sólida: no se atraviesa (el modelo antes era solo visual)
	var lbl := Label3D.new()
	lbl.text = String(pal.get("shop_name", "TIENDA DEL NOTARIO"))
	lbl.font_size = 56
	lbl.pixel_size = 0.0058
	lbl.outline_size = 12
	lbl.modulate = Color(1, 1, 1)
	lbl.position = Vector3(0, sign_y, 1.0)
	root.add_child(lbl)
	# baliza de luz cálida para reconocer la tienda de lejos
	var lamp := OmniLight3D.new()
	lamp.light_color = accent.lightened(0.2)
	lamp.light_energy = 0.9
	lamp.omni_range = 7.0
	lamp.position = Vector3(0, 3.0, 1.6)
	root.add_child(lamp)
	return root


## Base temática que se coloca debajo del cofre (pedestal): lo integra con el escenario y lo hace visible.
static func chest_base(pal: Dictionary, tint: Color) -> Node3D:
	var root := Node3D.new()
	root.name = "ChestBase"
	var b := MeshBuilder.new()
	var kind := String(pal.get("chest_kind", "slab"))
	var st: Color = pal.get("platform", Color(0.5, 0.5, 0.52))
	match kind:
		"roots":
			for i in 7:
				var a := TAU * float(i) / 7.0
				b.cylinder(0.1, 0.32, 1.9, 5, _x(Vector3(cos(a) * 1.3, 0.1, sin(a) * 1.3), Vector3(sin(a) * 78.0, 0, -cos(a) * 78.0)), Color(0.34, 0.23, 0.13))
			b.cylinder(1.3, 1.5, 0.25, 10, _x(Vector3(0, 0.1, 0)), Color(0.28, 0.42, 0.22))
		"crate":
			b.box(Vector3(2.2, 0.3, 1.8), _x(Vector3(0, 0.15, 0)), Color(0.45, 0.32, 0.2))
			for sx in [-0.8, 0.8]:
				b.box(Vector3(0.3, 0.3, 1.9), _x(Vector3(sx, 0.12, 0)), Color(0.3, 0.2, 0.12))
			b.box(Vector3(2.0, 0.05, 0.3), _x(Vector3(0, 0.32, 0.9)), _g(Color(1.0, 0.75, 0.1), 0.6))
		"sand":
			b.frustum(Vector2(3.2, 3.2), Vector2(2.0, 2.0), 0.35, _x(Vector3(0, 0.17, 0)), Color(0.75, 0.6, 0.38))
			for i in 4:
				b.box(Vector3(0.3, 0.8 + i * 0.1, 0.3), _x(Vector3(cos(i * 1.57 + 0.7) * 1.2, 0.4, sin(i * 1.57 + 0.7) * 1.2), Vector3(0, i * 30.0, 8)), Color(0.72, 0.62, 0.45))
		"crystal":
			b.cylinder(1.3, 1.5, 0.3, 8, _x(Vector3(0, 0.15, 0)), st.lightened(0.1))
			for i in 6:
				var a2 := TAU * float(i) / 6.0
				b.frustum(Vector2(0.3, 0.3), Vector2(0.04, 0.04), 0.9, _x(Vector3(cos(a2) * 1.2, 0.6, sin(a2) * 1.2), Vector3(0, 0, 0)), _g(tint, 0.7))
		"gold":
			b.cylinder(1.3, 1.5, 0.3, 8, _x(Vector3(0, 0.15, 0)), st.darkened(0.1))
			b.cylinder(1.0, 1.1, 0.1, 8, _x(Vector3(0, 0.34, 0)), Color(0.55, 0.12, 0.16))
			for i in 4:
				var a3 := TAU * float(i) / 4.0 + 0.78
				b.cylinder(0.08, 0.1, 0.9, 5, _x(Vector3(cos(a3) * 1.1, 0.55, sin(a3) * 1.1)), _g(Color(1.0, 0.8, 0.3), 0.5))
		_:   # slab de hormigón con luces
			b.box(Vector3(2.4, 0.22, 1.9), _x(Vector3(0, 0.11, 0)), st)
			b.box(Vector3(2.5, 0.06, 2.0), _x(Vector3(0, 0.03, 0)), st.darkened(0.25))
			for sx in [-1.1, 1.1]:
				b.box(Vector3(0.08, 0.06, 0.08), _x(Vector3(sx, 0.25, 0.85)), _g(tint, 1.0))
				b.box(Vector3(0.08, 0.06, 0.08), _x(Vector3(sx, 0.25, -0.85)), _g(tint, 1.0))
	Mats.mesh_instance(b.build(), Mats.world_material(), root)
	return root
