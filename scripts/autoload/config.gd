extends Node
## Constantes de juego, capas de física, equilibrio base y presets de calidad.
## Todo el equilibrio vive aquí o en Scaling/UpgradeDB para poder ajustarse sin tocar
## cada enemigo individualmente.

const GAME_NAME := "LAWYER MAYHEM 3D"
const VERSION := "0.11.0"

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

# --- Calidad gráfica --------------------------------------------------------
# Cada preset fija los ajustes sueltos (sombras, distancia, efectos, escala); el jugador puede cambiarlos uno a uno.
# max_enemies: límite simultáneo de enemigos; msaa: suavizado de bordes del preset.
const QUALITY := [
	{"name": "Baja", "msaa": 0, "max_enemies": 18, "shadow_q": 0, "draw_dist": 0, "fx_level": 0, "render_scale": 0.67},
	{"name": "Media", "msaa": 0, "max_enemies": 28, "shadow_q": 0, "draw_dist": 1, "fx_level": 1, "render_scale": 0.85},
	{"name": "Alta", "msaa": 1, "max_enemies": 40, "shadow_q": 2, "draw_dist": 2, "fx_level": 2, "render_scale": 1.0},
]
## Sombras del sol: apagadas / bajas (atlas pequeño, corto alcance) / altas.
const SHADOW_LEVELS := [
	{"name": "Apagadas", "on": false, "atlas": 1024, "dist": 30.0, "filter": 0},
	{"name": "Bajas", "on": true, "atlas": 1024, "dist": 32.0, "filter": 1},
	{"name": "Altas", "on": true, "atlas": 4096, "dist": 60.0, "filter": 2},
]
## Distancia de dibujado = plano lejano de la cámara (lo que queda más lejos no se dibuja).
const DRAW_DISTS := [
	{"name": "Corta", "far": 90.0},
	{"name": "Media", "far": 140.0},
	{"name": "Larga", "far": 220.0},
]
## Efectos: máximo de efectos simultáneos y densidad de partículas.
const FX_LEVELS := [
	{"name": "Reducidos", "max_fx": 24, "particles": 0.5},
	{"name": "Normales", "max_fx": 48, "particles": 0.8},
	{"name": "Completos", "max_fx": 80, "particles": 1.0},
]
const RENDER_SCALES := [0.5, 0.67, 0.85, 1.0]
const GFX_KEYS := ["shadow_q", "draw_dist", "fx_level", "render_scale"]

# --- Cámara -------------------------------------------------------------------
## Límites razonables: nunca atraviesa al personaje, no se aleja tanto que no se vea, ni queda en un ángulo injugable.
const CAM_DIST := {"min": 5.0, "max": 16.0, "def": 9.6}
const CAM_HEIGHT := {"min": 1.0, "max": 3.2, "def": 1.7}
const CAM_PITCH := {"min": 15.0, "max": 55.0, "def": 25.0}      # grados de inclinación hacia abajo
const CAM_SENS := {"min": 0.3, "max": 2.5, "def": 1.0}
const CAM_KEYS := ["cam_dist", "cam_height", "cam_pitch", "cam_sens_x", "cam_sens_y", "cam_invert_y"]


func reset_camera() -> void:
	SaveSystem.set_setting("cam_dist", CAM_DIST["def"])
	SaveSystem.set_setting("cam_height", CAM_HEIGHT["def"])
	SaveSystem.set_setting("cam_pitch", CAM_PITCH["def"])
	SaveSystem.set_setting("cam_sens_x", CAM_SENS["def"])
	SaveSystem.set_setting("cam_sens_y", CAM_SENS["def"])
	SaveSystem.set_setting("cam_invert_y", false)
	apply_camera()


## Aplica al instante la cámara guardada (distancia, altura e inclinación; la sensibilidad se lee en cada fotograma).
func apply_camera() -> void:
	if GameState.cam != null and is_instance_valid(GameState.cam):
		GameState.cam.apply_settings()


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


