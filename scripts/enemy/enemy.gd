class_name Enemy
extends CharacterBody3D
## Enemigo genérico dirigido por datos (EnemyDefs). Una única clase cubre ladrones, corredores,
## tanques, a distancia, invocadores, élites, minijefes y jefe de zona.
##
## Máquina de estados: SPAWN → PATROL → CHASE → TELE (telegrafía) → ACT (golpe) → RECOVER
##   con interrupciones HURT / FROZEN / PHASE y final DEAD.
## Todos los ataques se telegrafían en el suelo y son esquivables (el jugador tiene i-frames al esquivar).
## El Arena instancia/recicla enemigos (pooling) llamando a setup().

signal died(enemy: Enemy)
signal despawned(enemy: Enemy)
signal request_spawn(kind: String, pos: Vector3)

enum S { SPAWN, PATROL, CHASE, TELE, ACT, RECOVER, HURT, FROZEN, PHASE, DEAD }

const GRAVITY := 28.0
const ACCEL := 22.0

var kind := "thief"
var def: Dictionary = {}
var alive := false
var state := S.SPAWN
var arena_index := 0
var affix := ""
var is_elite := false
var is_boss := false
var body_radius := 0.45
var vscale := 1.0
var max_hp := 50.0
var hp := 50.0
var dmg_base := 8.0
var move_speed := 4.0
var xp_value := 5.0
var coin_value := 1
var kill_paid := false               # la recompensa de esta baja ya se pagó (anti doble pago)
var display_name := ""
var rig: Rig
var variant := 0

# estados alterados
var marked_t := 0.0
var slow_t := 0.0
var slow_amt := 0.4
var burn_t := 0.0
var burn_dps := 0.0
var freeze_t := 0.0
var _burn_tick := 0.0

var aggro_range := 24.0
var home := Vector3.ZERO
var phase := 1
var invuln_t := 0.0

var _t := 0.0                      # temporizador del estado actual
var _kb := Vector3.ZERO            # empuje por golpes
var _patrol_target := Vector3.ZERO
var _patrol_wait := 0.0
var _cds: Dictionary = {}          # nombre de ataque -> enfriamiento restante
var _gate := 0.0                   # pausa global entre ataques
var _atk_name := ""
var _atk: Dictionary = {}
var _aim_yaw := 0.0
var _aim_dir := Vector3.FORWARD
var _tele_items: Array = []
var _barrage_pts: Array = []
var _dash_left := 0.0
var _dash_hit := false
var _since_hit := 99.0
var boss_style := ""                # id del bioma del jefe (EnemyDefs.BOSS_STYLES): nombre, color y ataques propios
var _wave_n := 0                    # repeticiones pendientes del ataque actual (espirales, rayos cruzados, ondas)
var _wave_k := 1
var _wave_t := 0.0
var _wave_dmg := 0.0
var _leap_t := 0.0                  # salto / teletransporte del jefe en curso
var _leap_dur := 0.5
var _leap_from := Vector3.ZERO
var _leap_to := Vector3.ZERO
static var chase_us := 0                    # medición de rendimiento (pruebas): microsegundos acumulados en _chase
static var chase_n := 0
var _seed := 0.0
var _sep := Vector3.ZERO
var _sep_frame := 0
var _boom_t := -1.0
var _dead_t := 0.0
var _vis_key := ""
var _spawn_scale_t := 0.0
var _col: CollisionShape3D
var _bar: Node3D
var _bar_fill: MeshInstance3D
var _bar_mesh: QuadMesh
var _strafe_dir := 1.0
# --- navegación (ver NavGrid) ---
var nav_cls := 0                   # 0 = pequeño, 1 = grande (tanque, élite, minijefe, jefe)
var _wp := Vector3.INF             # siguiente punto de paso (caché; se recalcula cada ~0.12 s, escalonado por enemigo)
var _wp_info := 0                  # 0 línea directa, 1 rodeando por el campo de flujo, 2 sin campo aún, 3 sin ruta
var _wp_t := 0.0
var _los_t := 0.0
var _los_ok := true                # línea de visión física (rayo contra el mundo) hasta el jugador
var _slot_ang := 0.0               # ángulo (mundo) del hueco alrededor del jugador al que quiere llegar
var _slot_off := 0.0
var _stk_pos := Vector3.ZERO
var _stk_acc := 0.0
var _stuck_t := 0.0                # segundos acumulados sin avanzar pese a querer moverse
var _stuck_lvl := 0
var _prog_best := 1e9              # mejor "distancia restante" (pasos de ruta o metros) conseguida
var _prog_t := 0.0                 # tiempo sin mejorarla
var _prog_mode := -1
var _detour_t := 0.0
var _detour_pt := Vector3.INF
var nav_unstuck_count := 0         # veces que el anti-atasco tuvo que intervenir (estadística/tests)
static var _slot_n := 0

static var _bar_back_mat: StandardMaterial3D
static var _bar_front_mat: StandardMaterial3D


func _ready() -> void:
	collision_layer = Config.L_ENEMY
	collision_mask = Config.L_WORLD
	floor_snap_length = 0.4
	# Con el margen por defecto (0,001) cada move_and_slide sobre el HeightMapShape del terreno repite pasos de recuperación:
	# medido ~3x más caro con 50 enemigos. 0,03 m no se nota al jugar y quita casi todo ese coste.
	safe_margin = 0.03
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	_seed = randf() * 10.0


