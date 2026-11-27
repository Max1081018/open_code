extends TestCase
## The heroine holds weapons and tools by magic: an equipped sword floats
## beside her right hand, stays visible at rest, flies to the palm's line when
## she strikes, rises for a cast, and the violet magic around her hand grows
## brighter with what she does. Torches stay in her fist.


func test_floating_weapon_follows_her_state() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var main: Node = load("res://scenes/main3d.tscn").instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	await tree.process_frame
	var p: Player3D = main.player
	var mh := p.magic_hold
	check(mh != null, "she has a magic hold")
	check(MagicHold.floats("moonblade"), "swords float")
	check(not MagicHold.floats("torch"), "torches do not")
	p.hold("moonblade")
	await tree.create_timer(1.2).timeout
	check(mh.item != null and mh.item.is_inside_tree(), "the sword is in the hold")
	check(mh.visible and mh.item.visible, "and visible at rest (not hidden away)")
	check_eq(mh.mode, MagicHold.Mode.REST, "at rest")
	var hand := p.right_hand.global_position
	var gap := mh.global_position.distance_to(hand)
	check(gap > 0.08 and gap < 0.5, "it floats beside the hand, not in the fist (%.2f m)" % gap)
	check(mh.global_transform.basis.y.normalized().y > 0.7, "point up")
	var rest_energy := mh.energy
	check(rest_energy > 0.2 and rest_energy < 0.6, "the magic is faint at rest")

	# Strike: the hold snaps to the palm's line and the magic brightens.
	p._start_action(false)
	await tree.create_timer(0.15).timeout
	check_eq(mh.mode, MagicHold.Mode.STRIKE, "a swing takes it into strike")
	var palm := p.right_hand.global_position + p.right_hand.global_transform.basis.z.normalized() * MagicHold.PALM_GAP
	check(mh.global_position.distance_to(palm) < 0.2, "it follows the palm through the swing")
	check(mh.energy > rest_energy + 0.3, "the magic flares when she strikes")
	# Back to rest after the swing.
	await tree.create_timer(1.0).timeout
	check_eq(mh.mode, MagicHold.Mode.REST, "it drifts back to rest")

	# Cast: raised and brightest.
	mh.cast(1.0)
	await tree.create_timer(0.5).timeout
	check_eq(mh.mode, MagicHold.Mode.CAST, "a spell raises it")
	check(mh.energy > 1.0, "the magic burns brightest in a cast")

	# A torch is gripped, and the hold empties.
	p.hold("torch")
	await tree.process_frame
	check(mh.item == null, "a torch leaves the magic hold empty")
	check(not mh.visible, "and the hold hides")
	main.queue_free()
	await tree.process_frame
