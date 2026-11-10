#!/usr/bin/env bash
# Play-test Lazy Lake headlessly on Linux: import the project, then run it under
# a virtual X display with software OpenGL. The game's autotest mode plays full
# casts with synthetic touch input, saves a screenshot and quits.
#
# Usage: fishing/tools/play.sh [frames] [screenshot.png]
# Needs: GODOT=/path/to/Godot_v4.3-stable_linux.x86_64 (or `godot` on PATH), xvfb-run.
set -euo pipefail

GAME_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-godot}"
FRAMES="${1:-1800}"
SHOT="${2:-$GAME_DIR/build/autotest.png}"
mkdir -p "$(dirname "$SHOT")"

"$GODOT" --headless --path "$GAME_DIR" --import >/dev/null 2>&1 || true

LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1280x720x24" \
  "$GODOT" --path "$GAME_DIR" --rendering-driver opengl3 --resolution 1280x720 --fixed-fps 60 \
  -- --autotest --fresh --screen=play --frames="$FRAMES" --shot="$SHOT"

echo "Screenshot: $SHOT"
