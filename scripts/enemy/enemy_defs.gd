class_name EnemyDefs
extends RefCounted
## Definiciones de enemigos y de sus ataques (datos puros; el escalado lo aplica Scaling).
## Para añadir un enemigo nuevo: una entrada en DEFS + un modelo en ModelFactory.build_enemy.

const DEFS := {
	"thief": {
		"name": "Ladrón", "hp": 55.0, "speed": 4.4, "dmg": 9.0, "radius": 0.45, "scale": 1.0,
		"xp": 8.0, "coins": 2, "behavior": "melee", "attacks": ["melee"], "knock_res": 0.0, "variants": 3,
	},
	"runner": {
		"name": "Corredor", "hp": 32.0, "speed": 7.2, "dmg": 7.0, "radius": 0.38, "scale": 1.0,
		"xp": 9.0, "coins": 2, "behavior": "flank", "attacks": ["melee_fast"], "knock_res": 0.0, "variants": 3,
	},
	"tank": {
		"name": "Tanque", "hp": 240.0, "speed": 2.7, "dmg": 18.0, "radius": 0.8, "scale": 1.0,
		"xp": 22.0, "coins": 6, "behavior": "melee", "attacks": ["ground_slam", "melee_heavy"], "knock_res": 0.7, "variants": 2,
	},
	"ranged": {
		"name": "Especialista", "hp": 42.0, "speed": 3.8, "dmg": 10.0, "radius": 0.42, "scale": 1.0,
		"xp": 12.0, "coins": 3, "behavior": "ranged", "attacks": ["shoot"], "knock_res": 0.0, "variants": 3,
		"band": [8.5, 13.5],
	},
	"summoner": {
		"name": "Invocador", "hp": 90.0, "speed": 3.0, "dmg": 8.0, "radius": 0.45, "scale": 1.0,
		"xp": 26.0, "coins": 7, "behavior": "ranged", "attacks": ["summon", "shoot_slow"], "knock_res": 0.1, "variants": 1,
		"band": [11.0, 16.0],
	},
	"elite": {
		"name": "Capo Élite", "hp": 560.0, "speed": 4.4, "dmg": 16.0, "radius": 0.65, "scale": 1.0,
		"xp": 55.0, "coins": 14, "behavior": "melee", "attacks": ["melee", "dash_strike", "ring_blast"], "knock_res": 0.55, "variants": 3,
	},
	"miniboss": {
		"name": "Capataz Blindado", "hp": 1500.0, "speed": 3.3, "dmg": 22.0, "radius": 0.95, "scale": 1.0,
		"xp": 130.0, "coins": 40, "behavior": "melee", "attacks": ["melee_heavy", "ground_slam", "charge", "shoot_fan"], "knock_res": 0.85, "variants": 1,
	},
	"boss": {
		"name": "Don Capital, el Banquero Corrupto", "hp": 4600.0, "speed": 3.1, "dmg": 24.0, "radius": 1.3, "scale": 1.0,
		"xp": 400.0, "coins": 120, "behavior": "boss", "attacks": [], "knock_res": 0.95, "variants": 1,
	},
}

## Escala visual (se aplica al rig) por clase
const VISUAL_SCALE := {
	"thief": 1.0, "runner": 1.0, "tank": 1.3, "ranged": 1.0, "summoner": 1.0, "elite": 1.3, "miniboss": 1.75, "boss": 2.3,
}

