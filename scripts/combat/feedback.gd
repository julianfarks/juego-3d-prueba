class_name Feedback
extends RefCounted
## Punto ÚNICO de retroalimentación de daño: número flotante + sonido de impacto.
##
## Todo daño que recibe un enemigo (armas, habilidades, proyectiles, explosiones, cadenas,
## efectos periódicos, críticos, sinergias…) llega a Enemy.take_damage(), que ya trae el daño
## FINAL (Combat.calc + resistencia de élite) y llama a on_damage() una sola vez por evento.
## Así el número, el sonido y el daño aplicado salen del mismo evento y del mismo valor.
##
## El número muestra el daño completo del impacto aunque supere la vida restante
## (sobredaño); la vida solo se limita en el enemigo y el exceso no se transfiere.

const DOT_SRCS := ["burn", "zone"]                                  # daño periódico
const COMBO_SRCS := ["chain", "nova", "crit_explosion", "echo"]     # impactos encadenados por sinergias
const MASSIVE_ABS := 10000.0       # daño absoluto desde el que un impacto es "masivo"
const MASSIVE_FRAC := 0.35         # o fracción de la vida máxima del objetivo (con mínimo MASSIVE_MIN)
const MASSIVE_MIN := 150.0
const COMBO_WINDOW := 0.5
const COMBO_TIERS := [3, 6, 10, 15]

const C_NORMAL := Color(1.0, 1.0, 1.0)
const C_CRIT := Color(1.0, 0.72, 0.15)
const C_MASSIVE := Color(1.0, 0.35, 0.5)
const C_EXEC := Color(1.0, 0.25, 0.3)
const C_DOT_FIRE := Color(1.0, 0.5, 0.18)
const C_DOT := Color(0.62, 0.95, 0.5)

## Gancho de pruebas: cuando record = true cada evento queda en `event_log`.
static var record := false
static var event_log: Array = []
static var stats := {"events": 0, "silent": 0, "numbers": 0, "merged": 0, "dropped": 0, "sounds": 0, "kills": 0}

static var _combo_n := 0
static var _combo_t := -10.0
static var _combo_tier := 0
static var _last_variant := -1
static var _immune_t: Dictionary = {}


static func reset() -> void:
	event_log.clear()
	stats = {"events": 0, "silent": 0, "numbers": 0, "merged": 0, "dropped": 0, "sounds": 0, "kills": 0}
	_combo_n = 0
	_combo_t = -10.0
	_combo_tier = 0
	_immune_t.clear()


# --- formato -----------------------------------------------------------------
## 24 → "24" · 1250 → "1.250" · 2750000 → "2.750.000". Para cantidades astronómicas, "1,23e18".
static func fmt(value: float) -> String:
	if value >= 1.0e15:
		var e := int(floor(log(value) / log(10.0)))
		var m := value / pow(10.0, float(e))
		return ("%.2f" % m).replace(".", ",") + "e" + str(e)
	var n := int(round(value))
	if value > 0.0 and n < 1:
		n = 1
	var s := str(absi(n))
	var out := ""
	var cnt := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		cnt += 1
		if cnt % 3 == 0 and i > 0:
			out = "." + out
	return ("-" if n < 0 else "") + out


# --- clasificación -----------------------------------------------------------
static func is_massive(dmg: float, max_hp: float) -> bool:
	return dmg >= MASSIVE_ABS or (dmg >= MASSIVE_MIN and dmg >= MASSIVE_FRAC * maxf(1.0, max_hp))


