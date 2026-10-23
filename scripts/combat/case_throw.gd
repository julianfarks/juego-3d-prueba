class_name CaseThrow
extends Node3D
## ATAQUE PRINCIPAL: el abogado LANZA el maletín como un bumerán (ya no hay golpe cuerpo a cuerpo).
##
## Ciclo:  lanzamiento (anim + maletín de la mano se oculta) → IDA curva → [rebote entre enemigos / perforación /
## rebote por el entorno] → REGRESO curvo hacia la mano → recuperación (el maletín reaparece en la mano).
## Mientras no se recupera el maletín no se puede lanzar otro (sin lanzamientos infinitos ni maletines duplicados).
##
## Todas las mejoras `bc_*` se combinan en el MISMO impacto: `_impact()` ejecuta, en orden, daño normal (con crítico),
## explosión, fuegos artificiales, fragmentos, documentos, lluvia, rayo, marca, propagación de estados y onda;
## el maletín sigue después su trayectoria y al volver activa los efectos de retorno. Cada efecto respeta su
## probabilidad, su enfriamiento y los presupuestos de rendimiento (proyectiles, explosiones y brasas máximas).
##
## Daño, números y sonidos NO se calculan aquí: todo golpe pasa por Combat.player_hit / Combat.explode y por tanto por
## Feedback (número flotante + sonido) igual que el resto del juego.

const MAX_CASES := 7
const MAX_SECONDARY := 40            # fragmentos, minimaletines y cohetes vivos a la vez
const MAX_BLASTS_PER_SEC := 14       # explosiones de mejoras por segundo
const MAX_EMBERS := 24               # brasas del rastro de fuego
const HIT_Y := 1.15                  # altura de vuelo del maletín
const REHIT_BOUNCE := 0.45           # reimpacto sobre el mismo enemigo en modo rebote (s)
const SRC := "case"

class C extends RefCounted:
	var node: Node3D
	var pivot: Node3D
	var idx := 0
	var state := "out"               # out | bounce | ret
	var pos := Vector3.ZERO
	var vel := Vector3.ZERO
	var heading := Vector3.FORWARD
	var side := 1.0
	var curve_rate := 0.0
	var speed := 24.0
	var speed_cur := 24.0
	var range_m := 10.0
	var dist := 0.0
	var t := 0.0                     # tiempo en la fase actual
	var life := 0.0
	var radius := 0.75
	var dmg_mult := 1.0
	var pierce_left := 0
	var bounces_left := 0
	var bounces_done := 0
	var wall_left := 0.0
	var env_bounced := false
	var hits: Dictionary = {}        # id de enemigo -> instante del último impacto
	var impacts := 0
	var mega := false
	var main := false
	var sealed := false
	var trail_acc := 0.0
	var multi_acc := 0.0
	var beam_acc := 0.0
	var prof: Dictionary = {}

class S extends RefCounted:
	var node: Node3D
	var kind := ""                   # frag | mini | rocket
	var src := "frag"
	var pos := Vector3.ZERO
	var vel := Vector3.ZERO
	var life := 0.5
	var age := 0.0
	var dmg := 1.0
	var radius := 0.5
	var pierce := 0
	var hits: Array = []
	var from := Vector3.ZERO
	var to := Vector3.ZERO
	var dur := 0.7
	var frag_on_pop := false
	var prof: Dictionary = {}

var cases: Array[C] = []
var secondaries: Array[S] = []
var _sec_pool: Dictionary = {}
var _embers: Array = []              # {pos, t, tick, fx}
var _rain: Array = []                # {t, pos, dmg}
var _queued: Array = []              # lanzamientos escalonados {t, fn}
var _cd: Dictionary = {}             # enfriamientos internos de efectos
var _clock := 0.0
var _blast_times: Array[float] = []
var _pending_launch := false
var _pending_t := 0.0                 # seguro: si el lanzamiento diferido se pierde (p. ej. Skills.reset), no bloquea ATACAR
var _meshes: Dictionary = {}
var _shake_t := 0.0

## Ganchos de prueba / estadísticas
var record := false
var impact_log: Array = []
var counts := {"throws": 0, "impacts": 0, "catches": 0, "blasts": 0, "rockets": 0, "frags": 0, "minis": 0, "docs": 0,
	"rain": 0, "shock": 0, "marks": 0, "spreads": 0, "return_blasts": 0, "bounces_enemy": 0, "bounces_wall": 0,
	"embers": 0, "echo": 0, "skipped_budget": 0, "max_secondary": 0, "max_cases": 0}


func _ready() -> void:
	GameState.case_throw = self


# ============================================================================ API pública
func in_flight() -> bool:
	return not cases.is_empty() or _pending_launch or not _queued.is_empty()


func can_throw() -> bool:
	var p = GameState.player
	return p != null and is_instance_valid(p) and p.alive and not in_flight()


func _hand() -> Node3D:
	var p = GameState.player
	if p == null or p.rig == null:
		return null
	return p.rig.props.get("case", null)


func hand_pos() -> Vector3:
	var h := _hand()
	if h != null and is_instance_valid(h):
		return h.global_position + Vector3(0, 0.1, 0)
	var p = GameState.player
	return p.global_position + Vector3(0, HIT_Y, 0) if p != null else Vector3.ZERO


func _set_hand_visible(v: bool) -> void:
	var h := _hand()
	if h != null and is_instance_valid(h):
		h.visible = v


