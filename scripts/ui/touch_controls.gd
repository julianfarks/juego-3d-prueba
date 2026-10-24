class_name TouchControls
extends Control
## Controles táctiles: joystick flotante (izquierda), cámara por arrastre (mitad derecha) y botones
## redondos con posición/tamaño configurables. Escribe en las acciones de InputMap, así que teclado
## y táctil comparten la misma ruta de entrada. En escritorio funciona con ratón (emulate_touch_from_mouse).

signal edit_finished

const BUTTONS := ["attack", "jump", "dodge", "skill1", "interact"]   # SELLO y OBJECIÓN ya no son botones (automáticos)
const LABELS := {
	"attack": "ATACAR", "jump": "SALTAR", "dodge": "ESQUIVAR", "skill1": "DOCS", "interact": "USAR",
}
const COLORS := {
	"attack": Color(1.0, 0.45, 0.25), "jump": Color(0.4, 0.8, 1.0), "dodge": Color(0.5, 1.0, 0.7),
	"skill1": Color(1.0, 0.85, 0.35),
	"interact": Color(1.0, 1.0, 1.0),
}
const BASE_R := 54.0
const JOY_R := 96.0
const JOY_ZONE_X := 0.34       # el joystick solo nace en la parte inferior izquierda: x ≤ 34 % del ancho…
const JOY_ZONE_TOP := 0.45     # …y por debajo del 45 % de la altura (valores a escala 1.0 de la opción «zona»)
const CAM_X := 0.46            # la cámara se arrastra solo en la mitad derecha
const JOY_DEAD := 0.12

var edit_mode := false
var selected := "attack"
var _pointers: Dictionary = {}       # index -> {role, ...}
var _joy_origin := Vector2.ZERO
var _joy_pos := Vector2.ZERO
var _joy_active := false
var _joy_vec := Vector2.ZERO
var _pressed: Dictionary = {}
var _toolbar: PanelContainer
var _slider: HSlider
var _sel_label: Label
var show_interact := false
var _icons: Dictionary = {}
var blockers: Array = []             # controles de la interfaz (inventario, pausa) que nunca deben iniciar movimiento ni cámara
var last_event_pos := Vector2.ZERO    # (pruebas) última posición de toque recibida, en coordenadas del control
var suppressed := false              # modo mando: los controles táctiles no capturan ni dibujan


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	for b in BUTTONS:
		_pressed[b] = false


func _layout(name: String) -> Dictionary:
	return SaveSystem.data["controls"][name]


func _center(name: String) -> Vector2:
	var l := _layout(name)
	return Vector2(float(l["x"]) * size.x, float(l["y"]) * size.y)


func _radius(name: String) -> float:
	return (BASE_R if name != "joystick" else JOY_R) * float(_layout(name)["scale"])


## Zona (en coordenadas del control) donde puede nacer el joystick dinámico.
func joy_zone() -> Rect2:
	var zs := clampf(float(SaveSystem.setting("joy_zone")), 0.6, 1.4)
	var w := minf(JOY_ZONE_X * zs, CAM_X - 0.02)
	var top := clampf(1.0 - (1.0 - JOY_ZONE_TOP) * zs, 0.2, 0.9)
	return Rect2(0.0, size.y * top, size.x * w, size.y * (1.0 - top))


func in_joy_zone(pos: Vector2) -> bool:
	if joy_zone().has_point(pos):
		return true
	# el joystick fijo configurado (aunque el jugador lo haya movido) siempre es válido
	return pos.distance_to(_center("joystick")) <= _radius("joystick") * 1.3


func _over_ui(pos: Vector2) -> bool:
	for b in blockers:
		if is_instance_valid(b) and (b as Control).is_visible_in_tree() and (b as Control).get_global_rect().grow(10.0).has_point(pos):
			return true
	return false


func joy_active() -> bool:
	return _joy_active


