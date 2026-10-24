class_name PadInput
extends Node
## Mandos (Xbox, PlayStation y genéricos) y reasignación de controles.
##
## - Detecta conexión/desconexión (Input.joy_connection_changed) y elige el mando activo (el último que se usó).
## - Godot normaliza los botones con su base de datos SDL: A/B/X/Y son posiciones físicas (en PlayStation A = cruz,
##   B = círculo, X = cuadrado, Y = triángulo), L1/R1 = LEFT/RIGHT_SHOULDER y L2/R2 = ejes TRIGGER_LEFT/RIGHT. Lo único
##   que cambia entre marcas es el NOMBRE que se muestra al jugador (ver BTN_XBOX / BTN_PS).
## - Los botones y gatillos se enlazan al InputMap (acciones del juego); los sticks se leen aquí para poder aplicar zonas
##   muertas, sensibilidad e intercambio de sticks. Los enlaces se guardan en SaveSystem.data["pad"].
## - Modo de control: "auto" (mando conectado → sin controles táctiles), "touch" o "pad" (forzados desde ajustes).

signal mode_changed(is_pad: bool)
signal devices_changed
signal bindings_changed

static var inst: PadInput
static var pad_mode := false          # true = se juega con mando (los controles táctiles se ocultan)

const AXIS_TRIGGER_L := 4
const AXIS_TRIGGER_R := 5

## Acciones de juego configurables (en este orden en el menú) y de interfaz.
const GAME_ACTIONS := ["attack", "skill1", "dodge", "jump", "interact", "inventory", "pause"]
const UI_ACTIONS := ["ui_accept", "ui_cancel", "ui_focus_prev", "ui_focus_next"]
const ACTION_LABEL := {
	"attack": "Lanzar el maletín (ATACAR)", "skill1": "Usar DOCS", "dodge": "Esquivar", "jump": "Saltar",
	"interact": "Interactuar (cofres, estaciones)", "inventory": "Abrir el inventario", "pause": "Pausar",
	"ui_accept": "Confirmar", "ui_cancel": "Cancelar / volver",
	"ui_focus_prev": "Menús: anterior (carta/opción)", "ui_focus_next": "Menús: siguiente (carta/opción)",
}
const KEY_ACTIONS := ["move_forward", "move_back", "move_left", "move_right", "attack", "skill1", "dodge", "jump", "interact", "inventory", "pause"]
const KEY_LABEL := {
	"move_forward": "Mover adelante", "move_back": "Mover atrás", "move_left": "Mover izquierda", "move_right": "Mover derecha",
	"attack": "Lanzar el maletín", "skill1": "Usar DOCS", "dodge": "Esquivar", "jump": "Saltar", "interact": "Interactuar",
	"inventory": "Abrir el inventario", "pause": "Pausar",
}
const KEY_DEFAULT := {
	"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D, "attack": KEY_J, "skill1": KEY_Q,
	"dodge": KEY_SHIFT, "jump": KEY_SPACE, "interact": KEY_F, "inventory": KEY_I, "pause": KEY_ESCAPE,
}

const BTN_XBOX := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y", JOY_BUTTON_BACK: "View", JOY_BUTTON_GUIDE: "Xbox",
	JOY_BUTTON_START: "Menu", JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3", JOY_BUTTON_LEFT_SHOULDER: "LB",
	JOY_BUTTON_RIGHT_SHOULDER: "RB", JOY_BUTTON_DPAD_UP: "Cruceta ↑", JOY_BUTTON_DPAD_DOWN: "Cruceta ↓",
	JOY_BUTTON_DPAD_LEFT: "Cruceta ←", JOY_BUTTON_DPAD_RIGHT: "Cruceta →", JOY_BUTTON_MISC1: "Compartir",
}
const BTN_PS := {
	JOY_BUTTON_A: "Cruz", JOY_BUTTON_B: "Círculo", JOY_BUTTON_X: "Cuadrado", JOY_BUTTON_Y: "Triángulo", JOY_BUTTON_BACK: "Share",
	JOY_BUTTON_GUIDE: "PS", JOY_BUTTON_START: "Options", JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_LEFT_SHOULDER: "L1", JOY_BUTTON_RIGHT_SHOULDER: "R1", JOY_BUTTON_DPAD_UP: "Cruceta ↑", JOY_BUTTON_DPAD_DOWN: "Cruceta ↓",
	JOY_BUTTON_DPAD_LEFT: "Cruceta ←", JOY_BUTTON_DPAD_RIGHT: "Cruceta →", JOY_BUTTON_MISC1: "Micrófono", JOY_BUTTON_TOUCHPAD: "Panel táctil",
}

