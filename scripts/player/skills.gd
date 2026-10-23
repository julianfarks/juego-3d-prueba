class_name Skills
extends Node
## Habilidades del abogado. Cada una tiene comportamiento, alcance, enfriamiento,
## coste de recurso (Expediente) y efectos propios, modificados por las mejoras (Build).
##   slot 0  Lanzamiento de Maletín (primaria: bumerán 3D, ver CaseThrow)
##   slot 1  Documentos Teledirigidos (proyectiles que persiguen)
##   slot 2  Sello Mágico          (automático: se deposita al final de la ida del maletín)
##   slot 3  Objeción              (automática: escudo + onda al estar herido)

signal cooldown_fired(slot: int)
signal denied(slot: int, reason: String)

const SLOT_NAMES := ["slam", "docs", "seal", "barrier"]

var player: CharacterBody3D
var cd: Array[float] = [0.0, 0.0, 0.0, 0.0]
var cd_max: Array[float] = [0.55, 4.0, 7.5, 11.0]
var energy := 100.0
var energy_max := 100.0

var combo_stacks := 0
var combo_timer := 0.0
var dodge_haste_t := 0.0
var skill_haste_t := 0.0
var takeover_t := 12.0
var takeover_ready := false
var _double_pending := false
var barrier_hp := 0.0
var barrier_t := 0.0
var barrier_absorbed := 0.0
var barrier_visual: MeshInstance3D = null
var barrier_active := false
var _pending: Array = []
var _zones: Array = []
var _energy_kill_budget := 25.0
var _passive_acc := 0.0
var auto_aim := true
var practice := false        # en la Sala Central la energía no se agota (para probar habilidades)


func setup(p: CharacterBody3D) -> void:
	player = p
	barrier_visual = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.9
	sm.height = 3.8
	sm.radial_segments = 14
	sm.rings = 8
	barrier_visual.mesh = sm
	barrier_visual.material_override = Mats.fx_material(Color(0.4, 0.75, 1.0, 0.28), true)
	barrier_visual.position = Vector3(0, 0.95, 0)
	barrier_visual.visible = false
	barrier_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	player.add_child(barrier_visual)


func reset() -> void:
	for i in 4:
		cd[i] = 0.0
	energy = energy_max
	combo_stacks = 0
	combo_timer = 0.0
	dodge_haste_t = 0.0
	skill_haste_t = 0.0
	takeover_t = 12.0
	takeover_ready = false
	barrier_hp = 0.0
	barrier_t = 0.0
	barrier_active = false
	_pending.clear()
	if GameState.case_throw != null:
		GameState.case_throw.clear_all()            # el lanzamiento diferido (_pending) se acaba de borrar: nada debe quedar a medias
	for z in _zones:
		if z.get("fx") != null and GameState.fx != null:
			GameState.fx.cancel(z["fx"])
	_zones.clear()
	if barrier_visual != null:
		barrier_visual.visible = false


# ----------------------------------------------------------------- utilidades
func attack_speed_mult() -> float:
	return _attack_speed_base() + Perks.buff("haste")


func _attack_speed_base() -> float:
	var b: Build = GameState.build
	var m := 1.0 + b.s("atk_speed")
	if dodge_haste_t > 0.0:
		m += b.s("dodge_haste")
	if skill_haste_t > 0.0:
		m += b.s("skill_haste")
	return minf(m, 2.8)


func cdr() -> float:
	return minf(GameState.build.s("cdr"), 0.6)


func cd_fraction(slot: int) -> float:
	if cd_max[slot] <= 0.001:
		return 0.0
	return clampf(cd[slot] / cd_max[slot], 0.0, 1.0)


func skill_cost(slot: int) -> float:
	var cut := 1.0 - minf(GameState.build.s("cost_cut"), 0.5)
	match slot:
		1: return float(Config.SKILLS["docs"]["cost"]) * cut
		2: return float(Config.SKILLS["seal"]["cost"]) * cut
		3: return float(Config.SKILLS["barrier"]["cost"]) * cut
	return 0.0


