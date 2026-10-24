class_name PauseMenu
extends Control
## Menú de pausa (el árbol está pausado; esta capa procesa siempre). Se adapta al contexto:
##   "run"   – durante una partida: inventario, build, guardar, ajustes, vídeo, audio, controles y volver al vestíbulo.
##   "lobby" – en el Vestíbulo del Bufete: continuar partida guardada, récords, despacho, ajustes, vídeo, audio y controles.
## Cada botón tiene nombre "Pause_<id>" para poder probarlos y navegarlos con el mando.

signal resume_pressed
signal settings_pressed(page: String)     # "game" | "video" | "audio"
signal controls_pressed
signal inventory_pressed
signal save_pressed
signal leave_save_pressed                  # guardar y volver al vestíbulo
signal abandon_pressed                     # abandonar la run (cuenta como derrota)
signal records_pressed
signal meta_pressed
signal continue_saved_pressed
signal quit_game_pressed

var context := "run"
var can_save := true
var _grid: GridContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UIKit.dim_background(0.7))
	var v := UIKit.center_box(self, Vector2(720, 0))
	v.add_theme_constant_override("separation", 12)
	var t := UIKit.title("PAUSA", 52)
	t.name = "PauseTitle"
	v.add_child(t)
	var sub := ""
	if context == "run":
		sub = "Arena %d · %d bajas · %s" % [GameState.arena_index + 1, GameState.kills, UIKit.fmt_time(GameState.run_time)]
	else:
		sub = "Vestíbulo del Bufete · Honorarios: %d" % int(SaveSystem.data["meta"]["fees"])
	var sl := UIKit.label(sub, 22, UIKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	sl.name = "PauseSub"
	v.add_child(sl)
	var r := UIKit.accent_button("CONTINUAR", Vector2(460, 70), 30)
	r.name = "Pause_resume"
	r.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	r.pressed.connect(func(): resume_pressed.emit())
	v.add_child(r)
	if context == "lobby" and SaveSystem.has_valid_run():
		var run: Dictionary = SaveSystem.get_run()
		var cs := UIKit.accent_button("CONTINUAR PARTIDA GUARDADA · Arena %d" % (int(run["arena_index"]) + 1), Vector2(680, 62), 24)
		cs.name = "Pause_continue_saved"
		cs.pressed.connect(func(): continue_saved_pressed.emit())
		v.add_child(cs)
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 10)
	_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(_grid)
	if context == "run":
		_add("inventory", "INVENTARIO", func(): inventory_pressed.emit())
		_add("build", "MI BUILD", _show_build)
		var sv := _add("save", "GUARDAR PARTIDA", func(): save_pressed.emit())
		sv.disabled = not can_save
	else:
		_add("records", "RÉCORDS", func(): records_pressed.emit())
		_add("meta", "EL DESPACHO", func(): meta_pressed.emit())
	_add("settings", "AJUSTES", func(): settings_pressed.emit("game"))
	_add("video", "VÍDEO Y GRÁFICOS", func(): settings_pressed.emit("video"))
	_add("audio", "AUDIO", func(): settings_pressed.emit("audio"))
	_add("controls", "CONTROLES", func(): controls_pressed.emit())
	if context == "run":
		_add("leave", "VOLVER AL VESTÍBULO", _confirm_leave)
	elif OS.has_feature("pc") and not OS.has_feature("android"):
		_add("quit_game", "SALIR DEL JUEGO", func(): quit_game_pressed.emit())


func _add(id: String, text: String, cb: Callable) -> Button:
	var b := UIKit.button(text, Vector2(334, 58), 22)
	b.name = "Pause_" + id
	b.pressed.connect(func():
		AudioManager.sfx("click")
		cb.call())
	_grid.add_child(b)
	return b


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
	for syn in UpgradeDB.synergies():
		if b.active_synergies.has(syn["id"]):
			lv.add_child(UIKit.label("★ %s: %s" % [syn["name"], syn["desc"]], 20, Color(1.0, 0.85, 0.3)))
	var c := UIKit.accent_button("Cerrar", Vector2(240, 60), 24)
	c.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	c.pressed.connect(box.queue_free)
	v.add_child(c)


## Confirmación para no abandonar una run por accidente: guardar y volver, abandonar (derrota) o cancelar.
func _confirm_leave() -> void:
	var box := Control.new()
	box.name = "LeaveBox"
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(box)
	box.add_child(UIKit.dim_background(0.6))
	var v := UIKit.center_box(box, Vector2(700, 300))
	v.add_theme_constant_override("separation", 12)
	v.add_child(UIKit.label("¿Volver al Vestíbulo?", 34, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER))
	var l := UIKit.label("Puedes guardar y retomar esta partida desde el portal CONTINUAR (si estás en combate se retoma al inicio de la arena). Abandonarla cuenta como derrota: se cobran los honorarios y se pierde la partida guardada.", 20, UIKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(640, 0)
	v.add_child(l)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	var save := UIKit.accent_button("GUARDAR Y VOLVER", Vector2(250, 62), 22)
	save.name = "Leave_save"
	save.disabled = not can_save
	save.pressed.connect(func(): leave_save_pressed.emit())
	row.add_child(save)
	var ab := UIKit.button("ABANDONAR RUN", Vector2(220, 62), 22)
	ab.name = "Leave_abandon"
	ab.pressed.connect(func(): abandon_pressed.emit())
	row.add_child(ab)
	var no := UIKit.button("Cancelar", Vector2(180, 62), 22)
	no.name = "Leave_cancel"
	no.pressed.connect(box.queue_free)
	row.add_child(no)
