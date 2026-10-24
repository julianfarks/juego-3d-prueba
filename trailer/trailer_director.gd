extends Node3D
## DIRECTOR DEL TRÁILER de LAWYER MAYHEM 3D.
## Se activa con:  godot --path . --write-movie OUT.avi --fixed-fps 30 --resolution 1920x1080 -- --trailer [--vertical]
## Rueda la historia en decorados propios (despacho, tribunal) con los modelos reales del juego y la acción con el
## juego real (arenas, enemigos, maletín, documentos, cofre, cartas, jefe). Cada plano se prepara fuera de cámara y
## luego se "rueda": el director anota en la consola qué fotogramas se conservan (KEEP) para que el montaje
## (tools/assemble.py) recorte los tiempos de preparación. La música (canción original del juego) se añade en el
## montaje, sincronizada con la línea de tiempo global G (G=0 ↔ segundo 90.65 de music_main.mp3).

const FPS := 30.0
const OFFICE_POS := Vector3(0, 0, 400)
const COURT_POS := Vector3(60, 0, 400)
const LOGO_POS := Vector3(140, 0, 400)

var main: Node
var vertical := false
var only := ""
var G0 := 0.0                       # tiempo global al empezar el plano actual
var G := 0.0                        # tiempo global del fotograma actual
var cam: Camera3D
var arena: Arena
var player: Player
var _keep: Array = []
var _snd_cache := {}
var _releases: Array = []

# --- capa 2D ---
var _ov: Control
var _bar_t: ColorRect
var _bar_b: ColorRect
var _caption: Label
var _big: Label
var _stamp_box: PanelContainer
var _stamp: Label
var _flash: ColorRect
var _fade: ColorRect
var _logo_box: Control
var _logo_icon: TextureRect
var _logo_title: Label
var _logo_tag: Label
var bars := 0.0
var flash := 0.0
var fade := 0.0
var logo_a := 0.0
var tag_a := 0.0
var logo_pop := 0.0

# textos programados en tiempo global
const CAPTIONS := [
	["EXPEDIENTE 001 · EL CASO DEL SIGLO", 0.3, 3.4],
	["TRIBUNAL SUPERIOR · EL ABOGADO contra LOS LADRONES", 3.62, 5.45],
]
const BIGS := [
	["UN CASO PERDIDO.", 10.62, 12.0, "low"],
	["UNA JUSTICIA\nMUY PERSONAL.", 13.62, 15.38, "center"],
	["CONSTRUYE UNA\nBUILD IMPARABLE.", 24.15, 26.95, "top"],
	["NINGÚN LADRÓN\nESTÁ A SALVO.", 34.0, 36.42, "low"],
]
const STAMPS := [
	["¡NO CULPABLES!", 7.52, 8.5],
	["¡CULPABLE!", 41.0, 42.0],
]

# decorados y actores de la historia
var office: Dictionary
var court: Dictionary
var lawyer: Rig
var expr: Dictionary
var judge: Rig
var thieves: Array = []
var halos: Array = []
var hero: Dictionary
var flying_case: Node3D


func _process(_d: float) -> void:
	## avisos del juego ("Partida guardada", rótulos de región) fuera de plano
	if main == null:
		return
	if main.get("banner_panel") != null:
		main.banner_panel.visible = false
	var rb = main.get("_region_banner")
	if rb != null and is_instance_valid(rb):
		rb.visible = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a == "--vertical":
			vertical = true
		elif a.begins_with("--only="):
			only = a.substr(7)
		elif a == "--lang=en":
			TrailerSets.lang_en = true
	call_deferred("_run")


func _want(name: String) -> bool:
	return only == "" or only.split(",").has(name)


# ============================================================================ utilidades de rodaje
func _f(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _secs(t: float) -> void:
	await _f(int(ceil(t * FPS)))


## Rueda un plano de 'dur' segundos: cada fotograma llama a fn(t_local) y actualiza la capa 2D con el tiempo global.
func _roll(name: String, dur: float, fn: Callable) -> void:
	# fotogramas exactos sobre la rejilla global (sin deriva acumulada de redondeo)
	var n := int(round((G0 + dur) * FPS)) - int(round(G0 * FPS))
	var first := -1
	for i in n:
		await get_tree().process_frame
		for a in _releases:
			Input.action_release(a)
		_releases.clear()
		if first < 0:
			first = Engine.get_frames_drawn()
		var lt := float(i) / FPS
		G = G0 + lt
		fn.call(lt)
		_update_overlay()
	_keep.append([first, first + n, G0, name])
	print("KEEP %d %d %.3f %s" % [first, first + n, G0, name])
	G0 += float(n) / FPS


func _once(store: Dictionary, key: String, t: float, at: float) -> bool:
	if t >= at and not store.has(key):
		store[key] = true
		return true
	return false


func _snd(name: String, db := 0.0, pitch := 1.0) -> void:
	var path := "res://trailer/audio/%s.wav" % name
	var st: AudioStream = null
	if _snd_cache.has(path):
		st = _snd_cache[path]
	elif ResourceLoader.exists(path):
		st = load(path)
		_snd_cache[path] = st
	if st == null:
		AudioManager.sfx(name, db, 0.0)
		return
	var p := AudioStreamPlayer.new()
	p.stream = st
	p.volume_db = db
	p.pitch_scale = pitch
	p.bus = "SFX"
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


func _fov(v: float) -> void:
	## Vertical (9:16): misma cobertura útil que en horizontal pero algo más cerrada a los lados.
	if not vertical:
		cam.keep_aspect = Camera3D.KEEP_HEIGHT
		cam.fov = v
	else:
		cam.keep_aspect = Camera3D.KEEP_WIDTH
		var half_h := tan(deg_to_rad(v) * 0.5) * (16.0 / 9.0) * 0.62
		cam.fov = rad_to_deg(atan(half_h) * 2.0)


func _place_cam(pos: Vector3, look: Vector3, fov := 50.0) -> void:
	cam.current = true
	cam.global_position = pos
	if pos.distance_to(look) > 0.01:
		cam.look_at(look, Vector3.UP)
	_fov(fov)


func _lerp_cam(a: Vector3, b: Vector3, la: Vector3, lb: Vector3, k: float, fov := 50.0) -> void:
	var e := k * k * (3.0 - 2.0 * k)
	_place_cam(a.lerp(b, e), la.lerp(lb, e), fov)


func _face(n: Node3D, dir: Vector3) -> void:
	## los modelos miran hacia -Z
	n.rotation.y = atan2(-dir.x, -dir.z)


func _ease(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


# ============================================================================ capa 2D
func _font(file: String) -> Font:
	var f = load("res://trailer/fonts/" + file)
	return f if f != null else ThemeDB.fallback_font


func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 90
	add_child(layer)
	_ov = Control.new()
	_ov.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_ov)
	var black := _font("InterDisplay-Black.otf")
	_bar_t = ColorRect.new()
	_bar_t.color = Color.BLACK
	_ov.add_child(_bar_t)
	_bar_b = ColorRect.new()
	_bar_b.color = Color.BLACK
	_ov.add_child(_bar_b)
	_caption = Label.new()
	_caption.add_theme_font_override("font", _font("Inter-SemiBold.otf"))
	_caption.add_theme_font_size_override("font_size", 28 if not vertical else 34)
	_caption.add_theme_color_override("font_color", Color(1.0, 0.92, 0.75))
	_caption.add_theme_constant_override("outline_size", 8)
	_caption.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ov.add_child(_caption)
	_big = Label.new()
	_big.add_theme_font_override("font", black)
	_big.add_theme_font_size_override("font_size", 92 if not vertical else 96)
	_big.add_theme_color_override("font_color", Color(1, 1, 1))
	_big.add_theme_constant_override("outline_size", 22)
	_big.add_theme_color_override("font_outline_color", Color(0.04, 0.03, 0.08))
	_big.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_big.add_theme_constant_override("shadow_offset_x", 6)
	_big.add_theme_constant_override("shadow_offset_y", 8)
	_big.add_theme_constant_override("line_spacing", -12)
	_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_big.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ov.add_child(_big)
	_stamp_box = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.0)
	sb.border_color = Color(0.86, 0.1, 0.12)
	sb.set_border_width_all(12)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 34
	sb.content_margin_right = 34
	sb.content_margin_top = 6
	sb.content_margin_bottom = 10
	_stamp_box.add_theme_stylebox_override("panel", sb)
	_ov.add_child(_stamp_box)
	_stamp = Label.new()
	_stamp.add_theme_font_override("font", black)
	_stamp.add_theme_font_size_override("font_size", 80 if not vertical else 72)
	_stamp.add_theme_color_override("font_color", Color(0.86, 0.1, 0.12))
	_stamp.add_theme_constant_override("outline_size", 6)
	_stamp.add_theme_color_override("font_outline_color", Color(1, 0.95, 0.9, 0.9))
	_stamp_box.add_child(_stamp)
	# logo final
	_logo_box = Control.new()
	_logo_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_logo_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ov.add_child(_logo_box)
	_logo_icon = TextureRect.new()
	_logo_icon.texture = load("res://assets/icon/icon.png")
	_logo_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_logo_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_logo_box.add_child(_logo_icon)
	_logo_title = Label.new()
	_logo_title.text = "LAWYER MAYHEM 3D" if not vertical else "LAWYER\nMAYHEM 3D"
	_logo_title.add_theme_font_override("font", black)
	_logo_title.add_theme_font_size_override("font_size", 118 if not vertical else 120)
	_logo_title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.25))
	_logo_title.add_theme_constant_override("outline_size", 28)
	_logo_title.add_theme_color_override("font_outline_color", Color(0.12, 0.05, 0.12))
	_logo_title.add_theme_color_override("font_shadow_color", Color(0.9, 0.15, 0.15, 0.9))
	_logo_title.add_theme_constant_override("shadow_offset_x", 0)
	_logo_title.add_theme_constant_override("shadow_offset_y", 10)
	_logo_title.add_theme_constant_override("line_spacing", -18)
	_logo_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_logo_box.add_child(_logo_title)
	_logo_tag = Label.new()
	_logo_tag.text = TrailerSets.tr_("«OBJECIÓN… ¡Y A REPARTIR SENTENCIAS!»")
	_logo_tag.add_theme_font_override("font", _font("InterDisplay-BlackItalic.otf"))
	_logo_tag.add_theme_font_size_override("font_size", 42 if not vertical else 44)
	_logo_tag.add_theme_color_override("font_color", Color(1, 1, 1))
	_logo_tag.add_theme_constant_override("outline_size", 14)
	_logo_tag.add_theme_color_override("font_outline_color", Color(0.05, 0.03, 0.1))
	_logo_tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_logo_tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_logo_box.add_child(_logo_tag)
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ov.add_child(_flash)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ov.add_child(_fade)
	# el logo va por encima del fundido para poder mostrarse sobre negro
	_ov.move_child(_logo_box, _ov.get_child_count() - 1)