var devices: Array = []               # ids de los mandos conectados
var active := -1                      # mando activo (el último que se usó)
var debug_names: Dictionary = {}      # device -> nombre (pruebas automáticas)
var capturing := false
var _capture_kind := ""
var _capture_cb: Callable
var _capture_t := 0.0
var _axes: Dictionary = {}            # device -> {axis: valor}
var _last_mode := false
var last_pad_input := -100.0          # instante (s) de la última pulsación/movimiento real de mando
var touch_override := false           # en «automático»: se tocó la pantalla sin actividad del mando → vuelven los controles táctiles
const OVERRIDE_IDLE := 8.0


func _init() -> void:
	inst = self


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.joy_connection_changed.connect(_on_joy_connection)
	for d in Input.get_connected_joypads():
		_add_device(int(d))
	apply_all()
	_refresh_mode(true)


# ------------------------------------------------------------------ datos
static func cfg() -> Dictionary:
	return SaveSystem.data["pad"]


static func default_binding(action: String) -> Dictionary:
	match action:
		"attack": return {"t": "a", "i": AXIS_TRIGGER_R}
		"skill1": return {"t": "a", "i": AXIS_TRIGGER_L}
		"jump": return {"t": "b", "i": JOY_BUTTON_A}
		"dodge": return {"t": "b", "i": JOY_BUTTON_B}
		"interact": return {"t": "b", "i": JOY_BUTTON_X}
		"inventory": return {"t": "b", "i": JOY_BUTTON_Y}
		"pause": return {"t": "b", "i": JOY_BUTTON_START}
		"ui_accept": return {"t": "b", "i": JOY_BUTTON_A}
		"ui_cancel": return {"t": "b", "i": JOY_BUTTON_B}
		"ui_focus_prev": return {"t": "b", "i": JOY_BUTTON_LEFT_SHOULDER}
		"ui_focus_next": return {"t": "b", "i": JOY_BUTTON_RIGHT_SHOULDER}
	return {"t": "none"}


static func binding(action: String) -> Dictionary:
	var ov: Dictionary = cfg()["bindings"]
	if ov.has(action):
		return ov[action]
	return default_binding(action)


static func group_of(action: String) -> String:
	return "ui" if action.begins_with("ui_") else "game"


static func same(a: Dictionary, b: Dictionary) -> bool:
	return String(a.get("t", "none")) != "none" and String(a.get("t")) == String(b.get("t")) and int(a.get("i", -1)) == int(b.get("i", -2))


## Acción del mismo grupo que ya usa ese botón (o "" si no hay conflicto).
static func find_conflict(action: String, b: Dictionary) -> String:
	var pool: Array = UI_ACTIONS if group_of(action) == "ui" else GAME_ACTIONS
	for other in pool:
		if other != action and same(binding(other), b):
			return other
	return ""


static func set_binding(action: String, b: Dictionary) -> void:
	cfg()["bindings"][action] = b
	SaveSystem.mark_dirty()
	if inst != null:
		inst.apply_all()
		inst.bindings_changed.emit()


