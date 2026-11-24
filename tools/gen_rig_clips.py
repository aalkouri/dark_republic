"""Turns an auto-rigged character (UniRig: bones named bone_0, bone_1, ...; no clips) into a model
the game can play: finds the hips, spine, head, arms and legs from the skeleton's shape, renames
them to the Meshy names the game expects (Hips, Spine02, RightHand, ...), stands the model on the
ground at its in-game height facing the right way, and writes five clips made here in code (idle,
run, hit, attack, ability) plus, for crowd enemies, a death. The result goes to
<out dir>/<id>/<id>.glb; tools/extract_clips.gd then saves its clips as anims.res.

  blender -b --factory-startup --python tools/gen_rig_clips.py -- <rigged dir> <out dir> [--dry] [--faces=N] id[:height] ...

--dry only prints what each bone was taken for. --faces=N decimates the mesh (crowd enemies).
"""
import bpy, sys, os, math
from mathutils import Quaternion, Vector

FPS = 30
argv = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = argv[0], argv[1]
DRY = "--dry" in argv
FACES = next((int(a.split("=")[1]) for a in argv if a.startswith("--faces=")), 0)
IDS = [a for a in argv[2:] if not a.startswith("--")]


def chain(b):
    """b and its descendants, always following the child with the deepest subtree."""
    out = [b]
    while b.children:
        b = max(b.children, key=depth)
        out.append(b)
    return out


def depth(b):
    return 1 + max((depth(c) for c in b.children), default=0)


def subtree(b):
    out = [b]
    for c in b.children:
        out += subtree(c)
    return out


def classify(arm):
    bones = arm.data.bones
    zs = [b.head_local.z for b in bones] + [b.tail_local.z for b in bones]
    H = max(zs) - min(zs)
    hips = next(b for b in bones if b.parent is None)
    while len(hips.children) == 1:
        hips = hips.children[0]
    names = {hips.name: "Hips"}
    legs, ups = [], []
    for c in hips.children:
        lo = min(x.tail_local.z for x in subtree(c))
        hi = max(x.tail_local.z for x in subtree(c))
        if hi - hips.head_local.z > 0.12 * H and hi - hips.head_local.z > hips.head_local.z - lo:
            ups.append(c)
        elif hips.head_local.z - lo > 0.12 * H and abs(c.tail_local.x) > 0.01 * H:
            legs.append(c)
    spine = max(ups, key=lambda c: len(subtree(c))) if ups else None
    for c in sorted(legs, key=lambda c: -len(subtree(c))):
        side = "Left" if c.tail_local.x > 0 else "Right"
        if side + "UpLeg" in names.values():
            continue
        for b, n in zip(chain(c), ["UpLeg", "Leg", "Foot", "ToeBase"]):
            names[b.name] = side + n
    if spine:
        sp = [spine]
        while len(sp[-1].children) == 1:
            sp.append(sp[-1].children[0])
        chest = sp[-1]
        if len(sp) == 1:
            lab = ["Spine02"]
        elif len(sp) == 2:
            lab = ["Spine", "Spine02"]
        else:
            lab = ["Spine"] + ["Spine01"] * (len(sp) - 2) + ["Spine02"]
        seen = set()
        for b, n in zip(sp, lab):
            if n in seen:
                n = "SpineMid%d" % len(seen)
            seen.add(n)
            names[b.name] = n
        arms, necks = [], []
        for c in chest.children:
            reach = max(abs(x.tail_local.x) for x in subtree(c))
            top = max(x.tail_local.z for x in subtree(c))
            if reach > 0.13 * H and abs(c.tail_local.x) > 0.03 * H:
                arms.append(c)
            elif top > chest.tail_local.z:
                necks.append(c)
        for c in sorted(arms, key=lambda c: -len(subtree(c))):
            side = "Left" if c.tail_local.x > 0 else "Right"
            if side + "Arm" in names.values():
                continue
            ch = chain(c)
            # the hand is where the fingers branch, or the 4th bone
            hand_i = next((i for i, b in enumerate(ch) if len(b.children) > 1), min(3, len(ch) - 1))
            hand_i = min(max(hand_i, 2), 3)
            lab = ["Shoulder", "Arm", "ForeArm", "Hand"] if hand_i == 3 else ["Arm", "ForeArm", "Hand"]
            for b, n in zip(ch, lab):
                names[b.name] = side + n
        if necks:
            nk = chain(max(necks, key=lambda c: max(x.tail_local.z for x in subtree(c))))
            if len(nk) == 1:
                names[nk[0].name] = "Head"
            else:
                names[nk[0].name] = "neck"
                names[nk[1].name] = "Head"
    return names, H