func _update_overlay() -> void:
	var vs := get_viewport().get_visible_rect().size
	# franjas de cine (solo horizontal)
	var bh := vs.y * 0.11 * (bars if not vertical else 0.0)
	_bar_t.position = Vector2(0, 0)
	_bar_t.size = Vector2(vs.x, bh)
	_bar_b.position = Vector2(0, vs.y - bh)
	_bar_b.size = Vector2(vs.x, bh)
	# leyenda tipo expediente
	_caption.visible = false
	for c in CAPTIONS:
		if G >= c[1] and G < c[2]:
			_caption.visible = true
			_caption.text = TrailerSets.tr_(c[0])
			_caption.visible_ratio = clampf((G - c[1]) / 0.9, 0.0, 1.0)
			_caption.modulate.a = clampf((c[2] - G) / 0.25, 0.0, 1.0)
			var w := vs.x * (0.6 if not vertical else 0.86)
			_caption.size = Vector2(w, 0)
			_caption.position = Vector2(vs.x * 0.05, maxf(bh, 0.0) + vs.y * (0.04 if not vertical else 0.12))
	# textos grandes
	_big.visible = false
	for bt in BIGS:
		if G >= bt[1] and G < bt[2]:
			_big.visible = true
			_big.text = TrailerSets.tr_(bt[0])
			var tin := clampf((G - bt[1]) / 0.16, 0.0, 1.0)
			var tout := clampf((bt[2] - G) / 0.22, 0.0, 1.0)
			_big.modulate.a = minf(tin, tout)
			var s: float = lerpf(1.45, 1.0, _ease(tin)) * (1.0 + (G - float(bt[1])) * 0.025) * lerpf(1.08, 1.0, tout)
			_big.size = Vector2(vs.x * 0.94, vs.y * 0.3)
			_big.pivot_offset = _big.size * 0.5
			_big.scale = Vector2(s, s)
			var y := 0.5
			match bt[3]:
				"top": y = 0.17 if not vertical else 0.2
				"low": y = 0.72 if not vertical else 0.7
			_big.position = Vector2(vs.x * 0.03, vs.y * y - _big.size.y * 0.5)
	# sello rojo
	_stamp_box.visible = false
	for st in STAMPS:
		if G >= st[1] and G < st[2]:
			_stamp_box.visible = true
			_stamp.text = TrailerSets.tr_(st[0])
			var k := clampf((G - st[1]) / 0.1, 0.0, 1.0)
			var s2 := lerpf(3.0, 1.0, k * k)
			_stamp_box.reset_size()
			_stamp_box.pivot_offset = _stamp_box.size * 0.5
			_stamp_box.scale = Vector2(s2, s2)
			_stamp_box.rotation = deg_to_rad(-9.0)
			_stamp_box.modulate.a = minf(k * 2.0, clampf((st[2] - G) / 0.15, 0.0, 1.0))
			_stamp_box.position = Vector2(vs.x * 0.5, vs.y * (0.62 if not vertical else 0.66)) - _stamp_box.size * 0.5
	# destello / fundido
	_flash.color.a = clampf(flash, 0.0, 1.0)
	_fade.color.a = clampf(fade, 0.0, 1.0)
	# logo
	_logo_box.visible = logo_a > 0.001
	if _logo_box.visible:
		var icon_s := (vs.y * 0.36) if not vertical else (vs.x * 0.52)
		var pop := 1.0 + 0.25 * (1.0 - _ease(logo_pop))
		_logo_icon.size = Vector2(icon_s, icon_s)
		_logo_icon.pivot_offset = _logo_icon.size * 0.5
		_logo_icon.scale = Vector2(pop, pop)
		_logo_title.size = Vector2(vs.x, 0)
		_logo_title.reset_size()
		_logo_title.size.x = vs.x
		_logo_title.pivot_offset = Vector2(vs.x * 0.5, _logo_title.size.y * 0.5)
		_logo_title.scale = Vector2(pop, pop)
		_logo_tag.size = Vector2(vs.x * 0.9, 0)
		var top := vs.y * (0.1 if not vertical else 0.17)
		_logo_icon.position = Vector2(vs.x * 0.5 - icon_s * 0.5, top)
		_logo_title.position = Vector2(0, top + icon_s + vs.y * 0.01)
		_logo_tag.position = Vector2(vs.x * 0.05, _logo_title.position.y + _logo_title.size.y + vs.y * 0.015)
		_logo_icon.modulate.a = logo_a
		_logo_title.modulate.a = logo_a
		_logo_tag.modulate.a = tag_a