func shadow_cfg() -> Dictionary:
	return SHADOW_LEVELS[clampi(int(SaveSystem.setting("shadow_q")), 0, SHADOW_LEVELS.size() - 1)]


func draw_far() -> float:
	return float(DRAW_DISTS[clampi(int(SaveSystem.setting("draw_dist")), 0, DRAW_DISTS.size() - 1)]["far"])


func fx_cfg() -> Dictionary:
	return FX_LEVELS[clampi(int(SaveSystem.setting("fx_level")), 0, FX_LEVELS.size() - 1)]


func render_scale() -> float:
	var v := float(SaveSystem.setting("render_scale"))
	var best: float = RENDER_SCALES[0]
	for r in RENDER_SCALES:
		if absf(float(r) - v) < absf(best - v):
			best = float(r)
	return best


## Límites de FPS que ofrece este dispositivo: 30 y 60 siempre; 90/120 solo si la pantalla llega a esa frecuencia.
func fps_options() -> Array:
	var out := [30, 60]
	var hz := DisplayServer.screen_get_refresh_rate()
	if hz >= 85.0:
		out.append(90)
	if hz >= 115.0:
		out.append(120)
	return out


## Elige un preset (Baja/Media/Alta) y copia sus valores a los ajustes sueltos.
func apply_preset(i: int) -> void:
	i = clampi(i, 0, QUALITY.size() - 1)
	SaveSystem.set_setting("quality", i)
	for k in GFX_KEYS:
		SaveSystem.set_setting(k, QUALITY[i][k])


## ¿Los ajustes sueltos coinciden con el preset elegido? (si no, la interfaz muestra "Personalizado")
func preset_matches() -> bool:
	var q := quality()
	for k in GFX_KEYS:
		if absf(float(SaveSystem.setting(k)) - float(q[k])) > 0.001:
			return false
	return true


func reset_graphics() -> void:
	apply_preset(1)
	SaveSystem.set_setting("fps", 60)
	SaveSystem.set_setting("show_fps", false)
	SaveSystem.set_setting("reduce_fx", false)


## Configura un sol según las sombras elegidas (lo llaman la sala y las arenas al crearlo, y apply_graphics al cambiar).
func configure_sun(sun: DirectionalLight3D) -> void:
	var sc := shadow_cfg()
	sun.shadow_enabled = bool(sc["on"])
	sun.directional_shadow_max_distance = float(sc["dist"])
	if not sun.is_in_group("sun_light"):
		sun.add_to_group("sun_light")


## Aplica TODOS los ajustes gráficos guardados al motor (escala de render, MSAA, FPS, sombras, distancia).
func apply_graphics(viewport: Viewport = null) -> void:
	if viewport == null:
		viewport = get_viewport()
	var q := quality()
	if viewport != null:
		viewport.scaling_3d_scale = render_scale()
		viewport.msaa_3d = int(q["msaa"]) as Viewport.MSAA
	Engine.max_fps = clampi(int(SaveSystem.setting("fps")), 15, 240)
	var sc := shadow_cfg()
	RenderingServer.directional_shadow_atlas_set_size(int(sc["atlas"]), true)
	RenderingServer.directional_soft_shadow_filter_set_quality([RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM][int(sc["filter"])] as RenderingServer.ShadowQuality)
	for l in get_tree().get_nodes_in_group("sun_light"):
		configure_sun(l as DirectionalLight3D)
	var far := draw_far()
	if GameState.cam != null and is_instance_valid(GameState.cam) and GameState.cam.cam != null:
		GameState.cam.cam.far = far
	if GameState.fx != null and is_instance_valid(GameState.fx):
		GameState.fx.apply_quality()


func cmd_flag(flag: String) -> bool:
	return OS.get_cmdline_user_args().has(flag) or OS.get_cmdline_args().has(flag)
