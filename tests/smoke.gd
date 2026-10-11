extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var packed: PackedScene = load("res://src/Main.tscn")
	if packed == null:
		push_error("Main scene failed to load")
		quit(1)
		return
	var game = packed.instantiate()
	root.add_child(game)
	await process_frame
	var errors: Array[String] = game.debug_run_checks()
	if not errors.is_empty():
		push_error("Smoke checks failed: %s" % [errors])
		quit(1)
		return
	print("PASS: 3D drag flight, triple auto-drop, evolutions, anger, banking, and lineage")
	quit(0)
