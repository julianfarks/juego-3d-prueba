class_name SettingsMenu
extends Control
## Ajustes en tres páginas que se abren desde la pausa:
##   "game"  – AJUSTES: cámara, números de daño, vibración, acceso a CONTROLES y (oculto) modo desarrollador.
##   "video" – VÍDEO Y GRÁFICOS: calidad, sombras, distancia de dibujado, efectos, escala de render y límite de FPS.
##   "audio" – AUDIO: música y efectos por separado.
##   "camera" – CÁMARA: distancia, altura, inclinación, sensibilidad H/V e inversión del eje vertical (panel lateral para ver el efecto).
## Todos los valores se aplican al instante y se guardan en la partida (persisten entre sesiones).

signal closed
signal edit_controls_requested

const CODE_DEV_HASH := "9481bba0edf44b6d9ab0462aeea1726921565d97b7813b8537f7e4e971aacc5c"   # sha256 del código que desbloquea DESARROLLADOR
const AUDIO_DEFAULTS := {"music": 0.7, "sfx": 0.9, "combat_sfx": 0.85, "ambient": 0.6}
const TITLES := {"game": "AJUSTES", "video": "VÍDEO Y GRÁFICOS", "audio": "AUDIO", "camera": "CÁMARA"}

var page := "game"
var _taps := 0
var _tap_t := 0.0
var _dev_box: VBoxContainer
var _vbox: VBoxContainer
var _dev_tools_requested := false
var _opt_rows: Array = []        # {key, btns, values, getter}
var _toggles: Array = []         # {key, cb}
var _sliders: Array = []         # {key, slider, val, pct}
var _preset_note: Label
signal dev_tools_requested


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var is_cam := page == "camera"
	add_child(UIKit.dim_background(0.0 if is_cam else 0.85))
	var v: VBoxContainer
	if is_cam:
		# panel a un lado y sin oscurecer la escena: se ve al personaje mientras se ajusta
		var row := HBoxContainer.new()
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(row)
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(16, 0)
		gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(gap)
		var pnl := UIKit.panel(Vector2(560, 0))
		pnl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pnl.modulate = Color(1, 1, 1, 0.94)
		row.add_child(pnl)
		v = VBoxContainer.new()
		pnl.add_child(v)
		var rest := Control.new()
		rest.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rest.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(rest)
	else:
		v = UIKit.center_box(self, Vector2(900, 620))
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := UIKit.label(String(TITLES.get(page, "AJUSTES")), 42, UIKit.ACCENT)
	t.name = "PageTitle"
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var close := UIKit.accent_button("Volver", Vector2(200, 60), 26)
	close.name = "Close"
	close.pressed.connect(func():
		SaveSystem.save_now()
		closed.emit()
		queue_free())
	head.add_child(close)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(520, 470) if is_cam else Vector2(860, 520)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	_vbox = VBoxContainer.new()
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vbox.add_theme_constant_override("separation", 10)
	sc.add_child(_vbox)
	match page:
		"video":
			_build_video()
		"audio":
			_build_audio()
		"camera":
			_build_camera()
		_:
			_build_game()


func _build_audio() -> void:
	_section("Volumen")
	_slider("Música", "music", 0.0, 1.0, 0.05)
	_slider("Efectos de combate", "combat_sfx", 0.0, 1.0, 0.05)
	_slider("Otros efectos", "sfx", 0.0, 1.0, 0.05)
	_slider("Ambiente", "ambient", 0.0, 1.0, 0.05)
	var rb := UIKit.button("Restaurar audio", Vector2(360, 56), 22)
	rb.name = "ResetAudio"
	rb.pressed.connect(func():
		for k in AUDIO_DEFAULTS.keys():
			SaveSystem.set_setting(k, AUDIO_DEFAULTS[k])
		AudioManager.apply_volumes()
		_sync())
	_vbox.add_child(rb)


