class_name CaseMods
extends Node3D
## ATAQUES SECUNDARIOS DEL MALETÍN (módulo de modificadores). El maletín sigue siendo el ataque principal (CaseThrow);
## este módulo añade ataques que viajan con él, salen de él o se activan al lanzar, impactar, rebotar y regresar.
##
## Ganchos que llama CaseThrow:   on_throw · case_tick · on_impact · on_bounce · on_catch · update · clear_all
## Cada ataque es un comportamiento distinto (no un simple cambio de color):
##   cuchillas (rectas, perforan)  · misiles (teledirigidos, explosión de área)  · rayos (instantáneos, varios objetivos)
##   órbita (cuchillas que giran alrededor del maletín) · expedientes (caen del cielo y explotan) · fantasma (copias
##   espectrales en CaseThrow)     · discos (curva, rodean al objetivo y vuelven) · láser (aviso + haz potente, recarga larga)
##   apertura (explosión al salir) · rayo de regreso · lluvia de cuchillas (al recuperar) · onda de choque (anillo + empuje)
##   granada de papeles (zona temporal) · persecución (proyectil que busca al siguiente enemigo).
## Límites de seguridad: MAX_SHOTS proyectiles vivos, MAX_ZONES zonas, MAX_BLADES cuchillas orbitales; los proyectiles
## derivados (gen 1: divididos, persecución, expedientes dirigidos) nunca generan más derivados -> sin cascadas infinitas.

const MAX_SHOTS := 36
const MAX_ZONES := 6
const MAX_BLADES := 18
const SRC := "case_mod"
const HIT_Y := 1.1

class Shot extends RefCounted:
	var node: Node3D
	var kind := ""                 # knife | missile | seeker | disc | file | split
	var vis := ""                  # malla: knife | missile | seeker | disc | file
	var pos := Vector3.ZERO
	var vel := Vector3.ZERO
	var life := 1.0
	var age := 0.0
	var dmg := 1.0
	var radius := 0.5
	var pierce := 0
	var hits: Array = []
	var homing := 0.0
	var target: Node3D = null
	var gen := 0                   # 0 original · 1 derivado (no puede dividirse ni generar más)
	var phase := 0                 # disco: 0 ida · 1 órbita · 2 regreso
	var center := Vector3.ZERO
	var from := Vector3.ZERO
	var ctrl := Vector3.ZERO
	var ang := 0.0
	var hitcd: Dictionary = {}
	var splash := 0.0
	var prof: Dictionary = {}

var ct: Node                          # CaseThrow
var shots: Array = []
var _pool: Dictionary = {}
var _meshes: Dictionary = {}
var _zones: Array = []
var _orbits: Dictionary = {}          # C -> {nodes:[], hit:{}}
var _lasers: Array = []
var _cd: Dictionary = {}
var _clock := 0.0
var counts := {"knives": 0, "missiles": 0, "rays": 0, "blade_hits": 0, "files": 0, "discs": 0, "lasers": 0, "opens": 0,
	"retrays": 0, "kfall": 0, "waves": 0, "zones": 0, "chases": 0, "splits": 0, "xtra": 0, "both": 0, "fission": 0,
	"capped": 0, "max_shots": 0, "ghost_orbits": 0, "sec_hits": 0, "file_seek": 0, "laser_knives": 0}


# ============================================================================ perfil (se congela al lanzar)
static func profile(b: Build) -> Dictionary:
	var p := {}
	var kn := int(b.s("bc_knife_n"))
	var rn := int(b.s("bc_ray_n"))
	p["m_knives"] = mini(int(b.s("bc_knife")) + kn, 10) if b.s("bc_knife") > 0.0 else 0
	p["m_blades"] = mini(int(b.s("bc_orbit")) + kn, 8) if b.s("bc_orbit") > 0.0 else 0
	p["m_kfall"] = mini(int(b.s("bc_kfall")) + 2 * kn, 16) if b.s("bc_kfall") > 0.0 else 0
	p["m_missiles"] = mini(int(b.s("bc_missile")) + int(b.s("bc_missile_n")), 8) if b.s("bc_missile") > 0.0 else 0
	p["m_rays"] = mini(int(b.s("bc_ray")) + rn, 7) if b.s("bc_ray") > 0.0 else 0
	p["m_retray"] = mini(int(b.s("bc_retray")) + rn, 7) if b.s("bc_retray") > 0.0 else 0
	p["m_files"] = mini(int(b.s("bc_files")), 8)
	p["m_ghosts"] = mini(int(b.s("bc_ghost")), 3)
	p["m_discs"] = mini(int(b.s("bc_disc")), 6)
	p["m_laser"] = mini(int(b.s("bc_laser")), 8)
	p["m_open"] = b.s("bc_open")
	p["m_wave"] = b.s("bc_wave")
	p["m_gren"] = b.s("bc_gren")
	p["m_chase"] = b.s("bc_chase")
	p["m_range"] = 1.0 + minf(b.s("bc_sec_range"), 1.2)
	p["m_pierce"] = int(b.s("bc_sec_pierce"))
	p["m_xtra"] = minf(b.s("bc_xtra"), 0.9)
	p["m_both"] = minf(b.s("bc_both"), 1.0)
	p["m_split"] = minf(b.s("bc_split"), 0.9)
	p["m_seek"] = minf(b.s("bc_seek"), 1.0)
	p["m_blast_n"] = mini(int(b.s("bc_blast_n")), 3)
	# multiplicadores de daño por nivel de cada ataque (+10% por nivel por encima del 1.º)
	for pair in [["k", "case_knives"], ["m", "case_missiles"], ["r", "case_rays"], ["o", "case_orbit"], ["f", "case_files"],
			["d", "case_discs"], ["l", "case_laser"], ["a", "case_retray"], ["w", "case_wave"], ["g", "case_gren"], ["c", "case_chase"], ["p", "case_open"]]:
		p["m_x_" + String(pair[0])] = 1.0 + 0.1 * float(maxi(b.count_of(String(pair[1])) - 1, 0))
	p["m_lv_laser"] = b.count_of("case_laser")
	# sinergias que alteran el comportamiento
	p["syn_knife_bounce"] = b.s("syn_knife_bounce") > 0.0
	p["syn_salvo"] = b.s("syn_salvo") > 0.0
	p["syn_storm"] = b.s("syn_storm") > 0.0
	p["syn_blastzone"] = b.s("syn_blastzone") > 0.0
	p["syn_expressray"] = b.s("syn_expressray") > 0.0
	p["syn_phantom"] = b.s("syn_phantom") > 0.0
	p["syn_fileseek"] = b.s("syn_fileseek") > 0.0
	p["syn_fission"] = b.s("syn_fission") > 0.0
	p["syn_laserknives"] = b.s("syn_laserknives") > 0.0
	return p


