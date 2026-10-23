class_name UpgradeCatalog
extends RefCounted
## Catálogo de mejoras GENERADO a partir de tablas (ver tools/gen_catalog.py). Cada entrada es DATO: stats que
## leen Combat/Player/Skills/Perks. Aquí no hay lógica de efectos.

const EXISTING_TAGS := {
	"heavy_case": ["maletin"],
	"precedent": ["maletin"],
	"closing_arg": ["ejecucion"],
	"hostile_witness": ["ejecucion"],
	"overtime": ["ataque"],
	"contingency": ["monedas"],
	"chain_custody": ["maletin", "racha"],
	"kinetic_law": ["velocidad"],
	"italian_shoes": ["velocidad"],
	"rush_hour": ["esquiva"],
	"express": ["velocidad"],
	"slide_clause": ["esquiva"],
	"espresso": ["ataque"],
	"paralegal": ["habilidad"],
	"notarial_burst": ["esquiva", "ataque"],
	"multitask": ["habilidad"],
	"expert_eye": ["critico"],
	"gavel": ["critico", "maletin"],
	"verdict": ["critico", "explosion"],
	"lucky_break": ["critico", "habilidad"],
	"health_plan": ["vida"],
	"legal_nap": ["vida"],
	"settlement": ["vida", "racha"],
	"second_opinion": ["vida"],
	"vest": ["escudo"],
	"immunity": ["escudo"],
	"fine_print": ["escudo"],
	"retaliation": ["escudo", "explosion"],
	"wide_sweep": ["area", "explosion"],
	"class_action": ["area"],
	"echo_wave": ["maletin", "area", "explosion"],
	"hot_ink": ["fuego"],
	"frozen_assets": ["hielo", "control"],
	"static_objection": ["rayo", "cadena"],
	"corrosive": ["marca"],
	"paper_storm": ["docs"],
	"twin_seal": ["sello"],
	"loaded_barrier": ["objecion", "explosion"],
	"boomerang_case": ["maletin"],
	"energy_zone": ["control", "habilidad"],
	"skill_power": ["docs", "habilidad"],
	"retainer": ["monedas"],
	"billable": ["monedas"],
	"appraisal": ["monedas"],
	"case_xp": ["monedas"],
	"closing_nova": ["racha", "explosion"],
	"streak_fury": ["racha"],
	"bloodlust": ["racha", "velocidad"],
	"last_word": ["racha", "explosion"],
	"bail_refund": ["racha", "habilidad"],
	"glass_cannon": ["riesgo"],
	"high_stakes": ["riesgo", "monedas"],
	"all_in": ["riesgo", "critico"],
	"blood_pact": ["riesgo", "habilidad"],
	"hostile_takeover": ["riesgo", "maletin"],
}

