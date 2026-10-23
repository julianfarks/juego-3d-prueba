class_name ModelFactory
extends RefCounted
## Fábrica de personajes 3D originales (low-poly estilizado, generados por código).
## Cada personaje = esqueleto articulado (Rig) + una malla por articulación con color por vértice.

# Paleta del juego
const NAVY := Color(0.10, 0.14, 0.32)
const NAVY_L := Color(0.17, 0.23, 0.45)
const WHITE := Color(0.95, 0.95, 0.93)
const RED := Color(0.86, 0.12, 0.16)
const SKIN := Color(0.96, 0.75, 0.6)
const SKIN_D := Color(0.82, 0.6, 0.47)
const HAIR := Color(0.14, 0.09, 0.07)
const BLACK := Color(0.07, 0.07, 0.09)
const GOLD := Color(1.0, 0.76, 0.2)
const LEATHER := Color(0.46, 0.25, 0.1)
const LEATHER_L := Color(0.58, 0.34, 0.14)
const STEEL := Color(0.52, 0.55, 0.6)
const STEEL_D := Color(0.3, 0.32, 0.37)


static func _x(pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE) -> Transform3D:
	return MeshBuilder.xf(pos, rot, scl)


static func _g(c: Color, amount := 1.0) -> Color:
	return MeshBuilder.glow(c, amount)


## Construye el esqueleto base. spec: leg, torso, arm_up, arm_lo, sw, hw
static func make_skeleton(sp: Dictionary) -> Rig:
	var rig := Rig.new()
	rig.name = "Rig"
	rig.material = Mats.char_material()
	var vis := Node3D.new()
	vis.name = "Visual"
	rig.add_child(vis)
	rig.visual = vis
	var leg: float = sp.get("leg", 0.86)
	var torso_h: float = sp.get("torso", 0.62)
	var up: float = sp.get("arm_up", 0.3)
	var lo: float = sp.get("arm_lo", 0.3)
	var sw: float = sp.get("sw", 0.34)
	var hw: float = sp.get("hw", 0.12)
	rig.hip_height = leg
	rig.heavy = sp.get("heavy", false)
	var mk := func(jname: String, parent: Node3D, pos: Vector3) -> Node3D:
		var n := Node3D.new()
		n.name = jname
		n.position = pos
		parent.add_child(n)
		rig.j[jname] = n
		return n
	var hips: Node3D = mk.call("hips", vis, Vector3(0, leg, 0))
	var torso: Node3D = mk.call("torso", hips, Vector3(0, 0.08, 0))
	mk.call("head", torso, Vector3(0, torso_h, 0))
	var arm_l: Node3D = mk.call("arm_l", torso, Vector3(-sw, torso_h - 0.07, 0))
	mk.call("fore_l", arm_l, Vector3(0, -up, 0))
	var arm_r: Node3D = mk.call("arm_r", torso, Vector3(sw, torso_h - 0.07, 0))
	mk.call("fore_r", arm_r, Vector3(0, -up, 0))
	var leg_l: Node3D = mk.call("leg_l", hips, Vector3(-hw, 0, 0))
	mk.call("shin_l", leg_l, Vector3(0, -leg * 0.5, 0))
	var leg_r: Node3D = mk.call("leg_r", hips, Vector3(hw, 0, 0))
	mk.call("shin_r", leg_r, Vector3(0, -leg * 0.5, 0))
	rig.set_meta("lo", lo)
	rig.set_meta("up", up)
	return rig


static func _new_parts() -> Dictionary:
	var d := {}
	for jn in Rig.JOINTS:
		d[jn] = MeshBuilder.new()
	return d


static func _attach(rig: Rig, parts: Dictionary) -> void:
	for jn in parts.keys():
		var mb: MeshBuilder = parts[jn]
		if mb.is_empty():
			continue
		var node: Node3D = rig.j[jn]
		var mi := Mats.mesh_instance(mb.build(), rig.material, node)
		mi.name = "Mesh_" + String(jn)


## Pierna/brazo cilíndrico colgante (hacia -Y).
static func _limb(mb: MeshBuilder, length: float, r_top: float, r_bot: float, col: Color, seg := 6) -> void:
	mb.cylinder(r_top, r_bot, length, seg, _x(Vector3(0, -length * 0.5, 0)), col)


static func _std_legs(parts: Dictionary, leg: float, hw_r: float, pants: Color, shoe: Color, sole: Color, shoe_len := 0.32) -> void:
	var half := leg * 0.5
	for side in ["l", "r"]:
		_limb(parts["leg_" + side], half, hw_r, hw_r * 0.82, pants)
		_limb(parts["shin_" + side], half, hw_r * 0.82, hw_r * 0.66, pants)
		var sh: MeshBuilder = parts["shin_" + side]
		sh.box(Vector3(hw_r * 1.55, 0.09, shoe_len), _x(Vector3(0, -half + 0.07, -shoe_len * 0.18)), shoe)
		sh.box(Vector3(hw_r * 1.6, 0.035, shoe_len + 0.02), _x(Vector3(0, -half + 0.017, -shoe_len * 0.18)), sole)


static func _std_arms(parts: Dictionary, up: float, lo: float, r: float, sleeve: Color, cuff: Color, hand: Color, hand_r := 0.07) -> void:
	for side in ["l", "r"]:
		_limb(parts["arm_" + side], up, r * 1.1, r, sleeve)
		var fa: MeshBuilder = parts["fore_" + side]
		_limb(fa, lo, r, r * 0.88, sleeve)
		fa.cylinder(r * 0.95, r * 0.95, 0.04, 6, _x(Vector3(0, -lo + 0.01, 0)), cuff)
		fa.sphere(hand_r, 6, 4, _x(Vector3(0, -lo - 0.04, 0)), hand)