func active(p: Dictionary) -> bool:
	return int(p.get("m_knives", 0)) > 0 or int(p.get("m_missiles", 0)) > 0 or int(p.get("m_rays", 0)) > 0 or int(p.get("m_blades", 0)) > 0 \
		or int(p.get("m_files", 0)) > 0 or int(p.get("m_discs", 0)) > 0 or int(p.get("m_laser", 0)) > 0 or float(p.get("m_open", 0.0)) > 0.0 \
		or int(p.get("m_retray", 0)) > 0 or int(p.get("m_kfall", 0)) > 0 or float(p.get("m_wave", 0.0)) > 0.0 \
		or float(p.get("m_gren", 0.0)) > 0.0 or float(p.get("m_chase", 0.0)) > 0.0


func busy() -> bool:
	return not shots.is_empty() or not _zones.is_empty() or not _lasers.is_empty() or not _orbits.is_empty()


func clear_all() -> void:
	for s in shots:
		s.node.visible = false
	shots.clear()
	for z in _zones:
		if z["fx"] != null and GameState.fx != null:
			GameState.fx.cancel(z["fx"])
	_zones.clear()
	_lasers.clear()
	for c in _orbits.keys():
		_free_orbit(c)
	_orbits.clear()
	_cd.clear()


# ============================================================================ utilidades
func _on_cd(key: String, secs: float) -> bool:
	if _cd.has(key):
		return true
	_cd[key] = secs
	return false


func _budget(n: int) -> int:
	var free := MAX_SHOTS - shots.size()
	if free < n:
		counts["capped"] += n - maxi(free, 0)
	return clampi(free, 0, n)


func _extra(p: Dictionary, n: int, cap: int) -> int:
	# Proyectil Extra: probabilidad de sumar un proyectil más a la salva (una sola tirada por salva)
	if float(p["m_xtra"]) > 0.0 and randf() < float(p["m_xtra"]):
		counts["xtra"] += 1
		return mini(n + 1, cap)
	return n


func _ground(v: Vector3) -> Vector3:
	return Vector3(v.x, Terrain.ground_y(v.x, v.z) + HIT_Y, v.z)


func _mesh_for(vis: String) -> ArrayMesh:
	if _meshes.has(vis):
		return _meshes[vis]
	var b := MeshBuilder.new()
	match vis:
		"knife":      # hoja metálica alargada con mango oscuro
			b.box(Vector3(0.1, 0.035, 0.6), MeshBuilder.xf(Vector3(0, 0, 0.1)), Color(0.86, 0.9, 1.0))
			b.box(Vector3(0.07, 0.07, 0.2), MeshBuilder.xf(Vector3(0, 0, -0.32)), Color(0.18, 0.16, 0.2))
		"missile":    # cuerpo azul con punta y llama trasera
			b.cylinder(0.075, 0.075, 0.5, 6, MeshBuilder.xf(Vector3.ZERO, Vector3(90, 0, 0)), Color(0.25, 0.45, 0.9))
			b.sphere(0.09, 6, 4, MeshBuilder.xf(Vector3(0, 0, 0.3)), Color(0.95, 0.95, 1.0))
			b.sphere(0.11, 6, 4, MeshBuilder.xf(Vector3(0, 0, -0.3)), MeshBuilder.glow(Color(1.0, 0.6, 0.15), 1.0))
		"seeker":     # esfera violeta brillante
			b.sphere(0.17, 8, 6, MeshBuilder.xf(), MeshBuilder.glow(Color(0.8, 0.45, 1.0), 1.0))
		"disc":       # disco dorado plano
			b.cylinder(0.5, 0.5, 0.06, 12, MeshBuilder.xf(), Color(0.95, 0.78, 0.25))
			b.cylinder(0.3, 0.3, 0.09, 12, MeshBuilder.xf(), Color(0.55, 0.4, 0.1))
		"file":       # hoja de papel blanca
			b.box(Vector3(0.36, 0.025, 0.46), MeshBuilder.xf(), Color(0.97, 0.96, 0.88))
			b.box(Vector3(0.36, 0.03, 0.06), MeshBuilder.xf(Vector3(0, 0, 0.2)), Color(0.8, 0.2, 0.2))
		_:
			b.sphere(0.15, 6, 4, MeshBuilder.xf(), Color.WHITE)
	_meshes[vis] = b.build()
	return _meshes[vis]


