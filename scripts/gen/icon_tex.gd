class_name IconTex
extends RefCounted
## Texturas de iconos generadas por código (sin archivos de imagen).

static var _cache: Dictionary = {}


static func _circle(img: Image, cx: float, cy: float, r: float, col: Color) -> void:
	var x0 := maxi(0, int(cx - r - 1))
	var x1 := mini(img.get_width() - 1, int(cx + r + 1))
	var y0 := maxi(0, int(cy - r - 1))
	var y1 := mini(img.get_height() - 1, int(cy + r + 1))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if Vector2(x + 0.5 - cx, y + 0.5 - cy).length() <= r:
				img.set_pixel(x, y, col)


static func _rect(img: Image, x: float, y: float, w: float, h: float, col: Color) -> void:
	img.fill_rect(Rect2i(int(x), int(y), int(w), int(h)), col)


## Dibuja la silueta de una mano que señala hacia arriba ("toca aquí") sobre 'img'.
static func _hand_shape(img: Image, col: Color, grow: float) -> void:
	var g := grow
	# dedo índice
	_rect(img, 40 - g, 16, 15 + g * 2, 38, col)
	_circle(img, 47.5, 17, 7.5 + g, col)
	# palma
	_rect(img, 30 - g, 50 - g, 46 + g * 2, 34 + g * 2, col)
	_circle(img, 40, 82, 10 + g, col)
	_circle(img, 66, 82, 10 + g, col)
	_rect(img, 30 - g, 74, 46 + g * 2, 10 + g, col)
	# nudillos de los dedos doblados
	_circle(img, 59, 52, 7.5 + g, col)
	_circle(img, 67, 56, 7.5 + g, col)
	_circle(img, 74, 63, 7.0 + g, col)
	# pulgar
	_circle(img, 29, 66, 8.0 + g, col)
	_rect(img, 22 - g, 60, 12 + g, 12 + g, col)


## Mano señalando hacia abajo (contorno oscuro, relleno de 'fill').
static func hand(fill := Color(1.0, 0.9, 0.35)) -> ImageTexture:
	var key := "hand_%s" % fill.to_html()
	if _cache.has(key):
		return _cache[key]
	var img := Image.create(96, 96, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_hand_shape(img, Color(0.08, 0.06, 0.12, 0.95), 3.5)
	_hand_shape(img, fill, 0.0)
	# líneas de los dedos (detalle)
	for x in [58, 66]:
		_rect(img, x, 56, 1, 14, fill.darkened(0.35))
	img.flip_y()      # el dedo señala hacia abajo: "interactúa aquí"
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex
