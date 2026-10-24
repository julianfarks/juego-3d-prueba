class_name TrailerSets
extends RefCounted
## Decorados 3D del tráiler (solo para el tráiler, no se usan en el juego): despacho del abogado, sala del
## tribunal y fondo de ciudad para el logo. Se construyen con el mismo MeshBuilder/material toon del juego
## para que tengan la misma identidad visual que las arenas.

const WOOD := Color(0.42, 0.27, 0.16)
const WOOD_D := Color(0.28, 0.17, 0.1)
const WOOD_L := Color(0.6, 0.42, 0.26)
const WALL := Color(0.86, 0.8, 0.68)
const WALL_D := Color(0.68, 0.6, 0.5)
const GREEN := Color(0.16, 0.36, 0.26)
const PAPER := Color(0.97, 0.96, 0.9)
const GOLD := Color(0.95, 0.75, 0.25)
const RED := Color(0.75, 0.12, 0.12)


static func _x(pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE) -> Transform3D:
	return MeshBuilder.xf(pos, rot, scl)


static func _g(c: Color, amount := 1.0) -> Color:
	return MeshBuilder.glow(c, amount)


static func _mesh(b: MeshBuilder, parent: Node3D) -> MeshInstance3D:
	return Mats.mesh_instance(b.build(), Mats.world_material(), parent)


## Versión en inglés del tráiler (--lang=en): traducción de los rótulos propios del tráiler (no del juego, que solo está en español).
static var lang_en := false
const EN := {
	"EXPEDIENTE 001 · EL CASO DEL SIGLO": "CASE FILE 001 · THE TRIAL OF THE CENTURY",
	"TRIBUNAL SUPERIOR · EL ABOGADO contra LOS LADRONES": "SUPERIOR COURT · THE LAWYER vs. THE THIEVES",
	"UN CASO PERDIDO.": "A LOST CASE.",
	"UNA JUSTICIA\nMUY PERSONAL.": "A VERY PERSONAL\nKIND OF JUSTICE.",
	"CONSTRUYE UNA\nBUILD IMPARABLE.": "BUILD AN\nUNSTOPPABLE BUILD.",
	"NINGÚN LADRÓN\nESTÁ A SALVO.": "NO THIEF\nIS SAFE.",
	"¡NO CULPABLES!": "NOT GUILTY!",
	"¡CULPABLE!": "GUILTY!",
	"«OBJECIÓN… ¡Y A REPARTIR SENTENCIAS!»": "“OBJECTION… AND SENTENCES ARE SERVED!”",
	"LICENCIADO EN DERECHO": "LAW DEGREE",
	"LISTO": "DONE",
	"PRUEBA A": "EXHIBIT A",
	"Huellas del ladrón\nen la escena": "Thief's fingerprints\nat the scene",
	"JUEZ": "JUDGE",
	"COARTADA:\nESTABA EN\nOTRO SITIO": "ALIBI:\nI WAS\nELSEWHERE",
}


static func tr_(t: String) -> String:
	return String(EN.get(t, t)) if lang_en else t


static func label3d(text: String, size := 48, col := Color(0.1, 0.08, 0.06), outline := 0) -> Label3D:
	var l := Label3D.new()
	l.text = tr_(text)
	l.font_size = size
	l.pixel_size = 0.004
	l.modulate = col
	l.outline_size = outline
	l.outline_modulate = Color(1, 1, 1, 0.9)
	l.shaded = false
	l.double_sided = false
	var f = load("res://trailer/fonts/InterDisplay-Black.otf")
	if f != null:
		l.font = f
	return l


