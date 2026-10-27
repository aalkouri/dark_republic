class_name Shrine
extends Node3D
## A shrine challenge. Stand inside the 5-yard zone for 10 seconds (leaving resets the timer)
## while dodging the shrine's damage pattern; completing it spawns a chest whose tier matches
## the difficulty (1 Bronze, 2 Silver, 3 Gold).
##
## Pattern CHAINS - chains swing around the shrine at shin height (jump over them):
##   D1  1 plain iron chain, 1 yd long          hit: 10% max HP
##   D2  2 burning chains, 3 yd long            hit: burn (5% max HP/s for 2 s, doesn't stack)
##   D3  3 burning chains, the full zone + the shrine itself is on fire (touching it burns)
## Pattern NOVA - rings of electricity crawl outward along the ground (jump over them):
##   D1  one ring every 2 s;  D2  two rings 0.5 s apart every 2 s;  D3  a ring every 0.5 s
##   hit: 8% max HP

signal completed(shrine: Shrine)

enum { CHAINS, NOVA }

const YARD := 0.9144
const ZONE_RADIUS := 5.0 * YARD
const REQUIRED_TIME := 10.0
const PILLAR_RADIUS := 0.55
const TIER_NAMES := ["Bronze", "Silver", "Gold"]
const TIER_COLORS := [Color(0.85, 0.5, 0.22), Color(0.82, 0.86, 0.95), Color(1.0, 0.82, 0.2)]

# Chains
const CHAIN_LENGTHS := [1.0 * YARD, 3.0 * YARD, ZONE_RADIUS - PILLAR_RADIUS]
const CHAIN_SPEEDS := [1.2, 1.35, 1.5]      # rad/s
const CHAIN_HEIGHT := 0.45                   # above the ground; jump over
const CHAIN_HIT_RADIUS := 0.12               # chain thickness for hit tests
const CHAIN_HIT_FRAC := 0.10
const SHRINE_FIRE_REACH := 0.75              # D3: touching the burning shrine
# Nova
const NOVA_SPEED := 1.5                      # m/s - slow
const NOVA_PERIOD := 2.0
const NOVA_HALF_WIDTH := 0.3
const NOVA_HEIGHT := 0.35                    # hits feet below this; jump over
const NOVA_HIT_FRAC := 0.08
const PLAYER_RADIUS := 0.4

var pattern := CHAINS
var difficulty := 1
var progress := 0.0
var done := false
var player_inside := false

var _t := 0.0
var _chains: Array[Node3D] = []
var _chain_angle := 0.0
var _novas := PackedFloat32Array()   # radii of live rings
var _nova_nodes: Array[MeshInstance3D] = []
var _next_pulse := 0.0
var _pulse_idx := 0
var _pulse_cycle := 0
var _zone_mat: ShaderMaterial
var _label: Label3D
var _fx_root: Node3D
var _shrine_fire: CPUParticles3D

