class_name CaseCatalog
extends RefCounted
## Mejoras que alteran DIRECTAMENTE el lanzamiento del maletín (estilo "builds" de Crab Champions, contenido propio).
## Son datos: las estadísticas bc_* las lee CaseThrow.make_profile()/plan_cases() al lanzar. Se combinan todas en la
## misma tirada (ver CaseThrow._impact). Los niveles suben al repetirse en cofres (máx. por mejora en cada alta).
##
## Descripciones: {v} = 1.ª estadística, {w} = 2.ª. Aparecen tal cual en cartas, tienda e inventario.

const LABELS := {
	"bc_dmg": "Daño del maletín", "bc_range": "Alcance", "bc_size": "Tamaño", "bc_speed": "Velocidad de vuelo",
	"bc_homing": "Teledirección", "bc_pierce": "Perforaciones", "bc_bounce": "Rebotes entre enemigos", "bc_wall": "Rebote en el entorno (s)",
	"bc_sharp": "Daño en el regreso", "bc_blast": "Explosión por impacto", "bc_blast_r": "Radio de explosión",
	"bc_pyro": "Prob. de fuegos artificiales", "bc_pyro_n": "Cohetes extra", "bc_frag": "Fragmentos por impacto", "bc_frag_dmg": "Daño de fragmentos",
	"bc_docs": "Documentos por impacto", "bc_rain": "Prob. de lluvia", "bc_rain_n": "Documentos de lluvia", "bc_shock": "Prob. eléctrica",
	"bc_shock_n": "Saltos eléctricos", "bc_corr": "Prob. de corrosión", "bc_spread": "Propagación de estados", "bc_trail": "Daño del rastro",
	"bc_multi": "Minimaletines en vuelo", "bc_return": "Explosión de retorno", "bc_return_r": "Radio de retorno", "bc_catch": "Prisa al atrapar",
	"bc_fw": "Fuegos artificiales por tiro", "bc_rate": "Cadencia de lanzamiento", "bc_ret": "Velocidad de retorno",
	"bc_ammo": "Maletines de reserva", "bc_loot": "Monedas por maletín recuperado",
	"bc_cases": "Maletines extra", "bc_double": "Doble maletín", "bc_crit": "Crítico contractual",
}


