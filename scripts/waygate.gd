class_name Waygate
extends Node3D
## A waygate: the portal a sub-boss drops where it dies (SubBosses). Smaller than the end-of-map
## BossPortal and nothing like it: a mossy trilithon of two standing stones and a lintel, about
## 2.9 m tall, carved with runes, in a ring of half-sunk stones. Its states:
##   - inactive (its partner hasn't dropped yet): dark, runes faint, no swirl. Come within
##     HINT_DIST and a floating text says "Needs another portal to activate".
##   - active: runes glow blue-green, a swirling vortex fills the arch, a light and a hum.
##     Near it, "Press E" (ActivatePrompt); SubBosses teleports you to the partner gate.
##   - cooldown (after any use, both gates): dimmed, the swirl faint, and the floating text counts
##     down ("Recharging 1:12"); E does nothing.
##   - closing (the map boss died / the run ended): it fades and sinks away, then frees itself.
## In the "waygate" group (the minimap draws it).

const HEIGHT := 2.9
const PILLAR_X := 1.12
const OPEN_W := 1.7          # the vortex inside the arch
const OPEN_H := 2.3
const OPEN_C := 1.25
const ARRIVE := 2.6          # you land this far in front of it
const HINT_DIST := 4.0
const USE_DIST := 3.4
const RISE_TIME := 1.2
const CLOSE_TIME := 1.4
const CLEAR_R := 2.0         # the spot must be clear of props this far round
const RUNE := Color(0.3, 1.0, 0.85)
const FLAT_R := 2.2

var state := "inactive"      # inactive | active | cooldown | closing
var partner: Waygate
var cooldown_left := 0.0
var _t := 0.0                # since it was dropped
var _close_t := 0.0
var _power := 0.0            # 0 dark .. 1 fully lit (eased toward the state's level)
var _frame: Node3D
var _rune_mat: ShaderMaterial
var _vortex_mat: ShaderMaterial
var _vortex: MeshInstance3D
var _light: OmniLight3D
var _swirl: GPUParticles3D
var _text: Label3D
var prompt: ActivatePrompt
var _hum: AudioStreamPlayer3D
var _sfx_rise: AudioStreamPlayer3D
var _sfx_on: AudioStreamPlayer3D
var _fx: FxManager


func _init() -> void:
	add_to_group("waygate")


func setup(p_fx: FxManager) -> void:
	_fx = p_fx


func _ready() -> void:
	_frame = Node3D.new()
	add_child(_frame)
	_build_frame()
	_build_vortex()
	_light = OmniLight3D.new()
	_light.light_color = RUNE
	_light.light_energy = 0.0
	_light.omni_range = 9.0
	_light.position = Vector3(0, OPEN_C, 0.9)
	add_child(_light)
	_build_swirl()
	_text = Label3D.new()
	_text.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_text.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_text.no_depth_test = true
	_text.render_priority = 10
	_text.font_size = 38
	_text.outline_size = 10
	_text.pixel_size = 0.008
	_text.modulate = Color(0.75, 1.0, 0.95)
	_text.outline_modulate = Color(0.02, 0.05, 0.05)
	_text.position.y = HEIGHT + 0.55
	_text.visible = false
	add_child(_text)
	prompt = ActivatePrompt.new()
	prompt.position.y = HEIGHT + 0.55
	add_child(prompt)
	_sfx_rise = _sound("res://audio/subboss/gate_rise.wav", 0.0)
	_sfx_on = _sound("res://audio/subboss/gate_activate.wav", 0.0)
	_hum = _sound("res://audio/subboss/gate_hum.wav", -10.0)
	if _hum.stream is AudioStreamWAV:
		var w := (_hum.stream as AudioStreamWAV).duplicate() as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate)
		_hum.stream = w
	_frame.position.y = -HEIGHT - 0.3
	if _sfx_rise.stream:
		_sfx_rise.play()
	_apply_power(0.0)


func _sound(path: String, db: float) -> AudioStreamPlayer3D:
	var a := AudioStreamPlayer3D.new()
	a.bus = Settings.SFX_BUS
	a.unit_size = 12.0
	a.max_distance = 70.0
	a.volume_db = db
	a.position.y = OPEN_C
	if ResourceLoader.exists(path):
		a.stream = load(path)
	add_child(a)
	return a


# ------------------------------------------------------------------ state

func is_active() -> bool:
	return state == "active"