# ============================================================================ DESPACHO
static func office() -> Dictionary:
	var root := Node3D.new()
	root.name = "Office"
	var b := MeshBuilder.new()
	# suelo de tarima y alfombra
	b.box(Vector3(12, 0.2, 10), _x(Vector3(0, -0.1, 0)), WOOD_L)
	for i in 12:
		b.box(Vector3(0.02, 0.01, 10), _x(Vector3(-5.5 + i, 0.005, 0)), WOOD)
	b.box(Vector3(5.0, 0.03, 3.4), _x(Vector3(0, 0.015, 0.3)), Color(0.5, 0.1, 0.12))
	b.box(Vector3(4.6, 0.035, 3.0), _x(Vector3(0, 0.02, 0.3)), Color(0.62, 0.16, 0.16))
	# paredes: fondo con zócalo de madera, izquierda y derecha
	b.box(Vector3(12, 4.2, 0.2), _x(Vector3(0, 2.1, -4.0)), WALL)
	b.box(Vector3(12, 1.1, 0.24), _x(Vector3(0, 0.55, -3.95)), WOOD)
	b.box(Vector3(0.2, 4.2, 10), _x(Vector3(-6.0, 2.1, 0)), WALL_D)
	b.box(Vector3(0.2, 4.2, 10), _x(Vector3(6.0, 2.1, 0)), WALL_D)
	# ventanal con la ciudad (hora dorada)
	b.box(Vector3(3.4, 2.4, 0.06), _x(Vector3(2.4, 2.3, -3.86)), Color(0.98, 0.72, 0.45))
	for i in 9:
		var hx := 0.9 + i * 0.36
		var hh := 0.6 + fmod(i * 0.73, 1.0) * 1.2
		b.box(Vector3(0.34, hh, 0.04), _x(Vector3(hx, 1.1 + hh * 0.5, -3.82)), Color(0.32, 0.25, 0.35))
		for w in int(hh / 0.25):
			if (i + w) % 3 != 0:
				b.box(Vector3(0.06, 0.08, 0.02), _x(Vector3(hx - 0.07 + (w % 2) * 0.14, 1.2 + w * 0.22, -3.79)), _g(Color(1.0, 0.85, 0.4), 0.8))
	for sx in [-1.75, 0.0, 1.75]:
		b.box(Vector3(0.1, 2.5, 0.12), _x(Vector3(2.4 + sx * 0.97, 2.3, -3.8)), WOOD_D)
	b.box(Vector3(3.6, 0.12, 0.14), _x(Vector3(2.4, 3.55, -3.8)), WOOD_D)
	b.box(Vector3(3.6, 0.14, 0.3), _x(Vector3(2.4, 1.05, -3.72)), WOOD_D)
	# estantería con libros de derecho
	b.box(Vector3(2.4, 3.2, 0.5), _x(Vector3(-3.3, 1.6, -3.65)), WOOD_D)
	for shelf in 5:
		var y := 0.35 + shelf * 0.62
		b.box(Vector3(2.2, 0.05, 0.42), _x(Vector3(-3.3, y, -3.55)), WOOD)
		var x := -4.3
		var k := 0
		while x < -2.35:
			var w := 0.09 + fmod(k * 0.37 + shelf * 0.21, 0.07)
			var h := 0.38 + fmod(k * 0.53 + shelf * 0.11, 0.16)
			var cols := [Color(0.5, 0.12, 0.12), Color(0.12, 0.22, 0.45), GREEN, Color(0.55, 0.42, 0.2), Color(0.25, 0.2, 0.3)]
			b.box(Vector3(w, h, 0.32), _x(Vector3(x + w * 0.5, y + 0.025 + h * 0.5, -3.52)), cols[(k + shelf) % cols.size()])
			b.box(Vector3(w * 0.7, 0.03, 0.33), _x(Vector3(x + w * 0.5, y + 0.03 + h * 0.75, -3.52)), _g(GOLD, 0.2))
			x += w + 0.015
			k += 1
	# diploma
	b.box(Vector3(1.0, 0.75, 0.06), _x(Vector3(-0.6, 2.55, -3.86)), GOLD)
	b.box(Vector3(0.86, 0.6, 0.07), _x(Vector3(-0.6, 2.55, -3.85)), PAPER)
	b.cylinder(0.08, 0.08, 0.02, 10, _x(Vector3(-0.35, 2.38, -3.8), Vector3(90, 0, 0)), _g(RED, 0.3))
	# escritorio
	b.box(Vector3(2.6, 0.1, 1.2), _x(Vector3(-0.9, 0.95, -1.6)), WOOD)
	b.box(Vector3(2.5, 0.85, 1.1), _x(Vector3(-0.9, 0.45, -1.62)), WOOD_D)
	b.box(Vector3(2.2, 0.02, 0.8), _x(Vector3(-0.9, 1.01, -1.6)), GREEN)
	for i in 5:
		b.box(Vector3(0.42, 0.03, 0.56), _x(Vector3(-1.75, 1.03 + i * 0.03, -1.55), Vector3(0, i * 7.0, 0)), PAPER)
	b.cylinder(0.08, 0.12, 0.05, 8, _x(Vector3(0.05, 1.03, -1.85)), WOOD_D)                          # lámpara
	b.cylinder(0.02, 0.02, 0.5, 6, _x(Vector3(0.05, 1.3, -1.85)), GOLD)
	b.frustum(Vector2(0.45, 0.3), Vector2(0.25, 0.18), 0.2, _x(Vector3(0.05, 1.58, -1.85)), _g(Color(0.15, 0.45, 0.25), 0.2))
	b.box(Vector3(0.3, 0.12, 0.2), _x(Vector3(-0.55, 1.06, -1.95)), Color(0.15, 0.15, 0.17))         # sello
	b.cylinder(0.05, 0.05, 0.16, 6, _x(Vector3(-0.55, 1.2, -1.95)), WOOD_D)
	# planta
	b.cylinder(0.22, 0.17, 0.45, 8, _x(Vector3(4.8, 0.22, -3.2)), Color(0.75, 0.42, 0.25))
	for i in 7:
		var a := TAU * i / 7.0
		b.sphere(0.28, 6, 4, _x(Vector3(4.8 + cos(a) * 0.22, 0.75 + fmod(i * 0.37, 0.4), -3.2 + sin(a) * 0.22)), Color(0.2, 0.5, 0.25))
	_mesh(b, root)
	var dip := label3d("LICENCIADO EN DERECHO", 26, Color(0.25, 0.15, 0.1))
	dip.position = Vector3(-0.6, 2.7, -3.8)
	root.add_child(dip)
	# documento para sellar (aparece el sello rojo al estamparlo)
	var doc := Node3D.new()
	doc.name = "Doc"
	doc.position = Vector3(-0.9, 1.03, -1.35)
	root.add_child(doc)
	var db := MeshBuilder.new()
	db.box(Vector3(0.5, 0.012, 0.66), _x(), PAPER)
	for i in 6:
		db.box(Vector3(0.34, 0.004, 0.02), _x(Vector3(0, 0.008, -0.22 + i * 0.07)), Color(0.4, 0.4, 0.45))
	_mesh(db, doc)
	var seal := label3d("LISTO", 64, Color(0.85, 0.08, 0.1))
	seal.name = "Seal"
	seal.rotation_degrees = Vector3(-90, 0, 12)
	seal.position = Vector3(0, 0.02, 0.1)
	seal.visible = false
	doc.add_child(seal)
	# luces: cálida de la ventana y lámpara
	var sun := OmniLight3D.new()
	sun.position = Vector3(2.4, 2.6, -2.2)
	sun.light_color = Color(1.0, 0.75, 0.5)
	sun.light_energy = 2.2
	sun.omni_range = 9.0
	root.add_child(sun)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0.05, 1.5, -1.6)
	lamp.light_color = Color(1.0, 0.85, 0.6)
	lamp.light_energy = 1.2
	lamp.omni_range = 3.5
	root.add_child(lamp)
	var fill := OmniLight3D.new()
	fill.position = Vector3(0, 2.4, 3.5)
	fill.light_color = Color(0.85, 0.9, 1.0)
	fill.light_energy = 1.0
	fill.omni_range = 10.0
	root.add_child(fill)
	return {"root": root, "doc": doc, "seal": seal, "lights": [sun, lamp, fill]}


