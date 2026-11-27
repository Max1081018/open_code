class_name MagicHold
extends Node3D
## She is a mage: her sword or tool is not gripped in a fist but held by
## magic. At rest it hovers upright beside her right hand, tilted out from
## her body, bobbing and turning gently. When she strikes, gathers or casts it
## snaps to the palm's line and follows the hand through the swing a few
## centimetres off the palm, so the clip's own swing arc becomes the blade's.
##
## The magic is visible and tracks what she is doing:
##   a violet glow cupping the palm, a ring of energy round the hilt, a
##   flowing strand joining palm to hilt, wisps rising from the hand, and a
##   soft violet light. Faint at rest; bright when she strikes; brightest
##   when she casts; each sudden move of the weapon sends a pulse through it.
##
## The node is top-level: its transform is the weapon's pivot (the grip
## frame every packed item is built for: shaft +Y, head +X).

enum Mode { REST, STRIKE, GATHER, CAST, ORBIT }
const ENERGY := {Mode.REST: 0.32, Mode.STRIKE: 1.0, Mode.GATHER: 0.75, Mode.CAST: 1.5, Mode.ORBIT: 1.25}
## Follow rates (1/s): snappy in a swing, floaty at rest.
const RATE := {Mode.REST: 7.0, Mode.STRIKE: 40.0, Mode.GATHER: 32.0, Mode.CAST: 14.0, Mode.ORBIT: 30.0}
const PALM_GAP := 0.07   ## metres between the palm and a held hilt

var player: Node3D      ## Player3D
var hand: Node3D        ## the right hand's grip frame (HumanoidGrip)
var item: Node3D
var item_id := ""
var mode := Mode.REST
var energy := 0.32
var _pulse := 0.0
var _t := 0.0
var _cast_left := 0.0
var _last_pos := Vector3.ZERO
var _placed := false

var _palm: MeshInstance3D
var _ring: MeshInstance3D
var _strand: MeshInstance3D
var _wisps: CPUParticles3D
var _wisp_mat: StandardMaterial3D
var _light: OmniLight3D
var _mats: Array[ShaderMaterial] = []


## Weapons and tools float; torches, lanterns and shields stay in the hand.
static func floats(id: String) -> bool:
	return id != "" and Items.kind(id) in [Items.Kind.SWORD, Items.Kind.AXE, Items.Kind.PICKAXE, Items.Kind.HAMMER]


func _init() -> void:
	top_level = true
	process_priority = 50   # after the skeleton has been posed this frame


func setup(the_player: Node3D, grip: Node3D) -> void:
	player = the_player
	hand = grip
	_build_fx()
	visible = false


func set_item(id: String, node: Node3D) -> void:
	if item and is_instance_valid(item):
		item.queue_free()
	item = node
	item_id = id
	visible = node != null
	if node:
		add_child(node)
		_placed = false
		pulse(0.8)
	_set_fx_visible(node != null)


## A surge through the magic (a summon, a hit landing, a cast).
func pulse(amount := 0.6) -> void:
	_pulse = maxf(_pulse, amount)


## Hold it high and bright for a spell.
func cast(seconds: float) -> void:
	_cast_left = maxf(_cast_left, seconds)


## Blade Orbit: send it circling her at `radius` for `seconds`.
var _orbit_left := 0.0
var _orbit_r := 2.4


func orbit(seconds: float, radius: float) -> void:
	_orbit_left = seconds
	_orbit_r = radius
	pulse(1.0)


