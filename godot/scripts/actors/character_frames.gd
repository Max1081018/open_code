class_name CharacterFrames
extends RefCounted
## SpriteFrames for the Toon characters, which all share one pose set.

## animation -> [frame names, frames per second, loops]
const CLIPS := {
	"idle": [["idle"], 1.0, true],
	"walk": [["walk0", "walk1", "walk2", "walk3", "walk4", "walk5", "walk6", "walk7"], 13.0, true],
	"run": [["run0", "run1", "run2"], 11.0, true],
	"jump": [["jump"], 1.0, false],
	"fall": [["fall"], 1.0, false],
	"attack": [["attack0", "attack1", "attack2"], 18.0, false],
	"use": [["attack1", "attack2", "attack1"], 16.0, false],
	# Tool swings: the art's attack1 is the raised wind-up, attack0 the
	# strike, attack2 the follow-through.
	"swing_mine": [["attack1", "attack1", "attack0", "attack2", "attack2", "attack0"], 16.0, false],
	"swing_chop": [["attack0", "attack1", "attack1", "attack2", "attack2", "attack0"], 16.0, false],
	"slash": [["attack1", "attack0", "attack2", "attack2", "attack0"], 18.0, false],
	"hurt": [["hurt"], 1.0, false],
	"death": [["hit", "fallDown"], 6.0, false],
	"interact": [["interact"], 1.0, false],
	"climb": [["climb0", "climb1"], 6.0, true],
	"cheer": [["cheer0", "cheer1"], 5.0, true],
	"talk": [["talk", "idle"], 3.0, true],
}

static var _cache := {}


static func build(character: String) -> SpriteFrames:
	if _cache.has(character):
		return _cache[character]
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	for clip in CLIPS:
		var spec: Array = CLIPS[clip]
		frames.add_animation(clip)
		frames.set_animation_speed(clip, spec[1])
		frames.set_animation_loop(clip, spec[2])
		for name in spec[0]:
			var path := "res://assets/characters/%s/%s.png" % [character, name]
			if ResourceLoader.exists(path):
				frames.add_frame(clip, load(path))
	_cache[character] = frames
	return frames