func joy_vector() -> Vector2:
	return _joy_vec


func _process(_delta: float) -> void:
	var pl = GameState.player
	show_interact = pl != null and pl.interact_target != null and not edit_mode
	if visible:
		queue_redraw()


func _btn_visible(name: String) -> bool:
	if name == "interact":
		return show_interact or edit_mode
	return true


func _button_at(pos: Vector2) -> String:
	for name in BUTTONS:
		if not _btn_visible(name):
			continue
		if pos.distance_to(_center(name)) <= _radius(name) * 1.12:
			return name
	return ""


func _input(event: InputEvent) -> void:
	if not visible or (get_tree().paused and not edit_mode) or (suppressed and not edit_mode):
		return
	if event is InputEventScreenTouch:
		var pos: Vector2 = event.position
		last_event_pos = pos
		if event.pressed:
			_on_down(event.index, pos)
		else:
			_on_up(event.index)
	elif event is InputEventScreenDrag:
		_on_drag(event.index, event.position, event.relative)


func _on_down(idx: int, pos: Vector2) -> void:
	if edit_mode and _toolbar != null and _toolbar.get_global_rect().has_point(pos):
		return
	var b := _button_at(pos)
	if edit_mode:
		var target := b
		if target == "" and pos.distance_to(_center("joystick")) <= _radius("joystick"):
			target = "joystick"
		if target != "":
			_select(target)
			_pointers[idx] = {"role": "edit", "name": target, "off": _center(target) - pos}
		return
	if b != "":
		_pointers[idx] = {"role": "button", "name": b}
		_set_action(b, true)
		return
	if _over_ui(pos):
		return      # tocar el inventario o la pausa nunca mueve al personaje ni la cámara
	if in_joy_zone(pos):
		if _joy_active:
			return  # ya hay un dedo en el joystick: otro toque no lo cambia
		var r := JOY_R * float(_layout("joystick")["scale"])
		_pointers[idx] = {"role": "joy"}
		_joy_active = true
		# la base nace bajo el pulgar pero siempre completa dentro de la pantalla
		_joy_origin = Vector2(clampf(pos.x, r + 8.0, size.x - r - 8.0), clampf(pos.y, r + 8.0, size.y - r - 8.0))
		_joy_pos = pos
		_joy_vec = ((pos - _joy_origin) / r).limit_length(1.0)
		_apply_joy()
	elif pos.x >= size.x * CAM_X:
		_pointers[idx] = {"role": "cam"}
	# cualquier otro punto de la izquierda queda fuera de las zonas de control: se ignora


func _on_up(idx: int) -> void:
	if not _pointers.has(idx):
		return
	var p: Dictionary = _pointers[idx]
	match p["role"]:
		"button":
			_set_action(p["name"], false)
		"joy":
			_joy_active = false
			_joy_vec = Vector2.ZERO
			_apply_joy()
		"edit":
			SaveSystem.mark_dirty()
	_pointers.erase(idx)


func _on_drag(idx: int, pos: Vector2, rel: Vector2) -> void:
	if not _pointers.has(idx):
		return
	var p: Dictionary = _pointers[idx]
	match p["role"]:
		"joy":
			_joy_pos = pos
			var d := pos - _joy_origin
			var r := JOY_R * float(_layout("joystick")["scale"])
			if d.length() > r:
				# el origen sigue al dedo para no quedar atascado en un borde
				_joy_origin = pos - d.normalized() * r
				d = pos - _joy_origin
			_joy_vec = d / r
			_apply_joy()
		"cam":
			GameState.look_delta += rel
		"edit":
			var np: Vector2 = pos + p["off"]
			var l := _layout(p["name"])
			l["x"] = clampf(np.x / size.x, 0.04, 0.96)
			l["y"] = clampf(np.y / size.y, 0.08, 0.94)
		"button":
			pass


