class_name HUD
extends Control
## HUD de partida: vida/escudo/energía, nivel, monedas, objetivo, barra de jefe, avisos,
## sinergias y medidor de potencia del build, destellos de daño y botón de pausa.

signal pause_pressed
signal inventory_pressed

var _hp_bar: ProgressBar
var _hp_label: Label
var _shield_bar: ProgressBar
var _en_bar: ProgressBar
var _xp_bar: ProgressBar
var _lvl_label: Label
var _coins_label: Label
var _kills_label: Label
var _obj_label: Label
var _obj_bar: ProgressBar
var _boss_box: VBoxContainer
var _boss_name: Label
var _boss_bar: ProgressBar
var _toasts: VBoxContainer
var _prompt: Label
var _pad_hints: Label
var _power_label: Label
var _inv_btn: Button
var _power_bar: ProgressBar
var _syn_box: HBoxContainer
var _fps_label: Label
var _damage_flash: ColorRect
var _synergy_flash: ColorRect
var _banner: Label
var _arena_label: Label
var _combo_label: Label
var _last_hp := -1.0
var _low_hp_t := 0.0
var _toast_queue: Array = []
var _toast_cd := 0.0
var _tier := -1
var _debug_label: Label
var _top_bg: PanelContainer

const TIERS := [
	{"name": "Pasante", "at": 0.0, "col": Color(0.78, 0.8, 0.85)},
	{"name": "Asociado", "at": 1.6, "col": Color(0.3, 0.62, 1.0)},
	{"name": "Socio", "at": 2.8, "col": Color(0.72, 0.38, 1.0)},
	{"name": "Socio Director", "at": 4.8, "col": Color(1.0, 0.7, 0.15)},
	{"name": "¡LEYENDA DEL FORO!", "at": 8.0, "col": Color(1.0, 0.35, 0.3)},
]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	GameState.player_hp_changed.connect(_on_hp)
	GameState.energy_changed.connect(_on_energy)
	GameState.xp_changed.connect(_on_xp)
	GameState.coins_changed.connect(func(v): _coins_label.text = "$ %d" % v)
	GameState.kills_changed.connect(func(v): _kills_label.text = "Bajas: %d" % v)
	GameState.toast.connect(_queue_toast)
	GameState.objective_changed.connect(_on_objective)
	GameState.boss_bar.connect(_on_boss)
	GameState.arena_started.connect(_on_arena)
	GameState.level_up.connect(func(l): _show_banner("¡NIVEL DE CASO %d!" % (l + 1), UIKit.ACCENT))
	GameState.build.synergy_unlocked.connect(_on_synergy)
	GameState.build.changed.connect(_refresh_build)
	_refresh_build()


