@tool
extends "res://addons/godot_mcp_bridge/commands/base_command.gd"

## resource category (SPEC §6, specs/B01) — 4 tools.
## Every handler is editor-side and needs no open scene: never call error_no_scene() here.

const PropertyParser := preload("res://addons/godot_mcp_bridge/utils/property_parser.gd")

## Internal bookkeeping props that are never meaningful to expose or edit.
const SKIPPED_PROPS: PackedStringArray = [
	"script", "resource_local_to_scene", "resource_path", "resource_name"
]
const IMAGE_EXTENSIONS: PackedStringArray = ["png", "jpg", "jpeg", "svg", "webp", "bmp"]


func get_commands() -> Dictionary:
	return {
		"read_resource": _read_resource,
		"edit_resource": _edit_resource,
		"create_resource": _create_resource,
		"get_resource_preview": _get_resource_preview,
	}


# ---------------------------------------------------------------------------
# read_resource
# ---------------------------------------------------------------------------


func _read_resource(params: Dictionary) -> Dictionary:
	var res: Array = require_string(params, "path")
	if res[1] != null:
		return res[1]
	var path: String = res[0]

	var resource: Resource = ResourceLoader.load(path)
	if resource == null:
		return error_not_found("Resource: %s" % path)

	return success(
		{
			"path": path,
			"type": resource.get_class(),
			"properties": _serialize_resource_properties(resource),
		}
	)


func _serialize_resource_properties(resource: Resource) -> Dictionary:
	var out: Dictionary = {}
	for prop: Dictionary in resource.get_property_list():
		var prop_name: String = str(prop.get("name", ""))
		if prop_name.is_empty() or SKIPPED_PROPS.has(prop_name):
			continue
		var usage: int = int(prop.get("usage", 0))
		if usage & PROPERTY_USAGE_EDITOR == 0:
			continue
		if usage & PROPERTY_USAGE_GROUP != 0 or usage & PROPERTY_USAGE_CATEGORY != 0:
			continue
		if usage & PROPERTY_USAGE_SUBGROUP != 0:
			continue
		out[prop_name] = PropertyParser.serialize_value(resource.get(prop_name))
	return out


# ---------------------------------------------------------------------------
# edit_resource
# ---------------------------------------------------------------------------


func _edit_resource(params: Dictionary) -> Dictionary:
	var res: Array = require_string(params, "path")
	if res[1] != null:
		return res[1]
	var path: String = res[0]

	if not params.has("properties") or typeof(params["properties"]) != TYPE_DICTIONARY:
		return error(-32602, "Missing required parameter: properties (expected an object)")
	var props: Dictionary = params["properties"]
	if props.is_empty():
		return error(-32602, "Missing required parameter: properties (must not be empty)")

	var resource: Resource = ResourceLoader.load(path)
	if resource == null:
		return error_not_found("Resource: %s" % path)

	var types: Dictionary = _property_types(resource)
	var changed: Dictionary = {}

	for key: Variant in props:
		var prop_name: String = str(key)
		if not types.has(prop_name):
			return error(
				-32602,
				"Resource %s has no property: %s" % [resource.get_class(), prop_name],
				{"path": path, "property": prop_name}
			)
		var target_type: int = int(types[prop_name])
		var old_value: Variant = resource.get(prop_name)
		var new_value: Variant = _parse_for_target(props[key], target_type)

		resource.set(prop_name, new_value)
		var after: Variant = resource.get(prop_name)

		# Object.set() is a silent no-op when the value fails the property's type check, so
		# never report a prop as changed on the strength of the request alone: compare.
		if not _values_equal(old_value, after):
			changed[prop_name] = {
				"old": PropertyParser.serialize_value(old_value),
				"new": PropertyParser.serialize_value(after),
			}
		elif not _values_equal(new_value, after):
			return error(
				-32602,
				(
					"Could not set %s on %s: value was rejected (expected %s, still %s)"
					% [
						prop_name,
						resource.get_class(),
						type_string(typeof(new_value)),
						type_string(typeof(after)),
					]
				),
				{
					"path": path,
					"property": prop_name,
					"expected_type": type_string(target_type),
					"value": PropertyParser.serialize_value(new_value),
				}
			)

	if changed.is_empty():
		return success({"path": path, "changed": changed, "count": 0})

	var err: int = ResourceSaver.save(resource, path)
	if err != OK:
		return error(-32603, "Failed to save resource %s: %s" % [path, error_string(err)])

	return success({"path": path, "changed": changed, "count": changed.size()})


## parse_value + the one coercion it cannot do: an Object-typed property assigned by path.
## "res://icon.svg" / "uid://abc" for e.g. albedo_texture must become the loaded Resource,
## otherwise Object.set() silently drops the raw String and the edit no-ops.
static func _parse_for_target(value: Variant, target_type: int) -> Variant:
	if target_type == TYPE_OBJECT and typeof(value) == TYPE_STRING:
		var s: String = String(value).strip_edges()
		if s.is_empty():
			return null
		if s.begins_with("res://") or s.begins_with("uid://"):
			return ResourceLoader.load(s)
	return PropertyParser.parse_value(value, target_type)


