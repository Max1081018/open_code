#!/usr/bin/env bash
# Disable the bridge addon and remove the autoloads it injected.
set -euo pipefail
cd "$(dirname "$0")/../.."
sed -i 's|, "res://addons/godot_mcp_bridge/plugin.cfg"||' project.godot
sed -i '/^MCPGameInspector=/d; /^MCPInputService=/d; /^MCPScreenshot=/d' project.godot
pkill -f "godot --headless -e --path ." || true
echo "bridge disabled; project.godot is export-clean"
