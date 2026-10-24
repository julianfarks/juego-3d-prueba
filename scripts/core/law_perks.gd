class_name LawPerks
extends RefCounted
## Efectos de la ampliación judicial (LawCatalog) y reglas de recompensa por rendimiento. Estado estático de la partida:
## se reinicia al empezar una partida (reset) y las cadenas/curas por ronda al empezar cada arena (on_round_start).
## Todo está acotado: cada efecto tiene tope duro (UpgradeDB.CAPS) y/o límite por ronda.

# --- reglas de recompensa (ver ArenaManager._evaluate_performance y Main._open_cards) ---
const PERF_MAX_LOSS := 0.20            # vida máxima perdida como mucho en la ronda para optar al cofre extra
const PERF_CHEST_CHANCE := 0.5         # prob. de cofre adicional si se cumple
const DOUBLE_CHANCE := 0.5             # prob. de que un cofre deje elegir dos recompensas

const OBJ_MAX_STACKS := 8
const OBJ_TIME := 5.0
const MEDIC_EVERY := 5
const MEDIC_CAP := 0.20                # curación máxima por ronda (fracción de la salud máxima)
const MEDIC_CAP_SYN := 0.30
const IMMUN_CD := 25.0
const IMMUN_FRAC := 0.12
const BLOCK_ICD := 1.0
const PAPER_RADIUS := 2.3
const PAPER_HIT_CD := 0.6

static var obj_stacks := 0
static var obj_t := 0.0
static var round_t := 0.0                         # segundos dentro de la ronda actual (Impulso Procesal)
static var _bill_t := 0.0
static var _season_t := 0.0
static var case_loot_round := 0                   # monedas del Maletín Cobrador cobradas en esta ronda (tope por ronda)
static var dodge_t := 0.0
static var dodge_next := false
static var kills_since_heal := 0
static var heal_round := 0.0
static var immun_cd := 0.0
static var block_icd := 0.0
static var throws := 0
static var gavel_count := 0               # para las pruebas
static var _papers: Node3D = null
static var _paper_ang := 0.0
static var _paper_cd: Dictionary = {}
static var _paper_n := 0
static var forced_roll := -1.0          # pruebas: fuerza la próxima tirada (0..1); -1 = aleatoria


static func reset() -> void:
	round_t = 0.0
	_bill_t = 0.0
	_season_t = 0.0
	case_loot_round = 0
	obj_stacks = 0
	obj_t = 0.0
	dodge_t = 0.0
	dodge_next = false
	kills_since_heal = 0
	heal_round = 0.0
	immun_cd = 0.0
	block_icd = 0.0
	throws = 0
	gavel_count = 0
	_paper_cd.clear()
	_free_papers()


## Tirada 0..1 de las reglas de recompensa (cofre extra, cofre doble, bloqueo). Las pruebas pueden fijarla con forced_roll.
static func roll() -> float:
	return forced_roll if forced_roll >= 0.0 else randf()


static func on_round_start() -> void:
	round_t = 0.0
	case_loot_round = 0
	obj_stacks = 0
	obj_t = 0.0
	kills_since_heal = 0
	heal_round = 0.0


# ------------------------------------------------------------------ combate
## Multiplicador de daño de los nuevos poderes para un golpe a 'enemy'. No consume nada (ver after_hit).
static func damage_mult(enemy: Node3D, opts: Dictionary) -> float:
	var b: Build = GameState.build
	var m := 1.0
	if b.s("law_final") > 0.0 and enemy.hp_frac() < 0.3:
		m *= 1.0 + b.s("law_final")
	if obj_stacks > 0 and b.s("law_obj") > 0.0:
		m *= 1.0 + float(obj_stacks) * b.s("law_obj")
	m *= time_mult()
	if b.s("law_dodge") > 0.0:
		if dodge_t > 0.0:
			m *= 1.0 + b.s("law_dodge")
		if dodge_next and opts.get("proc", true):
			m *= 1.6 if b.s("syn_law_dodge") > 0.0 else 1.4
	return m


