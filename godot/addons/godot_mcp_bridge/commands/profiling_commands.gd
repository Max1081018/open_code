@tool
extends "res://addons/godot_mcp_bridge/commands/base_command.gd"

## profiling category (SPEC §6, specs/B12) — 2 tools.
## Both read the EDITOR process's Performance singleton: the numbers describe the editor itself,
## not a running game (game metrics belong to the runtime category). Pure reads — no undo, no IO.
## Raw units: time_* in seconds (except time_fps), memory / VRAM in bytes.

const BYTES_PER_MB := 1048576.0


func get_commands() -> Dictionary:
	return {
		"get_performance_monitors": _get_performance_monitors,
		"get_editor_performance": _get_editor_performance,
	}


## snake_case key -> Performance monitor constant. Insertion order groups the prefixes.
func _monitor_map() -> Dictionary:
	return {
		"time_fps": Performance.TIME_FPS,
		"time_process": Performance.TIME_PROCESS,
		"time_physics_process": Performance.TIME_PHYSICS_PROCESS,
		"time_navigation_process": Performance.TIME_NAVIGATION_PROCESS,
		"memory_static": Performance.MEMORY_STATIC,
		"memory_static_max": Performance.MEMORY_STATIC_MAX,
		"object_count": Performance.OBJECT_COUNT,
		"object_node_count": Performance.OBJECT_NODE_COUNT,
		"object_orphan_node_count": Performance.OBJECT_ORPHAN_NODE_COUNT,
		"render_total_objects_in_frame": Performance.RENDER_TOTAL_OBJECTS_IN_FRAME,
		"render_total_primitives_in_frame": Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME,
		"render_total_draw_calls_in_frame": Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME,
		"render_video_mem_used": Performance.RENDER_VIDEO_MEM_USED,
		"render_texture_mem_used": Performance.RENDER_TEXTURE_MEM_USED,
		"render_buffer_mem_used": Performance.RENDER_BUFFER_MEM_USED,
		"physics_2d_active_objects": Performance.PHYSICS_2D_ACTIVE_OBJECTS,
		"physics_2d_collision_pairs": Performance.PHYSICS_2D_COLLISION_PAIRS,
		"physics_2d_island_count": Performance.PHYSICS_2D_ISLAND_COUNT,
		"physics_3d_active_objects": Performance.PHYSICS_3D_ACTIVE_OBJECTS,
		"physics_3d_collision_pairs": Performance.PHYSICS_3D_COLLISION_PAIRS,
		"physics_3d_island_count": Performance.PHYSICS_3D_ISLAND_COUNT,
		"navigation_active_maps": Performance.NAVIGATION_ACTIVE_MAPS,
		"navigation_region_count": Performance.NAVIGATION_REGION_COUNT,
		"navigation_agent_count": Performance.NAVIGATION_AGENT_COUNT,
		"navigation_link_count": Performance.NAVIGATION_LINK_COUNT,
		"navigation_polygon_count": Performance.NAVIGATION_POLYGON_COUNT,
		"navigation_edge_count": Performance.NAVIGATION_EDGE_COUNT,
		"navigation_edge_merge_count": Performance.NAVIGATION_EDGE_MERGE_COUNT,
		"navigation_edge_connection_count": Performance.NAVIGATION_EDGE_CONNECTION_COUNT,
		"navigation_edge_free_count": Performance.NAVIGATION_EDGE_FREE_COUNT,
	}


# ---------------------------------------------------------------------------
# get_performance_monitors
# ---------------------------------------------------------------------------


func _get_performance_monitors(params: Dictionary) -> Dictionary:
	# `category` is a key-prefix filter, not a lookup: an unknown prefix yields an empty dump.
	var category: String = optional_string(params, "category", "")

	var monitors: Dictionary = {}
	var map: Dictionary = _monitor_map()
	for key: String in map:
		if not category.is_empty() and not key.begins_with(category):
			continue
		monitors[key] = Performance.get_monitor(map[key])

	return success({"monitors": monitors, "count": monitors.size(), "category": category})


# ---------------------------------------------------------------------------
# get_editor_performance
# ---------------------------------------------------------------------------


func _get_editor_performance(_params: Dictionary) -> Dictionary:
	var frame_time: float = Performance.get_monitor(Performance.TIME_PROCESS)
	var static_mem: float = Performance.get_monitor(Performance.MEMORY_STATIC)
	var video_mem: float = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)

	return success(
		{
			"fps": _round2(Performance.get_monitor(Performance.TIME_FPS)),
			"frame_time_msec": _round2(frame_time * 1000.0),
			"draw_calls":
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			"objects_in_frame":
			int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
			"node_count": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
			"orphan_nodes": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
			"memory_static_mb": _round2(static_mem / BYTES_PER_MB),
			"video_mem_mb": _round2(video_mem / BYTES_PER_MB),
		}
	)


func _round2(value: float) -> float:
	return snappedf(value, 0.01)