func _apply_joy() -> void:
	var v := _joy_vec
	var len := v.length()
	if len < JOY_DEAD:
		v = Vector2.ZERO
	else:
		# curva suave al empezar y respuesta completa al empujar; la misma para todas las direcciones
		# (la magnitud nunca supera 1, así que las diagonales no van más rápido)
		var t := clampf((len - JOY_DEAD) / (0.88 - JOY_DEAD), 0.0, 1.0)     # velocidad máxima al 88 % del recorrido
		var sens := clampf(float(SaveSystem.setting("joy_sens")), 0.5, 1.8)
		v = v / len * clampf(pow(t, 1.15) * sens, 0.0, 1.0)
	_set_axis("move_left", maxf(-v.x, 0.0))
	_set_axis("move_right", maxf(v.x, 0.0))
	_set_axis("move_forward", maxf(-v.y, 0.0))
	_set_axis("move_back", maxf(v.y, 0.0))


func _set_axis(action: String, strength: float) -> void:
	if strength > 0.001:
		Input.action_press(action, strength)
	else:
		Input.action_release(action)


func _set_action(name: String, down: bool) -> void:
	_pressed[name] = down
	if down:
		Input.action_press(name)
	else:
		Input.action_release(name)


func set_suppressed(on: bool) -> void:
	suppressed = on
	if on:
		release_all()
	queue_redraw()


func release_all() -> void:
	for n in BUTTONS:
		Input.action_release(n)
		_pressed[n] = false
	for a in ["move_left", "move_right", "move_forward", "move_back"]:
		Input.action_release(a)
	_pointers.clear()
	_joy_active = false
	_joy_vec = Vector2.ZERO


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not visible:
		release_all()
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		release_all()


# ------------------------------------------------------------------ dibujo
func _draw() -> void:
	if suppressed and not edit_mode:
		return
	# zona donde nace el joystick (muy tenue, solo mientras no se usa)
	if not _joy_active:
		var z := joy_zone()
		draw_rect(z, Color(1, 1, 1, 0.025 if not edit_mode else 0.07), true)
		draw_rect(z, Color(1, 1, 1, 0.07 if not edit_mode else 0.2), false, 2.0)
	# joystick
	var jr := _radius("joystick")
	var jc := _center("joystick")
	var base_c := _joy_origin if _joy_active else jc
	var knob := _joy_pos if _joy_active else jc
	if _joy_active:
		knob = base_c + _joy_vec.limit_length(1.0) * jr
	draw_circle(base_c, jr, Color(0.0, 0.0, 0.0, 0.22))
	draw_circle(base_c, jr, Color(1, 1, 1, 0.1))
	draw_arc(base_c, jr, 0, TAU, 48, Color(1, 1, 1, 0.55 if _joy_active else 0.3), 3.5)
	draw_circle(knob, jr * 0.46, Color(0.0, 0.0, 0.0, 0.3))
	draw_circle(knob, jr * 0.42, Color(1, 1, 1, 0.55 if _joy_active else 0.28))
	draw_arc(knob, jr * 0.42, 0, TAU, 32, Color(1, 1, 1, 0.85), 2.5)
	if edit_mode and selected == "joystick":
		draw_arc(jc, jr + 8.0, 0, TAU, 48, UIKit.ACCENT, 4.0)
	# botones
	var pl = GameState.player
	var font := ThemeDB.fallback_font
	for name in BUTTONS:
		if not _btn_visible(name):
			continue
		var c := _center(name)
		var r := _radius(name)
		var col: Color = COLORS[name]
		var down: bool = _pressed[name] or (_is_pointer_on(name))
		var cdf := 0.0
		var afford := true
		if pl != null and not edit_mode:
			match name:
				"skill1":
					var slot := int(name.substr(5))
					cdf = pl.skills.cd_fraction(slot)
					afford = pl.skills.energy >= pl.skills.skill_cost(slot)
				"dodge":
					cdf = pl.dodge_cd_fraction()
		var alpha := 0.34 if not down else 0.62
		draw_circle(c, r, Color(col.r * 0.25, col.g * 0.25, col.b * 0.25, 0.55))
		draw_circle(c, r * 0.92, Color(col.r, col.g, col.b, alpha * (0.55 if not afford else 1.0)))
		draw_arc(c, r, 0, TAU, 40, Color(col.r, col.g, col.b, 0.9 if afford else 0.4), 3.5)
		if cdf > 0.01:
			var pts := PackedVector2Array([c])
			var a0 := -PI * 0.5
			var a1 := a0 + TAU * cdf
			var seg := maxi(4, int(40.0 * cdf))
			for i in seg + 1:
				var a := lerpf(a0, a1, float(i) / seg)
				pts.append(c + Vector2(cos(a), sin(a)) * r * 0.92)
			draw_colored_polygon(pts, Color(0, 0, 0, 0.55))
		var txt: String = LABELS[name]
		if name == "interact" and pl != null and not edit_mode and pl.interact_target != null:
			txt = String((pl.interact_target as Interactable).action_text)
		var fs := int(clampf(r * 0.3, 12.0, 26.0))
		var ts := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		draw_string(font, c + Vector2(-ts.x * 0.5, fs * 0.35), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.95))
		if name.begins_with("skill") and pl != null and not edit_mode:
			var cost := int(pl.skills.skill_cost(int(name.substr(5))))
			var cs := "%d" % cost
			draw_string(font, c + Vector2(-8, r * 0.78), cs, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 0.95, 0.5, 0.9))
		if edit_mode and selected == name:
			draw_arc(c, r + 8.0, 0, TAU, 48, UIKit.ACCENT, 4.0)