## Intercambia los botones de dos acciones.
static func swap_bindings(a: String, b: String) -> void:
	var ba := binding(a).duplicate()
	var bb := binding(b).duplicate()
	cfg()["bindings"][a] = bb
	cfg()["bindings"][b] = ba
	SaveSystem.mark_dirty()
	if inst != null:
		inst.apply_all()
		inst.bindings_changed.emit()


static func reset_bindings() -> void:
	var c := cfg()
	c["bindings"] = {}
	c["move_stick"] = "left"
	c["look_sens"] = 1.0
	c["dead_move"] = 0.2
	c["dead_look"] = 0.15
	SaveSystem.mark_dirty()
	if inst != null:
		inst.apply_all()
		inst.bindings_changed.emit()


static func reset_keys() -> void:
	SaveSystem.data["keys"] = {}
	SaveSystem.mark_dirty()
	if inst != null:
		inst.apply_all()
		inst.bindings_changed.emit()


# ------------------------------------------------------------------ nombres según el tipo de mando
## Tipo de mando a partir del nombre que reporta Android/SO: "ps", "xbox" o "generic".
static func kind_from_name(joy_name: String, vendor := 0) -> String:
	var n := joy_name.to_lower()
	if vendor == 0x045e or n.contains("xbox") or n.contains("xinput") or n.contains("microsoft"):
		return "xbox"
	if vendor == 0x054c or n.contains("playstation") or n.contains("dualshock") or n.contains("dualsense") or n.contains("sony") \
			or n.begins_with("ps3") or n.begins_with("ps4") or n.begins_with("ps5") or n.contains("ps4 ") or n.contains("ps5 ") \
			or n.contains("wireless controller"):
		return "ps"
	return "generic"


func device_name(d: int) -> String:
	if debug_names.has(d):
		return String(debug_names[d])
	return Input.get_joy_name(d)


func device_kind(d: int = -1) -> String:
	var dev := active if d < 0 else d
	if dev < 0:
		return "generic"
	var vendor := 0
	if not debug_names.has(dev):
		var info := Input.get_joy_info(dev)
		vendor = int(info.get("vendor_id", 0)) if info.has("vendor_id") else 0
	return kind_from_name(device_name(dev), vendor)


## Nombre de un botón físico para el mando activo (Xbox o PlayStation).
func button_name(b: Dictionary) -> String:
	match String(b.get("t", "none")):
		"b":
			var tbl: Dictionary = BTN_PS if device_kind() == "ps" else BTN_XBOX
			return String(tbl.get(int(b["i"]), "Botón %d" % int(b["i"])))
		"a":
			var ps := device_kind() == "ps"
			if int(b["i"]) == AXIS_TRIGGER_L:
				return "L2" if ps else "LT"
			if int(b["i"]) == AXIS_TRIGGER_R:
				return "R2" if ps else "RT"
			return "Eje %d" % int(b["i"])
	return "—"


func action_label(action: String) -> String:
	return button_name(binding(action))


static func label(action: String) -> String:
	return inst.action_label(action) if inst != null else "?"


func key_name(action: String) -> String:
	var k := keycode_for(action)
	return OS.get_keycode_string(k) if k != 0 else "—"


static func keycode_for(action: String) -> int:
	var keys: Dictionary = SaveSystem.data.get("keys", {})
	if keys.has(action):
		return int(keys[action])
	return int(KEY_DEFAULT.get(action, 0))


# ------------------------------------------------------------------ aplicar al InputMap
func apply_all() -> void:
	for a in GAME_ACTIONS:
		if not InputMap.has_action(a):
			InputMap.add_action(a, 0.5)
	for a in GAME_ACTIONS + UI_ACTIONS:
		_apply_pad_action(a)
	for a in KEY_ACTIONS:
		_apply_key_action(a)
	# el joystick táctil aplica su propia zona muerta: la del InputMap no debe esconder los empujes pequeños
	for a in ["move_left", "move_right", "move_forward", "move_back"]:
		InputMap.action_set_deadzone(a, 0.02)