# =============================================================================
#  ABOGADO (jugador)
# =============================================================================
static func build_lawyer() -> Rig:
	var rig := make_skeleton({"leg": 0.86, "torso": 0.64, "arm_up": 0.3, "arm_lo": 0.3, "sw": 0.35, "hw": 0.125})
	var p := _new_parts()
	# --- pelvis y torso (traje) ---
	(p["hips"] as MeshBuilder).box(Vector3(0.5, 0.2, 0.3), _x(Vector3(0, 0.03, 0)), NAVY)
	(p["hips"] as MeshBuilder).box(Vector3(0.52, 0.04, 0.31), _x(Vector3(0, 0.1, 0)), BLACK)  # cinturón
	(p["hips"] as MeshBuilder).box(Vector3(0.07, 0.05, 0.02), _x(Vector3(0, 0.1, -0.16)), GOLD)
	var t: MeshBuilder = p["torso"]
	t.frustum(Vector2(0.58, 0.36), Vector2(0.64, 0.32), 0.62, _x(Vector3(0, 0.31, 0)), NAVY)
	t.frustum(Vector2(0.62, 0.40), Vector2(0.58, 0.36), 0.2, _x(Vector3(0, 0.02, 0)), NAVY)  # faldón chaqueta
	t.box(Vector3(0.16, 0.5, 0.02), _x(Vector3(0, 0.36, -0.172)), WHITE)                      # camisa
	t.box(Vector3(0.075, 0.4, 0.025), _x(Vector3(0, 0.33, -0.19)), RED)                       # corbata
	t.wedge(Vector3(0.075, 0.07, 0.03), _x(Vector3(0, 0.1, -0.19), Vector3(0, 0, 0)), RED)
	t.box(Vector3(0.09, 0.06, 0.04), _x(Vector3(0, 0.55, -0.185)), Color(0.7, 0.08, 0.12))    # nudo
	t.box(Vector3(0.18, 0.05, 0.1), _x(Vector3(0, 0.62, -0.02)), WHITE)                        # cuello camisa
	for sx in [-1.0, 1.0]:
		t.box(Vector3(0.1, 0.48, 0.03), _x(Vector3(sx * 0.13, 0.36, -0.176), Vector3(0, 0, sx * -9.0)), NAVY_L)  # solapas
		t.sphere(0.13, 6, 4, _x(Vector3(sx * 0.33, 0.55, 0)), NAVY)                                              # hombros
	for i in 2:
		t.box(Vector3(0.035, 0.035, 0.02), _x(Vector3(0.0, 0.16 - i * 0.1, -0.186)), GOLD)
	t.box(Vector3(0.1, 0.012, 0.02), _x(Vector3(0.17, 0.42, -0.178)), WHITE)                  # pañuelo
	t.box(Vector3(0.1, 0.04, 0.2), _x(Vector3(0, 0.15, 0.2)), NAVY_L)                          # abertura trasera
	# --- cabeza ---
	var h: MeshBuilder = p["head"]
	h.cylinder(0.085, 0.095, 0.1, 6, _x(Vector3(0, 0.04, 0)), SKIN_D)
	h.sphere(0.28, 8, 6, _x(Vector3(0, 0.31, 0), Vector3.ZERO, Vector3(1.0, 1.05, 0.96)), SKIN)
	h.sphere(0.298, 8, 4, _x(Vector3(0, 0.42, 0.02), Vector3.ZERO, Vector3(1.0, 0.72, 1.02)), HAIR)     # pelo
	h.box(Vector3(0.5, 0.1, 0.1), _x(Vector3(0, 0.44, -0.2), Vector3(-12, 0, 0)), HAIR)                 # tupé engominado
	for sx in [-1.0, 1.0]:
		h.sphere(0.05, 5, 4, _x(Vector3(sx * 0.285, 0.3, 0)), SKIN_D)                                   # orejas
		h.sphere(0.058, 6, 4, _x(Vector3(sx * 0.105, 0.33, -0.245)), WHITE)                             # ojos
		h.sphere(0.03, 5, 4, _x(Vector3(sx * 0.105, 0.33, -0.292)), BLACK)
		h.box(Vector3(0.13, 0.03, 0.03), _x(Vector3(sx * 0.11, 0.41, -0.265), Vector3(0, 0, sx * 14.0)), HAIR)  # ceño serio
		h.cylinder(0.092, 0.092, 0.024, 8, _x(Vector3(sx * 0.105, 0.33, -0.29), Vector3(90, 0, 0)), Color(0.05, 0.05, 0.07), false)  # gafas
	h.box(Vector3(0.09, 0.02, 0.02), _x(Vector3(0, 0.34, -0.292)), BLACK)                               # puente gafas
	h.box(Vector3(0.05, 0.07, 0.07), _x(Vector3(0, 0.27, -0.285)), SKIN_D)                              # nariz
	h.box(Vector3(0.12, 0.022, 0.02), _x(Vector3(0, 0.17, -0.262)), Color(0.35, 0.12, 0.12))            # boca seria
	# --- brazos, piernas ---
	_std_arms(p, 0.3, 0.3, 0.07, NAVY, WHITE, SKIN, 0.072)
	_std_legs(p, 0.86, 0.1, NAVY, BLACK, WHITE, 0.33)
	_attach(rig, p)
	# --- maletín (en la mano derecha) ---
	var case_node := Node3D.new()
	case_node.name = "Briefcase"
	var fore_r: Node3D = rig.j["fore_r"]
	case_node.position = Vector3(0, -0.34, 0)
	fore_r.add_child(case_node)
	var cb := briefcase_mesh()
	var cmi := Mats.mesh_instance(cb, rig.material, case_node)
	cmi.name = "BriefcaseMesh"
	rig.props["case"] = case_node
	return rig


