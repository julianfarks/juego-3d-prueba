extends SceneTree
## Herramienta rápida (sin render): estadísticas de pendiente y altura de cada bioma.
##   godot --headless --path . --script tests/terrain_probe.gd
func _init() -> void:
	for b in BiomeDB.COUNT:
		var pal := BiomeDB.get_biome(b)
		for sd in [11, 222, 3333]:
			Terrain.configure(pal, 26.0, sd, [Vector3(12, -8, 5), Vector3(-14, 10, 4)])
			var arr: Array = []
			var lo := 1e9
			var hi := -1e9
			var x := -25.5
			while x < 26.0:
				var z := -25.5
				while z < 26.0:
					arr.append(Terrain.slope_deg(x, z))
					var h := Terrain.height(x, z)
					lo = minf(lo, h)
					hi = maxf(hi, h)
					z += 0.75
				x += 0.75
			arr.sort()
			print("%-10s seed %5d  alt %.2f..%.2f  pend máx %.1f°  p99 %.1f°  p95 %.1f°" % [pal["id"], sd, lo, hi, arr[arr.size() - 1], arr[int(arr.size() * 0.99)], arr[int(arr.size() * 0.95)]])
	quit()
