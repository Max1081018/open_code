@tool
extends "res://addons/godot_mcp_bridge/commands/base_command.gd"

## scene_3d — 6 tools (SPEC §6, specs/B02).
## 3D authoring in the currently edited scene: meshes, lights, materials, environment,
## camera, gridmap. All tools require an open scene ([E+S]).

const NodeUtils := preload("res://addons/godot_mcp_bridge/utils/node_utils.gd")
const PropertyParser := preload("res://addons/godot_mcp_bridge/utils/property_parser.gd")

const MESH_TYPES := [
	"BoxMesh",
	"SphereMesh",
	"CylinderMesh",
	"CapsuleMesh",
	"PlaneMesh",
	"PrismMesh",
	"TorusMesh",
	"QuadMesh",
]
const LIGHT_TYPES := ["DirectionalLight3D", "OmniLight3D", "SpotLight3D"]

const TRANSPARENCY_NAMES := [
	"disabled", "alpha", "alpha_scissor", "alpha_hash", "alpha_depth_pre_pass"
]
const CULL_MODE_NAMES := ["back", "front", "disabled"]

const PRESET_LIGHT_TYPE := {
	"sun": "DirectionalLight3D",
	"indoor": "OmniLight3D",
	"dramatic": "SpotLight3D",
}
const PRESET_NAME := {
	"sun": "SunLight",
	"indoor": "IndoorLight",
	"dramatic": "DramaticLight",
}


func get_commands() -> Dictionary:
	return {
		"add_mesh_instance": _add_mesh_instance,
		"setup_lighting": _setup_lighting,
		"set_material_3d": _set_material_3d,
		"setup_environment": _setup_environment,
		"setup_camera_3d": _setup_camera_3d,
		"add_gridmap": _add_gridmap,
	}


# ---------------------------------------------------------------------------
# add_mesh_instance
# ---------------------------------------------------------------------------


func _add_mesh_instance(params: Dictionary) -> Dictionary:
	var root: Node = get_edited_root()
	if root == null:
		return error_no_scene()

	var parent_path: String = optional_string(params, "parent_path", ".")
	var parent: Node = find_node_by_path(parent_path)
	if parent == null:
		return error_not_found("Parent node: %s" % parent_path)

	var mesh_type: String = optional_string(params, "mesh_type", "")
	var mesh_file: String = optional_string(params, "mesh_file", "")
	if mesh_type.is_empty() and mesh_file.is_empty():
		return error(-32602, "Either 'mesh_type' or 'mesh_file' is required")

	var mesh: Mesh = null
	var mesh_source: String = ""

	if not mesh_file.is_empty():
		# mesh_file wins when both are given.
		if not ResourceLoader.exists(mesh_file):
			return error_not_found("Mesh file: %s" % mesh_file)
		var loaded: Resource = load(mesh_file)
		if loaded is Mesh:
			mesh = loaded as Mesh
		elif loaded is PackedScene:
			var temp: Node = (loaded as PackedScene).instantiate()
			if temp == null:
				return error(-32603, "Could not instantiate mesh scene: %s" % mesh_file)
			mesh = _find_first_mesh(temp)
			temp.free()
			if mesh == null:
				return error(
					-32602, "No MeshInstance3D with a mesh found in scene: %s" % mesh_file
				)
		else:
			var found_class: String = loaded.get_class() if loaded != null else "null"
			return error(
				-32602,
				"'%s' is not a Mesh or PackedScene (is %s)" % [mesh_file, found_class]
			)
		mesh_source = mesh_file
	else:
		var canonical: String = _canonical(mesh_type, MESH_TYPES)
		if canonical.is_empty():
			return error(
				-32602, "Unknown mesh_type: %s (expected one of %s)" % [mesh_type, MESH_TYPES]
			)
		var primitive: Mesh = ClassDB.instantiate(canonical) as Mesh
		if primitive == null:
			return error(-32603, "Could not instantiate mesh type: %s" % canonical)
		var mesh_properties: Dictionary = _dict_param(params, "mesh_properties")
		for key: String in mesh_properties.keys():
			if key in primitive:
				var current: Variant = primitive.get(key)
				primitive.set(key, PropertyParser.parse_value(mesh_properties[key], typeof(current)))
		mesh = primitive
		mesh_source = canonical

	var instance := MeshInstance3D.new()
	var node_name: String = optional_string(params, "name", "MeshInstance3D")
	if node_name.is_empty():
		node_name = "MeshInstance3D"
	instance.name = unique_child_name(parent, node_name, "MeshInstance3D")
	instance.mesh = mesh
	instance.position = _parse_vec3(params, "position", Vector3.ZERO)
	instance.rotation_degrees = _parse_vec3(params, "rotation", Vector3.ZERO)
	instance.scale = _parse_vec3(params, "scale", Vector3.ONE)

	var inserted: Dictionary = _insert_node(parent, instance, root, "add_mesh_instance")
	if not inserted.is_empty():
		return inserted

	return success(
		{
			"node_path": _path_of(root, instance),
			"name": str(instance.name),
			"mesh_source": mesh_source,
		}
	)


