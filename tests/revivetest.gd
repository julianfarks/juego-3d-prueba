extends Node
## Pruebas del sistema de reanimación con anuncios recompensados (proveedor de PRUEBA; no hay anuncios reales).
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 -- --revivetest --out=DIR

var main: Node
var out_dir := "/tmp/revivetest"
var fails: Array = []
var passes := 0
var prov: DevTestAdProvider


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


func _tap(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await _touch(p, true)
	await _touch(p, false)
	await _frames(3)


func _btn(name: String) -> Button:
	var es: EndScreen = main._defeat_es
	if es == null or not is_instance_valid(es):
		return null
	return es.find_child(name, true, false) as Button


func _label(name: String) -> Label:
	var es: EndScreen = main._defeat_es
	if es == null or not is_instance_valid(es):
		return null
	return es.find_child(name, true, false) as Label


func _new_run() -> void:
	if main.state == main.St.LOBBY:
		main._on_play()
	else:
		main._start_run()
	await _secs(2.0)
	var t := 0.0
	while main.state != main.St.RUN and t < 10.0:
		await _secs(0.1)
		t += 0.1
	await _secs(0.8)
	var ar: Arena = main.arena
	ar.phase = Arena.Phase.IDLE


func _die() -> void:
	var pl = GameState.player
	pl.shield = 0.0
	pl.iframes = 0.0
	pl.hurt_iframes = 0.0
	pl.take_damage(pl.max_hp * 10.0, pl.global_position + Vector3(2, 0, 0), {})
	var t := 0.0
	while (main._defeat_es == null or not is_instance_valid(main._defeat_es)) and t < 8.0:
		await _secs(0.1)
		t += 0.1
	await _secs(0.5)


func _revive_via_ui(result: int) -> void:
	prov.scripted_result = result
	await _tap(_btn("End_revive"))
	await _secs(0.6)


func _run() -> void:
	await _frames(4)
	var t := 0.0
	while main.state != main.St.LOBBY and t < 10.0:
		await _secs(0.1)
		t += 0.1
	await _secs(1.0)
	prov = DevTestAdProvider.new()
	RewardedAdService.set_provider(prov)
	ok(not prov.is_real and prov.provider_name.contains("PRUEBA"), "A0 el proveedor de prueba se identifica como PRUEBA y no es real")
	await _new_run()
	var pl = GameState.player
	ok(GameState.ad_revives_used == 0 and GameState.ad_revives_left() == 2, "A1 partida nueva: 2/2 reanimaciones")
	GameState.coins = 321
	GameState.build.add("armor_low", 0, true)
	GameState.build_changed.emit()
	var picks0: int = GameState.build.picks.size()
	var deaths0 := int(SaveSystem.data["stats"]["deaths"])
	var fees0 := int(SaveSystem.data["meta"]["fees"])
	var arena0: int = GameState.arena_index
	var phase0: int = main.arena.phase
	# ---- 1.ª muerte
	await _die()
	ok(main._defeat_es != null and not pl.alive, "B1 al morir aparece la pantalla de derrota")
	ok(_btn("End_revive") != null and _btn("End_revive").text == "REVIVIR — VER ANUNCIO DE 30 S" and not _btn("End_revive").disabled, "B2 botón «REVIVIR — VER ANUNCIO DE 30 S» visible y activo")
	ok(_label("End_reviveCount").text == "Reanimaciones disponibles: 2/2", "B3 contador «%s»" % _label("End_reviveCount").text)
	ok(_btn("End_retry") != null and _btn("End_lobby") != null, "B4 siguen existiendo Reintentar y VOLVER AL VESTÍBULO (derrota habitual)")
	await _shot("derrota_2de2")
	# ---- cancelar / error / no disponible no consumen
	for case in [[DevTestAdProvider.Result.CANCELLED, "cancelado", "cancel"], [DevTestAdProvider.Result.ERROR, "error", "Error"], [DevTestAdProvider.Result.UNAVAILABLE, "no disponible", "Anuncio no disponible. Inténtalo más tarde."]]:
		await _revive_via_ui(case[0])
		var msg := _label("End_reviveMsg")
		ok(GameState.ad_revives_used == 0 and not pl.alive and main._defeat_es != null, "C %s: no consume oportunidad ni revive (usadas=%d)" % [case[1], GameState.ad_revives_used])
		ok(msg != null and msg.visible and msg.text != "" and not _btn("End_revive").disabled, "C %s: mensaje «%s» y el botón sigue disponible" % [case[1], msg.text if msg != null else ""])
	prov.available = false
	await _revive_via_ui(-1)
	ok(GameState.ad_revives_used == 0 and _label("End_reviveMsg").text == "Anuncio no disponible. Inténtalo más tarde.", "C5 proveedor sin anuncio listo → «Anuncio no disponible. Inténtalo más tarde.»")
	prov.available = true
	await _shot("derrota_no_disponible")
	# ---- pulsaciones repetidas con recompensa concedida: UNA sola reanimación
	prov.scripted_result = DevTestAdProvider.Result.COMPLETED
	var b := _btn("End_revive")
	var p := b.get_global_rect().get_center()
	for k in 3:
		await _touch(p, true)
		await _touch(p, false)
	for k in 5:
		main._on_revive_pressed()
	await _secs(1.0)
	ok(GameState.ad_revives_used == 1 and GameState.ad_revives_left() == 1, "D1 pulsaciones repetidas: solo se consume 1 (usadas=%d)" % GameState.ad_revives_used)
	ok(pl.alive and absf(pl.hp - pl.max_hp * 0.5) < 1.0, "D2 revive con el 50%% de vida (%.1f/%.1f)" % [pl.hp, pl.max_hp])
	ok(pl.iframes > 1.5, "D3 invulnerable unos segundos (%.1f s)" % pl.iframes)
	ok(main.state == main.St.RUN and not main._end_pending and not get_tree().paused and main._defeat_es == null, "D4 vuelve al control: estado RUN, sin pausa ni pantalla de derrota")
	ok(GameState.coins == 321 and GameState.build.picks.size() == picks0 and GameState.arena_index == arena0 and main.arena.phase == phase0, "D5 se conservan monedas, mejoras, ronda y fase")
	ok(int(SaveSystem.data["stats"]["deaths"]) == deaths0 and int(SaveSystem.data["meta"]["fees"]) == fees0 and GameState.in_run, "D6 la muerte y los honorarios de la derrota quedan revertidos al reanimar")
	var hp_before = pl.hp
	await _secs(1.0)
	ok(pl.alive and pl.hp >= hp_before - 0.5, "D7 sin muerte instantánea tras reanimar")
	main._do_revive()
	main._do_revive()
	ok(GameState.ad_revives_used == 1, "D8 llamar de nuevo a la secuencia no reanima ni consume otra vez")
	# ---- guardado: se conserva el uso
	await _secs(0.5)
	var snap: Dictionary = GameState.snapshot_run("fight")
	ok(int(snap["ad_revives"]) == 1 and SaveSystem.validate_run(snap) == "", "E1 el guardado incluye ad_revives=1 y es válido")
	var back = JSON.parse_string(JSON.stringify(snap))
	var saved: Dictionary = SaveSystem.data["run"]
	ok(not saved.is_empty() and int(saved.get("ad_revives", -1)) == 1, "E2 tras reanimar se guarda la partida con 1 reanimación usada")
	GameState.ad_revives_used = 0
	GameState.restore_run(back)
	ok(GameState.ad_revives_used == 1, "E3 al cargar la partida guardada se conserva el uso (1/2)")
	# ---- 2.ª muerte y 2.ª reanimación
	await _die()
	ok(_label("End_reviveCount") != null and _label("End_reviveCount").text == "Reanimaciones disponibles: 1/2", "F1 2.ª derrota muestra 1/2")
	await _revive_via_ui(DevTestAdProvider.Result.COMPLETED)
	ok(pl.alive and GameState.ad_revives_used == 2 and GameState.ad_revives_left() == 0, "F2 la 2.ª reanimación funciona y consume la última")
	# ---- 3.ª muerte
	await _die()
	ok(_label("End_reviveCount").text == "Reanimaciones disponibles: 0/2", "G1 3.ª derrota muestra 0/2")
	var rb := _btn("End_revive")
	ok(rb != null and rb.disabled and rb.text == "SIN REANIMACIONES DISPONIBLES", "G2 el botón queda desactivado: «%s»" % rb.text)
	var shown0 := prov.shown
	prov.scripted_result = DevTestAdProvider.Result.COMPLETED
	main._on_revive_pressed()
	await _tap(rb)
	await _secs(0.5)
	ok(not pl.alive and GameState.ad_revives_used == 2 and prov.shown == shown0, "G3 ni pulsando ni llamando al método se puede revivir una 3.ª vez")
	await _shot("derrota_0de2")
	# ---- adaptable
	for res in [Vector2i(1280, 720), Vector2i(854, 480), Vector2i(800, 360), Vector2i(640, 300)]:
		get_window().size = res
		await _secs(0.6)
		var vs := get_viewport().get_visible_rect()
		var all_in := true
		for nm in ["End_revive", "End_retry", "End_lobby", "End_settings"]:
			var bb := _btn(nm)
			if bb == null:
				all_in = false
				continue
			var r := bb.get_global_rect()
			if r.position.x < -1 or r.position.y < -1 or r.end.x > vs.end.x + 1 or r.end.y > vs.end.y + 1:
				all_in = false
				print("   fuera: ", nm, " ", r, " vs ", vs)
		ok(all_in, "H derrota con reanimar cabe en %dx%d" % [res.x, res.y])
		await _shot("derrota_%dx%d" % [res.x, res.y])
	get_window().size = Vector2i(1280, 720)
	await _secs(0.5)
	# ---- partida nueva restaura las dos
	await _tap(_btn("End_retry"))
	await _secs(3.0)
	ok(GameState.ad_revives_used == 0 and GameState.ad_revives_left() == 2, "I1 una partida nueva restaura las 2 reanimaciones")
	# ---- diálogo del proveedor de prueba (UI real, sin anuncio)
	prov.scripted_result = -1
	prov.available = true
	await _new_run()
	pl = GameState.player
	await _die()
	await _tap(_btn("End_revive"))
	await _secs(0.5)
	var dlg = main._ov_root().find_child("DevTestAdDialog", true, false)
	ok(dlg != null and _all_text(dlg).find("NO es un anuncio") >= 0 and _all_text(dlg).find("MODO DESARROLLO") >= 0, "J1 el diálogo se rotula como MODO DESARROLLO y aclara que NO es un anuncio")
	await _shot("dialogo_prueba")
	ok(GameState.ad_revives_used == 0 and not pl.alive, "J2 mientras el diálogo está abierto no hay reanimación (no hay temporizador que reviva solo)")
	await _secs(3.0)
	ok(GameState.ad_revives_used == 0 and not pl.alive, "J3 pasado un rato sigue sin reanimar sola")
	await _tap(dlg.find_child("DevAd_cancel", true, false) as Button)
	await _secs(0.5)
	ok(GameState.ad_revives_used == 0 and main._defeat_es != null and _label("End_reviveMsg").visible, "J4 cancelar en el diálogo: no consume y vuelve a la derrota")
	await _tap(_btn("End_revive"))
	await _secs(0.5)
	dlg = main._ov_root().find_child("DevTestAdDialog", true, false)
	await _tap(dlg.find_child("DevAd_completed", true, false) as Button)
	await _secs(0.8)
	ok(pl.alive and GameState.ad_revives_used == 1, "J5 «recompensa concedida» en el diálogo de prueba reanima (1 uso)")
	# ---- sin proveedor (producción sin SDK)
	RewardedAdService.set_provider(NullAdProvider.new())
	var rr: int = await RewardedAdService.show_rewarded("revive", self)
	ok(rr == RewardedAdService.Result.UNAVAILABLE and not RewardedAdService.provider().is_real, "K1 sin SDK conectado el servicio responde «no disponible» (nunca concede)")
	RewardedAdService.set_provider(null)
	print("[RESULT] reanimación: %d ok, %d fallos" % [passes, fails.size()])
	for f in fails:
		print("  FALLO: ", f)
	get_tree().quit(1 if fails.size() > 0 else 0)


func _all_text(n: Node) -> String:
	var s := ""
	if n is Label:
		s += (n as Label).text + "\n"
	elif n is Button:
		s += (n as Button).text + "\n"
	for c in n.get_children():
		s += _all_text(c)
	return s