# ============================================================================ TRIBUNAL
static func court() -> Dictionary:
	var root := Node3D.new()
	root.name = "Court"
	var b := MeshBuilder.new()
	# suelo ajedrezado de mármol
	for ix in 14:
		for iz in 12:
			var c := Color(0.82, 0.8, 0.76) if (ix + iz) % 2 == 0 else Color(0.36, 0.3, 0.28)
			b.box(Vector3(1, 0.2, 1), _x(Vector3(-6.5 + ix, -0.1, -5.5 + iz)), c)
	# pared del fondo con paneles de madera y escudo de la balanza
	b.box(Vector3(14, 6, 0.3), _x(Vector3(0, 3, -6.0)), WOOD_D)
	for i in 7:
		b.box(Vector3(1.6, 3.6, 0.06), _x(Vector3(-6 + i * 2.0, 2.2, -5.83)), WOOD)
	b.box(Vector3(14, 0.3, 0.4), _x(Vector3(0, 4.3, -5.8)), WOOD_L)
	b.cylinder(1.0, 1.0, 0.1, 20, _x(Vector3(0, 4.9, -5.78), Vector3(90, 0, 0)), _g(GOLD, 0.35))
	b.cylinder(0.85, 0.85, 0.12, 20, _x(Vector3(0, 4.9, -5.75), Vector3(90, 0, 0)), Color(0.18, 0.2, 0.35))
	b.box(Vector3(0.08, 0.9, 0.05), _x(Vector3(0, 4.85, -5.66)), _g(GOLD, 0.6))
	b.box(Vector3(1.0, 0.06, 0.05), _x(Vector3(0, 5.25, -5.66)), _g(GOLD, 0.6))
	for sx in [-1.0, 1.0]:
		b.cylinder(0.2, 0.05, 0.12, 8, _x(Vector3(sx * 0.45, 4.95, -5.66)), _g(GOLD, 0.6))
	# paredes laterales con columnas
	for sx in [-1.0, 1.0]:
		b.box(Vector3(0.3, 6, 12), _x(Vector3(sx * 7.0, 3, 0)), WALL_D)
		for iz in 3:
			b.cylinder(0.32, 0.36, 5.6, 10, _x(Vector3(sx * 6.4, 2.8, -4.0 + iz * 3.5)), Color(0.9, 0.88, 0.82))
	# estrado del juez
	b.box(Vector3(4.2, 0.5, 2.0), _x(Vector3(0, 0.25, -4.4)), WOOD_D)
	b.box(Vector3(3.8, 1.75, 0.6), _x(Vector3(0, 1.375, -3.6)), WOOD)
	b.box(Vector3(4.0, 0.12, 0.85), _x(Vector3(0, 2.3, -3.65)), WOOD_L)
	b.box(Vector3(1.6, 0.9, 0.04), _x(Vector3(0, 1.35, -3.28)), WOOD_D)
	b.cylinder(0.32, 0.32, 0.04, 14, _x(Vector3(0, 1.4, -3.25), Vector3(90, 0, 0)), _g(GOLD, 0.5))
	b.box(Vector3(0.7, 0.18, 0.4), _x(Vector3(0.95, 2.45, -3.7)), WOOD_D)                       # bloque del martillo
	# mesas: abogado (izquierda) y defensa (derecha)
	for sx in [-1.0, 1.0]:
		b.box(Vector3(2.8, 0.1, 1.1), _x(Vector3(sx * 2.6, 0.85, 0.4)), WOOD)
		b.box(Vector3(2.7, 0.8, 0.08), _x(Vector3(sx * 2.6, 0.42, 0.9)), WOOD_D)
		for lx in [-1.2, 1.2]:
			b.box(Vector3(0.1, 0.85, 0.9), _x(Vector3(sx * 2.6 + lx, 0.42, 0.4)), WOOD_D)
	for i in 3:
		b.box(Vector3(0.38, 0.03, 0.5), _x(Vector3(-2.9 + i * 0.05, 0.92 + i * 0.03, 0.35), Vector3(0, i * 9.0, 0)), PAPER)
	# barandilla del público y bancos
	b.box(Vector3(12, 0.08, 0.12), _x(Vector3(0, 1.0, 2.4)), WOOD_L)
	for i in 13:
		b.box(Vector3(0.07, 1.0, 0.07), _x(Vector3(-6 + i, 0.5, 2.4)), WOOD)
	for row in 2:
		for sx in [-1.0, 1.0]:
			b.box(Vector3(4.4, 0.12, 0.6), _x(Vector3(sx * 3.4, 0.5, 3.6 + row * 1.4)), WOOD)
			b.box(Vector3(4.4, 0.7, 0.1), _x(Vector3(sx * 3.4, 0.85, 3.95 + row * 1.4)), WOOD_D)
	# atril con la PRUEBA
	b.box(Vector3(0.1, 1.6, 0.1), _x(Vector3(0, 0.8, -1.0), Vector3(-8, 0, 0)), WOOD_D)
	for sx in [-0.35, 0.35]:
		b.box(Vector3(0.08, 1.5, 0.08), _x(Vector3(sx, 0.75, -0.85), Vector3(10, 0, sx * 20)), WOOD_D)
	_mesh(b, root)
	var evid := Node3D.new()
	evid.name = "Evidence"
	evid.position = Vector3(0, 1.45, -0.86)
	evid.rotation_degrees = Vector3(-10, 0, 0)
	root.add_child(evid)
	var eb := MeshBuilder.new()
	eb.box(Vector3(0.75, 0.95, 0.03), _x(), PAPER)
	eb.box(Vector3(0.6, 0.02, 0.01), _x(Vector3(0, -0.12, 0.02)), Color(0.4, 0.4, 0.45))
	eb.box(Vector3(0.6, 0.02, 0.01), _x(Vector3(0, -0.2, 0.02)), Color(0.4, 0.4, 0.45))
	eb.box(Vector3(0.45, 0.02, 0.01), _x(Vector3(0, -0.28, 0.02)), Color(0.4, 0.4, 0.45))
	_mesh(eb, evid)
	var el := label3d("PRUEBA A", 64, RED)
	el.position = Vector3(0, 0.22, 0.03)
	evid.add_child(el)
	var el2 := label3d("Huellas del ladrón\nen la escena", 26, Color(0.2, 0.2, 0.25))
	el2.position = Vector3(0, 0.0, 0.03)
	evid.add_child(el2)
	var plate := label3d("JUEZ", 46, GOLD)
	plate.position = Vector3(0, 1.95, -3.28)
	root.add_child(plate)
	var lights: Array = []
	for p in [Vector3(0, 4.5, -2.0), Vector3(-3.5, 4.0, 2.0), Vector3(3.5, 4.0, 2.0)]:
		var l := OmniLight3D.new()
		l.position = p
		l.light_color = Color(1.0, 0.9, 0.75)
		l.light_energy = 1.6
		l.omni_range = 11.0
		root.add_child(l)
		lights.append(l)
	return {"root": root, "evidence": evid, "lights": lights}


