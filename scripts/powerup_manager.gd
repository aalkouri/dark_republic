class_name PowerupManager
extends Node3D
## Power-ups dropped by elite (epic) enemies: DROP_BASE + DROP_PER_LUCK x the Luck stat,
## one of four at random.
##   Magnet            pulls every XP orb on the map to you (instant)
##   Fear Idol         every goblin runs away from you for 15 s
##   5x Damage         all damage you deal x5 for 10 s
##   Movement Enhancer +80% move speed for 15 s
## Picking up a power-up that's already active refreshes its timer.

signal collected(kind: int)

enum { MAGNET, FEAR, DAMAGE, SPEED }

const DROP_BASE := 0.02
const DROP_PER_LUCK := 0.1    # per point of the Luck stat (a Tome of Luck level = 0.1 luck = +1%)
const NAMES := ["Magnet", "Fear Idol", "5x Damage", "Movement Enhancer"]
const PICKUP_TEXT := ["MAGNET! All orbs incoming", "FEAR IDOL! Enemies flee for 15 s", "5x DAMAGE for 10 s!", "MOVEMENT +80% for 15 s!"]
const DURATION := [0.0, 15.0, 10.0, 15.0]
const COLORS := [Color(1.0, 0.25, 0.2), Color(0.65, 0.3, 1.0), Color(1.0, 0.55, 0.1), Color(0.3, 1.0, 0.45)]
const DAMAGE_MULT := 5.0
const SPEED_MULT := 1.8
const LIFETIME := 45.0
const PICKUP_DIST := 1.2

var player: Player
var stats: Stats
var enemies: EnemyManager
var gems: GemManager
var db: UpgradeDB
var rng: RandomNumberGenerator

var active := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])   # seconds left per kind
var _pickups: Array = []   # {node, spinner, kind, age, pulled}


func setup(p_player: Player, p_stats: Stats, p_enemies: EnemyManager, p_gems: GemManager, p_db: UpgradeDB, p_rng: RandomNumberGenerator) -> void:
	player = p_player
	stats = p_stats
	enemies = p_enemies
	gems = p_gems
	db = p_db
	rng = p_rng


func drop_chance() -> float:
	var luck := stats.value("luck") if stats != null and stats.has_stat("luck") else 0.0
	return DROP_BASE + DROP_PER_LUCK * luck


## Called when an elite dies: maybe drop a random power-up.
func on_elite_killed(at: Vector3) -> void:
	if rng.randf() < drop_chance():
		drop(at, rng.randi() % 4)


# ------------------------------------------------------------------ pickups

func drop(at: Vector3, kind: int) -> void:
	var root := Node3D.new()
	root.top_level = true
	add_child(root)
	root.global_position = Vector3(at.x, at.y, at.z)
	var spinner := Node3D.new()
	spinner.position.y = 0.8
	root.add_child(spinner)
	var model := _model(kind)
	model.rotation.z = deg_to_rad(15.0)
	spinner.add_child(model)
	var light := OmniLight3D.new()
	light.light_color = COLORS[kind]
	light.light_energy = 1.6
	light.omni_range = 3.5
	light.position.y = 0.8
	root.add_child(light)
	var ring := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.7
	disc.bottom_radius = 0.7
	disc.height = 0.02
	disc.radial_segments = 28
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.albedo_color = Color(COLORS[kind], 0.45)
	disc.material = dm
	ring.mesh = disc
	ring.position.y = 0.04
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	_pickups.append({"node": root, "spinner": spinner, "kind": kind, "age": 0.0, "pulled": false})


static func _glow(c: Color, energy := 1.2) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.roughness = 0.4
	return m