## Estadísticas del lanzamiento, congeladas al lanzar (no cambian si la build cambia en pleno vuelo).
func make_profile() -> Dictionary:
	var b: Build = GameState.build
	var wp: Dictionary = GameState.weapon_params
	var amult := 1.0
	if GameState.player != null and GameState.player.skills != null:
		amult = GameState.player.skills.attack_speed_mult()
	var big: bool = b.s("syn_big_boomerang") > 0.0
	var p := {}
	p["base"] = float(Config.SKILLS["slam"]["dmg"]) * float(wp.get("dmg_x", 1.0)) * (1.0 + b.s("bc_dmg")) * (1.4 if big else 1.0)
	p["range"] = 10.0 * float(wp.get("radius_x", 1.0)) * (1.0 + b.s("bc_range") + b.s("slam_radius"))
	p["size"] = (1.8 if big else 1.0) * (1.0 + b.s("bc_size") + 0.5 * b.s("slam_radius"))
	p["speed"] = 26.0 * (1.0 + b.s("bc_speed")) * (1.0 + (amult - 1.0) * 0.8)
	p["knock"] = float(Config.SKILLS["slam"]["knock"]) * float(wp.get("knock_x", 1.0)) * (1.0 + b.s("slam_knock")) * 0.45
	p["curve"] = clampf(float(wp.get("arc", 150.0)) / 150.0 + b.s("slam_arc") / 200.0, 0.35, 1.6)
	p["homing"] = clampf(b.s("bc_homing"), 0.0, 0.95)
	p["pierce"] = int(b.s("bc_pierce"))
	p["bounces"] = int(b.s("bc_bounce")) + (2 if b.s("syn_pinball") > 0.0 else 0)
	p["wall_t"] = (2.5 + b.s("bc_wall")) if b.s("bc_wall") > 0.0 else 0.0
	p["sharp"] = b.s("bc_sharp") > 0.0
	p["ret_mult"] = 0.5 + b.s("bc_sharp") if b.s("bc_sharp") > 0.0 else 0.0
	p["blast"] = b.s("bc_blast")
	p["blast_r"] = b.s("bc_blast_r")
	p["pyro"] = b.s("bc_pyro")
	p["pyro_n"] = int(b.s("bc_pyro_n"))
	p["frag"] = b.s("bc_frag")
	p["frag_dmg"] = b.s("bc_frag_dmg")
	p["docs"] = b.s("bc_docs")
	p["rain"] = b.s("bc_rain")
	p["rain_n"] = int(b.s("bc_rain_n"))
	p["shock"] = b.s("bc_shock")
	p["shock_n"] = int(b.s("bc_shock_n"))
	p["corr"] = b.s("bc_corr")
	p["spread"] = b.s("bc_spread")
	p["trail"] = b.s("bc_trail")
	p["multi"] = b.s("bc_multi")
	p["ret_blast"] = b.s("bc_return")
	p["ret_r"] = b.s("bc_return_r")
	p["catch_haste"] = b.s("bc_catch")
	p["echo"] = b.s("echo_wave")
	p["syn_pyro_frag"] = b.s("syn_pyro_frag") > 0.0
	p["syn_conductor"] = b.s("syn_conductor") > 0.0
	p["syn_return_fw"] = b.s("syn_return_fw") > 0.0
	p["syn_inferno_trail"] = b.s("syn_inferno_trail") > 0.0
	p["syn_pinball"] = b.s("syn_pinball") > 0.0
	return p


## Número y características de los maletines de un lanzamiento: [{mult, side, ang, delay, range_x}]
func plan_cases(p: Dictionary) -> Array:
	var b: Build = GameState.build
	var plan: Array = [{"mult": 1.0, "side": 1.0, "ang": 0.0, "delay": 0.0, "range_x": 1.0}]
	var extra := int(b.s("bc_cases"))
	if b.s("bc_double") > 0.0:
		plan.append({"mult": 0.6 + 0.12 * b.s("bc_double"), "side": -1.0, "ang": 0.0, "delay": 0.14, "range_x": 0.85})   # recorrido propio, curva opuesta
	if b.s("boomerang") > 0.0:
		plan.append({"mult": b.s("boomerang"), "side": -1.0, "ang": 0.0, "delay": 0.1, "range_x": 0.9})
	for i in extra:
		plan.append({"mult": 0.8, "side": 1.0 if i % 2 == 0 else -1.0, "ang": 0.0, "delay": 0.05 * float(i + 1), "range_x": 0.95})
	if b.s("slam_double") > 0.0 and randf() < b.s("slam_double"):
		plan.append({"mult": 0.8, "side": -1.0, "ang": 0.0, "delay": 0.28, "range_x": 0.9})
	while plan.size() > MAX_CASES:
		plan.pop_back()
	# abanico: reparte los ángulos de los maletines adicionales alrededor de la dirección de apuntado
	var n := plan.size()
	for i in n:
		var step := (i + 1) / 2                         # 0, +1, -1, +2, -2... (el maletín principal va al centro)
		plan[i]["ang"] = (float(step) * (1.0 if i % 2 == 1 else -1.0)) * deg_to_rad(16.0) if n > 1 else 0.0
	return plan


