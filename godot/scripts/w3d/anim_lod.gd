class_name AnimLod
extends RefCounted
## Animation level of detail: a character far from the camera updates its
## skeleton every third frame (with the time it skipped, so it never slides
## or freezes mid-step), close ones every frame. Skeleton blending is one of
## the dearest things a crowd costs a phone's CPU.

const EVERY := 3


## Call every frame with whether the character is far. Holds its own count
## in `state` (a small Dictionary owned by the character).
static func step(anim: AnimationPlayer, far: bool, delta: float, state: Dictionary) -> void:
	if anim == null:
		return
	var manual := anim.callback_mode_process == AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	if far != manual:
		anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL if far else AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
		if not far and float(state.get("acc", 0.0)) > 0.0:
			anim.advance(float(state.acc))
		state["acc"] = 0.0
	if not far:
		return
	state["acc"] = float(state.get("acc", 0.0)) + delta
	state["n"] = int(state.get("n", 0)) + 1
	if int(state.n) % EVERY == 0:
		anim.advance(float(state.acc))
		state["acc"] = 0.0
