class_name UpgradeDB
extends RefCounted
## Base de datos de mejoras (cartas), rarezas y sinergias.
##
## Cada mejora modifica CLAVES DE ESTADÍSTICA (ver Build). Esas claves las leen
## de verdad Player, Combat, Skills y Enemy: no hay mejoras "de texto".
## Convención de claves:
##   - sufijo "_x": multiplicador acumulativo (se multiplican entre sí => builds explosivas)
##   - resto: bonificación aditiva
## Los valores por pick se escalan con la rareza: RARITY_MULT (o RARITY_FLAT si flat=true).

const RARITY_NAMES := ["Común", "Rara", "Épica", "Legendaria"]
const RARITY_COLORS := [Color(0.78, 0.8, 0.85), Color(0.3, 0.62, 1.0), Color(0.72, 0.38, 1.0), Color(1.0, 0.7, 0.15)]
const RARITY_MULT := [1.0, 1.6, 2.4, 3.6]
const RARITY_FLAT := [1.0, 1.0, 1.0, 2.0]
const RARITY_WEIGHT := [62.0, 27.0, 9.5, 1.5]

const CATEGORY_NAMES := {
	"dmg": "Daño y Potencia",
	"speed": "Velocidad de Movimiento",
	"atk": "Velocidad de Ataque",
	"crit": "Críticos",
	"hp": "Salud y Recuperación",
	"shield": "Escudos y Supervivencia",
	"aoe": "Efectos de Área",
	"elem": "Elementales",
	"combo": "Combinación de Habilidades",
	"eco": "Economía y Recompensas",
	"streak": "Rachas de Eliminaciones",
	"risk": "Alto Riesgo / Alta Recompensa",
}

const CATEGORY_COLORS := {
	"dmg": Color(1.0, 0.35, 0.3), "speed": Color(0.4, 0.9, 0.7), "atk": Color(1.0, 0.8, 0.3),
	"crit": Color(1.0, 0.55, 0.15), "hp": Color(0.95, 0.35, 0.5), "shield": Color(0.4, 0.7, 1.0),
	"aoe": Color(0.8, 0.5, 1.0), "elem": Color(1.0, 0.5, 0.2), "combo": Color(0.3, 0.9, 1.0),
	"eco": Color(1.0, 0.85, 0.25), "streak": Color(1.0, 0.45, 0.7), "risk": Color(0.85, 0.15, 0.2),
}

## Límites duros de ciertas estadísticas para evitar builds rotas (por encima = inútil).
const CAPS := {
	"crit_chance": 0.85, "armor": 0.6, "block": 0.45, "cdr": 0.6, "atk_speed": 1.6,
	"slow_chance": 0.8, "burn_chance": 0.9, "chain_chance": 0.7, "freeze_chance": 0.3,
	"mark_chance": 0.7, "dodge_cd": 0.6, "move_speed": 1.0, "shop_discount": 0.5,
	"aoe_pct": 1.5, "crit_mult": 6.0, "crit_explosion": 5.0,
}

## Máximo de niveles de cualquier mejora y separación entre hitos (multiplicadores extra por cada 10 niveles).
const MAX_LEVEL := 50
const MILESTONE_EVERY := 10

## Afinidad con el equipamiento de la Sala Central: esas mejoras salen más a menudo.
const EQUIP_AFFINITY := {
	"case": ["heavy_case", "echo_wave", "boomerang_case", "wide_sweep"],
	"gavel": ["heavy_case", "gavel", "wide_sweep", "verdict"],
	"quill": ["espresso", "expert_eye", "static_objection", "lucky_break"],
	"docs_burst": ["paper_storm", "skill_power", "multitask"],
	"seal_master": ["twin_seal", "wide_sweep", "energy_zone"],
	"objection_iron": ["loaded_barrier", "vest", "immunity"],
	"brawler": ["heavy_case", "overtime"],
	"dancer": ["italian_shoes", "rush_hour", "notarial_burst"],
	"precise": ["expert_eye", "gavel", "verdict"],
	"toga": ["health_plan", "legal_nap"],
	"tie": ["appraisal", "retainer"],
	"watch": ["paralegal", "case_xp"],
}


static var _defs: Array = []
static var _by_id: Dictionary = {}


static func _u(id: String, uname: String, cat: String, icon: String, desc: String, stats: Dictionary, fmt: Dictionary, extra: Dictionary = {}) -> void:
	var d := {
		"id": id, "name": uname, "cat": cat, "icon": icon, "desc": desc,
		"stats": stats, "fmt": fmt,
		"max": 6, "flat": false, "rarities": [0, 1, 2, 3],
	}
	for k in extra.keys():
		d[k] = extra[k]
	_defs.append(d)
	_by_id[id] = d


