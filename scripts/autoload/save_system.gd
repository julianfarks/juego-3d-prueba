extends Node
## Guardado local persistente (JSON en user://).
## Guarda: ajustes, distribución de controles, meta-progresión (honorarios y mejoras
## permanentes), récords y estadísticas.
## LIMITACIÓN CONOCIDA: no se guarda la partida en curso (run). Las transiciones entre
## arenas y el volver al menú nunca pierden el progreso permanente porque éste se
## escribe en disco al terminar cada arena y al terminar/abandonar la partida.

const PATH := "user://lawyer_mayhem_save.json"
const SAVE_VERSION := 1

var data: Dictionary = {}
var _dirty := false
var _save_timer := 0.0


func _init() -> void:
	data = defaults()


func _ready() -> void:
	load_data()


func defaults() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"settings": {
			"music": 0.7,
			"sfx": 0.9,
			"ambient": 0.6,
			"quality": 1,          # 0 baja, 1 media, 2 alta
			"fps": 60,
			"camera_sens": 1.0,
			"vibration": true,
			"show_fps": false,
			"auto_attack": true,
			"damage_numbers": true,
			"dev_unlocked": false,
		},
		"controls": {
			# posiciones como fracción de la pantalla (centro del botón) y escala
			"joystick": {"x": 0.14, "y": 0.74, "scale": 1.0},
			"attack": {"x": 0.88, "y": 0.72, "scale": 1.15},
			"skill1": {"x": 0.76, "y": 0.84, "scale": 0.9},
			"skill2": {"x": 0.68, "y": 0.64, "scale": 0.9},
			"skill3": {"x": 0.80, "y": 0.50, "scale": 0.9},
			"jump": {"x": 0.93, "y": 0.50, "scale": 0.95},
			"dodge": {"x": 0.61, "y": 0.84, "scale": 0.95},
			"interact": {"x": 0.50, "y": 0.62, "scale": 1.0},
		},
		"meta": {
			"fees": 0,              # honorarios: moneda permanente
			"perm": {},             # id -> nivel
			"unlocks": ["theme_roof"],
		},
		"records": {
			"best_arena": 0,
			"best_cycle": 0,
			"best_kills": 0,
			"best_time": 0.0,
			"best_score": 0,
		},
		"stats": {
			"runs": 0,
			"kills": 0,
			"deaths": 0,
			"bosses": 0,
			"coins": 0,
			"playtime": 0.0,
			"damage": 0.0,
			"cards": 0,
		},
	}


func load_data() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		push_warning("[Save] No se pudo abrir el guardado: %s" % error_string(FileAccess.get_open_error()))
		return
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("[Save] Guardado corrupto, se usan valores por defecto.")
		return
	data = _merge(defaults(), parsed)


func save_now() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_warning("[Save] No se pudo escribir el guardado: %s" % error_string(FileAccess.get_open_error()))
		return
	f.store_string(JSON.stringify(data))
	f.close()
	_dirty = false


func mark_dirty() -> void:
	_dirty = true
	_save_timer = 1.0


func _process(delta: float) -> void:
	if _dirty:
		_save_timer -= delta
		if _save_timer <= 0.0:
			save_now()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		save_now()


func _merge(base: Dictionary, over: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for k in over.keys():
		if out.has(k) and typeof(out[k]) == TYPE_DICTIONARY and typeof(over[k]) == TYPE_DICTIONARY:
			out[k] = _merge(out[k], over[k])
		else:
			out[k] = over[k]
	return out


# --- accesos cómodos -------------------------------------------------------
func setting(key: String) -> Variant:
	return data["settings"][key]


func set_setting(key: String, value: Variant) -> void:
	data["settings"][key] = value
	mark_dirty()


func reset_controls() -> void:
	data["controls"] = defaults()["controls"]
	mark_dirty()
