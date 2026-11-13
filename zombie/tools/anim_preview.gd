extends SceneTree
## Renders a strip of frames from one baked clip so a retarget can be checked
## by eye instead of by hope.
##   godot --path zombie --script res://tools/anim_preview.gd -- walk /tmp/out

const MODEL := "res://assets/chars/AtlasZombieLite_Walker.fbx"
const LIB := "res://assets/chars/zombie_anims.res"

var _ap: AnimationPlayer
var _clip := "walk"
var _out := "/tmp/zprev"
var _frame := 0
var _skel: Skeleton3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_clips = args[0].split(",")
		_clip = _clips[0]
	if args.size() > 1:
		_out = args[1]
	DirAccess.make_dir_recursive_absolute(_out)
	var root := get_root()
	var world := Node3D.new()
	root.add_child(world)
	var model: Node3D = (load(MODEL) as PackedScene).instantiate()
	world.add_child(model)
	_skel = model.find_children("*", "Skeleton3D", true, false)[0]
	_ap = model.find_children("*", "AnimationPlayer", true, false)[0]
	_ap.add_animation_library("z", load(LIB))
	print("bones rest: ", _skel.get_bone_name(1), "=", _skel.get_bone_global_rest(1).origin,
		"  head=", _skel.get_bone_global_rest(_skel.find_bone("head")).origin,
		"  footL=", _skel.get_bone_global_rest(_skel.find_bone("foot_L")).origin)
	var aabb := AABB()
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		aabb = aabb.merge((mi as MeshInstance3D).get_aabb())
	print("skel path from ap root: ", _ap.get_node(_ap.root_node).get_path_to(_skel))
	if _ap.has_animation("z/" + _clip):
		_ap.play("z/" + _clip)
	else:
		print("no clip ", _clip)

	var cam := Camera3D.new()
	world.add_child(cam)
	# The rig is modelled tiny and scaled up by its node, and a skinned mesh
	# reports its bind-pose box, so the camera is placed for the size the
	# character actually is rather than for what the box says.
	cam.position = Vector3(1.7, 1.05, 2.3)
	cam.look_at(Vector3(0, 0.8, 0))

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 35, 0)
	world.add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.25, 0.28, 0.32)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.65, 0.7)
	e.ambient_light_energy = 0.7
	env.environment = e
	world.add_child(env)


var _shot := 0
var _clips: PackedStringArray = ["walk"]
var _ci := 0
const SHOTS := 4

func _process(_d: float) -> bool:
	_frame += 1
	if _ci >= _clips.size():
		return true
	if _frame % 2 == 1:
		_ap.seek(_ap.current_animation_length * (0.08 + 0.84 * float(_shot) / float(SHOTS - 1)), true)
	else:
		get_root().get_texture().get_image().save_png("%s/%s_%d.png" % [_out, _clip, _shot])
		_shot += 1
		if _shot >= SHOTS:
			_shot = 0
			_ci += 1
			if _ci < _clips.size():
				_clip = _clips[_ci]
				if _ap.has_animation("z/" + _clip):
					_ap.play("z/" + _clip)
	return false