func _apply_pad_action(action: String) -> void:
	# fuera los botones/ejes de mando anteriores (ojo: ui_* trae también cruceta y stick de fábrica; solo se tocan los de acción)
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton:
			InputMap.action_erase_event(action, ev)
		elif ev is InputEventJoypadMotion and (int(ev.axis) == AXIS_TRIGGER_L or int(ev.axis) == AXIS_TRIGGER_R):
			InputMap.action_erase_event(action, ev)
	var b := binding(action)
	match String(b.get("t", "none")):
		"b":
			var jb := InputEventJoypadButton.new()
			jb.button_index = int(b["i"])
			InputMap.action_add_event(action, jb)
		"a":
			var jm := InputEventJoypadMotion.new()
			jm.axis = int(b["i"])
			jm.axis_value = 1.0
			InputMap.action_add_event(action, jm)
	if action in GAME_ACTIONS:
		InputMap.action_set_deadzone(action, 0.5)


func _apply_key_action(action: String) -> void:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			InputMap.action_erase_event(action, ev)
	var k := keycode_for(action)
	if k != 0:
		var ek := InputEventKey.new()
		ek.physical_keycode = k as Key
		InputMap.action_add_event(action, ek)
	if action == "attack" and not SaveSystem.data.get("keys", {}).has("attack"):
		var e2 := InputEventKey.new()
		e2.physical_keycode = KEY_CTRL
		InputMap.action_add_event(action, e2)


static func set_key(action: String, keycode: int) -> void:
	# una tecla no puede servir a dos acciones: la otra queda sin asignar
	var keys: Dictionary = SaveSystem.data["keys"]
	for other in KEY_ACTIONS:
		if other != action and keycode_for(other) == keycode:
			keys[other] = 0
	keys[action] = keycode
	SaveSystem.mark_dirty()
	if inst != null:
		inst.apply_all()
		inst.bindings_changed.emit()


# ------------------------------------------------------------------ dispositivos
func _on_joy_connection(device: int, connected: bool) -> void:
	if connected:
		_add_device(device)
	else:
		_remove_device(device)


func _add_device(d: int) -> void:
	if not devices.has(d):
		devices.append(d)
	if active < 0:
		active = d
	devices_changed.emit()
	_refresh_mode()


func _remove_device(d: int) -> void:
	devices.erase(d)
	_axes.erase(d)
	if active == d:
		active = int(devices[devices.size() - 1]) if not devices.is_empty() else -1
	devices_changed.emit()
	_refresh_mode()


func connected() -> bool:
	return not devices.is_empty()


## Modo configurado: "auto", "touch" o "pad".
func mode_setting() -> String:
	return String(cfg().get("mode", "auto"))


func is_pad_mode() -> bool:
	match mode_setting():
		"pad": return true
		"touch": return false
	return connected() and not touch_override


func set_mode_setting(m: String) -> void:
	cfg()["mode"] = m
	SaveSystem.mark_dirty()
	_refresh_mode()


func _refresh_mode(force := false) -> void:
	var want := is_pad_mode()
	if want != pad_mode or force:
		pad_mode = want
		mode_changed.emit(pad_mode)
	_last_mode = pad_mode


