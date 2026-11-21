class_name Pickup3D
extends Node3D
## Something lying in the world to collect: a log, a stone, ore, loot. Shown
## as its real 3D model where one exists (or its icon on a camera-facing
## card), it pops out, bounces to rest on the ground, bobs and glints, then
## flies to the player when they come near.

var id := ""
var count := 1
var game: Node
var _velocity := Vector3.ZERO
var _resting := false
var _age := 0.0
var _visual: Node3D

## Real models for common resources (assets/models/nature3d, CC0).
const MODELS := {
	"stone": "Pebble_Round_3", "coal": "Pebble_Square_2", "iron_ore": "Pebble_Square_4",
	"copper_ore": "Pebble_Square_5", "gold_ore": "Pebble_Round_5", "silver_ore": "Pebble_Square_3",
}


func setup(the_id: String, the_count: int, the_game: Node, impulse: Vector3) -> void:
	id = the_id
	count = the_count
	game = the_game
	_velocity = impulse


func _ready() -> void:
	add_to_group("pickups")
	if id == "wood":
		_visual = _log()
	elif MODELS.has(id):
		_visual = Node3D.new()
		for part in FoliageLib.parts(MODELS[id]):
			var mi := MeshInstance3D.new()
			mi.mesh = part[0]
			mi.transform = part[1].scaled(Vector3.ONE * 1.6)
			if id != "stone":
				var tint := StandardMaterial3D.new()
				tint.albedo_color = {"coal": Color(0.12, 0.12, 0.13), "iron_ore": Color(0.62, 0.5, 0.45),
					"copper_ore": Color(0.85, 0.45, 0.25), "gold_ore": Color(1.0, 0.8, 0.3),
					"silver_ore": Color(0.85, 0.88, 0.95)}.get(id, Color.WHITE)
				tint.metallic = 0.5
				tint.roughness = 0.4
				mi.material_override = tint
			_visual.add_child(mi)
	else:
		var item := Body3D.item_model(id)
		if item:
			_visual = item
			item.scale = Vector3.ONE * 0.8
		else:
			var card := Sprite3D.new()
			card.texture = Items.icon(id)
			card.pixel_size = 0.4 / maxf(card.texture.get_width(), 1) if card.texture else 0.01
			card.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			card.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
			_visual = card
	add_child(_visual)


func _log() -> Node3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.16
	mesh.bottom_radius = 0.18
	mesh.height = 0.9
	var bark := StandardMaterial3D.new()
	bark.albedo_texture = load("res://assets/models/nature3d/Bark_NormalTree.png")
	bark.uv1_scale = Vector3(1, 1.5, 1)
	mesh.material = bark
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.rotation = Vector3(0, 0, PI * 0.5)
	return mi


func _physics_process(delta: float) -> void:
	if game == null:
		return
	_age += delta
	var player: Node3D = game.player
	var to := player.global_position + Vector3(0, 1.0, 0) - global_position
	if _age > 0.6 and to.length() < 3.2:
		# Drawn in, then collected.
		global_position += to.normalized() * minf(to.length(), delta * (6.0 + 30.0 / maxf(to.length(), 0.3)))
		if to.length() < 0.6:
			game.collect(id, count, global_position)
			queue_free()
		return
	var ground: float = game.world.height_at(global_position.x, global_position.z) + 0.2
	if not _resting:
		_velocity.y -= 18.0 * delta
		global_position += _velocity * delta
		if global_position.y <= ground:
			global_position.y = ground
			_velocity *= Vector3(0.5, -0.35, 0.5)
			if absf(_velocity.y) < 1.0:
				_resting = true
	else:
		global_position.y = ground + 0.12 + sin(_age * 3.0) * 0.06
		_visual.rotation.y += delta * 1.4
	if _age > 180.0:
		queue_free()
