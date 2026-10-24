class_name DevTools
extends Control
## Menú DESARROLLADOR (se desbloquea escribiendo el código en AJUSTES → CÓDIGOS). Panel adaptable a la pantalla con
## zona desplazable: dinero (monedas y honorarios), mejoras con rareza y nivel, partida y depuración.

signal closed
signal jump_to_arena(index: int)

const MAX_W := 900.0
var _panel: PanelContainer
var _scroll: ScrollContainer
var _coins_spin: SpinBox
var _fees_spin: SpinBox
var _arena_spin: SpinBox
var _status: Label
var _opt: OptionButton
var _rar: OptionButton
var _qty: SpinBox
var _ids: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UIKit.dim_background(0.7))
	_panel = UIKit.panel()
	_panel.name = "DevPanel"
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
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := UIKit.label("DESARROLLADOR", 34, Color(1.0, 0.5, 0.5))
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var close := UIKit.accent_button("Cerrar", Vector2(160, 56), 22)
	close.name = "DevClose"
	close.pressed.connect(func():
		SaveSystem.save_now()
		closed.emit()
		queue_free())
	head.add_child(close)
	_status = UIKit.label("", 20, UIKit.GOOD)
	_status.name = "DevStatus"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(200, 0)
	v.add_child(_status)
	_scroll = ScrollContainer.new()
	_scroll.name = "DevScroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_scroll.custom_minimum_size = Vector2(0, 110)
	v.add_child(_scroll)
	var g := VBoxContainer.new()
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_theme_constant_override("separation", 8)
	_scroll.add_child(g)
	_build_money(g)
	_build_items(g)
	_build_run(g)
	_build_debug(g)
	get_viewport().size_changed.connect(_layout)
	_layout()
	_update_status()


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


func _update_status() -> void:
	_status.text = "Monedas: %d   ·   Honorarios: %d" % [GameState.coins, int(SaveSystem.data["meta"]["fees"])]


func _section(parent: Control, text: String) -> void:
	parent.add_child(UIKit.label(text, 24, UIKit.ACCENT))


func _spin(min_v: float, max_v: float, val: float, step := 1.0) -> SpinBox:
	var sp := SpinBox.new()
	sp.min_value = min_v
	sp.max_value = max_v
	sp.step = step
	sp.value = val
	sp.custom_minimum_size = Vector2(190, 52)
	sp.get_line_edit().add_theme_font_size_override("font_size", 22)
	return sp


# ------------------------------------------------------------------ dinero
func _build_money(g: VBoxContainer) -> void:
	_section(g, "Dinero")
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 8)
	g.add_child(flow)
	for amt in [100, 1000, 10000, 100000]:
		var b := UIKit.button("+%d $" % amt, Vector2(150, 52), 20)
		b.name = "DevCoins_%d" % amt
		b.pressed.connect(func(): add_coins(amt))
		flow.add_child(b)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 10)
	g.add_child(row)
	_coins_spin = _spin(1, 99999999, 5000)
	_coins_spin.name = "DevCoinsAmount"
	row.add_child(_coins_spin)
	var add := UIKit.accent_button("Añadir monedas", Vector2(260, 52), 20)
	add.name = "DevCoinsAdd"
	add.pressed.connect(func(): add_coins(int(_coins_spin.value)))
	row.add_child(add)
	var row2 := HFlowContainer.new()
	row2.add_theme_constant_override("h_separation", 10)
	g.add_child(row2)
	_fees_spin = _spin(1, 99999999, 500)
	_fees_spin.name = "DevFeesAmount"
	row2.add_child(_fees_spin)
	var addf := UIKit.button("Añadir honorarios", Vector2(260, 52), 20)
	addf.name = "DevFeesAdd"
	addf.pressed.connect(func(): add_fees(int(_fees_spin.value)))
	row2.add_child(addf)


## Suma monedas a la partida en curso (o a la sala de práctica). No pasa por bonificaciones.
func add_coins(amount: int) -> void:
	if amount <= 0:
		return
	GameState.add_coins(amount, false)
	_update_status()
	GameState.toast_msg("+%d monedas (desarrollador)" % amount, UIKit.GOOD)


## Suma honorarios (la moneda permanente de El Despacho).
func add_fees(amount: int) -> void:
	if amount <= 0:
		return
	SaveSystem.data["meta"]["fees"] = int(SaveSystem.data["meta"]["fees"]) + amount
	SaveSystem.save_now()
	_update_status()
	GameState.toast_msg("+%d honorarios (desarrollador)" % amount, UIKit.GOOD)