## Estilo visual (sin tocar nodos): kind, texto, color, escala relativa, duración, prioridad…
static func classify(dmg: float, info: Dictionary, max_hp: float) -> Dictionary:
	var crit: bool = info.get("crit", false)
	var src: String = info.get("src", "")
	var element: String = info.get("element", "phys")
	var elem_col: Color = Combat.COLORS.get(element, C_NORMAL)
	var massive := is_massive(dmg, max_hp)
	var kind := "normal"
	var col := C_NORMAL
	var scale := 1.0
	var dur := 0.70
	var rise := 1.25
	var prio := 1
	if src == "execute":
		kind = "exec"
		col = C_EXEC
		scale = 1.35
		dur = 0.95
		rise = 1.5
		prio = 4
	elif crit:
		kind = "crit"
		col = C_CRIT
		scale = 1.35
		dur = 0.9
		rise = 1.55
		prio = 3
	elif DOT_SRCS.has(src):
		kind = "dot"
		col = C_DOT_FIRE if element == "fire" or src == "burn" else elem_col.lerp(C_DOT, 0.5)
		scale = 0.72
		dur = 0.85
		rise = 0.8
		prio = 0
	elif src == "chain":
		kind = "chain"
		col = elem_col
		scale = 0.9
		dur = 0.7
		prio = 2
	elif info.get("aoe", false) or int(info.get("area", 1)) > 1:
		kind = "aoe"
		col = elem_col if element != "phys" else Color(1.0, 0.9, 0.75)
		scale = 0.95
		prio = 2
	elif element != "phys" and Combat.COLORS.has(element):
		kind = "elem"
		col = elem_col
		prio = 2
	# tamaño: crece suavemente (logaritmo) con la cantidad, siempre acotado
	var mag := clampf(log(maxf(dmg, 10.0) / 10.0) / log(10.0), 0.0, 8.0)   # 0 a 8 órdenes de magnitud
	scale *= 1.0 + 0.07 * mag
	if massive:
		prio = maxi(prio, 4)
		scale *= 1.3
		dur += 0.25
		rise += 0.3
		if kind == "normal" or kind == "elem" or kind == "aoe" or kind == "chain":
			col = col.lerp(C_MASSIVE, 0.65)
	scale = clampf(scale, 0.7, 2.0)
	var txt := fmt(dmg)
	if crit or kind == "exec":
		txt += "!"
	return {"kind": kind, "text": txt, "color": col, "scale": scale, "dur": dur, "rise": rise,
		"prio": prio, "massive": massive, "crit": crit, "value": dmg}


# --- evento de daño -----------------------------------------------------------
## Llamado por Enemy.take_damage (y el muñeco de práctica) UNA vez por impacto real.
## dmg = daño final aplicado (antes de limitar a la vida restante) · hp_before = vida antes del golpe.
static func on_damage(enemy: Node3D, dmg: float, info: Dictionary, hp_before: float, max_hp: float, killed: bool) -> void:
	stats["events"] += 1
	if dmg <= 0.0 or info.get("silent", false):
		stats["silent"] += 1
		return
	var st := classify(dmg, info, max_hp)
	var src: String = info.get("src", "")
	var element: String = info.get("element", "phys")
	var vscale := 1.0
	var vs: Variant = enemy.get("vscale")
	if vs != null:
		vscale = float(vs)
	var is_boss: bool = bool(enemy.get("is_boss"))
	# --- número ---
	var shown := "off"
	var fx = GameState.fx
	if fx != null:
		var pos: Vector3 = enemy.global_position + Vector3(0, 2.1 * vscale, 0)
		shown = fx.spawn_number(pos, enemy.get_instance_id(), st)
		match shown:
			"new":
				stats["numbers"] += 1
			"merged":
				stats["merged"] += 1
			"dropped":
				stats["dropped"] += 1
	# --- impacto visual por familia + aviso de muerte ---
	if fx != null and not info.get("no_fx", false):
		if killed:
			fx.kill_banner(enemy.global_position, enemy.get_instance_id(), is_boss, vscale)
		fx.impact(enemy.global_position, String(st["kind"]), src, element, bool(st["massive"]), is_boss, vscale)
	# --- sonido ---
	var snd := _play_sound(enemy, st, src, element, killed, is_boss, vscale, info)
	# --- combos de sinergia ---
	if COMBO_SRCS.has(src):
		_combo_hit(enemy.global_position)
	if killed:
		stats["kills"] += 1
	if record:
		event_log.append({"id": enemy.get_instance_id(), "dmg": dmg, "applied": minf(dmg, hp_before), "text": st["text"],
			"kind": st["kind"], "crit": st["crit"], "massive": st["massive"], "src": src, "element": element,
			"killed": killed, "number": shown, "sound": snd, "hp_before": hp_before, "scale": st["scale"]})


