extends Node
## Guardado local persistente (user://, funciona igual en Android).
## Guarda: ajustes, controles, meta-progresión (honorarios, mejoras y desbloqueos), equipamiento y
## dificultad elegidos, récords, estadísticas y la PARTIDA EN CURSO ("run").
##
## Seguridad contra archivos corruptos:
##  - Escritura atómica: se escribe a un .tmp, se vuelve a leer y se verifica su suma SHA-256 antes de
##    reemplazar el archivo bueno. El archivo anterior se conserva como .bak.
##  - Al cargar, si el archivo principal está dañado se usa la copia .bak.
##  - La partida en curso se valida campo por campo; si no es válida se descarta (nunca se carga a medias).

signal notice(text: String, good: bool)

const PATH := "user://lawyer_mayhem_save.json"
const PATH_TMP := "user://lawyer_mayhem_save.json.tmp"
const PATH_BAK := "user://lawyer_mayhem_save.json.bak"
const SAVE_VERSION := 2
const RUN_VERSION := 1
const RUN_STAGES := ["fight", "reward", "portal"]

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
		"loadout": {"weapon": "case", "skill": "docs_burst", "tactic": "brawler", "gear": "toga"},
		"difficulty": "associate",
		"run": {},                 # partida en curso (vacío = no hay partida guardada)
		"records": {
			"best_arena": 0,
			"best_cycle": 0,
			"best_kills": 0,
			"best_time": 0.0,
			"best_score": 0,
		},
		"stats": {
			"runs": 0,
			"wins": 0,             # runs completadas (victoria)
			"kills": 0,
			"deaths": 0,
			"bosses": 0,
			"coins": 0,
			"playtime": 0.0,
			"damage": 0.0,
			"cards": 0,
		},
	}


var last_load_note := ""      # texto sobre lo ocurrido al cargar (para mostrarlo al jugador)


func load_data() -> void:
	last_load_note = ""
	var had_file := FileAccess.file_exists(PATH) or FileAccess.file_exists(PATH_BAK)
	var parsed: Variant = _read_file(PATH)
	if parsed == null and FileAccess.file_exists(PATH_BAK):
		parsed = _read_file(PATH_BAK)
		if parsed != null:
			last_load_note = "Se recuperó la copia de seguridad del guardado."
			push_warning("[Save] Guardado principal dañado: se usa la copia de seguridad.")
	if parsed == null:
		if had_file:
			last_load_note = "El guardado estaba dañado y no se pudo recuperar. Se empezó de cero."
			push_warning("[Save] Guardado ilegible, se usan valores por defecto.")
		return
	data = _merge(defaults(), parsed)
	data["version"] = SAVE_VERSION
	_sanitize_after_load()


## Lee y valida un archivo de guardado. Devuelve el Dictionary de datos o null si no es válido.
func _read_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("[Save] No se pudo abrir %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return null
	var txt := f.get_as_text()
	f.close()
	return decode(txt)


## Decodifica el texto de un guardado (formato 2 con suma de control, o formato antiguo sin ella).
func decode(txt: String) -> Variant:
	var outer: Variant = JSON.parse_string(txt)
	if typeof(outer) != TYPE_DICTIONARY:
		return null
	var o: Dictionary = outer
	if o.has("payload") and o.has("sum"):
		var payload := String(o["payload"])
		if payload.sha256_text() != String(o["sum"]):
			return null
		var inner: Variant = JSON.parse_string(payload)
		return inner if typeof(inner) == TYPE_DICTIONARY else null
	# formato 1 (sin suma): se acepta si es un diccionario con "version" y "settings"
	if o.has("version") and o.has("settings"):
		return o
	return null


func encode(d: Dictionary) -> String:
	var payload := JSON.stringify(d)
	return JSON.stringify({"format": 2, "sum": payload.sha256_text(), "payload": payload})


## Guarda en disco de forma atómica. Devuelve true si el guardado quedó verificado.
func save_now() -> bool:
	_dirty = false
	var txt := encode(data)
	var f := FileAccess.open(PATH_TMP, FileAccess.WRITE)
	if f == null:
		push_warning("[Save] No se pudo escribir: %s" % error_string(FileAccess.get_open_error()))
		notice.emit("No se pudo guardar (no hay acceso al almacenamiento).", false)
		return false
	f.store_string(txt)
	f.flush()
	f.close()
	# verificación: se relee lo escrito y debe decodificar igual
	var check: Variant = _read_file(PATH_TMP)
	if check == null:
		push_warning("[Save] La verificación del guardado falló; se conserva el archivo anterior.")
		notice.emit("Error al guardar: el archivo no se verificó. Se conservó el guardado anterior.", false)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH_TMP))
		return false
	var dir := DirAccess.open("user://")
	if dir == null:
		notice.emit("Error al guardar: sin acceso al almacenamiento.", false)
		return false
	if dir.file_exists(PATH.get_file()):
		if dir.file_exists(PATH_BAK.get_file()):
			dir.remove(PATH_BAK.get_file())
		dir.rename(PATH.get_file(), PATH_BAK.get_file())
	var err := dir.rename(PATH_TMP.get_file(), PATH.get_file())
	if err != OK:
		# la copia buena sigue en .bak; se intenta restaurarla
		if dir.file_exists(PATH_BAK.get_file()) and not dir.file_exists(PATH.get_file()):
			dir.rename(PATH_BAK.get_file(), PATH.get_file())
		notice.emit("Error al guardar (%s)." % error_string(err), false)
		return false
	return true


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
		if _dirty:
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


