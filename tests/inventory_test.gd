extends Node
## Pruebas LÓGICAS (sin renderizado) del catálogo de 200+ mejoras, el inventario de 30 tipos, la venta, los cofres
## y el guardado:    godot --headless res://tests/inventory_test.tscn
## Las pruebas con jugador/enemigos reales y con toques en pantalla están en tests/invtest.gd (renderizado).

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
	_t1_catalog()
	_t1b_effects_connected()
	_t2_stackable()
	_t3_limit()
	_t4_sell()
	_t7_chests()
	_t8_max_level()
	_t9_save_load()
	_t_perm_vs_run()
	print("[RESULT] inventario: %d ok, %d fallos" % [passes, fails.size()])
	for f in fails:
		print("  FALLO: ", f)
	get_tree().quit(1 if fails.size() > 0 else 0)


func _build() -> Build:
	var b := Build.new()
	b.reset({})
	return b


func _fill(b: Build, ids: Array, rarity := 0) -> void:
	for id in ids:
		b.add(id, rarity, true)


## Los 30 primeros tipos "normales" (sin requisitos de equipo/arena) para llenar el inventario.
func _first_types(n: int, skip: Array = []) -> Array:
	var out: Array = []
	for d in UpgradeDB.all():
		if out.size() >= n:
			break
		if skip.has(d["id"]) or (d.get("req", {}) as Dictionary).size() > 0:
			continue
		out.append(d["id"])
	return out


# --- 1: catálogo ------------------------------------------------------------------------------------------
func _t1_catalog() -> void:
	var defs := UpgradeDB.all()
	ok(defs.size() >= 200, "T1 existen al menos 200 mejoras (hay %d)" % defs.size())
	var ids := {}
	var names := {}
	var sigs := {}
	var dup_id := 0
	var dup_name := 0
	var dup_sig := 0
	var bad_fields := 0
	var bad_icon := 0
	var cats := {}
	for d in defs:
		if ids.has(d["id"]):
			dup_id += 1
		ids[d["id"]] = true
		if names.has(d["name"]):
			dup_name += 1
			print("   nombre repetido: ", d["name"])
		names[d["name"]] = true
		var keys: Array = (d["stats"] as Dictionary).keys()
		keys.sort()
		var sig := ",".join(keys)
		if sigs.has(sig):
			dup_sig += 1
			print("   misma estadística: ", d["id"], " = ", sigs[sig])
		sigs[sig] = d["id"]
		for f in ["id", "name", "cat", "icon", "desc", "stats", "max", "rarities", "tags", "req"]:
			if not d.has(f):
				bad_fields += 1
		if String(d["name"]) == "" or String(d["desc"]) == "" or (d["stats"] as Dictionary).is_empty() or (d["tags"] as Array).is_empty():
			bad_fields += 1
		if not (IconView.ALIAS.has(d["icon"]) or IconView.ALIAS.values().has(d["icon"])):
			bad_icon += 1
			print("   icono desconocido: ", d["id"], " ", d["icon"])
		cats[d["cat"]] = int(cats.get(d["cat"], 0)) + 1
	ok(dup_id == 0, "T1 identificadores únicos")
	ok(dup_name == 0, "T1 nombres únicos (no son variantes de nombre)")
	ok(dup_sig == 0, "T1 cada mejora tiene un conjunto de estadísticas propio (no son variantes de color/icono)")
	ok(bad_fields == 0, "T1 todas tienen id, nombre, descripción, icono, rareza, etiquetas, requisitos, estadísticas y máximo")
	ok(bad_icon == 0, "T1 todos los iconos existen")
	ok(cats.size() >= 12, "T1 hay %d categorías: %s" % [cats.size(), str(cats)])
	var rar_seen := {}
	for d in defs:
		for r in d["rarities"]:
			rar_seen[r] = true
	ok(rar_seen.size() == 4, "T1 existen las 4 rarezas")
	var tagged := 0
	for d in defs:
		if (d["tags"] as Array).size() >= 1:
			tagged += 1
	ok(tagged == defs.size(), "T1 todas llevan etiquetas de sinergia")
	var equip := 0
	var gated := 0
	for d in defs:
		var rq: Dictionary = d.get("req", {})
		if rq.has("equip_any") or rq.has("not_equip"):
			equip += 1
		if not rq.is_empty():
			gated += 1
	ok(equip >= 2 and gated >= 10, "T1 hay restricciones de aparición (%d con requisitos, %d por equipamiento)" % [gated, equip])


