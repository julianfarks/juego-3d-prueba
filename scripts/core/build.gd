class_name Build
extends RefCounted
## Estado de mejoras de la partida actual y estadísticas calculadas.
## Las estadísticas se recalculan al añadir una mejora. Todo el código de juego
## consulta Build.s("clave") en vez de números fijos.

signal changed
signal synergy_unlocked(syn: Dictionary)

var picks: Array = []                 # historial: [{id, rarity}]
var counts: Dictionary = {}           # id -> veces elegida
var stats: Dictionary = {}            # estadísticas calculadas
var active_synergies: Array = []      # ids de sinergias activas
var perm: Dictionary = {}             # id perm -> nivel (meta-progresión)
var level := 0                        # nivel de caso (XP) de la partida
var loadout_stats: Dictionary = {}    # estadísticas del equipamiento elegido en la Sala Central
const MAX_TYPES := 30                 # tipos de mejora distintos a la vez (los niveles NO cuentan como espacios)
var triggers: Array = []              # [{event, effect, v}] precalculado en recompute (ver Perks)
var trigger_events: Dictionary = {}   # evento -> true (para descartar rápido)
var conds: Array = []                 # [[condición, bonus]]
var srcs: Dictionary = {}             # fuente -> bonus de daño


func reset(perm_levels: Dictionary) -> void:
	picks.clear()
	counts.clear()
	active_synergies.clear()
	perm = perm_levels.duplicate()
	recompute(false)


## Reconstruye el estado de una partida guardada (mejoras elegidas) sin emitir avisos de sinergia.
func restore(saved_picks: Array, perm_levels: Dictionary, lo_stats: Dictionary, lvl: int) -> void:
	picks.clear()
	counts.clear()
	active_synergies.clear()
	perm = perm_levels.duplicate()
	loadout_stats = lo_stats.duplicate()
	level = lvl
	for p in saved_picks:
		var id := String(p["id"])
		picks.append({"id": id, "rarity": int(p["rarity"])})
		counts[id] = count_of(id) + 1
	recompute(false)
	# las sinergias ya activas no deben anunciarse otra vez
	changed.emit()


func count_of(id: String) -> int:
	return int(counts.get(id, 0))


## Tipos de mejora distintos en la build.
func type_count() -> int:
	return counts.size()


func is_full() -> bool:
	return counts.size() >= MAX_TYPES


## ¿Puede la build aceptar esta mejora? (espacio libre o ya la tiene, y no está en su nivel máximo)
func can_add(id: String) -> bool:
	var d := UpgradeDB.get_def(id)
	if d.is_empty():
		return false
	if count_of(id) >= mini(int(d["max"]), UpgradeDB.MAX_LEVEL):
		return false
	return count_of(id) > 0 or counts.size() < MAX_TYPES


## Motivo legible por el que no se puede aceptar la mejora ("" si se puede).
func why_not(id: String) -> String:
	var d := UpgradeDB.get_def(id)
	if d.is_empty():
		return "Mejora desconocida"
	if count_of(id) >= mini(int(d["max"]), UpgradeDB.MAX_LEVEL):
		return "%s ya está en su nivel máximo" % d["name"]
	if count_of(id) == 0 and counts.size() >= MAX_TYPES:
		return "Inventario lleno (%d/%d tipos): vende o desecha una mejora para liberar un espacio" % [counts.size(), MAX_TYPES]
	return ""


## Añade un nivel. Devuelve false (sin cambiar nada) si no cabe o está al máximo; 'force' lo omite (solo pruebas).
func add(id: String, rarity: int, force := false) -> bool:
	if not force and not can_add(id):
		return false
	picks.append({"id": id, "rarity": rarity})
	counts[id] = count_of(id) + 1
	recompute(true)
	return true


## Valor de venta (monedas) de TODOS los niveles de una mejora. Misma función para mostrarlo y para cobrarlo.
func sell_value(id: String) -> int:
	var total := 0.0
	var k := 0
	for p in picks:
		if p["id"] != id:
			continue
		var base := float(Config.ECONOMY["attr_price"]) * (1.0 + 0.7 * int(p["rarity"])) * 0.5
		total += base * (1.0 + 0.04 * k)
		k += 1
	return int(round(total * (1.0 + s("sell_bonus"))))