func _acquire(vis: String) -> Shot:
	var list: Array = _pool.get(vis, [])
	for s in list:
		if not s.node.visible:
			s.hits = []
			s.hitcd = {}
			s.age = 0.0
			s.target = null
			s.phase = 0
			s.gen = 0
			s.splash = 0.0
			s.pierce = 0
			s.homing = 0.0
			return s
	var s2 := Shot.new()
	var n := Node3D.new()
	var mi := Mats.mesh_instance(_mesh_for(vis), Mats.world_material(), n)
	mi.material_override = Mats.world_material()
	add_child(n)
	s2.node = n
	s2.vis = vis
	list.append(s2)
	_pool[vis] = list
	return s2


func _place(s: Shot) -> void:
	s.node.visible = true
	s.node.global_position = s.pos
	shots.append(s)
	counts["max_shots"] = maxi(int(counts["max_shots"]), shots.size())


func _beam(a: Vector3, b: Vector3, col: Color, w: float, dur: float) -> void:
	if GameState.fx != null:
		GameState.fx.beam(a, b, col, w, dur)


func _sec_hit(e: Node3D, dmg: float, dir: Vector3, element: String, proc: bool) -> bool:
	## UN golpe de ataque secundario: pasa por Combat.player_hit (número flotante, sonido, críticos) y cura limitada.
	if e == null or not is_instance_valid(e) or not e.alive:
		return false
	counts["sec_hits"] += 1
	var killed: bool = Combat.player_hit(e, dmg, {"src": SRC, "knock": dir * 2.0, "area_hits": 1, "flat": false, "skill": false,
		"element": element, "proc": proc})
	LawPerks.on_secondary_hit()
	return killed


# ============================================================================ al lanzar
func on_throw(p: Dictionary, origin: Vector3, dir: Vector3, base: float) -> void:
	if not active(p):
		return
	var d := Vector3(dir.x, 0.0, dir.z)
	d = d.normalized() if d.length() > 0.01 else Vector3.FORWARD
	var o := _ground(origin)
	if int(p["m_knives"]) > 0:
		_volley_knives(p, o, d, base, int(p["m_knives"]), 1.0)
	if int(p["m_missiles"]) > 0:
		_volley_missiles(p, o, d, base, int(p["m_missiles"]) + (2 if bool(p["syn_salvo"]) else 0), 1.0)
	if bool(p["syn_salvo"]) and int(p["m_missiles"]) > 0 and int(p["fw"]) > 0:
		ct._launch_rockets(origin, null, base, p, 2)          # Misiles + Cohetes: salva adicional de proyectiles explosivos
	if int(p["m_discs"]) > 0:
		_volley_discs(p, o, d, base, int(p["m_discs"]), 1.0)
	if float(p["m_open"]) > 0.0 and ct._blast_ok():
		ct._note_blast()
		counts["opens"] += 1
		var rad := 3.4 * Combat.area_mult() * float(p["m_range"]) * (1.0 + 0.15 * minf(float(p["m_open"]), 4.0) - 0.15)
		Combat.explode(Vector3(origin.x, 0.2, origin.z), rad, base * 0.55 * float(p["m_open"]) * float(p["m_x_p"]), {"src": SRC, "soft": true})
	if int(p["m_laser"]) > 0:
		_try_laser(p, o, d, base)


func _volley_knives(p: Dictionary, o: Vector3, d: Vector3, base: float, n: int, frac: float) -> void:
	n = maxi(1, int(round(float(n) * frac)))
	n = _budget(_extra(p, n, 12))
	if n <= 0:
		return
	counts["knives"] += n
	var spread := minf(8.0 * float(n), 70.0)
	for i in n:
		var a := 0.0 if n == 1 else deg_to_rad(-spread * 0.5 + spread * float(i) / float(n - 1))
		_make_knife(p, o, d.rotated(Vector3.UP, a), base * 0.42 * float(p["m_x_k"]), 0)
	AudioManager.combat_sfx("shard", o, -6.0, AudioManager.P_HIT, 1.2, 0.1)


func _make_knife(p: Dictionary, pos: Vector3, dir: Vector3, dmg: float, gen: int, vis := "knife") -> Shot:
	var s := _acquire(vis)
	s.kind = "knife" if gen == 0 else "split"
	s.gen = gen
	s.pos = pos
	s.vel = dir * 24.0
	s.life = 13.0 * float(p["m_range"]) / 24.0
	s.dmg = dmg
	s.radius = 0.5
	s.pierce = 1 + int(p["m_pierce"])
	s.homing = float(p["m_seek"]) * 4.0
	s.prof = p
	_place(s)
	s.node.look_at(s.pos + s.vel, Vector3.UP)
	return s


func _volley_missiles(p: Dictionary, o: Vector3, d: Vector3, base: float, n: int, frac: float) -> void:
	n = maxi(1, int(round(float(n) * frac)))
	n = _budget(_extra(p, n, 10))
	if n <= 0:
		return
	counts["missiles"] += n
	var used: Array = []
	for i in n:
		var s := _acquire("missile")
		s.kind = "missile"
		var tgt := Combat.nearest_enemy(o, 16.0 * float(p["m_range"]), used)
		if tgt != null:
			used.append(tgt)
		var a := deg_to_rad(-55.0 + 110.0 * float(i) / float(maxi(n - 1, 1))) if n > 1 else 0.0
		s.pos = o
		s.vel = d.rotated(Vector3.UP, a) * 15.0     # salen en abanico y luego buscan
		s.life = 2.2 * float(p["m_range"])
		s.dmg = base * 0.7 * float(p["m_x_m"])
		s.radius = 0.55
		s.homing = 5.5
		s.target = tgt
		s.splash = 2.1 * (1.3 if bool(p["syn_salvo"]) else 1.0)
		s.prof = p
		_place(s)
	AudioManager.combat_sfx("fw_launch", o, -6.0, AudioManager.P_ELEM, 1.3, 0.06)