static func _ensure() -> void:
	if not _defs.is_empty():
		return
	# ----------------------------------------------------------------- DAÑO
	_u("heavy_case", "Daño de Maletín", "dmg", "sword", "Daño +{dmg_pct}", {"dmg_pct": 0.16}, {"dmg_pct": "p"}, {"max": 50, "mile": {"more_dmg_x": 0.1}})
	_u("precedent", "Jurisprudencia", "dmg", "book", "+{flat_dmg} de daño plano en cada golpe", {"flat_dmg": 3.0}, {"flat_dmg": "i"}, {"max": 30, "mile": {"flat_dmg": 8.0}})
	_u("closing_arg", "Alegato Final", "dmg", "skull", "+{execute_pct} de daño a enemigos bajo 35% de salud", {"execute_pct": 0.12}, {"execute_pct": "p"}, {"max": 20})
	_u("hostile_witness", "Testigo Hostil", "dmg", "target", "+{boss_dmg} de daño a élites y jefes", {"boss_dmg": 0.1}, {"boss_dmg": "p"}, {"max": 30})
	_u("overtime", "Horas Extra", "dmg", "clock", "Todo tu daño se MULTIPLICA ×{more_dmg_x}", {"more_dmg_x": 0.05}, {"more_dmg_x": "m"}, {"max": 15, "rarities": [1, 2, 3]})
	_u("contingency", "Cobro por Éxito", "dmg", "coin", "+{coin_dmg} de daño por cada 25 monedas (máx. +45%)", {"coin_dmg": 0.03}, {"coin_dmg": "p"}, {"max": 5})
	_u("chain_custody", "Cadena de Custodia", "dmg", "link", "Golpes seguidos: +{combo_dmg} de daño por acumulación (hasta 15)", {"combo_dmg": 0.015}, {"combo_dmg": "p"}, {"max": 15})
	_u("kinetic_law", "Cinética Procesal", "dmg", "bolt", "Tu bonus de velocidad de movimiento aumenta el daño ×{speed_to_dmg}", {"speed_to_dmg": 0.3}, {"speed_to_dmg": "n"}, {"max": 10})
	# ------------------------------------------------------------ VELOCIDAD
	_u("italian_shoes", "Zapatos Italianos", "speed", "shoe", "Velocidad de movimiento +{move_speed}", {"move_speed": 0.04}, {"move_speed": "p"}, {"max": 20})
	_u("rush_hour", "Hora Pico", "speed", "wind", "Enfriamiento de esquiva -{dodge_cd}", {"dodge_cd": 0.05}, {"dodge_cd": "p"}, {"max": 10})
	_u("express", "Trámite Exprés", "speed", "wing", "+{extra_jumps} salto(s) en el aire", {"extra_jumps": 1.0}, {"extra_jumps": "i"}, {"max": 2, "flat": true})
	_u("slide_clause", "Cláusula de Deslizamiento", "speed", "trail", "Tu esquiva deja una estela que daña ({dodge_trail} de daño)", {"dodge_trail": 14.0}, {"dodge_trail": "i"}, {"max": 10})
	# -------------------------------------------------------- VELOCIDAD ATAQUE
	_u("espresso", "Café Expreso", "atk", "cup", "Velocidad de ataque +{atk_speed}", {"atk_speed": 0.04}, {"atk_speed": "p"}, {"max": 30})
	_u("paralegal", "Pasante Eficiente", "atk", "gear", "Enfriamiento de habilidades -{cdr}", {"cdr": 0.03}, {"cdr": "p"}, {"max": 15})
	_u("notarial_burst", "Ráfaga Notarial", "atk", "fast", "Tras esquivar: +{dodge_haste} vel. de ataque durante 2.5 s", {"dodge_haste": 0.2}, {"dodge_haste": "p"}, {"max": 8})
	_u("multitask", "Multitarea", "atk", "layers", "Cada habilidad secundaria: +{skill_haste} vel. de ataque 3 s", {"skill_haste": 0.1}, {"skill_haste": "p"}, {"max": 10})
	# ------------------------------------------------------------- CRÍTICOS
	_u("expert_eye", "Ojo de Perito", "crit", "eye", "Prob. de crítico +{crit_chance}", {"crit_chance": 0.025}, {"crit_chance": "p"}, {"max": 30, "mile": {"crit_mult": 0.25}})
	_u("gavel", "Mazo del Juez", "crit", "gavel", "Daño crítico +{crit_mult}", {"crit_mult": 0.1}, {"crit_mult": "p"}, {"max": 30, "mile": {"more_dmg_x": 0.1}})
	_u("verdict", "Veredicto", "crit", "burst", "Los críticos explotan (+{crit_explosion} del daño en área)", {"crit_explosion": 0.12}, {"crit_explosion": "p"}, {"max": 15, "mile": {"crit_explosion": 0.2}})
	_u("lucky_break", "Golpe de Suerte", "crit", "clover", "Cada crítico reduce {crit_cdr} s los enfriamientos", {"crit_cdr": 0.04}, {"crit_cdr": "s"}, {"max": 10})
	# ---------------------------------------------------------------- SALUD
	_u("health_plan", "Seguro Médico", "hp", "heart", "Salud máxima +{max_hp_pct}", {"max_hp_pct": 0.06}, {"max_hp_pct": "p"}, {"max": 30, "mile": {"max_hp_pct": 0.1}})
	_u("legal_nap", "Siesta Legal", "hp", "zzz", "Regeneración +{regen} salud/s", {"regen": 0.8}, {"regen": "n"}, {"max": 15})
	_u("settlement", "Acuerdo Extrajudicial", "hp", "handshake", "Cada baja cura {kill_heal} de salud (máx. 14/s)", {"kill_heal": 1.0}, {"kill_heal": "n"}, {"max": 10})
	_u("second_opinion", "Segunda Opinión", "hp", "cross", "Reaparece al morir con 40% de salud ({revives} vez)", {"revives": 1.0}, {"revives": "i"}, {"max": 2, "flat": true, "rarities": [2, 3]})
	# -------------------------------------------------------------- ESCUDOS
	_u("vest", "Chaleco Antibalas", "shield", "vest", "Escudo regenerable +{shield_max}", {"shield_max": 12.0}, {"shield_max": "i"}, {"max": 25})
	_u("immunity", "Inmunidad Diplomática", "shield", "badge", "Reducción de daño +{armor}", {"armor": 0.018}, {"armor": "p"}, {"max": 30})
	_u("fine_print", "Letra Pequeña", "shield", "doc", "{block} de anular un golpe recibido", {"block": 0.03}, {"block": "p"}, {"max": 12})
	_u("retaliation", "Cláusula de Represalia", "shield", "thorn", "Al recibir daño devuelves {thorns} en onda", {"thorns": 10.0}, {"thorns": "i"}, {"max": 20})
	# ---------------------------------------------------------------- ÁREA
	_u("wide_sweep", "Barrido Amplio", "aoe", "ring", "Radio de todas tus áreas +{aoe_pct}", {"aoe_pct": 0.03}, {"aoe_pct": "p"}, {"max": 30, "mile": {"more_dmg_x": 0.1}})
	_u("class_action", "Demanda Colectiva", "aoe", "crowd", "+{crowd_dmg} de daño por cada enemigo extra alcanzado (máx. 40%)", {"crowd_dmg": 0.02}, {"crowd_dmg": "p"}, {"max": 15})
	_u("echo_wave", "Onda Residual", "aoe", "echo", "Cada golpe de maletín genera una onda secundaria ({echo_wave} del daño)", {"echo_wave": 0.12}, {"echo_wave": "p"}, {"max": 20, "mile": {"echo_wave": 0.2}})
	# ------------------------------------------------------------ ELEMENTAL
	_u("hot_ink", "Tinta Hirviente", "elem", "flame", "{burn_chance} de incendiar ({burn_dps} daño/s)", {"burn_chance": 0.06, "burn_dps": 5.0}, {"burn_chance": "p", "burn_dps": "i"}, {"max": 20, "mile": {"burn_dps": 6.0}})
	_u("frozen_assets", "Activos Congelados", "elem", "snow", "{slow_chance} de ralentizar un 45% (y {freeze_chance} de congelar)", {"slow_chance": 0.08, "freeze_chance": 0.006}, {"slow_chance": "p", "freeze_chance": "p"}, {"max": 15})
	_u("static_objection", "Objeción Estática", "elem", "zap", "{chain_chance} de rayo en cadena (+{chain_count} saltos)", {"chain_chance": 0.06, "chain_count": 0.5}, {"chain_chance": "p", "chain_count": "n"}, {"max": 15})
	_u("corrosive", "Cláusula Corrosiva", "elem", "drop", "{mark_chance} de marcar: el objetivo recibe +25% de daño", {"mark_chance": 0.07}, {"mark_chance": "p"}, {"max": 12})
	# ---------------------------------------------------------- COMBINACIONES
	_u("paper_storm", "Tormenta de Papel", "combo", "paper", "Documentos teledirigidos: +{docs_extra} documento(s)", {"docs_extra": 1.0}, {"docs_extra": "i"}, {"max": 12, "flat": true, "mile": {"docs_extra": 2.0}})
	_u("twin_seal", "Sello Gemelo", "combo", "seal", "Sello Mágico: +{seal_extra} sello(s) adicional(es)", {"seal_extra": 1.0}, {"seal_extra": "i"}, {"max": 4, "flat": true})
	_u("loaded_barrier", "Barrera Cargada", "combo", "barrier", "Al romperse o expirar, la Objeción estalla ({barrier_blast} del daño absorbido)", {"barrier_blast": 0.6}, {"barrier_blast": "p"}, {"max": 10})
	_u("boomerang_case", "Maletín Bumerán", "combo", "boomerang", "Tu golpe lanza un maletín bumerán ({boomerang} del daño, ida y vuelta)", {"boomerang": 0.35}, {"boomerang": "p"}, {"max": 15, "mile": {"boomerang": 0.4}})
	_u("energy_zone", "Zona Contenciosa", "combo", "zone", "Tus habilidades dejan zonas de energía ({energy_zone} del daño por segundo, ralentizan)", {"energy_zone": 0.2}, {"energy_zone": "p"}, {"max": 12})
	_u("skill_power", "Pericia Procesal", "combo", "gear", "Daño de habilidades (documentos, sello…) ×{skill_dmg_x}", {"skill_dmg_x": 0.06}, {"skill_dmg_x": "m"}, {"max": 25, "mile": {"skill_dmg_x": 0.12}})
	# ------------------------------------------------------------- ECONOMÍA
	_u("retainer", "Anticipo", "eco", "coin", "Monedas ganadas +{coin_pct}", {"coin_pct": 0.12}, {"coin_pct": "p"}, {"max": 15})
	_u("billable", "Horas Facturables", "eco", "clock", "Generas {passive_coins} moneda(s) por segundo en combate", {"passive_coins": 0.15}, {"passive_coins": "n"}, {"max": 10})
	_u("appraisal", "Tasación", "eco", "gem", "Mejor suerte en cofres +{luck} y descuento en tienda {shop_discount}", {"luck": 0.06, "shop_discount": 0.02}, {"luck": "p", "shop_discount": "p"}, {"max": 12})
	_u("case_xp", "Casos Ganados", "eco", "star", "Experiencia ganada +{xp_pct}", {"xp_pct": 0.15}, {"xp_pct": "p"}, {"max": 10})
	# --------------------------------------------------------------- RACHAS
	_u("closing_nova", "Descarga de Cierre", "streak", "nova", "Cada baja genera una descarga ({kill_nova} del daño) a enemigos cercanos", {"kill_nova": 0.3}, {"kill_nova": "p"}, {"max": 15, "mile": {"kill_nova": 0.3}})
	_u("streak_fury", "Furia de Racha", "streak", "fire2", "Por baja en racha (4 s): +{streak_dmg} de daño (hasta 10 bajas)", {"streak_dmg": 0.02}, {"streak_dmg": "p"}, {"max": 15})
	_u("bloodlust", "Sed de Cobro", "streak", "wind", "Cada baja: +{kill_speed} velocidad de movimiento 2 s", {"kill_speed": 0.1}, {"kill_speed": "p"}, {"max": 8})
	_u("last_word", "La Última Palabra", "streak", "mega", "Cada 10.ª baja desata una explosión enorme ({nth_kill_nova} del daño)", {"nth_kill_nova": 1.5}, {"nth_kill_nova": "p"}, {"max": 10, "rarities": [1, 2, 3]})
	_u("bail_refund", "Fianza Reembolsable", "streak", "battery", "Cada baja restaura {kill_energy} de Expediente (máx. 25/s)", {"kill_energy": 1.0}, {"kill_energy": "n"}, {"max": 10})
	# ----------------------------------------------------------- ALTO RIESGO
	_u("glass_cannon", "Cañón de Cristal", "risk", "glass", "Daño +{dmg_pct} pero salud máxima -{hp_malus}", {"dmg_pct": 0.5, "max_hp_pct": -0.22}, {"dmg_pct": "p", "max_hp_pct": "pm"}, {"max": 3, "rarities": [2, 3]})
	_u("high_stakes", "Apuesta Máxima", "risk", "dice", "Monedas y experiencia +{coin_pct}, pero recibes +{dmg_taken} de daño", {"coin_pct": 0.6, "xp_pct": 0.6, "dmg_taken": 0.2}, {"coin_pct": "p", "xp_pct": "p", "dmg_taken": "p"}, {"max": 3, "rarities": [1, 2, 3]})
	_u("all_in", "Todo o Nada", "risk", "spade", "Prob. de crítico +{crit_chance}, pero tus golpes no críticos hacen -{noncrit_malus}", {"crit_chance": 0.2, "noncrit_malus": 0.25}, {"crit_chance": "p", "noncrit_malus": "p"}, {"max": 3, "rarities": [1, 2, 3]})
	_u("blood_pact", "Conflicto de Intereses", "risk", "pact", "Tus habilidades secundarias cuestan {skill_hp_cost} de salud pero hacen ×{skill_dmg_x}", {"skill_hp_cost": 3.0, "skill_dmg_x": 0.45}, {"skill_hp_cost": "i", "skill_dmg_x": "m"}, {"max": 3, "rarities": [1, 2, 3]})
	_u("hostile_takeover", "Adquisición Hostil", "risk", "crown", "Cada 12 s tu próximo golpe es una MEGA onda ({takeover} del daño)", {"takeover": 6.0}, {"takeover": "p"}, {"max": 3, "rarities": [3]})


