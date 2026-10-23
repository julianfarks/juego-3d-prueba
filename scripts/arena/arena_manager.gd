class_name Arena
extends Node3D
## Gestor de una arena: construye el escenario, ejecuta oleadas/objetivos, recicla enemigos (pooling),
## suelta monedas, y al terminar genera cofre, portal y (según la zona) tienda.
## Regla central: la arena NO se completa mientras haya enemigos obligatorios vivos o pendientes.

signal chest_opened(min_rarity: int)
signal portal_entered
signal shop_requested
signal cleared(index: int)

enum Phase { IDLE, INTRO, FIGHT, CLEARED }

var index := 0
var kind := "elimination"
var half := 26.0
var phase := Phase.IDLE
var rng := RandomNumberGenerator.new()

var world_root: Node3D
var enemy_root: Node3D
var pickup_root: Node3D
var circles: Array = []
var pal: Dictionary = {}

var active: Array = []                 # enemigos en escena (vivos o muriendo)
var pool: Dictionary = {}              # kind -> Array[Enemy] libres
var _queue: Array = []                 # tipos pendientes de aparecer
var _plan: Dictionary = {}
var _wave_i := -1
var _wave_size := 0
var _wave_t := 0.0
var _spawn_t := 0.0
var _intro_t := 0.0
var _survival_left := 0.0
var _boss_spawned := false
var _boss_ref: Enemy = null
var _hazard_t := 4.0
var _hazards: Array = []               # {pos, t, r}
var _coins: Array = []
var _coin_pool: Array = []
var _coin_mat: Material
var _coin_mesh: ArrayMesh
var _chest: Interactable
var _chest_lid: Node3D
var _portal: Interactable
var _portal_vis: Dictionary = {}
var _shop: Interactable
var _cleared_t := 0.0
var _boss_dead_t := -1.0
var _coin_sfx_t := 0.0
var chest_taken := false
var seed_used := 0                     # semilla de esta arena (se guarda para reconstruirla al cargar)


func _ready() -> void:
	enemy_root = Node3D.new()
	enemy_root.name = "Enemies"
	add_child(enemy_root)
	pickup_root = Node3D.new()
	pickup_root.name = "Pickups"
	add_child(pickup_root)
	GameState.arena = self


## Objetivos de práctica de la Sala Central (muñecos). Si hay alguno, el combate apunta a ellos.
var practice_targets: Array = []


func get_enemies() -> Array:
	return practice_targets if not practice_targets.is_empty() else active


func alive_count() -> int:
	var n := 0
	for e in active:
		if is_instance_valid(e) and e.alive:
			n += 1
	return n


## Prepara y arranca la arena 'idx'. Devuelve la posición de aparición del jugador.
func start(idx: int, seed_value := -1) -> Vector3:
	_teardown()
	index = idx
	kind = Scaling.kind_of(idx)
	seed_used = seed_value if seed_value >= 0 else (randi() & 0x7fffffff)
	rng.seed = seed_used
	GameState.arena = self
	GameState.arena_index = idx
	world_root = Node3D.new()
	world_root.name = "World"
	add_child(world_root)
	var data := ArenaBuilder.build(world_root, idx, kind, rng)
	circles = data["circles"]
	half = data["half"]
	pal = data["pal"]
	_plan = WaveDirector.plan(kind, idx, rng)
	_wave_i = -1
	_queue.clear()
	_boss_spawned = false
	_boss_ref = null
	_boss_dead_t = -1.0
	_survival_left = float(_plan["survival_time"])
	_hazard_t = 5.0
	phase = Phase.INTRO
	_intro_t = 2.4
	chest_taken = false
	_cleared_t = 0.0
	GameState.arena_started.emit(idx, kind)
	Perks.fire("arena_start", {})
	_announce()
	GameState.objective_changed.emit(_objective_text(), 0.0)
	return Vector3(0, 0.3, 0)


