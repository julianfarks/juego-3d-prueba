class_name IconView
extends Control
## Icono vectorial procedural para cartas, tienda y HUD. Dibuja un glifo según el nombre
## sobre un medallón del color de la categoría (no usa imágenes externas).

var icon := "star"
var color := Color(1, 0.8, 0.3)
var ring_color := Color(1, 1, 1, 0.5)


func setup(p_icon: String, p_color: Color, size := 96.0) -> IconView:
	icon = p_icon
	color = p_color
	custom_minimum_size = Vector2(size, size)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()
	return self


const ALIAS := {
	"sword": "blade", "thorn": "blade", "book": "page", "doc": "page", "paper": "page", "pact": "page",
	"target": "ringdot", "eye": "ringdot", "link": "chain", "handshake": "chain", "bolt": "bolt", "zap": "bolt",
	"shoe": "chevrons", "wind": "chevrons", "wing": "chevrons", "trail": "chevrons", "fast": "chevrons",
	"cup": "cell", "battery": "cell", "layers": "shield", "vest": "shield", "badge": "shield", "barrier": "shield",
	"burst": "starburst", "nova": "starburst", "mega": "starburst", "star": "starburst", "seal": "starburst",
	"ring": "rings", "echo": "rings", "zone": "rings", "flame": "flame", "fire2": "flame", "gem": "gem",
	"crown": "crown", "glass": "gem", "dice": "dice", "spade": "spade", "crowd": "crowd", "cross": "cross",
	"heart": "heart", "zzz": "zzz", "clock": "clock", "coin": "coin", "skull": "skull", "gear": "gear",
	"clover": "clover", "snow": "snow", "drop": "drop", "boomerang": "boomerang", "gavel": "gavel",
}


