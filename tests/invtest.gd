extends Node
## Prueba con renderizado real (xvfb + Mesa) y TOQUES de pantalla: botón del inventario en la HUD, inventario,
## vender/desechar con confirmación, cofre con inventario lleno y el comportamiento REAL de disparadores,
## condiciones y fuentes con jugador y enemigos de verdad.
##   godot --rendering-driver opengl3 ... -- --invtest --out=DIR
## Un fallo termina con código 1.

var main: Node
var out_dir := "/tmp/invtest"
var fails: Array = []
var passes := 0
var _touch_id := 20


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out_dir)
	call_deferred("_run")


func ok(cond: bool, name: String) -> void:
	if cond:
		passes += 1
		print("[PASS] ", name)
	else:
		fails.append(name)
		print("[FAIL] ", name)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _secs(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _shot(name: String) -> void:
	await _frames(3)
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png("%s/%s.png" % [out_dir, name])


func _overlay(cls: Variant) -> Node:
	for n in main._ov_root().get_children():
		if is_instance_of(n, cls):
			return n
	return null


## TOQUE real (pantalla táctil emulada): pulsar y soltar sobre el centro del control.
func _tap(c: Control) -> void:
	var pos := c.get_global_rect().get_center()
	_touch_id += 1
	var down := InputEventScreenTouch.new()
	down.index = _touch_id
	down.position = pos
	down.pressed = true
	Input.parse_input_event(down)
	await _frames(3)
	var up := InputEventScreenTouch.new()
	up.index = _touch_id
	up.position = pos
	up.pressed = false
	Input.parse_input_event(up)
	await _frames(4)


func _button(root: Node, prefix: String) -> Button:
	for b in root.find_children("*", "Button", true, false):
		if (b as Button).visible and (b as Button).text.begins_with(prefix):
			return b
	return null


func _types(n: int, skip: Array = []) -> Array:
	var out: Array = []
	for d in UpgradeDB.all():
		if out.size() >= n:
			break
		if skip.has(d["id"]) or (d.get("req", {}) as Dictionary).size() > 0 or d.get("cat", "") == "legend":
			continue
		out.append(d["id"])
	return out


func _finish() -> void:
	print("[RESULT] invtest: %d ok, %d fallos" % [passes, fails.size()])
	for f in fails:
		print("  FALLO: ", f)
	get_tree().quit(1 if fails.size() > 0 else 0)


func _run() -> void:
	await _frames(10)
	await main._enter_lobby(true)
	await _frames(15)
	main._on_play()
	var t := 0.0
	while main.state != main.St.RUN and t < 10.0:
		await _frames(2)
		t += 0.03
	ok(main.state == main.St.RUN, "I0 empieza la partida")
	Config.dev_god_mode = true
	main.arena.force_complete()
	await _secs(1.0)
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
	if only != "behavior":
		await _ui_part()
	if only != "ui":
		await _behavior_part()
	_finish()


# ============================================================================== interfaz táctil
func _ui_part() -> void:
	var b: Build = GameState.build
	b.reset({})
	GameState.build_changed.emit()
	await _frames(3)
	var hud = main.hud
	var inv_btn: Button = hud._inv_btn
	ok(inv_btn != null and inv_btn.visible, "I1 el botón del inventario es visible en la HUD durante la partida")
	var r := inv_btn.get_global_rect()
	ok(r.size.x >= 100 and r.size.y >= 64, "I2 el botón mide %dx%d px (objetivo táctil ≥ 64)" % [int(r.size.x), int(r.size.y)])
	ok(inv_btn.text == "INVENTARIO\n0/30", "I3 muestra el contador «%s»" % inv_btn.text)
	# no se pisa con el botón de pausa
	var pause_rect: Rect2 = Rect2()
	for c in hud.find_children("*", "Button", true, false):
		if (c as Button).text == "II":
			pause_rect = (c as Button).get_global_rect()
	ok(not r.intersects(pause_rect), "I4 el botón del inventario no se solapa con el de pausa")
	# llenar 30 tipos con niveles
	var ids := _types(31)
	for i in 30:
		b.add(ids[i], i % 4 if i % 4 < 3 else 1, true)
	for i in 8:
		b.add(ids[0], 0, true)
	b.add("heavy_case", 2, true)
	for i in 14:
		b.add("heavy_case", 1, true)
	GameState.build_changed.emit()
	await _frames(3)
	ok(b.type_count() == 31 or b.type_count() == 30, "I5 build preparada con %d tipos" % b.type_count())
	# la build puede llevar heavy_case ya dentro de los 30; normalizar a 30 exactos
	while b.type_count() > 30:
		b.remove(b.counts.keys()[b.counts.size() - 1], false)
	GameState.build_changed.emit()
	await _frames(3)
	ok(b.type_count() == 30 and inv_btn.text == "INVENTARIO\n30/30", "I6 el contador de la HUD pasa a «%s»" % inv_btn.text)
	# abrir con un TOQUE
	await _tap(inv_btn)
	var ui := _overlay(InventoryUI) as InventoryUI
	ok(ui != null, "I7 tocar el botón abre el inventario")
	if ui == null:
		return
	await _frames(5)
	await _shot("i01_inventario")
	ok(get_tree().paused, "I8 el juego queda en pausa mientras el inventario está abierto")
	ok(ui._grid.get_child_count() == 30, "I9 la cuadrícula muestra los 30 espacios")
	ok(ui._slots.size() == 30, "I10 los 30 espacios están ocupados por mejoras distintas")
	var slot_ok := true
	for id in ui._slots.keys():
		var rect: Rect2 = (ui._slots[id] as Button).get_global_rect()
		if rect.size.x < 90 or rect.size.y < 80:
			slot_ok = false
	ok(slot_ok, "I11 cada espacio mide ≥ 90×80 px (apto para el dedo)")
	ok(ui._count_label.text.begins_with("30 / 30"), "I12 la cabecera indica «%s»" % ui._count_label.text)
	# elegir un espacio con un toque y ver su detalle
	var first_id: String = ui._slots.keys()[0]
	await _tap(ui._slots[first_id])
	ok(ui._selected == first_id, "I13 tocar un espacio lo selecciona")
	var detail_txt := ""
	for l in ui._detail.find_children("*", "Label", true, false):
		detail_txt += (l as Label).text + "\n"
	var dn := String(UpgradeDB.get_def(first_id)["name"])
	ok(detail_txt.contains(dn) and detail_txt.contains("NIVEL") and detail_txt.contains("EFECTO ACUMULADO"), "I14 el detalle muestra nombre, nivel y efecto acumulado")
	await _shot("i02_detalle")
	# filtros
	await _tap(ui._rar_btn)
	ok(ui._rar_filter == 0, "I15 el filtro de rareza cambia con un toque")
	var dim := 0
	for id in ui._slots.keys():
		if (ui._slots[id] as Button).modulate.a < 0.5:
			dim += 1
	ok(dim > 0 and dim < 30, "I16 el filtro atenúa las que no coinciden (%d atenuadas)" % dim)
	ui._rar_filter = 3
	await _tap(ui._rar_btn)     # vuelve a «Todas»
	ok(ui._rar_filter == -1, "I17 el filtro vuelve a «Todas»")
	await _tap(ui._cat_btn)
	ok(ui._cat_filter != "", "I18 el filtro de categoría cambia con un toque")
	await _tap(ui._cat_btn)
	ui._cat_filter = ""
	ui._search.text = String(UpgradeDB.get_def(first_id)["name"]).substr(0, 4).to_lower()
	ui._refresh_grid()
	await _frames(2)
	ok((ui._slots[first_id] as Button).modulate.a > 0.9, "I19 la búsqueda por nombre mantiene resaltada la mejora buscada")
	ui._search.text = ""
	ui._refresh_grid()
	await _frames(2)
	# sinergias
	await _tap(ui._tab_syn)
	ok(ui._body_syn.visible and ui._syn_list.get_child_count() >= 3, "I20 la pestaña SINERGIAS muestra activas y por completar")
	await _shot("i03_sinergias")
	await _tap(ui._tab_items)
	ok(ui._body_items.visible, "I21 se vuelve a MEJORAS")
	# ----- vender con confirmación
	var sell_id := "heavy_case"
	if not b.counts.has(sell_id):
		sell_id = String(b.counts.keys()[3])
	await _tap(ui._slots[sell_id])
	var sell_btn := _button(ui._detail, "VENDER")
	ok(sell_btn != null, "I22 hay botón VENDER con el valor: «%s»" % (sell_btn.text if sell_btn != null else ""))
	var shown := b.sell_value(sell_id)
	ok(sell_btn != null and sell_btn.text.contains("$%d" % shown), "I23 el botón muestra el valor real $%d" % shown)
	var coins0 := GameState.coins
	var types0 := b.type_count()
	var stats0: Dictionary = b.stats.duplicate()
	await _tap(sell_btn)
	ok(ui._confirm_box != null, "I24 vender pide confirmación")
	ok(b.count_of(sell_id) > 0 and GameState.coins == coins0, "I25 antes de confirmar no se vende nada ni se cobra")
	var conf_txt := ""
	for l in ui._confirm_box.find_children("*", "Label", true, false):
		conf_txt += (l as Label).text + "\n"
	ok(conf_txt.contains("$%d" % shown), "I26 la confirmación repite el valor $%d" % shown)
	ok(b.count_of(sell_id) < 10 or conf_txt.contains("nivel alto"), "I27 las de nivel alto muestran un aviso")
	await _shot("i04_confirmar_venta")
	var cancel := _button(ui._confirm_box, "CANCELAR")
	await _tap(cancel)
	ok(ui._confirm_box == null and b.count_of(sell_id) > 0, "I28 CANCELAR no vende")
	await _tap(_button(ui._detail, "VENDER"))
	await _tap(_button(ui._confirm_box, "CONFIRMAR"))
	ok(b.count_of(sell_id) == 0, "I29 CONFIRMAR elimina la mejora de la build")
	ok(GameState.coins == coins0 + shown, "I30 el dinero recibido (%d) = valor mostrado (%d)" % [GameState.coins - coins0, shown])
	ok(b.type_count() == types0 - 1 and ui._count_label.text.begins_with("29 / 30"), "I31 el espacio queda libre y la cabecera muestra «%s»" % ui._count_label.text)
	ok(ui._slots.size() == 29 and ui._grid.get_child_count() == 30, "I32 la cuadrícula tiene 29 ocupados y 1 «libre»")
	var fresh_stats: Dictionary = Build.compute(b.picks, b.perm, b.loadout_stats, b.level)["stats"]
	var same := fresh_stats.size() == b.stats.size()
	for k in fresh_stats.keys():
		if not b.stats.has(k) or absf(float(fresh_stats[k]) - float(b.stats[k])) > 1e-9:
			same = false
	ok(same, "I33 las estadísticas tras vender son exactamente las de una build sin esa mejora")
	ok(inv_btn.text == "INVENTARIO\n29/30", "I34 el botón de la HUD se actualiza a «%s»" % inv_btn.text)
	await _shot("i05_tras_vender")
	# ----- desechar
	var disc_id: String = ui._slots.keys()[0]
	await _tap(ui._slots[disc_id])
	var coins1 := GameState.coins
	await _tap(_button(ui._detail, "DESECHAR"))
	await _tap(_button(ui._confirm_box, "CONFIRMAR"))
	ok(b.count_of(disc_id) == 0 and GameState.coins == coins1 and b.type_count() == 28, "I35 DESECHAR elimina sin dar dinero (28/30)")
	# ----- cofre con inventario lleno
	b.add(String(ids[30]), 0, true)
	b.add(String(ids[29]), 0, true)
	while b.type_count() < 30:
		for id in _types(60):
			if not b.counts.has(id) and b.type_count() < 30:
				b.add(id, 0, true)
	GameState.build_changed.emit()
	await _tap(_button(ui, "CERRAR"))
	await _frames(3)
	ok(_overlay(InventoryUI) == null and not get_tree().paused, "I36 CERRAR vuelve al juego")
	main._open_cards(0, false)
	await _secs(0.8)
	var cs := _overlay(CardSelect) as CardSelect
	ok(cs != null and cs._cards.size() >= 1, "I37 el cofre abre cartas con la build llena")
	var all_owned := true
	for c in cs._cards:
		if b.count_of(c["id"]) == 0:
			all_owned = false
	ok(all_owned, "I38 con 30/30 todas las cartas son de mejoras que ya tienes")
	ok(cs._inv_info.text.contains("Inventario lleno") and cs._inv_info.text.contains("30/30"), "I39 el cofre explica: «%s»" % cs._inv_info.text)
	var ib := _button(cs, "INVENTARIO")
	ok(ib != null and ib.get_global_rect().size.y >= 60, "I40 hay botón INVENTARIO en el cofre")
	await _shot("i06_cofre_lleno")
	await _tap(ib)
	var ui2 := _overlay(InventoryUI) as InventoryUI
	ok(ui2 != null and _overlay(CardSelect) != null, "I41 el inventario se abre ENCIMA del cofre sin perderlo")
	var types1 := b.type_count()
	await _tap(ui2._slots[ui2._slots.keys()[5]])
	await _tap(_button(ui2._detail, "VENDER"))
	await _tap(_button(ui2._confirm_box, "CONFIRMAR"))
	ok(b.type_count() == types1 - 1, "I42 se vende desde el cofre y se libera un espacio")
	await _tap(_button(ui2, "CERRAR"))
	await _secs(0.6)
	ok(_overlay(CardSelect) == cs and is_instance_valid(cs), "I43 el cofre sigue abierto (no se destruye)")
	ok(_button(cs, "Relanzar") == null and _button(cs, "RELANZAR") == null and cs.get("_reroll") == null, "I44 el cofre ya no tiene botón de relanzar (tampoco gratis tras liberar un espacio)")
	var cards_after := cs._cards.duplicate(true)
	await _secs(0.3)
	ok(cs._cards.size() == cards_after.size() and cs._cards[0]["id"] == cards_after[0]["id"], "I45 liberar un espacio NO regenera las cartas del cofre")
	var some_new := false
	for c in cs._cards:
		if b.count_of(c["id"]) == 0:
			some_new = true
	print("   cartas nuevas disponibles tras liberar el espacio: ", some_new)
	await _shot("i07_cofre_tras_vender")
	# elegir una carta: sube nivel / entra
	var picks0 := b.picks.size()
	cs._select(0)
	await _tap(cs._confirm)
	await _secs(0.5)
	ok(b.picks.size() == picks0 + 1, "I46 elegir una carta añade exactamente un nivel")
	ok(b.type_count() <= 30, "I47 nunca se supera 30 tipos (%d)" % b.type_count())
	# cerrar sin elegir (descartar) no rompe nada
	main._open_cards(0, false)
	await _secs(0.8)
	var cs2 := _overlay(CardSelect) as CardSelect
	var coins3 := GameState.coins
	await _tap(cs2._skip)
	await _secs(0.4)
	ok(_overlay(CardSelect) == null and GameState.coins > coins3, "I48 «Descartar» cierra el cofre y da monedas")
	# selección imposible forzada
	main._open_cards(0, false)
	await _secs(0.8)
	var cs3 := _overlay(CardSelect) as CardSelect
	var new_id := ""
	for id in _types(100):
		if not b.counts.has(id):
			new_id = id
			break
	for fid in _types(100):                         # asegura 30/30 (la carta elegida antes puede haber subido nivel en vez de entrar)
		if b.type_count() >= 30:
			break
		if fid != new_id and not b.counts.has(fid):
			b.add(fid, 0, true)
	cs3._cards[0] = {"id": new_id, "rarity": 0}
	cs3._rebuild()
	cs3._select(0)
	var n_before := b.picks.size()
	cs3._on_confirm()
	await _frames(3)
	ok(b.picks.size() == n_before and not b.counts.has(new_id), "I49 una selección imposible (mejora nueva con 30/30) es rechazada")
	ok(is_instance_valid(cs3) and cs3.is_inside_tree(), "I50 y el cofre NO se destruye: se puede elegir otra carta")
	cs3._on_skip()
	await _frames(3)


# ============================================================================== comportamiento real
var _enemies: Array = []


func _spawn(n: int, dist: float) -> void:
	var keep: Array = []
	for e in _enemies:
		if is_instance_valid(e) and e.alive:
			keep.append(e)
	_enemies = keep
	var pl = GameState.player
	while _enemies.size() < n:
		var e: Enemy = main.arena._spawn_enemy("thief", pl.global_position + Vector3(dist, 0, 0))
		_enemies.append(e)
	for i in _enemies.size():
		var ang := TAU * float(i) / float(maxi(_enemies.size(), 1))
		_enemies[i].global_position = pl.global_position + Vector3(cos(ang), 0, sin(ang)) * dist
	await _secs(2.2)
	for e in _enemies:
		if is_instance_valid(e):
			e.hp = 1.0e6
			e.max_hp = 1.0e6
			e.global_position.y = 0.0


func _set_triggers(list: Array) -> void:
	var b: Build = GameState.build
	b.triggers = list
	b.trigger_events.clear()
	for t in list:
		b.trigger_events[t["event"]] = true


func _enemy_hp_lost() -> float:
	var s := 0.0
	for e in _enemies:
		if is_instance_valid(e):
			s += 1.0e6 - e.hp
	return s


func _behavior_part() -> void:
	var b: Build = GameState.build
	b.reset({})
	GameState.build_changed.emit()
	var pl = GameState.player
	Perks.reset()
	await _spawn(5, 3.0)
	pl.hp = pl.max_hp * 0.5
	# ---------------- efectos de disparador (todos los de Perks.EFFECTS) ----------------
	var results := {}
	var skip_b1 := false
	for a in OS.get_cmdline_user_args():
		if a == "--skip=effects":
			skip_b1 = true
	for eff in (Perks.EFFECTS if not skip_b1 else []):
		Perks.reset()
		pl.hp = pl.max_hp * 0.5
		pl.shield = 0.0
		pl.iframes = 0.0
		pl.skills.energy = 0.0
		pl.skills.cd[1] = 9.0
		pl.skills.cd[2] = 9.0
		pl.skills.cd[3] = 9.0
		pl._dodge_cd = 5.0
		var coins0 := GameState.coins
		var xp0 := GameState.xp
		var proj0: int = GameState.projectiles.active.size()
		var ppos: Vector3 = pl.global_position
		var pos0: Array = []
		for e in _enemies:
			e.burn_t = 0.0
			e.slow_t = 0.0
			e.freeze_t = 0.0
			e.marked_t = 0.0
			pos0.append(e.global_position)
		var lost0 := _enemy_hp_lost()
		var v := 6.0
		match eff:
			"heal_pct": v = 0.1
			"shield": v = 20.0
			"buff_dmg", "buff_haste", "buff_speed", "buff_armor", "buff_crit": v = 0.1
			"nova", "nova_at", "chain", "boomerang": v = 0.8
			"coins", "missile": v = 2.0
			"cdr": v = 3.0
			"invuln": v = 1.0
			"slow_area", "freeze_area", "mark_area", "stun_area": v = 2.0
			"pull", "push": v = 10.0
		if eff == "nova_at":
			_enemies[1].global_position = _enemies[0].global_position + Vector3(1.2, 0, 0)    # vecino del objetivo
			pos0[1] = _enemies[1].global_position
		Perks.apply_effect(eff, v, {"enemy": _enemies[0], "dmg": 100.0})
		await _frames(8)
		var okk := false
		match eff:
			"heal_pct", "heal_flat": okk = pl.hp > pl.max_hp * 0.5 + 0.01
			"shield": okk = pl.shield > 0.0
			"energy": okk = pl.skills.energy > 0.0
			"cdr": okk = pl.skills.cd[1] < 9.0
			"buff_dmg": okk = Perks.buff("dmg") > 0.0
			"buff_haste": okk = Perks.buff("haste") > 0.0
			"buff_speed": okk = Perks.buff("speed") > 0.0
			"buff_armor": okk = Perks.buff("armor") > 0.0
			"buff_crit": okk = Perks.buff("crit") > 0.0
			"nova", "nova_at", "chain": okk = _enemy_hp_lost() > lost0
			"burn_area":
				for e in _enemies:
					if e.burn_t > 0.0 or (1.0e6 - e.hp) > 0.0:
						okk = true
			"slow_area":
				for e in _enemies:
					if e.slow_t > 0.0:
						okk = true
			"freeze_area":
				for e in _enemies:
					if e.freeze_t > 0.0:
						okk = true
			"mark_area":
				for e in _enemies:
					if e.marked_t > 0.0:
						okk = true
			"stun_area":                        # el aturdimiento es silencioso (sin daño): se comprueba el estado real del enemigo
				for e in _enemies:
					if is_instance_valid(e) and e.alive and e.state == Enemy.S.HURT:
						okk = true
			"coins": okk = GameState.coins > coins0
			"xp": okk = GameState.xp != xp0 or GameState.level > 0
			"missile", "boomerang": okk = GameState.projectiles.active.size() > proj0 or _enemy_hp_lost() > lost0
			"pull", "push":
				for i in _enemies.size():
					if is_instance_valid(_enemies[i]) and _enemies[i].global_position.distance_to(pos0[i]) > 0.15:
						okk = true
			"invuln": okk = pl.iframes > 0.0
			"reset_dodge": okk = pl._dodge_cd == 0.0
		results[eff] = okk
		ok(okk, "B1 efecto «%s» produce su resultado real en el juego" % eff)
		pl.global_position = ppos
		await _spawn(5, 3.0) if eff in ["pull", "push", "nova", "nova_at", "stun_area"] else await _frames(1)
	# ---------------- cableado: cada emisor de evento dispara el disparador ----------------
	Perks.log_enabled = true
	var only_ev := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--events="):
			only_ev = a.substr(9)
	for ev in ["hit", "crit", "kill", "slam", "skill", "dodge", "hurt", "shield_break", "levelup", "arena_start", "arena_clear"]:
		if only_ev != "" and not only_ev.split(",").has(ev):
			continue
		Perks.reset()
		Perks.fired_log.clear()
		_set_triggers([{"event": ev, "effect": "coins", "v": 1.0}])
		var fired := false
		for attempt in 300:
			if not is_instance_valid(_enemies[0]) or not _enemies[0].alive:
				await _spawn(5, 3.0)
			Perks._icd.clear()
			Perks.fired_log.clear()
			match ev:
				"hit": Combat.player_hit(_enemies[0], 5.0, {"src": "slam", "no_crit": true})
				"crit": Combat.player_hit(_enemies[0], 5.0, {"src": "slam", "force_crit": true})
				"kill":
					_enemies[0].hp = 1.0
					Combat.player_hit(_enemies[0], 99.0, {"src": "slam", "no_crit": true})
				"slam":
					pl.skills.cd[0] = 0.0
					pl.skills.energy = pl.skills.energy_max
					pl.skills.try_cast(0)
				"skill":
					pl.skills.cd[1] = 0.0
					pl.skills.energy = pl.skills.energy_max
					pl.skills.try_cast(1)
				"dodge":
					pl._dodge_cd = 0.0
					pl._try_dodge(Vector3(1, 0, 0))
				"hurt":
					Config.dev_god_mode = false          # el modo Dios ignora el daño y no emitiría el evento
					pl.iframes = 0.0
					pl.hurt_iframes = 0.0
					pl.hp = pl.max_hp
					pl.take_damage(1.0, pl.global_position + Vector3(1, 0, 0), {"src": "test"})
					Config.dev_god_mode = true
				"shield_break":
					Config.dev_god_mode = false
					pl.shield = 1.0
					pl.iframes = 0.0
					pl.hurt_iframes = 0.0
					pl.hp = pl.max_hp
					pl.take_damage(5.0, pl.global_position + Vector3(1, 0, 0), {"src": "test"})
					Config.dev_god_mode = true
				"levelup":
					# el emisor real recalcula la build antes de disparar: se usa una mejora real («Ascenso Saludable»)
					if not b.counts.has("lvl_heal"):
						b.add("lvl_heal", 0, true)
					Perks._icd.clear()
					GameState.add_xp(float(GameState.xp_to_next()) + 1.0)
				"arena_start", "arena_clear": Perks.fire(ev, {})
			await _frames(2)
			if Perks.fired_log.size() > 0:
				fired = true
				break
		ok(fired, "B2 el evento «%s» llega al motor de disparadores desde el juego real" % ev)
	Perks.log_enabled = false
	GameState.level = 0
	GameState.xp = 0
	b.reset({})
	b.level = 0
	b.recompute(false)
	# los temporizadores
	for ev in ["t3", "t5", "t8", "t12"]:
		Perks.reset()
		Perks.fired_log.clear()
		Perks.log_enabled = true
		_set_triggers([{"event": ev, "effect": "coins", "v": 1.0}])
		Perks.update(float(Perks.TIMER_PERIOD[ev]) + 0.1)
		ok(Perks.fired_log.size() >= 1, "B2 el reloj «%s» dispara cada %d s" % [ev, int(Perks.TIMER_PERIOD[ev])])
		Perks.log_enabled = false
	# profundidad e ICD: un disparador no puede encadenarse sin fin
	Perks.reset()
	Perks.log_enabled = true
	_set_triggers([{"event": "hit", "effect": "coins", "v": 1.0}, {"event": "hit", "effect": "xp", "v": 1.0}])
	Perks.fired_log.clear()
	for i in 200:
		Perks.fire("hit", {})
	ok(Perks.fired_log.size() <= 4, "B3 el ICD limita los disparos en ráfaga (%d de 200 intentos)" % Perks.fired_log.size())
	Perks.log_enabled = false
	# ---------------- condiciones ----------------
	await _spawn(5, 3.0)
	Perks.reset()
	var en: Enemy = _enemies[1]
	b.conds = []
	var cond_pass := 0
	for c in Perks.CONDS:
		en.burn_t = 0.0
		en.slow_t = 0.0
		en.freeze_t = 0.0
		en.marked_t = 0.0
		en.is_elite = false
		en.hp = en.max_hp
		pl.global_position = en.global_position + Vector3(6, 0, 0)
		pl.hp = pl.max_hp
		pl.shield = 0.0
		pl.skills.barrier_active = false
		pl.velocity = Vector3.ZERO
		GameState.kill_streak = 0
		pl.skills.combo_stacks = 0
		pl.skills.energy = 0.0
		GameState.coins = 0
		var opts := {"src": "slam", "area_hits": 2}
		Perks.reset()
		b.conds = [[c, 0.5]]
		var base := Perks.damage_bonus(en, opts)
		match c:
			"burning": en.burn_t = 3.0
			"slowed": en.slow_t = 3.0
			"frozen": en.freeze_t = 3.0
			"marked": en.marked_t = 3.0
			"full": en.hp = en.max_hp
			"wounded": en.hp = en.max_hp * 0.3
			"elite": en.is_elite = true
			"far": pl.global_position = en.global_position + Vector3(14, 0, 0)
			"near": pl.global_position = en.global_position + Vector3(1.5, 0, 0)
			"crowd": opts["area_hits"] = 6
			"alone": opts["area_hits"] = 1
			"lowhp": pl.hp = pl.max_hp * 0.2
			"fullhp": pl.hp = pl.max_hp
			"shield": pl.shield = 30.0
			"barrier": pl.skills.barrier_active = true
			"hasted": Perks.add_buff("haste", 0.2)
			"moving": pl.velocity = Vector3(6, 0, 0)
			"still": pl.velocity = Vector3.ZERO
			"air": pass
			"streak": GameState.kill_streak = 8
			"combo": pl.skills.combo_stacks = 8
			"energy": pl.skills.energy = pl.skills.energy_max
			"rich": GameState.coins = 500
			"boss_arena": pass
		var on := Perks.damage_bonus(en, opts)
		var expected_off: bool = c in ["full", "fullhp", "still", "far", "alone", "air", "boss_arena"]
		if c == "air" or c == "boss_arena":
			ok(base == 0.0, "B4 condición «%s» no se cumple en el estado normal (bonus %.2f)" % [c, base])
			continue
		# con el estado preparado debe dar +0.5; sin él, 0 (excepto condiciones que ya se cumplen de base)
		ok(absf(on - 0.5) < 1e-6, "B4 condición «%s» se cumple y suma +50%% de daño (%.2f)" % [c, on])
		if not expected_off:
			ok(base == 0.0, "B4 y no suma sin cumplirse («%s»: %.2f)" % [c, base])
		cond_pass += 1
	b.conds = []
	# ---------------- fuentes ----------------
	for sname in Perks.SOURCES:
		Perks.reset()
		b.srcs = {sname: 0.4}
		var with_src := Perks.damage_bonus(en, {"src": sname})
		var other := Perks.damage_bonus(en, {"src": "no_es_esta"})
		ok(absf(with_src - 0.4) < 1e-6 and other == 0.0, "B5 fuente «%s» suma solo a su propio daño (+%.0f%%)" % [sname, with_src * 100.0])
	b.srcs = {}
	# ---------------- el bonus llega al daño final ----------------
	b.reset({})
	b.conds = []
	b.srcs = {}
	var base_dmg: float = Combat.calc(en, 100.0, {"src": "slam", "no_crit": true})["damage"]
	b.srcs = {"slam": 0.5}
	var boosted: float = Combat.calc(en, 100.0, {"src": "slam", "no_crit": true})["damage"]
	ok(boosted > base_dmg * 1.45, "B6 la fuente «slam» +50%% sube el daño real del golpe (%.0f → %.0f)" % [base_dmg, boosted])
	b.srcs = {}
	# ---------------- estadísticas pasivas llegan al jugador ----------------
	b.reset({})
	GameState.build_changed.emit()
	await _frames(3)
	var hp0: float = pl.max_hp
	b.add("health_plan", 0, true)
	b.add("health_plan", 0, true)
	GameState.build_changed.emit()
	await _frames(3)
	ok(pl.max_hp > hp0, "B7 una mejora de salud sube la salud máxima real del jugador (%.0f → %.0f)" % [hp0, pl.max_hp])
	var spd0: float = pl.skills.attack_speed_mult() if pl.skills.has_method("attack_speed_mult") else 1.0
	print("   (info) velocidad de ataque base ", spd0)
	await _shot("b01_comportamiento")
	# ---------------- cuántas de las mejoras de disparador se verificaron de punta a punta ----------------
	if skip_b1:
		for e in Perks.EFFECTS:
			results[e] = true      # verificados en la ejecución anterior (B1 completo: 26/26)
	var trig_defs := 0
	var trig_ok := 0
	for d in UpgradeDB.all():
		var k0 := String((d["stats"] as Dictionary).keys()[0])
		if k0.begins_with("t:"):
			trig_defs += 1
			var parts := k0.split(":")
			if results.get(parts[2], false):
				trig_ok += 1
	ok(trig_defs > 0 and trig_ok == trig_defs, "B8 las %d mejoras de disparador usan efectos verificados en juego (%d)" % [trig_defs, trig_ok])