static func briefcase_mesh() -> ArrayMesh:
	var b := MeshBuilder.new()
	b.box(Vector3(0.52, 0.36, 0.14), _x(Vector3(0, -0.24, 0)), LEATHER)
	b.box(Vector3(0.52, 0.07, 0.145), _x(Vector3(0, -0.095, 0)), LEATHER_L)
	b.box(Vector3(0.5, 0.012, 0.15), _x(Vector3(0, -0.14, 0)), Color(0.3, 0.15, 0.06))
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			b.box(Vector3(0.07, 0.07, 0.16), _x(Vector3(sx * 0.25, -0.24 + sy * 0.16, 0)), _g(GOLD, 0.35))
		b.box(Vector3(0.08, 0.05, 0.155), _x(Vector3(sx * 0.14, -0.14, 0)), _g(GOLD, 0.35))
	b.box(Vector3(0.05, 0.06, 0.16), _x(Vector3(0, -0.14, 0)), _g(GOLD, 0.5))
	# asa
	b.box(Vector3(0.2, 0.025, 0.05), _x(Vector3(0, -0.015, 0)), STEEL_D)
	b.box(Vector3(0.025, 0.09, 0.05), _x(Vector3(-0.1, -0.055, 0)), STEEL_D)
	b.box(Vector3(0.025, 0.09, 0.05), _x(Vector3(0.1, -0.055, 0)), STEEL_D)
	b.box(Vector3(0.2, 0.05, 0.02), _x(Vector3(0, -0.28, -0.075)), Color(0.9, 0.85, 0.7))  # etiqueta
	return b.build()


# =============================================================================
#  ENEMIGOS
# =============================================================================
static func build_enemy(kind: String, variant := 0) -> Rig:
	match kind:
		"thief": return _thief(variant)
		"runner": return _runner(variant)
		"tank": return _tank(variant)
		"ranged": return _ranged(variant)
		"summoner": return _summoner(variant)
		"elite": return _elite(variant)
		"miniboss": return _miniboss()
		"boss": return _boss()
	return _thief(variant)


static func _thief(variant: int) -> Rig:
	var rig := make_skeleton({"leg": 0.8, "torso": 0.58, "arm_up": 0.28, "arm_lo": 0.28, "sw": 0.31, "hw": 0.11})
	var p := _new_parts()
	var stripe: Color = [Color(0.1, 0.1, 0.12), Color(0.55, 0.1, 0.1), Color(0.1, 0.25, 0.5)][variant % 3]
	var pants: Color = [Color(0.3, 0.32, 0.4), Color(0.35, 0.28, 0.2), Color(0.22, 0.28, 0.25)][variant % 3]
	(p["hips"] as MeshBuilder).box(Vector3(0.45, 0.2, 0.28), _x(Vector3(0, 0.03, 0)), pants)
	var t: MeshBuilder = p["torso"]
	for i in 6:
		var col := stripe if i % 2 == 0 else WHITE
		t.frustum(Vector2(0.5, 0.33), Vector2(0.5, 0.33), 0.1, _x(Vector3(0, 0.06 + i * 0.095, 0)), col)
	t.sphere(0.12, 5, 4, _x(Vector3(-0.3, 0.5, 0)), stripe)
	t.sphere(0.12, 5, 4, _x(Vector3(0.3, 0.5, 0)), stripe)
	# saco del botín
	t.sphere(0.27, 6, 5, _x(Vector3(0, 0.32, 0.3), Vector3.ZERO, Vector3(1.0, 1.1, 0.9)), Color(0.55, 0.42, 0.25))
	t.box(Vector3(0.1, 0.06, 0.1), _x(Vector3(0, 0.6, 0.3)), Color(0.4, 0.3, 0.18))
	t.box(Vector3(0.08, 0.1, 0.01), _x(Vector3(0, 0.3, 0.57)), _g(GOLD, 0.6))
	var h: MeshBuilder = p["head"]
	h.sphere(0.25, 7, 5, _x(Vector3(0, 0.29, 0), Vector3.ZERO, Vector3(1.0, 1.05, 0.96)), SKIN_D)
	h.sphere(0.265, 7, 4, _x(Vector3(0, 0.4, 0.01), Vector3.ZERO, Vector3(1.0, 0.7, 1.0)), BLACK)  # gorro
	h.box(Vector3(0.46, 0.1, 0.1), _x(Vector3(0, 0.31, -0.19)), BLACK)                            # antifaz
	for sx in [-1.0, 1.0]:
		h.sphere(0.04, 5, 4, _x(Vector3(sx * 0.09, 0.31, -0.235)), WHITE)
		h.sphere(0.02, 4, 3, _x(Vector3(sx * 0.09, 0.31, -0.268)), BLACK)
	h.box(Vector3(0.1, 0.02, 0.02), _x(Vector3(0, 0.17, -0.235)), Color(0.3, 0.1, 0.1))
	_std_arms(p, 0.28, 0.28, 0.065, stripe, WHITE, SKIN_D, 0.065)
	_std_legs(p, 0.8, 0.095, pants, Color(0.15, 0.12, 0.1), Color(0.8, 0.8, 0.8), 0.3)
	_attach(rig, p)
	# palanca
	var bar := MeshBuilder.new()
	bar.cylinder(0.025, 0.025, 0.75, 5, _x(Vector3(0, -0.15, -0.0), Vector3(90, 0, 0)), STEEL_D)
	bar.box(Vector3(0.05, 0.05, 0.14), _x(Vector3(0, -0.15, -0.38), Vector3(0, 25, 0)), Color(0.75, 0.15, 0.12))
	var wn := Node3D.new()
	wn.name = "Weapon"
	wn.position = Vector3(0, -0.32, 0)
	(rig.j["fore_r"] as Node3D).add_child(wn)
	Mats.mesh_instance(bar.build(), rig.material, wn)
	rig.props["weapon"] = wn
	return rig


