class_name Player
extends CharacterBody3D
## Controlador del abogado: movimiento 3D relativo a la cámara, salto (con saltos extra),
## esquiva/deslizamiento con fotogramas de invulnerabilidad, salud/escudo/armadura,
## muerte y reaparición, e interacción con cofres/tienda/portales.

signal died
signal interact_target_changed(target: Node)

var rig: Rig
var skills: Skills
var cam: CameraRig

var alive := true
var hp := 100.0
var max_hp := 100.0
var shield := 0.0
var shield_max := 0.0
var iframes := 0.0
var hurt_iframes := 0.0
var revives_left := 0
var kill_speed_t := 0.0
var _since_hurt := 99.0
var _heal_budget := 14.0
var _dodge_t := 0.0
var _dodge_cd := 0.0
var _dodge_dir := Vector3.ZERO
var _trail_hit: Array = []
var _trail_tick := 0.0
var _coyote := 0.0
var _jump_buffer := 0.0
var _jumps_left := 0
var _was_on_floor := true
var _step_t := 0.0
var _face_override_t := 0.0
var _face_yaw := 0.0
var _stun_t := 0.0
var interact_target: Interactable = null
var _aura: MeshInstance3D
var _aura_t := 0.0
var _last_max_hp := 100.0
var _regen_acc := 0.0
var _joy := Vector2.ZERO


func _ready() -> void:
	collision_layer = Config.L_PLAYER
	collision_mask = Config.L_WORLD
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(52.0)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.38
	cap.height = 1.7
	cs.shape = cap
	cs.position = Vector3(0, 0.85, 0)
	add_child(cs)
	rig = ModelFactory.build_lawyer()
	add_child(rig)
	skills = Skills.new()
	add_child(skills)
	skills.setup(self)
	# aura de build (se enciende con las sinergias)
	_aura = MeshInstance3D.new()
	var rm := FX._ring_mesh()
	_aura.mesh = rm
	_aura.material_override = Mats.fx_material(Color(0.3, 0.9, 1.0, 0.0), true)
	_aura.position = Vector3(0, 0.06, 0)
	_aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aura.visible = false
	add_child(_aura)
	GameState.build.changed.connect(_on_build_changed)
	GameState.player = self


func reset_for_run() -> void:
	alive = true
	rig.revive()
	skills.reset()
	var b: Build = GameState.build
	max_hp = compute_max_hp()
	hp = max_hp
	shield_max = b.s("shield_max")
	shield = shield_max
	revives_left = int(b.s("revives"))
	iframes = 1.0
	hurt_iframes = 0.0
	velocity = Vector3.ZERO
	_dodge_t = 0.0
	_dodge_cd = 0.0
	_stun_t = 0.0
	_last_max_hp = max_hp
	emit_hp()
	GameState.energy_changed.emit(skills.energy, skills.energy_max)


## Aplica la salud/escudo/revivires de una partida guardada (después de reset_for_run).
func apply_saved(r: Dictionary) -> void:
	hp = clampf(float(r["hp"]), 1.0, max_hp)
	shield = clampf(float(r["shield"]), 0.0, shield_max)
	revives_left = int(r["revives_left"])
	emit_hp()


func compute_max_hp() -> float:
	var b: Build = GameState.build
	return maxf(30.0, (float(Config.PLAYER["max_hp"]) + b.s("max_hp_flat")) * (1.0 + b.s("max_hp_pct")))


func _on_build_changed() -> void:
	var nm := compute_max_hp()
	if absf(nm - _last_max_hp) > 0.01 and alive:
		# mantener la proporción y sumar lo ganado
		if nm > _last_max_hp:
			hp += nm - _last_max_hp
		hp = minf(hp, nm)
		max_hp = nm
		_last_max_hp = nm
	else:
		max_hp = nm
	var old_shield_max := shield_max
	shield_max = GameState.build.s("shield_max")
	if shield_max > old_shield_max:
		shield += shield_max - old_shield_max
	revives_left = maxi(revives_left, 0)
	emit_hp()


func emit_hp() -> void:
	GameState.player_hp_changed.emit(hp, max_hp, shield, shield_max)


func facing_dir() -> Vector3:
	return Basis(Vector3.UP, rotation.y) * Vector3(0, 0, -1)


func face_dir(d: Vector3, hold := 0.3) -> void:
	if d.length() < 0.01:
		return
	_face_yaw = atan2(-d.x, -d.z)
	_face_override_t = hold
	rotation.y = lerp_angle(rotation.y, _face_yaw, 0.65)


func stunned() -> bool:
	return _stun_t > 0.0