func _build() -> void:
	# --- vida / energía (arriba-izquierda) ---
	var tl := VBoxContainer.new()
	tl.position = Vector2(20, 14)
	tl.add_theme_constant_override("separation", 5)
	add_child(tl)
	_hp_bar = _bar(Color(0.85, 0.2, 0.28), Vector2(340, 30))
	tl.add_child(_hp_bar)
	_hp_label = UIKit.label("100 / 100", 20, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER)
	_hp_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hp_bar.add_child(_hp_label)
	_shield_bar = _bar(Color(0.4, 0.75, 1.0), Vector2(340, 10))
	tl.add_child(_shield_bar)
	_en_bar = _bar(Color(1.0, 0.78, 0.2), Vector2(340, 16))
	tl.add_child(_en_bar)
	var xrow := HBoxContainer.new()
	tl.add_child(xrow)
	_lvl_label = UIKit.label("Caso 1", 20, UIKit.ACCENT)
	xrow.add_child(_lvl_label)
	_xp_bar = _bar(Color(0.5, 0.9, 0.6), Vector2(250, 12))
	_xp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	xrow.add_child(_xp_bar)
	var crow := HBoxContainer.new()
	tl.add_child(crow)
	_coins_label = UIKit.label("$ 0", 26, Color(1.0, 0.85, 0.3))
	crow.add_child(_coins_label)
	_kills_label = UIKit.label("Bajas: 0", 22, UIKit.TEXT_DIM)
	_kills_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	crow.add_child(_kills_label)
	_combo_label = UIKit.label("", 22, Color(1.0, 0.6, 0.3))
	tl.add_child(_combo_label)
	# --- objetivo (arriba-centro) ---
	# Panel oscuro detras del objetivo: se leia mal sobre fondos brillantes.
	var top_bg := PanelContainer.new()
	_top_bg = top_bg
	top_bg.add_theme_stylebox_override("panel", UIKit.style(Color(0.03, 0.04, 0.08, 0.62), Color(1, 1, 1, 0.08), 14, 1, 8))
	top_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_bg)
	UIKit.place(top_bg, 0.5, 0.0, -300, 8, 600, 0)
	top_bg.grow_vertical = Control.GROW_DIRECTION_END
	var top := VBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bg.add_child(top)
	_arena_label = UIKit.label("Arena 1", 22, UIKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	top.add_child(_arena_label)
	_obj_label = UIKit.label("", 24, UIKit.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	top.add_child(_obj_label)
	for l: Label in [_arena_label, _obj_label]:
		l.add_theme_constant_override("outline_size", 5)
	_obj_bar = _bar(Color(0.4, 0.9, 0.55), Vector2(420, 10))
	_obj_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	top.add_child(_obj_bar)
	_boss_box = VBoxContainer.new()
	_boss_box.visible = false
	top.add_child(_boss_box)
	_boss_name = UIKit.label("", 26, Color(1.0, 0.5, 0.4), HORIZONTAL_ALIGNMENT_CENTER)
	_boss_box.add_child(_boss_name)
	_boss_bar = _bar(Color(0.9, 0.2, 0.2), Vector2(560, 22))
	_boss_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_boss_box.add_child(_boss_bar)
	# --- derecha: pausa, fps, potencia ---
	var pb := UIKit.button("II", Vector2(72, 72), 30)
	pb.name = "PauseButton"
	pb.pressed.connect(func(): pause_pressed.emit())
	add_child(pb)
	UIKit.place(pb, 1.0, 0.0, -92, 14, 72, 72)
	_inv_btn = UIKit.button("INVENTARIO\n0/30", Vector2(190, 72), 20)
	_inv_btn.name = "InventoryButton"
	_inv_btn.icon = _briefcase_icon()
	_inv_btn.expand_icon = false
	_inv_btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_inv_btn.add_theme_constant_override("h_separation", 8)
	_inv_btn.pressed.connect(func(): inventory_pressed.emit())
	add_child(_inv_btn)
	UIKit.place(_inv_btn, 1.0, 0.0, -302, 14, 190, 72)
	_fps_label = UIKit.label("", 18, Color(0.7, 1, 0.7), HORIZONTAL_ALIGNMENT_RIGHT)
	add_child(_fps_label)
	UIKit.place(_fps_label, 1.0, 0.0, -300, 92, 280, 24)
	var pw := VBoxContainer.new()
	pw.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(pw)
	UIKit.place(pw, 1.0, 0.0, -532, 14, 220, 140)
	_power_label = UIKit.label("Build: Pasante", 20, UIKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	pw.add_child(_power_label)
	_power_bar = _bar(Color(1.0, 0.7, 0.2), Vector2(220, 10))
	pw.add_child(_power_bar)
	_syn_box = HBoxContainer.new()
	_syn_box.alignment = BoxContainer.ALIGNMENT_END
	pw.add_child(_syn_box)
	# --- avisos ---
	_toasts = VBoxContainer.new()
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toasts)
	UIKit.place(_toasts, 0.5, 0.5, -300, -210, 600, 200)
	_prompt = UIKit.label("", 26, Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER)
	add_child(_prompt)
	UIKit.place(_prompt, 0.5, 1.0, -300, -230, 600, 40)
	_pad_hints = UIKit.label("", 19, UIKit.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	_pad_hints.visible = false
	add_child(_pad_hints)
	UIKit.place(_pad_hints, 0.5, 1.0, -560, -44, 1120, 30)
	_banner = UIKit.title("", 64)
	_banner.modulate.a = 0.0
	add_child(_banner)
	UIKit.place(_banner, 0.5, 0.5, -500, -90, 1000, 100)
	# destellos de pantalla
	_damage_flash = ColorRect.new()
	_damage_flash.color = Color(1, 0.1, 0.1, 0.0)
	_damage_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_damage_flash)
	_synergy_flash = ColorRect.new()
	_synergy_flash.color = Color(1, 0.85, 0.3, 0.0)
	_synergy_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_synergy_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_synergy_flash)
	_debug_label = UIKit.label("", 16, Color(0.8, 1, 0.8))
	_debug_label.position = Vector2(20, 300)
	add_child(_debug_label)


func _bar(col: Color, min_size: Vector2) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = min_size
	b.min_value = 0.0
	b.max_value = 1.0
	b.step = 0.0
	b.value = 1.0
	b.add_theme_stylebox_override("background", UIKit.style(Color(0.05, 0.05, 0.09, 0.8), Color(1, 1, 1, 0.12), 6, 1, 0))
	b.add_theme_stylebox_override("fill", UIKit.style(col, Color(0, 0, 0, 0), 6, 0, 0))
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func _on_hp(hp: float, max_hp: float, shield: float, shield_max: float) -> void:
	_hp_bar.value = clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)
	_hp_label.text = "%d / %d" % [int(ceil(hp)), int(max_hp)]
	_shield_bar.visible = shield_max > 0.0 or shield > 0.0
	_shield_bar.value = clampf(shield / maxf(shield_max, 40.0 if shield_max <= 0.0 else 1.0), 0.0, 1.0)
	if _last_hp >= 0.0 and hp < _last_hp - 0.5:
		_damage_flash.color.a = clampf(0.18 + (_last_hp - hp) / maxf(max_hp, 1.0), 0.0, 0.5)
	_last_hp = hp
	_low_hp_t = 1.0 if hp / maxf(max_hp, 1.0) < 0.25 and hp > 0.0 else 0.0


