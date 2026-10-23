class_name Projectiles
extends Node3D
## Gestor central de proyectiles con pooling. No usa cuerpos físicos: mueve cada proyectil
## manualmente, hace un raycast contra el mundo y comprueba distancia contra objetivos.
## Tipos: "doc" (documento teledirigido del jugador), "boomerang" (maletín bumerán),
## "coin" / "bolt" / "blob" (proyectiles enemigos).

class P extends RefCounted:
	var node: Node3D
	var kind := ""
	var team := "player"
	var pos := Vector3.ZERO
	var vel := Vector3.ZERO
	var life := 3.0
	var dmg := 10.0
	var radius := 0.35
	var speed := 14.0
	var target: Node3D = null
	var turn := 0.0
	var pierce := 0
	var hit_set: Array = []
	var phase := 0
	var dist := 0.0
	var max_dist := 10.0
	var opts: Dictionary = {}
	var spin := 0.0
	var gravity := 0.0

var pool: Dictionary = {}
var active: Array[P] = []
static var _meshes: Dictionary = {}
var max_active := 90


func _ready() -> void:
	GameState.projectiles = self


static func _mesh_for(kind: String) -> ArrayMesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var b := MeshBuilder.new()
	var x := func(pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE) -> Transform3D:
		return MeshBuilder.xf(pos, rot, scl)
	match kind:
		"doc":
			b.box(Vector3(0.3, 0.025, 0.4), x.call(), MeshBuilder.glow(Color(0.98, 0.97, 0.9), 0.55))
			for i in 4:
				b.box(Vector3(0.2, 0.03, 0.02), x.call(Vector3(0, 0.003, -0.12 + i * 0.07)), Color(0.25, 0.3, 0.5))
			b.cylinder(0.05, 0.05, 0.035, 6, x.call(Vector3(0.08, 0.004, 0.14)), MeshBuilder.glow(Color(0.9, 0.12, 0.15), 0.9))
		"boomerang":
			var cb := ModelFactory.briefcase_mesh()
			_meshes[kind] = cb
			return cb
		"coin":
			b.cylinder(0.2, 0.2, 0.06, 8, x.call(Vector3.ZERO, Vector3(90, 0, 0)), MeshBuilder.glow(Color(1.0, 0.78, 0.2), 0.9))
			b.cylinder(0.12, 0.12, 0.08, 8, x.call(Vector3.ZERO, Vector3(90, 0, 0)), MeshBuilder.glow(Color(1.0, 0.95, 0.6), 1.0))
		"bolt":
			b.sphere(0.2, 6, 4, x.call(), MeshBuilder.glow(Color(1.0, 0.35, 0.15), 1.0))
			b.sphere(0.3, 6, 4, x.call(), MeshBuilder.glow(Color(1.0, 0.7, 0.2), 0.45))
		"blob":
			b.sphere(0.34, 7, 5, x.call(), MeshBuilder.glow(Color(0.3, 1.0, 0.5), 1.0))
			b.sphere(0.5, 7, 5, x.call(), MeshBuilder.glow(Color(0.2, 0.9, 0.4), 0.35))
		_:
			b.sphere(0.25, 6, 4, x.call(), MeshBuilder.glow(Color(1, 1, 1), 1.0))
	_meshes[kind] = b.build()
	return _meshes[kind]


func _acquire(kind: String) -> P:
	var list: Array = pool.get(kind, [])
	for cand in list:
		if cand.node != null and not cand.node.visible:
			cand.hit_set = []
			cand.target = null
			cand.opts = {}
			cand.phase = 0
			cand.dist = 0.0
			cand.pierce = 0
			cand.turn = 0.0
			cand.spin = 0.0
			cand.gravity = 0.0
			return cand
	var p := P.new()
	p.kind = kind
	var n := Node3D.new()
	var mi := Mats.mesh_instance(_mesh_for(kind), Mats.world_material(), n)
	mi.material_override = Mats.world_material()
	add_child(n)
	p.node = n
	list.append(p)
	pool[kind] = list
	return p


func _spawn(p: P) -> void:
	p.node.visible = true
	p.node.global_position = p.pos
	active.append(p)


func count() -> int:
	return active.size()


## Documento teledirigido del jugador.
func fire_doc(from: Vector3, dir: Vector3, dmg: float, target: Node3D, speed: float, opts: Dictionary) -> void:
	if active.size() >= max_active:
		return
	var p := _acquire("doc")
	p.team = "player"
	p.pos = from
	p.speed = speed
	p.vel = dir.normalized() * speed
	p.dmg = dmg
	p.target = target
	p.turn = 7.0
	p.life = 3.0
	p.radius = 0.55
	p.opts = opts
	p.spin = 14.0
	_spawn(p)


func fire_boomerang(from: Vector3, dir: Vector3, dmg: float, max_dist: float, size: float, opts: Dictionary) -> void:
	if active.size() >= max_active:
		return
	var p := _acquire("boomerang")
	p.team = "player"
	p.pos = from
	p.speed = 17.0
	p.vel = dir.normalized() * p.speed
	p.dmg = dmg
	p.max_dist = max_dist
	p.life = 5.0
	p.radius = 0.9 * size
	p.pierce = 99
	p.opts = opts
	p.spin = 16.0
	p.node.scale = Vector3.ONE * size
	_spawn(p)


