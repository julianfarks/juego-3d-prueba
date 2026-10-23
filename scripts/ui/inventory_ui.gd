class_name InventoryUI
extends Control
## Inventario de mejoras de la run: 30 espacios (un espacio por TIPO de mejora; el nivel no ocupa más).
## Filtros por categoría, rareza y nombre; detalle con el efecto acumulado; VENDER / DESECHAR con confirmación
## y pestaña de sinergias (activas y por completar). Funciona al tacto: botones grandes, sin teclado obligatorio.

signal closed
signal changed          # se vendió o desechó una mejora

var _grid: GridContainer
var _detail: VBoxContainer
var _syn_list: VBoxContainer
var _body_items: Control
var _body_syn: Control
var _count_label: Label
var _coins_label: Label
var _cat_btn: Button
var _rar_btn: Button
var _search: LineEdit
var _tab_items: Button
var _tab_syn: Button
var _selected := ""
var _cat_filter := ""          # "" = todas
var _rar_filter := -1          # -1 = todas
var _confirm_box: Control = null
var _slots: Dictionary = {}    # id -> Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UIKit.dim_background(0.82))
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIKit.style(UIKit.PANEL, Color(1, 1, 1, 0.18), 16, 2, 12))
	add_child(panel)
	UIKit.place(panel, 0.0, 0.0, 20, 12, 1240, 696)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 20
	panel.offset_top = 12
	panel.offset_right = -20
	panel.offset_bottom = -12
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	panel.add_child(root)
	# --- cabecera ---
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	root.add_child(head)
	var t := UIKit.label("INVENTARIO DE MEJORAS", 34, UIKit.ACCENT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	_count_label = UIKit.label("", 26, Color(1, 1, 1))
	head.add_child(_count_label)
	_coins_label = UIKit.label("", 26, Color(1.0, 0.85, 0.3))
	head.add_child(_coins_label)
	var close := UIKit.accent_button("CERRAR", Vector2(170, 56), 24)
	close.pressed.connect(_close)
	head.add_child(close)
	# --- pestañas ---
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	root.add_child(tabs)
	_tab_items = UIKit.button("MEJORAS", Vector2(200, 50), 22)
	_tab_items.pressed.connect(func(): _show_tab(true))
	tabs.add_child(_tab_items)
	_tab_syn = UIKit.button("SINERGIAS", Vector2(200, 50), 22)
	_tab_syn.pressed.connect(func(): _show_tab(false))
	tabs.add_child(_tab_syn)
	# --- filtros ---
	var filt := HBoxContainer.new()
	filt.add_theme_constant_override("separation", 10)
	tabs.add_child(filt)
	_cat_btn = UIKit.button("Categoría: Todas", Vector2(280, 50), 20)
	_cat_btn.pressed.connect(_cycle_cat)
	filt.add_child(_cat_btn)
	_rar_btn = UIKit.button("Rareza: Todas", Vector2(210, 50), 20)
	_rar_btn.pressed.connect(_cycle_rar)
	filt.add_child(_rar_btn)
	_search = LineEdit.new()
	_search.placeholder_text = "Buscar por nombre…"
	_search.custom_minimum_size = Vector2(250, 50)
	_search.add_theme_font_size_override("font_size", 20)
	_search.text_changed.connect(func(_t): _refresh_grid())
	filt.add_child(_search)
	# --- cuerpo: mejoras ---
	_body_items = HBoxContainer.new()
	_body_items.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body_items.add_theme_constant_override("separation", 14)
	root.add_child(_body_items)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(700, 0)
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body_items.add_child(sc)
	_grid = GridContainer.new()
	_grid.columns = 6
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	sc.add_child(_grid)
	var dsc := ScrollContainer.new()
	dsc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dsc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body_items.add_child(dsc)
	_detail = VBoxContainer.new()
	_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail.add_theme_constant_override("separation", 6)
	dsc.add_child(_detail)
	# --- cuerpo: sinergias ---
	_body_syn = ScrollContainer.new()
	_body_syn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	(_body_syn as ScrollContainer).horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_body_syn)
	_syn_list = VBoxContainer.new()
	_syn_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_syn_list.add_theme_constant_override("separation", 8)
	_body_syn.add_child(_syn_list)
	_show_tab(true)
	_refresh_all()