func _on_energy(v: float, m: float) -> void:
	_en_bar.value = clampf(v / maxf(m, 1.0), 0.0, 1.0)


func _on_xp(xp: int, to_next: int, level: int) -> void:
	_xp_bar.value = clampf(float(xp) / maxf(float(to_next), 1.0), 0.0, 1.0)
	_lvl_label.text = "Caso %d" % (level + 1)


## En la Sala Central no hay objetivo ni jefe: se oculta el panel superior.
func set_lobby(on: bool) -> void:
	if _top_bg != null:
		_top_bg.visible = not on
	_boss_box.visible = false
	_inv_btn.visible = not on


func _on_objective(text: String, prog: float) -> void:
	_obj_label.text = text
	_obj_bar.value = prog


func _on_boss(vis: bool, boss_name: String, hp: float, max_hp: float) -> void:
	_boss_box.visible = vis
	_boss_name.text = boss_name
	_boss_bar.value = clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)


func _on_arena(idx: int, kind: String) -> void:
	_arena_label.text = "Arena %d · Ciclo %d" % [idx + 1, Scaling.cycle_of(idx) + 1]
	_boss_box.visible = false


func _queue_toast(text: String, color: Color) -> void:
	if _toast_queue.size() > 5:
		_toast_queue.pop_front()
	_toast_queue.append([text, color])


func _show_toast(text: String, color: Color) -> void:
	var l := UIKit.label(text, 30, color, HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_constant_override("outline_size", 8)
	l.modulate.a = 0.0
	_toasts.add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "modulate:a", 1.0, 0.18)
	tw.tween_interval(1.6)
	tw.tween_property(l, "modulate:a", 0.0, 0.5)
	tw.tween_callback(l.queue_free)
	while _toasts.get_child_count() > 3:
		_toasts.get_child(0).queue_free()
		break


func _show_banner(text: String, color: Color) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	_banner.modulate.a = 1.0
	_banner.scale = Vector2(1.3, 1.3)
	_banner.pivot_offset = Vector2(500, 50)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_banner, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_banner, "modulate:a", 0.0, 0.6).set_delay(1.4)


func _on_synergy(syn: Dictionary) -> void:
	_show_banner("¡SINERGIA: %s!" % String(syn.get("name", "")).to_upper(), Color(1.0, 0.85, 0.3))
	_synergy_flash.color = Color(1.0, 0.85, 0.3, 0.45)
	AudioManager.sfx("levelup", -2.0)
	GameState.toast_msg(String(syn.get("desc", "")), Color(1.0, 0.95, 0.7))


## Controles de la interfaz que no deben iniciar el joystick ni la cámara al tocarlos.
func ui_blockers() -> Array:
	var out: Array = []
	for n in ["InventoryButton", "PauseButton"]:
		var c := get_node_or_null(n)
		if c != null:
			out.append(c)
	return out


## Icono de maletín dibujado por código (32x32).
static func _briefcase_icon() -> ImageTexture:
	var im := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var body := Color(0.78, 0.5, 0.2)
	var dark := Color(0.35, 0.2, 0.08)
	im.fill_rect(Rect2i(11, 4, 10, 3), dark)       # asa
	im.fill_rect(Rect2i(11, 4, 2, 8), dark)
	im.fill_rect(Rect2i(19, 4, 2, 8), dark)
	im.fill_rect(Rect2i(3, 10, 26, 18), dark)      # cuerpo
	im.fill_rect(Rect2i(4, 11, 24, 16), body)
	im.fill_rect(Rect2i(4, 17, 24, 2), dark)       # banda
	im.fill_rect(Rect2i(14, 15, 4, 6), Color(1.0, 0.85, 0.3))   # cierre
	return ImageTexture.create_from_image(im)


