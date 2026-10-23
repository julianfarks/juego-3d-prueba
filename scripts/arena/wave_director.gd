class_name WaveDirector
extends RefCounted
## Planifica las oleadas de una arena según su tipo y el escalado centralizado (Scaling).
## No instancia nada: devuelve datos que ArenaManager ejecuta.

## Devuelve {"waves": Array[Array[String]], "survival_time": float, "hazards": bool, "boss": String}
static func plan(kind: String, index: int, rng: RandomNumberGenerator) -> Dictionary:
	var cycle := Scaling.cycle_of(index)
	var out := {"waves": [], "survival_time": 0.0, "hazards": false, "boss": "", "stream": false}
	match kind:
		Scaling.KIND_ELIMINATION:
			var n := 3 + (1 if cycle >= 1 else 0)
			for w in n:
				out["waves"].append(_compose(Scaling.wave_budget(index, w), index, rng))
		Scaling.KIND_SURVIVAL:
			out["survival_time"] = 40.0 + 6.0 * cycle
			out["stream"] = true
			out["hazards"] = index >= 3
		Scaling.KIND_CHALLENGE:
			out["boss"] = "miniboss"
			out["hazards"] = true
			out["waves"].append(_compose(Scaling.wave_budget(index, 0) * 0.5, index, rng))
			out["waves"].append(_compose(Scaling.wave_budget(index, 1) * 0.5, index, rng))
		Scaling.KIND_ELITE:
			var elites := 1 + (1 if index >= 8 else 0) + cycle
			var first: Array = []
			for i in elites:
				first.append("elite")
			out["waves"].append(first)
			out["waves"].append(_compose(Scaling.wave_budget(index, 1) * 0.7, index, rng))
			out["waves"].append(_compose(Scaling.wave_budget(index, 2) * 0.7, index, rng))
		Scaling.KIND_BOSS:
			out["boss"] = "boss"
	return out


## Compone una oleada gastando 'budget' puntos en tipos disponibles.
static func _compose(budget: float, index: int, rng: RandomNumberGenerator) -> Array:
	var types := Scaling.available_types(index)
	var list: Array = []
	var guard := 0
	while budget > 0.9 and guard < 60:
		guard += 1
		var t: String = types[rng.randi() % types.size()]
		# los tipos baratos pesan más para que haya masa de enemigos básicos
		if rng.randf() < 0.45:
			t = "thief" if rng.randf() < 0.7 else "runner" if types.has("runner") else "thief"
		var cost := float(Scaling.ENEMY_COST[t])
		if cost > budget + 0.5:
			continue
		budget -= cost
		list.append(t)
	list.shuffle()
	return list


## Tipo de enemigo para el flujo continuo de la arena de supervivencia.
static func stream_pick(index: int, rng: RandomNumberGenerator) -> String:
	var types := Scaling.available_types(index)
	var w := {}
	for t in types:
		w[t] = 1.0 / float(Scaling.ENEMY_COST[t])
	var total := 0.0
	for k in w:
		total += w[k]
	var r := rng.randf() * total
	for k in w:
		r -= w[k]
		if r <= 0.0:
			return k
	return "thief"


## Afijo aleatorio (o "") para enemigos normales.
static func roll_affix(index: int, kind: String, rng: RandomNumberGenerator) -> String:
	if kind in ["elite", "miniboss", "boss", "summoner"]:
		return ""
	if rng.randf() < Scaling.affix_chance(index):
		var keys: Array = EnemyDefs.AFFIXES.keys()
		return keys[rng.randi() % keys.size()]
	return ""
