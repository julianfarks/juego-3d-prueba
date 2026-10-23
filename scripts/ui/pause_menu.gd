class_name PauseMenu
extends Control
## Menú de pausa (el árbol está pausado; esta capa procesa siempre).

signal resume_pressed
signal settings_pressed
signal quit_pressed


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UIKit.dim_background(0.7))
	var v := UIKit.center_box(self, Vector2(560, 0))
	v.add_theme_constant_override("separation", 14)
	v.add_child(UIKit.title("PAUSA", 52))
	v.add_child(UIKit.label("Arena %d · %d bajas · %s" % [GameState.arena_index + 1, GameState.kills, UIKit.fmt_time(GameState.run_time)], 22, UIKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	var r := UIKit.accent_button("Continuar", Vector2(440, 72), 30)
	r.pressed.connect(func(): resume_pressed.emit())
	v.add_child(r)
	var b := UIKit.button("Mi build", Vector2(440, 62), 24)
	b.pressed.connect(_show_build)
	v.add_child(b)
	var s := UIKit.button("Ajustes", Vector2(440, 62), 24)
	s.pressed.connect(func(): settings_pressed.emit())
	v.add_child(s)
	var q := UIKit.button("Abandonar partida", Vector2(440, 62), 24)
	q.pressed.connect(_confirm_quit)
	v.add_child(q)


func _show_build() -> void:
	var box := Control.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(box)
	box.add_child(UIKit.dim_background(0.6))
	var v := UIKit.center_box(box, Vector2(680, 500))
	v.add_child(UIKit.label("TU BUILD", 38, UIKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(640, 330)
	v.add_child(sc)
	var lv := VBoxContainer.new()
	sc.add_child(lv)
	var b: Build = GameState.build
	var lines := b.summary_lines()
	if lines.is_empty():
		lines = ["Aún no tienes mejoras. ¡Abre cofres!"]
	for l in lines:
		lv.add_child(UIKit.label("• " + String(l), 22))
	for sid in b.active_synergies:
		lv.add_child(UIKit.label("★ Sinergia activa: " + String(sid), 22, Color(1.0, 0.85, 0.3)))
	var c := UIKit.accent_button("Cerrar", Vector2(240, 60), 24)
	c.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	c.pressed.connect(box.queue_free)
	v.add_child(c)


func _confirm_quit() -> void:
	var box := Control.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(box)
	box.add_child(UIKit.dim_background(0.6))
	var v := UIKit.center_box(box, Vector2(600, 240))
	v.add_child(UIKit.label("¿Abandonar la partida?", 32, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UIKit.label("Se contará como derrota (cobras los honorarios acumulados).", 20, UIKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	var no := UIKit.button("Seguir", Vector2(220, 60), 24)
	no.pressed.connect(box.queue_free)
	row.add_child(no)
	var yes := UIKit.accent_button("Abandonar", Vector2(240, 60), 24)
	yes.pressed.connect(func(): quit_pressed.emit())
	row.add_child(yes)
