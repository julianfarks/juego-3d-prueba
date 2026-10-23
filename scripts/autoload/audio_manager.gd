extends Node
## Audio: buses independientes (Music / SFX / Ambient), pool de reproductores,
## música con capas dinámicas (la capa intensa entra según la presión del combate).

const AUDIO_DIR := "res://assets/audio/"
const SFX_POOL := 18
const COMBAT_POOL := 14          ## voces simultáneas máximas de efectos de combate
const COMBAT_WINDOW := 0.10      ## ventana (s) del presupuesto de sonidos nuevos
const COMBAT_BUDGET := 5         ## sonidos de prioridad normal por ventana
const COMBAT_BUDGET_PRIO := 3    ## sonidos extra permitidos solo a prioridad alta (crítico, muerte, jefe, combo)
## Prioridades: 0 periódico · 1 golpe normal · 2 elemental/área · 3 crítico · 4 muerte · 5 jefe/combo
const P_DOT := 0
const P_HIT := 1
const P_ELEM := 2
const P_CRIT := 3
const P_KILL := 4
const P_BOSS := 5

var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_next := 0
var _cache: Dictionary = {}
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _boss_music: AudioStreamPlayer
var _menu_music: AudioStreamPlayer
var _main_music: AudioStreamPlayer     # canción principal (motion_to_chase) en bucle: menú, sala y combate
var _ambient: AudioStreamPlayer
var _current_music := "none"
var _intensity := 0.0
var _target_intensity := 0.0
var _fade: Dictionary = {}   # player -> volumen objetivo (lineal)
var _vol_cache: Dictionary = {}
var listener: Node3D = null   # nodo (cámara/jugador) para atenuar sonidos 3D
# --- capa de sonido de combate -----------------------------------------------
var _combat_players: Array[AudioStreamPlayer] = []
var _combat_prio: Array[int] = []
var _combat_t0: Array[float] = []
var _combat_next := 0
var _combat_recent: Array[float] = []     # instantes de los sonidos aceptados (ventana deslizante)
var _combat_last: Dictionary = {}         # clave -> último instante (antirrepetición)
var combat_stats := {"played": 0, "dropped": 0, "stolen": 0, "max_active": 0}
var record_combat := false                # gancho de pruebas: registra cada decisión
var combat_log: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	for i in SFX_POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_sfx_players.append(p)
	for i in COMBAT_POOL:
		var cp := AudioStreamPlayer.new()
		cp.bus = "Combat"
		add_child(cp)
		_combat_players.append(cp)
		_combat_prio.append(-1)
		_combat_t0.append(-10.0)
	_menu_music = _make_music("music_menu", "Music")
	_main_music = _make_music("music_main", "Music")
	_music_a = _make_music("music_combat_a", "Music")
	_music_b = _make_music("music_combat_b", "Music")
	_boss_music = _make_music("music_boss", "Music")
	_ambient = _make_music("amb_city", "Ambient")
	apply_volumes()