func _close() -> void:
	closed.emit()
	queue_free()


func _show_tab(items: bool) -> void:
	_body_items.visible = items
	_body_syn.visible = not items
	_cat_btn.visible = items
	_rar_btn.visible = items
	_search.visible = items
	_tab_items.disabled = items
	_tab_syn.disabled = not items
	if not items:
		_refresh_synergies()


# ------------------------------------------------------------------ filtros
func _categories_in_build() -> Array:
	var cats: Array = [""]
	for id in GameState.build.counts.keys():
		var c: String = String(UpgradeDB.get_def(id)["cat"])
		if not cats.has(c):
			cats.append(c)
	return cats


func _cycle_cat() -> void:
	var cats := _categories_in_build()
	var i := cats.find(_cat_filter)
	_cat_filter = String(cats[(i + 1) % cats.size()])
	_cat_btn.text = "Categoría: " + ("Todas" if _cat_filter == "" else String(UpgradeDB.CATEGORY_NAMES[_cat_filter]))
	_refresh_grid()


func _cycle_rar() -> void:
	_rar_filter += 1
	if _rar_filter > 3:
		_rar_filter = -1
	_rar_btn.text = "Rareza: " + ("Todas" if _rar_filter < 0 else String(UpgradeDB.RARITY_NAMES[_rar_filter]))
	_refresh_grid()


func _matches(id: String) -> bool:
	var d := UpgradeDB.get_def(id)
	if _cat_filter != "" and String(d["cat"]) != _cat_filter:
		return false
	if _rar_filter >= 0 and GameState.build.rarity_of(id) != _rar_filter:
		return false
	var q := _search.text.strip_edges().to_lower()
	if q != "" and not String(d["name"]).to_lower().contains(q):
		return false
	return true


# ------------------------------------------------------------------ refrescos
func _refresh_all() -> void:
	var b: Build = GameState.build
	_count_label.text = "%d / %d tipos" % [b.type_count(), Build.MAX_TYPES]
	_count_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35) if b.is_full() else Color(1, 1, 1))
	_coins_label.text = "$ %d" % GameState.coins
	_refresh_grid()
	_refresh_detail()
	if _body_syn.visible:
		_refresh_synergies()


func _refresh_grid() -> void:
	for c in _grid.get_children():
		c.queue_free()
	_slots.clear()
	var b: Build = GameState.build
	var ids: Array = b.counts.keys()
	for i in Build.MAX_TYPES:
		if i < ids.size():
			var id := String(ids[i])
			var btn := _make_slot(id)
			btn.modulate.a = 1.0 if _matches(id) else 0.25
			_grid.add_child(btn)
			_slots[id] = btn
		else:
			var empty := Panel.new()
			empty.custom_minimum_size = Vector2(104, 92)
			empty.add_theme_stylebox_override("panel", UIKit.style(Color(1, 1, 1, 0.04), Color(1, 1, 1, 0.1), 10, 1, 4))
			var l := UIKit.label("libre", 16, Color(1, 1, 1, 0.3), HORIZONTAL_ALIGNMENT_CENTER)
			l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			empty.add_child(l)
			_grid.add_child(empty)


