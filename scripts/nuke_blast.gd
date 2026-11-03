class_name NukeBlast
extends Node3D
## The NUKE power-up going off at the player's feet (PowerupManager.activate(NUKE)).
##
## Gameplay (tick(), driven by PowerupManager.tick so it pauses with the game):
##   - Every enemy alive at the moment it's set off is marked (by uid); enemies that spawn
##     afterwards are spared. A shockwave runs out from you and each marked enemy dies when it
##     reaches them, so the horde falls in a wave over WAVE_TIME seconds, nearest first.
##   - Bosses aren't killed: each takes BOSS_FRAC of its max health, nothing else.
##   - Kills drop XP gems as usual (the gem cap merges them), then every gem flies to you.
##   - It never hurts you (bomber skeletons it kills don't drop their barrels).
## Spectacle (_process): a white flash, a fireball, a mushroom cloud of billowing puffs (stem,
## rolling cap and a ground skirt; fire cooling to smoke) rising over you, a condensation ring,
## a shockwave racing along the ground, a light, a little shake and a boom. All of it is kept
## small (VISUAL_SCALE): a tiny mushroom cloud as a marker of what happened, not a real bomb.
## Indoors (Abilities.ceiling) the cloud is squashed under the ceiling and spreads wider.

const VISUAL_SCALE := 0.16      # the mushroom cloud is a small marker, not a real bomb going off
const WAVE_TIME := 0.6          # the farthest marked enemy dies this long after the blast
const MIN_SPEED := 45.0         # m/s: the shockwave never runs slower than this
const BOSS_FRAC := 0.15         # bosses lose this share of their max HP
const RING_MAX := 22.0          # the visible shockwave fades out past this radius (was 95)
const CLOUD_H := 30.0           # height of the cap outdoors
const RISE_TIME := 3.6
const LIFE := 10.0
const MAX_BURSTS := 48          # fire bursts on dying enemies (sampled)
const STEM_N := 12
const CAP_RING_N := 22
const CAP_TOP_N := 9
const SKIRT_N := 16
const SND_BOOM := "res://audio/powerups/nuke.wav"
const SND_WIND := "res://audio/powerups/nuke_wind.wav"

const PUFF_SHADER := """
shader_type spatial;
render_mode cull_back, shadows_disabled;
// INSTANCE_CUSTOM: x heat (1 white-hot fire .. 0 cold smoke), y dissolve (0 solid .. 1 gone),
// z underglow (fire light on the underside), w phase
uniform float time = 0.0;
varying vec3 wpos;
varying vec4 cust;
varying vec3 wnorm;
float h3(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453); }
float vnoise(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h3(i), h3(i + vec3(1,0,0)), f.x), mix(h3(i + vec3(0,1,0)), h3(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(h3(i + vec3(0,0,1)), h3(i + vec3(1,0,1)), f.x), mix(h3(i + vec3(0,1,1)), h3(i + vec3(1,1,1)), f.x), f.y), f.z);
}
void vertex() {
	cust = INSTANCE_CUSTOM;
	float ph = cust.w * 17.0;
	float n = vnoise(VERTEX * 2.6 + vec3(ph, time * 0.6, -time * 0.4)) * 0.6
		+ vnoise(VERTEX * 5.5 + vec3(-time * 0.9, ph, time * 0.5)) * 0.4;
	n += vnoise(VERTEX * 9.0 + vec3(ph, -time * 1.2, ph)) * 0.25;
	VERTEX += NORMAL * (n - 0.55) * 0.55;   // lumpy, churning cauliflower surface
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	float heat = cust.x;
	float n = vnoise(wpos * 0.9 + vec3(0.0, -time * 0.8, 0.0));
	if (n < cust.y * 1.05) { discard; }   // breaks up as it fades
	float up = clamp(wnorm.y * 0.5 + 0.5, 0.0, 1.0);
	float grain = vnoise(wpos * 2.7 + vec3(time * 0.3));
	vec3 smoke = mix(vec3(0.2, 0.16, 0.14), vec3(0.66, 0.6, 0.54), up * 0.65 + n * 0.2 + grain * 0.15);
	vec3 fire = mix(vec3(1.0, 0.32, 0.04), vec3(1.0, 0.92, 0.65), clamp(heat * heat + n * 0.25 - 0.1, 0.0, 1.0));
	float burn = clamp(heat * 1.25 - (1.0 - n) * 0.35, 0.0, 1.0);
	ALBEDO = mix(smoke, fire * 0.6, burn);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	float under = cust.z * clamp(-wnorm.y * 0.8 + 0.35, 0.0, 1.0);
	EMISSION = fire * (burn * 4.5 + under * 1.6) + smoke * (0.22 + 0.1 * grain);
}
"""