# ---------------------------------------------------------------------------
# setup_lighting
# ---------------------------------------------------------------------------


func _setup_lighting(params: Dictionary) -> Dictionary:
	var root: Node = get_edited_root()
	if root == null:
		return error_no_scene()

	var parent_path: String = optional_string(params, "parent_path", ".")
	var parent: Node = find_node_by_path(parent_path)
	if parent == null:
		return error_not_found("Parent node: %s" % parent_path)

	var preset: String = optional_string(params, "preset", "").strip_edges().to_lower()
	var light_type: String = optional_string(params, "light_type", "")
	if preset.is_empty() and light_type.is_empty():
		return error(-32602, "Either 'light_type' or 'preset' is required")
	if not preset.is_empty() and not PRESET_LIGHT_TYPE.has(preset):
		return error(-32602, "Unknown preset: %s (expected sun, indoor or dramatic)" % preset)

	var canonical: String = ""
	if not light_type.is_empty():
		canonical = _canonical(light_type, LIGHT_TYPES)
		if canonical.is_empty():
			return error(
				-32602, "Unknown light_type: %s (expected one of %s)" % [light_type, LIGHT_TYPES]
			)
	else:
		canonical = str(PRESET_LIGHT_TYPE[preset])

	# Preset defaults fill only the params the caller omitted — explicit params always win.
	var light_color: Color = Color.WHITE
	var energy: float = 1.0
	var shadows: bool = false
	var light_range: float = 5.0
	var attenuation: float = 1.0
	var spot_angle: float = 45.0
	var spot_angle_attenuation: float = 1.0
	var rotation_degrees: Vector3 = Vector3.ZERO
	var has_rotation: bool = _has(params, "rotation")

	match preset:
		"sun":
			if not _has(params, "shadows"):
				shadows = true
			if not has_rotation:
				rotation_degrees = Vector3(-45.0, -30.0, 0.0)
				has_rotation = true
		"indoor":
			if not _has(params, "energy"):
				energy = 0.8
			if not _has(params, "color"):
				light_color = Color(1.0, 0.95, 0.85)
			if not _has(params, "range"):
				light_range = 8.0
		"dramatic":
			if not _has(params, "energy"):
				energy = 2.0
			if not _has(params, "shadows"):
				shadows = true
			if not _has(params, "spot_angle"):
				spot_angle = 25.0
			if not _has(params, "range"):
				light_range = 10.0

	light_color = _parse_color(params, "color", light_color)
	energy = optional_float(params, "energy", energy)
	shadows = optional_bool(params, "shadows", shadows)
	light_range = optional_float(params, "range", light_range)
	attenuation = optional_float(params, "attenuation", attenuation)
	spot_angle = optional_float(params, "spot_angle", spot_angle)
	spot_angle_attenuation = optional_float(
		params, "spot_angle_attenuation", spot_angle_attenuation
	)
	rotation_degrees = _parse_vec3(params, "rotation", rotation_degrees)

	var node_name: String = optional_string(params, "name", "")
	if node_name.is_empty():
		node_name = str(PRESET_NAME[preset]) if not preset.is_empty() else canonical

	var light: Light3D = ClassDB.instantiate(canonical) as Light3D
	if light == null:
		return error(-32603, "Could not instantiate light type: %s" % canonical)

	light.name = unique_child_name(parent, node_name, canonical)
	light.light_color = light_color
	light.light_energy = energy
	light.shadow_enabled = shadows
	light.position = _parse_vec3(params, "position", Vector3.ZERO)
	if has_rotation:
		light.rotation_degrees = rotation_degrees

	if light is OmniLight3D:
		var omni: OmniLight3D = light as OmniLight3D
		omni.omni_range = light_range
		omni.omni_attenuation = attenuation
	elif light is SpotLight3D:
		var spot: SpotLight3D = light as SpotLight3D
		spot.spot_range = light_range
		spot.spot_attenuation = attenuation
		spot.spot_angle = spot_angle
		spot.spot_angle_attenuation = spot_angle_attenuation

	var inserted: Dictionary = _insert_node(parent, light, root, "setup_lighting")
	if not inserted.is_empty():
		return inserted

	return success(
		{
			"node_path": _path_of(root, light),
			"name": str(light.name),
			"light_type": canonical,
			"preset": preset,
		}
	)


