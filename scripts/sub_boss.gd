class_name SubBoss
extends Node3D
## A sub-boss: between an epic and a map boss. It's a crowd row in EnemyManager (type SUB_BOSS,
## drawn by the goblin VAT at its kind's size and tint), so every weapon, burn and ability hits it,
## and it's targeted like any elite (the bosses-first rule stays the real boss's). This node adds
## what makes it read as a mini-boss (a bone crown, a totem staff, a ground aura, a name and its
## own health bar over its head), and runs its two telegraphed abilities:
##   - Mud Slam (close): a circle round it fills (>= MIN_WARN s), then it slams the ground:
##     damage, a slow and a shove for anyone inside.
##   - Bog Bolt (at range): a lane toward you fills, then a bolt of bog water tears down it:
##     damage and a slow if you're in it.
## It stands still while casting. When the row dies it emits `died(at)` (SubBosses drops a
## waygate there) and frees itself.
## Kinds are data (KINDS): only the Swamp's Bog Shaman for now.

signal died(at: Vector3)

const MIN_WARN := 1.0            # every telegraph gives at least this long (like MapBoss.MIN_WARN)
const WARN_COLOR := Color(1.0, 0.12, 0.05)
const BAR_HIDE := 60.0

## Per kind: crowd-row numbers (hp is x the run's HP multiplier; a goblin is 10, an epic 40),
## the look, and the two abilities.
const KINDS := {
	"bog_shaman": {
		"name": "Bog Shaman",
		"hp": 320.0, "speed": 3.3, "radius": 1.0, "scale": 2.2, "damage": 32.0, "xp": 40.0,
		"tint": Color(0.13, 0.36, 0.12),        # bog-green rags
		"glow": Color(0.35, 1.0, 0.45),          # the totem's swamp-fire
		"bar": Color(1.0, 0.55, 0.15),           # its name and bar border
		"slam": {"radius": 5.0, "warn": 1.1, "damage": 24.0, "slow": 0.5, "slow_secs": 2.5, "every": 7.0, "range": 6.5},
		"bolt": {"length": 20.0, "width": 3.2, "warn": 1.0, "damage": 18.0, "slow": 0.65, "slow_secs": 2.0, "every": 8.0, "min": 4.0, "max": 22.0},
	},
}

