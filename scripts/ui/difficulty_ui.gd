class_name DifficultyUI
extends Control
## Mesa del Juez: elige la dificultad de la próxima partida. Afecta de verdad a la vida, el daño y
## la cantidad de los enemigos, y a las recompensas (monedas y honorarios) vía Scaling.

signal closed
signal changed

var _list: VBoxContainer
var _msg: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UIKit.dim_background(0.82))
	var v := UIKit.center_box(self, Vector2(980, 0))
	v.add_theme_constant_override("separation", 8)
	v.add_child(UIKit.label("MESA DEL JUEZ", 40, UIKit.ACCENT))
	v.add_child(UIKit.label("Dificultad de la próxima partida (una partida guardada conserva la suya).", 20, UIKit.TEXT_DIM))
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	v.add_child(_list)
	_msg = UIKit.label("", 22, UIKit.GOOD, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_msg)
	var close := UIKit.accent_button("Listo", Vector2(280, 62), 28)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func():
		AudioManager.sfx("click")
		closed.emit()
		queue_free())
	v.add_child(close)
	_refresh()


func _refresh() -> void:
	for c in _list.get_children():
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
	pc.add_theme_stylebox_override("panel", UIKit.style(UIKit.PANEL_LIGHT, border, 14, 4 if selected else 2, 10))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	pc.add_child(h)
	var bar := ColorRect.new()
	bar.custom_minimum_size = Vector2(12, 72)
	bar.color = col if unlocked else Color(0.4, 0.4, 0.45)
	h.add_child(bar)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_theme_constant_override("separation", 2)
	h.add_child(tv)
	tv.add_child(UIKit.label(String(d["name"]) + ("   — ELEGIDA" if selected else ""), 28, col if unlocked else Color(0.6, 0.6, 0.65)))
	var desc := UIKit.label(String(d["desc"]), 19, UIKit.TEXT_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(640, 0)
	tv.add_child(desc)
	tv.add_child(UIKit.label("Vida enemiga ×%.2f · Daño enemigo ×%.2f · Cantidad ×%.2f · Monedas ×%.2f · Honorarios ×%.2f" % [
		float(d["hp_x"]), float(d["dmg_x"]), float(d["count_x"]), float(d["reward_x"]), float(d["fee_x"])], 18, Color(0.85, 0.95, 1.0)))
	if not unlocked:
		tv.add_child(UIKit.label("Requisito: llegar a la arena %d (tu mejor: %d)" % [int(d["req_arena"]), LoadoutDB.best_arena()], 18, Color(1.0, 0.8, 0.5)))
	var btn: Button
	if selected:
		btn = UIKit.button("ELEGIDA", Vector2(180, 60), 24)
		btn.disabled = true
	elif unlocked:
		btn = UIKit.accent_button("ELEGIR", Vector2(180, 60), 26)
		btn.pressed.connect(_choose.bind(id))
	else:
		btn = UIKit.button("BLOQUEADA", Vector2(180, 60), 22)
		btn.disabled = true
	h.add_child(btn)
	return pc


func _choose(id: String) -> void:
	if LoadoutDB.select_difficulty(id):
		AudioManager.sfx("buy")
		SaveSystem.save_now()
		_msg.text = "Dificultad elegida: %s" % String(LoadoutDB.DIFFICULTIES[id]["name"])
		changed.emit()
	_refresh()
