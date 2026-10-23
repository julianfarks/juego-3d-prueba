class_name Combat
extends RefCounted
## Núcleo del sistema de daño del jugador: fórmula de daño, críticos, efectos de estado,
## procs de mejoras (cadena, explosiones, marcas...) y consecuencias de las bajas.
## TODAS las mejoras de UpgradeDB se aplican aquí o en Skills/Player/Enemy leyendo Build.s().

const COLORS := {
	"phys": Color(1, 1, 1), "fire": Color(1.0, 0.55, 0.2), "ice": Color(0.55, 0.9, 1.0),
	"shock": Color(1.0, 0.95, 0.4), "crit": Color(1.0, 0.72, 0.15), "mark": Color(0.85, 0.4, 1.0),
	"exec": Color(1.0, 0.25, 0.3),
}

static var _nova_depth := 0
static var _chain_guard := 0


static func arena_enemies() -> Array:
	if GameState.arena != null and GameState.arena.has_method("get_enemies"):
		return GameState.arena.get_enemies()
	return []


static func enemies_in_radius(center: Vector3, radius: float) -> Array:
	var out: Array = []
	var r2 := radius * radius
	for e in arena_enemies():
		if not is_instance_valid(e) or not e.alive:
			continue
		var d: Vector3 = e.global_position - center
		d.y = 0.0
		var rr: float = radius + e.body_radius
		if d.length_squared() <= rr * rr:
			out.append(e)
	return out


static func nearest_enemy(from: Vector3, max_dist := 40.0, exclude: Array = []) -> Node3D:
	var best: Node3D = null
	var best_d := max_dist * max_dist
	for e in arena_enemies():
		if not is_instance_valid(e) or not e.alive or exclude.has(e):
			continue
		var d: Vector3 = e.global_position - from
		d.y = 0.0
		var dd := d.length_squared()
		if dd < best_d:
			best_d = dd
			best = e
	return best


static func area_mult() -> float:
	return 1.0 + GameState.build.s("aoe_pct")


## Calcula el daño final de un golpe del jugador contra 'enemy'.
## opts: src, skill(bool), flat(bool), area_hits(int), force_crit(bool), no_crit(bool)
static func calc(enemy: Node3D, base: float, opts: Dictionary) -> Dictionary:
	var b: Build = GameState.build
	var skills = GameState.player.skills if GameState.player != null else null
	var dmg := base
	if opts.get("flat", true):
		dmg += b.s("flat_dmg")
	var pct := b.s("dmg_pct")
	pct += minf(float(GameState.coins) / 25.0 * b.s("coin_dmg"), 0.45)
	if skills != null:
		pct += float(skills.combo_stacks) * b.s("combo_dmg")
	var streak := minf(float(GameState.kill_streak), 10.0)
	pct += streak * b.s("streak_dmg")
	pct += (minf(float(opts.get("area_hits", 1)) - 1.0, 10.0)) * b.s("crowd_dmg") if b.s("crowd_dmg") > 0.0 else 0.0
	pct += b.s("move_speed") * b.s("speed_to_dmg")
	if enemy.hp_frac() < 0.35:
		pct += b.s("execute_pct")
	if enemy.is_elite or enemy.is_boss:
		pct += b.s("boss_dmg")
	dmg *= maxf(0.1, 1.0 + pct)
	dmg *= b.s("more_dmg_x")
	if b.has_synergy("war_machine") and GameState.kill_streak > 0:
		dmg *= 1.3
	if enemy.marked_t > 0.0:
		dmg *= 1.25
	if enemy.slow_t > 0.0 and b.s("syn_cold_zone") > 0.0:
		dmg *= 1.25
	if opts.get("skill", false):
		dmg *= b.s("skill_dmg_x")
	var crit := false
	if not opts.get("no_crit", false):
		var cc := 0.05 + b.s("crit_chance")
		crit = opts.get("force_crit", false) or randf() < cc
	if crit:
		dmg *= 1.75 + b.s("crit_mult")
	else:
		dmg *= maxf(0.2, 1.0 - b.s("noncrit_malus"))
	return {"damage": dmg, "crit": crit}


