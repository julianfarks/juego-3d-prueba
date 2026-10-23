class_name MainMenu
extends Control
## Menú principal sobre el escenario 3D del despacho (el abogado posa de fondo).

signal play_pressed
signal continue_pressed
signal lobby_pressed
signal meta_pressed
signal settings_pressed
signal quit_pressed

var _records: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var left := VBoxContainer.new()
	left.position = Vector2(70, 24)
	left.custom_minimum_size = Vector2(430, 0)
	left.add_theme_constant_override("separation", 6)
	add_child(left)
	var t1 := UIKit.label("LAWYER", 68, UIKit.ACCENT)
	t1.add_theme_constant_override("outline_size", 12)
	left.add_child(t1)
	var t2 := UIKit.label("MAYHEM 3D", 48, Color(1, 1, 1))
	t2.add_theme_constant_override("outline_size", 10)
	left.add_child(t2)
	left.add_child(UIKit.label("Objeción… ¡y a repartir sentencias!", 22, UIKit.TEXT_DIM))
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 2)
	left.add_child(sp)
	var has_run := SaveSystem.has_valid_run()
	# CONTINUAR solo aparece si existe una partida guardada válida
	if has_run:
		var run: Dictionary = SaveSystem.get_run()
		var cont := UIKit.accent_button("CONTINUAR PARTIDA", Vector2(420, 70), 30)
		cont.pressed.connect(func():
			AudioManager.sfx("click")
			continue_pressed.emit())
		left.add_child(cont)
		var diff_name := String(LoadoutDB.diff(String(run["difficulty"]))["name"])
		var info := UIKit.label("Arena %d · Ciclo %d · %s · %s" % [int(run["arena_index"]) + 1, Scaling.cycle_of(int(run["arena_index"])) + 1, diff_name, UIKit.fmt_time(float(run["run_time"]))], 19, UIKit.GOOD)
		left.add_child(info)
	var play: Button = UIKit.button("NUEVA PARTIDA", Vector2(420, 62), 28) if has_run else UIKit.accent_button("NUEVA PARTIDA", Vector2(420, 74), 32)
	play.pressed.connect(_on_new_pressed)
	left.add_child(play)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	left.add_child(grid)
	var lobby := UIKit.button("Sala Central", Vector2(206, 56), 22)
	lobby.pressed.connect(func():
		AudioManager.sfx("click")
		lobby_pressed.emit())
	grid.add_child(lobby)
	var meta := UIKit.button("El Despacho", Vector2(206, 56), 22)
	meta.pressed.connect(func():
		AudioManager.sfx("click")
		meta_pressed.emit())
	grid.add_child(meta)
	var rec := UIKit.button("Récords", Vector2(206, 56), 22)
	rec.pressed.connect(_toggle_records)
	grid.add_child(rec)
	var st := UIKit.button("Ajustes", Vector2(206, 56), 22)
	st.pressed.connect(func():
		AudioManager.sfx("click")
		settings_pressed.emit())
	grid.add_child(st)
	if OS.has_feature("pc") or OS.has_feature("web") == false and not OS.has_feature("android"):
		var q := UIKit.button("Salir", Vector2(206, 56), 22)
		q.pressed.connect(func(): quit_pressed.emit())
		grid.add_child(q)
	var fees := UIKit.label("Honorarios: %d" % int(SaveSystem.data["meta"]["fees"]), 26, Color(0.6, 1.0, 0.7))
	add_child(fees)
	UIKit.place(fees, 0.0, 1.0, 70, -60, 400, 40)
	var ver := UIKit.label("v%s" % Config.VERSION, 18, UIKit.TEXT_DIM)
	add_child(ver)
	UIKit.place(ver, 1.0, 1.0, -110, -44, 100, 30)


func _on_new_pressed() -> void:
	AudioManager.sfx("click")
	if not SaveSystem.has_valid_run():
		play_pressed.emit()
		return
	# hay una partida guardada: no se sobrescribe sin avisar
	var box := Control.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(box)
	box.add_child(UIKit.dim_background(0.7))
	var v := UIKit.center_box(box, Vector2(640, 260))
	v.add_theme_constant_override("separation", 12)
	v.add_child(UIKit.label("¿Empezar una partida nueva?", 34, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER))
	var l := UIKit.label("Ya tienes una partida guardada. Si empiezas una nueva, la partida guardada se perderá.", 22, UIKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(580, 0)
	v.add_child(l)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	var no := UIKit.accent_button("Cancelar", Vector2(240, 62), 26)
	no.pressed.connect(box.queue_free)
	row.add_child(no)
	var yes := UIKit.button("Sobrescribir", Vector2(240, 62), 26)
	yes.pressed.connect(func():
		box.queue_free()
		play_pressed.emit())
	row.add_child(yes)


func _toggle_records() -> void:
	AudioManager.sfx("click")
	if _records != null and is_instance_valid(_records):
		_records.queue_free()
		_records = null
		return
	var sp := StatsPanel.new()
	sp.closed.connect(func(): _records = null)
	add_child(sp)
	_records = sp
