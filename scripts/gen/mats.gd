class_name Mats
extends RefCounted
## Materiales compartidos. El shader "toon" lee el color por vértice (alfa = emisión)
## y admite destello de golpe, escarcha y quemadura sin añadir llamadas de dibujo.

const CHAR_SHADER_CODE := """
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
uniform vec4 tint : source_color = vec4(1.0);
uniform float flash = 0.0;
uniform float frost = 0.0;
uniform float burn = 0.0;
uniform float rim_power = 2.6;
uniform float rim_amount = 0.22;
uniform float emit_boost = 1.4;

vec3 to_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) / vec3(1.055), vec3(2.4)), c / vec3(12.92), lessThan(c, vec3(0.04045)));
}

void fragment() {
	vec3 base = to_linear(COLOR.rgb) * tint.rgb;
	base = mix(base, vec3(0.45, 0.75, 1.0), frost * 0.6);
	base = mix(base, vec3(1.0, 0.4, 0.08), burn * 0.35);
	ALBEDO = mix(base, vec3(1.0), flash);
	ROUGHNESS = 0.82;
	SPECULAR = 0.25;
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), rim_power);
	EMISSION = base * COLOR.a * emit_boost + vec3(flash) * 0.7 + vec3(1.0, 0.35, 0.05) * burn * 0.18 + base * rim * rim_amount;
}
"""

static var _shader: Shader
static var _world_mat: ShaderMaterial
static var _fx_cache: Dictionary = {}


static func shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = CHAR_SHADER_CODE
	return _shader


## Material único por personaje (permite destello/escarcha independientes).
static func char_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader()
	return m


## Material compartido para escenarios estáticos.
static func world_material() -> ShaderMaterial:
	if _world_mat == null:
		_world_mat = ShaderMaterial.new()
		_world_mat.shader = shader()
		_world_mat.set_shader_parameter("rim_amount", 0.08)
	return _world_mat


## Material sin sombreado, translúcido, para efectos (anillos, telegrafías, destellos).
static func fx_material(color: Color, additive := false) -> StandardMaterial3D:
	var key := "%s_%s" % [color.to_html(true), additive]
	if _fx_cache.has(key):
		return _fx_cache[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = color
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.no_depth_test = false
	_fx_cache[key] = m
	return m


static func mesh_instance(mesh: Mesh, mat: Material, parent: Node = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if parent != null:
		parent.add_child(mi)
	return mi
