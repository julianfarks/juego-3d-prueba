extends Node
## Estado global de la partida: monedas, experiencia, estadísticas, mejoras y señales.
## También registra las acciones de entrada (teclado + táctil usan las mismas acciones).

signal coins_changed(value: int)
signal kills_changed(value: int)
signal xp_changed(xp: int, to_next: int, level: int)
signal level_up(level: int)
signal arena_started(index: int, kind: String)
signal arena_cleared(index: int)
signal run_started
signal run_ended(victory: bool)
signal toast(text: String, color: Color)
signal boss_bar(visible: bool, boss_name: String, hp: float, max_hp: float)
signal objective_changed(text: String, progress: float)
signal kill_registered(enemy: Node)
signal player_hp_changed(hp: float, max_hp: float, shield: float, shield_max: float)
signal energy_changed(value: float, max_value: float)
signal build_changed

var in_run := false
var arena_index := 0
var coins := 0
var kills := 0
var xp := 0
var level := 0
var run_time := 0.0
var build: Build = Build.new()
var rng := RandomNumberGenerator.new()

var player: Node3D = null
var arena: Node = null
var fx: Node = null
var main: Node = null
var cam: Node = null
var projectiles: Node = null
var case_throw: Node = null          # CaseThrow: maletín bumerán (ataque principal)

var difficulty_id := "associate"     # dificultad de la partida en curso
var loadout: Dictionary = {}         # equipamiento de la partida en curso (ver LoadoutDB)
var weapon_params: Dictionary = {}   # parámetros del ataque primario según la herramienta equipada
var _flushed: Dictionary = {}        # parte de la partida ya volcada a las estadísticas permanentes
var _fees_paid := 0                  # honorarios ya cobrados en esta partida (la victoria permite seguir)

var look_delta := Vector2.ZERO   # gestos de cámara acumulados por la capa táctil
var kill_streak := 0
var streak_timer := 0.0
var run_stats := {}
## Rendimiento de la ronda en curso (v0.11): vida REAL perdida (sin contar curas ni escudo), vida al empezar y vida máxima.
var round_damage := 0.0
var round_start_hp := 0.0
var round_max_hp := 100.0
var round_perf: Dictionary = {}

var _last_stat_save := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.randomize()
	_register_actions()
	build.changed.connect(func(): build_changed.emit())
	reset_run_stats()


func _register_actions() -> void:
	var map := {
		"move_left": [KEY_A],
		"move_right": [KEY_D],
		"move_forward": [KEY_W],
		"move_back": [KEY_S],
		"look_left": [KEY_LEFT],
		"look_right": [KEY_RIGHT],
		"look_up": [KEY_UP],
		"look_down": [KEY_DOWN],
		"attack": [KEY_J, KEY_CTRL],
		"jump": [KEY_SPACE],
		"dodge": [KEY_SHIFT],
		"skill1": [KEY_Q],
		"interact": [KEY_F],
		"inventory": [KEY_I],
		"pause": [KEY_ESCAPE],
	}
	for action in map.keys():
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for key in map[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)


func reset_run_stats() -> void:
	run_stats = {
		"damage_dealt": 0.0, "damage_taken": 0.0, "crits": 0, "bosses": 0, "cards": 0,
		"coins_earned": 0, "coins_spent": 0, "best_streak": 0, "elites": 0, "arenas": 0,
		"highest_hit": 0.0,
	}


func _apply_setup(lo: Dictionary, diff_id: String) -> void:
	loadout = LoadoutDB.sanitize(lo)
	difficulty_id = diff_id if LoadoutDB.DIFFICULTIES.has(diff_id) else LoadoutDB.DEFAULT_DIFFICULTY
	Scaling.set_difficulty(difficulty_id)
	weapon_params = LoadoutDB.weapon_params(loadout)
	build.loadout_stats = LoadoutDB.total_stats(loadout)


func _reset_flush() -> void:
	_flushed = {"kills": 0, "bosses": 0, "playtime": 0.0, "damage": 0.0, "coins": 0, "cards": 0}
	_fees_paid = 0