static func _values_equal(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return false
	return a == b


func _property_types(resource: Resource) -> Dictionary:
	var out: Dictionary = {}
	for prop: Dictionary in resource.get_property_list():
		var prop_name: String = str(prop.get("name", ""))
		if prop_name.is_empty():
			continue
		out[prop_name] = int(prop.get("type", TYPE_NIL))
	return out


# ---------------------------------------------------------------------------
# create_resource
# ---------------------------------------------------------------------------


func _create_resource(params: Dictionary) -> Dictionary:
	var path_res: Array = require_string(params, "path")
	if path_res[1] != null:
		return path_res[1]
	var type_res: Array = require_string(params, "type")
	if type_res[1] != null:
		return type_res[1]

	var path: String = path_res[0]
	var type_name: String = type_res[0]
	var overwrite: bool = optional_bool(params, "overwrite", false)

	var props: Dictionary = {}
	if params.has("properties") and typeof(params["properties"]) == TYPE_DICTIONARY:
		props = params["properties"]

	if not ClassDB.class_exists(type_name):
		return error(-32602, "Unknown class: %s" % type_name)
	if not ClassDB.is_parent_class(type_name, "Resource"):
		return error(-32602, "Not a Resource subclass: %s" % type_name)
	if not ClassDB.can_instantiate(type_name):
		return error(-32602, "Class cannot be instantiated: %s" % type_name)

	if FileAccess.file_exists(path) and not overwrite:
		return error(
			-32000,
			"Resource already exists: %s" % path,
			{"path": path, "suggestion": "pass overwrite: true to replace it"}
		)

	var instance: Variant = ClassDB.instantiate(type_name)
	var resource: Resource = instance as Resource
	if resource == null:
		return error(-32603, "Failed to instantiate resource of type %s" % type_name)

	var types: Dictionary = _property_types(resource)
	var applied: Dictionary = {}
	for key: Variant in props:
		var prop_name: String = str(key)
		if not types.has(prop_name):
			return error(
				-32602,
				"Resource %s has no property: %s" % [type_name, prop_name],
				{"type": type_name, "property": prop_name}
			)
		var target_type: int = int(types[prop_name])
		resource.set(prop_name, _parse_for_target(props[key], target_type))
		applied[prop_name] = PropertyParser.serialize_value(resource.get(prop_name))

	var base_dir: String = path.get_base_dir()
	if not base_dir.is_empty() and not DirAccess.dir_exists_absolute(base_dir):
		var mk: int = DirAccess.make_dir_recursive_absolute(base_dir)
		if mk != OK:
			return error(-32603, "Failed to create directory %s: %s" % [base_dir, error_string(mk)])

	var err: int = ResourceSaver.save(resource, path)
	if err != OK:
		return error(-32603, "Failed to save resource %s: %s" % [path, error_string(err)])

	var fs: EditorFileSystem = EditorInterface.get_resource_filesystem()
	if fs != null:
		fs.scan()

	return success({"path": path, "type": type_name, "properties_applied": applied})


# ---------------------------------------------------------------------------
# get_resource_preview
# ---------------------------------------------------------------------------


func _get_resource_preview(params: Dictionary) -> Dictionary:
	var res: Array = require_string(params, "path")
	if res[1] != null:
		return res[1]
	var path: String = res[0]
	var max_size: int = maxi(1, optional_int(params, "max_size", 256))

	var image: Image = null
	var ext: String = path.get_extension().to_lower()
	if IMAGE_EXTENSIONS.has(ext):
		image = Image.load_from_file(path)

	if image == null:
		var resource: Resource = ResourceLoader.load(path)
		if resource == null:
			return error_not_found("Resource: %s" % path)
		var source: Image = null
		if resource is Texture2D:
			source = (resource as Texture2D).get_image()
		elif resource is Image:
			source = resource as Image
		else:
			return error(
				-32000,
				"Resource is not previewable: %s (%s)" % [path, resource.get_class()],
				{"path": path, "type": resource.get_class()}
			)
		# The Image handed back here can be the live, cache-shared object: `resource as Image`
		# IS the cached Resource, and some Texture2D subclasses (e.g. NoiseTexture2D) return
		# their internal Ref<Image> rather than a copy. decompress()/resize() mutate in place,
		# so preview a deep copy — a read-only call must never downscale the real resource.
		if source != null and not source.is_empty():
			image = Image.new()
			image.copy_from(source)

	if image == null or image.is_empty():
		return error(-32000, "Resource is not previewable: %s" % path, {"path": path})

	if image.is_compressed():
		var derr: int = image.decompress()
		if derr != OK:
			return error(
				-32603, "Failed to decompress image %s: %s" % [path, error_string(derr)]
			)

	var original_width: int = image.get_width()
	var original_height: int = image.get_height()

	var longest: int = maxi(original_width, original_height)
	if longest > max_size and longest > 0:
		var scale: float = float(max_size) / float(longest)
		var new_width: int = maxi(1, int(roundf(float(original_width) * scale)))
		var new_height: int = maxi(1, int(roundf(float(original_height) * scale)))
		image.resize(new_width, new_height, Image.INTERPOLATE_LANCZOS)

	var png: PackedByteArray = image.save_png_to_buffer()
	if png.is_empty():
		return error(-32603, "Failed to encode PNG for %s" % path)

	return success(
		{
			"image": Marshalls.raw_to_base64(png),
			"width": image.get_width(),
			"height": image.get_height(),
			"original_width": original_width,
			"original_height": original_height,
			"path": path,
		}
	)
