extends SceneTree
## Supplemental visible-popup QA; synthetic viewport input never warps the OS cursor.
const Data = preload("res://data/mech_data.gd")
var view: Control
var failures := 0
var results: Array = []
var output := ""

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("output="):
			output = argument.trim_prefix("output=")
	call_deferred("run")

func inspect(button: Button, context: String) -> void:
	var ancestor: Node = button.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			ancestor.ensure_control_visible(button)
		ancestor = ancestor.get_parent()
	await process_frame
	var before: Dictionary = view.state.snapshot()
	var event := InputEventMouseMotion.new()
	event.position = button.get_global_rect().get_center()
	event.global_position = event.position
	root.push_input(event, true)
	var popup: PopupPanel = null
	var deadline := Time.get_ticks_usec() + 3_000_000
	while popup == null and Time.get_ticks_usec() < deadline:
		await process_frame
		for child in button.get_children():
			if child is PopupPanel and child.visible:
				popup = child
	var label: Label = null
	if popup != null:
		for child in popup.get_children():
			if child is Label:
				label = child
	var ok: bool = popup != null and label != null and not button.tooltip_text.is_empty()
	if ok:
		ok = label.text == button.tooltip_text and popup.size.x > 0 and popup.size.y > 0
		ok = ok and before == view.state.snapshot()
		if popup.is_embedded():
			var rectangle := Rect2i(popup.position, popup.size)
			ok = ok and Rect2i(Vector2i(-2, -2), root.size + Vector2i(4, 4)).encloses(rectangle)
	var entry := {"context": context, "button": button.text, "disabled": button.disabled,
		"expected": button.tooltip_text, "visible_text": label.text if label != null else "", "passed": ok}
	if popup != null:
		entry["popup_position"] = str(popup.position)
		entry["popup_size"] = str(popup.size)
		entry["embedded"] = popup.is_embedded()
	results.append(entry)
	if not ok:
		failures += 1
		printerr("ERROR: visible tooltip failed: " + JSON.stringify(entry))
	elif not output.is_empty():
		await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var result := image.save_png(output.path_join("tooltip-%02d.png" % results.size()))
		if result != OK:
			failures += 1
			printerr("ERROR: tooltip screenshot could not be saved")
	# Moving within this viewport cancels the popup without moving the user's mouse.
	event = InputEventMouseMotion.new()
	event.position = Vector2(2, 2)
	event.global_position = event.position
	root.push_input(event, true)
	await process_frame

func examine(context: String) -> void:
	for button in [view.print_button, view.undo_button, view.next_button]:
		await inspect(button, context)

func display_matrix(context: String) -> void:
	for resolution in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = resolution
		root.content_scale_size = resolution
		for scale in [1.0, 1.25, 1.5]:
			view._set_font_scale(scale)
			await process_frame
			await examine("%s %s font %.2f" % [context, resolution, scale])
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	view._set_font_scale(1.0)
	await process_frame

func run() -> void:
	if DisplayServer.get_name() == "headless" or output.is_empty() or not DirAccess.dir_exists_absolute(output):
		printerr("ERROR: graphical rendering and an existing evidence directory are required")
		quit(2)
		return
	view = load("res://integrated_main.tscn").instantiate()
	view.autosave_enabled = false
	root.add_child(view)
	view._new_game()
	view.overlay.hide()
	await process_frame
	root.notify_mouse_entered()
	await display_matrix("initial")
	view._print()
	await examine("printed")
	view._reset_confirmed()
	for index in range(8):
		for action in Data.PUZZLES[index]["solution"]:
			view._select(int(int(action) / 4))
			view.state.set_rotation(int(action) % 4)
			view._print()
		if index == 0:
			await examine("solved nonfinal")
		if index < 7:
			view._next()
	await display_matrix("solved final")
	view._save_progress()
	view._undo()
	await examine("undo final")
	view._load_confirmed()
	await examine("loaded final")
	view._reset_confirmed()
	await examine("reset final")
	view.free()
	view = null
	print("TOOLTIP_VISIBLE_RESULT " + JSON.stringify({"passed": failures == 0, "checks": results.size(), "results": results}))
	quit(0 if failures == 0 else 2)