## Juez: el mismo esqueleto del abogado con toga negra, peluca blanca y martillo (sin maletín).
static func judge() -> Rig:
	var rig := ModelFactory.build_lawyer()
	(rig.props["case"] as Node3D).visible = false
	var robe := MeshBuilder.new()
	robe.frustum(Vector2(0.78, 0.5), Vector2(0.7, 0.44), 0.74, _x(Vector3(0, 0.3, 0)), Color(0.08, 0.08, 0.1))
	robe.box(Vector3(0.2, 0.3, 0.04), _x(Vector3(0, 0.45, -0.23)), Color(0.95, 0.95, 0.95))
	Mats.mesh_instance(robe.build(), rig.material, rig.j["torso"])
	var skirt := MeshBuilder.new()
	skirt.frustum(Vector2(0.9, 0.6), Vector2(0.62, 0.42), 0.9, _x(Vector3(0, -0.4, 0)), Color(0.08, 0.08, 0.1))
	Mats.mesh_instance(skirt.build(), rig.material, rig.j["hips"])
	for arm in ["arm_l", "arm_r", "fore_l", "fore_r"]:
		var sl := MeshBuilder.new()
		sl.cylinder(0.11, 0.13, 0.32, 6, _x(Vector3(0, -0.15, 0)), Color(0.08, 0.08, 0.1))
		Mats.mesh_instance(sl.build(), rig.material, rig.j[arm])
	var wig := MeshBuilder.new()
	wig.sphere(0.31, 8, 5, _x(Vector3(0, 0.42, 0.03), Vector3.ZERO, Vector3(1.05, 0.8, 1.05)), Color(0.96, 0.95, 0.92))
	for sx in [-1.0, 1.0]:
		for k in 3:
			wig.sphere(0.1, 6, 4, _x(Vector3(sx * 0.3, 0.32 - k * 0.11, 0.05)), Color(0.94, 0.93, 0.9))
	Mats.mesh_instance(wig.build(), rig.material, rig.j["head"])
	var gav := Node3D.new()
	gav.name = "Gavel"
	gav.position = Vector3(0, -0.34, 0)
	(rig.j["fore_r"] as Node3D).add_child(gav)
	var gb := MeshBuilder.new()
	gb.cylinder(0.025, 0.025, 0.42, 6, _x(Vector3(0, -0.05, -0.15), Vector3(90, 0, 0)), WOOD_L)
	gb.cylinder(0.08, 0.08, 0.26, 8, _x(Vector3(0, -0.05, -0.38), Vector3(0, 0, 90)), WOOD_D)
	gb.cylinder(0.085, 0.085, 0.03, 8, _x(Vector3(0.12, -0.05, -0.38), Vector3(0, 0, 90)), _g(GOLD, 0.4))
	gb.cylinder(0.085, 0.085, 0.03, 8, _x(Vector3(-0.12, -0.05, -0.38), Vector3(0, 0, 90)), _g(GOLD, 0.4))
	Mats.mesh_instance(gb.build(), rig.material, gav)
	rig.props["gavel"] = gav
	return rig


