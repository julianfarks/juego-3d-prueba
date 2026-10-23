class_name CardSelect
extends Control
## Selección de mejoras: tres cartas (rareza, categoría, icono, valores reales, apilado y sinergias
## posibles). Tocar una carta la selecciona; "ELEGIR" confirma. Permite relanzar (cuesta monedas)
## o descartar a cambio de monedas.

signal picked(card: Dictionary)
signal closed

var min_rarity := 0
var _cards: Array = []
var _selected := -1
var _card_nodes: Array = []
var _confirm: Button
var _reroll: Button
var _skip: Button
var _rerolls := 0
var _row: HBoxContainer
var _title: Label
var _depth := 0
var source := "chest"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UIKit.dim_background(0.78))
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", 14)
	add_child(root)
	_title = UIKit.title("ELIGE UNA MEJORA", 50)
	root.add_child(_title)
	_row = HBoxContainer.new()
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", 22)
	root.add_child(_row)
	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_theme_constant_override("separation", 18)
	root.add_child(btns)
	_reroll = UIKit.button("Relanzar", Vector2(260, 62), 24)
	_reroll.pressed.connect(_on_reroll)
	btns.add_child(_reroll)
	_confirm = UIKit.accent_button("ELEGIR", Vector2(300, 66), 30)
	_confirm.pressed.connect(_on_confirm)
	btns.add_child(_confirm)
	_skip = UIKit.button("Descartar (+%d $)" % _skip_value(), Vector2(260, 62), 24)
	_skip.pressed.connect(_on_skip)
	btns.add_child(_skip)


func _skip_value() -> int:
	return 15 + int(GameState.arena_index * 2)


func _reroll_cost() -> int:
	return int(round(20.0 * pow(1.5, _rerolls)))


func open(depth: int, p_min_rarity := 0, p_source := "chest", count := 3) -> void:
	_depth = depth
	min_rarity = p_min_rarity
	source = p_source
	_title.text = "¡CONTENIDO DEL COFRE!" if source == "chest" else "ELIGE UNA MEJORA"
	_roll(count)


func _roll(count: int) -> void:
	var b: Build = GameState.build
	_cards = UpgradeDB.roll_cards(count, b.s("luck"), _depth, b, GameState.rng, min_rarity)
	_selected = -1
	_rebuild()
	_update_buttons()
	AudioManager.sfx("card_flip")