## Prepara (o recicla) el enemigo. 'v' es el variante visual solo si aún no hay modelo.
func setup(p_kind: String, p_arena_index: int, p_affix: String, pos: Vector3, p_aggro := 999.0) -> void:
	kill_paid = false
	var first := rig == null
	if first or kind != p_kind:
		if rig != null:
			rig.queue_free()
			rig = null
		kind = p_kind
		def = EnemyDefs.DEFS[kind]
		variant = randi() % maxi(1, int(def.get("variants", 1)))
		rig = ModelFactory.build_enemy(kind, variant)
		add_child(rig)
		vscale = float(EnemyDefs.VISUAL_SCALE.get(kind, 1.0))
		rig.scale = Vector3.ONE * vscale
		rig.heavy = kind in ["tank", "elite", "miniboss", "boss"]
		_build_collider()
		_build_bar()
	kind = p_kind
	def = EnemyDefs.DEFS[kind]
	arena_index = p_arena_index
	affix = p_affix
	is_boss = kind == "miniboss" or kind == "boss"
	is_elite = kind == "elite" or is_boss
	body_radius = float(def["radius"])
	display_name = String(def["name"])
	var hpm := Scaling.hp_mult(arena_index)
	var spm := Scaling.speed_mult(arena_index)
	max_hp = float(def["hp"]) * hpm
	move_speed = float(def["speed"]) * spm
	dmg_base = float(def["dmg"]) * Scaling.dmg_mult(arena_index)
	xp_value = float(def["xp"]) * (1.0 + 0.06 * arena_index)
	coin_value = int(round(float(def["coins"]) * Scaling.reward_mult(arena_index)))
	var tint := Color(1, 1, 1)
	if affix != "" and EnemyDefs.AFFIXES.has(affix):
		var a: Dictionary = EnemyDefs.AFFIXES[affix]
		max_hp *= float(a["hp"])
		move_speed *= float(a["speed"])
		tint = a["tint"]
		display_name = "%s %s" % [a["name"], display_name]
		xp_value *= 1.5
		coin_value = int(ceil(coin_value * 1.5))
	boss_style = ""
	if kind == "boss":
		boss_style = String(BiomeDB.get_biome(BiomeDB.biome_index(arena_index))["id"])
		var bst: Dictionary = EnemyDefs.BOSS_STYLES.get(boss_style, EnemyDefs.BOSS_STYLES["urban"])
		display_name = String(bst["name"])
		max_hp *= float(bst["hp_x"])
		move_speed *= float(bst["speed_x"])
		tint = bst["tint"]
		vscale = float(bst["scale"])
	_wave_n = 0
	_leap_t = 0.0
	hp = max_hp
	marked_t = 0.0
	slow_t = 0.0
	burn_t = 0.0
	freeze_t = 0.0
	invuln_t = 0.0
	phase = 1
	_cds.clear()
	_gate = randf_range(0.4, 1.2)
	_kb = Vector3.ZERO
	_boom_t = -1.0
	_dead_t = 0.0
	nav_cls = 1 if body_radius > 0.6 else 0
	_wp = Vector3.INF
	_wp_info = 2
	_wp_t = randf() * 0.1
	_los_t = 0.0
	_los_ok = true
	_stuck_t = 0.0
	_stuck_lvl = 0
	_prog_best = 1e9
	_prog_t = 0.0
	_prog_mode = -1
	_detour_t = 0.0
	_stk_acc = 0.0
	_slot_n += 1
	_slot_off = (fmod(float(_slot_n) * 2.39996, TAU) - PI) * 0.35
	_clear_tele()
	_vis_key = ""
	home = pos
	aggro_range = p_aggro
	global_position = pos
	velocity = Vector3.ZERO
	rotation = Vector3.ZERO
	rotation.y = randf() * TAU
	aggro_range = p_aggro
	alive = true
	visible = true
	rig.revive()
	rig.scale = Vector3.ZERO
	_spawn_scale_t = 0.0
	_apply_visual(tint)
	_set_state(S.SPAWN)
	_t = 0.7 if not is_boss else 1.2
	_col.disabled = false
	set_physics_process(true)
	set_process(true)
	if _bar != null:
		_bar.visible = false
	if GameState.fx != null:
		GameState.fx.ring(pos, 1.6 * vscale, Color(0.9, 0.3, 1.0, 0.8), 0.6, 0.2)
	AudioManager.sfx_at("spawn", pos, -8.0)
	if is_boss:
		GameState.boss_bar.emit(true, display_name, hp, max_hp)


func _build_collider() -> void:
	if _col != null:
		_col.queue_free()
	_col = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	var r := float(def["radius"])
	cap.radius = r
	cap.height = maxf(r * 2.0 + 0.1, 1.8 * vscale)
	_col.shape = cap
	_col.position.y = cap.height * 0.5
	add_child(_col)


func _build_bar() -> void:
	if _bar != null:
		_bar.queue_free()
	if _bar_back_mat == null:
		_bar_back_mat = StandardMaterial3D.new()
		_bar_back_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_bar_back_mat.albedo_color = Color(0.05, 0.05, 0.08, 0.85)
		_bar_back_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_bar_back_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_bar_back_mat.billboard_keep_scale = true
		_bar_back_mat.no_depth_test = true
		_bar_back_mat.render_priority = 10
		_bar_front_mat = _bar_back_mat.duplicate()
		_bar_front_mat.albedo_color = Color(0.95, 0.25, 0.3, 1.0)
		_bar_front_mat.render_priority = 11
	_bar = Node3D.new()
	_bar.position.y = 2.0 * vscale + 0.35
	add_child(_bar)
	var w := 1.1 + 0.25 * vscale
	var back := MeshInstance3D.new()
	var bm := QuadMesh.new()
	bm.size = Vector2(1.0, 0.16)
	back.mesh = bm
	back.scale = Vector3(w + 0.06, 1.0, 1.0)
	back.material_override = _bar_back_mat
	back.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bar.add_child(back)
	_bar_fill = MeshInstance3D.new()
	_bar_mesh = QuadMesh.new()
	_bar_mesh.size = Vector2(1.0, 0.11)
	_bar_fill.mesh = _bar_mesh
	_bar_fill.scale = Vector3(w, 1.0, 1.0)
	_bar_fill.material_override = _bar_front_mat
	_bar_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bar.add_child(_bar_fill)
	_bar.set_meta("w", w)
	_bar.visible = false


func _update_bar() -> void:
	if _bar == null or is_boss:
		return
	var f := clampf(hp / max_hp, 0.001, 1.0)
	_bar.visible = hp < max_hp - 0.01 and alive
	var w: float = _bar.get_meta("w")
	_bar_fill.scale.x = w * f
	_bar_mesh.center_offset = Vector3(0.5 - 0.5 / f, 0, 0)


func hp_frac() -> float:
	return clampf(hp / max_hp, 0.0, 1.0)


func _player() -> Player:
	var p = GameState.player
	if p != null and is_instance_valid(p) and p.alive:
		return p
	return null


func _set_state(s: S) -> void:
	state = s