# --- 1b: todo efecto está CONECTADO a un sistema real ----------------------------------------------------
func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f != null else ""


func _scripts(dir: String, out: Array) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for sub in DirAccess.get_directories_at(dir):
		_scripts(dir + "/" + sub, out)


func _t1b_effects_connected() -> void:
	var files: Array = []
	_scripts("res://scripts", files)
	var code := ""
	for f in files:
		if f.ends_with("upgrade_catalog.gd"):
			continue          # las definiciones no cuentan como "uso"
		if f.ends_with("upgrade_db.gd"):
			# de upgrade_db solo cuentan las líneas que LEEN estadísticas (p. ej. la suerte épica al sortear rarezas)
			for line in _read(f).split("\n"):
				if line.contains('.s("'):
					code += line + "\n"
			continue
		code += _read(f) + "\n"
	var cat_defs := _read("res://scripts/core/upgrade_db.gd")
	var unused: Array = []
	var bad_trig: Array = []
	var seen_keys := {}
	var amp_markers := {}
	for d in UpgradeDB.all():
		if d.has("amp"):
			for k in (d["stats"] as Dictionary).keys():
				amp_markers[k] = true
	for d in UpgradeDB.all():
		for k in (d["stats"] as Dictionary).keys():
			var key := String(k)
			if seen_keys.has(key) or amp_markers.has(key):
				continue
			seen_keys[key] = true
			if key.begins_with("t:"):
				var p := key.split(":")
				if p.size() != 3 or not Perks.EVENTS.has(p[1]) or not Perks.EFFECTS.has(p[2]):
					bad_trig.append(key)
				elif not (code.contains('fire("%s"' % p[1]) or Perks.TIMER_PERIOD.has(p[1])):
					unused.append(key + " (evento sin emisor)")
			elif key.begins_with("c:"):
				if not Perks.CONDS.has(key.substr(2)):
					bad_trig.append(key)
			elif key.begins_with("s:"):
				var src := key.substr(2)
				if not Perks.SOURCES.has(src) or not (code.contains('"src": "%s"' % src) or code.contains("'src': '%s'" % src) or code.contains('"%s"' % src)):
					bad_trig.append(key)
			elif not code.contains('"%s"' % key):
				unused.append(key)
	print("   claves sin lector en el código: ", unused)
	print("   disparadores/condiciones/fuentes no válidos: ", bad_trig)
	ok(unused.is_empty(), "T1 toda estadística de toda mejora la lee el código real de combate/jugador/habilidades (%d claves distintas)" % seen_keys.size())
	ok(bad_trig.is_empty(), "T1 todo disparador/condición/fuente usa eventos, efectos y condiciones que el motor implementa")
	# todas las claves "t:" usan un efecto con implementación (el match de apply_effect)
	var perks_code := _read("res://scripts/core/perks.gd")
	var no_impl: Array = []
	for e in Perks.EFFECTS:
		if not perks_code.contains('"%s"' % e):
			no_impl.append(e)
	ok(no_impl.is_empty(), "T1 todos los efectos de disparador tienen implementación en Perks")
	var no_cond: Array = []
	for c in Perks.CONDS:
		if not perks_code.contains('"%s"' % c):
			no_cond.append(c)
	ok(no_cond.is_empty(), "T1 todas las condiciones tienen implementación en Perks.cond_met")
	var rest := cat_defs   # silenciar variable sin uso
	rest = ""


# --- 2: acumulables -------------------------------------------------------------------------------------------
func _buddies_for(d: Dictionary) -> Array:
	# mejoras "Catalizador": necesitan otras mejoras con su etiqueta para mostrar efecto
	var out: Array = []
	if d.has("amp"):
		for o in UpgradeDB.all():
			if out.size() >= 3:
				break
			if o["id"] != d["id"] and not o.has("amp") and (d["amp"]["tag"] == "*" or (o["tags"] as Array).has(d["amp"]["tag"])):
				out.append(o["id"])
	return out