## Proyectil enemigo. kind: coin | bolt | blob
func fire_enemy(kind: String, from: Vector3, dir: Vector3, dmg: float, speed: float, radius := 0.3, life := 4.0, gravity := 0.0) -> void:
	if active.size() >= max_active:
		return
	var p := _acquire(kind)
	p.team = "enemy"
	p.pos = from
	p.speed = speed
	p.vel = dir.normalized() * speed
	p.dmg = dmg
	p.life = life
	p.radius = radius
	p.spin = 9.0
	p.gravity = gravity
	p.node.scale = Vector3.ONE
	_spawn(p)


func clear_all() -> void:
	for p in active:
		p.node.visible = false
	active.clear()


func _physics_process(delta: float) -> void:
	if active.is_empty():
		return
	var space := get_world_3d().direct_space_state
	var player = GameState.player
	var i := active.size() - 1
	while i >= 0:
		var p := active[i]
		var kill := false
		p.life -= delta
		if p.life <= 0.0:
			kill = true
		# --- movimiento ---
		if p.kind == "doc" and p.target != null and is_instance_valid(p.target) and p.target.alive:
			var want: Vector3 = (p.target.global_position + Vector3(0, 1.0, 0) - p.pos).normalized()
			var cur := p.vel.normalized()
			cur = cur.slerp(want, clampf(p.turn * delta, 0.0, 1.0))
			p.vel = cur * p.speed
		elif p.kind == "doc" and (p.target == null or not is_instance_valid(p.target) or not p.target.alive):
			var nt := Combat.nearest_enemy(p.pos, 18.0)
			if nt != null:
				p.target = nt
		if p.kind == "boomerang":
			if p.phase == 0:
				p.dist += p.speed * delta
				if p.dist >= p.max_dist:
					p.phase = 1
					p.hit_set = []
			elif player != null:
				var back: Vector3 = (player.global_position + Vector3(0, 1.0, 0) - p.pos)
				if back.length() < 1.2:
					kill = true
				p.vel = back.normalized() * p.speed * 1.15
		p.vel.y -= p.gravity * delta
		var new_pos := p.pos + p.vel * delta
		# --- colisión con el mundo ---
		if p.kind != "boomerang":
			var q := PhysicsRayQueryParameters3D.create(p.pos, new_pos, Config.L_WORLD)
			var res := space.intersect_ray(q)
			if not res.is_empty():
				kill = true
				new_pos = res["position"]
				if GameState.fx != null:
					GameState.fx.burst(new_pos, Color(1, 0.9, 0.6), 4, 3.0, 0.1, 0.3)
		p.pos = new_pos
		# --- impactos ---
		if not kill:
			if p.team == "player":
				for e in Combat.arena_enemies():
					if not is_instance_valid(e) or not e.alive or p.hit_set.has(e):
						continue
					var c: Vector3 = e.global_position + Vector3(0, 0.9, 0)
					var rr: float = p.radius + e.body_radius
					if c.distance_squared_to(p.pos) <= rr * rr:
						p.hit_set.append(e)
						_player_projectile_hit(p, e)
						if p.pierce <= 0:
							kill = true
							break
						p.pierce -= 1 if p.kind != "boomerang" else 0
			elif player != null and player.alive:
				var pc: Vector3 = player.global_position + Vector3(0, 0.9, 0)
				var rr2: float = p.radius + 0.45
				if pc.distance_squared_to(p.pos) <= rr2 * rr2:
					player.take_damage(p.dmg, p.pos, {"src": "projectile"})
					kill = true
		# --- visual ---
		p.node.global_position = p.pos
		if p.kind == "doc":
			if p.vel.length() > 0.1:
				p.node.look_at(p.pos + p.vel, Vector3.UP)
			p.node.rotate_object_local(Vector3(0, 0, 1), p.spin * delta + p.life * 0.0)
		elif p.kind == "boomerang":
			p.node.rotation.y += p.spin * delta
			p.node.rotation.z = 0.5
		else:
			p.node.rotation.y += p.spin * delta
		if kill:
			p.node.visible = false
			active.remove_at(i)
		i -= 1


func _player_projectile_hit(p: P, e: Node3D) -> void:
	var dir: Vector3 = p.vel.normalized()
	dir.y = 0.0
	var o: Dictionary = p.opts.duplicate()
	o["knock"] = dir * 3.0
	o["skill"] = p.kind == "doc"
	var src: String = "docs" if p.kind == "doc" else "boomerang"
	o["src"] = src
	if GameState.fx != null:
		GameState.fx.burst(p.pos, Color(1, 1, 0.9), 5, 4.0, 0.1, 0.3)
	if GameState.build.has_synergy("perfect_storm") and p.kind == "doc":
		o["force_crit"] = randf() < 0.25
	AudioManager.sfx_at("hit_1", p.pos, -8.0)
	Combat.player_hit(e, p.dmg, o)
