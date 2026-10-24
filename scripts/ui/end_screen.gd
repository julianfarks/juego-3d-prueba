class_name EndScreen
extends Control
## Pantalla de derrota / victoria con resumen de la partida. Diseño ADAPTABLE (v0.10.3):
##  · el panel se dimensiona a la pantalla visible (márgenes laterales/superior/inferior, ancho máx. 1040) y se recoloca si cambia;
##  · título, subtítulo, honorarios y botones son FIJOS (siempre visibles); estadísticas y lista de mejoras van en una zona
##    desplazable (con el dedo o el stick derecho) que ocupa el espacio sobrante;
##  · los botones están en un contenedor que pasa a otra fila si no caben (nunca se recortan).

signal retry_pressed
signal settings_pressed
signal continue_pressed
signal lobby_pressed
signal revive_pressed

const MAX_W := 1040.0
var _panel: PanelContainer
var _scroll: ScrollContainer
var _revive_btn: Button
var _revive_count: Label
var _revive_msg: Label


## revive: {} = sin opción de reanimar; {"left": n, "max": 2} = muestra «REVIVIR — VER ANUNCIO DE 30 S» y el contador.
func show_summary(sm: Dictionary, can_continue := false, revive := {}) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UIKit.dim_background(0.82))
	var victory: bool = sm.get("victory", false)
	_panel = UIKit.panel()
	_panel.name = "EndPanel"
	_panel.clip_contents = true
	add_child(_panel)
	var mc := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		mc.add_theme_constant_override(side, 18)
	for side in ["margin_top", "margin_bottom"]:
		mc.add_theme_constant_override(side, 14)
	_panel.add_child(mc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	mc.add_child(v)
	# --- cabecera fija ---
	var title := UIKit.title("¡CASO GANADO!" if victory else "CASO PERDIDO", 54)
	title.name = "EndTitle"
	title.add_theme_color_override("font_color", UIKit.GOOD if victory else UIKit.BAD)
	v.add_child(title)
	v.add_child(UIKit.label("Arena %d · Ciclo %d" % [sm["arena"], sm["cycle"]], 26, UIKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	# --- zona desplazable: estadísticas + mejoras ---
	_scroll = ScrollContainer.new()
	_scroll.name = "EndScroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(0, 110)
	v.add_child(_scroll)
	var sv := VBoxContainer.new()
	sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sv.add_theme_constant_override("separation", 10)
	_scroll.add_child(sv)
	var st: Dictionary = sm["stats"]
	var grid := GridContainer.new()
	grid.columns = 4                      # etiqueta | valor | etiqueta | valor: menos altura que una sola columna
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sv.add_child(grid)
	var rows := [
		["Puntuación", str(sm["score"])], ["Tiempo", UIKit.fmt_time(float(sm["time"]))],
		["Bajas", str(sm["kills"])], ["Jefes derrotados", str(st["bosses"])],
		["Daño infligido", str(int(float(st["damage_dealt"])))], ["Golpe más fuerte", str(int(float(st["highest_hit"])))],
		["Críticos", str(st["crits"])], ["Mejor racha", str(st["best_streak"])],
		["Monedas ganadas", str(st["coins_earned"])], ["Mejoras elegidas", str(st["cards"])],
	]
	for i in rows.size():
		var r: Array = rows[i]
		var lb := UIKit.label(String(r[0]), 23, UIKit.TEXT_DIM)
		lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(lb)
		var vl := UIKit.label(String(r[1]), 23, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_RIGHT)
		vl.name = "EndStat_%d" % i
		grid.add_child(vl)
	var bl: Array = sm["build"]
	if not bl.is_empty():
		UIKit.hsep(sv)
		sv.add_child(UIKit.label("MEJORAS DE LA BUILD (%d)" % bl.size(), 24, UIKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
		var items := GridContainer.new()
		items.name = "EndBuild"
		items.columns = 2
		items.add_theme_constant_override("h_separation", 24)
		items.add_theme_constant_override("v_separation", 4)
		items.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sv.add_child(items)
		for line in bl:
			var l := UIKit.label(String(line), 21, UIKit.TEXT)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.custom_minimum_size = Vector2(120, 0)
			items.add_child(l)
	# --- pie fijo: honorarios + botones ---
	UIKit.hsep(v)
	var fees := UIKit.label("Honorarios cobrados: +%d" % int(sm["fees"]), 30, Color(0.6, 1.0, 0.7), HORIZONTAL_ALIGNMENT_CENTER)
	fees.name = "EndFees"
	v.add_child(fees)
	if not revive.is_empty() and not victory:
		_revive_btn = UIKit.accent_button("REVIVIR — VER ANUNCIO DE 30 S", Vector2(520, 70), 26)
		_revive_btn.name = "End_revive"
		_revive_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_revive_btn.pressed.connect(func(): revive_pressed.emit())
		var rb := CenterContainer.new()
		rb.add_child(_revive_btn)
		v.add_child(rb)
		_revive_count = UIKit.label("", 24, UIKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
		_revive_count.name = "End_reviveCount"
		v.add_child(_revive_count)
		_revive_msg = UIKit.label("", 22, UIKit.BAD, HORIZONTAL_ALIGNMENT_CENTER)
		_revive_msg.name = "End_reviveMsg"
		_revive_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_revive_msg.custom_minimum_size = Vector2(300, 0)
		_revive_msg.visible = false
		v.add_child(_revive_msg)
		refresh_revive(int(revive["left"]), int(revive["max"]))
	var row := HFlowContainer.new()
	row.name = "EndButtons"
	row.alignment = FlowContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("h_separation", 14)
	row.add_theme_constant_override("v_separation", 10)
	v.add_child(row)
	if can_continue:
		var cont := UIKit.accent_button("CONTINUAR EN MODO INFINITO", Vector2(380, 64), 22)
		cont.name = "End_continue"
		cont.pressed.connect(func(): continue_pressed.emit())
		row.add_child(cont)
	else:
		var retry := UIKit.accent_button("Reintentar", Vector2(300, 64), 26)
		retry.name = "End_retry"
		retry.pressed.connect(func(): retry_pressed.emit())
		row.add_child(retry)
	# ya no existe un menú principal: el destino coherente tras una partida es el Vestíbulo del Bufete
	var lob := UIKit.button("RECLAMAR VICTORIA" if victory else "VOLVER AL VESTÍBULO", Vector2(300, 64), 22)
	lob.name = "End_lobby"
	lob.pressed.connect(func(): lobby_pressed.emit())
	row.add_child(lob)
	var sbtn := UIKit.button("AJUSTES", Vector2(200, 64), 22)
	sbtn.name = "End_settings"
	sbtn.pressed.connect(func(): settings_pressed.emit())
	row.add_child(sbtn)


## Actualiza botón y contador (n/máx). Sin reanimaciones: botón desactivado con «SIN REANIMACIONES DISPONIBLES».
func refresh_revive(left: int, maxn: int) -> void:
	if _revive_btn == null:
		return
	_revive_count.text = "Reanimaciones disponibles: %d/%d" % [left, maxn]
	_revive_btn.disabled = left <= 0
	_revive_btn.text = "REVIVIR — VER ANUNCIO DE 30 S" if left > 0 else "SIN REANIMACIONES DISPONIBLES"


func set_revive_busy(busy: bool) -> void:
	if _revive_btn != null:
		_revive_btn.disabled = busy or _revive_btn.text.begins_with("SIN ")


func set_revive_message(text: String, col := Color(1.0, 0.45, 0.4)) -> void:
	if _revive_msg == null:
		return
	_revive_msg.text = text
	_revive_msg.add_theme_color_override("font_color", col)
	_revive_msg.visible = text != ""
	_layout()


func _ready() -> void:
	get_viewport().size_changed.connect(_layout)
	_layout()


## Ajusta el panel al área visible: márgenes proporcionales, ancho máximo y centrado (también si cambia la ventana).
func _layout() -> void:
	if _panel == null:
		return
	var vs := get_viewport().get_visible_rect().size
	var mx := clampf(vs.x * 0.04, 16.0, 60.0)
	var my := clampf(vs.y * 0.04, 12.0, 40.0)
	var w := minf(vs.x - mx * 2.0, MAX_W)
	var h := vs.y - my * 2.0
	_panel.anchor_left = 0.0
	_panel.anchor_top = 0.0
	_panel.anchor_right = 0.0
	_panel.anchor_bottom = 0.0
	_panel.offset_left = (vs.x - w) * 0.5
	_panel.offset_top = my
	_panel.offset_right = _panel.offset_left + w
	_panel.offset_bottom = my + h
	_panel.custom_minimum_size = Vector2.ZERO


## El stick derecho del mando desplaza la lista (los botones fijos se manejan con el foco normal).
func _process(delta: float) -> void:
	if _scroll == null or not is_visible_in_tree():
		return
	var a := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if absf(a) > 0.25:
		_scroll.scroll_vertical += int(a * 900.0 * delta)
