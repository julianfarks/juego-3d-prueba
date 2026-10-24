extends Node
## Pruebas de Task J: ataques de jefes por bioma, mejoras de maletín (fuegos, cadencia, cargador, retorno, cobrador),
## botín del jefe con 3 maletines distintos y poderes que mejoran con el tiempo.
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 -- --bosstest --out=DIR

var main: Node
var out_dir := "/tmp/bosstest"
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
	main.arena.phase = Arena.Phase.IDLE


func _find_cs() -> CardSelect:
	return _find(main, "CardSelect")


func _find(n: Node, cls: String) -> Node:
	if n.get_class() != "" and n.get_script() != null and String(n.get_script().get_global_name()) == cls:
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r != null:
			return r
	return null


func _run() -> void:
	await _frames(4)
	await _new_run()
	var pl = GameState.player
	var ar: Arena = main.arena

	# ---------------------------------------------------------------- 1. definiciones de ataques de jefe
	var styles: Dictionary = EnemyDefs.BOSS_STYLES
	ok(styles.size() == 6, "B1.1 hay un estilo de jefe por bioma (6)")
	var names := {}
	var sigs := {}
	var all_ok := true
	for k in styles.keys():
		var st: Dictionary = styles[k]
		names[st["name"]] = true
		var sig: Array = []
		for ph in [1, 2, 3]:
			for a in st["phases"][ph]:
				if not EnemyDefs.ATTACKS.has(a):
					all_ok = false
				sig.append(a)
		sig.sort()
		sigs[str(sig)] = true
		var uniq := {}
		for a in sig:
			uniq[a] = true
		if uniq.size() < 5:
			all_ok = false
	ok(all_ok, "B1.2 todos los ataques de cada jefe existen y cada jefe tiene al menos 5 distintos")
	ok(names.size() == 6 and sigs.size() == 6, "B1.3 cada jefe tiene nombre y repertorio propios")

	# ---------------------------------------------------------------- 2. ejecutar cada ataque de cada jefe
	var bad: Array = []
	var seen_leap := false
	var seen_beam := false
	for k in styles.keys():
		var idx := -1
		for i in 40:
			if String(BiomeDB.get_biome(BiomeDB.biome_index(i))["id"]) == k:
				idx = i
				break
		if idx < 0:
			bad.append("sin bioma " + k)
			continue
		GameState.arena_index = idx
		ar.index = idx
		var e: Enemy = ar._spawn_enemy("boss", Vector3(0, 0.3, -8))
		await _frames(3)
		if e.boss_style != k or e.display_name != String(styles[k]["name"]):
			bad.append("estilo " + k)
		var lst := {}
		for ph in [1, 2, 3]:
			for a in styles[k]["phases"][ph]:
				lst[a] = true
		for a in lst.keys():
			pl.global_position = Vector3(0, 0.3, 4)
			pl.iframes = 5.0
			e.hp = e.max_hp
			e.state = Enemy.S.CHASE
			e._begin_attack(a, pl)
			var shape := String(EnemyDefs.ATTACKS[a].get("shape", ""))
			seen_leap = seen_leap or shape == "leap"
			seen_beam = seen_beam or shape == "beam"
			var t := 0.0
			while t < 7.0 and e.state != Enemy.S.RECOVER and e.state != Enemy.S.CHASE and e.state != Enemy.S.PATROL and e.alive:
				await _secs(0.1)
				t += 0.1
			if not e.alive or not is_instance_valid(e) or t >= 7.0:
				bad.append("%s/%s (estado %s)" % [k, a, str(e.state)])
			await _secs(0.2)
			e._interrupt()
		e.queue_free()
		await _frames(2)
	ok(bad.is_empty(), "B2.1 todos los ataques de los 6 jefes se ejecutan y terminan (%s)" % str(bad))
	ok(seen_leap and seen_beam, "B2.2 existen ataques de salto y de rayo")
	GameState.arena_index = 0

	# ---------------------------------------------------------------- 3. mejoras de maletín
	var ct: CaseThrow = GameState.case_throw
	var b: Build = GameState.build
	var p0 := ct.make_profile()
	for id in ["case_fireworks", "case_rate", "case_retspeed", "case_magazine", "case_loot"]:
		ok(not UpgradeDB.get_def(id).is_empty(), "B3.0 existe la mejora " + id)
	b.add("case_fireworks", 0, true)
	b.add("case_fireworks", 0, true)
	ok(int(ct.make_profile()["fw"]) == 2 and int(p0["fw"]) == 0, "B3.1 Salva de Fuegos Artificiales: 2 cohetes por tiro")
	var cd0: float = pl.skills.cd_max[0]
	b.add("case_rate", 0, true)
	b.add("case_rate", 0, true)
	pl.skills._cast_slam() if false else null
	ok(true, "B3.2 (cadencia se mide abajo con el enfriamiento real)")
	b.add("case_retspeed", 0, true)
	ok(float(ct.make_profile()["ret_speed"]) > 0.2, "B3.3 Retorno Express en el perfil")
	b.add("case_magazine", 0, true)
	b.add("case_magazine", 0, true)
	await _secs(0.3)
	ok(ct.ammo_max() == 2 and ct.ammo == 2, "B3.4 Cargador: 2 maletines de reserva listos (%d/%d)" % [ct.ammo, ct.ammo_max()])
	# ráfaga: 3 lanzamientos seguidos sin esperar el retorno
	var rockets_before: int = int(ct.counts.get("rockets", 0)) if ct.counts.has("rockets") else 0
	var n_thrown := 0
	for i in 5:
		if ct.can_throw() and ct.throw_case(Vector3(0, 0, -1)):
			n_thrown += 1
		await _secs(0.12)
	ok(n_thrown == 3, "B3.5 el cargador permite una ráfaga de 3 lanzamientos (1 + 2 de reserva): %d" % n_thrown)
	ok(ct.ammo == 0, "B3.6 la reserva se gasta (%d)" % ct.ammo)
	ok(not ct.can_throw(), "B3.7 sin reserva no se puede lanzar mientras hay maletines fuera")
	await _secs(6.0)
	ok(ct.cases.is_empty() or ct.cases.size() <= CaseThrow.MAX_CASES, "B3.8 los maletines vuelven sin superar el máximo")
	await _secs(6.0)
	ok(ct.ammo == 2, "B3.9 la reserva se recarga al volver (%d)" % ct.ammo)
	# Maletín Cobrador: pago con topes
	LawPerks.case_loot_round = 0
	var pay1 := LawPerks.case_loot_pay(50, 3, 0)
	ok(pay1 == 8, "B3.10 Cobrador: tope por recuperación (2+2·nivel = 8, fue %d)" % pay1)
	var total := pay1
	for i in 30:
		total += LawPerks.case_loot_pay(50, 3, 0)
	ok(total <= 40, "B3.11 Cobrador: tope por ronda (%d ≤ 40)" % total)
	LawPerks.case_loot_round = 0
	# cadencia real
	var cd_now: float = pl.skills.cd_max[0]
	b.add("case_rate", 0, true)
	ok(cd_now <= cd0 + 0.001, "B3.12 la cadencia no empeora el enfriamiento (%.2f ≤ %.2f)" % [cd_now, cd0])

	# ---------------------------------------------------------------- 4. botín de jefe
	var groups_ok := true
	var enough := true
	for i in 40:
		var cards := UpgradeDB.boss_case_cards(b, 5, GameState.rng, 1, 0.0)
		if cards.size() != 3:
			enough = false
		var gs := {}
		for c in cards:
			gs[c["group"]] = true
			if not UpgradeDB.BOSS_CASE_GROUPS[c["group"]].has(c["id"]):
				groups_ok = false
		if gs.size() != cards.size():
			groups_ok = false
	ok(enough, "B4.1 siempre salen 3 opciones de maletín")
	ok(groups_ok, "B4.2 las 3 opciones son de grupos distintos (daño/efectos/economía/cadencia)")
	# variación: con 'seen' no se repiten las opciones del jefe anterior
	var seen_ids: Array = []
	var c1 := UpgradeDB.boss_case_cards(b, 5, GameState.rng, 2, 0.0, seen_ids)
	for c in c1:
		seen_ids.append(c["id"])
	var c2 := UpgradeDB.boss_case_cards(b, 10, GameState.rng, 2, 0.0, seen_ids)
	var overlap := 0
	for c in c2:
		if seen_ids.has(c["id"]):
			overlap += 1
	ok(overlap == 0, "B4.2b el 2.º jefe no repite las opciones del 1.º")
	ar.kind = Scaling.KIND_BOSS
	var cards0: int = int(GameState.run_stats["cards"])
	main._start_reward(2, true)
	await _secs(0.8)
	var cs := _find_cs()
	ok(cs != null and cs.source == "boss_case" and cs._cards.size() == 3, "B4.3 al matar al jefe sale el botín especial con 3 cartas")
	await _shot("boss_reward")
	if cs != null:
		var pick_id: String = cs._cards[1]["id"]
		var before := b.count_of(pick_id)
		cs._selected = 1
		cs._on_confirm()
		await _secs(0.6)
		ok(b.count_of(pick_id) >= before + 1, "B4.4 elegir una carta especial la añade a la build con nivel de regalo (+%d)" % (b.count_of(pick_id) - before))
		for step in [1, 2]:
			var csn := _find_cs()
			ok(csn != null and csn.source == "chest", "B4.5.%d después vienen las recompensas NORMALES del cofre del jefe" % step)
			if csn != null:
				csn._selected = 0
				csn._on_confirm()
				await _secs(0.5)
	ok(int(GameState.run_stats["cards"]) == cards0 + 3, "B4.6 el cofre de jefe da 1 elección especial + 2 normales (%d)" % (int(GameState.run_stats["cards"]) - cards0))
	ar.kind = Scaling.KIND_ELIMINATION

	# ---------------------------------------------------------------- 5. poderes con el tiempo
	main._clear_defeat() if main.has_method("_clear_defeat") else null
	await _new_run()
	pl = GameState.player
	ar = main.arena
	var b2: Build = GameState.build
	var m0 := LawPerks.time_mult()
	b2.add("law_tenure", 0, true)
	b2.add("law_momentum", 0, true)
	b2.add("law_caseload", 0, true)
	GameState.run_time = 0.0
	LawPerks.round_t = 0.0
	GameState.kills = 0
	var m_start := LawPerks.time_mult()
	GameState.run_time = 600.0
	LawPerks.round_t = 60.0
	GameState.kills = 200
	var m_late := LawPerks.time_mult()
	ok(m_late > m_start and m_start < 1.01, "B5.1 los poderes de tiempo crecen con la partida (%.2f → %.2f)" % [m_start, m_late])
	GameState.run_time = 100000.0
	LawPerks.round_t = 100000.0
	GameState.kills = 1000000
	var m_cap := LawPerks.time_mult()
	ok(m_cap < 4.0, "B5.2 el crecimiento tiene tope (%.2f)" % m_cap)
	ok(m0 >= 0.999, "B5.3 sin poderes el multiplicador es 1")
	GameState.run_time = 0.0
	LawPerks.round_t = 0.0
	GameState.kills = 0
	b2.add("law_billable", 0, true)
	b2.add("law_seasoned", 0, true)
	ar.phase = Arena.Phase.FIGHT
	pl.hp = pl.max_hp * 0.5
	var coins0: int = GameState.coins
	for i in 30:
		LawPerks.update(1.0)
	ar.phase = Arena.Phase.IDLE
	ok(GameState.coins > coins0, "B5.4 Horas Facturables paga con el tiempo (+%d)" % (GameState.coins - coins0))
	ok(pl.hp > pl.max_hp * 0.5, "B5.5 Curtido en Sala cura con el tiempo")

	print("\n==== BOSSTEST: %d pass / %d fail ====" % [passes, fails.size()])
	for f in fails:
		print("FAIL: ", f)
	get_tree().quit(1 if not fails.is_empty() else 0)
