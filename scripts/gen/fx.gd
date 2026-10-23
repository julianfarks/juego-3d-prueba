class_name FX
extends Node3D
## Efectos visuales con pooling: anillos, destellos, rayos, telegrafías de ataque,
## zonas persistentes, números de daño y ráfagas de partículas.
## El número máximo de efectos simultáneos depende del preset de calidad (Config.QUALITY).

class Item extends RefCounted:
	var node: Node3D
	var inner: MeshInstance3D = null
	var mat: StandardMaterial3D
	var inner_mat: StandardMaterial3D = null
	var kind := ""
	var t := 0.0
	var dur := 1.0
	var color := Color.WHITE
	var s0 := 1.0
	var s1 := 1.0
	var active := false
	var data: Dictionary = {}
	var follow: Node3D = null

var pools: Dictionary = {}
var active_items: Array[Item] = []
var particle_pool: Array[CPUParticles3D] = []
var particle_next := 0
var max_fx := 48
var particle_scale := 1.0
var numbers_enabled := true

static var _disc: ArrayMesh
static var _ring: ArrayMesh
static var _sphere: SphereMesh
static var _box: BoxMesh
static var _sectors: Dictionary = {}
static var _spark: BoxMesh


func _ready() -> void:
	apply_quality()
	GameState.fx = self


func apply_quality() -> void:
	var q := Config.quality()
	max_fx = int(q["max_fx"])
	particle_scale = float(q["fx_particles"])
	numbers_enabled = bool(SaveSystem.setting("damage_numbers"))


# --- mallas compartidas -------------------------------------------------------
static func _disc_mesh() -> ArrayMesh:
	if _disc == null:
		_disc = _fan(360.0, 28, 1.0)
	return _disc


