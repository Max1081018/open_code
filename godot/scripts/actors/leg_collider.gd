class_name LegCollider
extends Node
## Feeds the posed thighs to the clothing's toon shaders every frame (see
## leg_collide.gdshaderinc): hip and knee of each leg in each clothing
## mesh's own space, and the capsule radii (hip, knee).

var skeleton: Skeleton3D
var bones: Array = []      ## [[upper, lower], [upper, lower]]
var radius := Vector2.ZERO
var meshes: Array = []     ## clothing MeshInstance3Ds


func _process(_delta: float) -> void:
	if skeleton == null or not is_instance_valid(skeleton):
		return
	var sg := skeleton.global_transform
	var pts := []
	for pair in bones:
		pts.append(sg * skeleton.get_bone_global_pose(pair[0]).origin)
		pts.append(sg * skeleton.get_bone_global_pose(pair[1]).origin)
	for m in meshes:
		var mi := m as MeshInstance3D
		if not mi.is_visible_in_tree():
			continue
		var inv := mi.global_transform.affine_inverse()
		for s in mi.get_surface_override_material_count():
			var mat := mi.get_surface_override_material(s) as ShaderMaterial
			if mat == null:
				continue
			for target in [mat, mat.next_pass]:
				var sm := target as ShaderMaterial
				if sm == null:
					continue
				sm.set_shader_parameter("leg_a0", inv * pts[0])
				sm.set_shader_parameter("leg_b0", inv * pts[1])
				sm.set_shader_parameter("leg_a1", inv * pts[2])
				sm.set_shader_parameter("leg_b1", inv * pts[3])
				sm.set_shader_parameter("leg_r", radius / maxf(mi.global_transform.basis.get_scale().x, 0.0001))
