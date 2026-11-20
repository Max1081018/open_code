extends Node

## GAME-SIDE autoload (injected by the plugin). No @tool — this only runs in the game.
##
## File IPC (frozen): editor writes `user://mcp_screenshot_request`
## (optionally `{"half_resolution": true}`), we capture the viewport and write
## `user://mcp_screenshot.png`; the editor polls for the PNG for up to 3s.

const REQUEST_PATH := "user://mcp_screenshot_request"
const OUTPUT_PATH := "user://mcp_screenshot.png"

var _busy: bool = false


func _ready() -> void:
	# Clear stale files from a previous run.
	if FileAccess.file_exists(REQUEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(REQUEST_PATH))


func _process(_delta: float) -> void:
	if _busy:
		return
	if not FileAccess.file_exists(REQUEST_PATH):
		return
	_busy = true
	_handle_request()


func _handle_request() -> void:
	var half_resolution: bool = false

	var file: FileAccess = FileAccess.open(REQUEST_PATH, FileAccess.READ)
	if file != null:
		var text: String = file.get_as_text()
		file.close()
		if not text.strip_edges().is_empty():
			var parsed: Variant = JSON.parse_string(text)
			if typeof(parsed) == TYPE_DICTIONARY:
				half_resolution = bool((parsed as Dictionary).get("half_resolution", false))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(REQUEST_PATH))

	await RenderingServer.frame_post_draw

	var viewport: Viewport = get_viewport()
	if viewport == null:
		_busy = false
		return
	var texture: ViewportTexture = viewport.get_texture()
	if texture == null:
		_busy = false
		return
	var image: Image = texture.get_image()
	if image == null:
		_busy = false
		return

	if half_resolution and image.get_width() > 1 and image.get_height() > 1:
		image.resize(
			maxi(1, image.get_width() / 2),
			maxi(1, image.get_height() / 2),
			Image.INTERPOLATE_LANCZOS
		)

	var err: int = image.save_png(OUTPUT_PATH)
	if err != OK:
		push_error("[MCP] screenshot save failed: %s" % error_string(err))

	_busy = false
