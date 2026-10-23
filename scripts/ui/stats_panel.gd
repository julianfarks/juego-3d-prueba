class_name StatsPanel
extends Control
## Panel de estadísticas y récords persistentes (Archivo de Casos de la sala y botón "Récords" del menú).

signal closed


static func fmt_long_time(t: float) -> String:
	var s := int(t)
	var h := s / 3600
	var m := (s % 3600) / 60
	if h > 0:
		return "%d h %02d min" % [h, m]
	return "%d min %02d s" % [m, s % 60]


## Líneas [etiqueta, valor] con los datos guardados.
static func rows() -> Array:
	var r: Dictionary = SaveSystem.data["records"]
	var s: Dictionary = SaveSystem.data["stats"]
	return [
		["Runs completadas", str(int(s["wins"]))],
		["Partidas jugadas", str(int(s["runs"]))],
		["Derrotas", str(int(s["deaths"]))],
		["Enemigos derrotados", str(int(s["kills"]))],
		["Jefes derrotados", str(int(s["bosses"]))],
		["Mejor progreso", "Arena %d · Ciclo %d" % [int(r["best_arena"]), int(r["best_cycle"])]],
		["Tiempo total jugado", fmt_long_time(float(s["playtime"]))],
		["Mayor puntuación", str(int(r["best_score"]))],
		["Más bajas en una partida", str(int(r["best_kills"]))],
		["Partida más larga", UIKit.fmt_time(float(r["best_time"]))],
		["Monedas ganadas", str(int(s["coins"]))],
		["Mejoras elegidas", str(int(s["cards"]))],
		["Daño total", str(int(s["damage"]))],
	]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UIKit.dim_background(0.8))
	var v := UIKit.center_box(self, Vector2(760, 0))
	v.add_theme_constant_override("separation", 6)
	v.add_child(UIKit.label("ARCHIVO DE CASOS", 40, UIKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UIKit.label("Estadísticas y récords (se conservan al cerrar el juego)", 20, UIKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 4)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(grid)
	for row in rows():
		grid.add_child(UIKit.label(String(row[0]), 24, UIKit.TEXT_DIM))
		var val := UIKit.label(String(row[1]), 24, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_RIGHT)
		val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(val)
	var c := UIKit.accent_button("Cerrar", Vector2(240, 60), 26)
	c.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	c.pressed.connect(func():
		AudioManager.sfx("click")
		closed.emit()
		queue_free())
	v.add_child(c)
