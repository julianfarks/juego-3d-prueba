extends Node
## Pruebas v0.11 (render real, entrada real): cofres por rendimiento y doble recompensa, 15 poderes nuevos y sus sinergias,
## economía, tienda ampliada, guardado y menú CÓDIGOS → DESARROLLADOR.
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 -- --lawtest --out=DIR [--only=perf,reward,...]

var main: Node
var out_dir := "/tmp/lawtest"
var only: Array = []
var fails: Array = []
var passes := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a.begins_with("--only="):
			only = a.substr(7).split(",")
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


func _pready() -> bool:
	var ar: Arena = main.arena
	return ar._portal != null and ar._portal.enabled


func _want(tag: String) -> bool:
	return only.is_empty() or only.has(tag)


# ------------------------------------------------------------------ utilidades de escenario
func _reset_build() -> void:
	GameState.build.reset(SaveSystem.data["meta"]["perm"])
	LawPerks.reset()
	LawPerks.forced_roll = -1.0
	GameState.build_changed.emit()


func _give(id: String, n := 1, rarity := 0) -> void:
	for i in n:
		GameState.build.add(id, rarity, true)
	GameState.build_changed.emit()


func _enter_round(idx := 0) -> void:
	Engine.time_scale = 1.0
	await main._begin_arena(idx, true)
	await _frames(10)
	var ar: Arena = main.arena
	ar.phase = Arena.Phase.IDLE
	ar._queue.clear()
	_clear_enemies()
	await _frames(4)


func _clear_enemies() -> void:
	for e in Combat.arena_enemies().duplicate():
		if is_instance_valid(e) and "invuln_t" in e and e.alive:
			e.invuln_t = 0.0
			e.take_damage(e.hp * 50.0 + 50.0, {"src": "boss_death", "silent": true})


func _hurt(frac_of_max: float) -> void:
	var pl = GameState.player
	pl.iframes = 0.0
	pl.hurt_iframes = 0.0
	pl.take_damage(pl.max_hp * frac_of_max, pl.global_position + Vector3(2, 0, 0), {})


func _dummy(pos_off := Vector3(4, 0, 0), kind := "thief") -> Enemy:
	var pl = GameState.player
	var e: Enemy = main.arena._spawn_enemy(kind, pl.global_position + pos_off)
	e.set_physics_process(false)
	e.velocity = Vector3.ZERO
	e.state = Enemy.S.CHASE
	e.invuln_t = 0.0
	return e


func _complete_round() -> void:
	var ar: Arena = main.arena
	ar.phase = Arena.Phase.FIGHT
	ar._complete()
	await _frames(6)


func _close_overlays() -> void:
	for o in main._overlays.duplicate():
		if is_instance_valid(o):
			o.queue_free()
	await _frames(3)


func _run() -> void:
	await _frames(4)
	var t := 0.0
	while main.state != main.St.LOBBY and t < 10.0:
		await _secs(0.1)
		t += 0.1
	await _secs(1.0)
	SaveSystem.set_setting("dev_unlocked", false)
	if _want("catalog"):
		_t_catalog()
	main._on_play()
	t = 0.0
	while main.state != main.St.RUN and t < 10.0:
		await _secs(0.1)
		t += 0.1
	await _secs(1.0)
	Config.dev_god_mode = false
	if _want("perf"):
		await _t_perf()
	if _want("reward"):
		await _t_reward()
	if _want("powers"):
		await _t_powers()
	if _want("econ"):
		await _t_econ()
	if _want("shop"):
		await _t_shop()
	if _want("save"):
		await _t_save()
	if _want("menu"):
		await _t_menu()
	print("[RESULT] ampliación judicial: %d ok, %d fallos" % [passes, fails.size()])
	for f in fails:
		print("  FALLO: ", f)
	get_tree().quit(1 if fails.size() > 0 else 0)


# ====================================================================== catálogo
func _t_catalog() -> void:
	var combat := ["law_demolisher", "law_return", "law_piercing", "law_double", "law_sentence", "law_objection_chain", "law_gavel_strike",
		"law_cutting_papers", "law_final_word", "law_procedural", "law_legal_dodge", "law_file_shield", "law_medic", "law_appeal", "law_immunity_shield"]
	var eco := ["law_win_fees", "law_vip_client", "law_advance_fee", "law_firm_interest", "law_negotiator", "law_efficiency"]
	var shop := LawCatalog.SHOP_GROUPS.keys()
	var all_ok := true
	for id in combat + eco + shop:
		var d := UpgradeDB.get_def(id)
		if d.is_empty():
			all_ok = false
			info("falta " + id)
			continue
		for r in 4:
			if (d["rarities"] as Array).has(r):
				var txt := UpgradeDB.describe(id, r)
				if txt.find("{") >= 0 or txt.strip_edges() == "":
					all_ok = false
					info("descripción rota %s r%d: %s" % [id, r, txt])
	ok(combat.size() == 15 and all_ok, "G1 los 15 poderes nuevos existen y sus descripciones se rellenan")
	ok(eco.size() == 6, "G2 las 6 mejoras económicas existen")
	ok(shop.size() >= 12, "G3 hay %d artículos exclusivos de tienda (≥12)" % shop.size())
	var syn_ids := ["law_case_duo", "law_paper_pierce", "law_dodge_chain", "law_medic_def", "law_crit_final", "law_fee_eff"]
	var found := 0
	for s in UpgradeDB.synergies():
		if syn_ids.has(s["id"]):
			found += 1
	ok(found == 6, "G4 las 6 sinergias nuevas están registradas (%d)" % found)
	# los artículos de tienda NUNCA salen en cofres
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var leaked := false
	for i in 400:
		for c in UpgradeDB.roll_cards(3, 0.3, i % 30, GameState.build, rng, 0):
			if (UpgradeDB.get_def(c["id"]).get("shop_only", false)):
				leaked = true
	ok(not leaked, "G5 400 cofres: ningún artículo exclusivo de tienda aparece en cofres")
	# los poderes nuevos sí salen en cofres
	var seen := {}
	for i in 600:
		for c in UpgradeDB.roll_cards(3, 0.3, 10 + i % 30, GameState.build, rng, 0):
			if String(c["id"]).begins_with("law_"):
				seen[c["id"]] = true
	ok(seen.size() >= 12, "G6 los poderes law_* aparecen en cofres (%d distintos)" % seen.size())
	# exclusión: la 2.ª tirada nunca repite lo ya elegido
	var bad := false
	for i in 200:
		var first := UpgradeDB.roll_cards(1, 0.0, 12, GameState.build, rng, 0)
		var second := UpgradeDB.roll_cards(3, 0.0, 12, GameState.build, rng, 0, [first[0]["id"]])
		for c in second:
			if c["id"] == first[0]["id"]:
				bad = true
	ok(not bad, "G7 200 cofres dobles: la 2.ª elección nunca repite la 1.ª")