# ------------------------------------------------------------------ física / IA
func _physics_process(delta: float) -> void:
	if state == S.DEAD:
		_dead_tick(delta)
		return
	_since_hit += delta
	_tick_status(delta)
	if alive and global_position.y < -15.0:
		global_position = home + Vector3(0, 1.0, 0)
		velocity = Vector3.ZERO
	for k in _cds.keys():
		_cds[k] = maxf(0.0, float(_cds[k]) - delta)
	_gate = maxf(0.0, _gate - delta)
	invuln_t = maxf(0.0, invuln_t - delta)
	if _wave_n > 0 and alive:
		_wave_tick(delta)
	var p := _player()
	match state:
		S.SPAWN:
			_t -= delta
			_spawn_scale_t += delta
			var k := clampf(_spawn_scale_t / (0.6 if not is_boss else 1.1), 0.0, 1.0)
			rig.scale = Vector3.ONE * vscale * (1.0 - pow(1.0 - k, 3.0))
			_move_toward_dir(Vector3.ZERO, 0.0, delta)
			if _t <= 0.0:
				rig.scale = Vector3.ONE * vscale
				_set_state(S.CHASE if aggro_range >= 900.0 else S.PATROL)
		S.PATROL:
			_patrol(delta, p)
		S.CHASE:
			var _t0 := Time.get_ticks_usec()
			_chase(delta, p)
			chase_us += Time.get_ticks_usec() - _t0
			chase_n += 1
		S.TELE:
			_tele_tick(delta, p)
		S.ACT:
			_act_tick(delta, p)
		S.RECOVER:
			_t -= delta
			_move_toward_dir(Vector3.ZERO, 0.0, delta)
			if _t <= 0.0:
				_set_state(S.CHASE)
		S.HURT:
			_t -= delta
			_move_toward_dir(Vector3.ZERO, 0.0, delta)
			if _t <= 0.0:
				_set_state(S.CHASE)
		S.FROZEN:
			freeze_t -= delta
			_move_toward_dir(Vector3.ZERO, 0.0, delta)
			if freeze_t <= 0.0:
				_set_state(S.CHASE)
		S.PHASE:
			_t -= delta
			_move_toward_dir(Vector3.ZERO, 0.0, delta)
			if _t <= 0.0:
				_set_state(S.CHASE)
	if rig != null:
		var hs := Vector2(velocity.x, velocity.z).length()
		rig.speed_norm = clampf(hs / maxf(1.0, move_speed * 1.15), 0.0, 1.0) if state in [S.CHASE, S.PATROL] else 0.0
	_update_visual_status()


func _speed_now() -> float:
	var s := move_speed
	if slow_t > 0.0:
		s *= (1.0 - slow_amt)
	return s


func _move_toward_dir(dir: Vector3, speed: float, delta: float) -> void:
	var want := dir * speed
	want += _kb
	var hv := Vector3(velocity.x, 0, velocity.z)
	hv = hv.move_toward(want, ACCEL * delta * (1.0 + (speed / 6.0)))
	velocity.x = hv.x
	velocity.z = hv.z
	if is_on_floor():
		velocity.y = -1.0
	else:
		velocity.y -= GRAVITY * delta
	_kb = _kb.move_toward(Vector3.ZERO, 14.0 * delta)
	move_and_slide()


func _face(dir: Vector3, rate := 10.0, delta := 0.016) -> void:
	if dir.length() < 0.01:
		return
	var yaw := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, yaw, clampf(rate * delta, 0.0, 1.0))


func _flat_to(p: Player) -> Vector3:
	var d: Vector3 = p.global_position - global_position
	d.y = 0.0
	return d


func _separation() -> Vector3:
	_sep_frame += 1
	if _sep_frame % 4 != int(_seed) % 4:
		return _sep
	var out := Vector3.ZERO
	for e in Combat.arena_enemies():
		if e == self or not is_instance_valid(e) or not e.alive:
			continue
		var d: Vector3 = global_position - e.global_position
		d.y = 0.0
		var rr: float = body_radius + e.body_radius + 0.25
		var l := d.length()
		if l < rr and l > 0.001:
			out += d / l * (rr - l) / rr
	_sep = out * 1.6
	return _sep


func _patrol(delta: float, p: Player) -> void:
	if p != null and _flat_to(p).length() < aggro_range:
		_set_state(S.CHASE)
		return
	_patrol_wait -= delta
	var to := _patrol_target - global_position
	to.y = 0.0
	if _patrol_wait <= 0.0 or to.length() < 0.6:
		_patrol_wait = randf_range(2.0, 4.0)
		var a := randf() * TAU
		_patrol_target = home + Vector3(cos(a), 0, sin(a)) * randf_range(2.0, 6.0)
		to = _patrol_target - global_position
		to.y = 0.0
	var dir := to.normalized() if to.length() > 0.6 else Vector3.ZERO
	_face(dir, 6.0, delta)
	_move_toward_dir(dir, _speed_now() * 0.45, delta)


func _nav() -> NavGrid:
	var a = GameState.arena
	if a != null and is_instance_valid(a):
		var nv = a.get("nav")
		if nv != null and nv.ready:
			return nv
	return null


## Línea de visión física hasta el jugador (solo muros y obstáculos; el relieve suave del terreno no cuenta, igual que en los proyectiles).
func _ray_los(p: Player) -> bool:
	var q := PhysicsRayQueryParameters3D.create(global_position + Vector3(0, 1.0, 0), p.global_position + Vector3(0, 1.0, 0), Config.L_WORLD)
	if Terrain.body_rid.is_valid():
		q.exclude = [Terrain.body_rid]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _flat_dir_to(pt: Vector3) -> Vector3:
	var v := pt - global_position
	v.y = 0.0
	return v.normalized() if v.length() > 0.05 else Vector3.ZERO


