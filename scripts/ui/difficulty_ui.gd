class_name DifficultyUI
extends Control
## Mesa del Juez: elige la dificultad de la próxima partida. Afecta de verdad a la vida, el daño y
## la cantidad de los enemigos, y a las recompensas (monedas y honorarios) vía Scaling.

signal closed
signal changed

const MAX_W := 1000.0
var _panel: PanelContainer
var _scroll: ScrollContainer
var _list: VBoxContainer
var _msg: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UIKit.dim_background(0.82))
	# Diseño ADAPTABLE (v0.10.4): el panel se ajusta al área visible; título y botón «Listo» son fijos y
	# las cuatro tarjetas van en una zona desplazable (dedo o stick derecho) que ocupa el espacio sobrante.
	_panel = UIKit.panel()
	_panel.name = "DiffPanel"
	_panel.clip_contents = true
	add_child(_panel)
	var mc := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		mc.add_theme_constant_override(side, 16)
	for side in ["margin_top", "margin_bottom"]:
		mc.add_theme_constant_override(side, 10)
	_panel.add_child(mc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	mc.add_child(v)
	var title := UIKit.label("MESA DEL JUEZ", 34, UIKit.ACCENT)
	title.name = "DiffTitle"
	v.add_child(title)
	var sub := UIKit.label("Dificultad de la próxima partida (una partida guardada conserva la suya).", 18, UIKit.TEXT_DIM)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size = Vector2(120, 0)
	v.add_child(sub)
	_scroll = ScrollContainer.new()
	_scroll.name = "DiffScroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_scroll.custom_minimum_size = Vector2(0, 110)
	v.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	_scroll.add_child(_list)
	_msg = UIKit.label("", 20, UIKit.GOOD, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_msg)
	var close := UIKit.accent_button("Listo", Vector2(260, 58), 26)
	close.name = "DiffClose"
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func():
		AudioManager.sfx("click")
		closed.emit()
		queue_free())
	v.add_child(close)
	get_viewport().size_changed.connect(_layout)
	_layout()
	_refresh()


## Ajusta el panel al área visible: márgenes proporcionales, ancho máximo y centrado.
func _layout() -> void:
	if _panel == null:
		return
	var vs := get_viewport().get_visible_rect().size
	var mx := clampf(vs.x * 0.04, 16.0, 60.0)
	var my := clampf(vs.y * 0.04, 10.0, 36.0)
	var w := minf(vs.x - mx * 2.0, MAX_W)
	_panel.anchor_left = 0.0
	_panel.anchor_top = 0.0
	_panel.anchor_right = 0.0
	_panel.anchor_bottom = 0.0
	_panel.offset_left = (vs.x - w) * 0.5
	_panel.offset_top = my
	_panel.offset_right = _panel.offset_left + w
	_panel.offset_bottom = vs.y - my
	_panel.custom_minimum_size = Vector2.ZERO


func _process(delta: float) -> void:
	if _scroll == null or not is_visible_in_tree():
		return
	var a := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if absf(a) > 0.25:
		_scroll.scroll_vertical += int(a * 900.0 * delta)


func _refresh() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var sel := LoadoutDB.selected_difficulty()
	for id in LoadoutDB.DIFF_ORDER:
		_list.add_child(_row(id, id == sel))


func _row(id: String, selected: bool) -> Control:
	var d: Dictionary = LoadoutDB.DIFFICULTIES[id]
	var unlocked := LoadoutDB.diff_unlocked(id)
	var col: Color = d["color"]
	var pc := PanelContainer.new()
	var border := col if selected else Color(1, 1, 1, 0.12)
	pc.add_theme_stylebox_override("panel", UIKit.style(UIKit.PANEL_LIGHT, border, 12, 3 if selected else 2, 8))
	pc.name = "Diff_" + id
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	pc.add_child(h)
	var bar := ColorRect.new()
	bar.custom_minimum_size = Vector2(10, 56)
	bar.color = col if unlocked else Color(0.4, 0.4, 0.45)
	h.add_child(bar)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_theme_constant_override("separation", 1)
	h.add_child(tv)
	tv.add_child(UIKit.label(String(d["name"]) + ("   — ELEGIDA" if selected else ""), 24, col if unlocked else Color(0.6, 0.6, 0.65)))
	var desc := UIKit.label(String(d["desc"]), 17, UIKit.TEXT_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(120, 0)
	tv.add_child(desc)
	var mult := UIKit.label("Vida enemiga ×%.2f · Daño enemigo ×%.2f · Cantidad ×%.2f · Monedas ×%.2f · Honorarios ×%.2f" % [
		float(d["hp_x"]), float(d["dmg_x"]), float(d["count_x"]), float(d["reward_x"]), float(d["fee_x"])], 16, Color(0.85, 0.95, 1.0))
	mult.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mult.custom_minimum_size = Vector2(120, 0)
	tv.add_child(mult)
	if not unlocked:
		tv.add_child(UIKit.label("Requisito: llegar a la arena %d (tu mejor: %d)" % [int(d["req_arena"]), LoadoutDB.best_arena()], 16, Color(1.0, 0.8, 0.5)))
	var btn: Button
	if selected:
		btn = UIKit.button("ELEGIDA", Vector2(150, 56), 22)
		btn.disabled = true
	elif unlocked:
		btn = UIKit.accent_button("ELEGIR", Vector2(150, 56), 24)
		btn.pressed.connect(_choose.bind(id))
	else:
		btn = UIKit.button("BLOQUEADA", Vector2(150, 56), 18)
		btn.disabled = true
	btn.name = "DiffBtn_" + id
	h.add_child(btn)
	return pc


func _choose(id: String) -> void:
	if LoadoutDB.select_difficulty(id):
		AudioManager.sfx("buy")
		SaveSystem.save_now()
		_msg.text = "Dificultad elegida: %s" % String(LoadoutDB.DIFFICULTIES[id]["name"])
		changed.emit()
	_refresh()