## Golpe del jugador a un enemigo con todos los procs. Devuelve true si lo mata.
static func player_hit(enemy: Node3D, base: float, opts: Dictionary) -> bool:
	if enemy == null or not is_instance_valid(enemy) or not enemy.alive:
		return false
	var b: Build = GameState.build
	var r := calc(enemy, base, opts)
	var dmg: float = r["damage"]
	var crit: bool = r["crit"]
	var info := {
		"crit": crit, "src": opts.get("src", "slam"),
		"knock": opts.get("knock", Vector3.ZERO), "element": opts.get("element", "phys"),
		"stagger": opts.get("stagger", 0.0),
	}
	GameState.run_stats["highest_hit"] = maxf(float(GameState.run_stats["highest_hit"]), dmg)
	if crit:
		GameState.run_stats["crits"] += 1
	var killed: bool = enemy.take_damage(dmg, info)
	var proc: bool = opts.get("proc", true)
	if proc and not killed and enemy.alive:
		_apply_procs(enemy, dmg, crit, opts)
	if crit and proc:
		_crit_effects(enemy, dmg, opts)
		if not killed and enemy.alive and b.s("syn_execute") > 0.0 and not enemy.is_boss and enemy.hp_frac() < 0.15:
			enemy.take_damage(enemy.hp + 1.0, {"crit": true, "src": "execute", "element": "phys", "knock": Vector3.ZERO})
			killed = true
	return killed or not enemy.alive


static func _apply_procs(enemy: Node3D, dmg: float, crit: bool, opts: Dictionary) -> void:
	var b: Build = GameState.build
	if b.s("burn_chance") > 0.0 and randf() < b.s("burn_chance") + (0.0 if not opts.get("force_burn", false) else 1.0):
		enemy.apply_burn(b.s("burn_dps") * (1.0 + b.s("dmg_pct") * 0.5), 3.0)
	if b.s("slow_chance") > 0.0 and randf() < b.s("slow_chance"):
		enemy.apply_slow(0.45, 2.5)
	if b.s("freeze_chance") > 0.0 and randf() < b.s("freeze_chance") and not enemy.is_boss:
		enemy.apply_freeze(1.1)
	if b.s("mark_chance") > 0.0 and randf() < b.s("mark_chance"):
		enemy.apply_mark(4.0)
	if b.s("chain_chance") > 0.0 and randf() < b.s("chain_chance"):
		chain_lightning(enemy, dmg * 0.55, 2 + int(b.s("chain_count")))


static func _crit_effects(enemy: Node3D, dmg: float, opts: Dictionary) -> void:
	var b: Build = GameState.build
	if b.s("crit_explosion") > 0.0:
		var mult: float = b.s("crit_explosion")
		if b.s("syn_docs_crit") > 0.0 and opts.get("src", "") == "docs":
			mult *= 2.0
		explode(enemy.global_position, 2.6 * area_mult(), dmg * mult * 0.5, {"src": "crit_explosion", "exclude": enemy})
	if b.s("crit_cdr") > 0.0 and GameState.player != null:
		GameState.player.skills.reduce_cooldowns(b.s("crit_cdr"))


