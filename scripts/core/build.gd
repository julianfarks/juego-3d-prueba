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


func add(id: String, rarity: int) -> void:
	picks.append({"id": id, "rarity": rarity})
	counts[id] = count_of(id) + 1
	recompute(true)


## s(): valor de una estadística (aditiva => 0 por defecto; "_x" => 1.0 por defecto).
func s(key: String) -> float:
	if stats.has(key):
		return float(stats[key])
	return 1.0 if key.ends_with("_x") else 0.0


func has_synergy(id: String) -> bool:
	return active_synergies.has(id)


func recompute(announce: bool) -> void:
	var st: Dictionary = {}
	for p in picks:
		var d := UpgradeDB.get_def(p["id"])
		if d.is_empty():
			continue
		var sc := UpgradeDB.rarity_scale(d, int(p["rarity"]))
		var dstats: Dictionary = d["stats"]
		for k in dstats.keys():
			var v := float(dstats[k]) * sc
			if String(k).ends_with("_x"):
				st[k] = float(st.get(k, 1.0)) * (1.0 + v)
			else:
				st[k] = float(st.get(k, 0.0)) + v
	# equipamiento inicial (mismas reglas: "_x" multiplica, el resto suma)
	for k in loadout_stats.keys():
		var lv := float(loadout_stats[k])
		if String(k).ends_with("_x"):
			st[k] = float(st.get(k, 1.0)) * lv
		else:
			st[k] = float(st.get(k, 0.0)) + lv
	# meta-progresión
	st["max_hp_flat"] = float(perm.get("perm_hp", 0)) * 8.0 + level * 3.0
	st["dmg_pct"] = float(st.get("dmg_pct", 0.0)) + float(perm.get("perm_dmg", 0)) * 0.04 + level * 0.015
	st["luck"] = float(st.get("luck", 0.0)) + float(perm.get("perm_luck", 0)) * 0.06
	st["move_speed"] = float(st.get("move_speed", 0.0)) + float(perm.get("perm_speed", 0)) * 0.03
	st["regen"] = float(st.get("regen", 0.0)) + float(perm.get("perm_regen", 0)) * 0.6
	# sinergias
	var newly: Array = []
	for syn in UpgradeDB.synergies():
		var ok := true
		for need_key in (syn["needs"] as Dictionary).keys():
			if float(st.get(need_key, 0.0)) < float(syn["needs"][need_key]):
				ok = false
				break
		if ok:
			for gk in (syn["gives"] as Dictionary).keys():
				var gv := float((syn["gives"] as Dictionary)[gk])
				if String(gk).ends_with("_x"):
					st[gk] = float(st.get(gk, 1.0)) * (1.0 + gv)
				else:
					st[gk] = float(st.get(gk, 0.0)) + gv
			if not active_synergies.has(syn["id"]):
				newly.append(syn)
	# límites duros
	for ck in UpgradeDB.CAPS.keys():
		if st.has(ck):
			st[ck] = minf(float(st[ck]), float(UpgradeDB.CAPS[ck]))
	stats = st
	for syn in newly:
		active_synergies.append(syn["id"])
		if announce:
			synergy_unlocked.emit(syn)
	changed.emit()


## Estimación del multiplicador de daño total (para el indicador de "poder de build").
func power_rating() -> float:
	var r := 1.0 + s("dmg_pct")
	r *= s("more_dmg_x")
	r *= 1.0 + s("crit_chance") * (0.75 + s("crit_mult"))
	r *= 1.0 + s("atk_speed")
	r *= 1.0 + active_synergies.size() * 0.15
	return r


func summary_lines() -> Array:
	var out: Array = []
	var ids := counts.keys()
	ids.sort()
	for id in ids:
		var d := UpgradeDB.get_def(id)
		out.append("%s x%d" % [d.get("name", id), counts[id]])
	return out
