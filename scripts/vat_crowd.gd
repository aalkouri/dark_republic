class_name VatCrowd
extends RefCounted
## Loads a vertex-animation bake (tools/bake_vat.gd) as a mesh + material for a MultiMesh.
##
## Per-instance data:
##   COLOR (instance color)  r = clip index / 4, g = phase in the clip (0..1)
##   INSTANCE_CUSTOM         rgb = tint, a = burn (0..1) + 2 if hit-flashing + 4 if epic
## The shader looks up the two baked frames around the phase and blends them, so playback is
## smooth at any speed. Clips are numbered in bake order (see vat.json).

const SHADER := """
shader_type spatial;

uniform sampler2D vat_pos : filter_nearest, repeat_disable;
uniform sampler2D vat_nrm : filter_nearest, repeat_disable;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform int verts = 1;
uniform int tex_w = 4096;
uniform vec4 clips[4];          // start frame, frame count, loop (1/0), unused
uniform float tint_amount = 0.35;

varying vec3 tint;
varying float burn;
varying float flash;
varying float epic;

ivec2 texel(int frame, int vid) {
	int idx = frame * verts + vid;
	return ivec2(idx % tex_w, idx / tex_w);
}

void vertex() {
	int clip = clamp(int(COLOR.r * 4.0 + 0.5), 0, 3);
	vec4 c = clips[clip];
	int start = int(c.x);
	int frames = max(int(c.y), 1);
	bool loop = c.z > 0.5;
	float f = clamp(COLOR.g, 0.0, 1.0) * float(loop ? frames : frames - 1);
	int f0 = min(int(floor(f)), frames - 1);
	int f1 = loop ? (f0 + 1) % frames : min(f0 + 1, frames - 1);
	float w = fract(f);
	int vid = int(CUSTOM0.x + 0.5);     // baked vertex index
	vec3 p0 = texelFetch(vat_pos, texel(start + f0, vid), 0).rgb;
	vec3 p1 = texelFetch(vat_pos, texel(start + f1, vid), 0).rgb;
	vec3 n0 = texelFetch(vat_nrm, texel(start + f0, vid), 0).rgb * 2.0 - 1.0;
	vec3 n1 = texelFetch(vat_nrm, texel(start + f1, vid), 0).rgb * 2.0 - 1.0;
	VERTEX = mix(p0, p1, w);
	NORMAL = normalize(mix(n0, n1, w));

	float a = INSTANCE_CUSTOM.a;
	epic = step(3.5, a);
	a -= epic * 4.0;
	flash = step(1.5, a);
	a -= flash * 2.0;
	burn = clamp(a, 0.0, 1.0);
	tint = INSTANCE_CUSTOM.rgb;
}

void fragment() {
	vec3 col = texture(albedo_tex, UV).rgb;
	col = mix(col, col * tint * 1.8, tint_amount);
	col = mix(col, col * vec3(0.95, 0.55, 1.35), epic * 0.85);
	col = mix(col, vec3(1.0, 0.42, 0.08), burn * 0.6);
	EMISSION = vec3(1.0, 0.32, 0.04) * burn * 0.9 + vec3(0.45, 0.1, 0.8) * epic * 0.3;
	// Hit: a brief reddish tint. (A pure-white flash read as bright white dots on goblins
	// far away in the fog.)
	ALBEDO = mix(col, col * vec3(1.45, 0.55, 0.45), flash * 0.6);
	ROUGHNESS = 0.85;
}
"""

var mesh: ArrayMesh
var material: ShaderMaterial
var clip_index := {}     # name -> index (bake order)
var clip_length := {}    # name -> seconds
var height := 1.0        # top of the model at scale 1


static func load_bake(dir: String) -> VatCrowd:
	var v := VatCrowd.new()
	var info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("vat.json")))
	v.mesh = (load(dir.path_join("vat_mesh.res")) as ArrayMesh).duplicate() as ArrayMesh
	var sh := Shader.new()
	sh.code = SHADER
	v.material = ShaderMaterial.new()
	v.material.shader = sh
	v.material.set_shader_parameter("vat_pos", load(dir.path_join("vat_pos.res")))
	v.material.set_shader_parameter("vat_nrm", load(dir.path_join("vat_nrm.res")))
	var albedo := dir.path_join("albedo.png")
	if ResourceLoader.exists(albedo):
		v.material.set_shader_parameter("albedo_tex", load(albedo))
	v.material.set_shader_parameter("verts", int(info["verts"]))
	v.material.set_shader_parameter("tex_w", int(info["tex_w"]))
	var table: Dictionary = info["clips"]
	# Order clips by start frame = bake order
	var names := table.keys()
	names.sort_custom(func(a, b): return float(table[a]["start"]) < float(table[b]["start"]))
	var packed := PackedVector4Array()
	packed.resize(4)
	for k in names.size():
		var c: Dictionary = table[names[k]]
		packed[k] = Vector4(float(c["start"]), float(c["frames"]), 1.0 if c["loop"] else 0.0, 0.0)
		v.clip_index[names[k]] = k
		v.clip_length[names[k]] = float(c["length"])
	v.material.set_shader_parameter("clips", packed)
	var bb: Array = info["aabb"]
	v.height = float(bb[4])
	v.mesh.custom_aabb = AABB(Vector3(bb[0], bb[1], bb[2]), Vector3(bb[3] - bb[0], bb[4] - bb[1], bb[5] - bb[2]))
	v.mesh.surface_set_material(0, v.material)
	return v


## Instance color for a clip at a phase (0..1).
func anim_color(clip: String, phase: float) -> Color:
	return Color(float(clip_index.get(clip, 0)) / 4.0, phase, 0.0, 1.0)
