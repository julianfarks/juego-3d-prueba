class_name LawCatalog
extends RefCounted
## Ampliación judicial v0.11: 15 poderes nuevos (combate, defensa y movilidad), 6 de economía, 15 artículos exclusivos de la
## tienda y 6 sinergias. Son DATOS: las estadísticas law_* las leen LawPerks (efectos), CaseThrow (maletín) y Combat/Player.
## Los artículos "shop_only" no salen en los cofres: solo se compran en la tienda del despacho.

const LABELS := {
	"law_demo": "Daño de ida", "law_ret": "Daño al regresar", "law_pierce": "Perforación extra", "law_dbl": "Prob. de 2.º proyectil",
	"law_sent": "Crítico (Sentencia)", "law_obj": "Daño por objeción", "law_gavel": "Impacto del mazo", "law_papers": "Papeles orbitales",
	"law_final": "Daño a debilitados", "law_def": "Reducción de daño", "law_dodge": "Bonus tras esquivar", "law_block": "Bloqueo de expedientes",
	"law_medic": "Cura por bajas", "law_immun": "Escudo de inmunidad",
	"law_fee_win": "Monedas por baja", "law_vip": "Cliente de alto perfil", "law_adv": "Cobro anticipado", "law_firm": "Intereses del bufete",
	"law_eff": "Eficiencia",
}

## Grupos de la tienda (para variar y para complementar la build).
const SHOP_GROUPS := {
	"shop_suit": "Defensiva", "shop_vest": "Defensiva", "shop_toga": "Defensiva",
	"shop_case": "Ofensiva", "shop_pen": "Ofensiva", "shop_coffee": "Ofensiva",
	"shop_shoes": "Movilidad", "shop_stamp": "Movilidad",
	"shop_account": "Económica", "shop_wallet": "Económica", "shop_vip": "Económica",
	"shop_insurance": "Curación",
	"shop_contract": "Especial", "shop_key": "Especial", "shop_notary": "Especial",
}


