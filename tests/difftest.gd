extends Node
## Pruebas v0.10.4: ventana «MESA DEL JUEZ» adaptable, rótulo de región/bioma dentro de pantalla y guante 3D indicador.
## Render real (xvfb), entrada táctil real, capturas en --out=DIR.
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 -- --difftest --out=DIR

var main: Node
var out_dir := "/tmp/difftest"
var fails: Array = []
var passes := 0
const RES := [Vector2i(1280, 720), Vector2i(960, 540), Vector2i(854, 480), Vector2i(1280, 590), Vector2i(800, 360), Vector2i(640, 300)]


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


func _all_controls(root: Node, out: Array) -> void:
	for ch in root.get_children():
		if ch is Control and (ch as Control).is_visible_in_tree():
			out.append(ch)
		_all_controls(ch, out)


func _overlay_of(cls: Variant) -> Node:
	for o in main._overlays:
		if is_instance_valid(o) and is_instance_of(o, cls):
			return o
	return null


func _inside(r: Rect2, vs: Rect2, m := 2.0) -> bool:
	return r.position.x >= vs.position.x + m and r.position.y >= vs.position.y + m and r.end.x <= vs.end.x - m and r.end.y <= vs.end.y - m


func _run() -> void:
	await _frames(4)
	var t := 0.0
	while main.state != main.St.LOBBY and t < 10.0:
		await _secs(0.1)
		t += 0.1
	await _secs(1.0)
	var stats_before := _diff_stats()
	for r in RES:
		await _diff_case(r)
	get_window().size = Vector2i(1280, 720)
	await _secs(0.5)
	await _diff_interaction()
	ok(_diff_stats() == stats_before, "D-datos: los multiplicadores de dificultad no cambiaron")
	await _banner_cases()
	await _hand_cases()
	print("[RESULT] mesa del juez / rótulo / mano: %d ok, %d fallos" % [passes, fails.size()])
	for f in fails:
		print("  FALLO: ", f)
	get_tree().quit(1 if fails.size() > 0 else 0)


func _diff_stats() -> String:
	var s := ""
	for id in LoadoutDB.DIFF_ORDER:
		var d: Dictionary = LoadoutDB.DIFFICULTIES[id]
		s += "%s:%s,%s,%s,%s,%s;" % [id, d["hp_x"], d["dmg_x"], d["count_x"], d["reward_x"], d["fee_x"]]
	return s


func _open_diff() -> DifficultyUI:
	var ui := DifficultyUI.new()
	main._open_overlay(ui)
	await _secs(0.35)
	return ui


func _close_diff(ui: Node) -> void:
	var cl := ui.find_child("DiffClose", true, false) as Button
	if cl != null:
		await _tap(cl)
	await _secs(0.2)


func _diff_case(res: Vector2i) -> void:
	var tag := "%dx%d" % [res.x, res.y]
	get_window().size = res
	await _secs(0.6)
	var ui := await _open_diff()
	var vs := get_viewport().get_visible_rect()
	var panel := ui.get_node("DiffPanel") as Control
	ok(_inside(panel.get_global_rect(), vs, 8.0), "M %s: el panel respeta los márgenes (%s en %s)" % [tag, str(panel.get_global_rect()), str(vs)])
	var sc := ui._scroll as ScrollContainer
	var sr := sc.get_global_rect()
	var cl := ui.find_child("DiffClose", true, false) as Button
	ok(_inside(cl.get_global_rect(), vs, 4.0) and cl.get_global_rect().size.y >= 56.0, "M %s: botón «Listo» completo y táctil (%s)" % [tag, str(cl.get_global_rect())])
	var title := ui.find_child("DiffTitle", true, false) as Control
	ok(_inside(title.get_global_rect(), vs, 4.0), "M %s: título dentro de pantalla" % tag)
	await _shot("diff_%s_top" % tag)
	# cada botón de acción es alcanzable: se desplaza hasta verlo completo y se comprueba tamaño táctil
	var all_ok := true
	var worst := ""
	for id in LoadoutDB.DIFF_ORDER:
		var b := ui.find_child("DiffBtn_" + id, true, false) as Button
		sc.ensure_control_visible(b)
		await _frames(3)
		var br := b.get_global_rect()
		var fully := br.position.y >= sr.position.y - 1.0 and br.end.y <= sr.end.y + 1.0 and br.position.x >= vs.position.x and br.end.x <= vs.end.x
		if not fully or br.size.y < 56.0 or br.size.x < 140.0:
			all_ok = false
			worst = "%s %s" % [id, str(br)]
		# la ventana debe poder leerse entera: ningún texto de la tarjeta se sale del panel por la derecha
		var card := ui.find_child("Diff_" + id, true, false) as Control
		if card.get_global_rect().end.x > panel.get_global_rect().end.x + 1.0:
			all_ok = false
			worst = "tarjeta " + id
	ok(all_ok, "M %s: botones ELEGIR/ELEGIDA/BLOQUEADA completos (≥56 px alto) al desplazar %s" % [tag, worst])
	var can_scroll := sc.get_v_scroll_bar().max_value > sc.get_v_scroll_bar().page + 1.0
	if can_scroll:
		sc.scroll_vertical = 0
		await _frames(2)
		await _swipe_up(sr.get_center(), 90.0)
		ok(sc.scroll_vertical > 10, "M %s: el contenido se desplaza con el dedo (scroll=%d)" % [tag, sc.scroll_vertical])
	else:
		ok(true, "M %s: las 4 tarjetas caben sin desplazar" % tag)
	sc.scroll_vertical = int(sc.get_v_scroll_bar().max_value)
	await _frames(3)
	await _shot("diff_%s_bottom" % tag)
	ok(_inside(cl.get_global_rect(), vs, 4.0), "M %s: «Listo» sigue visible tras desplazar" % tag)
	await _close_diff(ui)
	ok(_overlay_of(DifficultyUI) == null, "M %s: «Listo» cierra la ventana" % tag)