## Explosión de área (daño directo, sin críticos propios para no desbalancear).
static func explode(pos: Vector3, radius: float, damage: float, opts: Dictionary = {}) -> void:
	var fx = GameState.fx
	if fx != null:
		fx.ring(pos, radius, Color(1.0, 0.7, 0.2, 0.85), 0.35, 0.3)
		fx.flash_sphere(pos + Vector3(0, 0.6, 0), radius * 0.55, Color(1.0, 0.8, 0.35, 0.7), 0.22)
		fx.burst(pos + Vector3(0, 0.5, 0), Color(1.0, 0.75, 0.25), 8, 6.0, 0.14, 0.45)
	AudioManager.sfx_at("explosion", pos, -4.0)
	var exclude = opts.get("exclude", null)
	var hits := enemies_in_radius(pos, radius)
	for e in hits:
		if e == exclude:
			continue
		var dir: Vector3 = (e.global_position - pos)
		dir.y = 0.0
		dir = dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
		var o := {"src": opts.get("src", "explosion"), "no_crit": true, "flat": false, "proc": false,
			"knock": dir * 4.0, "area_hits": hits.size(), "element": opts.get("element", "fire")}
		var r := calc(e, damage, o)
		var killed: bool = e.take_damage(r["damage"], {"crit": false, "src": o["src"], "knock": o["knock"], "element": o["element"]})
		if not killed and opts.get("burn", false):
			e.apply_burn(GameState.build.s("burn_dps") + 6.0, 3.0)


static func chain_lightning(from_enemy: Node3D, damage: float, jumps: int) -> void:
	if _chain_guard > 40:
		return
	_chain_guard += 1
	var hit: Array = [from_enemy]
	var cur := from_enemy
	var fx = GameState.fx
	var mark: bool = GameState.build.s("syn_chain_mark") > 0.0
	for i in jumps:
		var nxt := nearest_enemy(cur.global_position, 7.0, hit)
		if nxt == null:
			break
		var a: Vector3 = cur.global_position + Vector3(0, 1.0, 0)
		var c: Vector3 = nxt.global_position + Vector3(0, 1.0, 0)
		if fx != null:
			fx.beam(a, c, Color(0.7, 0.9, 1.0, 0.95), 0.1, 0.18)
			fx.burst(c, Color(0.8, 0.95, 1.0), 4, 4.0, 0.1, 0.3)
		AudioManager.sfx_at("zap", c, -6.0)
		var o := {"src": "chain", "proc": false, "element": "shock", "flat": false, "no_crit": true, "knock": Vector3.ZERO}
		var r := calc(nxt, damage, o)
		nxt.take_damage(r["damage"], {"crit": false, "src": "chain", "element": "shock", "knock": Vector3.ZERO})
		if mark and nxt.alive:
			nxt.apply_mark(4.0)
		hit.append(nxt)
		cur = nxt
		damage *= 0.85
	_chain_guard -= 1


## Se llama cuando un enemigo muere por daño del jugador (cualquier fuente).
static func on_kill(enemy: Node3D, info: Dictionary) -> void:
	var b: Build = GameState.build
	var player = GameState.player
	if player == null:
		return
	if b.s("kill_heal") > 0.0:
		player.heal_limited(b.s("kill_heal"))
	if b.s("kill_energy") > 0.0:
		player.skills.add_energy_limited(b.s("kill_energy"))
	if b.s("kill_speed") > 0.0:
		player.kill_speed_t = 2.0
	var src: String = info.get("src", "")
	if b.s("kill_nova") > 0.0 and _nova_depth < 3:
		_nova_depth += 1
		var base: float = float(Config.SKILLS["slam"]["dmg"]) * b.s("kill_nova")
		var burn: bool = b.s("syn_nova_burn") > 0.0
		explode(enemy.global_position, 3.4 * area_mult(), base, {"src": "nova", "burn": burn, "exclude": enemy})
		_nova_depth -= 1
	if b.s("nth_kill_nova") > 0.0 and GameState.kills % 10 == 0 and GameState.kills > 0 and _nova_depth < 2:
		_nova_depth += 1
		var base2: float = float(Config.SKILLS["slam"]["dmg"]) * b.s("nth_kill_nova")
		explode(enemy.global_position, 7.0 * area_mult(), base2, {"src": "nova", "exclude": enemy})
		GameState.toast_msg("¡LA ÚLTIMA PALABRA!", Color(1.0, 0.5, 0.2))
		if GameState.cam != null:
			GameState.cam.shake(0.6)
		_nova_depth -= 1
	if src == "slam" and player != null and not player.skills.takeover_ready:
		pass