# ====================================================================== rendimiento
func _t_perf() -> void:
	info("--- rendimiento ---")
	_reset_build()
	await _enter_round(0)
	var pl = GameState.player
	ok(absf(GameState.round_damage) < 0.001 and GameState.round_max_hp == pl.max_hp, "P0 la ronda empieza con daño 0 y vida máxima registrada")
	# sin daño
	LawPerks.forced_roll = 0.1
	await _complete_round()
	var ar: Arena = main.arena
	ok(bool(ar.perf_result["perfect"]) and ar.bonus_chest_wanted and ar._bchest != null, "P1 sin daño + tirada 0.1 → ronda perfecta y cofre adicional")
	ok(not _pready(), "P1b el portal espera a los DOS cofres")
	# una sola vez: repetir la evaluación no vuelve a tirar
	LawPerks.forced_roll = 0.99
	ar._evaluate_performance()
	ar._evaluate_performance()
	ok(ar.bonus_chest_wanted, "P2 la bonificación se comprueba UNA sola vez (repetir no la cambia)")
	# sin cofre extra con tirada alta
	await _enter_round(0)
	LawPerks.forced_roll = 0.9
	await _complete_round()
	ok(bool(ar.perf_result["perfect"]) and not ar.bonus_chest_wanted and ar._bchest == null, "P3 ronda perfecta con tirada 0.9 → sin cofre extra (conserva el cofre normal)")
	ok(ar._chest != null, "P3b el cofre normal sigue existiendo")
	# 15 % de daño
	await _enter_round(0)
	_hurt(0.15)
	LawPerks.forced_roll = 0.2
	await _complete_round()
	ok(bool(ar.perf_result["perfect"]) and ar.bonus_chest_wanted, "P4 perdiendo el 15%% de vida → cofre adicional (daño registrado %.1f)" % GameState.round_damage)
	# 25 % de daño en dos golpes del 12.5 % (no se cuenta doble)
	await _enter_round(0)
	_hurt(0.125)
	_hurt(0.125)
	var expect = pl.max_hp * 0.25
	ok(absf(GameState.round_damage - expect) < 0.5, "P5 dos golpes del 12.5%% suman %.1f (esperado %.1f), sin doble conteo" % [GameState.round_damage, expect])
	LawPerks.forced_roll = 0.0
	await _complete_round()
	ok(not bool(ar.perf_result["perfect"]) and not ar.bonus_chest_wanted, "P6 25%% de pérdida → sin bonificación aunque la tirada sea 0.0")
	# curarse no permite manipular el requisito
	await _enter_round(0)
	_hurt(0.15)
	pl.hp = pl.max_hp
	_hurt(0.10)
	LawPerks.forced_roll = 0.0
	await _complete_round()
	ok(not bool(ar.perf_result["perfect"]), "P7 15%% + curación total + 10%% = 25%% perdido: curarse no oculta el daño (%.1f)" % GameState.round_damage)
	# el escudo absorbe: no es vida perdida
	await _enter_round(0)
	pl.shield = 80.0
	pl.hp = pl.max_hp
	_hurt(0.5)
	ok(GameState.round_damage < 0.5, "P8 un golpe absorbido por el escudo no cuenta como vida perdida (%.2f)" % GameState.round_damage)
	# límite exacto 20 %
	await _enter_round(0)
	pl.shield = 0.0
	pl.hp = pl.max_hp
	_hurt(0.20)
	var r := LawPerks.evaluate(GameState.round_damage, GameState.round_max_hp, 0.0)
	ok(bool(r["perfect"]), "P9 exactamente el 20%% aún cuenta (≤20%%)")
	var r2 := LawPerks.evaluate(GameState.round_max_hp * 0.2001, GameState.round_max_hp, 0.0)
	ok(not bool(r2["perfect"]), "P9b 20.01%% ya no cuenta")
	# estadística de la tirada 50 %
	var n_ok := 0
	for i in 1000:
		if bool(LawPerks.evaluate(0.0, 100.0, float(i) / 1000.0)["bonus_chest"]):
			n_ok += 1
	ok(n_ok == 500, "P10 la probabilidad del cofre extra es exactamente el 50%% (%d/1000)" % n_ok)
	var n_dbl := 0
	for i in 1000:
		if LawPerks.roll_double(float(i) / 1000.0):
			n_dbl += 1
	ok(n_dbl == 500, "P11 la probabilidad del cofre doble es el 50%% (%d/1000)" % n_dbl)
	# Recompensa por Eficiencia: monedas solo si la ronda es perfecta
	_reset_build()
	_give("law_efficiency", 2)
	await _enter_round(3)
	GameState.coins = 0
	await _complete_round()
	var c_perfect := GameState.coins
	await _enter_round(3)
	GameState.coins = 0
	_hurt(0.5)
	await _complete_round()
	ok(c_perfect >= LawPerks.efficiency_coins(3) and GameState.coins < c_perfect, "P12 Recompensa por Eficiencia paga en ronda perfecta (%d $) y no con mucho daño (%d $)" % [c_perfect, GameState.coins])
	LawPerks.forced_roll = -1.0
	_reset_build()


# ====================================================================== cofres: doble recompensa
func _pick_current(idx_card := 0) -> Dictionary:
	var cs := _overlay_of(CardSelect) as CardSelect
	if cs == null:
		return {}
	cs._selected = clampi(idx_card, 0, cs._cards.size() - 1)
	var card: Dictionary = cs._cards[cs._selected]
	cs._on_confirm()
	await _secs(0.35)
	return card