func _diff_interaction() -> void:
	var before := LoadoutDB.selected_difficulty()
	var ui := await _open_diff()
	var other := "socio" if before != "socio" else "asociado"
	if not LoadoutDB.DIFFICULTIES.has(other):
		other = LoadoutDB.DIFF_ORDER[0]
	var b := ui.find_child("DiffBtn_" + other, true, false) as Button
	ui._scroll.ensure_control_visible(b)
	await _frames(3)
	if b != null and not b.disabled:
		await _tap(b)
		await _secs(0.3)
		ok(LoadoutDB.selected_difficulty() == other, "I: tocar ELEGIR cambia la dificultad a %s" % other)
	ui = _overlay_of(DifficultyUI) as DifficultyUI
	var locked := LoadoutDB.DIFF_ORDER[LoadoutDB.DIFF_ORDER.size() - 1]
	var lb := ui.find_child("DiffBtn_" + locked, true, false) as Button
	ok(lb != null and (lb.disabled == (not LoadoutDB.diff_unlocked(locked))), "I: la dificultad bloqueada sigue bloqueada (%s)" % locked)
	# restaura la elección original
	var rb := ui.find_child("DiffBtn_" + before, true, false) as Button
	if rb != null and not rb.disabled:
		await _tap(rb)
		await _secs(0.2)
	ok(LoadoutDB.selected_difficulty() == before, "I: se restauró la dificultad original (%s)" % before)
	await _close_diff(_overlay_of(DifficultyUI))


func _banner_cases() -> void:
	for res in RES:
		get_window().size = res
		await _secs(0.5)
		var vs := get_viewport().get_visible_rect()
		for idx in [1, 6, 11, 16]:
			main._show_region_banner(idx, 1.0)
			await _secs(0.6)
			var rb: Control = main._region_banner
			var labels: Array = []
			_all_controls(rb, labels)
			var good := not labels.is_empty()
			var worst := ""
			for l in labels:
				if l is Label:
					var r := (l as Label).get_global_rect()
					if not _inside(r, vs, 0.0):
						good = false
						worst = "%s %s" % [(l as Label).text, str(r)]
			ok(good, "B %dx%d arena %d: los 3 textos del rótulo de región dentro de pantalla %s" % [res.x, res.y, idx, worst])
			if idx == 6:
				await _shot("region_%dx%d" % [res.x, res.y])
			await _secs(1.2)


func _hand_cases() -> void:
	get_window().size = Vector2i(1280, 720)
	await _secs(0.5)
	var st: Interactable = main.lobby.stations["difficulty"]
	var hand := st._ind_icon
	ok(hand != null and hand.name == "PointerHand", "H: la mesa de dificultad usa el guante 3D (no un sprite)")
	var mesh: ArrayMesh = ModelFactory.pointer_hand_mesh(Color(1, 0.5, 0.5))
	var bb := mesh.get_aabb()
	ok(absf((bb.position.y) + 0.43) < 0.06, "H: la punta del índice es el punto más bajo (y=%.2f)" % bb.position.y)
	ok(bb.size.y > bb.size.x * 1.5, "H: silueta alta y estrecha (%.2f x %.2f)" % [bb.size.x, bb.size.y])
	GameState.player.teleport_to(st.global_position + Vector3(2.0, 0.0, 2.2))
	await _secs(0.8)
	var cam := get_viewport().get_camera_3d()
	if cam != null and hand != null:
		var tip := hand.global_position + Vector3(0, -0.43 * hand.global_transform.basis.get_scale().y * st._ind.scale.y, 0)
		var table := st.global_position
		ok(tip.y > table.y + 0.5, "H: la punta del guante queda por encima de la mesa (%.2f > %.2f)" % [tip.y, table.y])
		ok(not cam.is_position_behind(hand.global_position), "H: el guante está delante de la cámara")
		var sp := cam.unproject_position(hand.global_position)
		ok(get_viewport().get_visible_rect().has_point(sp), "H: el guante está en pantalla (%s)" % str(sp))
		# orientado a cámara: su eje Z local apunta (en el plano XZ) hacia la cámara
		var fwd := hand.global_transform.basis.z
		var to_cam := cam.global_position - hand.global_position
		fwd.y = 0.0
		to_cam.y = 0.0
		ok(fwd.normalized().dot(to_cam.normalized()) > 0.98, "H: el guante mira a la cámara")
	await _shot("hand_lobby")
	# primer plano: la cámara habitual del jugador desde cerca de la mesa
	GameState.player.teleport_to(st.global_position + Vector3(0.0, 0.0, 3.4))
	await _secs(1.0)
	await _shot("hand_lobby_close")
