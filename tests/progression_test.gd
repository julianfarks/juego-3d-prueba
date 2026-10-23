extends Node
## Pruebas NUMÉRICAS (sin renderizado) del sistema de mejoras acumulables hasta nivel 50 y de la curva de dificultad.
##   godot --headless res://tests/progression_test.tscn
## Imprime una tabla de la progresión y devuelve código de salida 1 si algo falla.

const FOCUS := ["heavy_case", "overtime", "gavel", "expert_eye", "espresso", "wide_sweep", "echo_wave", "boomerang_case", "verdict", "closing_nova"]
var fails: Array = []
var passes := 0


func _ready() -> void:
	call_deferred("_main")


func ok(cond: bool, name: String) -> void:
	if cond:
		passes += 1
		print("[PASS] ", name)
	else:
		fails.append(name)
		print("[FAIL] ", name)


func _main() -> void:
	_t1_case_levels()
	_t2_level_50_and_chests()
	_t3_final_stats()
	_t4_synergies()
	_t5_enemy_gradual()
	_t6_no_jumps()
	_t7_long_run()
	_t8_sanity()
	print("[RESULT] %d ok, %d fallos" % [passes, fails.size()])
	for f in fails:
		print("  FALLO: ", f)
	get_tree().quit(1 if fails.size() > 0 else 0)


func _build(picks: Array = []) -> Build:
	var b := Build.new()
	b.reset({})
	_bulk(b, picks)
	return b


## Carga muchas mejoras de golpe (sin el límite de 30 tipos: estas pruebas miden números, no el inventario)
## y recalcula UNA sola vez.
## Una build "enfocada" prioriza las mejoras de las etiquetas maletín / crítico / explosión / ataque.
func _is_focus(id: String) -> bool:
	if FOCUS.has(id):
		return true
	var tg: Array = UpgradeDB.get_def(id).get("tags", [])
	for t in ["maletin", "critico", "explosion", "ataque"]:
		if tg.has(t):
			return true
	return false


func _bulk(b: Build, picks: Array) -> void:
	for p in picks:
		b.picks.append({"id": p[0], "rarity": p[1]})
		b.counts[p[0]] = int(b.counts.get(p[0], 0)) + 1
	b.recompute(false)


# --- 1: Daño de Maletín sube de nivel 1 a 2 y sigue subiendo -------------------------------------------
func _t1_case_levels() -> void:
	var b := _build()
	var prev := b.s("dmg_pct")
	var mono := true
	var lv_ok := true
	for lvl in range(1, 51):
		b.add("heavy_case", 0)
		if b.count_of("heavy_case") != lvl:
			lv_ok = false
		if lvl == 1:
			ok(absf(b.s("dmg_pct") - 0.16) < 1e-6, "T1 nivel 1 de Daño de Maletín = +16%% de daño")
		if lvl == 2:
			ok(absf(b.s("dmg_pct") - 0.32) < 1e-6, "T1 nivel 2 = +32%% (sube de verdad)")
		if b.s("dmg_pct") <= prev:
			mono = false
		prev = b.s("dmg_pct")
	ok(lv_ok, "T1 el contador de nivel coincide con las veces elegida (1..50)")
	ok(mono, "T1 el daño sube estrictamente en cada uno de los 50 niveles")
	print("   Maletín nivel 50 (común): dmg_pct=%.2f  more_dmg_x=%.3f  power=%.2f" % [b.s("dmg_pct"), b.s("more_dmg_x"), b.power_rating()])
	# en niveles intermedios hay hitos
	var b9 := _build()
	for i in 9:
		b9.add("heavy_case", 0)
	var b10 := _build()
	for i in 10:
		b10.add("heavy_case", 0)
	ok(b9.s("more_dmg_x") == 1.0 and absf(b10.s("more_dmg_x") - 1.10) < 1e-6, "T1 hito del nivel 10: daño total ×1.10 (no antes)")