func _t_reward() -> void:
	info("--- cofres y recompensas ---")
	_reset_build()
	await _enter_round(0)
	var b: Build = GameState.build
	var ar: Arena = main.arena
	# 1) cofre normal, tirada alta: UNA elección
	LawPerks.forced_roll = 0.9
	await _complete_round()
	var n0 := b.picks.size()
	info("R1 conexiones=%s" % str(ar.chest_opened.get_connections()))
	info("R1 antes: chest_taken=%s chest=%s" % [str(ar.chest_taken), str(ar._chest)])
	ar._open_chest(0)
	for k in 6:
		await _secs(0.25)
		info("R1 t=%.2f overlays=%d tree_paused=%s ts=%s" % [0.25 * (k + 1), main._overlays.size(), str(get_tree().paused), str(Engine.time_scale)])
	info("R1 overlays=%s fase=%s chest_taken=%s" % [str(main._overlays), str(main.arena.phase), str(ar.chest_taken)])
	ok(_overlay_of(CardSelect) != null, "R1 al abrir el cofre aparece la selección de recompensa")
	var title1 := (_overlay_of(CardSelect) as CardSelect)._title.text
	var c1 := await _pick_current()
	await _secs(0.5)
	ok(_overlay_of(CardSelect) == null and b.picks.size() == n0 + 1, "R2 tirada 0.9: una sola recompensa (%s → +%d)" % [title1, b.picks.size() - n0])
	ok(_pready(), "R2b sin cofre extra el portal se activa al abrir el cofre")
	# 2) cofre doble: DOS elecciones, la 2.ª distinta
	await _enter_round(0)
	LawPerks.forced_roll = 0.9
	await _complete_round()
	LawPerks.forced_roll = 0.1                 # la tirada del doble se hace al abrir el cofre
	var n1 := b.picks.size()
	ar._open_chest(0)
	await _secs(1.0)
	var t_a := (_overlay_of(CardSelect) as CardSelect)._title.text
	var ca := await _pick_current()
	await _secs(0.4)
	var cs2 := _overlay_of(CardSelect) as CardSelect
	ok(cs2 != null and cs2._title.text == "RECOMPENSA 2 DE 2" and t_a == "RECOMPENSA 1 DE 2", "R3 cofre doble: «%s» y luego «%s»" % [t_a, cs2._title.text if cs2 != null else "—"])
	var dup := false
	if cs2 != null:
		for c in cs2._cards:
			if c["id"] == ca["id"]:
				dup = true
	ok(not dup, "R4 la 2.ª elección no ofrece la mejora ya elegida (%s)" % String(ca.get("id", "")))
	var cb := await _pick_current()
	await _secs(0.4)
	ok(_overlay_of(CardSelect) == null and b.picks.size() == n1 + 2, "R5 cofre doble = exactamente 2 mejoras añadidas (+%d)" % (b.picks.size() - n1))
	# 3) cofre de jefe: 2 elecciones y NO una tercera aunque salga el doble
	await _enter_round(4)
	LawPerks.forced_roll = 0.9
	await _complete_round()
	LawPerks.forced_roll = 0.1
	var n2 := b.picks.size()
	var cards2: int = int(GameState.run_stats["cards"])
	ar._open_chest(2)
	await _secs(1.0)
	await _pick_current()          # botín ESPECIAL del jefe (3 categorías; da +1 nivel de regalo)
	await _secs(0.4)
	await _pick_current()          # 1.ª elección normal
	await _secs(0.4)
	await _pick_current()          # 2.ª elección normal
	await _secs(0.6)
	var dcards: int = int(GameState.run_stats["cards"]) - cards2
	ok(_overlay_of(CardSelect) == null and dcards == 3 and b.picks.size() <= n2 + 4, "R6 cofre de jefe + doble no se acumula: 1 especial + 2 normales = 3 elecciones (%d; mejoras +%d)" % [dcards, b.picks.size() - n2])
	# 4) cofre extra + cofre doble a la vez: cada cofre aplica sus propias reglas
	await _enter_round(0)
	LawPerks.forced_roll = 0.1
	await _complete_round()
	ok(ar.bonus_chest_wanted and ar._bchest != null, "R7 ronda perfecta con cofre extra")
	var n3 := b.picks.size()
	LawPerks.forced_roll = 0.9                 # el cofre principal: 1 elección
	ar._open_chest(0)
	await _secs(1.0)
	await _pick_current()
	await _secs(0.5)
	ok(b.picks.size() == n3 + 1 and not _pready(), "R8 el cofre principal dio 1 mejora y el portal sigue cerrado (falta el extra)")
	LawPerks.forced_roll = 0.1                 # el cofre extra: doble
	ar._open_bonus_chest()
	await _secs(1.0)
	await _pick_current()
	await _secs(0.4)
	await _pick_current()
	await _secs(0.6)
	ok(b.picks.size() == n3 + 3, "R9 el cofre extra (doble) dio 2 mejoras más: total +%d" % (b.picks.size() - n3))
	ok(_pready(), "R10 con los dos cofres abiertos el portal se activa")
	ar._open_bonus_chest()
	ar._open_chest(0)
	await _secs(1.0)
	ok(_overlay_of(CardSelect) == null and b.picks.size() == n3 + 3, "R11 volver a abrir un cofre ya abierto no da nada")
	LawPerks.forced_roll = -1.0
	await _close_overlays()
	_reset_build()


# ====================================================================== poderes
func _calc(e: Enemy) -> float:
	return float(Combat.calc(e, 100.0, {"src": "slam", "no_crit": true, "flat": false})["damage"])


