extends Node
## Audio: buses independientes (Music / SFX / Ambient), pool de reproductores,
## música con capas dinámicas (la capa intensa entra según la presión del combate).

const AUDIO_DIR := "res://assets/audio/"
const SFX_POOL := 18

var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_next := 0
var _cache: Dictionary = {}
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _boss_music: AudioStreamPlayer
var _menu_music: AudioStreamPlayer
var _ambient: AudioStreamPlayer
var _current_music := "none"
var _intensity := 0.0
var _target_intensity := 0.0
var _fade: Dictionary = {}   # player -> volumen objetivo (lineal)
var _vol_cache: Dictionary = {}
var listener: Node3D = null   # nodo (cámara/jugador) para atenuar sonidos 3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	for i in SFX_POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_sfx_players.append(p)
	_menu_music = _make_music("music_menu", "Music")
	_music_a = _make_music("music_combat_a", "Music")
	_music_b = _make_music("music_combat_b", "Music")
	_boss_music = _make_music("music_boss", "Music")
	_ambient = _make_music("amb_city", "Ambient")
	apply_volumes()


func _setup_buses() -> void:
	for bus_name in ["Music", "SFX", "Ambient"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.get_bus_count() - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")


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
		p.stream = s
	add_child(p)
	return p


func _load(stream_name: String) -> AudioStream:
	if _cache.has(stream_name):
		return _cache[stream_name]
	var path := AUDIO_DIR + stream_name + ".wav"
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


func sfx_random(prefix: String, count: int, volume_db := 0.0) -> void:
	sfx("%s_%d" % [prefix, randi() % count], volume_db)


# --- Música ------------------------------------------------------------------
func play_music(kind: String) -> void:
	if kind == _current_music:
		return
	_current_music = kind
	for p in [_menu_music, _music_a, _music_b, _boss_music]:
		_fade[p] = 0.0
	match kind:
		"menu":
			_start(_menu_music, 0.9)
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
