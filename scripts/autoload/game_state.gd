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

var look_delta := Vector2.ZERO   # gestos de cámara acumulados por la capa táctil
var kill_streak := 0
var streak_timer := 0.0
var run_stats := {}

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
		"skill2": [KEY_E],
		"skill3": [KEY_R],
		"interact": [KEY_F],
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


func start_run() -> void:
	in_run = true
	arena_index = 0
	kills = 0
	xp = 0
	level = 0
	run_time = 0.0
	kill_streak = 0
	streak_timer = 0.0
	reset_run_stats()
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


func score() -> int:
	return int(kills * 10 + run_stats["arenas"] * 150 + run_stats["bosses"] * 1000 + run_stats["coins_earned"] * 0.5)


func fees_for_run(victory: bool) -> int:
	var base := float(run_stats["arenas"]) * 18.0 + float(kills) * 0.6 + float(run_stats["bosses"]) * 90.0
	return int(round(base * (1.25 if victory else 1.0)))


## Cierra la partida: guarda récords, estadísticas y honorarios. Devuelve el resumen.
func end_run(victory: bool) -> Dictionary:
	if not in_run:
		return {}
	in_run = false
	var fees := fees_for_run(victory)
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
	}
	var d := SaveSystem.data
	d["meta"]["fees"] += fees
	var rec: Dictionary = d["records"]
	rec["best_arena"] = maxi(int(rec["best_arena"]), arena_index + 1)
	rec["best_cycle"] = maxi(int(rec["best_cycle"]), Scaling.cycle_of(arena_index) + 1)
	rec["best_kills"] = maxi(int(rec["best_kills"]), kills)
	rec["best_time"] = maxf(float(rec["best_time"]), run_time)
	rec["best_score"] = maxi(int(rec["best_score"]), score())
	var st: Dictionary = d["stats"]
	st["kills"] += kills
	st["coins"] += int(run_stats["coins_earned"])
	st["bosses"] += int(run_stats["bosses"])
	st["playtime"] += run_time
	st["damage"] += float(run_stats["damage_dealt"])
	st["cards"] += int(run_stats["cards"])
	if not victory:
		st["deaths"] += 1
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