def q(axis, deg):
    return Quaternion({"x": (1, 0, 0), "y": (0, 1, 0), "z": (0, 0, 1)}[axis], math.radians(deg))


def ss(a, b, t):
    """0 before a, 1 after b, smooth between."""
    if t <= a:
        return 0.0
    if t >= b:
        return 1.0
    x = (t - a) / (b - a)
    return x * x * (3 - 2 * x)


def bump(t, a, b, c, d):
    """Rises a..b, holds, falls c..d."""
    return ss(a, b, t) * (1.0 - ss(c, d, t))


# Each clip: t -> ({bone: [(axis, degrees), ...]}, hips drop as a fraction of the height).
# Axes are the model's: x = its left, z = up, it faces -y. Turning about +x tips the top forward.
def c_idle(t):
    s = math.sin(2 * math.pi * t / 2.4)
    return {"Spine02": [("x", 1.5 * s)], "Head": [("x", -1.0 * s)],
            "LeftArm": [("y", 2.0 * s)], "RightArm": [("y", -2.0 * s)]}, 0.004 * s


def c_run(t):
    p = 2 * math.pi * t / 0.7
    s, c = math.sin(p), math.cos(p)
    return {
        "Hips": [("z", 6 * s)], "Spine": [("x", 7)], "Spine02": [("z", -10 * s)], "Head": [("x", -4)],
        "LeftUpLeg": [("x", -8 + 34 * s)], "RightUpLeg": [("x", -8 - 34 * s)],
        "LeftLeg": [("x", 10 + 48 * max(0.0, -c))], "RightLeg": [("x", 10 + 48 * max(0.0, c))],
        "LeftFoot": [("x", 8 * s)], "RightFoot": [("x", -8 * s)],
        "LeftArm": [("x", -30 * s)], "RightArm": [("x", 30 * s)],
        "LeftForeArm": [("x", -35 - 12 * s)], "RightForeArm": [("x", -35 + 12 * s)],
    }, -0.012 - 0.012 * abs(c)


def c_hit(t):
    k = bump(t, 0.05, 0.2, 0.3, 0.9)
    return {"Spine": [("x", -10 * k)], "Spine02": [("x", -12 * k)], "Head": [("x", -14 * k)],
            "LeftArm": [("y", -22 * k)], "RightArm": [("y", 22 * k)]}, -0.01 * k


def c_attack(t):
    w = bump(t, 0.0, 0.14, 0.16, 0.3)      # wind-up
    k = bump(t, 0.16, 0.32, 0.45, 0.8)     # thrust
    return {"Spine02": [("z", 14 * w - 22 * k)], "Spine": [("x", 6 * k)],
            "RightArm": [("x", 35 * w - 88 * k), ("y", 10 * k)], "RightForeArm": [("x", -60 * w - 8 * k)],
            "LeftArm": [("x", -14 * k)]}, -0.008 * k


def c_ability(t):
    a = bump(t, 0.05, 0.3, 0.6, 0.95)      # both hands pushed forward
    b = bump(t, 1.15, 1.45, 1.75, 2.05)    # arms flung wide and up
    up = bump(t, 2.25, 2.6, 2.72, 2.9)     # the ultimate: both arms overhead...
    dn = bump(t, 2.72, 2.92, 3.1, 3.38)    # ...slammed down
    return {
        "Spine": [("x", 5 * a - 6 * b - 10 * up + 20 * dn)], "Spine02": [("x", 4 * a - 8 * b - 10 * up + 14 * dn)],
        "Head": [("x", -8 * b - 12 * up + 6 * dn)],
        "LeftArm": [("x", -84 * a - 165 * up - 60 * dn), ("y", -105 * b)],
        "RightArm": [("x", -84 * a - 165 * up - 60 * dn), ("y", 105 * b)],
        "LeftForeArm": [("x", -10 * a - 20 * b - 10 * dn)], "RightForeArm": [("x", -10 * a - 20 * b - 10 * dn)],
        "LeftUpLeg": [("x", -22 * dn)], "RightUpLeg": [("x", -22 * dn)],
        "LeftLeg": [("x", 40 * dn)], "RightLeg": [("x", 40 * dn)],
    }, -0.01 * a - 0.07 * dn


def c_death(t):
    k = ss(0.0, 0.55, t)
    k = k * k
    return {"Spine": [("x", -12 * k)], "Head": [("x", -18 * k)],
            "LeftArm": [("y", -50 * k)], "RightArm": [("y", 50 * k)],
            "LeftUpLeg": [("x", 10 * k)], "RightUpLeg": [("x", 14 * k)]}, 0.0, -88 * k   # falls on its back