static func _runner(variant: int) -> Rig:
	var rig := make_skeleton({"leg": 0.86, "torso": 0.5, "arm_up": 0.3, "arm_lo": 0.3, "sw": 0.26, "hw": 0.1})
	var p := _new_parts()
	var hood: Color = [Color(0.1, 0.65, 0.65), Color(0.85, 0.35, 0.1), Color(0.55, 0.2, 0.75)][variant % 3]
	var pants := Color(0.12, 0.12, 0.16)
	(p["hips"] as MeshBuilder).box(Vector3(0.38, 0.18, 0.24), _x(Vector3(0, 0.03, 0)), pants)
	var t: MeshBuilder = p["torso"]
	t.frustum(Vector2(0.44, 0.28), Vector2(0.5, 0.26), 0.5, _x(Vector3(0, 0.25, 0)), hood)
	t.box(Vector3(0.3, 0.12, 0.03), _x(Vector3(0, 0.15, -0.15)), hood.darkened(0.2))  # bolsillo canguro
	t.box(Vector3(0.2, 0.28, 0.12), _x(Vector3(0, 0.3, 0.2)), Color(0.15, 0.15, 0.2))  # mochila
	t.box(Vector3(0.12, 0.03, 0.125), _x(Vector3(0, 0.38, 0.2)), _g(Color(1, 0.9, 0.2), 0.8))
	var h: MeshBuilder = p["head"]
	h.sphere(0.23, 7, 5, _x(Vector3(0, 0.27, 0), Vector3.ZERO, Vector3(1.0, 1.05, 0.97)), SKIN)
	h.sphere(0.27, 7, 5, _x(Vector3(0, 0.3, 0.04), Vector3.ZERO, Vector3(1.0, 1.0, 1.0)), hood)  # capucha
	h.sphere(0.2, 6, 4, _x(Vector3(0, 0.27, -0.06), Vector3.ZERO, Vector3(1.0, 1.0, 0.8)), SKIN)
	h.box(Vector3(0.3, 0.12, 0.04), _x(Vector3(0, 0.16, -0.205)), _g(Color(1, 0.85, 0.15), 0.4))     # pañuelo
	for sx in [-1.0, 1.0]:
		h.sphere(0.04, 5, 4, _x(Vector3(sx * 0.08, 0.3, -0.2)), WHITE)
		h.sphere(0.02, 4, 3, _x(Vector3(sx * 0.08, 0.3, -0.235)), BLACK)
	_std_arms(p, 0.3, 0.3, 0.055, hood, hood.darkened(0.25), SKIN, 0.055)
	_std_legs(p, 0.86, 0.082, pants, WHITE, _g(Color(0.2, 1.0, 0.6), 0.9), 0.3)
	_attach(rig, p)
	rig.visual.scale = Vector3(0.95, 1.0, 0.95)
	return rig


static func _tank(variant: int) -> Rig:
	var rig := make_skeleton({"leg": 0.78, "torso": 0.7, "arm_up": 0.32, "arm_lo": 0.32, "sw": 0.5, "hw": 0.17, "heavy": true})
	var p := _new_parts()
	var cloth := Color(0.25, 0.3, 0.22) if variant % 2 == 0 else Color(0.35, 0.22, 0.2)
	(p["hips"] as MeshBuilder).box(Vector3(0.7, 0.24, 0.4), _x(Vector3(0, 0.03, 0)), Color(0.2, 0.2, 0.22))
	var t: MeshBuilder = p["torso"]
	t.frustum(Vector2(0.78, 0.5), Vector2(0.98, 0.5), 0.7, _x(Vector3(0, 0.35, 0)), cloth)
	for sx in [-1.0, 1.0]:
		t.sphere(0.22, 6, 4, _x(Vector3(sx * 0.5, 0.64, 0), Vector3.ZERO, Vector3(1.0, 0.7, 1.0)), STEEL)
		t.sphere(0.26, 6, 4, _x(Vector3(sx * 0.5, 0.72, 0), Vector3.ZERO, Vector3(1.0, 0.45, 1.0)), STEEL_D)
	t.box(Vector3(0.62, 0.38, 0.06), _x(Vector3(0, 0.4, -0.27)), STEEL)                     # peto de chapa
	t.box(Vector3(0.5, 0.06, 0.07), _x(Vector3(0, 0.4, -0.27)), STEEL_D)
	for i in 4:
		t.sphere(0.025, 4, 3, _x(Vector3(-0.25 + i * 0.167, 0.55, -0.31)), GOLD)
		t.sphere(0.025, 4, 3, _x(Vector3(-0.25 + i * 0.167, 0.25, -0.31)), GOLD)
	t.sphere(0.34, 6, 4, _x(Vector3(0, 0.2, -0.05), Vector3.ZERO, Vector3(1.1, 0.8, 1.0)), cloth.lightened(0.05))  # barriga
	var h: MeshBuilder = p["head"]
	h.sphere(0.27, 7, 5, _x(Vector3(0, 0.3, 0)), SKIN_D)
	h.cylinder(0.3, 0.32, 0.22, 8, _x(Vector3(0, 0.46, 0)), STEEL_D)                          # casco-olla
	h.cylinder(0.04, 0.3, 0.06, 8, _x(Vector3(0, 0.6, 0)), STEEL)
	h.box(Vector3(0.36, 0.08, 0.05), _x(Vector3(0, 0.31, -0.25)), BLACK)
	for sx in [-1.0, 1.0]:
		h.sphere(0.03, 4, 3, _x(Vector3(sx * 0.09, 0.31, -0.275)), _g(Color(1, 0.3, 0.2), 1.0))
	_std_arms(p, 0.32, 0.32, 0.12, cloth, STEEL_D, SKIN_D, 0.11)
	_std_legs(p, 0.78, 0.15, Color(0.22, 0.22, 0.25), BLACK, STEEL, 0.42)
	# escudo puerta de caja fuerte en el antebrazo izquierdo
	var fl: MeshBuilder = p["fore_l"]
	fl.cylinder(0.5, 0.5, 0.1, 10, _x(Vector3(0, -0.2, -0.22), Vector3(90, 0, 0)), STEEL)
	fl.cylinder(0.4, 0.4, 0.12, 10, _x(Vector3(0, -0.2, -0.22), Vector3(90, 0, 0)), STEEL_D)
	fl.cylinder(0.1, 0.1, 0.16, 8, _x(Vector3(0, -0.2, -0.25), Vector3(90, 0, 0)), _g(GOLD, 0.4))
	for k in 3:
		fl.box(Vector3(0.62, 0.05, 0.05), _x(Vector3(0, -0.2, -0.3), Vector3(0, 0, k * 60.0)), _g(GOLD, 0.3))
	_attach(rig, p)
	# llave inglesa gigante
	var wr := MeshBuilder.new()
	wr.cylinder(0.04, 0.04, 0.8, 5, _x(Vector3(0, -0.2, -0.2), Vector3(70, 0, 0)), STEEL_D)
	wr.box(Vector3(0.22, 0.14, 0.2), _x(Vector3(0, -0.2, -0.62), Vector3(70, 0, 0)), STEEL)
	var wn := Node3D.new()
	wn.name = "Weapon"
	wn.position = Vector3(0, -0.36, 0)
	(rig.j["fore_r"] as Node3D).add_child(wn)
	Mats.mesh_instance(wr.build(), rig.material, wn)
	rig.props["weapon"] = wn
	return rig


