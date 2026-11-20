@tool
extends RefCounted

## Property value format (FROZEN, both sides — SPEC §3.4).
##
## Tool params accept native JSON numbers/bools plus strings coerced editor-side against
## the target property's type: "Vector2(100, 200)", "Vector3(1, 2, 3)", "Color(1, 0, 0, 1)"
## or "#ff0000", "true"/"false", "42", "3.14", plain strings.
## Constructor strings are evaluated with a restricted Expression, only when they match
## Godot constructor shape (^[A-Za-z0-9_]+\().

const CONSTRUCTOR_RE := "^[A-Za-z0-9_]+\\("


static func parse_value(value: Variant, target_type: int) -> Variant:
	var t: int = typeof(value)

	# Non-string values pass through, with int<->float coercion toward the target type.
	if t != TYPE_STRING and t != TYPE_STRING_NAME:
		if target_type == TYPE_INT and t == TYPE_FLOAT:
			return int(roundf(float(value)))
		if target_type == TYPE_FLOAT and t == TYPE_INT:
			return float(value)
		if target_type == TYPE_BOOL and (t == TYPE_INT or t == TYPE_FLOAT):
			return not is_zero_approx(float(value))
		# Vector/Color-ish objects arriving as JSON dicts/arrays.
		if t == TYPE_DICTIONARY or t == TYPE_ARRAY:
			var built: Variant = _from_collection(value, target_type)
			if built != null:
				return built
		return value

	var s: String = String(value).strip_edges()

	match target_type:
		TYPE_BOOL:
			return s.to_lower() == "true" or s == "1"
		TYPE_INT:
			if s.is_valid_int():
				return s.to_int()
			if s.is_valid_float():
				return int(roundf(s.to_float()))
			return _eval_or_raw(s)
		TYPE_FLOAT:
			if s.is_valid_float():
				return s.to_float()
			return _eval_or_raw(s)
		TYPE_STRING, TYPE_STRING_NAME, TYPE_NODE_PATH:
			return s
		TYPE_COLOR:
			return _parse_color(s)
		TYPE_VECTOR2, TYPE_VECTOR2I, TYPE_VECTOR3, TYPE_VECTOR3I, TYPE_VECTOR4, TYPE_VECTOR4I, TYPE_RECT2, TYPE_RECT2I, TYPE_QUATERNION, TYPE_PLANE, TYPE_BASIS, TYPE_TRANSFORM2D, TYPE_TRANSFORM3D, TYPE_AABB:
			return _eval_or_raw(s)
		TYPE_NIL:
			return _parse_untyped(s)
		_:
			return _eval_or_raw(s)


static func _parse_untyped(s: String) -> Variant:
	var lower: String = s.to_lower()
	if lower == "true":
		return true
	if lower == "false":
		return false
	if s.is_valid_int():
		return s.to_int()
	if s.is_valid_float():
		return s.to_float()
	if s.begins_with("#"):
		return _parse_color(s)
	if _is_constructor(s):
		return _eval_or_raw(s)
	return s


static func _parse_color(s: String) -> Variant:
	if s.begins_with("#"):
		# Color.html() answers opaque black for malformed hex, which would silently commit a
		# black value instead of reporting a bad param. Hand the raw string back so the caller's
		# TYPE_COLOR check fails and it can return -32602.
		if not s.is_valid_html_color():
			return s
		return Color.html(s)
	if _is_constructor(s):
		return _eval_or_raw(s)
	if s.is_valid_html_color():
		return Color.html(s)
	# Named colors ("red", "cornflower_blue", …). Color.from_string returns the fallback
	# when the name is unknown, so probe with two distinct fallbacks to tell them apart.
	var a: Color = Color.from_string(s, Color.BLACK)
	var b: Color = Color.from_string(s, Color.WHITE)
	if a == b:
		return a
	return s


static func _is_constructor(s: String) -> bool:
	var re := RegEx.new()
	re.compile(CONSTRUCTOR_RE)
	return re.search(s) != null and s.ends_with(")")


## Evaluate a Godot constructor expression with a restricted Expression; raw string on failure.
static func _eval_or_raw(s: String) -> Variant:
	if not _is_constructor(s):
		return s
	var expr := Expression.new()
	if expr.parse(s) != OK:
		return s
	var out: Variant = expr.execute([], null, false)
	if expr.has_execute_failed():
		return s
	return out