func start_run() -> void:
	LawPerks.reset()
	if player != null:
		player.skills.practice = false
	in_run = true
	arena_index = 0
	kills = 0
	xp = 0
	level = 0
	run_time = 0.0
	kill_streak = 0
	streak_timer = 0.0
	reset_run_stats()
	_reset_flush()
	_apply_setup(LoadoutDB.equipped(), LoadoutDB.selected_difficulty())
	var perm: Dictionary = SaveSystem.data["meta"]["perm"]
	build.level = 0
	build.reset(perm)
	coins = int(perm.get("perm_coins", 0)) * 20
	SaveSystem.data["stats"]["runs"] += 1
	SaveSystem.mark_dirty()
	coins_changed.emit(coins)
	kills_changed.emit(kills)
	xp_changed.emit(xp, xp_to_next(), level)
	run_started.emit()


## Prepara el estado para probar el equipamiento en la Sala Central (sin partida en curso).
func prepare_practice() -> void:
	in_run = false
	_apply_setup(LoadoutDB.equipped(), LoadoutDB.selected_difficulty())
	var perm: Dictionary = SaveSystem.data["meta"]["perm"]
	build.level = 0
	build.reset(perm)
	if player != null:
		player.reset_for_run()
		player.skills.practice = true


## Foto de la partida actual para guardarla. 'stage': fight (al empezar la arena), reward (arena
## completada, cofre sin abrir) o portal (cofre abierto y cartas elegidas).
func snapshot_run(stage: String) -> Dictionary:
	flush_stats()      # la foto y las estadísticas permanentes siempre quedan coherentes
	var pl = player
	var pos := Vector3.ZERO
	var hp := 100.0
	var sh := 0.0
	var rv := 0
	if pl != null:
		pos = pl.global_position
		hp = float(pl.hp)
		sh = float(pl.shield)
		rv = int(pl.revives_left)
	var ar = arena
	return {
		"version": SaveSystem.RUN_VERSION,
		"stage": stage,
		"arena_index": arena_index,
		"arena_seed": int(ar.seed_used) if ar != null else 0,
		"chest_taken": stage == "portal",
		"difficulty": difficulty_id,
		"loadout": loadout.duplicate(),
		"coins": coins, "kills": kills, "xp": xp, "level": level, "run_time": run_time,
		"hp": hp, "shield": sh, "revives_left": rv,
		"player_pos": [pos.x, pos.y, pos.z],
		"picks": build.picks.duplicate(true),
		"run_stats": run_stats.duplicate(true),
		"flushed": _flushed.duplicate(),
		"fees_paid": _fees_paid,
		"shop_purchases": ShopUI.purchases,
		"perf": ({"result": ar.perf_result, "bonus": ar.bonus_chest_wanted, "bonus_taken": ar.bonus_taken, "main_taken": ar.chest_taken} if ar != null and ar.phase == Arena.Phase.CLEARED else {}),
		"saved_at": Time.get_unix_time_from_system(),
	}


## Restaura una partida guardada (ya validada por SaveSystem). No cuenta como partida nueva.
func restore_run(r: Dictionary) -> void:
	LawPerks.reset()
	if player != null:
		player.skills.practice = false
	in_run = true
	arena_index = int(r["arena_index"])
	kills = int(r["kills"])
	xp = int(r["xp"])
	level = int(r["level"])
	run_time = float(r["run_time"])
	coins = int(r["coins"])
	kill_streak = 0
	streak_timer = 0.0
	reset_run_stats()
	var rs: Dictionary = r["run_stats"]
	for k in rs.keys():
		run_stats[k] = rs[k]
	_reset_flush()
	var fl: Dictionary = r.get("flushed", {})
	for k in fl.keys():
		if _flushed.has(k):
			_flushed[k] = fl[k]
	_fees_paid = int(r.get("fees_paid", 0))
	var lo: Dictionary = r["loadout"]
	loadout = lo.duplicate()
	difficulty_id = String(r["difficulty"])
	Scaling.set_difficulty(difficulty_id)
	weapon_params = LoadoutDB.weapon_params(loadout)
	var perm: Dictionary = SaveSystem.data["meta"]["perm"]
	build.restore(r["picks"], perm, LoadoutDB.total_stats(loadout), level)
	coins_changed.emit(coins)
	kills_changed.emit(kills)
	xp_changed.emit(xp, xp_to_next(), level)
	run_started.emit()


func score() -> int:
	return int(kills * 10 + run_stats["arenas"] * 150 + run_stats["bosses"] * 1000 + run_stats["coins_earned"] * 0.5)


func fees_for_run(victory: bool) -> int:
	var base := float(run_stats["arenas"]) * 18.0 + float(kills) * 0.6 + float(run_stats["bosses"]) * 90.0
	return int(round(base * (1.25 if victory else 1.0) * Scaling.diff_x("fee_x")))


