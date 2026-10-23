class_name BiomeDB
extends RefCounted
## Definición DATA-DRIVEN de los biomas. Cada bioma cambia SOLO tras derrotar a un jefe de zona
## (bioma = ciclo de jefes: Scaling.cycle_of(arena) % COUNT). Todo lo que distingue a una región vive aquí:
## paleta, cielo/niebla/luz, estilo y amplitud del terreno, materiales del suelo, objetos del escenario,
## arquitectura del fondo, tienda/cofre/portal y transición. Los generadores (Terrain, BiomeScenery,
## BiomeProps) leen estos datos; añadir un bioma = añadir una entrada + su función de fondo.

const COUNT := 6

const BIOMES := [
	{ # ------------------------------------------------------------------ 0
		"id": "urban", "name": "Distrito en Ruinas", "region": "Bufete Abandonado · Calles en ruinas",
		"floor_a": Color(0.2, 0.21, 0.24), "floor_b": Color(0.17, 0.18, 0.2),
		"g_main": Color(0.19, 0.2, 0.23), "g_alt": Color(0.43, 0.42, 0.4), "g_detail": Color(0.3, 0.42, 0.22),
		"g_path": Color(0.5, 0.49, 0.46), "ground": Color(0.13, 0.14, 0.16), "floor_line": Color(0.95, 0.78, 0.2),
		"wall": Color(0.5, 0.5, 0.52), "wall_accent": Color(0.95, 0.55, 0.15), "wall_style": "urban",
		"building": Color(0.34, 0.31, 0.3), "window": Color(1.0, 0.82, 0.45), "towers": 16,
		"wood": Color(0.5, 0.36, 0.22), "metal": Color(0.45, 0.48, 0.52),
		"paints": [Color(0.5, 0.2, 0.16), Color(0.3, 0.4, 0.5), Color(0.72, 0.58, 0.2), Color(0.6, 0.6, 0.58)],
		"marble": Color(0.82, 0.8, 0.76), "platform": Color(0.5, 0.5, 0.52),
		"sky": Color(0.62, 0.68, 0.76), "sky_top": Color(0.28, 0.42, 0.66), "sky_horizon": Color(0.93, 0.74, 0.58),
		"fog": Color(0.82, 0.74, 0.68), "fog_density": 0.0052, "ambient": Color(0.66, 0.68, 0.74), "ambient_energy": 0.85,
		"sun": Color(1.0, 0.84, 0.66), "sun_energy": 1.1, "sun_pitch": -34.0,
		"kinds": ["car", "car", "barrier", "dumpster", "debris", "wall_piece", "lamp", "sign", "planter", "rubble", "bus_stop", "tree_city"],
		"lane_kinds": "car,barrier,bus_stop", "extra_props": 6,
		"terrain": "urban", "amp": 0.6, "freq": 0.05, "flat_r": 8.0,
		"accent": Color(1.0, 0.62, 0.2), "portal_frame": Color(0.4, 0.42, 0.46), "portal_tint": Color(1.0, 0.65, 0.25),
		"shop_name": "FURGONETA DEL NOTARIO", "shop_kind": "truck", "chest_kind": "slab",
		"trans": "fade", "trans_color": Color(0.05, 0.05, 0.08),
	},
	{ # ------------------------------------------------------------------ 1
		"id": "forest", "name": "Bosque Judicial Encantado", "region": "Robles de la Jurisprudencia",
		"floor_a": Color(0.2, 0.3, 0.16), "floor_b": Color(0.17, 0.26, 0.14),
		"g_main": Color(0.2, 0.34, 0.17), "g_alt": Color(0.28, 0.4, 0.2), "g_detail": Color(0.42, 0.3, 0.18),
		"g_path": Color(0.5, 0.4, 0.26), "ground": Color(0.08, 0.14, 0.09), "floor_line": Color(0.5, 0.4, 0.26),
		"wall": Color(0.35, 0.27, 0.18), "wall_accent": Color(0.55, 0.95, 0.6), "wall_style": "hedge",
		"building": Color(0.12, 0.22, 0.14), "window": Color(0.7, 1.0, 0.8), "towers": 14,
		"wood": Color(0.4, 0.27, 0.15), "metal": Color(0.4, 0.45, 0.42),
		"paints": [Color(0.3, 0.6, 0.4), Color(0.6, 0.45, 0.2), Color(0.55, 0.7, 0.9)],
		"marble": Color(0.75, 0.8, 0.74), "platform": Color(0.4, 0.38, 0.32),
		"sky": Color(0.4, 0.62, 0.55), "sky_top": Color(0.18, 0.4, 0.42), "sky_horizon": Color(0.72, 0.88, 0.7),
		"fog": Color(0.5, 0.7, 0.58), "fog_density": 0.013, "ambient": Color(0.55, 0.72, 0.62), "ambient_energy": 0.85,
		"sun": Color(1.0, 0.95, 0.7), "sun_energy": 1.15, "sun_pitch": -58.0,
		"kinds": ["tree", "tree", "tree_big", "rock", "rock", "stump", "bush", "bush", "mushrooms", "log"],
		"terrain": "forest", "amp": 1.0, "freq": 0.055, "flat_r": 9.0,
		"accent": Color(0.55, 1.0, 0.65), "portal_frame": Color(0.32, 0.26, 0.18), "portal_tint": Color(0.45, 1.0, 0.65),
		"shop_name": "CABAÑA DEL ESCRIBANO", "shop_kind": "hut", "chest_kind": "roots",
		"trans": "flash", "trans_color": Color(0.7, 1.0, 0.8),
	},
	{ # ------------------------------------------------------------------ 2
		"id": "industrial", "name": "Complejo Industrial", "region": "Fábrica de Sentencias",
		"floor_a": Color(0.24, 0.25, 0.27), "floor_b": Color(0.2, 0.21, 0.23),
		"g_main": Color(0.26, 0.27, 0.29), "g_alt": Color(0.36, 0.37, 0.39), "g_detail": Color(0.5, 0.36, 0.2),
		"g_path": Color(0.55, 0.5, 0.2), "ground": Color(0.1, 0.1, 0.12), "floor_line": Color(0.95, 0.75, 0.1),
		"wall": Color(0.38, 0.4, 0.44), "wall_accent": Color(1.0, 0.55, 0.1), "wall_style": "rail",
		"building": Color(0.3, 0.27, 0.26), "window": Color(1.0, 0.6, 0.2), "towers": 14,
		"wood": Color(0.4, 0.3, 0.2), "metal": Color(0.5, 0.52, 0.56),
		"paints": [Color(0.85, 0.5, 0.1), Color(0.7, 0.18, 0.15), Color(0.2, 0.4, 0.6)],
		"marble": Color(0.7, 0.7, 0.7), "platform": Color(0.38, 0.4, 0.44),
		"sky": Color(0.5, 0.42, 0.4), "sky_top": Color(0.28, 0.27, 0.34), "sky_horizon": Color(0.9, 0.55, 0.32),
		"fog": Color(0.62, 0.45, 0.36), "fog_density": 0.0115, "ambient": Color(0.62, 0.58, 0.6), "ambient_energy": 0.8,
		"sun": Color(1.0, 0.7, 0.45), "sun_energy": 1.05, "sun_pitch": -32.0,
		"kinds": ["tank", "pipes", "crate_big", "container", "barrier", "machine", "pallets", "pylon"],
		"terrain": "industrial", "amp": 0.75, "freq": 0.05, "flat_r": 9.0,
		"accent": Color(1.0, 0.6, 0.15), "portal_frame": Color(0.35, 0.36, 0.4), "portal_tint": Color(1.0, 0.55, 0.15),
		"shop_name": "ALMACÉN DE SUMINISTROS", "shop_kind": "container", "chest_kind": "crate",
		"trans": "bars", "trans_color": Color(0.9, 0.5, 0.1),
	},
	{ # ------------------------------------------------------------------ 3
		"id": "desert", "name": "Desierto de Expedientes", "region": "Dunas del Archivo Olvidado",
		"floor_a": Color(0.8, 0.62, 0.38), "floor_b": Color(0.74, 0.56, 0.34),
		"g_main": Color(0.7, 0.52, 0.32), "g_alt": Color(0.8, 0.62, 0.4), "g_detail": Color(0.5, 0.33, 0.22),
		"g_path": Color(0.68, 0.5, 0.32), "ground": Color(0.7, 0.52, 0.32), "floor_line": Color(0.6, 0.45, 0.3),
		"wall": Color(0.62, 0.42, 0.28), "wall_accent": Color(0.95, 0.8, 0.45), "wall_style": "rocks",
		"building": Color(0.72, 0.5, 0.34), "window": Color(1.0, 0.9, 0.6), "towers": 10,
		"wood": Color(0.5, 0.35, 0.2), "metal": Color(0.55, 0.5, 0.45),
		"paints": [Color(0.8, 0.45, 0.2), Color(0.6, 0.3, 0.2), Color(0.9, 0.75, 0.4)],
		"marble": Color(0.9, 0.82, 0.66), "platform": Color(0.7, 0.55, 0.38),
		"sky": Color(0.95, 0.78, 0.55), "sky_top": Color(0.4, 0.62, 0.85), "sky_horizon": Color(1.0, 0.82, 0.58),
		"fog": Color(0.92, 0.72, 0.5), "fog_density": 0.0085, "ambient": Color(0.85, 0.72, 0.62), "ambient_energy": 0.62,
		"sun": Color(1.0, 0.84, 0.58), "sun_energy": 1.3, "sun_pitch": -38.0,
		"kinds": ["rock_red", "rock_red", "cactus", "ruin_pillar", "archive_stack", "bones", "dead_tree", "buried_arch"],
		"terrain": "dunes", "amp": 1.3, "freq": 0.03, "flat_r": 8.0,
		"accent": Color(1.0, 0.8, 0.4), "portal_frame": Color(0.7, 0.55, 0.38), "portal_tint": Color(1.0, 0.8, 0.35),
		"shop_name": "CARAVANA DEL ARCHIVERO", "shop_kind": "tent", "chest_kind": "sand",
		"trans": "dust", "trans_color": Color(0.95, 0.78, 0.5),
	},
	{ # ------------------------------------------------------------------ 4
		"id": "citadel", "name": "Ciudadela Flotante", "region": "Cielos del Derecho Natural",
		"floor_a": Color(0.78, 0.8, 0.86), "floor_b": Color(0.7, 0.72, 0.8),
		"g_main": Color(0.6, 0.64, 0.8), "g_alt": Color(0.48, 0.52, 0.72), "g_detail": Color(0.4, 0.85, 1.0),
		"g_path": Color(0.9, 0.86, 0.7), "ground": Color(0.35, 0.4, 0.62), "floor_line": Color(0.5, 0.9, 1.0),
		"wall": Color(0.82, 0.84, 0.92), "wall_accent": Color(0.4, 0.9, 1.0), "wall_style": "crystal",
		"building": Color(0.7, 0.72, 0.86), "window": Color(0.6, 0.95, 1.0), "towers": 12,
		"wood": Color(0.5, 0.4, 0.5), "metal": Color(0.7, 0.75, 0.85),
		"paints": [Color(0.4, 0.8, 0.95), Color(0.8, 0.5, 0.9), Color(0.95, 0.85, 0.5)],
		"marble": Color(0.92, 0.93, 0.98), "platform": Color(0.72, 0.74, 0.84),
		"sky": Color(0.55, 0.65, 0.95), "sky_top": Color(0.22, 0.28, 0.65), "sky_horizon": Color(0.95, 0.7, 0.88),
		"fog": Color(0.74, 0.62, 0.9), "fog_density": 0.0048, "ambient": Color(0.7, 0.72, 0.95), "ambient_energy": 0.65,
		"sun": Color(1.0, 0.9, 0.82), "sun_energy": 1.05, "sun_pitch": -40.0,
		"kinds": ["crystal", "crystal", "float_pillar", "arch", "lantern", "planter_magic", "statue", "crystal"],
		"void": true, "terrain": "floating", "amp": 1.2, "freq": 0.042, "flat_r": 9.0,
		"accent": Color(0.5, 0.95, 1.0), "portal_frame": Color(0.75, 0.78, 0.9), "portal_tint": Color(0.45, 0.9, 1.0),
		"shop_name": "PABELLÓN DE CRISTAL", "shop_kind": "pavilion", "chest_kind": "crystal",
		"trans": "iris", "trans_color": Color(0.7, 0.8, 1.0),
	},
	{ # ------------------------------------------------------------------ 5
		"id": "court", "name": "Tribunal Final", "region": "La Gran Sala del Juicio",
		"floor_a": Color(0.2, 0.17, 0.26), "floor_b": Color(0.16, 0.13, 0.22),
		"g_main": Color(0.2, 0.17, 0.27), "g_alt": Color(0.3, 0.26, 0.38), "g_detail": Color(0.95, 0.75, 0.25),
		"g_path": Color(0.5, 0.2, 0.22), "ground": Color(0.06, 0.05, 0.1), "floor_line": Color(1.0, 0.78, 0.25),
		"wall": Color(0.32, 0.28, 0.4), "wall_accent": Color(1.0, 0.78, 0.25), "wall_style": "columns",
		"building": Color(0.22, 0.2, 0.3), "window": Color(1.0, 0.75, 0.3), "towers": 10,
		"wood": Color(0.3, 0.18, 0.12), "metal": Color(0.7, 0.58, 0.25),
		"paints": [Color(0.55, 0.12, 0.18), Color(0.95, 0.75, 0.25), Color(0.3, 0.2, 0.5)],
		"marble": Color(0.7, 0.66, 0.72), "platform": Color(0.3, 0.26, 0.38),
		"sky": Color(0.12, 0.07, 0.2), "sky_top": Color(0.05, 0.03, 0.12), "sky_horizon": Color(0.45, 0.16, 0.3),
		"fog": Color(0.2, 0.1, 0.24), "fog_density": 0.0095, "ambient": Color(0.55, 0.45, 0.65), "ambient_energy": 0.85,
		"sun": Color(1.0, 0.8, 0.65), "sun_energy": 1.0, "sun_pitch": -50.0,
		"kinds": ["pillar", "pillar", "statue", "brazier", "counter", "scale_statue", "banner", "brazier"],
		"terrain": "court", "amp": 0.3, "freq": 0.05, "flat_r": 12.0,
		"accent": Color(1.0, 0.78, 0.25), "portal_frame": Color(0.3, 0.26, 0.38), "portal_tint": Color(1.0, 0.75, 0.25),
		"shop_name": "DESPACHO DEL ALGUACIL", "shop_kind": "booth", "chest_kind": "gold",
		"trans": "bars", "trans_color": Color(0.9, 0.7, 0.2),
	},
]


