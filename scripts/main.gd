extends Node
## Orquestador del juego: crea el mundo 3D, la UI y controla el flujo
## Vestíbulo del Bufete (primera escena jugable) → partida (arenas, cofres, tienda, portales) → derrota/victoria → Vestíbulo.
##
## process_mode = ALWAYS (ver main.tscn) para poder gestionar pausas; el mundo 3D se marca PAUSABLE.

enum St { BOOT, RUN, ENDED, LOBBY }

var state := St.BOOT
var world: Node3D
var fx: FX
var projectiles: Projectiles
var cam: CameraRig
var player: Player
var arena: Arena
var lobby: Lobby

var hud_layer: CanvasLayer
var overlay_layer: CanvasLayer
var fade_layer: CanvasLayer
var hud: HUD
var touch: TouchControls
var fade: ColorRect
var banner_panel: PanelContainer
var banner: Label
var _banner_tw: Tween

var _overlays: Array = []
var _pause_menu: PauseMenu
var pad: PadInput
var pad_nav: PadNav
var _transitioning := false
var _victory_shown := false
var _end_pending := false
var _selftest := false


func _ready() -> void:
	GameState.main = self
	get_tree().set_auto_accept_quit(true)
	DisplayServer.screen_set_keep_on(true)
	Config.dev_mode = bool(SaveSystem.setting("dev_unlocked"))
	_build_world()
	_build_ui()
	_build_pad()
	Config.apply_graphics(get_viewport())
	AudioManager.apply_volumes()
	SaveSystem.notice.connect(notify)
	if Config.cmd_flag("--selftest"):
		_selftest = true
		var st := load("res://tests/selftest.gd")
		if st != null:
			var node: Node = st.new()
			node.name = "SelfTest"
			add_child(node)
			node.set("main", self)
		return
	if Config.cmd_flag("--lobbytest"):
		var lt := load("res://tests/lobbytest.gd")
		if lt != null:
			var lnode: Node = lt.new()
			lnode.name = "LobbyTest"
			add_child(lnode)
			lnode.set("main", self)
		return
	if Config.cmd_flag("--invtest"):
		var it := load("res://tests/invtest.gd")
		if it != null:
			var inode: Node = it.new()
			inode.name = "InvTest"
			add_child(inode)
			inode.set("main", self)
		return
	if Config.cmd_flag("--casetest"):
		var ctst := load("res://tests/casetest.gd")
		if ctst != null:
			var cnode: Node = ctst.new()
			cnode.name = "CaseTest"
			add_child(cnode)
			cnode.set("main", self)
		return
	if Config.cmd_flag("--padtest"):
		var pdt := load("res://tests/padtest.gd")
		if pdt != null:
			var pdn: Node = pdt.new()
			pdn.name = "PadTest"
			add_child(pdn)
			pdn.set("main", self)
		return
	if Config.cmd_flag("--controltest"):
		var cot := load("res://tests/controltest.gd")
		if cot != null:
			var con: Node = cot.new()
			con.name = "ControlTest"
			add_child(con)
			con.set("main", self)
		return
	if Config.cmd_flag("--biometest"):
		var bmt := load("res://tests/biometest.gd")
		if bmt != null:
			var bmn: Node = bmt.new()
			bmn.name = "BiomeTest"
			add_child(bmn)
			bmn.set("main", self)
		return
	if Config.cmd_flag("--cameratest"):
		# observa el arranque normal (Vestíbulo) y luego entra en una partida
		var cmt := load("res://tests/cameratest.gd")
		if cmt != null:
			var cmn: Node = cmt.new()
			cmn.name = "CameraTest"
			add_child(cmn)
			cmn.set("main", self)
	if Config.cmd_flag("--trailer"):
		# rodaje del tráiler (carpeta trailer/): no afecta al juego normal
		var trd := load("res://trailer/trailer_director.gd")
		if trd != null:
			var trn: Node = trd.new()
			trn.name = "TrailerDirector"
			add_child(trn)
			trn.set("main", self)
	if Config.cmd_flag("--difftest"):
		var dft := load("res://tests/difftest.gd")
		if dft != null:
			var dfn: Node = dft.new()
			dfn.name = "DiffTest"
			add_child(dfn)
			dfn.set("main", self)
	if Config.cmd_flag("--attacktest"):
		var att_t := load("res://tests/attacktest.gd")
		if att_t != null:
			var atn: Node = att_t.new()
			atn.name = "AttackTest"
			add_child(atn)
			atn.set("main", self)
	if Config.cmd_flag("--perftest"):
		var prf_t := load("res://tests/perftest.gd")
		if prf_t != null:
			var prn: Node = prf_t.new()
			prn.name = "PerfTest"
			add_child(prn)
			prn.set("main", self)
	if Config.cmd_flag("--fxshot"):
		var fxs := load("res://tests/fxshot.gd")
		if fxs != null:
			var fxn: Node = fxs.new()
			fxn.name = "FxShot"
			add_child(fxn)
			fxn.set("main", self)
	if Config.cmd_flag("--chesttest"):
		var cht := load("res://tests/chesttest.gd")
		if cht != null:
			var chn: Node = cht.new()
			chn.name = "ChestTest"
			add_child(chn)
			chn.set("main", self)
	if Config.cmd_flag("--handtest"):
		var hdt := load("res://tests/handtest.gd")
		if hdt != null:
			var hdn: Node = hdt.new()
			hdn.name = "HandTest"
			add_child(hdn)
			hdn.set("main", self)
	if Config.cmd_flag("--bosstest"):
		var bst_t := load("res://tests/bosstest.gd")
		if bst_t != null:
			var bsn: Node = bst_t.new()
			bsn.name = "BossTest"
			add_child(bsn)
			bsn.set("main", self)
	if Config.cmd_flag("--revivetest"):
		var rvt := load("res://tests/revivetest.gd")
		if rvt != null:
			var rvn: Node = rvt.new()
			rvn.name = "ReviveTest"
			add_child(rvn)
			rvn.set("main", self)
	if Config.cmd_flag("--lawtest"):
		var lwt := load("res://tests/lawtest.gd")
		if lwt != null:
			var lwn: Node = lwt.new()
			lwn.name = "LawTest"
			add_child(lwn)
			lwn.set("main", self)
	if Config.cmd_flag("--endtest"):
		var ent := load("res://tests/endtest.gd")
		if ent != null:
			var enn: Node = ent.new()
			enn.name = "EndTest"
			add_child(enn)
			enn.set("main", self)
	if Config.cmd_flag("--shopcoltest"):
		var sct := load("res://tests/shopcoltest.gd")
		if sct != null:
			var scn: Node = sct.new()
			scn.name = "ShopColTest"
			add_child(scn)
			scn.set("main", self)
	if Config.cmd_flag("--shoptest"):
		var sht := load("res://tests/shoptest.gd")
		if sht != null:
			var shn: Node = sht.new()
			shn.name = "ShopTest"
			add_child(shn)
			shn.set("main", self)
	if Config.cmd_flag("--navtest"):
		var nvt := load("res://tests/navtest.gd")
		if nvt != null:
			var nvn: Node = nvt.new()
			nvn.name = "NavTest"
			add_child(nvn)
			nvn.set("main", self)
		return
	if Config.cmd_flag("--fbtest"):
		var bt := load("res://tests/fbtest.gd")
		if bt != null:
			var bnode: Node = bt.new()
			bnode.name = "FeedbackTest"
			add_child(bnode)
			bnode.set("main", self)
		return
	if Config.cmd_flag("--flowtest"):
		var ft := load("res://tests/flowtest.gd")
		if ft != null:
			var fnode: Node = ft.new()
			fnode.name = "FlowTest"
			add_child(fnode)
			fnode.set("main", self)
		return
	if Config.cmd_flag("--starttest"):
		# esta prueba observa el arranque en frío REAL: se añade y el juego arranca como siempre
		var stt := load("res://tests/starttest.gd")
		if stt != null:
			var stn: Node = stt.new()
			stn.name = "StartTest"
			add_child(stn)
			stn.set("main", self)
	# Arranque normal: directo al Vestíbulo del Bufete (sin pantalla de menú previa)
	_enter_lobby(true)


