extends Node
## Pruebas del sistema de números de daño y sonido de combate (renderizado real: xvfb + Mesa).
##   xvfb-run -a godot --path . --rendering-driver opengl3 -- --fbtest --out=DIR
## Cubre las 8 comprobaciones obligatorias + ajustes. Un fallo termina con código 1.
## Limitación honesta: verifica el flujo de audio (qué se reproduce, cuántas voces, volumen/tono,
## buses y límites) y las propiedades de los WAV; NO puede "escuchar" el resultado en un móvil.

var main: Node
var out_dir := "/tmp/fbtest"
var fails: Array = []
var passes := 0
var fx: Node
var _bench: Dictionary = {}


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
	await get_tree().create_timer(t).timeout


func _shot(name: String) -> void:
	await _frames(3)
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png("%s/%s.png" % [out_dir, name])


## Enemigo listo para recibir daño (fuera de SPAWN), inmóvil y con vida enorme.
func _spawn(kind: String, pos: Vector3, hp := 1.0e12) -> Enemy:
	var e: Enemy = main.arena._spawn_enemy(kind, pos)
	var t := 0.0
	while e.state == Enemy.S.SPAWN and t < 4.0:
		await _frames(2)
		t += 0.04
	e.move_speed = 0.0
	e.max_hp = hp
	e.hp = hp
	return e


## Mata sin ruido ni número (el enemigo sigue el ciclo normal de muerte y reciclaje del arena).
func _dispose(e: Node) -> void:
	if is_instance_valid(e) and e.get("alive"):
		e.set("invuln_t", 0.0)
		e.take_damage(float(e.get("hp")) * 20.0 + 20.0, {"src": "boss_death", "silent": true})   # ×20: cubre la resistencia de élite


func _calm() -> void:
	## Deja el sistema de números sin presión ni números vivos (aísla cada comprobación).
	fx._update_labels(3.0)
	fx._spawn_times.clear()
	fx._recent_by_key.clear()


func _last_label(e: Node) -> Dictionary:
	var out := {}
	for d in fx._labels:
		if d["key"] == e.get_instance_id():
			out = d
	return out


func _events() -> Array:
	return Feedback.event_log.filter(func(x): return not x.has("combo"))


func _run() -> void:
	await _frames(10)
	main._show_menu()
	await _frames(15)
	main._on_play()
	var t := 0.0
	while main.state != main.St.RUN and t < 10.0:
		await _frames(2)
		t += 0.03
	ok(main.state == main.St.RUN, "F0 empieza la partida")
	Config.dev_god_mode = true
	main.arena.force_complete()
	await _secs(1.0)
	fx = GameState.fx
	Feedback.record = true
	AudioManager.record_combat = true
	GameState.kill_streak = 0
	await _t0_format_and_assets()
	await _t1_attack_types()
	await _t2_crits_and_modifiers()
	await _t3_overkill()
	await _t4_explosions()
	await _t5_kills_no_dupes()
	await _t6_sound_saturation()
	await _t7_many_enemies()
	await _t8_performance()
	await _t9_settings()
	await _t10_no_hit_no_sound()
	await _t11_gallery()
	_finish()


func _finish() -> void:
	print("[RESULT] %d ok, %d fallos" % [passes, fails.size()])
	for f in fails:
		print("  FALLO: ", f)
	get_tree().quit(1 if fails.size() > 0 else 0)


# ============================================================================ T0 formato y recursos
func _t0_format_and_assets() -> void:
	ok(Feedback.fmt(24) == "24", "T0.1 formato 24")
	ok(Feedback.fmt(157) == "157", "T0.2 formato 157")
	ok(Feedback.fmt(1250) == "1.250", "T0.3 formato 1.250")
	ok(Feedback.fmt(18450) == "18.450", "T0.4 formato 18.450")
	ok(Feedback.fmt(2750000) == "2.750.000", "T0.5 formato 2.750.000")
	ok(Feedback.fmt(999.6) == "1.000", "T0.6 redondeo 999.6 → 1.000")
	ok(Feedback.fmt(0.2) == "1", "T0.7 daño positivo minúsculo se muestra como 1")
	ok(Feedback.fmt(1.0e20) == "1,00e20", "T0.8 cantidades astronómicas en notación corta (sin desbordar int)")
	ok(Feedback.fmt(1234567890123.0) == "1.234.567.890.123", "T0.9 billones con separadores")
	# todos los sonidos usados existen, cargan y son válidos
	var names := ["hit_0", "hit_1", "hit_2", "hit_3", "hit_4", "crit", "crit_1", "hit_heavy", "hit_boss", "hit_fire",
		"hit_ice", "hit_shock", "dot_tick", "kill", "kill_boss", "combo", "explosion", "zap", "swing"]
	var missing: Array = []
	var seen_len: Dictionary = {}
	for n in names:
		var s := AudioManager._load("sfx_" + n)
		if s == null:
			missing.append(n)
		else:
			seen_len[n] = s.get_length()
	ok(missing.is_empty(), "T0.10 todos los sonidos de combate cargan (faltan: %s)" % str(missing))
	var all_short := true
	for n in seen_len:
		if float(seen_len[n]) <= 0.05 or float(seen_len[n]) > 1.0:
			all_short = false
	ok(all_short, "T0.11 duraciones razonables (0,05–1,0 s)")
	ok(AudioServer.get_bus_index("Combat") != -1, "T0.12 existe el bus Combat")
	ok(AudioServer.get_bus_effect_count(AudioServer.get_bus_index("Combat")) >= 1, "T0.13 el bus Combat lleva limitador")