const BAND_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec4 color : source_color = vec4(1.0, 0.85, 0.6, 1.0);
uniform float alpha = 1.0;
varying float ly;
void vertex() { ly = VERTEX.y; }
void fragment() {
	float a = alpha * pow(clamp(0.5 - ly, 0.0, 1.0), 1.6);   // bright at the ground, fading upward
	ALBEDO = color.rgb;
	ALPHA = a * color.a;
}
"""

const HALO_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform float alpha = 0.0;
varying vec2 lp;
void vertex() { lp = VERTEX.xz; }
void fragment() {
	float d = length(lp) * 2.0;
	float a = smoothstep(0.62, 0.8, d) * (1.0 - smoothstep(0.86, 1.0, d));
	ALBEDO = vec3(0.92, 0.94, 1.0);
	ALPHA = a * alpha;
}
"""

var em: EnemyManager
var player: Node3D
var gems: GemManager
var fx: FxManager
var at := Vector3.ZERO
var t := 0.0                     # gameplay time since the blast
var killed := 0                  # tests: enemies the wave has killed
var bosses_hit := 0              # tests: bosses that took the BOSS_FRAC hit
var marked := 0                  # tests: enemies alive at the blast
var wave_done := false
var _pending := {}               # uid -> flat distance from the blast
var _speed := MIN_SPEED
var _bursts := 0
var _burst_every := 1
var _vt := 0.0                   # visual time
var _height := CLOUD_H
var _indoor := false
var _flash_layer: CanvasLayer
var _flash: ColorRect
var _fireball: MeshInstance3D
var _puffs: MultiMeshInstance3D
var _puff_mat: ShaderMaterial
var _puff_data: Array = []       # {kind, a (angle), r0, s (size), ph}
var _ground_ring: GroundDisc
var _ground_glow: GroundDisc
var _band: MeshInstance3D
var _band_mat: ShaderMaterial
var _halo: MeshInstance3D        # the condensation ring round the stem
var _halo_mat: ShaderMaterial
var _light: OmniLight3D


## Set it off at `p_at`: mark every enemy alive right now.
func setup(p_em: EnemyManager, p_player: Node3D, p_gems: GemManager, p_fx: FxManager, p_at: Vector3) -> void:
	em = p_em
	player = p_player
	gems = p_gems
	fx = p_fx
	at = p_at
	var far := 0.0
	if em != null:
		for i in em.count:
			if em.dead[i]:
				continue
			var d := Vector2(em.pos[i].x - at.x, em.pos[i].z - at.z).length()
			_pending[em.uid[i]] = d
			far = maxf(far, d)
	marked = _pending.size()
	_speed = maxf(MIN_SPEED, far / WAVE_TIME)
	_burst_every = maxi(1, ceili(float(marked) / MAX_BURSTS))
	_indoor = Abilities.ceiling < 1e6
	_height = CLOUD_H if not _indoor else maxf(6.0, Abilities.ceiling - at.y - 6.0)


func _ready() -> void:
	top_level = true
	global_position = at
	_build_flash()
	_build_fireball()
	_build_cloud()
	_build_rings()
	var vis := Node3D.new()   # the fireball, cloud and condensation ring, shrunk to a little marker
	vis.scale = Vector3.ONE * VISUAL_SCALE
	add_child(vis)
	for n in [_fireball, _puffs, _halo]:
		if n != null:
			remove_child(n)
			vis.add_child(n)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.95, 0.85)
	_light.light_energy = 14.0
	_light.omni_range = 90.0 * VISUAL_SCALE * 1.5
	_light.omni_attenuation = 0.6
	_light.shadow_enabled = false
	_light.position.y = 6.0
	add_child(_light)
	_sound(SND_BOOM, 0.0, -5.0)
	_sound(SND_WIND, 0.12, -9.0)
	if player != null and player.has_method("add_shake"):
		player.add_shake(0.3)


