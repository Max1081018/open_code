extends Node3D
## Dev harness: lays every imported model out in a grid so you can eyeball that
## the GLBs load with their textures. Run it headlessly:
##   godot --path fishing res://tools/assetcheck.tscn -- --shot=/tmp/assets.png
## It screenshots after a few frames and quits.

const MODELS := [
	"res://assets/models/fishing/lakeside-bait-shop.glb",
	"res://assets/models/fishing/tackle-shop-counter.glb",
	"res://assets/models/fishing/stilted-fishing-hut.glb",
	"res://assets/models/fishing/fish-market-stand.glb",
	"res://assets/models/fishing/river-fish-set.glb",
	"res://assets/models/fishing/rarity-fish-set.glb",
	"res://assets/models/fishing/low-poly-ocean-fish-set.glb",
	"res://assets/models/fishing/junk-catches-set.glb",
	"res://assets/models/characters/Barbarian.glb",
	"res://assets/models/characters/Knight.glb",
	"res://assets/models/weapons/sword_A.gltf",
	"res://assets/models/weapons/dagger_A.gltf",
	"res://assets/models/weapons/axe_A.gltf",
	"res://assets/models/coast/lighthouse_tall.glb",
]

var shot := ""
var frame := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			shot = a.get_slice("=", 1)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.25, 0.33, 0.42)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.75, 0.8)
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 35, 0)
	sun.light_energy = 1.2
	add_child(sun)

	var cols := 5
	var spacing := 3.2
	for i in MODELS.size():
		var packed = load(MODELS[i])
		if packed == null:
			push_error("FAILED TO LOAD %s" % MODELS[i])
			continue
		var inst: Node3D = packed.instantiate()
		var col := i % cols
		var row := i / cols
		inst.position = Vector3((col - (cols - 1) * 0.5) * spacing, 0, -row * spacing)
		add_child(inst)
		# Report the model's size so we know what scale to use in the game.
		var aabb := _aabb_of(inst)
		print("MODEL %-22s size=(%.2f,%.2f,%.2f) ymin=%.2f ymax=%.2f xmin=%.2f zmin=%.2f" % [
			MODELS[i].get_file(), aabb.size.x, aabb.size.y, aabb.size.z,
			aabb.position.y, aabb.position.y + aabb.size.y, aabb.position.x, aabb.position.z])

	var cam := Camera3D.new()
	cam.position = Vector3(0, 7.5, 9.0)
	cam.rotation_degrees = Vector3(-32, 0, 0)
	cam.fov = 60
	add_child(cam)


func _aabb_of(node: Node) -> AABB:
	var box := AABB()
	var first := true
	for child in _all(node):
		if child is MeshInstance3D and child.mesh:
			var a: AABB = child.global_transform * child.mesh.get_aabb()
			if first:
				box = a
				first = false
			else:
				box = box.merge(a)
	return box


func _all(node: Node) -> Array:
	var out := [node]
	for c in node.get_children():
		out.append_array(_all(c))
	return out


func _process(_d: float) -> void:
	frame += 1
	if frame > 20:
		if shot != "":
			get_viewport().get_texture().get_image().save_png(shot)
		print("ASSETCHECK done")
		get_tree().quit()