# ------------------------------------------------------------------ construcción
func _build_world() -> void:
	world = Node3D.new()
	world.name = "World"
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	fx = FX.new()
	fx.name = "FX"
	world.add_child(fx)
	projectiles = Projectiles.new()
	projectiles.name = "Projectiles"
	world.add_child(projectiles)
	var case_throw := CaseThrow.new()
	case_throw.name = "CaseThrow"
	world.add_child(case_throw)
	arena = Arena.new()
	arena.name = "Arena"
	world.add_child(arena)
	player = Player.new()
	player.name = "Player"
	player.visible = false
	world.add_child(player)
	cam = CameraRig.new()
	cam.name = "CameraRig"
	world.add_child(cam)
	player.cam = cam
	player.died.connect(_on_player_died)
	arena.chest_opened.connect(_on_chest_opened)
	arena.bonus_chest_opened.connect(_on_bonus_chest_opened)
	arena.portal_entered.connect(_on_portal)
	arena.shop_requested.connect(_on_shop)
	arena.cleared.connect(_on_arena_cleared)


func _build_ui() -> void:
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 5
	hud_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(hud_layer)
	var theme_root := Control.new()
	theme_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme_root.theme = UIKit.theme()
	hud_layer.add_child(theme_root)
	theme_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud = HUD.new()
	hud.visible = false
	hud.pause_pressed.connect(_toggle_pause)
	hud.inventory_pressed.connect(_open_inventory)
	theme_root.add_child(hud)
	touch = TouchControls.new()
	touch.visible = false
	theme_root.add_child(touch)
	touch.blockers = hud.ui_blockers()
	overlay_layer = CanvasLayer.new()
	overlay_layer.layer = 20
	overlay_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(overlay_layer)
	var ov := Control.new()
	ov.name = "OverlayRoot"
	ov.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.theme = UIKit.theme()
	overlay_layer.add_child(ov)
	ov.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade_layer = CanvasLayer.new()
	fade_layer.layer = 40
	fade_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(fade_layer)
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 0)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_layer.add_child(fade)
	# aviso de guardado / carga / error (visible en menús, sala y partida)
	var bl := CanvasLayer.new()
	bl.layer = 35
	bl.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(bl)
	banner_panel = PanelContainer.new()
	banner_panel.add_theme_stylebox_override("panel", UIKit.style(Color(0.04, 0.05, 0.1, 0.9), Color(1, 1, 1, 0.2), 14, 2, 14))
	banner_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_panel.visible = false
	bl.add_child(banner_panel)
	UIKit.place(banner_panel, 0.5, 0.0, -320, 12, 640, 0)
	banner_panel.grow_vertical = Control.GROW_DIRECTION_END
	banner = UIKit.label("", 22, UIKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_panel.add_child(banner)


## Mensaje breve arriba de la pantalla (guardado, carga, errores).
func notify(text: String, good := true) -> void:
	if banner == null:
		return
	banner.text = text
	banner.add_theme_color_override("font_color", UIKit.GOOD if good else UIKit.BAD)
	# durante la partida va debajo del panel de objetivo para no taparlo
	var top_y := 120.0 if state == St.RUN else 12.0
	UIKit.place(banner_panel, 0.5, 0.0, -320, top_y, 640, 0)
	banner_panel.grow_vertical = Control.GROW_DIRECTION_END
	banner_panel.visible = true
	banner_panel.modulate.a = 1.0
	if _banner_tw != null and _banner_tw.is_valid():
		_banner_tw.kill()
	_banner_tw = banner_panel.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_banner_tw.tween_interval(2.4 if good else 4.5)
	_banner_tw.tween_property(banner_panel, "modulate:a", 0.0, 0.5)
	_banner_tw.tween_callback(func(): banner_panel.visible = false)


func _ov_root() -> Control:
	return overlay_layer.get_node("OverlayRoot")


func _open_overlay(n: Control) -> void:
	_ov_root().add_child(n)
	_overlays.append(n)
	touch.release_all()
	get_tree().paused = true
	n.tree_exited.connect(func():
		_overlays.erase(n)
		if _overlays.is_empty() and state != St.ENDED and is_inside_tree():
			get_tree().paused = false)


## Inventario de mejoras (botón del HUD, pausa y cofres). Se apila sobre cualquier otro panel.
func _open_inventory() -> void:
	if state != St.RUN or _transitioning:
		return
	for o in _overlays:
		if o is InventoryUI:
			return
	_open_overlay(InventoryUI.new())


func _open_inventory_over(cs: CardSelect) -> void:
	var inv := InventoryUI.new()
	var changed := [false]
	inv.changed.connect(func(): changed[0] = true)
	inv.tree_exited.connect(func():
		if is_instance_valid(cs):
			cs.on_inventory_closed(changed[0]))
	_open_overlay(inv)


func _fade_to(a: float, t := 0.25) -> void:
	var tw := create_tween()
	tw.tween_property(fade, "color:a", a, t)
	await tw.finished


# ------------------------------------------------------------------ ajustes
## Abre una página de ajustes: "game" (AJUSTES), "video" (VÍDEO Y GRÁFICOS) o "audio" (AUDIO).
func _open_settings(page := "game") -> void:
	var s := SettingsMenu.new()
	s.page = page
	s.edit_controls_requested.connect(_begin_edit_controls)
	s.dev_tools_requested.connect(_open_dev_tools)
	if page == "camera" and _pause_menu != null and is_instance_valid(_pause_menu):
		# la página CÁMARA deja ver la escena para comprobar los cambios al instante: se oculta la pausa mientras tanto
		var pm := _pause_menu
		pm.visible = false
		s.tree_exited.connect(func():
			if is_instance_valid(pm):
				pm.visible = true)
	_open_overlay(s)


## CONTROLES (táctil, mando y teclado) directo desde la pausa.
func _open_controls() -> void:
	var cm := ControlsMenu.new()
	cm.edit_controls_requested.connect(func():
		cm.queue_free()
		_begin_edit_controls())
	_open_overlay(cm)


func _open_dev_tools() -> void:
	var d := DevTools.new()
	d.jump_to_arena.connect(func(i): if state == St.RUN: _begin_arena(i))
	_open_overlay(d)


var _edit_hidden: Array = []


func _begin_edit_controls() -> void:
	# oculta los menús abiertos y el HUD y deja solo los controles editables
	_edit_hidden.clear()
	for o in _overlays:
		if is_instance_valid(o) and (o as Control).visible:
			(o as Control).visible = false
			_edit_hidden.append(o)
	hud.visible = false
	touch.visible = true
	touch.begin_edit()
	get_tree().paused = true
	if not touch.edit_finished.is_connected(_on_edit_done):
		touch.edit_finished.connect(_on_edit_done, CONNECT_ONE_SHOT)


func _on_edit_done() -> void:
	hud.visible = state == St.RUN or state == St.LOBBY
	touch.visible = hud.visible
	for o in _edit_hidden:
		if is_instance_valid(o):
			(o as Control).visible = true
	_edit_hidden.clear()
	get_tree().paused = not _overlays.is_empty()


# ------------------------------------------------------------------ Vestíbulo del Bufete
## Entra al Vestíbulo: es la primera escena jugable al abrir el juego (instant = sin fundido de salida) y a donde
## se vuelve al terminar o abandonar una partida.
func _enter_lobby(instant := false) -> void:
	if _transitioning:
		return
	_transitioning = true
	if instant:
		fade.color.a = 1.0          # arranque en frío: negro hasta tener la sala construida
	else:
		await _fade_to(1.0, 0.25)
	get_tree().paused = false
	GameState.in_run = false
	if arena != null:
		arena._teardown()
		arena.phase = Arena.Phase.IDLE
	_cleanup_lobby()
	lobby = Lobby.new()
	world.add_child(lobby)
	lobby.build()
	lobby.station_activated.connect(_on_station)
	arena.practice_targets = lobby.dummies
	state = St.LOBBY
	if _zoom_tw != null and _zoom_tw.is_valid():
		_zoom_tw.kill()
	player.visible = true
	GameState.prepare_practice()
	player.teleport_to(lobby.spawn_position())
	player.iframes = 1.0
	cam.target = player
	cam.apply_settings()
	cam.shoulder = 0.55
	cam.yaw = 0.0
	cam.snap_to_target()
	hud.visible = true
	hud.set_lobby(true)
	touch.visible = true
	touch.release_all()
	Engine.time_scale = 1.0
	AudioManager.play_music("menu")
	Config.apply_graphics(get_viewport())
	await _fade_to(0.0, 0.3)
	_transitioning = false
	if SaveSystem.last_load_note != "":
		notify(SaveSystem.last_load_note, false)
		SaveSystem.last_load_note = ""
	elif SaveSystem.has_valid_run():
		notify("Tienes una partida guardada: entra por el portal CONTINUAR PARTIDA", true)
	else:
		notify("Vestíbulo del Bufete: prepara tu equipo y entra por un portal", true)


func _cleanup_lobby() -> void:
	if arena != null:
		arena.practice_targets = []
	if lobby != null and is_instance_valid(lobby):
		lobby.queue_free()
	lobby = null
	if player != null and player.skills != null:
		player.skills.practice = false
	if hud != null:
		hud.set_lobby(false)


func _on_station(id: String) -> void:
	if _transitioning or state != St.LOBBY or not _overlays.is_empty():
		return
	AudioManager.sfx("click")
	if id == "new_run":
		if SaveSystem.has_valid_run():
			_confirm_overwrite()
		else:
			_go_to_run({})
	elif id == "continue":
		_on_continue()
	elif id.begins_with("equip:"):
		var ui := EquipStationUI.new(id.substr(6))
		ui.changed.connect(_lobby_changed)
		ui.closed.connect(_lobby_changed)
		_open_overlay(ui)
	elif id == "difficulty":
		var d := DifficultyUI.new()
		d.changed.connect(_lobby_changed)
		d.closed.connect(_lobby_changed)
		_open_overlay(d)
	elif id == "meta":
		var m := MetaScreen.new()
		m.closed.connect(_lobby_changed)
		_open_overlay(m)
	elif id == "stats":
		_open_overlay(StatsPanel.new())


## Tras cambiar equipo, dificultad o mejoras: la sala y la zona de práctica reflejan la elección.
func _lobby_changed() -> void:
	if state != St.LOBBY:
		return
	GameState.prepare_practice()
	if lobby != null and is_instance_valid(lobby):
		lobby.refresh()


func _confirm_overwrite() -> void:
	var box := Control.new()
	box.process_mode = Node.PROCESS_MODE_ALWAYS
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_child(UIKit.dim_background(0.7))
	var v := UIKit.center_box(box, Vector2(640, 260))
	v.add_theme_constant_override("separation", 12)
	v.add_child(UIKit.label("¿Empezar una partida nueva?", 34, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER))
	var l := UIKit.label("Ya tienes una partida guardada. Si empiezas una nueva, la guardada se perderá.", 22, UIKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(580, 0)
	v.add_child(l)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	var no := UIKit.accent_button("Cancelar", Vector2(240, 62), 26)
	no.pressed.connect(box.queue_free)
	row.add_child(no)
	var yes := UIKit.button("Sobrescribir", Vector2(240, 62), 26)
	yes.pressed.connect(func():
		box.queue_free()
		await get_tree().process_frame
		_go_to_run({}))
	row.add_child(yes)
	_open_overlay(box)


# ------------------------------------------------------------------ partida
func _on_play() -> void:
	_go_to_run({})


## Continúa la partida guardada (si es válida; si no, avisa y no hace nada).
func _on_continue() -> void:
	if _transitioning:
		return
	var run := SaveSystem.get_run()
	if run.is_empty():
		notify("No hay una partida guardada válida.", false)
		return
	_go_to_run(run)


func _go_to_run(resume: Dictionary) -> void:
	if _transitioning:
		return
	_transitioning = true
	if state == St.LOBBY:
		# pequeña transición al cruzar el portal: sonido, aviso, zoom de cámara y fundido
		AudioManager.sfx("portal")
		GameState.toast_msg("¡A los tribunales!" if resume.is_empty() else "Retomando tu partida…", Color(0.8, 0.7, 1.0))
		if GameState.fx != null and player != null:
			GameState.fx.flash_sphere(player.global_position + Vector3(0, 1.0, 0), 2.4, Color(0.7, 0.55, 1.0, 0.8), 0.4)
		if _zoom_tw != null and _zoom_tw.is_valid():
			_zoom_tw.kill()
		_zoom_tw = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_zoom_tw.tween_property(cam, "distance", 2.6, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await _fade_to(1.0, 0.3)
	_cleanup_lobby()
	_start_run(resume)
	_transitioning = false


func _start_run(resume: Dictionary = {}) -> void:
	var restoring := not resume.is_empty()
	ShopUI.purchases = int(resume.get("shop_purchases", 0)) if restoring else 0
	_victory_shown = false
	_end_pending = false
	if restoring:
		GameState.restore_run(resume)
	else:
		SaveSystem.clear_run()      # una partida nueva sustituye a la guardada (el menú ya avisó)
		GameState.start_run()
	state = St.RUN
	if _zoom_tw != null and _zoom_tw.is_valid():
		_zoom_tw.kill()          # el zoom del portal del vestíbulo no debe pisar la distancia elegida por el jugador
	cam.target = player
	cam.apply_settings()
	cam.shoulder = 0.55
	player.visible = true
	player.reset_for_run()
	if restoring:
		player.apply_saved(resume)
		notify("Partida cargada · Arena %d" % (int(resume["arena_index"]) + 1), true)
	hud.visible = true
	touch.visible = true
	get_tree().paused = false
	Engine.time_scale = 1.0
	_begin_arena(int(resume["arena_index"]) if restoring else 0, true, resume)


## ¿Esta arena inaugura una región nueva? (la primera de la partida o la que sigue a un jefe de zona)
func _region_changed(idx: int) -> bool:
	return idx == 0 or BiomeDB.biome_index(idx) != BiomeDB.biome_index(idx - 1)


var _bars: Array = []
## Estado de la visita actual a la tienda (ofertas + relanzamientos usados). Se reinicia al empezar cada arena.
var _shop_visit: Dictionary = {}
var _zoom_tw: Tween


## Cubre la pantalla con la transición propia del bioma al que se entra (varía: fundido, destello, barras, polvo, iris).
func _region_cover(bm: Dictionary) -> void:
	var col: Color = bm["trans_color"]
	fade.color = Color(col.r, col.g, col.b, fade.color.a)
	AudioManager.sfx("portal", -2.0)
	match String(bm["trans"]):
		"flash":
			await _fade_to(1.0, 0.14)
		"bars":
			var vp := get_viewport().get_visible_rect().size
			for i in 2:
				var bar := ColorRect.new()
				bar.color = col.darkened(0.2)
				bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
				bar.anchor_right = 1.0
				bar.anchor_top = 0.0 if i == 0 else 1.0
				bar.anchor_bottom = 0.0 if i == 0 else 1.0
				fade_layer.add_child(bar)
				fade_layer.move_child(bar, fade.get_index())
				_bars.append(bar)
				var tw := create_tween()
				if i == 0:
					tw.tween_property(bar, "offset_bottom", vp.y * 0.52, 0.32).set_trans(Tween.TRANS_CUBIC)
				else:
					tw.tween_property(bar, "offset_top", -vp.y * 0.52, 0.32).set_trans(Tween.TRANS_CUBIC)
			await get_tree().create_timer(0.34).timeout
			fade.color = Color(col.r, col.g, col.b, 1.0)
		"dust":
			await _fade_to(1.0, 0.6)
		"iris":
			await _fade_to(1.0, 0.5)
		_:
			await _fade_to(1.0, 0.4)


func _region_reveal() -> void:
	await _fade_to(0.0, 0.45)
	for bar in _bars:
		if is_instance_valid(bar):
			bar.queue_free()
	_bars.clear()
	fade.color = Color(0, 0, 0, 0)


var _region_banner: Control


## Cartel con el nombre de la región. 'hold' = segundos visible.
func _show_region_banner(idx: int, hold: float) -> void:
	var bm := BiomeDB.for_arena(idx)
	if _region_banner != null and is_instance_valid(_region_banner):
		_region_banner.queue_free()
	var root := Control.new()
	root.name = "RegionBanner"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UIKit.theme()
	# centrado real y ancho limitado al área visible (antes: position absoluta negativa → el texto salía por la izquierda)
	var vs := get_viewport().get_visible_rect().size
	var bw := minf(900.0, vs.x - 48.0)
	var box := VBoxContainer.new()
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 0.5
	box.anchor_bottom = 0.5
	box.offset_left = -bw * 0.5
	box.offset_right = bw * 0.5
	box.offset_top = -120.0
	box.offset_bottom = 120.0
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE      # el cartel NUNCA debe tapar ni bloquear toques del centro de la pantalla
	root.add_child(box)
	var accent: Color = bm["accent"]
	var l1 := UIKit.label("REGIÓN %d" % (Scaling.cycle_of(idx) + 1), 30, accent.lightened(0.2), HORIZONTAL_ALIGNMENT_CENTER)
	var l2 := UIKit.title(String(bm["name"]).to_upper(), 58 if vs.x >= 1000.0 else 40)
	l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l2.add_theme_color_override("font_color", Color(1, 1, 1))
	l2.add_theme_color_override("font_outline_color", accent.darkened(0.55))
	l2.add_theme_constant_override("outline_size", 10)
	var l3 := UIKit.label(String(bm["region"]), 26, Color(0.92, 0.92, 0.95), HORIZONTAL_ALIGNMENT_CENTER)
	for l in [l1, l2, l3]:
		(l as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(l)
	root.modulate.a = 0.0
	fade_layer.add_child(root)
	_region_banner = root
	var tw := create_tween()
	tw.tween_property(root, "modulate:a", 1.0, 0.3)
	tw.tween_interval(hold)
	tw.tween_property(root, "modulate:a", 0.0, 0.45)
	tw.tween_callback(root.queue_free)


func _begin_arena(idx: int, instant := false, resume: Dictionary = {}) -> void:
	_transitioning = true
	_shop_visit = {}                   # visita nueva a la tienda: ofertas nuevas y relanzamientos a 0
	var region := _region_changed(idx)
	var bm := BiomeDB.for_arena(idx)
	if not instant:
		if region:
			await _region_cover(bm)
		else:
			await _fade_to(1.0, 0.25)
	projectiles.clear_all()
	if GameState.case_throw != null:
		GameState.case_throw.clear_all()
	var restoring := not resume.is_empty()
	var stage_name := String(resume.get("stage", "fight"))
	var pos := arena.start(idx, int(resume["arena_seed"]) if restoring else -1)
	if restoring and stage_name != "fight":
		# la arena ya estaba superada: reaparecen el cofre y el portal tal como estaban
		arena.restore_cleared(stage_name == "portal", resume.get("perf", {}))
		var pp: Array = resume["player_pos"]
		var rx := clampf(float(pp[0]), -arena.half + 1.5, arena.half - 1.5)
		var rz := clampf(float(pp[2]), -arena.half + 1.5, arena.half - 1.5)
		pos = Vector3(rx, Terrain.ground_y(rx, rz) + 0.3, rz)
	player.teleport_to(pos)
	player.iframes = maxf(player.iframes, 1.2)
	if not restoring:
		_pay_advance_fee(idx)                 # Cobro Anticipado: solo en rondas nuevas, nunca al cargar una partida
	cam.yaw = 0.0
	cam.snap_to_target()
	if idx > 0 and Scaling.zone_pos(idx) == 0 and (not restoring or stage_name == "fight"):
		GameState.toast_msg("Ciclo %d · los enemigos siguen endureciéndose poco a poco" % (Scaling.cycle_of(idx) + 1), Color(1.0, 0.4, 0.3))
	AudioManager.play_music("combat")
	if region and not instant:
		player.iframes = maxf(player.iframes, 3.0)
		_show_region_banner(idx, 1.15)
		await get_tree().create_timer(1.25).timeout
		await _region_reveal()
	else:
		await _fade_to(0.0, 0.3)
		if region:
			_show_region_banner(idx, 1.3)
	_transitioning = false
	if not restoring:
		_autosave("fight")


# ------------------------------------------------------------------ guardado automático
## Guarda la partida en un momento seguro. Etapas: fight (inicio de arena), reward (arena superada,
## cofre sin abrir) y portal (cofre abierto y recompensa elegida).
func _autosave(stage_name: String, quiet := false) -> bool:
	if state != St.RUN or not GameState.in_run or _end_pending:
		return false
	GameState.flush_stats()
	var ok := SaveSystem.store_run(GameState.snapshot_run(stage_name))
	if ok and not quiet:
		notify("Partida guardada", true)
	return ok


func _on_arena_cleared(_i: int) -> void:
	_autosave("reward")


func _pay_advance_fee(idx: int) -> void:
	var fee := LawPerks.advance_fee(idx)
	if fee > 0:
		GameState.add_coins(fee, false)
		GameState.toast_msg("Cobro Anticipado: +%d $" % fee, Color(1.0, 0.85, 0.3))


func _on_chest_opened(min_rarity: int) -> void:
	await get_tree().create_timer(0.5, true, false, true).timeout
	_start_reward(min_rarity, arena.kind == Scaling.KIND_BOSS)


func _on_bonus_chest_opened(min_rarity: int) -> void:
	await get_tree().create_timer(0.5, true, false, true).timeout
	_start_reward(min_rarity, false)


## Recompensas de UN cofre: 1 elección, o 2 si es de jefe o le toca «cofre doble» (50%). Nunca más de 2 por cofre:
## el doble no se acumula con el del jefe. La 2.ª tirada excluye lo ya elegido (sin duplicados accidentales).
func _start_reward(min_rarity: int, boss: bool) -> void:
	if boss:
		# BOTÍN ESPECIAL del jefe (sistema aparte): 3 opciones de categorías distintas; después, las 2 elecciones normales
		_boss_special_pick(min_rarity)
		return
	var total := 1
	if LawPerks.roll_double(LawPerks.roll()):
		total = 2
		GameState.toast_msg("¡COFRE DOBLE! Puedes elegir dos recompensas", Color(1.0, 0.85, 0.3))
	_reward_pick(min_rarity, 1, total, [])


func _boss_special_pick(min_rarity: int) -> void:
	var seen: Array = GameState.run_stats.get("boss_seen", [])
	var cards: Array = UpgradeDB.boss_case_cards(GameState.build, GameState.arena_index, GameState.rng, 2, GameState.build.s("luck"), seen)
	if cards.is_empty():
		_reward_pick(min_rarity, 1, 2, [])
		return
	var cs := CardSelect.new()
	cs.picked.connect(func(card):
		seen.append(String(card["id"]))
		for c2 in cards:
			if not seen.has(String(c2["id"])):
				seen.append(String(c2["id"]))                  # lo ofrecido tampoco se repite en el siguiente jefe
		GameState.run_stats["boss_seen"] = seen)
	cs.closed.connect(func():
		await get_tree().create_timer(0.1, true, false, true).timeout
		_reward_pick(min_rarity, 1, 2, []))
	cs.inventory_requested.connect(func(): _open_inventory_over(cs))
	_open_overlay(cs)
	cs.open_fixed(cards, "¡BOTÍN ESPECIAL DEL JEFE! ELIGE UNA", GameState.arena_index)


## Compatibilidad (pruebas y herramientas): abre las cartas de un cofre; 'second' = dos elecciones.
func _open_cards(min_rarity: int, second: bool) -> void:
	_reward_pick(min_rarity, 1, 2 if second else 1, [])


func _reward_pick(min_rarity: int, step: int, total: int, taken: Array) -> void:
	var cs := CardSelect.new()
	cs.picked.connect(func(card): taken.append(String(card["id"])))
	cs.closed.connect(func():
		if step < total:
			await get_tree().create_timer(0.1, true, false, true).timeout
			_reward_pick(maxi(min_rarity - 1, 0), step + 1, total, taken)
		else:
			_autosave("portal" if arena.rewards_done() else "reward"))
	cs.inventory_requested.connect(func(): _open_inventory_over(cs))
	_open_overlay(cs)
	cs.open(GameState.arena_index, min_rarity, "chest", 3, taken, step, total)


func _on_shop() -> void:
	var sh := ShopUI.new()
	sh.visit = _shop_visit            # misma visita (arena) = mismas ofertas y mismo contador de relanzamientos
	sh.closed.connect(func():
		if arena.phase == Arena.Phase.CLEARED:
			_autosave("portal" if arena.rewards_done() else "reward", true))
	_open_overlay(sh)
	sh.open(GameState.arena_index)


func _on_portal() -> void:
	if _transitioning:
		return
	if arena.kind == Scaling.KIND_BOSS and int(GameState.run_stats["bosses"]) >= 2 and not _victory_shown:
		_victory_shown = true
		_end_run(true, true)
		return
	_begin_arena(GameState.arena_index + 1)


# ------------------------------------------------------------------ fin de partida
func _on_player_died() -> void:
	if _end_pending or state != St.RUN:
		return
	_end_pending = true
	SaveSystem.clear_run()      # perder la partida la elimina: no se puede recuperar
	AudioManager.play_music("none")
	touch.release_all()
	Engine.time_scale = 0.35
	await get_tree().create_timer(1.6, true, false, true).timeout
	Engine.time_scale = 1.0
	_end_run(false, false)


func _end_run(victory: bool, can_continue: bool) -> void:
	var sm := GameState.end_run(victory)
	if sm.is_empty():
		return
	if can_continue:
		# la victoria permite seguir: reabrimos la partida tras mostrar el resumen
		pass
	state = St.ENDED
	touch.release_all()
	get_tree().paused = true
	var es := EndScreen.new()
	es.show_summary(sm, can_continue, {} if victory else {"left": GameState.ad_revives_left(), "max": GameState.MAX_AD_REVIVES})
	if not victory:
		_defeat_sm = sm
		_defeat_es = es
		es.revive_pressed.connect(_on_revive_pressed)
	es.retry_pressed.connect(func():
		_clear_defeat()
		es.queue_free()
		_restart_from_end())
	es.settings_pressed.connect(func(): _open_settings("game"))
	es.lobby_pressed.connect(func():
		_clear_defeat()
		es.queue_free()
		get_tree().paused = false
		_enter_lobby())
	es.continue_pressed.connect(func():
		es.queue_free()
		_continue_after_victory())
	_ov_root().add_child(es)
	_overlays.append(es)
	es.tree_exited.connect(func(): _overlays.erase(es))
	if victory:
		AudioManager.sfx("victory")
	else:
		AudioManager.sfx("defeat")


# ------------------------------------------------------------------ reanimación con anuncio recompensado
var _defeat_sm: Dictionary = {}
var _defeat_es: EndScreen
var _revive_busy := false
var _death_seq := 0


## Botón «REVIVIR — VER ANUNCIO DE 30 S». La oportunidad solo se consume si el servicio de anuncios confirma COMPLETED.
func _on_revive_pressed() -> void:
	if _revive_busy or _defeat_es == null or _defeat_sm.is_empty() or GameState.ad_revives_left() <= 0:
		return
	_revive_busy = true
	var es := _defeat_es
	var seq := _death_seq
	es.set_revive_busy(true)
	es.set_revive_message("")
	var r: int = await RewardedAdService.show_rewarded(RewardedAdService.PLACEMENT_REVIVE, _ov_root())
	_revive_busy = false
	if seq != _death_seq or _defeat_es != es or not is_instance_valid(es):
		return                                      # la pantalla de derrota ya no es la misma: no se concede nada
	if r == RewardedAdService.Result.COMPLETED:
		_do_revive()
		return
	es.set_revive_busy(false)
	match r:
		RewardedAdService.Result.CANCELLED:
			es.set_revive_message("Anuncio cancelado. No se ha consumido ninguna reanimación.")
		RewardedAdService.Result.UNAVAILABLE:
			es.set_revive_message("Anuncio no disponible. Inténtalo más tarde.")
		_:
			es.set_revive_message("Error al cargar o reproducir el anuncio. No se ha consumido ninguna reanimación.")


func _clear_defeat() -> void:
	_defeat_sm = {}
	_defeat_es = null
	_death_seq += 1


func _do_revive() -> void:
	if _defeat_sm.is_empty() or GameState.player == null:
		return
	if not GameState.consume_ad_revive():
		return
	var sm := _defeat_sm
	_defeat_sm = {}                                 # un solo uso por muerte (eventos duplicados no reaniman dos veces)
	var es := _defeat_es
	_defeat_es = null
	_death_seq += 1
	GameState.resume_after_defeat(sm)
	if is_instance_valid(es):
		es.queue_free()
	_overlays.erase(es)
	state = St.RUN
	_end_pending = false
	Engine.time_scale = 1.0
	get_tree().paused = false
	player.revive_from_defeat(0.5, 3.0)
	AudioManager.play_music("combat")
	GameState.toast_msg("¡REANIMADO! Quedan %d/%d reanimaciones" % [GameState.ad_revives_left(), GameState.MAX_AD_REVIVES], Color(0.5, 0.9, 1.0))
	var stage := "fight"
	if arena != null and arena.phase == Arena.Phase.CLEARED:
		stage = "portal" if arena.rewards_done() else "reward"
	_autosave(stage, true)


func _restart_from_end() -> void:
	get_tree().paused = false
	await _fade_to(1.0, 0.25)
	_start_run()


func _continue_after_victory() -> void:
	# sigue la partida (modo infinito): se reabre el run sin perder el build
	GameState.in_run = true
	state = St.RUN
	get_tree().paused = false
	_begin_arena(GameState.arena_index + 1)


func _back_to_lobby() -> void:
	get_tree().paused = false
	await _enter_lobby()


# ------------------------------------------------------------------ pausa
## Abre/cierra el menú de pausa (en el Vestíbulo y durante una run). Si hay un submenú abierto encima, lo cierra primero.
func _toggle_pause() -> void:
	if _transitioning or (state != St.RUN and state != St.LOBBY):
		return
	if _pause_menu != null and is_instance_valid(_pause_menu):
		if not _overlays.is_empty() and _overlays.back() != _pause_menu:
			pad_nav.press_cancel()          # cierra el submenú de arriba (ajustes, inventario…)
		else:
			_resume()
		return
	if not _overlays.is_empty():
		return
	_pause_menu = PauseMenu.new()
	_pause_menu.context = "run" if state == St.RUN else "lobby"
	_pause_menu.can_save = _can_save()
	_pause_menu.resume_pressed.connect(_resume)
	_pause_menu.settings_pressed.connect(_open_settings)
	_pause_menu.controls_pressed.connect(_open_controls)
	_pause_menu.inventory_pressed.connect(_open_inventory)
	_pause_menu.save_pressed.connect(_save_game)
	_pause_menu.leave_save_pressed.connect(_save_and_leave)
	_pause_menu.abandon_pressed.connect(func():
		_resume()
		_end_run(false, false))
	_pause_menu.records_pressed.connect(func(): _open_overlay(StatsPanel.new()))
	_pause_menu.meta_pressed.connect(func():
		var m := MetaScreen.new()
		m.closed.connect(_lobby_changed)
		_open_overlay(m))
	_pause_menu.continue_saved_pressed.connect(func():
		_resume()
		_on_continue())
	_pause_menu.quit_game_pressed.connect(func(): get_tree().quit())
	_open_overlay(_pause_menu)


## ¿Es seguro guardar ahora? (en una run, sin transición ni derrota en curso)
func _can_save() -> bool:
	return state == St.RUN and GameState.in_run and not _end_pending and not _transitioning


## Guarda la partida donde está. En combate se conserva el último punto de control (inicio de la arena);
## con la arena superada se guarda justo aquí (cofre/portal). Devuelve true si quedó guardada.
func _save_game() -> bool:
	if not _can_save():
		notify("No se puede guardar en este momento.", false)
		return false
	var msg := "Partida guardada"
	if arena.phase == Arena.Phase.CLEARED:
		if not _autosave("portal" if arena.rewards_done() else "reward", true):
			return false         # SaveSystem ya mostró el error
	elif not SaveSystem.has_valid_run():
		if not _autosave("fight", true):
			return false
		msg = "Partida guardada. Se retomará al inicio de esta arena."
	else:
		msg = "Partida guardada. Se retomará al inicio de esta arena."
		GameState.flush_stats()
		SaveSystem.save_now()
	_last_save_msg = msg
	notify(msg, true)
	return true


var _last_save_msg := ""


## Guarda y vuelve al Vestíbulo; si no se pudo guardar, se queda en la partida para no perderla.
func _save_and_leave() -> void:
	if not _can_save():
		return
	_resume()
	if not _save_game():
		return
	var msg := _last_save_msg + " Continúa desde el portal CONTINUAR."
	await _back_to_lobby()
	notify(msg, true)


func _resume() -> void:
	if _pause_menu != null and is_instance_valid(_pause_menu):
		_pause_menu.queue_free()
	_pause_menu = null


## Mandos: detección, modo de control (táctil ↔ mando) y navegación de menús.
func _build_pad() -> void:
	pad = PadInput.new()
	pad.name = "PadInput"
	add_child(pad)
	pad_nav = PadNav.new()
	pad_nav.name = "PadNav"
	pad_nav.main = self
	add_child(pad_nav)
	pad.mode_changed.connect(_on_pad_mode)
	pad.bindings_changed.connect(hud.refresh_pad_hints)
	pad.devices_changed.connect(hud.refresh_pad_hints)
	_on_pad_mode(PadInput.pad_mode)


func _on_pad_mode(on: bool) -> void:
	# con mando: fuera los controles táctiles (joystick y botones) para aprovechar toda la pantalla
	touch.set_suppressed(on)
	hud.refresh_pad_hints()
	if on and state == St.RUN and hud.visible:
		GameState.toast_msg("Modo mando: controles táctiles ocultos", UIKit.GOOD)
	elif not on and state == St.RUN and hud.visible:
		GameState.toast_msg("Controles táctiles activados", UIKit.GOOD)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory") and not event.is_echo() and state == St.RUN and not _transitioning:
		var open_inv: Control = null
		for o in _overlays:
			if o is InventoryUI:
				open_inv = o
		if open_inv != null:
			open_inv.call("_close")
		else:
			_open_inventory()
		return
	if event.is_action_pressed("pause"):
		_toggle_pause()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_toggle_pause()
	elif what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if state == St.RUN and _pause_menu == null and _overlays.is_empty():
			_toggle_pause()
