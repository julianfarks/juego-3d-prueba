class_name MainMenu
extends Control
## Menú principal sobre el escenario 3D del despacho (el abogado posa de fondo).

signal play_pressed
signal meta_pressed
signal settings_pressed
signal quit_pressed

var _records: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var left := VBoxContainer.new()
	left.position = Vector2(70, 24)
	left.custom_minimum_size = Vector2(540, 0)
	left.add_theme_constant_override("separation", 8)
	add_child(left)
	var t1 := UIKit.label("LAWYER", 84, UIKit.ACCENT)
	t1.add_theme_constant_override("outline_size", 14)
	left.add_child(t1)
	var t2 := UIKit.label("MAYHEM 3D", 60, Color(1, 1, 1))
	t2.add_theme_constant_override("outline_size", 12)
	left.add_child(t2)
	left.add_child(UIKit.label("Objeción… ¡y a repartir sentencias!", 24, UIKit.TEXT_DIM))
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(0, 4)
	left.add_child(sp)
	var play := UIKit.accent_button("JUGAR", Vector2(420, 76), 36)
	play.pressed.connect(func():
		AudioManager.sfx("click")
		play_pressed.emit())
	left.add_child(play)
	var meta := UIKit.button("El Despacho (mejoras)", Vector2(420, 58), 24)
	meta.pressed.connect(func():
		AudioManager.sfx("click")
		meta_pressed.emit())
	left.add_child(meta)
	var rec := UIKit.button("Récords y estadísticas", Vector2(420, 58), 24)
	rec.pressed.connect(_toggle_records)
	left.add_child(rec)
	var st := UIKit.button("Ajustes", Vector2(420, 58), 24)
	st.pressed.connect(func():
		AudioManager.sfx("click")
		settings_pressed.emit())
	left.add_child(st)
	if OS.has_feature("pc") or OS.has_feature("web") == false and not OS.has_feature("android"):
		var q := UIKit.button("Salir", Vector2(420, 54), 22)
		q.pressed.connect(func(): quit_pressed.emit())
		left.add_child(q)
	var fees := UIKit.label("Honorarios: %d" % int(SaveSystem.data["meta"]["fees"]), 26, Color(0.6, 1.0, 0.7))
	add_child(fees)
	UIKit.place(fees, 0.0, 1.0, 70, -60, 400, 40)
	var ver := UIKit.label("v%s" % Config.VERSION, 18, UIKit.TEXT_DIM)
	add_child(ver)
	UIKit.place(ver, 1.0, 1.0, -110, -44, 100, 30)


func _toggle_records() -> void:
	AudioManager.sfx("click")
	if _records != null:
		_records.queue_free()
		_records = null
		return
	_records = Control.new()
	_records.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_records)
	_records.add_child(UIKit.dim_background(0.7))
	var v := UIKit.center_box(_records, Vector2(760, 480))
	v.add_child(UIKit.label("RÉCORDS Y ESTADÍSTICAS", 38, UIKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	var r: Dictionary = SaveSystem.data["records"]
	var s: Dictionary = SaveSystem.data["stats"]
	var lines := [
		"Mejor arena alcanzada: %d" % int(r["best_arena"]),
		"Mejor ciclo: %d" % int(r["best_cycle"]),
		"Más bajas en una partida: %d" % int(r["best_kills"]),
		"Mayor puntuación: %d" % int(r["best_score"]),
		"Partida más larga: %s" % UIKit.fmt_time(float(r["best_time"])),
		"—",
		"Partidas jugadas: %d    Derrotas: %d" % [int(s["runs"]), int(s["deaths"])],
		"Bajas totales: %d    Jefes derrotados: %d" % [int(s["kills"]), int(s["bosses"])],
		"Monedas ganadas: %d    Mejoras elegidas: %d" % [int(s["coins"]), int(s["cards"])],
		"Daño total: %d    Tiempo jugado: %s" % [int(s["damage"]), UIKit.fmt_time(float(s["playtime"]))],
	]
	for l in lines:
		v.add_child(UIKit.label(l, 24, UIKit.TEXT))
	var c := UIKit.accent_button("Cerrar", Vector2(240, 60), 24)
	c.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	c.pressed.connect(_toggle_records)
	v.add_child(c)