func _t_powers() -> void:
	info("--- poderes ---")
	Config.dev_god_mode = false
	_reset_build()
	await _enter_round(8)
	var pl = GameState.player
	pl.shield = 0.0
	pl.hp = pl.max_hp
	var b: Build = GameState.build
	var e := _dummy(Vector3(5, 0, 0))
	var base := _calc(e)
	# --- Última Palabra
	_give("law_final_word", 2)
	e.hp = e.max_hp * 0.2
	var hi := _calc(e)
	e.hp = e.max_hp
	var lo := _calc(e)
	ok(absf(lo - base) < 0.01 and absf(hi / base - (1.0 + b.s("law_final"))) < 0.01, "W1 Última Palabra: ×%.2f contra <30%% de vida y ×1.00 con vida llena" % (hi / base))
	# --- Cadena de Objeciones
	_give("law_objection_chain", 3)
	var k0 := _calc(e)
	for i in 12:
		LawPerks.on_kill(e)
	var k1 := _calc(e)
	ok(LawPerks.obj_stacks == 8 and absf(k1 / k0 - (1.0 + 8.0 * b.s("law_obj"))) < 0.02, "W2 Cadena de Objeciones: máx. 8 acumulaciones (×%.2f)" % (k1 / k0))
	LawPerks.update(6.0)
	ok(LawPerks.obj_stacks == 0, "W2b las acumulaciones caducan a los 5 s")
	# --- Evasión Legal
	_give("law_legal_dodge", 2)
	var d0 := _calc(e)
	LawPerks.on_dodge()
	var d1 := _calc(e)
	ok(d1 > d0 * 1.4, "W3 Evasión Legal: tras esquivar el golpe sale ×%.2f" % (d1 / d0))
	Combat.player_hit(e, 1.0, {"src": "slam", "no_crit": true, "flat": false})
	ok(not LawPerks.dodge_next, "W3b el golpe potenciado se consume una sola vez")
	LawPerks.update(6.0)
	info("W3c d0=%.3f ahora=%.3f dodge_t=%.2f" % [d0, _calc(e), LawPerks.dodge_t])
	ok(absf(_calc(e) - d0) < 0.01, "W3c el bonus de 3 s caduca")
	# --- Sentencia Crítica (estadístico: prob. de crítico sube)
	var crit_before := 0
	for i in 3000:
		if bool(Combat.calc(e, 10.0, {"src": "slam", "flat": false})["crit"]):
			crit_before += 1
	_give("law_sentence", 5)
	var crit_after := 0
	for i in 3000:
		if bool(Combat.calc(e, 10.0, {"src": "slam", "flat": false})["crit"]):
			crit_after += 1
	ok(crit_after > crit_before + 3000 * 0.12, "W4 Sentencia Crítica: críticos %d → %d de 3000 (+%.0f%% esperado)" % [crit_before, crit_after, b.s("law_sent") * 100.0])
	# --- Defensa Procesal
	pl.hp = pl.max_hp
	pl.shield = 0.0
	_hurt(0.30)
	var lost_plain = pl.max_hp - pl.hp
	_reset_build()
	pl.hp = pl.max_hp
	_give("law_procedural", 4)
	_hurt(0.30)
	var lost_def = pl.max_hp - pl.hp
	ok(absf(lost_def / lost_plain - (1.0 - b.s("law_def"))) < 0.03 and b.s("law_def") <= 0.35, "W5 Defensa Procesal: daño recibido ×%.2f (esperado ×%.2f)" % [lost_def / lost_plain, 1.0 - b.s("law_def")])
	# --- Blindaje de Expedientes
	_reset_build()
	_give("law_file_shield", 3)
	pl.hp = pl.max_hp
	LawPerks.forced_roll = 0.0
	_hurt(0.2)
	var blocked = pl.hp >= pl.max_hp - 0.01
	_hurt(0.2)
	var second_hit = pl.hp < pl.max_hp - 1.0
	ok(blocked and second_hit, "W6 Blindaje: bloquea un impacto y no bloquea dos seguidos (1 s entre bloqueos)")
	LawPerks.forced_roll = -1.0
	_give("law_file_shield", 20)
	ok(b.s("law_block") <= 0.3, "W6b el bloqueo está limitado al 30%% (%.2f)" % b.s("law_block"))
	# --- Escudo de Inmunidad
	_reset_build()
	_give("law_immunity_shield", 2, 1)
	pl.hp = pl.max_hp
	pl.shield = 0.0
	_hurt(0.2)
	ok(pl.iframes >= 1.0 and pl.shield > 0.0 and LawPerks.immun_cd > 20.0, "W7 Escudo de Inmunidad tras golpe grave: invulnerable %.1f s, escudo %.0f, recarga %.0f s" % [pl.iframes, pl.shield, LawPerks.immun_cd])
	var sh = pl.shield
	pl.iframes = 0.0
	pl.shield = 0.0
	_hurt(0.2)
	ok(pl.shield <= 0.01, "W7b en recarga no se repite")
	# --- Recuperación Médica (con límite por ronda)
	_reset_build()
	_give("law_medic", 8, 3)
	pl.hp = 1.0
	pl.shield = 0.0
	LawPerks.on_round_start()
	for i in 200:
		LawPerks.on_kill(e)
	var healed = pl.hp - 1.0
	ok(healed > 1.0 and healed <= pl.max_hp * 0.2 + 0.5, "W8 Recuperación Médica: 200 bajas curan %.1f (límite 20%% = %.1f)" % [healed, pl.max_hp * 0.2])
	LawPerks.on_round_start()
	pl.hp = 1.0
	for i in 200:
		LawPerks.on_kill(e)
	ok(pl.hp > 1.0, "W8b el límite se reinicia en la ronda siguiente")
	# --- Impulso de Apelación
	_reset_build()
	_give("law_appeal", 3)
	ok(b.s("dodge_cd") > 0.1 and b.s("dodge_speed") > 0.2, "W9 Impulso de Apelación: enfriamiento -%.0f%% y velocidad +%.0f%%" % [b.s("dodge_cd") * 100.0, b.s("dodge_speed") * 100.0])
	# --- Papeles Cortantes
	_reset_build()
	_give("law_cutting_papers", 2)
	var victims: Array = []
	for i in 6:
		var ang := TAU * float(i) / 6.0
		var v := _dummy(Vector3(cos(ang), 0, sin(ang)) * LawPerks.PAPER_RADIUS)
		v.invuln_t = 0.0
		victims.append(v)
	var hp0: Array = []
	for v in victims:
		hp0.append(v.hp)
	await _secs(2.2)
	var cut := 0
	for i in victims.size():
		if is_instance_valid(victims[i]) and (not victims[i].alive or victims[i].hp < hp0[i] - 0.01):
			cut += 1
	ok(LawPerks.paper_count() == 2 and pl.get_node_or_null("LawPapers") != null and cut >= 2, "W10 Papeles Cortantes: 2 papeles giran y dañaron a %d de 6 enemigos" % cut)
	_clear_enemies()
	# --- Mazo Judicial
	_reset_build()
	_give("law_gavel_strike", 2)
	var gv := _dummy(Vector3(2.5, 0, 0), "tank")
	var ghp: float = gv.hp
	for i in 7:
		LawPerks.on_throw()
	ok(LawPerks.gavel_count == 1 and gv.hp < ghp, "W11 Mazo Judicial: a los 7 lanzamientos golpea el área (daño %.0f)" % (ghp - gv.hp))
	_clear_enemies()
	# --- maletín: Demoledor / Regreso Letal / Perforante / Doble Alegato
	_reset_build()
	var p0: Dictionary = GameState.case_throw.make_profile()
	_give("law_demolisher", 3)
	_give("law_return", 2)
	_give("law_piercing", 2)
	var p1: Dictionary = GameState.case_throw.make_profile()
	ok(float(p1["out_mult"]) > 1.4 and float(p0["out_mult"]) == 1.0 if p0.has("out_mult") else float(p1["out_mult"]) > 1.4, "W12 Maletín Demoledor: daño de ida ×%.2f" % float(p1["out_mult"]))
	ok(bool(p1["sharp"]) and float(p1["ret_mult"]) >= 0.7, "W13 Regreso Letal: el maletín golpea al volver (×%.2f del daño de ida)" % float(p1["ret_mult"]))
	ok(int(p1["pierce"]) == int(p0["pierce"]) + 2, "W14 Expediente Perforante: +2 perforaciones (%d → %d)" % [int(p0["pierce"]), int(p1["pierce"])])
	_give("law_double", 3)
	LawPerks.forced_roll = 0.0
	var plan_hi: Array = GameState.case_throw.plan_cases(p1)
	LawPerks.forced_roll = 0.99
	var plan_lo: Array = GameState.case_throw.plan_cases(p1)
	ok(plan_hi.size() == plan_lo.size() + 1 and b.s("law_dbl") <= 0.4, "W15 Doble Alegato: 2.º maletín con tirada baja (%d vs %d), prob. %.0f%%" % [plan_hi.size(), plan_lo.size(), b.s("law_dbl") * 100.0])
	LawPerks.forced_roll = -1.0
	# lanzamiento real: el regreso golpea
	_reset_build()
	_give("law_return", 3)
	pl.hp = pl.max_hp
	var far_a := _dummy(Vector3(0, 0, -7.0))
	far_a.hp = far_a.max_hp * 1000.0
	far_a.max_hp = far_a.hp
	var late := _dummy(Vector3(18, 0, 18))
	late.hp = late.max_hp * 1000.0
	late.max_hp = late.hp
	var ct = GameState.case_throw
	ct.record = true
	ct.impact_log.clear()
	pl.skills.cd[0] = 0.0
	pl.skills.try_cast(0)
	var guard := 0
	while guard < 500:
		await get_tree().physics_frame
		guard += 1
		if not ct.cases.is_empty() and (ct.cases[0] as CaseThrow.C).state == "ret":
			break
	await get_tree().physics_frame
	if not ct.cases.is_empty():
		var cc: CaseThrow.C = ct.cases[0]
		late.global_position = Vector3(cc.pos.x + cc.vel.x * 0.05, 0.1, cc.pos.z + cc.vel.z * 0.05)
	await _secs(2.8)
	var ret_hits := 0
	for rec in ct.impact_log:
		if String(rec["state"]) == "ret" and int(rec["enemy"]) == late.get_instance_id():
			ret_hits += 1
	ok(ret_hits == 1, "W16 lanzamiento real: con Regreso Letal el maletín golpea UNA vez a un enemigo que encuentra en el regreso (%d)" % ret_hits)
	var out_far: int = ct.impact_log.filter(func(x): return int(x["enemy"]) == far_a.get_instance_id()).size()
	ok(out_far == 1, "W16b el enemigo de la ida no recibe un segundo golpe al volver (%d)" % out_far)
	ct.record = false
	_clear_enemies()
	# --- sinergias
	_reset_build()
	_give("law_demolisher")
	_give("law_return")
	ok(b.has_synergy("law_case_duo") and b.s("syn_law_case") > 0.0, "S1 sinergia Doble Sentencia (Demoledor + Regreso) activa")
	var pS: Dictionary = ct.make_profile()
	ok(bool(pS["ret_demo"]), "S1b la sinergia hace que el bonus de ida cuente al regresar")
	_give("law_piercing")
	_give("law_cutting_papers")
	ok(b.has_synergy("law_paper_pierce") and LawPerks.paper_count() == 2, "S2 sinergia Archivo Cortante: +1 papel (%d papeles)" % LawPerks.paper_count())
	_give("law_legal_dodge")
	_give("law_objection_chain")
	ok(b.has_synergy("law_dodge_chain"), "S3 sinergia Contraataque Procesal activa")
	LawPerks.obj_stacks = 0
	LawPerks.on_dodge()
	ok(LawPerks.obj_stacks == 3, "S3b esquivar suma 3 objeciones con la sinergia")
	_give("law_medic")
	_give("law_procedural")
	ok(b.has_synergy("law_medic_def") and b.s("armor") >= 0.05, "S4 sinergia Cobertura Médica activa (+%.0f%% de armadura)" % (b.s("armor") * 100.0))
	_give("law_sentence")
	_give("law_final_word")
	ok(b.has_synergy("law_crit_final"), "S5 sinergia Veredicto Final activa")
	var ev := _dummy(Vector3(4, 0, 0))
	ev.hp = ev.max_hp * 0.1
	var cf := 0.0
	for i in 80:
		var r := Combat.calc(ev, 10.0, {"src": "slam", "flat": false, "force_crit": true})
		cf = float(r["damage"])
	ev.hp = ev.max_hp * 0.9
	var cn := float(Combat.calc(ev, 10.0, {"src": "slam", "flat": false, "force_crit": true})["damage"])
	ok(cf > cn * 1.4, "S5b crítico a un enemigo debilitado ×%.2f más fuerte" % (cf / cn))
	_give("law_win_fees")
	_give("law_efficiency")
	ok(b.has_synergy("law_fee_eff"), "S6 sinergia Bufete Eficiente activa")
	# se muestran en el inventario
	var inv := InventoryUI.new()
	main._open_overlay(inv)
	await _secs(0.5)
	var txt := _all_text(inv)
	ok(txt.find("Doble Sentencia") >= 0 or txt.find("Sinergia") >= 0 or txt.find("SINERGIA") >= 0, "S7 el inventario muestra las sinergias activas")
	await _shot("inventario_sinergias")
	await _close_overlays()
	_clear_enemies()
	_reset_build()