## Lanza el maletín (o el abanico de maletines). Devuelve false si no se puede.
func throw_case(dir: Vector3, mega := false) -> bool:
	if not can_throw():
		return false
	var p := make_profile()
	var plan := plan_cases(p)
	var origin := hand_pos()
	var target := Combat.nearest_enemy(GameState.player.global_position, float(p["range"]) + 2.0)
	var tdist := float(p["range"]) * 0.6
	if target != null:
		var td: Vector3 = target.global_position - GameState.player.global_position
		td.y = 0.0
		tdist = clampf(td.length(), 2.0, float(p["range"]))
	_set_hand_visible(false)
	counts["throws"] += 1
	for i in plan.size():
		var spec: Dictionary = plan[i]
		var delay: float = spec["delay"]
		if delay <= 0.0:
			_spawn_case(i, spec, p, dir, origin, tdist, mega and i == 0)
		else:
			_queued.append({"t": delay, "i": i, "spec": spec, "p": p, "dir": dir, "tdist": tdist})
	AudioManager.combat_sfx("throw", origin, -3.0, AudioManager.P_ELEM, 1.0, 0.06)
	return true


func _spawn_case(i: int, spec: Dictionary, p: Dictionary, dir: Vector3, origin: Vector3, tdist: float, mega: bool) -> void:
	if cases.size() >= MAX_CASES:
		return
	var c := C.new()
	c.idx = i
	c.main = i == 0
	c.prof = p
	c.mega = mega
	c.side = float(spec["side"])
	c.dmg_mult = float(spec["mult"]) * (float(GameState.build.s("takeover")) if mega else 1.0)
	c.speed = float(p["speed"])
	c.speed_cur = c.speed
	c.range_m = float(p["range"]) * float(spec["range_x"])
	c.radius = 0.75 * float(p["size"]) * (2.2 if mega else 1.0)
	c.pierce_left = int(p["pierce"])
	c.bounces_left = int(p["bounces"])
	c.wall_left = float(p["wall_t"])
	c.pos = Vector3(origin.x, HIT_Y, origin.z)
	var flat_dir := Vector3(dir.x, 0.0, dir.z).normalized() if Vector3(dir.x, 0.0, dir.z).length() > 0.01 else Vector3.FORWARD
	# arco: el ángulo total que gira en el trayecto es proporcional a la curvatura del arma
	var t_out := c.range_m / c.speed
	var total_turn := float(p["curve"]) * 0.9
	c.curve_rate = c.side * total_turn / t_out
	# compensación: el arco pasa por el objetivo apuntado (tangente inicial = mitad del giro hasta él)
	var comp := -c.side * float(p["curve"]) * 0.9 * (minf(tdist, c.range_m) / c.range_m) * 0.5
	c.heading = flat_dir.rotated(Vector3.UP, float(spec["ang"]) + comp)
	c.vel = c.heading * c.speed
	c.node = Node3D.new()
	c.pivot = Node3D.new()
	c.node.add_child(c.pivot)
	var mi := Mats.mesh_instance(ModelFactory.briefcase_mesh(), Mats.world_material(), c.pivot)
	mi.position = Vector3(0, 0.24, 0)
	mi.material_override = Mats.world_material()
	c.node.scale = Vector3.ONE * float(p["size"]) * (2.2 if mega else 1.0)
	add_child(c.node)
	c.node.global_position = c.pos
	cases.append(c)
	counts["max_cases"] = maxi(int(counts["max_cases"]), cases.size())
	if GameState.fx != null:
		GameState.fx.burst(c.pos, Color(1.0, 0.9, 0.6), 5, 4.0, 0.1, 0.25)


func clear_all() -> void:
	for c in cases:
		if c.node != null and is_instance_valid(c.node):
			c.node.queue_free()
	cases.clear()
	_queued.clear()
	_pending_launch = false
	for s in secondaries:
		s.node.visible = false
	secondaries.clear()
	for e in _embers:
		if e["fx"] != null and GameState.fx != null:
			GameState.fx.cancel(e["fx"])
	_embers.clear()
	_rain.clear()
	_cd.clear()
	_set_hand_visible(true)


func mark_pending(v: bool) -> void:
	_pending_launch = v
	_pending_t = 1.0 if v else 0.0


# ============================================================================ bucle
func _physics_process(delta: float) -> void:
	if _pending_launch:
		_pending_t -= delta
		if _pending_t <= 0.0:
			_pending_launch = false
			_set_hand_visible(true)
	if cases.is_empty() and secondaries.is_empty() and _embers.is_empty() and _rain.is_empty() and _queued.is_empty():
		return
	_clock += delta
	for k in _cd.keys():
		_cd[k] = float(_cd[k]) - delta
		if float(_cd[k]) <= 0.0:
			_cd.erase(k)
	_shake_t = maxf(0.0, _shake_t - delta)
	while not _blast_times.is_empty() and _clock - _blast_times[0] > 1.0:
		_blast_times.pop_front()
	# lanzamientos escalonados
	var qi := _queued.size() - 1
	while qi >= 0:
		_queued[qi]["t"] = float(_queued[qi]["t"]) - delta
		if float(_queued[qi]["t"]) <= 0.0:
			var q: Dictionary = _queued[qi]
			_queued.remove_at(qi)
			if GameState.player != null and GameState.player.alive:
				_spawn_case(int(q["i"]), q["spec"], q["p"], q["dir"], hand_pos(), float(q["tdist"]), false)
		qi -= 1
	var space := get_world_3d().direct_space_state
	var i := cases.size() - 1
	while i >= 0:
		var c := cases[i]
		if _step_case(c, delta, space):
			_catch(c)
			cases.remove_at(i)
		i -= 1
	_update_secondary(delta, space)
	_update_embers(delta)
	_update_rain(delta)
	# invariante: el maletín de la mano solo se ve cuando NINGÚN maletín está fuera
	_set_hand_visible(cases.is_empty() and _queued.is_empty() and not _pending_launch)