# ---------------------------------------------------------------- SINERGIAS
## Se activan solas cuando se cumplen todas las condiciones (stat > umbral).
## "gives" añade estadísticas a la build; los códigos syn_* los leen Combat/Skills.
static var _syn_cache: Array = []


static func synergies() -> Array:
	if not _syn_cache.is_empty():
		return _syn_cache
	_syn_cache = [
		{"id": "perfect_storm", "name": "Tormenta Perfecta", "desc": "Documentos + Veredicto: los críticos de documentos explotan el doble.", "needs": {"docs_extra": 0.5, "crit_explosion": 0.01}, "gives": {"syn_docs_crit": 1.0}},
		{"id": "inferno", "name": "Inferno Legal", "desc": "Tinta Hirviente + Descarga de Cierre: las descargas prenden a todos.", "needs": {"burn_chance": 0.01, "kill_nova": 0.01}, "gives": {"syn_nova_burn": 1.0}},
		{"id": "deep_freeze", "name": "Congelación Total", "desc": "Activos Congelados + Zona Contenciosa: las zonas congelan y +25% de daño a ralentizados.", "needs": {"slow_chance": 0.01, "energy_zone": 0.01}, "gives": {"syn_cold_zone": 1.0}},
		{"id": "thunder", "name": "Tormenta Eléctrica", "desc": "Objeción Estática + Onda Residual: las ondas secundarias lanzan rayos.", "needs": {"chain_chance": 0.01, "echo_wave": 0.01}, "gives": {"syn_echo_chain": 1.0}},
		{"id": "war_machine", "name": "Máquina de Guerra", "desc": "Furia de Racha + Velocidad de ataque: ×1.3 de daño mientras mantienes racha.", "needs": {"streak_dmg": 0.01, "atk_speed": 0.2}, "gives": {"syn_war": 1.0}},
		{"id": "sprinter", "name": "Velocista Letal", "desc": "Cinética Procesal + Zapatos: ×1.25 de daño total.", "needs": {"speed_to_dmg": 0.01, "move_speed": 0.2}, "gives": {"more_dmg_x": 0.25}},
		{"id": "execution", "name": "Ejecución Perfecta", "desc": "Alegato Final + Críticos: los críticos ejecutan a enemigos bajo 15%.", "needs": {"execute_pct": 0.01, "crit_chance": 0.25}, "gives": {"syn_execute": 1.0}},
		{"id": "volatile_shield", "name": "Escudo Explosivo", "desc": "Chaleco + Represalia: al romperse tu escudo estalla con tu daño de Represalia ×5.", "needs": {"shield_max": 1.0, "thorns": 1.0}, "gives": {"syn_shield_blast": 1.0}},
		{"id": "death_mark", "name": "Marca Mortal", "desc": "Cláusula Corrosiva + Rayo: las cadenas saltan +2 veces y marcan.", "needs": {"mark_chance": 0.01, "chain_chance": 0.01}, "gives": {"chain_count": 2.0, "syn_chain_mark": 1.0}},
		# --- sinergias por NIVEL de mejora ("lv": id -> nivel mínimo). Dan multiplicadores (_x) y se aplican una sola vez.
		{"id": "case_master", "name": "Maestro del Maletín", "desc": "Maletín 10 + Barrido 5: ×1.25 de daño y +10% de radio.", "needs": {}, "lv": {"heavy_case": 10, "wide_sweep": 5}, "gives": {"more_dmg_x": 0.25, "aoe_pct": 0.10}},
		{"id": "total_artillery", "name": "Artillería Total", "desc": "Maletín 20 + Barrido 15 + Café 10: ×1.5 de daño y los críticos explotan.", "needs": {}, "lv": {"heavy_case": 20, "wide_sweep": 15, "espresso": 10}, "gives": {"more_dmg_x": 0.5, "crit_explosion": 0.5}},
		{"id": "crit_crusher", "name": "Aplastamiento Crítico", "desc": "Ojo 15 + Mazo 10: ×1.35 de daño y explosiones críticas.", "needs": {}, "lv": {"expert_eye": 15, "gavel": 10}, "gives": {"more_dmg_x": 0.35, "crit_explosion": 0.4}},
		{"id": "living_library", "name": "Biblioteca Viviente", "desc": "Tormenta 8 + Pericia 8: +3 documentos y ×1.3 de daño de habilidades.", "needs": {}, "lv": {"paper_storm": 8, "skill_power": 8}, "gives": {"docs_extra": 3.0, "skill_dmg_x": 0.3}},
		{"id": "relentless", "name": "Ritmo Imparable", "desc": "Café 12 + Pasante 8: ×1.3 de daño.", "needs": {}, "lv": {"espresso": 12, "paralegal": 8}, "gives": {"more_dmg_x": 0.3}},
		{"id": "chain_of_command", "name": "Cadena de Mando", "desc": "Rayo 6 + Onda 6 + Tinta 6: +2 saltos de rayo y +20% de incendiar.", "needs": {}, "lv": {"static_objection": 6, "echo_wave": 6, "hot_ink": 6}, "gives": {"chain_count": 2.0, "burn_chance": 0.2}},
		{"id": "iron_wall", "name": "Muro de Jurisprudencia", "desc": "Inmunidad 10 + Chaleco 8 + Seguro 10: +8% de reducción, +50 de escudo y +4 de regeneración.", "needs": {}, "lv": {"immunity": 10, "vest": 8, "health_plan": 10}, "gives": {"armor": 0.08, "shield_max": 50.0, "regen": 4.0}},
		{"id": "heavy_artillery", "name": "Artillería Pesada", "desc": "Maletín Bumerán + Barrido Amplio: el bumerán es gigante y ×1.4 de daño.", "needs": {"boomerang": 0.01, "aoe_pct": 0.2}, "gives": {"syn_big_boomerang": 1.0}},
	]
	return _syn_cache