# ------------------------------------------------------------------ gameplay

## Advance the shockwave: kill each marked enemy it reaches. Returns true while it runs.
func tick(dt: float) -> bool:
	if wave_done:
		return false
	t += dt
	var reach := _speed * t
	if em != null and not _pending.is_empty():
		for i in em.count:
			if em.dead[i]:
				continue
			var u: int = em.uid[i]
			if not _pending.has(u) or float(_pending[u]) > reach:
				continue
			_pending.erase(u)
			_hit(i)
	if player != null and player.has_method("add_shake"):
		player.add_shake(clampf(0.3 - t / 2.4, 0.08, 0.3))
	if _pending.is_empty() or t > WAVE_TIME + 0.4:
		_pending.clear()
		wave_done = true
		if gems != null:
			gems.magnetise_all()   # the whole wave's XP comes to you
	return not wave_done


func _hit(i: int) -> void:
	if em.is_boss(i):
		# a big chunk, nothing else: exactly BOSS_FRAC of max HP whatever buffs are running
		var want := em.hp_max[i] * BOSS_FRAC
		var m := em.damage_mult * em.taken_mult(i)
		em.damage(i, want / maxf(m, 0.0001), Vector3.ZERO, "Nuke")
		bosses_hit += 1
		return
	if em.bomber[i] == 1:
		em.bomber[i] = 2   # a bomber caught in the blast doesn't drop its barrel (the nuke never hurts you)
	var p := em.pos[i]
	em.hp[i] = 0.0
	em._kill(i)
	killed += 1
	if fx != null and killed % _burst_every == 0 and _bursts < MAX_BURSTS:
		_bursts += 1
		fx.burst(p + Vector3(0, 0.6, 0), 1.6, Color(1.0, 0.5, 0.12), 0.45)


# ------------------------------------------------------------------ spectacle

func _process(delta: float) -> void:
	_vt += delta
	var v := _vt
	# the flash: blinding white, then a warm afterglow
	if _flash != null:
		var fa := 1.0 if v < 0.07 else clampf(1.0 - (v - 0.07) / 0.75, 0.0, 1.0)
		_flash.color = Color(1.0, lerpf(0.75, 1.0, fa), lerpf(0.45, 1.0, fa), pow(fa, 1.4) * 0.22)   # a brief glint, not a blinding flash
		if v > 0.9:
			_flash_layer.queue_free()
			_flash_layer = null
			_flash = null
	# the fireball swells at the ground, then is swallowed by the cloud
	if _fireball != null:
		var fr := 7.5 * (1.0 - exp(-v * 9.0))
		_fireball.scale = Vector3.ONE * maxf(fr, 0.01)
		_fireball.position.y = fr * 0.45 + minf(v, 1.2) * 3.0
		if v > 1.4:
			_fireball.queue_free()
			_fireball = null
	_update_cloud(v)
	# the shockwave along the ground
	var rr := _speed * v
	var ring_on := rr < RING_MAX
	_ground_ring.visible = ring_on
	_ground_glow.visible = ring_on
	_band.visible = ring_on
	if ring_on:
		var fade := clampf(1.0 - rr / RING_MAX, 0.0, 1.0)
		var rad := maxf(rr, 0.5)
		_ground_ring.scale = Vector3(rad, 1.0, rad)
		_ground_ring.set_ring(clampf(1.0 - 3.2 / rad, 0.0, 0.98))
		_ground_ring.alpha = 0.95 * fade
		_ground_glow.scale = Vector3(rad, 1.0, rad)
		_ground_glow.set_ring(clampf(1.0 - 14.0 / rad, 0.0, 0.98))
		_ground_glow.alpha = 0.35 * fade
		_band.scale = Vector3(rad, 3.0, rad)
		_band_mat.set_shader_parameter("alpha", 0.9 * fade)
	# the condensation ring round the stem
	if _halo != null:
		var hr := 2.0 + 20.0 * (1.0 - exp(-maxf(v - 0.5, 0.0) * 1.2))
		_halo.scale = Vector3(hr * 2.0, 1.0, hr * 2.0)
		_halo.position.y = _height * 0.42 * _rise(v)
		_halo_mat.set_shader_parameter("alpha", 0.55 * clampf((v - 0.5) * 2.0, 0.0, 1.0) * clampf(1.0 - (v - 1.5) / 2.5, 0.0, 1.0))
		if v > 4.2:
			_halo.queue_free()
			_halo = null
	if _light != null:
		var le := 4.0 * exp(-v * 1.6) + 0.8 * clampf(1.0 - v / 7.0, 0.0, 1.0)
		_light.light_energy = le
		_light.light_color = Color(1.0, lerpf(0.45, 0.95, exp(-v * 1.2)), lerpf(0.15, 0.85, exp(-v * 1.5)))
		_light.position.y = (3.0 + _height * 0.6 * _rise(v)) * VISUAL_SCALE
	if v >= LIFE:
		queue_free()