static func _fan(angle_deg: float, seg: int, radius: float) -> ArrayMesh:
	# sector plano en XZ con vértice en el origen, centrado hacia -Z
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var half := deg_to_rad(angle_deg) * 0.5
	for i in seg:
		var a0 := -half + 2.0 * half * float(i) / seg
		var a1 := -half + 2.0 * half * float(i + 1) / seg
		verts.append(Vector3.ZERO)
		verts.append(Vector3(sin(a1) * radius, 0, -cos(a1) * radius))
		verts.append(Vector3(sin(a0) * radius, 0, -cos(a0) * radius))
		for k in 3:
			normals.append(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


static func _ring_mesh() -> ArrayMesh:
	if _ring == null:
		var verts := PackedVector3Array()
		var normals := PackedVector3Array()
		var seg := 32
		var r0 := 0.86
		for i in seg:
			var a0 := TAU * float(i) / seg
			var a1 := TAU * float(i + 1) / seg
			var p00 := Vector3(cos(a0) * r0, 0, sin(a0) * r0)
			var p01 := Vector3(cos(a0), 0, sin(a0))
			var p10 := Vector3(cos(a1) * r0, 0, sin(a1) * r0)
			var p11 := Vector3(cos(a1), 0, sin(a1))
			for v in [p00, p01, p11, p00, p11, p10]:
				verts.append(v)
				normals.append(Vector3.UP)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		_ring = ArrayMesh.new()
		_ring.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _ring


static func _sector_mesh(angle_deg: float) -> ArrayMesh:
	var key := int(angle_deg)
	if not _sectors.has(key):
		_sectors[key] = _fan(angle_deg, maxi(4, int(angle_deg / 12.0)), 1.0)
	return _sectors[key]


static func _sphere_mesh() -> SphereMesh:
	if _sphere == null:
		_sphere = SphereMesh.new()
		_sphere.radius = 1.0
		_sphere.height = 2.0
		_sphere.radial_segments = 10
		_sphere.rings = 6
	return _sphere


static func _box_mesh() -> BoxMesh:
	if _box == null:
		_box = BoxMesh.new()
		_box.size = Vector3(1, 1, 1)
	return _box


# --- pool genérico -----------------------------------------------------------
func _acquire(kind: String, force := false) -> Item:
	if not force and active_items.size() >= max_fx:
		return null
	var pool: Array = pools.get(kind, [])
	var it: Item = null
	for cand in pool:
		if not cand.active:
			it = cand
			break
	if it == null:
		it = _create(kind)
		pool.append(it)
		pools[kind] = pool
	it.active = true
	it.t = 0.0
	it.follow = null
	it.data.erase("cancel")
	it.data.erase("width")
	it.node.visible = true
	active_items.append(it)
	return it


func _create(kind: String) -> Item:
	var it := Item.new()
	it.kind = kind
	var root := Node3D.new()
	add_child(root)
	it.node = root
	it.mat = StandardMaterial3D.new()
	it.mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	it.mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	it.mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	match kind:
		"ring":
			mi.mesh = _ring_mesh()
			it.mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		"flash":
			mi.mesh = _sphere_mesh()
			it.mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		"beam":
			mi.mesh = _box_mesh()
			it.mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		"tele_circle", "zone":
			mi.mesh = _disc_mesh()
		"tele_cone":
			mi.mesh = _disc_mesh()
		"tele_line":
			mi.mesh = _box_mesh()
		"label":
			pass
	mi.material_override = it.mat
	root.add_child(mi)
	it.data["mesh"] = mi
	if kind.begins_with("tele_") or kind == "zone":
		it.inner_mat = StandardMaterial3D.new()
		it.inner_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		it.inner_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		it.inner_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var inner := MeshInstance3D.new()
		inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		inner.mesh = mi.mesh
		inner.material_override = it.inner_mat
		root.add_child(inner)
		it.inner = inner
	return it


func _release(it: Item) -> void:
	it.active = false
	it.node.visible = false
	it.follow = null


func _process(delta: float) -> void:
	var i := active_items.size() - 1
	while i >= 0:
		var it := active_items[i]
		it.t += delta
		var k := clampf(it.t / it.dur, 0.0, 1.0)
		var done := false
		match it.kind:
			"ring":
				var r := lerpf(it.s0, it.s1, ease(k, 0.35))
				it.node.scale = Vector3(r, 1, r)
				it.mat.albedo_color = Color(it.color.r, it.color.g, it.color.b, it.color.a * (1.0 - k))
				done = k >= 1.0
			"flash":
				var r2 := lerpf(it.s0, it.s1, ease(k, 0.3))
				it.node.scale = Vector3.ONE * r2
				it.mat.albedo_color = Color(it.color.r, it.color.g, it.color.b, it.color.a * (1.0 - k) * (1.0 - k))
				done = k >= 1.0
			"beam":
				it.mat.albedo_color = Color(it.color.r, it.color.g, it.color.b, it.color.a * (1.0 - k))
				done = k >= 1.0
			"tele_circle", "tele_cone", "tele_line":
				if it.follow != null and is_instance_valid(it.follow):
					it.node.global_position = Vector3(it.follow.global_position.x, it.node.global_position.y, it.follow.global_position.z)
				var fill := ease(k, 1.6)
				var pulse := 0.18 + 0.1 * sin(it.t * 18.0)
				it.mat.albedo_color = Color(it.color.r, it.color.g, it.color.b, pulse + 0.1)
				it.inner_mat.albedo_color = Color(it.color.r, it.color.g, it.color.b, 0.5 * (0.5 + 0.5 * k))
				_set_fill(it, fill)
				done = k >= 1.0
			"zone":
				var fade := 1.0 if k < 0.85 else (1.0 - k) / 0.15
				var pulse2 := 0.5 + 0.5 * sin(it.t * 5.0)
				it.mat.albedo_color = Color(it.color.r, it.color.g, it.color.b, (0.22 + 0.1 * pulse2) * fade)
				it.inner_mat.albedo_color = Color(it.color.r, it.color.g, it.color.b, (0.1 + 0.06 * pulse2) * fade)
				it.inner.scale = Vector3.ONE * (0.55 + 0.4 * fmod(it.t * 0.7, 1.0))
				if it.follow != null and is_instance_valid(it.follow):
					it.node.global_position = Vector3(it.follow.global_position.x, it.node.global_position.y, it.follow.global_position.z)
				done = k >= 1.0
			"label":
				pass
		if done or it.data.get("cancel", false):
			_release(it)
			active_items.remove_at(i)
		i -= 1
	_update_labels(delta)


func _set_fill(it: Item, fill: float) -> void:
	match it.kind:
		"tele_circle":
			it.inner.scale = Vector3(fill, 1, fill) * it.s0
		"tele_cone":
			it.inner.scale = Vector3(fill, 1, fill) * it.s0
		"tele_line":
			var width: float = it.data.get("width", 1.0)
			var length: float = it.s0
			it.inner.scale = Vector3(width, 0.02, maxf(length * fill, 0.01))
			it.inner.position = Vector3(0, 0, -length * fill * 0.5)


# --- API pública --------------------------------------------------------------
func ring(pos: Vector3, radius: float, color := Color(1, 1, 1, 0.8), dur := 0.35, start_radius := 0.3, y := 0.1) -> void:
	var it := _acquire("ring")
	if it == null:
		return
	it.node.global_position = Vector3(pos.x, pos.y + y, pos.z)
	it.color = color
	it.dur = dur
	it.s0 = start_radius
	it.s1 = radius


func flash_sphere(pos: Vector3, radius: float, color := Color(1, 0.8, 0.3, 0.8), dur := 0.25) -> void:
	var it := _acquire("flash")
	if it == null:
		return
	it.node.global_position = pos
	it.color = color
	it.dur = dur
	it.s0 = radius * 0.3
	it.s1 = radius


func beam(a: Vector3, b: Vector3, color := Color(0.6, 0.9, 1.0, 0.9), width := 0.12, dur := 0.14) -> void:
	var it := _acquire("beam")
	if it == null:
		return
	var d := b - a
	var len := d.length()
	if len < 0.01:
		_release(it)
		active_items.erase(it)
		return
	it.node.global_position = (a + b) * 0.5
	it.node.look_at_from_position((a + b) * 0.5, b, Vector3.UP if absf(d.normalized().y) < 0.99 else Vector3.RIGHT)
	(it.data["mesh"] as MeshInstance3D).scale = Vector3(width, width, len)
	it.color = color
	it.dur = dur


## Telegrafías (señales visuales previas a un ataque enemigo).
func telegraph_circle(pos: Vector3, radius: float, dur: float, color := Color(1.0, 0.15, 0.1)) -> Item:
	var it := _acquire("tele_circle", true)
	if it == null:
		return null
	it.node.global_position = Vector3(pos.x, 0.07, pos.z)
	it.node.rotation = Vector3.ZERO
	it.color = color
	it.dur = maxf(dur, 0.05)
	it.s0 = radius
	(it.data["mesh"] as MeshInstance3D).scale = Vector3(radius, 1, radius)
	(it.data["mesh"] as MeshInstance3D).position = Vector3.ZERO
	it.inner.position = Vector3.ZERO
	return it


func telegraph_cone(pos: Vector3, yaw: float, radius: float, angle_deg: float, dur: float, color := Color(1.0, 0.15, 0.1)) -> Item:
	var it := _acquire("tele_cone", true)
	if it == null:
		return null
	it.node.global_position = Vector3(pos.x, 0.07, pos.z)
	it.node.rotation = Vector3(0, yaw, 0)
	it.color = color
	it.dur = maxf(dur, 0.05)
	it.s0 = radius
	var m := _sector_mesh(angle_deg)
	var mi: MeshInstance3D = it.data["mesh"]
	mi.mesh = m
	mi.scale = Vector3(radius, 1, radius)
	mi.position = Vector3.ZERO
	it.inner.mesh = m
	it.inner.position = Vector3.ZERO
	return it


func telegraph_line(pos: Vector3, yaw: float, length: float, width: float, dur: float, color := Color(1.0, 0.15, 0.1)) -> Item:
	var it := _acquire("tele_line", true)
	if it == null:
		return null
	it.node.global_position = Vector3(pos.x, 0.07, pos.z)
	it.node.rotation = Vector3(0, yaw, 0)
	it.color = color
	it.dur = maxf(dur, 0.05)
	it.s0 = length
	it.data["width"] = width
	var mi: MeshInstance3D = it.data["mesh"]
	mi.scale = Vector3(width, 0.02, length)
	mi.position = Vector3(0, 0, -length * 0.5)
	return it


func cancel(it: Item) -> void:
	if it != null and it.active:
		it.data["cancel"] = true


## Zona persistente (sellos, zonas de energía, peligros). Devuelve el Item para poder cancelarla.
func zone(pos: Vector3, radius: float, dur: float, color := Color(0.5, 0.3, 1.0), follow_node: Node3D = null) -> Item:
	var it := _acquire("zone", true)
	if it == null:
		return null
	it.node.global_position = Vector3(pos.x, 0.06, pos.z)
	it.node.rotation = Vector3.ZERO
	it.color = color
	it.dur = maxf(dur, 0.1)
	var mi: MeshInstance3D = it.data["mesh"]
	mi.mesh = _disc_mesh()
	mi.scale = Vector3(radius, 1, radius)
	it.inner.mesh = _disc_mesh()
	it.inner.scale = Vector3(radius * 0.6, 1, radius * 0.6)
	it.follow = follow_node
	return it


# --- números de daño ----------------------------------------------------------
var _labels: Array = []   # [{node, t, dur, vel, start}]
var _label_pool: Array[Label3D] = []


func damage_number(pos: Vector3, text: String, color := Color.WHITE, size := 1.0, crit := false) -> void:
	if not numbers_enabled:
		return
	if _labels.size() >= int(max_fx * 0.6):
		return
	var lbl: Label3D = null
	for l in _label_pool:
		if not l.visible:
			lbl = l
			break
	if lbl == null:
		lbl = Label3D.new()
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true
		lbl.fixed_size = false
		lbl.font_size = 44
		lbl.outline_size = 10
		lbl.pixel_size = 0.0085
		lbl.shaded = false
		lbl.double_sided = true
		add_child(lbl)
		_label_pool.append(lbl)
	lbl.visible = true
	lbl.text = text
	lbl.modulate = color
	lbl.outline_modulate = Color(0.05, 0.03, 0.08, 0.95)
	lbl.global_position = pos + Vector3(randf_range(-0.3, 0.3), 0.0, randf_range(-0.3, 0.3))
	lbl.scale = Vector3.ONE * size * (1.5 if crit else 1.0)
	_labels.append({"node": lbl, "t": 0.0, "dur": 0.85 if crit else 0.65, "base": lbl.scale.x, "color": color})


func _update_labels(delta: float) -> void:
	var i := _labels.size() - 1
	while i >= 0:
		var d: Dictionary = _labels[i]
		d["t"] += delta
		var k: float = clampf(d["t"] / d["dur"], 0.0, 1.0)
		var lbl: Label3D = d["node"]
		lbl.global_position += Vector3(0, delta * (2.4 - 1.8 * k), 0)
		var pop := 1.0 + 0.35 * maxf(0.0, 1.0 - k * 6.0)
		lbl.scale = Vector3.ONE * float(d["base"]) * pop
		var c: Color = d["color"]
		lbl.modulate = Color(c.r, c.g, c.b, 1.0 - maxf(0.0, (k - 0.55) / 0.45))
		if k >= 1.0:
			lbl.visible = false
			_labels.remove_at(i)
		i -= 1


# --- partículas ---------------------------------------------------------------
func burst(pos: Vector3, color: Color, amount := 10, speed := 5.0, size := 0.12, life := 0.5) -> void:
	var n := int(round(amount * particle_scale))
	if n <= 0:
		return
	var p := _particles()
	p.global_position = pos
	p.amount = n
	p.lifetime = life
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.scale_amount_min = size * 0.7
	p.scale_amount_max = size * 1.3
	p.color = color
	p.restart()
	p.emitting = true


func _particles() -> CPUParticles3D:
	var cap := maxi(6, int(max_fx * 0.35))
	if particle_pool.size() < cap:
		var p := CPUParticles3D.new()
		p.one_shot = true
		p.explosiveness = 1.0
		p.emitting = false
		p.direction = Vector3.UP
		p.spread = 180.0
		p.gravity = Vector3(0, -10, 0)
		if _spark == null:
			_spark = BoxMesh.new()
			_spark.size = Vector3(0.5, 0.5, 0.5)
		p.mesh = _spark
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		p.material_override = m
		var curve := Curve.new()
		curve.add_point(Vector2(0, 1))
		curve.add_point(Vector2(1, 0))
		p.scale_amount_curve = curve
		p.local_coords = false
		add_child(p)
		particle_pool.append(p)
		return p
	var q := particle_pool[particle_next]
	particle_next = (particle_next + 1) % particle_pool.size()
	return q


func clear_all() -> void:
	for it in active_items:
		_release(it)
	active_items.clear()
	for l in _label_pool:
		l.visible = false
	_labels.clear()
