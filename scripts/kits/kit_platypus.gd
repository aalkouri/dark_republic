class_name KitPlatypus
extends KitPart
## Sentient Platypus
##   1  Electro-Bill   30 s  an electric pulse to 15 m: 60 damage and a 1.5 s stun
##   2  Egg Clutch     45 s  lays 4 eggs round him that hatch after 2 s: each puggle explodes for
##                           80 within 4 m and poisons
##   3  The Lecture   120 s  every enemy within 25 m falls asleep for 6 s (the boss is only
##                           slowed) and takes +25% damage while it sleeps

const BILL_RADIUS := 15.0
const BILL_DAMAGE := 60.0
const BILL_STUN := 1.5
const EGG_COUNT := 4
const EGG_HATCH := 2.0
const EGG_RADIUS := 4.0
const EGG_DAMAGE := 80.0
const EGG_POISON := 0.02
const LECTURE_RADIUS := 25.0
const LECTURE_TIME := 6.0

var _eggs: Array = []            # {node, t}
var _lecture_t := 0.0


func cast(i: int) -> void:
	src(i)
	match i:
		0: _electro_bill()
		1: _egg_clutch()
		2: _lecture()


func active(name: String) -> bool:
	match name:
		"eggs": return not _eggs.is_empty()
		"lecture": return _lecture_t > 0.0
	return false


func tick(dt: float) -> void:
	src(1)
	for k in range(_eggs.size() - 1, -1, -1):
		var e: Dictionary = _eggs[k]
		e["t"] = float(e["t"]) - dt
		var node: Node3D = e["node"]
		node.rotation.z = sin(float(e["t"]) * 25.0) * 0.15 * (1.0 - float(e["t"]) / EGG_HATCH)   # wobbling, about to hatch
		if float(e["t"]) <= 0.0:
			var at := node.global_position
			var d := EGG_DAMAGE * dmg() * pw(1)
			for i in near(at, EGG_RADIUS):
				enemies.damage(i, d)
				enemies.poison(i, EGG_POISON, 4.0, 5)
			fx.burst(at + Vector3(0, 0.4, 0), EGG_RADIUS * 0.8, Color(0.75, 1.0, 0.35), 0.4)
			ring(at, EGG_RADIUS, Color(0.75, 1.0, 0.4), 0.35)
			play("pop", -3.0)
			node.queue_free()
			_eggs.remove_at(k)
	if _lecture_t > 0.0:
		_lecture_t -= dt


# ------------------------------------------------------------------ Electro-Bill

func _electro_bill() -> void:
	play("electro_bill")
	var r := BILL_RADIUS * (0.8 + 0.2 * pw(0))
	var d := BILL_DAMAGE * dmg() * pw(0)
	for i in near(chest(), r):
		enemies.damage(i, d)
		enemies.stun(i, BILL_STUN)
		if randf() < 0.4:
			mote(chest(), (enemies.center_of(i) - chest()) * 5.0, 0.2, Color(0.6, 0.9, 1.0), 0.15, false, 0.0)
	for k in 3:
		after(k * 0.08, func(): ring(feet(), r * (0.4 + 0.3 * k), Color(0.55, 0.9, 1.0, 0.7), 0.3))
	flash_light(chest(), Color(0.6, 0.85, 1.0), 4.0, r, 0.3)


# ------------------------------------------------------------------ Egg Clutch

func _egg_clutch() -> void:
	play("eggs")
	for k in EGG_COUNT:
		var a := TAU * k / EGG_COUNT + randf() * 0.3
		var at := ground(feet() + Vector3(cos(a), 0, sin(a)) * 2.5)
		var egg := MeshInstance3D.new()
		egg.mesh = HeroBody._sph(0.18)
		egg.scale = Vector3(0.85, 1.15, 0.85)
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.95, 0.92, 0.8)
		egg.material_override = m
		spawn(egg, at + Vector3(0, 0.2, 0))
		_eggs.append({"node": egg, "t": EGG_HATCH})


# ------------------------------------------------------------------ The Lecture

func _lecture() -> void:
	play("lecture")
	for i in near(feet(), LECTURE_RADIUS):
		if enemies.is_boss(i):
			enemies.slow(i, 0.5, LECTURE_TIME)
		else:
			enemies.stun(i, LECTURE_TIME)   # fast asleep
			enemies.curse(i, LECTURE_TIME)
			if randf() < 0.3:
				var z := Label3D.new()
				z.text = "Zz"
				z.font_size = 64
				z.pixel_size = 0.006
				z.billboard = BaseMaterial3D.BILLBOARD_ENABLED
				z.modulate = Color(0.85, 0.9, 1.0)
				spawn(z, enemies.center_of(i) + Vector3(0, 0.8, 0))
				var tw := z.create_tween()
				tw.tween_property(z, "position:y", z.position.y + 1.2, LECTURE_TIME)
				tw.parallel().tween_property(z, "modulate:a", 0.0, LECTURE_TIME)
				tw.tween_callback(z.queue_free)
	_lecture_t = LECTURE_TIME
	ring(feet(), LECTURE_RADIUS, Color(0.8, 0.85, 1.0, 0.5), 0.8)