func _build_video() -> void:
	if Config.pc_mode():
		_section("Pantalla")
		_options("Modo de pantalla", "window_mode", Config.WINDOW_MODES, [], func(i):
			SaveSystem.set_setting("window_mode", i)
			Config.apply_display(), 190)
		var rs := Config.available_resolutions()
		var rnames: Array = []
		var rvals: Array = []
		for r in rs:
			rnames.append("%d×%d" % [r.x, r.y])
			rvals.append(Config.PC_RESOLUTIONS.find(r))
		_options("Resolución (ventana)", "resolution", rnames, rvals, func(i):
			SaveSystem.set_setting("resolution", i)
			Config.apply_display(), 150)
		_options("VSync", "vsync", Config.VSYNC_MODES, [], func(i):
			SaveSystem.set_setting("vsync", i)
			Config.apply_display(), 190)
	_section("Calidad gráfica")
	_options("Calidad", "quality", Config.quality_names(), [], func(i): Config.apply_preset(i))
	_preset_note = UIKit.label("", 20, UIKit.TEXT_DIM)
	_preset_note.name = "PresetNote"
	_vbox.add_child(_preset_note)
	_section("Ajustes detallados")
	_options("Sombras", "shadow_q", ["Apagadas", "Bajas", "Altas"])
	_options("Distancia de dibujado", "draw_dist", ["Corta", "Media", "Larga"])
	_options("Efectos", "fx_level", ["Reducidos", "Normales", "Completos"])
	_options("Escala de renderizado", "render_scale", ["50%", "67%", "85%", "100%"], Config.RENDER_SCALES)
	var fo := Config.fps_options()
	_options("Límite de FPS", "fps", fo.map(func(x): return "Sin límite" if int(x) == 0 else str(x)), fo, Callable(), 150 if Config.pc_mode() else 130)
	_toggle("Mostrar FPS", "show_fps")
	_toggle("Reducir efectos con muchos impactos", "reduce_fx")
	_vbox.add_child(UIKit.label("Los cambios se aplican al instante. En pantalla completa la resolución es la del escritorio (usa la escala de renderizado para ganar rendimiento)." if Config.pc_mode() else "Los cambios se aplican al instante. El límite de FPS real depende de la pantalla del dispositivo.", 18, UIKit.TEXT_DIM))
	var rb := UIKit.button("Restaurar valores predeterminados", Vector2(520, 60), 22)
	rb.name = "ResetVideo"
	rb.pressed.connect(func():
		Config.reset_graphics()
		_apply_gfx()
		_sync())
	_vbox.add_child(rb)
	_sync()


func _build_camera() -> void:
	_vbox.add_theme_constant_override("separation", 8)
	_cam_row("Distancia", "cam_dist", Config.CAM_DIST, 0.4, "%.1f m", "Acercar", "Alejar")
	_cam_row("Altura", "cam_height", Config.CAM_HEIGHT, 0.1, "%.1f m", "Bajar", "Subir")
	_cam_row("Inclinación", "cam_pitch", Config.CAM_PITCH, 2.0, "%d°", "Más plana", "Más picada")
	_cam_row("Sensibilidad horizontal", "cam_sens_x", Config.CAM_SENS, 0.1, "%d%%", "", "", true)
	_cam_row("Sensibilidad vertical", "cam_sens_y", Config.CAM_SENS, 0.1, "%d%%", "", "", true)
	_toggle("Invertir eje vertical", "cam_invert_y")
	_vbox.add_child(UIKit.label("Los cambios se ven al instante. Con mando: ◄ ► en el deslizador.", 17, UIKit.TEXT_DIM))
	var rb := UIKit.button("Restablecer cámara", Vector2(360, 56), 22)
	rb.name = "ResetCamera"
	rb.pressed.connect(func():
		Config.reset_camera()
		_sync())
	_vbox.add_child(rb)