func move_speed() -> float:
	var b: Build = GameState.build
	var bonus := b.s("move_speed")
	if kill_speed_t > 0.0:
		bonus += b.s("kill_speed")
	return float(Config.PLAYER["move_speed"]) * (1.0 + minf(bonus, 1.6))


func _input_vector() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_forward", "move_back")


func _physics_process(delta: float) -> void:
	if not alive:
		velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 30.0 * delta)
		velocity.y -= float(Config.PLAYER["gravity"]) * delta
		move_and_slide()
		return
	var b: Build = GameState.build
	# --- temporizadores ---
	iframes = maxf(0.0, iframes - delta)
	hurt_iframes = maxf(0.0, hurt_iframes - delta)
	kill_speed_t = maxf(0.0, kill_speed_t - delta)
	_stun_t = maxf(0.0, _stun_t - delta)
	_dodge_cd = maxf(0.0, _dodge_cd - delta)
	_since_hurt += delta
	_face_override_t = maxf(0.0, _face_override_t - delta)
	_heal_budget = minf(14.0, _heal_budget + 14.0 * delta)
	skills.update(delta)
	_update_regen(delta, b)
	# --- entrada de movimiento ---
	var iv := _input_vector()
	var yaw: float = cam.yaw if cam != null else 0.0
	var move_dir := Basis(Vector3.UP, yaw) * Vector3(iv.x, 0, iv.y)
	var strength := minf(iv.length(), 1.0)
	var on_floor := is_on_floor()
	if on_floor:
		_coyote = 0.12
		_jumps_left = int(b.s("extra_jumps"))
		if not _was_on_floor:
			AudioManager.sfx("land", -8.0)
	else:
		_coyote = maxf(0.0, _coyote - delta)
	_was_on_floor = on_floor
	# --- esquiva / deslizamiento ---
	if Input.is_action_just_pressed("dodge"):
		_try_dodge(move_dir)
	if _dodge_t > 0.0:
		_dodge_t -= delta
		var dspeed: float = float(Config.PLAYER["dodge_speed"]) * (1.0 + b.s("dodge_trail") * 0.0)
		velocity.x = _dodge_dir.x * dspeed
		velocity.z = _dodge_dir.z * dspeed
		_trail_tick -= delta
		if b.s("dodge_trail") > 0.0 and _trail_tick <= 0.0:
			_trail_tick = 0.07
			for e in Combat.enemies_in_radius(global_position, 1.6):
				if not _trail_hit.has(e):
					_trail_hit.append(e)
					Combat.player_hit(e, b.s("dodge_trail"), {"src": "trail", "flat": false, "knock": _dodge_dir * 3.0})
			if GameState.fx != null:
				GameState.fx.burst(global_position + Vector3(0, 0.2, 0), Color(0.5, 0.85, 1.0), 3, 2.0, 0.12, 0.35)
		rig.sliding = true
		if _dodge_t <= 0.0:
			rig.sliding = false
	else:
		rig.sliding = false
		# --- movimiento normal ---
		var spd := move_speed() * (1.0 if strength > 0.55 else 0.65)
		var target_v := move_dir * spd * strength
		if _stun_t > 0.0:
			target_v *= 0.2
		var accel := float(Config.PLAYER["accel"]) if strength > 0.05 else float(Config.PLAYER["friction"])
		if not on_floor:
			accel *= 0.6
		velocity.x = move_toward(velocity.x, target_v.x, accel * delta)
		velocity.z = move_toward(velocity.z, target_v.z, accel * delta)
	# --- salto ---
	if Input.is_action_just_pressed("jump"):
		_jump_buffer = 0.14
	_jump_buffer = maxf(0.0, _jump_buffer - delta)
	if _jump_buffer > 0.0 and _stun_t <= 0.0:
		if _coyote > 0.0:
			_do_jump()
			_coyote = 0.0
		elif _jumps_left > 0:
			_jumps_left -= 1
			_do_jump()
			if GameState.fx != null:
				GameState.fx.ring(global_position, 1.2, Color(0.8, 0.9, 1.0, 0.7), 0.3, 0.2)
	velocity.y -= float(Config.PLAYER["gravity"]) * delta
	move_and_slide()
	# --- orientación ---
	var hv := Vector2(velocity.x, velocity.z)
	if _face_override_t > 0.0:
		rotation.y = lerp_angle(rotation.y, _face_yaw, 1.0 - exp(-delta * 22.0))
	elif hv.length() > 0.6 and _dodge_t <= 0.0:
		var yaw_t := atan2(-hv.x, -hv.y)
		rotation.y = lerp_angle(rotation.y, yaw_t, 1.0 - exp(-delta * 14.0))
	elif _dodge_t > 0.0:
		rotation.y = lerp_angle(rotation.y, atan2(-_dodge_dir.x, -_dodge_dir.z), 1.0 - exp(-delta * 20.0))
	# --- animación ---
	rig.speed_norm = clampf(hv.length() / maxf(move_speed(), 0.1), 0.0, 1.0) if on_floor else 0.0
	rig.airborne = not on_floor and _dodge_t <= 0.0
	rig.vy = velocity.y
	# --- pasos ---
	if on_floor and hv.length() > 2.0 and _dodge_t <= 0.0:
		_step_t -= delta * (hv.length() / 7.0)
		if _step_t <= 0.0:
			_step_t = 0.34
			AudioManager.sfx_random("step", 3, -14.0)
	# --- ataque automático / mantenido ---
	if Input.is_action_pressed("attack") or (bool(SaveSystem.setting("auto_attack")) and _enemy_in_reach()):
		skills.try_cast(0)
	if Input.is_action_just_pressed("skill1"):
		skills.try_cast(1)
	if Input.is_action_just_pressed("skill2"):
		skills.try_cast(2)
	if Input.is_action_just_pressed("skill3"):
		skills.try_cast(3)
	# --- interacción ---
	_update_interaction()
	if Input.is_action_just_pressed("interact") and interact_target != null:
		interact_target.activate(self)
	_update_aura(delta)
	GameState.energy_changed.emit(skills.energy, skills.energy_max)