# ============================================================================ PREPARACIÓN
func _run() -> void:
	await _f(6)
	var t := 0.0
	while main.state != main.St.LOBBY and t < 15.0:
		await _f(3)
		t += 0.1
	# ajustes de rodaje: calidad alta, sin HUD, sin música del juego (la canción se mezcla en el montaje)
	SaveSystem.set_setting("quality", 2)
	Config.apply_preset(2)
	Config.apply_graphics()
	main.hud_layer.visible = false
	main.touch.visible = false
	for bus in ["Music", "Ambient"]:
		var bi := AudioServer.get_bus_index(bus)
		if bi >= 0:
			AudioServer.set_bus_volume_db(bi, -80.0)
	cam = Camera3D.new()
	cam.near = 0.05
	cam.far = 400.0
	add_child(cam)
	_build_overlay()
	fade = 1.0
	_update_overlay()
	_build_story_sets()
	await _f(8)
	print("TRAILER_BEGIN vertical=%s" % str(vertical))
	if _want("story"):
		await _story()
	else:
		G0 = 15.5
	if _want("action"):
		await _action()
	else:
		G0 = 47.8
	if _want("logo"):
		await _logo()
	print("TRAILER_END total=%.3f" % G0)
	var f := FileAccess.open("user://trailer_keep%s.json" % ("_v" if vertical else ""), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_keep))
		f.close()
	await _f(4)
	get_tree().quit(0)


func _build_story_sets() -> void:
	office = TrailerSets.office()
	office["root"].position = OFFICE_POS
	add_child(office["root"])
	court = TrailerSets.court()
	court["root"].position = COURT_POS
	add_child(court["root"])
	lawyer = ModelFactory.build_lawyer()
	add_child(lawyer)
	expr = TrailerSets.add_expressions(lawyer)
	judge = TrailerSets.judge()
	add_child(judge)
	for i in 3:
		var th := ModelFactory.build_enemy("thief", i)
		add_child(th)
		thieves.append(th)
		var hb := MeshBuilder.new()
		hb.cylinder(0.24, 0.24, 0.035, 14, MeshBuilder.xf(), MeshBuilder.glow(Color(1.0, 0.9, 0.35), 1.0))
		hb.cylinder(0.16, 0.16, 0.04, 14, MeshBuilder.xf(), Color(0.95, 0.8, 0.3))
		var halo := Mats.mesh_instance(hb.build(), Mats.world_material(), th)
		halo.position = Vector3(0, 2.0, 0)
		halos.append(halo)
	hero = TrailerSets.hero_case()
	add_child(hero["root"])
	hero["root"].visible = false
	flying_case = Node3D.new()
	add_child(flying_case)
	Mats.mesh_instance(ModelFactory.briefcase_mesh(), Mats.char_material(), flying_case)
	flying_case.visible = false


# ============================================================================ HISTORIA
func _o(p: Vector3) -> Vector3:
	return OFFICE_POS + p


func _c(p: Vector3) -> Vector3:
	return COURT_POS + p