func _process(delta: float) -> void:
	if item == null or hand == null or not is_instance_valid(hand) or not is_instance_valid(item):
		return
	_t += delta
	_cast_left -= delta
	_orbit_left -= delta
	mode = _mode_now()
	var target := _target()
	if not _placed:
		global_transform = target
		_placed = true
	else:
		var k := 1.0 - exp(-float(RATE[mode]) * delta)
		var cur := global_transform
		var q := cur.basis.get_rotation_quaternion().slerp(target.basis.get_rotation_quaternion(), k)
		var s := target.basis.get_scale()
		global_transform = Transform3D(Basis(q).scaled(s), cur.origin.lerp(target.origin, k))
	# Pulses from sudden moves of the weapon.
	var speed := global_position.distance_to(_last_pos) / maxf(delta, 0.001)
	_last_pos = global_position
	_pulse = maxf(_pulse - delta * 1.8, clampf((speed - 4.0) * 0.06, 0.0, 0.6))
	var want: float = ENERGY[mode] + _pulse
	energy = lerpf(energy, want, 1.0 - exp(-10.0 * delta))
	_update_fx()


func _mode_now() -> int:
	if _orbit_left > 0.0:
		return Mode.ORBIT
	if _cast_left > 0.0:
		return Mode.CAST
	var acting: bool = player.get("_action") > 0.0
	if acting:
		var name: String = player.get("_action_name")
		return Mode.GATHER if name in ["chop", "mine"] else Mode.STRIKE
	return Mode.REST


## Where the weapon wants to be this frame.
func _target() -> Transform3D:
	var g := hand.global_transform
	var s := g.basis.get_scale()
	var gb := g.basis.orthonormalized()
	if mode == Mode.STRIKE or mode == Mode.GATHER:
		# In line with the hand, lifted off the palm: the swing is the clip's.
		return Transform3D(gb.scaled(s), g.origin + gb.z * PALM_GAP)
	var mb: Basis = player.get("model").global_transform.basis.orthonormalized()
	var fwd := mb.z
	var body: Vector3 = player.global_position + Vector3.UP * 1.0
	# Out to the side of her hand's side of the body (lateral, never in
	# front of her, wherever the clip puts the hand).
	var side := -mb.x
	if (g.origin - body).dot(side) < 0.0:
		side = -side
	var length: float = item.get_meta("length", 1.0)
	if mode == Mode.ORBIT:
		# Point first round her, flat, at chest height.
		var a := _t * 6.5
		var radial := Vector3(cos(a), 0.0, sin(a))
		var tangent := Vector3(-sin(a), 0.0, cos(a))
		var centre: Vector3 = player.global_position + Vector3.UP * 1.0
		return Transform3D(Basis(radial, tangent, radial.cross(tangent)).scaled(s), centre + radial * _orbit_r - tangent * length * 0.4)
	if mode == Mode.CAST:
		# Raised before her, spinning slowly, point up.
		var up_c := Vector3.UP
		var x_c := fwd.rotated(Vector3.UP, _t * 3.0)
		x_c = (x_c - up_c * x_c.dot(up_c)).normalized()
		return Transform3D(Basis(x_c, up_c, x_c.cross(up_c)).scaled(s),
			body + fwd * 0.55 + side * 0.1 + Vector3.UP * (0.35 + sin(_t * 4.0) * 0.04) - up_c * length * 0.3)
	# At rest: upright beside the hand, tilted out from her body, bobbing.
	var bob := sin(_t * 2.1) * 0.035
	var tilt := 0.32 + sin(_t * 0.9) * 0.05
	var up := (Vector3.UP * cos(tilt) + side * sin(tilt) + fwd * 0.12).normalized()
	var x := fwd.rotated(up, sin(_t * 0.7) * 0.35)
	x = (x - up * x.dot(up)).normalized()
	var pos := g.origin + side * 0.24 + fwd * 0.02 + Vector3.UP * (0.02 + bob)
	return Transform3D(Basis(x, up, x.cross(up)).scaled(s), pos)


# ------------------------------------------------------------------ fx ---

