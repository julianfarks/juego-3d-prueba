class_name CardSelect
extends Control
## Selección de mejoras: tres cartas (rareza, categoría, icono, valores reales, apilado y sinergias
## posibles). Tocar una carta la selecciona; "ELEGIR" confirma. Permite relanzar (cuesta monedas)
## o descartar a cambio de monedas.

signal picked(card: Dictionary)
signal closed
signal inventory_requested

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
var _inv_info: Label
var _inv_btn: Button
var _free_reroll := false     # tras liberar un espacio se relanza gratis una vez
var _inv_changed := false


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
	_inv_info = UIKit.label("", 22, UIKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	_inv_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_inv_info.custom_minimum_size = Vector2(1000, 0)
	_inv_info.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	root.add_child(_inv_info)
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
	_inv_btn = UIKit.button("INVENTARIO", Vector2(240, 62), 24)
	_inv_btn.pressed.connect(func(): inventory_requested.emit())
	btns.add_child(_inv_btn)


func _skip_value() -> int:
	return int(round((15 + int(GameState.arena_index * 2)) * (1.0 + GameState.build.s("skip_bonus"))))


func _reroll_cost() -> int:
	return int(round(20.0 * pow(1.5, _rerolls) * (1.0 - minf(GameState.build.s("reroll_cut"), 0.6))))


func open(depth: int, p_min_rarity := 0, p_source := "chest", count := 3) -> void:
	_depth = depth
	min_rarity = p_min_rarity
	source = p_source
	_title.text = "¡CONTENIDO DEL COFRE!" if source == "chest" else "ELIGE UNA MEJORA"
	_roll(count + int(GameState.build.s("chest_cards")))


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
	for i in _cards.size():
		var card: Dictionary = _cards[i]
		var d := UpgradeDB.get_def(card["id"])
		var rar: int = card["rarity"]
		var rcol: Color = UpgradeDB.RARITY_COLORS[rar]
		var ccol: Color = UpgradeDB.CATEGORY_COLORS.get(d["cat"], Color.WHITE)
		var pc := PanelContainer.new()
		var cw := 330.0 if _cards.size() <= 3 else 250.0
		pc.custom_minimum_size = Vector2(cw, 470)
		pc.add_theme_stylebox_override("panel", UIKit.style(UIKit.PANEL, rcol, 18, 5, 16))
		pc.pivot_offset = Vector2(cw * 0.5, 235)
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
		nm.custom_minimum_size = Vector2(cw - 40.0, 0)
		v.add_child(nm)
		v.add_child(UIKit.label(String(UpgradeDB.CATEGORY_NAMES[d["cat"]]), 18, ccol, HORIZONTAL_ALIGNMENT_CENTER))
		var ds := UIKit.label(UpgradeDB.describe(card["id"], rar), 19, UIKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
		ds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ds.custom_minimum_size = Vector2(cw - 40.0, 0)
		ds.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(ds)
		var have := b.count_of(card["id"])
		var cap := mini(int(d["max"]), UpgradeDB.MAX_LEVEL)
		var lvl_txt := "NUEVA · NIVEL 1" if have == 0 else "NIVEL %d → %d  (máx. %d)" % [have, have + 1, cap]
		v.add_child(UIKit.label(lvl_txt, 20, UIKit.GOOD if have == 0 else UIKit.ACCENT, HORIZONTAL_ALIGNMENT_CENTER))
		# qué cambia exactamente en tu build con esta elección
		for line in UpgradeDB.preview_lines(card["id"], rar, b):
			var pl := UIKit.label(String(line), 16, Color(0.75, 0.95, 0.8), HORIZONTAL_ALIGNMENT_CENTER)
			pl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			pl.custom_minimum_size = Vector2(cw - 40.0, 0)
			v.add_child(pl)
		var syn_name := UpgradeDB.synergy_hint(card["id"], b)
		if syn_name != "":
			var sl := UIKit.label("★ Sinergia: " + syn_name, 16, Color(1.0, 0.85, 0.3), HORIZONTAL_ALIGNMENT_CENTER)
			sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			sl.custom_minimum_size = Vector2(cw - 40.0, 0)
			v.add_child(sl)
		pc.gui_input.connect(_on_card_input.bind(i))
		pc.set_meta("pad_card", true)           # enfocable con mando: el foco selecciona la carta, confirmar la elige
		pc.focus_mode = Control.FOCUS_ALL if PadInput.pad_mode else Control.FOCUS_NONE
		pc.focus_entered.connect(func(): if PadInput.pad_mode and _selected != i: _select(i))
		_row.add_child(pc)
		_card_nodes.append(pc)
		# animación de entrada
		pc.modulate.a = 0.0
		pc.scale = Vector2(0.6, 0.6)
		var tw := create_tween().set_parallel(true)
		tw.tween_property(pc, "modulate:a", 1.0, 0.25).set_delay(0.08 * i)
		tw.tween_property(pc, "scale", Vector2.ONE, 0.3).set_delay(0.08 * i).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_card_input(event: InputEvent, i: int) -> void:
	if event.is_action_pressed("ui_accept") and not event.is_echo():
		if _selected == i:
			_on_confirm()
		else:
			_select(i)
		accept_event()
		return
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


## Llamado cuando se cierra el inventario: si se liberó un espacio, se relanzan las cartas gratis (una vez).
func on_inventory_closed(changed: bool) -> void:
	if changed:
		_inv_changed = true
		_free_reroll = true
		_roll(_cards.size())
	else:
		_update_buttons()


func _update_buttons() -> void:
	var b: Build = GameState.build
	if b.is_full():
		_inv_info.text = "Inventario lleno (%d/%d tipos): solo se ofrecen mejoras que ya tienes. Abre el INVENTARIO para vender o desechar y liberar un espacio." % [b.type_count(), Build.MAX_TYPES]
		_inv_info.add_theme_color_override("font_color", Color(1.0, 0.55, 0.4))
	else:
		_inv_info.text = "Inventario: %d/%d tipos de mejora" % [b.type_count(), Build.MAX_TYPES]
		_inv_info.add_theme_color_override("font_color", UIKit.TEXT_DIM)
	_confirm.disabled = _selected < 0
	_confirm.text = "ELEGIR" if _selected >= 0 else "Toca una carta"
	_reroll.text = "Relanzar (%d $)" % _reroll_cost() if not _free_reroll else "Relanzar (GRATIS)"
	_reroll.disabled = GameState.coins < _reroll_cost() and not _free_reroll


func _on_reroll() -> void:
	if _free_reroll:
		_free_reroll = false
	elif not GameState.spend_coins(_reroll_cost()):
		AudioManager.sfx("deny")
		return
	else:
		_rerolls += 1
	AudioManager.sfx("buy")
	_roll(_cards.size())


func _on_confirm() -> void:
	if _selected < 0:
		return
	var card: Dictionary = _cards[_selected]
	if not GameState.build.can_add(card["id"]):
		# selección imposible (inventario lleno o nivel máximo): se explica y no se pierde el cofre
		GameState.toast_msg(GameState.build.why_not(card["id"]), Color(1.0, 0.5, 0.4))
		AudioManager.sfx("deny")
		_selected = -1
		_rebuild()
		_update_buttons()
		return
	GameState.build.add(card["id"], card["rarity"])
	GameState.run_stats["cards"] += 1
	GameState.build_changed.emit()
	AudioManager.sfx("card")
	var d := UpgradeDB.get_def(card["id"])
	GameState.toast_msg("%s — NIVEL %d  (%s)" % [d["name"], GameState.build.count_of(card["id"]), UpgradeDB.RARITY_NAMES[card["rarity"]]], UpgradeDB.RARITY_COLORS[card["rarity"]])
	picked.emit(card)
	_close()


func _on_skip() -> void:
	GameState.add_coins(_skip_value(), false)
	AudioManager.sfx("coin")
	_close()


func _close() -> void:
	closed.emit()
	queue_free()