static func register() -> void:
	# ------------------------------------------------------------------ COMBATE
	UpgradeDB.add_def("law_demolisher", "Maletín Demoledor", "case", "sword", "El maletín lanzado hace +{v} de daño en la IDA", {"law_demo": 0.18}, "p", 12, ["maletin", "ataque"])
	UpgradeDB.add_def("law_return", "Regreso Letal", "case", "boomerang", "El maletín golpea al REGRESAR con {v} del daño de ida (se suma a otros daños de regreso)", {"law_ret": 0.35}, "p", 8, ["maletin", "ataque"])
	UpgradeDB.add_def("law_piercing", "Expediente Perforante", "case", "page", "El maletín atraviesa a {v} enemigo(s) adicional(es) sin detenerse", {"law_pierce": 1.0}, "i", 4, ["maletin", "lanzamiento"], {"flat": true})
	UpgradeDB.add_def("law_double", "Doble Alegato", "case", "boomerang", "{v} de prob. de lanzar un 2.º maletín (65% del daño, recorrido propio)", {"law_dbl": 0.08}, "p", 5, ["maletin", "lanzamiento"], {"req": {"arena": 2}})
	# ---- poderes que mejoran con el paso del tiempo (todos con tope: más rotos cuanto más dura la partida, sin romperla)
	UpgradeDB.add_def("law_tenure", "Antigüedad del Bufete", "dmg", "clock", "+{v} de daño por cada minuto de partida (tope: 20 min)", {"law_tenure": 0.01}, "p", 8, ["tiempo", "ataque"])
	UpgradeDB.add_def("law_momentum", "Impulso Procesal", "dmg", "fast", "+{v} de daño cada 10 s dentro de la ronda (hasta 10 veces; se reinicia en cada ronda)", {"law_momentum": 0.015}, "p", 8, ["tiempo", "ataque"])
	UpgradeDB.add_def("law_caseload", "Carga de Casos", "dmg", "book", "+{v} de daño por cada 10 bajas de la partida (tope +60% por nivel acumulado)", {"law_caseload": 0.004}, "p", 8, ["tiempo", "racha"])
	UpgradeDB.add_def("law_billable", "Horas Facturables", "gold", "coin", "Cada 20 s cobras {v} moneda(s) (crece con la arena; solo en combate)", {"law_bill": 1.0}, "i", 5, ["tiempo", "economia"])
	UpgradeDB.add_def("law_seasoned", "Curtido en Sala", "hp", "heart", "Cada 10 s te curas {v} de tu salud máxima (solo en combate)", {"law_season": 0.006}, "p", 8, ["tiempo", "defensa"])
	UpgradeDB.add_def("law_sentence", "Sentencia Crítica", "crit", "target", "Prob. de golpe crítico +{v}", {"law_sent": 0.04}, "p", 10, ["critico"])
	UpgradeDB.add_def("law_objection_chain", "Cadena de Objeciones", "streak", "chain", "Cada baja: +{v} de daño durante 5 s (acumulable hasta 8 veces)", {"law_obj": 0.015}, "p", 8, ["racha", "ataque"])
	UpgradeDB.add_def("law_gavel_strike", "Mazo Judicial", "aoe", "gavel", "Cada pocos lanzamientos (7, menos con niveles) el mazo golpea a tu alrededor: {v} del daño base", {"law_gavel": 0.8}, "p", 6, ["maletin", "explosion"], {"req": {"arena": 2}})
	UpgradeDB.add_def("law_cutting_papers", "Papeles Cortantes", "docs", "page", "{v} papel(es) giran a tu alrededor y cortan a los enemigos que tocan", {"law_papers": 1.0}, "i", 4, ["docs", "proyectil"], {"flat": true})
	UpgradeDB.add_def("law_final_word", "Última Palabra", "dmg", "skull", "+{v} de daño a enemigos con menos de 30% de salud", {"law_final": 0.18}, "p", 8, ["ejecucion"])
	# ------------------------------------------------------- DEFENSA Y MOVILIDAD
	UpgradeDB.add_def("law_procedural", "Defensa Procesal", "shield", "shield", "Reduces {v} del daño que recibes (máx. 35%)", {"law_def": 0.04}, "p", 8, ["escudo"])
	UpgradeDB.add_def("law_legal_dodge", "Evasión Legal", "speed", "shoe", "Tras esquivar: +{v} de daño durante 3 s (y el siguiente golpe es un 40% más fuerte)", {"law_dodge": 0.12}, "p", 8, ["esquiva", "ataque"])
	UpgradeDB.add_def("law_file_shield", "Blindaje de Expedientes", "shield", "badge", "{v} de prob. de bloquear un impacto (máx. 30%, 1 s entre bloqueos)", {"law_block": 0.05}, "p", 6, ["escudo"])
	UpgradeDB.add_def("law_medic", "Recuperación Médica", "hp", "cross", "Cada 5 bajas recuperas {v} de tu salud máx. (límite: 20% de tu salud por ronda)", {"law_medic": 0.015}, "q", 8, ["vida", "racha"])
	UpgradeDB.add_def("law_appeal", "Impulso de Apelación", "speed", "wind", "Esquiva -{v} de enfriamiento y +{w} de velocidad de esquiva", {"dodge_cd": 0.05, "dodge_speed": 0.08}, "pp", 6, ["esquiva", "velocidad"])
	UpgradeDB.add_def("law_immunity_shield", "Escudo de Inmunidad", "shield", "zzz", "Tras un golpe grave (≥12% de tu salud): {v} de escudo y 1.2 s de invulnerabilidad (recarga 25 s)", {"law_immun": 14.0}, "i", 6, ["escudo"], {"rarities": [1, 2, 3], "req": {"arena": 3}})
	# ------------------------------------------------------------------ ECONOMÍA
	UpgradeDB.add_def("law_win_fees", "Honorarios por Victoria", "eco", "coin", "Las monedas que sueltan los enemigos +{v} (máx. +60%)", {"law_fee_win": 0.06}, "p", 8, ["monedas"])
	UpgradeDB.add_def("law_vip_client", "Cliente de Alto Perfil", "eco", "crown", "Élites y jefes sueltan +{v} de monedas; limpiar arenas especiales y jefes paga un extra", {"law_vip": 0.2}, "p", 6, ["monedas"], {"req": {"arena": 3}})
	UpgradeDB.add_def("law_advance_fee", "Cobro Anticipado", "eco", "coin", "Al empezar cada ronda recibes +{v} moneda(s) (crece con las rondas, máx. 60)", {"law_adv": 4.0}, "i", 8, ["monedas"], {"flat": true})
	UpgradeDB.add_def("law_firm_interest", "Intereses del Bufete", "eco", "gem", "Al terminar cada zona (rondas 5, 10, 15…) ganas {v} de tus monedas (máx. 80 por pago)", {"law_firm": 0.03}, "p", 5, ["monedas"], {"req": {"arena": 3}})
	UpgradeDB.add_def("law_negotiator", "Negociador Experto", "eco", "gem", "Todo cuesta {v} menos en la tienda (se suma al descuento existente, máx. 50%)", {"shop_discount": 0.04}, "p", 8, ["monedas"])
	UpgradeDB.add_def("law_efficiency", "Recompensa por Eficiencia", "eco", "star", "Ronda con ≤20% de salud perdida: +{v} moneda(s) (crece con las rondas, máx. 120)", {"law_eff": 12.0}, "i", 6, ["monedas", "vida"], {"flat": true})
	# ---------------------------------------------- TIENDA (no salen en los cofres)
	var S := {"shop_only": true}
	_shop("shop_suit", "Traje a Medida", "shield", "badge", "+{v} de salud máxima", {"max_hp_flat": 18.0}, "i", 6, [0, 1], ["vida"])
	_shop("shop_vest", "Chaleco de Cortesía", "shield", "vest", "+{v} de escudo máximo y recarga más rápida", {"shield_max": 14.0, "shield_regen_pct": 0.15}, "ip", 5, [0, 1, 2], ["escudo"])
	_shop("shop_toga", "Toga Reforzada", "shield", "badge", "Reduces {v} el daño recibido y {w} de prob. de bloquear", {"armor": 0.03, "block": 0.02}, "pp", 5, [1, 2], ["escudo"])
	_shop("shop_case", "Maletín Cromado", "dmg", "sword", "+{v} de daño plano y +{w} de daño del maletín", {"flat_dmg": 4.0, "bc_dmg": 0.06}, "ip", 6, [0, 1, 2], ["maletin"])
	_shop("shop_pen", "Pluma Estilográfica", "crit", "eye", "Crítico +{v} y daño crítico +{w}", {"crit_chance": 0.03, "crit_mult": 0.1}, "pp", 6, [0, 1, 2], ["critico"])
	_shop("shop_coffee", "Café Doble del Bufete", "atk", "cup", "Velocidad de ataque +{v} y Expediente +{w} más rápido", {"atk_speed": 0.05, "energy_regen_pct": 0.06}, "pp", 5, [0, 1, 2], ["ataque"])
	_shop("shop_shoes", "Zapatos de Tribunal", "speed", "shoe", "Velocidad +{v} y esquiva +{w} más veloz", {"move_speed": 0.05, "dodge_speed": 0.06}, "pp", 5, [0, 1, 2], ["velocidad", "esquiva"])
	_shop("shop_stamp", "Sello Urgente", "speed", "wind", "Esquiva -{v} de enfriamiento y +{w} de velocidad", {"dodge_cd": 0.06, "move_speed": 0.03}, "pp", 4, [0, 1, 2], ["esquiva"])
	_shop("shop_account", "Cuenta de Cliente", "eco", "coin", "Todas las monedas que ganas +{v} (máx. 4 niveles)", {"coin_pct": 0.08}, "p", 4, [0, 1, 2], ["monedas"])
	_shop("shop_wallet", "Cartera Gruesa", "eco", "coin", "{v} de prob. de +1 moneda por baja y las monedas te alcanzan desde más lejos", {"kill_coins": 0.05, "magnet": 1.2}, "pn", 4, [0, 1, 2], ["monedas"])
	_shop("shop_vip", "Pase VIP", "eco", "gem", "Relanzar ofertas cuesta {v} menos y la tienda {w} menos", {"reroll_cut": 0.12, "shop_discount": 0.03}, "pp", 3, [1, 2], ["monedas"])
	_shop("shop_insurance", "Seguro Premium", "hp", "heart", "Regeneras {v} de salud máx. por s y las curas son {w} más potentes", {"hp_regen_pct": 0.004, "heal_pow": 0.1}, "qp", 4, [0, 1, 2], ["vida"])
	_shop("shop_contract", "Contrato Exclusivo", "legend", "crown", "Todo tu daño ×{v}", {"more_dmg_x": 0.12}, "m", 2, [2, 3], ["ataque"])
	_shop("shop_key", "Llave del Archivo", "legend", "gem", "Los cofres ofrecen {v} carta(s) más para elegir", {"chest_cards": 1.0}, "i", 1, [1, 2], ["monedas"], true)
	_shop("shop_notary", "Notario Personal", "legend", "gear", "Enfriamientos -{v} y habilidades ×{w} de daño", {"cdr": 0.05, "skill_dmg_x": 0.1}, "pm", 3, [2, 3], ["habilidad"])


