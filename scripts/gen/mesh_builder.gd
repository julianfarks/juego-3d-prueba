class_name MeshBuilder
extends RefCounted
## Constructor de mallas low-poly procedurales con sombreado plano (flat) y color por vértice.
## El canal alfa del color indica emisión (0 = normal, 1 = brillo total) y lo interpreta el
## shader de personajes/mundo. Así una pieza entera es UNA sola malla y UNA sola llamada de dibujo.

var _v := PackedVector3Array()
var _n := PackedVector3Array()
var _c := PackedColorArray()


static func xf(pos := Vector3.ZERO, rot_deg := Vector3.ZERO, scl := Vector3.ONE) -> Transform3D:
	var b := Basis.from_euler(Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z)))
	b = b.scaled(scl)
	return Transform3D(b, pos)


static func glow(c: Color, amount := 1.0) -> Color:
	return Color(c.r, c.g, c.b, clampf(amount, 0.0, 1.0))


func is_empty() -> bool:
	return _v.is_empty()


func tri(a: Vector3, b: Vector3, c: Vector3, hint: Vector3, col: Color) -> void:
	var cr := (b - a).cross(c - a)
	if cr.length_squared() < 1e-10:
		return
	var n := -cr.normalized()
	var center := (a + b + c) / 3.0
	if n.dot(center - hint) < 0.0:
		var t := b
		b = c
		c = t
		n = -n
	_v.append(a)
	_v.append(b)
	_v.append(c)
	_n.append(n)
	_n.append(n)
	_n.append(n)
	_c.append(col)
	_c.append(col)
	_c.append(col)


func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, hint: Vector3, col: Color) -> void:
	tri(a, b, c, hint, col)
	tri(a, c, d, hint, col)


## Caja centrada en el origen del transform.
func box(size: Vector3, t: Transform3D, col: Color) -> void:
	var h := size * 0.5
	var p: Array[Vector3] = []
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				p.append(t * Vector3(h.x * sx, h.y * sy, h.z * sz))
	# índices: x(0/1)*4 + y(0/1)*2 + z(0/1)
	var hint := t.origin
	quad(p[0], p[1], p[3], p[2], hint, col)  # -x
	quad(p[4], p[5], p[7], p[6], hint, col)  # +x
	quad(p[0], p[1], p[5], p[4], hint, col)  # -y
	quad(p[2], p[3], p[7], p[6], hint, col)  # +y
	quad(p[0], p[2], p[6], p[4], hint, col)  # -z
	quad(p[1], p[3], p[7], p[5], hint, col)  # +z


## Tronco de pirámide rectangular centrado: base (abajo) y tope (arriba) con tamaño XZ propio.
func frustum(bottom: Vector2, top: Vector2, height: float, t: Transform3D, col: Color) -> void:
	var hy := height * 0.5
	var b := [
		t * Vector3(-bottom.x * 0.5, -hy, -bottom.y * 0.5), t * Vector3(bottom.x * 0.5, -hy, -bottom.y * 0.5),
		t * Vector3(bottom.x * 0.5, -hy, bottom.y * 0.5), t * Vector3(-bottom.x * 0.5, -hy, bottom.y * 0.5),
	]
	var tp := [
		t * Vector3(-top.x * 0.5, hy, -top.y * 0.5), t * Vector3(top.x * 0.5, hy, -top.y * 0.5),
		t * Vector3(top.x * 0.5, hy, top.y * 0.5), t * Vector3(-top.x * 0.5, hy, top.y * 0.5),
	]
	var hint := t.origin
	quad(b[0], b[1], b[2], b[3], hint, col)
	quad(tp[0], tp[1], tp[2], tp[3], hint, col)
	for i in 4:
		var j := (i + 1) % 4
		quad(b[i], b[j], tp[j], tp[i], hint, col)


## Cilindro / cono (r_top = 0) a lo largo de Y, centrado.
func cylinder(r_top: float, r_bottom: float, height: float, seg: int, t: Transform3D, col: Color, caps := true) -> void:
	var hy := height * 0.5
	var hint := t.origin
	var top_c := t * Vector3(0, hy, 0)
	var bot_c := t * Vector3(0, -hy, 0)
	for i in seg:
		var a0 := TAU * float(i) / seg
		var a1 := TAU * float(i + 1) / seg
		var tb0 := t * Vector3(cos(a0) * r_top, hy, sin(a0) * r_top)
		var tb1 := t * Vector3(cos(a1) * r_top, hy, sin(a1) * r_top)
		var bb0 := t * Vector3(cos(a0) * r_bottom, -hy, sin(a0) * r_bottom)
		var bb1 := t * Vector3(cos(a1) * r_bottom, -hy, sin(a1) * r_bottom)
		quad(bb0, bb1, tb1, tb0, hint, col)
		if caps:
			tri(top_c, tb0, tb1, hint, col)
			tri(bot_c, bb0, bb1, hint, col)


## Esfera low-poly (UV). Con 'scale' en el transform se obtienen elipsoides.
func sphere(radius: float, seg: int, rings: int, t: Transform3D, col: Color) -> void:
	var hint := t.origin
	for r in rings:
		var p0 := PI * float(r) / rings
		var p1 := PI * float(r + 1) / rings
		for i in seg:
			var a0 := TAU * float(i) / seg
			var a1 := TAU * float(i + 1) / seg
			var v00 := t * (Vector3(sin(p0) * cos(a0), cos(p0), sin(p0) * sin(a0)) * radius)
			var v01 := t * (Vector3(sin(p0) * cos(a1), cos(p0), sin(p0) * sin(a1)) * radius)
			var v10 := t * (Vector3(sin(p1) * cos(a0), cos(p1), sin(p1) * sin(a0)) * radius)
			var v11 := t * (Vector3(sin(p1) * cos(a1), cos(p1), sin(p1) * sin(a1)) * radius)
			quad(v00, v01, v11, v10, hint, col)


## Cuña triangular (rampa/tejado): base rectangular size.x * size.z, altura size.y en el borde -z..+z.
func wedge(size: Vector3, t: Transform3D, col: Color) -> void:
	var h := size * 0.5
	# triángulo en el plano YZ, extruido en X: (y=-h, z=-h) (y=-h, z=+h) (y=+h, z=-h)
	var pts := [Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, -h.y, h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, -h.z)]
	var p: Array[Vector3] = []
	for v in pts:
		p.append(t * v)
	var hint := t * Vector3(0, -h.y / 3.0, -h.z / 3.0)  # centroide del prisma triangular
	tri(p[0], p[1], p[2], hint, col)
	tri(p[3], p[4], p[5], hint, col)
	quad(p[0], p[1], p[4], p[3], hint, col)  # base
	quad(p[0], p[2], p[5], p[3], hint, col)  # cara vertical
	quad(p[1], p[2], p[5], p[4], hint, col)  # pendiente


func build() -> ArrayMesh:
	if _v.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _v
	arrays[Mesh.ARRAY_NORMAL] = _n
	arrays[Mesh.ARRAY_COLOR] = _c
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


func triangle_count() -> int:
	return _v.size() / 3