## Fila de ajuste de cámara: etiqueta, deslizador con límites y botones − / + (acercar/alejar, bajar/subir…).
func _cam_row(label: String, key: String, lim: Dictionary, step: float, fmt: String, minus_tip: String, plus_tip: String, pct := false) -> void:
	var box := VBoxContainer.new()
	_vbox.add_child(box)
	var top := HBoxContainer.new()
	box.add_child(top)
	var l := UIKit.label(label, 22)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(l)
	var val := UIKit.label("", 22, UIKit.ACCENT, HORIZONTAL_ALIGNMENT_RIGHT)
	top.add_child(val)
	var row := HBoxContainer.new()
	box.add_child(row)
	var minus := UIKit.button("−", Vector2(64, 52), 28)
	minus.name = "Cam_%s_minus" % key
	row.add_child(minus)
	var s := HSlider.new()
	s.min_value = float(lim["min"])
	s.max_value = float(lim["max"])
	s.step = step * 0.5
	s.name = "Slider_" + key
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size = Vector2(300, 44)
	row.add_child(s)
	var plus := UIKit.button("+", Vector2(64, 52), 28)
	plus.name = "Cam_%s_plus" % key
	row.add_child(plus)
	var show := func(x: float):
		val.text = (fmt % int(round(x * 100.0))) if pct else (fmt % (int(round(x)) if fmt.contains("d") else x))
	s.value = float(SaveSystem.setting(key))
	show.call(s.value)
	s.value_changed.connect(func(x):
		SaveSystem.set_setting(key, x)
		show.call(x)
		Config.apply_camera())
	minus.pressed.connect(func(): s.value = clampf(s.value - step, s.min_value, s.max_value))
	plus.pressed.connect(func(): s.value = clampf(s.value + step, s.min_value, s.max_value))
	_sliders.append({"key": key, "slider": s, "val": val, "pct": pct, "fmt": fmt})


func _build_game() -> void:
	_section("Juego")
	_toggle("Números de daño", "damage_numbers")
	_slider("Tamaño de los números", "number_size", 0.6, 1.6, 0.05, true)
	_toggle("Vibración", "vibration")
	_section("Controles")
	var crow := HBoxContainer.new()
	_vbox.add_child(crow)
	var cbtn := UIKit.accent_button("CONTROLES: táctil, mando y teclado", Vector2(520, 64), 24)
	cbtn.name = "OpenControls"
	cbtn.pressed.connect(func():
		var cm := ControlsMenu.new()
		cm.edit_controls_requested.connect(func():
			edit_controls_requested.emit()
			queue_free())
		add_child(cm))
	crow.add_child(cbtn)
	_section("Códigos")
	var codes_btn := UIKit.accent_button("CÓDIGOS", Vector2(320, 60), 24)
	codes_btn.name = "OpenCodes"
	codes_btn.pressed.connect(_ask_code)
	_vbox.add_child(codes_btn)
	_dev_box = VBoxContainer.new()
	_dev_box.name = "DevBox"
	_vbox.add_child(_dev_box)
	_section("Acerca de")
	var ver := UIKit.label("%s  v%s" % [Config.GAME_NAME, Config.VERSION], 20, UIKit.TEXT_DIM)
	ver.name = "VersionLabel"
	ver.mouse_filter = Control.MOUSE_FILTER_STOP
	ver.gui_input.connect(_on_version_input)
	_vbox.add_child(ver)
	_vbox.add_child(UIKit.label("Hecho con Godot 4. Todo el arte y audio es procedural y original.", 18, UIKit.TEXT_DIM))
	_refresh_dev()


## Aplica al motor lo que hay guardado (escala, FPS, sombras, distancia, efectos).
func _apply_gfx() -> void:
	Config.apply_graphics(get_viewport())