func _setup_buses() -> void:
	for bus_name in ["Music", "SFX", "Ambient", "Combat"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.get_bus_count() - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")
	# El bus de combate lleva un limitador: decenas de impactos a la vez no distorsionan.
	var ci := AudioServer.get_bus_index("Combat")
	if ci != -1 and AudioServer.get_bus_effect_count(ci) == 0 and ClassDB.class_exists("AudioEffectHardLimiter"):
		var lim = ClassDB.instantiate("AudioEffectHardLimiter")
		lim.ceiling_db = -1.5
		lim.pre_gain_db = 0.0
		AudioServer.add_bus_effect(ci, lim)


func _make_music(stream_name: String, bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	p.volume_db = -80.0
	var s := _load(stream_name)
	if s != null:
		if s is AudioStreamWAV:
			var w := s as AudioStreamWAV
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			var bytes_per := 2 if w.format == AudioStreamWAV.FORMAT_16_BITS else 1
			w.loop_end = w.data.size() / bytes_per / (2 if w.stereo else 1)
		elif s is AudioStreamMP3:
			(s as AudioStreamMP3).loop = true
		p.stream = s
	add_child(p)
	return p


func _load(stream_name: String) -> AudioStream:
	if _cache.has(stream_name):
		return _cache[stream_name]
	var path := AUDIO_DIR + stream_name + ".wav"
	if not ResourceLoader.exists(path) and ResourceLoader.exists(AUDIO_DIR + stream_name + ".mp3"):
		path = AUDIO_DIR + stream_name + ".mp3"
	var res: AudioStream = null
	if ResourceLoader.exists(path):
		res = load(path) as AudioStream
	else:
		push_warning("[Audio] Falta el recurso de audio: %s" % path)
	_cache[stream_name] = res
	return res


func apply_volumes() -> void:
	_set_bus("Music", float(SaveSystem.setting("music")))
	_set_bus("SFX", float(SaveSystem.setting("sfx")))
	_set_bus("Ambient", float(SaveSystem.setting("ambient")))
	_set_bus("Combat", float(SaveSystem.setting("combat_sfx")))


func _set_bus(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(idx, linear <= 0.001)


# --- SFX ---------------------------------------------------------------------
func sfx(stream_name: String, volume_db := 0.0, pitch_var := 0.06) -> void:
	var s := _load("sfx_" + stream_name)
	if s == null:
		return
	var p := _sfx_players[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx_players.size()
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.play()


func sfx_at(stream_name: String, pos: Vector3, volume_db := 0.0, pitch_var := 0.06) -> void:
	var db := volume_db
	if listener != null and is_instance_valid(listener):
		var d := listener.global_position.distance_to(pos)
		if d > 45.0:
			return
		db -= clampf((d - 6.0) * 0.55, 0.0, 22.0)
	sfx(stream_name, db, pitch_var)


## Sonido de combate con prioridad, presupuesto por ventana, antirrepetición y variación
## natural de volumen/tono. Devuelve true si se reprodujo. Nunca debe llamarse sin impacto real.
func combat_sfx(stream_name: String, pos: Vector3, volume_db := 0.0, prio := P_HIT, pitch := 1.0,
		pitch_var := 0.07, vol_var_db := 1.5) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	var verdict := _combat_admit(stream_name, pos, prio, now)
	if verdict != "":
		combat_stats["dropped"] += 1
		if record_combat:
			combat_log.append({"name": stream_name, "prio": prio, "played": false, "why": verdict, "t": now})
		return false
	var s := _load("sfx_" + stream_name)
	if s == null:
		return false
	var slot := _combat_slot(prio)
	if slot < 0:
		combat_stats["dropped"] += 1
		if record_combat:
			combat_log.append({"name": stream_name, "prio": prio, "played": false, "why": "voces", "t": now})
		return false
	# densidad: cuantos más sonidos recientes, más se baja cada uno (evita saturación)
	var density := float(_combat_recent.size())
	var db := volume_db - minf(density * 1.1, 6.0) + randf_range(-vol_var_db, vol_var_db)
	if listener != null and is_instance_valid(listener):
		db -= clampf((listener.global_position.distance_to(pos) - 6.0) * 0.55, 0.0, 22.0)
	var p := _combat_players[slot]
	p.stream = s
	p.volume_db = db
	p.pitch_scale = clampf(pitch * (1.0 + randf_range(-pitch_var, pitch_var)), 0.6, 1.8)
	p.play()
	_combat_prio[slot] = prio
	_combat_t0[slot] = now
	_combat_recent.append(now)
	_combat_last[stream_name] = now
	combat_stats["played"] += 1
	var active := 0
	for q in _combat_players:
		if q.playing:
			active += 1
	combat_stats["max_active"] = maxi(int(combat_stats["max_active"]), active)
	if record_combat:
		combat_log.append({"name": stream_name, "prio": prio, "played": true, "why": "", "t": now, "db": db, "pitch": p.pitch_scale})
	return true


## "" = admitido; si no, el motivo del descarte.
func _combat_admit(stream_name: String, pos: Vector3, prio: int, now: float) -> String:
	if float(SaveSystem.setting("combat_sfx")) <= 0.001:
		return "silencio"
	if listener != null and is_instance_valid(listener) and listener.global_position.distance_to(pos) > 45.0:
		return "lejos"
	while not _combat_recent.is_empty() and now - _combat_recent[0] > COMBAT_WINDOW:
		_combat_recent.pop_front()
	var n := _combat_recent.size()
	if prio < P_CRIT:
		if n >= COMBAT_BUDGET:
			return "presupuesto"
	elif n >= COMBAT_BUDGET + COMBAT_BUDGET_PRIO:
		return "presupuesto"
	# antirrepetición: el mismo sonido no se dispara de nuevo en milisegundos
	var gap := 0.11 if prio == P_DOT else (0.03 if prio <= P_ELEM else 0.015)
	if _combat_last.has(stream_name) and now - float(_combat_last[stream_name]) < gap:
		return "repetido"
	return ""


## Voz libre; si no hay, roba la de menor prioridad (y más antigua) si es menor que la nueva.
func _combat_slot(prio: int) -> int:
	for k in COMBAT_POOL:
		var i := (_combat_next + k) % COMBAT_POOL
		if not _combat_players[i].playing:
			_combat_next = (i + 1) % COMBAT_POOL
			return i
	var best := -1
	for i in COMBAT_POOL:
		if _combat_prio[i] < prio and (best == -1 or _combat_prio[i] < _combat_prio[best]
				or (_combat_prio[i] == _combat_prio[best] and _combat_t0[i] < _combat_t0[best])):
			best = i
	if best != -1:
		combat_stats["stolen"] += 1
	return best


func combat_active_voices() -> int:
	var n := 0
	for q in _combat_players:
		if q.playing:
			n += 1
	return n


func reset_combat_stats() -> void:
	combat_stats = {"played": 0, "dropped": 0, "stolen": 0, "max_active": 0}
	combat_log.clear()
	_combat_recent.clear()
	_combat_last.clear()


func sfx_random(prefix: String, count: int, volume_db := 0.0) -> void:
	sfx("%s_%d" % [prefix, randi() % count], volume_db)


# --- Música ------------------------------------------------------------------
func play_music(kind: String) -> void:
	if kind == _current_music:
		return
	_current_music = kind
	for p in [_menu_music, _music_a, _music_b, _boss_music, _main_music]:
		_fade[p] = 0.0
	var has_main := _main_music != null and _main_music.stream != null
	match kind:
		"menu":
			_start(_main_music if has_main else _menu_music, 0.8 if has_main else 0.9)
		"combat" when has_main:
			_start(_main_music, 0.8)       # sin reiniciar si ya sonaba: el bucle continúa entre menú, sala y arenas
			_intensity = 0.0
		"combat":
			# Las dos capas se reinician a la vez para que queden sincronizadas.
			_music_a.stop()
			_music_b.stop()
			_start(_music_a, 0.85)
			_start(_music_b, 0.0)
			_intensity = 0.0
		"boss":
			_start(_boss_music, 0.95)
		_:
			pass
	if not _ambient.playing and _ambient.stream != null:
		_ambient.volume_db = linear_to_db(0.5)
		_ambient.play()


func _start(p: AudioStreamPlayer, target: float) -> void:
	_fade[p] = target
	if p.stream == null:
		return
	if not p.playing:
		p.volume_db = -80.0
		p.play()


func set_combat_intensity(v: float) -> void:
	_target_intensity = clampf(v, 0.0, 1.0)


func stop_music() -> void:
	play_music("none")


func _process(delta: float) -> void:
	_intensity = move_toward(_intensity, _target_intensity, delta * 0.35)
	for p in _fade.keys():
		var pl: AudioStreamPlayer = p
		var target: float = _fade[p]
		if pl == _music_b and _current_music == "combat":
			target = _intensity * 0.9
		var cur := db_to_linear(pl.volume_db) if pl.volume_db > -79.0 else 0.0
		cur = move_toward(cur, target, delta * 0.8)
		pl.volume_db = linear_to_db(cur) if cur > 0.001 else -80.0
		if cur <= 0.001 and target <= 0.0 and pl.playing and not (pl == _music_b and _current_music == "combat"):
			pl.stop()
