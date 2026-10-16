extends SceneTree
const Scene = preload("res://integrated_main.tscn")
const Data = preload("res://data/mech_data.gd")
var failures := 0
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("TOOLTIP FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func examine(view, context: String) -> void:
	for button in [view.print_button, view.undo_button, view.next_button]:
		check(not button.tooltip_text.is_empty(), context + " tooltip nonempty")
	check(view.print_button.text == "SPACE · 인쇄", context + " print label unchanged")
	check(view.undo_button.text == "U / Z · 되돌리기", context + " undo label unchanged")
	check(view.next_button.text == "N · 다음 퍼즐", context + " next label unchanged")
	var before: Dictionary = view.state.snapshot()
	for button in [view.print_button, view.undo_button, view.next_button]:
		var event := InputEventMouseMotion.new()
		event.position = button.get_global_rect().get_center()
		Input.parse_input_event(event)
		await process_frame
	check(before == view.state.snapshot(), context + " hover preserves state")

func run() -> void:
	var view = Scene.instantiate()
	view.autosave_enabled = false
	root.add_child(view)
	await process_frame
	view._new_game()
	view.overlay.hide()
	await examine(view, "initial")
	var initial: Array = [view.print_button.tooltip_text, view.undo_button.tooltip_text, view.next_button.tooltip_text]
	view._print()
	await examine(view, "printed")
	check(view.undo_button.tooltip_text != initial[1], "undo explains changed availability")
	view._reset_confirmed()
	check(view.undo_button.tooltip_text == initial[1], "reset restores undo explanation")
	for index in range(8):
		for action in Data.PUZZLES[index]["solution"]:
			view._select(int(int(action) / 4))
			view.state.set_rotation(int(action) % 4)
			view._print()
		await examine(view, "solved %d" % index)
		check(view.print_button.tooltip_text != initial[0], "solved print explanation")
		var solved_tooltips: Array = [view.print_button.tooltip_text, view.undo_button.tooltip_text, view.next_button.tooltip_text]
		if index == 7:
			check(view.next_button.tooltip_text.contains("마지막") or view.next_button.tooltip_text.contains("모두"), "final next explanation")
		else:
			check(view.next_button.tooltip_text.contains("N"), "manual next shortcut explained")
		check(view._save_progress(), "save solved state")
		view._undo()
		await examine(view, "undo solution %d" % index)
		check(view.print_button.tooltip_text == initial[0], "undo restores unsolved print explanation")
		view._load_confirmed()
		check(view.print_button.tooltip_text == solved_tooltips[0], "load refreshes print tooltip")
		check(view.undo_button.tooltip_text == solved_tooltips[1], "load refreshes undo tooltip")
		check(view.next_button.tooltip_text == solved_tooltips[2], "load refreshes next tooltip")
		if index < 7:
			view._next()
	view.queue_free()
	for i in range(8):
		await process_frame
	if failures == 0:
		print("TOOLTIP_ACCEPTANCE_PASS checks=%d" % checks)
		quit(0)
	else:
		printerr("TOOLTIP_ACCEPTANCE_FAIL failures=%d checks=%d" % [failures, checks])
		quit(1)