# ============================================================================ trayectoria
func _step_case(c: C, delta: float, space: PhysicsDirectSpaceState3D) -> bool:
	var player = GameState.player
	if player == null or not is_instance_valid(player) or not player.alive:
		return true
	c.life += delta
	c.t += delta
	var hand := hand_pos()
	match c.state:
		"out":
			var turn := c.curve_rate * delta
			if float(c.prof["homing"]) > 0.0:
				var tgt := Combat.nearest_enemy(c.pos, 9.0)
				if tgt != null:
					var want: Vector3 = tgt.global_position - c.pos
					want.y = 0.0
					if want.length() > 0.2:
						var ang := c.heading.signed_angle_to(want.normalized(), Vector3.UP)
						turn += clampf(ang, -1.0, 1.0) * float(c.prof["homing"]) * 6.0 * delta
			c.heading = c.heading.rotated(Vector3.UP, turn)
			c.vel = c.heading * c.speed
			c.dist += c.speed * delta
			if c.dist >= c.range_m:
				_end_out(c)
		"bounce":
			c.wall_left -= delta
			c.vel = c.heading * c.speed
			if c.wall_left <= 0.0:
				_begin_return(c)
		"ret":
			var to := hand - c.pos
			to.y = 0.0
			if to.length() < 1.0 or c.life > 7.0:
				return true
			var ang2 := c.heading.signed_angle_to(to.normalized(), Vector3.UP)
			var max_turn := (6.0 + 10.0 * c.t) * delta if c.life < 4.5 else 3.0
			c.heading = c.heading.rotated(Vector3.UP, clampf(ang2, -max_turn, max_turn))
			c.speed_cur = move_toward(c.speed_cur, c.speed * 1.2, 45.0 * delta)
			c.vel = c.heading * c.speed_cur
			c.pos.y = move_toward(c.pos.y, hand.y, 3.0 * delta)
	if c.life > 5.5 and c.state != "ret":
		_begin_return(c)
	var new_pos := c.pos + c.vel * delta
	# --- mundo: rebote por el entorno o regreso (en el regreso se atraviesa todo para garantizar la vuelta) ---
	if c.state != "ret":
		var q := PhysicsRayQueryParameters3D.create(c.pos, new_pos, Config.L_WORLD)
		var res := space.intersect_ray(q)
		if not res.is_empty():
			var n: Vector3 = res["normal"]
			n.y = 0.0
			n = n.normalized() if n.length() > 0.01 else -c.heading
			if c.wall_left > 0.0 or c.state == "bounce":
				c.heading = c.heading.bounce(n).normalized()
				c.vel = c.heading * c.speed
				new_pos = res["position"] + n * 0.25
				new_pos.y = c.pos.y
				if c.state == "out":
					c.state = "bounce"
					c.env_bounced = true
					c.hits.clear()
				c.bounces_done += 1
				_wall_fx(c, new_pos)
				counts["bounces_wall"] += 1
			else:
				new_pos = res["position"] + n * 0.25
				new_pos.y = c.pos.y
				_wall_fx(c, new_pos)
				c.pos = new_pos
				_begin_return(c)
				new_pos = c.pos
	c.pos = new_pos
	c.node.global_position = c.pos
	c.pivot.rotation = Vector3(0.0, c.pivot.rotation.y + 19.0 * delta, 0.28)
	# --- rastro visible, brasas, proyectiles durante el vuelo ---
	c.beam_acc += delta
	if c.main and c.beam_acc >= 0.045 and GameState.fx != null:
		c.beam_acc = 0.0
		GameState.fx.beam(c.pos - c.vel * 0.05, c.pos, Color(1.0, 0.85, 0.5, 0.55), 0.07, 0.2)
	if float(c.prof["trail"]) > 0.0:
		c.trail_acc += delta
		if c.trail_acc >= 0.1:
			c.trail_acc = 0.0
			_add_ember(c)
	if float(c.prof["multi"]) > 0.0:
		c.multi_acc += delta
		if c.multi_acc >= 0.16:
			c.multi_acc = 0.0
			_spawn_minis(c)
	# --- impactos ---
	for e in Combat.arena_enemies():
		if not is_instance_valid(e) or not e.alive:
			continue
		var d: Vector3 = e.global_position - c.pos
		d.y = 0.0
		var rr: float = c.radius + float(e.body_radius)
		if d.length_squared() > rr * rr:
			continue
		var key: int = e.get_instance_id()
		if c.hits.has(key):
			if c.state != "bounce" or _clock - float(c.hits[key]) < REHIT_BOUNCE:
				continue
		if c.state == "ret" and not bool(c.prof["sharp"]):
			continue
		c.hits[key] = _clock
		_impact(c, e)
		if c.state == "ret" and c.t < 0.001:
			break                       # acaba de dar la vuelta por este impacto
	return false


func _end_out(c: C) -> void:
	if c.wall_left > 0.0 and not c.env_bounced:
		c.state = "bounce"                  # Rebotes de Maletín: sigue rebotando en vez de volver
		c.env_bounced = true
		c.hits.clear()
		return
	_begin_return(c)