## Reducción de enfriamiento efectiva de una habilidad (general + específica de esa habilidad).
func cd_cut(key: String) -> float:
	return minf(cdr() + GameState.build.s(key), 0.75)


func reduce_cooldowns(seconds: float) -> void:
	for i in range(1, 4):
		cd[i] = maxf(0.0, cd[i] - seconds)


func add_energy_limited(amount: float) -> void:
	if _energy_kill_budget <= 0.0:
		return
	var a := minf(amount, _energy_kill_budget)
	_energy_kill_budget -= a
	energy = minf(energy_max, energy + a)


func aim_dir(search_range := 7.0) -> Vector3:
	var pp: Vector3 = player.global_position
	if auto_aim:
		var e := Combat.nearest_enemy(pp, search_range)
		if e != null:
			var d: Vector3 = e.global_position - pp
			d.y = 0.0
			if d.length() > 0.05:
				return d.normalized()
	return player.facing_dir()


func _after(t: float, fn: Callable) -> void:
	_pending.append({"t": t, "fn": fn})


# -------------------------------------------------------------------- bucle
func update(delta: float) -> void:
	var b: Build = GameState.build
	energy_max = float(Config.PLAYER["energy_max"]) + b.s("energy_max_add")
	energy = minf(energy_max, energy + float(Config.PLAYER["energy_regen"]) * (1.0 + b.s("energy_regen_pct")) * delta)
	_energy_kill_budget = minf(25.0, _energy_kill_budget + 25.0 * delta)
	for i in 4:
		if cd[i] > 0.0:
			cd[i] = maxf(0.0, cd[i] - delta * (attack_speed_mult() if i == 0 else 1.0))
	if combo_timer > 0.0:
		combo_timer -= delta
		if combo_timer <= 0.0:
			combo_stacks = 0
	dodge_haste_t = maxf(0.0, dodge_haste_t - delta)
	skill_haste_t = maxf(0.0, skill_haste_t - delta)
	# Adquisición Hostil
	if b.s("takeover") > 0.0 and not takeover_ready:
		takeover_t -= delta
		if takeover_t <= 0.0:
			takeover_ready = true
			GameState.toast_msg("¡Adquisición lista! Tu próximo golpe es una MEGA onda", Color(1.0, 0.8, 0.2))
			AudioManager.sfx("levelup")
	# Horas facturables
	if b.s("passive_coins") > 0.0 and Combat.arena_enemies().size() > 0:
		_passive_acc += b.s("passive_coins") * delta
		if _passive_acc >= 1.0:
			var n := int(_passive_acc)
			_passive_acc -= n
			GameState.add_coins(n, false)
	# acciones pendientes
	var i2 := _pending.size() - 1
	while i2 >= 0:
		_pending[i2]["t"] -= delta
		if _pending[i2]["t"] <= 0.0:
			var fn: Callable = _pending[i2]["fn"]
			_pending.remove_at(i2)
			if fn.is_valid():
				fn.call()
		i2 -= 1
	_update_zones(delta)
	_update_barrier(delta)
	_auto_barrier_check()


# ------------------------------------------------------------------ lanzar
func try_cast(slot: int) -> bool:
	if not player.alive or player.stunned():
		return false
	if cd[slot] > 0.0:
		return false
	match slot:
		0: return _cast_slam()
		1: return _cast_docs()
		2, 3: return false          # SELLO y OBJECIÓN ya no son botones: se activan solos
	return false


func _pay(slot: int) -> bool:
	if practice:
		energy = energy_max
	var cost := skill_cost(slot)
	if energy < cost:
		denied.emit(slot, "energy")
		AudioManager.sfx("deny", -6.0)
		return false
	energy -= cost
	var b: Build = GameState.build
	var hpc := b.s("skill_hp_cost")
	if hpc > 0.0:
		player.hp = maxf(1.0, player.hp - hpc)
		player.emit_hp()
	return true


func _after_secondary() -> void:
	var b: Build = GameState.build
	Perks.fire("skill", {})
	if b.s("skill_haste") > 0.0:
		skill_haste_t = 3.0
	if b.s("energy_zone") > 0.0:
		_add_energy_zone(player.global_position)
	cooldown_fired.emit(0)


