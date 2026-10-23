extends Node
## Orquestador del juego: crea el mundo 3D, la UI y controla el flujo
## menú → partida (arenas, cofres, tienda, portales) → derrota/victoria → menú.
##
## process_mode = ALWAYS (ver main.tscn) para poder gestionar pausas; el mundo 3D se marca PAUSABLE.

enum St { MENU, RUN, ENDED, LOBBY }

var state := St.MENU
var world: Node3D
var fx: FX
var projectiles: Projectiles
var cam: CameraRig
var player: Player
var arena: Arena
var stage: Node3D
var stage_rig: Rig
var stage_pivot: Node3D
var lobby: Lobby

var hud_layer: CanvasLayer
var overlay_layer: CanvasLayer
var fade_layer: CanvasLayer
var hud: HUD
var touch: TouchControls
var menu: MainMenu
var fade: ColorRect
var banner_panel: PanelContainer
var banner: Label
var _banner_tw: Tween

var _overlays: Array = []
var _pause_menu: PauseMenu
var _transitioning := false
var _victory_shown := false
var _end_pending := false
var _menu_t := 0.0
var _selftest := false


func _ready() -> void:
	GameState.main = self
	get_tree().set_auto_accept_quit(true)
	DisplayServer.screen_set_keep_on(true)
	Config.dev_mode = bool(SaveSystem.setting("dev_unlocked"))
	_build_world()
	_build_ui()
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
	if Config.cmd_flag("--flowtest"):
		var ft := load("res://tests/flowtest.gd")
		if ft != null:
			var fnode: Node = ft.new()
			fnode.name = "FlowTest"
			add_child(fnode)
			fnode.set("main", self)
		return
	_show_menu()
	if SaveSystem.last_load_note != "":
		notify(SaveSystem.last_load_note, false)


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
	theme_root.add_child(hud)
	touch = TouchControls.new()
	touch.visible = false
	theme_root.add_child(touch)
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
		if _overlays.is_empty() and state != St.ENDED:
			get_tree().paused = false)


func _fade_to(a: float, t := 0.25) -> void:
	var tw := create_tween()
	tw.tween_property(fade, "color:a", a, t)
	await tw.finished


# ------------------------------------------------------------------ menú
func _build_stage() -> void:
	stage = Node3D.new()
	stage.name = "MenuStage"
	world.add_child(stage)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.1, 0.18)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.65, 0.85)
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	stage.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	sun.light_energy = 1.2
	sun.light_color = Color(1.0, 0.92, 0.8)
	stage.add_child(sun)
	var rim := OmniLight3D.new()
	rim.position = Vector3(-2.5, 2.5, -2.0)
	rim.light_color = Color(0.5, 0.6, 1.0)
	rim.light_energy = 2.0
	rim.omni_range = 9.0
	stage.add_child(rim)
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 2.4
	cm.bottom_radius = 2.6
	cm.height = 0.3
	disc.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.2, 0.22, 0.3)
	m.roughness = 0.6
	disc.material_override = m
	disc.position.y = -0.15
	stage.add_child(disc)
	stage_pivot = Node3D.new()
	stage.add_child(stage_pivot)
	stage_rig = ModelFactory.build_lawyer()
	stage_pivot.add_child(stage_rig)
	stage_pivot.rotation.y = 0.5


func _show_menu() -> void:
	_cleanup_lobby()
	state = St.MENU
	get_tree().paused = false
	GameState.in_run = false
	if arena != null:
		arena._teardown()
		arena.phase = Arena.Phase.IDLE
	player.visible = false
	hud.visible = false
	touch.visible = false
	touch.release_all()
	if stage == null or not is_instance_valid(stage):
		_build_stage()
	cam.target = stage_pivot
	cam.distance = 4.0
	cam.pivot_height = 1.2
	cam.shoulder = -1.2
	cam.pitch = -0.12
	cam.yaw = 0.35
	cam.snap_to_target()
	Engine.time_scale = 1.0
	if menu != null and is_instance_valid(menu):
		menu.queue_free()
	menu = MainMenu.new()
	menu.play_pressed.connect(_on_play)
	menu.continue_pressed.connect(_on_continue)
	menu.lobby_pressed.connect(_enter_lobby)
	menu.meta_pressed.connect(func(): _open_overlay(_make_meta()))
	menu.settings_pressed.connect(func(): _open_settings())
	menu.quit_pressed.connect(func(): get_tree().quit())
	_ov_root().add_child(menu)
	AudioManager.play_music("menu")
	_fade_to(0.0, 0.3)


