class_name LoadoutDB
extends RefCounted
## Datos del equipamiento inicial y de las dificultades (se eligen en la Sala Central).
##
## Integración (nada se duplica):
##  - El equipamiento aporta estadísticas a Build (mismo sistema que las mejoras de cofre).
##    La herramienta principal además modifica el ataque primario (Skills lee weapon_params()).
##  - Los desbloqueos se guardan en SaveSystem.data["meta"]["unlocks"] y se pagan con los
##    honorarios (la moneda permanente que ya existía). El requisito de progreso usa los
##    récords ya guardados (records.best_arena).
##  - La dificultad la aplica Scaling (vida, daño, cantidad y recompensas de enemigos) y
##    GameState.fees_for_run (honorarios).

const SLOTS := ["weapon", "skill", "tactic", "gear"]
const SLOT_NAMES := {
	"weapon": "Herramienta principal",
	"skill": "Habilidad especial",
	"tactic": "Estilo de combate",
	"gear": "Equipo defensivo / accesorio",
}
const DEFAULT_LOADOUT := {"weapon": "case", "skill": "docs_burst", "tactic": "brawler", "gear": "toga"}

# cost: honorarios (0 = incluido desde el principio). req_arena: mejor arena alcanzada necesaria.
# weapon_params (solo herramienta): cd_x tiempo entre golpes, dmg_x daño, radius_x alcance, arc grados, knock_x empuje.
const ITEMS := {
	"case": {"slot": "weapon", "name": "Maletín Clásico", "desc": "Golpe amplio y equilibrado. El arma de siempre.",
		"cost": 0, "req_arena": 0, "color": Color(0.75, 0.45, 0.2), "stats": {},
		"weapon_params": {"cd_x": 1.0, "dmg_x": 1.0, "radius_x": 1.0, "arc": 150.0, "knock_x": 1.0}},
	"gavel": {"slot": "weapon", "name": "Mazo del Juez", "desc": "Lento y brutal: golpes enormes con gran empuje, pero en un arco corto.",
		"cost": 140, "req_arena": 3, "color": Color(0.55, 0.35, 0.15), "stats": {},
		"weapon_params": {"cd_x": 1.8, "dmg_x": 2.1, "radius_x": 0.85, "arc": 110.0, "knock_x": 1.6}},
	"quill": {"slot": "weapon", "name": "Pluma Estilete", "desc": "Muy rápida y de largo alcance, pero golpea más flojo y en un arco estrecho.",
		"cost": 220, "req_arena": 5, "color": Color(0.9, 0.9, 1.0), "stats": {},
		"weapon_params": {"cd_x": 0.55, "dmg_x": 0.6, "radius_x": 1.25, "arc": 70.0, "knock_x": 0.5}},
	"docs_burst": {"slot": "skill", "name": "Ráfaga de Documentos", "desc": "Tus Documentos Teledirigidos lanzan más páginas.",
		"cost": 0, "req_arena": 0, "color": Color(1.0, 0.85, 0.35), "stats": {"docs_extra": 2.0}},
	"seal_master": {"slot": "skill", "name": "Sello Maestro", "desc": "El Sello Mágico crea una zona extra y todas tus áreas son mayores.",
		"cost": 120, "req_arena": 2, "color": Color(0.8, 0.5, 1.0), "stats": {"seal_extra": 1.0, "aoe_pct": 0.10}},
	"objection_iron": {"slot": "skill", "name": "Objeción Férrea", "desc": "Más escudo máximo y armadura: la Objeción aguanta mucho más.",
		"cost": 160, "req_arena": 4, "color": Color(0.4, 0.7, 1.0), "stats": {"shield_max": 30.0, "armor": 0.08}},
	"brawler": {"slot": "tactic", "name": "Pelea Callejera", "desc": "Un poco más de daño en todo lo que haces.",
		"cost": 0, "req_arena": 0, "color": Color(1.0, 0.45, 0.25), "stats": {"dmg_pct": 0.06}},
	"dancer": {"slot": "tactic", "name": "Esquiva de Tribunal", "desc": "Esquiva más a menudo, te mueves más rápido y atacas con prisa tras esquivar.",
		"cost": 100, "req_arena": 2, "color": Color(0.5, 1.0, 0.7), "stats": {"dodge_cd": 0.2, "dodge_haste": 0.25, "move_speed": 0.05}},
	"precise": {"slot": "tactic", "name": "Alegato Preciso", "desc": "Más probabilidad de crítico y críticos más fuertes.",
		"cost": 180, "req_arena": 4, "color": Color(1.0, 0.35, 0.55), "stats": {"crit_chance": 0.10, "crit_mult": 0.25}},
	"toga": {"slot": "gear", "name": "Toga Reforzada", "desc": "Más salud máxima y algo de regeneración.",
		"cost": 0, "req_arena": 0, "color": Color(0.3, 0.4, 0.8), "stats": {"max_hp_pct": 0.10, "regen": 0.3}},
	"tie": {"slot": "gear", "name": "Corbata de la Suerte", "desc": "Mejores cofres y más monedas por enemigo.",
		"cost": 90, "req_arena": 2, "color": Color(0.9, 0.15, 0.2), "stats": {"luck": 0.15, "coin_pct": 0.15}},
	"watch": {"slot": "gear", "name": "Reloj de Bolsillo", "desc": "Tus habilidades se recargan antes y subes de nivel más rápido.",
		"cost": 200, "req_arena": 5, "color": Color(1.0, 0.8, 0.2), "stats": {"cdr": 0.12, "xp_pct": 0.10}},
}