func _energy_mat(seed: float, rim: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://scripts/shaders/magic_energy.gdshader")
	m.set_shader_parameter("seed", seed)
	m.set_shader_parameter("rim_only", 1.0 if rim else 0.0)
	_mats.append(m)
	return m


func _build_fx() -> void:
	# The palm's glow (on the hand, so it follows every finger of the clip).
	_palm = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.065
	sphere.height = 0.11
	sphere.radial_segments = 16
	sphere.rings = 8
	_palm.mesh = sphere
	_palm.material_override = _energy_mat(0.0, true)
	_palm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_palm.position = Vector3(0, 0, 0.025)
	hand.add_child(_palm)
	# A ring of energy round the hilt (on the weapon).
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.045
	torus.outer_radius = 0.06
	torus.rings = 24
	torus.ring_segments = 6
	_ring.mesh = torus
	_ring.material_override = _energy_mat(3.0, true)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	# The strand joining palm and hilt.
	_strand = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	_strand.mesh = quad
	_strand.material_override = _energy_mat(5.0, false)
	_strand.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_strand.top_level = true
	add_child(_strand)
	# Wisps rising off the hand.
	_wisps = CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.035, 0.035)
	_wisps.mesh = q
	_wisp_mat = StandardMaterial3D.new()
	_wisp_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_wisp_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_wisp_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_wisp_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_wisp_mat.albedo_texture = Play3D._spark_texture()
	_wisp_mat.vertex_color_use_as_albedo = true
	_wisps.material_override = _wisp_mat
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color(0.95, 0.85, 1.0, 0.0), Color(0.78, 0.5, 1.0, 1.0), Color(0.5, 0.25, 1.0, 0.0)])
	ramp.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	_wisps.color_ramp = ramp
	_wisps.amount = 10 if Settings.particles <= 0 else (16 if Settings.particles == 1 else 24)
	_wisps.lifetime = 0.8
	_wisps.local_coords = false
	_wisps.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_wisps.emission_sphere_radius = 0.06
	_wisps.direction = Vector3.UP
	_wisps.spread = 60.0
	_wisps.initial_velocity_min = 0.05
	_wisps.initial_velocity_max = 0.3
	_wisps.gravity = Vector3(0, 0.5, 0)
	_wisps.scale_amount_min = 0.5
	_wisps.scale_amount_max = 1.3
	hand.add_child(_wisps)
	if Settings.lighting >= 2:
		_light = OmniLight3D.new()
		_light.light_color = Color(0.7, 0.45, 1.0)
		_light.omni_range = 1.6
		_light.shadow_enabled = false
		hand.add_child(_light)
	_set_fx_visible(false)


func _set_fx_visible(on: bool) -> void:
	for n in [_palm, _ring, _strand, _wisps, _light]:
		if n:
			n.visible = on
	if _wisps:
		_wisps.emitting = on


func _update_fx() -> void:
	var e := energy
	for m in _mats:
		m.set_shader_parameter("energy", e)
	_palm.scale = Vector3.ONE * (0.75 + e * 0.35 + sin(_t * 6.0) * 0.05)
	_ring.rotation.y = _t * 4.0
	_ring.position = Vector3(0, 0.03, 0)
	_ring.scale = Vector3.ONE * (0.85 + e * 0.25)
	_wisp_mat.albedo_color = Color(1, 1, 1, clampf(0.3 + e * 0.6, 0.0, 1.0))
	_wisps.speed_scale = 0.7 + e * 0.6
	if _light:
		_light.light_energy = 0.25 + e * 0.9
	# The strand: a ribbon from palm to hilt, turned to face the camera.
	var a := hand.global_position + hand.global_transform.basis.z.normalized() * 0.02
	var b := global_position
	var d := b - a
	var len := d.length()
	_strand.visible = len > 0.04
	if not _strand.visible:
		return
	var cam := get_viewport().get_camera_3d()
	var to_cam := (cam.global_position - (a + b) * 0.5).normalized() if cam else Vector3.FORWARD
	var y := d
	var x := y.cross(to_cam).normalized() * (0.035 + e * 0.02)
	var z := x.cross(y).normalized()
	_strand.global_transform = Transform3D(Basis(x, y, z), (a + b) * 0.5)