func _announce() -> void:
	var names := {
		"elimination": "ELIMINACIÓN", "survival": "SUPERVIVENCIA", "challenge": "DESAFÍO ESPECIAL",
		"elite": "ARENA DE ÉLITE", "boss": "¡JEFE DE ZONA!",
	}
	GameState.toast_msg("%s — %s" % [names.get(kind, kind), pal.get("name", "")], Color(1.0, 0.85, 0.3))


func _teardown() -> void:
	phase = Phase.IDLE
	_plan = {}
	_survival_left = 0.0
	for e in active:
		if is_instance_valid(e):
			e.set_physics_process(false)
			e.visible = false
			e._clear_tele()
			var p: Array = pool.get(e.kind, [])
			if not p.has(e):
				p.append(e)
			pool[e.kind] = p
	active.clear()
	for c in _coins:
		c["node"].visible = false
		_coin_pool.append(c["node"])
	_coins.clear()
	_hazards.clear()
	if GameState.projectiles != null:
		GameState.projectiles.clear_all()
	if GameState.fx != null:
		GameState.fx.clear_all()
	for n in get_tree().get_nodes_in_group("interactable"):
		n.queue_free()
	if world_root != null and is_instance_valid(world_root):
		world_root.queue_free()
		world_root = null
	_chest = null
	_portal = null
	_shop = null
	GameState.boss_bar.emit(false, "", 0.0, 1.0)


# ------------------------------------------------------------------ bucle principal
func _physics_process(delta: float) -> void:
	_update_coins(delta)
	_update_hazards(delta)
	if _portal != null and not _portal_vis.is_empty():
		_portal_vis["swirl"].rotation.z += delta * 1.6
		_portal_vis["swirl2"].rotation.z -= delta * 2.4
	match phase:
		Phase.INTRO:
			_intro_t -= delta
			if _intro_t <= 0.0:
				phase = Phase.FIGHT
				_next_wave()
		Phase.FIGHT:
			_fight(delta)
		Phase.CLEARED:
			_cleared_t += delta
	if _boss_dead_t >= 0.0:
		_boss_dead_t -= delta
		if _boss_dead_t < 0.0:
			_kill_leftovers()


func _fight(delta: float) -> void:
	_wave_t += delta
	var alive := alive_count()
	var cap: int = int(Config.quality()["max_enemies"])
	# --- supervivencia: flujo continuo + temporizador ---
	if bool(_plan["stream"]):
		_survival_left = maxf(0.0, _survival_left - delta)
		if _survival_left > 0.0:
			_spawn_t -= delta
			if _spawn_t <= 0.0 and alive < mini(cap, 8 + index):
				_spawn_t = Scaling.spawn_interval(index) * 0.8
				_spawn_enemy(WaveDirector.stream_pick(index, rng))
	else:
		# cola de la oleada actual
		if not _queue.is_empty():
			_spawn_t -= delta
			if _spawn_t <= 0.0 and alive < cap:
				_spawn_t = Scaling.spawn_interval(index) * (0.55 if _queue.size() > 6 else 0.9)
				_spawn_enemy(_queue.pop_front())
		# ¿siguiente oleada?
		elif _wave_i < (_plan["waves"] as Array).size() - 1:
			var thr := maxi(2, int(_wave_size * 0.25))
			if alive <= thr or _wave_t > 28.0:
				_next_wave()
		# jefe / minijefe (aparece al empezar, tras la primera pausa)
		if String(_plan["boss"]) != "" and not _boss_spawned:
			_boss_spawned = true
			_spawn_boss(String(_plan["boss"]))
	_update_objective(alive)
	# --- ¿completada? ---
	var waves_done := bool(_plan["stream"]) or (_queue.is_empty() and _wave_i >= (_plan["waves"] as Array).size() - 1)
	if String(_plan["boss"]) != "" and not _boss_spawned:
		waves_done = false
	if bool(_plan["stream"]) and _survival_left > 0.0:
		waves_done = false
	alive = alive_count()
	if waves_done and alive == 0 and _pending_spawns() == 0:
		_complete()


