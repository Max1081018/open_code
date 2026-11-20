#!/usr/bin/env bash
# Enable the godot-mcp-bridge addon for this session and start a headless
# editor that dials the bridge. The bridge itself is started by Claude Code
# (stdio). Run tools/mcp/stop_bridge.sh before exporting: the addon injects
# three autoloads that would otherwise ship inside the game.
set -euo pipefail
cd "$(dirname "$0")/../.."
grep -q godot_mcp_bridge/plugin.cfg project.godot || \
  sed -i 's|enabled=PackedStringArray("res://addons/beckett/plugin.cfg")|enabled=PackedStringArray("res://addons/beckett/plugin.cfg", "res://addons/godot_mcp_bridge/plugin.cfg")|' project.godot
"${GODOT:-godot}" --headless -e --path . >"${TMPDIR:-/tmp}/bridge-editor.log" 2>&1 &
echo "editor pid $!; register the bridge once with:"
echo "  claude mcp add --scope user godot -- node /absolute/path/to/godot-mcp-bridge/dist/index.js"