# ============================================================================ T1 todos los tipos de ataque
func _t1_attack_types() -> void:
	var pl = GameState.player
	var e: Enemy = await _spawn("thief", pl.global_position + Vector3(4, 0, 0))
	var cases := [
		{"src": "slam", "base": 40.0}, {"src": "docs", "base": 16.0, "skill": true}, {"src": "boomerang", "base": 30.0},
		{"src": "echo", "base": 25.0, "flat": false}, {"src": "barrier", "base": 20.0, "skill": true},
		{"src": "zone", "base": 9.0, "flat": false, "skill": true}, {"src": "trail", "base": 12.0, "flat": false},
		{"src": "melee", "base": 55.0, "element": "fire"}, {"src": "melee", "base": 55.0, "element": "ice"},
		{"src": "melee", "base": 55.0, "element": "shock"}, {"src": "melee", "base": 180000.0},
	]
	var good := 0
	for c in cases:
		_calm()
		Feedback.reset()
		e.hp = e.max_hp
		var o: Dictionary = c.duplicate()
		o["no_crit"] = true
		o["proc"] = false
		var base: float = o["base"]
		var expected := float(Combat.calc(e, base, o)["damage"])
		var before := e.hp
		Combat.player_hit(e, base, o)
		var applied := before - e.hp
		var evs := _events()
		var lbl := _last_label(e)
		var match_ev := evs.size() == 1 and absf(float(evs[0]["dmg"]) - expected) < 0.001
		var match_hp := absf(applied - expected) < maxf(0.01, expected * 1e-9)
		var match_txt := not lbl.is_empty() and (lbl["node"] as Label3D).text == Feedback.fmt(expected)
		if match_ev and match_hp and match_txt:
			good += 1
		else:
			info("T1 %s/%s esperado %.3f evento %s aplicado %.3f etiqueta %s" % [o["src"], o.get("element", "phys"), expected,
				str(evs[0]["dmg"]) if evs.size() > 0 else "-", applied, (lbl["node"] as Label3D).text if not lbl.is_empty() else "-"])
	ok(good == cases.size(), "T1.1 el daño del evento = vida perdida = número en pantalla en %d/%d tipos de ataque" % [good, cases.size()])
	# proyectil real (documento teledirigido) y jugador real: golpear con la API de proyectiles
	_calm()
	Feedback.reset()
	e.hp = e.max_hp
	var hp0 := e.hp
	var pp: Vector3 = pl.global_position + Vector3(0, 1.0, 0)
	var dir: Vector3 = (e.global_position - pl.global_position).normalized()
	GameState.projectiles.fire_boomerang(pp, dir, 30.0, 9.0, 1.0, {"src": "boomerang", "flat": false, "no_crit": true})
	await _secs(1.2)
	var proj_events := _events().filter(func(x): return x["src"] == "boomerang")
	var lost := hp0 - e.hp
	var sum_ev := 0.0
	for x in _events():          # el ataque automático del jugador también golpea: se suman todos los eventos del enemigo
		if x["id"] == e.get_instance_id():
			sum_ev += float(x["dmg"])
	ok(proj_events.size() >= 1 and absf(sum_ev - lost) < 0.5, "T1.2 proyectil real (bumerán): %d impactos suyos; suma de todos los eventos %.1f = vida perdida %.1f" % [proj_events.size(), sum_ev, lost])
	# efecto periódico (quemadura) con el enemigo activo
	_calm()
	Feedback.reset()
	e.hp = e.max_hp
	e.apply_burn(40.0, 2.0)
	var hp1 := e.hp
	await _secs(2.6)
	var dot_events := _events().filter(func(x): return x["src"] == "burn")
	var dsum := 0.0
	for x in dot_events:
		dsum += float(x["dmg"])
	ok(dot_events.size() >= 3 and absf(dsum - (hp1 - e.hp)) < 0.5, "T1.3 quemadura: %d ticks, suma %.1f = vida perdida %.1f" % [dot_events.size(), dsum, hp1 - e.hp])
	var all_dot := dot_events.all(func(x): return x["kind"] == "dot")
	ok(all_dot, "T1.4 los ticks de quemadura se clasifican como periódicos")
	var normal_style := Feedback.classify(100.0, {"src": "melee"}, 1000.0)
	var dot_style := Feedback.classify(100.0, {"src": "burn", "element": "fire"}, 1000.0)
	ok(float(dot_style["scale"]) < float(normal_style["scale"]) and dot_style["color"] != normal_style["color"], "T1.5 periódico: más pequeño y de otro color que el normal")
	var merged_ok := true
	var live_for_e := 0
	for d in fx._labels:
		if d["key"] == e.get_instance_id():
			live_for_e += 1
	ok(live_for_e <= 2, "T1.6 los ticks de un mismo enemigo se agrupan en pocos números (%d vivos)" % live_for_e)
	var tot_shown := 0.0
	for x in dot_events:
		tot_shown += float(x["dmg"])
	_dispose(e)