static func _shop(id: String, uname: String, cat: String, icon: String, desc: String, stats: Dictionary, fmt: String, mx: int, rarities: Array, tags: Array, flat := false) -> void:
	UpgradeDB.add_def(id, uname, cat, icon, desc, stats, fmt, mx, tags, {"shop_only": true, "rarities": rarities, "flat": flat})


## Sinergias (se añaden a UpgradeDB.synergies()). Se activan solas al reunir las piezas y se muestran en el inventario.
static func synergies() -> Array:
	return [
		{"id": "law_case_duo", "name": "Doble Sentencia", "desc": "Maletín Demoledor + Regreso Letal: el maletín hace +25% de daño al regresar y el bonus de ida también cuenta al volver.", "needs": {"law_demo": 0.01, "law_ret": 0.01}, "gives": {"syn_law_case": 1.0}},
		{"id": "law_paper_pierce", "name": "Archivo Cortante", "desc": "Expediente Perforante + Papeles Cortantes: +1 perforación, +1 papel y papeles más grandes (+30% de daño).", "needs": {"law_pierce": 0.5, "law_papers": 0.5}, "gives": {"syn_law_papers": 1.0}},
		{"id": "law_dodge_chain", "name": "Contraataque Procesal", "desc": "Evasión Legal + Cadena de Objeciones: esquivar suma 3 objeciones y el siguiente golpe sale con +60% de daño.", "needs": {"law_dodge": 0.01, "law_obj": 0.001}, "gives": {"syn_law_dodge": 1.0}},
		{"id": "law_medic_def", "name": "Cobertura Médica", "desc": "Recuperación Médica + Defensa Procesal: +5% de reducción de daño y la cura por baja es ×1.5 (límite por ronda: 30%).", "needs": {"law_medic": 0.001, "law_def": 0.01}, "gives": {"syn_law_medic": 1.0, "armor": 0.05}},
		{"id": "law_crit_final", "name": "Veredicto Final", "desc": "Sentencia Crítica + Última Palabra: los críticos a enemigos debilitados hacen ×1.4 de daño.", "needs": {"law_sent": 0.01, "law_final": 0.01}, "gives": {"syn_law_final": 1.0}},
		{"id": "law_fee_eff", "name": "Bufete Eficiente", "desc": "Honorarios por Victoria + Recompensa por Eficiencia: la bonificación de eficiencia paga ×1.5.", "needs": {"law_fee_win": 0.01, "law_eff": 1.0}, "gives": {"syn_law_eff": 1.0}},
	]
