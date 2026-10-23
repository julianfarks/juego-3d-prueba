class_name EquipStationUI
extends Control
## Estación de equipamiento de la Armería: muestra los objetos de un slot con nombre, descripción,
## estadísticas, estado (equipado / desbloqueado / bloqueado) y permite equipar o desbloquear.

signal closed
signal changed

var slot := "weapon"
var _fees: Label
var _row: HBoxContainer
var _msg: Label


func _init(p_slot: String = "weapon") -> void:
	slot = p_slot


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UIKit.dim_background(0.82))
	var v := UIKit.center_box(self, Vector2(1000, 0))
	v.add_theme_constant_override("separation", 10)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := UIKit.label(String(LoadoutDB.SLOT_NAMES[slot]).to_upper(), 38, UIKit.ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	_fees = UIKit.label("", 28, Color(0.6, 1.0, 0.7), HORIZONTAL_ALIGNMENT_RIGHT)
	head.add_child(_fees)
	v.add_child(UIKit.label("Lo que equipes aquí se usa de verdad en la próxima partida y en la zona de práctica.", 20, UIKit.TEXT_DIM))
	_row = HBoxContainer.new()
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", 14)
	v.add_child(_row)
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
	_fees.text = "Honorarios: %d" % int(SaveSystem.data["meta"]["fees"])
	for c in _row.get_children():
		c.queue_free()
	var equipped: String = String(LoadoutDB.equipped()[slot])
	for id in LoadoutDB.items_for(slot):
		_row.add_child(_card(id, id == equipped))


func _card(id: String, is_equipped: bool) -> Control:
	var d: Dictionary = LoadoutDB.item(id)
	var unlocked := LoadoutDB.is_unlocked(id)
	var col: Color = d["color"]
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(310, 0)
	var border := UIKit.GOOD if is_equipped else (Color(1, 1, 1, 0.14) if unlocked else Color(1, 0.4, 0.4, 0.4))
	pc.add_theme_stylebox_override("panel", UIKit.style(UIKit.PANEL_LIGHT, border, 14, 4 if is_equipped else 2, 12))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	pc.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(14, 56)
	swatch.color = col
	top.add_child(swatch)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(tv)
	tv.add_child(UIKit.label(String(d["name"]), 26, Color(1, 1, 1)))
	var status := "EQUIPADO" if is_equipped else ("DESBLOQUEADO" if unlocked else "BLOQUEADO")
	tv.add_child(UIKit.label(status, 18, UIKit.GOOD if unlocked else UIKit.BAD))
	var desc := UIKit.label(String(d["desc"]), 19, UIKit.TEXT_DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(280, 76)
	v.add_child(desc)
	for line in LoadoutDB.stat_lines(id):
		v.add_child(UIKit.label("• " + String(line), 20, Color(0.85, 0.95, 1.0)))
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sp)
	if not unlocked:
		var rq := UIKit.label("Requisitos: " + LoadoutDB.requirement_text(id), 18, Color(1.0, 0.8, 0.5))
		rq.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rq.custom_minimum_size = Vector2(280, 0)
		v.add_child(rq)
	var btn: Button
	if is_equipped:
		btn = UIKit.button("EQUIPADO", Vector2(280, 58), 24)
		btn.disabled = true
	elif unlocked:
		btn = UIKit.accent_button("EQUIPAR", Vector2(280, 58), 26)
		btn.pressed.connect(_equip.bind(id))
	else:
		btn = UIKit.accent_button("DESBLOQUEAR  %d" % int(d["cost"]), Vector2(280, 58), 24)
		btn.disabled = not LoadoutDB.can_unlock(id)
		btn.pressed.connect(_unlock.bind(id))
	v.add_child(btn)
	return pc


func _equip(id: String) -> void:
	if LoadoutDB.equip(slot, id):
		AudioManager.sfx("buy")
		_msg.text = "Equipado: %s" % String(LoadoutDB.item(id)["name"])
		_msg.add_theme_color_override("font_color", UIKit.GOOD)
		SaveSystem.save_now()
		changed.emit()
		_refresh()


func _unlock(id: String) -> void:
	if LoadoutDB.unlock(id):
		AudioManager.sfx("buy")
		_msg.text = "Desbloqueado: %s" % String(LoadoutDB.item(id)["name"])
		_msg.add_theme_color_override("font_color", UIKit.GOOD)
		changed.emit()
	else:
		AudioManager.sfx("deny")
		_msg.text = "No cumples los requisitos."
		_msg.add_theme_color_override("font_color", UIKit.BAD)
	_refresh()