func _enemy_in_reach() -> bool:
	var e := Combat.nearest_enemy(global_position, 4.2)
	return e != null


func _do_jump() -> void:
	velocity.y = float(Config.PLAYER["jump_velocity"])
	_jump_buffer = 0.0
	AudioManager.sfx("jump", -8.0)
	floor_snap_length = 0.0
	get_tree().create_timer(0.12).timeout.connect(func(): floor_snap_length = 0.35)


func _try_dodge(move_dir: Vector3) -> void:
	if _dodge_cd > 0.0 or _dodge_t > 0.0 or _stun_t > 0.0:
		return
	var b: Build = GameState.build
	_dodge_dir = move_dir.normalized() if move_dir.length() > 0.1 else facing_dir()
	_dodge_t = float(Config.PLAYER["dodge_time"])
	_dodge_cd = float(Config.PLAYER["dodge_cd"]) * (1.0 - minf(b.s("dodge_cd"), 0.6))
	iframes = maxf(iframes, float(Config.PLAYER["iframes"]))
	_trail_hit.clear()
	_trail_tick = 0.0
	skills.dodge_haste_t = 2.5 if b.s("dodge_haste") > 0.0 else 0.0
	rig.play("dodge", _dodge_t)
	AudioManager.sfx("dodge", -4.0)
	if GameState.fx != null:
		GameState.fx.burst(global_position + Vector3(0, 0.3, 0), Color(0.8, 0.9, 1.0), 6, 3.0, 0.14, 0.35)


func dodge_cd_fraction() -> float:
	var b: Build = GameState.build
	var full := float(Config.PLAYER["dodge_cd"]) * (1.0 - minf(b.s("dodge_cd"), 0.6))
	return clampf(_dodge_cd / maxf(full, 0.01), 0.0, 1.0)


# ------------------------------------------------------------------ salud
func _update_regen(delta: float, b: Build) -> void:
	var regen := b.s("regen")
	if regen > 0.0 and hp < max_hp:
		_regen_acc += regen * delta
		if _regen_acc >= 0.5:
			hp = minf(max_hp, hp + _regen_acc)
			_regen_acc = 0.0
			emit_hp()
	if shield < shield_max and _since_hurt > float(Config.PLAYER["shield_regen_delay"]):
		shield = minf(shield_max, shield + float(Config.PLAYER["shield_regen"]) * delta)
		emit_hp()


func heal(amount: float) -> void:
	if not alive:
		return
	hp = minf(max_hp, hp + amount)
	emit_hp()
	if GameState.fx != null and amount >= 1.0:
		GameState.fx.damage_number(global_position + Vector3(0, 2.2, 0), "+%d" % int(round(amount)), Color(0.4, 1.0, 0.5), 0.9)


func heal_limited(amount: float) -> void:
	if _heal_budget <= 0.0 or hp >= max_hp:
		return
	var a := minf(amount, _heal_budget)
	_heal_budget -= a
	hp = minf(max_hp, hp + a)
	emit_hp()