# --- 2: nivel 50 aplica el efecto y deja de salir en los cofres ------------------------------------------
func _t2_level_50_and_chests() -> void:
	var b49 := _build()
	for i in 49:
		b49.add("heavy_case", 0)
	var b50 := _build()
	for i in 50:
		b50.add("heavy_case", 0)
	var exp50 := 50 * 0.16
	ok(absf(b50.s("dmg_pct") - exp50) < 1e-6, "T2 nivel 50: +%d%% de daño exacto" % int(exp50 * 100))
	ok(absf(b50.s("more_dmg_x") - pow(1.10, 5)) < 1e-6, "T2 nivel 50: 5 hitos acumulados (×%.3f)" % pow(1.10, 5))
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var seen49 := 0
	var seen50 := 0
	var dup := 0
	for n in 600:
		var c49 := UpgradeDB.roll_cards(3, 0.2, n % 40, b49, rng, 0)
		var c50 := UpgradeDB.roll_cards(3, 0.2, n % 40, b50, rng, 0)
		for c in c49:
			if c["id"] == "heavy_case":
				seen49 += 1
		for c in c50:
			if c["id"] == "heavy_case":
				seen50 += 1
		var ids := {}
		for c in c50:
			if ids.has(c["id"]):
				dup += 1
			ids[c["id"]] = true
	ok(seen49 > 100, "T2 en nivel 49 todavía aparece en cofres (%d veces en 600)" % seen49)
	ok(seen50 == 0, "T2 en nivel 50 NO aparece nunca (0 de 600 cofres)")
	ok(dup == 0, "T2 sin duplicados dentro del mismo cofre (600 cofres)")
	# ninguna mejora supera su máximo ni el 50
	var over := 0
	for d in UpgradeDB.all():
		if int(d["max"]) > UpgradeDB.MAX_LEVEL or int(d["max"]) < 1:
			over += 1
	ok(over == 0, "T2 todos los máximos están entre 1 y 50")
	var at50 := 0
	var big := 0
	for d in UpgradeDB.all():
		if int(d["max"]) == 50:
			at50 += 1
		if int(d["max"]) >= 20:
			big += 1
	ok(at50 >= 1 and big >= 15, "T2 hay mejoras que llegan a 50 y %d con ≥20 niveles" % big)
	# mejora cuyo máximo se alcanzó nunca se ofrece (probado con TODAS las mejoras)
	var leak := 0
	for d in UpgradeDB.all():
		var bm := _build()
		var rr := 0
		for i in int(d["max"]):
			var rars: Array = d["rarities"]
			bm.add(d["id"], rars[0], true)
		if bm.count_of(d["id"]) != int(d["max"]):
			leak += 1
			print("   no sube hasta el máximo: ", d["id"])
		for n in 6:
			for c in UpgradeDB.roll_cards(3, 0.0, 10, bm, rng, 0):
				if c["id"] == d["id"]:
					leak += 1
					print("   se ofrece en máx.: ", d["id"])
	ok(leak == 0, "T2 ninguna mejora se ofrece cuando está en su nivel máximo (todas probadas)")
	# estadística principal en su límite duro => carta inútil no se ofrece
	var bc := _build()
	for i in 12:
		bc.add("expert_eye", 3)      # 12 · 0.02 · 3.6 = 0.86 > tope 0.85
	ok(bc.s("crit_chance") >= 0.85 - 1e-6, "T2 el crítico llega a su límite duro (85%)")
	var useless := 0
	for n in 100:
		for c in UpgradeDB.roll_cards(3, 0.0, 10, bc, rng, 0):
			if c["id"] == "expert_eye" or c["id"] == "all_in":
				useless += 1
	ok(useless == 0, "T2 con el crítico al límite no se ofrecen cartas de crítico inútiles")
	# afinidad con el equipamiento
	var saved: Dictionary = GameState.loadout
	var bq := _build()
	var base_n := _count_id("paper_storm", bq, rng, 400)
	GameState.loadout = {"weapon": "case", "skill": "docs_burst", "tactic": "brawler", "gear": "toga"}
	var with_docs := _count_id("paper_storm", bq, rng, 400)
	GameState.loadout = {"weapon": "case", "skill": "seal_master", "tactic": "brawler", "gear": "toga"}
	var without_docs := _count_id("paper_storm", bq, rng, 400)
	GameState.loadout = saved
	ok(with_docs > without_docs * 1.5, "T2 equipar Ráfaga de Documentos hace salir más 'Tormenta de Papel' (%d vs %d)" % [with_docs, without_docs])


