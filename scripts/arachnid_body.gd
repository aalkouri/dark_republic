class_name ArachnidBody
extends SpiderModel
## The Arachnid as a playable character: the Castle boss's code-built spider (SpiderModel) at
## player size - about 1.5 m tall and 3 m across the legs. The legs walk themselves (feet stay
## planted until the body has moved on, then step in two alternating groups), so running is
## just moving; on top of that it bobs and leans as it runs, sways and breathes when idle,
## jabs its head forward with each Venom Spit (the drops of venom on its fangs flare green),
## rears up clawing the air when it casts, recoils when hit, lets its legs hang in the air when
## it jumps, and curls its legs up when it dies. Faces -Z, origin at the feet.

const SIZE := 0.42
const VENOM := Color(0.55, 1.0, 0.2)

var spits := 0                     # Venom Spit jabs (tests)
var dead := false
var _spit := 0.0
var _hurt := 0.0
var _dim := 1.0
var _time := 0.0
var _base: Array[Color] = []
var _venom_mat: StandardMaterial3D
var _last := Vector3.INF


static func create() -> ArachnidBody:
	var b := ArachnidBody.new()
	b.scale = Vector3.ONE * SIZE
	b.step_scaled = true
	return b


func _ready() -> void:
	super()
	for m in _mats:
		_base.append(m.albedo_color)
	# A drop of venom hanging off each fang
	_venom_mat = StandardMaterial3D.new()
	_venom_mat.albedo_color = VENOM
	_venom_mat.emission_enabled = true
	_venom_mat.emission = VENOM
	_venom_mat.emission_energy_multiplier = 1.5
	for s in [-1.0, 1.0]:
		var d := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.1
		sm.height = 0.24
		sm.material = _venom_mat
		d.mesh = sm
		d.position = Vector3(0.28 * s, HIP_Y - 0.6, -1.82)
		_body.add_child(d)


## One Venom Spit: the head jabs forward and the venom flares.
func spit() -> void:
	_spit = 1.0
	spits += 1


func die() -> void:
	dead = true


## Where the venom globs leave from: between the fangs.
func tip() -> Vector3:
	return _body.global_transform * Vector3(0, HIP_Y - 0.45, -1.95)


## Called every frame by RosterHero / RosterModel: ground speed, in the air or not, the cast
## pulse (1 -> 0) and the hit flinch (1 -> 0).
func animate(dt: float, speed: float, airborne: bool, swell := 0.0, flinch := 0.0) -> void:
	_time += dt
	_spit = maxf(0.0, _spit - dt * 5.0)
	var lean := clampf(speed / 7.0, 0.0, 1.0)
	var j := sin(_spit * PI)
	# Teleported (entrance, respawn): put the feet down where they belong at once
	if _last != Vector3.INF and global_position.distance_to(_last) > 3.0:
		plant_all()
	_last = global_position
	if dead:
		curl = move_toward(curl, 1.0, dt * 1.6)
		crouch = move_toward(crouch, 0.6, dt * 1.2)
		rear = 0.0
		pitch = 0.0
		nudge = Vector3.ZERO
		_venom_mat.emission_energy_multiplier = 0.3
		return
	# Rearing up for a cast, front legs clawing the air
	rear = sin(clampf(swell, 0.0, 1.0) * PI)
	crouch = 0.12 * lean
	# Head jab with each spit; a lean and a scuttling bob as it runs; a jolt back when hit
	pitch = 0.32 * j + 0.08 * lean - 0.3 * flinch
	var bob := 0.12 * absf(sin(_time * (10.0 + speed * 1.2))) * lean
	var sway := 0.06 * sin(_time * 1.3) * (1.0 - lean)
	nudge = Vector3(sway, bob - 0.15 * j, -0.35 * j + 0.3 * flinch)
	# In the air the legs hang under the body instead of staying on the ground
	if airborne:
		plant_all()
	_venom_mat.emission_energy_multiplier = 1.5 + 5.0 * j + 1.5 * rear


func set_dim(f: float) -> void:
	_dim = f
	for k in _mats.size():
		var c := _base[k]
		_mats[k].albedo_color = Color(c.r * f, c.g * f, c.b * f, c.a)


func set_hurt(f: float) -> void:
	_hurt = f


func _process(dt: float) -> void:
	super(dt)
	if _hurt > 0.0:
		for m in _mats:
			m.emission = m.emission + Color(1.0, 0.85, 0.75) * _hurt
