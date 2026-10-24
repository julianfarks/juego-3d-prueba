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
	"case": "Maletín: Golpes y Ataques",
	"docs": "Documentos y Proyectiles",
	"ctrl": "Habilidades y Control",
	"syn": "Sinergias entre Mejoras",
	"legend": "Especiales y Legendarias",
}

const CATEGORY_COLORS := {
	"dmg": Color(1.0, 0.35, 0.3), "speed": Color(0.4, 0.9, 0.7), "atk": Color(1.0, 0.8, 0.3),
	"crit": Color(1.0, 0.55, 0.15), "hp": Color(0.95, 0.35, 0.5), "shield": Color(0.4, 0.7, 1.0),
	"aoe": Color(0.8, 0.5, 1.0), "elem": Color(1.0, 0.5, 0.2), "combo": Color(0.3, 0.9, 1.0),
	"eco": Color(1.0, 0.85, 0.25), "streak": Color(1.0, 0.45, 0.7), "risk": Color(0.85, 0.15, 0.2),
	"case": Color(1.0, 0.6, 0.35), "docs": Color(0.95, 0.95, 0.7), "ctrl": Color(0.55, 0.65, 1.0),
	"syn": Color(0.4, 1.0, 0.8), "legend": Color(1.0, 0.75, 0.2),
}

## Límites duros de ciertas estadísticas para evitar builds rotas (por encima = inútil).
const CAPS := {
	"crit_chance": 0.85, "armor": 0.6, "block": 0.45, "cdr": 0.6, "atk_speed": 1.6,
	"slow_chance": 0.8, "burn_chance": 0.9, "chain_chance": 0.7, "freeze_chance": 0.3,
	"mark_chance": 0.7, "dodge_cd": 0.6, "move_speed": 1.0, "shop_discount": 0.5,
	"aoe_pct": 1.5, "bc_sec_range": 1.2, "bc_xtra": 0.9, "bc_both": 1.0, "bc_split": 0.9, "bc_seek": 1.2, "bc_knife_n": 4.0, "bc_missile_n": 4.0, "bc_ray_n": 4.0, "bc_sec_pierce": 4.0, "bc_blast_n": 3.0, "bc_chase": 1.0, "law_leech": 0.03, "law_mshield": 0.4, "law_tenure": 0.2, "law_momentum": 0.2, "law_caseload": 0.06, "law_bill": 6.0, "law_season": 0.06, "bc_rate": 1.2, "bc_ret": 2.0, "bc_ammo": 4.0, "bc_fw": 4.0, "bc_loot": 5.0, "crit_mult": 6.0, "crit_explosion": 5.0,
	"hp_regen_pct": 0.05, "heal_pow": 1.5, "armor_low": 0.3, "iframe_add": 0.4, "dodge_speed": 1.0, "hurt_iframe_add": 0.4,
	"shield_regen_pct": 3.0, "shield_delay_cut": 0.6, "jump_pow": 0.6, "lifesteal": 0.12, "cd_docs": 0.6, "cd_seal": 0.6,
	"cd_barrier": 0.6, "cd_slam": 0.5, "docs_pierce": 6.0, "docs_speed": 1.5, "docs_turn": 12.0, "cost_cut": 0.5,
	"slam_double": 0.6, "burn_spread": 0.8, "slow_amt": 0.35, "reroll_cut": 0.6, "exec_thr": 0.24, "slam_arc": 200.0, "kill_coins": 0.5,
	"explosion_pow": 3.0, "explo_rad": 1.2, "slam_radius": 1.0, "seal_radius": 1.5, "knock_pow": 3.0,
	# maletín lanzado (CaseThrow): probabilidades al 100 % y el resto acotado para que ninguna cadena rompa el rendimiento
	"bc_dmg": 5.0, "bc_range": 1.0, "bc_size": 0.8, "bc_speed": 1.0, "bc_homing": 0.95, "bc_sharp": 1.0, "bc_crit": 0.6,
	"bc_blast": 3.0, "bc_blast_r": 1.5, "bc_pyro": 1.0, "bc_pyro_n": 4.0, "bc_frag": 10.0, "bc_frag_dmg": 0.6, "bc_docs": 8.0,
	"bc_rain": 1.0, "bc_rain_n": 6.0, "bc_shock": 1.0, "bc_shock_n": 6.0, "bc_corr": 1.0, "bc_spread": 12.0, "bc_trail": 2.0,
	"bc_multi": 3.0, "bc_return": 4.2, "bc_return_r": 1.5, "bc_catch": 0.8, "bc_pierce": 8.0, "bc_bounce": 8.0, "bc_wall": 6.0,
	"bc_cases": 5.0, "bc_double": 4.0,
	# ampliación judicial (LawCatalog): todo con tope duro
	"law_demo": 2.0, "law_ret": 1.5, "law_pierce": 6.0, "law_dbl": 0.4, "law_sent": 0.4, "law_obj": 0.08, "law_gavel": 4.8, "law_papers": 8.0,
	"law_final": 1.2, "law_def": 0.35, "law_dodge": 0.9, "law_block": 0.3, "law_medic": 0.06, "law_immun": 90.0,
	"law_fee_win": 0.6, "law_vip": 1.0, "law_adv": 60.0, "law_firm": 0.15, "law_eff": 120.0,
}