# ============================================================================ T2 críticos, sinergias y modificadores
func _t2_crits_and_modifiers() -> void:
	var pl = GameState.player
	var b: Build = GameState.build
	var e: Enemy = await _spawn("thief", pl.global_position + Vector3(4, 1, 0))
	var o := {"src": "slam", "proc": false, "flat": false}
	var base := 100.0
	_calm()
	Feedback.reset()
	e.hp = e.max_hp
	var o1 := o.duplicate()
	o1["no_crit"] = true
	Combat.player_hit(e, base, o1)
	var n1 := float(_events()[0]["dmg"])
	_calm()
	e.hp = e.max_hp
	var o2 := o.duplicate()
	o2["force_crit"] = true
	Combat.player_hit(e, base, o2)
	var ev2: Dictionary = _events()[1]
	var n2 := float(ev2["dmg"])
	var want_ratio := 1.75 + b.s("crit_mult")
	ok(ev2["crit"] and ev2["kind"] == "crit" and absf(n2 / n1 - want_ratio) < 0.01, "T2.1 crítico muestra el multiplicador real (×%.2f esperado, ×%.3f mostrado)" % [want_ratio, n2 / n1])
	ok((_last_label(e)["node"] as Label3D).text == Feedback.fmt(n2) + "!", "T2.2 el crítico lleva '!' y el valor exacto")
	var cs := Feedback.classify(n2, {"crit": true}, 1.0e12)
	var ns := Feedback.classify(n1, {}, 1.0e12)
	ok(float(cs["scale"]) > float(ns["scale"]) and cs["color"] != ns["color"] and int(cs["prio"]) > int(ns["prio"]), "T2.3 crítico: más grande, otro color y mayor prioridad")
	# multiplicador de build (stat) → número
	var save_more: float = b.stats.get("more_dmg_x", 1.0)
	b.stats["more_dmg_x"] = save_more * 2.0
	_calm()
	e.hp = e.max_hp
	Combat.player_hit(e, base, o1)
	var n3 := float(_events()[2]["dmg"])
	ok(absf(n3 / n1 - 2.0) < 0.001, "T2.4 un multiplicador de build ×2 se refleja ×%.3f en el número" % (n3 / n1))
	b.stats["more_dmg_x"] = save_more
	# sinergia "war_machine" (×1.3 con racha de bajas)
	var had := b.active_synergies.has("war_machine")
	if not had:
		b.active_synergies.append("war_machine")
	GameState.kill_streak = 3
	_calm()
	e.hp = e.max_hp
	Combat.player_hit(e, base, o1)
	var n4 := float(_events()[3]["dmg"])
	var streak_pct: float = minf(3.0, 10.0) * b.s("streak_dmg")
	var expect4 := n1 * (1.0 + streak_pct) / 1.0 * 1.3
	ok(absf(n4 - expect4) < 0.01, "T2.5 sinergia War Machine ×1,3 reflejada (esperado %.2f, mostrado %.2f)" % [expect4, n4])
	if not had:
		b.active_synergies.erase("war_machine")
	GameState.kill_streak = 0
	# vulnerabilidad: enemigo marcado
	e.apply_mark(5.0)
	_calm()
	e.hp = e.max_hp
	Combat.player_hit(e, base, o1)
	var n5 := float(_events()[4]["dmg"])
	ok(absf(n5 / n1 - (1.25 + b.s("mark_amp"))) < 0.001, "T2.6 vulnerabilidad (marca ×%.2f) reflejada ×%.3f" % [1.25 + b.s("mark_amp"), n5 / n1])
	e.marked_t = 0.0
	# resistencia de élite
	var el: Enemy = await _spawn("elite", pl.global_position + Vector3(-4, 1, 0))
	el.arena_index = 20            # la resistencia de élite crece con la arena; en la 1 es 0
	Feedback.reset()
	_calm()
	el.hp = el.max_hp
	var calc_el := float(Combat.calc(el, base, o1)["damage"])
	Combat.player_hit(el, base, o1)
	var nel := float(_events()[0]["dmg"])
	var resist := Scaling.elite_resist(el.arena_index)
	ok(absf(nel - calc_el * (1.0 - resist)) < 0.01 and resist > 0.0, "T2.7 la resistencia de élite (%.0f%%) se refleja en el número (%.2f)" % [resist * 100.0, nel])
	ok(absf((el.max_hp - el.hp) - nel) < 0.01, "T2.8 y coincide con la vida realmente perdida")
	_dispose(el)
	_dispose(e)


# ============================================================================ T3 sobredaño
func _t3_overkill() -> void:
	var pl = GameState.player
	var e: Enemy = await _spawn("thief", pl.global_position + Vector3(5, 0, 2), 3000.0)
	var neighbor: Enemy = await _spawn("thief", pl.global_position + Vector3(5.8, 0, 2), 3000.0)
	e.hp = 300.0
	_calm()
	Feedback.reset()
	var n_hp := neighbor.hp
	var killed: bool = e.take_damage(5000.0, {"src": "slam", "element": "phys"})
	var ev: Dictionary = _events()[0]
	ok(killed and e.hp <= 0.0 and not e.alive, "T3.1 el golpe de 5000 mata al enemigo con 300 de vida")
	ok(ev["text"] == "5.000" and absf(float(ev["dmg"]) - 5000.0) < 0.001, "T3.2 el número muestra '5.000', no '300' (texto: %s)" % ev["text"])
	ok(absf(float(ev["applied"]) - 300.0) < 0.001, "T3.3 el registro distingue daño mostrado (5000) de vida realmente quitada (300)")
	ok(neighbor.hp == n_hp, "T3.4 el exceso no se transfiere a otros enemigos")
	var lbl := _last_label(e)
	ok(not lbl.is_empty() and (lbl["node"] as Label3D).text == "5.000", "T3.5 la etiqueta en pantalla dice 5.000")
	ok(e.hp == 0.0, "T3.6 la vida queda exactamente en 0")
	# sobredaño con crítico y masivo
	var e2: Enemy = await _spawn("thief", pl.global_position + Vector3(5, 0, -2), 3000.0)
	e2.hp = 10.0
	Feedback.reset()
	e2.take_damage(2750000.0, {"src": "slam", "crit": true})
	var ev2: Dictionary = _events()[0]
	ok(ev2["text"] == "2.750.000!" and ev2["massive"], "T3.7 2.750.000 crítico masivo sobre 10 de vida muestra '2.750.000!'")
	_dispose(neighbor)


