extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var packed:PackedScene=load("res://src/Main.tscn")
	var first=packed.instantiate()
	root.add_child(first)
	await process_frame
	first.save_data.total_score=4321
	first.save_data.best=700
	first.save_game()
	first.queue_free()
	await process_frame

	var second=packed.instantiate()
	root.add_child(second)
	await process_frame
	if int(second.save_data.total_score)!=4321:
		push_error("Cumulative score did not survive reload")
		quit(1)
		return
	second.start_sortie()
	second.score=600
	second.finish_sortie(true)
	if int(second.save_data.total_score)!=4921:
		push_error("Successful sortie was not banked")
		quit(1)
		return
	second.start_sortie()
	second.score=333
	second.finish_sortie(false)
	if int(second.save_data.total_score)!=4921:
		push_error("Failed sortie changed cumulative score")
		quit(1)
		return
	second.queue_free()
	await process_frame

	var third=packed.instantiate()
	root.add_child(third)
	await process_frame
	if int(third.save_data.total_score)!=4921:
		push_error("Banked cumulative score did not survive second reload")
		quit(1)
		return
	print("PASS: cumulative score survives success, retry, failure, and reload")
	quit(0)