## Refleja en la interfaz el estado guardado (tras un preset, restaurar, etc.).
func _sync() -> void:
	for r in _opt_rows:
		var cur: Variant = r["get"].call()
		var vals: Array = r["values"]
		for i in vals.size():
			(r["btns"][i] as Button).set_pressed_no_signal(_same(vals[i], cur))
	for t in _toggles:
		(t["cb"] as CheckButton).set_pressed_no_signal(bool(SaveSystem.setting(t["key"])))
	for sl in _sliders:
		var x := float(SaveSystem.setting(sl["key"]))
		(sl["slider"] as HSlider).set_value_no_signal(x)
		if sl.has("fmt"):
			var f: String = sl["fmt"]
			(sl["val"] as Label).text = (f % int(round(x * 100.0))) if sl["pct"] else (f % (int(round(x)) if f.contains("d") else x))
		else:
			(sl["val"] as Label).text = ("%d%%" % int(round(x * 100.0))) if sl["pct"] else "%.2f" % x
	if _preset_note != null:
		_preset_note.text = "" if Config.preset_matches() else "Personalizado: has cambiado ajustes sueltos respecto al preset."


static func _same(a: Variant, b: Variant) -> bool:
	if (typeof(a) == TYPE_FLOAT or typeof(a) == TYPE_INT) and (typeof(b) == TYPE_FLOAT or typeof(b) == TYPE_INT):
		return absf(float(a) - float(b)) < 0.001
	return a == b


func _section(text: String) -> void:
	var l := UIKit.label(text.to_upper(), 22, UIKit.ACCENT)
	_vbox.add_child(l)
	UIKit.hsep(_vbox)


func _slider(label: String, key: String, lo: float, hi: float, step: float, as_pct := false) -> void:
	as_pct = as_pct or hi <= 1.0
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
	var val := UIKit.label("%d%%" % int(round(s.value * 100.0)) if as_pct else "%.2f" % s.value, 22, UIKit.TEXT_DIM)
	s.name = "Slider_" + key
	_sliders.append({"key": key, "slider": s, "val": val, "pct": as_pct})
	s.value_changed.connect(func(x):
		SaveSystem.set_setting(key, x)
		val.text = ("%d%%" % int(round(x * 100.0))) if as_pct else "%.2f" % x
		AudioManager.apply_volumes()
		if GameState.fx != null:
			GameState.fx.apply_quality())
	if key == "combat_sfx":
		# al soltar el control suena un golpe de muestra con el volumen elegido
		s.drag_ended.connect(func(_changed): AudioManager.combat_sfx("hit_0", Vector3.ZERO, -4.0, AudioManager.P_BOSS))
	row.add_child(s)
	row.add_child(val)


func _toggle(label: String, key: String) -> void:
	var cb := CheckButton.new()
	cb.text = label
	cb.button_pressed = bool(SaveSystem.setting(key))
	cb.add_theme_font_size_override("font_size", 24)
	cb.focus_mode = Control.FOCUS_NONE
	cb.custom_minimum_size = Vector2(0, 54)
	cb.name = "Toggle_" + key
	cb.toggled.connect(func(on):
		SaveSystem.set_setting(key, on)
		if GameState.fx != null:
			GameState.fx.apply_quality())
	_toggles.append({"key": key, "cb": cb})
	_vbox.add_child(cb)


func _options(label: String, key: String, names: Array, values: Array = [], on_pick: Callable = Callable(), btn_w := 130) -> void:
	var row := HBoxContainer.new()
	_vbox.add_child(row)
	var l := UIKit.label(label, 24)
	l.custom_minimum_size = Vector2(300, 0)
	row.add_child(l)
	var vals: Array = values if not values.is_empty() else range(names.size())
	var btns: Array = []
	var getter := func() -> Variant:
		return Config.render_scale() if key == "render_scale" else SaveSystem.setting(key)
	for i in names.size():
		var b := UIKit.button(String(names[i]), Vector2(btn_w, 56), 22)
		var v: Variant = vals[i]
		b.name = "Opt_%s_%d" % [key, i]
		b.toggle_mode = true
		b.pressed.connect(func():
			if on_pick.is_valid():
				on_pick.call(v)
			else:
				SaveSystem.set_setting(key, v)
			_apply_gfx()
			_sync())
		btns.append(b)
		row.add_child(b)
	_opt_rows.append({"key": key, "btns": btns, "values": vals, "get": getter})
	_sync()


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


