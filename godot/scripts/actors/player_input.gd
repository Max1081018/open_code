class_name PlayerInput
extends RefCounted
## One frame of player intent, whatever produced it: keyboard and mouse
## on desktop, the touch controls on a phone, or a scripted test.

var move := 0.0
var jump_held := false
var jump_pressed := false
var use_held := false  ## using the held item at `aim`
var aim := Vector2.ZERO  ## world position
var hover := Vector2.INF  ## mouse position in the world (desktop), INF on touch
var attack_pressed := false
var interact_pressed := false
var block_held := false  ## raising the shield
var dodge_pressed := false
var hotbar_select := -1


## Clear the one-frame edges after the player has consumed them.
func end_frame() -> void:
	jump_pressed = false
	attack_pressed = false
	interact_pressed = false
	dodge_pressed = false
	hotbar_select = -1