# ------------------------------------------------------------------- API
static func all() -> Array:
	_ensure()
	return _defs


static func get_def(id: String) -> Dictionary:
	_ensure()
	return _by_id.get(id, {})


static func rarity_scale(def: Dictionary, rarity: int) -> float:
	if def.get("flat", false):
		return RARITY_FLAT[rarity]
	return RARITY_MULT[rarity]


## Texto de la carta con los valores concretos según la rareza.
static func describe(id: String, rarity: int) -> String:
	var d := get_def(id)
	if d.is_empty():
		return ""
	var txt: String = d["desc"]
	var sc := rarity_scale(d, rarity)
	var stats: Dictionary = d["stats"]
	var fmt: Dictionary = d["fmt"]
	for key in fmt.keys():
		var v := float(stats.get(key, 0.0)) * sc
		var out := ""
		match String(fmt[key]):
			"p": out = "%d%%" % int(round(v * 100.0))
			"pm": out = "%d%%" % int(round(absf(v) * 100.0))
			"m": out = "%.2f" % (1.0 + v)
			"i": out = "%d" % int(round(v))
			"s": out = "%.2f" % v
			_: out = "%.1f" % v
		txt = txt.replace("{%s}" % key, out)
	# marcadores auxiliares
	txt = txt.replace("{hp_malus}", "%d%%" % int(round(absf(float(stats.get("max_hp_pct", 0.0))) * sc * 100.0)))
	txt = txt.replace("{noncrit_malus}", "%d%%" % int(round(float(stats.get("noncrit_malus", 0.0)) * sc * 100.0)))
	return txt


