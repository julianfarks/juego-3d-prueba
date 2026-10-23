class_name Perks
extends RefCounted
## Motor MODULAR de efectos de mejoras. Las mejoras son datos (UpgradeDB); aquí viven los pocos mecanismos
## reutilizables que las 200+ mejoras combinan, en vez de un sistema por mejora:
##   - DISPARADORES  "t:<evento>:<efecto>": al ocurrir un evento (golpe, crítico, baja, esquiva…) se aplica un efecto.
##   - CONDICIONES   "c:<condición>": bonus de daño % si se cumple la condición (contra quemados, a distancia…).
##   - FUENTES       "s:<fuente>": bonus de daño % a una fuente concreta (maletín, documentos, explosiones…).
##   - BUFFS         bonificaciones temporales que dan los disparadores (daño, prisa, velocidad, armadura, crítico).
## Build precalcula las listas (triggers/conds/srcs) al recalcular; nada se reconstruye por fotograma.

const EVENTS := ["hit", "crit", "kill", "slam", "skill", "dodge", "hurt", "shield_break", "arena_clear", "arena_start", "levelup", "t3", "t5", "t8", "t12"]
## Probabilidad por ocurrencia del evento (los eventos muy frecuentes no disparan siempre).
const CHANCE := {"hit": 0.12, "crit": 0.4, "kill": 0.3, "slam": 0.5, "hurt": 0.6}
const OVERSHIELD := 40.0               # escudo extra máximo que pueden dar los disparadores
const ICD := 0.35                      # segundos mínimos entre dos disparos del mismo (evento, efecto)
const TIMER_PERIOD := {"t3": 3.0, "t5": 5.0, "t8": 8.0, "t12": 12.0}

const EFFECTS := ["heal_pct", "heal_flat", "shield", "energy", "cdr", "buff_dmg", "buff_haste", "buff_speed", "buff_armor", "buff_crit",
	"nova", "nova_at", "chain", "burn_area", "slow_area", "mark_area", "stun_area", "coins", "xp", "missile", "pull", "push", "invuln",
	"reset_dodge", "boomerang", "freeze_area"]

const BUFF_CAPS := {"dmg": 1.2, "haste": 0.8, "speed": 0.6, "armor": 0.4, "crit": 0.5}
const BUFF_TIME := {"dmg": 4.0, "haste": 3.0, "speed": 3.0, "armor": 4.0, "crit": 4.0}

## Condiciones de daño (nombre -> descripción corta). La evaluación está en cond_met().
const CONDS := ["burning", "slowed", "frozen", "marked", "full", "wounded", "elite", "far", "near", "crowd", "alone", "lowhp", "fullhp",
	"shield", "barrier", "hasted", "moving", "still", "air", "streak", "combo", "energy", "rich", "boss_arena"]
const SOURCES := ["slam", "docs", "echo", "boomerang", "nova", "crit_explosion", "chain", "thorns", "trail", "seal", "barrier", "case", "firework", "frag"]
const CASE_SRCS := ["case"]

static var buffs: Dictionary = {}           # nombre -> {"t": segundos restantes, "v": valor}
static var _icd: Dictionary = {}            # "evento:efecto" -> segundos hasta poder volver a disparar
static var _timers: Dictionary = {}         # evento de reloj -> segundos acumulados
static var _depth := 0
static var fired_log: Array = []            # para las pruebas: [{event, effect, v}]
static var log_enabled := false


static func reset() -> void:
	buffs.clear()
	_icd.clear()
	_timers.clear()
	_depth = 0
	fired_log.clear()


# ----------------------------------------------------------------------------- buffs
static func add_buff(name: String, value: float, dur: float = -1.0) -> void:
	var cap: float = float(BUFF_CAPS.get(name, 1.0))
	var cur: float = float((buffs.get(name, {}) as Dictionary).get("v", 0.0))
	buffs[name] = {"t": dur if dur > 0.0 else float(BUFF_TIME.get(name, 3.0)), "v": minf(cap, cur + value)}


static func buff(name: String) -> float:
	var b: Dictionary = buffs.get(name, {})
	return float(b.get("v", 0.0))


