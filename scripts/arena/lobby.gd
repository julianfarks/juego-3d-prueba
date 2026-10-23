class_name Lobby
extends Node3D
## Sala Central ("El Vestíbulo del Bufete"): espacio 3D donde el jugador prepara la próxima partida.
## Zonas (todas con distancias cortas desde el punto de aparición):
##   Norte  – portales NUEVA PARTIDA y CONTINUAR PARTIDA.
##   Oeste  – La Armería: 4 pedestales (herramienta, habilidad, estilo, equipo).
##   Este   – Mesa del Juez (dificultad), El Despacho (mejoras permanentes), Archivo de Casos (estadísticas).
##   Sur    – Zona de Práctica con muñecos que usan el sistema de combate real.
## Cada estación es un Interactable: al activarla se emite 'station_activated' y Main abre la interfaz.
## Idea inspirada en un vestíbulo de partida, pero con identidad propia (un bufete fantástico y absurdo).

signal station_activated(id: String)

const HALF := 22.0
const PAL := {
	"name": "Vestíbulo del Bufete",
	"floor_a": Color(0.74, 0.7, 0.62), "floor_b": Color(0.66, 0.62, 0.55), "floor_line": Color(0.75, 0.55, 0.2),
	"floor_style": "cross", "ground": Color(0.05, 0.05, 0.09),
	"wall": Color(0.5, 0.18, 0.2), "wall_accent": Color(1.0, 0.76, 0.2), "wall_style": "wall",
	"building": Color(0.1, 0.1, 0.18), "window": Color(1.0, 0.85, 0.5), "towers": 22,
	"marble": Color(0.92, 0.9, 0.85), "metal": Color(0.45, 0.47, 0.5), "wood": Color(0.45, 0.28, 0.15),
	"paints": [Color(0.55, 0.15, 0.2), Color(0.15, 0.3, 0.5), Color(0.8, 0.7, 0.3)],
	"platform": Color(0.72, 0.7, 0.64),
	"sky": Color(0.1, 0.1, 0.2), "fog": Color(0.2, 0.18, 0.3), "ambient": Color(0.82, 0.8, 0.9), "sun": Color(1.0, 0.92, 0.8),
	"kinds": ["pillar"],
}
const ZONE_COLORS := {
	"portal_new": Color(0.55, 0.4, 1.0), "portal_cont": Color(1.0, 0.8, 0.25), "armory": Color(0.3, 0.85, 1.0),
	"difficulty": Color(1.0, 0.4, 0.35), "meta": Color(0.4, 1.0, 0.6), "stats": Color(0.5, 0.65, 1.0),
	"practice": Color(1.0, 0.65, 0.25),
}

var stations: Dictionary = {}        # id -> Interactable
var dummies: Array = []
var _pedestals: Dictionary = {}      # slot -> {"model": Node3D, "name": Label3D, "base_y": float}
var _cont_label: Label3D
var _cont_sub: Label3D
var _diff_sign: Label3D
var _diff_sub: Label3D
var _diff_disc: MeshInstance3D
var _portal_cont: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _model_cache_key: Dictionary = {}


func spawn_position() -> Vector3:
	return Vector3(0, 0.3, 8.0)


func build() -> void:
	name = "Lobby"
	_rng.seed = 2024
	var q: Dictionary = Config.quality()
	# --- entorno y luz ---
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = PAL["sky"]
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = PAL["ambient"]
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = PAL["fog"]
	env.fog_density = 0.004
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = PAL["sun"]
	sun.light_energy = 1.0
	sun.rotation_degrees = Vector3(-55.0, 25.0, 0.0)
	sun.shadow_enabled = bool(q["shadows"])
	sun.directional_shadow_max_distance = 50.0
	add_child(sun)
	# --- suelo, muros, horizonte ---
	Mats.mesh_instance(PropsFactory.floor_mesh(HALF, PAL, _rng), Mats.world_material(), self).name = "Floor"
	Mats.mesh_instance(PropsFactory.wall_visual(HALF, PAL, _rng), Mats.world_material(), self).name = "WallVisual"
	var sky := Mats.mesh_instance(PropsFactory.skyline(HALF, PAL, _rng), Mats.world_material(), self)
	sky.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in PropsFactory.wall_colliders(HALF):
		add_child(c)
	_build_decor()
	_build_portals()
	_build_armory()
	_build_difficulty()
	_build_desks()
	_build_practice()
	refresh()