func _rebuild() -> void:
	for c in _row.get_children():
		c.queue_free()
	_card_nodes.clear()
	var b: Build = GameState.build
	var synergies := UpgradeDB.synergies()
	for i in _cards.size():
		var card: Dictionary = _cards[i]
		var d := UpgradeDB.get_def(card["id"])
		var rar: int = card["rarity"]
		var rcol: Color = UpgradeDB.RARITY_COLORS[rar]
		var ccol: Color = UpgradeDB.CATEGORY_COLORS.get(d["cat"], Color.WHITE)
		var pc := PanelContainer.new()
		pc.custom_minimum_size = Vector2(330, 470)
		pc.add_theme_stylebox_override("panel", UIKit.style(UIKit.PANEL, rcol, 18, 5, 16))
		pc.pivot_offset = Vector2(165, 235)
		pc.mouse_filter = Control.MOUSE_FILTER_STOP
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 8)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pc.add_child(v)
		var rl := UIKit.label(String(UpgradeDB.RARITY_NAMES[rar]).to_upper(), 20, rcol, HORIZONTAL_ALIGNMENT_CENTER)
		v.add_child(rl)
		var ic := IconView.new().setup(String(d["icon"]), ccol, 110.0)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(ic)
		var nm := UIKit.label(String(d["name"]), 28, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER)
		nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nm.custom_minimum_size = Vector2(290, 0)
		v.add_child(nm)
		v.add_child(UIKit.label(String(UpgradeDB.CATEGORY_NAMES[d["cat"]]), 18, ccol, HORIZONTAL_ALIGNMENT_CENTER))
		var ds := UIKit.label(UpgradeDB.describe(card["id"], rar), 21, UIKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
		ds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ds.custom_minimum_size = Vector2(290, 0)
		ds.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(ds)
		var have := b.count_of(card["id"])
		var stack := UIKit.label("Nuevo" if have == 0 else "Apilado: x%d → x%d" % [have, have + 1], 18, UIKit.GOOD if have == 0 else UIKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
		v.add_child(stack)
		# ¿sinergia posible?
		var syn_name := _synergy_hint(card["id"], synergies, b)
		if syn_name != "":
			var sl := UIKit.label("★ Sinergia: " + syn_name, 17, Color(1.0, 0.85, 0.3), HORIZONTAL_ALIGNMENT_CENTER)
			sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			sl.custom_minimum_size = Vector2(290, 0)
			v.add_child(sl)
		pc.gui_input.connect(_on_card_input.bind(i))
		_row.add_child(pc)
		_card_nodes.append(pc)
		# animación de entrada
		pc.modulate.a = 0.0
		pc.scale = Vector2(0.6, 0.6)
		var tw := create_tween().set_parallel(true)
		tw.tween_property(pc, "modulate:a", 1.0, 0.25).set_delay(0.08 * i)
		tw.tween_property(pc, "scale", Vector2.ONE, 0.3).set_delay(0.08 * i).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _synergy_hint(id: String, synergies: Array, b: Build) -> String:
	var d := UpgradeDB.get_def(id)
	for s in synergies:
		if b.active_synergies.has(s["id"]):
			continue
		for key in (s["needs"] as Dictionary).keys():
			if (d["stats"] as Dictionary).has(key):
				return String(s["name"])
	return ""


func _on_card_input(event: InputEvent, i: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_select(i)
	elif event is InputEventScreenTouch and event.pressed:
		_select(i)


func _select(i: int) -> void:
	_selected = i
	AudioManager.sfx("click", -4.0)
	for k in _card_nodes.size():
		var pc: PanelContainer = _card_nodes[k]
		var rar: int = _cards[k]["rarity"]
		var rcol: Color = UpgradeDB.RARITY_COLORS[rar]
		var on := k == i
		pc.add_theme_stylebox_override("panel", UIKit.style(UIKit.PANEL_LIGHT if on else UIKit.PANEL, Color(1, 1, 1) if on else rcol, 18, 7 if on else 5, 16))
		var tw := create_tween()
		tw.tween_property(pc, "scale", Vector2(1.06, 1.06) if on else Vector2.ONE, 0.12)
	_update_buttons()


func _update_buttons() -> void:
	_confirm.disabled = _selected < 0
	_confirm.text = "ELEGIR" if _selected >= 0 else "Toca una carta"
	_reroll.text = "Relanzar (%d $)" % _reroll_cost()
	_reroll.disabled = GameState.coins < _reroll_cost()


func _on_reroll() -> void:
	if not GameState.spend_coins(_reroll_cost()):
		AudioManager.sfx("deny")
		return
	_rerolls += 1
	AudioManager.sfx("buy")
	_roll(_cards.size())


func _on_confirm() -> void:
	if _selected < 0:
		return
	var card: Dictionary = _cards[_selected]
	GameState.build.add(card["id"], card["rarity"])
	GameState.run_stats["cards"] += 1
	GameState.build_changed.emit()
	AudioManager.sfx("card")
	var d := UpgradeDB.get_def(card["id"])
	GameState.toast_msg("%s  (%s)" % [d["name"], UpgradeDB.RARITY_NAMES[card["rarity"]]], UpgradeDB.RARITY_COLORS[card["rarity"]])
	picked.emit(card)
	_close()


func _on_skip() -> void:
	GameState.add_coins(_skip_value(), false)
	AudioManager.sfx("coin")
	_close()


func _close() -> void:
	closed.emit()
	queue_free()