static func _ranged(variant: int) -> Rig:
	var rig := make_skeleton({"leg": 0.84, "torso": 0.58, "arm_up": 0.3, "arm_lo": 0.3, "sw": 0.3, "hw": 0.11})
	var p := _new_parts()
	var coat: Color = [Color(0.32, 0.22, 0.14), Color(0.2, 0.28, 0.3), Color(0.28, 0.18, 0.3)][variant % 3]
	(p["hips"] as MeshBuilder).box(Vector3(0.42, 0.2, 0.28), _x(Vector3(0, 0.03, 0)), Color(0.15, 0.15, 0.18))
	(p["hips"] as MeshBuilder).frustum(Vector2(0.5, 0.34), Vector2(0.62, 0.4), 0.5, _x(Vector3(0, -0.2, 0)), coat)  # faldón largo del abrigo
	var t: MeshBuilder = p["torso"]
	t.frustum(Vector2(0.58, 0.36), Vector2(0.56, 0.32), 0.58, _x(Vector3(0, 0.29, 0)), coat)
	t.box(Vector3(0.14, 0.4, 0.03), _x(Vector3(0, 0.3, -0.18)), coat.lightened(0.15))
	t.sphere(0.12, 5, 4, _x(Vector3(-0.3, 0.52, 0)), coat)
	t.sphere(0.12, 5, 4, _x(Vector3(0.3, 0.52, 0)), coat)
	t.box(Vector3(0.5, 0.1, 0.34), _x(Vector3(0, 0.58, 0)), coat.darkened(0.15))        # solapa/cuello alzado
	t.box(Vector3(0.1, 0.1, 0.1), _x(Vector3(0, 0.1, 0.22)), _g(GOLD, 0.5))             # bolsa de monedas
	var h: MeshBuilder = p["head"]
	h.sphere(0.25, 7, 5, _x(Vector3(0, 0.29, 0), Vector3.ZERO, Vector3(1.0, 1.05, 0.96)), SKIN)
	h.box(Vector3(0.4, 0.14, 0.12), _x(Vector3(0, 0.18, -0.19)), Color(0.75, 0.15, 0.15))  # bufanda-pañuelo
	h.cylinder(0.24, 0.26, 0.16, 8, _x(Vector3(0, 0.5, 0)), Color(0.35, 0.35, 0.4))        # sombrero fedora
	h.cylinder(0.42, 0.42, 0.02, 10, _x(Vector3(0, 0.42, -0.02), Vector3(-8, 0, 0)), Color(0.3, 0.3, 0.35))
	h.box(Vector3(0.5, 0.04, 0.5), _x(Vector3(0, 0.45, 0)), BLACK)
	for sx in [-1.0, 1.0]:
		h.sphere(0.04, 5, 4, _x(Vector3(sx * 0.09, 0.31, -0.225)), WHITE)
		h.sphere(0.02, 4, 3, _x(Vector3(sx * 0.09, 0.31, -0.258)), BLACK)
	_std_arms(p, 0.3, 0.3, 0.06, coat, coat.darkened(0.2), SKIN, 0.06)
	_std_legs(p, 0.84, 0.09, Color(0.15, 0.15, 0.18), BLACK, Color(0.7, 0.7, 0.7), 0.3)
	_attach(rig, p)
	# lanzamonedas
	var gun := MeshBuilder.new()
	gun.box(Vector3(0.12, 0.14, 0.4), _x(Vector3(0, -0.12, -0.2)), STEEL_D)
	gun.cylinder(0.05, 0.05, 0.3, 6, _x(Vector3(0, -0.1, -0.5), Vector3(90, 0, 0)), STEEL)
	gun.cylinder(0.07, 0.07, 0.05, 6, _x(Vector3(0, -0.1, -0.63), Vector3(90, 0, 0)), _g(GOLD, 0.9))
	gun.cylinder(0.11, 0.11, 0.1, 8, _x(Vector3(0, -0.02, -0.14), Vector3(0, 0, 90)), _g(GOLD, 0.5))
	var wn := Node3D.new()
	wn.name = "Weapon"
	wn.position = Vector3(0, -0.3, 0)
	(rig.j["fore_r"] as Node3D).add_child(wn)
	Mats.mesh_instance(gun.build(), rig.material, wn)
	rig.props["weapon"] = wn
	return rig