# ------------------------------------------------------------------ mejoras
func _build_items(g: VBoxContainer) -> void:
	_section(g, "Agregar mejoras")
	_opt = OptionButton.new()
	_opt.name = "DevItem"
	_opt.custom_minimum_size = Vector2(300, 52)
	_opt.add_theme_font_size_override("font_size", 20)
	var defs: Array = UpgradeDB.all().duplicate()
	defs.sort_custom(func(a, b): return String(a["name"]) < String(b["name"]))
	for d in defs:
		_opt.add_item("%s%s" % [d["name"], " (tienda)" if d.get("shop_only", false) else ""])
		_ids.append(d["id"])
	_opt.fit_to_longest_item = false
	g.add_child(_opt)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 10)
	g.add_child(row)
	_rar = OptionButton.new()
	_rar.name = "DevRarity"
	_rar.custom_minimum_size = Vector2(190, 52)
	_rar.add_theme_font_size_override("font_size", 20)
	for n in UpgradeDB.RARITY_NAMES:
		_rar.add_item(String(n))
	row.add_child(_rar)
	_qty = _spin(1, 50, 1)
	_qty.name = "DevQty"
	row.add_child(_qty)
	var add := UIKit.accent_button("Agregar mejora", Vector2(260, 52), 20)
	add.name = "DevItemAdd"
	add.pressed.connect(func(): give_upgrade(String(_ids[_opt.selected]), _rar.selected, int(_qty.value)))
	row.add_child(add)


## Da una mejora (varios niveles). Respeta el límite de niveles y el de inventario; devuelve cuántos niveles se añadieron.
func give_upgrade(id: String, rarity: int, qty: int) -> int:
	var n := 0
	for _i in qty:
		if not GameState.build.can_add(id):
			break
		if GameState.build.add(id, clampi(rarity, 0, 3)):
			n += 1
	GameState.build_changed.emit()
	var nm := String(UpgradeDB.get_def(id).get("name", id))
	if n > 0:
		GameState.toast_msg("%s +%d nivel(es) (desarrollador)" % [nm, n], UIKit.GOOD)
	else:
		GameState.toast_msg(GameState.build.why_not(id), UIKit.BAD)
	return n


# ------------------------------------------------------------------ partida
func _build_run(g: VBoxContainer) -> void:
	_section(g, "Partida")
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 8)
	g.add_child(flow)
	_btn(flow, "Subir un nivel", func(): GameState.add_xp(float(GameState.xp_to_next())))
	_btn(flow, "Curar y recargar", func():
		var p = GameState.player
		if p != null:
			p.hp = p.max_hp
			p.skills.energy = p.skills.energy_max
			p.emit_hp())
	_btn(flow, "Matar enemigos", func():
		if GameState.arena != null:
			GameState.arena.kill_all())
	_btn(flow, "Completar arena", func():
		if GameState.arena != null:
			GameState.arena.force_complete())
	var r2 := HFlowContainer.new()
	r2.add_theme_constant_override("h_separation", 10)
	g.add_child(r2)
	r2.add_child(UIKit.label("Ir a la arena nº", 20))
	_arena_spin = _spin(1, 60, GameState.arena_index + 1)
	r2.add_child(_arena_spin)
	var go := UIKit.button("Ir", Vector2(120, 52), 22)
	go.pressed.connect(func():
		jump_to_arena.emit(int(_arena_spin.value) - 1)
		closed.emit()
		queue_free())
	r2.add_child(go)


func _build_debug(g: VBoxContainer) -> void:
	_section(g, "Depuración")
	_check(g, "Modo Dios (invulnerable)", Config.dev_god_mode, func(on): Config.dev_god_mode = on)
	_check(g, "Mostrar depuración (FPS, enemigos)", Config.dev_show_debug, func(on): Config.dev_show_debug = on)
	var row := HFlowContainer.new()
	g.add_child(row)
	row.add_child(UIKit.label("Dificultad ×", 20))
	var sl := HSlider.new()
	sl.min_value = 0.25
	sl.max_value = 4.0
	sl.step = 0.05
	sl.value = Scaling.dev_mult
	sl.custom_minimum_size = Vector2(240, 40)
	var vl := UIKit.label("x%.2f" % sl.value, 20)
	sl.value_changed.connect(func(x):
		Scaling.dev_mult = x
		vl.text = "x%.2f" % x)
	row.add_child(sl)
	row.add_child(vl)


func _check(parent: Control, text: String, val: bool, cb: Callable) -> void:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = val
	c.focus_mode = Control.FOCUS_NONE
	c.add_theme_font_size_override("font_size", 20)
	c.toggled.connect(cb)
	parent.add_child(c)


func _btn(parent: Control, text: String, cb: Callable) -> void:
	var b := UIKit.button(text, Vector2(220, 52), 20)
	b.pressed.connect(cb)
	parent.add_child(b)