static func _play_sound(enemy: Node3D, st: Dictionary, src: String, element: String, killed: bool,
		is_boss: bool, vscale: float, info: Dictionary) -> String:
	var pos: Vector3 = enemy.global_position
	var kind: String = st["kind"]
	var pitch := clampf(1.0 / sqrt(maxf(vscale, 0.5)), 0.82, 1.18)
	var name := ""
	var prio := AudioManager.P_HIT
	var db := -7.0
	if killed:
		name = "kill_boss" if is_boss else "kill"
		prio = AudioManager.P_BOSS if is_boss else AudioManager.P_KILL
		db = -2.0 if is_boss else -3.0
	elif kind == "dot":
		name = "dot_tick"
		prio = AudioManager.P_DOT
		db = -13.0
	elif src == "chain":
		return ""                       # el salto ya emite su propio zap; el combo lo gestiona _combo_hit
	elif info.get("aoe", false):
		return ""                       # la explosión ya suena una vez en conjunto
	elif is_boss:
		name = "hit_boss"
		prio = AudioManager.P_BOSS
		db = -3.5
	elif kind == "crit" or kind == "exec":
		name = "crit_1" if randi() % 2 == 0 else "crit"
		prio = AudioManager.P_CRIT
		db = -5.0
	elif st["massive"]:
		name = "hit_heavy"
		prio = AudioManager.P_ELEM
		db = -4.5
	elif kind == "elem":
		name = "hit_" + element if ["fire", "ice", "shock"].has(element) else _plain()
		prio = AudioManager.P_ELEM
		db = -6.5
	else:
		name = _plain()
	var ok: bool = AudioManager.combat_sfx(name, pos, db, prio, pitch)
	if ok:
		stats["sounds"] += 1
	# crítico a un jefe: capa extra de campanilla
	if ok and is_boss and kind == "crit" and not killed:
		AudioManager.combat_sfx("crit", pos, -9.0, AudioManager.P_CRIT, pitch * 1.05)
	return name if ok else ""


static func _plain() -> String:
	var v := randi() % 5
	if v == _last_variant:
		v = (v + 1 + randi() % 4) % 5
	_last_variant = v
	return "hit_%d" % v


## Cadena de impactos de sinergia: a partir de ciertos recuentos suena un "combo" que sube de tono.
static func _combo_hit(pos: Vector3) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _combo_t > COMBO_WINDOW:
		_combo_n = 0
		_combo_tier = 0
	_combo_t = now
	_combo_n += 1
	if _combo_tier < COMBO_TIERS.size() and _combo_n >= int(COMBO_TIERS[_combo_tier]):
		AudioManager.combat_sfx("combo", pos, -5.0, AudioManager.P_BOSS, 1.0 + 0.07 * float(_combo_tier), 0.02, 0.5)
		_combo_tier += 1
		stats["sounds"] += 1
		if record:
			event_log.append({"combo": true, "tier": _combo_tier, "n": _combo_n})


## "¡INMUNE!" y avisos: no son daño, no suenan, y se limitan por enemigo.
static func immune(enemy: Node3D) -> void:
	var fx = GameState.fx
	if fx == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var id := enemy.get_instance_id()
	if now - float(_immune_t.get(id, -10.0)) < 0.6:
		return
	_immune_t[id] = now
	var vs: Variant = enemy.get("vscale")
	var vscale := float(vs) if vs != null else 1.0
	fx.spawn_number(enemy.global_position + Vector3(0, 2.2 * vscale, 0), id,
		{"kind": "info", "text": "¡INMUNE!", "color": Color(0.7, 0.7, 0.8), "scale": 0.85, "dur": 0.7,
		"rise": 0.9, "prio": 2, "massive": false, "crit": false, "value": 0.0})