static func _summoner(_variant: int) -> Rig:
	var rig := make_skeleton({"leg": 0.84, "torso": 0.6, "arm_up": 0.3, "arm_lo": 0.3, "sw": 0.3, "hw": 0.1})
	var p := _new_parts()
	var robe := Color(0.3, 0.12, 0.45)
	var trim := Color(0.2, 0.95, 0.45)
	(p["hips"] as MeshBuilder).frustum(Vector2(0.85, 0.7), Vector2(0.5, 0.34), 0.95, _x(Vector3(0, -0.28, 0)), robe)  # túnica larga
	(p["hips"] as MeshBuilder).box(Vector3(0.88, 0.04, 0.72), _x(Vector3(0, -0.74, 0)), _g(trim, 0.6))
	var t: MeshBuilder = p["torso"]
	t.frustum(Vector2(0.52, 0.34), Vector2(0.6, 0.32), 0.6, _x(Vector3(0, 0.3, 0)), robe)
	t.box(Vector3(0.1, 0.6, 0.02), _x(Vector3(0, 0.3, -0.175)), _g(trim, 0.7))
	t.sphere(0.13, 5, 4, _x(Vector3(-0.31, 0.54, 0)), robe)
	t.sphere(0.13, 5, 4, _x(Vector3(0.31, 0.54, 0)), robe)
	t.sphere(0.08, 6, 4, _x(Vector3(0, 0.38, -0.2)), _g(GOLD, 0.8))                       # medallón
	var h: MeshBuilder = p["head"]
	h.sphere(0.24, 7, 5, _x(Vector3(0, 0.29, 0)), Color(0.1, 0.05, 0.14))                    # cara en sombra
	h.sphere(0.3, 7, 5, _x(Vector3(0, 0.32, 0.05), Vector3.ZERO, Vector3(1.0, 1.08, 1.0)), robe)  # capucha
	h.sphere(0.2, 7, 4, _x(Vector3(0, 0.29, -0.1), Vector3.ZERO, Vector3(0.95, 0.95, 0.7)), Color(0.08, 0.04, 0.1))
	h.cylinder(0.02, 0.2, 0.28, 6, _x(Vector3(0, 0.62, 0.04)), robe)                         # punta de capucha
	for sx in [-1.0, 1.0]:
		h.sphere(0.045, 5, 4, _x(Vector3(sx * 0.085, 0.31, -0.22)), _g(trim, 1.0))
	_std_arms(p, 0.3, 0.3, 0.07, robe, trim, Color(0.55, 0.45, 0.6), 0.06)
	_std_legs(p, 0.84, 0.08, robe.darkened(0.3), BLACK, BLACK, 0.28)
	_attach(rig, p)
	# bastón con orbe de dólar
	var st := MeshBuilder.new()
	st.cylinder(0.025, 0.03, 1.3, 5, _x(Vector3(0, -0.05, -0.1), Vector3(0, 0, 0)), Color(0.35, 0.2, 0.1))
	st.sphere(0.13, 7, 5, _x(Vector3(0, 0.66, -0.1)), _g(trim, 1.0))
	st.box(Vector3(0.05, 0.16, 0.05), _x(Vector3(0, 0.66, -0.1)), Color(0.05, 0.4, 0.2))
	st.box(Vector3(0.14, 0.04, 0.05), _x(Vector3(0, 0.66, -0.1), Vector3(0, 0, 45)), Color(0.05, 0.4, 0.2))
	var wn := Node3D.new()
	wn.name = "Weapon"
	wn.position = Vector3(0, -0.32, 0)
	(rig.j["fore_r"] as Node3D).add_child(wn)
	Mats.mesh_instance(st.build(), rig.material, wn)
	rig.props["weapon"] = wn
	return rig


static func _elite(variant: int) -> Rig:
	var rig := make_skeleton({"leg": 0.84, "torso": 0.62, "arm_up": 0.31, "arm_lo": 0.31, "sw": 0.38, "hw": 0.13})
	var p := _new_parts()
	var suit: Color = [Color(0.55, 0.08, 0.12), Color(0.1, 0.1, 0.12), Color(0.4, 0.08, 0.35)][variant % 3]
	(p["hips"] as MeshBuilder).box(Vector3(0.52, 0.22, 0.3), _x(Vector3(0, 0.03, 0)), suit.darkened(0.2))
	var t: MeshBuilder = p["torso"]
	t.frustum(Vector2(0.6, 0.36), Vector2(0.72, 0.34), 0.62, _x(Vector3(0, 0.31, 0)), suit)
	t.box(Vector3(0.18, 0.5, 0.02), _x(Vector3(0, 0.36, -0.182)), WHITE)
	t.box(Vector3(0.12, 0.5, 0.03), _x(Vector3(0, 0.3, -0.2), Vector3(0, 0, 0)), _g(GOLD, 0.5))   # chaleco dorado
	for sx in [-1.0, 1.0]:
		t.sphere(0.17, 6, 4, _x(Vector3(sx * 0.4, 0.58, 0), Vector3.ZERO, Vector3(1.1, 0.7, 1.0)), _g(GOLD, 0.35))  # hombreras
		t.cylinder(0.02, 0.07, 0.14, 5, _x(Vector3(sx * 0.46, 0.7, 0)), _g(GOLD, 0.35))
	for i in 7:  # cadena de oro
		var a := PI * (0.15 + i * 0.1)
		t.sphere(0.035, 4, 3, _x(Vector3(cos(a + PI * 0.5) * 0.2, 0.52 - sin(a) * 0.12, -0.2)), _g(GOLD, 0.8))
	t.sphere(0.3, 6, 5, _x(Vector3(0, 0.34, 0.32), Vector3.ZERO, Vector3(1.0, 1.1, 0.9)), Color(0.3, 0.22, 0.12))  # saco enorme
	t.sphere(0.2, 5, 4, _x(Vector3(0.0, 0.5, 0.45)), _g(GOLD, 0.7))
	var h: MeshBuilder = p["head"]
	h.sphere(0.27, 7, 5, _x(Vector3(0, 0.3, 0), Vector3.ZERO, Vector3(1.0, 1.05, 0.96)), SKIN_D)
	h.cylinder(0.25, 0.27, 0.2, 8, _x(Vector3(0, 0.55, 0)), WHITE)           # sombrero blanco de capo
	h.cylinder(0.45, 0.45, 0.025, 10, _x(Vector3(0, 0.45, 0)), WHITE)
	h.box(Vector3(0.52, 0.05, 0.52), _x(Vector3(0, 0.5, 0)), suit)
	h.box(Vector3(0.18, 0.04, 0.03), _x(Vector3(0, 0.2, -0.26)), HAIR)       # bigote
	for sx in [-1.0, 1.0]:
		h.sphere(0.05, 5, 4, _x(Vector3(sx * 0.1, 0.33, -0.245)), _g(GOLD, 1.0))
		h.box(Vector3(0.13, 0.03, 0.03), _x(Vector3(sx * 0.11, 0.4, -0.26), Vector3(0, 0, sx * 16.0)), HAIR)
	_std_arms(p, 0.31, 0.31, 0.085, suit, _g(GOLD, 0.5), SKIN_D, 0.08)
	_std_legs(p, 0.84, 0.115, suit.darkened(0.1), BLACK, _g(GOLD, 0.4), 0.34)
	_attach(rig, p)
	var cane := MeshBuilder.new()
	cane.cylinder(0.03, 0.03, 0.95, 5, _x(Vector3(0, -0.1, -0.2), Vector3(70, 0, 0)), _g(GOLD, 0.5))
	cane.sphere(0.09, 6, 4, _x(Vector3(0, -0.1, -0.62)), _g(Color(1.0, 0.9, 0.4), 0.9))
	var wn := Node3D.new()
	wn.name = "Weapon"
	wn.position = Vector3(0, -0.35, 0)
	(rig.j["fore_r"] as Node3D).add_child(wn)
	Mats.mesh_instance(cane.build(), rig.material, wn)
	rig.props["weapon"] = wn
	return rig


