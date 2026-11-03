class_name ItemDrops
extends Node3D
## Items come from the world, not from level-ups. When a tree, fallen log or burnable prop
## finishes burning (Events.prop_burnt) it drops a random item that can still level up; on the
## Graveyard you can also open a crypt (Activate at its door) and on the Desert a statue (Activate
## at its base): the item comes out and the crypt / statue sinks into the ground, used up. Very
## rarely (SHARD_CHANCE) a shard of the current map drops instead.
## An item hovers where it lands, spinning and glowing in its colour; walk over it (pulled in by
## your pickup range) and main.found_item() pauses the run to show what you got.

signal picked(pick: Dictionary)   # {id, rarity}

const LOOT_GROUP := "loot_source"     # crypts / statues you can open (meta "use_at", "loot_kind")
const SHARD_CHANCE := 0.02
const USE_DIST := 3.6                 # how close to a crypt door / statue you must stand
const PICKUP_DIST := 1.3
const HOVER := 0.9
const SINK_TIME := 2.6

var main: Node
var shard_chance := SHARD_CHANCE
var drops: Array = []                 # {node, spin, id, rarity, from, to, t, time, landed, pulled, age}
var _icon_tex := {}                   # item id -> ViewportTexture of its UpgradeIcon
var _prompt: ActivatePrompt
var _near: Node3D = null
var _sfx := {}


func setup(p_main: Node) -> void:
	main = p_main


func _ready() -> void:
	Events.prop_burnt.connect(_on_prop_burnt)
	_prompt = ActivatePrompt.new()
	_prompt.top_level = true
	add_child(_prompt)


func _exit_tree() -> void:
	if Events.prop_burnt.is_connected(_on_prop_burnt):
		Events.prop_burnt.disconnect(_on_prop_burnt)


func _on_prop_burnt(at: Vector3) -> void:
	if main == null or main.state in ["dead", "won"]:
		return
	loot(at)


## Drop a random item (or, rarely, a shard of this map) bursting out of `at`. Returns what dropped:
## an item id, "shard:<kind>", or "" if every item is maxed.
func loot(at: Vector3, toward := Vector3.INF) -> String:
	if main.rng.randf() < shard_chance and main.aftermath != null:
		var kinds: Array = Wallet.map_shards(Settings.selected_map)
		var kind: String = kinds[main.rng.randi() % kinds.size()]
		main.aftermath.drops.drop({kind: 1}, at, main.rng, main.aftermath._good_ground, main.player.global_position)
		return "shard:" + kind
	var id: String = main.db.roll_item()
	if id == "":
		return ""
	var pick: Dictionary = main.db.item_pick(id, main.stats.value("luck"))
	spawn(pick, at, toward)
	return id