func _all_text(n: Node) -> String:
	var s := ""
	if n is Label:
		s += (n as Label).text + "\n"
	elif n is Button:
		s += (n as Button).text + "\n"
	for c in n.get_children():
		s += _all_text(c)
	return s


# ====================================================================== economía
func _coins_on_floor() -> int:
	var t := 0
	for c in main.arena._coins:
		t += int(c["value"])
	return t


func _t_econ() -> void:
	info("--- economía ---")
	_reset_build()
	await _enter_round(6)
	var ar: Arena = main.arena
	var b: Build = GameState.build
	# pago por baja: una sola vez
	var e1 := _dummy(Vector3(5, 0, 0))
	e1.invuln_t = 0.0
	var before := _coins_on_floor()
	e1.take_damage(e1.hp * 10.0, {"src": "slam", "element": "phys", "knock": Vector3.ZERO})
	await _frames(3)
	var base_pay := _coins_on_floor() - before
	ok(base_pay >= 1, "E1 una baja suelta monedas (%d)" % base_pay)
	ar._on_enemy_died(e1)
	ar._on_enemy_died(e1)
	await _frames(2)
	ok(_coins_on_floor() - before == base_pay, "E2 la señal de muerte repetida NO paga dos veces (%d → %d)" % [base_pay, _coins_on_floor() - before])
	e1.take_damage(1.0, {"src": "slam", "element": "phys", "knock": Vector3.ZERO})
	await _frames(2)
	ok(_coins_on_floor() - before == base_pay, "E3 golpear un cadáver no vuelve a pagar")
	# Honorarios por Victoria
	_give("law_win_fees", 4)
	var e2 := _dummy(Vector3(5, 0, 1))
	e2.invuln_t = 0.0
	var cv: int = e2.coin_value
	var b2 := _coins_on_floor()
	e2.take_damage(e2.hp * 10.0, {"src": "slam", "element": "phys", "knock": Vector3.ZERO})
	await _frames(3)
	var pay2 := _coins_on_floor() - b2
	var want := int(round(float(cv) * (1.0 + b.s("law_fee_win"))))
	ok(absf(float(pay2 - want)) <= 1.5 and b.s("law_fee_win") <= 0.6, "E4 Honorarios por Victoria: %d monedas (base %d, esperado ≈%d, máx. +60%%)" % [pay2, cv, want])
	# Cliente de Alto Perfil: élites/jefes
	_give("law_vip_client", 3)
	var el := _dummy(Vector3(5, 0, -1), "elite")
	el.invuln_t = 0.0
	var cve: int = el.coin_value
	var b3 := _coins_on_floor()
	el.take_damage(el.hp * 10.0, {"src": "slam", "element": "phys", "knock": Vector3.ZERO})
	await _frames(3)
	var pay3 := _coins_on_floor() - b3
	ok(pay3 > int(round(float(cve) * (1.0 + b.s("law_fee_win")))), "E5 Cliente de Alto Perfil: un élite paga %d (más que sin él)" % pay3)
	ok(LawPerks.vip_clear(10, Scaling.KIND_BOSS) > 0 and LawPerks.vip_clear(10, Scaling.KIND_ELIMINATION) == 0, "E5b el extra de limpieza solo en arenas especiales (%d $)" % LawPerks.vip_clear(10, Scaling.KIND_BOSS))
	# Cobro Anticipado: al empezar ronda nueva, no al cargar
	_reset_build()
	_give("law_advance_fee", 3)
	GameState.coins = 0
	await main._begin_arena(2, true)
	await _frames(6)
	var adv := GameState.coins
	ok(adv == LawPerks.advance_fee(2) and adv > 0, "E6 Cobro Anticipado: +%d $ al empezar la ronda (esperado %d)" % [adv, LawPerks.advance_fee(2)])
	var big := LawPerks.advance_fee(0)
	_give("law_advance_fee", 30)
	ok(LawPerks.advance_fee(0) <= 6 and LawPerks.advance_fee(80) <= 60, "E6b crece con las rondas y tiene tope (ronda 1: %d, ronda 81: %d)" % [LawPerks.advance_fee(0), LawPerks.advance_fee(80)])
	# Intereses del Bufete: solo fin de zona, con tope
	_reset_build()
	_give("law_firm_interest", 5)
	ok(LawPerks.firm_interest(3, 500) == 0 and LawPerks.firm_interest(4, 500) > 0, "E7 Intereses del Bufete: solo en las rondas 5, 10… (r4: %d, r5: %d)" % [LawPerks.firm_interest(3, 500), LawPerks.firm_interest(4, 500)])
	ok(LawPerks.firm_interest(4, 1000000) <= 80, "E7b con muchas monedas el pago tiene tope (%d ≤ 80)" % LawPerks.firm_interest(4, 1000000))
	# Negociador Experto
	_reset_build()
	var sh := ShopUI.new()
	var p_before := sh.price_of(100.0)
	_give("law_negotiator", 4)
	var p_after := sh.price_of(100.0)
	ok(p_after < p_before and p_after >= int(p_before * 0.5), "E8 Negociador Experto: un artículo de 100 pasa a %d (antes %d)" % [p_after, p_before])
	_give("law_negotiator", 30)
	ok(sh.price_of(100.0) >= int(round(float(p_before) * 0.5)), "E8b el descuento total tiene tope del 50%%")
	sh.free()
	# ronda completa: intereses una sola vez
	_reset_build()
	_give("law_firm_interest", 3)
	await _enter_round(4)
	GameState.coins = 1000
	await _complete_round()
	var after_clear := GameState.coins
	ar._pay_round_economy
	ok(after_clear > 1000, "E9 al terminar la ronda 5 se pagan intereses (%d → %d)" % [1000, after_clear])
	_reset_build()


