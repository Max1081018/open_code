extends Node3D
## Dev harness for composing the shop: drops a model on a ground plane next to a
## 1.75 m reference figure and photographs it from eye height, so scale and
## layout can be judged before wiring anything into the game.
##
##   godot --path fishing res://tools/shoplab.tscn -- \
##       --model=res://assets/models/fishing/lakeside-bait-shop.glb \
##       --scale=0.38 --cam=0,1.62,9 --look=0,2,0 --shot=/tmp/shop.png

var model_path := "res://assets/models/fishing/lakeside-bait-shop.glb"
var model_scale := 0.38
var cam_pos := Vector3(0, 1.62, 9)
var look_at := Vector3(0, 2, 0)
var ref_pos := Vector3(1.9, 0.875, 2.6)
var shot := ""
var frame := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--model="): model_path = a.get_slice("=", 1)
		elif a.begins_with("--scale="): model_scale = float(a.get_slice("=", 1))
		elif a.begins_with("--shot="): shot = a.get_slice("=", 1)
		elif a.begins_with("--cam="): cam_pos = _v3(a.get_slice("=", 1))
		elif a.begins_with("--look="): look_at = _v3(a.get_slice("=", 1))
		elif a.begins_with("--ref="): ref_pos = _v3(a.get_slice("=", 1))

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.72, 0.9)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.68, 0.72, 0.78)
	env.ambient_light_energy = 0.75
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 40, 0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	add_child(sun)

	# Ground
	var g := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(120, 120)
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.45, 0.68, 0.36)
	pm.material = gm
	g.mesh = pm
	add_child(g)

	# The model under test
	var packed: PackedScene = load(model_path)
	var inst: Node3D = packed.instantiate()
	inst.scale = Vector3.ONE * model_scale
	add_child(inst)
	var box := _aabb(inst)
	print("MODEL %s scale=%.3f -> size=(%.2f, %.2f, %.2f) ymin=%.2f" % [
		model_path.get_file(), model_scale, box.size.x, box.size.y, box.size.z, box.position.y])

	# 1.75 m reference figure so scale is obvious
	var ref := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.3
	cap.height = 1.75
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.95, 0.25, 0.25)
	cap.material = rm
	ref.mesh = cap
	ref.position = ref_pos
	add_child(ref)

	var cam := Camera3D.new()
	cam.fov = 68
	cam.position = cam_pos
	add_child(cam)
	cam.look_at(look_at)


func _v3(s: String) -> Vector3:
	var p := s.split(",")
	if p.size() != 3:
		return Vector3.ZERO
	return Vector3(float(p[0]), float(p[1]), float(p[2]))


func _aabb(node: Node) -> AABB:
	var out := AABB()
	var first := true
	for n in _all(node):
		if n is MeshInstance3D and n.mesh:
			var a: AABB = n.global_transform * n.mesh.get_aabb()
			if first:
				out = a
				first = false
			else:
				out = out.merge(a)
	return out


func _all(node: Node) -> Array:
	var out := [node]
	for c in node.get_children():
		out.append_array(_all(c))
	return out


func _process(_d: float) -> void:
	frame += 1
	if frame > 12:
		if shot != "":
			get_viewport().get_texture().get_image().save_png(shot)
		print("SHOPLAB done")
		get_tree().quit()