# --- partida en curso (run) --------------------------------------------------
func _sanitize_after_load() -> void:
	# equipamiento / dificultad: ids válidos y desbloqueados (si no, valores por defecto)
	data["loadout"] = LoadoutDB.sanitize(data.get("loadout", {}))
	var did := String(data.get("difficulty", LoadoutDB.DEFAULT_DIFFICULTY))
	if not LoadoutDB.DIFFICULTIES.has(did):
		data["difficulty"] = LoadoutDB.DEFAULT_DIFFICULTY
	# partida guardada: si no pasa la validación se descarta
	var r: Variant = data.get("run", {})
	if typeof(r) == TYPE_DICTIONARY and not (r as Dictionary).is_empty():
		var why := validate_run(r)
		if why != "":
			push_warning("[Save] Partida guardada descartada: %s" % why)
			last_load_note = "La partida guardada no era válida y se descartó (%s)." % why
			data["run"] = {}
	else:
		data["run"] = {}


func has_valid_run() -> bool:
	var r: Variant = data.get("run", {})
	return typeof(r) == TYPE_DICTIONARY and not (r as Dictionary).is_empty() and validate_run(r) == ""


func get_run() -> Dictionary:
	return (data["run"] as Dictionary).duplicate(true) if has_valid_run() else {}


## Guarda la partida en curso y la escribe a disco. Devuelve true si quedó verificada.
func store_run(run: Dictionary) -> bool:
	var why := validate_run(run)
	if why != "":
		push_warning("[Save] No se guardó la partida: %s" % why)
		notice.emit("No se pudo guardar la partida (%s)." % why, false)
		return false
	data["run"] = run.duplicate(true)
	return save_now()


## Borra la partida guardada (al perder, abandonar o terminar una run).
func clear_run() -> void:
	if (data.get("run", {}) as Dictionary).is_empty():
		return
	data["run"] = {}
	save_now()


## Comprueba que una partida guardada es coherente. Devuelve "" si es válida o el motivo del rechazo.
func validate_run(r: Variant) -> String:
	if typeof(r) != TYPE_DICTIONARY:
		return "formato"
	var d: Dictionary = r
	if int(d.get("version", -1)) != RUN_VERSION:
		return "versión"
	var need_num := ["arena_index", "arena_seed", "coins", "kills", "xp", "level", "run_time", "hp", "shield", "revives_left"]
	for k in need_num:
		var t := typeof(d.get(k, null))
		if t != TYPE_INT and t != TYPE_FLOAT:
			return "falta " + k
	if not RUN_STAGES.has(String(d.get("stage", ""))):
		return "etapa"
	if int(d["arena_index"]) < 0 or int(d["arena_index"]) > 999:
		return "arena"
	if float(d["hp"]) <= 0.0:
		return "salud"       # una run con 0 de salud terminó: no se puede recuperar
	if float(d["coins"]) < 0.0 or float(d["kills"]) < 0.0 or float(d["run_time"]) < 0.0:
		return "valores negativos"
	if not LoadoutDB.DIFFICULTIES.has(String(d.get("difficulty", ""))):
		return "dificultad"
	if typeof(d.get("loadout", null)) != TYPE_DICTIONARY:
		return "equipamiento"
	for slot in LoadoutDB.SLOTS:
		var it := LoadoutDB.item(String((d["loadout"] as Dictionary).get(slot, "")))
		if it.is_empty() or String(it["slot"]) != slot:
			return "equipamiento"
	if typeof(d.get("picks", null)) != TYPE_ARRAY:
		return "mejoras"
	for p in d["picks"]:
		if typeof(p) != TYPE_DICTIONARY or UpgradeDB.get_def(String((p as Dictionary).get("id", ""))).is_empty():
			return "mejora desconocida"
		var rar := int((p as Dictionary).get("rarity", -1))
		if rar < 0 or rar > 3:
			return "rareza"
	if typeof(d.get("run_stats", null)) != TYPE_DICTIONARY:
		return "estadísticas"
	if typeof(d.get("player_pos", null)) != TYPE_ARRAY or (d["player_pos"] as Array).size() != 3:
		return "posición"
	return ""