# Cómo mostrar cada estadística: [texto, tipo]  (n = número entero, p = porcentaje)
const STAT_LABELS := {
	"docs_extra": ["Documentos extra", "n"], "seal_extra": ["Zonas de Sello extra", "n"],
	"aoe_pct": ["Tamaño de áreas", "p"], "shield_max": ["Escudo máximo", "n"], "armor": ["Armadura", "p"],
	"dmg_pct": ["Daño", "p"], "dodge_cd": ["Recarga de esquiva", "pm"], "dodge_haste": ["Velocidad tras esquivar", "p"],
	"move_speed": ["Velocidad de movimiento", "p"], "crit_chance": ["Prob. crítico", "p"], "crit_mult": ["Daño crítico", "p"],
	"max_hp_pct": ["Salud máxima", "p"], "regen": ["Regeneración", "f"], "luck": ["Suerte en cofres", "p"],
	"coin_pct": ["Monedas", "p"], "cdr": ["Recarga de habilidades", "pm"], "xp_pct": ["Experiencia", "p"],
}

const DIFFICULTIES := {
	"intern": {"name": "Pasante", "color": Color(0.5, 0.9, 0.6), "req_arena": 0,
		"desc": "Para aprender. Enemigos con menos vida y daño, y menos numerosos. Menos recompensas.",
		"hp_x": 0.75, "dmg_x": 0.70, "count_x": 0.85, "reward_x": 0.85, "fee_x": 0.6},
	"associate": {"name": "Asociado", "color": Color(0.5, 0.8, 1.0), "req_arena": 0,
		"desc": "La experiencia estándar del bufete.",
		"hp_x": 1.0, "dmg_x": 1.0, "count_x": 1.0, "reward_x": 1.0, "fee_x": 1.0},
	"partner": {"name": "Socio", "color": Color(1.0, 0.7, 0.25), "req_arena": 0,
		"desc": "Enemigos más duros y numerosos. Mejores monedas y honorarios.",
		"hp_x": 1.35, "dmg_x": 1.25, "count_x": 1.2, "reward_x": 1.3, "fee_x": 1.4},
	"prosecutor": {"name": "Fiscal Implacable", "color": Color(1.0, 0.35, 0.35), "req_arena": 6,
		"desc": "Castigo máximo. Para abogados veteranos: vida, daño y cantidad muy altos, con las mejores recompensas.",
		"hp_x": 1.9, "dmg_x": 1.55, "count_x": 1.4, "reward_x": 1.8, "fee_x": 2.2},
}
const DIFF_ORDER := ["intern", "associate", "partner", "prosecutor"]
const DEFAULT_DIFFICULTY := "associate"


# ------------------------------------------------------------------ consultas
static func item(id: String) -> Dictionary:
	return ITEMS.get(id, {})


static func items_for(slot: String) -> Array:
	var out: Array = []
	for id in ITEMS.keys():
		if String(ITEMS[id]["slot"]) == slot:
			out.append(id)
	return out


static func diff(id: String) -> Dictionary:
	return DIFFICULTIES.get(id, DIFFICULTIES[DEFAULT_DIFFICULTY])


static func best_arena() -> int:
	return int(SaveSystem.data["records"]["best_arena"])


static func is_unlocked(id: String) -> bool:
	var d := item(id)
	if d.is_empty():
		return false
	if int(d["cost"]) <= 0:
		return true
	return (SaveSystem.data["meta"]["unlocks"] as Array).has(id)


static func requirement_met(id: String) -> bool:
	var d := item(id)
	return not d.is_empty() and best_arena() >= int(d["req_arena"])