func _chase(delta: float, p: Player) -> void:
	if p == null:
		_move_toward_dir(Vector3.ZERO, 0.0, delta)
		return
	var to := _flat_to(p)
	var dist := to.length()
	var dir := to.normalized() if dist > 0.01 else Vector3.FORWARD
	_face(dir, 9.0, delta)
	var behavior := String(def["behavior"])
	var nav := _nav()
	# línea de visión física (escalonada)
	_los_t -= delta
	if _los_t <= 0.0:
		_los_t = 0.1 + fmod(_seed, 0.05)
		_los_ok = _ray_los(p)
	# ¿atacar? (no a través de muros; los jefes y las invocaciones no necesitan línea de visión)
	if _gate <= 0.0:
		var name := _pick_attack(dist)
		if name != "":
			if is_boss or _los_ok or String(EnemyDefs.ATTACKS[name]["shape"]) == "summon":
				_begin_attack(name, p)
				return
	# --- ruta: punto de paso rodeando obstáculos (escalonado, no cada fotograma) ---
	var target := p.global_position
	var melee_slot := nav != null and (behavior == "melee") and not is_boss and dist < 10.0
	if dist > 10.0:
		_slot_ang = atan2(-to.z, -to.x) + _slot_off
	elif melee_slot:
		var sp := p.global_position + Vector3(cos(_slot_ang), 0, sin(_slot_ang)) * 1.5
		if nav.walkable(sp, nav_cls) and dist > 2.2:
			target = sp
	if nav != null:
		nav.request(nav_cls)
		_wp_t -= delta
		var near_wp := _wp != Vector3.INF and _wp_info == 1 and _flat_dir_to(_wp).length() > 0.0 and (_wp - global_position).length() < 0.7
		if _wp_t <= 0.0 or near_wp:
			_wp_t = 0.1 + fmod(_seed, 0.06)
			var out := [0]
			_wp = nav.waypoint(global_position, target, nav_cls, out)
			_wp_info = int(out[0])
	else:
		_wp = Vector3.INF
		_wp_info = 2
	var approach := dir
	if _wp != Vector3.INF and _wp_info in [0, 1]:
		var wd := _flat_dir_to(_wp)
		if wd != Vector3.ZERO:
			approach = wd
	var routing := _wp_info == 1                # el camino directo está bloqueado: seguir la ruta
	var move := Vector3.ZERO
	var spd := _speed_now()
	match behavior:
		"flank":
			if routing:
				move = approach
			else:
				var k := clampf((dist - 3.0) / 7.0, 0.0, 1.0)
				var off := sin(Time.get_ticks_msec() * 0.0025 + _seed) * 0.95 * k
				move = approach.rotated(Vector3.UP, off)
			if dist < 1.4:
				move = Vector3.ZERO
		"ranged":
			var band: Array = def.get("band", [8.0, 13.0])
			var b0 := float(band[0])
			if (routing or not _los_ok) and dist > b0 * 0.6:
				move = approach            # sin línea de tiro: avanzar por la ruta hasta tener una posición válida
			elif dist < b0:
				move = -dir.rotated(Vector3.UP, 0.4 * _strafe_dir)
				spd *= 0.9
			elif dist > float(band[1]):
				move = approach
			else:
				move = dir.rotated(Vector3.UP, PI * 0.5 * _strafe_dir) * 0.55
				if randf() < 0.004:
					_strafe_dir = -_strafe_dir
			if nav != null and move != approach and not nav.free_ahead(global_position, move, 1.6, nav_cls):
				_strafe_dir = -_strafe_dir
				move = dir.rotated(Vector3.UP, PI * 0.5 * _strafe_dir) * 0.55
				if not nav.free_ahead(global_position, move, 1.6, nav_cls):
					move = approach if dist > b0 * 0.6 else Vector3.ZERO
		"boss":
			if dist > 7.5:
				move = approach
			else:
				move = dir.rotated(Vector3.UP, PI * 0.5 * _strafe_dir) * 0.6
				if randf() < 0.006:
					_strafe_dir = -_strafe_dir
				if nav != null and not nav.free_ahead(global_position, move, 2.0, nav_cls):
					_strafe_dir = -_strafe_dir
					move = approach
		_:
			var stop := 1.5 * maxf(1.0, vscale * 0.9)
			if dist <= stop:
				move = Vector3.ZERO
			elif target != p.global_position and (target - global_position).length() < 0.5:
				move = Vector3.ZERO         # ya está en su hueco alrededor del jugador
			else:
				move = approach
			if is_boss and dist < 5.0 and dist > stop and not routing:
				move = dir.rotated(Vector3.UP, 0.5 * _strafe_dir)
	# desvío temporal del anti-atasco: manda sobre lo demás
	if _detour_t > 0.0:
		_detour_t -= delta
		var dd := _flat_dir_to(_detour_pt)
		if dd == Vector3.ZERO or (_detour_pt - global_position).length() < 0.4:
			_detour_t = 0.0
		else:
			move = dd
	move += _separation() * 0.8
	if move.length() > 1.0:
		move = move.normalized()
	var intended := move.length()               # lo que QUIERE avanzar (antes de deslizarse): el anti-atasco mide contra esto
	# esquivar paredes: si estamos bloqueados contra una pared, deslizar por la normal
	if is_on_wall():
		var n := get_wall_normal()
		n.y = 0.0
		if n.length() > 0.01:
			var slide := move.slide(n.normalized())
			move = slide if slide.length() > 0.1 else n.normalized().rotated(Vector3.UP, PI * 0.5 * _strafe_dir)
	_stuck_check(delta, intended > 0.25, spd, nav, dist, routing or (behavior != "ranged" and behavior != "boss" and dist > 2.0))
	_move_toward_dir(move, spd, delta)


## Anti-atasco: mide el avance real cada 0.25 s. Sin avance pese a querer moverse → escala:
##  0.5 s recalcular ruta · 1.0 s punto alternativo · 2.0 s desvío a la celda libre más cercana y nuevo hueco · 4.0 s pequeño salto
##  comprobado con test_move (nunca atraviesa geometría).
func _stuck_check(delta: float, wants_move: bool, spd: float, nav: NavGrid, dist: float, approaching: bool) -> void:
	_stk_acc += delta
	if _stk_acc < 0.25:
		return
	var step_t := _stk_acc
	var moved := Vector2(global_position.x - _stk_pos.x, global_position.z - _stk_pos.z).length()
	_stk_pos = global_position
	var expect := spd * step_t * 0.3
	_stk_acc = 0.0
	# progreso hacia el objetivo (deslizarse por una pared no cuenta): pasos de ruta si hay campo, metros si no
	var mode := 0
	var metric := dist
	if nav != null and _wp_info == 1:
		var dd := nav.dist_at(global_position, nav_cls)
		if dd >= 0:
			mode = 1
			metric = float(dd)
	if mode != _prog_mode:
		_prog_mode = mode
		_prog_best = metric
		_prog_t = 0.0
	elif approaching and wants_move:
		if metric < _prog_best - (0.9 if mode == 1 else 0.4):
			_prog_best = metric
			_prog_t = 0.0
		else:
			_prog_t += step_t
	else:
		_prog_best = metric
		_prog_t = 0.0
	if wants_move and (moved < maxf(0.05, expect) or _prog_t >= 1.5) and _since_hit > 0.4:
		_stuck_t += 0.25
	else:
		_stuck_t = maxf(0.0, _stuck_t - 0.5)
		if _stuck_t <= 0.0:
			_stuck_lvl = 0
		return
	if nav == null:
		return
	if _stuck_t >= 0.5 and fmod(_stuck_t, 1.0) < 0.26 and _stuck_t < 6.0:
		if _stuck_lvl < 1:
			_stuck_lvl = 1
			nav_unstuck_count += 1
		_wp_t = 0.0                                  # recalcular la ruta ya
		nav.request(nav_cls)
		nav.reprobe(get_world_3d().direct_space_state, global_position, 5)   # ¿hay algo que el mapa no conocía?
	if _stuck_t >= 1.0 and _stuck_lvl < 2:
		_stuck_lvl = 2
		var alt := nav.alt_point(global_position, nav_cls, _strafe_dir)
		if alt != Vector3.INF:
			_detour_pt = alt
			_detour_t = 1.2
		_strafe_dir = -_strafe_dir
	elif _stuck_t >= 2.0 and _stuck_lvl < 3:
		_stuck_lvl = 3
		var wk := nav.nearest_walkable(global_position, nav_cls)
		if wk != Vector3.INF and (wk - global_position).length() > 0.3:
			_detour_pt = wk
			_detour_t = 1.0
		else:
			var alt2 := nav.alt_point(global_position, nav_cls, -_strafe_dir)
			if alt2 != Vector3.INF:
				_detour_pt = alt2
				_detour_t = 1.2
		_slot_off = -_slot_off
	elif _stuck_t >= 4.0 and _stuck_lvl < 4:
		_stuck_lvl = 4
		_unstick_hop(nav)
		_stuck_t = 2.0
		_stuck_lvl = 2


