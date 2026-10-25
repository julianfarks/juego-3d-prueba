extends Node
## Pruebas de la SUPERVIVENCIA INFINITA (sin victoria final) y de la pantalla de estadísticas al morir.
##   Fase 1 (partida nueva, save borrado):  godot --path . -- --infinitetest --out=DIR
##   Fase 2 (proceso NUEVO, mismo save):    godot --path . -- --infinitetest --phase=2 --out=DIR
## Render real (xvfb). Todo lo medido se compara con eventos independientes contados por la propia prueba.

var main: Node
var out_dir := "/tmp/infinitetest"
var phase := 1
var fails: Array = []
var passes := 0
var kills_seen := 0                 # contador INDEPENDIENTE de bajas (señal kill_registered)
var prov: DevTestAdProvider


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		if a == "--phase=2":
			phase = 2
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


func _tap(c: Control) -> void:
	var p := c.get_global_rect().get_center()
	await _touch(p, true)
	await _touch(p, false)
	await _frames(3)


func _overlay_of(cls: Variant) -> Node:
	for o in main._overlays:
		if is_instance_valid(o) and is_instance_of(o, cls):
			return o
	return null


func _end_screen() -> EndScreen:
	return _overlay_of(EndScreen) as EndScreen


func _stat(es: Node, key: String) -> String:
	var l := es.find_child("EndStat_" + key, true, false) as Label
	return l.text if l != null else "<falta>"


func _wait_state(st: int, limit := 15.0) -> void:
	var t := 0.0
	while main.state != st and t < limit:
		await _secs(0.1)
		t += 0.1


## Pasa por fuera todos los textos de interfaz y escenas buscando restos del final por victoria.
func _scan_sources() -> Array:
	var bad: Array = []
	var words := ["GANASTE", "CASO GANADO", "RECLAMAR VICTORIA", "CONTINUAR EN MODO", "continue_pressed", "_continue_after_victory", "_victory_shown"]
	var stack: Array = ["res://scripts"]
	while not stack.is_empty():
		var d: String = stack.pop_back()
		for f in DirAccess.get_files_at(d):
			if f.ends_with(".gd"):
				var txt := FileAccess.get_file_as_string(d + "/" + f)
				for w in words:
					if txt.contains(w):
						bad.append("%s/%s «%s»" % [d, f, w])
		for sub in DirAccess.get_directories_at(d):
			stack.append(d + "/" + sub)
	return bad


func _labels_with(root: Node, words: Array, out: Array) -> void:
	for ch in root.get_children():
		var txt := ""
		if ch is Label:
			txt = (ch as Label).text
		elif ch is Button:
			txt = (ch as Button).text
		for w in words:
			if txt.to_upper().contains(String(w)):
				out.append(txt)
		_labels_with(ch, words, out)


