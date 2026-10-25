extends Node
## Capturas de los efectos de impacto por familia. --fxshot --out=DIR
var main: Node
var out_dir := "/tmp/fxshot"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out_dir)
	call_deferred("_run")

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _run() -> void:
	await _frames(10)
	await main._enter_lobby(true)
	await _frames(15)
	main._on_play()
	var t := 0.0
	while main.state != main.St.RUN and t < 10.0:
		await _frames(2)
		t += 0.03
	Config.dev_god_mode = true
	main.arena.force_complete()
	await get_tree().create_timer(5.0).timeout
	var fx = GameState.fx
	var pl = GameState.player
	var cases := [["normal", "case", "phys", false], ["crit", "case", "phys", false], ["elem", "x", "fire", false], ["elem", "x", "ice", false],
		["elem", "x", "shock", false], ["normal", "case", "phys", true]]
	for i in cases.size():
		var c: Array = cases[i]
		var pos: Vector3 = pl.global_position + Vector3(-3.0 + 1.2 * i, 0, -4)
		fx.impact(pos, c[0], c[1], c[2], c[3], false, 1.0)
	fx.kill_banner(pl.global_position + Vector3(0, 0, -9), 99, false, 1.0)
	await _frames(2)
	get_viewport().get_texture().get_image().save_png(out_dir + "/impacts.png")
	print("[FXSHOT] stats ", fx.impact_stats)
	get_tree().quit(0)