## Daño extra por el paso del tiempo (Antigüedad, Impulso Procesal, Carga de Casos). Todo con tope.
static func time_mult() -> float:
	var b: Build = GameState.build
	var m := 1.0
	if b.s("law_tenure") > 0.0:
		m *= 1.0 + minf(GameState.run_time / 60.0, 20.0) * b.s("law_tenure")
	if b.s("law_momentum") > 0.0:
		m *= 1.0 + float(mini(int(round_t / 10.0), 10)) * b.s("law_momentum")
	if b.s("law_caseload") > 0.0:
		m *= 1.0 + minf(float(GameState.kills / 10) * b.s("law_caseload"), 0.6)
	return m


## Tras un golpe real del jugador: el "siguiente golpe" potenciado por Evasión Legal se consume una sola vez.
static func after_hit(opts: Dictionary) -> void:
	if dodge_next and opts.get("proc", true):
		dodge_next = false


static func crit_bonus(enemy: Node3D) -> float:
	var b: Build = GameState.build
	if b.s("syn_law_final") > 0.0 and enemy.hp_frac() < 0.3:
		return 1.4
	return 1.0


static func on_kill(_enemy: Node3D) -> void:
	var b: Build = GameState.build
	var pl = GameState.player
	if pl == null or not is_instance_valid(pl):
		return
	if b.s("law_obj") > 0.0:
		obj_stacks = mini(OBJ_MAX_STACKS, obj_stacks + 1)
		obj_t = OBJ_TIME
	if b.s("law_medic") > 0.0 and pl.alive:
		kills_since_heal += 1
		if kills_since_heal >= MEDIC_EVERY:
			kills_since_heal = 0
			var cap: float = (MEDIC_CAP_SYN if b.s("syn_law_medic") > 0.0 else MEDIC_CAP) * pl.max_hp
			var room: float = cap - heal_round
			if room > 0.0:
				var want: float = pl.max_hp * b.s("law_medic") * (1.5 if b.s("syn_law_medic") > 0.0 else 1.0)
				var before: float = pl.hp
				pl.heal(minf(want, room / (1.0 + b.s("heal_pow"))))
				heal_round += maxf(0.0, pl.hp - before)


static func on_dodge() -> void:
	var b: Build = GameState.build
	if b.s("law_dodge") > 0.0:
		dodge_t = 3.0
		dodge_next = true
		if b.s("syn_law_dodge") > 0.0 and b.s("law_obj") > 0.0:
			obj_stacks = mini(OBJ_MAX_STACKS, obj_stacks + 3)
			obj_t = OBJ_TIME


static func on_throw() -> void:
	throws += 1
	var b: Build = GameState.build
	var g := b.s("law_gavel")
	if g <= 0.0:
		return
	var interval := clampi(7 - int(g), 3, 7)
	if throws % interval != 0:
		return
	var pl = GameState.player
	if pl == null or not is_instance_valid(pl) or not pl.alive:
		return
	gavel_count += 1
	var dmg: float = float(Config.SKILLS["slam"]["dmg"]) * g
	Combat.explode(pl.global_position, 5.0 * Combat.area_mult(), dmg, {"src": "nova"})
	AudioManager.sfx("explosion", -4.0)
	if GameState.cam != null:
		GameState.cam.shake(0.25)
	GameState.toast_msg("¡MAZO JUDICIAL!", Color(1.0, 0.75, 0.3))


# ------------------------------------------------------------------ defensa
## ¿Bloquea este impacto el Blindaje de Expedientes? (máx. uno por segundo)
static func try_block() -> bool:
	var b: Build = GameState.build
	if b.s("law_block") <= 0.0 or block_icd > 0.0:
		return false
	if roll() < b.s("law_block"):
		block_icd = BLOCK_ICD
		return true
	return false


static func def_mult() -> float:
	return 1.0 - minf(GameState.build.s("law_def"), 0.35)