static func register() -> void:
	# ---------------------------------------------------------------- base del lanzamiento
	UpgradeDB.add_def("case_dmg", "Maletín Reforzado", "case", "sword", "El maletín lanzado hace +{v} de daño", {"bc_dmg": 0.14}, "p", 20, ["maletin", "lanzamiento"])
	UpgradeDB.add_def("case_range", "Cadena Larga", "case", "boomerang", "El maletín llega +{v} más lejos antes de volver", {"bc_range": 0.08}, "p", 10, ["maletin", "lanzamiento"])
	UpgradeDB.add_def("case_size", "Maletín Sobredimensionado", "case", "mega", "El maletín es +{v} más grande y golpea más ancho", {"bc_size": 0.1}, "p", 8, ["maletin", "lanzamiento"])
	UpgradeDB.add_def("case_speed", "Lanzamiento Veloz", "case", "fast", "El maletín vuela +{v} más rápido (ida y vuelta)", {"bc_speed": 0.1}, "p", 10, ["maletin", "lanzamiento"])
	UpgradeDB.add_def("case_homing", "Maletín Teledirigido", "case", "target", "La ida del maletín se curva hacia los enemigos cercanos ({v} de guiado)", {"bc_homing": 0.15}, "p", 6, ["maletin", "lanzamiento"])
	UpgradeDB.add_def("case_sharp", "Esquinas Afiladas", "case", "blade", "El maletín también golpea en el REGRESO (50% del daño de ida, +{v} por nivel)", {"bc_sharp": 0.15}, "p", 6, ["maletin", "lanzamiento"])
	UpgradeDB.add_def("case_catch", "Atrapar al Vuelo", "case", "wind", "Al recuperar el maletín: +{v} de velocidad de ataque 2.5 s", {"bc_catch": 0.1}, "p", 6, ["maletin", "ataque"])
	UpgradeDB.add_def("case_fireworks", "Salva de Fuegos Artificiales", "case", "burst", "Cada lanzamiento del maletín dispara {v} cohete(s) de fuegos artificiales", {"bc_fw": 1}, "i", 4, ["maletin", "lanzamiento"])
	UpgradeDB.add_def("case_rate", "Cadencia de Despacho", "case", "fast", "Puedes lanzar el maletín +{v} más a menudo", {"bc_rate": 0.15}, "p", 8, ["maletin", "ataque"])
	UpgradeDB.add_def("case_retspeed", "Retorno Express", "case", "wind", "El maletín vuelve +{v} más rápido a tu mano", {"bc_ret": 0.25}, "p", 6, ["maletin", "lanzamiento"])
	UpgradeDB.add_def("case_magazine", "Cargador de Maletines", "case", "mega", "Guardas {v} maletín(es) de reserva: lanzas en ráfaga como un subfusil sin esperar a que vuelvan", {"bc_ammo": 1}, "i", 4, ["maletin", "ataque"])
	UpgradeDB.add_def("case_loot", "Maletín Cobrador", "case", "coin", "Al recuperar el maletín cobras {v} moneda(s) por enemigo golpeado (con tope por ronda)", {"bc_loot": 1}, "i", 5, ["maletin", "economia"])
	UpgradeDB.add_def("case_crit", "Crítico Contractual", "crit", "eye", "Los impactos del maletín (y sus derivados) tienen +{v} de prob. de crítico", {"bc_crit": 0.04}, "p", 15, ["maletin", "critico"])
	# ---------------------------------------------------------------- trayectoria
	UpgradeDB.add_def("case_pierce", "Perforación Documental", "case", "page", "El maletín atraviesa a {v} enemigo(s) más y sigue su camino", {"bc_pierce": 1.0}, "i", 6, ["maletin", "lanzamiento"], {"flat": true})
	UpgradeDB.add_def("case_bounce", "Rebote Judicial", "case", "boomerang", "Tras un impacto rebota hacia otro enemigo cercano ({v} rebote(s)) antes de volver", {"bc_bounce": 1.0}, "i", 6, ["maletin", "lanzamiento"], {"flat": true})
	UpgradeDB.add_def("case_wall", "Rebotes de Maletín", "case", "ring", "Al llegar al final (o a una pared) rebota por el entorno durante {v} s antes de volver", {"bc_wall": 0.5}, "s", 5, ["maletin", "lanzamiento"], {"req": {"arena": 2}})
	UpgradeDB.add_def("case_cases", "Multi Maletín", "case", "layers", "Lanzas {v} maletín(es) más cada vez, en abanico (cada nivel +1)", {"bc_cases": 1.0}, "i", 5, ["maletin", "lanzamiento"], {"flat": true, "req": {"arena": 2}})
	UpgradeDB.add_def("case_double", "Doble Maletín", "case", "echo", "Segundo maletín con SU PROPIO recorrido (curva contraria, daño 60% +12% por nivel). Es un proyectil aparte: no duplica los efectos de retorno", {"bc_double": 1.0}, "i", 4, ["maletin", "lanzamiento"], {"flat": true, "req": {"arena": 3}})
	UpgradeDB.add_def("case_multi", "Multilanzamiento", "case", "fast", "Mientras vuela suelta minimaletines laterales (prob. {v} cada 0.4 s, 42% del daño)", {"bc_multi": 0.5}, "p", 6, ["maletin", "proyectil"])
	# ---------------------------------------------------------------- efectos al impactar
	UpgradeDB.add_def("case_blast", "Explosión Legal", "aoe", "burst", "Cada impacto provoca una explosión alrededor del enemigo ({v} del daño, radio +{w})", {"bc_blast": 0.35, "bc_blast_r": 0.15}, "pp", 8, ["maletin", "explosion"])
	UpgradeDB.add_def("case_pyro", "Maletín Pirotécnico", "elem", "flame", "Al impactar ({v} prob.): dispara fuegos artificiales que buscan enemigos y explotan (+1 cohete cada 3 niveles)", {"bc_pyro": 0.2, "bc_pyro_n": 0.34}, "pn", 5, ["maletin", "fuego", "explosion", "proyectil"])
	UpgradeDB.add_def("case_frag", "Fragmentación", "case", "nova", "Al impactar salen {v} fragmentos que pueden golpear a otros enemigos", {"bc_frag": 2.0, "bc_frag_dmg": 0.02}, "in", 5, ["maletin", "proyectil", "explosion"])
	UpgradeDB.add_def("case_docs", "Documentos Explosivos", "docs", "doc", "Al impactar libera {v} documento(s) que persiguen enemigos cercanos y explotan", {"bc_docs": 1.0}, "i", 6, ["maletin", "docs", "explosion", "proyectil"], {"flat": true})
	UpgradeDB.add_def("case_rain", "Lluvia de Documentos", "docs", "paper", "Al impactar ({v} prob., enfr. 0.9 s): llueven documentos sobre la zona (+1 cada 2 niveles)", {"bc_rain": 0.2, "bc_rain_n": 0.5}, "pn", 5, ["maletin", "docs", "proyectil"])
	UpgradeDB.add_def("case_trail", "Rastro de Fuego", "elem", "fire2", "El maletín deja una estela de fuego que daña ({v} del daño por pulso)", {"bc_trail": 0.12}, "p", 10, ["maletin", "fuego"])
	UpgradeDB.add_def("case_shock", "Maletín Eléctrico", "elem", "bolt", "Al impactar ({v} prob.): rayo en cadena entre enemigos (+1 salto cada 3 niveles)", {"bc_shock": 0.25, "bc_shock_n": 0.34}, "pn", 4, ["maletin", "rayo", "cadena"])
	UpgradeDB.add_def("case_corr", "Maletín Corrosivo", "elem", "drop", "Al impactar ({v} prob.): marca al enemigo (recibe más daño de todo)", {"bc_corr": 0.25}, "p", 4, ["maletin", "marca"])
	UpgradeDB.add_def("case_chain", "Cadena de Impactos", "aoe", "link", "Fuego, marcas y ralentización de un enemigo golpeado se propagan a {v} más cercano(s) (+1 cada 2 niveles)", {"bc_spread": 2.0}, "i", 6, ["maletin", "cadena", "fuego", "marca"])
	UpgradeDB.add_def("case_return", "Retorno Explosivo", "aoe", "nova", "Al recuperar el maletín: explosión a tu alrededor ({v} del daño, radio +{w})", {"bc_return": 0.7, "bc_return_r": 0.2}, "pp", 6, ["maletin", "explosion"])


