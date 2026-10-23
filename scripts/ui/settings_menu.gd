class_name SettingsMenu
extends Control
## Ajustes: volúmenes independientes, calidad gráfica, FPS, cámara, opciones de juego, editor de
## controles táctiles y (oculto) acceso al modo desarrollador protegido por código.

signal closed
signal edit_controls_requested

const DEV_HASH := "cc22eeb5148b1958e6a9999e4f76bbaf152c7a81079d9218164199d9e2b46d2d"

var _taps := 0
var _tap_t := 0.0
var _dev_box: VBoxContainer
var _vbox: VBoxContainer
var _dev_tools_requested := false
signal dev_tools_requested


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UIKit.dim_background(0.85))
	var v := UIKit.center_box(self, Vector2(900, 620))
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := UIKit.label("AJUSTES", 42, UIKit.ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var close := UIKit.accent_button("Volver", Vector2(200, 60), 26)
	close.pressed.connect(func():
		SaveSystem.save_now()
		closed.emit()
		queue_free())
	head.add_child(close)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(860, 520)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	_vbox = VBoxContainer.new()
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vbox.add_theme_constant_override("separation", 10)
	sc.add_child(_vbox)
	_section("Audio")
	_slider("Música", "music", 0.0, 1.0, 0.05)
	_slider("Efectos", "sfx", 0.0, 1.0, 0.05)
	_slider("Ambiente", "ambient", 0.0, 1.0, 0.05)
	_section("Gráficos y rendimiento")
	_options("Calidad", "quality", ["Baja", "Media", "Alta"])
	_options("FPS máximos", "fps", ["30", "60"], [30, 60])
	_toggle("Mostrar FPS", "show_fps")
	_section("Juego")
	_slider("Sensibilidad de cámara", "camera_sens", 0.3, 2.5, 0.05)
	_toggle("Ataque automático", "auto_attack")
	_toggle("Números de daño", "damage_numbers")
	_toggle("Vibración", "vibration")
	_section("Controles táctiles")
	var row := HBoxContainer.new()
	_vbox.add_child(row)
	var edit := UIKit.button("Editar posición y tamaño", Vector2(380, 60), 22)
	edit.pressed.connect(func():
		edit_controls_requested.emit()
		SaveSystem.save_now()
		queue_free())
	row.add_child(edit)
	var rst := UIKit.button("Restablecer", Vector2(220, 60), 22)
	rst.pressed.connect(func():
		SaveSystem.reset_controls()
		GameState.toast_msg("Controles restablecidos", UIKit.GOOD))
	row.add_child(rst)
	_section("Acerca de")
	var ver := UIKit.label("%s  v%s" % [Config.GAME_NAME, Config.VERSION], 20, UIKit.TEXT_DIM)
	ver.mouse_filter = Control.MOUSE_FILTER_STOP
	ver.gui_input.connect(_on_version_input)
	_vbox.add_child(ver)
	_vbox.add_child(UIKit.label("Hecho con Godot 4. Todo el arte y audio es procedural y original.", 18, UIKit.TEXT_DIM))
	_dev_box = VBoxContainer.new()
	_vbox.add_child(_dev_box)
	_refresh_dev()


func _section(text: String) -> void:
	var l := UIKit.label(text.to_upper(), 22, UIKit.ACCENT)
	_vbox.add_child(l)
	UIKit.hsep(_vbox)


func _slider(label: String, key: String, lo: float, hi: float, step: float) -> void:
	var row := HBoxContainer.new()
	_vbox.add_child(row)
	var l := UIKit.label(label, 24)
	l.custom_minimum_size = Vector2(300, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(SaveSystem.setting(key))
	s.custom_minimum_size = Vector2(400, 44)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var val := UIKit.label("%d%%" % int(s.value * 100.0) if hi <= 1.0 else "%.2f" % s.value, 22, UIKit.TEXT_DIM)
	s.value_changed.connect(func(x):
		SaveSystem.set_setting(key, x)
		val.text = ("%d%%" % int(x * 100.0)) if hi <= 1.0 else "%.2f" % x
		AudioManager.apply_volumes())
	row.add_child(s)
	row.add_child(val)


func _toggle(label: String, key: String) -> void:
	var cb := CheckButton.new()
	cb.text = label
	cb.button_pressed = bool(SaveSystem.setting(key))
	cb.add_theme_font_size_override("font_size", 24)
	cb.focus_mode = Control.FOCUS_NONE
	cb.custom_minimum_size = Vector2(0, 54)
	cb.toggled.connect(func(on): SaveSystem.set_setting(key, on))
	_vbox.add_child(cb)


func _options(label: String, key: String, names: Array, values: Array = []) -> void:
	var row := HBoxContainer.new()
	_vbox.add_child(row)
	var l := UIKit.label(label, 24)
	l.custom_minimum_size = Vector2(300, 0)
	row.add_child(l)
	var cur: Variant = SaveSystem.setting(key)
	var btns: Array = []
	for i in names.size():
		var b := UIKit.button(String(names[i]), Vector2(130, 56), 22)
		var v: Variant = values[i] if not values.is_empty() else i
		b.toggle_mode = true
		b.button_pressed = (cur == v)
		b.pressed.connect(func():
			SaveSystem.set_setting(key, v)
			for o in btns:
				o.button_pressed = (o == b)
			Config.apply_graphics(get_viewport())
			if GameState.fx != null:
				GameState.fx.apply_quality())
		btns.append(b)
		row.add_child(b)


func _on_version_input(event: InputEvent) -> void:
	var pressed: bool = (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed)
	if not pressed:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _tap_t > 1.2:
		_taps = 0
	_tap_t = now
	_taps += 1
	if _taps >= 7:
		_taps = 0
		_ask_code()


func _ask_code() -> void:
	if bool(SaveSystem.setting("dev_unlocked")):
		return
	var box := Control.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(box)
	box.add_child(UIKit.dim_background(0.7))
	var v := UIKit.center_box(box, Vector2(560, 240))
	v.add_child(UIKit.label("Código de acceso", 28, UIKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	var le := LineEdit.new()
	le.secret = true
	le.custom_minimum_size = Vector2(440, 56)
	v.add_child(le)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	var no := UIKit.button("Cancelar", Vector2(200, 56), 22)
	no.pressed.connect(box.queue_free)
	row.add_child(no)
	var ok := UIKit.accent_button("Entrar", Vector2(200, 56), 22)
	ok.pressed.connect(func():
		if le.text.sha256_text() == DEV_HASH:
			SaveSystem.set_setting("dev_unlocked", true)
			Config.dev_mode = true
			GameState.toast_msg("Modo desarrollador activado", UIKit.GOOD)
			box.queue_free()
			_refresh_dev()
		else:
			AudioManager.sfx("deny")
			le.text = ""
			le.placeholder_text = "Código incorrecto")
	row.add_child(ok)


func _refresh_dev() -> void:
	for c in _dev_box.get_children():
		c.queue_free()
	if bool(SaveSystem.setting("dev_unlocked")):
		Config.dev_mode = true
		var b := UIKit.button("Abrir herramientas de desarrollo", Vector2(460, 60), 22)
		b.pressed.connect(func():
			dev_tools_requested.emit()
			queue_free())
		_dev_box.add_child(b)
		var off := UIKit.button("Desactivar modo desarrollador", Vector2(460, 56), 20)
		off.pressed.connect(func():
			SaveSystem.set_setting("dev_unlocked", false)
			Config.dev_mode = false
			Config.dev_god_mode = false
			Config.dev_show_debug = false
			Scaling.dev_mult = 1.0
			_refresh_dev())
		_dev_box.add_child(off)