func _make_meta() -> MetaScreen:
	var m := MetaScreen.new()
	m.closed.connect(func():
		if menu != null:
			menu.queue_free()
			_show_menu())
	return m


func _open_settings() -> void:
	var s := SettingsMenu.new()
	s.edit_controls_requested.connect(_begin_edit_controls)
	s.dev_tools_requested.connect(_open_dev_tools)
	_open_overlay(s)


func _open_dev_tools() -> void:
	var d := DevTools.new()
	d.jump_to_arena.connect(func(i): if state == St.RUN: _begin_arena(i))
	_open_overlay(d)


func _begin_edit_controls() -> void:
	# oculta menús/HUD y deja solo los controles editables
	if menu != null:
		menu.visible = false
	if _pause_menu != null and is_instance_valid(_pause_menu):
		_pause_menu.visible = false
	hud.visible = false
	touch.visible = true
	touch.begin_edit()
	get_tree().paused = true
	if not touch.edit_finished.is_connected(_on_edit_done):
		touch.edit_finished.connect(_on_edit_done, CONNECT_ONE_SHOT)


func _on_edit_done() -> void:
	if state == St.MENU:
		touch.visible = false
		if menu != null:
			menu.visible = true
		get_tree().paused = _overlays.size() > 0
	else:
		hud.visible = true
		if _pause_menu != null and is_instance_valid(_pause_menu):
			_pause_menu.visible = true


func _process(delta: float) -> void:
	if state == St.MENU and stage_pivot != null and is_instance_valid(stage_pivot):
		_menu_t += delta
		cam.yaw += delta * 0.18
		if stage_rig != null and fmod(_menu_t, 5.0) < delta:
			stage_rig.play("swing", 0.6)


# ------------------------------------------------------------------ Sala Central
func _enter_lobby() -> void:
	if _transitioning:
		return
	_transitioning = true
	await _fade_to(1.0, 0.25)
	if menu != null and is_instance_valid(menu):
		menu.queue_free()
	menu = null
	if stage != null and is_instance_valid(stage):
		world.remove_child(stage)
		stage.queue_free()
		stage = null
		stage_rig = null
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
	player.visible = true
	GameState.prepare_practice()
	player.teleport_to(lobby.spawn_position())
	player.iframes = 1.0
	cam.target = player
	cam.distance = 6.4
	cam.pivot_height = 1.55
	cam.shoulder = 0.55
	cam.pitch = -0.4
	cam.yaw = 0.0
	cam.snap_to_target()
	hud.visible = true
	hud.set_lobby(true)
	touch.visible = true
	Engine.time_scale = 1.0
	AudioManager.play_music("menu")
	await _fade_to(0.0, 0.3)
	_transitioning = false
	if SaveSystem.last_load_note != "":
		notify(SaveSystem.last_load_note, false)
		SaveSystem.last_load_note = ""
	else:
		notify("Sala Central: prepara tu equipo y entra por un portal", true)


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