func _volley_discs(p: Dictionary, o: Vector3, d: Vector3, base: float, n: int, frac: float) -> void:
	n = maxi(1, int(round(float(n) * frac)))
	n = _budget(_extra(p, n, 6))
	if n <= 0:
		return
	counts["discs"] += n
	var used: Array = []
	for i in n:
		var tgt := Combat.nearest_enemy(o, 14.0 * float(p["m_range"]), used)
		var center: Vector3
		if tgt != null:
			used.append(tgt)
			center = tgt.global_position
		else:
			center = o + d.rotated(Vector3.UP, deg_to_rad(float(i) * 40.0 - 20.0 * float(n - 1))) * 7.0
		var s := _acquire("disc")
		s.kind = "disc"
		s.pos = o
		s.from = o
		s.center = _ground(center)
		var side := 1.0 if i % 2 == 0 else -1.0
		s.ctrl = (o + s.center) * 0.5 + (s.center - o).cross(Vector3.UP).normalized() * 5.0 * side
		s.age = 0.0
		s.phase = 0
		s.ang = 0.0
		s.life = 99.0
		s.dmg = base * 0.5 * float(p["m_x_d"])
		s.radius = 0.7
		s.pierce = 99
		s.target = tgt
		s.prof = p
		_place(s)


func _try_laser(p: Dictionary, o: Vector3, d: Vector3, base: float) -> void:
	var lv := int(p["m_lv_laser"])
	if _on_cd("laser", maxf(2.2, 5.0 - 0.5 * float(lv))):
		return
	var tgt := Combat.nearest_enemy(o, 16.0, [])
	var dd := d
	if tgt != null:
		dd = tgt.global_position - o
		dd.y = 0.0
		dd = dd.normalized() if dd.length() > 0.01 else d
	var length := 16.0 * float(p["m_range"])
	_lasers.append({"t": 0.4, "from": o, "to": o + dd * length, "dmg": base * 2.2 * float(p["m_x_l"]), "p": p})
	counts["lasers"] += 1
	_beam(o, o + dd * length, Color(1.0, 0.25, 0.2, 0.4), 0.07, 0.4)       # aviso: trayectoria marcada


func _fire_laser(l: Dictionary) -> void:
	var a: Vector3 = l["from"]
	var b: Vector3 = l["to"]
	_beam(a, b, Color(1.0, 0.35, 0.25, 0.95), 0.5, 0.2)
	_beam(a, b, Color(1.0, 0.95, 0.85, 1.0), 0.15, 0.2)
	AudioManager.combat_sfx("zap", a, -2.0, AudioManager.P_CRIT, 0.6, 0.04)
	var seg := b - a
	seg.y = 0.0
	var seg2 := seg.length_squared()
	for e in Combat.arena_enemies():
		if not is_instance_valid(e) or not e.alive:
			continue
		var rel: Vector3 = e.global_position - a
		rel.y = 0.0
		var t := clampf(rel.dot(seg) / maxf(seg2, 0.001), 0.0, 1.0)
		var dist := (rel - seg * t).length()
		if dist <= 0.9 + float(e.body_radius):
			_sec_hit(e, float(l["dmg"]), seg.normalized(), "fire", true)
	var lp: Dictionary = l["p"]
	if bool(lp["syn_laserknives"]) and int(lp["m_knives"]) > 0:
		# Láser + Cuchillas: el haz deja cuchillas a ambos lados de la trayectoria
		var dir := seg.normalized()
		for k in 2:
			var pos: Vector3 = a + seg * (0.35 + 0.3 * float(k))
			for sgn in [-1.0, 1.0]:
				if _budget(1) > 0:
					counts["laser_knives"] += 1
					_make_knife(lp, _ground(pos), dir.rotated(Vector3.UP, deg_to_rad(90.0) * float(sgn)), float(l["dmg"]) * 0.18, 1)


# ============================================================================ durante el vuelo (por maletín)
func case_tick(c, delta: float) -> void:
	var p: Dictionary = c.prof
	if not active(p):
		return
	var mod: Dictionary = c.mod
	var base: float = float(p["base"]) * c.dmg_mult
	# --- Rayos de la Fiscalía: pulsos mientras viaja (maletín principal) ---
	if int(p["m_rays"]) > 0 and c.main:
		mod["ray"] = float(mod.get("ray", 0.2)) + delta
		if float(mod["ray"]) >= 0.3:
			mod["ray"] = 0.0
			_ray_pulse(c.pos, int(p["m_rays"]), 8.0 * float(p["m_range"]), base * 0.5 * float(p["m_x_r"]), p, true)
	# --- Rayo de Regreso: pulsos mientras vuelve ---
	if int(p["m_retray"]) > 0 and c.main and c.state == "ret" and int(mod.get("rr_n", 0)) < 14:
		mod["rr"] = float(mod.get("rr", 0.0)) + delta
		var iv := 0.18 if bool(p["syn_expressray"]) else 0.36
		if float(mod["rr"]) >= iv:
			mod["rr"] = 0.0
			if _ray_pulse(c.pos, int(p["m_retray"]), 7.0 * float(p["m_range"]), base * 0.45 * float(p["m_x_a"]), p, false) > 0:
				mod["rr_n"] = int(mod.get("rr_n", 0)) + 1
				counts["retrays"] += 1
	# --- Lluvia de Expedientes: caen documentos por donde pasa ---
	if int(p["m_files"]) > 0 and c.main:
		mod["files"] = float(mod.get("files", 0.15)) + delta
		if float(mod["files"]) >= 0.28:
			mod["files"] = 0.0
			_drop_files(c.pos, int(p["m_files"]), base * 0.36 * float(p["m_x_f"]), p)