## El jugador perdió 'lost' de vida real de un solo golpe: Escudo de Inmunidad si fue grave (con recarga).
static func on_player_damaged(lost: float, max_hp: float) -> void:
	var b: Build = GameState.build
	var pl = GameState.player
	if pl == null:
		return
	if b.s("law_immun") > 0.0 and immun_cd <= 0.0 and lost >= max_hp * IMMUN_FRAC and pl.hp > 0.0:
		immun_cd = IMMUN_CD
		pl.iframes = maxf(pl.iframes, 1.2)
		pl.shield = minf(pl.shield_max + Perks.OVERSHIELD, pl.shield + b.s("law_immun"))
		pl.emit_hp()
		GameState.toast_msg("¡ESCUDO DE INMUNIDAD!", Color(0.5, 0.85, 1.0))
		AudioManager.sfx("shield", -2.0)
		if GameState.fx != null:
			GameState.fx.ring(pl.global_position, 4.0, Color(0.5, 0.85, 1.0, 0.9), 0.5, 0.4)


# ------------------------------------------------------------------ por fotograma
## Maletín Cobrador: monedas por enemigos golpeados al recuperar el maletín. Topes: por recuperación y por ronda.
static func case_loot_pay(hits: int, per_hit: int, arena_index: int) -> int:
	if hits <= 0 or per_hit <= 0:
		return 0
	var raw := mini(hits * per_hit, 2 + 2 * per_hit)
	var room := maxi(0, 40 + 6 * arena_index - case_loot_round)
	var pay := mini(raw, room)
	case_loot_round += pay
	return pay


static func update(delta: float) -> void:
	round_t += delta
	var pl = GameState.player
	var b: Build = GameState.build
	var fighting: bool = pl != null and is_instance_valid(pl) and pl.alive and GameState.arena != null and is_instance_valid(GameState.arena) and GameState.arena.phase == Arena.Phase.FIGHT
	if fighting and b.s("law_bill") > 0.0:
		_bill_t += delta
		if _bill_t >= 20.0:
			_bill_t = 0.0
			GameState.add_coins(int(b.s("law_bill")) * (1 + GameState.arena_index / 4))
	if fighting and b.s("law_season") > 0.0:
		_season_t += delta
		if _season_t >= 10.0:
			_season_t = 0.0
			pl.heal(pl.max_hp * minf(b.s("law_season"), 0.1))
	if obj_t > 0.0:
		obj_t -= delta
		if obj_t <= 0.0:
			obj_stacks = 0
	dodge_t = maxf(0.0, dodge_t - delta)
	immun_cd = maxf(0.0, immun_cd - delta)
	block_icd = maxf(0.0, block_icd - delta)
	_update_papers(delta)


static func _free_papers() -> void:
	if _papers != null and is_instance_valid(_papers):
		_papers.queue_free()
	_papers = null
	_paper_n = 0


static func paper_count() -> int:
	var b: Build = GameState.build
	var n := int(b.s("law_papers"))
	if n > 0 and b.s("syn_law_papers") > 0.0:
		n += 1
	return mini(n, 9)


