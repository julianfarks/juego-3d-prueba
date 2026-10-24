class_name ShopUI
extends Control
## Tienda del despacho: curación, mejoras de atributo, de habilidad, especial y segunda oportunidad.
## Cada compra pide confirmación y valida el saldo. Los precios crecen con las compras de la partida
## y se reducen con la mejora "Tasación".

signal closed

## Estado de la VISITA (lo crea Main al empezar cada arena y se comparte con cada apertura de la interfaz):
## ofertas actuales, relanzamientos usados y profundidad. Cerrar y volver a abrir la tienda en la misma visita
## NO regenera las ofertas ni reinicia el límite de relanzamientos.
var visit: Dictionary = {}
const MAX_REROLLS := 3
const DRAG_DEADZONE := 14.0           # píxeles antes de considerar que el gesto es un desplazamiento y no una pulsación
var _offers: Array = []
var _list: VBoxContainer
var _coins_label: Label
var _confirm_box: Control
var _sc: ScrollContainer
var _reroll_btn: Button
var _drag_active := false           # hay un gesto de dedo/ratón empezado dentro de la lista
var _drag_moved := false            # ese gesto ya es un desplazamiento (se ignora para comprar)
var _drag_start := Vector2.ZERO
var _drag_last := Vector2.ZERO
var _drag_vel := 0.0
var _inertia := 0.0
static var purchases := 0         # compras de la partida actual (reinicia Main al empezar)