# ============================================================================ T4 explosiones y cadenas
func _t4_explosions() -> void:
	var pl = GameState.player
	var center: Vector3 = pl.global_position + Vector3(8, 0, 0)
	var group: Array = []
	for i in 6:
		var off := Vector3(cos(TAU * float(i) / 6.0), 0, sin(TAU * float(i) / 6.0)) * (1.0 + 0.5 * float(i % 3))
		group.append(await _spawn("thief", center + off))
	var far: Enemy = await _spawn("thief", center + Vector3(30, 0, 0))
	_calm()
	Feedback.reset()
	AudioManager.reset_combat_stats()
	var hp_before: Array = group.map(func(g): return g.hp)
	var far_hp := far.hp
	var dmg := 120.0
	var rad := 5.0
	var radius := rad * (1.0 + b_s("explo_rad"))
	var hits := Combat.enemies_in_radius(center, radius)
	var scaled := dmg * (1.0 + b_s("explosion_pow"))
	var expected: Dictionary = {}
	for h in hits:
		expected[h.get_instance_id()] = float(Combat.calc(h, scaled, {"src": "explosion", "no_crit": true, "flat": false, "proc": false, "area_hits": hits.size(), "element": "fire"})["damage"])
	Combat.explode(center, rad, dmg)
	var evs := _events()
	var extra: Array = hits.filter(func(h): return not group.has(h))
	if not extra.is_empty():
		info("T4 enemigo ajeno dentro del radio: %s" % str(extra.map(func(x): return str(x.name))))
	var all_in := group.all(func(g): return hits.has(g))
	ok(evs.size() == hits.size() and all_in, "T4.1 la explosión genera un evento por enemigo afectado (%d eventos, %d afectados, %d del grupo incluidos)" % [evs.size(), hits.size(), group.size()])
	var per_ok := 0
	var texts_ok := 0
	for i in group.size():
		var g: Enemy = group[i]
		var lost: float = float(hp_before[i]) - g.hp
		var want: float = expected.get(g.get_instance_id(), -1.0)
		if absf(lost - want) < maxf(0.01, want * 1e-9):
			per_ok += 1
		var lbl := _last_label(g)
		if not lbl.is_empty() and (lbl["node"] as Label3D).text == Feedback.fmt(want):
			texts_ok += 1
	ok(per_ok == 6, "T4.2 cada enemigo pierde exactamente el daño esperado (%d/6)" % per_ok)
	ok(texts_ok == 6, "T4.3 cada enemigo muestra su propio número exacto (%d/6)" % texts_ok)
	ok(far.hp == far_hp and _last_label(far).is_empty(), "T4.4 el enemigo fuera del radio no recibe daño ni número")
	ok(evs.all(func(x): return x["kind"] == "aoe"), "T4.5 los números de área usan el estilo de área")
	var snd := AudioManager.combat_log.filter(func(x): return x["played"])
	var expl := snd.filter(func(x): return x["name"] == "explosion")
	var hitsn := snd.filter(func(x): return String(x["name"]).begins_with("hit_"))
	ok(expl.size() == 1 and hitsn.size() == 0, "T4.6 una sola explosión sonora, sin 6 golpes extra (explosión %d, golpes %d)" % [expl.size(), hitsn.size()])
	# cadena de rayos: cada salto muestra su daño
	var line: Array = []
	var cpos: Vector3 = pl.global_position + Vector3(-8, 0, 6)
	for i in 4:
		line.append(await _spawn("thief", cpos + Vector3(float(i) * 3.0, 0, 0)))
	_calm()
	Feedback.reset()
	var h0: Array = line.map(func(g): return g.hp)
	Combat.chain_lightning(line[0], 100.0, 3)
	var cev := _events().filter(func(x): return x["src"] == "chain")
	var csum_ok := cev.size() == 3
	for i in cev.size():
		var lost2: float = float(h0[i + 1]) - (line[i + 1] as Enemy).hp
		if absf(lost2 - float(cev[i]["dmg"])) > 0.01:
			csum_ok = false
	ok(csum_ok, "T4.7 cadena: 3 saltos, cada número = daño aplicado (%d eventos)" % cev.size())
	ok(float(cev[0]["dmg"]) > float(cev[1]["dmg"]) and float(cev[1]["dmg"]) > float(cev[2]["dmg"]), "T4.8 el daño decae por salto y el número lo refleja")
	for g in group:
		_dispose(g)
	for g in line:
		_dispose(g)
	_dispose(far)


func b_s(k: String) -> float:
	return GameState.build.s(k)


# ============================================================================ T5 sin duplicados al matar
func _t5_kills_no_dupes() -> void:
	var pl = GameState.player
	var e: Enemy = await _spawn("thief", pl.global_position + Vector3(6, 0, 4), 500.0)
	e.hp = 50.0
	_calm()
	Feedback.reset()
	AudioManager.reset_combat_stats()
	var r1: bool = e.take_damage(100.0, {"src": "slam"})
	var r2: bool = e.take_damage(100.0, {"src": "slam"})      # mismo fotograma, ya muerto
	var r3: bool = e.take_damage(100.0, {"src": "burn", "element": "fire"})
	e._tick_status(0.6)
	var evs := _events()
	ok(r1 and not r2 and not r3, "T5.1 solo el primer golpe mata; los siguientes no cuentan")
	ok(evs.size() == 1 and evs[0]["killed"], "T5.2 un solo evento/número para la muerte (%d eventos)" % evs.size())
	var snd := AudioManager.combat_log.filter(func(x): return x["played"])
	var kills := snd.filter(func(x): return x["name"] == "kill")
	var other := snd.filter(func(x): return x["name"] != "kill")
	ok(kills.size() == 1 and other.size() == 0, "T5.3 un solo sonido de muerte y ningún golpe extra (kill %d, otros %d)" % [kills.size(), other.size()])
	var cnt := 0
	for d in fx._labels:
		if d["key"] == e.get_instance_id():
			cnt += 1
	ok(cnt == 1, "T5.4 un solo número vivo en el enemigo muerto (%d)" % cnt)
	# muerte de jefe: sonido propio y fuerte
	var boss: Enemy = await _spawn("boss", pl.global_position + Vector3(-6, 0, 4), 100000.0)
	AudioManager.reset_combat_stats()
	_calm()
	boss.take_damage(10.0, {"src": "slam"})
	var hb := AudioManager.combat_log.filter(func(x): return x["played"])
	ok(hb.size() >= 1 and hb[0]["name"] == "hit_boss", "T5.5 golpear a un jefe suena 'hit_boss' (%s)" % (str(hb[0]["name"]) if hb.size() > 0 else "nada"))
	await _secs(0.15)
	AudioManager.reset_combat_stats()
	boss.hp = 5.0
	boss.invuln_t = 0.0
	boss.take_damage(500.0, {"src": "slam"})
	var kb := AudioManager.combat_log.filter(func(x): return x["played"])
	ok(kb.size() == 1 and kb[0]["name"] == "kill_boss", "T5.6 matar a un jefe suena 'kill_boss' una vez")
	# acciones silenciosas no generan números ni sonidos
	var e3: Enemy = await _spawn("thief", pl.global_position + Vector3(6, 0, -4))
	Feedback.reset()
	AudioManager.reset_combat_stats()
	e3.take_damage(0.0, {"src": "push", "silent": true, "knock": Vector3(2, 0, 0)})
	e3.take_damage(0.0, {"src": "stun", "silent": true, "stagger": 0.4})
	ok(_events().is_empty() and AudioManager.combat_log.is_empty(), "T5.7 empuje/aturdimiento sin daño no generan número ni sonido")
	# inmunidad: avisa pero no cuenta como daño ni suena
	e3.invuln_t = 1.0
	_calm()
	AudioManager.reset_combat_stats()
	var hp_i := e3.hp
	e3.take_damage(999.0, {"src": "slam"})
	e3.take_damage(999.0, {"src": "slam"})
	var inm := 0
	for d in fx._labels:
		if d["key"] == e3.get_instance_id():
			inm += 1
	ok(e3.hp == hp_i and inm == 1 and AudioManager.combat_log.is_empty(), "T5.8 inmune: un único '¡INMUNE!', sin daño ni sonido")
	e3.invuln_t = 0.0
	_dispose(e3)


