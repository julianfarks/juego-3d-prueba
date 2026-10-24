class_name EndScreen
extends Control
## Pantalla de derrota / victoria con resumen de la partida.

signal retry_pressed
signal settings_pressed
signal continue_pressed
signal lobby_pressed


func show_summary(sm: Dictionary, can_continue := false) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UIKit.dim_background(0.82))
	var victory: bool = sm.get("victory", false)
	var v := UIKit.center_box(self, Vector2(860, 0))
	v.add_theme_constant_override("separation", 8)
	var title := UIKit.title("¡CASO GANADO!" if victory else "CASO PERDIDO", 62)
	title.add_theme_color_override("font_color", UIKit.GOOD if victory else UIKit.BAD)
	v.add_child(title)
	v.add_child(UIKit.label("Arena %d · Ciclo %d" % [sm["arena"], sm["cycle"]], 28, UIKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	var st: Dictionary = sm["stats"]
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(grid)
	var rows := [
		["Puntuación", str(sm["score"])], ["Tiempo", UIKit.fmt_time(float(sm["time"]))],
		["Bajas", str(sm["kills"])], ["Jefes derrotados", str(st["bosses"])],
		["Daño infligido", str(int(float(st["damage_dealt"])))], ["Golpe más fuerte", str(int(float(st["highest_hit"])))],
		["Críticos", str(st["crits"])], ["Mejor racha", str(st["best_streak"])],
		["Monedas ganadas", str(st["coins_earned"])], ["Mejoras elegidas", str(st["cards"])],
	]
	for r in rows:
		grid.add_child(UIKit.label(String(r[0]), 24, UIKit.TEXT_DIM))
		grid.add_child(UIKit.label(String(r[1]), 24, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_RIGHT))
	UIKit.hsep(v)
	v.add_child(UIKit.label("Honorarios cobrados: +%d" % int(sm["fees"]), 32, Color(0.6, 1.0, 0.7), HORIZONTAL_ALIGNMENT_CENTER))
	var bl: Array = sm["build"]
	if not bl.is_empty():
		var txt := ", ".join(bl.slice(0, 8))
		if bl.size() > 8:
			txt += " … (+%d)" % (bl.size() - 8)
		var l := UIKit.label("Build: " + txt, 18, UIKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(800, 0)
		v.add_child(l)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	if can_continue:
		var cont := UIKit.accent_button("Seguir (ciclo más difícil)", Vector2(360, 70), 24)
		cont.pressed.connect(func(): continue_pressed.emit())
		row.add_child(cont)
	else:
		var retry := UIKit.accent_button("Reintentar", Vector2(300, 70), 28)
		retry.pressed.connect(func(): retry_pressed.emit())
		row.add_child(retry)
	var lob := UIKit.button("VOLVER AL VESTÍBULO", Vector2(300, 70), 22)
	lob.name = "End_lobby"
	lob.pressed.connect(func(): lobby_pressed.emit())
	row.add_child(lob)
	var sbtn := UIKit.button("AJUSTES", Vector2(200, 70), 22)
	sbtn.name = "End_settings"
	sbtn.pressed.connect(func(): settings_pressed.emit())
	row.add_child(sbtn)