func _pending_spawns() -> int:
	return _queue.size()


func _next_wave() -> void:
	var waves: Array = _plan["waves"]
	if bool(_plan["stream"]):
		_wave_i = 0
		return
	_wave_i += 1
	_wave_t = 0.0
	if _wave_i >= waves.size():
		_wave_i = waves.size() - 1
		return
	_queue = (waves[_wave_i] as Array).duplicate()
	_wave_size = _queue.size()
	_spawn_t = 0.0
	if waves.size() > 1 and kind != Scaling.KIND_BOSS:
		GameState.toast_msg("Oleada %d / %d" % [_wave_i + 1, waves.size()], Color(1, 1, 1))
	AudioManager.sfx("alert", -6.0)


func _objective_text() -> String:
	match kind:
		"survival":
			return "Sobrevive %ds y elimina a los restantes" % int(ceil(_survival_left))
		"challenge":
			return "Derrota al Capataz Blindado"
		"elite":
			return "Elimina a los Capos Élite"
		"boss":
			return "Derrota a Don Capital"
	return "Elimina a todos los enemigos"


func _update_objective(alive: int) -> void:
	var prog := 0.0
	var txt := _objective_text()
	match kind:
		"survival":
			var total := float(_plan["survival_time"])
			prog = 1.0 - _survival_left / maxf(total, 1.0)
			txt = ("Sobrevive: %ds" % int(ceil(_survival_left))) if _survival_left > 0.0 else "Elimina a los restantes: %d" % alive
		_:
			var total_w := 0
			for w in _plan["waves"]:
				total_w += (w as Array).size()
			total_w += (1 if String(_plan["boss"]) != "" else 0)
			var remaining := _queue.size() + alive
			for wi in range(_wave_i + 1, (_plan["waves"] as Array).size()):
				remaining += ((_plan["waves"] as Array)[wi] as Array).size()
			prog = 1.0 - float(remaining) / maxf(1.0, float(total_w))
			txt = "%s (%d restantes)" % [_objective_text(), remaining]
	GameState.objective_changed.emit(txt, clampf(prog, 0.0, 1.0))


# ------------------------------------------------------------------ enemigos
func spawn_point(min_player_dist := 9.0) -> Vector3:
	var pl = GameState.player
	var pp: Vector3 = Vector3.ZERO if pl == null else pl.global_position
	var best := Vector3.ZERO
	var best_d := -1.0
	for _t in 24:
		var x := rng.randf_range(-half + 3.0, half - 3.0)
		var z := rng.randf_range(-half + 3.0, half - 3.0)
		var ok := true
		for c in circles:
			if c.x == 0.0 and c.y == 0.0 and c.z == 7.0:
				continue   # zona de aparición del jugador: sí se permite aparecer enemigos (se filtra por distancia)
			var dx: float = x - c.x
			var dz: float = z - c.y
			var rr: float = c.z + 0.9
			if dx * dx + dz * dz < rr * rr:
				ok = false
				break
		if not ok:
			continue
		var d := Vector2(x - pp.x, z - pp.z).length()
		if d >= min_player_dist:
			return Vector3(x, 0.3, z)
		if d > best_d:
			best_d = d
			best = Vector3(x, 0.3, z)
	return best if best_d >= 0.0 else Vector3(half * 0.6, 0.3, half * 0.6)


func _get_enemy(k: String) -> Enemy:
	var list: Array = pool.get(k, [])
	while not list.is_empty():
		var e: Enemy = list.pop_back()
		if is_instance_valid(e):
			return e
	var en := Enemy.new()
	en.name = "Enemy_" + k
	enemy_root.add_child(en)
	en.died.connect(_on_enemy_died)
	en.despawned.connect(_on_enemy_despawned)
	en.request_spawn.connect(_on_request_spawn)
	return en