## Both gates are down: light up (with a flare and a sound).
func activate() -> void:
	if state == "closing":
		return
	state = "active"
	if _sfx_on.stream:
		_sfx_on.play()
	if _hum.stream and not _hum.playing:
		_hum.play()
	if _fx != null:
		_fx.burst(global_position + Vector3(0, OPEN_C, 0), 3.5, RUNE, 0.5)


## Used: dim for `secs` (the shared cooldown), then glow again.
func start_cooldown(secs: float) -> void:
	if state == "closing":
		return
	state = "cooldown"
	cooldown_left = secs


## The map is done: fade and sink away, then free.
func close() -> void:
	if state == "closing":
		return
	state = "closing"
	_close_t = 0.0
	remove_from_group("waygate")
	prompt.visible = false
	_text.visible = false
	if _hum.playing:
		_hum.stop()


## Where you land when you come through to this gate: in front of it, facing away.
func arrival() -> Vector3:
	return global_position + global_transform.basis.z * ARRIVE


func front() -> Vector3:
	return global_transform.basis.z


## The floating text for the gate's state (empty: none).
func status_text() -> String:
	match state:
		"inactive":
			return tr("Needs another portal to activate")
		"cooldown":
			var s := int(ceilf(cooldown_left))
			return tr("Recharging %d:%02d") % [s / 60, s % 60]
	return ""


func _physics_process(dt: float) -> void:
	_t += dt
	var k := clampf(_t / RISE_TIME, 0.0, 1.0)
	if state != "closing":
		_frame.position.y = (-HEIGHT - 0.3) * (1.0 - (1.0 - pow(1.0 - k, 3.0)))
		_frame.position.x = sin(_t * 41.0) * 0.03 * (1.0 - k)
	if _fx != null and k < 1.0 and fmod(_t, 0.2) < dt:
		var a := randf() * TAU
		_fx.burst(global_position + Vector3(cos(a) * 1.8, 0.2, sin(a) * 1.8), 1.2, Color(0.4, 0.34, 0.24), 0.45)
	if state == "cooldown":
		cooldown_left -= dt
		if cooldown_left <= 0.0:
			cooldown_left = 0.0
			state = "active"
			if _fx != null:
				_fx.burst(global_position + Vector3(0, OPEN_C, 0), 2.5, RUNE, 0.4)
	var want := 0.0
	match state:
		"active":
			want = 1.0
		"cooldown":
			want = 0.28
	if state == "closing":
		_close_t += dt
		var c := clampf(_close_t / CLOSE_TIME, 0.0, 1.0)
		_power = _power * (1.0 - c)
		_frame.position.y = -(HEIGHT + 0.3) * c * c
		_apply_power(_power)
		if c >= 1.0:
			queue_free()
		return
	_power = move_toward(_power, want, dt * 1.5)
	_apply_power(_power)


## Show the floating text / the prompt for a player `d` metres away.
func show_for(d: float) -> void:
	if state == "closing":
		return
	var s := status_text()
	_text.visible = s != "" and d < (HINT_DIST if state == "inactive" else HINT_DIST + 4.0)
	if _text.visible:
		_text.text = s
	prompt.visible = state == "active" and d < USE_DIST


func text_visible() -> bool:
	return _text.visible


func _apply_power(v: float) -> void:
	var base := 0.12 if state == "inactive" else 0.35
	_rune_mat.set_shader_parameter("glow", base + 2.4 * v)
	_vortex_mat.set_shader_parameter("open", maxf(v, 0.001))
	_vortex.visible = v > 0.02
	_light.light_energy = 0.15 + 2.6 * v + (0.4 * sin(Time.get_ticks_msec() * 0.004) if v > 0.9 else 0.0)
	_swirl.emitting = v > 0.5


# ------------------------------------------------------------------ placement

## Nearest flat, dry, open spot to `at` (spiralling out), at least 8 m from each of `avoid`.
static func find_spot(main: Node, at: Vector3, avoid: Array) -> Vector3:
	for ring in 20:
		var r := ring * 1.5
		var n := 1 if ring == 0 else 6 + ring * 2
		for k in n:
			var a := TAU * float(k) / float(n) + ring * 0.41
			var q := Vector2(at.x, at.z) + Vector2(cos(a), sin(a)) * r
			if is_clear(main, q, avoid):
				return Vector3(q.x, main.water.ground_height(q.x, q.y), q.y)
	return Vector3(at.x, main.water.ground_height(at.x, at.z), at.z)