# Atributos de cada ataque. shape: cone | circle | line | aim | circles | summon
const ATTACKS := {
	"melee": {"shape": "cone", "radius": 2.6, "angle": 110.0, "tele": 0.6, "recover": 0.6, "dmg": 1.0, "anim": "slam", "range": 2.2, "min_range": 0.0, "cd": 0.5},
	"melee_fast": {"shape": "cone", "radius": 2.1, "angle": 100.0, "tele": 0.38, "recover": 0.5, "dmg": 0.85, "anim": "swing", "range": 1.9, "min_range": 0.0, "cd": 0.5},
	"melee_heavy": {"shape": "cone", "radius": 3.4, "angle": 130.0, "tele": 0.8, "recover": 0.8, "dmg": 1.3, "anim": "slam", "range": 2.8, "min_range": 0.0, "cd": 0.7},
	"ground_slam": {"shape": "circle", "radius": 4.3, "tele": 1.0, "recover": 0.9, "dmg": 1.5, "anim": "slam", "range": 3.8, "min_range": 0.0, "cd": 2.6, "shake": 0.55},
	"charge": {"shape": "line", "length": 10.0, "width": 2.4, "tele": 0.9, "recover": 1.2, "dmg": 1.4, "anim": "windup", "range": 12.0, "min_range": 4.5, "cd": 4.5, "dash_speed": 17.0},
	"dash_strike": {"shape": "line", "length": 7.0, "width": 1.9, "tele": 0.65, "recover": 0.75, "dmg": 1.1, "anim": "windup", "range": 8.0, "min_range": 3.0, "cd": 3.5, "dash_speed": 21.0},
	"shoot": {"shape": "aim", "tele": 0.6, "recover": 0.7, "dmg": 1.0, "anim": "shoot", "range": 17.0, "min_range": 3.0, "cd": 1.9, "proj": "coin", "speed": 12.0, "count": 1, "spread": 0.0},
	"shoot_fan": {"shape": "cone", "radius": 13.0, "angle": 70.0, "tele": 0.75, "recover": 0.9, "dmg": 0.85, "anim": "shoot", "range": 15.0, "min_range": 0.0, "cd": 3.2, "proj": "bolt", "speed": 11.5, "count": 5, "spread": 60.0},
	"shoot_slow": {"shape": "aim", "tele": 0.7, "recover": 0.8, "dmg": 0.9, "anim": "shoot", "range": 18.0, "min_range": 0.0, "cd": 3.4, "proj": "blob", "speed": 7.5, "count": 1, "spread": 0.0},
	"summon": {"shape": "summon", "radius": 3.2, "tele": 1.1, "recover": 0.9, "dmg": 0.0, "anim": "summon", "range": 40.0, "min_range": 0.0, "cd": 9.0, "count": 2},
	"ring_blast": {"shape": "circle", "radius": 6.5, "tele": 1.05, "recover": 0.9, "dmg": 1.2, "anim": "roar", "range": 9.0, "min_range": 0.0, "cd": 5.5, "shake": 0.45},
	"barrage": {"shape": "circles", "n": 6, "radius": 2.5, "tele": 1.25, "recover": 0.9, "dmg": 1.3, "anim": "summon", "range": 40.0, "min_range": 0.0, "cd": 6.5},
	"volley": {"shape": "aim", "tele": 0.9, "recover": 0.9, "dmg": 0.9, "anim": "shoot", "range": 40.0, "min_range": 0.0, "cd": 4.0, "proj": "bolt", "speed": 12.0, "count": 3, "spread": 28.0},
	"radial": {"shape": "circle", "radius": 3.0, "tele": 0.85, "recover": 1.0, "dmg": 0.8, "anim": "roar", "range": 40.0, "min_range": 0.0, "cd": 6.0, "proj": "bolt", "speed": 9.0, "count": 14, "spread": 360.0},
	# --- ataques nuevos de jefes (v0.12) ---
	"coin_rain": {"shape": "circles", "n": 9, "radius": 2.2, "tele": 1.4, "recover": 1.0, "dmg": 1.2, "anim": "summon", "range": 40.0, "min_range": 0.0, "cd": 7.0},
	"sand_pillars": {"shape": "circles", "n": 5, "radius": 3.3, "tele": 1.7, "recover": 1.1, "dmg": 1.4, "anim": "summon", "range": 40.0, "min_range": 0.0, "cd": 7.5},
	"spiral": {"shape": "circle", "radius": 2.4, "tele": 0.8, "recover": 1.3, "dmg": 0.7, "anim": "roar", "range": 40.0, "min_range": 0.0, "cd": 8.5, "proj": "bolt", "speed": 8.5, "count": 5, "spread": 360.0, "waves": 7, "wave_gap": 0.18, "wave_rot": 24.0},
	"ring_chain": {"shape": "circle", "radius": 5.6, "tele": 1.0, "recover": 1.1, "dmg": 1.0, "anim": "roar", "range": 10.0, "min_range": 0.0, "cd": 7.0, "shake": 0.5, "waves": 3, "wave_gap": 0.55},
	"rocket_volley": {"shape": "aim", "tele": 0.85, "recover": 1.0, "dmg": 0.8, "anim": "shoot", "range": 40.0, "min_range": 0.0, "cd": 5.5, "proj": "bolt", "speed": 11.0, "count": 7, "spread": 70.0, "waves": 2, "wave_gap": 0.45},
	"vine_sweep": {"shape": "cone", "radius": 9.0, "angle": 160.0, "tele": 0.95, "recover": 1.0, "dmg": 1.3, "anim": "slam", "range": 9.0, "min_range": 0.0, "cd": 5.0, "shake": 0.4},
	"summon_runners": {"shape": "summon", "radius": 3.2, "tele": 1.0, "recover": 0.9, "dmg": 0.0, "anim": "summon", "range": 40.0, "min_range": 0.0, "cd": 10.0, "count": 3, "minion": "runner"},
	"gavel_leap": {"shape": "leap", "radius": 4.2, "tele": 1.0, "recover": 1.0, "dmg": 1.5, "anim": "windup", "range": 30.0, "min_range": 5.0, "cd": 6.0, "dur": 0.5, "shake": 0.7},
	"blink_strike": {"shape": "leap", "radius": 3.4, "tele": 0.7, "recover": 0.8, "dmg": 1.2, "anim": "windup", "range": 40.0, "min_range": 3.0, "cd": 5.0, "dur": 0.12, "behind": true, "shake": 0.4},
	"verdict_beam": {"shape": "beam", "length": 22.0, "width": 2.4, "tele": 1.1, "recover": 1.0, "dmg": 1.5, "anim": "shoot", "range": 40.0, "min_range": 2.0, "cd": 6.5},
	"cross_beam": {"shape": "beam", "length": 22.0, "width": 2.2, "tele": 1.25, "recover": 1.1, "dmg": 1.4, "anim": "shoot", "range": 40.0, "min_range": 2.0, "cd": 8.0, "waves": 3, "wave_gap": 0.5, "wave_rot": 60.0},
}

