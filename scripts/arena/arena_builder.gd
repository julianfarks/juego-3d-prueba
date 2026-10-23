class_name ArenaBuilder
extends RefCounted
## Construye proceduralmente el escenario de una arena: entorno, luz, suelo, muros,
## horizonte, obstáculos y plataformas con rampas. Devuelve datos de colocación para el spawn.

const THEMES := [
	{ # 0: Muelle de carga
		"name": "Muelle Portuario",
		"floor_a": Color(0.36, 0.37, 0.40), "floor_b": Color(0.31, 0.32, 0.35),
		"wall": Color(0.45, 0.28, 0.2), "wall_accent": Color(0.95, 0.7, 0.2), "wall_style": "rail",
		"building": Color(0.13, 0.15, 0.24), "window": Color(1.0, 0.85, 0.45), "towers": 30,
		"wood": Color(0.62, 0.42, 0.22), "metal": Color(0.42, 0.46, 0.52),
		"paints": [Color(0.75, 0.2, 0.18), Color(0.2, 0.42, 0.7), Color(0.88, 0.65, 0.15)],
		"marble": Color(0.85, 0.84, 0.8), "platform": Color(0.5, 0.52, 0.56),
		"sky": Color(0.36, 0.5, 0.74), "fog": Color(0.55, 0.65, 0.82), "ambient": Color(0.62, 0.68, 0.8),
		"sun": Color(1.0, 0.93, 0.8), "kinds": ["crate", "crate", "crate_big", "container", "pallets", "barrier", "tank", "debris"],
	},
	{ # 1: Azotea de rascacielos
		"name": "Azotea Financiera",
		"floor_a": Color(0.4, 0.42, 0.46), "floor_b": Color(0.35, 0.37, 0.41),
		"wall": Color(0.6, 0.62, 0.66), "wall_accent": Color(0.3, 0.8, 0.95), "wall_style": "glass",
		"building": Color(0.1, 0.12, 0.2), "window": Color(0.6, 0.9, 1.0), "towers": 40,
		"wood": Color(0.55, 0.4, 0.28), "metal": Color(0.55, 0.6, 0.66),
		"paints": [Color(0.2, 0.55, 0.75), Color(0.85, 0.85, 0.9), Color(0.9, 0.45, 0.2)],
		"marble": Color(0.9, 0.9, 0.92), "platform": Color(0.55, 0.58, 0.63),
		"sky": Color(0.95, 0.6, 0.4), "fog": Color(0.98, 0.72, 0.55), "ambient": Color(0.85, 0.72, 0.7),
		"sun": Color(1.0, 0.78, 0.55), "kinds": ["ac_unit", "ac_unit", "crate", "pillar", "bench", "barrier", "tank", "safe"],
	},
	{ # 2: Plaza de los Juzgados
		"name": "Plaza de los Juzgados",
		"floor_a": Color(0.75, 0.72, 0.65), "floor_b": Color(0.68, 0.65, 0.58),
		"wall": Color(0.82, 0.8, 0.74), "wall_accent": Color(0.75, 0.55, 0.2), "wall_style": "rail",
		"building": Color(0.2, 0.2, 0.28), "window": Color(1.0, 0.9, 0.6), "towers": 24,
		"wood": Color(0.45, 0.3, 0.18), "metal": Color(0.4, 0.42, 0.45),
		"paints": [Color(0.55, 0.15, 0.2), Color(0.15, 0.3, 0.5), Color(0.8, 0.7, 0.3)],
		"marble": Color(0.92, 0.9, 0.85), "platform": Color(0.72, 0.7, 0.64),
		"sky": Color(0.42, 0.62, 0.85), "fog": Color(0.7, 0.8, 0.92), "ambient": Color(0.78, 0.8, 0.85),
		"sun": Color(1.0, 0.96, 0.88), "kinds": ["pillar", "pillar", "statue", "bench", "counter", "car", "dumpster", "wall_piece"],
	},
	{ # 3: Bóveda del banco (jefe)
		"name": "Bóveda del Banco",
		"floor_a": Color(0.24, 0.24, 0.28), "floor_b": Color(0.2, 0.2, 0.24),
		"wall": Color(0.3, 0.3, 0.36), "wall_accent": Color(1.0, 0.76, 0.2), "wall_style": "glass",
		"building": Color(0.08, 0.08, 0.12), "window": Color(1.0, 0.7, 0.25), "towers": 18,
		"wood": Color(0.35, 0.22, 0.12), "metal": Color(0.5, 0.52, 0.56),
		"paints": [Color(0.7, 0.55, 0.15), Color(0.5, 0.1, 0.12), Color(0.2, 0.2, 0.28)],
		"marble": Color(0.7, 0.68, 0.62), "platform": Color(0.32, 0.32, 0.38),
		"sky": Color(0.1, 0.07, 0.14), "fog": Color(0.16, 0.1, 0.2), "ambient": Color(0.5, 0.42, 0.55),
		"sun": Color(0.95, 0.75, 0.6), "kinds": ["safe", "safe", "pillar", "crate_big", "counter", "statue"],
	},
]