# ---------------------------------------------------------------------------
# set_material_3d
# ---------------------------------------------------------------------------


func _set_material_3d(params: Dictionary) -> Dictionary:
	var root: Node = get_edited_root()
	if root == null:
		return error_no_scene()

	var res: Array = require_string(params, "node_path")
	if res[1] != null:
		return res[1]
	var node_path: String = res[0]

	var node: Node = find_node_by_path(node_path)
	if node == null:
		return error_not_found("Node: %s" % node_path)
	if not (node is MeshInstance3D):
		return error(
			-32602, "'%s' is not a MeshInstance3D (is %s)" % [node_path, node.get_class()]
		)
	var mesh_instance: MeshInstance3D = node as MeshInstance3D

	var surface_count: int = mesh_instance.get_surface_override_material_count()
	var surface_index: int = optional_int(params, "surface_index", 0)
	if surface_index < 0 or surface_index >= surface_count:
		return error(
			-32602,
			(
				"surface_index %d is out of range — the mesh has %d surface(s)"
				% [surface_index, surface_count]
			)
		)

	# A FRESH material every call: omitted params fall back to StandardMaterial3D defaults.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _parse_color(params, "albedo_color", Color.WHITE)
	mat.metallic = optional_float(params, "metallic", 0.0)
	mat.roughness = optional_float(params, "roughness", 1.0)

	var albedo_texture: Texture2D = _load_texture(params, "albedo_texture")
	if albedo_texture != null:
		mat.albedo_texture = albedo_texture
	var metallic_texture: Texture2D = _load_texture(params, "metallic_texture")
	if metallic_texture != null:
		mat.metallic_texture = metallic_texture
	var roughness_texture: Texture2D = _load_texture(params, "roughness_texture")
	if roughness_texture != null:
		mat.roughness_texture = roughness_texture
	var normal_texture: Texture2D = _load_texture(params, "normal_texture")
	if normal_texture != null:
		mat.normal_enabled = true
		mat.normal_texture = normal_texture

	var emission_texture: Texture2D = _load_texture(params, "emission_texture")
	var has_emission_color: bool = _has(params, "emission") or _has(params, "emission_color")
	if has_emission_color or emission_texture != null:
		mat.emission_enabled = true
		if has_emission_color:
			var emission_key: String = "emission" if _has(params, "emission") else "emission_color"
			mat.emission = _parse_color(params, emission_key, mat.emission)
		mat.emission_energy_multiplier = optional_float(
			params, "emission_energy", mat.emission_energy_multiplier
		)
		if emission_texture != null:
			mat.emission_texture = emission_texture

	var transparency: int = _enum_index(params, "transparency", TRANSPARENCY_NAMES)
	if transparency >= 0:
		mat.transparency = transparency as BaseMaterial3D.Transparency
	var cull_mode: int = _enum_index(params, "cull_mode", CULL_MODE_NAMES)
	if cull_mode >= 0:
		mat.cull_mode = cull_mode as BaseMaterial3D.CullMode

	var ur: EditorUndoRedoManager = undo_redo()
	if ur == null:
		return error(-32603, "Undo/redo manager is unavailable")

	var previous: Material = mesh_instance.get_surface_override_material(surface_index)
	ur.create_action("MCP: set_material_3d")
	ur.add_do_method(mesh_instance, "set_surface_override_material", surface_index, mat)
	ur.add_do_reference(mat)
	ur.add_undo_method(mesh_instance, "set_surface_override_material", surface_index, previous)
	ur.commit_action()

	return success(
		{
			"node_path": node_path,
			"surface_index": surface_index,
			"albedo_color": PropertyParser.serialize_value(mat.albedo_color),
			"metallic": mat.metallic,
			"roughness": mat.roughness,
		}
	)


