class_name GraveyardAmbience
extends Node3D
## Life (of a sort) in the Haunted Graveyard:
##   - WILL-O'-WISPS: pale blue-green ghost-lights drifting low over graves, round the crypt doors
##     and under the trees, bobbing, pulsing and wandering about their haunts.
##   - Lantern and candle LIGHTS flicker (every OmniLight in the grave_light group).
##   - CROWS circle high overhead, wings flapping, and caw now and then; more caws from the
##     headstones round you.
##   - The chapel BELL tolls, far off, every minute or so.

const WISPS := 56
const FLYING_CROWS := 7
const WISP_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 tint : source_color = vec4(0.45, 1.0, 0.85, 1.0);
varying float pulse;
void vertex() {
	// a camera-facing halo with the instance's scale
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
	pulse = INSTANCE_CUSTOM.r;
}
void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float core = 1.0 - smoothstep(0.0, 0.18, d);
	float halo = pow(max(1.0 - d, 0.0), 2.6);
	ALBEDO = tint.rgb * (halo * 0.9 + core * 2.5) * pulse;
}
"""

var wisps: int = 0
var _homes: Array[Vector3] = []
var _phase := PackedFloat32Array()
var _range := PackedFloat32Array()
var _home_i := PackedInt32Array()
var _wander := PackedVector3Array()
var _mm: MultiMesh
var _lights: Array[OmniLight3D] = []
var _crow_mm: MultiMesh
var _crow_c := PackedVector3Array()
var _crow_r := PackedFloat32Array()
var _crow_s := PackedFloat32Array()
var _t := 0.0
var _bell_t := 25.0
var _caw_t := 6.0
var _chapel := Vector3.INF
var _bell: AudioStreamPlayer3D
var _caw: Array[AudioStreamPlayer3D] = []
var _caws: Array[AudioStream] = []
var bell_tolls := 0                     # for tests
var _rng := RandomNumberGenerator.new()


func setup(rng: RandomNumberGenerator, homes: Array[Vector3], lights: Array[OmniLight3D], chapel: Vector3, half: float) -> void:
	_rng.seed = rng.randi()
	_homes = homes.duplicate()
	while _homes.size() < 12:
		_homes.append(Vector3(_rng.randf_range(-half * 0.8, half * 0.8), 0, _rng.randf_range(-half * 0.8, half * 0.8)))
	_lights = lights
	_chapel = chapel
	wisps = WISPS
	for k in wisps:
		_home_i.append(k % _homes.size())
		_phase.append(_rng.randf() * TAU)
		_range.append(_rng.randf_range(2.0, 7.0))
		_wander.append(Vector3.ZERO)
	for k in FLYING_CROWS:
		var c := Vector3(_rng.randf_range(-half * 0.7, half * 0.7), 0, _rng.randf_range(-half * 0.7, half * 0.7))
		c.y = SwampWater.height_at(c.x, c.z) + _rng.randf_range(22.0, 38.0)
		_crow_c.append(c)
		_crow_r.append(_rng.randf_range(10.0, 26.0))
		_crow_s.append(_rng.randf_range(0.25, 0.45) * (1.0 if _rng.randf() < 0.5 else -1.0))


func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var sh := Shader.new()
	sh.code = WISP_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	quad.material = m
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_custom_data = true
	_mm.mesh = quad
	_mm.instance_count = maxi(wisps, 1)
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = _mm
	mi.name = "Wisps"   # no-i18n
	mi.custom_aabb = AABB(Vector3(-300, -50, -300), Vector3(600, 150, 600))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_crow_mm = MultiMesh.new()
	_crow_mm.transform_format = MultiMesh.TRANSFORM_3D
	_crow_mm.mesh = GraveyardProps.crow(true)
	_crow_mm.instance_count = FLYING_CROWS
	var ci := MultiMeshInstance3D.new()
	ci.multimesh = _crow_mm
	ci.material_override = GraveyardProps.crow_material(true)
	ci.custom_aabb = AABB(Vector3(-300, -50, -300), Vector3(600, 200, 600))
	ci.name = "Crows"   # no-i18n
	add_child(ci)
	_bell = _player("res://audio/graveyard/bell_toll.wav", 60.0, -2.0)
	for k in 2:
		_caw.append(_player("", 14.0, -6.0))
	for path in ["res://audio/graveyard/crow_caw_1.wav", "res://audio/graveyard/crow_caw_2.wav"]:
		if ResourceLoader.exists(path):
			_caws.append(load(path))
	_tick(0.0)


func _player(path: String, unit: float, db: float) -> AudioStreamPlayer3D:
	var a := AudioStreamPlayer3D.new()
	a.bus = Settings.SFX_BUS
	a.unit_size = unit
	a.max_distance = 400.0
	a.volume_db = db
	if path != "" and ResourceLoader.exists(path):
		a.stream = load(path)
	add_child(a)
	return a


func _process(dt: float) -> void:
	if get_tree().paused:
		return
	_tick(dt)


func _tick(dt: float) -> void:
	_t += dt
	# wisps drift about their haunts, bob and pulse; now and then one wanders off a way
	for k in wisps:
		var h: Vector3 = _homes[_home_i[k]]
		var ph := _phase[k]
		var r := _range[k]
		if _rng.randf() < dt * 0.05:
			_wander[k] = Vector3(_rng.randf_range(-8, 8), 0, _rng.randf_range(-8, 8))
		var w := _wander[k] * clampf(sin(_t * 0.1 + ph) * 0.5 + 0.5, 0.0, 1.0)
		var p := h + w + Vector3(sin(_t * 0.31 + ph) * r, 0.0, cos(_t * 0.23 + ph * 1.7) * r)
		p.y = SwampWater.height_at(p.x, p.z) + 0.7 + 0.45 * sin(_t * 0.9 + ph * 2.3) + 0.25 * sin(_t * 2.1 + ph)
		var pulse := 0.65 + 0.35 * sin(_t * 3.0 + ph * 5.0) + 0.15 * sin(_t * 11.0 + ph)
		var s := 0.55 + 0.15 * sin(_t * 2.0 + ph)
		_mm.set_instance_transform(k, Transform3D(Basis.from_scale(Vector3.ONE * s), p))
		_mm.set_instance_custom_data(k, Color(clampf(pulse, 0.1, 1.3), 0, 0, 0))
	# flickering lanterns and candles
	for l in _lights:
		if is_instance_valid(l):
			var b: float = l.get_meta("base", 1.0)
			var hsh := float(l.get_instance_id() % 97)
			l.light_energy = b * (0.82 + 0.1 * sin(_t * 7.3 + hsh) + 0.08 * sin(_t * 17.0 + hsh * 2.0))
	# crows wheeling overhead
	for k in FLYING_CROWS:
		var a := _t * _crow_s[k] + k * 1.7
		var c := _crow_c[k]
		var p := c + Vector3(cos(a), 0.0, sin(a)) * _crow_r[k] + Vector3(0, sin(_t * 0.5 + k) * 2.0, 0)
		var tangent := Vector3(-sin(a), 0, cos(a)) * signf(_crow_s[k])
		var basis := Basis.looking_at(-tangent, Vector3.UP).scaled(Vector3.ONE * 2.2)
		_crow_mm.set_instance_transform(k, Transform3D(basis, p))
	if dt <= 0.0:
		return
	# the bell tolls three times, far off
	_bell_t -= dt
	if _bell_t <= 0.0:
		_bell_t = _rng.randf_range(55.0, 80.0)
		if _bell.stream != null:
			_bell.global_position = _chapel if _chapel != Vector3.INF else Vector3(0, 20, 0)
			_bell.play()
		bell_tolls += 1
	# caws
	_caw_t -= dt
	if _caw_t <= 0.0:
		_caw_t = _rng.randf_range(5.0, 14.0)
		var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
		if cam != null and not _caws.is_empty():
			var a := _caw[_rng.randi() % _caw.size()]
			a.stream = _caws[_rng.randi() % _caws.size()]
			a.pitch_scale = _rng.randf_range(0.85, 1.15)
			var k := _rng.randi() % FLYING_CROWS
			var src := cam.global_position + Vector3(_rng.randf_range(-25, 25), _rng.randf_range(2, 10), _rng.randf_range(-25, 25))
			if _rng.randf() < 0.4:
				src = _crow_mm.get_instance_transform(k).origin
			a.global_position = src
			a.play()