## Parámetro de la herramienta principal equipada (Maletín, Mazo, Pluma…); ver LoadoutDB.
func _wp(key: String, default_value: float) -> float:
	var wp: Dictionary = GameState.weapon_params
	return float(wp.get(key, default_value))


## ATACAR: lanza el maletín como un bumerán (ver CaseThrow). Ya no hay golpe cuerpo a cuerpo.
func _cast_slam() -> bool:
	var ct = GameState.case_throw
	if ct == null or not ct.can_throw():
		return false                       # el maletín aún no ha vuelto a la mano: no hay lanzamientos infinitos
	var amult := attack_speed_mult()
	cd_max[0] = float(Config.SKILLS["slam"]["cd"]) * _wp("cd_x", 1.0) * (1.0 - minf(GameState.build.s("cd_slam"), 0.5))
	cd[0] = cd_max[0]  # update() lo descuenta más rápido cuanta más velocidad de ataque haya
	var dir := aim_dir(float(ct.make_profile()["range"]))
	player.face_dir(dir, 0.4)
	var dur := clampf(cd_max[0] / amult * 0.6, 0.18, 0.4)
	player.rig.play("throw", dur)
	var is_mega := takeover_ready
	if is_mega:
		takeover_ready = false
		takeover_t = 12.0
	ct.mark_pending(true)
	# el maletín sale de la mano en el instante del latigazo de la animación
	_after(dur * 0.4, func():
		ct.mark_pending(false)
		if player.alive:
			ct.throw_case(dir, is_mega))
	cooldown_fired.emit(0)
	return true


## Sello Mágico automático: ya no tiene botón; se deposita en el punto más lejano del recorrido del maletín.
func auto_seal(pos: Vector3) -> void:
	if cd[2] > 0.0 or not player.alive:
		return
	var b: Build = GameState.build
	cd_max[2] = float(Config.SKILLS["seal"]["cd"]) * (1.0 - cd_cut("cd_seal"))
	cd[2] = cd_max[2]
	var radius: float = float(Config.SKILLS["seal"]["radius"]) * Combat.area_mult() * (1.0 + b.s("seal_radius"))
	var count := 1 + int(b.s("seal_extra"))
	for i in count:
		var p2 := Vector3(pos.x, 0.0, pos.z)
		if i > 0:
			var ang := randf() * TAU
			p2 += Vector3(cos(ang), 0, sin(ang)) * randf_range(3.0, 5.0)
		_after(0.05 + 0.12 * i, func(): _place_seal(p2, radius))
	Perks.fire("skill", {})


## Objeción automática: ya no tiene botón; salta sola cuando estás herido y está lista.
func _auto_barrier_check() -> void:
	if cd[3] > 0.0 or barrier_active or not player.alive:
		return
	if player.hp <= player.max_hp * 0.45 and not Combat.enemies_in_radius(player.global_position, 6.5).is_empty():
		_cast_barrier()


func _echo(center: Vector3, radius: float, dmg: float) -> void:
	if not player.alive:
		return
	var fx = GameState.fx
	if fx != null:
		fx.ring(center, radius, Color(0.6, 0.85, 1.0, 0.7), 0.4, 0.5)
	AudioManager.sfx_at("swing", center, -9.0)          # sonido de lanzamiento; los impactos suenan por enemigo golpeado
	var list := Combat.enemies_in_radius(center, radius)
	for e in list:
		var away: Vector3 = e.global_position - center
		away.y = 0.0
		away = away.normalized() if away.length() > 0.05 else Vector3.FORWARD
		Combat.player_hit(e, dmg, {"src": "echo", "knock": away * 3.0, "area_hits": list.size(), "flat": false})
	if GameState.build.s("syn_echo_chain") > 0.0 and list.size() > 0:
		Combat.chain_lightning(list[randi() % list.size()], dmg * 0.8, 3 + int(GameState.build.s("chain_count")))