func _ray_pulse(from: Vector3, n: int, reach: float, dmg: float, p: Dictionary, chain_ok: bool) -> int:
	var used: Array = []
	var got := 0
	for i in n:
		var tgt := Combat.nearest_enemy(from, reach, used)
		if tgt == null:
			break
		used.append(tgt)
		got += 1
		counts["rays"] += 1
		var tp: Vector3 = tgt.global_position + Vector3(0, 1.0, 0)
		_beam(from, tp, Color(0.55, 0.85, 1.0, 0.95), 0.12, 0.16)
		if GameState.fx != null:
			GameState.fx.burst(tp, Color(0.8, 0.95, 1.0), 4, 4.0, 0.1, 0.3)
		var dir: Vector3 = (tgt.global_position - from)
		dir.y = 0.0
		_sec_hit(tgt, dmg, dir.normalized(), "shock", false)
		if got == 1 and chain_ok and bool(p["syn_storm"]) and is_instance_valid(tgt) and tgt.alive:
			Combat.chain_lightning(tgt, dmg * 0.6, 2)       # Rayos + Cadena Eléctrica: el rayo se encadena
	if got > 0:
		AudioManager.combat_sfx("zap", from, -8.0, AudioManager.P_ELEM, 1.1, 0.08)
	return got


func _drop_files(center: Vector3, n: int, dmg: float, p: Dictionary) -> void:
	n = _budget(_extra(p, n, 6))
	for i in n:
		var a := randf() * TAU
		var gp := center + Vector3(cos(a), 0.0, sin(a)) * randf_range(0.6, 3.2)
		var s := _acquire("file")
		s.kind = "file"
		s.gen = 1
		s.pos = Vector3(gp.x, 5.5, gp.z)
		s.vel = Vector3(0, -24.0, 0)
		s.life = 1.2
		s.dmg = dmg
		s.splash = 1.5
		s.prof = p
		counts["files"] += 1
		_place(s)
		s.node.rotation = Vector3(0, randf() * TAU, 0)
		# Expedientes + Persecución: algunos documentos buscan objetivos cercanos
		if bool(p["syn_fileseek"]) and randf() < 0.4:
			var tgt := Combat.nearest_enemy(gp, 12.0, [])
			if tgt != null:
				counts["file_seek"] += 1
				s.kind = "seeker"
				s.vis = "file"
				s.pos = _ground(gp)
				s.vel = (tgt.global_position - s.pos).normalized() * 18.0
				s.vel.y = 0.0
				s.target = tgt
				s.homing = 6.0
				s.life = 2.0
				s.splash = 1.5


# ============================================================================ al impactar / rebotar / recuperar
func on_impact(c, e: Node3D, base: float, ipos: Vector3) -> void:
	var p: Dictionary = c.prof
	if not active(p):
		return
	# Onda de Choque: anillo expansivo que empuja (una vez cada 0.7 s por maletín)
	if float(p["m_wave"]) > 0.0 and not _on_cd("wave%d" % c.idx, 0.7):
		_wave(ipos, p, base)
	# Granada de Papeles: zona temporal de daño (Detonación + Granada: siempre, mayor y con quemadura)
	if float(p["m_gren"]) > 0.0:
		var sure := bool(p["syn_blastzone"]) and float(p["blast"]) > 0.0
		if (sure or randf() < 0.5) and not _on_cd("gren%d" % c.idx, 0.9):
			_zone(ipos, p, base, sure)
	# Explosiones adicionales por impacto (Detonaciones Múltiples), con tope de explosiones por segundo
	if int(p["m_blast_n"]) > 0 and float(p["blast"]) > 0.0:
		for k in int(p["m_blast_n"]):
			if not ct._blast_ok():
				break
			ct._note_blast()
			var a := TAU * float(k) / float(maxi(int(p["m_blast_n"]), 1)) + randf() * 0.6
			var off := Vector3(cos(a), 0, sin(a)) * 2.2
			Combat.explode(ipos + off, (2.0 + float(p["blast_r"]) * 2.0) * Combat.area_mult(), base * float(p["blast"]) * 0.6, {"src": SRC, "soft": true})
	# Persecución Judicial: tras golpear, un proyectil busca al SIGUIENTE enemigo
	if float(p["m_chase"]) > 0.0 and randf() < float(p["m_chase"]) and not _on_cd("chase%d" % c.idx, 0.35):
		var nxt := Combat.nearest_enemy(ipos, 14.0 * float(p["m_range"]), [e])
		if nxt != null and _budget(1) > 0:
			var s := _acquire("seeker")
			s.kind = "seeker"
			s.gen = 1
			s.pos = _ground(ipos)
			var dv: Vector3 = nxt.global_position - s.pos
			dv.y = 0.0
			s.vel = dv.normalized() * 22.0
			s.life = 2.2
			s.dmg = base * 0.55 * float(p["m_x_c"])
			s.radius = 0.5
			s.homing = 7.0
			s.target = nxt
			s.hits = [e]
			s.prof = p
			counts["chases"] += 1
			_place(s)