func _t2_stackable() -> void:
	var stackable := 0
	var lvl50 := 0
	var lvl20 := 0
	var single := 0
	var not_growing: Array = []
	var not_monotone: Array = []
	for d in UpgradeDB.all():
		var mx := int(d["max"])
		if mx > 1:
			stackable += 1
		else:
			single += 1
		if mx >= 50:
			lvl50 += 1
		if mx >= 20:
			lvl20 += 1
		if mx < 2:
			continue
		var buddies := _buddies_for(d)
		var prev := {}
		var grew_always := true
		var lv_check := mx
		for lv in range(1, lv_check + 1):
			var picks: Array = []
			for bd in buddies:
				picks.append({"id": bd, "rarity": 0})
			for i in lv:
				picks.append({"id": d["id"], "rarity": 0})
			var st: Dictionary = Build.compute(picks, {}, {}, 0)["stats"]
			if lv > 1 and _same_stats(st, prev):
				grew_always = false
			prev = st
		if not grew_always:
			not_growing.append(d["id"])
	print("   ACUMULABLES: %d de %d (máx. 1: %d) · con tope 50: %d · con tope ≥20: %d" % [stackable, UpgradeDB.all().size(), single, lvl50, lvl20])
	var l50: Array = []
	for d in UpgradeDB.all():
		if int(d["max"]) >= 50:
			l50.append(d["id"])
	print("   Nivel máx. 50: ", l50)
	ok(not_growing.is_empty(), "T2 en TODAS las acumulables cada nivel nuevo cambia las estadísticas reales (fallan: %s)" % str(not_growing))
	ok(stackable >= 150, "T2 más de 150 mejoras son acumulables (%d)" % stackable)
	# el contador de nivel y el tope
	var b := _build()
	for i in 5:
		b.add("heavy_case", 0)
	ok(b.count_of("heavy_case") == 5 and b.type_count() == 1, "T2 5 veces la misma mejora = nivel 5 en 1 solo espacio")
	var b2 := _build()
	for i in 60:
		b2.add("heavy_case", 0)
	ok(b2.count_of("heavy_case") == 50, "T2 Daño de Maletín se detiene en el nivel 50 (add rechaza el nivel 51)")