## Máximo de niveles de cualquier mejora y separación entre hitos (multiplicadores extra por cada 10 niveles).
const MAX_LEVEL := 50
const MILESTONE_EVERY := 10

## Afinidad con el equipamiento de la Sala Central: esas mejoras salen más a menudo.
const EQUIP_AFFINITY := {
	"case": ["heavy_case", "echo_wave", "boomerang_case", "wide_sweep", "case_blast", "case_pyro", "case_bounce", "case_cases"],
	"gavel": ["heavy_case", "gavel", "wide_sweep", "verdict", "case_size", "case_return", "case_pierce"],
	"quill": ["espresso", "expert_eye", "static_objection", "lucky_break", "case_speed", "case_multi", "case_shock"],
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
		"max": 6, "flat": false, "rarities": [0, 1, 2, 3], "tags": [], "req": {},
	}
	for k in extra.keys():
		d[k] = extra[k]
	_defs.append(d)
	_by_id[id] = d


## Alta compacta para el catálogo generado: 'fmt' = una letra de formato por estadística (en orden).
static func add_def(id: String, uname: String, cat: String, icon: String, desc: String, stats: Dictionary, fmt: String, mx: int, tags: Array, extra: Dictionary = {}) -> void:
	var f := {}
	var i := 0
	for k in stats.keys():
		f[k] = fmt[i] if i < fmt.length() else "n"
		i += 1
	var e := {"max": mx, "tags": tags}
	for k in extra.keys():
		e[k] = extra[k]
	_u(id, uname, cat, icon, desc, stats, f, e)


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
	_u("echo_wave", "Onda Residual", "aoe", "echo", "Cada impacto del maletín genera una onda secundaria ({echo_wave} del daño)", {"echo_wave": 0.12}, {"echo_wave": "p"}, {"max": 20, "mile": {"echo_wave": 0.2}})
	# ------------------------------------------------------------ ELEMENTAL
	_u("hot_ink", "Tinta Hirviente", "elem", "flame", "{burn_chance} de incendiar ({burn_dps} daño/s)", {"burn_chance": 0.06, "burn_dps": 5.0}, {"burn_chance": "p", "burn_dps": "i"}, {"max": 20, "mile": {"burn_dps": 6.0}})
	_u("frozen_assets", "Activos Congelados", "elem", "snow", "{slow_chance} de ralentizar un 45% (y {freeze_chance} de congelar)", {"slow_chance": 0.08, "freeze_chance": 0.006}, {"slow_chance": "p", "freeze_chance": "p"}, {"max": 15})
	_u("static_objection", "Objeción Estática", "elem", "zap", "{chain_chance} de rayo en cadena (+{chain_count} saltos)", {"chain_chance": 0.06, "chain_count": 0.5}, {"chain_chance": "p", "chain_count": "n"}, {"max": 15})
	_u("corrosive", "Cláusula Corrosiva", "elem", "drop", "{mark_chance} de marcar: el objetivo recibe +25% de daño", {"mark_chance": 0.07}, {"mark_chance": "p"}, {"max": 10})
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
	# ------------------------------------------------- catálogo ampliado (datos generados)
	for id in UpgradeCatalog.EXISTING_TAGS.keys():
		if _by_id.has(id):
			_by_id[id]["tags"] = UpgradeCatalog.EXISTING_TAGS[id]
	UpgradeCatalog.register()
	CaseCatalog.register()
	LawCatalog.register()


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
		# --- sinergias por ETIQUETA ("tags": etiqueta -> nº de tipos distintos de mejora con esa etiqueta).
		{"id": "tag_fire", "name": "Pirómano Legal", "desc": "4 mejoras de fuego: +25% de incendiar y ×1.2 de daño.", "needs": {}, "tags": {"fuego": 4}, "gives": {"burn_chance": 0.25, "more_dmg_x": 0.2}},
		{"id": "tag_ice", "name": "Cámara Frigorífica", "desc": "3 mejoras de hielo: +25% de ralentizar y +15% de congelar.", "needs": {}, "tags": {"hielo": 3}, "gives": {"slow_chance": 0.25, "freeze_chance": 0.15}},
		{"id": "tag_bolt", "name": "Red Eléctrica", "desc": "3 mejoras de rayo: +3 saltos de cadena y +20% de cadena.", "needs": {}, "tags": {"rayo": 3}, "gives": {"chain_count": 3.0, "chain_chance": 0.2}},
		{"id": "tag_crit", "name": "Tribunal Supremo", "desc": "4 mejoras de crítico: +15% de crítico y +0.5 de multiplicador crítico.", "needs": {}, "tags": {"critico": 4}, "gives": {"crit_chance": 0.15, "crit_mult": 0.5}},
		{"id": "tag_boom", "name": "Demolición Controlada", "desc": "4 mejoras de explosión: +25% de radio y ×1.25 de daño.", "needs": {}, "tags": {"explosion": 4}, "gives": {"aoe_pct": 0.25, "more_dmg_x": 0.25}},
		{"id": "tag_docs", "name": "Archivo General", "desc": "4 mejoras de documentos: +2 documentos y ×1.25 de daño de habilidades.", "needs": {}, "tags": {"docs": 4}, "gives": {"docs_extra": 2.0, "skill_dmg_x": 0.25}},
		{"id": "tag_shield", "name": "Fortaleza Jurídica", "desc": "5 mejoras de escudo: +60 de escudo y +10% de reducción de daño.", "needs": {}, "tags": {"escudo": 5}, "gives": {"shield_max": 60.0, "armor": 0.1}},
		{"id": "tag_case", "name": "Arsenal de Maletines", "desc": "5 mejoras de maletín: ×1.3 de daño y +15% de radio.", "needs": {}, "tags": {"maletin": 5}, "gives": {"more_dmg_x": 0.3, "aoe_pct": 0.15}},
		{"id": "tag_streak", "name": "Imparable", "desc": "4 mejoras de racha: +15% de velocidad de ataque y ×1.2 de daño.", "needs": {}, "tags": {"racha": 4}, "gives": {"atk_speed": 0.15, "more_dmg_x": 0.2}},
		{"id": "tag_ctrl", "name": "Orden en la Sala", "desc": "4 mejoras de control: +20% de aturdir/ralentizar y +10% de reducción de daño.", "needs": {}, "tags": {"control": 4}, "gives": {"slow_chance": 0.2, "armor": 0.1}},
		{"id": "tag_money", "name": "Bufete Próspero", "desc": "5 mejoras de monedas: +15% de descuento en tienda y +1 moneda por baja.", "needs": {}, "tags": {"monedas": 5}, "gives": {"shop_discount": 0.15, "kill_coins": 1.0}},
	]
	_syn_cache.append_array(CaseCatalog.synergies())
	_syn_cache.append_array(LawCatalog.synergies())
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


