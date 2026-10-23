class_name PracticeDummy
extends Node3D
## Muñeco de práctica de la Sala Central. Implementa lo mismo que un enemigo para el sistema de
## combate real (Combat, Skills, Projectiles): recibe daño, críticos, empuje y estados, pero no ataca,
## no muere y no da recompensas. Muestra el daño de cada golpe y el DPS de los últimos segundos.

var kind := "dummy"
var alive := true
var is_elite := false
var is_boss := false
var body_radius := 0.7
var max_hp := 1000000.0
var hp := 1000000.0
var marked_t := 0.0
var slow_t := 0.0
var burn_t := 0.0
var freeze_t := 0.0
var vscale := 1.0
var home := Vector3.ZERO

var _pivot: Node3D
var _label: Label3D
var _hits: Array = []          # [{t, dmg}] de los últimos 5 s
var _sway := Vector3.ZERO
var _sway_v := Vector3.ZERO
var _last_dmg := 0.0
var _flash := 0.0
var _mat: ShaderMaterial


func _ready() -> void:
	home = position
	_pivot = Node3D.new()
	add_child(_pivot)
	var b := MeshBuilder.new()
	var wood := Color(0.55, 0.38, 0.2)
	var straw := Color(0.9, 0.72, 0.35)
	var red := Color(0.85, 0.2, 0.18)
	b.cylinder(0.75, 0.85, 0.18, 10, MeshBuilder.xf(Vector3(0, 0.09, 0)), wood.darkened(0.3))   # base
	b.cylinder(0.12, 0.14, 1.5, 6, MeshBuilder.xf(Vector3(0, 0.9, 0)), wood)                      # poste
	b.box(Vector3(1.3, 0.16, 0.16), MeshBuilder.xf(Vector3(0, 1.45, 0)), wood)                     # brazos
	b.cylinder(0.42, 0.5, 0.95, 8, MeshBuilder.xf(Vector3(0, 1.25, 0)), straw)                     # torso de paja
	b.sphere(0.3, 8, 6, MeshBuilder.xf(Vector3(0, 2.0, 0)), straw)                                 # cabeza
	b.cylinder(0.43, 0.43, 0.1, 10, MeshBuilder.xf(Vector3(0, 1.42, 0)), red)                      # franja roja
	b.cylinder(0.25, 0.25, 0.08, 10, MeshBuilder.xf(Vector3(0, 1.0, -0.38), Vector3(90, 0, 0)), red)  # diana
	b.cylinder(0.12, 0.12, 0.09, 10, MeshBuilder.xf(Vector3(0, 1.0, -0.39), Vector3(90, 0, 0)), Color(1, 1, 1))
	_mat = Mats.char_material()
	Mats.mesh_instance(b.build(), _mat, _pivot)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.shaded = false
	_label.pixel_size = 0.009
	_label.font_size = 48
	_label.outline_size = 14
	_label.modulate = Color(1.0, 0.9, 0.5)
	_label.position = Vector3(0, 3.1, 0)
	_label.text = "MUÑECO"
	add_child(_label)


func hp_frac() -> float:
	return 1.0


## Mismo contrato que Enemy.take_damage: devuelve true si "mata" (nunca).
func take_damage(dmg: float, info: Dictionary = {}) -> bool:
	var src: String = info.get("src", "")
	_last_dmg = dmg
	_flash = 0.25
	if src != "burn":
		_hits.append({"t": Time.get_ticks_msec() / 1000.0, "dmg": dmg})
	# mismo punto único de número + sonido que los enemigos (el muñeco nunca muere)
	Feedback.on_damage(self, dmg, info, max_hp, max_hp, false)
	var kb: Vector3 = info.get("knock", Vector3.ZERO)
	if kb.length() > 0.01:
		_sway_v += Vector3(kb.z, 0, -kb.x) * 0.06
	_sway_v += Vector3(randf_range(-0.4, 0.4), 0, randf_range(-0.4, 0.4))
	hp = max_hp          # nunca baja: es un muñeco de práctica
	return false


func apply_burn(_dps: float, dur: float) -> void:
	burn_t = dur


func apply_slow(_amt: float, dur: float) -> void:
	slow_t = dur


func apply_freeze(dur: float) -> void:
	freeze_t = dur


func apply_mark(dur: float) -> void:
	marked_t = dur


func dps() -> float:
	var now := Time.get_ticks_msec() / 1000.0
	var total := 0.0
	var first := now
	var i := _hits.size() - 1
	while i >= 0:
		if now - float(_hits[i]["t"]) > 5.0:
			_hits.remove_at(i)
		else:
			total += float(_hits[i]["dmg"])
			first = minf(first, float(_hits[i]["t"]))
		i -= 1
	if _hits.is_empty():
		return 0.0
	return total / maxf(1.0, now - first)


func _process(delta: float) -> void:
	# balanceo amortiguado al recibir golpes
	_sway_v -= _sway * 40.0 * delta
	_sway_v *= maxf(0.0, 1.0 - 5.0 * delta)
	_sway += _sway_v * delta
	_sway = _sway.limit_length(0.6)
	_pivot.rotation = _sway
	if marked_t > 0.0:
		marked_t = maxf(0.0, marked_t - delta)
	if slow_t > 0.0:
		slow_t = maxf(0.0, slow_t - delta)
	if burn_t > 0.0:
		burn_t = maxf(0.0, burn_t - delta)
	if freeze_t > 0.0:
		freeze_t = maxf(0.0, freeze_t - delta)
	_flash = maxf(0.0, _flash - delta)
	_mat.set_shader_parameter("flash", _flash * 2.0)
	var d := dps()
	if d > 0.5:
		_label.text = "DPS %d\nÚltimo golpe: %d" % [int(round(d)), int(round(_last_dmg))]
	else:
		_label.text = "MUÑECO"