func _cast_docs() -> bool:
	if not _pay(1):
		return false
	var b: Build = GameState.build
	cd_max[1] = float(Config.SKILLS["docs"]["cd"]) * (1.0 - cd_cut("cd_docs"))
	cd[1] = cd_max[1]
	var count: int = mini(int(Config.SKILLS["docs"]["count"]) + int(b.s("docs_extra")), 36)
	var dmg: float = float(Config.SKILLS["docs"]["dmg"])
	var speed: float = float(Config.SKILLS["docs"]["speed"]) * (1.0 + b.s("docs_speed"))
	var dir := aim_dir(24.0)
	player.face_dir(dir, 0.35)
	player.rig.play("cast", 0.45)
	AudioManager.sfx("docs")
	# objetivos: los más cercanos
	var targets: Array = []
	var pool := Combat.arena_enemies().duplicate()
	pool = pool.filter(func(x): return is_instance_valid(x))
	pool.sort_custom(func(a, c): return a.global_position.distance_squared_to(player.global_position) < c.global_position.distance_squared_to(player.global_position))
	for e in pool:
		if is_instance_valid(e) and e.alive and e.global_position.distance_to(player.global_position) < 26.0:
			targets.append(e)
		if targets.size() >= count:
			break
	var from: Vector3 = player.global_position + Vector3(0, 1.35, 0)
	for i in count:
		var spread := (float(i) - float(count - 1) * 0.5) * 0.3
		var d := dir.rotated(Vector3.UP, spread)
		var tgt: Node3D = null
		if not targets.is_empty():
			tgt = targets[i % targets.size()]
		_after(0.12 + 0.045 * i, func(): _launch_doc(from, d, dmg, tgt, speed))
	_after_secondary()
	return true


func _launch_doc(from: Vector3, d: Vector3, dmg: float, tgt: Node3D, speed: float) -> void:
	if not player.alive or GameState.projectiles == null:
		return
	var origin: Vector3 = player.global_position + Vector3(0, 1.35, 0) + d * 0.7
	GameState.projectiles.fire_doc(origin, d + Vector3(0, 0.25, 0), dmg, tgt, speed, {"src": "docs", "skill": true, "flat": true,
		"pierce": int(GameState.build.s("docs_pierce")), "turn_add": GameState.build.s("docs_turn")})


func _place_seal(pos: Vector3, radius: float) -> void:
	if not player.alive:
		return
	var b: Build = GameState.build
	var dur: float = float(Config.SKILLS["seal"]["duration"]) * (1.0 + b.s("seal_time"))
	var fxitem = null
	if GameState.fx != null:
		fxitem = GameState.fx.zone(pos, radius, dur, Color(0.65, 0.35, 1.0))
		GameState.fx.ring(pos, radius, Color(0.8, 0.6, 1.0, 0.8), 0.4, 0.5)
	AudioManager.sfx_at("seal", pos, -2.0)
	_zones.append({"pos": pos, "radius": radius, "t": 0.0, "dur": dur, "tick": 0.0, "interval": float(Config.SKILLS["seal"]["tick"]),
		"dmg": float(Config.SKILLS["seal"]["dmg"]), "kind": "seal", "fx": fxitem, "freeze": b.s("syn_cold_zone") > 0.0})


func _add_energy_zone(pos: Vector3) -> void:
	var b: Build = GameState.build
	var radius: float = 3.6 * Combat.area_mult()
	var dur := 3.5
	var fxitem = null
	if GameState.fx != null:
		fxitem = GameState.fx.zone(pos, radius, dur, Color(0.3, 0.9, 1.0))
	_zones.append({"pos": pos, "radius": radius, "t": 0.0, "dur": dur, "tick": 0.0, "interval": 0.5,
		"dmg": float(Config.SKILLS["slam"]["dmg"]) * b.s("energy_zone") * 0.6, "kind": "energy", "fx": fxitem, "freeze": b.s("syn_cold_zone") > 0.0})


