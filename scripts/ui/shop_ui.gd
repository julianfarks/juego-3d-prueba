class_name ShopUI
extends Control
## Tienda del despacho: curación, mejoras de atributo, de habilidad, especial y segunda oportunidad.
## Cada compra pide confirmación y valida el saldo. Los precios crecen con las compras de la partida
## y se reducen con la mejora "Tasación".

signal closed

var _offers: Array = []
var _list: VBoxContainer
var _coins_label: Label
var _confirm_box: Control
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
	sc.custom_minimum_size = Vector2(940, 400)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_list)
	var close := UIKit.accent_button("Salir de la tienda", Vector2(360, 66), 28)
	close.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func():
		AudioManager.sfx("click")
		closed.emit()
		queue_free())
	v.add_child(close)
	GameState.coins_changed.connect(func(_c): _refresh())


func open(depth: int) -> void:
	_generate(depth)
	_refresh()


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
			_offers.append({"type": "card", "card": c, "name": d["name"], "desc": UpgradeDB.describe(c["id"], c["rarity"]), "icon": d["icon"],
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
	for c in _list.get_children():
		c.queue_free()
	for i in _offers.size():
		_list.add_child(_row_for(i))


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