func _wave(pos: Vector3, p: Dictionary, base: float) -> void:
	counts["waves"] += 1
	var rad := 3.6 * Combat.area_mult() * (1.0 + 0.5 * (float(p["m_range"]) - 1.0)) * (1.0 + 0.1 * minf(float(p["m_wave"]), 5.0))
	if GameState.fx != null:
		GameState.fx.ring(Vector3(pos.x, 0.1, pos.z), rad, Color(0.7, 0.9, 1.0, 0.9), 0.45, 0.4)
		GameState.fx.ring(Vector3(pos.x, 0.1, pos.z), rad * 0.7, Color(1.0, 1.0, 1.0, 0.6), 0.35, 0.3)
	AudioManager.combat_sfx("explosion", pos, -8.0, AudioManager.P_ELEM, 1.4, 0.05)
	var list: Array = Combat.enemies_in_radius(pos, rad)
	for e in list:
		var dv: Vector3 = e.global_position - pos
		dv.y = 0.0
		var dn := dv.normalized() if dv.length() > 0.01 else Vector3.FORWARD
		Combat.player_hit(e, base * 0.5 * float(p["m_wave"]) * float(p["m_x_w"]), {"src": SRC, "knock": dn * 9.0, "stagger": 0.3, "area_hits": list.size(), "flat": false, "skill": false, "proc": false, "no_crit": true})
		LawPerks.on_secondary_hit()
	counts["sec_hits"] += list.size()


func _zone(pos: Vector3, p: Dictionary, base: float, strong: bool) -> void:
	while _zones.size() >= MAX_ZONES:
		var old: Dictionary = _zones.pop_front()
		if old["fx"] != null and GameState.fx != null:
			GameState.fx.cancel(old["fx"])
	var r := 2.0 * Combat.area_mult() * (1.4 if strong else 1.0) * (1.0 + 0.4 * (float(p["m_range"]) - 1.0))
	var fxi = null
	if GameState.fx != null:
		fxi = GameState.fx.zone(Vector3(pos.x, 0.0, pos.z), r, 2.6, Color(1.0, 0.9, 0.5) if not strong else Color(1.0, 0.55, 0.2))
	counts["zones"] += 1
	_zones.append({"pos": Vector3(pos.x, 0.0, pos.z), "r": r, "t": 0.0, "dur": 2.6, "tick": 0.0, "fx": fxi,
		"dmg": base * 0.22 * float(p["m_gren"]) * float(p["m_x_g"]), "burn": strong})


func on_bounce(c) -> void:
	var p: Dictionary = c.prof
	# Cuchillas + Rebote Procesal: cada rebote lanza cuchillas
	if bool(p["syn_knife_bounce"]) and int(p["m_knives"]) > 0 and not _on_cd("kb%d" % c.idx, 0.2):
		var base: float = float(p["base"]) * c.dmg_mult
		var h: Vector3 = c.heading
		_volley_knives(p, _ground(c.pos), Vector3(h.x, 0, h.z).normalized(), base, maxi(2, int(p["m_knives"]) - 1), 1.0)


func on_catch(c) -> void:
	var p: Dictionary = c.prof
	if not c.main or not active(p):
		return
	var pl = GameState.player
	if pl == null or not is_instance_valid(pl):
		return
	var o := _ground(pl.global_position)
	var base: float = float(p["base"]) * c.dmg_mult
	# Lluvia de Cuchillas: salva radial al completar el regreso
	if int(p["m_kfall"]) > 0:
		var n := _budget(int(p["m_kfall"]))
		counts["kfall"] += n
		var off := randf() * TAU
		for i in n:
			var a := off + TAU * float(i) / float(maxi(n, 1))
			_make_knife(p, o, Vector3(cos(a), 0, sin(a)), base * 0.4, 0)
	# Ataques que se activan al salir Y al regresar (Doble Activación)
	var both := float(p["m_both"])
	if both > 0.0:
		counts["both"] += 1
		if int(p["m_knives"]) > 0:
			var f: Vector3 = (-pl.global_transform.basis.z)
			_volley_knives(p, o, Vector3(f.x, 0, f.z).normalized(), base, int(p["m_knives"]), both)
		if int(p["m_missiles"]) > 0:
			_volley_missiles(p, o, Vector3.FORWARD, base, int(p["m_missiles"]), both)
		if int(p["m_discs"]) > 0:
			_volley_discs(p, o, Vector3.FORWARD, base, int(p["m_discs"]), both)


# ============================================================================ actualización
func update(delta: float, _space: PhysicsDirectSpaceState3D) -> void:
	_clock += delta
	for k in _cd.keys():
		_cd[k] = float(_cd[k]) - delta
		if float(_cd[k]) <= 0.0:
			_cd.erase(k)
	_update_lasers(delta)
	_update_zones(delta)
	_update_orbits(delta)
	_update_shots(delta)


func _update_lasers(delta: float) -> void:
	var i := _lasers.size() - 1
	while i >= 0:
		_lasers[i]["t"] = float(_lasers[i]["t"]) - delta
		if float(_lasers[i]["t"]) <= 0.0:
			var l: Dictionary = _lasers[i]
			_lasers.remove_at(i)
			_fire_laser(l)
		i -= 1


func _update_zones(delta: float) -> void:
	var i := _zones.size() - 1
	while i >= 0:
		var z: Dictionary = _zones[i]
		z["t"] += delta
		z["tick"] += delta
		if float(z["tick"]) >= 0.4:
			z["tick"] = 0.0
			var list: Array = Combat.enemies_in_radius(z["pos"], float(z["r"]))
			for e in list:
				Combat.player_hit(e, float(z["dmg"]), {"src": SRC, "element": "fire" if z["burn"] else "phys", "flat": false, "no_crit": true, "proc": false, "area_hits": list.size()})
				if is_instance_valid(e) and e.alive:
					e.apply_slow(0.4, 0.6)
					if z["burn"]:
						e.apply_burn(5.0 + GameState.build.s("burn_dps"), 1.5)
			if not list.is_empty():
				LawPerks.on_secondary_hit()
				counts["sec_hits"] += list.size()
		if float(z["t"]) >= float(z["dur"]):
			_zones.remove_at(i)
		i -= 1