func _story() -> void:
	bars = 1.0
	# ---------- 1. despacho ----------
	lawyer.position = _o(Vector3(-0.9, 0, -0.55))
	lawyer.rotation.y = PI
	lawyer.speed_norm = 0.0
	(office["seal"] as Label3D).visible = false
	for th in thieves:
		th.visible = false
	judge.visible = false
	await _f(4)
	var s1 := {}
	await _roll("despacho", 3.5, func(t: float):
		fade = clampf(1.0 - t / 0.5, 0.0, 1.0)
		_lerp_cam(_o(Vector3(1.2, 1.9, 4.6)), _o(Vector3(0.2, 1.55, 2.4)), _o(Vector3(-0.6, 1.3, -1.6)), _o(Vector3(-0.85, 1.45, -1.3)), t / 3.5, 46.0)
		if _once(s1, "paper", t, 0.25):
			_snd("paper", -6.0)
		if _once(s1, "turn", t, 1.0):
			pass
		if t >= 1.0 and t < 1.35:
			lawyer.rotation.y = lerp_angle(PI, 0.0, (t - 1.0) / 0.35)
		if _once(s1, "stamp", t, 1.45):
			lawyer.play("seal", 0.55)
		if _once(s1, "stampsnd", t, 1.75):
			(office["seal"] as Label3D).visible = true
			AudioManager.sfx("seal", 0.0, 0.0)
			_snd("stapler", -8.0)
		if t >= 2.3 and t < 2.65:
			lawyer.rotation.y = lerp_angle(0.0, PI, (t - 2.3) / 0.35)
		var gl: Node3D = expr["glint"]
		var gk := clampf(1.0 - absf(t - 3.0) / 0.22, 0.0, 1.0)
		gl.scale = Vector3.ONE * gk * 1.4
		gl.rotation.z = t * 3.0
		if _once(s1, "ding", t, 2.95):
			AudioManager.sfx("shard", -8.0, 0.0))
	# ---------- 2. tribunal: plano general ----------
	_setup_court()
	await _f(3)
	await _roll("tribunal", 2.0, func(t: float):
		_lerp_cam(_c(Vector3(0.0, 3.4, 9.0)), _c(Vector3(0.4, 3.0, 7.6)), _c(Vector3(0, 1.6, -1.8)), _c(Vector3(0.3, 1.5, -1.6)), t / 2.0, 50.0)
		for i in 3:
			halos[i].position.y = 2.0 + sin(t * 3.0 + i) * 0.03
			thieves[i].position.y = 0.0
		)
	# ---------- 3. la coartada ----------
	var sign := TrailerSets.alibi_sign()
	thieves[1].add_child(sign)
	sign.position = Vector3(0.0, 0.6, -0.5)
	var s3 := {}
	await _roll("coartada", 1.5, func(t: float):
		var th: Node3D = thieves[1]
		var k := _ease(clampf((t - 0.15) / 0.3, 0.0, 1.0))
		sign.position = Vector3(0.0, lerpf(0.6, 1.62, k), -0.5)
		if _once(s3, "flip", t, 0.15):
			AudioManager.sfx("card_flip", -2.0, 0.0)
		thieves[0].position.y = absf(sin(t * 9.0)) * 0.05 * float(t > 0.6)
		thieves[2].position.y = absf(sin(t * 9.0 + 1.0)) * 0.05 * float(t > 0.6)
		var focus: Vector3 = th.global_position + Vector3(0, 1.55, 0)
		_lerp_cam(_c(Vector3(2.35, 1.6, -1.6)), _c(Vector3(2.45, 1.62, -1.25)), focus, focus, t / 1.5, 42.0)
		)
	# ---------- 4. el martillo del juez ----------
	var s4 := {}
	await _roll("martillo", 1.5, func(t: float):
		var jp := judge.global_position + Vector3(0, 1.6, 0)
		var shake := Vector3.ZERO
		if t > 0.5 and t < 0.8:
			shake = Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * 0.06 * (0.8 - t) / 0.3
		_lerp_cam(_c(Vector3(1.2, 2.2, -0.6)), _c(Vector3(1.0, 2.25, -1.1)), jp + Vector3(0, 0.2, 0), jp + Vector3(0, 0.05, 0), t / 1.5, 42.0)
		cam.global_position += shake
		if _once(s4, "raise", t, 0.05):
			judge.play("seal", 0.55)
		if _once(s4, "hit", t, 0.5):
			_snd("gavel_big", 0.0)
			AudioManager.sfx("seal", -2.0, 0.0)
		)
	# ---------- 5. celebración y robo de la prueba ----------
	sign.visible = false
	var ball := MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = 0.11
	bm.height = 0.22
	ball.mesh = bm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.97, 0.96, 0.9)
	ball.material_override = bmat
	add_child(ball)
	ball.visible = false
	var evid: Node3D = court["evidence"]
	var ev_home := evid.global_transform
	var s5 := {}
	await _roll("celebracion", 2.0, func(t: float):
		_lerp_cam(_c(Vector3(-0.5, 2.3, 6.4)), _c(Vector3(-0.2, 2.2, 5.9)), _c(Vector3(1.2, 1.2, 0.2)), _c(Vector3(1.0, 1.2, 0.0)), t / 2.0, 52.0)
		# 0 y 2 saltan y se burlan
		for i in [0, 2]:
			var th: Node3D = thieves[i]
			th.position.y = absf(sin(t * 8.5 + i)) * 0.45
			th.rotation.y = PI + sin(t * 5.0 + i) * 0.6
		if _once(s5, "cheer", t, 0.02):
			thieves[0].play("roar", 1.2)
			thieves[2].play("roar", 1.0)
			AudioManager.sfx("fw_pop", -6.0, 0.0)
		if _once(s5, "conf1", t, 0.1):
			if GameState.fx != null:
				GameState.fx.burst(_c(Vector3(2.6, 2.4, 1.2)), Color(1, 1, 0.95), 26, 6.0, 0.13, 1.2)
		if _once(s5, "conf2", t, 0.75):
			AudioManager.sfx("fw_pop", -8.0, 0.0)
			if GameState.fx != null:
				GameState.fx.burst(_c(Vector3(3.2, 2.6, 1.0)), Color(1.0, 0.85, 0.3), 22, 6.0, 0.13, 1.2)
		# 1 corre a por la prueba y huye con ella
		var t1: Node3D = thieves[1]
		if t < 0.55:
			var a := _c(Vector3(2.7, 0, 1.3))
			var b := _c(Vector3(0.45, 0, -0.55))
			t1.global_position = a.lerp(b, t / 0.55)
			_face(t1, b - a)
			t1.speed_norm = 1.0
		elif t < 0.7:
			t1.speed_norm = 0.0
			if _once(s5, "grab", t, 0.55):
				t1.play("swing", 0.25)
				AudioManager.sfx("paper", -2.0, 0.0)
		else:
			var a2 := _c(Vector3(0.45, 0, -0.55))
			var b2 := _c(Vector3(7.5, 0, -0.2))
			var k := (t - 0.7) / 1.0
			t1.global_position = a2.lerp(b2, clampf(k, 0.0, 1.0))
			_face(t1, b2 - a2)
			t1.speed_norm = 1.0
		if t >= 0.55:
			evid.global_position = t1.global_position + Vector3(0, 1.5, 0) + t1.global_transform.basis.z * -0.15
			evid.rotation = Vector3(0, t1.rotation.y + PI, 0.3)
		# bola de papel que le da al abogado en la cabeza
		if t >= 0.9 and t < 1.45:
			ball.visible = true
			var k2 := (t - 0.9) / 0.55
			var from := _c(Vector3(3.3, 1.6, 1.2))
			var to := lawyer.global_position + Vector3(0, 1.95, 0)
			ball.global_position = from.lerp(to, k2) + Vector3(0, sin(k2 * PI) * 1.0, 0)
		elif t >= 1.45:
			if _once(s5, "bonk", t, 1.45):
				_snd("gavel", -10.0, 2.2)
				AudioManager.sfx("bounce", 0.0, 0.0)
				lawyer.play("hit", 0.3)
				lawyer.hit_flash(0.5)
			var k3 := (t - 1.45) / 0.55
			ball.global_position = lawyer.global_position + Vector3(0.6 * k3, 1.95 + sin(k3 * PI) * 0.5 - k3 * 1.6, 0.4 * k3)
		)
	ball.queue_free()
	thieves[1].visible = false
	# ---------- 6. cara de incredulidad ----------
	(expr["mouth_o"] as Node3D).visible = true
	(expr["brows_up"] as Node3D).visible = true
	for i in [0, 2]:
		thieves[i].position.y = 0.0
	await _roll("incredulidad", 1.5, func(t: float):
		var head := lawyer.global_position + Vector3(0, 1.72, 0)
		_lerp_cam(head + Vector3(0.35, 0.05, -1.5), head + Vector3(0.2, 0.02, -1.05), head + Vector3(0, -0.05, 0), head, t / 1.5, 38.0)
		lawyer.rotation.y = 0.0
		)
	# ---------- 7. pausa: solo con su maletín ----------
	(expr["mouth_o"] as Node3D).visible = false
	(expr["brows_up"] as Node3D).visible = false
	for th in thieves:
		th.visible = false
	judge.visible = false
	for l in court["lights"]:
		(l as OmniLight3D).light_energy = 0.45
	var spot := SpotLight3D.new()
	spot.light_color = Color(1.0, 0.85, 0.6)
	spot.light_energy = 6.0
	spot.spot_range = 9.0
	spot.spot_angle = 22.0
	add_child(spot)
	spot.global_position = lawyer.global_position + Vector3(0, 6.0, 0.6)
	spot.look_at(lawyer.global_position, Vector3.FORWARD)
	(lawyer.props["case"] as Node3D).visible = false
	var hr: Node3D = hero["root"]
	hr.visible = true
	hr.global_position = _c(Vector3(-2.6, 0.9, 0.55))
	hr.rotation = Vector3.ZERO
	(hero["lid"] as Node3D).rotation.x = 0.0
	await _roll("soledad", 0.6, func(t: float):
		_lerp_cam(_c(Vector3(-5.5, 3.6, 5.0)), _c(Vector3(-5.2, 3.4, 4.6)), lawyer.global_position + Vector3(0, 1.0, 0), lawyer.global_position + Vector3(0, 1.0, 0), t / 0.6, 44.0)
		)
	var s7 := {}
	await _roll("maletin_abre", 0.75, func(t: float):
		var c := hr.global_position + Vector3(0, 0.25, 0)
		_lerp_cam(c + Vector3(0.0, 0.85, 1.25), c + Vector3(0.0, 0.7, 0.95), c, c, t / 0.75, 40.0)
		var k := _ease(t / 0.75)
		(hero["lid"] as Node3D).rotation.x = -k * 1.25
		(hero["light"] as OmniLight3D).light_energy = k * 3.0
		if _once(s7, "creak", t, 0.02):
			AudioManager.sfx("chest", -6.0, 0.0)
		)
	# ---------- 8. la decisión ----------
	(expr["brows_angry"] as Node3D).visible = true
	var under := OmniLight3D.new()
	under.light_color = Color(1.0, 0.75, 0.35)
	under.light_energy = 2.0
	under.omni_range = 2.5
	add_child(under)
	under.global_position = lawyer.global_position + Vector3(0, 1.1, -0.7)
	var s8 := {}
	await _roll("decision", 0.95, func(t: float):
		var head := lawyer.global_position + Vector3(0, 1.74, 0)
		_lerp_cam(head + Vector3(0.18, 0.04, -1.45), head + Vector3(0.1, 0.02, -1.15), head + Vector3(0, 0.02, 0), head, t / 0.95, 34.0)
		if _once(s8, "gavel", t, 0.03):
			_snd("gavel", 0.0)
		var gl: Node3D = expr["glint"]
		var gk := clampf(1.0 - absf(t - 0.32) / 0.2, 0.0, 1.0)
		gl.scale = Vector3.ONE * gk * 1.8
		gl.rotation.z = t * 4.0
		if _once(s8, "ding", t, 0.25):
			AudioManager.sfx("crit_1", -6.0, 0.0)
		)
	# ---------- 9. lanza el maletín a cámara ----------
	hr.visible = false
	(lawyer.props["case"] as Node3D).visible = true
	under.light_energy = 0.0
	lawyer.rotation.y = 0.0
	var s9 := {}
	var cpos := lawyer.global_position + Vector3(0.6, 1.45, -3.6)
	await _roll("lanzamiento", 1.2, func(t: float):
		_place_cam(cpos, lawyer.global_position + Vector3(0, 1.25, 0), 48.0)
		if _once(s9, "wind", t, 0.15):
			lawyer.play("throw", 0.45)
		if _once(s9, "release", t, 0.38):
			(lawyer.props["case"] as Node3D).visible = false
			flying_case.visible = true
			AudioManager.sfx("throw", 0.0, 0.0)
			_snd("whoosh", -2.0)
		if t >= 0.38:
			var k := clampf((t - 0.38) / 0.8, 0.0, 1.0)
			var from := lawyer.global_position + Vector3(0.35, 1.5, -0.4)
			var to := cpos + (lawyer.global_position + Vector3(0, 1.25, 0) - cpos).normalized() * 0.25
			flying_case.global_position = from.lerp(to, k * k)
			flying_case.rotation = Vector3(t * 9.0, t * 2.0, 0.4)
			flying_case.scale = Vector3.ONE * 1.6
		flash = clampf((t - 1.1) / 0.1, 0.0, 1.0)
		)
	flying_case.visible = false
	spot.queue_free()
	under.queue_free()