## A small floating model per power-up.
func _model(kind: int) -> Node3D:
	var root := Node3D.new()
	match kind:
		MAGNET:
			# Red horseshoe (U opening downward) with silver tips
			var mb := MeshBuilder.new()
			var prev := Vector3.ZERO
			var steps := 10
			for k in steps + 1:
				var a := deg_to_rad(lerpf(-20.0, 200.0, float(k) / steps))
				var p := Vector3(cos(a) * 0.22, sin(a) * 0.22, 0.0)
				if k > 0:
					mb.limb(prev, p, 0.065, 0.065, Color.WHITE, 10)
				prev = p
			for side in [-1.0, 1.0]:
				var a2 := deg_to_rad(-20.0 if side > 0 else 200.0)
				var top := Vector3(cos(a2) * 0.22, sin(a2) * 0.22, 0.0)
				mb.limb(top, top + Vector3(0, -0.14, 0), 0.065, 0.065, Color.WHITE, 10)
			var horse := MeshInstance3D.new()
			horse.mesh = mb.commit(_glow(Color(0.95, 0.12, 0.1), 0.8))
			root.add_child(horse)
			for side in [-1.0, 1.0]:
				var tip := CylinderMesh.new()
				tip.top_radius = 0.068
				tip.bottom_radius = 0.068
				tip.height = 0.1
				tip.material = _glow(Color(0.85, 0.88, 0.95), 0.6)
				var t := MeshInstance3D.new()
				t.mesh = tip
				t.position = Vector3(0.207 * side, -0.27, 0)
				root.add_child(t)
		FEAR:
			# Stone idol with glowing purple eyes
			var stone := StandardMaterial3D.new()
			stone.albedo_color = Color(0.3, 0.29, 0.27)
			stone.roughness = 0.9
			for part in [[Vector3(0.36, 0.3, 0.3), 0.0], [Vector3(0.3, 0.32, 0.26), 0.3], [Vector3(0.42, 0.06, 0.32), 0.48]]:
				var b := BoxMesh.new()
				b.size = part[0]
				b.material = stone
				var mi := MeshInstance3D.new()
				mi.mesh = b
				mi.position.y = part[1] - 0.15
				root.add_child(mi)
			for side in [-1.0, 1.0]:
				var eye := SphereMesh.new()
				eye.radius = 0.045
				eye.height = 0.09
				eye.material = _glow(Color(0.75, 0.3, 1.0), 4.0)
				var e := MeshInstance3D.new()
				e.mesh = eye
				e.position = Vector3(0.07 * side, 0.18, 0.13)
				root.add_child(e)
		DAMAGE:
			# Burning "5x"
			var core := SphereMesh.new()
			core.radius = 0.22
			core.height = 0.44
			core.material = _glow(Color(1.0, 0.45, 0.08), 2.0)
			var c := MeshInstance3D.new()
			c.mesh = core
			root.add_child(c)
			var label := Label3D.new()
			label.text = "5x"
			label.font_size = 96
			label.outline_size = 18
			label.pixel_size = 0.004
			label.modulate = Color(1.0, 0.95, 0.75)
			label.outline_modulate = Color(0.5, 0.05, 0.0)
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.position.y = 0.42
			root.add_child(label)
		SPEED:
			# Green winged boot
			var boot_mat := _glow(Color(0.25, 0.85, 0.35), 0.8)
			var leg := BoxMesh.new()
			leg.size = Vector3(0.16, 0.3, 0.16)
			leg.material = boot_mat
			var l := MeshInstance3D.new()
			l.mesh = leg
			l.position.y = 0.05
			root.add_child(l)
			var foot := BoxMesh.new()
			foot.size = Vector3(0.18, 0.12, 0.34)
			foot.material = boot_mat
			var f := MeshInstance3D.new()
			f.mesh = foot
			f.position = Vector3(0, -0.12, 0.08)
			root.add_child(f)
			for side in [-1.0, 1.0]:
				var wing := CylinderMesh.new()
				wing.top_radius = 0.0
				wing.bottom_radius = 0.12
				wing.height = 0.36
				wing.material = _glow(Color(0.95, 0.95, 1.0), 0.8)
				var w := MeshInstance3D.new()
				w.mesh = wing
				w.scale = Vector3(1, 1, 0.25)
				w.position = Vector3(0.14 * side, 0.12, -0.04)
				w.rotation.z = deg_to_rad(-60.0 * side)
				root.add_child(w)
	return root


# ------------------------------------------------------------------ update

func tick(dt: float, pickup_range: float) -> void:
	_tick_effects(dt)
	var target := player.global_position + Vector3(0, 0.6, 0)
	for k in range(_pickups.size() - 1, -1, -1):
		var p: Dictionary = _pickups[k]
		var root: Node3D = p["node"]
		var spinner: Node3D = p["spinner"]
		p["age"] += dt
		var age: float = p["age"]
		spinner.position.y = 0.8 + 0.15 * sin(age * 2.2)
		spinner.rotation.y += 1.1 * dt
		var to := target - (root.global_position + Vector3(0, 0.6, 0))
		var d := to.length()
		if d < pickup_range:
			p["pulled"] = true
		if p["pulled"]:
			root.global_position += to.normalized() * minf(d, (10.0 + age) * dt * 2.0)
		if d < PICKUP_DIST:
			activate(p["kind"])
			root.queue_free()
			_pickups.remove_at(k)
			continue
		if age > LIFETIME:
			root.queue_free()
			_pickups.remove_at(k)
		else:
			root.visible = PotionManager.is_visible_at(age)


func activate(kind: int) -> void:
	match kind:
		MAGNET:
			gems.magnetise_all()
		FEAR:
			enemies.fear = true
		DAMAGE:
			enemies.damage_mult = DAMAGE_MULT
		SPEED:
			if active[SPEED] <= 0.0:
				stats.apply("move_speed", "mult", SPEED_MULT)
	active[kind] = DURATION[kind]
	collected.emit(kind)


func _tick_effects(dt: float) -> void:
	for kind in active.size():
		if active[kind] <= 0.0:
			continue
		active[kind] = maxf(0.0, active[kind] - dt)
		if active[kind] > 0.0:
			continue
		match kind:   # expired: undo
			FEAR:
				enemies.fear = false
			DAMAGE:
				enemies.damage_mult = 1.0
			SPEED:
				stats.apply("move_speed", "mult", 1.0 / SPEED_MULT)


func count() -> int:
	return _pickups.size()


## BBCode for the HUD: active timed power-ups with seconds left.
func status_text() -> String:
	var parts: Array[String] = []
	for kind in [FEAR, DAMAGE, SPEED]:
		if active[kind] > 0.0:
			parts.append("[color=#%s]%s %ds[/color]" % [COLORS[kind].to_html(false), tr(NAMES[kind]).to_upper(), ceili(active[kind])])
	return "   ".join(parts)
