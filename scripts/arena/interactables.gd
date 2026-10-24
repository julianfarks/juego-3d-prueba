class_name Interactable
extends Node3D
## Objeto con el que el jugador puede interactuar (cofre, portal, tienda, estaciones de la sala).
## El jugador busca el más cercano del grupo "interactable"; el HUD y el botón táctil lo muestran.
## Opcionalmente lleva un indicador flotante (icono de mano + texto) que mira siempre a la cámara.

var prompt := "Interactuar"
var action_text := "USAR"            # texto del botón táctil mientras este objeto es el objetivo
var radius := 2.8
var anchor := Vector3.ZERO           # punto de uso (local): la zona de atención puede estar delante del modelo, no en su centro
var enabled := true
var callback: Callable = Callable()
var kind := "generic"

var ind_range := 16.0                # distancia a la que se ve el indicador
var ind_active := true               # false: el indicador permanece oculto (p. ej. cofre ya abierto)
var ind_scale := 1.0                 # tamaño del cartel (el del portal es más pequeño: el portal ya es enorme)
var _ind: Node3D = null
var _ind_label: Label3D = null
var _ind_icon: Node3D = null          # guante 3D que señala hacia abajo (ModelFactory.pointer_hand)
var _ind_t := 0.0
var _ind_base_y := 2.6


func _ready() -> void:
	add_to_group("interactable")
	set_process(_ind != null)


func use_point() -> Vector3:
	return to_global(anchor)


func activate(player: Node) -> void:
	if enabled and callback.is_valid():
		callback.call(self)


## Crea el indicador flotante. 'text': ABRIR, ENTRAR… ; 'icon': si lleva la mano de "toca aquí".
func setup_indicator(text: String, height: float, color := Color(1.0, 0.9, 0.35), icon := true) -> void:
	_ind_base_y = height
	_ind = Node3D.new()
	_ind.name = "Indicator"
	_ind.position = Vector3(0, height, 0)
	add_child(_ind)
	if icon:
		_ind_icon = ModelFactory.pointer_hand(color)
		_ind_icon.position = Vector3(0, 1.2, 0)
		_ind_icon.scale = Vector3.ONE * 0.95
		_ind.add_child(_ind_icon)
	_ind_label = Label3D.new()
	_ind_label.text = text
	_ind_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_ind_label.no_depth_test = true
	_ind_label.shaded = false
	_ind_label.fixed_size = false
	_ind_label.pixel_size = 0.011
	_ind_label.font_size = 64
	_ind_label.outline_size = 22
	_ind_label.modulate = color
	_ind_label.outline_modulate = Color(0.05, 0.04, 0.1, 0.95)
	_ind_label.render_priority = 11
	_ind_label.position = Vector3(0, 0.2 if icon else 0.0, 0)
	_ind_label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ind.add_child(_ind_label)
	set_process(true)


func set_indicator(text: String, color: Color, active := true) -> void:
	ind_active = active
	if _ind_label != null:
		_ind_label.text = text
		_ind_label.modulate = color
	if _ind_icon != null:
		var old := _ind_icon
		_ind_icon = ModelFactory.pointer_hand(color)
		_ind_icon.position = old.position
		_ind_icon.scale = old.scale
		_ind.add_child(_ind_icon)
		_ind.remove_child(old)
		old.queue_free()
	if _ind != null:
		_ind.visible = active and _ind.visible


func indicator_visible() -> bool:
	return _ind != null and _ind.visible


func _process(delta: float) -> void:
	if _ind == null:
		return
	var pl = GameState.player
	var show_it: bool = ind_active and pl != null and pl.visible and pl.alive and is_inside_tree()
	var d := 999.0
	if show_it:
		d = use_point().distance_to(pl.global_position)
		show_it = d <= ind_range
	_ind.visible = show_it
	if not show_it:
		return
	_ind_t += delta
	# rebote suave; cuando el jugador ya puede usarlo el cartel late y crece
	var near := enabled and d <= radius
	_ind.position.y = _ind_base_y + sin(_ind_t * 3.2) * (0.16 if near else 0.1)
	var s := 1.0 + (0.14 * sin(_ind_t * 7.0) + 0.2 if near else 0.0)
	# escala con la distancia para que se lea desde lejos
	s *= clampf(0.75 + d * 0.05, 0.85, 1.5) * ind_scale
	_ind.scale = Vector3(s, s, s)
	# el guante mira siempre a la cámara (solo giro en Y: nunca se tumba) y "pica" hacia abajo con un vaivén suave
	if _ind_icon != null:
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			var to_cam := cam.global_position - _ind.global_position
			_ind_icon.global_rotation = Vector3(0, atan2(to_cam.x, to_cam.z), 0)
		_ind_icon.position.y = 1.2 + sin(_ind_t * 4.5) * 0.07