const ATTR_CATS := ["dmg", "speed", "atk", "crit", "hp", "shield"]
const SKILL_CATS := ["aoe", "elem", "combo", "streak"]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UIKit.dim_background(0.8))
	var v := UIKit.center_box(self, Vector2(980, 560))
	v.add_theme_constant_override("separation", 10)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := UIKit.label("TIENDA DEL DESPACHO", 40, UIKit.ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	_coins_label = UIKit.label("", 32, Color(1.0, 0.85, 0.3), HORIZONTAL_ALIGNMENT_RIGHT)
	head.add_child(_coins_label)
	var sc := ScrollContainer.new()
	sc.name = "ShopScroll"
	_sc = sc
	sc.custom_minimum_size = Vector2(940, 400)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# el desplazamiento táctil lo gestiona _input (funciona también sobre las cartas y los botones)
	v.add_child(sc)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	sc.add_child(_list)
	# cabecera y pie fijos: el dinero y el título arriba; relanzar y salir siempre a la vista abajo
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_CENTER
	foot.add_theme_constant_override("separation", 16)
	v.add_child(foot)
	_reroll_btn = UIKit.button("RELANZAR OFERTAS", Vector2(520, 66), 24)
	_reroll_btn.name = "Shop_reroll"
	_reroll_btn.pressed.connect(_ask_reroll)
	foot.add_child(_reroll_btn)
	var close := UIKit.accent_button("Salir de la tienda", Vector2(360, 66), 28)
	close.name = "Shop_close"
	close.pressed.connect(func():
		AudioManager.sfx("click")
		closed.emit()
		queue_free())
	foot.add_child(close)
	GameState.coins_changed.connect(func(_c): _refresh())


func open(depth: int) -> void:
	if visit.is_empty():
		visit["rerolls"] = 0
		visit["depth"] = depth
	if not visit.has("offers"):
		_generate(depth)
		visit["offers"] = _offers
	else:
		_offers = visit["offers"]
	_refresh()


# ------------------------------------------------------------------ relanzar ofertas (máx. 3 por visita)
func rerolls_used() -> int:
	return int(visit.get("rerolls", 0))


func reroll_cost() -> int:
	## Mismo cálculo que la economía existente de relanzamientos (20 $ ×1,5 por uso, reducido por «Relanzamiento Barato»).
	return int(round(20.0 * pow(1.5, rerolls_used()) * (1.0 - minf(GameState.build.s("reroll_cut"), 0.6))))


func _reroll_label() -> String:
	if rerolls_used() >= MAX_REROLLS:
		return "RELANZAMIENTOS AGOTADOS — %d/%d" % [MAX_REROLLS, MAX_REROLLS]
	return "RELANZAR (%d $) — %d/%d" % [reroll_cost(), rerolls_used() + 1, MAX_REROLLS]


func _ask_reroll() -> void:
	if rerolls_used() >= MAX_REROLLS:
		AudioManager.sfx("deny")
		GameState.toast_msg("Ya usaste los %d relanzamientos de esta visita" % MAX_REROLLS, UIKit.BAD)
		return
	var cost := reroll_cost()
	if GameState.coins < cost:
		AudioManager.sfx("deny")
		GameState.toast_msg("No tienes suficientes monedas (relanzar cuesta %d $)" % cost, UIKit.BAD)
		return
	AudioManager.sfx("click")
	if _confirm_box != null:
		_confirm_box.queue_free()
	_confirm_box = Control.new()
	_confirm_box.name = "RerollConfirm"
	_confirm_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm_box.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_confirm_box)
	_confirm_box.add_child(UIKit.dim_background(0.6))
	var v := UIKit.center_box(_confirm_box, Vector2(640, 260))
	v.add_child(UIKit.label("¿Relanzar las ofertas?", 32, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UIKit.label("Precio: %d $   ·   Saldo: %d $   ·   Uso %d/%d" % [cost, GameState.coins, rerolls_used() + 1, MAX_REROLLS], 24, UIKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	var no := UIKit.button("Cancelar", Vector2(240, 64), 26)
	no.name = "Reroll_no"
	no.pressed.connect(func(): _confirm_box.queue_free())
	row.add_child(no)
	var yes := UIKit.accent_button("Confirmar", Vector2(260, 64), 28)
	yes.name = "Reroll_yes"
	yes.pressed.connect(func():
		_confirm_box.queue_free()
		do_reroll())
	row.add_child(yes)


## Cobra y sustituye las ofertas. Devuelve true si se relanzó. Valida límite y saldo (nunca cobra si falla).
func do_reroll() -> bool:
	if rerolls_used() >= MAX_REROLLS:
		return false
	var cost := reroll_cost()
	if not GameState.spend_coins(cost):
		AudioManager.sfx("deny")
		return false
	visit["rerolls"] = rerolls_used() + 1
	# lo ya agotado de una sola vez (Segunda Opinión) no vuelve a aparecer como disponible
	var sold_ids := {}
	for o in _offers:
		if o["type"] == "revive" and o["sold"]:
			sold_ids["revive"] = true
	_generate(int(visit.get("depth", GameState.arena_index)))
	for o in _offers:
		if sold_ids.has(o["type"]):
			o["sold"] = true
	visit["offers"] = _offers
	AudioManager.sfx("buy")
	GameState.toast_msg("Ofertas renovadas (-%d $)" % cost, UIKit.GOOD)
	_refresh()
	_sc.scroll_vertical = 0
	return true


func price_of(base: float) -> int:
	var p := base * pow(float(Config.ECONOMY["price_growth"]), purchases)
	p *= 1.0 - minf(GameState.build.s("shop_discount"), 0.5)
	return maxi(1, int(round(p)))


func _generate(depth: int) -> void:
	var b: Build = GameState.build
	_offers.clear()
	_offers.append({"type": "heal", "name": "Atención médica", "desc": "Recupera el 45% de tu salud máxima.", "icon": "heart", "color": Color(0.95, 0.35, 0.5), "base": float(Config.ECONOMY["heal_price"]), "sold": false, "repeat": true})
	var pool := UpgradeDB.roll_cards(40, b.s("luck") + 0.1, depth, b, GameState.rng, 0)
	var picked := {}
	var take := func(cats: Array, n: int, min_r: int, base: float, label: String) -> void:
		var got := 0
		for c in pool:
			if got >= n:
				break
			if picked.has(c["id"]):
				continue
			var d := UpgradeDB.get_def(c["id"])
			if not cats.has(d["cat"]) or int(c["rarity"]) < min_r:
				continue
			picked[c["id"]] = true
			got += 1
			_offers.append({"type": "card", "card": c, "name": "%s · NIVEL %d → %d" % [d["name"], b.count_of(c["id"]), b.count_of(c["id"]) + 1], "desc": UpgradeDB.describe(c["id"], c["rarity"]), "icon": d["icon"],
				"color": UpgradeDB.CATEGORY_COLORS.get(d["cat"], Color.WHITE), "base": base * (1.0 + 0.7 * int(c["rarity"])), "sold": false, "label": label})
	take.call(ATTR_CATS, 2, 0, float(Config.ECONOMY["attr_price"]), "Atributo")
	take.call(SKILL_CATS, 1, 0, float(Config.ECONOMY["skill_price"]), "Habilidad")
	take.call(UpgradeDB.CATEGORY_NAMES.keys(), 1, 2, float(Config.ECONOMY["special_price"]) * 0.8, "Especial")
	_offers.append({"type": "revive", "name": "Segunda Opinión", "desc": "Si caes, reapareces con 40% de salud (una vez).", "icon": "cross", "color": Color(1.0, 0.9, 0.4), "base": float(Config.ECONOMY["special_price"]) * 1.3, "sold": false, "repeat": false})
	_offers.append({"type": "energy", "name": "Café del despacho", "desc": "Recarga toda tu energía y reinicia enfriamientos.", "icon": "cell", "color": Color(1.0, 0.78, 0.2), "base": float(Config.ECONOMY["heal_price"]) * 0.6, "sold": false, "repeat": true})


func _refresh() -> void:
	if _list == null:
		return
	_coins_label.text = "$ %d" % GameState.coins
	var keep := _sc.scroll_vertical
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	for i in _offers.size():
		_list.add_child(_row_for(i))
	var pad := Control.new()                 # margen final: la última oferta nunca queda pegada al borde
	pad.custom_minimum_size = Vector2(0, 14)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_list.add_child(pad)
	_sc.set_deferred("scroll_vertical", keep)
	_reroll_btn.text = _reroll_label()
	_reroll_btn.disabled = rerolls_used() >= MAX_REROLLS or GameState.coins < reroll_cost()


func _row_for(i: int) -> Control:
	var o: Dictionary = _offers[i]
	var price := price_of(float(o["base"]))
	var pc := PanelContainer.new()
	var rcol := Color(1, 1, 1, 0.12)
	if o["type"] == "card":
		rcol = UpgradeDB.RARITY_COLORS[int(o["card"]["rarity"])]
	pc.add_theme_stylebox_override("panel", UIKit.style(UIKit.PANEL_LIGHT, rcol, 14, 3, 10))
	var h := HBoxContainer.new()
	pc.add_child(h)
	h.add_child(IconView.new().setup(String(o["icon"]), o["color"], 84.0))
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_theme_constant_override("separation", 2)
	h.add_child(tv)
	var title := String(o["name"])
	if o["type"] == "card":
		title += "  [%s · %s]" % [UpgradeDB.RARITY_NAMES[int(o["card"]["rarity"])], o.get("label", "")]
	tv.add_child(UIKit.label(title, 26, Color(1, 1, 1)))
	var d := UIKit.label(String(o["desc"]), 20, UIKit.TEXT_DIM)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(540, 0)
	tv.add_child(d)
	var btn: Button
	if o["sold"]:
		btn = UIKit.button("VENDIDO", Vector2(200, 64), 24)
		btn.disabled = true
	else:
		btn = UIKit.accent_button("$ %d" % price, Vector2(200, 64), 28)
		btn.disabled = GameState.coins < price
		btn.pressed.connect(_ask_buy.bind(i))
	h.add_child(btn)
	return pc


func _ask_buy(i: int) -> void:
	var o: Dictionary = _offers[i]
	var price := price_of(float(o["base"]))
	if GameState.coins < price:
		AudioManager.sfx("deny")
		GameState.toast_msg("No tienes suficientes monedas", UIKit.BAD)
		return
	AudioManager.sfx("click")
	if _confirm_box != null:
		_confirm_box.queue_free()
	_confirm_box = Control.new()
	_confirm_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm_box.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_confirm_box)
	_confirm_box.add_child(UIKit.dim_background(0.6))
	var v := UIKit.center_box(_confirm_box, Vector2(640, 260))
	v.add_child(UIKit.label("¿Comprar «%s»?" % o["name"], 32, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UIKit.label("Precio: %d $   ·   Saldo: %d $" % [price, GameState.coins], 24, UIKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	var no := UIKit.button("Cancelar", Vector2(240, 64), 26)
	no.pressed.connect(func(): _confirm_box.queue_free())
	row.add_child(no)
	var yes := UIKit.accent_button("Confirmar", Vector2(260, 64), 28)
	yes.pressed.connect(func():
		_confirm_box.queue_free()
		_buy(i))
	row.add_child(yes)


func _buy(i: int) -> void:
	var o: Dictionary = _offers[i]
	if o["sold"]:
		return
	var price := price_of(float(o["base"]))
	if o["type"] == "card" and not GameState.build.can_add(o["card"]["id"]):
		GameState.toast_msg(GameState.build.why_not(o["card"]["id"]), Color(1.0, 0.5, 0.4))
		AudioManager.sfx("deny")
		return
	if not GameState.spend_coins(price):
		AudioManager.sfx("deny")
		return
	var pl = GameState.player
	match o["type"]:
		"heal":
			if pl != null:
				pl.heal(pl.max_hp * 0.45)
		"energy":
			if pl != null:
				pl.skills.energy = pl.skills.energy_max
				pl.skills.reduce_cooldowns(99.0)
				GameState.energy_changed.emit(pl.skills.energy, pl.skills.energy_max)
		"revive":
			if pl != null:
				pl.revives_left += 1
		"card":
			GameState.build.add(o["card"]["id"], o["card"]["rarity"])
			GameState.run_stats["cards"] += 1
			GameState.build_changed.emit()
	purchases += 1
	if not bool(o.get("repeat", false)):
		o["sold"] = true
	AudioManager.sfx("buy")
	GameState.toast_msg("Compraste: %s" % o["name"], UIKit.GOOD)
	_refresh()


# ------------------------------------------------------------------ desplazamiento táctil de la lista
## Arrastrar con el dedo (o el ratón) sobre CUALQUIER parte de la lista la desplaza, con inercia. Un gesto que pasa
## el umbral es un desplazamiento: se anula la pulsación del botón sobre el que empezó y se ignora su suelta, así que
## deslizar nunca compra. Comprar exige una pulsación corta sobre «$ N» y, además, la confirmación.
func _in_list(pos: Vector2) -> bool:
	return _sc != null and _sc.get_global_rect().has_point(pos) and (_confirm_box == null or not is_instance_valid(_confirm_box))


func _input(event: InputEvent) -> void:
	if _sc == null or not is_visible_in_tree():
		return
	var pos := Vector2.ZERO
	var kind := ""        # "down" | "move" | "up"
	var rel := 0.0
	if event is InputEventScreenTouch:
		pos = event.position
		kind = "down" if event.pressed else "up"
	elif event is InputEventScreenDrag:
		pos = event.position
		kind = "move"
		rel = event.relative.y
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			if _drag_moved:
				get_viewport().set_input_as_handled()      # eco ratón del gesto táctil que ya es un desplazamiento
				if not event.pressed:
					_end_drag()
			return
		pos = event.position
		kind = "down" if event.pressed else "up"
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		if event.device == InputEvent.DEVICE_ID_EMULATION:
			if _drag_moved:
				get_viewport().set_input_as_handled()
			return
		pos = event.position
		kind = "move"
		rel = event.relative.y
	else:
		return
	match kind:
		"down":
			if _in_list(pos):
				_drag_active = true
				_drag_moved = false
				_drag_start = pos
				_drag_last = pos
				_drag_vel = 0.0
				_inertia = 0.0
		"move":
			if not _drag_active:
				return
			if not _drag_moved:
				if absf(pos.y - _drag_start.y) < DRAG_DEADZONE:
					if event is InputEventScreenDrag:
						get_viewport().set_input_as_handled()      # el ScrollContainer no debe desplazarse por su cuenta
					return
				_drag_moved = true
				_cancel_press_at(_drag_start)
			_sc.scroll_vertical -= int(round(pos.y - _drag_last.y))
			_drag_vel = lerpf(_drag_vel, pos.y - _drag_last.y, 0.5)
			_drag_last = pos
			get_viewport().set_input_as_handled()
		"up":
			if _drag_active and _drag_moved:
				get_viewport().set_input_as_handled()
				_inertia = _drag_vel * 60.0          # px/s
			_end_drag()


## Anula la pulsación a medias del botón que hay bajo el punto donde empezó el gesto (alternar «disabled» reinicia
## su estado de pulsación sin cambiar su estado final), para que deslizar no lo «dispare» ni lo deje hundido.
func _cancel_press_at(pos: Vector2) -> void:
	for b in _list.find_children("*", "Button", true, false):
		var bt := b as Button
		if bt.get_global_rect().has_point(pos):
			var was := bt.disabled
			bt.disabled = true
			bt.disabled = was


func _end_drag() -> void:
	_drag_active = false
	_drag_moved = false


func _process(delta: float) -> void:
	if absf(_inertia) > 20.0 and not _drag_active and _sc != null:
		var before := _sc.scroll_vertical
		_sc.scroll_vertical = before - int(round(_inertia * delta))
		_inertia *= exp(-delta * 4.5)
		if _sc.scroll_vertical == before:
			_inertia = 0.0
	else:
		_inertia = 0.0