## Último recurso: desplazamiento corto (≤1.5 m) hacia donde la rejilla dice que se puede estar, solo si el motor confirma que no choca.
func _unstick_hop(nav: NavGrid) -> void:
	var cands: Array = []
	var wk := nav.nearest_walkable(global_position, nav_cls)
	if wk != Vector3.INF:
		cands.append(wk - global_position)
	var a0 := randf() * TAU
	for k in 6:
		cands.append(Vector3(cos(a0 + k * 1.047), 0, sin(a0 + k * 1.047)) * 1.2)
	for v in cands:
		var m: Vector3 = v
		m.y = 0.0
		m = m.limit_length(1.5)
		if m.length() < 0.2:
			continue
		if not test_move(global_transform, m):
			global_position += m
			velocity = Vector3.ZERO
			return


# ------------------------------------------------------------------ ataques
func _attack_list() -> Array:
	if kind == "boss":
		var bst: Dictionary = EnemyDefs.BOSS_STYLES.get(boss_style, EnemyDefs.BOSS_STYLES["urban"])
		return (bst["phases"] as Dictionary)[clampi(phase, 1, 3)]
	return def["attacks"]


func _pick_attack(dist: float) -> String:
	var opts: Array = []
	for n in _attack_list():
		if float(_cds.get(n, 0.0)) > 0.0:
			continue
		var a: Dictionary = EnemyDefs.ATTACKS[n]
		if dist <= float(a["range"]) and dist >= float(a["min_range"]):
			opts.append(n)
	if opts.is_empty():
		return ""
	# prioriza los ataques de mayor alcance mínimo (cargas) y reparte el resto al azar
	return opts[randi() % opts.size()]


func _begin_attack(name: String, p: Player) -> void:
	_atk_name = name
	_atk = EnemyDefs.ATTACKS[name]
	var to := _flat_to(p)
	_aim_dir = to.normalized() if to.length() > 0.01 else -global_transform.basis.z
	_aim_yaw = atan2(-_aim_dir.x, -_aim_dir.z)
	rotation.y = _aim_yaw
	var tele := float(_atk["tele"])
	if phase >= 3:
		tele *= 0.85
	_t = tele
	_dash_hit = false
	_dash_left = 0.0
	_set_state(S.TELE)
	var fx = GameState.fx
	if fx != null:
		var col := Color(1.0, 0.15, 0.1)
		if affix == "explosivo":
			col = Color(1.0, 0.45, 0.1)
		var pos := global_position
		match String(_atk["shape"]):
			"cone":
				_tele_items.append(fx.telegraph_cone(pos, _aim_yaw, float(_atk["radius"]), float(_atk["angle"]), tele, col))
			"circle":
				_tele_items.append(fx.telegraph_circle(pos, float(_atk["radius"]), tele, col))
			"line":
				_tele_items.append(fx.telegraph_line(pos, _aim_yaw, float(_atk["length"]), float(_atk["width"]), tele, col))
			"aim":
				if int(_atk.get("count", 1)) > 1:
					_tele_items.append(fx.telegraph_cone(pos, _aim_yaw, 14.0, float(_atk["spread"]) + 10.0, tele, col))
				else:
					_tele_items.append(fx.telegraph_line(pos, _aim_yaw, 14.0, 0.7, tele, col))
			"circles":
				_barrage_pts.clear()
				var pp: Vector3 = p.global_position
				_barrage_pts.append(Vector3(pp.x, 0, pp.z))
				for i in int(_atk["n"]) - 1:
					var a := randf() * TAU
					var r := randf_range(2.0, 8.0)
					_barrage_pts.append(Vector3(pp.x + cos(a) * r, 0, pp.z + sin(a) * r))
				for bp in _barrage_pts:
					_tele_items.append(fx.telegraph_circle(bp, float(_atk["radius"]), tele, col))
			"summon":
				_tele_items.append(fx.telegraph_circle(pos, float(_atk["radius"]), tele, Color(0.75, 0.3, 1.0)))
			"leap":
				var tgt: Vector3 = p.global_position
				if bool(_atk.get("behind", false)):
					var away := tgt - global_position
					away.y = 0.0
					tgt += (away.normalized() if away.length() > 0.01 else Vector3.BACK) * 3.0
				var hh := 14.0
				if GameState.arena != null:
					hh = float(GameState.arena.half) - 2.5
				_leap_to = Vector3(clampf(tgt.x, -hh, hh), global_position.y, clampf(tgt.z, -hh, hh))
				_tele_items.append(fx.telegraph_circle(_leap_to, float(_atk["radius"]), tele, col))
			"beam":
				_tele_items.append(fx.telegraph_line(pos, _aim_yaw, float(_atk["length"]), float(_atk["width"]), tele, col))
	AudioManager.sfx_at("telegraph", global_position, -8.0)
	var an := String(_atk["anim"])
	rig.play("windup" if an in ["slam", "swing", "windup"] else an, tele + 0.05)
	if an in ["roar", "summon", "shoot"]:
		rig.play(an, tele + float(_atk["recover"]) * 0.5)


func _tele_tick(delta: float, _p: Player) -> void:
	_t -= delta
	rotation.y = _aim_yaw
	_move_toward_dir(Vector3.ZERO, 0.0, delta)
	if _t <= 0.0:
		_execute_attack()