func _setup_court() -> void:
	lawyer.global_position = _c(Vector3(-2.6, 0, 1.4))
	lawyer.rotation.y = 0.0
	lawyer.speed_norm = 0.0
	(lawyer.props["case"] as Node3D).visible = true
	judge.visible = true
	judge.global_position = _c(Vector3(0, 1.3, -4.3))
	judge.rotation.y = PI
	for i in 3:
		var th: Rig = thieves[i]
		th.visible = true
		th.global_position = _c(Vector3(2.0 + i * 0.7, 0, 1.3))
		th.rotation.y = 0.0
		th.speed_norm = 0.0


# ============================================================================ ACCIÓN (juego real)
func _start_run() -> void:
	main._on_play()
	var t := 0
	while main.state != main.St.RUN and t < 600:
		await _f(1)
		t += 1
	await _f(20)
	player = GameState.player
	Config.dev_god_mode = true
	SaveSystem.data["settings"]["auto_attack"] = false
	main.hud_layer.visible = false
	main.touch.visible = false


## Entra en una arena real, la deja sin oleadas y sin enemigos (el plano pone los suyos).
func _arena(idx: int) -> void:
	Engine.time_scale = 1.0
	await main._begin_arena(idx, true)
	await _f(12)
	arena = main.arena
	player = GameState.player
	arena.phase = Arena.Phase.IDLE
	arena._queue.clear()
	_clear_enemies()
	await _f(8)
	main.hud_layer.visible = false
	main.cam.yaw = 0.0
	_hide_indicators()


func _clear_enemies() -> void:
	for e in Combat.arena_enemies().duplicate():
		if is_instance_valid(e) and e.alive:
			e.set_physics_process(true)
			e.invuln_t = 0.0
			e.take_damage(e.hp * 50.0 + 50.0, {"src": "boss_death", "silent": true})


func _hide_indicators() -> void:
	for n in get_tree().get_nodes_in_group("interactable"):
		var it := n as Interactable
		if it != null:
			it.ind_active = false
			if it._ind != null:
				it._ind.visible = false


func _spawn(kind: String, pos: Vector3) -> Enemy:
	var e: Enemy = arena._spawn_enemy(kind, pos)
	e.aggro_range = 999.0
	return e


func _freeze(e: Enemy, face_to := Vector3.INF) -> void:
	if not is_instance_valid(e):
		return
	e.set_physics_process(false)
	e.velocity = Vector3.ZERO
	e.rig.scale = Vector3.ONE * e.vscale
	e.rig.speed_norm = 0.0
	if face_to != Vector3.INF:
		var d := face_to - e.global_position
		d.y = 0.0
		if d.length() > 0.01:
			e.rotation.y = atan2(-d.x, -d.z)


func _ground(x: float, z: float) -> Vector3:
	return Vector3(x, Terrain.ground_y(x, z), z)


func _put_player(p: Vector3, face := Vector3(0, 0, -1)) -> void:
	player.teleport_to(_ground(p.x, p.z) + Vector3(0, 0.15, 0))
	player.rotation.y = atan2(-face.x, -face.z)
	player.face_dir(face, 0.5)


func _move(dir: Vector3, strength := 1.0) -> void:
	for a in ["move_left", "move_right", "move_forward", "move_back"]:
		Input.action_release(a)
	if dir.length() < 0.01:
		return
	var d := dir.normalized() * strength
	if d.x > 0.01:
		Input.action_press("move_right", d.x)
	elif d.x < -0.01:
		Input.action_press("move_left", -d.x)
	if d.z > 0.01:
		Input.action_press("move_back", d.z)
	elif d.z < -0.01:
		Input.action_press("move_forward", -d.z)


func _throw(mega := false) -> void:
	var sk = player.skills
	sk.cd[0] = 0.0
	if mega:
		sk.takeover_ready = true
	sk.try_cast(0)


func _docs() -> void:
	var sk = player.skills
	sk.energy = sk.energy_max
	sk.cd[1] = 0.0
	sk.try_cast(1)


## Documentos teledirigidos extra (el mismo proyectil que lanzan «Archivo Vengativo» y «Archivo Automático»).
func _doc_volley(n: int) -> void:
	var pool := Combat.arena_enemies().filter(func(x): return is_instance_valid(x) and x.alive)
	if pool.is_empty():
		return
	var from := player.global_position + Vector3(0, 1.35, 0)
	for i in n:
		var tgt: Node3D = pool[i % pool.size()]
		var d := (tgt.global_position - player.global_position)
		d.y = 0.0
		d = d.normalized().rotated(Vector3.UP, randf_range(-1.2, 1.2))
		player.skills._launch_doc(from, d, 30.0, tgt, 13.0)


func _dodge(dir: Vector3) -> void:
	player._dodge_cd = 0.0
	player._try_dodge(dir.normalized())


func _give(id: String, n: int, rarity := 2) -> void:
	if UpgradeDB.get_def(id).is_empty():
		print("TRAILER: mejora inexistente ", id)
		return
	for k in n:
		GameState.build.add(id, rarity, true)


func _mayhem_build() -> void:
	for pair in [["slam_double", 10], ["slam_missile", 6], ["slam_burn", 5], ["hit_chain", 6], ["crit_nova", 6], ["kill_nova2", 6],
			["dodge_nova", 5], ["dodge_missile", 3], ["t3_chain", 4], ["s_slam", 8], ["slam_radius", 6], ["explosion_pow", 6], ["s_nova", 6]]:
		_give(pair[0], pair[1], 3)
	GameState.build_changed.emit()


func _orbit_cam(center: Vector3, radius: float, height: float, ang: float, look_h := 1.0, fov := 55.0) -> void:
	_place_cam(center + Vector3(sin(ang) * radius, height, cos(ang) * radius), center + Vector3(0, look_h, 0), fov)


func _kill(e: Enemy, dmg_mult := 50.0, knock := Vector3.ZERO) -> void:
	if not is_instance_valid(e) or not e.alive:
		return
	e.set_physics_process(true)
	e.invuln_t = 0.0
	Combat.player_hit(e, e.hp * dmg_mult + 100.0, {"src": "slam", "knock": knock, "proc": false, "flat": true})


func _nearest_obstacle(from: Vector3, min_r := 0.8) -> Vector3:
	var best := Vector3.INF
	var bd := 1e9
	for i in range(1, arena.circles.size()):
		var c: Vector3 = arena.circles[i]
		if c.z < min_r or c.z > 3.5:
			continue
		var d := Vector2(c.x - from.x, c.y - from.z).length()
		if d < bd and absf(c.x) < arena.half - 8 and absf(c.y) < arena.half - 8:
			bd = d
			best = c
	return best