# ============================================================================ T6 saturación de sonido
func _t6_sound_saturation() -> void:
	var pl = GameState.player
	var crowd: Array = []
	for i in 8:
		crowd.append(await _spawn("thief", pl.global_position + Vector3(3.0 + float(i % 4) * 1.4, 0, -3.0 + floorf(float(i) / 4.0) * 2.0)))
	await _secs(0.3)
	AudioManager.reset_combat_stats()
	_calm()
	var hits := 0
	var max_active := 0
	for f in 150:
		for k in 8:
			var e: Enemy = crowd[k]
			var r := randf()
			var info := {"src": "melee", "crit": r < 0.12}
			if r > 0.8:
				info["element"] = ["fire", "ice", "shock"][randi() % 3]
			e.take_damage(40.0 + randf() * 30.0, info)
			hits += 1
		max_active = maxi(max_active, AudioManager.combat_active_voices())
		await get_tree().process_frame
	var played := AudioManager.combat_log.filter(func(x): return x["played"])
	var dropped := AudioManager.combat_log.filter(func(x): return not x["played"])
	info("T6 impactos %d, sonidos reproducidos %d, descartados %d, voces máx. %d" % [hits, played.size(), dropped.size(), max_active])
	ok(max_active <= AudioManager.COMBAT_POOL, "T6.1 voces simultáneas ≤ %d (máx. observado %d)" % [AudioManager.COMBAT_POOL, max_active])
	# ventana deslizante de 100 ms
	var worst := 0
	for i in played.size():
		var n := 0
		for j in range(i, played.size()):
			if float(played[j]["t"]) - float(played[i]["t"]) <= AudioManager.COMBAT_WINDOW:
				n += 1
			else:
				break
		worst = maxi(worst, n)
	var cap_w := AudioManager.COMBAT_BUDGET + AudioManager.COMBAT_BUDGET_PRIO
	ok(worst <= cap_w, "T6.2 nunca más de %d sonidos nuevos por ventana de 100 ms (observado %d)" % [cap_w, worst])
	ok(played.size() < hits * 0.5 and dropped.size() > 0, "T6.3 el limitador recorta la avalancha (%d de %d impactos suenan)" % [played.size(), hits])
	# prioridad: los críticos se conservan más que los golpes normales
	var crits_p := played.filter(func(x): return String(x["name"]).begins_with("crit")).size()
	var crits_d := dropped.filter(func(x): return String(x["name"]).begins_with("crit")).size()
	var norm_p := played.filter(func(x): return String(x["name"]).begins_with("hit_") and not ["hit_fire", "hit_ice", "hit_shock"].has(x["name"])).size()
	var norm_d := dropped.filter(func(x): return String(x["name"]).begins_with("hit_") and not ["hit_fire", "hit_ice", "hit_shock"].has(x["name"])).size()
	var crit_rate := float(crits_p) / maxf(1.0, float(crits_p + crits_d))
	var norm_rate := float(norm_p) / maxf(1.0, float(norm_p + norm_d))
	ok(crit_rate >= norm_rate, "T6.4 la prioridad conserva más críticos (%.0f%%) que golpes normales (%.0f%%)" % [crit_rate * 100.0, norm_rate * 100.0])
	# variación natural de tono y volumen
	var pitches: Array = played.filter(func(x): return String(x["name"]).begins_with("hit_")).map(func(x): return float(x["pitch"]))
	var dbs: Array = played.filter(func(x): return String(x["name"]).begins_with("hit_")).map(func(x): return float(x["db"]))
	var variants := {}
	for x in played:
		variants[x["name"]] = true
	if pitches.size() > 3:
		ok(pitches.min() >= 0.8 and pitches.max() <= 1.25 and pitches.max() - pitches.min() > 0.04, "T6.5 tono variado dentro de límites naturales (%.3f–%.3f)" % [pitches.min(), pitches.max()])
		ok(dbs.max() - dbs.min() > 1.0 and dbs.max() - dbs.min() < 14.0, "T6.6 volumen variado sin extremos (%.1f dB de rango)" % (dbs.max() - dbs.min()))
	else:
		ok(false, "T6.5 muestras de tono insuficientes")
	ok(variants.size() >= 4, "T6.7 se usan varios sonidos distintos (%d)" % variants.size())
	# antirrepetición: el mismo sonido no se dispara con menos de 15 ms de separación
	var last: Dictionary = {}
	var rep := 0
	for x in played:
		if last.has(x["name"]) and float(x["t"]) - float(last[x["name"]]) < 0.014:
			rep += 1
		last[x["name"]] = x["t"]
	ok(rep == 0, "T6.8 sin disparos idénticos en menos de 15 ms (%d)" % rep)
	for g in crowd:
		_dispose(g)


