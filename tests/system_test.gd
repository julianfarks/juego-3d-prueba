extends Node
## Pruebas de sistemas SIN renderizado (guardado, carga, dificultad, equipamiento, estadísticas).
## Se ejecutan en procesos separados para simular "cerrar el juego y abrirlo de nuevo":
##   godot --headless res://tests/system_test.tscn -- --phase=A --out=/tmp/x
##   godot --headless res://tests/system_test.tscn -- --phase=B --out=/tmp/x
## (usar XDG_DATA_HOME propio para no tocar guardados reales)

var phase := "A"
var out_dir := "/tmp/systest"
var fails: Array = []
var passes := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--phase="):
			phase = a.substr(8)
		elif a.begins_with("--out="):
			out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out_dir)
	call_deferred("_main")


func ok(cond: bool, name: String) -> void:
	if cond:
		passes += 1
		print("[PASS] ", name)
	else:
		fails.append(name)
		print("[FAIL] ", name)


func _main() -> void:
	match phase:
		"A": _phase_a()
		"B": _phase_b()
		"C": _phase_c()
	print("[RESULT] fase %s: %d ok, %d fallos" % [phase, passes, fails.size()])
	get_tree().quit(1 if fails.size() > 0 else 0)


func _file(name: String) -> String:
	return out_dir + "/" + name