static func _update_papers(delta: float) -> void:
	var pl = GameState.player
	var n := paper_count()
	if n <= 0 or pl == null or not is_instance_valid(pl) or not pl.alive or not pl.is_inside_tree():
		if _papers != null:
			_free_papers()
		return
	if _papers == null or not is_instance_valid(_papers) or _papers.get_parent() != pl or _paper_n != n:
		_free_papers()
		_papers = Node3D.new()
		_papers.name = "LawPapers"
		pl.add_child(_papers)
		_paper_n = n
		var mb := MeshBuilder.new()
		mb.box(Vector3(0.55, 0.05, 0.72), MeshBuilder.xf(), MeshBuilder.glow(Color(0.98, 0.97, 0.88), 0.35))
		mb.box(Vector3(0.38, 0.055, 0.04), MeshBuilder.xf(Vector3(0, 0.002, 0.12)), Color(0.45, 0.5, 0.65))
		mb.box(Vector3(0.38, 0.055, 0.04), MeshBuilder.xf(Vector3(0, 0.002, -0.02)), Color(0.45, 0.5, 0.65))
		var mesh := mb.build()
		for i in n:
			var mi := Mats.mesh_instance(mesh, Mats.world_material(), _papers)
			mi.name = "Paper%d" % i
	var syn := GameState.build.s("syn_law_papers") > 0.0
	var radius := PAPER_RADIUS * (1.2 if syn else 1.0)
	_paper_ang += delta * 3.4
	var hit_r := 0.8 + (0.35 if syn else 0.0)
	var dmg: float = float(Config.SKILLS["slam"]["dmg"]) * 0.5 * (1.3 if syn else 1.0)
	for k in _paper_cd.keys():
		_paper_cd[k] -= delta
		if float(_paper_cd[k]) <= 0.0:
			_paper_cd.erase(k)
	for i in n:
		var node := _papers.get_node_or_null("Paper%d" % i) as Node3D
		if node == null:
			continue
		var a := _paper_ang + TAU * float(i) / float(n)
		node.position = Vector3(cos(a) * radius, 1.0 + 0.12 * sin(_paper_ang * 2.0 + i), sin(a) * radius)
		node.rotation = Vector3(0.0, -a + _paper_ang * 2.0, 0.35)
		var wp := node.global_position
		for e in Combat.arena_enemies():
			if not is_instance_valid(e) or not e.alive:
				continue
			var key: int = e.get_instance_id()
			if _paper_cd.has(key):
				continue
			var d: Vector3 = e.global_position - wp
			d.y = 0.0
			if d.length() > hit_r + float(e.body_radius):
				continue
			_paper_cd[key] = PAPER_HIT_CD
			var out: Vector3 = e.global_position - pl.global_position
			out.y = 0.0
			out = out.normalized() if out.length() > 0.05 else Vector3.FORWARD
			Combat.player_hit(e, dmg, {"src": "docs", "flat": false, "proc": false, "knock": out * 2.0, "area_hits": 1, "skill": false})


# ------------------------------------------------------------------ economía
## Multiplicador de las monedas que suelta un enemigo al morir (Honorarios por Victoria y Cliente de Alto Perfil).
static func kill_coin_mult(e: Node) -> float:
	var b: Build = GameState.build
	var m := 1.0 + minf(b.s("law_fee_win"), 0.6)
	if (e.is_elite or e.is_boss) and b.s("law_vip") > 0.0:
		m += minf(b.s("law_vip"), 1.0)
	return m


static func advance_fee(index: int) -> int:
	var b: Build = GameState.build
	if b.s("law_adv") <= 0.0:
		return 0
	return int(round(minf(b.s("law_adv"), 6.0 + 2.0 * float(index))))


## Intereses del Bufete: solo al terminar una zona (arenas 5, 10, 15…), con tope por pago.
static func firm_interest(index: int, coins: int) -> int:
	var b: Build = GameState.build
	if b.s("law_firm") <= 0.0 or (index + 1) % 5 != 0:
		return 0
	return int(round(minf(float(coins) * b.s("law_firm"), 80.0)))


## Extra de Cliente de Alto Perfil al limpiar arenas especiales (élite, desafío, jefe).
static func vip_clear(index: int, kind: String) -> int:
	var b: Build = GameState.build
	if b.s("law_vip") <= 0.0 or kind == Scaling.KIND_ELIMINATION or kind == Scaling.KIND_SURVIVAL:
		return 0
	return int(round(minf(b.s("law_vip"), 1.0) * (15.0 + 3.0 * float(index))))


static func efficiency_coins(index: int) -> int:
	var b: Build = GameState.build
	if b.s("law_eff") <= 0.0:
		return 0
	var v := minf(b.s("law_eff") * (1.0 + 0.1 * float(index)), 120.0)
	if b.s("syn_law_eff") > 0.0:
		v *= 1.5
	return int(round(v))


# ------------------------------------------------------------------ rendimiento y cofres
## Resultado de la ronda: {"perfect": bool, "bonus_chest": bool, "lost": float, "limit": float}.
## 'lost' es la vida REAL perdida en la ronda (se acumula en Player.take_damage; curarse no la reduce).
static func evaluate(lost: float, round_max_hp: float, roll: float) -> Dictionary:
	var limit := round_max_hp * PERF_MAX_LOSS
	var perfect := lost <= limit + 0.0001
	return {"perfect": perfect, "bonus_chest": perfect and roll < PERF_CHEST_CHANCE, "lost": lost, "limit": limit}


static func roll_double(roll: float) -> bool:
	return roll < DOUBLE_CHANCE
