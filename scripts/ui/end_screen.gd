class_name EndScreen
extends Control
## Pantalla FINAL de la partida (supervivencia infinita): solo aparece al morir sin reanimaciones o al abandonar.
## No existe victoria ni «continuar»: la partida solo termina cuando el jugador cae. Muestra únicamente datos medidos de
## verdad (GameState.run_stats + récords guardados). Diseño ADAPTABLE (pantalla vertical de Android incluida):
##  · cabecera y botones FIJOS; las estadísticas van en una zona desplazable (dedo con TouchScroll, rueda o stick derecho);
##  · el panel se dimensiona a la pantalla visible y se recoloca si cambia; las filas hacen salto de línea (nada se recorta);
##  · los botones están en un contenedor que pasa a otra fila si no caben.

signal retry_pressed          # NUEVA PARTIDA
signal settings_pressed
signal lobby_pressed          # VOLVER A LA SALA CENTRAL
signal revive_pressed

const MAX_W := 1040.0
var _panel: PanelContainer
var _scroll: ScrollContainer
var _touch: TouchScroll
var _revive_btn: Button
var _revive_count: Label
var _revive_msg: Label


## revive: {} = sin opción de reanimar; {"left": n, "max": 2} = muestra «REVIVIR — VER ANUNCIO DE 30 S» y el contador.
func show_summary(sm: Dictionary, revive := {}) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UIKit.dim_background(0.86))
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
	var title := UIKit.title("CASO PERDIDO", 52)
	title.name = "EndTitle"
	title.add_theme_color_override("font_color", UIKit.BAD)
	v.add_child(title)
	var sub := UIKit.label("Sobreviviste hasta la Arena %d · Ciclo %d" % [int(sm["arena"]), int(sm["cycle"])], 26, UIKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	sub.name = "EndSub"
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size = Vector2(260, 0)
	v.add_child(sub)
	# --- zona desplazable ---
	_scroll = ScrollContainer.new()
	_scroll.name = "EndScroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(0, 110)
	v.add_child(_scroll)
	_touch = TouchScroll.new()
	add_child(_touch)
	_touch.setup(_scroll, _scroll)
	var sv := VBoxContainer.new()
	sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sv.add_theme_constant_override("separation", 12)
	_scroll.add_child(sv)
	var st: Dictionary = sm["stats"]
	var nw: Dictionary = sm["new"]
	var best: Dictionary = sm["best"]
	var srcs: Array = sm.get("sources", [])
	var top := "—"
	if not srcs.is_empty():
		var tot := 0.0
		for e in srcs:
			tot += float(e[1])
		top = "%s (%d%%)" % [String(srcs[0][0]), int(round(100.0 * float(srcs[0][1]) / maxf(tot, 1.0)))]
	var unl: Array = sm.get("unlocked", [])
	_section(sv, "RESUMEN DE LA PARTIDA", [
		["time", "Tiempo de supervivencia", UIKit.fmt_time(float(sm["time"])), _rec(nw["time"], UIKit.fmt_time(float(best["time"])))],
		["arena", "Arena alcanzada", str(int(sm["arena"])), _rec(nw["arena"], str(int(best["arena"])))],
		["waves", "Oleadas completadas", Feedback.fmt(float(st["waves"])), ""],
		["bosses", "Jefes derrotados", Feedback.fmt(float(st["bosses"])), ""],
		["kills", "Enemigos eliminados", Feedback.fmt(float(sm["kills"])), _rec(nw["kills"], Feedback.fmt(float(best["kills"])))],
		["score", "Puntuación", Feedback.fmt(float(sm["score"])), _rec(nw["score"], Feedback.fmt(float(best["score"])))],
	])
	_section(sv, "COMBATE", [
		["dmg", "Daño infligido", Feedback.fmt(float(st["damage_dealt"])), ""],
		["dmg_boss", "Daño a jefes y capataces", Feedback.fmt(float(st["damage_boss"])), ""],
		["taken", "Daño recibido", Feedback.fmt(float(st["damage_taken"])), ""],
		["hits", "Impactos a enemigos", Feedback.fmt(float(st["hits"])), ""],
		["hurt", "Veces que te hirieron", Feedback.fmt(float(st["hurt"])), ""],
		["highest", "Golpe más fuerte", Feedback.fmt(float(st["highest_hit"])), ""],
		["crits", "Golpes críticos", Feedback.fmt(float(st["crits"])), ""],
		["top_src", "Mayor fuente de daño", top, ""],
	])
	_section(sv, "ECONOMÍA", [
		["earned", "Monedas obtenidas", Feedback.fmt(float(st["coins_earned"])), ""],
		["spent", "Gastadas en la tienda", Feedback.fmt(float(st["coins_spent"])), ""],
		["purchases", "Compras realizadas", Feedback.fmt(float(st["purchases"])), ""],
		["coins_kill", "Cobradas de enemigos", Feedback.fmt(float(st["coins_kill"])), ""],
		["coins_boss", "Cobradas de jefes", Feedback.fmt(float(st["coins_boss"])), ""],
		["coins_left", "Monedas al morir", Feedback.fmt(float(sm["coins_left"])), ""],
		["fees", "Honorarios cobrados", "+" + Feedback.fmt(float(sm["fees"])), ""],
	])
	_section(sv, "PROGRESIÓN Y RECOMPENSAS", [
		["upgrades", "Mejoras obtenidas", Feedback.fmt(float(sm["upgrades"])), ""],
		["synergies", "Sinergias activas", Feedback.fmt(float(sm["synergies"])), ""],
		["chests", "Cofres abiertos", Feedback.fmt(float(st["chests"])), ""],
		["boss_rewards", "Botines de jefe elegidos", Feedback.fmt(float(st["boss_rewards"])), ""],
		["revives", "Reanimaciones usadas", Feedback.fmt(float(sm["revives"])), ""],
		["unlocked", "Desbloqueos nuevos disponibles", "Ninguno" if unl.is_empty() else ", ".join(PackedStringArray(unl)), ""],
	])
	var bl: Array = sm["build"]
	if not bl.is_empty():
		var items := VBoxContainer.new()
		items.name = "EndBuild"
		items.add_theme_constant_override("separation", 4)
		for line in bl:
			var l := UIKit.label(String(line), 21, UIKit.TEXT)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size = Vector2(200, 0)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			items.add_child(l)
		_card(sv, "MEJORAS DE LA BUILD (%d)" % bl.size(), items)
	# --- pie fijo: botones ---
	UIKit.hsep(v)
	var fees := UIKit.label("Honorarios cobrados: +%d" % int(sm["fees"]), 28, Color(0.6, 1.0, 0.7), HORIZONTAL_ALIGNMENT_CENTER)
	fees.name = "EndFees"
	v.add_child(fees)
	if not revive.is_empty():
		_revive_btn = UIKit.accent_button("REVIVIR — VER ANUNCIO DE 30 S", Vector2(440, 66), 24)
		_revive_btn.name = "End_revive"
		_revive_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		_revive_btn.pressed.connect(func(): revive_pressed.emit())
		var rb := CenterContainer.new()
		rb.add_child(_revive_btn)
		v.add_child(rb)
		_revive_count = UIKit.label("", 22, UIKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
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
	var retry := UIKit.accent_button("NUEVA PARTIDA", Vector2(300, 64), 26)
	retry.name = "End_retry"
	retry.pressed.connect(func(): retry_pressed.emit())
	row.add_child(retry)
	var lob := UIKit.button("VOLVER A LA SALA CENTRAL", Vector2(360, 64), 22)
	lob.name = "End_lobby"
	lob.pressed.connect(func(): lobby_pressed.emit())
	row.add_child(lob)
	var sbtn := UIKit.button("AJUSTES", Vector2(200, 64), 22)
	sbtn.name = "End_settings"
	sbtn.pressed.connect(func(): settings_pressed.emit())
	row.add_child(sbtn)


## «★ NUEVO RÉCORD» si esta partida batió el récord guardado; si no, el récord personal vigente.
func _rec(is_new: bool, best_txt: String) -> String:
	return "★ NUEVO RÉCORD" if is_new else "Récord: " + best_txt


## Tarjeta con título (estilo del juego) alrededor de 'body'.
func _card(parent: Control, title_text: String, body: Control) -> void:
	var pc := PanelContainer.new()
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.add_theme_stylebox_override("panel", UIKit.style(Color(0.15, 0.17, 0.25, 0.95), Color(0.75, 0.52, 0.08, 0.8), 12, 2, 12))
	parent.add_child(pc)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 6)
	pc.add_child(cv)
	cv.add_child(UIKit.label(title_text, 24, UIKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
	cv.add_child(body)


## Sección de filas [clave, etiqueta, valor, nota]. Cada valor es un Label «EndStat_<clave>» (las pruebas lo leen).
func _section(parent: Control, title_text: String, rows: Array) -> void:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 16)
	g.add_theme_constant_override("v_separation", 5)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for r in rows:
		var lb := UIKit.label(String(r[1]), 22, UIKit.TEXT_DIM)
		lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lb.custom_minimum_size = Vector2(150, 0)
		lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(lb)
		var box := VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_theme_constant_override("separation", 0)
		var vl := UIKit.label(String(r[2]), 23, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_RIGHT)
		vl.name = "EndStat_" + String(r[0])
		vl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vl.custom_minimum_size = Vector2(120, 0)
		vl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(vl)
		if String(r[3]) != "":
			var note := UIKit.label(String(r[3]), 18, UIKit.ACCENT if String(r[3]).begins_with("★") else UIKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
			note.name = "EndNote_" + String(r[0])
			note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			box.add_child(note)
		g.add_child(box)
	_card(parent, title_text, g)


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