# ------------------------------------------------------------------ escalado puro
func _test_scaling() -> void:
	var bad_nan := 0
	var bad_mono := 0
	var bad_step := 0
	var hp_cap: float = float(Config.SCALING["hp_cap"])
	var dmg_cap: float = float(Config.SCALING["dmg_cap"])
	var prev_hp := 0.0
	var prev_dmg := 0.0
	var max_step_hp := 0.0
	var diff := Scaling.diff_x("hp_x")
	var dd := Scaling.diff_x("dmg_x")
	for a in range(0, 3001):
		var h := Scaling.hp_mult(a)
		var d := Scaling.dmg_mult(a)
		if is_nan(h) or is_inf(h) or is_nan(d) or is_inf(d) or h > hp_cap * diff + 0.001 or d > dmg_cap * dd + 0.001:
			bad_nan += 1
		if h < prev_hp - 1e-9 or d < prev_dmg - 1e-9:
			bad_mono += 1
		if a > 0:
			max_step_hp = maxf(max_step_hp, h / prev_hp)
			if h / prev_hp > 1.15 or d / prev_dmg > 1.15:
				bad_step += 1
		prev_hp = h
		prev_dmg = d
	ok(bad_nan == 0, "S1 vida y daño de 0 a 3000 arenas: finitos y bajo el techo seguro (%d fallos)" % bad_nan)
	ok(bad_mono == 0, "S2 la dificultad nunca baja al avanzar (%d retrocesos)" % bad_mono)
	ok(bad_step == 0, "S3 sube de forma gradual: salto máximo entre arenas ×%.3f (≤ ×1.15)" % max_step_hp)
	ok(Scaling.hp_mult(300) > Scaling.hp_mult(100) and Scaling.dmg_mult(300) > Scaling.dmg_mult(100), "S4 pasado el punto donde el exponencial se congela sigue subiendo (arena 100→300: vida ×%.1f→×%.1f)" % [Scaling.hp_mult(100), Scaling.hp_mult(300)])
	# por debajo del tope, la curva es la de siempre
	var c := Config.SCALING
	var old10 := (1.0 + float(c["hp_lin"]) * 10.0) * pow(float(c["hp_exp"]), 10.0) * Scaling.dev_mult * diff
	ok(absf(Scaling.hp_mult(10) - old10) < 1e-6, "S5 las primeras arenas conservan la curva original (arena 10: ×%.3f)" % Scaling.hp_mult(10))
	var max_elite := 0
	var max_cnt := 0.0
	for a in range(0, 3001):
		max_elite = maxi(max_elite, Scaling.elite_count(a))
		max_cnt = maxf(max_cnt, Scaling.count_mult(a))
	ok(max_elite <= int(c["elite_cap"]) and max_cnt <= float(c["count_cap"]) * Scaling.diff_x("count_x") + 0.001, "S6 élites ≤ %d y cantidad ×%.2f ≤ tope (sin oleadas descontroladas)" % [max_elite, max_cnt])
	# tamaño real de los planes de oleada
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var worst := 0
	var worst_wave := 0
	for a in range(0, 1500, 7):
		for k in Scaling.KINDS:
			var pl := WaveDirector.plan(k, a, rng)
			var tot := 0
			for w in pl["waves"]:
				tot += (w as Array).size()
				worst_wave = maxi(worst_wave, (w as Array).size())
			worst = maxi(worst, tot)
	ok(worst_wave <= 60 and worst <= 150, "S7 oleadas acotadas hasta la arena 1500: máx. %d por oleada, %d por arena" % [worst_wave, worst])
	ok(Scaling.survival_time(5000) <= 100.0, "S8 la arena de supervivencia no se alarga sin fin (%.0f s)" % Scaling.survival_time(5000))
	var bad := _scan_sources()
	ok(bad.is_empty(), "S9 el código ya no contiene victoria/«continuar» (%s)" % str(bad))


# ------------------------------------------------------------------ flujo real
func _clear_current_arena() -> void:
	var ar: Arena = main.arena
	var t := 0.0
	while ar.phase == Arena.Phase.INTRO and t < 12.0:
		await _secs(0.1)
		t += 0.1
	t = 0.0
	while ar.phase == Arena.Phase.FIGHT and t < 60.0:
		ar._survival_left = 0.0
		ar.kill_all()
		await _secs(0.35)
		t += 0.35


## Abre el cofre y resuelve TODAS las pantallas de recompensa que aparezcan (botín del jefe incluido).
func _take_rewards() -> int:
	var ar: Arena = main.arena
	var picks := 0
	ar._open_chest(0)
	var t := 0.0
	var idle := 0.0
	while t < 14.0:
		await _secs(0.25)
		t += 0.25
		var cs := _overlay_of(CardSelect) as CardSelect
		if cs != null:
			idle = 0.0
			await _secs(0.3)
			cs._select(0)
			cs._on_confirm()
			picks += 1
			await _secs(0.4)
		else:
			idle += 0.25
			if idle > 1.6:
				break
	return picks


func _goto_next_arena(prev_idx: int) -> void:
	main._on_portal()
	var t := 0.0
	while (GameState.arena_index != prev_idx + 1 or main._transitioning) and t < 20.0:
		await _secs(0.1)
		t += 0.1
	await _secs(0.4)