static func _miniboss() -> Rig:
	var rig := make_skeleton({"leg": 0.8, "torso": 0.72, "arm_up": 0.34, "arm_lo": 0.34, "sw": 0.55, "hw": 0.18, "heavy": true})
	var p := _new_parts()
	var vest := Color(0.95, 0.55, 0.08)
	(p["hips"] as MeshBuilder).box(Vector3(0.75, 0.26, 0.42), _x(Vector3(0, 0.03, 0)), Color(0.22, 0.2, 0.22))
	var t: MeshBuilder = p["torso"]
	t.frustum(Vector2(0.8, 0.52), Vector2(1.05, 0.52), 0.72, _x(Vector3(0, 0.36, 0)), Color(0.2, 0.22, 0.28))
	t.frustum(Vector2(0.84, 0.54), Vector2(1.08, 0.54), 0.5, _x(Vector3(0, 0.42, 0)), vest)
	t.box(Vector3(0.88, 0.07, 0.56), _x(Vector3(0, 0.45, 0)), _g(Color(1, 1, 0.7), 0.5))   # banda reflectante
	t.box(Vector3(0.88, 0.07, 0.56), _x(Vector3(0, 0.25, 0)), _g(Color(1, 1, 0.7), 0.5))
	for sx in [-1.0, 1.0]:
		t.sphere(0.26, 6, 4, _x(Vector3(sx * 0.55, 0.66, 0), Vector3.ZERO, Vector3(1.1, 0.7, 1.1)), STEEL)
		t.cylinder(0.0, 0.1, 0.3, 5, _x(Vector3(sx * 0.6, 0.86, 0), Vector3(0, 0, sx * -25.0)), STEEL_D)  # pinchos
		t.cylinder(0.0, 0.1, 0.24, 5, _x(Vector3(sx * 0.5, 0.82, -0.12), Vector3(-25, 0, 0)), STEEL_D)
	var h: MeshBuilder = p["head"]
	h.sphere(0.27, 7, 5, _x(Vector3(0, 0.3, 0)), SKIN_D)
	h.sphere(0.3, 7, 4, _x(Vector3(0, 0.42, 0), Vector3.ZERO, Vector3(1.0, 0.7, 1.0)), Color(0.95, 0.8, 0.1))  # casco de obra
	h.box(Vector3(0.1, 0.07, 0.4), _x(Vector3(0, 0.6, 0)), Color(0.9, 0.75, 0.1))
	h.box(Vector3(0.5, 0.03, 0.2), _x(Vector3(0, 0.38, -0.25)), Color(0.9, 0.75, 0.1))
	h.box(Vector3(0.34, 0.05, 0.05), _x(Vector3(0, 0.32, -0.26), Vector3(0, 0, 0)), BLACK)
	for sx in [-1.0, 1.0]:
		h.sphere(0.04, 4, 3, _x(Vector3(sx * 0.09, 0.32, -0.28)), _g(Color(1, 0.15, 0.1), 1.0))
	h.box(Vector3(0.22, 0.08, 0.03), _x(Vector3(0, 0.16, -0.26)), WHITE)
	_std_arms(p, 0.34, 0.34, 0.13, Color(0.2, 0.22, 0.28), STEEL_D, SKIN_D, 0.12)
	_std_legs(p, 0.8, 0.16, Color(0.22, 0.2, 0.22), BLACK, STEEL, 0.44)
	_attach(rig, p)
	var hm := MeshBuilder.new()
	hm.cylinder(0.05, 0.05, 1.0, 5, _x(Vector3(0, -0.25, -0.3), Vector3(70, 0, 0)), Color(0.4, 0.25, 0.12))
	hm.box(Vector3(0.38, 0.32, 0.55), _x(Vector3(0, -0.15, -0.78), Vector3(70, 0, 0)), STEEL_D)
	hm.box(Vector3(0.4, 0.05, 0.57), _x(Vector3(0, -0.04, -0.82), Vector3(70, 0, 0)), _g(Color(1, 0.25, 0.1), 0.9))
	var wn := Node3D.new()
	wn.name = "Weapon"
	wn.position = Vector3(0, -0.4, 0)
	(rig.j["fore_r"] as Node3D).add_child(wn)
	Mats.mesh_instance(hm.build(), rig.material, wn)
	rig.props["weapon"] = wn
	return rig