func _lobby_to_menu() -> void:
	if _transitioning or state != St.LOBBY:
		return
	await _fade_to(1.0, 0.25)
	player.visible = false
	hud.visible = false
	touch.visible = false
	_show_menu()


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
		var ztw := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		ztw.tween_property(cam, "distance", 2.6, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await _fade_to(1.0, 0.3)
	_cleanup_lobby()
	if menu != null:
		menu.queue_free()
		menu = null
	if stage != null and is_instance_valid(stage):
		world.remove_child(stage)
		stage.queue_free()
		stage = null
		stage_rig = null
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
	cam.target = player
	cam.distance = 6.4
	cam.pivot_height = 1.55
	cam.shoulder = 0.55
	cam.pitch = -0.42
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


func _begin_arena(idx: int, instant := false, resume: Dictionary = {}) -> void:
	_transitioning = true
	if not instant:
		await _fade_to(1.0, 0.25)
	projectiles.clear_all()
	var restoring := not resume.is_empty()
	var stage_name := String(resume.get("stage", "fight"))
	var pos := arena.start(idx, int(resume["arena_seed"]) if restoring else -1)
	if restoring and stage_name != "fight":
		# la arena ya estaba superada: reaparecen el cofre y el portal tal como estaban
		arena.restore_cleared(stage_name == "portal")
		var pp: Array = resume["player_pos"]
		pos = Vector3(clampf(float(pp[0]), -arena.half + 1.5, arena.half - 1.5), 0.3, clampf(float(pp[2]), -arena.half + 1.5, arena.half - 1.5))
	player.teleport_to(pos)
	player.iframes = maxf(player.iframes, 1.2)
	cam.yaw = 0.0
	cam.snap_to_target()
	if idx > 0 and Scaling.zone_pos(idx) == 0 and (not restoring or stage_name == "fight"):
		GameState.toast_msg("Ciclo %d · los enemigos siguen endureciéndose poco a poco" % (Scaling.cycle_of(idx) + 1), Color(1.0, 0.4, 0.3))
	AudioManager.play_music("combat")
	await _fade_to(0.0, 0.3)
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


func _on_chest_opened(min_rarity: int) -> void:
	await get_tree().create_timer(0.5).timeout
	_open_cards(min_rarity, arena.kind == Scaling.KIND_BOSS)


func _open_cards(min_rarity: int, second: bool) -> void:
	var cs := CardSelect.new()
	cs.closed.connect(func():
		if second:
			await get_tree().create_timer(0.1).timeout
			_open_cards(maxi(min_rarity - 1, 0), false)
		else:
			_autosave("portal"))
	_open_overlay(cs)
	cs.open(GameState.arena_index, min_rarity, "chest")


func _on_shop() -> void:
	var sh := ShopUI.new()
	sh.closed.connect(func():
		if arena.phase == Arena.Phase.CLEARED:
			_autosave("portal" if arena.chest_taken else "reward", true))
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
	es.show_summary(sm, can_continue)
	es.retry_pressed.connect(func():
		es.queue_free()
		_restart_from_end())
	es.menu_pressed.connect(func():
		es.queue_free()
		_back_to_menu())
	es.lobby_pressed.connect(func():
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


func _back_to_menu() -> void:
	get_tree().paused = false
	await _fade_to(1.0, 0.25)
	_show_menu()


# ------------------------------------------------------------------ pausa
func _toggle_pause() -> void:
	if state == St.LOBBY:
		if _overlays.is_empty():
			_lobby_to_menu()
		return
	if state != St.RUN or _transitioning:
		return
	if _pause_menu != null and is_instance_valid(_pause_menu):
		_resume()
		return
	if not _overlays.is_empty():
		return
	_pause_menu = PauseMenu.new()
	_pause_menu.resume_pressed.connect(_resume)
	_pause_menu.settings_pressed.connect(_open_settings)
	_pause_menu.save_quit_pressed.connect(_save_and_exit)
	_pause_menu.quit_pressed.connect(func():
		_resume()
		_end_run(false, false))
	_open_overlay(_pause_menu)


## Guarda y vuelve al menú. En combate se conserva el último punto de control (inicio de la arena);
## con la arena superada se guarda justo aquí (cofre/portal).
func _save_and_exit() -> void:
	if state != St.RUN or _transitioning:
		return
	var msg := "Partida guardada. Puedes continuarla desde el menú."
	_resume()
	if arena.phase == Arena.Phase.CLEARED:
		if not _autosave("portal" if arena.chest_taken else "reward", true):
			return        # SaveSystem ya mostró el error; no se sale para no perder la partida
	elif not SaveSystem.has_valid_run():
		if not _autosave("fight", true):
			return
	else:
		msg = "Partida guardada. Se retomará al inicio de esta arena."
		GameState.flush_stats()
		SaveSystem.save_now()
	await _back_to_menu()
	notify(msg, true)


func _resume() -> void:
	if _pause_menu != null and is_instance_valid(_pause_menu):
		_pause_menu.queue_free()
	_pause_menu = null


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_toggle_pause()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_toggle_pause()
	elif what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if state == St.RUN and _pause_menu == null and _overlays.is_empty():
			_toggle_pause()
