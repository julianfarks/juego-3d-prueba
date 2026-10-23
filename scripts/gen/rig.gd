class_name Rig
extends Node3D
## Esqueleto humanoide articulado (jerarquía de Node3D) + animaciones procedurales.
## Las "animaciones" se calculan por código (ciclos de caminar/correr, ataques, golpe,
## muerte...) y se mezclan con suavizado: hacen el papel de rig + AnimationPlayer sin
## depender de importar archivos externos. Los personajes comparten esta misma rig.

const JOINTS := ["hips", "torso", "head", "arm_l", "fore_l", "arm_r", "fore_r", "leg_l", "shin_l", "leg_r", "shin_r"]

var j: Dictionary = {}              # nombre -> Node3D
var visual: Node3D                  # contenedor escalable (squash/stretch)
var material: ShaderMaterial        # material único de este personaje
var props: Dictionary = {}          # nodos extra (maletín, arma...) por nombre

var hip_height := 0.9
var phase := 0.0
var speed_norm := 0.0               # 0 = quieto, 1 = corriendo
var airborne := false
var vy := 0.0
var sliding := false
var charging := false
var action := ""
var _action_t := 0.0
var _action_dur := 0.0
var dead := false
var stunned := false
var hit_squash := 0.0
var heavy := false                  # animaciones más pesadas/lentas (jefes, tanques)
var _time := 0.0
var _tgt: Dictionary = {}
var _hips_y_off := 0.0
var _root_rot := Vector3.ZERO
var _root_y := 0.0
var _flash := 0.0
var _flash_color_boost := 0.0


func _ready() -> void:
	set_process(true)


## Reproduce una acción puntual (se interrumpe a sí misma al terminar).
func play(action_name: String, duration: float) -> void:
	if dead:
		return
	action = action_name
	_action_t = 0.0
	_action_dur = maxf(duration, 0.05)


func action_progress() -> float:
	return 0.0 if action == "" else clampf(_action_t / _action_dur, 0.0, 1.0)


func die(duration := 0.9) -> void:
	dead = true
	action = "death"
	_action_t = 0.0
	_action_dur = duration


func revive() -> void:
	dead = false
	action = ""
	_root_rot = Vector3.ZERO
	_root_y = 0.0
	rotation = Vector3.ZERO
	position.y = 0.0
	if material != null:
		material.set_shader_parameter("flash", 0.0)


func hit_flash(strength := 1.0) -> void:
	_flash = strength
	hit_squash = 1.0


func set_status_visual(frost: float, burn: float, tint := Color(1, 1, 1)) -> void:
	if material == null:
		return
	material.set_shader_parameter("frost", frost)
	material.set_shader_parameter("burn", burn)
	material.set_shader_parameter("tint", tint)


func _process(delta: float) -> void:
	_time += delta
	if action != "":
		_action_t += delta
		if _action_t >= _action_dur and action != "death":
			action = ""
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 9.0)
		if material != null:
			material.set_shader_parameter("flash", clampf(_flash, 0.0, 1.0) * 0.8)
	hit_squash = maxf(0.0, hit_squash - delta * 5.0)
	var stride := 8.5 if not heavy else 6.0
	phase += delta * stride * (0.35 + speed_norm * 0.9) * (1.0 if speed_norm > 0.02 else 0.0)
	_compute()
	_apply(delta)


func _s(joint: String, x := 0.0, y := 0.0, z := 0.0) -> void:
	_tgt[joint] = Vector3(x, y, z)