# ---------------------------------------------------------------------------
# setup_environment
# ---------------------------------------------------------------------------


func _setup_environment(params: Dictionary) -> Dictionary:
	var root: Node = get_edited_root()
	if root == null:
		return error_no_scene()

	var world_env: WorldEnvironment = null
	var parent: Node = null
	var is_existing: bool = false

	var node_path: String = optional_string(params, "node_path", "")
	if not node_path.is_empty():
		var existing: Node = find_node_by_path(node_path)
		if existing == null:
			return error_not_found("Node: %s" % node_path)
		if not (existing is WorldEnvironment):
			return error(
				-32602,
				"'%s' is not a WorldEnvironment (is %s)" % [node_path, existing.get_class()]
			)
		world_env = existing as WorldEnvironment
		is_existing = true
	else:
		var parent_path: String = optional_string(params, "parent_path", ".")
		parent = find_node_by_path(parent_path)
		if parent == null:
			return error_not_found("Parent node: %s" % parent_path)
		world_env = WorldEnvironment.new()
		var node_name: String = optional_string(params, "name", "WorldEnvironment")
		if node_name.is_empty():
			node_name = "WorldEnvironment"
		world_env.name = node_name

	var env: Environment = world_env.environment
	if env == null:
		env = Environment.new()

	var bg_modes: Dictionary = {
		"clear_color": Environment.BG_CLEAR_COLOR,
		"color": Environment.BG_COLOR,
		"sky": Environment.BG_SKY,
		"canvas": Environment.BG_CANVAS,
	}
	var bg_mode: int = _enum_value(params, "background_mode", bg_modes)
	if bg_mode < 0:
		bg_mode = Environment.BG_SKY
	env.background_mode = bg_mode as Environment.BGMode

	if env.background_mode == Environment.BG_COLOR:
		env.background_color = _parse_color(params, "background_color", Color(0.3, 0.3, 0.3))

	# A sky block always forces BG_SKY, whatever background_mode said.
	var sky_params: Dictionary = _dict_param(params, "sky")
	if _has(params, "sky") and not sky_params.is_empty():
		var sky_material := ProceduralSkyMaterial.new()
		sky_material.sky_top_color = _parse_color(
			sky_params, "sky_top_color", sky_material.sky_top_color
		)
		sky_material.sky_horizon_color = _parse_color(
			sky_params, "sky_horizon_color", sky_material.sky_horizon_color
		)
		sky_material.ground_bottom_color = _parse_color(
			sky_params, "ground_bottom_color", sky_material.ground_bottom_color
		)
		sky_material.ground_horizon_color = _parse_color(
			sky_params, "ground_horizon_color", sky_material.ground_horizon_color
		)
		sky_material.sun_angle_max = optional_float(
			sky_params, "sun_angle_max", sky_material.sun_angle_max
		)
		sky_material.sky_curve = optional_float(sky_params, "sky_curve", sky_material.sky_curve)
		var sky := Sky.new()
		sky.sky_material = sky_material
		env.sky = sky
		env.background_mode = Environment.BG_SKY

	if _has(params, "ambient_light_color"):
		env.ambient_light_color = _parse_color(
			params, "ambient_light_color", env.ambient_light_color
		)
	if _has(params, "ambient_light_energy"):
		env.ambient_light_energy = optional_float(
			params, "ambient_light_energy", env.ambient_light_energy
		)
	var ambient_sources: Dictionary = {
		"background": Environment.AMBIENT_SOURCE_BG,
		"disabled": Environment.AMBIENT_SOURCE_DISABLED,
		"color": Environment.AMBIENT_SOURCE_COLOR,
		"sky": Environment.AMBIENT_SOURCE_SKY,
	}
	var ambient_source: int = _enum_value(params, "ambient_light_source", ambient_sources)
	if ambient_source >= 0:
		env.ambient_light_source = ambient_source as Environment.AmbientSource

	# agx is Godot 4.4+; assign the raw enum value so 4.3 still compiles.
	var tonemap_modes: Dictionary = {
		"linear": Environment.TONE_MAPPER_LINEAR,
		"reinhardt": Environment.TONE_MAPPER_REINHARDT,
		"filmic": Environment.TONE_MAPPER_FILMIC,
		"aces": Environment.TONE_MAPPER_ACES,
		"agx": 4,
	}
	var tonemap: int = _enum_value(params, "tonemap_mode", tonemap_modes)
	if tonemap >= 0:
		env.tonemap_mode = tonemap as Environment.ToneMapper
	if _has(params, "tonemap_exposure"):
		env.tonemap_exposure = optional_float(params, "tonemap_exposure", env.tonemap_exposure)
	if _has(params, "tonemap_white"):
		env.tonemap_white = optional_float(params, "tonemap_white", env.tonemap_white)

	if _has(params, "fog_enabled"):
		env.fog_enabled = optional_bool(params, "fog_enabled", env.fog_enabled)
	if env.fog_enabled:
		# Only when the caller actually sent it — writing it unconditionally wipes an existing
		# WorldEnvironment's fog colour on every reconfigure, and reconfigure is not undoable.
		if _has(params, "fog_light_color"):
			env.fog_light_color = _parse_color(
				params, "fog_light_color", Color(0.518, 0.553, 0.608)
			)
		if _has(params, "fog_density"):
			env.fog_density = optional_float(params, "fog_density", env.fog_density)
		if _has(params, "fog_light_energy"):
			env.fog_light_energy = optional_float(
				params, "fog_light_energy", env.fog_light_energy
			)

	if _has(params, "glow_enabled"):
		env.glow_enabled = optional_bool(params, "glow_enabled", env.glow_enabled)
	if env.glow_enabled:
		if _has(params, "glow_intensity"):
			env.glow_intensity = optional_float(params, "glow_intensity", env.glow_intensity)
		if _has(params, "glow_strength"):
			env.glow_strength = optional_float(params, "glow_strength", env.glow_strength)
		if _has(params, "glow_bloom"):
			env.glow_bloom = optional_float(params, "glow_bloom", env.glow_bloom)

	if _has(params, "ssao_enabled"):
		env.ssao_enabled = optional_bool(params, "ssao_enabled", env.ssao_enabled)
	if env.ssao_enabled:
		if _has(params, "ssao_radius"):
			env.ssao_radius = optional_float(params, "ssao_radius", env.ssao_radius)
		if _has(params, "ssao_intensity"):
			env.ssao_intensity = optional_float(params, "ssao_intensity", env.ssao_intensity)

	if _has(params, "ssr_enabled"):
		env.ssr_enabled = optional_bool(params, "ssr_enabled", env.ssr_enabled)
	if env.ssr_enabled:
		if _has(params, "ssr_max_steps"):
			env.ssr_max_steps = optional_int(params, "ssr_max_steps", env.ssr_max_steps)
		if _has(params, "ssr_fade_in"):
			env.ssr_fade_in = optional_float(params, "ssr_fade_in", env.ssr_fade_in)
		if _has(params, "ssr_fade_out"):
			env.ssr_fade_out = optional_float(params, "ssr_fade_out", env.ssr_fade_out)

	if _has(params, "sdfgi_enabled"):
		env.sdfgi_enabled = optional_bool(params, "sdfgi_enabled", env.sdfgi_enabled)

	world_env.environment = env

	if not is_existing:
		var inserted: Dictionary = _insert_node(parent, world_env, root, "setup_environment")
		if not inserted.is_empty():
			return inserted

	var features: Array[String] = []
	if env.fog_enabled:
		features.append("fog")
	if env.glow_enabled:
		features.append("glow")
	if env.ssao_enabled:
		features.append("ssao")
	if env.ssr_enabled:
		features.append("ssr")
	if env.sdfgi_enabled:
		features.append("sdfgi")

	return success(
		{
			"node_path": _path_of(root, world_env),
			"name": str(world_env.name),
			"background_mode": _key_for_value(bg_modes, int(env.background_mode)),
			"features": features,
			"is_existing": is_existing,
		}
	)


