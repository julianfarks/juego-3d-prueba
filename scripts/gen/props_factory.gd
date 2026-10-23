class_name PropsFactory
extends RefCounted
## Escenarios, obstáculos, cofres, portales y tienda: todo generado por código.

const OBSTACLE_KINDS := ["crate", "crate_big", "container", "pillar", "barrier", "ac_unit", "tank", "dumpster",
	"car", "bench", "safe", "counter", "pallets", "statue", "debris", "wall_piece"]


static func _x(pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE) -> Transform3D:
	return MeshBuilder.xf(pos, rot, scl)


static func _g(c: Color, amount := 1.0) -> Color:
	return MeshBuilder.glow(c, amount)


static func _vary(c: Color, rng: RandomNumberGenerator, amt := 0.04) -> Color:
	return Color(clampf(c.r + rng.randf_range(-amt, amt), 0, 1), clampf(c.g + rng.randf_range(-amt, amt), 0, 1), clampf(c.b + rng.randf_range(-amt, amt), 0, 1), c.a)


static func static_body(size: Vector3, center: Vector3, layers := 17) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = layers   # mundo + bloqueo de cámara
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = center
	sb.add_child(cs)
	return sb


# =============================================================================
#  OBSTÁCULOS
# =============================================================================
## Devuelve {"node": StaticBody3D, "size": Vector3(ancho, alto, fondo)}
static func make_obstacle(kind: String, rng: RandomNumberGenerator, pal: Dictionary) -> Dictionary:
	var b := MeshBuilder.new()
	var sz := Vector3(1.6, 1.5, 1.6)
	var wood: Color = pal.get("wood", Color(0.6, 0.4, 0.2))
	var metal: Color = pal.get("metal", Color(0.45, 0.48, 0.52))
	var paints: Array = pal.get("paints", [Color(0.7, 0.2, 0.2), Color(0.2, 0.4, 0.7), Color(0.85, 0.65, 0.15)])
	var marble: Color = pal.get("marble", Color(0.88, 0.87, 0.82))
	match kind:
		"crate":
			sz = Vector3(1.6, 1.5, 1.6)
			var w := _vary(wood, rng)
			b.box(Vector3(1.6, 1.5, 1.6), _x(Vector3(0, 0.75, 0)), w)
			for sx in [-1.0, 1.0]:
				for sz2 in [-1.0, 1.0]:
					b.box(Vector3(0.14, 1.56, 0.14), _x(Vector3(sx * 0.77, 0.75, sz2 * 0.77)), w.darkened(0.35))
			for sz2 in [-1.0, 1.0]:
				b.box(Vector3(1.5, 0.12, 0.05), _x(Vector3(0, 0.75, sz2 * 0.81), Vector3(0, 0, 38)), w.darkened(0.25))
			for sx in [-1.0, 1.0]:
				b.box(Vector3(0.05, 0.12, 1.5), _x(Vector3(sx * 0.81, 0.75, 0), Vector3(38, 0, 0)), w.darkened(0.25))
		"crate_big":
			sz = Vector3(2.4, 2.5, 2.4)
			var w2 := _vary(wood, rng)
			b.box(Vector3(2.4, 1.3, 2.4), _x(Vector3(0, 0.65, 0)), w2)
			b.box(Vector3(2.0, 1.2, 2.0), _x(Vector3(0.1, 1.9, 0.05), Vector3(0, 14, 0)), w2.lightened(0.06))
			for sx in [-1.0, 1.0]:
				for sz2 in [-1.0, 1.0]:
					b.box(Vector3(0.16, 1.34, 0.16), _x(Vector3(sx * 1.16, 0.65, sz2 * 1.16)), w2.darkened(0.35))
			b.box(Vector3(2.0, 0.1, 2.1), _x(Vector3(0.1, 2.52, 0.05), Vector3(0, 14, 0)), w2.darkened(0.2))
		"container":
			sz = Vector3(6.0, 2.7, 2.4)
			var pc: Color = paints[rng.randi() % paints.size()]
			b.box(Vector3(6.0, 2.6, 2.4), _x(Vector3(0, 1.35, 0)), pc)
			for i in 14:
				b.box(Vector3(0.1, 2.6, 0.06), _x(Vector3(-2.8 + i * 0.43, 1.35, 1.2)), pc.darkened(0.25))
				b.box(Vector3(0.1, 2.6, 0.06), _x(Vector3(-2.8 + i * 0.43, 1.35, -1.2)), pc.darkened(0.25))
			b.box(Vector3(6.1, 0.12, 2.5), _x(Vector3(0, 2.68, 0)), pc.darkened(0.4))
			b.box(Vector3(0.1, 2.5, 2.3), _x(Vector3(3.02, 1.35, 0)), pc.darkened(0.3))
			for sy in [0.5, 2.2]:
				b.box(Vector3(0.14, 0.08, 2.2), _x(Vector3(3.08, sy, 0)), STEEL())
			for k in 3:
				b.box(Vector3(0.14, 2.3, 0.07), _x(Vector3(3.08, 1.35, -0.6 + k * 0.6)), STEEL())
		"pillar":
			sz = Vector3(1.4, 5.0, 1.4)
			b.box(Vector3(1.5, 0.4, 1.5), _x(Vector3(0, 0.2, 0)), marble.darkened(0.08))
			b.cylinder(0.55, 0.62, 4.2, 8, _x(Vector3(0, 2.5, 0)), marble)
			b.box(Vector3(1.55, 0.4, 1.55), _x(Vector3(0, 4.8, 0)), marble.darkened(0.05))
			b.cylinder(0.7, 0.55, 0.3, 8, _x(Vector3(0, 4.5, 0)), marble.darkened(0.04))
		"barrier":
			sz = Vector3(3.0, 1.0, 0.9)
			b.frustum(Vector2(3.0, 0.9), Vector2(3.0, 0.38), 1.0, _x(Vector3(0, 0.5, 0)), Color(0.7, 0.7, 0.7))
			for i in 5:
				b.box(Vector3(0.35, 0.05, 0.4), _x(Vector3(-1.2 + i * 0.6, 1.02, 0)), Color(0.95, 0.75, 0.1) if i % 2 == 0 else BLACKC())
		"ac_unit":
			sz = Vector3(2.6, 1.7, 1.8)
			b.box(Vector3(2.6, 1.4, 1.8), _x(Vector3(0, 0.95, 0)), Color(0.72, 0.74, 0.76))
			for sx in [-0.6, 0.6]:
				b.cylinder(0.5, 0.5, 0.08, 10, _x(Vector3(sx, 1.68, 0)), Color(0.15, 0.15, 0.18))
				b.box(Vector3(1.0, 0.04, 0.06), _x(Vector3(sx, 1.73, 0)), STEEL())
				b.box(Vector3(0.06, 0.04, 1.0), _x(Vector3(sx, 1.73, 0)), STEEL())
			for sy in 5:
				b.box(Vector3(2.0, 0.05, 0.05), _x(Vector3(0, 0.55 + sy * 0.18, 0.92)), Color(0.5, 0.52, 0.55))
			for sx in [-1.0, 1.0]:
				b.box(Vector3(0.2, 0.25, 1.6), _x(Vector3(sx * 1.1, 0.12, 0)), Color(0.3, 0.3, 0.33))
			b.cylinder(0.12, 0.12, 1.2, 6, _x(Vector3(1.0, 1.6, 1.1), Vector3(0, 0, 90)), Color(0.8, 0.8, 0.8))
		"tank":
			sz = Vector3(2.6, 4.2, 2.6)
			for sx in [-1.0, 1.0]:
				for sz2 in [-1.0, 1.0]:
					b.box(Vector3(0.18, 2.2, 0.18), _x(Vector3(sx * 0.95, 1.1, sz2 * 0.95)), Color(0.35, 0.28, 0.2))
			b.box(Vector3(2.4, 0.12, 2.4), _x(Vector3(0, 2.2, 0)), Color(0.3, 0.25, 0.18))
			b.cylinder(1.25, 1.25, 1.7, 10, _x(Vector3(0, 3.1, 0)), Color(0.5, 0.36, 0.22))
			b.cylinder(0.05, 1.3, 0.5, 10, _x(Vector3(0, 4.1, 0)), Color(0.38, 0.28, 0.18))
			for k in 3:
				b.cylinder(1.28, 1.28, 0.06, 10, _x(Vector3(0, 2.6 + k * 0.5, 0)), Color(0.25, 0.2, 0.15))
		"dumpster":
			sz = Vector3(2.4, 1.6, 1.4)
			var gc := Color(0.15, 0.4, 0.22)
			b.frustum(Vector2(2.3, 1.2), Vector2(2.4, 1.4), 1.2, _x(Vector3(0, 0.8, 0)), gc)
			b.wedge(Vector3(2.4, 0.3, 1.4), _x(Vector3(0, 1.5, 0)), gc.darkened(0.3))
			for sx in [-1.0, 1.0]:
				b.cylinder(0.12, 0.12, 0.1, 6, _x(Vector3(sx * 0.9, 0.12, 0.5), Vector3(0, 0, 90)), BLACKC())
		"car":
			sz = Vector3(4.2, 1.6, 1.9)
			var car_c: Color = paints[rng.randi() % paints.size()]
			b.frustum(Vector2(4.2, 1.9), Vector2(4.0, 1.8), 0.7, _x(Vector3(0, 0.7, 0)), car_c)
			b.frustum(Vector2(2.3, 1.7), Vector2(1.6, 1.5), 0.6, _x(Vector3(-0.2, 1.3, 0)), car_c.lightened(0.05))
			b.frustum(Vector2(2.1, 1.74), Vector2(1.4, 1.54), 0.4, _x(Vector3(-0.2, 1.33, 0)), _g(Color(0.5, 0.75, 0.95), 0.15))
			for sx in [-1.3, 1.3]:
				for sz2 in [-0.95, 0.95]:
					b.cylinder(0.4, 0.4, 0.26, 8, _x(Vector3(sx, 0.4, sz2), Vector3(90, 0, 0)), BLACKC())
					b.cylinder(0.2, 0.2, 0.28, 6, _x(Vector3(sx, 0.4, sz2), Vector3(90, 0, 0)), Color(0.7, 0.7, 0.72))
			for sz2 in [-0.6, 0.6]:
				b.box(Vector3(0.06, 0.18, 0.3), _x(Vector3(2.1, 0.75, sz2)), _g(Color(1, 0.95, 0.6), 0.9))
				b.box(Vector3(0.06, 0.16, 0.3), _x(Vector3(-2.1, 0.8, sz2)), _g(Color(1, 0.1, 0.1), 0.8))
		"bench":
			sz = Vector3(2.4, 0.95, 0.8)
			b.box(Vector3(2.4, 0.1, 0.6), _x(Vector3(0, 0.5, 0)), wood)
			b.box(Vector3(2.4, 0.5, 0.08), _x(Vector3(0, 0.78, 0.3), Vector3(-8, 0, 0)), wood.darkened(0.1))
			for sx in [-1.0, 1.0]:
				b.box(Vector3(0.1, 0.5, 0.6), _x(Vector3(sx * 1.05, 0.25, 0)), metal)
		"safe":
			sz = Vector3(2.0, 2.3, 1.8)
			b.box(Vector3(2.0, 2.2, 1.8), _x(Vector3(0, 1.2, 0)), Color(0.28, 0.3, 0.34))
			b.box(Vector3(1.6, 1.8, 0.1), _x(Vector3(0, 1.2, -0.92)), Color(0.38, 0.4, 0.45))
			b.cylinder(0.32, 0.32, 0.1, 10, _x(Vector3(0, 1.25, -1.0), Vector3(90, 0, 0)), _g(GOLD(), 0.5))
			for k in 3:
				b.box(Vector3(0.8, 0.07, 0.07), _x(Vector3(0, 1.25, -1.07), Vector3(0, 0, k * 60.0)), _g(GOLD(), 0.5))
			for sy in [0.6, 1.8]:
				b.box(Vector3(0.12, 0.2, 0.12), _x(Vector3(-0.85, sy, -0.98)), STEEL())
		"counter":
			sz = Vector3(5.0, 1.3, 1.2)
			b.box(Vector3(5.0, 1.1, 1.1), _x(Vector3(0, 0.55, 0)), wood.darkened(0.15))
			b.box(Vector3(5.2, 0.14, 1.3), _x(Vector3(0, 1.17, 0)), marble)
			for i in 6:
				b.box(Vector3(0.7, 0.8, 0.04), _x(Vector3(-2.1 + i * 0.84, 0.55, -0.57)), wood.lightened(0.05))
			b.box(Vector3(0.6, 0.35, 0.5), _x(Vector3(1.5, 1.45, 0.1)), Color(0.2, 0.2, 0.24))
		"pallets":
			sz = Vector3(1.9, 1.7, 1.9)
			for k in 3:
				b.box(Vector3(1.8, 0.14, 1.8), _x(Vector3(0, 0.07 + k * 0.58, 0)), wood.darkened(0.1))
				b.box(Vector3(1.6, 0.4, 1.6), _x(Vector3(0, 0.34 + k * 0.58, 0), Vector3(0, k * 17.0, 0)), paints[(k + rng.randi()) % paints.size()])
		"statue":
			sz = Vector3(1.8, 4.4, 1.8)
			b.box(Vector3(1.7, 1.7, 1.7), _x(Vector3(0, 0.85, 0)), marble.darkened(0.06))
			b.box(Vector3(1.9, 0.2, 1.9), _x(Vector3(0, 0.1, 0)), marble.darkened(0.15))
			b.cylinder(0.25, 0.55, 1.5, 7, _x(Vector3(0, 2.4, 0)), Color(0.85, 0.85, 0.8))
			b.sphere(0.28, 6, 5, _x(Vector3(0, 3.35, 0)), Color(0.9, 0.9, 0.85))
			b.box(Vector3(0.9, 0.08, 0.08), _x(Vector3(0.35, 3.1, 0), Vector3(0, 0, 8)), _g(GOLD(), 0.5))
			for sx in [-0.28, 0.98]:
				b.cylinder(0.22, 0.22, 0.04, 8, _x(Vector3(sx, 2.78, 0)), _g(GOLD(), 0.5))
			b.box(Vector3(0.06, 0.8, 0.06), _x(Vector3(-0.45, 2.7, -0.05)), STEEL())
		"debris":
			sz = Vector3(2.8, 1.2, 2.8)
			for i in 7:
				var s := Vector3(rng.randf_range(0.5, 1.2), rng.randf_range(0.3, 0.7), rng.randf_range(0.5, 1.2))
				b.box(s, _x(Vector3(rng.randf_range(-0.9, 0.9), s.y * 0.5 + (i % 3) * 0.25, rng.randf_range(-0.9, 0.9)),
					Vector3(rng.randf_range(-12, 12), rng.randf_range(0, 90), rng.randf_range(-12, 12))), _vary(Color(0.5, 0.48, 0.45), rng, 0.08))
			for i in 3:
				b.cylinder(0.02, 0.02, 1.1, 4, _x(Vector3(rng.randf_range(-0.8, 0.8), 1.0, rng.randf_range(-0.8, 0.8)), Vector3(rng.randf_range(-20, 20), 0, rng.randf_range(-20, 20))), Color(0.5, 0.25, 0.15))
		"wall_piece":
			sz = Vector3(3.6, 2.5, 0.7)
			var bc := Color(0.55, 0.3, 0.25)
			b.box(Vector3(3.6, 1.8, 0.6), _x(Vector3(0, 0.9, 0)), bc)
			b.box(Vector3(1.8, 0.7, 0.6), _x(Vector3(-0.9, 2.15, 0)), bc.darkened(0.08))
			b.box(Vector3(0.9, 0.4, 0.6), _x(Vector3(1.0, 2.0, 0)), bc.darkened(0.12))
			for i in 4:
				b.box(Vector3(3.4, 0.05, 0.62), _x(Vector3(0, 0.3 + i * 0.45, 0)), bc.darkened(0.3))
		_:
			b.box(Vector3(1.5, 1.5, 1.5), _x(Vector3(0, 0.75, 0)), wood)
	var body := static_body(sz, Vector3(0, sz.y * 0.5, 0))
	body.name = "Obstacle_" + kind
	Mats.mesh_instance(b.build(), Mats.world_material(), body)
	return {"node": body, "size": sz}