func _spawn_enemy(k: String, at := Vector3.INF) -> Enemy:
	var pos := at if at != Vector3.INF else spawn_point()
	pos.x = clampf(pos.x, -half + 2.0, half - 2.0)
	pos.z = clampf(pos.z, -half + 2.0, half - 2.0)
	var e := _get_enemy(k)
	var affix := WaveDirector.roll_affix(index, k, rng)
	e.setup(k, index, affix, pos, 999.0)
	if not active.has(e):
		active.append(e)
	if k == "elite":
		GameState.run_stats["elites"] += 1
	return e


func _spawn_boss(k: String) -> void:
	var pl = GameState.player
	var pp: Vector3 = Vector3.ZERO if pl == null else pl.global_position
	var dir := Vector3(0, 0, -1) if pp.z > -1.0 else Vector3(0, 0, 1)
	var pos := Vector3(0, 0.3, 0) + dir * (half * 0.5)
	_boss_ref = _spawn_enemy(k, pos)
	AudioManager.play_music("boss")
	GameState.toast_msg("¡%s!" % _boss_ref.display_name, Color(1.0, 0.4, 0.3))
	AudioManager.sfx("boss_roar", -2.0)
	if GameState.cam != null:
		GameState.cam.shake(0.6)


func _on_request_spawn(k: String, pos: Vector3) -> void:
	if alive_count() >= int(Config.quality()["max_enemies"]) + 6:
		return
	_spawn_enemy(k, pos)


func _on_enemy_died(e: Enemy) -> void:
	# monedas: se reparten en varias para que se vea el botín
	var n := mini(maxi(1, e.coin_value), 7)
	var each := maxi(1, int(round(float(e.coin_value) / float(n))))
	for i in n:
		_drop_coin(e.global_position + Vector3(0, 0.8, 0), each)
	if e == _boss_ref and kind == Scaling.KIND_BOSS:
		_boss_dead_t = 1.2
		GameState.toast_msg("¡JEFE DERROTADO!", Color(1.0, 0.85, 0.3))
		AudioManager.sfx("victory")
	elif e == _boss_ref:
		GameState.toast_msg("¡Capataz derrotado!", Color(1.0, 0.85, 0.3))
		_boss_dead_t = 0.6


func _on_enemy_despawned(e: Enemy) -> void:
	active.erase(e)
	var p: Array = pool.get(e.kind, [])
	if not p.has(e):
		p.append(e)
	pool[e.kind] = p


func _kill_leftovers() -> void:
	for e in active.duplicate():
		if is_instance_valid(e) and e.alive:
			e.invuln_t = 0.0
			e.take_damage(e.hp + 1.0, {"src": "boss_death", "element": "phys", "knock": Vector3.ZERO})


## Herramienta de desarrollo: mata a todos los enemigos vivos.
func kill_all() -> void:
	_kill_leftovers()


# ------------------------------------------------------------------ monedas
func _drop_coin(pos: Vector3, value: int) -> void:
	if _coins.size() > 120:
		# demasiadas: fusiona el valor en la moneda más antigua
		_coins[0]["value"] += value
		return
	if _coin_mat == null:
		_coin_mat = Mats.world_material()
		_coin_mesh = PropsFactory.coin_mesh()
	var node: MeshInstance3D = null
	if not _coin_pool.is_empty():
		node = _coin_pool.pop_back()
	else:
		node = Mats.mesh_instance(_coin_mesh, _coin_mat, pickup_root)
	node.visible = true
	node.global_position = pos
	var a := rng.randf() * TAU
	var vel := Vector3(cos(a) * rng.randf_range(1.5, 3.5), rng.randf_range(4.0, 6.5), sin(a) * rng.randf_range(1.5, 3.5))
	_coins.append({"node": node, "pos": pos, "vel": vel, "value": value, "t": 0.0})