## Expresiones extra para la cabeza del abogado (boca abierta, cejas, destello de gafas).
static func add_expressions(rig: Rig) -> Dictionary:
	var head: Node3D = rig.j["head"]
	var out := {}
	var mo := MeshBuilder.new()
	mo.sphere(0.06, 8, 5, _x(Vector3(0, 0.0, 0), Vector3.ZERO, Vector3(1.2, 1.35, 0.4)), Color(0.18, 0.04, 0.06))
	var mouth := Node3D.new()
	mouth.position = Vector3(0, 0.17, -0.268)
	head.add_child(mouth)
	Mats.mesh_instance(mo.build(), rig.material, mouth)
	mouth.visible = false
	out["mouth_o"] = mouth
	var angry := Node3D.new()
	head.add_child(angry)
	var ab := MeshBuilder.new()
	for sx in [-1.0, 1.0]:
		ab.box(Vector3(0.16, 0.045, 0.04), _x(Vector3(sx * 0.105, 0.405, -0.285), Vector3(0, 0, sx * 30.0)), Color(0.08, 0.06, 0.05))
	Mats.mesh_instance(ab.build(), rig.material, angry)
	angry.visible = false
	out["brows_angry"] = angry
	var up := Node3D.new()
	head.add_child(up)
	var ub := MeshBuilder.new()
	for sx in [-1.0, 1.0]:
		ub.box(Vector3(0.14, 0.035, 0.04), _x(Vector3(sx * 0.115, 0.47, -0.27), Vector3(0, 0, sx * -16.0)), Color(0.08, 0.06, 0.05))
	Mats.mesh_instance(ub.build(), rig.material, up)
	up.visible = false
	out["brows_up"] = up
	var glint := Node3D.new()
	glint.position = Vector3(0.13, 0.37, -0.31)
	head.add_child(glint)
	var gm := MeshBuilder.new()
	gm.box(Vector3(0.12, 0.018, 0.01), _x(Vector3.ZERO, Vector3(0, 0, 45)), _g(Color(1, 1, 1), 1.0))
	gm.box(Vector3(0.12, 0.018, 0.01), _x(Vector3.ZERO, Vector3(0, 0, -45)), _g(Color(1, 1, 1), 1.0))
	Mats.mesh_instance(gm.build(), Mats.world_material(), glint)
	glint.scale = Vector3.ZERO
	out["glint"] = glint
	return out