func _rise(v: float) -> float:
	var x := clampf(v / RISE_TIME, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 2.6)


func _update_cloud(v: float) -> void:
	_puff_mat.set_shader_parameter("time", v)
	var mm := _puffs.multimesh
	var rise := _rise(v)
	var cap_y := lerpf(4.0, _height, rise)
	var spread := 1.0 - exp(-v * 0.55)
	var squash := 0.62 if _indoor else 1.0
	var cap_r := lerpf(3.0, 11.0 if not _indoor else 15.0, spread)
	var tube := lerpf(2.5, 4.4, spread)
	var roll := v * 0.9
	var dissolve := clampf((v - (LIFE - 3.5)) / 3.2, 0.0, 1.0)
	var under := clampf(1.0 - v / 7.0, 0.0, 1.0)
	for k in _puff_data.size():
		var p: Dictionary = _puff_data[k]
		var kind: String = p["kind"]
		var a: float = p["a"]
		var s: float = p["s"]
		var ph: float = p["ph"]
		var pos := Vector3.ZERO
		var size := s
		var heat := 0.0
		var dis := dissolve
		match kind:
			"stem":
				var f: float = p["r0"]   # 0 bottom .. 1 top
				var top := cap_y - tube * 0.6
				pos = Vector3(cos(a) * 0.9, lerpf(1.0, top, f), sin(a) * 0.9)
				pos.x += sin(v * 1.3 + ph) * 0.5
				pos.z += cos(v * 1.1 + ph) * 0.5
				size = s * lerpf(1.0, 1.35, spread) * lerpf(1.25, 0.85, f)
				heat = clampf(1.0 - v / 2.2 - f * 0.15, 0.0, 1.0)
				dis = clampf(dissolve * 1.25 + (1.0 - f) * 0.1 * dissolve, 0.0, 1.0)
			"cap":
				var phi: float = p["r0"] + roll   # rolls over the tube: up the outside, in over the top
				var radial := cap_r + cos(phi) * tube
				pos = Vector3(cos(a) * radial, cap_y + sin(phi) * tube * squash, sin(a) * radial)
				size = s * lerpf(0.7, 1.25, spread)
				heat = clampf(1.15 - v / 3.0 - (sin(phi) * 0.5 + 0.5) * 0.25, 0.0, 1.0)
			"top":
				var r0: float = p["r0"]
				pos = Vector3(cos(a) * r0 * cap_r * 0.55, cap_y + tube * 0.75 * squash, sin(a) * r0 * cap_r * 0.55)
				size = s * lerpf(0.7, 1.3, spread)
				heat = clampf(1.05 - v / 2.8, 0.0, 1.0)
			"skirt":
				var r1 := lerpf(3.0, 22.0, 1.0 - exp(-v * 0.9)) * float(p["r0"])
				pos = Vector3(cos(a) * r1, 1.0 + 0.6 * sin(v + ph), sin(a) * r1)
				size = s * lerpf(0.8, 1.6, spread)
				heat = clampf(0.7 - v / 0.9, 0.0, 1.0)
				dis = clampf((v - 3.0) / 3.0, 0.0, 1.0)
		var grow := clampf(v / 0.35, 0.05, 1.0)
		var b := Basis().scaled(Vector3(size, size * (squash if kind != "stem" else 1.0), size) * grow)
		mm.set_instance_transform(k, Transform3D(b, pos))
		mm.set_instance_custom_data(k, Color(heat, dis, under, ph))