# ============================================================================ T7 legibilidad con muchos enemigos
func _t7_many_enemies() -> void:
	var pl = GameState.player
	var cam: Camera3D = get_viewport().get_camera_3d()
	var crowd: Array = []
	for i in 36:
		var ang := TAU * float(i) / 36.0
		var rad := 4.0 + float(i % 3) * 2.5
		crowd.append(await _spawn("thief", pl.global_position + Vector3(cos(ang), 0, sin(ang)) * rad))
	_calm()
	fx.reset_number_stats()
	Feedback.reset()
	var cap: int = fx.number_cap()
	var max_live := 0
	var crit_events := 0
	var max_overlap := 0.0
	var overlap_sum := 0.0
	var samples := 0
	var shot := false
	for f in 150:
		for k in 36:
			if (k + f) % 4 != 0:
				continue
			var e: Enemy = crowd[k]
			var c := randf() < 0.1
			e.take_damage((300.0 if c else 60.0) * (1.0 + randf()), {"src": "slam", "crit": c, "aoe": randf() < 0.3})
			crit_events += 1 if c else 0
		max_live = maxi(max_live, fx.live_number_count())
		if f > 20 and f % 10 == 0 and cam != null:
			var ov := _overlap_fraction(cam)
			max_overlap = maxf(max_overlap, ov)
			overlap_sum += ov
			samples += 1
		if f == 90 and not shot:
			shot = true
			await _shot("T7_muchos_enemigos")
		await get_tree().process_frame
	info("T7 vivos máx %d / tope %d · solapamiento medio %.2f, máximo %.2f · números nuevos %d, agrupados %d, descartados %d, expulsados %d" % [
		max_live, cap, overlap_sum / maxf(1.0, float(samples)), max_overlap, fx.num_stats["new"], fx.num_stats["merged"], fx.num_stats["dropped"], fx.num_stats["evicted"]])
	ok(max_live <= cap, "T7.1 números vivos ≤ tope (%d ≤ %d)" % [max_live, cap])
	var crit_ev := _events().filter(func(x): return x["kind"] == "crit")
	var crit_shown := crit_ev.filter(func(x): return x["number"] != "dropped")
	ok(crit_ev.size() > 0 and crit_shown.size() == crit_ev.size(), "T7.2 ningún crítico se pierde bajo saturación (%d/%d visibles)" % [crit_shown.size(), crit_ev.size()])
	ok(overlap_sum / maxf(1.0, float(samples)) < 0.35, "T7.3 solapamiento medio de rectángulos de texto < 35%% (%.0f%%)" % (100.0 * overlap_sum / maxf(1.0, float(samples))))
	# conservación de información: lo no mostrado como número propio se suma a otro o se cuenta como descartado
	var sum_events := 0.0
	for x in _events():
		sum_events += float(x["dmg"])
	var stats_total: int = int(fx.num_stats["new"]) + int(fx.num_stats["merged"]) + int(fx.num_stats["dropped"])
	ok(stats_total == _events().size(), "T7.4 cada impacto queda contabilizado como nuevo/agrupado/descartado (%d = %d)" % [stats_total, _events().size()])
	# tamaño acotado
	var sizes_ok := true
	for d in fx._labels:
		var s: float = (d["node"] as Label3D).scale.x
		if s > fx.NUM_MAX_SCALE * fx.number_size * 1.5 or s < 0.1:
			sizes_ok = false
	ok(sizes_ok, "T7.5 todos los tamaños dentro de los límites")
	var huge: Dictionary = Feedback.classify(1.0e18, {"crit": true}, 100.0)
	var tiny: Dictionary = Feedback.classify(1.0, {}, 100.0)
	ok(float(huge["scale"]) <= 2.0 and float(tiny["scale"]) >= 0.7, "T7.6 la escala nunca crece sin límite (%.2f…%.2f)" % [float(tiny["scale"]), float(huge["scale"])])
	for g in crowd:
		_dispose(g)
	await _secs(1.2)


## Fracción media de la superficie de cada número vivo cubierta por otros (rectángulos aproximados en pantalla).
func _overlap_fraction(cam: Camera3D) -> float:
	var rects: Array = []
	for d in fx._labels:
		var l: Label3D = d["node"]
		if not l.visible or cam.is_position_behind(l.global_position):
			continue
		var sc := l.scale.x
		var w_m: float = float(l.text.length()) * 0.55 * fx.NUM_FONT * fx.NUM_PIXEL * sc
		var h_m: float = fx.NUM_FONT * fx.NUM_PIXEL * sc
		var p0 := cam.unproject_position(l.global_position)
		var right := cam.global_transform.basis.x
		var up := cam.global_transform.basis.y
		var p1 := cam.unproject_position(l.global_position + right * w_m)
		var p2 := cam.unproject_position(l.global_position + up * h_m)
		var w := absf(p1.x - p0.x)
		var h := absf(p2.y - p0.y)
		rects.append({"r": Rect2(p0.x - w * 0.5, p0.y - h * 0.5, w, h), "prio": d["prio"]})
	if rects.size() < 2:
		return 0.0
	var tot := 0.0
	for i in rects.size():
		var ri: Rect2 = rects[i]["r"]
		var covered := 0.0
		for j in rects.size():
			if i == j:
				continue
			# solo cuenta quien tapa con igual o mayor prioridad (los importantes quedan encima)
			var inter: Rect2 = ri.intersection(rects[j]["r"])
			covered = maxf(covered, inter.get_area() / maxf(1.0, ri.get_area()))
		tot += covered
	return tot / float(rects.size())