static func register() -> void:
	UpgradeDB.add_def("hit_heal", "Cobro por Contacto", "dmg", "heart", "Al golpear (12%): cura {v} de tu salud máxima", {"t:hit:heal_pct": 0.01}, "p", 10, ["vida"])
	UpgradeDB.add_def("hit_burn", "Chispa de Escritorio", "elem", "flame", "Al golpear (12%): incendia a los enemigos a 5 m ({v} daño/s)", {"t:hit:burn_area": 5.0}, "n", 12, ["fuego"])
	UpgradeDB.add_def("hit_chain", "Trámite Relámpago", "aoe", "bolt", "Al golpear (12%): rayo en cadena con {v} del daño del golpe", {"t:hit:chain": 0.3}, "p", 10, ["rayo", "cadena"])
	UpgradeDB.add_def("hit_coin", "Propina Agresiva", "eco", "coin", "Al golpear (12%): ganas +{v} moneda(s)", {"t:hit:coins": 1.0}, "i", 12, ["monedas"])
	UpgradeDB.add_def("hit_energy", "Tinta Cargada", "ctrl", "cup", "Al golpear (12%): recuperas {v} de Expediente", {"t:hit:energy": 4.0}, "n", 12, ["habilidad"])
	UpgradeDB.add_def("hit_rage", "Furia Burocrática", "dmg", "fire2", "Al golpear (12%): +{v} de daño durante 4 s (acumulable, máx. +120%)", {"t:hit:buff_dmg": 0.04}, "p", 10, ["ataque"])
	UpgradeDB.add_def("crit_nova", "Sentencia Explosiva", "crit", "burst", "Al crítico (40%): explosión en el objetivo con {v} del daño base del maletín", {"t:crit:nova_at": 0.5}, "p", 12, ["critico", "explosion"])
	UpgradeDB.add_def("crit_haste", "Crítico Contagioso", "crit", "fast", "Al crítico (40%): +{v} de velocidad de ataque 3 s (máx. +80%)", {"t:crit:buff_haste": 0.05}, "p", 10, ["critico", "ataque"])
	UpgradeDB.add_def("crit_heal", "Veredicto Curativo", "crit", "cross", "Al crítico (40%): cura {v} de tu salud máxima", {"t:crit:heal_pct": 0.01}, "p", 10, ["critico", "vida"])
	UpgradeDB.add_def("crit_energy", "Crítico Energético", "crit", "battery", "Al crítico (40%): recuperas {v} de Expediente", {"t:crit:energy": 4.0}, "n", 10, ["critico", "habilidad"])
	UpgradeDB.add_def("crit_mark", "Marca Crítica", "crit", "target", "Al crítico (40%): marca a los enemigos a 7 m durante {v} s", {"t:crit:mark_area": 1.5}, "n", 8, ["critico", "marca"])
	UpgradeDB.add_def("crit_coin", "Crítico Rentable", "crit", "coin", "Al crítico (40%): ganas +{v} moneda(s)", {"t:crit:coins": 1.0}, "i", 10, ["critico", "monedas"])
	UpgradeDB.add_def("crit_buff", "Racha Afortunada", "crit", "clover", "Al crítico (40%): +{v} de prob. de crítico durante 4 s (máx. +50%)", {"t:crit:buff_crit": 0.04}, "p", 8, ["critico"])
	UpgradeDB.add_def("kill_shield", "Botín de Escudo", "streak", "vest", "Al eliminar (30%): +{v} de escudo", {"t:kill:shield": 5.0}, "i", 12, ["escudo", "racha"])
	UpgradeDB.add_def("kill_rage", "Racha Sangrienta", "streak", "skull", "Al eliminar (30%): +{v} de daño durante 4 s (acumulable)", {"t:kill:buff_dmg": 0.03}, "p", 12, ["racha", "ataque"])
	UpgradeDB.add_def("kill_armor", "Piel de Hierro", "streak", "badge", "Al eliminar (30%): +{v} de reducción de daño 4 s (máx. +40%)", {"t:kill:buff_armor": 0.04}, "p", 8, ["racha", "escudo"])
	UpgradeDB.add_def("kill_stun", "Cierre Estruendoso", "streak", "mega", "Al eliminar (30%): aturde a los enemigos a 4.5 m durante {v} s", {"t:kill:stun_area": 0.35}, "s", 8, ["racha", "control"])
	UpgradeDB.add_def("kill_missile", "Archivo Vengativo", "streak", "page", "Al eliminar (30%): lanza {v} documento(s) teledirigido(s)", {"t:kill:missile": 1.0}, "i", 6, ["racha", "docs"], {"flat": true})
	UpgradeDB.add_def("kill_xp", "Casos Archivados", "streak", "star", "Al eliminar (30%): +{v} de experiencia", {"t:kill:xp": 5.0}, "i", 10, ["racha"])
	UpgradeDB.add_def("kill_cdr", "Eficiencia Procesal", "streak", "gear", "Al eliminar (30%): -{v} s a los enfriamientos de habilidades", {"t:kill:cdr": 0.3}, "s", 10, ["racha", "habilidad"])
	UpgradeDB.add_def("kill_nova2", "Pólvora de Caso Cerrado", "streak", "nova", "Al eliminar (30%): explosión alrededor de ti con {v} del daño base del maletín", {"t:kill:nova": 0.35}, "p", 12, ["racha", "explosion"])
	UpgradeDB.add_def("kill_haste", "Euforia de Bajas", "streak", "wind", "Al eliminar (30%): +{v} de velocidad de ataque 3 s", {"t:kill:buff_haste": 0.04}, "p", 10, ["racha", "ataque"])
	UpgradeDB.add_def("slam_push", "Golpe Estruendoso", "case", "mega", "Al impactar con el maletín lanzado (50%): empuja a los enemigos cercanos (fuerza {v})", {"t:slam:push": 8.0}, "n", 8, ["maletin", "control"])
	UpgradeDB.add_def("slam_pull", "Imán Jurídico", "case", "link", "Al impactar con el maletín lanzado (50%): atrae a los enemigos hacia ti (fuerza {v})", {"t:slam:pull": 6.0}, "n", 8, ["maletin", "control"])
	UpgradeDB.add_def("slam_missile", "Documento por Golpe", "case", "page", "Al impactar con el maletín lanzado (50%): lanza {v} documento(s) teledirigido(s)", {"t:slam:missile": 1.0}, "i", 6, ["maletin", "docs"], {"flat": true})
	UpgradeDB.add_def("slam_burn", "Maletín Incendiario", "case", "flame", "Al impactar con el maletín lanzado (50%): incendia a los enemigos a 5 m ({v} daño/s)", {"t:slam:burn_area": 6.0}, "n", 10, ["maletin", "fuego"])
	UpgradeDB.add_def("slam_shield", "Parada de Maletín", "case", "vest", "Al impactar con el maletín lanzado (50%): +{v} de escudo", {"t:slam:shield": 4.0}, "i", 12, ["maletin", "escudo"])
	UpgradeDB.add_def("slam_rage", "Impulso de Mazo", "case", "gavel", "Al impactar con el maletín lanzado (50%): +{v} de daño durante 4 s (acumulable)", {"t:slam:buff_dmg": 0.03}, "p", 12, ["maletin", "ataque"])
	UpgradeDB.add_def("slam_boom", "Maletín Gemelo", "case", "boomerang", "Al impactar con el maletín lanzado (50%): lanza un maletín bumerán ({v} del daño base)", {"t:slam:boomerang": 0.5}, "p", 10, ["maletin"])
	UpgradeDB.add_def("skill_heal", "Dividendos de Habilidad", "ctrl", "heart", "Al usar una habilidad: cura {v} de tu salud máxima", {"t:skill:heal_pct": 0.02}, "p", 8, ["habilidad", "vida"])
	UpgradeDB.add_def("skill_haste", "Pericia en Cadena", "ctrl", "fast", "Al usar una habilidad: +{v} de velocidad de ataque 3 s", {"t:skill:buff_haste": 0.08}, "p", 8, ["habilidad", "ataque"])
	UpgradeDB.add_def("skill_shield", "Escudo de Habilidad", "ctrl", "vest", "Al usar una habilidad: +{v} de escudo", {"t:skill:shield": 8.0}, "i", 10, ["habilidad", "escudo"])
	UpgradeDB.add_def("skill_nova", "Eco de Habilidad", "ctrl", "echo", "Al usar una habilidad: explosión a tu alrededor con {v} del daño base del maletín", {"t:skill:nova": 0.6}, "p", 10, ["habilidad", "explosion"])
	UpgradeDB.add_def("skill_inv", "Cláusula de Inmunidad Breve", "ctrl", "badge", "Al usar una habilidad: {v} s de invulnerabilidad", {"t:skill:invuln": 0.2}, "s", 5, ["habilidad", "escudo"])
	UpgradeDB.add_def("skill_coin", "Honorarios de Habilidad", "ctrl", "coin", "Al usar una habilidad: ganas +{v} monedas", {"t:skill:coins": 3.0}, "i", 8, ["habilidad", "monedas"])
	UpgradeDB.add_def("skill_freeze", "Escarcha Notarial", "ctrl", "snow", "Al usar una habilidad: congela a los enemigos a 4.5 m durante {v} s (no jefes)", {"t:skill:freeze_area": 0.8}, "s", 8, ["habilidad", "hielo"])
	UpgradeDB.add_def("dodge_nova", "Esquiva Explosiva", "speed", "burst", "Al esquivar: explosión a tu alrededor con {v} del daño base del maletín", {"t:dodge:nova": 0.5}, "p", 10, ["esquiva", "explosion"])
	UpgradeDB.add_def("dodge_chain", "Esquiva Eléctrica", "speed", "zap", "Al esquivar: rayo en cadena con {v} del daño base del maletín", {"t:dodge:chain": 0.5}, "p", 8, ["esquiva", "rayo"])
	UpgradeDB.add_def("dodge_rage", "Esquiva Furiosa", "speed", "fire2", "Al esquivar: +{v} de daño durante 4 s (acumulable)", {"t:dodge:buff_dmg": 0.06}, "p", 8, ["esquiva", "ataque"])
	UpgradeDB.add_def("dodge_heal", "Esquiva Reparadora", "speed", "cross", "Al esquivar: cura {v} de tu salud máxima", {"t:dodge:heal_pct": 0.01}, "p", 10, ["esquiva", "vida"])
	UpgradeDB.add_def("dodge_missile", "Documentos de Despiste", "speed", "paper", "Al esquivar: lanza {v} documentos teledirigidos", {"t:dodge:missile": 2.0}, "i", 6, ["esquiva", "docs"], {"flat": true})
	UpgradeDB.add_def("dodge_stun", "Esquiva Aturdidora", "speed", "mega", "Al esquivar: aturde a los enemigos a 4.5 m durante {v} s", {"t:dodge:stun_area": 0.4}, "s", 8, ["esquiva", "control"])
	UpgradeDB.add_def("dodge_energy", "Esquiva Cargada", "speed", "battery", "Al esquivar: recuperas {v} de Expediente", {"t:dodge:energy": 5.0}, "n", 10, ["esquiva", "habilidad"])
	UpgradeDB.add_def("dodge_haste", "Paso Fantasma", "speed", "wind", "Al esquivar: +{v} de velocidad de movimiento 3 s (máx. +60%)", {"t:dodge:buff_speed": 0.06}, "p", 8, ["esquiva", "velocidad"])
	UpgradeDB.add_def("hurt_nova", "Represalia Total", "shield", "thorn", "Al recibir daño (60%): explosión a tu alrededor con {v} del daño base del maletín", {"t:hurt:nova": 0.5}, "p", 10, ["escudo", "explosion"])
	UpgradeDB.add_def("hurt_armor", "Endurecimiento", "shield", "badge", "Al recibir daño (60%): +{v} de reducción de daño 4 s (máx. +40%)", {"t:hurt:buff_armor": 0.05}, "p", 8, ["escudo"])
	UpgradeDB.add_def("hurt_heal", "Curación Tras Golpe", "shield", "heart", "Al recibir daño (60%): recuperas {v} de salud", {"t:hurt:heal_flat": 3.0}, "i", 12, ["escudo", "vida"])
	UpgradeDB.add_def("hurt_stun", "Grito de Abogado", "shield", "mega", "Al recibir daño (60%): aturde a los enemigos a 4.5 m durante {v} s", {"t:hurt:stun_area": 0.5}, "s", 8, ["escudo", "control"])
	UpgradeDB.add_def("hurt_push", "Onda de Rebote", "shield", "echo", "Al recibir daño (60%): empuja a los enemigos cercanos (fuerza {v})", {"t:hurt:push": 9.0}, "n", 8, ["escudo", "control"])
	UpgradeDB.add_def("hurt_inv", "Segundo Aliento", "shield", "zzz", "Al recibir daño (60%): {v} s extra de invulnerabilidad", {"t:hurt:invuln": 0.25}, "s", 5, ["escudo"])
	UpgradeDB.add_def("hurt_haste", "Adrenalina de Defensa", "shield", "wind", "Al recibir daño (60%): +{v} de velocidad de movimiento 3 s", {"t:hurt:buff_speed": 0.08}, "p", 8, ["escudo", "velocidad"])
	UpgradeDB.add_def("sb_rage", "Escudo Vengativo", "shield", "glass", "Al romperse tu escudo: +{v} de daño durante 4 s", {"t:shield_break:buff_dmg": 0.15}, "p", 6, ["escudo", "ataque"])
	UpgradeDB.add_def("sb_stun", "Detonación de Escudo", "shield", "nova", "Al romperse tu escudo: aturde a los enemigos a 4.5 m durante {v} s", {"t:shield_break:stun_area": 0.8}, "s", 6, ["escudo", "control"])
	UpgradeDB.add_def("sb_heal", "Escudo Reparador", "shield", "heart", "Al romperse tu escudo: cura {v} de tu salud máxima", {"t:shield_break:heal_pct": 0.03}, "p", 6, ["escudo", "vida"])
	UpgradeDB.add_def("clear_shield", "Escudo de Cierre", "shield", "vest", "Al completar una arena: +{v} de escudo", {"t:arena_clear:shield": 30.0}, "i", 8, ["escudo"])
	UpgradeDB.add_def("clear_energy", "Tregua de Expediente", "ctrl", "cup", "Al completar una arena: recuperas {v} de Expediente", {"t:arena_clear:energy": 25.0}, "i", 6, ["habilidad"])
	UpgradeDB.add_def("clear_bonus", "Bonificación de Victoria", "eco", "coin", "Al completar una arena: +{v} monedas", {"t:arena_clear:coins": 8.0}, "i", 10, ["monedas"])
	UpgradeDB.add_def("start_rage", "Alegato de Apertura", "dmg", "mega", "Al empezar una arena: +{v} de daño durante 4 s", {"t:arena_start:buff_dmg": 0.15}, "p", 8, ["ataque"])
	UpgradeDB.add_def("start_shield", "Escudo Inicial", "shield", "vest", "Al empezar una arena: +{v} de escudo", {"t:arena_start:shield": 20.0}, "i", 8, ["escudo"])
	UpgradeDB.add_def("start_speed", "Salida Rápida", "speed", "shoe", "Al empezar una arena: +{v} de velocidad de movimiento 3 s", {"t:arena_start:buff_speed": 0.2}, "p", 6, ["velocidad"])
	UpgradeDB.add_def("lvl_heal", "Ascenso Saludable", "hp", "cross", "Al subir de nivel de caso: cura {v} de tu salud máxima", {"t:levelup:heal_pct": 0.1}, "p", 6, ["vida"])
	UpgradeDB.add_def("lvl_nova", "Celebración Explosiva", "aoe", "nova", "Al subir de nivel de caso: gran explosión con {v} del daño base del maletín", {"t:levelup:nova": 1.5}, "p", 6, ["explosion"])
	UpgradeDB.add_def("t5_shield", "Escudo Periódico", "shield", "vest", "Cada 5 s: +{v} de escudo", {"t:t5:shield": 8.0}, "i", 12, ["escudo"])
	UpgradeDB.add_def("t5_energy", "Goteo de Expediente", "ctrl", "cup", "Cada 5 s: recuperas {v} de Expediente", {"t:t5:energy": 8.0}, "n", 10, ["habilidad"])
	UpgradeDB.add_def("t8_nova", "Pulso Legal", "aoe", "ring", "Cada 8 s: explosión a tu alrededor con {v} del daño base del maletín", {"t:t8:nova": 0.8}, "p", 10, ["explosion"])
	UpgradeDB.add_def("t3_burn", "Brasas Constantes", "elem", "flame", "Cada 3 s: incendia a los enemigos a 5 m ({v} daño/s)", {"t:t3:burn_area": 4.0}, "n", 10, ["fuego"])
	UpgradeDB.add_def("t5_heal", "Pulso Sanador", "hp", "heart", "Cada 5 s: cura {v} de tu salud máxima", {"t:t5:heal_pct": 0.02}, "p", 10, ["vida"])
	UpgradeDB.add_def("t8_missile", "Archivo Automático", "docs", "page", "Cada 8 s: lanza {v} documentos teledirigidos", {"t:t8:missile": 2.0}, "i", 6, ["docs"], {"flat": true})
	UpgradeDB.add_def("t12_rage", "Segundo Aire de Guerra", "dmg", "fire2", "Cada 12 s: +{v} de daño durante 4 s", {"t:t12:buff_dmg": 0.3}, "p", 8, ["ataque"])
	UpgradeDB.add_def("t5_mark", "Marcado Periódico", "elem", "target", "Cada 5 s: marca a los enemigos a 7 m durante {v} s", {"t:t5:mark_area": 2.0}, "n", 8, ["marca"])
	UpgradeDB.add_def("t8_stun", "Pulso Aturdidor", "ctrl", "mega", "Cada 8 s: aturde a los enemigos a 4.5 m durante {v} s", {"t:t8:stun_area": 0.5}, "s", 8, ["control"])
	UpgradeDB.add_def("t5_slow", "Escarcha Periódica", "elem", "snow", "Cada 5 s: ralentiza a los enemigos a 6 m durante {v} s", {"t:t5:slow_area": 1.5}, "n", 8, ["hielo", "control"])
	UpgradeDB.add_def("t12_freeze", "Congelación Programada", "elem", "snow", "Cada 12 s: congela a los enemigos a 4.5 m durante {v} s (no jefes)", {"t:t12:freeze_area": 1.0}, "n", 6, ["hielo"])
	UpgradeDB.add_def("t3_chain", "Rayo Periódico", "aoe", "bolt", "Cada 3 s: rayo en cadena con {v} del daño base del maletín", {"t:t3:chain": 0.6}, "p", 10, ["rayo", "cadena"])
	UpgradeDB.add_def("t12_boom", "Maletín Automático", "case", "boomerang", "Cada 12 s: lanza un maletín bumerán ({v} del daño base)", {"t:t12:boomerang": 1.0}, "p", 8, ["maletin"])
	UpgradeDB.add_def("t8_cdr", "Reloj de Arena", "atk", "clock", "Cada 8 s: -{v} s a los enfriamientos de habilidades", {"t:t8:cdr": 2.0}, "n", 8, ["habilidad"])
	UpgradeDB.add_def("t5_coin", "Honorarios Periódicos", "eco", "coin", "Cada 5 s: ganas +{v} monedas", {"t:t5:coins": 2.0}, "i", 12, ["monedas"])
	UpgradeDB.add_def("c_burning", "Remate Ardiente", "elem", "flame", "+{v} de daño a enemigos en llamas", {"c:burning": 0.08}, "p", 15, ["fuego"])
	UpgradeDB.add_def("c_slowed", "Cazador de Rezagados", "elem", "snow", "+{v} de daño a enemigos ralentizados", {"c:slowed": 0.08}, "p", 15, ["hielo"])
	UpgradeDB.add_def("c_frozen", "Golpe de Hielo", "elem", "snow", "+{v} de daño a enemigos congelados", {"c:frozen": 0.08}, "p", 12, ["hielo"])
	UpgradeDB.add_def("c_marked", "Cobrador de Marcas", "elem", "drop", "+{v} de daño a enemigos marcados", {"c:marked": 0.08}, "p", 15, ["marca"])
	UpgradeDB.add_def("c_full", "Primer Golpe", "dmg", "skull", "+{v} de daño a enemigos con más del 85% de salud", {"c:full": 0.08}, "p", 15, ["ataque"])
	UpgradeDB.add_def("c_wounded", "Rematador", "dmg", "skull", "+{v} de daño a enemigos con menos del 50% de salud", {"c:wounded": 0.08}, "p", 15, ["ejecucion"])
	UpgradeDB.add_def("c_far", "Francotirador Legal", "docs", "target", "+{v} de daño a enemigos a más de 9 m", {"c:far": 0.08}, "p", 12, ["docs"])
	UpgradeDB.add_def("c_near", "Cuerpo a Cuerpo", "case", "sword", "+{v} de daño a enemigos a menos de 3.5 m", {"c:near": 0.08}, "p", 12, ["maletin"])
	UpgradeDB.add_def("c_crowd", "Demanda Masiva", "aoe", "crowd", "+{v} de daño cuando el golpe alcanza a 4 o más enemigos", {"c:crowd": 0.08}, "p", 12, ["area"])
	UpgradeDB.add_def("c_alone", "Duelo de Abogados", "dmg", "ringdot", "+{v} de daño cuando el golpe solo alcanza a un enemigo", {"c:alone": 0.08}, "p", 12, ["ataque"])
	UpgradeDB.add_def("c_lowhp", "Desesperación Legal", "risk", "heart", "+{v} de daño con menos del 40% de tu salud", {"c:lowhp": 0.08}, "p", 12, ["riesgo"])
	UpgradeDB.add_def("c_fullhp", "Impecable", "dmg", "gem", "+{v} de daño con más del 90% de tu salud", {"c:fullhp": 0.08}, "p", 12, ["ataque"])
	UpgradeDB.add_def("c_shield", "Escudo Ofensivo", "shield", "vest", "+{v} de daño mientras tengas escudo", {"c:shield": 0.08}, "p", 12, ["escudo"])
	UpgradeDB.add_def("c_barrier", "Objeción Agresiva", "ctrl", "barrier", "+{v} de daño mientras la Objeción esté activa", {"c:barrier": 0.08}, "p", 10, ["objecion"])
	UpgradeDB.add_def("c_hasted", "Ritmo de Tribunal", "atk", "fast", "+{v} de daño con prisa de ataque activa", {"c:hasted": 0.08}, "p", 12, ["ataque"])
	UpgradeDB.add_def("c_moving", "Alegato en Movimiento", "speed", "wind", "+{v} de daño mientras te mueves", {"c:moving": 0.08}, "p", 12, ["velocidad"])
	UpgradeDB.add_def("c_still", "Postura Firme", "dmg", "vest", "+{v} de daño mientras estás quieto", {"c:still": 0.08}, "p", 12, ["ataque"])
	UpgradeDB.add_def("c_air", "Golpe Aéreo", "speed", "wing", "+{v} de daño mientras estás en el aire", {"c:air": 0.08}, "p", 12, ["velocidad"])
	UpgradeDB.add_def("c_streak", "Racha Imparable", "streak", "fire2", "+{v} de daño con una racha de 5 o más bajas", {"c:streak": 0.08}, "p", 12, ["racha"])
	UpgradeDB.add_def("c_combo", "Combo de Maletín", "case", "link", "+{v} de daño con 6 o más golpes seguidos", {"c:combo": 0.08}, "p", 12, ["maletin"])
	UpgradeDB.add_def("c_energy", "Expediente Lleno", "ctrl", "cup", "+{v} de daño con el Expediente por encima del 80%", {"c:energy": 0.08}, "p", 12, ["habilidad"])
	UpgradeDB.add_def("c_rich", "Cliente Adinerado", "eco", "coin", "+{v} de daño con 150 o más monedas", {"c:rich": 0.08}, "p", 12, ["monedas"])
	UpgradeDB.add_def("c_boss", "Especialista en Jefes", "dmg", "crown", "+{v} de daño en arenas de jefe", {"c:boss_arena": 0.08}, "p", 10, ["ejecucion"])
	UpgradeDB.add_def("s_slam", "Arte del Maletín", "case", "sword", "+{v} de daño del maletín lanzado", {"s:slam": 0.08}, "p", 15, ["maletin"])
	UpgradeDB.add_def("s_docs", "Tinta Reforzada", "docs", "page", "+{v} de daño de los documentos teledirigidos", {"s:docs": 0.08}, "p", 15, ["docs"])
	UpgradeDB.add_def("s_echo", "Resonancia", "aoe", "echo", "+{v} de daño de la Onda Residual", {"s:echo": 0.08}, "p", 12, ["maletin", "area"])
	UpgradeDB.add_def("s_boom", "Maletín Afilado", "case", "boomerang", "+{v} de daño de los maletines bumerán", {"s:boomerang": 0.08}, "p", 12, ["maletin"])
	UpgradeDB.add_def("s_nova", "Carga de Cierre", "aoe", "nova", "+{v} de daño de explosiones de mejoras (descargas, esquivas…)", {"s:nova": 0.08}, "p", 15, ["explosion"])
	UpgradeDB.add_def("s_critexp", "Carga Crítica", "crit", "burst", "+{v} de daño de las explosiones críticas", {"s:crit_explosion": 0.08}, "p", 12, ["critico", "explosion"])
	UpgradeDB.add_def("s_chain", "Alto Voltaje", "aoe", "zap", "+{v} de daño de los rayos en cadena", {"s:chain": 0.08}, "p", 12, ["rayo", "cadena"])
	UpgradeDB.add_def("s_thorns", "Espinas Letales", "shield", "thorn", "+{v} de daño de Represalia", {"s:thorns": 0.08}, "p", 12, ["escudo", "explosion"])
	UpgradeDB.add_def("s_trail", "Estela Ardiente", "speed", "trail", "+{v} de daño de la estela de esquiva", {"s:trail": 0.08}, "p", 12, ["esquiva"])
	UpgradeDB.add_def("s_seal", "Sello Potente", "ctrl", "seal", "+{v} de daño del Sello Mágico", {"s:seal": 0.08}, "p", 12, ["sello"])
	UpgradeDB.add_def("s_barrier", "Objeción Contundente", "ctrl", "barrier", "+{v} de daño de la onda de la Objeción", {"s:barrier": 0.08}, "p", 12, ["objecion"])
	UpgradeDB.add_def("hp_regen_pct", "Régimen Saludable", "hp", "zzz", "Regeneras {v} de tu salud máxima por segundo", {"hp_regen_pct": 0.004}, "q", 12, ["vida"], {})
	UpgradeDB.add_def("heal_pow", "Botiquín Notarial", "hp", "cross", "Toda curación que recibes +{v}", {"heal_pow": 0.08}, "p", 12, ["vida"], {})
	UpgradeDB.add_def("armor_low", "Último Recurso", "shield", "badge", "Con menos del 35% de salud: reducción de daño +{v}", {"armor_low": 0.04}, "p", 7, ["escudo"], {})
	UpgradeDB.add_def("iframe_add", "Esquive Elegante", "speed", "wing", "Invulnerabilidad al esquivar +{v} s", {"iframe_add": 0.03}, "s", 8, ["esquiva"], {})
	UpgradeDB.add_def("dodge_speed", "Zapatillas de Tribunal", "speed", "shoe", "Velocidad de la esquiva +{v}", {"dodge_speed": 0.06}, "p", 10, ["esquiva", "velocidad"], {})
	UpgradeDB.add_def("hurt_iframe_add", "Piel de Abogado", "shield", "badge", "Tras recibir un golpe, {v} s más de invulnerabilidad", {"hurt_iframe_add": 0.05}, "s", 6, ["escudo"], {})
	UpgradeDB.add_def("shield_regen_pct", "Recarga de Escudo", "shield", "battery", "Tu escudo se regenera +{v} más rápido", {"shield_regen_pct": 0.12}, "p", 10, ["escudo"], {})
	UpgradeDB.add_def("shield_delay_cut", "Escudo Impaciente", "shield", "clock", "El escudo empieza a regenerarse {v} antes", {"shield_delay_cut": 0.08}, "p", 6, ["escudo"], {})
	UpgradeDB.add_def("jump_pow", "Resorte Legal", "speed", "wing", "Altura de salto +{v}", {"jump_pow": 0.05}, "p", 8, ["velocidad"], {})
	UpgradeDB.add_def("max_hp_flat", "Plus de Antigüedad", "hp", "heart", "Salud máxima +{v}", {"max_hp_flat": 12.0}, "i", 15, ["vida"], {})
	UpgradeDB.add_def("lifesteal", "Honorarios de Sangre", "hp", "skull", "Recuperas {v} del daño que infliges", {"lifesteal": 0.01}, "p", 10, ["vida", "ataque"], {})
	UpgradeDB.add_def("magnet", "Imán de Honorarios", "eco", "coin", "Radio de recogida de monedas +{v} m", {"magnet": 1.5}, "n", 8, ["monedas"], {})
	UpgradeDB.add_def("cd_docs", "Archivo Rápido", "docs", "page", "Enfriamiento de los Documentos -{v}", {"cd_docs": 0.05}, "p", 10, ["docs", "habilidad"], {})
	UpgradeDB.add_def("cd_seal", "Sello Veloz", "ctrl", "seal", "Enfriamiento del Sello Mágico -{v}", {"cd_seal": 0.05}, "p", 10, ["sello", "habilidad"], {})
	UpgradeDB.add_def("cd_barrier", "Objeción Rápida", "ctrl", "barrier", "Enfriamiento de la Objeción -{v}", {"cd_barrier": 0.05}, "p", 10, ["objecion", "habilidad"], {})
	UpgradeDB.add_def("cd_slam", "Maletín Ligero", "case", "sword", "Enfriamiento entre lanzamientos del maletín -{v}", {"cd_slam": 0.04}, "p", 10, ["maletin", "ataque"], {})
	UpgradeDB.add_def("docs_pierce", "Documentos Perforantes", "docs", "page", "Los documentos atraviesan {v} enemigo(s) más", {"docs_pierce": 1.0}, "i", 4, ["docs"], {"flat": true})
	UpgradeDB.add_def("docs_speed", "Papel Aerodinámico", "docs", "paper", "Velocidad de los documentos +{v}", {"docs_speed": 0.08}, "p", 10, ["docs"], {})
	UpgradeDB.add_def("docs_turn", "Teledirección Mejorada", "docs", "target", "Los documentos giran más rápido hacia su objetivo (+{v})", {"docs_turn": 1.5}, "n", 6, ["docs"], {"req": {"arena": 3}})
	UpgradeDB.add_def("seal_radius", "Sello Gigante", "ctrl", "seal", "Radio del Sello Mágico +{v}", {"seal_radius": 0.1}, "p", 12, ["sello", "area"], {})
	UpgradeDB.add_def("seal_time", "Sello Duradero", "ctrl", "seal", "Duración del Sello Mágico +{v}", {"seal_time": 0.12}, "p", 10, ["sello"], {})
	UpgradeDB.add_def("barrier_hp_pct", "Objeción Blindada", "ctrl", "barrier", "Resistencia de la Objeción +{v}", {"barrier_hp_pct": 0.12}, "p", 12, ["objecion", "escudo"], {})
	UpgradeDB.add_def("barrier_time", "Objeción Prolongada", "ctrl", "barrier", "Duración de la Objeción +{v}", {"barrier_time": 0.1}, "p", 10, ["objecion"], {})
	UpgradeDB.add_def("energy_max_add", "Más Expediente", "ctrl", "cup", "Expediente máximo +{v}", {"energy_max_add": 10.0}, "i", 10, ["habilidad"], {})
	UpgradeDB.add_def("energy_regen_pct", "Expediente Fluido", "ctrl", "cup", "Regeneración de Expediente +{v}", {"energy_regen_pct": 0.08}, "p", 12, ["habilidad"], {})
	UpgradeDB.add_def("cost_cut", "Tarifa Reducida", "ctrl", "coin", "Coste de las habilidades -{v}", {"cost_cut": 0.04}, "p", 10, ["habilidad"], {})
	UpgradeDB.add_def("slam_radius", "Maletín Extra Largo", "case", "sword", "Alcance del maletín lanzado +{v} (y algo de tamaño)", {"slam_radius": 0.06}, "p", 15, ["maletin", "area"], {})
	UpgradeDB.add_def("slam_arc", "Barrido de Arco", "case", "ring", "El maletín describe una curva más abierta (+{v}° de arco)", {"slam_arc": 8.0}, "i", 10, ["maletin", "area"], {"req": {"equip_any": ["gavel", "quill"]}})
	UpgradeDB.add_def("slam_knock", "Golpe Contundente", "case", "mega", "Empuje del maletín lanzado +{v}", {"slam_knock": 0.1}, "p", 10, ["maletin", "control"], {"req": {"equip_any": ["gavel", "case"]}})
	UpgradeDB.add_def("slam_double", "Doble Golpe", "case", "gavel", "{v} de prob. de lanzar un maletín extra con su propio recorrido", {"slam_double": 0.05}, "p", 10, ["maletin"], {})
	UpgradeDB.add_def("knock_pow", "Empuje Procesal", "ctrl", "wind", "Todo tu empuje +{v}", {"knock_pow": 0.1}, "p", 10, ["control"], {})
	UpgradeDB.add_def("stagger_add", "Aturdimiento Legal", "ctrl", "zzz", "Tus golpes aturden +{v} s más", {"stagger_add": 0.08}, "s", 8, ["control"], {})
	UpgradeDB.add_def("exec_thr", "Umbral de Ejecución", "dmg", "skull", "El bonus de ejecución se activa con {v} más de salud enemiga", {"exec_thr": 0.03}, "p", 8, ["ejecucion"], {"req": {"owns": ["closing_arg"]}})
	UpgradeDB.add_def("explosion_pow", "Pólvora Legal", "aoe", "burst", "Daño de todas tus explosiones +{v}", {"explosion_pow": 0.08}, "p", 15, ["explosion"], {})
	UpgradeDB.add_def("explo_rad", "Radio de Estallido", "aoe", "ring", "Radio de todas tus explosiones +{v}", {"explo_rad": 0.06}, "p", 15, ["explosion", "area"], {})
	UpgradeDB.add_def("burn_dur", "Combustión Lenta", "elem", "flame", "Las quemaduras duran +{v}", {"burn_dur": 0.15}, "p", 8, ["fuego"], {})
	UpgradeDB.add_def("slow_amt", "Escarcha Densa", "elem", "snow", "Tus ralentizaciones reducen +{v} más la velocidad enemiga", {"slow_amt": 0.04}, "p", 8, ["hielo"], {})
	UpgradeDB.add_def("slow_dur", "Frío Prolongado", "elem", "snow", "Las ralentizaciones duran +{v}", {"slow_dur": 0.15}, "p", 8, ["hielo"], {})
	UpgradeDB.add_def("freeze_dur", "Hielo Persistente", "elem", "snow", "Las congelaciones duran +{v}", {"freeze_dur": 0.1}, "p", 6, ["hielo"], {})
	UpgradeDB.add_def("mark_amp", "Marca Profunda", "elem", "drop", "Los enemigos marcados reciben +{v} de daño extra", {"mark_amp": 0.04}, "p", 10, ["marca"], {})
	UpgradeDB.add_def("mark_dur", "Marca Duradera", "elem", "drop", "Las marcas duran +{v}", {"mark_dur": 0.15}, "p", 8, ["marca"], {})
	UpgradeDB.add_def("chain_dmg", "Rayo Concentrado", "elem", "zap", "El rayo en cadena hace +{v} del daño del golpe", {"chain_dmg": 0.04}, "p", 10, ["rayo", "cadena"], {})
	UpgradeDB.add_def("burn_spread", "Contagio Ardiente", "elem", "fire2", "{v} de prob. de que un enemigo en llamas propague el fuego al morir", {"burn_spread": 0.1}, "p", 8, ["fuego"], {})
	UpgradeDB.add_def("burn_dps2", "Gasolina Notarial", "elem", "flame", "Daño por segundo de tus quemaduras de golpe +{v}", {"burn_dps": 4.0}, "n", 10, ["fuego"], {"req": {"owns": ["hot_ink"]}})
	UpgradeDB.add_def("chest_cards", "Cofre Generoso", "eco", "gem", "Los cofres ofrecen +{v} carta más", {"chest_cards": 1.0}, "i", 2, ["monedas"], {"flat": true, "rarities": [2, 3], "req": {"arena": 5}})
	UpgradeDB.add_def("reroll_cut", "Relanzamiento Barato", "eco", "dice", "El relanzamiento de cartas cuesta -{v}", {"reroll_cut": 0.1}, "p", 6, ["monedas"], {})
	UpgradeDB.add_def("skip_bonus", "Descarte Rentable", "eco", "coin", "Descartar una carta da +{v} de monedas", {"skip_bonus": 0.25}, "p", 8, ["monedas"], {})
	UpgradeDB.add_def("sell_bonus", "Buen Negociante", "eco", "handshake", "Las mejoras se venden por +{v}", {"sell_bonus": 0.1}, "p", 8, ["monedas"], {})
	UpgradeDB.add_def("clear_coins", "Bonificación de Cierre", "eco", "coin", "Al completar una arena: +{v} monedas", {"clear_coins": 4.0}, "i", 10, ["monedas"], {})
	UpgradeDB.add_def("interest", "Interés Compuesto", "eco", "gem", "Al completar una arena: ganas {v} de tus monedas (máx. 40)", {"interest": 0.01}, "p", 8, ["monedas"], {})
	UpgradeDB.add_def("kill_coins", "Soborno", "eco", "coin", "{v} de prob. de ganar +1 moneda al eliminar", {"kill_coins": 0.04}, "p", 10, ["monedas"], {})
	UpgradeDB.add_def("xp_kill", "Aprendizaje de Campo", "eco", "star", "+{v} de experiencia por baja", {"xp_kill": 0.4}, "n", 10, ["monedas"], {})
	UpgradeDB.add_def("epic_luck", "Fortuna Procesal", "eco", "clover", "Más probabilidad de cartas épicas y legendarias (+{v})", {"epic_luck": 0.15}, "p", 10, ["monedas"], {})
	UpgradeDB.add_def("boss_coins", "Botín de Jefe", "eco", "crown", "Los jefes sueltan +{v} de monedas", {"boss_coins": 0.2}, "p", 6, ["monedas"], {})
	UpgradeDB.add_def("amp_fuego", "Catalizador de Fuego", "syn", "flame", "+{v} de daño total por cada OTRA mejora de «fuego» que tengas, multiplicado por su nivel", {"amp_fuego": 0.025}, "q", 5, ["sinergia"], {"amp": {"tag": "fuego", "stat": "more_dmg_x", "per": 0.025}, "req": {"tag": {"fuego": 2}}})
	UpgradeDB.add_def("amp_hielo", "Catalizador de Hielo", "syn", "snow", "+{v} de daño total por cada OTRA mejora de «hielo» que tengas, multiplicado por su nivel", {"amp_hielo": 0.025}, "q", 5, ["sinergia"], {"amp": {"tag": "hielo", "stat": "more_dmg_x", "per": 0.025}, "req": {"tag": {"hielo": 2}}})
	UpgradeDB.add_def("amp_rayo", "Catalizador de Rayo", "syn", "zap", "+{v} de daño total por cada OTRA mejora de «rayo» que tengas, multiplicado por su nivel", {"amp_rayo": 0.025}, "q", 5, ["sinergia"], {"amp": {"tag": "rayo", "stat": "more_dmg_x", "per": 0.025}, "req": {"tag": {"rayo": 2}}})
	UpgradeDB.add_def("amp_marca", "Catalizador de Marcas", "syn", "drop", "+{v} de daño total por cada OTRA mejora de «marca» que tengas, multiplicado por su nivel", {"amp_marca": 0.025}, "q", 5, ["sinergia"], {"amp": {"tag": "marca", "stat": "more_dmg_x", "per": 0.025}, "req": {"tag": {"marca": 2}}})
	UpgradeDB.add_def("amp_critico", "Catalizador Crítico", "syn", "eye", "+{v} de daño crítico por cada OTRA mejora de «critico» que tengas, multiplicado por su nivel", {"amp_critico": 0.05}, "q", 5, ["sinergia"], {"amp": {"tag": "critico", "stat": "crit_mult", "per": 0.05}, "req": {"tag": {"critico": 2}}})
	UpgradeDB.add_def("amp_explosion", "Catalizador Explosivo", "syn", "burst", "+{v} de daño de explosiones por cada OTRA mejora de «explosion» que tengas, multiplicado por su nivel", {"amp_explosion": 0.04}, "q", 5, ["sinergia"], {"amp": {"tag": "explosion", "stat": "explosion_pow", "per": 0.04}, "req": {"tag": {"explosion": 2}}})
	UpgradeDB.add_def("amp_docs", "Catalizador de Papel", "syn", "page", "+{v} de daño de habilidades por cada OTRA mejora de «docs» que tengas, multiplicado por su nivel", {"amp_docs": 0.03}, "q", 5, ["sinergia"], {"amp": {"tag": "docs", "stat": "skill_dmg_x", "per": 0.03}, "req": {"tag": {"docs": 2}}})
	UpgradeDB.add_def("amp_maletin", "Catalizador de Maletín", "syn", "sword", "+{v} de daño total por cada OTRA mejora de «maletin» que tengas, multiplicado por su nivel", {"amp_maletin": 0.025}, "q", 5, ["sinergia"], {"amp": {"tag": "maletin", "stat": "more_dmg_x", "per": 0.025}, "req": {"tag": {"maletin": 2}}})
	UpgradeDB.add_def("amp_escudo", "Catalizador de Escudo", "syn", "vest", "+{v} de reducción de daño por cada OTRA mejora de «escudo» que tengas, multiplicado por su nivel", {"amp_escudo": 0.01}, "q", 5, ["sinergia"], {"amp": {"tag": "escudo", "stat": "armor", "per": 0.01}, "req": {"tag": {"escudo": 2}}})
	UpgradeDB.add_def("amp_velocidad", "Catalizador de Velocidad", "syn", "wind", "+{v} de velocidad de movimiento por cada OTRA mejora de «velocidad» que tengas, multiplicado por su nivel", {"amp_velocidad": 0.015}, "q", 5, ["sinergia"], {"amp": {"tag": "velocidad", "stat": "move_speed", "per": 0.015}, "req": {"tag": {"velocidad": 2}}})
	UpgradeDB.add_def("amp_control", "Catalizador de Control", "syn", "mega", "+{v} de empuje por cada OTRA mejora de «control» que tengas, multiplicado por su nivel", {"amp_control": 0.03}, "q", 5, ["sinergia"], {"amp": {"tag": "control", "stat": "knock_pow", "per": 0.03}, "req": {"tag": {"control": 2}}})
	UpgradeDB.add_def("amp_monedas", "Catalizador de Honorarios", "syn", "coin", "+{v} de monedas ganadas por cada OTRA mejora de «monedas» que tengas, multiplicado por su nivel", {"amp_monedas": 0.03}, "q", 5, ["sinergia"], {"amp": {"tag": "monedas", "stat": "coin_pct", "per": 0.03}, "req": {"tag": {"monedas": 2}}})
	UpgradeDB.add_def("amp_vida", "Catalizador de Vitalidad", "syn", "heart", "+{v} de salud máxima por cada OTRA mejora de «vida» que tengas, multiplicado por su nivel", {"amp_vida": 0.025}, "q", 5, ["sinergia"], {"amp": {"tag": "vida", "stat": "max_hp_pct", "per": 0.025}, "req": {"tag": {"vida": 2}}})
	UpgradeDB.add_def("amp_esquiva", "Catalizador de Esquiva", "syn", "trail", "+{v} de reducción del enfriamiento de esquiva por cada OTRA mejora de «esquiva» que tengas, multiplicado por su nivel", {"amp_esquiva": 0.015}, "q", 5, ["sinergia"], {"amp": {"tag": "esquiva", "stat": "dodge_cd", "per": 0.015}, "req": {"tag": {"esquiva": 2}}})
	UpgradeDB.add_def("leg_living_law", "Jurisprudencia Viviente", "legend", "book", "Daño total ×{v} por cada OTRA mejora distinta que tengas en tu build", {"amp_all": 0.015}, "q", 1, ["legendaria"], {"rarities": [3], "amp": {"tag": "*", "stat": "more_dmg_x", "per": 0.015}, "req": {"arena": 8}})
	UpgradeDB.add_def("leg_eternal", "Contrato Eterno", "legend", "handshake", "Regeneras {v} de tu salud máxima por segundo y recibes {w} menos de daño", {"hp_regen_pct": 0.01, "armor": 0.06}, "pp", 1, ["legendaria", "vida"], {"rarities": [3], "req": {"arena": 8}})
	UpgradeDB.add_def("leg_storm", "Tormenta Legal", "legend", "bolt", "Cada 3 s y al eliminar (30%): rayo en cadena ({v} y {w} del daño base del maletín)", {"t:t3:chain": 0.8, "t:kill:chain": 0.5}, "pp", 2, ["legendaria", "rayo"], {"rarities": [3], "req": {"arena": 8}})
	UpgradeDB.add_def("leg_attorney", "Fiscal General", "legend", "crown", "+{v} de daño a élites y jefes y +{w} en arenas de jefe", {"boss_dmg": 0.6, "c:boss_arena": 0.4}, "pp", 2, ["legendaria", "ejecucion"], {"rarities": [3], "req": {"arena": 10}})
	UpgradeDB.add_def("leg_countdown", "Cuenta Atrás Notarial", "legend", "clock", "Cada 8 s: gran explosión ({v} del daño base) y lanzamiento de maletín {w} más rápido", {"t:t8:nova": 2.0, "cd_slam": 0.1}, "pp", 2, ["legendaria", "explosion"], {"rarities": [3], "req": {"arena": 8}})
	UpgradeDB.add_def("leg_library", "Biblioteca Infinita", "legend", "paper", "+{v} documentos y atraviesan {w} enemigo más", {"docs_extra": 4.0, "docs_pierce": 1.0}, "ii", 1, ["legendaria", "docs"], {"rarities": [3], "req": {"arena": 10}, "flat": true})
	UpgradeDB.add_def("leg_parachute", "Paracaídas Dorado", "legend", "badge", "Al recibir daño (60%): cura {v} de tu salud máxima y {w} s de invulnerabilidad", {"t:hurt:heal_pct": 0.05, "t:hurt:invuln": 0.5}, "ps", 2, ["legendaria", "escudo"], {"rarities": [3], "req": {"arena": 10}})
	UpgradeDB.add_def("leg_blood_money", "Dinero Sucio", "legend", "coin", "Recuperas {v} del daño infligido y {w} de prob. de +1 moneda por baja", {"lifesteal": 0.03, "kill_coins": 0.1}, "pp", 2, ["legendaria", "monedas"], {"rarities": [3], "req": {"arena": 8}})
	UpgradeDB.add_def("leg_hostile_merge", "Fusión Hostil", "legend", "gavel", "+{v} de daño del maletín y {w} de prob. de repetir el golpe", {"s:slam": 0.5, "slam_double": 0.15}, "pp", 2, ["legendaria", "maletin"], {"rarities": [3], "req": {"arena": 10, "equip_any": ["case", "gavel"]}})
	UpgradeDB.add_def("leg_endless", "Alegato Interminable", "legend", "mega", "Al impactar con el maletín lanzado (50%): +{v} de daño 4 s, y +{w} de daño con combo alto", {"t:slam:buff_dmg": 0.15, "c:combo": 0.4}, "pp", 2, ["legendaria", "maletin"], {"rarities": [3], "req": {"arena": 8}})