static func effect_summary(id: String) -> String:
	var d := get_def(id)
	return String(UpgradeDB.CATEGORY_NAMES.get(d.get("cat", ""), ""))


## Nivel (veces elegida) actual de una mejora en la build.
static func level_of(build: Build, id: String) -> int:
	return 0 if build == null else build.count_of(id)


## Hitos alcanzados (multiplicadores extra cada MILESTONE_EVERY niveles).
static func milestones_at(level: int) -> int:
	return level / MILESTONE_EVERY


## ¿Sigue aportando algo? Falso si ya está al nivel máximo o su estadística principal ya tocó su límite duro.
static func is_offerable(d: Dictionary, build: Build) -> bool:
	if build == null:
		return true
	if build.count_of(d["id"]) >= mini(int(d["max"]), MAX_LEVEL):
		return false
	var first_key := String((d["stats"] as Dictionary).keys()[0])
	if CAPS.has(first_key) and float((d["stats"] as Dictionary)[first_key]) > 0.0 and build.s(first_key) >= float(CAPS[first_key]) - 0.0005:
		return false
	return true


## Nombre de la sinergia inactiva que esta mejora ayudaría a completar (si ya llevas alguna otra pieza).
static func synergy_hint(id: String, build: Build) -> String:
	var d := get_def(id)
	for s in synergies():
		if build != null and build.active_synergies.has(s["id"]):
			continue
		var lv: Dictionary = s.get("lv", {})
		var needs: Dictionary = s["needs"]
		var mine := lv.has(id)
		for key in needs.keys():
			if (d["stats"] as Dictionary).has(key):
				mine = true
		if not mine:
			continue
		var others := 0
		for k2 in lv.keys():
			if k2 != id and build != null and build.count_of(k2) > 0:
				others += 1
		for key in needs.keys():
			if not (d["stats"] as Dictionary).has(key) and build != null and build.s(key) > 0.0:
				others += 1
		if others > 0 or (lv.size() + needs.size()) == 1 or build == null:
			return String(s["name"])
	return ""