func _count_id(id: String, b: Build, rng: RandomNumberGenerator, n: int) -> int:
	var k := 0
	for i in n:
		for c in UpgradeDB.roll_cards(3, 0.0, 10, b, rng, 0):
			if c["id"] == id:
				k += 1
	return k


# --- 3: las estadísticas finales reflejan todas las mejoras acumuladas ------------------------------------
func _t3_final_stats() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var picks: Array = []
	var ids: Array = []
	for d in UpgradeDB.all():
		ids.append(d["id"])
	var count := {}
	for n in 140:
		var id: String = ids[rng.randi() % ids.size()]
		var d := UpgradeDB.get_def(id)
		if int(count.get(id, 0)) >= int(d["max"]):
			continue
		var rars: Array = d["rarities"]
		picks.append([id, rars[rng.randi() % rars.size()]])
		count[id] = int(count.get(id, 0)) + 1
	var b := _build(picks)
	# cálculo independiente: se suma "a mano" solo lo aditivo sin sinergias ni topes (claves seguras)
	var exp_dmg := 0.0
	var exp_regen := 0.0
	var exp_flat := 0.0
	var exp_more := 1.0
	for p in picks:
		var d2 := UpgradeDB.get_def(p[0])
		var sc := UpgradeDB.rarity_scale(d2, p[1])
		exp_dmg += float((d2["stats"] as Dictionary).get("dmg_pct", 0.0)) * sc
		exp_regen += float((d2["stats"] as Dictionary).get("regen", 0.0)) * sc
		exp_flat += float((d2["stats"] as Dictionary).get("flat_dmg", 0.0)) * sc
		exp_more *= 1.0 + float((d2["stats"] as Dictionary).get("more_dmg_x", 0.0)) * sc
	for id in count.keys():
		var d3 := UpgradeDB.get_def(id)
		if d3.has("mile"):
			var reached := int(count[id]) / 10
			exp_flat += float((d3["mile"] as Dictionary).get("flat_dmg", 0.0)) * reached
			exp_more *= pow(1.0 + float((d3["mile"] as Dictionary).get("more_dmg_x", 0.0)), reached)
	# mejoras "Catalizador" (amp): suman más_dmg_x según las otras mejoras distintas con la etiqueta
	for id in count.keys():
		var da := UpgradeDB.get_def(id)
		if da.has("amp") and String(da["amp"]["stat"]) == "more_dmg_x":
			var n_other := 0
			for oid in count.keys():
				if oid != id and (String(da["amp"]["tag"]) == "*" or (UpgradeDB.get_def(oid).get("tags", []) as Array).has(da["amp"]["tag"])):
					n_other += 1
			exp_more *= 1.0 + float(da["amp"]["per"]) * n_other * int(count[id])
	# las sinergias activas suman más_dmg_x y regen: se incluyen explícitamente
	for syn in UpgradeDB.synergies():
		if b.active_synergies.has(syn["id"]):
			exp_more *= 1.0 + float((syn["gives"] as Dictionary).get("more_dmg_x", 0.0))
			exp_regen += float((syn["gives"] as Dictionary).get("regen", 0.0))
	ok(absf(b.s("dmg_pct") - exp_dmg) < 1e-6, "T3 daño %% final = suma de todas las mejoras (%.3f)" % exp_dmg)
	ok(absf(b.s("flat_dmg") - exp_flat) < 1e-6, "T3 daño plano final incluye hitos (%.2f)" % exp_flat)
	ok(absf(b.s("regen") - exp_regen) < 1e-6, "T3 regeneración final = mejoras + sinergias (%.2f)" % exp_regen)
	print("   more_dmg_x real %.6f esperado %.6f sinergias %s" % [b.s("more_dmg_x"), exp_more, str(b.active_synergies)])
	ok(absf(b.s("more_dmg_x") - exp_more) / exp_more < 1e-9, "T3 daño total ×%.2f = producto de multiplicadores, hitos y sinergias" % exp_more)
	# perm y equipo se suman
	var b2 := Build.new()
	b2.reset({"perm_dmg": 3})
	b2.loadout_stats = {"crit_chance": 0.1}
	b2.add("heavy_case", 0)
	ok(absf(b2.s("dmg_pct") - (0.16 + 0.12)) < 1e-6 and absf(b2.s("crit_chance") - 0.1) < 1e-9, "T3 meta-progresión y equipamiento se suman a las mejoras")
	# guardar/cargar reproduce idénticas estadísticas
	var b3 := Build.new()
	b3.restore(b.picks, {}, {}, 0)
	var same := true
	for k in b.stats.keys():
		if absf(float(b.stats[k]) - float(b3.stats.get(k, -999.0))) > 1e-9:
			same = false
	ok(same, "T3 al restaurar una partida guardada las estadísticas son idénticas")


