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
signal run_ended
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
		# --- contadores de la pantalla final (SOLO de la partida en curso; se guardan con ella y se reinician en una nueva) ---
		"hits": 0,              # impactos a enemigos (take_damage con daño aplicado; sin daño por quemadura)
		"damage_boss": 0.0,     # daño infligido a jefes (mismo cómputo que damage_dealt)
		"hurt": 0,              # veces que el jugador recibió daño
		"dmg_src": {},          # fuente -> daño infligido (para «fuente de daño más usada»)
		"coins_kill": 0, "coins_boss": 0,    # monedas COBRADAS procedentes de bajas / de jefes (tras bonus de monedas)
		"purchases": 0,         # compras en la tienda
		"chests": 0,            # cofres abiertos
		"boss_rewards": 0,      # botines especiales de jefe elegidos
		"waves": 0,             # oleadas completadas
		"revives_free": 0,      # «Segunda Opinión» consumidas
	}
	_rec_base = {}


func _apply_setup(lo: Dictionary, diff_id: String) -> void:
	loadout = LoadoutDB.sanitize(lo)
	difficulty_id = diff_id if LoadoutDB.DIFFICULTIES.has(diff_id) else LoadoutDB.DEFAULT_DIFFICULTY
	Scaling.set_difficulty(difficulty_id)
	weapon_params = LoadoutDB.weapon_params(loadout)
	build.loadout_stats = LoadoutDB.total_stats(loadout)
	refresh_hand_weapon()


## El objeto que sostiene el personaje sigue SIEMPRE a la herramienta realmente equipada (loadout), no al texto de la UI.
func hand_weapon_id() -> String:
	return String(loadout.get("weapon", "case"))


func refresh_hand_weapon() -> void:
	if player != null and is_instance_valid(player) and player.get("rig") != null:
		ModelFactory.set_hand_weapon(player.rig, hand_weapon_id())


## Récords al empezar la partida: así «nuevo récord» se decide contra lo anterior a ESTA partida, aunque se haya guardado a mitad.
var _rec_base := {}


func _capture_rec_base() -> void:
	var rec: Dictionary = SaveSystem.data["records"]
	_rec_base = {"best_arena": int(rec["best_arena"]), "best_kills": int(rec["best_kills"]),
		"best_time": float(rec["best_time"]), "best_score": int(rec["best_score"])}


func _reset_flush() -> void:
	_flushed = {"kills": 0, "bosses": 0, "playtime": 0.0, "damage": 0.0, "coins": 0, "cards": 0}
	_fees_paid = 0


## Reanimaciones por anuncio recompensado (máx. 2 por partida). Viven aquí, no en la escena: pausar, reiniciar la escena
## o pulsar repetidamente no las restablece; se guardan con la partida y solo una partida NUEVA las reinicia.
const MAX_AD_REVIVES := 2
var ad_revives_used := 0


func ad_revives_left() -> int:
	return maxi(0, MAX_AD_REVIVES - ad_revives_used)


## Consume UNA reanimación. Devuelve false (sin consumir nada) si ya no quedan.
func consume_ad_revive() -> bool:
	if ad_revives_used >= MAX_AD_REVIVES:
		return false
	ad_revives_used += 1
	return true


## Revierte lo que end_run() hizo al morir (muerte contabilizada, honorarios cobrados) cuando el jugador reanima.
func resume_after_defeat(sm: Dictionary) -> void:
	in_run = true
	var fees := int(sm.get("fees", 0))
	_fees_paid = maxi(0, _fees_paid - fees)
	var d := SaveSystem.data
	d["meta"]["fees"] = maxi(0, int(d["meta"]["fees"]) - fees)
	d["stats"]["deaths"] = maxi(0, int(d["stats"]["deaths"]) - 1)
	SaveSystem.save_now()


func start_run() -> void:
	ad_revives_used = 0
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
	_capture_rec_base()
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
		"hp": hp, "shield": sh, "revives_left": rv, "ad_revives": ad_revives_used,
		"player_pos": [pos.x, pos.y, pos.z],
		"picks": build.picks.duplicate(true),
		"run_stats": run_stats.duplicate(true),
		"flushed": _flushed.duplicate(),
		"fees_paid": _fees_paid,
		"rec_base": _rec_base.duplicate(),
		"shop_purchases": ShopUI.purchases,
		"perf": ({"result": ar.perf_result, "bonus": ar.bonus_chest_wanted, "bonus_taken": ar.bonus_taken, "main_taken": ar.chest_taken} if ar != null and ar.phase == Arena.Phase.CLEARED else {}),
		"saved_at": Time.get_unix_time_from_system(),
	}


## Restaura una partida guardada (ya validada por SaveSystem). No cuenta como partida nueva.
func restore_run(r: Dictionary) -> void:
	ad_revives_used = clampi(int(r.get("ad_revives", 0)), 0, MAX_AD_REVIVES)
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
	var rb: Variant = r.get("rec_base", null)
	if typeof(rb) == TYPE_DICTIONARY and not (rb as Dictionary).is_empty():
		_rec_base = (rb as Dictionary).duplicate()
	else:
		_capture_rec_base()
	var lo: Dictionary = r["loadout"]
	loadout = lo.duplicate()
	difficulty_id = String(r["difficulty"])
	Scaling.set_difficulty(difficulty_id)
	weapon_params = LoadoutDB.weapon_params(loadout)
	refresh_hand_weapon()
	var perm: Dictionary = SaveSystem.data["meta"]["perm"]
	build.restore(r["picks"], perm, LoadoutDB.total_stats(loadout), level)
	coins_changed.emit(coins)
	kills_changed.emit(kills)
	xp_changed.emit(xp, xp_to_next(), level)
	run_started.emit()