## Maletín grande de atrezo con tapa articulada y brillo dentro (primer plano de la decisión).
static func hero_case() -> Dictionary:
	var root := Node3D.new()
	var b := MeshBuilder.new()
	var leather := Color(0.4, 0.2, 0.1)
	b.box(Vector3(0.9, 0.12, 0.6), _x(Vector3(0, 0.06, 0)), leather)
	b.box(Vector3(0.9, 0.3, 0.04), _x(Vector3(0, 0.15, 0.28)), leather)
	b.box(Vector3(0.9, 0.3, 0.04), _x(Vector3(0, 0.15, -0.28)), leather)
	b.box(Vector3(0.04, 0.3, 0.6), _x(Vector3(0.43, 0.15, 0)), leather)
	b.box(Vector3(0.04, 0.3, 0.6), _x(Vector3(-0.43, 0.15, 0)), leather)
	b.box(Vector3(0.8, 0.02, 0.5), _x(Vector3(0, 0.13, 0)), _g(Color(1.0, 0.82, 0.35), 1.0))
	for i in 4:
		b.box(Vector3(0.6, 0.015, 0.4), _x(Vector3(0, 0.15 + i * 0.02, 0), Vector3(0, i * 6.0 - 8.0, 0)), PAPER)
	_mesh(b, root)
	var lid := Node3D.new()
	lid.position = Vector3(0, 0.3, -0.3)
	root.add_child(lid)
	var lb := MeshBuilder.new()
	lb.box(Vector3(0.92, 0.06, 0.62), _x(Vector3(0, 0.0, 0.31)), leather.lightened(0.1))
	for sx in [-0.3, 0.3]:
		lb.box(Vector3(0.1, 0.07, 0.06), _x(Vector3(sx, -0.02, 0.6)), _g(GOLD, 0.5))
	lb.box(Vector3(0.3, 0.05, 0.08), _x(Vector3(0, 0.05, 0.31)), Color(0.2, 0.2, 0.22))
	_mesh(lb, lid)
	var glow := OmniLight3D.new()
	glow.position = Vector3(0, 0.5, 0)
	glow.light_color = Color(1.0, 0.8, 0.35)
	glow.light_energy = 0.0
	glow.omni_range = 2.5
	root.add_child(glow)
	return {"root": root, "lid": lid, "light": glow}