func _update_coins(delta: float) -> void:
	_coin_sfx_t = maxf(0.0, _coin_sfx_t - delta)
	if _coins.is_empty():
		return
	var pl = GameState.player
	var pp: Vector3 = Vector3.ZERO
	var have_p: bool = pl != null and pl.alive
	if have_p:
		pp = pl.global_position + Vector3(0, 0.9, 0)
	var magnet := 4.5 + GameState.build.s("magnet")
	var i := _coins.size() - 1
	while i >= 0:
		var c: Dictionary = _coins[i]
		c["t"] += delta
		var pos: Vector3 = c["pos"]
		var vel: Vector3 = c["vel"]
		var to_player: bool = have_p and (pos.distance_to(pp) < magnet or c["t"] > 5.0 or phase == Phase.CLEARED)
		if to_player and c["t"] > 0.35:
			var dir := (pp - pos)
			var d := dir.length()
			vel = vel.lerp(dir.normalized() * (14.0 + c["t"] * 2.0), clampf(delta * 9.0, 0.0, 1.0))
			if d < 1.0:
				var got := GameState.add_coins(int(c["value"]))
				if _coin_sfx_t <= 0.0:
					AudioManager.sfx("coin", -6.0)
					_coin_sfx_t = 0.05
				if GameState.fx != null and got >= 3 and randf() < 0.35:
					GameState.fx.damage_number(pp + Vector3(0, 1.4, 0), "+%d" % got, Color(1.0, 0.85, 0.2), 0.8)
				(c["node"] as Node3D).visible = false
				_coin_pool.append(c["node"])
				_coins.remove_at(i)
				i -= 1
				continue
		else:
			vel.y -= 18.0 * delta
			if pos.y <= 0.3 and vel.y < 0.0:
				pos.y = 0.3
				vel.y = 0.0
				vel.x *= 0.85
				vel.z *= 0.85
		pos += vel * delta
		pos.x = clampf(pos.x, -half + 0.5, half - 0.5)
		pos.z = clampf(pos.z, -half + 0.5, half - 0.5)
		c["pos"] = pos
		c["vel"] = vel
		var nd: Node3D = c["node"]
		nd.global_position = pos
		nd.rotation.y += delta * 5.0
		i -= 1


# ------------------------------------------------------------------ peligros del desafío
func _update_hazards(delta: float) -> void:
	if phase == Phase.FIGHT and bool(_plan["hazards"]) and (kind == Scaling.KIND_CHALLENGE or _survival_left > 0.0 or kind == Scaling.KIND_SURVIVAL):
		_hazard_t -= delta
		var pl = GameState.player
		if _hazard_t <= 0.0 and pl != null and pl.alive and GameState.fx != null:
			_hazard_t = maxf(2.2, 6.0 - index * 0.14)
			var tgt: Vector3 = pl.global_position + Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-3, 3))
			tgt.x = clampf(tgt.x, -half + 2.0, half - 2.0)
			tgt.z = clampf(tgt.z, -half + 2.0, half - 2.0)
			var r := 2.8
			GameState.fx.telegraph_circle(tgt, r, 1.4, Color(1.0, 0.7, 0.1))
			_hazards.append({"pos": tgt, "t": 1.4, "r": r})
			AudioManager.sfx("telegraph", -8.0)
	var i := _hazards.size() - 1
	while i >= 0:
		var h: Dictionary = _hazards[i]
		h["t"] -= delta
		if h["t"] <= 0.0:
			var pl2 = GameState.player
			var hp: Vector3 = h["pos"]
			if GameState.fx != null:
				GameState.fx.ring(hp, h["r"], Color(1.0, 0.7, 0.15, 0.9), 0.35, 0.3)
				GameState.fx.burst(hp + Vector3(0, 0.5, 0), Color(1.0, 0.8, 0.3), 8, 6.0, 0.16, 0.5)
			AudioManager.sfx_at("explosion", hp, -4.0)
			if GameState.cam != null:
				GameState.cam.shake(0.3)
			if pl2 != null and pl2.alive:
				var d: Vector3 = pl2.global_position - hp
				d.y = 0.0
				if d.length() < h["r"] + 0.4:
					pl2.take_damage(12.0 * Scaling.dmg_mult(index), hp, {"src": "hazard"})
			_hazards.remove_at(i)
		i -= 1