static func theme_for(index: int, kind: String) -> Dictionary:
	if kind == Scaling.KIND_BOSS:
		return THEMES[3]
	return THEMES[(index + Scaling.cycle_of(index)) % 3]


static func half_for(kind: String) -> float:
	return 30.0 if kind == Scaling.KIND_BOSS else 26.0


## Construye todo bajo 'root'. Devuelve {"circles": Array[Vector3(x,z,r)], "half": float, "env": WorldEnvironment}
static func build(root: Node3D, index: int, kind: String, rng: RandomNumberGenerator) -> Dictionary:
	var pal := theme_for(index, kind)
	var half := half_for(kind)
	var q: Dictionary = Config.quality()
	# --- entorno ---
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = pal["sky"]
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = pal["ambient"]
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = pal["fog"]
	env.fog_density = 0.0045
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = pal["sun"]
	sun.light_energy = 1.05
	sun.rotation_degrees = Vector3(-52.0, 38.0 + index * 17.0, 0.0)
	sun.shadow_enabled = bool(q["shadows"])
	sun.directional_shadow_max_distance = 60.0
	root.add_child(sun)
	# --- suelo, muros, horizonte ---
	var floor_mi := Mats.mesh_instance(PropsFactory.floor_mesh(half, pal, rng), Mats.world_material(), root)
	floor_mi.name = "Floor"
	var wall_mi := Mats.mesh_instance(PropsFactory.wall_visual(half, pal, rng), Mats.world_material(), root)
	wall_mi.name = "WallVisual"
	var sky_mi := Mats.mesh_instance(PropsFactory.skyline(half, pal, rng), Mats.world_material(), root)
	sky_mi.name = "Skyline"
	sky_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in PropsFactory.wall_colliders(half):
		root.add_child(c)
	# --- plataformas y obstáculos ---
	var circles: Array = [Vector3(0, 0, 7.0)]   # zona de aparición del jugador libre
	var plat_count := 0 if kind == Scaling.KIND_SURVIVAL else (1 if kind == Scaling.KIND_BOSS else rng.randi_range(1, 2))
	for i in plat_count:
		var sx := rng.randf_range(6.0, 9.0)
		var sz := rng.randf_range(5.0, 7.0)
		var h := rng.randf_range(1.1, 1.7)
		var plat := PropsFactory.make_platform(sx, sz, h, pal, rng)
		var fp: Vector2 = plat.get_meta("footprint")
		var pos := _free_spot(circles, half - fp.y * 0.5 - 2.0, maxf(fp.x, fp.y) * 0.5, rng, 14.0)
		if pos == Vector3.INF:
			plat.queue_free()
			continue
		plat.position = Vector3(pos.x, 0, pos.z)
		root.add_child(plat)
		circles.append(Vector3(pos.x, pos.z, maxf(fp.x, fp.y) * 0.5))
	var count := mini(8 + index / 2 + (4 if kind == Scaling.KIND_SURVIVAL else 0), 18)
	if kind == Scaling.KIND_BOSS:
		count = 8
	var kinds: Array = pal["kinds"]
	for i in count:
		var k: String = kinds[rng.randi() % kinds.size()]
		var ob := PropsFactory.make_obstacle(k, rng, pal)
		var size: Vector3 = ob["size"]
		var r := maxf(size.x, size.z) * 0.5 + 0.4
		var pos := _free_spot(circles, half - 3.0, r, rng, 0.0)
		if pos == Vector3.INF:
			(ob["node"] as Node).queue_free()
			continue
		var n: Node3D = ob["node"]
		n.position = Vector3(pos.x, 0, pos.z)
		n.rotation.y = rng.randf() * TAU if k in ["statue", "tank", "pillar"] else float(rng.randi() % 4) * PI * 0.5 + rng.randf_range(-0.2, 0.2)
		root.add_child(n)
		circles.append(Vector3(pos.x, pos.z, r))
	return {"circles": circles, "half": half, "env": we, "pal": pal}


## Busca un hueco libre (centro, radio) dentro de ±limit. Devuelve Vector3.INF si falla.
static func _free_spot(circles: Array, limit: float, radius: float, rng: RandomNumberGenerator, extra: float) -> Vector3:
	for _t in 40:
		var x := rng.randf_range(-limit, limit)
		var z := rng.randf_range(-limit, limit)
		var ok := true
		for c in circles:
			var dx: float = x - c.x
			var dz: float = z - c.y
			var rr: float = c.z + radius + 0.9 + extra * 0.0
			if dx * dx + dz * dz < rr * rr:
				ok = false
				break
		if ok:
			return Vector3(x, 0, z)
	return Vector3.INF