# ====================================================================== tienda
func _t_shop() -> void:
	info("--- tienda ---")
	_reset_build()
	await _enter_round(1)
	var b: Build = GameState.build
	var sets: Array = []
	var shop_offers: Array = []
	for visit in 12:
		var sh := ShopUI.new()
		sh.visit = {}
		sh._generate(5 + visit)
		var ids: Array = []
		var groups := {}
		for o in sh._offers:
			if String(o.get("label", "")).begins_with("Tienda"):
				ids.append(o["card"]["id"])
				groups[o["label"]] = true
		ids.sort()
		sets.append(ids)
		shop_offers.append({"n": ids.size(), "groups": groups.size()})
		sh.free()
	var distinct := {}
	for s in sets:
		distinct[str(s)] = true
	var all3 := true
	var diverse := true
	for so in shop_offers:
		if int(so["n"]) < 3:
			all3 = false
		if int(so["groups"]) < 2:
			diverse = false
	ok(all3, "T1 cada visita ofrece 3 artículos exclusivos")
	ok(diverse, "T2 los artículos exclusivos son de grupos distintos")
	ok(distinct.size() >= 7, "T3 12 visitas dieron %d surtidos distintos (la tienda varía)" % distinct.size())
	var same_consec := 0
	for i in range(1, sets.size()):
		if str(sets[i]) == str(sets[i - 1]):
			same_consec += 1
	ok(same_consec <= 1, "T4 apenas se repite el mismo surtido en visitas seguidas (%d)" % same_consec)
	# todos los artículos: efecto real
	var all_effect := true
	for id in LawCatalog.SHOP_GROUPS.keys():
		_reset_build()
		var d := UpgradeDB.get_def(id)
		var r: int = (d["rarities"] as Array)[0]
		GameState.build.add(id, r, true)
		GameState.build.recompute(false)
		for k in (d["stats"] as Dictionary).keys():
			var key := String(k)
			var v := GameState.build.s(key)
			var neutral := 1.0 if key.ends_with("_x") else 0.0
			if absf(v - neutral) < 0.0001:
				all_effect = false
				info("sin efecto: %s %s" % [id, key])
	ok(all_effect, "T5 los 15 artículos de tienda cambian de verdad las estadísticas")
	_reset_build()
	# compra con dinero suficiente / insuficiente, a través de la interfaz real
	var shp := ShopUI.new()
	shp.visit = {}
	main._open_overlay(shp)
	shp.open(5)
	await _secs(0.4)
	var idx := -1
	for i in shp._offers.size():
		if shp._offers[i]["type"] == "card":
			idx = i
			break
	var offer: Dictionary = shp._offers[idx]
	var price := shp.price_of(float(offer["base"]))
	GameState.coins = price - 1
	var n_before := b.picks.size()
	shp._buy(idx)
	ok(GameState.coins == price - 1 and b.picks.size() == n_before and not bool(offer["sold"]), "T6 sin dinero suficiente (%d < %d) no se compra ni se cobra" % [price - 1, price])
	GameState.coins = price + 7
	shp._lock_until = 0
	shp._buy(idx)
	ok(GameState.coins == 7 and b.picks.size() == n_before + 1 and bool(offer["sold"]), "T7 con dinero suficiente se compra: saldo %d y la mejora entra" % GameState.coins)
	GameState.coins = 5000
	shp._lock_until = 0
	shp._buy(idx)
	ok(b.picks.size() == n_before + 1, "T8 un artículo vendido no se compra dos veces")
	# doble pulsación rápida en un artículo repetible
	var heal_idx := 0
	GameState.coins = 5000
	shp._lock_until = 0
	var c0 := GameState.coins
	var p_heal := shp.price_of(float(shp._offers[heal_idx]["base"]))
	shp._buy(heal_idx)
	shp._buy(heal_idx)
	ok(c0 - GameState.coins == p_heal, "T9 dos pulsaciones seguidas cobran UNA sola compra (%d)" % (c0 - GameState.coins))
	# relanzamientos: límite 3 y sin duplicar por doble pulsación
	GameState.coins = 100000
	shp._lock_until = 0
	var ok1 := shp.do_reroll()
	var ok1b := shp.do_reroll()      # inmediato: bloqueado
	ok(ok1 and not ok1b and shp.rerolls_used() == 1, "T10 doble pulsación en RELANZAR cuenta un solo uso (%d)" % shp.rerolls_used())
	for i in 2:
		await _secs(0.5)
		shp.do_reroll()
	await _secs(0.5)
	var ok4 := shp.do_reroll()
	ok(shp.rerolls_used() == 3 and not ok4, "T11 el límite de 3 relanzamientos por visita se respeta")
	# precio y rareza visibles en la fila
	await _frames(3)
	var txt := _all_text(shp)
	ok(txt.find("$") >= 0 and (txt.find("Común") >= 0 or txt.find("Rara") >= 0 or txt.find("Épica") >= 0 or txt.find("Legendaria") >= 0), "T12 la tienda muestra precio y rareza")
	await _shot("tienda_nueva")
	# los artículos antiguos siguen: curación, energía, segunda opinión
	var types := {}
	for o in shp._offers:
		types[o["type"]] = true
	ok(types.has("heal") and types.has("revive") and types.has("energy") and types.has("card"), "T13 se conservan los artículos existentes (curación, Segunda Opinión, café, mejoras)")
	await _close_overlays()
	_reset_build()