func _begin_return(c: C) -> void:
	if c.state == "ret":
		return
	c.state = "ret"
	c.t = 0.0
	# se conservan los enemigos que aún solapan al girar: un mismo contacto no cuenta dos veces (ida y vuelta)
	for key in c.hits.keys():
		var en := instance_from_id(int(key))
		if en == null or not is_instance_valid(en) or (en as Node3D).global_position.distance_to(Vector3(c.pos.x, (en as Node3D).global_position.y, c.pos.z)) > c.radius + 1.9:
			c.hits.erase(key)
	c.speed_cur = c.speed
	# Sello automático en el punto más lejano del recorrido (sustituye al botón SELLO)
	if c.main and not c.sealed:
		c.sealed = true
		var pl = GameState.player
		if pl != null and pl.skills != null:
			pl.skills.auto_seal(c.pos)


func _catch(c: C) -> void:
	counts["catches"] += 1
	var player = GameState.player
	var hand := hand_pos()
	if c.node != null and is_instance_valid(c.node):
		c.node.queue_free()
	AudioManager.combat_sfx("catch", hand, -4.0, AudioManager.P_ELEM, 1.0, 0.05)
	if GameState.fx != null:
		GameState.fx.burst(hand, Color(1.0, 0.9, 0.55), 6, 3.5, 0.1, 0.25)
	if player == null or not is_instance_valid(player) or not player.alive or not c.main:
		return                           # los efectos de retorno se activan UNA vez por lanzamiento (maletín principal)
	var p: Dictionary = c.prof
	# --- efectos de retorno ---
	if float(p["ret_blast"]) > 0.0 and _blast_ok():
		_note_blast()
		counts["return_blasts"] += 1
		var rad := (3.6 + float(p["ret_r"]) * 2.0) * Combat.area_mult() * (1.6 if bool(p["syn_return_fw"]) else 1.0)
		Combat.explode(player.global_position, rad, float(p["base"]) * c.dmg_mult * float(p["ret_blast"]), {"src": "return_blast"})
		if GameState.fx != null:
			GameState.fx.ring(player.global_position, rad, Color(1.0, 0.8, 0.3, 0.8), 0.4, 0.5)
		if bool(p["syn_return_fw"]):
			_launch_rockets(player.global_position + Vector3(0, 1.0, 0), null, float(p["base"]) * c.dmg_mult, p, 1 + int(p["pyro_n"]))
	if float(p["catch_haste"]) > 0.0:
		Perks.add_buff("haste", float(p["catch_haste"]), 2.5)


# ============================================================================ impacto: todas las mejoras en la misma tirada
func _impact(c: C, e: Node3D) -> void:
	var p: Dictionary = c.prof
	var b: Build = GameState.build
	var ipos: Vector3 = e.global_position
	var dir := c.heading
	var base: float = float(p["base"]) * c.dmg_mult
	var hit_mult := 1.0
	if bool(p["syn_pinball"]):
		hit_mult += 0.25 * float(c.bounces_done)
	if c.state == "ret":
		hit_mult *= float(p["ret_mult"])
	var opts := {"src": SRC, "knock": dir * float(p["knock"]), "stagger": 0.12, "area_hits": 1}
	var hp_before: float = float(e.hp)
	var killed: bool = Combat.player_hit(e, base * hit_mult, opts)
	c.impacts += 1
	counts["impacts"] += 1
	var sk = GameState.player.skills
	if sk != null:
		sk.combo_stacks = mini(sk.combo_stacks + 1, 15)
		sk.combo_timer = 2.0
	Perks.fire("slam", {"n": 1, "enemy": e})
	if record:
		impact_log.append({"case": c.idx, "state": c.state, "enemy": e.get_instance_id(), "killed": killed, "hp_before": hp_before, "base": base * hit_mult, "t": _clock})
	if GameState.fx != null:
		GameState.fx.burst(ipos + Vector3(0, 1.0, 0), Color(1.0, 0.92, 0.65), 6, 5.0, 0.12, 0.3)
	if GameState.cam != null and _shake_t <= 0.0:
		_shake_t = 0.12
		GameState.cam.shake(0.14 if not c.mega else 0.6)
	var ctx_pos := ipos + Vector3(0, 0.9, 0)
	# ---- 1. Explosión legal -------------------------------------------------------------------
	if float(p["blast"]) > 0.0 and _blast_ok():
		_note_blast()
		counts["blasts"] += 1
		var rad := (2.4 + float(p["blast_r"]) * 3.0) * Combat.area_mult()
		Combat.explode(ipos, rad, base * float(p["blast"]), {"src": "case_boom", "exclude": e, "soft": true})
	# ---- 2. Fuegos artificiales ----------------------------------------------------------------
	if float(p["pyro"]) > 0.0 and randf() < float(p["pyro"]) and not _on_cd("pyro", c, 0.25):
		_launch_rockets(ctx_pos, e, base, p, 1 + int(p["pyro_n"]))
	# ---- 3. Fragmentación ----------------------------------------------------------------------
	if float(p["frag"]) > 0.0:
		var n := int(floor(float(p["frag"]))) + (1 if randf() < fmod(float(p["frag"]), 1.0) else 0)
		_spawn_frags(ctx_pos, n, base * (0.32 + float(p["frag_dmg"])), p, "frag")
	# ---- 4. Documentos explosivos --------------------------------------------------------------
	if float(p["docs"]) > 0.0 and not _on_cd("docs", c, 0.3):
		var nd := int(floor(float(p["docs"]))) + (1 if randf() < fmod(float(p["docs"]), 1.0) else 0)
		_launch_docs(ctx_pos, e, nd, base)
	# ---- 5. Lluvia de documentos ---------------------------------------------------------------
	if float(p["rain"]) > 0.0 and randf() < float(p["rain"]) and not _on_cd("rain", c, 0.9):
		_start_rain(ipos, base, 4 + int(p["rain_n"]))
	# ---- 6. Maletín eléctrico ------------------------------------------------------------------
	if float(p["shock"]) > 0.0 and randf() < float(p["shock"]) and is_instance_valid(e):
		counts["shock"] += 1
		Combat.chain_lightning(e, base * 0.65 * (1.0 + b.s("chain_dmg")), 2 + int(p["shock_n"]) + int(b.s("chain_count")))
	# ---- 7. Corrosión y propagación de estados ------------------------------------------------
	if is_instance_valid(e) and e.alive:
		if float(p["corr"]) > 0.0 and randf() < float(p["corr"]):
			e.apply_mark(4.0 * (1.0 + b.s("mark_dur")))
			counts["marks"] += 1
		if float(p["spread"]) > 0.0:
			_spread_status(e, 1 + int(float(p["spread"]) * 0.5))
	# ---- 8. Onda residual (mejora existente) ---------------------------------------------------
	if float(p["echo"]) > 0.0 and sk != null:
		counts["echo"] += 1
		var rad2: float = float(Config.SKILLS["slam"]["radius"]) * Combat.area_mult() * 0.8
		var edmg: float = base * float(p["echo"])
		sk._after(0.25, func(): sk._echo(ipos, rad2, edmg))
	# ---- 9. Adquisición Hostil: el maletín gigante estalla -------------------------------------
	if c.mega and c.impacts == 1:
		Combat.explode(ipos, 7.0 * Combat.area_mult(), base * 0.6, {"src": "case_boom", "exclude": e, "soft": true})
		GameState.toast_msg("¡ADQUISICIÓN HOSTIL!", Color(1.0, 0.8, 0.2))
	# ---- movimiento tras el impacto: perforar / rebotar entre enemigos / volver ---------------
	if c.state == "ret":
		return
	if c.state == "bounce":
		return                          # en modo rebote por el entorno sigue su camino
	if c.pierce_left > 0:
		c.pierce_left -= 1
		return
	if c.bounces_left > 0:
		var nxt := _next_target(c, e)
		if nxt != null:
			c.bounces_left -= 1
			c.bounces_done += 1
			counts["bounces_enemy"] += 1
			var want: Vector3 = nxt.global_position - c.pos
			want.y = 0.0
			c.heading = want.normalized()
			c.dist = 0.0
			c.range_m = maxf(c.range_m * 0.5, 6.0)
			c.curve_rate *= 0.4
			AudioManager.combat_sfx("bounce", ipos, -4.0, AudioManager.P_ELEM, 1.0, 0.06)
			if bool(p["syn_conductor"]) and is_instance_valid(e):
				Combat.chain_lightning(nxt, base * 0.5, 2)
			return
	_begin_return(c)