## Indicaciones de botones con los nombres del mando conectado (Xbox: RT/A/B… · PlayStation: R2/Cruz/Círculo…).
func refresh_pad_hints() -> void:
	_pad_hints.visible = PadInput.pad_mode
	if not PadInput.pad_mode or PadInput.inst == null:
		return
	var parts: Array = []
	for a in ["attack", "skill1", "dodge", "jump", "interact", "inventory"]:
		parts.append("%s %s" % [PadInput.label(a), String(PadInput.ACTION_LABEL[a]).split(" (")[0]])
	_pad_hints.text = "  ·  ".join(parts)


func _refresh_build() -> void:
	var b: Build = GameState.build
	var pr := b.power_rating()
	_inv_btn.text = "INVENTARIO\n%d/%d" % [b.type_count(), Build.MAX_TYPES]
	_inv_btn.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4) if b.is_full() else UIKit.TEXT)
	var ti := 0
	for i in TIERS.size():
		if pr >= float(TIERS[i]["at"]):
			ti = i
	var tier: Dictionary = TIERS[ti]
	_power_label.text = "Build: %s" % tier["name"]
	_power_label.add_theme_color_override("font_color", tier["col"])
	var lo := float(tier["at"])
	var hi := float(TIERS[ti + 1]["at"]) if ti + 1 < TIERS.size() else lo + 1.0
	_power_bar.value = clampf((pr - lo) / maxf(hi - lo, 0.01), 0.0, 1.0)
	_power_bar.add_theme_stylebox_override("fill", UIKit.style(tier["col"], Color(0, 0, 0, 0), 6, 0, 0))
	if ti > _tier and _tier >= 0 and ti >= 2:
		_show_banner("¡BUILD: %s!" % String(tier["name"]).to_upper(), tier["col"])
		_synergy_flash.color = Color(tier["col"].r, tier["col"].g, tier["col"].b, 0.35)
	_tier = ti
	for c in _syn_box.get_children():
		c.queue_free()
	for sid in b.active_synergies:
		var l := UIKit.label("★", 24, Color(1.0, 0.85, 0.3))
		l.tooltip_text = String(sid)
		_syn_box.add_child(l)


func _process(delta: float) -> void:
	# destellos
	if _damage_flash.color.a > 0.0:
		_damage_flash.color.a = maxf(0.0, _damage_flash.color.a - delta * 1.6)
	if _low_hp_t > 0.0 and _damage_flash.color.a < 0.12:
		_damage_flash.color.a = 0.06 + 0.06 * sin(Time.get_ticks_msec() * 0.008)
	if _synergy_flash.color.a > 0.0:
		_synergy_flash.color.a = maxf(0.0, _synergy_flash.color.a - delta * 0.9)
	# avisos en cola
	_toast_cd -= delta
	if _toast_cd <= 0.0 and not _toast_queue.is_empty():
		var t: Array = _toast_queue.pop_front()
		_show_toast(t[0], t[1])
		_toast_cd = 0.35
	# prompt de interacción
	var pl = GameState.player
	if pl != null and pl.interact_target != null:
		var key_txt := String(pl.interact_target.action_text)
		if PadInput.pad_mode:
			key_txt = PadInput.label("interact")      # nombre del botón según el mando (X / Cuadrado…)
		_prompt.text = "[ %s ]  %s" % [key_txt, String(pl.interact_target.prompt)]
	else:
		_prompt.text = ""
	# racha
	if GameState.kill_streak >= 3:
		_combo_label.text = "Racha x%d" % GameState.kill_streak
	else:
		_combo_label.text = ""
	# fps / depuración
	if bool(SaveSystem.setting("show_fps")) or Config.dev_show_debug:
		var txt := "%d FPS" % Engine.get_frames_per_second()
		_fps_label.text = txt
	else:
		_fps_label.text = ""
	if Config.dev_show_debug:
		var ne := Combat.arena_enemies().size()
		var pc: int = GameState.projectiles.count() if GameState.projectiles != null else 0
		_debug_label.text = "Enemigos: %d  Proyectiles: %d\nDraw calls: %d  Objetos: %d\nMem: %.0f MB  Escala 3D: %.2f" % [
			ne, pc, int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)),
			int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)),
			OS.get_static_memory_usage() / 1048576.0, get_viewport().scaling_3d_scale]
	else:
		_debug_label.text = ""