func _is_pointer_on(name: String) -> bool:
	for p in _pointers.values():
		if p["role"] == "button" and p["name"] == name:
			return true
	return false


# ------------------------------------------------------------------ edición
func begin_edit() -> void:
	edit_mode = true
	visible = true
	release_all()
	selected = "attack"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _toolbar == null:
		_build_toolbar()
	_toolbar.visible = true
	_select("attack")


func end_edit() -> void:
	edit_mode = false
	if _toolbar != null:
		_toolbar.visible = false
	SaveSystem.mark_dirty()
	SaveSystem.save_now()
	edit_finished.emit()


func _build_toolbar() -> void:
	_toolbar = UIKit.panel()
	add_child(_toolbar)
	UIKit.place(_toolbar, 0.5, 0.0, -380, 14, 760, 150)
	var v := VBoxContainer.new()
	_toolbar.add_child(v)
	_sel_label = UIKit.label("Editando: ", 24, UIKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_sel_label)
	var hint := UIKit.label("Arrastra un botón para moverlo. Toca uno para elegirlo y ajusta su tamaño.", 18, UIKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(hint)
	var row := HBoxContainer.new()
	v.add_child(row)
	row.add_child(UIKit.label("Tamaño", 20))
	_slider = HSlider.new()
	_slider.min_value = 0.6
	_slider.max_value = 1.7
	_slider.step = 0.05
	_slider.custom_minimum_size = Vector2(260, 40)
	_slider.value_changed.connect(func(val): _layout(selected)["scale"] = val)
	row.add_child(_slider)
	var reset := UIKit.button("Restablecer", Vector2(150, 50), 20)
	reset.pressed.connect(func():
		SaveSystem.reset_controls()
		_select(selected))
	row.add_child(reset)
	var done := UIKit.accent_button("Listo", Vector2(120, 50), 22)
	done.pressed.connect(end_edit)
	row.add_child(done)


func _select(name: String) -> void:
	selected = name
	if _sel_label != null:
		_sel_label.text = "Editando: " + ("Joystick" if name == "joystick" else LABELS.get(name, name))
	if _slider != null:
		_slider.set_value_no_signal(float(_layout(name)["scale"]))