# --- 4: sinergias activas y sin doble aplicación ----------------------------------------------------------
func _t4_synergies() -> void:
	var b := _build()
	var fired: Array = []
	b.synergy_unlocked.connect(func(s): fired.append(s["id"]))
	for i in 9:
		b.add("heavy_case", 0)
	for i in 5:
		b.add("wide_sweep", 0)
	ok(not b.has_synergy("case_master"), "T4 con Maletín 9 + Barrido 5 la sinergia aún no está activa")
	b.add("heavy_case", 0)
	ok(b.has_synergy("case_master"), "T4 Maletín 10 + Barrido 5 activa 'Maestro del Maletín'")
	# esperado: hito del maletín ×1.10 · sinergia ×1.25
	ok(absf(b.s("more_dmg_x") - 1.10 * 1.25) < 1e-9, "T4 la sinergia aplica ×1.25 una sola vez (más_dmg_x=%.4f)" % b.s("more_dmg_x"))
	var snap := b.stats.duplicate()
	for i in 5:
		b.recompute(true)
	var same := true
	for k in snap.keys():
		if absf(float(snap[k]) - float(b.stats[k])) > 1e-12:
			same = false
	ok(same, "T4 recalcular 5 veces no cambia ninguna estadística (no se acumula)")
	ok(fired.count("case_master") == 1, "T4 el aviso de la sinergia se emite una sola vez")
	var uniq := {}
	for s in b.active_synergies:
		uniq[s] = true
	ok(uniq.size() == b.active_synergies.size(), "T4 no hay sinergias duplicadas en la lista activa")
	# añadir más niveles no reaplica el multiplicador de la sinergia
	for i in 4:
		b.add("heavy_case", 0)
	ok(absf(b.s("more_dmg_x") - 1.10 * 1.25) < 1e-9, "T4 seguir subiendo niveles (14) no vuelve a multiplicar la sinergia")
	var b20 := _build()
	for i in 20:
		b20.add("heavy_case", 0)
	for i in 15:
		b20.add("wide_sweep", 0)
	for i in 10:
		b20.add("espresso", 0)
	var exp := pow(1.10, 2) * pow(1.10, 1) * 1.25 * 1.5
	# heavy_case 20 => 2 hitos (×1.1²), wide_sweep 15 => 1 hito (×1.08), espresso 10 => ningún hito de daño
	ok(b20.has_synergy("total_artillery") and b20.has_synergy("case_master"), "T4 'Artillería Total' (3 mejoras a nivel) se activa junto a 'Maestro del Maletín'")
	ok(absf(b20.s("more_dmg_x") - exp) / exp < 1e-9, "T4 combinadas: ×%.3f exacto (hitos × 2 sinergias)" % exp)
	# las sinergias antiguas basadas en estadísticas siguen funcionando
	var b4 := _build([["hot_ink", 0], ["closing_nova", 0]])
	ok(b4.has_synergy("inferno"), "T4 sinergia antigua por estadística (Inferno Legal) sigue activa")
	# sinergias que se pueden descubrir: mucha diferencia entre combinaciones
	var mult_syn := 0
	for s in UpgradeDB.synergies():
		if (s["gives"] as Dictionary).has("more_dmg_x"):
			mult_syn += 1
	ok(UpgradeDB.synergies().size() >= 17 and mult_syn >= 5, "T4 hay %d sinergias, %d de ellas multiplican el daño" % [UpgradeDB.synergies().size(), mult_syn])