const BAR_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_test_disabled;
uniform float hp = 1.0;
uniform vec3 border : source_color = vec3(1.0, 0.55, 0.15);
void vertex() {
	float sx = length(MODEL_MATRIX[0].xyz);
	float sy = length(MODEL_MATRIX[1].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * sx, INV_VIEW_MATRIX[1] * sy, INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	vec2 uv = UV;
	float bx = 0.02;
	float by = 0.18;
	vec3 col = border;
	if (uv.x > bx && uv.x < 1.0 - bx && uv.y > by && uv.y < 1.0 - by) {
		float x = (uv.x - bx) / (1.0 - 2.0 * bx);
		vec3 fill = mix(vec3(0.95, 0.25, 0.08), vec3(1.0, 0.62, 0.12), hp);
		col = x < hp ? fill : vec3(0.12, 0.04, 0.03);
	}
	ALBEDO = col;
}
"""

var main: Node
var em: EnemyManager
var player: Player
var kind := "bog_shaman"
var data: Dictionary
var uid := -1
var idx := -1
var state := "alive"              # alive | dead
var casting := ""                 # "" | slam | bolt
var cd_slam := 2.5
var cd_bolt := 4.0
var last_pos := Vector3.ZERO
var counts := {"warned": 0, "hits": 0, "slam_warn": 0.0, "bolt_warn": 0.0, "slams": 0, "bolts": 0}   # tests
var _warns: Array[Dictionary] = []   # {disc, t, time, land}
var _bolts: Array[Dictionary] = []   # {node, from, to, t}
var _look: Node3D                 # crown, staff (follows the row)
var _aura: GroundDisc
var _over: Node3D                 # name + bar (top level)
var _label: Label3D
var _bar_mat: ShaderMaterial
var _sfx := {}
var _t := 0.0


## Spawn the row at `at` with `hp_mult` x the kind's health.
func setup(p_main: Node, at: Vector3, hp_mult: float, p_kind := "bog_shaman") -> void:
	main = p_main
	em = main.enemies
	player = main.player
	kind = p_kind
	data = KINDS[kind]
	var t := EnemyManager.SUB_BOSS
	em.type_names[t] = data["name"]
	em.t_hp[t] = data["hp"]
	em.t_speed[t] = data["speed"]
	em.t_radius[t] = data["radius"]
	em.t_scale[t] = data["scale"]
	em.t_height[t] = EnemyManager.GOBLIN_HEIGHT * float(data["scale"])
	em.t_damage[t] = data["damage"]
	em.t_xp[t] = data["xp"]
	em.t_color[t] = data["tint"]
	idx = em.spawn(t, at, hp_mult)
	uid = em.uid[idx] if idx >= 0 else -1
	last_pos = em.pos[idx] if idx >= 0 else at


func _ready() -> void:
	for k in ["arrive", "slam", "bolt", "death"]:
		var a := AudioStreamPlayer3D.new()
		a.bus = Settings.SFX_BUS
		a.unit_size = 22.0
		a.max_distance = 120.0
		var path := "res://audio/subboss/%s.wav" % k
		if ResourceLoader.exists(path):
			a.stream = load(path)
		add_child(a)
		_sfx[k] = a
	_build_look()
	_build_overhead()
	_arrive_fx()


func display_name() -> String:
	return data.get("name", "Bog Shaman")


## Current crowd row (rows move when others die), or -1 once gone.
func row() -> int:
	if em == null or uid < 0:
		return -1
	if idx >= 0 and idx < em.count and em.uid[idx] == uid:
		return idx
	idx = -1
	for i in em.count:
		if em.uid[i] == uid:
			idx = i
			break
	return idx


func is_alive() -> bool:
	var i := row()
	return state == "alive" and i >= 0 and not em.dead[i]


func hp_fraction() -> float:
	var i := row()
	return clampf(em.hp[i] / em.hp_max[i], 0.0, 1.0) if i >= 0 and not em.dead[i] else 0.0


# ------------------------------------------------------------------ loop

func _physics_process(dt: float) -> void:
	if state == "dead":
		return
	var i := row()
	if i < 0 or em.dead[i]:
		_die()
		return
	last_pos = em.pos[i]
	_follow(i, dt)
	if main.state != "playing" or main.intro:
		return
	_t += dt
	_tick_warns(dt)
	_tick_bolts(dt)
	cd_slam -= dt
	cd_bolt -= dt
	if casting != "":
		em.throw_anim[i] = 0.1   # stands still while casting (EnemyManager stops anything with throw_anim > 0)
		return
	em.throw_anim[i] = 0.0
	if em.is_harmless(i) or em.is_held(i):
		return
	var d := MapBoss.flat_dist(player.global_position, em.pos[i])
	var s: Dictionary = data["slam"]
	var b: Dictionary = data["bolt"]
	if cd_slam <= 0.0 and d < float(s["range"]):
		cast_slam()
	elif cd_bolt <= 0.0 and d > float(b["min"]) and d < float(b["max"]):
		cast_bolt()


## Mud Slam: the circle round it fills, then the slam lands.
func cast_slam() -> void:
	var i := row()
	if i < 0:
		return
	var s: Dictionary = data["slam"]
	casting = "slam"
	cd_slam = float(s["every"])
	var c := em.pos[i]
	var r := float(s["radius"])
	var w := _warn(c, Vector3(r, 1, r), 0.0, float(s["warn"]), func(): _land_slam(c))
	counts["slam_warn"] = w["time"]


func _land_slam(c: Vector3) -> void:
	var s: Dictionary = data["slam"]
	casting = ""
	counts["slams"] += 1
	_play("slam")
	var fx: FxManager = main.fx
	fx.burst(c + Vector3(0, 0.3, 0), float(s["radius"]) * 1.1, Color(0.32, 0.24, 0.12), 0.5)
	fx.burst(c + Vector3(0, 0.5, 0), float(s["radius"]) * 0.6, Color(0.3, 0.8, 0.3), 0.35)
	_shake(0.35)
	if MapBoss.flat_dist(player.global_position, c) < float(s["radius"]):
		var push := player.global_position - c
		push.y = 0.0
		if _hit(float(s["damage"]), push.normalized() * 8.0 if push.length() > 0.01 else Vector3.ZERO):
			player.apply_slow(float(s["slow"]), float(s["slow_secs"]))


## Bog Bolt: a lane toward where you're heading fills, then the bolt tears down it.
func cast_bolt() -> void:
	var i := row()
	if i < 0:
		return
	var b: Dictionary = data["bolt"]
	casting = "bolt"
	cd_bolt = float(b["every"])
	var from := em.pos[i]
	var v := player.velocity
	var aim := player.global_position + Vector3(v.x, 0, v.z) * 0.35 - from
	aim.y = 0.0
	if aim.length() < 0.1:
		aim = Vector3(0, 0, 1)
	aim = aim.normalized()
	var length := float(b["length"])
	var width := float(b["width"])
	var c := from + aim * (length * 0.5)
	var w := _warn(c, Vector3(width * 0.5, 1, length * 0.5), atan2(-aim.x, -aim.z), float(b["warn"]), func(): _land_bolt(from, aim))
	counts["bolt_warn"] = w["time"]


func _land_bolt(from: Vector3, dir: Vector3) -> void:
	var b: Dictionary = data["bolt"]
	casting = ""
	counts["bolts"] += 1
	_play("bolt")
	var length := float(b["length"])
	_launch_bolt(from + Vector3(0, 1.4, 0), from + dir * length + Vector3(0, 1.0, 0))
	if in_lane(player.global_position, from, dir, length, float(b["width"])):
		if _hit(float(b["damage"]), dir * 5.0):
			player.apply_slow(float(b["slow"]), float(b["slow_secs"]))


static func in_lane(p: Vector3, from: Vector3, dir: Vector3, length: float, width: float) -> bool:
	var d := Vector2(p.x - from.x, p.z - from.z)
	var u := Vector2(dir.x, dir.z).normalized()
	var along := d.dot(u)
	var across := absf(d.cross(u))
	return along >= -0.5 and along <= length and across <= width * 0.5


func _hit(amount: float, push: Vector3) -> bool:
	player.invuln = 0.0   # a telegraphed hit always lands, whatever grazed you a moment ago
	if player.hurt(amount * main.enemy_damage_mult(), display_name()):
		counts["hits"] += 1
		if push != Vector3.ZERO:
			player.knockback(push)
		_shake(0.3)
		return true
	return false


func _shake(amount: float) -> void:
	var d := MapBoss.flat_dist(player.global_position, last_pos)
	player.add_shake(amount * clampf(1.3 - d / 30.0, 0.15, 1.0))


func _play(k: String) -> void:
	var a: AudioStreamPlayer3D = _sfx.get(k)
	if a and a.stream:
		a.global_position = last_pos + Vector3(0, 1.5, 0)
		a.pitch_scale = randf_range(0.94, 1.05)
		a.play()


# ------------------------------------------------------------------ telegraphs

## A red marker on the ground (a circle, or an oval lane when the scale is stretched) that fills
## over `secs` (never under MIN_WARN), then calls `land`.
func _warn(at: Vector3, scl: Vector3, yaw: float, secs: float, land: Callable) -> Dictionary:
	var d := GroundDisc.create(1.0, WARN_COLOR, false)
	d.alpha = 0.55
	d.set_lift(0.15)
	d.set_fill(0.0)
	d.top_level = true
	add_child(d)
	d.global_position = Vector3(at.x, SwampWater.height_at(at.x, at.z), at.z)
	d.scale = scl
	d.rotation.y = yaw
	var w := {"disc": d, "t": 0.0, "time": maxf(secs, MIN_WARN), "land": land}
	_warns.append(w)
	counts["warned"] += 1
	return w


func _tick_warns(dt: float) -> void:
	for k in range(_warns.size() - 1, -1, -1):
		var w: Dictionary = _warns[k]
		w["t"] += dt
		var d: GroundDisc = w["disc"]
		d.set_fill(clampf(w["t"] / w["time"], 0.0, 1.0))
		if w["t"] >= w["time"]:
			_warns.remove_at(k)
			d.queue_free()
			(w["land"] as Callable).call()


func _clear_warns() -> void:
	for w in _warns:
		(w["disc"] as Node).queue_free()
	_warns.clear()
	casting = ""


func _launch_bolt(from: Vector3, to: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.55
	sm.height = 1.1
	var m := StandardMaterial3D.new()
	var g: Color = data["glow"]
	m.albedo_color = g
	m.emission_enabled = true
	m.emission = g
	m.emission_energy_multiplier = 2.5
	sm.material = m
	mi.mesh = sm
	mi.top_level = true
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = from
	_bolts.append({"node": mi, "from": from, "to": to, "t": 0.0})


func _tick_bolts(dt: float) -> void:
	for k in range(_bolts.size() - 1, -1, -1):
		var b: Dictionary = _bolts[k]
		b["t"] += dt
		var f: float = clampf(b["t"] / 0.35, 0.0, 1.0)
		var p: Vector3 = (b["from"] as Vector3).lerp(b["to"], f)
		(b["node"] as Node3D).global_position = p
		if fmod(b["t"], 0.06) < dt:
			main.fx.burst(p, 0.9, Color(0.3, 0.75, 0.3), 0.3)
		if f >= 1.0:
			(b["node"] as Node).queue_free()
			_bolts.remove_at(k)


# ------------------------------------------------------------------ the look

## Arrival: mud bursts up where it stands, with a guttural chant.
func _arrive_fx() -> void:
	_play("arrive")
	var fx: FxManager = main.fx
	fx.burst(last_pos + Vector3(0, 0.4, 0), 5.0, Color(0.3, 0.22, 0.1), 0.7)
	fx.burst(last_pos + Vector3(0, 1.0, 0), 3.0, data["glow"], 0.5)


func _build_look() -> void:
	_look = Node3D.new()
	_look.top_level = true
	add_child(_look)
	var bone := Color(0.86, 0.82, 0.68, 0.0)
	var wood := Color(0.28, 0.2, 0.12, 0.0)
	var moss := Color(0.2, 0.34, 0.12, 0.0)
	var glow: Color = data["glow"]
	var mb := MeshBuilder.new()
	var gl := MeshBuilder.new()
	# A bone crown on its head: a band, a ring of spikes and two curling horns
	var hc := Vector3(0, 0.93, 0.16)
	mb.add(MeshBuilder.cyl(0.13, 0.15, 0.06, 10), Transform3D(Basis(), hc), wood)
	for k in 7:
		var a := PI * (0.15 + 0.7 * k / 6.0)
		var at := hc + Vector3(cos(a) * 0.14, 0.05, sin(a) * 0.14 - 0.02)
		mb.add(MeshBuilder.cone(0.025, 0.16 + 0.05 * (1.0 - absf(k - 3) / 3.0), 5), Transform3D(Basis(Vector3.RIGHT, -0.15).rotated(Vector3.UP, 0.0), at + Vector3(0, 0.08, 0)), bone)
	for sx in [-1.0, 1.0]:
		var p0 := hc + Vector3(sx * 0.12, 0.02, 0)
		var p1 := p0 + Vector3(sx * 0.12, 0.12, -0.04)
		var p2 := p1 + Vector3(sx * 0.04, 0.14, -0.1)
		mb.limb(p0, p1, 0.035, 0.026, bone, 6)
		mb.limb(p1, p2, 0.026, 0.008, bone, 6)
	gl.add(MeshBuilder.sphere(0.03, 6, 4), Transform3D(Basis(), hc + Vector3(0, 0.03, 0.15)), glow)
	# A mossy mantle of hides on its shoulders
	mb.add(MeshBuilder.cyl(0.16, 0.3, 0.12, 9), Transform3D(Basis(Vector3.RIGHT, 0.35), Vector3(0, 0.72, 0.05)), moss)
	# A totem staff in its right hand: a gnarled pole, a skull and a ball of swamp-fire
	var s0 := Vector3(-0.42, 0.02, 0.14)
	var s1 := Vector3(-0.46, 0.7, 0.18)
	var s2 := Vector3(-0.44, 1.32, 0.16)
	mb.limb(s0, s1, 0.035, 0.03, wood, 6)
	mb.limb(s1, s2, 0.03, 0.026, wood, 6)
	mb.add(MeshBuilder.sphere(0.075, 8, 5), Transform3D(Basis().scaled(Vector3(1, 0.9, 1.1)), s2 + Vector3(0, 0.05, 0)), bone)
	for sx in [-1.0, 1.0]:
		mb.limb(s2 + Vector3(0, 0.08, 0), s2 + Vector3(sx * 0.12, 0.24, 0), 0.015, 0.004, bone, 5)
	gl.add(MeshBuilder.sphere(0.065, 8, 5), Transform3D(Basis(), s2 + Vector3(0, 0.2, 0)), glow)
	for sy in [0.45, 0.55]:   # feathers and charms tied to the pole
		gl.add(MeshBuilder.sphere(0.02, 5, 3), Transform3D(Basis(), s1.lerp(s2, sy) + Vector3(-0.03, 0, 0.03)), glow.lerp(Color.WHITE, 0.2))
	var mi := MeshInstance3D.new()
	mi.mesh = mb.commit(MeshBuilder.prop_material())
	gl.commit_into(mi.mesh as ArrayMesh, MeshBuilder.glow_material())
	_look.add_child(mi)
	var light := OmniLight3D.new()
	light.light_color = glow
	light.light_energy = 1.4
	light.omni_range = 2.6   # at scale 1 (the node is scaled up with the row)
	light.position = s2 + Vector3(0, 0.2, 0)
	_look.add_child(light)
	# a sickly green aura on the ground under it
	_aura = GroundDisc.create(1.0, Color(glow, 1.0), true)
	_aura.alpha = 0.3
	_aura.set_ring(0.55)
	_aura.top_level = true
	add_child(_aura)


func _build_overhead() -> void:
	_over = Node3D.new()
	_over.top_level = true
	add_child(_over)
	_label = Label3D.new()
	_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_label.text = tr(display_name())
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.font_size = 40
	_label.outline_size = 10
	_label.pixel_size = 0.008
	_label.modulate = (data["bar"] as Color).lerp(Color.WHITE, 0.3)
	_label.outline_modulate = Color(0.06, 0.02, 0.0)
	_label.position.y = 0.38
	_over.add_child(_label)
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	var sh := Shader.new()
	sh.code = BAR_SHADER
	_bar_mat = ShaderMaterial.new()
	_bar_mat.shader = sh
	_bar_mat.set_shader_parameter("border", data["bar"])
	_bar_mat.render_priority = 9
	q.material = _bar_mat
	var bar := MeshInstance3D.new()
	bar.mesh = q
	bar.scale = Vector3(2.2, 0.2, 1.0)
	bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_over.add_child(bar)


## Keep the crown, staff, aura, name and bar on the row.
func _follow(i: int, _dt: float) -> void:
	var p := em.pos[i]
	var sc := em.t_scale[em.typ[i]] * em.sz[i]
	var h := em.heading(i)
	var f := Vector2(h.x, h.z)
	if f.length() < 0.3 or casting != "":
		f = em.heading_to(i, player.global_position)
	else:
		f = f.normalized()
	_look.global_transform = Transform3D(Basis(Vector3.UP, atan2(f.x, f.y)).scaled(Vector3.ONE * sc), p)
	_look.visible = em.frog_t[i] <= 0.0
	_aura.global_position = Vector3(p.x, SwampWater.height_at(p.x, p.z), p.z)
	var r := 1.6 + 0.12 * sin(_t * 3.0)
	_aura.scale = Vector3(r, 1, r)
	_over.global_position = p + Vector3(0, em.t_height[em.typ[i]] * em.sz[i] + 0.55, 0)
	var near := MapBoss.flat_dist(player.global_position, p) < BAR_HIDE
	_over.visible = near
	_bar_mat.set_shader_parameter("hp", hp_fraction())


# ------------------------------------------------------------------ death

func _die() -> void:
	if state == "dead":
		return
	state = "dead"
	_clear_warns()
	for b in _bolts:
		(b["node"] as Node).queue_free()
	_bolts.clear()
	_play("death")
	main.fx.burst(last_pos + Vector3(0, 1.0, 0), 4.0, data["glow"], 0.5)
	_look.visible = false
	_over.visible = false
	_aura.visible = false
	died.emit(Vector3(last_pos.x, SwampWater.height_at(last_pos.x, last_pos.z), last_pos.z))
	get_tree().create_timer(2.5, false).timeout.connect(queue_free)