func _make_slot(id: String) -> Button:
	var d := UpgradeDB.get_def(id)
	var b: Build = GameState.build
	var rar := b.rarity_of(id)
	var rcol: Color = UpgradeDB.RARITY_COLORS[rar]
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(104, 92)
	btn.focus_mode = Control.FOCUS_NONE
	var sel := id == _selected
	btn.add_theme_stylebox_override("normal", UIKit.style(UIKit.PANEL_LIGHT if sel else UIKit.PANEL, Color(1, 1, 1) if sel else rcol, 10, 4 if sel else 3, 4))
	btn.add_theme_stylebox_override("hover", UIKit.style(UIKit.PANEL_LIGHT, rcol.lightened(0.3), 10, 3, 4))
	btn.add_theme_stylebox_override("pressed", UIKit.style(UIKit.PANEL_LIGHT, Color(1, 1, 1), 10, 4, 4))
	var ic := IconView.new().setup(String(d["icon"]), UpgradeDB.CATEGORY_COLORS.get(d["cat"], Color.WHITE), 50.0)
	ic.position = Vector2(27, 4)
	btn.add_child(ic)
	var lvl := UIKit.label("Nv %d" % b.count_of(id), 18, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER)
	lvl.position = Vector2(0, 54)
	lvl.size = Vector2(104, 22)
	lvl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(lvl)
	var cap := mini(int(d["max"]), UpgradeDB.MAX_LEVEL)
	if b.count_of(id) >= cap:
		var mx := UIKit.label("MÁX", 13, Color(1.0, 0.8, 0.2), HORIZONTAL_ALIGNMENT_CENTER)
		mx.position = Vector2(0, 74)
		mx.size = Vector2(104, 16)
		mx.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(mx)
	btn.pressed.connect(func():
		_selected = id
		AudioManager.sfx("click", -4.0)
		_refresh_grid()
		_refresh_detail())
	return btn


func _refresh_detail() -> void:
	for c in _detail.get_children():
		c.queue_free()
	var b: Build = GameState.build
	if _selected == "" or b.count_of(_selected) == 0:
		_selected = ""
		_detail.add_child(UIKit.label("Toca una mejora para ver su efecto acumulado, venderla o desecharla.", 20, UIKit.TEXT_DIM))
		_detail.add_child(UIKit.label("Cada TIPO de mejora ocupa un espacio; subir su nivel no ocupa más.", 18, UIKit.TEXT_DIM))
		if b.is_full():
			var full := UIKit.label("Inventario lleno: para aceptar una mejora NUEVA vende o desecha una.", 20, Color(1.0, 0.5, 0.4))
			full.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_detail.add_child(full)
		for l in _detail.get_children():
			if l is Label:
				(l as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		return
	var d := UpgradeDB.get_def(_selected)
	var rar := b.rarity_of(_selected)
	var cap := mini(int(d["max"]), UpgradeDB.MAX_LEVEL)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	_detail.add_child(head)
	head.add_child(IconView.new().setup(String(d["icon"]), UpgradeDB.CATEGORY_COLORS.get(d["cat"], Color.WHITE), 64.0))
	var hv := VBoxContainer.new()
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hv)
	var nm := UIKit.label("%s — NIVEL %d" % [d["name"], b.count_of(_selected)], 24, Color(1, 1, 1))
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hv.add_child(nm)
	hv.add_child(UIKit.label("%s · máx. %d · %s" % [UpgradeDB.RARITY_NAMES[rar], cap, UpgradeDB.CATEGORY_NAMES[d["cat"]]], 17, UpgradeDB.RARITY_COLORS[rar]))
	var ds := UIKit.label(UpgradeDB.describe(_selected, rar), 19, UIKit.TEXT)
	ds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(ds)
	_detail.add_child(UIKit.label("EFECTO ACUMULADO", 18, UIKit.ACCENT))
	for line in effect_lines(_selected):
		var el := UIKit.label("• " + String(line), 18, Color(0.75, 0.95, 0.8))
		el.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail.add_child(el)
	if d.has("mile"):
		var next := (b.count_of(_selected) / UpgradeDB.MILESTONE_EVERY + 1) * UpgradeDB.MILESTONE_EVERY
		var mt := UIKit.label("Hito cada %d niveles (%d alcanzados): %s%s" % [UpgradeDB.MILESTONE_EVERY, UpgradeDB.milestones_at(b.count_of(_selected)), UpgradeDB.mile_text(d),
			(" · próximo: nivel %d" % next) if next <= cap else ""], 16, Color(1.0, 0.85, 0.3))
		mt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail.add_child(mt)
	var tg: Array = d.get("tags", [])
	if not tg.is_empty():
		var tl := UIKit.label("Etiquetas: " + ", ".join(tg), 16, UIKit.TEXT_DIM)
		tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail.add_child(tl)
	var in_syn: Array = []
	for syn in UpgradeDB.synergies():
		if b.active_synergies.has(syn["id"]) and _syn_uses(syn, _selected):
			in_syn.append(syn["name"])
	if not in_syn.is_empty():
		var sl := UIKit.label("★ Sinergias activas con ella: " + ", ".join(in_syn), 17, Color(1.0, 0.85, 0.3))
		sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail.add_child(sl)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_detail.add_child(row)
	var sell := UIKit.accent_button("VENDER  +$%d" % b.sell_value(_selected), Vector2(250, 60), 22)
	sell.pressed.connect(func(): _ask(true))
	row.add_child(sell)
	var disc := UIKit.button("DESECHAR", Vector2(170, 60), 22)
	disc.pressed.connect(func(): _ask(false))
	row.add_child(disc)