func _next_target(c: C, from_enemy: Node3D) -> Node3D:
	var best: Node3D = null
	var best_d := 100.0
	for e in Combat.arena_enemies():
		if not is_instance_valid(e) or not e.alive or e == from_enemy or c.hits.has(e.get_instance_id()):
			continue
		var d: float = (e.global_position - c.pos).length()
		if d < best_d and d < 10.0:
			best_d = d
			best = e
	return best


func _on_cd(key: String, c: C, secs: float) -> bool:
	var k := "%s%d" % [key, c.idx]
	if _cd.has(k):
		return true
	_cd[k] = secs
	return false


func _blast_ok() -> bool:
	if _blast_times.size() >= MAX_BLASTS_PER_SEC:
		counts["skipped_budget"] += 1
		return false
	return true


func _note_blast() -> void:
	_blast_times.append(_clock)


func _spread_status(e: Node3D, n: int) -> void:
	var infected := false
	var near: Array = Combat.enemies_in_radius(e.global_position, 6.0)
	near = near.filter(func(x): return x != e)
	near.sort_custom(func(a, b): return a.global_position.distance_squared_to(e.global_position) < b.global_position.distance_squared_to(e.global_position))
	var k := 0
	for t in near:
		if k >= n:
			break
		if e.burn_t > 0.0:
			t.apply_burn(maxf(e.burn_dps, 4.0), minf(e.burn_t, 3.0))
			infected = true
		if e.marked_t > 0.0:
			t.apply_mark(minf(e.marked_t, 4.0))
			infected = true
		if e.slow_t > 0.0:
			t.apply_slow(0.45, minf(e.slow_t, 2.5))
			infected = true
		if infected and GameState.fx != null:
			GameState.fx.beam(e.global_position + Vector3(0, 1, 0), t.global_position + Vector3(0, 1, 0), Color(0.9, 0.6, 1.0, 0.8), 0.08, 0.2)
		k += 1
	if infected:
		counts["spreads"] += 1


func _wall_fx(c: C, pos: Vector3) -> void:
	AudioManager.combat_sfx("bounce", pos, -3.0, AudioManager.P_ELEM, 1.0, 0.07)
	if GameState.fx != null:
		GameState.fx.burst(pos, Color(1.0, 0.9, 0.5), 6, 5.0, 0.1, 0.25)


# ============================================================================ proyectiles secundarios
func _secondary_count() -> int:
	return secondaries.size() + (GameState.projectiles.count() if GameState.projectiles != null else 0)


func _sec_budget(n: int) -> int:
	var free := MAX_SECONDARY - _secondary_count()
	if free < n:
		counts["skipped_budget"] += n - maxi(free, 0)
	return clampi(free, 0, n)