func _execute_attack() -> void:
	var p := _player()
	_clear_tele()
	var a := _atk
	var dmg := dmg_base * float(a["dmg"])
	var an := String(a["anim"])
	if an in ["slam", "swing"]:
		rig.play(an, 0.45)
	_cds[_atk_name] = float(a["cd"]) * randf_range(0.9, 1.15)
	var shape := String(a["shape"])
	_t = 0.12
	_wave_n = int(a.get("waves", 1)) - 1
	_wave_k = 1
	_wave_t = float(a.get("wave_gap", 0.3))
	_wave_dmg = dmg
	match shape:
		"cone":
			if a.has("proj"):
				_fire_projectiles(dmg)
			elif p != null:
				var to := _flat_to(p)
				var ang := absf(rad_to_deg(_aim_dir.angle_to(to)))
				if to.length() <= float(a["radius"]) + 0.45 and ang <= float(a["angle"]) * 0.5 + 6.0:
					p.take_damage(dmg, global_position, {"src": "melee", "enemy": self})
			_fx_impact(global_position + _aim_dir * 1.5, float(a.get("radius", 3.0)) * 0.5, float(a.get("shake", 0.2)))
			_after_act()
		"circle":
			if a.has("proj"):
				_fire_projectiles(dmg)
			elif p != null and _flat_to(p).length() <= float(a["radius"]) + 0.4:
				p.take_damage(dmg, global_position, {"src": "slam", "enemy": self})
			_fx_impact(global_position, float(a["radius"]), float(a.get("shake", 0.3)))
			_after_act()
		"circles":
			for bp in _barrage_pts:
				if p != null:
					var d: Vector3 = p.global_position - bp
					d.y = 0.0
					if d.length() <= float(a["radius"]) + 0.4:
						p.take_damage(dmg, bp, {"src": "barrage", "enemy": self})
						_barrage_pts = []
						break
			if GameState.fx != null:
				for bp in _barrage_pts:
					GameState.fx.ring(bp, float(a["radius"]), Color(1.0, 0.5, 0.2, 0.85), 0.35, 0.3)
					GameState.fx.burst(bp + Vector3(0, 0.4, 0), Color(1.0, 0.6, 0.2), 6, 5.0, 0.14, 0.4)
			AudioManager.sfx_at("explosion", global_position, -6.0)
			_barrage_pts = []
			_after_act()
		"aim":
			_fire_projectiles(dmg)
			_after_act()
		"line":
			_dash_left = float(a["length"]) / float(a["dash_speed"])
			_t = _dash_left
			_set_state(S.ACT)
			rig.play("windup", _dash_left)
			rig.charging = true
			AudioManager.sfx_at("dodge", global_position, -6.0)
		"leap":
			_leap_from = global_position
			_leap_dur = float(a.get("dur", 0.5))
			_leap_t = _leap_dur
			_set_state(S.ACT)
			rig.play("windup", _leap_dur + 0.1)
			AudioManager.sfx_at("dodge", global_position, -6.0)
		"beam":
			_beam_strike(_aim_dir, dmg, a)
			if _wave_n > 0:
				_wave_tele_next()
			_after_act()
		"summon":
			var n := int(a.get("count", 2))
			var minion := String(a.get("minion", "thief"))
			if kind == "boss":
				if not a.has("minion"):
					minion = "ranged" if phase >= 2 and randf() < 0.4 else "thief"
				n += phase - 1
			elif arena_index >= 6 and randf() < 0.4:
				minion = "runner"
			for i in n:
				var ang := TAU * float(i) / float(n) + randf() * 0.5
				var sp := global_position + Vector3(cos(ang), 0, sin(ang)) * (2.0 + vscale)
				request_spawn.emit(minion, sp)
			_fx_impact(global_position, float(a["radius"]), 0.15)
			_after_act()


func _act_tick(delta: float, p: Player) -> void:
	if _leap_t > 0.0:
		_leap_t -= delta
		var k := 1.0 - clampf(_leap_t / _leap_dur, 0.0, 1.0)
		var pp := _leap_from.lerp(_leap_to, k)
		pp.y = _leap_from.y + sin(k * PI) * (3.2 if _leap_dur > 0.2 else 0.4)
		global_position = pp
		velocity = Vector3.ZERO
		if _leap_t <= 0.0:
			global_position = _leap_to
			var a := _atk
			if p != null and _flat_to(p).length() <= float(a["radius"]) + 0.4:
				p.take_damage(dmg_base * float(a["dmg"]), global_position, {"src": "slam", "enemy": self})
			_fx_impact(global_position, float(a["radius"]), float(a.get("shake", 0.5)))
			_after_act()
		return
	# fase activa: solo las cargas (línea) pasan por aquí
	if _dash_left > 0.0:
		_dash_left -= delta
		var sp := float(_atk["dash_speed"])
		var dir := _aim_dir
		var hv := dir * sp
		velocity.x = hv.x
		velocity.z = hv.z
		if is_on_floor():
			velocity.y = -1.0
		else:
			velocity.y -= GRAVITY * delta
		move_and_slide()
		if p != null and not _dash_hit:
			var d := _flat_to(p)
			if d.length() < float(_atk["width"]) * 0.5 + 0.7:
				_dash_hit = true
				p.take_damage(dmg_base * float(_atk["dmg"]), global_position, {"src": "charge", "enemy": self})
		if is_on_wall() and kind != "boss":
			_dash_left = 0.0
		if _dash_left <= 0.0:
			rig.charging = false
			_fx_impact(global_position, 2.0, 0.25)
			_after_act()
		return
	_t -= delta
	_move_toward_dir(Vector3.ZERO, 0.0, delta)
	if _t <= 0.0:
		_after_act()


## Rayo en línea: daña (una vez) si el jugador está dentro del pasillo; efectos a lo largo de la línea.
func _beam_strike(dir: Vector3, dmg: float, a: Dictionary) -> void:
	var p := _player()
	var blen := float(a["length"])
	var w := float(a["width"])
	if p != null:
		var rel := p.global_position - global_position
		rel.y = 0.0
		var along := rel.dot(dir)
		var side := absf(rel.cross(dir).y)
		if along >= 0.0 and along <= blen and side <= w * 0.5 + 0.4:
			p.take_damage(dmg, global_position, {"src": "beam", "enemy": self})
	var fx = GameState.fx
	if fx != null:
		var steps := int(blen / 3.0)
		for i in steps:
			var q := global_position + dir * (2.0 + 3.0 * float(i)) + Vector3(0, 0.5, 0)
			fx.burst(q, Color(1.0, 0.45, 0.25), 4, 5.0, 0.14, 0.35)
		fx.ring(global_position + dir * 2.0, 2.0, Color(1.0, 0.55, 0.25, 0.85), 0.3, 0.3)
	AudioManager.sfx_at("explosion", global_position, -5.0)
	if GameState.cam != null:
		GameState.cam.shake(0.25)