# ------------------------------------------------------------------ final de arena
func _complete() -> void:
	phase = Phase.CLEARED
	GameState.run_stats["arenas"] += 1
	GameState.objective_changed.emit("¡Arena completada!", 1.0)
	GameState.arena_cleared.emit(index)
	AudioManager.sfx("victory", -4.0)
	if kind != Scaling.KIND_BOSS:
		AudioManager.play_music("combat")
	GameState.toast_msg("¡ARENA COMPLETADA!", Color(0.5, 1.0, 0.6))
	GameState.toast_msg("Abre el cofre y después cruza el portal", Color(1.0, 0.9, 0.4))
	var bld: Build = GameState.build
	var bonus := int(round(bld.s("clear_coins") + minf(float(GameState.coins) * bld.s("interest"), 40.0)))
	if bonus > 0:
		GameState.add_coins(bonus, false)
	Perks.fire("arena_clear", {})
	var heal := GameState.build.s("clear_heal")
	if heal > 0.0 and GameState.player != null:
		GameState.player.heal(GameState.player.max_hp * heal)
	_spawn_rewards()
	cleared.emit(index)


func _spawn_rewards() -> void:
	# posiciones de los premios reproducibles a partir de la semilla (para poder restaurarlas al cargar)
	rng.seed = (seed_used ^ 0x5EED5) & 0x7fffffff
	# cofre
	var tint := Color(0.4, 0.85, 1.0)
	var min_rarity := 0
	if kind == Scaling.KIND_ELITE or kind == Scaling.KIND_CHALLENGE:
		tint = Color(0.8, 0.45, 1.0)
		min_rarity = 1
	elif kind == Scaling.KIND_BOSS:
		tint = Color(1.0, 0.8, 0.25)
		min_rarity = 2
	var cv := PropsFactory.chest_node(tint)
	_chest = Interactable.new()
	_chest.kind = "chest"
	_chest.prompt = "Abrir cofre"
	_chest.action_text = "ABRIR"
	_chest.radius = 3.0
	_chest.setup_indicator("ABRIR", 2.7, Color(1.0, 0.9, 0.35))
	_chest.add_child(cv["root"])
	_chest_lid = cv["lid"]
	var cpos := _reward_spot(Vector3(-3.5, 0, 0))
	_chest.position = cpos
	_chest.callback = func(_i): _open_chest(min_rarity)
	world_root.add_child(_chest)
	if GameState.fx != null:
		GameState.fx.ring(cpos, 3.0, Color(tint.r, tint.g, tint.b, 0.9), 0.7, 0.3)
	# portal (se activa al abrir el cofre)
	var pv := PropsFactory.portal_node()
	_portal_vis = pv
	_portal = Interactable.new()
	_portal.kind = "portal"
	_portal.radius = 3.4
	_portal.enabled = false
	_portal.prompt = "Abre el cofre primero"
	_portal.action_text = "ENTRAR"
	_portal.setup_indicator("ABRE EL COFRE", 4.6, Color(0.8, 0.8, 0.9), false)
	_portal.ind_scale = 0.5
	_portal.add_child(pv["root"])
	_portal.position = _reward_spot(Vector3(4.5, 0, 0))
	_portal.callback = func(_i): _enter_portal()
	(pv["light"] as OmniLight3D).light_energy = 0.25
	(pv["swirl"] as MeshInstance3D).visible = false
	(pv["swirl2"] as MeshInstance3D).visible = false
	world_root.add_child(_portal)
	# tienda
	var zp := Scaling.zone_pos(index)
	if bool(Config.SHOP_AFTER_ZONE_INDEX[zp]):
		_shop = Interactable.new()
		_shop.kind = "shop"
		_shop.prompt = "Entrar a la tienda"
		_shop.action_text = "TIENDA"
		_shop.radius = 3.4
		_shop.setup_indicator("TIENDA", 3.4, Color(0.6, 1.0, 0.7))
		_shop.add_child(PropsFactory.shop_node())
		_shop.position = _reward_spot(Vector3(0, 0, 5.5))
		_shop.callback = func(_i): shop_requested.emit()
		world_root.add_child(_shop)