# Ataques del jefe por fase (jefe genérico/urbano; los demás jefes usan BOSS_STYLES)
const BOSS_PHASES := {
	1: ["ground_slam", "volley", "summon"],
	2: ["ground_slam", "volley", "charge", "barrage", "summon"],
	3: ["ground_slam", "charge", "barrage", "ring_blast", "radial", "volley"],
}

## Un jefe por región (el bioma decide cuál): nombre, color, escala y ataques propios en cada fase.
const BOSS_STYLES := {
	"urban": {"name": "Don Capital, el Banquero Corrupto", "tint": Color(1, 1, 1), "scale": 2.3, "hp_x": 1.0, "speed_x": 1.0,
		"phases": {1: ["ground_slam", "volley", "summon", "coin_rain"], 2: ["ground_slam", "volley", "charge", "barrage", "summon", "coin_rain"],
			3: ["ground_slam", "charge", "barrage", "ring_blast", "radial", "volley", "coin_rain", "spiral"]}},
	"forest": {"name": "Doña Hiedra, la Notaria Venenosa", "tint": Color(0.7, 1.0, 0.7), "scale": 2.2, "hp_x": 0.95, "speed_x": 1.1,
		"phases": {1: ["vine_sweep", "volley", "summon_runners"], 2: ["vine_sweep", "spiral", "barrage", "summon_runners", "volley"],
			3: ["vine_sweep", "spiral", "cross_beam", "barrage", "radial", "summon_runners"]}},
	"industrial": {"name": "Capataz Mayor Acero", "tint": Color(1.0, 0.75, 0.55), "scale": 2.5, "hp_x": 1.15, "speed_x": 0.95,
		"phases": {1: ["ground_slam", "charge", "rocket_volley"], 2: ["ground_slam", "charge", "gavel_leap", "rocket_volley", "ring_chain"],
			3: ["gavel_leap", "charge", "ring_chain", "rocket_volley", "barrage", "radial"]}},
	"desert": {"name": "El Escribano Faraón", "tint": Color(1.0, 0.92, 0.55), "scale": 2.3, "hp_x": 1.0, "speed_x": 1.0,
		"phases": {1: ["verdict_beam", "sand_pillars", "summon"], 2: ["verdict_beam", "sand_pillars", "blink_strike", "volley"],
			3: ["cross_beam", "sand_pillars", "blink_strike", "spiral", "summon_runners"]}},
	"citadel": {"name": "El Fiscal Supremo del Cielo", "tint": Color(0.7, 0.85, 1.0), "scale": 2.2, "hp_x": 0.95, "speed_x": 1.15,
		"phases": {1: ["blink_strike", "volley", "rocket_volley"], 2: ["blink_strike", "spiral", "verdict_beam", "rocket_volley"],
			3: ["blink_strike", "cross_beam", "spiral", "ring_chain", "radial"]}},
	"court": {"name": "El Juez Supremo, Verdugo de la Sala", "tint": Color(1.0, 0.65, 0.75), "scale": 2.6, "hp_x": 1.25, "speed_x": 1.0,
		"phases": {1: ["gavel_leap", "verdict_beam", "summon"], 2: ["gavel_leap", "cross_beam", "ring_chain", "barrage", "summon"],
			3: ["gavel_leap", "cross_beam", "spiral", "ring_chain", "coin_rain", "radial", "blink_strike"]}},
}

## Afijos (variantes peligrosas de enemigos normales)
const AFFIXES := {
	"veloz": {"name": "Veloz", "tint": Color(0.7, 1.0, 0.75), "speed": 1.35, "hp": 0.85},
	"blindado": {"name": "Blindado", "tint": Color(0.72, 0.8, 1.0), "speed": 0.95, "hp": 1.8},
	"explosivo": {"name": "Explosivo", "tint": Color(1.0, 0.62, 0.45), "speed": 1.05, "hp": 1.0},
	"regenerante": {"name": "Regenerante", "tint": Color(1.0, 0.72, 0.95), "speed": 1.0, "hp": 1.3},
}
