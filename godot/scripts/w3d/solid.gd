class_name Solid
extends RefCounted
## Makes a visual prop solid: a StaticBody3D on the world layer (1), parented
## to the prop so it follows it, with one shape. For the props built in code
## (standing stones, shrines, chests, posts) that were drawn but had nothing
## for the heroine or a foe to bump into.


## The convex hull of the prop's own mesh (stones, pillars, crystals).
static func hull(mi: MeshInstance3D) -> StaticBody3D:
	if mi.mesh == null:
		return null
	var shape := mi.mesh.create_convex_shape(true, true)
	return _body(mi, shape, Transform3D.IDENTITY)


## A box `size` centred at `at` in the prop's space.
static func box(parent: Node3D, size: Vector3, at := Vector3.ZERO) -> StaticBody3D:
	var shape := BoxShape3D.new()
	shape.size = size
	return _body(parent, shape, Transform3D(Basis.IDENTITY, at))


## An upright cylinder standing on `at` (its base) in the prop's space.
static func cylinder(parent: Node3D, radius: float, height: float, at := Vector3.ZERO) -> StaticBody3D:
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	return _body(parent, shape, Transform3D(Basis.IDENTITY, at + Vector3(0, height * 0.5, 0)))


## ArchKit.gate(span): its two pylons, walk-through between them.
static func gate(mi: MeshInstance3D, span: float) -> void:
	for sx in [-1.0, 1.0]:
		box(mi, Vector3(2.0, 7.0, 2.0), Vector3(sx * (span * 0.5 + 0.8), 3.5, 0))


## ArchKit.star_fountain(): the basin rim and the central column.
static func fountain(mi: MeshInstance3D) -> void:
	cylinder(mi, 5.3, 1.35, Vector3(0, -0.3, 0))
	cylinder(mi, 0.9, 4.9)


static func _body(parent: Node3D, shape: Shape3D, local: Transform3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = local
	body.add_child(cs)
	parent.add_child(body)
	return body