## Elimina la mejora COMPLETA (todos sus niveles). Recalcula estadísticas y sinergias.
## Devuelve {"ok", "levels", "value"}; 'sell' false = desechar (sin dinero).
func remove(id: String, sell := true) -> Dictionary:
	if count_of(id) == 0:
		return {"ok": false, "levels": 0, "value": 0}
	var value := sell_value(id) if sell else 0
	var levels := count_of(id)
	var keep: Array = []
	for p in picks:
		if p["id"] != id:
			keep.append(p)
	picks = keep
	counts.erase(id)
	var before := active_synergies.duplicate()
	active_synergies.clear()
	recompute(false)
	# las sinergias que siguen activas no deben volver a anunciarse
	for sid in before:
		if not active_synergies.has(sid):
			pass
	return {"ok": true, "levels": levels, "value": value}


## Rareza más alta entre los niveles de una mejora.
func rarity_of(id: String) -> int:
	var r := 0
	for p in picks:
		if p["id"] == id:
			r = maxi(r, int(p["rarity"]))
	return r


## Sinergias activas que se perderían al quitar esta mejora (ids).
func synergies_lost_if_removed(id: String) -> Array:
	var keep: Array = []
	for p in picks:
		if p["id"] != id:
			keep.append(p)
	var res := Build.compute(keep, perm, loadout_stats, level)
	var lost: Array = []
	for sid in active_synergies:
		if not (res["syn"] as Array).has(sid):
			lost.append(sid)
	return lost


## Estadísticas que aporta una sola mejora (todos sus niveles, hitos y amplificación por etiquetas), sin sinergias ni topes.
func effects_of(id: String) -> Dictionary:
	var only: Array = []
	for p in picks:
		if p["id"] == id:
			only.append(p)
	var res := Build.compute(only, {}, {}, 0, true)
	var out: Dictionary = {}
	for k in (res["stats"] as Dictionary).keys():
		var v := float(res["stats"][k])
		if (String(k) in ["max_hp_flat", "dmg_pct", "luck", "move_speed", "regen"]) and v == 0.0:
			continue
		out[k] = v
	var d := UpgradeDB.get_def(id)
	if d.has("amp") and count_of(id) > 0:
		var amp: Dictionary = d["amp"]
		var n := 0
		for oid in counts.keys():
			if oid != id and (amp["tag"] == "*" or (UpgradeDB.get_def(oid).get("tags", []) as Array).has(amp["tag"])):
				n += 1
		_accumulate(out, String(amp["stat"]), float(amp["per"]) * n * count_of(id))
	return out


## Cuántos tipos distintos de la build tienen una etiqueta.
func tag_count(tag: String) -> int:
	var n := 0
	for id in counts.keys():
		if (UpgradeDB.get_def(id).get("tags", []) as Array).has(tag):
			n += 1
	return n


## Progreso de una sinergia: {"active": bool, "parts": [{"label", "ok", "cur", "need"}]}.
func synergy_progress(syn: Dictionary) -> Dictionary:
	var parts: Array = []
	var all_ok := true
	for lk in (syn.get("lv", {}) as Dictionary).keys():
		var cur := count_of(lk)
		var need := int(syn["lv"][lk])
		parts.append({"label": String(UpgradeDB.get_def(lk).get("name", lk)), "ok": cur >= need, "cur": cur, "need": need})
	for tk in (syn.get("tags", {}) as Dictionary).keys():
		var cur2 := tag_count(tk)
		var need2 := int(syn["tags"][tk])
		parts.append({"label": "Mejoras de «%s»" % tk, "ok": cur2 >= need2, "cur": cur2, "need": need2})
	for nk in (syn["needs"] as Dictionary).keys():
		var cur3 := s(nk)
		var need3 := float(syn["needs"][nk])
		parts.append({"label": UpgradeDB.stat_label(String(nk)), "ok": cur3 >= need3, "cur": cur3, "need": need3, "stat": true})
	for pt in parts:
		if not pt["ok"]:
			all_ok = false
	return {"active": all_ok, "parts": parts}


## s(): valor de una estadística (aditiva => 0 por defecto; "_x" => 1.0 por defecto).
func s(key: String) -> float:
	if stats.has(key):
		return float(stats[key])
	return 1.0 if key.ends_with("_x") else 0.0


func has_synergy(id: String) -> bool:
	return active_synergies.has(id)


func recompute(announce: bool) -> void:
	var res := Build.compute(picks, perm, loadout_stats, level)
	stats = res["stats"]
	_derive_perk_lists()
	var newly: Array = []
	for syn in UpgradeDB.synergies():
		if (res["syn"] as Array).has(syn["id"]) and not active_synergies.has(syn["id"]):
			newly.append(syn)
	for syn in newly:
		active_synergies.append(syn["id"])
		if announce:
			synergy_unlocked.emit(syn)
	changed.emit()