static func fmt_value(letter: String, v: float) -> String:
	match letter:
		"p": return "%d%%" % int(round(v * 100.0))
		"pm": return "%d%%" % int(round(absf(v) * 100.0))
		"q": return "%.1f%%" % (v * 100.0)
		"m": return "%.2f" % (1.0 + v)
		"i": return "%d" % int(round(v))
		"s": return "%.2f" % v
	return "%.1f" % v


## Texto de la carta con los valores concretos según la rareza ({clave}, {v} = 1.ª estadística, {w} = 2.ª).
static func describe(id: String, rarity: int) -> String:
	var d := get_def(id)
	if d.is_empty():
		return ""
	var txt: String = d["desc"]
	var sc := rarity_scale(d, rarity)
	var stats: Dictionary = d["stats"]
	var fmt: Dictionary = d["fmt"]
	var n := 0
	for key in fmt.keys():
		var out := fmt_value(String(fmt[key]), float(stats.get(key, 0.0)) * sc)
		txt = txt.replace("{%s}" % key, out)
		if n == 0:
			txt = txt.replace("{v}", out)
		elif n == 1:
			txt = txt.replace("{w}", out)
		n += 1
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
static func is_offerable(d: Dictionary, build: Build, depth := 0) -> bool:
	if d.get("shop_only", false):
		return false                 # artículos exclusivos de la tienda del despacho
	if build == null:
		return true
	if build.count_of(d["id"]) >= mini(int(d["max"]), UpgradeDB.MAX_LEVEL):
		return false
	# inventario lleno: solo se ofrecen las que ya tienes
	if build.count_of(d["id"]) == 0 and build.is_full():
		return false
	var first_key := String((d["stats"] as Dictionary).keys()[0])
	if CAPS.has(first_key) and float((d["stats"] as Dictionary)[first_key]) > 0.0 and build.s(first_key) >= float(CAPS[first_key]) - 0.0005:
		return false
	return requirements_met(d, build, depth)


