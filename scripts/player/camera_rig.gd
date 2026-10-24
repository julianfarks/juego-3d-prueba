class_name CameraRig
extends Node3D
## Cámara en tercera persona: órbita con gestos en la mitad derecha de la pantalla,
## seguimiento suavizado (sin vibración) y detección de colisiones para no atravesar paredes.

var cam: Camera3D
var target: Node3D
var yaw := 0.0
var pitch := -0.52
var distance := 9.6
var min_pitch := -1.05
var max_pitch := -0.12
var pivot_height := 1.7
var shoulder := 0.55
var _pivot := Vector3.ZERO
var _cur_dist := 9.6
var _shake := 0.0
var _initialized := false
var look_sens := 0.0052
var _hold := 0.0                  # tiempo que lleva despejada la vista (evita el «bombeo» al rozar esquinas)
static var _probe: SphereShape3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS      # sigue viva con la pausa para ver al instante los cambios de CÁMARA
	cam = Camera3D.new()
	cam.fov = 68.0
	cam.near = 0.15
	cam.far = Config.draw_far()
	add_child(cam)
	cam.current = true
	GameState.cam = self
	apply_settings()
	_cur_dist = distance


## Copia los ajustes de CÁMARA (distancia, altura, inclinación) a la cámara. La sensibilidad se lee en cada fotograma.
func apply_settings(reset_pitch := true) -> void:
	distance = clampf(float(SaveSystem.setting("cam_dist")), float(Config.CAM_DIST["min"]), float(Config.CAM_DIST["max"]))
	pivot_height = clampf(float(SaveSystem.setting("cam_height")), float(Config.CAM_HEIGHT["min"]), float(Config.CAM_HEIGHT["max"]))
	if reset_pitch:
		pitch = -deg_to_rad(clampf(float(SaveSystem.setting("cam_pitch")), float(Config.CAM_PITCH["min"]), float(Config.CAM_PITCH["max"])))


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
	var paused := get_tree().paused
	var sx: float = clampf(float(SaveSystem.setting("cam_sens_x")), 0.1, 3.0)
	var sy: float = clampf(float(SaveSystem.setting("cam_sens_y")), 0.1, 3.0)
	var inv := -1.0 if bool(SaveSystem.setting("cam_invert_y")) else 1.0
	if not paused:
		# entrada de cámara (táctil + teclado + stick del mando)
		var look: Vector2 = GameState.look_delta
		GameState.look_delta = Vector2.ZERO
		var kb := Input.get_vector("look_left", "look_right", "look_up", "look_down")
		look += kb * 900.0 * delta
		if PadInput.inst != null:
			look += PadInput.inst.look_vector() * 550.0 * delta
		yaw -= look.x * look_sens * sx
		pitch = clampf(pitch - look.y * look_sens * 0.85 * sy * inv, min_pitch, max_pitch)
	# pivote suavizado (también en saltos, esquivas y lanzamientos)
	var want_pivot: Vector3 = target.global_position + Vector3(0, pivot_height, 0)
	if not _initialized:
		_pivot = want_pivot
		_initialized = true
	_pivot = _pivot.lerp(want_pivot, 1.0 - exp(-delta * 20.0))
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	var right := Basis(Vector3.UP, yaw) * Vector3.RIGHT
	var origin := _pivot + right * shoulder
	var dir_back: Vector3 = basis * Vector3(0, 0, 1)
	# colisión: se lanza una esfera (no un rayo) desde el pivote hacia atrás, así no se cuela por esquinas ni rendijas
	var hit_dist := distance
	var blocked := false
	if _probe == null:
		_probe = SphereShape3D.new()
		_probe.radius = 0.3
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _probe
	q.transform = Transform3D(Basis(), origin)
	q.motion = dir_back * distance
	q.collision_mask = Config.L_CAMERA
	var res := get_world_3d().direct_space_state.cast_motion(q)
	if res.size() >= 2 and float(res[0]) < 1.0:
		hit_dist = maxf(1.4, distance * float(res[0]))
		blocked = true
	# un obstáculo acerca la cámara al instante (nunca queda dentro de la pared); sin obstáculo, los cambios son suaves:
	# alejarse espera 0,25 s tras despejarse la vista para no «bombear» al rozar esquinas
	if blocked and hit_dist < _cur_dist:
		_cur_dist = hit_dist
		_hold = 0.0
	else:
		_hold += delta
		var rate := 10.0 if paused else (4.0 if (_hold > 0.25 or hit_dist < _cur_dist) else 0.0)
		_cur_dist = lerpf(_cur_dist, hit_dist, 1.0 - exp(-delta * rate))
	var pos := origin + dir_back * _cur_dist
	if Terrain.active:
		# el perímetro de la arena no se «lanza» con rayos (acercaría la cámara de golpe al girar junto al borde):
		# la posición se recorta dentro de los límites, lo que es continuo al girar y la deja deslizar por el muro
		var lim := Terrain.half - 0.7
		pos.x = clampf(pos.x, -lim, lim)
		pos.z = clampf(pos.z, -lim, lim)
		# no se mete bajo el terreno
		pos.y = maxf(pos.y, Terrain.ground_y(pos.x, pos.z) + 0.45)
	# temblor de pantalla
	var off := Vector3.ZERO
	if _shake > 0.001:
		off = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake * 0.25
		_shake = lerpf(_shake, 0.0, 1.0 - exp(-delta * 9.0))
	cam.global_position = pos + off
	cam.look_at(origin - dir_back * 2.0, Vector3.UP)