func _mesh_for(kind: String) -> ArrayMesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var b := MeshBuilder.new()
	match kind:
		"frag":
			b.box(Vector3(0.09, 0.09, 0.3), MeshBuilder.xf(), MeshBuilder.glow(Color(1.0, 0.7, 0.25), 1.0))
		"rocket":
			b.cylinder(0.06, 0.06, 0.34, 6, MeshBuilder.xf(Vector3.ZERO, Vector3(90, 0, 0)), Color(0.85, 0.2, 0.2))
			b.sphere(0.1, 6, 4, MeshBuilder.xf(Vector3(0, 0, 0.2)), MeshBuilder.glow(Color(1.0, 0.85, 0.3), 1.0))
		"mini":
			_meshes[kind] = ModelFactory.briefcase_mesh()
			return _meshes[kind]
	_meshes[kind] = b.build()
	return _meshes[kind]


func _acquire_sec(kind: String) -> S:
	var list: Array = _sec_pool.get(kind, [])
	for s in list:
		if not s.node.visible:
			s.hits = []
			s.age = 0.0
			return s
	var s2 := S.new()
	s2.kind = kind
	var n := Node3D.new()
	var mi := Mats.mesh_instance(_mesh_for(kind), Mats.world_material(), n)
	mi.material_override = Mats.world_material()
	if kind == "mini":
		mi.position = Vector3(0, 0.2, 0)
		n.scale = Vector3.ONE * 0.4
	add_child(n)
	s2.node = n
	list.append(s2)
	_sec_pool[kind] = list
	return s2


func _spawn_frags(pos: Vector3, n: int, dmg: float, p: Dictionary, src: String) -> void:
	n = _sec_budget(n)
	if n <= 0:
		return
	counts["frags"] += n
	var off := randf() * TAU
	for i in n:
		var s := _acquire_sec("frag")
		var a := off + TAU * float(i) / float(n)
		s.src = src
		s.pos = pos
		s.vel = Vector3(cos(a), 0.0, sin(a)) * 17.0
		s.life = 0.5
		s.dmg = dmg
		s.radius = 0.5
		s.pierce = 0
		s.prof = p
		s.node.visible = true
		s.node.global_position = pos
		secondaries.append(s)
	counts["max_secondary"] = maxi(int(counts["max_secondary"]), secondaries.size())
	AudioManager.combat_sfx("shard", pos, -7.0, AudioManager.P_HIT, 1.0, 0.1)


func _spawn_minis(c: C) -> void:
	var rate := float(c.prof["multi"])
	if randf() >= minf(rate, 1.0):
		return
	var n := _sec_budget(1 + int(rate))
	if n <= 0:
		return
	counts["minis"] += n
	for i in n:
		var s := _acquire_sec("mini")
		var a := (1.0 if (i + c.idx) % 2 == 0 else -1.0) * deg_to_rad(randf_range(30.0, 60.0))
		var d := c.heading.rotated(Vector3.UP, a)
		s.src = "mini"
		s.pos = c.pos
		s.vel = d * 15.0
		s.life = 0.65
		s.dmg = float(c.prof["base"]) * 0.42 * c.dmg_mult
		s.radius = 0.55
		s.pierce = 0
		s.prof = c.prof
		s.node.visible = true
		s.node.global_position = c.pos
		secondaries.append(s)


func _launch_rockets(pos: Vector3, from_enemy: Node3D, base: float, p: Dictionary, n: int) -> void:
	n = _sec_budget(n)
	if n <= 0:
		return
	counts["rockets"] += n
	var used: Array = []
	if from_enemy != null:
		used.append(from_enemy)
	for i in n:
		var tgt := Combat.nearest_enemy(pos, 14.0, used)
		var to: Vector3
		if tgt != null:
			used.append(tgt)
			to = tgt.global_position
		else:
			var a := randf() * TAU
			to = pos + Vector3(cos(a), 0, sin(a)) * randf_range(3.0, 7.0)
		to.y = 0.3
		var s := _acquire_sec("rocket")
		s.src = "firework"
		s.from = pos
		s.to = to
		s.pos = pos
		s.age = 0.0
		s.dur = clampf(0.55 + pos.distance_to(to) * 0.03, 0.55, 0.95)
		s.life = s.dur + 0.1
		s.dmg = base * 0.6
		s.frag_on_pop = bool(p["syn_pyro_frag"])
		s.prof = p
		s.node.visible = true
		s.node.global_position = pos
		secondaries.append(s)
	counts["max_secondary"] = maxi(int(counts["max_secondary"]), secondaries.size())
	AudioManager.combat_sfx("fw_launch", pos, -5.0, AudioManager.P_ELEM, 1.0, 0.06)


func _launch_docs(pos: Vector3, from_enemy: Node3D, n: int, base: float) -> void:
	if GameState.projectiles == null or n <= 0:
		return
	n = _sec_budget(n)
	var used: Array = [from_enemy]
	for i in n:
		var tgt := Combat.nearest_enemy(pos, 12.0, used)
		if tgt != null:
			used.append(tgt)
		var a := randf() * TAU
		var d := Vector3(cos(a), 0.4, sin(a))
		counts["docs"] += 1
		GameState.projectiles.fire_doc(pos, d, base * 0.5, tgt, 15.0, {"src": "docs", "skill": false, "flat": false, "explode": true})