func _wave_tele_next() -> void:
	var fx = GameState.fx
	if fx == null:
		return
	var rot := deg_to_rad(float(_atk.get("wave_rot", 0.0))) * float(_wave_k)
	_tele_items.append(fx.telegraph_line(global_position, _aim_yaw + rot, float(_atk["length"]), float(_atk["width"]), float(_atk.get("wave_gap", 0.5)), Color(1.0, 0.15, 0.1)))


## Repeticiones de un ataque (espiral de proyectiles, rayos cruzados, ondas en cadena).
func _wave_tick(delta: float) -> void:
	_wave_t -= delta
	if _wave_t > 0.0:
		return
	var a := _atk
	var rot := deg_to_rad(float(a.get("wave_rot", 0.0))) * float(_wave_k)
	_wave_k += 1
	_wave_n -= 1
	_wave_t = float(a.get("wave_gap", 0.3))
	var shape := String(a.get("shape", ""))
	match shape:
		"beam":
			_clear_tele()
			_beam_strike(_aim_dir.rotated(Vector3.UP, rot), _wave_dmg, a)
			if _wave_n > 0:
				_wave_tele_next()
		"circle", "cone", "aim":
			if a.has("proj"):
				var base := _aim_dir
				var p := _player()
				if rot == 0.0 and p != null:
					var to := _flat_to(p)
					if to.length() > 0.01:
						_aim_dir = to.normalized()
				else:
					_aim_dir = base.rotated(Vector3.UP, rot)
				_fire_projectiles(_wave_dmg)
				_aim_dir = base
			else:
				var p2 := _player()
				if p2 != null and _flat_to(p2).length() <= float(a["radius"]) + 0.4:
					p2.take_damage(_wave_dmg, global_position, {"src": "slam", "enemy": self})
				_fx_impact(global_position, float(a["radius"]), float(a.get("shake", 0.3)))


func _after_act() -> void:
	rig.charging = false
	var rec := float(_atk.get("recover", 0.6))
	if kind == "boss":
		rec *= 1.0 - 0.12 * (phase - 1)
	_t = rec
	_gate = ((0.35 if not is_boss else 0.55) + randf() * 0.4) * (Scaling.attack_pace(arena_index) if is_elite else 1.0)
	_set_state(S.RECOVER)


func _fire_projectiles(dmg: float) -> void:
	var pr = GameState.projectiles
	if pr == null:
		return
	var a := _atk
	var n := int(a.get("count", 1))
	var spread := deg_to_rad(float(a.get("spread", 0.0)))
	var from := global_position + Vector3(0, 1.3 * vscale, 0) + _aim_dir * 0.7 * vscale
	var pk := String(a.get("proj", "coin"))
	var spd := float(a.get("speed", 12.0))
	var full_circle := float(a.get("spread", 0.0)) >= 359.0
	for i in n:
		var ang := 0.0
		if n > 1:
			ang = TAU * float(i) / float(n) if full_circle else lerpf(-spread * 0.5, spread * 0.5, float(i) / float(n - 1))
		var d := _aim_dir.rotated(Vector3.UP, ang)
		var radius := 0.34 if pk == "blob" else 0.3
		pr.fire_enemy(pk, from, d, dmg, spd, radius, 4.5)
	AudioManager.sfx_at("enemy_shoot", global_position, -6.0)


func _fx_impact(pos: Vector3, radius: float, shake: float) -> void:
	var fx = GameState.fx
	if fx != null:
		fx.ring(pos, radius, Color(1.0, 0.55, 0.25, 0.8), 0.3, 0.3)
		fx.burst(pos + Vector3(0, 0.3, 0), Color(0.9, 0.8, 0.6), 5, 4.0, 0.12, 0.35)
	var p = GameState.player
	if shake > 0.0 and p != null and GameState.cam != null:
		if global_position.distance_to(p.global_position) < 18.0:
			GameState.cam.shake(shake * (1.0 if is_boss else 0.6))
	if shake >= 0.4:
		AudioManager.sfx_at("slam", pos, -4.0)


func _clear_tele() -> void:
	var fx = GameState.fx
	if fx != null:
		for it in _tele_items:
			if it != null:
				fx.cancel(it)
	_tele_items.clear()


func _interrupt() -> void:
	_wave_n = 0
	_leap_t = 0.0
	_clear_tele()
	_barrage_pts.clear()
	rig.charging = false
	_dash_left = 0.0
	rig.action = ""


# ------------------------------------------------------------------ daño y estados
## Devuelve true si el golpe mata al enemigo.
func take_damage(dmg: float, info: Dictionary = {}) -> bool:
	if not alive or state == S.DEAD:
		return false
	if state == S.SPAWN:
		return false
	if invuln_t > 0.0:
		Feedback.immune(self)
		return false
	dmg = maxf(0.0, dmg)
	if is_elite:
		dmg *= 1.0 - Scaling.elite_resist(arena_index)
	var hp_before := hp
	hp -= dmg
	_since_hit = 0.0
	GameState.run_stats["damage_dealt"] += dmg
	var crit: bool = info.get("crit", false)
	var src: String = info.get("src", "")
	# Número flotante + sonido: mismo evento, mismo valor (sobredaño incluido) que el daño aplicado.
	Feedback.on_damage(self, dmg, info, hp_before, max_hp, hp <= 0.0)
	if src != "burn" and dmg > 0.0:
		rig.hit_flash(0.7)
	var kb: Vector3 = info.get("knock", Vector3.ZERO)
	if kb.length() > 0.01:
		_kb += kb * (1.0 - float(def.get("knock_res", 0.0))) * 1.6
		_kb.y = 0.0
	if aggro_range < 900.0 and state == S.PATROL:
		_set_state(S.CHASE)
		aggro_range = 999.0
	if is_boss:
		GameState.boss_bar.emit(true, display_name, maxf(hp, 0.0), max_hp)
	_update_bar()
	if hp <= 0.0:
		_die(info)
		return true
	# interrupción: los enemigos ligeros pierden el ataque al ser golpeados
	var light := float(def.get("knock_res", 0.0)) < 0.3
	if light and src != "burn" and src != "chain" and dmg > 0.0:
		if state == S.TELE or state == S.CHASE or state == S.RECOVER or state == S.PATROL:
			if state == S.TELE:
				_interrupt()
				_cds[_atk_name] = float(_atk.get("cd", 1.0)) * 0.5
			_t = 0.22 if crit else 0.14
			_set_state(S.HURT)
			rig.play("stagger", _t + 0.1)
	var stagger: float = info.get("stagger", 0.0)
	if stagger > 0.0 and not is_boss and state != S.DEAD:
		_interrupt()
		_t = stagger
		_set_state(S.HURT)
		rig.play("stagger", stagger)
	# fases del jefe
	if kind == "boss":
		var f := hp_frac()
		var np := 1 if f > 0.66 else (2 if f > 0.33 else 3)
		if np > phase:
			_enter_phase(np)
	return false