## Requisitos y restricciones de aparición: arena mínima, mejoras/etiquetas previas y compatibilidad con el equipo.
static func requirements_met(d: Dictionary, build: Build, depth := 0) -> bool:
	var req: Dictionary = d.get("req", {})
	if req.is_empty():
		return true
	if depth < int(req.get("arena", 0)):
		return false
	if req.has("owns"):
		var ok := false
		for oid in req["owns"]:
			if build != null and build.count_of(oid) > 0:
				ok = true
		if not ok:
			return false
	if req.has("tag"):
		for tg in (req["tag"] as Dictionary).keys():
			var n := 0
			if build != null:
				for oid2 in build.counts.keys():
					if oid2 != d["id"] and (get_def(oid2).get("tags", []) as Array).has(tg):
						n += 1
			if n < int(req["tag"][tg]):
				return false
	var equipped := _equipped_ids()
	if req.has("equip_any"):
		var any := false
		for e in req["equip_any"]:
			if equipped.has(e):
				any = true
		if not any:
			return false
	if req.has("not_equip"):
		for e2 in req["not_equip"]:
			if equipped.has(e2):
				return false
	return true


static func _equipped_ids() -> Array:
	var out: Array = []
	if GameState != null and GameState.loadout is Dictionary:
		for slot in (GameState.loadout as Dictionary).keys():
			out.append(String(GameState.loadout[slot]))
	return out


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
		# profundizar una build ya empezada tiene que ser tentador; las que más has subido salen más
		w *= 1.6 + minf(float(build.count_of(id)), 30.0) * 0.05
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
## Categorías del BOTÍN ESPECIAL del jefe (3 opciones, una de cada categoría cuando hay suficientes).
const BOSS_CASE_GROUPS := {
	"PODER DEL MALETÍN": ["case_knives", "case_missiles", "case_rays", "case_orbit", "case_files", "case_ghost", "case_discs", "case_laser",
		"case_open", "case_retray", "case_kfall", "case_wave", "case_gren", "case_chase", "case_fireworks", "case_magazine", "case_cases", "case_double"],
	"EFECTOS DE COMBATE": ["case_blast", "case_shock", "case_corr", "case_pyro", "case_frag", "case_docs", "case_trail", "case_bounce", "case_pierce",
		"case_wall", "case_multi", "case_rain", "case_chain", "case_return", "case_more_knives", "case_more_missiles", "case_more_rays",
		"case_sec_range", "case_sec_pierce", "case_xtra", "case_both", "case_split", "case_seek", "case_blast_n", "case_rate", "case_retspeed"],
	"ECONOMÍA Y SUPERVIVENCIA": ["case_loot", "law_commission", "law_streak_fee", "law_clean_boss", "law_leech", "law_despacho_shield",
		"law_negotiator", "law_firm_interest", "law_efficiency", "law_billable", "law_seasoned", "law_def", "law_medic"],
}


