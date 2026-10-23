class_name CameraRig
extends Node3D
## Cámara en tercera persona: órbita con gestos en la mitad derecha de la pantalla,
## seguimiento suavizado (sin vibración) y detección de colisiones para no atravesar paredes.

var cam: Camera3D
var target: Node3D
var yaw := 0.0
var pitch := -0.42
var distance := 6.4
var min_pitch := -1.15
var max_pitch := -0.08
var pivot_height := 1.55
var shoulder := 0.55
var _pivot := Vector3.ZERO
var _cur_dist := 6.4
var _shake := 0.0
var _initialized := false
var look_sens := 0.0052


func _ready() -> void:
	cam = Camera3D.new()
	cam.fov = 68.0
	cam.near = 0.15
	cam.far = 220.0
	add_child(cam)
	cam.current = true
	GameState.cam = self


func snap_to_target() -> void:
	if target == null:
		return
	_pivot = target.global_position + Vector3(0, pivot_height, 0)
	_cur_dist = distance
	_initialized = true


func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func forward_flat() -> Vector3:
	return Basis(Vector3.UP, yaw) * Vector3(0, 0, -1)


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var sens: float = float(SaveSystem.setting("camera_sens"))
	# entrada de cámara (táctil + teclado)
	var look: Vector2 = GameState.look_delta
	GameState.look_delta = Vector2.ZERO
	var kb := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	look += kb * 900.0 * delta
	yaw -= look.x * look_sens * sens
	pitch = clampf(pitch - look.y * look_sens * 0.85 * sens, min_pitch, max_pitch)
	# pivote suavizado
	var want_pivot: Vector3 = target.global_position + Vector3(0, pivot_height, 0)
	if not _initialized:
		_pivot = want_pivot
		_initialized = true
	_pivot = _pivot.lerp(want_pivot, 1.0 - exp(-delta * 16.0))
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	var right := Basis(Vector3.UP, yaw) * Vector3.RIGHT
	var origin := _pivot + right * shoulder
	var dir_back: Vector3 = basis * Vector3(0, 0, 1)
	var want_pos := origin + dir_back * distance
	# colisión con paredes/obstáculos
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, want_pos, Config.L_CAMERA)
	var res := space.intersect_ray(q)
	var hit_dist := distance
	if not res.is_empty():
		hit_dist = maxf(0.6, origin.distance_to(res["position"]) - 0.35)
	# acercarse al instante si hay obstáculo; alejarse suavemente
	if hit_dist < _cur_dist:
		_cur_dist = hit_dist
	else:
		_cur_dist = lerpf(_cur_dist, hit_dist, 1.0 - exp(-delta * 4.0))
	var pos := origin + dir_back * _cur_dist
	# temblor de pantalla
	var off := Vector3.ZERO
	if _shake > 0.001:
		off = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake * 0.25
		_shake = lerpf(_shake, 0.0, 1.0 - exp(-delta * 9.0))
	cam.global_position = pos + off
	cam.look_at(origin + Vector3(0, 0.0, 0) - dir_back * 2.0, Vector3.UP)