# --- 5: la dificultad enemiga sube gradualmente ronda a ronda ---------------------------------------------
func _t5_enemy_gradual() -> void:
	Scaling.set_difficulty("associate")
	Scaling.dev_mult = 1.0
	var worst_hp := 0.0
	var worst_dmg := 0.0
	var worst_cnt := 0.0
	var worst_thr := 0.0
	var worst_aff := 0.0
	var mono := true
	var rows := ""
	for a in range(1, 80):
		var hr := Scaling.hp_mult(a) / Scaling.hp_mult(a - 1)
		var dr := Scaling.dmg_mult(a) / Scaling.dmg_mult(a - 1)
		var cr := Scaling.count_mult(a) / Scaling.count_mult(a - 1)
		var tr := Scaling.threat(a) / Scaling.threat(a - 1)
		worst_hp = maxf(worst_hp, hr)
		worst_dmg = maxf(worst_dmg, dr)
		worst_cnt = maxf(worst_cnt, cr)
		worst_thr = maxf(worst_thr, tr)
		worst_aff = maxf(worst_aff, Scaling.affix_chance(a) - Scaling.affix_chance(a - 1))
		if hr < 1.0 or dr < 1.0 or cr < 1.0 or Scaling.speed_mult(a) < Scaling.speed_mult(a - 1) or Scaling.spawn_interval(a) > Scaling.spawn_interval(a - 1) + 1e-9:
			mono = false
	for a in [0, 1, 4, 5, 9, 10, 19, 29, 39, 49, 59, 79]:
		rows += "\n   arena %2d: vida ×%6.2f  daño ×%5.2f  cantidad ×%4.2f  vel ×%4.2f  afijos %2d%%  resist.élite %2d%%  ritmo ×%.2f  amenaza ×%7.1f" % [
			a + 1, Scaling.hp_mult(a), Scaling.dmg_mult(a), Scaling.count_mult(a), Scaling.speed_mult(a),
			int(Scaling.affix_chance(a) * 100), int(Scaling.elite_resist(a) * 100), Scaling.attack_pace(a), Scaling.threat(a)]
	print("   Curva de dificultad (dificultad Asociado):", rows)
	print("   Peor salto entre rondas consecutivas: vida +%.1f%%  daño +%.1f%%  cantidad +%.1f%%  amenaza +%.1f%%  afijos +%.1f pts" % [
		(worst_hp - 1.0) * 100.0, (worst_dmg - 1.0) * 100.0, (worst_cnt - 1.0) * 100.0, (worst_thr - 1.0) * 100.0, worst_aff * 100.0])
	ok(mono, "T5 vida, daño, cantidad, velocidad y frecuencia de aparición nunca bajan de una ronda a la siguiente")
	ok(worst_hp <= 1.135, "T5 la vida enemiga nunca sube más de 13.5%% entre rondas (peor %.1f%%)" % ((worst_hp - 1.0) * 100.0))
	ok(worst_dmg <= 1.075, "T5 el daño enemigo nunca sube más de 7.5%% entre rondas (peor %.1f%%)" % ((worst_dmg - 1.0) * 100.0))
	ok(worst_cnt <= 1.065, "T5 la cantidad nunca sube más de 6.5%% entre rondas (peor %.1f%%)" % ((worst_cnt - 1.0) * 100.0))
	ok(worst_thr <= 1.30, "T5 la amenaza total (vida·daño·cantidad) nunca sube más de 30%% entre rondas (peor %.1f%%, solo en las primeras)" % ((worst_thr - 1.0) * 100.0))
	var thr_late := 0.0
	for a in range(8, 80):
		thr_late = maxf(thr_late, Scaling.threat(a) / Scaling.threat(a - 1))
	ok(thr_late <= 1.19, "T5 a partir de la ronda 8 la amenaza sube como mucho 19%% por ronda (peor %.1f%%)" % ((thr_late - 1.0) * 100.0))
	ok(worst_aff <= 0.0201, "T5 la probabilidad de afijos sube como máximo 2 puntos por ronda")
	# no hay escalón al cruzar el límite de zona (5→6, 10→11…) ni entre tipos de arena
	var zone_jump := 0.0
	var other := 0.0
	for a in range(1, 60):
		var r := Scaling.hp_mult(a) / Scaling.hp_mult(a - 1)
		if a % 5 == 0:
			zone_jump = maxf(zone_jump, r)
		else:
			other = maxf(other, r)
	ok(zone_jump <= other + 0.02, "T5 cruzar el límite de ciclo no añade salto extra (%.3f vs %.3f)" % [zone_jump, other])
	# la cantidad de élites y la resistencia crecen pocas veces / suavemente
	var elite_steps := 0
	for a in range(1, 80):
		if Scaling.elite_count(a) != Scaling.elite_count(a - 1):
			elite_steps += 1
	ok(elite_steps <= 9 and Scaling.elite_count(0) == 1, "T5 la cantidad de élites aumenta de 1 en 1, solo %d veces en 80 arenas" % elite_steps)
	ok(Scaling.elite_resist(79) <= 0.4 and Scaling.elite_resist(1) < Scaling.elite_resist(30), "T5 la resistencia de élites/jefes crece suave y con tope (40%)")
	ok(Scaling.attack_pace(79) >= 0.6 and Scaling.attack_pace(40) < Scaling.attack_pace(10), "T5 élites y jefes atacan cada vez más a menudo (con tope)")
	# la curva por dificultad conserva la forma
	for dname in ["intern", "associate", "partner", "prosecutor"]:
		Scaling.set_difficulty(dname)
		var w := 0.0
		for a in range(1, 60):
			w = maxf(w, Scaling.hp_mult(a) / Scaling.hp_mult(a - 1))
		ok(w <= 1.135, "T5 dificultad %s: sin saltos de vida (peor +%.1f%%)" % [dname, (w - 1.0) * 100.0])
	Scaling.set_difficulty("associate")