## Menú CÓDIGOS: se escribe un código y, si es válido, se desbloquea el menú DESARROLLADOR (se guarda en los ajustes).
func _ask_code() -> void:
	var box := Control.new()
	box.name = "CodesBox"
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(box)
	box.add_child(UIKit.dim_background(0.75))
	var v := UIKit.center_box(box, Vector2(min(620.0, get_viewport().get_visible_rect().size.x - 40.0), 0))
	v.add_theme_constant_override("separation", 10)
	v.add_child(UIKit.label("CÓDIGOS", 36, UIKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	var info := UIKit.label("Escribe un código para desbloquear contenido.", 20, UIKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(300, 0)
	v.add_child(info)
	var le := LineEdit.new()
	le.name = "CodeInput"
	le.placeholder_text = "Código"
	le.custom_minimum_size = Vector2(300, 58)
	le.add_theme_font_size_override("font_size", 26)
	v.add_child(le)
	var msg := UIKit.label("", 22, UIKit.GOOD, HORIZONTAL_ALIGNMENT_CENTER)
	msg.name = "CodeMsg"
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.custom_minimum_size = Vector2(300, 0)
	v.add_child(msg)
	var row := HFlowContainer.new()
	row.alignment = FlowContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("h_separation", 14)
	v.add_child(row)
	var no := UIKit.button("Cerrar", Vector2(200, 58), 24)
	no.name = "CodeClose"
	no.pressed.connect(box.queue_free)
	row.add_child(no)
	var ok := UIKit.accent_button("Canjear", Vector2(220, 58), 24)
	ok.name = "CodeRedeem"
	var redeem := func():
		var r := redeem_code(le.text)
		msg.text = String(r["msg"])
		msg.add_theme_color_override("font_color", UIKit.GOOD if bool(r["ok"]) else UIKit.BAD)
		if bool(r["ok"]):
			AudioManager.sfx("levelup")
			le.text = ""
		else:
			AudioManager.sfx("deny")
	ok.pressed.connect(redeem)
	le.text_submitted.connect(func(_t): redeem.call())
	row.add_child(ok)


## Canjea un código. Devuelve {"ok": bool, "msg": String}. «maletindefarks» desbloquea el menú DESARROLLADOR (persistente).
func redeem_code(text: String) -> Dictionary:
	var code := text.strip_edges().to_lower()
	if code == "":
		return {"ok": false, "msg": "Escribe un código."}
	if code.sha256_text() == CODE_DEV_HASH:
		if bool(SaveSystem.setting("dev_unlocked")):
			return {"ok": true, "msg": "Ya tenías desbloqueado el menú DESARROLLADOR."}
		SaveSystem.set_setting("dev_unlocked", true)
		SaveSystem.save_now()
		Config.dev_mode = true
		_refresh_dev()
		return {"ok": true, "msg": "¡Código válido! Se desbloqueó el menú DESARROLLADOR en Ajustes."}
	return {"ok": false, "msg": "Código no válido."}


func _refresh_dev() -> void:
	if _dev_box == null or not is_instance_valid(_dev_box):
		return
	for c in _dev_box.get_children():
		_dev_box.remove_child(c)
		c.queue_free()
	if bool(SaveSystem.setting("dev_unlocked")):
		Config.dev_mode = true
		var b := UIKit.accent_button("DESARROLLADOR", Vector2(320, 60), 24)
		b.name = "OpenDev"
		b.pressed.connect(func():
			dev_tools_requested.emit()
			queue_free())
		_dev_box.add_child(b)
		var off := UIKit.button("Ocultar menú DESARROLLADOR", Vector2(320, 52), 18)
		off.name = "DevOff"
		off.pressed.connect(func():
			SaveSystem.set_setting("dev_unlocked", false)
			Config.dev_mode = false
			Config.dev_god_mode = false
			Config.dev_show_debug = false
			Scaling.dev_mult = 1.0
			_refresh_dev())
		_dev_box.add_child(off)