func _reward_spot(pref: Vector3) -> Vector3:
	var p := pref
	for _t in 12:
		var ok := true
		for c in circles:
			if c.z == 7.0 and c.x == 0.0 and c.y == 0.0:
				continue
			var dx: float = p.x - c.x
			var dz: float = p.z - c.y
			var rr: float = c.z + 2.4
			if dx * dx + dz * dz < rr * rr:
				ok = false
				break
		if ok:
			return p
		p = Vector3(rng.randf_range(-8, 8), 0, rng.randf_range(-8, 8))
	return pref


func _open_chest(min_rarity: int) -> void:
	if chest_taken or _chest == null:
		return      # cada cofre se abre una sola vez
	chest_taken = true
	_chest.enabled = false
	_chest.set_indicator("", Color.WHITE, false)
	AudioManager.sfx("chest")
	AudioManager.sfx("card", -3.0)
	var tw := create_tween()
	tw.tween_property(_chest_lid, "rotation:x", -1.9, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if GameState.fx != null:
		var cp := _chest.global_position + Vector3(0, 0.8, 0)
		GameState.fx.burst(cp, Color(1.0, 0.9, 0.4), 22, 7.0, 0.18, 0.8)
		GameState.fx.flash_sphere(cp, 1.8, Color(1.0, 0.9, 0.5, 0.75), 0.4)
		GameState.fx.ring(_chest.global_position, 3.4, Color(1.0, 0.9, 0.4, 0.9), 0.6, 0.3)
	GameState.toast_msg("¡Cofre abierto! Elige tu recompensa", Color(1.0, 0.9, 0.4))
	_activate_portal()
	chest_opened.emit(min_rarity)


## Enciende el portal (cuando el cofre ya se abrió).
func _activate_portal() -> void:
	if _portal == null:
		return
	_portal.enabled = true
	_portal.prompt = "Entrar al portal"
	_portal.set_indicator("ENTRAR", Color(0.85, 0.6, 1.0), true)
	(_portal_vis["light"] as OmniLight3D).light_energy = 1.4
	(_portal_vis["swirl"] as MeshInstance3D).visible = true
	(_portal_vis["swirl2"] as MeshInstance3D).visible = true
	AudioManager.sfx("portal", -4.0)


## Reconstruye una arena ya completada tras cargar una partida: aparecen el cofre y el portal.
## 'taken': el cofre ya se había abierto y sus cartas elegidas (el portal queda activo).
func restore_cleared(taken: bool) -> void:
	phase = Phase.CLEARED
	_queue.clear()
	GameState.objective_changed.emit("¡Arena completada!", 1.0)
	_spawn_rewards()
	if taken:
		chest_taken = true
		_chest.enabled = false
		_chest.set_indicator("", Color.WHITE, false)
		_chest_lid.rotation.x = -1.9
		_activate_portal()


func _enter_portal() -> void:
	if phase != Phase.CLEARED:
		return
	_portal.enabled = false
	portal_entered.emit()


## Herramienta de desarrollo / pruebas: fuerza el final de la arena.
func force_complete() -> void:
	_queue.clear()
	_kill_leftovers()
	_survival_left = 0.0
	_wave_i = 999
	_plan["waves"] = []
	if String(_plan["boss"]) != "":
		_boss_spawned = true
