extends Control
## Captura de la pantalla de cartas con una build de nivel alto (comprobación visual).
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	call_deferred("_go")

func _go() -> void:
	GameState.start_run()
	for i in 16:
		GameState.build.add("heavy_case", 1)
	for i in 9:
		GameState.build.add("wide_sweep", 0)
	for i in 4:
		GameState.build.add("espresso", 0)
	GameState.rng.seed = 5
	var cs := CardSelect.new()
	add_child(cs)
	cs.open(12, 0, "chest")
	cs._cards = [{"id": "heavy_case", "rarity": 1}, {"id": "wide_sweep", "rarity": 0}, {"id": "paper_storm", "rarity": 2}]
	cs._rebuild()
	await get_tree().create_timer(1.2).timeout
	get_viewport().get_texture().get_image().save_png("/tmp/claude-0/cards.png")
	get_tree().quit()