## Flat, dry ground with nothing standing within CLEAR_R (props, walls, chests, other gates).
static func is_clear(main: Node, q: Vector2, avoid: Array) -> bool:
	var half: float = main.ARENA_HALF - 12.0
	if absf(q.x) > half or absf(q.y) > half:
		return false
	var water: SwampWater = main.water
	if not CalderaBuilder.active and water.near_pool(q.x, q.y, CLEAR_R + 0.5):
		return false
	if CalderaBuilder.active and CalderaBuilder.near_lava(q.x, q.y, CLEAR_R + 2.0):
		return false
	var h0 := water.ground_height(q.x, q.y)
	for k in 8:
		var a := TAU * k / 8.0
		if absf(water.ground_height(q.x + cos(a) * FLAT_R, q.y + sin(a) * FLAT_R) - h0) > 0.5:
			return false
	if CastleNav.current != null:
		for dz in range(-3, 4, 2):
			for dx in range(-3, 4, 2):
				if CastleNav.current.is_blocked(q.x + dx, q.y + dz):
					return false
	for o in avoid:
		var v: Vector3 = o
		if Vector2(v.x - q.x, v.z - q.y).length() < 8.0:
			return false
	if main.chests != null:
		for c in main.chests.chests:
			if is_instance_valid(c) and Vector2(c.global_position.x - q.x, c.global_position.z - q.y).length() < CLEAR_R + 2.5:
				return false
	var space: PhysicsDirectSpaceState3D = (main as Node3D).get_world_3d().direct_space_state
	var params := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(CLEAR_R * 2.0, 3.0, CLEAR_R * 2.0 + ARRIVE)
	params.shape = box
	params.transform = Transform3D(Basis(), Vector3(q.x, h0 + 0.6 + 1.5, q.y))
	params.collide_with_areas = false
	if main.player != null:
		params.exclude = [main.player.get_rid()]
	return space.intersect_shape(params, 1).is_empty()


# ------------------------------------------------------------------ the look

