#!/usr/bin/env bash
# Start the Beckett MCP server in a headless Godot editor and print the
# command that registers it with Claude Code. No display is needed:
# BECKETT_ENABLE=1 forces the server on without the editor's GUI.
set -euo pipefail
cd "$(dirname "$0")/../.."
GODOT="${GODOT:-godot}"
LOG="${TMPDIR:-/tmp}/beckett-editor.log"
BECKETT_ENABLE=1 "$GODOT" --headless -e --path . >"$LOG" 2>&1 &
echo "editor pid $! (log: $LOG); waiting for the server..."
for _ in $(seq 1 150); do
  url=$(grep -oE "http://127\.0\.0\.1:[0-9]+/mcp/[0-9a-f]+" "$LOG" | head -1 || true)
  if [ -n "$url" ]; then
    echo "Beckett is listening: $url"
    echo "Register once with:  claude mcp add --transport http beckett $url"
    exit 0
  fi
  sleep 1
done
echo "server did not start; see $LOG" >&2
exit 1
