class_name IconBaker
extends Node
## Renders small 3D item pictures for the hotbar: each model is posed at a
## three-quarter angle in a private little studio (own world, own light),
## photographed once into a texture and cached. One picture per frame, so it
## never causes a hitch; slots show a vector icon until their picture is ready.

signal baked(key: String)

const SIZE := 160

var cache := {}                   # key -> Texture2D
var _queue: Array = []            # [key, Node3D]
var _queued := {}
var _vp: SubViewport
var _cam: Camera3D
var _stage: Node3D
var _busy := false


func _ready() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(SIZE, SIZE)
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.ambient_light_energy = 0.75
	_cam = Camera3D.new()
	_cam.environment = env
	_cam.fov = 30.0
	_cam.position = Vector3(0, 0, 4.0)
	_vp.add_child(_cam)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, 35, 0)
	key.light_energy = 1.25
	_vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-10, 200, 0)
	rim.light_energy = 0.55
	rim.light_color = Color(0.75, 0.85, 1.0)
	_vp.add_child(rim)
	_stage = Node3D.new()
	_vp.add_child(_stage)


func has_icon(key: String) -> bool:
	return cache.has(key)


func get_icon(key: String) -> Texture2D:
	return cache.get(key)


## Queue a model to photograph under `key`. The node is taken over (freed after).
func request(key: String, model: Node3D) -> void:
	if cache.has(key) or _queued.has(key):
		model.free()
		return
	_queued[key] = true
	_queue.append([key, model])


func _process(_d: float) -> void:
	if _busy or _queue.is_empty():
		return
	_busy = true
	var job: Array = _queue.pop_front()
	var key: String = job[0]
	var model: Node3D = job[1]
	_stage.add_child(model)
	_frame(model)
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	if img and not img.is_empty():
		img.generate_mipmaps()
		cache[key] = ImageTexture.create_from_image(img)
	model.queue_free()
	_queued.erase(key)
	_busy = false
	baked.emit(key)


## Lay the item's long side diagonally across the picture, turned a little
## toward the camera, and fit it to the frame.
func _frame(model: Node3D) -> void:
	model.transform = Transform3D.IDENTITY
	var box := _aabb(model, Transform3D.IDENTITY)
	# longest axis -> X
	var b := Basis()
	if box.size.y >= box.size.x and box.size.y >= box.size.z:
		b = Basis(Vector3(0, 0, 1), PI * 0.5)
	elif box.size.z >= box.size.x and box.size.z >= box.size.y:
		b = Basis(Vector3.UP, PI * 0.5)
	b = Basis(Vector3(0, 0, 1), deg_to_rad(38.0)) * Basis(Vector3.UP, deg_to_rad(-28.0)) \
		* Basis(Vector3.RIGHT, deg_to_rad(12.0)) * b
	model.transform = Transform3D(b, Vector3.ZERO)
	var box2 := _aabb(model, Transform3D.IDENTITY)
	model.position = -box2.get_center()
	var r := maxf(box2.size.x, box2.size.y) * 0.5
	var dist := r / tan(deg_to_rad(_cam.fov * 0.5)) * 0.98
	_cam.position = Vector3(0, 0, dist + box2.size.z * 0.5)
	_cam.near = maxf(dist * 0.05, 0.01)
	_cam.far = dist * 4.0 + box2.size.z * 2.0
	_cam.look_at(Vector3.ZERO, Vector3.UP)


func _aabb(node: Node, xf: Transform3D) -> AABB:
	var acc := [null]
	_walk(node, xf, acc)
	return acc[0] if acc[0] != null else AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)


func _walk(n: Node, xf: Transform3D, acc: Array) -> void:
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh and (n as Node3D).visible:
		var a: AABB = t * (n as MeshInstance3D).mesh.get_aabb()
		acc[0] = a if acc[0] == null else (acc[0] as AABB).merge(a)
	for c in n.get_children():
		_walk(c, t, acc)