# ---------------------------------------------------------------------------
# setup_camera_3d
# ---------------------------------------------------------------------------


func _setup_camera_3d(params: Dictionary) -> Dictionary:
	var root: Node = get_edited_root()
	if root == null:
		return error_no_scene()

	var camera: Camera3D = null
	var parent: Node = null
	var is_existing: bool = false

	var node_path: String = optional_string(params, "node_path", "")
	if not node_path.is_empty():
		var existing: Node = find_node_by_path(node_path)
		if existing == null:
			return error_not_found("Node: %s" % node_path)
		if not (existing is Camera3D):
			return error(
				-32602, "'%s' is not a Camera3D (is %s)" % [node_path, existing.get_class()]
			)
		camera = existing as Camera3D
		is_existing = true
	else:
		var parent_path: String = optional_string(params, "parent_path", ".")
		parent = find_node_by_path(parent_path)
		if parent == null:
			return error_not_found("Parent node: %s" % parent_path)
		camera = Camera3D.new()
		var node_name: String = optional_string(params, "name", "Camera3D")
		if node_name.is_empty():
			node_name = "Camera3D"
		camera.name = node_name

	var projections: Dictionary = {
		"perspective": Camera3D.PROJECTION_PERSPECTIVE,
		"orthogonal": Camera3D.PROJECTION_ORTHOGONAL,
		"orthographic": Camera3D.PROJECTION_ORTHOGONAL,
		"frustum": Camera3D.PROJECTION_FRUSTUM,
	}
	var projection: int = _enum_value(params, "projection", projections)
	if projection >= 0:
		camera.projection = projection as Camera3D.ProjectionType

	if _has(params, "fov"):
		camera.fov = optional_float(params, "fov", camera.fov)
	if _has(params, "size"):
		camera.size = optional_float(params, "size", camera.size)
	if _has(params, "near"):
		camera.near = optional_float(params, "near", camera.near)
	if _has(params, "far"):
		camera.far = optional_float(params, "far", camera.far)
	if _has(params, "cull_mask"):
		camera.cull_mask = optional_int(params, "cull_mask", camera.cull_mask)

	# Always applied — pass current: true when reconfiguring the active camera.
	camera.current = optional_bool(params, "current", false)

	var default_position: Vector3 = camera.position if is_existing else Vector3(0.0, 1.0, 3.0)
	camera.position = _parse_vec3(params, "position", default_position)
	if _has(params, "rotation"):
		camera.rotation_degrees = _parse_vec3(params, "rotation", camera.rotation_degrees)

	var environment_path: String = optional_string(params, "environment_path", "")
	if not environment_path.is_empty() and ResourceLoader.exists(environment_path):
		var env_res: Environment = load(environment_path) as Environment
		if env_res != null:
			camera.environment = env_res

	if not is_existing:
		var inserted: Dictionary = _insert_node(parent, camera, root, "setup_camera_3d")
		if not inserted.is_empty():
			return inserted

	# look_at overrides rotation and only works once the node is inside the tree.
	if _has(params, "look_at") and camera.is_inside_tree():
		var target: Vector3 = _parse_vec3(params, "look_at", Vector3.ZERO)
		if not camera.global_position.is_equal_approx(target):
			camera.look_at(target, Vector3.UP)

	return success(
		{
			"node_path": _path_of(root, camera),
			"name": str(camera.name),
			"projection": _key_for_value(
				{
					"perspective": Camera3D.PROJECTION_PERSPECTIVE,
					"orthogonal": Camera3D.PROJECTION_ORTHOGONAL,
					"frustum": Camera3D.PROJECTION_FRUSTUM,
				},
				int(camera.projection)
			),
			"fov": camera.fov,
			"position": PropertyParser.serialize_value(camera.position),
			"is_existing": is_existing,
		}
	)


