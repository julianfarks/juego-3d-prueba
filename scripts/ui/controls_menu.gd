class_name ControlsMenu
extends Control
## Ajustes → CONTROLES: pestañas TÁCTIL, MANDO y TECLADO. En MANDO cada acción se reasigna pulsando el botón nuevo
## (modo de espera con cancelación), con aviso y resolución de conflictos, restaurar valores y zonas muertas/sensibilidad.

signal closed
signal edit_controls_requested

var _tab := "touch"
var _body: VBoxContainer
var _tab_btns: Dictionary = {}
var _status: Label
var _box: Control            # diálogo modal actual (captura / conflicto)
var _cap_t := 0.0
var _cap_label: Label
var _scroll: ScrollContainer
var _action_btns: Dictionary = {}     # acción -> Button (para devolver el foco tras reasignar)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UIKit.dim_background(0.88))
	var v := UIKit.center_box(self, Vector2(940, 640))
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := UIKit.label("CONTROLES", 42, UIKit.ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var close := UIKit.accent_button("Volver", Vector2(200, 60), 26)
	close.pressed.connect(func():
		SaveSystem.save_now()
		closed.emit()
		queue_free())
	head.add_child(close)
	var tabs := HBoxContainer.new()
	v.add_child(tabs)
	for k in [["touch", "TÁCTIL"], ["pad", "MANDO"], ["keys", "TECLADO"]]:
		var b := UIKit.button(String(k[1]), Vector2(200, 54), 22)
		b.toggle_mode = true
		b.name = "Tab_" + String(k[0])
		b.pressed.connect(_show_tab.bind(String(k[0])))
		tabs.add_child(b)
		_tab_btns[k[0]] = b
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(900, 470)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)
	if PadInput.inst != null:
		PadInput.inst.devices_changed.connect(_refresh_status)
		PadInput.inst.bindings_changed.connect(_refresh_labels)
	_show_tab("pad" if PadInput.pad_mode else "touch")


func _process(delta: float) -> void:
	if _box != null and is_instance_valid(_box) and PadInput.inst != null and PadInput.inst.capturing and _cap_t > 0.0:
		_cap_t -= delta
		if _cap_label != null:
			_cap_label.text = "Cancelación automática en %d s" % int(ceil(maxf(_cap_t, 0.0)))
		if _cap_t <= 0.0:
			PadInput.inst.cancel_capture()


func _clear_body() -> void:
	for c in _body.get_children():
		_body.remove_child(c)       # fuera del árbol ya: los nombres (Bind_attack…) quedan libres para la pestaña nueva
		c.queue_free()
	_action_btns.clear()
	_status = null


func _show_tab(tab: String) -> void:
	_tab = tab
	for k in _tab_btns.keys():
		(_tab_btns[k] as Button).button_pressed = (k == tab)
	_clear_body()
	match tab:
		"touch": _build_touch()
		"pad": _build_pad()
		"keys": _build_keys()
	_scroll.scroll_vertical = 0


# ------------------------------------------------------------------ piezas
func _section(text: String) -> void:
	_body.add_child(UIKit.label(text.to_upper(), 22, UIKit.ACCENT))
	UIKit.hsep(_body)