func _die_now() -> void:
	var pl = GameState.player
	pl.shield = 0.0
	pl.iframes = 0.0
	pl.hurt_iframes = 0.0
	pl.take_damage(pl.max_hp * 10.0, pl.global_position + Vector3(2, 0, 0), {})


func _wait_end_screen(limit := 8.0) -> EndScreen:
	var t := 0.0
	while (main._defeat_es == null or not is_instance_valid(main._defeat_es)) and t < limit:
		await _secs(0.1)
		t += 0.1
	await _secs(0.5)
	return main._defeat_es


func _phase1() -> void:
	_test_scaling()
	GameState.kill_registered.connect(func(_e): kills_seen += 1)
	prov = DevTestAdProvider.new()
	RewardedAdService.set_provider(prov)
	var save_before: Dictionary = (SaveSystem.data["meta"]["perm"] as Dictionary).duplicate(true)
	main._on_play()
	await _wait_state(main.St.RUN)
	await _secs(1.0)
	Config.dev_god_mode = true
	PadInput.inst.set_mode_setting("touch")
	var rs: Dictionary = GameState.run_stats
	ok(int(rs["hits"]) == 0 and float(rs["damage_dealt"]) == 0.0 and int(rs["purchases"]) == 0 and int(rs["chests"]) == 0, "N0 partida nueva: contadores de estadísticas a cero")

	# ---- T1/T2: recorrer 12 arenas reales (incluye los 2 primeros jefes, donde antes acababa la partida)
	var boss_cleared := 0
	var chests := 0
	var boss_special := 0
	var no_victory_ui := true
	var last_idx := 0
	for idx in 12:
		last_idx = idx
		ok(GameState.arena_index == idx and main.state == main.St.RUN, "T1.%d arena %d en marcha (tipo %s)" % [idx, idx + 1, main.arena.kind])
		var was_boss: bool = main.arena.kind == Scaling.KIND_BOSS
		var bosses0 := int(rs["bosses"])
		await _clear_current_arena()
		ok(main.arena.phase == Arena.Phase.CLEARED, "T1.%d arena %d superada" % [idx, idx + 1])
		var chests0 := int(rs["chests"])
		var br0 := int(rs["boss_rewards"])
		var picks := await _take_rewards()
		chests += 1
		ok(int(rs["chests"]) == chests0 + 1, "T1.%d cofre contado una sola vez (%d → %d)" % [idx, chests0, int(rs["chests"])])
		if was_boss:
			boss_cleared += 1
			ok(int(rs["bosses"]) == bosses0 + 1, "T8.%d jefe derrotado contado (+1 → %d)" % [idx, int(rs["bosses"])])
			ok(int(rs["boss_rewards"]) == br0 + 1 and picks >= 2, "T8.%d botín especial del jefe sigue funcionando (elegidos %d, pantallas %d)" % [idx, int(rs["boss_rewards"]) - br0, picks])
			boss_special += 1
		var bad: Array = []
		_labels_with(main._ov_root(), ["GANASTE", "VICTORIA", "GANADO", "CONTINUAR"], bad)
		if main.state != main.St.RUN or _end_screen() != null or not bad.is_empty() or not GameState.in_run:
			no_victory_ui = false
		ok(main.state == main.St.RUN and _end_screen() == null and bad.is_empty() and GameState.in_run, "T1.%d tras el cofre%s no hay pantalla de victoria ni fin (estado RUN, %s)" % [idx, " del jefe" if was_boss else "", str(bad)])
		await _goto_next_arena(idx)
	ok(boss_cleared == 2, "T1 se derrotaron %d jefes reales y la partida siguió" % boss_cleared)
	ok(GameState.arena_index == 12 and main.state == main.St.RUN and GameState.in_run, "T2 se superó la arena donde antes terminaba el juego (tras el 2.º jefe): ahora en la arena %d" % (GameState.arena_index + 1))
	ok(no_victory_ui, "T1 en ningún momento apareció una pantalla de victoria")
	ok(int(rs["waves"]) >= 12, "T1 oleadas completadas medidas (%d)" % int(rs["waves"]))
	ok(kills_seen == GameState.kills and kills_seen > 0, "T5a bajas = bajas reales contadas por separado (%d = %d)" % [GameState.kills, kills_seen])

	# ---- T3: dificultad en arenas muy lejanas, en vivo
	var cap: int = int(Config.quality()["max_enemies"])
	var last_boss_hp := 0.0
	for far in [60, 149, 400, 1000]:
		main._begin_arena(far, true)
		await _secs(0.6)
		var ar: Arena = main.arena
		ar._survival_left = 40.0
		await _secs(7.0)
		var alive := ar.alive_count()
		var hp_ok := true
		var maxhp := 0.0
		for e in ar.active:
			if is_instance_valid(e) and e.alive:
				maxhp = maxf(maxhp, float(e.max_hp))
				if is_nan(e.max_hp) or is_inf(e.max_hp) or e.max_hp <= 0.0:
					hp_ok = false
		ok(GameState.arena_index == far and main.state == main.St.RUN and alive <= cap and hp_ok, "T3 arena %d (%s): %d enemigos ≤ tope %d, vida máx. %.0f finita" % [far + 1, ar.kind, alive, cap, maxhp])
		if far == 149 or far == 400 or far == 1000:
			ar.kill_all()
		await _secs(0.3)
	var f1 := await _measure_fps()
	info("tiempo medio por fotograma en arena 1000: %.1f ms (entorno sin GPU: NO es FPS real)" % f1)
	ok(f1 < 250.0, "T3 el motor no se bloquea en arenas lejanas (%.1f ms/fotograma)" % f1)
	Config.dev_god_mode = false

	# ---- T5: contadores contra eventos reales controlados
	main._begin_arena(1, true)
	await _secs(1.0)
	var ar2: Arena = main.arena
	ar2.kill_all()
	ar2.phase = Arena.Phase.IDLE
	await _secs(0.5)
	var pl = GameState.player
	pl.hp = pl.max_hp
	var e: Enemy = ar2._spawn_enemy("thief", pl.global_position + Vector3(6, 0, 0))
	await _secs(2.5)
	e.hp = 1.0e6
	e.max_hp = 1.0e6
	e.invuln_t = 0.0
	var d0 := float(rs["damage_dealt"])
	var h0 := int(rs["hits"])
	var db0 := float(rs["damage_boss"])
	var kills0 := GameState.kills
	for i in 3:
		e.invuln_t = 0.0
		e.take_damage(37.0, {"src": "slam"})
	ok(is_equal_approx(float(rs["damage_dealt"]) - d0, 111.0) and int(rs["hits"]) - h0 == 3 and float(rs["damage_boss"]) == db0, "T5b 3 golpes de 37 = +111 de daño, +3 impactos, 0 a jefes (%.1f / %d)" % [float(rs["damage_dealt"]) - d0, int(rs["hits"]) - h0])
	var slam: float = float((rs["dmg_src"] as Dictionary).get("slam", 0.0))
	ok(is_equal_approx(slam, 111.0), "T5c el daño por fuente coincide (slam %.1f)" % slam)
	e.hp = 1.0
	e.invuln_t = 0.0
	e.take_damage(500.0, {"src": "case"})
	await _secs(0.3)
	ok(GameState.kills == kills0 + 1 and kills_seen == GameState.kills, "T5d una baja real suma exactamente 1 (%d → %d)" % [kills0, GameState.kills])
	# jefe
	ar2._spawn_boss("boss")
	await _secs(3.0)
	var boss: Enemy = ar2._boss_ref
	if boss != null and is_instance_valid(boss):
		boss.hp = 1.0e6
		boss.max_hp = 1.0e6
		boss.invuln_t = 0.0
		var db1 := float(rs["damage_boss"])
		var dd1 := float(rs["damage_dealt"])
		boss.take_damage(50.0, {"src": "case"})
		var exp_b := 50.0 * (1.0 - Scaling.elite_resist(boss.arena_index))      # los jefes ignoran parte del daño (resistencia)
		ok(absf(float(rs["damage_boss"]) - db1 - exp_b) < 0.01 and absf(float(rs["damage_dealt"]) - dd1 - exp_b) < 0.01, "T5e golpe de 50 al jefe: +%.2f a «daño a jefes» y al total (50 con su resistencia)" % exp_b)
		ar2.kill_all()
		await _secs(0.5)
	else:
		ok(false, "T5e no se pudo crear el jefe de prueba")
	ar2.phase = Arena.Phase.IDLE
	# monedas: de baja y de jefe
	var ce0 := int(rs["coins_earned"])
	var ck0 := int(rs["coins_kill"])
	var cb0 := int(rs["coins_boss"])
	ar2._drop_coin(pl.global_position + Vector3(0, 0.6, 0), 10, false)
	ar2._drop_coin(pl.global_position + Vector3(0, 0.6, 0), 20, true)
	await _secs(3.0)
	var dce := int(rs["coins_earned"]) - ce0
	var dck := int(rs["coins_kill"]) - ck0
	var dcb := int(rs["coins_boss"]) - cb0
	ok(dck + dcb == dce and dce >= 30 and dcb >= 18 and dcb <= 22, "T5f monedas cobradas por origen: bajas %d + jefes %d = obtenidas %d" % [dck, dcb, dce])
	# daño recibido
	pl.hp = pl.max_hp
	pl.shield = 0.0
	pl.iframes = 0.0
	pl.hurt_iframes = 0.0
	var dt0 := float(rs["damage_taken"])
	var hu0 := int(rs["hurt"])
	pl.take_damage(10.0, pl.global_position + Vector3(2, 0, 0), {})
	var ddt := float(rs["damage_taken"]) - dt0
	ok(int(rs["hurt"]) - hu0 == 1 and ddt > 0.0 and ddt <= 10.0 * 1.6, "T5g un golpe al jugador: +1 vez herido, daño recibido %.2f" % ddt)
	pl.heal(pl.max_hp)
	# tienda real
	GameState.coins = 5000
	var sp0 := int(rs["coins_spent"])
	var pu0 := int(rs["purchases"])
	main._on_shop()
	await _secs(0.5)
	var sh := _overlay_of(ShopUI) as ShopUI
	ok(sh != null, "T5h la tienda se abre")
	if sh != null:
		var bought := 0
		var expect := 0
		var idx_offer := -1
		for i in sh._offers.size():
			var o: Dictionary = sh._offers[i]
			if not o["sold"] and o["type"] in ["heal", "heal_full", "shield_pack", "energy"]:
				idx_offer = i
				break
		if idx_offer >= 0:
			expect += sh.price_of(float(sh._offers[idx_offer]["base"]))
			sh._buy(idx_offer)
			bought += 1
			await _secs(0.5)
		var rc := sh.reroll_cost()
		if sh.do_reroll():
			expect += rc
		await _secs(0.5)
		ok(int(rs["coins_spent"]) - sp0 == expect and int(rs["purchases"]) - pu0 == bought and expect > 0, "T5i gastado en la tienda = %d (compra + relanzamiento) y %d compra" % [int(rs["coins_spent"]) - sp0, int(rs["purchases"]) - pu0])
		ok(GameState.coins == 5000 - expect, "T5j el saldo baja exactamente lo gastado (%d)" % GameState.coins)
		sh.queue_free()
		main._overlays.erase(sh)
		await _frames(3)
	# ---- T8: Segunda Opinión + reanimaciones con anuncio; luego muerte definitiva
	var spent_total := int(rs["coins_spent"])
	var dmg_total := float(rs["damage_dealt"])
	pl.revives_left = 1
	var free0 := int(rs["revives_free"])
	_die_now()
	await _secs(1.0)
	ok(pl.alive and int(rs["revives_free"]) == free0 + 1 and _end_screen() == null, "T8a «Segunda Opinión» sigue funcionando y se mide (+1)")
	pl.revives_left = 0
	var deaths0 := int(SaveSystem.data["stats"]["deaths"])
	var fees0 := int(SaveSystem.data["meta"]["fees"])
	for n in 2:
		_die_now()
		var es1 := await _wait_end_screen()
		ok(es1 != null and es1.find_child("End_revive", true, false) != null and not (es1.find_child("End_revive", true, false) as Button).disabled, "T8b.%d tras morir se ofrece reanimar (quedan %d)" % [n, GameState.ad_revives_left()])
		prov.scripted_result = RewardedAdService.Result.COMPLETED
		await _tap(es1.find_child("End_revive", true, false) as Control)
		await _secs(0.8)
		ok(pl.alive and main.state == main.St.RUN and _end_screen() == null and GameState.ad_revives_used == n + 1, "T8c reanimación %d con anuncio completada; la partida continúa (usadas %d)" % [n + 1, GameState.ad_revives_used])
		ok(int(SaveSystem.data["stats"]["deaths"]) == deaths0 and int(SaveSystem.data["meta"]["fees"]) == fees0, "T8d reanimar no deja derrotas ni honorarios registrados")
	ok(float(rs["damage_dealt"]) >= dmg_total and int(rs["coins_spent"]) == spent_total and int(rs["purchases"]) >= 1 and int(rs["bosses"]) == 2, "T8e las estadísticas de la partida se conservan al reanimar")

	# ---- T4: muerte definitiva -> pantalla de estadísticas
	GameState.build.add("armor_low", 0, true)
	GameState.build_changed.emit()
	var arena_at_death: int = GameState.arena_index + 1
	var coins_at_death := GameState.coins
	_die_now()
	var es := await _wait_end_screen()
	ok(es != null and main.state == main.St.ENDED, "T4a al morir sin reanimaciones aparece la pantalla de estadísticas")
	if es == null:
		return
	var rb := es.find_child("End_revive", true, false) as Button
	ok(rb != null and rb.disabled and rb.text.begins_with("SIN REANIMACIONES"), "T4b sin reanimaciones: el botón de reanimar queda desactivado")
	var bad2: Array = []
	_labels_with(es, ["GANASTE", "VICTORIA", "GANADO", "CONTINUAR"], bad2)
	ok(bad2.is_empty() and es.find_child("End_continue", true, false) == null, "T4c no hay «GANASTE» ni «CONTINUAR» (%s)" % str(bad2))
	var rt := es.find_child("End_retry", true, false) as Button
	var lb := es.find_child("End_lobby", true, false) as Button
	ok(rt != null and rt.text == "NUEVA PARTIDA" and lb != null and lb.text == "VOLVER A LA SALA CENTRAL", "T4d botones NUEVA PARTIDA y VOLVER A LA SALA CENTRAL")
	ok(es.find_child("EndScroll", true, false) != null, "T4e hay zona desplazable")
	var F := func(v: float) -> String: return Feedback.fmt(v)
	ok(_stat(es, "dmg") == F.call(float(rs["damage_dealt"])), "T5k «daño infligido» mostrado = medido (%s)" % _stat(es, "dmg"))
	ok(_stat(es, "taken") == F.call(float(rs["damage_taken"])) and _stat(es, "hurt") == F.call(float(rs["hurt"])), "T5l «daño recibido» (%s) y «veces herido» (%s) = medidos" % [_stat(es, "taken"), _stat(es, "hurt")])
	ok(_stat(es, "spent") == F.call(float(spent_total)) and _stat(es, "purchases") == F.call(float(rs["purchases"])), "T5m «gastado» (%s) y «compras» (%s) = medidos" % [_stat(es, "spent"), _stat(es, "purchases")])
	ok(_stat(es, "kills") == F.call(float(kills_seen)), "T5n «enemigos eliminados» (%s) = bajas contadas aparte (%d)" % [_stat(es, "kills"), kills_seen])
	ok(_stat(es, "coins_left") == F.call(float(coins_at_death)), "T5o «monedas al morir» (%s) = saldo real (%d)" % [_stat(es, "coins_left"), coins_at_death])
	ok(_stat(es, "earned") == F.call(float(rs["coins_earned"])) and int(rs["coins_earned"]) >= int(rs["coins_kill"]) + int(rs["coins_boss"]), "T5p «monedas obtenidas» (%s) no se confunde con lo gastado (%s)" % [_stat(es, "earned"), _stat(es, "spent")])
	ok(_stat(es, "arena") == str(arena_at_death) and _stat(es, "bosses") == str(int(rs["bosses"])) and int(rs["bosses"]) == 2, "T4f arena (%s) y jefes (%s) coherentes" % [_stat(es, "arena"), _stat(es, "bosses")])
	ok(_stat(es, "chests") == F.call(float(chests)) and _stat(es, "boss_rewards") == str(boss_special), "T4g cofres (%s) y botines de jefe (%s) = los abiertos de verdad" % [_stat(es, "chests"), _stat(es, "boss_rewards")])
	ok(_stat(es, "revives") == "3", "T8f reanimaciones usadas = 1 «Segunda Opinión» + 2 con anuncio (%s)" % _stat(es, "revives"))
	ok(int(_stat(es, "upgrades")) >= 1 and _stat(es, "upgrades") == str(GameState.build.picks.size()), "T4h mejoras obtenidas = picks reales (%s)" % _stat(es, "upgrades"))
	var rec: Dictionary = SaveSystem.data["records"]
	ok(int(rec["best_arena"]) >= arena_at_death and float(rec["best_time"]) > 0.0 and es.find_child("EndNote_arena", true, false) != null, "T4i récords guardados (mejor arena %d)" % int(rec["best_arena"]))
	ok(int(SaveSystem.data["stats"]["deaths"]) == deaths0 + 1, "T4j la muerte se registra una sola vez (%d → %d)" % [deaths0, int(SaveSystem.data["stats"]["deaths"])])
	var fees1 := int(SaveSystem.data["meta"]["fees"])
	ok(GameState.end_run().is_empty() and int(SaveSystem.data["meta"]["fees"]) == fees1, "T4k abrir/cerrar el final otra vez no cobra ni registra nada dos veces")
	await _shot("infinite_end_top")
	var sc := es.find_child("EndScroll", true, false) as ScrollContainer
	sc.scroll_vertical = 100000
	await _frames(4)
	await _shot("infinite_end_bottom")
	sc.scroll_vertical = 0
	var kills_hist := int(SaveSystem.data["stats"]["kills"])
	var best_arena_hist := int(rec["best_arena"])
	var best_time_hist := float(rec["best_time"])
	var best_kills_hist := int(rec["best_kills"])

	# ---- T6: nueva partida desde el final
	await _tap(rt)
	await _wait_state(main.St.RUN)
	await _secs(1.5)
	var rs2: Dictionary = GameState.run_stats
	ok(main.state == main.St.RUN and _end_screen() == null, "T6a NUEVA PARTIDA arranca una partida nueva")
	var zero := int(rs2["hits"]) == 0 and float(rs2["damage_dealt"]) == 0.0 and float(rs2["damage_taken"]) == 0.0 and int(rs2["hurt"]) == 0 and int(rs2["coins_spent"]) == 0 \
		and int(rs2["purchases"]) == 0 and int(rs2["chests"]) == 0 and int(rs2["boss_rewards"]) == 0 and int(rs2["revives_free"]) == 0 and int(rs2["bosses"]) == 0 \
		and (rs2["dmg_src"] as Dictionary).is_empty() and int(rs2["coins_kill"]) == 0 and float(rs2["damage_boss"]) == 0.0
	ok(zero and GameState.kills == 0 and GameState.arena_index == 0 and GameState.ad_revives_used == 0, "T6b los contadores de la sesión anterior no se mezclan (todo a cero)")
	ok(int(SaveSystem.data["stats"]["kills"]) >= kills_hist and int(SaveSystem.data["records"]["best_arena"]) == best_arena_hist and float(SaveSystem.data["records"]["best_time"]) == best_time_hist, "T6c las estadísticas históricas y los récords se conservan (kills históricas %d)" % int(SaveSystem.data["stats"]["kills"]))
	# ---- T7 (parte 1): un desbloqueo permanente y una mejora temporal
	GameState.build.add("armor_low", 0, true)
	GameState.build_changed.emit()
	SaveSystem.data["meta"]["fees"] = 100000
	var unl_ok := LoadoutDB.unlock("gavel")
	SaveSystem.save_now()
	ok(unl_ok and LoadoutDB.is_unlocked("gavel"), "T7a desbloqueo permanente comprado (Mazo del Juez)")
	var perm_now: Dictionary = SaveSystem.data["meta"]["perm"]
	ok(perm_now == save_before and not (SaveSystem.data["meta"]["unlocks"] as Array).has("armor_low"), "T7b las mejoras temporales de la partida NO se guardan como permanentes")
	var f := FileAccess.open(out_dir + "/phase1.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"best_arena": best_arena_hist, "best_time": best_time_hist, "best_kills": best_kills_hist,
		"unlocks": SaveSystem.data["meta"]["unlocks"], "kills": int(SaveSystem.data["stats"]["kills"]), "deaths": int(SaveSystem.data["stats"]["deaths"]),
		"bosses": int(SaveSystem.data["stats"]["bosses"])}))
	f.close()


