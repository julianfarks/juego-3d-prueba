class_name PcInput
extends Node
## Entrada de PC (solo en modo PC, ver Config.pc_mode): ratón para la cámara y el combate.
## - Mientras se juega (sin menús ni pausa) el cursor queda capturado: el ratón gira la cámara.
## - Clic izquierdo = atacar (acción «attack»), clic derecho = Documentos (acción «skill1»).
## - En menús, pausa, tienda, cofres o pantalla final el cursor se libera y vuelve a funcionar con normalidad.
## No toca la entrada táctil ni la de mando; en Android este nodo ni siquiera se crea.

var main: Node
var captured := false
var _mouse_attack := false
var _mouse_skill := false
var assume_focus := false     # (pruebas) sin gestor de ventanas no hay foco real
var motion_events := 0       # (pruebas) movimientos de ratón recibidos mientras estaba capturado


func _ready() -> void:
	name = "PcInput"
	process_mode = Node.PROCESS_MODE_ALWAYS
	# tecla extra: E también interactúa (F sigue igual)
	if InputMap.has_action("interact"):
		var e := InputEventKey.new()
		e.physical_keycode = KEY_E
		InputMap.action_add_event("interact", e)


func wants_capture() -> bool:
	if main == null or not is_instance_valid(main):
		return false
	var st: int = main.state
	if st != main.St.RUN and st != main.St.LOBBY:
		return false
	if main._transitioning or not main._overlays.is_empty() or main._pause_menu != null:
		return false
	if get_tree().paused:
		return false
	return assume_focus or DisplayServer.get_name() == "headless" or DisplayServer.window_is_focused()


func _process(_delta: float) -> void:
	var want := wants_capture()
	if want != captured:
		captured = want
		if DisplayServer.get_name() != "headless":
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE
		if not captured:
			_release_buttons()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if captured:
			motion_events += 1
			GameState.look_delta += (event as InputEventMouseMotion).relative
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.device == InputEvent.DEVICE_ID_EMULATION:
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_set_button(mb.pressed, "attack")
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_set_button(mb.pressed, "skill1")


func _set_button(pressed: bool, action: String) -> void:
	var held := _mouse_attack if action == "attack" else _mouse_skill
	if pressed and captured and not held:
		Input.action_press(action)
		_store(action, true)
	elif not pressed and held:
		Input.action_release(action)
		_store(action, false)


func _store(action: String, v: bool) -> void:
	if action == "attack":
		_mouse_attack = v
	else:
		_mouse_skill = v


func _release_buttons() -> void:
	if _mouse_attack:
		Input.action_release("attack")
		_mouse_attack = false
	if _mouse_skill:
		Input.action_release("skill1")
		_mouse_skill = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_PREDELETE:
		_release_buttons()
		if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and DisplayServer.get_name() != "headless":
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			captured = false