# ------------------------------------------------------------------ utilidades de construcción
func _station(id: String, pos: Vector3, prompt: String, action: String, radius: float, ind_text: String, ind_h: float, color: Color) -> Interactable:
	var it := Interactable.new()
	it.kind = "station"
	it.prompt = prompt
	it.action_text = action
	it.radius = radius
	it.position = pos
	it.setup_indicator(ind_text, ind_h, color)
	it.callback = func(_i): station_activated.emit(id)
	add_child(it)
	stations[id] = it
	return it


func _label(text: String, pos: Vector3, size: int, color: Color, pixel := 0.01, parent: Node = null) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.shaded = false
	l.font_size = size
	l.pixel_size = pixel
	l.outline_size = int(size * 0.28)
	l.modulate = color
	l.outline_modulate = Color(0.04, 0.03, 0.08, 0.95)
	l.position = pos
	l.render_priority = 5
	(parent if parent != null else self).add_child(l)
	return l


func _zone_disc(pos: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = 0.03
	cm.radial_segments = 28
	mi.mesh = cm
	mi.material_override = Mats.fx_material(Color(color.r, color.g, color.b, 0.34), false)
	mi.position = pos + Vector3(0, 0.03, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _block(size: Vector3, pos: Vector3, color: Color, solid := true) -> void:
	var b := MeshBuilder.new()
	b.box(size, MeshBuilder.xf(Vector3(0, size.y * 0.5, 0)), color)
	var holder := Node3D.new()
	holder.position = pos
	add_child(holder)
	Mats.mesh_instance(b.build(), Mats.world_material(), holder)
	if solid:
		holder.add_child(PropsFactory.static_body(size, Vector3(0, size.y * 0.5, 0)))


# ------------------------------------------------------------------ decoración central
func _build_decor() -> void:
	# emblema de balanza en el centro
	var b := MeshBuilder.new()
	b.cylinder(3.2, 3.3, 0.06, 24, MeshBuilder.xf(Vector3(0, 0.03, 0)), Color(0.85, 0.65, 0.2))
	b.cylinder(2.8, 2.9, 0.08, 24, MeshBuilder.xf(Vector3(0, 0.05, 0)), Color(0.18, 0.2, 0.35))
	b.box(Vector3(0.18, 0.1, 5.0), MeshBuilder.xf(Vector3(0, 0.12, 0)), Color(1.0, 0.8, 0.3))
	b.box(Vector3(4.2, 0.1, 0.18), MeshBuilder.xf(Vector3(0, 0.12, -0.6)), Color(1.0, 0.8, 0.3))
	for sx in [-2.0, 2.0]:
		b.cylinder(0.85, 0.85, 0.1, 14, MeshBuilder.xf(Vector3(sx, 0.12, 0.7)), Color(1.0, 0.8, 0.3))
		b.cylinder(0.7, 0.7, 0.12, 14, MeshBuilder.xf(Vector3(sx, 0.13, 0.7)), Color(0.18, 0.2, 0.35))
	Mats.mesh_instance(b.build(), Mats.world_material(), self)
	# columnas en las esquinas
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var ob := PropsFactory.make_obstacle("pillar", _rng, PAL)
			var n: Node3D = ob["node"]
			n.position = Vector3(sx * (HALF - 2.5), 0, sz * (HALF - 2.5))
			add_child(n)
	_label("VESTÍBULO DEL BUFETE", Vector3(0, 6.5, 2.0), 64, Color(1.0, 0.85, 0.35), 0.012)


# ------------------------------------------------------------------ portales (norte)
func _build_portals() -> void:
	var z := -17.0
	# NUEVA PARTIDA
	var pn := PropsFactory.portal_node()
	var holder_n := Node3D.new()
	holder_n.position = Vector3(-6.5, 0, z)
	add_child(holder_n)
	holder_n.add_child(pn["root"])
	_zone_disc(Vector3(-6.5, 0, z + 3.2), 3.4, ZONE_COLORS["portal_new"])
	_label("NUEVA PARTIDA", Vector3(-6.5, 5.7, z), 76, ZONE_COLORS["portal_new"].lightened(0.35), 0.0125)
	_diff_sub = _label("", Vector3(-6.5, 4.95, z), 40, Color(0.9, 0.9, 1.0), 0.011)
	_station("new_run", Vector3(-6.5, 0, z + 2.6), "Entrar al portal: NUEVA PARTIDA", "ENTRAR", 3.6, "ENTRAR", 5.0, ZONE_COLORS["portal_new"].lightened(0.3)).ind_scale = 0.625
	# CONTINUAR PARTIDA
	var pc := PropsFactory.portal_node()
	_portal_cont = pc
	var holder_c := Node3D.new()
	holder_c.position = Vector3(6.5, 0, z)
	add_child(holder_c)
	holder_c.add_child(pc["root"])
	(pc["light"] as OmniLight3D).light_color = Color(1.0, 0.8, 0.3)
	_zone_disc(Vector3(6.5, 0, z + 3.2), 3.4, ZONE_COLORS["portal_cont"])
	_cont_label = _label("CONTINUAR PARTIDA", Vector3(6.5, 5.7, z), 76, ZONE_COLORS["portal_cont"], 0.0125)
	_cont_sub = _label("", Vector3(6.5, 4.95, z), 40, Color(0.9, 0.95, 0.8), 0.011)
	_station("continue", Vector3(6.5, 0, z + 2.6), "Entrar al portal: CONTINUAR PARTIDA", "CONTINUAR", 3.6, "CONTINUAR", 5.0, ZONE_COLORS["portal_cont"]).ind_scale = 0.625


# ------------------------------------------------------------------ armería (oeste)
func _build_armory() -> void:
	var x := -14.5
	_zone_disc(Vector3(x, 0, 0), 6.5, ZONE_COLORS["armory"])
	_label("LA ARMERÍA", Vector3(x - 1.5, 6.0, 0), 80, ZONE_COLORS["armory"].lightened(0.3), 0.0135)
	var slots := LoadoutDB.SLOTS
	var short := {"weapon": "HERRAMIENTA", "skill": "HABILIDAD", "tactic": "ESTILO", "gear": "EQUIPO"}
	for i in slots.size():
		var slot: String = slots[i]
		var pos := Vector3(x, 0, -7.5 + i * 5.0)
		var b := MeshBuilder.new()
		b.cylinder(1.15, 1.3, 0.25, 12, MeshBuilder.xf(Vector3(0, 0.125, 0)), Color(0.35, 0.36, 0.42))
		b.cylinder(0.85, 1.0, 0.85, 10, MeshBuilder.xf(Vector3(0, 0.67, 0)), PAL["marble"])
		b.cylinder(1.0, 1.0, 0.1, 10, MeshBuilder.xf(Vector3(0, 1.14, 0)), Color(0.85, 0.65, 0.2))
		b.cylinder(0.8, 0.8, 0.06, 10, MeshBuilder.xf(Vector3(0, 1.2, 0)), MeshBuilder.glow(ZONE_COLORS["armory"], 0.9))
		var holder := Node3D.new()
		holder.position = pos
		add_child(holder)
		Mats.mesh_instance(b.build(), Mats.world_material(), holder)
		holder.add_child(PropsFactory.static_body(Vector3(2.0, 1.2, 2.0), Vector3(0, 0.6, 0)))
		var model := Node3D.new()
		model.position = Vector3(0, 2.15, 0)
		holder.add_child(model)
		_label(short[slot], Vector3(0, 4.15, 0), 44, Color(1, 1, 1), 0.01, holder)
		var nm := _label("", Vector3(0, 3.55, 0), 38, Color(1.0, 0.9, 0.5), 0.0095, holder)
		_pedestals[slot] = {"model": model, "name": nm, "item": ""}
		var st := _station("equip:" + slot, pos + Vector3(2.2, 0, 0), "%s" % LoadoutDB.SLOT_NAMES[slot], "ELEGIR", 2.9, "ELEGIR", 3.0, ZONE_COLORS["armory"].lightened(0.35))
		st.ind_scale = 0.62
		st.position = pos + Vector3(2.0, 0, 0)


# ------------------------------------------------------------------ dificultad (este, norte)
func _build_difficulty() -> void:
	var pos := Vector3(14.5, 0, -8.5)
	_diff_disc = _zone_disc(pos, 4.0, ZONE_COLORS["difficulty"])
	_diff_disc.material_override = (_diff_disc.material_override as StandardMaterial3D).duplicate()   # material propio (cambia de color)
	var b := MeshBuilder.new()
	b.cylinder(1.5, 1.7, 0.3, 10, MeshBuilder.xf(Vector3(0, 0.15, 0)), Color(0.32, 0.18, 0.18))
	b.box(Vector3(2.4, 1.0, 1.4), MeshBuilder.xf(Vector3(0, 0.8, 0)), Color(0.5, 0.28, 0.16))
	b.box(Vector3(2.6, 0.12, 1.6), MeshBuilder.xf(Vector3(0, 1.36, 0)), Color(0.85, 0.82, 0.75))
	b.box(Vector3(0.7, 0.18, 0.45), MeshBuilder.xf(Vector3(0.6, 1.5, 0)), Color(0.5, 0.3, 0.15))                       # mazo
	b.cylinder(0.12, 0.12, 0.55, 6, MeshBuilder.xf(Vector3(0.2, 1.55, 0), Vector3(0, 0, 90)), Color(0.4, 0.22, 0.1))
	b.cylinder(0.3, 0.3, 0.1, 10, MeshBuilder.xf(Vector3(-0.7, 1.47, 0)), Color(0.85, 0.2, 0.2))
	var holder := Node3D.new()
	holder.position = pos
	add_child(holder)
	Mats.mesh_instance(b.build(), Mats.world_material(), holder)
	holder.add_child(PropsFactory.static_body(Vector3(2.8, 1.5, 1.8), Vector3(0, 0.75, 0)))
	_label("MESA DEL JUEZ", pos + Vector3(1.5, 4.6, 0), 60, ZONE_COLORS["difficulty"].lightened(0.3), 0.012)
	_diff_sign = _label("", pos + Vector3(1.5, 3.7, 0), 56, Color(1, 1, 1), 0.012)
	_station("difficulty", pos + Vector3(-2.4, 0, 0), "Mesa del Juez: elegir dificultad", "DIFICULTAD", 3.0, "DIFICULTAD", 2.8, ZONE_COLORS["difficulty"].lightened(0.3)).ind_scale = 0.62


# ------------------------------------------------------------------ despacho y archivo (este)
func _build_desks() -> void:
	# Despacho (mejoras permanentes)
	var p1 := Vector3(14.5, 0, 0.5)
	_zone_disc(p1, 3.8, ZONE_COLORS["meta"])
	var b := MeshBuilder.new()
	b.box(Vector3(2.8, 1.0, 1.5), MeshBuilder.xf(Vector3(0, 0.5, 0)), Color(0.35, 0.22, 0.12))
	b.box(Vector3(3.0, 0.1, 1.7), MeshBuilder.xf(Vector3(0, 1.05, 0)), Color(0.18, 0.5, 0.3))
	b.box(Vector3(0.9, 0.5, 0.06), MeshBuilder.xf(Vector3(-0.6, 1.4, -0.1), Vector3(-12, 0, 0)), Color(0.15, 0.15, 0.2))
	b.box(Vector3(0.8, 0.4, 0.04), MeshBuilder.xf(Vector3(-0.6, 1.4, -0.14), Vector3(-12, 0, 0)), MeshBuilder.glow(Color(0.4, 1.0, 0.6), 0.8))
	for i in 4:
		b.cylinder(0.22, 0.22, 0.08 + i * 0.001, 8, MeshBuilder.xf(Vector3(0.7, 1.14 + i * 0.09, 0.1)), Color(1.0, 0.8, 0.25))
	var h1 := Node3D.new()
	h1.position = p1
	add_child(h1)
	Mats.mesh_instance(b.build(), Mats.world_material(), h1)
	h1.add_child(PropsFactory.static_body(Vector3(3.0, 1.2, 1.7), Vector3(0, 0.6, 0)))
	_label("EL DESPACHO", p1 + Vector3(1.5, 3.4, 0), 60, ZONE_COLORS["meta"].lightened(0.3), 0.012)
	_label("Mejoras permanentes", p1 + Vector3(1.5, 2.75, 0), 38, Color(0.85, 1.0, 0.9), 0.0105)
	_station("meta", p1 + Vector3(-2.4, 0, 0), "El Despacho: mejoras permanentes", "DESPACHO", 3.0, "MEJORAS", 2.8, ZONE_COLORS["meta"].lightened(0.3)).ind_scale = 0.62
	# Archivo (estadísticas)
	var p2 := Vector3(14.5, 0, 9.5)
	_zone_disc(p2, 3.8, ZONE_COLORS["stats"])
	var b2 := MeshBuilder.new()
	b2.box(Vector3(0.4, 2.6, 3.4), MeshBuilder.xf(Vector3(0, 1.3, 0)), Color(0.28, 0.3, 0.4))
	b2.box(Vector3(0.45, 2.2, 3.0), MeshBuilder.xf(Vector3(-0.04, 1.3, 0)), MeshBuilder.glow(Color(0.35, 0.5, 1.0), 0.45))
	for i in 5:
		b2.box(Vector3(0.1, 0.12, 2.4 - i * 0.3), MeshBuilder.xf(Vector3(-0.3, 2.1 - i * 0.35, 0.3 - i * 0.1)), Color(1, 1, 1))
	var h2 := Node3D.new()
	h2.position = p2
	add_child(h2)
	Mats.mesh_instance(b2.build(), Mats.world_material(), h2)
	h2.add_child(PropsFactory.static_body(Vector3(0.6, 2.6, 3.4), Vector3(0, 1.3, 0)))
	_label("ARCHIVO DE CASOS", p2 + Vector3(-1.0, 4.0, 0), 56, ZONE_COLORS["stats"].lightened(0.3), 0.012)
	_label("Estadísticas y récords", p2 + Vector3(-1.0, 3.35, 0), 38, Color(0.85, 0.9, 1.0), 0.0105)
	_station("stats", p2 + Vector3(-2.4, 0, 0), "Archivo de Casos: estadísticas", "ARCHIVO", 3.0, "ESTADÍSTICAS", 3.0, ZONE_COLORS["stats"].lightened(0.3)).ind_scale = 0.62


# ------------------------------------------------------------------ práctica (sur)
func _build_practice() -> void:
	var c := Vector3(0, 0, 16.0)
	_zone_disc(c, 7.0, ZONE_COLORS["practice"])
	_label("ZONA DE PRÁCTICA", c + Vector3(0, 6.2, 3.5), 70, ZONE_COLORS["practice"].lightened(0.3), 0.0135)
	_label("Prueba tu equipo: los muñecos no hacen daño", c + Vector3(0, 5.4, 3.5), 36, Color(1.0, 0.95, 0.85), 0.0105)
	for sx in [-4.5, 0.0, 4.5]:
		var d := PracticeDummy.new()
		d.position = c + Vector3(sx, 0, 1.2 if sx == 0.0 else 0.0)
		add_child(d)
		dummies.append(d)


# ------------------------------------------------------------------ actualización
## Refresca todo lo que cambia con las elecciones del jugador (equipo, dificultad, partida guardada).
func refresh() -> void:
	var lo: Dictionary = LoadoutDB.equipped()
	for slot in LoadoutDB.SLOTS:
		var id := String(lo[slot])
		var p: Dictionary = _pedestals[slot]
		(p["name"] as Label3D).text = String(LoadoutDB.item(id)["name"])
		if String(p["item"]) != id:
			p["item"] = id
			var model: Node3D = p["model"]
			for ch in model.get_children():
				ch.queue_free()
			Mats.mesh_instance(_item_mesh(id), Mats.world_material(), model)
	var did := LoadoutDB.selected_difficulty()
	var dd: Dictionary = LoadoutDB.diff(did)
	_diff_sign.text = String(dd["name"]).to_upper()
	_diff_sign.modulate = dd["color"]
	_diff_sub.text = "Dificultad: %s" % dd["name"]
	_diff_sub.modulate = dd["color"].lightened(0.3)
	var disc_mat := _diff_disc.material_override as StandardMaterial3D
	if disc_mat != null:
		var dc: Color = dd["color"]
		disc_mat.albedo_color = Color(dc.r, dc.g, dc.b, 0.42)
	var has_run := SaveSystem.has_valid_run()
	var cont: Interactable = stations["continue"]
	cont.enabled = has_run
	cont.ind_active = has_run
	if has_run:
		var r: Dictionary = SaveSystem.get_run()
		_cont_label.modulate = ZONE_COLORS["portal_cont"]
		_cont_sub.text = "Arena %d · %s · %s" % [int(r["arena_index"]) + 1, String(LoadoutDB.diff(String(r["difficulty"]))["name"]), UIKit.fmt_time(float(r["run_time"]))]
		_cont_sub.modulate = Color(0.9, 0.95, 0.8)
		(_portal_cont["light"] as OmniLight3D).light_energy = 1.4
		(_portal_cont["swirl"] as MeshInstance3D).visible = true
		(_portal_cont["swirl2"] as MeshInstance3D).visible = true
	else:
		_cont_label.modulate = Color(0.5, 0.5, 0.55)
		_cont_sub.text = "Sin partida guardada"
		_cont_sub.modulate = Color(0.6, 0.6, 0.65)
		(_portal_cont["light"] as OmniLight3D).light_energy = 0.15
		(_portal_cont["swirl"] as MeshInstance3D).visible = false
		(_portal_cont["swirl2"] as MeshInstance3D).visible = false


func _process(delta: float) -> void:
	_t += delta
	for slot in _pedestals.keys():
		var m: Node3D = _pedestals[slot]["model"]
		m.rotation.y += delta * 1.2
		m.position.y = 2.15 + sin(_t * 2.0 + float(LoadoutDB.SLOTS.find(slot))) * 0.1
	if not _portal_cont.is_empty() and SaveSystem.has_valid_run():
		(_portal_cont["swirl"] as MeshInstance3D).rotation.z += delta * 1.6
		(_portal_cont["swirl2"] as MeshInstance3D).rotation.z -= delta * 2.4


# ------------------------------------------------------------------ modelos 3D de los objetos
func _x(pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE) -> Transform3D:
	return MeshBuilder.xf(pos, rot, scl)


func _item_mesh(id: String) -> ArrayMesh:
	var b := MeshBuilder.new()
	var it: Dictionary = LoadoutDB.item(id)
	var col: Color = it["color"]
	var gold := Color(1.0, 0.8, 0.25)
	match id:
		"case":
			b.box(Vector3(0.9, 0.62, 0.28), _x(), Color(0.55, 0.3, 0.12))
			b.box(Vector3(0.38, 0.12, 0.18), _x(Vector3(0, 0.37, 0)), Color(0.4, 0.22, 0.08))
			b.box(Vector3(0.12, 0.12, 0.3), _x(Vector3(0, 0.0, 0)), MeshBuilder.glow(gold, 0.8))
		"gavel":
			b.cylinder(0.2, 0.2, 0.7, 8, _x(Vector3(0, 0.35, 0), Vector3(0, 0, 90)), Color(0.55, 0.33, 0.15))
			b.cylinder(0.075, 0.075, 0.9, 6, _x(Vector3(0, -0.2, 0), Vector3(0, 0, 0)), Color(0.4, 0.24, 0.1))
			b.cylinder(0.22, 0.22, 0.08, 8, _x(Vector3(-0.38, 0.35, 0), Vector3(0, 0, 90)), gold)
			b.cylinder(0.22, 0.22, 0.08, 8, _x(Vector3(0.38, 0.35, 0), Vector3(0, 0, 90)), gold)
		"quill":
			b.cylinder(0.02, 0.07, 1.1, 5, _x(Vector3(0, 0, 0), Vector3(0, 0, 18)), Color(0.95, 0.95, 1.0))
			b.frustum(Vector2(0.28, 0.04), Vector2(0.02, 0.02), 0.7, _x(Vector3(0.15, 0.2, 0), Vector3(0, 0, 18)), col)
			b.cylinder(0.0, 0.05, 0.2, 5, _x(Vector3(-0.2, -0.58, 0), Vector3(0, 0, 18)), Color(0.15, 0.15, 0.2))
		"docs_burst":
			for i in 4:
				b.box(Vector3(0.6, 0.02, 0.8), _x(Vector3(0, -0.2 + i * 0.1, 0), Vector3(0, i * 14.0 - 20.0, 0)), Color(0.96, 0.95, 0.9) if i % 2 == 0 else Color(0.85, 0.85, 0.8))
			b.box(Vector3(0.4, 0.03, 0.05), _x(Vector3(0, 0.22, 0.1), Vector3(0, 10, 0)), Color(0.4, 0.4, 0.5))
		"seal_master":
			b.cylinder(0.5, 0.5, 0.08, 14, _x(Vector3(0, -0.1, 0)), col)
			b.cylinder(0.32, 0.32, 0.12, 14, _x(Vector3(0, -0.04, 0)), MeshBuilder.glow(col, 0.8))
			b.cylinder(0.1, 0.12, 0.35, 8, _x(Vector3(0, 0.2, 0)), Color(0.45, 0.28, 0.14))
			b.sphere(0.14, 6, 4, _x(Vector3(0, 0.42, 0)), gold)
		"objection_iron":
			b.frustum(Vector2(0.9, 0.2), Vector2(0.9, 0.2), 0.12, _x(Vector3(0, 0.25, 0), Vector3(90, 0, 0)), col)
			b.frustum(Vector2(0.75, 0.15), Vector2(0.15, 0.1), 0.6, _x(Vector3(0, -0.4, 0), Vector3(0, 0, 0)), col.darkened(0.15))
			b.box(Vector3(0.14, 0.7, 0.14), _x(Vector3(0, 0.0, -0.06)), Color(0.9, 0.95, 1.0))
		"brawler":
			b.sphere(0.34, 7, 5, _x(), Color(0.95, 0.72, 0.58))
			for i in 4:
				b.sphere(0.12, 5, 4, _x(Vector3(-0.21 + i * 0.14, 0.2, -0.22)), Color(0.9, 0.66, 0.52))
			b.box(Vector3(0.5, 0.2, 0.5), _x(Vector3(0, -0.34, 0)), col)
		"dancer":
			b.box(Vector3(0.38, 0.22, 0.9), _x(Vector3(0, -0.2, 0)), col)
			b.wedge(Vector3(0.38, 0.4, 0.4), _x(Vector3(0, 0.0, 0.25)), col.darkened(0.25))
			b.box(Vector3(0.42, 0.06, 0.95), _x(Vector3(0, -0.34, 0)), Color(0.1, 0.1, 0.12))
			b.cylinder(0.04, 0.04, 0.8, 4, _x(Vector3(0.0, 0.25, 0.1), Vector3(0, 0, 90)), MeshBuilder.glow(Color(0.7, 1.0, 0.85), 0.9))
		"precise":
			for r in 3:
				b.cylinder(0.55 - r * 0.17, 0.55 - r * 0.17, 0.06 + r * 0.01, 14, _x(Vector3(0, 0, 0), Vector3(90, 0, 0)), col if r % 2 == 0 else Color(1, 1, 1))
			b.box(Vector3(0.05, 0.05, 1.0), _x(Vector3(0.1, 0.1, 0.1), Vector3(-10, 25, 0)), gold)
		"toga":
			b.frustum(Vector2(0.9, 0.55), Vector2(0.45, 0.35), 0.9, _x(Vector3(0, -0.45, 0)), col)
			b.box(Vector3(0.2, 0.9, 0.04), _x(Vector3(0, -0.02, -0.24)), Color(0.95, 0.95, 0.92))
			b.sphere(0.14, 6, 4, _x(Vector3(0, 0.55, 0)), Color(0.96, 0.75, 0.6))
			b.box(Vector3(0.5, 0.05, 0.5), _x(Vector3(0, 0.72, 0)), Color(0.1, 0.1, 0.14))
		"tie":
			b.box(Vector3(0.22, 0.2, 0.1), _x(Vector3(0, 0.45, 0)), col.darkened(0.15))
			b.frustum(Vector2(0.2, 0.08), Vector2(0.4, 0.08), 0.9, _x(Vector3(0, -0.5, 0)), col)
			b.box(Vector3(0.4, 0.04, 0.09), _x(Vector3(0, -0.1, 0.0)), gold)
			b.sphere(0.12, 5, 4, _x(Vector3(0.0, 0.7, 0.0)), Color(0.35, 0.8, 0.4))
		"watch":
			b.cylinder(0.42, 0.42, 0.12, 14, _x(Vector3(0, 0, 0), Vector3(90, 0, 0)), gold)
			b.cylinder(0.34, 0.34, 0.14, 14, _x(Vector3(0, 0, 0), Vector3(90, 0, 0)), Color(0.96, 0.95, 0.88))
			b.box(Vector3(0.04, 0.26, 0.04), _x(Vector3(0, 0.1, -0.08)), Color(0.1, 0.1, 0.15))
			b.box(Vector3(0.2, 0.04, 0.04), _x(Vector3(0.08, 0.0, -0.08)), Color(0.1, 0.1, 0.15))
			b.cylinder(0.05, 0.05, 0.12, 6, _x(Vector3(0, 0.5, 0)), gold)
		_:
			b.sphere(0.4, 8, 6, _x(), col)
	return b.build()