# ============================================================================ T8 rendimiento
func _t8_performance() -> void:
	# a) coste por evento (CPU de escritorio; un móvil es varias veces más lento: se informa, no se promete)
	var pl = GameState.player
	var e: Enemy = await _spawn("thief", pl.global_position + Vector3(5, 0, 5))
	Feedback.record = false
	AudioManager.record_combat = false
	var n := 3000
	_calm()
	var t0 := Time.get_ticks_usec()
	for i in n:
		e.take_damage(55.0 + float(i % 7), {"src": "melee", "crit": i % 9 == 0})
		if i % 6 == 0:
			fx._update_labels(0.016)
	var per := float(Time.get_ticks_usec() - t0) / float(n)
	info("T8 coste medio por impacto completo (daño+número+sonido): %.1f µs" % per)
	ok(per < 400.0, "T8.1 coste por impacto < 400 µs en esta máquina (%.1f µs)" % per)
	# b) reutilización de objetos: tras la tormenta no hay más nodos que antes
	var nodes_before := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var pool_before: int = fx._label_pool.size()
	for i in 4000:
		e.take_damage(77.0, {"src": "melee", "crit": i % 5 == 0})
		if i % 5 == 0:
			fx._update_labels(0.016)
	var nodes_after := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var pool_after: int = fx._label_pool.size()
	ok(pool_after <= fx.number_cap() + 2, "T8.2 el pool de etiquetas no supera el tope (%d ≤ %d)" % [pool_after, fx.number_cap() + 2])
	ok(nodes_after - nodes_before <= 4, "T8.3 4000 impactos más no crean nodos nuevos (+%d)" % (nodes_after - nodes_before))
	# c) coste de CPU de la función por fotograma bajo 360 impactos/s (el render por software de xvfb
	#    domina el tiempo total de fotograma, así que se mide solo el código del sistema)
	var cpu: Array = []
	for f in 90:
		var t1 := Time.get_ticks_usec()
		for k in 6:
			e.take_damage(60.0, {"src": "melee", "crit": k == 0})
		cpu.append(float(Time.get_ticks_usec() - t1) / 1000.0)
		await get_tree().process_frame
	var avg := 0.0
	var worst_f := 0.0
	for s2 in cpu:
		avg += s2
		worst_f = maxf(worst_f, s2)
	avg /= float(cpu.size())
	info("T8 CPU del sistema bajo 360 impactos/s: %.2f ms/fotograma de media, %.2f ms el peor (PC; un móvil será varias veces más lento)" % [avg, worst_f])
	ok(avg < 1.5, "T8.4 coste medio < 1,5 ms por fotograma a 360 impactos/s (%.2f ms)" % avg)
	Feedback.record = true
	AudioManager.record_combat = true
	_dispose(e)


# ============================================================================ T9 ajustes
func _t9_settings() -> void:
	var pl = GameState.player
	var e: Enemy = await _spawn("thief", pl.global_position + Vector3(5, 0, -5))
	# activar/desactivar números
	SaveSystem.set_setting("damage_numbers", false)
	fx.apply_quality()
	_calm()
	Feedback.reset()
	e.take_damage(100.0, {"src": "slam"})
	ok(_last_label(e).is_empty() and _events()[0]["number"] == "off", "T9.1 con los números desactivados no aparece ninguno (el daño sí se aplica)")
	SaveSystem.set_setting("damage_numbers", true)
	# tamaño
	SaveSystem.set_setting("number_size", 0.6)
	fx.apply_quality()
	_calm()
	e.take_damage(100.0, {"src": "slam"})
	var base_small: float = _last_label(e)["base"]
	SaveSystem.set_setting("number_size", 1.6)
	fx.apply_quality()
	_calm()
	e.take_damage(100.0, {"src": "slam"})
	var base_big: float = _last_label(e)["base"]
	ok(absf(base_big / base_small - 1.6 / 0.6) < 0.2, "T9.2 el ajuste de tamaño escala los números (×%.2f entre 60%% y 160%%)" % (base_big / base_small))
	SaveSystem.set_setting("number_size", 1.0)
	# reducir efectos
	var cap_normal: int = fx.number_cap()
	SaveSystem.set_setting("reduce_fx", true)
	fx.apply_quality()
	ok(fx.number_cap() < cap_normal, "T9.3 'reducir efectos' baja el tope de números (%d → %d)" % [cap_normal, fx.number_cap()])
	SaveSystem.set_setting("reduce_fx", false)
	fx.apply_quality()
	# volúmenes reales 0–100 %
	var ok_bus := true
	for pct in [0, 25, 50, 80, 100]:
		SaveSystem.set_setting("combat_sfx", float(pct) / 100.0)
		SaveSystem.set_setting("music", float(pct) / 100.0)
		AudioManager.apply_volumes()
		var ci := AudioServer.get_bus_index("Combat")
		var mi := AudioServer.get_bus_index("Music")
		if pct == 0:
			ok_bus = ok_bus and AudioServer.is_bus_mute(ci) and AudioServer.is_bus_mute(mi)
		else:
			var want := linear_to_db(float(pct) / 100.0)
			ok_bus = ok_bus and absf(AudioServer.get_bus_volume_db(ci) - want) < 0.01 and absf(AudioServer.get_bus_volume_db(mi) - want) < 0.01 \
				and not AudioServer.is_bus_mute(ci)
	ok(ok_bus, "T9.4 los buses Combat y Music siguen el porcentaje 0/25/50/80/100 (dB reales, 0 = silencio)")
	# independencia: combate al 30 %, música al 90 %
	SaveSystem.set_setting("combat_sfx", 0.3)
	SaveSystem.set_setting("music", 0.9)
	AudioManager.apply_volumes()
	var d_combat := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Combat"))
	var d_music := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music"))
	ok(absf(d_combat - linear_to_db(0.3)) < 0.01 and absf(d_music - linear_to_db(0.9)) < 0.01 and d_combat < d_music, "T9.5 combate y música se ajustan por separado (%.1f dB / %.1f dB)" % [d_combat, d_music])
	# con combate al 0 % no se reproduce ningún sonido de combate
	SaveSystem.set_setting("combat_sfx", 0.0)
	AudioManager.apply_volumes()
	AudioManager.reset_combat_stats()
	e.take_damage(100.0, {"src": "slam"})
	ok(AudioManager.combat_log.all(func(x): return not x["played"]), "T9.6 con efectos de combate al 0 % no se reproduce nada")
	SaveSystem.set_setting("combat_sfx", 0.85)
	SaveSystem.set_setting("music", 0.7)
	AudioManager.apply_volumes()
	# el menú de ajustes expone los controles
	var sm = load("res://scripts/ui/settings_menu.gd").new()
	main._ov_root().add_child(sm)
	await _frames(4)
	var labels: Array = []
	for l in sm.find_children("*", "Label", true, false):
		labels.append((l as Label).text)
	var sliders: Array = sm.find_children("*", "HSlider", true, false)
	var toggles: Array = sm.find_children("*", "CheckButton", true, false).map(func(c): return (c as CheckButton).text)
	ok(labels.has("Efectos de combate") and labels.has("Música") and labels.has("Tamaño de los números"), "T9.7 el menú muestra sliders de música, efectos de combate y tamaño de números")
	ok(toggles.has("Números de daño") and toggles.has("Reducir efectos con muchos impactos"), "T9.8 el menú muestra los interruptores de números y reducción de efectos")
	var pcts := labels.filter(func(s): return String(s).ends_with("%"))
	ok(pcts.size() >= 4, "T9.9 los sliders muestran porcentajes (%s)" % str(pcts))
	await _shot("T9_ajustes")
	sm.queue_free()
	_dispose(e)


