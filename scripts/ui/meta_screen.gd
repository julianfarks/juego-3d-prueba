class_name MetaScreen
extends Control
## "El Despacho": mejoras permanentes que se compran con honorarios ganados al terminar partidas.

signal closed

var _list: VBoxContainer
var _fees: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UIKit.dim_background(0.88))
	var v := UIKit.center_box(self, Vector2(900, 600))
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := UIKit.label("EL DESPACHO", 42, UIKit.ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	_fees = UIKit.label("", 30, Color(0.6, 1.0, 0.7))
	head.add_child(_fees)
	v.add_child(UIKit.label("Mejoras permanentes: se conservan entre partidas.", 20, UIKit.TEXT_DIM))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(860, 420)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_list)
	var close := UIKit.accent_button("Volver", Vector2(280, 62), 26)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func():
		closed.emit()
		queue_free())
	v.add_child(close)
	_refresh()


func _cost(def: Dictionary, level: int) -> int:
	return int(round(float(def["cost"]) * pow(float(def["growth"]), level)))


func _refresh() -> void:
	_fees.text = "Honorarios: %d" % int(SaveSystem.data["meta"]["fees"])
	for c in _list.get_children():
		c.queue_free()
	var perm: Dictionary = SaveSystem.data["meta"]["perm"]
	var icons := {"perm_hp": "heart", "perm_dmg": "gavel", "perm_coins": "coin", "perm_luck": "clover", "perm_speed": "shoe", "perm_regen": "cross"}
	for def in Config.PERM_UPGRADES:
		var lvl := int(perm.get(def["id"], 0))
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", UIKit.style(UIKit.PANEL_LIGHT, Color(1, 1, 1, 0.12), 14, 2, 10))
		var h := HBoxContainer.new()
		pc.add_child(h)
		h.add_child(IconView.new().setup(icons.get(def["id"], "star"), Color(0.5, 0.8, 1.0), 76.0))
		var tv := VBoxContainer.new()
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.add_theme_constant_override("separation", 2)
		h.add_child(tv)
		tv.add_child(UIKit.label("%s   Nv. %d / %d" % [def["name"], lvl, def["max"]], 26))
		tv.add_child(UIKit.label(String(def["desc"]), 20, UIKit.TEXT_DIM))
		var btn: Button
		if lvl >= int(def["max"]):
			btn = UIKit.button("MÁXIMO", Vector2(200, 62), 24)
			btn.disabled = true
		else:
			var cost := _cost(def, lvl)
			btn = UIKit.accent_button("%d" % cost, Vector2(200, 62), 28)
			btn.disabled = int(SaveSystem.data["meta"]["fees"]) < cost
			btn.pressed.connect(_buy.bind(def))
		h.add_child(btn)
		_list.add_child(pc)


func _buy(def: Dictionary) -> void:
	var perm: Dictionary = SaveSystem.data["meta"]["perm"]
	var lvl := int(perm.get(def["id"], 0))
	if lvl >= int(def["max"]):
		return
	var cost := _cost(def, lvl)
	if int(SaveSystem.data["meta"]["fees"]) < cost:
		AudioManager.sfx("deny")
		return
	SaveSystem.data["meta"]["fees"] = int(SaveSystem.data["meta"]["fees"]) - cost
	perm[def["id"]] = lvl + 1
	SaveSystem.mark_dirty()
	SaveSystem.save_now()
	AudioManager.sfx("buy")
	_refresh()