func spawn(pick: Dictionary, at: Vector3, toward := Vector3.INF) -> void:
	var rng: RandomNumberGenerator = main.rng
	var from := at + Vector3(0, 1.6, 0)
	var to := at
	var dir := Vector3(toward.x - at.x, 0, toward.z - at.z) if toward != Vector3.INF else Vector3.ZERO
	for tries in 10:   # land on good ground a few metres out (toward the player for doors)
		var a := (atan2(dir.z, dir.x) + rng.randf_range(-0.5, 0.5)) if dir.length() > 0.1 else rng.randf() * TAU
		var q := at + Vector3(cos(a), 0, sin(a)) * rng.randf_range(1.8, 3.2) * (1.0 - tries * 0.08)
		if main.aftermath == null or main.aftermath._good_ground(q):
			to = q
			break
	to.y = SwampWater.height_at(to.x, to.z)
	var d: Dictionary = main.db.defs[pick["id"]]
	var tint := Color.html(str(d["icon"].get("tint", "#ffd060")))
	var rcol := Color.html(str(main.db.rarities[int(pick["rarity"])]["color"]))
	var root := Node3D.new()
	root.top_level = true
	add_child(root)
	root.global_position = from
	var spin := Node3D.new()
	root.add_child(spin)
	var spr := Sprite3D.new()   # the item's charm icon, always facing you
	spr.texture = _icon(pick["id"])
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.pixel_size = 0.0075
	spr.shaded = false
	spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	spin.add_child(spr)
	var halo := MeshInstance3D.new()   # a soft rarity-coloured glow behind it
	var qm := QuadMesh.new()
	qm.size = Vector2(1.7, 1.7)
	halo.mesh = qm
	halo.material_override = _halo_mat(rcol)
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	halo.position.z = -0.02
	root.add_child(halo)
	var light := OmniLight3D.new()
	light.light_color = tint
	light.light_energy = 1.4
	light.omni_range = 4.0
	root.add_child(light)
	var ring := GroundDisc.create(0.75, Color(rcol, 0.35), true)
	ring.top_level = true
	ring.visible = false
	add_child(ring)
	drops.append({"node": root, "spin": spin, "ring": ring, "id": pick["id"], "rarity": int(pick["rarity"]),
		"from": from, "to": to, "t": 0.0, "time": rng.randf_range(0.7, 0.9), "peak": rng.randf_range(2.2, 3.2),
		"landed": false, "pulled": false, "age": 0.0})
	_play("item_drop", at, -4.0)


func _physics_process(dt: float) -> void:
	if main == null or main.state != "playing" or main.intro:
		_prompt.visible = false
		return
	_tick_drops(dt)
	_tick_sources()


func _tick_drops(dt: float) -> void:
	var feet: Vector3 = main.player.global_position
	var target := feet + Vector3(0, 0.9, 0)
	var reach: float = main.stats.value("pickup_range")
	for k in range(drops.size() - 1, -1, -1):
		var d: Dictionary = drops[k]
		var root: Node3D = d["node"]
		d["age"] = float(d["age"]) + dt
		if not d["landed"]:
			d["t"] = float(d["t"]) + dt
			var f := clampf(float(d["t"]) / float(d["time"]), 0.0, 1.0)
			var p: Vector3 = (d["from"] as Vector3).lerp(d["to"] + Vector3(0, HOVER, 0), f)
			p.y += float(d["peak"]) * 4.0 * f * (1.0 - f)
			root.global_position = p
			if f >= 1.0:
				d["landed"] = true
				var ring: GroundDisc = d["ring"]
				ring.global_position = d["to"] + Vector3(0, 0.05, 0)
				ring.visible = true
			continue
		var spin: Node3D = d["spin"]
		spin.position.y = 0.12 * sin(float(d["age"]) * 2.4)
		var to := target - root.global_position
		var dist := to.length()
		if dist < reach:
			d["pulled"] = true
		if d["pulled"]:
			root.global_position += to.normalized() * minf(dist, (9.0 + float(d["age"])) * dt * 2.0)
			(d["ring"] as Node3D).visible = false
		if dist < PICKUP_DIST:
			(d["ring"] as Node).queue_free()
			root.queue_free()
			drops.remove_at(k)
			picked.emit({"id": d["id"], "rarity": d["rarity"]})
			return   # one per tick: each pickup pauses the run for its card


## Crypts and statues: show "Press E" at the nearest one in reach and open it on a press.
func _tick_sources() -> void:
	var p: Vector3 = main.player.global_position
	var best: Node3D = null
	var best_d := USE_DIST
	for s in get_tree().get_nodes_in_group(LOOT_GROUP):
		var n := s as Node3D
		var at: Vector3 = n.get_meta("use_at", n.global_position)
		var dd := Vector2(at.x - p.x, at.z - p.z).length()
		if dd < best_d and absf(at.y - p.y) < 4.0:
			best_d = dd
			best = n
	_near = best
	_prompt.visible = best != null
	if best == null:
		return
	_prompt.global_position = (best.get_meta("use_at") as Vector3) + Vector3(0, 2.6, 0)
	if main.player.take_activate():
		open_source(best)


