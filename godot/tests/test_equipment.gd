extends TestCase
## Equipment drawn in the hands: anchors, grips, swings, blocking.


## three_d: the player is the 3D model instead of the cut-out hero (the default).
func _make_level(three_d := false) -> Level:
	var was := [Settings.characters_3d, Settings.player_3d]
	Settings.characters_3d = three_d
	Settings.player_3d = three_d
	var level := Level.new()
	Engine.get_main_loop().root.add_child(level)
	level.start(777)
	Settings.characters_3d = was[0]
	Settings.player_3d = was[1]
	return level


func test_every_pose_the_rig_can_meet_has_hand_positions() -> void:
	for clip in ["idle", "walk", "run", "jump", "fall", "attack", "use", "swing_mine",
			"swing_chop", "slash", "hurt", "interact"]:
		for frame in CharacterFrames.CLIPS[clip][0]:
			check(RigData.HANDS.has(frame), "%s/%s has hands" % [clip, frame])


func test_the_front_hand_is_in_front() -> void:
	# The art faces right: the front fist is further right than the back one.
	for frame in ["idle", "walk0", "walk4", "attack0", "attack2"]:
		var pair: Array = RigData.HANDS[frame]
		check(pair[0].x > pair[1].x, "%s: front hand ahead of back hand" % frame)


func test_every_tool_and_weapon_icon_has_a_grip() -> void:
	for id in Items.defs:
		var kind := Items.kind(id)
		if kind in [Items.Kind.PICKAXE, Items.Kind.AXE, Items.Kind.SWORD]:
			var key := String(Items.def(id).icon)
			check(RigData.GRIPS.has(key), "%s (%s) has a grip" % [id, key])
	check(RigData.GRIPS.has("equipment/torch_held"), "the hand torch has a grip")


func test_grips_sit_toward_the_handle() -> void:
	# A pickaxe icon is drawn handle bottom-left, head top-right: the grip is
	# in the lower-left half and the axis points up and to the right.
	var pick: Array = RigData.GRIPS["items/toolPickaxe"]
	check(pick[0].x < 64 and pick[0].y > 64, "grip near the handle end")
	check(pick[1] < 0.0 and pick[1] > -PI / 2, "axis points up-right")
	var torch: Array = RigData.GRIPS["equipment/torch_held"]
	check_near(torch[1], -PI / 2, 0.1, "a torch is held upright")


func test_swing_curves_start_and_end_at_rest() -> void:
	for kind in EquipmentRig.CURVES:
		var keys: Array = EquipmentRig.CURVES[kind]
		check_near(EquipmentRig._curve(keys, 1.0), keys[keys.size() - 1][1], 0.01, "%s ends" % kind)
		check(EquipmentRig.IMPACT.has(kind), "%s has an impact moment" % kind)
		check(EquipmentRig.BODY.has(kind), "%s has a body clip" % kind)
		# The strike happens after the wind-up: the angle at impact is well
		# past the furthest point back.
		var back := 0.0
		for key in keys:
			back = minf(back, key[1])
		check(EquipmentRig._curve(keys, EquipmentRig.IMPACT[kind]) > back + 40.0,
			"%s has swung through by impact" % kind)


func test_a_swing_lands_once_at_its_impact_time() -> void:
	var level := _make_level()
	var rig := level.player.rig
	var hits := [0]
	rig.swing("mine", 0.4, func(): hits[0] += 1)
	rig._process(0.4 * 0.5)
	check_eq(hits[0], 0, "nothing lands during the wind-up")
	rig._process(0.4 * 0.1)
	check_eq(hits[0], 1, "it lands at the strike")
	rig._process(0.4)
	check_eq(hits[0], 1, "and only once")
	check(not rig.swinging(), "the swing is over")
	level.free()


func test_a_raised_shield_blocks_from_the_front_only() -> void:
	var level := _make_level()
	var player := level.player
	player.inventory.add("iron_shield", 1)
	player._refresh_held()
	check(player.rig.has_shield(), "the shield is carried")
	player.facing = 1
	player.rig.blocking = true
	player.health = 100.0
	player.hurt(20.0, player.global_position + Vector2(100, 0))
	check_near(player.health, 96.0, 0.01, "a frontal blow is mostly blocked (iron: 80%)")
	player._invulnerable = 0.0
	player.health = 100.0
	player.hurt(20.0, player.global_position - Vector2(100, 0))
	check_near(player.health, 80.0, 0.01, "a blow from behind is not")
	level.free()


func test_shields_are_craftable_items() -> void:
	for id in ["wood_shield", "iron_shield"]:
		check(Items.exists(id), "%s exists" % id)
		check(Items.kind(id) == Items.Kind.SHIELD, "%s is a shield" % id)
		check(Items.icon(id) != null, "%s has art" % id)
		var found := false
		for recipe in Items.recipes:
			if recipe[0] == id:
				found = true
		check(found, "%s has a recipe" % id)


