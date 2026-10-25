class_name TouchScroll
extends Node
## Desplazamiento táctil reutilizable para un ScrollContainer: se arrastra sobre CUALQUIER parte del contenido (cartas y
## botones incluidos), con zona muerta, inercia y sin "disparar" lo que había bajo el dedo. Es la misma lógica que usan
## la tienda (shop_ui) y la Mesa del Juez (difficulty_ui), empaquetada para el panel de cofres.
##
## Uso: var ts := TouchScroll.new(); add_child(ts); ts.setup(scroll, contenedor_con_botones)
## - 'drag_moved' es true mientras el gesto actual ya es un desplazamiento (no una pulsación).
## - Al empezar a desplazar se anula la pulsación a medias de los Button del contenedor (alternar «disabled»).
## - El «soltar» de un gesto que fue desplazamiento se consume: ningún control lo recibe, así que no elige nada.

const DRAG_DEADZONE := 14.0

var sc: ScrollContainer
var cancel_root: Node
var enabled := true
var drag_active := false
var drag_moved := false
var _start := Vector2.ZERO
var _last := Vector2.ZERO
var _vel := 0.0
var _inertia := 0.0
var _swallow_until := 0          # ms: tras un desplazamiento se ignoran los «soltar» duplicados (táctil + eco de ratón)


func setup(scroll: ScrollContainer, root: Node = null) -> void:
	sc = scroll
	cancel_root = root if root != null else scroll
	process_mode = Node.PROCESS_MODE_ALWAYS


func _in_area(pos: Vector2) -> bool:
	return enabled and sc != null and is_instance_valid(sc) and sc.is_visible_in_tree() and sc.get_global_rect().has_point(pos)


func _input(event: InputEvent) -> void:
	if sc == null or not is_instance_valid(sc) or not sc.is_visible_in_tree():
		return
	if Time.get_ticks_msec() < _swallow_until:
		if (event is InputEventScreenTouch and not event.pressed) or (event is InputEventMouseButton and not event.pressed):
			get_viewport().set_input_as_handled()
			return
	var pos := Vector2.ZERO
	var kind := ""
	if event is InputEventScreenTouch:
		pos = event.position
		kind = "down" if event.pressed else "up"
	elif event is InputEventScreenDrag:
		pos = event.position
		kind = "move"
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			if drag_moved:
				get_viewport().set_input_as_handled()      # eco ratón de un gesto táctil que ya es desplazamiento
			return
		pos = event.position
		kind = "down" if event.pressed else "up"
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			if drag_moved:
				get_viewport().set_input_as_handled()
			return
		pos = event.position
		kind = "move"
	else:
		return
	match kind:
		"down":
			if _in_area(pos):
				drag_active = true
				drag_moved = false
				_start = pos
				_last = pos
				_vel = 0.0
				_inertia = 0.0
		"move":
			if not drag_active:
				return
			if not drag_moved:
				if absf(pos.y - _start.y) < DRAG_DEADZONE:
					if event is InputEventScreenDrag:
						get_viewport().set_input_as_handled()      # el ScrollContainer no debe moverse por su cuenta
					return
				drag_moved = true
				_cancel_press_at(_start)
			sc.scroll_vertical -= int(round(pos.y - _last.y))
			_vel = lerpf(_vel, pos.y - _last.y, 0.5)
			_last = pos
			get_viewport().set_input_as_handled()
		"up":
			if drag_active and drag_moved:
				get_viewport().set_input_as_handled()
				_inertia = _vel * 60.0
				_swallow_until = Time.get_ticks_msec() + 150
			_end()


func _cancel_press_at(pos: Vector2) -> void:
	if cancel_root == null:
		return
	for b in cancel_root.find_children("*", "Button", true, false):
		var bt := b as Button
		if bt.get_global_rect().has_point(pos):
			var was := bt.disabled
			bt.disabled = true
			bt.disabled = was


func _end() -> void:
	drag_active = false
	drag_moved = false


func _process(delta: float) -> void:
	if absf(_inertia) > 20.0 and not drag_active and sc != null and is_instance_valid(sc):
		var before := sc.scroll_vertical
		sc.scroll_vertical = before - int(round(_inertia * delta))
		_inertia *= exp(-delta * 4.5)
		if sc.scroll_vertical == before:
			_inertia = 0.0
	else:
		_inertia = 0.0
