extends SceneTree
## Optional focused UI checks. Not independent QA or a human playtest.
const MainScene = preload("res://main.tscn")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, context: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("PROGRESS CLARITY FAIL: " + context)

func _key(scene, code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	scene._input(event)

func _retry_hint(scene) -> void:
	_check(scene.status.text.contains("U / Z: undo"), "completion names undo keys")
	_check(scene.status.text.contains("R: reset"), "completion names reset key")
	_check(not scene.undo_button.disabled, "undo remains available on completion")

func _unsolved_hint(scene, puzzle: int) -> void:
	_check(not scene.state.is_solved(), "undo/reset reopens puzzle")
	_check(scene.state.snapshot()["puzzle"] == puzzle, "undo/reset stays in current puzzle")
	_check(scene.status.text.begins_with("Different cells:"), "normal status returns")
	_check(not scene.status.text.contains("N: next puzzle"), "manual-next hint disappears")
	_check(not scene.status.text.contains("Both puzzles complete"), "final hint disappears")
	_check(not scene.status.text.contains("Close the window to exit"), "completion exit hint disappears")
	_check(scene.next_button.disabled, "next is disabled after undo/reset")

func _first_hint(scene) -> void:
	_check(scene.state.is_solved(), "first puzzle solved through inputs")
	_check(scene.state.snapshot()["puzzle"] == 0, "first completion does not auto-advance")
	_check(scene.status.text.contains("Next is manual"), "manual progression is explicit")
	_check(scene.status.text.contains("press N"), "next key is named")
	_check(scene.status.text.contains("click 'N: next puzzle'"), "next button is named")
	_check(scene.status.text.contains("for puzzle 2"), "destination is named")
	_check(not scene.next_button.disabled, "next is enabled at first completion")
	_retry_hint(scene)

func _final_hint(scene) -> void:
	_check(scene.state.is_solved(), "second puzzle solved through inputs")
	_check(scene.state.snapshot()["puzzle"] == 1, "second completion remains final puzzle")
	_check(scene.status.text.contains("Both puzzles complete"), "final completion is explicit")
	_check(scene.status.text.contains("No next puzzle"), "final boundary is explicit")
	_check(scene.status.text.contains("Close the window to exit"), "window-close exit is named")
	_check(scene.next_button.disabled, "next stays disabled at final completion")
	_retry_hint(scene)

func _run() -> void:
	var scene = MainScene.instantiate()
	root.add_child(scene)
	await process_frame
	_check(scene.next_button.disabled, "initial next is disabled")
	_key(scene, KEY_SPACE)
	_key(scene, KEY_E)
	_key(scene, KEY_ENTER)
	await process_frame
	_first_hint(scene)

	# Mouse undo removes the first-completion hint and locks progression.
	scene.undo_button.pressed.emit()
	_unsolved_hint(scene, 0)
	var undone: Dictionary = scene.state.snapshot()
	_key(scene, KEY_N)
	_check(scene.state.snapshot() == undone, "N cannot advance after undo")
	_key(scene, KEY_SPACE)
	_first_hint(scene)

	# Explicit mouse next enters puzzle 2; real controls solve A180 then B90.
	scene.next_button.pressed.emit()
	_unsolved_hint(scene, 1)
	_key(scene, KEY_E)
	_key(scene, KEY_E)
	scene.print_button.pressed.emit()
	scene.mask_buttons[1].pressed.emit()
	_key(scene, KEY_Q)
	_key(scene, KEY_SPACE)
	await process_frame
	_final_hint(scene)
	var completed: Dictionary = scene.state.snapshot()
	var completed_hint: String = scene.status.text
	_key(scene, KEY_N)
	_check(scene.state.snapshot() == completed, "N preserves completed final state")
	_check(scene.status.text == completed_hint, "N preserves final completion hint")
	_check(scene.next_button.disabled, "N leaves final next disabled")

	_key(scene, KEY_Z)
	_unsolved_hint(scene, 1)
	_key(scene, KEY_ENTER)
	_final_hint(scene)
	_key(scene, KEY_R)
	_unsolved_hint(scene, 1)
	_check(scene.state.snapshot()["moves"] == 0, "final reset clears print count")
	_check(scene.state.snapshot()["history_size"] == 0, "final reset clears history")
	_check(scene.undo_button.disabled, "final reset exhausts undo")

	scene.queue_free()
	await process_frame
	if failures > 0:
		printerr("PROGRESS CLARITY FAILED: %d / %d checks" % [failures, checks])
		quit(1)
		return
	print("Optional progress-clarity checks passed: %d" % checks)
	print("ITER_001_PROGRESS_CLARITY_PASS")
	quit(0)