# ---------------------------------------------------------------------------
# add_gridmap
# ---------------------------------------------------------------------------


func _add_gridmap(params: Dictionary) -> Dictionary:
	var root: Node = get_edited_root()
	if root == null:
		return error_no_scene()

	var grid_map: GridMap = null
	var parent: Node = null
	var is_existing: bool = false

	var node_path: String = optional_string(params, "node_path", "")
	if not node_path.is_empty():
		var existing: Node = find_node_by_path(node_path)
		if existing == null:
			return error_not_found("Node: %s" % node_path)
		if not (existing is GridMap):
			return error(
				-32602, "'%s' is not a GridMap (is %s)" % [node_path, existing.get_class()]
			)
		grid_map = existing as GridMap
		is_existing = true
	else:
		var parent_path: String = optional_string(params, "parent_path", ".")
		parent = find_node_by_path(parent_path)
		if parent == null:
			return error_not_found("Parent node: %s" % parent_path)
		grid_map = GridMap.new()
		var node_name: String = optional_string(params, "name", "GridMap")
		if node_name.is_empty():
			node_name = "GridMap"
		grid_map.name = node_name

	var mesh_library_path: String = optional_string(params, "mesh_library_path", "")
	if not mesh_library_path.is_empty():
		if not ResourceLoader.exists(mesh_library_path):
			if not is_existing:
				grid_map.free()
			return error_not_found("MeshLibrary: %s" % mesh_library_path)
		var library: MeshLibrary = load(mesh_library_path) as MeshLibrary
		if library == null:
			if not is_existing:
				grid_map.free()
			return error(-32602, "'%s' is not a MeshLibrary" % mesh_library_path)
		grid_map.mesh_library = library

	if _has(params, "cell_size"):
		grid_map.cell_size = _parse_vec3(params, "cell_size", grid_map.cell_size)

	var default_position: Vector3 = grid_map.position if is_existing else Vector3.ZERO
	grid_map.position = _parse_vec3(params, "position", default_position)

	if not is_existing:
		var inserted: Dictionary = _insert_node(parent, grid_map, root, "add_gridmap")
		if not inserted.is_empty():
			return inserted

	# Cell painting runs OUTSIDE the undo action — painted cells are not undoable.
	var cells_set: int = 0
	var cells: Variant = params.get("cells", [])
	if typeof(cells) == TYPE_ARRAY:
		var cell_list: Array = cells
		for cell: Variant in cell_list:
			if typeof(cell) != TYPE_DICTIONARY:
				continue
			var c: Dictionary = cell
			var coords := Vector3i(
				optional_int(c, "x", 0), optional_int(c, "y", 0), optional_int(c, "z", 0)
			)
			grid_map.set_cell_item(
				coords, optional_int(c, "item", 0), optional_int(c, "orientation", 0)
			)
			cells_set += 1

	return success(
		{
			"node_path": _path_of(root, grid_map),
			"name": str(grid_map.name),
			"cells_set": cells_set,
			"is_existing": is_existing,
			"has_mesh_library": grid_map.mesh_library != null,
		}
	)


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------


