#!/usr/bin/env bash
# Play-test the game headlessly on Linux: imports the project, then runs it
# under a virtual X display with software OpenGL. The game's autotest mode
# steers the joystick toward the nearest orb, saves a screenshot and quits.
#
# Usage: game/tools/play.sh [frames] [screenshot.png]
# Needs: GODOT=/path/to/Godot_v4.3-stable_linux.x86_64 (or `godot` on PATH), xvfb-run.
set -euo pipefail

GAME_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-godot}"
FRAMES="${1:-600}"
SHOT="${2:-$GAME_DIR/build/autotest.png}"
mkdir -p "$(dirname "$SHOT")"

# First import generates .godot/ (the editor's cache); without it the game
# can't load the icon or scripts' global classes.
"$GODOT" --headless --path "$GAME_DIR" --import >/dev/null 2>&1 || true

# llvmpipe = Mesa's software OpenGL; no GPU needed.
LIBGL_ALWAYS_SOFTWARE=1 xvfb-run -a -s "-screen 0 1280x720x24" \
  "$GODOT" --path "$GAME_DIR" --rendering-driver opengl3 --resolution 1280x720 --fixed-fps 60 \
  -- --autotest --frames="$FRAMES" --shot="$SHOT"

echo "Screenshot: $SHOT"