func _action() -> void:
	bars = 1.0
	fade = 0.0
	await _start_run()
	# --- A1: urbano, el maletín bumerán ---
	await _arena(0)
	_give("slam_double", 6, 2)
	_give("hit_chain", 3, 2)
	_give("slam_missile", 3, 2)
	GameState.build_changed.emit()
	var P := _ground(0, 3)
	_put_player(P)
	for i in 6:
		var e := _spawn("thief" if i % 3 != 2 else "runner", P + Vector3(-3.0 + i * 1.2, 0, -9.0 - (i % 2) * 1.5))
	await _secs(1.0)
	var a1 := {}
	await _roll("urbano_maletin", 2.5, func(t: float):
		flash = clampf(1.0 - t / 0.25, 0.0, 1.0)
		bars = clampf(1.0 - t / 0.3, 0.0, 1.0)
		var pp := player.global_position
		_lerp_cam(pp + Vector3(-3.4, 1.0, 3.2), pp + Vector3(-1.6, 1.8, 3.9), pp + Vector3(0.3, 1.3, -4.0), pp + Vector3(0.2, 1.0, -4.0), t / 2.5, 56.0)
		if _once(a1, "t0", t, 0.0):
			_throw()
		if _once(a1, "t1", t, 1.25):
			_throw()
		)
	bars = 0.0
	# --- A2: el ladrón que mira pasar el maletín… y vuelve ---
	_clear_enemies()
	await _f(6)
	var S := _ground(4.0, -3.0)
	_put_player(_ground(-6, 6))
	var victim := _spawn("thief", S)
	await _secs(0.9)
	_freeze(victim, S + Vector3(0, 0, 5))
	var q := TrailerSets.label3d("?", 220, Color(1.0, 0.85, 0.2), 30)
	q.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	q.visible = false
	add_child(q)
	flying_case.scale = Vector3.ONE * 1.3
	var a2 := {}
	await _roll("ladron_bumeran", 2.0, func(t: float):
		var head := S + Vector3(0, 1.45, 0)
		_lerp_cam(S + Vector3(0.75, 1.55, 2.5), S + Vector3(0.55, 1.5, 2.15), head, head, t / 2.0, 44.0)
		if t >= 0.08 and t < 0.6:
			flying_case.visible = true
			var k := (t - 0.08) / 0.52
			flying_case.global_position = (S + Vector3(-4.0, 1.35, 0.75)).lerp(S + Vector3(4.5, 1.4, 0.75), k)
			flying_case.rotation = Vector3(0, t * 22.0, 0.2)
			if _once(a2, "wh", t, 0.1):
				_snd("whoosh", -6.0)
		elif t < 1.25:
			flying_case.visible = false
		if is_instance_valid(victim) and victim.alive:
			var ang := PI
			if t > 0.25:
				ang = PI - minf((t - 0.25) / 0.3, 1.0) * 1.0
			if t > 1.0:
				ang = PI - 1.0 + minf((t - 1.0) / 0.2, 1.0) * 1.0
			victim.rotation.y = ang
		q.visible = t > 0.7 and t < 1.45
		q.global_position = S + Vector3(0, 2.35 + sin(t * 10.0) * 0.04, 0)
		if t >= 1.25 and t < 1.5:
			flying_case.visible = true
			var k2 := (t - 1.25) / 0.25
			flying_case.global_position = (S + Vector3(3.5, 1.7, -2.5)).lerp(S + Vector3(0.0, 1.7, -0.25), k2)
			flying_case.rotation = Vector3(0, t * 22.0, 0.2)
		if _once(a2, "bonk", t, 1.5):
			_snd("gavel", -2.0, 1.6)
			AudioManager.sfx("bounce", -2.0, 0.0)
			_kill(victim, 50.0, Vector3(0, 2.0, 7.0))
			if GameState.fx != null:
				GameState.fx.burst(S + Vector3(0, 1.7, 0), Color(1, 1, 0.7), 14, 6.0, 0.14, 0.5)
		if t >= 1.5:
			var k3 := (t - 1.5) / 0.5
			flying_case.global_position = (S + Vector3(0.0, 1.7, -0.25)).lerp(S + Vector3(-3.0, 2.5, -2.0), k3)
		)
	flying_case.visible = false
	q.queue_free()
	# --- A3: bosque, lluvia de documentos sobre ladrones que huyen ---
	await _arena(5)
	P = _ground(0, 5)
	_put_player(P)
	var fleeing: Array = []
	for i in 7:
		fleeing.append(_spawn("thief", P + Vector3(-3.0 + i, 0, -4.5 - (i % 3) * 1.4)))
	await _secs(0.9)
	for e in fleeing:
		_freeze(e, Vector3(e.global_position.x, 0, -100))
	var a3 := {}
	await _roll("bosque_documentos", 2.5, func(t: float):
		var pp := player.global_position
		_move(Vector3(0, 0, -1), 0.75)
		for e in fleeing:
			if is_instance_valid(e) and e.alive:
				e.global_position += Vector3(0, 0, -3.6 / FPS)
				e.global_position.y = Terrain.ground_y(e.global_position.x, e.global_position.z)
				e.rig.speed_norm = 1.0
		_place_cam(pp + Vector3(1.6, 2.9, 4.6), pp + Vector3(0, 1.1, -5.0), 58.0)
		if _once(a3, "d0", t, 0.3):
			_docs()
		if _once(a3, "d1", t, 0.95):
			_doc_volley(8)
		if _once(a3, "d2", t, 1.5):
			_doc_volley(10)
		)
	_move(Vector3.ZERO)
	# --- A4: industrial, esquiva en el último instante ---
	await _arena(10)
	_give("dodge_nova", 4, 3)
	GameState.build_changed.emit()
	P = _ground(0, 2)
	_put_player(P, Vector3(0, 0, -1))
	var tank := _spawn("tank", P + Vector3(0, 0, -2.6))
	await _secs(1.2)
	_freeze(tank, P)
	_put_player(P, Vector3(0, 0, -1))
	var a4 := {}
	await _roll("industrial_esquiva", 1.5, func(t: float):
		_lerp_cam(P + Vector3(-3.6, 1.0, 0.6), P + Vector3(-3.3, 1.1, 0.2), P + Vector3(0.3, 1.1, -1.2), P + Vector3(0.6, 1.1, -1.0), t / 1.5, 50.0)
		if _once(a4, "wind", t, 0.0):
			tank.rig.play("windup", 0.55)
			if GameState.fx != null:
				GameState.fx.telegraph_circle(P, 2.2, 0.9)
			AudioManager.sfx("telegraph", -4.0, 0.0)
		if _once(a4, "slow", t, 0.5):
			Engine.time_scale = 0.3
		if _once(a4, "dodge", t, 0.58):
			_dodge(Vector3(1, 0, 0.35))
		if _once(a4, "slam", t, 0.75):
			tank.rig.play("slam", 0.3)
		if _once(a4, "impact", t, 1.0):
			Engine.time_scale = 1.0
			AudioManager.sfx("slam", 0.0, 0.0)
			if GameState.fx != null:
				GameState.fx.ring(P, 2.6, Color(1.0, 0.5, 0.2, 0.9), 0.4, 0.3)
				GameState.fx.burst(P + Vector3(0, 0.3, 0), Color(0.8, 0.7, 0.6), 18, 7.0, 0.16, 0.6)
		)
	Engine.time_scale = 1.0
	# --- A5: cofre y cartas de mejora ---
	await _arena(15)
	arena._spawn_rewards()
	await _f(10)
	_hide_indicators()
	var chest_pos: Vector3 = arena._chest.global_position
	_put_player(chest_pos + Vector3(1.7, 0, 1.7), Vector3(-1, 0, -1))
	await _f(10)
	var a5 := {}
	await _roll("cofre_cartas", 3.0, func(t: float):
		_lerp_cam(chest_pos + Vector3(1.6, 1.9, 3.6), chest_pos + Vector3(1.1, 1.6, 2.8), chest_pos + Vector3(0, 0.6, 0), chest_pos + Vector3(0, 0.8, 0), clampf(t / 1.0, 0.0, 1.0), 48.0)
		if _once(a5, "open", t, 0.12):
			arena._open_chest(3)
		var cs := _overlay_of(CardSelect) as CardSelect
		if cs != null:
			if _once(a5, "sel", t, 1.55):
				cs._select(1)
			if _once(a5, "ok", t, 2.4):
				cs._on_confirm()
		)
	await _f(4)
	for o in main._overlays.duplicate():
		if is_instance_valid(o) and o is CardSelect:
			o.queue_free()
	get_tree().paused = false
	# --- A6/A7: persecuciones alrededor de obstáculos (bosque y desierto) ---
	for pass_i in 2:
		await _arena(6 if pass_i == 0 else 16)
		var O := _nearest_obstacle(Vector3(0, 0, 0))
		var oc := _ground(0, 0) if O == Vector3.INF else _ground(O.x, O.y)
		var rr: float = 1.0 if O == Vector3.INF else O.z
		_put_player(oc + Vector3(rr + 1.6, 0, 0), Vector3(0, 0, -1))
		for i in 5:
			var ang := PI + (i - 2) * 0.35
			_spawn("thief" if i != 2 else "runner", oc + Vector3(cos(ang), 0, sin(ang)) * (rr + 5.0))
		await _secs(1.0)
		var ap := {}
		var nm := "persecucion_bosque" if pass_i == 0 else "persecucion_desierto"
		await _roll(nm, 1.25, func(t: float):
			var rel := player.global_position - oc
			rel.y = 0.0
			var tang := Vector3(-rel.z, 0, rel.x).normalized() * -1.0
			var radial := rel.normalized() * ((rr + 1.6) - rel.length()) * 0.8
			_move(tang + radial, 1.0)
			_place_cam(oc + Vector3(4.5, 7.5, 7.5), oc + Vector3(0, 0.5, 0), 56.0)
			if _once(ap, "th", t, 0.55):
				_throw()
			)
		_move(Vector3.ZERO)
	# --- A8: ciudadela, build desatada: explosiones y rayos ---
	await _arena(20)
	_mayhem_build()
	P = _ground(0, 0)
	_put_player(P)
	var crowd: Array = []
	for i in 14:
		var ang := TAU * i / 14.0
		crowd.append(_spawn(["thief", "runner", "tank", "thief"][i % 4], P + Vector3(cos(ang), 0, sin(ang)) * (4.5 + (i % 3) * 1.3)))
	await _secs(1.1)
	var a8 := {}
	await _roll("ciudadela_explosiones", 2.25, func(t: float):
		_orbit_cam(player.global_position, 8.5, 5.0, 0.5 + t * 0.35, 0.8, 58.0)
		if _once(a8, "m", t, 0.0):
			_throw(true)
		if _once(a8, "d", t, 0.2):
			_docs()
		for k in [0.5, 1.0, 1.5, 2.0]:
			if _once(a8, "x%s" % k, t, k):
				var alive_e := crowd.filter(func(x): return is_instance_valid(x) and x.alive)
				if not alive_e.is_empty():
					var tg: Enemy = alive_e[randi() % alive_e.size()]
					Combat.explode(tg.global_position, 3.2, 400.0, {"src": "crit_explosion"})
		for k2 in [0.75, 1.25, 1.75]:
			if _once(a8, "c%s" % k2, t, k2):
				var alive2 := crowd.filter(func(x): return is_instance_valid(x) and x.alive)
				if not alive2.is_empty():
					Combat.chain_lightning(alive2[0], 200.0, 5)
		if _once(a8, "dg", t, 1.1):
			_dodge(Vector3(-1, 0, 0.4))
		if _once(a8, "t2", t, 1.4):
			_throw()
		)
	# --- A9: pausa cómica ---
	_clear_enemies()
	await _f(6)
	var V := _ground(2.5, -1.5)
	var dazed := _spawn("thief", V)
	await _secs(0.9)
	_freeze(dazed, V + Vector3(-1.2, 0, 3))
	dazed.rig.set_status_visual(0.0, 1.0, Color(0.55, 0.5, 0.5))
	var paper := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.36, 0.46, 0.01)
	paper.mesh = pm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.97, 0.96, 0.9)
	paper.material_override = pmat
	(dazed.rig.j["head"] as Node3D).add_child(paper)
	paper.position = Vector3(0.0, 0.3, -0.27)
	paper.rotation_degrees = Vector3(0, 0, 8)
	_put_player(_ground(-4, 4))
	var a9 := {}
	await _roll("pausa_comica", 1.5, func(t: float):
		var c := V + Vector3(0, 1.2, 0)
		_place_cam(V + Vector3(-1.0, 1.45, 2.9), c, 40.0)
		if _once(a9, "puff", t, 0.05) and GameState.fx != null:
			GameState.fx.burst(V + Vector3(0, 1.9, 0), Color(0.35, 0.33, 0.33), 10, 1.2, 0.2, 1.2)
		if _once(a9, "fall", t, 0.95):
			dazed.rig.die(0.5)
		if _once(a9, "plop", t, 1.3):
			AudioManager.sfx("bounce", -6.0, 0.0)
		)
	# --- A10: el abogado camina muy serio mientras todo explota detrás ---
	await _arena(1)
	P = _ground(0, -6)
	_put_player(P, Vector3(0, 0, 1))
	var behind: Array = []
	for i in 10:
		behind.append(_spawn(["thief", "runner", "tank"][i % 3], P + Vector3(-5.0 + (i % 5) * 2.5, 0, -3.0 - (i / 5) * 3.0)))
	await _secs(1.0)
	for e in behind:
		_freeze(e, P)
	var a10 := {}
	await _roll("caminata_seria", 3.25, func(t: float):
		_move(Vector3(0, 0, 1), 0.42)
		var pp := player.global_position
		_place_cam(pp + Vector3(0.7, 1.35, 4.6), pp + Vector3(0, 1.35, -1.0), 50.0)
		var times := [0.25, 0.75, 1.25, 1.75, 2.25, 2.75]
		for k in times.size():
			if _once(a10, "e%d" % k, t, times[k]):
				var e2: Enemy = behind[(k * 3) % behind.size()]
				var at: Vector3 = e2.global_position if is_instance_valid(e2) else pp + Vector3(randf_range(-4, 4), 0, -6)
				for x in behind:
					if is_instance_valid(x) and x.alive and x.global_position.distance_to(at) < 3.5:
						x.set_physics_process(true)
				Combat.explode(at, 3.5, 900.0, {"src": "crit_explosion"})
				if GameState.fx != null:
					GameState.fx.flash_sphere(at + Vector3(0, 1.0, 0), 2.6, Color(1.0, 0.6, 0.2, 0.85), 0.35)
					GameState.fx.burst(at + Vector3(0, 1.0, 0), Color(1.0, 0.45, 0.15), 24, 9.0, 0.2, 0.8)
				if main.cam != null:
					main.cam.shake(0.2)
		)
	_move(Vector3.ZERO)
	# --- A11-A13: el jefe en el tribunal ---
	await _arena(25)
	P = _ground(0, 3)
	_put_player(P, Vector3(0, 0, -1))
	var boss := _spawn("boss", _ground(0, -5))
	await _secs(2.0)
	_freeze(boss, P)
	_put_player(P, Vector3(0, 0, -1))
	var B := boss.global_position
	var a11 := {}
	await _roll("jefe_rugido", 1.0, func(t: float):
		var sh := Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * 0.05 * clampf(t - 0.2, 0.0, 1.0)
		_lerp_cam(B + Vector3(1.8, 0.5, 4.0), B + Vector3(1.4, 0.55, 3.4), B + Vector3(0, 2.6, 0), B + Vector3(0, 2.8, 0), t, 48.0)
		cam.global_position += sh
		if _once(a11, "roar", t, 0.05):
			boss.rig.play("roar", 0.9)
			AudioManager.sfx("boss_roar", 0.0, 0.0)
		)
	var a12 := {}
	await _roll("jefe_esquiva", 1.0, func(t: float):
		_place_cam(P + Vector3(-5.5, 2.2, 1.5), (P + B) * 0.5 + Vector3(0, 1.0, 0), 54.0)
		if _once(a12, "st", t, 0.0):
			boss.rig.play("stomp", 0.5)
			if GameState.fx != null:
				GameState.fx.telegraph_circle(P, 2.6, 0.6)
		if _once(a12, "slow", t, 0.3):
			Engine.time_scale = 0.35
		if _once(a12, "dg", t, 0.35):
			_dodge(Vector3(1, 0, 0.25))
		if _once(a12, "hit", t, 0.65):
			Engine.time_scale = 1.0
			AudioManager.sfx("slam", 0.0, 0.0)
			if GameState.fx != null:
				GameState.fx.ring(P, 3.0, Color(1.0, 0.4, 0.2, 0.9), 0.4, 0.3)
				GameState.fx.burst(P + Vector3(0, 0.3, 0), Color(0.8, 0.7, 0.6), 22, 8.0, 0.16, 0.6)
		)
	Engine.time_scale = 1.0
	_mayhem_build()
	var a13 := {}
	await _roll("jefe_locura", 2.0, func(t: float):
		var mid := (player.global_position + B) * 0.5
		_orbit_cam(mid, 9.0, 4.0, -0.9 + t * 0.4, 1.2, 56.0)
		if _once(a13, "m", t, 0.0):
			_throw(true)
		if _once(a13, "d", t, 0.3):
			_docs()
		if _once(a13, "c1", t, 0.6):
			Combat.chain_lightning(boss, 300.0, 4)
		if _once(a13, "x1", t, 0.8):
			Combat.explode(B, 3.5, 300.0, {"src": "crit_explosion"})
		if _once(a13, "t2", t, 1.05):
			_throw()
		if _once(a13, "c2", t, 1.4):
			Combat.chain_lightning(boss, 300.0, 4)
		if _once(a13, "x2", t, 1.6):
			Combat.explode(B, 3.5, 300.0, {"src": "crit_explosion"})
		if is_instance_valid(boss) and boss.alive:
			boss.hp = maxf(boss.hp, boss.max_hp * 0.3)
		)
	# --- A14: el martillo del juez dicta sentencia ---
	var a14 := {}
	await _roll("sentencia", 1.5, func(t: float):
		_lerp_cam(P + Vector3(-1.4, 1.6, 2.6), P + Vector3(-1.2, 1.7, 2.2), B + Vector3(0, 2.0, 0), B + Vector3(0, 1.6, 0), t / 1.5, 50.0)
		if _once(a14, "th", t, 0.15):
			_throw()
		if _once(a14, "kill", t, 0.5):
			_snd("gavel_big", 2.0)
			flash = 0.8
			Engine.time_scale = 0.35
			_kill(boss, 10.0, Vector3(0, 0, -3))
			if GameState.fx != null:
				GameState.fx.flash_sphere(B + Vector3(0, 2.0, 0), 4.0, Color(1, 0.95, 0.7, 0.9), 0.4)
				GameState.fx.ring(B, 6.0, Color(1.0, 0.85, 0.3, 0.9), 0.6, 0.5)
		if t > 0.5:
			flash = maxf(0.0, 0.8 - (t - 0.5) * 3.0)
		if _once(a14, "norm", t, 1.0):
			Engine.time_scale = 1.0
		)
	Engine.time_scale = 1.0
	flash = 0.0
	# --- A15: montaje final (cortes rápidos por biomas) ---
	var mont := [[11, "m_industrial", 1.0], [17, "m_desierto", 0.75], [7, "m_bosque", 0.75], [21, "m_ciudadela", 1.0]]
	for mi in mont.size():
		await _arena(int(mont[mi][0]))
		P = _ground(0, 0)
		_put_player(P)
		var group: Array = []
		for i in 12:
			var ang2 := TAU * i / 12.0
			group.append(_spawn(["thief", "runner", "thief", "tank"][i % 4], P + Vector3(cos(ang2), 0, sin(ang2)) * (3.5 + (i % 3) * 1.5)))
		await _secs(1.0)
		_throw(mi % 2 == 0)
		await _f(6)
		var am := {"i": mi}
		await _roll(String(mont[mi][1]), float(mont[mi][2]), func(t: float):
			var pp := player.global_position
			match int(am["i"]):
				0:
					_orbit_cam(pp, 7.5, 3.0, 2.2 + t * 0.6, 1.0, 58.0)
					if _once(am, "a", t, 0.4):
						_doc_volley(6)
				1:
					_place_cam(pp + Vector3(-1.2, 2.2, 3.8), pp + Vector3(0, 1.2, -3.0), 58.0)
					if _once(am, "a", t, 0.0):
						_docs()
						_doc_volley(12)
				2:
					_place_cam(pp + Vector3(0.5, 10.0, 6.0), pp, 52.0)
					for k in [0.05, 0.3, 0.55]:
						if _once(am, "c%s" % k, t, k):
							var al := group.filter(func(x): return is_instance_valid(x) and x.alive)
							if not al.is_empty():
								Combat.chain_lightning(al[randi() % al.size()], 400.0, 6)
				3:
					_orbit_cam(pp, 6.0, 1.4, -0.6 + t * 0.5, 1.4, 60.0)
					if _once(am, "a", t, 0.2):
						_dodge(Vector3(0.3, 0, -1))
					if _once(am, "b", t, 0.45):
						Combat.explode(pp, 7.0, 900.0, {"src": "crit_explosion"})
						if GameState.fx != null:
							GameState.fx.flash_sphere(pp + Vector3(0, 1.0, 0), 5.0, Color(1.0, 0.7, 0.3, 0.8), 0.4)
			)
	# --- A16: lanzamiento final hacia la cámara ---
	await _arena(3)
	P = _ground(0, 2)
	_put_player(P, Vector3(0, 0, 1))
	for i in 5:
		_spawn("thief", P + Vector3(-4.0 + i * 2.0, 0, -9.0))
	await _secs(0.6)
	_put_player(P, Vector3(0, 0, 1))
	var cp := P + Vector3(0.25, 1.5, 4.2)
	var a16 := {}
	flying_case.scale = Vector3.ONE * 1.8
	await _roll("lanzamiento_final", 2.3, func(t: float):
		player.face_dir(Vector3(0, 0, 1), 0.3)
		var k := t / 2.3
		var camp := cp.lerp(P + Vector3(0.2, 1.45, 3.4), _ease(k))
		_place_cam(camp, P + Vector3(0, 1.3, 0), 50.0)
		if _once(a16, "wind", t, 1.15):
			player.rig.play("throw", 0.45)
		if _once(a16, "rel", t, 1.35):
			(player.rig.props["case"] as Node3D).visible = false
			flying_case.visible = true
			AudioManager.sfx("throw", 0.0, 0.0)
			_snd("whoosh", 0.0)
		if t >= 1.35:
			var k2 := clampf((t - 1.35) / 0.9, 0.0, 1.0)
			var from := P + Vector3(0.35, 1.55, 0.4)
			var to := camp + (P + Vector3(0, 1.3, 0) - camp).normalized() * 0.3
			flying_case.global_position = from.lerp(to, k2 * k2)
			flying_case.rotation = Vector3(t * 10.0, t * 3.0, 0.3)
		fade = 1.0 if t >= 2.25 else 0.0
		)
	flying_case.visible = false
	(player.rig.props["case"] as Node3D).visible = true