## Botín especial del jefe: 3 opciones de categorías distintas (poder del maletín / efectos de combate / economía y
## supervivencia). Rareza mínima épica (limitada a las que admite cada mejora). Evita repetir lo ya ofrecido en la
## partida ('seen') mientras haya alternativas, así que varía entre jefes y partidas. Cada elección da +1 nivel extra.
static func boss_case_cards(build: Build, depth: int, rng: RandomNumberGenerator, min_rarity := 2, luck := 0.0, seen: Array = []) -> Array:
	_ensure()
	var avail := {}
	for g in BOSS_CASE_GROUPS.keys():
		var fresh: Array = []
		var old: Array = []
		for id in BOSS_CASE_GROUPS[g]:
			var d: Dictionary = get_def(id)
			if d.is_empty() or not is_offerable(d, build, depth):
				continue
			if seen.has(id):
				old.append(id)
			else:
				fresh.append(id)
		var ids: Array = fresh if not fresh.is_empty() else old
		if not ids.is_empty():
			avail[g] = ids
	var out: Array = []
	var order: Array = BOSS_CASE_GROUPS.keys()
	for g in order:
		if not avail.has(g):
			continue
		var ids2: Array = avail[g]
		var id2: String = ids2[rng.randi() % ids2.size()]
		out.append(_special_card(id2, g, depth, rng, min_rarity, luck))
		(avail[g] as Array).erase(id2)
	# si una categoría no tenía nada que ofrecer, se completa con otras (nunca repite la misma mejora)
	var guard := 0
	while out.size() < 3 and guard < 20:
		guard += 1
		var gs: Array = []
		for g in avail.keys():
			if not (avail[g] as Array).is_empty():
				gs.append(g)
		if gs.is_empty():
			break
		var g2: String = gs[rng.randi() % gs.size()]
		var ids3: Array = avail[g2]
		var id3: String = ids3[rng.randi() % ids3.size()]
		(avail[g2] as Array).erase(id3)
		out.append(_special_card(id3, g2, depth, rng, min_rarity, luck))
	return out


static func _special_card(id: String, group: String, depth: int, rng: RandomNumberGenerator, min_rarity: int, luck: float) -> Dictionary:
	var d: Dictionary = get_def(id)
	var rs: Array = d["rarities"]
	var rar := clampi(_roll_rarity(luck, depth, rng, min_rarity), rs[0], rs[rs.size() - 1])
	return {"id": id, "rarity": rar, "group": group, "special": true}


static func roll_cards(count: int, luck: float, depth: int, build: Build, rng: RandomNumberGenerator, min_rarity := 0, exclude: Array = []) -> Array:
	_ensure()
	var cards: Array = []
	var used := {}
	for ex in exclude:
		used[String(ex)] = true          # p. ej. la 2.ª recompensa de un cofre doble nunca repite la 1.ª
	var equipped: Array = []
	if GameState != null and GameState.loadout is Dictionary:
		for slot in (GameState.loadout as Dictionary).keys():
			equipped.append(String(GameState.loadout[slot]))
	# la lista de ofrecibles se calcula UNA vez por cofre (con 240+ mejoras evita recalcular los requisitos por carta)
	var wcache := {}
	var offerable: Array = []
	for d in _defs:
		if is_offerable(d, build, depth):
			offerable.append(d)
	for i in count:
		var force_min := min_rarity if i == 0 else 0
		var rarity := _roll_rarity(luck, depth, rng, force_min)
		var pool: Array = []
		for d in offerable:
			if not used.has(d["id"]):
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
			if not wcache.has(d["id"]):
				wcache[d["id"]] = _pick_weight(d, build, equipped)
			var w: float = wcache[d["id"]]
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