static func biome_index(arena_index: int) -> int:
	return Scaling.cycle_of(arena_index) % COUNT


static func get_biome(i: int) -> Dictionary:
	return BIOMES[posmod(i, COUNT)]


static func for_arena(arena_index: int) -> Dictionary:
	return BIOMES[biome_index(arena_index)]


## Diccionario de paleta que usa todo el código antiguo (pal): bioma + ajustes por tipo de arena.
static func palette_for(arena_index: int, kind: String) -> Dictionary:
	var pal: Dictionary = for_arena(arena_index).duplicate()
	pal["biome"] = biome_index(arena_index)
	if kind == Scaling.KIND_BOSS:
		# arena de jefe: más oscura y tensa (cielo teñido de rojo) pero del MISMO bioma
		pal["sky_top"] = (pal["sky_top"] as Color).darkened(0.35).lerp(Color(0.35, 0.05, 0.08), 0.25)
		pal["sky_horizon"] = (pal["sky_horizon"] as Color).darkened(0.25).lerp(Color(0.7, 0.18, 0.15), 0.3)
		pal["fog"] = (pal["fog"] as Color).darkened(0.25).lerp(Color(0.45, 0.1, 0.1), 0.25)
		pal["sun"] = (pal["sun"] as Color).lerp(Color(1.0, 0.55, 0.4), 0.3)
		pal["sun_energy"] = float(pal["sun_energy"]) * 0.9
		pal["ambient_energy"] = float(pal["ambient_energy"]) * 0.85
		pal["boss"] = true
	else:
		pal["boss"] = false
	return pal