## Llamado una vez por fotograma de física desde Player.
static func update(delta: float) -> void:
	for k in buffs.keys():
		buffs[k]["t"] -= delta
		if float(buffs[k]["t"]) <= 0.0:
			buffs.erase(k)
	for k in _icd.keys():
		_icd[k] -= delta
		if float(_icd[k]) <= 0.0:
			_icd.erase(k)
	var b: Build = GameState.build
	if b.trigger_events.is_empty():
		return
	for ev in TIMER_PERIOD.keys():
		if not b.trigger_events.has(ev):
			continue
		_timers[ev] = float(_timers.get(ev, 0.0)) + delta
		if float(_timers[ev]) >= float(TIMER_PERIOD[ev]):
			_timers[ev] = 0.0
			fire(ev, {})


# ----------------------------------------------------------------------------- disparadores
static func fire(event: String, ctx: Dictionary = {}) -> void:
	var b: Build = GameState.build
	if b == null or not b.trigger_events.has(event) or _depth >= 3:
		return
	var player = GameState.player
	if player == null or not is_instance_valid(player) or not player.alive:
		return
	_depth += 1
	var chance: float = float(CHANCE.get(event, 1.0))
	for t in b.triggers:
		if t["event"] != event:
			continue
		var key: String = "%s:%s" % [event, t["effect"]]
		if _icd.has(key):
			continue
		if chance < 1.0 and randf() > chance:
			continue
		_icd[key] = ICD if chance < 1.0 else 0.05
		apply_effect(String(t["effect"]), float(t["v"]), ctx)
		if log_enabled:
			fired_log.append({"event": event, "effect": t["effect"], "v": t["v"]})
	_depth -= 1


static func apply_effect(effect: String, v: float, ctx: Dictionary) -> void:
	var player = GameState.player
	if player == null or not is_instance_valid(player):
		return
	var slam: float = float(Config.SKILLS["slam"]["dmg"])
	var pos: Vector3 = player.global_position
	var enemy = ctx.get("enemy", null)
	var at: Vector3 = pos
	if enemy != null and is_instance_valid(enemy):
		at = enemy.global_position
	match effect:
		"heal_pct":
			player.heal(player.max_hp * v)
		"heal_flat":
			player.heal(v)
		"shield":
			# escudo temporal: permite hasta OVERSHIELD por encima del máximo (incluso sin escudo base)
			player.shield = minf(player.shield_max + OVERSHIELD, player.shield + v)
			player.emit_hp()
		"energy":
			player.skills.energy = minf(player.skills.energy_max, player.skills.energy + v)
		"cdr":
			player.skills.reduce_cooldowns(v)
		"buff_dmg":
			add_buff("dmg", v)
		"buff_haste":
			add_buff("haste", v)
		"buff_speed":
			add_buff("speed", v)
		"buff_armor":
			add_buff("armor", v)
		"buff_crit":
			add_buff("crit", v)
		"nova":
			Combat.explode(pos, 4.0 * Combat.area_mult(), slam * v, {"src": "nova"})
		"nova_at":
			Combat.explode(at, 3.0 * Combat.area_mult(), slam * v, {"src": "nova", "exclude": enemy})
		"chain":
			if enemy != null and is_instance_valid(enemy) and enemy.alive:
				Combat.chain_lightning(enemy, maxf(float(ctx.get("dmg", slam)), slam * 0.5) * v, 3)
			else:
				var nearest := Combat.nearest_enemy(pos, 12.0)
				if nearest != null:
					Combat.chain_lightning(nearest, slam * v, 3)
		"burn_area":
			for e in Combat.enemies_in_radius(pos, 5.0):
				e.apply_burn(v, 3.0)
		"slow_area":
			for e in Combat.enemies_in_radius(pos, 6.0):
				e.apply_slow(0.5, v)
		"freeze_area":
			for e in Combat.enemies_in_radius(pos, 4.5):
				if not e.is_boss:
					e.apply_freeze(v)
		"mark_area":
			for e in Combat.enemies_in_radius(pos, 7.0):
				e.apply_mark(v)
		"stun_area":
			for e in Combat.enemies_in_radius(pos, 4.5):
				e.take_damage(0.0, {"src": "stun", "silent": true, "stagger": v, "element": "phys", "knock": Vector3.ZERO})
		"coins":
			GameState.add_coins(maxi(1, int(round(v))), false)
		"xp":
			GameState.add_xp(v)
		"missile":
			if GameState.projectiles != null:
				var n := maxi(1, int(round(v)))
				var used: Array = []
				for i in n:
					var tgt := Combat.nearest_enemy(pos, 20.0, used)
					if tgt == null:
						break
					used.append(tgt)
					var d: Vector3 = (tgt.global_position - pos)
					d.y = 0.0
					d = d.normalized() if d.length() > 0.01 else Vector3.FORWARD
					GameState.projectiles.fire_doc(pos + Vector3(0, 1.35, 0) + d * 0.7, d + Vector3(0, 0.25, 0), float(Config.SKILLS["docs"]["dmg"]) * 0.8, tgt, float(Config.SKILLS["docs"]["speed"]), {"src": "docs", "skill": true, "flat": true})
		"pull":
			for e in Combat.enemies_in_radius(pos, 8.0):
				var d2: Vector3 = pos - e.global_position
				d2.y = 0.0
				if d2.length() > 1.5:
					e.take_damage(0.0, {"src": "pull", "silent": true, "knock": d2.normalized() * v, "element": "phys"})
		"push":
			for e in Combat.enemies_in_radius(pos, 5.5):
				var d3: Vector3 = e.global_position - pos
				d3.y = 0.0
				d3 = d3.normalized() if d3.length() > 0.05 else Vector3.FORWARD
				e.take_damage(0.0, {"src": "push", "silent": true, "knock": d3 * v, "element": "phys"})
		"invuln":
			player.iframes = maxf(player.iframes, v)
		"reset_dodge":
			player._dodge_cd = 0.0
		"boomerang":
			if GameState.projectiles != null:
				var tgt2 := Combat.nearest_enemy(pos, 14.0)
				var dir: Vector3 = player.facing_dir()
				if tgt2 != null:
					dir = (tgt2.global_position - pos)
					dir.y = 0.0
					dir = dir.normalized()
				GameState.projectiles.fire_boomerang(pos + Vector3(0, 1.1, 0), dir, slam * v, 8.0 * Combat.area_mult(), 1.0, {"src": "boomerang", "flat": false})