CLIPS = [("idle", 2.4, c_idle), ("run", 0.7, c_run), ("hit", 1.0, c_hit), ("attack", 1.0, c_attack),
         ("ability", 3.4, c_ability), ("death", 1.0, c_death)]


def build(spec):
    cid, _, hs = spec.partition(":")
    height = float(hs) if hs else 1.8
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, cid + ".glb"))
    sc = bpy.context.scene
    arm = next(o for o in sc.objects if o.type == "ARMATURE")
    for o in [o for o in sc.objects if o.type == "MESH" and o.find_armature() is None and not o.vertex_groups]:
        bpy.data.objects.remove(o)   # UniRig leaves a stray icosphere
    meshes = [o for o in sc.objects if o.type == "MESH"]
    names, H = classify(arm)
    got = sorted(names.values())
    want = ["Hips", "Spine02", "Head", "LeftArm", "LeftForeArm", "LeftHand", "RightArm", "RightForeArm", "RightHand",
            "LeftUpLeg", "LeftLeg", "RightUpLeg", "RightLeg"]
    print("CLASS %s bones=%d named=%d missing=%s" % (cid, len(arm.data.bones), len(names), [w for w in want if w not in got]))
    if DRY:
        print("   ", {v: k for k, v in names.items()})
        return
    for old, new in names.items():
        arm.data.bones[old].name = new   # vertex groups follow
    # stand it on the ground at its game height, centred
    pts = [m.matrix_world @ v.co for m in meshes for v in m.data.vertices]
    lo = Vector([min(p[i] for p in pts) for i in range(3)])
    hi = Vector([max(p[i] for p in pts) for i in range(3)])
    s = height / (hi.z - lo.z)
    for o in [arm] + [m for m in meshes if m.parent is None]:
        o.scale = o.scale * s
        o.location = (o.location - Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))) * s
    bpy.ops.object.select_all(action="DESELECT")
    for o in [arm] + meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    arm.name = "Armature"
    arm.data.name = "Armature"
    if FACES:
        for m in meshes:
            n = len(m.data.polygons)
            if n > FACES:
                bpy.context.view_layer.objects.active = m
                d = m.modifiers.new("dec", "DECIMATE")
                d.ratio = FACES / n
                # the decimate must sit above the armature modifier
                while m.modifiers[0] != d:
                    bpy.ops.object.modifier_move_up(modifier=d.name)
                bpy.ops.object.modifier_apply(modifier=d.name)
    bpy.context.view_layer.objects.active = arm
    rest = {b.name: b.matrix_local.to_quaternion() for b in arm.data.bones}
    arm.animation_data_create()
    sc.render.fps = FPS
    pbs = arm.pose.bones
    for pb in pbs:
        pb.rotation_mode = "QUATERNION"
    hips = pbs["Hips"]
    used = [n for n in names.values()]
    for cname, length, fn in CLIPS:
        act = bpy.data.actions.new(cname)
        arm.animation_data.action = act
        n = int(round(length * FPS))
        for f in range(n + 1):
            r = fn(f / FPS)
            pose, drop = r[0], r[1]
            fall = r[2] if len(r) > 2 else 0.0
            for bn in used:
                Q = Quaternion()
                for axis, deg in pose.get(bn, []):
                    Q = q(axis, deg) @ Q
                if bn == "Hips" and fall:
                    Q = q("x", fall) @ Q
                rb = rest[bn]
                pbs[bn].rotation_quaternion = rb.inverted() @ Q @ rb
                pbs[bn].keyframe_insert("rotation_quaternion", frame=f)
            off = Vector((0, 0, drop * height))
            if fall:   # pivot about the feet: the hips swing down and back
                hz = arm.data.bones["Hips"].head_local.z
                a = math.radians(-fall)
                off = Vector((0, hz * math.sin(a), hz * math.cos(a) - hz + 0.06 * height * math.sin(a)))
            hips.location = rest["Hips"].inverted() @ off
            hips.keyframe_insert("location", frame=f)
        tr = arm.animation_data.nla_tracks.new()
        tr.name = cname
        arm.animation_data.action = None
        st = tr.strips.new(cname, 0, act)
        st.name = cname
        for pb in pbs:
            pb.rotation_quaternion = Quaternion()
            pb.location = Vector()
    dst = os.path.join(OUT, cid)
    os.makedirs(dst, exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(dst, cid + ".glb"), export_format="GLB", export_animations=True,
                              export_animation_mode="NLA_TRACKS", export_frame_range=False, export_force_sampling=True,
                              export_optimize_animation_size=False, export_yup=True, export_skins=True,
                              export_image_format="JPEG", export_jpeg_quality=88)
    print("WROTE", cid, "height", height, "faces", sum(len(m.data.polygons) for m in meshes))


for spec in IDS:
    build(spec)