func _note(text: String) -> void:
	var l := UIKit.label(text, 18, UIKit.TEXT_DIM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(860, 0)
	_body.add_child(l)


## Deslizador ligado a un diccionario guardado (clave dentro de d).
func _slider(label: String, d: Dictionary, key: String, lo: float, hi: float, step: float, pct := true) -> HSlider:
	var row := HBoxContainer.new()
	_body.add_child(row)
	var l := UIKit.label(label, 22)
	l.custom_minimum_size = Vector2(340, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(d[key])
	s.custom_minimum_size = Vector2(380, 44)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.name = "S_" + key
	s.focus_mode = Control.FOCUS_ALL if PadInput.pad_mode else Control.FOCUS_NONE
	var val := UIKit.label(("%d%%" % int(round(s.value * 100.0))) if pct else "%.2f" % s.value, 22, UIKit.TEXT_DIM)
	s.value_changed.connect(func(x):
		d[key] = x
		SaveSystem.mark_dirty()
		val.text = ("%d%%" % int(round(x * 100.0))) if pct else "%.2f" % x)
	row.add_child(s)
	row.add_child(val)
	return s


# ------------------------------------------------------------------ TÁCTIL
func _build_touch() -> void:
	_section("Joystick de movimiento")
	_note("El joystick aparece bajo tu pulgar, pero solo si tocas la zona inferior izquierda (se ve como un rectángulo tenue). Tocar fuera de esa zona, los botones o el inventario no mueve al personaje.")
	_slider("Tamaño de la zona", SaveSystem.data["settings"], "joy_zone", 0.6, 1.4, 0.05)
	_slider("Sensibilidad", SaveSystem.data["settings"], "joy_sens", 0.5, 1.8, 0.05)
	_note("El tamaño y la posición del joystick y de los botones se editan arrastrándolos:")
	var row := HBoxContainer.new()
	_body.add_child(row)
	var edit := UIKit.button("Editar posición y tamaño", Vector2(380, 60), 22)
	edit.pressed.connect(func():
		edit_controls_requested.emit()
		SaveSystem.save_now()
		queue_free())
	row.add_child(edit)
	var rst := UIKit.button("Restablecer", Vector2(220, 60), 22)
	rst.pressed.connect(func():
		SaveSystem.reset_controls()
		SaveSystem.data["settings"]["joy_zone"] = 1.0
		SaveSystem.data["settings"]["joy_sens"] = 1.0
		GameState.toast_msg("Controles táctiles restablecidos", UIKit.GOOD)
		_show_tab("touch"))
	row.add_child(rst)


# ------------------------------------------------------------------ MANDO
func _build_pad() -> void:
	var pi := PadInput.inst
	_section("Mando")
	_status = UIKit.label("", 22, UIKit.GOOD)
	_status.name = "PadStatus"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(860, 0)
	_body.add_child(_status)
	_refresh_status()
	var mrow := HBoxContainer.new()
	_body.add_child(mrow)
	mrow.add_child(UIKit.label("Controles en uso", 22))
	var modes := [["auto", "AUTOMÁTICO"], ["touch", "SOLO TÁCTIL"], ["pad", "SOLO MANDO"]]
	var mb: Array = []
	for m in modes:
		var b := UIKit.button(String(m[1]), Vector2(200, 54), 20)
		b.toggle_mode = true
		b.name = "Mode_" + String(m[0])
		b.button_pressed = pi.mode_setting() == m[0]
		b.pressed.connect(func():
			pi.set_mode_setting(String(m[0]))
			for o in mb:
				o.button_pressed = (o == b)
			_refresh_status())
		mb.append(b)
		mrow.add_child(b)
	_note("Automático: al conectar un mando se ocultan los controles táctiles y reaparecen al desconectarlo.")
	_section("Sticks")
	var srow := HBoxContainer.new()
	_body.add_child(srow)
	var l := UIKit.label("Moverse", 24)
	l.custom_minimum_size = Vector2(340, 0)
	srow.add_child(l)
	var sb := UIKit.button("", Vector2(260, 54), 22)
	sb.name = "MoveStick"
	srow.add_child(sb)
	var cam_lbl := UIKit.label("", 22, UIKit.TEXT_DIM)
	srow.add_child(cam_lbl)
	var upd := func():
		var left: bool = pi.move_stick_name() == "left"
		sb.text = "Stick izquierdo" if left else "Stick derecho"
		cam_lbl.text = "Girar la cámara: stick %s" % ("derecho" if left else "izquierdo")
	upd.call()
	sb.pressed.connect(func():
		PadInput.cfg()["move_stick"] = "right" if pi.move_stick_name() == "left" else "left"
		SaveSystem.mark_dirty()
		upd.call())
	_slider("Sensibilidad de la cámara", PadInput.cfg(), "look_sens", 0.3, 2.5, 0.05)
	_slider("Zona muerta del movimiento", PadInput.cfg(), "dead_move", 0.05, 0.5, 0.01)
	_slider("Zona muerta de la cámara", PadInput.cfg(), "dead_look", 0.05, 0.5, 0.01)
	_section("Botones (selecciona una acción y pulsa el botón nuevo)")
	for a in PadInput.GAME_ACTIONS:
		_action_row(String(a))
	_section("Menús, cartas y cofres")
	_note("Navegar: cruceta o stick izquierdo (fijo).")
	for a in PadInput.UI_ACTIONS:
		_action_row(String(a))
	var rst := UIKit.button("Restaurar valores predeterminados", Vector2(520, 60), 22)
	rst.name = "ResetPad"
	rst.pressed.connect(func():
		PadInput.reset_bindings()
		GameState.toast_msg("Mando restaurado", UIKit.GOOD)
		_show_tab("pad"))
	_body.add_child(rst)


func _action_row(a: String) -> void:
	var row := HBoxContainer.new()
	_body.add_child(row)
	var l := UIKit.label(String(PadInput.ACTION_LABEL[a]), 22)
	l.custom_minimum_size = Vector2(500, 0)
	row.add_child(l)
	var b := UIKit.button(PadInput.inst.action_label(a), Vector2(260, 54), 22)
	b.name = "Bind_" + a
	b.set_meta("action", a)
	b.pressed.connect(func(): _start_capture(a, "pad"))
	row.add_child(b)
	_action_btns[a] = b


func _refresh_status() -> void:
	if _status == null or not is_instance_valid(_status):
		return
	var pi := PadInput.inst
	if pi.connected():
		var kind := pi.device_kind()
		var kn: String = {"xbox": "Xbox", "ps": "PlayStation", "generic": "genérico"}[kind]
		_status.text = "Mando detectado: %s (%s)%s" % [pi.device_name(pi.active), kn, "" if pi.devices.size() < 2 else " · %d conectados, activo el último que usaste" % pi.devices.size()]
		_status.add_theme_color_override("font_color", UIKit.GOOD)
	else:
		_status.text = "Ningún mando conectado. Conecta uno por Bluetooth o USB."
		_status.add_theme_color_override("font_color", UIKit.TEXT_DIM)
	_refresh_labels()


func _refresh_labels() -> void:
	for a in _action_btns.keys():
		var b: Button = _action_btns[a]
		if is_instance_valid(b):
			b.text = PadInput.inst.key_name(String(a)) if _tab == "keys" else PadInput.inst.action_label(String(a))


# ------------------------------------------------------------------ TECLADO
func _build_keys() -> void:
	_section("Teclado (PC)")
	_note("En el móvil no hace falta. Pulsa una acción y luego la tecla nueva (Esc cancela). Una tecla solo sirve para una acción.")
	for a in PadInput.KEY_ACTIONS:
		var row := HBoxContainer.new()
		_body.add_child(row)
		var l := UIKit.label(String(PadInput.KEY_LABEL[a]), 22)
		l.custom_minimum_size = Vector2(500, 0)
		row.add_child(l)
		var b := UIKit.button(PadInput.inst.key_name(String(a)), Vector2(260, 54), 22)
		b.name = "Key_" + String(a)
		b.pressed.connect(func(): _start_capture(String(a), "key"))
		row.add_child(b)
		_action_btns[a] = b
	var rst := UIKit.button("Restaurar teclas", Vector2(360, 60), 22)
	rst.pressed.connect(func():
		PadInput.reset_keys()
		_show_tab("keys"))
	_body.add_child(rst)


# ------------------------------------------------------------------ reasignación
func _start_capture(action: String, kind: String) -> void:
	_close_box()
	_box = Control.new()
	_box.name = "CaptureBox"
	_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_box)
	_box.add_child(UIKit.dim_background(0.7))
	var v := UIKit.center_box(_box, Vector2(640, 260))
	var what := String(PadInput.ACTION_LABEL[action]) if kind == "pad" else String(PadInput.KEY_LABEL[action])
	v.add_child(UIKit.label(what, 30, UIKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	var prompt := "Pulsa el botón del mando que quieres usar…" if kind == "pad" else "Pulsa la tecla que quieres usar… (Esc cancela)"
	v.add_child(UIKit.label(prompt, 24, UIKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	_cap_label = UIKit.label("", 20, UIKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_cap_label)
	_cap_t = 8.0
	var cancel := UIKit.button("CANCELAR", Vector2(260, 56), 22)
	cancel.name = "CaptureCancel"
	cancel.pressed.connect(func():
		if PadInput.inst.capturing:
			PadInput.inst.cancel_capture())
	var cr := HBoxContainer.new()
	cr.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(cr)
	cr.add_child(cancel)
	PadInput.inst.begin_capture(kind, func(b: Dictionary): _on_captured(action, kind, b))


func _close_box() -> void:
	if _box != null and is_instance_valid(_box):
		_box.queue_free()
	_box = null
	_cap_label = null


func _on_captured(action: String, kind: String, b: Dictionary) -> void:
	_close_box()
	if b.is_empty():
		GameState.toast_msg("Reasignación cancelada", UIKit.TEXT_DIM)
		_restore_focus(action)
		return
	if kind == "key":
		PadInput.set_key(action, int(b["i"]))
		_refresh_labels()
		_restore_focus(action)
		return
	var other := PadInput.find_conflict(action, b)
	if other == "":
		PadInput.set_binding(action, b)
		GameState.toast_msg("%s → %s" % [PadInput.ACTION_LABEL[action], PadInput.inst.button_name(b)], UIKit.GOOD)
		_restore_focus(action)
		return
	_ask_conflict(action, other, b)


func _ask_conflict(action: String, other: String, b: Dictionary) -> void:
	_box = Control.new()
	_box.name = "ConflictBox"
	_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_box)
	_box.add_child(UIKit.dim_background(0.7))
	var v := UIKit.center_box(_box, Vector2(760, 300))
	v.add_child(UIKit.label("Botón ya usado", 32, UIKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	var msg := UIKit.label("«%s» ya está asignado a «%s». Si lo repites, una pulsación activaría las dos acciones a la vez." % [PadInput.inst.button_name(b), PadInput.ACTION_LABEL[other]], 22, UIKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.custom_minimum_size = Vector2(700, 0)
	v.add_child(msg)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	var swap := UIKit.accent_button("INTERCAMBIAR", Vector2(230, 60), 22)
	swap.name = "ConflictSwap"
	swap.pressed.connect(func():
		_close_box()
		# «action» recibe el botón nuevo y «other» recibe el que tenía «action»
		var old := PadInput.binding(action).duplicate()
		PadInput.set_binding(action, b)
		PadInput.set_binding(other, old)
		GameState.toast_msg("Botones intercambiados", UIKit.GOOD)
		_restore_focus(action))
	row.add_child(swap)
	var rep := UIKit.button("REEMPLAZAR", Vector2(230, 60), 22)
	rep.name = "ConflictReplace"
	rep.pressed.connect(func():
		_close_box()
		PadInput.set_binding(other, {"t": "none"})
		PadInput.set_binding(action, b)
		GameState.toast_msg("«%s» queda sin asignar" % PadInput.ACTION_LABEL[other], UIKit.BAD)
		_restore_focus(action))
	row.add_child(rep)
	var cancel := UIKit.button("CANCELAR", Vector2(230, 60), 22)
	cancel.name = "ConflictCancel"
	cancel.pressed.connect(func():
		_close_box()
		_restore_focus(action))
	row.add_child(cancel)


func _restore_focus(action: String) -> void:
	_refresh_labels()
	if PadInput.pad_mode and _action_btns.has(action):
		var b: Button = _action_btns[action]
		if is_instance_valid(b):
			b.call_deferred("grab_focus")