# ----------------------------------------------------------------------------- condiciones
static func cond_met(name: String, enemy: Node3D, opts: Dictionary) -> bool:
	var player = GameState.player
	match name:
		"burning": return enemy.burn_t > 0.0
		"slowed": return enemy.slow_t > 0.0
		"frozen": return enemy.freeze_t > 0.0
		"marked": return enemy.marked_t > 0.0
		"full": return enemy.hp_frac() > 0.85
		"wounded": return enemy.hp_frac() < 0.5
		"elite": return enemy.is_elite or enemy.is_boss
		"far", "near":
			if player == null:
				return false
			var d: Vector3 = enemy.global_position - player.global_position
			d.y = 0.0
			return d.length() > 9.0 if name == "far" else d.length() < 3.5
		"crowd": return int(opts.get("area_hits", 1)) >= 4
		"alone": return int(opts.get("area_hits", 1)) <= 1
		"lowhp": return player != null and player.hp < player.max_hp * 0.4
		"fullhp": return player != null and player.hp >= player.max_hp * 0.9
		"shield": return player != null and player.shield > 0.0
		"barrier": return player != null and player.skills.barrier_active
		"hasted": return player != null and (player.skills.dodge_haste_t > 0.0 or buff("haste") > 0.0)
		"moving": return player != null and Vector2(player.velocity.x, player.velocity.z).length() > 2.0
		"still": return player != null and Vector2(player.velocity.x, player.velocity.z).length() < 0.6
		"air": return player != null and not player.is_on_floor()
		"streak": return GameState.kill_streak >= 5
		"combo": return player != null and player.skills.combo_stacks >= 6
		"energy": return player != null and player.skills.energy >= player.skills.energy_max * 0.8
		"rich": return GameState.coins >= 150
		"boss_arena": return GameState.arena != null and String(GameState.arena.kind) == Scaling.KIND_BOSS
	return false


## Bonus de daño % por condiciones y fuente para este golpe (suma de todas las mejoras aplicables).
static func damage_bonus(enemy: Node3D, opts: Dictionary) -> float:
	var b: Build = GameState.build
	var pct := 0.0
	for c in b.conds:
		if cond_met(String(c[0]), enemy, opts):
			pct += float(c[1])
	var src: String = String(opts.get("src", ""))
	if src != "":
		pct += float(b.srcs.get(src, 0.0))
		if CASE_SRCS.has(src):                       # el maletín lanzado hereda las mejoras del antiguo golpe y del bumerán
			pct += float(b.srcs.get("slam", 0.0)) + float(b.srcs.get("boomerang", 0.0))
	pct += buff("dmg")
	return pct