func _draw() -> void:
	var s := minf(size.x, size.y)
	if s <= 1.0:
		return
	var c := Vector2(size.x, size.y) * 0.5
	draw_circle(c, s * 0.48, color.darkened(0.55))
	draw_circle(c, s * 0.44, color.darkened(0.2))
	draw_arc(c, s * 0.46, 0, TAU, 40, ring_color, maxf(2.0, s * 0.03))
	var g: String = ALIAS.get(icon, "starburst")
	var u := s * 0.5          # unidad (radio del glifo)
	var w := Color(1, 1, 1, 0.96)
	var d := Color(0.1, 0.1, 0.16, 0.9)
	match g:
		"blade":
			draw_colored_polygon(_p(c, u, [[-0.1, 0.55], [0.1, 0.55], [0.1, -0.25], [0.0, -0.65], [-0.1, -0.25]]), w)
			draw_rect(Rect2(c + Vector2(-0.3, 0.38) * u, Vector2(0.6, 0.12) * u), color.lightened(0.4))
		"page":
			draw_rect(Rect2(c + Vector2(-0.38, -0.5) * u, Vector2(0.76, 1.0) * u), w)
			for i in 4:
				draw_line(c + Vector2(-0.24, -0.28 + i * 0.22) * u, c + Vector2(0.24, -0.28 + i * 0.22) * u, d, maxf(2.0, s * 0.03))
		"skull":
			draw_circle(c + Vector2(0, -0.1) * u, 0.5 * u, w)
			draw_rect(Rect2(c + Vector2(-0.26, 0.2) * u, Vector2(0.52, 0.35) * u), w)
			draw_circle(c + Vector2(-0.2, -0.1) * u, 0.14 * u, d)
			draw_circle(c + Vector2(0.2, -0.1) * u, 0.14 * u, d)
		"ringdot":
			draw_arc(c, 0.55 * u, 0, TAU, 32, w, maxf(3.0, s * 0.05))
			draw_arc(c, 0.3 * u, 0, TAU, 24, w, maxf(3.0, s * 0.05))
			draw_circle(c, 0.1 * u, w)
		"clock":
			draw_arc(c, 0.55 * u, 0, TAU, 32, w, maxf(3.0, s * 0.05))
			draw_line(c, c + Vector2(0, -0.38) * u, w, maxf(3.0, s * 0.05))
			draw_line(c, c + Vector2(0.28, 0.1) * u, w, maxf(3.0, s * 0.05))
		"coin":
			draw_circle(c, 0.55 * u, Color(1.0, 0.85, 0.3))
			draw_circle(c, 0.4 * u, Color(1.0, 0.95, 0.6))
			draw_line(c + Vector2(0, -0.28) * u, c + Vector2(0, 0.28) * u, Color(0.7, 0.5, 0.1), maxf(3.0, s * 0.05))
		"chain":
			draw_arc(c + Vector2(-0.22, 0) * u, 0.3 * u, 0, TAU, 24, w, maxf(3.0, s * 0.06))
			draw_arc(c + Vector2(0.22, 0) * u, 0.3 * u, 0, TAU, 24, w, maxf(3.0, s * 0.06))
		"bolt":
			draw_colored_polygon(_p(c, u, [[0.15, -0.65], [-0.35, 0.1], [-0.02, 0.1], [-0.15, 0.65], [0.38, -0.12], [0.04, -0.12]]), Color(1.0, 0.95, 0.4))
		"chevrons":
			for i in 3:
				var x := -0.4 + i * 0.32
				draw_polyline(_p(c, u, [[x, -0.4], [x + 0.28, 0.0], [x, 0.4]]), w, maxf(3.0, s * 0.06))
		"cell":
			draw_rect(Rect2(c + Vector2(-0.35, -0.4) * u, Vector2(0.7, 0.95) * u), w)
			draw_rect(Rect2(c + Vector2(-0.15, -0.6) * u, Vector2(0.3, 0.2) * u), w)
			draw_rect(Rect2(c + Vector2(-0.25, 0.05) * u, Vector2(0.5, 0.42) * u), color.lightened(0.2))
		"gear":
			for i in 8:
				var a := TAU * i / 8.0
				draw_line(c + Vector2(cos(a), sin(a)) * 0.45 * u, c + Vector2(cos(a), sin(a)) * 0.65 * u, w, maxf(4.0, s * 0.09))
			draw_circle(c, 0.5 * u, w)
			draw_circle(c, 0.2 * u, color.darkened(0.3))
		"shield":
			draw_colored_polygon(_p(c, u, [[-0.5, -0.5], [0.5, -0.5], [0.5, 0.1], [0.0, 0.7], [-0.5, 0.1]]), w)
			draw_colored_polygon(_p(c, u, [[-0.3, -0.32], [0.3, -0.32], [0.3, 0.05], [0.0, 0.45], [-0.3, 0.05]]), color.lightened(0.1))
		"gavel":
			draw_colored_polygon(_p(c, u, [[-0.55, -0.4], [0.05, -0.65], [0.3, -0.25], [-0.3, 0.0]]), w)
			draw_line(c + Vector2(-0.05, -0.15) * u, c + Vector2(0.45, 0.55) * u, w, maxf(4.0, s * 0.08))
		"starburst":
			var pts: Array = []
			for i in 16:
				var r := 0.65 if i % 2 == 0 else 0.3
				var a := TAU * i / 16.0 - PI * 0.5
				pts.append([cos(a) * r, sin(a) * r])
			draw_colored_polygon(_p(c, u, pts), Color(1.0, 0.95, 0.5))
		"clover":
			for o in [[-0.22, -0.22], [0.22, -0.22], [-0.22, 0.22], [0.22, 0.22]]:
				draw_circle(c + Vector2(o[0], o[1]) * u, 0.26 * u, Color(0.5, 1.0, 0.55))
			draw_line(c + Vector2(0, 0.2) * u, c + Vector2(0.2, 0.7) * u, Color(0.5, 1.0, 0.55), maxf(3.0, s * 0.05))
		"heart":
			draw_circle(c + Vector2(-0.22, -0.15) * u, 0.32 * u, Color(1.0, 0.4, 0.5))
			draw_circle(c + Vector2(0.22, -0.15) * u, 0.32 * u, Color(1.0, 0.4, 0.5))
			draw_colored_polygon(_p(c, u, [[-0.5, -0.02], [0.5, -0.02], [0.0, 0.62]]), Color(1.0, 0.4, 0.5))
		"cross":
			draw_rect(Rect2(c + Vector2(-0.16, -0.55) * u, Vector2(0.32, 1.1) * u), Color(1.0, 0.45, 0.5))
			draw_rect(Rect2(c + Vector2(-0.55, -0.16) * u, Vector2(1.1, 0.32) * u), Color(1.0, 0.45, 0.5))
		"zzz":
			for i in 3:
				var k := 0.25 + i * 0.12
				var o := Vector2(-0.3 + i * 0.25, 0.3 - i * 0.35)
				draw_polyline(_p(c + o * u, u, [[-k, -k], [k, -k], [-k, k], [k, k]]), w, maxf(2.0, s * 0.04))
		"rings":
			for i in 3:
				draw_arc(c, (0.2 + i * 0.2) * u, 0, TAU, 28, Color(1, 1, 1, 0.95 - i * 0.2), maxf(2.0, s * 0.045))
		"flame":
			draw_colored_polygon(_p(c, u, [[0.0, -0.7], [0.4, -0.05], [0.3, 0.5], [0.0, 0.65], [-0.3, 0.5], [-0.42, -0.05], [-0.1, -0.2]]), Color(1.0, 0.55, 0.2))
			draw_colored_polygon(_p(c, u, [[0.0, -0.1], [0.2, 0.25], [0.0, 0.5], [-0.2, 0.25]]), Color(1.0, 0.9, 0.4))
		"snow":
			for i in 3:
				var a := PI * i / 3.0
				draw_line(c - Vector2(cos(a), sin(a)) * 0.6 * u, c + Vector2(cos(a), sin(a)) * 0.6 * u, Color(0.8, 0.95, 1.0), maxf(3.0, s * 0.05))
		"drop":
			draw_circle(c + Vector2(0, 0.2) * u, 0.4 * u, Color(0.4, 0.8, 1.0))
			draw_colored_polygon(_p(c, u, [[0.0, -0.65], [0.37, 0.12], [-0.37, 0.12]]), Color(0.4, 0.8, 1.0))
		"boomerang":
			draw_polyline(_p(c, u, [[-0.55, -0.4], [0.0, 0.5], [0.55, -0.4]]), w, maxf(5.0, s * 0.11))
		"gem":
			draw_colored_polygon(_p(c, u, [[-0.45, -0.1], [-0.25, -0.5], [0.25, -0.5], [0.45, -0.1], [0.0, 0.6]]), Color(0.6, 0.95, 1.0))
			draw_polyline(_p(c, u, [[-0.45, -0.1], [0.45, -0.1]]), w, maxf(2.0, s * 0.03))
		"crown":
			draw_colored_polygon(_p(c, u, [[-0.55, 0.4], [-0.55, -0.35], [-0.25, -0.05], [0.0, -0.5], [0.25, -0.05], [0.55, -0.35], [0.55, 0.4]]), Color(1.0, 0.85, 0.3))
		"dice":
			draw_rect(Rect2(c + Vector2(-0.45, -0.45) * u, Vector2(0.9, 0.9) * u), w)
			for o in [[-0.22, -0.22], [0.22, 0.22], [0.0, 0.0], [0.22, -0.22], [-0.22, 0.22]]:
				draw_circle(c + Vector2(o[0], o[1]) * u, 0.08 * u, d)
		"spade":
			draw_circle(c + Vector2(-0.2, 0.05) * u, 0.3 * u, w)
			draw_circle(c + Vector2(0.2, 0.05) * u, 0.3 * u, w)
			draw_colored_polygon(_p(c, u, [[0.0, -0.65], [0.5, 0.0], [-0.5, 0.0]]), w)
			draw_rect(Rect2(c + Vector2(-0.07, 0.15) * u, Vector2(0.14, 0.5) * u), w)
		"crowd":
			for o in [[-0.3, 0.0], [0.3, 0.0], [0.0, -0.1]]:
				draw_circle(c + Vector2(o[0], o[1] - 0.25) * u, 0.18 * u, w)
				draw_colored_polygon(_p(c + Vector2(o[0], o[1]) * u, u, [[-0.25, 0.65], [0.25, 0.65], [0.0, 0.0]]), w)
		_:
			draw_circle(c, 0.4 * u, w)


func _p(origin: Vector2, u: float, pts: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(origin + Vector2(p[0], p[1]) * u)
	return out