func take_damage(amount: float, from_pos: Vector3, info: Dictionary = {}) -> void:
	if not alive or Config.dev_god_mode:
		return
	if iframes > 0.0 or hurt_iframes > 0.0:
		return
	var b: Build = GameState.build
	if b.s("block") > 0.0 and randf() < b.s("block"):
		if GameState.fx != null:
			GameState.fx.damage_number(global_position + Vector3(0, 2.3, 0), "¡OBJECIÓN!", Color(0.5, 0.9, 1.0), 1.0)
		AudioManager.sfx("shield", -4.0)
		return
	var dmg := amount * (1.0 - minf(b.s("armor"), 0.6)) * (1.0 + b.s("dmg_taken"))
	dmg = skills.absorb(dmg)
	if dmg <= 0.01:
		hurt_iframes = 0.15
		return
	_since_hurt = 0.0
	GameState.run_stats["damage_taken"] += dmg
	var shield_before := shield
	if shield > 0.0:
		var absorbed := minf(shield, dmg)
		shield -= absorbed
		dmg -= absorbed
		if shield <= 0.0 and shield_before > 0.0:
			AudioManager.sfx("shield", -2.0)
			if b.s("syn_shield_blast") > 0.0:
				Combat.explode(global_position, 5.0 * Combat.area_mult(), b.s("thorns") * 5.0 + 20.0, {"src": "thorns"})
	if dmg > 0.0:
		hp -= dmg
	hurt_iframes = 0.4
	rig.play("hit", 0.28)
	rig.hit_flash(0.8)
	AudioManager.sfx("hurt", -2.0)
	if GameState.cam != null:
		GameState.cam.shake(0.35)
	if bool(SaveSystem.setting("vibration")):
		Input.vibrate_handheld(35)
	if GameState.fx != null:
		GameState.fx.damage_number(global_position + Vector3(0, 2.3, 0), str(int(round(amount))), Color(1.0, 0.3, 0.3), 1.1)
		GameState.fx.burst(global_position + Vector3(0, 1.0, 0), Color(1.0, 0.3, 0.3), 6, 4.0, 0.12, 0.4)
	if b.s("thorns") > 0.0:
		Combat.explode(global_position, 3.4 * Combat.area_mult(), b.s("thorns"), {"src": "thorns", "element": "phys"})
	emit_hp()
	if hp <= 0.0:
		_die()


func _die() -> void:
	if revives_left > 0:
		revives_left -= 1
		hp = max_hp * 0.4
		iframes = 2.0
		emit_hp()
		AudioManager.sfx("levelup")
		GameState.toast_msg("¡Segunda Opinión! Reapareces", Color(1.0, 0.9, 0.4))
		if GameState.fx != null:
			GameState.fx.ring(global_position, 7.0, Color(1.0, 0.9, 0.4, 0.9), 0.6, 0.5)
			Combat.explode(global_position, 6.0, 60.0, {"src": "revive"})
		return
	hp = 0.0
	alive = false
	rig.die(1.0)
	velocity = Vector3.ZERO
	AudioManager.sfx("defeat")
	emit_hp()
	died.emit()


# ------------------------------------------------------------- interacción
func _update_interaction() -> void:
	var best: Interactable = null
	var best_d := 99999.0
	for n in get_tree().get_nodes_in_group("interactable"):
		var it := n as Interactable
		if it == null or not it.enabled or not it.is_inside_tree():
			continue
		var d := it.global_position.distance_to(global_position)
		if d <= it.radius and d < best_d:
			best_d = d
			best = it
	if best != interact_target:
		interact_target = best
		interact_target_changed.emit(best)


func _update_aura(delta: float) -> void:
	var n := GameState.build.active_synergies.size()
	var power := GameState.build.power_rating()
	var show := n > 0 or power > 3.0 or skills.takeover_ready
	_aura.visible = show and alive
	if not show:
		return
	_aura_t += delta
	var cols := [Color(0.3, 0.9, 1.0), Color(1.0, 0.8, 0.2), Color(1.0, 0.35, 0.8), Color(1, 1, 1)]
	var c: Color = cols[clampi(n - 1, 0, 3)] if n > 0 else Color(0.5, 0.8, 1.0)
	if skills.takeover_ready:
		c = Color(1.0, 0.6, 0.1)
	var r := 1.3 + 0.25 * sin(_aura_t * 4.0) + minf(n, 5) * 0.15
	_aura.scale = Vector3(r, 1, r)
	_aura.rotation.y += delta * 1.5
	(_aura.material_override as StandardMaterial3D).albedo_color = Color(c.r, c.g, c.b, 0.55)


func teleport_to(pos: Vector3) -> void:
	global_position = pos
	velocity = Vector3.ZERO