# ============================================================================ T10 sin impacto, sin sonido
func _t10_no_hit_no_sound() -> void:
	var pl = GameState.player
	AudioManager.reset_combat_stats()
	Feedback.reset()
	_calm()
	# disparo/explosión al vacío: solo el sonido deliberado de explosión; sin golpes ni números
	var before: int = int(fx.num_stats["new"])
	Combat.explode(Vector3(40, 0, 40), 4.0, 100.0)
	var snd := AudioManager.combat_log.filter(func(x): return x["played"] or x["why"] != "")
	var impact := snd.filter(func(x): return String(x["name"]).begins_with("hit_") or String(x["name"]).begins_with("crit") or x["name"] == "kill")
	ok(impact.is_empty() and fx.num_stats["new"] == before and Feedback.event_log.is_empty(), "T10.1 explosión al vacío: sin números ni sonidos de impacto")
	ok(not Combat.player_hit(null, 10.0, {"src": "slam"}), "T10.2 golpear a nada no hace nada")
	var dead: Enemy = await _spawn("thief", pl.global_position + Vector3(7, 0, 7), 100.0)
	dead.take_damage(1000.0, {"src": "slam"})
	Feedback.reset()
	AudioManager.reset_combat_stats()
	dead.take_damage(1000.0, {"src": "slam"})
	Combat.player_hit(dead, 100.0, {"src": "slam"})
	ok(Feedback.event_log.is_empty() and AudioManager.combat_log.is_empty(), "T10.3 golpear a un enemigo ya muerto no genera número ni sonido")
	# desactivar números no cambia el daño aplicado
	var e: Enemy = await _spawn("thief", pl.global_position + Vector3(7, 0, -7))
	SaveSystem.set_setting("damage_numbers", false)
	fx.apply_quality()
	var o := {"src": "slam", "no_crit": true, "proc": false}
	var exp := float(Combat.calc(e, 50.0, o)["damage"])
	var h := e.hp
	Combat.player_hit(e, 50.0, o)
	ok(absf((h - e.hp) - exp) < 0.01, "T10.4 con los números desactivados el daño aplicado es el mismo")
	SaveSystem.set_setting("damage_numbers", true)
	fx.apply_quality()
	_dispose(e)


# ============================================================================ T11 galería de estilos (captura)
func _t11_gallery() -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	var pl = GameState.player
	var fwd: Vector3 = -cam.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right: Vector3 = cam.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	var cases := [
		{"d": 87.0, "i": {"src": "slam"}, "k": "normal"},
		{"d": 1250.0, "i": {"src": "slam", "crit": true}, "k": "crit"},
		{"d": 342.0, "i": {"src": "melee", "element": "fire"}, "k": "elem"},
		{"d": 342.0, "i": {"src": "melee", "element": "ice"}, "k": "elem"},
		{"d": 342.0, "i": {"src": "melee", "element": "shock"}, "k": "elem"},
		{"d": 156.0, "i": {"src": "explosion", "element": "fire", "aoe": true}, "k": "aoe"},
		{"d": 24.0, "i": {"src": "burn", "element": "fire"}, "k": "dot"},
		{"d": 18450.0, "i": {"src": "slam"}, "k": "normal"},
		{"d": 2750000.0, "i": {"src": "slam", "crit": true}, "k": "crit"},
		{"d": 480.0, "i": {"src": "execute", "crit": true}, "k": "exec"},
	]
	var es: Array = []
	for i in cases.size():
		var col := float(i) - 4.5
		var pos: Vector3 = pl.global_position + fwd * (9.0 + float(i % 2) * 3.0) + right * col * 2.1
		es.append(await _spawn("thief", pos))
	_calm()
	Feedback.reset()
	var kinds_ok := true
	for i in cases.size():
		(es[i] as Enemy).take_damage(float(cases[i]["d"]), cases[i]["i"])
	for i in cases.size():
		var ev: Dictionary = _events()[i]
		if ev["kind"] != cases[i]["k"]:
			kinds_ok = false
			info("T11 caso %d esperado %s, obtenido %s" % [i, cases[i]["k"], ev["kind"]])
	ok(kinds_ok, "T11.1 cada tipo de daño recibe su estilo (normal, crítico, elemental x3, área, periódico, masivo, ejecución)")
	var cols: Array = []
	for d in fx._labels:
		cols.append((d["node"] as Label3D).modulate)
	await _frames(3)
	fx.set_process(false)          # congela la animación en su punto más legible para la captura
	await _shot("T11_galeria_estilos")
	fx.set_process(true)
	for e in es:
		_dispose(e)