func _same_stats(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k in a.keys():
		if not b.has(k) or absf(float(a[k]) - float(b[k])) > 1e-12:
			return false
	return true


# --- 3: límite de 30 tipos ---------------------------------------------------------------------------------------
func _t3_limit() -> void:
	var b := _build()
	var ids := _first_types(Build.MAX_TYPES + 5)
	for i in Build.MAX_TYPES:
		b.add(ids[i], 0)
	ok(b.type_count() == 30 and b.is_full(), "T3 con 30 tipos distintos el inventario está lleno")
	# subir niveles NO ocupa espacio
	var first: String = ids[0]
	var lv := 1
	for i in 15:
		if b.add(first, 0):
			lv += 1
	ok(b.type_count() == 30 and b.count_of(first) > 10, "T3 la mejora %s sube a nivel %d y el inventario sigue en 30 tipos (los niveles no cuentan)" % [first, b.count_of(first)])
	var extra: String = ids[30]
	var before_picks := b.picks.size()
	var before_stats := b.stats.duplicate()
	ok(not b.can_add(extra), "T3 no se puede añadir una mejora NUEVA con 30 tipos")
	ok(not b.add(extra, 0), "T3 add() rechaza la mejora nueva y no cambia nada")
	ok(b.picks.size() == before_picks and _same_stats(b.stats, before_stats), "T3 el rechazo no modifica picks ni estadísticas")
	var why := b.why_not(extra)
	ok(why.contains("lleno") and why.contains("30"), "T3 el motivo se explica: «%s»" % why)
	ok(b.can_add(ids[1]), "T3 sí se pueden seguir mejorando las que ya tienes")
	# vender libera el hueco
	var res := b.remove(ids[2], true)
	ok(bool(res["ok"]) and b.type_count() == 29 and not b.is_full(), "T3 vender libera un espacio (29/30)")
	ok(b.add(extra, 0), "T3 tras liberar el espacio ya se puede añadir una mejora nueva")
	ok(b.type_count() == 30, "T3 vuelve a 30/30")


# --- 4/5/6: vender y desechar ---------------------------------------------------------------------------------
func _t4_sell() -> void:
	var b := _build()
	var core := ["heavy_case", "wide_sweep", "espresso", "expert_eye", "gavel"]
	for id in core:
		for i in 12:
			b.add(id, 2)
	for id in _first_types(8, core):
		b.add(id, 1)
	b.add("heavy_case", 3)      # un nivel legendario suma más al valor
	var syn_before := b.active_synergies.duplicate()
	ok(syn_before.has("case_master"), "T4 la sinergia «Maestro del Maletín» está activa antes de vender (%s)" % str(syn_before))
	var shown := b.sell_value("heavy_case")
	ok(shown > 0, "T4/T5 el valor mostrado de vender Daño de Maletín nv13 es $%d" % shown)
	# fórmula independiente
	var exp := 0.0
	var k := 0
	for p in b.picks:
		if p["id"] == "heavy_case":
			exp += float(Config.ECONOMY["attr_price"]) * (1.0 + 0.7 * int(p["rarity"])) * 0.5 * (1.0 + 0.04 * k)
			k += 1
	exp = round(exp * (1.0 + b.s("sell_bonus")))
	ok(int(exp) == shown, "T5 el valor coincide con la fórmula (rareza × nivel × economía): $%d" % int(exp))
	# vender de verdad: dinero recibido = valor mostrado (misma ruta que el botón del inventario)
	GameState.coins = 100
	var syn_stats := b.stats.duplicate()
	var types_before := b.type_count()
	var res := b.remove("heavy_case", true)
	GameState.add_coins(int(res["value"]), false)
	ok(int(res["value"]) == shown and GameState.coins == 100 + shown, "T5 dinero recibido = valor mostrado (+$%d)" % shown)
	ok(b.count_of("heavy_case") == 0 and int(res["levels"]) == 13, "T4 se eliminan los 13 niveles")
	ok(b.type_count() == types_before - 1, "T4 el espacio queda libre")
	# recalculo exacto: idéntico a una build construida desde cero SIN esa mejora
	var fresh := _build()
	for p in b.picks:
		fresh.add(p["id"], int(p["rarity"]), true)
	ok(_same_stats(b.stats, fresh.stats), "T6 tras vender las estadísticas son idénticas a las de una build limpia sin ella (sin bonos residuales)")
	ok(_same_stats(Build.compute(b.picks, b.perm, b.loadout_stats, b.level)["stats"], b.stats), "T6 recalcular otra vez no cambia nada")
	ok(not b.active_synergies.has("case_master"), "T6 la sinergia que dependía de ella se desactiva")
	ok(b.s("dmg_pct") < float(syn_stats["dmg_pct"]) - 1.0, "T6 el daño baja de %.2f a %.2f" % [float(syn_stats["dmg_pct"]), b.s("dmg_pct")])
	ok(b.s("more_dmg_x") < float(syn_stats["more_dmg_x"]), "T6 los multiplicadores de hito y de sinergia se retiran")
	# desechar: sin dinero
	var coins := GameState.coins
	var lost_predict := b.synergies_lost_if_removed("wide_sweep")
	var r2 := b.remove("wide_sweep", false)
	ok(int(r2["value"]) == 0 and GameState.coins == coins, "T4 desechar no da dinero")
	ok(b.count_of("wide_sweep") == 0, "T4 desechar elimina la mejora")
	for sid in lost_predict:
		ok(not b.active_synergies.has(sid), "T6 la advertencia de la confirmación («pierdes %s») es cierta" % sid)
	var fresh2 := _build()
	for p in b.picks:
		fresh2.add(p["id"], int(p["rarity"]), true)
	ok(_same_stats(b.stats, fresh2.stats), "T6 tras desechar las estadísticas siguen siendo exactas")
	# vender algo que no se tiene
	ok(not bool(b.remove("no_existe", true)["ok"]), "T4 no se puede vender una mejora que no tienes")
	# el valor sube con el nivel y la rareza
	var low := _build()
	low.add("espresso", 0)
	var hi := _build()
	hi.add("espresso", 3)
	var lv10 := _build()
	for i in 10:
		lv10.add("espresso", 0)
	ok(hi.sell_value("espresso") > low.sell_value("espresso") and lv10.sell_value("espresso") > low.sell_value("espresso") * 9, "T5 el precio crece con la rareza y con el nivel")
	# bonus de venta
	var sb := _build()
	sb.add("espresso", 0)
	var plain := sb.sell_value("espresso")
	ok(plain > 0, "T5 valor base $%d" % plain)


# --- 7: cofres con inventario lleno ------------------------------------------------------------------------------
func _t7_chests() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var b := _build()
	var ids := _first_types(Build.MAX_TYPES)
	for id in ids:
		b.add(id, 0)
	var bad := 0
	var new_cards := 0
	var dups := 0
	var empty := 0
	for n in 300:
		var cards := UpgradeDB.roll_cards(3, 0.2, n % 40, b, rng, 0)
		if cards.is_empty():
			empty += 1
		var seen := {}
		for c in cards:
			if not b.can_add(c["id"]):
				bad += 1
			if b.count_of(c["id"]) == 0:
				new_cards += 1
			if seen.has(c["id"]):
				dups += 1
			seen[c["id"]] = true
	ok(new_cards == 0 and bad == 0, "T7 con 30/30 el cofre solo ofrece mejoras que ya tienes y que se pueden subir (300 cofres)")
	ok(dups == 0 and empty == 0, "T7 sin duplicados en el cofre y nunca vacío")
	var b2 := _build()
	b2.add("espresso", 0)
	var new2 := 0
	for n in 100:
		for c in UpgradeDB.roll_cards(3, 0.2, 10, b2, rng, 0):
			if b2.count_of(c["id"]) == 0:
				new2 += 1
	ok(new2 > 50, "T7 con espacio libre sí ofrece mejoras nuevas")
	# todo al máximo y lleno: no se ofrece nada imposible
	var b3 := _build()
	var all_picks: Array = []
	for id in ids:
		var mx := mini(int(UpgradeDB.get_def(id)["max"]), 50)
		for i in mx:
			all_picks.append({"id": id, "rarity": 0})
	b3.restore(all_picks, {}, {}, 0)
	var imp := 0
	for n in 50:
		for c in UpgradeDB.roll_cards(3, 0.2, 10, b3, rng, 0):
			imp += 1
	ok(imp == 0, "T7 con 30/30 y todo al máximo el cofre no ofrece nada (no hay selecciones imposibles)")
	# requisitos de aparición
	var gated := 0
	for n in 200:
		for c in UpgradeDB.roll_cards(3, 0.2, 0, _build(), rng, 0):
			var rq: Dictionary = UpgradeDB.get_def(c["id"]).get("req", {})
			if not rq.is_empty() and rq.has("arena") and int(rq["arena"]) > 0:
				gated += 1
	ok(gated == 0, "T7 las mejoras con arena mínima no salen en la arena 1")


# --- 8: máximo ---------------------------------------------------------------------------------------------------
func _t8_max_level() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var leaked := 0
	var tested := 0
	for d in UpgradeDB.all():
		var b := _build()
		var mx := mini(int(d["max"]), 50)
		for i in mx:
			b.add(d["id"], (d["rarities"] as Array)[0], true)
		tested += 1
		for n in 8:
			for c in UpgradeDB.roll_cards(3, 0.0, 12, b, rng, 0):
				if c["id"] == d["id"]:
					leaked += 1
		if b.can_add(d["id"]):
			leaked += 1
	ok(leaked == 0, "T8 ninguna de las %d mejoras aparece ni se puede añadir en su nivel máximo" % tested)


# --- 9: guardar y cargar ----------------------------------------------------------------------------------------------
func _t9_save_load() -> void:
	var b := GameState.build
	b.reset({})
	var names := ["heavy_case", "wide_sweep", "espresso", "expert_eye", "gavel", "static_objection", "echo_wave", "hot_ink"]
	for id in names:
		for i in 11:
			b.add(id, 1, true)
	for id in _first_types(10, names):
		b.add(id, 0, true)
	for id in ["hit_burn", "crit_nova", "kill_rage", "slam_push"]:
		b.add(id, 1, true)
	b.add("heavy_case", 3, true)
	var stats0 := b.stats.duplicate()
	var syn0 := b.active_synergies.duplicate()
	var types0 := b.type_count()
	var picks0 := b.picks.size()
	var trig0 := b.triggers.size()
	var snap := GameState.snapshot_run("portal")
	# guardar -> JSON -> cargar (como el disco)
	var json := JSON.stringify(snap)
	var parsed: Dictionary = JSON.parse_string(json)
	GameState.restore_run(parsed)
	ok(GameState.build.picks.size() == picks0, "T9 cargar restaura exactamente %d niveles (sin duplicar)" % picks0)
	ok(GameState.build.type_count() == types0, "T9 restaura los %d tipos" % types0)
	ok(_same_stats(GameState.build.stats, stats0), "T9 las estadísticas son idénticas tras guardar y cargar")
	var syn_same := GameState.build.active_synergies.size() == syn0.size()
	for s in syn0:
		if not GameState.build.active_synergies.has(s):
			syn_same = false
	ok(syn_same, "T9 las mismas sinergias (%d) siguen activas" % syn0.size())
	ok(trig0 >= 4 and GameState.build.triggers.size() == trig0, "T9 los disparadores precalculados no se duplican (%d)" % trig0)
	# cargar dos veces seguidas no acumula
	var parsed2: Dictionary = JSON.parse_string(json)
	GameState.restore_run(parsed2)
	GameState.restore_run(JSON.parse_string(json))
	ok(GameState.build.picks.size() == picks0 and _same_stats(GameState.build.stats, stats0), "T9 cargar tres veces no duplica ninguna bonificación")
	ok(GameState.build.count_of("heavy_case") == 12, "T9 el nivel de cada mejora se conserva (Daño de Maletín nv12)")
	# vender, guardar y cargar: la venta persiste
	var res := GameState.build.remove("heavy_case", true)
	ok(bool(res["ok"]), "T9 vendida antes de guardar")
	var snap2 := GameState.snapshot_run("portal")
	var parsed3: Dictionary = JSON.parse_string(JSON.stringify(snap2))
	var stats_sold := GameState.build.stats.duplicate()
	GameState.restore_run(parsed3)
	ok(GameState.build.count_of("heavy_case") == 0 and GameState.build.type_count() == types0 - 1, "T9 la venta persiste al guardar y cargar")
	ok(_same_stats(GameState.build.stats, stats_sold), "T9 y las estadísticas siguen siendo las de la build sin ella")
	# datos corruptos: una mejora desconocida no rompe la carga
	var corrupt := parsed3.duplicate(true)
	(corrupt["picks"] as Array).append({"id": "mejora_borrada", "rarity": 1})
	GameState.restore_run(corrupt)
	ok(GameState.build.type_count() <= Build.MAX_TYPES, "T9 una mejora desconocida en el guardado no rompe la carga")


# --- permanentes vs temporales de la run -----------------------------------------------------------------------
func _t_perm_vs_run() -> void:
	var b := _build()
	b.reset({"perm_dmg": 3})
	b.add("heavy_case", 0)
	var with_run := b.s("dmg_pct")
	b.reset({"perm_dmg": 3})
	ok(b.picks.is_empty() and b.type_count() == 0, "Perm: empezar una run nueva borra las mejoras temporales (inventario vacío)")
	ok(b.s("dmg_pct") > 0.0 and b.s("dmg_pct") < with_run, "Perm: la mejora permanente de la tienda (+%d%%) se conserva y no se mezcla con el inventario" % int(b.s("dmg_pct") * 100.0))
	ok(not b.counts.has("perm_dmg"), "Perm: las permanentes no ocupan espacios de los 30")