static func _from_collection(value: Variant, target_type: int) -> Variant:
	if typeof(value) == TYPE_DICTIONARY:
		var d: Dictionary = value
		match target_type:
			TYPE_VECTOR2:
				return Vector2(float(d.get("x", 0.0)), float(d.get("y", 0.0)))
			TYPE_VECTOR2I:
				return Vector2i(int(d.get("x", 0)), int(d.get("y", 0)))
			TYPE_VECTOR3:
				return Vector3(
					float(d.get("x", 0.0)), float(d.get("y", 0.0)), float(d.get("z", 0.0))
				)
			TYPE_VECTOR3I:
				return Vector3i(int(d.get("x", 0)), int(d.get("y", 0)), int(d.get("z", 0)))
			TYPE_VECTOR4:
				return Vector4(
					float(d.get("x", 0.0)),
					float(d.get("y", 0.0)),
					float(d.get("z", 0.0)),
					float(d.get("w", 0.0))
				)
			TYPE_COLOR:
				return Color(
					float(d.get("r", 0.0)),
					float(d.get("g", 0.0)),
					float(d.get("b", 0.0)),
					float(d.get("a", 1.0))
				)
			TYPE_RECT2:
				return Rect2(
					float(d.get("x", 0.0)),
					float(d.get("y", 0.0)),
					float(d.get("width", d.get("w", 0.0))),
					float(d.get("height", d.get("h", 0.0)))
				)
		return null

	if typeof(value) == TYPE_ARRAY:
		var a: Array = value
		match target_type:
			TYPE_VECTOR2:
				if a.size() >= 2:
					return Vector2(float(a[0]), float(a[1]))
			TYPE_VECTOR2I:
				if a.size() >= 2:
					return Vector2i(int(a[0]), int(a[1]))
			TYPE_VECTOR3:
				if a.size() >= 3:
					return Vector3(float(a[0]), float(a[1]), float(a[2]))
			TYPE_VECTOR3I:
				if a.size() >= 3:
					return Vector3i(int(a[0]), int(a[1]), int(a[2]))
			TYPE_VECTOR4:
				if a.size() >= 4:
					return Vector4(float(a[0]), float(a[1]), float(a[2]), float(a[3]))
			TYPE_COLOR:
				if a.size() >= 3:
					return Color(
						float(a[0]),
						float(a[1]),
						float(a[2]),
						float(a[3]) if a.size() > 3 else 1.0
					)
			TYPE_RECT2:
				if a.size() >= 4:
					return Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3]))
		return null

	return null


## Render a Variant back into the same string shapes the parser accepts.
static func serialize_value(value: Variant) -> Variant:
	match typeof(value):
		TYPE_NIL:
			return null
		TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return value
		TYPE_STRING_NAME, TYPE_NODE_PATH:
			return String(value)
		TYPE_VECTOR2:
			var v2: Vector2 = value
			return "Vector2(%s, %s)" % [_num(v2.x), _num(v2.y)]
		TYPE_VECTOR2I:
			var v2i: Vector2i = value
			return "Vector2i(%d, %d)" % [v2i.x, v2i.y]
		TYPE_VECTOR3:
			var v3: Vector3 = value
			return "Vector3(%s, %s, %s)" % [_num(v3.x), _num(v3.y), _num(v3.z)]
		TYPE_VECTOR3I:
			var v3i: Vector3i = value
			return "Vector3i(%d, %d, %d)" % [v3i.x, v3i.y, v3i.z]
		TYPE_VECTOR4:
			var v4: Vector4 = value
			return "Vector4(%s, %s, %s, %s)" % [_num(v4.x), _num(v4.y), _num(v4.z), _num(v4.w)]
		TYPE_COLOR:
			var c: Color = value
			return "Color(%s, %s, %s, %s)" % [_num(c.r), _num(c.g), _num(c.b), _num(c.a)]
		TYPE_RECT2:
			var r: Rect2 = value
			return (
				"Rect2(%s, %s, %s, %s)"
				% [_num(r.position.x), _num(r.position.y), _num(r.size.x), _num(r.size.y)]
			)
		TYPE_RECT2I:
			var ri: Rect2i = value
			return (
				"Rect2i(%d, %d, %d, %d)"
				% [ri.position.x, ri.position.y, ri.size.x, ri.size.y]
			)
		TYPE_QUATERNION, TYPE_PLANE, TYPE_BASIS, TYPE_TRANSFORM2D, TYPE_TRANSFORM3D, TYPE_AABB:
			return var_to_str(value).replace("\n", " ")
		TYPE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY:
			var out_arr: Array = []
			for item: Variant in value:
				out_arr.append(serialize_value(item))
			return out_arr
		TYPE_DICTIONARY:
			var out_dict: Dictionary = {}
			for key: Variant in value:
				out_dict[str(key)] = serialize_value(value[key])
			return out_dict
		TYPE_OBJECT:
			if value == null:
				return null
			var obj: Object = value
			var desc: Dictionary = {"type": obj.get_class()}
			if obj is Resource:
				var res: Resource = obj
				if not res.resource_path.is_empty():
					desc["resource_path"] = res.resource_path
			if obj is Node:
				desc["name"] = str((obj as Node).name)
			return desc
		_:
			return str(value)


static func _num(f: float) -> String:
	if is_equal_approx(f, roundf(f)) and absf(f) < 1e15:
		return str(int(roundf(f)))
	return String.num(f, 4).rstrip("0").rstrip(".")