## Sinergias del maletín (se añaden a UpgradeDB.synergies()).
static func synergies() -> Array:
	return [
		{"id": "pyro_party", "name": "Fiesta Pirotécnica", "desc": "Pirotécnico + Fragmentación: cada cohete se rompe en 4 fragmentos al explotar.", "needs": {"bc_pyro": 0.01, "bc_frag": 0.01}, "gives": {"syn_pyro_frag": 1.0}},
		{"id": "judicial_conductor", "name": "Pararrayos Judicial", "desc": "Eléctrico + Rebote Judicial: cada rebote entre enemigos descarga un rayo.", "needs": {"bc_shock": 0.01, "bc_bounce": 0.5}, "gives": {"syn_conductor": 1.0}},
		{"id": "grand_finale", "name": "Gran Final", "desc": "Retorno Explosivo + Pirotécnico: al volver, el maletín lanza fuegos artificiales.", "needs": {"bc_return": 0.01, "bc_pyro": 0.01}, "gives": {"syn_return_fw": 1.0}},
		{"id": "inferno_trail", "name": "Estela Infernal", "desc": "Rastro de Fuego + Explosión Legal: la estela incendia a quien toca.", "needs": {"bc_trail": 0.01, "bc_blast": 0.01}, "gives": {"syn_inferno_trail": 1.0}},
		{"id": "pinball", "name": "Pinball Legal", "desc": "Rebotes en el entorno + Rebote Judicial: +2 rebotes y +25% de daño por rebote acumulado.", "needs": {"bc_wall": 0.01, "bc_bounce": 0.5}, "gives": {"syn_pinball": 1.0}},
		{"id": "case_arsenal", "name": "Arsenal Aéreo", "desc": "Multi Maletín + Doble Maletín: ×1.25 de daño total.", "needs": {"bc_cases": 0.5, "bc_double": 0.5}, "gives": {"more_dmg_x": 0.25}},
	]