## One undo action per inserted node. Returns an EMPTY Dictionary when OK (check .is_empty()).
func _insert_node(parent: Node, node: Node, root: Node, tool_name: String) -> Dictionary:
	var ur: EditorUndoRedoManager = undo_redo()
	if ur == null:
		node.free()
		return error(-32603, "Undo/redo manager is unavailable")
	ur.create_action("MCP: %s" % tool_name)
	ur.add_do_method(parent, "add_child", node, true)
	ur.add_do_method(node, "set_owner", root)
	ur.add_do_reference(node)
	ur.add_undo_method(parent, "remove_child", node)
	ur.commit_action()
	NodeUtils.set_owner_recursive(node, root)
	return {}


func _path_of(root: Node, node: Node) -> String:
	if node == root:
		return "."
	if root.is_ancestor_of(node):
		return str(root.get_path_to(node))
	return str(node.name)


func _has(params: Dictionary, key: String) -> bool:
	return params.has(key) and params[key] != null


func _dict_param(params: Dictionary, key: String) -> Dictionary:
	if not _has(params, key):
		return {}
	var raw: Variant = params[key]
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	var out: Dictionary = raw
	return out


## "Vector3(x, y, z)" string, [x, y, z] array, or {x, y, z} object; omitted fields keep the default.
func _parse_vec3(params: Dictionary, key: String, default_value: Vector3) -> Vector3:
	if not _has(params, key):
		return default_value
	var raw: Variant = params[key]
	if typeof(raw) == TYPE_DICTIONARY:
		var d: Dictionary = raw
		return Vector3(
			float(d.get("x", default_value.x)),
			float(d.get("y", default_value.y)),
			float(d.get("z", default_value.z))
		)
	var parsed: Variant = PropertyParser.parse_value(raw, TYPE_VECTOR3)
	if typeof(parsed) == TYPE_VECTOR3:
		var vec: Vector3 = parsed
		return vec
	return default_value


