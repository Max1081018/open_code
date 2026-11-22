class_name AmbientLife
extends Node3D
## The world's small life, kept round the heroine: butterflies over the
## meadows by day, fireflies blinking in the grass at night, and a flock of
## birds wheeling high over the land.

const BIRDS := 9

var game: Node
var _butterflies: CPUParticles3D
var _fireflies: CPUParticles3D
var _bmat: ShaderMaterial
var _fmat: ShaderMaterial
var _birds: MultiMeshInstance3D
var _bird_centre := Vector3.ZERO
var _bird_seed: Array = []


func setup(the_game: Node) -> void:
	game = the_game
	var shader: Shader = load("res://scripts/shaders/critter.gdshader")
	_bmat = ShaderMaterial.new()
	_bmat.shader = shader
	_bmat.set_shader_parameter("kind", 0)
	_fmat = ShaderMaterial.new()
	_fmat.shader = shader
	_fmat.set_shader_parameter("kind", 1)
	_fmat.render_priority = 1
	_butterflies = _swarm(_bmat, 26, Vector3(22, 1.2, 22), 0.32, 8.0)
	var colours := Gradient.new()
	colours.offsets = PackedFloat32Array([0.0, 0.33, 0.66, 1.0])
	colours.colors = PackedColorArray([Color(0.95, 0.35, 0.6), Color(1.0, 0.72, 0.12), Color(0.3, 0.55, 1.0), Color(0.75, 0.45, 1.0)])
	_butterflies.color_initial_ramp = colours
	_fireflies = _swarm(_fmat, 110, Vector3(14, 1.0, 14), 0.42, 7.0)
	_build_birds()


func _swarm(mat: ShaderMaterial, amount: int, box: Vector3, size: float, life: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	p.mesh = quad
	p.material_override = mat
	p.amount = amount
	p.lifetime = life
	p.preprocess = life
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = box
	p.direction = Vector3(1, 0.2, 0)
	p.spread = 180.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.8
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.3
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p


## A loose flock of simple winged shapes.
func _build_birds() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Body and two wings as thin triangles; UV.x marks the wingtips for the flap.
	var pts := [[Vector3(0, 0, 0.35), 0.0], [Vector3(-0.08, 0, -0.25), 0.0], [Vector3(0.08, 0, -0.25), 0.0],
		[Vector3(0, 0, 0.12), 0.0], [Vector3(-0.9, 0.05, -0.1), 1.0], [Vector3(0, 0, -0.12), 0.0],
		[Vector3(0, 0, 0.12), 0.0], [Vector3(0, 0, -0.12), 0.0], [Vector3(0.9, 0.05, -0.1), 1.0]]
	for q in pts:
		st.set_uv(Vector2(q[1], 0))
		st.add_vertex(q[0])
	st.generate_normals()
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded, cull_disabled;
void vertex() {
	float id = float(INSTANCE_ID);
	VERTEX.y += UV.x * sin(TIME * 7.0 + id * 1.7) * 0.45;
}
void fragment() {
	ALBEDO = vec3(0.12, 0.13, 0.2);
}
"""
	mat.shader = sh
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var mesh := st.commit()
	mesh.surface_set_material(0, mat)
	mm.mesh = mesh
	mm.instance_count = BIRDS
	_birds = MultiMeshInstance3D.new()
	_birds.multimesh = mm
	_birds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_birds)
	for i in BIRDS:
		_bird_seed.append([randf_range(-8, 8), randf_range(-3, 3), randf_range(-8, 8), randf_range(0.9, 1.1)])


func _process(_delta: float) -> void:
	if game == null or game.player == null:
		return
	var p: Vector3 = game.player.global_position
	var night: float = clampf(1.0 - clampf(sin((game.time_of_day - 0.25) * TAU) * 3.0 + 0.2, 0.0, 1.0), 0.0, 1.0)
	var t := Time.get_ticks_msec() / 1000.0
	# Butterflies by day, over green land; fireflies after dark.
	var green: bool = game.world.biome_at(p) in [TerrainGen.Biome.FOREST, TerrainGen.Biome.DARK_FOREST]
	_butterflies.global_position = p + Vector3(0, 1.2, 0)
	_fireflies.global_position = p + Vector3(0, 0.9, 0)
	_butterflies.emitting = green and night < 0.5
	_fireflies.emitting = green and night > 0.3
	_bmat.set_shader_parameter("fade", clampf(1.0 - night * 2.0, 0.0, 1.0))
	_fmat.set_shader_parameter("fade", clampf(night * 1.6 - 0.2, 0.0, 1.0))
	# The flock wheels in a wide circle that drifts with the heroine.
	_bird_centre = _bird_centre.lerp(p, 0.002) if _bird_centre != Vector3.ZERO else p
	var mm := _birds.multimesh
	_birds.visible = night < 0.6
	for i in BIRDS:
		var sd: Array = _bird_seed[i]
		var a := t * 0.12 * float(sd[3]) + i * 0.08
		var r := 70.0 + float(sd[0])
		var pos := _bird_centre + Vector3(cos(a) * r + float(sd[2]), 55.0 + float(sd[1]) + sin(t * 0.5 + i) * 2.0, sin(a) * r)
		var fwd := Vector3(-sin(a), 0, cos(a))
		var basis := Basis.looking_at(-fwd, Vector3.UP).scaled(Vector3.ONE * 1.6)
		mm.set_instance_transform(i, Transform3D(basis, pos))