func _build_flash() -> void:
	_flash_layer = CanvasLayer.new()
	_flash_layer.layer = 95
	add_child(_flash_layer)
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(1, 1, 1, 0.95)
	_flash_layer.add_child(_flash)


func _build_fireball() -> void:
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.95, 0.8)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.85, 0.55)
	m.emission_energy_multiplier = 6.0
	s.material = m
	_fireball = MeshInstance3D.new()
	_fireball.mesh = s
	_fireball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fireball.scale = Vector3.ONE * 0.01
	add_child(_fireball)


func _build_cloud() -> void:
	var r := RandomNumberGenerator.new()
	r.seed = int(at.x * 13.0 + at.z * 7.0) + 99
	for k in STEM_N:
		_puff_data.append({"kind": "stem", "a": r.randf() * TAU, "r0": float(k) / float(STEM_N - 1), "s": r.randf_range(2.0, 2.6), "ph": r.randf()})
	for k in CAP_RING_N:
		for layer in 3:   # three puffs round the tube, so the rolling cap stays one solid doughnut
			_puff_data.append({"kind": "cap", "a": TAU * (k + layer / 3.0) / CAP_RING_N + r.randf_range(-0.08, 0.08),
				"r0": TAU * layer / 3.0 + r.randf_range(-0.4, 0.4), "s": r.randf_range(2.8, 3.6), "ph": r.randf()})
	for k in CAP_TOP_N:
		_puff_data.append({"kind": "top", "a": TAU * k / CAP_TOP_N, "r0": 0.0 if k == 0 else r.randf_range(0.5, 1.0), "s": r.randf_range(3.0, 3.8), "ph": r.randf()})
	for k in SKIRT_N:
		_puff_data.append({"kind": "skirt", "a": TAU * k / SKIRT_N + r.randf_range(-0.1, 0.1), "r0": r.randf_range(0.7, 1.0), "s": r.randf_range(1.6, 2.4), "ph": r.randf()})
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 20
	sm.rings = 12
	var sh := Shader.new()
	sh.code = PUFF_SHADER
	_puff_mat = ShaderMaterial.new()
	_puff_mat.shader = sh
	sm.material = _puff_mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = sm
	mm.instance_count = _puff_data.size()
	_puffs = MultiMeshInstance3D.new()
	_puffs.multimesh = mm
	_puffs.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_puffs.custom_aabb = AABB(Vector3(-40, -5, -40), Vector3(80, 60, 80))
	add_child(_puffs)
	_update_cloud(0.0)


func _build_rings() -> void:
	_ground_glow = GroundDisc.create(1.0, Color(1.0, 0.55, 0.2, 0.35), true)
	add_child(_ground_glow)
	_ground_glow.global_position = at
	_ground_ring = GroundDisc.create(1.0, Color(1.0, 0.9, 0.7, 0.95), true)
	_ground_ring.set_lift(0.18)
	add_child(_ground_ring)
	_ground_ring.global_position = at
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 1.0
	cyl.radial_segments = 64
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	var sh := Shader.new()
	sh.code = BAND_SHADER
	_band_mat = ShaderMaterial.new()
	_band_mat.shader = sh
	cyl.material = _band_mat
	_band = MeshInstance3D.new()
	_band.mesh = cyl
	_band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_band.position.y = 1.2
	_band.scale = Vector3(0.5, 3.0, 0.5)
	add_child(_band)
	var hp := PlaneMesh.new()
	hp.size = Vector2(1.0, 1.0)
	var hs := Shader.new()
	hs.code = HALO_SHADER
	_halo_mat = ShaderMaterial.new()
	_halo_mat.shader = hs
	hp.material = _halo_mat
	_halo = MeshInstance3D.new()
	_halo.mesh = hp
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_halo)


func _sound(path: String, delay: float, db: float) -> void:
	if not ResourceLoader.exists(path):
		return
	var a := AudioStreamPlayer.new()
	a.stream = load(path)
	a.bus = Settings.SFX_BUS
	a.volume_db = db
	add_child(a)
	if delay <= 0.0:
		a.play()
	else:
		get_tree().create_timer(delay, false).timeout.connect(func():
			if is_instance_valid(a):
				a.play())