func _build_frame() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var stone := MeshBuilder.new()
	var rune := MeshBuilder.new()
	var grey := Color(0.42, 0.44, 0.4, 0.0)
	var moss := Color(0.22, 0.36, 0.14, 0.0)
	# two standing stones, each a stack of rough blocks leaning in a touch, mossy at the foot
	for sx in [-1.0, 1.0]:
		var y := 0.0
		for b in 3:
			var h := [0.95, 0.8, 0.7][b] as float
			var w := 0.6 - b * 0.05
			var col := grey.lerp(Color(0.5, 0.5, 0.46, 0.0), rng.randf()) * rng.randf_range(0.85, 1.05)
			col.a = 0.0
			var bs := Basis(Vector3.BACK, sx * 0.025 + rng.randf_range(-0.02, 0.02)).rotated(Vector3.UP, rng.randf_range(-0.08, 0.08))
			stone.add(MeshBuilder.box(Vector3(w, h, 0.52)), Transform3D(bs, Vector3(sx * PILLAR_X, y + h * 0.5, 0)), col)
			y += h
		stone.add(MeshBuilder.cyl(0.42, 0.5, 0.35, 8), Transform3D(Basis(), Vector3(sx * PILLAR_X, 0.12, 0)), moss)
		# moss drips down the outer face
		for m in 3:
			stone.add(MeshBuilder.box(Vector3(0.08, rng.randf_range(0.3, 0.7), 0.54)), Transform3D(Basis(), Vector3(sx * (PILLAR_X + 0.27), rng.randf_range(0.6, 1.8), rng.randf_range(-0.05, 0.05))), moss)
		# runes down the inner faces and the fronts
		for r in 5:
			var ry := 0.35 + r * 0.42
			for face in [1.0, -1.0]:
				var off := Vector3(sx * PILLAR_X, ry, face * 0.27)
				rune.add(MeshBuilder.box(Vector3(0.06, 0.2, 0.02)), Transform3D(Basis(Vector3.BACK, 0.3 * (r % 2 * 2 - 1)), off), RUNE)
				rune.add(MeshBuilder.box(Vector3(0.18, 0.04, 0.02)), Transform3D(Basis(), off + Vector3(0, 0.07 if r % 2 else -0.07, 0)), RUNE)
	# the lintel across the top, with a glowing carved eye
	stone.add(MeshBuilder.box(Vector3(PILLAR_X * 2.0 + 0.9, 0.42, 0.6)), Transform3D(Basis(Vector3.BACK, 0.02), Vector3(0, HEIGHT - 0.24, 0)), grey.darkened(0.08))
	stone.add(MeshBuilder.box(Vector3(PILLAR_X * 2.0 + 0.5, 0.1, 0.64)), Transform3D(Basis(), Vector3(0, HEIGHT - 0.02, 0)), moss)
	for face in [1.0, -1.0]:
		rune.add(MeshBuilder.cyl(0.12, 0.12, 0.02, 10), Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, HEIGHT - 0.24, face * 0.31)), RUNE)
		for k in 6:
			var x := -1.0 + k * 0.4
			if absf(x) < 0.2:
				continue
			rune.add(MeshBuilder.box(Vector3(0.14, 0.05, 0.02)), Transform3D(Basis(Vector3.BACK, 0.5 * (k % 2 * 2 - 1)), Vector3(x, HEIGHT - 0.24, face * 0.31)), RUNE)
	# a ring of half-sunk mossy stones round it, and rune chips glowing between them
	for k in 9:
		var a := TAU * k / 9.0 + 0.2
		var r := 2.2 + rng.randf_range(-0.1, 0.15)
		var s := rng.randf_range(0.25, 0.4)
		var col := grey.lerp(moss, rng.randf_range(0.2, 0.7))
		col.a = 0.0
		stone.add(MeshBuilder.sphere(s, 7, 4), Transform3D(Basis().scaled(Vector3(1.0, 0.6, 0.9)).rotated(Vector3.UP, a), Vector3(cos(a) * r, s * 0.15, sin(a) * r)), col)
		var a2 := a + TAU / 18.0
		rune.add(MeshBuilder.box(Vector3(0.18, 0.03, 0.06)), Transform3D(Basis(Vector3.UP, -a2), Vector3(cos(a2) * 2.0, 0.05, sin(a2) * 2.0)), RUNE)
	var mi := MeshInstance3D.new()
	mi.mesh = stone.commit(MeshBuilder.prop_material())
	_rune_mat = MeshBuilder.glow_material().duplicate() as ShaderMaterial
	rune.commit_into(mi.mesh as ArrayMesh, _rune_mat)
	_frame.add_child(mi)
	# the standing stones are solid; you use it from the front
	var body := StaticBody3D.new()
	for sx in [-1.0, 1.0]:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.6, HEIGHT - 0.4, 0.52)
		cs.shape = bs
		cs.position = Vector3(sx * PILLAR_X, (HEIGHT - 0.4) * 0.5, 0)
		body.add_child(cs)
	_frame.add_child(body)


func _build_vortex() -> void:
	var q := QuadMesh.new()
	q.size = Vector2(OPEN_W, OPEN_H)
	var sh := Shader.new()
	sh.code = BossPortal.VORTEX_SHADER
	_vortex_mat = ShaderMaterial.new()
	_vortex_mat.shader = sh
	_vortex_mat.set_shader_parameter("col_a", Color(0.02, 0.18, 0.2))
	_vortex_mat.set_shader_parameter("col_b", Color(0.2, 0.85, 0.7))
	_vortex_mat.set_shader_parameter("col_c", Color(0.55, 0.85, 1.0))
	q.material = _vortex_mat
	_vortex = MeshInstance3D.new()
	_vortex.mesh = q
	_vortex.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vortex.position = Vector3(0, OPEN_C, 0)
	_frame.add_child(_vortex)


func _build_swirl() -> void:
	_swirl = GPUParticles3D.new()
	_swirl.amount = 36
	_swirl.lifetime = 1.6
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(OPEN_W * 0.45, OPEN_H * 0.45, 0.1)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 30.0
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.6
	pm.gravity = Vector3(0, 0.3, 0)
	pm.tangential_accel_min = 0.5
	pm.tangential_accel_max = 1.2
	var g := Gradient.new()
	g.set_color(0, Color(0.5, 1.0, 0.9, 0.0))
	g.add_point(0.3, Color(0.45, 1.0, 0.85, 1.0))
	g.set_color(g.get_point_count() - 1, Color(0.4, 0.8, 1.0, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	_swirl.process_material = pm
	_swirl.draw_pass_1 = BossPortal._spark_mesh(0.06)
	_swirl.position = Vector3(0, OPEN_C, 0)
	_swirl.emitting = false
	_frame.add_child(_swirl)
