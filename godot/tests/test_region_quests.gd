extends TestCase
## Each region has a quest line: wake its Starstone, then defeat its foes.
## The lines follow one another, Gloomwood first.


func test_region_lines() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var main: Node = load("res://scenes/main3d.tscn").instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	var q: Quests3D = main.quests
	check(q.offer_for("mira").get("id", "") == "shards", "Mira starts with the Starshards")
	q.state["shards"] = "done"
	check(q.offer_for("mira").is_empty(), "the Gloomwood waits for the Night Hunt")
	q.state["hunt"] = "done"
	var g := q.offer_for("mira")
	check(g.get("id", "") == "gloom_stone", "then Mira asks for the Gloomwood's Starstone")
	check(not main.starstones.stone("the_gloomwood").is_empty(), "the Gloomwood has a Starstone")
	q._accept(g)
	check(q.tracker().target is Vector3, "the tracker points at the stone")
	main.starstones.attune("the_gloomwood")
	await tree.process_frame
	check(q.state["gloom_stone"] == "ready", "waking it readies the quest")
	q._complete(g)
	var c := q.offer_for("mira")
	check(c.get("id", "") == "gloom_cull", "then the Gloomwood's foes")
	q._accept(c)
	for i in 8:
		var e := Enemy3D.new()
		e.kind = "thornling" if i % 2 == 0 else "wisp_caller"
		q._on_kill(e)
		e.free()
	var z := Enemy3D.new()
	z.kind = "zombie"
	q._on_kill(z)
	z.free()
	check(q.progress["gloom_cull"] == 8, "only the region's foes count")
	check(q.state["gloom_cull"] == "ready", "eight of them ready it")
	q._complete(c)
	check(q.offer_for("aldous").get("id", "") in ["warden", "frost_stone"], "Aldous takes up the next region")
	for id in ["the_frostpeaks", "the_sunscar", "the_ashlands", "the_blight"]:
		check(not main.starstones.stone(id).is_empty(), "%s has a Starstone" % id)
	main.queue_free()
	await tree.process_frame