static func can_unlock(id: String) -> bool:
	return not is_unlocked(id) and requirement_met(id) and int(SaveSystem.data["meta"]["fees"]) >= int(item(id)["cost"])


## Compra un objeto con honorarios. Devuelve true si se desbloqueó.
static func unlock(id: String) -> bool:
	if not can_unlock(id):
		return false
	SaveSystem.data["meta"]["fees"] = int(SaveSystem.data["meta"]["fees"]) - int(item(id)["cost"])
	(SaveSystem.data["meta"]["unlocks"] as Array).append(id)
	SaveSystem.mark_dirty()
	SaveSystem.save_now()
	return true


static func diff_unlocked(id: String) -> bool:
	return DIFFICULTIES.has(id) and best_arena() >= int(DIFFICULTIES[id]["req_arena"])


# ------------------------------------------------------------------ selección guardada
static func equipped() -> Dictionary:
	var lo: Dictionary = SaveSystem.data.get("loadout", {})
	return sanitize(lo)


## Devuelve un equipamiento válido: ids existentes, del slot correcto y desbloqueados.
static func sanitize(lo: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for slot in SLOTS:
		var id := String(lo.get(slot, ""))
		var d := item(id)
		if d.is_empty() or String(d["slot"]) != slot or not is_unlocked(id):
			id = String(DEFAULT_LOADOUT[slot])
		out[slot] = id
	return out


static func equip(slot: String, id: String) -> bool:
	var d := item(id)
	if d.is_empty() or String(d["slot"]) != slot or not is_unlocked(id):
		return false
	var lo := equipped()
	lo[slot] = id
	SaveSystem.data["loadout"] = lo
	SaveSystem.mark_dirty()
	return true


static func selected_difficulty() -> String:
	var id := String(SaveSystem.data.get("difficulty", DEFAULT_DIFFICULTY))
	if not DIFFICULTIES.has(id) or not diff_unlocked(id):
		return DEFAULT_DIFFICULTY
	return id


static func select_difficulty(id: String) -> bool:
	if not DIFFICULTIES.has(id) or not diff_unlocked(id):
		return false
	SaveSystem.data["difficulty"] = id
	SaveSystem.mark_dirty()
	return true


## Suma las estadísticas de todo el equipamiento (mismas reglas que Build: "_x" multiplica).
static func total_stats(lo: Dictionary) -> Dictionary:
	var st: Dictionary = {}
	for slot in SLOTS:
		var d := item(String(lo.get(slot, "")))
		if d.is_empty():
			continue
		var s: Dictionary = d["stats"]
		for k in s.keys():
			if String(k).ends_with("_x"):
				st[k] = float(st.get(k, 1.0)) * (1.0 + float(s[k]))
			else:
				st[k] = float(st.get(k, 0.0)) + float(s[k])
	return st


static func weapon_params(lo: Dictionary) -> Dictionary:
	var d := item(String(lo.get("weapon", "case")))
	if d.is_empty() or not d.has("weapon_params"):
		return item("case")["weapon_params"]
	return d["weapon_params"]


static func format_stat(key: String, value: float) -> String:
	var info: Array = STAT_LABELS.get(key, [key, "f"])
	match String(info[1]):
		"n": return "%s +%d" % [info[0], int(round(value))]
		"p": return "%s +%d%%" % [info[0], int(round(value * 100.0))]
		"pm": return "%s −%d%%" % [info[0], int(round(value * 100.0))]
	return "%s +%.1f" % [info[0], value]


## Líneas de estadísticas de un objeto para mostrar al jugador.
static func stat_lines(id: String) -> Array:
	var d := item(id)
	var out: Array = []
	if d.is_empty():
		return out
	if d.has("weapon_params"):
		var w: Dictionary = d["weapon_params"]
		out.append("Daño por golpe ×%.2f" % float(w["dmg_x"]))
		out.append("Velocidad de ataque ×%.2f" % (1.0 / float(w["cd_x"])))
		out.append("Alcance ×%.2f · Arco %d°" % [float(w["radius_x"]), int(w["arc"])])
		out.append("Empuje ×%.2f" % float(w["knock_x"]))
	var s: Dictionary = d["stats"]
	for k in s.keys():
		out.append(format_stat(String(k), float(s[k])))
	return out


static func requirement_text(id: String) -> String:
	var d := item(id)
	if d.is_empty():
		return ""
	var parts: Array = []
	if int(d["req_arena"]) > 0:
		parts.append("Llegar a la arena %d (mejor: %d)" % [int(d["req_arena"]), best_arena()])
	if int(d["cost"]) > 0:
		parts.append("%d honorarios" % int(d["cost"]))
	return " · ".join(parts)
