class_name DevTools
extends Control
## Herramientas de desarrollo (solo si el modo desarrollador está desbloqueado en Ajustes).
## Permiten probar balance y progresión sin jugar la partida entera.

signal closed
signal jump_to_arena(index: int)

var _arena_spin: SpinBox


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UIKit.dim_background(0.6))
	var v := UIKit.center_box(self, Vector2(820, 560))
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := UIKit.label("DESARROLLO", 38, Color(1.0, 0.5, 0.5))
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var close := UIKit.accent_button("Cerrar", Vector2(180, 56), 22)
	close.pressed.connect(func():
		closed.emit()
		queue_free())
	head.add_child(close)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(780, 450)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var g := VBoxContainer.new()
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(g)
	_check(g, "Modo Dios (invulnerable)", Config.dev_god_mode, func(on): Config.dev_god_mode = on)
	_check(g, "Mostrar depuración (FPS, enemigos, draw calls)", Config.dev_show_debug, func(on): Config.dev_show_debug = on)
	var row := HBoxContainer.new()
	g.add_child(row)
	row.add_child(UIKit.label("Multiplicador de dificultad", 22))
	var sl := HSlider.new()
	sl.min_value = 0.25
	sl.max_value = 4.0
	sl.step = 0.05
	sl.value = Scaling.dev_mult
	sl.custom_minimum_size = Vector2(300, 40)
	var vl := UIKit.label("x%.2f" % sl.value, 22)
	sl.value_changed.connect(func(x):
		Scaling.dev_mult = x
		vl.text = "x%.2f" % x)
	row.add_child(sl)
	row.add_child(vl)
	_btn(g, "+1000 monedas", func(): GameState.add_coins(1000, false))
	_btn(g, "Subir un nivel", func(): GameState.add_xp(float(GameState.xp_to_next())))
	_btn(g, "Curar y recargar todo", func():
		var p = GameState.player
		if p != null:
			p.hp = p.max_hp
			p.skills.energy = p.skills.energy_max
			p.emit_hp())
	_btn(g, "Matar a todos los enemigos", func():
		if GameState.arena != null:
			GameState.arena.kill_all())
	_btn(g, "Completar arena actual", func():
		if GameState.arena != null:
			GameState.arena.force_complete())
	var r2 := HBoxContainer.new()
	g.add_child(r2)
	r2.add_child(UIKit.label("Ir a la arena nº", 22))
	_arena_spin = SpinBox.new()
	_arena_spin.min_value = 1
	_arena_spin.max_value = 60
	_arena_spin.value = GameState.arena_index + 1
	_arena_spin.custom_minimum_size = Vector2(160, 48)
	r2.add_child(_arena_spin)
	var go := UIKit.button("Ir", Vector2(120, 52), 22)
	go.pressed.connect(func():
		jump_to_arena.emit(int(_arena_spin.value) - 1)
		closed.emit()
		queue_free())
	r2.add_child(go)
	g.add_child(UIKit.label("Dar mejora:", 22, UIKit.ACCENT))
	var opt := OptionButton.new()
	var ids: Array = []
	for d in UpgradeDB.all():
		opt.add_item(String(d["name"]))
		ids.append(d["id"])
	opt.custom_minimum_size = Vector2(500, 52)
	g.add_child(opt)
	var rar := OptionButton.new()
	for n in UpgradeDB.RARITY_NAMES:
		rar.add_item(String(n))
	g.add_child(rar)
	_btn(g, "Añadir mejora seleccionada", func():
		GameState.build.add(ids[opt.selected], rar.selected)
		GameState.build_changed.emit()
		GameState.toast_msg("Mejora añadida (dev)", UIKit.GOOD))


func _check(parent: Control, text: String, val: bool, cb: Callable) -> void:
	var c := CheckButton.new()
	c.text = text
	c.button_pressed = val
	c.focus_mode = Control.FOCUS_NONE
	c.add_theme_font_size_override("font_size", 22)
	c.toggled.connect(cb)
	parent.add_child(c)


func _btn(parent: Control, text: String, cb: Callable) -> void:
	var b := UIKit.button(text, Vector2(420, 54), 22)
	b.pressed.connect(cb)
	parent.add_child(b)