func _update_zones(delta: float) -> void:
	var i := _zones.size() - 1
	while i >= 0:
		var z: Dictionary = _zones[i]
		z["t"] += delta
		z["tick"] += delta
		if z["tick"] >= z["interval"]:
			z["tick"] = 0.0
			var list := Combat.enemies_in_radius(z["pos"], z["radius"])
			for e in list:
				Combat.player_hit(e, z["dmg"], {"src": "zone", "skill": z["kind"] == "seal", "flat": false, "area_hits": list.size(), "no_crit": z["kind"] != "seal", "proc": z["kind"] == "seal"})
				if is_instance_valid(e) and e.alive:
					e.apply_slow(0.45, 0.9)
					if z["freeze"] and randf() < 0.12 and not e.is_boss:
						e.apply_freeze(0.9)
		if z["t"] >= z["dur"]:
			_zones.remove_at(i)
		i -= 1


func _cast_barrier() -> bool:
	var b: Build = GameState.build
	cd_max[3] = float(Config.SKILLS["barrier"]["cd"]) * (1.0 - cd_cut("cd_barrier"))
	cd[3] = cd_max[3]
	player.rig.play("barrier", 0.6)
	var radius: float = float(Config.SKILLS["barrier"]["radius"]) * Combat.area_mult()
	var dmg: float = float(Config.SKILLS["barrier"]["dmg"])
	var knock: float = float(Config.SKILLS["barrier"]["knock"])
	var center: Vector3 = player.global_position
	barrier_hp = (float(Config.SKILLS["barrier"]["shield"]) + b.s("shield_max") * 0.5) * (1.0 + b.s("barrier_hp_pct"))
	barrier_t = float(Config.SKILLS["barrier"]["duration"]) * (1.0 + b.s("barrier_time"))
	barrier_absorbed = 0.0
	barrier_active = true
	barrier_visual.visible = true
	AudioManager.sfx("barrier")
	var fx = GameState.fx
	if fx != null:
		fx.ring(center, radius, Color(0.5, 0.8, 1.0, 0.9), 0.4, 0.5)
		fx.ring(center, radius * 0.6, Color(1, 1, 1, 0.5), 0.3, 0.3)
	var list := Combat.enemies_in_radius(center, radius)
	for e in list:
		var away: Vector3 = e.global_position - center
		away.y = 0.0
		away = away.normalized() if away.length() > 0.05 else Vector3.FORWARD
		Combat.player_hit(e, dmg, {"src": "barrier", "skill": true, "knock": away * knock, "stagger": 0.6, "area_hits": list.size()})
		if is_instance_valid(e) and e.alive:
			e.apply_slow(0.6, 1.2)
	if GameState.cam != null:
		GameState.cam.shake(0.3)
	_after_secondary()
	return true


## Devuelve el daño que NO absorbe la barrera.
func absorb(amount: float) -> float:
	if not barrier_active or barrier_hp <= 0.0:
		return amount
	var used := minf(barrier_hp, amount)
	barrier_hp -= used
	barrier_absorbed += used
	if GameState.fx != null:
		GameState.fx.burst(player.global_position + Vector3(0, 1, 0), Color(0.5, 0.85, 1.0), 4, 3.0, 0.1, 0.3)
	AudioManager.sfx("shield", -6.0)
	if barrier_hp <= 0.0:
		_end_barrier()
	return amount - used


func _update_barrier(delta: float) -> void:
	if barrier_t > 0.0:
		barrier_t -= delta
		if barrier_visual != null:
			barrier_visual.scale = Vector3.ONE * (1.0 + 0.03 * sin(Time.get_ticks_msec() * 0.02))
		if barrier_t <= 0.0:
			_end_barrier()


func _end_barrier() -> void:
	if not barrier_active:
		return
	barrier_active = false
	if barrier_visual != null:
		barrier_visual.visible = false
	barrier_hp = 0.0
	barrier_t = 0.0
	var b: Build = GameState.build
	if b.s("barrier_blast") > 0.0 and barrier_absorbed > 0.0:
		var dmg := (barrier_absorbed + 25.0) * b.s("barrier_blast")
		Combat.explode(player.global_position, 6.0 * Combat.area_mult(), dmg, {"src": "barrier_blast"})
	barrier_absorbed = 0.0