func _syn_uses(syn: Dictionary, id: String) -> bool:
	var d := UpgradeDB.get_def(id)
	if (syn.get("lv", {}) as Dictionary).has(id):
		return true
	for k in (syn["needs"] as Dictionary).keys():
		if (d["stats"] as Dictionary).has(k):
			return true
	for tk in (syn.get("tags", {}) as Dictionary).keys():
		if (d.get("tags", []) as Array).has(tk):
			return true
	return false


## Líneas legibles del efecto acumulado de una mejora (todos sus niveles, hitos y amplificación).
static func effect_lines(id: String) -> Array:
	var b: Build = GameState.build
	var d := UpgradeDB.get_def(id)
	var eff := b.effects_of(id)
	var out: Array = []
	for k in eff.keys():
		var v := float(eff[k])
		var f := String((d["fmt"] as Dictionary).get(k, "n"))
		if String(k).ends_with("_x"):
			out.append("%s ×%.2f" % [UpgradeDB.stat_label(String(k)), v])
		elif (d["fmt"] as Dictionary).has(k) or true:
			out.append("%s %s" % [UpgradeDB.stat_label(String(k)), UpgradeDB.fmt_value("q" if f == "p" and absf(v) < 0.1 else f, v)])
	return out


# ------------------------------------------------------------------ vender / desechar
func _ask(sell: bool) -> void:
	if _selected == "" or _confirm_box != null:
		return
	var b: Build = GameState.build
	var d := UpgradeDB.get_def(_selected)
	var value := b.sell_value(_selected) if sell else 0
	var lost := b.synergies_lost_if_removed(_selected)
	var msg := ""
	if sell:
		msg = "¿Vender %s (nivel %d) por $%d?" % [d["name"], b.count_of(_selected), value]
	else:
		msg = "¿Desechar %s (nivel %d)? No recibirás monedas." % [d["name"], b.count_of(_selected)]
	msg += "\nSe elimina TODO su efecto y libera un espacio. No se puede deshacer."
	if b.count_of(_selected) >= 10:
		msg += "\n⚠ Es una mejora de nivel alto."
	if not lost.is_empty():
		var names: Array = []
		for sid in lost:
			for syn in UpgradeDB.synergies():
				if syn["id"] == sid:
					names.append(syn["name"])
		msg += "\n⚠ Desactivará la sinergia: " + ", ".join(names)
	_confirm_box = Control.new()
	_confirm_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_confirm_box)
	_confirm_box.add_child(UIKit.dim_background(0.6))
	var v := UIKit.center_box(_confirm_box, Vector2(640, 0))
	v.add_theme_constant_override("separation", 14)
	var ml := UIKit.label(msg, 22, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER)
	ml.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ml.custom_minimum_size = Vector2(600, 0)
	v.add_child(ml)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	v.add_child(row)
	var ok := UIKit.accent_button("CONFIRMAR", Vector2(250, 64), 24)
	ok.pressed.connect(func(): _do_remove(sell))
	row.add_child(ok)
	var cancel := UIKit.button("CANCELAR", Vector2(230, 64), 24)
	cancel.pressed.connect(_cancel_confirm)
	row.add_child(cancel)