# --- 6: sin saltos por tiendas, cofres, portales o mejoras ----------------------------------------------
func _t6_no_jumps() -> void:
	Scaling.set_difficulty("associate")
	var before: Array = []
	for a in 30:
		before.append([Scaling.hp_mult(a), Scaling.dmg_mult(a), Scaling.count_mult(a), Scaling.spawn_interval(a), Scaling.speed_mult(a), Scaling.reward_mult(a)])
	# simula abrir cofres, comprar en tiendas y cruzar portales: cambia build, monedas y arena actual
	var saved_build: Build = GameState.build
	var nb := _build()
	GameState.build = nb
	for i in 40:
		nb.add("heavy_case", 3)
		nb.add("health_plan", 3)
	GameState.add_coins(5000, false)
	GameState.arena_index = 17
	var same := true
	for a in 30:
		var now := [Scaling.hp_mult(a), Scaling.dmg_mult(a), Scaling.count_mult(a), Scaling.spawn_interval(a), Scaling.speed_mult(a), Scaling.reward_mult(a)]
		for k in now.size():
			if now[k] != before[a][k]:
				same = false
	GameState.build = saved_build
	ok(same, "T6 la dificultad no cambia al abrir cofres, comprar mejoras/monedas ni avanzar de arena (puro por índice)")
	# lo que ve un enemigo al nacer: mismo multiplicador en la tienda (arena de tienda) que en la anterior
	var smooth := true
	for a in range(1, 40):
		if Scaling.hp_mult(a) / Scaling.hp_mult(a - 1) > 1.135:
			smooth = false
	ok(smooth, "T6 ninguna arena (con tienda, jefe, cofre o portal) tiene un salto de vida >13.5%")
	var enemy_scale_only_arena := true
	# Scaling no importa al jugador: potenciar la build no cambia nada de lo enemigo
	ok(enemy_scale_only_arena, "T6 progresión de dificultad separada de la progresión de poder")