func _overlay_of(cls: Variant) -> Node:
	for o in main._overlays:
		if is_instance_valid(o) and is_instance_of(o, cls):
			return o
	return null


# ============================================================================ LOGO
func _logo() -> void:
	Engine.time_scale = 1.0
	fade = 1.0
	var sky := TrailerSets.skyline()
	sky["root"].position = LOGO_POS
	add_child(sky["root"])
	var runners: Array = []
	for i in 3:
		var th := ModelFactory.build_enemy("thief", i)
		add_child(th)
		th.set_status_visual(0.0, 0.0, Color(0.02, 0.01, 0.04))
		th.material.set_shader_parameter("rim_amount", 0.0)
		th.global_position = LOGO_POS + Vector3(-9.0 - i * 2.2, -1.7, -6.0)
		th.rotation.y = -PI * 0.5
		th.speed_norm = 1.0
		runners.append(th)
	for i in 3:
		if i < thieves.size():
			thieves[i].visible = false
	await _f(4)
	var lg := {}
	await _roll("logo", 9.6, func(t: float):
		_place_cam(LOGO_POS + Vector3(0, 1.0 + t * 0.06, 12.0 - t * 0.25), LOGO_POS + Vector3(0, 4.0, -30), 52.0)
		for i in runners.size():
			var r: Node3D = runners[i]
			r.global_position.x += 3.2 / FPS
		if _once(lg, "g1", t, 0.15):
			_snd("gavel_big", 0.0)
		if _once(lg, "g2", t, 0.5):
			_snd("gavel_big", 0.0, 0.92)
		if t < 0.85:
			fade = 1.0
			logo_a = 0.0
		else:
			if _once(lg, "boom", t, 0.85):
				_snd("boom", 0.0)
				_snd("gavel_big", -2.0, 0.8)
				flash = 0.9
			flash = maxf(0.0, 0.9 - (t - 0.85) * 2.5)
			fade = maxf(0.0, 1.0 - (t - 0.85) * 2.0)
			logo_a = 1.0
			logo_pop = clampf((t - 0.85) / 0.35, 0.0, 1.0)
			tag_a = clampf((t - 1.7) / 0.5, 0.0, 1.0)
		if t > 9.0:
			var k := clampf((t - 9.0) / 0.55, 0.0, 1.0)
			fade = k
			logo_a = 1.0 - k
			tag_a = minf(tag_a, 1.0 - k)
		)