func score() -> int:
	return int(kills * 10 + run_stats["arenas"] * 150 + run_stats["bosses"] * 1000 + run_stats["coins_earned"] * 0.5)


func fees_for_run() -> int:
	var base := float(run_stats["arenas"]) * 18.0 + float(kills) * 0.6 + float(run_stats["bosses"]) * 90.0
	return int(round(base * Scaling.diff_x("fee_x")))


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


## Cierra la partida (solo por muerte o abandono; ya no existe la victoria): guarda récords, estadísticas y honorarios
## UNA sola vez (in_run lo impide) y devuelve el resumen que muestra la pantalla final.
func end_run() -> Dictionary:
	if not in_run:
		return {}
	in_run = false
	var fees := maxi(0, fees_for_run() - _fees_paid)
	_fees_paid += fees
	var d := SaveSystem.data
	d["meta"]["fees"] += fees
	flush_stats()
	d["stats"]["deaths"] += 1
	d["run"] = {}          # una partida terminada nunca se puede recuperar
	var rec: Dictionary = d["records"]
	if _rec_base.is_empty():
		_capture_rec_base()
	var base_arena := int(_rec_base["best_arena"])
	var summary := {
		"arena": arena_index + 1,
		"cycle": Scaling.cycle_of(arena_index) + 1,
		"kills": kills,
		"time": run_time,
		"score": score(),
		"fees": fees,
		"stats": run_stats.duplicate(true),
		"build": build.summary_lines(),
		"power": build.power_rating(),
		"difficulty": difficulty_id,
		"coins_left": coins,
		"upgrades": build.picks.size(),
		"synergies": build.active_synergies.size(),
		"revives": ad_revives_used + int(run_stats["revives_free"]),
		"ad_revives": ad_revives_used,
		# récords personales (guardados) y si esta partida los ha batido
		"best": {"arena": int(rec["best_arena"]), "kills": int(rec["best_kills"]), "time": float(rec["best_time"]), "score": int(rec["best_score"])},
		"new": {
			"arena": arena_index + 1 > base_arena,
			"kills": kills > int(_rec_base["best_kills"]),
			"time": run_time > float(_rec_base["best_time"]) + 0.01,
			"score": score() > int(_rec_base["best_score"]),
		},
		"unlocked": _newly_available(base_arena, int(rec["best_arena"])),
		"sources": damage_sources(),
	}
	SaveSystem.save_now()
	run_ended.emit()
	return summary


## Fuentes de daño agrupadas por categoría legible, de mayor a menor: [[nombre, daño], …]. Datos medidos en Enemy.take_damage.
func damage_sources() -> Array:
	var agg := {}
	var m: Dictionary = run_stats["dmg_src"]
	for k in m.keys():
		var lab := src_label(String(k))
		agg[lab] = float(agg.get(lab, 0.0)) + float(m[k])
	var out: Array = []
	for lab in agg.keys():
		out.append([lab, float(agg[lab])])
	out.sort_custom(func(a, b): return a[1] > b[1])
	return out


func src_label(src: String) -> String:
	match src:
		"case", "case_boom", "return_blast", "boomerang":
			return String(LoadoutDB.item(String(loadout.get("weapon", "case"))).get("name", "Maletín"))
		"case_mod":
			return "Mejoras del maletín"
		"docs", "docs_boom":
			return "Documentos Teledirigidos"
		"zone":
			return "Sello Mágico"
		"barrier", "barrier_blast":
			return "Objeción"
		"melee", "slam", "charge", "projectile", "hazard", "boss_death", "revive", "other", "":
			return "Otras fuentes"
	return "Efectos de mejoras"


## Objetos y dificultades cuyo requisito de «mejor arena» se cumplió POR PRIMERA VEZ en esta partida (desbloqueos permanentes
## que quedan disponibles; comprarlos sigue siendo en el Vestíbulo). Cálculo puro sobre datos reales, sin contar dos veces.
func _newly_available(base_arena: int, now_arena: int) -> Array:
	var out: Array = []
	for id in LoadoutDB.ITEMS.keys():
		var req := int(LoadoutDB.ITEMS[id]["req_arena"])
		if req > base_arena and req <= now_arena:
			out.append(String(LoadoutDB.ITEMS[id]["name"]))
	for id in LoadoutDB.DIFF_ORDER:
		var req2 := int(LoadoutDB.DIFFICULTIES[id]["req_arena"])
		if req2 > base_arena and req2 <= now_arena:
			out.append("Dificultad: " + String(LoadoutDB.DIFFICULTIES[id]["name"]))
	return out


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


## Contadores de daño infligido (los llama Enemy.take_damage: UN evento = UNA cuenta). 'burn' (quemadura continua) no cuenta como golpe.
func count_damage_dealt(dmg: float, src: String, is_boss: bool) -> void:
	if src != "burn":
		run_stats["hits"] += 1
	if is_boss:
		run_stats["damage_boss"] += dmg
	var key := src if src != "" else "other"
	var m: Dictionary = run_stats["dmg_src"]
	m[key] = float(m.get(key, 0.0)) + dmg


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