# ====================================================================== guardado
func _t_save() -> void:
	info("--- guardado ---")
	_reset_build()
	await _enter_round(0)
	var ar: Arena = main.arena
	_give("law_demolisher", 2)
	_give("shop_suit", 1)
	LawPerks.forced_roll = 0.1
	await _complete_round()
	ok(ar.bonus_chest_wanted, "V0 ronda con cofre extra")
	var snap: Dictionary = GameState.snapshot_run("reward")
	ok(SaveSystem.validate_run(snap) == "", "V1 la partida con las mejoras nuevas pasa la validación (%s)" % SaveSystem.validate_run(snap))
	ok(bool((snap["perf"] as Dictionary).get("bonus", false)), "V2 el cofre extra pendiente se guarda")
	var json := JSON.stringify(snap)
	var back = JSON.parse_string(json)
	ok(typeof(back) == TYPE_DICTIONARY and SaveSystem.validate_run(back) == "", "V3 el guardado sobrevive a JSON")
	# restaurar: NO se vuelve a tirar (tirada 0.99 no quita el cofre) y el principal sigue sin abrir
	LawPerks.forced_roll = 0.99
	await main._begin_arena(0, true, back)
	await _frames(8)
	ar = main.arena
	ok(ar.bonus_chest_wanted and ar._bchest != null and not ar.chest_taken and not ar.bonus_taken, "V4 al cargar reaparecen el cofre normal y el extra, sin volver a tirar")
	ok(not _pready(), "V5 el portal sigue cerrado hasta abrir los dos")
	# con el principal abierto
	ar._open_chest(0)
	await _secs(1.0)
	await _close_overlays()
	var snap2: Dictionary = GameState.snapshot_run("reward")
	ok(bool((snap2["perf"] as Dictionary).get("main_taken", false)) and not bool((snap2["perf"] as Dictionary).get("bonus_taken", true)), "V6 el estado «principal abierto, extra pendiente» se guarda")
	await main._begin_arena(0, true, JSON.parse_string(JSON.stringify(snap2)))
	await _frames(8)
	ar = main.arena
	ok(ar.chest_taken and not ar.bonus_taken and ar.bonus_chest_wanted, "V7 al cargar: principal ya abierto (no se puede repetir) y extra disponible")
	ar._open_bonus_chest()
	await _secs(1.0)
	await _close_overlays()
	var snap3: Dictionary = GameState.snapshot_run("portal")
	await main._begin_arena(0, true, JSON.parse_string(JSON.stringify(snap3)))
	await _frames(8)
	ar = main.arena
	ok(ar.rewards_done() and _pready(), "V8 con todo abierto el portal queda activo tras cargar")
	# restaurar la build guardada: sigue con las mejoras nuevas
	GameState.restore_run(JSON.parse_string(JSON.stringify(snap3)))
	ok(GameState.build.count_of("law_demolisher") == 2 and GameState.build.count_of("shop_suit") == 1, "V9 la build restaurada conserva las mejoras nuevas y de tienda")
	LawPerks.forced_roll = -1.0
	_reset_build()