## Listas precalculadas para Perks a partir de claves "t:evento:efecto", "c:condición" y "s:fuente".
func _derive_perk_lists() -> void:
	triggers.clear()
	trigger_events.clear()
	conds.clear()
	srcs.clear()
	for k in stats.keys():
		var key := String(k)
		if key.length() < 3 or key[1] != ":":
			continue
		var v := float(stats[k])
		if v == 0.0:
			continue
		if key.begins_with("t:"):
			var parts := key.split(":")
			if parts.size() == 3:
				triggers.append({"event": parts[1], "effect": parts[2], "v": v})
				trigger_events[parts[1]] = true
		elif key.begins_with("c:"):
			conds.append([key.substr(2), v])
		elif key.begins_with("s:"):
			srcs[key.substr(2)] = v


## Cálculo PURO de las estadísticas a partir de las mejoras elegidas (sin estado ni señales).
## Devuelve {"stats": Dictionary, "syn": Array[String]}. Siempre se parte de cero: recalcular dos veces da
## exactamente lo mismo, así que ninguna sinergia ni hito puede aplicarse dos veces.
static func compute(p_picks: Array, p_perm: Dictionary, p_loadout: Dictionary, p_level: int, solo := false) -> Dictionary:
	var st: Dictionary = {}
	var lv: Dictionary = {}
	for p in p_picks:
		var d := UpgradeDB.get_def(p["id"])
		if d.is_empty():
			continue
		lv[p["id"]] = int(lv.get(p["id"], 0)) + 1
		var sc := UpgradeDB.rarity_scale(d, int(p["rarity"]))
		var dstats: Dictionary = d["stats"]
		for k in dstats.keys():
			_accumulate(st, String(k), float(dstats[k]) * sc)
	# hitos: cada MILESTONE_EVERY niveles de una mejora otorgan su bonus (no depende de la rareza)
	for id in lv.keys():
		var d2 := UpgradeDB.get_def(id)
		if not d2.has("mile"):
			continue
		var reached := UpgradeDB.milestones_at(int(lv[id]))
		for k in (d2["mile"] as Dictionary).keys():
			for _i in reached:
				_accumulate(st, String(k), float(d2["mile"][k]))
	# amplificadores por etiquetas: cada mejora de sinergia suma por cada OTRA mejora distinta con esa etiqueta
	for id in lv.keys():
		var d4 := UpgradeDB.get_def(id)
		if not d4.has("amp") or solo:
			continue
		var amp: Dictionary = d4["amp"]
		var n := 0
		for oid in lv.keys():
			if oid != id and (amp["tag"] == "*" or (UpgradeDB.get_def(oid).get("tags", []) as Array).has(amp["tag"])):
				n += 1
		_accumulate(st, String(amp["stat"]), float(amp["per"]) * n * int(lv[id]))
	# equipamiento inicial (mismas reglas: "_x" multiplica, el resto suma)
	for k in p_loadout.keys():
		var lvv := float(p_loadout[k])
		if String(k).ends_with("_x"):
			st[k] = float(st.get(k, 1.0)) * lvv
		else:
			st[k] = float(st.get(k, 0.0)) + lvv
	# meta-progresión
	st["max_hp_flat"] = float(st.get("max_hp_flat", 0.0)) + float(p_perm.get("perm_hp", 0)) * 8.0 + p_level * 3.0
	st["dmg_pct"] = float(st.get("dmg_pct", 0.0)) + float(p_perm.get("perm_dmg", 0)) * 0.04 + p_level * 0.015
	st["luck"] = float(st.get("luck", 0.0)) + float(p_perm.get("perm_luck", 0)) * 0.06
	st["move_speed"] = float(st.get("move_speed", 0.0)) + float(p_perm.get("perm_speed", 0)) * 0.03
	st["regen"] = float(st.get("regen", 0.0)) + float(p_perm.get("perm_regen", 0)) * 0.6
	if solo:
		return {"stats": st, "syn": []}
	# sinergias (cada una como máximo UNA vez)
	var active: Array = []
	for syn in UpgradeDB.synergies():
		var ok := true
		for need_key in (syn["needs"] as Dictionary).keys():
			if float(st.get(need_key, 0.0)) < float(syn["needs"][need_key]):
				ok = false
				break
		if ok:
			for tk in (syn.get("tags", {}) as Dictionary).keys():
				var tn := 0
				for oid2 in lv.keys():
					if (UpgradeDB.get_def(oid2).get("tags", []) as Array).has(tk):
						tn += 1
				if tn < int(syn["tags"][tk]):
					ok = false
					break
		if ok:
			for lk in (syn.get("lv", {}) as Dictionary).keys():
				if int(lv.get(lk, 0)) < int(syn["lv"][lk]):
					ok = false
					break
		if ok:
			for gk in (syn["gives"] as Dictionary).keys():
				_accumulate(st, String(gk), float((syn["gives"] as Dictionary)[gk]))
			active.append(syn["id"])
	# límites duros
	for ck in UpgradeDB.CAPS.keys():
		if st.has(ck):
			st[ck] = minf(float(st[ck]), float(UpgradeDB.CAPS[ck]))
	return {"stats": st, "syn": active}