# ---- Órbita de Navajas -------------------------------------------------------
func _orbit_blades_for(c) -> int:
	var p: Dictionary = c.prof
	var n := int(p["m_blades"])
	if n <= 0:
		return 0
	if c.main:
		return n
	if c.ghost and bool(p["syn_phantom"]):
		return maxi(2, n - 1)            # Órbita + Fantasma: cada copia tiene su propia órbita (algo más corta)
	return 0


func _free_orbit(c) -> void:
	var o: Dictionary = _orbits.get(c, {})
	for n in o.get("nodes", []):
		if n != null and is_instance_valid(n):
			n.queue_free()


func _update_orbits(delta: float) -> void:
	# limpia órbitas de maletines que ya no existen
	for c in _orbits.keys():
		if not ct.cases.has(c):
			_free_orbit(c)
			_orbits.erase(c)
	var total := 0
	for c in ct.cases:
		var n := _orbit_blades_for(c)
		if n <= 0:
			continue
		n = mini(n, MAX_BLADES - total)
		if n <= 0:
			break
		total += n
		var o: Dictionary = _orbits.get(c, {})
		if o.is_empty():
			o = {"nodes": [], "hit": {}}
			_orbits[c] = o
			if not c.main:
				counts["ghost_orbits"] += 1
		var nodes: Array = o["nodes"]
		while nodes.size() < n:
			var nd := Node3D.new()
			var mi := Mats.mesh_instance(_mesh_for("knife"), Mats.world_material(), nd)
			mi.material_override = Mats.world_material()
			nd.scale = Vector3.ONE * 0.8
			add_child(nd)
			nodes.append(nd)
		var p: Dictionary = c.prof
		var radius := 1.9 * float(p["m_range"]) * float(c.prof.get("size", 1.0))
		var spin := _clock * 7.0
		var base: float = float(p["base"]) * c.dmg_mult * 0.3 * float(p["m_x_o"])
		var hit: Dictionary = o["hit"]
		for i in n:
			var a := spin + TAU * float(i) / float(n)
			var bp: Vector3 = c.pos + Vector3(cos(a), 0, sin(a)) * radius
			var nd2: Node3D = nodes[i]
			nd2.global_position = bp
			nd2.look_at(bp + Vector3(-sin(a), 0, cos(a)), Vector3.UP)      # la hoja apunta en sentido de giro
			for e in Combat.arena_enemies():
				if not is_instance_valid(e) or not e.alive:
					continue
				var dv: Vector3 = e.global_position - bp
				dv.y = 0.0
				var rr: float = 0.7 + float(e.body_radius)
				if dv.length_squared() > rr * rr:
					continue
				var key := "%d_%d" % [i, e.get_instance_id()]
				if hit.has(key) and _clock - float(hit[key]) < 0.5:
					continue
				hit[key] = _clock
				counts["blade_hits"] += 1
				_sec_hit(e, base, Vector3(-sin(a), 0, cos(a)), "phys", false)
		if hit.size() > 120:
			hit.clear()


# ---- proyectiles ---------------------------------------------------------------
func _steer(s: Shot, delta: float, strength: float) -> void:
	if strength <= 0.0:
		return
	if s.target == null or not is_instance_valid(s.target) or not s.target.alive or s.hits.has(s.target):
		s.target = Combat.nearest_enemy(s.pos, 12.0, s.hits)
	if s.target == null:
		return
	var want: Vector3 = s.target.global_position - s.pos
	want.y = 0.0
	if want.length() < 0.2:
		return
	var v := Vector3(s.vel.x, 0, s.vel.z)
	var ang := v.signed_angle_to(want.normalized(), Vector3.UP)
	var lim := strength * delta
	s.vel = s.vel.rotated(Vector3.UP, clampf(ang, -lim, lim))


func _update_shots(delta: float) -> void:
	var pl = GameState.player
	var i := shots.size() - 1
	while i >= 0:
		var s: Shot = shots[i]
		s.age += delta
		var done := false
		match s.kind:
			"knife", "split":
				_steer(s, delta, s.homing)
				s.pos += s.vel * delta
				s.pos.y = Terrain.ground_y(s.pos.x, s.pos.z) + HIT_Y
				s.life -= delta
				done = s.life <= 0.0 or _touch(s)
			"missile", "seeker":
				_steer(s, delta, s.homing)
				s.pos += s.vel * delta
				s.pos.y = Terrain.ground_y(s.pos.x, s.pos.z) + HIT_Y
				s.life -= delta
				if s.life <= 0.0:
					done = true
					if s.splash > 0.0:
						_pop(s)
				else:
					done = _touch(s)
			"file":
				s.pos += s.vel * delta
				s.life -= delta
				if s.pos.y <= 0.5 or s.life <= 0.0:
					_pop(s)
					done = true
			"disc":
				done = _update_disc(s, delta, pl)
		if s.kind == "knife" or s.kind == "split" or s.kind == "missile" or (s.kind == "seeker" and s.vis != "file"):
			if s.vel.length() > 0.1:
				s.node.look_at(s.pos + s.vel, Vector3.UP)
		elif s.kind == "disc":
			s.node.rotation.y += 22.0 * delta
		elif s.kind == "seeker":
			s.node.rotation.y += 9.0 * delta
		s.node.global_position = s.pos
		if done:
			s.node.visible = false
			shots.remove_at(i)
		i -= 1