static func _pick_weight(d: Dictionary, build: Build, equipped: Array) -> float:
	var w := 1.0
	var id: String = d["id"]
	if build != null and build.count_of(id) > 0:
		w *= 1.6        # profundizar una build ya empezada tiene que ser tentador
	for item in equipped:
		if (EQUIP_AFFINITY.get(item, []) as Array).has(id):
			w *= 2.2
			break
	if build != null and synergy_hint(id, build) != "":
		w *= 1.5
	return w


## Genera 'count' cartas distintas. 'luck' >=0, 'depth' = índice de arena,
## 'min_rarity' garantiza al menos una carta de esa rareza o mayor (cofres de jefe).
## Excluye: mejoras en su nivel máximo (50 como mucho), con la estadística principal ya en su límite duro,
## y duplicados dentro del mismo cofre. Pondera según el equipamiento y la build.
static func roll_cards(count: int, luck: float, depth: int, build: Build, rng: RandomNumberGenerator, min_rarity := 0) -> Array:
	_ensure()
	var cards: Array = []
	var used := {}
	var equipped: Array = []
	if GameState != null and GameState.loadout is Dictionary:
		for slot in (GameState.loadout as Dictionary).keys():
			equipped.append(String(GameState.loadout[slot]))
	for i in count:
		var force_min := min_rarity if i == 0 else 0
		var rarity := _roll_rarity(luck, depth, rng, force_min)
		var pool: Array = []
		for d in _defs:
			if used.has(d["id"]) or not is_offerable(d, build):
				continue
			pool.append(d)
		if pool.is_empty():
			break
		var allowed: Array = []
		for d in pool:
			if (d["rarities"] as Array).has(rarity):
				allowed.append(d)
		if allowed.is_empty():
			var pick0: Dictionary = pool[rng.randi() % pool.size()]
			var rs: Array = pick0["rarities"]
			rarity = rs[rs.size() - 1] if rarity > rs[rs.size() - 1] else rs[0]
			allowed = [pick0]
		# casilla de continuidad: la 2.ª carta de cada cofre sale de las mejoras que ya llevas (si hay), para que
		# una build enfocada pueda seguir subiendo de nivel hasta el 50 en vez de depender de la suerte
		if i == 1 and build != null and build.picks.size() >= 3:
			var owned: Array = []
			for d in allowed:
				if build.count_of(d["id"]) > 0:
					owned.append(d)
			if not owned.is_empty():
				allowed = owned
		var total := 0.0
		var ws: Array = []
		for d in allowed:
			var w := _pick_weight(d, build, equipped)
			ws.append(w)
			total += w
		var r := rng.randf() * total
		var chosen: Dictionary = allowed[allowed.size() - 1]
		for k in allowed.size():
			r -= float(ws[k])
			if r <= 0.0:
				chosen = allowed[k]
				break
		used[chosen["id"]] = true
		cards.append({"id": chosen["id"], "rarity": rarity})
	return cards