static func STEEL() -> Color:
	return Color(0.5, 0.53, 0.58)


static func BLACKC() -> Color:
	return Color(0.08, 0.08, 0.1)


static func GOLD() -> Color:
	return Color(1.0, 0.76, 0.2)


## Plataforma elevada con rampas en dos lados (desnivel transitable).
static func make_platform(size_x: float, size_z: float, height: float, pal: Dictionary, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.name = "Platform"
	var top: Color = pal.get("platform", Color(0.55, 0.55, 0.58))
	var b := MeshBuilder.new()
	b.box(Vector3(size_x, height, size_z), _x(Vector3(0, height * 0.5, 0)), top)
	b.box(Vector3(size_x + 0.1, 0.1, size_z + 0.1), _x(Vector3(0, height - 0.05, 0)), top.lightened(0.12))
	b.box(Vector3(size_x + 0.2, 0.12, size_z + 0.2), _x(Vector3(0, 0.06, 0)), top.darkened(0.3))
	for i in 6:
		var px := -size_x * 0.5 + (i + 0.5) * size_x / 6.0
		b.box(Vector3(0.12, 0.05, size_z - 0.3), _x(Vector3(px, height + 0.01, 0)), _g(Color(1.0, 0.8, 0.2), 0.12) if i % 2 == 0 else top.darkened(0.1))
	var body := static_body(Vector3(size_x, height, size_z), Vector3(0, height * 0.5, 0))
	Mats.mesh_instance(b.build(), Mats.world_material(), body)
	root.add_child(body)
	# rampas (+Z y -Z)
	var ramp_len := height / tan(deg_to_rad(16.0))
	for dirz in [-1.0, 1.0]:
		var rb := MeshBuilder.new()
		rb.wedge(Vector3(size_x * 0.5, height, ramp_len), _x(Vector3.ZERO), top.darkened(0.08))
		var rbody := StaticBody3D.new()
		rbody.collision_layer = 17
		rbody.collision_mask = 0
		var cs := CollisionShape3D.new()
		var cv := ConvexPolygonShape3D.new()
		var hx := size_x * 0.25
		var hy := height * 0.5
		var hz := ramp_len * 0.5
		cv.points = PackedVector3Array([
			Vector3(-hx, -hy, -hz), Vector3(-hx, -hy, hz), Vector3(-hx, hy, -hz),
			Vector3(hx, -hy, -hz), Vector3(hx, -hy, hz), Vector3(hx, hy, -hz)])
		cs.shape = cv
		rbody.add_child(cs)
		Mats.mesh_instance(rb.build(), Mats.world_material(), rbody)
		# wedge: pendiente va de (y=-h,z=+h) a (y=+h,z=-h): lado alto en -z. Para dirz=-1 (rampa hacia -Z) el alto debe tocar la plataforma (+Z)
		rbody.position = Vector3(0, height * 0.5, dirz * (size_z * 0.5 + ramp_len * 0.5))
		rbody.rotation_degrees.y = 180.0 if dirz < 0.0 else 0.0
		root.add_child(rbody)
	root.set_meta("footprint", Vector2(size_x, size_z + ramp_len * 2.0))
	root.set_meta("height", height)
	return root


# =============================================================================
#  INTERACTUABLES
# =============================================================================
static func chest_node(tint: Color) -> Dictionary:
	var root := Node3D.new()
	root.name = "ChestVisual"
	var base := MeshBuilder.new()
	var wood := Color(0.45, 0.25, 0.12)
	base.box(Vector3(1.3, 0.6, 0.85), _x(Vector3(0, 0.3, 0)), wood)
	for sx in [-0.5, 0.5]:
		base.box(Vector3(0.12, 0.64, 0.9), _x(Vector3(sx, 0.3, 0)), _g(tint, 0.35))
	base.box(Vector3(0.2, 0.2, 0.06), _x(Vector3(0, 0.5, -0.45)), _g(tint, 0.8))
	base.box(Vector3(1.34, 0.06, 0.9), _x(Vector3(0, 0.02, 0)), wood.darkened(0.4))
	Mats.mesh_instance(base.build(), Mats.world_material(), root)
	var lid := Node3D.new()
	lid.name = "Lid"
	lid.position = Vector3(0, 0.6, 0.42)
	root.add_child(lid)
	var lb := MeshBuilder.new()
	lb.frustum(Vector2(1.3, 0.85), Vector2(1.3, 0.5), 0.3, _x(Vector3(0, 0.15, -0.42)), wood.lightened(0.05))
	for sx in [-0.5, 0.5]:
		lb.frustum(Vector2(0.12, 0.88), Vector2(0.12, 0.52), 0.32, _x(Vector3(sx, 0.15, -0.42)), _g(tint, 0.35))
	lb.sphere(0.1, 5, 4, _x(Vector3(0, 0.32, -0.42)), _g(tint, 1.0))
	Mats.mesh_instance(lb.build(), Mats.world_material(), lid)
	return {"root": root, "lid": lid}


static func coin_mesh() -> ArrayMesh:
	var b := MeshBuilder.new()
	b.cylinder(0.2, 0.2, 0.05, 8, _x(Vector3.ZERO, Vector3(90, 0, 0)), _g(GOLD(), 0.55))
	b.cylinder(0.13, 0.13, 0.065, 8, _x(Vector3.ZERO, Vector3(90, 0, 0)), _g(Color(1.0, 0.9, 0.45), 0.7))
	return b.build()


static func portal_node() -> Dictionary:
	var root := Node3D.new()
	root.name = "PortalVisual"
	var b := MeshBuilder.new()
	b.cylinder(1.9, 2.1, 0.3, 12, _x(Vector3(0, 0.15, 0)), Color(0.28, 0.3, 0.38))
	b.cylinder(1.7, 1.8, 0.1, 12, _x(Vector3(0, 0.33, 0)), _g(Color(0.5, 0.3, 0.9), 0.4))
	var n := 14
	for i in n:
		var a := TAU * float(i) / n
		var pos := Vector3(cos(a) * 1.7, 2.1 + sin(a) * 1.75, 0)
		b.box(Vector3(0.55, 0.55, 0.5), _x(pos, Vector3(0, 0, rad_to_deg(a))), Color(0.34, 0.36, 0.45) if i % 2 == 0 else Color(0.28, 0.3, 0.38))
		if i % 2 == 0:
			b.box(Vector3(0.12, 0.2, 0.52), _x(pos, Vector3(0, 0, rad_to_deg(a))), _g(Color(0.7, 0.45, 1.0), 1.0))
	Mats.mesh_instance(b.build(), Mats.world_material(), root)
	# disco interior (swirl)
	var swirl := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.45
	cm.bottom_radius = 1.45
	cm.height = 0.02
	cm.radial_segments = 20
	swirl.mesh = cm
	swirl.material_override = Mats.fx_material(Color(0.55, 0.3, 1.0, 0.65), true)
	swirl.position = Vector3(0, 2.1, 0)
	swirl.rotation_degrees.x = 90
	swirl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(swirl)
	var swirl2 := MeshInstance3D.new()
	var cm2 := CylinderMesh.new()
	cm2.top_radius = 1.0
	cm2.bottom_radius = 1.0
	cm2.height = 0.02
	cm2.radial_segments = 6
	swirl2.mesh = cm2
	swirl2.material_override = Mats.fx_material(Color(0.9, 0.7, 1.0, 0.5), true)
	swirl2.position = Vector3(0, 2.1, 0.02)
	swirl2.rotation_degrees.x = 90
	swirl2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(swirl2)
	var light := OmniLight3D.new()
	light.light_color = Color(0.65, 0.4, 1.0)
	light.light_energy = 1.2
	light.omni_range = 7.0
	light.position = Vector3(0, 2.0, 0.5)
	root.add_child(light)
	return {"root": root, "swirl": swirl, "swirl2": swirl2, "light": light}


static func shop_node() -> Node3D:
	var root := Node3D.new()
	root.name = "ShopVisual"
	var b := MeshBuilder.new()
	var wood := Color(0.42, 0.26, 0.14)
	b.box(Vector3(3.2, 1.1, 1.2), _x(Vector3(0, 0.55, 0)), wood)
	b.box(Vector3(3.3, 0.12, 1.3), _x(Vector3(0, 1.16, 0)), Color(0.85, 0.82, 0.75))
	b.box(Vector3(3.2, 2.8, 0.25), _x(Vector3(0, 1.4, 0.8)), wood.darkened(0.2))
	for sy in [1.3, 2.0, 2.7]:
		b.box(Vector3(3.0, 0.07, 0.5), _x(Vector3(0, sy, 0.6)), wood.lightened(0.1))
		var rng := RandomNumberGenerator.new()
		rng.seed = int(sy * 100)
		for i in 5:
			var c := Color.from_hsv(rng.randf(), 0.7, 0.95)
			if i % 2 == 0:
				b.box(Vector3(0.28, 0.3, 0.28), _x(Vector3(-1.2 + i * 0.6, sy + 0.19, 0.6)), _g(c, 0.5))
			else:
				b.sphere(0.16, 5, 4, _x(Vector3(-1.2 + i * 0.6, sy + 0.18, 0.6)), _g(c, 0.6))
	# toldo a rayas
	for i in 8:
		var c2: Color = Color(0.85, 0.2, 0.2) if i % 2 == 0 else Color(0.95, 0.95, 0.9)
		b.box(Vector3(0.42, 0.06, 1.7), _x(Vector3(-1.47 + i * 0.42, 3.0, 0.05), Vector3(-14, 0, 0)), c2)
	for sx in [-1.5, 1.5]:
		b.box(Vector3(0.1, 3.0, 0.1), _x(Vector3(sx, 1.5, -0.6)), wood.darkened(0.3))
	b.box(Vector3(2.6, 0.5, 0.1), _x(Vector3(0, 3.55, 0.2)), _g(Color(0.2, 0.7, 0.35), 0.9))
	b.box(Vector3(0.6, 0.35, 0.5), _x(Vector3(1.0, 1.4, 0.0)), Color(0.2, 0.2, 0.24))
	b.box(Vector3(0.4, 0.2, 0.3), _x(Vector3(1.0, 1.55, -0.1), Vector3(-20, 0, 0)), _g(Color(0.4, 1.0, 0.6), 0.6))
	Mats.mesh_instance(b.build(), Mats.world_material(), root)
	var lbl := Label3D.new()
	lbl.text = "TIENDA DEL NOTARIO"
	lbl.font_size = 56
	lbl.pixel_size = 0.0065
	lbl.outline_size = 12
	lbl.modulate = Color(1, 1, 1)
	lbl.position = Vector3(0, 3.56, 0.14)
	lbl.no_depth_test = false
	root.add_child(lbl)
	var lbl2 := lbl.duplicate()
	lbl2.position = Vector3(0, 3.56, 0.14)
	return root


# =============================================================================
#  SUELO, MUROS Y HORIZONTE
# =============================================================================
static func floor_mesh(half: float, pal: Dictionary, rng: RandomNumberGenerator) -> ArrayMesh:
	var b := MeshBuilder.new()
	var tile := 2.0
	var n := int(ceil(half * 2.0 / tile))
	var a: Color = pal.get("floor_a", Color(0.3, 0.3, 0.33))
	var c2: Color = pal.get("floor_b", Color(0.26, 0.26, 0.29))
	var line: Color = pal.get("floor_line", Color(0.9, 0.8, 0.2))
	var start := -half
	var down := Vector3(0, -1.0, 0)
	for ix in n:
		for iz in n:
			var col := a if (ix + iz) % 2 == 0 else c2
			col = _vary(col, rng, 0.012)
			var x0 := start + ix * tile
			var z0 := start + iz * tile
			b.quad(Vector3(x0, 0, z0), Vector3(x0 + tile, 0, z0), Vector3(x0 + tile, 0, z0 + tile), Vector3(x0, 0, z0 + tile), Vector3(x0 + tile * 0.5, -1, z0 + tile * 0.5), col)
	# marcas decorativas
	var style: String = pal.get("floor_style", "lines")
	if style == "lines":
		for k in range(-1, 2):
			b.box(Vector3(half * 2.0, 0.01, 0.18), _x(Vector3(0, 0.012, k * half * 0.6)), line)
	elif style == "ring":
		for i in 32:
			var ang := TAU * float(i) / 32.0
			b.box(Vector3(1.6, 0.01, 0.3), _x(Vector3(cos(ang) * 9.0, 0.012, sin(ang) * 9.0), Vector3(0, -rad_to_deg(ang) + 90.0, 0)), line)
	elif style == "cross":
		b.box(Vector3(half * 2.0, 0.01, 0.3), _x(Vector3(0, 0.012, 0)), line)
		b.box(Vector3(0.3, 0.01, half * 2.0), _x(Vector3(0, 0.012, 0)), line)
	# terreno exterior
	var out: Color = pal.get("ground", Color(0.06, 0.07, 0.09))
	var f := 260.0
	b.quad(Vector3(-f, -0.06, -f), Vector3(f, -0.06, -f), Vector3(f, -0.06, f), Vector3(-f, -0.06, f), Vector3(0, -2, 0), out)
	return b.build()


static func wall_visual(half: float, pal: Dictionary, rng: RandomNumberGenerator) -> ArrayMesh:
	var b := MeshBuilder.new()
	var style: String = pal.get("wall_style", "rail")
	var wc: Color = pal.get("wall", Color(0.4, 0.4, 0.45))
	var accent: Color = pal.get("wall_accent", Color(0.9, 0.7, 0.2))
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
			if style == "rail":
				b.box(Vector3(0.14, 1.2, 0.14), _x(pos + Vector3(0, 0.6, 0)), wc.darkened(0.2))
				b.box(Vector3(step, 0.08, 0.1), _x(pos + Vector3(0, 1.15, 0), Vector3(0, rot, 0)), wc)
				b.box(Vector3(step, 0.06, 0.08), _x(pos + Vector3(0, 0.7, 0), Vector3(0, rot, 0)), wc.darkened(0.1))
				if i % 4 == 0:
					b.sphere(0.12, 5, 4, _x(pos + Vector3(0, 1.3, 0)), _g(accent, 0.8))
			elif style == "wall":
				b.box(Vector3(step, 1.5, 0.5), _x(pos + Vector3(0, 0.75, 0), Vector3(0, rot, 0)), _vary(wc, rng, 0.03))
				b.box(Vector3(step + 0.1, 0.15, 0.62), _x(pos + Vector3(0, 1.55, 0), Vector3(0, rot, 0)), wc.lightened(0.1))
			else:  # valla
				b.box(Vector3(0.1, 2.0, 0.1), _x(pos + Vector3(0, 1.0, 0)), wc.darkened(0.3))
				b.box(Vector3(step, 1.6, 0.04), _x(pos + Vector3(0, 1.0, 0), Vector3(0, rot, 0)), wc)
				b.box(Vector3(step, 0.06, 0.08), _x(pos + Vector3(0, 2.0, 0), Vector3(0, rot, 0)), wc.lightened(0.2))
	return b.build()


static func wall_colliders(half: float) -> Array:
	var out: Array = []
	var thick := 3.0
	var hgt := 12.0
	var e := half + 0.4
	var defs := [
		[Vector3(half * 2.0 + thick * 2.0, hgt, thick), Vector3(0, hgt * 0.5, -e - thick * 0.5)],
		[Vector3(half * 2.0 + thick * 2.0, hgt, thick), Vector3(0, hgt * 0.5, e + thick * 0.5)],
		[Vector3(thick, hgt, half * 2.0), Vector3(-e - thick * 0.5, hgt * 0.5, 0)],
		[Vector3(thick, hgt, half * 2.0), Vector3(e + thick * 0.5, hgt * 0.5, 0)],
	]
	for d in defs:
		var sb := static_body(d[0], d[1])
		sb.name = "WallCollider"
		out.append(sb)
	# suelo
	var fl := static_body(Vector3(half * 2.0 + 8.0, 2.0, half * 2.0 + 8.0), Vector3(0, -1.0, 0))
	fl.name = "FloorCollider"
	out.append(fl)
	return out


static func skyline(half: float, pal: Dictionary, rng: RandomNumberGenerator) -> ArrayMesh:
	var b := MeshBuilder.new()
	var body_c: Color = pal.get("building", Color(0.12, 0.13, 0.2))
	var win_c: Color = pal.get("window", Color(1.0, 0.85, 0.45))
	var count := int(pal.get("towers", 30))
	for i in count:
		var ang := TAU * (float(i) + rng.randf_range(-0.3, 0.3)) / count
		var dist := half * 1.55 + rng.randf_range(4.0, 28.0)
		var w := rng.randf_range(8.0, 16.0)
		var d := rng.randf_range(8.0, 16.0)
		var h := rng.randf_range(14.0, 58.0)
		var pos := Vector3(cos(ang) * dist, h * 0.5 - 0.5, sin(ang) * dist)
		var yaw := -rad_to_deg(ang) + 90.0
		var col := _vary(body_c, rng, 0.03)
		b.box(Vector3(w, h, d), _x(pos, Vector3(0, yaw, 0)), col)
		b.box(Vector3(w * 0.7, 1.2, d * 0.7), _x(pos + Vector3(0, h * 0.5 + 0.6, 0), Vector3(0, yaw, 0)), col.darkened(0.2))
		if rng.randf() < 0.4:
			b.cylinder(0.08, 0.08, 6.0, 4, _x(pos + Vector3(0, h * 0.5 + 4.0, 0)), STEEL())
			b.sphere(0.3, 4, 3, _x(pos + Vector3(0, h * 0.5 + 7.2, 0)), _g(Color(1, 0.15, 0.1), 1.0))
		# ventanas en la cara que mira al centro del escenario
		var face_dir := Vector3(-cos(ang), 0, -sin(ang))
		var basis := Basis.from_euler(Vector3(0, deg_to_rad(yaw), 0))
		var zaxis := basis * Vector3(0, 0, 1)
		var xaxis := basis * Vector3(1, 0, 0)
		var normal := zaxis if zaxis.dot(face_dir) > 0.0 else -zaxis
		var rows := int(h / 3.2)
		var cols := int(w / 2.0)
		for r in rows:
			for c in cols:
				if rng.randf() < 0.45:
					continue
				var lx := (c - (cols - 1) * 0.5) * 2.0
				var ly := -h * 0.5 + 2.0 + r * 3.2
				var center := pos + xaxis * lx + Vector3(0, ly, 0) + normal * (d * 0.5 + 0.04)
				var wcol := win_c if rng.randf() < 0.8 else Color(0.5, 0.8, 1.0)
				var rx := xaxis * 0.7
				var ry := Vector3(0, 0.9, 0)
				b.quad(center - rx - ry, center + rx - ry, center + rx + ry, center - rx + ry, pos, _g(wcol, 0.9))
	return b.build()
