class_name FallingTree
extends Node3D
## A felled tree: the same model, toppling away from the axe with a creak and
## a heavy landing, then splitting into logs (wood pickups) amid bark and
## leaf debris. Rocks shatter instead (handled by Play3D's debris).

var kind := ""
var away := Vector3.FORWARD
var game: Node
var scale_factor := 1.0
var _t := 0.0
var _pivot: Node3D
var _landed := false


func _ready() -> void:
	_pivot = Node3D.new()
	add_child(_pivot)
	for part in FoliageLib.parts(kind):
		var mi := MeshInstance3D.new()
		mi.mesh = part[0]
		mi.transform = part[1]
		_pivot.add_child(mi)
	_pivot.scale = Vector3.ONE * scale_factor


func _process(delta: float) -> void:
	_t += delta
	# Tip slowly, then faster (falling under gravity), about a ground hinge.
	var angle := clampf(_t * _t * 1.3, 0.0, PI * 0.47)
	var axis := away.cross(Vector3.UP).normalized() * -1.0
	_pivot.transform.basis = Basis(axis, angle).scaled(Vector3.ONE * scale_factor) if axis.length() > 0.5 else _pivot.transform.basis
	if angle >= PI * 0.47 and not _landed:
		_landed = true
		game.tree_landed(self)
	if _landed and _t > 2.6:
		# Logs along where the trunk lies.
		for i in 4:
			var at := global_position + away * (1.5 + i * 2.0) * scale_factor + Vector3(0, 0.5, 0)
			game.spawn_pickup("wood", 2, at, Vector3(randf_range(-1, 1), 3.0, randf_range(-1, 1)))
		if randf() < 0.4:
			game.spawn_pickup("apple", 1, global_position + away * 4.0 + Vector3(0, 1, 0), Vector3(0, 3, 0))
		game.debris(global_position + away * 3.0 * scale_factor + Vector3(0, 0.6, 0), Color(0.36, 0.26, 0.18), 18)
		queue_free()