## Open a crypt / statue: the item (or a rare shard) comes out, then it sinks into the ground.
func open_source(n: Node3D) -> String:
	if not n.is_in_group(LOOT_GROUP):
		return ""
	n.remove_from_group(LOOT_GROUP)
	var at: Vector3 = n.get_meta("use_at", n.global_position)
	var kind: String = n.get_meta("loot_kind", "crypt")
	_play("crypt_open" if kind == "crypt" else "statue_crack", at, 0.0)
	var got := loot(at, main.player.global_position)
	sink(n)
	return got


## Sink a crypt / statue into the earth over SINK_TIME, rumbling and shaking dust off, then
## remove it (collision first, so nothing gets stuck in it).
func sink(n: Node3D) -> void:
	for c in n.find_children("*", "CollisionShape3D", true, false):
		(c as CollisionShape3D).set_deferred("disabled", true)
	var aabb := AABB()
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		aabb = aabb.merge((mi as MeshInstance3D).get_aabb())
	var depth := maxf(aabb.end.y * n.global_basis.get_scale().y, 3.0) + 0.6
	var lamp: Node = n.get_meta("light", null) if n.has_meta("light") else null
	_play("sink_rumble", n.global_position, 0.0)
	if main.player.global_position.distance_to(n.global_position) < 25.0:
		main.player.add_shake(0.35)
	var tw := n.create_tween()
	tw.set_parallel(true)
	tw.tween_property(n, "global_position:y", n.global_position.y - depth, SINK_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_method(func(t: float): n.rotation.z = sin(t * 40.0) * 0.012 * (1.0 - t), 0.0, 1.0, SINK_TIME)   # a grinding judder
	if lamp is OmniLight3D and is_instance_valid(lamp):   # its lantern goes out with it ("base": the flicker)
		var l := lamp as OmniLight3D
		tw.tween_method(func(e: float):
			if is_instance_valid(l):
				l.set_meta("base", e)
				l.light_energy = e, l.light_energy, 0.0, SINK_TIME * 0.6)
	tw.chain().tween_callback(func():
		if lamp != null and is_instance_valid(lamp):
			lamp.queue_free()
		n.queue_free())
	if main.fx != null:
		for k in 6:
			var a := TAU * k / 6.0
			main.fx.burst(n.global_position + Vector3(cos(a) * 2.5, 0.4, sin(a) * 2.5), 1.6, Color(0.55, 0.5, 0.42, 0.6), 0.6)


## The item's charm icon (UpgradeIcon) rendered once into a texture, cached per item.
func _icon(id: String) -> Texture2D:
	if _icon_tex.has(id):
		return _icon_tex[id]
	var vp := SubViewport.new()
	vp.size = Vector2i(128, 128)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var ic := UpgradeIcon.create(main.db.defs[id].get("icon", {}), "item")
	ic.size = Vector2(128, 128)
	vp.add_child(ic)
	add_child(vp)
	_icon_tex[id] = vp.get_texture()
	return _icon_tex[id]


func _halo_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var g := GradientTexture2D.new()
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	var gr := Gradient.new()
	gr.set_color(0, Color(c, 0.75))
	gr.set_color(1, Color(c, 0.0))
	g.gradient = gr
	m.albedo_texture = g
	return m


func _play(sname: String, at: Vector3, db: float) -> void:
	if not _sfx.has(sname):
		var a := AudioStreamPlayer3D.new()
		a.bus = Settings.SFX_BUS
		a.unit_size = 18.0
		a.max_distance = 90.0
		a.max_polyphony = 3
		var path := "res://audio/items/%s.wav" % sname
		if ResourceLoader.exists(path):
			a.stream = load(path)
		add_child(a)
		_sfx[sname] = a
	var p: AudioStreamPlayer3D = _sfx[sname]
	if p.stream != null:
		p.global_position = at
		p.volume_db = db
		p.play()


func count() -> int:
	return drops.size()