## Colisión de un proyectil con los enemigos. Devuelve true si debe desaparecer.
func _touch(s: Shot) -> bool:
	for e in Combat.arena_enemies():
		if not is_instance_valid(e) or not e.alive or s.hits.has(e):
			continue
		var dv: Vector3 = e.global_position - s.pos
		dv.y = 0.0
		var rr: float = s.radius + float(e.body_radius)
		if dv.length_squared() > rr * rr:
			continue
		s.hits.append(e)
		if s.kind == "missile" or (s.kind == "seeker" and s.splash > 0.0):
			_pop(s, e)
			return true
		var dn := s.vel.normalized()
		_sec_hit(e, s.dmg, dn, "phys", s.gen == 0)
		if GameState.fx != null:
			GameState.fx.burst(s.pos, Color(0.9, 0.95, 1.0), 3, 3.0, 0.08, 0.2)
		_on_shot_hit(s, e)
		if s.pierce <= 0:
			return true
		s.pierce -= 1
	return false


func _pop(s: Shot, direct: Node3D = null) -> void:
	## Explosión de misiles, expedientes y proyectiles dirigidos con área.
	var rad := s.splash * Combat.area_mult()
	if direct != null:
		_sec_hit(direct, s.dmg, s.vel.normalized(), "fire", false)
	if ct._blast_ok():
		ct._note_blast()
		Combat.explode(Vector3(s.pos.x, 0.2, s.pos.z), rad, s.dmg * (0.7 if direct != null else 1.0), {"src": SRC, "exclude": direct, "soft": true, "element": "fire" if s.kind == "missile" else "phys"})
	elif GameState.fx != null:
		GameState.fx.burst(s.pos, Color(1.0, 0.8, 0.4), 6, 4.0, 0.1, 0.3)
	if s.kind == "file" and GameState.fx != null:
		GameState.fx.burst(Vector3(s.pos.x, 0.4, s.pos.z), Color(0.98, 0.97, 0.9), 6, 3.0, 0.1, 0.35)
	if s.gen == 0:
		_on_shot_hit(s, direct)


func _on_shot_hit(s: Shot, e: Node3D) -> void:
	var p: Dictionary = s.prof
	if p.is_empty():
		return
	# Proyectiles que se dividen: el impacto de un proyectil original lanza 2 derivados más débiles
	if s.gen == 0 and float(p.get("m_split", 0.0)) > 0.0 and randf() < float(p["m_split"]) and e != null:
		var n := _budget(2)
		for k in n:
			var sign_ := 1.0 if k == 0 else -1.0
			var dir := s.vel.normalized().rotated(Vector3.UP, deg_to_rad(38.0) * sign_)
			var sp := _make_knife(p, s.pos, dir, s.dmg * 0.4, 1)
			sp.life = 0.5
			sp.pierce = 0
			sp.hits = [e]
			counts["splits"] += 1
	# Dividir + Cadena Eléctrica: los proyectiles derivados descargan un rayo (con tope de frecuencia)
	if s.gen == 1 and s.kind == "split" and bool(p.get("syn_fission", false)) and e != null and is_instance_valid(e) and e.alive:
		if not _on_cd("fis%d" % (counts["fission"] % 6), 0.15):
			counts["fission"] += 1
			Combat.chain_lightning(e, s.dmg * 1.2, 2)


func _update_disc(s: Shot, delta: float, pl) -> bool:
	# Disco Judicial: ida curva (bézier) → rodea al objetivo → regresa al jugador
	match s.phase:
		0:
			var dur := 0.5 / maxf(float(s.prof.get("m_range", 1.0)) * 0.8, 0.6)
			var k := clampf(s.age / dur, 0.0, 1.0)
			var q0: Vector3 = s.from.lerp(s.ctrl, k)
			var q1: Vector3 = s.ctrl.lerp(s.center, k)
			s.pos = q0.lerp(q1, k)
			if k >= 1.0:
				s.phase = 1
				s.age = 0.0
		1:
			if s.target != null and is_instance_valid(s.target) and s.target.alive:
				s.center = _ground(s.target.global_position)
			s.ang += 7.5 * delta
			s.pos = s.center + Vector3(cos(s.ang), 0, sin(s.ang)) * 1.9
			if s.age >= 0.95:
				s.phase = 2
				s.age = 0.0
		2:
			if pl == null or not is_instance_valid(pl):
				return true
			var to: Vector3 = _ground(pl.global_position) - s.pos
			if to.length() < 1.2 or s.age > 3.0:
				return true
			s.pos += to.normalized() * 28.0 * delta
	s.pos.y = Terrain.ground_y(s.pos.x, s.pos.z) + HIT_Y
	# daño: cada enemigo como mucho cada 0.4 s
	for e in Combat.arena_enemies():
		if not is_instance_valid(e) or not e.alive:
			continue
		var dv: Vector3 = e.global_position - s.pos
		dv.y = 0.0
		var rr: float = s.radius + float(e.body_radius)
		if dv.length_squared() > rr * rr:
			continue
		var key: int = e.get_instance_id()
		if s.hitcd.has(key) and _clock - float(s.hitcd[key]) < 0.4:
			continue
		s.hitcd[key] = _clock
		_sec_hit(e, s.dmg, Vector3(-sin(s.ang), 0, cos(s.ang)), "phys", false)
	return false