## Cartel de coartada que levanta un ladrón.
static func alibi_sign() -> Node3D:
	var root := Node3D.new()
	var b := MeshBuilder.new()
	b.box(Vector3(1.0, 0.62, 0.04), _x(Vector3(0, 0.0, 0)), PAPER)
	b.box(Vector3(1.04, 0.66, 0.03), _x(Vector3(0, 0.0, 0.01)), Color(0.55, 0.4, 0.25))
	b.box(Vector3(0.05, 0.7, 0.05), _x(Vector3(0, -0.6, 0.03)), WOOD)
	_mesh(b, root)
	var l := label3d("COARTADA:\nESTABA EN\nOTRO SITIO", 40, Color(0.12, 0.1, 0.1))
	l.position = Vector3(0, 0.0, -0.025)
	l.rotation_degrees = Vector3(0, 180, 0)
	root.add_child(l)
	return root


## Ciudad nocturna con siluetas para el fondo del logo.
static func skyline() -> Dictionary:
	var root := Node3D.new()
	root.name = "Skyline"
	var b := MeshBuilder.new()
	# cielo de atardecer en bandas
	var bands := [Color(0.98, 0.55, 0.25), Color(0.92, 0.38, 0.3), Color(0.7, 0.25, 0.4), Color(0.4, 0.18, 0.42), Color(0.18, 0.12, 0.32), Color(0.08, 0.07, 0.2)]
	for i in bands.size():
		b.box(Vector3(160, 6.2, 0.2), _x(Vector3(0, 2.0 + i * 6.0, -60)), _g(bands[i], 0.9))
	b.sphere(7.0, 16, 10, _x(Vector3(-14, 6.0, -58)), _g(Color(1.0, 0.82, 0.45), 1.0))
	# tres capas de edificios
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	for layer in 3:
		var z := -40.0 + layer * 12.0
		var col: Color = [Color(0.22, 0.14, 0.3), Color(0.14, 0.09, 0.2), Color(0.06, 0.04, 0.1)][layer]
		var x := -70.0
		while x < 70.0:
			var w := rng.randf_range(3.0, 7.0)
			var h := rng.randf_range(6.0, 22.0) * (1.0 - layer * 0.22)
			b.box(Vector3(w, h, 3.0), _x(Vector3(x + w * 0.5, h * 0.5 - 2.0, z)), col)
			if layer < 2:
				var wy := 0.0
				while wy < h - 2.5:
					for wx in int(w / 1.2):
						if rng.randf() < 0.35:
							b.box(Vector3(0.45, 0.6, 0.1), _x(Vector3(x + 0.6 + wx * 1.2, wy, z + 1.55)), _g(Color(1.0, 0.8, 0.35), 0.7))
					wy += 1.6
			x += w + rng.randf_range(0.2, 1.2)
	# azotea en primer plano
	b.box(Vector3(80, 1.0, 10), _x(Vector3(0, -2.2, -6)), Color(0.03, 0.02, 0.06))
	_mesh(b, root)
	return {"root": root}