func _compute() -> void:
	_tgt.clear()
	_hips_y_off = 0.0
	_root_rot = Vector3.ZERO
	_root_y = 0.0
	var w := speed_norm
	var s := sin(phase)
	var c := cos(phase)
	var breathe := sin(_time * (2.0 if not heavy else 1.2)) * 0.025
	# --- locomoción base ---------------------------------------------------
	if sliding:
		_hips_y_off = -hip_height * 0.55
		_s("torso", 0.85, 0.0, 0.0)
		_s("head", -0.5, 0.0, 0.0)
		_s("leg_l", 1.35, 0.0, 0.0)
		_s("shin_l", -0.15, 0.0, 0.0)
		_s("leg_r", 1.0, 0.0, 0.0)
		_s("shin_r", -0.9, 0.0, 0.0)
		_s("arm_l", -0.7, 0.0, -0.5)
		_s("arm_r", -0.9, 0.0, 0.5)
		_s("fore_l", 0.3)
		_s("fore_r", 0.3)
	elif airborne:
		var rising := vy > 0.0
		_s("torso", -0.12 if rising else 0.05)
		_s("head", 0.0)
		_s("arm_l", 2.3 if rising else 0.5, 0.0, -0.5)
		_s("arm_r", 2.0 if rising else 0.5, 0.0, 0.5)
		_s("fore_l", 0.3)
		_s("fore_r", 0.3)
		_s("leg_l", 0.7 if rising else 0.25)
		_s("shin_l", -1.2 if rising else -0.3)
		_s("leg_r", -0.2)
		_s("shin_r", -0.6)
	else:
		var amp := 0.95 if not heavy else 0.65
		_s("leg_l", s * amp * w)
		_s("leg_r", -s * amp * w)
		_s("shin_l", -maxf(0.0, c) * 1.1 * w)
		_s("shin_r", -maxf(0.0, -c) * 1.1 * w)
		_s("arm_l", -s * 0.85 * w + breathe, 0.0, -0.06 - 0.08 * (1.0 - w))
		_s("arm_r", s * 0.6 * w - breathe, 0.0, 0.06 + 0.08 * (1.0 - w))
		_s("fore_l", 0.25 + 0.9 * w * maxf(0.0, s))
		_s("fore_r", 0.25 + 0.7 * w * maxf(0.0, -s))
		_s("torso", -0.14 * w + breathe, s * 0.14 * w, 0.0)
		_s("head", 0.1 * w - breathe, -s * 0.08 * w, 0.0)
		_hips_y_off = absf(s) * 0.07 * w - 0.015 * (1.0 - w) * (1.0 + sin(_time * 2.0))
	if charging:
		_s("torso", -0.55, 0.0, 0.0)
		_s("arm_l", -1.4, 0.0, -0.2)
		_s("arm_r", -1.4, 0.0, 0.2)
		_hips_y_off -= 0.06
	# --- acciones ----------------------------------------------------------
	if action == "":
		return
	var p := clampf(_action_t / _action_dur, 0.0, 1.0)
	match action:
		"slam":
			if p < 0.55:
				var k := ease(p / 0.55, 0.45)
				_s("arm_r", lerpf(0.3, 2.9, k), 0.0, 0.15)
				_s("fore_r", lerpf(0.3, 0.9, k))
				_s("arm_l", lerpf(0.0, -0.6, k), 0.0, -0.4)
				_s("torso", lerpf(0.0, 0.3, k), lerpf(0.0, 0.35, k))
				_s("head", lerpf(0.0, -0.15, k))
				_s("leg_l", 0.45)
				_s("leg_r", -0.35)
				_hips_y_off -= 0.04 * k
			else:
				var k2 := clampf((p - 0.55) / 0.3, 0.0, 1.0)
				_s("arm_r", lerpf(2.9, 0.1, ease(k2, 0.3)), 0.0, 0.1)
				_s("fore_r", lerpf(0.9, 0.1, k2))
				_s("arm_l", -0.6, 0.0, -0.4)
				_s("torso", lerpf(0.3, -0.5, ease(k2, 0.3)), lerpf(0.35, -0.2, k2))
				_s("head", 0.2)
				_s("leg_l", 0.85)
				_s("shin_l", -0.2)
				_s("leg_r", -0.5)
				_s("shin_r", -0.4)
				_hips_y_off -= 0.14 * k2
		"swing":
			var k3 := ease(p, 0.6)
			_s("torso", -0.1, lerpf(-0.9, 1.0, k3))
			_s("arm_r", 1.4, 0.0, lerpf(0.9, -0.2, k3))
			_s("fore_r", 0.2)
			_s("arm_l", -0.5, 0.0, -0.5)
			_s("leg_l", 0.5)
			_s("leg_r", -0.4)
		"cast":
			var k4 := minf(p * 3.0, 1.0)
			_s("arm_l", lerpf(0.0, 1.55, k4), 0.0, -0.15)
			_s("arm_r", lerpf(0.0, 1.55, k4), 0.0, 0.15)
			_s("fore_l", 0.1)
			_s("fore_r", 0.1)
			_s("torso", -0.12 * k4 - 0.1 * (1.0 - p))
			_s("head", 0.1)
			_s("leg_l", 0.3)
			_s("leg_r", -0.3)
		"seal":
			var k5 := minf(p * 2.0, 1.0)
			_hips_y_off = -0.22 * k5 * (1.0 - maxf(0.0, (p - 0.7) / 0.3))
			_s("torso", -0.6 * k5)
			_s("head", 0.5 * k5)
			_s("arm_l", 0.9 + 0.6 * ease(maxf(0.0, p - 0.5) * 2.0, 0.4), 0.0, -0.3)
			_s("arm_r", 0.9 + 0.6 * ease(maxf(0.0, p - 0.5) * 2.0, 0.4), 0.0, 0.3)
			_s("leg_l", 0.9 * k5)
			_s("shin_l", -1.2 * k5)
			_s("leg_r", -0.5 * k5)
			_s("shin_r", -0.2 * k5)
		"barrier":
			var k6 := minf(p * 3.0, 1.0)
			_s("arm_l", 0.4, 0.0, -1.35 * k6)
			_s("arm_r", 0.4, 0.0, 1.35 * k6)
			_s("fore_l", 0.2)
			_s("fore_r", 0.2)
			_s("torso", 0.18 * k6)
			_s("head", -0.25 * k6)
			_s("leg_l", 0.0, 0.0, -0.15 * k6)
			_s("leg_r", 0.0, 0.0, 0.15 * k6)
			_hips_y_off = -0.05 * k6
		"hit":
			var k7 := 1.0 - p
			_s("torso", 0.55 * k7, 0.0, 0.1 * k7)
			_s("head", 0.5 * k7)
			_s("arm_l", 0.3 * k7, 0.0, -0.9 * k7)
			_s("arm_r", 0.3 * k7, 0.0, 0.9 * k7)
			_hips_y_off -= 0.06 * k7
		"windup":
			var k8 := ease(p, 0.5)
			_s("arm_r", lerpf(0.3, 2.7, k8), 0.0, 0.2)
			_s("arm_l", lerpf(0.0, 2.0, k8), 0.0, -0.2)
			_s("torso", 0.25 * k8)
			_s("head", -0.1 * k8)
		"shoot":
			_s("arm_r", 1.55 + 0.35 * (1.0 - p))
			_s("fore_r", 0.05)
			_s("arm_l", 0.5, 0.0, -0.4)
			_s("torso", -0.1 + 0.15 * (1.0 - p), -0.15)
		"summon":
			var k9 := ease(minf(p * 1.6, 1.0), 0.5)
			_s("arm_l", lerpf(0.0, 2.9, k9), 0.0, -0.35)
			_s("arm_r", lerpf(0.0, 2.9, k9), 0.0, 0.35)
			_s("torso", 0.3 * k9)
			_s("head", 0.55 * k9)
			_hips_y_off += 0.08 * k9
		"roar":
			var pulse := sin(p * PI)
			_s("head", 0.6 * pulse)
			_s("torso", 0.4 * pulse)
			_s("arm_l", 0.2, 0.0, -1.1 * pulse)
			_s("arm_r", 0.2, 0.0, 1.1 * pulse)
			_s("leg_l", 0.0, 0.0, -0.2 * pulse)
			_s("leg_r", 0.0, 0.0, 0.2 * pulse)
		"stomp":
			if p < 0.5:
				_s("leg_l", lerpf(0.0, 1.3, p * 2.0))
				_s("shin_l", lerpf(0.0, -1.0, p * 2.0))
				_s("arm_l", 1.0, 0.0, -0.5)
				_s("arm_r", 1.0, 0.0, 0.5)
				_s("torso", 0.2)
			else:
				_s("leg_l", lerpf(1.3, 0.0, (p - 0.5) * 4.0))
				_s("torso", -0.35)
				_hips_y_off -= 0.12 * (1.0 - p)
		"dodge":
			var k10 := sin(p * PI)
			_s("torso", -0.7 * k10)
			_s("arm_l", -1.2 * k10, 0.0, -0.3)
			_s("arm_r", -1.2 * k10, 0.0, 0.3)
			_s("leg_l", 0.9 * k10)
			_s("leg_r", -0.9 * k10)
			_hips_y_off -= 0.18 * k10
		"stagger":
			_s("head", 0.5 + sin(_time * 14.0) * 0.2)
			_s("torso", 0.3, sin(_time * 12.0) * 0.2)
			_s("arm_l", 0.4, 0.0, -0.7)
			_s("arm_r", 0.4, 0.0, 0.7)
		"death":
			var kd := ease(p, 0.35)
			_root_rot = Vector3(lerpf(0.0, 1.5, kd), 0.0, 0.0)
			_root_y = lerpf(0.0, 0.18, kd)
			_s("arm_l", 0.3, 0.0, -1.0 * kd)
			_s("arm_r", 0.3, 0.0, 1.0 * kd)
			_s("leg_l", 0.2, 0.0, -0.25 * kd)
			_s("leg_r", 0.1, 0.0, 0.25 * kd)
			_s("head", 0.4 * kd)
			_s("torso", 0.0)


func _apply(delta: float) -> void:
	var k := 1.0 - exp(-delta * (22.0 if not heavy else 14.0))
	for name in JOINTS:
		var node: Node3D = j.get(name)
		if node == null:
			continue
		var tgt: Vector3 = _tgt.get(name, Vector3.ZERO)
		node.rotation = node.rotation.lerp(tgt, k)
	var hips: Node3D = j.get("hips")
	if hips != null:
		hips.position.y = lerpf(hips.position.y, hip_height + _hips_y_off, 1.0 - exp(-delta * 18.0))
	if visual != null:
		var sq := hit_squash
		visual.scale = Vector3(1.0 + 0.1 * sq, 1.0 - 0.1 * sq, 1.0 + 0.1 * sq)
	if dead:
		rotation = rotation.lerp(_root_rot, 1.0 - exp(-delta * 10.0))
		position.y = lerpf(position.y, _root_y, 1.0 - exp(-delta * 10.0))
