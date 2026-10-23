extends Node
## Constantes de juego, capas de física, equilibrio base y presets de calidad.
## Todo el equilibrio vive aquí o en Scaling/UpgradeDB para poder ajustarse sin tocar
## cada enemigo individualmente.

const GAME_NAME := "LAWYER MAYHEM 3D"
const VERSION := "0.6.0"

# Capas de física (máscaras de bits)
const L_WORLD := 1
const L_PLAYER := 2
const L_ENEMY := 4
const L_PICKUP := 8
const L_CAMERA := 16

# --- Jugador base -----------------------------------------------------------
const PLAYER := {
	"max_hp": 100.0,
	"move_speed": 7.2,
	"sprint_mult": 1.0,
	"jump_velocity": 8.6,
	"gravity": 24.0,
	"accel": 48.0,
	"friction": 40.0,
	"dodge_time": 0.30,
	"dodge_speed": 17.0,
	"dodge_cd": 1.15,
	"iframes": 0.32,
	"energy_max": 100.0,
	"energy_regen": 7.0,
	"shield_regen_delay": 4.0,
	"shield_regen": 12.0,
}

# --- Habilidades base --------------------------------------------------------
# slot 0: primaria; 1..3 secundarias
const SKILLS := {
	"slam": {"name": "Lanzamiento de Maletín", "cd": 0.55, "dmg": 24.0, "radius": 3.6, "arc": 150.0, "cost": 0.0, "knock": 7.0},
	"docs": {"name": "Documentos Teledirigidos", "cd": 4.0, "dmg": 16.0, "count": 4, "cost": 18.0, "speed": 15.0, "range": 28.0},
	"seal": {"name": "Sello Mágico", "cd": 7.5, "dmg": 9.0, "radius": 4.2, "duration": 4.5, "cost": 28.0, "tick": 0.4},
	"barrier": {"name": "Objeción", "cd": 11.0, "dmg": 20.0, "radius": 5.2, "duration": 3.0, "cost": 34.0, "shield": 45.0, "knock": 16.0},
}

# --- Escalado de dificultad (ver Scaling) ------------------------------------
## Curva de dificultad CONTINUA: depende solo del índice de arena (y de la dificultad elegida), nunca de tiendas,
## mejoras ni portales. Cada magnitud crece un pequeño % por arena (lineal + exponencial suave).
const SCALING := {
	"arenas_per_zone": 5,           # solo rota el TIPO de arena (eliminación, supervivencia…); no sube la dificultad
	"hp_lin": 0.09, "hp_exp": 1.03,        # vida = (1 + lin·a) · exp^a
	"dmg_lin": 0.045, "dmg_exp": 1.02,       # daño = (1 + lin·a) · exp^a
	"count_per_arena": 0.06, "count_cap": 4.0,   # cantidad: crece y satura suavemente hacia el tope
	"spawn_interval_base": 2.3,
	"spawn_interval_decay": 0.94,
	"spawn_interval_min": 0.55,
	"reward_per_arena": 0.08,
	"speed_per_arena": 0.005, "speed_cap": 1.35,
	"affix_start": 4, "affix_per_arena": 0.02, "affix_cap": 0.6,
	"resist_per_arena": 0.006, "resist_cap": 0.4,    # resistencia de élites y jefes (reduce el daño que reciben)
	"pace_per_arena": 0.006, "pace_min": 0.6,        # élites y jefes atacan con más frecuencia
}

# --- Presets de calidad -----------------------------------------------------
# max_enemies: límite simultáneo; max_fx: efectos simultáneos
const QUALITY := [
	{"name": "Baja", "shadows": false, "scale3d": 0.67, "max_enemies": 18, "max_fx": 24, "msaa": 0, "fx_particles": 0.5},
	{"name": "Media", "shadows": false, "scale3d": 0.85, "max_enemies": 28, "max_fx": 48, "msaa": 0, "fx_particles": 0.8},
	{"name": "Alta", "shadows": true, "scale3d": 1.0, "max_enemies": 40, "max_fx": 80, "msaa": 1, "fx_particles": 1.0},
]

# --- Economía ---------------------------------------------------------------
const ECONOMY := {
	"coin_base": 3,
	"chest_coins": 25,
	"heal_price": 30,
	"attr_price": 55,
	"skill_price": 80,
	"special_price": 140,
	"price_growth": 1.18,
}

# --- Mejoras permanentes (meta-progresión, se compran con honorarios) -------
const PERM_UPGRADES := [
	{"id": "perm_hp", "name": "Salud de Socio", "desc": "+8 salud máxima por nivel", "max": 10, "cost": 60, "growth": 1.35},
	{"id": "perm_dmg", "name": "Litigante Veterano", "desc": "+4% daño por nivel", "max": 10, "cost": 80, "growth": 1.4},
	{"id": "perm_coins", "name": "Fondo de Reserva", "desc": "+20 monedas iniciales por nivel", "max": 8, "cost": 50, "growth": 1.3},
	{"id": "perm_luck", "name": "Contactos Influyentes", "desc": "+6% suerte en cofres por nivel", "max": 6, "cost": 120, "growth": 1.5},
	{"id": "perm_speed", "name": "Zapatos de Marca", "desc": "+3% velocidad por nivel", "max": 6, "cost": 90, "growth": 1.4},
	{"id": "perm_regen", "name": "Seguro Privado", "desc": "+0.6 regeneración por nivel", "max": 6, "cost": 100, "growth": 1.45},
]

# Probabilidad de que cada arena de ciclo tenga tienda (índice dentro de la zona 0..4)
const SHOP_AFTER_ZONE_INDEX := [false, true, false, true, true]

var dev_mode := false           # se activa desde ajustes (opción discreta)
var dev_god_mode := false
var dev_show_debug := false


func quality() -> Dictionary:
	var q := int(SaveSystem.setting("quality"))
	return QUALITY[clampi(q, 0, QUALITY.size() - 1)]


func apply_graphics(viewport: Viewport) -> void:
	var q := quality()
	if viewport != null:
		viewport.scaling_3d_scale = float(q["scale3d"])
		viewport.msaa_3d = int(q["msaa"]) as Viewport.MSAA
	Engine.max_fps = int(SaveSystem.setting("fps"))


func cmd_flag(flag: String) -> bool:
	return OS.get_cmdline_user_args().has(flag) or OS.get_cmdline_args().has(flag)