static func _accumulate(st: Dictionary, k: String, v: float) -> void:
	if k.ends_with("_x"):
		st[k] = float(st.get(k, 1.0)) * (1.0 + v)
	else:
		st[k] = float(st.get(k, 0.0)) + v


## Estimación del multiplicador de daño total (para el indicador de "poder de build").
func power_rating() -> float:
	var r := 1.0 + s("dmg_pct")
	r *= s("more_dmg_x")
	r *= 1.0 + minf(s("crit_chance") + 0.05, 1.0) * (0.75 + s("crit_mult"))
	r *= 1.0 + s("atk_speed")
	r *= 1.0 + s("aoe_pct") * 0.5                 # radio mayor => golpea a más enemigos
	r *= 1.0 + s("echo_wave") * 0.3 + s("boomerang") * 0.3 + s("kill_nova") * 0.15
	r *= 1.0 + s("crit_explosion") * 0.15 * minf(s("crit_chance") + 0.05, 1.0)
	r *= pow(1.0 + case_power(), 0.6)           # rendimientos decrecientes: es una estimación, no daño real
	r *= 1.0 + active_synergies.size() * 0.15
	r *= 1.0 + perk_power()
	return r


## Aporte estimado de las mejoras del maletín lanzado (CaseThrow): cada efecto pesa según cuánto daño añade por impacto.
func case_power() -> float:
	var p := s("bc_dmg") + 0.45 * s("bc_blast") + 0.5 * s("bc_pyro") + 0.10 * s("bc_frag") * (1.0 + s("bc_frag_dmg") * 10.0) + 0.3 * s("bc_docs") + 0.25 * s("bc_fw") + 0.6 * s("bc_rate") + 0.35 * s("bc_ammo")
	p += 0.4 * s("bc_rain") + 0.5 * s("bc_shock") + 0.3 * s("bc_corr") + 0.7 * s("bc_trail") + 0.3 * s("bc_multi") + 0.35 * s("bc_return")
	p += 0.12 * s("bc_pierce") + 0.1 * s("bc_bounce") + 0.5 * s("bc_cases") + 0.35 * s("bc_double") + 0.75 * s("bc_crit") + 0.5 * s("bc_sharp")
	p += 0.25 * s("bc_range") + 0.2 * s("bc_size") + 0.15 * s("bc_speed") + 0.2 * s("bc_wall")
	return p


## Estimación (aproximada, solo para el indicador de la HUD y las simulaciones) del daño extra que aportan las
## condiciones, fuentes y disparadores: condiciones activas ~35% del tiempo, fuentes ~30% del daño, y cada
## disparador de daño aporta (valor × probabilidad). El combate real usa Perks, no esta cifra.
func perk_power() -> float:
	var p := 0.0
	for c in conds:
		p += float(c[1]) * 0.35
	for k in srcs.keys():
		p += float(srcs[k]) * 0.3
	for t in triggers:
		var ch: float = float(Perks.CHANCE.get(t["event"], 0.3))
		match String(t["effect"]):
			"nova", "nova_at", "chain", "boomerang":
				p += float(t["v"]) * ch
			"buff_dmg":
				p += float(t["v"]) * ch * 8.0
			"buff_haste", "buff_crit":
				p += float(t["v"]) * ch * 5.0
			"missile":
				p += float(t["v"]) * ch * 0.35
			"burn_area", "mark_area", "stun_area", "freeze_area", "slow_area":
				p += ch * 0.04
	return p


func summary_lines() -> Array:
	var out: Array = []
	var ids := counts.keys()
	ids.sort()
	for id in ids:
		var d := UpgradeDB.get_def(id)
		out.append("%s — NIVEL %d" % [d.get("name", id), counts[id]])
	return out