func _measure_fps() -> float:
	var t0 := Time.get_ticks_usec()
	var n := 60
	await _frames(n)
	return float(Time.get_ticks_usec() - t0) / 1000.0 / float(n)


func _phase2() -> void:
	var txt := FileAccess.get_file_as_string(out_dir + "/phase1.json")
	var d: Dictionary = JSON.parse_string(txt) if txt != "" else {}
	ok(not d.is_empty(), "R0 existe el registro de la fase 1")
	if d.is_empty():
		return
	var rec: Dictionary = SaveSystem.data["records"]
	ok(int(rec["best_arena"]) == int(d["best_arena"]) and int(rec["best_arena"]) >= 12, "R1 el récord de mejor arena sobrevivió al reinicio del juego (%d)" % int(rec["best_arena"]))
	ok(float(rec["best_time"]) == float(d["best_time"]) and int(rec["best_kills"]) == int(d["best_kills"]), "R2 récords de tiempo (%.1f s) y bajas (%d) sobrevivieron" % [float(rec["best_time"]), int(rec["best_kills"])])
	var unl: Array = SaveSystem.data["meta"]["unlocks"]
	ok(unl.has("gavel") and LoadoutDB.is_unlocked("gavel"), "R3 el desbloqueo permanente sobrevivió al reinicio (%s)" % str(unl))
	ok(int(SaveSystem.data["stats"]["kills"]) == int(d["kills"]) and int(SaveSystem.data["stats"]["bosses"]) == int(d["bosses"]), "R4 estadísticas históricas intactas (bajas %d, jefes %d)" % [int(SaveSystem.data["stats"]["kills"]), int(SaveSystem.data["stats"]["bosses"])])
	ok(not (unl as Array).has("armor_low") and (SaveSystem.data["meta"]["perm"] as Dictionary).is_empty(), "R5 ninguna mejora temporal quedó como permanente")
	var has_wins := false
	for r in StatsPanel.rows():
		if String(r[0]).contains("completadas"):
			has_wins = true
	ok(not has_wins, "R6 el panel de récords ya no muestra «runs completadas»")


func _run() -> void:
	await _frames(4)
	await _wait_state(main.St.LOBBY, 10.0)
	await _secs(1.0)
	if phase == 2:
		await _phase2()
	else:
		await _phase1()
	print("[RESULT] supervivencia infinita (fase %d): %d ok, %d fallos" % [phase, passes, fails.size()])
	for f in fails:
		print("  FALLO: ", f)
	get_tree().quit(1 if fails.size() > 0 else 0)