func _write_json(name: String, d: Dictionary) -> void:
	var f := FileAccess.open(_file(name), FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()


func _read_json(name: String) -> Dictionary:
	var f := FileAccess.open(_file(name), FileAccess.READ)
	return JSON.parse_string(f.get_as_text())


# --------------------------------------------------------------- A: crear y guardar
func _phase_a() -> void:
	ok(not SaveSystem.has_valid_run(), "A1 sin partida guardada al empezar de cero")
	# equipamiento y dificultad elegidos
	SaveSystem.data["records"]["best_arena"] = 6
	SaveSystem.data["meta"]["fees"] = 1000
	ok(LoadoutDB.unlock("gavel"), "A2 se desbloquea el Mazo del Juez con honorarios")
	ok(int(SaveSystem.data["meta"]["fees"]) == 860, "A3 el desbloqueo descuenta 140 honorarios")
	ok(LoadoutDB.equip("weapon", "gavel"), "A4 se equipa el Mazo")
	ok(not LoadoutDB.equip("weapon", "quill"), "A5 no se puede equipar lo bloqueado (Pluma)")
	ok(LoadoutDB.select_difficulty("partner"), "A6 se elige dificultad Socio")
	GameState.start_run()
	ok(GameState.difficulty_id == "partner", "A7 la partida usa la dificultad elegida")
	ok(float(GameState.weapon_params["dmg_x"]) == 2.1, "A8 la herramienta equipada llega a la partida")
	ok(GameState.build.s("docs_extra") == 2.0, "A9 el equipamiento aporta estadísticas a Build")
	# estado de partida
	GameState.arena_index = 6
	GameState.coins = 321
	GameState.kills = 44
	GameState.run_time = 400.0
	GameState.run_stats["bosses"] = 1
	GameState.run_stats["damage_dealt"] = 5000.0
	GameState.run_stats["coins_earned"] = 500
	GameState.run_stats["cards"] = 2
	GameState.run_stats["arenas"] = 6
	GameState.build.add("wide_sweep", 1)
	GameState.build.add("wide_sweep", 0)
	GameState.xp = 10
	GameState.level = 3
	var picks_before: Array = GameState.build.picks.duplicate(true)
	var snap := GameState.snapshot_run("portal")
	snap["hp"] = 63.0
	snap["shield"] = 12.0
	snap["revives_left"] = 1
	ok(SaveSystem.store_run(snap), "A10 la partida se guarda y se verifica en disco")
	var expected := {"coins": 321, "kills": 44, "arena": 6, "picks": picks_before.size(), "hp": 63.0, "diff": "partner",
		"weapon": "gavel", "stage": "portal", "level": 3, "run_time": 400.0, "stats_kills": int(SaveSystem.data["stats"]["kills"])}
	# volcado de estadísticas durante la partida (no solo al final)
	GameState.flush_stats()
	SaveSystem.save_now()
	expected["stats_kills"] = int(SaveSystem.data["stats"]["kills"])
	expected["stats_bosses"] = int(SaveSystem.data["stats"]["bosses"])
	expected["stats_runs"] = int(SaveSystem.data["stats"]["runs"])
	ok(int(expected["stats_kills"]) == 44, "A11 las estadísticas se actualizan durante la partida (kills=44)")
	GameState.flush_stats()
	ok(int(SaveSystem.data["stats"]["kills"]) == 44, "A12 volcar dos veces no duplica estadísticas")
	_write_json("expected.json", expected)


# --------------------------------------------------------------- B: reabrir y comprobar
func _phase_b() -> void:
	var e := _read_json("expected.json")
	ok(SaveSystem.has_valid_run(), "B1 tras reiniciar hay una partida guardada válida")
	var r := SaveSystem.get_run()
	ok(int(r["coins"]) == int(e["coins"]) and int(r["kills"]) == int(e["kills"]), "B2 monedas y bajas se recuperan")
	ok(int(r["arena_index"]) == int(e["arena"]) and String(r["stage"]) == String(e["stage"]), "B3 arena y etapa se recuperan")
	ok(float(r["hp"]) == float(e["hp"]), "B4 la salud se recupera")
	ok(String(r["difficulty"]) == "partner", "B5 la dificultad se recupera")
	ok(String(r["loadout"]["weapon"]) == "gavel", "B6 el equipamiento se recupera")
	ok((r["picks"] as Array).size() == int(e["picks"]), "B7 las mejoras elegidas se recuperan")
	GameState.restore_run(r)
	ok(GameState.coins == 321 and GameState.kills == 44 and GameState.level == 3, "B8 GameState restaurado (monedas, bajas, nivel)")
	ok(GameState.build.count_of("wide_sweep") == 2, "B9 la build restaurada tiene las mejoras")
	ok(absf(GameState.build.s("aoe_pct") - 0.12 * (UpgradeDB.rarity_scale(UpgradeDB.get_def("wide_sweep"), 1) + UpgradeDB.rarity_scale(UpgradeDB.get_def("wide_sweep"), 0))) < 0.0001, "B10 las estadísticas de la build se recalculan igual")
	ok(Scaling.diff_id == "partner", "B11 la dificultad restaurada llega a Scaling")
	ok(int(SaveSystem.data["stats"]["runs"]) == int(e["stats_runs"]), "B12 reanudar no cuenta como partida nueva")
	GameState.flush_stats()
	ok(int(SaveSystem.data["stats"]["kills"]) == int(e["stats_kills"]), "B13 reanudar no duplica las bajas ya volcadas")
	ok(int(SaveSystem.data["stats"]["bosses"]) == int(e["stats_bosses"]), "B14 reanudar no duplica los jefes")
	# desbloqueos y selección persisten
	ok(LoadoutDB.is_unlocked("gavel"), "B15 el desbloqueo persiste")
	ok(LoadoutDB.equipped()["weapon"] == "gavel", "B16 el equipamiento elegido persiste")
	ok(LoadoutDB.selected_difficulty() == "partner", "B17 la dificultad elegida persiste")
	ok(int(SaveSystem.data["meta"]["fees"]) == 860, "B18 los honorarios persisten")
	# una partida terminada no se recupera
	var sm := GameState.end_run(false)
	ok(not sm.is_empty(), "B19 la partida termina (derrota)")
	ok(not SaveSystem.has_valid_run(), "B20 tras perder, no hay partida recuperable")
	ok(int(SaveSystem.data["stats"]["deaths"]) == 1, "B21 la derrota queda en las estadísticas")
	ok(int(SaveSystem.data["stats"]["kills"]) == 44, "B22 al terminar no se duplican las bajas")
	# robustez: archivo corrupto
	SaveSystem.store_run(_valid_run())
	SaveSystem.store_run(_valid_run())      # la copia .bak es la generación anterior: guardamos dos veces
	ok(SaveSystem.has_valid_run(), "B23 se vuelve a guardar una partida válida")
	var p := ProjectSettings.globalize_path(SaveSystem.PATH)
	var f := FileAccess.open(SaveSystem.PATH, FileAccess.WRITE)
	f.store_string("{\"format\":2,\"sum\":\"x\",\"payload\":\"{roto\"")
	f.close()
	SaveSystem.data = SaveSystem.defaults()
	SaveSystem.load_data()
	ok(SaveSystem.last_load_note.contains("copia de seguridad"), "B24 archivo dañado: se recupera la copia de seguridad")
	ok(SaveSystem.has_valid_run(), "B25 la copia de seguridad conserva la partida")
	# ambos dañados
	for path in [SaveSystem.PATH, SaveSystem.PATH_BAK]:
		var g := FileAccess.open(path, FileAccess.WRITE)
		g.store_string("basura")
		g.close()
	SaveSystem.data = SaveSystem.defaults()
	SaveSystem.load_data()
	ok(SaveSystem.last_load_note.contains("dañado"), "B26 ambos dañados: se avisa y se empieza de cero")
	ok(not SaveSystem.has_valid_run(), "B27 no se carga una partida de un archivo dañado")
	# partida inválida (salud 0 / mejora inexistente) se descarta
	var bad := _valid_run()
	bad["hp"] = 0.0
	ok(SaveSystem.validate_run(bad) != "", "B28 una partida con 0 de salud no es válida")
	bad = _valid_run()
	bad["picks"] = [{"id": "no_existe", "rarity": 0}]
	ok(SaveSystem.validate_run(bad) != "", "B29 una mejora inexistente invalida la partida")
	bad = _valid_run()
	bad.erase("coins")
	ok(SaveSystem.validate_run(bad) != "", "B30 un campo que falta invalida la partida")
	# partida inválida en disco se descarta al cargar
	SaveSystem.data["run"] = bad
	SaveSystem.save_now()
	SaveSystem.data = SaveSystem.defaults()
	SaveSystem.load_data()
	ok(not SaveSystem.has_valid_run(), "B31 una partida inválida en disco se descarta al cargar")
	# restos de escritura interrumpida (.tmp) no afectan
	var t := FileAccess.open(SaveSystem.PATH_TMP, FileAccess.WRITE)
	t.store_string("{parcial")
	t.close()
	SaveSystem.store_run(_valid_run())
	ok(SaveSystem.has_valid_run(), "B32 un .tmp sobrante no impide guardar")


func _valid_run() -> Dictionary:
	GameState.start_run()
	GameState.arena_index = 2
	var s := GameState.snapshot_run("fight")
	s["hp"] = 80.0
	return s


# --------------------------------------------------------------- C: dificultad y reglas
func _phase_c() -> void:
	var hp := {}
	var dmg := {}
	var cnt := {}
	var rew := {}
	for id in LoadoutDB.DIFF_ORDER:
		Scaling.set_difficulty(id)
		hp[id] = Scaling.hp_mult(4)
		dmg[id] = Scaling.dmg_mult(4)
		cnt[id] = Scaling.count_mult(4)
		rew[id] = Scaling.reward_mult(4)
	ok(hp["intern"] < hp["associate"] and hp["associate"] < hp["partner"] and hp["partner"] < hp["prosecutor"], "C1 la vida enemiga sube con la dificultad")
	ok(dmg["intern"] < dmg["associate"] and dmg["associate"] < dmg["partner"] and dmg["partner"] < dmg["prosecutor"], "C2 el daño enemigo sube con la dificultad")
	ok(cnt["intern"] < cnt["associate"] and cnt["associate"] < cnt["partner"] and cnt["partner"] < cnt["prosecutor"], "C3 la cantidad de enemigos sube con la dificultad")
	ok(rew["intern"] < rew["associate"] and rew["associate"] < rew["partner"] and rew["partner"] < rew["prosecutor"], "C4 las recompensas suben con la dificultad")
	Scaling.set_difficulty("associate")
	var base_hp := Scaling.hp_mult(4)
	ok(absf(base_hp - (1.0 + 0.11 * 4)) < 0.0001, "C5 Asociado conserva el equilibrio original")
	# honorarios
	GameState.start_run()
	GameState.run_stats["arenas"] = 5
	GameState.kills = 50
	Scaling.set_difficulty("associate")
	var f1 := GameState.fees_for_run(false)
	Scaling.set_difficulty("prosecutor")
	var f2 := GameState.fees_for_run(false)
	ok(f2 > f1 * 2, "C6 los honorarios suben con la dificultad")
	# dificultad bloqueada
	SaveSystem.data["records"]["best_arena"] = 1
	ok(not LoadoutDB.select_difficulty("prosecutor"), "C7 Fiscal Implacable está bloqueado hasta llegar a la arena 6")
	SaveSystem.data["records"]["best_arena"] = 6
	ok(LoadoutDB.select_difficulty("prosecutor"), "C8 se desbloquea al llegar a la arena 6")
	# equipamiento: cada objeto cambia algo real
	for id in LoadoutDB.ITEMS.keys():
		var lo: Dictionary = LoadoutDB.DEFAULT_LOADOUT.duplicate()
		lo[LoadoutDB.item(id)["slot"]] = id
		var st := LoadoutDB.total_stats(lo)
		var wp := LoadoutDB.weapon_params(lo)
		ok(not st.is_empty() or id == "case" or id == "gavel" or id == "quill", "C9 %s aporta estadísticas o parámetros" % id)
	ok(LoadoutDB.weapon_params({"weapon": "quill"})["cd_x"] < LoadoutDB.weapon_params({"weapon": "case"})["cd_x"], "C10 la Pluma ataca más rápido que el Maletín")
	ok(LoadoutDB.weapon_params({"weapon": "gavel"})["dmg_x"] > LoadoutDB.weapon_params({"weapon": "case"})["dmg_x"], "C11 el Mazo golpea más fuerte")
	ok(LoadoutDB.sanitize({"weapon": "quill"})["weapon"] == "case", "C12 un objeto bloqueado en el guardado se sustituye por el de serie")