func _enter_phase(np: int) -> void:
	phase = np
	_interrupt()
	invuln_t = 1.8
	_t = 1.8
	_set_state(S.PHASE)
	rig.play("roar", 1.6)
	move_speed *= 1.1
	_cds.clear()
	if GameState.fx != null:
		GameState.fx.ring(global_position, 9.0, Color(1.0, 0.3, 0.3, 0.9), 0.8, 0.5)
		GameState.fx.flash_sphere(global_position + Vector3(0, 1.5, 0), 3.5, Color(1.0, 0.4, 0.3, 0.6), 0.5)
	if GameState.cam != null:
		GameState.cam.shake(0.8)
	AudioManager.sfx("phase")
	AudioManager.sfx("boss_roar", -2.0)
	GameState.toast_msg("¡%s entra en FASE %d!" % [display_name, np], Color(1.0, 0.45, 0.35))
	for i in 3:
		var ang := TAU * float(i) / 3.0 + randf()
		request_spawn.emit("thief" if np == 2 else "runner", global_position + Vector3(cos(ang), 0, sin(ang)) * 4.5)


func _die(info: Dictionary) -> void:
	alive = false
	hp = 0.0
	state = S.DEAD
	_interrupt()
	_dead_t = 1.2
	_col.disabled = true
	if _bar != null:
		_bar.visible = false
	rig.die(0.9)
	velocity = Vector3.ZERO
	if GameState.fx != null:
		GameState.fx.burst(global_position + Vector3(0, 1.0, 0), Color(1.0, 0.9, 0.5), 10 if not is_boss else 24, 6.0, 0.14, 0.6)
	if is_boss:
		GameState.boss_bar.emit(false, display_name, 0.0, max_hp)
		GameState.run_stats["bosses"] += 1 if kind == "boss" else 0
		if GameState.cam != null:
			GameState.cam.shake(0.9)
	if affix == "explosivo":
		_boom_t = 0.7
		if GameState.fx != null:
			GameState.fx.telegraph_circle(global_position, 3.2, 0.7, Color(1.0, 0.45, 0.1))
	set_status_clear()
	Combat.on_kill(self, info)
	GameState.register_kill(self, xp_value, coin_value)
	died.emit(self)


func set_status_clear() -> void:
	marked_t = 0.0
	slow_t = 0.0
	burn_t = 0.0
	freeze_t = 0.0


func _dead_tick(delta: float) -> void:
	_dead_t -= delta
	if _boom_t > 0.0:
		_boom_t -= delta
		if _boom_t <= 0.0:
			_boom_t = -1.0
			var p := _player()
			if GameState.fx != null:
				GameState.fx.ring(global_position, 3.2, Color(1.0, 0.5, 0.15, 0.9), 0.35, 0.3)
				GameState.fx.flash_sphere(global_position + Vector3(0, 0.6, 0), 1.8, Color(1.0, 0.6, 0.2, 0.8), 0.25)
			AudioManager.sfx_at("explosion", global_position, -3.0)
			if p != null and _flat_to(p).length() < 3.4:
				p.take_damage(dmg_base * 1.3, global_position, {"src": "explosion", "enemy": self})
	if _dead_t <= 0.0 and _boom_t < 0.0:
		visible = false
		set_physics_process(false)
		despawned.emit(self)


func _tick_status(delta: float) -> void:
	if marked_t > 0.0:
		marked_t -= delta
	if slow_t > 0.0:
		slow_t -= delta
	if burn_t > 0.0:
		burn_t -= delta
		_burn_tick -= delta
		if _burn_tick <= 0.0:
			_burn_tick = 0.5
			take_damage(burn_dps * 0.5, {"src": "burn", "element": "fire"})
			if state == S.DEAD:
				return
	if affix == "regenerante" and _since_hit > 3.0 and hp < max_hp:
		hp = minf(max_hp, hp + max_hp * 0.04 * delta)
		_update_bar()


func apply_burn(dps: float, dur: float) -> void:
	if not alive:
		return
	burn_dps = maxf(burn_dps if burn_t > 0.0 else 0.0, dps)
	burn_t = maxf(burn_t, dur)


func apply_slow(amt: float, dur: float) -> void:
	if not alive:
		return
	slow_amt = clampf(maxf(amt, slow_amt if slow_t > 0.0 else 0.0), 0.0, 0.7 if not is_boss else 0.35)
	slow_t = maxf(slow_t, dur)


func apply_freeze(dur: float) -> void:
	if not alive or is_boss or state == S.SPAWN or state == S.DEAD:
		return
	_interrupt()
	freeze_t = dur
	_set_state(S.FROZEN)


func apply_mark(dur: float) -> void:
	if alive:
		marked_t = maxf(marked_t, dur)


func _update_visual_status() -> void:
	if rig == null:
		return
	var frost := 1.0 if state == S.FROZEN else (0.45 if slow_t > 0.0 else 0.0)
	var burn := 1.0 if burn_t > 0.0 else 0.0
	var tint := Color(1, 1, 1)
	if affix != "" and EnemyDefs.AFFIXES.has(affix):
		tint = EnemyDefs.AFFIXES[affix]["tint"]
	if marked_t > 0.0:
		tint = tint.lerp(Color(0.85, 0.4, 1.0), 0.55)
	var key := "%s|%s|%s" % [frost, burn, tint]
	if key == _vis_key:
		return
	_vis_key = key
	rig.set_status_visual(frost, burn, tint)


func _apply_visual(tint: Color) -> void:
	_vis_key = ""
	rig.set_status_visual(0.0, 0.0, tint)


func debug_text() -> String:
	return "%s %s hp %.0f/%.0f st %d" % [kind, affix, hp, max_hp, state]