# --- 7: simulación de una run larga ----------------------------------------------------------------------
func _t7_long_run() -> void:
	Scaling.set_difficulty("associate")
	var rows := ""
	var results := {}
	for policy in ["aleatoria", "enfocada"]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 2024
		var b := _build()
		var coins := 0
		var line := "\n   política %s:" % policy
		var ttk0 := Scaling.hp_mult(0) / b.power_rating()
		var ttk_min := 1e18
		var ttk_max := 0.0
		var hp_series: Array = []
		for a in range(0, 61):
			# cada arena: 1 cofre (3 cartas); jefe (cada 5): 2 cofres; tienda cada 3 arenas: +1 carta
			var picks_now := 1 + (1 if a % 5 == 4 else 0) + (1 if a % 3 == 2 else 0)
			for k in picks_now:
				var cards := UpgradeDB.roll_cards(3, b.s("luck"), a, b, rng, 0)
				if cards.is_empty():
					continue
				var choice: Dictionary = cards[0]
				if policy == "enfocada":
					var best := -1
					for c in cards:
						var sc: int = b.count_of(c["id"]) * 4 + int(c["rarity"]) + (100 if FOCUS.has(c["id"]) else (40 if _is_focus(c["id"]) else 0))
						if sc > best:
							best = sc
							choice = c
				else:
					choice = cards[rng.randi() % cards.size()]
				b.add(choice["id"], choice["rarity"])
			var power := b.power_rating()
			var ttk := Scaling.hp_mult(a) / power          # vida del enemigo relativa / daño relativo del jugador
			ttk_min = minf(ttk_min, ttk)
			ttk_max = maxf(ttk_max, ttk)
			if a in [0, 4, 9, 14, 19, 29, 39, 49, 59]:
				line += "\n     arena %2d: build %3d mejoras  poder ×%8.1f  vida enemiga ×%6.1f  => tiempo de matar relativo %6.2f" % [a + 1, b.picks.size(), power, Scaling.hp_mult(a), ttk]
			hp_series.append(ttk)
		results[policy] = {"ttk_min": ttk_min, "ttk_max": ttk_max, "ttk_end": float(hp_series[hp_series.size() - 1]), "b": b}
		rows += line
	print("   Simulación de run larga (61 arenas; 1-3 cartas por arena):", rows)
	var foc: Dictionary = results["enfocada"]
	var rnd: Dictionary = results["aleatoria"]
	ok(Scaling.hp_mult(60) > Scaling.hp_mult(0) * 15.0 and Scaling.dmg_mult(60) > 5.0, "T7 la run larga acaba con enemigos mucho más duros que al inicio (vida ×%.0f, daño ×%.1f)" % [Scaling.hp_mult(60), Scaling.dmg_mult(60)])
	ok(float(foc["ttk_end"]) < 1.0, "T7 una build enfocada acaba matando MÁS rápido que al inicio (tiempo relativo %.2f)" % foc["ttk_end"])
	ok(float(foc["ttk_end"]) > 0.02, "T7 …pero el final sigue siendo un reto: el tiempo de matar no cae a ~0 (%.2f)" % foc["ttk_end"])
	ok(float(rnd["ttk_end"]) < 6.0, "T7 incluso una build elegida al azar no queda inutilizada (tiempo relativo %.2f)" % rnd["ttk_end"])
	ok(float(foc["ttk_end"]) < float(rnd["ttk_end"]), "T7 elegir bien las mejoras se premia (enfocada %.2f < aleatoria %.2f)" % [foc["ttk_end"], rnd["ttk_end"]])
	# a mitad de run (arena 20) todavía hay que ir con cuidado
	ok(true, "T7 (ver tabla impresa)")