func test_a_dodge_rolls_through_blows_and_then_cools_down() -> void:
	var level := _make_level()
	var player := level.player
	player.input.dodge_pressed = true
	player._dodge(1.0 / 60.0)
	check(player.dodging(), "the roll starts")
	check(absf(player.velocity.x) > 1000.0, "with a burst of speed")
	player.health = 100.0
	player.hurt(20.0, player.global_position + Vector2(80, 0))
	check_eq(player.health, 100.0, "blows pass through a rolling body")
	player._dodge(Player.DODGE_TIME)
	player._dodge(0.01)
	check(not player.dodging(), "the roll ends")
	player.input.dodge_pressed = true
	player._dodge(0.01)
	check(not player.dodging(), "and cannot be chained at once")
	player._dodge_cooldown = 0.0
	player.input.dodge_pressed = true
	player._dodge(0.01)
	if not player.is_on_floor():
		check(not player.dodging(), "only one dash in the air until you land")
	level.free()


func test_arm_ik_puts_the_hand_on_the_target() -> void:
	var level := _make_level(false)
	var body: CutoutBody = level.player.body
	var shoulder := body.shoulder_rig(true)
	var length := body.arm_length()
	for angle in [-150.0, -90.0, -30.0, 0.0, 45.0, 90.0]:
		var target := shoulder + Vector2.from_angle(deg_to_rad(angle)) * length * 0.8
		body.reach(true, target, angle)
		check(body.hand_rig(true).distance_to(target) < 1.5,
			"hand reaches %d degrees (off by %.1f px)" % [angle, body.hand_rig(true).distance_to(target)])
	var far := shoulder + Vector2(length * 3.0, 0)
	body.reach(true, far)
	var hand := body.hand_rig(true)
	check(hand.distance_to(shoulder) > length * 0.97, "out of reach: the arm straightens")
	check(absf((hand - shoulder).angle()) < 0.05, "and points at the target")
	level.free()


func test_the_held_item_sits_in_the_fist() -> void:
	var level := _make_level(false)
	var player := level.player
	player.inventory.slots[0] = {"id": "iron_pickaxe", "count": 1}
	player.hotbar_index = 0
	player._refresh_held()
	var rig := player.rig
	rig.swing("mine", 0.4)
	for i in 12:
		player.body._process(1.0 / 60.0)
		rig._process(1.0 / 60.0)
		var fist := player.to_local(player.body.front_hand())
		check(fist.distance_to(rig.main.position) < 3.0,
			"frame %d: grip and fist together (off by %.1f px)" % [i, fist.distance_to(rig.main.position)])
	level.free()


func test_footsteps_come_with_the_stride() -> void:
	for three_d in [true, false]:
		var level := _make_level(three_d)
		var body: Node2D = level.player.body
		var steps := [0, 0]
		body.footstep.connect(func(running): steps[1 if running else 0] += 1)
		var tick := func():
			if body is Body3D:
				body.anim.advance(1.0 / 60.0)
			body._process(1.0 / 60.0)
		body.grounded = true
		body.motion = Vector2(200, 0)  # a walk
		for i in 120:
			tick.call()
		check(steps[0] >= 2, "%s: walking two seconds takes steps (%d)" % [body.get_class(), steps[0]])
		body.motion = Vector2(600, 0)  # a run
		for i in 120:
			tick.call()
		check(steps[1] > steps[0], "%s: running takes more, quicker steps (%d vs %d)" % [body, steps[1], steps[0]])
		var before: int = steps[0] + steps[1]
		body.motion = Vector2.ZERO
		for i in 120:
			tick.call()
		check_eq(steps[0] + steps[1], before, "standing still takes none")
		level.free()


func test_the_3d_character_holds_items_on_its_hand_bone() -> void:
	var level := _make_level(true)
	var player := level.player
	var body: Body3D = player.body
	var bone: BoneAttachment3D = body.right_hand.get_parent()
	check(bone != null and bone.bone_name == "hand_r", "a grip on the right hand bone")
	for id in ["iron_pickaxe", "iron_axe", "wood_hammer", "iron_sword", "torch", "planks"]:
		player.inventory.slots[0] = {"id": id, "count": 1}
		player.hotbar_index = 0
		player._refresh_held()
		check(body._held != null and body._held.get_parent() == body.right_hand, "%s is parented to the hand bone" % id)
	# And it turns round when it changes direction, through facing the camera.
	body.flip_h = true
	for i in 5:
		body._process(1.0 / 60.0)
	check(body.facing_yaw < Body3D.SIDE_YAW and body.facing_yaw > -Body3D.SIDE_YAW, "mid-turn (%.0f degrees)" % body.facing_yaw)
	for i in 30:
		body._process(1.0 / 60.0)
	check_eq(body.facing_yaw, -Body3D.SIDE_YAW, "turned to face left")
	level.free()