## Artículos exclusivos de la tienda (shop_only) que se pueden comprar ahora: no están al máximo ni el inventario lleno.
static func shop_items(build: Build) -> Array:
	_ensure()
	var out: Array = []
	for d in _defs:
		if not d.get("shop_only", false):
			continue
		if build != null:
			var n := build.count_of(d["id"])
			if n >= int(d["max"]):
				continue
			if n == 0 and build.is_full():
				continue
		out.append(d)
	return out


## Rareza de un artículo de tienda: ponderada por las probabilidades normales (suerte y profundidad) dentro de las que admite.
static func roll_shop_rarity(d: Dictionary, luck: float, depth: int, rng: RandomNumberGenerator) -> int:
	var rs: Array = d["rarities"]
	var total := 0.0
	var ws: Array = []
	for r in rs:
		var w: float = RARITY_WEIGHT[r] * (1.0 + (luck * float(r) + depth * 0.02 * float(r)))
		ws.append(w)
		total += w
	var x := rng.randf() * total
	for i in rs.size():
		x -= float(ws[i])
		if x <= 0.0:
			return int(rs[i])
	return int(rs[rs.size() - 1])


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
	var label := stat_label(key)
	if f == "m":
		return "%s ×%.2f" % [label, v]
	return "%s %s" % [label, fmt_value(f, v)]


const EVENT_NAMES := {"hit": "Al golpear", "crit": "Al crítico", "kill": "Al eliminar", "slam": "Al impactar el maletín", "skill": "Al usar habilidad",
	"dodge": "Al esquivar", "hurt": "Al recibir daño", "shield_break": "Al romperse el escudo", "arena_clear": "Al limpiar arena", "arena_start": "Al empezar arena",
	"levelup": "Al subir de nivel", "t3": "Cada 3 s", "t5": "Cada 5 s", "t8": "Cada 8 s", "t12": "Cada 12 s"}
const EFFECT_NAMES := {"heal_pct": "curar", "heal_flat": "curar", "shield": "escudo", "energy": "Expediente", "cdr": "enfriamientos", "buff_dmg": "daño temporal",
	"buff_haste": "prisa de ataque", "buff_speed": "velocidad temporal", "buff_armor": "armadura temporal", "buff_crit": "crítico temporal", "nova": "explosión",
	"nova_at": "explosión en objetivo", "chain": "rayo", "burn_area": "incendio", "slow_area": "ralentizar", "freeze_area": "congelar", "mark_area": "marcar",
	"stun_area": "aturdir", "coins": "monedas", "xp": "experiencia", "missile": "documentos", "pull": "atraer", "push": "empujar", "invuln": "invulnerabilidad",
	"reset_dodge": "reiniciar esquiva", "boomerang": "bumerán"}
const COND_NAMES := {"burning": "en llamas", "slowed": "ralentizados", "frozen": "congelados", "marked": "marcados", "full": "salud alta", "wounded": "heridos",
	"far": "lejanos", "near": "cercanos", "crowd": "grupo", "alone": "objetivo único", "lowhp": "tu salud baja", "fullhp": "tu salud alta", "shield": "con escudo",
	"barrier": "con Objeción", "hasted": "con prisa", "moving": "en movimiento", "still": "quieto", "air": "en el aire", "streak": "racha", "combo": "combo",
	"energy": "Expediente lleno", "rich": "con monedas", "boss_arena": "arena de jefe"}


