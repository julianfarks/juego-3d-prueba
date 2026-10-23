class_name ArenaBuilder
extends RefCounted
## Construye proceduralmente el escenario de una arena a partir de su BIOMA (ver BiomeDB):
## entorno/luz, terreno con relieve y colisión (Terrain), perímetro, fondo en capas (BiomeScenery),
## plataformas con rampas y obstáculos del bioma (BiomeProps). La composición es deliberada: primero se
## reservan los huecos (jugador, recompensas, plataformas, obstáculos), luego el terreno se aplana donde hace falta.
## Devuelve datos de colocación para el spawn.

static func theme_for(index: int, kind: String) -> Dictionary:
	return BiomeDB.palette_for(index, kind)


static func half_for(kind: String) -> float:
	return 30.0 if kind == Scaling.KIND_BOSS else 26.0


## Construye todo bajo 'root'. Devuelve {"circles": Array[Vector3(x,z,r)], "half": float, "env": WorldEnvironment, "pal": Dictionary}
static func build(root: Node3D, index: int, kind: String, rng: RandomNumberGenerator) -> Dictionary:
	var pal := theme_for(index, kind)
	var half := half_for(kind)
	var biome_seed := int(rng.seed & 0xfffff)
	var we := BiomeScenery.environment(root, pal, index)
	# --- 1. reservar huecos: plataformas y obstáculos (los nodos se añaden cuando el terreno ya existe) ---
	var circles: Array = [Vector3(0, 0, 7.0)]   # zona de aparición del jugador libre
	var pending: Array = []                    # [{node, pos}]
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
		pending.append({"node": plat, "pos": Vector3(pos.x, 0, pos.z), "yaw": 0.0})
		circles.append(Vector3(pos.x, pos.z, maxf(fp.x, fp.y) * 0.5))
	var count := mini(8 + index / 2 + (4 if kind == Scaling.KIND_SURVIVAL else 0), 18)
	if kind == Scaling.KIND_BOSS:
		count = 8
	count += int(pal.get("extra_props", 0))
	var kinds: Array = pal["kinds"]
	for i in count:
		var k: String = kinds[rng.randi() % kinds.size()]
		var ob := BiomeProps.make(k, rng, pal)
		var size: Vector3 = ob["size"]
		var r := maxf(size.x, size.z) * 0.5 + 0.4
		var lane := String(pal.get("lane_kinds", "")).split(",").has(k)
		var pos := _free_spot(circles, half - 3.0, r, rng, 0.0, lane)
		if pos == Vector3.INF:
			(ob["node"] as Node).queue_free()
			continue
		var yaw := rng.randf() * TAU if k in ["statue", "tank", "pillar", "tree", "tree_big", "rock", "rock_red", "bush", "stump", "crystal", "cactus", "dead_tree", "tree_city", "mushrooms"] else float(rng.randi() % 4) * PI * 0.5 + rng.randf_range(-0.2, 0.2)
		if lane:
			# vehículos y barreras se alinean con la calle más cercana
			yaw = 0.0 if absf(pos.z) < absf(pos.x) else PI * 0.5
			yaw += rng.randf_range(-0.12, 0.12) + (PI if rng.randf() < 0.5 else 0.0)
		pending.append({"node": ob["node"], "pos": Vector3(pos.x, 0, pos.z), "yaw": yaw})
		circles.append(Vector3(pos.x, pos.z, r))
	# --- 2. terreno (se aplana alrededor de todo lo reservado) ---
	var flats: Array = []
	for i in range(1, circles.size()):
		flats.append(circles[i])
	flats.append(Vector3(-3.5, 0, 3.0))   # zonas de recompensa preferidas (cofre / portal / tienda)
	flats.append(Vector3(4.5, 0, 0.0))
	flats.append(Vector3(0, 5.5, 3.0))
	Terrain.configure(pal, half, biome_seed, flats)
	Terrain.build(root, pal)
	# --- 3. perímetro, colisiones y fondo ---
	var wall_mi := Mats.mesh_instance(BiomeScenery.walls(half, pal, rng), Mats.world_material(), root)
	wall_mi.name = "WallVisual"
	for c in BiomeScenery.wall_colliders(half):
		root.add_child(c)
	BiomeScenery.backdrop(root, half, pal, rng)
	BiomeScenery.ground_details(root, half, pal, rng, circles)
	# --- 4. colocar plataformas y obstáculos sobre el terreno ---
	for p in pending:
		var n: Node3D = p["node"]
		var pos: Vector3 = p["pos"]
		n.position = Vector3(pos.x, Terrain.ground_y(pos.x, pos.z), pos.z)
		n.rotation.y = float(p["yaw"])
		root.add_child(n)
	return {"circles": circles, "half": half, "env": we, "pal": pal}


## Busca un hueco libre (centro, radio) dentro de ±limit. Devuelve Vector3.INF si falla.
static func _free_spot(circles: Array, limit: float, radius: float, rng: RandomNumberGenerator, extra: float, lane := false) -> Vector3:
	for _t in 40:
		var x := rng.randf_range(-limit, limit)
		var z := rng.randf_range(-limit, limit)
		if lane:
			# sobre una de las dos calles (ejes), a un lado del carril central
			var off := rng.randf_range(1.6, 2.6) * (1.0 if rng.randf() < 0.5 else -1.0)
			if rng.randf() < 0.5:
				z = off
			else:
				x = off
			if absf(x) < 8.0 and absf(z) < 8.0:
				continue      # el cruce central queda despejado
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