func _update_secondary(delta: float, _space: PhysicsDirectSpaceState3D) -> void:
	var i := secondaries.size() - 1
	while i >= 0:
		var s := secondaries[i]
		s.age += delta
		var done := false
		if s.kind == "rocket":
			var k := clampf(s.age / s.dur, 0.0, 1.0)
			var np := s.from.lerp(s.to, k) + Vector3(0, 3.2 * sin(PI * k), 0)
			s.vel = (np - s.pos) / maxf(delta, 0.001)
			s.pos = np
			if k >= 1.0:
				_pop_rocket(s)
				done = true
			elif fmod(s.age, 0.12) < delta and GameState.fx != null:
				GameState.fx.burst(s.pos, Color(1.0, 0.7, 0.2), 2, 1.5, 0.08, 0.3)
		else:
			s.pos += s.vel * delta
			s.life -= delta
			if s.life <= 0.0:
				done = true
			else:
				for e in Combat.arena_enemies():
					if not is_instance_valid(e) or not e.alive or s.hits.has(e):
						continue
					var d: Vector3 = e.global_position - s.pos
					d.y = 0.0
					var rr: float = s.radius + float(e.body_radius)
					if d.length_squared() <= rr * rr:
						s.hits.append(e)
						var dir := s.vel.normalized()
						Combat.player_hit(e, s.dmg, {"src": s.src, "knock": dir * 2.0, "area_hits": 1, "flat": false, "skill": false})
						if GameState.fx != null:
							GameState.fx.burst(s.pos, Color(1.0, 0.8, 0.4), 3, 3.0, 0.08, 0.2)
						if s.pierce <= 0:
							done = true
							break
						s.pierce -= 1
		if s.kind == "mini":
			s.node.rotation.y += 16.0 * delta
		elif s.kind == "frag" and s.vel.length() > 0.1:
			s.node.look_at(s.pos + s.vel, Vector3.UP)
		s.node.global_position = s.pos
		if done:
			s.node.visible = false
			secondaries.remove_at(i)
		i -= 1


func _pop_rocket(s: S) -> void:
	var p := s.prof
	if _blast_ok():
		_note_blast()
		Combat.explode(s.pos, 2.4 * Combat.area_mult(), s.dmg, {"src": "firework", "element": "fire", "soft": true})
	AudioManager.combat_sfx("fw_pop", s.pos, -4.0, AudioManager.P_CRIT, 1.0, 0.08)
	if GameState.fx != null:
		var cols := [Color(1.0, 0.4, 0.3), Color(0.4, 0.8, 1.0), Color(1.0, 0.9, 0.3), Color(0.7, 1.0, 0.5)]
		GameState.fx.burst(s.pos, cols[randi() % cols.size()], 14, 6.0, 0.13, 0.6)
	if s.frag_on_pop:
		_spawn_frags(s.pos, 4, s.dmg * 0.4, p, "frag")


# ============================================================================ lluvia de documentos
func _start_rain(center: Vector3, base: float, n: int) -> void:
	counts["rain"] += 1
	for i in n:
		var a := randf() * TAU
		_rain.append({"t": 0.12 + 0.09 * float(i), "pos": center + Vector3(cos(a), 0, sin(a)) * randf_range(0.5, 3.2), "dmg": base * 0.35})
	AudioManager.combat_sfx("paper", center, -8.0, AudioManager.P_HIT, 1.0, 0.1)


func _update_rain(delta: float) -> void:
	var i := _rain.size() - 1
	while i >= 0:
		_rain[i]["t"] = float(_rain[i]["t"]) - delta
		if float(_rain[i]["t"]) <= 0.0:
			var r: Dictionary = _rain[i]
			_rain.remove_at(i)
			if GameState.fx != null:
				GameState.fx.burst(r["pos"] + Vector3(0, 0.3, 0), Color(0.98, 0.97, 0.9), 5, 3.0, 0.1, 0.35)
			if _blast_ok():
				_note_blast()
				Combat.explode(r["pos"], 1.5 * Combat.area_mult(), float(r["dmg"]), {"src": "rain", "element": "phys", "soft": true})
		i -= 1


# ============================================================================ rastro de fuego
func _add_ember(c: C) -> void:
	if _embers.size() >= MAX_EMBERS:
		counts["skipped_budget"] += 1
		return
	var fxi = null
	if GameState.fx != null:
		fxi = GameState.fx.zone(Vector3(c.pos.x, 0.0, c.pos.z), 1.0, 1.1, Color(1.0, 0.45, 0.12))
	counts["embers"] += 1
	_embers.append({"pos": Vector3(c.pos.x, 0.0, c.pos.z), "t": 0.0, "tick": 0.0, "fx": fxi, "dmg": float(c.prof["base"]) * float(c.prof["trail"]) * c.dmg_mult,
		"inferno": bool(c.prof["syn_inferno_trail"])})


func _update_embers(delta: float) -> void:
	var i := _embers.size() - 1
	while i >= 0:
		var m: Dictionary = _embers[i]
		m["t"] += delta
		m["tick"] += delta
		if float(m["tick"]) >= 0.3:
			m["tick"] = 0.0
			var list := Combat.enemies_in_radius(m["pos"], 1.1)
			for e in list:
				Combat.player_hit(e, float(m["dmg"]), {"src": "fire_trail", "element": "fire", "flat": false, "no_crit": true, "proc": false, "area_hits": list.size()})
				if is_instance_valid(e) and e.alive and bool(m["inferno"]):
					e.apply_burn(6.0 + GameState.build.s("burn_dps"), 2.0)
		if float(m["t"]) >= 1.1:
			_embers.remove_at(i)
		i -= 1
