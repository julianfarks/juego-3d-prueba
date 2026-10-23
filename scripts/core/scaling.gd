class_name Scaling
extends RefCounted
## Sistema CENTRALIZADO de escalado de dificultad.
## Todos los enemigos piden aquí sus multiplicadores; nada se ajusta enemigo por enemigo.
## Valores configurables en Config.SCALING (+ multiplicador manual del modo desarrollador).

const KIND_ELIMINATION := "elimination"
const KIND_SURVIVAL := "survival"
const KIND_CHALLENGE := "challenge"
const KIND_ELITE := "elite"
const KIND_BOSS := "boss"
const KINDS := [KIND_ELIMINATION, KIND_SURVIVAL, KIND_CHALLENGE, KIND_ELITE, KIND_BOSS]

# Coste en "puntos de oleada" y arena mínima (índice global) para aparecer.
const ENEMY_COST := {
	"thief": 1.0, "runner": 1.3, "ranged": 1.7, "tank": 3.2, "summoner": 3.6, "elite": 7.5,
}
const ENEMY_MIN_ARENA := {
	"thief": 0, "runner": 1, "ranged": 2, "tank": 3, "summoner": 5, "elite": 99,
}

static var dev_mult := 1.0   # multiplicador manual (modo desarrollador)
static var diff_id := "associate"   # dificultad de la partida (la fija GameState al empezar/cargar)


static func set_difficulty(id: String) -> void:
	diff_id = id if LoadoutDB.DIFFICULTIES.has(id) else LoadoutDB.DEFAULT_DIFFICULTY


## Multiplicador de la dificultad elegida: "hp_x", "dmg_x", "count_x", "reward_x" o "fee_x".
static func diff_x(key: String) -> float:
	return float(LoadoutDB.diff(diff_id)[key])


static func zone_len() -> int:
	return int(Config.SCALING["arenas_per_zone"])


static func cycle_of(arena_index: int) -> int:
	return arena_index / zone_len()


static func zone_pos(arena_index: int) -> int:
	return arena_index % zone_len()


static func kind_of(arena_index: int) -> String:
	return KINDS[zone_pos(arena_index)]


static func hp_mult(arena_index: int) -> float:
	var c := Config.SCALING
	return (1.0 + float(c["hp_per_arena"]) * arena_index) * pow(float(c["hp_per_cycle"]), cycle_of(arena_index)) * dev_mult * diff_x("hp_x")


static func dmg_mult(arena_index: int) -> float:
	var c := Config.SCALING
	return (1.0 + float(c["dmg_per_arena"]) * arena_index) * pow(float(c["dmg_per_cycle"]), cycle_of(arena_index)) * (1.0 + (dev_mult - 1.0) * 0.5) * diff_x("dmg_x")


static func count_mult(arena_index: int) -> float:
	var c := Config.SCALING
	return (1.0 + float(c["count_per_arena"]) * arena_index + float(c["count_per_cycle"]) * cycle_of(arena_index)) * diff_x("count_x")


static func spawn_interval(arena_index: int) -> float:
	var c := Config.SCALING
	return maxf(float(c["spawn_interval_min"]), float(c["spawn_interval_base"]) * pow(float(c["spawn_interval_decay"]), arena_index))


static func speed_mult(arena_index: int) -> float:
	var c := Config.SCALING
	return minf(1.0 + float(c["speed_per_cycle"]) * cycle_of(arena_index) + 0.01 * arena_index, float(c["speed_cap"]))


static func reward_mult(arena_index: int) -> float:
	var c := Config.SCALING
	return (1.0 + float(c["reward_per_arena"]) * arena_index + float(c["reward_per_cycle"]) * cycle_of(arena_index)) * diff_x("reward_x")


## Probabilidad de que un enemigo normal reciba una variante peligrosa (afijo).
static func affix_chance(arena_index: int) -> float:
	return clampf((arena_index - 4) * 0.045 + cycle_of(arena_index) * 0.08, 0.0, 0.6)


## Puntos de oleada disponibles para una arena.
static func wave_budget(arena_index: int, wave_number: int) -> float:
	return (7.0 + 2.2 * wave_number) * count_mult(arena_index)


static func available_types(arena_index: int) -> Array:
	var out: Array = []
	for t in ENEMY_MIN_ARENA.keys():
		if t == "elite":
			continue
		if arena_index >= int(ENEMY_MIN_ARENA[t]):
			out.append(t)
	return out


static func coin_reward(arena_index: int) -> int:
	return int(round(float(Config.ECONOMY["chest_coins"]) * reward_mult(arena_index)))


static func describe(arena_index: int) -> String:
	return "Arena %d · Ciclo %d · Vida ×%.2f · Daño ×%.2f · Cantidad ×%.2f" % [
		arena_index + 1, cycle_of(arena_index) + 1, hp_mult(arena_index), dmg_mult(arena_index), count_mult(arena_index)]