## Qué cambia al elegir la carta: líneas "Etiqueta: antes → después" con la build real.
static func preview_lines(id: String, rarity: int, build: Build) -> Array:
	var d := get_def(id)
	var out: Array = []
	if d.is_empty() or build == null:
		return out
	var before := build.stats
	var after: Dictionary = Build.compute(_with_pick(build.picks, id, rarity), build.perm, build.loadout_stats, build.level)["stats"]
	for key in (d["stats"] as Dictionary).keys():
		var b0 := float(before.get(key, 1.0 if String(key).ends_with("_x") else 0.0))
		var a0 := float(after.get(key, 1.0 if String(key).ends_with("_x") else 0.0))
		var f := String((d["fmt"] as Dictionary).get(key, "n"))
		out.append("%s → %s" % [_fmt_stat(key, b0, f), _fmt_stat(key, a0, f)])
	var lvl := build.count_of(id)
	var next_mile := (lvl / MILESTONE_EVERY + 1) * MILESTONE_EVERY
	if d.has("mile") and next_mile <= int(d["max"]) and lvl + 1 == next_mile:
		out.append("¡HITO nivel %d! %s" % [next_mile, mile_text(d)])
	return out


static func _with_pick(picks: Array, id: String, rarity: int) -> Array:
	var np := picks.duplicate()
	np.append({"id": id, "rarity": rarity})
	return np