## Vuelca a las estadísticas permanentes lo ganado desde el último volcado (así los datos se
## conservan aunque se cierre la app, sin contar nada dos veces al reanudar una partida guardada).
func flush_stats() -> void:
	if _flushed.is_empty():
		_reset_flush()
	var d := SaveSystem.data
	var st: Dictionary = d["stats"]
	var cur := {
		"kills": kills, "bosses": int(run_stats["bosses"]), "playtime": run_time,
		"damage": float(run_stats["damage_dealt"]), "coins": int(run_stats["coins_earned"]), "cards": int(run_stats["cards"]),
	}
	for k in cur.keys():
		var delta: float = float(cur[k]) - float(_flushed[k])
		if delta > 0.0:
			if typeof(st[k]) == TYPE_FLOAT:
				st[k] = float(st[k]) + delta
			else:
				st[k] = int(st[k]) + int(round(delta))
			_flushed[k] = cur[k]
	var rec: Dictionary = d["records"]
	rec["best_arena"] = maxi(int(rec["best_arena"]), arena_index + 1)
	rec["best_cycle"] = maxi(int(rec["best_cycle"]), Scaling.cycle_of(arena_index) + 1)
	rec["best_kills"] = maxi(int(rec["best_kills"]), kills)
	rec["best_time"] = maxf(float(rec["best_time"]), run_time)
	rec["best_score"] = maxi(int(rec["best_score"]), score())


## Cierra la partida: guarda récords, estadísticas y honorarios. Devuelve el resumen.
func end_run(victory: bool) -> Dictionary:
	if not in_run:
		return {}
	in_run = false
	var fees := maxi(0, fees_for_run(victory) - _fees_paid)
	_fees_paid += fees
	var summary := {
		"victory": victory,
		"arena": arena_index + 1,
		"cycle": Scaling.cycle_of(arena_index) + 1,
		"kills": kills,
		"time": run_time,
		"score": score(),
		"fees": fees,
		"stats": run_stats.duplicate(),
		"build": build.summary_lines(),
		"power": build.power_rating(),
		"difficulty": difficulty_id,
	}
	var d := SaveSystem.data
	d["meta"]["fees"] += fees
	flush_stats()
	if victory:
		d["stats"]["wins"] += 1
	else:
		d["stats"]["deaths"] += 1
	d["run"] = {}          # una partida terminada nunca se puede recuperar
	SaveSystem.save_now()
	run_ended.emit(victory)
	return summary


# --- monedas -----------------------------------------------------------------
func add_coins(amount: int, apply_bonus := true) -> int:
	var n := amount
	if apply_bonus:
		n = int(round(amount * (1.0 + build.s("coin_pct"))))
	coins += n
	run_stats["coins_earned"] += n
	coins_changed.emit(coins)
	return n


func spend_coins(amount: int) -> bool:
	if amount < 0 or coins < amount:
		return false
	coins -= amount
	run_stats["coins_spent"] += amount
	coins_changed.emit(coins)
	return true


# --- experiencia -------------------------------------------------------------
func xp_to_next() -> int:
	return int(32 + 24 * pow(level, 1.2))


func add_xp(amount: float) -> void:
	xp += int(round(amount * (1.0 + build.s("xp_pct"))))
	var leveled := false
	while xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
		leveled = true
	xp_changed.emit(xp, xp_to_next(), level)
	if leveled:
		build.level = level
		build.recompute(false)
		level_up.emit(level)
		Perks.fire("levelup", {})
		AudioManager.sfx("levelup")
		toast.emit("¡Nivel de caso %d!" % (level + 1), Color(1, 0.85, 0.3))


# --- bajas -------------------------------------------------------------------
func register_kill(enemy: Node, xp_value: float, coin_value: int) -> void:
	kills += 1
	kill_streak += 1
	streak_timer = 4.0
	run_stats["best_streak"] = maxi(int(run_stats["best_streak"]), kill_streak)
	add_xp(xp_value)
	kills_changed.emit(kills)
	kill_registered.emit(enemy)


func _process(delta: float) -> void:
	if in_run and not get_tree().paused:
		run_time += delta
		if kill_streak > 0:
			streak_timer -= delta
			if streak_timer <= 0.0:
				kill_streak = 0


func toast_msg(text: String, color := Color.WHITE) -> void:
	toast.emit(text, color)
