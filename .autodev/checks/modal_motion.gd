extends SceneTree
## Trusted S07 probe: opening any campaign dialog or settings cancels print/undo
## presentation motion at once, it never resumes behind the modal, gameplay and
## save bytes are untouched, and later actions still animate (or stay immediate
## with reduced motion). Executable coverage only; not a human taste review.
var failures: Array = []
var checks := 0
const Save = preload("res://scripts/campaign_save.gd")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		printerr("MODAL MOTION FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func boards(main) -> Array:
	return [main.before_view, main.after_view, main.target_view, main.stamp_mask_view]

func neutral(main) -> bool:
	var ok: bool = main.stamp_view.scale == Vector2.ONE and is_zero_approx(main.stamp_view.rotation) \
		and main.stamp_view.modulate == Color.WHITE and main.reaction_time == 0.0 and not main.is_processing()
	for view in boards(main):
		ok = ok and view.impression_time == 0.0 and view.success_time == 0.0 and view.feedback_time == 0.0
	return ok

func animate(main) -> void:
	# Alternate print/undo on the first puzzle; neither action solves it.
	if int(main.session.snapshot()["history_size"]) == 0:
		main.puzzle_view._print()
	else:
		main.puzzle_view._undo()

func save_bytes() -> PackedByteArray:
	return FileAccess.get_file_as_bytes(Save.SAVE_PATH) if FileAccess.file_exists(Save.SAVE_PATH) else PackedByteArray()

func run() -> void:
	var main = load("res://campaign_main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.start_new()
	main.dismiss_story()
	main.settings["reduce_motion"] = false
	await process_frame
	var openers := {
		"pause": Callable(main, "_open_pause"), "help": Callable(main, "_open_help"),
		"settings": Callable(main, "_open_settings"), "journal": Callable(main, "_open_journal"),
		"story": Callable(main, "_open_story"), "reset": Callable(main, "_ask_reset"),
		"order": Callable(main, "_open_order"), "hint": Callable(main, "_open_hint")}
	for name in openers:
		main.dismiss_story()
		animate(main)
		check(main.is_processing() and main.before_view.impression_time > 0.0, name + ": action motion active before modal")
		var progress: Dictionary = main.session.export_progress().duplicate(true)
		var hints: Array = main.hint_levels.duplicate()
		var bytes := save_bytes()
		openers[name].call()
		check(main.overlay.visible, name + ": modal visible")
		check(neutral(main), name + ": stamp pose and every reaction/impression/success clock reset immediately")
		for i in range(20):
			await process_frame
		check(neutral(main), name + ": motion does not resume behind the modal")
		if not name in ["order", "hint"]:
			# Reading an order marks it read and a hint spends its slot by design.
			check(main.session.export_progress() == progress and main.hint_levels == hints, name + ": gameplay state unchanged")
			check(save_bytes() == bytes, name + ": progress save bytes unchanged")
		main.dismiss_story()
		for i in range(5):
			await process_frame
		check(neutral(main), name + ": closing the modal does not restart motion")
	main.dismiss_story()
	animate(main)
	check(main.is_processing() and main.before_view.impression_time > 0.0, "normal actions still animate after modals")
	for i in range(30):
		await process_frame
	main.settings["reduce_motion"] = true
	animate(main)
	check(neutral(main), "reduced motion stays immediate")
	main.free()
	print("MODAL_MOTION_RESULT " + JSON.stringify({"checks": checks, "failures": failures}))
	if failures.is_empty():
		print("MODAL_MOTION_PASS")
	quit(0 if failures.is_empty() else 2)
