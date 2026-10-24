extends Node
## Pruebas de la pantalla de DERROTA / VICTORIA (v0.10.3): diseño adaptable, lista de 30 mejoras desplazable,
## botones completos (táctil y mando), varias resoluciones horizontales. Render real (xvfb), entrada real.
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 -- --endtest --out=DIR

var main: Node
var out_dir := "/tmp/endtest"
var fails: Array = []
var passes := 0
const RES := [Vector2i(1280, 720), Vector2i(960, 540), Vector2i(854, 480), Vector2i(1280, 590), Vector2i(800, 360)]


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


func info(msg: String) -> void:
	print("[INFO] ", msg)


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


func _tap(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await _touch(p, true)
	await _touch(p, false)
	await _frames(3)


func _swipe_up(from: Vector2, dy: float) -> void:
	await _touch(from, true)
	var pos := from
	var moved := 0.0
	while moved < dy:
		pos.y -= 20.0
		moved += 20.0
		await _dragev(pos, Vector2(0, -20))
	await _touch(pos, false)
	await _frames(4)


func _joy(btn: int) -> void:
	for d in [true, false]:
		var ev := InputEventJoypadButton.new()
		ev.button_index = btn
		ev.pressed = d
		Input.parse_input_event(ev)
		await _frames(3)


func _overlay_of(cls: Variant) -> Node:
	for o in main._overlays:
		if is_instance_valid(o) and is_instance_of(o, cls):
			return o
	return null


func _types(n: int) -> Array:
	var out: Array = []
	for d in UpgradeDB.all():
		if out.size() >= n:
			break
		if (d.get("req", {}) as Dictionary).size() > 0 or d.get("cat", "") == "legend":
			continue
		out.append(d["id"])
	return out


func _summary(victory: bool) -> Dictionary:
	return {"victory": victory, "arena": 15, "cycle": 3, "kills": 1234, "time": 1807.0, "score": 987654, "fees": 4321,
		"stats": {"bosses": 3, "damage_dealt": 1234567.0, "highest_hit": 98765.0, "crits": 4321, "best_streak": 321, "coins_earned": 54321, "cards": 30},
		"build": GameState.build.summary_lines()}


func _all_controls(root: Node, out: Array) -> void:
	for ch in root.get_children():
		if ch is Control and (ch as Control).is_visible_in_tree():
			out.append(ch)
		_all_controls(ch, out)


func _run() -> void:
	await _frames(4)
	var t := 0.0
	while main.state != main.St.LOBBY and t < 10.0:
		await _secs(0.1)
		t += 0.1
	await _secs(1.0)
	main._on_play()
	t = 0.0
	while main.state != main.St.RUN and t < 10.0:
		await _secs(0.1)
		t += 0.1
	Config.dev_god_mode = true
	await _secs(1.0)
	# build de 30 mejoras DIFERENTES (con niveles distintos)
	var b: Build = GameState.build
	var ids := _types(30)
	for i in ids.size():
		b.add(ids[i], 0, true)
		if i % 3 == 0:
			b.add(ids[i], 0, true)
	GameState.build_changed.emit()
	ok(b.type_count() == 30, "E0 la build tiene 30 mejoras diferentes (%d)" % b.type_count())
	for victory in [false, true]:
		for r in RES:
			await _layout_case(victory, r)
	get_window().size = Vector2i(1280, 720)
	await _secs(0.5)
	await _interaction_tests()
	print("[RESULT] pantalla de fin: %d ok, %d fallos" % [passes, fails.size()])
	for f in fails:
		print("  FALLO: ", f)
	get_tree().quit(1 if fails.size() > 0 else 0)


func _layout_case(victory: bool, res: Vector2i) -> void:
	var tag := "%s %dx%d" % ["VICTORIA" if victory else "DERROTA", res.x, res.y]
	get_window().size = res
	await _secs(0.6)
	var es := EndScreen.new()
	es.show_summary(_summary(victory), victory)
	main._ov_root().add_child(es)
	await _secs(0.4)
	var vs := get_viewport().get_visible_rect()
	var inside := true
	var worst := ""
	var ctrls: Array = []
	_all_controls(es, ctrls)
	for c in ctrls:
		var ctl := c as Control
		if ctl is Label or ctl is Button:
			# los elementos de la zona desplazable se juzgan por el recorte de su contenedor; los fijos, por la pantalla
			if es._scroll.is_ancestor_of(ctl):
				continue
			var r := ctl.get_global_rect()
			if r.position.x < vs.position.x + 4 or r.position.y < vs.position.y + 4 or r.end.x > vs.end.x - 4 or r.end.y > vs.end.y - 4:
				inside = false
				worst = "%s %s" % [ctl.name, str(r)]
	ok(inside, "L %s: título, honorarios y botones completos dentro de la pantalla %s" % [tag, worst])
	var panel := es.get_node("EndPanel") as Control
	var pr := panel.get_global_rect()
	ok(pr.position.x >= vs.position.x + 8 and pr.end.x <= vs.end.x - 8 and pr.position.y >= vs.position.y + 8 and pr.end.y <= vs.end.y - 8, "L %s: el panel respeta los márgenes (%s en %s)" % [tag, str(pr), str(vs)])
	var btns := es.get_node("EndPanel").find_children("End_*", "Button", true, false)
	var small := false
	var overlap := false
	for i in btns.size():
		var br := (btns[i] as Button).get_global_rect()
		if br.size.y < 56.0 or br.size.x < 150.0:
			small = true
		for j in range(i + 1, btns.size()):
			if br.intersects((btns[j] as Button).get_global_rect()):
				overlap = true
	ok(btns.size() == (3 if true else 3) and not small and not overlap, "L %s: 3 botones, tamaño táctil (≥56 px de alto) y sin solaparse (%d)" % [tag, btns.size()])
	var sr := es._scroll.get_global_rect()
	var fr := (es.find_child("EndFees", true, false) as Control).get_global_rect()
	var bb := (es.find_child("EndButtons", true, false) as Control).get_global_rect()
	ok(sr.end.y <= fr.position.y + 1.0 and fr.end.y <= bb.position.y + 1.0 and sr.size.y >= 90.0, "L %s: la lista no se superpone con honorarios ni botones (lista %.0f px de alto)" % [tag, sr.size.y])
	var mx: int = int(es._scroll.get_v_scroll_bar().max_value - es._scroll.get_v_scroll_bar().page)
	var items := (es.find_child("EndBuild", true, false) as GridContainer).get_child_count()
	ok(items == 30, "L %s: se listan las 30 mejoras con su nivel (%d)" % [tag, items])
	# textos de las mejoras: ninguno recortado por el ancho (se parten en líneas)
	var clipped := false
	for l in (es.find_child("EndBuild", true, false) as GridContainer).get_children():
		var lb := l as Label
		if lb.get_minimum_size().x > lb.size.x + 2.0 and lb.autowrap_mode == TextServer.AUTOWRAP_OFF:
			clipped = true
	ok(not clipped, "L %s: ningún texto de mejora queda recortado" % tag)
	# desplazar con el dedo hasta el final y ver la última mejora
	if mx > 0:
		for k in 14:
			await _swipe_up(Vector2(sr.position.x + sr.size.x * 0.5, sr.position.y + sr.size.y * 0.85), minf(sr.size.y * 0.7, 300.0))
		await _secs(0.8)
		var last := (es.find_child("EndBuild", true, false) as GridContainer).get_child(29) as Control
		var lr := last.get_global_rect()
		ok(es._scroll.scroll_vertical >= mx - 2 and lr.position.y >= sr.position.y - 1.0 and lr.end.y <= sr.end.y + 1.0, "L %s: con el dedo se llega a la última mejora y queda visible (scroll %d/%d)" % [tag, es._scroll.scroll_vertical, mx])
	else:
		ok(true, "L %s: todo cabe sin desplazar" % tag)
	if res == Vector2i(1280, 720) or res == Vector2i(854, 480) or res == Vector2i(800, 360):
		es._scroll.scroll_vertical = 0
		await _frames(3)
		await _shot("e_%s_%dx%d" % ["victoria" if victory else "derrota", res.x, res.y])
	es.queue_free()
	await _frames(3)


func _interaction_tests() -> void:
	# --- derrota real: toque real sobre los botones ---
	var sm := GameState.end_run(false)
	ok(not sm.is_empty(), "I0 la derrota genera su resumen")
	main.state = main.St.ENDED
	var es := EndScreen.new()
	es.show_summary(sm, false)
	var fired := {"retry": 0, "lobby": 0, "settings": 0, "continue": 0}
	es.retry_pressed.connect(func(): fired["retry"] += 1)
	es.lobby_pressed.connect(func(): fired["lobby"] += 1)
	es.settings_pressed.connect(func(): fired["settings"] += 1)
	es.continue_pressed.connect(func(): fired["continue"] += 1)
	main._ov_root().add_child(es)
	main._overlays.append(es)
	get_tree().paused = true
	await _secs(0.5)
	await _tap(es.find_child("End_settings", true, false) as Control)
	await _tap(es.find_child("End_lobby", true, false) as Control)
	await _tap(es.find_child("End_retry", true, false) as Control)
	ok(fired["settings"] == 1 and fired["lobby"] == 1 and fired["retry"] == 1, "I1 los tres botones responden al toque real (%s)" % str(fired))
	# deslizar la lista empezando sobre un texto no activa ningún botón
	var sr := es._scroll.get_global_rect()
	var before := fired.duplicate()
	await _swipe_up(Vector2(sr.position.x + 80, sr.position.y + sr.size.y * 0.8), 120.0)
	ok(fired == before, "I2 deslizar la lista no dispara botones")
	# --- mando ---
	main.pad.debug_names[0] = "Xbox Wireless Controller"
	Input.joy_connection_changed.emit(0, true)
	await _secs(0.5)
	var fo := get_viewport().gui_get_focus_owner()
	info("foco inicial con mando: %s" % (str(fo.name) if fo != null else "ninguno"))
	ok(fo != null and es.is_ancestor_of(fo), "P1 con mando el foco cae en un botón de la pantalla de fin")
	var f0 := fired.duplicate()
	for step in 3:
		await _joy(JOY_BUTTON_DPAD_RIGHT)
	var fo2 := get_viewport().gui_get_focus_owner()
	ok(fo2 != null and es.is_ancestor_of(fo2), "P2 la cruceta mantiene el foco dentro de los botones (%s)" % (str(fo2.name) if fo2 != null else "?"))
	# ir a cada botón con la cruceta y confirmar con A
	var reach := {}
	for target in ["End_retry", "End_lobby", "End_settings"]:
		var guard := 0
		while guard < 12:
			var cur := get_viewport().gui_get_focus_owner()
			if cur != null and cur.name == target:
				break
			await _joy(JOY_BUTTON_DPAD_RIGHT if guard < 4 else JOY_BUTTON_DPAD_LEFT)
			guard += 1
			if guard == 4:
				for k in 4:
					await _joy(JOY_BUTTON_DPAD_LEFT)
		var cur2 := get_viewport().gui_get_focus_owner()
		if cur2 != null and cur2.name == target:
			reach[target] = true
			var key: String = target.substr(4)
			var n0: int = int(fired[key])
			await _joy(JOY_BUTTON_A)
			ok(int(fired[key]) == n0 + 1, "P3 con la cruceta se llega a «%s» y A lo confirma" % target)
	ok(reach.size() == 3, "P4 con el mando se alcanzan los 3 botones (%s)" % str(reach.keys()))
	es._scroll.scroll_vertical = 0
	await _frames(3)
	# stick derecho desplaza la lista
	var ev := InputEventJoypadMotion.new()
	ev.axis = JOY_AXIS_RIGHT_Y
	ev.axis_value = 1.0
	Input.parse_input_event(ev)
	var s0 := es._scroll.scroll_vertical
	await _secs(0.6)
	ev.axis_value = 0.0
	Input.parse_input_event(ev)
	await _frames(2)
	ok(es._scroll.scroll_vertical > s0, "P5 el stick derecho desplaza la lista (%d → %d)" % [s0, es._scroll.scroll_vertical])
	Input.joy_connection_changed.emit(0, false)
	await _frames(3)
	es.queue_free()
	await _frames(3)