static func _boss() -> Rig:
	var rig := make_skeleton({"leg": 0.8, "torso": 0.78, "arm_up": 0.36, "arm_lo": 0.36, "sw": 0.62, "hw": 0.2, "heavy": true})
	var p := _new_parts()
	var tux := Color(0.07, 0.07, 0.1)
	(p["hips"] as MeshBuilder).box(Vector3(0.8, 0.28, 0.5), _x(Vector3(0, 0.03, 0)), tux)
	var t: MeshBuilder = p["torso"]
	t.frustum(Vector2(0.9, 0.62), Vector2(1.1, 0.6), 0.78, _x(Vector3(0, 0.39, 0)), tux)
	t.sphere(0.5, 8, 5, _x(Vector3(0, 0.22, -0.12), Vector3.ZERO, Vector3(1.1, 0.85, 0.85)), tux)       # panza
	t.box(Vector3(0.3, 0.62, 0.03), _x(Vector3(0, 0.42, -0.3)), WHITE)
	t.sphere(0.4, 8, 5, _x(Vector3(0, 0.2, -0.17), Vector3.ZERO, Vector3(1.0, 0.8, 0.5)), Color(0.55, 0.1, 0.18))  # chaleco
	for i in 4:
		t.sphere(0.04, 4, 3, _x(Vector3(0, 0.45 - i * 0.12, -0.36)), _g(GOLD, 0.9))
	t.box(Vector3(0.2, 0.09, 0.04), _x(Vector3(-0.1, 0.72, -0.3), Vector3(0, 0, 12)), RED)              # pajarita
	t.box(Vector3(0.2, 0.09, 0.04), _x(Vector3(0.1, 0.72, -0.3), Vector3(0, 0, -12)), RED)
	t.sphere(0.07, 5, 4, _x(Vector3(0, 0.72, -0.31)), Color(0.6, 0.08, 0.12))
	for sx in [-1.0, 1.0]:
		t.sphere(0.24, 6, 4, _x(Vector3(sx * 0.6, 0.7, 0), Vector3.ZERO, Vector3(1.1, 0.8, 1.1)), tux)
		t.sphere(0.2, 6, 4, _x(Vector3(sx * 0.6, 0.78, 0), Vector3.ZERO, Vector3(1.1, 0.5, 1.1)), _g(GOLD, 0.6))  # charreteras
	# enorme saco de dinero a la espalda
	t.sphere(0.62, 8, 6, _x(Vector3(0, 0.45, 0.55), Vector3.ZERO, Vector3(1.0, 1.1, 0.9)), Color(0.45, 0.35, 0.2))
	t.box(Vector3(0.3, 0.12, 0.3), _x(Vector3(0, 1.05, 0.55)), Color(0.35, 0.27, 0.15))
	t.box(Vector3(0.12, 0.34, 0.03), _x(Vector3(0, 0.45, 1.0)), _g(GOLD, 0.9))
	t.box(Vector3(0.3, 0.08, 0.03), _x(Vector3(0, 0.55, 1.0), Vector3(0, 0, 0)), _g(GOLD, 0.9))
	t.box(Vector3(0.3, 0.08, 0.03), _x(Vector3(0, 0.35, 1.0)), _g(GOLD, 0.9))
	for i in 6:
		t.cylinder(0.12, 0.12, 0.03, 6, _x(Vector3(-0.5 + i * 0.2, 1.1 + (i % 2) * 0.08, 0.5 + (i % 3) * 0.1), Vector3(60 + i * 15, 0, i * 20)), _g(GOLD, 0.8))
	var h: MeshBuilder = p["head"]
	h.sphere(0.34, 8, 6, _x(Vector3(0, 0.34, 0), Vector3.ZERO, Vector3(1.1, 1.0, 1.0)), SKIN)
	h.cylinder(0.3, 0.32, 0.5, 8, _x(Vector3(0, 0.84, 0)), tux)                                               # chistera
	h.cylinder(0.55, 0.55, 0.04, 10, _x(Vector3(0, 0.6, 0)), tux)
	h.cylinder(0.32, 0.32, 0.1, 8, _x(Vector3(0, 0.68, 0)), _g(GOLD, 0.8))
	h.box(Vector3(0.34, 0.07, 0.07), _x(Vector3(-0.15, 0.2, -0.33), Vector3(0, 0, 8)), HAIR)                 # bigote
	h.box(Vector3(0.34, 0.07, 0.07), _x(Vector3(0.15, 0.2, -0.33), Vector3(0, 0, -8)), HAIR)
	h.box(Vector3(0.22, 0.05, 0.04), _x(Vector3(0, 0.12, -0.31)), _g(GOLD, 0.9))                              # dientes de oro
	for sx in [-1.0, 1.0]:
		h.sphere(0.06, 5, 4, _x(Vector3(sx * 0.13, 0.36, -0.3)), WHITE)
		h.sphere(0.03, 4, 3, _x(Vector3(sx * 0.13, 0.36, -0.355)), _g(Color(1, 0.2, 0.1), 1.0))
		h.box(Vector3(0.17, 0.04, 0.04), _x(Vector3(sx * 0.14, 0.45, -0.32), Vector3(0, 0, sx * 20.0)), HAIR)
	h.cylinder(0.1, 0.1, 0.03, 8, _x(Vector3(0.13, 0.36, -0.35), Vector3(90, 0, 0)), _g(GOLD, 0.9), false)  # monóculo
	_std_arms(p, 0.36, 0.36, 0.14, tux, WHITE, SKIN, 0.13)
	_std_legs(p, 0.8, 0.18, tux, Color(0.15, 0.15, 0.17), WHITE, 0.46)
	_attach(rig, p)
	# cañón de oro en el brazo derecho
	var cn := MeshBuilder.new()
	cn.cylinder(0.17, 0.2, 0.9, 8, _x(Vector3(0, -0.2, -0.45), Vector3(90, 0, 0)), _g(GOLD, 0.45))
	cn.cylinder(0.22, 0.22, 0.12, 8, _x(Vector3(0, -0.2, -0.95), Vector3(90, 0, 0)), _g(Color(1.0, 0.9, 0.4), 0.9))
	cn.cylinder(0.12, 0.12, 0.06, 8, _x(Vector3(0, -0.2, -1.0), Vector3(90, 0, 0)), _g(Color(1.0, 0.4, 0.1), 1.0))
	cn.sphere(0.24, 7, 5, _x(Vector3(0, -0.2, -0.05)), _g(GOLD, 0.35))
	var wn := Node3D.new()
	wn.name = "Weapon"
	wn.position = Vector3(0, -0.4, 0)
	(rig.j["fore_r"] as Node3D).add_child(wn)
	Mats.mesh_instance(cn.build(), rig.material, wn)
	rig.props["weapon"] = wn
	return rig