## "#rrggbb(aa)" / "Color(...)" string or {r, g, b, a} object; omitted fields keep the default.
func _parse_color(params: Dictionary, key: String, default_value: Color) -> Color:
	if not _has(params, key):
		return default_value
	var raw: Variant = params[key]
	if typeof(raw) == TYPE_DICTIONARY:
		var d: Dictionary = raw
		return Color(
			float(d.get("r", default_value.r)),
			float(d.get("g", default_value.g)),
			float(d.get("b", default_value.b)),
			float(d.get("a", default_value.a))
		)
	var parsed: Variant = PropertyParser.parse_value(raw, TYPE_COLOR)
	if typeof(parsed) == TYPE_COLOR:
		var col: Color = parsed
		return col
	return default_value


## Case-insensitive class-name match against a whitelist; "" when unknown.
func _canonical(value: String, allowed: Array) -> String:
	var needle: String = value.strip_edges().to_lower()
	for candidate: String in allowed:
		if candidate.to_lower() == needle:
			return candidate
	return ""


## Enum name (case-insensitive) or raw int / int-as-string -> index; -1 when absent/unrecognized.
func _enum_index(params: Dictionary, key: String, names: Array) -> int:
	if not _has(params, key):
		return -1
	var raw: Variant = params[key]
	if typeof(raw) == TYPE_INT or typeof(raw) == TYPE_FLOAT:
		var numeric: int = int(raw)
		return numeric if numeric >= 0 and numeric < names.size() else -1
	var text: String = str(raw).strip_edges().to_lower()
	if text.is_valid_int():
		var parsed: int = text.to_int()
		return parsed if parsed >= 0 and parsed < names.size() else -1
	return names.find(text)


## Enum name (case-insensitive) or raw int / int-as-string -> value; -1 when absent/unrecognized.
func _enum_value(params: Dictionary, key: String, mapping: Dictionary) -> int:
	if not _has(params, key):
		return -1
	var raw: Variant = params[key]
	if typeof(raw) == TYPE_INT or typeof(raw) == TYPE_FLOAT:
		return int(raw)
	var text: String = str(raw).strip_edges().to_lower()
	if mapping.has(text):
		return int(mapping[text])
	if text.is_valid_int():
		return text.to_int()
	return -1


func _key_for_value(mapping: Dictionary, value: int) -> String:
	for key: String in mapping.keys():
		if int(mapping[key]) == value:
			return key
	return str(value)


## Resource-path textures are skipped silently when missing or of the wrong type.
func _load_texture(params: Dictionary, key: String) -> Texture2D:
	var path: String = optional_string(params, key, "")
	if path.is_empty():
		return null
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


## Breadth-first search for the first MeshInstance3D carrying a mesh.
func _find_first_mesh(node: Node) -> Mesh:
	var queue: Array[Node] = [node]
	while not queue.is_empty():
		var current: Node = queue.pop_front()
		if current is MeshInstance3D:
			var mesh_instance: MeshInstance3D = current as MeshInstance3D
			if mesh_instance.mesh != null:
				return mesh_instance.mesh
		for child: Node in current.get_children():
			queue.append(child)
	return null
