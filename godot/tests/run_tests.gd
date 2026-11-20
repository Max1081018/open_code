extends SceneTree
## Headless test runner.
##
##   godot --headless --path godot -s res://tests/run_tests.gd [-- filter]
##
## Finds every tests/test_*.gd, runs each test_* method on a fresh
## instance, and exits non-zero if anything failed.


func _initialize() -> void:
	# Autoloads attach on the first frame; give them a moment.
	await process_frame
	var filter := ""
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		filter = args[0]

	var passed := 0
	var failed := 0
	var started := Time.get_ticks_msec()

	var dir := DirAccess.open("res://tests")
	var files: Array = []
	for file in dir.get_files():
		if file.begins_with("test_") and file.ends_with(".gd") and file != "test_case.gd":
			files.append(file)
	files.sort()

	for file in files:
		var script: GDScript = load("res://tests/" + file)
		for method in script.get_script_method_list():
			var name: String = method.name
			if not name.begins_with("test_"):
				continue
			if filter != "" and not (filter in name or filter in file):
				continue
			var suite: TestCase = script.new()
			suite.current = "%s::%s" % [file.get_basename(), name]
			var result = suite.call(name)
			if result is Object and result.has_method("is_valid"):
				await result
			if suite.failures.is_empty():
				passed += 1
			else:
				failed += 1
				for failure in suite.failures:
					printerr("FAIL ", failure)

	var seconds := (Time.get_ticks_msec() - started) / 1000.0
	print("%d passed, %d failed in %.2fs" % [passed, failed, seconds])
	quit(1 if failed > 0 else 0)