static func _fmt_stat(key: String, v: float, f: String) -> String:
	var label := String(STAT_LABELS.get(key, key))
	match f:
		"p", "pm": return "%s %d%%" % [label, int(round(v * 100.0))]
		"m": return "%s ×%.2f" % [label, v]
		"i": return "%s %d" % [label, int(round(v))]
		_: return "%s %.1f" % [label, v]


const STAT_LABELS := {
	"dmg_pct": "Daño", "flat_dmg": "Daño plano", "execute_pct": "Ejecución", "boss_dmg": "Daño a jefes", "more_dmg_x": "Daño total",
	"coin_dmg": "Daño/monedas", "combo_dmg": "Daño/combo", "speed_to_dmg": "Cinética", "move_speed": "Velocidad", "dodge_cd": "Enfr. esquiva",
	"dodge_trail": "Estela", "extra_jumps": "Saltos", "atk_speed": "Vel. ataque", "cdr": "Enfriamiento", "dodge_haste": "Prisa esquiva",
	"skill_haste": "Prisa habilidad", "crit_chance": "Crítico", "crit_mult": "Daño crítico", "crit_explosion": "Explosión crítica",
	"crit_cdr": "Rec. crítico", "max_hp_pct": "Salud máx.", "regen": "Regen.", "kill_heal": "Cura/baja", "revives": "Revives", "shield_max": "Escudo",
	"armor": "Armadura", "block": "Bloqueo", "thorns": "Represalia", "aoe_pct": "Radio", "crowd_dmg": "Multitud", "echo_wave": "Onda",
	"burn_chance": "Incendiar", "burn_dps": "Fuego/s", "slow_chance": "Ralentizar", "freeze_chance": "Congelar", "chain_chance": "Rayo",
	"chain_count": "Saltos", "mark_chance": "Marcar", "docs_extra": "Documentos", "seal_extra": "Sellos", "barrier_blast": "Estallido",
	"boomerang": "Bumerán", "energy_zone": "Zona", "coin_pct": "Monedas", "passive_coins": "Monedas/s", "luck": "Suerte", "shop_discount": "Descuento",
	"xp_pct": "Experiencia", "kill_nova": "Descarga", "streak_dmg": "Racha", "kill_speed": "Prisa/baja", "nth_kill_nova": "Explosión 10.ª",
	"kill_energy": "Energía/baja", "skill_dmg_x": "Habilidades",
}


static func mile_text(d: Dictionary) -> String:
	var parts: Array = []
	for key in (d["mile"] as Dictionary).keys():
		var v := float(d["mile"][key])
		var label := String(STAT_LABELS.get(key, key))
		if String(key).ends_with("_x"):
			parts.append("%s ×%.2f" % [label, 1.0 + v])
		elif v < 5.0:
			parts.append("%s +%d%%" % [label, int(round(v * 100.0))])
		else:
			parts.append("%s +%d" % [label, int(round(v))])
	return ", ".join(parts)


static func _roll_rarity(luck: float, depth: int, rng: RandomNumberGenerator, min_rarity: int) -> int:
	var w := RARITY_WEIGHT.duplicate()
	w[1] *= 1.0 + luck * 1.0 + depth * 0.02
	w[2] *= 1.0 + luck * 2.0 + depth * 0.05
	w[3] *= 1.0 + luck * 3.0 + depth * 0.08
	for i in min_rarity:
		w[i] = 0.0
	var total := 0.0
	for x in w:
		total += x
	var r := rng.randf() * total
	for i in w.size():
		r -= w[i]
		if r <= 0.0:
			return i
	return w.size() - 1
