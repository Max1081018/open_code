#!/usr/bin/env bash
# Repeatable performance benchmark (see scripts/w3d/bench.gd).
#   tools/bench.sh OUT.jsonl [frames] [gpu|cpu]        (from godot/)
# gpu (default): software OpenGL at 640x360 -> draw calls, primitives, video
#   memory, load and hitch times (frame times here are the software
#   renderer's, not a phone's).
# cpu: no renderer at all (--headless) -> frame time is pure game CPU work
#   (scripts, physics, AI, animation, culling): the number that carries over.
# One line per scenario: frame times, 1% low, script/physics time, draw
# calls, primitives, memory, the scene's load time (and per-stage load
# times for the world). Runs at 640x360 on the software renderer: absolute
# FPS here is not a phone's, but CPU time, draw calls, primitives, memory
# and load times compare build to build.
set -u
cd "$(dirname "$0")/.."
out=${1:-/tmp/bench.jsonl}
frames=${2:-120}
mode=${3:-gpu}
only=${4:-}      # optional: space-separated scenario tags to run
settle=${SETTLE:-90}
[ -n "$only" ] || : > "$out"
run() {  # tag scene args...
	local tag=$1 scene=$2; shift 2
	if [ -n "$only" ] && [[ " $only " != *" $tag "* ]]; then return; fi
	local log
	if [ "$mode" = cpu ]; then
		log=$(timeout 1500 godot --headless --path . "$scene" -- --bench="$frames" --settle="$settle" --tag="$tag" "$@" 2>&1)
	else
		log=$(timeout 1500 xvfb-run -a -s "-screen 0 640x360x24" godot --path . --rendering-driver opengl3 \
			--resolution 640x360 "$scene" -- --bench="$frames" --settle="$settle" --tag="$tag" "$@" 2>&1)
	fi
	local line stages
	line=$(grep -m1 '^BENCH ' <<<"$log" | sed 's/^BENCH //')
	stages=$(grep -m1 '^READY_STAGES ' <<<"$log" | sed 's/^READY_STAGES //')
	if [ -z "$line" ]; then
		echo "{\"scene\":\"$tag\",\"error\":\"no result\"}" >> "$out"
		grep -E "SCRIPT ERROR|ERROR" <<<"$log" | head -3 >&2
	else
		[ -n "$stages" ] && line="${line%\}},\"stages\":$stages}"
		echo "$line" >> "$out"
	fi
	echo "$tag done" >&2
}
run menu res://scenes/menu3d.tscn --front=login
run town res://scenes/main3d.tscn --start= --yaw=3.1 --pitch=-0.15
run jungle res://scenes/main3d.tscn --start=jungle
run sky res://scenes/main3d.tscn --start=sky
run coast res://scenes/main3d.tscn --start=coast
run combat res://scenes/main3d.tscn --start= --spawn=zombie,robot,shade,warden --action=run
run boss res://scenes/main3d.tscn --start=jungle --boss=jungle --wake=10