func _cancel_confirm() -> void:
	if _confirm_box != null:
		_confirm_box.queue_free()
		_confirm_box = null


## Elimina la mejora de verdad (Build.remove), cobra el valor mostrado y refresca todo.
func _do_remove(sell: bool) -> void:
	var id := _selected
	var d := UpgradeDB.get_def(id)
	var res := GameState.build.remove(id, sell)
	_cancel_confirm()
	if not bool(res["ok"]):
		return
	if sell and int(res["value"]) > 0:
		GameState.add_coins(int(res["value"]), false)
		AudioManager.sfx("coin")
		GameState.toast_msg("Vendida: %s (+$%d)" % [d["name"], int(res["value"])], Color(1.0, 0.85, 0.3))
	else:
		AudioManager.sfx("deny", -4.0)
		GameState.toast_msg("Desechada: %s" % d["name"], Color(0.8, 0.8, 0.9))
	_selected = ""
	GameState.build_changed.emit()
	changed.emit()
	_refresh_all()


# ------------------------------------------------------------------ sinergias
func _refresh_synergies() -> void:
	for c in _syn_list.get_children():
		c.queue_free()
	var b: Build = GameState.build
	var active: Array = []
	var pending: Array = []
	for syn in UpgradeDB.synergies():
		var pr := b.synergy_progress(syn)
		var n_ok := 0
		for p in pr["parts"]:
			if p["ok"]:
				n_ok += 1
		var entry := {"syn": syn, "pr": pr, "ratio": float(n_ok) / maxf(1.0, float((pr["parts"] as Array).size()))}
		if b.active_synergies.has(syn["id"]):
			active.append(entry)
		else:
			pending.append(entry)
	pending.sort_custom(func(a, c): return a["ratio"] > c["ratio"])
	_syn_list.add_child(UIKit.label("ACTIVAS (%d)" % active.size(), 24, Color(1.0, 0.85, 0.3)))
	if active.is_empty():
		_syn_list.add_child(UIKit.label("Todavía ninguna. Combina mejoras con etiquetas o niveles afines.", 19, UIKit.TEXT_DIM))
	for e in active:
		_syn_list.add_child(_syn_card(e, true))
	_syn_list.add_child(UIKit.label("POR COMPLETAR (%d)" % pending.size(), 24, UIKit.ACCENT))
	for e in pending:
		_syn_list.add_child(_syn_card(e, false))


func _syn_card(e: Dictionary, on: bool) -> Control:
	var syn: Dictionary = e["syn"]
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UIKit.style(Color(0.35, 0.28, 0.05, 0.5) if on else UIKit.PANEL, Color(1.0, 0.8, 0.2) if on else Color(1, 1, 1, 0.12), 10, 2, 8))
	var v := VBoxContainer.new()
	pc.add_child(v)
	v.add_child(UIKit.label("%s %s" % ["★" if on else "☆", syn["name"]], 22, Color(1.0, 0.85, 0.3) if on else Color(1, 1, 1)))
	var ds := UIKit.label(String(syn["desc"]), 18, UIKit.TEXT)
	ds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ds.custom_minimum_size = Vector2(1000, 0)
	v.add_child(ds)
	var parts: Array = []
	for p in e["pr"]["parts"]:
		var mark := "✔" if p["ok"] else "✘"
		if p.get("stat", false):
			parts.append("%s %s %.2f/%.2f" % [mark, p["label"], float(p["cur"]), float(p["need"])])
		else:
			parts.append("%s %s %d/%d" % [mark, p["label"], int(p["cur"]), int(p["need"])])
	var pl := UIKit.label("   ".join(parts), 17, Color(0.7, 0.95, 0.75) if on else UIKit.TEXT_DIM)
	pl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(pl)
	return pc