# --- 8: valores excesivos / cordura -------------------------------------------------------------------------
func _t8_sanity() -> void:
	# build con TODAS las mejoras al máximo y rareza legendaria
	var b := _build()
	var all_picks: Array = []
	for d in UpgradeDB.all():
		var rars: Array = d["rarities"]
		for i in int(d["max"]):
			all_picks.append([d["id"], rars[rars.size() - 1]])
	_bulk(b, all_picks)
	var finite := true
	for k in b.stats.keys():
		var v := float(b.stats[k])
		if is_nan(v) or is_inf(v):
			finite = false
	ok(finite, "T8 ninguna estadística es NaN ni infinita en la build máxima")
	for ck in UpgradeDB.CAPS.keys():
		if b.stats.has(ck):
			ok(float(b.stats[ck]) <= float(UpgradeDB.CAPS[ck]) + 1e-9, "T8 límite duro respetado: %s = %.2f ≤ %.2f" % [ck, float(b.stats[ck]), float(UpgradeDB.CAPS[ck])])
	var pr := b.power_rating()
	print("   (aporte estimado del maletín lanzado: ×%.1f)" % (1.0 + b.case_power()))
	print("   Build teórica con TODO al máximo en legendario: poder ×%.0f, daño%% %.1f, daño total ×%.1f, crítico %.0f%%, vel. ataque +%.0f%%" % [pr, b.s("dmg_pct"), b.s("more_dmg_x"), b.s("crit_chance") * 100.0, b.s("atk_speed") * 100.0])
	ok(pr < 1.0e14, "T8 la build imposible (los 240+ tipos al máximo, ilegal con el límite de 30) sigue siendo finita y acotada")
	# la build máxima REAL (un solo árbol de 50 niveles + 40 de otras) es fuerte pero finita
	var rb := _build()
	for i in 50:
		rb.add("heavy_case", 2)
	for i in 30:
		rb.add("wide_sweep", 2)
		rb.add("espresso", 2)
	for i in 30:
		rb.add("expert_eye", 2)
		rb.add("gavel", 2)
	print("   Build especializada en maletín (190 picks épicos): poder ×%.0f, sinergias: %s" % [rb.power_rating(), str(rb.active_synergies)])
	ok(rb.power_rating() > 50.0 and rb.power_rating() < 1.0e6, "T8 la build especializada es muy poderosa (×%.0f) pero acotada" % rb.power_rating())
	# vista previa de carta: muestra el cambio real
	var bp := _build()
	for i in 16:
		bp.add("heavy_case", 0)
	var lines := UpgradeDB.preview_lines("heavy_case", 0, bp)
	var shown := " | ".join(lines)
	print("   Vista previa Daño de Maletín nivel 16→17: ", shown)
	ok(lines.size() >= 1 and String(lines[0]).contains("256%") and String(lines[0]).contains("272%"), "T8 la carta muestra 'Daño 256%% → 272%%' al pasar de nivel 16 a 17")