# ====================================================================== menú códigos / desarrollador
func _t_menu() -> void:
	info("--- códigos y desarrollador ---")
	_reset_build()
	SaveSystem.set_setting("dev_unlocked", false)
	Config.dev_mode = false
	get_window().size = Vector2i(1280, 720)
	await _secs(0.5)
	main._open_settings("game")
	await _secs(0.5)
	var st := _overlay_of(SettingsMenu) as SettingsMenu
	ok(st != null, "M0 se abre AJUSTES")
	var codes := st.find_child("OpenCodes", true, false) as Button
	ok(codes != null and codes.text == "CÓDIGOS", "M1 existe el botón CÓDIGOS en Ajustes")
	ok(st.find_child("OpenDev", true, false) == null, "M2 antes del código NO existe el menú DESARROLLADOR")
	for sc in st.find_children("*", "ScrollContainer", true, false):
		(sc as ScrollContainer).ensure_control_visible(codes)
	await _frames(2)
	await _tap(codes)
	await _secs(0.3)
	var le := st.find_child("CodeInput", true, false) as LineEdit
	var redeem := st.find_child("CodeRedeem", true, false) as Button
	ok(le != null and redeem != null, "M3 el menú CÓDIGOS pide un código")
	await _shot("codigos")
	le.text = "codigo-falso"
	await _secs(1.0)
	redeem.button_down.connect(func(): print("DBG redeem down"))
	redeem.pressed.connect(func(): print("DBG redeem pressed"))
	var mv := InputEventMouseMotion.new()
	mv.position = redeem.get_global_rect().get_center()
	Input.parse_input_event(mv)
	await _frames(3)
	info("M4 hovered2=%s" % str(get_viewport().gui_get_hovered_control()))
	await _tap(redeem)
	var msg := st.find_child("CodeMsg", true, false) as Label
	info("M4 hovered=%s" % str(get_viewport().gui_get_hovered_control()))
	info("M4 msg='%s' redeem_rect=%s vis=%s" % [msg.text, str(redeem.get_global_rect()), str(redeem.is_visible_in_tree())])
	ok(msg.text == "Código no válido." and not bool(SaveSystem.setting("dev_unlocked")) and st.find_child("OpenDev", true, false) == null, "M4 un código incorrecto se rechaza y no desbloquea nada")
	le.text = "maletindefarks"
	await _tap(redeem)
	await _secs(0.3)
	ok(bool(SaveSystem.setting("dev_unlocked")) and msg.text.find("DESARROLLADOR") >= 0, "M5 «maletindefarks» desbloquea el modo desarrollador (%s)" % msg.text)
	var opendev := st.find_child("OpenDev", true, false) as Button
	ok(opendev != null and opendev.text == "DESARROLLADOR", "M6 aparece el menú DESARROLLADOR")
	await _shot("codigos_ok")
	await _tap(st.find_child("CodeClose", true, false) as Button)
	await _secs(0.2)
	for sc in st.find_children("*", "ScrollContainer", true, false):
		(sc as ScrollContainer).ensure_control_visible(opendev)
	await _secs(0.3)
	await _tap(opendev)
	await _secs(0.5)
	var dv := _overlay_of(DevTools) as DevTools
	ok(dv != null, "M7 DESARROLLADOR se abre")
	if dv == null:
		return
	await _shot("desarrollador")
	# dinero por botones y por cantidad libre
	GameState.coins = 0
	await _tap(dv.find_child("DevCoins_1000", true, false) as Button)
	ok(GameState.coins == 1000, "M8 el botón +1000 $ sube el dinero a %d" % GameState.coins)
	(dv.find_child("DevCoinsAmount", true, false) as SpinBox).value = 12345
	await _tap(dv.find_child("DevCoinsAdd", true, false) as Button)
	ok(GameState.coins == 13345, "M9 cantidad libre: +12345 → %d" % GameState.coins)
	var fees0 := int(SaveSystem.data["meta"]["fees"])
	(dv.find_child("DevFeesAmount", true, false) as SpinBox).value = 250
	await _tap(dv.find_child("DevFeesAdd", true, false) as Button)
	ok(int(SaveSystem.data["meta"]["fees"]) == fees0 + 250, "M10 los honorarios suben +250")
	# agregar mejoras
	var opt := dv.find_child("DevItem", true, false) as OptionButton
	var target := -1
	for i in dv._ids.size():
		if dv._ids[i] == "law_demolisher":
			target = i
	opt.select(target)
	(dv.find_child("DevQty", true, false) as SpinBox).value = 3
	(dv.find_child("DevRarity", true, false) as OptionButton).select(2)
	var n0 := GameState.build.count_of("law_demolisher")
	await _tap(dv.find_child("DevItemAdd", true, false) as Button)
	ok(GameState.build.count_of("law_demolisher") == n0 + 3 and GameState.build.rarity_of("law_demolisher") >= 0, "M11 «Agregar mejora» añade 3 niveles de Maletín Demoledor")
	# nunca rompe los límites
	var given := dv.give_upgrade("law_demolisher", 3, 500)
	ok(GameState.build.count_of("law_demolisher") <= int(UpgradeDB.get_def("law_demolisher")["max"]) and given >= 0, "M12 pedir 500 niveles respeta el máximo (%d)" % GameState.build.count_of("law_demolisher"))
	# adaptable a varias pantallas
	for res in [Vector2i(1280, 720), Vector2i(854, 480), Vector2i(800, 360)]:
		get_window().size = res
		await _secs(0.5)
		var vs := get_viewport().get_visible_rect()
		var pr := (dv.find_child("DevPanel", true, false) as Control).get_global_rect()
		var cl := (dv.find_child("DevClose", true, false) as Control).get_global_rect()
		ok(pr.position.x >= 0 and pr.end.x <= vs.end.x + 1 and pr.end.y <= vs.end.y + 1 and cl.end.x <= vs.end.x and cl.end.y <= vs.end.y, "M13 DESARROLLADOR cabe en %dx%d" % [res.x, res.y])
	get_window().size = Vector2i(1280, 720)
	await _secs(0.4)
	await _tap(dv.find_child("DevClose", true, false) as Button)
	await _secs(0.2)
	ok(_overlay_of(DevTools) == null, "M14 Cerrar sale del menú")
	# persiste tras reabrir ajustes
	await _close_overlays()
	main._open_settings("game")
	await _secs(0.5)
	var st2 := _overlay_of(SettingsMenu) as SettingsMenu
	ok(st2.find_child("OpenDev", true, false) != null, "M15 el desbloqueo persiste al reabrir Ajustes")
	await _close_overlays()
	SaveSystem.set_setting("dev_unlocked", false)
	Config.dev_mode = false
	Config.dev_god_mode = false
	_reset_build()
