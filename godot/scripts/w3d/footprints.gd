class_name Footprints
extends MultiMeshInstance3D
## Footprints pressed into sand and snow: one MultiMesh (a single draw call)
## of small oval impressions — a shaded hollow with a lighter, pushed-up rim —
## laid along the ground's slope. Each print fades over LIFE seconds; the
## oldest is reused when the ring is full.
##   press(at, yaw, normal, snow)

const COUNT := 96
const LIFE := 40.0

var _next := 0
var _born := PackedFloat32Array()
var _t := 0.0


func _ready() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2(0.15, 0.3)
	q.orientation = PlaneMesh.FACE_Y
	mm.mesh = q
	mm.instance_count = COUNT
	multimesh = mm
	_born.resize(COUNT)
	for i in COUNT:
		_born[i] = -1000.0
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3.ZERO))
		mm.set_instance_custom_data(i, Color(0, 0, 0, 0))
	var m := ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = """shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
varying vec4 data;
void vertex() { data = INSTANCE_CUSTOM; }
void fragment() {
	// An oval sole and a rounder heel; a dark hollow inside, a pale rim.
	vec2 p = UV * 2.0 - 1.0;
	float sole = length(vec2(p.x * 1.35, (p.y + 0.28) * 0.95));
	float heel = length(vec2(p.x * 1.6, (p.y - 0.58) * 1.6));
	float d = min(sole, heel);
	float hollow = 1.0 - smoothstep(0.55, 0.72, d);
	float rim = smoothstep(0.62, 0.74, d) * (1.0 - smoothstep(0.74, 0.95, d));
	vec3 tint = data.y > 0.5 ? vec3(0.62, 0.7, 0.85) : vec3(0.45, 0.32, 0.2);
	ALBEDO = mix(tint, vec3(1.0, 0.95, 0.85), rim);
	ALPHA = (hollow * 0.6 + rim * 0.25) * data.x;
}"""
	material_override = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	top_level = true
	global_transform = Transform3D.IDENTITY
	custom_aabb = AABB(Vector3(-5000, -500, -5000), Vector3(10000, 1000, 10000))


## Press one print: `yaw` is the walking direction, `normal` the ground's.
func press(at: Vector3, yaw: float, normal: Vector3, snow := false) -> void:
	var i := _next
	_next = (_next + 1) % COUNT
	var up := normal.normalized()
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	fwd = (fwd - up * fwd.dot(up)).normalized()
	var right := up.cross(fwd).normalized()
	var b := Basis(right, up, -fwd)
	multimesh.set_instance_transform(i, Transform3D(b, at + up * 0.015))
	multimesh.set_instance_custom_data(i, Color(1.0, 1.0 if snow else 0.0, 0, 0))
	_born[i] = _t


func _process(delta: float) -> void:
	_t += delta
	# Fade a slice of the ring each frame (cheap: a few prints per frame).
	for k in 8:
		var i := (Engine.get_process_frames() * 8 + k) % COUNT
		var age := _t - _born[i]
		if age < 0.0 or age > LIFE + 2.0:
			continue
		var fade := clampf(1.0 - (age - LIFE * 0.6) / (LIFE * 0.4), 0.0, 1.0)
		var c := multimesh.get_instance_custom_data(i)
		c.r = fade
		multimesh.set_instance_custom_data(i, c)
