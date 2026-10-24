extends Node
## Pruebas de TIENDA y COFRES (v0.10.1): desplazamiento táctil de la lista, relanzamientos (3 por visita) y cofres sin relanzar.
## Render real (xvfb) y entrada real (InputEventScreenTouch / InputEventScreenDrag sobre la interfaz).
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 -- --shoptest --out=DIR

var main: Node
var out_dir := "/tmp/shoptest"
var fails: Array = []
var passes := 0


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


func _touch(idx: int, pos: Vector2, down: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = idx
	ev.position = get_viewport().get_final_transform() * pos       # de coordenadas del lienzo a coordenadas de ventana
	ev.pressed = down
	Input.parse_input_event(ev)
	await _frames(2)


func _dragev(idx: int, pos: Vector2, rel: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = idx
	ev.position = get_viewport().get_final_transform() * pos
	ev.relative = get_viewport().get_final_transform().basis_xform(rel)
	Input.parse_input_event(ev)
	await _frames(1)


func _tap(pos: Vector2) -> void:
	await _touch(0, pos, true)
	await _touch(0, pos, false)
	await _frames(3)


## Desliza el dedo: empieza en 'from', se mueve 'dy' píxeles en pasos de 'step' y suelta.
func _swipe(from: Vector2, dy: float, step := 24.0) -> void:
	await _touch(0, from, true)
	var pos := from
	var moved := 0.0
	var dirn := signf(dy)
	while absf(moved) < absf(dy):
		pos.y += dirn * step
		moved += dirn * step
		await _dragev(0, pos, Vector2(0, dirn * step))
	await _touch(0, pos, false)
	await _frames(4)


func _btn(root: Node, node_name: String) -> Button:
	return root.find_child(node_name, true, false) as Button if root != null else null


func _overlay_of(cls: Variant) -> Node:
	for o in main._overlays:
		if is_instance_valid(o) and is_instance_of(o, cls):
			return o
	return null


func _find_btn_text(root: Node, prefix: String) -> Button:
	for b in root.find_children("*", "Button", true, false):
		if (b as Button).visible and (b as Button).text.begins_with(prefix):
			return b
	return null


func _max_scroll(sc: ScrollContainer) -> int:
	var bar := sc.get_v_scroll_bar()
	return int(bar.max_value - bar.page)


func _open_shop() -> ShopUI:
	main._on_shop()
	await _secs(0.4)
	return _overlay_of(ShopUI) as ShopUI


func _close_shop(sh: ShopUI) -> void:
	await _tap(_btn(sh, "Shop_close").get_global_rect().get_center())
	await _secs(0.3)


func _valid_offers(sh: ShopUI) -> bool:
	var seen := {}
	var b: Build = GameState.build
	for o in sh._offers:
		if o["type"] == "card":
			var id: String = o["card"]["id"]
			if seen.has(id) or not b.can_add(id):
				return false
			seen[id] = true
	return true


func _ids(sh: ShopUI) -> Array:
	var out: Array = []
	for o in sh._offers:
		out.append(String(o["card"]["id"]) if o["type"] == "card" else String(o["type"]))
	return out


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
	await _scroll_tests()
	await _reroll_tests()
	await _chest_tests()
	print("[RESULT] tienda y cofres: %d ok, %d fallos" % [passes, fails.size()])
	for f in fails:
		print("  FALLO: ", f)
	get_tree().quit(1 if fails.size() > 0 else 0)


# ============================================================================ desplazamiento
func _scroll_tests() -> void:
	GameState.coins = 5000
	var sh := await _open_shop()
	ok(sh != null, "S0 la tienda se abre")
	var sc: ScrollContainer = sh._sc
	var mx := _max_scroll(sc)
	info("ofertas: %d · desplazamiento máximo %d px · lista %s" % [sh._offers.size(), mx, str(sc.get_global_rect())])
	ok(mx > 40, "S1 hay ofertas por debajo que exigen desplazarse (%d px)" % mx)
	await _shot("s01_tienda_inicio")
	var coins0: int = GameState.coins
	var purchases0 := ShopUI.purchases
	var r := sc.get_global_rect()
	# a) arrastrar desde una zona libre de la carta (el texto), hacia arriba
	var row0 := sh._list.get_child(1) as Control
	var from_text := Vector2(row0.get_global_rect().position.x + 260, row0.get_global_rect().get_center().y)
	await _swipe(from_text, -150)
	var s1 := sc.scroll_vertical
	ok(s1 >= 60, "S2 arrastrar desde el texto de una oferta desplaza la lista hacia abajo (scroll %d)" % s1)
	# b) arrastrar hacia abajo regresa
	await _swipe(from_text, 150)
	ok(sc.scroll_vertical < s1 - 40, "S3 arrastrar hacia abajo vuelve a las ofertas anteriores (scroll %d)" % sc.scroll_vertical)
	await _swipe(from_text, 300)
	await _secs(0.8)
	ok(sc.scroll_vertical <= 2, "S3b arrastrando hacia abajo se llega al principio (%d)" % sc.scroll_vertical)
	# c) empezar el gesto SOBRE el botón de compra: desplaza y no compra
	var buy: Button = null
	for b in sh._list.find_children("*", "Button", true, false):
		if (b as Button).text.begins_with("$"):
			buy = b
			break
	ok(buy != null and not buy.disabled, "S4 hay un botón de compra activo para la prueba")
	var bc := buy.get_global_rect().get_center()
	await _swipe(bc, -160)
	await _secs(0.5)
	ok(sc.scroll_vertical > 40, "S5 también desplaza si el dedo empieza sobre un botón de compra (scroll %d)" % sc.scroll_vertical)
	ok(GameState.coins == coins0 and ShopUI.purchases == purchases0, "S6 deslizar sobre el botón NO compra (monedas %d→%d)" % [coins0, GameState.coins])
	ok(sh.get_node_or_null("RerollConfirm") == null and _find_btn_text(sh, "Confirmar") == null, "S7 deslizar no abre ninguna confirmación de compra")
	# d) llegar hasta la última oferta sin tocar la barra
	for k in 8:
		await _swipe(Vector2(r.position.x + 300, r.position.y + r.size.y * 0.7), -220)
	await _secs(0.9)
	mx = _max_scroll(sc)
	ok(sc.scroll_vertical >= mx - 2, "S8 se llega al final de la lista solo con el dedo (%d de %d)" % [sc.scroll_vertical, mx])
	var last := sh._list.get_child(sh._list.get_child_count() - 2) as Control
	var lr := last.get_global_rect()
	ok(lr.position.y >= r.position.y - 1.0 and lr.end.y <= r.end.y + 1.0, "S9 la última oferta queda completa dentro de la lista (%s en %s)" % [str(lr), str(r)])
	var foot_btn := _btn(sh, "Shop_close")
	ok(foot_btn.get_global_rect().position.y >= r.end.y - 1.0, "S10 los botones inferiores no tapan la lista (salir en y=%.0f, lista termina en %.0f)" % [foot_btn.get_global_rect().position.y, r.end.y])
	await _shot("s02_tienda_final")
	# e) pulsación corta sobre el botón: abre la confirmación, no compra todavía
	var buy2: Button = null
	for b in sh._list.find_children("*", "Button", true, false):
		var bb := b as Button
		if bb.text.begins_with("$") and not bb.disabled and r.encloses(bb.get_global_rect()):
			buy2 = bb
			break
	if buy2 != null:
		await _tap(buy2.get_global_rect().get_center())
		await _secs(0.3)
		var yes := _find_btn_text(sh, "Confirmar")
		ok(yes != null and GameState.coins == coins0, "S11 una pulsación intencional pide confirmación y todavía no cobra")
		var no := _find_btn_text(sh, "Cancelar")
		if no != null:
			await _tap(no.get_global_rect().get_center())
			await _secs(0.3)
		ok(GameState.coins == coins0, "S12 cancelar no cobra")
	else:
		ok(false, "S11 no se encontró botón de compra visible al final de la lista")
	await _close_shop(sh)
	# e2) otra resolución (pantalla pequeña): sigue desplazando
	var win := get_window()
	var old := win.size
	win.size = Vector2i(854, 480)
	await _secs(0.6)
	info("ventana %s · transformación final %s" % [str(win.size), str(get_viewport().get_final_transform())])
	var sh2 := await _open_shop()
	var sc2: ScrollContainer = sh2._sc
	var rr := sc2.get_global_rect()
	var m2 := _max_scroll(sc2)
	if m2 > 0:
		await _swipe(Vector2(rr.position.x + rr.size.x * 0.5, rr.position.y + rr.size.y * 0.8), -120)
		ok(sc2.scroll_vertical > 20, "S13 con 854×480 también se desplaza con el dedo (scroll %d de %d)" % [sc2.scroll_vertical, m2])
	else:
		ok(true, "S13 con 854×480 todo cabe sin desplazar")
	await _shot("s03_tienda_854x480")
	await _close_shop(sh2)
	win.size = old
	await _secs(0.6)
	info("ventana restaurada %s" % str(win.size))


# ============================================================================ relanzamientos
func _reroll_tests() -> void:
	Config.dev_god_mode = true
	await main._begin_arena(0, true)
	await _secs(0.8)
	GameState.coins = 1000
	var sh := await _open_shop()
	var ids0 := _ids(sh)
	ok(sh.rerolls_used() == 0 and ShopUI.MAX_REROLLS == 3, "R0 nueva visita: 0/3 relanzamientos")
	var rb := _btn(sh, "Shop_reroll")
	ok(rb != null and rb.text == "RELANZAR (20 $) — 1/3", "R1 el botón muestra precio y contador: «%s»" % (rb.text if rb != null else "?"))
	await _shot("r01_tienda_relanzar")
	var costs := [20, 30, 45]
	var changed_any := false
	for n in 3:
		var before: int = GameState.coins
		var prev := _ids(sh)
		await _tap(rb.get_global_rect().get_center())
		await _secs(0.3)
		var yes := _find_btn_text(sh, "Confirmar")
		ok(yes != null and before == GameState.coins, "R2.%d se muestra la confirmación con el precio antes de cobrar" % (n + 1))
		var shown := false
		for l in sh.find_children("*", "Label", true, false):
			if (l as Label).text.contains("Precio: %d $" % costs[n]):
				shown = true
		ok(shown, "R3.%d la confirmación indica el precio correcto (%d $)" % [n + 1, costs[n]])
		await _tap(yes.get_global_rect().get_center())
		await _secs(0.4)
		ok(before - GameState.coins == costs[n], "R4.%d se cobró exactamente %d $ (cobrado %d)" % [n + 1, costs[n], before - GameState.coins])
		ok(sh.rerolls_used() == n + 1, "R5.%d contador de usos %d/3" % [n + 1, n + 1])
		ok(_valid_offers(sh), "R6.%d las nuevas ofertas son válidas (sin duplicados, todas comprables según la build)" % (n + 1))
		if _ids(sh) != prev:
			changed_any = true
		await _shot("r02_tras_relanzar_%d" % (n + 1))
	ok(changed_any, "R7 los relanzamientos generan ofertas distintas")
	ok(rb.disabled and rb.text.begins_with("RELANZAMIENTOS AGOTADOS"), "R8 al llegar a 3 el botón se desactiva e indica que se agotaron: «%s»" % rb.text)
	var c_before: int = GameState.coins
	var ok4 := sh.do_reroll()
	ok(not ok4 and GameState.coins == c_before and sh.rerolls_used() == 3, "R9 un 4.º relanzamiento es imposible y no cobra")
	sh._ask_reroll()
	await _frames(3)
	ok(_find_btn_text(sh, "Confirmar") == null and GameState.coins == c_before, "R9b ni siquiera abre la confirmación")
	# cerrar y reabrir la misma visita: no se reinicia el límite ni se regeneran las ofertas
	var ids_before := _ids(sh)
	await _close_shop(sh)
	var sh2 := await _open_shop()
	ok(sh2.rerolls_used() == 3 and _btn(sh2, "Shop_reroll").disabled, "R10 al cerrar y reabrir la tienda en la misma visita siguen gastados los 3 relanzamientos")
	ok(_ids(sh2) == ids_before, "R11 reabrir NO regenera las ofertas")
	var c2: int = GameState.coins
	ok(not sh2.do_reroll() and GameState.coins == c2, "R12 y no se puede relanzar de nuevo")
	await _close_shop(sh2)
	# visita nueva (siguiente arena): vuelve a 0/3
	await main._begin_arena(1, true)
	await _secs(0.8)
	GameState.coins = 1000
	var sh3 := await _open_shop()
	ok(sh3.rerolls_used() == 0 and not _btn(sh3, "Shop_reroll").disabled, "R13 una visita nueva restablece el límite (0/3)")
	# saldo insuficiente
	GameState.coins = 10
	sh3._refresh()
	var rb3 := _btn(sh3, "Shop_reroll")
	ok(rb3.disabled, "R14 sin dinero el botón está desactivado")
	var c3: int = GameState.coins
	sh3._ask_reroll()
	await _frames(3)
	ok(GameState.coins == c3 and _find_btn_text(sh3, "Confirmar") == null, "R15 sin dinero se informa y no se cobra nada")
	ok(not sh3.do_reroll() and GameState.coins == c3 and sh3.rerolls_used() == 0, "R16 do_reroll sin dinero devuelve falso y no consume un uso")
	# compra normal sigue funcionando
	GameState.coins = 1000
	sh3._refresh()
	var cc: int = GameState.coins
	var heal_i := 0
	var price := sh3.price_of(float(sh3._offers[heal_i]["base"]))
	sh3._lock_until = 0
	sh3._buy(heal_i)
	ok(cc - GameState.coins == price, "R17 las compras normales siguen cobrando su precio (%d $)" % price)
	# Segunda Opinión no se vuelve a ofrecer disponible tras relanzar
	var rev_i := -1
	for i in sh3._offers.size():
		if sh3._offers[i]["type"] == "revive":
			rev_i = i
	sh3._lock_until = 0
	sh3._buy(rev_i)
	ok(sh3._offers[rev_i]["sold"], "R18 «Segunda Opinión» queda vendida")
	sh3._lock_until = 0
	sh3.do_reroll()
	var rev_sold := false
	for o in sh3._offers:
		if o["type"] == "revive" and o["sold"]:
			rev_sold = true
	ok(rev_sold, "R19 relanzar no vuelve a poner a la venta una oferta de un solo uso ya comprada")
	await _close_shop(sh3)


# ============================================================================ cofres
func _chest_tests() -> void:
	GameState.coins = 500
	main._reward_pick(0, 1, 1, [])
	await _secs(0.8)
	var cs := _overlay_of(CardSelect) as CardSelect
	ok(cs != null and cs._cards.size() >= 1, "C0 el cofre abre sus cartas")
	var rer := false
	for b in cs.find_children("*", "Button", true, false):
		var tx := (b as Button).text.to_lower()
		if tx.contains("relanz") or tx.contains("reroll"):
			rer = true
	ok(not rer, "C1 la pantalla del cofre no muestra ningún botón de relanzar")
	ok(cs.get("_reroll") == null and not cs.has_method("_on_reroll") and not cs.has_method("_reroll_cost"), "C2 el cofre ya no contiene la lógica de relanzar")
	ok(_find_btn_text(cs, "Descartar") != null and _find_btn_text(cs, "INVENTARIO") != null, "C3 siguen estando Descartar e INVENTARIO")
	await _shot("c01_cofre")
	# tocar una carta la selecciona y ELEGIR la añade
	var picks0: int = GameState.build.picks.size()
	var node0: Control = cs._card_nodes[0]
	await _tap(node0.get_global_rect().get_center())
	ok(cs._selected == 0, "C4 tocar una carta la selecciona")
	var cards0 := cs._cards.duplicate(true)
	await _tap(cs._confirm.get_global_rect().get_center())
	await _secs(0.5)
	ok(GameState.build.picks.size() == picks0 + 1 and _overlay_of(CardSelect) == null, "C5 elegir una carta la añade y cierra el cofre")
	# descartar da monedas
	main._reward_pick(0, 1, 1, [])
	await _secs(0.8)
	var cs2 := _overlay_of(CardSelect) as CardSelect
	var co: int = GameState.coins
	await _tap(cs2._skip.get_global_rect().get_center())
	await _secs(0.4)
	ok(_overlay_of(CardSelect) == null and GameState.coins > co, "C6 Descartar cierra el cofre y da monedas")