# ------------------------------------------------------------------ entrada
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		# seguro contra «mandos fantasma» (teclados, mandos TV…): si hay un mando "conectado" pero nunca se usa y el jugador
		# toca la pantalla, vuelven los controles táctiles hasta que el mando dé señales de vida
		if mode_setting() == "auto" and connected() and not touch_override and _now() - last_pad_input > OVERRIDE_IDLE:
			touch_override = true
			_refresh_mode()
	if event is InputEventJoypadMotion:
		var jm := event as InputEventJoypadMotion
		var d := jm.device
		if not _axes.has(d):
			_axes[d] = {}
		_axes[d][int(jm.axis)] = jm.axis_value
		if absf(jm.axis_value) > 0.5:
			_note_activity(d)
		if capturing and _capture_kind == "pad" and _capture_t <= 0.0 and (jm.axis == AXIS_TRIGGER_L or jm.axis == AXIS_TRIGGER_R) and jm.axis_value > 0.6:
			_finish_capture({"t": "a", "i": int(jm.axis)})
			get_viewport().set_input_as_handled()
		elif capturing:
			get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton:
		var jb := event as InputEventJoypadButton
		if jb.pressed:
			_note_activity(jb.device)
		if capturing:
			if _capture_kind == "pad" and _capture_t <= 0.0 and jb.pressed:
				_finish_capture({"t": "b", "i": int(jb.button_index)})
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and capturing and _capture_kind == "key":
		var ek := event as InputEventKey
		if ek.pressed and not ek.echo and _capture_t <= 0.0:
			var kc := int(ek.physical_keycode)
			if kc == KEY_ESCAPE:
				cancel_capture()
			else:
				_finish_capture({"t": "key", "i": kc})
		get_viewport().set_input_as_handled()
	elif capturing and (event is InputEventKey or event is InputEventJoypadButton):
		get_viewport().set_input_as_handled()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _note_activity(d: int) -> void:
	last_pad_input = _now()
	if touch_override:
		touch_override = false      # el mando se usa de verdad: fuera los controles táctiles otra vez
		_refresh_mode()
	if not devices.has(d):
		# un mando que aún no avisó de su conexión (algunos Android lo hacen)
		_add_device(d)
	if active != d:
		active = d
		devices_changed.emit()


func _process(delta: float) -> void:
	if _capture_t > 0.0:
		_capture_t -= delta


## Espera la próxima pulsación para reasignar. kind: "pad" (botón/gatillo) o "key" (tecla). Esc cancela una tecla.
func begin_capture(kind: String, cb: Callable) -> void:
	capturing = true
	_capture_kind = kind
	_capture_cb = cb
	_capture_t = 0.35       # ignora lo que aún esté pulsado al abrir la captura


func cancel_capture() -> void:
	if capturing:
		capturing = false
		var cb := _capture_cb
		_capture_cb = Callable()
		if cb.is_valid():
			cb.call({})


func _finish_capture(b: Dictionary) -> void:
	capturing = false
	var cb := _capture_cb
	_capture_cb = Callable()
	if cb.is_valid():
		cb.call(b)


# ------------------------------------------------------------------ sticks
func _axis(d: int, a: int) -> float:
	if d < 0 or not _axes.has(d):
		return 0.0
	return float(_axes[d].get(a, 0.0))


func _stick(which: String) -> Vector2:
	var ax := 0 if which == "left" else 2
	return Vector2(_axis(active, ax), _axis(active, ax + 1))


static func _dead(v: Vector2, dz: float) -> Vector2:
	var l := v.length()
	if l <= dz:
		return Vector2.ZERO
	return v / l * clampf((l - dz) / (1.0 - dz), 0.0, 1.0)


func move_stick_name() -> String:
	return String(cfg().get("move_stick", "left"))


func look_stick_name() -> String:
	return "right" if move_stick_name() == "left" else "left"


## Vector de movimiento del mando (longitud ≤ 1, zona muerta radial). Vacío si no hay mando o está en modo táctil.
func move_vector() -> Vector2:
	if active < 0 or mode_setting() == "touch":
		return Vector2.ZERO
	return _dead(_stick(move_stick_name()), clampf(float(cfg().get("dead_move", 0.2)), 0.05, 0.6))


## Giro de cámara en "píxeles equivalentes por segundo" (ver CameraRig).
func look_vector() -> Vector2:
	if active < 0 or mode_setting() == "touch":
		return Vector2.ZERO
	var v := _dead(_stick(look_stick_name()), clampf(float(cfg().get("dead_look", 0.15)), 0.05, 0.6))
	# curva suave: precisión con poco recorrido, giro rápido al máximo
	return v * v.length() * float(cfg().get("look_sens", 1.0))
