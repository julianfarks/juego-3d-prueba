extends Node
## Panel de recompensas del cofre con desplazamiento táctil. Entrada táctil real (InputEventScreenTouch/Drag), render real.
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 -- --chesttest --out=DIR

var main: Node
var out_dir := "/tmp/chesttest"
var fails: Array = []
var passes := 0
const RES := [Vector2i(1280, 720), Vector2i(800, 360), Vector2i(405, 720)]


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out_dir)
	call_deferred("_run")


func ok(cond: bool, name: String) -> void:
	if cond:
		passes += 1
		print("[PASS] ", name)
	else:
		fails.append(name)
		print("[FAIL] ", name)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _secs(t: float) -> void:
	await get_tree().create_timer(t, true, false, true).timeout


func _shot(name: String) -> void:
	await _frames(4)
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png("%s/%s.png" % [out_dir, name])


func _touch(pos: Vector2, down: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.position = get_viewport().get_final_transform() * pos
	ev.pressed = down
	Input.parse_input_event(ev)
	await _frames(2)


func _dragev(pos: Vector2, rel: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = 0
	ev.position = get_viewport().get_final_transform() * pos
	ev.relative = get_viewport().get_final_transform().basis_xform(rel)
	Input.parse_input_event(ev)
	await _frames(1)


func _swipe(from: Vector2, dy: float) -> void:
	await _touch(from, true)
	var pos := from
	var moved := 0.0
	var step := 20.0 * signf(dy)
	while absf(moved) < absf(dy):
		pos.y += step
		moved += step
		await _dragev(pos, Vector2(0, step))
	await _touch(pos, false)
	await _frames(4)


func _tap(p: Vector2) -> void:
	await _touch(p, true)
	await _touch(p, false)
	await _frames(3)


func _mouse(pos: Vector2, down: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.position = get_viewport().get_final_transform() * pos
	ev.global_position = ev.position
	ev.pressed = down
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if down else 0
	Input.parse_input_event(ev)
	await _frames(2)


func _mmove(pos: Vector2, rel: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = get_viewport().get_final_transform() * pos
	ev.global_position = ev.position
	ev.relative = rel
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(ev)
	await _frames(1)


func _inside(r: Rect2, vs: Rect2, m := 1.0) -> bool:
	return r.position.x >= vs.position.x - m and r.position.y >= vs.position.y - m and r.end.x <= vs.end.x + m and r.end.y <= vs.end.y + m


func _open(count: int) -> CardSelect:
	var cs := CardSelect.new()
	main._open_overlay(cs)
	cs.open(GameState.arena_index, 0, "chest", count, [], 1, 1)
	return cs


func _run() -> void:
	await _frames(10)
	await main._enter_lobby(true)
	await _frames(10)
	main._on_play()
	var t := 0.0
	while main.state != main.St.RUN and t < 10.0:
		await _frames(2)
		t += 0.03
	await _secs(1.0)
	Config.dev_god_mode = true
	print("[INFO] pad_mode al empezar: ", PadInput.pad_mode)
	if PadInput.inst != null:
		PadInput.inst.set_mode_setting("touch")        # el móvil juega con el dedo (en modo mando la primera carta se enfoca/selecciona a propósito)
	await _frames(5)
	print("[INFO] pad_mode forzado a táctil: ", PadInput.pad_mode)
	for res in RES:
		get_window().size = res
		await _secs(0.6)
		var tag := "%dx%d" % [res.x, res.y]
		# en pantallas verticales la interfaz se escala a lo ancho y cabe mucho más alto: más cartas para forzar el desplazamiento
		var cs := _open(9 if res.x > res.y else 24)
		await _secs(1.0)
		var vs := get_viewport().get_visible_rect()
		var n: int = cs._cards.size()
		ok(n >= 9, "C1 %s: el cofre ofrece todas las cartas (%d, no se recorta ninguna)" % [tag, n])
		var sc: ScrollContainer = cs._sc
		var bar := sc.get_v_scroll_bar()
		var scrollable: bool = bar.max_value - bar.page > 4.0
		ok(scrollable, "C2 %s: el contenido necesita desplazamiento (%.0f > %.0f)" % [tag, bar.max_value, bar.page])
		ok(_inside(cs._confirm.get_global_rect(), vs) and _inside(cs._skip.get_global_rect(), vs) and _inside(cs._inv_btn.get_global_rect(), vs),
			"C3 %s: los botones ELEGIR / Descartar / INVENTARIO están siempre a la vista" % tag)
		ok(_inside(cs._title.get_global_rect(), vs), "C3b %s: el título queda dentro de la pantalla" % tag)
		await _shot("c_%s_top" % tag)
		# --- arrastrar sobre una carta no selecciona nada ---
		var c0: Control = cs._card_nodes[0]
		var start := c0.get_global_rect().get_center()
		start.y = clampf(start.y, sc.get_global_rect().position.y + 40.0, sc.get_global_rect().end.y - 160.0)
		var before := sc.scroll_vertical
		await _swipe(start, -160.0)
		ok(sc.scroll_vertical > before, "C4 %s: arrastrar hacia arriba desplaza (%d → %d)" % [tag, before, sc.scroll_vertical])
		ok(cs._selected == -1, "C5 %s: deslizar sobre las cartas NO selecciona ninguna" % tag)
		# --- ratón real arrastrado (no táctil) ---
		var b2 := sc.scroll_vertical
		var mp := sc.get_global_rect().get_center()
		await _mouse(mp, true)
		for k in 8:
			mp.y += 20.0
			await _mmove(mp, Vector2(0, 20))
		await _mouse(mp, false)
		await _frames(3)
		ok(cs._selected == -1, "C5b %s: arrastrar con ratón tampoco selecciona" % tag)
		# --- llegar hasta el final ---
		for k in 12:
			await _swipe(sc.get_global_rect().get_center(), -240.0)
		await _secs(1.2)
		bar = sc.get_v_scroll_bar()
		ok(sc.scroll_vertical >= int(bar.max_value - bar.page) - 3, "C6 %s: se llega al final de la lista (%d de %.0f)" % [tag, sc.scroll_vertical, bar.max_value - bar.page])
		var last: Control = cs._card_nodes[n - 1]
		ok(_inside(last.get_global_rect(), sc.get_global_rect(), 8.0), "C7 %s: la última carta queda completa en la zona visible (carta %s, zona %s)" % [tag, last.get_global_rect(), sc.get_global_rect()])
		await _shot("c_%s_bottom" % tag)
		await _tap(last.get_global_rect().get_center())
		ok(cs._selected == n - 1, "C8 %s: se puede seleccionar la última carta con un toque (sel=%d)" % [tag, cs._selected])
		ok(not cs._confirm.disabled and _inside(cs._confirm.get_global_rect(), vs), "C9 %s: ELEGIR queda activo y visible" % tag)
		# --- volver arriba ---
		for k in 14:
			await _swipe(sc.get_global_rect().get_center(), 240.0)
		await _secs(1.2)
		ok(sc.scroll_vertical <= 3, "C10 %s: se regresa a las primeras cartas (%d)" % [tag, sc.scroll_vertical])
		var first: Control = cs._card_nodes[0]
		await _tap(first.get_global_rect().get_center())
		ok(cs._selected == 0, "C11 %s: un toque en la primera carta la selecciona" % tag)
		# --- confirmar con el botón fijo ---
		var got := []
		cs.picked.connect(func(c): got.append(c))
		await _tap(cs._confirm.get_global_rect().get_center())
		await _secs(0.4)
		ok(got.size() == 1, "C12 %s: ELEGIR confirma la carta seleccionada (%d)" % [tag, got.size()])
		await _secs(0.5)
		for o in main._overlays.duplicate():
			if is_instance_valid(o):
				o.queue_free()
		await _secs(0.4)
	get_window().size = Vector2i(1280, 720)
	print("[RESULT] cofre táctil: %d ok, %d fallos" % [passes, fails.size()])
	for f in fails:
		print("  FALLO: ", f)
	get_tree().quit(1 if fails.size() > 0 else 0)