const ZONE_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec3 col : source_color = vec3(1.0, 0.8, 0.2);
uniform float progress = 0.0;
uniform float inside = 0.0;
void fragment() {
	vec2 c = UV * 2.0 - 1.0;
	float d = length(c);
	if (d > 1.0) { discard; }
	float ang = (atan(c.y, c.x) + PI) / (2.0 * PI);
	float rim = smoothstep(0.94, 0.97, d) * (1.0 - smoothstep(0.985, 1.0, d));
	float band = smoothstep(0.86, 0.885, d) * (1.0 - smoothstep(0.925, 0.94, d));
	float fill = band * step(ang, progress);
	ALBEDO = col * (1.0 + fill);
	ALPHA = 0.05 + 0.06 * inside + rim * 0.85 + band * 0.18 + fill * 0.8;
}
"""


func setup(p_pattern: int, p_difficulty: int) -> void:
	pattern = p_pattern
	difficulty = clampi(p_difficulty, 1, 3)


func tier_name() -> String:
	return TIER_NAMES[difficulty - 1]


func _ready() -> void:
	var tier_col: Color = TIER_COLORS[difficulty - 1]
	_build_pillar(tier_col)
	_build_zone(tier_col)
	_fx_root = Node3D.new()
	add_child(_fx_root)
	if pattern == CHAINS:
		_build_chains()
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 56
	_label.outline_size = 12
	_label.pixel_size = 0.008
	_label.position.y = 3.6
	_label.modulate = tier_col
	_label.no_depth_test = true
	add_child(_label)
	_update_label()


# ------------------------------------------------------------------ build

func _build_pillar(tier_col: Color) -> void:
	var body := StaticBody3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = PILLAR_RADIUS
	shape.height = 2.2
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = 1.1
	body.add_child(cs)
	add_child(body)
	var mb := MeshBuilder.new()
	var stone := Color(0.36, 0.37, 0.34, 0.0)
	var moss := Color(0.28, 0.36, 0.14, 0.0)
	mb.add(MeshBuilder.cyl(0.9, 1.0, 0.3, 10), Transform3D(Basis(), Vector3(0, 0.15, 0)), stone)
	mb.add(MeshBuilder.cyl(PILLAR_RADIUS * 0.85, PILLAR_RADIUS, 2.0, 8), Transform3D(Basis(), Vector3(0, 1.3, 0)), stone)
	mb.add(MeshBuilder.cyl(0.7, 0.62, 0.22, 8), Transform3D(Basis(), Vector3(0, 2.38, 0)), stone)
	mb.add(MeshBuilder.sphere(0.95, 10, 4), Transform3D(Basis.from_scale(Vector3(1.0, 0.18, 1.0)), Vector3(0, 0.3, 0)), moss)
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit()
	add_child(mi)
	# Floating crystal in the tier colour, with difficulty pips orbiting it
	var crystal := SphereMesh.new()
	crystal.radius = 0.32
	crystal.height = 0.9
	crystal.radial_segments = 6
	crystal.rings = 2
	crystal.material = PowerupManager._glow(tier_col, 2.2)
	var cmi := MeshInstance3D.new()
	cmi.mesh = crystal
	cmi.name = "Crystal"
	cmi.position.y = 3.0
	add_child(cmi)
	for k in difficulty:
		var pip := SphereMesh.new()
		pip.radius = 0.07
		pip.height = 0.14
		pip.material = PowerupManager._glow(Color(1.0, 0.95, 0.7), 3.0)
		var p := MeshInstance3D.new()
		p.mesh = pip
		p.name = "Pip%d" % k
		cmi.add_child(p)
	var light := OmniLight3D.new()
	light.light_color = tier_col
	light.light_energy = 2.0
	light.omni_range = 7.0
	light.position.y = 3.0
	add_child(light)
	# Beam of light so shrines can be found from across the swamp
	var beam := CylinderMesh.new()
	beam.top_radius = 0.18
	beam.bottom_radius = 0.18
	beam.height = 60.0
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bm.albedo_color = Color(tier_col, 0.35)
	beam.material = bm
	var bmi := MeshInstance3D.new()
	bmi.mesh = beam
	bmi.name = "Beam"
	bmi.position.y = 33.0
	bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bmi)
	# D3 chains: the shrine itself burns
	if pattern == CHAINS and difficulty == 3:
		_shrine_fire = Abilities._flame_particles(0.9, 0.7, 60)
		_shrine_fire.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		_shrine_fire.emission_box_extents = Vector3(PILLAR_RADIUS, 1.1, PILLAR_RADIUS)
		_shrine_fire.position.y = 1.2
		add_child(_shrine_fire)


func _build_zone(tier_col: Color) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(ZONE_RADIUS * 2.0, ZONE_RADIUS * 2.0)
	var sh := Shader.new()
	sh.code = ZONE_SHADER
	_zone_mat = ShaderMaterial.new()
	_zone_mat.shader = sh
	_zone_mat.set_shader_parameter("col", tier_col)
	plane.material = _zone_mat
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.name = "Zone"
	mi.position.y = 0.05
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_chains() -> void:
	var n := difficulty
	var length: float = CHAIN_LENGTHS[difficulty - 1]
	var burning := difficulty >= 2
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.32, 0.3, 0.3) if not burning else Color(0.35, 0.18, 0.1)
	iron.metallic = 0.7
	iron.roughness = 0.45
	if burning:
		iron.emission_enabled = true
		iron.emission = Color(1.0, 0.35, 0.05)
		iron.emission_energy_multiplier = 1.4
	var link := TorusMesh.new()
	link.inner_radius = 0.05
	link.outer_radius = 0.1
	link.rings = 10
	link.ring_segments = 6
	link.material = iron
	for k in n:
		var pivot := Node3D.new()
		pivot.position.y = CHAIN_HEIGHT
		_fx_root.add_child(pivot)
		var links := maxi(3, int(length / 0.15))
		for j in links:
			var l := MeshInstance3D.new()
			l.mesh = link
			l.position = Vector3(PILLAR_RADIUS + (j + 0.5) * length / links, 0, 0)
			l.rotation = Vector3(0, 0, PI * 0.5) if j % 2 == 0 else Vector3(PI * 0.5, 0, PI * 0.5)
			l.scale = Vector3(1.0, 1.0, 0.75)
			pivot.add_child(l)
		if burning:
			var f := Abilities._flame_particles(0.55, 0.45, int(length * 14.0))
			f.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
			f.emission_box_extents = Vector3(length * 0.5, 0.05, 0.05)
			f.position = Vector3(PILLAR_RADIUS + length * 0.5, 0, 0)
			f.local_coords = true
			pivot.add_child(f)
		_chains.append(pivot)


# ------------------------------------------------------------------ simulation

## Advance the shrine and resolve hits/progress for the player. Returns true while the player
## is inside the zone.
func tick(dt: float, player: Player) -> bool:
	_t += dt
	var crystal := get_node("Crystal") as Node3D
	crystal.rotation.y += dt * 1.2
	crystal.position.y = 3.0 + 0.15 * sin(_t * 1.8)
	for k in difficulty:
		var pip := crystal.get_node("Pip%d" % k) as Node3D
		var a := _t * 2.0 + TAU * k / difficulty
		pip.position = Vector3(cos(a) * 0.55, 0.0, sin(a) * 0.55)
	if done:
		return false

	var rel := player.global_position - global_position
	var flat := Vector2(rel.x, rel.z)
	var feet := rel.y
	player_inside = flat.length() < ZONE_RADIUS and not player.meteor_form

	if pattern == CHAINS:
		_tick_chains(dt, player, flat, feet)
	else:
		_tick_nova(dt, player, flat, feet)

	if player_inside:
		progress += dt
		if progress >= REQUIRED_TIME:
			_complete()
	else:
		progress = 0.0
	_zone_mat.set_shader_parameter("progress", clampf(progress / REQUIRED_TIME, 0.0, 1.0))
	_zone_mat.set_shader_parameter("inside", 1.0 if player_inside else 0.0)
	_update_label()
	return player_inside


func chain_angle(k: int) -> float:
	return _chain_angle + TAU * k / maxi(difficulty, 1)


func _tick_chains(dt: float, player: Player, flat: Vector2, feet: float) -> void:
	_chain_angle += CHAIN_SPEEDS[difficulty - 1] * dt
	for k in _chains.size():
		_chains[k].rotation.y = -chain_angle(k)
	if player.meteor_form:
		return
	if chain_hits(flat, feet):
		if difficulty == 1:
			player.hurt(player.max_hp * CHAIN_HIT_FRAC)
		else:
			player.ignite()
	if difficulty == 3 and flat.length() < PILLAR_RADIUS + PLAYER_RADIUS + SHRINE_FIRE_REACH * 0.5 and feet < 2.4:
		player.ignite()


## Is a player at `flat` (offset from the shrine, XZ) with feet at height `feet` touching a chain?
func chain_hits(flat: Vector2, feet: float) -> bool:
	if feet > CHAIN_HEIGHT + 0.15:   # jumped over
		return false
	var length: float = CHAIN_LENGTHS[difficulty - 1]
	for k in difficulty:
		var a := chain_angle(k)
		var dir := Vector2(cos(a), sin(a))
		var along := flat.dot(dir)
		if along < PILLAR_RADIUS - PLAYER_RADIUS or along > PILLAR_RADIUS + length + PLAYER_RADIUS:
			continue
		var perp := absf(flat.x * dir.y - flat.y * dir.x)
		if perp < CHAIN_HIT_RADIUS + PLAYER_RADIUS:
			return true
	return false


## Pulse offsets within each 2 s period, per difficulty.
func pulse_offsets() -> Array:
	match difficulty:
		1:
			return [0.0]
		2:
			return [0.0, 0.5]
		_:
			return [0.0, 0.5, 1.0, 1.5]


func _tick_nova(dt: float, player: Player, flat: Vector2, feet: float) -> void:
	# Emit pulses on an exact schedule: period * cycle + offset
	var offs := pulse_offsets()
	while _t >= _next_pulse:
		_emit_nova()
		_pulse_idx += 1
		if _pulse_idx >= offs.size():
			_pulse_idx = 0
			_pulse_cycle += 1
		_next_pulse = NOVA_PERIOD * _pulse_cycle + float(offs[_pulse_idx])
	# Move rings outward; drop them at the zone edge
	for k in range(_novas.size() - 1, -1, -1):
		_novas[k] += NOVA_SPEED * dt
		var r := _novas[k]
		var node := _nova_nodes[k]
		if r > ZONE_RADIUS:
			node.queue_free()
			_novas.remove_at(k)
			_nova_nodes.remove_at(k)
			continue
		node.scale = Vector3(r, 1.0, r)
		var mat := (node.mesh as TorusMesh).material as StandardMaterial3D
		mat.albedo_color.a = 0.65 + 0.35 * sin(_t * 40.0 + k)
		if not player.meteor_form and nova_hits(r, flat, feet):
			player.hurt(player.max_hp * NOVA_HIT_FRAC)


func nova_hits(r: float, flat: Vector2, feet: float) -> bool:
	if feet > NOVA_HEIGHT:   # jumped over
		return false
	return absf(flat.length() - r) < NOVA_HALF_WIDTH + PLAYER_RADIUS * 0.5


func _emit_nova() -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.94
	torus.outer_radius = 1.0
	torus.rings = 48
	torus.ring_segments = 6
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(0.45, 0.75, 1.0, 0.9)
	torus.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = torus
	mi.position.y = 0.15
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fx_root.add_child(mi)
	_novas.append(PILLAR_RADIUS)
	_nova_nodes.append(mi)


func nova_count() -> int:
	return _novas.size()


func _complete() -> void:
	done = true
	progress = REQUIRED_TIME
	_fx_root.queue_free()
	if _shrine_fire:
		_shrine_fire.emitting = false
	(get_node("Zone") as Node3D).visible = false
	(get_node("Beam") as Node3D).visible = false
	_update_label()
	completed.emit(self)


func _update_label() -> void:
	if done:
		_label.text = "Complete"
	elif progress > 0.0:
		_label.text = "%.1f / %d s" % [progress, int(REQUIRED_TIME)]
	else:
		_label.text = "%s Shrine" % tier_name()


func describe() -> String:
	var stars := "★".repeat(difficulty) + "☆".repeat(3 - difficulty)
	return "%s  %s" % ["Chain Shrine" if pattern == CHAINS else "Storm Shrine", stars]