## Nombre legible de una clave de estadística, incluidas las de disparadores (t:), condiciones (c:) y fuentes (s:).
static func stat_label(key: String) -> String:
	if key.begins_with("t:"):
		var p := key.split(":")
		if p.size() == 3:
			return "%s: %s" % [EVENT_NAMES.get(p[1], p[1]), EFFECT_NAMES.get(p[2], p[2])]
	if key.begins_with("c:"):
		return "Daño (%s)" % COND_NAMES.get(key.substr(2), key.substr(2))
	if key.begins_with("s:"):
		return "Daño de %s" % key.substr(2)
	if CaseCatalog.LABELS.has(key):
		return String(CaseCatalog.LABELS[key])
	if LawCatalog.LABELS.has(key):
		return String(LawCatalog.LABELS[key])
	return String(STAT_LABELS.get(key, key))


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
	"hp_regen_pct": "Regen. %", "heal_pow": "Curación", "armor_low": "Armadura (vida baja)", "iframe_add": "Invuln. esquiva", "dodge_speed": "Vel. esquiva",
	"hurt_iframe_add": "Invuln. tras golpe", "shield_regen_pct": "Regen. escudo", "shield_delay_cut": "Retardo escudo", "jump_pow": "Salto", "max_hp_flat": "Salud plana",
	"lifesteal": "Robo de vida", "magnet": "Imán", "cd_docs": "Enfr. documentos", "cd_seal": "Enfr. sello", "cd_barrier": "Enfr. objeción", "cd_slam": "Enfr. maletín",
	"docs_pierce": "Perforación", "docs_speed": "Vel. documentos", "docs_turn": "Teledirección", "seal_radius": "Radio sello", "seal_time": "Duración sello",
	"barrier_hp_pct": "Resist. objeción", "barrier_time": "Duración objeción", "energy_max_add": "Expediente máx.", "energy_regen_pct": "Regen. expediente",
	"cost_cut": "Coste habilidades", "slam_radius": "Radio maletín", "slam_arc": "Arco maletín", "slam_knock": "Empuje maletín", "slam_double": "Doble golpe",
	"knock_pow": "Empuje", "stagger_add": "Aturdimiento", "exec_thr": "Umbral ejecución", "explosion_pow": "Daño explosiones", "explo_rad": "Radio explosiones",
	"burn_dur": "Duración fuego", "slow_dur": "Duración frío", "freeze_dur": "Duración hielo", "mark_amp": "Marca extra", "mark_dur": "Duración marca",
	"chain_dmg": "Daño rayo", "burn_spread": "Contagio", "chest_cards": "Cartas extra", "reroll_cut": "Relanzar", "skip_bonus": "Descarte", "sell_bonus": "Venta",
	"clear_coins": "Monedas/arena", "interest": "Interés", "kill_coins": "Monedas/baja", "xp_kill": "XP/baja", "epic_luck": "Fortuna épica", "boss_coins": "Botín jefe",
	"slow_amt": "Ralentización",
}


static func mile_text(d: Dictionary) -> String:
	var parts: Array = []
	for key in (d["mile"] as Dictionary).keys():
		var v := float(d["mile"][key])
		var label := stat_label(String(key))
		if String(key).ends_with("_x"):
			parts.append("%s ×%.2f" % [label, 1.0 + v])
		elif v < 5.0:
			parts.append("%s +%d%%" % [label, int(round(v * 100.0))])
		else:
			parts.append("%s +%d" % [label, int(round(v))])
	return ", ".join(parts)


static func _roll_rarity(luck: float, depth: int, rng: RandomNumberGenerator, min_rarity: int) -> int:
	var w := RARITY_WEIGHT.duplicate()
	var el: float = GameState.build.s("epic_luck") if GameState != null and GameState.build != null else 0.0
	w[1] *= 1.0 + luck * 1.0 + depth * 0.02
	w[2] *= 1.0 + luck * 2.0 + depth * 0.05 + el
	w[3] *= 1.0 + luck * 3.0 + depth * 0.08 + el * 1.5
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
